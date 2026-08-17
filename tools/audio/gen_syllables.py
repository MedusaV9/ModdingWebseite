#!/usr/bin/env python3
"""gen_syllables.py — weiche Babbel-Silben für Gooby (AC-Gebrabbel).

Erzeugt 14 kurze WAVs (ba/bi/bu/bo/da/do/du/gu/ma/mi/na/pa/po/wa) nach dem
Synthese-Rezept von GOOBY/src/audio/goobyVoice.js:
  - Sinus-Grundton mit Toy-Squeak-Pitchkontur (start -> peak -> settle)
  - leichtes Vibrato (~7 Hz), warmer Ton (VOICE_WARMTH ~ -15% Pitch)
  - Vokalfarbe über additive Harmonische, gewichtet an Formanten F1/F2
  - Konsonant-Onsets: Plosiv (b/p/d/g = kurze Attack + Mini-Noise-Burst),
    Nasal (m/n = gesummter Vorlauf), Glide (w = u->Vokal-Übergang)

Aufruf (vom Repo-Root):
  python3 tools/audio/gen_syllables.py [--out GOOBY-GODOT/assets/audio/voice]
"""

import argparse
import os
import struct
import wave

import numpy as np

SR = 22050
# goobyVoice.js: VOICE_WARMTH faltet ~15% Pitch-Down in jede Stimme.
WARMTH = 0.85
BASE_F0 = 340.0 * WARMTH  # warmer Babbel-Grundton (~289 Hz)

# grobe Vokal-Formanten (F1, F2) in Hz
VOWELS = {
    "a": (800.0, 1200.0),
    "i": (320.0, 2300.0),
    "u": (350.0, 800.0),
    "o": (450.0, 900.0),
}

# Konsonant-Typ: (Art, Onset-Dauer s)
CONSONANTS = {
    "b": ("plosiv_weich", 0.015),
    "p": ("plosiv_hart", 0.020),
    "d": ("plosiv_weich", 0.015),
    "g": ("plosiv_dumpf", 0.020),
    "m": ("nasal", 0.060),
    "n": ("nasal", 0.055),
    "w": ("glide", 0.080),
}

SYLLABLES = [
    "ba", "bi", "bu", "bo",
    "da", "do", "du", "gu",
    "ma", "mi", "na",
    "pa", "po", "wa",
]


def harmonic_weights(f0, formants, n_harm=8):
    """Amplitude je Harmonische: 1/n-Abfall, angehoben nahe F1/F2."""
    f1, f2 = formants
    weights = []
    for n in range(1, n_harm + 1):
        f = f0 * n
        w = 1.0 / n
        for fc, boost, bw in ((f1, 2.2, 260.0), (f2, 1.2, 380.0)):
            w *= 1.0 + boost * np.exp(-((f - fc) ** 2) / (2 * bw**2))
        weights.append(w)
    weights = np.array(weights)
    return weights / weights.max()


def synth_syllable(syl, seed):
    rng = np.random.default_rng(seed)  # deterministisch pro Silbe
    cons, vowel = syl[0], syl[1]
    kind, onset = CONSONANTS[cons]
    dur = 0.16 + 0.03 * rng.random()
    n = int(SR * dur)
    t = np.arange(n) / SR

    # Toy-Squeak-Pitchkontur: start -> peak (bei ~25%) -> settle
    f0 = BASE_F0 * (1.0 + 0.06 * rng.standard_normal() * 0.5)
    start, peak, settle = f0 * 0.92, f0 * 1.10, f0 * 0.97
    k = np.minimum(t / (dur * 0.25), 1.0)
    pitch = start + (peak - start) * k
    rest = np.maximum(t - dur * 0.25, 0.0) / (dur * 0.75)
    pitch = pitch + (settle - peak) * rest * (t > dur * 0.25)
    # Vibrato ~7 Hz, ±1.5%
    pitch = pitch * (1.0 + 0.015 * np.sin(2 * np.pi * 7.0 * t))

    if kind == "glide":  # w: von /u/ in den Zielvokal gleiten
        wu = harmonic_weights(f0, VOWELS["u"])
        wv = harmonic_weights(f0, VOWELS[vowel])
        mix = np.minimum(t / onset, 1.0)
    else:
        wu = wv = harmonic_weights(f0, VOWELS[vowel])
        mix = np.ones(n)

    phase = 2 * np.pi * np.cumsum(pitch) / SR
    sig = np.zeros(n)
    for h, (a_u, a_v) in enumerate(zip(wu, wv), start=1):
        amp = a_u * (1 - mix) + a_v * mix
        sig += amp * np.sin(phase * h)

    # Hüllkurve: weicher Attack, runder Release
    attack = 0.035 if kind == "nasal" else 0.012
    env = np.minimum(t / attack, 1.0) * np.minimum((dur - t) / 0.05, 1.0)
    env = np.clip(env, 0.0, 1.0) ** 1.2

    if kind == "nasal":  # gesummter Vorlauf: nur Grundton, leiser
        lead = t < onset
        hum = 0.5 * np.sin(phase) * np.minimum(t / 0.02, 1.0)
        sig[lead] = hum[lead]
    elif kind.startswith("plosiv"):
        # Mini-Noise-Burst am Anfang (tiefpass-gefiltert, sehr kurz)
        nb = int(SR * onset)
        burst = rng.standard_normal(nb)
        cutoff = {"plosiv_weich": 900, "plosiv_hart": 1600, "plosiv_dumpf": 500}[kind]
        alpha = np.clip(2 * np.pi * cutoff / SR, 0, 1)
        for i in range(1, nb):
            burst[i] = burst[i - 1] + alpha * (burst[i] - burst[i - 1])
        level = 0.25 if kind == "plosiv_hart" else 0.12
        sig[:nb] += level * burst * np.linspace(1, 0, nb)

    out = sig * env
    out = 0.72 * out / max(np.abs(out).max(), 1e-9)
    return out


def write_wav(path, data):
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    default_out = os.path.join(
        os.path.dirname(__file__), "..", "..", "GOOBY-GODOT", "assets", "audio", "voice"
    )
    ap.add_argument("--out", default=default_out)
    args = ap.parse_args()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    for i, syl in enumerate(SYLLABLES):
        data = synth_syllable(syl, seed=1000 + i)
        path = os.path.join(out_dir, f"{syl}.wav")
        write_wav(path, data)
        print(f"[gen_syllables] {path} ({len(data) / SR * 1000:.0f} ms)")
    print(f"[gen_syllables] OK — {len(SYLLABLES)} Silben -> {out_dir}")


if __name__ == "__main__":
    main()
