# -*- coding: utf-8 -*-
"""Genereaza efectele sonore ale modului multiplayer Obby.

Acelasi motiv ca la generate_tank_sfx.py pentru un fisier separat:
generate_sfx.py regenereaza TOATE sunetele vechi la fiecare rulare (zgomotul
din ele vine din random), deci o rulare "ca sa adaug un sunet nou" ar fi
schimbat pe tacute sunete deja livrate. Aici se scriu strict obby_*.wav.

Uneltele de baza (ton, zgomot, mix, salvare) se importa din generate_sfx.py,
iar filtrele din generate_tank_sfx.py — o singura implementare a lantului de
normalizare/saturare pentru tot proiectul, altfel sunetele noi ies sistematic
mai incet sau mai tare decat cele vechi.

Rulare:  python tools/audio/generate_obby_sfx.py
Cere:    doar biblioteca standard.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from generate_sfx import gen_noise_burst, gen_tone, mix, save_wav  # noqa: E402
from generate_tank_sfx import gain, highpass, lowpass  # noqa: E402

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "assets",
    "sfx",
)


def build_obby_pick():
    """Am apasat o placa. Un "toc" scurt de lemn, cald si sec — placile din
    scena sunt maro/lemn, iar sunetul trebuie sa confirme apasarea fara sa
    promita nimic: inca nu se stie daca placa e buna sau falsa, deci NU urca
    (a urca ar suna a reusita) si nu coboara (ar suna a greseala)."""
    knock = gen_tone(420, 360, 0.10, attack=0.001, decay=0.045, amp=0.8)
    body = gen_tone(210, 180, 0.12, attack=0.002, decay=0.055, amp=0.35)
    tick = gain(highpass(gen_noise_burst(0.03, amp=0.5, decay=0.01), 2400), 0.4)
    buf = mix(0.16, [(0.0, knock), (0.0, body), (0.0, tick)])
    save_wav(os.path.join(OUT_DIR, "obby_pick.wav"), buf)


def build_obby_jump():
    """Placa a tinut: saritura reusita. Un "hop" scurt care URCA in frecventa
    (miscare in sus, citita instant ca reusita) plus un fasait de aer. Scurt
    (~0.25s) fiindca in scena saritura tine 0.35 din reveal — un sunet mai
    lung s-ar fi terminat dupa ce personajul a aterizat deja."""
    hop = gen_tone(320, 900, 0.20, attack=0.003, decay=0.10, amp=0.85)
    spring = gen_tone(640, 1500, 0.12, attack=0.002, decay=0.05, amp=0.30)
    air = gain(highpass(gen_noise_burst(0.16, amp=0.4, decay=0.05), 1600), 0.35)
    buf = mix(0.26, [(0.0, hop), (0.0, spring), (0.02, air)])
    save_wav(os.path.join(OUT_DIR, "obby_jump.wav"), buf)


def build_obby_fall():
    """Placa era falsa: caderea prin ea. Exact opusul lui obby_jump — coboara
    lung si adanc, cu un fasait infundat peste. E cel mai lung sunet din set
    (~0.9s) fiindca insoteste toata animatia de cadere, nu doar startul ei.
    Se termina intr-un bufnet jos, ca sa aiba un final clar, nu o disparitie."""
    drop = gen_tone(760, 90, 0.75, attack=0.004, decay=0.42, amp=0.9)
    under = gen_tone(300, 55, 0.80, attack=0.006, decay=0.45, amp=0.45)
    wind = gain(lowpass(gen_noise_burst(0.70, amp=0.55, decay=0.30), 900), 0.4)
    thud = lowpass(gen_noise_burst(0.22, amp=0.85, decay=0.05), 260)
    buf = mix(0.95, [(0.0, drop), (0.0, under), (0.05, wind), (0.72, thud)])
    save_wav(os.path.join(OUT_DIR, "obby_fall.wav"), buf)


def build_obby_finish():
    """Am trecut de ultimul obstacol — se aude o singura data pe meci, deci
    are voie sa fie cea mai mare afirmatie din set: trei note ascendente
    (do-mi-sol) cu un sparkle deasupra. Mai plin decat obby_jump, ca ultima
    saritura sa nu sune la fel cu celelalte sase."""
    notes = [523.25, 659.25, 783.99]  # C5 E5 G5
    segments = []
    for i, freq in enumerate(notes):
        tone = gen_tone(freq, freq * 1.01, 0.26, attack=0.003, decay=0.16, amp=0.62 - i * 0.03)
        segments.append((i * 0.085, tone))
    sparkle = gen_tone(1567.98, 1600, 0.30, attack=0.004, decay=0.20, amp=0.28)
    segments.append((0.17, sparkle))
    segments.append((0.0, gain(highpass(gen_noise_burst(0.06, amp=0.4, decay=0.02), 2000), 0.3)))
    buf = mix(0.62, segments)
    save_wav(os.path.join(OUT_DIR, "obby_finish.wav"), buf)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # samanta fixa: doua rulari trebuie sa dea exact aceleasi fisiere, altfel
    # un `git status` ar arata modificari dupa fiecare rulare degeaba.
    random.seed(2077)
    build_obby_pick()
    build_obby_jump()
    build_obby_fall()
    build_obby_finish()
    print(
        f"Scrise in {OUT_DIR}: obby_pick.wav, obby_jump.wav, obby_fall.wav, "
        "obby_finish.wav"
    )


if __name__ == "__main__":
    main()
