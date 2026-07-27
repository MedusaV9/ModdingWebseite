# WOAH-01 MANSION GLITCH DOME — Verdrahtung / geteilte Dateien (für den Hauptagenten)

Feature-Code lebt komplett in `dev.projecteclipse.eclipse.woah.mansiondome` (+ `…client`),
Dev-Commands in `devtools/dev/DevMansionDomeCommands`. Dieses Dokument listet (a) die
minimal-additiven Berührungen geteilter Dateien und (b) die offenen Merge-Punkte.

## A. Geteilte Dateien — was geändert wurde (alles rein additiv, 0 Löschungen)

### 1. `woah/WoahFeatures.java` (sanktionierter Anker)

- Genau eine Zeile unter `// --- WOAH-01 mansion glitch dome: mod-bus registrations go
  here ---`: `dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeEntities
  .register(modEventBus);` (DeferredRegister für die `glitch_emitter`-Entity +
  `EntityAttributeCreationEvent`).

### 2. `glitchzone/GlitchZoneEffects.java`

- Neue Konstante `public static final String DOME = "dome";` + Aufnahme in die
  `IDS`-Liste (ans Ende, bestehende Reihenfolge unverändert). Dadurch registriert
  `client/GlitchZoneFx` automatisch die TRANSITION-Post-Row `eclipse:glitch_dome`
  (Pipeline-Asset liegt bei) und `/dev glitch test dome [s]` funktioniert ohne
  weiteren Code. Frisch gelesen unmittelbar vor dem Edit; keine anderen Zeilen berührt.

### 3. `worldgen/structure/VanillaLandmarks.java`

- Neue öffentliche Fassade `public static BlockPos landmarkAnchor(DiscProfile,
  String landmarkId)` (delegiert an die package-privaten `StructureStamper.findLandmark`
  + `surfaceAnchor`). Grund: `MansionDomeService`/`DevMansionDomeCommands` brauchen den
  Mansion-Anker aus einem fremden Package; die bestehenden Methoden bleiben
  package-privat. Rein additiv am Klassenende.

### NICHT angefasst (bewusst)

- `network/fx/FxCues.java` — Cue-IDs entstehen in `woah/mansiondome/DomeCues` über das
  öffentliche `FxCues.cue("woah_dome_…")`.
- `network/EclipsePayloads.java` — `S2CMansionDomePayload` registriert sich über einen
  EIGENEN `RegisterPayloadHandlersEvent`-Subscriber in `MansionDomePayloads`
  (v1-Gruppe `v1woahdome`; das `EchoGrovePayloads`-Muster).
- `EclipseMod.java`, `worldgen/DiscMapDefaults.java` (die Mansion-Landmark
  `eclipse:mansion` ist zentral bereits eingetragen), `assets/eclipse/lang/*.json`,
  `assets/eclipse/sounds.json` — unberührt.

## B. Offene Merge-Punkte

1. **Langdrop**: `docs/plans_v3/langdrop/woah_dome.json` (21 Keys en+de: Entity-Name,
   Protection-Actionbar, 6 DevCommandDoc-Beschreibungen, 13 Dev-Feedback-Keys) muss in
   `assets/eclipse/lang/en_us.json` / `de_de.json` gemerged werden. Bis dahin rendern
   die Keys roh — kein Crash.
2. **Sounds**: KEIN Sounds-Ask nötig — es werden ausschließlich Bestands-Events
   verwendet (`EclipseSounds.AMBIENT_STORM_DOME_DRONE` / `EVENT_BORDER_GLITCH` /
   `EVENT_STORM_FLICKER` / `EVENT_STORM_SHATTER` + Vanilla `AMETHYST_BLOCK_CHIME`,
   `IRON_GOLEM_HURT`, `ANVIL_LAND`, `GENERIC_EXPLODE.value()`, `PLAYER_LEVELUP`).
3. **Zentraler Build**: kein `./gradlew` gelaufen (Regel). Compile-Korrektheit über
   einen isolierten `javac`-Lauf (alle 18 Feature-Dateien + transitive Repo-Deps gegen
   die NeoForge-21.1.238-/GeckoLib-4.9.2-/Veil-4.3.0-Cache-Jars, authlib 6.0.54) —
   0 Fehler; `.class`-Output für alle Klassen inkl. der drei geteilten Dateien geprüft.

## C. Selbstregistrierende Einstiegspunkte (nichts zu verdrahten, nur zur Übersicht)

| Klasse | Bus/Event | Rolle |
|---|---|---|
| `MansionDomeService` | GAME `@EventBusSubscriber` (ServerStarted/ServerTick + `StructurePendingRegistry`-Listener) | Arm bei Mansion-PLACED, Lifecycle-Ticks, Beat-Replayer, Aftershocks |
| `MansionDomeProtection` | GAME `@EventBusSubscriber` (Break/Place/ExplosionDetonate) | Block-Schutzzylinder solange ACTIVE/COLLAPSING |
| `MansionDomePayloads` | MOD `RegisterPayloadHandlersEvent` + GAME Login/Dimension-Change | `S2CMansionDomePayload` v1-Gruppe `v1woahdome` |
| `MansionDomeEntities` | MOD via `WoahFeatures`-Anker | `eclipse:glitch_emitter` EntityType + Attribute |
| `DevMansionDomeCommands` | GAME `RegisterCommandsEvent` (+ DevCommandDoc im `static{}`) | `/dev dome status/arm[ here [r]]/hits/destroy/shatter/reset` |
| `client.MansionDomeClient` | MOD `FMLClientSetupEvent`-frei (static init der Post-Row) + GAME ClientTick/Logout/Clone | Snapshot-Cache, `eclipse:dome_shell`-Row + Feeder, 48-Block-Loop-Fenster, Drone-Loop |
| `client.MansionDomeFxRows` | MOD `FMLClientSetupEvent` | 4 Photon-Rows (2 BURST-Legs, 2 WINDOWED-Loops) |
| `client.DomeShellRenderer` / `client.DomeBeamRenderer` | GAME `RenderLevelStageEvent` | CPU-Hülle / 200-Block-Beam |
| `client.DomeEmitterRenderer.Registration` | MOD `EntityRenderersEvent.RegisterRenderers` | GeckoLib-Renderer (Glowmask, Schadens-Tint/Jitter) |
