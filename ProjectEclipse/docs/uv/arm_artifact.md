# UV map — Arm Artifact (`assets/eclipse/textures/item/artifact/arm_artifact.png` + `_glowmask.png`)

**Texture size:** 64×64 (beide Dateien — GeckoLibs `AutoGlowingTexture` erzwingt
Albedo = Glowmask-Canvas). Modell: `assets/eclipse/geo/item/arm_artifact.geo.json`
(GeckoLib-ITEM, **12 Bones / 14 Cubes**, Box-UV). Das Geo ist die UV-Quelle der Wahrheit —
der Painter (`scripts/geckolib_gen/paint_lib.py`) parst es und rechnet jedes Face-Rect
selbst aus; hier ist nur das Layout eingefroren:

| Bone | Cube | Box W×H×D | UV | Notizen |
|---|---|---|---|---|
| forearm | Unterarm | 4×9×4 | (0,0) | `mummy`-Material: Bandagen-Nähte alle 3 Reihen, seltene Blutsprenkel |
| forearm | Bandagen-Zipfel | 0×3×1 (−8° Z) | (28,16) | Ebene, hängt an der Ostseite |
| glow_stump | Stumpf-Ring | 4×1×4 (inflate 0.25) | (16,0) | emissiv; `down`-Face = Schnittfläche (Gerinnsel-Kern) |
| hand | Handrücken | 5×2×4 | (32,0) | `knuckled` (Knöchel-Highlight auf Face-Reihe 0) |
| hand | Daumen | 1×3×1 (+20° Z) | (16,16) | |
| fingers | Finger 1–4 | je 1×3×1 | (0,16) / (4,16) / (8,16) / (12,16) | |
| glow_ledger | Ledger-Mote | 2×2×2 | (20,16) | statisch [45,0,45] gekippt, `flame`-Material |
| glow_page_a | Ledger-Blatt 1 | 4×5×0 | (0,21) | **NEU (F-098 MD2)**; z-Versatz +0.03 |
| glow_page_b | Ledger-Blatt 2 | 4×5×0 | (8,21) | NEU; z-Versatz +0.01 |
| glow_page_c | Ledger-Blatt 3 | 4×5×0 | (16,21) | NEU; z-Versatz −0.01 (spiegelseitig, origin x = −4) |
| glow_page_d | Ledger-Blatt 4 | 4×5×0 | (24,21) | NEU; z-Versatz −0.03 (spiegelseitig) |

**Kipp/Spin-Trennung (MD3-§6.1-Gesetz):** `glow_ledger` trägt den statischen
[45,0,45]-Kipp, die animierte Y-Drehung liegt auf dem NEUEN Elternbone `ledger_spin`,
und der gemeinsame Träger `ledger` (Kind von `hand`) trägt Hub und Seiten-Fächer.
Nie Kipp und Drehung auf demselben Bone — sonst präzediert die Mote.

**Z-Versatz der vier Blätter:** alle vier Ebenen sitzen auf derselben Höhe (y 12–17) und
demselben Pivot (0,14,0). Ohne Versatz wären sie in der Ruhelage exakt koplanar und
würden z-fighten, solange sie noch nicht aufgefächert sind. Die 0.02-px-Staffelung ist
kleiner als ein Texel und im Spiel unsichtbar.

**Orientierungs-Symmetrie der Blätter:** eine Ebene mit Tiefe 0 hat in der Box-UV-Strip
spiegelbildliche North-/South-Rects. Das `ledger_page`-Material verläuft deshalb NUR
vertikal (Rahmen + Höhengradient + gebrochene Schreiblinien) und hat bewusst KEIN
links/rechts-Bundhighlight — das würde auf den beiden Seiten desselben Blattes an
gegenüberliegenden Kanten landen.

**Art-Brief:** ein abgetrennter, mumifizierter Unterarm im eingefrorenen Bone/Parchment-
Ramp (`#6E6254` / `#C9BCA4` / `#EFE6D2`), ein Crimson-Stumpfring (`#A6193A`/`#E73753`,
Gerinnsel `#520C22`) und die Ledger-Lichtmote in der ACCENT-Identitätsfarbe des
Artefakt-Menüs (`#B98CFF`, Kern Richtung Weiß). Die vier Blätter mischen ACCENT 42 %
Richtung Weiß mit einem hellen Kantenrahmen — sie sollen als Pergament lesen, nicht als
Neonkarten.

**Emissiv (Glowmask):** alle `glow_*`-Bones (automatisch), plus drei gemalte Akzente:

* `palm_spill` — ACCENT-Lichtpfütze auf dem `up`-Face des Handrückens (α ≤ 150).
* `fingertip_spill` (**NEU MD2**) — ACCENT-Wash auf den Fingerkuppen (`up`, α 130) und je
  ein Tick auf der obersten Reihe der Seitenflächen (α 80): die Finger, die die Mote
  umschließen, fangen ihr Licht.
* `seam_runes` (**NEU MD2**) — sparsame ACCENT-Runenticks auf demselben
  Alle-3-Reihen-Gitter, das `mummy()` abdunkelt (Noise-Gate 0.72, α 70–180). Bewusst
  sparsam: das muss als Schrift lesen, nicht als leuchtender Ärmel.

**Generator (deterministisch, Re-Runs byte-identisch):**

```
python3 scripts/geckolib_gen/items/arm_artifact.py
```

Texturen NIE von Hand malen (AGENTS.md-Gesetz); AI-Art ersetzt später an identischen
Pfaden/Canvas-Größen.
