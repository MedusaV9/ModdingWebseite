# WB-ANTIXRAY — behavioral server-side anti-xray

## Scope and registration

The D23 packet-level palette rewrite is deliberately not implemented. It remains expensive,
fragile across client chunk optimizers, and weak against offline regeneration of Eclipse's
deterministic map. No chunk serialization, packet, worldgen, registry, or analytics source
was changed.

`OreExposureRules` and `DevAnticheatCommands` self-register through game-bus
`@EventBusSubscriber` discovery, so no `EclipseMod.java` edit is required. The detector
consumes analytics' existing `EclipseSignals.onNaturalBlockMined` lane. Consequently:

- the six-neighbor exposure test runs during the analytics-owned LOW-priority break event,
  before the broken block is replaced with air;
- creative, spectator, fake-player, and player-placed ore breaks never enter the detector;
- each configured valuable-ore break performs six neighbor reads and one fixed-ring-buffer
  update: O(1) time and O(`players × windowSize`) bounded memory;
- an unavailable neighbor chunk is classified as exposed, intentionally preferring a missed
  detection over a false positive.

`config/eclipse/anti_xray.json` is separate from the existing `anticheat.json` client-mod
screening schema. `AntiXrayConfig` registers with `ReloadHooks`; `/dev reload` atomically
swaps all settings and clears old-size rolling windows. Defaults are a 32-sample window,
eight-sample minimum, 70% soft and 90% hard scores, diamond/deepslate-diamond/ancient-debris,
and `notify_only`. `slowdown` is the only optional hard action. There is no ban action.

## Operator surface

- `/dev anticheat status`
- `/dev anticheat player <player>`
- `/dev anticheat threshold`
- `/dev anticheat threshold soft <0..100>` (permission 3, persisted)
- `/dev anticheat threshold hard <0..100>` (permission 3, persisted)

Merge `docs/plans_v3/langdrop/WB-ANTIXRAY.json` into both shipped locale files, then regenerate
`docs/DEV_COMMANDS.md`.

## Structural xray-resistance analysis

`OreField.tryOre` computes a frozen geographic annulus band and returns `null` when
`band < ore.unlockStage`. Therefore locked valuable ores are physically absent from the
earlier/inner annuli: ordinary strata are generated there and there is no hidden ore block
for a client xray to reveal. Diamond defaults to annulus 3+, while ancient debris defaults
to nether annulus 2+.

`OreField` itself does not read the current day, but its caller supplies the second half of
the structural gate: `DiscChunkGenerator.fillFromNoise` evaluates
`DiscTerrainFunction.column(..., WorldStageAccess.stage(profile), ...)` and skips a column
whose `inside` flag is false. Thus a future annulus generated before its stage unlock is
empty, not a hidden ore-bearing disc. The existing runtime ring-growth sweep rewrites those
chunks when the committed stage advances; chunks first generated after that advance also
use the wider stage.

Accordingly, “pre-unlock xray cannot reveal those ores because the server has not placed
them” is accurate for the normal committed-stage flow. Strictly this is an **unlock-stage**
guarantee, not a calendar guarantee: progression maps days to stages elsewhere, and an
operator can advance a stage manually. After a stage unlocks, placement remains deterministic
from the frozen map seed, so an attacker with the seed/config can regenerate coordinates
offline exactly as D23 warns.

Practical defense is therefore layered:

1. inner locked annuli contain no later-tier ore at all;
2. future annuli are empty until the committed stage materializes them;
3. after access unlocks, rolling server-observed mining behavior notifies operators when a
   player repeatedly reaches fully encased valuable ore;
4. the existing client-mod screening remains a deterrent, not a trusted proof.

No cheap fake-block or seed-shuffle layer was added because D23 does not specify one, and
rewriting generated ore coordinates would break the frozen deterministic world contract.

## Integration/testing

`gametest/anticheat/OreExposureTests` exercises ring eviction, score math, minimum-sample
gating, threshold bands, input bounding, and the notify-only default. The detector exposes
read-only `playerScore`, `playerScores`, and `status` query methods for `/dev` and future
stats integration; no analytics API change was needed.
