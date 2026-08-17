#!/usr/bin/env python3
"""ef2_apply_registry.py — traegt die Ergebnisse von ef2_music_master.py in
music_registry.gd ein: gain_trim (1.0 fuer normalisierte Dateien, gerechnete
Werte fuer die unangetasteten Ranch-Dateien) und duration_sec (Loop-Schnitt
kuerzt Kontext-Tracks)."""

import json
import re
import sys

REG = "/workspace/GOOBY-GODOT/scripts/audio/music_registry.gd"
REPORT = "/tmp/gooby-godot/artifacts/EF2/music_master_report.json"


def patch_block(src, tid, gain_trim, dur=None):
    pat = re.compile(r'("%s":\s*\n\s*\{.*?\n\s*\},)' % re.escape(tid), re.S)
    m = pat.search(src)
    if not m:
        print("WARN: Block fehlt fuer %s" % tid)
        return src
    block = m.group(1)
    new = re.sub(r'"gain_trim":\s*[\d.]+', '"gain_trim": %s' % gain_trim, block)
    if dur is not None:
        new = re.sub(r'"duration_sec":\s*[\d.]+',
                     '"duration_sec": %.1f' % dur, new)
    return src[: m.start(1)] + new + src[m.end(1):]


def main():
    src = open(REG).read()
    report = json.load(open(REPORT))
    for e in report:
        tid = e["id"]
        trim = e["new_gain_trim"]
        trim_s = "1.0" if trim == 1.0 else ("%.3f" % trim)
        dur = e.get("dur_after")
        src = patch_block(src, tid, trim_s, dur)
    open(REG, "w").write(src)
    print("music_registry.gd aktualisiert (%d Tracks)" % len(report))


if __name__ == "__main__":
    sys.exit(main())
