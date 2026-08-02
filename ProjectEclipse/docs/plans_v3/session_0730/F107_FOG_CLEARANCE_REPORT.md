# F-107 Teil 2 — Fog-Clearance: keine (halb)deckende Fläche mehr vor der Kamera

Anschluss an `F107_GODRAY_FIX_REPORT.md` (Teil 1, committet 8b3c241, live abgenommen).
Restbefund aus dem Abnahme-Video: bei einem Kameraschwenk schiebt weiterhin eine
**große, dunkelviolette, fast deckende vertikale Fläche am linken Bildrand** herein —
kein additives Leuchten (das war der Godray), sondern ein **alpha-geblendetes Fog-Quad
nah an der Kamera**. Verdächtige: `eclipse:limbo_fog` und `eclipse:limbo_fogbank`.

---

## 1. Entscheidung + Begründung

**Clearance-Garantie statt Symptomkosmetik.** Für FOG und FOGBANKS gilt jetzt in der
Worst-Case-Rechnung (§3): min. Spawn-Distanz − Shape-Radius − max. Half-Edge −
max. Lebenszeit-Drift Richtung Kamera ≥ **~5.4 bzw. ~7.9 Blöcke**. Vier Hebel, alle
kombiniert (die Traumhaftigkeit kommt aus Größe + Weichheit, nicht aus Ausreißern):

1. **Drift-Root-Cause gefixt** — der eigentliche Übeltäter war NICHT primär die
   Size-Variation, sondern Veils Wind-Modul (§2): eine **ungedämpfte per-Tick-
   Beschleunigung**, deren JSON-`strength` von Veil 4.3.0 stillschweigend ignoriert
   wird. Ein Fog-Sheet driftete so bis **~44 Blöcke**, eine Fogbank bis **~566 Blöcke**
   pro Partikelleben — mit Endgeschwindigkeiten von 20 bzw. 150 Blöcken/s. Jede
   Upwind-Bank fegte zwangsläufig als riesige dunkle Fläche durch die Kamera; genau
   das „Hereinschieben beim Schwenk". Fix: Fog-Wind 0.012 → 0.0003 (sanfter Schub,
   Drift ≤ 1.1); Fogbank-Wind 0.002 **plus `veil:drag` 0.96** — die Bänke laufen in
   eine **konstante Terminal-Rollgeschwindigkeit ~0.96 Blöcke/s** (Zeitkonstante
   ~1.2 s) statt endlos zu beschleunigen. Das „Rollen der Bänke in +X am Schiff
   vorbei" (IDEA-18 §3) bleibt als Design-Idee erhalten, ist jetzt aber gedeckelt:
   Drift ≤ ~6.1 Blöcke pro Leben.
2. **Size-Ausreißer gekappt**: fog 8 ± 7 → **8 ± 2** (Half-Edge max. 15 → 10),
   fogbank 26 ± 6 → **24 ± 4** (Half-Edge max. 32 → 28).
3. **Spawn-Geometrie entschärft**: Window-Ringe FOG 14–22 → **20–30**, FOGBANKS
   35–70 → **50–80** Blöcke; Emitter-Shape-Streuung (Sphere-`dimensions` sind
   DURCHMESSER, §2.1) fog 9 → **7** (Radius 3.5), fogbank 26 → **16** (Radius 8) —
   vorher konnte allein der Shape-Offset eine Fogbank 13 Blöcke Richtung Kamera
   versetzen.
4. **Textur-Stufen gekillt** (Empfehlung aus Teil 1 übernommen): dedizierte weiche,
   vorverdunkelte Sprites `limbo_fog_soft.png` (128×128, radial) und
   `limbo_fogbank_soft.png` (128×64, horizontales 2:1-Oval) ersetzen das 8×8-
   `purple_wisp.png`, das bei Nearest-Sampling (Veil-Quasar-RenderType: blur=false)
   auf 30-Block-Quads 3.75 Blöcke pro Texel als harte Stufen zeigte (§5).

Nicht angefasst: `limbo_godray` (Teil 1, live abgenommen), MOTES / NEAR_MOTES /
MOTHS / EMBERS (Audit §3.3: formale Drift ja, aber physisch kein Flächenrisiko).

## 2. Veil-4.3.0-Bytecode-Befunde (Grundlage der Drift-Formel)

Analysebasis: `veil-neoforge-1.21.1-4.3.0.jar` (Gradle-Cache), `javap -c` auf
`Sphere`, `WindForceData`, `ConstantForceModule`, `DragForceData`, `ScaleForceModule`,
`QuasarParticle`, `ParticleSettings`, `ParticleEmitter`. Ergänzend zu den Teil-1-
Befunden (Quad-Kante = 2 × size, Nearest-Sampling):

1. **Sphere-`dimensions` sind Durchmesser.** `Sphere.getPoint` skaliert eine
   Einheitsrichtung komponentenweise mit `dimensions × rand[0..1) × 0.5` → max.
   horizontaler Spawn-Offset vom Emitter-Zentrum = `dimensions/2` (fog alt: 4.5,
   fogbank alt: **13 Blöcke** — fehlte bisher in jeder Clearance-Betrachtung).
   Gleiche ×0.5-Konvention im Cylinder (Godray: Radius 0.45).
2. **`veil:wind` ist eine ungedämpfte konstante Beschleunigung.**
   `WindForceData.addModules` baut `ConstantForceModule(dir.normalize(wind_speed))`;
   `applyForce` addiert das pro Tick auf die Velocity, `QuasarParticle.tick()` macht
   danach `position += velocity` — ohne jede Dämpfung. Drift nach N Ticks (diskret):
   `x = a · N(N+1)/2`, Endgeschwindigkeit `v = a · N`.
3. **Die Wind-`strength` aus dem JSON wird NIE angewendet.** `addModules` ruft
   `setStrength` nicht auf; der Modul-Default ist 1.0. Effektive Beschleunigung =
   volle `wind_speed` (fogbank alt: 0.05 statt der vom Autor intendierten 0.025).
   Das Feld bleibt aus Schema-Gründen im JSON (Codec-Pflichtfeld), alle Rechnungen
   hier nutzen die volle `wind_speed`.
4. **`veil:drag` ist ein per-Tick-Velocity-MULTIPLIKATOR, kein Koeffizient.**
   `DragForceData(strength d)` → `ScaleForceModule`: `v ×= d` pro Tick. 0.96 = 4 %
   Verlust/Tick → mit Wind davor gilt `v(n+1) = (v(n) + a) · d`, Terminal-v =
   `a·d/(1−d)`. (Randnotiz: `limbo_moths` nutzt drag 0.01 = „sofort stoppen" — erklärt
   deren statisches Schweben; unverändert gelassen.)
5. **Initial-Velocity ist bei allen Limbo-Fog-Emittern rein vertikal.**
   `initialDirection(random)` multipliziert `initial_direction` KOMPONENTENWEISE mit
   rand[−1,1]; bei (0,1,0) bleibt (0,±v,0), skaliert mit `particle_speed` ∈
   [0.5·speed, speed]. Horizontaler v₀-Beitrag in der Drift-Formel = 0.
6. **`particle_size/lifetime_variation` sind einseitig**: Wert ∈ [base, base+var]
   (nicht ±). Max. Half-Edge = base + variation; max. Lifetime = base + variation.

## 3. Clearance-Rechnung je Fenster

Formel (horizontal, Worst Case über die volle Partikel-Lebenszeit):

```
C = D_min(Window) − R_shape(dims_h/2) − H_max(size+var) − Drift_h(t_max)
Drift_h = v0_h·t + Σ Wind/Drag   (v0_h = 0, §2.5; diskret simuliert, §6.5)
```

Konservativ: Alpha fällt ab 55 %/70 % der Lebenszeit auf 0 (bei Lebens-Ende ist das
Partikel unsichtbar); gerechnet wird trotzdem die volle Lebenszeit. Die Garantie gilt
für die Kamera-Position zum Spawn-Zeitpunkt — die ~5–6 Blöcke Marge absorbieren
zusätzlich das Deck-Umherlaufen während der Window-Lebensdauer (dieselbe Annahme wie
F-088 und F-107 Teil 1).

### 3.1 Vorher

| Fenster | D_min | R_shape | H_max | Wind a (eff., §2.3) | t_max | Drift | **Clearance** |
|---|---|---|---|---|---|---|---|
| FOG | 14 | 4.5 | 8+7 = 15 | 0.012 | 50+35 = 85 | 43.86 | **−49.36** |
| FOGBANKS | 35 | 13 | 26+6 = 32 | 0.05 | 110+40 = 150 | 566.25 | **−576.25** |
| GODRAYS | 14 | 0.45 | 3.5+1 = 4.5 | 0.008 | 100+20 = 120 | 58.08 | −49.03 |
| MOTES | 12 | 4.0 | 0.085 | 0.015 | 80+30 = 110 | 91.57 | −83.65 |
| NEAR_MOTES | 3 | 1.75 | 0.85 | 0.012 | 90+30 = 120 | 87.12 | −86.72 |
| MOTHS | 4 | 0.45 | 0.2 | drag 0.01 stoppt sofort | 40+20 = 60 | ~0 | **+3.35** |

Befund: FOG und FOGBANKS konnten die Kameraebene nicht nur schneiden (15 > 14 − 4.5
bzw. 32 > 35 − 13 schon OHNE Drift) — die ungedämpfte Wind-Beschleunigung schob jede
Upwind-Bank mit bis zu 150 Blöcken/s DURCH die Kamera. Das ist die dunkle Fläche im
Abnahme-Video.

### 3.2 Nachher (geänderte Fenster)

| Fenster | D_min | R_shape | H_max | Wind/Drag | t_max | Drift | **Clearance** |
|---|---|---|---|---|---|---|---|
| FOG | **20** | **3.5** | **8+2 = 10** | a = **0.0003** | 85 | **1.10** | **+5.40** |
| FOGBANKS | **50** | **8** | **24+4 = 28** | a = **0.002**, drag **0.96** | 150 | **6.05** | **+7.95** |

Drift-Detail (diskrete Simulation, §6.5): FOG-Endgeschwindigkeit 0.51 Blöcke/s
(sanftes Gleiten); FOGBANKS-Terminal 0.96 Blöcke/s ab ~1.2 s — konstantes, majestätisches
Rollen. Drift bis zum Ende des Alpha-Plateaus (70 % Lebenszeit): FOG 0.53, FOGBANKS 3.90
Blöcke — die sichtbare Drift ist also noch kleiner als der Worst Case.

### 3.3 Audit der unveränderten Fenster (Auftrag §3)

- **GODRAYS** (einziger weiterer Emitter mit base_particle_size ≥ 3): formale
  Clearance −49 — ein Schacht KANN über die Lebenszeit an der Kamera vorbeidriften
  (Wind 0.008, ~19 Blöcke/s am Lebensende). Per Auftrag unangetastet („Teil 1 bleibt
  wie er ist", live abgenommen). Physik des Restrisikos: additiv (kann nur aufhellen,
  nie verdecken), vorverdunkelte Textur, effektiver Peak ≈ 0.67 (Textur-α) × 0.06
  (Tint-α) ≈ 0.04, sichtbarer Kern ~25 % eines 7–9-Block-Quads ≈ 2 Blöcke — ein
  Vorbeizug liest als kurzer weicher Schimmer, nicht als Fläche. Follow-up-Kandidat
  nur, falls die nächste Live-Abnahme dort etwas zeigt (dann: gleiche Wind-Kur).
- **MOTES**: formale Drift 91.6 Blöcke, aber Quads ≤ 0.17 Blöcke, additiv, α_eff
  ≤ 0.74 × 0.28 ≈ 0.2 — Punktfunken, physisch kein Flächenrisiko. Beobachtungsnotiz:
  am Lebensende bis ~33 Blöcke/s → könnte als feine Funken-Streaks lesen; Alpha ist
  dort aber bereits im Fade-out. Unangetastet (Auftrag: „nur bei echten Verletzungen").
- **NEAR_MOTES**: by design DER Near-Camera-Bokeh-Layer (Spawn 3–7 Blöcke); Quads
  ≤ 1.7 Blöcke, additiv, α_eff ≤ 0.74 × 0.07 ≈ 0.05 — weiches Glimmen, keine Deckung.
  Unangetastet.
- **MOTHS**: an Soul-Lights gebunden, drag 0.01 (§2.4) stoppt jede Drift sofort,
  Quads ≤ 0.2 — Clearance positiv, unkritisch. **EMBERS**: fixe Spire-Positionen
  (≥ ~145 Blöcke vom Schiff), Mini-Quads — unkritisch.

## 4. Parameter vorher/nachher

### 4.1 `limbo_fog.json`

| Parameter | Vorher | Nachher | Begründung |
|---|---|---|---|
| Shape-`dimensions` (Sphere = Durchmesser) | 9.0 × 1.2 × 9.0 | **7.0 × 1.2 × 7.0** | Spawn-Offset Richtung Kamera 4.5 → 3.5 |
| `base_particle_size` | 8.0 | 8.0 | Grundgröße = der träumerische Look, bleibt |
| `particle_size_variation` | 7.0 | **2.0** | Half-Edge-Ausreißer 15 → 10 (einseitige Variation, §2.6) |
| `wind_speed` | 0.012 | **0.0003** | Drift 43.9 → 1.1 Blöcke; Endgeschw. 20 → 0.5 Blöcke/s |
| Wind-`strength` | 0.5 | 0.5 (unverändert) | Von Veil ignoriert (§2.3); bleibt für Schema-Konsistenz |
| `sprite` | `purple_wisp.png` (8×8) | **`limbo_fog_soft.png`** (128×128) | Stufenfrei + radialer Falloff + vorverdunkelt (§5) |
| unverändert | rate 8, count 2, max_particles 20, speed 0.006, lifetime 50±35, Tints #2B1546→#47257A→#381D63→#1E0F33, α-Peak 0.13, `velocity_stretch_factor` 0.0 explizit | — | Look/Dichte waren nie das Problem |

### 4.2 `limbo_fogbank.json`

| Parameter | Vorher | Nachher | Begründung |
|---|---|---|---|
| Shape-`dimensions` | 26.0 × 1.8 × 26.0 | **16.0 × 1.8 × 16.0** | Spawn-Offset Richtung Kamera 13 → 8 |
| `base_particle_size` | 26.0 | **24.0** | Half-Edge-Budget; Bank bleibt riesig (48-Block-Kante) |
| `particle_size_variation` | 6.0 | **4.0** | Half-Edge max. 32 → 28 |
| `wind_speed` | 0.05 | **0.002** | Mit Drag: Terminal ~0.96 Blöcke/s statt ungebremst 150 |
| NEU: `veil:drag` | — | **strength 0.96** | Per-Tick-Multiplikator (§2.4): deckelt das Rollen, erhält es aber (Terminal-v = a·d/(1−d) = 0.048 Blöcke/Tick) |
| `sprite` | `purple_wisp.png` (8×8) | **`limbo_fogbank_soft.png`** (128×64) | 2:1-Oval: Bank statt Ball, On-Quad-Höhe = halbe Kante (§5) |
| unverändert | rate 20, count 1, max_particles 8, speed 0.004, lifetime 110±40, Tints #1C0D33→#2E1755→#120826, α-Peak 0.1, `velocity_stretch_factor` 0.0 explizit | — | — |

### 4.3 Windows (`LimboAmbience.java`, nur Konstanten + Javadoc)

| Window | Parameter | Vorher | Nachher |
|---|---|---|---|
| FOG | Spawn-Ring | 14–22 | **20–30** |
| FOGBANKS | Spawn-Ring | 35–70 | **50–80** |
| beide | maxLive 2, Kadenz (110–160 / 140–200 t), Höhenband, kein Sway | unverändert | — |

Steady-State-Dichte unverändert: fog ~17 Partikel/Emitter (Cap 20), fogbank ~6.5
(Cap 8) — die Ringe wurden nach außen geschoben, nicht ausgedünnt.

## 5. Neue weiche Fog-Texturen + PIL-Verifikation

Generator: **`tools/art/gen_limbo_fog_soft.py`** (Stil/Ort wie
`gen_limbo_godray_shaft.py`; PIL, pure Mathematik, kein Random → deterministisch).
Beide Sprites in der Teil-1-Farbfamilie **vorverdunkelt** (Kern #8C69C8, Rand #5A3C96,
beide unter halber Luminanz) — der JSON-Tint multipliziert darauf, llvmpipe und echte
GPU lesen dasselbe dunkle Violett. Gauß-Falloff + Smoothstep-Edge-Kill → ALLE
Randtexel Alpha exakt 0 (die Quad-Kante kann nie zeichnen). Fog: 3-Lappen-Winkel-
Waviness gegen den „perfekte-Kugel"-Look; Fogbank: **2:1-Oval im UV-Raum** (v-Radius
verdoppelt — das UV-Quadrat mappt immer aufs quadratische Billboard, also muss die
Flachheit in die UV-Form) + Langwellen-Helligkeitsvariation entlang der Bank.

Peak-Deckung pro Quad: fog 0.620 (Textur-α) × 0.13 (Tint-α) ≈ **0.081** (vorher
wisp-Plateau 0.74 × 0.13 ≈ 0.096), fogbank 0.576 × 0.1 ≈ **0.058** (vorher ≈ 0.074) —
und statt des blockigen 8×8-Plateaus fällt die Deckung radial ab. Nearest-Sampling-
Stufen: Alpha-Schritt zwischen Nachbartexeln ≤ ~2/255, × Tint-α ≈ 0.0008 Deckung →
unsichtbar (vorher: 3.75 Blöcke pro Texel mit sichtbaren Kanten).

PIL-Messwerte (`Image.open`, Exit 0):

| Messpunkt | `limbo_fog_soft.png` (128×128 RGBA) | `limbo_fogbank_soft.png` (128×64 RGBA) |
|---|---|---|
| Kern (Mitte) | (64,64) = (140,105,200,**158**) | (64,32) = (140,105,200,**147**) |
| Halbradius seitlich | (96,64) = (101,70,161,34) | (96,32) = (104,72,164,39) |
| Halbhöhe unten | (64,96) = (101,70,161,35) | (64,48) = (…,**0**) — 2:1-Oval: ab halber Höhe transparent |
| Randnah (125, Mitte) | α = 0 | α = 0 |
| **max. α auf irgendeinem Randtexel** | **0** | **0** |
| globales max. α | 158 (0.620) | 147 (0.576) |

Determinismus: Generator zweimal ausgeführt, md5 identisch —
`limbo_fog_soft.png` = `ed60e6a81f709acb33539f6f1669da2d`,
`limbo_fogbank_soft.png` = `d9078b771528fc70630c0279d296fc60`.

## 6. Gate-Belege

Alle Kommandos aus `/workspace/ProjectEclipse`.

1. **JSON-Syntax**: `python3 -m json.tool src/main/resources/assets/eclipse/quasar/emitters/limbo_fog.json` → **Exit 0**; dito `limbo_fogbank.json` → **Exit 0**.
2. **processResources**: `./gradlew processResources --console=plain` → `BUILD SUCCESSFUL` → **Exit 0**.
3. **compileJava** (Java geändert: `LimboAmbience.java`): `./gradlew compileJava --console=plain` → `BUILD SUCCESSFUL` → **Exit 0**.
4. **PIL-Verifikation**: Tabelle §5 (Maße, Kern-/Rand-Messpunkte, Rand-α = 0) → Exit 0.
5. **Determinismus**: zwei Generator-Läufe, md5 beider PNGs identisch (§5).
6. **Drift-Simulation** (diskret, exakt die Veil-Tick-Semantik `v += a; [v ×= d;] x += v`):
   FOG neu 1.10 / FOGBANKS neu 6.05 / FOG alt 43.86 / FOGBANKS alt 566.25 Blöcke;
   FOGBANKS-Terminal 0.048 Blöcke/Tick = 0.96 Blöcke/s — Grundlage der Tabellen §3.

## 7. Erwartetes Sichtergebnis

Der Fog bleibt groß und träumerisch in Mittel- und Ferndistanz: weiche violette
Sheets (16–20 Blöcke Kante) ab 20 Blöcken, riesige flache 2:1-Bänke (48–56 Blöcke
breit, halb so hoch) ab 50 Blöcken, die konstant und gemächlich (~1 Block/s) in +X am
Schiff vorbeirollen. Aber: **nie mehr eine (halb)deckende Fläche am Bildrand oder vor
der Kamera** — die nächstmögliche Sheet-Kante bleibt rechnerisch ≥ ~5.4 (FOG) bzw.
~7.9 (FOGBANKS) Blöcke von der Kamera entfernt, über die gesamte Partikel-Lebenszeit
inklusive Wind-Drift, und die neuen Sprites können an ihren Rändern (Alpha exakt 0)
und in ihren Flanken (radialer Falloff statt 8×8-Plateau, keine Texel-Stufen) keine
harten Kanten mehr zeichnen. Der „Wellen"-Charakter des Limbo-Nebels (Rolling-Windows,
Kadenz, Alpha-Ein-/Ausblenden über ~3–7 s) bleibt unverändert.

Abnahme-Hinweis für den Orchestrator: Negativkontrolle wie Teil 1 (§7 des
Godray-Reports) — 2–3 min auf dem Schiff stehen/schwenken; zusätzlich einmal quer
über das Deck laufen (die ±5–6-Block-Marge deckt Deck-Bewegung). Manuelle Spawns:
`eclipsefx emitter "eclipse:limbo_fog" …` in 20 Blöcken bzw. `limbo_fogbank` in 50
Blöcken Abstand; die Bank muss als flaches, fernes Band lesen und darf beim
Vorbeirollen nie näher als ~8 Blöcke an die Kamera-Ebene heranreichen.

## 8. Geänderte/neue Dateien

| Datei | Art | Inhalt |
|---|---|---|
| `src/main/resources/assets/eclipse/quasar/emitters/limbo_fog.json` | geändert | Retune §4.1, Sprite-Wechsel |
| `src/main/resources/assets/eclipse/quasar/emitters/limbo_fogbank.json` | geändert | Retune §4.2, `veil:drag`-Modul, Sprite-Wechsel |
| `src/main/resources/assets/eclipse/textures/particle/limbo_fog_soft.png` | neu | 128×128 RGBA, weicher radialer Fog-Puff (generiert, §5) |
| `src/main/resources/assets/eclipse/textures/particle/limbo_fogbank_soft.png` | neu | 128×64 RGBA, 2:1-Oval-Bank (generiert, §5) |
| `tools/art/gen_limbo_fog_soft.py` | neu | deterministischer Generator für beide Sprites |
| `src/main/java/dev/projecteclipse/eclipse/veilfx/LimboAmbience.java` | geändert | nur FOG-/FOGBANKS-Window-Konstanten + F-107-Javadocs |
| `docs/plans_v3/session_0730/F107_FOG_CLEARANCE_REPORT.md` | neu | dieser Report |
