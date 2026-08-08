"""Aplica pozele aduse manual de user (folder "poze intrebari/") peste
intrebarile marcate cu "facut" in tools/images/baza_de_date_intrebari.xlsx,
si sterge intrebarile marcate cu "eliminata".

Citeste marcajele direct din xlsx, deci se poate rula ori de cate ori userul
mai adauga poze — nu trebuie tinuta o lista la zi in cod.

Ruleaza: python tools/images/apply_manual_images.py
"""
import json
import os
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(__file__))
from fetch_question_images import normalize  # reuseste crop/letterbox 800x600

SRC_DIR = "poze intrebari"
XLSX = "tools/images/baza_de_date_intrebari.xlsx"

CAT_MAP = {
    "Logo-uri (Branduri cunoscute)": "logouri",
    "Gamers Cave (Steam trivia)": "jocuri",
    "Medical (Obiecte medicale)": "medical",
    "Mecanica (Piese & scule auto)": "mecanica",
    "Aplicatii (Apps de telefon)": "aplicatii",
    "Masini de lux": "masini",
    "Celebritati": "celebritati",
    "Sport": "sport",
    "Romania": "romania",
    "Pixelat": "pixelat",
}


def read_markers():
    wb = openpyxl.load_workbook(XLSX, data_only=True)
    ws = wb["Baza de date"]
    replacements, deletions, unknown_cat = [], [], set()
    for row in ws.iter_rows(min_row=2, values_only=True):
        categorie, qid, _, marker, raspuns = row[0], row[1], row[2], row[3], row[4]
        if not marker or not qid:
            continue
        marker = str(marker).strip().lower()
        if marker not in ("facut", "eliminata"):
            continue
        slug = CAT_MAP.get(categorie)
        if not slug:
            unknown_cat.add(categorie)
            continue
        if marker == "facut":
            replacements.append((slug, qid, str(raspuns).strip()))
        else:
            deletions.append((slug, qid))
    for cat in sorted(unknown_cat):
        print(f"[ATENTIE] categorie necunoscuta in xlsx, ignorata: {cat}")
    return replacements, deletions


def find_source(raspuns, files_lower):
    return files_lower.get(f"{raspuns.lower()}.png")


def apply_replacements(replacements):
    files_lower = {f.lower(): f for f in os.listdir(SRC_DIR)}
    applied, missing = 0, []
    for slug, qid, raspuns in replacements:
        filename = find_source(raspuns, files_lower)
        if not filename:
            missing.append((qid, raspuns))
            continue
        with open(os.path.join(SRC_DIR, filename), "rb") as f:
            raw = f.read()
        normalize(raw, os.path.join("assets/continut", slug, "poze", f"{qid}.webp"))
        applied += 1
    print(f"[OK] aplicate {applied} poze")
    if missing:
        print(f"[INFO] {len(missing)} marcate 'facut' fara fisier in '{SRC_DIR}/' "
              f"(deja aplicate intr-o runda anterioara, sursa stearsa):")
        for qid, raspuns in missing:
            print(f"       {qid} — {raspuns}")


def apply_deletions(deletions):
    if not deletions:
        return
    by_slug = {}
    for slug, qid in deletions:
        by_slug.setdefault(slug, set()).add(qid)

    for slug, ids in by_slug.items():
        json_path = os.path.join("assets/continut", slug, "intrebari.json")
        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)
        for cat in data["categorii"].values():
            before = len(cat["intrebari"])
            cat["intrebari"] = [it for it in cat["intrebari"] if it["id"] not in ids]
            if before - len(cat["intrebari"]):
                print(f"[DEL] {json_path}: sterse {before - len(cat['intrebari'])} intrebari")
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        for qid in ids:
            img_path = os.path.join("assets/continut", slug, "poze", f"{qid}.webp")
            if os.path.exists(img_path):
                os.remove(img_path)
                print(f"[DEL] sters {img_path}")


def update_test_screen(replacements):
    """Rescrie lista testQuestionIds din ecranul de TEST, ca sa arate exact
    pozele aduse manual. Tinuta cu mana, lista ramanea mereu in urma."""
    ordine = ["logouri", "jocuri", "medical", "mecanica", "aplicatii",
              "masini", "celebritati", "sport", "romania", "pixelat"]
    grupe: dict[str, list[str]] = {}
    for slug, qid, _ in replacements:
        grupe.setdefault(slug, []).append(qid)

    linii = []
    for slug in ordine:
        ids = sorted(grupe.get(slug, []))
        for i in range(0, len(ids), 7):
            linii.append("  " + " ".join(f"'{q}'," for q in ids[i:i + 7]))

    bloc = ("// GENERAT AUTOMAT — START\nconst List<String> testQuestionIds = [\n"
            + "\n".join(linii) + "\n];\n// GENERAT AUTOMAT — STOP")

    path = "lib/screens/test_images_screen.dart"
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    start = txt.index("// GENERAT AUTOMAT — START")
    stop = txt.index("// GENERAT AUTOMAT — STOP") + len("// GENERAT AUTOMAT — STOP")
    with open(path, "w", encoding="utf-8") as f:
        f.write(txt[:start] + bloc + txt[stop:])
    print(f"[OK] ecranul de TEST arata acum {len(replacements)} poze")


if __name__ == "__main__":
    replacements, deletions = read_markers()
    apply_replacements(replacements)
    apply_deletions(deletions)
    update_test_screen(replacements)
    print("Gata.")
