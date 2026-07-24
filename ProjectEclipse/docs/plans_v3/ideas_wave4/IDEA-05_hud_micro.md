# IDEA-05 — HUD Micro-Interactions (10 ideas, ranked best-first)

Collector: 5/20, Eclipse Event ideas wave 4. Scope: **micro-interactions only** in the existing
HUD surfaces — sidebar (`client/hud/SidebarPanel` + `SidebarExpanded`), day timer
(`client/hud/DayTimerLayer` + `DayTimerCache`), bossbar (`client/hud/BossbarSkin`), skill XP
strip (`client/skills/SkillXpBarLayer`), hearts (`client/death/GhostHeartsLayer`,
`hearts/client/HeartBurstOverlay`, the sidebar hearts row). No new packets, no server changes —
everything below animates state the client already caches (`ClientStateCache`, payload-fed).

House conventions every idea must follow (all already established in these files):

- **`reducedFx` snaps/skips** every animation (`EclipseClientConfig.reducedFx()`), like the
  sidebar slide, timer spool and bossbar entrance already do.
- **Allocation-free render hot paths** — pre-built glyphs/arrays, wall-clock `Util.getMillis()`
  arithmetic (`DayTimerLayer` header documents the pattern).
- **Client-session hygiene**: new animation statics reset in the owning class's
  `ClientPlayerNetworkEvent.LoggingOut` / level-null handler (`SidebarPanel.onLoggingOut`,
  `SkillXpBarLayer.onClientTick` precedents).
- **Palette**: `EclipseUiTheme` only (`GOOD 0xFF9AF0B0`, `ACCENT 0xFFB98CFF`,
  `ACCENT_DEEP`, `DANGER 0xFFE86078`, `DIM`, `TEXT`, `HAIRLINE`).
- **Do not duplicate** existing juice: `LastMinuteHush` owns the last-60s *audio* heartbeat +
  HUD dim; `HeartBurstOverlay` owns the per-heart shatter; `GhostHeartsLayer` owns the revive
  burst; the collapsed goal checkbox already has a 6-tick L→R fill sweep
  (`SidebarPanel.drawGoalBox` / `TICK_SWEEP_MILLIS`).

---

## 1. Goal-complete "stamp" on the collapsed sidebar row *(S)*

The moment a daily goal flips done, the collapsed row today only gets the quiet 6-tick checkbox
fill. Upgrade it into a satisfying stamp, still Quiet-Eclipse calm: (a) the checkbox flashes
white for 2 ticks then settles `GOOD`; (b) a 1px `GOOD` ring expands 0→6px from the box center
and fades (three `fill()` hairlines, no textures); (c) the row text crossfades `TEXT → GOOD`
over the sweep instead of snapping (it currently swaps color the frame `goalDone()` flips —
`renderCollapsed`'s ternary); (d) one soft `UiSounds.click()`-family cue, pitch-salted by
`row.phaseSalt()` so back-to-back completions arpeggiate.

- Hooks: `SidebarPanel.drawGoalBox` (stamp visuals), `SidebarPanel.renderCollapsed` (text
  crossfade), `SidebarPanel.updateGoalSweeps` (already detects the done-flip edge per row id via
  `LAST_GOAL_DONE` / `GOAL_SWEEP_STARTED` — reuse the same stamp timestamp; extend the map TTL
  from `TICK_SWEEP_MILLIS` to ~600 ms for the ring/crossfade tail). Sound from the same edge,
  NOT from render.
- Guards: `reducedFx` keeps only the instant color swap; no sound while `minecraft.screen != null`
  is unnecessary — `UiSounds` is already volume/config gated.

## 2. Checkmark draw-on in the TAB expanded card *(S)*

`SidebarExpanded.render` pops a static `"\u2713"` glyph the frame a goal completes. Replace the
glyph with a two-stroke vector check drawn from `fill()` rectangles (short stroke down-right,
long stroke up-right) whose lengths lerp on over ~8 ticks with `easeOutCubic`, and let the
goal's progress bar (`drawBar`) sweep `ACCENT → GOOD` left-to-right over the same window instead
of recoloring instantly. Because the card only renders while TAB is held, key the animation off
the shared stamp timestamp from idea #1 (`GOAL_SWEEP_STARTED`): if the player is holding TAB
when the payload lands they see the draw-on live; if they open TAB within the TTL they catch
the tail — both feel intentional.

- Hooks: `SidebarExpanded.render` goal loop (marker + bar), reading
  `SidebarPanel.GOAL_SWEEP_STARTED` via a small package-private accessor (both classes are in
  `client/hud`); stroke geometry is 6 fills max per goal, allocation-free.
- Guards: `reducedFx` → static glyph as today. Scissor already active — strokes clip safely
  during the open/close morph.

## 3. XP strip overflow shimmer + multi-level sweep carry *(M)*

`SkillXpBarLayer` level-ups play a 5-tick full-white sweep, then re-fill from 0. Two upgrades:
(a) **shimmer** — during the sweep, instead of a flat white bar, run a 14px specular band
left-to-right across the 182px strip (3 stacked `fill()`s at descending alpha centered on
`sweepProgress * BAR_WIDTH`), so the bar visibly "spends" the overflow; (b) **carry** — on a
multi-level gain (`level > lastLevel + 1`, e.g. `/dev` grants or quest XP dumps), queue one
sweep per level gained (cap 3) before easing to the final fraction, each sweep re-pitching
`UiSounds.levelUp()` up a semitone-ish step (1.0/1.06/1.12). The level numeral increments once
per sweep, not once total — the odometer moment is the dopamine.

- Hooks: `SkillXpBarLayer.onClientTick` level-up branch (replace `sweepTicks` int with a
  `pendingSweeps` counter + the existing `sweepTicks` countdown; numeral shown =
  `ClientStateCache.skillLevel - pendingSweeps`), `SkillXpBarLayer.render` sweep branch (band
  drawing; `partial`-interpolated `sweepProgress`).
- Guards: `reducedFx` keeps today's snap (`pendingSweeps = 0`). Bar stays 2px — the shimmer is
  alpha-only, no height change, so hearts/food rows overlapping stay legible.

## 4. Day-timer "lub-dub" visual heartbeat in the final 10 s *(S)*

The final-10s digit pulse is currently a single `easeOutCubic((remaining % 1000) / 1000)` swell
per second — metronomic, not organic. Replace the envelope with a two-beat waveform (primary
beat at phase 0, softer echo beat at phase ~0.28, amplitudes 0.12/0.06, each a fast-attack
`easeOutCubic` decay), and couple the underline: it thickens 1px→2px and brightens toward
`ACCENT_DEEP` on each beat. The digits already sit in fixed monospace cells so the scale pulse
never causes wobble. Explicitly **no audio here** — `LastMinuteHush` already owns the
accelerating warden heartbeat over the same window; this is its visual counterpart, and the two
being phase-independent is fine (hush is ambience, this is the clock's own pulse).

- Hooks: `DayTimerLayer.render` pulse computation (the `pulse` local + `PULSE_AMPLITUDE`
  constant → small `beatEnvelope(phase)` helper), underline fill just below (thickness/color
  keyed to the same envelope value).
- Guards: existing gates already skip the pulse while paused/zero-hold/spooling and under
  `reducedFx` — keep them verbatim.

## 5. Sidebar hearts-row damage shake + last-heart breathing *(S)*

The sidebar `hearts` row is the only always-visible lives readout, and it changes silently.
(a) On a lives **decrease**, the row (icon + text) does a 4-tick ±1px horizontal shake (two
incommensurate sines, the `BossbarSkin` damage-shake recipe) and the count flashes `DANGER`;
(b) while `ClientStateCache.lives == 1`, the heart icon breathes — alpha 0.75↔1.0 sine, 2s
period, tinted toward `DANGER` — the own-player mirror of `LastHeartEmber`'s "protect the
ember" read; (c) on lives **increase** (revive, altar boon) a brief `GOOD` flash, no shake.

- Hooks: `SidebarPanel` — new `LAST_LIVES` static compared in `updateGoalSweeps`' caller (or a
  tiny `updateHeartsAnim(now)` beside it; `rowsHash` already includes `lives` so rows rebuild on
  change); `renderCollapsed` applies the x-offset/tint only for `row.id().equals("hearts")`.
  Reset in `onLoggingOut`.
- Guards: `reducedFx` drops shake and breathing (color flash may stay — it is a state readout).
  No sound: `HeartBurstOverlay.trigger` already plays the shatter crack at the same moment.

## 6. Counter bump when mains/optional tick up *(S)*

The `mains 2/5` and `optional` aggregate rows increment with zero fanfare, yet they are the
event's actual scoreboard. When `sidebarMainsDone` (or sides/personals done) increments, give
that row a "bump": the text lifts 2px and settles with `easeOutCubic` over 6 ticks while the
changed row flashes `GOOD → TEXT`. Pure position/color theater, one row at a time — the panel
itself must not move (deliberately excluded from `slideHash`, see the B11 comment).

- Hooks: `SidebarPanel` — statics `LAST_MAINS_DONE` / `LAST_SIDES_DONE` / `LAST_PERSONALS_DONE`
  updated where `updateGoalSweeps` runs; `renderCollapsed` adds the per-row y-offset for row ids
  `mains` / `optional`. Reset in `onLoggingOut`.
- Guards: `reducedFx` → color flash only. Skip the bump when the counter *decreases*
  (admin edits) — mirror `SkillXpBarLayer`'s "snap, no theater" rule for downward changes.

## 7. Bossbar phase-notch crossing pop *(S)*

`BossbarSkin` draws NOTCHED_6/10/12/20 ticks as static dark hairlines. When the (lerped) fill
edge crosses a notch **downward** — a boss phase threshold actually passed — pop that notch:
it flashes white, widens 1px→3px, and emits a one-frame 6px glow blip (reuse the existing
`GLOW` texture blit), fading over ~200 ms. Turns the notches from decoration into telegraphs —
players learn "the flash means a phase line just broke" without any new server data, since the
overlay/notch fractions are already vanilla-synced.

- Hooks: `BossbarSkin.BarState` — add `int lastNotchIndex = -1; long notchFlashStartMillis;
  int flashNotch;`; detect the crossing in `onBossEventProgress` (compare
  `floor(displayedProgress * notches)` against `lastNotchIndex`); render the pop inside
  `drawBar`'s notch loop (both ORNATE and SLIM paths share it).
- Guards: `reducedFx` skips (constant exists: gate beside `damageFlash`). Rising crossings
  (heals, countdown re-arms) stay silent — only drops telegraph.

## 8. XP "+n" gain chip *(S)*

Every XP gain currently lights the pulse+spark but never says *how much*. On a `totalXp` delta,
float a small `+n` numeral that rises 6px and fades over ~16 ticks, anchored just above the
level numeral right of the strip (that column is already reserved and clear of the food row).
Coalesce: gains landing while a chip is alive add into it and refresh its life (mining sprees
read as one growing `+34`, not confetti). String is rebuilt only when the value changes —
allocation discipline holds.

- Hooks: `SkillXpBarLayer.onClientTick` (delta already computed for `pulseTicks`; add
  `chipValue`/`chipTicks` statics, reset in the level-null branch), `SkillXpBarLayer.render`
  (draw after the numeral, `EclipseUiTheme.withAlpha(ACCENT, fade)`).
- Guards: `reducedFx` drops the chip entirely. Suppress the chip during a level-up sweep
  (idea #3) — the sweep is the bigger moment; fold the remainder into the next chip.

## 9. TAB-expansion content cascade *(S)*

`SidebarExpanded.render` fades all card content in as one block (`expandedAlpha`). Stagger it:
each section (title → vitals → goals header → goal rows → optional → buffs → you → stage) gets
`alpha * smoothstep(sectionIndex * 0.06, sectionIndex * 0.06 + 0.5, expansion)` plus a 2px rise,
so the card visibly *constructs* top-down over the existing 8-tick morph — the classic
"expensive settings panel" feel for free. The section index is already implicit in render order;
thread a counter through the existing `section(...)` helper and the goal loop.

- Hooks: `SidebarExpanded.render` (wrap each `drawString`/`drawBar` group's alpha; the
  smoothstep helper already exists in `SidebarPanel` — move it to `SidebarExpanded` or
  duplicate 6 lines), no state, purely a function of `expansion` — nothing to reset.
- Guards: `reducedFx` already snaps `progress` to 0/1 in `SidebarExpanded.update`, which makes
  every smoothstep saturate — the cascade disables itself with zero extra code.

## 10. Buff low-time blink in the expanded card *(S)*

Buff rows in the TAB card show a countdown that just runs out. In the final 10 s, blink the
row's remaining-time text `DIM ↔ ACCENT` at 1 Hz (wall-clock square wave, same idiom as the
timer zero-blink), and when a buff expires while the card is open, fade the row out over 6
ticks instead of popping (keyed on the buff id lingering in a small `EXPIRING` map for 300 ms).
Teaches players to re-up altar buffs before they lapse, using data the card already renders
(`buff.endsAtEpochMillis()` vs `estimatedServerNow()`).

- Hooks: `SidebarExpanded.render` buffs loop (blink is stateless: `remaining < 10_000 &&
  (now / 500) % 2 == 0`); the expiry fade needs a `Map<String, Long> EXPIRING` static — clear
  it from `SidebarExpanded.reset()` (already called by `SidebarPanel.onLoggingOut`).
- Guards: `reducedFx` → steady `DANGER`-tinted text under 10 s, no blink, instant removal.

---

### Cross-cutting notes

- Ideas 1+2 share one edge-detection source (`GOAL_SWEEP_STARTED`) — implement together.
- Ideas 3+8 both touch `SkillXpBarLayer` tick state — land as one PR to avoid rebase pain.
- Nothing here adds a GUI layer, a texture, or a payload; worst case is ~10 static fields and
  ~200 lines across 4 files. All ideas are individually shippable and individually revertible.
