# UIFEEL — celebration & feedback FX team log

Team process per component: **PLAN → IDEATE (6+) → IMPLEMENT → POLISH 2 → POLISH 3.**
Cluster: the celebration/feedback Quasar emitters (`quasar/emitters/`) + the client HUD
celebration layers that pair with them (visual polish only — no queue/dedup/network logic
touched).

**Laws honored everywhere:** `reducedFx` keeps its calm variants (all new motion —
overshoot, bounce, wobble, roll-up, confetti, flash ring — is gated off);
no screen flash was added beyond the existing photosensitivity envelope (the one new
flash element is a single non-repeating hairline ring at ray-level alpha over a ~40 px
area; `border_shard`'s flicker ENERGY went down, not up); no gradle/git — verification is
the sandbox `javac --release 21` harness (moddev merged jar + veil/geckolib/voicechat
classpath) + `python3 -m json.tool` on all 12 emitters + a corpus vocabulary cross-check
(touched emitters use only module ids/keys already present in untouched emitters).

House micro-structure rule applied to every celebration: **anticipation → impact →
settle.**

---

## 1. Bottom toast lane — `client/hud/BottomToastQueue` (+ `ShardGainToast`, `CollectionTierToast`)

**PLAN.** The shared lane owns timing/alpha/rise for every bottom pill/card. Goal:
entrance spring-ease with exactly 1 px overshoot, exit fade-slide, icon micro-bounce on
land. Constraint: queue mechanics (slots, FIFO, caps, lifts) untouched; `reducedFx` =
pure fade.

**IDEATE.**
1. ✓ Piecewise spring: rise from +3 px through −1 px overshoot over `IN_TICKS`, relax to
   0 over `SETTLE_TICKS` — exact 1 px overshoot by construction (an `easeOutBack` tuned
   to 1 px at 3 px travel is fragile at integer rounding).
2. ✓ Exit fade-slide: +4 px cubic ease-in drop under the existing out-fade (departs
   gaining speed = "released", vs entrance decelerating = "caught").
3. ✓ Icon micro-bounce: a shared `iconBounce(age)` helper — 1 px up-and-back sine hop
   starting the tick the spring lands, so the ◆/✦ "lands" one beat after the pill.
4. ✓ Age-aware `Toast.draw` overload (default delegates) so renderers can time flourishes
   without the queue leaking its constants.
5. ✗ Horizontal shimmy on entrance — fights the vertical lane metaphor, adds noise.
6. ✗ Scale pop on the whole pill — text scaling below 1.25× rasterizes badly at GUI scale
   2; rejected for legibility.
7. ✗ Per-slot desynced springs (slot 1 lands late) — cute but reads as lag, not craft.

**IMPLEMENT.** `springOffset(t, hold)` replaces the linear rise (entrance spring +
settle + exit slide in one offset function); `iconBounce(float)` public helper (0 under
`reducedFx`); 6-arg `Toast.draw` default; ◆ (shard pill) and ✦ (tier card) ride the
bounce in their renderers.

**POLISH 2.** Rounding audit: offsets are `Math.round`ed once, no double-rounding drift;
the 5-arg fallback paths pass `Float.MAX_VALUE` age → bounce window closed → identical
settled render. Exit slide capped at `OUT_TICKS` progress 1 so a long-lived slot can't
keep sliding.

**POLISH 3.** Verified alpha floor guard (≤ 0.04 skip) still runs before any offset work;
`reducedFx` path re-checked = zero motion, fade only; hold lengths (36/50t) are both
longer than the 4t settle window so the spring always completes. Compiles clean.

---

## 2. `client/skills/LevelUpOverlay` — number roll-up + burst timed to the sting

**PLAN.** Give the level glyph the anticipation→impact→settle spine: the number should
ROLL to its value, and the `unlock_burst` world flourish should hit the sting's swell,
not lead it.

**IDEATE.**
1. ✓ Odometer roll-up: level counts up `ROLL_SPAN=4` steps during the 8t glitch-in with
   ease-out (last step slowest), landing exactly at the resolve beat.
2. ✓ Burst re-timed: `spawnOrFallback` moved from `start()` (t=0) to the tick driver at
   `t == GLITCH_IN_TICKS` — scramble+roll = anticipation, resolved glyph + burst =
   impact, breathing hold + underline = settle. The `ui.level_up` sting starts at t=0 and
   swells; 8t (400 ms) into it is its loudest region, so the flourish now lands on it.
3. ✗ Roll from level 1 — for level 18 the number would lie for too long; a 4-step roll
   reads as motion without misinforming.
4. ✗ Rolling digits per-column (slot-machine style) — needs per-digit layout; the font is
   proportional, layout would shimmer.
5. ✗ Second burst on milestone levels — milestones already layer a second sting; doubling
   the emitter risks the FxBudget BURST channel for no added read.
6. ✗ Scale punch on resolve — the milestone scale (2.5×) already owns "bigger"; a punch
   on ordinary levels would flatten that hierarchy.
7. ✗ Tie the roll to the hold phase — the hold is the settle; motion there fights the
   breathing glow.

**IMPLEMENT.** `ROLL_SPAN` constant + roll computed in `render` (final text everywhere
else — width math, scramble, underline all keyed off the shown string as before);
`impactBurst()` fired from the tick driver at the resolve beat; javadoc updated.

**POLISH 2.** Pause safety: tick driver early-returns while paused BEFORE the increment,
so the burst cannot be skipped over a pause boundary. Downward admin level-set and login
seed paths unchanged.

**POLISH 3.** `reducedFx` shows the final number only (no roll) and still skips the burst
entirely; `span=0` guard for level 1. Compiles clean.

---

## 3. Awards roulette — `client/awards/AwardsOverlay` + `RouletteStrip`

**PLAN.** (a) VERIFY the tick deceleration curve feels physical, refine if needed;
(b) winner flash + confetti-glyph burst. Checked for a Quasar hook first: the checked-in
`eclipse:roulette_flare` emitter is WORLD-space (camera-dependent — the existing
`renderFlare` javadoc already ruled it unusable behind a fixed overlay), so the confetti
is a screen-space draw, per the established precedent.

**IDEATE.**
1. ✓ Deceleration verdict: the position curve is ease-out-quart with exact-landing by
   construction (`pos(T) == distance`, travel solved for ≈55 heads/s at t=0). Quart ≈
   friction-with-drag decay — physically plausible; the weak point was that NOTHING in
   the frame reacted to the speed. Fix: make the marker needle feel the strip.
2. ✓ Needle lean: marker deflects up to 2.2 px WITH the leftward head sweep,
   proportional to `speedFraction` (the quart derivative `(1-u)^3`) — the needle visibly
   relaxes as the strip decelerates, which is what sells drag.
3. ✓ Land springback: 1.5 px decaying sine wobble over 6t after landing — the needle
   "catches" the winner.
4. ✓ Winner flash: one expanding hairline accent ring (8t, non-repeating, alpha ≤ 0.5,
   ~40 px area) layered under the existing flare grow — inside the photosensitivity
   envelope, no full-screen element.
5. ✓ Confetti-glyph burst: 14 deterministic particles seeded by the reveal salt (pure
   function of `landTime` — zero state, zero allocation): upward fan, per-particle
   speed/life, soft gravity arc, quadratic fade; even indices are font glyphs ✦ ◆ + ·,
   odd are 2×2 px motes, all in the shared warm→purple `FLARE_COLORS`.
6. ✗ Slow-motion final head-pass (time dilation on the last SPACING) — breaks the
   exact-landing math contract; the deterministic landing is load-bearing (every client
   shows the same show).
7. ✗ Extra tick sounds / land thunk — audio timing is show logic; out of visual-polish
   scope, and `tickPitch` already does the end-rise tension.
8. ✗ Confetti clipped to the strip band — the band scissor is 50 px tall and would
   decapitate the fan; clipped to the card panel instead so it bursts up over the title.

**IMPLEMENT.** `RouletteStrip.speedFraction(partialTick)` (documented as the quart
derivative); `needleDeflect(...)` + deflect param on `drawMarker`; flash ring in
`renderFlare`; `renderConfetti(...)` with its own card-bounds scissor, called only when
landed and not `reducedFx`.

**POLISH 2.** Added the font-renderer alpha floor guard (`fade <= 0.06` skip) — MC's font
snaps tiny alphas to opaque, which would have made dying confetti POP back in. Confetti
draw order set above heads (burst reads as in front), below the winner label row.

**POLISH 3.** `reducedFx` audit: pre-landed strips report `speedFraction == 0`, wobble and
confetti and ring all explicitly gated → the calm reveal card is pixel-identical to
before. Deterministic-show audit: confetti/needle read ONLY salt + landAge + partialTick,
so all clients still see the same show. Compiles clean.

---

## 4. `client/rewards/RewardMaterializeOverlay` — touchdown settle

**PLAN.** The materialization had anticipation (descent) and impact (absorb flash +
sting) but no physical settle — the stack froze the instant the descent lerp ended.

**IDEATE.**
1. ✓ Touchdown press: stack presses 2 px past the land line, sine-relaxing over 5t.
2. ✓ Scale pop: +0.1 scale riding the same settle window (squash-and-release, one knob).
3. ✗ Rotation wiggle — item stacks render axis-aligned; rotation reads as glitch.
4. ✗ Second flash on settle end — one flash per grant is the photosensitivity-friendly
   budget; the existing absorb flash stays the only one.
5. ✗ Hotbar slot highlight on land — touches vanilla HUD outside this layer's ownership.
6. ✗ Label spring — the label already glitch-settles; two springs at once is noise.

**IMPLEMENT.** `TOUCH_SETTLE_TICKS` / `TOUCH_POP_SCALE` constants; press + pop applied in
`render` for the live variant only.

**POLISH 2.** Verified the label (positioned off `itemY + 8*scale`) rides the press — the
whole assembly lands as one object rather than the label hovering.

**POLISH 3.** Calm/replay variant re-checked: no press, no pop, no flash, no sting —
untouched. Window is fully inside `FLASH_TICKS+HOLD_TICKS` so it can't leak into the
fade. Compiles clean.

---

## 5. `quasar/emitters/unlock_burst.json` — richer two-tone

**PLAN.** The celebration burst (level-up resolve beat, podium moment, announcement
unlock). Old gradient was a mush of 4 near-neighbors; the ask: a composed TWO-TONE.

**IDEATE.** 1. ✓ White-hot birth point (#FFFFFF at 0) so the first frames read as a spark
flash. 2. ✓ Warm chord held through 0.42 (#FFE9A8→#FFD166), then a CRISP seam to the
violet chord at 0.56 (#C77DFF→#8A5BE0→#5B3AA6) — two families, one deliberate handoff,
instead of a continuous smear. 3. ✓ velocity stretch 0.25→0.4 (directional bloom).
4. ✓ gravity 0.18→0.14 + lifetime 20→22 (longer violet hang = settle). 5. ✗ second
emitter for a ring layer — call sites spawn ONE id; a second emitter would double BURST
budget charges. 6. ✗ sprite swap — purple_wisp is the shared additive language of the
whole kit. 7. ✗ higher count — the burst plays at the player's feet mid-gameplay;
14→more would crowd the hotbar sightline.

**IMPLEMENT/POLISH 2/POLISH 3.** Gradient/physics values above; alpha re-shaped
1.0→0.9(0.35)→0.45(0.75)→0 — strictly monotonic decay (no re-flash). Seam percents
checked against the 6-tick lifetime variation so even short-lived particles cross the
seam. JSON valid; vocabulary check clean.

---

## 6. `quasar/emitters/roulette_flare.json` — richer two-tone

**PLAN.** World-space twin of the roulette's screen-space flare (spawnable via
`/eclipsefx`; kept in the same palette so the two never diverge).

**IDEATE.** 1. ✓ Mirror the EXACT `FLARE_COLORS` java palette (#FFF3C4 #FFD166 #C77DFF
#7B2CBF) with a white flash point at 0 — asset and code now share one source of truth.
2. ✓ `face_velocity` true + stretch 0.2→0.5: particles become radial RAYS (it is a
flare, not a puff). 3. ✓ count 14→16, speed 0.35→0.45 (fuller wheel). 4. ✓ warm→violet
seam at 0.58 (two-tone, matching unlock_burst's composition rule). 5. ✗ vortex spin —
the screen-space flare rotates its rays; in world space a vortex on a 22t particle reads
as smoke, not flare. 6. ✗ trail module — rays are already stretched quads; trails double
the fill cost for no read.

**IMPLEMENT/POLISH 2/POLISH 3.** Values above; lifetime 22→24 (+var 7) for ray decay
tails; alpha 1.0→0.85(0.5)→0 monotonic. JSON valid; only corpus vocabulary used.

---

## 7. Gesture glyph trio — personality pass

### 7a. `glyph_greet.json` — warm double-pulse
**PLAN/IDEATE.** Greet should feel like a wave, not a smolder. 1. ✓ DOUBLE-PULSE alpha
envelope per particle: 0→0.9 @0.15, dip to 0.35 @0.35, second hump 0.85 @0.55, fade —
"hello-hello". 2. ✓ Warmer chord: #FFF6D0→#FFC94D golden core, violet only in the tail
(#E0AAFF→#B98CFF) so it still belongs to the eclipse palette. 3. ✓ speed 0.18→0.22
(livelier lift). 4. ✗ third pulse — two is a greeting, three is an alarm. 5. ✗ bigger
particles — greet must stay smaller-energy than danger. 6. ✗ faster vortex — the lazy
orbit IS the friendliness.
**POLISH.** Pulse humps sit at 0.15/0.55 of a 22t life ≈ 0.44 s apart — reads as one
gesture, aggregate flicker stays slow and staggered (random lifetimes desync particles).

### 7b. `glyph_danger.json` — sharp red, strobe-limited flicker
**PLAN/IDEATE.** Danger = urgency with a hard cap on strobing. 1. ✓ Sharp attack: alpha
0→1.0 in 8% of life (was 20%). 2. ✓ EXACTLY TWO spikes per particle (@0.08, @0.45),
decaying (1.0 then 0.95, floors 0.25/0.3), then out — per 16t particle that is ~2.5
pulses/s, and spawn stagger (loop rate 2, random lifetimes) desyncs particles so the
EMITTER never strobes coherently; small world-space area, no screen element. This is the
"strobe-limited" contract, documented here for future editors: never add a third spike,
never sync particle phases. 3. ✓ Hotter reds: #FFB3AD core →#FF3B3B→#C21807, violet
only at death (#5C1A66). 4. ✓ Snappier: lifetime 18→16, speed 0.22→0.26. 5. ✗ full-red
strobe at fixed Hz — photosensitivity law. 6. ✗ size pulsing — alpha already carries the
urgency; two animated channels = visual static.
**POLISH.** Verified both spikes fit before the shortest lifetime (16−3 = 13t > 45% of
16); dip floors (0.25/0.3) keep luminance ratio moderate rather than full on/off.

### 7c. `glyph_follow.json` — soft trailing
**PLAN/IDEATE.** Follow should feel like a thread being drawn behind a guide. 1. ✓ Trail
length 8→12, width 0.04→0.035, trail alpha 0.5→0.38 — longer but fainter ribbon.
2. ✓ Gentler swirl: vortex 0.8→0.55, drag 0.9→0.93, speed 0.2→0.18 (drift, not orbit).
3. ✓ Longer, softer envelope: lifetime 24→28, alpha peak 0.9→0.75 with a mid shelf at
0.55 (the thread persists instead of blinking out). 4. ✗ brighter blues — follow must
recede next to greet/danger. 5. ✗ trailPointModifier games — corpus uses 1.0
everywhere; not worth a novel value on a background glyph. 6. ✗ second trail entry —
double fill cost.
**POLISH.** Trail alpha and particle alpha now cross-fade in the same family
(#70B5FF→#5A8DEE→#B98CFF kept); with 12-point trails on 2-count spawns the fill cost
delta is negligible.

---

## 8. World emitters — impact clarity + settle detail

### 8a. `boss_slam.json` (Herald shard-crash AoE, fog-burst stand-in)
IDEATE: ✓ white-hot birth (#FFFFFF→#D9B8FF in the first 12%) = impact flash read;
✓ `face_velocity` + stretch 0.5 = debris reads its throw direction; ✓ new drag 0.96 =
ballistic start decaying into hang; ✓ lifetime 28→30 var 8→10 + late alpha shelf 0.45
@0.85 = lingering dust settle; ✓ speed 0.55→0.7 (harder pop against the bigger
telegraph); ✗ more particles (AoE spam × shard count — budget); ✗ dropping
`die_on_collision` (ground-cull is the cheap settle).
POLISH: collision-death still culls the settle tail on flat ground — accepted: the tail
is for shards crashing near ledges/players, exactly where clarity matters.

### 8b. `crater_updraft.json` (sanctum crater ambient)
IDEATE: ✓ gentle vortex (strength 0.08, range 6, center +3y) — motes now spiral out of
the bowl instead of rising in laminar columns (settle DETAIL, not energy); ✓ lifetime
var 20→26 + size var 0.03→0.04 (desyncs the loop, kills the visible respawn beat);
✗ rate/count changes (ambient budget is load-bearing); ✗ brighter alpha (it's a
background landmark, 0.35 peak stays).
POLISH: vortex strength chosen an order of magnitude under glyph_follow's — verified the
read stays "thermal drift", not "whirlpool".

### 8c. `eclipse_lightning_impact.json` (intro lightning strikes)
IDEATE: ✓ hot flash held: pure white through 15% (was instant falloff into violet) —
the strike frame reads unmistakably; ✓ stretch 1.6→1.9 + speed 1.4→1.6 (harder spark
streaks); ✓ ember settle: lifetime 9→11 var 4→6, gravity 0.22→0.3, alpha shelf 0.4
@0.7 — a few sparks arc down and die on the ground instead of the whole burst vanishing
as one; ✗ count increase (strikes come in volleys; volley × count is the real budget);
✗ light module (§7 perf trap, deliberately kept out).
POLISH: alpha remains monotonic decay — the flash is the bolt's own; this emitter adds
zero additional flash pulses.

### 8d. `glide_trail.json` (edge-glide attached loop) — covered by the "soft trailing"
verdict: trail 12→16 @ width 0.05, trail alpha 0.42, drag 0.92, lifetime 18→22, violet→
blue two-tone (#C4A5FF→#8F6BE8→#5A8DEE) with a soft mid shelf — a longer, quieter ribbon
that dissolves instead of clipping out. ✗ speed increase (it must trail the player, not
lead); ✗ second trail entry (fill cost).

### 8e. `supply_spark.json` (supply-drop landing pop)
IDEATE: ✓ spark attack: white core held to 15% then #E7D4FF (crisper than the old
white→purple ramp); ✓ stretch 0.4→0.7 (real spark streaks off the crate); ✓ settle:
gravity 0.5→0.65 + lifetime 14→16 var 4→6 + low shelf 0.35 @0.8 — sparks arc down and
gutter out; ✗ gold recolor (gold is the altar/awards chord; supply stays violet);
✗ count increase (the beam is the marker, the pop is garnish — per SupplyBeamClient).
POLISH: initial_velocity 3.5 kept — the pop's silhouette is its identity.

### 8f. `border_shard.json` (border re-seed pops)
IDEATE: ✓ impact clarity: first peak now HOLDS (1.0→0.85 across 0–20%) so the pop reads
before the glitching starts; ✓ settle: subsequent flicker peaks DECAY 0.6→0.35 into a
fade — glitch energy drains instead of staying hot to the end; ✓ lifetime 10→12 (ghost
tail); ✗ any new peaks (kept exactly 3 — the flicker count did NOT increase; total
luminance over life went DOWN, honoring the photosensitivity ceiling); ✗ texture swap
(border_glitch.png is the border's identity).
POLISH: peak spacing (0.5/0.8 of 12t ≈ 3.6t/3.6t) unchanged in frequency terms vs the
old 10t spacing — no faster blinking.

---

## 9. `quasar/emitters/cutscene_veil.json` — veil texture drift

**PLAN.** The start-event submerge/emerge shroud (and breach rim smoke). It read as a
firework: fast, stretched, hard-edged. A veil should DRIFT.

**IDEATE.** 1. ✓ `random_initial_rotation` false→true — the single biggest texture-drift
win: every quad now carries a different orientation of the wisp texture, so the shroud
stops looking like copy-pasted streaks (this was almost certainly an authoring oversight:
every other billboard emitter in the kit randomizes rotation). 2. ✓ New lateral wind
([0.4, 0.15, 0.25] @ strength 0.3) — the veil slides sideways-up like fabric caught in
air, instead of pure radial expansion. 3. ✓ Slower, broader, longer: speed 1.0→0.8, size
0.16→0.2 var 0.09, lifetime 26→32 var 10. 4. ✓ Softer body: stretch 1.2→0.9, alpha
re-shaped 0.9→0.6(0.35)→0.3(0.75)→0 — translucent cloth falloff instead of a bright
core. 5. ✗ trail module (fabric, not comets). 6. ✗ color change (the cyan→violet
identity is shared with the intro grade). 7. ✗ count increase (broadcast per-player in
cutscenes — count is multiplied by the server).

**POLISH 2.** Wind vector length ≈ 0.5 blocks/s at strength 0.3 — checked against the
hemisphere radius (2.4) so the drift doesn't visibly displace the shroud off its anchor
within one lifetime.

**POLISH 3.** Drag 0.92→0.9 rebalanced against the lower speed so the initial billow
still clears the player silhouette before the drift takes over. JSON valid.

---

## Verification (whole cluster)

- `javac --release 21 -proc:none` sandbox harness (`build/moddev` merged jar + Veil
  4.3.0 + geckolib 4.9.2 + voicechat-api 2.6.20 + `clientLegacyClasspath.txt`,
  `-sourcepath src/main/java`): all 7 touched Java files compile with 0 errors on owned
  files. (During one mid-session run, 4 unrelated errors appeared in
  `stormfx/StormWallRenderer.java` — a parallel worker's in-flight edit, not in this
  cluster; re-verified at close.)
- `python3 -m json.tool` on all 12 touched emitters: valid.
- Corpus vocabulary cross-check: touched emitters use only module ids / keys present in
  the untouched emitter corpus (sole flag was `veil:die_on_collision`, pre-existing in
  `boss_slam` itself); gradient percents monotonic, alphas in [0,1].
