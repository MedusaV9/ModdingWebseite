# EVAL-POLISH-S — v5 crash/correctness audit

**Scope:** read-only review of the four v5 waves, focused on physical-side safety,
mixins, dimensions, persistence/lifecycle, death-event ordering, transient display
cleanup, tick budgets, and stale configuration behavior.

**Score: 6.0 / 10.**

There is no confirmed dedicated-server classloading crash, invalid dimension definition,
SavedData factory mismatch, or double life decrement. The release still has three
production correctness/performance defects and two cleanup/budget defects worth fixing
before shipping: the new event dimensions are absent from the shared event-dimension
predicate, existing extended anti-cheat configs do not acquire the newly required nested
IDs, the credits transition performs about 44,588 block writes in one tick, chunk regen
rewrites a whole 10k–50k+ block-state chunk in one tick, and credits displays are not swept
after interruption.

## Release findings

### POL-S-01 — HIGH — the shared event-dimension predicate omits all three new v5 event dimensions

`XpGates.isEventDimension` contains only Limbo, minigames, and the Xbox map set
(`XpGates.java:67-71`). It does not include `BackroomsDimension.BACKROOMS`,
`ArenaDimension.ARENA`, or `CreditsSequence.EPILOGUE`.

This predicate is broader than XP:

- action XP remains enabled in Backrooms, the Ferryman arena, and the epilogue;
- `QuestEngine.increment` continues recording quest progress there;
- `RebirthService` permits a rebirth during those scripted events;
- `HeartTheftService.evaluate` does not return `NO_STEAL_EVENT_DIMENSION`, so PvP in
  Backrooms/the arena can consume permanent lives and arm the pair cooldown.

The four new Xbox dimensions are covered correctly because
`XboxDimensions.isXboxDimension` iterates the expanded `BY_WORLD_ID` map
(`XboxDimensions.java:35-42,69-70`). The omission is limited to the independently added
Backrooms, Ferryman, and credits dimensions.

**Fix:** make the shared predicate include the three keys and extend
`XpGateTests.eventDimensionPredicate`; consumers should continue using this one predicate.

### POL-S-02 — HIGH — the credits beach stamp performs about 44,588 writes synchronously

`beatEpilogue` reaches `stampBeach` from the credits tick machine. `stampBeach`
(`CreditsSequence.java:773-811`) executes the entire 175×61 set in one server tick:

- 32,025 base-slab writes (three layers);
- 10,675 surface writes;
- 1,404 barrier-rim writes;
- 484 lane-rail writes.

Every one also calls `getChunk` immediately before `setBlock`. This is a production finale
path, not a dev-only tool, and it exceeds the review's 10k single-tick threshold by more
than four times. A cold epilogue dimension additionally pays synchronous chunk loads in
that same tick, risking a visible watchdog-length freeze during the final transition.

**Fix:** persist a beach-stamp cursor and run it through `BudgetedBlockWriter` while the
screen is black; teleport/release the runners only after completion.

### POL-S-03 — HIGH — existing anti-cheat allowlists reject the newly documented nested IDs

The migration check only tests whether top-level schema keys exist
(`AntiCheatCheck.java:163-177`). Once an existing file already has `allowedMods`,
`requiredMods`, and `optionalMods`, migration is considered complete. `parse` then accepts
the on-disk maps/lists wholesale (`AntiCheatCheck.java:503-516`); it does not merge newly
shipped optional IDs from `defaults()`.

Consequently, an upgraded event server with a pre-v5 extended `anticheat.json` still lacks
the new `fabric_*`, `mixinsquared`, Photon/LDLib2/KilaGraph, and other nested/library rows.
In allowlist mode, clients using the now-supported Sodium/Iris/Supplementaries pack are
reported as `extra` and disconnected. `docs/BUNDLING.md` says these IDs “are allowlisted,”
but does not warn that existing configs must be regenerated or snapshotted.

**Fix:** either schema-version and merge new optional defaults without overwriting operator
pins, or explicitly document and surface the required `/dev modcheck snapshot`/manual
migration on upgrade.

### POL-S-04 — MEDIUM — `/dev chunk regen` is chunk-paced, not block/time-budgeted

The tick handler calls `job.tickOneChunk()` exactly once per tick
(`ChunkRegen.java:168-181`). That method runs all 256 columns, the whole base rewrite,
pipeline replay, heightmap prime, rescue, and relight queue synchronously
(`ChunkRegen.java:286-355`). `writeColumn` writes a full 16-block run for every intersecting
or non-air section (`ChunkRegen.java:365-383`).

At the center of the overworld disc, the lens spans roughly y=-130 through y=70, so one
chunk alone executes about 14 sections × 16 rows × 256 columns = **57,344 direct section
writes**, before feature replay. The class claim that “one chunk per tick” cannot stall is
not a meaningful budget. The command is permission-3/destructive, reducing exposure, but
it still violates the explicit no-10k-writes criterion and can trip watchdogs on slower
hosts.

**Fix:** cursor by section/column through `BudgetedBlockWriter` (or a nanosecond budget),
then run the chunk-finalization steps once its rewrite cursor completes.

### POL-S-05 — MEDIUM — interrupted credits displays persist with no boot/load sweep

Credits block displays are correctly tagged as `eclipse_credits_wheel` and
`eclipse_credits_flyer` (`CreditsSequence.java:168-171,659-710`). Normal/skip paths discard
the in-memory references. On restart, however, `onServerStarted` only marks an interrupted
run complete (`CreditsSequence.java:207-216`), while `onServerStopped` merely nulls the run
and task list (`CreditsSequence.java:219-223`). It never queries or join-sweeps either tag.

A stop/crash after the wheel or flyers are saved therefore leaves permanent display
entities in Limbo/the epilogue. This is exactly the orphan case handled by
`StructureFlightFx.onEntityJoin`, `EndShatterSequence.sweepDebris`, and
`ArenaFight.sweepMorphDisplays`.

**Fix:** add a tag-based entity-load sweep (stronger than querying only currently loaded
chunks), covering both credits tags.

### POL-S-06 — LOW — pending heart-loss visuals leak across integrated-server saves

`LifecycleEvents.PENDING_HEART_LOSSES` is a static mutable map
(`LifecycleEvents.java:52-64`) with TTL pruning only on the next death. Unlike adjacent
death/rescue services, `LifecycleEvents` has no `ServerStoppedEvent` cleanup. If a player
leaves one integrated-server save on the death screen and opens another save within an
hour, a respawn of the same UUID can consume the old save's entry and emit bogus heart
burst/quasar visuals.

This does not decrement a second life—the respawn handler only sends effects—but it
violates per-save lifecycle isolation.

**Fix:** clear the map on `ServerStoppedEvent`.

## Requested-area verification

### Client/server distribution safety

No confirmed defect.

- `CreditsPayloads`, `CollectionsPayloads`, and `BackroomsPayloads` use installable
  common-side `Consumer` hooks and contain no eager client-class fields/static
  initialization.
- `ShardPayloads.handleShardGain` directly names `ShardGainToast`, but the handler is
  registered only with `playToClient` (`ShardPayloads.java:60-77`). The symbolic client
  target is reached only when that clientbound handler executes; registration itself uses
  a method reference to the common `ShardPayloads` method. This matches the existing
  `EclipsePayloads`, `FxPayloads`, and `RewardPayloads` lazy handler-body pattern and is
  not a dedicated-server crash by itself.
- Storm state is likewise registered `playToClient`; no C2S/server handler reaches
  `StormFxClient`.

An installable hook would make `ShardPayloads` stylistically consistent, but the current
code is not a release finding without a server-reachable invocation.

### Mixins

No confirmed defect.

- `eclipse.worldgen.mixins.json` contains `NaturalSpawnerMixin`, and
  `neoforge.mods.toml` registers that config (`neoforge.mods.toml:50-61`).
- Its package root (`dev.projecteclipse.eclipse.mixin`) is disjoint from the core
  anonymity root and client root, so there is no config/package collision.
- The injection is a static RETURN injection matching the static
  `NaturalSpawner.getRandomPosWithin(Level, LevelChunk)` seam.
- `ClientSuggestionProviderMixin` is in the client-only config and guards
  `Minecraft.getInstance().player == null` before permission access
  (`ClientSuggestionProviderMixin.java:34-42`). A null connection/player during menus or
  disconnect masks suggestions rather than crashing.

### Dimensions

The seven reviewed JSONs are structurally coherent:

- every `type` reference exists (`backrooms`, `epilogue`, `limbo`, `xbox_classic`);
- every generator is the built-in `minecraft:flat`, with valid existing biome IDs;
- type heights are legal multiples of 16 and logical heights do not exceed height:
  Backrooms 0/32/32, Limbo and epilogue 0/384/384, Xbox 0/256/256;
- Backrooms geometry y=8..15 fits its 32-block range; epilogue beach y=60..66 fits 384;
  Ferryman uses the Limbo type and its generated 49-layer ocean fits that range.

The service-level dimension omission is POL-S-01, not a datapack registration failure.

### SavedData and event ordering

The reviewed factories all match the NeoForge 1.21.1
`new SavedData.Factory<>(constructor, loader)` pattern. Collections, rebirth, arena,
Backrooms, shatter, launcher, and theft data save and load the same fields/types; mutators
that change durable state mark dirty. No codec/NBT type mismatch was found.

Death routing does not double-decrement:

- `PreEventSafety` cancels at `HIGHEST`; lower listeners do not opt into canceled events,
  so `LifecycleEvents` at `NORMAL` never reaches `LivesApi.add`.
- `LifecycleEvents` performs the one victim decrement. `HeartTheftService.evaluate` is
  pure and only the `STEAL` branch credits the killer/records cooldown.
- `ContractService` at `LOW` grants contract rewards/modifiers but does not mutate
  permanent lives. Contract-pair evaluation suppresses the theft gain while retaining the
  normal death loss, matching the documented contract economy.

One intentional-but-sharp edge remains: a killer already at `MAX_HEARTS` receives no
heart, while the victim still loses one and the cooldown/ceremony records a “steal”
(`LifecycleEvents.java:109-125`). The v5 plan explicitly preserves the existing cap, so
this audit does not classify it as an implementation regression, but product should
confirm that a capped steal is meant to be a life sink.

### Display cleanup

- `StructureFlightFx`: tag + entity-join sweep + server-stop statics cleanup — safe even
  when the owning chunk was unloaded at boot.
- `EndShatterSequence`: tag + TTL + boot AABB sweep.
- `ArenaFight`: tag + normal discard + boot AABB sweep.
- `CreditsSequence`: tagged, normal-path discard only — POL-S-05.

### Tick budgets

- Backrooms: 16 cell units per tick; a normal unit is roughly 512 shell writes plus
  dressing, keeping the worst regular tick around 8k–9k writes. Boundary is one smaller
  unit. It is operation-spread, though adding the shared nanosecond budget would be safer.
- End shatter: cursor is resumable, work is bounded by config and a 2 ms clock, and chunk
  finalization occurs at a chunk boundary.
- Snow recovery: queued through `BudgetedBlockWriter`, maximum 1,024 columns/slice and at
  most two writes per qualifying column.
- Chunk regen: fails the budget requirement — POL-S-04.
- The unrequested but production-critical credits stamp also fails — POL-S-02.

### Config regeneration

- `goals.json`/`quests.json`: existing files intentionally remain unchanged, and
  `goals_v5_migration.md` clearly tells operators to delete/regenerate or hand-apply the
  new ladder/schema.
- `realtime.json`: missing `cadenceMode`/`intervalHours` fields safely parse as
  `daily`/2.0; operator commands persist both fields without replacing unrelated keys.
- `anticheat.json`: stale extended files are neither merged nor accompanied by an upgrade
  warning — POL-S-03.

## Priority order

1. Add Backrooms/Ferryman/epilogue to the shared event-dimension predicate and tests.
2. Budget the epilogue beach construction before the credits teleport.
3. Migrate or loudly document existing anti-cheat allowlists for nested IDs.
4. Make chunk regen genuinely resumable below the block/time budget.
5. Sweep both credits display tags on entity load.
6. Clear `PENDING_HEART_LOSSES` at server stop.

## Verification note

This was the requested static, read-only audit. No Gradle tasks, game launch, Git command,
or source-code mutation was performed; only this report was written.
