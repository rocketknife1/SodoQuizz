"""Pune / scoate mesajul de intretinere din Firebase Remote Config.

Cand `mesaj_intretinere` are text, TOTI jucatorii vad ecranul "Revenim
imediat" peste joc (vezi lib/widgets/remote_gate.dart) pana cand mesajul e
sters. Aplicatia il ia in cel mult ~1h (minimumFetchInterval), sau imediat
la urmatoarea pornire.

Ruleaza (din radacina proiectului):
    python tools/maintenance.py                       # arata starea curenta
    python tools/maintenance.py --pune "Text mesaj"   # aprinde intretinerea
    python tools/maintenance.py --scoate              # o stinge

Cheia: tools/service-account.json (aceeasi ca la celelalte scripturi).
"""

import io
import json
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

PROJECT_ID = "sodoquizz"
KEY_PATH = os.path.join("tools", "service-account.json")
RC_URL = f"https://firebaseremoteconfig.googleapis.com/v1/projects/{PROJECT_ID}/remoteConfig"
KEY = "mesaj_intretinere"
SCOPES = [
    "https://www.googleapis.com/auth/firebase.remoteconfig",
    "https://www.googleapis.com/auth/cloud-platform",
]


def _session():
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
    except ImportError:
        raise SystemExit("Lipseste o librarie. Ruleaza:  pip install google-auth requests")
    if not os.path.exists(KEY_PATH):
        raise SystemExit(
            f"Lipseste {KEY_PATH}. Firebase Console -> Project settings ->\n"
            "Service accounts -> Generate new private key -> salveaza-l acolo."
        )
    creds = service_account.Credentials.from_service_account_file(KEY_PATH, scopes=SCOPES)
    return AuthorizedSession(creds)


def _get(session):
    r = session.get(RC_URL, timeout=30)
    if r.status_code != 200:
        raise SystemExit(f"Nu s-a putut citi Remote Config: {r.status_code}\n{r.text[:400]}")
    return r.json(), r.headers.get("ETag", "*")


def _put(session, template, etag):
    r = session.put(
        RC_URL,
        headers={"Content-Type": "application/json; UTF-8", "If-Match": etag},
        data=json.dumps(template, ensure_ascii=False).encode("utf-8"),
        timeout=30,
    )
    if r.status_code != 200:
        raise SystemExit(f"Nu s-a putut scrie Remote Config: {r.status_code}\n{r.text[:400]}")


def _current(template):
    return (
        template.get("parameters", {})
        .get(KEY, {})
        .get("defaultValue", {})
        .get("value", "")
    )


def main():
    s = _session()
    template, etag = _get(s)
    now = _current(template).strip()

    if "--scoate" in sys.argv:
        if not now:
            print("Intretinerea e deja stinsa. N-am schimbat nimic.")
            return
        template.setdefault("parameters", {}).setdefault(KEY, {}).setdefault(
            "defaultValue", {}
        )["value"] = ""
        _put(s, template, etag)
        print("✓ Intretinere STINSA. Jocul revine pentru toata lumea.")
        print("  Aplicatiile deschise o vad in cel mult ~1h sau la repornire.")
        return

    if "--pune" in sys.argv:
        i = sys.argv.index("--pune")
        msg = " ".join(sys.argv[i + 1:]).strip()
        if not msg:
            raise SystemExit('Da si textul:  python tools/maintenance.py --pune "Revenim in 30 min"')
        template.setdefault("parameters", {}).setdefault(KEY, {})
        template["parameters"][KEY].setdefault("defaultValue", {})["value"] = msg
        template["parameters"][KEY].setdefault(
            "description", "Ne-gol => ecranul 'Revenim imediat' peste joc, pentru toti."
        )
        _put(s, template, etag)
        print(f"✓ Intretinere APRINSA cu mesajul:\n    „{msg}”")
        print("  Toti jucatorii vad ecranul 'Revenim imediat' in cel mult ~1h")
        print("  (sau imediat la repornirea aplicatiei).")
        print("  Cand termini:  python tools/maintenance.py --scoate")
        return

    # fara argumente: doar starea
    if now:
        print(f"INTRETINEREA E APRINSA. Mesaj:\n    „{now}”")
        print("\n  Ca s-o stingi:  python tools/maintenance.py --scoate")
    else:
        print("Intretinerea e stinsa. Jocul merge normal pentru toata lumea.")
        print('\n  Ca s-o aprinzi:  python tools/maintenance.py --pune "Text mesaj"')


if __name__ == "__main__":
    main()
