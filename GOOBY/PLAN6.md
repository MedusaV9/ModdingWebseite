# GOOBY V6 — FINAL PLAN (binding; becomes PLAN6.md, commit with CRLF endings)

Reviewed against the real tree on `cursor/gooby-polish-b7d6`. All load-bearing claims in this plan
were re-verified: stickers dir = **6,619,948 B / 49 files** (6.31 MiB of the 7.5 MiB
`FEATURE_CAPS_MB.stickers` cap — the test computes MB as 1024²); tested covers = **2,134,527 B /
30 PNGs** against the 2.3 MiB `TOTAL_BYTES` pin (≤85 KiB per file); **15** registered DOM screens
(grep `registerScreen(` — `gooby` showcase is a scene); `src/ui/ui.js openPanel()` has **no
duplicate-id guard** (verified); `src/data/stickers.js` pages are positional
`STICKER_PAGE_SIZES = [6×8]` with 48 regular + secret `herzGooby` last; `src/systems/vacation.js`,
`src/data/harnessParams.js`, `src/systems/notifyRules.js` (NOTIFY.IDS 1–8, MAX_SCHEDULED 8),
`test/gameCovers.test.js`, `src/recap/vignettes.logic.js` samplers, `src/ui/backdropDismiss.js`,
and every owned file below exist — with one exception fixed in Wave E (`test/decor.test.js` does
not exist). The Stickerbuch CSS lives in `albumScreen.js`'s injected `ALBUM_CSS` (line ~94), not
`styles.css`.

## Executive ruling (delta to EVAL)

The EVAL plan is sound and is adopted with corrections. The three binding changes:

1. **Stickers: +36, not +24 (48 → 84 regular).** The user's wish is explicit and superlative
   ("WESENTLICH mehr — wir brauchen VIEL mehr"); +24 (a 50% bump) under-delivers on the single
   most explicit ask. +36 is a 75% expansion (14 six-slot pages), stays payload-safe
   (6.31 + ≤3.4 MiB = ≤9.7 MiB → cap raise 7.5 → **10.0 MiB**, trivially inside the 280 MB app
   warn line), and bounds art-consistency risk by choosing the 12 additional stickers exclusively
   from rules that ride **existing signals** plus three trivial profile-reading specials. The two
   genuinely risky rule classes the evaluator cut — seasonal clock-only windows and self-count
   meta stickers — **stay cut** (those were technical/UX-risk cuts, not taste).
2. **Two restores** (allowed ≤3, both serve binding priorities, both fit budget):
   the **Riesenrad (ferris wheel)** as new agent F4 — the calm counterpart that makes Funkelpark
   read as a *park* rather than one ride (priority 1), procedural build, no save/economy surface;
   and the **petal-wipe transition + soft-settle panels** (idea 07 #15) folded into F2/F3 —
   the most-seen surface in the game gets the ACNH read (priority 9), a canvas variant of the
   existing iris wipe with the reduced-motion fallback already in place.
3. **Ownership/sequencing fixes:** strings-import hand-offs specified for every wave (not just
   B/D); Wave-D internal merge order pinned (D4's emoji gate can only pass after D3 merges);
   E1↔E2/E3 integration exports made explicit; E4's nonexistent `test/decor.test.js` replaced;
   F1's CSS location pinned to `ALBUM_CSS`.

Everything else from EVAL §1–§2 (scorecard, conflict resolutions, the single-coaster ruling, the
canonical nine-destination board, theme/ambient split, postcard-vs-sticker split, room-anchor
split) stands unchanged and is incorporated by reference.

## 3. THE PLAN

### Global merge/verification contract

- Each agent owns only the listed files. Cross-agent calls use agreed exports frozen at wave
  start; no opportunistic edits.
- Every commit runs `npm run lint`, `npm test`, and `npm run build`; each wave ends with
  `npx cap sync ios`; the iOS/.ipa CI must be green before the next wave starts. Visual agents
  also provide the named screenshots and a short real-time video.
- New/edited source stays CRLF, JSDoc, vanilla ES modules, EN+DE, and sample-backed audio only
  (no new synth recipes).
- No `SAVE.VERSION` bump. Every additive slice gets missing/junk/round-trip/offline tests and
  bounded arrays/maps. Additive `vacation`-slice fields MUST be added to `defaultSlice()`,
  `sliceOf()`, and every carried-transition helper — `sliceOf` whitelists fields and silently
  strips the rest.
- Shared-file owners by wave are exclusive:

| Wave | `styles.css` | `strings.js` | `constants.js` | `main.js` | `harnessParams.js` |
|---|---|---|---|---|---|
| A | A2 | A2 | — | A1 | A1 |
| B | B3 | B2 | — | — | — |
| C | — | C3 | C3 | — | — |
| D | D4 | D2 | D2 | — | D1 |
| E | — | E1 | — | E1 | E1 |
| F | F3 | F1 | — | — | — |

- **Appendix rule (extended):** a non-owner hands the owner a small labeled block; only the owner
  commits it. Explicitly: in A, **A2 commits A1's `v6-cutscenes.js` import pair** in `strings.js`.
  In B, **B3 commits B1's `V6/RECAP-LANDSCAPE` CSS** and **B2 commits B3's `v6-screen-themes.js`
  import**. In C, **C3 commits C4's `v6-juice.js` import**. In D, **D2 commits D1/D2 string
  imports and D4's raw-emoji removals in legacy `strings.js`**. In E, **E1 commits E3's
  `v6-park.js` import; E2's coaster caption keys land inside E3's `v6-park.js` as a labeled
  block**. In F, **F1 commits its own `v6-stickers.js` import** (F1 owns `strings.js` in F). No
  block may modify another block's selectors/data.
- **Wave-D merge order is pinned: D1 → D2 → D3 → D4.** D4's emoji-audit gate asserts zero rendered
  raw emoji across `src/` and can only go green once D3's icon replacements are merged.

### Wave A — foundations

#### A1 — Cutscene director

Goal: reusable, fail-safe timeline with a minimal demo consumer.

Owned files: new `src/systems/cutscene.js`, `src/ui/cutsceneView.js`, `src/data/cutscenes.js`,
`src/data/strings/v6-cutscenes.js`, `test/cutscene.test.js`; edit `src/main.js`,
`src/data/harnessParams.js`. (Strings import handed to A2 per the appendix rule.)

Acceptance: deterministic sequence/parallel/wait tests; 45 s watchdog; first-view hold and replay
tap skip; `finally` restores camera/gyro/music/props/overlay; camera lease refuses to start while
`roomManager.isPanning()`, during sleep, or while `sceneManager.isSwitching()`; reduced-motion
compile; every op, clip, emotion, sample id, and EN/DE key validated by a data-mirror test (the
source scanner in `test/onboarding.test.js` cannot see data-driven ids). Capture
`v6-a-cutscene-demo.png` and a skip/cleanup video.

Commit: `GOOBY V6/CUTSCENE: add reusable cinematic director`

#### A2 — Screen-theme and motion contract

Goal: all 15 DOM screens receive a coherent bespoke palette/pattern with one slow layer.

Owned files: edit `src/ui/styles.css`, `src/data/strings.js`; new `test/screenThemes.test.js`;
new `public/assets/acui/pattern_shop.png`, `pattern_wardrobe.png`, `pattern_arcade.png`,
`pattern_quest.png`, `pattern_album.png`, `pattern_passport.png`, `pattern_clinic.png`,
`pattern_radio.png`, `pattern_trophy.png`, `pattern_credits.png`, `pattern_blueprint.png`.

Acceptance: test derives registered screen ids and requires exactly one theme assignment each;
`--thm-*` defaults reproduce today's rendering pixel-for-pixel where a screen opts out;
transform-only 80–120 s drift (explicit translate variables — **no CSS `calc()` multiplication of
lengths, no `background-position`/filter animation**); reduced motion freezes it;
`test/screenThemes.test.js` also asserts each pattern PNG ≤48 KiB and the 11-tile aggregate
≤512 KiB; 320×568 and 390×844 EN/DE/uiScale-130 contact sheets; 10 s real-time drift video.

Commit: `GOOBY V6/THEMES: give every screen a cozy visual world`

#### A3 — Batched home ambient foundation

Goal: low-cost room life with day/weather switching.

Owned files: new `src/home/ambientLife.js`, `src/home/ambientLife.data.js`,
`test/ambientLife.test.js`; edit `src/home/homeScene.js`, `src/home/roomManager.js`.

Acceptance: pure sampler and band/weather tests (samplers ported from
`src/recap/vignettes.logic.js` `flutterPose`/`driftPose`/`streakPose` — verified present);
batched by texture/kind (fireflies = one `InstancedMesh`); ≤4 added draw calls in each room;
no-op under reduced motion; mount/swap/dispose leak tests. Capture day/night garden, kitchen
steam, living motes, bathroom bubbles, and bedroom-star states plus one real-time video.

Commit: `GOOBY V6/AMBIENT: bring slow life to every room`

#### A4 — Panel-layer correctness

Goal: close only the top dismissable sheet and never lose claim/one-time content.

Owned files: edit `src/ui/ui.js`, `src/ui/dailyBonusPopup.js`, `src/ui/whatsNew.js`,
`test/uiBackdropDismiss.test.js`; new `test/uiLayerPolicy.test.js`.

Acceptance: duplicate `openPanel(id)` returns false (guard verified missing today);
`backdropDismiss:false` opt-out consumed by daily bonus/what's-new (dailyBonus additionally must
not latch `shownDay` before claim); stacked panels close top only; child drag/cancel does not
dismiss; no click-through. Record the stacked-panel and nondismissable-popup interactions;
capture the final top-only state.

Commit: `GOOBY V6/UI-LAYERS: harden submenu backdrop dismissal`

### Wave B — recap, travel map, flagship screens

#### B1 — Landscape recap and Gooby framing

Goal: a true landscape cinematic with Gooby correctly seated, visible, and facing the story.

Owned files: edit `src/ui/recapOverlay.js`, `src/ui/recapOverlay.logic.js`,
`src/recap/vignettes.js`, `src/recap/vignettes.logic.js`, `test/recapOverlay.test.js`,
`test/recapVignettes.test.js`. (Landscape CSS handed to B3 per the appendix rule.)

Acceptance: rotated-frame/safe-inset math tests (JS-px vars, never `100vh/vw`); renderer
dimensions restored on finish/skip/error (every exit path, asserted); all eight midpoint previews
keep Gooby in a center-safe region; seat derives from hull bounds (`Box3`), not constants; facing
bias on walk biomes; calls stay ≤150 per vignette re-measured in landscape; full L10 beat error
stays ≤80 ms. Capture eight landscape previews and one full recap video on 390×844 with
`?notch=1`; verify DPR and the letterboxed reduced-motion fallback.

Commit: `GOOBY V6/RECAP: make the Rückblick a landscape movie`

#### B2 — Canonical nine-destination board

Goal: connect every recap place to a real vacation while preserving current saves.

Owned files: edit `src/data/vacations.js`, `src/ui/airportScreen.js`, `test/vacation.test.js`,
`src/data/strings.js`; new `src/data/strings/v6-vacations.js`.

Acceptance: catalog pins 4→9 with unique biome ids (`beach` stays the bonus non-recap ninth;
`harbor` is its own destination — never collapsed into beach), 3/4-day durations,
`souvenirCoins` ≪ price (anti-arbitrage), and exact `recap.lastRecapLevel` gates 15/25/30/35/40;
old destinations stay bookable and ungated; new locked cards disclose no destination art/name
before unlock; airport list scrolls at 320 px. Capture L1/L15/L40 boards in EN+DE.

Commit: `GOOBY V6/TRAVEL-MAP: turn recap places into destinations`

#### B3 — Shop, profile, album bespoke redesign

Goal: make the three most visible screens read as IKEA-cozy shop, passport, and scrapbook.

Owned files: edit `src/ui/shopScreen.js`, `src/ui/profileScreen.js`, `src/ui/albumScreen.js`,
`src/ui/styles.css`; new `src/data/strings/v6-screen-themes.js`,
`test/screenThemeDetails.test.js`. (Strings import handed to B2 per the appendix rule.)

Acceptance: no behavior/catalog changes; shelves do not clip cards (rotated tags get padding
compensation inside `overflow:hidden` grids); album scroll-snap survives page styling; passport
MRZ clips safely with `tabular-nums`; B1 landscape CSS included in its marked block; skin
exclusions `300001/300004/300006` untouched. Capture all three at 320×568 and 390×844, DE,
uiScale 130, notch enabled.

Commit: `GOOBY V6/SCREEN-WORLDS: rebuild shop profile and album`

### Wave C — games and game juice

#### C1 — Sternenlaterne

Owned files: new `src/minigames/games/lanternFloat.js`,
`src/minigames/games/lanternFloat.logic.js`, `test/lanternFloat.test.js`.

Acceptance: deterministic bot; invertible drag contract (one-boundary mirror per §G2.1 rule 1,
`harborHopper` pattern); difficulty direction/guardrails; endless termination; dispose hygiene;
gameplay video for normal/inverted/reduced-motion and result screenshot.

Commit: `GOOBY V6/GAME-LANTERN: add Sternenlaterne`

#### C2 — Schneckenpost

Owned files: new `src/minigames/games/snailMail.js`, `src/minigames/games/snailMail.logic.js`,
`test/snailMail.test.js`.

Acceptance: path endpoints/arc length/speed (reusing the `goobyWelt.logic.js` spline toolkit),
puddle edges, bonuses, deterministic bot, difficulty and dispose tests; gameplay video showing
draw-follow-deliver-retreat and result screenshot.

Commit: `GOOBY V6/GAME-SNAIL: add Schneckenpost`

#### C3 — Game data spine, covers, and pin choreography

Owned files: edit `src/data/constants.js`, `src/data/minigames.js`,
`src/data/difficultyTargets.js`, `src/systems/modifierEngine.js`, `src/data/strings.js`,
`test/minigameMeta.test.js`, `test/dataV2.test.js`, `test/dataV3.test.js`, `test/economy.test.js`,
`test/achievements.test.js`, `test/leveling.test.js`, `test/controlsContract.test.js`,
`test/gameCovers.test.js`, `test/v4ArcadeUi.test.js`, `test/modifierEngine.test.js`,
`test/difficultyCertification.test.js`, `test/difficultyEndless.test.js`; new
`src/data/strings/v6-games.js`, `test/minigamesV6.test.js`,
`public/assets/covers/lanternFloat.png`, `public/assets/covers/snailMail.png`.

Acceptance: all coordinated pins move 30→32 in ONE commit (metadata's dev-inclusive 31→33;
modifier-eligible 29→31 — the hard-coded `ALL_ARCADE_GAMES` literal in `modifierEngine.js` must be
edited); one documented V6 constants block (the V5/G06 precedent at `constants.js:796`);
exactly two ≤64 KiB indexed covers so the 2.3 MiB total pin is NOT raised (measured headroom
~277 KiB); games unlock at L6 (`snailMail`) / L7 (`lanternFloat`) and certify across difficulty
seeds. Capture the arcade grid.

Commit: `GOOBY V6/GAME-SPINE: wire two games and update contract pins`

#### C4 — Six-game juice pass

Owned files: edit `src/minigames/games/memoryMatch.js`, `memoryMatch.logic.js`, `goobySays.js`,
`goobySays.logic.js`, `pipeFlow.js`, `miniGolf.js`, `cityDrive.js`, `deliveryRush.js`,
`veggieChop.js`; new `src/data/strings/v6-juice.js`, `test/gamePolish6.test.js`. (Strings import
handed to C3 per the appendix rule.)

Acceptance: particles/samples/floats/reaction at the same event point; existing sfx ids only;
reduced-motion gates (imports added where missing); city-driving pair gets NO added camera shake
(PLAN4 §C7.2 motion-comfort ruling); frozen scoring tables unchanged, pinned by `*_JUICE` blocks.
Record before/after clips for the six dry-game groups and capture the final event-feedback states.

Commit: `GOOBY V6/GAME-JUICE: animate the driest arcade games`

### Wave D — vacation depth and authored UI

Merge order within the wave: **D1 → D2 → D3 → D4** (D4's audit gate requires D3's replacements).

#### D1 — Airport departure and reunion set pieces

Owned files: new `src/vacation/vacationCinematic.js`, `src/vacation/vacationCinematic.logic.js`,
`src/data/strings/v6-vacation-scenes.js`, `test/vacationCinematic.test.js`; edit
`src/data/cutscenes.js`, `src/ui/airportScreen.js`, `src/data/harnessParams.js`.

Acceptance: payment/pickup completes atomically BEFORE presentation; refused/failed cinema never
blocks state (callers treat `false` as skip-silently); on-time and taxi scripts differ without
changing rewards/stats (`PICKUP_STAT_FILL`, taxi fee frozen); departure cutscene never replays on
boot after offline catch-up (key off explicit user actions, not phase observation); skip and
reduced-motion land cleanly. Record all three paths and capture each final reunion state.

Commit: `GOOBY V6/VACATION-CINE: stage departures and reunions`

#### D2 — Daily postcard archive and fair reminders

Owned files: edit `src/systems/vacation.js`, `src/systems/notifyRules.js`,
`src/data/constants.js`, `src/data/strings.js`, `test/vacation.test.js`, `test/offline.test.js`,
`test/notifyRules.test.js`; new `src/systems/postcards.js`,
`src/data/strings/v6-vacation-content.js`, `test/postcards.test.js`.

Acceptance: archive stores destination/day/variant/time, caps at 36, normalizes junk, and
produces identical live/offline results without duplicates (every additive field added to
`defaultSlice`/`sliceOf` AND the transition helpers — the verified whitelist-strip trap);
fixed-ms trip days remain DST-safe; reminders at landing and pickupBy−3h obey quiet hours (not
quiet-exempt). Approve notification ids 9–10 / MAX_SCHEDULED 10 in one labeled constants block
(G53 precedent at `constants.js:761`). Capture airport archive after a pinned multi-day time jump
and test schedule output.

Commit: `GOOBY V6/VACATION-DEPTH: archive postcards and schedule pickup`

#### D3 — Authored icon catalogs and visual consumers

Owned files: new `src/ui/foodIcons.js`, `src/ui/iconCanvas.js`; edit `src/ui/icons.js`,
`src/data/foods.js`, `src/home/interactions.js`, `src/home/gardenInteractions.js`,
`src/home/decor.js`, `src/home/roomManager.js`, `src/ui/shopScreen.js`, `src/ui/gardenPanel.js`,
`src/ui/recapOverlay.js`, `src/ui/recapOverlay.logic.js`, `src/ui/loadingVeil.js`,
`src/ui/devPanel.js`, `src/minigames/framework.js`, `src/minigames/games/rocketRescue.js`,
`src/minigames/games/harborHopper.js`, `src/minigames/games/toyRacer.js`,
`src/minigames/games/purblePlace.js`, `src/minigames/games/burgerBuild.js`,
`src/minigames/games/miniGolf.js`, `src/minigames/games/starHopper.js`,
`src/minigames/games/shoppingSurf.js`, `src/minigames/games/cityDrive.js`,
`src/minigames/games/ghostHunt.js`, `src/minigames/games/deliveryRush.js`; edit
`test/icons.test.js`.

Acceptance: every food id and furniture/crop category resolves to authored SVG (one
`foodIcons.js` source of truth kills the two divergent `FOOD_EMOJI` tables);
`recapOverlay.logic.js` returns icon NAMES (stays headless-pure), the view renders them; canvas
surfaces use rasterized SVG, never font emoji; color-blind geometric symbols remain; a
catalog-sync test asserts every `foods.js` id has an icon. Screenshots cover tray, shop, garden,
recap, and affected HUDs at 85/130 scale.

Commit: `GOOBY V6/ICONS: replace raw glyphs with authored UI art`

#### D4 — Raw-emoji endgame and gate

Owned files: edit `src/ui/ui.js`, `src/ui/hud.js`, `src/ui/pregameScreen.js`,
`src/ui/modifierSurface.logic.js`, `src/ui/radioScreen.js`, `src/ui/photoMode.js`,
`src/ui/vetPanel.js`, `src/ui/sleepFlow.js`, `src/ui/careSheet.js`, `src/ui/arcadeScreen.js`,
`src/ui/albumScreen.js`, `src/ui/styles.css`, `src/systems/stickerBook.js`,
`src/systems/codesEngine.js`, `src/systems/leveling.js`, `src/systems/shopTrip.js`,
`src/systems/economy.js`, `src/data/strings/v4-modifier.js`, `v4-xp.js`, `v4-recap.js`,
`v4-difficulty.js`, `v4-recap2.js`, `v4-surf.js`, `v4-sick.js`, `v4-gallery.js`, `v4-codes.js`,
`v2-core.js`, `v2-health.js`, `v2-city.js`, `v3-travel.js`, `v2-games-e.js`, `v2-progress.js`,
`v2-garden.js`, `v4-core.js`, `v4-arcade.js`, `v3-stickers.js`, `package.json`; new
`scripts/emoji-audit.mjs`, `test/emojiAudit.test.js`. (Legacy `strings.js` removals handed to D2.)

Acceptance: audit reports zero rendered raw emoji; explicit exemptions are ONLY OS notification
bodies and `bubblePop` a11y geometry; comments do not count (parse rendered code/strings, never a
blind codepoint purge); EN/DE parity and the ~12 prior literal-string tests updated in the same
commit; lands LAST in Wave D. Produce a route contact sheet proving persistent UI is authored.

Commit: `GOOBY V6/NO-EMOJI: finish the authored interface sweep`

### Wave E — Funkelpark and rooms

#### E1 — Park trip, hub, and compact state

Owned files: new `src/park/parkScene.js`, `src/park/parkBuilder.js`, `src/systems/themePark.js`,
`test/parkLayout.test.js`, `test/themePark.test.js`; edit `src/city/cityBuilder.js`,
`src/minigames/games/cityDrive.js`, `src/systems/shopTrip.js`, `src/main.js`,
`src/data/harnessParams.js`, `src/data/strings.js`, `test/cityLayout.test.js`,
`test/cityRoads.test.js`, `test/shopTrip.test.js`.

**Integration contract (frozen at wave start):** E1's `parkScene.js` wires the plaza tap anchors
to agreed exports it does not implement — `startCoasterRide(ctx)` from E2's `coasterRide.js` and
`mountParkDressing(sceneGroup, band)` / `openParkStall(ui)` from E3's modules — plus a named
`ferrisWheel` plaza anchor reserved for F4. E1 commits E3's `v6-park.js` strings import.

Acceptance: route pins deliberately gain `parkRoute`/`parkGate`; tow always reaches the park;
plaza footprints have zero overlaps (layout test); state slice records visits/attraction counters
defensively (own `defaultSlice`/`sliceOf`, known ids only); hub ≤120 calls; trip and plaza are
vacation/sleep gated via untouched `canRequestTrip`. Record the trip and capture plaza arrival.

Commit: `GOOBY V6/PARK-HUB: open Funkelpark as a day trip`

#### E2 — One interactive cinematic coaster

Owned files: new `src/park/coasterRide.js`, `src/park/coasterRide.logic.js`,
`src/park/trackPieces.js`, `test/coasterRide.test.js`. (Caption keys land in E3's `v6-park.js` as
a labeled block.)

Acceptance: every track socket joins within 1 mm (socket math from the toy-car-kit table, never
eyeballed); cart/camera pose is continuous with clamped roll; hands-up windows are deterministic
and optional; NO fail/score/payout/cover/game-count pin (this is a park attraction, not an arcade
row — the single-coaster ruling); reduced motion uses static shots; ride ≤90 calls. Record the
full ride and capture lift/apex/photo states.

Commit: `GOOBY V6/PARK-COASTER: add the Funkelpark signature ride`

#### E3 — Candy Alley and lights

Owned files: new `src/park/parkDressing.js`, `src/ui/parkStall.js`,
`src/data/strings/v6-park.js`, `test/parkAttractions.test.js`; edit `src/data/foods.js`,
`src/ui/shopScreen.js`, `test/foodsV4.test.js`.

Acceptance: three park foods stay hidden from the normal shop (`park: true` filter) and buy
through existing `economy.buyFood`, priced ≥ shop equivalents; stalls/awnings are bounds-grounded
(counter plane at the measured bbox face, +2 cm prop offset against z-fighting); shared materials
swap once per band; night lights add ≤2 calls; no balloon persistence. Capture day/night plaza
and one food purchase/feeding video.

Commit: `GOOBY V6/PARK-LIFE: add Candy Alley and night lights`

#### E4 — Five-room asset rebuild

Owned files: edit `src/home/rooms/living.js`, `bedroom.js`, `garden.js`, `kitchen.js`,
`bathroom.js`, `src/home/decor.js`, `src/home/roomAudit.rules.js`,
`scripts/gen-asset-bounds.mjs`, `test/fixtures/asset-bounds.json` (regenerated, never
hand-edited), `test/roomAudit.test.js`, `test/rooms.test.js`; new `scripts/audit-rooms.mjs`.
(**Fix vs EVAL:** `test/decor.test.js` does not exist in the tree and is removed from this list.)

Acceptance: on-disk packs only (Tiny Treats/KayKit/aline — no new downloads); `FORWARD_BY_PACK` /
`FORWARD_OVERRIDES` entries added for `pretty-park`, `kaykit-furniture`, `house-plants`
(currently blind); zero audit warnings for clip/float/sink/facing/shell/tap targets across all 5
rooms; every enumerated `tap:*` hitbox and anchor keeps working; ≤4 added calls per room; moving
bird excluded and `gardenFenceBird` anchor present (ambient owns all moving visitors). Capture
before/after all five rooms and a room-tour video.

Commit: `GOOBY V6/ROOMS: rebuild every room with committed asset packs`

### Wave F — sticker payoff and final cozy polish

#### F1 — 84-sticker book (**changed: +36, not +24**)

Owned files: edit `src/data/stickers.js`, `src/systems/stickerBook.js`, `src/ui/albumScreen.js`,
`src/data/strings.js`, `test/stickers.test.js`, `test/stickerBook.test.js`, `test/fixD.test.js`,
`test/dataV3.test.js`, `test/assetBudget.test.js`; new `src/data/strings/v6-stickers.js` and
exactly 36 PNGs in `public/assets/stickers/`:

- **Page 9 „Reise" (Travel):** `beachPostcard`, `harborPostcard`, `bakeryPostcard`,
  `nightSkyPostcard`, `frequentFlyer`, `penPal`
- **Page 10 „Funkelpark":** `parkFirstVisit`, `loopStar`, `handsUp`, `candyDay`, `nightLights`,
  `parkExplorer`
- **Page 11 „Arcade-Sterne" (Arcade Stars):** `lanternKeeper`, `snailCourier`, `ghostWhisperer`,
  `harborMaster`, `rocketHero`, `pipeDreamer`
- **Page 12 „Kuschelleben" (Cozy Life):** `weekStreak`, `medsMaster`, `marketDay`,
  `memoryKeeper`, `interiorDesigner`, `storyTeller`
- **Page 13 „Schlemmerei" (Foodie Feast):** `teaTime`, `pancakeMountain`, `burgerBoss`,
  `veggieChef`, `cakeParade`, `nougatFlood` — all six ride EXISTING signals (`gameBest`,
  `cakesServed`, `nougatGlobs`); zero new evaluators
- **Page 14 „Beste Freunde" (Best Friends):** `bestBuddies`, `inseparable`, `tickleTornado`,
  `monthStreak`, `hatParade`, `bigSpender` — three trivial new specials (`playtimeMin`,
  `outfitsOwned`, `coinsSpent`), each a ~3-line pure profile/outfits read

(Id-collision check against the shipped 49 ids: clean.)

Acceptance: coordinated pins 48→84 regular, 49→85 total defs/art, 8→**14** pages of six
(append-only positional slicing — the frozen table order and secret-last invariant remain; NO
re-homing of existing pages); titled page rail with keyboard/swipe replaces the dots; page-tinted
mystery boxes keep the airtight locked rule verbatim — locked slots create no `<img>`/src/request
and reveal only page-generic tint/watermark/index; **all unlock conditions are pure reads of
existing state** (postcard stickers read D2's archive entries; park stickers read E1's park
counters; arcade stickers read `minigames` bests/counters) — no new fire sites outside
`stickerBook.js`, and sticker evaluation re-runs on the relevant change events and at boot after
offline catch-up; no rewards, no rarity animation, no seasonal clock windows, no self-count
stickers; F1's page-rail/tint CSS lives inside `albumScreen.js`'s injected `ALBUM_CSS` block —
`styles.css` (owned by F3) is not touched. Art: 512×512 indexed PNG-8, ≤96 KiB per V6 file
(new assertion), master BASE prompt from idea 05 §(d), 2–3 candidates per sticker with a
mandatory same-bunny human review before merge; raise `FEATURE_CAPS_MB.stickers` 7.5 → **10.0**;
existing 150 KiB legacy per-file ceiling retained. Capture locked/unlocked Travel and Park pages
and network proof of zero locked-art requests.

Commit: `GOOBY V6/STICKERS: expand the book to 84 authored keepsakes`

#### F2 — Gooby/world ambient reactions + cozy transitions (**restore folded in**)

Owned files: edit `src/home/ambientLife.js`, `src/home/ambientLife.data.js`,
`src/home/homeScene.js`, `src/gfx/particles.js`, `src/ui/loadingVeil.js`,
`test/ambientLife.test.js`; new `src/home/ambientVisitors.js`, `test/ambientVisitors.test.js`.

Acceptance: Gooby watches nearby butterfly/bird with clamped head motion, emits authored note
particles while happy, and the transient bird visit schedules deterministically without save
writes; hidden/reduced-motion cleanup is airtight; home remains ≤100 calls/40k tris. **Restored
petal wipe:** the loading veil gains a petal/leaf sweep variant of the existing canvas iris wipe
(2 pre-painted sprites, stamped with rotation, same 450 ms window); reduced motion keeps the
plain fade; no new architecture, no DOM particle layer. Record one garden visitor sequence, one
humming micro-idle, and one petal-wipe transition; capture peak states.

Commit: `GOOBY V6/COZY-LIFE: connect Gooby to the living world`

#### F3 — Scale/accessibility hardening and release gate (**restore folded in**)

Owned files: edit `scripts/px-audit.mjs`, `src/city/carController.js`,
`src/character/showcase.js`, `src/ui/styles.css`, `package.json`, `test/miscQuality.test.js`.

Acceptance: px audit recursively covers CSS literals in UI/home/character/city/minigames with no
temporary allowlist left at the end; the two verified offender islands (`carController.js`,
`showcase.js`) swept ÷16 with 44 px touch floors preserved; global `:focus-visible` ring;
**restored soft-settle:** `panel-up` retuned to a settle overshoot
(`cubic-bezier(0.34,1.56,0.64,1)`), reduced-motion exempt; screenshots at uiScale 85/130 and
DE/notch; final lint/test/build/cap-sync and asset/draw-call ledgers attached.

Commit: `GOOBY V6/RELEASE-POLISH: harden scale focus and final gates`

#### F4 — Riesenrad (**restored item**, new agent)

Owned files: new `src/park/ferrisWheel.js`, `test/ferrisWheel.test.js`; edit
`src/park/parkScene.js`, `src/park/parkBuilder.js` (E1's files — untouched by any other Wave-F
agent), labeled string block in `src/data/strings/v6-park.js`.

Goal: the calm anti-coaster — tap the wheel, a ~45 s real-time gondola ride over the plaza with
day-band/weather visible, Gooby leaning out and waving at the apex; the existing HUD camera
button works throughout (photo spot for free).

Acceptance: fully procedural build (rim/spokes/hub/gondolas from primitives + instancing — no new
assets, no cover, no economy calls, no save fields); the classic bug is unit-tested: pure
`gondolaTransform(θ, i)` counter-rotates cabins so they stay upright and never swing through
spokes; camera tween via `gfx/tween.js` with `finally` restore; reduced motion = static apex shot;
park hub stays ≤120 calls WITH the wheel mounted; vacation/sleep gating inherited from the trip.
Record the full ride; capture the apex view in day and dusk bands.

Commit: `GOOBY V6/PARK-WHEEL: add the Riesenrad quiet ride`

## 4. Explicit cut/defer list (updated)

- Vacation: suitcase, physical souvenir shelf, streak bonuses, grumpy stat penalty, separate
  diary (postcard text variants cover the flavor), airport pickup drive, rotating deals.
- Park: ~~ferris wheel~~ **restored as F4**; park map, balloons, day ticket/stamp card, ride
  payout, rocket carousel, swan pond, parade, park photo frame — still cut/deferred.
- Games: `coasterRush`, `jamCarousel` cut; `plushWash` deferred.
- Themes: full tab/chip/header convergence, second ambient veil, floating DOM theme particles.
- Stickers: the remaining +24/+3 of agent 05's proposal, new secrets/codes, page coin rewards,
  rarity animations, **seasonal clock-only unlocks** (kept cut: a season-gated page is
  uncompletable for most of the year — UX risk, not taste), **self-count meta stickers** (kept
  cut), page re-homing of the existing 48.
- Cutscenes: birthday deferred; first snow and onboarding retrofit cut.
- Ambient: plant/curtain/clock/TV/window-cloud loops deferred; ~~petal wipe~~ **restored into
  F2/F3**; roomba/audio-moment scheduler cut.
- Rooms: new pack downloads (Lovely Living Room / Playful Bedroom), wallpaper/floor additions,
  and buyable Tiny Treats variants deferred.
- Recap: share image, authored captions, and extra beat-confetti deferred.
- UI: portrait gate and automated browser tap-audit deferred; pause-scrim-to-resume cut.

## 5. Hard budget guardrails (corrected)

### Image payload

- Total new V6 raster payload: **≤4.2 MiB** (was 3.0 — raised solely for the +36 sticker ruling:
  0.5 patterns + 0.128 covers + ≤3.4 stickers ≈ 4.03).
- Theme patterns: 11 indexed 512×512 PNGs, **≤48 KiB each and ≤512 KiB aggregate**; `acui/` stays
  far under its 2.5 MiB cap (measured today: 0.35 MiB).
- New game covers: exactly 2 indexed 512×384 PNGs, **≤64 KiB each / ≤128 KiB aggregate**; the
  `gameCovers.test.js` **2.3 MiB total pin is NOT raised** (measured: 2,134,527 B + 2×64 KiB
  fits with ~146 KiB to spare).
- New stickers: exactly **36** indexed 512×512 PNGs, **≤96 KiB each / ≤3.4 MiB aggregate**. Raise
  only `FEATURE_CAPS_MB.stickers` from **7.5 to 10.0 MiB** (measured base: 6.31 MiB → worst case
  9.7); retain the 150 KiB legacy per-file ceiling and add the 96 KiB V6-file assertion.
- No new recap/vacation/park-map/photo-frame images; reuse committed recap art and 3D packs.

### Rendering and motion

- Home steady state: **≤100 draw calls, ≤40k triangles** (measured baseline ~71/27k); ambient
  foundation **≤+4 calls/room** and room rebuild **≤+4 calls/room** over measured pre-wave state.
- Park hub: **≤120 calls, ≤75k triangles — including the F4 wheel (~+6 calls)**. Coaster scene:
  **≤90 calls, ≤60k triangles**.
- Recap: retain **≤150 calls per vignette**, re-measured after landscape widens culling.
- New arcade games: **≤100 calls each**; no per-frame allocations in update paths.
- UI: one ambient pseudo-layer per screen, transform+opacity only, 80–120 s drift, no filters,
  backdrop-filter, background-position animation, or steady JS animation loop.
- Repeated GLBs use instancing/atlas batches; every directional asset is bounds-grounded and has
  a forward rule. Zero room/park overlap warnings is mandatory.

### Persistence/economy

- Postcard archive cap **36 entries**; cutscene seen map and park counters contain only known ids.
- No `SAVE.VERSION` bump; no retroactive grants; no unbounded arrays.
- No coaster/wheel payout or ticket/stamp economy. Vacation prices, 24-hour window, taxi fee,
  full stat reunion, and all existing minigame scoring tables remain frozen.

## Changes vs EVAL

1. **F1 stickers +24 → +36 (48→84, 8→14 pages).** The evaluator's cut to +24 was scope taste, not
   technical necessity; the user's ask is the plan's most explicit priority. Payload verified safe
   (cap 7.5→10.0 MiB, app-level budget untouched); art risk bounded by choosing the extra 12 from
   existing-signal rules only and keeping the mandatory same-bunny review gate. The genuinely
   risky rule classes (seasonal windows, self-count stickers, page rewards, new secrets) stay cut.
2. **Restored the Riesenrad as new agent F4** (EVAL SHIP-LATER): serves priority 1
   (Achterbahnpark as a place, not one ride), fully procedural, zero save/economy surface,
   counter-rotation unit-tested, fits the existing ≤120-call hub budget. Scheduled in Wave F so
   the hub (E1) is proven first; its parkScene/parkBuilder edits collide with no Wave-F agent.
3. **Restored petal-wipe + soft-settle** (EVAL deferred) split by ownership: canvas petal wipe →
   F2 (`loadingVeil.js`), settle bezier → F3 (`styles.css` owner). Serves priority 9 on the
   most-seen surface; reuses the existing iris-wipe/reduced-motion plumbing.
4. **Fixed E4's file list:** `test/decor.test.js` does not exist (verified); replaced by the real
   gates (`test/roomAudit.test.js`, `test/rooms.test.js`, regenerated bounds fixture).
5. **Extended the appendix hand-off rule to every wave** (EVAL specified only B and D): A1→A2,
   B3→B2, C4→C3, E3/E2→E1, F1 self-owned. Each new `strings/v6-*` module's import pair into
   `strings.js` is committed by that wave's `strings.js` owner.
6. **Pinned Wave-D internal merge order D1→D2→D3→D4:** D4's zero-emoji audit gate cannot pass
   until D3's icon replacements are merged — an intra-wave dependency EVAL left implicit.
7. **Made E1↔E2/E3/F4 integration exports explicit** (`startCoasterRide`, `mountParkDressing`,
   `openParkStall`, reserved `ferrisWheel` anchor) — E1 owns `parkScene.js`, so tap-wiring against
   frozen exports is the only collision-free integration path.
8. **Hardened F1's acceptance:** conditions must be pure reads of existing slices (D2 archive, E1
   park counters, minigame slice) with no new fire sites; page expansion is append-only positional
   slicing (no re-home of the frozen 48); page-rail CSS pinned to `ALBUM_CSS` in `albumScreen.js`
   because `styles.css` belongs to F3 in Wave F (verified: the Stickerbuch styles are injected,
   only 3 `g34-sb` rules live in `styles.css`).
9. **Added a pattern-budget assertion to A2's test** (≤48 KiB/tile, ≤512 KiB aggregate) so the
   guardrail is machine-checked, not prose.
10. **Corrected budget totals** for the sticker ruling (new-raster ≤4.2 MiB; stickers cap
    10.0 MiB) and annotated the cover/sticker pins with the re-measured byte truths.
11. **C3 unlock levels confirmed against the real schedule** (L6/L7 already host games — L2 and
    L5 precedents make co-located gates fine) and the `ALL_ARCADE_GAMES` hard-coded literal edit
    called out explicitly.

## Risk register (top 8)

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Recap landscape rotation breaks renderer sizing on iOS WebKit** (shared canvas, B1) — a missed restore path portrait-locks the whole game | JS-px vars (never `100vh/vw`); size swap only behind the entry/exit whites; restore asserted on finish/skip/error in tests; letterboxed portrait fallback kept as the reduced-motion path; §A2 beat probe (≤80 ms) re-run on the full L10 preview |
| 2 | **Sticker art consistency at +36** — 36 generated images must read as the same bunny/style | Master BASE prompt (idea 05 §d); 2–3 candidates per sticker; batch same-bunny human review is a merge gate; PNG-8 ≤96 KiB enforced by test; the 12 added stickers ride existing signals so a rejected image never blocks engine work |
| 3 | **Emoji purge false positives / ordering** — a blind codepoint ban hits comments, DE prose, a11y glyphs; the gate lands before consumers are clean | Audit parses rendered code/strings only; explicit allowlist (OS notification bodies, `bubblePop` geometry); D-wave merge order pinned D1→D4; later waves (E/F) are policed automatically by the same test |
| 4 | **Game-count pin choreography (C3)** — 17 test files + `modifierEngine.js` literal must move atomically or CI is red mid-wave | Single-commit rule for all pin moves; `test/minigamesV6.test.js` cloned from the V5 shape; covers quantized ≤64 KiB BEFORE the art pass so the 2.3 MiB pin never needs raising |
| 5 | **Cutscene camera/overlay deadlocks** (A1/D1) — three camera writers on the home scene; a stuck overlay soft-locks the game | Camera lease with snapshot+`finally` restore; refuse during pan/sleep/switch; watchdog 45 s; mandatory tapWait timeouts; `keepOnSkip` ops applied on skip; music push/pop balanced in `finally` |
| 6 | **Park scene budget + coaster socket math** (E1/E2/F4) — clipping/perf regressions in the flagship new place | Pure layout tests: zero footprint overlaps, socket joins ≤1 mm, gondola counter-rotation unit-tested; draw-call ledgers measured on the VM per band; separate scene graphs (plaza not rendered during the ride) |
| 7 | **Additive save-slice normalization traps** (D2 postcards, E1 park, cutscene seen-map) — `sliceOf` whitelists fields; a missed normalizer silently drops data | Every additive field lands in `defaultSlice`/`sliceOf`/transition helpers with junk + offline round-trip tests; archive capped at 36; counters restricted to known ids; no `SAVE.VERSION` bump anywhere |
| 8 | **Hot-file churn across waves** (`shopScreen.js` B3→D3→E3; `albumScreen.js` B3→D4→F1; `airportScreen.js` B2→D1) — merge conflicts and regressions between waves | Waves are strictly sequential with the iOS/.ipa CI green gate between them; marked blocks per agent; each wave's owner table is exclusive; screenshots re-taken by the LAST touching agent of each screen |
