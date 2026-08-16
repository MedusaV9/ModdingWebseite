# Blockbench-Quellprojekte (Gooby Premium-Wave)

`gooby.bbmodel` und `gooby_baby.bbmodel` sind vollwertige Blockbench-Projekte
(Format `bedrock`, Blockbench ≥ 4.10) und werden **deterministisch generiert**
aus den Runtime-Assets:

```
python3 scripts/gen_bbmodel.py
```

Quellen der Wahrheit bleiben die Runtime-Dateien:

- `src/main/resources/assets/goobymod/geo/gooby.geo.json`
- `src/main/resources/assets/goobymod/geo/gooby_baby.geo.json`
- `src/main/resources/assets/goobymod/animations/gooby.animation.json`

## Inhalt

| Projekt | Cubes | Bones | Animationen | Textur (embedded) |
| --- | --- | --- | --- | --- |
| `gooby.bbmodel` | 27 | 21 (inkl. `hat_anchor`, `neck_anchor`, `back_anchor`) | alle 52 Clips | `gooby.png` (Base64) |
| `gooby_baby.bbmodel` | 27 | 19 | — (Clips teilt sich das Baby mit dem Adult-Projekt) | `gooby_baby.png` (Base64) |

## Konventionen

- **Bone-Namen und Locator-Anker niemals umbenennen** (`hat_anchor`,
  `neck_anchor`, `back_anchor` werden vom `GoobyRenderer` per Namen gegriffen,
  `head`/`body` vom `GoobyModel`).
- Koordinaten sind beim Import/Export nach Bedrock-Konvention gespiegelt
  (X-Achse; Bone-Rotationen `[-x, -y, z]`, Positions-Keyframes `-x`).
- GeckoLib-Easings (`easeInOutSine`, `easeOutBack`, …) sind an den Keyframes
  als `easing`-Feld hinterlegt und werden vom Blockbench-Plugin
  „GeckoLib Animation Utils" angezeigt; Vanilla-Blockbench zeigt diese
  Keyframes als linear an. `lerp_mode: catmullrom` erscheint als
  Smooth-Keyframe.
- Nach manuellen Änderungen in Blockbench: als Bedrock-Geo exportieren,
  Runtime-Dateien ersetzen und danach `python3 scripts/gen_bbmodel.py`
  erneut ausführen, damit die `.bbmodel`-Quellen synchron bleiben.
  `python3 scripts/validate_assets.py` prüft anschließend UVs, Bones,
  Texturen und die `.bbmodel`-Konsistenz.
