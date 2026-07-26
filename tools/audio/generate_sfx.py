"""Genereaza efecte sonore scurte (sinteza locala, fara sample-uri externe,
deci fara griji de licenta) pentru: butonul Next, aparitia recompensei de
quest si impactul monedelor in balanta.

Rulare: python tools/audio/generate_sfx.py
"""
import math
import random
import struct
import wave
import os

SR = 44100
OUT_DIR = "assets/sfx"


def gen_tone(freq_start, freq_end, duration, attack=0.004, decay=None, amp=0.9):
    n = int(duration * SR)
    out = [0.0] * n
    if decay is None:
        decay = duration
    phase = 0.0
    for i in range(n):
        t = i / SR
        frac = t / duration if duration > 0 else 0
        freq = freq_start + (freq_end - freq_start) * frac
        phase += 2 * math.pi * freq / SR
        s = math.sin(phase)
        if t < attack:
            env = t / attack
        else:
            env = math.exp(-(t - attack) / decay * 5)
        out[i] = s * env * amp
    return out


def gen_noise_burst(duration, amp=0.3, decay=None):
    n = int(duration * SR)
    if decay is None:
        decay = duration
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t / decay * 6)
        out.append(random.uniform(-1, 1) * env * amp)
    return out


def _normalize(buf, target):
    peak = max(1e-9, max(abs(x) for x in buf))
    scale = target / peak
    return [x * scale for x in buf]


def mix(total_duration, segments):
    """segments: list de (start_time, samples). Normalizeaza mereu la
    aproape de scara maxima (nu doar cand ar da clipping) — altfel sunetele,
    randate initial cu amplitudini mici (0.2-0.9), ies mult prea incet
    chiar si la volum maxim pe telefon. Un soft-saturate (tanh) intre doua
    normalizari creste energia perceputa (RMS), nu doar varful."""
    n = int(total_duration * SR)
    buf = [0.0] * n
    for start_t, samples in segments:
        start = int(start_t * SR)
        for i, s in enumerate(samples):
            idx = start + i
            if 0 <= idx < n:
                buf[idx] += s
    buf = _normalize(buf, 0.9)
    buf = [math.tanh(x * 1.8) for x in buf]
    buf = _normalize(buf, 0.98)
    return buf


def save_wav(path, buf):
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in buf)
        f.writeframes(frames)


def build_next_tap():
    """Tock scurt si sec pentru butonul Next: coborare rapida de frecventa
    plus un mic transient pentru senzatia de "click" solid."""
    tone = gen_tone(950, 560, 0.09, attack=0.002, decay=0.045, amp=0.85)
    click = gen_tone(2200, 1800, 0.012, attack=0.001, decay=0.006, amp=0.35)
    buf = mix(0.13, [(0.0, tone), (0.0, click)])
    save_wav(f"{OUT_DIR}/next_tap.wav", buf)


def build_reward_pop():
    """Arpegiu ascendent tip "sparkle" pentru aparitia recompensei — cufarul
    care se deschide si monedele care explodeaza din el."""
    notes = [523.25, 659.25, 783.99, 1046.50]  # C5 E5 G5 C6
    segments = []
    whoosh = gen_noise_burst(0.05, amp=0.22, decay=0.03)
    segments.append((0.0, whoosh))
    for i, freq in enumerate(notes):
        start = i * 0.065
        amp = 0.55 - i * 0.04
        tone = gen_tone(freq, freq * 1.01, 0.16, attack=0.003, decay=0.14, amp=amp)
        segments.append((start, tone))
    buf = mix(0.6, segments)
    save_wav(f"{OUT_DIR}/reward_pop.wav", buf)


def build_tile_select():
    """Sunet cald si fin, pentru tap pe un gamemod — mult mai discret decat
    next_tap: atac moale, coborare usoara de ton, plus un substrat cald
    la o octava mai jos, ca sa nu fie ascutit."""
    main = gen_tone(500, 380, 0.14, attack=0.02, decay=0.12, amp=0.5)
    warmth = gen_tone(250, 190, 0.16, attack=0.025, decay=0.13, amp=0.22)
    buf = mix(0.2, [(0.0, main), (0.0, warmth)])
    save_wav(f"{OUT_DIR}/tile_select.wav", buf)


def build_coin_hit():
    """Ding metalic scurt pentru impactul monedei cu balanta — fundamentala
    + un supraton mai subtire, cu un mic bend de pitch la atac."""
    fundamental = gen_tone(850, 1250, 0.22, attack=0.003, decay=0.11, amp=0.8)
    overtone = gen_tone(1900, 2450, 0.16, attack=0.002, decay=0.07, amp=0.3)
    buf = mix(0.28, [(0.0, fundamental), (0.005, overtone)])
    save_wav(f"{OUT_DIR}/coin_hit.wav", buf)


def build_xp_hit():
    """Doua note distincte, ascendente ("ding-ding" de power-up), diferit
    de coin_hit (care e un singur bend continuu) — pentru impactul XP-ului
    in bara de nivel."""
    note1 = gen_tone(660, 700, 0.11, attack=0.004, decay=0.09, amp=0.6)
    note2 = gen_tone(880, 930, 0.16, attack=0.004, decay=0.13, amp=0.65)
    sparkle = gen_tone(1760, 1860, 0.08, attack=0.002, decay=0.06, amp=0.22)
    buf = mix(0.34, [(0.0, note1), (0.1, note2), (0.1, sparkle)])
    save_wav(f"{OUT_DIR}/xp_hit.wav", buf)


def build_heart_hit():
    """Doua pulsatii calde si rotunde, tip "bataie de inima" — mult mai jos
    si mai moale decat coin_hit/xp_hit, ca sa se simta distinct organic."""
    thump1 = gen_tone(180, 140, 0.09, attack=0.006, decay=0.07, amp=0.75)
    thump2 = gen_tone(200, 150, 0.11, attack=0.006, decay=0.09, amp=0.6)
    warmth = gen_tone(90, 70, 0.14, attack=0.008, decay=0.11, amp=0.3)
    buf = mix(0.32, [(0.0, thump1), (0.13, thump2), (0.0, warmth)])
    save_wav(f"{OUT_DIR}/heart_hit.wav", buf)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    random.seed(7)
    build_next_tap()
    build_reward_pop()
    build_tile_select()
    build_coin_hit()
    build_xp_hit()
    build_heart_hit()
    print(
        f"Scrise {OUT_DIR}/next_tap.wav, reward_pop.wav, tile_select.wav, "
        "coin_hit.wav, xp_hit.wav, heart_hit.wav"
    )


if __name__ == "__main__":
    main()
