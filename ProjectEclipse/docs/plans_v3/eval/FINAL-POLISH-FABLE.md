# FINAL-POLISH — Wave-4 Polish Audit (Fable)

Read-only final-wave audit against the Quiet-Eclipse system (`docs/plans_v3/P3_ui.md` §2:
`EclipseUiTheme` tokens, ≤2× type, eased motion, `UiSounds`-only audio) plus overlay
collisions, F1/`reducedFx`/cutscene coverage, wave-4 de_de quality, and the
title→join→limbo→intro first impression. Java root:
`src/main/java/dev/projecteclipse/eclipse/`. Severities: HIGH / MED / LOW.

Audited overlays: `client/hud/BossIntroOverlay`, `client/rewards/RewardMaterializeOverlay`,
`client/contracts/ContractRevealOverlay` (+ `ContractRouletteStrip`,
`ContractClientState`), the Day-Number card inside `client/hud/AnnouncementOverlay`,
`client/wand/WandPathScreen`, `client/wand/WandChargeHud`,
`hearts/client/PurpleHeartsLayer`.

---

## 1. Visual consistency vs. Quiet Eclipse

| Overlay | Palette | Type scale | Motion | Audio | Verdict |
|---|---|---|---|---|---|
| `BossIntroOverlay` | tokens only (`VEIL`/`DANGER`/`TEXT`/`DIM`) | 2.0× name (at cap) | eased-ish; linear fades | `UiSounds` only | clean |
| Day card (`AnnouncementOverlay`) | tokens only | **5.0×** numeral | `easeOutCubic` everywhere | `UiSounds` only | clean except scale (sanctioned, see V-2) |
| `RewardMaterializeOverlay` | tokens only | item 2.6×→1.5×; count decorations ride the item scale | eased | `UiSounds` only | clean-ish |
| `ContractRevealOverlay` | **`RED`/`DEEP_RED` off-palette** | 1.9±0.06 pulse (under cap) | eased/typed | **3 raw vanilla sounds** | worst offender |
| `WandPathScreen` | 1 token dupe + **2 off-palette accents** | 1.0× | none (instant hover lift) | **silent** | gaps |
| `WandChargeHud` | 2 private greys + **3 path accents** (dup of screen) | n/a | static | n/a | acceptable |
| `PurpleHeartsLayer` | sprite-driven; tint triplets | n/a | vanilla-parity | none (by design) | exemplary |

### V-1 (MED) · `ContractRevealOverlay` plays raw vanilla sounds outside `UiSounds`
**File:** `client/contracts/ContractRevealOverlay.java` (`playUi`, `tickHunterReveal`,
`tickTextCeremony`).
`SoundEvents.ANVIL_LAND` + `SoundEvents.BELL_RESONATE` (stamp) and
`SoundEvents.AMETHYST_BLOCK_CHIME` (prank exhale) go straight to
`SimpleSoundInstance.forUI`. This bypasses BOTH the `uiSounds` kill-switch and the
`uiSoundVolume` slider — the exact B18/§2.3 violation the rest of the suite was scrubbed
for (compare: the same file's roulette ticks and typewriter correctly route through
`UiSounds`). These are presentation flourishes, not gameplay-critical warnings (the
`UiSounds` javadoc exemption covers only the heart-shatter crack and mark bell), so a
player who turned UI sounds off still gets anvil-slams. Fix: add
`UiSounds.stamp()`/`UiSounds.chime()` helpers with vanilla-event fallbacks (the existing
self-healing `play(path, …, fallback, pitchScale)` plumbing makes this a 10-line change).

### V-2 (MED) · Off-palette color constants in two contract/wand clusters
**Files:** `client/contracts/ContractRevealOverlay.java` (`RED = 0xFFE03040`,
`DEEP_RED = 0xFFB01020`), `client/wand/WandPathScreen.java` (`ACCENTS` array),
`client/wand/WandChargeHud.java` (`tint()` — same three values duplicated).
- The contract reds are near-DANGER but not `EclipseUiTheme.DANGER` (`0xFFE86078`);
  `BossIntroOverlay` renders its equally "dangerous" moment with the real token. Two
  different "blood reds" now exist in the language.
- The wand trio (violet/ember/star-cyan) is a deliberate per-path identity — fine as
  design — but the violet is a *hardcoded copy* of `ACCENT`, and all three literals are
  duplicated across `WandPathScreen` and `WandChargeHud` with no single owner. Move them
  onto `WandPath` (an `accentArgb()` accessor) or a small `WandTheme` holder so a retune
  can't desync the chooser from the pips.

### V-3 (MED) · `WandPathScreen` skips four house conventions
**File:** `client/wand/WandPathScreen.java`.
1. **Silent interaction** — card hover has no `UiSounds.hover()` edge blip and the
   choose-click sends the payload with no `UiSounds.click()`; §2.3 mandates `UiSounds`
   on every interactive element (B18).
2. **No `CursorManager.endFrame()` per frame / `CursorManager.reset()` in `removed()`**
   — P3 hard rule 5 for all new screens (every other Eclipse screen complies, cf.
   `EclipseTitleScreen.render`/`removed`).
3. **No open/close motion** — §2.3 prescribes a 5-tick fade + 4px rise (`reducedFx`
   snaps); this screen pops instantly and the hover lift itself is an un-eased 3px snap.
4. **Strings bypass `EclipseLang.tr`** — see L-1.
Also mouse-only: cards are not focusable widgets, so keyboard/narration users cannot
choose a path (the handbook rail shows the accessible pattern).

### V-4 (LOW) · Day card renders type at 5× (system cap is 2×)
**File:** `client/hud/AnnouncementOverlay.java` (`CARD_SCALE = 5.0F`).
§2.2 froze "2.0 max for the single hero number"; the W4-CEREMONY wiring doc explicitly
sanctioned 4–6× for this one moment, so this is a *documented* exception — but it is now
the precedent siblings will cite. Either amend §2.2 with the "ceremony numeral" carve-out
or drop the card to ~3× (it reads fine; the odometer roll is what sells it). Same nit,
smaller: `RewardMaterializeOverlay` starts its stack at 2.6× and `renderItemDecorations`
scales the count numeral with it — vanilla item-count digits at 2.6× look soft against
the theme's crisp-fills promise (`EclipseUiTheme` javadoc: icons "are never scaled").

### V-5 (LOW) · Linear lerps and a wall-clock sine wrap in `BossIntroOverlay`
**File:** `client/hud/BossIntroOverlay.java`. The end fade
(`1 - (t-hold)/FADE_TICKS`), the lock flash decay, and the subtitle 1-char/tick reveal
are all linear (§2.3 wants eased motion; every other wave-4 overlay uses
`easeOutCubic`). The hairline "breathe" uses
`sin(System.currentTimeMillis() % 100_000 * 0.0021)` — 100 000 ms is not a whole period
of that frequency, so the breathing visibly jumps phase every 100 s a band happens to be
on screen. Use `Util.getMillis()` unwrapped (floats are fine at this magnitude for days)
or a tick-based phase.

### V-6 (LOW) · Hardcoded theme-token copies in the title screen
**File:** `client/menu/EclipseTitleScreen.java` (`DIM_TEXT_COLOR = 0xFF9A8FB8`, journey
pulse `0xB98CFF`, footer `0xFFD7CEE8`/`0xFFB98CFF`/`0xAA9A8FB8`). All are literal copies
of `EclipseUiTheme.DIM`/`ACCENT` values instead of references (a repo-wide pattern:
`OptionsThemer`, `GoalEditorScreen`, `ArmArtifactItem`, `OreProcFxClient`,
`EclipseMenuButton`, `GhostHeartsLayer` all carry private `ACCENT` copies). A palette
retune would now miss ~9 files.

---

## 2. Screen-space overlay inventory & collisions

Full inventory, anchor, and trigger (registration in `client/EclipseGuiLayers` unless
noted "self"):

| Layer (bottom → top) | Anchor | Trigger |
|---|---|---|
| `MarkVignetteOverlay` (below CROSSHAIR) | screen edges | lantern-gaze mark |
| `LastMinuteHush` (below CROSSHAIR, self) | screen edges | final minute of day |
| `PurpleHeartsLayer` (health slot, self) | hearts row | always (survival) |
| `GhostHeartsLayer` (above PLAYER_HEALTH, self) | hearts row | ghost state |
| `HeartBurstOverlay` (above PLAYER_HEALTH) | hearts row | heart loss |
| `SkillXpBarLayer` (above EXPERIENCE_BAR, self) | XP bar | always |
| `WandChargeHud` (above HOTBAR, self) | bottom-center, `h-51` | wand in hand |
| `SidebarPanel` (above SCOREBOARD_SIDEBAR) | right/left edge, v-centered | always; TAB morphs to center |
| `SkillProcToast` (above BOSS_OVERLAY, self) | bottom-center, `h-59` | skill proc |
| `DayTimerLayer` (below announcements) | top-center under bossbars | timer armed |
| `AnnouncementOverlay` (above BOSS_OVERLAY) | sweep top-center; typewriter `h-80`; **day card center `h/3` at 5×** | queued announcements; day card on STYLE_DAY |
| `WaveOverlay` (aboveAll) | full screen | intro wave |
| `LetterboxLayer` (aboveAll) | top/bottom 12% bars | cutscene flights |
| `CaptionRenderer` (aboveAll) | above bottom bar | cutscene captions |
| `AwardsOverlay` (aboveAll, self) | full-screen veil + center | dawn roulette (T+200) |
| `ContractRevealOverlay` (aboveAll, self) | full-screen veil + center `h/2-10`; window chrome: edge vignette + top-right marker | contract reveal/resolve; window chrome whole window |
| `LevelUpOverlay` (aboveAll, self) | center `h/3` | custom level-up |
| `RewardMaterializeOverlay` (aboveAll, self) | starts center `h/3`, lands `h-58` | reward grant payload |
| `BossIntroOverlay` (**`RenderGuiEvent.Post`**, self — above everything incl. letterbox) | full-width band at `h/4` | boss spawn (Herald/Ferryman/Rift Warden/Fog Tyrant) |

### C-1 (MED) · The `h/3` center anchor is triple-booked with no arbitration
`LevelUpOverlay`, `RewardMaterializeOverlay` (start position) and the day card all
center on `guiHeight/3`. They defer to *cutscenes* but not to *each other*. Concrete
plausible combos:
- **Quest reward with items + skill XP**: `S2CRewardGrantPayload` and the level-up land
  the same tick → the 2.6× stack materializes exactly through the rising "LEVEL 8"
  burst.
- **Dawn**: goals resolve at rollover → reward payloads arrive while the day card holds
  at `h/3` (the card runs on the announcement layer, so the announcement queue can't
  gate it — different subsystems).
A tiny shared "center-stage token" (static `boolean CenterStage.claim()` consulted by
the three tick drivers, queue-deferring exactly like the existing
`CameraDirector.isHudSuppressed()` checks) would serialize them for ~20 lines.

### C-2 (MED) · Bottom-center lane pileup at `h-58/-59`
`SkillProcToast` renders at `h-59`; `RewardMaterializeOverlay`'s touchdown + absorb
flash is at `h-58` (flash ring reaches ±38px); `WandChargeHud` sits at `h-51`;
the announcement typewriter at `h-80`. A vein-clear proc that *completes a mining goal*
fires the proc toast and the reward grant within a tick — stamp and stack land on top
of each other, and the flash whites out the wand pips. Same fix class as C-1 (the toast
already queues; make it also yield while a materialization is inside its
FLOAT/FLASH window), or nudge the toast lane to `h-72`.

### C-3 (MED) · Day rollover + contract window + boss intro is a legal triple
Contract windows run for N minutes and are not closed at rollover
(`ContractService` windows span wall-clock; `DawnCeremony` doesn't touch them), and
Fog-Tyrant/Herald spawns are day-driven. Worst plausible frame (expansion morning,
window open, boss spawns): red edge-vignette pulsing + top-right marker
(`ContractRevealOverlay`), full-width DANGER band at `h/4` (`BossIntroOverlay`),
5× day card at `h/3` (whitelisted announcement layer — renders even letterboxed, see
S-1), plus the dawn toll audio stack. The band bottom (`h/4+~42`) and the card's digit
top (`h/3 - 22` at 5×) **overlap on any window ≤ ~500px tall** — two hero moments
physically intersect. Cheap mitigation: `BossIntroOverlay.handle` already queues — also
hold the queue while the day card is live (`AnnouncementOverlay` exposing a
`dayCardActive()` getter), and vice-versa; the two never *need* to coexist.

### C-4 (LOW) · `registerAboveAll` z-order across self-registrars is classload-ordered
`WaveOverlay`/`LetterboxLayer`/`CaptionRenderer` are appended aboveAll by
`EclipseGuiLayers` in one deterministic call sequence, but `AwardsOverlay`,
`ContractRevealOverlay`, `LevelUpOverlay` and `RewardMaterializeOverlay` each append
from their own `@EventBusSubscriber` — same event, same priority, so their order
relative to the letterbox stack (and each other) depends on FML's scan order, which is
stable per build but *specified nowhere*. Today it doesn't visibly matter (suppression
cancels the non-whitelisted ones during flights); it will the day one of them is
whitelisted. Worth one ledger comment or moving the four aboveAll registrations into
the hub.

### C-5 (LOW) · Contract mini-marker vs. `windowMinutesShown` truncation
`ContractRevealOverlay.handleReveal` computes `windowTicks / (20*60)` with integer
division — a 90-second dev window reads "You have 1 minutes" (also the en plural is
hardcoded; de "Du hast %s Minuten" is fine). Round up (`(ticks + 1199) / 1200`) and use
a plural-aware key.

---

## 3. F1 / reducedFx / cutscene-suppression coverage

| Layer | F1 (`hideGui`) | `reducedFx` | Cutscene suppression |
|---|---|---|---|
| `BossIntroOverlay` | ✅ render-gated | ✅ calm static + no breathe (decode roll still runs — documented) | **immune by design** (`RenderGuiEvent.Post`; doc'd "plays under the letterbox") |
| Day card | ✅ | ✅ static card | **❌ renders during cutscenes** — see S-1 |
| `RewardMaterializeOverlay` | ✅ (state advances) | ✅ calm fade-in | ✅ defers start; mid-flight continues hidden (doc'd) |
| `ContractRevealOverlay` | ✅ | ✅ spin+kick skipped (title pulse + window vignette not gated — LOW) | **❌ hidden but ticks + sounds** — see S-2 |
| `WandPathScreen` | n/a (Screen) | n/a (no motion) | n/a |
| `WandChargeHud` | ✅ | n/a | ✅ (not whitelisted) |
| `PurpleHeartsLayer` | ✅ (Pre-hook leaves slot alone) | ✅ jitter suppressed | ✅ `receiveCanceled=true` clears `owningFrame` — exemplary |
| (context) `AwardsOverlay` | ✅ | ✅ | ✅ holds behind letterbox (`barPx > 0`) |
| (context) `LevelUpOverlay` | ✅ | ✅ | ✅ defers start |
| (context) `DayTimerLayer`, `SidebarPanel`, `SkillProcToast`, `SkillXpBarLayer`, `MarkVignetteOverlay`, `LastMinuteHush` | ✅ | ✅ | ✅ (not whitelisted) |

### S-1 (MED) · The 5× day card rides the announcement layer's cutscene whitelist
**Files:** `client/EclipseGuiLayers.java` (whitelist), `client/hud/AnnouncementOverlay.java`.
`AnnouncementOverlay.LAYER_ID` is letterbox-whitelisted (the P2 §1.7 fix: cutscene
subtitles are delivered as announcements). The W4-CEREMONY day card was then built INTO
that layer — so on an expansion morning (camera flight at rollover, `hideHud` path
live), the ceremony's T+40 STYLE_DAY announcement paints a 5× numeral card over the
cinematic frame. Compounding it, the class javadoc still claims "deliberately NOT
letterbox-whitelisted" — stale since the whitelist landed. Fix: in
`beginDayCard`/`tickDayCard`, defer the card while `CameraDirector.isHudSuppressed()`
(keep the plain sweep/typewriter path, which IS the subtitle mechanism), and correct
the javadoc.

### S-2 (MED) · Contract ceremonies play to a suppressed screen
**File:** `client/contracts/ContractRevealOverlay.java` (`onClientTick`).
The overlay is not whitelisted, so its *render* is cancelled during cutscene HUD
suppression — but the state machine has no `CameraDirector.isHudSuppressed()` check
(contrast `RewardMaterializeOverlay`/`LevelUpOverlay`): a hunter reveal arriving
mid-flight ticks through VEIL→SPIN→STAMP→TEXT invisibly, complete with roulette ticks,
anvil stamp and typewriter audio, and is gone when the letterbox lifts. The player
misses their own contract ceremony. Fix: don't `startCeremony` while suppressed — hold
the pending `Show` and start when the flight ends (window chrome can keep rendering).

### S-3 (LOW) · Audio leaks under F1 across the queue-driven overlays
`BossIntroOverlay`, `ContractRevealOverlay`, `RewardMaterializeOverlay` and the day
card all keep *ticking* under F1 (correct — hidden HUD shouldn't stall queues), but the
tick drivers also fire their stings/typewriter blips, so an F1 screenshot session gets
disembodied UI audio. One shared guard (`if (!minecraft.options.hideGui)` around the
sound calls only) would align them; note the same behavior pre-exists in
`TypewriterLine`, so this is a consistency call, not a wave-4 regression.

---

## 4. de_de quality — 30-key sample across the wave-4 langdrops

Sampled 37 keys across `W4-CEREMONY` (7/7), `W4-BOSSJUICE` (4/4), `W4-HEARTS` (2/2),
`W4-ISLAND` (2/2), `W4-ATMOS` (6/6), `W4-FEEL` (13 spot-checked), and random draws from
`W4-WAND` (65), `W4-CONTRACTS` (47), `W4-MINIGAMES` (71), `W4-TOGGLES` (38),
`W4-WIZARD` (27), `W4-BESTIARY` (47). Machine-verified: **every wave-4 drop has full
en/de parity and all keys are merged into the shipped
`assets/eclipse/lang/{en_us,de_de}.json` (1749/1749 keys, zero one-sided).**

**Verdict: genuinely good German** — idiomatic, register-consistent, not
machine-literal. Highlights: "DAS BLATT HAT SICH GEWENDET" (tables-turned),
"Das Kopfgeld wechselt die Taschen", the Rift-Warden weakness prose ("tritt ein oder
bleib daheim"), Orin's dialogue, correct gendered pronouns per boss ("Die Finsternis
spricht durch **ihn**" for der Herold, "**Er** bewacht…" for der Wächter). Grammar,
compounding (Artefakt-Logbuch, Sternschauer, Seelenbindungs-Umwandlung) and du-form are
consistent throughout.

Nits (all LOW):
- `gui.eclipse.contract.oath`: EN "This is your **mark**" → DE "Das ist dein **Ziel**"
  — loses the branded-target flavor; "Das ist dein Gezeichneter" or "deine Beute" would
  carry it.
- `dev.eclipse.wand.mode.item`: DE drops the subject ("Fortschrittsmodus" vs "Wand
  progression mode") — harmless in dev-command context.
- `eclipse.caption.dawn.goals`: "Der Tag hat Ziele." is slightly flat next to the EN
  decree line; "Der Tag stellt Forderungen." would match the register.

### L-1 (MED) · `wand.eclipse.*` is invisible to the `/lang` override
**Files:** `client/lang/EclipseLang.java` (`KEY_PREFIXES`),
`client/wand/WandPathScreen.java`, `wand/WandPath` lang keys.
The resolver's prefix table has no `wand.eclipse.` entry, so even code that *did* call
`EclipseLang.tr` would fall through to the global language for every wand string — and
`WandPathScreen` doesn't call it anyway (raw `Component.translatable` throughout, the
only wave-4 screen to skip the house API). A German player on an en_us client using
`/lang de` gets a German handbook, German contracts, German day card… and an English
path-choice ceremony (one of the few irreversible choices in the event). Two-line fix:
add the prefix + switch the screen to `EclipseLang.tr`. (Same gap: `movement.eclipse.*`,
`dialogue.eclipse.*`, `eclipse.caption.*`, `eclipse.minigame.*`, `dev.eclipse.*` — the
latter two arrive server-localized via `LangService`, so only client-rendered prefixes
matter.)

---

## 5. First impression — title→join→limbo→intro (fresh-eyes read)

The flow is in strong shape; the engineering is defensive where it counts:
- **Title** (`EclipseTitleScreen`): journey matrix re-fingerprints per tick (hot config
  edits rebuild live), panorama has a per-face existence check + runtime fallback,
  cursor lifecycle correct, `reducedFx` swaps the glitch theater for a disabled button
  + countdown tooltip. `GlitchErrorTheater` routes audio through `UiSounds.error()`.
- **Join**: `JourneyController.tryConnect` never throws (R-2 honored; bad host →
  themed error panel). `EclipseLoadingScreen` wraps the vanilla screen as a hidden
  ticking delegate with a wall-clock failsafe *checked in render too* (SP load loop
  doesn't tick screens — nice catch), killswitch config intact.
- **Limbo/intro**: `IntroSequence` persists its phase (`IntroData`) and skips to the end
  state after a mid-intro restart; APPROACH stalls re-whisper every 60 s; the logbook
  handoff caption uses `Component.keybind` so rebinds show truthfully.

Rough edges found:
- **F-1 (LOW)** `WandPathScreen` is the first bespoke SCREEN a player meets in the
  first hour (first wand right-click) and it's the least polished surface in the wave
  (V-3: silent, snap-motion, mouse-only, override-blind). It teaches the player the
  wrong quality bar right after the intro's high.
- **F-2 (LOW)** Day-card shrink flight always flies toward top-RIGHT
  (`guiWidth - 40`, `0.22h`) — with `sidebarSide=LEFT` the card flies away from the
  day row it's supposed to land on. Read `EclipseClientConfig.sidebarSide()`.
- **F-3 (LOW)** First-morning pile: `DawnCeremony` T+40 line + day card + goals caption
  at T+140 + (non-expansion) roulette at T+200 are well spaced — but a first-day
  contract draw or boss intro is not fenced against the ceremony (C-3). Consider a
  server-side quiet window ± 15 s around `DawnCeremony.begin`.
- **F-4 (LOW)** `AnnouncementOverlay` javadoc contradiction (S-1) will mislead the next
  worker reading the file during onboarding — cheap doc fix, disproportionate value.

---

## Consolidated defects

| # | Sev | File | Summary |
|---|---|---|---|
| V-1 | MED | `ContractRevealOverlay` | anvil/bell/chime bypass `UiSounds` gate + volume |
| S-1 | MED | `AnnouncementOverlay` + `EclipseGuiLayers` | 5× day card renders during cutscenes via subtitle whitelist; stale javadoc |
| S-2 | MED | `ContractRevealOverlay` | ceremonies tick + sound while render is cutscene-suppressed (player misses the reveal) |
| L-1 | MED | `EclipseLang`, `WandPathScreen` | `wand.eclipse.*` invisible to `/lang`; screen bypasses `EclipseLang.tr` |
| C-1 | MED | `LevelUpOverlay`/`RewardMaterializeOverlay`/day card | `h/3` center anchor triple-booked, no mutual deferral |
| C-2 | MED | `SkillProcToast`/`RewardMaterializeOverlay` | `h-59` vs `h-58` bottom-center collision (proc + reward same tick) |
| C-3 | MED | `BossIntroOverlay`/day card/contract chrome | boss band (`h/4`) and day card (`h/3`) physically overlap ≤ ~500px windows; no cross-hold |
| V-2 | MED | `ContractRevealOverlay`, `WandPathScreen`, `WandChargeHud` | off-palette reds; wand accent trio duplicated, violet shadows `ACCENT` |
| V-3 | MED | `WandPathScreen` | no `UiSounds`, no `CursorManager`, no open motion, mouse-only |
| C-5 | LOW | `ContractRevealOverlay` | window-minutes integer truncation + hardcoded plural |
| V-4 | LOW | `AnnouncementOverlay`, `RewardMaterializeOverlay` | 5× / 2.6× type-scale exceptions vs. §2.2's 2× cap |
| V-5 | LOW | `BossIntroOverlay` | linear fades; 100 s sine phase jump in hairline breathe |
| V-6 | LOW | `EclipseTitleScreen` (+8 files) | hardcoded copies of theme tokens |
| S-3 | LOW | queue overlays | UI stings audible under F1 |
| C-4 | LOW | 4 self-registrars | aboveAll z-order is classload-order-defined |
| F-2 | LOW | `AnnouncementOverlay` | day-card flight ignores `sidebarSide=LEFT` |

## Top 5 polish actions

1. **Route the three contract vanilla sounds through `UiSounds`** (V-1) — the only
   place in wave 4 where the audio-consistency law is broken; 10 lines, zero risk.
2. **Defer ceremonies under cutscene suppression**: hold the day card while
   `CameraDirector.isHudSuppressed()` and hold `ContractRevealOverlay.startCeremony`
   the same way (S-1 + S-2) — fixes both the "5× card over the letterbox" and the
   "missed your own contract reveal" failure with the already-proven
   `RewardMaterializeOverlay` pattern; correct the stale javadoc while there.
3. **Add a shared center-stage arbiter** for `LevelUpOverlay`,
   `RewardMaterializeOverlay`, the day card and `BossIntroOverlay` (C-1/C-2/C-3): one
   static claim/release consulted at each queue-start, so simultaneous hero moments
   serialize instead of stacking.
4. **Bring `WandPathScreen` up to house standard** (V-3 + L-1): `UiSounds`
   hover/click, `CursorManager` lifecycle, 5-tick fade-in, `EclipseLang.tr` +
   `wand.eclipse.` prefix in `KEY_PREFIXES`, keyboard focusable cards — it's the first
   bespoke screen new players meet.
5. **Centralize the stray colors** (V-2/V-6): contract reds → `DANGER`-derived
   constants beside the theme, wand accents → `WandPath`, and sweep the nine hardcoded
   `ACCENT`/`DIM` copies onto `EclipseUiTheme` references so the palette stays
   retunable.
