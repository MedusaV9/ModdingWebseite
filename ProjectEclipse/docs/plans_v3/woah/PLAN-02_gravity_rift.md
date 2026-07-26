# PLAN-02 — GRAVITATIONSBRUCH ("Gravity Rift")

Feature 2 der WOAH-Reihe: eine begehbare Schwerkraft-Anomalie als permanentes Map-Feature —
das Gegenstück zum volumetrischen Sturm, aber mit völlig anderem Woah-Vektor: nicht Bedrohung,
sondern **Staunen + Vertikalität + Physik-Bruch**.

Alle Klassen-/Dateipfade in diesem Plan sind gegen den Stand des Repos verifiziert
(Branch `cursor/project-eclipse`). Wo API-Fakten zitiert werden, steht die Quelle dabei.
KEIN Java-Code hier — nur Spezifikation + Pseudo-Code.

---

## 1. Konzept-Zusammenfassung

Im äußeren Moonlit-Grove-Ring des Wald-Sektors klafft ein terrassierter Krater
(r ≈ 28, ~13 Blöcke tief). Über ihm schwebt ein dreistöckiges Trümmer-Orbital:
**~220 BlockDisplays** in drei Schalen kreisen langsam um ein pulsierendes
**Gravitations-Herz** am Kraterboden — kleiner Kies schnell und tief, mittlere Erdschollen
träger darüber, und ganz oben riesige Schollen-Komposite mit Gras-Deckplatten und
Baum-Fragmenten, die fast stillzustehen scheinen. Dazwischen steigt Photon-Staub AUFWÄRTS
statt zu fallen. Zusätzlich hängen **statische, echte Blockinseln** im Raum (Parkour-Stufen
+ zwei bewachsene Ambient-Großschollen + die Loot-Scholle ganz oben) — sie sind das, was
man aus jeder Entfernung sieht, und sie sind das, worauf man tatsächlich steht.

Wer die Zone betritt, bekommt **Low-Gravity**: ~3-fache Sprunghöhe, langer schwebender
Fall, kein Fallschaden innerhalb der Zone. Alle 45 Sekunden stößt das Herz einen
**Gravitationspuls** aus: eine sichtbare Photon-Ringwelle + Screen-Shake, alle Schollen
heben und senken sich synchron, Spieler in der Zone werden sanft nach oben geworfen —
das Timing-Werkzeug für die zwei "Hero Gaps" der Parkour-Route nach oben zur Loot-Scholle.
Schlägt man das Herz, **invertiert** die Anomalie für 10 Sekunden: das gesamte Orbital
stürzt chaotisch taumelnd Richtung Kraterboden, die Zone drückt kurz nach oben statt zu
tragen, dann gleitet alles wieder in seine Bahnen zurück.

Am Boden sitzt das Herz selbst: ein pulsierender Amethyst-Kern (Display-Komposit,
Brightness-Override 15/15) in einer Photon-Aura — und im Nahbereich verbiegt ein
**Veil-Lensing-Post-Pass** den Bildschirm subtil zum Herzen hin (Screen-UV-Distortion +
chromatische Aberration am Rand, eine bewusst schwächere, weltfeste Variante der
`black_hole.fsh`-Ideen — siehe §4.1, warum wir den Shader NICHT direkt wiederverwenden).

### Blickfang aus 200 Blöcken

Wichtiger technischer Fakt zuerst: `BLOCK_DISPLAY`-Entities werden nur innerhalb des
Entity-Tracking-Horizonts von **10 Chunks (160 Blöcke)** überhaupt an Clients gesendet —
egal welcher `view_range` gesetzt ist (dokumentiert + gelöst in
`worldgen/stage/ExpansionBorderFx.java`, Klassen-Javadoc "Why the v1 boulders were never
seen"). Das Fern-Bild darf sich also NICHT auf die Orbital-Displays verlassen. Deshalb ist
der Fern-Blickfang aus echten Blöcken + Photon (Photon-Partikel sind KEINE Entities und
unterliegen dem Tracking nicht — Präzedenz: `CUE_SUMMON_BEACON` ist "readable disc-wide",
`network/fx/FxCues.java`):

- **Silhouette**: zwei große statische Schwebe-Inseln (echte Blöcke, mit je einem Baum)
  über einem dunklen Kraterschlund + die gestaffelten Parkour-Stufeninseln — sichtbar bis
  Renderdistanz, auch bei 300+ Blöcken.
- **Puls-Leuchtsäule**: `gravity_pulse_ring.fx` enthält neben dem Boden-Ring eine dünne,
  4 s stehende HDR-Lichtsäule (distanz-skalierte Breite, das `boss_summon_beacon`-Rezept).
  Cue-Range 256 → aus 200 Blöcken sieht man alle 45 s einen violetten Lichtstoß über dem
  Wald aufsteigen. Das ist der "Was ist DAS da drüben?"-Köder.
- Ab **≤ 160 Blöcken** blenden die 220 Orbital-Displays ein (Tracking-Horizont), ab
  **≤ 120** die Photon-Staub/Funken-Loops, ab **≤ 140** der Lensing-Post — die Anomalie
  "erwacht" beim Näherkommen in drei Stufen. Das ist dieselbe LOD-Erzählung wie die
  Sturm-Handover-Kette (`stormfx/StormVolumeFx.VOLUME_RANGE` / `StormNearfieldFx`).

---

## 2. Platzierung + Krater-Terraforming

### 2.1 Standort auf der Disc

Verifizierte Ist-Lage (aus `worldgen/DiscMapDefaults.overworldDefaults()` und
`worldgen/FrozenParams.DEFAULT_OVERWORLD_RADII = {96, 150, 210, 280, 360, 440}`):

| Landmark | (x, z) | r | Sektor |
|---|---|---|---|
| desert_temple | (165, 99) | ≈192 | Wüste |
| jungle_temple | (−173, 173) | ≈245 | Dschungel |
| village_plains | (254, −22) | ≈255 | Plains |
| pillager_outpost | (−192, −34) | ≈195 | Savanne |
| trial_chambers | (143, 205) | ≈250 | unter Badlands |
| ancient_city / Berg | (54, −129) | Berg r=75+Flanke | Snowy |
| mansion | (219, −219) | ≈310 | Dark Forest |
| nether_breach | (85, 85) | ≈120 | Wüste |
| fog_storm_1 | (−173, −173) | ≈245 | Sumpf |
| fog_storm_2 | (0, −250) | ≈250 | Snowy |
| stronghold_emergence | (0, −400) | 400 | Snowy-Außenring |

Der **Wald-Sektor (67.5°–112.5°, Richtung +Z) hat als einziger Sektor KEIN Landmark**.
Dort platzieren wir:

**Anker: `eclipse:gravity_rift` bei (x = −40, z = 290), Stage 4, Radius (Protection) 40.**

Begründung (alle Regeln aus dem `overworldDefaults()`-Javadoc "Landmark placement rules"):

- r ≈ 292.7 → liegt im **`eclipse:moonlit_grove`**-Ring (Wald-Ringtabelle: birch ≤ 280,
  danach moonlit_grove; ±6-Block-Wobble aus `DiscMapDefaults.RING_WOBBLE_BLOCKS` lässt
  min. r ≈ 286.7 > 280). Mondlicht-Hain + Gravitations-Anomalie = thematischer Volltreffer.
- Stage-Regel: Site + Radius im Stage-Disc → 292.7 + 40 = 332.7 < 360 (Stage 4) ✓;
  nicht im Stage-3-Disc (292.7 > 280) → **Stage 4** ist die früheste gültige Stage.
- **Kritisch für Bestandswelten ohne Landmark-Schutz**: Der Stage-4→5-Growth-Sweep
  rewritet nur Chunks mit Spalten `r ≥ min(360,440) − RIM_REWRITE_MARGIN` und
  `RIM_REWRITE_MARGIN = RIM_WIDTH(12) + RIM_NOISE_AMP(8) + 4 = 24`
  (`worldgen/DiscTerrainFunction.java` Z.67–75; Band-Regel im
  `RingGrowthService`-Javadoc). Band-Innenkante = 336. Unsere maximale Ausdehnung
  332.7 < 336 → **kein späterer Sweep fasst den Krater je an**, selbst wenn die
  Landmark-Protection fehlt (Bestandssave, s.u.).
- Abstände: jungle_temple ≈ 177, village ≈ 430, r=170-Spielerdisc-Ring ≥ ~98 (Discs r=24),
  Fluss 3 (Polyline (38,115)→(62,215)→(65,320)→(100,495)) ≈ 103 Blöcke zur Mittellinie
  (Regel: > 18 + Site-Radius = 58) ✓, Sektor-Seams 67.5°/112.5° ≥ 14.6° ≈ 74 Bogen-Blöcke
  (±5°-Wobble ≈ ±25 Blöcke + 40 Radius = 65 < 74) ✓.

### 2.2 Rollout: neue UND bestehende Saves

`disc_map.json` wird pro Save eingefroren (`FrozenParams` snapshottet
`DiscMapDefaults`) — ein neuer Landmark-Eintrag erreicht nur NEUE Welten. Deshalb
zweigleisig, exakt das **`WizardObservatory`-Muster**
(`worldgen/structure/WizardObservatory.java`, Javadoc "Placement"):

1. **Neue Saves**: eine Zeile in `DiscMapDefaults.overworldDefaults()` —
   `new DiscMapData.Landmark("eclipse:gravity_rift", -40, 290, 40, 4)`. Damit greift die
   Growth-Sweep-Spalten-Protection (`RingGrowthService.buildProtectedZones()` liest die
   Landmark-Tabelle; `protectionExtent` fällt auf den authored radius 40 zurück) auch für
   `/eclipse stage rebuild`.
2. **Alle Saves (Platzierung)**: `GravityRiftService` registriert einen
   `WorldStageService.StageListener` (Registrierung in `ServerAboutToStartEvent`, das
   `AltarSanctumBuilder`-Muster) und enqueued beim Überschreiten von **Stage 4** die Site
   `eclipse:gravity_rift` in die **`StructurePendingRegistry`** (zweiphasig → Rift-Tear-
   Reveal, SavedData-Resume, Dedup und Erase-Cleanup gratis). Dazu ein LOW-priority
   `ServerStartedEvent`-Catch-up für Welten, die Stage 4 schon vor dem Merge überschritten
   haben (wortwörtlich der `WizardObservatory`-Kommentar).
3. Der Placer wird via `StructurePendingRegistry.registerPlacer("eclipse:gravity_rift", …)`
   registriert (Vorbild: `UndergroundSites.registerPlacers()` — selbst-carvende Builder).

### 2.3 Krater-Terraforming (Laufzeit, deterministisch)

**Kein** Eingriff in `DiscTerrainFunction` (das wäre nur für Chunkgen/Sweep-Bytegleichheit
nötig — der Krater liegt aber nachweislich außerhalb jedes zukünftigen Sweep-Bands, §2.1).
Stattdessen Laufzeit-Terraform im Placer, Komposition nach dem **`SanctumCrater`**-Rezept
(`worldgen/structure/SanctumCrater.java`: parabolisches Tiefenprofil + Hash-Roughness +
terrassierte Strata, alles deterministisch über `FallbackBuilders.hash01`, ZERO
`RandomSource`):

Neue Klasse **`worldgen/structure/GravityRiftBuilder.java`**:

- `carveCrater(level, anchor)`: Bowl r=28, Tiefe 13 (parabolisch + Hash-Bite ±2),
  3 Terrassen; Strata von außen nach innen: moos-durchsetzter Stein → Tuff/Deepslate →
  Kraterboden aus `polished_deepslate`/`sculk`-Flecken/`amethyst_block`-Adern (die
  "aufgerissene Welt"). Rim: geborstener Schutt-Ring r 28..31 mit **freigehaltenem
  Zugangs-Sektor Richtung Sektor-Innenseite** (Süd-Walk-Regel von `SanctumCrater`,
  `WALK_SECTOR_HALF_WIDTH`-Analogon), damit man hineinlaufen kann.
- Boden-Y: `DiscTerrainFunction.surfaceY` am Anker (das vegetation-blinde deterministische
  Ground-Y — dieselbe Quelle, die `SitePrep.preparePlateau` benutzt); vorher ein
  Vegetations-Clear über dem Footprint wie `SitePrep` Mode PLATEAU (Canopy-Sweep).
- Schreiben ausschließlich über **`worldgen/stage/BudgetedBlockWriter`**; Abschluss:
  Heightmap-Re-Prime + `BudgetedBlockWriter.relightAndResend` (der `SitePrep.finish`-
  Kontrakt — großer Carve darf keinen Tick spiken).
- `placeStaticIslands(level, anchor)`: die **echten** Blockinseln (§5.3) — Parkour-Stufen,
  zwei Ambient-Großschollen (7×5×7 Gras/Erde/Stein + Fichten-/Dark-Oak-Mini-Baum), die
  Loot-Scholle (+46) mit Chest (`setLootTable` auf
  `eclipse:chests/gravity_rift_loft`, Vorbild: `SupplyBeacon`/Dungeon-Builder) und den
  Herz-Sockel (3×3 `polished_deepslate` + Mitte `amethyst_block`).
- `isBuiltSentinel(level, anchor)`: prüft einen vergrabenen Sentinel-Block (z. B.
  `crying_obsidian` unter dem Sockel) → macht den Build **idempotent + selbstheilend**:
  `GravityRiftService` re-carvt beim Serverstart, wenn der Sentinel fehlt (Schutz für
  Bestandswelten gegen exotische Rebuild-Pfade, Risiko R2).

---

## 3. Server-Systeme

Neues Package **`dev.projecteclipse.eclipse.gravityrift`** (Repo-Konvention: ein
Feature-Package wie `stormfx`, `glitchzone`), plus der Builder in
`worldgen/structure` (§2.3).

### 3.1 `GravityRiftState.java` — SavedData

Eigene SavedData-Klasse nach dem `EclipseWorldState`-Muster
(`core/state/EclipseWorldState.java`; Datei `data/eclipse_gravity_rift.dat`, overworld
storage):

- `built` (bool) + `builtVersion` (int, für spätere Re-Carves),
- `anchor` (BlockPos, der aufgelöste Kraterboden-Mittelpunkt),
- `invertUntilGameTime` (long, 0 = keine Inversion aktiv),
- `lastInvertGameTime` (long, Cooldown),
- `lootChestPlaced` (bool).

Der Puls braucht KEINEN persistierten Timer: Puls-Beats liegen auf dem absoluten Raster
`gameTime % PULSE_PERIOD_TICKS == riftPhaseOffset` (Offset = Hash des Ankers) — dadurch
sind Server-Beat, Display-Pose-Funktion und Client-FX von Natur aus synchron und
restart-sicher (das Stateless-Push-Gesetz von `SanctumOrbitals`, s.u.).

### 3.2 `GravityRiftService.java` — Tick-Owner

`@EventBusSubscriber`, `ServerTickEvent.Post`. Verantwortungen:

1. **Platzierung/Heilung**: Stage-Listener + Catch-up (§2.2); Sentinel-Check beim Start.
2. **Zonen-Erkennung** (alle 10 t): Zylinder um `anchor`
   (r = 34, von floorY−2 bis floorY+56). Spieler-Eintritt/Austritt wird in einem
   `Set<UUID>` gehalten (In-Memory, das `SkyLauncher`-Flight-Map-Muster).
3. **Low-Gravity-Attribute** (§3.4).
4. **Puls-Beat**: bei `gameTime % 900 == offset` →
   `FxPayloads.sendFxEvent(level, FxCues.CUE_GRAVITY_PULSE, heartPos, radiusScale, 0, 256)`
   + `S2CShakePayload.shake(0.28F, 16)` an Spieler ≤ 48 (PacketDistributor.sendToPlayersNear,
   das `ExpansionBorderFx.raiseFx`-Rezept) + Sounds (§6) + **Puls-Launch** (§7.3)
   + vanilla Partikel-Floor (eine Handvoll `END_ROD`/`CLOUD` als photon-loser Baseline —
   INTEGRATION-Gesetz: nie unter die Quasar/Vanilla-Basislinie fallen).
5. **Herz-Hit / Inversion** (§7.4): `AttackEntityEvent`-Hook auf das Interaction-Entity
   (Tag `eclipse_gravrift_heart`), setzt `invertUntilGameTime = now + 200`, synct Payload,
   Cooldown 2400 t.
6. **Item-/XP-Drift**: alle 5 t bekommen `ItemEntity`/`ExperienceOrb` in der Zone
   `setDeltaMovement(dx, min(dy + 0.03, 0.12), dz)` — loses Zeug steigt träge auf.
7. **Sync**: `S2CGravityRiftPayload` (§3.5) bei Login/Dimensionswechsel/Respawn (der
   `StormRegistry`-Re-Sync-Kontrakt) und bei jeder Zustandsänderung (Inversion an/aus).
8. **Chunk-Residenz**: eigener `TicketType` `eclipse_gravity_rift`
   (Lifespan 600 t, Refresh alle 400 t — exakt die `ExpansionBorderFx.BOULDER_TICKET`-
   Konstanten) auf den Mount-Chunk + Radius 1, NUR solange ein Spieler ≤ 224 Blöcke ist.
   Niemand da → Tickets laufen aus, Chunk + persistente Displays entladen zusammen.

### 3.3 `GravityRiftOrbitals.java` — Orbit-Choreograf

Der Kern. Alle Gesetze sind im Repo erprobt und werden 1:1 übernommen:

- **Fixed-Mount-Gesetz** (`sequence/StormDebrisFx.java` Javadoc "Transport" +
  `SanctumOrbitals` "Why the entities never move"): JEDES Display sitzt an EINEM fixen
  Entity-Punkt — Krater-Mitte, floorY+30 (offene Luft → korrektes Licht-Sampling, EIN
  Chunk besitzt alle Displays). Die gesamte Bewegung lebt in der Transformation-Translation.
- **Stateless-Push-Gesetz** (`SanctumOrbitals` Javadoc "Animation transport"): Pose =
  absolute Funktion von `gameTime`. Push-Kadenz == Interpolationsdauer, ein Fenster
  **Keyframe-LEAD** (Pose für `gameTime + cadence` senden — der `ExpansionBorderFx.animate`-
  Kommentar "SanctumOrbitals law").
- **90°-Fenster-Gesetz** (VFXPOLISH-3, `SanctumOrbitals.BOB_BASE_PERIOD_TICKS`-Kommentar):
  kein Sinus-/Winkelterm darf pro Interpolationsfenster mehr als ~90° Phase überstreichen.
  Bei Kadenz 20 t heißt das ω ≤ 4.5°/t — unsere schnellste Schicht liegt bei ~2.4°/t. ✓
- **Persistenz + Reconcile** (`SanctumOrbitals` "Persistence + self-healing"): Displays
  sind persistent, tragen `eclipse_gravrift_orbital` + Identitäts-Tag
  `eclipse_gravrift_orbital_<layer>_<index>`; Reconcile-Sweep (Boot, alle 600 t bei
  Spielernähe, on-missing) adoptiert per Tag, discardet Duplikate, respawnt Fehlendes —
  inkl. `ServerLevel.areEntitiesLoaded`-Warte beim ersten Boot-Reconcile (Deckhand-
  Load-Race-Lektion). `/kill @e[tag=eclipse_gravrift_orbital]` heilt sich selbst.
- **Spawn-Detail**: `DisplayBrightnessFx.set(display, 6, 15, viewRange)` — Licht-Override
  + `view_range` in EINEM NBT-Roundtrip (`worldgen/stage/DisplayBrightnessFx.java`,
  3-Argument-Overload); Interpolations-Setter via der bereits vorhandenen
  accesstransformer-Öffnung (OarAnimator-Präzedenz).

**Pose-Funktion (Pseudo-Code, pro Piece deterministisch aus Layer+Index gehasht):**

```
pose(piece, t):                        # t = gameTime + CADENCE (Keyframe-Lead)
  ang = piece.phase0 + piece.omega * t              # omega aus Tangential-
                                                    # geschwindigkeit / baseR abgeleitet
                                                    # (StormDebrisFx-Regel: außen wirbelt
                                                    # nicht schneller als innen)
  r   = piece.baseR + piece.wobAmp * sin(TAU * t / piece.wobPeriod + piece.wobPhase)
  y   = piece.baseY + piece.bobAmp * sin(TAU * t / piece.bobPeriod + piece.bobPhase)
        + pulseLift(t) * piece.layerLift            # §Puls
        + invertDrop(piece, t)                      # §Inversion
  spin = Quaternion(piece.axis, piece.spinRate * t) # Eigenrotation, Achse präzediert
                                                    # langsam um Y (FloatingDecor-Craft)
  translation = (cos(ang)*r, y, sin(ang)*r) - mountOffset - rotatedHalfExtents
  return Transformation(translation, spin, piece.sizePerAxis, identity)

pulseLift(t):                          # STATELESS: Puls-Raster = t mod 900
  u = (t - phaseOffset) mod 900
  env = smoothstep(0,15,u) * (1 - smoothstep(25,60,u))   # 3 s Atmen
  return 2.5 * env                     # layerLift: Kies 0.6 / Schollen 1.0 / Inseln 1.4

invertDrop(piece, t):                  # NICHT stateless — verankert an invertStart
  if t < invertStart or t > invertStart + 300: return 0
  u = t - invertStart
  fall  = -(piece.baseY - bowlFloorClearance(piece)) * easeIn(clamp(u/80))   # Sturz 4 s
  hold  = ...  chaotisches Zittern (hash-Sinus, Amplitude 0.6) für u in [80,200]
  back  = Rückkehr per smoothstep über u in [200,300]                        # Gleiten 5 s
  # Tumble-Spike: spinRate * 4 während u < 200 (Impuls-Abkling wie
  # CreditsShatterAct "1-(1-q)^3"-Integral)
```

Kadenz/Slicing: Basis-Kadenz **20 t** (Spieler ≤ 128), **40 t** (≤ 224), **Pause**
(Pose halten, null Pakete) darüber — das `SanctumOrbitals.PLAYER_GATE_RANGE`-Early-out.
Pushes werden über das Fenster **phasen-gesliced** (`StormDebrisFx` "Budget"):
220 Displays / 20 t ≈ 11 Entity-Data-Pakete pro Tick worst case. Während der ±40 t um
einen Puls und während der Inversion verdichtet die Kadenz auf 10 t (Bewegung wird
schneller → Fenster-Gesetz einhalten).

### 3.4 Low-Gravity-Zone — Attribute (1.21.1 verifiziert)

Per `javap` gegen das gemappte 1.21.1-Jar verifiziert
(`net.minecraft.world.entity.ai.attributes.Attributes`): es existieren
**`GRAVITY`** (Registry-Id `minecraft:generic.gravity`, Basis 0.08), **`JUMP_STRENGTH`**,
**`SAFE_FALL_DISTANCE`**, **`FALL_DAMAGE_MULTIPLIER`**. Kein anderes Mod-System im Repo
belegt sie bisher (rg-Census: 0 Treffer) — keine Modifier-Kollisionen.

Beim Zonen-Eintritt (Server, transient — transiente Modifier werden NIE gespeichert,
Crash-Leak unmöglich):

| Attribut | Operation | Wert | Effekt |
|---|---|---|---|
| `GRAVITY` | ADD_MULTIPLIED_TOTAL | −0.65 | 0.08 → 0.028 (Sprunghöhe ~3.1, Schwebe-Fall) |
| `JUMP_STRENGTH` | ADD_MULTIPLIED_TOTAL | +0.15 | Sprunghöhe → ~4.2 Blöcke |
| `FALL_DAMAGE_MULTIPLIER` | ADD_MULTIPLIED_TOTAL | −1.0 | kein Fallschaden IN der Zone |
| `SAFE_FALL_DISTANCE` | ADD_VALUE | +20 | Gürtel + Hosenträger |

Modifier-Id fix: `eclipse:gravity_rift_low_g` → `addOrUpdateTransientModifier` bei
Eintritt, `removeModifier` bei Austritt/Logout/Dimensionswechsel/Serverstopp
(Sweep im Service-Tick, nicht event-only). Das eigene GRAVITY-Attribut wird vanilla an
den eigenen Client repliziert → die client-authoritative Bewegung stimmt sofort.
Auch Nicht-Spieler-LivingEntities in der Zone bekommen den GRAVITY-Modifier (Mobs
hüpfen in Zeitlupe — verkauft die Anomalie).

**Austritt in der Luft**: 8 s Slow Falling (MobEffect) beim Verlassen der Zone ohne
Bodenkontakt — verhindert Todes-Cheese an der Zonenkante, benutzt bewusst NICHT
`TimedBuffApi` (server-global, config-definiert — dieselbe Abgrenzung, die
`SkyLauncher.grantFallGrace` in seinem Javadoc dokumentiert).

### 3.5 `network/fx/S2CGravityRiftPayload.java`

Neuer S2C-Payload, registriert in `network/fx/FxPayloads.register` (dort registrieren
bereits `S2CStormStatePayload` & Co.). Felder:
`anchor (BlockPos)`, `floorY`, `zoneRadius`, `active (bool)`,
`pulsePeriodTicks`, `pulsePhaseOffset`, `invertUntilGameTime (long)`.
Client-Handler schreibt in `client/gravityrift/GravityRiftClientState` (§4.4).
Cues (`FxCues`): **`CUE_GRAVITY_PULSE`** (`a` = Ring-Radius-Skala) und
**`CUE_GRAVITY_INVERT`** — Position-Lane, Rows in §4.3.

---

## 4. Client-Systeme

### 4.1 Veil-Lensing-Post `eclipse:gravity_lens`

**Wiederverwendbarkeits-Prüfung `black_hole.fsh`** (gelesen:
`pinwheel/shaders/program/black_hole.fsh` + `client/credits/CreditsBlackHolePostFx.java`):
Der Pass kann technisch alles, was wir brauchen ([b1] radialer UV-Pull, [b2b] CA-Band),
aber er trägt Finale-DNA, die für ein Dauer-Weltfeature falsch ist: Event-Horizon-
Blackout, 85 % Desaturierung + 55 % Abdunklung, Akkretions-Discs, Star-Streaks — alles an
`Strength` gekoppelt, nicht einzeln abschaltbar. Seine Aktivierung hängt außerdem an
`CreditsSkyFx.holeAmount`. **Entscheidung: NICHT wiederverwenden, sondern einen schlanken
Schwester-Shader schreiben**, der nur Pull + Swirl-Hauch + CA übernimmt (Copy der
bewährten Formeln, gleiche `eclipse:eclipse_common`-Includes `efxChroma`/`efxNoise`/
`efxHash`).

Neue Dateien:
- `assets/eclipse/pinwheel/post/gravity_lens.json` (Pipeline),
- `assets/eclipse/pinwheel/shaders/program/gravity_lens.fsh` + `.json` (Programm).

Registrierung: neue Client-Klasse **`veilfx/GravityRiftLensFx.java`**
(`@EventBusSubscriber(Dist.CLIENT)`, static-init-Seam wie `StormVolumeFx`/
`CreditsBlackHolePostFx`): `VeilPostController.register(PipelineSpec(GRAVITY_LENS_POST,
PipelinePriority.FEATURE, predicate, feeder))`. Damit gratis: Iris-Gate, ≤ 3 konkurrente
Passes mit Eviction, Failure-Fuse (alles `veilfx/VeilPostController.java`).

**Uniform-Spez** (Feeder allocation-frei, JOML-Scratch — Controller-Regel):

| Uniform | Quelle | Semantik |
|---|---|---|
| `Heart` (vec2) | `SunTracker.worldToNdc(heartPos)`, Last-Good-Fallback | Herz in UV (das `CreditsBlackHolePostFx`-Projektions-Rezept inkl. "behind camera hält letzten Punkt") |
| `Aspect` (float) | Viewport | Kreisform |
| `Time` (float) | pausen-gefrorene Tick-Uhr, Wrap 72 000 t | Shimmer |
| `Strength` (float) | Distanz-Rampe: 1 bei ≤ 40 Blöcken zum Herz, → 0 bei 140; × Höhen-Falloff; × Invert-Boost 1.5 | Master |
| `PulseAmount` (float) | Envelope 0→1→0 über 30 t nach jedem Puls-Beat (Raster aus Payload) | Screen-Space-Refraktionswelle |
| `Detail` (float) | 0 unter `reducedFx` | schaltet CA + Shimmer ab |

**Falloff-Spec im Shader**: max. UV-Verschiebung **0.012** (subtil! kein Finale),
`pull = smoothstep(0.65, 0.05, dist) * 0.012 * Strength`; Mini-Swirl ≤ 0.15 rad;
CA-Band um die Herz-Richtung `caAmt ≈ 0.0025 * Strength * Detail` (die [b2b]-Formel,
halbe Stärke); `PulseAmount` addiert eine auslaufende Ring-Refraktion
(`sin(dist*40 - PulseAmount*12)`-Fenster). KEIN Horizon, KEINE Desaturierung.

### 4.2 Photon-FX-Liste (Assets via neues `tools/photon/gravity_fx.py`, fxlib-Pipeline
inkl. `.fxproj`-Siblings — Konvention aus `docs/plans_v3/PHOTON_EDITOR_CAPABILITIES.md` §1)

| Asset (`assets/eclipse/fx/…`) | Typ | Emitter-Spec |
|---|---|---|
| `gravity_dust_rise.fx` | Loop (WINDOWED) | 2 Emitter: `dust_motes` — Box-Shape über der Bowl (32×10×32), Rate 0.12/t, Lifetime 80–140 t, Start-Velocity +Y 0.02, Gravity **negativ** (−0.01), Größe 0.05–0.12, staubgrau, leichtes Orbit-Force-Feld um die Achse; `dust_glints` — Rate 0.04/t, additive HDR-Punkte, violett-weiß |
| `gravity_orbit_sparks.fx` | Loop (WINDOWED) | 2 Ring-Emitter am Herz (Radius 6 und 10, Orbital-Velocity ~1.2 rad/s bzw. 0.7), additive Funken 0.08–0.15, HDR ×2, Lifetime 40–70 t, leichte Aufwärts-Spirale |
| `gravity_heart_aura.fx` | Loop (WINDOWED) | Shell-Emitter r=2.2 um das Herz: Fresnel-artige additive Hülle (Mesh/Shell-Material, PHOTON-ADVANCED-Rezept) + `indraw_wisps`: Partikel spawnen bei r 5–7 und driften mit negativer Radial-Velocity INS Herz (Rate 0.05/t) |
| `gravity_pulse_ring.fx` | One-Shot 50 t | 3 Sub-Emitter: Boden-Ring-Burst (Torus expandiert 4→34 Blöcke über 30 t, HDR violett), vertikale Lichtsäule (dünnes additives Band, 90 Blöcke hoch, 4 s stehend, distanz-skalierte Breite — das `boss_summon_beacon`-Rezept), Staub-Kick (Burst 60 Partikel, +Y) |
| `gravity_invert_burst.fx` | One-Shot 60 t | REVERSE_SUB-Dunkel-Riss am Herz + nach INNEN kollabierende Shell + 20 t später ADD-Re-Expand (das `riss_maw`/`tyrant_death_implosion`-Vokabular) |

### 4.3 Rows + Fenster-Controller

- **`veilfx/GravityRiftFxRows.java`** (neuer Client-Registrar, `FMLClientSetupEvent`,
  Copy-Muster `PhotonFxRows`):
  - Row `CUE_GRAVITY_PULSE` → `gravity_pulse_ring.fx`, Quasar-Leg `null` (Photon-only-
    Garnish ist für NEUE Cues legal — `PhotonFxRegistry.Row`-Javadoc; der photon-lose
    Floor sind die server-seitigen Vanilla-Ring-Partikel aus §3.2), Channel BURST,
    Mode LAYER, Custom-Leg skaliert Executor mit `a`.
  - Row `CUE_GRAVITY_INVERT` → `gravity_invert_burst.fx`, analog.
  - Die 3 Loop-Rows (`dust_rise`, `orbit_sparks`, `heart_aura`) mit `loop=true` —
    **WINDOWED-only-Gesetz**: nie payload-gefeuert.
- **`client/gravityrift/GravityRiftAmbience.java`** — der Fenster-Controller
  (Hysterese-Muster `StormNearfieldFx`/`SanctumLightfall`): attach ≤ 96, release ≥ 120,
  Retry-Kadenz 40 t bei refused Spawns, Release bei `reducedFx`/Dimensionswechsel/Logout;
  Emissions-Raten reiten `1 − smoothstep(60, 120, dist)` (Channel-A-Live-Tuner-Muster von
  `StormNearfieldFx`, Basis-Raten frozen im Generator-Skript). Steuert auch den
  **Hum-Loop** (§6) und liest `GravityRiftClientState`.

### 4.4 `client/gravityrift/GravityRiftClientState.java`

Cache des `S2CGravityRiftPayload` (Anker, Zone, Puls-Raster, Invert-Fenster) + abgeleitete
Werte pro Client-Tick: `heartDistance`, `lensStrength`, `pulseEnvelope`. Gelesen von
`GravityRiftLensFx` (Feeder) und `GravityRiftAmbience`. Reset bei
`ClientPlayerNetworkEvent.LoggingOut` (Repo-Standard in allen FX-Controllern).

### 4.5 Herz-Rendering

**Entscheidung: Display-Komposit + Photon-Aura + Lens-Post, KEIN Custom-Mesh-Renderer.**
Begründung: Der Woah-Effekt kommt aus Aura + Lensing + Puls; ein eigener Veil-World-Space-
Renderer wäre der teuerste Weg zum kleinsten Delta. Serverseitig (Teil von
`GravityRiftOrbitals`, gleiche Tags/Reconcile):
- Kern: 1 BlockDisplay `minecraft:budding_amethyst`, Scale-Puls 1.4↔1.8 (Atem-Periode
  90 t, absolute Zeitfunktion), Brightness-Override **15/15** (`DisplayBrightnessFx.set`).
- 2 Gegenläufig rotierende "Käfig"-Shells: BlockDisplays `minecraft:tinted_glass`,
  Scale 2.4/2.8, 45°-verkantete Achsen, ±0.4°/t.
- Hitbox: 1 `minecraft:interaction`-Entity (2.5×2.5) — via NBT gespawnt, weil vanilla
  keine public Width/Height-Setter hat (**exakt** `SkyLauncher.spawnPadInteraction`,
  Z. 924 ff.), Tag `eclipse_gravrift_heart`.

---

## 5. BlockDisplay-Layout + Begehbarkeit

### 5.1 Orbital-Schalen (Displays, NICHT begehbar)

Alle Radien relativ Krater-Mitte, alle Y relativ Kraterboden (floorY):

| Schale | Stück | Displays | Radius | Höhe | Größe/Achse | Tangential | Blöcke |
|---|---|---|---|---|---|---|---|
| 0 "Kies" | 110 | 110 | 6–14 | +3..+12 | 0.25–0.6 | 0.25 b/t (≈1.0–2.4°/t) | cobbled_deepslate, stone, tuff, andesite |
| 1 "Schollen" | 48 | 60 (12 als 2-Slab-Komposit) | 12–22 | +12..+28 | 0.8–1.8, Y flacher (×0.5) | 0.12 b/t | dirt, rooted_dirt, stone, moss_block, coarse_dirt |
| 2 "Inseln" | 10 | ~50 (4–6 Slabs je Komposit) | 10–20 | +28..+44 | bis (5.5, 2.5, 5.5) | 0.05 b/t (≈0.14–0.29°/t) | Deckslab `grass_block`, darunter dirt/stone-Slabs; 4 Stück mit `spruce_log`- + `spruce_leaves`-Displays als Baum-Fragment |

Summe ≈ **220 Displays** (Hard-Cap 260). Komposit-Bau nach dem
`ExpansionBorderFx.buildBoulder`-Rezept (per-Achse-Größen, genestete verkantete Slabs —
"never reads as a scaled cube"); Größenklassen-Dramaturgie nach `CreditsShatterAct`
(Boulder-Minderheit groß + träge, Shard-Tier klein + schnell drehend).
Drehung: Eigenrotation 0.1–1.2°/t, Achse präzediert (das `FloatingDecor.poseAt`-Craft).
`view_range`: Schale 2 → 8.0 (=512 Blöcke, voll bis zum Tracking-Limit), Schale 1 → 6.0,
Schale 0 → 3.0 (kleiner Kies muss aus 300 m nicht gezeichnet werden — spart Far-Draw).

### 5.2 Begehbarkeit — Entscheidung + Begründung

**BlockDisplays haben keine Kollision. Optionen geprüft:**
1. Barrier-Blöcke unter orbitierenden Displays — ❌ Barriers sind statisch, Displays
   bewegen sich → permanenter Sicht/Kollisions-Versatz, unsichtbare Wände neben
   sichtbaren Schollen. Schlechtestmögliche UX.
2. `minecraft:interaction` — ❌ hat KEINE Kollision, nur Hit-/Use-Box. Ungeeignet.
3. Shulker-Reittier-Trick (unsichtbarer Shulker = solide) — ❌ Living-Entity-Kosten, AI,
   Anfälligkeit (Tod/Push), 10+ Stück permanent = neue Fehlerklasse. Repo hat dafür
   keinerlei Präzedenz.
4. **Hybrid (GEWÄHLT)**: alles, was sich BEWEGT, ist reine Display-Kulisse; alles, was
   man BETRITT, sind **statische echte Blockinseln** (§5.3). Displays orbitieren bewusst
   NICHT durch die Stufen-Korridore (Orbital-Radien 6–22 vs. Stufen bei r 16–26 auf
   versetzten Höhenbändern + 2 Blöcke Freihalte-Toleranz in der Bahnplanung). Kollision
   ist damit vanilla-solide, restart-sicher, anticheat-neutral — und der Puls-Launch
   (§7.3) liefert das "die Anomalie trägt mich"-Gefühl, ohne dass Plattformen sich
   bewegen müssen.

### 5.3 Statische Inseln (echte Blöcke, vom Builder gestampft)

- **8 Parkour-Stufen**: 3×1×3 bis 2×1×2 (`grass_block`-Deck, `dirt`/`stone` darunter,
  Moos-Akzente), Spiralaufstieg gegen den Uhrzeigersinn:
  Höhen +6, +11, +17, +23, +30, +36, +41, +44; horizontale Lücken 5–7 Blöcke
  (Low-G-Sprung: Airtime ≈ 34 t, Sprint-Reichweite ≈ 9 Blöcke → machbar, fühlt sich
  episch an), **zwei Hero-Gaps mit 10–11 Blöcken** (+23→+30, +36→+41), die nur mit
  Puls-Timing gehen.
- **Loot-Scholle**: 5×2×5 bei +46, r ≈ 8 von der Achse; Chest mit LootTable
  `eclipse:chests/gravity_rift_loft` (§7.2), 1 `amethyst_cluster`-Deko, 1 Lantern.
- **2 Ambient-Großschollen**: 7×5×7 bei +20/r 30 und +34/r 26 (außerhalb der
  Orbital-Bänder), mit echtem Mini-Baum — der Fern-Blickfang (§1).

---

## 6. Sounds

`assets/eclipse/sounds.json` + `registry/EclipseSounds.java` geprüft — **alles Nötige
existiert bereits, null neue Audio-Assets**:

| Moment | Sound (existiert) | Einsatz |
|---|---|---|
| Hum-Loop nahe Herz | `eclipse:ambient.sanctum_hum` (`EclipseSounds.AMBIENT_SANCTUM_HUM`) | client-seitig als positionaler Loop aus `GravityRiftAmbience` (Fenster ≤ 40 Blöcke, Volumen ∝ 1/dist), Pitch 0.7 → klingt fremder als am Altar |
| Tiefen-Drone der Zone | `eclipse:ambient.storm_dome_drone` | leiser zweiter Layer ≤ 24 Blöcke, Pitch 0.85 |
| Puls-Boom | `eclipse:event.storm_pulse` + `eclipse:event.rift_thud` (Doppel-Layer, Thud 2 t versetzt) | Server `level.playSound` am Herz, Vol 2.2/1.6 |
| Puls-Fernrollen | `eclipse:event.lightning_far`, Pitch 0.6 | an Spieler 64–192 Blöcke (der Fern-Köder hörbar gemacht) |
| Inversion Start | `eclipse:event.rift_drone` + `eclipse:event.storm_shatter` | am Herz |
| Re-Stabilisierung | `eclipse:event.rift_resolve` | am Herz |
| Herz-Treffer | `eclipse:event.border_glitch`, Pitch 1.4 | Feedback des Hits |

Optional (nice-to-have, NICHT Pflicht): eigener Eintrag `event.gravity_pulse` mit
Custom-OGG später — die Tabelle oben trägt das Feature vollständig.

---

## 7. Gameplay

### 7.1 Parkour-Route
Einstieg über den freigehaltenen Rim-Sektor → Kraterboden (Herz aus der Nähe ansehen,
Lensing-Maximum) → Spiralaufstieg über die 8 Stufen (§5.3). Low-G macht 5–7-Block-Gaps
zu schwebenden Genuss-Sprüngen; die zwei Hero-Gaps verlangen Puls-Timing (alle 45 s,
Ring + Sound + Screen-Shake telegraphieren den Beat 1.5 s vorher via
`gravity_pulse_ring`-Anlauf-Delay im Asset). Fehlsprung = folgenloser Schwebe-Fall in
den Krater (kein Fallschaden in der Zone) → sofort neuer Versuch. Frust-frei by design.

### 7.2 Loot oben (`data/eclipse/loot_table/chests/gravity_rift_loft.json`)
Vanilla-only, thematisch "Wind/Schwerelosigkeit/Echo":
- garantiert: 3–5 `wind_charge` (Breeze-Item, 1.21.1 ✓), 1 `amethyst_shard` mit
  `set_name` "Herzsplitter" (via Loot-Function, kursiv-frei),
- Pool 2 (2 Rolls): `enchanted_book` (feather_falling IV/V, 30 %), 4–8 `echo_shard`
  ODER 8–16 `phantom_membrane`, 1 `golden_apple` (20 %),
- Pool 3: 16–32 `glowstone_dust` / 4–8 `slime_ball`.
Einmalige Chest (kein Refill in v1 — der wiederholbare Reward IST das Puls-Reiten und
die Aussicht).

### 7.3 Puls-Launch
Beim Beat: alle Spieler in der Zone mit `onGround` oder < 6 Blöcke über Grund/Insel
erhalten `setDeltaMovement(dx, +0.9, dz)` (weit unter dem ±3.9-Motion-Packet-Clamp, den
das `SkyLauncher`-Javadoc "MOTION_PACKET_LIMIT" dokumentiert) + `resetFallDistance`.
Spieler in der Luft bekommen nur +0.35 (kein Raketen-Stacking).

### 7.4 Herz-Hit-Umkehrung (optional, aber eingeplant)
`AttackEntityEvent` auf das Interaction-Entity → wenn `now > lastInvert + 2400`:
`invertUntilGameTime = now + 200` (10 s), Payload-Sync, `CUE_GRAVITY_INVERT`,
Orbitals stürzen chaotisch (Pose-Term §3.3), Zone: GRAVITY-Modifier wird für die 10 s
durch −1.05 ersetzt (g leicht negativ → alles schwebt aufwärts, Spieler treiben sanft
hoch; Deckel: Zylinder-Top prüft und dämpft `dy`), danach 5 s Rückgleiten +
`event.rift_resolve`. Während Inversion: Puls-Beats pausieren.

### 7.5 Schutz vor Missbrauch
- **Kein Low-G-Export**: Modifier werden beim Zonen-Austritt sofort entfernt (10-t-Poll
  + Belt-and-Braces-Sweep über ALLE Online-Spieler, nicht nur das Eintritt-Set).
- **Kein Fallschaden-Cheese**: `FALL_DAMAGE_MULTIPLIER` gilt nur in der Zone; Austritt in
  der Luft gibt 8 s Slow Falling statt Immunität (§3.4) — man kann den Krater nicht als
  globalen MLG-Ersatz benutzen.
- **Puls-Launch-Deckel**: nur in der Zone, `dy`-Cap +0.9, kein Stacking (§7.3); Elytra-
  Spieler bekommen keinen Launch (isFallFlying-Check).
- **Inversion-Cooldown** 120 s + Interaction-Entity `invulnerable` (nur Event-Hook, kein
  Durability-Kill möglich).
- **Kein Grief-Sonderschutz** für Kraterblöcke (bewusst: Spieler dürfen bauen/abbauen;
  die Landmark-Protection in `RingGrowthService` schützt nur gegen Worldgen-Sweeps).
  Sentinel-Selbstheilung (§2.3) repariert NUR bei fehlendem Sentinel, überschreibt also
  keine Spielerbauten im Bowl-Bereich, solange der Sockel steht.

---

## 8. Performance-Budget + Distanz-LOD

| Distanz zum Herz | aktiv | Kosten |
|---|---|---|
| > 224 | nichts — Orbitals halten Pose (0 Pakete, Gate-Early-out), Tickets laufen aus, Chunk entlädt | 0 |
| 160–224 | Orbitals @ 40-t-Kadenz (≈ 5–6 Pakete/t, phasen-gesliced) | minimal |
| ≤ 160 | Tracking-Horizont: Displays erscheinen; @ 20-t-Kadenz ≈ 11 Pakete/t | moderat |
| ≤ 140 | `gravity_lens`-Post (FEATURE, zählt gegen ≤ 3-Pass-Budget des `VeilPostController`) | 1 Fullscreen-Pass, trivialer Shader (kein Raymarch) |
| ≤ 120/96 | Photon-Loops attach (Hysterese 96/120), Raten rampen 60→120 | ≤ 5 Live-Executors (Bridge-Cap 40 unberührt) |
| Puls (überall ≤ 256) | 1 One-Shot-Executor + 1 Sound-Roundtrip | vernachlässigbar |

Regeln: Displays 220 (Cap 260) — unter `StormDebrisFx.HARD_CAP` 400 und mit identischem
Slicing; Interpolations-Fenster-Gesetz eingehalten (max 2.4°/t × 20 t = 48° < 90°);
`reducedFx` schaltet Photon-Loops (Release, Loop-Gesetz), Lens (`Detail=0` + Predicate)
und lässt nur Displays + Sounds (bewegungsarme Basis). Kein per-Tick-Allocation im
Feeder (Controller-Regel). Puls verdichtet Kadenz nur lokal ±40 t.

---

## 9. Dev-Commands

Neue Klasse **`devtools/dev/DevWoahCommands.java`** (Muster `DevEventCommands`: statischer
`DevCommandRegistry.register(DevCommandDoc(...))`-Block + `RegisterCommandsEvent`;
Kategorie `DevCategory.EVENT`, perm 2):

```
/dev woah gravity spawn [here]    # enqueued/baut die Site am Anker (oder Operator-Fuß,
                                  # 'here' = Iterier-Modus wie 'start herold here')
/dev woah gravity pulse           # feuert sofort einen Puls-Beat (Cue+Launch+Sound)
/dev woah gravity invert          # startet die 10-s-Inversion (Cooldown-Bypass)
/dev woah gravity reset           # discardet alle eclipse_gravrift_*-Displays + Rebuild
                                  # (das SanctumOrbitals.rebuild-Muster)
/dev woah gravity zone on|off     # Low-G-Zone togglen (Attribute testen)
/dev woah gravity status          # State-Dump: built, anchor, Puls-Raster, invert, Displays
```

Client-seitig reicht Vorhandenes: `/dev fx post force eclipse:gravity_lens …` fällt aus
den bestehenden `VeilPostController`-OVERRIDES-Hooks heraus (Force-on/off existiert dort
bereits als Map), plus `/photon_client clear_client_fx_cache` beim Asset-Iterieren
(dokumentiert in `PHOTON_EDITOR_CAPABILITIES.md`).

---

## 10. Datei-für-Datei-Checkliste

**Server, neu:**
1. `src/main/java/dev/projecteclipse/eclipse/gravityrift/package-info.java`
2. `gravityrift/GravityRiftState.java` — SavedData (§3.1)
3. `gravityrift/GravityRiftService.java` — Tick-Owner, Stage-Listener/Catch-up, Zone,
   Attribute, Puls, Inversion, Tickets, Payload-Sync (§3.2, §3.4)
4. `gravityrift/GravityRiftOrbitals.java` — 220-Display-Choreograf + Herz-Komposit +
   Reconcile + Tags (§3.3, §4.5)
5. `gravityrift/GravityRiftZone.java` — pure Geometrie (Zylinder-Test, Stufen-/Bahn-Layout-
   Konstanten, deterministische Piece-Hashes)
6. `worldgen/structure/GravityRiftBuilder.java` — Krater-Carve, statische Inseln,
   Loot-Chest, Herz-Sockel, Sentinel (§2.3, §5.3)

**Server, editiert:**
7. `worldgen/DiscMapDefaults.java` — Landmark-Zeile `eclipse:gravity_rift` (−40, 290, 40, 4)
8. `network/fx/S2CGravityRiftPayload.java` (neu) + `network/fx/FxPayloads.java`
   (playToClient-Registrierung + Handler-Branch)
9. `network/fx/FxCues.java` — `CUE_GRAVITY_PULSE`, `CUE_GRAVITY_INVERT`
10. `devtools/dev/DevWoahCommands.java` (neu, §9)

**Client, neu:**
11. `client/gravityrift/GravityRiftClientState.java` (§4.4)
12. `client/gravityrift/GravityRiftAmbience.java` — Loop-Fenster + Hum (§4.3, §6)
13. `veilfx/GravityRiftFxRows.java` — Cue-Rows (§4.3)
14. `veilfx/GravityRiftLensFx.java` — Post-Registrierung + Feeder (§4.1)

**Assets, neu:**
15. `assets/eclipse/pinwheel/post/gravity_lens.json`
16. `assets/eclipse/pinwheel/shaders/program/gravity_lens.fsh` + `gravity_lens.json`
17. `tools/photon/gravity_fx.py` → generiert
    `assets/eclipse/fx/gravity_{dust_rise,orbit_sparks,heart_aura,pulse_ring,invert_burst}.fx`
    (+ `.fxproj`-Siblings)
18. `data/eclipse/loot_table/chests/gravity_rift_loft.json` (§7.2)
19. Lang-Keys (`assets/eclipse/lang/en_us.json`, `de_de.json`):
    `eclipse.caption.gravity_rift.enter` (Whisper-Caption beim Erst-Eintritt via
    `S2CCaptionPayload`), Dev-Doc-Keys `dev.eclipse.doc.woah.gravity.*`

**Optional (empfohlen):**
20. `gametest/worldgen/GravityRiftTest.java` — Builder-Idempotenz + Attribut-Ein/Austritt
    (Repo hat GameTest-Infrastruktur unter `gametest/worldgen/`)

**Abarbeitungsreihenfolge:** 6 → 2 → 3 (ohne Puls/Invert) → 8/9 → 4 → 7 → 10 →
Client 11–14 → Assets 15–18 → Puls/Invert-Feinschliff → 19/20.
Jeder Schritt ist einzeln testbar (`/dev woah gravity spawn here` ab Schritt 3).

---

## 11. Risiken

| # | Risiko | Gegenmaßnahme (im Plan verankert) |
|---|---|---|
| R1 | **160-Block-Entity-Tracking-Horizont**: Orbital-Displays sind aus > 160 Blöcken unsichtbar — der "Blickfang aus 200 Blöcken" könnte scheitern | Hybrid-Design §1/§5.3: statische ECHTE Inseln + Puls-Lichtsäule (Photon, kein Entity) tragen das Fernbild; Displays sind bewusst nur Nahfeld-Dichte |
| R2 | **Bestandswelten ohne Landmark-Protection**: eingefrorene `disc_map.json` kennt den neuen Landmark nicht → `/eclipse stage rebuild` (Dev-Tool) könnte den Krater rewriten | Anker so gewählt, dass max. Ausdehnung 332.7 < 336 = Innenkante jedes zukünftigen Grow-Bands (§2.1); zusätzlich Sentinel-Selbstheilung (§2.3); Landmark-Zeile schützt neue Saves vollständig |
| R3 | **Attribut-Leaks/Kollisionen**: hängengebliebener Low-G-Modifier außerhalb der Zone (Logout mitten in der Zone, Plugin-Konflikte) | ausschließlich TRANSIENTE Modifier (nie persistiert), feste Modifier-Id, 10-t-Sweep über alle Online-Spieler statt Event-only, Removal bei Logout/Dim-Change/Server-Stop (§3.4) |
| R4 | **Interpolations-Hitching** bei Puls/Inversion (schnelle Posen über 20–40-t-Fenster; 90°-Fenster-Gesetz) | Kadenz-Verdichtung auf 10 t in den ±40-t-Fenstern um Puls/Invert; Envelope-Perioden nach der VFXPOLISH-3-Formel dimensioniert (§3.3, §8) |
| R5 | **Post-Pass-Konkurrenz**: `gravity_lens` (FEATURE) kämpft mit `storm_volume`/Grades um das ≤-3-Pass-Budget; Fog-Storm-Sites liegen auf derselben Disc | Lens-Predicate ist hart distanz-gegated (≤ 140) und degradiert sauber via `VeilPostController`-Eviction (Photon/Displays bleiben — kein leeres Feature); Anker liegt > 250 Blöcke von beiden fog_storm-Sites |
| R6 | Paket-/Serverlast durch 220 persistente Displays + Tickets | Phase-Slicing, Spieler-Gate 224, Ticket-TTL 600 t nur bei Spielernähe, Hard-Cap 260, Reconcile statt Dauer-Respawn (§3.3, §8) |
| R7 | Interaction-Entity-Duplikate/Strays nach Crash | Tag-Reconcile + Join-Zeit-Stray-Sweep (die `ExpansionBorderFx`/`SanctumOrbitals`-Doktrin: getaggte Joiner außerhalb des Live-Sets werden discardet) |
| R8 | Puls-Launch vs. clientseitige Bewegungs-Prediction (Gummiband) | Impuls +0.9 weit unter Motion-Packet-Clamp ±3.9; GRAVITY-Attribut ist vanilla-repliziert → Client rechnet identisch (§3.4, §7.3); Repo hat keinen Movement-Anticheat (nur Anti-Xray, verifiziert) |
