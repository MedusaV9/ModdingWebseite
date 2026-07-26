"""Feine Tempo-/Phasen-Schätzung für den Trailer-Schnitt.

Sucht BPM in 0,01er-Schritten um 100 und die Grid-Phase, die den
Spektralfluss maximiert; gibt außerdem starke Downbeat-Kandidaten aus.
"""
import subprocess
import sys

import numpy as np

SR = 22050
HOP = 256


def load_mono(path: str) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR),
         "-f", "f32le", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def onset_envelope(y: np.ndarray, n_fft: int = 1024):
    win = np.hanning(n_fft)
    n = (len(y) - n_fft) // HOP
    frames = np.lib.stride_tricks.as_strided(
        y, shape=(n, n_fft), strides=(y.strides[0] * HOP, y.strides[0]))
    mag = np.abs(np.fft.rfft(frames * win, axis=1))
    flux = np.maximum(0.0, np.diff(mag, axis=0)).sum(axis=1)
    return flux, SR / HOP


def main(path: str) -> None:
    y = load_mono(path)
    flux, fps = onset_envelope(y)
    dauer = len(flux) / fps

    best = (-1e18, 0.0, 0.0)
    for bpm100 in range(9800, 10200):
        bpm = bpm100 / 100.0
        beat = 60.0 / bpm
        lag = beat * fps
        # Phase in 24 Stufen testen
        for ph24 in range(24):
            phase = ph24 / 24.0 * beat
            idx = np.arange(phase * fps, len(flux), lag).astype(int)
            idx = idx[idx < len(flux)]
            score = flux[idx].sum() / len(idx)
            if score > best[0]:
                best = (score, bpm, phase)
    _, bpm, phase = best
    print(f"BPM={bpm:.2f}  Beat={60.0 / bpm:.5f}s  Phase={phase:.3f}s  Länge={dauer:.1f}s")

    # Starke Beats am Anfang (Downbeat-Kandidaten für den Schnitt-Start).
    beat = 60.0 / bpm
    zeiten = np.arange(phase, min(dauer, 30.0), beat)
    staerken = [
        flux[int(z * fps)] if int(z * fps) < len(flux) else 0.0 for z in zeiten
    ]
    order = np.argsort(staerken)[::-1][:12]
    kandidaten = sorted(zeiten[i] for i in order)
    print("Starke Beats (erste 30 s):", [round(z, 3) for z in kandidaten])


if __name__ == "__main__":
    main(sys.argv[1])
