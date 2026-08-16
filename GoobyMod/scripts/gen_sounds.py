#!/usr/bin/env python3
"""Synthetisiert Goobys Sounds (numpy → wav → ffmpeg → ogg). NIEDLICH!

Aufruf:  python3 scripts/gen_sounds.py
Schreibt nach src/main/resources/assets/goobymod/sounds/entity/gooby/.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "src", "main", "resources", "assets", "goobymod",
                   "sounds", "entity", "gooby")


def env(n, attack=0.02, release=0.3):
    """Huellkurve: weicher Attack, weiches Release."""
    e = np.ones(n)
    a = int(SR * attack)
    r = int(SR * release)
    if a > 0:
        e[:a] = np.linspace(0, 1, a)
    if r > 0 and r < n:
        e[-r:] = np.linspace(1, 0, r)
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


def save(name, signal, peak=0.5):
    signal = signal / (np.max(np.abs(signal)) + 1e-9) * peak
    pcm = (signal * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    ogg_path = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
                    "-c:a", "libvorbis", "-q:a", "4", ogg_path], check=True)
    os.unlink(wav_path)
    print("  ", ogg_path)


def gen_squeak():
    """Zwei schnelle, aufsteigende Quietscher — pures Glueck."""
    a = tone([850, 1450], 0.14, vibrato_hz=30, vibrato_amt=0.02) * env(int(SR * 0.14), 0.008, 0.05)
    gap = np.zeros(int(SR * 0.05))
    b = tone([950, 1650], 0.18, vibrato_hz=30, vibrato_amt=0.03) * env(int(SR * 0.18), 0.008, 0.09)
    sig = np.concatenate([a, gap, b])
    # Etwas Obertoene fuer den "Plueschtier"-Charakter
    sig = sig + 0.3 * np.roll(sig, 3) * sig
    save("squeak", sig, peak=0.45)


def gen_purr():
    """Weiches Schnurren: tiefer Ton, amplitudenmoduliert."""
    dur = 1.4
    n = int(SR * dur)
    t = np.arange(n) / SR
    base = tone([115, 105, 118, 108], dur) * 0.7 + tone([232, 214], dur) * 0.25
    rumble = 0.14 * (np.random.default_rng(42).random(n) * 2 - 1)
    # Tiefpass fuers Rauschen (einfacher gleitender Mittelwert)
    kernel = np.ones(64) / 64
    rumble = np.convolve(rumble, kernel, mode="same")
    am = 0.55 + 0.45 * np.sin(2 * np.pi * 24 * t)
    sig = (base + rumble) * am * env(n, 0.15, 0.35)
    save("purr", sig, peak=0.4)


def gen_boing():
    """BOING! Federnder Abpraller — Schlaege prallen einfach ab."""
    dur = 0.55
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 340 * np.exp(-4.5 * t) + 70
    wobble = 1 + 0.25 * np.sin(2 * np.pi * 13 * t) * np.exp(-3 * t)
    phase = 2 * np.pi * np.cumsum(f * wobble) / SR
    sig = np.sin(phase) * env(n, 0.004, 0.3)
    sig += 0.3 * np.sin(2 * phase) * env(n, 0.004, 0.18)
    save("boing", sig, peak=0.55)


def gen_plop():
    """Plop! Magischer Teleport-/Verwandlungs-Sound."""
    dur = 0.22
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 320 * np.exp(-14 * t) + 55
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = np.sin(phase) * env(n, 0.002, 0.1)
    # Funkel-Schimmer hinterher
    shimmer = tone([1800, 2600], 0.3) * env(int(SR * 0.3), 0.02, 0.25) * 0.2
    sig = np.concatenate([sig, shimmer])
    save("plop", sig, peak=0.5)


def gen_munch():
    """Schmatzen — Gesicht im Nutella-Glas."""
    rng = np.random.default_rng(7)
    chunks = []
    for i in range(4):
        dur = 0.11
        n = int(SR * dur)
        noise = rng.random(n) * 2 - 1
        kernel = np.ones(24) / 24
        noise = np.convolve(noise, kernel, mode="same")
        chomp = noise * env(n, 0.004, 0.07)
        thud = tone([160 - i * 12, 70], dur) * env(n, 0.002, 0.08) * 0.8
        chunks.append(chomp + thud)
        chunks.append(np.zeros(int(SR * (0.07 + 0.02 * i))))
    save("munch", np.concatenate(chunks), peak=0.45)


def gen_snore():
    """Leises Schnarchen: ein- und ausatmen."""
    rng = np.random.default_rng(11)
    parts = []
    for direction in (1, -1):
        dur = 0.8
        n = int(SR * dur)
        noise = rng.random(n) * 2 - 1
        kernel = np.ones(90) / 90
        noise = np.convolve(noise, kernel, mode="same")
        t = np.arange(n) / SR
        flutter = 1 + 0.5 * np.sin(2 * np.pi * (26 if direction == 1 else 18) * t)
        parts.append(noise * flutter * env(n, 0.2, 0.3) * (1.0 if direction == 1 else 0.6))
        parts.append(np.zeros(int(SR * 0.12)))
    save("snore", np.concatenate(parts), peak=0.3)


def gen_ambient():
    """Zufriedenes Muemmel-Geraeusch: zwei weiche Toene."""
    a = tone([520, 430], 0.22, vibrato_hz=12, vibrato_amt=0.03) * env(int(SR * 0.22), 0.03, 0.1)
    gap = np.zeros(int(SR * 0.08))
    b = tone([360, 470], 0.28, vibrato_hz=10, vibrato_amt=0.04) * env(int(SR * 0.28), 0.03, 0.16)
    sig = np.concatenate([a, gap, b])
    save("ambient", sig, peak=0.35)


def gen_sad_whimper():
    """Two restrained descending whimpers; deliberately unlike the happy squeak."""
    for variant, start, middle, end, duration in (
            (1, 520, 390, 245, 0.72),
            (2, 470, 350, 210, 0.86)):
        n = int(SR * duration)
        voice = tone([start, middle, end], duration, vibrato_hz=7.0, vibrato_amt=0.018)
        breath = np.random.default_rng(80 + variant).normal(0.0, 0.025, n)
        breath = np.convolve(breath, np.ones(48) / 48, mode="same")
        signal = (voice * 0.86 + breath) * env(n, 0.045, 0.34)
        save(f"sad_whimper{variant}", signal, peak=0.30)


def gen_yawn_and_sniff():
    """Wake-up yawn plus two tiny rabbit-like nose sniffs."""
    duration = 1.15
    n = int(SR * duration)
    yawn = tone([260, 330, 370, 285], duration, vibrato_hz=5.0, vibrato_amt=0.025)
    yawn += 0.18 * tone([520, 660, 740, 570], duration)
    save("yawn", yawn * env(n, 0.12, 0.38), peak=0.32)

    for variant, seed, first, second in ((1, 131, 720, 920), (2, 132, 680, 860)):
        rng_local = np.random.default_rng(seed)
        pieces = []
        for index, frequency in enumerate((first, second)):
            duration = 0.085 + index * 0.018
            count = int(SR * duration)
            breath = rng_local.normal(0.0, 0.16, count)
            breath = np.convolve(breath, np.ones(18) / 18, mode="same")
            chirp = tone([frequency, frequency * 1.12], duration) * 0.20
            pieces.append((breath + chirp) * env(count, 0.006, 0.055))
            pieces.append(np.zeros(int(SR * 0.07)))
        save(f"sniff{variant}", np.concatenate(pieces), peak=0.24)


def gen_v32_soundscape():
    """Generate deterministic, mood-readable variant pools for v3.2."""
    # Happy squeaks
    for variant, base in enumerate((820, 900, 760), start=1):
        first = tone([base, base * 1.62], 0.14, 28, 0.022)
        second = tone([base * 1.08, base * 1.82], 0.17, 31, 0.025)
        signal = np.concatenate([
            first * env(len(first), 0.008, 0.055),
            np.zeros(int(SR * (0.035 + variant * 0.008))),
            second * env(len(second), 0.008, 0.075),
        ])
        save(f"squeak{variant}", signal, peak=0.42)

    # Purr one-shots and a mathematically periodic seamless loop.
    for variant, base in enumerate((102, 111, 119), start=1):
        duration = 1.25 + variant * 0.08
        count = int(SR * duration)
        time = np.arange(count) / SR
        signal = (0.72 * np.sin(2 * np.pi * base * time)
                  + 0.22 * np.sin(2 * np.pi * base * 2 * time))
        signal *= 0.58 + 0.42 * np.sin(2 * np.pi * (21 + variant) * time)
        save(f"purr{variant}", signal * env(count, 0.12, 0.28), peak=0.34)
    duration = 2.0
    count = int(SR * duration)
    time = np.arange(count) / SR
    loop = (0.74 * np.sin(2 * np.pi * 110 * time)
            + 0.20 * np.sin(2 * np.pi * 220 * time))
    loop *= 0.62 + 0.38 * np.sin(2 * np.pi * 22 * time)
    save("purr_loop", loop, peak=0.30)

    for variant, start in enumerate((410, 365), start=1):
        duration = 0.52 + variant * 0.04
        count = int(SR * duration)
        time = np.arange(count) / SR
        frequency = start * np.exp(-4.4 * time) + 68
        phase = 2 * np.pi * np.cumsum(frequency) / SR
        signal = (np.sin(phase) + 0.27 * np.sin(2 * phase)) * env(count, 0.004, 0.27)
        save(f"boing{variant}", signal, peak=0.50)

    for variant, base in enumerate((285, 340), start=1):
        body = tone([base, 58], 0.22) * env(int(SR * 0.22), 0.003, 0.1)
        shimmer = tone([1600 + variant * 170, 2450 + variant * 140], 0.27)
        shimmer *= env(len(shimmer), 0.018, 0.22) * 0.18
        save(f"plop{variant}", np.concatenate([body, shimmer]), peak=0.45)

    for variant in range(1, 4):
        rng_local = np.random.default_rng(200 + variant)
        chunks = []
        for bite in range(3 + (variant % 2)):
            duration = 0.10 + 0.008 * bite
            count = int(SR * duration)
            crunch = np.convolve(rng_local.normal(0, 1, count), np.ones(20) / 20, mode="same")
            thud = tone([175 - bite * 13, 72], duration) * 0.75
            chunks.extend([(crunch * 0.5 + thud) * env(count, 0.003, 0.065),
                           np.zeros(int(SR * (0.055 + bite * 0.012)))])
        save(f"munch{variant}", np.concatenate(chunks), peak=0.40)

    for variant in (1, 2):
        rng_local = np.random.default_rng(300 + variant)
        duration = 1.55 + variant * 0.16
        count = int(SR * duration)
        time = np.arange(count) / SR
        breath = np.convolve(rng_local.normal(0, 1, count), np.ones(84) / 84, mode="same")
        flutter = 0.55 + 0.45 * np.sin(2 * np.pi * (17 + variant * 3) * time)
        save(f"snore{variant}", breath * flutter * env(count, 0.2, 0.35), peak=0.27)

    # Neutral mumbles descend, happy trills rise, sleepy calls drift downward.
    for variant, base in enumerate((390, 440, 350), start=1):
        signal = tone([base, base * 0.88, base * 1.04], 0.48 + variant * 0.035,
                      9 + variant, 0.025)
        save(f"ambient_neutral{variant}", signal * env(len(signal), 0.035, 0.20), peak=0.30)
    for variant, base in enumerate((620, 700, 560), start=1):
        signal = tone([base, base * 1.35, base * 1.12, base * 1.55], 0.48 + variant * 0.03,
                      15 + variant, 0.032)
        save(f"ambient_happy{variant}", signal * env(len(signal), 0.025, 0.18), peak=0.34)
    for variant, base in enumerate((310, 275), start=1):
        signal = tone([base, base * 0.78, base * 0.68], 0.72 + variant * 0.08, 6, 0.018)
        save(f"ambient_sleepy{variant}", signal * env(len(signal), 0.08, 0.30), peak=0.25)

    # Three learned whistle pitches: wander low, follow middle, stay high.
    for name, notes in (
            ("whistle_wander", (620, 540)),
            ("whistle_follow", (760, 940)),
            ("whistle_stay", (1040, 1040))):
        signal = tone(list(notes), 0.34, 5, 0.01)
        save(name, signal * env(len(signal), 0.012, 0.16), peak=0.34)

    for variant, seed in ((1, 451), (2, 452)):
        rng_local = np.random.default_rng(seed)
        count = int(SR * 0.48)
        fabric = np.convolve(rng_local.normal(0, 1, count), np.ones(28) / 28, mode="same")
        sweep = np.linspace(0.25, 1.0, count) * np.linspace(1.0, 0.15, count)
        save(f"brush{variant}", fabric * sweep, peak=0.22)


def gen_v33_needs_sounds():
    """Hungry whines rise pleadingly; lonely sighs fall and breathe out."""
    for variant, base in ((1, 430), (2, 390)):
        signal = tone([base, base * 1.24, base * 1.08], 0.68 + variant * 0.06, 7, 0.028)
        save(f"whine_hungry{variant}", signal * env(len(signal), 0.045, 0.27), peak=0.29)
    for variant, base in ((1, 350), (2, 315)):
        signal = tone([base, base * 0.82, base * 0.58], 0.92 + variant * 0.08, 5, 0.018)
        save(f"lonely_sigh{variant}", signal * env(len(signal), 0.09, 0.40), peak=0.24)


def gen_v34_awareness_sounds():
    """Sharp warning chirps plus a soft, damp fur shake."""
    for variant, base in ((1, 980), (2, 880)):
        first = tone([base, base * 1.48], 0.16, 24, 0.018)
        second = tone([base * 1.12, base * 1.68], 0.19, 27, 0.022)
        signal = np.concatenate([
            first * env(len(first), 0.006, 0.06),
            np.zeros(int(SR * 0.055)),
            second * env(len(second), 0.006, 0.08),
        ])
        save(f"alarm_squeak{variant}", signal, peak=0.48)

    rng_local = np.random.default_rng(534)
    count = int(SR * 1.0)
    noise = np.convolve(rng_local.normal(0, 1, count), np.ones(14) / 14, mode="same")
    time = np.arange(count) / SR
    flutter = 0.25 + 0.75 * np.square(np.sin(2 * np.pi * 10 * time))
    save("shake", noise * flutter * env(count, 0.025, 0.22), peak=0.30)


def gen_v35_bond_sounds():
    """Signature tier-up arpeggio and a long, warm snuggle purr."""
    notes = []
    for frequency in (523.25, 659.25, 783.99, 1046.50):
        note = tone([frequency, frequency * 1.01], 0.18, 7, 0.006)
        notes.append(note * env(len(note), 0.008, 0.09))
        notes.append(np.zeros(int(SR * 0.025)))
    save("tier_up_jingle", np.concatenate(notes), peak=0.40)

    duration = 4.2
    count = int(SR * duration)
    time = np.arange(count) / SR
    purr = (0.68 * np.sin(2 * np.pi * 104 * time)
            + 0.23 * np.sin(2 * np.pi * 208 * time)
            + 0.08 * np.sin(2 * np.pi * 312 * time))
    purr *= 0.58 + 0.42 * np.sin(2 * np.pi * 21 * time)
    save("snuggle_purr_long", purr * env(count, 0.35, 0.65), peak=0.31)


def gen_v36_training_sounds():
    """Bright training reward and a soft, plush landing thud."""
    notes = []
    for frequency in (659.25, 880.00, 1174.66):
        note = tone([frequency, frequency * 1.015], 0.13, 9, 0.005)
        notes.append(note * env(len(note), 0.005, 0.07))
        notes.append(np.zeros(int(SR * 0.018)))
    save("trick_chime", np.concatenate(notes), peak=0.38)

    duration = 0.42
    count = int(SR * duration)
    time = np.arange(count) / SR
    rng_local = np.random.default_rng(636)
    body = np.sin(2 * np.pi * (92 - 34 * time) * time)
    plush = np.convolve(rng_local.normal(0, 1, count), np.ones(42) / 42, mode="same")
    save("flop_thud", (0.75 * body + 0.25 * plush) * env(count, 0.004, 0.34), peak=0.34)


def gen_v37_hutch_sounds():
    """Soft bedding rustle and a short wooden-door creak."""
    rng_local = np.random.default_rng(737)
    count = int(SR * 0.62)
    fabric = np.convolve(rng_local.normal(0, 1, count), np.ones(26) / 26, mode="same")
    time = np.arange(count) / SR
    sweep = np.sin(np.pi * np.clip(time / 0.62, 0, 1)) ** 1.5
    save("hutch_rustle", fabric * sweep, peak=0.23)

    duration = 0.72
    count = int(SR * duration)
    time = np.arange(count) / SR
    base = tone([185, 245, 172], duration, 5.5, 0.035)
    harmonic = tone([370, 465, 330], duration, 7.0, 0.022)
    wood = np.convolve(rng_local.normal(0, 0.18, count), np.ones(54) / 54, mode="same")
    save("hutch_creak", (0.68 * base + 0.24 * harmonic + wood)
         * env(count, 0.025, 0.28), peak=0.29)


def gen_v38_family_sounds():
    """Three separately rendered baby chirps and one soft family nuzzle."""
    for variant, base in enumerate((1180, 1320, 1080), start=1):
        duration = 0.24 + variant * 0.025
        chirp = tone([base, base * 1.55, base * 1.18], duration,
                     vibrato_hz=24 + variant * 2, vibrato_amt=0.026)
        chirp += 0.16 * tone([base * 2.0, base * 2.45, base * 2.1], duration)
        save(f"baby_squeak{variant}", chirp * env(len(chirp), 0.004, 0.10), peak=0.34)

    rng_local = np.random.default_rng(838)
    duration = 1.05
    count = int(SR * duration)
    fabric = np.convolve(rng_local.normal(0, 1, count), np.ones(58) / 58, mode="same")
    purr = tone([150, 142, 158], duration, 18, 0.018)
    save("nuzzle", (0.68 * purr + 0.32 * fabric) * env(count, 0.12, 0.34), peak=0.26)


def gen_v39_fashion_sound():
    """A short, soft fabric flourish for dressing and coat changes."""
    rng_local = np.random.default_rng(939)
    duration = 0.58
    count = int(SR * duration)
    fabric = np.convolve(rng_local.normal(0, 1, count), np.ones(31) / 31, mode="same")
    chime = tone([660, 880, 1046], duration, 7, 0.008) * 0.16
    save("dress_up", (0.72 * fabric + chime) * env(count, 0.018, 0.25), peak=0.24)


def gen_v41_wild_call():
    """A soft, carrying two-note call that points players toward wild Goobys."""
    first = tone([510, 760, 650], 0.72, vibrato_hz=7.0, vibrato_amt=0.018)
    second = tone([620, 910, 720], 0.86, vibrato_hz=8.0, vibrato_amt=0.022)
    signal = np.concatenate([
        first * env(len(first), 0.06, 0.28),
        np.zeros(int(SR * 0.18)),
        second * env(len(second), 0.05, 0.38),
    ])
    save("wild_call", signal, peak=0.38)


def gen_v42_social_chirps():
    """Two short call-and-response chirps reserved for Gooby social rituals."""
    for variant, notes in enumerate(((760, 1120, 920), (880, 1260, 1040)), start=1):
        signal = tone(list(notes), 0.34 + variant * 0.03,
                      vibrato_hz=18 + variant * 2, vibrato_amt=0.022)
        save(f"chirp_social{variant}", signal * env(len(signal), 0.006, 0.16), peak=0.31)


def gen_v43_treasure_sounds():
    """Ground-sniff sweep and a soft paper-map unfurl."""
    duration = 1.45
    count = int(SR * duration)
    rng_local = np.random.default_rng(843)
    breath = np.convolve(rng_local.normal(0, 1, count), np.ones(38) / 38, mode="same")
    nose = tone([310, 470, 280, 520, 340], duration, 9.0, 0.025)
    save("sniff_long", (0.55 * breath + 0.45 * nose) * env(count, 0.04, 0.32), peak=0.26)

    duration = 0.82
    count = int(SR * duration)
    paper = np.convolve(rng_local.normal(0, 1, count), np.ones(19) / 19, mode="same")
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * 15 * np.arange(count) / SR)
    save("map_rustle", paper * flutter * env(count, 0.015, 0.25), peak=0.22)


if __name__ == "__main__":
    print("Synthetisiere Gooby-Sounds…")
    gen_squeak()
    gen_purr()
    gen_boing()
    gen_plop()
    gen_munch()
    gen_snore()
    gen_ambient()
    gen_sad_whimper()
    gen_yawn_and_sniff()
    gen_v32_soundscape()
    gen_v33_needs_sounds()
    gen_v34_awareness_sounds()
    gen_v35_bond_sounds()
    gen_v36_training_sounds()
    gen_v37_hutch_sounds()
    gen_v38_family_sounds()
    gen_v39_fashion_sound()
    gen_v41_wild_call()
    gen_v42_social_chirps()
    gen_v43_treasure_sounds()
    print("Fertig!")
