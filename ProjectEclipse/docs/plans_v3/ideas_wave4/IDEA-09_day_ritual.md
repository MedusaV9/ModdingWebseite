# IDEA-09 — Day-Cycle Ritual Moments (10 ideas, ranked best-first)

Collector: 9/20, "Eclipse Event" wave 4. Scope: the recurring day-rollover beat — dawn
ceremony sequencing, morning announcements, goal reveal, offering deadline, awards ceremony.
Small-to-medium hooks into EXISTING systems only; every idea names exact files/hooks and an
effort tag (S/M).

**Ground truth (read before ranking):** the entire loud rollover stack executes in ONE server
tick inside `progression/DayScheduler.applyDay` — PRE `dayRollover` (offerings settle via
`OfferingService.resolveDay`, awards freeze via `AwardService.resolveDay`) → persist →
`S2CDayStatePayload` → flat vanilla `BELL_BLOCK` → `AnnouncementService.onDayChanged`
(day typewriter + sweep, unlock sweeps, timeline rebroadcast) →
`WorldStageService.applyDayTriggers` → `SundialPlaza.onDayChanged` (instant ~40-block
rewrite) → `RealtimeDayService.onDayApplied` → POST `dayRollover`
(`AwardService.sendRevealNow` roulette broadcast + `QuestEngine.runPollNow` personal-quest
assignment + sidebar dirty) → `broadcastClock`. Two implemented drama pieces already frame
the moment: `client/drama/LastMinuteHush` (60 s duck/dim/heartbeat, releases at T-0) and the
`DayTimerLayer`/`DayTimerCache` zero-blink. Everything below exploits gaps in that seam.

---

## 1. The Dawn Ceremony — one ordered arc instead of a single-tick pile-up *(M)*

Today the bell, the day typewriter, up to N unlock sweeps, the sidebar refresh, the
`quest.eclipse.assigned` actionbar AND the awards roulette payload all land in the same server
tick; on non-expansion days the roulette (up to ~75 s of `AwardsOverlay`) plays *concurrently*
with the day announcement sweep. Introduce a tiny server-side presentation sequencer —
`progression/DawnCeremony` — using the exact `Task`/`schedule()` pattern already proven in
`sequence/ExpansionSequence` (lines ~653–680). `applyDay` keeps ALL state changes synchronous
(persist, triggers, signals, sundial, clock — untouched); only the loud path's *presentation*
calls move into spaced beats: T+0 hush release lands (already client-side) → T+10 sun pulse
(idea 2) → T+20 dawn toll (idea 7) → T+40 day announcement (`AnnouncementService.onDayChanged`)
→ T+~140 goals reveal (idea 5) → T+~200 `AwardService.sendRevealNow`. For the awards beat:
`AwardService.onDayRollover` POST currently calls `sendRevealNow` inline — gate it behind
`DawnCeremony.isRunning(server)` so the ceremony owns the timing on non-expansion days, while
expansion days keep the existing END-seam call in `ExpansionSequence.beginEnd` (the client
dedupes by day via `AwardsOverlay.HANDLED_DAYS`, so the double-send stays safe).

- Hook: `progression/DayScheduler.applyDay` (the `changed && !quiet` block),
  `awards/AwardService.onDayRollover` (POST branch), new `progression/DawnCeremony` with the
  `ExpansionSequence` task-list pattern; statics reset on `ServerStoppedEvent` per house rule.
- Guards: `setDayQuiet` catch-up path never starts a ceremony (unchanged); a mid-ceremony
  restart simply drops the pending beats — every beat is a re-broadcastable payload, no state.

## 2. Land the flip ON T-0 — near-boundary precision + dawn sun pulse *(S)*

`RealtimeDayService` checks the boundary only every `FIRE_CHECK_TICKS = 100` (5 s), so the day
flip can land up to 5 s AFTER `LastMinuteHush` releases and `DayTimerCache` fires
`ui.timer_zero` — dead air exactly at the climax, different every night. Fix: in
`onServerTick`, when `state.getBoundaryEpochMillis() - now < 15_000`, run `runFireCheckNow`
every `BAR_UPDATE_TICKS` pass (one long compare per second; the epoch-day guard already makes
extra checks idempotent). Then give the flip a visible sky beat: a 30-tick "eclipse blink" —
`FxPayloads.sendEclipsePhase(server, BUILDUP, 0.35F, 10, permanentRim)` followed by a
scheduled `ENDING, 0.0F, 30` — the eclipsed sun swallows for one breath as the new day is
proclaimed. This is the same payload pair `ExpansionSequence.beginSkyward`/`beginEnd` already
uses, at lower intensity, so the client grade path needs zero new code.

- Hook: `progression/realtime/RealtimeDayService.onServerTick` (tighten),
  `network/fx/FxPayloads.sendEclipsePhase` + the idea-1 scheduler (blink), skip when an
  `ExpansionSequence` run is live (its grade owns the sky) and on `reducedFx`-irrelevant
  server side — the grade ramp is already cheap client-side.

## 3. The Day-Number Moment — typography as iconography *(S/M)*

The day announcement is currently a hotbar-height typewriter line; the day *number* — the one
datum every player structures their memory around — never gets visual weight. When a
`STYLE_DAY` announcement dequeues in `client/hud/AnnouncementOverlay`, render a center-screen
numeral card first: "DAY 7" at 4–6× scale using `DayTimerLayer`'s fixed monospace digit cells,
with the old day's digits odometer-rolling up to the new day (reuse the per-cell scissor +
`CELL_ROLL_HEIGHT` roll that `DayTimerLayer` already implements for the spool), a
`GlitchText` shimmer settle (the `client/handbook/GlitchText` used by the awards overlay), one
`ui.roulette_win` settle sting, hold ~30 ticks, then shrink toward the sidebar day row as the
existing typewriter line begins. Day 14 renders in the warn accent (`EclipseUiTheme` deep
purple). `reducedFx`: static card, no roll. Everything is client-local — the day number is in
the payload path and `ClientStateCache.dayClockDay`.

- Hook: `client/hud/AnnouncementOverlay` (STYLE_DAY branch of the queue), digit-cell craft
  from `client/hud/DayTimerLayer`, `client/handbook/GlitchText`, `EclipseUiTheme`; no server
  change, no new packets.

## 4. Last Call at the Altar — offering-deadline warning ritual *(S/M)*

Offerings settle silently at PRE rollover (`OfferingService.resolveDay`); a player who forgot
simply loses the day, and learns it from nothing. Add a two-stage deadline ritual driven from
the same tick loop that owns the boundary: at T-10 min and T-60 s (computed from
`RealtimeState.getBoundaryEpochMillis` in `RealtimeDayService.onServerTick`, once per stage
per boundary), every online player failing `OfferingService.hasOfferedToday(player)` gets a
PRIVATE whisper caption — `S2CCaptionPayload(…, STYLE_WHISPER)`, the exact channel
`ExpansionSequence` uses for `CAPTION_NETHER_RETURN` — plus a muffled low bell
(`playNotifySound(BELL_BLOCK, 0.4F, 0.6F)`). At the sanctum itself, the altar's
`ritual/BeamEmitter` flickers during the final minute so the deadline is legible in the world,
not just the HUD. No global text, no names: abstaining stays anonymous (the nightly tally is
IDEAS-A #8's job); this is purely a mercy-tap on the shoulder.

- Hook: `progression/realtime/RealtimeDayService.onServerTick` (two stage flags reset in
  `onDayApplied`), `offering/OfferingService.hasOfferedToday`,
  `network/fx/S2CCaptionPayload` STYLE_WHISPER, `ritual/BeamEmitter` +
  `EclipseWorldState.getSanctumAltarPos()`. Guards: engine armed && !paused; skip stages that
  are already inside the `LastMinuteHush` window (T-60 s tap fires at T-90 s instead so it
  never fights the hush).

## 5. "Today's Decrees" — a real goal-assignment reveal *(M)*

New personal quests are assigned on POST rollover (`QuestDetectors` → `QuestEngine.runPollNow`
→ `ensurePlayer`) and announced with a single actionbar line, `quest.eclipse.assigned` — the
weakest beat of the whole morning. Replace it with a sequenced reveal card that plays after
the day announcement finishes (idea-1 beat, or client-side keyed off `dayClockDay` change +
the next `S2CQuestStatePayload`): the day's MAIN goals typewrite in one by one
(`TypewriterLine` + `UI_TYPEWRITER` are shared craft), then the player's personal draws flip
up card-by-card with `UI_PAGE_TURN`, each with its progress target. All data is already on the
client via `S2CQuestStatePayload`; this is pure presentation. Sneak skips (the `AwardsOverlay`
accessibility convention), `reducedFx` shows the finished list instantly, and the card is
suppressed under letterbox exactly like the awards layer.

- Hook: new small client layer next to `client/awards/AwardsOverlay` (reuse its queue/dedupe
  pattern), `client/hud/TypewriterLine`, quest lines from the synced quest state cache; server
  side only deletes the `displayClientMessage(quest.eclipse.assigned)` line in
  `progression/goals/QuestEngine.ensurePlayer` (or keeps it as the reduced-fx fallback).

## 6. "Take your seats" — awards ceremony pre-beat and collision gate *(S/M)*

Two fit-and-finish problems in the roulette seam: (a) on non-expansion days the show starts
the same instant the day announcement sweep is still playing (see idea 1 — but the client
should also defend itself); (b) `AwardService.sendRevealNow` plays `AWARD_STING` server-side
at broadcast time, which on expansion days is the cinematic END — yet the client show may
start seconds later if queued behind letterbox, so the sting and the visuals detach. Fix
client-side: expose `AnnouncementOverlay.isIdle()` (queue empty && no active sweep) and make
`AwardsOverlay`'s show-start check wait for it, exactly like it already waits on
`LetterboxLayer`; move the sting client-side to the INTRO phase of the show (keep the server
sting only as the payload-arrival cue for players with the overlay hidden). Then open every
show with a 40-tick "take your seats" pre-beat: HUD/sidebar dim to ~60% (the `LastMinuteHush`
wash craft at lower alpha) with a slow `UI_ROULETTE_TICK` count-in, so the room settles before
the first head spins.

- Hook: `client/hud/AnnouncementOverlay` (new `isIdle()`), `client/awards/AwardsOverlay`
  (start gate + INTRO pre-beat + sting), `awards/AwardService.sendRevealNow` (sting note).

## 7. The Dawn Toll — replace the flat bell *(S)*

The rollover cue is a single vanilla `SoundEvents.BELL_BLOCK` at pitch 1.0 — indistinguishable
from a village bell. Make it a signature: three descending strikes (pitch 1.0 → 0.84 → 0.7)
spaced 8 ticks via the idea-1 scheduler (or a 3-entry inline task if idea 1 doesn't land),
finished with a quiet `EVENT_ECLIPSE_DRONE` tail fading over ~2 s. Day 7 (mid-arc) adds a
fourth strike; day 14 tolls five, slower — players learn to count the bell and know where they
are in the arc without reading anything. Quiet catch-up days stay silent (unchanged), and the
toll constants live next to the existing bell call so the diff is one screen.

- Hook: `progression/DayScheduler.applyDay` (the `playNotifySound(BELL_BLOCK…)` loop),
  `registry/EclipseSounds.EVENT_ECLIPSE_DRONE`, day count from the already-in-scope `newDay`
  vs `EclipseConfig.maxDay()`.

## 8. The Shadow Walks — sundial sweep instead of a teleporting line *(M)*

`SundialPlaza.onDayChanged` erases and re-stamps the basalt shadow line in one tick — the one
physical, in-world day indicator moves invisibly. Animate it: erase the old line block-by-block
outward, then place the new angle's blocks inward over ~30 ticks (scheduled via the idea-1
task list; ~40 total block writes, trivially budget-safe), each placement emitting a small
basalt-dust `S2CQuasarPayload` puff + `UI_CAPTION_TICK` for players within ~24 blocks; finish
with a one-shot gilded flash on the r=11 ring marker the shadow now points at and a 5 s
`ritual/BeamEmitter` column so even distant players see the sanctum register the new day.
Players who make a habit of greeting the dawn at the plaza get a real ceremony; nobody else
pays anything.

- Hook: `worldgen/structure/SundialPlaza.onDayChanged` (split erase/place into scheduled
  steps), `network/S2CQuasarPayload`, `ritual/BeamEmitter`,
  `EclipseWorldState.getSanctumAltarPos()`. Guard: fall back to the instant rewrite when no
  player is within ~64 blocks (don't animate for nobody) and on chunk-not-loaded.

## 9. "The World Moved On" — catch-up digest instead of a sweep flood *(M)*

After a multi-day offline catch-up, the FINAL loud day diffs every skipped day's unlock keys
into one announcement burst (documented in `DayScheduler` and
`AnnouncementService.announceNewUnlocks`) — the client `AnnouncementOverlay` queue caps at 8,
so a long absence can literally drop unlock announcements, and what survives is a minutes-long
sweep parade. When `RealtimeDayService.runCatchUpNow` advanced ≥ 2 days, pass the advanced
count into the loud rollover (a static handoff mirroring `rollingOver`/`pendingBoundary`) so
`AnnouncementService.onDayChanged` emits ONE digest instead: "Days 4–6 passed in your absence.
Five seals opened." as a single `STYLE_DAY` sweep, with the full key list posted to chat once
(the typewriter already posts completed lines to chat — same channel). Restores dignity to the
morning after downtime and stops the queue-cap information loss.

- Hook: `progression/realtime/RealtimeDayService.runCatchUpNow` (count handoff),
  `timeline/AnnouncementService.onDayChanged`/`announceNewUnlocks` (digest branch when
  `skippedDays > 0`), lang keys for the digest line (en/de per `Localized` convention).

## 10. The Morning Paper — a recap for late risers *(M)*

Players who log in after a rollover get no day announcement, and reveal replays are
deliberately suppressed (`AwardsOverlay` LATE_JOIN_GRACE_TICKS; login payloads are marked seen
in `AwardService.onPlayerLoggedIn`) — a returning player wakes into day N with zero morning
context. Send them a compact "morning paper" card on login instead of a show: day number +
`days.json` title (server-side literals via `TimelineService.dayTitleKey`), one line per
resolved award category winner from `AwardsState.resolved(latestResolvedDay())` (anonymized
strings are already baked bilingual in the payload records), and today's MAIN goals. Client
renders it with the `AwardsOverlay` summary-card craft (compact list, no roulette), dismissed
by any key. One new small S2C payload, or reuse `S2CAwardRevealPayload` with a `recap` flag.

- Hook: `awards/AwardService.onPlayerLoggedIn` (branch: seen-but-new-session → recap),
  `timeline/TimelineService.dayTitleKey`, quest mains from `S2CQuestStatePayload` already sent
  at login by `QuestEngine`; client card next to `client/awards/AwardsOverlay`'s summary
  renderer.

---

### Ranking rationale (one line)

1–2 make the boundary land as ONE readable ceremony on the exact second (the sequencer plus
the 5-second-slop fix are the enabling infrastructure); 3 gives the ritual its icon; 4 adds
stakes before the cut; 5–6 turn the two buried reveals (goals, awards) into staged beats; 7–8
dress the moment in sound and stone; 9–10 keep the ritual dignified for the absent.
