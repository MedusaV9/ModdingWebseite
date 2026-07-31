# UV map — Umbral Blade (`assets/eclipse/textures/item/umbral/umbral_blade.png` + `_glowmask.png`)

**Texture size:** 64×64 (beide Dateien — GeckoLibs `AutoGlowingTexture` erzwingt
Albedo = Glowmask-Canvas). Modell: `assets/eclipse/geo/item/umbral_blade.geo.json`
(GeckoLib-ITEM, **14 Bones / 16 Cubes**, Box-UV). **Geo, Anim UND Texturen sind
GENERIERT** — `python3 scripts/geckolib_gen/items/umbral_blade.py` schreibt alle vier
Dateien deterministisch; hier ist nur das Layout eingefroren:

| Bone | Cube | Box W×H×D | UV | Notizen |
|---|---|---|---|---|
| grip | Griffsäule | 1×5×1 | (0,0) | `hilt_bone`, Knochen/Elfenbein mit Drechselringen |
| grip | Wickelband | 2×1×2 (inflate −0.15) | (8,0) | dunkles Gewebe (`weave`) |
| pommel | Knauf | 2×2×2 | (16,0) | `guard_iron` |
| glow_eye | Knauf-Auge | 1×1×1 (inflate 0.18) | (26,0) | emissiv, `flame`; ringsum sichtbarer Iris-Ring |
| guard | Parierbalken | 6×1×2 | (32,0) | `guard_iron`, blasse Oberkante |
| guard | Horn links | 1×2×2 (rot z +28) | (0,8) | nach AUSSEN geschwungen (Halbmond-Silhouette) |
| guard | Horn rechts | 1×2×2 (rot z −28) | (8,8) | |
| blade_root | Klingensegment 1 | 2×6×1 | (16,8) | `blade_steel`: WEST = Schneide (blass), EAST = Rücken (dunkel) |
| blade_mid | Klingensegment 2 | 2×5×1 (rest z 5°) | (24,8) | Kurve Richtung Schneide |
| blade_tip | Klingensegment 3 | 2×2×1 (rest z 7°) | (32,8) | kumulierte 12° Krümmung |
| blade_tip | Spitzenkappe | 1×2×1 (inflate −0.24) | (40,8) | zur Schneidenseite versetzt |
| glow_edge_a | Schneiden-Aura 1 | 1×5×0 | (46,8) | emissive 0-Tiefe-Ebene, ragt über die Schneide hinaus |
| glow_edge_b | Schneiden-Aura 2 | 1×5×0 | (50,8) | |
| glow_edge_c | Schneiden-Aura 3 | 1×3×0 | (54,8) | |
| wisp_a | Schatten-Fahne links | 2×2×0 | (0,16) | NICHT emissiv; Ruhe-Scale 0 (idle-Anim, MD3-Muster) |
| wisp_b | Schatten-Fahne rechts | 2×2×0 | (6,16) | |

**Emissiv (Glowmask):**

* `glow_eye`, `glow_edge_*` — automatischer Albedo-Copy jedes `glow_*`-Bones
  (`edge_aura` ist shadeless mit ragged Flame-Lücken).
* **Adern** (`blade_vein_glow`) — die Klingensegmente sind KEINE `glow_`-Bones; ein
  expliziter Glow-Painter zeichnet die wandernde Adersäule (`vein_intensity`, pro
  Zeile global-y-verrauscht plus seltene Seitenzweige) NUR in die Glowmask. Dieselbe
  Maskenfunktion tönt die Albedo (dunkelvioletter Einleger) — Albedo und Glow bleiben
  pixelgenau deckungsgleich.

**Art-Brief:** ein dunkles Umbral-Kurzschwert — Nachtviolett-Stahl (`#120B1E`/`#3A2860`),
gehonte blasse Schneide (`#EDE7F8` auf der West-Face), Adern in `#7B4FD0`/`#CEB2FC`,
Knochengriff (`#C9BCA4`/`#6E6254`) — exakt die Palette des finalen 2D-Icons
(`textures/item/umbral_blade.png`), das GUI/Ground/Fixed weiterhin zeigen.

**Generator (deterministisch, Re-Runs byte-identisch):**

```
python3 scripts/geckolib_gen/items/umbral_blade.py
```

Texturen NIE von Hand malen (AGENTS.md-Gesetz); AI-Art ersetzt später an identischen
Pfaden/Canvas-Größen.
