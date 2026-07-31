# MA5 — Finale-Props-Trio (portal_gate + portal_key + soul_wisp)

**Auftrag:** `MOB_ITEM_CENSUS.md` §5 Welle M-A Zeile MA5 — (a) Gate: idle →
Atmungs-Bogen + Keystone-Shimmer-Bones + das 512²-Canvas endlich nutzen
(Runen-Detailtextur, mehr Cubes/Verzahnung), (b) Key: `unlock_turn` mit 3
Bart-Glyphen-Klick-Beats auf B7s Ring-Snaps (t=8/22/36) + Schwebe-Verfeinerung,
(c) Wisp: +Trail-Bone, +`panic_scatter`, death → 3-Bone-Zerfall.

**Datei-Besitz (exklusiv, §5-G1):** `ferryman/finale/{PortalGate,PortalKey,SoulWisp}Entity`,
`client/entity/finale/*`, `geo/entity/{portal_gate,portal_key,soul_wisp}.geo.json`,
`animations/entity/{…}.animation.json`, `textures/entity/{…}(.png|_glowmask.png)`,
`scripts/geckolib_gen/mobs/{portal_gate,portal_key,soul_wisp}.py`,
`docs/uv/{portal_gate,portal_key,soul_wisp}.md`, dieser Report.

**Nicht angefasst:** `FinaleSequence.java` / `PortalFormation.java` / `FinaleState.java`
(B7-frisch bzw. Fremdbesitz — NUR gelesen), `veilfx/FerrymanFinaleFxRows` +
`veilfx/CutsceneBeatFxRows` + alle `.fx`-Assets (A3/B7), FROZEN-Basen
(`EclipseGeoMob`/`EclipseGeoMonster`/`EclipseGeoAnimations`/`EclipseGeoRenderer`),
`validate_geo.py`/`paint_lib.py`, `sounds.json`/lang (kein neuer Key nötig).

---

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 0.1 B7s UNLOCK-Beat — gelesen in `FinaleSequence.java` + `B7_CUTSCENE_REPORT.md` §1/5

* `insertKey()` (FLIGHT-Ende) feuert in EINEM Tick: `key.discard()` →
  `gate.unlock()` → Sounds/Shake/Caption → `FxPayloads.sendFxEvent(CUE_BEAT_KEYGLYPHS,
  keyhole −1.5 y, a=gateYaw)` → `stage = UNLOCK; ticks = 0`.
* `tickUnlock()` inkrementiert ZUERST (`ticks++`) und vergleicht dann gegen
  `KEYGLYPH_CLICKS_AT = {8, 22, 36}` → die `LODESTONE_COMPASS_LOCK`-Stings
  (Pitch 0.6 / 0.75 / 0.9) fallen auf **Tick 8 / 22 / 36 nach dem insertKey-Tick**,
  deckungsgleich mit den 3 im Photon-Asset gebackenen Ring-Snaps.
  → **Anim-Sekunden = Tick/20 = 0.40 s / 1.10 s / 1.80 s.**
* `BREACH_AT_TICK = 50` bleibt bewusst frei; `UNLOCK_HOLD_TICKS = 110`.
* **Fund (der Grund, warum es die Anim bisher nicht geben KONNTE):** der Schlüssel
  wird in `insertKey` im selben Tick `discard()`et — eine `unlock_turn`-Anim auf dem
  Key hätte nie ein Frame gerendert. Lösung ohne Fremddatei-Eingriff in §2.3.

### 0.2 Trigger-Muster der Props (FROZEN-Contract, `EclipseGeoMob` gelesen)

`registerControllers` ist final: `base` (State-Machine über `handleBaseState`) +
`action` (Transition 0, nur `triggerableAnim` aus `registerActionTriggers`).
Server feuert `triggerAction("<name>")`, GeckoLib synct selbst. Das Gate zeigt das
Nachzügler-Muster vor: gesyncte Flag (`DATA_OPEN`) → `handleBaseState` liefert
`hold(unlock)`, damit ein Client, der den Trigger nie sah, die Endpose rendert.
Dasselbe Muster übernimmt der Key (`DATA_SEATED` → `hold(unlock_turn)`).

### 0.3 Ist-Bestand (gemessen, nicht geschätzt)

| Prop | Bones/Cubes | Canvas | Anims |
|---|---|---|---|
| portal_gate | 8 / 11 | 512² | idle (4 kf, reine Molang-Skalen), unlock (6 s) |
| portal_key | 5 / 8 | 64² | idle (11 kf), fly (5 kf) |
| soul_wisp | 7 / 6 | 32² | idle, walk, attack, death (1 Bone / 6 kf) |

---

## 1. Plan (vor der Umsetzung festgelegt)

### 1.1 Portal Gate

* **Verzahnung statt Platten:** `frame` (1 Bone, 5 flache Cubes) → Gruppe `frame` mit
  `pillar_l/r` (je Plinthe + 4 wechselnd vorspringende Kurse + Kapitell),
  `arch_l/r` (je 3 Keilsteine/Voussoirs, nach innen ansteigend), `keystone_block`
  (Keil + Krone). Türen bekommen je 2 Eisenbänder.
* **Runen-Segmente:** die 2 Monolith-Runenplatten → **8 einzeln glimmende Bones**
  `glow_rune_l1..l4` / `glow_rune_r1..r4`, jeweils auf „ihrem" Kurs (Front-z folgt
  der Verzahnung: −9.05 auf bündigen, −12.05 auf vorspringenden Kursen).
* **Keystone-Shimmer:** `glow_keystone` (Scheibe) + `glow_shimmer_l/r/top` (3 Chips
  mit eigener Frequenz).
* **idle = Atmung:** `frame` atmet (Scale/Position, catmullrom, 8 s), Pfeiler
  gegenphasig, Bogen-Segmente mikro-rotiert, Runen glimmen als Welle nach oben.
* **unlock:** bestehendes Tür-Timing bleibt, aber die Runen zünden in **3 Stufen auf
  0.40 / 1.10 / 1.80 s** — dieselben Beats wie B7s Klick-Stings; der Keystone flasht
  auf dem dritten.
* **Painter:** pro Runen-Segment eine EIGENE Glyphe (8 Varianten), Chips + Bänder neu.

### 1.2 Portal Key

* **Geo:** `teeth` (2 Cubes) → 3 Bart-Bones `bit_1/2/3` mit je einer emissiven
  Glyphenplatte `glow_glyph_1/2/3`; dazu Ferrule/Collar am Schaft.
* **`unlock_turn` (2.4 s, hold):** Root dreht in 3 Rasten −40° / −80° / −120°, Ankunft
  EXAKT auf 0.40 / 1.10 / 1.80 s, danach je 3 Frames Rückprall (Overshoot-Settle);
  pro Rast schnappt die zugehörige Bart-Glyphe (Rotation −22° → 0 mit +6°-Overshoot)
  und ihr Glow flasht; der Schlüssel sinkt pro Rast tiefer ins Schloss.
* **idle:** Präzession (Molang-Taumel auf X/Z bei kontinuierlicher Y-Drehung),
  langsamere/majestätischere 8-s-Umdrehung, gestaffelter Glyphen-Puls.
* **Verdrahtung ohne Fremddatei:** `PortalKeyEntity.discard()` bekommt den
  Seat-Deferral (§2.3) — der Key spielt seine Rast-Anim zu Ende und entsorgt sich
  selbst bei t=46, VOR `BREACH_AT_TICK=50`.

### 1.3 Soul Wisp

* **Canvas 32² → 64²** (Haus-Standard; Painter schreibt Albedo+Glowmask in EINEM Lauf,
  kein Mismatch möglich) — 32² hätte die neuen Cubes nicht mehr sauber gepackt.
* **Geo:** +`trail_tail` (cube-loser FX-Locator an der Schleppen-Spitze),
  +`shell_l`/`shell_r` (zwei Schalen-Fragmente des Leichentuchs).
* **`panic_scatter` (0.9 s):** Rückprall + Spin + Schalen klappen auf.
  Entity HAT keinen Panic-Zustand → einer wird ergänzt (Radius/Speed-Gate +
  40 t Cooldown + 12 t Scatter-Fenster) plus öffentliche `panicScatter(Vec3)`-API
  für Fremd-Trigger (Snippet in §6).
* **death 1 Bone → 3 Bones (+ Rest):** Kern steigt/flasht/kollabiert, beide Schalen
  driften taumelnd auseinander und verlöschen; Sheet 1.2 s mit `tickDeath`-Override
  (24 t) nach Death-Konvention §6.2.

### 1.4 Validierung

`validate_geo.py <geo> <anim>` je Prop (0 Errors), Painter-Läufe (deterministisch,
zweifach ausgeführt = byte-identisch), `./gradlew compileJava`, danach
`runServer` + RCON-`/dev start_ferryman` (Sequenz-Beweis) und `runClient`
(Asset-Ladung + Sichtprüfung, llvmpipe).

---

## 2. Umsetzung

### 2.0 Geänderte Dateien (12)

| Datei | Was |
|---|---|
| `geo/entity/portal_gate.geo.json` | Verzahnter Bogen, 8 Runen-Segmente, Keystone-Shimmer |
| `animations/entity/portal_gate.animation.json` | idle = Atmung, unlock = 3-Stufen-Runenzündung |
| `scripts/geckolib_gen/mobs/portal_gate.py` | Painter: 8 Glyphen-Varianten, Voussoirs, Chips, Türbänder |
| `geo/entity/portal_key.geo.json` | Bart → 3 `bit_*` + 3 `glow_glyph_*`, Ferrule |
| `animations/entity/portal_key.animation.json` | `unlock_turn` (neu), idle-Präzession, fly angeglichen |
| `scripts/geckolib_gen/mobs/portal_key.py` | Painter: 3 Ward-Glyphen, Collar, vereinheitlichter `body_glow` |
| `ferryman/finale/PortalKeyEntity.java` | `DATA_SEATED`, Seat-Deferral, `SeatWatch`, `snapToKeyhole` |
| `geo/entity/soul_wisp.geo.json` | 32² → 64², `shell_l/r`, `trail_tail`-Locator |
| `animations/entity/soul_wisp.animation.json` | `panic_scatter` (neu), death = 3-Bone-Zerfall |
| `scripts/geckolib_gen/mobs/soul_wisp.py` | Painter: Schalen-Fragmente auf 64² |
| `ferryman/finale/SoulWispEntity.java` | Panic-Zustand + `panicScatter(Vec3)`, `tickDeath`-Override |
| `docs/uv/{portal_gate,portal_key,soul_wisp}.md` + dieser Report | Doku |

Texturen (Painter-Output, keine Handarbeit): `textures/entity/{portal_gate,portal_key,
soul_wisp}{,_ glowmask}.png`.

### 2.1 Portal Gate — vorher/nachher

| | vorher | nachher |
|---|---|---|
| Bones | 8 | **22** (davon 13 `glow_*`) |
| Cubes | 11 | **39** |
| Canvas-Belegung | 89 648 px | **121 556 px** (46.4 % von 512²), Glowmask 1 108 → **1 348 px** |
| `idle` | 4 Keyframes auf 4 Bones | **91 Keyframes auf 21 Bones**, 8 s |
| `unlock` | 39 kf / 6 Bones | **107 kf / 18 Bones** |

Bone-Baum: `root → frame → {pillar_l(+glow_rune_l1..l4), pillar_r(+glow_rune_r1..r4),
arch_l(+glow_shimmer_l), arch_r(+glow_shimmer_r), keystone_block(+glow_keystone,
+glow_shimmer_top)}`, `root → door_l`, `root → door_r(+glow_keyhole)`.

Die Pfeiler sind jetzt 6 Cubes mit abwechselnd vorspringenden Kursen (Front-z −9 / −12),
die Runenplatten sitzen bündig auf „ihrem" Kurs — daher die Tiefenwirkung. Jede der acht
Platten bekommt vom Painter eine EIGENE Glyphe (deterministisch aus dem Bone-Namen),
sodass sie einzeln glimmen können.

**Atmung, am laufenden Client gemessen** (`portal_gate_idle_breathing_runtime_proof.png`):
Statische Kamera, 18 s Capture. Die Oberkante des Basalt-Bogens pendelt mit **exakt 8 s
Periode** (Maxima bei t = 0 / 8 / 16 s = Loop-Grenzen von `animation.portal_gate.idle`)
über **10 Bildschirm-Pixel**; die emissive Runenfläche schwingt dabei um **98 %**
(256 → 715 px). Vorher: eine reine Molang-Skala auf `frame`, kein sichtbarer Hub.

### 2.2 Portal Key — vorher/nachher

| | vorher | nachher |
|---|---|---|
| Bones | 5 | **10** (davon 4 `glow_*`) |
| Cubes | 8 | **13** |
| Canvas-Belegung | 1 496 px | **1 890 px** (64²), Glowmask 136 → **330 px** |
| Anims | idle (9 kf), fly (5 kf) | idle (26 kf), fly (10 kf), **`unlock_turn` 2.4 s / 80 kf** |

Bart: `teeth` (2 Cubes, 1 Bone) → `bit_1/2/3`, jeder mit eigener emissiver Glyphenplatte
`glow_glyph_1/2/3` als Kind.

### 2.3 Klick-Beat-Beweis (t = 8 / 22 / 36)

Zwei unabhängige Beweise, beide aus den ausgelieferten Dateien, nicht aus dem Gedächtnis:

**(a) Asset gegen Quelltext** — `portal_key_clickbeat_timing_proof.png`. Das Skript liest
`KEYGLYPH_CLICKS_AT` und `BREACH_AT_TICK` per Regex direkt aus `FinaleSequence.java` und
sampelt die Sheets:

```
FinaleSequence.KEYGLYPH_CLICKS_AT = [8, 22, 36] -> [0.4, 1.1, 1.8] s  (BREACH_AT_TICK=50)

portal_key.unlock_turn — root Y (deg), detent arrivals:
  t= 8 (0.40 s): keyframe present=True value=[0, -40, 0]
  t=22 (1.10 s): keyframe present=True value=[0, -80, 0]
  t=36 (1.80 s): keyframe present=True value=[0, -120, 0]

portal_key.unlock_turn — bit glyph snaps (Z deg, -24 -> 0 + overshoot):
  bit_1: at 0.40 s -> [0, 0, 0] ; overshoot [(0.46, 7)]
  bit_2: at 1.10 s -> [0, 0, 0] ; overshoot [(1.16, 7)]
  bit_3: at 1.80 s -> [0, 0, 0] ; overshoot [(1.86, 8)]

portal_gate.unlock — rune stage / keystone beats:
  glow_rune_l1/l2/l4  -> 0.40 / 1.10 / 1.80
  glow_shimmer_l/r/top-> 0.40 / 1.10 / 1.80
  glow_keystone, keystone_block, glow_keyhole -> alle drei Beats

RESULT: all three detents land exactly on t=8/22/36
```

**(b) Laufzeit** — `portal_key_unlock_turn_runtime_stages.png`. Die Messingfläche des
Schlüssels im Client-Render, pro Server-Tick maskiert: drei Silhouetten-Maxima
(Tick 7 / 19 / 34) mit je einem Einbruch unmittelbar nach dem Beat, der Schlüssel ist
Tick 3…42 auf dem Schirm und **vor** `BREACH_AT_TICK = 50` weg. Die Pixelfläche ist eine
Projektion des Yaw, nicht der Yaw selbst — deshalb ist (b) Korroboration der Form und des
Fensters, die exakten Zeiten liefert (a).

**Warum es die Anim vorher nicht geben konnte:** `FinaleSequence.insertKey()` ruft im
selben Tick `key.discard()`. `Entity.discard()` ist `final`, also sitzt die Abfangung eine
Ebene tiefer auf `remove(RemovalReason)`: ein `DISCARDED` **während des Flugs und noch
nicht seated** IST der Seating-Beat und wird zu `seatIntoKeyhole()`; jede andere Entfernung
(Duplikat-Sweep, Chunk-Unload, der Selbst-Discard am Ende) läuft unverändert durch.
`FinaleSequence.java` wurde nicht angefasst.

**Leak-Guard:** der Countdown läuft NICHT in `tick()`. Ein Schlüssel, dessen Chunk geladen,
aber nicht entity-ticking ist (headless Server ohne Spieler in der Nähe), würde sonst nie
verschwinden — im ersten Testlauf genau so passiert. Er hängt jetzt an einer statischen
`SEATED`-Liste, die ein `ServerTickEvent.Post`-Subscriber (`PortalKeyEntity.SeatWatch`)
abarbeitet; `ServerStoppedEvent` leert sie. Zusätzlich `isPersistenceRequired()` /
`shouldBeSaved()` → `false`, solange seated: kein Schlüssel darf einen Crash mitten in der
Drehung im Schloss überleben.

### 2.4 Soul Wisp — vorher/nachher

| | vorher | nachher |
|---|---|---|
| Bones | 7 | **10** (`shell_l`, `shell_r`, `trail_tail`) |
| Cubes | 6 | **8** |
| Canvas | **32²** | **64²** (Albedo 395 → 645 px, Glowmask 32 → 121 px) |
| Anims | idle, walk, attack, death (**1 Bone / 6 kf**) | idle, walk, attack, **`panic_scatter` 0.9 s / 48 kf**, **death 1.2 s / 60 kf auf 8 Bones** |

`trail_tail` ist ein cube-loser Locator an der Schleppenspitze (Kind von `tail`) — reiner
FX-Anker, rendert nichts.

**Panic:** die Entity hatte keinen Panic-Zustand. Ergänzt wurden `PANIC_RADIUS = 1.7`,
`PANIC_PLAYER_SPEED = 0.12 b/t`, `PANIC_COOLDOWN_TICKS = 40`, `PANIC_SCATTER_TICKS = 12`,
`PANIC_PUSH = 0.42` sowie die öffentliche `panicScatter(Vec3 from)` für Fremd-Trigger
(§6.2). Die Bissschleife bleibt unangetastet.

> **Bug beim Verifizieren gefunden und behoben:** das Gate benutzte zuerst
> `player.position() − player.xo/yo/zo` als Schrittweite. Für einen `ServerPlayer` ist das
> **immer 0** — `ServerGamePacketListenerImpl.handleMovePlayer` beendet jedes Move-Packet
> mit `absMoveTo(...)`, und `Entity.absMoveTo` schreibt `xo = x`. Der Panic konnte also
> nie feuern. Jetzt: `player.getKnownMovement()` (der von `setKnownMovement` gepflegte
> Per-Tick-Vektor, vanillas eigener Weg dafür).

**Laufzeit-Beleg** (`soul_wisp_panic_scatter_velocity_proof.png`): 27 Wisps, Spieler fliegt
hindurch, `Motion` per RCON mit ~55 Hz gesampelt. Die gebrushten Wisps springen vom
0.12-b/t-Swirl auf **0.45–0.50 b/t** (= `PANIC_PUSH` 0.42 seitlich + 0.16…0.28 aufwärts)
und trudeln über ~12 t aus — genau das Profil, das `panicScatter()` setzt.

**Death:** `body`-Scale/Rotation allein → Kern (`glow_core`: Flare 2.4 → Delle → zweiter
Flare 2.8 → Kollaps 0.02) plus beide Schalen (`shell_l/r`: ±7 px auseinander, +3.5 px hoch,
−2.5 px zurück, dabei bis 160° verdreht und auf 0.2 geschrumpft), dazu `tail`, `arm_l/r`,
`glow_eyes`. Vanilla `Mob.tickDeath()` löscht bei Tick 20 und hätte den Drift
abgeschnitten → `tickDeath()`-Override hält bis `DEATH_DURATION_TICKS = 24`.
Gemessen am laufenden Server (`DeathTime` per UUID gepollt, weil `@e` sterbende Entities
nicht mehr selektiert): `DeathTime`-Zug 0…23, Körper nach **1229 ms** entfernt.
Der Renderer trägt bereits `withUprightDeath()`, der Vanilla-Umfaller stört also nicht.

---

## 3. Validierung

```
############ painters (deterministic, albedo+glowmask in one run)
painted geometry.portal_gate (512x512) -> …/portal_gate.png
  121556 albedo px, 1348 glowmask px -> …/portal_gate_glowmask.png
painted geometry.portal_key  (64x64)  -> …/portal_key.png
  1890 albedo px, 330 glowmask px    -> …/portal_key_glowmask.png
painted geometry.soul_wisp   (64x64)  -> …/soul_wisp.png
  645 albedo px, 121 glowmask px     -> …/soul_wisp_glowmask.png
re-run md5 diff: identical -> deterministic

############ validate_geo.py            (je <geo> + <anim> in einem Aufruf)
portal_gate : 2/2 file(s) passed — 0 errors, 0 warnings
portal_key  : 2/2 file(s) passed — 0 errors, 0 warnings
soul_wisp   : 2/2 file(s) passed — 0 errors, 0 warnings

############ ./gradlew compileJava
BUILD SUCCESSFUL
```

Volles Protokoll: `ma5_validate_and_compile.txt`.

---

## 4. Test-Rezept

```bash
./gradlew runServer          # oder runData/runClient je nach Bedarf
```

Im Server (RCON/Konsole):

```
gamerule spawnChunkRadius 8      # sonst tickt das Tor-Chunk headless nicht (PORTAL_MAX_DIST = 64)
eclipse start_event              # löst den Limbo-Gate, sonst sieht der Client die Props nicht
dev start_ferryman               # legt Altar + Tor an, startet die Sequenz
dev ferryman status              # Stage beobachten: ORBITS → … → PORTAL_READY → FLIGHT → UNLOCK
```

* **Gate-idle:** irgendwann vor dem Unlock 15 s auf das Tor schauen — der Bogen atmet mit
  8 s Periode, die acht Runensegmente glimmen als Welle nach oben.
* **Key-idle:** der Schlüssel schwebt über dem Altar, präzediert langsam, die drei
  Bartglyphen pulsen gestaffelt.
* **UNLOCK:** ab `insertKey` rastet der Schlüssel im Schloss dreimal ein — auf denselben
  Ticks wie B7s `LODESTONE_COMPASS_LOCK`-Stings (0.40 / 1.10 / 1.80 s). Bei t=46
  verschwindet er, bei t=50 bricht das Tor durch.
* **Wisps:** `execute at Dev anchored eyes run summon eclipse:soul_wisp ^0 ^-0.8 ^6`
  ein paar Mal, dann mit >0.12 b/t durch die Wolke laufen/fliegen → `panic_scatter`.
  `/kill @e[type=eclipse:soul_wisp]` → 3-Bone-Zerfall über 24 t.

Falls die Sequenz schon `DONE` ist: `eclipse_ferryman_finale.dat` (`stage`) und
`eclipse_ferryman_arena.dat` (`fightRunning`) zurücksetzen oder eine frische Welt nehmen.

---

## 5. Koordinations-Snippet für A3 (FX-Besitz)

Alle Bones existieren, sind validiert und ändern ihre Namen nicht mehr. Nichts davon ist
von MA5 verdrahtet — die Zeilen gehören A3.

```
# ---- portal_gate (geometry.portal_gate, 512²) --------------------------------
glow_keystone        Keystone-Scheibe, pulst im idle, flasht auf UNLOCK t=36
glow_shimmer_l/r/top 3 Chips am Bogenscheitel, eigene Frequenzen; zünden t=8/22/36
glow_rune_l1..l4     linke Pfeiler-Runen, unten→oben; Stufen t=8 / t=22 / t=36
glow_rune_r1..r4     rechte Pfeiler-Runen, gespiegelt
glow_keyhole         Schlüsselloch in door_r — Anker für den Insert-Funken
door_l / door_r      Türblätter (Öffnungs-Timing unverändert)

# ---- portal_key (geometry.portal_key, 64²) -----------------------------------
root                 trägt die Rast-Drehung (−40 / −80 / −120°)
glow_gem             Kopfgemme, pulst im idle
glow_glyph_1/2/3     Bartglyphen; Snap+Flash auf 0.40 s / 1.10 s / 1.80 s
                     (= FinaleSequence.KEYGLYPH_CLICKS_AT 8/22/36)
bit_1/2/3            die drei Bartzähne selbst, falls ein FX am Zahn hängen soll

# ---- soul_wisp (geometry.soul_wisp, 64²) -------------------------------------
trail_tail           NEU, cube-loser Locator an der Schleppenspitze — gedacht als
                     Anker für das Wisp-Schleppen-FX (rendert selbst nichts)
glow_core            Seelenkern; death: Flare t≈4 und t≈16, Kollaps bis t=24
shell_l / shell_r    Leichentuch-Fragmente; death: driften ±7 px auseinander,
                     panic_scatter: klappen auf
```

Zeitfenster, auf die A3 timen kann:

| Anim | Länge | Beats |
|---|---|---|
| `portal_key.unlock_turn` | 2.4 s (hold) | 0.40 / 1.10 / 1.80 s; Key weg bei t=46 |
| `portal_gate.unlock` | 6.0 s (hold) | Runenstufen 0.40 / 1.10 / 1.80 s |
| `portal_gate.idle` | 8.0 s loop | Atmungsperiode 8 s |
| `soul_wisp.panic_scatter` | 0.9 s | Burst in den ersten 0.25 s |
| `soul_wisp.death` | 1.2 s (hold) | Kernflares 0.18 s / 0.80 s, Ende 1.2 s = 24 t |

Der bestehende `FerrymanFinaleFxRows.keyTrail(...)` ist entity-gebunden und wird mit dem
Schlüssel mitentsorgt — der Seat-Deferral verlängert die Schleppe also automatisch um die
2.3 s der Drehung, ohne dass A3 etwas ändern muss.

---

## 6. Trigger-Snippets

### 6.1 Was bereits verdrahtet ist

* `PortalKeyEntity`: `unlock_turn` läuft automatisch über den `remove(DISCARDED)`-Deferral,
  `DATA_SEATED` sorgt über `handleBaseState` → `hold(unlock_turn)` für Nachzügler-Clients.
* `SoulWispEntity`: `panic_scatter` feuert selbst über das Radius/Speed-Gate im `tick()`.

### 6.2 Panic von außen auslösen (3 Zeilen, für Breach-Gush / Cutscene-Beats / Boss-Stomp)

```java
for (SoulWispEntity wisp : level.getEntitiesOfClass(SoulWispEntity.class,
        new AABB(center, center).inflate(6.0D), SoulWispEntity::isAlive)) {
    wisp.panicScatter(center); // Shove weg von center + panic_scatter, serverseitig
}
```

`panicScatter(Vec3)` ist idempotent-sicher (setzt Cooldown und Scatter-Fenster selbst) und
prüft `isClientSide` / `isAlive` intern.

---

## 7. Artefakte

| Datei | Zeigt |
|---|---|
| `portal_gate_idle_breathing_arch.mp4` | Tor im idle, 2 Loops, statische Kamera |
| `portal_gate_idle_breathing_runtime_proof.png` | 8-s-Atmung + 98 % Runen-Puls, am Client gemessen |
| `portal_key_clickbeat_timing_proof.png` | Rasten vs. `KEYGLYPH_CLICKS_AT` aus dem Quelltext |
| `portal_key_unlock_turn_runtime_stages.png` | 3 Drehstufen im Client-Render, Key weg vor dem Breach |
| `portal_key_unlock_turn_detents_raw.mp4` | UNLOCK-Nahaufnahme (Rohaufnahme) |
| `soul_wisp_panic_scatter_swarm_parts.mp4` | Durchflug, Wisps stieben auseinander |
| `soul_wisp_panic_scatter_velocity_proof.png` | 0.12 → 0.48 b/t Bursts, RCON-gemessen |
| `soul_wisp_death_3bone_decay.mp4` | Nahaufnahme des Zerfalls |
| `soul_wisp_death_3bone_decay_proof.png` | Sheet-Kurven + `DeathTime`-Zug (24 t statt 20 t) |
| `ma5_painter_atlases_albedo_glowmask.png` | Albedo + Glowmask aller drei Props |
| `ma5_validate_and_compile.txt` | Painter/validate_geo/compileJava im Volltext |
