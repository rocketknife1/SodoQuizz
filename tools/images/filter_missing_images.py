"""Elimina din intrebari.json orice intrebare care nu are poza corespunzatoare
in folderul poze/ (id.png lipsa) — pastreaza doar intrebarile cu imagine reala.
Se aplica peste toate gamemodurile, inclusiv cele premium.

Rulare: python tools/images/filter_missing_images.py
"""
import json
import os

MODES = ["pixelat", "logouri", "jocuri", "medical", "mecanica", "aplicatii",
         "masini", "celebritati", "sport", "romania"]
TARGETS = [(f"assets/continut/{m}/intrebari.json", f"assets/continut/{m}/poze") for m in MODES]


def filter_file(json_path, img_dir):
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)

    existing = {os.path.splitext(f)[0] for f in os.listdir(img_dir)} if os.path.isdir(img_dir) else set()

    total_before = 0
    total_after = 0
    for cat in data["categorii"].values():
        items = cat["intrebari"]
        total_before += len(items)
        kept = [it for it in items if it["id"] in existing]
        total_after += len(kept)
        cat["intrebari"] = kept

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"{json_path}: {total_before} -> {total_after} intrebari (pastrate doar cele cu poza)")


def main():
    for json_path, img_dir in TARGETS:
        filter_file(json_path, img_dir)


if __name__ == "__main__":
    main()
