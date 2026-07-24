# IDEA-06 — Handbook / Menu Juice (Eclipse Event, wave 4, collector 6/20)

Scope: handbook (`client/handbook/`), skill tree (`client/skills/SkillTreeScreen` + `SkillTreeWidget`),
settings (`client/menu/SettingsPanel`), dev handbook (`devtools/dev/handbook/DevHandbookScreen`).

Ground rules every idea below respects (from the frozen "Quiet Eclipse" system, `P3_ui.md` §2 / §7.2):

- **reducedFx-gate everything** — snap to the final state when `EclipseClientConfig.reducedFx()` is true
  (the existing pattern in `HandbookScreen.panelProgress`, `SkillTreeWidget.renderNode`).
- **B3: hitboxes never move** — animate *drawn pixels only*; widgets stay where `init()` put them.
- **B18: all audio through `UiSounds`** — new cues use the self-healing
  `play(String path, …, fallback, pitchScale)` ledger pattern so they sound today and pick up real
  events later. New helpers are additive (frozen API evolves additively only).
- **fill/text only** — no structural textures; pose translate/scale on content is fine (the tab
  crossfade already does it).

---

## Ranked ideas

### 1. Node-purchase branch light-up cascade (M) — flagship

**What:** buying a skill node currently celebrates only the bought tile (white flash + ring +
edge draw-in). Extend it into a cascade: the confirmation wave travels *onward* — every child edge
of the bought node that just flipped LOCKED→AVAILABLE draws in dim-accent after the node flash, and
the newly-available child tiles "wake up" with a soft accent border flash + a temporary pulse boost,
staggered by graph distance.

**Hooks:**
- `SkillTreeWidget.onNodePurchased(String)` — already the single entry point (called from
  `SkillTreeScreen.tick()`'s server-truth diff). Before recording `purchaseAnimStart`, snapshot
  which nodes are AVAILABLE (`SkillTreeModel.current().stateOf(...)`); after, diff and put the newly
  available ids into a new `Map<String, Long> unlockAnimStart` with start = `Util.getMillis() +
  RING_MILLIS + 80L * depth` (depth from the bought node).
- `SkillTreeWidget.renderEdges(...)` — for a child in `unlockAnimStart`, reuse the existing `drawIn`
  wipe (`LINE_MILLIS`, `easeOutCubic`) with `ACCENT_DEEP` instead of `ACCENT`.
- `SkillTreeWidget.renderNode(...)` — for a tile in `unlockAnimStart`, draw one
  `drawBorderOutset(..., spread 2, withAlpha(ACCENT, 0.6F * (1-t)))` flash over ~250 ms, then let the
  normal affordable `pulse()` take over.
- Sound: one new `UiSounds.skillUnlockWave()` → ledger `"ui.skill_unlock"`, fallback
  `UI_HOVER` at `0.8F` pitch, fired once per cascade (not per node).

**Why first:** the buy is the emotional peak of the skill screen; the cascade literally shows the
player what their point just opened up — juice that doubles as information.

### 2. Settings toggle: knob glide + two-stage themed click (S)

**What:** `ThemedToggle` knobs currently teleport between `pillX + 1` and `pillX + PILL_W - 7`.
Give the knob an ~80 ms eased slide and a knob-landing "settle" tick, so flipping a toggle feels
like a physical switch: press-click on down, settle-tick when the knob docks.

**Hooks:**
- `SettingsPanel.ThemedToggle` — add `private long flipMillis;` set in `flip()`. In
  `renderContent(...)`, compute `t = easeOutCubic(clamp((Util.getMillis() - flipMillis) / 80F, 0, 1))`
  and lerp `knobX` between the off/on positions (flip lerp direction by `value`). Also lerp the knob
  color DIM→ACCENT with `t`. `reducedFx` → `t = 1`.
- Settle tick: in `renderContent`, when `t` crosses 1.0 the first time after a flip, call a new
  `UiSounds.toggleSettle(boolean on)` → ledger `"ui.toggle_settle"`, fallback `UI_TAB` at
  `on ? 1.1F : 0.75F` pitch, volume 0.35 — ON lands brighter than OFF, so you can hear the state
  without looking. Keyboard path (`keyPressed`) gets it for free since it renders the same lerp.
- `ThemedEnumCycle` bonus: same pattern — value text slides 4 px in the cycle direction over 80 ms
  (offset drawn text only) after `cycle(...)`.

### 3. Page-turn paper feel: directional squash + edge-light sweep + pitched whoosh (S/M)

**What:** the handbook tab crossfade (4 ticks, 6 px slide) is clean but flat. Add three cheap layers
of "paper" without any parchment texture: (a) the outgoing content squashes horizontally to ~0.97
toward its exit edge while the incoming un-squashes from 0.97 — a page flexing as it turns; (b) a
1 px vertical `withAlpha(ACCENT, 0.35*(1-t))` "page edge" line sweeps across the content rect in the
switch direction; (c) `UiSounds.pageTurn()` pitch follows direction (forward ≈1.05, backward ≈0.9).

**Hooks:**
- `HandbookScreen.renderTabContent(...)` — already pushes a pose and translates by `dx`; add
  `pose().scale(sx, 1.0F, 1.0F)` around a pivot at the content edge (translate to pivot, scale,
  translate back). `sx = 1 - 0.03F * (1 - |progress delta|)`. Widgets are rendered untransformed by
  the screen (per `HandbookTab.widgets()` contract) so hitboxes are untouched — B3 safe.
- Edge sweep: in `HandbookScreen.renderContent(...)` inside the existing scissor, after both pages:
  `x = contentX + (switchDir > 0 ? eased : 1-eased) * contentW`, `fill(x, contentY, x+1, contentY+contentH, …)`.
- Pitch: `UiSounds.pageTurn()` gains an overload `pageTurn(float pitchScale)`; call sites:
  `switchTab(int, boolean)` (direction known from `switchDir`) and the open rustle in `init()` (keep 1.0).
- All of it inside the existing `switchProgress()`/`reducedFx` gates — reduced mode stays a snap.

### 4. Rail active-bar slide (S)

**What:** the 2 px accent bar marking the active handbook tab currently blinks from one rail button
to another. Make one bar that *travels*: on switch it lerps vertically from the old button's y to
the new one's over the same 4 ticks (easeOutCubic), overshooting 1 px and settling. Reads as a
single physical indicator, the classic sidebar-juice move.

**Hooks:**
- The bar is drawn per-button in `HandbookScreen.RailButton.renderContent(...)`
  (`fill(panelX+1, getY()+1, panelX+3, …)` when `index == activeTab()`). Move that draw up to the
  screen: a `renderRailBar(GuiGraphics, float partialTick)` called from `renderBackground(...)`
  after `drawPanel`, using `switchFrom`/`switchTicks`/`switchProgress(partialTick)` that already
  exist, plus the deterministic rail geometry from `init()` (`railTop + i * (buttonH + gap)` — store
  `railTop/buttonH/gap` as fields). `RailButton` keeps only the icon tint logic.
- Rail presses and 1–8/arrow hotkeys both funnel through `switchTab(int, boolean)`, so one hook
  covers every switch path. `reducedFx` → bar snaps (progress 1).

### 5. Tab icon micro-bounce on press (S)

**What:** rail glyphs respond to a press with a 2-frame downward dip (1 px) and a 1-frame
brightness pop when they become the active tab — a micro-bounce, drawn pixels only.

**Hooks:**
- `HandbookScreen.RailButton` — add `private long pressMillis;` set in `onClick(...)`. In
  `renderContent(...)`: `age = Util.getMillis() - pressMillis`; if `age < 100`, offset `iconY`
  by `+1` px for the first 50 ms, `-1` for the next 50 (dip-and-spring); if the button just became
  active (`index == activeTab()` and `age < 150`), tint the glyph toward `TEXT` before settling on
  `ACCENT`. Letter-fallback path (`drawCenteredString`) gets the same y offset.
- Same micro-pattern is drop-in for `DevHandbookScreen`'s rail (its rail buttons are
  `EclipseWidget`s too) — share via a tiny static helper in `EclipseWidget` (additive), e.g.
  `protected int pressDipY()`.

### 6. Slider tuning-dial pitch ramp + detent flash (S)

**What:** `ThemedSlider` already ticks `UiSounds.slider()` per detent. Map the tick pitch to the
slider fraction (low end ≈0.85, high end ≈1.25) so dragging a slider *sounds* like sweeping a dial —
the ui-volume slider becomes self-demonstrating. Add a 1-frame `TEXT`-colored handle flash per
detent so the ear and eye agree.

**Hooks:**
- `UiSounds.slider()` → additive overload `slider(float pitch)` (keep the old no-arg delegating
  at jittered 1.0 for other callers).
- `SettingsPanel.ThemedSlider.applyQuantized(double)` — the only detent site (mouse, drag and
  keyboard all funnel here): compute `fraction = (quantized - min) / (max - min)` and call
  `UiSounds.slider(0.85F + 0.4F * fraction)`; record `detentMillis = Util.getMillis()`.
- `renderContent(...)` — if `Util.getMillis() - detentMillis < 60`, draw the handle in
  `EclipseUiTheme.TEXT` instead of ACCENT/ACCENT_DEEP.

### 7. Buy button: pending ellipsis walk + success flash (S)

**What:** while a skill purchase is in flight the buy button shows a static "…" label for up to 3 s
(`PENDING_TIMEOUT_TICKS`). Animate the wait — the pending label's dots walk (`.`, `..`, `...` on a
~250 ms cycle) and the border alpha breathes; on server confirmation the button flashes `GOOD` for
150 ms before hiding. Failure (timeout) flashes `DANGER` once so the silent unlock isn't confusing.

**Hooks:**
- `SkillTreeScreen.BuyButton.renderContent(...)` — pending branch: label =
  `buy_pending` text + `".".repeat(1 + (int)(Util.getMillis() / 250 % 3))`; border alpha
  `0.5 + 0.3 * pulse` (reuse `SkillTreeWidget.pulse`-style sine or a local one).
- `SkillTreeScreen.tick()` — both resolution sites already exist: the owned-diff branch
  (`id.equals(pendingNodeId)` → set `resolveMillis`/`resolveGood=true`) and the timeout branch
  (`pendingTicks > PENDING_TIMEOUT_TICKS` → `resolveGood=false`). `updateBuyButton()` passes the
  flash state through.
- No new sounds needed: success already plays `ui.skill_buy` via `canvas.onNodePurchased`.

### 8. Header glance micro-pops: hearts and day flip (S)

**What:** the handbook header's live glance (day counter + hearts row) never acknowledges change.
When `ClientStateCache.lives` drops/rises while the book is open, the changed heart pops (draws 1 px
outset for ~120 ms, i.e. an 11×11 blit for the 9×9 icon — 1:1 art scaled by draw rect, still crisp
at these sizes) with a `DANGER`/`GOOD` under-glow fill; when `ClientStateCache.day` increments, the
day text slides 3 px down-in like a flip counter.

**Hooks:**
- `HandbookScreen` — fields `lastLives`, `lastDay`, `livesChangeMillis`, `dayChangeMillis`,
  `changedHeartIndex`; diff in `tick()` (screen already ticks every client tick).
- `renderHeader(GuiGraphics, int, float)` — apply the pop to blit size/position of
  `changedHeartIndex` and a `fill` under it; offset the `dayText` y by
  `3 * (1 - easeOutCubic(t))` while flipping. All inside existing alpha handling; `reducedFx` snaps.

### 9. Settings rows entrance cascade (S/M)

**What:** when the settings panel first appears (handbook `SettingsTab` shown, or
`EclipseSettingsScreen` opened) the rows cascade in: each visible row fades from 0 and slides 4 px
up, staggered ~12 ms per `relY` step, section headers leading their rows. One-shot per mount, never
on scroll — quiet, fast (<250 ms total), makes the longest menu in the game feel deliberate.

**Hooks:**
- `SettingsPanel` — add `private long mountMillis = Util.getMillis();` and a public
  `restartEntrance()` (called by hosts on show — `SettingsTab.onShown()` and
  `EclipseSettingsScreen.init()`).
- `renderWidget(...)` — per row compute `t = clamp((now - mountMillis - row.relY * 0.7F) / 150F)`;
  skip rendering below `t < 0.05` (mirrors the tab-fade "skip sub-10% frames" rule from
  `HandbookTab`), else pose-translate `4 * (1-easeOutCubic(t))` px down before `row.render(...)`.
  Rows are inside the panel scissor already; hitboxes unaffected because input lands after the
  ~250 ms window in practice, and rows are pose-shifted only visually (input during the window still
  works — offset is ≤4 px, same tolerance the handbook crossfade accepts). Headers use the same `t`
  from their `relY`. `reducedFx` → skip entirely.

### 10. Dev handbook search feel: keystroke ticks + match-count flash (S)

**What:** the ops-only dev handbook filters instantly per keystroke but silently. Add the existing
`UiSounds.typewriter(pitch)` blip (jittered 0.95–1.1, volume already quiet) on each keystroke that
*changes* the query, and flash the bottom-bar match counter in `ACCENT` for 200 ms whenever the
result count changes — typing feels mechanical, and the counter catches the eye exactly when results
move. Zero-result state nudges once with `UiSounds.error()` at low volume (never repeats until the
count leaves zero).

**Hooks:**
- `DevHandbookScreen` — the search `EditBox` responder already rebuilds cards per keystroke
  (`query` field + `DevHandbookSearch`); wrap the "query changed" site with the typewriter blip and
  record `lastMatchCount`/`countChangeMillis` when the filtered card list size changes.
- Bottom bar match-counter draw site: lerp text color `DIM→ACCENT→DIM` over 200 ms from
  `countChangeMillis`; zero-state: one `UiSounds.error()` guarded by a `zeroSounded` flag.
- Reuses two existing `UiSounds` helpers — no new ledger events.

---

## Cross-cutting notes for the integrator

- New `UiSounds` helpers needed: `skillUnlockWave()`, `toggleSettle(boolean)`, `pageTurn(float)`,
  `slider(float)` — all follow the ledger-with-fallback pattern already in `UiSounds.play(String, …)`,
  so they work before the `sounds.json` ledger lands (§2.3 procedural fallback rule).
- Every idea is drawn-pixels/pose-only; no widget positions change (B3), no textures added (§2.1),
  no frozen-API signature changes (§7.2 additive only).
- Wall-clock (`Util.getMillis()`) easing matches the house style (`SkillTreeWidget` celebrations,
  `GlitchText` bucketing) and stays frame-rate independent.
