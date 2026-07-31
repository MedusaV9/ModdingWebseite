# MC4 — The Other + Ghost/Echo-Familie (Welle M-C, Mob/Item-Zensus F-098)

**Auftrag:** MOB_ITEM_CENSUS §5 Welle M-C Zeile MC4 — NUR Polish, Gesetz **§5-G7**:
(a) The Other: Fragment-Cubes bei Aggro → **Orbital-Stagger statt Gleichtakt**,
(b) Ghost-Reveal-Layer-Feinschliff (Übergänge, Alpha-Kurven, Timing),
(c) Echo-Grove-Renderer-Feinschliff, (d) Selbstkritik + weitere Polish-Pässe.
**KEINE Geometrie-Änderung an der Humanoid-Silhouette** — Beweis in §5.8.

**Datei-Besitz (exklusiv, §5-G1):** `entity/TheOtherEntity.java`,
`client/entity/TheOther{Model,Renderer}.java`, `ghosts/*`, `client/entity/ghost/*`,
`client/entity/echo/*` (die woah/echogrove-Renderer), `docs/uv/the_other.md`.
**Nicht angefasst:** `EclipseEntityRenderers.java` (SHARED, §5-G2 — nur gelesen),
`woah/echogrove/*`-Entity-/Service-Klassen (Besitz WOAH-05/C3), FROZEN-Basen,
`validate_geo.py`/`paint_lib.py`, `tools/photon/**`, `assets/eclipse/fx/**`,
`sounds.json`/Lang-Dateien, `client/echo/EchoPhotonFxRows.java` (W13-FX-Besitz).

---

## 0. Plan (vor der Implementierung festgehalten)

1. Ist-Zustand ALLER Familien-Renderer lesen + Vanilla-`HumanoidModel.setupAnim` aus dem
   NeoForm-Quell-Jar gegenprüfen (welche Kanäle resettet Vanilla pro Frame, welche nicht?)
   — nichts aus dem Gedächtnis.
2. (a) Fragmente: echte ORBITS (drei verschiedene Orbit-Ebenen) statt Achsen-Bobs; Perioden
   paarweise inkommensurabel, Phasen pro Entity gehasht + harte 120°-Staffelung pro
   Fragment, Hüfte GEGENLÄUFIG; Detach-Beat (Overshoot-Ease aus der Silhouette heraus)
   statt Instant-Einblendung — dafür eine Client-Reveal-Uhr in der Entity.
3. (b) Ghost-Reveal: Smoothstep-Envelope über die Fensterränder (Alpha-Flicker, Jitter,
   Herz-Glow), Re-Scramble-Decay, Materialize-Fade beim Spawn/Tracking-Eintritt.
4. (c) Echo: Alpha-Kurven-Audit (Glow×Fade!), Familien-Helfer vereinheitlichen,
   WAVE-Pose anwärmen. Nur Renderer-Dateien (Entity-Klassen sind fremder Besitz).
5. Pro Runde `./gradlew compileJava`; Beweise über einen Java-Offline-Harness, der die
   ECHTEN Funktionen aufruft (MA2-Präzedenz: gegen die echte Runtime, nicht gegen eine
   Python-Nachbildung), inkl. Silhouetten-Regressions-Diff der gebackenen Geometrie.

---

## 1. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 1.1 Vanilla-Reset-Verhalten (aus dem NeoForm-Quell-Jar gelesen)

`net/minecraft/client/model/HumanoidModel.java` (sourcesAndCompiledWithNeoForge-Jar):
`setupAnim` schreibt pro Frame `head.yRot/xRot`, `body.yRot`, `body.xRot` (0 bzw.
Crouch), alle Arm-/Bein-Rotationen und endet mit `hat.copyFrom(head)`.
**`head.zRot` wird NIE geschrieben.** `PlayerModel.setupAnim` kopiert danach
Sleeves/Pants/Jacket. Konsequenz: jedes `+=` auf `head.zRot` akkumuliert pro FRAME und
leakt über die geteilte Model-Instanz auf alle Entities desselben Renderers → Bug B-1.

### 1.2 Kampf-/Sync-Schleife The Other

`isAggressive()` ist das synchronisierte Byte-Flag (`Mob.setAggressive` via
`MeleeAttackGoal.start/stop`); der 180°-Head-Snap läuft serverseitig über
`headSnapTicks` (2 Ticks à +90°). Es gibt KEINEN synchronisierten Reveal-Fortschritt —
das Flag ist binär, jedes Easing braucht eine client-lokale Uhr (neu: §3.1).

### 1.3 Echo-Fade/Glow-Lebenszyklus (EchoSceneService, nur gelesen)

`spawnActor` setzt `setEchoFade(0)` (Fade-in 0→30 über 30 Ticks), `applyGlow()` setzt
`echoGlow = max(glowBoost, floodGlow)` bereits BEIM Materialisieren; Release zählt
`fadeOut` 30→0 und ruft dann `discard()`. Alt-Formel der Renderer:
`0.35·fade + 0.20·glow` — der Glow-Term hing NICHT am Fade → Actor, der während eines
Floods materialisiert/released, poppt mit Alpha `0.20·glow` (bis 0.20) hart ein/aus
(Bug B-2). Der `MoonGlowLayer` skalierte dagegen schon immer mit `fade` — die Asymmetrie
bestätigt die Intention.

### 1.4 Ghost-Reveal-Fenster

`GhostRenderers.Reveal` (Wall-Clock, default 60 t): `progress` 0→1, `activeReveal`
liefert `null` nach Ablauf. Alt: Jitter/Flicker binär an `reveal != null` gekoppelt →
harter Schnitt an beiden Fensterrändern; Worst-Case-Erste-Frame-Sprung **0.2636**
Alpha (gemessen, §5-B3). Re-Scramble konstant 4/32 bis zum harten Cut bei 0.85.

### 1.5 Textur-Status der Familie (Auftrags-Pflichtvermerk)

Die Familie hat **keine Painter-Skripte** (bewusst: `the_other.png` ist ein
Uniform-Skin-Derivat per `scripts/placeholder_gen/EntitySkinPlaceholder.java`,
`eclipsed_player*.png`/`echo_ghost*.png`/`memory_orb.png` sind generierte finale Kunst
der Skin-Familie). **Keine Textur wurde angefasst**; die neuen Fragment-Beats samplen
ausschließlich BESTEHENDE Skin-Regionen (texOffs (0,0)/(16,16)/(40,16), dokumentiert in
`docs/uv/the_other.md`). Ein `echo_ghost_wolf_glow.png` existiert nicht → bewusst KEIN
Wolf-Glow-Layer erfunden (hätte Hand-Textur gebraucht — verboten).

---

## 2. Gefundene Bugs

| # | Bug | Wirkung | Fix |
|---|---|---|---|
| B-1 | `TheOtherModel.setupAnim`: `this.head.zRot += REVEAL_HEAD_CANT` — Vanilla resettet `zRot` nie (§1.1) | Kopf KORKENZIEHT mit Framerate-abhängiger Geschwindigkeit (+0.12 rad **pro Frame**) statt 7°-Kippung; nach Aggro-Ende bleibt der akkumulierte Roll für immer stehen und leakt über die geteilte Model-Instanz auf jede andere The-Other-Instanz | Absolutes Schreiben in ALLEN Zweigen (`= cant·ease` / `= 0`), Gesetz im Klassen-Javadoc verankert |
| B-2 | Echo-Ghost+Wolf: Glow-Boost außerhalb des Fade-Envelopes (§1.3) | Flood-beleuchtete Aktoren poppen bei Materialize/Release mit Alpha bis 0.20 hart ein/aus | `(base + glow·boost) × fade` — bei vollem Fade wertidentisch (Beweis §5-C2) |
| B-3 (minor) | Wolf-Shimmer-Phase `(id * 0x9E3779B9) & 0xFF` ad-hoc statt Familien-Hash | nur Stil/Entropie | Wolf nutzt jetzt den geteilten `echoAlpha`-Helfer |

Nebenbefund (kein Bug, aber gehärtet): die alte Fragment-Drift hing an `ageInTicks`
(wächst unbegrenzt, Float-Präzision auf langen Sessions); die neuen Orbits laufen auf
der pro Reveal resettenden Client-Uhr — Winkelargumente bleiben klein.

---

## 3. Geänderte Dateien

| Datei | Änderung |
|---|---|
| `entity/TheOtherEntity.java` | Client-Reveal-/Retract-Uhren (`clientRevealAge`/`clientRetractAge`/`clientLastRevealTicks`), Beat-Fenster-Konstanten `REVEAL_DETACH_TICKS`/`REVEAL_RETRACT_TICKS` (Single Source of Truth), Re-Aggro-Backdate; Server-Verhalten unverändert |
| `client/entity/TheOtherModel.java` | B-1-Fix; Fragment-Kinematik komplett neu: Detach → Orbital-Stagger → Retract (`fragmentPose`/`retractPose`, package-visible für den Harness); Kopf-Cant geeast; Geometrie/`createBodyLayer` **byte-identisch** zu vorher (nur Konstanten-Referenzen umgezogen, Beweis §5.8) |
| `client/entity/ghost/GhostPlayerRenderer.java` | Reveal-Envelope (`revealEnvelope`), Alpha-Blend idle↔flicker, Jitter-Duty/Amplituden-Rampe, Re-Scramble-Decay, Herz-Glow-Flare (`GLOW_REVEAL 0.95`), Materialize-Fade (12 t) |
| `client/entity/echo/EchoGhostRenderer.java` | B-2-Fix als geteilter Helfer `echoAlpha` (package-visible), WAVE-Kopfneigung (+`hat`-Re-Sync, `zRot`-Reset-Gesetz) |
| `client/entity/echo/EchoGhostWolfRenderer.java` | nutzt `EchoGhostRenderer.echoAlpha` (B-2+B-3), tote Konstanten raus |
| `client/entity/echo/EchoRenderers.java` | deprecated `bus = ...`-Attribut entfernt (NeoForge wählt den Mod-Bus am Event-Typ; exakt das GhostRenderers-Muster, das die Datei laut eigenem Javadoc spiegelt) — Compile jetzt warningfrei in MC4-Dateien |
| `docs/uv/the_other.md` | Fragment-UV-Sampling-Tabelle + Hinweis für künftige Skin-Redraws |
| `docs/plans_v3/session_0730/MC4_GHOSTS_REPORT.md` | dieser Report |

**Nicht geändert:** Geo-/Anim-JSONs (es gibt für diese Familie keine — alles prozedural),
Texturen, Painter, `ghosts/*`-Logik (`LogoutGhostService`/`GhostConfig`/`GhostsState`
brauchten keinen Polish; `LogoutGhostEntity` blieb nach Review unangetastet),
`GhostRenderers.java` (Reveal-Cache ist korrekt), `MemoryOrbRenderer.java` (§7 offener
Punkt), `TheOtherRenderer.java`. **Langdrop:** keine neuen UI-Strings → bewusst KEIN
`docs/plans_v3/langdrop/MC4-GHOSTS.json` (nichts zu mergen).

---

## 4. Die drei Beats im Detail

### 4.1 (a) The Other — Detach → Orbital-Stagger → Retract

**Detach (0 – 8 t, easeOutBack mit 10 % Overshoot):** Jedes Fragment startet an einem
Emergence-Punkt IN der Silhouette (Kopf-Oberseite / Schulter-Wurzel / Hüft-Rückfläche),
skaliert von 0.25 hoch (Peak 1.075 bei t≈4.6, Ruhe 1.0) und reißt mit einem
front-loaded Tumble-Kick (`TUMBLE_SPEED × 40` rad, quadratisch abklingend) heraus —
Übergang in die Orbits C¹-glatt bis auf ≤ 0.14 px/t Restknick (§5-A7, subpixel).

**Orbital-Stagger (der Kern des Auftrags):** drei ORBITS statt drei synchroner Bobs —

| Fragment | Orbit-Ebene | ω (rad/t) | Periode | Radius | 2. Frequenz | Tumble |
|---|---|---|---|---|---|---|
| crown (Kopf-Space) | horizontal (x/z) | 0.113 | 2.8 s | 1.1 px | Bob 0.073 | yRot +0.021/t |
| shoulder | frontal-Ellipse (x/y) | 0.0787 | 4.0 s | 0.85 px (x×0.55) | Sway 0.053 | zRot +0.017/t |
| hip | horizontal, **GEGENLÄUFIG** | 0.0593 | 5.3 s | 0.9 px | Bob 0.089 | xRot **−0.013**/t |

Frequenz-Verhältnisse 1.44 / 1.33 / 1.91 (paarweise inkommensurabel), Phase = per-Entity-
Hash + harte 120°-Staffelung pro Fragment. Gemessen (§5-A4/A5): paarweise
Positions-Korrelation |r| ≤ 0.062, engste Wiederannäherung an die Startkonstellation in
120 s = 1.197 px Restdistanz — **kein Gleichtakt, keine Wiederholung**. Zwei Others
nebeneinander laufen nachweislich verschieden (§5-A6). Clearance-Gesetz eingehalten:
alle Orbit-Extrema (64 Entity-Seeds × 2000 t) bleiben außerhalb der Limb-Volumina
(§5-A3, 3×PASS) — die Silhouette bleibt lesbar.

**Retract (Selbstkritik-Pass 1, 6 t):** Aggro-Verlust ließ die Fragmente vorher in einem
Frame verschwinden und den Kopf zurückschnappen. Jetzt: Orbit-Uhr friert auf der
Reveal-Dauer ein, Fragmente werden per Smoothstep auf die Emergence-Punkte zurückgezogen
und schrumpfen auf 30 % — der `visible=false`-Flip passiert IN der Silhouette
(§5-A9: Übergangs-Kontinuität exakt 0.0000). Kopf nivelliert auf derselben Kurve.

**Re-Aggro-Backdate (Selbstkritik-Pass 2):** Flackert Aggro während des Retracts wieder
an, würde das Detach hart von den Emergence-Punkten neu starten (Positionssprung bis zur
vollen Rest-Distanz). `TheOtherEntity.tick` datiert die Reveal-Uhr deshalb um
`DETACH · (1 − smoothstep(retract))` zurück — das Detach setzt ungefähr am aktuellen
Radius wieder auf. Beat-Fenster leben dafür als gemeinsame Konstanten in der Entity
(`REVEAL_DETACH_TICKS`/`REVEAL_RETRACT_TICKS`), das Model aliased sie.

### 4.2 (b) Ghost-Reveal-Layer (GhostPlayerRenderer)

- **Envelope:** `revealEnvelope(progress)` = Smoothstep-Rampe über die ersten/letzten
  12 % des Fensters (60 t → 7.2 t Rampen). Alpha blendet idle↔flicker per Envelope,
  Jitter rampt Duty-Cycle 3/16→16/16 UND Amplitude 0.02→0.045 — der Geist gleitet in
  den Glitch und setzt sich wieder heraus. Worst-Case-Erste-Frame-Sprung: **0.2636 →
  0.0049** (54×, §5-B3).
- **Re-Scramble-Decay:** volle Namens-Re-Scrambles starten bei 5/32 (≈16 %) der
  150-ms-Buckets und klingen linear mit dem Resolve-Fortschritt auf 0 ab (ersetzt den
  harten 0.85-Cut) — „der Name kämpft sich frei" (§5-B5).
- **Herz-Flare:** `HeartGlowLayer` lerpt während des Reveals per Envelope Richtung 0.95
  (Heartbeat 0.60–0.82 im Ruhezustand) — die leckende Identität brennt.
- **Materialize-Fade (12 t über client `tickCount`):** deckt Spawn UND
  Tracking-Range-Eintritt ab — vorher poppte der Spectre mit vollen 40 % ein (§5-B4);
  wirkt konsistent auch auf den Glow-Layer.
- reducedFx-Verhalten erhalten: idle konstant, Reveal-Flicker weiterhin aktiv
  (Gameplay-Signal), Fades bleiben (Übergang, kein Effekt).

### 4.3 (c) Echo-Grove-Renderer

- **B-2-Fix** (`echoAlpha`, von Ghost UND Wolf genutzt): Glow-Boost im Fade-Envelope;
  Steady-State bei vollem Fade bit-identisch (§5-C2, |diff| = 0.000000).
- **WAVE-Pose:** Kopf neigt sich 3.4°±2.3° zum erhobenen Arm, gegenphasig zum
  Arm-Schwenken (`hat` re-synct; `zRot`-Reset im else-Zweig — B-1-Gesetz).
- **EchoRenderers:** Deprecation-Fix (§3-Tabelle).
- `MemoryOrbRenderer` nach Audit unverändert (Atmung/Warmth sind sauber; Lit-Flip siehe §7).

---

## 5. Validierung

### 5.1 Pflicht-Checks

- **`validate_geo.py`: nicht anwendbar** — MC4 ändert keine `.geo.json`/`.animation.json`
  (die Familie ist zu 100 % prozedural auf Vanilla-/Player-Modellen, §1/§2 des Zensus);
  es gibt keine Assets, die der Validator prüfen könnte.
- **Compile:**

```
$ ./gradlew compileJava
  BUILD SUCCESSFUL
```

  Ein `--rerun-tasks`-Volllauf zeigt ausschließlich VORBESTEHENDE `bus()`-Deprecation-
  Warnings aus Dateien fremder Teams (u. a. `client/echo/EchoPhotonFxRows.java` =
  W13-FX-Besitz, worldgen/xboxevent/…); **aus MC4-Dateien kommt keine einzige Warning**
  (die einzige — `EchoRenderers` — wurde in diesem Paket behoben).

### 5.2 Offline-Harness gegen den ECHTEN Code (MA2-Präzedenz)

Kein `runClient`-Playblast: llvmpipe rendert Sekunden pro Frame (AGENTS.md) und
Sub-Pixel-Orbits/1-Frame-Envelope-Rampen sind dort nicht einfangbar; außerdem arbeiten
parallel fünf Teams im selben Checkout. Stattdessen ruft eine Wegwerf-Harness in
`/tmp/mc4harness/` die **echten, package-visible Funktionen** auf
(`TheOtherModel.fragmentPose/retractPose/easeOutBack`,
`GhostPlayerRenderer.revealEnvelope/computeAlpha`, `EchoGhostRenderer.echoAlpha`) —
Klassenpfad = `build/classes/java/main` + NeoForm-`compiledWithNeoForge`-Jar + Deps aus
dem Gradle-Cache. Die Alt-Formeln sind für Vorher/Nachher-Messungen 1:1 repliziert und
als OLD gelabelt. Vollprotokoll: `/tmp/mc4harness/mc4_harness_output.txt`. Auszüge
(wörtlich):

**[A1] Detach-Beat (id 1234, crown):** Emerge (−2.5, −7.0) → Overshoot (−5.996, −11.777)
bei t=4.6 → Ruhe+Orbit ab t=8; scale 0.250 → 1.075 → 1.000.

```
[A2] easeOutBack peak = 1.1000 (expected ~1.10), scale peak = 1.0750, scale(t=8) = 1.0000

[A3] Steady-state clearance (t = 20..2000, step 0.1, ids 1..64) vs limb volumes:
    crown    x [ -6.600.. -4.400]  y [-12.000..-11.000]  z [ -1.100..  1.100]
    shoulder x [-10.467.. -9.533]  y [  0.150..  1.850]  z [  0.200..  0.800]
    hip      x [  4.900..  6.700]  y [  9.100..  9.900]  z [  3.600..  5.400]
    crown stays above head top (maxY+1 <= -8): PASS
    shoulder clears arm outer face (maxX+1.5 <= -8): PASS
    hip clears body/leg depth (minZ-1 >= 2): PASS

[A4] Orbital stagger — pairwise position correlation over 60 s:
    corr(x_crown, x_shoulder) = -0.0199
    corr(x_crown, x_hip)      = -0.0062
    corr(x_shoulder, x_hip)   = -0.0623

[A5] closest re-approach within 120 s: dist=1.197 px at t=1298.84 (0 would be lockstep repeat)

[A6] Per-entity desync (crown at t=100): id=1000 (-4.400,-11.522, 0.011)
     id=1001 (-6.556,-11.007, 0.309)   id=1002 (-5.196,-11.895,-1.057)

[A7] Detach-boundary continuity |dv| (px/tick): crown (0.022, 0.072, 0.140)
     shoulder (0.034, 0.040, 0.030)   hip (0.045, 0.049, 0.122)

[A9] Retract: |retractPose(r=0) − fragmentPose(t_drop)| = (0.0000, 0.0000, 0.0000)
     für alle drei Fragmente; crown-Track r=0→1: (−6.449,−11.015) → (−2.500,−7.000),
     scale 1.000 → 0.300 (Flip in der Silhouette versteckt)
```

**[B] Ghost-Reveal:**

```
[B2] 60-tick reveal, worst frame-to-frame alpha step (0.5-tick frames):
    window ENTRY:  OLD max|dAlpha| = 0.2365   NEW max|dAlpha| = 0.1078
    window EXIT:   OLD max|dAlpha| = 0.2329   NEW max|dAlpha| = 0.1079
    (mid-window flicker steps are the DESIGN — only the edges must be eased)

[B3] Worst-case entry/exit pop across 512 entity ids / phases:
    OLD worst first-frame jump = 0.2636  |  NEW worst first-frame jump = 0.0049

[B4] Materialize fade-in: tick 0 → alpha 0.0000 … tick 12 → 0.3984 (voll ab 12 t)

[B5] Re-scramble: 15.6 % → 12.5 % → 9.4 % → 6.3 % → 3.1 % → 0 % (bei progress 0.8)
     (OLD: konstant 12.5 % bis harter Cut bei 0.85)

[B6] Jitter-Rampe: env 0→1: duty 3/16→16/16, amplitude 0.020→0.045
```

**[C] Echo-Alpha-Fix:**

```
[C1] Materialize during a full flood (glow=1.0):
    fade-tick 0:  OLD 0.2000  NEW 0.0000   (OLD poppt am ersten Frame mit 0.20 ein)
    fade-tick 30: OLD 0.5208  NEW 0.5208
[C2] Full fade steady state unchanged: |diff| = 0.000000 für glow 0.0/0.5/1.0
[C3] reducedFx path: 0.0000 / 0.2750 / 0.5500 (konstant, kein Shimmer)
```

### 5.8 Silhouetten-Regressionsbeweis (§5-G7)

Der Harness backt `TheOtherModel.createBodyLayer()` und die Vanilla-Referenz
`HumanoidModel.createMesh(CubeDeformation.NONE, 0)` über GeckoLib-freie
Vanilla-Pipeline (`LayerDefinition.bakeRoot`) und diff't die Bäume rekursiv
(Reflection auf `cubes`/`children`, alle Posen + Cube-Boxen):

```
[A8] Silhouette regression proof: baked TheOtherModel vs vanilla humanoid mesh:
    EXTRA (ours only) @root/body/frag_hip:      [(-1.0,-1.0,-1.0)-(1.0,1.0,1.0)]  pose (5.8, 9.5, 4.5)
    EXTRA (ours only) @root/body/frag_shoulder: [(-1.5,-1.5,-1.5)-(1.5,1.5,1.5)]  pose (-10.0, 1.0, 0.5)
    EXTRA (ours only) @root/head/frag_crown:    [(-1.0,-1.0,-1.0)-(1.0,1.0,1.0)]  pose (-5.5, -11.5, 0.0)
```

Keine einzige DIFF-/MISSING-Zeile: die Humanoid-Silhouette (alle Posen und Cube-Boxen
von head/hat/body/arms/legs inkl. Overlays) ist **bit-identisch** zu Vanilla; die drei
Fragmente sind exakt die drei vorbestehenden Zusatz-Cubes (Boxen/UVs unverändert).

---

## 6. Test-Rezept (in-game, für den Integrator/Eval)

Voraussetzung: The Other spawnt nur in Pale Nights — für den Test direkt summonen.

```bash
./gradlew runClient    # llvmpipe: 20-40 s pro Aktion einplanen
# im Spiel:
/summon eclipse:the_other ~3 ~ ~
```

1. **Looming idle:** nicht angreifen, aus 6+ Blöcken beobachten — Arme totenstill,
   leichter Lean, KEINE sichtbaren Fragmente, Kopf ohne Roll (B-1-Regression: vor dem
   Fix rollte der Kopf nach einem Aggro-Zyklus dauerhaft schief).
2. **Detach:** auf ≤3 Blöcke herantreten (Aggro). Erwartung: drei Skin-Splitter reißen
   in ~0.4 s aus Kopf/Schulter/Hüfte, überschwingen kurz und orbiten dann sichtbar
   VERSCHIEDEN schnell in drei Ebenen (Hüfte gegenläufig); Kopf kippt dabei 7° ein.
   Zwei nebeneinander gesummonte Others dürfen NIE synchron orbiten.
3. **Retract:** Aggro brechen (wegsprinten >Follow-Range oder `/effect give @s
   invisibility`). Erwartung: Fragmente saugen sich in ~0.3 s zurück in den Körper und
   verschwinden DORT (kein Pop im freien Raum), Kopf nivelliert.
4. **Ghost-Reveal:** `logout_ghost` per Ausloggen eines Zweit-Accounts erzeugen, Ghost
   schlagen → Namens-Reveal: Glitch fährt weich hoch (kein Alpha-Sprung am Fensterrand),
   Re-Scrambles werden zum Ende hin seltener, Herz flackert heller, danach weiches
   Aussetzen. Neu spawnende/in Sichtweite kommende Ghosts faden in ~0.6 s ein.
5. **Echo-Flood:** im Echo-Grove `/dev`-Flood auslösen — Szenen-Aktoren, die WÄHREND des
   Floods materialisieren, faden jetzt von 0 ein statt bei 20 % Alpha zu poppen; Wave-
   Geste mit Kopfneigung prüfen.

Offline-Äquivalent (sekundenschnell, ohne Client): Harness-Aufruf wie in §5.2.

---

## 7. Koordinations-Snippets + offene Punkte

### 7.1 An den W13-FX-Besitzer von `other_dread_aura` (B2/scare-Umfeld) — nur Info

MC4 hat dem Reveal jetzt harte Client-Beats gegeben, an die sich die Aura hängen ließe
(kein Handlungsbedarf, Timings nur als Angebot):

| Beat | Fenster | Quelle |
|---|---|---|
| Fragment-Detach | Aggro-Flip + 0.0 – 0.4 s | `TheOtherEntity.REVEAL_DETACH_TICKS = 8` |
| Orbit-Steady | ab +0.4 s | Perioden 2.8 / 4.0 / 5.3 s, Hüfte gegenläufig |
| Retract | Aggro-Verlust + 0.0 – 0.3 s | `TheOtherEntity.REVEAL_RETRACT_TICKS = 6` |

### 7.2 An den Integrator

- Nichts committet (Anweisung); keine Shared-Datei angefasst, kein Snippet nötig
  (`EclipseEntityRenderers` unverändert — die Layer-Definition zeigt weiter auf
  `TheOtherModel::createBodyLayer`, dessen Signatur/Bake-Ergebnis nur um nichts
  Silhouettenrelevantes erweitert wurde, §5.8). Kein langdrop/sounddrop (keine neuen
  Strings/Sounds).
- `REVEAL_DETACH_TICKS`/`REVEAL_RETRACT_TICKS` sind bewusst in der ENTITY (common) —
  wer die Beats tunen will, ändert NUR dort (Model + Backdate ziehen automatisch mit).

### 7.3 Offene Punkte (bewusst nicht gemacht — Scope)

1. **Ghost-Nametag-Fenster-Ränder:** der Reveal-Tag poppt als Text ein/aus (voll
   gescrambelt beim Einpoppen — kaschiert den Eintritt; der Austritt zeigt den
   aufgelösten Namen). Echtes Text-Alpha-Fading braucht eine eigene
   `renderNameTag`-Implementierung (Vanilla bietet keinen Alpha-Kanal) — eigenes Ticket.
2. **Echo-SIT-Übergang:** der −0.45-Body-Drop schaltet hart, wenn eine Szene mitten in
   der Sichtbarkeit SIT toggelt (selten; Szenen sitzen i. d. R. ganze Loops). Sauber wäre
   per-Entity-Client-State im Renderer (Map wie `GhostRenderers.REVEALS`) — bei Bedarf.
3. **MemoryOrb-Lit-Flip:** Scale 1.0→1.3 + Warmton schalten instant. Gleiches
   State-Problem; die Atmung kaschiert es weitgehend, daher unangetastet gelassen.
4. **The-Other-Schatten:** Fragmente werfen keinen Schatten (Vanilla-Blob am Root) —
   irrelevant klein, nur der Vollständigkeit halber notiert.
