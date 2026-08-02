# F-107 — „das Lila Ding beim Limbo": Godray-Wall-Fix + Limbo-Emitter-Audit

User-Feedback F-107, Branch `cursor/project-eclipse`. Scope: der vom Hauptagenten per
A/B-Test überführte Quasar-Emitter `eclipse:limbo_godray` (periodische blass-rosa
Quad-Wand am Bildrand), Audit der Limbo-Schwester-Windows, repo-weiter Kurz-Audit aller
additiven Emitter (report-only). Alle Gates grün (§6); die visuelle Live-Abnahme macht
der Hauptagent nach dem RCON-Drehbuch in §7.

> **Completion-Pass (Folge-Durchgang, gleicher Auftrag):** Dieser Report beschreibt den
> ersten F-107-Durchgang (Emitter-Optik; Window bewusst unangetastet). Ein
> Folge-Durchgang hat den Fix vervollständigt: **GODRAYS-Window entschärft**
> (maxLive 3 → 2, Spawn-Ring 10–24 → 14–28 Blöcke, F-088-FOG-Präzedens),
> `velocity_stretch_factor` als explizites `0.0` wieder aufgenommen (Konvention:
> 101/102 Emitter führen das Feld) und der Textur-Generator an den Konventions-Ort
> `tools/art/gen_limbo_godray_shaft.py` verschoben (PNG byte-identisch reproduziert).
> Autoritativ für den Endzustand: `F107_GODRAY_FIX_REPORT.md`. Pfad-/Parameterangaben
> unten wurden entsprechend aktualisiert.

## 1. Erst-Verifikation (jede Prompt-Behauptung gegen den Live-Tree)

| Behauptung (Prompt) | Befund | Beweis |
|---|---|---|
| `limbo_godray.json`: `base_particle_size` 6.0 ± 4.0 | BESTÄTIGT | Datei-Read vor Edit (Zeilen 25–26) |
| `max_particles` 10, `additive: true` | BESTÄTIGT | Zeilen 6, 43 |
| Tints #C9A0FF→#A45CF2→#8A3CE8, alpha-Plateau 0.1 | BESTÄTIGT | color-Modul, Zeilen 66–98 |
| Textur `purple_wisp.png` = 8×8, Kern (231,190,255,189) | BESTÄTIGT | PIL-Dump: 8×8 RGBA, Center-Pixel exakt (231,190,255,189) |
| `random_initial_rotation: true` kippt die Quads | **ABWEICHUNG** — im Live-Tree steht `false` (Zeile 35). Die Schräg-Sheets kommen stattdessen aus `face_velocity` (§2) | Datei-Read; FaceVelocityModule-Analyse |
| Vorschlag „ggf. `velocity_stretch_factor` + `face_velocity` ergänzen" | **BEREITS VORHANDEN** (`face_velocity: true`, `velocity_stretch_factor: 3.4` seit v4-Polish 6aea52b/Wave-A 8c2bfca) — und beides ist Teil der Root Cause, nicht der Lösung (§2) | `git log/diff` auf die Datei; Veil-Bytecode-Analyse |
| GODRAYS-Window in `LimboAmbience` ~Z. 359, Array ~Z. 392 | BESTÄTIGT (Z. 359–360 bzw. 392) | Datei-Read |
| Javadoc „tall soft additive light" ~Z. 51 | BESTÄTIGT (Z. 51–54) | Datei-Read |
| Sway-Javadoc ~Z. 97 | BESTÄTIGT (Z. 97–101; `swayAmplitude` 0.9 am Window) | Datei-Read |
| `limbo.fsh` hat bereits Screen-Space-God-Rays (GodrayDir-Block am Dateiende) | BESTÄTIGT (Z. 264–282) — aber mit `lookUp`-Gate: nur sichtbar, solange die Disc-NDC nahe dem Screen liegt | Datei-Read |
| „~66 Quasar-Emitter" | **ABWEICHUNG**: es sind 102 Emitter-JSONs (davon 89 additive) | `ls`/Audit-Script §5 |
| GhostShipBuilder-Blueprint ohne Deepslate | BESTÄTIGT | `rg "DEEPSLATE" src/main/java/dev/projecteclipse/eclipse/limbo/` → 0 Treffer |

## 2. Root Cause (vier Faktoren, alle per Veil-4.3.0-Bytecode verifiziert)

Analysebasis: dekompiliertes `RenderStyle$Billboard.render`, `FaceVelocityModule.update`
und `VeilRenderType` aus `veil-neoforge-1.21.1-4.3.0.jar` (Gradle-Cache).

1. **Quad-Größe ist 2× `base_particle_size`.** Veils Billboard-Plane hat Halbkante 1
   (`PLANE_POSITIONS` = ±1) und wird mit `renderRadius` multipliziert → 6.0 ± 4.0 ergibt
   Quads von **4 bis 20 Blöcken** Kantenlänge.
2. **`velocity_stretch_factor` ist ein KONSTANTER Streckfaktor** der lokalen X-Achse
   (`POS.x *= 1 + factor`, geschwindigkeitsunabhängig). 3.4 → ×4.4 → Quads bis
   **88 Blöcke** entlang einer Achse.
3. **`face_velocity` rotiert die gestreckte Achse in die Bildschirmtiefe.** Das Modul
   setzt pitch = atan2(v.y, |v.xz|), yaw (+π/2 für Billboards); bei Abwärts-Velocity
   (0,−1,0) landet die gestreckte lokale X-Achse nach rotateX(−π/2)·rotateY(π/2) auf
   lokal −Z — und die Kamera-Orientierung wird DANACH angewendet. Ergebnis: riesige,
   schräg in die Szene gekippte Sheets statt vertikaler Schächte („Lichtschächte sollten
   vertikal stehen" — genau das konnte diese Pipeline nie liefern).
4. **8×8-Textur + Nearest-Sampling + additive Stapelung.** Der Quasar-RenderType bindet
   Texturen mit `TextureStateShard(…, blur=false, mipmap=false)` → Nearest-Neighbor. Ein
   8×8-Sprite auf 12–20 Blöcken = 1.5–2.5 Blöcke pro Texel → die gemeldeten „harten,
   gestuften Quad-Kanten". Blending ist `ADDITIVE_TRANSPARENCY` (SRC_ALPHA, ONE):
   pro Quad-Kern ≈ 0.9 (Textur) × 0.8 (Tint #C9A0FF) × 0.74 (Textur-Alpha) × 0.1
   (Vertex-Alpha) ≈ **0.053 pro Kanal — 10 Quads pro Emitter × 3 Emitter stapeln auf
   ≈ 0.5+ und waschen Richtung Weiß-Rosa** (die „blasse Wand").

Das „kommt in Wellen": `particle_lifetime` 100 ± 20 (~5 s) + Window-Kadenz — beim
manuellen Spawn steht die Wand nach ~5 s voll (10 Partikel im Steady-State) und
verschwindet mit dem Partikel-Lifetime wieder; im Ambience-Betrieb pulsiert sie mit dem
Rolling-Window.

## 3. Entscheidung: (b) dedizierte Godray-Textur + (a) Retune — Window bleibt

**Gegen (c) Stilllegen:** Der Post-Shader-Godray (`limbo.fsh`, GodrayDir-Block) ist
screen-space und über `lookUp = 1 − smoothstep(0.9, 2.6, length(GodrayDir))` gated — er
existiert nur, solange man Richtung Eclipse-Disc schaut, und die Klassen-Javadoc von
`LimboAmbience` (Z. 52–54) dokumentiert explizit, dass die World-Space-Schächte auch
unter Iris überleben, wenn die Post-Pipeline abgeschaltet ist. Der Mehrwert gegenüber dem
Post-Shader ist also nicht null → Window-Mechanik (Sway, Kadenz, Javadoc ~Z. 97) bleibt
erhalten; die Emitter-Optik wurde ersetzt. (Completion-Pass: Window-Rahmen zusätzlich
entschärft — maxLive 2, Ring 14–28 — siehe Addendum oben.)

**Neue Textur `limbo_godray_shaft.png` (64×256, eingecheckt):** deterministisch generiert
via `tools/art/gen_limbo_godray_shaft.py` (PIL, pure Mathematik, kein Random). Vertikaler
Schacht: horizontaler Gauss-Falloff (Kern ~25 % der Quad-Breite), symmetrische
End-Fades oben/unten, äußerste Texel-Spalten/-Zeilen exakt Alpha 0 (keine sichtbaren
Quad-Kanten möglich), sanfte Langwellen-Helligkeitsvariation gegen den „Uniform-Balken"-
Look. **Dunkel vorgetönt** (Kern #8C69C8 → Rand #5A3C96, beide unter halber Luminanz):
die Tönung hängt nicht allein am Vertex-Tint → llvmpipe und echte GPUs lesen dasselbe
dunkle Violett. 256 px Höhe ≈ 35 Texel/Block auf einem 7-Block-Quad → auch mit
Nearest-Sampling stufenfrei.

**Retune-Mathematik:** Kern-Beitrag pro Quad ≈ 0.78 (Textur-Blau) × 0.72 (Tint #7A55B8)
× 0.67 (Textur-Alpha) × 0.06 (Vertex-Alpha) ≈ **0.023 Blau / 0.011 Rot** — bei ~3–4
Partikeln pro Emitter und seltener Kern-Überlappung bleibt der Worst Case < 0.08:
ein subtiler dunkel-violetter Schacht, nie eine Wand. Geometrie: plain Billboard
(kein face_velocity/stretch mehr), Schacht-Vertikalität kommt aus der Textur — screen-up-
ausgerichtet, was für weiches Licht der korrekte Billboard-Kompromiss ist.

### Vorher/Nachher-Parameter (limbo_godray.json)

| Parameter | Vorher | Nachher | Begründung |
|---|---|---|---|
| `rate` | 10 | 30 | Steady-State ~3.3 statt 10 Partikel pro Emitter |
| `max_particles` | 10 | 4 | Stapel-Deckel: 2 Windows × 4 = max. 8 Schächte statt 30 Wände |
| `base_particle_size` | 6.0 | 3.5 | Quad 7 statt 12 Blöcke Kante (Veil: Kante = 2×size) |
| `particle_size_variation` | 4.0 | 1.0 | Ausreißer bis 20-Block-Quads eliminiert |
| `face_velocity` | true | false | Root-Cause-Geometrie (§2.3): kippte die Sheets in die Tiefe |
| `velocity_stretch_factor` | 3.4 | 0.0 (explizit) | Konstanter ×4.4-Stretch = Wandbreite; explizit statt Codec-Default (Schema-Konvention) |
| `sprite` | `purple_wisp.png` (8×8) | `limbo_godray_shaft.png` (64×256) | Stufenfrei + Schachtform + dunkel vorgetönt |
| rgb_points | #C9A0FF→#A45CF2→#8A3CE8 | #7A55B8→#5F3D9E→#46297A | V2.1 „dunkle Birth-Tints"; ~halbe Luminanz |
| alpha-Plateau | 0.1 | 0.06 | Additiv-Budget (§3 Mathematik) |
| unverändert | shape/cylinder, speed 0.022, lifetime 100±20, wind-Modul, loop, `max_lifetime` 20 | | Spawn-Verteilung, Sink-Drift und Window-Mechanik waren nicht das Problem |

Java (Stand nach Completion-Pass): `GODRAYS`-Window-Konstante in `LimboAmbience.java`
entschärft — maxLive 3 → **2**, Spawn-Ring 10–24 → **14–28** Blöcke; Kadenz 90–130,
yBias 8–15 und Sway 0.9 unverändert. Javadoc trägt den F-107-Absatz.

## 4. Audit der Limbo-Schwester-Windows (Auftrag 2)

Risiko-Kombi = additive + große base_particle_size + hohe max_particles + helle Tints
+ lange Lifetime. Befund: **kein weiterer Fix nötig** — der Godray war der einzige
Ausreißer.

| Emitter | additive | size ±var | max_p | hellster Tint (Lum) | max α | Befund |
|---|---|---|---|---|---|---|
| `limbo_motes` | ja | 0.055 ± 0.03 | 64 | #B98CFF (0.63) | 0.28 | OK — winzige Quads (~0.17 Block), Stapelung physisch harmlos |
| `limbo_motes_near` | ja | 0.55 ± 0.3 | 12 | #B98CFF (0.63) | 0.07 | OK — Bokeh-Layer, sehr niedriges Alpha, Garnish-Tier (reducedFx-clear) |
| `limbo_fog` | **nein** (alpha-blend) | 8.0 ± 7.0 | 20 | #47257A (0.13) | 0.13 | OK — dunkle Tints + Normal-Blending: kann nicht Richtung Weiß stapeln |
| `limbo_fogbank` | **nein** (alpha-blend) | 26.0 ± 6.0 | 8 | #2E1755 (0.09) | 0.1 | OK — live als subtil bewiesen (A/B des Hauptagenten); NICHT angefasst |
| `limbo_moths` | ja | 0.15 ± 0.05 | 12 | #D9FFE9 (0.96) | 0.5 | OK — hell, aber 0.15-Block-Quads an Soul-Lights: Punktfunken, keine Fläche |
| `limbo_embers` | ja | 0.12 ± 0.06 | 40 | #4FD8A0 (0.65) | 0.45 | OK — Mini-Quads in Säulenform an den 3 Spires, ≤160-Block-Gate |

Merksatz fürs nächste Tuning: Die Fog-Familie zeigt das korrekte Muster für GROSSE
Flächen — alpha-blend + dunkle Tints; additiv ist im Limbo den kleinen Punkt-Effekten
vorbehalten. Der Godray folgt jetzt einem dritten Muster: additiv + klein + dunkel
vorgetönte High-Res-Textur.

## 5. Repo-weiter Kurz-Audit (Auftrag 3 — report-only, KEINE Fixes)

Scan aller 102 Emitter (89 additive) auf additive + `base_particle_size` ≥ 8 + helle
rgb_points: **0 Treffer** (nach dem F-107-Fix; vorher war `limbo_godray` der einzige).
Da `velocity_stretch_factor` den Footprint konstant multipliziert (§2.2), wurde
zusätzlich der effektive Footprint 2×(size+var)×(1+stretch) geprüft. Kandidaten ≥ 5
Blöcke:

| Emitter | Footprint | Lum/α | Lifetime/loop | 1-Zeilen-Einschätzung |
|---|---|---|---|---|
| `storm_godfinger` | bis ~45 Blöcke (4.5±2.5, stretch 2.2) | 0.96 / 0.1 | 70 t, loop, max_p 8 | **Einziger echter Follow-up-Kandidat**: exakt das F-107-Rezept (hell-additiv + Stretch + 8×8-wisp + loop), aber ≤2 Emitter, doppelt gegated (EyeDim ≥ 0.3 + Interior ≥ 0.5, nur ≤48 Blöcke am Sturm-Auge) und als dramatische Lichtfinger im dunklen Dom GEWOLLT auffällig — bei nächster Storm-Abnahme prüfen, ob die Sheets dort als Kanten lesen; ggf. dieselbe Shaft-Textur verwenden |
| `impact_light` | ~8.8 (3.6±0.8) | 1.0 / 0.95 | 7 t, kein loop | OK — Sub-Sekunden-Blitz-Burst, genau der Fall „kurzer Burst = additiv-hell OK" |
| `wand_soulbind_flash` | ~7.6 (3.2±0.6) | 1.0 / 1.0 | 6 t, kein loop | OK — Einmal-Flash beim Soulbind |
| `storm_rain_sheet` | ~5.1 (0.55±0.25, stretch 2.2) | 0.59 / 0.31 | 14 t, loop | OK — Regen-Streaks: klein, kurzlebig, gedämpfter Tint |

Alle übrigen additiven Emitter liegen unter ~3 Blöcken Footprint (Bursts, Funken,
Ringe) — unauffällig.

## 6. Gates

- **JSON**: `python3 -c "json.load(...)"` auf `limbo_godray.json` → OK.
- **Java** (Javadoc-Edit): `flock /tmp/gradle.lock ./gradlew compileJava --offline
  --console=plain` → **`BUILD SUCCESSFUL in 1s`** (2 actionable tasks: 1 executed,
  1 up-to-date).
- **Textur-Generator**: `python3 tools/art/gen_limbo_godray_shaft.py` → 64×256 RGBA,
  Rand-Alpha überall exakt 0, Kern (140,105,200,171); deterministisch
  (pure Mathematik, kein Random-Seed), byte-identisch reproduzierbar.

## 7. RCON-Abnahme-Drehbuch für den Hauptagenten

Ausgangslage: Dev steht auf dem Limbo-Schiff bei ca. (0.5, 53, 5.5). Der Client cached
Assets — nach dem Deploy des neuen JARs/Resource-Reloads sicherstellen, dass Textur +
JSON geladen sind (Client-Neustart oder F3+T, je nach Deploy-Weg der Session).

1. **Manueller A/B-Spawn** (identisch zur Beweisführung F-107):
   `execute as Dev run eclipsefx emitter "eclipse:limbo_godray" 0.5 50 25.5`
   — gleicher Spawnpunkt wie beim historischen `/tmp/f107_ab_godray_5s.png`.
2. **Screenshot-Timing**: Partikel-Lifetime 100 ± 20 t → Steady-State (~3–4 Partikel)
   ab ~90 t. Screenshot bei **t ≈ 5 s** nach Spawn (Vergleichszeitpunkt des
   historischen Bildes) und optional ein zweiter bei ~8 s.
3. **SOLL-Bild**: 3–4 **schmale vertikale** dunkel-violette Lichtschächte (~1–2 Blöcke
   sichtbare Kernbreite, 5–9 Blöcke hoch), weiche Ränder ohne Pixel-Stufen, langsam
   sinkend/driftend. **KEINE** blasse rosa Fläche, **keine** harten Quad-Kanten,
   **keine** schräg gekippten Sheets; Himmel/Fog hinter den Schächten bleibt klar
   ablesbar. Erwartete additive Aufhellung im Schacht-Kern grob +0.02–0.08 (deutlich
   unter jeder „Wand"-Schwelle).
4. **Ambience-Abnahme**: nach dem manuellen Test ~2–3 min normal auf dem Schiff stehen
   bleiben (GODRAYS-Window: max 2 Emitter, Kadenz 90–130 t, Ring 14–28 Blöcke, Höhenband
   +8…+15 über Wasser) und den linken/rechten Bildrand beobachten: der periodische „Wellen"-Effekt
   (Wand kommt/geht) darf nicht mehr auftreten; stattdessen wandernde einzelne Schächte,
   die mit dem Schiffs-Roll (~12.5 s Periode) schwanken — Sway-Mechanik unverändert.
5. **Negativkontrolle** (unverändert): `execute as Dev run eclipsefx emitter
   "eclipse:limbo_fogbank" 0.5 50 25.5` muss weiterhin wie `/tmp/f107_ab_fogbank.png`
   (fast unsichtbar-subtil) aussehen — Fogbank wurde nicht angefasst.

## 8. Protokoll: Steinplattform unter dem Boot (vom Hauptagenten bereits erledigt)

Die „Steinplattform unter dem Boot" war eine verwaiste, 1 Block dicke
Deepslate-Testplatte (735 Blöcke, y=50, ~x −16..8 / z −20..20) aus einer früheren
Foto-Session — per RCON-`fill` entfernt; **kein Code-Fix nötig**. Verifiziert:
`rg "DEEPSLATE" src/main/java/dev/projecteclipse/eclipse/limbo/` → 0 Treffer, der
GhostShipBuilder-Blueprint enthält kein Deepslate.

## 9. Geänderte/neue Dateien

- `src/main/resources/assets/eclipse/quasar/emitters/limbo_godray.json` — F-107-Retune (§3)
- `src/main/resources/assets/eclipse/textures/particle/limbo_godray_shaft.png` — NEU, 64×256 (generiert)
- `tools/art/gen_limbo_godray_shaft.py` — NEU, deterministischer Generator
- `src/main/java/dev/projecteclipse/eclipse/veilfx/LimboAmbience.java` — GODRAYS-Window-Konstante (maxLive 2, Ring 14–28) + F-107-Javadoc
- `docs/plans_v3/session_0730/F107_LIMBO_VISUAL_FIXES_REPORT.md` — dieser Report
- `docs/plans_v3/session_0730/F107_GODRAY_FIX_REPORT.md` — Completion-Report (Endzustand)
