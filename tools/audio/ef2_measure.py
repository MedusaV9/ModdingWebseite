#!/usr/bin/env python3
"""ef2_measure.py — EF-2-Nachmessung des EVAL-1-Audio-Reports.

Identische Metriken wie EVAL1/analyze_audio.py (Peak/RMS/Loudness dBFS,
effektiver Playback-Pegel nach Trim, Spektral-Zentroid, Energie >4 kHz,
Attack, End-Klick, Loop-Naht) PLUS:
  - Ranch-Registry-Einträge (RANCH_MUSIK_DIR + "...") werden korrekt
    ihrer Track-Id zugeordnet (EVAL1 führte sie als unmapped).
  - loop_offset aus der .import-Datei; seam_loop_db = Pegel-Differenz
    zwischen Dateiende und Loop-Punkt (die Naht, die man WIRKLICH hört,
    wenn loop_offset gesetzt ist). Ohne loop_offset == seam_db (Anfang).

Aufruf: python3 tools/audio/ef2_measure.py [--out DIR] [--csv NAME]
"""

import argparse
import csv
import json
import math
import os
import re
import subprocess
import sys

import numpy as np

ROOT = "/workspace/GOOBY-GODOT"
SR = 48000


def decode(path):
    cmd = [
        "ffmpeg", "-v", "error", "-i", path,
        "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "1", "-ar", str(SR), "-",
    ]
    raw = subprocess.run(cmd, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def dbfs(x):
    if x <= 0:
        return -120.0
    return 20.0 * math.log10(x)


def loop_offset_for(path):
    imp = path + ".import"
    if not os.path.exists(imp):
        return 0.0
    m = re.search(r"^loop_offset=([\d.]+)", open(imp).read(), re.M)
    return float(m.group(1)) if m else 0.0


def analyze(path):
    x = decode(path)
    if x.size < 16:
        return None
    dur = x.size / SR
    peak = dbfs(float(np.max(np.abs(x))))
    rms = dbfs(float(np.sqrt(np.mean(x ** 2))))
    win = int(0.4 * SR)
    if x.size >= win:
        n = x.size // win
        frames = x[: n * win].reshape(n, win)
        fr = np.sqrt(np.mean(frames ** 2, axis=1))
        active = fr[fr > 10 ** (-60 / 20)]
        loud = dbfs(float(np.sqrt(np.mean(active ** 2)))) if active.size else rms
    else:
        loud = rms
    seg = x[: min(x.size, 2 ** 20)]
    spec = np.abs(np.fft.rfft(seg * np.hanning(seg.size))) ** 2
    freqs = np.fft.rfftfreq(seg.size, 1 / SR)
    total = float(np.sum(spec)) or 1e-12
    centroid = float(np.sum(freqs * spec) / total)
    hi = float(np.sum(spec[freqs > 4000]) / total)
    lo = float(np.sum(spec[freqs < 200]) / total)
    absx = np.abs(x)
    pk = float(np.max(absx))
    attack_ms = float(np.argmax(absx >= 0.9 * pk)) / SR * 1000.0
    tail = x[-int(0.005 * SR):]
    end_db = dbfs(float(np.sqrt(np.mean(tail ** 2))))
    head = x[: int(0.05 * SR)]
    tail50 = x[-int(0.05 * SR):]
    seam = abs(dbfs(float(np.sqrt(np.mean(head ** 2)) + 1e-12)) -
               dbfs(float(np.sqrt(np.mean(tail50 ** 2)) + 1e-12)))
    # Loop-bewusste Naht: Ende vs. 50 ms AB dem Loop-Punkt.
    off = loop_offset_for(path)
    i0 = int(off * SR)
    if 0 < i0 < x.size - int(0.05 * SR):
        at_loop = x[i0: i0 + int(0.05 * SR)]
        seam_loop = abs(dbfs(float(np.sqrt(np.mean(at_loop ** 2)) + 1e-12)) -
                        dbfs(float(np.sqrt(np.mean(tail50 ** 2)) + 1e-12)))
    else:
        seam_loop = seam
    return {
        "dur_s": round(dur, 3), "peak_db": round(peak, 1), "rms_db": round(rms, 1),
        "loud_db": round(loud, 1), "centroid_hz": round(centroid),
        "hi4k_pct": round(hi * 100, 1), "lo200_pct": round(lo * 100, 1),
        "attack_ms": round(attack_ms, 1), "end_db": round(end_db, 1),
        "seam_db": round(seam, 1), "loop_offset_s": round(off, 3),
        "seam_loop_db": round(seam_loop, 1),
    }


def parse_sfx_map():
    """id -> (file, volume_db) aus sfx_map.gd + feel_sfx.gd."""
    out = {}
    for f, base in [("scripts/audio/sfx_map.gd", "assets/audio/sfx"),
                    ("scripts/minigames/feel/feel_sfx.gd", "assets/audio/sfx/game")]:
        src = open(os.path.join(ROOT, f)).read()
        pat = r'"([a-z_0-9]+)":\s*\n?\s*\{"file":\s*([^,}]+)(?:,\s*"volume_db":\s*(-?[\d.]+))?'
        for m in re.finditer(pat, src):
            sid, fexpr, vol = m.group(1), m.group(2).strip(), m.group(3)
            if fexpr.startswith("RANCH_DIR"):
                fpath = ("assets/ranch/audio/sfx/"
                         + fexpr.split("+")[-1].strip().strip('"').lstrip("/"))
            else:
                fpath = base + "/" + fexpr.strip('"')
            out[sid] = (fpath, float(vol) if vol else 0.0)
    return out


def parse_music_registry():
    """track_id -> (relpath_vom_projekt, trim_db). Inkl. Ranch-Einträge."""
    src = open(os.path.join(ROOT, "scripts/audio/music_registry.gd")).read()
    out = {}
    pat = (r'"([\w-]+)":\s*\n\s*\{[^}]*?"file":\s*(RANCH_MUSIK_DIR\s*\+\s*)?'
           r'"([^"]+)"[^}]*?"gain_trim":\s*([\d.]+)')
    for m in re.finditer(pat, src, re.S):
        tid, ranch, f, g = m.group(1), m.group(2), m.group(3), float(m.group(4))
        if ranch:
            rel = "assets/ranch/audio/musik/" + f.lstrip("/")
        else:
            rel = "assets/music/" + f
        out[tid] = (rel, 20 * math.log10(max(g, 1e-6)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/gooby-godot/artifacts/EF2")
    ap.add_argument("--csv", default="audio_analysis.csv")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rows = []
    sfx = parse_sfx_map()
    music = parse_music_registry()
    seen = set()
    for sid, (f, vol) in sorted(sfx.items()):
        p = os.path.join(ROOT, f)
        if not os.path.exists(p):
            rows.append({"id": sid, "file": f, "missing": True, "kind": "sfx"})
            continue
        a = analyze(p)
        a.update({"id": sid, "file": f, "trim_db": vol,
                  "eff_loud_db": round(a["loud_db"] + vol, 1),
                  "eff_peak_db": round(a["peak_db"] + vol, 1), "kind": "sfx"})
        rows.append(a)
        seen.add(os.path.normpath(p))
    for tid, (f, trim) in sorted(music.items()):
        p = os.path.join(ROOT, f)
        if not os.path.exists(p):
            rows.append({"id": tid, "file": f, "missing": True, "kind": "music"})
            continue
        a = analyze(p)
        a.update({"id": tid, "file": f, "trim_db": round(trim, 1),
                  "eff_loud_db": round(a["loud_db"] + trim, 1),
                  "eff_peak_db": round(a["peak_db"] + trim, 1), "kind": "music"})
        rows.append(a)
        seen.add(os.path.normpath(p))
    for base in ["assets/audio", "assets/music", "assets/ranch/audio"]:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, base)):
            for fn in sorted(files):
                if not fn.endswith((".ogg", ".wav")):
                    continue
                p = os.path.normpath(os.path.join(dirpath, fn))
                if p in seen:
                    continue
                a = analyze(p)
                if a is None:
                    continue
                a.update({"id": "(unmapped)", "file": os.path.relpath(p, ROOT),
                          "trim_db": 0.0, "eff_loud_db": a["loud_db"],
                          "eff_peak_db": a["peak_db"], "kind": "unmapped"})
                rows.append(a)
    keys = ["kind", "id", "file", "dur_s", "peak_db", "rms_db", "loud_db",
            "trim_db", "eff_loud_db", "eff_peak_db", "centroid_hz", "hi4k_pct",
            "lo200_pct", "attack_ms", "end_db", "seam_db", "loop_offset_s",
            "seam_loop_db", "missing"]
    out_csv = os.path.join(args.out, args.csv)
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in keys})
    print(json.dumps({"rows": len(rows), "csv": out_csv}))


if __name__ == "__main__":
    sys.exit(main())
