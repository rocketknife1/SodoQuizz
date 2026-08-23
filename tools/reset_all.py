"""Reset complet: goleste Firestore SI sterge toate conturile din Authentication.

CE FACE: aduce proiectul in starea "n-a jucat nimeni niciodata". Sterge toate
documentele din toate colectiile (inclusiv subcolectiile de prieteni si
cereri, si subcolectiile players/chat ale meciurilor in desfasurare) si apoi
toate conturile din Firebase Authentication, inclusiv al tau.

CE NU FACE, si e important de stiut:
  - NU atinge progresul de pe telefoane. Fiecare telefon isi tine progresul
    local (SharedPreferences). Daca te reloghezi dupa reset, aplicatia vede
    ca nu exista nimic in cloud si URCA INAPOI ce are telefonul, recreand
    users/{uid} si player_profiles/{uid}. Reset "definitiv" inseamna si
    stergerea datelor aplicatiei de pe telefon.
  - NU atinge AdMob. E un produs separat, cu consola separata.
  - NU iti pierzi drepturile de admin. Regula din firestore.rules verifica
    EMAILUL, nu uid-ul (vezi lib/core/admin.dart), deci dupa relogare
    primesti un uid nou si ramai admin.

RULARE (din radacina proiectului):
    python tools/reset_all.py            # doar raporteaza, nu sterge
    python tools/reset_all.py --sterge   # sterge efectiv
    python tools/reset_all.py --sterge --doar-firestore   # lasa conturile

Are nevoie de tools/service-account.json (vezi tools/purge_accounts.py).
"""
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

PROJECT_ID = "sodoquizz"
KEY_PATH = os.path.join("tools", "service-account.json")
SCOPES = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/datastore",
    "https://www.googleapis.com/auth/firebase",
]
FIRESTORE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
IDENTITY = f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT_ID}"

# Colectiile de nivel 1. Subcolectiile se descopera automat pentru fiecare
# document, deci nu trebuie enumerate aici.
COLLECTIONS = [
    "player_profiles",
    "users",
    "completed_matches",
    "multiplayer_activity",
    "multiplayer_presence",
    "matches",
    "matchmaking_queue",
    "quickmatch_offers",
    "rematch_offers",
    "friend_chats",
    "reports",
    "question_reports",
    "admin_grants",
    "banned_players",
    "pending_auth_deletions",
]

# ATENTIE LA ORICE FEATURE NOU CARE SCRIE O COLECTIE NOUA: lista de mai sus e
# scrisa de mana si nu se auto-descopera (Firestore nu are "listeaza toate
# colectiile" fara Admin SDK pe radacina). Cele patru de mai jos au fost
# adaugate pe 13 august 2026, cand s-a observat ca scriptul lasa in urma exact
# datele adaugate dupa ce a fost scris: prezenta din multiplayer, ofertele de
# revansa, conversatiile private dintre prieteni si raportarile de moderare.
# Un reset care spune "gol" si nu e chiar gol e mai rau decat unul care crapa.
# Verificare rapida a listei:
#   grep -rho "_db.collection('[a-z_]*')" lib/ | sort -u


def session():
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
    except ImportError:
        print("Lipseste o librarie. Ruleaza:  pip install google-auth requests")
        sys.exit(1)
    if not os.path.exists(KEY_PATH):
        print(f"Lipseste {KEY_PATH} — vezi tools/purge_accounts.py pentru cum se genereaza.")
        sys.exit(1)
    creds = service_account.Credentials.from_service_account_file(KEY_PATH, scopes=SCOPES)
    return AuthorizedSession(creds)


def list_docs(s, path):
    """Toate documentele dintr-o colectie, paginat complet."""
    docs, token = [], None
    while True:
        params = {"pageSize": 300}
        if token:
            params["pageToken"] = token
        r = s.get(f"{FIRESTORE}/{path}", params=params, timeout=90)
        if r.status_code != 200:
            return docs
        body = r.json()
        docs.extend(body.get("documents", []))
        token = body.get("nextPageToken")
        if not token:
            return docs


def sub_collections(s, doc_name):
    """Id-urile subcolectiilor unui document (ex. friends, friend_requests)."""
    r = s.post(f"https://firestore.googleapis.com/v1/{doc_name}:listCollectionIds",
               json={"pageSize": 100}, timeout=90)
    if r.status_code != 200:
        return []
    return r.json().get("collectionIds", [])


def collect_targets(s):
    """Toate documentele de sters, subcolectiile inaintea parintilor."""
    targets = []
    per_collection = {}
    for coll in COLLECTIONS:
        docs = list_docs(s, coll)
        per_collection[coll] = len(docs)
        for d in docs:
            for sub in sub_collections(s, d["name"]):
                rel = d["name"].split("/documents/")[1]
                for sd in list_docs(s, f"{rel}/{sub}"):
                    targets.append(sd["name"])
                    per_collection[f"{coll}/*/{sub}"] = per_collection.get(f"{coll}/*/{sub}", 0) + 1
            targets.append(d["name"])
    return targets, per_collection


def list_accounts(s):
    accounts, token = [], None
    while True:
        payload = {"maxResults": 500}
        if token:
            payload["nextPageToken"] = token
        r = s.post(f"{IDENTITY}/accounts:batchGet", json=payload, timeout=90)
        if r.status_code != 200:
            r = s.get(f"{IDENTITY}/accounts:batchGet", params=payload, timeout=90)
            if r.status_code != 200:
                return accounts
        body = r.json()
        accounts.extend(body.get("users", []))
        token = body.get("nextPageToken")
        if not token:
            return accounts


def main():
    apply = "--sterge" in sys.argv
    # Golirea Firestore fara sa se atinga conturile: dupa reset fiecare
    # jucator se reconecteaza cu acelasi uid si isi reurca progresul de pe
    # telefon, in loc sa primeasca un cont nou.
    doar_firestore = "--doar-firestore" in sys.argv
    s = session()

    print("=" * 64)
    print("  RESET COMPLET" + ("" if apply else "  (rulare de proba)"))
    print("=" * 64)

    targets, per_collection = collect_targets(s)
    accounts = [] if doar_firestore else list_accounts(s)

    print("\n--- Firestore ---")
    if not per_collection or not any(per_collection.values()):
        print("  gol deja")
    for name, n in sorted(per_collection.items()):
        if n:
            print(f"  {name:<34} {n} doc")
    print(f"\n  TOTAL de sters: {len(targets)} documente")

    print("\n--- Authentication ---")
    if doar_firestore:
        print("  neatins (--doar-firestore)")
    elif not accounts:
        print("  niciun cont")
    else:
        for a in accounts:
            who = a.get("email") or ("anonim" if not a.get("providerUserInfo") else "?")
            print(f"  {a['localId']}  {who}")
        print(f"\n  TOTAL de sters: {len(accounts)} conturi")

    if not apply:
        print("\nRulare de proba. Nimic nu a fost sters.")
        print("Ruleaza din nou cu --sterge ca sa aplici.")
        return

    print("\nSterg documentele...")
    failed = 0
    for name in targets:
        r = s.delete(f"https://firestore.googleapis.com/v1/{name}", timeout=90)
        if r.status_code not in (200, 204):
            failed += 1
            print(f"  ESUAT {name.split('/documents/')[-1]}: HTTP {r.status_code}")
    print(f"  {len(targets) - failed}/{len(targets)} documente sterse")

    afailed = 0
    if not doar_firestore:
        print("\nSterg conturile...")
        for a in accounts:
            r = s.post(f"{IDENTITY}/accounts:delete", json={"localId": a["localId"]}, timeout=90)
            if r.status_code != 200:
                afailed += 1
                print(f"  ESUAT {a['localId']}: HTTP {r.status_code} {r.text[:120]}")
        print(f"  {len(accounts) - afailed}/{len(accounts)} conturi sterse")

    print("\n" + "=" * 64)
    if failed or afailed:
        print("  Gata, dar cu erori — vezi mai sus.")
    else:
        print("  Gata. Firestore gol"
              + (", Authentication neatins." if doar_firestore else ", Authentication gol."))
    print("=" * 64)


if __name__ == "__main__":
    main()
