"""Micsoreaza pozele intrebarilor, fara pierdere vizibila.

DE CE: cele 1400 de poze sunt 101 MB din cele ~173 MB ale APK-ului. Un joc de
quiz care cere 173 MB se pierde la descarcare — omul vede cifra si renunta,
mai ales pe date mobile. Reincodarea la calitate 72 taie ~48 MB fara ca
diferenta sa se vada, mai ales ca jocul arata pozele BLURATE la inceput.

CE NU ATINGE:
  - pozele sub 40 KB — castigul ar fi mic si ar pierde calitate degeaba;
  - pozele care nu se micsoreaza cu macar 15% — deja sunt bine comprimate.
Asa se evita si un diff urias in git: se schimba doar ce chiar merita.

Reincodarea e ireversibila ca fisier, DAR pozele sunt in git, deci un
`git checkout -- assets/` le aduce inapoi oricand.

Rulare:
    python tools/optimize_images.py            # doar raporteaza
    python tools/optimize_images.py --aplica   # scrie efectiv
"""

import glob
import io
import os
import sys

from PIL import Image

# Calitatea WebP. 72 s-a ales uitandu-ne la poze inainte/dupa: la 800x600,
# diferenta se vede doar in texturi fine (iarba, frunze), niciodata pe subiect.
QUALITY = 72

# Sub atat nu merita atinsa poza.
MIN_BYTES = 40 * 1024

# Daca nu se castiga macar atat, poza ramane neatinsa.
MIN_GAIN = 0.15


def main() -> None:
    apply = "--aplica" in sys.argv
    files = sorted(glob.glob("assets/continut/**/*.webp", recursive=True))
    if not files:
        raise SystemExit(
            "Nicio poza gasita. Ruleaza din radacina proiectului."
        )

    before_total = after_total = 0
    touched = 0

    for path in files:
        before = os.path.getsize(path)
        before_total += before

        if before < MIN_BYTES:
            after_total += before
            continue

        image = Image.open(path).convert("RGB")
        buffer = io.BytesIO()
        image.save(buffer, "WEBP", quality=QUALITY, method=6)
        after = buffer.tell()

        if after >= before * (1 - MIN_GAIN):
            after_total += before
            continue

        touched += 1
        after_total += after
        if apply:
            with open(path, "wb") as handle:
                handle.write(buffer.getvalue())

    mb = 1024 * 1024
    print(f"poze:      {len(files)} (atinse: {touched})")
    print(f"inainte:   {before_total / mb:.1f} MB")
    print(f"dupa:      {after_total / mb:.1f} MB")
    print(f"castig:    {(before_total - after_total) / mb:.0f} MB")
    if not apply:
        print("\nRulare de proba. Adauga --aplica ca sa scrie efectiv.")


if __name__ == "__main__":
    main()
