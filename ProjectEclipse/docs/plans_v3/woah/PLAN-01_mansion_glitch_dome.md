# PLAN-01 — MANSION GLITCH DOME (WOAH-Serie, Feature 1)

**Ziel-Repo-Stand:** Branch `cursor/project-eclipse`, NeoForge 1.21.1, Mojang-Mappings,
Mod-ID `eclipse`, Package-Root `dev.projecteclipse.eclipse`. Alle Klassen-/Datei-Referenzen
in diesem Plan wurden gegen den echten Code verifiziert (Stand dieses Plans).

**User-Vorgabe (wörtlich):** *"Baue eine Glitch Zone bei der Mansion Struktur wo man diesen
Grünen Outlines Glitch Effekt durchgehend drin im Gebäude hat. Platziere eine Art Gerät auf
dem Dach, das die Spieler schlagen und damit zerstören können. Es soll eine Art Schildblase
machen und in dieser Schildblase sind nur Scan Lines an. Man soll von draußen NICHT in diese
Glitch-Blase sehen können, sondern nur einen Strahl nach oben sehen von dem
Glitch-Macher-Gerät. Baue dafür ein Model in Blockbench/Blender."*

---

## 1. Konzept-Zusammenfassung

Die Woodland Mansion (Landmark `eclipse:mansion`, Stage 4) steht nach ihrer Platzierung
unter einer **Glitch-Schildblase**:

- **Innen** (Spieler in der Blase): dauerhaft der grüne **Outline-Glitch** (Welt schwarz,
  Phosphor-Kanten) **plus CRT-Scanlines-Overlay** — umgesetzt als EIN neuer kombinierter
  GLITCHZONE-Effekt `dome` (neue Veil-Post-Pipeline `eclipse:glitch_dome`), getrieben über
  das bestehende, server-autoritative GlitchZone-System (Sync, Easing, Accent-Farben,
  Iris-Gate — alles geschenkt).
- **Außen**: eine **opake, glitchende Schild-Hülle** (dunkle Kugel mit scrollendem
  Scanline-Muster, Hex-Schimmer und Fresnel-Rim) — man sieht NICHT hinein. Basis ist ein
  CPU-World-Space-Shell-Renderer (depth-schreibend, funktioniert auch unter Iris/ohne
  Veil-Post — Fallback-Gesetz §7); obendrauf als Garnitur ein Veil-Raymarch-Post
  `eclipse:dome_shell` (Verzerrung/Schimmer, Muster nach `storm_volume.fsh`).
- Auf dem **Dach** steht der **Glitch-Emitter** (`DomeEmitterEntity`, GeckoLib,
  Scenery-with-State nach dem `PortalGateEntity`-Vorbild): rotierende Ringe + pulsierender
  Kern (Glowmask), aus seiner Antenne steigt ein **vertikaler Licht-Strahl** in den Himmel
  (SupplyBeam-Bauart, shader-los, von weitem sichtbar).
- Spieler **schlagen** das Gerät (8 Melee-Treffer, i-Frames, Hit-Feedback: Photon-Funken,
  Flinch-Anim, lokaler Datamosh-Impuls). Beim letzten Treffer: **Zerstörungs-Sequenz** —
  Gerät kollabiert, die Hülle **zerspringt in ~240 BlockDisplay-Scherben**
  (StormDebrisFx/CreditsShatterAct-Doktrin), finaler Glitch-Burst + Screenshake, Loot
  (Glitch-Shards + Vitae-Shard + XP), der Innen-Glitch blendet aus, danach kurzes
  **Rest-Flackern** (drei schwache Scanlines-Nachbeben). Mansion ist ab dann normal
  sichtbar und normal abbaubar.
- **Persistenz**: kompletter Zustand in eigener SavedData (`eclipse_mansion_dome`),
  Restart-sicher inkl. laufender Zerstörungs-Sequenz und Nachbeben-Schedule.
- Solange der Schild aktiv ist, ist die Mansion **baugeschützt** (Break/Place/Explosion
  gecancelt, DevMode ausgenommen — `LandmarkProtection`-Muster).

Das Event bleibt im Haus-Stil **still**: kein Announce, kein Bossbar — Spieler entdecken
die Blase am Horizont (Strahl + schwarze Kugel).

---

## 2. Platzierung / Anchor (verifiziert)

### 2.1 Wo die Mansion wirklich herkommt

- Landmark-Definition: `worldgen/DiscMapDefaults.java` Z. ~177:
  `new DiscMapData.Landmark("eclipse:mansion", 219, -219, 40, 4)` — Overworld-Disc,
  r≈310 (dunkler Wald, äußerer Ring), Landmark-Radius 40, **Stage 4**.
- Enqueue-Kette: `StructureStamper.enqueueConfigured(...)` mappt
  `minecraft:mansion → eclipse:mansion` (über `VanillaLandmarks.landmarkIdFor`), Anchor =
  `StructureStamper.surfaceAnchor(profile, landmark)` (deterministisch via
  `DiscTerrainFunction.surfaceY`), Footprint = `max(2*40, 80) = 80`
  (`StructureStamper.footprintOf`). Ergebnis:
  `StructurePendingRegistry.PendingSite(siteId="eclipse:mansion",
  structureId="minecraft:mansion", dimension="overworld", anchor, stage=4, footprint=80)`.
- Platzierung: Async-Placer `"minecraft:mansion"` (registriert in
  `StructureStamper.registerPlacers`, Z. ~191) → `VanillaLandmarks.placeVanillaAsync`
  (PLATEAU-Modus, SitePrep, `StructureGrounding.fillFoundations`, `finishPlacement`).
- Lifecycle-Hook: `StructurePendingRegistry.addListener(SiteListener)` feuert
  `Phase.PLACED` für `siteId "eclipse:mansion"` auf dem Server-Thread;
  `StructurePendingRegistry.wasPlaced("eclipse:mansion")` beantwortet den Bestandsfall.

### 2.2 Wie der Dome seinen Anker findet

Neuer Code in `MansionDomeService` (siehe §3):

1. **Arm-Trigger**: `StructurePendingRegistry.addListener` — bei
   `Phase.PLACED && site.siteId().equals("eclipse:mansion")` → `arm(level, site.anchor())`.
   Zu diesem Zeitpunkt sind die Mansion-Chunks garantiert geladen (SitePrep.finish hat
   gerade relit/resent).
2. **Bestands-/Restart-Fall**: `ServerStartedEvent` — wenn
   `wasPlaced("eclipse:mansion")` und `MansionDomeState.status() == UNARMED` →
   `arm(...)` mit Anchor aus `StructureStamper.findLandmark(DiscProfile.OVERWORLD,
   "eclipse:mansion")` + `surfaceAnchor` (Achtung: `findLandmark`/`surfaceAnchor` sind
   package-private in `worldgen.structure` — im Zuge dieses Plans eine kleine öffentliche
   Fassade `VanillaLandmarks.landmarkAnchor(ServerLevel, String)` ergänzen, statt
   Sichtbarkeiten quer zu öffnen).
3. **Dach-Höhe**: beim Arm über die geladenen Chunks proben —
   `roofY = max( level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z) )`
   über ein 9×9-Sample-Gitter (Schrittweite 8) im 80×80-Footprint um den Anchor.
   `devicePos` = Säule mit maximalem Y innerhalb des inneren 24×24-Bereichs um den
   Anchor (dort ist das Hauptdach), +1 Block. Ein einzelner `level.getChunk(...)`-Load
   pro Probe ist zulässig (gleicher One-off wie `StructureStamper.registerStart`).
4. **Geometrie ableiten** (alles in SavedData persistieren, nie neu raten):
   - `groundY` = Anchor-Y (Plateau-Sitz).
   - `shellCentre` = `(anchor.x, groundY + 8, anchor.z)` — Kugel leicht eingegraben,
     obere Hälfte liest sich als Dome.
   - `shellRadius` = `clamp(ceil(halbe Footprint-Diagonale) + 10, 48, 72)` → bei
     Footprint 80 ≈ **64**; zusätzlich `shellRadius ≥ (roofY + 6) − shellCentre.y + 4`
     (Gerät + Dachfirst müssen sicher innen liegen).
   - `zoneRadius` = `shellRadius + 8` (= 72): das Edge-Band von
     `GlitchZone.spatialStrength` (25 % vom Radius, geklemmt 2–12 → hier 12) liegt damit
     größtenteils AUSSERHALB der Hülle — innen ist der Effekt überall voll.

---

## 3. Server-Systeme

Neues Feature-Package: `dev.projecteclipse.eclipse.mansiondome` (Server),
Client-Hälfte unter `client/mansiondome` (§4).

### 3.1 `mansiondome/MansionDomeState` (SavedData)

Haus-Muster `EclipseSavedData.getOverworld(server, DATA_NAME, Factory)` — exakt wie
`glitchzone/GlitchZoneState`. `DATA_NAME = "eclipse_mansion_dome"`.

Felder (NBT):

| Tag | Typ | Bedeutung |
|---|---|---|
| `status` | byte | 0 UNARMED, 1 ACTIVE, 2 COLLAPSING, 3 DESTROYED |
| `centre` | long (BlockPos) | `shellCentre` |
| `shellRadius` | float | s.o. |
| `groundY`, `roofY` | int | Probe-Ergebnisse |
| `devicePos` | long (BlockPos) | Standfuß des Geräts |
| `deviceUuid` | UUID | lebende Gerät-Entity (Reconcile) |
| `hitsRemaining` | int | Start 8 |
| `zoneId` | UUID | UUID der Dome-GlitchZone in `GlitchZoneState` |
| `collapseStartGameTime` | long | Beginn der Zerstörungs-Sequenz (Restart-Resume) |
| `aftershocksRemaining` | int + `nextAftershockGameTime` long | Rest-Flackern-Schedule |

Alle Mutatoren `setDirty()`; Getter unmodifiable. KEINE statischen Caches nötig außer dem
Sequenz-Cursor in `DomeShatterFx` (transient, `ServerStoppedEvent`-Reset — Haus-Regel).

### 3.2 `mansiondome/MansionDomeService` (@EventBusSubscriber, Server)

Der eine Tick-/Lifecycle-Owner:

- **Registrierung**: statisch `StructurePendingRegistry.addListener(...)` (Arm bei
  PLACED, §2.2); `ServerStartedEvent`-Reconcile; `ServerStoppedEvent` reset.
- **`arm(ServerLevel, BlockPos anchor)`**: Geometrie proben (§2.2), Status ACTIVE,
  Gerät spawnen (§3.3), Dome-Zone anlegen (§3.5), `FxAnchors`-artige Client-Sync via
  `S2CMansionDomePayload` (§3.6) an die Dimension broadcasten.
- **Tick (`ServerTickEvent.Post`, jede 20 t reicht — `gameTime % 20 == 0`)**, nur wenn
  Status ≠ UNARMED:
  - ACTIVE: Selbstheilung — (a) Zone mit `zoneId` fehlt in `GlitchZoneState.all()`
    (z. B. `/dev glitch clear`) → neu anlegen; (b) Gerät-Entity fehlt, Chunk geladen
    (`level.isLoaded(devicePos)` + `areEntitiesLoaded`) → respawnen (Deckhand-Lehre:
    NIE sofort nach einem einzelnen `getEntity(uuid) == null` respawnen — erst wenn die
    Entity-Section wirklich geladen ist).
  - COLLAPSING: Sequenz-Beats fahren (§5); Restart mitten in der Sequenz → ab
    `collapseStartGameTime` nahtlos weiterrechnen oder, wenn > Sequenzlänge, direkt
    `finishDestroy()`.
  - DESTROYED: Nachbeben-Schedule abarbeiten (§5, Rest-Flackern), danach idle (0 Kosten).
- **`onDeviceHit(DomeEmitterEntity, ServerPlayer)`** (vom Entity gerufen): Treffer
  zählen, Sounds/FX (§6/§4.4), `hitsRemaining == 0` → `beginDestroy()`.
- **Login-Sync**: `PlayerLoggedInEvent` → aktuelles `S2CMansionDomePayload` an den
  Spieler (FxAnchors-Login-Resend-Muster).

Tick-Budget: ACTIVE-Idle = 1 Map-Lookup + 2 Checks pro Sekunde; die Innen-Effekt-Syncs
laufen komplett über den existierenden `GlitchZoneService` (Change-Detection, EPSILON
0.02 — idle 0 Pakete).

### 3.3 `mansiondome/DomeEmitterEntity` (GeckoLib, Gerät)

Vorbild: `ferryman/finale/PortalGateEntity` (Scenery-with-State auf `EclipseGeoMob`).

- `extends EclipseGeoMob`, `geoId() = "glitch_emitter"`; Konstruktor: `setNoGravity(true)`,
  `noCulling = true`, `setPersistenceRequired()`, `travel`-No-op, kein Despawn.
- **HP/Hit-Handling**: NICHT über Vanilla-Health. `hurt(DamageSource, float)`:
  - akzeptiert nur direkten Spieler-Melee (`source.getDirectEntity() instanceof Player`,
    kein Projektil, kein Explosion/Fire — `DamageTypeTags`-Filter wie Deckhand);
  - i-Frames: 10 t (`lastHitGameTime`-Gate);
  - pro gültigem Treffer: synced `DATA_HITS` (`EntityDataAccessor<Integer>`) dekrement,
    `triggerAction("hit")`, Callback `MansionDomeService.onDeviceHit`;
  - alles andere: `return false` + Abpraller-Feedback (Sound `AMETHYST_BLOCK_CHIME`,
    Pitch 1.6).
- **Animation-Wiring**: `handleBaseState` → immer `idle`-Loop;
  `registerActionTriggers`: `hit` (Play-once) + `death` (hold) — Namen aus
  `EclipseGeoAnimations`-Konvention (`animation.glitch_emitter.idle` usw.).
- **Registrierung**: `entity/EclipseEntities` — `ENTITIES.register("glitch_emitter", ...)`
  (MobCategory.MISC, Größe 1.4 × 2.6, `clientTrackingRange` 10 Chunks), Attribute im
  `EntityAttributeCreationEvent` (nur MAX_HEALTH 100 als Formalie — echte HP sind
  `DATA_HITS`). Spawn-Egg nicht nötig.
- Synced `DATA_HITS` treibt clientseitig Riss-Stufen/Extra-Funken (§4.4); die
  First-Hurt-Frame-Funken kommen gratis über `client/entity/geo/HurtSparks`
  (feuert für JEDEN `EclipseGeoRenderer`-Mob).

### 3.4 `mansiondome/MansionDomeProtection`

Muster: `protection/LandmarkProtection` (B7). Solange `status == ACTIVE || COLLAPSING`:

- `BlockEvent.BreakEvent` + `BlockEvent.EntityPlaceEvent` im Zylinder
  `r = shellRadius`, Y-Band `groundY − 8 … roofY + 24` → cancel + Actionbar
  `message.eclipse.dome_protected` (neuer Lang-Key, beide Sprachdateien), `DevMode`-Spieler
  ausgenommen (PROGFIX #5).
- `ExplosionEvent.Detonate`: betroffene Blöcke im Zylinder aus der Liste entfernen.
- Kein Schutz mehr ab DESTROYED — die Mansion gehört dann den Spielern.

### 3.5 Innen-Effekt: Dome-Zone im GLITCHZONE-System

**Entscheidung**: den Innen-Glitch NICHT als Parallel-System bauen, sondern als
persistente `GlitchZone` — Präzedenzfall `AltarGlitchAmbience` (Feature schreibt Zonen in
`GlitchZoneState`, `GlitchZoneService` synct).

- Neuer Effekt-Typ in `glitchzone/GlitchZoneEffects`: Konstante `DOME = "dome"` + Eintrag
  in `IDS`. Laut Klassen-Doc ist das der sanktionierte Erweiterungspfad ("adding an effect
  = add the asset pair and one entry here"). `client/GlitchZoneFx` registriert die
  Pipeline-Row automatisch (der static-Block iteriert `GlitchZoneEffects.IDS`) — dort ist
  KEINE Änderung nötig.
- Zone anlegen (in `arm`):
  `new GlitchZone(zoneId, Level.OVERWORLD, shellCentre, zoneRadius, "dome",
  GlitchColors.DEFAULT, now, PERMANENT_END, 40, 0, false)` mit
  `PERMANENT_END = Long.MAX_VALUE / 2` (übersteht `removeExpired`; kein Overflow in
  `temporalStrength`). Default-Accent = das Shipped-Grün des Shaders (F-049-Gesetz:
  leerer Colour-String ist bit-identisch zur Konstante).
- Zone entfernen (Zerstörung): NICHT hart löschen, sondern durch eine Kopie mit
  `endGameTime = now + 60, fadeTicks = 60` ersetzen (`state.remove(zoneId)` +
  `state.add(fadingCopy)`) — der Innen-Glitch blendet über 3 s aus, `GlitchZoneService`
  erledigt den Rest.
- Hit-Impulse: pro Treffer eine Mini-Zone
  `("datamosh", radius 16, 30 t Dauer, fadeTicks 10)` am `devicePos` — max. 1 alle 10 t
  (i-Frame-Gate), `MAX_ZONES` 64 ist nie in Gefahr.

### 3.6 Netzwerk

- **Neu** `network/fx/S2CMansionDomePayload` (Record-Payload, `NetCodecs`-Stil):
  `{byte status, BlockPos centre, float shellRadius, int deviceY, long collapseStartGameTime}`.
  Registrierung: eine Zeile in `network/EclipsePayloads.register` (Registrar "3",
  additiv — kein Versions-Bump). Handler schreibt in `client/mansiondome/MansionDomeClient`.
  Gesendet: bei Arm/Statuswechsel an die Dimension
  (`PacketDistributor.sendToPlayersInDimension`), bei Login an den Spieler.
- **FxCues-Ergänzungen** (`network/fx/FxCues`, Namespace-Gesetz `eclipse:fx/cue/…`):
  - `CUE_DOME_DEVICE_HIT = cue("dome_device_hit")` — Position-Lane, `a` =
    `hitsRemaining / 8f`, `b` = 0 normal / 1 finaler Treffer.
  - `CUE_DOME_SHATTER_BURST = cue("dome_shatter_burst")` — Position-Lane am `shellCentre`,
    `a` = shellRadius.
  - `CUE_DOME_DEVICE_IDLE = cue("dome_device_idle")` — **Loop-Row, WINDOWED-only**
    (niemals payload-gefeuert; Fenster-Controller im Client, §4.4).
  - `CUE_DOME_BEAM_BASE = cue("dome_beam_base")` — Loop-Row, WINDOWED-only.
- Screenshake: bestehendes `S2CShakePayload` (StormDebrisFx-Nutzung als Vorlage).

### 3.7 `mansiondome/DomeShatterFx` (Server-BlockDisplay-Choreografie)

Doktrin komplett aus `sequence/StormDebrisFx` + `ritual/CreditsShatterAct` übernehmen:

- Command-Tag `eclipse_dome_shatter` an jeder Scherbe; `EntityJoinLevelEvent`-Sweep
  discardet getaggte Displays, die nicht getrackt sind (Crash-Streuner); Watchdog 400 t;
  `/kill @e[tag=eclipse_dome_shatter]` funktioniert immer.
- **Mount-Gesetz**: alle Scherben werden an EINER festen Entity-Position gespawnt
  (`shellCentre`), alle Bewegung lebt in der Transformation (Translation), Pushes alle
  10 t mit passender `setTransformationInterpolationDuration` + 1-Fenster-Lead;
  `DisplayBrightnessFx.set(display, 15, 15, viewRangeOverride)` (Brightness-Override +
  `view_range` ~4.0 ≈ 256 Blöcke — sonst sieht ab 64 Blöcken niemand die Show).
- Scherben: ~**240** Displays (Cap), Fibonacci-Gitter auf der oberen Hemisphäre +
  Äquator-Ring; BlockStates gemischt `GREEN_STAINED_GLASS` (60 %), `TINTED_GLASS` (30 %),
  `EMERALD_BLOCK` (10 % Glints); Grundform: flache Platte (Scale ≈ 2.6 × 2.6 × 0.25),
  tangential zur Kugel rotiert (Quaternion aus Normale).
- Spawn budgetiert 60/Tick (4 Ticks), Flug-Update ≈ 240/10 = **24 Entity-Updates/Tick**
  im Schnitt — weit unter dem FIN-6-Budget (CreditsShatterAct fährt 185/t).

---

## 4. Client-Systeme

### 4.1 `client/mansiondome/MansionDomeClient` (State + Post-Rows)

- Hält das letzte `S2CMansionDomePayload` (+ per-Tick-Easing `visibility` 0→1 beim Arm,
  1→0 über die Collapse-Timeline; `LoggingOut`/`Clone`-Reset wie `StormVolumeFx`).
- **Inside/Outside**: `inside = cameraPos.distanceTo(centre) < shellRadius − 1.5`.
  Innen kommt der Post-Effekt server-autoritativ über die GlitchZone (§3.5) — hier wird
  nur entschieden, was die HÜLLE tut: innen wird sie nicht gezeichnet (bzw. nur ein
  schwacher Interior-Film, s. 4.2).
- Registriert im static-Init die Post-Row (VeilPostController-Muster):
  `PipelineSpec(eclipse:dome_shell, FEATURE, () -> shellPostStrength() > 0.01, feeder)`.
  FEATURE wie `storm_volume` (komponiert über Grades, überlebt Eviction gegen sie);
  der Innen-Effekt `glitch_dome` läuft als TRANSITION über die automatische
  `GlitchZoneFx`-Row. Innen/Außen schließen sich gegenseitig aus → real nie mehr als
  1 zusätzlicher Fullscreen-Pass durch dieses Feature.
- Fenster-Controller für die beiden Photon-Loops (WINDOWED-Gesetz, INTEGRATION.md §4,
  `SanctumLightfall`-Muster): Fenster auf, wenn Kamera < 48 Blöcke am `devicePos` und
  Status ACTIVE; `PhotonFxRegistry.ensureLoop` / `releaseLoop`; Release bei `reducedFx`,
  Dimensionswechsel, Logout.

### 4.2 `client/mansiondome/DomeShellRenderer` (CPU-Hülle — die Blickdicht-Garantie)

Muster: `veilfx/SupplyBeamRenderer` + `stormfx/StormWallRenderer`-Occluder-Idee.

- `RenderLevelStageEvent`, Stage `AFTER_ENTITIES` (Hülle ist OPAK und **depth-schreibend**
  — sie muss Partikel/Translucents dahinter clippen; dokumentierter Fallback bei
  Sodium/Embeddium-Artefakten: Stage-Konstante auf `AFTER_PARTICLES` tauschen, gleiches
  Vorgehen wie beim SupplyBeam).
- Geometrie: UV-Kugel, obere Hemisphäre + 2 Ringe unter den Horizont (der Rest steckt im
  Boden): nah **24 × 12 Segmente** (~576 Quads, 1 Drawcall, gepoolter `Tesselator`),
  ab 300 Blöcken **16 × 8** (~128 Quads). Double-sided NICHT nötig: außen Backface-Cull;
  ist die Kamera innen, wird stattdessen nur ein sehr schwacher additiver Interior-Film
  (Alpha ≤ 0.08, gleiche Kugel, Frontface-Cull invertiert) gezeichnet, damit der
  Blasenrand von innen lesbar bleibt.
- Look: Basisfarbe fast schwarz (0.01/0.03/0.02) — **voll deckend** (Alpha 1, depth write),
  darüber im selben Vertex-Stream: (a) scrollende horizontale Scanlines
  (Textur `textures/particle/noise_strip.png` oder `crt_glow_2x2.png`, V-Scroll
  ~0.6 s/Wiederholung, Grün 0.30/0.95/0.62 — `GlitchColors`-Grün), (b) Hex-/Zellen-Schimmer
  als zweiter additiver Pass mit `textures/environment/border_glitch.png` (UV auf
  Sphärenkoordinaten, langsame Rotation), (c) Fresnel-Rim per Vertex-Alpha
  (`pow(1−|dot(view,normal)|, 2)`), (d) 2-Hz-Puls auf der Rim-Helligkeit.
  Alles shader-los (Vanilla-RenderTypes) → funktioniert unter Iris-Packs = die Garantie
  "von draußen sieht man NICHT hinein" hängt NIE am Veil-Post.
- Aktiv nur bei Status ACTIVE/COLLAPSING, Distanz < 640, `visibility > 0.01`.
  COLLAPSING: 0–30 t Puls-Beschleunigung + Aufhellen, ab t30 (Shatter-Beat) hart aus —
  ab da übernehmen die Server-Scherben.

### 4.3 Veil-Post-Pipelines

**(a) NEU `eclipse:glitch_dome`** — der Innen-Effekt (Outline + Scanlines kombiniert):

- Assets: `assets/eclipse/pinwheel/post/glitch_dome.json` (1 Stage, `veil:blit`,
  `in minecraft:main`, `out veil:post` — 1:1 wie `glitch_outline.json`),
  `shaders/program/glitch_dome.fsh` + `glitch_dome.json` (Program-Def).
- Shader-Inhalt: `glitch_outline.fsh` als Basis (Depth-Laplacian + Normal-Disagreement +
  Roberts-Luma, Phosphor-Palette `EDGE_GREEN/FILL_GREEN`, Accent-Mechanik) **plus** die
  Scanline-Schichten aus `glitch_scanlines.fsh`: feine Scanlines (Zeilenmaske auf dem
  Readout), Vertical-Hold-Jitter (nur auf den Readout-UVs, gated über `Detail`),
  Roll-Bar + Tape-Static schwach (0.4× der scanlines-Stärke). Beide Quell-Shader nutzen
  dieselben Includes (`eclipse:eclipse_common`, `eclipse:eclipse_glitch`,
  `veil:space_helper`) und denselben Uniform-Vertrag — der Merge ist mechanisch.
- **Uniform-Vertrag (eingefroren, identisch zu den 5 Bestands-Effekten)**: `Strength`
  (0..1, No-op-Gesetz bei 0, Early-out ≤ 0.0005), `Time` (Wall-Clock-Sekunden), `Detail`
  (0 unter `reducedFx`: Sweep/Jitter/Static einfrieren, Grade bleibt), `AccentColor` +
  `AccentAmount` (F-049), `Origin`/`OriginMode` (deklarieren, ignorieren — Feeder ist
  row-uniform). Gefüttert wird automatisch von `client/GlitchZoneFx.feed` — KEINE
  Client-Java-Änderung für den Innen-Effekt nötig.

**(b) NEU `eclipse:dome_shell`** — Außen-Garnitur (FEATURE):

- Assets: `pinwheel/post/dome_shell.json`, `shaders/program/dome_shell.fsh/.json`.
- Technik nach `storm_volume.fsh` (Ray-Sphere, szene-depth-geklemmt), aber DEUTLICH
  billiger: kein fBm-Raymarch, sondern analytischer Shell-Hit (2 Kugel-Schnitte):
  auf der Hit-Fläche Verzerrung (Screen-UV-Offset nach Sphärennormale × Glitch-Noise),
  Hex-Schimmer, chromatische Aberration am Rim, Scanline-Flackern — additiv ÜBER die
  bereits opake CPU-Hülle.
- Uniforms: `DomeCenter` (kamera-relativ — das `VolCenter`-Gesetz: Subtraktion in Doubles
  im Feeder), `DomeRadius`, `Strength` (Distanz-Ramp 1→0 über 450→600 Blöcke +
  Collapse-Puls), `Time` (Tick-Clock wie storm_volume), `Detail`. Feeder in
  `MansionDomeClient` (allokationsfrei). Innen (`inside == true`) → `Strength 0`.
  Unter `reducedFx` bleibt der Pass aus (Motion-FX-Gesetz) — die CPU-Hülle deckt weiter ab.

### 4.4 Photon-FX (Assets generiert über `tools/photon/fxlib.py`, neues Skript `tools/photon/mansion_dome_fx.py`; jede `.fx` mit `.fxproj`-Sibling via `write_fxproj`)

Rows registriert in **neu** `veilfx/MansionDomeFxRows` (Registrar-Klasse nach
`WorldPhotonFxRows`-Vorbild, Aufruf im `FMLClientSetupEvent` neben den bestehenden
Registraren). Alle Texturen existieren bereits unter `assets/eclipse/textures/particle/`.

| Cue / Asset | Loop | Emitter (Photon) | Spez |
|---|---|---|---|
| `dome_device_idle.fx` | ja (WINDOWED, 48-Block-Fenster) | E1 "core_motes": Shape `sphere(r=0.6)`, Rate 6/s, Life 1.2–1.8 s, Textur `star_2x2.png`, Additive, Grün-Gradient (Alpha 0→1→0), Größe `random_between(0.05, 0.10)`, Molang-Drift nach oben (`variable.particle_age`-Kurve, vy ≈ 0.4) | Kern-Glimmen |
| | | E2 "ring_arcs": Shape `circle(r=0.9)`, Burst 2 alle 0.5 s, Life 0.4 s, Textur `noise_strip.png` (Stretch), OrbitalVelocity um Y (Molang `math.sin(variable.particle_age*8)`) | Blitz-Bögen an den Ringen |
| `dome_beam_base.fx` | ja (WINDOWED) | E1 "updraft": Shape `cylinder(r=0.5)`, Rate 10/s, Life 2.5 s, Textur `beam_core.png`, Additive, vy 2.5→6 (Kurve), Größe 0.12→0.0 | Sog in den Strahl |
| `dome_device_hit.fx` | nein (BURST) | E1 "sparks": Burst `12 + 12·(1−a)` (a = hitsRemaining/8 — je kaputter, desto mehr), Life 0.5–0.8 s, Textur `glitch_shard.png`, Gravity −4, Radial-Speed 4–7, Größe 0.08–0.16, grün/weiß random_color | Hit-Funken |
| | | E2 "glitch_frame": Burst 1, Life 0.15 s, Textur `static_4x4.png`, Billboard groß (1.4), Additive | 1-Frame-Störbild |
| `dome_shatter_burst.fx` | nein (BURST) | E1 "ring_shock": Burst 1, Life 0.6 s, Textur `ring_soft.png`, Größe 4→`a` (shellRadius, Executor-Scale über Cue-Param wie `structure_slam`), Alpha 1→0 | Schockwellen-Ring |
| | | E2 "shard_rain": Burst 90, Life 1.5–2.5 s, Textur `glitch_shard.png`, Cone nach oben (angle 40°), Speed 8–14, Gravity −9, Collision aus | Funken-Regen |
| | | E3 "afterglow": Burst 1, Life 2.0 s, Textur `dome_faint.png`, Größe 10→18, Additive, Alpha 0.5→0 | Nachleuchten |

Row-Parameter: Kanal `BURST` für die One-Shots, `AMBIENT` für die Loops; Mode `LAYER`;
Quasar-Fallback `null` (neue Cues, Baseline war nichts — sanktioniert laut
`PhotonFxRegistry`-Doc). Der `dome_shatter_burst`-Cue braucht einen kleinen
`PhotonLeg` (Executor-Scale aus `a` — Muster `CUE_STRUCTURE_SLAM`).

### 4.5 Beam-Rendering (`client/mansiondome/DomeBeamRenderer`)

Klon von `veilfx/SupplyBeamRenderer` (bewusst KEIN Refactor des Originals — Datei kopieren
und anpassen, das Original ist FROZEN-artig verdrahtet):

- Basis am Geräte-Antennen-Top (`devicePos.y + 2.4`), Höhe **200** Blöcke (Himmel-Stich),
  4 gekreuzte additive Planes (0°/45°/90°/135°), Core-Breite 0.5, Haze 1.6,
  Impact-Glow-Disc auf dem Dach; Textur `textures/environment/border_glitch.png`,
  Scroll nach oben; Farbe Dome-Grün.
- LOD: > 192 Blöcke nur Core-Planes, > **640** nichts (der Strahl ist das
  Fernsicht-Signal, deshalb weiter als der SupplyBeam); ≤ 16 Quads nah (§3.5-Beam-Cap).
- Status-Kopplung: ACTIVE voll; COLLAPSING t0–t30 Flackern (Alpha-Noise 10 Hz), ab t30
  Top-down-Kollaps (Höhe 200→0 über 20 t); DESTROYED aus. Shader-los → Iris-fest.

### 4.6 Gerät-Renderer

`client/entity/DomeEmitterRenderer extends EclipseGeoRenderer<DomeEmitterEntity>` —
Asset-Tripel per Konvention `geo/entity/glitch_emitter.geo.json`,
`animations/entity/glitch_emitter.animation.json`, `textures/entity/glitch_emitter.png`
**+ `textures/entity/glitch_emitter_glowmask.png`** (Emissive-Layer wird von
`EclipseGeoRenderer` nativ unterstützt, gleiche Canvas-Größe erzwungen). Registrierung:
Self-Registration-Muster `DeckhandRenderer.Registration` ODER eine Zeile in
`client/entity/EclipseEntityRenderers.onRegisterRenderers` — Letzteres bevorzugen (weniger
Magie). Riss-Stufen: ab `DATA_HITS ≤ 4` RenderColor leicht rot-flackernd, ab ≤ 2
zusätzlich Jitter-Offset (±0.02) im `preRender` — billig, kein Extra-Asset.

---

## 5. Zerstörungs-Sequenz (BlockDisplay-Choreografie, Timeline in Ticks)

`t = 0` ist der finale Treffer (`beginDestroy()`): Status → COLLAPSING,
`collapseStartGameTime = now`, Payload-Broadcast.

| Tick | Server | Client (folgt aus Payload/Cues) |
|---|---|---|
| t0 | Gerät: `triggerAction("death")`; Sounds `ANVIL_LAND` (1.0/0.6) + `EclipseSounds.EVENT_BORDER_GLITCH` am Gerät; `CUE_DOME_DEVICE_HIT` mit `b=1`; Mini-Zone `datamosh` r24/60 t/fade 20 am Gerät | Beam-Flackern beginnt; Hüllen-Puls beschleunigt |
| t10 | `S2CShakePayload` an Spieler < 200 Blöcke (Stärke 0.6) | Shake |
| t20 | **Loot**: ItemEntities am `devicePos` — 4× `EclipseItems.GLITCH_SHARD`, 1× `EclipseItems.VITAE_SHARD`; XP-Orbs 500 gestreut; Sound `SoundEvents.PLAYER_LEVELUP` (0.6/1.4) | — |
| t30 | Gerät-Entity `discard()`; **Shatter-Beat**: Status-Detail im Payload (Client stoppt Hülle), `DomeShatterFx.begin(centre, shellRadius)` (Spawn 60/Tick, 4 Ticks); `CUE_DOME_SHATTER_BURST(centre, a=shellRadius)`; Sounds `EclipseSounds.EVENT_STORM_SHATTER` + `SoundEvents.GENERIC_EXPLODE` (**Achtung: in 1.21.1 ein `Holder<SoundEvent>` → `.value()`**), beide range-weit; zweiter Shake 1.0 | CPU-Hülle aus; Scherben übernehmen; Photon-Burst |
| t30–t150 | Scherbenflug: radial + Up-Bias 0.4–1.0, Tumble-Impuls mit `1−(1−q)^3`-Decay (CreditsShatterAct-Gesetz), Scale → 0 bei individuellem Life 80–120 t; Pushes alle 10 t | Beam kollabiert t30–t50 top-down |
| t80 | Dome-Zone gegen Fading-Kopie tauschen (`end = now+60`, `fade = 60`, §3.5) | Innen-Glitch blendet über 3 s aus, Welt kommt zurück |
| t150 | Scherben-Discard (Watchdog spätestens t430); Status → **DESTROYED**; Nachbeben armen: `aftershocksRemaining = 3`, `next = now + 1200` | Alles aus bis auf Rest-Flackern |
| +60 s / +180 s / +360 s | je 1 Nachbeben: Zone `("scanlines", r=20, 80–120 t, fadeIn 20, fade 40)` an zufälliger Position im Mansion-Footprint (deterministisch aus `placementRandom`-Seed-Idee: `RandomSource.create(mapSeed ^ centre.asLong() ^ n)`) | kurzes Scanline-Flackern im Haus |

Restart-Sicherheit: COLLAPSING mit `elapsed = now − collapseStartGameTime` wieder
aufgenommen; verpasste Beats werden in EINEM Tick nachgeholt (Loot nur, wenn
`elapsed < 20` beim Crash noch nicht gedroppt war — Flag `lootDropped` in SavedData);
Scherben-Streuner fängt der Tag-Sweep.

---

## 6. Sounds (gegen `assets/eclipse/sounds.json` + `registry/EclipseSounds` verifiziert)

| Moment | Sound | Quelle |
|---|---|---|
| Schild-Ambient (nahe Hülle, Client-Fenster-Loop) | `EclipseSounds.AMBIENT_STORM_DOME_DRONE` (`ambient.storm_dome_drone`) | vorhanden — passt namentlich perfekt |
| Beam-Summen am Gerät (Client-Fenster-Loop) | `EclipseSounds.EVENT_BEAM_HUM` (`event.beam_hum`) | vorhanden |
| Gültiger Treffer | `SoundEvents.IRON_GOLEM_HURT` (Pitch 0.8 + 0.06·Treffer) + `SoundEvents.AMETHYST_BLOCK_CHIME` (0.7/0.6) | vanilla |
| Abpraller (Projektil/Explosion) | `SoundEvents.AMETHYST_BLOCK_CHIME` (1.6) | vanilla |
| Glitch-Impuls pro Treffer | `EclipseSounds.EVENT_BORDER_GLITCH` (`event.border_glitch`) | vorhanden |
| Gerät-Tod (t0) | `SoundEvents.ANVIL_LAND` (1.0/0.6) + `event.border_glitch` | mix |
| Shell-Shatter (t30) | `EclipseSounds.EVENT_STORM_SHATTER` (`event.storm_shatter`) + `SoundEvents.GENERIC_EXPLODE.value()` | vorhanden/vanilla |
| Loot-Pop (t20) | `SoundEvents.PLAYER_LEVELUP` (0.6/1.4) | vanilla |
| Nachbeben | `EclipseSounds.EVENT_STORM_FLICKER` (`event.storm_flicker`) leise | vorhanden |

Keine neuen `sounds.json`-Einträge nötig; Loops laufen client-seitig über den
Fenster-Controller (kein Server-Sound-Spam).

---

## 7. Gerät-Modell "glitch_emitter" (Blockbench-/geo.json-Spec)

Format wie `assets/eclipse/geo/entity/portal_gate.geo.json` (`format_version 1.12.0`,
Bedrock-Geometry). Konventionen: 16 Model-Units = 1 Block; Identifier
`geometry.glitch_emitter`; **texture_width/height 128×128**;
`visible_bounds_width 6`, `visible_bounds_height 5`, Offset `[0, 2, 0]`.
Gesamthöhe ≈ 39 u ≈ 2.45 Blöcke (Hitbox 1.4 × 2.6 passt).

Bones + Cubes (origin = Ecke, size in Units, uv = Platzierungsvorschlag):

| Bone (Parent) | Pivot | Cubes |
|---|---|---|
| `root` | [0,0,0] | — |
| `base` (root) | [0,0,0] | Bodenplatte `origin [-6,0,-6] size [12,3,12] uv [0,0]` |
| `leg_0/1/2` (base, Yaw 0°/120°/240°) | [0,3,0] | je `origin [-1,0,5] size [2,5,2] uv [48,0]`, Bone-Rotation x = −22° (gespreiztes Stativ) |
| `pylon` (base) | [0,3,0] | Mast `origin [-2,3,-2] size [4,15,4] uv [0,16]` |
| `ring_outer` (pylon) | [0,24,0] | 4 Segmente: `[-9,23,-1.5] size [5,2,3] uv [32,16]`, dann je +90° um Y gedreht (im Modell 4 Cubes mit rotierten Origins bzw. 4 Sub-Bones `seg_n` mit Yaw n·90) |
| `ring_inner` (pylon, Grund-Tilt z = 20°) | [0,24,0] | 4 Segmente radius 6: `[-6.5,23.2,-1] size [3.5,1.6,2] uv [32,24]` je +90° |
| `core` (pylon) | [0,24,0] | Kern `origin [-3,21,-3] size [6,6,6] uv [0,40]` — **Glowmask: Kern voll emissiv** |
| `antenna` (core) | [0,30,0] | Spitze `origin [-0.5,27,-0.5] size [1,9,1] uv [56,0]` + Emitter-Knauf `origin [-1.5,36,-1.5] size [3,3,3] uv [56,16]` (Glowmask an) — Beam-Ursprung bei y ≈ 39 u ≈ 2.4 Blöcke |

Textur-Look: dunkles Gunmetal mit Kupfer-Kanten; Kern + Knauf: Giftgrün
(0.30/0.95/0.62) — nur diese Bereiche in `glitch_emitter_glowmask.png` weiß, Rest schwarz.

Animationen (`animations/entity/glitch_emitter.animation.json`,
Namensschema `animation.glitch_emitter.<name>` — Pflicht wegen
`EclipseGeoAnimations`-Lookup):

- **`idle`** (Loop, 4.0 s): `ring_outer` rot.y 0→360; `ring_inner` rot.y 360→0 plus
  rot.x Wobble ±6° (Keyframes 0/1/2/3/4 s); `core` scale 1→1.06→1 (bei 2 s) und
  pos.y ±0.5 u Bob; `antenna` rot.y Jitter (0°, 4°, −3°, 0° bei 0/1.3/2.6/4 s).
- **`hit`** (One-shot, 0.35 s): `root` rot.z 0→6°→−4°→0; `core` scale 1→0.85→1.05→1;
  `ring_outer` +25° Yaw-Step (Beschleunigungs-Illusion).
- **`death`** (One-shot, 1.5 s, HOLD): `ring_outer`/`ring_inner` rot.x → 75–85° + pos.y
  −6 u (Ringe kippen und sacken, leicht versetzt: inner ab 0.2 s); `core` scale → 1.3
  (0.9 s) → 0.0 (1.2 s); `pylon` rot.z → 14°; `base` pos.y → −2 u. End-Pose halten
  (GeckoLib `hold`) — Server discardet bei t30 ohnehin.

Damit kann ein Implementierer die `.geo.json` + `.animation.json` direkt programmatisch
oder in Blockbench (Bedrock-Entity-Projekt, 128×128) erzeugen; Referenz für Zahlenformat
und Bone-Verschachtelung ist `portal_gate.geo.json`.

---

## 8. Gameplay

- **Interaktion**: Nur Spieler-Melee zählt (kein Bogen/TNT/Creeper-Cheese — Abpraller-
  Feedback statt Schaden). 8 Treffer, 10 t i-Frames → Solo ≈ 8–10 s Fokus auf dem Dach;
  das Dach erreicht man klassisch durchs Gebäude (Innen-Glitch macht das zum Erlebnis)
  oder per Towern (erlaubt: Platzieren ist nur INNERHALB des Schutz-Zylinders gesperrt —
  Ausnahme: Platzieren erlaubt, Break gesperrt? **Entscheidung: beides gesperrt**, sonst
  wird die Protection über Block-Töpfe ausgehebelt; Anlauf übers Dach ist per Vanilla-
  Mansion-Treppen möglich).
- **Schutz**: solange ACTIVE/COLLAPSING kein Break/Place/Explosionsschaden im Zylinder
  (§3.4) — "kein Abbau der Mansion durch Fremde solange Schild aktiv" = ja, für ALLE
  Nicht-DevMode-Spieler.
- **Belohnung**: 4× `glitch_shard` (Epic, existiert — füttert die Vitae-Schmiede-Route),
  1× `vitae_shard`, 500 XP; dazu implizit: die komplette, ungeplünderte Mansion
  (Vanilla-Loot) wird zugänglich. Kein Announce (silent-Gesetz) — Belohnung erklärt sich
  physisch.
- **Balancing**: Kein HP-Regen des Geräts (Fortschritt bleibt, persistiert); Blase ist
  begehbar (kein physischer Kollisions-Schild) — der Horror ist visuell; Mobs innen
  normal. Optionaler späterer Hook (NICHT Teil dieses Plans): Glitched-Mob-Spawns in der
  Blase über `glitch/GlitchSpawnService`.

---

## 9. Performance-Budget + Culling/LOD

| Posten | Budget | Mechanik |
|---|---|---|
| Server idle (ACTIVE) | ~0 | GlitchZone-Sync nur bei Änderung (EPSILON-Cache); Service-Check 1×/s |
| Server Zerstörung | ≤ 60 Spawns/t für 4 t; ~24 Display-Updates/t für 120 t | Phase-Slicing (StormDebrisFx-Gesetz), Cap 240, Watchdog |
| Client Hülle | 1 Drawcall, ≤ 576 Quads nah / 128 fern (LOD ab 300), 0 Allokationen | gepoolter Tesselator, Early-out ohne Payload |
| Client Beam | ≤ 16 Quads nah, 4 fern (>192), aus >640 | SupplyBeam-LOD |
| Post innen (`glitch_dome`) | 1 Fullscreen-Pass, nur in der Zone | GlitchZoneFx-Row, TRANSITION, `MIN_ACTIVE`-Gate |
| Post außen (`dome_shell`) | 1 Pass, analytisch (kein March-Loop), Strength-Fade 450→600, aus > 600 u. innen | eigener Feeder; `reducedFx` → aus (CPU-Hülle deckt weiter ab) |
| Photon | 2 Loops nur im 48-Block-Fenster; Bursts BURST-budgetiert | WINDOWED-Gesetz, `FxBudget` |
| Gerät | 1 Entity, GeckoLib-Anim nur beim Rendern | `clientTrackingRange` 10 Chunks |

Innen/Außen exklusiv → dieses Feature addiert nie mehr als 1 gleichzeitigen Post-Pass;
zusammen mit `world_grade` + ggf. Storm bleibt `MAX_CONCURRENT = 3` haltbar (FEATURE-
Priorität sichert `dome_shell` gegen Grade-Eviction, TRANSITION sichert `glitch_dome`).

---

## 10. Dev-Commands (`devtools/dev/DevMansionDomeCommands`)

Registrierung: `DevCommandRegistry.register(DevCommandDoc...)` im static-Block +
`RegisterCommandsEvent` (exakt das `DevGlitchCommands`-Muster, perm 2). Baum `/dev dome …`
(die WOAH-Serie hängt so unter einem gemeinsamen, dokumentierten Literal):

- `/dev dome status` — Status, Zentrum, Radius, hitsRemaining, zoneId, Gerät-UUID,
  Nachbeben-Schedule.
- `/dev dome arm` — armiert an der echten Mansion-Landmark (Fehler, wenn Mansion noch
  nicht PLACED); `/dev dome arm here [radius]` — Test-Dome an der Spielerposition
  (transient markiert, nutzt dieselben Pfade; für Shader-/Renderer-Iteration ohne
  Stage-4-Welt).
- `/dev dome hits <n>` — hitsRemaining setzen (sync auf Entity-Data).
- `/dev dome destroy` — volle Zerstörungs-Sequenz ab t0.
- `/dev dome shatter` — nur die BlockDisplay-Scherben-Show (FX-Iteration).
- `/dev dome reset` — Zustand auf ACTIVE zurück: Gerät respawnen, Zone neu, Scherben-
  Sweep, Nachbeben-Schedule löschen.
- Sichtprüfung Innen-Effekt ohne Welt: bestehendes `/dev glitch test dome [s]`
  funktioniert automatisch, sobald `dome` in `GlitchZoneEffects.IDS` steht.

---

## 11. Datei-für-Datei-Checkliste

**Neue Java-Dateien (Server, `src/main/java/dev/projecteclipse/eclipse/…`):**

1. `mansiondome/MansionDomeState.java` — SavedData (§3.1)
2. `mansiondome/MansionDomeService.java` — Lifecycle/Tick/Sync (§3.2)
3. `mansiondome/DomeEmitterEntity.java` — GeckoLib-Gerät (§3.3)
4. `mansiondome/MansionDomeProtection.java` — Break/Place/Explosion (§3.4)
5. `mansiondome/DomeShatterFx.java` — BlockDisplay-Choreografie (§3.7)
6. `mansiondome/package-info.java` — Paket-Doc (Haus-Stil)
7. `network/fx/S2CMansionDomePayload.java` (§3.6)
8. `devtools/dev/DevMansionDomeCommands.java` (§10)

**Neue Java-Dateien (Client):**

9. `client/mansiondome/MansionDomeClient.java` — Payload-Cache, Post-Row `dome_shell`,
   Loop-Fenster, Inside/Outside (§4.1/4.3b)
10. `client/mansiondome/DomeShellRenderer.java` (§4.2)
11. `client/mansiondome/DomeBeamRenderer.java` (§4.5)
12. `client/mansiondome/package-info.java`
13. `client/entity/DomeEmitterRenderer.java` (§4.6)
14. `veilfx/MansionDomeFxRows.java` — Photon-Rows (§4.4)

**Geänderte Java-Dateien (jeweils minimal-invasiv, 1–5 Zeilen):**

15. `glitchzone/GlitchZoneEffects.java` — `DOME = "dome"` + `IDS`-Eintrag
16. `network/fx/FxCues.java` — 4 neue `CUE_*`-Konstanten
17. `network/EclipsePayloads.java` — `playToClient(S2CMansionDomePayload…)`
18. `entity/EclipseEntities.java` — `GLITCH_EMITTER`-Registrierung + Attribute
19. `client/entity/EclipseEntityRenderers.java` — Renderer-Zeile
20. `worldgen/structure/VanillaLandmarks.java` — kleine öffentliche Fassade
    `landmarkAnchor(ServerLevel, String)` (§2.2; einzige Alternative: Sichtbarkeiten in
    `StructureStamper` öffnen — Fassade ist sauberer)
21. Client-Setup-Klasse (`client/EclipseClient.java`): Aufruf
    `MansionDomeFxRows.register()` im `FMLClientSetupEvent` neben den bestehenden
    Registraren; Classload-Anker für `MansionDomeClient`
22. Lang-Dateien (`assets/eclipse/lang/en_us.json`, `de_de.json`) —
    `message.eclipse.dome_protected`, `entity.eclipse.glitch_emitter`

**Neue Assets:**

23. `assets/eclipse/pinwheel/post/glitch_dome.json`
24. `assets/eclipse/pinwheel/shaders/program/glitch_dome.fsh` + `.json`
25. `assets/eclipse/pinwheel/post/dome_shell.json`
26. `assets/eclipse/pinwheel/shaders/program/dome_shell.fsh` + `.json`
27. `assets/eclipse/geo/entity/glitch_emitter.geo.json` (§7)
28. `assets/eclipse/animations/entity/glitch_emitter.animation.json` (§7)
29. `assets/eclipse/textures/entity/glitch_emitter.png` + `glitch_emitter_glowmask.png`
    (128×128)
30. `assets/eclipse/fx/dome_device_idle.fx` + `.fxproj`, `dome_beam_base.fx` + `.fxproj`,
    `dome_device_hit.fx` + `.fxproj`, `dome_shatter_burst.fx` + `.fxproj`
31. `tools/photon/mansion_dome_fx.py` — Generator (fxlib, §4.4)

**Tests/Verifikation (Implementierer):** `./gradlew build`; Dedicated-Server-Smoke
(`/dev dome arm here 40`, `hits 1`, schlagen, `destroy`, Restart-Resume prüfen);
Client-Sichtprüfung Innen/Außen/Iris-an/reducedFx/`veilPostFx off`.

---

## 12. Risiken / Fallstricke

1. **Post-Budget & Compositor-Interplay (TOP)**: `MAX_CONCURRENT = 3` in
   `VeilPostController`; `glitch_dome` (TRANSITION) + `world_grade` (GRADE) + ein
   Storm-Pass können kollidieren. Entschärft durch Innen/Außen-Exklusivität und die
   Prioritäts-Bänder; TESTEN: Spieler in der Blase während eines C8-Sturms in Sichtweite.
2. **Blickdichtheit unter allen Render-Pfaden (TOP)**: Die Garantie "man sieht nicht
   hinein" darf NIE am Veil-Post hängen (Iris-Gate, `veilPostFx off`, Budget-Eviction,
   Failure-Fuse). Deshalb ist die CPU-Hülle opak + depth-schreibend die Baseline;
   Sodium/Embeddium-Sortierung kann Stage-Tausch erfordern (dokumentierter Fallback wie
   beim SupplyBeam). Translucente Blöcke VOR der Hülle (Wasser) sind der Härtetest.
3. **GLITCHZONE-Integration (TOP)**: (a) Die "permanente" Zone braucht ein
   End-Sentinel (`Long.MAX_VALUE/2`), das `removeExpired`/`temporalStrength` sicher
   übersteht; (b) `/dev glitch clear` killt die Dome-Zone → Selbstheilung im
   Service-Tick ist Pflicht; (c) "best zone wins": eine stärkere Dev-Zone im selben
   Bereich verdrängt den Dome-Effekt (akzeptiert — Operatoren-Werkzeug); (d) Saves, die
   mit diesem Build angefasst und dann OHNE das Feature geladen werden, droppen die
   `dome`-Zone still (Load-Validierung in `GlitchZoneState` — dokumentiertes Verhalten).
4. **Anchor-/Dach-Probing & Restart-Reconcile (TOP)**: Heightmap-Probe muss NACH
   `SitePrep.finish` laufen (sonst Prä-Plateau-Höhen); im ServerStarted-Fall Chunks
   einmalig synchron laden; Gerät-Respawn nur mit geladener Entity-Section
   (Deckhand-Bug-4a-Lehre) — sonst Duplikate.
5. **BlockDisplay-Sichtbarkeit/Budget in der Shatter-Show (TOP)**: Ohne
   `view_range`-Override (Displays rendern `view_range × 64` Blöcke um die
   ENTITY-Position) und ohne Fixed-Mount am Zentrum ist die Show ab 64 Blöcken
   unsichtbar bzw. verliert Stücke an Chunk-Unloads — beide Gesetze aus
   `StormDebrisFx` übernehmen; Tag-Sweep gegen Crash-Streuner.
6. **Shader-Merge `glitch_dome`**: Outline braucht `DiffuseDepthSampler` +
   `veil:space_helper`; Scanline-Verschiebungen (Hold-Jitter/Roll-Bar) verschieben UVs —
   die Depth-Taps müssen auf den UNVERSCHOBENEN UVs bleiben, sonst wandern die Kanten
   gegen die Geometrie. Reihenfolge im Shader: erst Outline-Readout bauen, dann
   Scanline-Layer auf das Readout anwenden.
7. **`GENERIC_EXPLODE` ist in 1.21.1 `Holder<SoundEvent>`** (`.value()` nötig) — kleiner,
   aber beliebter Compile-Stolperstein.
8. **Payload-Additivität**: Neuer Eintrag im Registrar "3" ist additiv; KEIN
   Versions-Bump (der ist nur für inkompatible Codec-Änderungen — Klassen-Doc
   `EclipsePayloads`).
9. **`dome_shell`-Kosten am Rand**: Kamera direkt an der Hülle = Near-Fullscreen-Pass;
   analytischer Shell-Hit (kein March-Loop) hält das billig — KEINEN fBm-Raymarch aus
   `storm_volume.fsh` kopieren.
10. **Protection-Wechselwirkung**: `LandmarkProtection` kennt die Mansion NICHT (nur
    Breach/Arrival/Observatory) — keine Doppel-Cancels; DevMode-Ausnahme konsistent
    halten (PROGFIX #5).
11. **Photon-Loops**: Loop-Rows dürfen NIE payload-gefeuert werden (WINDOWED-Gesetz,
    einmal-WARN in `PhotonFxRegistry.dispatch`) — Idle/Beam-Loops ausschließlich über den
    Fenster-Controller.
12. **Mansion-Fallback**: `minecraft:mansion` hat KEINEN prozeduralen Fallback-Builder —
    schlägt die Vanilla-Generierung mehrfach fehl, bleibt die Site pending und der Dome
    armiert nie. Der Service darf sich also NICHT auf "Stage 4 committed ⇒ Mansion
    existiert" verlassen, nur auf `Phase.PLACED`/`wasPlaced`.
