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
    """O nota de clopotel MOALE: fundamentala + o armonica slaba, stingere lina.

    A doua versiune (2026-09-03) — userul a zis ca prima suna "brutal si
    zgomotos". Schimbari: armonica de ordin 3 scoasa (ea dadea muchia
    metalica), armonica 2 mult mai slaba, atac de 3x mai lung (fara pocnet),
    stingere mai lunga (coada catifelata, nu taiere seaca).
    """
    n = int(RATE * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    env = np.exp(-t * 3.6)  # era 5.5 — coada mai lunga, mai blanda
    attack = 1.0 - np.exp(-t / 0.014)  # rampa lina, nu prag (era t/0.004)
    wave_ = (
        np.sin(2 * np.pi * freq * t)
        + 0.18 * np.sin(2 * np.pi * freq * 2 * t)  # era 0.42
    )
    out = np.zeros(int(RATE * TOTAL))
    start = int(RATE * delay)
    out[start:start + n] = wave_ * env * attack * amp
    return out


TOTAL = 1.3

# Do-mi-sol in octava a 4-a (o octava mai JOS decat prima versiune): mai cald,
# mai putin ascutit. Note mai apropiate in timp — suna a "ding-dong" scurt, nu
# a trei bipuri separate.
NOTES = [
    (261.63, 0.55, 0.00, 0.40),  # do4
    (329.63, 0.55, 0.07, 0.40),  # mi4
    (392.00, 0.95, 0.14, 0.46),  # sol4
]


def main():
    mix = np.zeros(int(RATE * TOTAL))
    for freq, dur, delay, amp in NOTES:
        mix += note(freq, dur, delay, amp)

    peak = np.max(np.abs(mix))
    if peak > 0:
        # 0.62 in loc de 0.85 — notificarea nu trebuie sa sara mai tare decat
        # sunetele sistemului.
        mix = mix / peak * 0.62

    # fade lung la final, ca sa se stinga, nu sa se taie
    tail = int(RATE * 0.12)
    mix[-tail:] *= np.linspace(1, 0, tail) ** 2

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
