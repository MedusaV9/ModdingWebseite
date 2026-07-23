# P4-B6 wiring notes — daily awards + altar offerings v2

No `EclipseMod.java`, `EclipsePayloads.java`, registry, progression, skills, analytics, or
devtools file was edited.

## Files

- `awards/AwardConfig`, `AwardMath`, `AwardsState`, `AwardService`, `AwardCommands`
- `offering/OfferingConfig`, `OfferingRules`, `OfferingState`, `OfferingService`
- owned altar edits: `ritual/AltarBlock`, `ritual/AltarBlockEntity`
- gametests: `gametest/awards/AwardGameTests`, `gametest/offering/OfferingGameTests`
- lang handoff: `docs/plans_v3/langdrop/P4-B6.json`

## Self-wiring

| System | Registration / behavior |
|---|---|
| `AwardService` | `@EventBusSubscriber`: loads `awards.json`, registers `ReloadHooks` key `awards`, consumes day PRE/POST, delivers pending rewards at login, resets signal/config statics on stop |
| `OfferingService` | `@EventBusSubscriber`: loads `offering_values.json`, registers `ReloadHooks` key `offerings`, consumes day PRE idempotently, resets signal/config statics on stop |
| `AwardCommands` | `RegisterCommandsEvent`: `/eclipse-awards preview\|resolve\|reroll [day]`, permission 2 |
| `AltarBlock` | LOWEST `RightClickBlock` handles sneak-item offering because vanilla skips block interaction; existing lure/sigil/finale routes retain priority |
| SavedData | overworld `eclipse_awards.dat` and `eclipse_offerings.dat`; no explicit registration |

`AwardService` explicitly calls `OfferingService.resolveDay` before award resolution instead
of relying on subscriber ordering. Offering PRE also resolves itself; both paths are guarded by
the persisted day record.

## Altar signals

- milestone: `AltarBlockEntity.handleMilestoneDeposit` fires `MILESTONE` with the exact
  consumed count;
- offering: `OfferingService.accept` fires `OFFERING` exactly once after one/day state accepts;
- shard bank: `AltarBlock` intercepts the existing sneak-shard path, calls
  `ShardEconomy.deposit`, then fires `SHARD_BANK` with the deposited stack count.

The frozen A1 signal has no value/`ItemStack` field. `OfferingService` snapshots `altar_value`
before/after firing it and reconciles only the difference to the exact component-aware value
through the existing public `AnalyticsState.add` API. This produces exact enchant-aware
`altar_value` without double-counting and leaves `analytics/**` read-only. A future additive
`fireAltarDeposit(..., valuePoints)` overload would remove that compatibility top-up.

## Reveal seams

- PRE snapshots analytics, freezes winners/rewards, queues offline rewards, and never
  re-resolves a persisted day.
- POST calls `AwardService.sendRevealNow(server)` after `DayScheduler` has started the
  expansion sequence.
- P2's expansion cinematic may call the same public method at its actual final beat. Re-sends
  are safe; P3 owns overlay queue/dedup presentation.
- Login replays the latest unseen resolved reveal and claims all pending rewards.

The checked-in A1 `S2CAwardRevealPayload.Category` shape is
`id/titleEn/titleDe/rewardTextEn/rewardTextDe/candidates/winners`; it does **not** contain the
dedicated `winnerIndex/statLine/rewardLine` fields stated in the P3 handoff. B6 does not own
that frozen payload. B6 persists proper bilingual `statLine`/`rewardLine`; on wire it sends
`title + "\n" + statLine` and uses the existing reward fields. P3 should split on the first
newline for the roulette overlay. Preferred hub follow-up: the A1/P3 payload owner adds the
explicit fields and maps `winners` to tie-aware reveal cards.

## Merge asks

1. Merge `docs/plans_v3/langdrop/P4-B6.json` into both real language files.
2. P2 should call `AwardService.sendRevealNow(server)` at expansion-cinematic completion if
   POST is earlier than the desired visual beat.
3. P3 renders UUID-only candidates/winners as anonymized heads and must support multiple
   winners (ties receive the already-split reward).
