# P4-B1 wiring notes (Real-time day engine, R1/§2.1)

Worker **P4-B1** owns `progression/realtime/*` (new), `progression/DayScheduler.java`
(rework), `devtools/PhaseScheduler.java` (delegate rework), `gametest/realtime/*`. No
foreign hub file was edited.

## Already self-wired (no hub edit required)

| System | Registration |
|--------|--------------|
| `RealtimeDayService` | `@EventBusSubscriber`: `ServerTickEvent.Post` (20t bar/sync, 100t fire check), `ServerStartedEvent` (migration + auto-arm + catch-up), `ServerStoppedEvent` (statics reset), player login/logout (bar + clock payload) |
| `RealtimeConfig` | `ReloadHooks.register("realtime", …)` — `/eclipse admin reload` hot-reloads `realtime.json`; re-anchor happens on the next fire check |
| `RealtimeCommands` | `@EventBusSubscriber` `RegisterCommandsEvent` — NEW root `/eclipse-rt` (perm 3); the untouchable `/eclipse` tree is not modified |
| `gametest/realtime/*` | `@GameTestHolder(EclipseMod.MOD_ID)` self-registration |
| `S2CDayClockPayload` client fill | Already real in A1's `EclipsePayloads.handleDayClock` → `ClientStateCache` (verified — no stub left); B1 only added the server-side sending |

## Hub / sibling follow-ups

| Target | Owner | Need |
|--------|-------|------|
| src lang JSONs | Hub | Merge `langdrop/P4-B1.json` — 11 keys per locale (`command.eclipse.rt.*`, `bossbar.eclipse.schedule.paused`). Base key `bossbar.eclipse.schedule` already exists (W14). |
| `network/S2CDayClockPayload.java` | A1/Hub | **Optional (P3-W6 decides):** plan §2.1 muses a transient "pre-shift boundary" field for the add/subtract spool animation. The landed 6-field shape does NOT have it; P3 can animate from consecutive payloads (see cadence below). If P3 wants the extra field, that payload edit is hub-owned. |
| `progression/goals` etc. | B2/B4/B9 | Subscribe `EclipseSignals.onDayRollover` — PRE fires with state still on the ended day, POST after all legacy side effects and the re-anchored clock. Catch-up replays PRE/POST once per missed day (quiet). |
| docs / server guide | Hub | `general.json dayAutoAdvance` is now parsed-but-IGNORED (one-time deprecation WARN); `config/eclipse/realtime.json` is the replacement. |

## `realtime.json` (auto-created in `config/eclipse/` on first load)

```json
{
  "zone": "Europe/Berlin",
  "boundaryTime": "18:00",
  "autoArmOnStartEvent": true,
  "catchUpMaxDays": 13,
  "clientSyncSeconds": 5
}
```

## FROZEN `RealtimeDayApi` surface (P5-W3 builds commands on exactly this)

```java
RealtimeDayApi.arm(server)                        // long — next boundary epoch millis (recurring cadence)
RealtimeDayApi.disarm(server)                     // void — no further advances, countdown hidden
RealtimeDayApi.isArmed(server)                    // boolean
RealtimeDayApi.isPaused(server)                   // boolean
RealtimeDayApi.pause(server)                      // long — frozen remaining millis, -1 = not running
RealtimeDayApi.resume(server)                     // long — new boundary (now + frozen), -1 = not paused
RealtimeDayApi.addMillis(server, ±deltaMillis)    // long — new remaining millis, -1 = disarmed (clamp ≥ now+5s)
RealtimeDayApi.setBoundary(server, spec, zone)    // long — target epoch millis; throws IllegalArgumentException
RealtimeDayApi.status(server)                     // String — one status line
```

Specs: `+NhNNm[NNs]` relative or ISO-8601 local date-time (`2026-07-23T18:00[:ss]`)
interpreted in the passed zone. Every mutator broadcasts `S2CDayClockPayload` itself.
`/eclipse schedule next|clear` and `/eclipse day set` keep working verbatim through the
`PhaseScheduler` delegate + `DayScheduler` re-anchor.

## `S2CDayClockPayload` cadence (P3-W6 sidebar/spool)

Broadcast to ALL players: on arm/disarm/pause/resume/add/set, after EVERY day change, on
player login (single send), and re-synced every `clientSyncSeconds` (default 5 s) while
armed. Client fields land in `ClientStateCache` (`dayClockDay`, `boundaryEpochMillis`,
`prevBoundaryEpochMillis`, `serverNowEpochMillis`, `dayClockPaused`,
`pauseRemainingMillis`, `clockSyncLocalMillis`).

- Offset: `serverNowEpochMillis - System.currentTimeMillis()` sampled at receipt
  (`clockSyncLocalMillis` stores the receipt instant).
- `boundaryEpochMillis == 0` → clock hidden (disarmed).
- `paused == true` → render `pauseRemainingMillis` frozen.
- Spool animation for add/subtract: each shift broadcasts immediately — animate from the
  previously cached remaining to the new payload's remaining (no extra field needed).
- Progress-bar origin: `prevBoundaryEpochMillis` (window start), i.e.
  `progress = (boundary - now) / (boundary - prevBoundary)`.

## Rollover order (choke point in `DayScheduler.applyDay`)

`dayRollover PRE (state still on ended day)` → persist day + bell/announcements
(`quiet` suppresses these during catch-up) → `applyDayTriggers` ring expansion +
`SundialPlaza` → `RealtimeDayService.onDayApplied` (boundary re-anchor / one-shot
consume / maxDay disarm) → `dayRollover POST` → clock broadcast. Non-±1 jumps
(`/eclipse day set 6`) fire NO signals (admin correction), but still re-anchor and
broadcast both day-state and clock payloads.
