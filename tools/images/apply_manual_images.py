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
# Runda 2026-08-02b: doar mec_018 (PISTON), adaugata dupa runda anterioara
# (lgf_008-017, gam_*, restul mec_*, apl_001 - deja aplicate).
REPLACEMENTS = [
    ("assets/continut/mecanica/intrebari.json", "assets/continut/mecanica/poze", "mec_018", "piston.png"),
]

# (json_path, img_dir, question_id) -- marcate "eliminata" in xlsx
DELETIONS: list[tuple[str, str, str]] = []


def apply_replacements():
    for json_path, img_dir, qid, filename in REPLACEMENTS:
        src_path = os.path.join(SRC_DIR, filename)
        out_path = os.path.join(img_dir, f"{qid}.webp")
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
            img_path = os.path.join(img_dir, f"{qid}.webp")
            if os.path.exists(img_path):
                os.remove(img_path)
                print(f"[DEL] removed image {img_path}")


if __name__ == "__main__":
    apply_replacements()
    apply_deletions()
    print("Gata.")
