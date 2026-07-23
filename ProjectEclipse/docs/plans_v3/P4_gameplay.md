# P4 — Gameplay Systems & Progression (plans_v3)

Planner: **P4** (one of six parallel planners). Scope: real-time day clock, goal/quest system,
skills + skill tree, analytics, daily awards, altar offerings v2, recipe gating, revive rework,
glitched-mob heart path, villager restrictions, advancements, logout ghosts, day-1 containment,
spawn protection v2, voice mute, timed buffs, scoreboard data, event-start disc assignment.

Repo facts (verified 2026-07): NeoForge **21.1.238**, MC **1.21.1**, Java 21, project
`/workspace/ProjectEclipse`, mod id `eclipse`, package `dev.projecteclipse.eclipse`. Build =
`./gradlew build`; smoke = `runServer` + RCON (port 25575, password `eclipsedev`, see
`AGENTS.md`); gametests enabled for namespace `eclipse` in every run config **including a
ready `gameTestServer` run config** (`./gradlew runGameTestServer`) — currently zero gametests
exist; this plan introduces them.

---

## GLOBAL RULES FOR ALL P4 WORKERS (copy into every worker prompt)

1. **NEVER edit** `admin/EclipseCommands.java`, `assets/eclipse/lang/en_us.json`,
   `assets/eclipse/lang/de_de.json`, or `EclipseMod.java`. New commands go in NEW classes
   (e.g. `skills/SkillCommands.java`) registered via your own `@EventBusSubscriber` +
   `RegisterCommandsEvent`, under a NEW root (`/eclipse-skills`, `/eclipse-rt`, …, perm 3) so
   the existing `/eclipse` tree is untouched. All user-visible strings (en **and** de) go to
   `docs/plans_v3/langdrop/<worker-id>.json` in the shape
   `{"en": {"key": "text"...}, "de": {"key": "text"...}}` — the orchestrator merges them into
   the real lang files after all waves.
2. **No EclipseMod wiring needed** — verified: all P4 systems self-register via
   `@EventBusSubscriber(modid = EclipseMod.MOD_ID)`; new items/sounds/attachments go into the
   already-registered `registry/Eclipse*.java` classes (owned exclusively by worker P4-A1);
   SavedData needs no registration; NeoForge auto-scans `@GameTestHolder` classes. If you
   believe you need an `EclipseMod.java` change, STOP and list it in your final message
   instead of editing.
3. **File ownership is exclusive** — the matrix in §3.0 is law. If two workers would touch a
   file, the design is wrong; escalate instead of editing.
4. **Persistence is per-save**: every new persistent state is a `SavedData` obtained via
   `server.overworld().getDataStorage().computeIfAbsent(...)` (pattern:
   `core/state/EclipseWorldState`) or a chunk `AttachmentType` — both die with the save by
   construction. **Known bug class in this repo: static fields leaking across saves** (a
   singleplayer relaunch reuses the JVM). Every service with statics MUST reset them in a
   `ServerStoppedEvent` handler (existing pattern: `UnlockState.onServerStopped`,
   `SanctumProtection.onServerStopped`, `ShardEconomy.onServerStopped`). Add a
   `// statics reset on ServerStopped` comment next to each static and a handler that clears
   ALL of them.
5. **Config-driven + hot-reloadable**: every knob lives in `config/eclipse/<file>.json`
   (created with defaults on first run, pattern `EclipseConfig.loadOrCreate`). Register a
   reload hook via `core/config/ReloadHooks.register(...)` (created by P4-A1; `/eclipse
   reload` → `EclipseConfig.reload()` → `ReloadHooks.runAll()`). Balance content that must
   ship with the event ALSO goes into the tracked `run/config/eclipse/<file>.json` (that
   directory is the live event server's config and IS committed).
6. **Performance budget**: no per-tick scans proportional to blocks or chunks. Event-driven
   first; polls at ≥ 20-tick cadence and O(online players) only. One shared
   `BlockEvent.BreakEvent`/`EntityPlaceEvent` subscriber (analytics) fans out via
   `core/signal/EclipseSignals`; do NOT add your own break/place subscribers.
7. **Feedback style**: action bar + sounds, never chat — EXCEPT the two explicitly chat-based
   features (skill proc line with clickable disable, R3; award/ghost flows are overlay/payload
   driven). Anonymity is sacred: no payload or log line may leak player NAMES to clients
   except the single ghost-hit reveal (R12).
8. **Testing**: every worker ships (a) pure-static "core math" methods for its decisions and
   (b) NeoForge gametests under `src/main/java/dev/projecteclipse/eclipse/gametest/<area>/`
   (`@GameTestHolder(EclipseMod.MOD_ID)`, `@PrefixGameTestTemplate(false)`, empty structure
   `eclipse:gametest.empty` — P4-A1 provides the shared empty-structure nbt + a reference
   test). `./gradlew runGameTestServer` must pass. Plus the RCON smoke commands listed per
   package. `./gradlew build` green before commit.
9. Mains/sides/personal goal text, offering names, award category names: **en + de** always
   (see rule 1). Server → client text that must not be datamineable ships as LITERAL en/de
   string pairs in payloads (existing precedent: `days.json` titles), NOT as lang keys.

---

## 1. CURRENT-STATE AUDIT

### 1.1 Day/time pipeline (what exists)

- `core/state/EclipseWorldState` (SavedData `eclipse_world_state.dat`, overworld storage):
  `day` (int, default 1), `altarLevel`, `milestoneProgress` (free-form String→long map used
  as a reserved-key scratchpad by many systems), banned set, shard pool, boss flags,
  `nextPhaseEpochMillis`/`phaseScheduledAtEpochMillis` (W14 scheduler), stage/growth cursors.
- `progression/DayScheduler`: **days are manual by default.** `setDay(server, day)` is the
  single write path: persists day, broadcasts `S2CDayStatePayload(day, altarLevel,
  goals:List<String>)`, bell cue, `AnnouncementService.onDayChanged` (typewriter + unlock
  diff + timeline rebroadcast), `WorldStageService.applyDayTriggers` (ring expansion for
  `day:N`/`final_day` stages — **this is "the expansion sequence"** and is idempotent, takes
  max stage), `SundialPlaza.onDayChanged`. Optional `dayAutoAdvance` (general.json, default
  false) advances once per real-world day at `dayAutoAdvanceTime` (`LocalTime`,
  server-local!) — polled every 100 ticks; dedup via reserved milestone key
  `scheduler:last_auto_advance_epoch_day`.
- `devtools/PhaseScheduler`: one-shot wall-clock schedule (`/eclipse schedule next
  <ISO|+NhNNm>`), persisted as epoch millis in EclipseWorldState, drives ONE global purple
  countdown bossbar (theme `day` via `S2CBossbarStylePayload`), fires `DayScheduler.setDay(day+1)`,
  supersedes `dayAutoAdvance`.
- **What breaks with real-time days**: (a) there is no persistent "day started at" anchor —
  only a one-shot schedule; after it fires nothing re-arms, so a 14-day arc needs 13 manual
  re-schedules; (b) no catch-up: if the server is down across the boundary, `PhaseScheduler`
  fires once on next boot (good) but multi-day outages advance only 1 day; `dayAutoAdvance`
  advances at most once per real day; (c) no pause/add/reduce API and no client-visible
  countdown other than the bossbar text; (d) `dayAutoAdvanceTime` is server-local
  `LocalTime.now()` — not timezone-explicit, DST-fragile; (e) `/eclipse day set` clamps to
  1..14 via the command tree (fine), but nothing coordinates "end-of-day" work (awards,
  offering resolution) BEFORE the increment; (f) three competing advance paths
  (manual/auto/scheduler) with subtle interplay warnings.

### 1.2 Goals (what exists)

- Goals are **plain strings** in `days.json` (`EclipseConfig.DayPlan.goals`, exactly 3/day in
  practice, ≤8 hard cap from the bitmask). Progress = per-player int attachment
  `eclipse:goal_progress` encoded `(day << 8) | bitmask` (self-invalidating on day change).
- `progression/GoalTracker`: `complete(player, index)` is the only write; announces first
  completion per (day,index) via reserved key `goal_announced:<day>:<i>`; day-1 completion
  index 2 seeds 2 umbral shards to everyone. **Auto-detection is a hardcoded `switch (day)`**
  over the DEFAULT arc (altar proximity poll day 1, nether dimension-change day 2, Herald
  hooks day 7, pearl/altar counters day 8, shard pool day 9, hearts day 11, dragon day 13,
  ferryman day 14). A rewritten days.json silently degrades those to manual goals. Everything
  else: `/eclipse goals tick <player> <index>`.
- Editor: `/eclipse goals edit` → `S2COpenGoalEditorPayload(daysJson)` →
  `devtools/client/GoalEditorScreen` (edits goal STRINGS + unlock keys) →
  `C2SConfigEditPayload` → `devtools/ConfigEditor.handleEdit` (perm 3, ≤64 KiB, normalizes,
  writes `days.json`, `EclipseConfig.reload()`, re-broadcasts).
- No side quests, no personal quests, no reward hooks, no i18n (strings are English-only
  literals shipped server-side on purpose — anti-datamine).

### 1.3 Altar / milestones / economy (what exists)

- `ritual/AltarBlockEntity`: right-click w/ item = **milestone deposit** (consumes toward
  `EclipseConfig.milestone(level+1)` costs; progress under reserved keys
  `altar_level_<n>[:item_id]`; completion raises `altarLevel`, global cue). Sneak+empty hand =
  heart sacrifice (2-click confirm, −1 life → 1 `heart_fragment` drop). Sigil cycle/confirm →
  `ReviveRitual`. Lure/shard sneak-hints.
- Milestones (run/config + defaults identical): L1 16 iron → `create`; L2 16 gold →
  `simulated`; L3 8 diamond → `aeronautics`; L4 herald core + 16 pearls → `sable`; L5 2
  netherite → `end`. **Too easy for 20-30 players** (single afternoon of pooled mining
  clears L1-L3); no per-player participation, no daily cadence — one player can solo-feed it.
- `economy/ShardEconomy`: personal balance = attachment `eclipse:shards`; team pool in world
  state; bank = sneak-right-click altar with `umbral_shard` (whole stack); browse = sneak-look
  (action-bar carousel, 1 s cadence); buy = sneak-punch. Offers hardcoded (dowser 4, compass
  8, vitae 12, pick 12, blade 16, Eclipse's Favor 16 pooled, Supply Beacon 24 pooled).
  `SupplyBeacon.drop(server)` exists and is admin-invokable (`/eclipse supply drop`).
- **No per-player daily offering, no secret item values, no anti-copy mechanic, no daily
  winner.**

### 1.4 Lives / hearts / revive (what exists)

- `LivesApi` on attachment `eclipse:lives` (default 5); `hearts/HeartsService` projects lives
  → transient MAX_HEALTH modifier, `MAX_HEARTS = 7` cap already exists. Death: −1 heart, killer
  +1 (cap 7, +1 more with umbral blade), grave with drops, ban at 0 (`lives/BanService` →
  adventure ghost in limbo, glowing, ghost team). `economy/VitaeShardItem` = +1 heart
  (hold-to-use, cap 7) — currently shop-bought for 12 shards.
- `ritual/ReviveRitual`: 3-minute tick ritual at the altar, red bossbar, confirmer leash 16
  blocks, success → `BanService.unban` (1 heart, overworld spawn). Sigil recipe
  (`data/eclipse/recipe/revive_sigil.json`): 3 heart fragments + 4 netherite + nether star +
  dragon breath — **nether star + dragon breath are unobtainable most of the event**, so in
  practice revive = altar heart sacrifice × 3 by donors, then late-game items. Requirement 8
  replaces the fragment source (self "heart extractor") and re-costs the recipe.

### 1.5 Timeline/announcements/HUD (what exists)

- `timeline/TimelineService` builds anonymized entries (future = hidden) from days.json +
  milestones; synced at login + day/altar change. `timeline/AnnouncementService` announces
  day changes, unlock-key diffs, altar levels, stage completions;
  `announceGoalCompleted(server, rawText)`.
- `client/hud/SidebarPanel` renders ENTIRELY from `ClientStateCache` (lives, day, altar,
  goals+ticks) **plus a client-computed online count** (`getConnection().getOnlinePlayers()
  .size()`) — requirement 18 removes that row (P3 renders; P4 provides replacement data).
- Payload registrar `network/EclipsePayloads` (version "2"); login sync pushes lives/day
  state/goal progress/milestones/timeline/stages/border/cutscene library.

### 1.6 Voice / anonymity / misc (what exists)

- `voice/EclipseVoicePlugin` (`@ForgeVoicechatPlugin`, compileOnly `voicechat-api:2.6.20`
  already in build.gradle): cancels `MicrophonePacketEvent` when `VoiceMuteApi.isMuted`
  (10-min entry mute via `first_overworld_join` attachment + persistent per-player
  `forceVoiceMuted` set in world state; `/eclipse voicemute <player> on|off` exists). **No
  global mute.**
- Anonymity: chat/command/tab/nametag/skin suppression (mixins + `TabListHider`,
  `NameTagHider`, `AbstractClientPlayerMixin` forces the eclipse skin). `announceAdvancements
  = false` and `showDeathMessages = false` are FORCED every server start in
  `lives/LifecycleEvents.onServerStarted` — requirement 11's "verify" is ✔; keep the forcing.
- `worldgen/structure/SanctumProtection`: r=16 around the altar — break/place cancel, explosion
  block-strip, hostile natural-spawn suppression, ops (perm ≥3) exempt. **No PvP block, no
  fluid/minecart/TNT-specific rules, no mob-grief block, radius far smaller than "whole spawn
  island", no fall-damage exemption at the island edge.**
- `worldgen/stage/WorldStageService.addListener((level, profile, fromStage, toStage) -> …)` —
  the ring-commit listener P4 uses for "newly expanded areas" (R9).
- No custom advancements exist (`data/eclipse/advancement/` absent). No villager restrictions.
  No logout ghosts. No containment. No recipe gating beyond namespace ModGate + workstation
  locks (`progression/ModGate`, `progression/PhaseInventoryLock`). No skills/XP, no analytics,
  no awards, no timed buffs.

### 1.7 Testing baseline

- **Zero automated tests** today (AGENTS.md: "No text-based tests"). But: gametest namespaces
  are enabled in all run configs and `gameTestServer` run config exists → NeoForge gametests
  are the sanctioned headless harness. RCON smoke path documented. P4's domain (math, state
  machines, JSON schemas, event-driven counters) is the most testable in the mod — every
  worker package below has gametest acceptance criteria.

---

## 2. DESIGN

Cross-cutting primitives first (§2.0), then per requirement R1–R19.

### 2.0 Cross-cutting primitives (worker P4-A1)

**`core/config/ReloadHooks`** — `public static void register(String name, Runnable hook)`,
`runAll()`; called at the END of `EclipseConfig.reload()` (one-line insertion — the only
EclipseConfig.java change in all of P4; file owned by A1). Hooks must be idempotent and
exception-isolated (one failing hook logs and continues).

**`core/signal/EclipseSignals`** — server-side static multicast (plain
`CopyOnWriteArrayList` of listeners, server thread only; NOT the NeoForge bus — these are
intra-mod, high-frequency, and we want explicit ordering). Events fired exactly once per
underlying game event by the SINGLE owning subscriber:

| Signal | Fired by (owner) | Consumed by |
|---|---|---|
| `naturalBlockMined(player, state, pos)` | analytics (owns `BlockEvent.BreakEvent`) | skills XP, goals, buffs (double ore), awards via analytics |
| `blockPlaced(player, state, pos)` | analytics (owns `EntityPlaceEvent` fan-in) | goals, analytics |
| `mobKilled(player, LivingEntity victim)` | analytics (owns `LivingDeathEvent` fan-in for non-player victims) | skills, goals, glitch drops |
| `playerDeath(victim, killerOrNull)` | analytics (listens after `lives/LifecycleEvents`) | skills (negative XP), analytics |
| `itemCrafted(player, stack)` / `itemSmelted(player, stack)` | analytics | skills, goals, recipe-gate audit |
| `chunkExplored(player, chunkPos)` / `biomeVisited(player, biomeId)` | analytics sampler | skills, goals |
| `altarDeposit(player, itemId, count, purpose)` (`purpose ∈ MILESTONE, OFFERING, SHARD_BANK`) | offerings worker (altar block entity) | analytics, goals, skills |
| `dayRollover(server, endedDay, newDay, Phase PRE/POST)` | realtime worker (inside `DayScheduler.setDay`) | awards (PRE), offerings resolve (PRE), goals re-roll (POST), recipe gate refresh (POST), sidebar sync (POST), analytics day cut (PRE) |
| `questCompleted(player, GoalSpec, scope)` | goal engine | skills (reward XP), analytics |
| `skillLevelUp(player, newLevel)` | skills | sidebar sync, advancements (via criteria trigger) |

Listeners registered in each system's `ServerStartedEvent` (guarded by an
`AtomicBoolean` like `AnnouncementService.STAGE_LISTENER_REGISTERED`); listener LISTS cleared
on `ServerStoppedEvent` by EclipseSignals itself.

**New registry entries** (all in A1; behavior classes owned by feature workers per §3.0):

- Items (`registry/EclipseItems`): `heart_extractor` (class
  `ritual/HeartExtractorItem`), `glitch_shard` (plain `Item`, rarity EPIC, max 64).
  (`heart_fragment`, `vitae_shard`, `revive_sigil` already exist and are reused.)
- Sounds (`registry/EclipseSounds`): `skill.proc`, `skill.levelup`, `award.sting`,
  `offering.accept`, `ritual.extract` (+ tiny placeholder .ogg per repo convention, en/de
  subtitles via langdrop).
- Attachments (`registry/EclipseAttachments`): **one** new CHUNK attachment
  `placed_blocks` (`AttachmentType<PlacedBlockData>` with codec, no copyOnDeath — chunks),
  data class `analytics/PlacedBlockData` (A1 creates the shell: section-index →
  `long[64]` bitset map + codec; analytics worker owns the logic wrapper). No new player
  attachments — new per-player state lives in SavedData maps keyed by UUID so offline players
  are queryable (awards/analytics need this; attachments cannot be read for offline players).

**New network payloads** (records + registration + client stub handlers writing to
`client/ClientStateCache` fields, all A1; P3 consumes/replaces the stubs):

| Payload | Dir | Fields |
|---|---|---|
| `S2CDayClockPayload` | S2C | `day:int, boundaryEpochMillis:long, prevBoundaryEpochMillis:long, serverNowEpochMillis:long, paused:boolean, pauseRemainingMillis:long` |
| `S2CQuestStatePayload` | S2C | `day:int, entries:List<QuestEntry>` where `QuestEntry{id:String, kind:byte(0 main,1 side,2 personal), textEn:String, textDe:String, progress:int, target:int, done:boolean, teamScope:boolean}` |
| `S2CSkillStatePayload` | S2C | `level:int, totalXp:long, xpIntoLevel:int, xpForLevel:int, points:int, unspent:int, ownedNodes:List<String>, procMsgEnabled:boolean, secretMultiplierActive:boolean(always false on wire — never leak)` |
| `S2CSkillProcPayload` | S2C | `procId:String, magnitude:float` (client sound/flash; P3) |
| `S2CAwardRevealPayload` | S2C | `day:int, categories:List<Cat>` where `Cat{id:String, titleEn, titleDe, rewardTextEn, rewardTextDe, candidates:List<(UUID,long value)>, winners:List<UUID>}` |
| `S2CBuffStatePayload` | S2C | `active:List<Buff>` where `Buff{id, titleEn, titleDe, endsAtEpochMillis:long, magnitude:float}` |
| `S2CRecipeLocksPayload` | S2C | `lockedItemIds:List<String>, lockedRecipeIds:List<String>` |
| `S2CSidebarStatePayload` | S2C | `day:int, boundaryEpochMillis:long, paused:boolean, skillLevel:int, xpIntoLevel:int, xpForLevel:int, altarLevel:int, mainsDone:int, mainsTotal:int, sidesDone:int, sidesTotal:int, personalsDone:int, personalsTotal:int, buffIds:List<String>, shards:int` |
| `S2CGhostRevealPayload` | S2C | `ghostEntityId:int, ownerName:String, ticks:int` (THE only name on the wire) |
| `C2SSkillNodeBuyPayload` | C2S | `nodeId:String` (server re-validates cost/prereqs/perm-free) |

**New SavedData files** (each owned by its feature worker; all in overworld data storage —
per-save by construction): `eclipse_realtime`, `eclipse_quests`, `eclipse_skills`,
`eclipse_analytics`, `eclipse_awards`, `eclipse_offerings`, `eclipse_buffs`,
`eclipse_ghosts`, `eclipse_voice`, `eclipse_start_assign`.

**New config files** (`config/eclipse/`; loader class in the owning package; defaults
written on first run; hot-reload via ReloadHooks; authored event values additionally
committed under `run/config/eclipse/` by the content worker): `realtime.json`, `goals.json`,
`quests.json`, `skills.json`, `skilltree.json`, `awards.json`, `offering_values.json`,
`recipegate.json`, `glitch.json`, `buffs.json`, `protection.json`, `analytics.json`.

**Gametest scaffolding**: `gametest/GameTestSupport` (mock-player helpers, day-set helper,
`eclipse:gametest.empty` 1×1×1 structure nbt under
`data/eclipse/structure/gametest/empty.nbt`), one reference test proving the harness runs.

### 2.1 R1 — Real-time days (`progression/realtime/`)

**Model** — explicit persisted boundary (PhaseScheduler generalized), not derived-on-the-fly:

`RealtimeState` (SavedData `eclipse_realtime`): `armed:boolean`, `paused:boolean`,
`boundaryEpochMillis:long` (next advance instant), `prevBoundaryEpochMillis:long` (progress
origin for bars/spool), `pauseRemainingMillis:long` (frozen remaining while paused),
`lastAdvanceEpochDay:long` (monotonic guard), `manualOverride:boolean` (one-shot schedules).

`realtime.json`:

```json
{
  "zone": "Europe/Berlin",
  "boundaryTime": "18:00",
  "autoArmOnStartEvent": true,
  "catchUpMaxDays": 13,
  "clientSyncSeconds": 5
}
```

**Boundary math** (pure, testable): `RealtimeMath.nextBoundary(nowEpochMillis, zoneId,
localTime)` → next occurrence of `boundaryTime` in `zone` strictly after `now`
(`ZonedDateTime` — DST-correct: a boundary during the skipped hour resolves via
`ZonedDateTime.of(...)` normalization; test 2026-03-29 and 2026-10-25 Berlin transitions).

**Service** (`RealtimeDayService`, replaces the auto-advance half of `DayScheduler` and the
firing half of `PhaseScheduler`):

- Tick (every 100t, matching existing cadence): if `armed && !paused && now >=
  boundaryEpochMillis` → roll over.
- **Rollover sequence** (single choke point, also used by manual `/eclipse day set` going
  UP by exactly 1): fire `dayRollover(PRE, endedDay)` (awards compute, offerings resolve,
  analytics day-cut) → `DayScheduler.setDay(server, day+1)` (bell, announcements,
  `applyDayTriggers` ring expansion — untouched behavior) → set
  `prevBoundary=boundary; boundary=nextBoundary(now)` → fire `dayRollover(POST, newDay)`
  (quest re-roll, baselines, recipe-lock rebroadcast, sidebar sync) → broadcast
  `S2CDayClockPayload`. At `day >= EclipseConfig.maxDay()`: disarm (arc complete).
- **Catch-up** (ServerStartedEvent): while `armed && !paused && now >= boundary && day <
  maxDay && advanced < catchUpMaxDays`: run the rollover sequence with `catchUp=true` —
  PRE/POST signals fire per skipped day (awards for each missed day use whatever analytics
  exist), but announcements/cutscene side effects are suppressed except for the FINAL day
  reached (pass a `quiet` flag through a new `DayScheduler.setDayQuiet` overload;
  `applyDayTriggers` is cumulative-idempotent so terrain lands correctly in one sweep).
- **Dev API** (P5 surfaces commands; P4-B1 ships a minimal `realtime/RealtimeCommands`
  under `/eclipse-rt` for smoke): `arm()/disarm()`, `pause()` (freeze: store
  `pauseRemainingMillis = boundary - now`), `resume()` (boundary = now + remaining),
  `addMillis(±delta)` (shift boundary; clamp ≥ now+5s; broadcast a clock payload immediately —
  the OLD boundary is still in `prevBoundary`… no: keep `prevBoundary` as the bar origin and
  add the pre-shift boundary as a transient field in the payload broadcast so **P3 animates
  the spool** from old remaining → new remaining), `setBoundary(isoDateTime|+NhNNm)` (reuse
  `PhaseScheduler.parseSpec` — move parsing into `RealtimeMath`), `status()`.
- **Countdown UI**: keep the existing global bossbar EXACTLY as PhaseScheduler renders it
  (purple, theme `day`) but driven by RealtimeDayService; additionally P3 renders the sidebar
  countdown from `S2CDayClockPayload` (client clock offset = `serverNowEpochMillis -
  System.currentTimeMillis()` sampled at receipt).
- **Legacy interop**: `general.json dayAutoAdvance` → parsed but IGNORED with a one-time
  deprecation warning (pattern: `warnedBorderSizeDeprecated`). `PhaseScheduler` becomes a
  thin delegate (`scheduleNext` → `setBoundary` + `manualOverride=true`; `clear` → revert to
  schedule-derived boundary) so the untouchable `/eclipse schedule` subcommands keep working
  verbatim. `/eclipse day set` (also untouchable) still works: `setDay` detects
  out-of-band changes and re-anchors (`boundary = nextBoundary(now)`).
- Time-zone/skew hardening: `lastAdvanceEpochDay` (in `zone`) prevents double-advance if the
  wall clock jumps backwards (NTP); log WARN if `now` regresses > 60 s between polls.

### 2.2 R2 — Goal system rework (`progression/goals/`)

**Files of record**: `config/eclipse/goals.json` (per-day mains + sides), `config/eclipse/quests.json`
(personal pool). `days.json` keeps `day/unlocks/title/subtitle` and its legacy `goals` strings
purely as FALLBACK (a day missing from goals.json renders its days.json strings as `manual`
mains — zero-migration safety; ConfigEditor/day editor keeps working for unlocks/titles).

**GoalSpec schema** (one entry):

```json
{
  "id": "d03_iron_arsenal",
  "kind": "main",                 // main | side | personal
  "scope": "each_player",         // each_player | team_total | team_all
  "trigger": {
    "type": "collect_item",       // see registry below
    "target": "minecraft:iron_ingot",  // item/block/entity/biome/stat id OR #tag
    "count": 32,
    "naturalOnly": true,           // mine_block only: consult placed-block tracker
    "x": 0, "z": 0, "radius": 24,  // visit_location only
    "y": -32,                      // reach_depth only
    "statId": "minecraft:custom/minecraft:jump" // stat_threshold only
  },
  "reward": { "skillXp": 300, "shards": 0, "items": [ {"id":"eclipse:umbral_shard","count":2} ] },
  "text": { "en": "Forge 32 iron ingots", "de": "Schmiedet 32 Eisenbarren" },
  "weight": 1,                    // personal-pool draw weight
  "minDay": 0, "maxDay": 0        // personal only; 0 = any
}
```

**Trigger type registry** (`goals/TriggerType` enum + one detector class each; ALL detectors
are either signal-driven or ride the 20-tick poll — never per-tick):

| type | source | notes |
|---|---|---|
| `collect_item` | vanilla stat delta `ITEM_PICKED_UP` + `ITEM_CRAFTED` (baseline snapshot at assignment) | tags expanded at load |
| `craft_item` | `itemCrafted` signal | |
| `smelt_item` | `itemSmelted` signal | |
| `kill_entity` | `mobKilled` signal | target = entity id, `#tag`, or `any_hostile` |
| `mine_block` | `naturalBlockMined` signal | `naturalOnly` default true |
| `place_blocks` | `blockPlaced` signal | count of placements |
| `deposit_altar` | `altarDeposit` signal | filter by `purpose`/item |
| `visit_location` | 20t poll, squared-distance | O(players×activeLocationGoals) |
| `visit_biomes` | `biomeVisited` signal | count distinct |
| `explore_chunks` | `chunkExplored` signal | count new chunks |
| `reach_depth` | 20t poll on player Y | |
| `travel_distance` | analytics distance counter delta | |
| `breed_animals` | `BabyEntitySpawnEvent` (goal engine owns this one event) | |
| `stat_threshold` | vanilla `ServerStatsCounter` delta from baseline | generic escape hatch |
| `survive_night_no_damage` | MC-night window watcher + damage-flag reset | per MC night, any night that day |
| `skill_level` | `skillLevelUp` signal | personal quests |
| `manual` | admin/P5 command only | legacy fallback |

**Scopes**: `each_player` (per-player progress+completion), `team_total` (one shared counter;
everyone gets credit at target), `team_all` (complete only when every ONLINE player
individually satisfies it — the day-11 hearts pattern).

**Storage** (`QuestState`, SavedData `eclipse_quests` — replaces the `goal_progress`
attachment, which B2 stops writing): per day: per goalId → team counter; per (uuid, goalId) →
progress long + done flag; per uuid → assigned personal quest ids for that day + lifetime
completed-personal set (no repeats); per (uuid) → stat baselines `Map<statKey,long>` captured
at assignment (day start or login backfill).

**Assignment**: mains+sides from goals.json for the current day. Personal: 3 drawn from
quests.json pool, deterministic `seed = hash(worldSeed, uuid, day)` weighted-without-repeat
(excluding lifetime-completed) — deterministic means a relog/restart re-derives identically
even if SavedData was rolled back. Draw math in pure `QuestMath.draw(...)` (testable).

**Completion pipeline**: single `QuestEngine.complete(...)` (analog of `GoalTracker.complete`)
→ mark state → grant `reward` (skillXp via SkillsApi if present — soft-lookup so B2 compiles
without B3 at runtime order… both are same jar; just direct call), fire `questCompleted`
signal, re-send `S2CQuestStatePayload` to affected player(s), announce mains via existing
`AnnouncementService.announceGoalCompleted` (subtitle = literal `text` in server language?
No: announce with the payload's en text — the overlay renders literals; P3 may upgrade to
localized announcements later; document this seam). Sides/personals announce only to the
completing player (action bar + `skill.proc`-style chime), never globally.

**Anti-abuse**: `collect_item` uses pickup+craft stats (drop/re-pickup inflates PICKED_UP —
mitigate: use `max(craftDelta, pickupDelta)` not sum, and prefer `craft_item`/`mine_block`
for farmable targets in authored content; documented for the content worker).
`mine_block` honors the placed-block tracker (R4).

**Legacy bridge**: `GoalTracker` is retired in place — B2 rewrites it as a thin adapter:
`complete(player, index)` (used by `/eclipse goals tick`, untouchable command) maps index →
current day's main[index] manual-complete; `mask()` returns mains bitmask for the legacy
`S2CGoalProgressPayload` (kept for the artifact menu / old sidebar until P3 lands). All
hardcoded `switch(day)` detectors + shard-seed logic are DELETED (the day-1 seed becomes an
authored `deposit_altar`-triggered reward in goals.json content); Herald/Finale team hooks
(`onHeraldSummoned`, `onFinaleBegun` — called from ritual/boss code we don't own) become
signal-shims calling `QuestEngine.completeTeamBeat("herald_summoned" / "finale_begun")`,
which authored goals reference via trigger `manual` + `beatId` field (add optional
`"beatId": "herald_summoned"` to the trigger schema; engine listens for beats).

**Editor support (P5)**: `GoalConfig.validateAndNormalize(JsonElement) -> JsonElement`
public static (same contract as `ConfigEditor.normalizeDays`) so P5's reworked editor GUI can
round-trip goals.json safely; P4 does NOT touch `ConfigEditor`/`GoalEditorScreen`.

**Difficulty**: authored content (worker P4-B3) makes mains ~30-50% harder than current
strings (counts up per §3 B3 table); 3-5 sides/day; hidden = false for all (categories of
AWARDS stay secret, goals do not).

### 2.3 R3 — Skills + tree (`skills/`)

**SkillState** (SavedData `eclipse_skills`): per uuid → `totalXp:long`, `spentPoints:int`,
`ownedNodes:Set<String>`, `procMsgEnabled:boolean(default true)`,
`secretMultiplier:float(default 1.0)`, `lastLevelSeen:int`.

**Curve** (`SkillCurve`, pure): `xpForLevel(n) = round(baseCost * n^exponent)`, cumulative
`C(L)`; defaults `baseCost=20`, `exponent=1.3`, `softcapLevel=50`, `softcapMult=2.0` (cost
doubles past 50). With the default earn table (~600-800 XP/h active): **~L12 after 4 h**
(C(12) ≈ 2 650), L28-32 for 4 h/day by day 14, L48-55 for 8-10 h/day grinders (C(50) ≈
70 000). All four constants in `skills.json`; content worker tunes.

**Earn table** (`skills.json` — EVERY action listed with its value; hot-reload):

```json
{
  "curve": { "baseCost": 20, "exponent": 1.3, "softcapLevel": 50, "softcapMult": 2.0 },
  "procFeedback": { "sound": "eclipse:skill.proc", "chatLine": true },
  "xp": {
    "mine": { "default": 1, "#minecraft:coal_ores": 3, "#minecraft:iron_ores": 4,
              "#minecraft:gold_ores": 5, "#minecraft:diamond_ores": 12, "#minecraft:emerald_ores": 10,
              "minecraft:ancient_debris": 20, "#minecraft:logs": 1, "minecraft:stone": 0.5 },
    "kill": { "default": 5, "minecraft:zombie": 8, "minecraft:skeleton": 9, "minecraft:creeper": 10,
              "minecraft:enderman": 15, "minecraft:blaze": 14, "minecraft:wither_skeleton": 16,
              "eclipse:gazer": 20, "eclipse:umbral_stalker": 18, "eclipse:the_other": 40,
              "eclipse:herald": 400, "eclipse:ferryman": 600, "#eclipse:glitched": 60 },
    "exploreChunk": 5, "visitNewBiome": 40,
    "craft": { "default": 0.5, "minecraft:crafting_table": 2, "#minecraft:planks": 0 },
    "smelt": { "default": 1 },
    "trade": 10, "breed": 6,
    "altarDepositPerValuePoint": 2, "shardBankedEach": 3,
    "death": -50,
    "questMain": 0, "questSide": 0, "questPersonal": 0,   // 0 = use per-spec reward.skillXp
    "advancements": { "default": 50, "eclipse:herald_slain": 200, "eclipse:skill_25": 150 }
  }
}
```

Fractional values accumulate per player in a float remainder (int XP granted, remainder
carried) so `stone: 0.5` works without spam. Lookup order: exact id → tag (first match) →
`default`. Per-source daily soft-caps optional field `"dailyCaps": {"mine": 3000, ...}`
(anti-grind; default present, generous).

**SkillsApi** (server): `addXp(player, sourceKey, baseAmount)` — applies (a) buff multiplier
(`TimedBuffApi.multiplier("skill_xp")`), (b) per-player `secretMultiplier` (set via
`SkillsApi.setSecretMultiplier(uuid, f)` — persisted; **never synced, never logged at info
level**; P5 surfaces the command), (c) node bonuses; handles level-ups (sound
`skill.levelup`, +1 point per level, `skillLevelUp` signal, S2C resync). `getLevel(uuid)`,
`getTotalXp(uuid)`, `addPoints`, `resetTree(uuid)` (P5 dev command). Levels derived from
totalXp (never stored) so multiplier/HP edits are consistent.

**Proc feedback**: when a chance-node procs (double drop etc.): play `skill.proc` to that
player + IF `procMsgEnabled` a **chat** system line
`[✦] Doppelte Beute! (deaktivieren)` / `[✦] Double loot! (disable)` where `(disable)` is a
`ClickEvent.RUN_COMMAND "/skills procmsg off"`. `/skills` root (perm 0, new class
`skills/SkillCommands`): `procmsg on|off`, `info` (level/xp/points action-bar dump).
Admin root `/eclipse-skills` (perm 3): `xp add|set <player> <n>`, `mult set <player>
<factor>` *(P5 will surface/alias; ours is the reference implementation)*, `reload`.

**Tree** (`skilltree.json`, worker B4): ~21 nodes, 3 branches + spine; node schema
`{ "id", "branch", "cost", "requires": ["id"...], "title": {en,de}, "desc": {en,de},
"effect": { "type": "...", "value": x } }`. Effect types (each implemented as ONE hook in
`skills/SkillPerks`, values config-driven, all small — never OP):

| Node (default cost) | Effect type | Impl hook |
|---|---|---|
| S1 Awakened (1) | `vanilla_xp_pct +5%` | `PlayerXpEvent.XpChange` scale |
| S2 Attuned (2) | `skill_xp_pct +5%` | SkillsApi pre-multiplier |
| S3 Eclipsed (3) | `proc_chance_add +1%` (all chance nodes) | SkillPerks shared roll |
| U1 Night's Edge (1) | `melee_damage_night_pct +3%` | `LivingIncomingDamageEvent` (attacker perk) |
| U2 Reaper (2) | `double_mob_drop_chance 2%` | `LivingDropsEvent` duplicate (non-boss, natural spawns) |
| U3 Bulwark (2) | `post_kill_absorption 2♥/10s, 30s icd` | kill signal |
| U4 Shardseeker (3) | `bonus_shard_on_night_kill 3%` | kill signal, spawns 1 umbral_shard item |
| U5 Duelist (3) | `attack_speed_pct +2%` | transient attribute modifier |
| U6 Umbral Pact (4) | `night_event_kill_xp +50%` | SkillsApi (checks activeNightEvent) |
| T1 Prospector (1) | `mine_skill_xp_pct +10%` | SkillsApi source scale |
| T2 Fortune's Echo (2) | `double_ore_drop_chance 2%` (natural ores) | naturalBlockMined + loot re-roll |
| T3 Iron Stomach (2) | `hunger_drain_pct -5%` | scale exhaustion in a 20t sweep (read+rewrite `FoodData.exhaustionLevel` delta) |
| T4 Deep Delver (3) | `break_speed_pct +5% below y=0` | `PlayerEvent.BreakSpeed` |
| T5 Smeltmaster (3) | `smelt_double_xp_chance 5%` | itemSmelted signal |
| T6 Earthen Bond (4) | `bonus_raw_ore_chance 1%` | naturalBlockMined |
| V1 Islander (1) | `spawn_island_speed_pct +1%` | transient attribute while inside protection zone (R14 zone query) |
| V2 Wayfarer (2) | `explore_xp_pct +25%` | SkillsApi source scale |
| V3 Featherfall (2) | `fall_damage_pct -10%` | `LivingIncomingDamageEvent` fall type |
| V4 Soft Landing (3) | `no_fall_damage_below_blocks 6` | same hook |
| V5 Night Stride (3) | `night_speed_pct +2%` | transient attribute at night |
| V6 Cartographer (4) | `first_biome_bonus_xp 100` | biomeVisited signal |

Purchase: `C2SSkillNodeBuyPayload` → server validates unspent points + prereqs + node exists →
persist, resync, `skill.levelup` chime. (P3 owns the GUI; a fallback `/skills buy <nodeId>`
command ships for testing.)

**Advancement XP bridge** (R11 half): `skills/AdvancementXpBridge` subscribes
`AdvancementEvent.AdvancementEarnEvent`, filters namespace `eclipse`, grants
`xp.advancements[id|default]`; dedup is inherent (event fires once per player+advancement).

### 2.4 R4 — Analytics (`analytics/`)

**AnalyticsState** (SavedData `eclipse_analytics`): `Map<Integer day, Map<UUID,
Object2LongMap<String>>>` implemented as nested HashMaps (String→Long); serialized compactly
(per day: per uuid: key→varlong compound). Key namespace (bounded, documented):

- `kill:<entity_id>` and `kill_total`; `death`; `dmg_dealt`, `dmg_taken` (x10 fixed-point)
- `mine:<block_id>` (NATURAL only) and `mine_total`; `place_total`, `place_types` (distinct,
  via per-day per-player small id-hash set held in memory, count persisted)
- `craft_total`, `craft:<item_id>` (only for ids appearing in goals/awards configs — full
  per-id craft tracking is unbounded; the allowlist is built at config load), `smelt_total`
- `dist_cm` (position delta sampled 1/s, per-sample cap 100 m to drop teleports; only when
  grounded/swimming/elytra — all movement counts), `biomes` (distinct count; visited set per
  player stored once, not per day: `biomes_lifetime` set + per-day count), `chunks_new`
- `playtime_s` (1/s while online), `depth_min_y` (min Y reached, stored as `4096 - y` so
  "max" aggregation works), `breed_total`, `trade_total`
- `altar_value` (offering + milestone deposits × value points), `shards_banked`
- `quests_done`, `mains_done`, `sides_done`, `personals_done` (via questCompleted signal)

**Event ownership** (single subscriber each, fans out via signals): `BlockEvent.BreakEvent`
(natural check → tracker), `BlockEvent.EntityPlaceEvent`, `LivingDeathEvent` (ordered AFTER
lives logic — use `@SubscribeEvent(priority = LOW)`), `LivingDamageEvent.Post`,
`PlayerEvent.ItemCraftedEvent`, `PlayerEvent.ItemSmeltedEvent`, `TradeWithVillagerEvent`,
`BabyEntitySpawnEvent` (goal engine owns this one — analytics listens to its signal), 1 Hz
sampler for playtime/distance/biome/chunk/depth (O(online players), zero allocation on the
hot path — reuse a scratch `BlockPos.MutableBlockPos`).

**Placed-block tracker** (`analytics/PlacedBlockTracker`, THE anti-abuse primitive — reused
by skills T2/T6, buffs double-ore, goals `naturalOnly`, awards mining categories):

- Chunk attachment `eclipse:placed_blocks` → `PlacedBlockData`: `Int2ObjectMap<long[]>`
  section-index → 4096-bit bitset (64 longs), lazily allocated per section on first write;
  serialized as one `long[]` per non-empty section. Memory: only player-built sections pay.
- `markPlaced(level, pos)` on EntityPlaceEvent (players only, any dimension);
  `isPlaced(level, pos)` O(1); `clear(level, pos)` on BreakEvent after the natural check
  (so re-placing the same spot re-marks). Explosions/pistons do NOT update bits — accepted
  leak documented in §5 (an exploded placed block leaves a stale bit = at worst a natural
  block later at that exact pos is mis-flagged non-natural: fails SAFE, never mints XP).
- Worldgen/ring-growth writes never mark (they don't fire EntityPlaceEvent — verified:
  `RingGrowthService` writes `LevelChunkSection` directly).

**Query API** (P5 command surface + awards): `AnalyticsApi.value(day, uuid, key)`,
`top(day, key, n)` → `List<(UUID,long)>` sorted desc, `sumAcrossDays(uuid, key)`,
`keys(day)`, `onlineOrKnownUuids(day)`. Reference dump command `analytics/AnalyticsCommands`
(`/eclipse-analytics top <day> <key> [n]`, `dump <day> <player>`, `reload`).

`analytics.json`: sampler toggles, per-sample distance cap, craft-allowlist extras,
`retentionDays` (default 20 — never prunes a 14-day event).

### 2.5 R5 — Daily awards (`awards/`)

`awards.json` (server-side ONLY — never synced; categories stay secret until reveal):

```json
{
  "categoriesPerDay": 3,
  "minPlaytimeSeconds": 1800,
  "categories": [
    { "id": "most_kills",        "metric": "kill_total",  "order": "max", "weight": 10,
      "title": {"en":"Bloodiest Blade","de":"Blutigste Klinge"},
      "reward": {"skillXp": 400, "shards": 4}, "dayTags": ["combat"] },
    { "id": "mob_specialist",    "metric": "kill:$mob",   "order": "max", "weight": 6,
      "mobPoolByDay": true, "title": {"en":"$MOB Hunter","de":"$MOB-Jäger"}, ... },
    { "id": "most_mined",        "metric": "mine_total",  "order": "max", ... },
    { "id": "ore_baron",         "metric": "mine:$ore",   "order": "max", "orePool": ["minecraft:iron_ore","minecraft:deepslate_diamond_ore", "..."], ... },
    { "id": "master_builder",    "metric": "place_total", "order": "max", "weight": 12, "dayTags": ["build"] },
    { "id": "architect",         "metric": "place_types", "order": "max", "weight": 8, "dayTags": ["build"] },
    { "id": "marathon",          "metric": "dist_cm",     "order": "max", ... },
    { "id": "globetrotter",      "metric": "biomes",      "order": "max", ... },
    { "id": "industrialist",     "metric": "craft_total", "order": "max", ... },
    { "id": "furnace_lord",      "metric": "smelt_total", "order": "max", ... },
    { "id": "gladiator",         "metric": "dmg_dealt",   "order": "max", "dayTags": ["combat"], ... },
    { "id": "untouchable",       "metric": "dmg_taken",   "order": "min", "requiresPlaytime": true, ... },
    { "id": "devout",            "metric": "altar_value", "order": "max", "dayTags": ["altar"], ... },
    { "id": "banker",            "metric": "shards_banked","order": "max", ... },
    { "id": "quest_zealot",      "metric": "quests_done", "order": "max", ... },
    { "id": "deep_diver",        "metric": "depth_min_y", "order": "max", ... },
    { "id": "rancher",           "metric": "breed_total", "order": "max", ... },
    { "id": "cursed",            "metric": "death",       "order": "max", "booby": true, "reward": {"skillXp": 50}, ... }
  ],
  "dayThemes": { "7": ["combat"], "10": ["build"], "14": ["combat","altar"] }
}
```

**Selection** (`AwardMath.pick(seed, day, categories, themes)` — pure): weighted draw of 3
distinct categories; categories whose `dayTags` intersect `dayThemes[day]` get weight ×3;
`$mob`/`$ore` pools resolved from what was actually killed/mined that day (fallback: skip).
Seed = `hash(worldSeed, day)` so a restart between PRE and reveal cannot re-roll.

**Resolution** (on `dayRollover PRE` for `endedDay`): for each category: candidates = every
uuid with analytics that day AND `playtime_s ≥ minPlaytimeSeconds` (booby/min categories
especially); winners = all tied at the best value; **ties split the reward** (skillXp and
shards divided, rounded up, min 1; item rewards each). Rewards granted immediately if online
else queued in `AwardsState.pendingRewards` (granted at login). Persist
`AwardsState` (SavedData `eclipse_awards`): per day → chosen category ids + winners + values
(idempotence: a day already resolved never re-resolves — catch-up safe), pending rewards.

**Reveal**: broadcast `S2CAwardRevealPayload` right after PRE resolution (so it lands
together with the new-day announcement stack); P3 owns the roulette overlay (payload contains
everything: candidates with values for suspense, winner uuids, i18n literals). Anonymity: the
payload carries UUIDs only; P3 renders anonymized heads (the client already forces the
eclipse skin for everyone). Login replay: last resolved day's payload re-sent on login
(players offline at reveal see it once).

### 2.6 R6 — Altar offerings v2 (`offering/`, owns `ritual/AltarBlock*` edits)

**Gesture**: sneak-right-click the altar with ANY item that is not `umbral_shard` /
`revive_sigil` / `heralds_lure` (all three keep their existing sneak paths) = personal daily
offering. Two-click confirm (pattern: heart sacrifice): first click shows
`ritual.eclipse.offering.confirm` ("Offer <item>? This is final for today.") — second click
within 100t consumes exactly **1 item** (count 1 off the stack). One offering per player per
real day (`already offered` hint afterwards). Feedback: `offering.accept` sound + purple
particle puff + action bar `ritual.eclipse.offering.done` — **value NEVER shown**.

**Value table** (`offering_values.json` — server-side only, never synced):

```json
{
  "tiers": { "junk": 0, "common": 5, "useful": 15, "valuable": 40, "rare": 100, "epic": 250 },
  "byTag":  { "#minecraft:dirt": "junk", "#minecraft:logs": "common", "#minecraft:iron_ores": "useful" },
  "byItem": { "minecraft:iron_ingot": "useful", "minecraft:gold_block": "valuable",
              "minecraft:diamond": "valuable", "minecraft:diamond_block": "rare",
              "minecraft:netherite_ingot": "rare", "minecraft:netherite_block": "epic",
              "minecraft:ender_pearl": "valuable", "minecraft:totem_of_undying": "epic",
              "eclipse:heart_fragment": "epic", "eclipse:umbral_shard": "useful",
              "eclipse:herald_core": "epic", "minecraft:dragon_egg": "epic" },
  "default": "junk",
  "enchantedMultiplier": 1.5,
  "modifiers": { "renamedBonus": 0 }
}
```

`OfferingRules.value(stack, cfg)` (pure): tier lookup exact id → tag → default; ×1.5 if
enchanted (round down). Junk (dirt etc.) = 0 by default table.

**Anti-copy**: resolution at `dayRollover PRE`: group that day's offerings by
`BuiltInRegistries.ITEM` id; any id offered by ≥2 players → ALL those offerings score **0**
(the items are still consumed — the altar "rejects copies", flavor via next-day announcement).
Secrecy: per-offering values and the duplicate rule outcome are computed only at resolution.

**Winner**: highest non-zero value (ties: all winners); feeds (a)
`analytics altar_value` (already counted at deposit), (b) a FIXED extra award category
`"best_offering"` appended to that day's award reveal (4th slot, marked `fixed:true` in the
payload… simpler: include it as one of the payload categories; P3 renders order as given),
(c) `AnnouncementService.announce` line `announce.eclipse.offering.winner` (subtitle = the
ITEM name, not the player — anonymity).

**State** (`OfferingState`, SavedData `eclipse_offerings`): per day → uuid → {itemId, value
(computed at resolve), resolved flag}; per day winner record.

**Altar level rebalance** (content worker B3, run/config/eclipse/milestones.json — harder +
participation-gated):

- L1: 48 iron + 24 copper blocks? Keep item types vanilla-available: **48 iron_ingot + 32 coal**
- L2: **32 gold_ingot + 16 amethyst_shard**
- L3: **24 diamond + 8 emerald_block**
- L4: **1 herald_core + 32 ender_pearl + 16 obsidian**
- L5: **4 netherite_ingot + 1 dragon_head?** — dragon parts arrive day 13; keep pacing: **4
  netherite_ingot + 48 quartz block**. (Numbers are B3's to finalize; direction: ×2-3 current
  cost, multi-item so no single hoarder clears it.)

The `altar_level_<n>:<item>` multi-cost progress-key mechanic already supports all of this
with zero code change (verified in `AltarBlockEntity.progressKey`).

### 2.7 R7 — Recipe/tech gating (`progression/RecipeGate.java`)

`recipegate.json`:

```json
{
  "tiers": [
    { "unlockDay": 1, "locks": { "items": ["#eclipse:tier_diamond_gear", "#eclipse:tier_netherite_gear",
                                            "minecraft:enchanting_table", "minecraft:anvil"],
                                  "recipes": [] } },
    { "unlockDay": 5, "locks": { "items": ["#eclipse:tier_diamond_gear"], "note": "diamond gear frees on day 5" } },
    { "unlockDay": 10, "locks": { "items": ["#eclipse:tier_netherite_gear"] } }
  ]
}
```

Semantics: an item/recipe is LOCKED while `currentDay < unlockDay` of every tier still
listing it (i.e. each tier's list stays locked until its day). Ships two item tags (data):
`data/eclipse/tags/item/tier_diamond_gear.json` (diamond sword/pick/axe/shovel/hoe/armor +
jukebox? no — gear only) and `tier_netherite_gear.json` (+ smithing template). Enforcement:

- **Craft block**: `PlayerEvent.ItemCraftedEvent` → locked result → shrink to 0 + refund
  ingredients? (vanilla already consumed them) → instead ALSO cancel earlier:
  `RightClickBlock` on crafting table is allowed (workbenches gate exists separately); the
  reliable server point is ItemCraftedEvent shrink (ModGate precedent, items never minted) +
  container-sweep is NOT needed (obtaining a locked item legitimately, e.g. loot, stays
  usable — this gates CRAFTING only, per requirement "no diamond+ recipes").
- **Smithing**: same event covers smithing results (fires for smithing table takes).
- **EMI/recipe-viewer hiding**: broadcast `S2CRecipeLocksPayload` at login + every
  `dayRollover POST` + reload; P3/P5 implement the EMI plugin client-side against it.
- API: `RecipeGate.isItemLocked(server, itemStack)`, `lockedItemIds(server)` (for the
  payload), `RecipeGateMath.lockedAt(day, cfg)` pure for tests.

**Base building rewarded** (requirement 7 tail): covered via awards categories
`master_builder` (place_total) + `architect` (place_types) with `build` day-theme boosts —
kept simple deliberately; no structure-footprint scanning (perf).

### 2.8 R8 — Revive rework (`ritual/HeartExtractorItem` + recipe data, worker B8)

- **Heart Extractor** (`eclipse:heart_extractor`, uncraftable? craftable:
  `data/eclipse/recipe/heart_extractor.json` = 2 iron block + 1 amethyst shard + 1 flint —
  cheap tool, the COST is your heart): hold-to-use 48t (UseAnim.SPEAR), requires
  `LivesApi.get(player) >= 2` (never to 0), on finish: `LivesApi.add(player, -1)` +
  `HeartsService.apply` (automatic via LivesApi? verified: LivesApi.set calls apply — B8
  confirms), drop **2 × heart_fragment** into inventory, pain package: `WARDEN_HEARTBEAT` +
  `PLAYER_HURT` sounds, 3 s Wither I + 10 s Slowness II + heart-burst overlay
  (`S2CHeartBurstPayload(heartIndex)` reuse), Gazer watch if near altar. Item survives
  (durability 4? one-per-use tool: 4 uses then breaks).
- **Recipe rework**: `revive_sigil.json` becomes **4 heart_fragment + 4 gold_block +
  1 diamond_block** (obtainable from day ~3; expensive but pre-boss). The old
  nether-star/dragon-breath recipe is deleted (single path, keeps the handbook page simple
  for P3).
- **Dual path decision**: KEEP the altar heart-sacrifice (1 fragment per heart, worse rate
  than the extractor's 2 — the altar version stays as the "no extractor yet" fallback and
  for drama). KEEP `ReviveRitual` exactly as is (sigil + 3-min ritual + 1-heart return via
  `BanService.unban`). So: extractor = fragment faucet; sigil = revive item; ritual = the
  ceremony. Requirement "using it at the altar revives with 1 heart" is already the unban
  behavior (verified `BanService.unban` → `LivesApi.set(player, 1)`).
- Interfaces: P3 renders the recipe in the handbook + death/ghost UI; P6's ship door checks
  `EclipseWorldState.isBanned` — unchanged.

### 2.9 R9 — Glitched mobs → heart crafting (`glitch/`, worker B8)

P6 owns the entity variants/models/renderers; P1 flags ring geometry. P4 owns:

- **Contract with P6**: glitched variants are separate entity types (or variant flag) whose
  types are listed in entity tag `data/eclipse/tags/entity_type/glitched.json` (P4 ships the
  tag file; P6 adds its ids — tag files merge, but to keep single-writer: **P4 ships the tag
  referencing the agreed ids** `eclipse:glitched_zombie`, `eclipse:glitched_skeleton`,
  `eclipse:glitched_spider` — P6 must register exactly these; listed in §4).
- **Spawn-rate config** (`glitch.json`): `{"enabled":true, "chancePerHostileSpawn":0.04,
  "onlyNewRings":true, "newRingRealDays":3, "maxAlive":12, "minDay":3}`. **Spawn hook**:
  `glitch/GlitchSpawnService` subscribes `FinalizeSpawnEvent` (natural spawns only): if the
  spawn pos is in a "new ring" area and the roll passes → cancel + spawn the glitched
  counterpart (mapping table in glitch.json `"replacements": {"minecraft:zombie":
  "eclipse:glitched_zombie", ...}`) — soft lookup via registry id so B8 compiles/works even
  before P6's entities land (missing type = no replacement, logged once).
- **"Newly expanded" definition**: `GlitchSpawnService` registers a
  `WorldStageService.addListener` and records `(profile, toStage, epochMillis)` in its own
  small SavedData (`eclipse_glitch_rings` section inside `eclipse_ghosts`? no — own file
  `eclipse_glitch`): a position qualifies if `distFromCenter > radius(stage committed >
  newRingRealDays ago)` — i.e. inside rings committed within the last N real days
  (`StageRadii.radius(profile, stage)` gives radii; center from
  `EclipseWorldState.getBorderCenter*`).
- **Drops**: `LivingDropsEvent` for entities in `#eclipse:glitched` → add 1-2 `glitch_shard`
  (config `dropMin/dropMax`, Looting +1 max). Kill XP via the `#eclipse:glitched` skills
  entry (60).
- **Heart crafting**: recipe `data/eclipse/recipe/vitae_shard_glitch.json`: shaped —
  8 × glitch_shard around 1 netherite_ingot → 1 `vitae_shard` (existing item already does +1
  heart hold-to-use, **cap 7 enforced** in VitaeShardItem — verified). "Many resources" knob:
  B3 may raise to include gold blocks; recipe json is the tuning point.
- **Cap logic**: nothing new — `HeartsService.MAX_HEARTS = 7` is enforced at every add path.

### 2.10 R10 — Villager/trader restrictions (`villagers/VillagerRestrictions.java`)

- **No enchanted books ever**: `VillagerTradesEvent` (mod-bus, fires once per profession at
  setup): strip every `MerchantOffer`/listing whose result or template is
  `minecraft:enchanted_book` from ALL professions; `WandererTradesEvent` likewise (belt +
  braces — the wanderer is also spawn-blocked). Runtime double-net:
  `PlayerInteractEvent.EntityInteract` on villagers → after offers exist, filter
  `getOffers().removeIf(result is enchanted_book)` once per villager (idempotent, cheap).
- **No librarians**: no NeoForge event for profession acquisition in 1.21.1 → 100-tick sweep
  over LOADED villagers (`level.getEntities(EntityTypeTest.forClass(Villager.class), aabb?)`
  — no: iterate `level.getAllEntities()` is O(entities); instead use
  `ServerLevel.getEntities(EntityType.VILLAGER, alwaysTrue)` which is type-indexed): any
  `profession == LIBRARIAN` → reset `VillagerData` to NONE + `setOffers(null)` + poof
  particles (the villager re-picks a different PoI; the lectern is never claimed for long).
  Plus proactive: cancel the claim faster by ALSO clearing on the trade-open interact hook.
  Window of a librarian existing ≤5 s and it can never trade books (offer filter above).
- **No wandering trader**: `EntityJoinLevelEvent` → `WanderingTrader` or `TraderLlama` with
  natural spawn reason → `setCanceled(true)`; plus set gamerule-equivalent
  `doTraderSpawning`? (that's `GameRules.RULE_DO_TRADER_SPAWNING` — set false on
  ServerStarted, same pattern as LifecycleEvents' gamerules; join-cancel remains as the
  guard against spawn eggs? NO — eggs/commands stay allowed for devs: only cancel
  `MobSpawnType` natural-ish reasons; gamerule handles the scheduler).
- Config `protection.json` section `"villagers": {"blockLibrarian":true,
  "blockEnchantedBookTrades":true, "disableWanderingTrader":true}`.

### 2.11 R11 — Advancements (data + bridge)

- ~20 JSON advancements under `src/main/resources/data/eclipse/advancement/event/…`
  (1.21.1 singular path), custom tab rooted at `event/root` (icon: altar item, background
  deepslate). All `"announce_to_chat": false` + chat already globally off (verified §1.6);
  most later ones `"hidden": true` (anti-datamine: titles are lang keys — acceptable for
  advancements since they're milestone flavor, NOT the anonymized day arc; the truly secret
  content (awards categories, offering values) never ships client-side).
- Trigger with VANILLA criteria only (no custom criterion class needed — keeps B3 data-only):
  `inventory_changed` (first shard, fragment, sigil, glitch shard, vitae),
  `changed_dimension` (nether, end, limbo? limbo via location), `location` (altar proximity,
  y<-64 depth), `player_killed_entity` (gazer/stalker/the_other/herald/ferryman/glitched),
  `bred_animals`, `villager_trade`, `recipe_crafted` (extractor, sigil), `tick` +
  `player condition` where needed. Two skill-level advancements are granted CODE-side:
  `skills/AdvancementXpBridge.grant(player, "eclipse:event/skill_25")` via
  `server.getAdvancements().getAdvancement(...)` + `AdvancementProgress.award` on level-up
  signal (levels 10/25/40).
- Every completion grants skill XP via the bridge (§2.3) using `skills.json
  xp.advancements` (default 50; boss/milestone ones 150-300). Full list of 20 ids + criteria
  + XP in worker B3's table (content worker writes the JSONs; bridge is B4 code).

### 2.12 R12 — Logout ghosts (`ghosts/LogoutGhostService`)

- **Contract with P6** (P6 owns `entity/LogoutGhostEntity` + renderer: invulnerable=code
  here, no AI, translucent eclipse skin, slow bob): entity type id `eclipse:logout_ghost`,
  synched data: `OWNER_UUID`, `OWNER_NAME:String` (server-side NBT only — NOT synched;
  the name travels ONLY in the reveal payload), `REVEAL_TICKS:int` (synched, counts down,
  drives P6's glitch shader). P6 calls `LogoutGhostService.onGhostHurt(ghost, attacker)`
  from `hurt()` (always returns false damage).
- **Spawn**: `PlayerLoggedOutEvent` (skip: banned-in-limbo players, spectators, permission
  ≥3 in creative, players inside an active cutscene freeze): spawn ghost at
  position/yaw, `setPersistenceRequired`, record `GhostsState` (SavedData `eclipse_ghosts`:
  uuid → {ghostUuid, GlobalPos}). Ghost entity persists WITH the chunk (normal entity
  serialization — restart-safe for free).
- **Despawn**: `PlayerLoggedInEvent` → if `GhostsState` has an entry: if the chunk is
  loaded, discard entity; else load the chunk once (`level.getChunk(x,z)` synchronous single
  chunk — acceptable at login) then discard; always clear the record. Startup sweep: on
  ServerStarted, prune records whose owner is online (crash-window duplicates) — and orphan
  ghost entities self-discard on tick if `GhostsState` has no record (belt+braces; P6's
  entity calls `LogoutGhostService.isValid(ghost)` every 100t).
- **Reveal**: `onGhostHurt` → rate-limit 5 s per ghost → set `REVEAL_TICKS=60` + broadcast
  `S2CGhostRevealPayload(ghost.getId(), ownerName, 60)` to players within 32 blocks. **This
  is the ONLY place a real player name reaches clients** (P3 renders the glitch text; the
  existing anonymity mixins don't apply — the ghost is not a Player entity).
- Config (`protection.json` section `"ghosts"`): enabled, revealTicks, revealCooldown,
  dimensions allowlist (overworld+nether).

### 2.13 R13 — Day-1 containment (`progression/ContainmentService`)

- Active while `day ∈ realtime cfg containmentDays` (default `[1]`). Every tick (cheap,
  O(online)): overworld survival/adventure players with `y < bounceY` (config; default =
  disc underside — P1 provides the constant, interim default `-180`, see §4) get: velocity
  `set(vx*0.4, +2.8, vz*0.4)`, `fallDistance = 0`, `hurtMarked = true` (sync), flag in a
  per-player `bouncedUntilTick` map → while set, cancel fall damage
  (`LivingIncomingDamageEvent` FALL) for 5 s; fire the FX hook: send existing
  `S2CQuasarPayload(CONTAINMENT_BOUNCE, pos)` (A1 adds the emitter-id constant; P2 registers
  the actual purple-glitch emitter — until then QuasarSpawner's built-in fallback particles
  cover it, verified `spawnOrFallback`).
- Also blocks ender-pearl/elytra escape implicitly (they'd re-enter the y check). Later days:
  service inert (config list). Statics reset on ServerStopped.

### 2.14 R14 — Spawn protection v2 (rework `worldgen/structure/SanctumProtection.java` in place)

Zone becomes config-driven (`protection.json`):

```json
{ "spawn": { "radius": 96, "verticalFrom": -64, "verticalTo": 320,
             "noPvp": true, "noFluidPlace": true, "noVehiclePlace": true, "noMobGriefing": true,
             "noFallDamage": true, "edgeBandExtra": 16, "exemptPermission": 3, "exemptCreative": true } }
```

Center = sanctum altar pos (existing). Additions to the existing break/place/explosion/spawn
rules (all same-file, same hint style): PvP cancel (`LivingIncomingDamageEvent` when both
attacker+victim are players and EITHER is inside), bucket/fluid-place cancel
(`RightClickBlock` with `BucketItem` containing fluid + `BlockEvent.FluidPlaceBlockEvent`),
minecart/boat/TNT place cancel (RightClickBlock item checks + `EntityJoinLevelEvent` for
primed tnt from dispensers inside), mob-grief cancel (`EntityMobGriefingEvent` inside),
enderman pickup included therein; **no fall damage** inside radius+edgeBandExtra (supports
P2's edge auto-glide: P2 owns the glide motion/visuals; P4 owns the safety rule). Creative OR
perm≥3 exempt (currently perm-only — requirement adds creative). `isProtected(level,pos)`
stays public (skills V1 node + P2 query it). The old constant `RADIUS=16` becomes the
config default's floor for pre-config worlds.

### 2.15 R15 — Voice mute v2 (`voice/`)

- Add `VoiceState` (SavedData `eclipse_voice`): `globalMuted:boolean` (+ future room for
  channel rules). `VoiceMuteApi` gains `setGlobalMuted(server, boolean)`,
  `isGlobalMuted(server)`; `isMuted(server, player)` = entry ∥ per-player ∥ global.
  `EclipseVoicePlugin.onMicrophonePacket` already funnels through `isMuted` — zero plugin
  changes (verified). Per-player set stays in EclipseWorldState (existing, untouched).
- Reference commands `voice/VoiceCommands` (`/eclipse-voice global on|off`, `list`) — P5
  surfaces the polished command set on top of the API.
- API surface research note: Simple Voice Chat API 2.6.20 (compileOnly, present) events used:
  `MicrophonePacketEvent` (sender-side cancel = hard mute — correct primitive; already
  proven in-repo). No volume APIs needed for mute. Optional nicety (P5): notify muted players
  via action bar when they speak while muted — API has no "attempted speak" callback beyond
  MicrophonePacketEvent itself; throttle a hint per 10 s on cancelled packets (cheap,
  server-side counter).

### 2.16 R16/R17 — Timed server buffs (`buffs/`)

`buffs.json` definitions:

```json
{
  "maxActive": 3,
  "buffs": [
    { "id": "double_skill_xp",  "title": {"en":"Double Skill XP","de":"Doppelte Skill-EP"},
      "effect": {"type":"multiplier", "tag":"skill_xp", "value":2.0}, "defaultMinutes":30, "stack":"extend" },
    { "id": "double_ore_drops", "title": {"en":"Ore Surge","de":"Erz-Flut"},
      "effect": {"type":"multiplier", "tag":"ore_drops", "value":2.0}, "defaultMinutes":15, "stack":"extend",
      "note": "natural blocks only — consults PlacedBlockTracker" },
    { "id": "half_hunger",      "title": {"en":"Well Fed","de":"Wohlgenährt"},
      "effect": {"type":"multiplier", "tag":"hunger", "value":0.5}, "defaultMinutes":30, "stack":"extend" },
    { "id": "double_shard_finds","title": {"en":"Shard Rush","de":"Splitter-Rausch"},
      "effect": {"type":"multiplier", "tag":"shard_drops", "value":2.0}, "defaultMinutes":20, "stack":"extend" },
    { "id": "supply_rush",      "title": {"en":"Supply Rush","de":"Nachschub-Regen"},
      "effect": {"type":"periodic", "action":"supply_drop", "periodSeconds":600}, "defaultMinutes":30, "stack":"refuse" },
    { "id": "xp_magnet",        "title": {"en":"XP Magnet","de":"EP-Magnet"},
      "effect": {"type":"magnet", "radius":8.0}, "defaultMinutes":15, "stack":"extend" },
    { "id": "glitch_surge",     "title": {"en":"Glitch Surge","de":"Glitch-Welle"},
      "effect": {"type":"multiplier", "tag":"glitch_spawn", "value":2.0}, "defaultMinutes":20, "stack":"extend" }
  ]
}
```

- **`TimedBuffService`**: `BuffState` (SavedData `eclipse_buffs`): active list {id,
  endsAtEpochMillis, magnitude} — **epoch millis = restart-persistent countdown** (real time,
  consistent with R1). Tick (20t): expire, update ONE shared bossbar per active buff
  (PhaseScheduler bar pattern, theme `goal`; ≥2 buffs collapse into one bar cycling names —
  P3 may replace with sidebar rows from `S2CBuffStatePayload`), announce start/end via
  `AnnouncementService.announce` (style `unlock`).
- **`TimedBuffApi`** (the generic hook, R16's Xbox reward calls exactly this):
  `start(server, id, minutesOverride?, magnitudeOverride?) -> boolean`,
  `stop(server, id)`, `active(server)`, and the consumer side:
  `multiplier(server, tag) -> float` (product of active multiplier-buffs with that tag; 1.0
  default) + `isActive(id)`. Consumers wired in their own packages: skills (`skill_xp`),
  glitch (`glitch_spawn`), shard drops — **shard drop location**: night-mob shard drops
  live in loot/economy code P4 doesn't own? Verified: shard drops come from night mobs
  (economy) — B9 implements `shard_drops` as a `LivingDropsEvent` post-processor doubling
  `umbral_shard` ItemEntities in drops (works regardless of drop source, natural-mob-only
  guard). `ore_drops` doubling: naturalBlockMined signal → re-add matched ore drops
  (LOW-priority BreakEvent companion in B9 keyed off analytics' natural verdict — B9 listens
  to the SIGNAL, doubles drops via `getDrops` re-roll? simplest correct: subscribe
  `BlockDropsEvent` (Neo 1.21.1 has it) and duplicate ore-tag ItemEntities when
  `PlacedBlockTracker.isPlaced == false`).
  `hunger` ×0.5: same exhaustion-scaling sweep as skills T3 (B9 owns the buff variant; both
  multiply — combined via the shared `ExhaustionScaler` utility placed in A1 to avoid
  double-ownership… final: A1 ships `core/util/ExhaustionScaler` with a static
  `registerFactor(String key, Supplier<Float>)`; skills and buffs register factors; the
  scaler's own 20t sweep applies the product — single writer, no conflict).
  `magnet`: 20t sweep teleport `ExperienceOrb` within radius toward nearest player (bounded:
  `level.getEntitiesOfClass(ExperienceOrb.class, box-around-players)`).
  `supply_drop`: calls existing `SupplyBeacon.drop(server)` every period.
- Stack rules per def: `extend` (same id: endsAt += duration), `refuse` (already active →
  no-op false), cap `maxActive` total.
- Reference commands `buffs/BuffCommands` (`/eclipse-buffs start <id> [minutes]`, `stop`,
  `list`, `reload`) — P5 surfaces the Xbox-event flow calling `TimedBuffApi.start`.

### 2.17 R18 — Scoreboard/sidebar data (`hud/SidebarSyncService`, worker C1)

- Server assembles `S2CSidebarStatePayload` (fields §2.0) from: RealtimeState (day/boundary/
  paused), SkillsApi (level/xp), QuestState (done/total per kind), EclipseWorldState
  (altarLevel), TimedBuffApi (ids), ShardEconomy (balance). Sent: at login, on any input
  change (each source fires a cheap `SidebarSyncService.markDirty(player|all)`), coalesced to
  at most 1 send/second/player (dirty-flag pattern — NO periodic full broadcast).
- **Online count: removed from the data model** — P3 deletes the client-computed row
  (`SidebarPanel` reads `getConnection().getOnlinePlayers()`; P4 flags it in §4, P3 owns the
  render change). Nothing server-side ever ships an online count.
- Time-to-next-day rendered client-side from `boundaryEpochMillis` (clock-offset technique
  §2.1) so no per-second packets.

### 2.18 R19 — Event start / disc assignment (`start/StartAssignmentService`, worker C1)

- `StartAssignState` (SavedData `eclipse_start_assign`): uuid → discIndex; `assigned:boolean`.
- **Interface to P1**: P1's v3 disc layout must expose
  `List<BlockPos> startDiscAnchors(ServerLevel)` (P1 deliverable — from disc_map.json v3
  `startDiscs` section or generator constants). Until P1 lands, the service falls back to
  N points on a ring of radius `cfg.fallbackRingRadius` (default 64) around world spawn
  (top-of-heightmap), so it is testable standalone.
- API: `assignAll(server)` (deterministic: sorted uuids of all ONLINE players round-robin
  onto anchors; late joiners assigned at login if event started), `assignedAnchor(server,
  uuid)`, `teleportToAssigned(player)` (safe-Y via heightmap).
- **Hook**: P2 owns the reworked intro sequence and calls
  `StartAssignmentService.assignAll` + per-player `teleportToAssigned` at its
  teleport beat (today `limbo/StartEventCutscene` t=140 teleports everyone to shared spawn —
  P2's file; §4 interface). Fallback wiring so R19 works even if P2 slips: C1 subscribes a
  LOW-priority hook to the same tick the cutscene teleports (no — cross-file fragile;
  instead C1 ships `/eclipse-start assign|tp` reference commands and P2/P5 wire the call).

---

## 3. WORKER PACKAGES

### 3.0 Waves + exclusive file-ownership matrix

**Wave A** (lands first, alone): P4-A1. **Wave B** (all parallel after A1): B1-B9.
**Wave C** (after B-wave merges): C1. 12 packages total. NO file appears in two packages.
"Owns" = creates or edits; everything else is read-only compile-time dependency.

| Pkg | Owns (java under `dev/projecteclipse/eclipse/`, plus data/config) |
|---|---|
| A1 | `core/config/ReloadHooks.java` (new), `core/config/EclipseConfig.java` (1-line hook), `core/signal/EclipseSignals.java` (new), `core/util/ExhaustionScaler.java` (new), `registry/EclipseItems.java`, `registry/EclipseSounds.java`, `registry/EclipseAttachments.java`, `analytics/PlacedBlockData.java` (shell+codec), `ritual/HeartExtractorItem.java` (shell: item class, constructor + TODO hooks only), all 10 new payload records in `network/`, `network/EclipsePayloads.java`, `client/ClientStateCache.java` (new fields + stub handlers), `gametest/GameTestSupport.java`, `gametest/HarnessSmokeTest.java`, `data/eclipse/structure/gametest/empty.nbt`, placeholder `.ogg`s + `sounds.json`, item models/textures for `heart_extractor`/`glitch_shard`, `docs/plans_v3/langdrop/P4-A1.json` |
| B1 | `progression/realtime/RealtimeDayService.java`, `RealtimeState.java`, `RealtimeMath.java`, `RealtimeConfig.java`, `RealtimeCommands.java` (all new), `progression/DayScheduler.java` (rework), `devtools/PhaseScheduler.java` (delegate rework), `gametest/realtime/*`, langdrop `P4-B1.json` |
| B2 | `progression/goals/` (new pkg: `GoalConfig`, `GoalSpec`, `TriggerType`, `QuestEngine`, `QuestState`, `QuestMath`, `QuestCommands` (`/eclipse-quests`), detectors), `progression/GoalTracker.java` (adapter rework), `network/S2CGoalProgressPayload.java` (keep shape, re-source from QuestEngine), `gametest/goals/*`, langdrop `P4-B2.json` |
| B3 | **content/data only**: `run/config/eclipse/goals.json`, `quests.json`, `milestones.json` (rebalance), `offering_values.json`, `awards.json`, `recipegate.json`, `skills.json`, `skilltree.json`, `buffs.json` (authored values; engines' built-in defaults stay minimal), `src/main/resources/data/eclipse/advancement/event/*.json` (~20), `data/eclipse/tags/item/tier_diamond_gear.json`, `tier_netherite_gear.json`, langdrop `P4-B3.json` (advancement titles/descs + award/buff/offering names en+de) |
| B4 | `skills/` (new pkg: `SkillService`, `SkillState`, `SkillCurve`, `SkillConfig`, `SkillsApi`, `SkillPerks`, `SkillTree`, `SkillTreeConfig`, `AdvancementXpBridge`, `SkillCommands`), `gametest/skills/*`, langdrop `P4-B4.json` |
| B5 | `analytics/` (new pkg minus `PlacedBlockData`: `AnalyticsService`, `AnalyticsState`, `AnalyticsApi`, `AnalyticsConfig`, `PlacedBlockTracker`, `AnalyticsSampler`, `AnalyticsCommands`), `gametest/analytics/*`, langdrop `P4-B5.json` |
| B6 | `awards/` (new: `AwardService`, `AwardsState`, `AwardMath`, `AwardConfig`, `AwardCommands`), `offering/` (new: `OfferingService`, `OfferingState`, `OfferingRules`, `OfferingConfig`), `ritual/AltarBlock.java` + `ritual/AltarBlockEntity.java` (offering gesture), `gametest/awards/*`, langdrop `P4-B6.json` |
| B7 | `progression/RecipeGate.java` (new), `villagers/VillagerRestrictions.java` (new), `progression/ContainmentService.java` (new), `worldgen/structure/SanctumProtection.java` (rework), shared config loader `protection/ProtectionConfig.java` (new pkg), `gametest/restrictions/*`, langdrop `P4-B7.json` |
| B8 | `ritual/HeartExtractorItem.java` (takes over A1's shell), `glitch/` (new: `GlitchSpawnService`, `GlitchDrops`, `GlitchConfig`), `data/eclipse/recipe/revive_sigil.json` (rework), `data/eclipse/recipe/heart_extractor.json`, `data/eclipse/recipe/vitae_shard_glitch.json`, `data/eclipse/tags/entity_type/glitched.json`, `gametest/revive/*`, langdrop `P4-B8.json` |
| B9 | `buffs/` (new: `TimedBuffService`, `BuffState`, `TimedBuffApi`, `BuffConfig`, `BuffEffects`, `BuffCommands`), `voice/VoiceState.java` (new), `voice/VoiceMuteApi.java` (global-mute additions), `voice/VoiceCommands.java` (new), `ghosts/` (new: `LogoutGhostService`, `GhostsState`), `gametest/buffs/*`, langdrop `P4-B9.json` |
| C1 | `hud/SidebarSyncService.java` (new pkg `hud/`), `start/StartAssignmentService.java`, `start/StartAssignState.java`, `start/StartCommands.java` (new), `gametest/integration/*`, langdrop `P4-C1.json` |

Read-only for everyone (never edited by P4): `EclipseMod.java`, `admin/EclipseCommands.java`,
`devtools/ConfigEditor.java`, `devtools/client/GoalEditorScreen.java` (P5 territory), lang
JSONs, `lives/*`, `hearts/*`, `economy/*`, `ritual/ReviveRitual.java`,
`timeline/*`, `worldgen/stage/*`, `client/hud/SidebarPanel.java` (P3 territory),
`voice/EclipseVoicePlugin.java` (works unchanged — verified it calls `VoiceMuteApi.isMuted`).

Wave-B compile deps on A1 only (signals, payloads, ReloadHooks, registry entries). C1 compile
deps on B1/B2/B4/B9 public APIs. B-wave workers must NOT reference each other's classes —
cross-talk ONLY via `EclipseSignals`, `TimedBuffApi` (B9, interface frozen in this doc — B4
may compile against it; if B9 hasn't merged, B4 uses A1's `core/util` stub? NO: keep it
simple — **A1 also ships `buffs/TimedBuffApi` as an interface + no-op holder** and B9
implements behind it; matrix amendment: `buffs/TimedBuffApi.java` moves to A1).

### 3.1 P4-A1 — Foundation plumbing (SOL, size M)

**Goal**: everything in §2.0 + `TimedBuffApi` facade, so wave B is conflict-free.
**Outline**: ReloadHooks + one-line EclipseConfig call; EclipseSignals (listener lists, fire
helpers, ServerStopped self-clear); ExhaustionScaler (factor registry + 20t sweep);
registry additions (2 items — `HeartExtractorItem` shell with constructor/use-duration only,
`glitch_shard` plain Item; 5 sounds + placeholder oggs; `placed_blocks` chunk attachment with
codec on `PlacedBlockData`); 10 payload records + registration in EclipsePayloads +
ClientStateCache fields/stub handlers (cache-write only, P3 replaces rendering);
`TimedBuffApi` interface + static holder defaulting to no-op; gametest harness (empty
structure nbt, support class, smoke test asserting a mock player exists and signals
dispatch); langdrop with item/sound names en+de.
**Acceptance**: `./gradlew build` green; `runGameTestServer` passes smoke test; `runServer`
boots clean (RCON `/eclipse status` works); no behavior change for existing systems (boot
log identical modulo new registrations).
**Tests**: harness smoke; signal register/fire/clear-on-stop gametest; payload codec
round-trip (encode→decode equality) for all 10 in a gametest.

### 3.2 P4-B1 — Real-time day engine (FABLE, size L)

**Goal**: §2.1 complete — persistent Berlin-18:00 (configurable) real-time day boundaries,
pause/add/reduce/set API, catch-up, spool payload, PhaseScheduler delegation, legacy flag
deprecation.
**Outline**: RealtimeMath (nextBoundary, parseSpec moved from PhaseScheduler, catch-up count
calc — ALL pure statics); RealtimeState SavedData; RealtimeDayService (tick, rollover
choke point firing `dayRollover PRE/POST`, catch-up on ServerStarted, arm-on-start_event via
`startEventDone` observation OR explicit `arm` from P5); DayScheduler rework: keep
`setDay` contract 100% (all existing callers verified: EclipseCommands daySet, PhaseScheduler,
auto-advance) + add `setDayQuiet` + re-anchor-on-external-change + fire signals; delete the
`dayAutoAdvance` poll body (deprecation warning once); PhaseScheduler internals → delegate to
RealtimeDayService (public statics keep signatures — EclipseCommands calls them);
RealtimeCommands `/eclipse-rt arm|disarm|pause|resume|add <±spec>|set <spec>|status`.
**Acceptance**: gametests — `nextBoundary` across DST spring/fall Berlin dates; catch-up
math (3 missed boundaries → +3 days, capped at maxDay); pause freezes remaining across a
simulated save/load (write NBT, reload state object); rollover order PRE→setDay→POST
asserted via recording signal listener; `/eclipse schedule next +90s` (RCON) still fires and
advances exactly one day; bossbar appears/disappears. RCON smoke: arm → `add +1m` → observe
advance + expansion (`stage get` changes on a `day:N` boundary with a test stages.json).
**Model**: FABLE (time-zone/catch-up edge cases are design-sensitive).

### 3.3 P4-B2 — Goal & personal-quest engine (FABLE, size L)

**Goal**: §2.2 complete — GoalSpec configs, 17 trigger types, 3 scopes, personal pools,
rewards, payload feed, legacy adapter, beat shims.
**Outline**: GoalConfig (+`validateAndNormalize` for P5), QuestState, QuestMath
(deterministic draws), QuestEngine (assignment on POST rollover/login, completion pipeline,
stat baselines via `player.getStats().getValue(...)`), detectors (signal listeners + ONE 20t
poll loop for location/depth), GoalTracker adapter (legacy command + payload keep working),
QuestCommands `/eclipse-quests tick <player> <id>|reroll <player>|list [player]|reload`.
**Acceptance**: gametests — draw determinism (same seed/uuid/day ⇒ same 3 quests; completed
excluded); each trigger type completes from a synthetic signal/mock-player action (kill via
signal, mine via signal + placed-check false, visit_location via teleported mock player +
poll invoke, stat_threshold via stats mutation); team_total credits offline?→ counter
persists and completes for online; reward grants skillXp (SkillsApi recorded) + items;
payload contents match state; legacy `/eclipse goals tick` (RCON) ticks main[0]. Fallback:
day missing from goals.json renders days.json strings as manual mains (gametest with doctored
config dir — config loaders must accept an injectable base path for tests).
**Model**: FABLE.

### 3.4 P4-B3 — Content & balance data (FABLE, size M)

**Goal**: author ALL event data: goals.json (14 days × 3 mains harder + 3-5 sides),
quests.json (≥24 personal quests), milestones rebalance, offering values, award categories
(≥18 incl. `best_offering` fixed slot), recipegate tiers, skills.json full earn table +
curve, skilltree.json 21 nodes, buffs.json 7 defs, 20 advancements JSON + 2 gear tags;
langdrop for every string (en+de).
**Direction anchors** (binding): mains per day track the CURRENT arc's theme but with real
triggers + raised targets (e.g. day 1: `survive_night_no_damage` team_all → side; main
"Gather 16 logs" → `mine_block #minecraft:logs 64 team_total`; day 3 "Forge a full iron
toolset" → `craft_item` iron tools 5 distinct? use 3 specs; day 6 blaze rods → `collect_item
minecraft:blaze_rod 12 team_total`); sides = smaller (e.g. `breed_animals 4`, `visit_biomes
3`, `reach_depth -32`, `smelt_item 32`, `deposit_altar value 40`); personals small
(`explore_chunks 40`, `kill_entity any_hostile 15`, `travel_distance 3000m`,
`craft_item torches 64`…). Milestones per §2.6. XP economy per §2.3 targets (~600-800 XP/h;
verify by summing a simulated hour: 300 stone + 40 ores + 12 kills + 20 chunks ≈ 150+180+120+100
= 550 + quests). Advancements list (ids + criteria + XP) written out in the file.
**Acceptance**: every engine loads the authored files with ZERO warnings (gametest in each
engine package already validates schema; B3 runs `runServer` + `/eclipse reload` clean);
sum-check script `scripts/p4_balance_check.py` (B3-owned, offline) recomputes XP/h and level
targets from skills.json and prints the table (committed with output in the PR description).
**Model**: FABLE (pure balancing).

### 3.5 P4-B4 — Skills core + tree + perks (FABLE, size L)

**Goal**: §2.3 complete (service, curve, config, procs, secret multipliers, tree purchase,
21 perk hooks, advancement XP bridge, commands).
**Acceptance**: gametests — `SkillCurve` monotonic + C(12)≈2650 ±5% with defaults; addXp
applies buff×secret×node multipliers in documented order; level-up grants points + fires
signal; node buy validates prereqs/cost, persists, survives NBT round-trip; T2/T6 proc rolls
respect `isPlaced` (mock tracker via A1 data class direct-write); death −50 floor at 0 total?
(decide: totalXp floors at 0 — test); AdvancementEarnEvent grants configured XP once;
procmsg off suppresses chat line (capture via mock player's sent messages). RCON smoke:
`/eclipse-skills xp add <p> 500`, `/skills info`, `mult set` hidden from `/skills info`
output.
**Model**: FABLE.

### 3.6 P4-B5 — Analytics + placed-block tracker (FABLE, size L)

**Goal**: §2.4 complete (state, all event owners, sampler, tracker, signals fan-out, API,
commands, config).
**Acceptance**: gametests — place→mark→break clears bit + NO `naturalBlockMined` fired;
natural break fires signal + counts `mine:<id>`; bitset codec round-trip through chunk
save/load (`helper.getLevel().getChunk(...)` attachment persistence); distance sampler caps
teleport jumps; per-day cut on rollover PRE (day N counters frozen, N+1 fresh); `top()`
ordering + tie behavior; craft allowlist honored; 1 Hz sampler executes < 0.2 ms for 50 mock
players (nanoTime assertion, generous bound). RCON: `/eclipse-analytics top 1 mine_total`.
**Model**: FABLE (perf-sensitive design).

### 3.7 P4-B6 — Daily awards + altar offerings v2 (FABLE, size L)

**Goal**: §2.5 + §2.6 code complete (award pick/resolve/reveal/pending, offering gesture on
the altar, value rules, anti-copy, winner, `altarDeposit` signal emission for ALL three
altar purposes incl. existing milestone/bank paths — B6 owns the altar files).
**Acceptance**: gametests — `AwardMath.pick` deterministic + theme-weighted (statistical
gametest: 1000 draws, combat categories ≥2.5× baseline on day 7); ties split rewards
(2 winners × 400 XP ⇒ 200 each); min-playtime filter; resolution idempotent (double PRE fire
⇒ one record); offering: 1/day enforced, confirm window, duplicate item types both zeroed,
enchanted ×1.5, winner fed into reveal payload as `best_offering`; pending reward granted at
mock relogin. RCON: offer via mock impossible — server smoke uses `/eclipse-awards preview
<day>` (B6 reference command, perm 3, prints WITHOUT resolving — secrecy note in help text).
**Model**: FABLE.

### 3.8 P4-B7 — Restriction suite (SOL, size L)

**Goal**: §2.7 recipe gate + §2.10 villagers + §2.13 containment + §2.14 spawn protection v2,
all config-driven under `protection.json`/`recipegate.json`.
**Acceptance**: gametests — RecipeGateMath.lockedAt table; ItemCraftedEvent shrink for locked
diamond pickaxe on day 1, allowed on day 5 (day set via helper); recipe-locks payload content;
villager: spawn librarian → after ≤100t sweep profession NONE; offers of a doctored
enchanted-book trade stripped on interact hook; wandering trader join-cancel (natural reason)
+ egg spawn allowed; containment: mock player at y=−200 day 1 → upward velocity + no fall
damage flag; day 2 → untouched; protection: PvP damage cancelled inside zone, allowed
outside; lava bucket RightClickBlock cancelled inside; fall damage cancelled inside
radius+band; creative exempt. RCON smoke: `day set 1` + observations.
**Model**: SOL (mechanical event-cancels against a precise spec).

### 3.9 P4-B8 — Revive rework + glitch path (FABLE, size M)

**Goal**: §2.8 + §2.9 (extractor behavior on A1's shell, recipes, glitch spawn/replace/drops,
new-ring window, buff hook `glitch_spawn`).
**Acceptance**: gametests — extractor: mock player 5 hearts → use-finish ⇒ 4 hearts + 2
fragments + effects; at 1 heart ⇒ refused; recipes load (RecipeManager lookup by id);
glitch: FinalizeSpawnEvent inside new-ring radius with forced roll ⇒ replaced type (register
a dummy `eclipse:glitched_zombie`? NO — B8 must NOT register entities (P6's); test the
DECISION function `GlitchSpawnService.shouldReplace(pos, type, roll)` pure + the
replacement lookup soft-fails clean when the type is absent); drops: doctored tag with
`minecraft:zombie` in a test-only datapack dir → kill ⇒ glitch shards; ring window math pure
test (`newRingContains(pos, now)`). RCON: none beyond boot-clean.
**Model**: FABLE (interlocking with lives/hearts safety rules).

### 3.10 P4-B9 — Timed buffs + voice global mute + logout ghosts (SOL, size L)

**Goal**: §2.16 buffs (service/state/effects/commands/bossbar) + §2.15 voice additions +
§2.12 ghost service (P6-independent parts; the service must run headless with the entity
type absent — spawn attempts soft-fail with one log line until P6 lands).
**Acceptance**: gametests — buff start/extend/refuse/cap/expiry across simulated restart
(state NBT round-trip with endsAt in past ⇒ expired on load); `multiplier` product of two
active buffs; ore-drop doubling only when `isPlaced=false`; magnet moves orbs; global voice
mute flips `VoiceMuteApi.isMuted` for a non-entry-muted mock player; ghosts: logout event
(synthesized) records state + spawns (skipped-if-type-missing branch tested both ways via
registry check), login discards + clears, reveal payload rate-limited. RCON:
`/eclipse-buffs start double_skill_xp 1` shows bossbar; `/eclipse-voice global on`.
**Model**: SOL.

### 3.11 P4-C1 — Sidebar sync + start assignment + integration tests (SOL, size M)

**Goal**: §2.17 + §2.18 + cross-system gametests that only make sense after wave B.
**Acceptance**: gametests — sidebar payload assembles all fields from live services;
dirty-coalescing (≤1 packet/s under spam); assignment determinism + round-robin balance
(N players, M anchors ⇒ counts differ ≤1); teleport lands on safe ground; **integration**:
full simulated day: arm clock → mock players mine/kill (signals) → boundary passes (state
manipulation) → assert awards resolved + reveal payload + quests re-rolled + recipe locks
rebroadcast + sidebar updated, in order. RCON smoke: `/eclipse-start assign` + `tp`.
**Model**: SOL.

---

## 4. INTERFACES TO OTHER PLANNERS

**P1 (world/rings/discs)**
- CONSUMES: `WorldStageService.addListener` (exists) for ring-commit timestamps;
  `StageRadii.radius(profile, stage)` + `EclipseWorldState.getBorderCenterX/Z` for glitch
  new-ring geometry. No P1 change needed.
- NEEDS FROM P1: (a) per-player **start-disc anchors** API or `disc_map.json` v3
  `startDiscs: [{x,z}...]` (C1 falls back to a spawn ring until then); (b) authoritative
  **disc underside Y** constant for containment `bounceY` (interim default −180 in
  protection.json — P1 corrects the default in its own config touch or tells P4 the value).

**P2 (FX/intro)**
- Containment bounce FX: P4 sends `S2CQuasarPayload("eclipse:containment_bounce", pos)` —
  P2 registers that Quasar emitter id (fallback particles already exist in `QuasarSpawner`).
- Island-edge auto-glide: P2 owns motion/visuals; P4's `SanctumProtection.isProtected` +
  no-fall-damage band (radius+`edgeBandExtra`) is the safety net. Zone query is public.
- Intro rework: P2 calls `StartAssignmentService.assignAll(server)` +
  `teleportToAssigned(player)` instead of the shared-spawn teleport at its teleport beat
  (today `StartEventCutscene` t=140). Signature frozen in §2.18.
- Day-advance "expansion sequence" untouched: `DayScheduler.setDay` still runs
  `applyDayTriggers` — P2's cinematics stay hooked where they are.

**P3 (UI/i18n)**
- Renders from new payloads (all shapes frozen in §2.0): day clock + **spool animation**
  (`S2CDayClockPayload` — animate when boundary changes while day unchanged), quest list
  (mains/sides/personals; replaces goal strings), skill GUI (`S2CSkillStatePayload` +
  `C2SSkillNodeBuyPayload`; tree layout data comes from skilltree.json — P3 may request a
  `S2C` tree-definition payload: NOT included; recommendation: ship skilltree.json содержимое…
  **decision**: A1's `S2CSkillStatePayload` carries owned nodes only; P3 reads node
  defs from a new `S2CSkillTreePayload`? — AGREED ADDITION: A1 registers an 11th payload
  `S2CSkillTreePayload(json:String)` sent at login + reload (tree is not secret).
- Award roulette overlay from `S2CAwardRevealPayload` (UUID→anonymized heads; values included
  for suspense; winners list; i18n literals inside payload).
- Buff rows / bossbar reskin from `S2CBuffStatePayload`; sidebar rows from
  `S2CSidebarStatePayload` — **P3 must delete the client-computed online-count row in
  `client/hud/SidebarPanel`** (the only sidebar datum P4 cannot remove server-side).
- Ghost reveal glitch-name rendering from `S2CGhostRevealPayload` (GlitchText exists).
- EMI hiding from `S2CRecipeLocksPayload`. Handbook: revive recipe page (recipes are normal
  datapack recipes — visible to recipe book/EMI when unlocked), skill tab, quest tab.
- i18n: langdrop files under `docs/plans_v3/langdrop/` are the SINGLE hand-off; P3/orchestrator
  merges into `en_us.json`/`de_de.json`. Payload-embedded literals (quests/awards/buffs) are
  en+de pairs by design (anti-datamine) — P3 picks by client language.
- Proc feedback UX: server plays sound + chat line (R3); P3 may add a GUI flash off
  `S2CSkillProcPayload`.

**P5 (devtools/commands)**
- Frozen server APIs to surface (P4 ships reference commands under separate roots so nothing
  blocks; P5 owns the polished `/eclipse …` UX in NEW command classes, never the old file):
  `RealtimeDayService` (arm/disarm/pause/resume/add/set/status — "timer visibly spools" is
  automatic: every boundary change broadcasts the clock payload), `SkillsApi`
  (xp add/set, `setSecretMultiplier(uuid, f)` — persistence handled), `AnalyticsApi`
  (top/value/dump), `TimedBuffApi.start/stop` (Xbox reward = `start("double_skill_xp", 60)`),
  `VoiceMuteApi.setGlobalMuted` + existing per-player, `QuestEngine` (tick/reroll/reload),
  `AwardService.preview/resolveNow`, `OfferingService.peek(day)` (perm 3; secrecy warning),
  `StartAssignmentService.assignAll/teleport`, `RecipeGate.lockedItemIds`.
- Goal editor GUI v2: edits goals.json trigger fields; server-side validation entry point
  `GoalConfig.validateAndNormalize(JsonElement)` (mirrors `ConfigEditor.normalizeDays`
  contract); `ConfigEditor`/`GoalEditorScreen`/`C2SConfigEditPayload` file-allowlist extension
  is P5's (add `goals.json`, `quests.json`).
- `/eclipse reload` already reaches all P4 configs via the ReloadHooks bridge.

**P6 (entities/models)**
- Glitched mobs: register exactly `eclipse:glitched_zombie|glitched_skeleton|glitched_spider`
  (P4's tag + replacement table reference these ids; extending = edit `glitch.json` +
  tag). Drops/XP/recipe/cap = P4 (done); models/AI/spawn-egg = P6. Spawn-rate lives in
  `glitch.json` (P6 must NOT add biome-modifier spawns for them).
- Logout ghost: P6 registers `eclipse:logout_ghost` (no AI, invulnerable, translucent
  eclipse-skin render, REVEAL_TICKS synched-data-driven glitch shader) and calls
  `LogoutGhostService.onGhostHurt(ghost, attacker)` from `hurt()` + `isValid(ghost)` in its
  100t self-check. Spawn/despawn/persistence/reveal payload = P4-B9 (already soft-registered:
  works the moment P6's type exists).
- Ship door (revive): unchanged `EclipseWorldState.isBanned` / `BanService`.

---

## 5. RISKS & FALLBACKS

1. **Simple Voice Chat API availability** — LOW: `voicechat-api:2.6.20` is already a
   compileOnly dep and the plugin pattern is proven in-repo. Global mute is a pure extension
   of `VoiceMuteApi.isMuted`. Fallback if SVC absent at runtime: plugin never loads (already
   the case today); commands still flip state; document "mute has no effect without SVC".
2. **Real-time catch-up edge cases** — DST (nextBoundary computed in ZoneId — tested on the
   two Berlin transitions), backwards clock jumps (monotonic `lastAdvanceEpochDay` guard +
   WARN), multi-day outages (bounded by `catchUpMaxDays`, awards resolve per skipped day from
   whatever analytics exist — possibly empty: categories with zero candidates are skipped,
   payload may carry <3 categories, P3 must tolerate), boundary while a ring sweep is mid-
   flight (safe: `applyDayTriggers` commits stages; `RingGrowthService` has restart-resume
   cursors already), TWO advances stacking cinematics (suppressed via `setDayQuiet` for all
   but the last catch-up day).
3. **Analytics overhead / NBT growth** — per-block cost is one event handler + one hash
   lookup + one long increment; the placed tracker is O(1) bit ops with lazy 512-byte section
   buffers; per-day maps are bounded by distinct ids actually touched (measured budget in
   B5's perf gametest). SavedData writes happen on autosave only (`setDirty` marks). If a
   14-day file still bloats: `retentionDays` prune + per-id caps are config levers (no code).
4. **Placed-tracker leaks** — explosions/pistons/water leave stale bits (fail-SAFE: only
   under-credits, never mints XP); re-place+break farming is dead (bit blocks credit);
   silk-touch move-and-rebreak of ORES across positions remains possible but yields no ore
   XP at the new pos only if marked — placing ore marks it ⇒ closed. Documented residual:
   piston-moved placed blocks become "natural" at the new pos (obscure, low value).
5. **Anonymity leaks** — award payload carries UUIDs (client cannot resolve names — tab list
   is hidden/anonymized; P3 renders anonymized heads); ghost reveal is the single name
   channel (rate-limited, 32-block radius); secret multipliers never sync and log at DEBUG
   only; offering values/categories never ship to clients before resolution.
6. **Shared-file contention** — solved structurally (wave A owns every shared file;
   ownership matrix §3.0; `TimedBuffApi`/`S2CSkillTreePayload` amendments folded into A1).
   Residual risk: another PLANNER's workers touching `EclipsePayloads`/`registry/*` —
   orchestrator must serialize A-waves across planners (flagged to orchestrator).
7. **Legacy interplay** — `/eclipse day set` (untouchable) re-anchors the clock (tested);
   `/eclipse goals tick` maps to mains adapter; `dayAutoAdvance` ignored with warning;
   `S2CDayStatePayload`/`S2CGoalProgressPayload` keep flowing until P3 swaps the sidebar.
   The old `goal_progress` attachment is simply no longer read (fresh event world assumed;
   no migration).
8. **Gametest determinism** — real-time services must accept an injectable clock
   (`LongSupplier now`) — mandated in B1/B9 designs; config loaders accept injectable dirs.
   If `runGameTestServer` proves flaky in CI-less local runs, fallback: keep gametests but
   gate acceptance on the pure-static test subset + RCON smoke (documented per package).
9. **P6/P1 timing** — glitch spawns and logout ghosts soft-fail without P6's entities (one
   log line, no crash — tested both branches); start assignment falls back to a spawn ring
   without P1's anchors; containment uses an interim `bounceY` default. Nothing in P4 hard-
   depends on another planner's merge order.
10. **Balance risk** — skills/goals/offering numbers are all data (`run/config/eclipse/*.json`,
    hot-reloadable via `/eclipse reload`); the event can be re-tuned live without a build.
    B3's `p4_balance_check.py` keeps the XP curve honest before ship.
