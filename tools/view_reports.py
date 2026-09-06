"""Descarca TOATE rapoartele jucatorilor din Firestore si le scrie lizibil.

Trei feluri de rapoarte, toate ajung aici:

  1. bug_reports      — butonul "Trimite raportul" din joc. Raportul il compune
                        SISTEMUL (ecran, eroare, stiva, firimituri), jucatorul
                        doar apasa. Astea sunt pentru "mi-a picat / s-a blocat".
  2. question_reports — "intrebarea asta e gresita" (raspuns/imagine/typo).
  3. reports          — un jucator raporteaza alt jucator (limbaj, comportament).

Ruleaza (din radacina proiectului):
    python tools/view_reports.py            # toate, si nerezolvate si rezolvate
    python tools/view_reports.py --noi      # doar cele cu handled/rezolvat = false

Scrie si un fisier in `rapoarte/` (gitignored) ca sa ramana pentru cand ii
ceri lui Claude sa repare ceva — el il citeste de acolo.

Cheia: `tools/service-account.json` (aceeasi ca la celelalte scripturi).
"""

import datetime
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

PROJECT_ID = "sodoquizz"
KEY_PATH = os.path.join("tools", "service-account.json")
FIRESTORE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
SCOPES = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/datastore",
]


def _session():
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
    except ImportError:
        raise SystemExit("Lipseste o librarie. Ruleaza:  pip install google-auth requests")
    if not os.path.exists(KEY_PATH):
        raise SystemExit(
            f"Lipseste {KEY_PATH}.\n"
            "Firebase Console -> Project settings -> Service accounts -> Generate new private key\n"
            "-> salveaza fisierul acolo. E in .gitignore, nu-l trimite nimanui."
        )
    creds = service_account.Credentials.from_service_account_file(KEY_PATH, scopes=SCOPES)
    return AuthorizedSession(creds)


def _val(field):
    """Scoate valoarea dintr-un camp Firestore REST ({stringValue: ...} etc)."""
    if not isinstance(field, dict):
        return field
    for k in ("stringValue", "booleanValue", "integerValue", "doubleValue", "timestampValue"):
        if k in field:
            return field[k]
    if "nullValue" in field:
        return None
    if "mapValue" in field:
        return {k: _val(v) for k, v in field["mapValue"].get("fields", {}).items()}
    if "arrayValue" in field:
        return [_val(v) for v in field["arrayValue"].get("values", [])]
    return field


def _fetch(session, collection):
    docs, token = [], None
    while True:
        params = {"pageSize": 300}
        if token:
            params["pageToken"] = token
        r = session.get(f"{FIRESTORE}/{collection}", params=params, timeout=90)
        if r.status_code != 200:
            print(f"  ! nu s-a putut citi `{collection}`: {r.status_code} {r.text[:200]}")
            return docs
        body = r.json()
        for d in body.get("documents", []):
            fields = {k: _val(v) for k, v in d.get("fields", {}).items()}
            fields["_id"] = d["name"].split("/")[-1]
            docs.append(fields)
        token = body.get("nextPageToken")
        if not token:
            return docs


def _ts_key(d):
    return d.get("trimisLa") or d.get("createdAt") or ""


def _emit(out, text=""):
    print(text)
    out.write(text + "\n")


def main():
    only_new = "--noi" in sys.argv
    s = _session()

    os.makedirs("rapoarte", exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    path = os.path.join("rapoarte", f"rapoarte_{stamp}.md")
    latest = os.path.join("rapoarte", "ULTIMUL.md")

    with io.open(path, "w", encoding="utf-8") as out:
        _emit(out, f"# Rapoarte jucatori — {datetime.datetime.now():%Y-%m-%d %H:%M}")
        _emit(out, "(doar nerezolvate)" if only_new else "(toate)")

        # ── 1. bug_reports ────────────────────────────────────────────────
        bugs = _fetch(s, "bug_reports")
        if only_new:
            bugs = [b for b in bugs if not b.get("rezolvat")]
        bugs.sort(key=_ts_key, reverse=True)
        _emit(out, f"\n## 🐞 Blocaje / crash-uri (`bug_reports`) — {len(bugs)}")
        for b in bugs:
            _emit(out, f"\n### {b.get('trimisLa', '?')}  ·  {b.get('platforma', '?')}  ·  v{b.get('versiune', '?')}")
            _emit(out, f"- uid: `{b.get('uid', '?')}`")
            _emit(out, f"- ecran: **{b.get('ecran', '?')}**")
            if b.get("eroare"):
                _emit(out, f"- eroare: `{b['eroare']}`")
            if b.get("stiva"):
                _emit(out, "- stiva:\n  ```\n  " + str(b["stiva"]).replace("\n", "\n  ") + "\n  ```")
            if b.get("firimituri"):
                _emit(out, f"- firimituri: {b['firimituri']}")
            _emit(out, f"- rezolvat: {b.get('rezolvat', False)}")

        # ── 2. question_reports ──────────────────────────────────────────
        qs = _fetch(s, "question_reports")
        if only_new:
            qs = [q for q in qs if not q.get("handled")]
        qs.sort(key=_ts_key, reverse=True)
        _emit(out, f"\n## ❓ Intrebari gresite (`question_reports`) — {len(qs)}")
        for q in qs:
            _emit(out, f"\n- **[{q.get('category', '?')}]** {q.get('questionText', '?')}")
            _emit(out, f"  - motiv: {q.get('reason', '?')}  ·  id: `{q.get('questionId', '?')}`  ·  {q.get('createdAt', '?')}")
            _emit(out, f"  - rezolvat: {q.get('handled', False)}")

        # ── 3. reports (jucator -> jucator) ──────────────────────────────
        rs = _fetch(s, "reports")
        if only_new:
            rs = [r for r in rs if not r.get("handled")]
        rs.sort(key=_ts_key, reverse=True)
        _emit(out, f"\n## 🚩 Jucator raporteaza jucator (`reports`) — {len(rs)}")
        for r in rs:
            _emit(out, f"\n- {r.get('reporterName', '?')} → **{r.get('targetName', '?')}**  ({r.get('reason', '?')})")
            if r.get("messageText"):
                _emit(out, f"  - mesaj citat: „{r['messageText']}”")
            if r.get("context"):
                _emit(out, f"  - context: {r['context']}")
            _emit(out, f"  - reporter `{r.get('reporterUid', '?')}` → target `{r.get('targetUid', '?')}`  ·  {r.get('createdAt', '?')}")
            _emit(out, f"  - rezolvat: {r.get('handled', False)}")

        total = len(bugs) + len(qs) + len(rs)
        _emit(out, f"\n---\n**{total} rapoarte** in total.")

    # copie "ULTIMUL.md" ca sa fie mereu acelasi nume de citit
    with io.open(path, "r", encoding="utf-8") as src, io.open(latest, "w", encoding="utf-8") as dst:
        dst.write(src.read())

    print(f"\n→ salvat in {path}  (si {latest})")
    print("  Cand vrei sa repar ceva dintr-un raport, spune-mi si citesc rapoarte/ULTIMUL.md")


if __name__ == "__main__":
    main()
