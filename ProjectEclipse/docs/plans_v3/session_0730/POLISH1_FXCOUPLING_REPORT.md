# POLISH1 — „FX-Kopplungswelle": die drei SPEC-ONLY Photon-Kopplungen implementiert

**Auftrag:** Die F-099-Eval-Runde fand drei Mob-Reports, deren Photon-Kopplung als
„SPEC ONLY" deklariert war — spezifiziert, nie gebaut. Alle drei sind jetzt real:

| Report | Kopplung | Status vorher | Status jetzt |
|---|---|---|---|
| MB2 §7 (Wizard Orin) | `star_call` Dirigier-Child-fx | Snippets im Report | Asset ×2 + Cue + Row + Sender, anim-synchron |
| MC3 §7 (Drift Lantern) | `flicker_dip`/`flicker_surge` via Timeline-Keyframes | Spec-only | Timeline im Sheet = SSOT + Keyframe-Handler + 2 Assets |
| MC2 §0/§9.4.6 (Umbral Stalker) | Sprint-Smear an `fx_smear_l/r` | Leere Locator-Bones | PhotonMobFx-LoopRow + Speed-Gate + Asset |

**Nicht angefasst:** `EclipseGeoMob`/`EclipseGeoMonster`, Storm-Dateien, Wand/Artifact/
Heart-Extractor-Items, `umbral_blade`/`umbral_pick`/`ferryman_toll`. FX-Registries nur
additiv (1 Cue, 1 Row-Registrar, 1 LoopRow).

**Live-Client-Hinweis:** Photon cached `.fx` statisch — nach dem Regenerieren in einer
laufenden Instanz `/photon_client clear_client_fx_cache` ausführen (F3+T lädt sie NICHT).

---

## 0. Anker-Mathe (bytecode-verifiziert, nicht geraten)

Alle drei Kopplungen reiten Photons `EntityEffectExecutor` (Anker = Augenposition +
World-Space-Offset; die LOKALEN Achsen des Effekts rotieren per `AutoRotate`).
`javap -c` gegen das gebundelte Photon-Jar, Tick-Branch 3 (`XROT`):

```
rotation = rotateY(toRadians(-90 − visualBodyYaw))
→ Effekt-lokal +X = Entity-VORWÄRTS, +Z = Entity-RECHTS, +Y = hoch.
Geo-Space-Mapping (Bedrock-Geo schaut -Z, +X = Entity-LINKS):
geo (gx, gy, gz) → lokal (x = -gz/16, z = -gx/16); y über den Augen-Offset.
```

Konsequenz für alle drei Assets: **laterale Bone-Offsets werden ins Asset GEBACKEN**
(nur lokale Koordinaten drehen mit dem Körper — der Executor-Offset ist World-Space
und würde beim Drehen von den Bones rutschen):

| Mob | Auge | Bone (Geo) | Asset-lokal | Row-Offset |
|---|---|---|---|---|
| Orin | 1.80 | Staff-Tip geo x −5 px (0.3125 b RECHTS) | z +0.31 | (0, −0.40, 0) → Anker 1.40 b über Fuß (MB2 §7.4) |
| Drift Lantern | 0.75 | `cage`-Zentrum y ≈ 12 px = 0.75 b | — | null — Auge IST das Cage-Zentrum (MC3 §7 Rb. 4) |
| Umbral Stalker | 0.85 | `fx_smear_l/r` geo (±3.5, 11, −2) | (+0.125, 0, ∓0.219) | (0, −0.1625, 0) → Pivot-Höhe 0.6875 b |

## 1. Wizard Orin `star_call` (MB2 §7)

### 1.1 Assets: `eclipse:wizard_star_call` + `_fast` (Generator `tools/photon/fxcoupling_fx.py`)

Vier Stufen — gather → release → conduct, exakt der Hero-Moment-Bogen aus der Quality-Bar
(die Descent-Streaks + Impacts selbst BLEIBEN Server-Partikel im `starZone`, MB2-Budget-Law:
die Zone ist für dieses Asset TABU):

| Emitter | Fenster | Design |
|---|---|---|
| `raise_motes` | 0 → Release | schmale steigende Mote-Säule am Staff-Tip (r 0.15, +0.8 b/s, Rate 6→22 p/s mit 0.7× Crouch-Dip bei 3.6t und Voll-Rampe ab dem Raise-Beat 11t — MB2-Zahlen wörtlich) |
| `gather_indraw` | Raise → Release | **Polish-Addition**: Funken auf breiter 0.85-b-Schale konvergieren mit −1.9…−2.6 b/s auf den Tip (invertierter Ramp dunkel→heiß, A5-Indraw-Lizenz) — Sternenlicht wird GERUFEN, die Antizipations-Hälfte des Flash |
| `release_ring` | Release-Beat | 24-Punkt-Radialring r 0.5→2.2 in 0.3 s (5.7 b/s), FLASH_CORE→FLASH_RIM→SACRED-Void |
| `release_beam` | Release-Beat | vertikaler Beam-Puls h 6 b, 4t — matcht den `glow_staff_tip` 1.9→2.6×-Snap des Sheets |
| `conducting_drizzle` | Release → Release+Shower | Stern-Staub-Vorhang r 1.6 b um Orin (World-Space — darf beim Torso-Drehen nicht mitschwirren), −0.4 b/s Fall, `star_2x2`-Flipbook-Twinkle ~3 Hz, gedimmtes #F5E6B8 α≤0.63; Anker +0.6 lokal = Geburt knapp über dem Hut |

**Zwei Varianten schließen MB2 §9.2s Ehrlichkeitslücke** („Anim-Akzent kommt 0.35 s zu
spät"): beide Casts teilen EIN Anim-Sheet, aber die Telegraph-Fenster differieren —

| Variante | Release-Beat | Shower-Fenster | gewählt wenn |
|---|---|---|---|
| `wizard_star_call` | 26t (Telegraph 25t + Timer-auf-−1) | 50t = 10 Bolts × 5t | `a` > 1.1 s |
| `wizard_star_call_fast` | 19t (Telegraph 18t) | 70t = 14 Bolts × 5t | `a` ≤ 1.1 s |

### 1.2 Java-Verdrahtung

* **`FxCues.CUE_WIZARD_STAR_CALL`** (additiv, hinter `CUE_WIZARD_CATALYST`): `a` =
  Sekunden bis zum Release-Beat (1.30 base / 0.95 unveiled), `b` = Shower-Sekunden
  (Bolts × 0.25, informativ).
* **`veilfx/WizardFxRows`** (neu, `MobPhotonFxRows`-Referenzmuster, `@EventBusSubscriber`
  Dist.CLIENT/MOD-Bus): eine Row, `Mode.LAYER`, Quasar-Leg `null` — die Vanilla-Basis
  (EVOKER_PREPARE_SUMMON + AMETHYST-Chimes + END_ROD-Zone-Sparkles + per-Bolt-Impacts)
  bleibt auf photon-losen Clients bit-identisch. Custom `PhotonLeg`: Entity-Lane mit
  `AutoRotate.XROT` + Offset (0, −0.40, 0); `a ≤ 1.1` → `_fast`-Asset (Cutoff mittig
  zwischen 0.95 und 1.30, float-wobble-sicher). Position-Degrade hebt den Fuß-Anker
  um 1.40 b auf Tip-Höhe.
* **`WizardOrinEntity.tickCombat`**: `FxPayloads.sendFxEntityEvent(...)` am
  Telegraph-START-Tick, im SELBEN Tick wie `triggerAction(ANIM_STAR_CALL)` — Säule
  startet mit dem Raise, Release-Flash landet auf dem Beat beider Cast-Varianten.

## 2. Drift Lantern `flicker` (MC3 §7)

### 2.1 Timeline-Keyframes als Single Source of Truth

`animation.drift_lantern.flicker` (0.8 s, `glow_flame`-Scale-Kurve) trägt jetzt den
`timeline`-Block aus MC3 §7 — vier Keys, jeder mit dem Scale-Faktor an diesem Frame
als Instruction-Payload:

```json
"timeline": {
    "0.06": "photon:flicker_dip 0.42",
    "0.26": "photon:flicker_dip 0.30",
    "0.46": "photon:flicker_dip 0.48",
    "0.58": "photon:flicker_surge 1.20"
}
```

**Kein paralleler Java-Timer.** `DriftLanternEntity.wireFlickerTimeline` registriert
einen `setCustomInstructionKeyframeHandler` auf dem `action`-Controller (Repo-Premiere —
POLISH2 §1.2 hatte verifiziert, dass es bislang NULL GeckoLib-Keyframe-FX gibt; das hier
ist der erste, exakt der von MC3 beschriebene Mechanismus). Der Handler filtert auf den
`photon:`-Prefix (der geteilte Controller könnte später weitere Timelines hören, Rb. 2),
parst den Faktor und ruft die client-only Klasse `client/entity/ambient/DriftLanternFx`.
Keyframe-Events feuern nur aus dem Client-Render-Pass; der explizite `isClientSide`-Guard
hält die Klasse zusätzlich aus einem Dedicated-Server-Classloader. Wer die Scale-Kurve
retimet, MUSS die Timeline mitziehen (im Sheet direkt nebeneinander).

### 2.2 Assets: das LICHT flackert, nicht die Flamme

Die Flamme schrumpft das Sheet selbst; die gebackene Cage-Glowmask kann aber nicht
dimmen (MC3 §6: Glow-Layer depth-rejected unter dem transluzenten Glas). Die Photon-Seite
spielt deshalb den SCHEIN:

* **`lantern_flicker_dip`** — `light_gulp`: EIN weiches dunkles Quad, `REVERSE_SUB`
  (dst−src, IDEAS-mobs-#5-Zwei-Pass-Law — funktioniert ohne Bloom), frisst ~9% Luminanz
  für 7t am Cage-Zentrum. Gulp-Menge lebt im `startColor` (0xFF17181D); die
  `colorOverLifetime`-Rampe ist ein WEISSER Alpha-Umschlag, weil Photon Ramp × startColor
  MULTIPLIZIERT (glitch_pop-Law) und die Subtraktion sich sonst selbst quadriert.
  `orderInLayer −1`: der Schatten zeichnet vor den anderen Transluzenten. Dazu
  `soot_flecks`: 2 dunkle Ruß-Flocken gluckern nach UNTEN aus der würgenden Flamme
  (Cone um 180° gedreht, World-Space, Gravity — sie fallen aus der Drift raus).
* **`lantern_flicker_surge`** — `recovery_flash` (5t, LAN_HOT→Teal, additiv, lights 15),
  `cage_relight` (breites Teal-Sheet OHNE HDR, dunkel geboren — schwillt aus dem
  Gulp-Schatten statt weiß zu poppen, V2.1) und `soul_puff` (4 Motes steigen World-Space
  aus der überschießenden Flamme — das Client-Echo des Server-SCULK_SOUL-Puffs, aber
  AUF dem Beat).

**Executor-Scale trägt den Keyframe-Faktor** (Rb. 4): Dips mappen tiefere Senke →
größerer Gulp (`×(1.55 − factor)`: 0.30→×1.25, 0.42→×1.13, 0.48→×1.07), der Surge
spielt sein eigenes 1.2×. `allowMulti` erzwungen — drei Dips landen binnen 0.4 s auf
DERSELBEN Entity und Photons per-Entity-CACHE-Dedup würde Nr. 2 und 3 sonst schlucken.

## 3. Umbral Stalker Sprint-Smear (MC2 §0/§9.4.6)

### 3.1 Asset: `eclipse:stalker_sprint_smear` — ein SCHATTEN, kein Glow

* **`smear_ribbon_l/r`** (2 Ara-Trails an den gebackenen Flank-Pivots): World-Space-
  Segment-Lag + Inertia-Physik (gravity −0.35, inertia 0.5, damping 0.68) — die Wisps
  reißen ab und setzen sich hinter dem Galopp. Dunkle ALPHA-Ribbons (SMEAR_DARK→GLI_DEAD)
  DUNKELN was hinter ihnen liegt — kein Additiv, kein HDR, die Nacht selbst verschmiert.
  `section`/`physicsSetting` ToggleGroups explizit `_enable: 1b` (W13/B2-LDLib2-Finding).
* **`umbral_flecks`** (≤20): `distanceRate 0.45` — geshedded pro GELAUFENEM BLOCK, der
  Smear skaliert damit GRATIS mit der echten Geschwindigkeit (Quality-Bar-Wunsch).
  Positive `inheritVelocity` 0.3 = Wake-Drag, sinken mit gravity 0.04.
* **`violet_glints`** (≤8, `distanceRate 0.5`): der NACHT-Read. Der Stalker jagt bei
  Licht 0, wo ein dunkles ALPHA-Ribbon nichts zu dunkeln hat — die seltenen, dunkel
  geborenen Spine-Glow-Funken (COR_VIOLET/COR_INK, HDR ≤1.0) taggen den Trail als
  umbral, bleiben aber viel zu dim um den Schatten je aufzuhellen.

### 3.2 Attach-Gate: sprint-only UND echte Geschwindigkeit

`UmbralStalkerEntity` (client-only, wie der bestehende `sprintHold`):
`updateSmearGate()` nimmt dasselbe Verdikt wie der Gait-Controller (Hunt-Latch ODER
Dawn-Flight) und verlangt ZUSÄTZLICH echten Bodengewinn — per-Tick-Positionsdelta
≥ 0.08 b/t (1.6 b/s; A*-Mikropausen und wandgepinnte Pfade fallen drunter, der
Bounding-Galopp ~0.3+ b/t liegt weit drüber). Ein Speed-Smear auf einem stehend
knurrenden Stalker wäre eine Lüge. Eigener 6t-Latch überbrückt Repath-Mikropausen;
`isSprintSmearing()` ist das Attach-Prädikat.

`PhotonMobFx`-LoopRow (additiv, hinter der Deckhand-Row): `AUTO_ROTATE_XROT` +
Offset (0, −0.1625, 0), Reichweite 32 b, Nearest-4 (Packs sind 3–4 Tiere; verdoppelte
Umbral-Night-Packs bleiben budget-gekappt). Detach = graceful release, die Ribbons
faden mid-stride aus statt zu poppen.

## 4. V2.1-Stacking-Law-Compliance

* Birth-Tints DUNKEL: STAR_BIRTH (0.10/0.12/0.18) unter SAC_VOID, LAN_BIRTH,
  SMEAR_DARK — jede additive Rampe wird unter ihrem Fade-Ziel geboren.
* Breite Schalen: Indraw r 0.85, Drizzle r 1.6, Fleck-Sphären 0.22–0.28 (nie Punktquelle).
* Getrimmte Counts: star_call worst case ≈ 70 live, Lantern-Pulse ≤ 12, Smear ≤ 30 + 2
  Ribbons. HDR überall ≤ 1.45 (Wave-13-Ceiling, `hdr()`-Clamp im Generator hält die
  Kanal-Ratio = den Farbton).
* Dunkelheit aus REVERSE_SUB / dunklen ALPHA-Quads, nie aus Dark-Bloom.

## 5. Validierung (alle Gates grün)

```
$ python3 tools/photon/fxcoupling_fx.py
WROTE …/wizard_star_call.fx       (raw 15573 B, gzip 2519 B) — valid, + .fxproj
WROTE …/wizard_star_call_fast.fx  (raw 15573 B, gzip 2515 B) — valid, + .fxproj
WROTE …/lantern_flicker_dip.fx    (raw  6769 B, gzip 1615 B) — valid, + .fxproj
WROTE …/lantern_flicker_surge.fx  (raw  9468 B, gzip 1680 B) — valid, + .fxproj
WROTE …/stalker_sprint_smear.fx   (raw 10146 B, gzip 2047 B) — valid, + .fxproj

$ python3 tools/photon/fxlib.py validate --lint
lint: 272 file(s), 0 NEW error/warn, 27 grandfathered, 142 advisory info
      (kein einziger Lint-Fund — auch kein advisory — auf den 5 neuen Assets)

$ python3 scripts/geckolib_gen/validate_geo.py \
      …/geo/entity/drift_lantern.geo.json …/animations/entity/drift_lantern.animation.json
validate_geo: 2/2 file(s) passed — all good
  (1 erwartete WARN: "'timeline' present — handlers must be wired" — der Handler IST
   im selben Commit verdrahtet, exakt das von MC3 §7 antizipierte Sheet+Controller-Paar)

$ flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain
BUILD SUCCESSFUL
```

## 6. Iterations-Pass (Selbstkritik nach dem ersten Wurf)

1. `light_gulp`: Rampe von getönt auf weißen Alpha-Umschlag umgestellt — die
   ursprüngliche dunkle `colorOverLifetime` hätte sich mit dem dunklen `startColor`
   multipliziert und die Subtraktion gegen null quadriert (glitch_pop-Law).
2. `conducting_drizzle`: Anker von +0.45 auf +0.6 lokal gehoben — der Staub wird jetzt
   knapp ÜBER dem Hut geboren und sinkt durch die Brustlinie statt in ihr zu spawnen.
3. `violet_glints`: `distanceRate` 0.15→0.5, `maxParticles` 6→8, Größen +~30% — der
   Nacht-Read war im ersten Wurf zu selten, um bei Licht 0 als umbral zu lesen.
4. Toter `cone().copy() if False`-Zweig und der überkomplexe `parents[4]`-Pfadreport
   im Generator entfernt.

## 7. Dateien (Ownership-Liste = exakt der Commit)

```
tools/photon/fxcoupling_fx.py                                              (neu)
src/main/resources/assets/eclipse/fx/wizard_star_call.fx[.fxproj]          (neu, generiert)
src/main/resources/assets/eclipse/fx/wizard_star_call_fast.fx[.fxproj]     (neu, generiert)
src/main/resources/assets/eclipse/fx/lantern_flicker_dip.fx[.fxproj]       (neu, generiert)
src/main/resources/assets/eclipse/fx/lantern_flicker_surge.fx[.fxproj]     (neu, generiert)
src/main/resources/assets/eclipse/fx/stalker_sprint_smear.fx[.fxproj]      (neu, generiert)
src/main/java/dev/projecteclipse/eclipse/network/fx/FxCues.java            (additiv: 1 Cue)
src/main/java/dev/projecteclipse/eclipse/veilfx/WizardFxRows.java          (neu)
src/main/java/dev/projecteclipse/eclipse/veilfx/PhotonMobFx.java           (additiv: 1 LoopRow)
src/main/java/dev/projecteclipse/eclipse/entity/wizard/WizardOrinEntity.java
src/main/java/dev/projecteclipse/eclipse/entity/ambient/DriftLanternEntity.java
src/main/java/dev/projecteclipse/eclipse/client/entity/ambient/DriftLanternFx.java (neu)
src/main/java/dev/projecteclipse/eclipse/entity/UmbralStalkerEntity.java
src/main/resources/assets/eclipse/animations/entity/drift_lantern.animation.json
docs/plans_v3/session_0730/POLISH1_FXCOUPLING_REPORT.md                    (dieser Report)
```
