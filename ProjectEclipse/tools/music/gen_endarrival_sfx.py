#!/usr/bin/env python3
"""Deterministic offline synthesizer for the F-077 V2 End-arrival SFX layer (WP-G).

Generates the six event one-shots the V2 cinematic layers over the shipped
vanilla/eclipse mix (docs/plans_v3/feedback3/PLAN-F077-end-erscheinen-cutscene.md §3):

  end_arrival_subboom   ~1.6 s  40 Hz heartbeat sub-boom (omen pulse + erupt hit)
  end_arrival_riser     ~6.0 s  filtered-noise + detuned sweep riser, ends ON the erupt
  end_arrival_choir     ~6.0 s  detuned minor pad ("choir"), re-fired through beat 3
  end_arrival_snap_a/b/c ~0.45 s chorus-flower snap ticks (debris landing stamps)
  end_arrival_drone     ~6.0 s  deep end-ambience tail under the reveal

House conventions (match assets/eclipse/sounds/event/*.ogg — e.g. emerge.ogg):
mono, 44.1 kHz, OGG Vorbis; loudness normalized to ≈ −14 LUFS via ffmpeg loudnorm.
Fully deterministic (fixed numpy seed) — re-running produces the same audio content.

Usage:
  python3 tools/music/gen_endarrival_sfx.py            # writes into assets tree
  python3 tools/music/gen_endarrival_sfx.py --out DIR  # write elsewhere (listening)

Requires: numpy + ffmpeg (both present in the dev environment).
"""
import argparse
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
EVENT_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/sounds/event"

SR = 44100
TARGET_LUFS = -14.0
SEED = 77077  # F-077


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def fade(sig: np.ndarray, in_s: float = 0.004, out_s: float = 0.05) -> np.ndarray:
    """Linear anti-click edges."""
    sig = sig.copy()
    n_in = max(1, int(in_s * SR))
    n_out = max(1, int(out_s * SR))
    sig[:n_in] *= np.linspace(0.0, 1.0, n_in)
    sig[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return sig


def soft_clip(sig: np.ndarray, drive: float = 1.0) -> np.ndarray:
    """tanh saturation — glues partials and tames peaks musically."""
    return np.tanh(sig * drive) / np.tanh(drive)


def lowpass(sig: np.ndarray, cutoff_hz: np.ndarray | float) -> np.ndarray:
    """One-pole lowpass with optionally time-varying cutoff (cheap, stable)."""
    cutoff = np.broadcast_to(np.asarray(cutoff_hz, dtype=np.float64), sig.shape)
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff / SR)
    out = np.empty_like(sig)
    acc = 0.0
    for i in range(sig.size):  # small files; clarity over vectorization
        acc += alpha[i] * (sig[i] - acc)
        out[i] = acc
    return out


def synth_subboom() -> np.ndarray:
    """40→28 Hz pitch-dropping sine boom with a soft click transient."""
    t = t_axis(1.6)
    freq = 40.0 * np.exp(-t * 0.9) + 28.0
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * np.exp(-t * 2.6)
    # Second harmonic whisper so small speakers still hear the hit.
    body += 0.22 * np.sin(2.0 * phase) * np.exp(-t * 4.0)
    rng = np.random.default_rng(SEED + 1)
    click = rng.standard_normal(t.size) * np.exp(-t * 220.0) * 0.25
    return fade(soft_clip(body + click, 1.6), out_s=0.25)


def synth_riser() -> np.ndarray:
    """6 s riser: swept filtered noise + two detuned rising partials; ends hard."""
    t = t_axis(6.0)
    rise = (t / t[-1]) ** 1.6
    rng = np.random.default_rng(SEED + 2)
    noise = lowpass(rng.standard_normal(t.size), 120.0 + 5200.0 * rise) * (0.12 + 0.55 * rise)
    freq = 80.0 * (2.0 ** (3.0 * rise))            # 80 → 640 Hz over three octaves
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    detune = 2.0 * np.pi * np.cumsum(freq * 1.011) / SR
    tone = (np.sin(phase) + 0.8 * np.sin(detune)) * (0.05 + 0.30 * rise)
    # Accelerating tremolo — the heartbeat handing over to the eruption.
    trem = 0.75 + 0.25 * np.sin(2.0 * np.pi * (1.2 + 4.0 * rise) * t)
    sig = (noise + tone) * trem
    return fade(soft_clip(sig, 1.3), out_s=0.02)  # hard end: the erupt beat lands here


def synth_choir() -> np.ndarray:
    """Detuned minor-chord pad with slow vibrato — the beat-3 'choir' bed."""
    t = t_axis(6.0)
    sig = np.zeros_like(t)
    rng = np.random.default_rng(SEED + 3)
    # A minor-ish stack rooted low: A2 110, C4 261.63, E3 164.81, A3 220.
    for base, gain in ((110.0, 0.5), (164.81, 0.38), (220.0, 0.34), (261.63, 0.22)):
        for det in (-0.6, 0.0, 0.7):  # three detuned voices per note = chorus width
            vib = 1.0 + 0.004 * np.sin(2.0 * np.pi * (0.14 + rng.uniform(0, 0.1)) * t
                                       + rng.uniform(0, 6.28))
            phase = 2.0 * np.pi * np.cumsum(base * (1.0 + det / 600.0) * vib) / SR
            sig += gain / 3.0 * np.sin(phase)
    breath = lowpass(rng.standard_normal(t.size), 900.0) * 0.05
    env = np.minimum(t / 1.4, 1.0) * np.minimum((t[-1] - t) / 1.6, 1.0).clip(0.0, 1.0)
    return fade(soft_clip((sig + breath) * env, 1.2), in_s=0.05, out_s=0.4)


def synth_snap(variant: int) -> np.ndarray:
    """Chorus-flower snap tick: FM blip + noise tick; three pitch variants."""
    t = t_axis(0.45)
    base = (620.0, 740.0, 520.0)[variant]
    rng = np.random.default_rng(SEED + 10 + variant)
    mod = np.sin(2.0 * np.pi * base * 2.7 * t) * 5.0 * np.exp(-t * 40.0)
    blip = np.sin(2.0 * np.pi * base * t + mod) * np.exp(-t * 22.0)
    tick = rng.standard_normal(t.size) * np.exp(-t * 300.0) * 0.5
    thump = np.sin(2.0 * np.pi * 90.0 * t) * np.exp(-t * 30.0) * 0.4
    return fade(soft_clip(blip + tick + thump, 1.5), out_s=0.12)


def synth_drone() -> np.ndarray:
    """Deep end-ambience: 55 Hz root + beating fifth + slow shimmer partials."""
    t = t_axis(6.0)
    rng = np.random.default_rng(SEED + 4)
    sig = 0.55 * np.sin(2.0 * np.pi * 55.0 * t)
    sig += 0.30 * np.sin(2.0 * np.pi * 82.6 * t)          # ~fifth, slightly flat: beats
    sig += 0.18 * np.sin(2.0 * np.pi * 110.6 * t + 1.1)   # octave shimmer
    # Sparse high shimmer — the void-wisp register.
    shimmer = np.sin(2.0 * np.pi * 1318.5 * t) * (0.03 + 0.02 * np.sin(2.0 * np.pi * 0.21 * t))
    shimmer *= (0.5 + 0.5 * np.sin(2.0 * np.pi * 0.09 * t + 2.0))
    breath = lowpass(rng.standard_normal(t.size), 300.0) * 0.06
    env = np.minimum(t / 1.0, 1.0) * np.minimum((t[-1] - t) / 2.2, 1.0).clip(0.0, 1.0)
    return fade(soft_clip((sig + shimmer + breath) * env, 1.2), in_s=0.05, out_s=0.6)


TRACKS = {
    "end_arrival_subboom": synth_subboom,
    "end_arrival_riser": synth_riser,
    "end_arrival_choir": synth_choir,
    "end_arrival_snap_a": lambda: synth_snap(0),
    "end_arrival_snap_b": lambda: synth_snap(1),
    "end_arrival_snap_c": lambda: synth_snap(2),
    "end_arrival_drone": synth_drone,
}


def write_wav(path: Path, sig: np.ndarray) -> None:
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig / peak * 0.891  # −1 dBFS headroom pre-loudnorm
    pcm = (sig * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack(f"<{pcm.size}h", *pcm))


def encode(wav: Path, ogg: Path) -> None:
    """Loudness-normalize (~−14 LUFS) and encode mono 44.1 kHz OGG Vorbis."""
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", str(wav),
         "-af", f"loudnorm=I={TARGET_LUFS}:TP=-1.5:LRA=11",
         "-ar", str(SR), "-ac", "1", "-c:a", "libvorbis", "-q:a", "4",
         str(ogg)],
        check=True)


def verify(ogg: Path) -> None:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels",
         "-of", "csv=p=0", str(ogg)],
        check=True, capture_output=True, text=True).stdout.strip()
    codec, rate, channels = out.split(",")[:3]
    if codec != "vorbis" or int(rate) != SR or int(channels) != 1:
        raise SystemExit(f"{ogg}: unexpected format {out} (want vorbis/{SR}/mono)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=EVENT_DIR)
    args = parser.parse_args()
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found on PATH", file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, synth in TRACKS.items():
            wav = Path(tmp) / f"{name}.wav"
            ogg = args.out / f"{name}.ogg"
            write_wav(wav, synth().astype(np.float64))
            encode(wav, ogg)
            verify(ogg)
            print(f"WROTE {ogg} ({ogg.stat().st_size} B)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
