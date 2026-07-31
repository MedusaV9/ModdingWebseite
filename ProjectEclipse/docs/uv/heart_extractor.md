# UV map — Heart Extractor (`assets/eclipse/textures/item/extractor/heart_extractor.png` + `_glowmask.png`)

**Texture size:** 64×64 (beide Dateien — GeckoLibs `AutoGlowingTexture` erzwingt
Albedo = Glowmask-Canvas). Modell: `assets/eclipse/geo/item/heart_extractor.geo.json`
(GeckoLib-ITEM, **11 Bones / 12 Cubes**, Box-UV). Das Geo ist die UV-Quelle der Wahrheit —
der Painter (`scripts/geckolib_gen/paint_lib.py`) parst es selbst; hier ist nur das
Layout eingefroren:

| Bone | Cube | Box W×H×D | UV | Notizen |
|---|---|---|---|---|
| needle | Kanüle | 1×3×1 | (0,0) | `needle_steel`, dunkelt zur Spitze ab |
| needle | Spitze | 1×1×1 (inflate −0.25) | (4,0) | |
| frame | Unterkragen | 3×1×3 | (8,0) | `brass`, Lathe-Highlight auf Reihe 0 |
| frame | Oberkragen | 3×1×3 | (20,0) | |
| clamp_n | Nord-Backe | 3×1×1 | (24,16) | **NEU (F-098 MD2)**; Messing, kneift beim Snap ein |
| clamp_s | Süd-Backe | 3×1×1 | (32,16) | NEU |
| glow_gauge | Vitae-Anzeige | 3×2×1 | (40,16) | NEU; Messingblende + crimsoner Füllbalken |
| glow_vitae | Vitae-Füllung | 2×3×2 | (0,8) | emissiv, `flame`-Material |
| chamber_body | Glaskammer | 3×3×3 | (0,16) | vorher `chamber`; Tint unverändert |
| chamber_lid | Kammerdeckel | 3×1×3 | (12,16) | NEU; Messingkappe (`up`) + Scharnierbalken (`north`, Reihe 0) |
| plunger | Kolben | 1×2×1 | (20,8) | |
| plunger | Daumenring | 3×2×0 | (24,8) | Ebene; mittleres Bodentexel ausgespart = Ring |

**Kammer-Snap-Bone (Zensus §5 Zeile MD2):** `chamber` ist jetzt ein reiner **Träger** ohne
Cubes; darunter hängen `chamber_body` (statisches Glas) und `chamber_lid` (Scharnier bei
Pivot (0, 8, −1.5)). Nur so kann der Deckel im `extract` von 25° auf −2° zuschnappen und
nachfedern, ohne dass die ganze Kammer mitwackelt. Der Deckel braucht dafür eine eigene
Silhouette — sonst liest der Snap als Glasbeben statt als bewegliches Teil; deshalb
Messingkappe und Scharnierbalken im `lid_glass`-Material.

**Emissiv (Glowmask):**

* `glow_vitae` — voll (automatischer Albedo-Copy jedes `glow_*`-Bones).
* `chamber_shine` — Vitae-Durchschein auf den Mittelspalten der Kammer-Seitenflächen
  (α 40→130 nach unten), jetzt auf `chamber_*` (Body UND Lid). Der Glow-Layer würde die
  innere Füllung unter dem translucenten Glas depth-rejecten — Konvention aus
  `docs/plans_v3/handoff/P6_geckolib_conventions.md`.
* `collar_filament` (**NEU MD2**) — 1px-Randring auf den `up`-Faces der Kragen, Messing
  30 % Richtung Scarlet, α 60. Highlight, keine Lampe.
* `gauge_glow` (**NEU MD2**) — **nur der Füllbalken** der Anzeige (α 210 Mitte / 130
  außen). Wichtig: dieser Painter läuft ANSTELLE des automatischen Albedo-Copys, den jeder
  `glow_*`-Bone bekommt. Ohne ihn addiert `AutoGlowingGeoLayer` auch die Messingblende
  dazu und die Anzeige liest als ein orangener Klotz (genau der Fehler aus §6.3 des
  MD2-Reports). Aus demselben Grund ist `gauge_dial` bewusst **nicht** `shadeless`.

**Art-Brief:** ein Messing-und-Glas-Herzzapfhahn — kalter Stahlnadel (`#B9BFC8`),
Herald-Messing-Kragen und Daumenring (`#9A6018` / `#E8A83A` / `#FFD86A`), translucente
Glaskammer (`#9FB8C4` bei α 88; der Renderer nutzt `entityTranslucent`, Teilalpha blendet
also wirklich) und die crimsone Vitae-Füllung (`#A6193A` / `#E73753`, Gerinnsel `#520C22`).

**Generator (deterministisch, Re-Runs byte-identisch):**

```
python3 scripts/geckolib_gen/items/heart_extractor.py
```

Texturen NIE von Hand malen (AGENTS.md-Gesetz); AI-Art ersetzt später an identischen
Pfaden/Canvas-Größen.
