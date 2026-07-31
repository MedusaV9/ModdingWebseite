# B4 — Glitch-Familie (Veil): Plan + Report

Team B4 aus `FX_CENSUS_WAVE13.md` §7 Welle B. Datei-Besitz (exklusiv):
`pinwheel/post/glitch_*.json`, `pinwheel/shaders/program/glitch_*.fsh|.json`,
`pinwheel/shaders/include/eclipse_glitch.glsl` (glitch-eigener Include),
`client/GlitchZoneFx.java`. NICHT angefasst: `VeilPostController`, alle anderen
Pipelines, `glitch_datamosh` (Zensus: „fertig — Referenzqualität").

Auftrag (Zensus §1 + §7-Zeile B4):

| Pipeline | Zensus-Idee | Nutzer-Auftrag |
|---|---|---|
| `glitch_outline` | Kanten-Trace mit Tiefen-Versatz | Tiefen-Trace: Kanten aus SceneDepth statt Farbe, „alles schwarz + nur Outlines" |
| `glitch_void` | Tiefen-Parallaxe | Sternfeld mit Tiefenlagen, Kamerabewegung ⇒ Parallaxe ⇒ „Loch in die Unendlichkeit" |
| `glitch_scanlines` | Phosphor-Persistenz | CRT-Phosphor-Decay, Bloom-Streaks auf hellen Pixeln, rollende Sync-Störung |
| `glitch_invert` | fBm-Flecken | Inversion in organischen fBm-Flecken die wachsen/schrumpfen |

---

## 0. Gelesener Bestand + die Fallen, die den Plan formen

### 0.1 glsl-processor-NPE (die teuerste Falle der Familie)

`umbral_veins.fsh` dokumentiert sie am genauesten, und `run/logs/latest.log` beweist sie
noch heute live:

```
[VeilShaderCompilerThread#0/ERROR] Couldn't parse shader eclipse:black_hole
Caused by: java.lang.NullPointerException: Cannot invoke "Object.hashCode()" because "this.value" is null
  at glsl.processor@0.2.3/…node.branch.GlslReturnNode.hashCode(GlslReturnNode.java:57)
```

Mechanik: glsl-processor hasht Funktionsbäume, sobald ein **Node-Marker** registriert ist;
einen Marker registriert **jedes einzelne `#`-Zeichen irgendwo in der Quelle, auch in
Kommentaren** (`#include`-Zeilen zählen NICHT — die frisst Veils Include-Auflösung vorher
weg). Ein wertloses `return;` hat `value == null` ⇒ NPE ⇒ Veil schluckt sie als „Couldn't
parse shader", registriert das Programm nie, und die Pipeline stirbt zur Laufzeit mit
„Failed to find post shader".

Zählung über die Familie (`grep -o '#' | wc -l` vs. `grep -c '^#include'`):

| Shader | `#` gesamt | davon `#include` | streunend | `return;` in main | Status |
|---|---|---|---|---|---|
| `glitch_outline` | 3 | 3 | 0 | ja | scharf, aber nicht gezündet |
| `glitch_void` | 3 | 3 | 0 | ja | scharf, aber nicht gezündet |
| `glitch_scanlines` | 2 | 2 | 0 | ja | scharf, aber nicht gezündet |
| `glitch_invert` | 2 | 2 | 0 | ja | scharf, aber nicht gezündet |
| `glitch_datamosh` | 2 | 2 | 0 | ja | scharf, aber nicht gezündet |
| `glitch_dome` | 3 | 3 | 0 | ja | scharf, aber nicht gezündet |
| `black_hole` | 3 | 1 | **2** (`FXWAVE-9 #4`) | ja | **gezündet — Pipeline tot** |
| `echo_grade` | 5 | 1 | 4 (Hex-Farben) | nein | Commit `431429c` hat sie entschärft |

⇒ Die ganze Glitch-Familie lebt nur davon, dass zufällig niemand eine Hex-Farbe oder ein
„Punkt #3" in einen Kommentar geschrieben hat. **Alle sechs Dateien bekommen deshalb das
`umbral_veins`-Muster: `main()` ohne wertloses `return`, verschachteltes `if`.** Das ist
dauerhaft immun und ändert null Verhalten (der Idle-Zweig lässt `color = scene` stehen).

`glslangValidator` kann diese Falle **nicht** sehen (es kompiliert `black_hole` anstandslos)
— sie ist reiner Veil-Parser. Deshalb zusätzlich ein Lint im Session-Harness.

### 0.2 Uniform-Idle-Gesetz

`GlitchZoneFx` gated Rows unter `MIN_ACTIVE = 0.01`, jeder Shader zusätzlich unter
`Strength <= 0.0005`. Nach dem Umbau steht dieser Gate als `if (s > 0.0005) { … }` um den
kompletten Effekt; im Else-Fall wird `scene` unverändert durchgereicht ⇒ bit-identisch.

### 0.3 Farb-Parameter — wie `GlitchZoneFx` sie feedet

Geprüft (`GlitchZoneFx.feed`, `GlitchColors`, `DevGlitchCommands`): **ein** global geeaster
Akzent für alle Rows, `AccentColor` (vec3, linear) + `AccentAmount` (0 = „keine Farbe
befohlen" ⇒ Shader nimmt seine eigene Konstante). Die Helfer sind
`gzAccent(shipped, accent, amount)` (luma-gematchter Tausch, für Akzente die DAS BILD sind)
und `gzTint(accent, amount)` (multiplikativ, exakt `vec3(1.0)` bei 0). **Jede neue Schicht
in diesem Paket geht durch einen der beiden** — Aufstellung in §5.

### 0.4 `Time` wrappt bei 100 s

`GlitchZoneFx` feedet `Time = (System.currentTimeMillis() % 100_000) / 1000f`. Jede Periode,
die 100 nicht teilt, springt einmal pro 100 s sichtbar. **Alle neuen Takte sind Teiler von
100** (5.0 / 6.25 / 12.5 / 25.0 s). (Der bestehende `PING_PERIOD = 4.5` in `void` tut das
nicht — Alt-Befund, siehe §7.)

### 0.5 Degenerierte Tiefe (A0 §7.2-Härtung)

A0s Heuristik: ein Roh-Depth-Sample von **exakt 0.0** kann nie von Geometrie stammen (das
wäre AUF der Near-Plane) — eine tote Depth-Kopie liest flächig 0.0. In `glitch_outline`/
`glitch_dome` ist das kein kosmetisches, sondern ein **NaN**-Problem: alle fünf
`screenToViewSpace`-Taps landen auf demselben Punkt, `cross()` wird der Nullvektor und
`normalize()` liefert NaN, das jeden späteren `clamp` überlebt. Deshalb neu in
`eclipse_glitch.glsl`: `gzDepthValid()` + `gzNormalizeSafe()`.

---

## 1. `glitch_outline` — Tiefen-Trace

**Neue Uniforms: keine** (alles aus `DiffuseDepthSampler` + `VeilCamera` + `Time`).

| # | Schicht | Formel | Kosten |
|---|---|---|---|
| O1 | **Tiefen-skalierte Trace-Breite** | `width = mix(2.6, 1.0, clamp(lC/34, 0, 1))`, Kreuz-Taps auf `texel*width` | 0 (dieselben 5 Taps, nur versetzt; 1 Tap umsortiert) |
| O2 | **Silhouette (vorzeichenbehaftet, planaritäts-gesiebt)** | pro Achse `min(max(l₊,l₋) − lC, \|l₊ + l₋ − 2·lC\|)`, davon das Maximum; `silhouette = smoothstep(0.30, 1.20, behind / max(lC*0.045, 0.22))` | 0 Taps |
| O3 | **Crease** (bestehender Laplacian, neu gewichtet 0.55) | unverändert | 0 |
| O4 | **Normalen-Disagreement** (bestehend, jetzt NaN-fest) | `gzNormalizeSafe(cross(...), vec3(0,0,1))` | 0 |
| O5 | **Depth-Trace-Ebene** | `planeDist = 2.0·(220/2)^fract(Time/6.25)`; `hit = exp(−|lC−planeDist| / max(planeDist·0.22, 0.8))`; Nachglühen `tail = step(lC,planeDist)·exp(−max(planeDist−lC, 0)/(planeDist·0.35+4))·0.35` | 1 `pow`, 2 `exp` |
| O6 | **Schwarz-Absenkung** | Fill-Wash `0.30 → 0.16` | 0 |

O2 ist der Kern: der ungerichtete Laplacian malt den Kantenbereich **beidseitig** (Objekt
UND Wand dahinter) und liest deshalb weich. Der vorzeichenbehaftete Test feuert nur auf der
NAHEN Seite ⇒ echte Objekt-Ausschnitte. Der `min()` gegen den planaren Rest kam in der
Polish-Runde dazu, weil der reine Vorzeichentest auf streifend gesehenen Flächen genauso
groß wird wie an einer Kante und den Boden geflutet hat (§7.3). O1 ist die zweite Hälfte:
eine feste 1-Texel-Kante malt auf allem einen Haarstrich, Dicke IST der Tiefen-Hinweis.

O5 ist „wandert statt statisch zu kleben" (Zensus): eine Schärfeebene fährt exponentiell
von 2 auf 220 Blöcke (Tiefe liest logarithmisch — eine lineare Fahrt kriecht im Nahfeld und
springt dann durch die Distanz), Kanten im Slab flammen auf, Passiertes glimmt nach.
Abgrenzung zu `void`: eine **Ebene** die sich von der Kamera wegschiebt, kein Radialschelf
um einen Ursprung.

Bei `Detail = 0` parkt die Ebene auf 24 Blöcken (Muster: `void`s geparkter Sweep).

## 2. `glitch_void` — Parallaxe

**Neue Uniforms: keine.** `VeilCamera.CameraPosition` ist in pinwheel-Posts belegt (Beweis:
`world_grade.fsh` A9-Shadow-Bands nutzen es), `viewDirFromUv` kommt aus `veil:space_helper`,
das der Shader schon inkludiert.

| # | Schicht | Formel | Kosten |
|---|---|---|---|
| V1 | **3 Parallaxe-Sternlagen** | `p_k = (mod(CamPos, 512) + ray·D_k) / S_k` mit `(D,S) = (176,16) / (68,8) / (21,4)` | 3 × 1 `efxHash` |
| V2 | **Durchscheinen** | `thin = mix((1−smoothstep(0.02,0.30,luma))·smoothstep(18,90,dist)·0.65, 1.0, sky)` | 0 Taps |
| V3 | **Ping-Vorrang** | `stars *= 1 − 0.55·clamp(ping,0,1)` | 0 |
| V4 | **Tote-Tiefe-Degradation** | `thin = max(thin, 1 − depthOk)` ⇒ reines Sternfeld statt schwarzem Bild | 0 |

**Warum das echte Parallaxe ist, kein Scroll-Trick:** ein Gitterpunkt, der bei Distanz `D`
entlang des Sehstrahls abgetastet wird, verschiebt sich bei einem Kameraschritt `dx` um
genau `dx/D` Radiant — die physikalisch korrekte Parallaxe für einen Stern in `D`. Ein
Schritt von 1 Block schiebt die 21-Block-Lage also 8.4× weiter als die 176-Block-Lage, und
Kopfdrehung ist über `ray` exakt. Die Sterne stehen effektiv auf Kugelschalen um die Kamera
— genau das gewollte „Loch in die Unendlichkeit"-Verhalten (Tiefe ohne Endpunkt).

**Warum eine Zelle reicht (Kosten!):** der Sternmittelpunkt wird in die mittleren 40 % der
Zelle gehasht (`0.5 ± 0.2`) und Kern-/Halo-Radius sind auf 0.13/0.30 gedeckelt ⇒ `0.2+0.3 =
0.5` = exakt die Zellgrenze. Ein Stern kann also nie von seiner Zelle beschnitten werden,
und die 8-Nachbarn-Suche eines klassischen 3-D-Sternfelds entfällt: **1 Hash pro Lage**.

**fp32-/Wrap-Disziplin:** `mod(CamPos, 512)` hält die Hash-Eingabe klein (die
`efxDither`-Notiz in `eclipse_common` ist hier Gesetz), und weil `512/S ∈ {32,64,128}` alle
Vielfache der 32-Zellen-Hash-Periode sind, ist das Feld über den Wrap **nahtlos** — kein
Umschlag-Pop beim Durchlaufen eines 512-Block-Vielfachen.

## 3. `glitch_scanlines` — Phosphor

**Neue Uniforms: keine.**

| # | Schicht | Formel | Kosten |
|---|---|---|---|
| S1 | **Asymmetrischer Phosphor-Raster** | `strike = exp(−fract(uv.y·lineCount)·3.2)`, Maske `mix(1−0.26, 1.0, strike)` statt symmetrischem Sinus | 1 `exp` statt 1 `sin` |
| S2 | **Auflösungs-treues Raster** | `lineCount = clamp(screenH·0.5, 120, 360)`, Grille `clamp(screenW·0.5, 180, 540)` | 0 |
| S3 | **Bar-Nachglühen** | `afterglow = exp(−fract(uv.y − barPos)/0.14)` (die Leiste rollt aufwärts ⇒ das Nachglühen liegt ÜBER ihr) | 1 `exp` |
| S4 | **Bloom-Streaks** | 4 horizontale Taps (`±0.0035`, `±0.0085`, Gewichte 0.34/0.16), `key = smoothstep(0.52, 1.0, luma)` | **4 Taps** |
| S5 | **Rollende Sync-Störung** | Band `exp(−|fract(uv.y−fract(Time/5))−0.5 … |·14)`, Sägezahn-Versatz `(fract(uv.y·9)−0.5)·0.020`, 1 Re-Roll in 5 verliert hart (×4.2) | 0 Taps |

S1 ist die eigentliche „Zeilen glimmen nach"-Antwort ohne History-Buffer: eine CRT-Zeile
leuchtet nicht symmetrisch um den Strahl, sie wird **geschlagen und zerfällt dann**. Ein
echtes Persistenz-Feedback bräuchte ein zweites, über Frames erhaltenes Veil-Target (neue
Framebuffer-Definition + zweiter Blit-Stage) — bewusst nicht in diesem Paket, siehe §7.
S3 liefert die zeitliche Hälfte des Nachglühens, die ohne History berechenbar ist: die
Leiste kennt ihren eigenen Verlauf aus `Time`.

## 4. `glitch_invert` — fBm-Flecken

**Neue Uniforms: keine.**

| # | Schicht | Formel | Kosten |
|---|---|---|---|
| I1 | **fBm-Feld** | `gzFbm(vec2(u.x·aspect, u.y)·2.6 + Time·(0.023, −0.017))`, **4 Oktaven** (Zensus-Deckel) | 4 × `efxNoise` |
| I2 | **Atmende Schwelle** | `thr = mix(mix(0.70,0.52,s), mix(0.60,0.30,s), grow)` mit `grow = mix(breath(12.5 s), swell(25 s), 0.45)` | 2 `sin` |
| I3 | **Fleck** | `patch = smoothstep(thr, thr + 0.055, field)` | 0 |
| I4 | **Fleck-gewichtete Grade** | Inversion `s·patch·invPulse`, Hue-Rotation `×mix(0.25,1,patch)`, Posterize-Level `mix(48,5, s·mix(0.35,1,patch))` | 0 |
| I5 | **Rand-Brand** | `rim = (1−|patch−0.5|·2)²`, Akzent-Additiv 0.45 | 0 |
| I6 | **Fleck-Korn + Rand-Dither** | Hash-Korn `×patch`, `efxDither ×rim` | 0 Taps |

Die **Schwelle** ist der Wachstums-Knopf, nicht die Amplitude: hohe Schwelle = ein paar
kleine Inseln, niedrige = die Inseln verschmelzen zum Kontinent. Zwei inkommensurable Takte
(12.5 s / 25 s), damit die Deckung nie auf einem hörbaren Beat pumpt. `Strength` verschiebt
das ganze Atemband nach unten ⇒ am Zonenrand ein paar Flecken, tief drin fast Vollbild — der
Effekt bleibt eine Übernahme, er ist nur kein Rechteck mehr.

**Getauscht:** der alte „Band-Seam-Shimmer" (Akzent-Glühen auf Posterize-Bandgrenzen, kostete
einen zusätzlichen Textur-Tap) weicht I5 — dem Akzent auf der Fleck-Isolinie. Gleiche Rolle
(der Akzent brennt auf einer Kante), stärkerer Read, ein Tap billiger.

## 5. Akzent-Vertrag pro neuer Schicht

| Schicht | Helfer | Bei `AccentAmount = 0` |
|---|---|---|
| O5 Trace-Flare / O2 Silhouette | `edgeAccent = gzAccent(EDGE_GREEN, …)` (bestehend) | Scanner-Grün |
| V1 Sterne | `gzAccent(STAR_COLD, …)` | kaltweiß |
| S3 Nachglühen, S4 Bloom | `gzTint(AccentColor, AccentAmount)` (bestehend) | `vec3(1.0)` = Identität |
| I5 Rand-Brand | `gzAccent(SEAM_VIOLET, …)` (bestehende Konstante) | Violett |

`void_purple` läuft damit durch **alle** neuen Void-Schichten: Sonar-Ping, Kontur, Kante
UND Sternfeld tragen dieselbe geeaste Farbe.

## 6. Verifikation (Plan)

1. `python3 /tmp/gzvalidate.py` — Veil-Präambel-Komposit (`#version 410 core` +
   aufgelöste `eclipse:`/`veil:`-Includes + `VeilCamera`-Stub) durch
   `glslangValidator -S frag`, alle 27 Post-Shader, plus der neue Bare-Return/`#`-Lint.
2. `./gradlew compileJava`.
3. `runClient` + `/dev glitch test <effect> <sekunden>` je Effekt, Screenshots (llvmpipe:
   Sekunden pro Frame, keine Videos).
4. Polish-Iteration nach Sichtung.

---

## 7. Verifikation (Ergebnis)

`runClient` war in dieser Session nicht fahrbar: der Arbeitsbaum ist von den parallel
laufenden Teams B1/B2 belegt und `./gradlew compileJava` scheitert reproduzierbar in
FREMDEN Dateien (erst `ritual/ReviveRitual.java`, nach deren Fix `veilfx/MobPhotonFxRows.java`
— `spawnOnEntity` mehrdeutig). B4 fasst **keine** Java-Datei an (`GlitchZoneFx.java` ist
unverändert, `git diff` leer), der Beitrag ist rein Ressourcen-seitig; `./gradlew
processResources` ist grün. Statt des Clients wurde die Familie auf **demselben Renderer**
geprüft, den der Client auf dieser VM benutzt (Mesa llvmpipe), über vier Sitzungswerkzeuge:

| Werkzeug | Was es prüft | Ergebnis |
|---|---|---|
| `/tmp/gzvalidate.py` | Veil-Präambel-Komposit → `glslangValidator -S frag`, alle 27 Post-Shader + Bare-Return/`#`-Lint | alle 6 Glitch-Shader OK; einzig `black_hole` fällt (fremd, schon vor dieser Welle kaputt) |
| `glsl-processor` 0.2.3 (`GlslParser.preprocessParse` + `GlslTree.toSourceString`) | die NPE-Falle selbst — Veils echter Parser | 6/6 OK. **Positivkontrolle**: `black_hole.fsh` wirft exakt `GlslReturnNode.hashCode` NPE ⇒ der Check greift wirklich |
| `/tmp/gzrender.py` + `/tmp/gztest.py` | Gesetzes-Checks gegen echte Frames (Farb- + Tiefen-FBO, `VeilCamera`-UBO) | s. Tabelle unten, alles PASS |
| `/tmp/gzparallax.py` | misst die Parallaxe der drei Void-Lagen gegen die geschlossene Form | s. §7.2 |

Der glsl-processor-Lauf zeigt nebenbei: die HEAD-Fassungen der sechs Shader hätten die NPE
**noch nicht** ausgelöst (Bare-Return vorhanden, aber kein streunendes `#` in der Datei) —
die Umstellung auf verschachteltes `if` entschärft also eine Mine, sie repariert keinen
akuten Bruch. Wichtig bleibt sie trotzdem: jede spätere Zeile mit `#` in einem Kommentar
hätte die Pipeline still abgemeldet.

### 7.1 Gesetzes-Checks (854×480, llvmpipe)

| Shader | Idle bit-identisch (`Strength` 0) | Tote Tiefe endlich | Wertebereich | Time-Sweep 0…100 s | reducedFx zeitinvariant |
|---|---|---|---|---|---|
| `glitch_outline` | PASS | PASS (mean 0.004) | PASS (max 1.15) | PASS | max Δ 0.0000 |
| `glitch_void` | PASS | PASS (mean 0.009) | PASS (max 0.37) | PASS | max Δ 0.0000 |
| `glitch_scanlines` | PASS | PASS (mean 0.132) | PASS (max 0.40) | PASS | max Δ 0.0000 |
| `glitch_invert` | PASS | PASS (mean 0.592) | PASS (max 1.00) | PASS | max Δ 0.0000 |
| `glitch_datamosh` | PASS | PASS (mean 0.168) | PASS (max 0.40) | PASS | max Δ 0.0000 |
| `glitch_dome` | PASS | PASS (mean 0.006) | PASS (max 1.10) | PASS | max Δ 0.0000 |

„Idle bit-identisch" ist ein exakter `np.array_equal` gegen den Eingangsframe, nicht ein
Toleranzvergleich. Zusätzlich: Endlichkeit auch bei Far-Plane 1024 und 4096 (Render-Distanz
64+ Chunks) für alle tiefenlesenden Pässe.

### 7.2 Parallaxe, gemessen statt behauptet

Jede Lage einzeln gerendert, Kamera 2 Blöcke seitwärts, Verschiebung per Korrelation:

| Lage | D | Vorhersage `dx/D · px_per_rad` | gemessen |
|---|---|---|---|
| nah | 21 Blöcke | 32.6 px | 37 px |
| mitte | 68 Blöcke | 10.1 px | 12 px |
| fern | 300 Blöcke | 2.3 px | 2 px |

Der kleine Überschuss stammt daher, dass die Korrelation über einen breiten Streifen läuft,
in dem px/rad zum Rand hin wächst. Lagentrennung nah↔fern: 14.3× — die Lagen laufen
tatsächlich gegeneinander, das ist der Tiefen-Read.

### 7.3 Zwei echte Bugs, die erst die Frames gezeigt haben

Die erste Testrunde war **falsch grün**: moderngl setzt auf Depth-Texturen per Default
`GL_TEXTURE_COMPARE_MODE`, jedes `texture()` durch einen normalen `sampler2D` gab damit 0.0
— zufällig genau das Tote-Tiefe-Muster. Die Pässe liefen also gegen einen toten
Tiefenpuffer und die Härtung hat den Fehler höflich versteckt. Nach dem Fix
(`compare_func = ""`) traten zwei reale Defekte zutage:

1. **NaN im Outline-Trace-Schweif** (neu von mir eingebaut). `step(lC, planeDist) *
   exp(-(planeDist - lC) / …)`: hinter der Trace-Ebene ist der Exponent POSITIV, bei
   512 Blöcken Far-Plane und 2 Blöcken Rack-Start ist das `e^108` ⇒ `+inf` in fp32, und
   `step()` multipliziert dann `0 * inf = NaN`. Ergebnis: die erste Sekunde JEDER
   6.25-s-Rackperiode hätte den halben Frame vernichtet (471 141 NaN-Komponenten). Fix:
   `exp(-max(planeDist - lC, 0.0) / …)`. Dieselbe Form steckt seit jeher in
   `glitch_void`s `behind`-Term (dort erst ab ~1000 Blöcken Far-Plane scharf) und ist
   prophylaktisch mitgezogen. `gztest.py` fährt jetzt den kompletten 100-s-`Time`-Wrap in
   0.25-s-Schritten ab, damit so etwas nicht mehr durch eine Einzelprobe rutscht.
2. **Streifende Flächen haben den Boden geflutet.** Der signierte Silhouetten-Term [O2]
   (`max(Nachbar) - lC`) ist auf einem streifend gesehenen Boden genauso groß wie an einer
   echten Kante — der ganze Untergrund leuchtete, also exakt das Gegenteil vom Auftrag
   „alles schwarz + nur Outlines". Fix: pro Achse `min(behind, |lR + lL - 2·lC|)`. Der
   planare Rest ist auf JEDER Ebene ~0 (egal wie schräg) und an einer Silhouette gleich der
   Stufenhöhe, das min() behält also den Ausschnitt und wirft die Schrägen weg.

Beides ist in den Shader-Kommentaren an Ort und Stelle begründet.

### 7.4 Artefakte

`outline_before_after.png`, `void_before_after_star_shells.png`, `invert_before_after.png`
(HEAD links, Arbeitsbaum rechts, identische Kamera/Uhr/Uniforms),
`scanlines_line_profile.png` (vertikales Luma-Profil über 12 Rasterzeilen: symmetrische
Sinus-Delle vs. Anschlag-plus-Abfall), `accent_purple_grid.png` (alle vier mit `purple`),
sowie Clips `void_parallax_camera_strafe.mp4` (Uhr eingefroren, nur Kamera ⇒ die Bewegung
IST die Parallaxe), `outline_depth_trace.mp4`, `invert_patches.mp4`,
`scanlines_phosphor.mp4`. Die Void-Artefakte sind für die Anzeige um 1/2.2 aufgehellt
(auf BEIDEN Panels gleich) — der Effekt selbst ist per Design fast schwarz.

## 8. Testkommandos (Syntax aus `DevGlitchCommands`)

```
/dev glitch test outline 20
/dev glitch test void_purple 30
/dev glitch test scanlines 20
/dev glitch test invert 20
/dev glitch add void 40 120 ~ ~ ~ 40 purple
/dev glitch color <id> cyan
/dev glitch list
/dev glitch clear
```

`test <effect> [seconds]` ist der Selbsttest (nur der Aufrufer, Default 10 s, 1…300).
Farben (`GlitchColors.IDS`): `purple green red cyan orange white pink`; entweder als Suffix
am Effekt (`void_purple`) oder als letztes `add`-Argument — das explizite Argument gewinnt.
Ohne Farbe bleibt `AccentAmount = 0`, dann ist der Frame bit-gleich mit der Fassung vor
F-049. Für den Parallaxe-Read: `void`-Zone setzen und LAUFEN, nicht nur umschauen — Drehung
verschiebt alle Lagen gleich, erst Translation trennt sie.

## 9. Offene Punkte

1. **Kein In-Game-Frame.** Alles oben ist llvmpipe über eine synthetische Szene mit echter
   Tiefe und echtem `VeilCamera`-Block, aber nicht Minecraft. Sobald der Baum wieder
   kompiliert, ist `/dev glitch test void_purple 30` mit ein paar Schritten Seitwärtsgang
   der einzige noch fehlende Beweis.
2. **`black_hole.fsh` ist weiterhin kaputt** (fremdes Eigentum, Nachweis in §7): Bare-Return
   plus streunendes `#`, die Pipeline meldet sich beim Laden still ab. Ein Owner sollte das
   nach demselben Muster (verschachteltes `if`) aufräumen.
3. **Sechs weitere Shader tragen die latente Mine** (Bare-Return, aktuell ohne `#`):
   `ghost_grade`, `gravity_lens`, `rift_volume`, `storm_volume` (5×), `storm_volume_upsample`,
   `sun_halo`, `xbox_era`. `gzvalidate.py` listet sie bei jedem Lauf mit auf.
4. **`glitch_dome`** hat nur die Härtung (`gzDepthValid`, `gzNormalizeSafe`) bekommen, nicht
   den Tiefen-Trace: Der Zensus führt es nicht in B4s Auftrag, und die Dome-Innenansicht ist
   eine andere Bildaufgabe. Falls WOAH-01 den neuen Outline-Read will, ist es ein Copy der
   Blöcke [O1]/[O2]/[O5].
