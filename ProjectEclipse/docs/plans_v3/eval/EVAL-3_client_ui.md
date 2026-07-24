# EVAL-3 — Client UI/HUD Audit (Fable)

Read-only audit of `client/hud`, `client/death`, `client/skills`, `client/awards`,
`client/invlock`, `client/loading`, `client/handbook/tabs`, `client/menu`,
`devtools/dev/handbook`, `client/emi`, `music`, and the P6 entity renderers.
Java root: `src/main/java/dev/projecteclipse/eclipse/`. Severities: HIGH / MED / LOW.

---

## Critical (HIGH)

### H-1 · Monotonic/epoch clock mixing freezes the expanded-sidebar timers
**Files:** `client/hud/SidebarExpanded.java` (`estimatedServerNow`, `remainingMillis`),
`client/hud/SidebarPanel.java` (`render`, passes `Util.getMillis()`),
`network/EclipsePayloads.java` (day-clock handler, stores `System.currentTimeMillis()`).

`SidebarPanel.render` passes `now = Util.getMillis()` (monotonic millis since JVM
start, a few million) down into `SidebarExpanded`. There,
`estimatedServerNow(localNowMillis)` computes
`serverNowEpochMillis + Math.max(0L, localNowMillis - ClientStateCache.clockSyncLocalMillis)`
— but `clockSyncLocalMillis` was recorded as `System.currentTimeMillis()` (epoch,
~1.7e12). The subtraction is always hugely negative, the `Math.max(0L, …)` clamp
pins the elapsed term to **0**, and `estimatedServerNow` degenerates to "the server
time as of the last payload".

**Effect:** the TAB-morph sidebar's day-boundary countdown and every buff
"remaining" line freeze between payloads and jump forward in `clientSyncSeconds`
(default 5 s) steps instead of ticking down each second. The same stale value feeds
`SidebarPanel`'s collapsed timer row through `remainingMillis`. The clamp also
hides the bug from casual testing — nothing is visibly *wrong*, just stuttery.

**Reference for the correct pattern in the same codebase:**
`devtools/dev/handbook/DevHandbookScreen.timerText()` computes
`System.currentTimeMillis() - clockSyncLocalMillis` (epoch minus epoch) and ticks
smoothly. Fix is to use one time base on both sides (either pass
`System.currentTimeMillis()` into `estimatedServerNow`, or record the sync stamp
with `Util.getMillis()`).

---

## Medium (MED)

### M-1 · i18n split-brain: direct `Component.translatable("gui.eclipse.*")` bypasses the `/lang` override
**Files:** `client/menu/CreditsScreen.java` (title, subtitle, load_error, section
titles), `client/menu/PauseMenuHook.java`, `client/menu/VanillaTitleGear.java`,
`client/menu/EclipseSettingsScreen.java` (title only — its subtitle correctly uses
`EclipseLang.tr`), `client/menu/EclipseTitleScreen.java` (gear/credits buttons,
tagline, disclaimer), `client/menu/OptionsThemer.java`,
`client/handbook/HandbookScreen.java` (title, day artifact, footer),
`client/handbook/tabs/HandbookTab.java` (**all tab labels**),
`client/skills/SkillTreeWidget.java` (screen title).

`EclipseLang.tr` only delegates to `Component.translatable` when the effective
override matches the vanilla game language (`usesVanillaPath()`); otherwise it
resolves from internal EN/DE tables. Every direct `Component.translatable` call on a
`gui.eclipse.*` key therefore renders in the **vanilla** language, not the `/lang`
override — e.g. `/lang de_de` on an English client yields a German settings panel
under an English title, English handbook tab names, an all-English credits screen,
and an English "Eclipse…" pause button. Mechanical fix: sweep these ~9 files to
`EclipseLang.tr` (the lang tables already contain every key — see cross-cutting (c)).

### M-2 · Boss music dies under F1 / cutscene letterbox
**File:** `music/MusicManager.java` (`onBossbar`, `naturalCue`).

Herald/Ferryman detection piggybacks on
`CustomizeGuiOverlayEvent.BossEventProgress`, which only fires while the boss-bar
GUI layer actually renders. With F1 (hide GUI) the vanilla layer stack is skipped,
and during cutscenes `LetterboxLayer` cancels the non-whitelisted `BOSS_OVERLAY`
layer — either way the event stream stops, `bossSeenMillis` goes stale, and after
the 1 s grace (`BOSS_SEEN_GRACE_MILLIS`) the boss track crossfades out mid-fight.
Cinematic boss-intro cutscenes are exactly when this triggers. (The
`receiveCanceled = true` subscription correctly survives `BossbarSkin`'s
cancellation — it is the *layer-level* suppression that kills it.) Detection should
key off actual boss-event state (e.g. the `BossHealthOverlay` events map or a tick
scan), not a render-path event.

### M-3 · InvLock click-cancellation is incomplete: drags and the drop key leak through
**File:** `client/invlock/InvLockOverlay.java`.

`ScreenEvent.MouseButtonPressed.Pre` over locked slots is cancelled, but:
- **Quick-craft drags** (`ScreenEvent.MouseDragged.Pre`) are not — dragging a stack
  across locked slots paints them into the vanilla quick-craft set and sends the
  server clicks for locked slots (server rejects; client shows a flicker/ghost
  split until resync).
- **The drop key (Q)** over a locked slot is not cancelled
  (`ScreenEvent.KeyPressed`), so hovering a locked slot and pressing Q drops the
  item the lock overlay claims is untouchable.

### M-4 · AwardsOverlay can replay a day's show after queue overflow
**File:** `client/awards/AwardsOverlay.java` (`pollPayload`).

A payload arriving while the queue is at capacity is dropped **without** recording
its day in `HANDLED_DAYS`. If the server re-sends (relog, re-sync) after the queue
drains, the same day's roulette plays again. Mark the day handled (or evict oldest)
instead of silently dropping.

### M-5 · AwardsOverlay ESC-skip hijacks the pause menu
**File:** `client/awards/AwardsOverlay.java` (`ScreenEvent.Opening` handler).

ESC during a show cancels the vanilla `PauseScreen` opening and jumps the show to
the summary. A player who genuinely wants the pause menu (disconnect, options)
loses both: the roulette is skipped **and** no menu appears; the show also advances
while the game is "paused" from the player's perspective. Consider letting the
pause screen open on the second press, or only consuming ESC when no screen swap
is pending.

### M-6 · LevelUpOverlay multi-level queue drops celebrations non-obviously
**File:** `client/skills/LevelUpOverlay.java`.

At `QUEUE_LIMIT`, `QUEUE.pollLast()` evicts the most recently queued level to make
room for the newer one — a 1→20 jump celebrates 2…9 and then 20, silently skipping
10–19 with no coalescing (e.g. a single "LEVEL 20" with a "+11" tag). Cosmetic but
reads as a bug to the player who just macro-levelled.

### M-7 · SidebarExpanded allocates every frame even while collapsed
**File:** `client/hud/SidebarExpanded.java` (`preferredHeight`, `render`).

`SidebarPanel.render` calls `preferredHeight` (and while morphing, `render`) every
frame; these build formatted strings, an `ArrayList` of goals, a `HashSet` of buff
ids and `font.split` results per frame in a HUD hot path. Cache by
(`ClientStateCache` payload generation, `EclipseLang.generation()`, width) — data
only changes on payload arrival.

### M-8 · DayTimerLayer ≥48 h display is ambiguous and jumps at the format switch
**File:** `client/hud/DayTimerLayer.java` (`computeDigits`).

Above 48 h the readout switches from `HH:MM:SS` to `DD:HH:MM` with no unit cue —
"02:05:33" reads as either 2 h 5 m 33 s or 2 d 5 h 33 m. At the boundary the
display jumps 48:00:00 → 02:00:00 → (a second later) 47:59:59. A `d`/`h` glyph or
a separator change (`2d 05:33`) would disambiguate.

---

## Low (LOW)

### client/hud
- **`SidebarPanel.java`** — `rowsHash` folds in `nowMillis / 1000` so `buildRows`
  re-allocates every string once per second even when nothing changed; `slideHash()`
  builds a stream + varargs array per frame; both are avoidable HUD-path churn.
- **`SidebarPanel.java`** — `LAST_GOAL_DONE` map never evicts stale goal ids
  (unbounded across a long session, bounded in practice by goal count).
- **`SidebarPanel.java`** — marquee scissor rect derives from lerped float positions
  (rounding can clip 1px at fractional GUI scales); `setColor` is deprecated in
  1.21.1 (works, but flagged for the next mapping bump).
- **`BossbarSkin.java`** — the live-bar path checks `hideGui` but not
  `CameraDirector.isHudSuppressed()`; currently mitigated because `LetterboxLayer`
  cancels the whole `BOSS_OVERLAY` layer first, but the guard is asymmetric with
  the exit-ghost path (defence-in-depth gap if the whitelist ever changes).
- **`DayTimerLayer.java`** — the `Math.min(99, hours)` cap in `computeDigits` is
  dead code (that branch only runs below 48 h).

### client/death
- **`DeathFlowController.java`** — the `ScreenEvent.Opening` suppression checks
  `instanceof ReceivingLevelScreen`, which `EclipseLoadingScreen` extends; with
  theater off this can cancel the custom loading screen `LoadingScreenSwap` just
  installed (blank-screen race, low likelihood).
- **`DeathFlowController.java`** — `PHASE_STALE_MILLIS` (30 s) uses wall time
  without an `isPaused` guard; a long singleplayer pause mid-flow can clear the
  phase and cause a visual discontinuity on unpause.
- **`EclipseDeathScreen.java`** — `init()` re-adds widgets on resize without
  clearing (one-frame active-state flicker); `exitToTitle` disconnects with no
  confirmation (vanilla asks); a re-opened death screen resets the hold-to-respawn
  timer.
- **`GhostHeartsLayer.java`** — `LEFT_HEIGHT_COMPENSATION` assumes a single-row
  heart stack; with datapack-extended max hearts the armor row can sit 1 row off
  while ghosted.

### client/skills
- **`SkillTreeScreen.java`** — window resize re-runs `init()` without resetting
  `viewInitialized`, silently discarding the player's pan/zoom; `knownOwned` diffing
  cannot detect node *revocation* (not currently a supported server op).
- **`SkillTreeWidget.java`** — click on empty canvas starts a drag even with zero
  nodes; `mouseScrolled` claims the event even when zoom is already clamped.
- **`SkillXpBarLayer.java`** — fixed offset above the vanilla XP bar collides with
  the mount-health/absorption row variants; renders even when the vanilla bar is
  hidden (creative/spectator edge).
- **`SkillProcToast.java`** — two proc payloads inside one client tick collapse
  into a single toast (payload cadence makes this rare).

### client/awards
- **`RouletteStrip.java`** — tie rendering: co-winner heads can overlap
  fading-out loser heads when their strip offsets are close (2-frame visual
  artifact). Landing math itself is exact — verified the deceleration integral
  terminates precisely on the winner index.

### client/invlock
- **`InvLockOverlay.java`** — edge-hint tooltip x is not clamped ≥ 0 on very
  narrow windows; slot-rect math itself is GUI-space and guiScale-safe (verified
  against scale 2/3 arithmetic).

### client/loading
- **`PortalTransitionController.java`** — solid (failsafes are wall-clock-driven and
  `advance()` is idempotent); only exposure is the `DeathFlowController`
  `ReceivingLevelScreen` race noted above.

### client/handbook
- **`HandbookScreen.java`** — the StatusTab settings link jumps to a hardcoded tab
  index (8); reordering tabs silently breaks it.
- **`tabs/RevivalTab.java`** — `drawStack` news up `ItemStack`s per frame (screen
  render, tolerable; cache per recipe resolve); the hearts strip can clip past
  `width - SCROLLBAR_INSET` if a datapack sets an extreme heart price. Recipe read
  via `RecipeManager` is correct for 1.21.1 (synced client-side).
- **`tabs/BestiaryTab.java`** — 7 creature cards vs 11 shipped P6 mobs; players
  will notice the missing four (content gap, not a code bug).
- **`tabs/TabScrollbar.java`** — clean; drag/wheel/clamp logic verified.

### client/menu
- **`SettingsPanel.java`** — closing the screen mid-slider-drag (ESC) skips
  `onRelease`, so the live `set()` is never `save()`d: the setting *applies* but
  silently reverts on next config load from disk. Also: an unrecognized
  `langOverride` token renders as "Auto" while behaving differently.
  Otherwise the B13 write path is correct (typed handles, `SPEC.isLoaded()` guards,
  save-on-release).
- **`PauseMenuHook.java` / `VanillaTitleGear.java`** — the dedupe guard only
  recognizes `TranslatableContents`; an Eclipse widget labelled via
  `EclipseLang.tr` under an active override is a literal component and slips past
  (merge-window double-entry risk only). PauseMenuHook's fallback row clamps to the
  screen bottom and can overlap the lowest grid row on very short windows.
- **`CreditsScreen.java`** — `font.split` per detail line per frame; `scroll` is
  not re-clamped in `init()` after a window grow (blank content until first wheel
  input). Plus the M-1 language bypass.
- **`EclipseSettingsScreen.java` / `TitleScreenSwap.java` / `OptionsThemer.java`**
  — correct: guard-on-open semantics, exact-class swap checks, cursor reset in
  `removed()`.

### devtools/dev/handbook
- **`DevHandbookScreen.java`** — a refresh payload while typing sets
  `pendingRebuild` → `rebuildWidgets()` recreates the search `EditBox`: value is
  preserved but focus and caret position are lost mid-keystroke. Everything else is
  notably solid: modal confirm swallows input correctly, manual hit-rects are
  scoped to the scissored list, the header timer uses epoch-epoch math (the correct
  version of H-1), and `/`-hotkey handles the German-layout `Shift+7` char path.

### client/emi
- **`EclipseEmiPlugin.java`** — exemplary isolation: only compile-time EMI file,
  throw-proof predicates, cosmetic-only hiding. No findings.
- **`EmiReindexer.java`** — the 5 s debounce *drops* the second unlock diff with no
  trailing retry; two unlock commands ~4 s apart leave the EMI index stale until
  the next diff. A deferred re-request (instead of a silent return) would close it.

### music
- **`MusicManager.java`** — besides M-2: a third cue arriving while a crossfade is
  in flight `forceStop()`s the outgoing sound (hard cut instead of fade); vanilla
  suppression via per-tick `stopPlaying()` is otherwise airtight, and logout
  cleanup resets all statics.

### entity renderers (P6 mobs)
- **No findings.** `glitch/GlitchedGeoRenderer.java`: the deterministic burst
  schedule provably keeps ≥ 12 t between alt-frame bursts (offset ∈ [6,30], len ≤ 4,
  window 40 t) — above the ≥ 8 t plan bar; hash math is sign-safe (`>>>` before `%`);
  zero per-frame allocation (pre-built `ResourceLocation`s). All `_alt.png` +
  `_alt_glowmask.png` + `_glowmask.png` textures ship for all three glitched mobs
  and the 8 other new mobs. `pale/PaleSentinelRenderer.java`: freeze visual is
  server-authoritative (yaw/pitch re-assert), renderer correctly just enables head
  tracking. Emissive layers all go through the frozen `EclipseGeoRenderer`
  `withGlowmask()` path; `DriftLantern` correctly pairs glowmask with
  `withTranslucency()` for its alpha glass.

---

## Cross-cutting check results

- **(a) F1 + cutscene suppression:** F1 is handled globally (vanilla gates the GUI
  layer stack on `hideGui`; overlays with own paths re-check it). Cutscene
  suppression flows through the single `LetterboxLayer` whitelist in
  `client/EclipseGuiLayers.java` (letterbox, heart burst, wave, announcement,
  captions) — verified every other Eclipse layer is correctly cancelled.
  **Exceptions:** MusicManager's boss detection breaks under both (M-2);
  BossbarSkin's asymmetric guard (LOW).
- **(b) Per-frame allocations:** worst offender is `SidebarExpanded` (M-7); then
  `SidebarPanel` string/hash churn, `CreditsScreen`/`RevivalTab` per-frame splits
  and `ItemStack`s (screen-render paths, LOW). `DayTimerLayer`, `MarqueeText`,
  `BossbarSkin`, glitch renderers are allocation-clean in their hot paths.
- **(c) en/de key usage:** `en_us.json` and `de_de.json` are in perfect parity
  (1401 = 1401 keys, zero one-sided keys). All 290 statically referenced UI keys
  resolve (the two grep "misses" are dynamic suffixes `rules.lineN` /
  `revival.stepN.*`, all present). No hardcoded English/German literals found in
  `Component.literal` UI strings. The real i18n defect is the *routing* split M-1.
- **(d) guiScale safety:** verified clamping in DevHandbookScreen (~480×270 floor),
  SettingsPanel/EclipseSettingsScreen/CreditsScreen min sizes, InvLock GUI-space
  slot rects, handbook panel clamps. Remaining nits: SidebarPanel float-scissor
  rounding and InvLock edge-hint clamping (both LOW).

---

## Top 3 Quick Wins

1. **Fix H-1 with a one-line time-base swap** — pass `System.currentTimeMillis()`
   into `SidebarExpanded.estimatedServerNow` (or store `clockSyncLocalMillis` as
   `Util.getMillis()` and subtract consistently, as `DevHandbookScreen.timerText`
   already does). Instantly turns the sidebar countdown and buff timers from 5 s
   stutter-steps into smooth per-second ticking.
2. **Sweep `Component.translatable("gui.eclipse.*")` → `EclipseLang.tr` (M-1)** —
   ~15 call sites across 9 files, purely mechanical, no new lang keys needed
   (tables are already complete). Kills every mixed-language screen under `/lang`.
3. **Cancel `MouseDragged.Pre` and the Q/drop key over locked slots in
   `InvLockOverlay` (M-3)** — two small additions to the existing event subscriber
   using the already-written `isInSlotHitbox`/lock lookup; completes the lock
   illusion and stops erroneous quick-craft packets.
