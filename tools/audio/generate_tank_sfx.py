# -*- coding: utf-8 -*-
"""Genereaza efectele sonore ale modului multiplayer Quizz Tanks.

De ce un script separat de generate_sfx.py, si nu inca sase functii acolo:
acela regenereaza TOATE sunetele vechi la fiecare rulare, iar zgomotul din
ele e aruncat cu random — deci o rulare "ca sa adaug un sunet nou" ar fi
schimbat pe tacute sunetele deja livrate in aplicatie. Aici scriem strict
fisierele tank_*.wav, deci se poate rula oricand, fara efecte laterale.

Uneltele de baza (ton, zgomot, mix, salvare) se importa din generate_sfx.py,
ca sa existe o singura implementare a lantului de normalizare/saturare —
altfel sunetele noi ar fi iesit sistematic mai incet sau mai tare decat cele
vechi. Importul e sigur: acel fisier isi tine tot codul de generare sub
`if __name__ == "__main__"`.

Rulare:  python tools/audio/generate_tank_sfx.py
Cere:    doar biblioteca standard.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from generate_sfx import SR, gen_noise_burst, gen_tone, mix, save_wav  # noqa: E402

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "assets",
    "sfx",
)


def lowpass(buf, cutoff_hz):
    """Filtru trece-jos cu un pol. Transforma zgomotul alb (care suna a
    "sss") in ceva greu si infundat — diferenta dintre un fasait si o
    bubuitura."""
    dt = 1.0 / SR
    rc = 1.0 / (2 * math.pi * cutoff_hz)
    a = dt / (rc + dt)
    out = []
    y = 0.0
    for x in buf:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(buf, cutoff_hz):
    """Trece-sus, ca sa scoatem partea grea dintr-un zgomot si sa ramana
    doar suieratul — folosit la ricoseu."""
    dt = 1.0 / SR
    rc = 1.0 / (2 * math.pi * cutoff_hz)
    a = rc / (rc + dt)
    out = []
    y = 0.0
    prev = 0.0
    for x in buf:
        y = a * (y + x - prev)
        prev = x
        out.append(y)
    return out


def gain(buf, k):
    return [x * k for x in buf]


def build_tank_fire():
    """Bubuitura de tun: un transient scurt si sec (praful de pusca), peste
    o coborare rapida de frecventa spre grav (teava) si un zgomot infundat
    care se stinge. Scurt intentionat — intr-o runda pot trage pana la patru
    tancuri, iar un boom lung s-ar transforma in noroi."""
    thump = gen_tone(230, 55, 0.30, attack=0.001, decay=0.09, amp=0.95)
    body = lowpass(gen_noise_burst(0.32, amp=0.9, decay=0.075), 700)
    crack = gain(highpass(gen_noise_burst(0.05, amp=0.6, decay=0.014), 2200), 0.5)
    buf = mix(0.42, [(0.0, thump), (0.0, body), (0.0, crack)])
    save_wav(os.path.join(OUT_DIR, "tank_fire.wav"), buf)


def build_tank_hit():
    """Impact in blindaj: doua componente metalice INARMONICE (nu un acord —
    metalul lovit nu suna a nota curata) peste un bufnet jos. Se aude clar
    diferit de tank_fire, ca sa se poata spune din auz daca proiectilul a
    lovit sau doar a plecat."""
    clank_a = gen_tone(640, 520, 0.20, attack=0.001, decay=0.055, amp=0.75)
    clank_b = gen_tone(970, 815, 0.16, attack=0.001, decay=0.04, amp=0.45)
    thud = lowpass(gen_noise_burst(0.26, amp=0.8, decay=0.06), 420)
    shrapnel = gain(highpass(gen_noise_burst(0.10, amp=0.5, decay=0.03), 3000), 0.35)
    buf = mix(0.34, [(0.0, clank_a), (0.004, clank_b), (0.0, thud), (0.01, shrapnel)])
    save_wav(os.path.join(OUT_DIR, "tank_hit.wav"), buf)


def build_tank_dodge():
    """Ricoseu: proiectilul a atins blindajul si a plecat mai departe.
    Coborare rapida de ton, subtire si metalica, peste un suierat filtrat sus
    — deliberat mai SLAB si mai inalt decat tank_hit, ca o lovitura evitata
    sa nu para o victorie sonora."""
    whine = gen_tone(2700, 620, 0.26, attack=0.002, decay=0.09, amp=0.55)
    tail = gen_tone(1500, 480, 0.20, attack=0.004, decay=0.07, amp=0.22)
    air = gain(highpass(gen_noise_burst(0.22, amp=0.45, decay=0.06), 1800), 0.4)
    buf = mix(0.32, [(0.0, whine), (0.03, tail), (0.0, air)])
    save_wav(os.path.join(OUT_DIR, "tank_dodge.wav"), buf)


def build_tank_explode():
    """Tanc distrus. Singurul sunet lung din set (peste o secunda) si singurul
    cu sub-bas adevarat — se intampla o data la cateva runde, deci are voie sa
    ocupe spatiu. Trei straturi: sub-ul care da lovitura in piept, corpul
    infundat care se stinge lent, si o coada de trosnete."""
    sub = gen_tone(95, 32, 0.85, attack=0.002, decay=0.26, amp=1.0)
    body = lowpass(gen_noise_burst(1.0, amp=0.95, decay=0.24), 320)
    debris = gain(lowpass(gen_noise_burst(0.9, amp=0.5, decay=0.4), 2400), 0.3)
    crack = gain(highpass(gen_noise_burst(0.08, amp=0.7, decay=0.02), 2600), 0.45)
    buf = mix(1.15, [(0.0, sub), (0.0, body), (0.05, debris), (0.0, crack)])
    save_wav(os.path.join(OUT_DIR, "tank_explode.wav"), buf)


def build_tank_lock():
    """Ținta blocată: doi bipuri INALTE si scurte, urcatoare, plus un mic
    "clac" de mecanism. Trebuie sa se auda a confirmare, nu a avertisment —
    de-aia urca (spre deosebire de tank_alarm, care sta pe loc)."""
    up_a = gen_tone(1180, 1200, 0.055, attack=0.001, decay=0.03, amp=0.6)
    up_b = gen_tone(1770, 1800, 0.11, attack=0.001, decay=0.06, amp=0.7)
    clack = gain(highpass(gen_noise_burst(0.035, amp=0.5, decay=0.012), 2600), 0.4)
    buf = mix(0.26, [(0.0, up_a), (0.07, up_b), (0.0, clack)])
    save_wav(os.path.join(OUT_DIR, "tank_lock.wav"), buf)


def build_tank_alarm():
    """Doua bipuri scurte si taioase, in ultimele secunde ale rundei. Inalte
    si uscate ca sa taie prin muzica de fundal fara sa fie tare — la cinci
    secunde de raspuns, avertismentul trebuie observat instant, nu ascultat."""
    beep_a = gen_tone(1350, 1330, 0.085, attack=0.002, decay=0.05, amp=0.7)
    beep_b = gen_tone(1350, 1330, 0.085, attack=0.002, decay=0.05, amp=0.7)
    edge_a = gain(gen_tone(2700, 2660, 0.06, attack=0.001, decay=0.03, amp=0.25), 1.0)
    edge_b = gain(gen_tone(2700, 2660, 0.06, attack=0.001, decay=0.03, amp=0.25), 1.0)
    buf = mix(0.30, [(0.0, beep_a), (0.0, edge_a), (0.14, beep_b), (0.14, edge_b)])
    save_wav(os.path.join(OUT_DIR, "tank_alarm.wav"), buf)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # samanta fixa: doua rulari trebuie sa dea exact aceleasi fisiere, altfel
    # un `git status` ar arata modificari dupa fiecare rulare degeaba.
    random.seed(1944)
    build_tank_fire()
    build_tank_hit()
    build_tank_dodge()
    build_tank_explode()
    build_tank_lock()
    build_tank_alarm()
    print(
        f"Scrise in {OUT_DIR}: tank_fire.wav, tank_hit.wav, tank_dodge.wav, "
        "tank_explode.wav, tank_lock.wav, tank_alarm.wav"
    )


if __name__ == "__main__":
    main()
