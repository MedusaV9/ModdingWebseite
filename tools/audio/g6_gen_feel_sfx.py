#!/usr/bin/env python3
"""g6_gen_feel_sfx.py — AUDIO-FEEL-Werkbank (G6-Paket, Lücken-Inventur W17).

Erzeugt die 22 neuen Sounds des Audio-Grammatik-Lückenschlusses — komplett
prozedural (numpy-Synthese, Rezepte/Primitive aus ef2_gen_sfx.py), CC0,
selbst erzeugt. Zwei Familien:

1. EMOTIONS-FAMILIE (assets/audio/sfx/soft/emo_*.ogg) — die 12 inszenierten
   FeelEmotions bekommen eigene, unterscheidbare Mini-Motive statt
   recycelter UI-Sounds (schreck klang wie ui_error, traurigkeit wie
   ui_close; muedigkeit/angst waren stumm). Weiche Plucks/Seufzer im
   soft/-Familienrezept: Zentroid < 2,5 kHz, kaum Energie > 4 kHz.

2. WELT-FAMILIE (assets/audio/sfx/welt/*.ogg) — Orts-/Stations-Momente:
     city_hupe / city_vogel  — seit W4 in city_scene verdrahtet, Ids
                               fehlten in der SfxMap (stiller Verzicht)
     laden_glocke            — echte Ladentür-Glocke (statt gvz_wave@1.35)
     kasse_piep              — Kassen-Scanner (statt ui_coins@1.15,
                               Grammatik: ui_coins = Münz-EINNAHME)
     foto_shutter            — Kamera-Auslöser (statt ui_click)
     licht_schalter          — Lampen-Kipp-Klick am Umleg-Moment
     tuer_auf/_zu/_ruettel/_plopp — Haus-Türen (EVAL-1 2.5: „Türen stumm,
                               Tür-Gag hat Bubble, keinen Klang")

Pegel-Kontrakt (AUDIO-GRAMMATIK.md): Quelldatei-Peak <= -1 dBFS (hier
konservativ -4,5), volume_db-Trim auf die gemeinsame Effekt-Ebene
~-22 dBFS eff. — das Skript druckt die einzutragenden Trims (EVAL1-Metrik
via ef2_measure.analyze) und schreibt sie nach
/tmp/gooby-godot/artifacts/G6/feel_sfx_stats.json.

Aufruf: python3 tools/audio/g6_gen_feel_sfx.py
Danach: Trims in scripts/audio/sfx_map.gd eintragen und
        python3 tools/audio/ef2_manifest.py (Mess-Fixture).
"""

import importlib.util
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def _lade(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gen = _lade("ef2_gen_sfx")
measure = _lade("ef2_measure")

SR = gen.SR
SFX = gen.SFX
## Gemeinsame Effekt-Ebene (AUDIO-GRAMMATIK.md „~-22 dBFS eff.").
ZIEL_EFF_DB = -22.0


# ── Kleine Zusatz-Primitive (auf gen.* aufbauend) ───────────────────────────


def _noise_burst(n, lo_hz, hi_hz, seed):
    """Bandpass-Rauschimpuls (weich, zirkular) — Klick-/Foley-Baustein."""
    mid = 0.5 * (lo_hz + hi_hz)
    breite = max(hi_hz - lo_hz, 50.0) * 0.5
    return gen._shaped_noise(
        n, lambda f: np.exp(-(((f - mid) / breite) ** 2)), seed)


def _vibrato_ton(freq, dur, vib_hz, vib_staerke, tau, sr=SR):
    """Sinuston mit Vibrato und exponentiellem Ausklang."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    phase = 2 * math.pi * (freq * t + vib_staerke * freq / vib_hz
                           * (1.0 - np.cos(2 * math.pi * vib_hz * t))
                           / (2 * math.pi))
    return np.sin(phase) * np.exp(-t / tau)


# ── Emotions-Familie (12 Mini-Motive, soft/-Rezept) ─────────────────────────


def gen_emo_schreck():
    # Erschrecktes „hup!“: schneller Aufwärts-Rutsch + Zitter-Ausklang.
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    rutsch = gen._sweep(310.0, 730.0, int(0.12 * SR))
    sig = np.zeros(n)
    sig[: rutsch.size] = rutsch * gen._env(rutsch.size, 0.008, 0.02)
    zitter = np.sin(2 * math.pi * 690.0 * t) * np.exp(-t / 0.07)
    zitter *= 1.0 + 0.35 * np.sin(2 * math.pi * 13.0 * t)
    start = int(0.11 * SR)
    sig[start:] += 0.6 * zitter[: n - start]
    return gen._norm_peak(sig * gen._env(n, 0.006, 0.06), -4.5)


def gen_emo_freude():
    # Helles Zwei-Ton-Hüpfen: G5 -> B5 mit warmem Fundament.
    sig = gen._pluck([
        (392.0, 0.22, 0.0, 0.12),
        (784.0, 1.0, 0.0, 0.10),
        (987.8, 0.9, 0.09, 0.12),
        (1568.0, 0.10, 0.09, 0.06),
    ], 0.34)
    return gen._norm_peak(sig, -4.5)


def gen_emo_begeisterung():
    # Auffächernde Dur-Arpeggio-Treppe (C5-E5-G5-C6) — Tanz-Moment.
    sig = gen._pluck([
        (261.6, 0.18, 0.0, 0.16),
        (523.3, 1.0, 0.0, 0.10),
        (659.3, 0.9, 0.07, 0.10),
        (784.0, 0.85, 0.14, 0.11),
        (1046.5, 0.8, 0.21, 0.13),
        (2093.0, 0.06, 0.21, 0.06),
    ], 0.50)
    return gen._norm_peak(sig, -4.5)


def gen_emo_ueberraschung():
    # „Oh!“: Aufwärts-Biege-Pluck + kleiner Glitzer oben drauf.
    n = int(0.40 * SR)
    sig = np.zeros(n)
    biege = gen._sweep(500.0, 880.0, int(0.11 * SR))
    sig[: biege.size] = biege * gen._env(biege.size, 0.007, 0.03)
    rest = gen._pluck([
        (880.0, 0.95, 0.0, 0.11),
        (1318.5, 0.16, 0.0, 0.06),
    ], 0.28)
    start = int(0.115 * SR)
    sig[start: start + rest.size] += rest[: n - start]
    return gen._norm_peak(sig * gen._env(n, 0.005, 0.05), -4.5)


def gen_emo_verlegen():
    # Verschämtes Wackeln: zwei gedämpfte Töne abwärts mit Vibrato.
    n = int(0.45 * SR)
    sig = np.zeros(n)
    a = _vibrato_ton(659.3, 0.22, 5.5, 0.012, 0.10)
    b = _vibrato_ton(523.3, 0.25, 5.5, 0.014, 0.12)
    sig[: a.size] += a * gen._env(a.size, 0.012, 0.05)
    start = int(0.16 * SR)
    sig[start: start + b.size] += 0.8 * b[: n - start]
    sig = gen._fft_lowpass(sig, 1800.0)
    return gen._norm_peak(sig * gen._env(n, 0.01, 0.08), -5.0)


def gen_emo_trotz():
    # Grummeliges Doppel-Stampfen: zwei tiefe Thumps + Luft-Schnaufer.
    n = int(0.34 * SR)
    sig = np.zeros(n)
    for onset, f0 in ((0.0, 165.0), (0.12, 140.0)):
        i0 = int(onset * SR)
        m = int(0.11 * SR)
        thump = gen._sweep(f0, f0 * 0.7, m) * np.exp(-np.arange(m) / SR / 0.035)
        sig[i0: i0 + m] += thump * gen._env(m, 0.004, 0.03)
    huff = gen._fft_lowpass(
        np.random.default_rng(61).standard_normal(int(0.1 * SR)), 700.0)
    huff *= np.exp(-np.arange(huff.size) / SR / 0.03)
    i0 = int(0.02 * SR)
    sig[i0: i0 + huff.size] += 0.22 * huff / max(np.abs(huff).max(), 1e-12)
    return gen._norm_peak(sig * gen._env(n, 0.004, 0.05), -4.5)


def gen_emo_traurig():
    # Absinkende kleine Terz (E5 -> C5), langsam und weich.
    sig = gen._pluck([
        (659.3, 0.95, 0.0, 0.16),
        (329.6, 0.2, 0.0, 0.2),
        (523.3, 1.0, 0.2, 0.24),
        (261.6, 0.22, 0.2, 0.26),
    ], 0.65, attack=0.012)
    return gen._norm_peak(sig, -5.0)


def gen_emo_muede():
    # Müder Seufzer: Abwärts-Gleiten + weiches Atem-Rauschen.
    n = int(0.70 * SR)
    t = np.arange(n) / SR
    gleit = gen._sweep(355.0, 205.0, n)
    huelle = np.sin(math.pi * np.clip(t / (n / SR), 0.0, 1.0)) ** 1.6
    atem = gen._fft_lowpass(
        np.random.default_rng(62).standard_normal(n), 900.0)
    atem /= max(np.abs(atem).max(), 1e-12)
    sig = (gleit + 0.30 * atem) * huelle
    sig = gen._fft_lowpass(sig, 1500.0)
    return gen._norm_peak(sig, -6.0)


def gen_emo_neugier():
    # Fragezeichen-Kontur: Ton bleibt kurz, biegt dann NACH OBEN.
    n = int(0.36 * SR)
    sig = np.zeros(n)
    kopf = np.sin(2 * math.pi * 523.3 * np.arange(int(0.1 * SR)) / SR)
    sig[: kopf.size] = kopf * gen._env(kopf.size, 0.01, 0.03)
    biege = gen._sweep(523.3, 659.3, int(0.14 * SR))
    i0 = int(0.10 * SR)
    sig[i0: i0 + biege.size] += biege * gen._env(biege.size, 0.006, 0.05)
    blip = gen._pluck([(1318.5, 0.18, 0.0, 0.05)], 0.1)
    i1 = int(0.25 * SR)
    sig[i1: i1 + blip.size] += blip[: n - i1]
    return gen._norm_peak(sig * gen._env(n, 0.008, 0.06), -4.5)


def gen_emo_stolz():
    # Mini-Fanfare: Quart-Aufstieg (C5 -> F5) mit Oktav-Schimmer.
    sig = gen._pluck([
        (261.6, 0.25, 0.0, 0.14),
        (523.3, 1.0, 0.0, 0.12),
        (698.5, 0.95, 0.12, 0.16),
        (1396.9, 0.12, 0.12, 0.08),
    ], 0.50)
    return gen._norm_peak(sig, -4.5)


def gen_emo_angst():
    # Leises Beben: Moll-Ton mit 9-Hz-Zittern, dunkel gefiltert.
    n = int(0.60 * SR)
    t = np.arange(n) / SR
    grund = np.sin(2 * math.pi * 440.0 * t) * np.exp(-t / 0.28)
    terz = 0.4 * np.sin(2 * math.pi * 523.3 * t) * np.exp(-t / 0.22)
    zitter = 1.0 + 0.4 * np.sin(2 * math.pi * 9.0 * t)
    sig = gen._fft_lowpass((grund + terz) * zitter, 1400.0)
    return gen._norm_peak(sig * gen._env(n, 0.02, 0.1), -6.0)


def gen_emo_verliebt():
    # Verträumtes Glitzern: A5 -> Cis6 mit sanftem Schimmer-Schweif.
    n = int(0.50 * SR)
    sig = gen._pluck([
        (880.0, 1.0, 0.0, 0.12),
        (1108.7, 0.9, 0.12, 0.16),
        (440.0, 0.2, 0.0, 0.18),
    ], 0.50, attack=0.008)
    t = np.arange(n) / SR
    schimmer = np.sin(2 * math.pi * 1760.0 * t) * np.exp(-t / 0.16)
    schimmer *= 1.0 + 0.3 * np.sin(2 * math.pi * 5.0 * t)
    sig += 0.10 * schimmer * gen._env(n, 0.05, 0.1)
    return gen._norm_peak(sig, -4.5)


# ── Welt-Familie (Orte/Stationen/Türen) ─────────────────────────────────────


def gen_city_hupe():
    # Freundliche Cartoon-Hupe „ta-tüü“: zwei Töne mit Horn-Timbre.
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for onset, dauer, f0 in ((0.0, 0.15, 392.0), (0.15, 0.28, 493.9)):
        i0 = int(onset * SR)
        m = int(dauer * SR)
        tt = np.arange(m) / SR
        ton = (np.sin(2 * math.pi * f0 * tt)
               + 0.45 * np.sin(2 * math.pi * 2 * f0 * tt)
               + 0.18 * np.sin(2 * math.pi * 3 * f0 * tt))
        ton = np.tanh(1.6 * ton)
        sig[i0: i0 + m] += ton * gen._env(m, 0.012, 0.05)
    sig = gen._fft_lowpass(sig, 2400.0)
    return gen._norm_peak(sig * gen._env(n, 0.01, 0.06), -4.5)


def gen_city_vogel():
    # Drei kurze Zwitscher-Bögen (aufwärts, Vibrato) — Stadtpark-Vogel.
    n = int(0.55 * SR)
    sig = np.zeros(n)
    for onset, dauer, f0, f1 in (
        (0.0, 0.08, 2500.0, 3300.0),
        (0.20, 0.07, 2800.0, 3500.0),
        (0.36, 0.10, 2400.0, 3100.0),
    ):
        m = int(dauer * SR)
        tt = np.arange(m) / SR
        freq = f0 + (f1 - f0) * (tt / dauer)
        freq *= 1.0 + 0.03 * np.sin(2 * math.pi * 38.0 * tt)
        chirp = np.sin(2 * math.pi * np.cumsum(freq) / SR)
        i0 = int(onset * SR)
        sig[i0: i0 + m] += chirp * gen._env(m, 0.008, 0.03)
    return gen._norm_peak(sig * gen._env(n, 0.005, 0.05), -5.0)


def gen_laden_glocke():
    # Ladentür-Glöckchen: helles Ding-Ding mit weichem Anschlag.
    n = int(0.70 * SR)
    sig = np.zeros(n)
    for onset, amp in ((0.0, 1.0), (0.16, 0.85)):
        teil = gen._pluck([
            (1318.5, 1.0 * amp, 0.0, 0.20),
            (2093.0, 0.22 * amp, 0.0, 0.10),
            (3135.9, 0.05 * amp, 0.0, 0.05),
        ], 0.5, attack=0.004)
        i0 = int(onset * SR)
        sig[i0: i0 + teil.size] += teil[: n - i0]
    return gen._norm_peak(sig * gen._env(n, 0.004, 0.1), -4.5)


def gen_kasse_piep():
    # Kassen-Scanner: ein sauberer, runder C6-Piep.
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    sig = (np.sin(2 * math.pi * 1046.5 * t)
           + 0.12 * np.sin(2 * math.pi * 2093.0 * t))
    sig *= np.exp(-t / 0.10)
    return gen._norm_peak(sig * gen._env(n, 0.006, 0.05), -4.5)


def gen_foto_shutter():
    # Kamera-Auslöser: heller Klick + dumpferes Nachklacken.
    n = int(0.20 * SR)
    sig = np.zeros(n)
    klick = _noise_burst(int(0.03 * SR), 1400.0, 2600.0, 63)
    klick *= np.exp(-np.arange(klick.size) / SR / 0.008)
    sig[: klick.size] += klick * gen._env(klick.size, 0.002, 0.008)
    klack = _noise_burst(int(0.045 * SR), 400.0, 900.0, 64)
    klack *= np.exp(-np.arange(klack.size) / SR / 0.012)
    i0 = int(0.07 * SR)
    sig[i0: i0 + klack.size] += 0.8 * klack * gen._env(klack.size, 0.002, 0.012)
    koerper = gen._sweep(260.0, 200.0, int(0.06 * SR))
    koerper *= np.exp(-np.arange(koerper.size) / SR / 0.02)
    sig[i0: i0 + koerper.size] += 0.3 * koerper
    return gen._norm_peak(sig * gen._env(n, 0.002, 0.03), -4.5)


def gen_licht_schalter():
    # Kipp-Schalter: kompakter Klick mit kleinem Gehäuse-Körper.
    n = int(0.12 * SR)
    tick = gen._sweep(850.0, 480.0, int(0.025 * SR))
    tick *= np.exp(-np.arange(tick.size) / SR / 0.007)
    rausch = gen._fft_lowpass(
        np.random.default_rng(65).standard_normal(int(0.02 * SR)), 1200.0)
    rausch /= max(np.abs(rausch).max(), 1e-12)
    rausch *= np.exp(-np.arange(rausch.size) / SR / 0.005)
    koerper = gen._sweep(200.0, 160.0, int(0.06 * SR))
    koerper *= np.exp(-np.arange(koerper.size) / SR / 0.018)
    sig = np.zeros(n)
    sig[: tick.size] += tick * gen._env(tick.size, 0.001, 0.008)
    sig[: rausch.size] += 0.35 * rausch
    sig[: koerper.size] += 0.4 * koerper
    return gen._norm_peak(sig * gen._env(n, 0.001, 0.02), -4.5)


def gen_tuer_auf():
    # Haustür öffnet: Klinken-Tick + gutmütiges kurzes Knarzen.
    n = int(0.50 * SR)
    sig = np.zeros(n)
    tick = gen._sweep(700.0, 420.0, int(0.02 * SR))
    tick *= np.exp(-np.arange(tick.size) / SR / 0.006)
    sig[: tick.size] += 0.5 * tick
    m = int(0.4 * SR)
    knarz = _noise_burst(m, 240.0, 560.0, 66)
    tt = np.arange(m) / SR
    wobble = 0.5 + 0.5 * np.clip(np.sin(2 * math.pi * 11.0 * tt), 0.0, 1.0) ** 1.3
    huelle = np.sin(math.pi * np.clip(tt / (m / SR), 0.0, 1.0)) ** 1.2
    i0 = int(0.05 * SR)
    sig[i0: i0 + m] += knarz * wobble * huelle
    ton = gen._sweep(300.0, 380.0, m) * huelle
    sig[i0: i0 + m] += 0.16 * ton
    return gen._norm_peak(sig * gen._env(n, 0.004, 0.08), -5.0)


def gen_tuer_zu():
    # Tür fällt weich zu: Holz-Thump + kurzer Schnapper.
    n = int(0.32 * SR)
    sig = np.zeros(n)
    thump = gen._sweep(150.0, 105.0, int(0.09 * SR))
    thump *= np.exp(-np.arange(thump.size) / SR / 0.03)
    sig[: thump.size] += thump * gen._env(thump.size, 0.003, 0.03)
    holz = _noise_burst(int(0.05 * SR), 300.0, 900.0, 67)
    holz *= np.exp(-np.arange(holz.size) / SR / 0.012)
    sig[: holz.size] += 0.4 * holz
    schnapp = gen._sweep(600.0, 380.0, int(0.02 * SR))
    schnapp *= np.exp(-np.arange(schnapp.size) / SR / 0.005)
    i0 = int(0.10 * SR)
    sig[i0: i0 + schnapp.size] += 0.35 * schnapp
    return gen._norm_peak(sig * gen._env(n, 0.002, 0.05), -4.5)


def gen_tuer_ruettel():
    # Klemm-Gag: drei schnelle Holz-Rüttler (fürs Tap-Mash, mit Jitter).
    n = int(0.30 * SR)
    sig = np.zeros(n)
    rng = np.random.default_rng(68)
    for i, onset in enumerate((0.0, 0.09, 0.18)):
        m = int(0.06 * SR)
        holz = _noise_burst(m, 600.0, 1300.0, 70 + i)
        holz *= np.exp(-np.arange(m) / SR / 0.012)
        koerper = gen._sweep(220.0 + rng.uniform(-15, 15), 170.0, m)
        koerper *= np.exp(-np.arange(m) / SR / 0.02)
        amp = 1.0 - 0.12 * i
        i0 = int(onset * SR)
        sig[i0: i0 + m] += amp * (holz * 0.6 + 0.5 * koerper) * gen._env(m, 0.002, 0.015)
    return gen._norm_peak(sig * gen._env(n, 0.002, 0.04), -4.5)


def gen_tuer_plopp():
    # Durchplopp-Moment (POLISH-7-Gag): perkiger Pop mit Luft-Puff.
    n = int(0.15 * SR)
    pop = gen._sweep(340.0, 175.0, n) * np.exp(-np.arange(n) / SR / 0.04)
    puff = gen._fft_lowpass(
        np.random.default_rng(69).standard_normal(n), 1100.0)
    puff /= max(np.abs(puff).max(), 1e-12)
    puff *= np.exp(-np.arange(n) / SR / 0.015)
    sig = (pop + 0.25 * puff) * gen._env(n, 0.003, 0.04)
    return gen._norm_peak(sig, -4.5)


## rel-Pfad unter assets/audio/sfx → Generator. Ziel-Effekt-Ebene je Datei
## (fast alle -22; Ambient-Vogel bewusst 2 dB darunter — Hintergrund-Moment).
GENS = {
    "soft/emo_schreck.ogg": (gen_emo_schreck, -22.0),
    "soft/emo_freude.ogg": (gen_emo_freude, -22.0),
    "soft/emo_begeisterung.ogg": (gen_emo_begeisterung, -22.0),
    "soft/emo_ueberraschung.ogg": (gen_emo_ueberraschung, -22.0),
    "soft/emo_verlegen.ogg": (gen_emo_verlegen, -23.0),
    "soft/emo_trotz.ogg": (gen_emo_trotz, -22.0),
    "soft/emo_traurig.ogg": (gen_emo_traurig, -23.0),
    "soft/emo_muede.ogg": (gen_emo_muede, -24.0),
    "soft/emo_neugier.ogg": (gen_emo_neugier, -23.0),
    "soft/emo_stolz.ogg": (gen_emo_stolz, -22.0),
    "soft/emo_angst.ogg": (gen_emo_angst, -24.0),
    "soft/emo_verliebt.ogg": (gen_emo_verliebt, -22.0),
    "welt/city_hupe.ogg": (gen_city_hupe, -22.0),
    "welt/city_vogel.ogg": (gen_city_vogel, -24.0),
    "welt/laden_glocke.ogg": (gen_laden_glocke, -22.0),
    "welt/kasse_piep.ogg": (gen_kasse_piep, -23.0),
    "welt/foto_shutter.ogg": (gen_foto_shutter, -22.0),
    "welt/licht_schalter.ogg": (gen_licht_schalter, -23.0),
    "welt/tuer_auf.ogg": (gen_tuer_auf, -22.0),
    "welt/tuer_zu.ogg": (gen_tuer_zu, -22.0),
    "welt/tuer_ruettel.ogg": (gen_tuer_ruettel, -22.0),
    "welt/tuer_plopp.ogg": (gen_tuer_plopp, -22.0),
}


def main():
    stats = {}
    print("%-30s %6s %6s %8s %8s  %s" % (
        "datei", "dur", "peak", "loud", "zentroid", "trim-Vorschlag"))
    for rel, (fn, ziel_eff) in GENS.items():
        sig = fn()
        pfad = os.path.join(SFX, rel)
        gen.encode_ogg(pfad, sig, SR)
        a = measure.analyze(pfad)
        trim = round(2.0 * (ziel_eff - a["loud_db"])) / 2.0
        stats[rel] = {
            "dur_s": a["dur_s"], "peak_db": a["peak_db"],
            "loud_db": a["loud_db"], "centroid_hz": a["centroid_hz"],
            "hi4k_pct": a["hi4k_pct"], "ziel_eff_db": ziel_eff,
            "volume_db_vorschlag": trim,
        }
        print("%-30s %5.2fs %6.1f %8.1f %7.0fHz  volume_db=%+.1f" % (
            rel, a["dur_s"], a["peak_db"], a["loud_db"],
            a["centroid_hz"], trim))
    out = "/tmp/gooby-godot/artifacts/G6/feel_sfx_stats.json"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        json.dump(stats, fh, indent=1)
    print(json.dumps({"generated": len(GENS), "stats": out}))


if __name__ == "__main__":
    sys.exit(main())
