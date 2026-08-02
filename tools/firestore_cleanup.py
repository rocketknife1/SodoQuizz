"""Sterge din Firestore documentele ramase orfane dupa ce contul lor a
disparut din Firebase Authentication.

DE CE E NEVOIE: stergerea unui cont din consola Firebase Auth NU atinge
Firestore. Aplicatia curata corect dupa ea insasi cand userul apasa "Sterge
contul" in joc (vezi AuthService.deleteAccount), dar nimic din client nu poate
reactiona la o stergere facuta manual din consola — un client nici macar nu
poate citi lista de conturi din Auth. Asa raman documente fantoma in
`player_profiles` (vizibile in leaderboard) si in `users` (cloud-save).

CUM FUNCTIONEAZA, fara Cloud Functions si fara service account:
 1. `firebase auth:export` da lista de UID-uri care CHIAR exista in Auth
    (foloseste login-ul tau din CLI);
 2. `player_profiles` se listeaza prin API-ul REST Firestore, autentificat cu
    un cont anonim temporar (regulile permit citirea profilurilor publice
    oricui e autentificat). Contul temporar se sterge singur la final;
 3. ce e in Firestore dar nu in Auth = orfan, se sterge cu
    `firebase firestore:delete` (care ruleaza cu drepturi de admin, deci
    trece peste reguli).

RULARE (din radacina proiectului):
    python tools/firestore_cleanup.py            # doar raporteaza, nu sterge
    python tools/firestore_cleanup.py --sterge   # sterge efectiv

LIMITARE cunoscuta: colectia `users` nu poate fi LISTATA (regulile o tin
strict privata, fiecare user isi vede doar propriul document, si asa trebuie
sa ramana). Scriptul incearca totusi sa stearga `users/{uid}` pentru fiecare
orfan gasit in `player_profiles`, ceea ce acopera cazul normal — un cont are
mereu si profil public, si cloud-save.
"""
import io
import json
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import os

# Numele jucatorilor contin diacritice, iar consola Windows e pe cp1252 —
# fara asta, un simplu print crapa scriptul la jumatate.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

PROJECT_ID = "sodoquizz"
# Cheia web publica din lib/firebase_options.dart — e menita sa fie publica
# (nu da niciun drept peste ce permit regulile), de-aia poate sta aici.
WEB_API_KEY = "AIzaSyAG1yZlVrHq1bFFT-HTJbvSjJC0sGUPnfU"

IDENTITY = "https://identitytoolkit.googleapis.com/v1"
FIRESTORE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"


def _post(url: str, payload: dict) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def _get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def _firebase(*args: str, attempts: int = 3) -> subprocess.CompletedProcess:
    """firebase CLI, cu reincercare pe crash-ul intermitent de libuv.

    Pe Windows, firebase-tools pica din cand in cand cu
    "Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)" — un bug in
    runtime-ul Node, nu in comanda ceruta. Aceeasi comanda reusita la a doua
    incercare, deci o reluam in loc sa raportam un esec fals.
    """
    res = None
    for i in range(attempts):
        res = subprocess.run(
            ["firebase", *args, "--project", PROJECT_ID],
            capture_output=True, text=True, shell=True,
        )
        if res.returncode == 0:
            return res
        if "UV_HANDLE_CLOSING" not in (res.stderr or "") + (res.stdout or ""):
            return res
        if i < attempts - 1:
            time.sleep(2)
    return res


def auth_uids() -> set[str]:
    """UID-urile care exista chiar acum in Firebase Authentication."""
    path = os.path.join(tempfile.gettempdir(), "sodoquizz_auth_export.json")
    res = _firebase("auth:export", path, "--format=json")
    if res.returncode != 0:
        raise SystemExit(f"firebase auth:export a esuat:\n{res.stderr or res.stdout}")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    os.remove(path)
    return {u["localId"] for u in data.get("users", [])}


def profile_ids(token: str) -> list[str]:
    """Id-urile documentelor din player_profiles (paginat)."""
    ids, page = [], None
    while True:
        url = f"{FIRESTORE}/player_profiles?pageSize=300&mask.fieldPaths=name"
        if page:
            url += f"&pageToken={page}"
        data = _get(url, token)
        for doc in data.get("documents", []):
            ids.append(doc["name"].rsplit("/", 1)[-1])
        page = data.get("nextPageToken")
        if not page:
            return ids


def main() -> int:
    apply = "--sterge" in sys.argv

    print("1/3  citesc conturile din Firebase Authentication...")
    live = auth_uids()
    print(f"     {len(live)} cont(uri) active")

    print("2/3  citesc profilurile din Firestore...")
    session = _post(f"{IDENTITY}/accounts:signUp?key={WEB_API_KEY}", {"returnSecureToken": True})
    token, temp_uid = session["idToken"], session["localId"]
    try:
        profiles = profile_ids(token)
    finally:
        # contul temporar nu trebuie sa ramana in urma noastra
        try:
            _post(f"{IDENTITY}/accounts:delete?key={WEB_API_KEY}", {"idToken": token})
        except urllib.error.URLError as exc:
            print(f"     ATENTIE: contul temporar {temp_uid} n-a putut fi sters: {exc}")
    # contul temporar apare in lista de profiluri doar daca a apucat sa scrie
    # un heartbeat, ceea ce nu face — dar il excludem oricum, din prudenta.
    profiles = [p for p in profiles if p != temp_uid]
    print(f"     {len(profiles)} profil(uri)")

    orphans = sorted(set(profiles) - live)
    print(f"3/3  {len(orphans)} orfan(i) (in Firestore, dar fara cont in Auth)")
    if not orphans:
        print("\nNimic de curatat.")
        return 0
    for uid in orphans:
        print(f"     - {uid}")

    if not apply:
        print("\nRulare de proba. Ruleaza din nou cu --sterge ca sa le stergi efectiv.")
        return 0

    print("\nSterg...")
    failed = 0
    for uid in orphans:
        for path in (f"player_profiles/{uid}", f"users/{uid}"):
            res = _firebase("firestore:delete", path, "--force", "--recursive")
            if res.returncode == 0:
                print(f"     [OK]  {path}")
            else:
                failed += 1
                print(f"     [EROARE] {path}: {(res.stderr or res.stdout).strip()[:120]}")
    print(f"\nGata. {len(orphans)} orfan(i) procesat(i)" + (f", {failed} erori." if failed else ", fara erori."))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
