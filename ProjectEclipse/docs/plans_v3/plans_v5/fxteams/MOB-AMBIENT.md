# FX Team — MOB-AMBIENT (mob detail pass, W-P-MOBAMB1)

Team process per mob: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: `entity/DeckhandEntity` (+`limbo/OarAnimator` contract), `wizard/*`,
`pale/PaleSentinelEntity`, `entity/GazerEntity`, `entity/SunmoteEntity`,
`ambient/DriftLanternEntity`, `entity/UmbralStalkerEntity`,
`dungeon/EclipseCultistEntity` + their GeckoLib assets / vanilla models / renderers /
texture drivers. Scope: MODEL detail, TEXTURE refinement (Python, palette-true,
emissive accents), ANIMATION richness. Hard rules: hitboxes/AI/balance untouched;
Java bone refs stay in sync with the JSONs (OarAnimator's `oar`/`oar_blade` deckhand
contract is sacred); self-checks are `javac` against the moddev merged jar,
`scripts/geckolib_gen/validate_geo.py` on every touched geo/anim pair, deterministic
texture reruns. No gradle, no git.

Priority order (visibility): Deckhand, Wizard, Pale Sentinel, Gazer, then Cultist /
Stalker / Sunmote / Drift Lantern.

---

## Mob 1 — DECKHAND (priority)

### PLAN
The limbo rower reads as a grey monk blob from the boat bench. Brief: silhouette
detail that moves with the row (hood + belt-lantern), row-cycle WEIGHT (the stroke
should look heavy), rest-pose variance so benched deckhands don't twin — all without
touching the `oar`/`oar_loom`/`oar_shaft`/`oar_blade` chain OarAnimator drives.

### IDEATE
1. **Hood point bone** — a raked 3×3.5×3 tip cube on the hood that lags the row via
   phase-offset sines. **CHOSEN**
2. **Belt + dead lantern** — rope band on the robe with a hanging iron lantern whose
   soul-glass is DEAD (`#57706B`, no glowmask px — the crew's lights went out);
   pendulum keyframes swing it against the stroke. **CHOSEN**
3. **Row weight via torso catmullrom retiming** — slow catch, heavy drive, slack
   recovery instead of an even sine. **CHOSEN**
4. Oar splash particles on the catch — rejected, renderer already spawns them.
5. Rest-pose variance from per-entity phase salts in molang (`hood_point`/`belt`
   desync between benches). **CHOSEN**
6. Second tatter layer on the robe hem — rejected, over-budget for a background mob.
7. Emissive rune on the belt — rejected: palette law says limbo crew carries no light.

### IMPLEMENT
`deckhand.geo.json`: +`hood_point` (child of `hood`), +`belt` (child of `robe`),
+`lantern` (2 cubes, child of `belt`). `deckhand.animation.json`: new channels in
`row`/`idle_sag`/`walk`/`rise`/`attack`/`death`; row torso re-keyed catmullrom for
catch–drive–recovery weight; lantern gets its own row pendulum (peaks mid-drive).
`mobs/deckhand.py`: `LANTERN_IRON`/`LANTERN_GLASS` + `belt_lantern` material, weave
on the hood point, rope kelp band (no ragged cut) on the belt.

### POLISH 2
Fixed the `tilt` loop seam (frequency snapped to a whole cycle per loop length);
lantern swing amplitudes reduced ~30% so it never clips the robe on the drive frame.

### POLISH 3
Bone-contract audit: `oar*` chain byte-identical in the geo; `DeckhandRenderer.
getGeoModel().getBone("oar")` + OarAnimator paths recompiled green. Painter rerun is
byte-identical; glowmask stays 0 px by design.

---

## Mob 2 — WIZARD ORIN (priority)

### PLAN
The observatory host is the most-watched NPC in the mod and he only breathed. Brief:
secondary motion (beard/robe-hem), a real staff crystal, idle business (page-flip +
staff-tap), and hospitality one-shots (greet on approach, ledger-lean while trading).

### IDEATE
1. **Beard split** — `beard` + `beard_tip` child so the sway whips. **CHOSEN**
2. **Robe hem bone** — skirt ring that lags torso motion. **CHOSEN**
3. **Staff crystal** — 45°-rotated `glow_staff_crystal` on the staff tip; `glow_`
   prefix rides the existing glowmask pass. **CHOSEN**
4. **Book prop** — left-arm ledger for the idle page-flip and the trade lean.
   **CHOSEN**
5. **Greet one-shot** — free-hand hat-tip triggered from `tickGreeting()`. **CHOSEN**
6. **Trade lean** — ledger-lean toward the listener from `speakLine()`. **CHOSEN**
7. Star-chart hologram over the book — rejected: FX-team turf (quasar emitters), not
   a model job.

### IMPLEMENT
`wizard_orin.geo.json`: beard split (+`beard_tip`), +`robe_hem` (child of
`robe_lower`), +`glow_staff_crystal` (child of `glow_staff_tip`), +`book` (child of
`arm_left`). `wizard_orin.animation.json`: idle reworked — beard/hem molang sway,
`arm_right` keyframed for a periodic staff-tap, book page-flip beat, crystal
scale-shimmer; NEW `greet` (hat-tip) + `trade` (ledger lean) one-shots; new bones
carried through `walk`/`star_call`/`hurt`/`death`. `WizardOrinEntity`: `ANIM_GREET`/
`ANIM_TRADE` constants, registered triggerable, fired from `tickGreeting()` /
`speakLine()` (cosmetic triggers only — greeting/dialogue logic untouched).
`mobs/wizard_orin.py`: `BOOK_LEATHER`/`BOOK_PAGE` + `book_material`, hem/beard
materials, crystal painted hot with glow accent.

### POLISH 2
Greet/trade lengths trimmed under the dialogue cadence so consecutive `speakLine`
calls can't visibly restart the lean mid-pose; beard_tip amplitude halved in `walk`
(it read as wind, not gait).

### POLISH 3
UV audit for the four new cubes (per-face rects packed into free sheet space, no
overlap — validator clean); `javac` green on entity + renderer; painter rerun
byte-identical (100 glow px incl. crystal).

---

## Mob 3 — PALE SENTINEL (priority)

### PLAN
The weeping-angel tree needs a payoff for the freeze/thaw loop. Brief: petal-armor
plates around the torso that live the whole state machine — sealed as a statue,
BLOOM-open the instant it may move, rippling at idle, wilting in death.

### IDEATE
1. **Four sepal plates** — 0-thickness petal quads (2 shoulder, chest, back) hung off
   the torso rim, per-face UVs. **CHOSEN**
2. **Bloom-open one-shot on thaw** — the unseen-grace tick that clears `DATA_FROZEN`
   fires a `bloom` action anim; keyframe 0 EQUALS the freeze pose so the transition
   is seamless. **CHOSEN**
3. **Petal ripple idle** — one wave travelling chest → right → back → left via 90°
   phase offsets. **CHOSEN**
4. **Walk tuck** — petals streamline against the torso while it creeps. **CHOSEN**
5. **Attack flare** — pull-in on the windup, snap-open on the double-claw hit.
   **CHOSEN**
6. **Death wilt** — brief last-gasp open, then droop closed with the crumble.
   **CHOSEN**
7. Petal-shed particles on bloom — rejected: server already bursts CHERRY_LEAVES on
   frozen hits; doubling reads as spam.

### IMPLEMENT
`pale_sentinel.geo.json`: +`petal_shoulder_right/left` (±24° z), +`petal_chest`
(−12° x), +`petal_back` (+10° x), all torso children, per-face UVs at rows 52–59.
`pale_sentinel.animation.json`: petal channels in `idle` (travelling ripple),
`walk` (tuck + flutter), `freeze` (sealed bud: +10/−8/±18 closing the rest flare),
`attack` (windup pull-in, 0.35 s flare), `death` (0.7 s gasp → wilt); NEW
`bloom` 0.7 s one-shot — petals overshoot open from the sealed pose, head lifts,
antlers quiver, everything settles to idle zero. `PaleSentinelEntity`: `ANIM_BLOOM`
registered + `triggerAction(ANIM_BLOOM)` at the thaw point (freeze hysteresis logic
untouched). `mobs/pale_sentinel.py`: `PETAL`/`PETAL_BLUSH` sepal material — pale
white, dark mid-vein, rose-blushed tip rows (matches the cherry-leaf burst).

### POLISH 2
Bloom keyframe 0 matched to the exact `freeze` statue values (torso [4,−6,0], head
[−8,5,7], petals sealed) — no snap when the base controller blends out of freeze.

### POLISH 3
Petal UV rects verified overlap-free (validator 0 warnings); glowmask untouched by
design (ember eyes stay the only light); entity + renderer `javac` green.

---

## Mob 4 — GAZER (priority)

### PLAN
The watcher's face is a static decal. Brief (vanilla `HierarchicalModel`, not
GeckoLib): iris layers + eyelid parts, iris DILATION as a player's gaze locks on
(the same dot math the vanish goal uses), blink cycles that never fire while
watched.

### IDEATE
1. **Iris pips** — two 1×2 emissive cubes proud inside the mask's hollow eye slits
   (slit centers ±1.5, −4), children of `face` so they ride the eyes pass free.
   **CHOSEN**
2. **Cloth lids** — 7×3 hood-cloth shutters pivoted at the face rims, `yScale` 0.08
   sliver → 1.0 shut; children of `hood`, skipped from the emissive pass so a blink
   OCCLUDES the glow (they sit proud in z). **CHOSEN**
3. **Dilation = view-dot** — nearest player's look·toGazer mapped 0.90→0.985 onto
   pip scale 1.0→1.9, client-side only. **CHOSEN**
4. **Stare suppresses blink** — `blink *= 1 − dilate`: the watched gazer refuses to
   blink. **CHOSEN**
5. **Whisper pulse** — ±8% idle pip shimmer on the ambient-whisper rhythm. **CHOSEN**
6. Pupil trailing the player's position inside the slit — rejected: 1 px of travel,
   invisible at gameplay range.
7. Lid texture as mask-plate (glowing lids) — rejected: a blink must DARKEN the
   face; lids are cloth.

### IMPLEMENT
`GazerModel`: +`iris_left/right` (shared texOffs 46,16; pivot = slit centers so
scale is dilation), +`lid_top`/`lid_bottom` (texOffs 44,24 / 44,28, z −4.75 proud of
the pips at −4.5); `setupAnim` computes dilate (VanishWhenSeenGoal dot math), blink
(110 t cycle, 7 t close, phase-salted by entity id so pairs never sync), whisper
pulse; `renderFaceEmissive` now also skipDraws the lids (face + pips stay the only
eyes-pass geometry). Texture via NEW `scripts/skin_gen/gazer_v2.py` — in-place,
deterministic: pips painted hotter than the mask (`#FFF4FF`), lids as `#1E1A30`
hood weave with a darkened closing-edge rim. `docs/uv/gazer.md` updated.

### POLISH 2
Lid z pushed to −4.75 (in front of pip fronts at −4.5) so a mid-blink frame occludes
the pips instead of z-fighting them; rest sliver kept at 0.08 so the face rim reads
a hint of cloth.

### POLISH 3
Idempotency check: `gazer_v2.py` rerun is byte-identical; `javac` green on model +
renderer; emissive pass audited — lids albedo-only, pips fullbright.

---

## Mob 5 — ECLIPSE CULTIST

### PLAN + IDEATE (compact)
Brief: chant sway (idle) + bolt-cast flourish (cast). Ideas: metronome torso rock /
counter-swaying robe (CHOSEN), verse-bow — head/hood/arms dip once per loop on
`abs(sin)` (CHOSEN), knife-hand devotional waggle (CHOSEN), asymmetric arm twists on
the cast raise + wrist-snap crossover at release (CHOSEN), robe whip + body
quarter-twist at release (CHOSEN), staggered rune-flare cascade a/b/c (CHOSEN),
floating-candle prop (rejected — new geometry unjustified for a spawner mob).

### IMPLEMENT
`eclipse_cultist.animation.json` only (bones already existed): idle = torso z-rock
±2.5° with robe counter-phase, one 5° verse-bow per 4 s loop (head, hood lag, both
arms lift into it), knife z-waggle; cast = y-twists through the raise (−26/+24 at
apex), release snaps arms across (+18/−16), knife spins −24→+30, robe/hood whip,
body [0,−4→+6,+2] twist, runes flare 0.92/0.94 staggered.

### POLISH 2 + 3
All added idle frequencies are whole half-cycles of the 4 s loop (45/90 families +
`abs(sin(45t))` = 0 at both ends) — zero loop seams; validator + `javac` green.

---

## Mob 6 — UMBRAL STALKER

### PLAN + IDEATE (compact)
Brief: skulk crouch cycle (vanilla model). Ideas: smoothed client-side stalk blend
off the synced `isAggressive()` (CHOSEN — in fast 0.08/out slow 0.05, no snap),
sprawl crouch — front legs fold forward / hind back, elbows splay, body sinks
between (CHOSEN), creeping stride — gait amplitude ×0.6 while stalking (CHOSEN),
pounce-ready weight-shift pump so the crouch never freezes (CHOSEN), hackles rake
flat — spine shards fold back 0.55 rad (CHOSEN), neck stretch low (CHOSEN), tail —
rejected (no tail bone; adding one is a silhouette change the pack doesn't need).

### IMPLEMENT
`UmbralStalkerEntity`: client-only `stalkAmount` lerp fields + `stalkAmount(pt)`
hook; `headLower()` now eases (`stalk × 0.3` rad) instead of snapping. Server logic
untouched. `UmbralStalkerModel.setupAnim`: sprawl (±0.38 legs, ±0.1 splay), body
+2.2 px sink + 0.06 rad nose-down, slow `sin(age·0.08)` pump on body/head, yaw
weight-shift, stride scale, spine `xRot = 0.55·stalk`.

### POLISH 2 + 3
Pump amplitudes tuned so paws stay visually grounded (≤0.6 px body travel); all
scales/offsets return to exact base at stalk 0 (no drift after disengage); `javac`
green on entity + model + renderer.

---

## Mob 7 — SUNMOTE

### PLAN + IDEATE (compact)
Brief: inner-core bones for pulse. Ideas: nested `core_inner` kernel that BREACHES
the 2 px shell at pulse peaks (CHOSEN — reads as a heart of daylight), slow beat +
fast shimmer harmonic (CHOSEN), sympathetic core breath ×1.08 (CHOSEN), halo
counter-bob against the beat (CHOSEN), halo wobble tilt (rejected — fights the
existing 45° spin), second orbit ring (rejected — silhouette budget).

### IMPLEMENT
`SunmoteModel`: +`core_inner` 1.4³ child of `core` (texOffs 16,0); `setupAnim`
pulses kernel 0.8–1.75× (`sin(age·0.18)` beat + `sin(age·0.45)` shimmer), core
breath, halo counter-bob ±0.3 px. Texture via NEW `scripts/skin_gen/sunmote_v2.py`:
the fractional kernel rects painted as one uniform `#FFFBE8` block (hotter than the
`#FFF2C0` core — correct under the whole-model additive eyes pass).
`docs/uv/sunmote.md` updated.

### POLISH 2 + 3
Kernel nested as a child of `core` so breach scale compounds with the breath (peak
≈2.6 px vs 2.16 px shell — a clean flare, not a flicker); uniform block texture makes
sub-pixel UV sampling artifact-proof; rerun byte-identical; `javac` green.

---

## Mob 8 — DRIFT LANTERN

### PLAN + IDEATE (compact)
Brief: inner-core bone + pulse rhythm (GeckoLib pilot mob). Ideas: `glow_flame_core`
kernel inside the soul flame (CHOSEN — `glow_` prefix rides the glowmask pass free),
heartbeat DOUBLE-thump — base beat + offset double-frequency harmonic (CHOSEN),
attack flare ×2.2 (CHOSEN), counter-flicker — kernel dips deeper than the flame in
`flicker` (CHOSEN), death "soul winks out last" — kernel holds through the flame's
collapse, surges at 1.1 s, dies at 1.5 s (CHOSEN), cage-glow sync (rejected — the
shine-through blob is baked into the cage glowmask; animating it needs shader turf).

### IMPLEMENT
`drift_lantern.geo.json`: +`glow_flame_core` 1.5³ (child of `glow_flame`, uv 32,14).
`drift_lantern.animation.json`: core channels in `idle` (lub-dub: `sin·240·0.25 +
sin·480+60°·0.15`), `walk` (deeper), `attack` (2.2 flare), `flicker`
(counter-dips 0.35), `death` (hold → surge → wink out). `mobs/drift_lantern.py`:
kernel material `flame(#FFFFFF, FLAME_CORE)` — hotter than the flame so the thump
reads through the cube faces when the kernel scales past them.

### POLISH 2 + 3
Idle/walk pulse frequencies are whole cycles of the 3 s loop (240/480 = 2/4 cycles —
seamless); glowmask regenerated (239 px incl. kernel); validator + geo bone tree
clean; renderer untouched (glow_ naming does the work).

---

## Batch validation (whole cluster)

- `validate_geo.py` on all 5 touched geo/anim pairs (deckhand, wizard_orin,
  pale_sentinel, eclipse_cultist, drift_lantern): **10/10 PASS, 0 errors** (only
  benign fractional-UV "painter rounds outward" warnings).
- `javac` (merged NeoForge jar + jarJar geckolib/veil + modules-2, `--release`
  toolchain 21) over every touched Java file incl. the OarAnimator/Deckhand contract
  pair: **clean**.
- Texture drivers rerun: deckhand / wizard_orin / pale_sentinel / drift_lantern
  (geckolib_gen) + gazer_v2 / sunmote_v2 (skin_gen, in-place): **deterministic,
  byte-identical on rerun**.
- Bone-ref sync audit: `OarAnimator`+`DeckhandRenderer` (`oar`, `oar_blade`),
  `PaleSentinelRenderer`, `GazerModel` child lookups, `SunmoteModel` kernel lookup —
  all resolve against the shipped geometry.
- Hitboxes, AI goals, damage numbers, spawn rules: **untouched** (the only entity
  edits are cosmetic animation triggers/hooks: wizard greet/trade, sentinel bloom,
  stalker client-side stalk blend).
