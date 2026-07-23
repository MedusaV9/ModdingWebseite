# WB-BOSSBAR (P3-W6) — Bossbar v3 + day-timer HUD (integration ledger)

## What landed

| File | Status | Role |
|---|---|---|
| `client/hud/BossbarSkin.java` | reworked (v3) | §3.5: entrance/exit state machine, animated fill (P2 `fill_anim.png` probe + procedural fallback), damage flash + micro-shake + trailing damage ghost, generalized NOTCHED_6/10/12/20 phase ticks, ORNATE/SLIM styles, in-band name (DIM→TEXT flash), boss-theme frame breathing. Same registration path as v2: game-bus `CustomizeGuiOverlayEvent.BossEventProgress` (+ a new `RenderGuiEvent.Post` pass for the event-less exit ghosts). Public API kept: `setTheme`, `nextFreeBarY`, both `drawThemedBar` overloads (AnnouncementOverlay still compiles untouched). NEW public: `reserveOverlayRow(int)` (see below). |
| `client/hud/DayTimerCache.java` | NEW | §3.6 data half: derives remaining/window/warn state from the EXISTING `S2CDayClockPayload` fields in `ClientStateCache` (`boundaryEpochMillis`, `prevBoundaryEpochMillis`, `serverNowEpochMillis`, `dayClockPaused`, `pauseRemainingMillis`, `clockSyncLocalMillis`) — no new payload, no `network/**` edits. Detects dev spools (boundary/pause-window jump while day + pause-state unchanged), tracks the 00:00 crossing and fires `UiSounds.timerZero()` exactly once per boundary. Frozen §7.2 API for W5: `remainingMillis()` / `warnMillis()` (plus `displayedRemainingMillis`, `remainingFraction`, `paused`, `armed`, `day`, `spooling`, `spoolRising`, `zeroBlinkStartMillis`). Self-registering (`@EventBusSubscriber` client tick). |
| `client/hud/DayTimerLayer.java` | NEW | §3.6 render half: top-center `HH:MM:SS` (`DD:HH:MM` ≥ 48 h) at 1.5x in fixed monospace cells, `TEXT→ACCENT→ACCENT_DEEP` color ramp (last 10% strongly purple), thin remaining-fraction underline, per-digit odometer roll during spools, final-10s pulse, 3-blink + DIM hold at zero, paused = DIM + slow alpha pulse + localized caption. Hidden: `showDayTimer=false`, F1, cutscene HUD suppression (not whitelisted). §2.3 appear motion (5t fade + 4px rise); `reducedFx` snaps everything. |
| `client/EclipseGuiLayers.java` | 1 registration added | `event.registerBelow(AnnouncementOverlay.LAYER_ID, DayTimerLayer.LAYER_ID, DayTimerLayer::render)` — this file was assigned to W6 this wave, so the line is already applied (NOT a pending ledger item). The letterbox whitelist is deliberately unchanged (timer + bossbar hide during cutscenes). |
| `docs/plans_v3/langdrop/WB-BOSSBAR.json` | NEW | 2 keys (`gui.eclipse.timer.paused`, `gui.eclipse.timer.zero`), en+de. |

## Integrator MUST-DOs

1. **Langdrop**: merge `docs/plans_v3/langdrop/WB-BOSSBAR.json` into `assets/eclipse/lang/{en_us,de_de}.json`. (`subtitles.eclipse.ui.timer_zero` already exists — no new subtitle needed.)
2. Nothing else — no `EclipseMod`/`network`/`registry`/sounds edits. `ui.timer_zero` was already registered (`EclipseSounds.UI_TIMER_ZERO` + `sounds.json`) and is consumed via the existing `UiSounds.timerZero()` helper.

## Layer-order contract (IMPORTANT for future EclipseGuiLayers edits)

`DayTimerLayer` MUST stay **below** (= rendering before) `AnnouncementOverlay`: the timer
draws at `BossbarSkin.nextFreeBarY()` and then calls `BossbarSkin.reserveOverlayRow(bottom)`
so the announcement sweep (which reads `nextFreeBarY()` during ITS render) stacks under the
timer instead of on top of it. NeoForge's `registerBelow(other, …)` inserts directly before
`other`, so the current line is deterministic. If the announcement registration ever moves,
keep the timer registered below it.

## Sibling asks (unchanged from the plan)

- **P2 (§5.2)**: `textures/gui/bossbar/fill_anim.png` — 512x128, 4 vertically stacked
  512x32 frames, cycled every 8 ticks. `BossbarSkin` probes the resource live (re-probed
  every ~5 s, so a resource reload picks it up without code changes); until it exists the
  committed fallback (fill + second half-speed scroll pass) renders. Optional SLIM frame
  art was NOT needed — SLIM is pure fills by design (§2.1 "no structural textures").
- **P5 (§5.3)**: dev surface already exists — `/dev timer add|sub|set|pause|resume` goes
  through `RealtimeDayApi`, which broadcasts `S2CDayClockPayload` on every change; the
  client spool animates from consecutive payloads whose boundary changed while the day did
  not (exactly the seam documented in `RealtimeDayService.addMillis`). No new command asked.
- **W5 sidebar**: expanded card can mirror the countdown via `DayTimerCache.remainingMillis()`
  / `warnMillis()` (frozen §7.2 names) — compile-time getters, no wiring needed.

## Behavior notes / edge cases

- **Spool vs. drift**: only boundary (or frozen-window) jumps > 250 ms with unchanged
  day/pause state spool; periodic re-sync payloads (same boundary, fresh `serverNow`) and
  pause/resume transitions never do (remaining time is continuous across those).
- **Zero state**: the sting + blink fire on the first tick the running remaining hits 0,
  guarded per boundary value; the display then HOLDS a DIM `00:00:00` until the server
  flips the day (payload with new day/boundary). The timer triggers nothing else (§3.6).
- **Bossbar increment**: v2 reserved +10 px per bar for the floating name line; v3 draws
  the name inside the fill band, so the vanilla 19 px increment is kept — stacked bars sit
  tighter (§3.5). `AnnouncementOverlay`'s sweep (`drawThemedBar` 8-arg) renders its title
  in-band too, consistent with real bars.
- **Exit ghosts** draw from a `RenderGuiEvent.Post` pass (the removed bar fires no more
  events); guarded against F1, cutscene HUD suppression, `showBossbarSkin=false` and
  `reducedFx`. Bars re-seen after > 1 s replay the entrance (boss re-enters range, F1
  toggle, cutscene end).
- **Minimal strip** (`showBossbarSkin=false`) is byte-identical to v2 — revive countdowns
  never disappear (acceptance line).
- **Perf**: no per-frame allocations in the render paths — digit glyphs come from a
  constant `String[]`, digit/roll state lives in reusable arrays, bar-name strings are
  rebuilt only when the server swaps the name component (~1/s on countdown bars), captions
  cache per `EclipseLang.generation()`, and the `fill_anim` probe is a cached int re-armed
  every 100 ticks.

## Test steps (manual, once integrated into a client run)

1. **Day timer basics**: join a world with the clock armed (`/eclipse-rt arm` or
   `/dev timer set +2h`) → timer appears top-center under the purple countdown bossbar,
   ticking once per second, underline shrinking. `F1` hides both; `showDayTimer=false`
   (settings → Display) hides the timer only.
2. **Spool**: `/dev timer add 30m` → digits spool upward like an odometer over ~1–1.5 s;
   `/dev timer sub 30m` → spool downward. With `reducedFx=true` both snap.
3. **Pause look**: `/dev timer pause` → digits freeze, go DIM, breathe slowly, "Pausiert"
   caption; `/dev timer resume` restores color and ticking without a jump.
4. **Purple ramp + zero**: `/dev timer set +2m` (window prev-boundary dependent — for a
   quick pure-color check `/dev timer sub` down into the last 10%) → digits shift purple,
   strongly `ACCENT_DEEP` near the end; final 10 s pulse once per second; at 00:00:00 the
   line blinks 3x, `ui.timer_zero` plays exactly once, then DIM hold + "Der Tag endet"
   until the server advances the day.
5. **Bossbar v3**: summon the Herald (NOTCHED_6 bar) → drop-in entrance, notch ticks at
   all 5 fractions, hitting the boss flashes the fill white + 2px shake + red trailing
   ghost that drains; healing shows the soft edge glow. Kill/despawn → 6-tick fade-out.
   Toggle `bossbarStyle=SLIM` in settings → frameless rounded strip, same telegraphs.
   `showBossbarSkin=false` → minimal 4px strip (still colored by bar color).
6. **Stacking**: with the day-clock bossbar AND an announcement running, the order top→down
   is: bossbar(s) → day timer → announcement sweep, nothing overlaps.
