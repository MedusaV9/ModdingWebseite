#!/usr/bin/env python3
"""gen_klangbetten.py — W18/J5 „Jeder Ort ein Klangbett" (Idee I-33).

Synthetisiert die 6 Orts-Ambience-Loops (Klangbetten) unter
GOOBY-GODOT/assets/audio/sfx/ambient/ — DETERMINISTISCH (feste Seeds,
byte-stabiler Signalpfad) und NAHTLOS loopbar by construction:

  * Rausch-Schichten kommen aus dem zirkulaeren _shaped_noise-Rezept von
    tools/audio/ef2_gen_sfx.py (ifft mit Zufallsphasen — periodisch, also
    knackfrei am Loop-Punkt).
  * Alle LFO-Wobbles laufen mit GANZZAHLIGEN Zyklen pro Loop-Laenge.
  * Ereignisse (Knister-Pops, Uhr-Ticks, Vogel-Pfiffe, Auto-Schwaden)
    werden bei t=0 gebaut und per np.roll an ihre Position gedreht —
    ihre Huellkurven wickeln damit zirkulaer um die Naht.

Betten (Mapping: scripts/audio/klangbett.gd, Ids: scripts/audio/sfx_map.gd):
  ambient/bett_kamin.ogg   — Kaminknistern + Glut-Grummeln     (Heim/Wohnen)
  ambient/bett_uhr.ogg     — Uhr-Ticken (Tick 0,5 s/Tock 1,5 s) (Heim-Raeume)
  ambient/bett_voegel.ogg  — Vogelzwitschern + Blaetter-Brise   (Garten)
  ambient/bett_wind.ogg    — weicher Wind                       (drauszen)
  ambient/bett_stadt.ogg   — fernes Gemurmel-Grummeln + Verkehr (Stadt)
  ambient/bett_laden.ogg   — Laden-Raumton (Lueftung + Rascheln)(Laeden/IKEA)

Mastering: gated 400-ms-RMS (ef2-Metrik) auf −20 dBFS, Peak-Deckel −3 dBFS
— gleiche Ebene wie die Bestands-Familie; die eigentliche Bett-Leisigkeit
kommt aus den volume_db-Trims der SfxMap (eff. ≈ −34…−36 dBFS, deutlich
unter Musik-Playback ≈ −30 und SFX-Median ≈ −22,6).

Lizenz: komplette Eigen-Synthese (numpy), CC0 — s. LICENSE.md im Zielordner.
Nach jedem Lauf: python3 tools/audio/ef2_manifest.py (Mess-Fixture).

Aufruf: python3 tools/audio/gen_klangbetten.py
"""

import json
import math
import os
import subprocess
import sys

import numpy as np

ROOT = "/workspace/GOOBY-GODOT"
OUT_DIR = os.path.join(ROOT, "assets/audio/sfx/ambient")
SR = 44100
LOUD_TARGET_DB = -20.0
PEAK_CAP_DB = -3.0


def db(x):
    return 20.0 * math.log10(max(x, 1e-12))


def lin(x_db):
    return 10.0 ** (x_db / 20.0)


def shaped_noise(n, mag_fn, seed):
    """Zirkulaeres Rauschen mit Wunsch-Spektrum (ef2_gen_sfx-Rezept)."""
    rng = np.random.default_rng(seed)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    mag = mag_fn(freqs)
    phase = rng.uniform(0, 2 * math.pi, freqs.size)
    spec = mag * np.exp(1j * phase)
    spec[0] = 0.0
    x = np.fft.irfft(spec, n)
    return x / max(np.abs(x).max(), 1e-12)


def lfo(n, zyklen, phase=0.0):
    """Sinus-LFO mit GANZZAHLIGEN Zyklen ueber den Loop (nahtlos)."""
    t = np.arange(n) / n
    return np.sin(2 * math.pi * float(int(zyklen)) * t + phase)


def event(n, sig, pos_s, gain=1.0):
    """Ereignis `sig` (gebaut bei t=0) zirkulaer an Position pos_s drehen."""
    out = np.zeros(n)
    out[: sig.size] = sig[:n] * gain
    return np.roll(out, int(pos_s * SR) % n)


def gated_loud_db(x):
    """ef2-Loudness-Naeherung: 400-ms-Frames, Gate −60 dBFS."""
    win = int(0.4 * SR)
    m = x.size // win
    fr = np.sqrt(np.mean(x[: m * win].reshape(m, win) ** 2, axis=1))
    active = fr[fr > lin(-60.0)]
    if active.size == 0:
        return db(float(np.sqrt(np.mean(x**2))))
    return db(float(np.sqrt(np.mean(active**2))))


def master(x):
    """Gated-Loudness auf −20 dBFS, Peak hart unter −3 dBFS."""
    gain = LOUD_TARGET_DB - gated_loud_db(x)
    peak = db(float(np.max(np.abs(x))))
    gain = min(gain, PEAK_CAP_DB - peak)
    return x * lin(gain)


def encode_ogg(path, x, quality=4):
    # bitexact + feste Ogg-Stream-Serial: sonst wuerfelt der Muxer pro Lauf
    # eine Serial in den Header und die Datei waere NICHT byte-stabil.
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR),
         "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", str(quality),
         "-fflags", "+bitexact", "-flags:a", "+bitexact",
         "-serial_offset", "1337", path],
        input=x.astype(np.float32).tobytes(), check=True)


# ── Ereignis-Bausteine ───────────────────────────────────────────────────────


def _decay_noise(dur_s, cutoff_fn, tau_s, seed):
    """Kurzer Rausch-Impuls mit Spektrum + Exponential-Ausklang."""
    m = int(dur_s * SR)
    body = shaped_noise(m, cutoff_fn, seed)
    t = np.arange(m) / SR
    att = np.clip(t / 0.002, 0.0, 1.0)
    return body * att * np.exp(-t / tau_s)


def _chirp(f0, f1, dur_s, vibrato_hz=0.0, vibrato_amt=0.0):
    """Vogel-Pfiff: Sinus-Sweep mit optionalem Vibrato, weiche Glocke."""
    m = int(dur_s * SR)
    t = np.arange(m) / SR
    u = t / dur_s
    freq = f0 + (f1 - f0) * u
    if vibrato_hz > 0.0:
        freq = freq * (1.0 + vibrato_amt * np.sin(2 * math.pi * vibrato_hz * t))
    tone = np.sin(2 * math.pi * np.cumsum(freq) / SR)
    return tone * np.sin(math.pi * u) ** 2


# ── Die sechs Betten ─────────────────────────────────────────────────────────


def gen_kamin():
    # 8 s: Glut-Grummeln + Feuerzungen-Hauch + deterministische Knister-Pops.
    n = int(8.0 * SR)
    glut = shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 200.0) ** 2.2), 101)
    zungen = shaped_noise(
        n, lambda f: np.exp(-((f - 1100.0) / 700.0) ** 2), 102)
    atmung = 1.0 + 0.14 * lfo(n, 3) + 0.08 * lfo(n, 7, 1.1)
    sig = (0.62 * glut + 0.11 * zungen) * atmung
    rng = np.random.default_rng(103)
    for _i in range(26):
        pos = rng.uniform(0.0, 8.0)
        hell = rng.uniform(1600.0, 3400.0)
        pop = _decay_noise(
            0.05, lambda f, h=hell: np.exp(-((f - h) / 900.0) ** 2),
            rng.uniform(0.004, 0.012), int(rng.integers(1, 1 << 30)))
        sig += event(n, pop, pos, rng.uniform(0.25, 0.75))
    return sig


def gen_uhr():
    # 2 s (1-Hz-Pendel): Tick bei 0,5 s, dunklerer Tock bei 1,5 s + Raumton.
    # Raumton liegt ueber dem −60-dB-Gate, damit die ef2-Loudness ALLE
    # Frames misst (sonst zaehlten nur die Tick-Fenster).
    n = int(2.0 * SR)
    raum = shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 240.0) ** 2), 111)
    sig = 0.16 * raum * (1.0 + 0.1 * lfo(n, 1))
    tick = _decay_noise(
        0.03, lambda f: np.exp(-((f - 3600.0) / 1000.0) ** 2), 0.006, 112)
    tock = _decay_noise(
        0.035, lambda f: np.exp(-((f - 2100.0) / 800.0) ** 2), 0.008, 113)
    sig += event(n, tick, 0.5, 1.0)
    sig += event(n, tock, 1.5, 0.8)
    return sig


def gen_voegel():
    # 12 s: Blaetter-Brise + 8 deterministische Pfiff-Phrasen (2–4 Pfiffe).
    n = int(12.0 * SR)
    brise = shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 380.0) ** 1.8), 121)
    blaetter = shaped_noise(
        n, lambda f: np.exp(-((f - 2900.0) / 1400.0) ** 2), 122)
    sig = (0.5 * brise + 0.05 * blaetter) * (1.0 + 0.18 * lfo(n, 2) + 0.1 * lfo(n, 5, 0.7))
    rng = np.random.default_rng(123)
    for _phrase in range(8):
        start = rng.uniform(0.0, 12.0)
        f_basis = rng.uniform(2100.0, 3900.0)
        for k in range(int(rng.integers(2, 5))):
            pfiff = _chirp(
                f_basis * rng.uniform(0.92, 1.08),
                f_basis * rng.uniform(1.05, 1.35),
                rng.uniform(0.06, 0.14), vibrato_hz=rng.uniform(18.0, 30.0),
                vibrato_amt=0.05)
            sig += event(n, pfiff, start + k * rng.uniform(0.12, 0.22),
                         rng.uniform(0.05, 0.12))
    return sig


def gen_wind():
    # 10 s: weicher Wind, zwei ganzzahlige Boeen-Wobbles + Boeen-Band.
    n = int(10.0 * SR)
    grund = shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 300.0) ** 1.7), 131)
    boee = shaped_noise(n, lambda f: np.exp(-((f - 620.0) / 320.0) ** 2), 132)
    hub = 1.0 + 0.22 * lfo(n, 2) + 0.12 * lfo(n, 5, 2.1)
    boeen_hub = np.clip(lfo(n, 3, 0.4), 0.0, 1.0) ** 2
    return (0.62 * grund + 0.16 * boee * boeen_hub) * hub


def gen_stadt():
    # 12 s: tiefes Stadt-Grummeln + Verkehrs-Wash + 3 ferne Vorbeifahrten.
    n = int(12.0 * SR)
    grummeln = shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 130.0) ** 2.0), 141)
    wash = shaped_noise(
        n, lambda f: np.exp(-((f - 480.0) / 380.0) ** 2), 142)
    luft = shaped_noise(
        n, lambda f: np.exp(-((f - 2400.0) / 1200.0) ** 2), 143)
    sig = (0.58 * grummeln * (1.0 + 0.12 * lfo(n, 2))
           + 0.2 * wash * (1.0 + 0.25 * lfo(n, 3, 1.4)) + 0.035 * luft)
    rng = np.random.default_rng(144)
    for _i in range(3):
        dauer = rng.uniform(2.2, 3.2)
        fahrt = shaped_noise(
            int(dauer * SR),
            lambda f: np.exp(-((f - rng.uniform(320.0, 800.0)) / 300.0) ** 2),
            int(rng.integers(1, 1 << 30)))
        t = np.arange(fahrt.size) / fahrt.size
        fahrt *= np.sin(math.pi * t) ** 2
        sig += event(n, fahrt, rng.uniform(0.0, 12.0), rng.uniform(0.1, 0.16))
    return sig


def gen_laden():
    # 9 s: Lueftungs-Brummen (100/200 Hz, ganzzahlige Hz = nahtlos) +
    # Luft-Rauschen + 2 sehr leise Waren-Rascheln. Bewusst OHNE Stimmen:
    # das Gemurmel + der Kassen-Piep bleiben Sache von OrtLeben (J3).
    n = int(9.0 * SR)
    t = np.arange(n) / SR
    brumm = 0.5 * np.sin(2 * math.pi * 100.0 * t) + 0.22 * np.sin(
        2 * math.pi * 200.0 * t + 0.8)
    luft = shaped_noise(n, lambda f: 1.0 / (1.0 + (f / 420.0) ** 2.0), 151)
    sig = 0.1 * brumm * (1.0 + 0.06 * lfo(n, 2)) + 0.5 * luft * (
        1.0 + 0.1 * lfo(n, 3, 0.5))
    rng = np.random.default_rng(152)
    for _i in range(2):
        rascheln = _decay_noise(
            0.3, lambda f: np.exp(-((f - 2000.0) / 1100.0) ** 2), 0.09,
            int(rng.integers(1, 1 << 30)))
        sig += event(n, rascheln, rng.uniform(0.0, 9.0), rng.uniform(0.05, 0.08))
    return sig


def main():
    gens = {
        "bett_kamin.ogg": gen_kamin,
        "bett_uhr.ogg": gen_uhr,
        "bett_voegel.ogg": gen_voegel,
        "bett_wind.ogg": gen_wind,
        "bett_stadt.ogg": gen_stadt,
        "bett_laden.ogg": gen_laden,
    }
    stats = {}
    for fn, gen in gens.items():
        sig = master(gen())
        path = os.path.join(OUT_DIR, fn)
        encode_ogg(path, sig)
        kopf = np.sqrt(np.mean(sig[: int(0.05 * SR)] ** 2))
        schwanz = np.sqrt(np.mean(sig[-int(0.05 * SR):] ** 2))
        stats[fn] = {
            "dur_s": round(sig.size / SR, 2),
            "loud_db": round(gated_loud_db(sig), 1),
            "peak_db": round(db(float(np.max(np.abs(sig)))), 1),
            "seam_db": round(abs(db(float(kopf)) - db(float(schwanz))), 2),
            "kb": round(os.path.getsize(path) / 1024.0, 1),
        }
        print("[bett] %-16s %s" % (fn, stats[fn]))
    print(json.dumps({"generated": len(gens), "dir": OUT_DIR}))


if __name__ == "__main__":
    sys.exit(main())
