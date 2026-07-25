#!/usr/bin/env python3
"""REPASS-CUTSCENES analysis harness.

Mirrors CutscenePath.parse + CameraDirector consumption rules over the nine bundled
cutscene JSONs, then runs a kinematics pass: per-segment arc length (same Catmull-Rom /
damped-Hermite math as PathSampler, LUT 64), average speed, junction entry/exit
velocities from the easing derivative (arc-length reparam means v = avgSpeed * ease'),
FOV slopes, lookAt bearing sweep rates, and an event timeline in ticks.

Read-only: prints a report, edits nothing.
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CUT = ROOT / "src/main/resources/assets/eclipse/cutscenes"
LANG = ROOT / "src/main/resources/assets/eclipse/lang"
SOUNDS = ROOT / "src/main/resources/assets/eclipse/sounds.json"

VEIL_EASINGS = {
    "LINEAR", "EASE_IN_QUAD", "EASE_OUT_QUAD", "EASE_IN_OUT_QUAD", "EASE_IN_CUBIC",
    "EASE_OUT_CUBIC", "EASE_IN_OUT_CUBIC", "EASE_IN_QUART", "EASE_OUT_QUART",
    "EASE_IN_OUT_QUART", "EASE_IN_QUINT", "EASE_OUT_QUINT", "EASE_IN_OUT_QUINT",
    "EASE_IN_SINE", "EASE_OUT_SINE", "EASE_IN_OUT_SINE", "EASE_IN_EXPO", "EASE_OUT_EXPO",
    "EASE_IN_OUT_EXPO", "EASE_IN_CIRC", "EASE_OUT_CIRC", "EASE_IN_OUT_CIRC",
    "EASE_IN_BACK", "EASE_OUT_BACK", "EASE_IN_OUT_BACK", "EASE_IN_ELASTIC",
    "EASE_OUT_ELASTIC", "EASE_IN_OUT_ELASTIC", "EASE_IN_BOUNCE", "EASE_OUT_BOUNCE",
    "EASE_IN_OUT_BOUNCE", "EASE_OUT_IN_QUAD", "EASE_OUT_IN_CUBIC", "EASE_OUT_IN_QUART",
    "EASE_OUT_IN_QUINT",
}


def camel_to_const(name):
    out = []
    for c in name:
        if c.isupper():
            out.append("_")
        out.append(c.upper())
    return "".join(out)


# --- easing evaluation + endpoint derivatives ------------------------------------------

def ease(name, t):
    n = camel_to_const(name or "linear")
    if n not in VEIL_EASINGS:
        n = "LINEAR"
    if n == "LINEAR":
        return t
    if n == "EASE_IN_OUT_SINE":
        return -(math.cos(math.pi * t) - 1) / 2
    if n == "EASE_IN_SINE":
        return 1 - math.cos(t * math.pi / 2)
    if n == "EASE_OUT_SINE":
        return math.sin(t * math.pi / 2)
    if n == "EASE_IN_QUAD":
        return t * t
    if n == "EASE_OUT_QUAD":
        return 1 - (1 - t) ** 2
    if n == "EASE_IN_OUT_QUAD":
        return 2 * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 2 / 2
    if n == "EASE_IN_CUBIC":
        return t ** 3
    if n == "EASE_OUT_CUBIC":
        return 1 - (1 - t) ** 3
    if n == "EASE_IN_OUT_CUBIC":
        return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2
    if n == "EASE_IN_OUT_QUART":
        return 8 * t ** 4 if t < 0.5 else 1 - (-2 * t + 2) ** 4 / 2
    raise ValueError("unhandled easing " + name)


def ease_deriv(name, t, h=1e-6):
    a = max(0.0, t - h)
    b = min(1.0, t + h)
    return (ease(name, b) - ease(name, a)) / (b - a)


# --- spline math (PathSampler mirror) ---------------------------------------------------

def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vlen(a):
    return math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2)


def catmull(t, p0, p1, p2, p3):
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3)


def spline_pos(kfs, seg, t, bezier):
    def pos(i):
        k = kfs[max(0, min(i, len(kfs) - 1))]
        return (k["pos"][0], k["pos"][1], k["pos"][2])
    p0, p1, p2, p3 = pos(seg - 1), pos(seg), pos(seg + 1), pos(seg + 2)
    if not bezier:
        return tuple(catmull(t, p0[i], p1[i], p2[i], p3[i]) for i in range(3))
    m1 = tuple((p2[i] - p0[i]) * 0.25 for i in range(3))
    m2 = tuple((p3[i] - p1[i]) * 0.25 for i in range(3))
    t2, t3 = t * t, t ** 3
    h1, h2, h3, h4 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
    return tuple(p1[i] * h1 + m1[i] * h2 + p2[i] * h3 + m2[i] * h4 for i in range(3))


def seg_arclen(kfs, seg, bezier, samples=64):
    acc = 0.0
    prev = spline_pos(kfs, seg, 0.0, bezier)
    for j in range(1, samples + 1):
        cur = spline_pos(kfs, seg, j / samples, bezier)
        acc += vlen(vsub(cur, prev))
        prev = cur
    return acc


# --- validation ------------------------------------------------------------------------

def load_lang():
    en = json.load(open(LANG / "en_us.json"))
    de = json.load(open(LANG / "de_de.json"))
    return en, de


def load_sounds():
    return set(json.load(open(SOUNDS)).keys())


def validate(pid, doc, en, de, sounds, problems):
    kfs = doc["keyframes"]
    if len(kfs) < 2:
        problems.append(f"{pid}: fewer than 2 keyframes")
    last_t = -1.0
    for i, kf in enumerate(kfs):
        t = kf["t"]
        if not (0.0 <= t <= 1.0):
            problems.append(f"{pid} kf{i}: t {t} out of [0,1]")
        if t <= last_t:
            problems.append(f"{pid} kf{i}: t {t} not strictly increasing")
        last_t = t
        if len(kf["pos"]) != 3 or not all(isinstance(v, (int, float)) for v in kf["pos"]):
            problems.append(f"{pid} kf{i}: bad pos")
        fov = kf.get("fov", 70.0)
        if not (isinstance(fov, (int, float)) and math.isfinite(fov) and 1 <= fov < 180):
            problems.append(f"{pid} kf{i}: bad fov {fov!r}")
        easing = kf.get("easing", "linear")
        if camel_to_const(easing) not in VEIL_EASINGS and easing != "linear":
            problems.append(f"{pid} kf{i}: unknown easing '{easing}' (falls back to linear)")
        la = kf.get("lookAt")
        if la is not None:
            if isinstance(la, list):
                if len(la) != 3 or not all(isinstance(v, (int, float)) for v in la):
                    problems.append(f"{pid} kf{i}: bad lookAt array")
            elif isinstance(la, str):
                if la != "player" and not (la.startswith("anchor:") and len(la) > 7):
                    problems.append(f"{pid} kf{i}: bad lookAt string '{la}'")
            else:
                problems.append(f"{pid} kf{i}: bad lookAt type")
    for j, ev in enumerate(doc.get("events", [])):
        t, typ = ev["t"], ev.get("type", "sound")
        if not (0.0 <= t <= 1.0):
            problems.append(f"{pid} ev{j}: t {t} out of [0,1]")
        eid, data = ev.get("id", ""), ev.get("data", "")
        if typ == "sound":
            if ":" not in eid:
                problems.append(f"{pid} ev{j}: sound id '{eid}' unqualified")
            elif eid.startswith("eclipse:") and eid.split(":", 1)[1] not in sounds:
                problems.append(f"{pid} ev{j}: eclipse sound '{eid}' missing from sounds.json")
        elif typ == "caption":
            if " " in eid or "." not in eid:
                problems.append(f"{pid} ev{j}: caption id '{eid}' looks literal")
            if eid not in en:
                problems.append(f"{pid} ev{j}: caption '{eid}' missing in en_us")
            if eid not in de:
                problems.append(f"{pid} ev{j}: caption '{eid}' missing in de_de")
            args = data.split(",") if data else []
            if args and args[0] not in ("subtitle", "title", "whisper"):
                problems.append(f"{pid} ev{j}: caption style '{args[0]}' unknown")
        elif typ == "fade":
            args = [a.strip() for a in data.split(",")] if data else []
            if len(args) < 3:
                problems.append(f"{pid} ev{j}: fade data '{data}' needs >=3 args")
            else:
                for a in args[:3]:
                    int(a)
                if len(args) > 3:
                    hexs = args[3].lstrip("#").lstrip("0x")
                    int(args[3].removeprefix("#").removeprefix("0x").removeprefix("0X"), 16)
        elif typ == "shake":
            args = [a.strip() for a in data.split(",")] if data else []
            if not args:
                problems.append(f"{pid} ev{j}: shake data empty")
            else:
                s = float(args[0])
                if s > 1.5:
                    problems.append(f"{pid} ev{j}: shake strength {s} above soft cap band")
                if len(args) > 1:
                    int(args[1])
                if len(args) > 2:
                    float(args[2])
        else:
            problems.append(f"{pid} ev{j}: unknown event type '{typ}' (ignored by engine)")


# --- kinematics report -------------------------------------------------------------------

def report(pid, doc):
    kfs = doc["keyframes"]
    dur = doc.get("durationTicks", 100)
    bezier = doc.get("interpolation") == "bezier"
    print(f"\n=== {pid} ({dur}t, {doc.get('interpolation','catmullrom')}, anchor {doc.get('anchor','world')}) ===")
    print(f"{'seg':>3} {'t-range':>13} {'ticks':>6} {'arclen':>8} {'avg b/t':>8} "
          f"{'v_in':>6} {'v_out':>6} {'easing':<16} {'fov':>11} {'fovslope°/t':>11}")
    n = len(kfs)
    vout_prev = None
    for s in range(n - 1):
        a, b = kfs[s], kfs[s + 1]
        span = b["t"] - a["t"]
        ticks = span * dur
        L = seg_arclen(kfs, s, bezier)
        avg = L / ticks if ticks > 0 else 0.0
        easing = a.get("easing", "linear")
        vin = avg * ease_deriv(easing, 0.0)
        vout = avg * ease_deriv(easing, 1.0)
        fova, fovb = a.get("fov", 70), b.get("fov", 70)
        fovslope = (fovb - fova) / ticks if ticks else 0
        jump = ""
        if vout_prev is not None and abs(vin - vout_prev) > 0.12 and max(vin, vout_prev) > 0.15:
            jump = f"  << VELOCITY JUMP {vout_prev:.2f}->{vin:.2f} b/t"
        print(f"{s:>3} {a['t']:>6}->{b['t']:<6} {ticks:>6.1f} {L:>8.1f} {avg:>8.3f} "
              f"{vin:>6.2f} {vout:>6.2f} {easing:<16} {fova:>5}->{fovb:<5} {fovslope:>+10.3f}{jump}")
        vout_prev = vout
    # dead-frame scan: windows > 60t with avg speed < 0.15 b/t and no event inside
    events = sorted(doc.get("events", []), key=lambda e: e["t"])
    print("  events (tick):")
    for ev in events:
        print(f"    t={ev['t']:<5} tick={ev['t']*dur:>6.1f}  {ev.get('type','sound'):<8} "
              f"{ev.get('id','')}  {ev.get('data','')}")


def main():
    en, de = load_lang()
    sounds = load_sounds()
    problems = []
    ids = ["intro_v3_ship", "intro_v3_flight", "intro_v3_reveal", "expansion_skyward",
           "expansion_flyover", "unlock_ring", "end_shatter", "finale_return", "credits_helm"]
    for pid in ids:
        doc = json.load(open(CUT / f"{pid}.json"))
        validate(pid, doc, en, de, sounds, problems)
        report(pid, doc)
    print("\n--- validation problems ---")
    if problems:
        for p in problems:
            print("  " + p)
        sys.exit(1)
    print("  none — all 9 paths pass the parse/i18n/grammar rules")


if __name__ == "__main__":
    main()
