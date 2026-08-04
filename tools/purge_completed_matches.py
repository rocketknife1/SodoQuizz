"""Sterge din Firestore jurnalul meciurilor multiplayer incheiate.

CE E COLECTIA `completed_matches`: un document per meci terminat normal, cu
cel putin 2 jucatori reali (vezi PlayerProfileService.recordCompletedMatch).
Nu tine progresul nimanui si nu e citita de joc — exista dintr-un singur
motiv: sa se stie CATE meciuri s-au jucat in total, pentru tab-ul Statistici
din AdminScreen, care face un .count() agregat pe server.

⚠️ DECI: cand golesti colectia asta, contorul "meciuri jucate" din admin
pica la zero. Nimic altceva nu se schimba — jucatorii, monedele, clasamentul
si statisticile personale (matchesPlayed/wins/losses din player_profiles)
sunt in ALTA parte si raman neatinse. Exact ce vrei ca sa arunci meciurile de
test dinainte de lansare; de evitat dupa, daca tii la cifra totala.

De ce un script pe PC si nu un buton in aplicatie: acelasi motiv ca la
tools/purge_accounts.py — o stergere in masa cere Admin SDK, iar proiectul e
pe planul gratuit, fara Cloud Functions. Regulile lasa orice jucator sa
SCRIE in colectie (id-ul e matchId, deci scrierile converg), dar sa citeasca
doar adminul; o stergere din client ar fi si lenta, si usor de declansat din
greseala de pe telefon.

CE ITI TREBUIE, o singura data: aceeasi cheie de cont de serviciu ca la
purge_accounts.py, adica fisierul:

    tools/service-account.json

  Firebase Console -> ⚙ Project settings -> Service accounts
  -> "Generate new private key" -> salveaza-l acolo.

  E in .gitignore — NU-l comite si nu-l trimite nimanui.

RULARE (din radacina proiectului):
    python tools/purge_completed_matches.py                 # doar raporteaza
    python tools/purge_completed_matches.py --sterge        # sterge TOT
    python tools/purge_completed_matches.py --zile 7        # raport, doar cele
                                                            # mai vechi de 7 zile
    python tools/purge_completed_matches.py --zile 7 --sterge

Sau, mai simplu, dublu-click pe "Curata meciuri terminate.bat".
"""
import os
import sys
from datetime import datetime, timedelta, timezone

# Cheia, verificarea ei si mesajul de eroare stau intr-un singur loc, in
# purge_accounts.py — n-are rost sa existe doua variante care pot ajunge sa
# spuna lucruri diferite despre acelasi fisier service-account.json.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from purge_accounts import PROJECT_ID, _session  # noqa: E402

# purge_accounts inlocuieste sys.stdout cu un TextIOWrapper pe utf-8 chiar la
# import. NU-l inlocui a doua oara aici: wrapper-ul dat la o parte ajunge la
# gunoi, isi inchide buffer-ul, iar primul print de dupa crapa cu
# "I/O operation on closed file". reconfigure() schimba acelasi obiect, deci
# e sigur si cand scriptul e rulat de unul singur.
sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)

FIRESTORE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
COLLECTION = "completed_matches"

# Firestore accepta cel mult 500 de operatii intr-un commit. Stergem in
# loturi, nu una cate una: la cateva sute de meciuri, un DELETE per document
# ar insemna cateva sute de dus-intors si zeci de secunde de asteptare.
BATCH = 400


def _parse_ts(raw: str):
    """Timestamp-ul Firestore ('2026-08-04T17:26:18.123456Z') ca datetime.
    Intoarce None daca lipseste sau nu se poate citi — un document fara
    finishedAt nu trebuie sa opreasca tot scriptul."""
    if not raw:
        return None
    try:
        txt = raw.replace("Z", "+00:00")
        # fractiunile de secunda pot veni cu 9 cifre (nanosecunde), iar
        # datetime accepta cel mult 6
        if "." in txt:
            head, rest = txt.split(".", 1)
            frac, tz = rest[:-6], rest[-6:]
            txt = f"{head}.{frac[:6]}{tz}"
        return datetime.fromisoformat(txt)
    except ValueError:
        return None


def completed(session) -> list[dict]:
    """Toate meciurile din jurnal: id, cand s-a terminat, ce mod, cati jucatori."""
    out, page = [], None
    while True:
        url = f"{FIRESTORE}/{COLLECTION}?pageSize=300"
        if page:
            url += f"&pageToken={page}"
        r = session.get(url, timeout=30)
        r.raise_for_status()
        data = r.json()
        for doc in data.get("documents", []):
            f = doc.get("fields", {})
            out.append({
                "id": doc["name"].rsplit("/", 1)[-1],
                "at": _parse_ts(f.get("finishedAt", {}).get("timestampValue", "")),
                "mode": f.get("gameModeId", {}).get("stringValue", "?"),
                "players": int(f.get("playerCount", {}).get("integerValue", 0) or 0),
            })
        page = data.get("nextPageToken")
        if not page:
            return out


def older_than(items: list[dict], days: int) -> list[dict]:
    """Meciurile mai vechi de [days] zile. Cele fara finishedAt sunt INCLUSE:
    sunt documente vechi sau scrise gresit, exact genul de resturi de curatat."""
    limit = datetime.now(timezone.utc) - timedelta(days=days)
    return [m for m in items if m["at"] is None or m["at"] < limit]


def delete_all(session, items: list[dict]) -> tuple[int, list[str]]:
    """Sterge in loturi. Intoarce (cate s-au sters, erori)."""
    done, errors = 0, []
    prefix = f"projects/{PROJECT_ID}/databases/(default)/documents/{COLLECTION}"
    for i in range(0, len(items), BATCH):
        chunk = items[i:i + BATCH]
        body = {"writes": [{"delete": f"{prefix}/{m['id']}"} for m in chunk]}
        r = session.post(f"{FIRESTORE}:commit", json=body, timeout=60)
        if r.status_code == 200:
            done += len(chunk)
            print(f"     sters {done}/{len(items)}")
        else:
            errors.append(f"lotul {i // BATCH + 1}: {r.text[:200]}")
    return done, errors


def _summary(items: list[dict]) -> None:
    """Rezumat, nu o lista de sute de id-uri pe care nu le citeste nimeni."""
    by_mode: dict[str, int] = {}
    for m in items:
        by_mode[m["mode"]] = by_mode.get(m["mode"], 0) + 1
    for mode, n in sorted(by_mode.items(), key=lambda kv: -kv[1]):
        print(f"     - {mode}: {n}")
    dated = sorted([m["at"] for m in items if m["at"]])
    if dated:
        print(f"     cel mai vechi: {dated[0]:%d.%m.%Y %H:%M}")
        print(f"     cel mai nou:   {dated[-1]:%d.%m.%Y %H:%M}")
    undated = sum(1 for m in items if m["at"] is None)
    if undated:
        print(f"     fara data: {undated}")


def main() -> int:
    apply = "--sterge" in sys.argv
    # "Curata meciuri terminate.bat" isi pune singur intrebarea de confirmare,
    # deci acolo indicatia "ruleaza din nou cu --sterge" ar trimite userul sa
    # faca manual exact ce face butonul.
    only_list = "--lista" in sys.argv

    days = None
    if "--zile" in sys.argv:
        try:
            days = int(sys.argv[sys.argv.index("--zile") + 1])
        except (IndexError, ValueError):
            raise SystemExit("Foloseste --zile cu un numar, de exemplu: --zile 7")

    session = _session()
    everything = completed(session)
    items = older_than(everything, days) if days is not None else everything

    if days is None:
        print(f"{len(items)} meci(uri) in jurnal")
    else:
        print(f"{len(items)} din {len(everything)} meci(uri) sunt mai vechi de {days} zile")
    if not items:
        print("\nNimic de facut.")
        return 0
    _summary(items)

    if not apply:
        if not only_list:
            print("\nRulare de proba. Ruleaza din nou cu --sterge ca sa le stergi efectiv.")
        return 0

    print("\nSterg...")
    done, errors = delete_all(session, items)
    for e in errors:
        print(f"     [EROARE] {e}")
    print(f"\nGata. {done} sterse." + (f" {len(errors)} loturi cu erori." if errors else " Fara erori."))
    if done:
        print("Contorul 'meciuri jucate' din AdminScreen arata acum "
              f"{len(everything) - done}.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
