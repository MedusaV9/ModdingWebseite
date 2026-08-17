# build_ball_prop.py — W13/BALL: der Wurfball fürs Wohnzimmer im Gooby-Stil
# (rund, pastellig, matt — Muster: build_home_props.py / props_stil.py).
# Kenney-artig low-poly: Kugel mit Äquator-Band und zwei Polkappen.
#
# Aufruf (headless):
#   blender --background --factory-startup --python build_ball_prop.py -- \
#       --out ../../../assets/props/wurfball.glb
#
# Maß: Radius exakt 0.11 m (BallLogic.RADIUS aus
# scripts/home/interactables/ball_logic.gd — Web CARE_TUNING.BALL.RADIUS).
# Ursprung = BALLMITTE (der Node setzt den Mount auf y = RADIUS und rollt
# die Kugel über rotation.x/z — Mitte-Ursprung dreht sauber).

import argparse
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from props_stil import MeshBuilder, build_object, export_glb, new_scene  # noqa: E402

RADIUS = 0.11


def wurfball(mb):
    """Kugel (creme) + dickeres Äquator-Band (pink) + Polkappen (teal)."""
    mb.uvsphere(RADIUS, 16, 12, "creme", pos=(0.0, 0.0, 0.0))
    # Band: leicht größerer Kugel-Ring um den Äquator (flachgedrückt).
    mb.uvsphere(RADIUS + 0.004, 16, 8, "pink", pos=(0.0, 0.0, 0.0),
                scale=(1.0, 0.32, 1.0))
    # Polkappen: abgeflachte Kugelchen knapp über/unter den Polen.
    for seite in (-1.0, 1.0):
        mb.uvsphere(RADIUS * 0.42, 10, 6, "teal",
                    pos=(0.0, seite * RADIUS * 0.82, 0.0),
                    scale=(1.0, 0.42, 1.0))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    new_scene()
    mb = MeshBuilder()
    wurfball(mb)
    obj = build_object("Wurfball", mb)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[build_ball_prop] wurfball: tris={tris}")
    export_glb(args.out)


if __name__ == "__main__":
    main()
