# CREDITS_RISK_CLOSEOUT_REPORT — F-103 TEAM B „Credits-Restrisiken"

**Mission**: Die zwei offenen Restrisiken aus `CREDITS_THOUSANDS_REPORT.md` §9 schließen —
(2) die Effigy-Welle ist ein 10-Tick-Burst (EPIC ~2.980 Transform-Writes auf ihren
Stride-Ticks, Cross-Listen-Caches als damaliger Blocker) und (3) der 57–88-Block-Sky-Drain-
Dom kommt der Kamera auf ~22 Blöcke nah (Haze-Quads könnten direkt vor der Linse aufziehen).

**Ergebnis in einem Satz**: Beide Finale-Felder (Map-Effigy UND Akkretion+Drains) sind
jetzt **phasen-gesliced** wie der F-102-Insel-Shatter — EPIC fällt von alternierenden
~2.980er/~2.120er-Stride-Spikes auf **konstant ≈ 510 Transform-Writes/Tick** (−83 % Peak),
choreo-identisch, weil alle Posen pure `(index, tick)`-Funktionen sind und alle Caches
`(pool, index)`-gekeyt (slice-stabil) bleiben; die Skydrain-Spawn-Schalen bekommen eine
**±48°-Kamera-Lune** (nativer `sphere`-`arc`-Keil 264° + Shape-Yaw 222°, gegen das
dekompilierte Photon-2.1.5-Sampling + JOML numerisch verifiziert), sodass **kein Sprite je
näher als ~60 Blöcke** an die Kamera kommt (vorher ~22) und die Haze-Quad-Kante immer
≥ ~18° außerhalb des gecrushten ~17°-FOV-Halbrahmens bleibt.

---

## Risiko 2 — Effigy-Welle als 10-Tick-Burst

### Analyse

- `CreditsMapRipAct.animate` wurde von `CreditsSequence` nur auf Stride-Ticks
  (`ripTick % PUSH_STRIDE == 0`, `PUSH_STRIDE = 10`) aufgerufen und schob dann das
  GESAMTE Feld in einem Tick: 4 Pools (Kruste + Seams + Shards + Underside) =
  700 (VERIFY) / 2.240 (STANDARD) / 2.980 (EPIC) Transform-Writes in EINEM Tick, danach
  9 Ticks Ruhe. `CreditsBlackHoleAct.animate` (Akkretion + Drains: 240 / 1.160 / 2.120)
  lief analog auf den um `PUSH_STRIDE/2` versetzten Ticks (F-102-Dephasierung, damit die
  beiden Bursts nie im selben Tick kollidieren → EPIC-Peak „nur" 2.980 statt 5.100).
- **Warum F-102 das Slicing NICHT machte (§9)**: `animate` bedient Cross-Listen-Caches
  (`crustLookCache`, `shardJobCache`, `undersideJobCache`, im Schwarzloch `dopplerCache` +
  `hotCache`), und ein naives Slicing hätte deren Edge-Trigger-Kadenz (Look-Swaps nur bei
  Job-Wechsel, nie pro Push) verändern können — Regressionsrisiko in der F-093-verifizierten
  Choreo.
- **Kern-Erkenntnis dieser Welle**: ALLE diese Caches sind `(pool, index)`-gekeyt, KEINER
  hängt am gemeinsamen Push-Tick. Die vier Pools haben unabhängige Index-Räume. Damit ist
  die Slice-Zugehörigkeit `index % PUSH_STRIDE` eine pure Funktion des Index: jeder
  Cache-Eintrag wird auf GENAU EINER Phase gelesen+geschrieben, alle `PUSH_STRIDE` Ticks —
  exakt die Kadenz (und dieselbe ≤1-Stride-Quantisierung der Look-Swaps), die der
  Ganzfeld-Push hatte. Die Caches sind von Natur aus slice-stabil; es braucht keine
  Partitionierung, nur den Beweis.

### Lösung

- `CreditsMapRipAct.animate` (Vorbild: F-102-Shatter-Slicing): läuft jetzt JEDEN Tick und
  schiebt pro Aufruf nur die Scheibe `index % PUSH_STRIDE == floorMod(ripTick, PUSH_STRIDE)`
  jedes Pools (`for (int i = phase; i < size; i += PUSH_STRIDE)`). Jedes Display reitet
  weiter ein volles 10t-Interpolationsfenster (`setTransformationInterpolationDuration(10)`
  auf Ziel `pose(index, ripTick + 10)`), nur der Push-Zeitpunkt ist pro Display
  phasen-versetzt.
- `CreditsBlackHoleAct.animate`: identisches Slicing für Akkretions- UND Drain-Population.
  Der Doppler-Refresh wählt statt des mutablen `pushWave`-Zählers 1/`dopplerStride` jeder
  Scheibe über den Voll-Stride-Wellenzähler `floorMod(actTick / PUSH_STRIDE, dopplerStride)`
  mit Selektor `(i / PUSH_STRIDE) % dopplerStride` — jedes Fragment refresht weiterhin
  genau einmal pro `dopplerStride` Strides (EPIC: alle 80t, ~20 Checks/t statt 400 in einem
  Burst-Tick; Werte bleiben quantisiert+gecacht, unveränderte Fragmente zahlen nie den
  NBT-Roundtrip). `hotCache`/Heat-Glow bleiben Crossing-Edge-only.
- `CreditsSequence`: beide Callsites feuern jetzt jeden Tick (Stride-Gate + F-102-Halb-
  Stride-Offset entfernt — die Dephasierung ist durch das Slicing obsolet, jeder Tick
  trägt ~1/10 beider Felder).

### Warum choreo-neutral (F-093-Landmarken unangetastet)

- **Stateless-Push-Gesetz**: alle Posen (`crustPose`/`seamPose`/`shardPose`/…,
  Akkretions-Spirale, Drain-Fall) sind pure Funktionen von `(index, tick)`. Gesliced wird
  nur, WANN ein Display sein nächstes 10t-Fenster bekommt (Phase = `index % 10`), nicht
  WOHIN es läuft — die stückweise-lineare Approximation derselben stetigen Kurve hat pro
  Display dieselbe Stützstellen-Dichte, nur phasenversetzte Knoten (< 1 Stride, dieselbe
  Quantisierungs-Magnitude, die der Ganzfeld-Push schon hatte).
- Spawn-Wartezeit bis zum ersten Push: unverändert ≤ 9t (vorher: bis zum nächsten
  Stride-Tick, jetzt: bis zur eigenen Phase).
- Edge-getriggerte NBT-Writes (Look-Swaps, Doppler, Heat) behalten Kadenz und
  ≤1-Stride-Quantisierung (Beweis oben); `swallowPulse`-Gulp-Schedule ist deterministisch
  und `animate`-unabhängig.
- Discard-Pfad, Budgets, Hard-Caps, Spawn-Raten: unangetastet.

### Zahlen — Transform-Writes/Tick (Finale-Fenster, Reveal → Dark)

| Tier | Effigy vorher (Burst @Stride) | Blackhole vorher (Burst, +5t versetzt) | Peak/Tick vorher | Effigy nachher (steady) | Blackhole nachher (steady) | **Summe nachher (steady)** |
|---|---|---|---|---|---|---|
| VERIFY | 700 alle 10t | 240 alle 10t | **700** | 70/t | 24/t | **94/t** |
| STANDARD | 2.240 alle 10t | 1.160 alle 10t | **2.240** | 224/t | 116/t | **340/t** |
| EPIC | 2.980 alle 10t | 2.120 alle 10t | **2.980** | 298/t | 212/t | **510/t** (−83 % Peak) |

(Populationen aus `CreditsDisplayBudget`: Effigy = ripCellCap+Seam+Shard+Underside =
420+60+80+140 / 1.300+160+280+500 / 1.700+220+420+640; Blackhole = holeCount+skyDrainCount =
180+60 / 900+260 / 1.600+520.)

---

## Risiko 3 — Sky-Drain-Dom vs. Kamera

### Analyse

- Geometrie ist per Konstruktion **run-invariant** (`CreditsBlackHoleAct.begin`): die
  Vantage steht exakt `VANTAGE_SOUTH=430` südlich der Loch-Säule (`dir.x == 0`), der
  FX-Anker `ANCHOR_AHEAD=110` Blöcke ENTLANG des Blickstrahls, und
  `CreditsFinaleFxRows` spawnt `credits5_skydrain` UNROTIERT am Anker (Cue ohne
  SpawnOptions). Im Emitter-Lokalframe liegt die Anker→Kamera-Achse also IMMER auf
  Welt-+Z (Azimut 90°), Pitch ~10–26° (islandTop-abhängig).
- Die volle 57–88er-Spawn-Sphäre legt ihren kameraseitigen Pol ~22 Blöcke vor die Kamera,
  MITTIG im gecrushten ~17°-FOV-Rahmen (`S2CCreditsFovPayload`) — ein 7–12-Block-
  BLEND_ALPHA-Haze-Quad (`skydrain_haze`, der eigentliche §9-Täter) füllt dort den
  ganzen Bildschirm; die 0,2–0,3er-Streak-Sprites (x2,4 Velocity-Stretch) wären grelle
  Vordergrund-Schmierer.
- Jar-Lektüre (dekompiliertes photon 2.1.5): `Sphere.nextPosVel` sampelt
  `r = cbrt(rmin³ + u·(r³−rmin³))`, Polar `acos(2u−1)`, Azimut `[0, arc)` (arcMode
  „Random"); `ShapeSetting` rotiert via `Vector3fHelper.rotateYXY` — JOML `rotateY(+a)`
  verschiebt den Azimut um **−a**.

### Lösung: ±48°-Kamera-Lune (Spawn-seitig, geringstes Choreo-Risiko)

- Beide Skydrain-Emitter (`skydrain_streaks` r=88/th=0,35, `skydrain_haze` r=84/th=0,3)
  bekommen `sphere(..., arc=264)` + Shape-Rotation `yaw=222`: gesampelter Azimut
  `[0°, 264°)` → Welt-Azimut `[138°, 402°)` ⇒ **Lücke (42°, 138°), zentriert auf +Z** —
  eine VERTIKALE Lune (alle Elevationen), damit **pitch-unabhängig** (die
  islandTop-Unsicherheit verschwindet). `arcMode` bleibt „Random" (Haus-Gesetz 5:
  „Uniform" = Client-Crash).
- **Alternativen verworfen**: (a) Dom-Kante global zurückziehen (Radius < 57) — ändert
  die Lesart „der GANZE Himmel zieht sich zusammen" und die Dichte-Balance zu den
  Display-Strömen (58–96-Band); (b) Size/Alpha-Rampe nahe Kamera — Photon hat keinen
  kameradistanz-abhängigen Kanal, das hieße neue Runtime-Logik in Team-A-Territorium
  (`PhotonBridge`); (c) Cull-Box-Trick — cullt das GANZE System, nicht einzelne Sprites.
  Die Lune ist ein reiner Daten-Fix im eigenen Asset mit exakt definierter Wirkung.

### Numerische Verifikation (Monte-Carlo gegen das GESHIPPTE Asset)

400k-Sample-Probe (`/tmp/f103_lune_probe.py`) reproduziert das javap-verifizierte
Photon-Sampling + JOML-Rotation direkt aus den NBT-Werten der `.fx`-Datei, inkl.
Radial-Creep über die volle Lebenszeit (Haze ≤ 12 Blöcke, Streaks ≤ 45) und
Streak-Orbital-Curl (≤ 0,595 rad), Pitch-Sweep 10°/18°/26°:

| Emitter | leere Azimut-Lücke | min. Kamera-Distanz über die Lebenszeit (vorher) | Sprites < 60 Blöcke vor der Kamera |
|---|---|---|---|
| `skydrain_haze` | exakt (42°, 138°) | **≥ 73,5 Blöcke** (~26) | **0 Samples, je** |
| `skydrain_streaks` | exakt (42°, 138°) | **≥ 60,6 Blöcke** (~22) | **0 Samples, je** |

Die Haze-Quad-KANTE (6-Block-Halbgröße eingerechnet) bleibt in jeder Lebensphase
≥ ~18° außerhalb des 17°-FOV-Halbrahmens; Achsen-Querungen gibt es erst 123–167 Blöcke
vor der Kamera — das ist der FERNE Dom hinter dem Anker, also genau die beabsichtigte
„Fäden konvergieren in der Bildmitte auf das Loch"-Lesart.

### Warum choreo-neutral

Radien, Timing, Lebenszeiten, Geschwindigkeiten, Farben, HDR (1,45-Deckel), Counts:
alles unangetastet — entfernt sind nur 96/360 der Spawn-RICHTUNGEN, die per Konstruktion
bei Geburt hinter/neben der Kamera lagen (im Bild nur je als Vordergrund-Schmierer
sichtbar, nie als Teil der Dom-Lesart). Emission-Rate bleibt 1,0/0,24 pro Tick — die
sichtbare Dom-Dichte steigt marginal (dieselben Partikel verteilen sich auf 264° statt
360°), weit unter der Run-zu-Run-Varianz des Random-Samplings.

---

## Gates

| Gate | Ergebnis |
|---|---|
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** |
| `python3 tools/photon/fxlib.py validate --lint` | **0 NEW** error/warn (284 Files, 27 grandfathered, Advisories vorbestehend) |
| Regen-Determinismus (`python3 tools/photon/credits5_fx.py` doppelt) | byte-identisch (SHA-256 stabil); `credits5_lastlight.*` byte-identisch zu HEAD (UUID5-Beweis, Diff = nur die Lune) |

Doku-Fakt für die Live-Verifikation: Photon cached `.fx` statisch — der Client braucht
`/photon_client clear_client_fx_cache` (F3+T reicht NICHT).

## Live-Verifikationsplan für den Main-Agent (Verify-Tier, analog §7)

**Setup**: Client `/photon_client clear_client_fx_cache` → `/dev credits tier verify`
(Kontrolle: bare `/dev credits tier`) → `/dev credits start` (Log:
`display-budget tier VERIFY (hard cap 1400)`).

**Risiko-2-Zählpunkte** (RCON `/execute if entity @e[type=minecraft:block_display,tag=<TAG>]`
— Populationen MÜSSEN unverändert sein, nur die Write-Verteilung ist neu):

| Zeitpunkt | Erwartung | RCON |
|---|---|---|
| t≈3.700 (~185 s) | Effigy fertig hinter Schwarz — Population unverändert | `tag=eclipse_credits_maprip` → **≈700** |
| t≈3.900 (~195 s) | Reveal, Akkretion | `tag=eclipse_credits_blackhole` → **180** |
| t≈3.900–5.000 | **Glattheits-Beweis**: `/tick query` mehrfach im Finale-Fenster — keine 10t-Sägezahn-Spitzen mehr (vorher: MSPT-Zacken auf den Stride-Ticks); Effigy-Drift + Akkretions-Spiralen visuell ruckelfrei (10t-Interpolation trägt weiter) | — |
| t≈4.400 (~220 s) | Drains dazu | `tag=eclipse_credits_blackhole` → **240** |
| t≈300, Gegenprobe | `/dev end_event` mitten im Run | Credits-Displays → **0** (Leak-Gate unverändert) |

**Risiko-3-Sichtprüfung** (llvmpipe reicht): im selben Verify-Run bei t≈4.400–4.900
(Skydrain-Beat) 2–3 Screenshots der Kamera-Perspektive — Erwartung: Drain-Fäden +
Haze ziehen als FERNE Dom-Kulisse zur Bildmitte (Loch), **kein** großflächiges
Haze-Quad, das schirmfüllend vor der Linse aufzieht; Bildzentrum bis ~60 Blöcke
sprite-frei. Schnell-Rehearsal ohne Full-Run: `/eclipsefx sequence credits BLACKHOLE`
(Skydrain-Cue @t360 relativ) mit Kamera ~110 Blöcke südlich des FX-Ankers auf der
Anker-Höhe ±30°-Pitch.

**Standard/Epic danach**: `/dev credits tier standard|epic` + Neustart — gleiche
Zählpunkte, Populationen aus der §7-Akt-Tabelle; erwartete steady Writes/Tick: 340
(STANDARD) / 510 (EPIC).

## Geänderte Files / Commit

- `ritual/CreditsMapRipAct.java` — `animate` phasen-gesliced + Slice-Stabilitäts-Doku.
- `ritual/CreditsBlackHoleAct.java` — `animate` phasen-gesliced (beide Populationen),
  `pushWave` durch Voll-Stride-Wellenzähler ersetzt.
- `ritual/CreditsSequence.java` — beide Callsites auf Jeden-Tick umgestellt
  (Stride-Gate + obsolete F-102-Dephasierung entfernt).
- `tools/photon/credits5_fx.py` — Kamera-Lune-Konstanten + Herleitung (Haus-Gesetz 6),
  beide Skydrain-Shapes auf `arc`/`rotation`.
- `assets/eclipse/fx/credits5_skydrain.fx` / `.fxproj` — regeneriert (nur die Lune;
  `credits5_lastlight.*` byte-identisch geblieben).
- Dieser Report.
