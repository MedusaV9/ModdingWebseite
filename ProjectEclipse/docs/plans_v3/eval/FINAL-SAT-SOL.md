# FINAL-SAT-SOL — Newest Systems Correctness Audit

Scope: static, read-only audit of `contracts/`, `wand/`, `minigames/`,
`entity/wizard/`, `movement/EdgeGlideService`, the new `drama/` services,
`progression/bestiary`, and `voice/VoiceChanger`. No Gradle task or live-server action
was run, per the audit instructions. Line references are approximate and refer to the
audited revision.

Severity means:

- **Critical** — can deterministically lose a recurring durable reward, permanently eat
  terrain, or lose/duplicate a player's real inventory across a credible crash boundary.
- **High** — major economy/state failure or an exploitable escape from a core event path.
- **Medium** — materially wrong behavior on a credible gameplay edge.
- **Low** — narrow operator edge or abuse surface whose intended policy is not explicit.

## Critical

### C1. Offline contract survivors can receive the queued consolation only once per save

**Files:** `contracts/ContractService.java:571-585`,
`awards/AwardService.java:223-239`, `awards/AwardsState.java:141-152,164-181`

When a target is offline at expiry, the contract queues the reward with the constant ID
`"contract_survived"`. `AwardsState` treats delivered IDs as permanent per-player
idempotency keys. After that player claims one such reward, every later contract they
survive while offline is rejected as already delivered; two expiries before the first
claim also collapse into one pending row. Online targets bypass the queue and are paid
directly, so reward eligibility depends on being connected at the expiry tick.

The ID must include the contract instance/day (for example
`contract_survived:<contractDay>`), while retries for that same instance reuse the same ID.

### C2. Phasenwelle can permanently replace terrain with air after a crash

**File:** `wand/WandPhaseService.java:117-126,149-192,211-234,314-316`

The crash-safety comment promises that snapshots reach disk before terrain vanishes, but
`Data.add` only mutates memory and the later `setDirty()` merely schedules a future
SavedData save; it does not flush a journal. During vanish, the block is changed to air
before `entry.vanished` is marked and before the final batched `setDirty()`.

Chunk data and overworld SavedData are separate persistence streams. A crash can therefore
leave the chunk containing air while the last durable entry is absent or still has
`vanished=false`. Boot recovery restores only entries whose persisted flag is true, then
clears every entry. That mismatch makes the missing block permanent. Persist/flush a
prepare record before the world mutation, then use an idempotent phase journal whose boot
recovery also reconciles `vanished=false` records against the actual block.

### C3. A minigame ticket is not durably committed before the real inventory is erased

**Files:** `minigames/MinigameService.java:460-490`,
`minigames/MinigameState.java:335-350,357-396`

Entry calls `putTicket`, teleports, and clears the player's real inventory in one server
turn. `putTicket` only marks SavedData dirty; it does not force the ticket to disk before
player NBT can persist the adventure-mode kit. A crash/save-order boundary can therefore
persist the kit-equipped player without the ticket, leaving login rescue with nothing to
restore. The reverse partial ordering can also replay a ticket over changes already made
after a prior restore.

The safety claim requires a durable entry transaction: persist a ticket with an instance
ID and phase before destructive mutation, and make restore/consume an idempotent,
reconcilable operation rather than relying on call order inside one tick.

## High

### H1. Leaving a minigame dimension outside the named routes leaks the disposable kit

**File:** `minigames/MinigameService.java:503-542,605-638,640-690`

The service handles `/minigameleave`, close/timeout, stale death, and login rescue, but has
no `PlayerChangedDimensionEvent` (or equivalent per-tick outside-dimension reconciliation).
If another command, mod transport, or admin teleport moves a participant out while the
event remains active, the player keeps the arena/race kit in the normal world and their
real inventory remains trapped in the ticket until relog. Before relog they can use or
drop the disposable gear, turning a recovery omission into item leakage.

### H2. Starting a new minigame erases an offline participant's old reward entitlement

**Files:** `minigames/MinigameState.java:173-191`,
`minigames/MinigameService.java:544-563,607-637`

`beginInstance` deliberately retains old tickets but clears `participants` and
`rewardedParticipation`. If a participant logs out inside instance A, A closes, and
instance B starts before they return, their ticket still restores their inventory, but
`grantParticipationIfOwed` consults B's freshly cleared participant set. The instance-A
participation reward is permanently lost. Tickets and reward entitlements need the same
persisted instance identity and must be settled before their owning instance bookkeeping
is discarded.

### H3. Arena podium rewards are discarded for offline winners

**File:** `minigames/ArenaGame.java:213-264`

Round ranking includes every UUID in the persisted score map, but payout is performed only
when `server.getPlayerList().getPlayer(uuid)` is non-null. An offline top-three player is
announced in the anonymous podium, receives nothing, and then `clearKills()` destroys the
only evidence needed to pay them later. Queue a stable per-instance/per-round reward for
offline winners instead of silently skipping it.

### H4. Minigame payouts are not crash-idempotent

**Files:** `minigames/ArenaGame.java:213-264`,
`minigames/MinigameService.java:534-563`,
`minigames/MinigameState.java:230-241`

Arena `endRound` clears the round deadline before directly granting shards/XP and clears
scores only after all grants. Participation similarly persists `rewardedParticipation`
before applying its direct grants. These markers and the player economy live in different
save records, with no stable queued reward transaction. A crash can persist player rewards
but old round state (duplicate podium payout on resume), or persist the completion marker
without the player mutation (lost podium/participation payout). The existing in-memory
guards prevent duplicate calls only within one uninterrupted process.

### H5. A failed native voice pipeline is retried forever and bypasses the budget kill switch

**Files:** `voice/VoiceChangerPlugin.java:73-111,126-155`,
`voice/VoiceChangerService.java:61-81`

Any decode/DSP/encode `Throwable` is logged and the original packet passes through, but the
failing `Pipeline` remains in `PIPELINES`; its decoder, encoder, and DSP state are neither
reset nor closed/replaced. The handler retries the same potentially corrupt native codec
objects on every microphone packet. Failed frames also never call `reportFrameNanos`, so
the budget kill switch cannot stop this failure loop. Remove-and-close the pipeline on
failure (with per-close protection), account the failed frame, and lazily create a clean
pipeline on the next packet.

## Medium

### M1. A hunter can leave during the omen/window with no fallback or cancellation

**File:** `contracts/ContractService.java:305-339,680-725`

Target logout is explicitly tracked and replaced by a hittable logout ghost. Hunter logout
has no corresponding branch. If the selected hunter leaves during `ANNOUNCED`,
`beginActive` still frightens/reveals the target but sends no hunter reveal; if they leave
while active, the window continues without any way for the target to turn the tables.
This enables collusive free survivor payouts and turns the headline event into empty
theater. Cancel/reselect during the omen, and define a persisted active-window hunter
logout resolution.

### M2. Trading mode lets a non-owner alter another player's selected wand power

**Files:** `wand/EclipseWandItem.java:97-117`,
`wand/WandPowers.java:162-177`, `wand/WandSoulbind.java:39-58`

Soulbind correctly preserves a foreign owner while trading is enabled and casting rejects
non-owners. Sneak-use is different: `EclipseWandItem.use` calls `cycleSelected` directly,
and that method performs no ownership check. A borrower can therefore rotate the physical
wand's `WAND_SELECTED` component before returning it. Because selected power is not part of
the PLAYER-mode store mirror, the owner can unexpectedly cast a different and costly
ability. Apply the same `tick` + `isOwner` validation used by casting/path choice.

### M3. Feuerwelle can hit tightly clustered entities multiple times in one ring tick

**File:** `wand/WandTickService.java:202-220`

The outer query snapshots all ring victims before `hit` is updated. For each victim it
then calls `damageAround` with a 0.5-block radius, which damages every nearby living entity,
not just that victim. Two or more mobs occupying the same space each trigger an area call,
so each can take the configured wave damage multiple times despite the documented “at most
once” invariant. Damage the selected victim once, or collect all unique victims before
applying damage.

### M4. The wizard fetch quest can permanently consume the once-only grant without delivery

**Files:** `entity/wizard/WizardOrinEntity.java:374-419`,
`entity/wizard/WizardData.java:111-133`

The once-per-player ledger is advanced before ingredients are consumed and before the
catalyst enters inventory/world. A crash or exception after that durable marker but before
delivery leaves the player marked complete with no catalyst; the normal interaction can
never retry, and the source comment explicitly relegates recovery to an operator-only
`resetquest`. Because SavedData and player/entity persistence are not atomic, the opposite
save ordering can also persist the item without the ledger and permit a second grant.
A pending/completed transaction with idempotent delivery is required.

### M5. The “guaranteed” wizard catalyst drop is disabled by `doMobLoot=false`

**File:** `entity/wizard/WizardOrinEntity.java:542-558`

The catalyst is emitted from `dropCustomDeathLoot`. Vanilla invokes custom death loot only
inside the mob-loot gamerule path, so a server running with `doMobLoot=false` gets no
catalyst even though the feature promises a drop independent of loot tables and kill
credit. If the take-path must be guaranteed, spawn it from a guarded death/removal path
with an entity-persisted “drop emitted” latch, not the gamerule-gated loot callback.

### M6. Edge glide does not honor `FreezeService`

**Files:** `movement/EdgeGlideService.java:110-149,172-235`,
`cutscene/FreezeService.java:232-270`

The glide tick never checks `FreezeService.isFrozen`. A frozen airborne player near a
lower notch who looks up satisfies lift entry because Freeze's PRE tick has zeroed velocity;
EdgeGlide's POST tick then starts the trail and writes upward velocity every tick. Freeze
usually rubber-bands/zeros it on the next PRE tick, but glide remains armed and can take
over immediately when the TTL releases, producing bogus FX and an unexpected launch at a
cutscene boundary. Frozen players should terminate/not enter either glide mode.

### M7. Kills advance entries explicitly defined as sightings-only

**Files:** `progression/bestiary/BestiaryService.java:87-105`,
`progression/bestiary/BestiaryTiers.java:22-30,47-57`

The kill listener increments every `eclipse:` entity without consulting
`isSightingProgress`. Killing Orin therefore advances the same count that is documented as
observation-only; forced/edge deaths of a gazer do the same. This undermines the special
progression contract. For sighting IDs, a kill may mark encountered, but must not increment
the sighting count.

### M8. The 16-block bestiary encounter rule is actually a much larger box

**File:** `progression/bestiary/BestiaryService.java:122-160`

`getEntitiesOfClass` is run on `player.getBoundingBox().inflate(16)` with no Euclidean
distance predicate. An entity near a diagonal corner can be more than 22 blocks from the
player (plus bounding-box extent) and still unlock an encounter/sighting. Add an explicit
`distanceToSqr <= ENCOUNTER_RANGE²` check so progression matches the stated radius.

### M9. Turning the voice effect OFF can skip the end-of-transmission reset

**File:** `voice/VoiceChangerPlugin.java:73-103`

The handler returns immediately when the effective preset is OFF, before reading the empty
Opus end marker. If a player disables the preset (or the global budget switch trips) before
that marker, the existing decoder/encoder and tremolo phase are not reset. Re-enabling
later resumes stale codec/effect state even though intervening original Opus packets were
never fed through that pipeline, causing avoidable artifacts and state divergence. Handle
the end marker/reset before the preset-OFF fast path.

### M10. One fast speaker can prevent the global voice budget switch from ever tripping

**File:** `voice/VoiceChangerService.java:61-81`

`overBudgetStrikes` is one global counter, and any under-budget frame resets it to zero.
Frames from multiple speakers interleave on the packet path, so a consistently slow
speaker can be masked by another speaker's fast frames. Conversely, a burst of unrelated
slow first frames can trip the global switch. Track consecutive strikes per pipeline (and
optionally a separate rolling aggregate overload metric) before making a global disable
decision.

## Low

### L1. Two idle accounts provide unlimited hearth healing

**File:** `drama/HearthAuraService.java:72-127`

The aura checks only alive/not-banned, proximity, and a shared lit campfire. It has no
activity, combat, hunger, or unique-human policy, so one player plus an idle alt can obtain
the event's only ambient heal indefinitely. This may be an intentional “sit together”
policy; if AFK farming is not intended, require recent movement/interaction or suspend the
pulse during combat/AFK. The implementation also carries a player's timer between different
qualifying hearths if they move between them within a 40-tick scan interval.

### L2. Rapid loud day changes silently discard the earlier dawn ceremony

**Files:** `drama/DawnCeremony.java:102-119`,
`awards/AwardService.java:91-109,207-220`

Every `begin` clears all pending ceremony tasks. If an operator advances two consecutive
days within the 10-second sequence, the first day's announcement, goals beat, and award
reveal are dropped; POST already suppressed the inline reveal because the first ceremony
was running, and the surviving T+200 task broadcasts only `latestResolvedDay`. Normal
real-time catch-up uses quiet intermediate days and avoids this, so impact is limited to
rapid manual loud changes.

## Requested edges verified without a concrete defect

- **Contracts:** target environmental death correctly resolves `VOIDED`; PRE rollover
  expires/cancels every non-idle phase; target logout uses the matching ghost owner UUID;
  prank expiry uses its own reveal path. The hunter gap is M1.
- **Wand:** cast payloads run on the server thread and validate held stack, owner, selected
  unlock, charge, cooldown, protection, and path. Rapid physical swaps do not create a
  data race. First-path locking itself rejects an already chosen path; M2 is the remaining
  ownership gap.
- **Minigames:** explicit leave, timeout/dev close, stale-dimension death, and login rescue
  do funnel through ticket restoration. The missing arbitrary dimension exit, cross-instance
  bookkeeping, offline podium, and crash transaction are H1-H4/C3.
- **Wizard:** tracked-UUID resolve plus loaded-entity/near-home adoption prevents the normal
  restart duplicate. Death and respawn both use the same vanilla overworld-day counter, as
  required by the shipped `/time add 24000` test procedure.
- **Movement/drama:** the horizontal glide clamp only reduces speed and is not itself a
  fling bug. Quiet catch-up days correctly skip `DawnCeremony`; normal loud rollovers gate
  the inline award reveal as intended.
- **Bestiary:** default/boss tier thresholds and full-snapshot replacement on the client are
  internally consistent. M7/M8 are progression-source/range defects, not payload-shape errors.
- **Voice:** the preset mirror uses a concurrent map plus volatile globals, and server-start
  rebuild is sound. The failures are codec recovery/reset and the semantics of the global
  strike counter, not the basic SavedData-to-voice-thread publication.
