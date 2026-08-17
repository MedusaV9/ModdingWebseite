#!/usr/bin/env python3
"""ef2_music_master.py — S1+S2 aus EVAL-DOPAMIN-SOUND-FEEL umsetzen.

Ein Render-Durchgang pro Musikdatei unter assets/music/ (46 Tracks):
  1. S2 Loop-Schnitt (nur Kontext-Tracks): Loop-Punkt t_a nach dem Intro,
     Schnittpunkt t_b vor dem Fade-out per Kreuzkorrelation phasenrichtig
     gesucht, Equal-Power-Kreuzblende der letzten FADE_S Sekunden in das
     Material VOR t_a gebacken -> Dateiende == Signal bei t_a, die Naht
     ist stetig. loop_offset=t_a landet in der .import-Datei.
  2. S1 Loudness-Normalisierung: gated 400-ms-RMS (EVAL1-Metrik) auf
     -20 dBFS (Beds) bzw. -17 dBFS (Stinger), Block-Limiter auf -1.5 dBFS,
     Verifikation nach dem Vorbis-Encode (Peak <= -1.05 dBFS, sonst
     nachregeln). gain_trim wird danach ueberall 1.0 (Registry-Update via
     ef2_apply_registry.py mit dem hier geschriebenen Report).
  3. Ranch-Tracks (assets/ranch, fremdes Terrain): NUR rechnerischer
     gain_trim, damit eff. Loudness/Peak dieselben Ziele einhalten.

Aufruf: python3 tools/audio/ef2_music_master.py [--only track-id ...]
Report: /tmp/gooby-godot/artifacts/EF2/music_master_report.json
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys

import numpy as np

ROOT = "/workspace/GOOBY-GODOT"
MUSIC_DIR = os.path.join(ROOT, "assets/music")
OUT = "/tmp/gooby-godot/artifacts/EF2"

TARGET_LOUD = -20.0
STINGER_LOUD = -17.0
CEIL_DB = -1.5
# Abnahme-Metrik = EVAL1-Decode (48 kHz mono). Hart geclipptes Material
# schiesst beim Resampling um mehrere dB ueber den nativen Peak hinaus
# (Inter-Sample-Peaks), also wird GEGEN DIESE Metrik verifiziert.
VERIFY_SR = 48000
VERIFY_PEAK_DB = -1.1
FADE_S = 1.6
MIN_LOOP_S = 8.0


def db(x):
    return 20.0 * math.log10(max(x, 1e-12))


def lin(x_db):
    return 10.0 ** (x_db / 20.0)


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=sample_rate,channels", "-of", "csv=p=0", path],
        capture_output=True, text=True).stdout.strip().split(",")
    return int(out[0]), int(out[1])


def decode(path, sr, ch):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le",
         "-acodec", "pcm_f32le", "-ac", str(ch), "-ar", str(sr), "-"],
        capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x.reshape(-1, ch)


def peak48(path):
    """Peak dBFS im EVAL1-Abnahme-Decode (48 kHz mono, f32)."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le",
         "-acodec", "pcm_f32le", "-ac", "1", "-ar", str(VERIFY_SR), "-"],
        capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    return db(float(np.max(np.abs(x)))) if x.size else -120.0


def encode(path, x, sr, quality=6):
    pcm = x.astype(np.float32).tobytes()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr),
         "-ac", str(x.shape[1]), "-i", "-", "-c:a", "libvorbis",
         "-q:a", str(quality), path],
        input=pcm, check=True)


def gated_loud(mono, sr):
    """EVAL1-Loudness: RMS ueber 400-ms-Fenster, Fenster > -60 dBFS gated."""
    win = int(0.4 * sr)
    if mono.size < win:
        return db(float(np.sqrt(np.mean(mono ** 2))))
    n = mono.size // win
    frames = mono[: n * win].reshape(n, win)
    fr = np.sqrt(np.mean(frames ** 2, axis=1))
    active = fr[fr > lin(-60)]
    if not active.size:
        return db(float(np.sqrt(np.mean(mono ** 2))))
    return db(float(np.sqrt(np.mean(active ** 2))))


def envelope(mono, sr, win_s=0.4, hop_s=0.05):
    win = int(win_s * sr)
    hop = int(hop_s * sr)
    idx = np.arange(0, max(mono.size - win, 1), hop)
    env = np.array([np.sqrt(np.mean(mono[i: i + win] ** 2)) for i in idx])
    times = idx / sr + win_s / 2.0
    return times, env


def limit_metric(y):
    """Betrag, gegen den limitiert wird: Kanal-Peaks UND |Mitte| —
    ffmpeg-Mono-Decode (EVAL1-Abnahme) ist (L+R)/sqrt(2), auf korreliertem
    Material bis +3 dB ueber dem Kanal-Peak."""
    amp = np.abs(y).max(axis=1)
    if y.shape[1] == 2:
        amp = np.maximum(amp, np.abs(y.sum(axis=1)) / math.sqrt(2.0))
    return amp


def block_limit(x, sr, ceil_db=CEIL_DB):
    """Zweistufiger Block-Limiter (20 ms + 5 ms) + Rest-Clip. Fuer die hier
    noetigen 0-8 dB Reduktion transparent genug; kein Pumpen dank Interp."""
    ceil = lin(ceil_db)
    y = x
    for block_s in (0.02, 0.005):
        n = y.shape[0]
        amp = limit_metric(y)
        b = max(int(block_s * sr), 8)
        nb = int(math.ceil(n / b))
        padded = np.zeros(nb * b)
        padded[:n] = amp
        bmax = padded.reshape(nb, b).max(axis=1)
        g = np.minimum(1.0, ceil / np.maximum(bmax, 1e-12))
        g = np.minimum.reduce([np.roll(g, 1), g, np.roll(g, -1)])
        g[0] = min(g[0], g[1] if nb > 1 else g[0])
        centers = np.arange(nb) * b + b / 2.0
        gain = np.interp(np.arange(n), centers, g)
        y = y * gain[:, None]
    # Rest-Clip auch auf die Mitte: Samples, deren |Mitte| noch ueber dem
    # Ceiling liegt, werden paarweise heruntergezogen (Mid-Clip).
    if y.shape[1] == 2:
        mid = np.abs(y.sum(axis=1)) / math.sqrt(2.0)
        over = mid > ceil
        if over.any():
            scale = np.ones(y.shape[0])
            scale[over] = ceil / mid[over]
            y = y * scale[:, None]
    return np.clip(y, -ceil, ceil)


def find_loop(mono, sr, dur):
    """(t_a, t_b, ncc) — Loop-Start nach dem Intro, Schnitt vor dem Fade-out,
    per normierter Kreuzkorrelation der Blend-Regionen ausgerichtet."""
    times, env = envelope(mono, sr)
    loud = gated_loud(mono, sr)
    thresh = lin(loud - 3.0)
    on = env >= thresh
    if not on.any():
        return None
    t_first = times[int(np.argmax(on))]
    t_last = times[len(on) - 1 - int(np.argmax(on[::-1]))]
    # Blend-Quelle ist (t_a - FADE_S, t_a): t_a MINDESTENS FADE_S hinter dem
    # ersten aktiven Frame, sonst blendet das Dateiende in den leisen Intro-
    # Fade und die Naht springt (EVAL blubberbad/pixie-awake: ~46 dB).
    t_a = max(t_first + FADE_S, FADE_S + 0.05)
    if t_last - t_a < MIN_LOOP_S:
        return None
    # Naht-Feinsuche: t_a auf eine getragene Stelle schieben — 50-ms-RMS
    # unmittelbar vor UND nach t_a nahe der Track-Loudness und ohne Sprung.
    # Sonst landet der Loop-Punkt in einer Atempause (blubberbad: Naht 42 dB).
    w = int(0.05 * sr)
    floor_db = loud - 9.0
    t = t_a
    limit = min(t_a + 15.0, t_last - MIN_LOOP_S)
    while t <= limit:
        i = int(t * sr)
        pre = db(float(np.sqrt(np.mean(mono[i - w: i] ** 2))))
        post = db(float(np.sqrt(np.mean(mono[i: i + w] ** 2))))
        if pre >= floor_db and post >= floor_db and abs(pre - post) <= 6.0:
            t_a = t
            break
        t += 0.05
    fade_n = int(FADE_S * sr)
    ref = mono[int(t_a * sr) - fade_n: int(t_a * sr)]
    ref_norm = float(np.sqrt(np.sum(ref ** 2))) or 1e-12
    lo = max(t_a + MIN_LOOP_S, t_last - 12.0)
    hi = min(t_last, dur - 0.05)
    if hi <= lo:
        return None
    best = (-2.0, hi)
    step = int(0.02 * sr)
    for i_b in range(int(lo * sr), int(hi * sr), step):
        cand = mono[i_b - fade_n: i_b]
        if cand.size != fade_n:
            continue
        cn = float(np.sqrt(np.sum(cand ** 2))) or 1e-12
        ncc = float(np.dot(ref, cand)) / (ref_norm * cn)
        if ncc > best[0]:
            best = (ncc, i_b / sr)
    return t_a, best[1], best[0]


def bake_loop(x, sr, t_a, t_b):
    """Equal-Power-Blende der letzten FADE_S s vor t_b in das Material vor
    t_a — das Dateiende laeuft nahtlos in den Loop-Punkt."""
    fade_n = int(FADE_S * sr)
    i_a, i_b = int(t_a * sr), int(t_b * sr)
    y = x[:i_b].copy()
    u = np.linspace(0.0, 1.0, fade_n)[:, None]
    g_out = np.cos(u * math.pi / 2.0)
    g_in = np.sin(u * math.pi / 2.0)
    y[i_b - fade_n: i_b] = (x[i_b - fade_n: i_b] * g_out
                            + x[i_a - fade_n: i_a] * g_in)
    return y


def set_import_loop(ogg_path, loop_offset):
    imp = ogg_path + ".import"
    if not os.path.exists(imp):
        return False
    text = open(imp).read()
    text = re.sub(r"^loop=.*$", "loop=true", text, flags=re.M)
    text = re.sub(r"^loop_offset=.*$", "loop_offset=%.3f" % loop_offset,
                  text, flags=re.M)
    open(imp, "w").write(text)
    return True


def parse_registry():
    src = open(os.path.join(ROOT, "scripts/audio/music_registry.gd")).read()
    pat = (r'"([\w-]+)":\s*\n\s*\{[^}]*?"file":\s*(RANCH_MUSIK_DIR\s*\+\s*)?'
           r'"([^"]+)"[^}]*?"gain_trim":\s*([\d.]+)[^}]*?"context":\s*"([^"]*)"')
    rows = {}
    for m in re.finditer(pat, src, re.S):
        tid, ranch, f, g, ctx = m.groups()
        rows[tid] = {
            "ranch": bool(ranch),
            "rel": ("assets/ranch/audio/musik/" + f.lstrip("/")) if ranch
            else ("assets/music/" + f),
            "gain_trim": float(g),
            "context": ctx,
            "stinger": f.startswith("stinger/"),
        }
    # vacation-day ist Kontext-Track via EXTRA_CONTEXT_TRACKS
    if "bordmusik-vacation-day" in rows:
        rows["bordmusik-vacation-day"]["context"] = "vacation"
    return rows


def already_done(path, mono, sr, target, is_context):
    """Idempotenz-Guard: nicht erneut schneiden/encodieren, was schon auf
    Ziel-Loudness/-Peak sitzt (schuetzt vor versehentlichem Doppellauf)."""
    loud = gated_loud(mono, sr)
    if abs(loud - target) > 0.4 or peak48(path) > VERIFY_PEAK_DB + 0.05:
        return False
    if not is_context:
        return True
    imp = path + ".import"
    if not os.path.exists(imp):
        return False
    return re.search(r"^loop_offset=0*\.?0*$", open(imp).read(), re.M) is None


def master_track(tid, row, report, force=False):
    path = os.path.join(ROOT, row["rel"])
    sr, ch = probe(path)
    x = decode(path, sr, ch)
    mono = x.mean(axis=1)
    dur = x.shape[0] / sr
    is_context = bool(row["context"]) and not row["stinger"]
    target_guard = STINGER_LOUD if row["stinger"] else TARGET_LOUD
    if not force and already_done(path, mono, sr, target_guard, is_context):
        print("[skip  ] %-42s bereits gemastert" % tid)
        report.append({"id": tid, "file": row["rel"], "skipped": True,
                       "new_gain_trim": 1.0})
        return
    entry = {"id": tid, "file": row["rel"], "dur_before": round(dur, 3)}
    loop_offset = 0.0
    if row["context"] and not row["stinger"]:
        found = find_loop(mono, sr, dur)
        if found:
            t_a, t_b, ncc = found
            x = bake_loop(x, sr, t_a, t_b)
            mono = x.mean(axis=1)
            loop_offset = t_a
            entry.update({"loop_t_a": round(t_a, 3), "loop_t_b": round(t_b, 3),
                          "loop_ncc": round(ncc, 3)})
        else:
            entry["loop_t_a"] = None
    target = STINGER_LOUD if row["stinger"] else TARGET_LOUD
    loud = gated_loud(mono, sr)
    gain_db = target - loud
    ceil_db = CEIL_DB
    for attempt in range(6):
        y = block_limit(x * lin(gain_db), sr, ceil_db)
        encode(path, y, sr)
        peak = peak48(path)
        chk = decode(path, sr, ch)
        loud_after = gated_loud(chk.mean(axis=1), sr)
        if peak <= VERIFY_PEAK_DB:
            break
        # True-Peak-Overshoot (Vorbis + 48k-Resampling): Ceiling senken statt
        # Gain — die Loudness bleibt, nur die Spitzen werden weiter gekappt.
        ceil_db -= (peak - VERIFY_PEAK_DB) + 0.15
    entry.update({
        "gain_db": round(gain_db, 2),
        "ceil_db": round(ceil_db, 2),
        "loud_after": round(loud_after, 2),
        "peak_after": round(peak, 2),
        "dur_after": round(chk.shape[0] / sr, 3),
        "loop_offset": round(loop_offset, 3),
        "new_gain_trim": 1.0,
    })
    if loop_offset > 0.0:
        set_import_loop(path, loop_offset)
    report.append(entry)
    print("[master] %-42s gain %+5.1f dB  loud %6.1f  peak %5.1f  loop %s"
          % (tid, gain_db, loud_after, peak,
             ("%.2fs->%.2fs" % (loop_offset, entry["dur_after"]))
             if loop_offset else "-"))


def ranch_trim(tid, row, report):
    path = os.path.join(ROOT, row["rel"])
    sr, ch = probe(path)
    x = decode(path, sr, ch)
    loud = gated_loud(x.mean(axis=1), sr)
    # Peak-Deckel gegen die 48k-Abnahme-Metrik (Datei bleibt unangetastet,
    # nur der Registry-Trim darf sie nicht ueber -1 dBFS heben).
    peak = peak48(path)
    trim = min(TARGET_LOUD - loud, -1.2 - peak)
    report.append({
        "id": tid, "file": row["rel"], "ranch": True,
        "loud": round(loud, 2), "peak": round(peak, 2),
        "trim_db": round(trim, 2),
        "new_gain_trim": round(lin(trim), 3),
    })
    print("[ranch ] %-42s trim %+5.1f dB (gain_trim %.3f)"
          % (tid, trim, lin(trim)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    rows = parse_registry()
    report = []
    for tid in sorted(rows):
        if args.only and tid not in args.only:
            continue
        row = rows[tid]
        if row["ranch"]:
            ranch_trim(tid, row, report)
        else:
            master_track(tid, row, report, force=args.force)
    with open(os.path.join(OUT, "music_master_report.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    print(json.dumps({"tracks": len(report)}))


if __name__ == "__main__":
    sys.exit(main())
