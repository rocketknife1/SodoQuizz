"""Elimină întrebările cu răspuns duplicat între/în gamemoduri.

Păstrează prima apariție (în ordinea pixel -> choice -> cave -> medical,
și în ordinea din fișier) și șterge restul. Rulare:
    python tools/dedupe_questions.py
"""
import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

FILES = [
    "assets/continut/pixelat/intrebari.json",
    "assets/continut/logouri/intrebari.json",
    "assets/continut/jocuri/intrebari.json",
    "assets/continut/medical/intrebari.json",
    "assets/continut/mecanica/intrebari.json",
]

seen = {}
removed = []

for path in FILES:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    changed = False
    for cat_id, cat in data["categorii"].items():
        kept = []
        for item in cat.get("intrebari", []):
            key = item["raspuns"].strip().upper()
            if key in seen:
                removed.append((path, item["id"], key, seen[key]))
                changed = True
            else:
                seen[key] = f"{path}:{item['id']}"
                kept.append(item)
        cat["intrebari"] = kept
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

print(f"Sterse: {len(removed)} intrebari duplicate")
for path, qid, answer, kept_in in removed:
    print(f"  {path} {qid} ({answer}) -- pastrat in {kept_in}")

print("\nRamase per fisier:")
for path in FILES:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for cat_id, cat in data["categorii"].items():
        print(f"  {path} [{cat_id}]: {len(cat['intrebari'])}")
