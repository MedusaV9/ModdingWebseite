#!/usr/bin/env python3
"""Deterministic synthesis of every Gooby sound (numpy -> wav -> ffmpeg -> ogg).

Audio-Polish-Wave: every emotionally frequent event family ships >= 3 clearly
distinct variants. Variants differ in envelope, harmonic content and timing --
never in pitch alone. All clips are peak-normalised per family, verified for
clipping, RMS consistency and container health after encoding.

Usage:
    python3 scripts/gen_sounds.py            # synthesise everything + verify
    python3 scripts/gen_sounds.py --verify   # verify existing files only
    python3 scripts/gen_sounds.py --prune    # also delete unmanaged .ogg files
    python3 scripts/gen_sounds.py --metrics out.json   # dump metrics as JSON
    python3 scripts/gen_sounds.py --update-manifest    # regen + bless manifest
    python3 scripts/gen_sounds.py --verify --update-manifest  # bless as-is

Determinism: fixed RNG seeds per clip and ffmpeg bitexact flags make the
generated .ogg files byte-for-byte reproducible (same ffmpeg/libvorbis build).
The committed manifest docs/audio_manifest.json pins the expected SHA-256 of
every clip; verify() compares against it fail-closed, so accidental
re-encodes with a drifted toolchain surface as hard errors. Only
--update-manifest (an explicit, reviewable step) may rewrite the manifest.

Deliberate single-variant sounds (do NOT add variants):
  * purr_loop            -- mathematically periodic, must loop seamlessly
  * whistle_wander/follow/stay -- players learn the three modes by ear
  * snuggle_purr_long    -- long signature bond sound, one canonical take
Locked pool size: alarm_squeak stays at exactly 2 variants
(GoobyGameTests.awareness_assets_complete asserts size == 2).
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
ASSETS = os.path.join(ROOT, "src", "main", "resources", "assets", "goobymod")
OUT = os.path.join(ASSETS, "sounds", "entity", "gooby")
SOUNDS_JSON = os.path.join(ASSETS, "sounds.json")
MANIFEST = os.path.join(ROOT, "docs", "audio_manifest.json")
SOUND_PREFIX = "goobymod:entity/gooby/"

# Verification bounds (post-encode, decoded samples).
PEAK_MIN, PEAK_MAX = 0.10, 0.92          # kein Clipping, aber hoerbar
RMS_MIN, RMS_MAX = 0.010, 0.36
DURATION_MIN, DURATION_MAX = 0.14, 5.0   # Sekunden
SIZE_MIN, SIZE_MAX = 2_000, 150_000      # Bytes
FAMILY_RMS_SPREAD = 2.6                  # max aktive-RMS-Streuung pro Familie

# Jitter-Bounds fuer Multi-Varianten-Pools in sounds.json.
# ACHTUNG: Diese Pool-Bounds spiegeln GoobyAudioExpansionTests
# (POOL_PITCH_MIN/MAX, POOL_VOLUME_MIN/MAX) und docs/AUDIO.md --
# immer alle drei Stellen zusammen aendern, sonst driften die Gates.
POOL_PITCH_MIN, POOL_PITCH_MAX = 0.94, 1.06
POOL_VOLUME_MIN, POOL_VOLUME_MAX = 0.90, 1.0
# Lose Global-Bounds fuer Sonderfaelle (z. B. whistle_denied bei Pitch 0.65).
GLOBAL_PITCH_MIN, GLOBAL_PITCH_MAX = 0.6, 1.1
JITTER_EXEMPT_EVENTS = frozenset(
    {"entity.gooby.alarm_squeak", "entity.gooby.whistle_denied"})

# Families that must offer >= 3 variants (emotionally frequent events).
FREQUENT_FAMILIES = (
    "squeak", "purr", "boing", "plop", "munch", "snore", "sniff",
    "sad_whimper", "yawn", "ambient_neutral", "ambient_happy",
    "ambient_sleepy", "brush", "whine_hungry", "lonely_sigh", "shake",
    "tier_up_jingle", "trick_chime", "flop_thud", "hutch_rustle",
    "hutch_creak", "baby_squeak", "nuzzle", "dress_up", "wild_call",
    "chirp_social", "sniff_long", "map_rustle",
)
SINGLE_FAMILIES = ("purr_loop", "whistle_wander", "whistle_follow",
                   "whistle_stay", "snuggle_purr_long")
LOCKED_FAMILIES = {"alarm_squeak": 2}


# ---------------------------------------------------------------------------
# DSP-Primitive
# ---------------------------------------------------------------------------

def env(n, attack=0.02, release=0.3, shape=1.0):
    """Huellkurve: weicher Attack, weiches Release, optional gekruemmt."""
    e = np.ones(n)
    a = int(SR * attack)
    r = int(SR * release)
    if a > 0:
        e[:a] = np.linspace(0, 1, a) ** shape
    if 0 < r < n:
        e[-r:] = np.linspace(1, 0, r) ** shape
    return e


def tone(freqs, dur, vibrato_hz=0.0, vibrato_amt=0.0):
    """Sinuston mit Frequenzverlauf (freqs = Liste von Stuetzpunkten)."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(freqs)), freqs)
    if vibrato_hz > 0:
        f = f * (1 + vibrato_amt * np.sin(2 * np.pi * vibrato_hz * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase)


def bell(freq, dur, partials, decay):
    """Glockenton: Partialstapel ((ratio, amp), ...) mit Exponential-Decay."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for ratio, amp in partials:
        sig += amp * np.sin(2 * np.pi * freq * ratio * t)
    return sig * np.exp(-t / decay)


def smooth_noise(rng, n, kernel, sigma=1.0):
    """Tiefpass-gefiltertes Gauss-Rauschen (gleitender Mittelwert)."""
    raw = rng.normal(0.0, sigma, n)
    return np.convolve(raw, np.ones(kernel) / kernel, mode="same")


def silence(dur):
    return np.zeros(int(SR * dur))


def place(base, addition, offset):
    """Addiert `addition` ab Sekunde `offset` in `base` (verlaengert bei Bedarf)."""
    start = int(SR * offset)
    end = start + len(addition)
    if end > len(base):
        base = np.concatenate([base, np.zeros(end - len(base))])
    base[start:end] += addition
    return base


# ---------------------------------------------------------------------------
# Render-Registry
# ---------------------------------------------------------------------------

CLIPS = {}


def clip(name, peak):
    def wrap(fn):
        CLIPS[name] = (fn, peak)
        return fn
    return wrap


# --- Squeaks: zwei aufsteigende Freude-Quietscher (Timing je Variante) -----

def _squeak(base, variant):
    first = tone([base, base * 1.62], 0.14, 28, 0.022)
    second = tone([base * 1.08, base * 1.82], 0.17, 31, 0.025)
    return np.concatenate([
        first * env(len(first), 0.008, 0.055),
        silence(0.035 + variant * 0.008),
        second * env(len(second), 0.008, 0.075),
    ])


clip("squeak1", 0.42)(lambda: _squeak(820, 1))
clip("squeak2", 0.42)(lambda: _squeak(900, 2))
clip("squeak3", 0.42)(lambda: _squeak(760, 3))


# --- Purr: amplitudenmodulierter Grundton + Oktave ---------------------------

def _purr(base, variant):
    dur = 1.25 + variant * 0.08
    n = int(SR * dur)
    t = np.arange(n) / SR
    sig = (0.72 * np.sin(2 * np.pi * base * t)
           + 0.22 * np.sin(2 * np.pi * base * 2 * t))
    sig *= 0.58 + 0.42 * np.sin(2 * np.pi * (21 + variant) * t)
    return sig * env(n, 0.12, 0.28)


clip("purr1", 0.34)(lambda: _purr(102, 1))
clip("purr2", 0.34)(lambda: _purr(111, 2))
clip("purr3", 0.34)(lambda: _purr(119, 3))


@clip("purr_loop", 0.30)
def _purr_loop():
    # Mathematisch periodisch (110/220/22 Hz teilen 2.0 s) -> nahtloser Loop.
    n = int(SR * 2.0)
    t = np.arange(n) / SR
    loop = 0.74 * np.sin(2 * np.pi * 110 * t) + 0.20 * np.sin(2 * np.pi * 220 * t)
    return loop * (0.62 + 0.38 * np.sin(2 * np.pi * 22 * t))


# --- Boing: federnder Abpraller ---------------------------------------------

def _boing(start, variant):
    dur = 0.52 + variant * 0.04
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = start * np.exp(-4.4 * t) + 68
    phase = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(phase) + 0.27 * np.sin(2 * phase)) * env(n, 0.004, 0.27)


clip("boing1", 0.50)(lambda: _boing(410, 1))
clip("boing2", 0.50)(lambda: _boing(365, 2))


@clip("boing3", 0.50)
def _boing3():
    # Dritte Variante: schnellerer Zerfall, Wobble und dritter Teilton.
    dur = 0.50
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 445 * np.exp(-5.3 * t) + 64
    wobble = 1 + 0.18 * np.sin(2 * np.pi * 11 * t) * np.exp(-4 * t)
    phase = 2 * np.pi * np.cumsum(f * wobble) / SR
    sig = np.sin(phase) + 0.34 * np.sin(2 * phase) + 0.10 * np.sin(3 * phase)
    return sig * env(n, 0.003, 0.24)


# --- Plop: Teleport-Blubb + Funkel-Schimmer ----------------------------------

def _plop(base, variant):
    body = tone([base, 58], 0.22) * env(int(SR * 0.22), 0.003, 0.1)
    shimmer = tone([1600 + variant * 170, 2450 + variant * 140], 0.27)
    shimmer *= env(len(shimmer), 0.018, 0.22) * 0.18
    return np.concatenate([body, shimmer])


clip("plop1", 0.45)(lambda: _plop(285, 1))
clip("plop2", 0.45)(lambda: _plop(340, 2))


@clip("plop3", 0.45)
def _plop3():
    # Dritte Variante: Doppel-Blubb (Haupt- + Nachblase) statt nur Pitch.
    body = tone([310, 50], 0.20) * env(int(SR * 0.20), 0.002, 0.09)
    bubble = tone([420, 95], 0.07) * env(int(SR * 0.07), 0.004, 0.05) * 0.5
    shimmer = tone([1900, 2750], 0.32) * env(int(SR * 0.32), 0.02, 0.26) * 0.16
    return np.concatenate([body, silence(0.03), bubble, shimmer])


# --- Munch: Schmatzer mit Bissfolge ------------------------------------------

def _munch(variant):
    rng = np.random.default_rng(200 + variant)
    chunks = []
    for bite in range(3 + (variant % 2)):
        dur = 0.10 + 0.008 * bite
        n = int(SR * dur)
        crunch = smooth_noise(rng, n, 20)
        thud = tone([175 - bite * 13, 72], dur) * 0.75
        chunks.append((crunch * 0.5 + thud) * env(n, 0.003, 0.065))
        chunks.append(silence(0.055 + bite * 0.012))
    return np.concatenate(chunks)


clip("munch1", 0.40)(lambda: _munch(1))
clip("munch2", 0.40)(lambda: _munch(2))
clip("munch3", 0.40)(lambda: _munch(3))


# --- Snore: Atemrauschen mit Flatter -----------------------------------------

def _snore(variant):
    rng = np.random.default_rng(300 + variant)
    dur = 1.55 + variant * 0.16
    n = int(SR * dur)
    t = np.arange(n) / SR
    breath = smooth_noise(rng, n, 84)
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * (17 + variant * 3) * t)
    return breath * flutter * env(n, 0.2, 0.35)


clip("snore1", 0.27)(lambda: _snore(1))
clip("snore2", 0.27)(lambda: _snore(2))


@clip("snore3", 0.27)
def _snore3():
    # Dritte Variante: langsameres Flattern plus leiser Ausatem-Pfeifton.
    rng = np.random.default_rng(303)
    dur = 1.95
    n = int(SR * dur)
    t = np.arange(n) / SR
    breath = smooth_noise(rng, n, 96)
    flutter = 0.50 + 0.50 * np.sin(2 * np.pi * 14 * t)
    sig = breath * flutter
    whistle = tone([880, 760], dur * 0.4) * 0.05
    sig = place(sig, whistle * env(len(whistle), 0.15, 0.25), dur * 0.55)
    return sig[:n] * env(n, 0.25, 0.40)


# --- Ambient-Pools: neutral faellt, happy trillert, sleepy sinkt --------------

def _ambient_neutral(base, variant):
    sig = tone([base, base * 0.88, base * 1.04], 0.48 + variant * 0.035,
               9 + variant, 0.025)
    return sig * env(len(sig), 0.035, 0.20)


clip("ambient_neutral1", 0.30)(lambda: _ambient_neutral(390, 1))
clip("ambient_neutral2", 0.30)(lambda: _ambient_neutral(440, 2))
clip("ambient_neutral3", 0.30)(lambda: _ambient_neutral(350, 3))


def _ambient_happy(base, variant):
    sig = tone([base, base * 1.35, base * 1.12, base * 1.55],
               0.48 + variant * 0.03, 15 + variant, 0.032)
    return sig * env(len(sig), 0.025, 0.18)


clip("ambient_happy1", 0.34)(lambda: _ambient_happy(620, 1))
clip("ambient_happy2", 0.34)(lambda: _ambient_happy(700, 2))
clip("ambient_happy3", 0.34)(lambda: _ambient_happy(560, 3))


def _ambient_sleepy(base, variant):
    sig = tone([base, base * 0.78, base * 0.68], 0.72 + variant * 0.08, 6, 0.018)
    return sig * env(len(sig), 0.08, 0.30)


clip("ambient_sleepy1", 0.25)(lambda: _ambient_sleepy(310, 1))
clip("ambient_sleepy2", 0.25)(lambda: _ambient_sleepy(275, 2))


@clip("ambient_sleepy3", 0.25)
def _ambient_sleepy3():
    # Dritte Variante: tieferer Fall mit hauchigem Atemanteil.
    dur = 0.98
    n = int(SR * dur)
    voice = tone([292, 292 * 0.82, 292 * 0.60], dur, 5, 0.02)
    breath = smooth_noise(np.random.default_rng(325), n, 60, 0.04)
    return (voice + breath) * env(n, 0.10, 0.34)


# --- Sad Whimper: verhaltene, fallende Wimmerer -------------------------------

def _sad_whimper(variant, start, middle, end, dur):
    n = int(SR * dur)
    voice = tone([start, middle, end], dur, vibrato_hz=7.0, vibrato_amt=0.018)
    breath = smooth_noise(np.random.default_rng(80 + variant), n, 48, 0.025)
    return (voice * 0.86 + breath) * env(n, 0.045, 0.34)


clip("sad_whimper1", 0.30)(lambda: _sad_whimper(1, 520, 390, 245, 0.72))
clip("sad_whimper2", 0.30)(lambda: _sad_whimper(2, 470, 350, 210, 0.86))


@clip("sad_whimper3", 0.30)
def _sad_whimper3():
    # Dritte Variante: Doppel-Schluchzer mit Atempause statt einem Bogen.
    sob_a = tone([495, 430], 0.30, 6.5, 0.02) * env(int(SR * 0.30), 0.03, 0.12)
    sob_b = tone([390, 300, 228], 0.50, 6.0, 0.022) * env(int(SR * 0.50), 0.03, 0.28)
    sig = np.concatenate([sob_a, silence(0.07), sob_b])
    breath = smooth_noise(np.random.default_rng(83), len(sig), 48, 0.025)
    return sig * 0.86 + breath * env(len(sig), 0.05, 0.30)


# --- Yawn: Aufwach-Gaehnen -----------------------------------------------------

@clip("yawn1", 0.32)
def _yawn1():
    dur = 1.15
    n = int(SR * dur)
    yawn = tone([260, 330, 370, 285], dur, vibrato_hz=5.0, vibrato_amt=0.025)
    yawn += 0.18 * tone([520, 660, 740, 570], dur)
    return yawn * env(n, 0.12, 0.38)


@clip("yawn2", 0.32)
def _yawn2():
    # Schlaefriger: langsamer Bogen, Quint-Teilton und Atemhauch.
    dur = 1.30
    n = int(SR * dur)
    yawn = tone([240, 310, 345, 250], dur, vibrato_hz=4.2, vibrato_amt=0.03)
    yawn += 0.22 * tone([360, 465, 518, 375], dur)
    breath = smooth_noise(np.random.default_rng(152), n, 70, 0.05)
    return (yawn + breath) * env(n, 0.18, 0.45)


@clip("yawn3", 0.32)
def _yawn3():
    # Kurzes, muntereres Morgen-Gaehnen mit Formant-Schlenker am Ende.
    dur = 0.95
    n = int(SR * dur)
    yawn = tone([285, 355, 390, 330, 300], dur, vibrato_hz=6.0, vibrato_amt=0.02)
    yawn += 0.15 * tone([570, 710, 780, 660, 600], dur)
    yawn += 0.08 * tone([855, 1065, 1170, 990, 900], dur)
    return yawn * env(n, 0.09, 0.30)


# --- Sniff: kleine Nasen-Schnuffler -------------------------------------------

def _sniff(seed, freqs, dur0=0.085, step=0.018, gap=0.07):
    rng = np.random.default_rng(seed)
    pieces = []
    for index, frequency in enumerate(freqs):
        dur = dur0 + index * step
        n = int(SR * dur)
        breath = smooth_noise(rng, n, 18, 0.16)
        chirp = tone([frequency, frequency * 1.12], dur) * 0.20
        pieces.append((breath + chirp) * env(n, 0.006, 0.055))
        pieces.append(silence(gap))
    return np.concatenate(pieces)


clip("sniff1", 0.24)(lambda: _sniff(131, (720, 920)))
clip("sniff2", 0.24)(lambda: _sniff(132, (680, 860)))
clip("sniff3", 0.24)(lambda: _sniff(133, (750, 940, 700), 0.07, 0.012, 0.055))


# --- Whistles: drei bewusst distinct lernbare Modi (KEINE Varianten!) ---------

def _whistle(notes):
    sig = tone(list(notes), 0.34, 5, 0.01)
    return sig * env(len(sig), 0.012, 0.16)


clip("whistle_wander", 0.34)(lambda: _whistle((620, 540)))
clip("whistle_follow", 0.34)(lambda: _whistle((760, 940)))
clip("whistle_stay", 0.34)(lambda: _whistle((1040, 1040)))


# --- Brush: Fell-Buersten ------------------------------------------------------

def _brush(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.48)
    fabric = smooth_noise(rng, n, 28)
    sweep = np.linspace(0.25, 1.0, n) * np.linspace(1.0, 0.15, n)
    sig = fabric * sweep
    # 2-ms-Fade-In: der Sweep beginnt bei Faktor 0.25, was sonst einen
    # messbaren Onset-Knack am ersten Sample erzeugt (~-32 dBFS).
    fade = int(SR * 0.002)
    sig[:fade] *= np.linspace(0.0, 1.0, fade)
    return sig


clip("brush1", 0.22)(lambda: _brush(451))
clip("brush2", 0.22)(lambda: _brush(452))


@clip("brush3", 0.22)
def _brush3():
    # Dritte Variante: zwei ruhige Buersten-Zuege mit weicherem Korn.
    rng = np.random.default_rng(453)
    n = int(SR * 0.60)
    t = np.arange(n) / SR
    fabric = smooth_noise(rng, n, 36)
    passes = np.sin(np.pi * np.clip(t / 0.30, 0, 1)) ** 2 * 1.0
    passes += np.sin(np.pi * np.clip((t - 0.30) / 0.30, 0, 1)) ** 2 * 0.7
    return fabric * passes


# --- Needs: hungriges Fiepen, einsames Seufzen --------------------------------

def _whine_hungry(base, variant):
    sig = tone([base, base * 1.24, base * 1.08], 0.68 + variant * 0.06, 7, 0.028)
    return sig * env(len(sig), 0.045, 0.27)


clip("whine_hungry1", 0.29)(lambda: _whine_hungry(430, 1))
clip("whine_hungry2", 0.29)(lambda: _whine_hungry(390, 2))


@clip("whine_hungry3", 0.29)
def _whine_hungry3():
    # Dritte Variante: doppelte Bittstell-Inflektion (auf-ab-auf).
    sig = tone([412, 505, 445, 530], 0.84, 8, 0.03)
    return sig * env(len(sig), 0.05, 0.30)


def _lonely_sigh(base, variant):
    sig = tone([base, base * 0.82, base * 0.58], 0.92 + variant * 0.08, 5, 0.018)
    return sig * env(len(sig), 0.09, 0.40)


clip("lonely_sigh1", 0.24)(lambda: _lonely_sigh(350, 1))
clip("lonely_sigh2", 0.24)(lambda: _lonely_sigh(315, 2))


@clip("lonely_sigh3", 0.24)
def _lonely_sigh3():
    # Dritte Variante: laengerer Ausatmer mit hoerbarem Atemanteil.
    dur = 1.14
    n = int(SR * dur)
    voice = tone([332, 300, 240, 196], dur, 4.5, 0.015)
    breath = smooth_noise(np.random.default_rng(336), n, 60, 0.03)
    return (voice + breath) * env(n, 0.12, 0.46)


# --- Awareness: Alarm (Pool-Groesse 2 ist durch GameTest fixiert) -------------

def _alarm_squeak(base):
    first = tone([base, base * 1.48], 0.16, 24, 0.018)
    second = tone([base * 1.12, base * 1.68], 0.19, 27, 0.022)
    return np.concatenate([
        first * env(len(first), 0.006, 0.06),
        silence(0.055),
        second * env(len(second), 0.006, 0.08),
    ])


clip("alarm_squeak1", 0.48)(lambda: _alarm_squeak(980))
clip("alarm_squeak2", 0.48)(lambda: _alarm_squeak(880))


# --- Shake: Fell-Schuetteln ----------------------------------------------------

@clip("shake1", 0.30)
def _shake1():
    rng = np.random.default_rng(534)
    n = int(SR * 1.0)
    t = np.arange(n) / SR
    noise = smooth_noise(rng, n, 14)
    flutter = 0.25 + 0.75 * np.square(np.sin(2 * np.pi * 10 * t))
    return noise * flutter * env(n, 0.025, 0.22)


@clip("shake2", 0.30)
def _shake2():
    # Schnelleres, helleres Schuetteln, dessen Flattertiefe ausklingt.
    rng = np.random.default_rng(535)
    n = int(SR * 0.80)
    t = np.arange(n) / SR
    noise = smooth_noise(rng, n, 10)
    depth = 0.40 + 0.60 * np.exp(-1.5 * t)
    flutter = (1 - depth) + depth * np.square(np.sin(2 * np.pi * 13 * t))
    return noise * flutter * env(n, 0.02, 0.18)


@clip("shake3", 0.30)
def _shake3():
    # Beschleunigendes Schuetteln (7 -> 13 Hz) mit weichem Anfangs-Plumps.
    rng = np.random.default_rng(536)
    n = int(SR * 1.10)
    t = np.arange(n) / SR
    noise = smooth_noise(rng, n, 18)
    rate = 7 + 6 * np.clip(t / 1.10, 0, 1)
    phase = 2 * np.pi * np.cumsum(rate) / SR
    flutter = 0.22 + 0.78 * np.square(np.sin(phase))
    sig = noise * flutter
    thump = tone([90, 60], 0.12) * env(int(SR * 0.12), 0.004, 0.08) * 0.4
    sig = place(sig, thump, 0.0)
    return sig[:n] * env(n, 0.03, 0.26)


# --- Bond: Tier-Up-Jingle + langes Kuschel-Schnurren ---------------------------

@clip("tier_up_jingle1", 0.40)
def _tier_up_jingle1():
    notes = []
    for frequency in (523.25, 659.25, 783.99, 1046.50):
        note = tone([frequency, frequency * 1.01], 0.18, 7, 0.006)
        notes.append(note * env(len(note), 0.008, 0.09))
        notes.append(silence(0.025))
    return np.concatenate(notes)


@clip("tier_up_jingle2", 0.40)
def _tier_up_jingle2():
    # Harfen-Variante: ueberlappende Glockentoene mit Oktav-Fundament.
    sig = np.zeros(1)
    partials = ((1.0, 1.0), (2.0, 0.40), (2.76, 0.18))
    for index, frequency in enumerate((523.25, 659.25, 783.99, 1046.50)):
        note = bell(frequency, 0.34, partials, 0.16)
        note += 0.30 * bell(frequency / 2, 0.34, ((1.0, 1.0), (2.0, 0.2)), 0.20)
        sig = place(sig, note * env(len(note), 0.004, 0.10), index * 0.14)
    return sig


@clip("tier_up_jingle3", 0.40)
def _tier_up_jingle3():
    # Lauf-Variante: fuenf kurze Stufen, Schlusston mit Funkel-Teilton.
    sig = np.zeros(1)
    offset = 0.0
    for frequency in (523.25, 587.33, 659.25, 783.99):
        note = tone([frequency, frequency * 1.008], 0.12, 8, 0.005)
        sig = place(sig, note * env(len(note), 0.005, 0.06), offset)
        offset += 0.135
    final = bell(1046.50, 0.40, ((1.0, 1.0), (2.5, 0.22)), 0.14)
    return place(sig, final * env(len(final), 0.004, 0.16), offset)


@clip("snuggle_purr_long", 0.31)
def _snuggle_purr_long():
    dur = 4.2
    n = int(SR * dur)
    t = np.arange(n) / SR
    purr = (0.68 * np.sin(2 * np.pi * 104 * t)
            + 0.23 * np.sin(2 * np.pi * 208 * t)
            + 0.08 * np.sin(2 * np.pi * 312 * t))
    purr *= 0.58 + 0.42 * np.sin(2 * np.pi * 21 * t)
    return purr * env(n, 0.35, 0.65)


# --- Training: Trick-Chime + Plumps -------------------------------------------

@clip("trick_chime1", 0.38)
def _trick_chime1():
    notes = []
    for frequency in (659.25, 880.00, 1174.66):
        note = tone([frequency, frequency * 1.015], 0.13, 9, 0.005)
        notes.append(note * env(len(note), 0.005, 0.07))
        notes.append(silence(0.018))
    return np.concatenate(notes)


@clip("trick_chime2", 0.38)
def _trick_chime2():
    # Gerollter Dreiklang aus Glockentoenen, enger getimt.
    sig = np.zeros(1)
    partials = ((1.0, 1.0), (2.0, 0.35), (2.76, 0.20))
    for index, frequency in enumerate((659.25, 880.00, 1174.66)):
        note = bell(frequency, 0.26, partials, 0.12)
        sig = place(sig, note * env(len(note), 0.003, 0.08), index * 0.085)
    return sig


@clip("trick_chime3", 0.38)
def _trick_chime3():
    # Zweiton-Oktavsprung mit Schimmer und laengerem Ausklang.
    low = tone([659.25, 659.25 * 1.01], 0.15, 9, 0.005)
    high = bell(1318.51, 0.34, ((1.0, 1.0), (2.5, 0.18)), 0.13)
    return np.concatenate([
        low * env(len(low), 0.004, 0.06),
        silence(0.02),
        high * env(len(high), 0.004, 0.12),
    ])


@clip("flop_thud1", 0.34)
def _flop_thud1():
    dur = 0.42
    n = int(SR * dur)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (92 - 34 * t) * t)
    plush = smooth_noise(np.random.default_rng(636), n, 42)
    return (0.75 * body + 0.25 * plush) * env(n, 0.004, 0.34)


@clip("flop_thud2", 0.34)
def _flop_thud2():
    # Schwererer Plumps mit leisem Nachfedern.
    dur = 0.52
    n = int(SR * dur)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (78 - 26 * t) * t)
    plush = smooth_noise(np.random.default_rng(637), n, 50)
    sig = (0.78 * body + 0.22 * plush) * env(n, 0.003, 0.30)
    n2 = int(SR * 0.16)
    t2 = np.arange(n2) / SR
    bounce = np.sin(2 * np.pi * (70 - 20 * t2) * t2) * env(n2, 0.003, 0.12) * 0.45
    return place(sig, bounce, 0.20)[:n]


@clip("flop_thud3", 0.34)
def _flop_thud3():
    # Leichter, fluffiger Aufprall: mehr Pluesch, knackigere Huellkurve.
    dur = 0.30
    n = int(SR * dur)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (105 - 40 * t) * t)
    plush = smooth_noise(np.random.default_rng(638), n, 30)
    return (0.60 * body + 0.40 * plush) * env(n, 0.002, 0.20, shape=1.4)


# --- Hutch: Einstreu-Rascheln + Holz-Knarzen -----------------------------------

@clip("hutch_rustle1", 0.23)
def _hutch_rustle1():
    rng = np.random.default_rng(737)
    n = int(SR * 0.62)
    t = np.arange(n) / SR
    fabric = smooth_noise(rng, n, 26)
    sweep = np.sin(np.pi * np.clip(t / 0.62, 0, 1)) ** 1.5
    return fabric * sweep


@clip("hutch_rustle2", 0.23)
def _hutch_rustle2():
    # Flinkes Eingraben: zwei ueberlappende, hellere Wuehl-Schuebe.
    rng = np.random.default_rng(738)
    n = int(SR * 0.55)
    t = np.arange(n) / SR
    fabric = smooth_noise(rng, n, 18)
    sweep = np.sin(np.pi * np.clip(t / 0.32, 0, 1)) ** 2
    sweep += 0.8 * np.sin(np.pi * np.clip((t - 0.20) / 0.35, 0, 1)) ** 2
    return fabric * sweep


@clip("hutch_rustle3", 0.23)
def _hutch_rustle3():
    # Schlaefriges Einkuscheln: langsamer Anstieg, spaetes Nachrutschen.
    rng = np.random.default_rng(739)
    n = int(SR * 0.75)
    t = np.arange(n) / SR
    fabric = smooth_noise(rng, n, 34)
    settle = np.sin(np.pi * np.clip(t / 0.55, 0, 1)) ** 1.2
    settle += 0.5 * np.sin(np.pi * np.clip((t - 0.58) / 0.16, 0, 1)) ** 2
    return fabric * settle


@clip("hutch_creak1", 0.29)
def _hutch_creak1():
    rng = np.random.default_rng(740)
    dur = 0.72
    n = int(SR * dur)
    base = tone([185, 245, 172], dur, 5.5, 0.035)
    harmonic = tone([370, 465, 330], dur, 7.0, 0.022)
    wood = smooth_noise(rng, n, 54, 0.18)
    return (0.68 * base + 0.24 * harmonic + wood) * env(n, 0.025, 0.28)


@clip("hutch_creak2", 0.29)
def _hutch_creak2():
    # Hoeheres, quietschigeres Knarzen mit Stick-Slip-Jitter.
    rng = np.random.default_rng(741)
    dur = 0.62
    n = int(SR * dur)
    base = tone([210, 280, 195], dur, 6.5, 0.045)
    slip = 1 + 0.08 * smooth_noise(rng, n, 300)
    harmonic = tone([420, 530, 370], dur, 8.0, 0.03)
    wood = smooth_noise(rng, n, 44, 0.16)
    return (0.66 * base * slip + 0.30 * harmonic + wood) * env(n, 0.02, 0.24)


@clip("hutch_creak3", 0.29)
def _hutch_creak3():
    # Tiefes, langsames Knarzen, das mit einem Setz-Klick endet.
    rng = np.random.default_rng(742)
    dur = 0.85
    n = int(SR * dur)
    base = tone([165, 215, 150], dur, 4.5, 0.03)
    harmonic = tone([330, 410, 285], dur, 6.0, 0.02)
    wood = smooth_noise(rng, n, 64, 0.22)
    sig = (0.70 * base + 0.20 * harmonic + wood) * env(n, 0.03, 0.34)
    click = smooth_noise(rng, int(SR * 0.03), 8) * env(int(SR * 0.03), 0.001, 0.02) * 0.30
    return place(sig, click, dur - 0.09)[:n]


# --- Familie: Baby-Chirps + Nuzzle ---------------------------------------------

def _baby_squeak(base, variant):
    dur = 0.24 + variant * 0.025
    chirp = tone([base, base * 1.55, base * 1.18], dur,
                 vibrato_hz=24 + variant * 2, vibrato_amt=0.026)
    chirp += 0.16 * tone([base * 2.0, base * 2.45, base * 2.1], dur)
    return chirp * env(len(chirp), 0.004, 0.10)


clip("baby_squeak1", 0.34)(lambda: _baby_squeak(1180, 1))
clip("baby_squeak2", 0.34)(lambda: _baby_squeak(1320, 2))
clip("baby_squeak3", 0.34)(lambda: _baby_squeak(1080, 3))


@clip("nuzzle1", 0.26)
def _nuzzle1():
    rng = np.random.default_rng(838)
    dur = 1.05
    n = int(SR * dur)
    fabric = smooth_noise(rng, n, 58)
    purr = tone([150, 142, 158], dur, 18, 0.018)
    return (0.68 * purr + 0.32 * fabric) * env(n, 0.12, 0.34)


@clip("nuzzle2", 0.26)
def _nuzzle2():
    # Waermer und ruhiger: tieferes Brummen mit Oktav-Hauch, weniger Stoff.
    rng = np.random.default_rng(839)
    dur = 1.20
    n = int(SR * dur)
    fabric = smooth_noise(rng, n, 66)
    purr = tone([138, 132, 145], dur, 14, 0.02)
    purr += 0.20 * tone([276, 264, 290], dur, 14, 0.02)
    return (0.76 * purr + 0.24 * fabric) * env(n, 0.16, 0.40)


@clip("nuzzle3", 0.26)
def _nuzzle3():
    # Aufgeweckter Stupser: heller, kuerzer, mit Aufwaerts-Schlenker am Ende.
    rng = np.random.default_rng(840)
    dur = 0.90
    n = int(SR * dur)
    fabric = smooth_noise(rng, n, 48)
    purr = tone([162, 150, 170, 185], dur, 20, 0.016)
    return (0.60 * purr + 0.40 * fabric) * env(n, 0.09, 0.28)


# --- Fashion: Stoff-Flourish ----------------------------------------------------

@clip("dress_up1", 0.24)
def _dress_up1():
    rng = np.random.default_rng(939)
    dur = 0.58
    n = int(SR * dur)
    fabric = smooth_noise(rng, n, 31)
    chime = tone([660, 880, 1046], dur, 7, 0.008) * 0.16
    return (0.72 * fabric + chime) * env(n, 0.018, 0.25)


@clip("dress_up2", 0.24)
def _dress_up2():
    # Zackiger Doppel-Swoosh mit hoeherem Funkeln.
    rng = np.random.default_rng(940)
    dur = 0.52
    n = int(SR * dur)
    t = np.arange(n) / SR
    fabric = smooth_noise(rng, n, 22)
    swipes = np.sin(np.pi * np.clip(t / 0.24, 0, 1)) ** 2
    swipes += 0.85 * np.sin(np.pi * np.clip((t - 0.26) / 0.24, 0, 1)) ** 2
    sparkle = tone([880, 1174.66, 1318.51], dur, 8, 0.007) * 0.13
    return fabric * swipes * 0.8 + sparkle * env(n, 0.02, 0.20)


@clip("dress_up3", 0.24)
def _dress_up3():
    # Seidiger Einzel-Swoosh: Korn wird zum Ende hin feiner, tiefes Glitzern.
    rng = np.random.default_rng(941)
    dur = 0.65
    n = int(SR * dur)
    t = np.arange(n) / SR
    coarse = smooth_noise(rng, n, 40)
    fine = smooth_noise(rng, n, 16)
    blend = np.linspace(0, 1, n)
    fabric = coarse * (1 - blend) + fine * blend
    chime = tone([523.25, 659.25, 783.99], dur, 6, 0.008) * 0.14
    return (0.74 * fabric + chime) * env(n, 0.03, 0.30)


# --- Wild: tragender Zwei-Noten-Ruf ---------------------------------------------

@clip("wild_call1", 0.38)
def _wild_call1():
    first = tone([510, 760, 650], 0.72, vibrato_hz=7.0, vibrato_amt=0.018)
    second = tone([620, 910, 720], 0.86, vibrato_hz=8.0, vibrato_amt=0.022)
    return np.concatenate([
        first * env(len(first), 0.06, 0.28),
        silence(0.18),
        second * env(len(second), 0.05, 0.38),
    ])


@clip("wild_call2", 0.38)
def _wild_call2():
    # Tieferer, melancholischer Ruf mit mehr Vibrato und laengerer Pause.
    first = tone([470, 690, 590], 0.80, vibrato_hz=6.5, vibrato_amt=0.026)
    second = tone([560, 820, 660], 0.95, vibrato_hz=7.5, vibrato_amt=0.03)
    return np.concatenate([
        first * env(len(first), 0.07, 0.30),
        silence(0.22),
        second * env(len(second), 0.06, 0.42),
    ])


@clip("wild_call3", 0.38)
def _wild_call3():
    # Suchender Dreier-Ruf: drei kuerzere, steigende Noten.
    a = tone([540, 780, 700], 0.50, vibrato_hz=8.0, vibrato_amt=0.02)
    b = tone([640, 900, 780], 0.55, vibrato_hz=8.5, vibrato_amt=0.022)
    c = tone([720, 1010, 820], 0.62, vibrato_hz=9.0, vibrato_amt=0.025)
    return np.concatenate([
        a * env(len(a), 0.05, 0.20),
        silence(0.12),
        b * env(len(b), 0.05, 0.22),
        silence(0.14),
        c * env(len(c), 0.05, 0.30),
    ])


# --- Social: Gooby-zu-Gooby-Chirps ----------------------------------------------

def _chirp_social(notes, variant):
    sig = tone(list(notes), 0.34 + variant * 0.03,
               vibrato_hz=18 + variant * 2, vibrato_amt=0.022)
    return sig * env(len(sig), 0.006, 0.16)


clip("chirp_social1", 0.31)(lambda: _chirp_social((760, 1120, 920), 1))
clip("chirp_social2", 0.31)(lambda: _chirp_social((880, 1260, 1040), 2))


@clip("chirp_social3", 0.31)
def _chirp_social3():
    # Dritte Variante: Vier-Punkte-Triller mit schnellerem Vibrato.
    sig = tone([820, 1180, 860, 1090], 0.42, vibrato_hz=24, vibrato_amt=0.024)
    return sig * env(len(sig), 0.006, 0.18)


# --- Treasure: Boden-Schnueffeln + Karten-Rascheln -------------------------------

@clip("sniff_long1", 0.26)
def _sniff_long1():
    rng = np.random.default_rng(843)
    dur = 1.45
    n = int(SR * dur)
    breath = smooth_noise(rng, n, 38)
    nose = tone([310, 470, 280, 520, 340], dur, 9.0, 0.025)
    return (0.55 * breath + 0.45 * nose) * env(n, 0.04, 0.32)


@clip("sniff_long2", 0.26)
def _sniff_long2():
    # Rhythmische Dreifach-Schnueffelei statt eines Bogens.
    rng = np.random.default_rng(844)
    pieces = []
    for index, dur in enumerate((0.28, 0.34, 0.40)):
        n = int(SR * dur)
        breath = smooth_noise(rng, n, 30)
        nose = tone([290 + index * 25, 410 + index * 30, 330], dur, 10.0, 0.028)
        pieces.append((0.55 * breath + 0.45 * nose) * env(n, 0.02, 0.10))
        pieces.append(silence(0.09))
    return np.concatenate(pieces)


@clip("sniff_long3", 0.26)
def _sniff_long3():
    # Aufgeregtes, helleres Wander-Schnueffeln mit schnellerem Vibrato.
    rng = np.random.default_rng(845)
    dur = 1.35
    n = int(SR * dur)
    breath = smooth_noise(rng, n, 26)
    nose = tone([340, 520, 300, 560, 380, 300], dur, 12.0, 0.03)
    return (0.50 * breath + 0.50 * nose) * env(n, 0.035, 0.30)


@clip("map_rustle1", 0.22)
def _map_rustle1():
    rng = np.random.default_rng(846)
    dur = 0.82
    n = int(SR * dur)
    paper = smooth_noise(rng, n, 19)
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * 15 * np.arange(n) / SR)
    return paper * flutter * env(n, 0.015, 0.25)


@clip("map_rustle2", 0.22)
def _map_rustle2():
    # Knackiges Doppel-Entfalten mit Knick-Schnipser in der Mitte.
    rng = np.random.default_rng(847)
    dur = 0.75
    n = int(SR * dur)
    t = np.arange(n) / SR
    paper = smooth_noise(rng, n, 14)
    flutter = (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t)) * (t < 0.30)
    flutter += (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * (t >= 0.36)
    sig = paper * flutter
    snap = smooth_noise(rng, int(SR * 0.025), 4) * env(int(SR * 0.025), 0.001, 0.018) * 0.9
    sig = place(sig, snap, 0.31)
    return sig[:n] * env(n, 0.01, 0.20)


@clip("map_rustle3", 0.22)
def _map_rustle3():
    # Langsames, sorgfaeltiges Aufrollen mit weichem Papierkorn.
    rng = np.random.default_rng(848)
    dur = 0.95
    n = int(SR * dur)
    paper = smooth_noise(rng, n, 26)
    flutter = 0.65 + 0.35 * np.sin(2 * np.pi * 6.5 * np.arange(n) / SR)
    return paper * flutter * env(n, 0.04, 0.30)


# ---------------------------------------------------------------------------
# Rendern + Encoden
# ---------------------------------------------------------------------------

def require_ffmpeg():
    """Klare Fehlermeldung statt rohem FileNotFoundError-Traceback."""
    if shutil.which("ffmpeg") is None:
        sys.exit("FEHLER: ffmpeg ist nicht auf dem PATH. Synthese UND "
                 "Verifikation brauchen ffmpeg (Encode/Decode) -- "
                 "Installation siehe docs/AUDIO.md.")


def save(name, signal, peak):
    signal = np.asarray(signal, dtype=np.float64)
    assert len(signal) >= int(SR * DURATION_MIN), f"{name}: zu kurz"
    signal = signal / (np.max(np.abs(signal)) + 1e-9) * peak
    pcm = (signal * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    try:
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        ogg_path = os.path.join(OUT, name + ".ogg")
        # bitexact + metadata strip => byte-reproduzierbare Ogg-Dateien.
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
                        "-c:a", "libvorbis", "-q:a", "4",
                        "-map_metadata", "-1",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        ogg_path], check=True)
    finally:
        os.unlink(wav_path)


def generate():
    print(f"Synthetisiere {len(CLIPS)} Gooby-Sounds…")
    for name in sorted(CLIPS):
        fn, peak = CLIPS[name]
        save(name, fn(), peak)
        print(f"   {name}.ogg")


# ---------------------------------------------------------------------------
# Verifikation (stdlib-Ogg-Parser + ffmpeg-Decode)
# ---------------------------------------------------------------------------

def parse_ogg(path):
    """Liest Magic/Version/Kanaele/Rate/Granule direkt aus dem Ogg-Container."""
    with open(path, "rb") as handle:
        data = handle.read()
    assert data[:4] == b"OggS", f"{path}: fehlendes OggS-Magic"
    offset = 0
    last_granule = 0
    first_payload = b""
    while offset < len(data):
        assert data[offset:offset + 4] == b"OggS", f"{path}: kaputte Page @{offset}"
        version = data[offset + 4]
        assert version == 0, f"{path}: unbekannte Ogg-Version {version}"
        granule = struct.unpack_from("<q", data, offset + 6)[0]
        if granule > 0:
            last_granule = max(last_granule, granule)
        nsegs = data[offset + 26]
        table = data[offset + 27:offset + 27 + nsegs]
        payload_len = sum(table)
        payload_off = offset + 27 + nsegs
        if not first_payload:
            first_payload = data[payload_off:payload_off + payload_len]
        offset = payload_off + payload_len
    assert first_payload[:7] == b"\x01vorbis", f"{path}: kein Vorbis-ID-Header"
    channels = first_payload[11]
    rate = struct.unpack_from("<I", first_payload, 12)[0]
    return {"channels": channels, "rate": rate,
            "duration": last_granule / rate if rate else 0.0,
            "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def decode_metrics(path):
    """Dekodiert per ffmpeg zu f32-PCM und misst Peak / RMS / aktive RMS."""
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", path,
         "-f", "f32le", "-ac", "1", "-"],
        check=True, capture_output=True).stdout
    samples = np.frombuffer(raw, dtype=np.float32)
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples ** 2)))
    active = samples[np.abs(samples) > 0.05 * peak] if peak > 0 else samples
    active_rms = float(np.sqrt(np.mean(active ** 2))) if len(active) else 0.0
    return peak, rms, active_rms


def family_of(name):
    return re.sub(r"\d+$", "", name)


# ---------------------------------------------------------------------------
# Audio-Manifest (docs/audio_manifest.json)
# ---------------------------------------------------------------------------

def toolchain_info():
    """Referenz-Toolchain, die die aktuellen Clips erzeugt hat (nur Doku)."""
    banner = subprocess.run(["ffmpeg", "-version"], check=True,
                            capture_output=True, text=True).stdout
    return {
        "ffmpeg": " ".join(banner.splitlines()[0].split()[:3]),
        "numpy": np.__version__,
        "python": ".".join(str(part) for part in sys.version_info[:3]),
        "note": ("Nur Dokumentation der Referenz-Toolchain -- verify() "
                 "vergleicht ausschliesslich die sha256-Werte unter 'clips'."),
    }


def write_manifest(metrics):
    payload = {
        "_comment": ("Committete SHA-256-Referenz aller generierten Gooby-"
                     "Clips. Nur bewusst aktualisieren via 'python3 scripts/"
                     "gen_sounds.py --update-manifest' (siehe docs/AUDIO.md)."),
        "toolchain": toolchain_info(),
        "clips": {name: {"sha256": info["sha256"], "size": info["size"],
                         "duration": info["duration"]}
                  for name, info in sorted(metrics.items())},
    }
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def check_manifest(metrics):
    """Fail-closed-Abgleich der On-Disk-Clips gegen das committete Manifest."""
    rel = os.path.relpath(MANIFEST, ROOT)
    if not os.path.exists(MANIFEST):
        return [f"Audio-Manifest fehlt: {rel} -- bewusst erzeugen mit "
                "'python3 scripts/gen_sounds.py --update-manifest'"]
    with open(MANIFEST, encoding="utf-8") as handle:
        manifest_clips = json.load(handle).get("clips", {})
    problems = []
    for name in sorted(set(manifest_clips) - set(metrics)):
        problems.append(f"Manifest-Eintrag ohne gesunde Datei: {name} "
                        f"(Manifest: {rel})")
    for name in sorted(set(metrics) - set(manifest_clips)):
        problems.append(f"Datei ohne Manifest-Eintrag: {name}.ogg -- bewusst "
                        "uebernehmen mit --update-manifest")
    for name in sorted(set(metrics) & set(manifest_clips)):
        if manifest_clips[name].get("sha256") != metrics[name]["sha256"]:
            problems.append(
                f"{name}: SHA-256 weicht vom Manifest ab (Toolchain-Drift "
                "oder unbeabsichtigte Aenderung) -- bewusst uebernehmen mit "
                "--update-manifest")
    return problems


def referenced_files():
    """Alle in sounds.json referenzierten goobymod-Clips (Dateinamen)."""
    with open(SOUNDS_JSON, encoding="utf-8") as handle:
        sounds = json.load(handle)
    names = set()
    jitter = {}
    for event, definition in sounds.items():
        for entry in definition["sounds"]:
            if isinstance(entry, str):
                ref, meta = entry, {}
            else:
                ref, meta = entry["name"], entry
            assert ref.startswith(SOUND_PREFIX), f"{event}: fremder Sound {ref}"
            names.add(ref[len(SOUND_PREFIX):])
            jitter.setdefault(event, []).append(meta)
    return sounds, names, jitter


def verify(metrics_out=None, update_manifest=False):
    problems = []
    sounds, referenced, jitter = referenced_files()

    on_disk = {f[:-4] for f in os.listdir(OUT) if f.endswith(".ogg")}
    for name in sorted(referenced - on_disk):
        problems.append(f"sounds.json referenziert fehlende Datei: {name}.ogg")
    for name in sorted(on_disk - referenced):
        problems.append(f"Verwaiste Datei ohne sounds.json-Referenz: {name}.ogg")
    for name in sorted(on_disk - set(CLIPS)):
        problems.append(f"Datei ohne Generator-Rezept: {name}.ogg")
    for name in sorted(set(CLIPS) - on_disk):
        problems.append(f"Generator-Rezept ohne Datei: {name}.ogg")

    # Familien-Kardinalitaeten
    families = {}
    for name in sorted(set(CLIPS)):
        families.setdefault(family_of(name), []).append(name)
    for family in FREQUENT_FAMILIES:
        count = len(families.get(family, []))
        if count < 3:
            problems.append(f"Haeufige Familie {family} hat nur {count} Varianten")
    for family in SINGLE_FAMILIES:
        count = len(families.get(family, []))
        if count != 1:
            problems.append(f"{family} muss genau 1 Variante behalten, hat {count}")
    for family, expected in LOCKED_FAMILIES.items():
        count = len(families.get(family, []))
        if count != expected:
            problems.append(f"{family} ist auf {expected} Varianten fixiert, hat {count}")

    # Datei-Metriken
    metrics = {}
    for name in sorted(on_disk & set(CLIPS)):
        path = os.path.join(OUT, name + ".ogg")
        try:
            info = parse_ogg(path)
            peak, rms, active_rms = decode_metrics(path)
        except (AssertionError, subprocess.CalledProcessError) as error:
            problems.append(f"{name}: Datei unlesbar/korrupt ({error})")
            continue
        info.update(peak=round(peak, 4), rms=round(rms, 4),
                    active_rms=round(active_rms, 4),
                    duration=round(info["duration"], 3))
        metrics[name] = info
        if info["channels"] != 1:
            problems.append(f"{name}: {info['channels']} Kanaele statt mono")
        if info["rate"] != SR:
            problems.append(f"{name}: Samplerate {info['rate']} statt {SR}")
        if not DURATION_MIN <= info["duration"] <= DURATION_MAX:
            problems.append(f"{name}: Dauer {info['duration']}s ausserhalb Bounds")
        if not SIZE_MIN <= info["size"] <= SIZE_MAX:
            problems.append(f"{name}: Dateigroesse {info['size']}B ausserhalb Bounds")
        if not PEAK_MIN <= peak <= PEAK_MAX:
            problems.append(f"{name}: Peak {peak:.3f} ausserhalb [{PEAK_MIN}, {PEAK_MAX}]")
        if not RMS_MIN <= rms <= RMS_MAX:
            problems.append(f"{name}: RMS {rms:.4f} ausserhalb [{RMS_MIN}, {RMS_MAX}]")

    # Varianten byte-verschieden + Lautheit pro Familie konsistent
    for family, names in sorted(families.items()):
        present = [n for n in names if n in metrics]
        hashes = {metrics[n]["sha256"] for n in present}
        if len(hashes) != len(present):
            problems.append(f"Familie {family}: Varianten sind bytegleich")
        actives = [metrics[n]["active_rms"] for n in present
                   if metrics[n]["active_rms"] > 0]
        if len(actives) > 1 and max(actives) / min(actives) > FAMILY_RMS_SPREAD:
            problems.append(f"Familie {family}: aktive RMS streut zu stark "
                            f"({min(actives):.3f}..{max(actives):.3f})")

    # Pool-Jitter-Grenzen in sounds.json. Enge Pool-Bounds gespiegelt aus
    # GoobyAudioExpansionTests.pools_apply_weights_and_gentle_jitter.
    for event, entries in sorted(jitter.items()):
        weighted = False
        jittered = False
        for meta in entries:
            weight = meta.get("weight", 1)
            pitch = meta.get("pitch")
            volume = meta.get("volume")
            if not 1 <= weight <= 8:
                problems.append(f"{event}: Gewicht {weight} ausserhalb [1, 8]")
            weighted = weighted or weight > 1
            if pitch is not None:
                jittered = True
                if not GLOBAL_PITCH_MIN <= pitch <= GLOBAL_PITCH_MAX:
                    problems.append(f"{event}: Pitch {pitch} ausserhalb "
                                    f"[{GLOBAL_PITCH_MIN}, {GLOBAL_PITCH_MAX}]")
            if volume is not None:
                jittered = True
                if not 0.5 < volume <= 1.0:
                    problems.append(f"{event}: Volume {volume} ausserhalb (0.5, 1.0]")
        if len(entries) < 3 or event in JITTER_EXEMPT_EVENTS:
            continue
        for meta in entries:
            pitch = meta.get("pitch")
            volume = meta.get("volume")
            if pitch is not None and not POOL_PITCH_MIN <= pitch <= POOL_PITCH_MAX:
                problems.append(f"{event}: Pool-Pitch {pitch} ausserhalb "
                                f"[{POOL_PITCH_MIN}, {POOL_PITCH_MAX}]")
            if volume is not None and not POOL_VOLUME_MIN <= volume <= POOL_VOLUME_MAX:
                problems.append(f"{event}: Pool-Volume {volume} ausserhalb "
                                f"[{POOL_VOLUME_MIN}, {POOL_VOLUME_MAX}]")
        if not weighted:
            problems.append(f"{event}: Multi-Varianten-Pool ohne Gewichtung")
        if not jittered:
            problems.append(f"{event}: Multi-Varianten-Pool ohne Pitch-/Volume-Jitter")

    # Manifest-Abgleich (fail-closed); --update-manifest schreibt es bewusst neu.
    if update_manifest:
        write_manifest(metrics)
        print(f"Manifest aktualisiert: {os.path.relpath(MANIFEST, ROOT)}")
    problems.extend(check_manifest(metrics))

    print(f"\nGeprueft: {len(metrics)} Dateien, {len(families)} Familien, "
          f"{len(sounds)} Sound-Events")
    print(f"{'Clip':<22}{'Dauer':>7}{'Groesse':>9}{'Peak':>7}{'RMS':>8}{'aktRMS':>8}")
    for name in sorted(metrics):
        m = metrics[name]
        print(f"{name:<22}{m['duration']:>6.2f}s{m['size']:>8}B"
              f"{m['peak']:>7.3f}{m['rms']:>8.4f}{m['active_rms']:>8.4f}")

    if metrics_out:
        with open(metrics_out, "w", encoding="utf-8") as handle:
            json.dump(metrics, handle, indent=2, sort_keys=True)
        print(f"Metriken geschrieben: {metrics_out}")

    if problems:
        print("\nFEHLER:")
        for problem in problems:
            print(f"  - {problem}")
        return False
    print("\nAlle Audio-Checks bestanden.")
    return True


def prune():
    managed = {name + ".ogg" for name in CLIPS}
    for filename in sorted(os.listdir(OUT)):
        if filename.endswith(".ogg") and filename not in managed:
            os.unlink(os.path.join(OUT, filename))
            print(f"   geloescht (unmanaged): {filename}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true",
                        help="nur pruefen, nichts synthetisieren")
    parser.add_argument("--prune", action="store_true",
                        help="unmanaged .ogg-Dateien im Zielordner loeschen")
    parser.add_argument("--metrics", metavar="PATH",
                        help="Metriken als JSON nach PATH schreiben")
    parser.add_argument("--update-manifest", action="store_true",
                        help="docs/audio_manifest.json bewusst neu schreiben "
                             "(expliziter, review-barer Schritt)")
    args = parser.parse_args()

    require_ffmpeg()
    if not args.verify:
        generate()
    if args.prune:
        prune()
    if not verify(args.metrics, update_manifest=args.update_manifest):
        sys.exit(1)


if __name__ == "__main__":
    main()
