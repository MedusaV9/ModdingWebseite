# P5-W34 wiring — dev bridges and ConfigEditor v2

## Registration

No `EclipseMod.java` or `EclipsePayloads.java` edit is required:

- `DevTimerCommands`, `DevBuffCommands`, `DevQuestCommands`, `DevPlayerCommands`,
  `DevStatsCommands`, and `DevViewDistance` are game-bus `@EventBusSubscriber` classes.
- Every `/dev` leaf self-registers through `DevCommandRegistry` during class initialization,
  so `/dev help`, the handbook, and generated docs discover the same surface.
- `DevViewDistance` also owns login and tick listeners. Its falling-edge check of
  `ViewDistanceService.isActive()` restores persisted pins after a transient cutscene.
- ConfigEditor v2 intentionally keeps the existing payload registrations. The
  `S2COpenGoalEditorPayload` string now carries a versioned `daysConfig` + `goalsConfig`
  envelope, and the unchanged `C2SConfigEditPayload` wire shape sends ordered
  `goals.json`/`days.json` edits.

## Integration actions

1. Merge `docs/plans_v3/langdrop/P5-W34.json` into both shipped language files.
2. Regenerate `docs/DEV_COMMANDS.md` after the command classes are present.

## Existing APIs verified

- `RealtimeDayApi` broadcasts `S2CDayClockPayload` from every successful mutation; no
  extra timer payload send is required.
- `VoiceMuteApi.setForceMuted` already persists per-player mutes, and
  `EclipseVoicePlugin` already rejects microphone packets through
  `VoiceMuteApi.isMuted`. No voice backend/plugin change was necessary.
- Buff commands call the existing global `TimedBuffApi`; ore doubling still reaches the
  existing natural-block check and does not bypass anti-abuse.

## Coordinate migration

`PlacedBlockData` v2 persists a format marker plus the dimension minimum section. On the
first `PlacedBlockCheck` lookup of legacy data it converts absolute `y >> 4` keys to
`level.getSectionIndex(y)` keys and dirties the chunk. The compatibility `sectionBits`
entry point translates later calls from the unchanged analytics tracker, so old and new
chunks remain readable without editing another worker's `PlacedBlockTracker`. Migration
uses the first queried section as a probe so helper/test attachments that were already
written with a level-relative key are not shifted twice; ambiguous legacy maps prefer the
production tracker's old absolute format.

## Cross-worker limitation

P2's current `ViewDistanceClient` treats every positive `S2CViewDistancePayload` as an
upward-only cinematic bump (`max(requested, current)`). W34 persists, replays, removes and
orders pins correctly, but a pin below a player's current client setting cannot lower it
until P2 extends its transport with exact/persistent semantics (while preserving the
client opt-out). This worker does not edit `cutscene/**` per ownership rules.
