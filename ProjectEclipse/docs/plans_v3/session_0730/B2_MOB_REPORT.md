# B2 — Mob-Paket (Welle 13)

**Auftrag:** FX_CENSUS_WAVE13 §7 Welle B Zeile B2 — Bewegungspaket für die Mob-FX,
N12 Gaze-Tether, `scare_*`-Politur, N6 Flüster-Hände.

**Datei-Besitz (exklusiv):** `tools/photon/mobs_fx.py`, `tools/photon/scare_fx.py` +
deren `.fx`/`.fxproj`, `veilfx/MobPhotonFxRows.java`, `client/scare/ScareDirector.java`.

---

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 0.1 `AUTO_ROTATE_LOOK` — Achsenkonvention (Photon 2.1.5, disassembliert)

`com.lowdragmc.photon.client.fx.EntityEffectExecutor.tick()`, `tableswitch` Fall 2:

```java
Vec3 look = entity.getLookAngle();
root.updateRotation(new Quaternionf(this.rotation)
        .rotateXYZ(0.0F, (float) Math.atan2(-look.z, look.x), (float) look.y));
```

JOML `rotateXYZ(ax, ay, az)` = `q · Rx · Ry · Rz`, ein lokaler Vektor durchläuft also
**erst Rz, dann Ry**. Mit `h = √(lx²+lz²)`, `θy = atan2(-lz, lx)`, `θz = ly`:

| lokal | → Welt |
|---|---|
| `+X` | `(cos θz·lx/h, sin θz, cos θz·lz/h)` ≈ **die Blickrichtung** |
| `−Z` | `(lz/h, 0, −lx/h)` = Blick **90° horizontal weggedreht** |

**Befund: `gazer_gaze_beam` hat einen echten Bug.** Der Faden endet auf
`end=(0, 0, −14)` und schießt damit seit dem Shipping *quer* zum Blick statt entlang.
Die Hypnose-Ringe stehen aus demselben Grund in der falschen Ebene. Fix: `end` auf
lokal `+X`, Ring-Shape 90° um Z gedreht (XZ-Kreis → YZ-Kreis, senkrecht zum Blick),
`facing_mode="EMITTER_TRANSFORM_YZ"`.

### 0.2 Bewegungsfeatures (Modell aus `wandfx2_fx.py` §A1, gegen `fxlib.py` geprüft)

* `distanceRate` — Partikel pro **gelaufenem Block** des Executors. Greift nur, wo der
  Executor sich bewegt: bei Mobs also die **entity-attached** Lanes (`spawnOnEntity` /
  `PhotonMobFx`-Loops). Bei positions-verankerten Cues (`glitch_pop`, `scare_*`) bleibt
  `accumulatedDistance` 0 → No-Op, dort NICHT verwendet.
* `inheritVelocity` — `{mode: CURRENT|INITIAL, multiply: NF}`, addiert
  `emitterVelocity·multiply` in **Welt**-Raum. Auf `simulation_space="World"`-Emittern
  zieht ein POSITIVES `multiply` die Partikel mit (Kielwasser); auf `"Local"`-Emittern
  reitet der Partikel schon auf dem Transform, dort ist ein **NEGATIVES** `multiply`
  der Schleif-/Nachzieh-Regler. Genau das ist "Auren reißen beim Laufen mit".
* `colorBySpeed` — Eingang ist `|realVelocity|·20`, also **Blöcke/Sekunde**; das
  Ergebnis **multipliziert** die Lifetime-Farbe (heißes Ende deshalb ~weiß). `speedRange`
  ist eine LDLib2-`Range` mit den Codec-Feldern `a`/`b` — **nicht** das `min`/`max`-Paar,
  das `fxlib._min_max` schreibt. Also immer über `with_module("colorBySpeed", …)`.
  → `hound_lunge_windup` benutzt aktuell `with_curves(color_by_speed=…)` und schreibt
  damit einen Range, den der Codec nicht liest: **stiller Defekt**, wird mitgefixt.
* `random_gradient` — zwei Ramps, pro Partikel gemerkt gelerpt. Gegen den Klon-Look.

### 0.3 Leitplanken, die hier beißen

* `fxlib.AraTrailEmitter` schreibt `section`/`physicsSetting` **ohne** `_enable: 1b`;
  beide sind LDLib2-`ToggleGroup`s und deserialisieren sonst DISABLED →
  `AraTrailParticle.updatePhysics` läuft gar nicht. Helper `ara_toggles_on` (aus
  `fx_boss_herald_ferryman.py`) wird lokal kopiert. Betrifft `hound_dash_trail` und
  `shadow_bolt_ribbon`: deren `physics=dict(inertia=…)` ist heute **wirkungslos**.
* `section`-Tubes sind in 2.1.5 kaputt → kein `section`, stattdessen Ribbon-Stacks.
* HDR-Deckel 1.45. Alpha-Blend + `vertexSortingMode NONE` = Lint.
* `EntityEffectExecutor`-Offsets sind Welt-Achsen → lokale Offsets ins Asset backen.

### 0.4 Besitz-Kollisionen im Zensus (Integrator muss schlichten)

1. **`revenant_fog_ribbons`** wird heute von `backlog_fx.py` erzeugt (A5: "tyrant-Teile"),
   die `.fx`-Outputs `fx/revenant_*` stehen aber in **B2s** exklusiver Liste. Da
   Konflikt-Gesetz 1 "ein `.fx` gehört genau EINEM Generator" verlangt, wird der Builder
   **nach `mobs_fx.py` umgezogen** und in `backlog_fx.py` chirurgisch entfernt
   (Docstring-Zeile, Funktion, `BUILDERS`-Eintrag — sonst nichts). Siehe §6.
2. **`award_star_shower` / `award_star_glint` / `boss_intro_shockwave`** liegen in
   `mobs_fx.py` (B2), sind laut §7 aber B6- bzw. A8-Outputs. **Nicht angefasst** —
   bleiben bit-identisch, damit B6 sie später gefahrlos übernehmen kann.
3. **`GlitchZoneFx`** (B4) hält nur `effect/strength/colour/origin`, **keinen Radius**
   und exportiert nur `handle(...)`. Ein echter Zonen-Rand-Anker für N6 ist damit ohne
   B4-Änderung unmöglich → N6 wird laut Auftrag die **ScareDirector-Variante**
   (Anker vor dem Spieler in Blickrichtung). Patch-Snippet für B4 in §7.

---

## 1. Bewegungspaket pro Asset

| Asset | Lane (Executor) | Maßnahme |
|---|---|---|
| `hound_lunge_windup` | Entity, `NONE`, Hund **verwurzelt** | `colorBySpeed` über `with_module` reparieren (Range `a`/`b`, 0.05–0.45 b/s = Kollaps-Tempo); `random_gradient` auf dem Spiral-Ramp. Kein `inheritVelocity`/`distanceRate`: der Hund steht in der Windup-Phase still (No-Ops). |
| `hound_dash_trail` | Entity, `FORWARD`, **schnellste Lane** | `ara_toggles_on` → Physik-Lag wird erst jetzt real; `vertex_sorting="DISTANCE"` (Lint); geeaste `thicknessOverLength` (Lint); **NEU `dash_grit`**: World-Space-Emitter mit `distance_rate` (0.35 Blöcke/Partikel), `inheritVelocity +0.3` und `colorBySpeed` (Slate → Weißglut). Das ist der Kern-Auftrag "distanceRate auf hound_dash_trail". |
| `gazer_gaze_beam` | Entity, `LOOK` | N12, siehe §2. |
| `other_dread_aura` | Entity, `NONE`, Local | `inheritVelocity −0.35` auf `light_eater` und `−0.5` auf `violet_motes` → das Leichentuch reißt beim Laufen nach; `distance_rate` auf den Motes (Aura schüttet mehr, wenn er auf dich zukommt); `random_gradient` auf den Motes. **Kein** `colorBySpeed`: die Aura darf nie aufhellen (sie frisst Licht). |
| `wanderer_static_shroud` | Entity, `NONE`, Local | `inheritVelocity −0.4` (paint_haze) / `−0.55` (static_seams) + `distance_rate` auf den Seams. `random_gradient` auf beiden. **Kein** `colorBySpeed`/HDR: `shade:1b` ist das Konzept (Flicker-Sync), HDR auf Alpha+shade wäre `LINT-HDR-DUST`. |
| `sentinel_alert` | Entity-Edge, one-shot | 3× `LINT-LINEAR-CURVE` auf `wink.sizeOverLifetime` fixen (Pop-Shrink); `random_gradient` auf dem Blüten-Puff. Statue ist eingefroren → keine Bewegungsfeatures. |
| `sentinel_petal_orbit` | Entity-Loop, Statue eingefroren | `random_gradient` gegen den Klon-Look. Bewegungsfeatures wären No-Ops (Loop läuft nur, während `isFrozen()`). |
| `shadow_bolt_ribbon` | Entity, Projektil | `ara_toggles_on`; geeaste `thicknessOverLength` (Lint); `wither_motes`: `inheritVelocity 0.3 → 0.45`, `distance_rate`, `colorBySpeed`, `random_gradient`. |
| `glitch_pop` | **Positions**-Cue | 3× `LINT-LINEAR-CURVE` fixen. Bewegungsfeatures sind hier nachweislich No-Ops (Welt-Anker, `accumulatedDistance` bleibt 0). |
| `revenant_fog_ribbons` | Entity-Loop, Local | Nach `mobs_fx.py` umgezogen; `inheritVelocity −0.4` (Saum reißt beim Driften mit), `distance_rate`, `random_gradient` auf dem Nebelkörper. `trails`-Modul bleibt unangetastet. |

## 2. N12 Gaze-Tether

**`gazer_gaze_beam` (Upgrade)**

1. Frame-Bug fixen (§0.1): Beam `end=(14, 0, 0)`, Cullbox entlang `+X`, Ringe in die
   YZ-Ebene (`rotation=(0,0,90)` auf dem Circle-Shape) mit `EMITTER_TRANSFORM_YZ`.
2. **Zäher Faden:** drei `ara_trail_emitter`-Strähnen an einem Empty bei lokal
   `(+3.2, 0, 0)`, `space="World"` + `physicsSetting` (`ara_toggles_on`) mit
   *unterschiedlicher* `inertia`/`damping`/`time`. Steht der Kopf still, decken sie sich
   exakt (kein Mehrkosten-Read); schwenkt der Kopf, fächern sie auf und schleppen nach —
   das ist der "zähe Faden, der nachschwingt". Beim Wegreißen laufen die Segmente aus
   und der Strang zerfasert sichtbar.
3. **Spannungsperlen** (`tension_beads`): World-Space am Faden-Anker, `inheritVelocity`
   positiv → beim Kopfschwenk werden sie weggeschleudert; `colorBySpeed` lässt sie
   dabei aufglühen. Stillstand = dunkel, Riss = kurz hell.
4. **Fransen** (`fray_wisps`): Local mit negativem `inheritVelocity` (Schleppe) +
   `random_gradient`.

**`gazer_tether_snap.fx` (NEU, one-shot 22 t)** — der Riss-Moment:
`snap_recoil` (Motes auf einer Schale ums Auge, radial **einwärts** = Schnur peitscht in
die Kapuze zurück, `colorBySpeed`), `fiber_shards` (dunkelviolette Stretched-Splitter),
`loss_pop` (ein **dunkler**, nicht heller Pop = das Licht geht aus). Bewusst
rotations-agnostisch (radial + Pop), damit `AUTO_ROTATE_NONE` reicht.

**Trigger (`MobPhotonFxRows.java`, eigener Besitz):** ein verschachtelter
Client-Tick-Watcher. Der Gazer hat keinen synchronisierten Ziel-Flag, aber seine
Kopf-/Körperdrehung ist client-sichtbar (`LookAtPlayerGoal`). Der Watcher misst den
Winkel zwischen Gazer-Blick und Richtung zum lokalen Spieler:
Anhaften ≤ 25°, Lösen > 45° (Hysterese, damit Idle-Wackeln nicht triggert), plus
Reichweiten-Gate 20 Blöcke (+2 Release-Band) und Cap 2 = dieselben Zahlen wie die
`PhotonMobFx`-Gazer-Row. Löst der Faden (Winkel, Sichtlinie, Reichweite, Verschwinden per
`VanishWhenSeenGoal`), feuert der Snap; Cap-Verdrängung und Level-Wechsel verwerfen ihn
still, weil dort nichts reißt (§6.4). Damit braucht N12
**keinen** Server-Cue, keine `FxCues`-Konstante und keine Änderung an `PhotonMobFx`
(gehört B2 nicht).

## 3. `scare_*`-Politur

* **HDR-Deckel 1.45**: `wraith_veil` (1.6/1.7/2.0), `wraith_core` (2.0/2.1/2.6),
  `swarm_stragglers` (1.1/1.6/1.4) werden hue-erhaltend geklemmt.
* **Dunkle Birth-Tints (V2.1-Stacking-Gesetz)**: `swarm_motes`, `swarm_rush`,
  `wraith_body`, `wraith_veil`, `wraith_core` starten heute alle auf `*_HOT` bei t=0.
  Zwei Dutzend Sprites im selben Halbblock direkt vor der Kamera konvergieren damit zur
  Sprite-Eigenfarbe (weißgrüner bzw. weißer Klumpen). Alle Ramps starten künftig auf
  `*_DEEP` und blühen erst bei t≈0.1–0.15 auf.
* **Timing-Snap gegen die Skript-Beats** (`ScareScripts`):
  * `swarm` (Photon bei t=3 und t=20, `VEX_CHARGE` bei 24, `EVENT_RIFT_SLAM` + Shake
    bei 50): Rush-Welle 2 von intern 14 → **21** (= Skript 24 der ersten Instanz, auf
    dem Charge-Sound) und eine dritte Welle bei intern **30** (= Skript 50 der zweiten
    Instanz, auf dem Slam). Vorher lag zwischen Charge und Slam visuell nichts.
  * `phantom_swoop` (Photon bei t=4, `PHANTOM_BITE` + Flash + Shake bei 26): Das Asset
    war bei intern 22 (= Skript 26) längst leer — der Biss hatte **kein** Photon-Bild.
    Neu: `wraith_bite` (dunkler Fetzen-Rückstoß) + ein zweiter, gedämpfter Pop auf
    intern 22.
* `colorBySpeed` auf den schnellen Lanes (`swarm_rush`, `wraith_veil`) und
  `random_gradient` überall — die zwei Assets feuern über 30 Jumpscares hinweg immer
  wieder, der Klon-Look ist hier am teuersten. `distanceRate`/`inheritVelocity` bleiben
  draußen: `ScareDirector.spawnPhoton` verankert an einer **Weltposition**, der Executor
  bewegt sich nicht (§0.2).

## 4. N6 Flüster-Hände

`whisper_hands.fx` (60 t ≈ 3 s) + Skript-Variante `whisper_hands` in der
Jumpscare-Registry.

* **Anker:** `ScareDirector.spawnPhoton` rotiert **nicht** zur Kamera (siehe Klassen-Doc
  in `scare_fx.py`). Das Asset ist deshalb rotations-agnostisch gebaut: die Hände steigen
  **von unten** aus einem Nebelsaum und greifen **aufwärts + radial einwärts** zur
  Ankermitte. "Unten" und "einwärts" lesen aus jedem Kamerawinkel; der Photon-Beat setzt
  den Anker per `forward`/`up` vor das Gesicht — also exakt "vor dem Spieler in
  Blickrichtung", ohne eine einzige Zeile in `ScareDirector` zu riskieren.
* **Textur:** neue deterministische `hand_reach.png` (PIL, im Generator) — eine
  greifende Hand-Silhouette mit weichem Alpha. Ohne eigene Textur bleiben es Rauchbälle
  und das Konzept ("Hände") ist nicht lesbar.
* **Emitter:** `fog_bed` (Nebelsaum unten), `fog_hands` (Vertical-Billboards, radial
  einwärts + aufwärts, `random_gradient` gegen sechs identische Hände),
  `finger_wisps` (Motes, die von den Fingerspitzen einwärts ziehen), `grasp_rot`
  (dunkler Zerfall exakt auf dem Reach-Peak t=34). Alles Alpha, dunkle Birth-Tints,
  gar kein HDR.
* **Registry:** `ScareIds.JUMPSCARES` (31.) + `ScareScripts`-Builder + Langdrop
  `docs/plans_v3/langdrop/B2-MOB.json`. Beides sind **additive** Einzeiler-Erweiterungen
  in Dateien, die kein anderes Welle-13-Team besitzt; die Abweichung vom Besitz-Zettel
  (der auf `ScareDirector` zeigt) ist in §7 dokumentiert.

## 5. Arbeitsschritte

1. `mobs_fx.py` (Helper, Bewegungspaket, N12, revenant-Umzug) → regen + `.fxproj`.
2. `scare_fx.py` (Politur, `whisper_hands`, Textur) → regen + `.fxproj`.
3. `backlog_fx.py`: chirurgische Entnahme des revenant-Builders.
4. Java: `MobPhotonFxRows` (Watcher), `ScareIds`, `ScareScripts`, Langdrop.
5. `python3 tools/photon/fxlib.py validate --lint` — 0 NEUE Findings.
6. `./gradlew compileJava`.
7. Polish-Iteration (kritischer Diff-Review) + Report.

---

## 6. Ergebnis

### 6.1 Geänderte / neue Dateien

| Datei | Art | Inhalt |
|---|---|---|
| `tools/photon/mobs_fx.py` | geändert (Besitz) | Bewegungspaket, N12-Faden + Snap-Builder, Frame-Bug-Fix, Revenant-Umzug, Lint-Fixes |
| `tools/photon/scare_fx.py` | geändert (Besitz) | Stacking-Politur, Timing-Snap, `wraith_bite`, N6 `whisper_hands` + `hand_reach.png`-Generator |
| `tools/photon/backlog_fx.py` | geändert (chirurgisch) | **nur** Docstring-Zeile + `build_revenant_fog_ribbons` + `BUILDERS`-Eintrag entfernt (§0.4.1) |
| `veilfx/MobPhotonFxRows.java` | geändert (Besitz) | `GazeTetherWatcher` (N12-Trigger), Klassen-Doc |
| `client/scare/ScareScripts.java` | geändert (additiv) | `whisper_hands`-Skript + `FX_HANDS` + `HAND_REACH` |
| `scare/ScareIds.java` | geändert (additiv) | 31. Jumpscare-ID `whisper_hands` |
| `docs/plans_v3/langdrop/B2-MOB.json` | **neu** | 2 Keys × 2 Sprachen (Haus-Regel: keine Handedits an den Lang-JSONs) |
| `fx/gazer_tether_snap.fx(proj)` | **neu** | N12-Riss |
| `fx/whisper_hands.fx(proj)` | **neu** | N6 |
| `textures/particle/hand_reach.png` | **neu** | N6-Handsilhouette (deterministisch aus dem Generator) |
| `fx/{hound_dash_trail, hound_lunge_windup, gazer_gaze_beam, other_dread_aura, wanderer_static_shroud, sentinel_alert, sentinel_petal_orbit, shadow_bolt_ribbon, glitch_pop, revenant_fog_ribbons, scare_swarm, scare_wraith}.fx(proj)` | regeneriert | siehe §1–§4 |
| `tools/photon/lint_baseline.txt` | gepflegt | 9 Einträge entfernt, die dieser Pass wirklich behebt |

`ScareDirector.java` blieb **unverändert**: `spawnPhoton` rotiert nicht zur Kamera, und N6
ist genau deswegen rotations-agnostisch gebaut (§4). Eine globale Yaw-Rotation dort hätte
`scare_swarm`/`scare_wraith` mitverändert — Risiko ohne Gegenwert.

### 6.2 Status

* `python3 tools/photon/fxlib.py validate --lint` → `264 file(s), **0 NEW** error/warn,
  27 grandfathered, 129 advisory info`.
* `./gradlew compileJava` → **BUILD SUCCESSFUL**, keine neuen Warnungen (die zwei
  `EventBusSubscriber.Bus`-Deprecations stehen auf der *bestehenden* Annotation Zeile 59).

### 6.3 Verifikation ohne laufende Instanz

Zwei Harnesses, beide außerhalb des Repos (`/tmp`, nicht eingecheckt — Haus-Regel
"No text-based tests"):

1. **`/tmp/b2_verify.py`** liest die *ausgelieferten* gzip-NBT-Binaries zurück und prüft
   jede Behauptung dieses Reports am Artefakt: **80/80 PASS**. Inklusive
   Kontroll-Sektion, die dieselben Prüfungen gegen `git show HEAD:` fährt — die
   Birth-Tint-, HDR-, Achsen-, `_enable:1b`- und `inheritVelocity`-Checks **schlagen dort
   fehl**, ein Check der auf dem alten Stand nicht failen kann ist kein Beweis.
2. **`/tmp/B2Contract.java`** lädt die *kompilierte* `ScareIds` und prüft den Vierer-Vertrag
   ID ↔ `ScareScripts`-Builder ↔ Lang-Key ↔ `.fx`-Datei plus die Watcher-Invarianten:
   **22/22 PASS** (u. a. `isJumpscare("whisper_hands")`, `HAND_REACH == HAND_REACH_TICK`,
   jeder `fx(...)`-Verweis existiert auf der Platte, `PhotonMobFx` unberührt).

**Offen: die visuelle In-Game-Abnahme.** Auf der VM laufen bereits zwei fremde
Minecraft-JVMs (≈7,7 GB RSS, ~3 GB frei); ein dritter Client hätte realistisch den
OOM-Killer auf eine fremde Session gehetzt. Die Kommandos dafür stehen in §6.5.

### 6.4 Polish-Iteration (kritischer Diff-Review, Runde 2)

Drei echte Defekte im eigenen Diff gefunden und behoben:

1. **Phantom-Snap nach Portal/Respawn.** Der Watcher hielt Entity-IDs über einen
   `ClientLevel`-Wechsel hinweg; im neuen Level sind sie "verschwunden" → er hätte den
   Riss an *stale Weltkoordinaten* in der falschen Dimension gefeuert. Jetzt hängt an der
   Map eine `WeakReference<ClientLevel>`, ein Level-Wechsel verwirft still.
2. **Riss an einem Faden, den es nie gab.** Die Gazer-Row hat `cap = 2` — nur die zwei
   nächsten Kapuzen haben überhaupt einen Faden. Der Watcher kannte den Cap nicht und
   hätte auch beim dritten Gazer gerissen. Jetzt spiegelt er Row-Gate *und* Cap exakt
   (inkl. `player.position()` als Messpunkt, wie `PhotonMobFx`), und wer vom Cap verdrängt
   wird, verliert den Tether **ohne** Snap — dort blendet der Loop sanft aus, da reißt
   nichts.
3. **Lang-Handedit.** Die zwei neuen Keys lagen direkt in `en_us.json`/`de_de.json` —
   AGENTS.md verbietet das während Parallelarbeit. Jetzt `langdrop/B2-MOB.json`; die
   Lang-JSONs sind wieder bit-identisch zu HEAD. Gegenprobe:
   `python3 tools/langmerge/merge_langdrops.py B2-MOB.json` erzeugt **exakt** den
   zurückgenommenen Diff (`en_us +2, de_de +2; parity OK`).

### 6.5 Test-Kommandos

Voraussetzung: `./gradlew build`, dann `./gradlew runClient` (Client nötig — alle vier
Punkte sind Client-Renderpfade). Photon-Befehle brauchen einen Spieler-Kontext.

```
# 1) Einzelassets direkt (Position = vor dir, damit die Cullbox nicht beißt)
/dev photon test "eclipse:gazer_tether_snap"
/dev photon test "eclipse:whisper_hands"
/dev photon test "eclipse:hound_dash_trail"
/dev photon status                      # Registry-Rows + geladene Assets

# 2) N6 als echter Jumpscare (Skript-Beats, Sound-Sync, Text)
/dev jumpscare whisper_hands
/dev jumpscare list                     # muss 31 Einträge zeigen

# 3) N12 end-to-end: Gazer spawnen, anstarren, dann Blick brechen
/summon eclipse:gazer ~ ~ ~5
#   -> Faden erscheint (<= 20 Blöcke). Kopf des Gazers schwenken lassen bzw.
#      hinter eine Wand treten / ihn anstarren bis VanishWhenSeenGoal ihn verwirft:
#      der Snap muss GENAU EINMAL feuern (nicht pro Tick, nicht beim Wackeln).

# 4) Bewegungspaket (distanceRate ist nur sichtbar, wenn das Vieh wirklich läuft)
/summon eclipse:hound ~ ~ ~8            # Dash provozieren -> Grit-Linie am Boden
/summon eclipse:the_other ~ ~ ~6        # Aura muss beim Laufen nachschleifen
/dev photon test "eclipse:revenant_fog_ribbons"
```

## 7. Für den Integrator

### 7.1 Abweichungen vom Besitz-Zettel (bewusst, minimal)

1. **`ScareIds.java` + `ScareScripts.java`** (je additiv, ~40 Zeilen). Der Auftrag sagt
   "Jumpscare-Registry F-065 — neue Variante dort registrieren" und zeigt auf
   `ScareDirector.java`; die Registry liegt real in diesen beiden Dateien
   (`ScareDirector` *konsumiert* sie nur). Kein anderes Welle-13-Team schreibt dort.
2. **`backlog_fx.py`**: nur die drei Revenant-Zeilen entnommen (§0.4.1). Die
   A5-Tyrant-Teile der Datei sind unberührt.
3. **`glitch_pop.fx`** liegt in `mobs_fx.py` und wurde mit-regeneriert (Lint-Fix) — falls
   B4 dieses Asset beansprucht: der Diff ist ausschließlich `sizeOverLifetime`
   linear → geeast.

### 7.2 Patch-Snippet für B4 — echter Zonen-Rand-Anker für N6 (optional)

N6 läuft heute als ScareDirector-Variante, weil `GlitchZoneFx` den Zonen-**Radius** nicht
publiziert. Wenn B4 das freigibt, kann N6 ohne Asset-Änderung an den echten Rand wandern:

```java
// client/GlitchZoneFx.java (B4) — additiv, kein Verhalten geändert:
/** Nearest active zone edge point toward the camera, or null if no zone is active. */
public static Vec3 nearestEdge(Vec3 camera) {
    Zone best = null;
    double bestDist = Double.MAX_VALUE;
    for (Zone zone : ACTIVE.values()) {          // ACTIVE is already the synced map
        double d = zone.origin().distanceTo(camera);
        if (d < bestDist) { bestDist = d; best = zone; }
    }
    if (best == null) return null;
    Vec3 out = camera.subtract(best.origin());
    if (out.lengthSqr() < 1.0E-4D) out = new Vec3(1.0D, 0.0D, 0.0D);
    return best.origin().add(out.normalize().scale(best.radius()));   // radius() needed
}
```

Verbraucher in `ScareDirector` (B2-Besitz) wäre dann ein Vorzugs-Anker für genau diesen
einen Scare — das Asset selbst bleibt gleich, weil es rotations-agnostisch ist.

### 7.3 Patch-Snippet: N12 serverseitig statt client-lokal (nur falls gewünscht)

Der Watcher braucht **nichts** davon. Wer den Riss lieber autoritativ vom Server hätte:

```java
// FxCues.java:  public static final ResourceLocation CUE_GAZE_SNAP = cue("gaze_snap");
// GazerEntity#stopStaring(ServerPlayer target):
FxCuePackets.sendTo(target, FxCues.CUE_GAZE_SNAP, this.getEyePosition());
```

Dann in `MobPhotonFxRows` eine normale `Row` registrieren und den Watcher entfernen. Die
Client-Lösung wurde bevorzugt, weil sie ohne Wire-Traffic, ohne `FxCues`-Konstante und
ohne Änderung an fremden Dateien auskommt.
