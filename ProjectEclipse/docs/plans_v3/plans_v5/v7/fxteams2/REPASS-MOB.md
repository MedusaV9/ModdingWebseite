# REPASS-MOB — fresh-eyes pass over mob ANIMATION FEEL (post-v6, the last 10%)

Team log. Prior logs: `plans_v5/fxteams/MOB-*.md` ×5; fixes landed since v6 and held here:
death arcs filled, wisp rotation, glowmask holes, UV integer snap. Process: **PASS 1**
(per-mob micro-review of the priority 8 + small keyframe fixes) → **PASS 2** (one
personality micro-beat per mob, existing trigger seams only, no new AI) → **PASS 3**
(fresh-eyes re-read of every edit + full re-verify). Self-checks: `validate_geo.py`
across all 15 geo+anim pairs, `javac --release 21 -proc:none` against the moddev
neoforge-21.1.238 classpath + geckolib 4.9.2 + veil 4.3.0 (`/tmp/repassmob.args`),
deterministic painter re-runs (md5 before/after). NO gradle, NO git.

Reminder from MOB-BOSS1: **Ferryman + Herald are NOT GeckoLib** — vanilla
`HierarchicalModel`s, all animation procedural Java in `setupAnim` driven by
lerped entity clock fields. Their "keyframes" are math; review + edits happen in
`FerrymanModel.java` / `HeraldModel.java`.

## Baseline (before touching anything)

`validate_geo.py` on all 15 geo+anim pairs: **0 errors / 0 warnings** (15/15 passed).
Held after every edit below and on the final re-run.

---

## PASS 1 — micro-review + small keyframe fixes (priority 8)

### Deckhand (`deckhand.animation.json`)
- **Missing counter-motion (walk):** torso pitched with the step but had zero yaw —
  shoulders rode the hips. Added ±3° torso counter-yaw against the leg swing
  (`[-2,3,0] → [-7,0,0] @ mid → [-2,-3,0]`, catmullrom, loop-symmetric). Small; reads
  as weight shift.
- **Linear where catmullrom breathes (row):** `oar_blade` feathering was linear ramps —
  robotic wrist. Converted to catmullrom (same values, same times).
- Loop seams: first==last everywhere else. Death runs its full length. Attack windup
  already eases (catmullrom). OK.

### Fog Colossus (`fog_colossus.animation.json`)
- **Seam pop (roar):** the back-slab/spine tremor (`math.sin(t*1400)`) started and cut
  at full amplitude — popped in at 0.0 and out at the end. Wrapped all five tremor
  molangs (`back_slab_low/high`, `spine_a/b/c`) in a
  `math.clamp(t*4,0,1) * math.clamp((1.5-t)*4,0,1)` fade envelope: tremor now swells
  in over 0.25 s and dies before the roar settles. No keyframe values touched.
- Walk cadence, slam anticipation (heavy ease-in already), death timing: OK.

### Fog Tyrant (`fog_tyrant.animation.json`)
- **Seam pop (idle):** the two wisp `scale` breathers used phases that didn't return
  to their start value at the 8 s loop end. Re-phased to `+180` / `+0`
  (`sin(t*45+180)`, `sin(t*45)`) — both now close the loop exactly (45·8 = 360).
- **Missing counter-motion (stride):** robe swung pitch-only while torso yawed —
  added gentle robe counter-yaw/roll (`[3,-2,2.5] ↔ [3,2,-2.5]`, catmullrom,
  first==last).
- Attack anticipation: already catmullrom ease-in-hard (torso −22° yaw coil at 0.25 s
  before the 0.45 s strike). Death: full-length. OK.

### Rift Warden (`rift_warden.animation.json`)
- **Seam pops (idle):** head Y-sway `sin(t*30)*8` landed at sin(120°)=0.87 at the 4 s
  loop end — visible position pop. Re-frequenced to `45` → C0-continuous ping-pong
  scan (the velocity flip at the zero-crossing reads as a deliberate glitch-snap —
  on-theme for the Warden). `glow_shard_a` orbit `t*120` → `t*90` (90·4 = 360, exact
  closure).
- **Missing counter-motion (walk):** hips yawed in phase with the torso. Phase-flipped
  hips to `sin(t*225+180)*5` — hips vs shoulders now counter-rotate.
- Death: hold-and-collapse runs the full length. OK.

### Storm Hound (`storm_hound.animation.json`)
- Gallop/idle cycles: loop-clean, catmullrom where it matters, hips/chest already
  counter-flex. Lunge anticipation eases in hard. Death full-length. No pass-1 edits.

### Glitched Wanderer (`glitched_wanderer.animation.json` — GENERATED, all edits in `scripts/skin_gen/backrooms_wanderer.py`)
- **Seam pops (idle):** body/arm sway freqs 60/70 didn't close the 5 s loop → all
  re-frequenced to `72` (72·5 = 360); `head_shard` drift `45 → 36` (36·5 = 180,
  symmetric sine closes at 0).
- **Seam pops (sprint):** the 0.55 s cycle used freqs that closed nowhere. Re-tuned
  head/jaw_shard/head_shard/shard_torso/glow_seam to `981.8` / `654.5`
  (981.8·0.55 ≈ 540 → half-period phase-aligned; 654.5·0.55 ≈ 360). `shard_torso`
  phase `+90 → +180` (pass-3 catch: `+90` left a 0.6 px pop; `+180` starts and ends
  the sine at zero).
- **Attack anticipation:** was a linear 2-key ramp to the −165° coil. Painter now
  injects a mid key at 60 % of the windup carrying only ~30 % of the travel
  (`arm_right` −48° @ 0.09 s of the 0.15 s coil, `body` matching) — piecewise
  ease-in-hard, the snap lands in the back half. Kept linear segments on purpose:
  the hard corner suits the glitch.

### Ferryman (`FerrymanModel.java` — procedural)
- Row cycle, chain pendulum, kneel/plant/raise blends, staggered death keel: reviewed
  — envelopes all smoothstep, no linear snaps, death fills `deathTime`. No pass-1
  edits (pass 2 below).

### Herald (`HeraldModel.java` — procedural)
- Corona bob, tentacle whip, gesture/volley/roar layers, joint-by-joint death
  collapse: reviewed — eased lurches, no abrupt end. Hoisted the `death` read to the
  top of `setupAnim` (needed by pass 2, and the old late duplicate declaration is
  gone — caught by javac in pass 3).

---

## PASS 2 — one personality micro-beat per priority mob (existing seams ONLY)

| Mob | Micro-beat | Wiring (existing pattern) |
| --- | --- | --- |
| Ferryman | Lantern raise-and-peer: every 540 ticks (~27 s) a 3 s smoothstep beat — chain shortens/hoists, head turns to the lantern, rowing damps 70 %, chain sway damps 85 % | Pure `setupAnim` clock (`animAge % 540`), gated to idle: scaled by `(1−raise)(1−kneel)(1−plant)(1−death)` — never fights an action |
| Herald | Crown shards briefly re-order: every ~14 s one 18-tick pulse ripples the crown spikes (each lifts/tilts in sequence, swap-like) | Pure `setupAnim` clock, per-spike phase offset; gated by `(1−roar)(1−gesture)(1−death)` |
| Fog Tyrant | Fog inhale before slam — **already present, verified**: `attack` wisps contract to 0.78–0.85 scale at 0.25 s (inhale) then burst 1.35–1.5 at the 0.45 s strike with a 0.62 s echo; same inhale-burst in `squall` (0.6→1.7 @ 1.4 s) and `enrage` | No change needed |
| Rift Warden | Shard orbit stutter-skip (glitch): `glow_shard_b` idle orbit now freezes at −216° for 0.15 s then snaps 27° ahead and resumes, closing at −360° | Keyframes inside the existing idle loop — zero wiring |
| Fog Colossus | Knuckle-drag scrape: `forearm_right` drags through the stride bottom (18→8→−8→… catmullrom, loop-symmetric) — the arm reads as scuffing the ground each cycle | Keyframes inside the existing walk loop |
| Storm Hound | Mane twitch on player sight: `mane_a/b/c` pre-twitch keys at 0.08/0.16 s (−7°/+3° flick) before the head throws back | Front of the existing `howl` one-shot, which already fires on first target acquisition (`setTarget` → `triggerAction(ANIM_HOWL)`) |
| Glitched Wanderer | Full-body 'notice' freeze: new 0.7 s one-shot — 0.06 s snap into a locked pose (body/head/arms/jaw shard all freeze off-axis, tiny root jolt), dead-still hold to 0.55 s with only the `glow_seam` flared 1.6×, then release | New `notice` anim in the painter + `ANIM_NOTICE` triggerable on the existing `action` controller; fired from `setTarget` first-acquisition guard (`noticed` flag) — byte-for-byte the Storm Hound howl pattern, no new AI |
| Deckhand | Rest-pose oar tap: during `tilt` (rest) the right arm taps the oar twice at ~1.85 s (8°→16°→10°→15.5° flutter, first==last) | Keyframes inside the existing tilt loop |

---

## PASS 3 — fresh-eyes re-read + full re-verify

Re-read every diff cold. Three catches, all fixed:
1. **Wanderer sprint `shard_torso` phase** `+90` still popped 0.6 px at the loop seam
   (981.8·0.55 ≈ 540 ⇒ need the sine at zero on both ends) → `+180`. Fixed in the
   painter, regenerated.
2. **Herald crown shuffle wasn't death-gated** — crown could keep tidying itself while
   collapsing. Pulse now scaled by `(1−death)`.
3. **Herald duplicate `death` local** (javac error after hoisting the read) — removed
   the late re-declaration inside the death block.

Verification matrix (all green):
- `validate_geo.py`: **15/15 pairs, 0 errors / 0 warnings** (deckhand, drift_lantern,
  eclipse_cultist, fog_colossus, fog_revenant, fog_tyrant, glitched_hound,
  glitched_husk, glitched_tick, glitched_wanderer, pale_sentinel, rift_warden,
  shadow_bolt, storm_hound, wizard_orin).
- `javac`: `FerrymanModel.java`, `HeraldModel.java`, `GlitchedWandererEntity.java`
  compile clean against the full moddev classpath.
- **RawAnimation resolution:** scripted cross-check of every
  `thenLoop/thenPlay/thenPlayAndHold` literal and every
  `EclipseGeoAnimations.once/loop/hold(GEO_ID, NAME)` pair against the full
  `assets/eclipse/animations/**` tree — **43/43 refs resolve** (incl. the new
  `animation.glitched_wanderer.notice`).
- **Painter determinism:** re-ran `mobs/{deckhand,fog_colossus,fog_tyrant,rift_warden,storm_hound}.py`
  + `skin_gen/backrooms_wanderer.py` — every geo/anim/texture/glowmask md5
  **byte-identical** across runs; the geckolib_gen painters don't write animation
  JSONs, so the hand-edited five stay authoritative (only the Wanderer's anim is
  generated, and its edits live in the painter).

## Files touched

- `src/main/resources/assets/eclipse/animations/entity/{deckhand,fog_colossus,fog_tyrant,rift_warden,storm_hound}.animation.json`
- `scripts/skin_gen/backrooms_wanderer.py` (+ regenerated `glitched_wanderer.animation.json`)
- `src/main/java/dev/projecteclipse/eclipse/client/entity/FerrymanModel.java`
- `src/main/java/dev/projecteclipse/eclipse/client/entity/HeraldModel.java`
- `src/main/java/dev/projecteclipse/eclipse/backrooms/GlitchedWandererEntity.java`
