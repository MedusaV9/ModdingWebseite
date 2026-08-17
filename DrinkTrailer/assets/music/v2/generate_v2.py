#!/usr/bin/env python3
"""
generate_v2.py -- deterministic, 100% self-synthesized v2 music library
for the 35 EARLY short trailers (DrinkTrailer/assets/music/v2).

Like v1 (assets/music/generate_audio.py) everything is rendered from scratch
with numpy: no samples, no loops, no third-party audio. One fixed seed =>
byte-identical output on every run. ffmpeg is only used to transcode the WAV
masters to .m4a (AAC, -bitexact => deterministic too).

The 10 tracks are TIMING MASTERS and STYLE PLACEHOLDERS in clearly distinct
genres: the client licenses real songs later via their agency (see
MUSIC_BRIEF.md next to this script); trailer cuts sync against tracks_v2.json,
not against these files, so any licensed song can replace a track 1:1.

Tracks (id / BPM): phonk_drift 132, house_groove 124, hyperpop_rush 150,
techno_strobe 138, lofi_morning 82, cinematic_epic 75 (halftime),
dnb_energy 174, trap_bounce 140, indie_pop_sun 112, ambient_air 70.

Outputs (all relative to this script):
  <track>.wav / <track>.m4a   10 tracks, 30-60 s, 48 kHz stereo, peak -1.5 dBFS
  tracks_v2.json              per track: id, file, BPM, first beat offset,
                              all beat times, markers (drop/chorus/break/outro)
  beat_grid_v2.json           byte-identical copy of tracks_v2.json under the
                              name the remotion sync script expects

Usage:
  python3 generate_v2.py                 # render everything
  python3 generate_v2.py --verify        # QC: container/peak/duration/JSON
  python3 generate_v2.py --checksums     # sha256 of all outputs (determinism)
  python3 generate_v2.py --only <track>  # dev aid: re-render one track
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
SEED = 20260817
HERE = os.path.dirname(os.path.abspath(__file__))
TWO_PI = 2.0 * np.pi
PEAK_DB = -1.5                     # master ceiling for all tracks
TRACKS_JSON = "tracks_v2.json"
GRID_COMPAT = "beat_grid_v2.json"  # remotion sync-assets looks for this name


# --------------------------------------------------------------------------
# deterministic RNG / basic helpers (v1 pattern)
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


def _mag_reslp(f, fc, q=4.0, o=2):
    """Lowpass with a resonance bump at the cutoff (acid/303 flavour)."""
    lp = _mag_lp(f, fc, o)
    peak = q * np.exp(-0.5 * ((f - fc) / (0.16 * fc + 1e-9)) ** 2)
    return lp * (1.0 + peak)


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


def block_filter(x: np.ndarray, mag_at, block: int = 4096, hop: int = 2048):
    """Time-varying zero-phase filter (overlap-add, hann windows).
    mag_at(frac, freqs) -> magnitude curve for block centered at frac 0..1."""
    mono = x.ndim == 1
    if mono:
        x = x[:, None]
    n = len(x)
    win = np.hanning(block)
    freqs = np.fft.rfftfreq(block, 1.0 / SR)
    out = np.zeros((n + block, x.shape[1]))
    pos = 0
    while pos < n:
        frac = min(1.0, (pos + block / 2) / n)
        mag = mag_at(frac, freqs)
        for c in range(x.shape[1]):
            seg = x[pos:pos + block, c]
            if len(seg) < block:
                seg = np.pad(seg, (0, block - len(seg)))
            out[pos:pos + block, c] += np.fft.irfft(np.fft.rfft(seg * win) * mag, block)
        pos += hop
    out = out[:n]
    return out[:, 0] if mono else out


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


def sat(x: np.ndarray, k: float) -> np.ndarray:
    return np.tanh(k * x) / math.tanh(k)


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

def synth_kick(tag: str = "kick", punch: float = 1.0) -> np.ndarray:
    n = ns(0.32)
    t = t_axis(n)
    freq = 46.0 + 118.0 * punch * np.exp(-t / 0.042)
    body = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / 0.115)
    body = sat(body, 2.4)
    cn = ns(0.005)
    click = rng_for(tag + ".click").standard_normal(cn) * exp_env(cn, 0.0012)
    body[:cn] += bandpass(click, 2000, 9000, 2) * 0.9
    att_ramp(body, 0.0004)
    fade_out(body, 0.012)
    return norm_peak(body)


def synth_kick_tight(tag: str = "kick.dnb") -> np.ndarray:
    """Shorter, punchier kick for fast genres (DnB)."""
    n = ns(0.18)
    t = t_axis(n)
    freq = 52.0 + 150.0 * np.exp(-t / 0.028)
    body = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / 0.055)
    body = sat(body, 2.0)
    cn = ns(0.004)
    click = rng_for(tag + ".click").standard_normal(cn) * exp_env(cn, 0.001)
    body[:cn] += bandpass(click, 2500, 10000, 2) * 0.8
    att_ramp(body, 0.0004)
    fade_out(body, 0.01)
    return norm_peak(body)


def synth_clap(tag: str = "clap") -> np.ndarray:
    n = ns(0.30)
    out = np.zeros(n)
    r = rng_for(tag)
    for k, off in enumerate((0.0, 0.010, 0.021, 0.032)):
        bn = ns(0.014)
        burst = r.standard_normal(bn) * exp_env(bn, 0.0045)
        i = ns(off)
        out[i:i + bn] += burst * (0.8 + 0.2 * (k == 3))
    tn = ns(0.24)
    tail = r.standard_normal(tn) * exp_env(tn, 0.055)
    out[ns(0.032):ns(0.032) + tn] += tail * 0.8
    out = bandpass(out, 500, 8500, 2)
    out += bandpass(out, 900, 1500, 2) * 0.7
    att_ramp(out, 0.0008)
    fade_out(out, 0.02)
    return norm_peak(out)


def synth_snare(tone: float = 190.0, noise_bal: float = 0.72,
                dur: float = 0.26, tag: str = "snare") -> np.ndarray:
    n = ns(dur)
    t = t_axis(n)
    body = np.sin(TWO_PI * np.cumsum(tone + 55.0 * np.exp(-t / 0.02)) / SR)
    body *= np.exp(-t / 0.055)
    nz = rng_for(tag).standard_normal(n) * exp_env(n, dur * 0.22)
    nz = bandpass(nz, 1100, 9500, 2)
    x = norm_peak(body) * (1.0 - noise_bal) + norm_peak(nz) * noise_bal
    cn = ns(0.004)
    crack = bandpass(rng_for(tag + ".crk").standard_normal(cn) * exp_env(cn, 0.001),
                     3000, 11000, 2)
    x[:cn] += crack * 0.6
    x = sat(x, 1.6)
    att_ramp(x, 0.0005)
    fade_out(x, 0.015)
    return norm_peak(x)


def synth_hat(open_hat: bool = False, tag: str = "") -> np.ndarray:
    dur = 0.30 if open_hat else 0.055
    n = ns(dur)
    t = t_axis(n)
    r = rng_for(("hat.open" if open_hat else "hat.closed") + tag)
    noise = r.standard_normal(n) * (1.0 + 0.6 * np.sin(TWO_PI * 7900 * t))
    noise *= exp_env(n, 0.085 if open_hat else 0.014)
    out = highpass(noise, 6800, 3)
    att_ramp(out, 0.0005)
    fade_out(out, 0.01)
    return norm_peak(out)


def synth_shaker(tag: str = "shaker") -> np.ndarray:
    n = ns(0.09)
    r = rng_for(tag)
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


def synth_snap(tag: str = "snap") -> np.ndarray:
    n = ns(0.16)
    r = rng_for(tag)
    body = r.standard_normal(n) * exp_env(n, 0.018)
    out = bandpass(body, 1200, 4200, 2)
    out += lowpass(r.standard_normal(n) * exp_env(n, 0.010), 500, 3) * 0.5
    att_ramp(out, 0.0006)
    fade_out(out, 0.02)
    return norm_peak(out)


def synth_taiko(tag: str = "taiko") -> np.ndarray:
    n = ns(0.75)
    t = t_axis(n)
    freq = 57.0 + 95.0 * np.exp(-t / 0.05)
    body = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / 0.24)
    r = rng_for(tag)
    sn = ns(0.06)
    skin = bandpass(r.standard_normal(sn) * exp_env(sn, 0.018), 300, 2600, 2)
    body[:sn] += skin * 0.55
    room = lowpass(r.standard_normal(n) * exp_env(n, 0.13), 750, 2)
    x = sat(body + room * 0.30, 1.8)
    att_ramp(x, 0.0008)
    fade_out(x, 0.05)
    return norm_peak(x)


def synth_crash(dur: float = 1.6, tag: str = "crash") -> np.ndarray:
    n = ns(dur)
    r = rng_for(tag)
    x = highpass(r.standard_normal(n), 4200, 2) * exp_env(n, dur * 0.30)
    x += bandpass(r.standard_normal(n), 7500, 15000, 2) * exp_env(n, dur * 0.18) * 0.7
    st = np.stack([x, np.roll(x, ns(0.009))], 1)
    st[:ns(0.009), 1] = 0.0
    att_ramp(st, 0.001)
    fade_out(st, 0.1)
    return norm_peak(st)


def synth_rumble(tag: str = "rumble") -> np.ndarray:
    """Dark techno rumble tail (goes right after each kick)."""
    n = ns(0.55)
    t = t_axis(n)
    r = rng_for(tag)
    nz = lowpass(r.standard_normal(n), 115, 3)
    env = np.minimum(1.0, t / 0.02) * np.exp(-t / 0.18)
    x = nz * env
    x += np.sin(TWO_PI * 43.0 * t) * np.exp(-t / 0.28) * 0.8
    x = sat(x, 1.7)
    att_ramp(x, 0.004)
    fade_out(x, 0.04)
    return norm_peak(x)


# --------------------------------------------------------------------------
# tonal synths
# --------------------------------------------------------------------------

def synth_sub(midi: float, dur: float) -> np.ndarray:
    f = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)
    x = np.sin(TWO_PI * f * t) + 0.22 * np.sin(TWO_PI * 2 * f * t) * np.exp(-t / 0.09)
    x = sat(x, 1.5)
    att_ramp(x, 0.004)
    fade_out(x, 0.025)
    return x


def synth_808(midi: float, dur: float, glide_from: float | None = None,
              glide_t: float = 0.08, drive: float = 2.5,
              tag: str = "808") -> np.ndarray:
    """Long saturated 808: pitch glides from glide_from (or a punch drop-in)."""
    n = ns(dur)
    t = t_axis(n)
    f1 = midi_hz(midi)
    f0 = midi_hz(glide_from) if glide_from is not None else f1 * 2.6
    freq = f1 + (f0 - f1) * np.exp(-t / max(glide_t / 2.8, 1e-4))
    ph = TWO_PI * np.cumsum(freq) / SR
    x = np.sin(ph) + 0.18 * np.sin(2 * ph) * np.exp(-t / 0.10)
    x = sat(x, drive)
    x *= np.minimum(1.0, t / 0.003) * np.exp(-t / (dur * 1.4))
    cn = ns(0.004)
    click = bandpass(rng_for(tag + ".clk").standard_normal(cn) * exp_env(cn, 0.001),
                     900, 5000, 2)
    x[:cn] += click * 0.22
    x = lowpass(x, 4500, 2)
    att_ramp(x, 0.001)
    fade_out(x, 0.02)
    return norm_peak(x)


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
    """Warm FM/additive piano stack (v1): inharmonic partials, hammer + thump."""
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
        fk = f * ks * np.sqrt(1.0 + 0.00038 * ks ** 2)
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


def synth_supersaw(midi: float, dur: float, bend: float = 0.0,
                   bend_t: float = 0.07, voices: int = 5, det: float = 0.010,
                   tag: str = "ss") -> np.ndarray:
    """Bright detuned saw stack with an exponential pitch bend into the note."""
    n = ns(dur)
    t = t_axis(n)
    f0 = midi_hz(midi)
    bendrat = 2.0 ** (bend / 12.0)
    fenv = f0 * (1.0 + (bendrat - 1.0) * np.exp(-t / max(bend_t / 3.0, 1e-4)))
    out = np.zeros((n, 2))
    r = rng_for(f"{tag}.{midi}.{round(bend, 2)}")
    kmax = int(max(2, min(10, 12000.0 / f0)))
    for v in range(voices):
        d = 1.0 + det * ((v / (voices - 1)) * 2.0 - 1.0) if voices > 1 else 1.0
        base = TWO_PI * np.cumsum(fenv * d) / SR + float(r.uniform(0, TWO_PI))
        sig = sum(np.sin(base * k) / k for k in range(1, kmax + 1))
        pan = ((v % 2) * 2 - 1) * (0.2 + 0.6 * v / max(voices - 1, 1))
        th = (max(-1.0, min(1.0, pan)) + 1.0) * np.pi / 4.0
        out[:, 0] += sig * math.cos(th)
        out[:, 1] += sig * math.sin(th)
    env = np.minimum(1.0, t / 0.01) * np.exp(-t / (dur * 2.2))
    out *= env[:, None]
    out = norm_peak(out)
    att_ramp(out, 0.003)
    fade_out(out, 0.05)
    return out


def synth_reese(midi: float, dur: float, tag: str = "reese") -> np.ndarray:
    """Two beating detuned saws + sub sine, driven and lowpassed (DnB)."""
    f = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)
    x = np.zeros(n)
    for i, det in enumerate((1.0065, 0.9935)):
        kmax = int(max(3, min(22, 3800.0 / f)))
        ks = np.arange(1, kmax + 1)
        ph = rng_for(f"{tag}.{midi}.{i}").uniform(0, TWO_PI, kmax)
        x += (np.sin(TWO_PI * f * det * ks[:, None] * t[None, :] + ph[:, None])
              / ks[:, None]).sum(0)
    x = norm_peak(x)
    x = sat(x, 2.4)
    x = lowpass(x, 1100, 2)
    x += np.sin(TWO_PI * f * t) * 0.55
    att_ramp(x, 0.008)
    fade_out(x, 0.03)
    return norm_peak(x)


def synth_acid(midi: float, dur: float, cutoff: float, accent: float = 0.0,
               tag: str = "acid") -> np.ndarray:
    """One 303-ish 16th note: driven saw through a resonant lowpass."""
    f0 = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)
    kmax = int(max(3, min(40, 12000.0 / f0)))
    ks = np.arange(1, kmax + 1)
    ph = rng_for(f"{tag}.{midi}").uniform(0, TWO_PI, kmax)
    x = (np.sin(TWO_PI * f0 * ks[:, None] * t[None, :] + ph[:, None])
         / ks[:, None]).sum(0)
    x = sat(norm_peak(x), 2.6)
    fc = cutoff * (1.0 + 0.9 * accent)
    x = fft_filter(x, lambda f: _mag_reslp(f, fc, q=4.5, o=2))
    x *= np.exp(-t / (dur * 0.55)) * (1.0 + 0.5 * accent)
    att_ramp(x, 0.001)
    fade_out(x, 0.008)
    return norm_peak(x)


_BELL_CACHE: dict = {}


def synth_bell(midi: float, dur: float = 1.1, tau_scale: float = 1.0,
               tag: str = "bell") -> np.ndarray:
    """Inharmonic FM-style bell (trap lead / glockenspiel)."""
    key = (midi, round(dur, 3), round(tau_scale, 3), tag)
    if key in _BELL_CACHE:
        return _BELL_CACHE[key]
    f0 = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)
    r = rng_for(f"{tag}.{midi}")
    parts = ((1.0, 1.0, 0.70), (2.0, 0.42, 0.34), (2.76, 0.30, 0.22),
             (5.40, 0.12, 0.10), (8.93, 0.05, 0.05))
    x = np.zeros(n)
    for ratio, amp, tau in parts:
        if f0 * ratio > 16000:
            continue
        x += (amp * np.sin(TWO_PI * f0 * ratio * t + float(r.uniform(0, TWO_PI)))
              * np.exp(-t / (tau * tau_scale)))
    cn = ns(0.003)
    strike = bandpass(rng_for(f"{tag}.strike.{midi}").standard_normal(cn)
                      * exp_env(cn, 0.0008), 2000, 9000, 2)
    x[:cn] += strike * 0.25
    st = np.stack([x, np.roll(x, ns(0.006))], 1)
    st[:ns(0.006), 1] = 0.0
    att_ramp(st, 0.001)
    fade_out(st, 0.04)
    st = norm_peak(st)
    _BELL_CACHE[key] = st
    return st


_RHODES_CACHE: dict = {}


def synth_rhodes(midi: int, dur: float, vel: float = 1.0) -> np.ndarray:
    """Dusty EP key: FM-ish partials, wow (slow pitch wobble), tremolo."""
    key = (midi, round(dur, 3))
    if key in _RHODES_CACHE:
        return _RHODES_CACHE[key] * vel
    f = midi_hz(midi)
    n = ns(dur)
    t = t_axis(n)
    r = rng_for(f"rhodes.{midi}")
    wow = 1.0 + 0.0035 * np.sin(TWO_PI * 0.6 * t + float(r.uniform(0, TWO_PI)))
    ph = TWO_PI * f * np.cumsum(wow) / SR
    x = np.sin(ph) * np.exp(-t / 1.5)
    x += 0.38 * np.sin(2 * ph + 0.4) * np.exp(-t / 0.45)
    x += 0.10 * np.sin(6.24 * ph) * np.exp(-t / 0.10)
    x *= 1.0 + 0.18 * np.sin(TWO_PI * 4.6 * t + float(r.uniform(0, TWO_PI)))
    cn = ns(0.006)
    click = lowpass(rng_for(f"rhodes.clk.{midi}").standard_normal(cn)
                    * exp_env(cn, 0.0015), 3000, 2)
    x[:cn] += click * 0.06
    x = lowpass(x, 3400, 2)
    st = np.stack([x, np.roll(x, ns(0.007))], 1)
    st[:ns(0.007), 1] = 0.0
    att_ramp(st, 0.002)
    fade_out(st, 0.05)
    st = norm_peak(st)
    _RHODES_CACHE[key] = st
    return st * vel


_KS_CACHE: dict = {}


def synth_guitar(midi: int, dur: float = 0.8, damp: float = 0.995,
                 tag: str = "gtr") -> np.ndarray:
    """Karplus-Strong plucked string, two detuned voices for stereo."""
    key = (midi, round(dur, 3), round(damp, 4), tag)
    if key in _KS_CACHE:
        return _KS_CACHE[key]
    n = ns(dur)

    def voice(p_off: int, vtag: str) -> np.ndarray:
        f0 = midi_hz(midi)
        p = max(2, int(round(SR / f0 - 0.5)) + p_off)
        burst = rng_for(f"ks.{vtag}.{midi}").uniform(-1.0, 1.0, p)
        burst = lowpass(burst, 7000, 2)
        chunks = [burst]
        prev, carry, total = burst, 0.0, p
        while total < n:
            shifted = np.empty_like(prev)
            shifted[0] = carry
            shifted[1:] = prev[:-1]
            cur = damp * 0.5 * (prev + shifted)
            chunks.append(cur)
            carry = prev[-1]
            prev = cur
            total += p
        return np.concatenate(chunks)[:n]

    x = np.stack([voice(0, "L" + tag), voice(1, "R" + tag)], 1)
    x = highpass(x, 70, 2)
    att_ramp(x, 0.0008)
    fade_out(x, 0.05)
    x = norm_peak(x)
    _KS_CACHE[key] = x
    return x


def heart_thump(f0: float = 60.0, dur: float = 0.16, tag: str = "lub") -> np.ndarray:
    n = ns(dur)
    t = t_axis(n)
    freq = f0 * (0.55 + 0.45 * np.exp(-t / 0.025))
    x = np.sin(TWO_PI * np.cumsum(freq) / SR) * np.exp(-t / (dur * 0.35))
    x = lowpass(x, 150, 2)
    att_ramp(x, 0.004)
    fade_out(x, 0.02)
    return norm_peak(x)


# --------------------------------------------------------------------------
# FX generators / textures
# --------------------------------------------------------------------------

def swept_noise(dur: float, path_fn, bw_oct: float = 0.9,
                tag: str = "sweep") -> np.ndarray:
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
    tone_f = midi_hz(45) * 2.0 ** (2.0 * frac)
    ph = TWO_PI * np.cumsum(tone_f) / SR
    tone = sum(np.sin(ph * k + rng_for(f"{tag}.t{k}").uniform(0, TWO_PI)) / k
               for k in (1, 2, 3, 4))
    x = noise * 0.8 + tone * 0.30
    x *= frac ** 1.8
    x = np.stack([x, np.roll(x, ns(0.012))], 1)
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
    x = sat(x, 1.4)
    att_ramp(x, 0.001)
    fade_out(x, min(0.3, dur * 0.25))
    return norm_peak(x)


def pingpong_delay(x: np.ndarray, delay_s: float, fb: float = 0.42,
                   taps: int = 5, damp: float = 5500.0) -> np.ndarray:
    out = x.copy()
    d = ns(delay_s)
    wet = fft_filter(x, lambda f: _mag_lp(f, damp, 2))
    for i in range(1, taps + 1):
        g = fb ** i
        sh = np.zeros_like(x)
        sh[i * d:] = wet[: len(x) - i * d]
        if i % 2 == 1:
            sh = sh[:, ::-1]
        out += sh * g
        wet = fft_filter(wet, lambda f: _mag_lp(f, damp * 0.85, 1))
    return out


def vinyl_bed(dur: float, tag: str = "vinyl") -> np.ndarray:
    """Crackle + hiss bed (mono)."""
    n = ns(dur)
    r = rng_for(tag)
    x = np.zeros(n)
    for _ in range(int(dur * 14)):
        i = int(r.uniform(0, n - 8))
        a = float(r.uniform(0.15, 1.0)) * (1.0 if r.uniform() < 0.5 else -1.0)
        w = int(r.integers(1, 4))
        x[i:i + w] += a
    x = bandpass(x, 300, 9500, 2)
    hiss = lowpass(r.standard_normal(n), 7500, 2) * 0.10
    out = x + hiss
    att_ramp(out, 0.01)
    fade_out(out, 0.05)
    return norm_peak(out)


def water_texture(dur: float, tag: str = "water") -> np.ndarray:
    """Slowly modulated stream noise + bubble chirps + high 'drips' (stereo)."""
    n = ns(dur)
    t = t_axis(n)
    r = rng_for(tag)
    chans = []
    for _ in range(2):
        nz = r.standard_normal(n)
        stream = bandpass(nz, 450, 2700, 2)
        am = 0.6 + 0.4 * np.sin(TWO_PI * float(r.uniform(0.05, 0.12)) * t
                                + float(r.uniform(0, TWO_PI)))
        am *= 0.7 + 0.3 * np.sin(TWO_PI * float(r.uniform(0.017, 0.05)) * t
                                 + float(r.uniform(0, TWO_PI)))
        chans.append(stream * am)
    x = np.stack(chans, 1) * 0.5
    for _ in range(int(dur * 3.0)):
        t0 = float(r.uniform(0.2, dur - 0.1))
        f = float(r.uniform(700, 2600))
        bn = ns(float(r.uniform(0.015, 0.05)))
        bt = t_axis(bn)
        blip = np.sin(TWO_PI * f * (1 + 9 * bt) * bt) * exp_env(bn, 0.012)
        add(x, blip, t0, float(r.uniform(0.4, 1.0)), pan=float(r.uniform(-0.7, 0.7)))
    for _ in range(int(dur * 1.2)):
        t0 = float(r.uniform(0.3, dur - 0.1))
        f = float(r.uniform(5200, 9600))
        bn = ns(0.03)
        blip = np.sin(TWO_PI * f * t_axis(bn)) * exp_env(bn, 0.008)
        add(x, blip, t0, 0.4, pan=float(r.uniform(-0.6, 0.6)))
    att_ramp(x, 0.01)
    fade_out(x, 0.05)
    return norm_peak(x)


# --------------------------------------------------------------------------
# mastering / file IO (v1 pattern)
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


BANDS = [(20, 120), (120, 500), (500, 2000), (2000, 8000), (8000, 20000)]


def band_shares(x: np.ndarray):
    mono = x.mean(1) if x.ndim == 2 else x
    spec = np.abs(np.fft.rfft(mono)) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1 / SR)
    tot = spec[(freqs >= 20) & (freqs < 20000)].sum()
    return [100 * spec[(freqs >= lo) & (freqs < hi)].sum() / max(tot, 1e-12)
            for lo, hi in BANDS]


def analyze(x: np.ndarray, label: str) -> None:
    peak = to_db(float(np.max(np.abs(x))))
    level = to_db(rms(x))
    dc = float(np.max(np.abs(x.mean(0))))
    pct = band_shares(x)
    print(f"  {label}: peak {peak:+.2f} dBFS | rms {level:+.2f} dBFS | "
          f"DC {dc:.2e} | bands sub/low/mid/hi/air = "
          + "/".join(f"{p:.1f}%" for p in pct))


def make_meta(name: str, bpm: float, n_total: int, bars: int,
              markers: dict) -> dict:
    beat = 60.0 / bpm
    return {
        "id": name,
        "file": f"{name}.wav",
        "file_m4a": f"{name}.m4a",
        "bpm": bpm,
        "sample_rate": SR,
        "duration_sec": round(n_total / SR, 6),
        "first_beat_offset_sec": 0.0,
        "beats_sec": [round(i * beat, 6) for i in range(bars * 4)],
        "markers_sec": {k: round(v, 6) for k, v in markers.items()},
    }


# ==========================================================================
# TRACK 1: phonk_drift  (132 BPM, A minor, cowbell lead / distorted 808)
# ==========================================================================

def build_phonk_drift():
    bpm = 132.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 24
    music_end = bars * bar
    total = music_end + 2.0
    n = ns(total)

    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    cowb = np.zeros((n, 2))
    padb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    drop1, drop2, outro = range(8, 16), range(16, 20), range(20, 24)

    kick = synth_kick("phonk.kick")
    snare = synth_snare(178.0, 0.68, 0.28, "phonk.snare")
    hat_c = synth_hat(False, ".phonk")
    hat_o = synth_hat(True, ".phonk")

    # ---- drums: half-time memphis groove --------------------------------
    kick_times = []
    for b in list(build) + list(drop1) + list(drop2) + list(outro):
        lvl = 0.62 if b in build or b in outro else 0.85
        for q in (0.0, 1.75, 2.5):
            add(drums, kick, b * bar + q * beat, lvl)
            kick_times.append(b * bar + q * beat)
    for b in intro:
        add(drums, kick, b * bar, 0.45)
        kick_times.append(b * bar)
    for b in list(build) + list(drop1) + list(drop2) + list(outro):
        add(drums, snare, b * bar + 2 * beat, 0.5 if b in build else 0.78)
    for b in list(build) + list(drop1) + list(drop2):
        for q in range(8):
            add(drums, hat_c, b * bar + q * beat / 2,
                0.26 if b in build else 0.38, pan=0.25 if q % 2 else -0.25)
        if b in drop1 or b in drop2:
            for s in range(4):                            # 16th roll, bar end
                add(drums, hat_c, b * bar + 3 * beat + s * beat / 4,
                    0.20 + 0.07 * s, pan=0.3 if s % 2 else -0.3)
    for b in drop2:
        add(drums, hat_o, b * bar + 3.5 * beat, 0.30)

    # ---- distorted 808 riff ----------------------------------------------
    roots = [33, 33, 36, 31]                              # A1 A1 C2 G1
    for b in list(build) + list(drop1) + list(drop2):
        root = roots[b % 4]
        drive = 2.2 if b in build else 3.4
        g = 0.30 if b in build else 0.40
        add(bassb, synth_808(root, 1.5 * beat, drive=drive, tag="p808a"),
            b * bar, g)
        add(bassb, synth_808(root, 0.6 * beat, drive=drive, tag="p808b"),
            b * bar + 1.75 * beat, g * 0.9)
        m2 = root + (3 if b % 2 else 0)
        add(bassb, synth_808(m2, 1.2 * beat, glide_from=root, glide_t=0.14,
                             drive=drive, tag="p808c"), b * bar + 2.5 * beat, g)
    for b in outro:
        add(bassb, synth_808(33, bar * 0.9, drive=2.0, tag="p808o"), b * bar, 0.30)

    # ---- cowbell lead (memphis hook) --------------------------------------
    pat_a = [(0.0, 69), (1.0, 72), (1.5, 69), (2.5, 67), (3.0, 64), (3.5, 67)]
    pat_b = [(0.0, 69), (1.0, 72), (1.5, 74), (2.5, 72), (3.0, 69), (3.5, 67)]

    def place_cow(bars_rng, gain, octave=False):
        for i, b in enumerate(bars_rng):
            pat = pat_a if i % 2 == 0 else pat_b
            for q, m in pat:
                t0 = b * bar + q * beat
                add(cowb, synth_cowbell(m), t0, gain, pan=0.2 if q % 1 else -0.2)
                if octave:
                    add(cowb, synth_cowbell(m + 12), t0, gain * 0.35, pan=-0.25)

    place_cow(list(build), 0.34)
    place_cow(list(drop1), 0.60)
    place_cow(list(drop2), 0.60, octave=True)
    place_cow([20, 21], 0.30)
    cowb = pingpong_delay(cowb, beat * 0.75, fb=0.38, taps=4, damp=4800)

    # ---- dark pad ----------------------------------------------------------
    chords = ([45, 52, 57, 60], [41, 48, 53, 57], [48, 55, 60, 63],
              [43, 50, 55, 59])
    for i, b in enumerate(list(intro) + list(outro)):
        add(padb, synth_pad_chord(chords[i % 4], bar * 1.3, 750, 0.5,
                                  f"ppad{i}"), b * bar, 0.30)

    # ---- FX ---------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "p.riser1"), 6 * bar, 0.32)
    add(fxb, synth_riser(2 * bar, "p.riser2"), 14 * bar, 0.36)
    add(fxb, synth_sweep_down(1.4, "p.sw1"), 8 * bar, 0.18)
    add(fxb, synth_sweep_down(1.4, "p.sw2"), 16 * bar, 0.18)
    add(fxb, synth_impact(2.0, 85, 32, 38, "p.imp1"), 8 * bar, 0.7)
    add(fxb, synth_impact(2.0, 85, 32, 38, "p.imp2"), 16 * bar, 0.7)
    add(fxb, synth_impact(2.0, 80, 30, 36, "p.impend"), music_end, 0.75)

    env = pump_env(n, kick_times, depth=0.50)
    bassb *= env[:, None]
    cowb *= env[:, None]
    padb *= env[:, None]

    mix = drums + bassb + cowb + padb + fxb
    audio = master(mix, rms_target_db=-14.2, shelf=(2800.0, 6.5))
    markers = {"intro": 0.0, "build": 4 * bar, "drop": 8 * bar,
               "drop2": 16 * bar, "outro": 20 * bar, "end": music_end}
    return audio, make_meta("phonk_drift", bpm, n, bars, markers)


# ==========================================================================
# TRACK 2: house_groove  (124 BPM, F minor, piano stabs / filter sweeps)
# ==========================================================================

def build_house_groove():
    bpm = 124.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 24
    music_end = bars * bar
    total = music_end + 1.5
    n = ns(total)

    drums = np.zeros((n, 2))
    stabb = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    drop1, drop2, outro = range(8, 16), range(16, 20), range(20, 24)

    kick = synth_kick("house.kick")
    clap = synth_clap("house.clap")
    hat_c = synth_hat(False, ".house")
    hat_o = synth_hat(True, ".house")
    shaker = synth_shaker("house.shk")

    # ---- 4/4 drums ---------------------------------------------------------
    beat_grid_times = []
    for b in range(bars):
        for q in range(4):
            t0 = b * bar + q * beat
            beat_grid_times.append(t0)
            lvl = 0.5 if b in intro else (0.65 if b in build or b in outro else 0.85)
            add(drums, kick, t0, lvl)
    for b in list(drop1) + list(drop2) + list(outro):
        add(drums, clap, b * bar + 1 * beat, 0.68)
        add(drums, clap, b * bar + 3 * beat, 0.72)
    for b in list(build) + list(drop1) + list(drop2) + list(outro):
        for q in range(4):                                # offbeat open hats
            add(drums, hat_o, b * bar + q * beat + beat / 2,
                0.34 if b in build else 0.48)
    for b in list(drop1) + list(drop2):
        for s in range(16):
            add(drums, hat_c, b * bar + s * beat / 4, 0.20,
                pan=0.3 if s % 2 else -0.3)
    for b in drop2:
        for s in range(16):
            add(drums, shaker, b * bar + s * beat / 4, 0.20,
                pan=0.35 if s % 2 else -0.35)
    for end_bar, hits in ((8, 8), (16, 8)):               # clap roll into drops
        t0 = end_bar * bar - hits * beat / 4
        for i in range(hits):
            add(drums, clap, t0 + i * beat / 4, 0.2 + 0.4 * i / hits)

    # ---- piano stabs (Fm7 / Db maj9 vamp), syncopated ----------------------
    fm7 = [53, 56, 60, 63]
    dbmaj9 = [49, 53, 56, 60]
    abmaj = [56, 60, 63, 68]
    ebmaj = [51, 55, 58, 63]
    prog = [fm7, fm7, dbmaj9, ebmaj]

    def stab(midis, t0, vel, dur=0.38):
        for i, m in enumerate(midis):                     # +12: classic bright house stab
            add(stabb, synth_piano(m + 12, dur, vel), t0 + i * 0.006, 1.0,
                pan=max(-0.4, min(0.4, (m - 57) / 30.0)))

    for b in range(bars):
        ch = prog[b % 4]
        vel = 0.55 if b < 8 else (0.9 if b < 20 else 0.6)
        stab(ch, b * bar + 1.5 * beat, vel)
        stab(ch, b * bar + 2.75 * beat, vel * 0.9)
        stab(ch, b * bar + 3.5 * beat, vel * 0.8)
    # drop2 top-line melody
    mel = [(0, 0.0, 72), (0, 2.0, 75), (1, 1.5, 77), (2, 0.0, 75),
           (2, 2.5, 72), (3, 0.0, 70), (3, 2.0, 68)]
    for mb, mq, mm in mel:
        add(stabb, synth_piano(mm, 0.9, 0.6), (16 + mb) * bar + mq * beat, 1.0,
            pan=0.2)

    # ---- offbeat sub bass ---------------------------------------------------
    broots = [29, 29, 25, 27]                             # F1 F1 Db1 Eb1
    for b in list(build) + list(drop1) + list(drop2) + list(outro):
        root = broots[b % 4]
        for q in range(4):
            add(bassb, synth_sub(root, beat * 0.42), b * bar + q * beat + beat / 2,
                0.27)

    # ---- big intro/build filter sweep on the stab+bass bus ------------------
    open_t = 8 * bar

    def sweep_mag(frac, freqs):
        t = frac * total
        if t >= open_t:
            return np.ones_like(freqs)
        fc = 300.0 * (11000.0 / 300.0) ** (t / open_t)
        return _mag_lp(freqs, fc, 3)

    stabb = block_filter(stabb, sweep_mag)
    bassb = block_filter(bassb, sweep_mag)

    # ---- FX ------------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "h.riser1"), 6 * bar, 0.32)
    add(fxb, synth_riser(2 * bar, "h.riser2"), 14 * bar, 0.36)
    add(fxb, synth_sweep_down(1.5, "h.sw1"), 8 * bar, 0.2)
    add(fxb, synth_sweep_down(1.5, "h.sw2"), 16 * bar, 0.2)
    add(fxb, synth_impact(1.8, 85, 34, 40, "h.imp1"), 8 * bar, 0.6)
    add(fxb, synth_impact(2.0, 80, 30, 36, "h.impend"), music_end, 0.7)

    env = pump_env(n, beat_grid_times, depth=0.62, rel=0.30)
    stabb *= env[:, None]
    bassb *= env[:, None]

    mix = drums + stabb + bassb + fxb
    audio = master(mix, rms_target_db=-14.2, shelf=(3200.0, 7.5))
    markers = {"intro": 0.0, "build": 4 * bar, "drop": 8 * bar,
               "drop2": 16 * bar, "outro": 20 * bar, "end": music_end}
    return audio, make_meta("house_groove", bpm, n, bars, markers)


# ==========================================================================
# TRACK 3: hyperpop_rush  (150 BPM, A major, supersaw bends / glitter)
# ==========================================================================

def build_hyperpop_rush():
    bpm = 150.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 28
    music_end = bars * bar
    total = music_end + 1.4
    n = ns(total)

    drums = np.zeros((n, 2))
    leadb = np.zeros((n, 2))
    chordb = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    glitb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    drop1, brk = range(8, 16), range(16, 20)
    drop2, outro = range(20, 24), range(24, 28)

    kick = synth_kick("hp.kick", punch=1.15)
    clap = synth_clap("hp.clap")
    snare = synth_snare(205.0, 0.8, 0.22, "hp.snare")
    hat_c = synth_hat(False, ".hp")

    # ---- drums ---------------------------------------------------------------
    kick_times = []
    for b in list(drop1) + list(drop2) + list(outro):
        for q in range(4):
            t0 = b * bar + q * beat
            add(drums, kick, t0, 0.85 if b not in outro else 0.6)
            kick_times.append(t0)
    for b in list(drop1) + list(drop2) + list(outro):
        add(drums, clap, b * bar + 1 * beat, 0.65)
        add(drums, clap, b * bar + 3 * beat, 0.7)
    for b in list(build) + list(drop1) + list(drop2):
        for s in range(16):
            g = 0.16 if b in build else 0.26
            if s % 4 == 2:
                g *= 1.5
            add(drums, hat_c, b * bar + s * beat / 4, g,
                pan=0.35 if s % 2 else -0.35)
    for b in brk:
        add(drums, kick, b * bar, 0.5)
        kick_times.append(b * bar)
        add(drums, clap, b * bar + 2 * beat, 0.5)
    # accelerating snare roll into the drop (bars 6-8)
    t0, tend = 6 * bar, 8 * bar
    step = beat / 2
    while t0 < tend:
        frac = (t0 - 6 * bar) / (2 * bar)
        add(drums, snare, t0, 0.25 + 0.5 * frac)
        step = beat / 2 if frac < 0.4 else (beat / 4 if frac < 0.8 else beat / 8)
        t0 += step
    for i in range(8):                                    # roll into drop2
        add(drums, snare, 20 * bar - beat + i * beat / 8, 0.3 + 0.4 * i / 8)

    # ---- supersaw lead with pitch bends ---------------------------------------
    # phrase over 2 bars (beats, midi, bend semitones, dur beats)
    phrase = [(0.0, 76, -3.0, 1.0), (1.0, 78, 0.0, 0.5), (1.5, 81, -2.0, 1.5),
              (3.0, 83, 0.0, 1.0), (4.5, 81, -1.0, 1.0), (5.5, 78, 0.0, 0.5),
              (6.0, 76, -2.0, 1.8)]

    def place_lead(bars_rng, gain, up=0):
        for i in range(0, len(bars_rng), 2):
            base = bars_rng[i] * bar
            for q, m, bend, dq in phrase:
                add(leadb, synth_supersaw(m + up, dq * beat * 1.1, bend=bend,
                                          tag="hp.lead"), base + q * beat, gain)

    place_lead(list(intro), 0.5)
    place_lead(list(drop1), 0.7)
    place_lead(list(drop2), 0.7, up=12)
    place_lead([24, 25], 0.4)
    leadb = pingpong_delay(leadb, beat * 0.75, fb=0.35, taps=4, damp=7500)

    # ---- supersaw-ish chords (pad stack, bright) -------------------------------
    prog = ([57, 61, 64, 69], [54, 57, 61, 66], [50, 57, 62, 66],
            [52, 59, 64, 68])                             # A F#m D E
    for b in list(drop1) + list(drop2):
        add(chordb, synth_pad_chord(prog[b % 4], bar * 1.05, 5200, 0.012,
                                    f"hpch{b % 4}"), b * bar, 0.34)
    for i, b in enumerate(brk):
        add(chordb, synth_pad_chord(prog[i % 4], bar * 1.3, 2400, 0.4,
                                    f"hpbrk{i % 4}"), b * bar, 0.26)

    # ---- bass 8ths ---------------------------------------------------------------
    broots = [33, 30, 26, 28]                             # A1 F#1 D1 E1
    for b in list(drop1) + list(drop2) + list(outro):
        root = broots[b % 4]
        for e in range(8):
            add(bassb, synth_sub(root + (12 if e == 7 else 0), beat / 2 * 0.9),
                b * bar + e * beat / 2, 0.32)

    # ---- glitter blips --------------------------------------------------------
    r = rng_for("hp.glitter")
    penta = [88, 90, 93, 95, 97]
    for b in list(intro) + list(drop1) + list(brk) + list(drop2):
        for _ in range(2):
            q = float(r.uniform(0, 4))
            m = int(penta[int(r.integers(0, len(penta)))])
            bn = ns(0.08)
            blip = np.sin(TWO_PI * midi_hz(m) * t_axis(bn)) * exp_env(bn, 0.03)
            add(glitb, blip, b * bar + q * beat, 0.22,
                pan=float(r.uniform(-0.6, 0.6)))
    gn = ns(0.5)
    for b in (8, 16, 20):
        shimmer = highpass(rng_for(f"hp.shim{b}").standard_normal(gn)
                           * exp_env(gn, 0.12), 6000, 2)
        add(glitb, shimmer, b * bar, 0.15)
    glitb = pingpong_delay(glitb, beat * 0.75, fb=0.45, taps=4, damp=9000)

    # ---- FX -----------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "hp.riser1"), 6 * bar, 0.36)
    add(fxb, synth_riser(2 * bar, "hp.riser2"), 18 * bar, 0.36)
    add(fxb, synth_sweep_down(1.3, "hp.sw1"), 8 * bar, 0.2)
    add(fxb, synth_sweep_down(1.3, "hp.sw2"), 20 * bar, 0.2)
    add(fxb, synth_impact(1.8, 90, 34, 40, "hp.imp1"), 8 * bar, 0.65)
    add(fxb, synth_impact(1.8, 90, 34, 40, "hp.imp2"), 20 * bar, 0.65)
    add(fxb, synth_impact(2.0, 80, 30, 36, "hp.impend"), music_end, 0.7)

    env = pump_env(n, kick_times, depth=0.58, rel=0.26)
    chordb *= env[:, None]
    bassb *= env[:, None]
    leadb *= env[:, None]

    mix = drums + leadb + chordb + bassb + glitb + fxb
    audio = master(mix, rms_target_db=-14.0, shelf=(3500.0, 7.5))
    markers = {"intro": 0.0, "build": 4 * bar, "drop": 8 * bar,
               "break": 16 * bar, "drop2": 20 * bar, "outro": 24 * bar,
               "end": music_end}
    return audio, make_meta("hyperpop_rush", bpm, n, bars, markers)


# ==========================================================================
# TRACK 4: techno_strobe  (138 BPM, A, rumble bass / off-hats / acid line)
# ==========================================================================

def build_techno_strobe():
    bpm = 138.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 26
    music_end = bars * bar
    total = music_end + 1.6
    n = ns(total)

    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    acidb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    drop, outro = range(8, 20), range(20, 26)

    kick = synth_kick("tech.kick")
    rumble = synth_rumble("tech.rumble")
    hat_c = synth_hat(False, ".tech")
    hat_o = synth_hat(True, ".tech")
    clap = synth_clap("tech.clap")

    # ---- kick + rumble every beat ---------------------------------------------
    kick_times = []
    for b in range(bars):
        lvl = 0.55 if b in intro else (0.7 if b in build else 0.85)
        if b >= 24:
            lvl = 0.55
        for q in range(4):
            t0 = b * bar + q * beat
            add(drums, kick, t0, lvl)
            kick_times.append(t0)
            add(bassb, rumble, t0 + 0.02, 0.32)
    for b in list(build) + list(drop) + list(outro):
        for q in range(4):
            add(drums, hat_o, b * bar + q * beat + beat / 2,
                0.30 if b in build else 0.46)
    for b in drop:
        for s in range(16):
            add(drums, hat_c, b * bar + s * beat / 4, 0.16,
                pan=0.3 if s % 2 else -0.3)
        add(drums, clap, b * bar + 1 * beat, 0.38)
        add(drums, clap, b * bar + 3 * beat, 0.42)

    # ---- acid line (A1/A2, accents), cutoff automation ---------------------------
    steps = [33, None, 33, 45, None, 33, None, 45,
             33, None, 36, None, 33, 45, 31, None]
    accents = {3, 7, 10, 13}
    for b in list(build) + list(drop) + list(outro[:2]):
        for s, m in enumerate(steps):
            if m is None:
                continue
            t0 = b * bar + s * beat / 4
            if b in build:
                fc = 380.0 + (850.0 - 380.0) * (b - 4 + s / 16) / 4.0
                g = 0.34
            elif b in drop:
                prog = (b - 8 + s / 16) / 12.0
                lfo = math.sin(TWO_PI * (t0 - 8 * bar) / (4 * bar))
                fc = (900.0 + 1700.0 * prog) * 2.0 ** (0.6 * lfo)
                g = 0.50
            else:
                fc = 500.0
                g = 0.30
            acc = 1.0 if s in accents else 0.0
            note = synth_acid(m, beat / 4 * 0.95, fc, acc, tag="tech.acid")
            add(acidb, note, t0, g * (1.0 + 0.25 * acc),
                pan=0.15 if s % 2 else -0.15)
    # classic club move: highpass the 303 so kick + rumble own the lows
    acidb = highpass(acidb, 110, 2)

    # ---- dark stab every 2 bars in the drop ---------------------------------------
    stab = synth_pad_chord([57, 60, 64], 0.4, 2800, 0.005, "tech.stab")
    for b in drop:
        if b % 2 == 0:
            add(fxb, stab, b * bar + 2.5 * beat, 0.38)
    fxb = pingpong_delay(fxb, beat * 0.75, fb=0.42, taps=4, damp=4500)

    # ---- strobe-gated noise pad (16th gate) -----------------------------------------
    gate_start, gate_end = 4 * bar, 20 * bar
    gn = ns(gate_end - gate_start)
    strobe = highpass(rng_for("tech.strobe").standard_normal(gn), 3800, 2)
    gate = np.zeros(gn)
    step16 = beat / 4
    tpos = 0.0
    while tpos < gate_end - gate_start:
        i0 = ns(tpos)
        i1 = min(gn, i0 + ns(step16 * 0.45))
        if i1 > i0:
            w = np.hanning(2 * (i1 - i0))[: i1 - i0]
            gate[i0:i1] = np.maximum(gate[i0:i1], w)
        tpos += step16
    lvl = np.linspace(0.3, 1.0, gn) ** 1.5
    add(drums, strobe * gate * lvl * 0.08, gate_start, 1.0)

    # ---- FX ----------------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "t.riser1"), 6 * bar, 0.3)
    add(fxb, synth_sweep_down(1.6, "t.sw1"), 8 * bar, 0.18)
    add(fxb, synth_riser(2 * bar, "t.riser2"), 18 * bar, 0.24)
    add(fxb, synth_impact(1.8, 80, 32, 38, "t.imp1"), 8 * bar, 0.6)
    add(fxb, synth_impact(2.2, 75, 30, 36, "t.impend"), music_end, 0.7)

    env = pump_env(n, kick_times, depth=0.55, rel=0.26)
    bassb *= env[:, None]
    acidb *= env[:, None]

    mix = drums + bassb + acidb + fxb
    audio = master(mix, rms_target_db=-14.2, shelf=(2800.0, 6.5))
    markers = {"intro": 0.0, "build": 4 * bar, "drop": 8 * bar,
               "outro": 20 * bar, "end": music_end}
    return audio, make_meta("techno_strobe", bpm, n, bars, markers)


# ==========================================================================
# TRACK 5: lofi_morning  (82 BPM, C major, dusty keys / vinyl / soft drums)
# ==========================================================================

def build_lofi_morning():
    bpm = 82.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 16
    music_end = bars * bar
    total = music_end + 1.3
    n = ns(total)

    keys = np.zeros((n, 2))
    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    noise = np.zeros((n, 2))

    intro, build = range(0, 2), range(2, 4)
    drop, outro = range(4, 12), range(12, 16)

    chords = ([48, 52, 55, 59], [45, 52, 55, 60], [41, 48, 52, 57],
              [43, 50, 55, 59])                           # Cmaj7 Am7 Fmaj7 G

    def chord(midis, t0, vel, dur=2.6):
        for i, m in enumerate(midis):
            add(keys, synth_rhodes(m, dur, vel), t0 + i * 0.014, 1.0,
                pan=max(-0.4, min(0.4, (m - 52) / 30.0)))

    for b in range(bars):
        vel = 0.55 if (b in intro or b in outro) else 0.75
        chord(chords[b % 4], b * bar, vel)
        if b % 2 == 1:
            chord([chords[b % 4][0] + 12], b * bar + 2.5 * beat, vel * 0.5, 1.6)
    # melody, drop bars 8-12
    mel = [(8, 0.5, 72), (8, 2.5, 74), (9, 0.0, 76), (9, 3.0, 74),
           (10, 1.0, 72), (10, 3.0, 79), (11, 0.5, 76), (11, 2.5, 74)]
    for mb, mq, mm in mel:
        add(keys, synth_rhodes(mm, 1.4, 0.5), mb * bar + mq * beat, 1.0, pan=0.2)
    keys = lowpass(keys, 5200, 2)                         # dusty

    # ---- dusty drums (boom-bap-ish, swung hats) ---------------------------------
    kick = lowpass(synth_kick("lofi.kick"), 2200, 2)
    snare = lowpass(synth_snare(170.0, 0.6, 0.24, "lofi.snare"), 5200, 2)
    hat_c = synth_hat(False, ".lofi")
    swing = 0.14 * beat
    for b in list(build) + list(drop) + list(outro[:2]):
        g = 0.55 if b in drop else 0.4
        add(drums, kick, b * bar, g)
        add(drums, kick, b * bar + 2.75 * beat, g * 0.8)
        add(drums, snare, b * bar + 1 * beat, g * 0.85)
        add(drums, snare, b * bar + 3 * beat, g * 0.9)
        if b % 2 == 1 and b in drop:
            add(drums, snare, b * bar + 3.75 * beat, g * 0.3)   # ghost
        for q in range(8):
            t0 = b * bar + q * beat / 2 + (swing if q % 2 else 0.0)
            add(drums, hat_c, t0, 0.38 if b in drop else 0.26,
                pan=0.25 if q % 2 else -0.25)

    # ---- warm bass ----------------------------------------------------------------
    broots = [36, 33, 29, 31]
    for b in list(build) + list(drop) + list(outro):
        root = broots[b % 4]
        g = 0.24 if b in drop else 0.18
        add(bassb, synth_sub(root, beat * 1.4), b * bar, g)
        add(bassb, synth_sub(root + (7 if b % 2 else 0), beat * 1.1),
            b * bar + 2.5 * beat, g * 0.85)

    # ---- vinyl bed -----------------------------------------------------------------
    bed = vinyl_bed(total, "lofi.vinyl")
    lvl = np.ones(ns(total))
    lvl[: ns(4 * bar)] = np.linspace(1.4, 1.0, ns(4 * bar))
    lvl[ns(12 * bar):] = np.linspace(1.0, 1.5, len(lvl) - ns(12 * bar))
    add(noise, bed * lvl[: len(bed)], 0.0, 0.075)

    mix = keys * 0.85 + drums + bassb + noise
    audio = master(mix, rms_target_db=-15.6, shelf=(2600.0, 5.0))
    markers = {"intro": 0.0, "build": 2 * bar, "chorus": 4 * bar,
               "outro": 12 * bar, "end": music_end}
    return audio, make_meta("lofi_morning", bpm, n, bars, markers)


# ==========================================================================
# TRACK 6: cinematic_epic  (75 BPM halftime, C minor, strings / taiko)
# ==========================================================================

def build_cinematic_epic():
    bpm = 75.0
    beat = 60.0 / bpm                                     # 0.8 s
    bar = 4 * beat                                        # 3.2 s
    bars = 14
    music_end = bars * bar                                # 44.8 s
    total = music_end + 2.5
    n = ns(total)

    strings = np.zeros((n, 2))
    perc = np.zeros((n, 2))
    brass = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 2), range(2, 6)
    drop, outro = range(6, 11), range(11, 14)

    taiko = synth_taiko("cine.taiko")
    crash = synth_crash(1.8, "cine.crash")
    bigsnare = synth_snare(150.0, 0.55, 0.42, "cine.snare")

    # ---- string pads + low drone -----------------------------------------------
    prog = ([48, 55, 60, 63], [44, 51, 56, 60], [46, 53, 58, 62],
            [43, 50, 55, 58])                             # Cm Ab Bb G
    add(strings, synth_pad_chord([36, 43], 6 * bar, 700, 2.0, "cine.drone"),
        0.0, 0.28)
    add(strings, synth_pad_chord([36, 43], 8 * bar, 900, 1.0, "cine.drone2"),
        6 * bar, 0.33)
    for i, b in enumerate(range(0, bars, 2)):
        cutoff = 1500 if b < 6 else 2600
        g = 0.28 if b < 2 else (0.34 if b < 6 else 0.44)
        if b >= 11:
            g = 0.30
        add(strings, synth_pad_chord(prog[i % 4], bar * 2.3, cutoff, 0.8,
                                     f"cinp{i % 4}.{cutoff}"), b * bar, g)

    # ---- staccato ostinato (build + drop) -----------------------------------------
    osti = [60, 63, 67, 63]
    for b in list(build) + list(drop):
        for e in range(8):
            m = osti[e % 4] + (12 if b in drop and e % 8 >= 4 else 0)
            g = 0.24 + 0.13 * (b in drop)
            add(strings, synth_pad_chord([m], beat * 0.45, 3800, 0.012,
                                         f"cost{m}"), b * bar + e * beat / 2, g,
                pan=0.2 if e % 2 else -0.2)

    # ---- high melody line in the drop ----------------------------------------------
    mel = [(6, 0.0, 72, 2.0), (7, 0.0, 75, 2.0), (8, 0.0, 74, 1.5),
           (8, 3.0, 70, 1.0), (9, 0.0, 72, 3.5), (10, 0.0, 79, 2.0),
           (10, 2.0, 75, 2.0)]
    for mb, mq, mm, md in mel:
        add(strings, synth_pad_chord([mm], md * beat, 3000, 0.06, f"cmel{mm}"),
            mb * bar + mq * beat, 0.34, pan=0.1)

    # ---- taiko patterns: halftime, big backbeat snare on beat 3 -------------------
    for b in intro:
        add(perc, taiko, b * bar, 0.4)
    for b in build:
        add(perc, taiko, b * bar, 0.6)
        add(perc, taiko, b * bar + 2 * beat, 0.5)
        add(perc, taiko, b * bar + 3.5 * beat, 0.35)
    for b in drop:
        for q, g in ((0.0, 0.9), (1.5, 0.5), (2.5, 0.45), (3.0, 0.55)):
            add(perc, taiko, b * bar + q * beat, g)
        add(perc, taiko, b * bar + 2 * beat, 0.6)
        add(perc, bigsnare, b * bar + 2 * beat, 0.62)     # halftime backbeat
        if b % 2 == 1:
            add(perc, taiko, b * bar + 3.75 * beat, 0.5)
    # crescendo roll into the drop (bar 5-6)
    for i in range(16):
        add(perc, taiko, 5 * bar + i * beat / 4, 0.15 + 0.5 * i / 16)
    add(perc, taiko, 11 * bar, 0.8)

    # ---- brass-ish low stabs -------------------------------------------------------
    stab = synth_pad_chord([36, 43, 48, 51], 0.6, 1700, 0.015, "cine.brass")
    for b in drop:
        add(brass, sat(stab, 1.8), b * bar, 0.42)

    # ---- crashes / risers / hits ----------------------------------------------------
    add(fxb, crash, 6 * bar, 0.4)
    add(fxb, crash, 9 * bar, 0.3)
    add(fxb, crash, 11 * bar, 0.45)
    add(fxb, synth_riser(3 * bar, "cine.riser", 200, 7000), 3 * bar, 0.30)
    add(fxb, synth_riser(1.5 * bar, "cine.riser2", 300, 9000), 9.5 * bar, 0.26)
    add(fxb, synth_impact(2.2, 80, 30, 36, "cine.imp1"), 6 * bar, 0.8)
    add(fxb, synth_impact(2.4, 75, 28, 34, "cine.impend"), 11 * bar, 0.85)
    rn = ns(1.5 * bar)
    swell = highpass(rng_for("cine.swell").standard_normal(rn), 3000, 2)
    swell *= np.linspace(0.0, 1.0, rn) ** 2.2
    add(fxb, swell, 4.5 * bar, 0.10)

    mix = strings + perc + brass + fxb
    audio = master(mix, rms_target_db=-14.8, shelf=(3000.0, 5.0))
    markers = {"intro": 0.0, "build": 2 * bar, "drop": 6 * bar,
               "outro": 11 * bar, "end": music_end}
    return audio, make_meta("cinematic_epic", bpm, n, bars, markers)


# ==========================================================================
# TRACK 7: dnb_energy  (174 BPM, A minor, breakbeat / reese bass)
# ==========================================================================

def build_dnb_energy():
    bpm = 174.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 32
    music_end = bars * bar
    total = music_end + 1.5
    n = ns(total)

    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    padb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    drop1, brk = range(8, 16), range(16, 20)
    drop2, outro = range(20, 28), range(28, 32)

    kick = synth_kick_tight("dnb.kick")
    snare = synth_snare(198.0, 0.78, 0.22, "dnb.snare")
    ghost = synth_snare(185.0, 0.85, 0.12, "dnb.ghost")
    hat_c = synth_hat(False, ".dnb")
    hat_o = synth_hat(True, ".dnb")

    # ---- breakbeat: kick 1 & 3.5, snare 2 & 4, ghosts ------------------------------
    duck_times = []
    step16 = beat / 4
    for b in list(build) + list(drop1) + list(drop2) + list(outro):
        full = b in drop1 or b in drop2
        g = 0.85 if full else 0.6
        for s_k in (0, 10):
            t0 = b * bar + s_k * step16
            add(drums, kick, t0, g)
            duck_times.append(t0)
        for s_s in (4, 12):
            t0 = b * bar + s_s * step16
            add(drums, snare, t0, g * 0.9)
            duck_times.append(t0)
        if full:
            add(drums, ghost, b * bar + 7 * step16, 0.25)
            if b % 2 == 1:
                add(drums, ghost, b * bar + 15 * step16, 0.22)
        for s in range(16):
            gh = 0.13 if not full else 0.20
            if s % 4 == 2:
                gh *= 1.4
            add(drums, hat_c, b * bar + s * step16, gh,
                pan=0.3 if s % 2 else -0.3)
    for b in drop2:
        add(drums, hat_o, b * bar + 2 * beat + beat / 2, 0.25)
    for b in intro:
        for s in range(16):
            add(drums, hat_c, b * bar + s * step16, 0.10,
                pan=0.3 if s % 2 else -0.3)
    # snare roll build (bars 6-8)
    t0 = 6 * bar
    while t0 < 8 * bar:
        frac = (t0 - 6 * bar) / (2 * bar)
        add(drums, snare, t0, 0.2 + 0.55 * frac)
        t0 += beat / 2 if frac < 0.4 else (beat / 4 if frac < 0.8 else beat / 8)
    for i in range(8):
        add(drums, snare, 20 * bar - beat + i * beat / 8, 0.3 + 0.4 * i / 8)

    # ---- reese bass riff --------------------------------------------------------
    roots = [33, 33, 29, 31]
    for b in list(drop1) + list(drop2):
        root = roots[b % 4]
        add(bassb, synth_reese(root, beat * 1.9, "dnb.reese"), b * bar, 0.4)
        m2 = root + (7 if b % 2 else 0)
        add(bassb, synth_reese(m2, beat * 1.9, "dnb.reese"), b * bar + 2 * beat, 0.4)
    for b in build:
        add(bassb, synth_reese(33, bar * 0.95, "dnb.reese"), b * bar, 0.22)

    # wobble movement on the reese in drop2
    d2_start, d2_end = 20 * bar, 28 * bar

    def reese_mag(frac, freqs):
        t = frac * total
        if d2_start <= t < d2_end:
            lfo = math.sin(TWO_PI * (t - d2_start) / bar * 1.0)
            fc = 750.0 * 2.0 ** (0.85 * lfo)
            return _mag_lp(freqs, fc, 2)
        return np.ones_like(freqs)

    bassb = block_filter(bassb, reese_mag)

    # ---- pads / break piano ---------------------------------------------------------
    for i, b in enumerate(range(0, 4, 2)):
        add(padb, synth_pad_chord([45, 52, 60, 64], bar * 2.3, 1100, 1.0,
                                  f"dnbp{i}"), b * bar, 0.30)
    for i, b in enumerate(range(16, 20, 2)):
        add(padb, synth_pad_chord([41, 48, 57, 60], bar * 2.3, 1300, 0.8,
                                  f"dnbb{i}"), b * bar, 0.34)
    for mb, mq, mm in ((16, 0.0, 76), (17, 2.0, 74), (18, 0.0, 72), (19, 2.0, 69)):
        add(padb, synth_piano(mm, 1.4, 0.5), mb * bar + mq * beat, 1.0, pan=0.15)
    padb = pingpong_delay(padb, beat * 1.5, fb=0.35, taps=3, damp=6000)

    # ---- FX ----------------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "d.riser1"), 6 * bar, 0.34)
    add(fxb, synth_riser(2 * bar, "d.riser2"), 18 * bar, 0.34)
    add(fxb, synth_sweep_down(1.3, "d.sw1"), 8 * bar, 0.18)
    add(fxb, synth_sweep_down(1.3, "d.sw2"), 20 * bar, 0.18)
    add(fxb, synth_impact(1.6, 90, 34, 40, "d.imp1"), 8 * bar, 0.6)
    add(fxb, synth_impact(1.6, 90, 34, 40, "d.imp2"), 20 * bar, 0.6)
    add(fxb, synth_impact(2.0, 80, 30, 36, "d.impend"), music_end, 0.7)

    env = pump_env(n, duck_times, depth=0.30, rel=0.12)
    bassb *= env[:, None]
    padb *= env[:, None]

    mix = drums + bassb + padb + fxb
    audio = master(mix, rms_target_db=-14.0, shelf=(3200.0, 6.5))
    markers = {"intro": 0.0, "build": 4 * bar, "drop": 8 * bar,
               "break": 16 * bar, "drop2": 20 * bar, "outro": 28 * bar,
               "end": music_end}
    return audio, make_meta("dnb_energy", bpm, n, bars, markers)


# ==========================================================================
# TRACK 8: trap_bounce  (140 BPM, D minor, hat rolls / 808 slides / snap)
# ==========================================================================

def build_trap_bounce():
    bpm = 140.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 26
    music_end = bars * bar
    total = music_end + 1.6
    n = ns(total)

    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    bellb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    drop1, drop2, outro = range(8, 16), range(16, 22), range(22, 26)

    kick = synth_kick("trap.kick")
    snare = synth_snare(182.0, 0.7, 0.3, "trap.snare")
    snap = synth_snap("trap.snap")
    hat_c = synth_hat(False, ".trap")
    hat_o = synth_hat(True, ".trap")

    # ---- half-time drums with rolls ----------------------------------------------
    duck_times = []
    for b in list(build) + list(drop1) + list(drop2) + list(outro):
        full = b in drop1 or b in drop2
        g = 0.85 if full else 0.55
        for q in (0.0, 1.75, 2.75):
            add(drums, kick, b * bar + q * beat, g * (0.9 if q else 1.0))
            duck_times.append(b * bar + q * beat)
        add(drums, snare, b * bar + 2 * beat, g * 0.85)
        add(drums, snap, b * bar + 2 * beat, g * 0.7, pan=0.15)
        duck_times.append(b * bar + 2 * beat)
    for b in intro:
        add(drums, snap, b * bar + 2 * beat, 0.4, pan=0.15)
    # hats: 8ths + rolls
    for b in list(build) + list(drop1) + list(drop2):
        g = 0.22 if b in build else 0.32
        for q in range(6):                                # 8ths, beats 0-3
            add(drums, hat_c, b * bar + q * beat / 2, g,
                pan=0.25 if q % 2 else -0.25)
        for s in range(4):                                # 16th roll on beat 3
            add(drums, hat_c, b * bar + 3 * beat + s * beat / 4, g * 0.9)
        if b % 2 == 1:                                    # 32nd roll, bar end
            for s in range(8):
                add(drums, hat_c, b * bar + 3.5 * beat + s * beat / 8,
                    g * (0.5 + 0.5 * s / 8))
        if b in drop2 and b % 4 == 1:                     # triplet burst
            for s in range(6):
                add(drums, hat_c, b * bar + 1 * beat + s * beat / 6, g * 1.1,
                    pan=0.35 if s % 2 else -0.35)
    for b in drop2:
        add(drums, hat_o, b * bar + 0.5 * beat, 0.26)

    # ---- 808 with slides -------------------------------------------------------
    riff = [(0.0, 26, None, 1.6), (2.75, 29, 26, 0.8), (3.5, 24, 29, 1.4)]
    for b in list(build) + list(drop1) + list(drop2):
        g = 0.30 if b in build else 0.42
        drive = 2.0 if b in build else 2.8
        for q, m, gl, dq in riff:
            mm = m + (2 if b % 4 == 3 else 0)
            add(bassb, synth_808(mm, dq * beat, glide_from=gl, glide_t=0.30,
                                 drive=drive, tag="trap808"), b * bar + q * beat, g)
    for b in outro:
        add(bassb, synth_808(26, bar * 0.9, drive=1.8, tag="trap808o"),
            b * bar, 0.3)

    # ---- dark bell motif ----------------------------------------------------------
    mot = [(0.0, 62, 1.0), (1.0, 65, 0.8), (1.75, 69, 0.9), (2.5, 67, 0.8),
           (3.25, 65, 0.7)]
    for b in range(0, bars - 2, 2):
        g = 0.30 if b < 8 or b >= 22 else 0.45
        up = 12 if 16 <= b < 22 else 0
        for q, m, gg in mot:
            add(bellb, synth_bell(m + up, 1.0, tag="trap.bell"),
                b * bar + q * beat, g * gg, pan=0.2 if q % 1 else -0.2)
    bellb = pingpong_delay(bellb, beat * 0.75, fb=0.4, taps=4, damp=5000)

    # ---- FX ------------------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "tr.riser1"), 6 * bar, 0.32)
    add(fxb, synth_riser(2 * bar, "tr.riser2"), 14 * bar, 0.34)
    add(fxb, synth_sweep_down(1.4, "tr.sw1"), 8 * bar, 0.18)
    add(fxb, synth_impact(1.8, 85, 32, 38, "tr.imp1"), 8 * bar, 0.65)
    add(fxb, synth_impact(1.8, 85, 32, 38, "tr.imp2"), 16 * bar, 0.65)
    add(fxb, synth_impact(2.0, 80, 30, 36, "tr.impend"), music_end, 0.72)

    env = pump_env(n, duck_times, depth=0.40, rel=0.20)
    bellb *= env[:, None]
    bassb *= env[:, None]

    mix = drums + bassb + bellb + fxb
    audio = master(mix, rms_target_db=-14.3, shelf=(3000.0, 7.0))
    markers = {"intro": 0.0, "build": 4 * bar, "drop": 8 * bar,
               "drop2": 16 * bar, "outro": 22 * bar, "end": music_end}
    return audio, make_meta("trap_bounce", bpm, n, bars, markers)


# ==========================================================================
# TRACK 9: indie_pop_sun  (112 BPM, C major, guitar-pluck synth / claps)
# ==========================================================================

def build_indie_pop_sun():
    bpm = 112.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 20
    music_end = bars * bar
    total = music_end + 1.6
    n = ns(total)

    gtr = np.zeros((n, 2))
    drums = np.zeros((n, 2))
    bassb = np.zeros((n, 2))
    leadb = np.zeros((n, 2))
    fxb = np.zeros((n, 2))

    intro, build = range(0, 4), range(4, 8)
    chorus, outro = range(8, 16), range(16, 20)

    kick = synth_kick("indie.kick")
    clap = synth_clap("indie.clap")
    shaker = synth_shaker("indie.shk")

    chords = ([48, 52, 55, 60], [43, 47, 50, 55], [45, 48, 52, 57],
              [41, 45, 48, 53])                           # C G Am F
    arp_order = [0, 2, 1, 3, 2, 0, 3, 1]

    # ---- guitar arps + strums --------------------------------------------------
    for b in range(bars):
        ch = chords[b % 4]
        g = 0.4 if b in intro or b in outro else 0.5
        for e in range(8):
            m = ch[arp_order[e]] + 12
            add(gtr, synth_guitar(m, 0.55, 0.9945, "arp"), b * bar + e * beat / 2,
                g, pan=0.25 if e % 2 else -0.25)
        if b in chorus:                                   # strums on 0 & 2.5
            for si, q in enumerate((0.0, 2.5)):
                for i, m in enumerate(ch + [ch[0] + 24]):
                    add(gtr, synth_guitar(m + 12, 0.9, 0.996, "strum"),
                        b * bar + q * beat + i * 0.012, 0.30,
                        pan=-0.3 + 0.15 * i)

    # ---- friendly lead + glockenspiel ------------------------------------------
    mel = [(0, 0.0, 72, 0.6), (0, 1.5, 74, 0.5), (0, 2.5, 76, 0.9),
           (1, 0.0, 79, 0.9), (1, 2.0, 76, 0.7), (2, 0.0, 74, 0.8),
           (2, 2.5, 72, 0.6), (3, 0.0, 69, 1.2), (3, 2.5, 71, 0.6)]
    for rep in range(2):
        base = 8 + rep * 4
        for mb, mq, mm, md in mel:
            t0 = (base + mb) * bar + mq * beat
            add(leadb, synth_pluck(mm, md, 0.9), t0, 0.55)
            add(leadb, synth_bell(mm + 12, 0.5, 0.5, "glock"), t0, 0.16, pan=0.3)
    leadb = pingpong_delay(leadb, beat * 0.75, fb=0.32, taps=3, damp=7000)

    # ---- drums ----------------------------------------------------------------
    duck_times = []
    for b in list(build) + list(chorus) + list(outro[:2]):
        full = b in chorus
        for q in range(4):
            if full or q in (0, 2):
                t0 = b * bar + q * beat
                add(drums, kick, t0, 0.6 if full else 0.45)
                duck_times.append(t0)
        add(drums, clap, b * bar + 1 * beat, 0.55 if full else 0.4)
        add(drums, clap, b * bar + 3 * beat, 0.6 if full else 0.45)
    for b in range(bars):
        for q in range(8):
            add(drums, shaker, b * bar + q * beat / 2,
                0.15 if b in chorus else 0.10, pan=0.3 if q % 2 else -0.3)
    for end_bar in (8, 16):                               # clap fills
        for i in range(4):
            add(drums, clap, end_bar * bar - beat + i * beat / 4,
                0.25 + 0.3 * i / 4)

    # ---- bass -------------------------------------------------------------------
    broots = [36, 31, 33, 29]
    for b in list(build) + list(chorus) + list(outro):
        root = broots[b % 4]
        g = 0.20 if b in chorus else 0.14
        add(bassb, synth_sub(root, beat * 1.4), b * bar, g)
        add(bassb, synth_sub(root, beat * 1.2), b * bar + 2.5 * beat, g * 0.9)
        if b in chorus:
            add(bassb, synth_sub(root + 7, beat * 0.5), b * bar + 3.5 * beat,
                g * 0.7)

    # ---- FX ----------------------------------------------------------------------
    add(fxb, synth_riser(2 * bar, "i.riser1"), 6 * bar, 0.24)
    add(fxb, synth_sweep_down(1.3, "i.sw1"), 8 * bar, 0.14)
    add(fxb, synth_impact(1.5, 90, 36, 42, "i.imp1"), 8 * bar, 0.45)
    add(fxb, synth_impact(1.8, 85, 32, 38, "i.impend"), music_end, 0.5)

    env = pump_env(n, duck_times, depth=0.22, rel=0.25)
    gtr *= env[:, None]
    bassb *= env[:, None]

    mix = gtr + drums + bassb + leadb + fxb
    audio = master(mix, rms_target_db=-14.8, shelf=(3500.0, 6.0))
    markers = {"intro": 0.0, "build": 4 * bar, "chorus": 8 * bar,
               "outro": 16 * bar, "end": music_end}
    return audio, make_meta("indie_pop_sun", bpm, n, bars, markers)


# ==========================================================================
# TRACK 10: ambient_air  (70 BPM, C major, pads / heartbeat / water)
# ==========================================================================

def build_ambient_air():
    bpm = 70.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 14
    music_end = bars * bar
    total = music_end + 1.9
    n = ns(total)

    padb = np.zeros((n, 2))
    pulse = np.zeros((n, 2))
    texb = np.zeros((n, 2))
    bellb = np.zeros((n, 2))

    # sections: intro 0-3, build 3-6, drop 6-11, outro 11-14
    chords = ([48, 55, 62, 64], [45, 52, 59, 62], [41, 48, 57, 60],
              [43, 50, 59, 62])                           # Cmaj9 Am9 Fmaj9 G9

    for i, b in enumerate(range(0, bars, 2)):
        ch = chords[i % 4]
        in_drop = 6 <= b < 11
        cutoff = 1500 if in_drop else 1050
        g = 0.42 if in_drop else 0.30
        add(padb, synth_pad_chord(ch, bar * 2.4, cutoff, 2.2,
                                  f"amb{i % 4}.{cutoff}"), b * bar, g)
        if in_drop:
            add(padb, synth_pad_chord([m + 12 for m in ch[1:]], bar * 2.4,
                                      2000, 2.6, f"ambhi{i % 4}"), b * bar, 0.16)

    # ---- heartbeat pulse (70 bpm = calm resting heart rate) ---------------------
    lub = heart_thump(58.0, 0.16, "amb.lub")
    dub = heart_thump(66.0, 0.12, "amb.dub")
    for b in range(3, bars):
        g = 0.30 if b < 6 else (0.45 if b < 11 else 0.25)
        for q in range(4):
            t0 = b * bar + q * beat
            add(pulse, lub, t0, g)
            add(pulse, dub, t0 + 0.30, g * 0.7)

    # ---- sub swell in the drop -----------------------------------------------------
    sw_n = ns(5 * bar)
    sw_t = t_axis(sw_n)
    swell = np.sin(TWO_PI * midi_hz(24) * sw_t)
    swell *= np.sin(np.pi * np.minimum(1.0, sw_t / (5 * bar))) ** 1.5
    add(pulse, swell, 6 * bar, 0.16)

    # ---- water textures --------------------------------------------------------
    add(texb, water_texture(total - 0.3, "amb.water"), 0.0, 0.16)

    # ---- soft bell melody (drop) ---------------------------------------------------
    mel = [(6, 0.0, 76), (7, 1.0, 74), (8, 0.0, 72), (9, 2.0, 67), (10, 0.0, 74)]
    for mb, mq, mm in mel:
        add(bellb, synth_bell(mm, 1.8, 1.6, "amb.bell"), mb * bar + mq * beat,
            0.22, pan=0.15)
    add(bellb, synth_bell(72, 2.2, 1.8, "amb.bell.end"), 11 * bar, 0.18)
    bellb = pingpong_delay(bellb, beat * 1.25, fb=0.45, taps=4, damp=6500)

    mix = padb + pulse + texb + bellb
    audio = master(mix, rms_target_db=-16.0, shelf=(2200.0, 4.0))
    markers = {"intro": 0.0, "build": 3 * bar, "drop": 6 * bar,
               "outro": 11 * bar, "end": music_end}
    return audio, make_meta("ambient_air", bpm, n, bars, markers)


TRACKS = {
    "phonk_drift": build_phonk_drift,
    "house_groove": build_house_groove,
    "hyperpop_rush": build_hyperpop_rush,
    "techno_strobe": build_techno_strobe,
    "lofi_morning": build_lofi_morning,
    "cinematic_epic": build_cinematic_epic,
    "dnb_energy": build_dnb_energy,
    "trap_bounce": build_trap_bounce,
    "indie_pop_sun": build_indie_pop_sun,
    "ambient_air": build_ambient_air,
}


# ==========================================================================
# generation / verify
# ==========================================================================

def output_files() -> list:
    files = []
    for name in TRACKS:
        files += [f"{name}.wav", f"{name}.m4a"]
    files += [TRACKS_JSON, GRID_COMPAT]
    return files


def generate(only: str | None = None) -> None:
    todo = [only] if only else list(TRACKS)
    grid_tracks = {}
    for i, name in enumerate(todo, 1):
        print(f"[{i}/{len(todo)}] rendering {name} ...")
        audio, meta = TRACKS[name]()
        analyze(audio, name)
        write_wav(os.path.join(HERE, meta["file"]), audio)
        encode_m4a(os.path.join(HERE, meta["file"]),
                   os.path.join(HERE, meta["file_m4a"]))
        grid_tracks[name] = meta
    if only:
        print("(--only: tracks_v2.json / beat_grid_v2.json not rewritten)")
        return

    doc = {
        "version": 2,
        "seed": SEED,
        "sample_rate": SR,
        "generator": "generate_v2.py",
        "tracks": grid_tracks,
    }
    payload = json.dumps(doc, indent=2, sort_keys=True) + "\n"
    # tracks_v2.json is the deliverable; beat_grid_v2.json is a byte-identical
    # copy under the name the remotion sync script looks for.
    for rel in (TRACKS_JSON, GRID_COMPAT):
        with open(os.path.join(HERE, rel), "w") as f:
            f.write(payload)
    print("done.")
    checksums()


def checksums() -> None:
    for name in output_files():
        p = os.path.join(HERE, name)
        print(f"  {sha256(p)}  {name}")


class Verifier:
    def __init__(self):
        self.fails = 0

    def check(self, ok: bool, msg: str) -> None:
        print(f"  [{'PASS' if ok else 'FAIL'}] {msg}")
        if not ok:
            self.fails += 1


def ffprobe_info(path: str) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "format=format_name,duration:stream=codec_name,sample_rate,channels",
         "-of", "json", path],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


# main musical section marker per track ("drop" unless it is a chorus genre)
MAIN_MARKER = {"lofi_morning": "chorus", "indie_pop_sun": "chorus"}


def verify() -> int:
    v = Verifier()
    grid_path = os.path.join(HERE, TRACKS_JSON)
    if not os.path.isfile(grid_path):
        print(f"  [FAIL] {TRACKS_JSON} missing")
        return 1
    with open(grid_path) as f:
        grid = json.load(f)
    v.check(grid["sample_rate"] == SR, f"tracks_v2.json sample_rate == {SR}")
    v.check(set(grid["tracks"]) == set(TRACKS),
            "tracks_v2.json covers exactly the 10 tracks")
    compat = os.path.join(HERE, GRID_COMPAT)
    v.check(os.path.isfile(compat) and sha256(compat) == sha256(grid_path),
            f"{GRID_COMPAT} is a byte-identical copy (remotion compat)")

    track_rms = {}
    for name in TRACKS:
        meta = grid["tracks"].get(name)
        print(f"-- {name}")
        wav_path = os.path.join(HERE, f"{name}.wav")
        if meta is None or not os.path.isfile(wav_path):
            v.check(False, f"{name}: wav + tracks_v2.json entry present")
            continue
        v.check(meta.get("id") == name, "json id matches track key")
        x, sr = read_wav(wav_path)
        dur = len(x) / sr
        v.check(sr == SR, f"wav sample rate {sr}")
        v.check(bool(np.all(np.isfinite(x))), "all samples finite")
        peak = to_db(float(np.max(np.abs(x))))
        v.check(-1.7 <= peak <= -1.3, f"peak {peak:+.2f} dBFS in [-1.7, -1.3]")
        v.check(float(np.max(np.abs(x))) < 1.0, "no clipping (peak < 0 dBFS)")
        dc = float(np.max(np.abs(x.mean(0))))
        v.check(dc < 1e-3, f"DC offset {dc:.2e} < 1e-3")
        v.check(30.0 <= dur <= 60.0, f"duration {dur:.3f}s in [30, 60]")
        v.check(abs(dur - meta["duration_sec"]) < 1e-4,
                "duration matches tracks_v2.json")
        level = to_db(rms(x))
        track_rms[name] = level
        v.check(-19.0 <= level <= -11.0,
                f"overall RMS {level:+.2f} dBFS in [-19, -11]")
        w = ns(0.4)
        nwin = len(x) // w
        wr = np.sqrt(np.square(x[: nwin * w]).reshape(nwin, -1).mean(1))
        v.check(to_db(float(wr.max())) <= -6.0,
                f"max 400ms-window RMS {to_db(float(wr.max())):+.2f} <= -6 dBFS")
        marks = meta["markers_sec"]
        main = MAIN_MARKER.get(name, "drop")
        required = ("intro", "build", main, "outro", "end")
        v.check(all(k in marks for k in required),
                f"markers include {'/'.join(required)}")
        seq = [marks[k] for k in required if k in marks]
        v.check(all(a < b for a, b in zip(seq, seq[1:])),
                "marker order intro < build < " + main + " < outro < end")
        v.check(all(0.0 <= mt <= dur for mt in marks.values()),
                "all markers inside file duration")
        e_main = rms(x[ns(marks[main] + 0.5):ns(marks[main] + 3.0)])
        e_intro = rms(x[ns(0.5):ns(3.0)])
        v.check(e_main > e_intro,
                f"{main} louder than intro ({to_db(e_main):+.1f} vs "
                f"{to_db(e_intro):+.1f} dBFS)")
        beats = meta["beats_sec"]
        step = 60.0 / meta["bpm"]
        diffs = np.diff(beats)
        v.check(bool(np.all(np.abs(diffs - step) < 1e-5)),
                f"beat spacing == {step:.6f}s ({len(beats)} beats)")
        v.check(abs(beats[0] - meta["first_beat_offset_sec"]) < 1e-9,
                "first beat == first_beat_offset_sec")
        v.check(beats[-1] < dur, "beats inside file duration")
        v.check(float(np.abs(x[0]).max()) < 1e-3 and
                float(np.abs(x[:ns(0.0005)]).max()) < 0.1,
                "clean start (ramps from zero, no click)")
        v.check(float(np.abs(x[-ns(0.01):]).max()) < 0.01, "clean end (fade to 0)")
        lp = lowpass(x, 100, 4)
        denom = float(np.sqrt(np.mean(lp[:, 0] ** 2) * np.mean(lp[:, 1] ** 2)))
        corr = float(np.mean(lp[:, 0] * lp[:, 1])) / max(denom, 1e-12)
        v.check(corr > 0.97, f"bass mono: <100 Hz L/R correlation {corr:.4f} > 0.97")
        shares = band_shares(x)
        v.check(all(s > 0.05 for s in shares) and max(shares) < 95.0,
                "spectral balance: sub/low/mid/hi/air = "
                + "/".join(f"{s:.1f}%" for s in shares))
        # m4a: container / codec / duration
        m4a_path = os.path.join(HERE, meta["file_m4a"])
        if not os.path.isfile(m4a_path):
            v.check(False, f"{meta['file_m4a']} exists")
        else:
            info = ffprobe_info(m4a_path)
            fmt = info.get("format", {})
            streams = info.get("streams", [])
            st = streams[0] if streams else {}
            v.check("mp4" in fmt.get("format_name", ""),
                    f"m4a container is mp4 ({fmt.get('format_name')})")
            v.check(st.get("codec_name") == "aac"
                    and st.get("sample_rate") == str(SR)
                    and st.get("channels") == 2,
                    f"m4a codec aac / {SR} Hz / stereo")
            mdur = float(fmt.get("duration", 0.0))
            v.check(abs(mdur - dur) < 0.2,
                    f"m4a duration {mdur:.3f}s matches wav ({dur:.3f}s)")

    print("-- loudness match")
    if track_rms:
        spread = max(track_rms.values()) - min(track_rms.values())
        v.check(spread <= 3.0,
                f"track RMS spread {spread:.2f} dB <= 3 dB "
                f"(min {min(track_rms.values()):+.1f}, "
                f"max {max(track_rms.values()):+.1f})")

    print(f"\n{'ALL CHECKS PASSED' if v.fails == 0 else str(v.fails) + ' CHECK(S) FAILED'}")
    return 1 if v.fails else 0


# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verify", action="store_true", help="run QC checks only")
    ap.add_argument("--checksums", action="store_true", help="print sha256 only")
    ap.add_argument("--only", metavar="TRACK", default=None,
                    help="dev aid: render a single track")
    args = ap.parse_args()
    if args.verify:
        return verify()
    if args.checksums:
        checksums()
        return 0
    if args.only and args.only not in TRACKS:
        print(f"unknown track {args.only!r}; choose from: {', '.join(TRACKS)}")
        return 2
    generate(args.only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
