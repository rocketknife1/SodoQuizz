"""Sunetul de notificare al aplicatiei — un clopotel scurt, prietenos.

DE CE E GENERAT, NU DESCARCAT: exact acelasi motiv ca la muzica (vezi
generate_music.py) si ca la toata arta jocului — nimic din ce ajunge in
aplicatie nu are licenta de urmarit. Fisierul iese identic la fiecare rulare,
deci se poate regenera oricand.

CUM SUNA: trei note dintr-un acord major (do-mi-sol), cantate una dupa alta,
scurt, cu un pic de "sclipici" deasupra. Un clopotel de cutie muzicala, nu un
bip de sistem: notificarea unui joc trebuie sa se simta ca un premiu, nu ca o
alarma.

UNDE MERGE: `android/app/src/main/res/raw/sodo_notify.wav`. Sunetul unei
notificari Android se leaga de CANAL, nu de mesaj — vezi
DeviceNotificationService. Fisierul trebuie sa fie in `res/raw`, nu in
`assets/`, fiindca sistemul (nu aplicatia) il reda.

Cere: numpy.
    python tools/generate_notification_sound.py
"""

import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join("android", "app", "src", "main", "res", "raw", "sodo_notify.wav")


def note(freq, dur, delay, amp=0.5):
    """O nota de clopotel: fundamentala + doua armonice, cu stingere rapida.

    Armonicele sunt la 2x si 3x, tot mai slabe — asa suna a clopot/carillon.
    O sinusoida singura ar fi iesit un bip de ceas desteptator.
    """
    n = int(RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    # stingere exponentiala: lovitura e la inceput, coada se duce lin
    env = np.exp(-t * 5.5)
    # atac scurt, ca sa nu pocneasca la pornire
    attack = np.minimum(t / 0.004, 1.0)
    wave_ = (
        np.sin(2 * np.pi * freq * t)
        + 0.42 * np.sin(2 * np.pi * freq * 2 * t)
        + 0.16 * np.sin(2 * np.pi * freq * 3 * t)
    )
    out = np.zeros(int(RATE * TOTAL))
    start = int(RATE * delay)
    out[start:start + n] = wave_ * env * attack * amp
    return out


TOTAL = 1.1

# Do-mi-sol in octava a 5-a: luminos, nu strident. Ultima nota e mai lunga si
# putin mai tare — se termina pe ceva, nu se opreste brusc.
NOTES = [
    (523.25, 0.45, 0.00, 0.42),  # do5
    (659.25, 0.45, 0.09, 0.42),  # mi5
    (783.99, 0.75, 0.18, 0.50),  # sol5
]


def main():
    mix = np.zeros(int(RATE * TOTAL))
    for freq, dur, delay, amp in NOTES:
        mix += note(freq, dur, delay, amp)

    # "sclipici": o octava peste ultima nota, foarte incet, doar cat sa dea
    # stralucire — fara el clopotelul suna gros si ieftin.
    mix += note(1567.98, 0.5, 0.18, 0.10)

    peak = np.max(np.abs(mix))
    if peak > 0:
        mix = mix / peak * 0.85

    # fade final, ca sa nu se taie coada cu un click
    tail = int(RATE * 0.06)
    mix[-tail:] *= np.linspace(1, 0, tail)

    data = (mix * 32767).astype(np.int16)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with wave.open(OUT, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print(f"scris {OUT}  ({os.path.getsize(OUT) / 1024:.0f} KB, {TOTAL:.1f}s)")


if __name__ == "__main__":
    main()
