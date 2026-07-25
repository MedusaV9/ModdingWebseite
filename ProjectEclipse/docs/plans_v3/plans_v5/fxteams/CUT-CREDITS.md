# FX Team — CUT-CREDITS (round: next-level pass)

Team process per beat: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: `cutscenes/credits_helm.json`, `ritual/CreditsSequence.java` (presentation
beats only), `client/credits/` (`CreditsPanel`, `TitleCardLayer`, `CreditsAutoRun`,
`CreditsClient`), plus the C15 white-loading gag in
`client/loading/EclipseLoadingScreen.renderCreditsWhite` (owned by this beat).

Hard rules this round: the C15 **phase machine, tick table, flow and close mechanics are
FROZEN** — every change is presentation (envelopes, sub-beat scheduling through the
existing `schedule()` scheduler, camera JSON, client render layers). Wire formats
(`CreditsPayloads`, `S2CScreenFadePayload`, `S2CCaptionPayload`) untouched. No new lang
keys (langdrop protocol not needed — verified below). Self-checks: sandbox
`javac --release 21 -proc:none` (moddev merged jar + Veil 4.3.0 + geckolib 4.9.2 +
voicechat-api 2.6.20 + molang-compiler + `clientLegacyClasspath.txt`,
`-sourcepath src/main/java`), `python3 -m json.tool` + a real `CutscenePath.parse`
harness on the reshot JSON. No gradle, no git.

`credits_helm.json` reshoot bookkeeping: the pre-edit SHA-256
`d1534925895f730513eda34d6ee070dcc795c97828727be764926581490576df` was appended to
`CutscenePaths.LEGACY_DEFAULT_HASHES` (the existing stale-default upgrade mechanism), so
untouched operator copies of the old shot upgrade in place. **NOTE: `Map.of()` in that
table is now at its 10-pair limit — the next reshoot must migrate it to
`Map.ofEntries()`.**

`day_final.ogg` measured via ffprobe: **127.4 s (2548t)** — far longer than the credits
span (the cue starts at t=300; the client dies at t≈1105, 40.25 s in). Conclusion for the
finale beat: there is no track *end* to sync to — the music-sync job is the **fade-out**,
not the timeline (see Beat 7).

---

## Beat 1 — helm push-in (`credits_helm.json` + wheel prop)

### PLAN
The opener should feel like a held breath: a slower dolly that ends INSIDE the moment —
wheel in the near field, survivor behind it — with an FOV squeeze that tightens as we
arrive, and one tactile beat (the hands settling on the wheel) so the pose reads as a
person, not a statue. 140t duration is FROZEN (t=40..180 + 20t handback before the
whiteout is a machine contract).

### IDEATE
1. **4-key slow dolly** — replace the 3-key rush with a 4th late keyframe so the final
   22% of the flight is a near-static settle (arc-length reparam makes extra keys safe).
   **CHOSEN**
2. **FOV 66→63→60→58 intimacy squeeze** — end at 58 (was 52: too tele, flattened the
   wheel against the player); most of the squeeze spent across the back half. **CHOSEN**
3. **Wheel foreground framing** — end pos `[2.9, 1.85, -1.35]`, lookAt drifting to the
   hands-on-wheel point `[0.85, 1.35, 0]`: the wheel (anchor offset `[1.1, ~1.5, 0]`)
   sits ~6.6° right of the player bearing at FOV 58 — near-field frame-right, face
   behind-left. **CHOSEN**
4. **Hands-settle wheel micro-anim** — the wheel block display takes a −9° interpolated
   grip turn at run tick 148 (path t≈0.78, as the dolly arrives) and relaxes to −6.5° at
   160; the t=0.65 "wheel" whisper retimed to 0.72 to land ON the settle. **CHOSEN**
5. **Caption retime** — keep both existing whisper keys (no new lang), shift only the
   second one (0.65 → 0.72). **CHOSEN**
6. **Slow roll (dutch) into the final frame** — ±1.5° roll for drift. **REJECTED** —
   roll on a near-static settle reads as drunk camera, not intimacy; the shot's calm IS
   the point.
7. Spawning block-display "hands" on the wheel rim. **REJECTED** — fake limbs next to a
   real player model read as horror, wrong genre for the epilogue.
8. Third whisper caption on arrival. **REJECTED** — needs a new lang key (langdrop
   round-trip) for a line the silence delivers better.

### IMPLEMENT
- JSON reshoot (4 keyframes, fov 66/63/60/58, lookAt drift `[0.6,1.4,0]` →
  `[0.85,1.35,0]`, wheel caption at t=0.72, `params._comment` documents the new
  language). Duration/flags/fade-open untouched.
- `CutscenePaths.LEGACY_DEFAULT_HASHES` += the pre-edit `credits_helm` hash (mechanism
  comment + `Map.of` capacity warning).
- `CreditsSequence`: wheel transform factored into `wheelPose(spinDegrees)` (the
  translation counter-rotates the half extent, so it must be recomputed per spin);
  `nudgeWheel(owner, deltaDegrees, overTicks)` pushes an interpolated pose, no-op when
  the run ended or the wheel is gone; `beatShip` schedules the settle via the existing
  scheduler at `WHEEL_SETTLE_AT/WHEEL_RELAX_AT` (148/160) − `T_SHIP`.

### POLISH 2
- **Guard audit:** `skip()` and `beatEpilogue` both discard the wheel before the nudges
  could fire late — `nudgeWheel` checks `run != owner || wheel == null || isRemoved()`,
  so a mid-shot skip can never resurrect a transform push on a discarded display.
- Framing math re-checked: horizontal separation wheel↔player from the final camera is
  ~6.6° (old shot: ~4.4°) — more lateral layering than before, no occlusion of the face.

### POLISH 3
- `CutscenePath.parse` harness on the reshot JSON: 4 keyframes, 3 events, all lookAt
  point-arrays parse, both caption ids are dot-keyed translation keys (the
  `warnLiteralCaptions` shape check passes). FX replay `HELM` needs no mirror — replays
  spawn no entities by R12 contract, so the wheel nudge correctly does not exist there.

---

## Beat 2 — white fade + disguised loading (t=200/230)

### PLAN
The whiteout is cover for a teleport disguised as a loading screen — the gag lands
harder the more boringly *real* the fake load behaves. Two jobs: make the white
envelope musical (its release should hand the frame to the sunrise exactly as
`day_final` starts), and make the fake progress line behave like a real terrain load.

### IDEATE
1. **Whiteout retime 30/40/20 → 36/44/20** — gentler rise, and the release now ends at
   exactly t=300 = `T_BEACH`: white finishes dying the same tick the music starts.
   **CHOSEN**
2. **Typing ellipsis on the fake line** — strip the translation's own trailing "…"
   and re-type 1→3 dots on a 500 ms cadence (locale-safe: works for the en "…" and the
   de " …" endings without new keys). **CHOSEN**
3. **Deadpan percent stall** — the exp-creep percentage freezes for 1.2 s at ~62% (the
   curve's value at the 2.5 s window) then resumes, monotonic by construction — real
   loads hitch mid-way; comedy is in the verisimilitude. **CHOSEN**
4. **reducedFx = fully static variant** — both animations dropped, plain translated
   line, no percentage (extends the existing reducedFx behavior). **CHOSEN**
5. Fake "Not responding" title-bar flicker. **REJECTED** — breaks the fiction (MC loads
   don't do that), and a flicker is exactly what reducedFx users opted out of.
6. Glitch slabs bleeding into the white (the black-variant language). **REJECTED** —
   the controller deliberately suppresses slabs for `STYLE_CREDITS_WHITE`; the gag is a
   *clean* white load, corruption would out the trick.
7. Percentage counting DOWN once past 99. **REJECTED** — funny once, but it breaks the
   "is this real?" doubt that sells the disguise.

### IMPLEMENT
- `beatWhiteout`: `S2CScreenFadePayload(36, 44, 20, 0xFFFFFFFF)` (javadoc documents the
  t=300 landing).
- `EclipseLoadingScreen.renderCreditsWhite`: typing ellipsis via new
  `stripTrailingEllipsis` helper + `".".repeat(1 + (elapsed/500) % 3)`; percent runs on
  `effective = elapsed<2500 ? elapsed : elapsed<3700 ? 2500 : elapsed−1200`; reducedFx
  short-circuits to the static line.

### POLISH 2
- Cover-gap audit: portal white overlay reaches full cover at ~t=245 (ENTER t=230 +
  500 ms no-op glitch phase + 250 ms fade); the screen-fade white holds 236→280 and
  releases 280→300 — the two whites always overlap, the reveal is owned by the portal
  fade-in as designed. Replay `WHITEOUT` keeps its own values (it has no beach to sync
  to).
- Stall continuity: `effective` is continuous at both boundaries (2500→2500), so the
  percent can never jump backward.

### POLISH 3
- Both lang values checked (`gui.eclipse.loading.credits_fake` en+de) — the stripper
  handles "…", '.', and trailing spaces, so no locale double-dots. Javadoc updated.

---

## Beat 3 — beach reveal + auto-run (t=300)

### PLAN
The reveal currently does everything at once (music + roll + forced walk on the same
tick). Let it breathe: 2 s of everyone standing still on the frozen-sunrise horizon
before the march starts, the credits panel arriving only after 3 s, and a barely-there
breathing camera once the walk is on. The nudge watchdog must not fight the intentional
stillness.

### IDEATE
1. **2 s auto-run hold** — `beatBeach` sends music+roll on schedule but arms the walk
   via the existing scheduler 40t later (`RUN_HOLD_TICKS`); expiry budget rebased so the
   failsafe margin is unchanged. **CHOSEN**
2. **Watchdog grace** — `nudgeStalledRunners` gate moves from `t > T_BEACH` to
   `t > T_BEACH + RUN_HOLD_TICKS`: statues are intentional until the run is armed.
   **CHOSEN**
3. **Panel 3 s fade-in** — `CreditsPanel` holds invisible for 60t, fades in over 20t
   (scrim + text ride one alpha), and the scroll clock starts after the delay so no
   lines are lost; short rejoin rolls (≥40t) skip the delay entirely. **CHOSEN**
4. **Breathing camera sway** — ±0.55° sinusoidal pitch at a 64t period, injected as a
   per-tick DIFFERENTIAL (only the delta between consecutive sine samples), so player
   look input passes through untouched and the offset self-cancels every period;
   reducedFx skips it (motion). **CHOSEN**
5. **Sway under the walk bob, not replacing it** — vanilla input injection already buys
   head bob + footsteps (the reason auto-run is input, not velocity); the sway is a
   second, slower layer. **CHOSEN (design constraint)**
6. Hold implemented client-side inside `CreditsAutoRun`. **REJECTED** — the server
   watchdog would nudge "stalled" players 20t into the deliberate hold; the hold must be
   server-authoritative or the two systems fight. (This rejection *forced* ideas 1+2.)
7. Footstep-synced bob amplification (scale the bob per step). **REJECTED** — vanilla
   bob is attached to walk distance, amplifying it needs a render hook outside this
   cluster; the slow sway reads better anyway.
8. Panel lines typewriting in per-row. **REJECTED** — 31 rolling lines × typewriter =
   visual noise next to the sunrise; the roll's calm scroll is the identity.

### IMPLEMENT
- `CreditsSequence`: `RUN_HOLD_TICKS = 40`; `beatBeach` schedules the arm (guarded:
  `run != current || ticks >= T_FADE_OUT` — a skip during the hold never arms the walk),
  `maxTicks` rebased (`T_FADE_OUT − T_BEACH − RUN_HOLD_TICKS + 100`); watchdog gate
  moved; class-javadoc timeline updated (auto-run at t=340).
- `CreditsPanel`: `FADE_IN_DELAY_TICKS = 60`, `FADE_IN_TICKS = 20`; delay applies only
  when `duration > delay + 2×fade`; progress remaps to `(age−delay)/(duration−delay)`;
  scrim steps (28/56/84/110 alpha) and text all multiply the fade alpha; `< 8` text
  alpha skipped (drawString treats ~0 as opaque).
- `CreditsAutoRun`: `swayOffset(tick)` sine, differential application before the ±35°
  pitch clamp, `swayTicks` reset per arm, reducedFx-gated; javadoc documents the layer.

### POLISH 2
- **Rejoin audit:** `onLoggedIn` mid-run still arms immediately (a rejoiner during the
  40t hold walks up to 2 s early — accepted: vanishingly rare, harmless, and the
  broadcast beach beat still reaches them).
- Sway drift bound: toggling reducedFx mid-walk can strand ≤ 0.55° of offset (the
  differential stops mid-period) — imperceptible, self-corrects on the next arm.

### POLISH 3
- Timeline math: roll = 700t → delay 60 + fade 20 + travel 640 — the block still fully
  exits before the ECLIPSE card (same end tick, slightly faster scroll: +9%).
  `EclipseUiTheme.TEXT/DIM` masked to RGB before re-alphaing (they ship 0xFF alpha).

---

## Beat 4 — lightning + block-display flyover (t=420–560)

### PLAN
Six strikes at near-identical range read as a loop; 24 fullbright floating blocks read
as decoration. Give the storm depth (near-far staggering with physically-late thunder)
and give the debris weight (backlit dark tint + moving ground shadows under the low
arcs). All server-side world presentation — deterministic, replay-consistent, discarded
by the same lifecycles.

### IDEATE
1. **Near-far depth ladder** — deterministic per-index distances past the surf line
   `STRIKE_DEPTHS = {64, 10, 34, 78, 16, 6}`, sides alternating: far–NEAR–mid–FAR–near–
   NEAREST, so the intensity ramp (0.6→1.0) peaks on the closest strike. **CHOSEN**
2. **Speed-of-sound thunder** — the flash (FX event + visual-only bolt) stays immediate;
   the thunder arrives `1 + depth/17` ticks late (~17 blocks/tick), far strikes lose top
   end (×0.72 volume, 0.72 base pitch vs 0.9 near). Uses the existing scheduler, guarded
   on `run` liveness. **CHOSEN**
3. **Dark underside tint on the debris** — display brightness override sky 7 / block 4:
   the fragments read as backlit silhouettes against the sunrise. `setBrightnessOverride`
   is private in 1.21.1, so the override rides the entity's own save NBT
   (`saveWithoutId` → put `brightness{sky,block}` → `load`) — the vanilla data path, no
   reflection. **CHOSEN**
4. **Shadow pucks under the low arcs** — flyers with the low apex roll (`hash01(i,2) <
   0.5`, ~12 of 24) get a flattened (0.045 y-scale) tinted-glass display riding the sand
   at `BEACH_Y+1.03`, mirroring the flyer's horizontal travel (same speedJitter/u/xOff
   hash math), footprint swelling +50% at apex, counter-spinning at 30% tumble rate;
   east travel clamped to the sand strip (`maxDx = sandEast − 2 − apexX`) so no shadow
   floats on open water. Same `FLYER_TAG` (stray sweep), same animate/discard lifecycle.
   **CHOSEN**
5. **Replay mirror** — `replay("LIGHTNING")` gets the same depth ladder + late thunder
   (impacts synthesized per watcher as before). **CHOSEN**
6. Vanilla entity shadows via `shadow_radius` NBT. **REJECTED** — display shadows render
   at the ENTITY position, and the flyers move via transformation translation from a
   fixed apex anchor: the shadow would sit still while the block flies. (This rejection
   forced idea 4's explicit pucks.)
7. Extra strike count / second volley. **REJECTED** — `LIGHTNING_STRIKES`/interval are
   tick-table constants of the frozen machine; depth does more than density.
8. Per-flyer trailing particle streaks. **REJECTED** — the epilogue has no FxBudget
   channel wired for it and the debris IS the spectacle; smoke would smear the sunrise.

### IMPLEMENT
- `beatLightningStrike`: depth ladder + `hash01` jitter for x/z (no more
  `epilogue.random` — strikes are now deterministic per index like the flyers), FX event
  + bolt immediate, thunder scheduled late/low/quiet; javadoc rewritten.
- `spawnFlyers`: `applyBrightnessOverride(flyer, 7, 4)` + `spawnShadowPuck` for low
  arcs; `Run.shadows` (`ShadowPuck(display, index, maxDx)` record); `animateFlyers`
  pushes `shadowPose` on the same 2t cadence; `discardFlyers` clears both lists;
  spawn log line reports both counts.
- Replay `LIGHTNING` mirrored (flash schedule + separate thunder schedule per strike).

### POLISH 2
- **Determinism audit:** every random the beat used is now `hash01(index, salt)` — a
  replayed strike/arc/shadow always agrees with itself and with re-pushes (the
  FloatingDecor doctrine the flyers already followed).
- Clamp check: apex x ∈ ~[19, 49] for a t=420 runner center → `maxDx` 45..75 vs. max
  east travel 40 — the clamp only engages for the farthest-east low arcs, exactly the
  water-adjacent cases it exists for. West travel bottoms at ~−21 > beach west rim −24.

### POLISH 3
- Budget: +≤12 displays (36 total live for ≤140t), one extra transform push per puck
  per 2t inside the existing loop, zero new per-tick allocation outside spawn. NBT
  round-trip happens once per flyer at spawn (24×, off the hot path). Thunder volume
  peaks at 1.2 like before (vanilla clamps); far strikes are QUIETER — never louder than
  the shipped beat.

---

## Beat 5 — DOOMSDAY card decode (t=480, `TitleCardLayer`)

### PLAN
The decode locks characters in silently-uniform TEXT color — the reveal wave is only
audible (typewriter blips), not visible. Make each lock *land*: per-letter gold resolve,
and one bass-synced flash frame when the full title snaps true (the `timerZero` boom).
Photosensitivity: the flash frame is precisely what `reducedFx` exists for.

### IDEATE
1. **Per-letter gold resolve** — each char draws GOLD the tick it locks
   (`lockTick(i) = PRE_TICKS + (i+1)·TICKS_PER_CHAR`, analytic — no extra state) and
   cools to TEXT over 5t; the existing whole-string lock flash rides on top via `max()`.
   **CHOSEN**
2. **Bass-sync flash frame** — a 2-tick, 0.22-alpha white full-frame pop starting the
   exact tick the title completes (same tick `timerZero` fires — the boom IS the bass).
   `reducedFx` drops it entirely. **CHOSEN**
3. **Per-char draw loop** — locked prefix rendered glyph-by-glyph with accumulated
   `font.width` advance (identical metrics to the string draw — vanilla font has no
   kerning), noise tail keeps its single draw. **CHOSEN (enabler)**
4. **Keep GlitchText noise/space preservation untouched** — the word-shape read through
   corruption is already the best part. **CHOSEN (constraint)**
5. Per-letter 1px drop/settle jitter on lock. **REJECTED** — vertical jitter at 2.0
   scale reads as broken baseline, and motion leaks past the reducedFx contract that
   this layer's decode is "calm static" there.
6. Chromatic split (red/cyan ghost) on the locking char. **REJECTED** — the glitch
   language of rift/border FX; the credits card is gold/warm by design (boss-card
   palette swap doctrine).
7. Screen shake on full lock. **REJECTED** — shake belongs to the t=650 burst; two
   impacts 8.5 s apart cheapen both.
8. Bass flash as a band-only (not full-frame) flash. **REJECTED** — the band already
   flashes via the hairlines; the single full-frame pop is the "subwoofer hit" and at
   0.22 alpha × 2 ticks it stays tasteful.

### IMPLEMENT
- `CHAR_FLASH_TICKS = 5`, `BASS_FLASH_TICKS = 2`, `BASS_FLASH_ALPHA = 0.22F`; per-char
  loop with `Math.max(charFlash, lockFlash)` gold lerp; flash frame drawn last, gated
  `!reduced && t >= decodeEnd && locked >= title.length()`; class javadoc documents both
  (and the reducedFx behavior). Dead `lockedPart` local removed.

### POLISH 2
- **Partial-tick audit:** `locked` derives from integer ticks while color uses
  `t = ticks + partial` — for every locked char `t ≥ lockTick(i)`, so `charFlash` can
  never exceed 1 or flash prematurely; the newest char is always full gold on its lock
  frame.
- Auto-shrink interplay: the per-char advance uses the same scaled pose as before, so
  long-title shrink (the 92% fit rule) is unaffected.

### POLISH 3
- reducedFx ladder recap for this layer: calm static (existing) + no hairline breathing
  (existing) + no bass flash (new); the per-letter resolve is pure color and stays — it
  *adds* readability, which is the accessibility direction.

---

## Beat 6 — burst + correction card (t=650/665)

### PLAN
"ECLIPSE : DOOMSDAY" is the punchline of the whole finale; a punchline needs dead air in
front of it. Today the correction card fades up while the burst flash is still dying
(flash 650–674 vs. card 665). Choreograph: tight flash → 500 ms of NOTHING → card.
Phase timing (`T_CORRECTION`, phase enter) is machine — only the payload dispatch moves.

### IDEATE
1. **Tighten the burst flash 8/6/10 → 6/4/6** — screen fully clean at t=666 (was 674);
   the shockwave FX carries the impact, the flash is punctuation. **CHOSEN**
2. **500 ms stillness** — phase `CORRECTION` still enters at t=665 (persisted phase
   string, restart contract untouched); the caption payload is dispatched via the
   scheduler +11t → lands t=676, exactly 10t (500 ms) after flash-out. **CHOSEN**
3. **Guard the held card against `skip()`** — a skip during the stillness moves the run
   to the outro; the scheduled dispatch checks `run != current` and drops. **CHOSEN**
4. **Replay mirror** — `replay("CORRECTION")` fires flash and card together today;
   mirrored as flash at 0 (dies 16t) + card at 26t = the same 10t of dead air. **CHOSEN**
5. **Keep the card on `CaptionRenderer` TITLE** — the deadpan lives in the caption
   system's dry track-in; a custom "correction" layer would over-sell the joke (the
   TitleCardLayer javadoc already promises TITLE stays untouched for this card).
   **CHOSEN (constraint)**
6. A second tiny flash as the correction lands. **REJECTED** — the correction is the
   anti-spectacle beat; light on it kills the deadpan.
7. Typewriter/decode treatment for the correction text. **REJECTED** — same reason; it
   must appear like paperwork, not like tech.
8. Longer stillness (1 s+). **REJECTED** — 20t of nothing after a burst starts reading
   as a bug, not a beat; 500 ms is the classic double-take gap.

### IMPLEMENT
- `CORRECTION_STILL_TICKS = 11` (documented: flash dead at 666, card at 676);
  `beatBurst` envelope 6/4/6; `beatCorrection` schedules the guarded broadcast;
  replay `CORRECTION` mirrors (6/4/6 + card at 26t); class-javadoc timeline updated.

### POLISH 2
- **Replay arithmetic re-checked and fixed:** the first mirror used
  `CORRECTION_STILL_TICKS + 5` = 16t — that's ZERO stillness (flash also dies at 16t
  when both fire together, since the replay has no 15t phase offset). Corrected to a
  literal 26t with a comment deriving it.

### POLISH 3
- Restart contract audit: the persisted phase still flips to `CORRECTION` at t=665; a
  crash inside the 11t hold skips to the end state like any other beat (the scheduler
  clears on server stop) — the held payload can never fire into a recovered world.

---

## Beat 7 — fade + music finale + close (t=745–1205)

### PLAN
Today the client dies mid-phrase: `day_final` is 127.4 s long (ffprobe), the stop lands
40.25 s in, and `Minecraft.stop()` guillotines the audio. Also the ECLIPSE card (90t
hold from t=1010) is still fading when the close executes at t≈1105 — there is no "pure
black" moment. Choreograph the last five seconds: card out early → 1 s of true black →
faint heartbeat → silence → stop.

### IDEATE
1. **Music-synced fade-out at close** — `CreditsClient.handleClose` (after all three
   close guards pass) calls `MusicCues.stop()`: the client crossfade
   (`MusicManager.FADE_TICKS = 40`) exactly matches the 40t close countdown, so the
   music reaches silence the tick the window dies — a fade *curve* synced to the close,
   which is the only meaningful sync against a 127 s bed. **CHOSEN**
2. **ECLIPSE card 90 → 75** — fully out by t≈1085; with the stop at t≈1105 that buys the
   1 s of pure black. Server-side presentation constant; replay OUTRO mirrored.
   **CHOSEN**
3. **Faint heartbeat under the black** — two `WARDEN_HEARTBEAT` UI thumps at countdown
   20 and 12 (0.4/0.3 volume, 0.7/0.62 pitch — a slowing, fading heart), gated by the
   existing `heartbeatSound` accessibility toggle (the B12 opt-out the storm/low-lives
   systems already respect). **CHOSEN**
4. **Rehearsals keep their music** — skip/rehearsal runs never receive the close
   payload, so the fade + heartbeat correctly never fire there; the situation ladder
   keeps owning `day_final` (it is a situation rung). **CHOSEN (falls out of guards)**
5. Fading the music server-side at `beatFadeOut` (t=745). **REJECTED** — the design doc
   is explicit ("the music finale keeps playing" through the black + home hop + ECLIPSE
   card); only the last 2 s before death belong to silence.
6. Retiming the t=745 black fade to a bar grid of the track. **REJECTED** — the bed is
   ambient dread (no hard grid to land on), and T_FADE_OUT is tick-table/flow.
7. Heartbeat via positional `playLocalSound`. **REJECTED** — the player is over black in
   an arbitrary dimension; `forUI` is the only spatially-honest channel left.
8. A final breath/exhale foley after the heartbeat. **REJECTED** — no shipped asset,
   and the ledger has no `ui.breath` event; the heartbeat alone is the "you're still
   alive" stinger.

### IMPLEMENT
- `CreditsClient`: `MusicCues.stop()` on close scheduling (log updated); heartbeat
  thumps at `HEARTBEAT_FIRST_AT/SECOND_AT` (20/12) in the countdown tick, gated by
  `EclipseClientConfig.heartbeatSound()`; class javadoc gained the close-choreography
  paragraph.
- `CreditsSequence.beatEclipseCard`: hold 75 (javadoc explains the pure-black second);
  replay `OUTRO` card mirrored to 75.

### POLISH 2
- **Guard-order audit:** `MusicCues.stop()` sits AFTER the nonce/singleplayer/
  `allowFinaleClose` early-returns — a rehearsal client or a nonce-mismatched joiner
  never has its music ladder muted by a stray close payload.
- Countdown edge: the heartbeat checks run after the `--closeCountdown == 0` stop path
  returns, so a 1-tick delay payload can never thump post-stop.

### POLISH 3
- Timeline: card visible 1010→1085 (75t incl. the TITLE 15t fade-out), heartbeats at
  ≈1085/1093, music silent + window dead at ≈1105, dedicated halt at 1205 — every value
  inside the frozen tick table; only payload contents moved. reducedFx: heartbeat is
  audio (owned by `heartbeatSound`, not `reducedFx`) — correct split per B12.

---

## Round summary (all beats)

| Beat | Files touched | Self-check | Cost added |
|---|---|---|---|
| 1 helm | `credits_helm.json`, `CutscenePaths`, `CreditsSequence` | json.tool + `CutscenePath.parse` harness + javac ✅ | 2 scheduled wheel pushes |
| 2 white/loading | `CreditsSequence`, `EclipseLoadingScreen` | javac ✅ | string ops on the load screen only |
| 3 beach/auto-run | `CreditsSequence`, `CreditsPanel`, `CreditsAutoRun` | javac ✅ | 1 scheduled arm; 1 sine/tick client-side |
| 4 lightning/flyover | `CreditsSequence` | javac ✅ | ≤12 displays ≤140t; 6 scheduled thunders; 24 one-time NBT round-trips |
| 5 DOOMSDAY card | `TitleCardLayer` | javac ✅ | per-glyph draw loop (~48 glyphs, GUI) |
| 6 burst/correction | `CreditsSequence` | javac ✅ | 1 scheduled caption |
| 7 finale/close | `CreditsSequence`, `CreditsClient` | javac ✅ | 2 UI sounds; 1 music-stop call |

- **Frozen surfaces untouched:** phase machine (`Phase` enum, persisted `CreditsData`,
  restart/skip/close contracts, the entire tick table), wire formats (all
  `CreditsPayloads` records, fade/caption payloads), `CaptionRenderer`,
  `PortalTransitionController` state machine, the nudge-watchdog mechanism (gate moved
  40t, algorithm identical), `Minecraft.stop()` path and its three client-side guards.
- **reducedFx ladder recap:** loading-gag ellipsis+percent → static line; auto-run
  breathing sway → off; DOOMSDAY bass flash frame → off (per-letter resolve stays,
  color-only); heartbeat → governed by `heartbeatSound` (B12 audio opt-out, the correct
  gate). Server-side world presentation (wheel nudge, debris tint, shadow pucks,
  thunder staggering) is not per-player gateable, matching the shipped flyers/strikes.
- **Caption/i18n audit:** every key referenced this round exists in BOTH lang files —
  `eclipse.credits.caption.helm/wheel`, `eclipse.credits.title.doomsday/correction/
  eclipse`, `gui.eclipse.loading.credits_fake`, `eclipse.credits.roll.1..31`. **Zero new
  lang keys** (no langdrop needed); both cutscene caption events are dot-keyed
  translation keys (loader literal-caption warning stays quiet).
- **Verification:** full-cluster sandbox `javac --release 21 -proc:none` (0 errors);
  `python3 -m json.tool` on the reshot JSON; a `CutscenePath.parse` harness (compiled
  against the cluster's own classes + gson) confirming 4 keyframes / 3 events / lookAt
  and caption shapes; `ffprobe` on `day_final.ogg` (127.4 s) backing the Beat-7 design
  call.

Note for sibling teams: `CutscenePaths.LEGACY_DEFAULT_HASHES` is now at `Map.of()`'s
10-pair ceiling (credits_helm joined this round) — the NEXT reshoot must migrate the
table to `Map.ofEntries(...)` before appending.
