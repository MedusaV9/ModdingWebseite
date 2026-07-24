# AUDIT-recent — v4/v5-round completion audit (AUDIT-2)

**Scope:** every v5 package (PLAN-A A1–A16, PLAN-B B1–B17, PLAN-C C1–C19, PLAN-D D1–D14), every EVAL-*.md fix-list item, and the full v4-era item list from the audit brief. Static read-only verification of the CURRENT code — mechanism wired, not file presence. No Gradle/git; only this report was written.

**Verdict counts:** **210 DONE · 4 PARTIAL · 8 MISSING** (222 audited items; the `storm_heart` gap appears in both the v5 and v4 sections, same root cause).

Evidence notation: `path:line` anchors are from the audited working tree.

---

## 1. PLAN-A — Client/UI (16/16 DONE)

| # | Item | Status | Evidence |
|---|---|---|---|
| A1 | i18n core: locale merge + server resolver | DONE | `lang/ServerLang.resolve` baked per recipient everywhere (e.g. `XboxEventService.broadcast`, `HeartTheftService.celebrate`); DE/EN key parity 2 119/2 119 (EVAL-POL-F §10 measured) |
| A2 | Loading screen smooth fade-out | DONE | `EclipseLoadingScreen` calls `DismissFade.begin(this)`; `renderPanel(..., alpha)` replays at decaying alpha |
| A3 | Main menu: settings removal + panorama/logo | DONE | `EclipseTitleScreen` has no Eclipse-settings entry (comment at line ~160); shipped `panorama_*.png` dither + feathered `logo.png` measured in EVAL-POL-F §2 |
| A4 | Timeline "AY 1" clipping | DONE | EVAL-SAT-F item 2 SATISFIED; `TimelineService` |
| A5 | Altar rewards: hide future levels + naming | DONE | `RewardsTab` renders only next milestone + 1 teaser; `S2CMilestonesPayload.current()` withholds > altarLevel+1 (EVAL-SAT-S #17) |
| A6 | Map tab rework (fog-of-war, sketch) | DONE | EVAL-SAT-F item 17 SATISFIED |
| A7 | ONE day timer; bossbar/top-center duplicates stripped | DONE | `DayTimerLayer` stack math verified collision-free (EVAL-POL-F §6); `XboxTimerLayer.active()` mutual exclusion |
| A8 | Sidebar: setting, TAB-only, sections, pre-event gate | DONE | `EclipseClientConfig.SHOW_SIDEBAR` + `SidebarMode` enum; `SidebarExpanded` sections + buffs; pre-event hidden (EVAL-SAT-F item 16) |
| A9 | Custom level bar replaces XP bar | DONE | `client/skills/SkillXpBarLayer` |
| A10 | Bossbar skin style pass | DONE | `BossbarSkin`: damage-only glow, no idle pulse, time-based fill lerp (EVAL-POL-F §6 "exactly right") |
| A11 | Inventory lock slots: no unlock-day hint | DONE | `InvLockOverlay` uses only `gui.eclipse.invlock.sealed` (EVAL-SAT-S #18) |
| A12 | Artifact only after event start | DONE | `ArtifactSlotLock` gates on `StartState.eventStarted` (3 call sites) |
| A13 | Rebirth server system | DONE | `RebirthConfig` (`costGrowth` 1.3, `levelCostMultiplierPerRebirth` 1.0) + `gametest/rebirth/RebirthTests` |
| A14 | Skill tree client rework (canvas, dbl-click, rebirth UI, wand tab) | DONE | EVAL-SAT-F item 15 SATISFIED |
| A15 | "New Decree" dedupe + arbitration | DONE | `DawnCeremony.lastGoalsHash` hashes RESOLVED `GoalConfig.goalsForDay` ids (V5-FIXGUARD / EVAL-SAT-S #4 fix in place, `DawnCeremony.java:191-231`) |
| A16 | EMI gate fix + upgrade | DONE | `build.gradle:143-148` EMI 1.1.24 jarJar; `RecipeGate.handleRecipeLocks` → `EmiReindexer.requestReload()` |

## 2. PLAN-B — Worldgen (17/17 DONE)

| # | Item | Status | Evidence |
|---|---|---|---|
| B1 | Mountain snowline persists | DONE | `DiscBiomeSource` maps footprint ≥ `SNOWLINE_Y=152` to snowy_slopes (EVAL-SAT-S #11) |
| B2 | Vanilla-shaped ore veins | DONE | `OreVeinShape` + `OreConfig` vanilla layers; deviations documented as deliberate (EVAL-SAT-S #7) |
| B3 | Structure air-bubble fix | DONE | `SitePrep.prepareCavity` per-piece boxes (EVAL-SAT-S #8) |
| B4 | Villages in air fixed | DONE | `VanillaLandmarks.placeVanillaAsync` deterministic `plateauY` + terrain skirt (EVAL-SAT-S #8) |
| B5 | Disc mob spawning | DONE | EVAL-SAT-F item 9 SATISFIED; `/dev spawn census` bands line exists (`de_de.json:1048`) |
| B6 | Nether floor interest + outer cliffs (merged w/ B11) | DONE | `DiscTerrainFunction`: `lavaPit`, `valley`, SOUL/BASALT palettes, `cliffiness`, terracotta/badlands ring |
| B7 | Nether arrival: shaft, fall damage, fog, lightning, protection | DONE | `BreachTransferService` (B7 fog-veil particle cadence, lines 126-130); `BreachBuilder` real `LightningBolt` (line 140); `LandmarkProtection` breach+arrival zones (`BREACH_PAD` 12); EVAL-SAT-F item 8 |
| B8 | "Betrete den Nether" quest | DONE | `GoalConfig` `TriggerType.VISIT_DIMENSION` → `minecraft:the_nether`; `QuestDetectors` iterates VISIT_DIMENSION specs |
| B9 | Border kick earlier + 5 s slow fall | DONE | EVAL-SAT-F item 7 SATISFIED |
| B10 | Spawn/altar full no-build r96 | DONE | `ProtectionConfig` radius 96 `noBuild=true`; `SanctumProtection.isBuildBlocked` on break/place/explosion (EVAL-SAT-S #12) |
| B11 | Outer terrain cliffs/hills | DONE | merged into B6 (single owner `DiscTerrainFunction`) |
| B12 | Giant caves + 2 new dungeons | DONE | `CaveDensity.cathedralAt`; `UndergroundSites.DUNGEON_ROWS` + `loot_table/dungeon/flooded_crypt.json`, `glitch_reliquary.json` |
| B13 | Snow returns after storm | DONE | `FogStormSites.recoverSite`: budgeted freeze_top_layer sweep + persisted `recovered` flag (crash-mid-sweep edge remains, see EVAL-SAT-S #10 note) |
| B14 | Umbral shards actually received | DONE | `ShardEconomy.deliverShardItems` + `ShardPayouts.deliverOrQueue` with login flush (`onPlayerLoggedIn`) |
| B15 | Stronghold removal | DONE | defaults no longer enqueue; `legacyStrongholdSelfHeal` opt-in default false (`EclipseConfig.java:46-48`, V5-FIXGUARD / EVAL-SAT-S #5) |
| B16 | `/dev chunk regen` | DONE | `DevChunkCommands` + `ChunkRegen.tickBudgeted` under `WRITE_BUDGET_PER_TICK` (EVAL-POL-S #4 fix in place) |
| B17 | `/give` names for OPs only | DONE | `ClientSuggestionProviderMixin` + `DevPlayerCommands` (EVAL-SAT-S #6) |

## 3. PLAN-C — Events (18 DONE, 1 PARTIAL)

| # | Item | Status | Evidence |
|---|---|---|---|
| C1 | Limbo water shader (real mask, world anchor, curvature) | DONE | `limbo.fsh` v3/v4: depth-reconstructed water band, `VoyageOffset` drift, ray-elevation curvature (POL-F #3 fix in header + code) |
| C2 | Limbo sky zenith disc + drift | DONE | `LimboSpecialEffects` C2 disc (EVAL-POL-F §1: "resolves the glitchy purple thing correctly") |
| C3 | Deckhands look-at fix | DONE | `DeckhandEntity` pins `yBodyRot` to `benchFacingYaw()`; `LookAtPlayerGoal` head-only |
| C4 | Pre-event limbo safety + ghost revival | DONE | `PreEventSafety` damage cancel + water rescue; `LivesApi.set` 0→positive unban path (EVAL-SAT-S #21) |
| C5 | Intro storm push zone, day switch, no night credit | DONE | `IntroLightningPhase.pushZoneTick`, `IntroSequence.scriptedDaySwitch`, `QuestDetectors.pollNightWindow` grace (EVAL-SAT-S #22) |
| C6 | Cutscene preload, hidden player, FOV, day-12 return | DONE | `CutsceneService` tickets + `validatedReturnPosition` (floating-shell heal); `CameraDirector` hide + FOV (EVAL-SAT-S #23) |
| C7 | Rift 2.0: real 3D, adaptive size, block-display assembly | DONE | `RiftRenderer` 5-shell prism; adaptive `max(footprint·√2·1.15,4)`; `StructureFlightFx` displays; POL-F #7 crawl/billboard fixed (`RiftRenderer.java:533-563`) |
| C8 | Fog storms: spheres, interior, explode, better reward | **PARTIAL** | Spheres + `Sphere` uniform in `storm_interior.fsh` + `StormRegistry.explode` all wired, **but `eclipse:storm_heart` is still not a registered item** — `FogTyrantEntity.java:1349-1365` detects the missing registration and substitutes 6 shards |
| C9 | Ferryman spawns out of the door | DONE | EVAL-SAT-F item 10 SATISFIED |
| C10 | Ferryman rework: door→ship→arena + spectator ship | DONE | EVAL-SAT-F item 10 SATISFIED |
| C11 | Sky launcher to the End disc | DONE | `SkyLauncher` registers `StructurePendingRegistry.registerAsyncPlacer`, enqueues on `EndFightState.materializationComplete()` |
| C12 | End disc: no snow | DONE | EVAL-SAT-F item 11 SATISFIED |
| C13 | Dragon victory island shatter | DONE | `EndShatterSequence`: islets + `GRACE_TICKS = 120*20` slow-fall/no-fall window; `EndCityKit` shulker structures |
| C14 | Adaptive day texts (day 13) | DONE | `TimelineService.titleDone` + `DayTextConditions.isDone` |
| C15 | Final credits + client close | DONE | EVAL-SAT-F item 12 SATISFIED; `CreditsSequence.stampBeach` via `BudgetedBlockWriter` |
| C16 | Frameless star-rift portal | DONE | `XboxPortal` "frameless rework", per-player open resync |
| C17 | Tutorial worlds: era immersion, one timer, more TUs | DONE | TU19/31/69/75 mapped (`XboxDimensions`); `XboxEraFx` console-era grade, `XboxHudSkin`, `XboxTimerLayer`, `XboxEraSounds`, XP/quests off via `XpGates`+`QuestEngine` (docs/XBOX_WORLDS.md §"Era immersion stack") |
| C18 | Backrooms event dimension | DONE | EVAL-SAT-F item 18 SATISFIED (operator-triggered by design) |
| C19 | Music actually plays | DONE | EVAL-SAT-F item 1 SATISFIED; regression guard `gametest/music/MusicAssetValidationTest` present |

## 4. PLAN-D — Systems (14/14 DONE)

| # | Item | Status | Evidence |
|---|---|---|---|
| D1 | Collections system | DONE | All 5 lanes fire (EVAL-DOPA-S lane trace); tier grants idempotent; toasts via `BottomToastQueue`. Crash-atomicity LOW edge open → see DOPA-S-06 |
| D2 | XP pacing gates + curve retune | DONE | `XpGates.allows` (pre-event, limbo, minigames, all xbox dims incl. backrooms/arena/epilogue); curve 90/1.55 |
| D3 | Contract debuffs window-scoped | DONE | `ContractModifierService` `expiresAtEpochMillis` + epoch sweep |
| D4 | Heart steal + safeguards + ceremony | DONE | `HeartTheftService`: verdict enum, pair cooldown `SavedData`, floor freeze, ceremony (title/announce/bell/shake/heart_burst) |
| D5 | Quests phase-aware + harder | DONE | v5 authored ladder + `requiresUnlock` + `CONFIG_VERSION 2` migration (`GoalConfig.java:46-58,170-231`) |
| D6 | Phase cadence + `/dev phase` | DONE | `RealtimeConfig.defaultConfig()` = `CadenceMode.INTERVAL`, 2.0 h; v2 migration regenerates old files; `DevPhaseCommands` |
| D7 | Mod checker rework | DONE | `AntiCheatCheck` allowlist truth, `allowContinueOnMismatch`, dev bypass; `BootstrapScreen` blur no-op |
| D8 | JSON hardening answer | DONE | `allowlistVersion` migration (`AntiCheatCheck.java:81-214`) + documented policy |
| D9 | Distributable `.mrpack` | DONE | EVAL-SAT-F item 20 SATISFIED |
| D10 | Wand FX rework + findable UI | DONE | `WandPowers` 13 path emitters; grayscale `wisp_white.png` shipped and used by 8 emitters; wand tab in skill tree (SAT-F item 15) |
| D11 | Rebirth service/state/API | DONE | `RebirthConfig` + `RebirthTests`; vitae shard shop price 20 (`ShardEconomy.java:85`) |
| D12 | Photon adoption | DONE | `PhotonBridge`: reflection-only (`Class.forName com.lowdragmc.photon...`), guards (`isLoaded`, `photonFx`, `!reducedFx`), 2 seams (`EclipsePayloads.handleQuasar`, `RiftFx`), silent no-op fallback; `.fx` assets deliberately not shipped (authored in-game, docs/BUNDLING.md) |
| D13 | `/dev lives give`, `/dev chunk regen` | DONE | `DevLivesCommands` (give/status), `DevChunkCommands` |
| D14 | Umbral shard economy | DONE | `ShardLedger`/`ShardPayouts.deliverOrQueue` (offline/dead queue + login flush); ◆N chips advertise income |

## 5. EVAL fix lists

### EVAL-POL-F (7 DONE, 3 MISSING)

| # | Fix | Status | Evidence |
|---|---|---|---|
| 1 | StormWall tangent-arc window drift | DONE | `StormWallRenderer`: `a0 = camAngle − halfArc + i·step`, `rot` folded into noise index only |
| 2 | Grayscale wisp sprite for wand emitters | DONE | `textures/particle/wisp_white.png` shipped; 8 emitter JSONs reference it |
| 3 | Curvature bend from ray elevation | DONE | `limbo.fsh:86-121` pure-ray `hd` (header documents the EVAL-POL-F #3 fix) |
| 4 | `storm_interior.fsh` sphere variant | DONE | `uniform float Sphere` mixes `desatTint`/`skySink` (lines 17,43-54) |
| 5 | `storm_shatter` own weight | DONE | `sounds.json:380-390`: layers `event/submerge` + `ambient/limbo_loop` under it, decoupled from `rift_slam` |
| 6 | Altar surge echo dedicated clock | DONE | `AltarVeilSky.java:384-404`: `skySurgeEchoTravel` monotonic 0→1, fires once, no park/retract |
| 7 | Rift arcs billboard + crawl | DONE | `RiftRenderer.java:533-563`: per-arc persisted drift ("genuinely CRAWL"), `emitBillboardSegment` camera-facing width |
| 8 | limbo.fsh: smoothstep facing, cap eps, wrap VoyageOffset | **MISSING** | `limbo.fsh:139` still binary `step(surfaceY + 0.5, CameraPos.y)`; line 134 `eps = 0.55 + dist·0.012` uncapped; `LimboAmbience.java:462-465` keeps the hourly jump ("one small jump per hour, like Time itself") |
| 9 | Credits white lines shadow-less | **MISSING** | `EclipseLoadingScreen.java:172,177` both lines still use shadowed `drawCenteredString` |
| 10 | DE micro-fixes | **MISSING** | `de_de.json`: "Ein Riss ächzt auf" (line 2045), singular "Mach dich bereit…" (line 1345), "Takedown(s)" (lines 1331-1337) all unchanged |

### EVAL-POL-S (5 DONE, 1 MISSING)

| # | Fix | Status | Evidence |
|---|---|---|---|
| S-01 | Event-dimension predicate covers v5 dims | DONE | `XpGates.isEventDimension` includes `BackroomsDimension.BACKROOMS`, `ArenaDimension.ARENA`, `CreditsSequence.EPILOGUE` (lines 85-87) |
| S-02 | Credits beach stamp budgeted | DONE | `CreditsSequence.stampBeach` → `BudgetedBlockWriter` (lines 79,814-839) |
| S-03 | Anti-cheat allowlist nested-id migration | DONE | `AntiCheatCheck` `allowlistVersion` union-migration, explicit "EVAL-POL-S #3" citations (lines 81-214,569-576) |
| S-04 | Chunk regen block/time budgeted | DONE | `ChunkRegen.tickBudgeted` + `WRITE_BUDGET_PER_TICK` |
| S-05 | Credits display sweep on load | DONE | `CreditsSequence.onEntityJoin` sweeps `eclipse_credits_wheel`/`eclipse_credits_flyer` tags |
| S-06 | Clear `PENDING_HEART_LOSSES` at server stop | **MISSING** | `LifecycleEvents` has `onServerStarted` but no `ServerStoppedEvent` handler; only the TTL prune (`LifecycleEvents.java:84`) — the cross-save leak on integrated servers within 1 h remains |

### EVAL-DOPA-F (4 DONE, 2 PARTIAL, 3 MISSING)

| # | Fix | Status | Evidence |
|---|---|---|---|
| 1 | Curve 150→90 + milestones {7,12,18} | DONE | `SkillCurve.Params.defaults()` 90/1.55; `MILESTONE_LEVELS = {7,12,18}` in `AdvancementXpBridge` + `LevelUpOverlay` |
| 2 | Rebirth 1.3/1.0, vitae 20, per-rebirth keepsake | **PARTIAL** | `RebirthConfig` 1.3/1.0 ✔, vitae shop 20 ✔ (`ShardEconomy.java:85`) — the per-rebirth keepsake (+1 kept node / cosmetic aura) does not exist anywhere |
| 3 | Boss shards fund rebirth lanes | DONE | `ShardPayouts.deliverOrQueue` 50/50 physical/personal + offline queue (FIX-ECON) |
| 4 | Quest reward chips "◆N · +XP" | **PARTIAL** | `S2CQuestStatePayload.QuestEntry.rewardShards` + "◆N" chips on `SidebarPanel`/`SidebarExpanded` ✔ — no `rewardXp` field, no "+XP" half of the chip |
| 5 | One shared bottom-toast queue | DONE | `client/hud/BottomToastQueue`; both `CollectionTierToast` and `ShardGainToast` enqueue into it ("Since EVAL-DOPA-F #5") |
| 6 | `contracts.json autoDaily → true` | DONE | `ContractConfig.defaults()`/`defaultJson()` both `autoDaily=true` |
| 7 | Heart theft: killer global cooldown + max-hearts freeze | **MISSING** | `HeartTheftService.Values` has only pair `cooldownMinutes`/`floorLives` — no `killerCooldownMinutes`; `LifecycleEvents.java:100-116`: a killer at `MAX_HEARTS` still drains the victim's Leben (gain denied, loss NOT frozen — the DOPA-S "sink" edge persists) |
| 8 | Day-1 quests: demote TEAM_ALL, minDay 2 | **MISSING** | `GoalConfig.java:546-549`: `d01_stone_age`/`d01_touch_altar` still `Scope.TEAM_ALL`; lines 873-876: `p_leaper`/`p_swimmer` `minDay` still 0 |
| 9 | Collections: cobble cap 1500, +1 SP to coal/timber T2/T3 | **MISSING** | cap plumbing exists (`CollectionsService.java:200-211`) but the default writer hardcodes `dailyCreditCap: 0` (`CollectionsConfig.java:418`) incl. cobblestone; coal T2/T3 = `tier(100,75,0)`/`tier(300,125,0)` — no SP moved |

### EVAL-DOPA-S (5 DONE, 1 MISSING)

| # | Fix | Status | Evidence |
|---|---|---|---|
| S-01 | Recipe locks at menu level | DONE | `CraftGateEnforcement` + `CraftingMenuMixin`/`RecipeBookMenuMixin`/`CrafterBlockMixin`; `RecipeGate.java:187-193` documents onTake as backstop only |
| S-02 | Durable pickup provenance | DONE | `AnalyticsService.isPickupCredited`/`markPickupCredited` with `PICKUP_CREDITED_TAG` (lines 330-367) |
| S-03 | Boss "shards" pay rebirth currency | DONE | boss payouts route through `ShardPayouts` personal delivery/queue |
| S-04 | `"award"` XP exemption | DONE | `XpGates` exemption set includes `"award"` (lines 32-53) |
| S-05 | Toast collision | DONE | `BottomToastQueue` single renderer/FIFO (same as DOPA-F 5) |
| S-06 | Collection tier crash atomicity | **MISSING** | claim + XP still live in `eclipse_collections.dat` vs `eclipse_skills.dat`, both merely `setDirty`; no `EclipseSavedData.flushOverworld`/journal in `CollectionsService` — normal-path safe, crash-torn saves can replay or lose a tier reward |

### EVAL-SAT-S — five highest-impact gaps (5/5 DONE)

| # | Gap | Status | Evidence |
|---|---|---|---|
| 1 | goals/quests never migrated | DONE | `GoalConfig` `CONFIG_VERSION 2` backup-and-regenerate (`migrateIfOutdated`) |
| 2 | Default cadence DAILY | DONE | `RealtimeConfig.defaultConfig()` = INTERVAL 2.0 h; v2 file migration regenerates |
| 3 | Boss shards: no offline queue | DONE | `ShardPayouts.deliverOrQueue` + `onPlayerLoggedIn` flush |
| 4 | Decree hash uses legacy strings | DONE | `DawnCeremony.resolvedGoalIds` hashes `GoalConfig.goalsForDay` (V5-FIXGUARD) |
| 5 | Legacy saves rebuild stronghold | DONE | `legacyStrongholdSelfHeal` explicit opt-in, default false |

Residual SAT-S notes carried, not counted as separate items: `storm_heart` unregistered (counted at C8), snow-recovery `recovered` flag persisted before the async sweep finishes (`FogStormSites.recoverSite` line ~282 — crash mid-sweep leaves a permanent partial scar; LOW).

### EVAL-SAT-F (20/20 DONE)

EVAL-SAT-F is itself a verification audit: all 20 sampled items (music, AY1, hearts naming, one countdown, loading-screen locale, EMI leaks, border kick, nether arrival, disc mobs, ferryman flow, end shatter/no-snow, credits+close, collections loop, heart steal, skill tree/rebirth/wand tab, sidebar TAB/pre-event, map spoiler, backrooms, Sonic0810 bypass, mrpack/Fabric-API answer) are recorded **SATISFIED** in that document and spot-confirmed above.

---

## 6. v4-era items (99 DONE, 1 PARTIAL)

| Item | Status | Evidence |
|---|---|---|
| Collection system | DONE | D1 above |
| Kill-contract debuffs hunt-window-only | DONE | `ContractModifierService` epoch-window scoping (D3) |
| Heart steal outside hunts | DONE | `HeartTheftService` + `LifecycleEvents` STEAL routing (D4) |
| Prank-round contract event + odds + dev commands | DONE | `ContractState.Mode` REAL/PRANK; 25 %/5 % roll ("already tuned", EVAL-DOPA-F); `/dev contract` start/stop/theft |
| Target's real MC head X-marked | DONE | `ContractRevealOverlay`: `SkinManager` face + blood-red X stamps |
| Wrong-kill punishments (both directions) | DONE | wrong killer 0.5× skills −20 % dmg + void next award; wrong victim −1 temp heart +35 % vs murderer (FINAL-DOPA-SOL §5 verified config) |
| Voice changer (pitch etc., command + dev) | DONE | `VoiceChangerPlugin` (`@ForgeVoicechatPlugin`, `MicrophonePacketEvent` DSP via `VoiceDsp`), `VoiceChangerCommands` + `DevVoiceChangerCommands` |
| Bestiary progressive unlocks by kills | DONE | `BestiaryTiers` knowledge tiers + "next entry at N kills" hints (`BestiaryTab`) |
| Purple hearts burst over hotbar on respawn | DONE | `PENDING_HEART_LOSSES` death→respawn handoff replays `heart_burst` |
| Classic blocks fully built | DONE | `classicblocks` package + provenance ledger (docs/XBOX_WORLDS.md) |
| More portal events (backrooms + minigames) | DONE | C18 backrooms + `MinigamePortal` + `PortalEventScheduler` |
| Wand (design, levels, effects, evolving model, craft, wizard, soulbind, dev, trading) | DONE | `eclipse_wand.geo.json` + renderer bone toggles per `wand_path`/`wand_level`; `WandPowers` (RISS blink/wave, GLUT stoss/welle fire, STERN funke/schauer star shower); recipe = 6 umbral shards + 2 diamond blocks + `wizard_catalyst`; `WizardService.isEnabled` + `/dev wizard`; `WandSoulbind` CONVERTS on pickup; `DevWandCommands`; `WizardOrinEntity` catalyst trade |
| Timeline AY1 | DONE | A4 |
| Altar offering naming + only current | DONE | A5 |
| Map quality + spoiler | DONE | A6 |
| Limbo repeating wave textures + infinite look + custom liquid | DONE | `limbo.fsh` world-anchored caustics, endless-horizon fade, real water mask |
| No artifact/sidebar pre-event | DONE | A12 + A8 |
| Main-menu settings removal | DONE | A3 |
| Quests context-aware + harder | DONE | D5 |
| Cutscene translation | DONE | lang parity + `ServerLang` |
| Cutscene render distance/chunk loading + player invisible | DONE | C6 |
| Level-5 start fix | DONE | level never stored: `SkillCurve.levelForXp(0)=0`, pure function of XP |
| Duplicate countdown removal | DONE | A7 |
| XP bar replacement | DONE | A9 |
| Spawn/altar protection | DONE | B10 |
| EMI runtime hiding (Create Connected etc.) | DONE | A16 + SAT-F item 6 |
| Bossbar animation | DONE | A10 |
| Border pushback earlier + 5 s slowfall | DONE | B9 |
| Portal event message only | DONE | SAT-S #14: opening broadcast reduced to "A portal has opened" |
| Leveling speed | DONE | DOPA-F 1 curve retune |
| Skill tree bigger + double-click | DONE | A14 |
| Locked slots no unlock display | DONE | A11 |
| 2 h phases + commands | DONE | D6 (INTERVAL default) |
| Tutorial world (bossbar, frames/chests, console filter, UI, old music/sounds, no quests/XP, legacy textures, water/lava/redstone normal, leave translated, TU19/31/69, TAB buff timers + width) | DONE | C17 stack; "console filter" = `XboxEraFx` console-ERA visual grade (`eclipse:xbox_era` Veil post pipeline); leave line translated (`XboxEventService.leaveLine` → `eclipse.xbox.enter.leaveline`); `SidebarExpanded` WIDTH 280 + buff timers |
| Timeline adaptation | DONE | C14 |
| Snow melting | DONE | `FogStormSites` biome-aware storm scar (B13 melt + snow/powder-snow scar palette) |
| Arena armor phase | DONE | `ArenaGame.giveKit` kit/armor equip |
| Minigame join protection | DONE | `MinigameService` death protection + ticket-based inventory safety |
| Sidebar off setting | DONE | `EclipseClientConfig.SHOW_SIDEBAR` + `SidebarMode` |
| Nether breach lightning | DONE | `BreachBuilder.java:140` real `LightningBolt` entities + thunder |
| Nether fall damage | DONE | SAT-F item 8 |
| Build protection near breach/hut | DONE | `LandmarkProtection`: breach crater, arrival chimney, observatory summit zones |
| Nether spawn in shaft | DONE | SAT-F item 8 arrival shaft |
| Nether hole fog | DONE | B7 fog veil: per-viewer smoke cadence at breach mouth (`BreachTransferService.java:126-130`) |
| Nether floor terrain | DONE | B6 |
| Nether quest | DONE | B8 |
| Disc mob spawning | DONE | B5 |
| Day-3 tasks | DONE | authored d03 goals (`GoalConfig` day-3 slate: iron gear, kinetics, 96 chunks) |
| World grow animation (shake/lightning/sounds/structures fly via block displays, player invisible, red frame removed) | DONE | `StructureFlightFx` tagged BLOCK_DISPLAY flights + `RiftRenderer` 3D tear + C16 frameless |
| /give names | DONE | B17 |
| Storm interior sphere + sounds | DONE | POL-F 4 + sphere-roar alias set (EVAL-POL-F §9 ✔) |
| Fog tyrant explosion + reward | **PARTIAL** | explosion + Fog Core + cloak trim + scaled shards + chest all wired; the advertised `eclipse:storm_heart` item is still unregistered → runtime 6-shard fallback (`FogTyrantEntity.java:1349-1365`) |
| Wand skill tree findable | DONE | wand tab (A14/D10) |
| 1 Leben = 2 hearts naming | DONE | SAT-F item 3 |
| Wand effects rework | DONE | D10 + wisp_white palette fix |
| Storm-phase full protection + day switch + no night credit | DONE | C5 |
| Bestiary translation | DONE | lang parity |
| Limbo death prevention + water rescue | DONE | C4 |
| Limbo ghost fix | DONE | `LivesApi.set` revival hook (SAT-S #21) |
| Dev lives command | DONE | D13 |
| All messages translated | DONE | 2 119/2 119 key parity, `ServerLang` per-recipient |
| Smooth loading fades | DONE | A2 |
| TAB menu global/side sections + 1 Heart grammar | DONE | A8 sections + singular handling (SAT-F items 3/16) |
| /dev chunk regen | DONE | B16 |
| Vanilla ore veins | DONE | B2 (documented deliberate deviations) |
| Structure air bubble | DONE | B3 |
| More dungeons + big caves | DONE | B12 |
| Snow re-set after storm | DONE | B13 (crash-mid-sweep edge noted) |
| More varied Veil effects | DONE | 51 quasar emitters + per-system grades (SAT-S #19 scan) |
| Altar skybox levels + stronger per-level ceremonies | DONE | `AltarVeilSky` tier ladder + ceremony surge ×3.2 + POL-F 6 echo fix |
| Rift size adaptive + 3D + block displays throw buildings | DONE | C7 |
| Villages in air | DONE | B4 |
| Umbral shards received | DONE | B14/D14 |
| Skill tree bigger incremental | DONE | A14 |
| Rebirth system | DONE | A13/D11 |
| New Decrees blocking | DONE | A15 |
| Ferryman dead-door → ship → arena → dimension + dead on spectator ship | DONE | C10 |
| End path launcher from mage mountain | DONE | C11 |
| Post-dragon island shatter + shulker structures + slowfall 120 s | DONE | `EndShatterSequence` (120 s grace) + `EndCityKit` live shulker guards |
| End biome no snow | DONE | C12 |
| Day-12 spawn | DONE | C6 `validatedReturnPosition` |
| Day-13 adaptive texts | DONE | C14 |
| Stronghold removal | DONE | B15 |
| Music playback | DONE | C19 |
| Final credits cutscene + game closes | DONE | C15 |
| Ferryman door stuck | DONE | C9 |
| Terracotta cliffs | DONE | `DiscTerrainFunction` terracotta/badlands outer ring |
| Cutscene FOV | DONE | C6 |
| Limbo sailing renderer + invisible in water | DONE | `limbo.fsh` VoyageOffset drift + submerged-camera caustic kill (`facing` gate) + `LimboHorizonShips` |
| Skill double-click | DONE | A14 |
| More blockdisplay animations | DONE | `StructureFlightFx` (SAT-S #24) |
| Main menu visuals (panorama/fog/logo transparency) | DONE | A3 (measured dither + feathered alpha, EVAL-POL-F §2) |
| mrpack/zip + Fabric API answer | DONE | D9 / SAT-F item 20 |
| Mod checker unknown-mods fix | DONE | D7 allowlist truth + `allowContinueOnMismatch` |
| Blurry screen | DONE | `BootstrapScreen.renderBlurredBackground` no-op |
| Sonic0810 rights | DONE | SAT-F item 19 dev bypass |
| Anticheat JSON security answer | DONE | D8 |
| EMI version bump | DONE | `build.gradle:143-148` EMI 1.1.24 |
| NeoForge loading screen | DONE | `EclipseLoadingScreen`/`BootstrapScreen` pipeline |
| Photon | DONE | D12 `PhotonBridge` |

---

## 7. Consolidated PARTIAL/MISSING register

1. **C8 / fog-tyrant reward — PARTIAL:** `eclipse:storm_heart` is still not a registered item; `FogTyrantEntity` substitutes 6 shards at runtime.
2. **DOPA-F 2 — PARTIAL:** rebirth retune + vitae price shipped, but no per-rebirth keepsake exists.
3. **DOPA-F 4 — PARTIAL:** "◆N" shard chips shipped on sidebar/TAB; no `rewardXp` payload field or "+XP" chip.
4. **DOPA-F 7 — MISSING:** no global per-killer cooldown; killer at `MAX_HEARTS` still drains the victim (loss not frozen).
5. **DOPA-F 8 — MISSING:** day-1 `TEAM_ALL` mains not demoted; `p_swimmer`/`p_leaper` `minDay` still 0.
6. **DOPA-F 9 — MISSING:** cobblestone `dailyCreditCap` still 0 (default writer hardcodes 0); no +1 SP moved to coal/timber T2/T3.
7. **DOPA-S-06 — MISSING:** collection tier claim + XP still tear across two SavedData files on crash (no flush/journal).
8. **POL-S-06 — MISSING:** `PENDING_HEART_LOSSES` is not cleared on `ServerStoppedEvent` (TTL prune only) — integrated-server cross-save visual leak remains.
9. **POL-F 8 — MISSING:** `limbo.fsh` facing cut still binary `step`; `eps` growth uncapped; `VoyageOffset` hourly wrap jump kept.
10. **POL-F 9 — MISSING:** credits-white lines still drawn with shadow (`drawCenteredString`).
11. **POL-F 10 — MISSING:** DE micro-fixes ("Ein Riss ächzt auf", singular "Mach dich bereit…", "Takedown(s)") all unapplied.
