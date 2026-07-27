#!/usr/bin/env python3
"""ef2_seam_demo.py — hoerbare Loop-Naht-Probe + Naht-Messung.

Baut pro Track ein OGG aus (letzte N s der Datei) + (N s ab loop_offset) —
genau das, was der Spieler beim Loop-Umbruch hoert — und misst:
  - seam_rms_db:  |RMS(50 ms vor EOF) - RMS(50 ms ab Loop-Punkt)|
  - seam_step:    Sample-Sprung an der Naht (linear, 0 = stetig)

Aufruf: python3 tools/audio/ef2_seam_demo.py <ogg> [<ogg> ...] [--secs 4]
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys

import numpy as np

OUT = "/tmp/gooby-godot/artifacts/EF2"
SR = 44100


def decode(path, ch=2):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le",
         "-acodec", "pcm_f32le", "-ac", str(ch), "-ar", str(SR), "-"],
        capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64).reshape(-1, ch)


def db(x):
    return 20.0 * math.log10(max(x, 1e-12))


def loop_offset_for(path):
    imp = path + ".import"
    if not os.path.exists(imp):
        return 0.0
    m = re.search(r"^loop_offset=([\d.]+)", open(imp).read(), re.M)
    return float(m.group(1)) if m else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--secs", type=float, default=4.0)
    ap.add_argument("--suffix", default="")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    results = []
    for path in args.files:
        x = decode(path)
        off = loop_offset_for(path)
        i0 = int(off * SR)
        n = int(args.secs * SR)
        tail = x[-n:]
        head = x[i0: i0 + n]
        joined = np.concatenate([tail, head])
        name = os.path.basename(path).replace(".ogg", "")
        out_path = os.path.join(OUT, "seam_%s%s.ogg" % (name, args.suffix))
        pcm = joined.astype(np.float32).tobytes()
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR),
             "-ac", "2", "-i", "-", "-c:a", "libvorbis", "-q:a", "6", out_path],
            input=pcm, check=True)
        w = int(0.05 * SR)
        rms_tail = db(float(np.sqrt(np.mean(x[-w:] ** 2))))
        rms_head = db(float(np.sqrt(np.mean(head[:w] ** 2))))
        step = float(np.max(np.abs(x[-1] - head[0]))) if head.size else 1.0
        results.append({
            "file": os.path.relpath(path), "loop_offset": off,
            "seam_rms_db": round(abs(rms_tail - rms_head), 2),
            "seam_step_lin": round(step, 4), "demo": out_path,
        })
    print(json.dumps(results, indent=1))


if __name__ == "__main__":
    sys.exit(main())
