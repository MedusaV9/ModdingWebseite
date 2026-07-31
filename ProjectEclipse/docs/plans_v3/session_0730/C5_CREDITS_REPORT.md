# C5 — Credits / End-Feinschliff (FX-Welle 13, Session 0730)

Scope aus `FX_CENSUS_WAVE13.md` §7 Zeile C5. Branch `cursor/project-eclipse`, **nicht
committet** — der Integrator committet zentral.

---

## 0. Kurzfassung

| # | Auftrag | Status | Beweis |
|---|---------|--------|--------|
| 1 | `black_hole.fsh` NPE-Mine entschärfen | **fertig** | Round-Trip: HEAD `EMIT-FAIL`, jetzt `OK` |
| 1b | Rotverschiebungs-Freeze `[b7]` | **fertig** | Ablationsmessung + gerenderte Leiter |
| 2 | `credits4_jetburst` `lifetimeByEmitterSpeed` | **fertig, mit dokumentierter Grenze** | Jar-Autopsie + Laufzeit-Probe |
| 3 | `end_arrival*` auf Welle-13 | **fertig** | 13 Motion-Terme korrigiert, Style-Audit grün |
| 4 | `end_void_wisps` GPU-Instancing | **war schon fertig** — kein Eingriff | Flags im ausgelieferten `.fx` verifiziert |
| 5 | `credits*` Welle-13-Politur | **fertig** | 11 Motion-Terme korrigiert, Style-Audit grün |

`validate --lint`: **0 neue Findings** (267 Dateien, 27 grandfathered = Baseline).
`./gradlew compileJava processResources`: **BUILD SUCCESSFUL**.

---

## 1. `black_hole.fsh` — der eigentliche Fix

### 1.1 Die Mine, reproduziert

B4s Befund stimmt, und ich habe ihn nicht geglaubt sondern nachgestellt: die HEAD-Fassung
läuft im echten Veil-Parser (`glsl-processor 0.2.3`, `GlslParser.preprocessParse` →
`tree.toSourceString`) in

```
EMIT-FAIL -> NullPointerException: Cannot invoke "Object.hashCode()" because "this.value" is null
    at GlslReturnNode.hashCode(GlslReturnNode.java:57)
    at GlslNodeList.hashCode  <- GlslFunctionNode.hashCode
    at HashMap.get            <- GlslTreeStringWriter.visitFunction(:90)
```

Das ist genau das stille Abmelden: Veil loggt `Couldn't parse shader eclipse:black_hole`,
registriert das Programm nie, und der ganze Finale-Pass ist zur Laufzeit ein No-op.
**`glslangValidator` sieht davon nichts** — er kompiliert die kaputte Datei anstandslos.
Deshalb ist der Round-Trip ein eigenes Gate und nicht durch den Validator ersetzbar.

### 1.2 Der Fix und eine Präzisierung von B4s Regel 2

Struktureller Fix wie von B4 vorgezeichnet: das `return;` im Idle-Gate ist durch ein
verschachteltes `if/else` in `main()` ersetzt, der `else`-Arm setzt `color` direkt aus dem
Sampler. Zusätzlich sind die beiden `FXWAVE-9 #4`-Kommentare entschärft.

Dabei ist mir aufgefallen, dass die Datei ihr eigenes Gesetz verletzte: das PARSER-LAW-Block
verbot „kein streunendes `#` irgendwo, Kommentare eingeschlossen" und schrieb zwei Zeilen
später selbst `` `#include` `` in einen Kommentar. Statt zu raten habe ich abliert — vier
Builds derselben Datei, die sich nur in (a) einem wieder eingesetzten `return;` und (b) der
**Position** eines streunenden `#` unterscheiden:

| Build | Ergebnis |
|---|---|
| `#` im Datei-Header (über `#include`) + `return;` | **OK** |
| `#` **im Funktionsrumpf** + `return;` | **EMIT-FAIL** (die NPE) |
| `#` im Funktionsrumpf, kein `return;` | **OK** |
| weder noch | **OK** |

Also: **das wertlose `return;` ist die Ladung, ein `#` im Funktionsrumpf ist nur der Zünder.**
Regel 1 allein genügt (Zeile 3), Regel 2 allein nicht (Zeile 2). Ein `#` oberhalb von
`#include` registriert nie einen Node-Marker (Zeile 1) — der Kommentar im Header ist also
beweisbar harmlos. Der PARSER-LAW-Block im Shader trägt diese Messung jetzt wörtlich, damit
der Nächste nicht dieselbe halbe Regel erbt.

### 1.3 `[b7]` Rotverschiebungs-Freeze

Schwarzschild-Dilatation `d(r) = sqrt(1 − r_s/r)` um den **gezeichneten** Rand
`r_s = coreR·1.6` (die äußere Kante von `[b3]`s Blackout — mit `r_s = coreR` läge die ganze
`d < 0.5`-Schale *innerhalb* des Schwarz, der Freeze wäre mathematisch da und optisch
unsichtbar). Scharfgeschaltet über `smoothstep(0.84, 0.98, Strength)`, also exakt über der
Lücke zwischen Leitersprosse 4 (0.8) und 5 (0.91) der Server-Intensitätsleiter.

Drei Angriffspunkte, jeder in der einzigen dort sicheren Form:

- **Temporal, konstant.** Alle Nahfeld-Uhren (Photonring-Shimmer, Sub-Ring-Beads,
  Disc-Shimmer, Hotspot-Orbits und -Flares, Dash-Flow, Starfield-Rotation und -Twinkle)
  laufen auf `Time · FREEZE_DILATION` mit **einem** konstanten Faktor —
  `FREEZE_DILATION_RIM = 0.25` für die Rand-Schale, `0.60` für die viel breitere Disc.
- **Radial, räumlich.** Die Phasen-Koordinate der Sterndashes wird am Rand gestreckt
  (`FREEZE_WARP_L`), die Einwärtsdrift fällt auf ~1/4.5 der Fernfeldrate. Das Fenster
  rutscht mit (`winLo/winHi` → 1.50/2.10·coreR), damit die gestauten Dashes noch gezeichnet
  werden statt kurz davor weggeschnitten zu sein.
- **Radial, chromatisch.** Ausbluten nach `REDSHIFT_EMBER` über den Per-Fragment-Gradienten
  `1 − d`, gewichtet mit `cos(theta)`: der zurückweichende (Bildschirm-links) Limbus
  rötet 1.9× stärker. Farbe kann nicht aliasen, also behält dieser Term die exakte Wurzel.

Damit wird aus dem harten `Szene → Schwarz` am Horizont ein `Szene → Rot → Schwarz`.

**Warum die Uhr räumlich konstant ist und das keine Vereinfachung ist.**
`CreditsBlackHolePostFx` speist `Time = (fxTicks % 72000)/20`, und `fxTicks` zählt ab
World-Join — `Time` kommt also routinemäßig in **Hunderten bis Tausenden** von Sekunden an.
Eine Per-Fragment-Uhr `Time·d(r)` hat dann einen radialen Phasengradienten `Time·d'(r)`, der
mit `Time` unbeschränkt wächst; `sqrt(1 − r_s/r)` ist der schlimmste Fall, weil seine
Steigung am Rand unendlich ist. Gemessen bereits bei `Time = 20 s`: das gelinste Starfield
rutschte am Rand **über eine halbe Zelle pro Pixel**, das „eingefrorene" Feld zerfiel in
funkelndes Hash, und seine zeitliche Korrelation kam **niedriger** heraus als ganz ohne
Freeze. Diese Version wurde verworfen.

Zwei Uhren bleiben absichtlich auf rohem `Time`, beides wären sonst Bugs:

- der Horizont-`wobble`, weil `coreR` daraus abgeleitet ist und `r_s` aus `coreR` — ihn zu
  bremsen schließt eine Zirkularität. (Aus demselben Grund rechnet die Freeze-Geometrie mit
  dem **unwobbelnden** `core`: als sie an `coreR` hing, jitterte der ±4-%-Shimmer das ganze
  Dash-Feld radial, und die Dash-Ebene maß *schlechter* als ohne Freeze.)
- die Polar-Jets, weil ein Jet ein **Ausfluss** entlang der Achse ist. Einen Ausfluss gegen
  den Rand einzufrieren, den er gerade verlässt, ist die falsche Physik.

### 1.4 Verifikation

| Gesetz | Ergebnis |
|---|---|
| L1 Idle (`Strength 0`) bit-identisch, 3 Uhren | `array_equal = True` |
| L2 Sprossen 1–4 gegen HEAD | `max|delta| = 0.000000` — identisch |
| L2 Sprossen 5–6 | `1.38` / `1.32` — geändert, wie beabsichtigt |
| L3 Freeze (Einzelebenen-Ablation, `c5_layers.py`) | Ring `+0.003`, Disc `+0.075`, Star `+0.024` Korrelationsgewinn gegen die Clock-on-Ablation |
| L3 Dash-Radialdrift (Kymograph, geteilter Strahl) | nah `−0.165` vs. fern `−0.216` core/s → nah läuft mit 0.76× der Fernrate |
| L3c Alias-Wächter bei `Time ≈ 3000 s` | Gewinn bleibt positiv (`+0.091` / `+0.014`) |
| L3c Starfield-Hochfrequenzenergie | `star_on` ≤ `star_off` bei allen drei Zeiten — kein Hash |
| L5a `reducedFx` Flimmerrate (Per-Frame-Ableitung) | C5 `0.00034` < HEAD `0.00056` |
| L5b Endlichkeit / Werteobergrenze über den vollen `Time`-Wrap | `0` nicht-endliche, Max `3.83` < HEAD `3.94` |
| glsl-processor Round-Trip | `OK (8434 chars)` |
| `glslangValidator` + `gzvalidate` Bare-Return/Stray-`#`-Lint | `OK` |

Der Freeze ist auf dem **Komposit**-Frame nicht messbar und der erste Messversuch war
falsch: Ring, Sub-Ring, Disc, Hotspots, Jets, Dashes und das gelinste Starfield überlappen
in jedem Annulus mit verschiedenen Uhren, `[b7]` schiebt zusätzlich *mehr* Dash-Inhalt in
genau das Band hinein, in dem gemessen wird, und die ungefrorenen Jets kreuzen alles. Die
ursprüngliche Metrik `mean|frame(t) − frame(t+0.5s)|` verwechselte damit Inhaltszuwachs mit
Bewegung und meldete „Bewegung nimmt zu". `c5_layers.py` rendert deshalb **eine Ebene nach
der anderen** auf schwarzem Input und misst jede gegen ihre *eigene* Clock-on-Ablation
(Pearson-Korrelation). Ebenso war die erste L4-Messung (Limbus-Verhältnis 3.1× statt der
konstruierten 1.9×) ein Szenen-Artefakt — das Bleed skaliert mit der lokalen Luminanz, und
die Testszene war nicht links/rechts-symmetrisch; gegen ein flaches Graufeld gemessen kommen
1.8× heraus.

Die JSONs (`post/black_hole.json`, `shaders/program/black_hole.json`) brauchten keine
Änderung: `[b7]` führt keine neue Uniform ein, alle sieben deklarierten Uniforms werden von
`CreditsBlackHolePostFx` gefüttert.

---

## 2. Der Einheiten-Bug — der rote Faden durch Punkt 3 und 5

Aus der Photon-Jar dekompiliert (`VelocityOverLifetimeSetting.getVelocity`):

| Feld | Faktor | Autorierte Einheit |
|---|---|---|
| `startSpeed`, `velocityOverLifetime.linear` | `× 0.05`/Tick | Blöcke / **Sekunde** |
| `velocityOverLifetime.orbital` (AngularVelocity) | `× 0.05`/Tick | Radiant / **Sekunde** |
| `velocityOverLifetime.radial` | **`× 0.01`**/Tick | eine eigene Skala — für dieselbe Strecke ist eine Radialzahl immer **5×** die lineare |

Die C5-Generatoren hatten alle drei durchgehend so autoriert, als wären es Blöcke/Tick. Das
ist derselbe Schlupf, den B6 in `ceremony_fx.py` und C4 quer durch `worldevents_fx.py` fand.
Ich habe **jede** Bewegungszahl aus der Strecke zurückgerechnet, die ihr eigener Kommentar
(oder ihre eigene Cull-Box) verspricht: `blocks = v × 0.05 × lifeTicks`, radial `× 0.01`.

Gemessen wird nicht am Generator-Quelltext, sondern an der **ausgelieferten** `.fx`: der
Probe deserialisiert die Datei mit der echten Photon-Jar und lässt ihre eigenen
`NumberFunction`s laufen. 24 Terme sind messbar korrigiert; die schlimmsten:

| Asset | Emitter | Term | HEAD | C5 | × |
|---|---|---|---|---|---|
| `end_arrival2_island_ring` | `rim_scatter` | radial | 0.2–0.6 b | 17–47 b | 78 |
| `black_hole_maw` | `maw_swirl_inner` | radial | 0.1 b | 4.4–7.5 b | 75 |
| `black_hole_maw` | `maw_infall` | radial | 0.3–0.4 b | 16.6–29.6 b | 74 |
| `black_hole_maw` | `maw_star_streaks` | radial | 0.3–0.5 b | 20.7–33.3 b | 67 |
| `credits3_precrack` | `precrack_dust` | linear.y | 0.2–0.7 b | 6–15.7 b | 22 |
| `credits_collapse` | `collapse_trail_dust` | linear.y | 1.1–2.9 b | 26–45.7 b | 16 |
| `credits4_jetburst` | `jetburst_up/down` | startSpeed | 1.2–2.7 b | **40.8 b** | 15 |

Vollständige Tabelle: Artefakt `c5_units_before_after.txt`.

**Was das konkret kaputt gemacht hat.** `maw_infall` ist als „motes pulled from a wide shell
straight into the center" dokumentiert, wird auf einer 32-Block-Schale geboren und legte
0.3 Blöcke zurück — 1 % des Wegs, also eine stehende Punktwolke statt eines Einfalls.
`collapse_trail_dust` ist der Vorhang, der „die Trümmer verfolgt", und dessen eigene Cull-Box
auf +52 dimensioniert ist; er stieg 2.9 Blöcke. Die Polar-Jets in `credits4_jetburst` sollen
laut Kommentar „~40 Blöcke entlang ±Y" erreichen, damit sie das ~26-Block-Maw überhaupt
verlassen, und der Shader strobt passende Säulen dazu — sie kamen 1.2–2.7 Blöcke weit.

**Kollateralschaden bei Stretched Billboards.** `TileParticle` zeichnet sie mit
`stretch = lengthScale + |velocity| × velocityScale`, `|velocity|` in Blöcken pro **Tick**.
`maw_star_streaks` — die „hard pull"-Ebene — bekam aus ihrem Radial 0.01 b/t und war damit
ein langsamer Orbital-Schmierer ohne jeden Einfall. Mit korrigiertem Radial trägt sie
0.74 b/t und zeichnet eine 0.75–1.65 Blöcke lange Linie, also länger als ihre eigene
Per-Tick-Strecke: der Strich liest sich durchgehend statt stroboskopisch.

### 2.1 Der Folgefehler, den der Einheiten-Fix selbst erzeugt hat

Photon wendet `radial` entlang `normalize(particle.localPos)` an und **re-normalisiert jeden
Tick**. Ein einwärts gerichteter Radial, der ein Partikel über `r = 0` hinausträgt, hält dort
also nicht an: der Richtungsvektor kippt und das Partikel fliegt mit derselben Rate wieder
**heraus**. Solange die Radials kaputt waren (0.2–0.5 Blöcke Reichweite) konnte das nie
passieren. Mit korrigierten Einheiten schossen vier Einwärts-Ebenen durch das Zentrum:

| Emitter | innere Spawn-Kante | max. Strecke | End-Radius |
|---|---|---|---|
| `end_arrival2_glyphs` / `gather_motes` | 6.6 | 11.2 | **−4.6** |
| `end_arrival_implosion` / `inhale` | 15.3 | 17.0 | **−1.7** |
| `end_arrival_suction` / `indraw_streaks` | 14.1 | 20.3 | **−6.2** |
| `end_arrival_puff` / `snap_in` | 2.2 | 2.4 | **−0.2** |

Ursache: ich hatte gegen den **nominalen** Shape-Radius zurückgerechnet, nicht gegen die
**innere Kante** der Spawn-Schale. Bei `sphere(radius=32, thickness=0.25)` starten Partikel
zwischen 24 und 32 — die innersten setzen die Obergrenze für alle. Alle Einwärts-Radials
sind jetzt gegen `r_inner − Marge` zurückgerechnet und einzeln nachgemessen; ein Einfall, der
laut Autorenabsicht *auf dem Punkt* landen soll (`snap_in`, `inhale`, `indraw_streaks`), darf
bei `r ≈ 0.1…1.2` ankommen, aber nie darunter. Der Audit liegt als
`c5_radial_bounce_audit.py` bei und liest die **ausgelieferten** `.fx` zurück — im
Generator-Quelltext ist das unsichtbar, weil dort nichts die Strecke gegen die Schale hält.

**Bewusst nachgerechnet und unverändert gelassen** (damit der Nächste sie nicht „mitfixt"):
`nebula_swaths` 0.012 rad/s = 6–10° über 180–300t — das *ist* „near-static".
`nebula_shooting_stars` 1.7 rad/s = 88–131° in 0.9–1.35 s auf der r=74-Schale; das sind
6.3 b/t tangential, was die Strecke auf 4.8–8.3 Blöcke zieht und damit die Per-Tick-Strecke
abdeckt. `maw_swirl_inner` 0.85 rad/s und `maw_swirl_outer` −0.28 rad/s waren in rad/Sekunde
korrekt autoriert. `braid_streaks` ist an `EndArrivalDebrisFx.STRAND_SPIN = 0.26 rad/**t**`
gekoppelt und rechnet die Java-Konstante bewusst nach `4.68–5.72 rad/s` um.

---

## 3. `credits4_jetburst` — `lifetimeByEmitterSpeed`

Der Zensus will diesen Modul-Erstnutzer. Er ist verdrahtet, **aber heute strukturell ein
No-op**, und das ist keine Vermutung sondern aus der Jar gelesen:

- `LifetimeByEmitterSpeedSetting.getLifetime(...)` liest `IParticleEmitter.getVelocity()`.
- `Emitter.update()` bildet diese Velocity als **Positionsdifferenz zwischen zwei Ticks**.
- `CreditsSequence.mapRipBeats` spawnt `credits4_jetburst` an einem statischen `fxAnchor()`.

Ein stehender Emitter hat also per Konstruktion Velocity 0, und der Modul ist die Identität.
Laufzeit-Probe an der ausgelieferten Datei, mit Photons eigener `getLifetime`:

```
lifetimeByEmitterSpeed{speedRange a=0.0 b=6.0}  base 100 -> still 100, moving-6bps 180
  [OK] speedRange parsed as authored (a=0,b=6)
  [OK] standing emitter is the identity (no-op today)
  [OK] moving emitter would stretch the knots
```

Das heißt: sauber scharfgeschaltet, schadfrei, und sobald jemand den Anchor an ein bewegtes
Objekt hängt, greift er sofort mit +80 % Lebensdauer. Den *gewünschten Leseeindruck* liefert
heute stattdessen ein **Kurvenpaar über die Emitter-Progression** (`SEG_JET_DECAY`):
`start_speed` und `start_lifetime` laufen auf derselben Kurvenform, sodass der Jet-Hals die
ersten 30 % der Burst-Dauer vollen Druck hält und dann kollabiert — die Knoten *sind* am
Anfang schnell und langlebig, am Ende langsam und kurz. Gemessen: 40.8 b Reichweite bei
`t=0`, 10.2 b bei `t=1`.

`fxlib.py` wurde **nicht** angefasst (A0-Grund diese Welle).

### Querschnitts-Bug: `Range`-Codec vs. `fxlib._min_max()` (Patch-Snippet für A0)

`fxlib._min_max()` schreibt `min`/`max`, Photons `Range`-Codec
(`com.lowdragmc.lowdraglib2.math.Range`) erwartet aber `a`/`b`. Jedes `speedRange`, das über
den Helfer läuft, deserialisiert damit auf die Defaults statt auf die autorierten Grenzen.
In `credits4_fx.py` ist der Range deshalb von Hand mit `a`/`b` gebaut (und die Probe oben
liest `a=0, b=6` bzw. `a=12, b=24` korrekt zurück). Der eigentliche Fix gehört in `fxlib`:

```python
# fxlib.py — _min_max() für Range-Felder (speedRange, sizeRange, ...)
def _range(lo, hi):
    """LDLib2 `Range` erwartet a/b, nicht min/max — siehe Range.CODEC."""
    return {"a": F(lo), "b": F(hi)}
```

Betrifft alle Generatoren, die `colorBySpeed` / `sizeBySpeed` / `lifetimeByEmitterSpeed`
benutzen (u. a. `echo_grove_fx.py`, `ferryman2_fx.py`) — deshalb A0, nicht C5.

---

## 4. `end_arrival*` — Welle-13

Beide Generatoren, V1 (`end_arrival_fx.py`, 21 Emitter) und V2 (`end_arrival2_fx.py`,
9 Emitter), auf denselben Stand gezogen:

- **Einheiten** nachgerechnet wie in §2. Die dicksten Brocken: `climb_streaks` (dessen
  Kommentar wörtlich „~2 b/t" sagte) stieg 13 der 260 Blöcke der Säule und ließ den Rest
  leer — jetzt 143–268 Blöcke, also die ganze autorierte Säule; `rim_scatter` streute
  0.2–0.6 Blöcke auf einem Ring, der 17–47 verlangt; `maw_drip` tropfte 0.4–1.3 Blöcke.
- **`random_gradient`** über `varied()` auf jedem Emitter mit echter Population.
- **Dunkle Birth-Tints** (V2.1-Stacking-Gesetz): jede Rampe öffnet unterhalb ihres *eigenen*
  Fade-Ziels. Das brauchte zwei Anläufe — die erste Runde teilte einen Birth-Tint zwischen
  additiven Violett-Rampen und den fast schwarzen Rauch-Rampen, was für den Rauch eine
  *Aufhellung* war. Jetzt getrennt: `VOID_BIRTH`/`DEEP_BIRTH` für additiv,
  `SMOKE_BIRTH = (0.022, 0.012, 0.038)` für Rauch/Staub.
- **HDR** auf 1.45 geklemmt, Kanalverhältnis (= Farbton) erhalten.

---

## 5. `end_void_wisps` — GPU-Instancing: war schon fertig

Kein Eingriff nötig und kein Eingriff getan. Der Builder liegt in `build_world_fx.py`, das
laut eigenem Header (Zeilen 31/59) C1/A6/F-096 gehört — nicht C5. Der ausgelieferte
`end_void_wisps.fx` trägt bereits alles, was der Zensus-Eintrag verlangt, aus der Datei
zurückgelesen:

```
useGPUInstance     B(1)
parallelUpdate     B(1)
parallelRendering  B(1)
maxParticles       I(1200)
cullBox            min(-110,-20,-110) max(110,30,110)
```

Ein Draw-Call, Parallel-Update legal (keine Physik, kein Level-Zugriff — `FX_FORMAT` §3.1),
Cull-Box für die Off-Screen-Skips. Der Zensus-Eintrag ist erledigt, nur noch nicht abgehakt.

---

## 6. `credits*` — Welle-13-Politur

`credits2_fx.py` (`credits_collapse`, `black_hole_maw`) und `credits3_fx.py`
(`credits3_precrack`, `credits3_nebula`) haben dieselbe Behandlung wie `credits4` bekommen:
Einheiten aus §2, `varied()`, dunkle Birth-Tints, HDR-Klemme.

Ausnahmen mit Begründung, damit sie nicht als Lücke gelesen werden: `collapse_ring`,
`collapse_aftershock`, `collapse_core_flash`, `platebreak_flash` und `precrack_pops` sind
**Ein-Quad-Blitze** mit `max_particles ≤ 4`, deren Bursts nie überlappen — sie sind absichtlich
snap-hell, ein Birth-Tint würde dort nur den Knall abstumpfen. Nur ihr HDR-Peak ist geklemmt.
`maw_rim` dagegen **bekommt** einen Birth-Tint: seine 46t-Pulse überleben ihr eigenes
42t-Refire-Intervall, zwei Rim-Scheiben überlappen also immer 4 Ticks lang.

Style-Audit über die gesamte C5-Fläche (liest die ausgelieferten `.fx` zurück):

```
C5 STYLE: 58 emitter(s), random_gradient on 46, all HDR/birth checks passed
```

Die 12 ohne `random_gradient` sind genau die Ein-Quad-Blitze und Einzelringe.

---

## 7. Geänderte Dateien

**Shader (exklusiv C5)**
- `src/main/resources/assets/eclipse/pinwheel/shaders/program/black_hole.fsh`

**Photon-Generatoren (exklusiv C5)**
- `tools/photon/credits2_fx.py`
- `tools/photon/credits3_fx.py`
- `tools/photon/credits4_fx.py`
- `tools/photon/end_arrival_fx.py`
- `tools/photon/end_arrival2_fx.py`

**Generierte Assets** (`.fx` + `.fxproj`, alle über die Generatoren geschrieben)
- `credits_collapse`, `black_hole_maw`
- `credits3_precrack`, `credits3_nebula`
- `credits4_crackfront`, `credits4_platebreak`, `credits4_jetburst`
- `end_arrival_{suction,rings,pillar,maw,wisp,puff,implosion,glitter}`
- `end_arrival2_{glyphs,strand_trail,island_ring,rift_ambient}`

**Nicht angefasst:** `fxlib.py`, `ritual/*.java`, `worldgen/end/*.java`,
`VeilPostController`, `build_world_fx.py`, alle `*FxRows`-Registrare (die Cue-Ids und
autorierten Höhen haben sich nicht geändert), sämtliche BlockDisplay-Akte.

> Hinweis für den Integrator: `fxlib` vergibt pro Lauf frische `uuid4()`-Objekt-Ids, jede
> Regenerierung erzeugt also auch ohne inhaltliche Änderung einen Binärdiff in der `.fx`.
> Das ist Vorbestand von A0-Grund und der Grund, warum das `.fxproj`-Geschwister existiert.

---

## 8. Verifikations-Status

| Gate | Kommando | Ergebnis |
|---|---|---|
| FX-Lint | `python3 tools/photon/fxlib.py validate --lint` | 267 Dateien, **0 neue** error/warn, 27 grandfathered (= Baseline) |
| Java | `./gradlew compileJava processResources` | BUILD SUCCESSFUL |
| GLSL Round-Trip | `glsl-processor 0.2.3` `preprocessParse` → `toSourceString` | `OK (8434 chars)`; HEAD `EMIT-FAIL` |
| GLSL Compile | `glslangValidator` via `gzvalidate.py black_hole` | `OK` |
| Shader-Gesetze | `/tmp/c5_bh.py`, `/tmp/c5_layers.py` | `ALL LAWS PASS` / `PASS` |
| Photon-Laufzeit | `C5Probe` gegen die ausgelieferten `.fx` mit der echten Jar | `all checks passed` |
| Style (HDR/Birth/Varied) | `c5_style.py` über 58 Emitter | `all HDR/birth checks passed` |
| Radial-Bounce | `c5_radial_bounce_audit.py` über 12 Radial-Emitter | `all inward radials die at or before r=0` |

---

## 9. Test-Kommandos

```
# Credits-Replay, FX-only (keine Teleports, keine Entities, kein State-Write):
/eclipsefx sequence credits SHATTER      # credits3_precrack -> credits_collapse (+50t)
/eclipsefx sequence credits BLACKHOLE    # black_hole_maw + credits3_nebula + der Post-Pass
/eclipsefx sequence credits OUTRO
# Phasen gesamt: SHATTER HELM WHITEOUT BEACH LIGHTNING ECLIPSE BURST OUTRO BLACKHOLE

# Ganzer Lauf bzw. Abbruch:
/dev credits start        /dev credits skip        /dev end_event

# Einzelnes Asset an die Blickrichtung spawnen (Tab-Completion auf den Cue-Ids):
/eclipsefx emitter credits4_jetburst
/eclipsefx emitter black_hole_maw
/eclipsefx emitter end_arrival2_strand_trail

# Den Post-Pass isoliert fahren und die Leiter von Hand durchsteppen —
# so sieht man den Freeze ohne die ganze Sequenz:
/eclipsefx post eclipse:black_hole on
/eclipsefx uniform eclipse:black_hole Strength 0.8    # letzte Sprosse VOR dem Freeze
/eclipsefx uniform eclipse:black_hole Strength 0.91   # Freeze schaltet scharf
/eclipsefx uniform eclipse:black_hole Strength 1.0
/eclipsefx uniform eclipse:black_hole Pulse 1.0       # vertieft das Ausbluten
/eclipsefx post eclipse:black_hole off
```

---

## 10. Offene Punkte

1. **`Range`-Codec in `fxlib`** — Patch-Snippet in §3. A0-Grund, betrifft mehrere Teams.
2. **Stale Doc-Kommentar in `EndArrivalDebrisFx.java`** (B3/Sequenz-Grund, nur gelesen).
   Zeile 117 sagt „*das `end_arrival2_strand_trail`-Asset umhüllt sie bei orbital 0.22–0.30*".
   Das war die Blöcke-pro-Tick-Lesart; das Asset trägt jetzt `4.68–5.72`, also **dieselbe
   physikalische Rate** in rad/Sekunde. Nur der Kommentar driftet:
   ```java
   -     * {@code end_arrival2_strand_trail} asset sheathes them at orbital 0.22–0.30).
   +     * {@code end_arrival2_strand_trail} asset sheathes them at orbital 4.68–5.72,
   +     * i.e. the same rate in Photon's rad/SECOND authoring unit).
   ```
3. **`glsl-processor` 0.2.3 selbst** ist der eigentliche Schuldige (NPE statt Fehlermeldung
   bei `return;`). Solange die Version steht, bleibt der Round-Trip-Check ein Pflicht-Gate für
   jede `.fsh`-Änderung — `glslangValidator` allein reicht beweisbar nicht (§1.1).
4. **Der Freeze ist auf `Strength ≥ 0.84` gegated**, also nur auf den letzten zwei
   Server-Sprossen sichtbar. Wer ihn früher will, senkt `FREEZE_ARM_LO` — dann gilt die
   Bit-Identität der Sprossen 1–4 aus L2 aber nicht mehr.
