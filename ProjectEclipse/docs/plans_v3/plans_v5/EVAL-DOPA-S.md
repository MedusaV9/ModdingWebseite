# EVAL-DOPAMINE-S — v5 dopamine plumbing audit

**Scope:** read-only correctness review of collections, recipe locks, XP gates, shard
economy, heart theft, and client celebration queues.

**Score: 5.5 / 10.**

The main collection lanes are genuinely connected and the heart-theft policy is mostly
sound, but three core promises are not server-tight: pickup progress can be recycled,
recipe locks can be bypassed by quick-moving/automation, and several things called
"shards" do not fund the personal balance consumed by rebirth. Two smaller reward/UI
faults make real payouts disappear or visually collide.

## Findings

### DOPA-S-01 — HIGH — RecipeGate enforces too late; shift-click and automation bypass it

`RecipeGate.onItemCrafted` only observes `PlayerEvent.ItemCraftedEvent` and empties
`event.getCrafting()` (`RecipeGate.java:166-175`). The event is not cancellable and is
fired from the result slot's post-take path. Vanilla/NeoForge quick-move moves the output
into the destination inventory before `Slot.onTake`; shrinking the result-slot remainder
does not remove the already moved copy. This is the same post-facto pattern in
`ModGate.java:136-145`.

Consequences:

- normal click is confiscated, but shift-click/recipe-book-then-shift-click can retain the
  locked result;
- the vanilla Crafter and other automated crafting paths never emit a player
  `ItemCraftedEvent`, so they bypass per-player collection locks entirely;
- config `recipes` entries are sent to EMI but never checked by server enforcement:
  `onItemCrafted` checks only the result item through `isItemLockedFor`.

NeoForge's menu contract explicitly documents that quick move transfers first and then
calls `onTake`:
<https://docs.neoforged.net/docs/1.21.1/gui/menus>.

The synchronization half is present: `CollectionsService.sweep` calls
`RecipeGate.syncTo(player)` on tier-up (`CollectionsService.java:258-261`), and
`RecipeGate.onPlayerLoggedIn` calls it on login (`RecipeGate.java:159-163`).

There is also a client refresh defect: `EclipsePayloads.handleRecipeLocks` only replaces
the two cache lists (`EclipsePayloads.java:289-292`). It does not call
`EmiReindexer.requestReload`, so a tier-up payload arrives but EMI can remain baked with
the old lock set until another reload/relog. `ClientUnlockCache` has the required
change-detect + reindex pattern; recipe locks do not.

### DOPA-S-02 — HIGH — pickup thrower check blocks direct Q-repickup, not item laundering

The implementation does use the correct raw UUID:

- `AnalyticsService.handleItemCollected` rejects `itemEntity.thrower != null`
  (`AnalyticsService.java:327-344`);
- `META-INF/accesstransformer.cfg:13-16` makes that exact field public;
- the pickup amount is correctly derived as `original.count - current.count`;
- the raw thrower UUID survives an offline thrower, unlike entity-resolving `getOwner()`.

That prevents the direct player-drop/repick loop. It does **not** make an item count only
once. After the first credited pickup, putting the shard through a dropper/dispenser, or
putting it in a container and breaking the container, creates a new `ItemEntity` with no
player thrower. Every pickup is credited again. No counted marker exists on the
`ItemStack` or in a UUID/entity ledger. The design claim that container laundering can
only under-credit is therefore false.

### DOPA-S-03 — HIGH — the rebirth currency is not what boss “shard” rewards pay

`RebirthService` checks and deducts only `ShardEconomy.getShards/addShards`, the personal
`eclipse:shards` attachment (`RebirthService.java:126-134`,
`EclipseAttachments.java:44-54`).

| Source | Actual destination | Funds rebirth? |
|---|---|---|
| Quest numeric `reward.shards` | `ShardEconomy.addShards` | Yes |
| Contracts | `ShardEconomy.addShards` | Yes |
| Awards / offering winner | `ShardEconomy.addShards` | Yes |
| Minigames | `ShardEconomy.addShards` | Yes |
| Admin shard commands | personal balance | Yes |
| Herald / Rift Warden / Fog Tyrant | physical items via `deliverShardItems` | No |
| Skill-perk shard proc | physical item via `deliverShardItems` | No |
| Backrooms and day-1 altar quest item rewards | physical items | No |
| Physical shard altar deposit | team pool only | No |
| Collections tiers | XP/points/unlocks only | No |

Boss payout code deliberately labels the split as physical/team-pool value, so this is
not an accidental call-site typo. It is nevertheless a correctness mismatch if bosses
are intended as a rebirth earn lane: their prominently named shard rewards can never pay
the personal rebirth cost. Collections also do not implement the D1 optional shard hook:
`CollectionsConfig.Tier` has no shard field and `CollectionsService.sweep` has no
`ShardEconomy` call.

### DOPA-S-04 — HIGH — award XP is claimed and then silently eaten by XpGates

The explicit exemption set is `quest`, `altar`, `advancement`, `death`, `admin`,
`collection`, and `contract` (`XpGates.java:30-37`). Quest and collection rewards
therefore pay before the event and in event dimensions as intended. Contract,
advancement, and altar reward XP also pay. Wand and minigame keys remain gated, which
matches their action/minigame policy.

`AwardService`, however, grants with source `"award"`
(`AwardService.java:330-343`), which is absent from the exemption set. Worse, it records
the durable claim before calling `SkillsApi.addXp`. Claiming an award while pre-event or
in limbo/minigame/xbox permanently consumes the reward record and applies zero XP.

The configurable collections `xpSourceKey` is another footgun: changing it from the
default `"collection"` also removes the exemption and silently gates tier XP.

### DOPA-S-05 — MEDIUM/HIGH — collection and shard toasts directly collide

`LevelUpOverlay` uses `CenterStageArbiter` correctly
(`LevelUpOverlay.java:143-153`). `CollectionTierToast` and `ShardGainToast` bypass it and
self-register direct GUI render callbacks. They also have independent queues and almost
identical positions:

- collection toast: `guiHeight - 84`, often two lines;
- shard toast: `guiHeight - 82`, one line.

When both are active, their cards render two pixels apart and overlap almost completely.
A collection XP tier can also trigger `LevelUpOverlay` in the same tick; that is not
serialized with either toast. These are direct-render bypasses, not merely queue-order
edge cases.

### DOPA-S-06 — MEDIUM — collection tier idempotency is normal-path safe, not crash-atomic

The normal relog/restart path does not double-grant:

- `grantedTiers` is monotonic and persisted in `eclipse_collections`;
- the sweep writes the claimed tier before granting XP/points
  (`CollectionsService.java:237-249`);
- login only syncs and does not re-sweep (`CollectionsService.java:139-143`);
- reload/new credit sweeps only tiers above the stored index.

However, claimed tiers and XP live in separate files:
`eclipse_collections.dat` and `eclipse_skills.dat`. Both are merely marked dirty; the tier
transaction does not use `EclipseSavedData.flushOverworld` or a journal. A crash during a
multi-file save can therefore persist skill XP but not the claimed tier (later sweep
replays XP), or persist the claim but not XP (reward is permanently lost). Relog itself
is safe; crash consistency is not. The current gametest checks in-memory repeat calls and
individual NBT round-trips, not a torn cross-file restart.

## Lane-by-lane collection trace

| Lane | Producer | Consumer | Verdict |
|---|---|---|---|
| natural mine | `AnalyticsService.handleBreak` after `PlacedBlockTracker.clear`, only when `wasPlaced == false` | `CollectionsService.handleNaturalBlockMined` | Fired and correctly natural-only |
| mob kill | `AnalyticsService.handleMobKilled` from non-player `LivingDeathEvent` with tracked player killer | `handleMobKilled` | Fired |
| altar deposit | `AltarBlockEntity` (milestone), `OfferingService` (offering), `AltarBlock` (shard bank) | `handleAltarDeposit`, filtered to `SHARD_BANK` | Fired; shard amount is stack count |
| crop harvest | `AnalyticsService.handleBreak` before the placed-block return, for `CropBlock.isMaxAge` | `handleCropHarvested` | Fired; wheat/carrot work |
| item collected | `ItemEntityPickupEvent.Post` in `AnalyticsService` | `handleItemCollected` | Fired; direct throw dedup only |

The crop predicate matches the configured vanilla `CropBlock` crops (wheat and carrot;
potato/beetroot would also work). Stem blocks are not `CropBlock` and do not fire the
harvest lane. The configured stem crop is pumpkin itself, intentionally counted through
the natural-mine lane: stem-generated fruit has no placed bit, while hand-placed pumpkin
does. That configuration is correct. Adding a future stem id to the `harvest` lane would
not work; its fruit must use the same natural-mine pattern.

## HeartTheftService

The core paths are server-thread serialized, so there is no Java data race:

- victim at `floorLives` returns `NO_STEAL_FLOOR` before decrement and freezes all Leben
  movement;
- a successful steal decrements the victim, then credits the killer, then records the
  cooldown;
- cooldown records are `SavedData`, call `setDirty`, store epoch millis, and survive a
  clean restart;
- direction-independent lookup prevents immediate traded farming.

Remaining correctness edges:

1. Simultaneous reciprocal projectile kills are order-dependent. The first processed
   kill records the pair cooldown; the second is classified `NO_STEAL_COOLDOWN` and loses
   no Leben at all. This is deterministic on the server thread, but not a symmetric trade.
2. A killer already at `MAX_HEARTS` still makes the victim lose a Leben, records a
   “steal,” and plays the steal ceremony while the killer receives nothing
   (`LifecycleEvents.java:109-125`). The transfer becomes a sink.
3. An offline shooter is not queued a payout. If the damage source no longer resolves to
   a live `ServerPlayer`, the death follows the PvE path; if a stale player object does
   resolve, there is no `hasDisconnected` guard and mutating that already-saved player
   risks losing the gain on restart.
4. Persistence is durable on normal shutdown/save, but the Leben attachments and cooldown
   ledger are separate persistence streams, so a hard crash can tear the transfer from
   its cooldown record.

## Priority repair order

1. Enforce recipe locks at result-slot `mayPickup`/menu level (and define automated
   crafting policy), not in post-craft notification.
2. Replace thrower-null as the sole pickup identity with durable “already credited”
   provenance, or make the collection consume-on-pickup.
3. Name/separate physical team shards from personal rebirth currency, or route intended
   rebirth sources (especially bosses/collections) to personal `addShards`.
4. Add `"award"` to reward exemptions and test claim inside every gated dimension.
5. Put collection/shard toasts behind one shared bottom-toast arbiter/queue.

## Verification note

This was the requested read-only audit. No Gradle, application, Git, or code mutation was
performed; evidence is static call-site and lifecycle tracing.
