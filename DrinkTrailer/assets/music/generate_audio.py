#!/usr/bin/env python3
"""
generate_audio.py -- deterministic, 100% self-synthesized audio stack for the
EARLY drink trailers (DrinkTrailer/assets/music).

Everything is rendered from scratch with numpy (no samples, no third-party
audio). One fixed seed => byte-identical output on every run. ffmpeg is only
used to transcode the final WAV masters to .m4a (AAC) with -bitexact.

Outputs (all in the directory of this script):
  hype_track.wav / .m4a   ~50 s, 140 BPM EDM/Phonk hybrid (TikTok cut)
  clean_track.wav / .m4a  ~48 s, 105 BPM minimal "Apple style"
  sfx/ (flat, here):      whoosh_1..3, impact_1..2, riser_short, fizz_open,
                          sparkle_pop, ui_tick  (WAV, 0.2-1.5 s)
  beat_grid.json          BPM, beat times, markers per track (Remotion sync)

Usage:
  python3 generate_audio.py            # generate everything + print manifest
  python3 generate_audio.py --verify   # QC checks against existing files
  python3 generate_audio.py --checksums# print sha256 of all outputs
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import wave

import numpy as np

SR = 48000
SEED = 20260816
HERE = os.path.dirname(os.path.abspath(__file__))
TWO_PI = 2.0 * np.pi
PEAK_DB = -1.5          # master ceiling for tracks and SFX
BEAT_GRID = "beat_grid.json"

HYPE_BPM = 140.0
CLEAN_BPM = 105.0


# --------------------------------------------------------------------------
# deterministic RNG / basic helpers
# --------------------------------------------------------------------------

def rng_for(tag: str) -> np.random.Generator:
    """Independent, order-stable RNG stream per named component."""
    h = int.from_bytes(hashlib.sha256(tag.encode()).digest()[:8], "big")
    return np.random.default_rng([SEED, h])


def ns(sec: float) -> int:
    return int(round(sec * SR))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n) / SR


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def to_db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x))))


# --------------------------------------------------------------------------
# FFT magnitude filters (zero phase, pure numpy)
# --------------------------------------------------------------------------

def _mag_lp(f, fc, o):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * o))


def _mag_hp(f, fc, o):
    f = np.maximum(f, 1e-9)
    return 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * o))


def fft_filter(x: np.ndarray, mag_fn) -> np.ndarray:
    if x.ndim == 2:
        return np.stack([fft_filter(x[:, c], mag_fn) for c in range(x.shape[1])], 1)
    n = len(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(np.fft.rfft(x) * mag_fn(freqs), n)


def lowpass(x, fc, o=4):
    return fft_filter(x, lambda f: _mag_lp(f, fc, o))


def highpass(x, fc, o=4):
    return fft_filter(x, lambda f: _mag_hp(f, fc, o))


def bandpass(x, lo, hi, o=3):
    return fft_filter(x, lambda f: _mag_hp(f, lo, o) * _mag_lp(f, hi, o))


# --------------------------------------------------------------------------
# envelopes / mixing
# --------------------------------------------------------------------------

def exp_env(n: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (tau * SR))


def att_ramp(x: np.ndarray, sec: float = 0.002) -> np.ndarray:
    k = min(len(x), max(1, ns(sec)))
    ramp = np.linspace(0.0, 1.0, k)
    if x.ndim == 2:
        x[:k] *= ramp[:, None]
    else:
        x[:k] *= ramp
    return x


def fade_out(x: np.ndarray, sec: float) -> np.ndarray:
    k = min(len(x), max(1, ns(sec)))
    ramp = np.linspace(1.0, 0.0, k)
    if x.ndim == 2:
        x[-k:] *= ramp[:, None]
    else:
        x[-k:] *= ramp
    return x


def norm_peak(x: np.ndarray, peak: float = 1.0) -> np.ndarray:
    m = float(np.max(np.abs(x)))
    return x * (peak / m) if m > 0 else x


def add(buf: np.ndarray, sig: np.ndarray, at_sec: float,
        gain: float = 1.0, pan: float = 0.0) -> None:
    """Mix mono/stereo `sig` into stereo `buf` at `at_sec` (equal-power pan)."""
    i0 = ns(at_sec)
    if i0 >= len(buf):
        return
    if sig.ndim == 1:
        th = (pan + 1.0) * np.pi / 4.0
        s = np.stack([sig * math.cos(th), sig * math.sin(th)], 1) * gain
    else:
        s = sig * gain
    i1 = min(len(buf), i0 + len(s))
    buf[i0:i1] += s[: i1 - i0]


def pump_env(n: int, times, depth=0.60, att=0.006, hold=0.012, rel=0.30):
    """Sidechain 'pump' curve: dips at each time, smooth cosine recovery."""
    env = np.ones(n)
    a, h, r = ns(att), ns(hold), ns(rel)
    curve = np.concatenate([
        1.0 - depth * np.linspace(0.0, 1.0, a),
        np.full(h, 1.0 - depth),
        1.0 - depth * (0.5 + 0.5 * np.cos(np.pi * np.linspace(0.0, 1.0, r))),
    ])
    for tsec in times:
        i = ns(tsec)
        if i >= n:
            continue
        j = min(n, i + len(curve))
        env[i:j] = np.minimum(env[i:j], curve[: j - i])
    return env


# --------------------------------------------------------------------------
# drum / percussion synths
# --------------------------------------------------------------------------

def synth_kick() -> np.ndarray:
    n = ns(0.32)
    t = t_axis(n)
    freq = 46.0 + 118.0 * np.exp(-t / 0.042)          # 164 -> 46 Hz glide
    body = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / 0.115)
    body = np.tanh(2.4 * body) / math.tanh(2.4)
    cn = ns(0.005)
    click = rng_for("kick.click").standard_normal(cn) * exp_env(cn, 0.0012)
    body[:cn] += bandpass(click, 2000, 9000, 2) * 0.9
    att_ramp(body, 0.0004)
    fade_out(body, 0.012)
    return norm_peak(body)


def synth_clap() -> np.ndarray:
    n = ns(0.30)
    out = np.zeros(n)
    r = rng_for("clap")
    for k, off in enumerate((0.0, 0.010, 0.021, 0.032)):
        bn = ns(0.014)
        burst = r.standard_normal(bn) * exp_env(bn, 0.0045)
        i = ns(off)
        out[i:i + bn] += burst * (0.8 + 0.2 * (k == 3))
    tn = ns(0.24)
    tail = r.standard_normal(tn) * exp_env(tn, 0.055)
    out[ns(0.032):ns(0.032) + tn] += tail * 0.8
    out = bandpass(out, 500, 8500, 2)
    out += bandpass(out, 900, 1500, 2) * 0.7          # clap "body" resonance
    att_ramp(out, 0.0008)
    fade_out(out, 0.02)
    return norm_peak(out)


def synth_hat(open_hat: bool = False) -> np.ndarray:
    dur = 0.30 if open_hat else 0.055
    n = ns(dur)
    t = t_axis(n)
    r = rng_for("hat.open" if open_hat else "hat.closed")
    noise = r.standard_normal(n) * (1.0 + 0.6 * np.sin(TWO_PI * 7900 * t))
    noise *= exp_env(n, 0.085 if open_hat else 0.014)
    out = highpass(noise, 6800, 3)
    att_ramp(out, 0.0005)
    fade_out(out, 0.01)
    return norm_peak(out)


def synth_shaker() -> np.ndarray:
    n = ns(0.09)
    r = rng_for("shaker")
    noise = r.standard_normal(n)
    env = np.minimum(1.0, t_axis(n) / 0.015) * exp_env(n, 0.028)
    out = bandpass(noise * env, 3500, 9500, 2)
    fade_out(out, 0.01)
    return norm_peak(out)


def synth_cowbell(midi: float) -> np.ndarray:
    f0 = midi_hz(midi)
    n = ns(0.22)
    t = t_axis(n)
    x = (np.sin(TWO_PI * f0 * t) + 0.7 * np.sin(TWO_PI * f0 * 1.48 * t)
         + 0.25 * np.sin(TWO_PI * f0 * 2.42 * t))
    x = np.tanh(1.8 * x) * exp_env(n, 0.075)
    x = bandpass(x, f0 * 0.6, 6000, 2)
    att_ramp(x, 0.001)
    fade_out(x, 0.02)
    return norm_peak(x)


def synth_snap() -> np.ndarray:
    """Soft finger snap for the clean track."""
    n = ns(0.16)
    r = rng_for("snap")
    body = r.standard_normal(n) * exp_env(n, 0.018)
    out = bandpass(body, 1200, 4200, 2)
    out += lowpass(r.standard_normal(n) * exp_env(n, 0.010), 500, 3) * 0.5
    att_ramp(out, 0.0006)
    fade_out(out, 0.02)
    return norm_peak(out)


def synth_thump() -> np.ndarray:
    """Soft downbeat thump (clean track pulse)."""
    n = ns(0.20)
    t = t_axis(n)
    freq = 52.0 + 60.0 * np.exp(-t / 0.03)
    x = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / 0.07)
    att_ramp(x, 0.002)
    fade_out(x, 0.03)
    return norm_peak(x)


# --------------------------------------------------------------------------
# tonal synths
# --------------------------------------------------------------------------

def synth_sub(midi: float, dur: float) -> np.ndarray:
    """Mono sub bass: sine + decaying 2nd harmonic, soft saturation."""
    f = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)
    x = np.sin(TWO_PI * f * t) + 0.22 * np.sin(TWO_PI * 2 * f * t) * np.exp(-t / 0.09)
    x = np.tanh(1.5 * x) / math.tanh(1.5)
    att_ramp(x, 0.004)
    fade_out(x, 0.025)
    return x


_PLUCK_CACHE: dict = {}


def synth_pluck(midi: int, dur: float = 0.45, bright: float = 0.92) -> np.ndarray:
    """Detuned additive-saw pluck; per-harmonic decay = filter-sweep feel."""
    key = (midi, round(dur, 3), round(bright, 3))
    if key in _PLUCK_CACHE:
        return _PLUCK_CACHE[key]
    f0 = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)

    def voice(f: float, tag: str) -> np.ndarray:
        kmax = int(max(3, min(26, 16000.0 / f)))
        ks = np.arange(1, kmax + 1)
        amps = (bright ** (ks - 1)) / ks ** 0.85
        taus = 0.30 / (1.0 + 0.5 * (ks - 1)) ** 0.75
        ph = rng_for(f"pluck.{tag}.{midi}.{bright}").uniform(0, TWO_PI, kmax)
        return (amps[:, None] * np.exp(-t[None, :] / taus[:, None])
                * np.sin(TWO_PI * f * ks[:, None] * t[None, :] + ph[:, None])).sum(0)

    x = np.stack([voice(f0 * 1.0012, "L"), voice(f0 * 0.9988, "R")], 1)
    att_ramp(x, 0.0015)
    fade_out(x, 0.04)
    x = norm_peak(x)
    _PLUCK_CACHE[key] = x
    return x


_PIANO_CACHE: dict = {}


def synth_piano(midi: int, dur: float, vel: float = 1.0) -> np.ndarray:
    """Warm FM/additive piano stack: inharmonic partials, per-partial decay,
    hammer transient + key thump. True-stereo (decorrelated L/R phases)."""
    dur = min(dur, 4.8)
    key = (midi, round(dur, 3))
    if key in _PIANO_CACHE:
        return _PIANO_CACHE[key] * vel
    f0 = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)

    def voice(det: float, tag: str) -> np.ndarray:
        f = f0 * det
        kmax = int(max(4, min(26, 15000.0 / f)))
        ks = np.arange(1, kmax + 1)
        fk = f * ks * np.sqrt(1.0 + 0.00038 * ks ** 2)     # string inharmonicity
        amps = 1.0 / ks ** 1.5 * np.exp(-((fk / 11000.0) ** 2))
        tau0 = 3.4 * (233.0 / f) ** 0.5
        taus = np.maximum(0.09, tau0 / (1.0 + 0.75 * (ks - 1)) ** 1.0)
        ph = rng_for(f"piano.{tag}.{midi}").uniform(0, TWO_PI, kmax)
        return (amps[:, None] * np.exp(-t[None, :] / taus[:, None])
                * np.sin(TWO_PI * fk[:, None] * t[None, :] + ph[:, None])).sum(0)

    x = np.stack([voice(1.0004, "L"), voice(0.9996, "R")], 1)
    x = norm_peak(x)
    r = rng_for(f"piano.noise.{midi}")
    hn = ns(0.012)
    hammer = bandpass(r.standard_normal(hn) * exp_env(hn, 0.003), 700, 5200, 2)
    x[:hn] += (hammer * 0.18)[:, None]
    tn = ns(0.035)
    thump = lowpass(r.standard_normal(tn) * exp_env(tn, 0.012), 190, 3)
    x[:tn] += (thump * 0.11)[:, None]
    att_ramp(x, 0.0012)
    fade_out(x, 0.06)
    _PIANO_CACHE[key] = x
    return x * vel


def synth_pad_chord(midis, dur: float, cutoff: float = 950.0,
                    attack: float = 0.7, tag: str = "pad") -> np.ndarray:
    """Soft detuned saw-stack pad (2 voices per side per note), lowpassed."""
    n = ns(dur)
    t = t_axis(n)
    out = np.zeros((n, 2))
    for m in midis:
        f0 = midi_hz(m)
        kmax = int(max(2, min(14, cutoff * 1.8 / f0)))
        ks = np.arange(1, kmax + 1)
        amps = 1.0 / ks ** 1.15 * _mag_lp(f0 * ks, cutoff, 2)
        for ch, dets in enumerate(((1.0025, 0.9985), (0.9975, 1.0015))):
            for vi, det in enumerate(dets):
                ph = rng_for(f"{tag}.{m}.{ch}.{vi}").uniform(0, TWO_PI, kmax)
                out[:, ch] += (amps[:, None] * np.sin(
                    TWO_PI * f0 * det * ks[:, None] * t[None, :] + ph[:, None]
                )).sum(0) * 0.5
    env = np.minimum(1.0, t / attack)
    out *= env[:, None]
    fade_out(out, min(0.6, dur * 0.3))
    return norm_peak(out)


# --------------------------------------------------------------------------
# FX generators (also used inside the tracks)
# --------------------------------------------------------------------------

def swept_noise(dur: float, path_fn, bw_oct: float = 0.9,
                tag: str = "sweep") -> np.ndarray:
    """Block-filtered noise; band center follows path_fn(frac 0..1) in Hz."""
    n = ns(dur)
    x = rng_for(tag).standard_normal(n)
    block, hop = 4096, 2048
    win = np.hanning(block)
    out = np.zeros(n + block)
    pos = 0
    while pos < n:
        seg = x[pos:pos + block]
        if len(seg) < block:
            seg = np.pad(seg, (0, block - len(seg)))
        frac = min(1.0, (pos + block / 2) / n)
        fc = float(path_fn(frac))
        lo, hi = fc / 2 ** (bw_oct / 2), fc * 2 ** (bw_oct / 2)
        out[pos:pos + block] += bandpass(seg * win, lo, hi, 3)
        pos += hop
    return out[:n]


def synth_riser(dur: float, tag: str = "riser",
                f0: float = 350.0, f1: float = 8500.0) -> np.ndarray:
    n = ns(dur)
    t = t_axis(n)
    noise = swept_noise(dur, lambda x: f0 * (f1 / f0) ** x, 0.9, tag + ".n")
    frac = t / dur
    tone_f = midi_hz(45) * 2.0 ** (2.0 * frac)          # A2 -> A4 glide
    ph = TWO_PI * np.cumsum(tone_f) / SR
    tone = sum(np.sin(ph * k + rng_for(f"{tag}.t{k}").uniform(0, TWO_PI)) / k
               for k in (1, 2, 3, 4))
    x = noise * 0.8 + tone * 0.30
    x *= frac ** 1.8
    x = np.stack([x, np.roll(x, ns(0.012))], 1)          # width via Haas
    x[:ns(0.012), 1] = 0.0
    att_ramp(x, 0.01)
    fade_out(x, 0.008)
    return norm_peak(x)


def synth_sweep_down(dur: float, tag: str = "swdown") -> np.ndarray:
    n = ns(dur)
    x = swept_noise(dur, lambda p: 9000.0 * (450.0 / 9000.0) ** p, 1.0, tag)
    x *= exp_env(n, dur * 0.35)
    att_ramp(x, 0.004)
    fade_out(x, 0.05)
    return norm_peak(x)


def synth_impact(dur: float = 1.5, f_start: float = 85.0, f_end: float = 32.0,
                 tail_hz: float = 38.0, tag: str = "impact") -> np.ndarray:
    n = ns(dur)
    t = t_axis(n)
    freq = f_end + (f_start - f_end) * np.exp(-t / 0.06)
    body = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / 0.40)
    tail = np.sin(TWO_PI * tail_hz * t) * np.exp(-t / (dur * 0.45)) * 0.7
    bn = ns(0.05)
    boom = lowpass(rng_for(tag + ".boom").standard_normal(bn) * exp_env(bn, 0.02), 240, 3)
    x = body + tail
    x[:bn] += boom * 0.8
    cn = ns(0.004)
    click = bandpass(rng_for(tag + ".clk").standard_normal(cn) * exp_env(cn, 0.001),
                     1500, 7000, 2)
    x[:cn] += click * 0.35
    x = np.tanh(1.4 * x) / math.tanh(1.4)
    att_ramp(x, 0.001)
    fade_out(x, min(0.3, dur * 0.25))
    return norm_peak(x)


def pingpong_delay(x: np.ndarray, delay_s: float, fb: float = 0.42,
                   taps: int = 5, damp: float = 5500.0) -> np.ndarray:
    """Simple stereo ping-pong: alternating L/R echoes, progressively darker."""
    out = x.copy()
    d = ns(delay_s)
    wet = fft_filter(x, lambda f: _mag_lp(f, damp, 2))
    for i in range(1, taps + 1):
        g = fb ** i
        sh = np.zeros_like(x)
        sh[i * d:] = wet[: len(x) - i * d]
        if i % 2 == 1:
            sh = sh[:, ::-1]                              # bounce sides
        out += sh * g
        wet = fft_filter(wet, lambda f: _mag_lp(f, damp * 0.85, 1))
    return out


# --------------------------------------------------------------------------
# TRACK 1: hype_track  (140 BPM, A minor, EDM/Phonk hybrid)
# --------------------------------------------------------------------------

def build_hype():
    bpm = HYPE_BPM
    beat = 60.0 / bpm                                     # 0.428571 s
    bar = 4 * beat                                        # 1.714286 s
    music_end = 28 * bar                                  # 48.0 s
    total = music_end + 2.4                               # ring-out tail
    n = ns(total)

    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    pluckb = np.zeros((n, 2))
    padb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    kick = synth_kick()
    clap = synth_clap()
    hat_c = synth_hat(False)
    hat_o = synth_hat(True)
    shaker = synth_shaker()

    intro = range(0, 4)
    drop1 = range(4, 12)
    brk = range(12, 16)
    drop2 = range(16, 24)
    outro = range(24, 28)

    # ---- drums -----------------------------------------------------------
    kick_times = []
    for b in list(drop1) + list(drop2):
        for q in range(4):
            kick_times.append(b * bar + q * beat)
    for b in outro:
        kick_times += [b * bar, b * bar + 2 * beat]
    for kt in kick_times:
        add(drums, kick, kt, 0.85)

    for b in list(drop1) + list(drop2) + list(outro):
        add(drums, clap, b * bar + 1 * beat, 0.65)
        add(drums, clap, b * bar + 3 * beat, 0.70)

    hat_bars = list(intro) + list(drop1) + list(drop2) + list(outro)
    for b in hat_bars:
        lvl = 0.24 if b in intro else 0.40
        for q in range(4):
            add(drums, hat_c, b * bar + q * beat + beat / 2, lvl,
                pan=0.25 if q % 2 else -0.25)
    for b in list(drop1) + list(drop2):
        if b % 2 == 1:
            add(drums, hat_o, b * bar + 3 * beat + beat / 2, 0.35)
    for b in drop2:                                       # 16th shaker layer
        for s in range(16):
            add(drums, shaker, b * bar + s * beat / 4, 0.16,
                pan=0.35 if s % 2 else -0.35)

    # clap rolls into each drop
    for end_bar, hits in ((4, 4), (16, 8)):
        t0 = end_bar * bar - hits * beat / 4
        for i in range(hits):
            add(drums, clap, t0 + i * beat / 4, 0.22 + 0.42 * i / hits)

    # ---- sub bass (mono, rolling 8ths) ------------------------------------
    roots = [33, 29, 36, 31]                              # A1 F1 C2 G1
    for b in list(drop1) + list(drop2):
        root = roots[b % 4]
        for e in range(8):
            m = root + (12 if e == 7 else 0)
            add(bassb, synth_sub(m, beat / 2 * 0.92), b * bar + e * beat / 2, 0.34)
    for b in outro:
        add(bassb, synth_sub(33, bar * 0.95), b * bar, 0.28)

    # ---- pluck hook (A minor pentatonic, 2-bar phrase) ---------------------
    bar_a = [69, None, 69, 72, 69, None, 67, 64]
    bar_b = [69, None, 69, 72, 74, 72, 69, 67]

    def place_hook(bars, bright, gain, octave=False):
        for i, b in enumerate(bars):
            pat = bar_a if i % 2 == 0 else bar_b
            for e, m in enumerate(pat):
                if m is None:
                    continue
                t0 = b * bar + e * beat / 2
                add(pluckb, synth_pluck(m, 0.45, bright), t0, gain)
                if octave:
                    add(pluckb, synth_pluck(m + 12, 0.35, bright), t0, gain * 0.35)

    place_hook(list(intro), 0.80, 0.55)
    place_hook(list(drop1), 0.93, 0.85)
    place_hook(list(drop2), 0.93, 0.85, octave=True)
    place_hook([24, 25], 0.84, 0.50)
    # break: sparse long mellow notes
    for bb, qb, m in ((12, 0, 76), (12, 3, 74), (13, 2, 72),
                      (14, 0, 69), (14, 3, 72), (15, 2, 74)):
        add(pluckb, synth_pluck(m, 0.9, 0.78), bb * bar + qb * beat, 0.6)

    pluckb = pingpong_delay(pluckb, beat * 0.75, fb=0.40, taps=5)

    # ---- cowbell counter-melody (phonk flavour, drop 2 only) ---------------
    cow_a = [69, None, 69, None, 72, None, 67, None]
    cow_b = [69, None, 74, None, 72, None, 67, None]
    for i, b in enumerate(drop2):
        pat = cow_a if i % 2 == 0 else cow_b
        for e, m in enumerate(pat):
            if m is None:
                continue
            add(drums, synth_cowbell(m), b * bar + e * beat / 2, 0.17,
                pan=0.3 if e % 4 else -0.3)

    # ---- break pads (Am F C G) ---------------------------------------------
    chords = ([45, 52, 60, 64], [41, 53, 57, 60], [48, 55, 60, 64], [43, 50, 59, 62])
    for i, b in enumerate(brk):
        add(padb, synth_pad_chord(chords[i], bar * 1.3, 950, 0.5, f"hpad{i}"),
            b * bar, 0.30)

    # ---- FX: risers, sweeps, impacts ---------------------------------------
    add(fxb, synth_riser(2 * bar, "riser1"), 2 * bar, 0.34)
    add(fxb, synth_riser(2 * bar, "riser2"), 14 * bar, 0.38)
    add(fxb, synth_sweep_down(1.4, "sw1"), 4 * bar, 0.20)
    add(fxb, synth_sweep_down(1.4, "sw2"), 16 * bar, 0.20)
    add(fxb, swept_noise(1.7, lambda p: 800 * (7000 / 800) ** p, 1.0, "wn12") *
        np.linspace(0, 1, ns(1.7)) ** 2, 12 * bar - 1.7, 0.13)
    add(fxb, synth_impact(2.0, 85, 32, 38, "imp.d1"), 4 * bar, 0.75)
    add(fxb, synth_impact(2.0, 85, 32, 38, "imp.d2"), 16 * bar, 0.75)
    add(fxb, synth_impact(2.3, 80, 30, 36, "imp.end"), music_end, 0.80)

    # ---- sidechain pump (sparkling feel) ------------------------------------
    pump_times = [b * bar + q * beat
                  for b in list(intro) + list(drop1) + list(drop2) + list(outro)
                  for q in range(4)]
    env = pump_env(n, pump_times, depth=0.55)
    bassb *= env[:, None]
    pluckb *= env[:, None]

    mix = drums + bassb + pluckb + padb + fxb
    audio = master(mix, rms_target_db=-14.6, shelf=(3000.0, 7.0))

    beats = [round(i * beat, 6) for i in range(112)]
    meta = {
        "file": "hype_track.wav",
        "file_m4a": "hype_track.m4a",
        "bpm": bpm,
        "sample_rate": SR,
        "duration_sec": round(n / SR, 6),
        "first_beat_offset_sec": 0.0,
        "beats_sec": beats,
        "markers_sec": {
            "intro": 0.0,
            "drop1": round(4 * bar, 6),
            "break": round(12 * bar, 6),
            "drop2": round(16 * bar, 6),
            "outro": round(24 * bar, 6),
            "end": round(music_end, 6),
        },
    }
    return audio, meta


# --------------------------------------------------------------------------
# TRACK 2: clean_track  (105 BPM, C major, minimal Apple style)
# --------------------------------------------------------------------------

def build_clean():
    bpm = CLEAN_BPM
    beat = 60.0 / bpm                                     # 0.571429 s
    bar = 4 * beat                                        # 2.285714 s
    music_end = 20 * bar                                  # 45.714286 s
    total = 47.0
    n = ns(total)

    piano = np.zeros((n, 2))
    shimmer = np.zeros((n, 2))
    padb = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    perc = np.zeros((n, 2))

    c_add9 = [48, 55, 62, 64]
    g_b = [47, 55, 62, 67]
    am7 = [45, 55, 60, 64]
    fmaj9 = [41, 53, 57, 64, 67]
    loop = [c_add9, g_b, am7, fmaj9]

    vel_rng = rng_for("clean.vel")
    roll_rng = rng_for("clean.roll")

    def chord(buf, midis, t0, vel, dur, gain=1.0, oct_top=False):
        for i, m in enumerate(midis):
            off = i * 0.018 + float(roll_rng.uniform(0, 0.006))
            v = vel * float(vel_rng.uniform(0.9, 1.0))
            add(buf, synth_piano(m, dur, v), t0 + off, gain,
                pan=max(-0.5, min(0.5, (m - 56) / 40.0)))
        if oct_top:
            add(buf, synth_piano(midis[-1] + 12, dur * 0.8, vel * 0.5),
                t0 + 0.03, gain, pan=0.2)

    # intro: bars 0-3, sparse
    for i in range(4):
        chord(piano, loop[i], i * bar, 0.72, 3.4)
    add(piano, synth_piano(76, 2.0, 0.42), 1 * bar + 2 * beat, 1.0, pan=0.25)
    add(piano, synth_piano(74, 2.0, 0.40), 3 * bar + 2 * beat, 1.0, pan=-0.2)

    # chorus: bars 4-11 (2 chord loops + melody)
    melody = [(0, 2.0, 67), (0, 3.0, 69), (1, 0.0, 71), (1, 2.5, 67),
              (2, 0.0, 69), (2, 2.0, 72), (3, 0.0, 76), (3, 2.5, 74)]
    for rep in range(2):
        base = (4 + rep * 4)
        for i in range(4):
            chord(piano, loop[i], (base + i) * bar, 0.92, 3.4)
        for mb, mq, mm in melody:
            add(piano, synth_piano(mm, 1.6, 0.5), (base + mb) * bar + mq * beat,
                1.0, pan=0.15)

    # bridge/lift: bars 12-15, octave tops + higher melody
    lift_mel = [(0, 2.0, 76), (1, 0.0, 74), (2, 0.0, 72), (2, 2.0, 74), (3, 0.0, 76)]
    for i in range(4):
        chord(piano, loop[i], (12 + i) * bar, 0.95, 3.4, oct_top=True)
    for mb, mq, mm in lift_mel:
        add(piano, synth_piano(mm, 1.8, 0.5), (12 + mb) * bar + mq * beat,
            1.0, pan=0.15)

    # outro: bars 16-19, resolve and ring out
    chord(piano, fmaj9, 16 * bar, 0.85, 3.4)
    chord(piano, [43, 55, 62, 69], 17 * bar, 0.80, 3.4)
    chord(piano, [48, 55, 64, 71], 18 * bar, 0.88, 4.8)   # Cmaj9, rings out
    add(piano, synth_piano(84, 3.0, 0.32), 18 * bar + 2 * beat, 1.0, pan=0.3)

    # shimmer: octave-up ghost layer with dotted-8th ping-pong echoes
    shim_events = []
    for i in range(4):
        shim_events.append((loop[i], (4 + i) * bar))
        shim_events.append((loop[i], (8 + i) * bar))
        shim_events.append((loop[i], (12 + i) * bar))
    shim_events.append(([48, 55, 64, 71], 18 * bar))
    for midis, t0 in shim_events:
        for m in midis[-2:]:
            add(shimmer, synth_piano(m + 12, 1.8, 0.30), t0 + 0.05, 1.0)
    shimmer = pingpong_delay(shimmer, beat * 0.75, fb=0.5, taps=4, damp=8000)
    shimmer = highpass(shimmer, 500, 2)

    # pads: chorus + bridge, soft
    for rep in range(3):
        base = 4 + rep * 4
        for i in range(4):
            add(padb, synth_pad_chord(loop[i][1:], bar * 1.35, 1400, 0.9,
                                      f"cpad{rep}.{i}"), (base + i) * bar, 0.16)

    # bass: soft sine roots, chorus onwards
    broots = [36, 35, 33, 29]
    for b in range(4, 18):
        add(bassb, synth_sub(broots[b % 4], bar * 0.9), b * bar, 0.12)
    add(bassb, synth_sub(36, bar * 1.8), 18 * bar, 0.13)

    # pulse: thump downbeats, snaps 2+4, filtered hats
    thump = synth_thump()
    snap = synth_snap()
    hat_c = lowpass(synth_hat(False), 9500, 2)
    for b in range(2, 18):
        add(perc, thump, b * bar, 0.20)
    for b in range(4, 16):
        add(perc, snap, b * bar + 1 * beat, 0.45, pan=0.15)
        add(perc, snap, b * bar + 3 * beat, 0.50, pan=-0.1)
        for q in range(8):
            add(perc, hat_c, b * bar + q * beat / 2, 0.26,
                pan=0.3 if q % 2 else -0.3)

    mix = piano * 0.9 + shimmer * 0.30 + padb + bassb + perc
    audio = master(mix, rms_target_db=-15.4, shelf=(2200.0, 9.0))

    beats = [round(i * beat, 6) for i in range(80)]
    meta = {
        "file": "clean_track.wav",
        "file_m4a": "clean_track.m4a",
        "bpm": bpm,
        "sample_rate": SR,
        "duration_sec": round(n / SR, 6),
        "first_beat_offset_sec": 0.0,
        "beats_sec": beats,
        "markers_sec": {
            "intro": 0.0,
            "chorus": round(4 * bar, 6),
            "bridge": round(12 * bar, 6),
            "outro": round(16 * bar, 6),
            "end": round(music_end, 6),
        },
    }
    return audio, meta


# --------------------------------------------------------------------------
# SFX pack
# --------------------------------------------------------------------------

def sfx_whoosh(dur, path_fn, tag):
    n = ns(dur)
    t = t_axis(n)
    x = swept_noise(dur, path_fn, 1.1, tag)
    env = np.sin(np.pi * np.minimum(1.0, t / dur)) ** 1.4
    x *= env
    # stereo motion L -> R
    gl = np.linspace(0.95, 0.35, n)
    st = np.stack([x * gl, x * gl[::-1]], 1)
    att_ramp(st, 0.008)
    fade_out(st, 0.03)
    return st


def sfx_fizz_open():
    """Can opening: click/crack + pressure hiss + bubble sparkle (~1.2 s)."""
    dur = 1.2
    n = ns(dur)
    out = np.zeros(n)
    r = rng_for("fizz")
    cn = ns(0.006)
    for off, g in ((0.0, 1.0), (0.014, 0.7)):
        click = bandpass(r.standard_normal(cn) * exp_env(cn, 0.0012), 1500, 8000, 2)
        i = ns(off)
        out[i:i + cn] += click * g
    hn = n - ns(0.02)
    hiss = highpass(r.standard_normal(hn), 2800, 2)
    henv = np.minimum(1.0, t_axis(hn) / 0.004) * (0.28 + 0.72 * exp_env(hn, 0.16))
    out[ns(0.02):] += hiss * henv * 0.30
    # bubbles: little rising chirps
    for _ in range(110):
        t0 = float(r.uniform(0.12, dur - 0.03))
        f = float(r.uniform(700, 3200))
        bn = ns(float(r.uniform(0.004, 0.012)))
        bt = t_axis(bn)
        blip = np.sin(TWO_PI * f * (1 + 18 * bt) * bt) * exp_env(bn, 0.004)
        i = ns(t0)
        out[i:i + bn] += blip * float(r.uniform(0.05, 0.16))
    st = np.stack([out, np.roll(out, ns(0.006))], 1)
    st[:ns(0.006), 1] = 0.0
    att_ramp(st, 0.0005)
    fade_out(st, 0.08)
    return st


def sfx_sparkle_pop():
    dur = 0.5
    n = ns(dur)
    out = np.zeros((n, 2))
    pn = ns(0.03)
    pt = t_axis(pn)
    freq = 90 + 190 * np.exp(-pt / 0.006)
    pop = np.sin(TWO_PI * np.cumsum(freq) / SR) * exp_env(pn, 0.012)
    add(out, pop, 0.0, 0.9)
    penta = [1568.0, 1760.0, 2093.0, 2637.0, 3136.0, 3520.0, 4186.0]
    for i, f in enumerate(penta):
        bn = ns(0.09)
        bt = t_axis(bn)
        blip = (np.sin(TWO_PI * f * bt) + 0.4 * np.sin(TWO_PI * 2 * f * bt))
        blip *= exp_env(bn, 0.035)
        add(out, blip, 0.02 + i * 0.022, 0.28, pan=0.5 if i % 2 else -0.5)
    gn = ns(0.4)
    glit = highpass(rng_for("pop.glit").standard_normal(gn) * exp_env(gn, 0.10),
                    6000, 2)
    add(out, glit, 0.02, 0.18)
    att_ramp(out, 0.0005)
    fade_out(out, 0.05)
    return out


def sfx_ui_tick():
    dur = 0.2
    n = ns(dur)
    out = np.zeros((n, 2))
    cn = ns(0.004)
    click = bandpass(rng_for("tick").standard_normal(cn) * exp_env(cn, 0.0008),
                     2500, 7000, 2)
    add(out, click, 0.0, 1.0)
    bn = ns(0.06)
    blip = np.sin(TWO_PI * 1650 * t_axis(bn)) * exp_env(bn, 0.014)
    add(out, blip, 0.001, 0.5)
    fade_out(out, 0.02)
    return out


def build_sfx() -> dict:
    return {
        "whoosh_1": sfx_whoosh(0.5, lambda p: 400 * (3800 / 400) ** p, "wh1"),
        "whoosh_2": sfx_whoosh(0.75, lambda p: 4500 * (350 / 4500) ** p, "wh2"),
        "whoosh_3": sfx_whoosh(1.0, lambda p: 500 * (5000 / 500) **
                               math.sin(math.pi * p), "wh3"),
        "impact_1": np.stack([synth_impact(1.5, 85, 30, 36, "sfx.imp1")] * 2, 1),
        "impact_2": np.stack([synth_impact(1.1, 110, 45, 45, "sfx.imp2")] * 2, 1),
        "riser_short": synth_riser(1.3, "sfx.riser", 300, 9000),
        "fizz_open": sfx_fizz_open(),
        "sparkle_pop": sfx_sparkle_pop(),
        "ui_tick": sfx_ui_tick(),
    }


# --------------------------------------------------------------------------
# mastering / file IO
# --------------------------------------------------------------------------

def master(x: np.ndarray, rms_target_db: float, peak_db: float = PEAK_DB,
           shelf: tuple = (3000.0, 6.0)):
    x = x - x.mean(axis=0, keepdims=True)                 # kill DC
    x = highpass(x, 24, 2)
    sf, sdb = shelf                                       # air/presence shelf
    x = fft_filter(x, lambda f: 1.0 + (db(sdb) - 1.0) * _mag_hp(f, sf, 1))
    mid = x.mean(1)
    side = highpass((x[:, 0] - x[:, 1]) * 0.5, 220, 6)    # bass mono < ~200 Hz
    x = np.stack([mid + side, mid - side], 1)
    x *= db(rms_target_db) / max(rms(x), 1e-9)
    p = db(peak_db)
    x = np.tanh(x / p) * p                                # soft-knee limiter
    x *= p / np.max(np.abs(x))                            # exact peak ceiling
    att_ramp(x, 0.003)
    fade_out(x, 0.35)
    return x


def write_wav(path: str, x: np.ndarray) -> None:
    y = np.clip(x, -1.0, 1.0)
    pcm = np.round(y * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path: str):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        nch = w.getnchannels()
        raw = w.readframes(w.getnframes())
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return x.reshape(-1, nch), sr


def encode_m4a(wav_path: str, m4a_path: str) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-nostdin", "-loglevel", "error", "-i", wav_path,
         "-c:a", "aac", "-b:a", "192k", "-ar", str(SR),
         "-movflags", "+faststart", "-map_metadata", "-1", "-bitexact",
         m4a_path],
        check=True,
    )


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def analyze(x: np.ndarray, label: str) -> None:
    peak = to_db(float(np.max(np.abs(x))))
    level = to_db(rms(x))
    dc = float(np.max(np.abs(x.mean(0))))
    mono = x.mean(1)
    spec = np.abs(np.fft.rfft(mono)) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1 / SR)
    bands = [(20, 120), (120, 500), (500, 2000), (2000, 8000), (8000, 20000)]
    tot = spec[(freqs >= 20) & (freqs < 20000)].sum()
    pct = [100 * spec[(freqs >= lo) & (freqs < hi)].sum() / tot for lo, hi in bands]
    print(f"  {label}: peak {peak:+.2f} dBFS | rms {level:+.2f} dBFS | "
          f"DC {dc:.2e} | bands sub/low/mid/hi/air = "
          + "/".join(f"{p:.1f}%" for p in pct))


# --------------------------------------------------------------------------
# generation entry point
# --------------------------------------------------------------------------

ALL_FILES = [
    "hype_track.wav", "hype_track.m4a",
    "clean_track.wav", "clean_track.m4a",
    "whoosh_1.wav", "whoosh_2.wav", "whoosh_3.wav",
    "impact_1.wav", "impact_2.wav", "riser_short.wav",
    "fizz_open.wav", "sparkle_pop.wav", "ui_tick.wav",
    BEAT_GRID,
]


def generate() -> None:
    print("[1/4] rendering hype_track (140 BPM, EDM/Phonk) ...")
    hype, hype_meta = build_hype()
    analyze(hype, "hype_track")
    write_wav(os.path.join(HERE, "hype_track.wav"), hype)

    print("[2/4] rendering clean_track (105 BPM, minimal) ...")
    clean, clean_meta = build_clean()
    analyze(clean, "clean_track")
    write_wav(os.path.join(HERE, "clean_track.wav"), clean)

    print("[3/4] rendering SFX pack ...")
    sfx_meta = {}
    for name, sig in build_sfx().items():
        sig = sig - sig.mean(axis=0, keepdims=True)
        sig = norm_peak(sig, db(PEAK_DB))
        write_wav(os.path.join(HERE, f"{name}.wav"), sig)
        sfx_meta[name] = {
            "file": f"{name}.wav",
            "duration_sec": round(len(sig) / SR, 6),
        }

    print("[4/4] beat grid + m4a encodes ...")
    grid = {
        "version": 1,
        "seed": SEED,
        "sample_rate": SR,
        "generator": "generate_audio.py",
        "tracks": {"hype_track": hype_meta, "clean_track": clean_meta},
        "sfx": sfx_meta,
    }
    with open(os.path.join(HERE, BEAT_GRID), "w") as f:
        json.dump(grid, f, indent=2, sort_keys=True)
        f.write("\n")

    encode_m4a(os.path.join(HERE, "hype_track.wav"),
               os.path.join(HERE, "hype_track.m4a"))
    encode_m4a(os.path.join(HERE, "clean_track.wav"),
               os.path.join(HERE, "clean_track.m4a"))
    print("done.")
    checksums()


def checksums() -> None:
    for name in ALL_FILES:
        p = os.path.join(HERE, name)
        print(f"  {sha256(p)}  {name}")


# --------------------------------------------------------------------------
# --verify
# --------------------------------------------------------------------------

class Verifier:
    def __init__(self):
        self.fails = 0

    def check(self, ok: bool, msg: str) -> None:
        print(f"  [{'PASS' if ok else 'FAIL'}] {msg}")
        if not ok:
            self.fails += 1


def ffprobe_duration(path: str) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return float(out)


def verify() -> int:
    v = Verifier()
    with open(os.path.join(HERE, BEAT_GRID)) as f:
        grid = json.load(f)
    v.check(grid["sample_rate"] == SR, f"beat_grid sample_rate == {SR}")

    track_rms = {}
    ranges = {"hype_track": (45.0, 55.0), "clean_track": (40.0, 50.0)}
    for name, meta in grid["tracks"].items():
        print(f"-- {name}")
        x, sr = read_wav(os.path.join(HERE, meta["file"]))
        dur = len(x) / sr
        v.check(sr == SR, f"wav sample rate {sr}")
        v.check(bool(np.all(np.isfinite(x))), "all samples finite")
        peak = to_db(float(np.max(np.abs(x))))
        v.check(-2.5 <= peak <= -1.0, f"peak {peak:+.2f} dBFS in [-2.5, -1.0]")
        dc = float(np.max(np.abs(x.mean(0))))
        v.check(dc < 1e-3, f"DC offset {dc:.2e} < 1e-3")
        lo, hi = ranges[name]
        v.check(lo <= dur <= hi, f"duration {dur:.3f}s in [{lo}, {hi}]")
        v.check(abs(dur - meta["duration_sec"]) < 1e-4,
                "duration matches beat_grid.json")
        level = to_db(rms(x))
        track_rms[name] = level
        v.check(-20.0 <= level <= -9.0, f"overall RMS {level:+.2f} dBFS in [-20, -9]")
        # windowed RMS: no window too hot, loudest section is a drop/chorus
        w = ns(0.4)
        nwin = len(x) // w
        wr = np.sqrt(np.square(x[: nwin * w]).reshape(nwin, -1).mean(1))
        v.check(to_db(float(wr.max())) <= -6.0,
                f"max 400ms-window RMS {to_db(float(wr.max())):+.2f} <= -6 dBFS")
        first_marker = ("drop1" if name == "hype_track" else "chorus")
        m_t = meta["markers_sec"][first_marker]
        e_sec = rms(x[ns(m_t + 0.5):ns(m_t + 3.0)])
        e_intro = rms(x[ns(0.5):ns(3.0)])
        v.check(e_sec > e_intro,
                f"{first_marker} louder than intro "
                f"({to_db(e_sec):+.1f} vs {to_db(e_intro):+.1f} dBFS)")
        # beat grid consistency
        beats = meta["beats_sec"]
        step = 60.0 / meta["bpm"]
        diffs = np.diff(beats)
        v.check(bool(np.all(np.abs(diffs - step) < 1e-5)),
                f"beat spacing == {step:.6f}s")
        v.check(abs(beats[0] - meta["first_beat_offset_sec"]) < 1e-9,
                "first beat == first_beat_offset_sec")
        v.check(all(0.0 <= t <= dur for t in meta["markers_sec"].values()),
                "all markers inside file duration")
        # edges: no clicks at start/end (musical onsets ramp from zero)
        v.check(float(np.abs(x[0]).max()) < 1e-3 and
                float(np.abs(x[:ns(0.0005)]).max()) < 0.1,
                "clean start (ramps from zero, no click)")
        v.check(float(np.abs(x[-ns(0.01):]).max()) < 0.01, "clean end (fade to 0)")
        # bass mono below 100 Hz
        lp = lowpass(x, 100, 4)
        denom = float(np.sqrt(np.mean(lp[:, 0] ** 2) * np.mean(lp[:, 1] ** 2)))
        corr = float(np.mean(lp[:, 0] * lp[:, 1])) / max(denom, 1e-12)
        v.check(corr > 0.97, f"bass mono: <100 Hz L/R correlation {corr:.4f} > 0.97")
        # m4a present and same length
        mdur = ffprobe_duration(os.path.join(HERE, meta["file_m4a"]))
        v.check(abs(mdur - dur) < 0.2,
                f"m4a duration {mdur:.3f}s matches wav ({dur:.3f}s)")

    print("-- loudness match")
    diff = abs(track_rms["hype_track"] - track_rms["clean_track"])
    v.check(diff <= 3.0, f"track RMS difference {diff:.2f} dB <= 3 dB")

    print("-- sfx")
    for name, meta in grid["sfx"].items():
        x, sr = read_wav(os.path.join(HERE, meta["file"]))
        dur = len(x) / sr
        peak = to_db(float(np.max(np.abs(x))))
        dc = float(np.max(np.abs(x.mean(0))))
        ok = (sr == SR and 0.2 <= dur <= 1.5 and -2.5 <= peak <= -1.0
              and dc < 1e-3 and abs(dur - meta["duration_sec"]) < 1e-4)
        v.check(ok, f"{name}: dur {dur:.3f}s, peak {peak:+.2f} dBFS, DC {dc:.1e}")

    print(f"\n{'ALL CHECKS PASSED' if v.fails == 0 else str(v.fails) + ' CHECK(S) FAILED'}")
    return 1 if v.fails else 0


# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verify", action="store_true", help="run QC checks only")
    ap.add_argument("--checksums", action="store_true", help="print sha256 only")
    args = ap.parse_args()
    if args.verify:
        return verify()
    if args.checksums:
        checksums()
        return 0
    generate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
