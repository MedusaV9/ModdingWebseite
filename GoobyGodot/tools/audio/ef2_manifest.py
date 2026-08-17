#!/usr/bin/env python3
"""ef2_manifest.py — misst alle gemappten Audio-Dateien (MusicRegistry,
SfxMap, Babble-WAVs) und schreibt das Test-Fixture
GOOBY-GODOT/tests/fixtures/ef2_audio_levels.json.

Das Fixture ist der Mess-Kontrakt fuer tests/unit/test_ef2_audio_levels.gd:
pro Datei sha256 (Drift-Erkennung), Loudness (EVAL1-Metrik: gated 400-ms-RMS
dBFS @48k mono), Peak dBFS, Zentroid, >4-kHz-Anteil sowie fuer Kontext-Tracks
loop_offset + Naht-Pegeldifferenz. Nach JEDER Audio-Aenderung neu erzeugen:
  python3 tools/audio/ef2_manifest.py
"""

import hashlib
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "/workspace/GOOBY-GODOT"
FIXTURE = os.path.join(ROOT, "tests/fixtures/ef2_audio_levels.json")

spec = importlib.util.spec_from_file_location(
    "ef2_measure", os.path.join(HERE, "ef2_measure.py"))
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def entry(path, rel):
    a = measure.analyze(path)
    return {
        "file": rel,
        "sha256": sha256(path),
        "dur_s": a["dur_s"],
        "loud_db": a["loud_db"],
        "peak_db": a["peak_db"],
        "centroid_hz": a["centroid_hz"],
        "hi4k_pct": a["hi4k_pct"],
        "end_db": a["end_db"],
        "loop_offset_s": a["loop_offset_s"],
        "seam_loop_db": a["seam_loop_db"],
    }


def main():
    music = {}
    for tid, (rel, _trim) in sorted(measure.parse_music_registry().items()):
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            print("WARN: fehlt %s" % rel)
            continue
        music[tid] = entry(p, rel)
    sfx = {}
    src = open(os.path.join(ROOT, "scripts/audio/sfx_map.gd")).read()
    pat = (r'"([a-z_0-9]+)":\s*\n?\s*\{"file":\s*([^,}]+?)'
           r'(?:,\s*"volume_db":\s*(-?[\d.]+))?[,}]')
    for m in re.finditer(pat, src):
        sid, fexpr = m.group(1), m.group(2).strip()
        if fexpr.startswith("RANCH_DIR"):
            rel = ("assets/ranch/audio/sfx/"
                   + fexpr.split("+")[-1].strip().strip('"').lstrip("/"))
        else:
            rel = "assets/audio/sfx/" + fexpr.strip('"')
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            print("WARN: fehlt %s (%s)" % (rel, sid))
            continue
        sfx[sid] = entry(p, rel)
    voice = {}
    voice_dir = os.path.join(ROOT, "assets/audio/voice")
    for fn in sorted(os.listdir(voice_dir)):
        if fn.endswith(".wav"):
            voice[fn] = entry(os.path.join(voice_dir, fn), "assets/audio/voice/" + fn)
    out = {
        "_hinweis": ("Mess-Kontrakt EF-2 (EVAL-1 S1-S4). Nach Audio-"
                     "Aenderungen neu erzeugen: python3 tools/audio/"
                     "ef2_manifest.py — Metrik: gated 400-ms-RMS dBFS "
                     "@48k mono, Peak dBFS."),
        "music": music,
        "sfx": sfx,
        "voice": voice,
    }
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
    print(json.dumps({"music": len(music), "sfx": len(sfx),
                      "voice": len(voice), "fixture": FIXTURE}))


if __name__ == "__main__":
    sys.exit(main())
