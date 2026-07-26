"""Kleiner BPM-Schätzer (Spektralfluss + Autokorrelation, nur numpy)."""
import subprocess
import sys

import numpy as np


def load_mono(path: str, sr: int = 22050) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr),
         "-f", "f32le", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def onset_envelope(y: np.ndarray, sr: int = 22050, hop: int = 256, n_fft: int = 1024):
    win = np.hanning(n_fft)
    n = (len(y) - n_fft) // hop
    frames = np.lib.stride_tricks.as_strided(
        y, shape=(n, n_fft), strides=(y.strides[0] * hop, y.strides[0]))
    mag = np.abs(np.fft.rfft(frames * win, axis=1))
    flux = np.maximum(0.0, np.diff(mag, axis=0)).sum(axis=1)
    flux -= flux.mean()
    return flux, sr / hop


def estimate_bpm(path: str):
    y = load_mono(path)
    # nur die ersten 90 s reichen
    y = y[: 22050 * 90]
    flux, fps = onset_envelope(y)
    ac = np.correlate(flux, flux, mode="full")[len(flux) - 1:]
    best = (0.0, 0.0)
    for bpm10 in range(600, 2000):
        bpm = bpm10 / 10.0
        lag = fps * 60.0 / bpm
        idx = int(round(lag))
        if idx < 1 or idx * 2 >= len(ac):
            continue
        score = ac[idx] + 0.5 * ac[idx * 2]
        if score > best[0]:
            best = (score, bpm)
    return best[1]


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(p, "→", round(estimate_bpm(p), 1), "BPM")
