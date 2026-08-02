"""Sterge din Firebase Authentication conturile puse la coada de admin.

CE REZOLVA: butonul "Sterge complet" din AdminScreen sterge instant tot ce
tine de un jucator din Firestore (profil, prieteni, cereri, salvarea din
cloud, grant-uri), dar NU poate sterge si contul din Authentication — un
client n-are voie sa stearga contul altcuiva, operatia cere Admin SDK, iar
proiectul e pe planul gratuit, fara Cloud Functions. Aplicatia noteaza deci
uid-ul in colectia `pending_auth_deletions`, iar scriptul asta termina treaba.

Pana la rulare, contul ramas in Auth e inert: nu mai are nicio data legata de
el si nu apare nicaieri in joc.

CE ITI TREBUIE, o singura data: o cheie de cont de serviciu.
  Firebase Console -> ⚙ Project settings -> Service accounts
  -> "Generate new private key" -> salvezi fisierul ca:

      tools/service-account.json

  Fisierul e deja in .gitignore — NU-l comite si nu-l trimite nimanui, e
  echivalentul unei parole de administrator peste tot proiectul.

RULARE (din radacina proiectului):
    python tools/purge_accounts.py            # doar raporteaza, nu sterge
    python tools/purge_accounts.py --sterge   # sterge efectiv

Vezi si tools/firestore_cleanup.py, care rezolva problema inversa: documente
ramase in Firestore dupa conturi sterse manual din consola Auth.
"""
import io
import json
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

QUEUE = "pending_auth_deletions"


def _session():
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
    except ImportError:
        raise SystemExit(
            "Lipsesc bibliotecile necesare. Ruleaza:\n"
            "    python -m pip install google-auth requests"
        )
    if not os.path.exists(KEY_PATH):
        raise SystemExit(
            f"Nu gasesc {KEY_PATH}.\n\n"
            "Descarca cheia o singura data:\n"
            "  Firebase Console -> Project settings -> Service accounts\n"
            "  -> Generate new private key -> salveaza fisierul acolo.\n\n"
            "Fara ea nu se pot sterge conturi din Authentication — vezi\n"
            "comentariul din capul acestui fisier pentru de ce."
        )
    creds = service_account.Credentials.from_service_account_file(KEY_PATH, scopes=SCOPES)
    return AuthorizedSession(creds)


def queued(session) -> list[tuple[str, str]]:
    """(uid, nume) pentru fiecare cont pus la coada."""
    out, page = [], None
    while True:
        url = f"{FIRESTORE}/{QUEUE}?pageSize=300"
        if page:
            url += f"&pageToken={page}"
        r = session.get(url, timeout=30)
        r.raise_for_status()
        data = r.json()
        for doc in data.get("documents", []):
            uid = doc["name"].rsplit("/", 1)[-1]
            name = doc.get("fields", {}).get("name", {}).get("stringValue", "?")
            out.append((uid, name))
        page = data.get("nextPageToken")
        if not page:
            return out


def delete_auth_user(session, uid: str) -> tuple[bool, str]:
    """Sterge contul din Authentication. Un cont deja inexistent NU e o
    eroare — inseamna doar ca a fost sters intre timp din consola."""
    r = session.post(f"{IDENTITY}/accounts:delete", json={"localId": uid}, timeout=30)
    if r.status_code == 200:
        return True, ""
    body = r.text[:200]
    if "USER_NOT_FOUND" in body:
        return True, "(nu mai exista in Auth)"
    return False, body


def main() -> int:
    apply = "--sterge" in sys.argv
    session = _session()

    items = queued(session)
    print(f"{len(items)} cont(uri) la coada pentru stergere din Authentication")
    if not items:
        print("\nNimic de facut.")
        return 0
    for uid, name in items:
        print(f"     - {name}  ({uid})")

    if not apply:
        print("\nRulare de proba. Ruleaza din nou cu --sterge ca sa le stergi efectiv.")
        return 0

    print("\nSterg...")
    failed = 0
    for uid, name in items:
        ok, note = delete_auth_user(session, uid)
        if not ok:
            failed += 1
            print(f"     [EROARE] {name} ({uid}): {note}")
            continue
        # scoatem din coada doar daca stergerea chiar a reusit, ca o eroare
        # trecatoare sa poata fi reincercata la urmatoarea rulare
        d = session.delete(f"{FIRESTORE}/{QUEUE}/{uid}", timeout=30)
        if d.status_code not in (200, 204):
            failed += 1
            print(f"     [EROARE] {name}: contul s-a sters, dar coada nu: {d.text[:120]}")
        else:
            print(f"     [OK] {name} {note}".rstrip())

    print(f"\nGata." + (f" {failed} erori." if failed else " Fara erori."))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
