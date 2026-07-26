"""Reincearca manual, cu interogari mai bune, intrebarile ramase fara poza
dupa rularea completa a tools/images/fetch_question_images.py.

Inlocuieste fostele retry_failed_images.py + retry_failed_images2.py (erau
doua treceri succesive peste aceleasi cateva esecuri, cu queries rafinate
intre ele) - ATTEMPTS de mai jos e lista din prima trecere, care a rezolvat
deja toate cele 10 intrebari (verificat: toate cele 999 de intrebari au
poza). Ramane ca sablon pentru urmatoarea data cand fetch_question_images.py
lasa ceva neacoperit - actualizeaza ATTEMPTS cu id-urile/query-urile noi.

Rulare:       python tools/images/retry_missing_images.py
Mai incet     (pauza 8s intre incercari, pentru rate-limit Wikimedia):
              python tools/images/retry_missing_images.py --slow
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from fetch_question_images import try_wiki, try_commons

# (img_dir, id, [interogari de incercat in ordine])
ATTEMPTS = [
    ("assets/continut/jocuri/poze", "gam_077", [("wiki", "Phasmophobia"), ("commons", "Phasmophobia video game")]),
    ("assets/continut/jocuri/poze", "gam_098", [("wiki", "Monster Hunter World"), ("commons", "Monster Hunter World")]),
    ("assets/continut/jocuri/poze", "gam_100", [("wiki", "Baldur's Gate 3"), ("commons", "Baldur's Gate 3 cover art")]),
    ("assets/continut/aplicatii/poze", "apl_043", [("commons", "MyFitnessPal logo"), ("wiki", "MyFitnessPal")]),
    ("assets/continut/aplicatii/poze", "apl_090", [("commons", "Cronometer logo"), ("wiki", "Cronometer")]),
    ("assets/continut/aplicatii/poze", "apl_096", [("commons", "Citymapper logo"), ("wiki", "Citymapper")]),
    ("assets/continut/sport/poze", "spo_060", [("wiki", "Manchester City F.C."), ("commons", "Manchester City FC logo")]),
    ("assets/continut/romania/poze", "rom_085", [("wiki", "Anghel Saligny Bridge"), ("wiki", "Cernavodă Bridge"), ("commons", "Cernavoda old bridge")]),
    ("assets/continut/romania/poze", "rom_096", [("wiki", "Cotnari"), ("commons", "Cotnari wine")]),
    ("assets/continut/romania/poze", "rom_100", [("commons", "covrigi pretzel Romania"), ("wiki", "Covasna")]),
]


def main():
    slow = "--slow" in sys.argv
    ok, fail = 0, 0
    for img_dir, qid, attempts in ATTEMPTS:
        out_path = os.path.join(img_dir, f"{qid}.png")
        found = None
        for kind, query in attempts:
            try:
                src = try_wiki(query, out_path) if kind == "wiki" else try_commons(query, out_path)
                if src:
                    found = src
                    break
            except Exception as e:
                print(f"    {kind} fail ({query}): {e}")
            if slow:
                time.sleep(8)
        if found:
            ok += 1
            print(f"[OK] {qid} <- {found}")
        else:
            fail += 1
            print(f"[--] {qid} FARA IMAGINE (incercari epuizate)")
        if slow:
            time.sleep(8)

    print(f"\nGata: {ok} descarcate, {fail} inca esuate")


if __name__ == "__main__":
    main()
