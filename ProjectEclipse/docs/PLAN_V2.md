# PROJECT: ECLIPSE — v2 Master Plan

Master architecture for the v2 upgrade of Eclipse-Core (NeoForge 1.21.1, modid `eclipse`,
package `dev.projecteclipse.eclipse`, Mojmap + Parchment, ModDevGradle 2.0.142, Java 21).
v1 is complete and green (see `README.md`). This plan consumes the five collector reports in
`docs/ideas/01..05_*.md` and sequences 16 strictly-sequential workers
(`docs/WORKER_PROMPTS_V2.md`) plus an orchestrator asset pipeline (`docs/ASSET_MANIFEST_V2.md`).

---

## 1. Requirement → subsystem map

| # | Requirement | Subsystem (new package) | Worker(s) |
|---|---|---|---|
| 1 | Veil 4.3.0 required, limbo/sun post shaders, Quasar, easing | `veilfx` (client), `assets/eclipse/pinwheel|quasar` | W1 |
| 5 | Real max-health hearts + HUD burst | `hearts` | W2 |
| 2 | Disc world, fusion, ring expansion, nether disc, own timeline | `worldgen`, `worldgen.stage` | W3, W4 |
| 2/10 | Temples/village/stronghold, altar sanctum + protection | `worldgen.structure` | W5 |
| 3 | Cutscene engine, freeze/invuln, keyframe editor | `cutscene`, `client.cutscene` | W6 |
| 4 | Circular soft border + glitch FX + failsafe | `border`, `client.border` | W7 |
| 7/8 | Bossbar skin, sidebar panel, announcements, timeline sync | `client.hud` | W8 |
| 6 | Handbook 2.0 (6 tabs, cursor, sounds, parallax) | `client.handbook` | W9 |
| 9 | Custom mobs + procedural anims + placeholder art | `entity`, `client.entity` | W10 |
| 9 | Herald (day 7) + Ferryman (day 14) bosses | `entity.boss` | W11, W12 |
| 10/12 | Umbral-shard economy, rewards, improved 14-day arc | `economy` + config defaults | W13 |
| 13 | Stage step-loader, phase scheduler, goal editor, inspector | `devtools` | W14 |
| 14 | Main menu v2 + settings screen | `client.menu` (rework) | W15 |
| 11/15 | Gated mod downloads, Sodium/Iris matrix, full smoke | run/mods + docs | W16 |

---

## 2. Package layout (new code only; v1 packages unchanged unless listed)

```
dev.projecteclipse.eclipse
├── veilfx/                     (client-only classes, guarded)
│   ├── VeilPostController      post pipeline add/remove + uniform feed + Iris gate
│   ├── QuasarSpawner           safe createEmitter wrapper (try/catch, id → emitter)
│   └── package-info
├── hearts/
│   ├── HeartsService           LIVES → MAX_HEALTH modifier; cap; reapply hooks
│   └── client/HeartBurstOverlay  GUI layer above PLAYER_HEALTH
├── worldgen/
│   ├── DiscChunkGenerator      Registries.CHUNK_GENERATOR codec "eclipse:disc"
│   ├── DiscBiomeSource         Registries.BIOME_SOURCE codec "eclipse:disc_sectors"
│   ├── DiscTerrainFunction     pure stateAt(profile, x,y,z, stage); shared by gen + growth
│   ├── DiscMapData             ECLIPSE_SEED constant + authored disc_map.json (+ optional PNG override)
│   ├── DiscProfile             overworld vs nether parameter sets
│   ├── stage/
│   │   ├── WorldStageService   setStage(server, dim, n, animate) single entry point
│   │   ├── RingGrowthService   tick-budgeted annulus sweep/erase; growth cursor persistence
│   │   └── FusionSequence      intro stage-1 dual-front sweep
│   └── structure/
│       ├── StructureStamper    vanilla Structure.generate + programmatic set-pieces
│       ├── AltarSanctumBuilder sanctum @ spawn (GhostShipBuilder pattern)
│       └── SanctumProtection   break/place/explosion/spawn suppression r=16
├── cutscene/
│   ├── CutsceneService         play/abort, path library load + S2C sync, ACK tracking
│   ├── CutscenePaths           config/eclipse/cutscenes/*.json load/save
│   ├── FreezeService           CUTSCENE_LOCK attachment; rubber-band + invuln; TTL watchdog
│   └── client/
│       ├── CameraDirector      Catmull-Rom/bezier eval, quat slerp, roll, fov
│       ├── CutsceneInput       input swallow + skip request
│       ├── LetterboxLayer      GUI layer, HUD suppression
│       └── KeyframeRecorder    editor command support
├── border/
│   ├── SoftBorder              circular border state + physics (players/vehicles/elytra/pearls)
│   └── client/BorderFxRenderer geometry glitch strip + particles + Veil post proximity
├── entity/
│   ├── EclipseEntities         DeferredRegister<EntityType<?>> + attributes
│   ├── TheOtherEntity / GazerEntity / UmbralStalkerEntity / DeckhandEntity / SunmoteEntity
│   ├── EclipseSpawner          day/event-keyed server-tick spawning; Pale/Umbral Nights
│   └── boss/HeraldEntity, HeraldShardProjectile, FerrymanEntity, FerrymanFight
├── client/entity/              models (code-built LayerDefinitions) + renderers
├── client/hud/                 BossbarSkin, SidebarPanel, AnnouncementOverlay, TypewriterLine
├── client/handbook/            HandbookScreen, tabs/*, CursorManager, UiSounds, GlitchText
├── economy/                    ShardEconomy, CompassOfWatcherItem, GraveDowserItem,
│                               VitaeShardItem, SupplyBeacon
├── devtools/                   PhaseScheduler, StageIO, TimelineInspector,
│                               client/GoalEditorScreen
└── client/menu/                (rework) EclipseTitleScreen v2, EclipseSettingsScreen,
                                ParallaxBackground, MenuParticles
```

Registry additions: `EclipseEntities`, `EclipseWorldgen` (chunk-generator + biome-source
codecs), new items in `EclipseItems`, new sounds in `EclipseSounds`, `EclipseClientConfig`
(NeoForge `ModConfigSpec`, type CLIENT, registered in the `EclipseMod` constructor via
`ModContainer`).

---

## 3. Data flow (key paths)

**World stage** (own timeline, separate from days):
`stages.json` triggers (`intro_fusion` | `milestone` | `day:N` | `final_day` | manual command)
→ `WorldStageService.setStage(dim, n, animate)` → persists `worldStage{Overworld,Nether}` +
`growthCursor` in `EclipseWorldState` → `RingGrowthService` enqueues annulus columns
(ordered radius-then-angle; fusion orders by distance-to-nearest-disc-edge) → per tick drains
a 2 ms budget writing `LevelChunkSection` directly, then relight + chunk resend (≤4/tick) →
broadcasts `S2CStagePayload` (handbook map, border FX) → on completion `StructureStamper`
places stage structures → `SoftBorder.setRadius(stageRadius + 12)` → `CutsceneService`
optionally plays `unlock_ring_N` orbit + `FreezeService` freezes during the sweep.
`DiscChunkGenerator` consults the same committed stage for never-generated chunks — one
deterministic terrain function, two consumers, idempotent by construction.

**Cutscene**: `CutsceneService.play(id, players)` → freeze (server) + `S2CCutscenePlayPayload`
→ client `CameraDirector` evaluates the synced path per render frame (Camera mixin position,
`ViewportEvent.ComputeCameraAngles` roll, `ComputeFov` fov) → letterbox + HUD suppression →
skip via `C2SCutsceneStatePayload` (checked against per-cutscene `allowSkip` + dev toggles) →
client ACK FINISHED/SKIPPED → unfreeze (watchdog releases at `durationTicks + 100` regardless).

**Hearts**: `LivesApi.set/add` (LIVES attachment = hearts count, source of truth) →
`HeartsService.apply(player)` sets transient MAX_HEALTH modifier `hearts*2 − 20` → reapplied
on respawn/clone/login → death with loss → `S2CHeartBurstPayload(heartIndex)` → HUD shatter
overlay positioned by vanilla heart math.

**Announcements**: `DayScheduler.setDay` / `UnlockState` change / milestone / stage completion
→ `Announcer.announce(server, style, title, subtitle)` → `S2CAnnouncePayload` → client
typewriter overlay + bossbar sweep; final text posted to chat once complete.

**Soft border**: server `PlayerTickEvent.Post` d² check → near flag / impulse / teleport
fallback → `S2CBorderPayload(center, radius, fxRange)` at login/change → client renders
glitch strip only within fxRange; vanilla border kept at radius+48 (damage 0) as failsafe,
hidden by a `LevelRenderer#renderWorldBorder` cancel mixin.

---

## 4. Persistent state & config additions

`EclipseWorldState` (new fields, all with defaults so old saves load):
`worldStageOverworld`, `worldStageNether`, `growthCursor` (long index + dim), `borderCenterX/Z`,
`softBorderRadius`, `nextPhaseEpochMillis`, `sanctumBuilt`, `heraldDefeated`, `ferrymanDefeated`,
`gravePositions` (owner → List<GlobalPos>), `shardPool` (team deposits), `disabledCutscenes`
(Set<String>), `activeNightEvent` (string + day stamp).

New config files under `config/eclipse/` (same lazy-default pattern as `EclipseConfig`):
`stages.json` (per-dim stage list: radius, trigger, structures, oreBudget),
`cutscenes/*.json` (camera paths, per-file `allowSkip` + `enabled`),
`disc_map.json` (authored control data: sector wedges, landmarks, mountain, rivers, wells).
Updated defaults in `days.json` / `milestones.json` / `modgate.json` (v2 arc, §6 of
`docs/ideas/04_content.md`). Client: `eclipse-client.toml` via `ModConfigSpec`
(`customMenu`, `showBossbarSkin`, `showSidebar`, `uiSounds`, `customCursor`, `veilPostFx`,
`reducedFx`).

New network payloads (registrar version bumped to "2"; all following v1 patterns in
`network/`): `S2CHeartBurstPayload`, `S2CStagePayload`, `S2CBorderPayload`,
`S2CCutsceneLibraryPayload`, `S2CCutscenePlayPayload`, `C2SCutsceneStatePayload`,
`S2CAnnouncePayload`, `S2CGoalProgressPayload`, `S2CTimelinePayload`, `S2CQuasarPayload`,
`S2CShakePayload`, `C2SConfigEditPayload` (perm-checked).

---

## 5. Key decisions (adopt / adapt / reject)

| Decision | Verdict | Reason (1 line) |
|---|---|---|
| One deterministic terrain function, two consumers (gen + runtime growth) (#1) | **Adopt** | Idempotent by construction; single code path powers chunkgen, animation, and dev revert. |
| Pre-generate full disc + hide behind barriers (#1 alternative) | **Reject** | Doubles block writes, leaks the map, still needs live writes for the growth animation. |
| Painted PNG heightmap/biome control maps (#1) | **Adapt** | Agents can't hand-paint; use authored `disc_map.json` (sectors/landmarks/mountain) + fixed-seed noise, keep an optional PNG-override hook for later human painting. |
| Fixed `ECLIPSE_SEED` constant, never `use_server_seed` (#1) | **Adopt** | Determinism is the whole "hand-prepared map" guarantee. |
| dimension_type override min_y −176 / height 512 (#1) | **Adopt** | Needed for underside + y≈280 mountain; event world starts fresh anyway. |
| Ring sweep batching: 1 chunk-column/tick, section writes + relight + resend (#1/#5) | **Adopt (merged)** | Proven Chunk-by-Chunk model; #5's 2 ms nano-budget + ≤4 relights/tick is the stricter guard — use both. |
| Veil 4.3.0 as required dep, jar-in-jar `[4.3.0,)` (#2) | **Adopt** | LGPL, Sable precedent, assets are dead weight without it; fallback to external-jar if MDG jarJar misbehaves (W1 has explicit fallback). |
| Lodestone lib (#2/#5) | **Reject** | Quasar + Easing + post pipelines cover it; second render lib doubles compat surface. |
| Veil first-party `IrisCompat` replaces v1 reflection IrisCompat (#2) | **Adopt** | Deletes fragile reflection; single source of truth for "shaderpack active". |
| Gate ALL Veil post pipelines/injections behind `areShadersLoaded()` (#2) | **Adopt** | Veil issue #34: world shaders break under active shaderpacks; biome tint/sun.png fallbacks remain. |
| Quasar for all particle systems incl. replacing v1 call sites (#2) | **Adopt** | Requirement 1; collector #4's "Quasar unavailable" belief is wrong (ships inside Veil). |
| Client camera-override cutscenes, not spectate-entity (#5) | **Adopt** | Per-frame smoothness, true roll/fov/easing; Sodium/Iris read camera after setup. |
| Own ~600-line camera engine, Veil only for easing + letterbox grade (#2/#5) | **Adopt** | Veil has no cinematic camera API (verified). |
| Server-authoritative FreezeService via attachment, never `abilities.invulnerable` (#5) | **Adopt** | Crash-safe; EclipseWorldState never stores freeze so restart always unfreezes. |
| Soft border: impulse physics + teleport fallback + vanilla border failsafe at R+48 (#5) | **Adopt** | Robust vs vehicles/elytra/pearls; failsafe catches anything physics misses. |
| Hearts via transient MAX_HEALTH `ADD_VALUE` modifier off LIVES attachment (#3) | **Adopt** | Transient avoids NBT double-apply; LIVES stays the single source of truth. |
| Heart burst as overlay above PLAYER_HEALTH, not layer replacement (#3) | **Adopt** | Safest interop (AppleSkin-style mods, Sodium/Iris untouched). |
| Surgical bossbar skin via `CustomizeGuiOverlayEvent.BossEventProgress` (#3) | **Adopt** | Skins only our bars; other mods' bars render vanilla. |
| Custom sidebar panel from `ClientStateCache`, not vanilla scoreboard data (#3) | **Adopt** | Vanilla scoreboard stays free for ops; richer icons/layout. |
| GLFW cursors with mandatory reset in `Screen#removed()` (#3) | **Adopt** | No vanilla API; leak-safe lifecycle is the only hard part. |
| Vanilla core-shader GUI effects primary, Veil GUI shaders optional (#3) | **Adopt** | Handbook must render with zero Veil post (Iris-active case). |
| Mob models as code (`MeshDefinition`/`CubeListBuilder`), boxy UVs + docs/uv/*.md (#4) | **Adopt** | No Blockbench in the loop; orchestrator image-gen needs documented UV maps; workers commit programmer-art so game never breaks. |
| Server-tick `EclipseSpawner` keyed off day/events, not biome modifiers (#4) | **Adopt** | Day-gated spawns are event logic, not worldgen data. |
| 14-day arc v2 (nether day 2, bosses 7/14, stronghold 12) (#4) | **Adopt** | Requirement 12; replaces v1 defaults (nether was day 6) via `days.json` defaults rewrite. |
| Herald core required for altar L4; Ferryman = finale mass-revive (#4) | **Adopt** | Ties bosses into existing milestone + ReviveRitual machinery. |
| Sunmote mob (#4) | **Adopt (last, optional)** | NICE-tier; cheap (2 cubes) and sells the sanctum — W10 does it only if on budget. |
| Create: Steam 'n' Rails (#4) | **Reject** | No NeoForge 1.21.1 build. |
| Create: Connected (#4) | **Defer to W16 (optional)** | NICE; only if namespace verification is trivial during integration. |
| spark profiler on dev server (#5) | **Adopt (dev only)** | Free MSPT evidence for ring-growth budget tuning; never a dependency. |
| Cloth Config / architectury (#5) | **Reject** | JSON + reload + own screens already exist; single-loader project. |
| Aeronautics/Sable sub-level border handling = teleport player only (#5) | **Adopt** | Sable sub-levels aren't vanilla vehicles; clamping contraptions is out of scope, documented. |
| days.json `borderSize` as border driver | **Retire (keep field)** | v2 border radius derives from world stage; field kept so old configs parse, ignored with a log warning. |

---

## 6. Risk register

| # | Risk | L×I | Mitigation |
|---|---|---|---|
| R1 | Veil post pipelines break/black-screen under Iris shaderpack (Veil #34) | H×H | Hard gate: every `PostProcessingManager.add` behind `IrisCompat.INSTANCE.areShadersLoaded()==false`; per-pipeline try/catch; v1 tint/sun.png fallbacks kept; W16 tests Sodium-only, Sodium+Iris-no-pack, Sodium+Iris+pack. |
| R2 | Ring growth tanks MSPT / floods clients with chunk packets | M×H | 2 ms nano budget + ≤4 relights/tick + MSPT>40 skip; growth cursor persisted (restart-safe); spark measurements in W4 acceptance. |
| R3 | `DiscChunkGenerator`/`DiscBiomeSource` codec or dimension JSON error = world fails to load | M×H | W3 acceptance = fresh `runServer` boots + `/locate`-free smoke; keep vanilla JSONs recoverable via git; fixed seed makes failures reproducible. |
| R4 | Camera mixin fights Sodium/Iris or breaks on shaderpack shadow pass | M×M | Inject at `Camera#setup` TAIL only (both read after); roll via ViewportEvent (API, not mixin); W16 matrix test; cutscenes abort cleanly if mixin fails (`defaultRequire` kept, engine no-ops without positions). |
| R5 | min_y change corrupts existing dev worlds | H×L | Documented: v2 requires fresh world; W3 deletes `run/world` in dev; stage snapshots provide curated-map workflow. |
| R6 | MDG jarJar config friction for Veil | M×L | W1 has explicit fallback: plain `implementation` + required dep + ship jar in packs (W16 downloads Veil into run/mods regardless). |
| R7 | MAX_HEALTH modifier double-apply or lost on respawn | M×M | Transient modifier + `addOrUpdateTransientModifier` + reapply on Respawn/Clone/Login; W2 acceptance includes kill/respawn/relog cycle. |
| R8 | Aeronautics (young, ~760 issues) breaks smoke or pins older Create | M×M | W16 verifies Create pin before updating; Aeronautics is optional/gated — on hard failure, document + exclude from server pack rather than block ship. |
| R9 | Sequential workers drift from frozen APIs → rework | M×M | This plan freezes signatures (§3/§4); every prompt lists exact v1 files it may touch; README "Core APIs" updated by the worker that changes them. |
| R10 | Orchestrator image-gen art mismatches mob UVs | H×L | Workers commit UV-mapped programmer art + `docs/uv/<mob>.md` first; game is never broken; art is drop-in byte-for-byte. |
| R11 | Freeze softlock (missed ACK, disabled cutscene, crash mid-scene) | M×H | Watchdog: TTL `durationTicks+100`, release on death/dimension change/logout, stale lock cleared at login, freeze never persisted, `/eclipse cutscene abort`. |
| R12 | Handbook GLFW cursor leak / crash on some drivers | L×M | Guard `glfwCreateStandardCursor` nulls, cache ptrs, reset in `Screen#removed()`, destroy on resource reload, `customCursor` config kill-switch. |

---

## 7. Test strategy

**Universal gate (every worker):** `./gradlew build` green (strict compile), then commit.
No unit-test suite exists (v1 convention); verification is build + targeted runtime smoke +
final visual eval. Workers that touch server logic must boot `runServer` (EULA:
`run/eula.txt` = `eula=true`) to "Done", exercise their feature via `/eclipse ...` commands,
and stop by PID (see `AGENTS.md` — never blanket-kill).

**Phase gates:**
- After W1 (Veil): server boots with Veil loaded; client dev run shows limbo grade +
  sun halo; `/quasar`-style spawn of one emitter works; with a shaderpack active, pipelines
  self-disable (log line proves gate).
- After W2 (hearts): new player has 10 max HP; `/eclipse lives set` moves the bar; kill →
  respawn shows burst + 8 HP; relog keeps modifier applied exactly once.
- After W3 (disc gen): FRESH world boots; spawn is on the main disc; void beyond stage-0
  radius; nether disc profile generates; `/eclipse status` unaffected.
- After W4 (stages): `/eclipse stage set overworld 2 animate` visibly grows the ring on a
  dev server without MSPT collapse (spark evidence); restart mid-growth resumes; erase-revert
  returns to prior radius.
- After W5 (structures): sanctum stands at spawn and is unbreakable for non-ops; stage-2
  animate reveals desert temple; stronghold command-trigger carves + places portal room.
- After W6 (cutscenes): `/eclipse cutscene preview intro_rise` flies the path with letterbox;
  skip works when allowed; frozen player can't move or take damage; watchdog releases a
  killed client.
- After W7 (border): walking out beyond R gets pushed back (also boat, elytra, pearl);
  glitch strip appears only within fxRange; vanilla border invisible but still stops at R+48.
- After W8–W9 (UI): bossbar skin renders our bars only; sidebar toggles via config;
  announcement typewriter + sweep fire on `/eclipse day set`; handbook opens (J), all 6 tabs
  navigate, cursor changes on hover, sounds play, timeline hides future entries.
- After W10–W12 (content): each mob spawns via command + scheduler, animates, drops;
  Herald full fight loop on a dev server (3 phases, arena lock, herald_core drop);
  Ferryman fight + mass revive path.
- After W13 (economy/arc): shard deposit shop cycles; compass points at nearest player;
  vitae shard grants heart to cap 7; day arc defaults regenerate correctly on fresh config.
- After W14 (devtools): stage save/load/revert roundtrip is byte-identical on the annulus;
  scheduler counts down on a bossbar and fires; goal editor writes days.json + reloads.
- After W15 (menu): title v2 animates; `customMenu=false` restores vanilla; settings screen
  reachable from Mods list and in-game.
- W16 (integration): full modlist boot matrix, see prompt.

**Final client visual eval checklist (W16 + orchestrator, `runClient` on the VM desktop):**
1. Title screen v2: drifting panorama, parallax responds to mouse, particles, widgets; toggle off restores vanilla.
2. New world intro: ship submerge camera flight → overworld rise cutscene → fusion animation fills the gap ring; skip honored per config.
3. Limbo: purple water/world grade fades in ≤2 s after entering; motes drift; off when a shaderpack is active.
4. Overworld: purple sun rim halo tracks the sun; disappears under shaderpack (fallback sun.png tint remains).
5. Hearts: 5 hearts shown; die with loss → shatter animation on the exact lost heart; low-health jitter matches vanilla.
6. Border: approach rim → glitch static + wisps within ~8 blocks; sprint/boat/pearl attempts all bounce; no vanilla border wall visible.
7. Ring unlock: `/eclipse stage set overworld 2 animate` → ring sweep animation + orbit cutscene + freeze + announcement + temple revealed.
8. Handbook: all 6 tabs, page-turn + parallax, cursor swap, hover/page sounds, glitchy "???" future timeline, map rings match stage.
9. Bossbar themes (day/goal/boss) + sidebar; both toggleable live in settings screen.
10. Mobs: Gazer vanish-when-seen, Stalker pack at night, The Other during Pale Night, Deckhands rowing in limbo.
11. Herald + Ferryman fights, boss bossbar theme, drops, finale mass revive cinematic.
12. Matrix: all of the above passes with (a) Sodium only, (b) Sodium+Iris no pack, (c) Sodium+Iris+pack (degraded: no Veil post, tint fallbacks), and with none of the optional mods installed.

---

## 8. Worker sequence (rationale)

Foundation (W1 Veil, W2 hearts) unblocks every later visual/health consumer. World core
(W3 generator → W4 stages → W5 structures) precedes border (needs radii) and cutscenes
(unlock shots film the growth). Cutscenes (W6) precede border (W7) only because FreezeService
lives in W6 and W7's pushback must respect frozen players; both precede UI announcements.
UI (W8 HUD → W9 handbook) before content so bosses get skinned bars and the bestiary/timeline
have sinks. Content (W10 mobs → W11 Herald → W12 Ferryman → W13 economy/arc) in dependency
order (bosses summon mobs; economy prices boss drops). Devtools (W14) after all systems exist
to be inspected. Menu (W15) is isolated, next-to-last. Integration (W16) last: downloads the
real mod pack, runs the matrix, fixes breakage, updates docs.
