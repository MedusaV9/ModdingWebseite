#!/usr/bin/env python3
"""ef2_gen_sfx.py — EF-2-SFX-Werkbank (EVAL-1 S1/S3/S4/S5 + Lueckenschluss).

1. NEUE weiche Sounds (numpy-Synthese im Stil der soft/-Familie, weiche
   Huellkurven, kein hartes Klicken):
     soft/soft_collect.ogg     — warmer ~1,2-kHz-Pluck (ersetzt grelles
                                 glass_004 fuer gvz_collect, S4)
     soft/soft_win.ogg         — Dur-Dreiklang-Pluck 659/831/988 Hz
                                 (ersetzt grelles confirmation_003, S6)
     soft/soft_care_erfolg.ogg — Pflege-Erfolgs-Pluck (ui_confirm-Familie,
                                 +2 Halbtoene, D6)
     foley/care_wasser.ogg     — Dusch-Wasserloop (loopbar, F7)
     foley/care_buersten.ogg   — Zahnputz-Schrubbloop (loopbar)
     foley/care_spuelung.ogg   — Klo-Spuelung/Abfluss-Whoosh
     foley/pet_squish.ogg      — Streichel-Squish (D5)
     foley/step_tap.ogg        — leises Schritt-Tapsen (D4/F8)
     foley/nom_nom.ogg         — Futter-Kaublip (D1)
     foley/travel_whoosh_auf.ogg / _zu.ogg — Reise-Whoosh-Paar (F9)
2. FIXES an Bestandsdateien (assets/audio, Ranch bleibt unberuehrt):
     - Peak-Normalisierung aller gemappten Quelldateien auf <= -1 dBFS
       (20 Kenney-Impacts peakten ueber 0 dBFS)
     - game_hit.ogg: 30-ms-Fade-out gegen den Abschneide-Klick (S5)
     - soft_open/soft_close: 20-ms-Fade-out (Restpegel -25 dBFS)
     - game_whoosh.ogg: +4,7 dB (war mit -29,5 dBFS eff. unhoerbar)
3. Babble-WAVs (assets/audio/voice): auf -16 dBFS RMS angeglichen,
   Peak <= -3 dBFS (S3 — vorher -8..-14 dBFS, lauteste Sounds im Spiel).

Aufruf: python3 tools/audio/ef2_gen_sfx.py
"""

import json
import math
import os
import subprocess
import sys
import wave

import numpy as np

ROOT = "/workspace/GOOBY-GODOT"
SFX = os.path.join(ROOT, "assets/audio/sfx")
VOICE = os.path.join(ROOT, "assets/audio/voice")
SR = 44100

VOICE_RMS_DB = -16.0
VOICE_PEAK_CAP = -3.0
PEAK_CEIL_DB = -1.0


def db(x):
    return 20.0 * math.log10(max(x, 1e-12))


def lin(x_db):
    return 10.0 ** (x_db / 20.0)


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=sample_rate,channels", "-of", "csv=p=0", path],
        capture_output=True, text=True).stdout.strip().split(",")
    return int(out[0]), int(out[1])


def decode(path, sr, ch):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le",
         "-acodec", "pcm_f32le", "-ac", str(ch), "-ar", str(sr), "-"],
        capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def encode_ogg(path, x, sr, quality=7):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr),
         "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", str(quality), path],
        input=x.astype(np.float32).tobytes(), check=True)


def report_line(tag, rel, x):
    print("[%s] %-38s dur %5.0f ms  rms %6.1f  peak %5.1f"
          % (tag, rel, 1000.0 * x.size / SR,
             db(float(np.sqrt(np.mean(x ** 2)))), db(float(np.max(np.abs(x))))))


# ── Synthese-Bausteine ───────────────────────────────────────────────────────


def _env(n, attack_s, release_s, sr=SR):
    t = np.arange(n) / sr
    dur = n / sr
    a = np.clip(t / max(attack_s, 1e-4), 0.0, 1.0)
    r = np.clip((dur - t) / max(release_s, 1e-4), 0.0, 1.0)
    return (0.5 - 0.5 * np.cos(a * math.pi)) * (0.5 - 0.5 * np.cos(r * math.pi))


def _pluck(notes, dur, attack=0.006, sr=SR):
    """notes: Liste (freq, amp, onset_s, tau_s) — Sinus-Partialtoene mit
    exponentiellem Ausklang und weichem Attack (soft/-Familienrezept)."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    sig = np.zeros(n)
    for freq, amp, onset, tau in notes:
        tt = t - onset
        gate = tt >= 0.0
        local = np.where(gate, tt, 0.0)
        tone = np.sin(2 * math.pi * freq * local) * np.exp(-local / tau)
        att = np.clip(local / attack, 0.0, 1.0)
        sig += amp * tone * (0.5 - 0.5 * np.cos(att * math.pi)) * gate
    sig *= _env(n, attack, 0.05)
    return sig


def _shaped_noise(n, mag_fn, seed):
    """Periodisches Rauschen mit Wunsch-Spektrum (ifft mit Zufallsphasen) —
    zirkular, also von Natur aus knackfrei loopbar."""
    rng = np.random.default_rng(seed)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    mag = mag_fn(freqs)
    phase = rng.uniform(0, 2 * math.pi, freqs.size)
    spec = mag * np.exp(1j * phase)
    spec[0] = 0.0
    x = np.fft.irfft(spec, n)
    return x / max(np.abs(x).max(), 1e-12)


def _fft_lowpass(x, cutoff, order=2):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(x.size, 1 / SR)
    spec *= 1.0 / (1.0 + (freqs / cutoff) ** (2 * order))
    return np.fft.irfft(spec, x.size)


def _norm_peak(x, peak_db_target):
    return x * (lin(peak_db_target) / max(np.abs(x).max(), 1e-12))


def _sweep(f0, f1, n, sr=SR):
    t = np.arange(n) / sr
    freq = f0 + (f1 - f0) * (t / (n / sr))
    return np.sin(2 * math.pi * np.cumsum(freq) / sr)


# ── Neue Sounds ──────────────────────────────────────────────────────────────


def gen_soft_collect():
    # Warmer Sammel-Pluck ~1,2 kHz — statt 7,3-kHz-Glas-Klirren (S4).
    sig = _pluck([
        (880.0, 0.35, 0.0, 0.05),
        (1174.7, 1.0, 0.012, 0.075),
        (1568.0, 0.28, 0.012, 0.05),
        (2349.3, 0.08, 0.012, 0.035),
    ], 0.26)
    return _norm_peak(sig, -4.5)


def gen_soft_win():
    # Dur-Dreiklang (E5/Gis5/H5) mit warmem Oktav-Fundament — AC-weich (S6).
    sig = _pluck([
        (329.6, 0.25, 0.0, 0.16),
        (659.3, 1.0, 0.0, 0.14),
        (830.6, 0.85, 0.07, 0.13),
        (987.8, 0.75, 0.14, 0.13),
        (1318.5, 0.12, 0.14, 0.08),
    ], 0.40)
    return _norm_peak(sig, -4.5)


def gen_soft_care_erfolg():
    # Pflege-Erfolg: ui_confirm-Familie, +2 Halbtoene (D5 -> A5, D6-Rezept).
    sig = _pluck([
        (587.3, 1.0, 0.0, 0.11),
        (1174.7, 0.15, 0.0, 0.06),
        (880.0, 0.9, 0.11, 0.13),
        (1760.0, 0.1, 0.11, 0.06),
    ], 0.38)
    return _norm_peak(sig, -4.5)


def gen_care_wasser():
    # Dusch-Loop 3,5 s: dunkles Wasserrauschen + leises Tropfen-Glitzern,
    # Amplituden-Wobble mit ganzzahligen Zyklen -> nahtlos loopbar.
    n = int(3.5 * SR)
    body = _shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 650.0) ** 1.6), 41)
    sizzle = _shaped_noise(
        n, lambda f: np.exp(-((f - 2400.0) / 1100.0) ** 2), 42)
    t = np.arange(n) / SR
    wob = (1.0 + 0.16 * np.sin(2 * math.pi * 2.0 * t)
           + 0.09 * np.sin(2 * math.pi * 7.0 * t + 1.3))
    sig = (body + 0.10 * sizzle) * wob
    return _norm_peak(sig, -6.0)


def gen_care_buersten():
    # Zahnputz-Loop 2,0 s: 6 weiche Schrubb-Striche (3 Hz), Band um 1,6 kHz.
    n = int(2.0 * SR)
    noise = _shaped_noise(
        n, lambda f: np.exp(-((f - 1600.0) / 900.0) ** 2)
        + 0.25 / (1.0 + (f / 500.0) ** 2), 43)
    t = np.arange(n) / SR
    strokes = 0.12 + 0.88 * np.clip(np.sin(2 * math.pi * 3.0 * t), 0.0, 1.0) ** 1.5
    return _norm_peak(noise * strokes, -6.5)


def gen_care_spuelung():
    # Spuelung 1,5 s: Whoosh von hell nach dunkel + Gurgel-Wobble, weich aus.
    n = int(1.5 * SR)
    t = np.arange(n) / SR
    u = t / (n / SR)
    low = _shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 320.0) ** 2), 44)
    mid = _shaped_noise(n, lambda f: np.exp(-((f - 900.0) / 500.0) ** 2), 45)
    high = _shaped_noise(n, lambda f: np.exp(-((f - 2100.0) / 900.0) ** 2), 46)
    gurgle = 1.0 + 0.35 * np.sin(2 * math.pi * 24.0 * t) * (1.0 - u)
    sig = (high * (1.0 - u) ** 1.5 + mid * 0.8 * (1.0 - 0.4 * u)
           + low * (0.4 + 0.9 * u) * gurgle)
    sig *= _env(n, 0.06, 0.35)
    return _norm_peak(sig, -6.0)


def gen_pet_squish():
    # Streichel-Squish 150 ms: runder Pitch-Fall + winziger Luft-Puff.
    n = int(0.15 * SR)
    body = _sweep(300.0, 185.0, n) * np.exp(-np.arange(n) / SR / 0.055)
    puff = _fft_lowpass(np.random.default_rng(47).standard_normal(n), 850.0)
    puff *= np.exp(-np.arange(n) / SR / 0.02)
    sig = (body + 0.18 * puff / max(np.abs(puff).max(), 1e-12)) * _env(n, 0.008, 0.04)
    return _norm_peak(sig, -5.0)


def gen_step_tap():
    # Schritt-Taps 90 ms: dumpfer Mini-Thump, sehr weich (Ziel eff. ~ -28 dB).
    n = int(0.09 * SR)
    body = _sweep(175.0, 120.0, n) * np.exp(-np.arange(n) / SR / 0.03)
    tick = _fft_lowpass(np.random.default_rng(48).standard_normal(n), 1200.0)
    tick *= np.exp(-np.arange(n) / SR / 0.006)
    sig = (body + 0.10 * tick / max(np.abs(tick).max(), 1e-12)) * _env(n, 0.004, 0.03)
    return _norm_peak(sig, -6.0)


def gen_nom_nom():
    # Kau-Blip 220 ms: zwei runde Nom-Silben (fuer D1-Fuettern; Pitch-Jitter
    # macht aus einer Datei drei Kau-Varianten).
    n = int(0.22 * SR)
    sig = np.zeros(n)
    rng = np.random.default_rng(49)
    for onset, f0 in ((0.0, 235.0), (0.105, 205.0)):
        i0 = int(onset * SR)
        m = int(0.09 * SR)
        blip = _sweep(f0, f0 * 0.62, m) * np.exp(-np.arange(m) / SR / 0.035)
        chew = _fft_lowpass(rng.standard_normal(m), 620.0)
        blip = blip + 0.22 * chew / max(np.abs(chew).max(), 1e-12)
        sig[i0: i0 + m] += blip * _env(m, 0.01, 0.03)
    return _norm_peak(sig * _env(n, 0.005, 0.04), -5.0)


def _whoosh(up):
    n = int(0.30 * SR)
    t = np.arange(n) / SR
    u = t / (n / SR)
    glide = u if up else (1.0 - u)
    lowb = _shaped_noise(n, lambda f: np.exp(-((f - 380.0) / 260.0) ** 2), 50)
    highb = _shaped_noise(n, lambda f: np.exp(-((f - 1050.0) / 500.0) ** 2), 51)
    sig = lowb * (1.0 - glide) + highb * glide
    sig *= np.sin(math.pi * u) ** 1.4
    return _norm_peak(sig, -7.0)


# ── Fixes an Bestandsdateien ────────────────────────────────────────────────


def fade_out(x, sr, ms):
    n = min(int(ms / 1000.0 * sr), x.size)
    if n <= 1:
        return x
    y = x.copy()
    y[-n:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, math.pi, n))
    return y


def fix_existing():
    fixes = []
    # 30-ms-Fade gegen den End-Klick des meistgespielten Sounds (S5) +
    # 20 ms fuer die beiden soft-Ausreisser (Restpegel ~ -25 dBFS).
    for rel, ms in (("game/game_hit.ogg", 30), ("soft/soft_open.ogg", 20),
                    ("soft/soft_close.ogg", 20)):
        path = os.path.join(SFX, rel)
        sr, _ch = probe(path)
        x = decode(path, sr, 1)
        x = fade_out(x, sr, ms)
        encode_ogg(path, x, sr)
        fixes.append((rel, "fade %d ms" % ms))
    # game_whoosh war 13 dB unter der Familie — anheben, Peak-Deckel haelt.
    path = os.path.join(SFX, "game/game_whoosh.ogg")
    sr, _ch = probe(path)
    x = decode(path, sr, 1)
    gain = min(4.7, PEAK_CEIL_DB - db(float(np.max(np.abs(x)))))
    encode_ogg(path, x * lin(gain), sr)
    fixes.append(("game/game_whoosh.ogg", "gain %+.1f dB" % gain))
    # Peak-Normalisierung: alles Gemappte unter assets/audio/sfx mit
    # Quell-Peak > -1 dBFS (Kenney-Impacts, S1/2.2).
    for dirpath, _dirs, files in os.walk(SFX):
        for fn in sorted(files):
            if not fn.endswith(".ogg"):
                continue
            path = os.path.join(dirpath, fn)
            sr, _ch = probe(path)
            x = decode(path, sr, 1)
            peak = db(float(np.max(np.abs(x))))
            if peak <= PEAK_CEIL_DB:
                continue
            for attempt in range(3):
                gain = PEAK_CEIL_DB - peak - 0.1 * attempt
                encode_ogg(path, x * lin(gain), sr)
                chk = decode(path, sr, 1)
                if db(float(np.max(np.abs(chk)))) <= PEAK_CEIL_DB + 0.05:
                    break
            fixes.append((os.path.relpath(path, SFX), "peak %+.1f dB" % gain))
    for rel, what in fixes:
        print("[fix ] %-38s %s" % (rel, what))


def normalize_voice():
    for fn in sorted(os.listdir(VOICE)):
        if not fn.endswith(".wav"):
            continue
        path = os.path.join(VOICE, fn)
        with wave.open(path, "rb") as w:
            sr = w.getframerate()
            n = w.getnframes()
            raw = w.readframes(n)
        x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32767.0
        rms = db(float(np.sqrt(np.mean(x ** 2))))
        peak = db(float(np.max(np.abs(x))))
        gain = min(VOICE_RMS_DB - rms, VOICE_PEAK_CAP - peak)
        y = np.clip(x * lin(gain), -1.0, 1.0)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes((y * 32767.0).astype("<i2").tobytes())
        print("[voice] %-37s gain %+5.1f dB  rms %6.1f -> %6.1f"
              % (fn, gain, rms, rms + gain))


def main():
    gens = {
        "soft/soft_collect.ogg": gen_soft_collect,
        "soft/soft_win.ogg": gen_soft_win,
        "soft/soft_care_erfolg.ogg": gen_soft_care_erfolg,
        "foley/care_wasser.ogg": gen_care_wasser,
        "foley/care_buersten.ogg": gen_care_buersten,
        "foley/care_spuelung.ogg": gen_care_spuelung,
        "foley/pet_squish.ogg": gen_pet_squish,
        "foley/step_tap.ogg": gen_step_tap,
        "foley/nom_nom.ogg": gen_nom_nom,
        "foley/travel_whoosh_auf.ogg": lambda: _whoosh(True),
        "foley/travel_whoosh_zu.ogg": lambda: _whoosh(False),
    }
    stats = {}
    for rel, fn in gens.items():
        sig = fn()
        encode_ogg(os.path.join(SFX, rel), sig, SR)
        report_line("gen ", rel, sig)
        stats[rel] = {"rms_db": round(db(float(np.sqrt(np.mean(sig ** 2)))), 1),
                      "peak_db": round(db(float(np.max(np.abs(sig)))), 1)}
    fix_existing()
    normalize_voice()
    out = "/tmp/gooby-godot/artifacts/EF2/gen_sfx_stats.json"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        json.dump(stats, fh, indent=1)
    print(json.dumps({"generated": len(gens)}))


if __name__ == "__main__":
    sys.exit(main())
