# EVAL-5 — Server Safety, Anonymity, and Lifecycle Audit

Scope: static, read-only audit of the requested NeoForge 1.21.1 command, anonymity,
lifecycle, C2S payload, and worldgen-thread boundaries. No Gradle task or live-server
action was run, per instructions. Line references are approximate and refer to the
audited revision.

Severity means:

- **Critical** — directly defeats the stated anonymity boundary or exposes identities to
  ordinary participants.
- **Medium** — credible state/authorization bypass, cross-snapshot worldgen inconsistency,
  or a player-visible anonymity leak on a supported path.
- **Low** — defense-in-depth gap, narrow integrated-server edge, or incomplete lifecycle
  hygiene with limited current impact.

## Critical

### C1. The anonymity model is presentation-only: every client still receives real profiles

**Files:** `client/TabListHider.java:12-32`,
`client/mixin/AbstractClientPlayerMixin.java:15-24`,
`client/mixin/ClientSuggestionProviderMixin.java:18-26`

The tab list, social screen, name tags, skin, and suggestions are hidden only at render/UI
boundaries. The code deliberately leaves player-info packets intact. Those packets contain
the roster's real `GameProfile` names and UUIDs, so a modified client, packet logger, or
client mod can recover every identity even though the stock Eclipse UI does not render it.
The forced skin changes `AbstractClientPlayer.getSkin()`; it does not anonymize the profile
on the wire.

This is Critical if anonymity is intended to hold against participants rather than only
against an honest, unmodified Eclipse client. If “honest-client presentation privacy” is
the actual threat model, document that limitation explicitly; server-enforced anonymity
requires pseudonymous profiles or a protocol/proxy architecture, not additional render
event cancellation.

### C2. Hitting a logout ghost sends and renders its owner's real name

**Files:** `network/S2CGhostRevealPayload.java:10-22`,
`ghosts/LogoutGhostService.java:124-149`,
`client/entity/ghost/GhostPlayerRenderer.java:93-96,130-175`

`S2CGhostRevealPayload` contains `ownerName`. `LogoutGhostService` sends it to every player
within 32 blocks, and `GhostPlayerRenderer` resolves the glitch text into that literal
name. The payload itself calls this the only real-name S2C payload. This is intentional
feature behavior, but it is a direct exception to complete anonymity and therefore
Critical under the requested policy.

## Medium

### M1. The custom death-screen kill switch restores vanilla killer-bearing death text

**Files:** `client/death/DeathScreenSwap.java:12-36`,
`core/config/EclipseClientConfig.java:99-102,202-204`,
`client/death/EclipseDeathScreen.java:24-35`

The custom screen is anonymous because it renders only a damage-type key. Any client may
set `customDeathScreen=false`, however, and `DeathScreenSwap` then leaves the vanilla
`DeathScreen` untouched. Vanilla combat death components can include the killer player's
real display name. The same gap exists when another mod supplies a `DeathScreen` subclass,
which this handler deliberately respects. `showDeathMessages=false` suppresses the global
chat announcement; it does not make the victim's local combat-death component anonymous.

### M2. Revive-sigil selection discloses banned players' real names

**File:** `ritual/AltarBlockEntity.java:283-304,321-353`

Cycling a revive sigil resolves each banned UUID through the online player/profile cache
and sends the resulting real name to the selecting player's action bar. The ritual's
global bossbar is generic, and `ReviveRitual.targetName` is otherwise used only in server
logs, so the action-bar selection is the player-visible leak.

### M3. Awards ship linkable UUIDs and every candidate's metric value to all clients

**Files:** `network/S2CAwardRevealPayload.java:14-47`,
`client/awards/AwardsOverlay.java:65-71`,
`client/awards/RouletteStrip.java:34-40`

The overlay does not render names and uses the uniform skin, but the payload contains a
UUID and raw value for every candidate plus winner UUIDs. Because normal player-info
packets provide the same UUID-to-name mapping (C1), a modified client can deanonymize
winners and the complete candidate ranking. “UUIDs only” is not anonymous against the
actual data already available to the client. If only winner animation is required, do
not send the full candidate/value table; use opaque per-show tokens or a server-generated
strip.

### M4. `C2SRespawnReadyPayload` can skip the pre-door ship/revive sequence

**Files:** `network/death/DeathFlowPayloads.java:55-59,124-139,205-209`,
`lives/DeathFlowHooks.java:54-61,90-107,233-295,383-400`,
`client/death/DeathFlowController.java:208-220`

The client sends `ACTION_DOOR_SKIP` only during `PHASE_DOOR_OPEN`, after a short arm delay.
The server accepts it during `DOOR_OPEN`, **or during `SHIP_WAKE` or `REVIVE_BURST`**. A
modified client can therefore return immediately, bypassing the 30-tick death beat or
55-tick revive celebration before the door opens. Identity, active-flow ownership, and
ban status are checked correctly; the allowed stage predicate is too broad.

### M5. Runtime refreeze publishes a mixed worldgen snapshot and resets one-way geometry flags

**Files:** `worldgen/FrozenParams.java:107-129,140-200,253-275,508-520`,
`worldgen/DiscMapData.java:204-227,256-259`,
`worldgen/ore/OreConfig.java:43-44,80-131`

`FrozenParams.refreeze()` calls `activateFromJson()`, which creates a new `Context` whose
`breachOpen` and `endDiscMaterialized` fields default to false. It never copies the live
`EclipseWorldgenState` flags into that context. After any runtime refreeze, worker-thread
terrain reads can therefore omit an already-open breach or already-materialized End disc
from newly generated chunks until some later setter happens to mirror the flags again.

The same activation is not atomic across readers: it publishes `current` first, then swaps
`StageRadii`, `DiscMapData`, `OreConfig`, storm loot, and fog sites one by one. The
`synchronized` refreeze method serializes writers only; worldgen workers can observe a new
seed/radii context with an old map or ore snapshot. Each individual volatile publication
is safe, but the multi-object configuration is not one coherent snapshot.

## Low

### L1. Vanilla scoreboard-sidebar suppression is controlled by a client setting

**Files:** `client/hud/SidebarPanel.java:30-38,70-90`,
`client/TabListHider.java:21-25`

The tab list is canceled unconditionally, but `VanillaGuiLayers.SCOREBOARD_SIDEBAR` is
canceled only while `showSidebar` is enabled. A client can disable the Eclipse sidebar and
see a server/admin/mod-provided vanilla objective, including score-holder names. The mod
does not currently create such an objective, so this is a latent external/admin path
rather than a default leak.

### L2. `StormRegistry` does not reset its session countdowns

**File:** `stormfx/StormRegistry.java:82-86,297-312,372-377`

Server stop clears both maps and resets `NEXT_ID`, but leaves `fogSitePollCountdown` and
`keepaliveCountdown` at their previous values. A second integrated-server save inherits
the old cadence (up to 40/200 ticks). No storm object leaks, so impact is limited, but it
fails the stated “all static mutable fields reset” criterion.

### L3. `EclipseDragonFight.LISTENERS` is neither reset nor save-backed

**File:** `worldgen/end/EclipseDragonFight.java:62-80,207-212,460-490`

The stop handler clears the dragon and bossbar references but not the
`CopyOnWriteArrayList` listener registry. There are currently no callers of
`EclipseDragonFight.addListener`, so this has no active cross-save effect. Once consumers
are added, the intended lifecycle must be explicit: JVM-lifetime registration with
idempotent registration, or server-session registration cleared/rebuilt on stop.

### L4. Three additional session caches rely on logout rather than a stop backstop

**Files:** `lives/LifecycleEvents.java:50-62,81-90,163-179`,
`lang/LangService.java:27-28,54-64,74-90`,
`cutscene/CutsceneService.java:166-177,599-628`

- `LifecycleEvents.PENDING_HEART_LOSSES` has a one-hour TTL but no
  `ServerStoppedEvent` clear; a same-UUID player in the next integrated save can inherit a
  stale pending visual handoff.
- `LangService.EXPLICIT_OVERRIDES` is removed on logout but has no whole-map stop clear.
- `CutsceneService.SESSIONS`/`RETURNS` are normally drained by logout (and returns are
  moved to `SavedData`), but there is no stop-event backstop if teardown ordering changes.

These are outside the specifically enumerated lifecycle classes, but they are the notable
additional static-session maps found in the same scan.

### L5. Locale requests accept arbitrary tokens and always trigger a resync

**Files:** `network/C2SLocalePayload.java:10-24`,
`network/LangPayloads.java:19-29`,
`lang/LangService.java:54-72,112-121`

Any explicit non-empty token beginning with `de` becomes `de_de`; every other token becomes
`en_us`. Every request then resends day state, goal progress, and timeline data, even when
the effective locale did not change. This is not an authorization bypass, but an untrusted
client can use repeated requests as avoidable server/network amplification. Enforce the
documented token allowlist and no-op unchanged values (optionally rate-limit).

### L6. The ore “immutable snapshot” exposes mutable band arrays

**Files:** `worldgen/ore/OreConfig.java:48-78,133-159,219-228`,
`worldgen/ore/OreField.java:48-51`

The snapshot's lists/maps are immutable and are safely published through a volatile
reference, but each `ResolvedOre` record exposes its mutable `double[] bandFactor`.
No current caller mutates it, so worker reads are safe in this revision. Returning a copy
or using an immutable value representation would make the documented immutability
enforceable rather than conventional.

## Confirmed anonymity controls

- `anonymity/ChatBlocker.java` cancels all `ServerChatEvent` broadcasts.
- `anonymity/CommandBlocker.java` blocks `/msg`, `/tell`, `/w`, `/me`, `/teammsg`,
  `/tm`, and `/list` below permission 2.
- `anonymity/mixin/PlayerListMixin.java` suppresses the three vanilla join/leave
  translation keys; `MinecraftServerMixin` removes the public status-ping profile sample.
- `ServerGamePacketListenerImplMixin` drops book-edit packets and server command
  suggestions for non-ops; `ClientSuggestionProviderMixin` removes client roster
  suggestions.
- `TabListHider`, `NameTagHider`, and `AbstractClientPlayerMixin` hide stock roster UI,
  player nametags, skins, capes, and elytra textures for an honest client.
- `LifecycleEvents.onServerStarted` forces both `showDeathMessages` and
  `announceAdvancements` false.
- All 18 files under `data/eclipse/advancement/event/` explicitly set
  `"announce_to_chat": false` and `"hidden": true`.
- The custom death screen contains no score, coordinates, killer component, or name.
- Awards render no names; the sidebar payload contains no player-name/online-count field.
- Bossbars created by Eclipse use generic/translatable event/entity labels; the revive
  bossbar does not include `targetName`.
- Dev handbook data contains command/config documentation only and is served only after a
  permission-2 check.
- Real names in server logs and permission-gated operator diagnostics were treated as
  administrative visibility, not ordinary-player leaks.

## Command permission audit

All 27 `RegisterCommandsEvent` handler files were inspected. No `/dev` or `/eclipse*`
command tree is missing its required root gate.

| Root/tree | Gate |
|---|---:|
| All 15 separately registered `/dev` roots (`DevRoot`, music, modcheck, anticheat, xboxevent, display, stage, spawn, timer, viewdist, replay, stats, player, quest, buff) | ≥2 |
| `/eclipse`, legacy `/eclipse goals` | 3 |
| `/eclipse-awards`, `/eclipse-start`, `/eclipse-worldgen` | 2 |
| `/eclipse-quests`, `/eclipse-voice`, `/eclipse-skills`, `/eclipse-rt`, `/eclipsefx`, `/eclipse-buffs`, `/eclipse-analytics` | 3 |
| `/xboxleave` | 0 — explicitly allowed exception |
| `/skills` | 0 — player-facing, not an `/eclipse*` root |
| Client `/eclipse-ui`, `/lang`, `/sprache` | client-side, explicitly allowed |

Several gated operator commands intentionally resolve and print real player names
(`DevAnticheatCommands`, `DevStatsCommands`, `DevXboxCommands`, `AnalyticsCommands`, and
parts of `/eclipse`). Their feedback remains source-only or operator-only and does not
create a permission-0 leak.

## Requested lifecycle matrix

| Service | Static/session state | Stop/persistence result |
|---|---|---|
| `sequence/IntroSequence` | `run`, `TASKS`, `REPLAY_LIGHTNING` | Cleared on `ServerStoppedEvent`; progress/end state is `SavedData` |
| `sequence/ExpansionSequence` | `RUNS`, `TASKS` | Cleared; nether returns are `SavedData` |
| `stormfx/StormRegistry` | storms/sites/id + two counters | Maps/id clear; counters do not (L2) |
| `glitch/GlitchSpawnService` | none | No mutable static session state |
| `devtools/display/DisplayAnimator` | delegates transient selection map | `DisplayPlacerService.clearTransientSelections()`; displays are `SavedData` |
| `awards/AwardService` | signal/reload guards | Session guard reset; ledger is `AwardsState` `SavedData`; reload guard intentionally JVM-lifetime |
| `offering/OfferingService` | signal/reload guards | Session guard reset; ledger is `OfferingState` `SavedData`; reload guard intentionally JVM-lifetime |
| `worldgen/nether/BreachTransferService` | transfer cooldown map | Cleared on stop and logout |
| `worldgen/end/EndDiscService` | active job/warning set | Cleared on stop; cursor/fight state is `SavedData` |
| `worldgen/end/EclipseDragonFight` | dragon, bossbar, count, listeners | Runtime references clear; listener list does not (L3); fight state is `SavedData` |
| `entity/boss/fog/FogBankMarker` | lair map | Cleared on stop |
| `start/StartAssignmentService` | no session collection | Assignments live in `StartState` `SavedData` |
| `hud/SidebarSyncService` | dirty batch/signal guard | Both reset; `EclipseSignals` clears its listener lists |
| `progression/InvLockSync` | last-sent map | Cleared on stop and logout |

The process-lifetime registration guards in `IntroSequence`, `ExpansionSequence`,
`AwardService`, and `OfferingService` are intentionally not all reset: their corresponding
replay/listener/reload registries survive for the JVM. The server-session data they invoke
is reset or save-backed.

## C2S payload matrix

| Payload | Server validation | Result |
|---|---|---|
| `C2SConfigEditPayload` | permission 3, 64 KiB codec/handler cap, filename allowlist, schema normalization | Pass |
| `C2SDisplayEditPayload` | permission 2, wand in either hand, known action dispatch, server raycast/reach for target | Pass |
| `C2SSkillNodeBuyPayload` | node existence, ownership, points, and prerequisites rechecked against server state | Pass |
| `C2SRespawnReadyPayload` | sender-owned flow and ban check, but stage set is too broad | **Medium — M4** |
| `C2SDevHandbookRequestPayload` | permission 2 before any registry/config data is sent | Pass |
| `C2SLocalePayload` | sender-scoped persistence, but no strict token/change/rate validation | **Low — L5** |

## Worldgen thread-safety result

- `DiscMapData.instance` and its seed-keyed noise are volatile; lazy creation uses
  double-checked locking. Published `DiscMapData` contents are effectively immutable.
- `OreConfig` swaps a fully built list/map snapshot through a volatile reference; readers
  see an old or new complete snapshot. L6 is the only mutability escape found.
- `CaveBiomeMap.regionNoise` is volatile, seed-keyed, and double-check synchronized. It
  safely reuses same-seed noise and rebuilds for a different save seed.
- `FrozenParams.Context` is volatile; final seed/radius fields and volatile materialization
  booleans are safe for individual reads.
- The unresolved boundary is **coherence across those separate snapshots during runtime
  refreeze**, plus loss of the two materialization flags (M5).

## Top 3 quick wins

1. **Remove the ghost real-name field:** replace `ownerName` with an opaque/per-session
   token and keep the reveal fully glitched; this closes C2 without changing ghost logic.
2. **Tighten the respawn action predicate:** accept `ACTION_DOOR_SKIP` only when
   `flow.stage == DOOR_OPEN`; reject unknown actions without refreshing state.
3. **Close configurable UI leaks:** always suppress the vanilla scoreboard sidebar and
   sanitize/replace the vanilla death component even when the custom death theater is off.

The larger C1 fix is not a quick win: it requires an explicit threat-model decision and,
for hostile-client anonymity, a server/protocol-level pseudonym design.
