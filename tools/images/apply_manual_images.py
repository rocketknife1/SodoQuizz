"""Aplica pozele aduse manual de user (folder "poze intrebari/") peste
intrebarile marcate cu "facut" in tools/images/baza_de_date_intrebari.xlsx,
si sterge intrebarea marcata cu "eliminata".

Ruleaza o singura data, manual: python tools/images/apply_manual_images.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from fetch_question_images import normalize  # reuseste crop/letterbox 800x600

SRC_DIR = "poze intrebari"

# (json_path, img_dir, question_id, nume_fisier_sursa)
REPLACEMENTS = [
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_001", "APPLE.png"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_002", "nike.png"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_003", "mcdonalds.png"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_004", "cola.png"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_005", "google.png"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_006", "adidas.png"),
    ("assets/continut/logouri/intrebari.json", "assets/continut/logouri/poze", "lgf_007", "ferrari.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_001", "stetoscop.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_002", "seringa.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_003", "scaun cu rotile.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_004", "aparat rmn.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_006", "ecograf.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_007", "bisturiu.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_008", "perfuzie.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_009", "branula.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_010", "termometru.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_011", "tensiometru.png"),
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_012", "pulsoximetru.png"),
]

# (json_path, img_dir, question_id) -- marcate "eliminata" in xlsx
DELETIONS = [
    ("assets/continut/medical/intrebari.json", "assets/continut/medical/poze", "med_005"),
]


def apply_replacements():
    for json_path, img_dir, qid, filename in REPLACEMENTS:
        src_path = os.path.join(SRC_DIR, filename)
        out_path = os.path.join(img_dir, f"{qid}.png")
        with open(src_path, "rb") as f:
            raw = f.read()
        normalize(raw, out_path)
        print(f"[OK] {qid} <- {filename}")


def apply_deletions():
    by_file = {}
    for json_path, img_dir, qid in DELETIONS:
        by_file.setdefault(json_path, []).append((img_dir, qid))

    for json_path, entries in by_file.items():
        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)
        ids_to_remove = {qid for _, qid in entries}
        for cat in data["categorii"].values():
            before = len(cat["intrebari"])
            cat["intrebari"] = [it for it in cat["intrebari"] if it["id"] not in ids_to_remove]
            removed = before - len(cat["intrebari"])
            if removed:
                print(f"[DEL] {json_path}: removed {removed} question(s)")
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        for img_dir, qid in entries:
            img_path = os.path.join(img_dir, f"{qid}.png")
            if os.path.exists(img_path):
                os.remove(img_path)
                print(f"[DEL] removed image {img_path}")


if __name__ == "__main__":
    apply_replacements()
    apply_deletions()
    print("Gata.")
