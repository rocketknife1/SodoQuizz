# -*- coding: utf-8 -*-
"""Genereaza cele patru piese de fundal din catalogul de muzica al jocului.

De ce exista scriptul, si nu doar fisierele: piesele sunt SINTETIZATE din cod
(oscilatoare + filtre + un mic secventiator), nu inregistrate. Asta inseamna
ca se pot regla oricand — schimbi tempoul, tonalitatea sau melodia aici si
rulezi din nou, in loc sa cauti alt fisier. Vezi lib/core/music_tracks.dart
pentru numele sub care apar in joc.

BUCLA E CUSUTA, nu taiata: fiecare piesa se genereaza cu o coada in plus
(cateva secunde), iar coada se aduna INAPOI peste inceput. Asa, ecoul si
notele care se sting la finalul buclei continua peste inceputul ei — nu mai
exista taietura audibila la reluare. Fara asta, orice loop suna a "clic".

Rulare:  python tools/generate_music.py
Cere:    numpy + ffmpeg in PATH.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'music')

# ─────────────────────────── unelte de baza ────────────────────────────────


def midi(note):
    """'A4' / 'C#3' -> frecventa in Hz."""
    names = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6,
             'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11}
    name = note[:-1]
    octave = int(note[-1])
    n = names[name] + (octave + 1) * 12
    return 440.0 * (2 ** ((n - 69) / 12.0))


def phase(freq, n, detune=0.0):
    """Faza acumulata — accepta si un vector de frecvente (pentru glissando)."""
    f = np.full(n, freq, dtype=np.float64) if np.isscalar(freq) else freq
    return np.cumsum(2 * np.pi * (f * (1 + detune)) / SR)


def sine(freq, n, detune=0.0):
    return np.sin(phase(freq, n, detune))


def saw(freq, n, detune=0.0):
    p = phase(freq, n, detune)
    return 2.0 * ((p / (2 * np.pi)) % 1.0) - 1.0


def square(freq, n, duty=0.5, detune=0.0):
    p = (phase(freq, n, detune) / (2 * np.pi)) % 1.0
    return np.where(p < duty, 1.0, -1.0)


def triangle(freq, n, detune=0.0):
    p = (phase(freq, n, detune) / (2 * np.pi)) % 1.0
    return 4.0 * np.abs(p - 0.5) - 1.0


def noise(n):
    return np.random.uniform(-1.0, 1.0, n)


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    """Anvelopa clasica, in secunde pentru a/d/r; s e nivelul de sustinere."""
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    ns = max(0, n - na - nd - nr)
    parts = [
        np.linspace(0, 1, na, endpoint=False) if na else np.array([]),
        np.linspace(1, s, nd, endpoint=False) if nd else np.array([]),
        np.full(ns, s),
        np.linspace(s, 0, nr) if nr else np.array([]),
    ]
    env = np.concatenate([p for p in parts if p.size])
    if env.size < n:
        env = np.pad(env, (0, n - env.size))
    return env[:n]


def lowpass(x, cutoff):
    """Filtru one-pole. `cutoff` poate fi un vector (filtru care se misca)."""
    c = np.full(x.size, cutoff, dtype=np.float64) if np.isscalar(cutoff) else cutoff
    alpha = 1.0 - np.exp(-2.0 * np.pi * np.clip(c, 20, SR / 2.2) / SR)
    out = np.empty_like(x)
    y = 0.0
    for i in range(x.size):
        y += alpha[i] * (x[i] - y)
        out[i] = y
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


class Track:
    """O piesa in constructie: un buffer lung, in care se 'lipesc' sunete."""

    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buf = np.zeros(self.n)

    def add(self, at, samples, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= self.n:
            return
        seg = samples[:self.n - i]
        self.buf[i:i + seg.size] += seg * gain
        self._pan = pan  # nefolosit in mono; pastrat pentru claritate

    def data(self):
        return self.buf


def stitch_loop(buf, loop_seconds, tail_seconds):
    """Aduna coada peste inceput si taie exact la lungimea buclei."""
    ln = int(loop_seconds * SR)
    tn = int(tail_seconds * SR)
    out = buf[:ln].copy()
    tail = buf[ln:ln + tn]
    out[:tail.size] += tail
    return out


# Volumul piesei originale a jocului, masurat cu `ffmpeg -af loudnorm` pe
# theme_loop.mp3. Piesele noi se aduc la ACELASI nivel, altfel schimbarea
# piesei din meniu ar suna si ca o schimbare de volum — o piesa sintetizata
# iese natural cu 8-12 dB mai incet decat una masterizata, iar jucatorul ar
# crede ca s-a stricat ceva.
TARGET_LUFS = -10.6

# Plafonul de varf cerut limitatorului. E cu mult sub 0 dB DELIBERAT: masurat,
# encodarea MP3 adauga ~2,5 dB de supraoscilatie intre esantioane, asa ca un
# plafon de -1 dB iesea din fisier la +1,5 dB, adica taiat pe unele telefoane.
# Cu -3,5 dB inainte de encodare, fisierul final sta sub zero.
TARGET_TRUE_PEAK = -3.5


def _measure_loudness(wav_path):
    """Prima trecere loudnorm — intoarce valorile masurate, ca a doua trecere
    sa poata normaliza exact (loudnorm cu o singura trecere e aproximativ)."""
    import json
    proc = subprocess.run(
        ['ffmpeg', '-hide_banner', '-nostats', '-i', wav_path,
         '-af', 'loudnorm=I=%s:TP=%s:print_format=json' % (TARGET_LUFS, TARGET_TRUE_PEAK),
         '-f', 'null', os.devnull],
        capture_output=True, text=True)
    text = proc.stderr
    start = text.rfind('{')
    end = text.rfind('}')
    if start == -1 or end == -1:
        return None
    try:
        return json.loads(text[start:end + 1])
    except ValueError:
        return None


def write_mp3(left, right, path, bitrate='128k'):
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)), 1e-9)
    left, right = left / peak * 0.89, right / peak * 0.89
    stereo = np.empty(left.size * 2, dtype=np.float64)
    stereo[0::2] = left
    stereo[1::2] = right
    pcm = (np.clip(stereo, -1, 1) * 32767).astype('<i2')

    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        wav_path = tmp.name
    try:
        with wave.open(wav_path, 'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())

        # Lant de "masterizare", in ordinea asta si nu alta:
        #   acompressor — strange dinamica, ca media sa poata urca fara ca
        #     loviturile de toba sa loveasca plafonul;
        #   loudnorm    — aduce la nivelul piesei originale. DINAMIC, nu
        #     `linear=true`: varianta liniara aplica un singur castig pe toata
        #     piesa si refuza sa urce cat trebuie (masurat: se oprea cu ~2-5 dB
        #     sub tinta), lasand piesele noi audibil mai incete;
        #   alimiter    — ultimul, ca plafonul de varf sa fie garantat. Fara
        #     el, loudnorm scotea varfuri peste 0 dB (masurat +2,3 dB), adica
        #     distorsiune la redare.
        m = _measure_loudness(wav_path)
        measured = ''
        if m:
            measured = (':measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s'
                        % (m['input_i'], m['input_tp'], m['input_lra'], m['input_thresh']))
        af = ('acompressor=threshold=0.08:ratio=4:attack=10:release=180:makeup=2,'
              'loudnorm=I=%s:TP=%s%s,'
              # `level=disabled` e OBLIGATORIU: alimiter are auto-level pornit
              # implicit, care re-ridica iesirea la maxim dupa ce a limitat —
              # adica anuleaza exact ce i-ai cerut. Masurat: cu el pornit,
              # varful ramanea la +1,6 dB oricat de jos puneam plafonul.
              'alimiter=limit=%.4f:attack=5:release=50:level=disabled'
              % (TARGET_LUFS, TARGET_TRUE_PEAK, measured,
                 10 ** (TARGET_TRUE_PEAK / 20.0)))

        subprocess.run(
            ['ffmpeg', '-y', '-loglevel', 'error', '-i', wav_path,
             '-af', af, '-ar', str(SR),
             '-codec:a', 'libmp3lame', '-b:a', bitrate, path],
            check=True)
    finally:
        os.unlink(wav_path)
    return os.path.getsize(path)


# ─────────────────────────── instrumente ────────────────────────────────────


def kick(dur=0.28, f0=120.0, f1=45.0):
    n = int(dur * SR)
    f = f1 + (f0 - f1) * np.exp(-np.linspace(0, 1, n) * 9)
    body = np.sin(phase(f, n)) * adsr(n, 0.001, 0.05, 0.35, dur - 0.06)
    click = noise(int(0.006 * SR)) * np.linspace(1, 0, int(0.006 * SR)) * 0.5
    body[:click.size] += click
    return body


def snare(dur=0.20, tone=190.0, bright=3500.0):
    n = int(dur * SR)
    body = highpass(noise(n), 900) * adsr(n, 0.001, 0.08, 0.2, dur - 0.09)
    body += np.sin(phase(tone, n)) * adsr(n, 0.001, 0.05, 0.0, 0.02) * 0.5
    return lowpass(body, bright)


def hat(dur=0.055, open_=False):
    d = 0.22 if open_ else dur
    n = int(d * SR)
    return highpass(noise(n), 6500) * adsr(n, 0.001, d * 0.5, 0.12, d * 0.4)


def pluck(freq, dur, wave_fn=square, duty=None, a=0.005, d=0.06, s=0.55, r=0.09):
    n = int(dur * SR)
    osc = wave_fn(freq, n, duty) if duty is not None else wave_fn(freq, n)
    return osc * adsr(n, a, d, s, max(r, 0.02))


def pad(freqs, dur, detunes=(-0.004, 0.0, 0.004), cutoff=1500, a=0.5, r=0.9):
    n = int(dur * SR)
    acc = np.zeros(n)
    for f in freqs:
        for dt in detunes:
            acc += saw(f, n, dt)
    acc /= (len(freqs) * len(detunes))
    return lowpass(acc, cutoff) * adsr(n, a, 0.3, 0.75, r)


# ─────────────────────────── piesele ────────────────────────────────────────


def retro_arcade():
    """Chiptune 8-bit, vioi — pentru cei mici si nostalgici. La minor, 142 BPM."""
    bpm, bars = 142.0, 24
    beat = 60.0 / bpm
    bar = beat * 4
    total = bars * bar
    t = Track(total + 4)

    # Bas pe optimi, urmarind progresia Am - F - C - G
    roots = ['A2', 'F2', 'C3', 'G2']
    for b in range(bars):
        r = midi(roots[b % 4])
        for e in range(8):
            t.add(b * bar + e * beat / 2,
                  pluck(r, beat * 0.46, square, duty=0.5, d=0.04, s=0.42, r=0.05),
                  gain=0.30)

    # Arpegii rapide de triunghi (16-imi), acordul barei
    chords = [['A3', 'C4', 'E4'], ['F3', 'A3', 'C4'], ['C4', 'E4', 'G4'], ['G3', 'B3', 'D4']]
    for b in range(bars):
        ch = chords[b % 4]
        for s16 in range(16):
            f = midi(ch[s16 % 3])
            t.add(b * bar + s16 * beat / 4,
                  pluck(f, beat * 0.22, triangle, a=0.002, d=0.03, s=0.35, r=0.04),
                  gain=0.17)

    # Melodie de square, pentatonica — doua fraze de 4 bari, repetate
    phrase_a = [('A4', 1.0), ('C5', 0.5), ('D5', 0.5), ('E5', 1.0), ('D5', 0.5), ('C5', 0.5),
                ('A4', 1.0), ('G4', 0.5), ('A4', 0.5), ('E4', 2.0)]
    phrase_b = [('C5', 1.0), ('E5', 0.5), ('G5', 0.5), ('E5', 1.0), ('D5', 1.0),
                ('C5', 0.5), ('D5', 0.5), ('E5', 1.0), ('A4', 2.0)]
    pos = 0.0
    while pos < total - 0.5:
        for name, beats in (phrase_a if int(pos / (bar * 4)) % 2 == 0 else phrase_b):
            if pos >= total:
                break
            dur = beats * beat
            t.add(pos, pluck(midi(name), dur * 0.92, square, duty=0.25,
                             a=0.004, d=0.05, s=0.6, r=0.08), gain=0.26)
            pos += dur

    # Tobe
    for b in range(bars):
        t.add(b * bar, kick(), gain=0.85)
        t.add(b * bar + beat * 2, kick(), gain=0.8)
        t.add(b * bar + beat, snare(), gain=0.42)
        t.add(b * bar + beat * 3, snare(), gain=0.42)
        for e in range(8):
            t.add(b * bar + e * beat / 2, hat(), gain=0.16)

    return stitch_loop(t.data(), total, 3.0), total


def lofi_chill():
    """Lo-fi relaxat — pentru sesiuni lungi. Fa major cu septime, 76 BPM."""
    bpm, bars = 76.0, 16
    beat = 60.0 / bpm
    bar = beat * 4
    total = bars * bar
    t = Track(total + 5)

    # Fmaj7 - Dm7 - Gm7 - C7, cate un acord pe bara
    prog = [
        ['F3', 'A3', 'C4', 'E4'],
        ['D3', 'F3', 'A3', 'C4'],
        ['G3', 'A#3', 'D4', 'F4'],
        ['C3', 'E3', 'G3', 'A#3'],
    ]
    bass_notes = ['F2', 'D2', 'G2', 'C2']

    for b in range(bars):
        ch = [midi(x) for x in prog[b % 4]]
        t.add(b * bar, pad(ch, bar * 0.98, cutoff=1250, a=0.35, r=0.8), gain=0.42)
        # cateva note de pian moale, deplasate ritmic (senzatie de swing lene)
        for k, off in enumerate([0.0, 1.5, 2.5]):
            f = ch[(k + b) % len(ch)] * 2
            t.add(b * bar + off * beat,
                  lowpass(pluck(f, beat * 1.1, triangle, a=0.01, d=0.25, s=0.3, r=0.5), 2200),
                  gain=0.20)
        # bas rotund
        bf = midi(bass_notes[b % 4])
        t.add(b * bar, lowpass(pluck(bf, beat * 1.7, sine, a=0.02, d=0.3, s=0.6, r=0.4), 420), gain=0.52)
        t.add(b * bar + beat * 2.5,
              lowpass(pluck(bf, beat * 1.0, sine, a=0.02, d=0.25, s=0.5, r=0.3), 420), gain=0.38)

        # tobe moi, cu hi-hat in swing
        t.add(b * bar, kick(0.32, 95, 42), gain=0.62)
        t.add(b * bar + beat * 2.5, kick(0.32, 95, 42), gain=0.5)
        t.add(b * bar + beat, lowpass(snare(0.16, 170, 2200), 2600), gain=0.3)
        t.add(b * bar + beat * 3, lowpass(snare(0.16, 170, 2200), 2600), gain=0.3)
        for e in range(8):
            swing = 0.06 * beat if e % 2 else 0.0
            t.add(b * bar + e * beat / 2 + swing, lowpass(hat(0.05), 9000), gain=0.09)

    # zgomot de vinil: fasait continuu + pocnete rare
    buf = t.data()
    hiss = lowpass(noise(buf.size), 5200) * 0.012
    buf += hiss
    rng = np.random.default_rng(7)
    for _ in range(int(total * 2.2)):
        i = rng.integers(0, buf.size - 400)
        crack = noise(220) * np.exp(-np.linspace(0, 8, 220)) * rng.uniform(0.02, 0.07)
        buf[i:i + 220] += crack

    return stitch_loop(buf, total, 4.0), total


def epic_quest():
    """Orchestral-cinematic (sintetic) — atmosfera de mare aventura. Re minor, 96 BPM."""
    bpm, bars = 96.0, 20
    beat = 60.0 / bpm
    bar = beat * 4
    total = bars * bar
    t = Track(total + 5)

    # Dm - B♭ - F - C, doua bari fiecare
    prog = [
        ['D3', 'F3', 'A3', 'D4'],
        ['A#2', 'D3', 'F3', 'A#3'],
        ['F3', 'A3', 'C4', 'F4'],
        ['C3', 'E3', 'G3', 'C4'],
    ]
    for b in range(bars):
        ch = [midi(x) for x in prog[(b // 2) % 4]]
        # corzi: atac lent, larg
        t.add(b * bar, pad(ch, bar * 1.05, detunes=(-0.006, -0.002, 0.002, 0.006),
                           cutoff=1700, a=0.65, r=1.1), gain=0.40)
        # "alamuri": acelasi acord, atac scurt, doar pe barile pare
        if b % 2 == 0:
            n = int(bar * 0.55 * SR)
            brass = np.zeros(n)
            for f in ch:
                brass += saw(f, n, -0.003) + saw(f, n, 0.003)
            brass /= len(ch) * 2
            t.add(b * bar, lowpass(brass, 2400) * adsr(n, 0.08, 0.2, 0.7, 0.5), gain=0.30)

    # tobe mari (timpani-ish) — doua lovituri pe bara, mai dese spre final
    for b in range(bars):
        t.add(b * bar, kick(0.6, 150, 55), gain=0.95)
        t.add(b * bar + beat * 2, kick(0.5, 140, 52), gain=0.7)
        if b % 4 == 3:
            for e in range(4):
                t.add(b * bar + beat * 3 + e * beat / 4, kick(0.28, 160, 60), gain=0.5)

    # linie melodica inalta, tip cor/corn
    melody = [('D5', 2), ('F5', 1), ('E5', 1), ('D5', 2), ('A4', 2),
              ('A#4', 2), ('D5', 1), ('C5', 1), ('A4', 4),
              ('F5', 2), ('E5', 1), ('D5', 1), ('C5', 2), ('A4', 2),
              ('D5', 4), ('A4', 4)]
    pos = 0.0
    while pos < total - 1.0:
        for name, beats in melody:
            if pos >= total:
                break
            dur = beats * beat
            n = int(dur * 0.95 * SR)
            f = midi(name)
            vib = 1 + 0.004 * np.sin(np.linspace(0, dur * 2 * np.pi * 5, n))
            voice = lowpass(saw(f * vib, n, 0.0) * 0.6 + sine(f * vib, n) * 0.4, 2000)
            t.add(pos, voice * adsr(n, 0.15, 0.25, 0.72, 0.4), gain=0.26)
            pos += dur

    return stitch_loop(t.data(), total, 4.0), total


def funky_groove():
    """Funk vesel, cu ritm — bun la orice varsta. Mi minor, 108 BPM."""
    bpm, bars = 108.0, 20
    beat = 60.0 / bpm
    bar = beat * 4
    total = bars * bar
    t = Track(total + 4)

    # Bas cu filtru care se misca (senzatie de "wah")
    bass_line = [(0.0, 'E2', 0.5), (0.75, 'E2', 0.25), (1.5, 'G2', 0.5),
                 (2.0, 'A2', 0.5), (2.75, 'E2', 0.25), (3.25, 'D2', 0.75)]
    for b in range(bars):
        shift = 0 if b % 4 < 2 else 3  # ridica fraza cu o terta la fiecare 2 bari
        for off, name, dur_beats in bass_line:
            f = midi(name) * (2 ** (shift / 12.0))
            n = int(dur_beats * beat * SR)
            osc = saw(f, n) * 0.6 + square(f, n, 0.5) * 0.4
            sweep = 280 + 2600 * np.exp(-np.linspace(0, 4, n))
            t.add(b * bar + off * beat,
                  lowpass(osc, sweep) * adsr(n, 0.004, 0.06, 0.55, 0.06), gain=0.44)

    # Stab-uri de clavinet pe contratimp
    stab_chords = [['E4', 'G4', 'B4'], ['D4', 'F#4', 'A4'], ['C4', 'E4', 'G4'], ['B3', 'D4', 'F#4']]
    for b in range(bars):
        ch = [midi(x) for x in stab_chords[b % 4]]
        for off in (1.75, 2.5, 3.75):
            n = int(0.16 * SR)
            s = np.zeros(n)
            for f in ch:
                s += saw(f, n)
            s /= len(ch)
            t.add(b * bar + off * beat,
                  highpass(lowpass(s, 3200), 220) * adsr(n, 0.003, 0.05, 0.25, 0.08),
                  gain=0.24)

    # Tobe: kick sincopat, snare pe 2 si 4, hi-hat pe saisprezecimi
    for b in range(bars):
        for off in (0.0, 1.75, 2.5):
            t.add(b * bar + off * beat, kick(0.24, 125, 48), gain=0.85)
        t.add(b * bar + beat, snare(0.18, 210, 4200), gain=0.5)
        t.add(b * bar + beat * 3, snare(0.18, 210, 4200), gain=0.5)
        for s16 in range(16):
            openh = (s16 % 8 == 7)
            t.add(b * bar + s16 * beat / 4, hat(open_=openh),
                  gain=0.13 if not openh else 0.10)

    return stitch_loop(t.data(), total, 3.0), total


# ─────────────────────────── rulare ─────────────────────────────────────────

TRACKS = [
    ('arcade_loop.mp3', retro_arcade, 'Retro Arcade  (chiptune 8-bit)'),
    ('lofi_loop.mp3', lofi_chill, 'Lofi Chill    (relaxat)'),
    ('epic_loop.mp3', epic_quest, 'Epic Quest    (orchestral)'),
    ('funk_loop.mp3', funky_groove, 'Funky Groove  (funk vesel)'),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for filename, fn, label in TRACKS:
        np.random.seed(abs(hash(filename)) % (2 ** 31))  # reproductibil
        mono, seconds = fn()
        # Un pic de latime stereo: canalul drept intarziat cu ~11 ms.
        delay = int(0.011 * SR)
        right = np.concatenate([np.zeros(delay), mono[:-delay]]) * 0.85 + mono * 0.15
        path = os.path.join(OUT_DIR, filename)
        size = write_mp3(mono, right, path)
        # Verificare de bucla: capetele trebuie sa fie apropiate ca nivel,
        # altfel reluarea se aude ca un pocnet.
        head = float(np.sqrt(np.mean(mono[:2000] ** 2)))
        tail = float(np.sqrt(np.mean(mono[-2000:] ** 2)))
        print('%-14s %-32s %5.1fs  %6.1f KB  capete: %.3f / %.3f'
              % (filename, label, seconds, size / 1024.0, head, tail))


if __name__ == '__main__':
    sys.exit(main())
