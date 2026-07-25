# 3D-Bühnen von mini_golf / basket_bounce / goalie_gooby / fishing_pond / ghost_hunt

Kuratierte Kopien aus der Web-Referenz `/workspace/GOOBY/public/assets`
(dort unverändert belassen — GODOT-PLAN §3.1 READ-ONLY). Diese Notiz deckt die
fünf Spielordner ab, die auf echte 3D-Szenen zurückgebaut wurden, plus den
gemeinsamen Partikel-Ordner `_3da_stage/vfx`.

| Ordner | Quelle | Lizenz |
|---|---|---|
| `mini_golf/*.glb` | Kenney **Minigolf Kit** + **Nature Kit** | CC0 1.0 — `License-kenney-*.txt` |
| `basket_bounce/*.glb` | Kenney **Nature Kit** | CC0 1.0 — `License-kenney-nature-kit.txt` |
| `goalie_gooby/*.glb` | Kenney **Nature Kit** | CC0 1.0 — `License-kenney-nature-kit.txt` |
| `fishing_pond/*.glb` | Kenney **Nature Kit** + **Watercraft Kit** | CC0 1.0 — `License-kenney-*.txt` |
| `ghost_hunt/*.glb` | Kenney **Nature Kit** | CC0 1.0 — `License-kenney-nature-kit.txt` |
| `_3da_stage/vfx/*.png` | **Brackeys VFX Bundle v1** (itch.io) | CC0 1.0 — `vfx/LICENSE & CREDITS.txt` |

`mini_golf/Textures/colormap.png` und `fishing_pond/Textures/colormap.png` sind
die Farbpaletten, auf die die jeweiligen Kenney-GLBs relativ verweisen — ohne
sie importiert Godot die Modelle ungefärbt.

Der Gooby selbst kommt NICHT von hier, sondern aus `assets/character/gooby.glb`
(GoobyRig, W1b) — die Minispiele instanziieren das echte Rig.
