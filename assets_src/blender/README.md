# Blender-Source-Workflow (Gooby-Referenzmodell)

Hier liegt **kein** binaeres `.blend` im Repo — Quelle der Wahrheit ist das
Skript `build_gooby_reference.py`, das ein sauberes, benanntes
Gooby-Referenzmodell direkt aus dem Runtime-Geo aufbaut. So bleibt die
Blender-Szene automatisch synchron zu `geo/gooby.geo.json`.

## Nutzung

Headless eine `.blend` erzeugen (Blender ≥ 3.6, getestet gegen die
`bpy`-API von Blender 4.x):

```bash
blender --background --python assets_src/blender/build_gooby_reference.py -- \
    --geo src/main/resources/assets/goobymod/geo/gooby.geo.json \
    --out assets_src/blender/gooby_reference.blend
```

Fuer das Baby-Modell einfach `--geo .../gooby_baby.geo.json --out
assets_src/blender/gooby_baby_reference.blend` verwenden.

Interaktiv: Blender normal starten, im *Scripting*-Tab das Skript laden und
ausfuehren (ohne `--out` wird nur die Szene aufgebaut).

## Was das Skript erzeugt

- Eine Collection `gooby` (bzw. `gooby_baby`).
- Pro Bone ein benanntes Empty (`root`, `body`, `head`, `muzzle`,
  `cheekLeft`, …) in exakt der Runtime-Hierarchie — inklusive der
  Renderer-Anker `hat_anchor`, `neck_anchor`, `back_anchor`.
- Pro Cube ein benanntes Mesh (Inflate eingerechnet, UV-Planes als
  hauchduenne Boxen) mit weichem Bevel-Modifier.
- Benannte Materialien mit der Gooby-Palette: `Gooby_Fur`, `Gooby_FurDark`,
  `Gooby_Cream`, `Gooby_Pink`, `Gooby_Eye`.

## Konventionen

- Koordinaten-Mapping: `blender = (-geo_x, -geo_z, geo_y) / 16` — die
  Schnauze zeigt in Blender nach `-Y`, 16 Bedrock-Pixel sind 1 m.
- Generierte `.blend`-Dateien werden **nicht** eingecheckt (siehe
  `.gitignore`-Konvention: Quellen + reproduzierbare Skripte statt Binaries).
- Bone-/Part-Namen muessen mit dem Runtime-Geo identisch bleiben; nach
  Geo-Aenderungen das Skript einfach erneut ausfuehren.
