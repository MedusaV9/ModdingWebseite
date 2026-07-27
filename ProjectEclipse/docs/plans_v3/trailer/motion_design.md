# PROJECT ECLIPSE — Trailer Motion Design (30 s · 4K60 · Remotion)

> Verbindliche Design-Spezifikation für den 30-Sekunden-Trailer. Alle Werte sind für
> **3840×2160 @ 60 fps = 1800 Frames** ausgelegt und ohne WebGL umsetzbar
> (nur CSS-Transforms/Filter, `mix-blend-mode`, SVG-Filter, Canvas-2D).
> Frame-Angaben: `F0`–`F1799`. Pixelwerte gelten für die volle 4K-Leinwand.

---

## 0. Rahmendaten

| Parameter | Wert |
|---|---|
| Auflösung / FPS | 3840×2160 @ 60 fps, `durationInFrames: 1800` |
| Bildformat | Letterbox **2.35:1** → Bildfeld 3840×1634 px, Balken je **263 px** oben/unten (`#000000`) |
| Quellmaterial | In-Game-Stills 1920×1080 (Faktor exakt 2× auf 4K) + native 4K-Motion-Graphics |
| Title-Safe | 5 % Rand innerhalb des Bildfelds: x ≥ 192 px, y ≥ 263+82 px |
| Schnittraster | Musik-Grid 126 BPM → **28,57 F/Beat**; Editing-Grid: 29 F (Beat) / 14 F (Halbbeat) |
| Akte | Akt I `F0–F600` (0–10 s) · Akt II `F600–F1320` (10–22 s) · Akt III `F1320–F1800` (22–30 s) |

---

## 1. Farbskript

### 1.1 Basis-Palette

| Token | Hex | Verwendung |
|---|---|---|
| `VOID` | `#030204` | Globaler Hintergrund, nie reines Schwarz im Bildfeld |
| `NIGHT` | `#0B0614` | Dunkle Flächen, Endcard-BG |
| `SHADOW_VIOLET` | `#1E1433` | Schattenanhebung / Duotone-Tiefen |
| `LETTERBOX` | `#000000` | Nur Balken + Legal-Hintergrund |

### 1.2 Akzente

| Token | Hex | Verwendung |
|---|---|---|
| `ECLIPSE_VIOLET` | `#8B5CF6` | Primärakzent, Glows, Keylines |
| `VIOLET_DEEP` | `#5B21B6` | Verläufe, große Flächen |
| `VIOLET_HOT` | `#A78BFA` | Highlights, Korona-Mittelzone |
| `GOLD` | `#E8B44A` | Sekundärakzent (Titel-Keyline, Einstein-Ring) |
| `GOLD_HOT` | `#FFD98A` | Gold-Flash, Ring-Hotspot |
| `GOLD_DEEP` | `#9A6A1F` | Gold-Schatten |
| `CORONA_WHITE` | `#FFF6E9` | Weißblitz, Korona-Kern (nie `#FFFFFF` als Fläche) |
| `GLITCH_R` / `GLITCH_C` | `#FF3355` / `#22F5EE` | Nur für Glitch-Kanten, max. 10 F sichtbar |

### 1.3 Glow-Stufen (Violett, von innen nach außen)

`G0 #FFFFFF → G1 #EDE4FF → G2 #C4B5FD → G3 #8B5CF6 → G4 #5B21B6 → G5 rgba(91,33,182,0)`

Standard-Glow als gestapelte `drop-shadow` (4K-Werte):
`filter: drop-shadow(0 0 12px #EDE4FF) drop-shadow(0 0 48px #A78BFA) drop-shadow(0 0 160px rgba(139,92,246,.55));`

### 1.4 Farbverlauf über 30 s (kühl → violett → schwarz/gold)

Umsetzung: ein globales Grade-Overlay (`position: fixed`, `mix-blend-mode: color`,
Opacity 0.22) + ein Multiply-Overlay (Opacity 0.30), Farben per `interpolateColors`:

| Frames | Grade-Farbe (color) | Multiply-Farbe | Zusatz |
|---|---|---|---|
| `F0–F540` | `#5A7A9E` (kühles Stahlblau) | `#16222E` | `saturate(0.85)` auf Stills |
| `F540–F720` | Blende `#5A7A9E → #8B5CF6` | `#16222E → #1E1433` | Übergang während Akt-I/II-Cut |
| `F720–F1320` | `#8B5CF6` | `#1E1433` | `saturate(1.05)` |
| `F1320–F1560` | `#8B5CF6 → #2A1245` | `#1E1433 → #050308` | Sog: Welt verdunkelt |
| `F1560–F1800` | aus; nur `NIGHT`-BG | — | Gold/Korona dominieren |

### 1.5 Vignette & Grain (global, dauerhaft)

- Vignette: `background: radial-gradient(ellipse 72% 62% at 50% 46%, transparent 55%, rgba(3,2,4,0.62) 100%)`; Opacity **0.38** in Akt I, animiert auf **0.55** ab `F1320`.
- Grain: Deckkraft **0.06** (Akt I/II), **0.09** (Akt III); Rezept in §3f.
- Zusätzlich permanenter Schwarz-Lift: nie unter Luma ~4 % (Overlay `#0B0614` @ `mix-blend-mode: lighten`, Opacity 0.5) — verhindert „abgesoffene" 1080p-Kompressionsschatten.

---

## 2. Typografie

Nur OFL-Fonts via **@fontsource** (im Repo bündelbar, kein CDN):

| Rolle | Paket | Weight | Fallback |
|---|---|---|---|
| Hero-Titel | `@fontsource/bebas-neue` | 400 (einziger) | `Anton, Impact, sans-serif` |
| Slam-Alternative | `@fontsource/anton` | 400 | — |
| Taglines / Kapitelkarten | `@fontsource/space-grotesk` | 500 / 700 | `Inter, sans-serif` |
| Mono-Akzente („TAG 1/7", Koordinaten) | `@fontsource/jetbrains-mono` | 500 | `monospace` |
| Legalzeile / Fließtext | `@fontsource-variable/inter` | 400 / 600 | `system-ui` |

Alle Pakete decken Latin-Extended ab (Ä/Ö/Ü/ß sicher; Bebas/Anton sind Caps-only → ß als „SS" setzen: „GROSSES FINALE").

### 2.1 Größenraster @4K (Baseline-Grid 8 px)

| Element | Font | Größe | Tracking | Zeilenhöhe | Farbe |
|---|---|---|---|---|---|
| Hero-Titel „PROJECT ECLIPSE" | Bebas Neue | **440 px** | animiert `0.02em → 0.24em` (§3g) | 0.9 | `#EDE4FF` + Gold-Keyline `-webkit-text-stroke: 3px #E8B44A` nur auf „ECLIPSE" |
| Akt-Tagline (z. B. „7 TAGE. EINE FINSTERNIS.") | Space Grotesk 700, CAPS | **112 px** | `0.22em` | 1.1 | `#C4B5FD` |
| Sub-Tagline / Datum („AB 07. AUGUST") | Space Grotesk 500 | **72 px** | `0.12em` | 1.2 | `#A78BFA` @ 85 % |
| Mono-Kicker („// TAG 03 — DIE TRÜMMER") | JetBrains Mono 500, CAPS | **48 px** | `0.18em` | 1.0 | `#8B5CF6` |
| Legalzeile | Inter 400 | **34 px** | `0.02em` | 1.4 | `#9CA3AF` @ 70 % |

Deutscher, filmischer Look: ausschließlich Versalien für Titel/Taglines, weite Sperrung
(Tracking ≥ 0.12em), kein Italic, keine Rundungen, harte Zeilenumbrüche mit Punkt-Endungen
(„7 TAGE. EINE FINSTERNIS."). Zahlen im Datum mit Punkt: „07.–13. AUGUST".

---

## 3. Signature-Effekte (Rezeptliste)

Alle Effekte deterministisch: eine Seed-RNG für alles (Anhang A).

### 3a. Eclipse-Ring-Reveal (Endcard-Logo)

Aufbau (Container 1400×1400 px, zentriert, `perspective` unnötig):

1. **Schwarze Scheibe**: `div` 720 px ⌀, `background:#030204`, `border-radius:50%`, darüber hauchdünner Rand `box-shadow: inset 0 0 4px 1px #FFF6E9`.
2. **Korona-Glow** (3 Layer hinter der Scheibe, je `border-radius:50%`):
   - L1: 760 px, `box-shadow: 0 0 40px 12px #FFF6E9` (Opacity 0.9)
   - L2: 820 px, `box-shadow: 0 0 120px 40px #C4B5FD` (Opacity 0.6)
   - L3: 980 px, `box-shadow: 0 0 320px 120px rgba(124,58,237,0.35)`
3. **Strahlenkranz**: `div` 1400 px, `background: repeating-conic-gradient(from 0deg, rgba(196,181,253,.5) 0deg 2deg, transparent 2deg 9deg)`, maskiert auf Ring: `mask: radial-gradient(circle, transparent 358px, black 362px, black 470px, transparent 640px)`; Rotation **+8°/s** (`rotate(frame * 8/60 deg)`); zweite Kopie mit 5deg-Raster bei **−5°/s**, Opacity 0.5.
4. **Puls**: Korona-Opacity `0.85 + 0.15 * sin(frame * 0.21)` (~2 s Periode).

**Reveal-Animation** (`F1560` Start): Scheibe `scale` per Spring `SLAM` (§3g) von 0.82→1.0; Korona-Opacity 0→1 über 30 F (`Easing.out(Easing.cubic)`); **Diamantring-Blitz** bei `F1578`: weiße Ellipse 90×60 px auf 1-Uhr-Position (45°), `filter: blur(10px)`, Scale-Spring 0→1.6→1, `mix-blend-mode: screen`, `GOLD_HOT`-Tint, Opacity danach auf 0.35 gehalten.

### 3b. RGB-Split-Glitch-Cut (Szenenübergang, 8 F Standard, 6–10 F Range)

Kanaltrennung ohne WebGL: 3 absolut positionierte Kopien des Frames, jede durch eine
SVG-`feColorMatrix` auf einen Kanal reduziert, additiv gemischt via `mix-blend-mode: screen`:

```xml
<filter id="onlyR"><feColorMatrix values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0"/></filter>
<filter id="onlyG"><feColorMatrix values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0"/></filter>
<filter id="onlyB"><feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0"/></filter>
```

Frame-Tabelle (Cut bei `Fc`, `t = frame − Fc`; Offsets = R-Kopie nach links, B-Kopie nach rechts; G bleibt):

| t | Inhalt | R/B-Offset x | Slice-Shift | Extra |
|---|---|---|---|---|
| 0–1 | Szene A | ±14 px | 3 Slices, ≤40 px | — |
| 2–3 | Szene A | ±36 px | 7 Slices, ≤90 px | `saturate(2.2)` |
| 4 | **Weißblitz** `#FFF6E9` @ 0.85 | — | — | 1 Frame |
| 5–6 | Szene B | ±28 px | 7 Slices, ≤70 px | `invert(0.08)` |
| 7–9 | Szene B | ±10 → ±0 px | 3 → 0 Slices | Decay |

**Slices**: 6–9 horizontale Streifen per `clip-path: inset(y1 0 y2 0)`-Kopien; y-Grenzen und x-Shift aus `rng(seed + Fc*100 + sliceIndex)`; Streifenhöhe 60–320 px. Dazu 2 dünne Leucht-Linien (`#22F5EE`/`#FF3355`, 4 px, `mix-blend-mode: screen`, Opacity 0.7) auf zufälligen y.

### 3c. Ken-Burns / Fake-Parallax für Stills

**Ken-Burns-Bereiche** (Scale relativ zur 4K-Vollfläche, Easing `Easing.bezier(0.33, 0, 0.67, 1)`):

| Shot-Typ | Scale | Dauer | Drift (translate) |
|---|---|---|---|
| Establisher push-in | `1.06 → 1.13` | 120–150 F | ≤ 90 px diagonal |
| Push-out-Reveal | `1.16 → 1.08` | 90–120 F | ≤ 60 px |
| Detail-Crop (Teilbild!) | `1.45 → 1.55` | max. 45 F | ≤ 140 px pan |
| Montage-Stakkato | `1.10 → 1.16` | 15–20 F | 0 (nur Zoom) |

Minimum-Zoomrate **≥ 2,5 %/s** — statische Frames entlarven das Upscaling (§4).

**3-Ebenen-Fake-Parallax** (drei skalierte Kopien desselben Stills):

| Ebene | Scale-Bonus | Bewegungsfaktor | Maske / Filter |
|---|---|---|---|
| BG | +0.06 | ×0.55 | `filter: blur(5px) brightness(0.85)` |
| MID (Basis) | ±0 | ×1.0 | `maskImage: radial-gradient(ellipse 65% 75% at <Motiv-x> <Motiv-y>, black 55%, transparent 78%)` |
| FG | +0.10 | ×1.4 | `clip-path: inset(62% 0 0 0)` (unteres Drittel = Boden/Trümmer), `blur(1.5px)` |

Gesamtdrift 90–160 px über den Shot; alle drei Ebenen teilen dieselbe Drift-Richtung. Motiv-Anker pro Still in einer Manifest-Datei (`{src, focusX, focusY, fgCut}`) pflegen.

### 3d. Block-Trümmer-Partikelfeld (deterministisch, seeded)

**300 Partikel** (Range 200–400), Empfehlung: **Canvas 2D** (ein `<canvas>` 3840×2160, pro Frame komplett neu gezeichnet — bei 4K deutlich schneller als 300 DOM-Nodes mit 3D-Transforms).

Partikel-Genese (einmalig, `mulberry32(SEED)`, Anhang A):

| Eigenschaft | Verteilung |
|---|---|
| Größe | 8–48 px Kantenlänge (Quadrate + 2:1-Rechtecke, 70/30) |
| Tiefe `z` | 0.35–1.0 (skaliert Größe, Speed, Alpha) |
| Farbe | 60 % `#1E1433`, 25 % `#5B21B6`, 10 % `#8B5CF6`, 5 % `#E8B44A` (Gold-Sprenkel) |
| Drift | vy = −(20…60) px/s · z; vx = ±8 px/s; Wrap-around am Rand |
| Rotation | ωz = 10–40°/s; „3D"-Kippen: `scaleX = |cos(ωx·t + φ)|` mit ωx = 15–35°/s |
| Alpha | `0.25 + 0.65·z`; Partikel mit z < 0.5 zusätzlich per `ctx.filter='blur(3px)'`-Pass (ein separater Offscreen-Layer, nicht pro Partikel) |

Zeichnen: `ctx.setTransform(scaleX·s, 0, 0, s, x, y); ctx.rotate(rotZ); ctx.fillRect(-w/2,-h/2,w,h)` —
die `scaleX`-Squash-Achse fakt Flip in 3D. Positionen **stateless aus `frame` berechnen**
(`x = x0 + vx * frame/60`), damit Remotion-Frames unabhängig gerendert werden können.
Im Sog-Finale (§3e) erhalten alle Partikel ab `F1320` eine Radialbeschleunigung Richtung Zentrum: `p += (center − p) · smoothstep(0,150,frame−1320) · 0.9`.

### 3e. Schwarzes-Loch-Endsequenz (F1320–F1620)

1. **Snapshot**: letzter Akt-II-Still als volle Ebene einfrieren (`F1320`).
2. **Sog** `F1320–F1470` (150 F) auf dem Snapshot-Wrapper:
   - `scale: 1 → 0.04`, Easing `Easing.bezier(0.7, 0, 0.84, 0)` (beschleunigend)
   - `rotate: 0 → −320°` (gleiche Kurve)
   - `filter: blur(0 → 36px) brightness(1 → 1.6)` bis `F1420`, dann `brightness → 0` bis `F1470`
   - **Radialstreifen-Overlay**: Fullscreen-`div`, `background: repeating-conic-gradient(from 0deg, rgba(167,139,250,.28) 0deg 1.2deg, transparent 1.2deg 7deg)`, `mix-blend-mode: screen`, Rotation 0 → −540° über die 150 F, Opacity 0 → 0.8 → 0.
   - Kamera-Shake `amp 18 px` ab `F1380`, Decay §5.3.
3. **Einstein-Ring (SVG)** `F1440–F1560`, zentriert:
   - Schwarze Scheibe `r=310`.
   - **Photonenring**: `circle r=340, strokeWidth=22`, Stroke = `linearGradient` `#FFD98A → #E8B44A → #8B5CF6`, plus Kopie mit `filter: blur(60px)` (Glow) und Kopie `blur(6px)`; Ring-Opacity 0 → 1 über 40 F, Gradient-Rotation +30°/s via `gradientTransform`.
   - **Lensing-Bögen**: 2 elliptische Pfade (rx 520, ry 190) oberhalb/unterhalb, `strokeWidth 10`, Stroke `#A78BFA`, Opacity 0.7, per `stroke-dasharray`-Reveal (`strokeDashoffset` animiert über 30 F).
4. **Morph zur Endcard** `F1560–F1620`: Einstein-Ring-Scheibe wächst per Spring auf 720 px ⌀ und wird nahtlos zur Eclipse-Scheibe aus §3a; Gold-Ring blendet in die Korona über (Crossfade 20 F). Schwarzes Loch **ist** das Logo — kein Schnitt.

### 3f. Letterbox 2.35:1 + Film-Grain + chromatische Aberration

- **Letterbox**: 2 fixe `#000`-Balken à **263 px**; Einfahren `F0–F30` von 0 auf 263 px (`Easing.out(Easing.cubic)`) als Opener-Geste. Alle UI/Text-Elemente bleiben im Bildfeld.
- **Grain**: Einmalig beim Mount 3 Grain-Tiles 1024×1024 per Canvas erzeugen (`rng`-Graustufenrauschen, Werte 96–160), als `background-image` über `repeat` auf Fullscreen-Div; pro 2 Frames: Tile-Index `floor(frame/2) % 3` + Versatz `translate(rng*1024, rng*1024)`. `mix-blend-mode: overlay`, Opacity **0.06** (Akt I/II) / **0.09** (Akt III). (SVG-`feTurbulence` live bei 4K vermeiden — zu langsam; als Fallback: `baseFrequency 0.9, numOctaves 2, seed = floor(frame/2)`.)
- **Chromatische Aberration** (nur Randzone, global): 2 Zusatzkopien der Szene mit `#onlyR`/`#onlyB` (§3b), Offset **±3 px** horizontal, `mix-blend-mode: screen`, maskiert per `maskImage: radial-gradient(ellipse 60% 55% at 50% 50%, transparent 62%, black 100%)` — Mitte bleibt sauber. Impact-Momente (§5.2): Offset kurzzeitig **±18 px** (2 F) → **±3 px** (Decay 6 F).

### 3g. Text-Animationen

Spring-Presets (Remotion `spring({frame, fps: 60, config})`):

| Preset | damping | stiffness | mass | Charakter |
|---|---|---|---|---|
| `SLAM` | 12 | 260 | 0.9 | ~8 % Overshoot, settle ≈ 28 F — Hero-Titel |
| `RISE` | 22 | 140 | 1.0 | minimaler Overshoot — Taglines/Letter |
| `DRIFT` | 40 | 60 | 1.4 | träge, filmisch — Datum, Legal, Ken-Burns-Zusätze |

**Per-Buchstabe-Stagger (Blur-in)** — Standard für Taglines:
- Split in `<span>` pro Zeichen, Delay = `index * 2` F (Wortweise: `index * 4`).
- Pro Buchstabe: `p = spring(RISE)`; `opacity: p`; `translateY: 46 → 0 px`; `filter: blur(interpolate(p, [0,1], [18, 0])px)`.
- Out-Animation gespiegelt mit Delay `index * 1` F, `blur → 12px`, `opacity → 0` über 12 F.

**Hero-„SLAM"** (Titel `F1580`): ganzes Wort, `scale 1.55 → 1.0` per `SLAM`, `blur 30 → 0 px`, gleichzeitiger Weißblitz-Frame + Shake `amp 24 px`.

**Tracking-Expand** (Titel-Nachlauf `F1580–F1740`): `letterSpacing: 0.02em → 0.24em` über 160 F, `Easing.out(Easing.cubic)` — Titel „atmet" nach dem Slam weiter auseinander; Opacity konstant.

---

## 4. Upscaling-Kaschierung (1080p-Stills in 4K)

1. **Offline-Preprocess (empfohlen)**: Stills einmalig mit Lanczos auf 3840×2160 skalieren (`sharp`/`ffmpeg -vf scale=3840:2160:flags=lanczos`) statt Browser-Resampling; danach gelten Punkte 2–7 trotzdem.
2. **Nachschärfen in Remotion**: SVG-Unsharp light auf jedem Still: `feConvolveMatrix order="3" kernelMatrix="0 -0.5 0 -0.5 3 -0.5 0 -0.5 0"` (Summe 1). CSS-only-Fallback: `filter: contrast(1.06) saturate(1.06) brightness(1.01)`. Nie beides stapeln.
3. **Nie 100 %-Darstellung**: Ken-Burns-Scale immer ≥ 1.06 (§3c) → Crop kaschiert Resampling-Kanten; Zoomrate ≥ 2,5 %/s, kein Still steht länger als 90 F ohne Bewegung.
4. **Teilbild-Crops als Feature**: Detail-Shots mit Scale 1.45–1.55 nur 15–45 F halten — kurze Standzeit macht Weichheit unsichtbar; Minecraft-Nahaufnahmen dürfen bewusst `image-rendering: pixelated` nutzen (Blockkante = Stilmittel), sonst immer `auto`.
5. **Grain als Detail-Ersatz**: §3f-Grain @ 0.06–0.09 legt Hochfrequenz über weiche Flächen — wichtigster Einzeltrick.
6. **Fake-Bloom statt Schärfe**: Kopie des Stills mit `filter: brightness(1.4) blur(28px)`, `mix-blend-mode: screen`, Opacity 0.22 — helle Bereiche (Korona, Glitzer) leuchten, Blick geht zu Lichtern statt zu Kanten.
7. **Aberration + Vignette** (§3f/§1.5) liefern die „Objektiv-Ausrede" für Randunschärfe; schnelle Shots (Akt II) zusätzlich mit 1–2 px `blur` in Bewegungsrichtung (Fake-Motion-Blur via 3 überlagerte, entlang der Drift versetzte Kopien @ Opacity 0.33).

---

## 5. Timing-Grammatik

### 5.1 Schnittfrequenz pro Drittel

| Akt | Frames | Shots | Frames/Shot | Übergänge |
|---|---|---|---|---|
| I — Etablieren (0–10 s) | `F0–F600` | 5 | 90–150 F | 12-F-Dip-to-`#030204`, 1× Glitch-Cut (8 F) bei `F540` als Akt-Wechsel |
| II — Eskalation (10–20 s) | `F600–F1200` | 9–11 | 45–75 F, fallend | Glitch-Cuts 8 F, jeder 2. Cut mit Weißblitz |
| II — Stakkato-Rampe (20–22 s) | `F1200–F1320` | 6 | 15–20 F | Hard cuts auf Halbbeat (14 F), letzte 2 Shots je 15 F |
| III — Sog + Endcard (22–30 s) | `F1320–F1800` | 2 | 150 F Sog / 240 F Endcard | §3e-Morph, kein Schnitt |

Schnitte auf das 29-F-Beat-Grid legen (126 BPM); Stakkato auf 14 F (Halbbeat).

### 5.2 Impact-Frames

| Typ | Rezept | Einsatz |
|---|---|---|
| **Weißblitz** | 1 F Fullscreen `#FFF6E9` @ 0.85, dann Opacity 0.4 / 0.18 / 0.06 über 3 F | Glitch-Cut-Mitte (t=4, §3b), Hero-Slam `F1580` |
| **Schwarzblitz** | 2 F `#000000` @ 1.0, harter Aus-/Einstieg | Unmittelbar vor Akt-Wechseln (`F598`, `F1318`) und vor Endcard (`F1558`) |
| **Goldblitz** | 1 F `#FFD98A` @ 0.7 + 4 F Decay | Nur 1×: Diamantring `F1578` |

Jeder Impact koppelt: Blitz + Shake + Aberration-Spike (±18 px, §3f) im selben Frame.

### 5.3 Shake-Rezept (deterministisch, frame-basiert)

```ts
const shake = (frame: number, start: number, amp: number, tau = 7) => {
  const t = frame - start;
  if (t < 0) return { x: 0, y: 0, rot: 0 };
  const d = Math.exp(-t / tau);                    // Decay: nach ~3·tau F vorbei
  return {
    x:   amp * d * Math.sin(t * 1.15),             // ≈ 11 Hz
    y:   amp * 0.7 * d * Math.sin(t * 1.36 + 2),   // ≈ 13 Hz, phasenversetzt
    rot: 0.45 * d * Math.sin(t * 0.9),             // Grad
  };
};
```

| Stufe | amp (px @4K) | tau | Einsatz |
|---|---|---|---|
| Heavy | 36 | 7 | Hero-Slam, Sog-Beginn |
| Medium | 18 | 6 | Glitch-Cuts, Stakkato-Hits |
| Handheld-Idle | 5 (kein Decay, 0.4 Hz: `sin(frame*0.042)`) | — | dauerhaft auf allen Stills, wirkt „gefilmt" |

Shake auf den Szenen-Wrapper anwenden; Wrapper dafür 1.02× vorskalieren, damit keine Ränder einreißen.

---

## Anhang A — Seed-RNG (für §3b/§3d/§3f)

```ts
export const mulberry32 = (seed: number) => () => {
  seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
export const SEED = 0xEC1195E; // Projekt-Seed („ECLIPSE"), nie ändern → Renders reproduzierbar
```

Regel: pro Effekt eigener Ableitungs-Seed (`SEED + effectId * 1000 + frameBucket`), niemals `Math.random()` — Remotion rendert Frames parallel/außer Reihenfolge.
