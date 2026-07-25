"""Reincearca manual, cu interogari mai bune, cele 10 intrebari ramase fara
poza dupa rularea completa a fetch_question_images.py.

Ruleaza o singura data, manual: python tools/retry_failed_images.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from fetch_question_images import try_wiki, try_commons

# (json_path pentru referinta, img_dir, id, [interogari de incercat in ordine])
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
        if found:
            ok += 1
            print(f"[OK] {qid} <- {found}")
        else:
            fail += 1
            print(f"[--] {qid} FARA IMAGINE (incercari epuizate)")

    print(f"\nGata: {ok} descarcate, {fail} inca esuate")


if __name__ == "__main__":
    main()
