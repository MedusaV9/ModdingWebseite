# PLAN-A — Client/UI Playtest Fixes (Wave 5)

> PLANNER-A output. Root-cause analysis + worker packages for the 19 client/UI issues
> reported in the latest playtest. Packages are **A1..A16**, each with an exclusive
> file-ownership list so parallel workers never collide. Where two packages must touch
> the same file, the file is owned by exactly ONE package and the other package declares
> a **DEPENDS-ON** and hands its edit spec to the owner (noted inline).
>
> Effort scale: **S** (≤2 files, mechanical), **M** (3–6 files, some design), **L** (7+ files
> or new subsystem/design work).

---

## 0. Cross-package contracts (read first)

Three new shared facilities are introduced by these packages. Owners are fixed here so
workers don't re-invent them:

1. **`ClientStateCache.eventStarted` flag** — owned by **A8**. Server truth =
   `StartState.isAssigned() || EclipseWorldState.isStartEventDone()`, synced inside the
   existing `S2CSidebarStatePayload` (add one boolean field). A8 lands the field +
   payload change; A12 (artifact gating) and A9 (XP bar) only *read* it via
   `ClientStateCache.eventStarted`.
2. **`EclipseLang.serverTr(...)` / `ServerLang`** — owned by **A1**. Server-side text that
   must respect the per-player `/lang` override resolves through `LangService` before
   send. A15 (announcements) and A1's xbox sweep call into it.
3. **`BossbarSkin.reserveOverlayRow()` stack** — already exists; **A7** owns all changes
   to the reservation/stacking logic. A10 (bossbar style) touches only draw code inside
   `BossbarSkin` sections marked below; A7 and A10 therefore share the file — to avoid
   collision, **A10 is DEPENDS-ON A7 and must branch from A7's result** (serialized, not
   parallel). Every other package pair is fully parallel.

---

## A1 — i18n core: fix the dead locale merge + prefix coverage + server-side resolver

**Covers items:** 1 (loading screen language), 17 (i18n sweep: cutscenes, bestiary,
death screen, xbox leave, decree announcements).

**Root cause (the big one).** `EclipseLang.mergeLocale`
(`src/main/java/dev/projecteclipse/eclipse/client/lang/EclipseLang.java` L195–199) filters
resource stacks with:

```java
resourceManager.listResourceStacks("lang",
    location -> location.getPath().endsWith("/" + localeFile)   // "…/en_us"
             || location.getPath().equals(localeFile));          // "en_us"
```

Actual resource paths are `lang/en_us.json` — they end with `.json`, so **neither predicate
ever matches**. `EN_US`/`DE_DE` stay empty, and `lookupTemplate` (L226–237) falls through to
`Component.translatable(key).getString()` = vanilla language = English unless the *game*
language is German. The whole `/lang de` override is a no-op for every `EclipseLang.tr`
surface, which is exactly why the loading screen (which *does* call `EclipseLang.tr` for
title and tips — `EclipseLoadingScreen` is not the bug) stays English.

**Secondary root causes for item 17:**
- `KEY_PREFIXES` (EclipseLang L41–59) is missing `eclipse.caption.` (cutscene/dawn
  captions), `eclipse.xbox.` (xbox leave command feedback), and `eclipse.minigame.` —
  keys with those prefixes are filtered out of the merged tables even after the merge fix.
- `CaptionRenderer` (`cutscene/client/CaptionRenderer.java`) resolves caption keys via
  `Component.translatable(...).getString()` directly, bypassing `EclipseLang` entirely.
- Server-baked strings: `XboxEventService` builds `Component.translatable` on the server;
  it serializes as a translatable and resolves client-side with the *vanilla* language,
  ignoring the mod override. Death screen / "New Decree" captions sent from
  `DawnCeremony` have the same problem.

**Exact fix:**
1. `mergeLocale`: predicate → `location.getPath().equals("lang/" + localeFile + ".json")`
   (and drop the dead second clause). Add a `LOGGER.debug` with merged key counts so a
   regression is visible in logs.
2. Add `"eclipse.caption."`, `"eclipse.xbox."`, `"eclipse.minigame."` to `KEY_PREFIXES`.
   Audit `assets/eclipse/lang/*.json` for any other prefix families not in the list
   (one-time sweep; record findings in the PR description).
3. `CaptionRenderer`: replace direct `Component.translatable(...).getString()` calls with
   `EclipseLang.tr(...)` (same signature, honors override + fallback chain).
4. New `ServerLang.tr(ServerPlayer, key, args)` thin wrapper over the existing
   `LangService` locale resolution; convert `XboxEventService` command feedback and any
   `sendSystemMessage(Component.translatable(...))` server sends found by
   `rg "sendSystemMessage\(Component.translatable" src/main/java` to it.
5. Verify bestiary + death screen keys exist in `de_de.json`; add missing German lines.

**Files owned:** `client/lang/EclipseLang.java`, `lang/LangService.java` (+ new
`lang/ServerLang.java`), `cutscene/client/CaptionRenderer.java` *(i18n lines only — A15
owns its queue logic; coordinate: A1 lands first, it's a 3-line change)*,
`xboxevent/XboxEventService.java`, `assets/eclipse/lang/en_us.json`,
`assets/eclipse/lang/de_de.json`.

**Effort:** M. **Blocks:** nothing, but A15 should rebase on it.

---

## A2 — Loading screen: smooth fade-out on every dismissal

**Covers item:** 2.

**Root cause.** `PortalTransitionController` already fades portal-driven transitions, but a
plain world join dismisses `EclipseLoadingScreen` the frame the level is ready — the
screen is popped with no exit animation (hard cut). There is no fade path for the
non-portal case.

**Exact fix.** Add a `dismissing` state to `EclipseLoadingScreen`: when the game signals
completion, don't pop immediately; start a ~400 ms alpha ramp (ease-out cubic) rendering
the last frame over the now-live world, then pop. Reuse the easing/timing constants from
`PortalTransitionController` (extract to a small shared `FadeCurve` helper if cleaner).
Guarantee: pop is unconditional after the timer even if render is starved (no soft-lock).

**Files owned:** `client/loading/EclipseLoadingScreen.java`,
`client/loading/PortalTransitionController.java` (only if extracting the shared curve).

**Effort:** S.

---

## A3 — Main menu: remove settings entry points + panorama/logo rework

**Covers items:** 3, 16.

**Root causes.**
- Item 3: settings reachable from three pre-game surfaces: gear button in
  `EclipseTitleScreen` (custom title), `VanillaTitleGear` (injects gear onto vanilla title
  when `customMenu` is off), and `PauseMenuHook` (pause menu button).
- Item 16: the six `assets/eclipse/textures/gui/title/panorama_*.png` faces are
  byte-identical (visible seams / "weird fog" = the fog overlay fighting a flat cube), and
  `logo.png` has a binary alpha channel — opaque rectangle behind the mark.

**Exact fix:**
1. Delete the gear/settings button from `EclipseTitleScreen.init()`; delete
   `VanillaTitleGear` registration (class can stay, unregistered, or be removed).
2. **Pause menu recommendation: KEEP a minimal entry.** Rationale: item 13 removes the
   artifact pre-event, so with title-screen settings gone, a player who disabled
   something (e.g. sidebar) pre-event would otherwise have *zero* path back to settings.
   Keep `PauseMenuHook`'s single small button; it is "ingame" and matches the user's "nur
   ingame" wording. If the user insists later, deletion is one revert.
3. Panorama: replace the six identical faces with a procedurally-rendered eclipse sky
   (static star field + eclipse disc on the front face, darker side/back faces, subtle
   gradient top/bottom) — render once into textures offline (script or generated PNGs),
   NOT runtime shader work. Tone the fog overlay down (alpha ≤ 0.25) or remove it.
4. Logo: re-export `logo.png` with true 8-bit alpha (feathered edges); verify
   `EclipseTitleScreen` blits with blend enabled.

**Files owned:** `client/menu/EclipseTitleScreen.java`, `client/menu/VanillaTitleGear.java`,
`client/menu/PauseMenuHook.java`, `assets/eclipse/textures/gui/title/*` (all six panorama
faces + `logo.png`).

**Effort:** M (art regeneration is the bulk).

---

## A4 — Timeline tab: fix "AY 1" clipping + general polish

**Covers items:** 4, 5.

**Root cause.** `TimelineTab` (`client/handbook/tabs/TimelineTab.java`): the first node
center is `x + 30` (L252 `nodeCenterX`). Captions are drawn centered on the node
(L212–217) after `clampCaption(...)` wraps to width `NODE_SPACING + 24`. A caption line
wider than 60 px extends left of `x + 30 - width/2 < x`, and the scissor set at L101
(`enableScissor(x, …)`) clips the overhang — "DAY 1 — FIRST LIGHT" wraps such that the
first character(s) fall left of `x` → renders as "AY 1 …".

**Exact fix:**
1. Left inset: first node at `x + LEFT_PAD` where `LEFT_PAD = 30 + font.width(widestCaptionHalf)`
   is too fiddly — simpler robust fix: clamp each caption line's draw X so
   `centerX - lineWidth/2 >= x + 4` and `centerX + lineWidth/2 <= x + width - 4` (shift,
   don't clip), OR increase the scissor to start at the panel edge and add `scrollX`
   min-clamp so node 0 can be scrolled fully into view. Implement the clamp — it fixes
   every node, not just the first.
2. Polish pass ("alles etwas mehr anpassen"): consistent 9-px caption line height,
   raise the hint band contrast, ease the node pulse, align the milestone divider label
   (L168–170) baseline with captions, and widen `NODE_SPACING` by ~8 px so two-line
   captions never touch.

**Files owned:** `client/handbook/tabs/TimelineTab.java`.

**Effort:** S/M.

---

## A5 — Altar rewards tab: hide future levels + "Altar Offering" naming

**Covers item:** 6.

**Root cause.** `RewardsTab` renders every entry of `ClientStateCache.milestones`;
`S2CMilestonesPayload.current()` ships **all** milestones (including future levels) to the
client. Both display and data are spoilery.

**Exact fix:**
1. Server: in the payload builder, trim to milestones with `level <= currentLevel + 1`
   (current + the immediate next as a teaser, fully-detailed only for `<= current`; the
   `+1` entry sends title only, no reward list — flag boolean `revealed`).
2. Client `RewardsTab`: render revealed entries normally; the single unrevealed next
   level renders as a "???" row; nothing beyond it.
3. Naming: retitle the tab + headers to the "Altar Offering" family —
   `gui.eclipse.handbook.rewards.title` → new strings `"Altar Offerings"` /
   `"Altar-Opfergaben"`; per-level heading "Offering Level N". Keys stay, values change
   (both lang files) — coordinate with A1 (A1 owns the lang JSONs; hand the string list
   to A1's worker or land after A1 — these are distinct JSON lines, merge-trivial).
4. **DEPENDS-ON:** none hard; lang value lines go through A1's files (trivial).

**Files owned:** `client/handbook/tabs/RewardsTab.java`,
`network/payload/S2CMilestonesPayload.java` + its server-side sender (in
`progression/`), `client/progression/ClientStateCache.java` *(milestone fields only —
the `eventStarted` field belongs to A8; different regions, but declare both so the two
workers put their fields in separate blocks)*.

**Effort:** M.

---

## A6 — Map tab rework: explored-rings fog-of-war, sketch style

**Covers item:** 7.

**Root cause.** `MapTab` draws the full world disc with **all** stage rings and landmark
markers regardless of progression — spoils total world size and future stages.

**Exact fix (design):**
1. Only render rings for stages `<= currentStage`; the next ring renders as a faint
   dashed "static/glitch" arc (GlitchText-style noise), nothing beyond.
2. Landmarks appear only once their chunk has been entered by the player (client keeps a
   visited-landmark id set synced via the existing unlock payloads — reuse
   `ClientUnlockCache` key mechanism: server adds `landmark:<id>` unlock keys on
   proximity; no new payload type).
3. Restyle: parchment/sketch look — hairline ink rings, cross-hatch fill for unexplored
   interior, hand-drawn-style compass rose; palette from `EclipseUiTheme`.
4. Remove numeric radii/coordinates from tooltips pre-exploration.

**Files owned:** `client/handbook/tabs/MapTab.java`, server proximity hook (new small
class in `progression/`, e.g. `LandmarkDiscoveryService.java`).

**Effort:** L (visual rework + discovery sync).

---

## A7 — ONE day timer above the hotbar; strip bossbar + top-center duplicates

**Covers item:** 8 (also enables 10, 12's slim sidebar).

**Root cause.** Four surfaces show day/buff countdowns simultaneously:
1. `DayTimerLayer` — top-center, stacked under bossbars via `BossbarSkin.nextFreeBarY()`
   (L173).
2. `RealtimeDayService` — server creates a `ServerBossEvent` for the day clock →
   rendered as a bossbar.
3. `TimedBuffService` — a second `ServerBossEvent` for buff timers → another bossbar.
4. `SidebarPanel` (collapsed) — repeats day + countdown text.

**Exact fix:**
1. `RealtimeDayService`: delete the `ServerBossEvent` creation/update path entirely
   (keep the tick clock + payloads; only the bossbar presentation goes).
2. `TimedBuffService`: same — remove its `ServerBossEvent`; buff state already reaches
   the client (sidebar data payload); buff timers render ONLY in the TAB-expanded
   sidebar (A8 renders them; this package just stops the bossbar).
3. `DayTimerLayer`: reposition from top-center to bottom-center **above the hotbar**:
   `topY = guiHeight - 50 - barHeight` (above hotbar + offhand slot, below the A9 XP
   bar slot — fixed coordinates agreed with A9: day timer baseline at `guiHeight - 47`,
   XP bar occupies vanilla slot `guiHeight - 32..-29`). Remove its
   `BossbarSkin.reserveOverlayRow` registration (no longer in the top stack) and drop
   the `nextFreeBarY()` call.
4. `EclipseGuiLayers`: re-register the layer above the hotbar layer, keep announcement
   sweep reservation logic working now that the day timer no longer reserves a row.
5. `SidebarPanel` (collapsed): **hand-off spec to A8** (A8 owns the sidebar files):
   remove countdown + "N active buffs" rows; keep "Day N" only.

**Files owned:** `client/hud/DayTimerLayer.java`,
`progression/realtime/RealtimeDayService.java`, `buffs/TimedBuffService.java`,
`client/EclipseGuiLayers.java`, `client/hud/BossbarSkin.java` *(reservation/stacking
region only — A10 branches from A7 for the style pass)*.

**Effort:** M. **Blocks:** A10 (serialize after A7).

---

## A8 — Sidebar rework: setting, TAB-only mode, sections, singular, pre-event gate

**Covers items:** 12 (all four sub-points), plus owns the shared `eventStarted` flag
(contract §0.1) and executes A7's collapsed-panel hand-off.

**Root causes.**
- No user setting exists for "sidebar off except TAB-hold" — `SidebarPanel.isActive()`
  has no such mode.
- `SidebarExpanded` renders one flat goal list; global missions vs sidequests are not
  visually separated (goal `kind` exists in the data, unused for grouping).
- `"1 Hearts"`: row text built with a hardcoded plural (no singular branch).
- Sidebar renders pre-event because `isActive()` never consults an event-started flag —
  and no such flag is synced to the client at all.

**Exact fix:**
1. Add `eventStarted` boolean to `S2CSidebarStatePayload` + `ClientStateCache`; server
   sets it from `StartState.isAssigned() || EclipseWorldState.isStartEventDone()`; send
   on join + on start-event completion. (Contract §0.1 — A9/A12 read it.)
2. New Eclipse setting `sidebarMode`: `FULL` (current), `TAB_ONLY` (nothing unless TAB
   held), `OFF` — surfaced in the artifact `SettingsTab`; `SidebarPanel.isActive()`
   respects it, and returns false whenever `!ClientStateCache.eventStarted`.
3. `SidebarExpanded`: group goals by kind into two labeled sections — header rows
   `gui.eclipse.sidebar.section.global` ("Global Missions"/"Globale Missionen") and
   `...section.side` ("Sidequests"/"Nebenaufgaben"); widen panel 220 → 280 px; buff
   timers (from A7's removal of the buff bossbar) render here as `icon + name + m:ss`.
4. Plural fix: `count == 1 ? tr("...heart.one") : tr("...hearts.many", count)` — with
   naming per A14/A13 contract: "Leben"/"Life"/"Lives" strings, keys
   `gui.eclipse.lives.one` / `gui.eclipse.lives.many`.
5. Execute A7's hand-off: collapsed panel drops countdown + buff-count rows.

**Files owned:** `client/hud/SidebarPanel.java`, `client/hud/SidebarExpanded.java`,
`network/payload/S2CSidebarStatePayload.java` + its sender, `client/progression/ClientStateCache.java`
*(eventStarted field block — see A5 note)*, `client/settings/` (setting registration +
`SettingsTab` row), `start/StartState.java` *(read-only accessor if missing)*.

**Effort:** L.

---

## A9 — Custom level bar replaces the vanilla XP bar (same slot)

**Covers item:** 9.

**Root cause.** `SkillXpBarLayer` registers **above** `VanillaGuiLayers.EXPERIENCE_BAR`
instead of replacing it → both bars render, mod bar in a non-standard slot.

**Exact fix:**
1. Cancel/hide vanilla `EXPERIENCE_BAR` + `EXPERIENCE_LEVEL` layers when skill sync is
   active (NeoForge: `RenderGuiLayerEvent.Pre` cancel for those two ids).
2. Render the skill bar in the vanilla slot (`guiHeight - 32`, width 182, centered),
   skill level number centered above it in the vanilla level position, mod styling
   (theme colors, odometer level ticks) retained.
3. Riding/jump-meter: when `player.jumpableVehicle() != null`, don't cancel — vanilla
   jump meter shows as normal.
4. Pre-event (`!ClientStateCache.eventStarted` — read-only, from A8): don't cancel
   vanilla, don't render the mod bar.

**Files owned:** `client/skills/SkillXpBarLayer.java` (+ its registration lines *inside
its own class*; the `EclipseGuiLayers` line change is handed to A7's worker, who owns
that file — one-line spec: "register SkillXpBarLayer replacing, not above").

**Effort:** S/M. **DEPENDS-ON:** A8 (flag), A7 (`EclipseGuiLayers` line).

---

## A10 — Bossbar skin style pass

**Covers item:** 10.

**Root cause.** `BossbarSkin` custom draw uses aggressive pulse/shake/sweep effects that
read as "not fitting" against the toned-down HUD; after A7 removes the day/buff bars,
the remaining real boss bars still animate with the old style.

**Exact fix.** Tone down: remove the constant idle pulse (pulse only on damage events),
reduce shake amplitude ≥50%, replace the hard color sweep with a subtle 1-px highlight
scan, and match bar frame corners/hairline to `EclipseUiTheme` panel style. Keep the
fill-lerp (that part reads well).

**Files owned:** `client/hud/BossbarSkin.java` *(draw/style regions — branch from A7's
merged result; A7 owns stacking logic)*.

**Effort:** S. **DEPENDS-ON:** A7 (serialize).

---

## A11 — Inventory lock slots: remove unlock-day hint

**Covers item:** 11.

**Root cause.** `InvLockOverlay` hover tooltip renders the `sealed_until` message
including the unlock day (`unlockDay` param baked into the translatable args).

**Exact fix.** Swap tooltip to the day-less variant: new key
`gui.eclipse.invlock.sealed` = "Sealed by the Eclipse" / "Von der Finsternis
versiegelt" (no args). Delete the `unlockDay` arg plumbing in the overlay (server can
keep sending it; client just stops displaying). Lang lines via A1's files (two lines,
merge-trivial).

**Files owned:** `client/invlock/InvLockOverlay.java`.

**Effort:** S.

---

## A12 — Artifact granted only after event start

**Covers item:** 13.

**Root cause.** `ArtifactSlotLock.enforce()` grants + pins the arm artifact
unconditionally on player tick — players get it pre-event.

**Exact fix.**
1. Server: in `enforce()`, early-return unless `StartState.isAssigned() ||
   EclipseWorldState.isStartEventDone()` (server-side truth, no payload needed). On the
   start-event completion hook, run one immediate `enforce()` pass so everyone gets the
   artifact at the ceremony moment.
2. Client: `ArtifactScreenOpener` (keybind/slot-click path) no-ops with a small toast
   ("The artifact has not chosen you yet") when `!ClientStateCache.eventStarted` (flag
   from A8) — prevents a keybind opening a handbook the player shouldn't have.

**Files owned:** `artifact/ArtifactSlotLock.java`, `artifact/` client opener class,
start-event completion hook site (`start/` — the specific method that flips
`isStartEventDone`, call-site addition only).

**Effort:** S/M. **DEPENDS-ON:** A8 (client flag only; server part is independent).

---

## A13 — Rebirth system (server): umbral splinters → +1 life, resets, escalating cost

**Covers item:** 14 (rebirth server half) + 15 (server lives model).

**Root cause / gap.** No rebirth mechanic exists. `HeartsService` (`MAX_HEARTS`, lives
tracking) has no API for "reset + grant permanent bonus life"; skill/level state has no
bulk-reset; no umbral-splinter currency sink.

**Exact fix (new subsystem, `progression/rebirth/RebirthService.java`):**
1. `rebirth(ServerPlayer)`: validate splinter cost → consume → `HeartsService.addPermanentLife(+1)`
   → reset skill nodes + skill XP + level to 0 → increment `rebirthCount` (persisted in
   the player's progression tag).
2. Cost curve: `cost(n) = BASE * GROWTH^n` (config `rebirth.json`: `baseCost: 8`,
   `growth: 1.6`); per-rebirth level-cost multiplier `levelCostMult(n) = 1 + 0.25 * n`
   applied in the skill XP requirement formula (single hook in the level-curve method).
3. New C2S payload `C2SRebirthPayload` (client button → server validate/execute) and the
   response ride on existing skill/hearts sync payloads.
4. `HeartsService`: add `addPermanentLife`, and ensure `MAX_HEARTS` cap accounts for
   rebirth bonus lives.

**Files owned:** new `progression/rebirth/` package, `hearts/HeartsService.java`,
`network/payload/C2SRebirthPayload.java` + registration, `run/config/eclipse/rebirth.json`
(new), the skill level-curve method (in `skills/` server class — named at
implementation time; declare in PR).

**Effort:** L. **Blocks:** A14's rebirth UI (client renders what this syncs).

---

## A14 — Skill tree client rework: bigger canvas, more nodes, dbl-click buy, rebirth UI, wand tab

**Covers item:** 14 (client half).

**Root causes.**
- `skilltree.json` ships only 25 nodes; `SkillTreeWidget` canvas bounds hug them → tree
  feels tiny.
- Buying = select node, click footer button (two-step, sluggish).
- No rebirth UI at all (server half = A13).
- `WandPathScreen.open()` is only triggered once by a pathless wand — wand progression
  is unfindable afterwards.

**Exact fix:**
1. Content: extend `skilltree.json` to ~60 nodes — add incremental filler nodes (+2%
   melee, +1 heart-piece progression, gathering/movement small nodes) between existing
   keystones; widen canvas world-bounds + default zoom-out in `SkillTreeWidget`.
2. Double-click buy: in `SkillTreeWidget.mouseClicked`, detect second click on the same
   node within 350 ms → send existing `C2SSkillNodeBuyPayload` directly (keep footer
   button as fallback).
3. Rebirth UI: new footer section in `SkillTreeScreen` — shows splinter cost (from A13
   sync), rebirth count, confirm dialog ("resets skills & levels, +1 Leben"); sends
   `C2SRebirthPayload`.
4. Wand tab: add a **wand progression tab** to the skill tree screen (tab strip: "Skills"
   | "Wand") that embeds the wand path/upgrade view; `WandPathScreen` stays for
   first-choice, but its content becomes reachable any time via the tab (extract its
   render core into a reusable widget).

**Files owned:** `client/skills/SkillTreeScreen.java`, `client/skills/SkillTreeWidget.java`,
`client/wand/WandPathScreen.java` (+ extracted widget class), `data/eclipse/skilltree.json`
(or `run/config` equivalent).

**Effort:** L. **DEPENDS-ON:** A13 (payload + sync fields).

---

## A15 — Announcement/caption arbitration: "New Decree" dedupe + no blocking

**Covers item:** 18 (+ finishes item 17's caption surface, jointly with A1).

**Root causes.**
- `DawnCeremony.goalsReveal` fires the "New Decree" caption (`eclipse.caption.dawn.goals`)
  **unconditionally every day** whenever goals exist — even if goals are unchanged.
- Two independent text systems draw in the same screen region with no arbitration:
  `CaptionRenderer` (cinematic captions, queued) and `AnnouncementOverlay`
  (`TypewriterLine`, own queue). A long decree caption visually blocks announcements and
  vice versa; neither yields.

**Exact fix:**
1. `DawnCeremony`: only send the decree caption when the goal set actually changed since
   the previous day (hash the goal ids; store last hash in the ceremony state); otherwise
   skip the beat (shortens the ceremony, no empty gap).
2. Single arbiter: `AnnouncementOverlay` becomes the owner of the shared screen band.
   `CaptionRenderer` exposes `isBusy()`; `AnnouncementOverlay` defers its queue while a
   caption is on screen (poll, don't drop), and `CaptionRenderer` likewise waits for the
   current typewriter line to finish before starting a caption (two-way politeness, no
   hard preemption, both queues preserved — nothing is ever dropped, only delayed).
3. Dedupe inside `AnnouncementOverlay`: identical message enqueued while the same text is
   pending/visible → coalesce.

**Files owned:** `drama/DawnCeremony.java`, `client/hud/AnnouncementOverlay.java`,
`cutscene/client/CaptionRenderer.java` *(queue/arbitration logic — A1 touched only its
i18n lookup lines; land after A1)*.

**Effort:** M. **DEPENDS-ON:** A1 (soft, rebase).

---

## A16 — EMI gate fix + EMI upgrade

**Covers item:** 19.

**Root causes.**
- `EclipseEmiPlugin.isHiddenStack` (L72–89) hides a stack only via the `EMI_HIDDEN` item
  tag or `ClientUnlockCache.isNamespaceLocked(namespace)`. Namespace locks come from
  `run/config/eclipse/modgate.json` — but **`createconnected`, `create_confectionery`
  (the "chocolate" mod), and `ends_delight` are only gated per-item by glob patterns in
  `modgate_ids.json`**, which `isHiddenStack` never consults → their items stay visible
  in EMI while still being server-locked.
- EMI pinned at `1.1.18+1.21.1` (`build.gradle` L145–148). Newer 1.21.1 NeoForge builds
  exist on the TerraformersMC maven: **1.1.22+1.21.1** is the conservative bump;
  1.1.24 line also publishes `+1.21.1` artifacts — worker must verify the newest
  `emi-neoforge` `+1.21.1` artifact actually resolvable from
  `https://maven.terraformersmc.com/releases/dev/emi/emi-neoforge/` at build time and
  pin that exact version (strictly, matching current jarJar pattern).
- Note: gradle may not be runnable in this environment — version bump must be verified
  by the worker in an environment with network + gradle.
1. `isHiddenStack`: additionally test the stack id against the compiled glob matchers
   from `modgate_ids.json` (the matcher already exists server-side for enforcement —
   expose it through `ClientUnlockCache.isIdLocked(ResourceLocation)`, synced the same
   way locked namespaces are).
2. Belt-and-braces: add the three namespaces to `modgate.json` `namespaces` if the
   *entire* mods are meant to be gated (check design intent in
   `docs/plans_v3/P4_gameplay.md` gate table; if only subsets are gated, glob fix alone
   is correct — worker decides from the table and records the decision).
3. Bump `build.gradle` EMI to the newest resolvable `+1.21.1` version (≥1.1.22), both
   the `:api` compileOnly and the jarJar strictly pin; run the client once to confirm
   the plugin API surface (`EmiRegistry.removeEmiStacks/removeRecipes`) is unchanged.

**Files owned:** `client/emi/EclipseEmiPlugin.java`,
`client/progression/ClientUnlockCache.java`, `run/config/eclipse/modgate.json`,
`run/config/eclipse/modgate_ids.json`, `build.gradle` (EMI lines only).

**Effort:** M.

---

## Ownership matrix (collision check)

| File / area | Owner |
|---|---|
| `client/lang/EclipseLang.java`, `lang/*`, both lang JSONs | A1 |
| `client/loading/*` | A2 |
| `client/menu/*`, title textures | A3 |
| `client/handbook/tabs/TimelineTab.java` | A4 |
| `client/handbook/tabs/RewardsTab.java`, milestones payload | A5 |
| `client/handbook/tabs/MapTab.java`, landmark discovery | A6 |
| `client/hud/DayTimerLayer.java`, `RealtimeDayService`, `TimedBuffService`, `EclipseGuiLayers.java`, `BossbarSkin` (stacking) | A7 |
| `client/hud/Sidebar*`, sidebar payload, `ClientStateCache.eventStarted`, settings | A8 |
| `client/skills/SkillXpBarLayer.java` | A9 |
| `client/hud/BossbarSkin.java` (style, after A7) | A10 |
| `client/invlock/InvLockOverlay.java` | A11 |
| `artifact/*` | A12 |
| `progression/rebirth/*`, `hearts/HeartsService.java`, rebirth payload/config | A13 |
| `client/skills/SkillTree*`, `client/wand/*`, `skilltree.json` | A14 |
| `drama/DawnCeremony.java`, `client/hud/AnnouncementOverlay.java`, `CaptionRenderer` (queue) | A15 |
| `client/emi/*`, `ClientUnlockCache.java`, modgate configs, `build.gradle` | A16 |

**Serialization constraints:** A10 after A7. A14 after A13. A9/A12 need A8's flag (can
develop in parallel against the contract, merge after). A15 rebases on A1. Everything
else fully parallel.

## Item → package map

| Item | Package(s) |
|---|---|
| 1 loading lang | A1 |
| 2 loading fade | A2 |
| 3 no menu settings | A3 |
| 4 "AY 1" clip | A4 |
| 5 timeline polish | A4 |
| 6 altar rewards | A5 |
| 7 map rework | A6 |
| 8 one day timer | A7 (+A8 sidebar rows) |
| 9 XP bar replace | A9 |
| 10 bossbar style | A10 |
| 11 lock-slot hint | A11 |
| 12 sidebar | A8 |
| 13 artifact gate | A12 |
| 14 skill tree/rebirth/wand | A13 + A14 |
| 15 hearts/Leben | A13 (server) + A8 (labels) — display layer note below |
| 16 main menu art | A3 |
| 17 i18n sweep | A1 (+A15 captions) |
| 18 New Decree | A15 |
| 19 EMI | A16 |

**Item 15 note (hearts display):** `PurpleHeartsLayer` already replaces vanilla
`PLAYER_HEALTH`; remaining work is (a) the 1 Leben = 2 MC hearts (4 HP) compression in
that layer's row math, (b) killing any residual vanilla-heart render path when absorption
/ effects modify health, (c) "Leben/Lives" strings in sidebar (A8), death screen +
handbook header (A1 lang values). The layer file `hearts/client/PurpleHeartsLayer.java`
is assigned to **A13's worker** (same subsystem, no other package touches it).
