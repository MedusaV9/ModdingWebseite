# PLAN-03 — CHRONO-STASE (Zeit-Anomalie)

**Feature 3 der Woah-Reihe.** Ein permanentes Map-Set-Piece in der Machart des volumetrischen
Sturms (FogStormSites-Pattern), aber mit einem völlig anderen Woah-Effekt: eine Lichtung, in
der die Zeit EINGEFROREN ist. Alle Klassennamen/Pfade unten sind gegen den Stand von
`cursor/project-eclipse` verifiziert; neue Klassen sind als **(NEU)** markiert.

Kern-Referenzen (gelesen, Muster übernommen):

- BlockDisplay-Choreographie & Gesetze: `worldgen/stage/ExpansionBorderFx.java`
  (VIEW_RANGE-/Tracking-Lektion, Ticket-Refresh, Stray-Sweep), `sequence/StormDebrisFx.java`
  (Achs-Mount, stateless Push, Budget-Slicing), `ritual/CreditsShatterAct.java`
  (Kulisse-Gesetz, SPAWN_PER_TICK=60, PUSH_STRIDE), `worldgen/structure/SanctumOrbitals.java`
  (persistente Displays + Identity-Tags + Reconcile + Keyframe-LEAD),
  `worldgen/stage/DisplayBrightnessFx.java` (Brightness + view_range in einem NBT-Roundtrip).
- Site-Placement: `worldgen/fog/FogStormSites.java` (Stage-Listener →
  `StructurePendingRegistry.enqueue` → async Placer → `SitePrep.preparePlateau`),
  `worldgen/DiscMapDefaults.java` (Landmark-Tabelle + Clearance-Regeln),
  `worldgen/StageRadii.java` (D8-Radien `{96,150,210,280,360,440}`).
- Veil-Grade: `client/xbox/XboxEraFx.java` (GRADE-Row, Ease, Uniform-Feeder) +
  `veilfx/VeilPostController.java` (≤3 Pass-Budget, Iris-Gate, Failure-Fuse) +
  `assets/eclipse/pinwheel/post/xbox_era.json` als Kopiervorlage.
- Photon: `docs/plans_v3/PHOTON_EDITOR_CAPABILITIES.md` (§2.2: `startSpeed`, Module;
  eingefrorene Partikel sind möglich — s. §4.3 unten), `tools/photon/fxlib.py`,
  `veilfx/PhotonBridge.java` (MAX_LIVE_EXECUTORS=24), `veilfx/PhotonFxRegistry.java`
  (Row-Dispatch), `network/fx/FxCues.java` / `network/fx/FxPayloads.java` (Cue-Lane),
  `client/xbox/EraDustMotes.java` + `stormfx/StormInteriorFx.java` (WINDOWED-Loop-Muster).
- Interaktion: `worldgen/structure/SkyLauncher.java` (`minecraft:interaction` via NBT,
  `PlayerInteractEvent.EntityInteract`, Tag-Gate).
- Zonen-FX-Sync: `veilfx/FxAnchors.java` (Server→Client Anker, FROZEN API, additiv erweiterbar),
  `client/GlitchZoneFx.java` (Ease/Idle-Skip-Muster).
- Persistenz: `progression/LandmarkDiscoveryService.java` (kleine eigene SavedData),
  `core/state/EclipseWorldgenState.java` (Ownership-Gesetz: eigene Datei statt Fremd-Schema).
- Dev-Commands: `devtools/dev/DevRoot.java` (Brigadier-Merge), `devtools/dev/DevXboxCommands.java`
  (eigener Subtree), `devtools/dev/DevCommandRegistry.java` + `DevCommandDoc`/`DevCategory`.

---

## 1. Konzept-Zusammenfassung + Fernwirkung

**Die Chrono-Stase** ist eine flache Senke im Birkenwald (Forest-Wedge, äußerer Ring), in der
ein einziger Augenblick für immer festhängt: Ein Blitzschlag steht als verästelte, leuchtende
Säule PERMANENT in der Luft. Daneben ist eine Explosion mitten im Detonieren erstarrt — ein
Feuerball aus radial hängenden Fragmenten, umgeben von reglosen Rauchballen. Über der ganzen
Lichtung hängen tausende glitzernde Regentropfen bewegungslos im Raum (sie fallen NICHT).
Ein halb eingestürzter Wachturm hängt mitten im Kollaps: Mauerwerksbrocken schweben in
Wurfparabeln, durch die man hindurchlaufen kann — eine begehbare explodierte
Zeitlupen-Szene mit Masse, Tiefe und Höhe. Vögel und Laub sind mitten in der Bewegung
erstarrt. Im Zentrum schwebt die **Chronosphäre** — ein Uhr-Artefakt aus drei langsam (fast
unmerklich) rotierenden Display-Ringen über einer gläsernen Sanduhr, deren Sandstrahl
mitten im Rinnen eingefroren ist.

Innen: entsättigtes, kühles Licht, leichte Vignette, feiner "Zeitstaub"-Schimmer, fast
vollständige Stille — nur ein einzelnes, tiefes Uhren-Ticken alle ~2 s, das zum Zentrum hin
LANGSAMER wird (die Zeit selbst wird zäher). Mobs und Projektile werden innen extrem
verlangsamt; die eigene Bewegung bleibt normal (man ist Beobachter, nicht Opfer).

**Interaktion:** Rechtsklick auf die Chronosphäre = **Zeit-Ruck** — für ~3 Sekunden ruckt die
gesamte Szene 1–2 Ticks weiter (jedes eingefrorene Objekt bewegt sich minimal, Photon-Puls,
tiefes Woom), dann friert alles wieder ein. Nach 5 Rucks entlädt sich die Szene einmal
spektakulär: der Blitz schlägt real ein, die Explosion detoniert zu Ende, der Regen fällt
schlagartig, die Turmtrümmer stürzen — und dann spult alles sichtbar in die Ausgangspose
ZURÜCK (der eigentliche Woah-Moment). Beim ersten Durchlauf gibt es eine Belohnung; danach
ist der Loop beliebig wiederholbar.

**Fernwirkung:** Der eingefrorene Blitz ragt ~55 Blöcke über die Baumkronen und trägt darüber
eine clientseitige, säulenartige Schimmer-Säule (Photon, vom `FxAnchors`-Anker getrieben, aus
bis zu ~600 Blöcken sichtbar — Display-Entities allein reichen dafür NICHT, ihr
Entity-Tracking endet bei 10 Chunks; die Lektion aus `ExpansionBorderFx` §"Why the v1
boulders were never seen").

---

## 2. Platzierung auf der Disc + Terraforming

### 2.1 Landmark-Eintrag

Neue Zeile in `worldgen/DiscMapDefaults.overworldDefaults()` (Landmark-Tabelle, damit die
Position pro Save via `FrozenParams`-Map-Snapshot eingefroren wird und Clearances
dokumentiert sind):

```
new DiscMapData.Landmark("eclipse:chrono_stasis", -24, 240, 26, 3)
```

Begründung gegen die dokumentierten D8-Placement-Regeln (Kommentarblock über
`overworldDefaults()`):

| Regel | Check |
|---|---|
| Stage-N-Site + Radius im Stage-N-Disc | r ≈ 241 + 26 = 267 < 280 (Stage-3-Radius) ✔ |
| Wedge | Winkel ≈ 95.7° → Forest-Wedge (67.5°–112.5°), 16.8° Abstand zu beiden Seams (>> ±5° Wobble) ✔ |
| Biom | r 241 im Forest-Wedge → `minecraft:birch_forest` (Ring 150–280) — lichte Birkenkulisse ✔ |
| Player-Disc-Ring (r=170, 8 Discs r=24) | |241−170| = 71 > 26+24 ✔ |
| Flüsse (>18 + Site-Radius = 44) | River 3 läuft über (38,115)/(62,215)/(65,320): minimale Segment-Distanz ≈ 87 ✔ |
| Andere Sites | jungle_temple (−173,173) ≈ 163 · trial_chambers (143,205) ≈ 171 · Berg (54,−129, Flanke ≤ ~171) ≈ 377 ✔ |

Der Forest-Wedge ist der einzige verbleibende Wedge ohne eigenes Set-Piece — die
Chrono-Stase füllt genau diese Lücke.

### 2.2 Materialisierung (FogStormSites-Pattern, 1:1)

- **(NEU)** `worldgen/chrono/ChronoStasisSite.java`: registriert sich in
  `ServerAboutToStartEvent` als `WorldStageService.addListener` UND als
  `StructurePendingRegistry.registerAsyncPlacer("eclipse:chrono_stasis", …)`.
  Beim Terrain-Complete von Stage 3 (`toStage >= 3 && fromStage < 3`) wird ein
  `StructurePendingRegistry.PendingSite` enqueued (siteId `eclipse:chrono_stasis`,
  Center aus dem Landmark der `DiscMapData`-Map, footprint = 52). Der Placer ruft
  `materialize(level, onComplete, onFailure)` — zweiphasig wie
  `FogStormSites.materializeSite`.
- **Stage-Rollback** (Dev-Erase, wie `FogStormSites.onStageTerrainComplete` mit
  `toStage <= fromStage`): Szene abbauen (Displays discarden, Anker entfernen,
  SavedData-Flags zurücksetzen).
- Öffentliche Konstanten (Client liest sie mit — single source set):
  `CENTER_X = -24`, `CENTER_Z = 240`, `RADIUS = 26` (Gameplay-/Grade-Radius),
  `FX_RADIUS = 34` (Photon-Regenfeld etwas größer, damit der Übergang weich ist).

### 2.3 Terraforming der Lichtung

Innerhalb von `materialize`, nach `SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
x−26, z−26, x+26, z+26, center)` und vor dem Szenen-Bau, ein budgetierter Carve über
`worldgen/stage/BudgetedBlockWriter.enqueue` (dieselbe Ausführungsschiene wie
`FogStormSites.carveGrove`):

- **Senke**: flache Schüssel, Tiefe 3 im Zentrum, Kosinus-Falloff bis r 24; Oberfläche im
  Kern `moss_block`/`coarse_dirt`/`podzol` gemischt (Hash pro Säule), außen normales Gras.
- **Rand**: stehen gelassene Birken; 6–8 Birken am Ring werden auf 2–4 Stammblöcke gekappt
  (abgebrochen), 2 davon liegen als kurze `birch_log`-Linien um den Kraterrand.
- **Wasser**: KEINS (eingefrorener Regen + Teich liest sich doppelt; bewusst weggelassen).
- **Turmfundament**: am Ost-Rand (lokal +14, −6) ein 6×6 Stumpf aus
  `stone_bricks`/`cracked_stone_bricks`/`cobblestone`, 4–7 hoch, oben unregelmäßig
  abgebrochen (echte Blöcke — nur die FLIEGENDEN Trümmer sind Displays; Kulisse-Gesetz:
  Displays verändern nie die Welt, aber ein Fundament ist Welt).
- **Relight/Resend**: `SitePrep.finish(level, prepared)` als Abschluss (wie FogStormSites).
- Danach: `FxAnchors.set(CHRONO_CENTER, level, Vec3)` (s. §4.1) und
  `LandmarkDiscoveryService`-Discovery bleibt dem normalen Näherungs-Flow überlassen.

---

## 3. Server-Systeme

### 3.1 Szenen-Bauer — **(NEU)** `worldgen/chrono/ChronoSceneBuilder.java`

Einmalige Konstruktion der eingefrorenen Szene aus `Display.BlockDisplay`-Entities.
Determinismus: `RandomSource.create(sceneSeed)` — der Seed wird beim ersten Bau gewürfelt
und in `ChronoStasisData` (§3.4) persistiert, damit Reconcile/Rebuild dieselbe Szene ergibt.

**Persistenz-Modell = `SanctumOrbitals`, nicht `ExpansionBorderFx`:** die Displays sind
PERSISTENT (mit dem Chunk gespeichert), tragen den Sammel-Tag `eclipse_chrono_prop` plus
einen Identity-Tag `eclipse_chrono_<gruppe>_<index>` (z. B. `eclipse_chrono_bolt_017`).
Ein Reconcile-Pass (beim Boot sobald `ServerLevel.areEntitiesLoaded` für den Site-AABB wahr
ist, danach alle ~2 min solange Spieler in 96 Blöcken) adoptiert pro Identity-Tag genau ein
Display, discardet Duplikate/Streuner und respawnt Fehlendes — `/kill
@e[tag=eclipse_chrono_prop]` heilt sich selbst. KEIN Boot-Discard-Sweep wie bei den
temporären FX-Klassen (das würde die Szene jede Session neu bauen).

**Wichtige Display-Gesetze** (aus den gelesenen Referenzen, alle anwenden):

- Jedes Display bekommt `DisplayBrightnessFx.set(display, 7, 15, VIEW_RANGE)` — Blitz- und
  Sphären-Teile `15/15` (selbstleuchtend), Trümmer `7/15`.
- `VIEW_RANGE = 4.0F` (256 Blöcke) für alles; die 160-Block-Tracking-Grenze bleibt der
  harte Deckel — Fernwirkung übernimmt §4.5.
- Entity-Position = Ankerpunkt der GRUPPE (Blitzfuß, Explosionszentrum, Turmzentrum,
  Sphärenzentrum), alle Bewegung lebt in der Transformation (StormDebrisFx-Transport:
  Licht-Sample in freier Luft, eine Handvoll Chunks besitzt alles).
- Spawn-Budget beim Erstbau/Rebuild: **60 Displays/Tick** (CreditsShatterAct-Wert), also
  ~9 Ticks für die Vollszene.

**Umfang (Ziel: ~520 Displays, fest gedeckelt bei 600):** Details in §5.

### 3.2 Slowness-Aura — Teil von **(NEU)** `worldgen/chrono/ChronoStasisService.java`

- Tick-Gate: Early-out, wenn kein Spieler in 96 Blöcken um das Zentrum (Server-Tick-Handler
  wie `ExpansionBorderFx.onServerTick`, ein `@EventBusSubscriber` auf
  `ServerTickEvent.Post`).
- **Mobs** (alle 10 Ticks): `level.getEntitiesOfClass(LivingEntity.class, AABB(center±RADIUS,
  y±20))`, Spieler ausgenommen → `MobEffects.MOVEMENT_SLOWDOWN` Amplifier 4, Dauer 40 t,
  `ambient=true`, `showParticles=false` (re-applied bevor es ausläuft → nahtlos; kein
  Attribut-Modifier nötig, weil der Effekt beim Verlassen von selbst ausläuft — genau der
  Grund, warum MobEffect hier besser passt als ein Attribute).
  Zusätzlich `MobEffects.DIG_SLOWDOWN` Amplifier 2 (gegen "schnelle" Angriffsanimationen
  liest sich das träger; rein kosmetisch-mechanischer Bonus).
- **Projektile** (jeden Tick, Liste ist praktisch immer leer):
  `level.getEntitiesOfClass(Projectile.class, aabb)` → `setDeltaMovement(delta.scale(0.5))`
  pro Tick solange drin (asymptotisches "Einfrieren"; kein Zurücksetzen beim Austritt —
  ein Pfeil, der hineinfliegt, bleibt fast stehen und trudelt zäh weiter). Kein
  No-Gravity-Flag (sonst leaken schwebende Pfeile, wenn der Server mitten drin stoppt).
- Spieler bleiben unberührt (Ziel-Erlebnis).

### 3.3 Zeit-Ruck-Statemachine — ebenfalls `ChronoStasisService`

Zustände (enum, in-memory; Persistenz nur für Zähler/Claim in §3.4):

```
FROZEN  --Rechtsklick-->  JOLT (60 t)  --> FROZEN   [joltCount++]
FROZEN  --Rechtsklick bei joltCount>=5-->  DISCHARGE (200 t)  --> REWIND (60 t) --> FROZEN [joltCount=0]
```

- **Interaktion:** ein `minecraft:interaction`-Entity (width 2.8, height 2.8,
  `response=false`) am Sphärenzentrum, gespawnt über das NBT-Muster von
  `SkyLauncher.spawnPadInteraction`, Tag `eclipse_chrono_sphere_pad` (persistent, vom
  Reconcile mitverwaltet). Handler: `PlayerInteractEvent.EntityInteract`, nur MAIN_HAND,
  kein Spectator, Event canceln (SkyLauncher-Vorbild). Klicks während JOLT/DISCHARGE/REWIND
  werden ignoriert (Re-Klick-Schutz wie `SkyLauncher.beginCharge`).
- **JOLT (der Zeit-Ruck, 60 t):**
  - t=0: `EclipseSounds.EVENT_CHRONO_WOOM` am Zentrum + `S2CShakePayload.shake(0.18F, 14)`
    an alle Spieler in 128 Blöcken (`PacketDistributor.sendToPlayersNear`) +
    `FxPayloads.sendFxEvent(level, FxCues.CUE_CHRONO_JOLT, sphereCenter, joltCount, 0, 96)`.
  - t=0..12: JEDE Szenengruppe pusht EINE neue Pose = "Szenenzeit + 2 Ticks" mit
    `setTransformationInterpolationDelay(0)` / `Duration(12)` — die ganze Szene gleitet
    sichtbar ein winziges Stück weiter (Blitzäste zucken 0.2–0.5 Blöcke, Explosionsfragmente
    wandern 2 % weiter nach außen, Turmbrocken sinken 0.1–0.3, Vögel flattern einen Frame).
    Push-Slicing: max. **80 Display-Pushes/Tick** (~7 Ticks für die Vollszene) — dieselbe
    Phasen-Slicing-Idee wie `StormDebrisFx` §Budget.
  - t=40..60: identischer Rück-Push zur alten Pose mit `Duration(20)` (das "Wieder-
    Einfrieren" — bewusst langsamer als der Ruck, liest sich wie zähes Zurücksacken).
  - Die "Szenenzeit" ist ein einziger int `sceneTick` (0 = Grundpose). Jede Gruppe
    definiert ihre Pose als reine Funktion `poseOf(index, sceneTick)` (stateless-push law) —
    JOLT setzt `sceneTick += 2` und wieder zurück.
- **DISCHARGE (200 t), die Auflösung:**
  - t=0: Hush-Beat — Caption (`S2CCaptionPayload`, STYLE_WHISPER,
    `eclipse.caption.chrono.discharge`), Sphären-Ringe beschleunigen (Pose-Pushes der
    Sphärengruppe auf 2-Tick-Kadenz für die Dauer).
  - t=20: **Blitz entlädt sich**: `LightningBolt` mit `setVisualOnly(true)` am Blitzfuß
    (vanilla Flash + Donner, kein Feuer/Schaden), gleichzeitig skalieren die Blitz-Displays
    über 6 t auf 0 (er "fährt in den Boden"). Sound `EVENT_CHRONO_DISCHARGE`.
  - t=30: **Explosion detoniert zu Ende**: Fragment-Gruppe fliegt über 30 t radial auseinander
    (Pose-Translation ×4, Scale→0 am Ende), Rauchballen steigen und verblassen;
    `FxCues.CUE_CHRONO_DISCHARGE` (Photon-Burst §4.3) + `EclipseSounds.EVENT_STORM_BURST`
    (existiert schon, pitcht gut) + Shake 0.35/22. KEIN `level.explode` — Kulisse-Gesetz.
  - t=30..100: **Regen fällt schlagartig**: rein clientseitig (§4.3/§4.4) — das
    Frozen-Rain-Feld wechselt für ~4 s in eine Fall-Variante, dann Fade auf 0.
  - t=40..120: **Turm kollabiert real**: Trümmer-Posen folgen einer ballistischen Kurve bis
    Bodenhöhe (Pose-Funktion mit `sceneTick`-Fortschreibung), Aufschlag-Puffs via
    `CUE_CHRONO_JOLT`-Reuse mit `a`=2 (Client mappt auf Staub-Variante).
  - t=120..200: Nachhall — nur Grade + Ticken setzen aus (Client, §4), Szene liegt "fertig".
  - **Belohnung** (einmalig, §7) feuert bei t=120.
- **REWIND (60 t):** alle Gruppen-Posen werden mit `Duration(40)` zurück auf
  `sceneTick=0` gepusht — sichtbares Zurückspulen (Trümmer heben ab, der Feuerball saugt
  sich zusammen, die Blitz-Displays wachsen wieder aus dem Boden); die Blitz-Gruppe
  re-spawnt, falls Scale-0-Displays discarded wurden (bewusst NICHT discarden — nur Scale 0,
  dann ist der Rewind ein reiner Pose-Push ohne Entity-Kosten). Danach `joltCount = 0`.
- **Watchdog:** hängt DISCHARGE/REWIND > 600 t (Server-Neustart mitten drin), setzt der
  nächste Reconcile-Pass hart auf FROZEN-Grundpose (Pose-Funktionen sind stateless —
  ein einziger Push heilt alles).

### 3.4 SavedData — **(NEU)** `worldgen/chrono/ChronoStasisData.java`

Eigene Datei `data/eclipse_chrono_stasis.dat` im Overworld-Storage (Ownership-Gesetz von
`EclipseWorldgenState`; Muster: `LandmarkDiscoveryService.Data` — kleine SavedData-Klasse
mit `get(MinecraftServer)`):

| Feld | Typ | Zweck |
|---|---|---|
| `placed` | boolean | Site materialisiert (Restart-Resync, wie FogSiteState) |
| `sceneSeed` | long | deterministischer Rebuild/Reconcile |
| `joltCount` | int | Rucks seit letzter Entladung (übersteht Restart) |
| `discharges` | int | Statistik + Gate für „Belohnung nur beim 1. Mal" |
| `rewardClaimed` | boolean | Belohnungs-Gate |

### 3.5 Tick-Budget (Server)

| Posten | Kosten |
|---|---|
| FROZEN, Spieler da | Aura-Scan alle 10 t (1 AABB-Query) + Projektil-Query 1/t + Ticken ist CLIENT |
| FROZEN, niemand in 96 Blöcken | **0** (Early-out; Displays sind statisch, 0 Pakete) |
| JOLT | 2 Push-Wellen à ~520 Displays, gesliced ≤80/t → ≤80 Entity-Data-Pakete/t für ~13 t |
| DISCHARGE/REWIND | Pushes nur für bewegte Gruppen (~340 Displays), 10-t-Kadenz, gesliced — Peak ≈ 34 Pakete/t |
| Reconcile | Tag-Scan im Site-AABB alle ~2 400 t, nur bei Spielernähe |

Keine Chunk-Tickets nötig: die Szene ist persistent und existiert nur, wenn ihre Chunks
ohnehin geladen sind (anders als die temporären Rim-Boulders).

---

## 4. Client-Systeme

Alle Klassen unter `client/chrono/` **(NEU, Package)**, alle `@EventBusSubscriber(value =
Dist.CLIENT)`; Verdrahtung per static-init wie `XboxEraFx`/`GlitchZoneFx` (kein Registrar-Call
nötig, die Subscriber-Annotation lädt die Klasse).

### 4.1 Zonen-Zustand (Anker statt Payload)

- `veilfx/FxAnchors.java`: neue frozen id `CHRONO_CENTER` (`eclipse:chrono_center`),
  gesetzt von `ChronoStasisSite.materialize` und beim Server-Start-Restore
  (`placed==true`), entfernt beim Stage-Rollback. Anker-Sync an Join ist im FxAnchors-Code
  schon eingebaut — es braucht KEINE neue Payload für die Zone.
- **(NEU)** `client/chrono/ChronoZoneState.java`: pro Client-Tick Distanz Kamera↔Anker,
  eased `inside`-Wert 0..1 (Ramp über die letzten 12 Blöcke vor `RADIUS`, Ease-Muster von
  `GlitchZoneFx`: EASE_RATE 0.18, SNAP, MIN_ACTIVE 0.01). Discharge-/Jolt-Phase kommt als
  Cue an (unten) und wird hier als kurzlebiger Client-Timer gehalten.

### 4.2 Zonen-Grade (Veil-Post)

- Assets: `assets/eclipse/pinwheel/post/chrono_grade.json` + Shader unter
  `assets/eclipse/pinwheel/shaders/` (Kopiervorlage: `post/xbox_era.json` + zugehöriger
  `.fsh` — GRADE-Pass mit Fullscreen-Blit).
- Uniforms: `Amount` (eased inside), `Tint` = (0.82, 0.90, 1.10) kühler Blaustich,
  `Saturation` = 0.55 (Ziel-Sättigungsfaktor), `Contrast` = 1.03, `Vignette` = 1.3,
  `Time` (Zeitstaub: ein sehr feines, additives Glitzer-Rauschen im Shader, Amplitude an
  `Amount` gekoppelt — Analogie: `xbox_era.fsh`-Scanband, aber als Sternchen-Hash).
- **(NEU)** `client/chrono/ChronoGradeFx.java`: registriert die Row per static-init —
  `VeilPostController.register(new PipelineSpec(CHRONO_GRADE_POST, PipelinePriority.GRADE,
  want, feed))`; `want` = `ChronoZoneState.amount() > MIN_ACTIVE` (+`reducedFx()`-Gate wie
  XboxEraFx); Feeder allokationsfrei. Iris-Gate/3-Pass-Budget/Fuse erbt der Controller.
  Während DISCHARGE t=20 (Blitz) hebt der Feeder `Amount` kurz an (Weiß-Kick über einen
  vorhandenen Uniform-Puls, kein zweiter Pass).

### 4.3 Eingefrorene Regen-Partikel (Photon) — Asset-Spezifikation

Photon KANN eingefrorene Partikel (verifiziert gegen `PHOTON_EDITOR_CAPABILITIES.md` §2.2):
`startSpeed = 0`, KEIN `velocityOverLifetime`/`forceOverLifetime`/`noise`, `physics` aus,
`simulationSpace = World` → Partikel bleiben exakt an ihrem Spawnpunkt stehen. Molang gibt
es nicht (§2.6) und wird nicht gebraucht.

Neuer Generator **(NEU)** `tools/photon/chrono_fx.py` (fxlib-Pipeline; `.fx` + `.fxproj`
nach `assets/eclipse/fx/`, danach `python3 tools/photon/fxlib.py validate --lint`):

| Asset | Spec |
|---|---|
| `chrono_rain_frozen.fx` | Loop. 3 Emitter-Boxen (Volumen ~24×18×24), `simulationSpace World`, Rate ~40/s + `startLifetime` 8 s (random 6–10), `startSpeed 0`, `startSize3D` (0.03, 0.28, 0.03) — vertikal gestreckte Tropfen via Größe (NICHT StretchedBillboard: das streckt entlang Velocity, und Velocity ist 0 — RenderMode `VerticalBillboard`), `colorOverLifetime` mit 0.4-s-Alpha-Fade an beiden Enden (unsichtbarer Turnover), leichtes HDR (~1.3) für Glitzern, `lights` sky 12, `useGPUInstance = true`, `maxParticles 320`/Emitter (≈960 gesamt), CullBox, `prewarm = true` (Feld steht sofort voll). |
| `chrono_dust_shimmer.fx` | Loop. Zeitstaub: dot-Sphere um die Kamera, 60 maxParticles, Größe 0.02–0.05, `startSpeed 0`, langsames `sizeOverLifetime`-Pulsieren, HDR 1.6. |
| `chrono_sphere_idle.fx` | Loop, WINDOWED. Corona der Chronosphäre: `circle`-Shape, `ShapeArcMode Loop` + arcSpeed (orbitierende Emissionspunkte), ara-frei, 48 maxParticles, HDR 2.0. |
| `chrono_bolt_glow.fx` | Loop, WINDOWED. Zylinder-Shape (r 0.8, h 40) am Blitzfuß, 90 maxParticles, `startSpeed 0`, weiß-blaues HDR-Glimmen entlang der Säule. |
| `chrono_jolt_pulse.fx` | One-shot (Burst): expandierender Horizontal-Ring + 30 Funken mit kurzen Trails; Variante `a=2` (vom Row-Mapping skaliert) als Staub-Puff für Turm-Aufschläge. |
| `chrono_discharge_burst.fx` | One-shot: Shockwave-Ring (Multi-Material: additiver HDR-Kern + Alpha-Rauchrand, Vorbild `shadow_bolt_impact.fx`), Ember-Jets radial, `subEmitters FirstCollision` → Boden-Puffs. |
| `chrono_rain_release.fx` | One-shot, 4 s: identische Box-Volumina, aber `startSpeed` 14 nach unten + `physics` (removedWhenCollided) — „der Regen fällt schlagartig". |
| `chrono_far_pillar.fx` | Loop, WINDOWED (Fern-Tell §4.5): schmale vertikale Säule (Box 2×60×2), 40 maxParticles, `startSpeed 0`, HDR 1.8, große CullBox. |

Loop-Fenster-Treiber **(NEU)** `client/chrono/ChronoRainField.java`: das
`EraDustMotes`/`StormInteriorFx`-WINDOWED-Muster — solange `ChronoZoneState.amount() > 0`
und `!EclipseClientConfig.reducedFx()` hält er 1–3 `PhotonBridge`-Loop-Handles
(Regen-Emitter auf einem 2×2-Gitter um die Kamera geclampt auf den Site-Kreis, Turnover wie
`StormInteriorFx.tickRainSheets`), + je einen Handle für `chrono_dust_shimmer`,
`chrono_sphere_idle`, `chrono_bolt_glow` (Positionen: Anker + feste lokale Offsets aus den
`ChronoStasisSite`-Konstanten). Release bei Fensterschluss/reducedFx/Disconnect
(Loop-Gesetz). Budget: ≤6 gleichzeitige Executor-Handles von `MAX_LIVE_EXECUTORS = 24`.
Während DISCHARGE t=30..110 ersetzt der Cue-Handler das Frozen-Feld durch EINEN
`chrono_rain_release`-Shot pro Emitter-Position und lässt das Loop-Fenster 5 s geschlossen.

Cue-Rows: **(NEU)** `veilfx/ChronoStasisFxRows.java` (Client-Registrar-Pattern aus dem
`FxCues`-Kopfkommentar) — Rows für `CUE_CHRONO_JOLT` (a=1 Puls / a=2 Staub-Puff) und
`CUE_CHRONO_DISCHARGE`; dazu die zwei neuen Konstanten in `network/fx/FxCues.java`.

### 4.4 Regen-Unterdrückung im Radius (Mixin)

Es existiert bereits `client/mixin/LevelRendererMixin.java` (cancelt
`renderWorldBorder`) in `eclipse.client.mixins.json` — dort zwei zusätzliche Injections
(kein neuer Mixin-Config-Eintrag nötig):

- `renderSnowAndRain` HEAD, cancellable: cancel, wenn
  `ChronoZoneState.suppressVanillaRain()` (= inside-Amount > 0.6 und nicht in
  DISCHARGE-Regenphase) — vanilla Regen-Streifen verschwinden, die eingefrorenen
  Photon-Tropfen ERSETZEN ihn.
- `tickRain` HEAD, cancellable: cancel unter derselben Bedingung (unterdrückt
  Splash-Partikel + Regen-Sounds am Boden).

Grenzfall bewusst simpel: die Unterdrückung ist ganz-oder-gar-nicht ab 0.6 — am Rand
überlappen echte und eingefrorene Tropfen für ~5 Blöcke, das liest sich als Übergang.

### 4.5 Fern-Tell

`ChronoRainField` hält zusätzlich ein Fern-Fenster: Kamera-Distanz zum Anker zwischen 96
und 640 → ein `chrono_far_pillar`-Loop am Anker (Photon-Partikel rendern distanzunabhängig,
weil der Executor client-seitig lebt — im Gegensatz zu den Display-Entities mit ihrer
160-Block-Tracking-Grenze). Unter 96 Blöcken übernimmt die echte Blitz-Geometrie, das
Fenster schließt.

### 4.6 Ticken-Sound — **(NEU)** `client/chrono/ChronoTickSound.java`

- Client-Tick: wenn `ChronoZoneState.amount() > 0.05`, Countdown; Periode =
  `lerp(distanceRatio, 60 t, 34 t)` — **am Zentrum 3 s, am Rand 1.7 s** („näher am Zentrum
  langsamer"). Bei Ablauf `level.playLocalSound(center…, EclipseSounds.EVENT_CHRONO_TICK,
  AMBIENT, vol = 0.4 + 0.5*amount, pitch = 0.9 − 0.25*amount, false)`.
- „Dumpf, fast stumm": kein echter Lowpass verfügbar — der Eindruck entsteht durch (a)
  `tickRain`-Cancel (keine Regen-/Splash-Sounds), (b) das Ticken als fast einzige
  Klangquelle, (c) Pitch-Absenkung zum Zentrum. Precedent für „Stille als Inszenierung":
  `client/drama/LastMinuteHush.java`.
- Während JOLT setzt das Ticken 60 t aus (der Woom ersetzt den Schlag), während
  DISCHARGE/REWIND komplett.

---

## 5. BlockDisplay-Szenen-Layout (Paletten + Transformationen)

Alle Posen als Funktion `poseOf(gruppe, index, sceneTick)`; Grundpose = `sceneTick 0`.
Slab-Konstruktion (per-Achse skalierte Boxen, zentriert um den Offset rotiert) exakt nach
dem `ExpansionBorderFx.poseOf`-Rezept (half-Vector-Zentrierung!).

### 5.1 Eingefrorener Blitz (~55 Displays) — Gruppe `bolt`, Anker: Blitzfuß (lokal −6, +2)

- **Geometrie**: Hauptstamm = Polyline von y+0 bis y+55 aus 16 Segmenten; jedes Segment eine
  dünne gestreckte Box (Größe 0.35–0.7 × 3.2–4.2 × 0.35–0.7), Knickwinkel pro Gelenk
  ±8–22° um Y und ±5–12° aus der Vertikalen (Zickzack, deterministisch aus dem Seed);
  Segment-Quaternion = Ausrichtung Fuß→Kopf des Segments (rotateTo-Konstruktion), Offset =
  Segment-Mittelpunkt. 3 Hauptäste bei y+18/y+30/y+42 (je 4–6 kürzere Segmente, 40–70° vom
  Stamm), 4 Zweig-Spitzen (je 2 Segmente, Girth 0.2).
- **Palette (Schichtung pro Segment, 2 Displays)**: Kern `white_stained_glass` in voller
  Segmentgröße MINUS 0.1 + Hülle `light_blue_stained_glass` 1.25× Girth (additiv wirkende
  Aura durch Transparenz); jedes 4. Stamm-Segment zusätzlich ein `end_rod`-Display (Girth
  0.5, FACING=up-State) als heißer Kernakzent. Brightness 15/15.
- **sceneTick-Verhalten**: JOLT verschiebt Knickwinkel um hash(index)-kleine Deltas (Äste
  „zucken"); DISCHARGE skaliert auf 0 (in den Boden fahrend, unterste Segmente zuletzt).

### 5.2 Erstarrte Explosion (~130 Displays) — Gruppe `blast`, Anker: (lokal −2, −10), y+4

- **Kern**: 3 Schalen radial hängender Fragmente um ein leeres Zentrum (r 1.5 / 3 / 5):
  Schale 1 = 18 × `magma_block`/`shroomlight` (glühendes Innere, Scale 0.5–0.9, Brightness
  15/15), Schale 2 = 34 × `orange_stained_glass`/`red_stained_glass`/`blackstone` (0.3–0.7),
  Schale 3 = 38 × `cobblestone`/`coal_block`/`polished_basalt` (0.2–0.6, dunkle Splitter).
  Jedes Fragment: radialer Offset + Tumble-Quaternion (fest), leichte radiale Streuung ±0.8.
- **Rauch**: 40 × `gray_stained_glass`/`light_gray_stained_glass`-Würfel (Scale 0.6–1.6)
  in einem nach oben driftenden, ERSTARRTEN Pilz (Kegel über dem Kern, y+5..y+12).
- **Quelle am Boden**: 2×2 Krater aus echtem `blackstone`/`magma_block` (Terraforming §2.3,
  Welt — der Ursprung der Explosion).
- **sceneTick**: Radius(t) = r0 · (1 + 0.02·sceneTick) (JOLT = sichtbares Weiteratmen);
  DISCHARGE: Radius ×4 über 30 t, Scale→0, Rauch steigt 6 Blöcke und skaliert auf 0.

### 5.3 Kollabierender Turm (~140 Displays) — Gruppe `tower`, Anker: Turmstumpf-Zentrum

- **Welt-Sockel**: §2.3-Stumpf (4–7 hoch). Displays = NUR die fliegenden Bruchstücke.
- **Bruchstücke**: 110 Mauerwerksbrocken (`stone_bricks` 45 %, `cracked_stone_bricks` 25 %,
  `mossy_stone_bricks` 15 %, `cobblestone` 15 %; Scale 0.4–1.3, wenige 1.8er „Wandplatten"
  mit stark anisotroper Box z. B. 1.8×0.9×0.4) + 20 `oak_planks`/`oak_log`-Balken
  (Gebälk, 0.3×0.3×1.6) + 10 `chiseled_stone_bricks`/`stone_brick_stairs`-Akzente.
- **Posen**: jedes Stück bekommt eine ballistische Bahn param. über `flightT(index)` ∈ [0,1]
  (wie weit sein Kollaps fortgeschritten ist, hash-verteilt 0.15–0.75): Position =
  Startpunkt auf dem (gedachten) intakten Turm (Höhe 7–18) + Wurfparabel Richtung
  Nord-West-Fächer; Tumble-Quaternion ∝ flightT. Ergebnis: eine räumliche Spur von „gerade
  gelöst" (oben, dicht) bis „kurz vorm Aufschlag" (unten, weit) — **begehbar**, die
  Unterkante der tiefsten Brocken hängt ≥ 2.2 über Grund (Kopffreiheit geprüft im Builder).
- **sceneTick**: flightT += 0.01·sceneTick (JOLT: alles sackt minimal weiter); DISCHARGE:
  flightT→1 über 80 t (Einschlag), REWIND zurück auf Grundpose.

### 5.4 Chronosphäre + Sanduhr (~80 Displays) — Gruppe `sphere`, Anker: Zentrum, y+6

- **Ringe**: 3 konzentrische Ringe (r 1.6 / 2.3 / 3.0) aus je 12 Segmenten
  (`waxed_copper_block` / `gold_block` / `chiseled_quartz_block` im Wechsel; Box
  0.55×0.18×0.18, tangential rotiert), Ringebenen um 0°/55°/−55° gekippt (Gyroskop-Optik).
  **Rotation**: SanctumOrbitals-Transport — Pose = Funktion der Game-Time, Push alle 40 t
  mit `Duration(40)` + Keyframe-LEAD, Winkelgeschwindigkeit BEWUSST winzig
  (0.8°/s, „fast stehende Zeit"), Early-out ohne Spieler in 64 Blöcken. Das ist die
  EINZIGE Dauer-Animation der Szene. (GeckoLib-Custom-Modell wurde verworfen: `entity/geo`
  existiert zwar, aber BlockDisplay-Ringe brauchen kein neues Modell-Asset, erben das
  bewährte Interpolations-Gesetz und bleiben im Display-Budget.)
- **Kern**: 3 ineinander gedrehte `amethyst_block`/`budding_amethyst`-Displays (Scale 0.7,
  45°-Verkantung) + `chrono_sphere_idle.fx`-Corona (Client).
- **Sanduhr** (unter der Sphäre, y+2.5..y+5.5): 2 Kegel aus je 12
  `glass`/`white_stained_glass`-Boxen (oben/unten, zulaufend), Taille 0.3; **eingefrorener
  Sandstrahl** = 5 × `sandstone`-Displays (0.12×0.5×0.12) in der Taille übereinander +
  ein „Sandhaufen-Kegel" unten (3 flache `sand`-Displays) + im Oberkegel 2 schräg hängende
  `sand`-Displays (nachrutschender, erstarrter Sand).
- **sceneTick**: Sandstrahl-Segmente wandern 0.05/Tick nach unten (JOLT: der Sand rinnt
  zwei Ticks!), Ringe springen 2°.

### 5.5 Vögel + Laub + Kleinkram (~55 Displays) — Gruppe `ambient`

- 4 erstarrte Vögel auf 8–14 Höhe über der Lichtung: je 4 Displays (`black_concrete`-Körper
  0.28×0.2×0.42 + 2 gespreizte `dark_oak_trapdoor`-artige Flügel als flache
  `spruce_planks`-Boxen 0.5×0.04×0.24, 15–40° angestellt + `orange_terracotta`-Schnabel
  0.06³) — mitten im Flügelschlag, Bahn Richtung Zonenrand (Flucht, eingefroren).
- 32 fallende Blätter: `birch_leaves`-Displays (persistent=true-State irrelevant — Displays
  ticken nicht) Scale 0.12–0.2, verstreut 1–7 über Grund, jede mit eigener Kipp-Rotation.
- 7 Astbrocken (`birch_log` 0.25–0.5) unter den gekappten Birken schwebend.
- **sceneTick**: Vögel-Flügelwinkel ±6°, Blätter sinken 0.04·sceneTick und drehen 3°.

**Summe: ~460 statische + ~36 Ring-Segmente animiert = ~500 Displays, Deckel 600.**

---

## 6. Sounds

Neue Rows in `assets/eclipse/sounds.json` + Registrierung in `registry/EclipseSounds.java`
(Layering-Stil des Bestands: vorhandene Eclipse-OGGs + Vanilla-Sound-FILES per Namespace-Pfad,
wie die `event.rift_*`-Rows aus reinen Bestands-Assets gemischt sind):

| Event (`EclipseSounds`-Konstante) | sounds.json-Row | Rezept |
|---|---|---|
| `EVENT_CHRONO_TICK` | `event.chrono_tick` | `minecraft:note/bass` pitch 0.5 vol 0.9 + `eclipse:event/submerge` pitch 1.8 vol 0.25 (dumpfer Uhrschlag mit Tiefen-Körper) |
| `EVENT_CHRONO_WOOM` | `event.chrono_woom` | `eclipse:event/submerge` pitch 0.45 vol 1.0 + `eclipse:event/border_glitch` pitch 0.35 vol 0.3 (tiefes Woom mit Zeit-Knistern) |
| `EVENT_CHRONO_DISCHARGE` | `event.chrono_discharge` | `eclipse:ui/heart_shatter` pitch 0.3 + `eclipse:event/submerge` pitch 0.4 + `eclipse:event/emerge` pitch 0.5 (Entladungs-Knall; Vorbild-Layering: `event.storm_shatter`) |
| `AMBIENT_CHRONO_DRONE` | `ambient.chrono_drone` | `eclipse:ambient/limbo_loop` pitch 0.35 vol 0.35 stream (optionaler Innen-Teppich, vom Ticken-Handler alle ~15 s leise gelegt) |

Vanilla-IDs direkt aus Code (kein sounds.json nötig): `SoundEvents.LIGHTNING_BOLT_THUNDER` /
`LIGHTNING_BOLT_IMPACT` kommen mit dem `setVisualOnly`-Bolt gratis;
`EclipseSounds.EVENT_STORM_BURST` (existiert) für den Explosions-Abschluss;
`SoundEvents.AMETHYST_BLOCK_CHIME` (pitch 0.5) als Klick-Feedback auf der Sphäre.
Subtitles: `subtitles.eclipse.event.chrono_*`-Keys in beiden Lang-Dateien.

---

## 7. Gameplay

- **Zeit-Ruck**: Rechtsklick Chronosphäre (Interaction-Pad §3.3). Feedback-Treppe: Klick 1–4
  → JOLT + Actionbar-Caption `eclipse.chrono.jolt_n` („Die Zeit ruckt… (n/5)" via
  `ServerLang.tr`); Klick 5 → DISCHARGE. Cooldown: neuer Klick erst im FROZEN-Zustand.
- **Finale Entladung**: Sequenz §3.3; danach REWIND-Rückspulen in die Grundpose — der Loop
  ist ohne Abnutzung wiederholbar (Statik = Persistenz, Bewegung = reine Pose-Funktionen).
- **Belohnung (nur 1. Entladung, `rewardClaimed`-Gate):**
  1. **Item „Stillstands-Kern"** — neuer einfacher Trophy-Item-Eintrag `chrono_core` in
     `registry/EclipseItems.java` (Rarity EPIC, `fireResistant`-frei, Tooltip-Zeile
     `item.eclipse.chrono_core.desc`; Muster: `GLITCH_SHARD`). Spawnt als Item-Entity aus
     der Sphäre bei DISCHARGE t=120 für den auslösenden Spieler.
  2. **64 Shards** an den Auslöser: `economy/ShardEconomy.addShards(player, 64, true)`.
  3. `progression/LandmarkDiscoveryService.discover(server, "eclipse:chrono_stasis")` —
     falls noch nicht durch Näherung passiert.
  Wiederhol-Entladungen: nur 8 Shards (kleiner Anreiz, kein Farm-Loop — Server-seitig
  zusätzlich 5-min-Cooldown auf DISCHARGE, Caption `eclipse.chrono.exhausted`).
- **Kein Griefing-Vektor**: Displays sind unzerstörbar, das Interaction-Pad canceled den
  Klick, die Szene schreibt außer Terraforming/Sockel nichts in die Welt.

---

## 8. Performance-Budget + Distanz-LOD

Grundsatz: **die Szene ist statisch = fast gratis.** Displays ohne Pose-Push senden keine
Pakete; ohne Spieler in 96 Blöcken tickt serverseitig NICHTS (Early-out), clientseitig ist
nur ggf. das Fern-Fenster (40 Partikel) offen.

| Distanz (Kamera→Anker) | aktiv |
|---|---|
| > 640 | nichts |
| 640–96 | `chrono_far_pillar` (1 Executor, 40 Partikel) |
| < 160 | Display-Entities streamen ein (Entity-Tracking-Horizont; ~500 Spawns verteilt über den Chunk-Load der 3×3 Chunks) |
| < RADIUS+12 | Grade-Ease beginnt, Ticken-Countdown startet, Regen-Mixin ab amount 0.6 |
| < RADIUS (26) | Frozen-Rain-Loops (≤3×320 GPU-instanced), Dust, Sphere-Corona, Bolt-Glow — ≤6 Executors, Photon-Budget 24 bleibt weit offen |

- Pushes: nur JOLT/DISCHARGE/REWIND, gesliced ≤80/t (§3.5) — kurze Update-Wellen, wie
  gefordert. Ring-Rotation 36 Displays / 40 t = 0.9 Pakete/t nur bei Spielernähe.
- `reducedFx`: schließt alle Photon-Fenster + Grade (XboxEraFx-Gate); Szene + Ticken +
  Slowness bleiben (Gameplay-relevant).
- Iris-Shaderpack: Grade fällt weg (VeilPostController-Gate), Rest unverändert.
- Kein Photon installiert: Cues/Loops verpuffen im `PhotonFxRegistry` (Bytes identisch,
  FxCues-Gesetz) — Szene, Grade, Sounds, Mixin und Gameplay sind davon unabhängig.

---

## 9. Dev-Commands

**(NEU)** `devtools/dev/DevWoahCommands.java` — eigener `/dev`-Subtree (Brigadier-Merge wie
`DevXboxCommands`), Gate `DevRoot.canUseDev`, Docs via `DevCommandRegistry.register` mit
`DevCategory.EVENT`:

| Command | Wirkung |
|---|---|
| `/dev woah chrono spawn` | Site sofort materialisieren (Stage-Gate umgehen; no-op + Meldung, wenn `placed`) |
| `/dev woah chrono tick` | einen Zeit-Ruck auslösen (wie Rechtsklick, ohne Zähler-Gate-Bypass; optionales Arg `count <n>` setzt `joltCount`) |
| `/dev woah chrono discharge` | DISCHARGE sofort starten (ignoriert joltCount/Cooldown) |
| `/dev woah chrono reset` | State auf FROZEN, `joltCount=0`, alle Props discarden + deterministischer Rebuild (Reconcile-Pfad), Anker neu setzen |
| `/dev woah chrono status` | placed/State/joltCount/discharges/rewardClaimed/Display-Zählung ausgeben |

Der `woah`-Literal-Knoten wird hier erstmalig angelegt; spätere Woah-Features (PLAN-01/02/…)
hängen ihre eigenen Subtrees an denselben Literal (Brigadier merged automatisch).

---

## 10. Datei-für-Datei-Checkliste

**Neue Dateien:**

1. `src/main/java/dev/projecteclipse/eclipse/worldgen/chrono/package-info.java` — Package-Doku.
2. `src/main/java/dev/projecteclipse/eclipse/worldgen/chrono/ChronoStasisSite.java` — Stage-Listener, PendingRegistry-Placer, Terraforming, Anker-Publish, Rollback.
3. `src/main/java/dev/projecteclipse/eclipse/worldgen/chrono/ChronoSceneBuilder.java` — deterministischer Szenen-Bau (§5), Identity-Tags, Reconcile, Budget-Spawn.
4. `src/main/java/dev/projecteclipse/eclipse/worldgen/chrono/ChronoStasisService.java` — Statemachine, Aura, Interaction-Handler, Pose-Wellen, Belohnung, Watchdog.
5. `src/main/java/dev/projecteclipse/eclipse/worldgen/chrono/ChronoStasisData.java` — SavedData (§3.4).
6. `src/main/java/dev/projecteclipse/eclipse/client/chrono/package-info.java`.
7. `src/main/java/dev/projecteclipse/eclipse/client/chrono/ChronoZoneState.java` — Anker-Distanz, Ease, Phase-Timer, `suppressVanillaRain()`.
8. `src/main/java/dev/projecteclipse/eclipse/client/chrono/ChronoGradeFx.java` — Veil-GRADE-Row.
9. `src/main/java/dev/projecteclipse/eclipse/client/chrono/ChronoRainField.java` — Photon-Loop-Fenster (Regen/Dust/Corona/Bolt-Glow/Fern-Säule) + Discharge-Umschaltung.
10. `src/main/java/dev/projecteclipse/eclipse/client/chrono/ChronoTickSound.java` — Ticken-Logik.
11. `src/main/java/dev/projecteclipse/eclipse/veilfx/ChronoStasisFxRows.java` — PhotonFxRegistry-Rows für die 2 Cues.
12. `src/main/java/dev/projecteclipse/eclipse/devtools/dev/DevWoahCommands.java` — §9.
13. `tools/photon/chrono_fx.py` — Generator für die 8 Assets aus §4.3.
14. `src/main/resources/assets/eclipse/fx/chrono_{rain_frozen,dust_shimmer,sphere_idle,bolt_glow,jolt_pulse,discharge_burst,rain_release,far_pillar}.fx` (+ `.fxproj`-Siblings via `write_fxproj`).
15. `src/main/resources/assets/eclipse/pinwheel/post/chrono_grade.json` + Shader-Datei neben den bestehenden unter `assets/eclipse/pinwheel/shaders/` (Namenskonvention der xbox_era-Vorlage folgen).

**Zu ändernde Dateien:**

16. `worldgen/DiscMapDefaults.java` — Landmark-Zeile + Clearance-Kommentar (§2.1).
17. `network/fx/FxCues.java` — `CUE_CHRONO_JOLT`, `CUE_CHRONO_DISCHARGE` (+ Javadoc im Haus-Stil: Sender, Payload-Felder, Range).
18. `veilfx/FxAnchors.java` — frozen id `CHRONO_CENTER`.
19. `client/mixin/LevelRendererMixin.java` — `renderSnowAndRain`/`tickRain` HEAD-Cancels (§4.4; KEINE Änderung an `eclipse.client.mixins.json` nötig).
20. `registry/EclipseSounds.java` + `assets/eclipse/sounds.json` — 4 neue Events (§6).
21. `registry/EclipseItems.java` — `chrono_core` (+ Modell/Textur `assets/eclipse/models/item/chrono_core.json`, `textures/item/chrono_core.png`, Lang-Keys).
22. `assets/eclipse/lang/en_us.json` + `de_de.json` — Captions (`eclipse.caption.chrono.discharge`, `eclipse.chrono.jolt_n`, `eclipse.chrono.exhausted`), Item-Name/Tooltip, Subtitles, `dev.eclipse.*`-Doc-Keys für §9.

**Validierung:** `./gradlew build` · `python3 tools/photon/fxlib.py validate --lint` ·
In-Game: `/dev woah chrono spawn` → Szene prüfen → `tick` ×5 → `discharge` → `reset`;
Restart-Test (Reconcile, joltCount-Persistenz); `/kill @e[tag=eclipse_chrono_prop]` →
Selbstheilung; reducedFx- und Iris-Gates.

---

## 11. Risiken

1. **Display-Volumen & Chunk-Load-Pop-in (~500 Entities in 3×3 Chunks).** Beim Einfliegen
   streamen alle Spawns mit dem Entity-Section-Load; Präzedenz CreditsShatterAct (~1400)
   zeigt Machbarkeit, aber dort temporär. Gegenmittel: harter 600er-Deckel, Gruppen-Anker
   (wenige Sections), Brightness statt Licht-Blöcke. Fallback: `ambient`-Gruppe streichen
   (−55) und Rauchballen halbieren.
2. **Entity-Tracking-Horizont (160 Blöcke) vs. „von weitem sichtbar".** Die Blitz-Displays
   sind jenseits 10 Chunks prinzipiell unsichtbar (ExpansionBorderFx-Lektion). Das Fern-Tell
   hängt daher komplett am Photon-`chrono_far_pillar` — auf photon-losen Clients gibt es
   KEINEN Fern-Tell (akzeptierter Degrade; Blitz erscheint ab ~160 Blöcken).
3. **Persistente Displays + Reconcile-Drift.** Duplikate nach Crash mitten im Spawn-Batch,
   verlorene Identity-Tags durch fremde `/kill`-Selektoren, Chunk-Kopien via Structure-Void
   o. ä. — der Reconcile (adopt/discard/respawn, SanctumOrbitals-Doktrin inkl.
   `areEntitiesLoaded`-Boot-Race) MUSS von Anfang an mitgebaut werden, sonst „vermüllt" die
   Site schleichend.
4. **DISCHARGE/REWIND-Zustand über Restarts.** Server-Stop mitten in der Entladung
   hinterlässt halb geflogene Posen; da Posen stateless Funktionen sind, heilt der
   Watchdog-/Reconcile-Push auf `sceneTick=0` — aber der Belohnungs-Moment darf nicht doppelt
   feuern (Claim wird VOR dem Item-Spawn persistiert, `setDirty` sofort).
5. **Mixin auf `renderSnowAndRain`/`tickRain`.** Vanilla-interne Methodennamen — bei
   NeoForge-Patches/Namensdrift bricht der Cancel leise (defaultRequire=1 macht ihn laut ⇒
   gewollt). Zusätzlich Doppel-Regen-Risiko am Zonenrand (0.6-Schwelle) und Konflikt mit
   künftigen Weather-Renderern (StormWeatherRenderer rendert eigene Regen-Vorhänge — die
   Chrono-Zone liegt aber nie in einem Fog-Storm-Radius, §2.1-Clearances).
6. **Sound-Rohmaterial.** Es gibt keine dedizierte Tick-/Uhr-Aufnahme; das
   `note/bass`+`submerge`-Layering (§6) muss in-game abgenommen werden — klingt es zu
   „musikalisch", ist der Fallback ein neues kleines OGG (`sounds/event/chrono_tick.ogg`),
   was Asset-Autoring bedeutet.
7. **Photon-Frozen-Rain-Dichte.** 3×320 GPU-instanzierte Partikel sind laut Zensus
   (era_dust_motes-Präzedenz) unkritisch, aber „tausende Tropfen" bei schwachen Clients
   könnten flimmern/kosten — maxParticles ist der Tuning-Knopf, reducedFx das Notventil.
