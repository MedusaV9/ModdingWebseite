# PORTAL RECIPE — adding a portal-event variant (1 page)

The C18 extraction: every one-off portal event (xbox tutorial worlds, the Backrooms,
whatever comes next) is startable through ONE dev surface —
`eventdim/PortalEventScheduler` + `/dev portal <variant> open|close|roll|list`.
This is the recipe for adding variant number three.

## What a variant is

One `PortalEventScheduler.Variant(id, rarity, opener, closer)`:

- `id` — the `/dev portal` literal (`xbox`, `backrooms`, …). Lowercase, no spaces.
- `rarity` — `COMMON` (weight 4) or `RARE` (weight 1); feeds `/dev portal roll`'s
  weighted lottery. New tiers = new enum constants in `Rarity`, one place.
- `opener(server, operator)` — starts your event; return `null` on success or the
  player-facing error `Component` (your service's start-refusal message).
- `closer(server)` — graceful stop; same null-or-error contract.

Registration is one `PortalEventScheduler.register(...)` call. The two launch variants
live in the scheduler's own static initializer; a NEW variant should self-register from
the variant's OWN service/registrar class instead (static init or a bootstrap hook — the
repo's self-registration pattern), so the scheduler file stays frozen.

## The checklist (what C18 actually shipped, as the template)

1. **Dimension** — datapack pair `data/eclipse/dimension_type/<id>.json` +
   `data/eclipse/dimension/<id>.json` (void flat generator), plus a tiny
   `<Id>Dimension` key/helper class. Steal `backrooms.json` verbatim; mind
   `fixed_time` (midnight disarms `TheOtherEntity.despawnAtDawn`, noon kills most
   undead cameos — pick deliberately).
2. **State** — a `SavedData` with `Phase {IDLE, ANNOUNCED, OPEN, CLOSING}`,
   `endsAtEpochMillis`, `instanceId`, per-instance sets. `BackroomsState` is the copy
   source; keep the instanceId-scoped lockout map and the `markX()` once-per-instance
   law (persisted booleans, not transient flags).
3. **Service** — the `XboxEventService`/`BackroomsEventService` skeleton: dev-triggered
   start, `ServerTickEvent.Post` state machine, T-5/T-1 warnings, bossbar for insiders,
   return anchors, protected deaths (HIGHEST-priority `LivingDeathEvent` cancel while
   inside), eject-on-close. Budget any world stamping across ticks during ANNOUNCED
   (`stampCursor` in the SavedData so a crash resumes).
4. **Portal** — `BackroomsPortal` is the frameless C16 build: one tagged
   `minecraft:interaction` (3×4), rift FX payload with your own style byte, always-on
   server-particle fallback. Claim the next free style value (0 structure, 1 xbox,
   2 backrooms).
5. **Transition** — send `S2CPortalFxPayload(ENTER, "eclipse:<id>_style", 30)` right
   BEFORE each teleport (`GatePayloads.sendPortalFx`); unknown styles render
   `PortalTransitionController`'s default cover, so this works before any client art.
6. **Leave command** — `/<id>leave` with click-confirm (`BackroomsLeaveCommand`
   pattern), localized, lockout on voluntary exit only.
7. **Dev tree + docs** — `/dev <id> start|stop|status|time|portal|lockout` subtree
   (`DevBackroomsCommands` pattern) and `DevCommandRegistry.register(...)` docs from a
   static initializer. Lang keys via a langdrop
   (`docs/plans_v3/langdrop/<TAG>.json`, `{"en":{},"de":{}}` accepted) merged with
   `tools/langmerge/merge_langdrops.py`.
8. **Scheduler** — finally, `PortalEventScheduler.register(new Variant(...))` and smoke
   it: `/dev portal list`, `/dev portal <id> open`, `/dev portal <id> close`,
   `/dev portal roll` until your variant comes up.

## Rules that are not optional

- **Death inside is free** where the design says "safe to be scary" (Backrooms law) —
  cancel the death BEFORE the lives pipeline, no drops, no lockout. If your event
  wants death-lockouts (xbox's mode), make it a config, not a hardcode.
- **Everything per-instance is keyed by `instanceId`**, never wall-clock.
- **Deterministic world stamping** — seed from `ECLIPSE_SEED ^ salt ^ instanceId` so a
  crash re-stamp rebuilds byte-identical geometry.
- **No shared-file edits**: your own registrars, your own `@EventBusSubscriber`s, one
  `EclipseMod` wiring line if you register entities/sounds. The xbox and backrooms
  files stay frozen.
