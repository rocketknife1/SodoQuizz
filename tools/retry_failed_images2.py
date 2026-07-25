"""A doua reincercare, mai lenta (pauza intre incercari), pentru cele 5
intrebari ramase fara poza dupa retry_failed_images.py.

Ruleaza o singura data, manual: python tools/retry_failed_images2.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from fetch_question_images import try_wiki, try_commons

ATTEMPTS = [
    ("assets/continut/jocuri/poze", "gam_077", [("wiki", "Phasmophobia"), ("wiki", "Phasmophobia video game"), ("commons", "Phasmophobia game logo")]),
    ("assets/continut/jocuri/poze", "gam_100", [("wiki", "Baldur's Gate 3"), ("wiki", "Baldur's Gate III"), ("commons", "Baldur's Gate 3 logo")]),
    ("assets/continut/aplicatii/poze", "apl_043", [("wiki", "MyFitnessPal"), ("commons", "MyFitnessPal icon"), ("commons", "MyFitnessPal")]),
    ("assets/continut/aplicatii/poze", "apl_090", [("wiki", "Cronometer"), ("commons", "Cronometer icon"), ("commons", "Cronometer")]),
    ("assets/continut/aplicatii/poze", "apl_096", [("wiki", "Citymapper"), ("commons", "Citymapper icon"), ("commons", "Citymapper")]),
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
            time.sleep(8)
        if found:
            ok += 1
            print(f"[OK] {qid} <- {found}")
        else:
            fail += 1
            print(f"[--] {qid} FARA IMAGINE (incercari epuizate)")
        time.sleep(8)

    print(f"\nGata: {ok} descarcate, {fail} inca esuate")


if __name__ == "__main__":
    main()
