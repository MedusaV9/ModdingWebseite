#!/usr/bin/env python3
"""ef2_compare.py — Vorher/Nachher-Gegenueberstellung (EVAL-1 → EF-2).

Joint die EVAL1-Basismessung mit der EF2-Nachmessung auf der id-Spalte und
schreibt /tmp/gooby-godot/artifacts/EF2/messvergleich.md: Kennzahlen-Block
(Clipping-Zaehler, Mediane, Naht-Extreme, Voice-Pegel) plus Detailtabellen
fuer die im Pruefbericht genannten Problemfaelle.
"""

import csv
import statistics
import sys

BEFORE = "/tmp/gooby-godot/artifacts/EVAL1/audio_analysis.csv"
AFTER = "/tmp/gooby-godot/artifacts/EF2/audio_analysis_after.csv"
OUT = "/tmp/gooby-godot/artifacts/EF2/messvergleich.md"

MUSIC_BUS_DB = -13.0


def load(path):
    rows = {}
    with open(path) as fh:
        for r in csv.DictReader(fh):
            if r.get("missing"):
                continue
            key = (r["kind"], r["id"], r["file"])
            rows[key] = {k: (float(v) if _num(v) else v) for k, v in r.items()}
    return rows


def _num(v):
    try:
        float(v)
        return True
    except (TypeError, ValueError):
        return False


def by_id(rows, kind):
    out = {}
    for (k, i, _f), r in rows.items():
        if k == kind and i != "(unmapped)":
            out[i] = r
    return out


def med(vals):
    return statistics.median(vals) if vals else float("nan")


def main():
    before, after = load(BEFORE), load(AFTER)
    mb, ma = by_id(before, "music"), by_id(after, "music")
    sb, sa = by_id(before, "sfx"), by_id(after, "sfx")
    lines = []
    a = lines.append
    a("# EF-2 Messvergleich (EVAL-1 Basis -> nach Umsetzung)")
    a("")
    a("Metrik identisch zu EVAL1/analyze_audio.py: Peak/Loudness dBFS im")
    a("48-kHz-Mono-Decode, eff_* = nach gain_trim/volume_db. Musik-Playback")
    a("zusaetzlich %+.0f dB Music-Bus-Offset (audio_director.gd)." % MUSIC_BUS_DB)
    a("")
    a("## Kennzahlen")
    a("")
    a("| Kennzahl | vorher | nachher |")
    a("|---|---|---|")
    clip_b = sum(1 for r in mb.values() if r["eff_peak_db"] > 0.0)
    clip_a = sum(1 for r in ma.values() if r["eff_peak_db"] > 0.0)
    over1_b = sum(1 for r in mb.values() if r["eff_peak_db"] > -1.0)
    over1_a = sum(1 for r in ma.values() if r["eff_peak_db"] > -1.0)
    a("| Musik-Tracks eff. Peak > 0 dBFS | **%d** (max %+.1f) | **%d** |"
      % (clip_b, max(r["eff_peak_db"] for r in mb.values()), clip_a))
    a("| Musik-Tracks eff. Peak > -1 dBFS | %d | **%d** (max %+.1f) |"
      % (over1_b, over1_a, max(r["eff_peak_db"] for r in ma.values())))
    med_mb = med([r["eff_loud_db"] for r in mb.values()])
    med_ma = med([r["eff_loud_db"] for r in ma.values()])
    a("| Musik eff. Loudness Median (Datei) | %.1f dBFS | %.1f dBFS |"
      % (med_mb, med_ma))
    spread_b = (max(r["eff_loud_db"] for r in mb.values())
                - min(r["eff_loud_db"] for r in mb.values()))
    spread_a = (max(r["eff_loud_db"] for r in ma.values())
                - min(r["eff_loud_db"] for r in ma.values()))
    a("| Musik Loudness-Spanne (max-min) | %.1f dB | %.1f dB |" % (spread_b, spread_a))
    med_sb = med([r["eff_loud_db"] for r in sb.values()])
    med_sa = med([r["eff_loud_db"] for r in sa.values()])
    a("| SFX eff. Loudness Median | %.1f dBFS | %.1f dBFS |" % (med_sb, med_sa))
    a("| Musik-Playback vs. SFX (AC-Soll: 6-10 dB drunter) | %.1f dB DRUEBER | "
      "**%.1f dB drunter** |"
      % (med_mb - med_sb, med_sa - (med_ma + MUSIC_BUS_DB)))
    ctx_a = {i: r for i, r in ma.items() if r.get("loop_offset_s", 0) > 0}
    seam_b = [(r["seam_db"], i) for i, r in mb.items() if i in ctx_a]
    seam_a = [(r["seam_loop_db"], i) for i, r in ctx_a.items()]
    a("| Loop-Naht Kontext-Tracks (max) | %.1f dB (%s) | **%.1f dB** (%s) |"
      % (max(seam_b)[0], max(seam_b)[1], max(seam_a)[0], max(seam_a)[1]))
    a("| Loop-Naht Kontext-Tracks (Median) | %.1f dB | %.1f dB |"
      % (med([s for s, _ in seam_b]), med([s for s, _ in seam_a])))
    vb = [r for (k, i, f), r in before.items()
          if "assets/audio/voice/" in str(f) and str(f).endswith(".wav")]
    va = [r for (k, i, f), r in after.items()
          if "assets/audio/voice/" in str(f) and str(f).endswith(".wav")]
    a("| Voice-Babble Loudness (min..max) | %.1f..%.1f dBFS | %.1f..%.1f dBFS |"
      % (min(r["loud_db"] for r in vb), max(r["loud_db"] for r in vb),
         min(r["loud_db"] for r in va), max(r["loud_db"] for r in va)))
    a("| Voice-Bus-Routing (gooby_voice.gd) | Master (Regler wirkungslos) | "
      "Voice-Bus + -6 dB Trim |")
    a("| gvz_collect Zentroid / >4 kHz | %.0f Hz / %.0f %% | %.0f Hz / %.0f %% |"
      % (sb["gvz_collect"]["centroid_hz"], sb["gvz_collect"]["hi4k_pct"],
         sa["gvz_collect"]["centroid_hz"], sa["gvz_collect"]["hi4k_pct"]))
    a("| mg_win Zentroid / >4 kHz | %.0f Hz / %.0f %% | %.0f Hz / %.0f %% |"
      % (sb["mg_win"]["centroid_hz"], sb["mg_win"]["hi4k_pct"],
         sa["mg_win"]["centroid_hz"], sa["mg_win"]["hi4k_pct"]))
    a("| game_hit Restpegel letzte 5 ms | %.1f dBFS (Klick) | %.1f dBFS |"
      % (sb["game_hit"]["end_db"], sa["game_hit"]["end_db"]))
    a("| stumme Pflege-/Interaktions-Ids | 0 gemappt | %d neu (care_*, "
      "gvz_collect-Ersatz, mg_win, pet/step/nom, travel_whoosh_*) |"
      % sum(1 for i in sa if i in (
          "care_wasser", "care_buersten", "care_spuelung", "care_erfolg",
          "gvz_collect", "mg_win", "pet_squish", "step_tap", "nom_nom",
          "travel_whoosh_auf", "travel_whoosh_zu")))
    a("")
    a("## Die 5 schlimmsten Clipper (Pruefbericht S1)")
    a("")
    a("| Track | eff. Peak vorher | eff. Peak nachher | eff. Loudness v->n |")
    a("|---|---|---|---|")
    worst = sorted(mb, key=lambda i: -mb[i]["eff_peak_db"])[:5]
    for i in worst:
        a("| %s | %+.1f dBFS | %+.1f dBFS | %.1f -> %.1f dBFS |"
          % (i, mb[i]["eff_peak_db"], ma[i]["eff_peak_db"],
             mb[i]["eff_loud_db"], ma[i]["eff_loud_db"]))
    a("")
    a("## Die 5 schlimmsten Loop-Naehte (Pruefbericht S2)")
    a("")
    a("| Track | Naht vorher (roh) | Naht nachher (am Loop-Punkt) | loop_offset |")
    a("|---|---|---|---|")
    for i in [w[1] for w in sorted(seam_b, reverse=True)[:5]]:
        a("| %s | %.1f dB | %.1f dB | %.2f s |"
          % (i, mb[i]["seam_db"], ma[i]["seam_loop_db"], ma[i]["loop_offset_s"]))
    a("")
    a("## Alle 56 Musik-Tracks (eff. Peak / eff. Loudness, vorher -> nachher)")
    a("")
    a("| Track | Peak v | Peak n | Loud v | Loud n |")
    a("|---|---|---|---|---|")
    for i in sorted(ma):
        b = mb.get(i)
        if b is None:
            a("| %s | - | %+.1f | - | %.1f |"
              % (i, ma[i]["eff_peak_db"], ma[i]["eff_loud_db"]))
        else:
            a("| %s | %+.1f | %+.1f | %.1f | %.1f |"
              % (i, b["eff_peak_db"], ma[i]["eff_peak_db"],
                 b["eff_loud_db"], ma[i]["eff_loud_db"]))
    with open(OUT, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(OUT)
    for line in lines[:40]:
        print(line)


if __name__ == "__main__":
    sys.exit(main())
