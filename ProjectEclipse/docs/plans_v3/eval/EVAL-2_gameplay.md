# EVAL-2 — Gameplay Systems Correctness Audit

Scope: read-only source audit of awards, offerings, skills, glitch/heart/revive,
buffs, analytics, anti-cheat, Xbox event, voice, villagers, protection, and
sidebar/network synchronization. No Gradle task was run, per audit instructions.

Severity means:

- **Critical** — can mint/lose durable progression or rewards, or is readily exploitable.
- **Medium** — materially wrong gameplay/state/UI behavior under normal or credible edge paths.
- **Low** — narrow edge, malformed-config behavior, or a currently redundant broken contract.

## Critical

### C1. Award/offering rewards are not transaction-safe and can be lost or duplicated

**Files:** `awards/AwardService.java:162-168,218-241`,
`awards/AwardsState.java:124-150`, `offering/OfferingService.java:133-142`

Both resolvers persist the day as resolved before they enqueue its rewards. If reward
construction/delivery throws after `putResolved`, later catch-up calls return the frozen
result and never reconstruct the missing queue entries. Delivery has the inverse failure:
`takePending` removes *all* queued rewards before XP, shards, and items are granted. An
exception or save-order boundary during the loop can therefore persist an empty queue after
only a partial grant (loss), or persist the old queue after some player data/items were saved
(duplicate grant on next login). Stable reward IDs only deduplicate entries still present in
the pending map; they do not provide a durable claimed/delivered transaction.

This affects both daily awards and best-offering rewards because both use the same queue.

### C2. Restarting during a day resets “distinct” analytics and re-fires chunk rewards

**Files:** `analytics/AnalyticsService.java:65-70,97-104,153-170`,
`analytics/AnalyticsSampler.java:39-43,102-111,138-147`,
`skills/SkillService.java:105-110`

`PLACE_TYPE_HASHES_TODAY` and `CHUNKS_TODAY` are process-local maps and are cleared on server
stop/start, while their aggregate counters are persisted. After every restart:

- placing an already-counted block type increments `place_types` again;
- the first sample in any previously visited chunk increments `chunks_new` again;
- that chunk sample re-fires `chunkExplored`, granting skill XP and quest progress again.

Repeated restarts can therefore inflate award metrics and farm exploration progression. This
violates the documented per-day-distinct semantics and is more than analytics drift because
the signal has reward-bearing consumers.

## Medium

### M1. Ore/shard buff multipliers above 2× are silently collapsed to 2×

**File:** `buffs/BuffEffects.java:67-120`

The service computes a product of all active matching multipliers, but both drop handlers only
test whether that product is greater than one and then append exactly one copy. For example,
`double_ore_drops` (2.0) plus `steady_hands` (1.25) reports 2.5× but pays exactly 2×; a 1.25×
or 1.5× buff also pays a deterministic 2×. The handler must apply the integer portion and
probabilistically apply the fractional remainder (or otherwise implement the configured
multiplier contract).

### M2. `supply_rush` fires immediately instead of after its first period

**Files:** `buffs/BuffMath.java:64-90`, `buffs/TimedBuffService.java:147-168`

A newly started periodic buff stores `lastPeriodicEpochMillis = 0`. The periodic loop treats
`last <= 0` as due, so the next one-second sweep launches a supply drop immediately even though
the default period is 600 seconds. Initialize the schedule at activation (or derive the first
due time from activation) so “periodic every 600s” does not mean “now, then every 600s.”

### M3. XP magnet works only in the overworld

**Files:** `buffs/TimedBuffService.java:147-160`, `buffs/BuffEffects.java:135-155`

The global timed buff calls `pullExperienceOrbs(server.overworld(), radius)` once. The pull
routine only iterates players and orbs in the supplied level, so players in the Nether, End,
Limbo, and Xbox dimensions receive no magnet effect. No config or design contract scopes this
buff to the overworld; the service should iterate all loaded levels.

### M4. The timed-buff bossbar progress never decreases

**File:** `buffs/TimedBuffService.java:275-302`

`refreshBossbar` assigns `total = max(remaining, 1)` immediately before calculating
`remaining / total`, making progress 1.0 for every active buff until it disappears. The text
countdown changes, but the visual progress bar stays full. Persist/start or reconstruct the
buff's total duration and divide by that duration.

### M5. Sidebar aggregate caches are not invalidated by three state owners

**Files:** `buffs/TimedBuffService.java:126-143,172-207`,
`progression/realtime/RealtimeDayService.java:105-269`,
`economy/ShardEconomy.java:117-125,241-255`,
`hud/SidebarSyncService.java:183-209,234-288`,
`client/hud/SidebarExpanded.java:245-252,279-288`

`SidebarSyncService` snapshots buff IDs, clock state, and shards, but:

- buff start/stop/expiry sends only `S2CBuffStatePayload`;
- clock mutations send only `S2CDayClockPayload`;
- `ShardEconomy.setShards`/`addShards` does not dirty the owning player.

Consequently `sidebarBuffIds`, `sidebarBoundaryEpochMillis`/`sidebarPaused`, and
`sidebarShards` can remain stale until an unrelated signal or relog. The dedicated buff payload
does not repair the sidebar: `SidebarExpanded.validBuffs` explicitly intersects it with stale
`sidebarBuffIds`. Purchases and admin/award shard mutations are especially visible stale paths.

### M6. Xbox close recovery can grant the global participation buff more than once

**File:** `xboxevent/XboxEventService.java:105-134,325-383`

The code claims the `CLOSING` sequence is safe to re-run, but it has no persisted completion
markers. It grants/extends the participation buff, then performs portal/reset cleanup, and only
finally writes `IDLE`. If a runtime failure leaves a persisted `CLOSING` state after the reward
was applied, boot recovery calls `beginClosing` again and extends the same reward buff again.
The close path needs idempotent, persisted steps (at minimum a reward-granted marker).

### M7. Manifest chest loot is available outside the active Xbox event

**Files:** `xboxevent/XboxEventService.java:712-738`,
`xboxevent/XboxEventState.java:260-278`

`lootFor` checks only that the level is an Xbox dimension and the manifest has loot at the
position. `consumeChestPosition` checks neither event phase nor that `manifestWorldId` equals
the active `state.worldId`. A player/admin present in an inactive or non-active Xbox world can
consume and receive its manifest loot. Consumption should require `OPEN`, matching world ID,
and normally active-instance participation/access.

### M8. Reaper duplicates drops from spawned/command-created hostiles despite “natural spawn” rule

**File:** `skills/SkillPerks.java:298-324`

The U2 handler excludes players and bosses but never checks how the hostile spawned. The
gameplay plan specifies non-boss **natural spawns**, so spawner-, structure-, and
command-created hostiles can currently trigger double drops. This enables farmable output
outside the perk's anti-abuse contract.

### M9. A crash during the revive ritual permanently consumes the sigil

**Files:** `ritual/AltarBlockEntity.java:307-334`,
`ritual/ReviveRitual.java:53-68,84-100,252-259`

The sigil is consumed when the three-minute ritual starts, but active rituals exist only in the
static `ACTIVE` list. Graceful `ServerStoppingEvent` refunds a sigil; a process crash cannot run
that handler, and no persisted ritual/refund record exists on boot. The target remains banned
and the valuable sigil is gone. Persist either the active ritual or a pending refundable sigil.

### M10. Per-day chunk identity collides across dimensions

**File:** `analytics/AnalyticsSampler.java:102-111`

`CHUNKS_TODAY` stores only `ChunkPos.asLong(x,z)`. The same coordinates in two dimensions are
treated as one chunk, suppressing the second dimension's `chunks_new`, skill XP, and
`explore_chunks` quest signal. Include the dimension key in the per-player distinct identity.

### M11. `/eclipse reload` does not reload `xboxevent.json`

**Files:** `xboxevent/XboxEventConfig.java:17-25,56-61`,
`core/config/ReloadHooks.java:8-15,35-47`,
`devtools/dev/DevReload.java:62-68`

`XboxEventConfig` registers only in `DevReloadRegistry`. `/dev reload` runs both the P4
`ReloadHooks` bridge and that registry, but `/eclipse reload` ends at `ReloadHooks.runAll()` and
never sees the Xbox hook. Thus the primary reload path leaves Xbox duration, reward, lockout,
portal, announcement, and world-list settings stale.

## Low

### L1. The dynamic analytics key cap counts static keys against a dynamic-only limit

**Files:** `analytics/AnalyticsState.java:137-150`,
`analytics/AnalyticsKeys.java:90-118`

`addDynamic` compares `counters.size()` with `maxDynamicKeysPerPlayerPerDay`, even though the
map also contains up to 22 static keys. The configured dynamic capacity is therefore reduced
by however many static counters the player touched. Count only keys with a dynamic prefix.

### L2. `SkillPerks.isPlaced` uses the placed-section compatibility API with the wrong coordinate

**Files:** `skills/SkillPerks.java:109-127`,
`analytics/PlacedBlockData.java:46-63,66-100`,
`analytics/PlacedBlockTracker.java:27-49`

`sectionBits` expects the tracker's legacy absolute section coordinate (`y >> 4`) and translates
it after migration. `SkillPerks` passes `level.getSectionIndex(y)` instead, so it usually misses
the stored bit and, after migration, applies the min-section offset twice. The normal signal
path already filters placed blocks through `PlacedBlockTracker`, limiting current impact, but
the public perk predicates and defensive check are incorrect and unsafe for direct/foreign
callers. Use `PlacedBlockTracker.isPlaced` (or the same migration-aware lookup as buffs).

### L3. Duplicate IDs in `glitch.json` double-count the alive cap

**Files:** `glitch/GlitchConfig.java:159-175`,
`glitch/GlitchSpawnService.java:157-170`

The loader preserves duplicate valid entity IDs, and `countAlive` adds the full entity count
once per list entry. A duplicated ID can make the service believe it reached `maxAlive` early.
Deduplicate IDs during parsing or alive counting.

### L4. Xbox login restores event UI based on dimension, not participation

**File:** `xboxevent/XboxEventService.java:545-569`

Any player who logs into the currently active Xbox dimension receives the timer and leave UI,
even if `state.isParticipant(uuid)` is false (for example, an operator teleport). Related
death/leave helpers also identify an active event by phase+dimension only. Require participant
membership for participant behavior, while retaining an explicit admin recovery path.

### L5. Xbox duration parsing and timer mutation are overflow-prone

**Files:** `devtools/dev/DevXboxCommands.java:376-397`,
`xboxevent/XboxEventService.java:298-322`

Unchecked chained multiplications can wrap a syntactically valid very large duration, and
adding/subtracting that value from `endsAtEpochMillis` can wrap again. `Math.max(now, wrapped)`
does not protect positive wraparound. This is permission-gated and requires extreme input, but
checked arithmetic or a reasonable maximum should reject it.

### L6. `BuffConfig` registers duplicate reload hooks across server lifetimes

**File:** `buffs/BuffConfig.java:84-89`

Unlike the other scoped loaders, it registers on every `ServerStartedEvent` without a
JVM-lifetime guard even though `ReloadHooks` is never cleared in production. Reopening worlds
in one JVM accumulates identical callbacks; later reloads parse the file repeatedly and emit
duplicate logs. The resulting value is normally correct, so impact is low.

## Config reload coverage

The following scoped reload paths are correctly bridged to `/eclipse reload`:

- awards (`AwardConfig`);
- offerings (`OfferingConfig`);
- skills (`SkillConfig` and `SkillTreeConfig` through one service hook);
- glitch (`GlitchConfig`);
- buffs (`BuffConfig`, subject to duplicate registration in L6);
- analytics (`AnalyticsConfig` and `DepositValues`);
- anti-xray (`AntiXrayConfig`, with rolling windows cleared);
- protection/villagers (`ProtectionConfig` reload runs before the LOWEST-registered gamerule
  reapply hook).

`xboxevent.json` is the sole scoped config with the primary-path gap (M11). Voice has no JSON
loader in this scope. The broader `S2CSidebarStatePayload` codec order, handler assignments,
and `ClientStateCache` field names match exactly; the HUD failures are invalidation bugs, not
wire-shape mismatches.

## Verified paths with no concrete defect found

- **Awards:** selection seed and candidate ordering are deterministic; tied XP/shards use the
  specified ceil/min-one split; item rewards are intentionally “each”; the newline title/stat
  compatibility encoding is split by `AwardsOverlay`.
- **Offerings:** one-per-day persistence, exact-id duplicate cancellation, junk handling,
  enchanted floor-multiplication, two-click confirmation, and altar signal reconciliation
  match the contract.
- **Skills:** curve anchors/softcap behavior, server-side node cost/prerequisite validation,
  hidden multiplier handling, shared proc-chance addition, and Bulwark's absorption units are
  internally consistent. Hunger skill and buff factors intentionally compose.
- **Hearts/revive:** extractor constants are the landed 2-heart/4-fragment contract; all
  `LivesApi` mutations immediately replace the transient max-health modifier, so no
  max-health drift was found; successful online/offline unban restores one life.
- **Glitch:** chance clamping, fresh-ring gating, configured drop bounds, and the fixed
  Looting max bonus match the current design.
- **Anti-cheat:** rolling exposure scoring, minimum-sample gate, threshold escalation alerts,
  and later de-escalation of `previousLevel` are correct.
- **Voice:** global/per-player/entry mute all converge through outgoing microphone cancellation,
  which is the documented mute semantics.
- **Villagers/protection:** librarian/book filtering, trader spawning restrictions, PvP/fluid/
  vehicle/mob/fall rules, and exemption handling are consistent with config.
- **Sanctum radius:** the saved dev radius override deliberately drives both sanctum build and
  broad spawn radii; fixed/configured defaults remain distinct when no override is set.

## Top 3 quick wins

1. **Dirty the sidebar at mutation ownership:** call `SidebarSyncService.markAllDirty` from
   timed-buff and realtime-clock global mutations, and `markDirty(player)` from
   `ShardEconomy.setShards`.
2. **Fix first periodic fire:** initialize a new periodic buff's
   `lastPeriodicEpochMillis` to activation time (preserving it on extension).
3. **Bridge Xbox config to the primary reload registry:** register `XboxEventConfig::reload`
   with `ReloadHooks` as well as (or instead of) `DevReloadRegistry`, with one idempotent guard.
