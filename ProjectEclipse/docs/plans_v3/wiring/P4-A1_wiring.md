# P4-A1 wiring notes

No hub/foreign file edits required for wave A.

## Consumed by wave B (read-only for them)

- `core/config/ReloadHooks` — register config reload hooks; invoked from `EclipseConfig.reload()`
- `core/signal/EclipseSignals` — intra-mod signal bus; register on `ServerStartedEvent`
- `core/state/EclipseSavedData.getOverworld(...)` — overworld SavedData factory helper
- `core/time/EclipseClock` — injectable epoch millis for gametest determinism
- `core/util/ExhaustionScaler.registerFactor(...)` — shared hunger-drain scaling
- `buffs/TimedBuffApi` + `TimedBuffApi.Holder` — B9 sets implementation on server start
- `registry/EclipseItems.HEART_EXTRACTOR`, `GLITCH_SHARD`
- `registry/EclipseSounds.SKILL_*`, `AWARD_STING`, `OFFERING_ACCEPT`, `RITUAL_EXTRACT`
- `registry/EclipseAttachments.PLACED_BLOCKS` + `analytics/PlacedBlockData`
- All new payloads registered in `network/EclipsePayloads` (stub S2C → `ClientStateCache`)
- `gametest/GameTestSupport` + template `eclipse:gametest.empty`

## Optional future hub touches (NOT done in A1)

- P5 `/dev reload` should call the same path as `/eclipse reload` → `EclipseConfig.reload()` → `ReloadHooks.runAll()` (already wired in A1).
- P3 replaces stub cache consumers with real UI; no `EclipseMod.java` change needed.

## Containment FX constant (R13)

P2 registers Quasar emitter `eclipse:containment_bounce`. Constant lives in wave B7
(`ContainmentService`); not part of A1.
