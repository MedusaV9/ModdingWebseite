# assets/props — Herkunft & Lizenz

Alle GLBs in diesem Ordner sind **Eigenbauten** dieses Projekts (WELT2):
prozedural in Blender erzeugt über die deterministische Pipeline
`tools/blender/props/` (`build_props.sh` → `build_home_props.py` +
`props_stil.py`). Keine Fremd-Assets, keine externen Texturen — die
Palette-Textur wird zur Buildzeit aus den Theme-Tokens (`themes/tokens.gd`)
generiert.

Lizenz: wie das Projekt selbst (Eigenwerk, keine Zusatzauflagen).

| GLB | Ersetzt | Verwendet von |
| --- | --- | --- |
| tuer_zarge / tuer_blatt | Box-Zarge + Box-Blatt + Kugel-Knauf | `door_transition.gd` |
| fenster_rahmen_1/2/3 | Rahmen-Leisten-Boxen | `home_props.fenster`, `room_base._build_window` |
| duschvorhang / duschkopf | Box-Vorhang | `klo_dusche.gd` |
| heizkoerper / lichtschalter / steckdose / bilderrahmen | (neu) | `rooms/room_deko.gd` |
| shed_l1/l2/l3 | Kisten-Shed | `home_props.shed` |
| werkstatt | Kisten-Hütte | `home_props.werkstatt` |
| gewaechshaus | Glas-Quader | `home_props.gewaechshaus` |
| sprinkler | Zylinder-Turm | `home_props.sprinkler` |
| werkbank | Platte + Beine | `home_props.werkbank` |
| sammel_stock / sammel_blatt | Zylinder/Box | `home_props.sammel_spot` |

Neu bauen: `GOOBY-GODOT/tools/blender/props/build_props.sh [prop]`
(Blender 4.x headless; identischer Input ⇒ identisches GLB).
