"""Sterge din Firestore camerele de joc multiplayer ramase blocate.

CE E COLECTIA `matches`: camera unui meci multiplayer *in desfasurare* —
altceva decat `completed_matches`, care e doar jurnalul statistic al
meciurilor incheiate (vezi tools/purge_completed_matches.py). Fiecare
document are subcolectiile `players` si `chat`.

DE CE RAMAN CAMERE IN URMA: MultiplayerService.leaveMatch() sterge camera
doar in doua situatii — hostul iese cat timp meciul e inca in lobby, sau
ultimul jucator apasa efectiv butonul de iesire. Daca jucatorii omoara
aplicatia din task switcher, pierd conexiunea sau inchid tab-ul de browser,
metoda aia nu se apeleaza niciodata. Proiectul e pe planul gratuit, fara
Cloud Functions si fara TTL pe colectie, deci nimeni nu mai atinge
documentul: ramane acolo la nesfarsit, de obicei cu status "playing" si o
runda inghetata la mijloc.

Nu strica jocul — camerele vechi nu sunt listate nicaieri si nu intra in
matchmaking — dar se aduna si fac consola greu de citit.

⚠️ NU rula cu o fereastra prea mica de ore cat timp chiar se joaca cineva:
un meci in curs e tot un document din `matches`. Implicit sunt 6 ore, mult
peste cele 60 de secunde ale unui meci real.

CE ITI TREBUIE, o singura data: aceeasi cheie de cont de serviciu ca la
purge_accounts.py, adica fisierul:

    tools/service-account.json

  Firebase Console -> ⚙ Project settings -> Service accounts
  -> "Generate new private key" -> salveaza-l acolo.

  E in .gitignore — NU-l comite si nu-l trimite nimanui.

RULARE (din radacina proiectului):
    python tools/purge_stale_matches.py                # raport, mai vechi de 6h
    python tools/purge_stale_matches.py --sterge       # sterge efectiv
    python tools/purge_stale_matches.py --ore 24       # alta fereastra
    python tools/purge_stale_matches.py --toate        # ignora vechimea

Sau, mai simplu, dublu-click pe "Curata camere blocate.bat".
"""
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from purge_accounts import PROJECT_ID, _session  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)

FIRESTORE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
COLLECTION = "matches"
SUBCOLLECTIONS = ("players", "chat")

BATCH = 400
ORE_IMPLICIT = 6


def _parse_ts(raw: str):
    if not raw:
        return None
    try:
        txt = raw.replace("Z", "+00:00")
        if "." in txt:
            head, rest = txt.split(".", 1)
            frac, tz = rest[:-6], rest[-6:]
            txt = f"{head}.{frac[:6]}{tz}"
        return datetime.fromisoformat(txt)
    except ValueError:
        return None


def rooms(session) -> list[dict]:
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
                "at": _parse_ts(f.get("createdAt", {}).get("timestampValue", "")),
                "status": f.get("status", {}).get("stringValue", "?"),
                "mode": f.get("mode", {}).get("stringValue", "?"),
            })
        page = data.get("nextPageToken")
        if not page:
            return out


def older_than(items: list[dict], hours: int) -> list[dict]:
    """Camerele mai vechi de [hours] ore. Cele fara createdAt sunt INCLUSE —
    sunt documente scrise gresit sau foarte vechi, exact resturile de curatat."""
    limit = datetime.now(timezone.utc) - timedelta(hours=hours)
    return [m for m in items if m["at"] is None or m["at"] < limit]


def _subdocs(session, match_id: str) -> list[str]:
    """Numele complete ale documentelor din players/ si chat/. Firestore nu
    sterge subcolectiile odata cu documentul parinte — daca le sarim, raman
    orfane si invizibile in consola, dar continua sa existe."""
    names = []
    for sub in SUBCOLLECTIONS:
        page = None
        while True:
            url = f"{FIRESTORE}/{COLLECTION}/{match_id}/{sub}?pageSize=300"
            if page:
                url += f"&pageToken={page}"
            r = session.get(url, timeout=30)
            if r.status_code != 200:
                break
            data = r.json()
            names += [d["name"] for d in data.get("documents", [])]
            page = data.get("nextPageToken")
            if not page:
                break
    return names


def delete_all(session, items: list[dict]) -> tuple[int, list[str]]:
    prefix = f"projects/{PROJECT_ID}/databases/(default)/documents/{COLLECTION}"
    targets: list[str] = []
    for m in items:
        targets += _subdocs(session, m["id"])
        targets.append(f"{prefix}/{m['id']}")

    done, errors = 0, []
    for i in range(0, len(targets), BATCH):
        chunk = targets[i:i + BATCH]
        body = {"writes": [{"delete": name} for name in chunk]}
        r = session.post(f"{FIRESTORE}:commit", json=body, timeout=60)
        if r.status_code == 200:
            done += len(chunk)
            print(f"     sters {done}/{len(targets)} documente")
        else:
            errors.append(f"lotul {i // BATCH + 1}: {r.text[:200]}")
    return done, errors


def _summary(items: list[dict]) -> None:
    by_status: dict[str, int] = {}
    for m in items:
        by_status[m["status"]] = by_status.get(m["status"], 0) + 1
    for status, n in sorted(by_status.items(), key=lambda kv: -kv[1]):
        print(f"     - status '{status}': {n}")
    dated = sorted([m["at"] for m in items if m["at"]])
    if dated:
        print(f"     cea mai veche: {dated[0]:%d.%m.%Y %H:%M}")
        print(f"     cea mai noua:  {dated[-1]:%d.%m.%Y %H:%M}")
    undated = sum(1 for m in items if m["at"] is None)
    if undated:
        print(f"     fara data: {undated}")


def main() -> int:
    apply = "--sterge" in sys.argv
    only_list = "--lista" in sys.argv
    toate = "--toate" in sys.argv

    hours = ORE_IMPLICIT
    if "--ore" in sys.argv:
        try:
            hours = int(sys.argv[sys.argv.index("--ore") + 1])
        except (IndexError, ValueError):
            raise SystemExit("Foloseste --ore cu un numar, de exemplu: --ore 24")

    session = _session()
    everything = rooms(session)
    items = everything if toate else older_than(everything, hours)

    if toate:
        print(f"{len(items)} camera(e) in `matches`, indiferent de vechime")
    else:
        print(f"{len(items)} din {len(everything)} camera(e) sunt mai vechi de {hours} ore")
    if not items:
        print("\nNimic de facut.")
        return 0
    _summary(items)

    if not apply:
        if not only_list:
            print("\nRulare de proba. Ruleaza din nou cu --sterge ca sa le stergi efectiv.")
        return 0

    print("\nSterg (camera + players + chat)...")
    done, errors = delete_all(session, items)
    for e in errors:
        print(f"     [EROARE] {e}")
    print(f"\nGata. {done} documente sterse." + (f" {len(errors)} loturi cu erori." if errors else " Fara erori."))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
