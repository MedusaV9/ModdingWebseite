# build_home_props.py — WELT2: selbstgebaute Home-/Garten-Props im
# Gooby-Stil (rund, pastellig, weiche Kanten). Ersetzt die Godot-Primitive
# aus home_props.gd / door_transition.gd / klo_dusche.gd / room_base.gd.
#
# Aufruf (headless):
#   blender --background --factory-startup --python build_home_props.py -- \
#       --prop tuer_blatt --out ../../assets/props/tuer_blatt.glb
#
# Maße kommen 1:1 aus den Godot-Skripten (Tür 1.0×2.0 m, Fenster H=0.95,
# Shed-Stufen aus shed_logic.gd) — KEINE neuen Footprints erfinden.

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from props_stil import (  # noqa: E402
    TAU,
    MeshBuilder,
    build_alpha_object,
    build_object,
    export_glb,
    new_scene,
    rot_x,
    rot_z,
)


# ---------------------------------------------------------------------------
# Wiederkehrende Bauteile
# ---------------------------------------------------------------------------
def kapsel_x(mb, r, laenge, part, pos, extra_rot=None):
    """Liegende Kapsel entlang X (weiche Leiste)."""

    def pre(p):
        p = rot_z(p, math.pi / 2)
        return extra_rot(p) if extra_rot else p

    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part, pos=pos, pre_rot=pre)


def kapsel_y(mb, r, laenge, part, pos):
    """Stehende Kapsel entlang Y (weicher Pfosten)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part, pos=pos)


def kapsel_z(mb, r, laenge, part, pos):
    """Kapsel entlang Z (Griffe, Achsen)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part, pos=pos,
               pre_rot=lambda p: rot_x(p, math.pi / 2))


def knauf(mb, r, part, pos):
    mb.uvsphere(r, 10, 8, part, pos=pos)


def klinke(mb, x, y, seite):
    """Türdrücker mit Schild + Hebel (der User-Wunsch: 'Türen mit Klinke')."""
    z0 = seite * 0.043
    mb.box(0.05, 0.15, 0.016, "gold", pos=(x, y, seite * 0.04))
    kapsel_z(mb, 0.012, 0.07, "gold", pos=(x, y, z0 + seite * 0.02))
    kapsel_x(mb, 0.015, 0.13, "gold", pos=(x - 0.06, y, seite * 0.085))
    knauf(mb, 0.02, "gold", (x - 0.125, y, seite * 0.085))


def satteldach(mb, breite_x, tiefe_z, first_h, wand_y, part, ueber=0.3):
    """Zwei geneigte Dachplatten + First (Firstlinie entlang X)."""
    halb = tiefe_z / 2.0
    ang = math.atan2(first_h, halb)
    slope = math.hypot(first_h, halb)
    for seite in (-1.0, 1.0):
        a = seite * ang
        mitte_y = wand_y + first_h / 2.0
        mitte_z = seite * halb / 2.0
        # Normale der gedrehten Platte (0,1,0) → (0,cos,±sin): 3,5 cm anheben.
        ny, nz = math.cos(a), math.sin(a)
        mb.box(breite_x + ueber, 0.07, slope + ueber * 0.8, part,
               pos=(0.0, mitte_y + ny * 0.035, mitte_z + nz * 0.035),
               pre_rot=lambda p, aa=a: rot_x(p, aa))
    kapsel_x(mb, 0.045, breite_x + ueber, part,
             pos=(0.0, wand_y + first_h + 0.02, 0.0))


# ---------------------------------------------------------------------------
# Tür (door_transition.gd: Öffnung 1.0 m breit, 2.0 m hoch)
# ---------------------------------------------------------------------------
DOOR_W = 1.0
DOOR_H = 2.0


def tuer_zarge(mb):
    """Zarge + Bekleidung + Sturz; Ursprung = Boden, Mitte der Öffnung."""
    for seite in (-1.0, 1.0):
        x = seite * (DOOR_W * 0.5 + 0.05)
        mb.box(0.1, DOOR_H, 0.16, "holz_dunkel", pos=(x, DOOR_H * 0.5, 0.0))
        xt = seite * (DOOR_W * 0.5 + 0.12)
        kapsel_y(mb, 0.038, DOOR_H + 0.1, "holz",
                 pos=(xt, (DOOR_H + 0.06) * 0.5, 0.055))
        kapsel_y(mb, 0.038, DOOR_H + 0.1, "holz",
                 pos=(xt, (DOOR_H + 0.06) * 0.5, -0.055))
    mb.box(DOOR_W + 0.34, 0.12, 0.16, "holz_dunkel",
           pos=(0.0, DOOR_H + 0.06, 0.0))
    kapsel_x(mb, 0.045, DOOR_W + 0.46, "holz", pos=(0.0, DOOR_H + 0.16, 0.075))
    kapsel_x(mb, 0.045, DOOR_W + 0.46, "holz", pos=(0.0, DOOR_H + 0.16, -0.075))
    knauf(mb, 0.05, "holz", (0.0, DOOR_H + 0.21, 0.0))


def tuer_blatt(mb):
    """Türblatt mit Kassetten + Drückergarnitur. Ursprung = Scharnierkante
    (x=0), Blatt reicht bis x=1.0 — passt 1:1 an den Hinge-Node."""
    mitte = DOOR_W * 0.5
    mb.box(DOOR_W, DOOR_H, 0.07, "holz", pos=(mitte, DOOR_H * 0.5, 0.0))
    kapsel_x(mb, 0.034, DOOR_W, "holz", pos=(mitte, DOOR_H - 0.01, 0.0))
    for seite in (-1.0, 1.0):
        for hoehe in (DOOR_H * 0.31, DOOR_H * 0.72):
            mb.box(DOOR_W * 0.62, DOOR_H * 0.34, 0.02, "holz_dunkel",
                   pos=(mitte, hoehe, seite * 0.04))
        klinke(mb, DOOR_W * 0.85, 1.0, seite)


# ---------------------------------------------------------------------------
# Fensterrahmen (home_props.gd: H=0.95, Breite = Zellen × 0.5 m)
# ---------------------------------------------------------------------------
def fenster_rahmen(mb, zellen):
    """Rahmen + Sprossenkreuz + Griff, zentriert am Ursprung (wie das
    prozedurale Fenster-Modul). Glas + Bank bleiben prozedural."""
    b = zellen * 0.5
    h = 0.95
    for seite in (-1.0, 1.0):
        kapsel_y(mb, 0.035, h + 0.13, "rahmen",
                 pos=(seite * (b + 0.06) * 0.5, 0.0, 0.0))
        kapsel_x(mb, 0.035, b + 0.13, "rahmen",
                 pos=(0.0, seite * (h + 0.06) * 0.5, 0.0))
    kapsel_y(mb, 0.018, h - 0.04, "rahmen", pos=(0.0, 0.0, 0.045))
    kapsel_x(mb, 0.018, b - 0.04, "rahmen", pos=(0.0, 0.06, 0.045))
    mb.box(0.045, 0.02, 0.03, "gold", pos=(0.0, -h * 0.5 + 0.1, 0.06))
    knauf(mb, 0.016, "gold", (0.0, -h * 0.5 + 0.085, 0.065))


# ---------------------------------------------------------------------------
# Bad: Duschvorhang (klo_dusche.gd: 1.1×1.5 m) + Duschkopf
# ---------------------------------------------------------------------------
def duschvorhang_stange(mb):
    """Stange + Halter + Ring-Clips; Ursprung = Boden, Vorhang-Mitte."""
    kapsel_x(mb, 0.022, 1.3, "metall", pos=(0.0, 1.66, 0.0))
    for x in (-0.63, 0.63):
        knauf(mb, 0.035, "metall", (x, 1.66, 0.0))
    for i in range(7):
        x = -0.51 + i * 0.17
        knauf(mb, 0.028, "rahmen", (x, 1.63, 0.0))


def duschvorhang_stoff(mb):
    """Welliger Vorhang-Stoff (parametrische Fläche, halbtransparent)."""

    def punkt(u, v):
        x = (u - 0.5) * 1.1
        y = 0.08 + v * 1.52
        tiefe = 0.045 * (1.0 - 0.45 * v)
        z = math.sin(u * math.pi * 7.0) * tiefe
        return (x, y, z)

    mb.flaeche(punkt, 28, 8, "himmel")


def duschkopf(mb):
    """Wand-Duschkopf: Steigrohr + Bogen + Brausekopf; Ursprung = Boden an
    der Wand (-Z Richtung Wand)."""
    kapsel_y(mb, 0.022, 0.85, "metall", pos=(0.0, 1.5, 0.0))
    knauf(mb, 0.035, "metall", (0.0, 1.92, 0.0))
    kapsel_z(mb, 0.02, 0.3, "metall", pos=(0.0, 1.94, 0.16))
    profil = [(0.0, 0.0), (0.05, -0.01), (0.1, -0.07), (0.085, -0.1), (0.0, -0.11)]
    mb.lathe(profil, 14, "rahmen", pos=(0.0, 1.93, 0.3))
    for i in range(6):
        a = TAU * i / 6.0
        knauf(mb, 0.012, "metall",
              (math.cos(a) * 0.05, 1.815, 0.3 + math.sin(a) * 0.05))
    mb.lathe([(0.03, 0.0), (0.045, 0.02), (0.045, 0.1), (0.03, 0.12)], 12,
             "gold", pos=(0.0, 1.02, 0.0))


# ---------------------------------------------------------------------------
# Raum-Deko: Heizkörper, Lichtschalter, Steckdose, Bilderrahmen
# ---------------------------------------------------------------------------
def heizkoerper(mb):
    """Rippen-Heizkörper mit Ventil; Ursprung = Boden, Rücken zur Wand (-Z)."""
    n = 8
    breite = 0.78
    schritt = breite / (n - 1)
    for i in range(n):
        x = -breite / 2.0 + i * schritt
        kapsel_y(mb, 0.042, 0.54, "rahmen", pos=(x, 0.42, 0.0))
    mb.box(breite + 0.1, 0.05, 0.11, "rahmen", pos=(0.0, 0.71, 0.0))
    kapsel_x(mb, 0.02, breite + 0.06, "rahmen", pos=(0.0, 0.16, 0.0))
    for x in (-breite / 2.0 + 0.02, breite / 2.0 - 0.02):
        mb.lathe([(0.014, 0.0), (0.014, 0.16)], 10, "metall", pos=(x, 0.0, 0.0))
    mb.lathe([(0.02, 0.0), (0.03, 0.015), (0.03, 0.045), (0.015, 0.06)], 10,
             "gold", pos=(0.33, 0.735, 0.0))
    knauf(mb, 0.024, "gold", (0.33, 0.8, 0.0))


def lichtschalter(mb):
    """Lichtschalter-Platte, Ursprung = Plattenmitte, Front +Z."""
    mb.box(0.09, 0.09, 0.014, "rahmen", pos=(0.0, 0.0, 0.0))
    mb.box(0.042, 0.05, 0.012, "weiss",
           pos=(0.0, 0.004, 0.012),
           pre_rot=lambda p: rot_x(p, -0.12))


def steckdose(mb):
    """Steckdosen-Platte mit Topf + zwei Löchern, Front +Z."""
    mb.box(0.09, 0.09, 0.014, "rahmen", pos=(0.0, 0.0, 0.0))
    mb.lathe([(0.03, 0.0), (0.03, 0.008)], 12, "creme",
             pos=(0.0, 0.0, 0.007), pre_rot=lambda p: rot_x(p, math.pi / 2))
    for x in (-0.011, 0.011):
        knauf(mb, 0.0045, "ink", (x, 0.0, 0.016))


def bilderrahmen(mb):
    """Bilderrahmen mit Gooby-Klecks-Motiv, Ursprung = Mitte, Front +Z."""
    b, h = 0.34, 0.28
    for seite in (-1.0, 1.0):
        kapsel_y(mb, 0.02, h, "gold", pos=(seite * b / 2.0, 0.0, 0.0))
        kapsel_x(mb, 0.02, b, "gold", pos=(0.0, seite * h / 2.0, 0.0))
    mb.box(b - 0.04, h - 0.04, 0.012, "creme", pos=(0.0, 0.0, -0.004))
    mb.uvsphere(0.075, 12, 8, "pink", pos=(0.0, -0.01, 0.006),
                scale=(1.0, 0.9, 0.22))
    for x in (-0.028, 0.028):
        mb.uvsphere(0.02, 8, 6, "pink", pos=(x, 0.062, 0.004),
                    scale=(1.0, 1.6, 0.22))


# ---------------------------------------------------------------------------
# Garten-Strukturen (home_props.gd / shed_logic.gd)
# ---------------------------------------------------------------------------
SHED_MASSE = {1: (2.0, 1.6, False, False, False),
              2: (2.2, 1.9, True, True, False),
              3: (2.4, 2.3, True, True, True)}


def shed(mb, stufe):
    """Shed-Stufe 1–3: Giebelhütte statt Kiste; gleiche Hüllmaße wie das
    prozedurale Modell (Breite 1.8+0.2·Stufe, Höhe aus shed_logic.gd)."""
    breite, hoehe, anstrich, fenster, wetterhahn = SHED_MASSE[stufe]
    wand_h = hoehe - 0.42
    farbe = "creme" if anstrich else "holz"
    mb.box(breite, wand_h, breite, farbe, pos=(0.0, wand_h * 0.5, 0.0))
    mb.tri_prisma(breite, 0.42, breite, farbe, pos=(0.0, wand_h, 0.0))
    satteldach(mb, breite, breite, 0.42, wand_h, "teal", ueber=0.3)
    for x in (-breite / 2.0, breite / 2.0):
        kapsel_y(mb, 0.035, wand_h + 0.04, "holz_dunkel",
                 pos=(x, wand_h * 0.5, breite / 2.0))
    tuer_h = wand_h * 0.82
    if stufe < 3:
        mb.box(0.5, tuer_h, 0.06, "holz_dunkel",
               pos=(0.0, tuer_h * 0.5, breite / 2.0 + 0.03))
        knauf(mb, 0.03, "gold", (0.16, tuer_h * 0.52, breite / 2.0 + 0.07))
    else:
        for seite in (-1.0, 1.0):
            mb.box(0.42, tuer_h, 0.06, "holz_dunkel",
                   pos=(seite * 0.23, tuer_h * 0.5, breite / 2.0 + 0.03))
            knauf(mb, 0.03, "gold",
                  (seite * 0.07, tuer_h * 0.52, breite / 2.0 + 0.07))
    if fenster:
        fx = breite * 0.28
        fy = wand_h * 0.66
        mb.box(0.34, 0.34, 0.05, "himmel", pos=(fx, fy, breite / 2.0 + 0.02))
        for seite in (-1.0, 1.0):
            kapsel_y(mb, 0.022, 0.4, "rahmen",
                     pos=(fx + seite * 0.19, fy, breite / 2.0 + 0.04))
            kapsel_x(mb, 0.022, 0.4, "rahmen",
                     pos=(fx, fy + seite * 0.19, breite / 2.0 + 0.04))
        mb.box(0.44, 0.11, 0.13, "holz_dunkel",
               pos=(fx, fy - 0.26, breite / 2.0 + 0.07))
        for i, teil in enumerate(("rot", "gelb", "pink")):
            mb.uvsphere(0.05, 8, 6, teil,
                        pos=(fx - 0.12 + i * 0.12, fy - 0.17,
                             breite / 2.0 + 0.07))
            mb.uvsphere(0.04, 8, 6, "blatt",
                        pos=(fx - 0.12 + i * 0.12, fy - 0.22,
                             breite / 2.0 + 0.1))
    if wetterhahn:
        mb.lathe([(0.018, 0.0), (0.018, 0.4)], 10, "metall",
                 pos=(0.0, hoehe + 0.03, 0.0))
        kapsel_x(mb, 0.02, 0.3, "gold", pos=(0.0, hoehe + 0.4, 0.0))
        mb.uvsphere(0.055, 10, 8, "gold", pos=(0.1, hoehe + 0.44, 0.0),
                    scale=(1.3, 1.0, 0.5))
        mb.uvsphere(0.03, 8, 6, "rot", pos=(0.13, hoehe + 0.5, 0.0),
                    scale=(1.2, 1.0, 0.5))
        mb.tri_prisma(0.004, 0.09, 0.14, "gold", pos=(-0.13, hoehe + 0.39, 0.0))


def werkstatt(mb):
    """Werkstatt-Hütte (Hülle 2.8×~2.3×1.8 wie das prozedurale Modell)."""
    wand_h = 1.72
    mb.box(2.8, wand_h, 1.8, "holz", pos=(0.0, wand_h * 0.5, 0.0))
    mb.tri_prisma(2.8, 0.42, 1.8, "holz", pos=(0.0, wand_h, 0.0))
    satteldach(mb, 2.8, 1.8, 0.42, wand_h, "pink", ueber=0.32)
    for x in (-1.4, 1.4):
        kapsel_y(mb, 0.04, wand_h + 0.04, "holz_dunkel",
                 pos=(x, wand_h * 0.5, 0.9))
    tuer_h = 1.42
    mb.box(0.7, tuer_h, 0.08, "holz_dunkel", pos=(-0.6, tuer_h * 0.5, 0.94))
    mb.box(0.62, 0.5, 0.02, "holz", pos=(-0.6, tuer_h * 0.62, 0.99))
    knauf(mb, 0.035, "gold", (-0.36, 0.74, 0.99))
    fx, fy = 0.7, 1.22
    mb.box(0.58, 0.48, 0.06, "himmel", pos=(fx, fy, 0.92))
    for seite in (-1.0, 1.0):
        kapsel_y(mb, 0.025, 0.56, "rahmen", pos=(fx + seite * 0.31, fy, 0.95))
        kapsel_x(mb, 0.025, 0.66, "rahmen", pos=(fx, fy + seite * 0.26, 0.95))
    kapsel_y(mb, 0.02, 0.5, "rahmen", pos=(fx, fy, 0.955))
    mb.box(0.66, 0.11, 0.13, "blatt", pos=(fx, fy - 0.34, 0.98))
    mb.lathe([(0.13, 0.0), (0.13, 0.55), (0.16, 0.57), (0.16, 0.63),
              (0.12, 0.63)], 10, "terra", pos=(1.0, 1.95, -0.4))
    # Schild hängt frei UNTER der Traufe (Dach-Unterkante ~1.70 bei z=0.94)
    # und rechts neben der Tür (Türblatt endet bei x=-0.25).
    mb.box(0.54, 0.24, 0.05, "rahmen", pos=(0.08, 1.32, 0.94))
    kapsel_x(mb, 0.018, 0.5, "gold", pos=(0.08, 1.46, 0.94))
    mb.uvsphere(0.045, 10, 8, "gold", pos=(-0.08, 1.32, 0.975),
                scale=(1.9, 0.28, 0.3))
    mb.uvsphere(0.045, 10, 8, "gold", pos=(0.2, 1.32, 0.975),
                scale=(1.1, 0.28, 0.3))


def gewaechshaus_gestell(mb):
    """Gewächshaus-Gestell: Sockel, Pfosten, First, Tür (Glas separat)."""
    mb.box(2.0, 0.18, 3.0, "holz_dunkel", pos=(0.0, 0.09, 0.0))
    for x in (-0.95, 0.95):
        for z in (-1.45, 0.0, 1.45):
            kapsel_y(mb, 0.04, 1.56, "rahmen", pos=(x, 0.86, z))
    for x in (-0.95, 0.95):
        kapsel_z(mb, 0.03, 2.95, "rahmen", pos=(x, 1.6, 0.0))
    kapsel_z(mb, 0.04, 3.15, "rahmen", pos=(0.0, 2.06, 0.0))
    ang = math.atan2(0.45, 1.0)
    for seite in (-1.0, 1.0):
        for z in (-1.45, 1.45):
            kapsel_x(mb, 0.025, 1.15, "rahmen",
                     pos=(seite * 0.5, 1.84, z),
                     extra_rot=lambda p, aa=-seite * ang: rot_z(p, aa))
    tuer_h = 1.42
    for seite in (-1.0, 1.0):
        kapsel_y(mb, 0.03, tuer_h, "rahmen",
                 pos=(seite * 0.36, tuer_h * 0.5 + 0.16, 1.5))
    kapsel_x(mb, 0.03, 0.78, "rahmen", pos=(0.0, tuer_h + 0.16, 1.5))
    kapsel_x(mb, 0.025, 0.66, "rahmen", pos=(0.0, 0.85, 1.5))
    knauf(mb, 0.028, "gold", (0.26, 0.9, 1.56))


def gewaechshaus_glas(mb):
    """Glasscheiben (Wände + Tür) — Alpha 0.35."""
    for x in (-0.95, 0.95):
        mb.box(0.025, 1.42, 2.9, "himmel", pos=(x, 0.89, 0.0))
    for z in (-1.45, 1.45):
        mb.box(1.9, 1.42, 0.025, "himmel", pos=(0.0, 0.89, z))
        # Giebel-Dreieck über der Stirnwand.
        mb.tri_prisma(0.025, 0.44, 1.9, "himmel", pos=(0.0, 1.6, z),
                      quer=True)
    mb.box(0.66, 1.3, 0.02, "himmel", pos=(0.0, 0.86, 1.5))


def gewaechshaus_dach(mb):
    """Glasdach — Alpha 0.45 (Firstlinie entlang Z). Platte fällt vom
    First (x=0, y=2.05) zur Traufe (x=±1.0, y=1.6) ab."""
    ang = math.atan2(0.45, 1.0)
    slope = math.hypot(0.45, 1.0)
    for seite in (-1.0, 1.0):
        a = -seite * ang
        # Normale der gedrehten Platte: rot_z((0,1,0), a) = (−sin a, cos a).
        nx, ny = -math.sin(a), math.cos(a)
        mb.box(slope + 0.12, 0.03, 3.1, "himmel",
               pos=(seite * 0.5 + nx * 0.015, 1.825 + ny * 0.015, 0.0),
               pre_rot=lambda p, aa=a: rot_z(p, aa))


def sprinkler(mb):
    """Sprinkler: Standrohr + Kopf + Tropfen (Arme: sprinkler_arme)."""
    mb.lathe([(0.11, 0.0), (0.11, 0.04), (0.05, 0.09), (0.05, 0.5),
              (0.065, 0.52)], 14, "metall")
    mb.lathe([(0.0, 0.5), (0.12, 0.54), (0.12, 0.63), (0.09, 0.66),
              (0.0, 0.67)], 14, "teal")
    for i in range(3):
        a = TAU * i / 3.0 + 0.5
        knauf(mb, 0.028, "himmel",
              (math.cos(a) * 0.2, 0.74 + 0.04 * i, math.sin(a) * 0.2))
    knauf(mb, 0.035, "gold", (0.0, 0.7, 0.0))


def sprinkler_arme(mb):
    """Die drei rotierten Arme als eigene Region (Y-Rotation von Hand)."""
    for i in range(3):
        a = TAU * i / 3.0

        def dreh(p, aa=a):
            x, y, z = p
            c, s = math.cos(aa), math.sin(aa)
            return (x * c + z * s, y, -x * s + z * c)

        mb.capsule(0.022, 0.28, 10, 6, "metall",
                   pos=(math.cos(a) * 0.19, 0.6, -math.sin(a) * 0.19),
                   pre_rot=lambda p, dd=dreh: dd(rot_z(p, math.pi / 2)))


def werkbank(mb):
    """Werkbank mit Ablage, Schraubstock und Hammer."""
    mb.box(1.4, 0.1, 0.7, "holz_dunkel", pos=(0.0, 0.75, 0.0))
    kapsel_x(mb, 0.045, 1.4, "holz_dunkel", pos=(0.0, 0.77, 0.35))
    for x in (-0.6, 0.6):
        for z in (-0.26, 0.26):
            mb.box(0.1, 0.7, 0.1, "holz", pos=(x, 0.35, z))
    mb.box(1.24, 0.05, 0.52, "holz", pos=(0.0, 0.24, 0.0))
    mb.box(0.2, 0.1, 0.18, "metall", pos=(0.5, 0.85, 0.05))
    mb.box(0.24, 0.05, 0.2, "metall", pos=(0.5, 0.92, 0.05))
    kapsel_z(mb, 0.014, 0.24, "gold", pos=(0.5, 0.85, 0.2))
    knauf(mb, 0.024, "gold", (0.5, 0.85, 0.33))
    kapsel_x(mb, 0.02, 0.3, "holz", pos=(-0.35, 0.82, -0.1))
    mb.box(0.09, 0.07, 0.07, "metall", pos=(-0.5, 0.82, -0.1))
    mb.lathe([(0.05, 0.0), (0.05, 0.02)], 10, "creme", pos=(-0.05, 0.8, 0.18))


def sammel_stock(mb):
    """Zwei gekreuzte Stöckchen mit Astknubbeln."""
    for i, winkel in enumerate((0.0, 0.6)):

        def dreh(p, aa=winkel):
            x, y, z = p
            c, s = math.cos(aa), math.sin(aa)
            return (x * c + z * s, y, -x * s + z * c)

        mb.capsule(0.032, 0.44, 10, 6, "holz_dunkel",
                   pos=(0.0, 0.04 + i * 0.05, 0.0),
                   pre_rot=lambda p, dd=dreh: dd(rot_z(p, math.pi / 2)))
        knauf(mb, 0.04, "holz_dunkel", (0.18 * math.cos(winkel),
                                        0.05 + i * 0.05,
                                        -0.18 * math.sin(winkel)))
    knauf(mb, 0.035, "holz", (-0.2, 0.05, 0.05))


def sammel_blatt(mb):
    """Ein großes weiches Blatt mit Stiel und Mittelrippe."""
    mb.uvsphere(0.16, 14, 8, "blatt", pos=(0.0, 0.025, 0.0),
                scale=(1.0, 0.16, 0.68))
    mb.uvsphere(0.1, 10, 6, "blatt_dkl", pos=(0.05, 0.045, 0.0),
                scale=(1.3, 0.12, 0.16))
    kapsel_x(mb, 0.015, 0.16, "holz_dunkel", pos=(-0.2, 0.03, 0.0))


# ---------------------------------------------------------------------------
# Garten-Crops ohne Kenney-Pendant (garden_view.gd, volle Größe ~0,5 m —
# das Wachstum skaliert der Renderer uniform über die Stufe)
# ---------------------------------------------------------------------------
def pflanze_tomate(mb):
    """Tomatenstrauch: Stab + Ranke + drei Tomaten mit Blattschopf."""
    kapsel_y(mb, 0.018, 0.5, "holz", pos=(0.0, 0.25, 0.0))
    mb.uvsphere(0.09, 10, 7, "blatt_dkl", pos=(0.02, 0.42, 0.0),
                scale=(1.2, 0.8, 1.2))
    mb.uvsphere(0.07, 10, 7, "blatt", pos=(-0.05, 0.3, 0.05),
                scale=(1.2, 0.9, 1.2))
    for (x, y, z) in ((0.08, 0.34, 0.05), (-0.08, 0.22, -0.04),
                      (0.04, 0.14, -0.08)):
        mb.uvsphere(0.055, 10, 8, "rot", pos=(x, y, z))
        mb.uvsphere(0.02, 6, 5, "blatt_dkl", pos=(x, y + 0.05, z),
                    scale=(1.4, 0.5, 1.4))


def pflanze_chili(mb):
    """Chili-Busch: Blätterkugeln + hängende rote Schoten."""
    kapsel_y(mb, 0.016, 0.3, "holz", pos=(0.0, 0.15, 0.0))
    mb.uvsphere(0.13, 12, 8, "blatt", pos=(0.0, 0.3, 0.0),
                scale=(1.2, 0.9, 1.2))
    mb.uvsphere(0.09, 10, 7, "blatt_dkl", pos=(0.07, 0.38, 0.04))
    for i in range(4):
        a = TAU * i / 4.0 + 0.4
        x, z = math.cos(a) * 0.13, math.sin(a) * 0.13
        mb.capsule(0.024, 0.07, 8, 6, "rot", pos=(x, 0.2, z),
                   pre_rot=lambda p: rot_z(p, 0.35))


def pflanze_ananas(mb):
    """Ananas: gelbe Frucht-Tonne + gefächerter Blattschopf."""
    mb.lathe([(0.0, 0.02), (0.08, 0.04), (0.11, 0.14), (0.1, 0.26),
              (0.06, 0.3), (0.0, 0.31)], 12, "gelb")
    for i in range(6):
        a = TAU * i / 6.0
        x, z = math.cos(a) * 0.04, math.sin(a) * 0.04

        def neig(p, aa=a):
            p = rot_x(p, 0.5)
            c, s = math.cos(aa), math.sin(aa)
            return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)

        mb.uvsphere(0.1, 8, 6, "blatt_dkl", pos=(x, 0.38, z),
                    scale=(0.28, 1.5, 0.28), pre_rot=neig)
    mb.uvsphere(0.05, 8, 6, "blatt", pos=(0.0, 0.4, 0.0),
                scale=(0.5, 1.4, 0.5))


# ---------------------------------------------------------------------------
# Prop-Katalog: name → [(objektname, builder, material)]
# material: None = Palette, ("alpha", part, wert) = Transparenz-Material
# ---------------------------------------------------------------------------
PROPS = {
    "tuer_zarge": [("TuerZarge", tuer_zarge, None)],
    "tuer_blatt": [("TuerBlatt", tuer_blatt, None)],
    "fenster_rahmen_1": [("FensterRahmen1",
                          lambda mb: fenster_rahmen(mb, 1), None)],
    "fenster_rahmen_2": [("FensterRahmen2",
                          lambda mb: fenster_rahmen(mb, 2), None)],
    "fenster_rahmen_3": [("FensterRahmen3",
                          lambda mb: fenster_rahmen(mb, 3), None)],
    "duschvorhang": [
        ("DuschStange", duschvorhang_stange, None),
        ("DuschStoff", duschvorhang_stoff, ("alpha", "himmel", 0.88)),
    ],
    "duschkopf": [("Duschkopf", duschkopf, None)],
    "heizkoerper": [("Heizkoerper", heizkoerper, None)],
    "lichtschalter": [("Lichtschalter", lichtschalter, None)],
    "steckdose": [("Steckdose", steckdose, None)],
    "bilderrahmen": [("Bilderrahmen", bilderrahmen, None)],
    "shed_l1": [("ShedL1", lambda mb: shed(mb, 1), None)],
    "shed_l2": [("ShedL2", lambda mb: shed(mb, 2), None)],
    "shed_l3": [("ShedL3", lambda mb: shed(mb, 3), None)],
    "werkstatt": [("Werkstatt", werkstatt, None)],
    "gewaechshaus": [
        ("GewaechshausGestell", gewaechshaus_gestell, None),
        ("GewaechshausGlas", gewaechshaus_glas, ("alpha", "himmel", 0.35)),
        ("GewaechshausDach", gewaechshaus_dach, ("alpha", "himmel", 0.45)),
    ],
    "sprinkler": [
        ("Sprinkler", sprinkler, None),
        ("SprinklerArme", sprinkler_arme, None),
    ],
    "werkbank": [("Werkbank", werkbank, None)],
    "sammel_stock": [("SammelStock", sammel_stock, None)],
    "sammel_blatt": [("SammelBlatt", sammel_blatt, None)],
    "pflanze_tomate": [("PflanzeTomate", pflanze_tomate, None)],
    "pflanze_chili": [("PflanzeChili", pflanze_chili, None)],
    "pflanze_ananas": [("PflanzeAnanas", pflanze_ananas, None)],
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--prop", required=True, choices=sorted(PROPS))
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    new_scene()
    tris = 0
    for obj_name, bauen, material in PROPS[args.prop]:
        mb = MeshBuilder()
        bauen(mb)
        if material is None:
            obj = build_object(obj_name, mb)
        else:
            obj = build_alpha_object(obj_name, mb, material[1], material[2])
        tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[build_home_props] {args.prop}: tris={tris}")
    export_glb(args.out)


if __name__ == "__main__":
    main()
