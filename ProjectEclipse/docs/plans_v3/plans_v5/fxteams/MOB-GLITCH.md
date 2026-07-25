# FX Team MOB-GLITCH — creature visual upgrade log (planner → ideators → polishers)

Cluster: **GLITCHED HUSK**, **GLITCHED HOUND**, **GLITCHED TICK** (reduced scope),
**WANDERER** (backrooms), **THE OTHER** — `entity/glitch/*.java`,
`backrooms/GlitchedWandererEntity.java`, `TheOtherEntity.java`, GeckoLib assets under
`assets/eclipse/geo|animations|textures/entity/glitched_*`, renderers under
`client/entity/glitch/` (incl. `GlitchedGeoRenderer` with its glitch-blink pose-pop) and
`client/entity/TheOtherRenderer`.

Ground rules honored throughout:

- **Hitboxes / AI / balance unchanged.** Every Java edit is visual-only: renderer layers,
  client-side animation *selection*, a vanilla model class, and one access widening
  (`private → protected`) on an existing attribute-modifier id constant so the Wanderer can
  *read* a speed state the base Husk already writes. No goal, attribute value, dimension or
  damage number was touched.
- Textures are Python-generated end to end (`scripts/geckolib_gen/mobs/*.py`,
  `scripts/skin_gen/backrooms_wanderer.py`) and remain **deterministic** — the full regen
  was re-run after every polish pass and produced byte-identical PNGs (md5 checked over all
  16 glitched/wanderer sheets, before == after).
- Java bone refs kept in sync: the only bone name referenced from Java in this cluster is
  `head` (head-tracking in the three `Glitched*Renderer`s) — present in every geo. All NEW
  bones (`jaw_shard`, `spine_shard_a/b/c`) are animation-driven only, no Java references
  by design.
- NO gradle, NO git. Validation after every pass: `python3 -m json.tool` +
  `scripts/geckolib_gen/validate_geo.py` (bone-parent graph, UV bounds vs texture size,
  animation→bone reference check) on every touched geo/anim pair, and `javac`
  (`--release 21 -proc:none`) against the cached moddev merged-jar + Veil + GeckoLib +
  molang-compiler + `build/classes/java/main` classpath for every touched Java file.
  All green at every checkpoint (the single `GlitchedTickEntity` deprecation note is
  pre-existing and out of scope).

---

## 1. GLITCHED HUSK — the corrupted baseline

### PLAN

Job: the family's first-contact mob — the player's mental template for "glitched." Read
target: a zombie whose *data* went bad, not its flesh. Current weaknesses (code + asset
read): the model is a clean symmetric humanoid (only the pre-existing `head_shard` breaks
it), the texture's glitch language is a single scanline/block pass with no motion feel,
and walk/idle are smooth sine loops — nothing about the animation says "dropped frames."

### IDEATE

1. **Displaced jaw bone (`jaw_shard`)** — the lower jaw torn off the face and re-hung
   floating askew under the head (own pivot, pre-rotated ~[-8, 6, -19]°), child of `head`
   so head-tracking drags the broken piece around rigidly. **ADOPTED.**
2. **Asymmetric arm dislocation** — both shoulder origins nudged off the torso line
   (right: out+down+forward, left: out+up+back) with opposing static Z/X pre-rotations, so
   the silhouette reads "wrong" from any angle even in T-pose. **ADOPTED.**
3. **Stutter-walk via hold-snap keyframes** — the walk cycle's leg/arm rotations re-keyed
   as hold → hold → SNAP (two identical keys 0.15–0.2 s apart, then a 0.05 s jump), plus a
   root-position micro-pop mid-cycle: frame-skip, not slow motion. **ADOPTED.**
4. **Jitter idle** — root position gets 1-frame ±0.15-unit XZ spasms at irregular offsets
   (0.7 s, 1.9 s, 3.1 s into the 4 s loop) layered under the existing breathing sway; jaw
   shard drifts on its own slow sine so it never sits still. **ADOPTED.**
5. **Datamosh texture pass** — horizontal run-length streaks (rows smeared sideways from a
   seeded source column), checkerboard corruption patches, RGB-split edges, and emissive
   glitch scars (short bright dashes exported to the glowmask). Implemented in the shared
   `glitch_lib.glitch_body` / `glitch_scars` so the whole family inherits it. **ADOPTED.**
6. Second head shard orbiting the skull — **REJECTED**: crowds the new jaw shard; one
   floating face fragment is a statement, three is noise.
7. Detached hand cube trailing the right arm — **REJECTED**: needs its own bone + anim
   channels in every animation for a detail that reads as a bug at distance.
8. Vertex-noise "melt" on the torso cubes — **REJECTED**: per-vertex deformation isn't
   expressible in a geo cube; faking it with many thin cubes would blow the UV budget.

### IMPLEMENT

Geo: new `jaw_shard` bone (child of `head`, own pivot, 2 cubes: jaw block + torn cheek
plate, pre-rotated); `arm_right`/`arm_left` origins displaced and given opposing static
pre-rotations. Texture: `glitched_husk.py` refactored from `paint()` into a reusable
`build()` (Wanderer reuses it, §4); new `jaw_shard` material (glitch body + cyan tint);
body glow = `combine_glow(heart_glow, glitch_scars)`; scars added to arms/legs.
Anims: `idle` gains root jitter pops + jaw drift; `walk` re-keyed hold-snap with root
micro-pop; `attack`/`death` gain jaw-shard channels so the new bone never floats inert.

### POLISH 2

- Walk snap timing tightened: the left-leg snap landed on the same beat as the root pop,
  which read as lag, not corruption — offset by 0.1 s so the pops syncopate.
- Jaw drift amplitude halved in `idle` (was visibly detaching from the head shadow at
  distance); `glow_seam` scale key in idle corrected (was overshooting to 1.4, now 1.15).

### POLISH 3

- Preview render sweep (orthographic front/side, texture applied to warped geo): arm
  dislocation confirmed asymmetric from the front; jaw shard clears the chest at all
  idle keys. Full regen → byte-identical; `validate_geo` + `json.tool` + `javac` green.

**Verdict:** the Husk now stutters like corrupted playback — broken silhouette, datamosh
skin, frame-skip gait — with zero gameplay drift.

---

## 2. GLITCHED HOUND — the pouncing corruption

### PLAN

Job: the fast flanker of the family. Read target: a dog-shaped process that keeps
dropping packets — chunks of it simply *aren't there*. Weaknesses: smooth quadruped spine
with no jaggedness, texture fully opaque (no missing-geometry read), and `attack` is a
generic lunge with no glitch identity; `glitch_blink` (the entity's short client-visible
blink state) had no dedicated pre-pose.

### IDEATE

1. **Jagged spine via shard bones** — three `spine_shard_a/b/c` bones (children of
   `body`) along the backline, each a thin plate pre-rotated at conflicting angles like a
   corrupted normal map; they breathe independently in idle/walk. **ADOPTED.**
2. **Missing-polygon look via texture alpha** — new `glitch_lib.dropout()` wrapper:
   seeded 3-px blocks punched to alpha 0 on body/legs/tail (5% base, 11% alt sheet),
   with `keep_faces` guarding UV rects that would open holes into the silhouette's
   load-bearing reads (eyes, jaw). Renderer already uses cutout — no Java needed. **ADOPTED.**
3. **Glitch-pounce attack** — re-keyed `attack`: crouch-load with spine shards slamming
   flat, 1-frame anticipation *pop* (root scale 1 → 0.92 → 1.06), then the leap arc with
   legs frozen mid-stride (dropped-frame feel) and jaw snap on landing. **ADOPTED.**
4. **Teleport-blink pre-pose** — `glitch_blink` rewritten: the hound compresses into a
   low corrupted crouch (body yaw-skewed 14°, head counter-rotated, `spine_shard_b`
   popped up) held for the blink duration — the renderer's pose-pop + new chromatic ghost
   (§6) sell the same beat from the shader side. **ADOPTED.**
5. **Shared corruption texture pass** — same datamosh/checkerboard/RGB-split/scar stack
   as the Husk via `glitch_lib`, hound palette. **ADOPTED.**
6. Tail deleted entirely on the alt sheet — **REJECTED**: crosses from "missing polygons"
   into "different mob"; the alt sheet already doubles the dropout rate.
7. Extra leg bone pair for a 6-legged glitch frame — **REJECTED**: changes the silhouette
   the family's readability depends on, and would need AI-side gait changes (out of scope).
8. Per-shard glowmask strips — **REJECTED**: the spine already reads at night from the
   body scars; glowing shards turn the backline into a landing strip.

### IMPLEMENT

Geo: `spine_shard_a/b/c` added (unique pivots, conflicting pre-rotations, distinct UV
rects). Texture: `dropout()` on body/legs/tail; `spine_shard_*` material; body glow =
`combine_glow(heart_glow, glitch_scars)`; leg scars. Anims: shard channels in
`idle`/`walk`/`death`; `attack` and `glitch_blink` fully rewritten per ideas 3–4.

### POLISH 2

- Pounce landing was mushy: jaw snap key moved 0.05 s earlier so it lands *on* the root
  impact key, and `spine_shard_c` now whips one key late for follow-through.
- Dropout was eating the eye row on the alt sheet — `keep_faces` extended to the head
  strip; regenerated, holes now live only on flanks/legs/tail.

### POLISH 3

- Preview render: shard plates read as a broken ridgeline from the side; alpha holes
  visible but silhouette intact. `glitch_blink` pre-pose checked against the renderer's
  1–2-frame pop hold (§6) — crouch is fully established before the ghost fires.
  Full regen byte-identical; all validation green.

**Verdict:** the Hound now telegraphs like a corrupted predator — jagged spine, holes in
its data, and a pounce that blinks before it bites.

---

## 3. GLITCHED TICK (reduced scope, per the "?")

### PLAN

Job: swarm filler — on screen for seconds, usually in groups. Verdict from the read: the
16×16-scale body can't carry model surgery (any shard bone is bigger than the limbs), and
its animations are already twitchy by design. **Scope: texture corruption pass only.**

### IDEATE (scoped)

1. **Inherit the upgraded `glitch_lib.glitch_body`** — the datamosh streaks, checkerboard
   patches and RGB-split edges land automatically via the shared library its driver
   already calls; new seeds mean a fresh but consistent corruption layout. **ADOPTED**
   (zero driver-file churn — `glitched_tick.py` unchanged).
2. Emissive scar pass — **REJECTED**: at tick scale the scars merge with the existing eye
   glow into a single blob; the glowmask stays as-was.
3. Alpha dropout — **REJECTED**: on a body this small, missing blocks read as z-fighting.
4. Jitter-idle re-key — **REJECTED**: idle is already a twitch loop; more jitter is
   invisible on top of it.
5. Leg shard bone — **REJECTED**: model surgery ruled out in PLAN.
6. Alt-sheet-only checker density boost — **REJECTED**: sheets should stay
   distinguishable by *palette*, not density, for swarm readability.

### IMPLEMENT / POLISH

Regenerated `glitched_tick{,_alt}{,_glowmask}.png` through the upgraded library; diffed
against the husk/hound sheets to confirm the tick's palette keeps its identity. Anim JSON
re-validated (untouched but part of the sweep). Nothing else — reduced scope honored.

**Verdict:** the Tick inherits the family's new skin for free; everything else stays.

---

## 4. WANDERER (backrooms) — the person-shaped wrong thing

### PLAN

Job: the backrooms' signature dread. It must NOT read "monster" at first glance — it
reads *person*, then the proportions register. Weaknesses: the geo was a straight husk
re-skin (identical proportions), the palette was husk-green (wrong biome), and its
animations were the husk's stutter set — but backrooms dread is *smoothness*, not stutter.

### IDEATE

1. **Subtly WRONG proportions via geo warp** — `_warp_geo()` in the generator: head (and
   its shards) deflated (−0.75 / −0.35 / −0.2 inflate) for the small-head read; both arm
   cubes stretched DOWN from unchanged shoulder anchors (right to 20 units, left to 15 —
   asymmetric, fingertips past the hip line). Anchors staying put means every
   husk-derived animation still lands on the warped rig. **ADOPTED.**
2. **Backrooms-yellow regrade** — the Wanderer's sheets are painted by the *husk's*
   `build()` materials on the warped geo, then regraded toward damp-carpet yellow
   (channel remap + luminance-preserving tint) so the corruption language is identical
   but the biome is unmistakable. **ADOPTED.**
3. **Unsettling slow pace** — bespoke `walk`: metronome-smooth, arms hanging dead
   straight (the long arms do the work), head locked level; the husk stutter vocabulary
   deliberately absent. **ADOPTED.**
4. **Head-turn-too-far moment** — in the 5 s `idle`, at 2.0 s the head snaps in 0.1 s to
   [6, −118, 8]° (past-shoulder, past-possible), holds 1.3 s, then ratchets back in two
   stops. One root micro-pop at 4.25 s keeps the glitch signature alive. **ADOPTED.**
5. **Burst-sprint anim + client-side selection** — bespoke `sprint` (deep forward lean,
   long arms trailing, stride rate ×2.4); `GlitchedWandererEntity.handleBaseState`
   override picks it when a gaze-burst speed modifier (`STALK_SPEED_ID` /
   `UNSEEN_SPEED_ID`) is active and the entity is moving — read-only client check,
   `GlitchedHuskEntity.UNSEEN_SPEED_ID` widened `private → protected` for it. AI/balance
   untouched. **ADOPTED.**
6. **UV collision fix as part of the warp** — the stretched right-arm strip (rows 16–39)
   collides with the husk's jaw UV at (32,36); the warp re-parks the wanderer's jaw strip
   at (32,40). **ADOPTED** (validator-driven, see POLISH 2).
7. Neck elongation — **REJECTED**: with the small head it tips into creature-feature
   territory; the brief is *subtly* wrong.
8. Fully bespoke geo file — **REJECTED**: the generator warping the husk geo keeps the
   two rigs provably in sync (same bones, same anim compatibility) with 60 lines instead
   of a 600-line fork.

### IMPLEMENT

`backrooms_wanderer.py` rewritten (+288 lines): imports `glitched_husk` as a library,
paints via `husk.build()` on the warped geometry, regrades to backrooms-yellow, warps geo
via `_warp_geo()`, and injects bespoke `IDLE`/`WALK`/`SPRINT` dicts into the exported
animation JSON (husk's `attack`/`glitch_blink`/`death` retained under wanderer names —
6 animations total). `GlitchedWandererEntity` gains `ANIM_SPRINT`, a cached
`RawAnimation`, the `handleBaseState` override and the `hasGazeBurst()` modifier check.

### POLISH 2

- `validate_geo` caught the arm-strip/jaw UV overlap (idea 6) — fixed in the warp, not by
  shrinking the arm (the long-arm read is the whole point).
- Head-turn hold extended 0.9 s → 1.3 s: at 0.9 s players could dismiss it as a look-at;
  at 1.3 s it's unmistakably wrong. Return path split into two ratchet stops.

### POLISH 3

- Preview render (front + side): small head + knee-length asymmetric arms read clearly at
  silhouette distance; yellow regrade keeps the emissive scars legible. Sprint selection
  logic compiles against both modifier ids; full regen byte-identical; all green.

**Verdict:** the Wanderer is now a smooth, person-shaped thing with proportions that
register a half-second too late — and it only glitches when it turns its head or charges.

---

## 5. THE OTHER — the silhouette that shouldn't be

### PLAN

Job: the reveal mob — it passes as a player-shaped figure until it's aggressive. Read
target: keep the vanilla-humanoid silhouette *exactly*, then break it on reveal.
Weakness: it rendered as a stock `HumanoidModel` — no custom anything, and the
disguise→reveal beat had zero model-side support.

### IDEATE

1. **Floating fragment bones, silhouette-preserving** — three small cubes (`frag_crown`,
   `frag_shoulder`, `frag_hip`) parented to head/body but positioned OUTSIDE the limb
   volumes; `visible = false` while disguised (perfect vanilla silhouette), on reveal they
   appear and drift on desynced sines. **ADOPTED.**
2. **Looming idle** — while disguised and near-stationary: arms pinned dead straight
   (zRot ±0.02), a 0.05 rad forward body lean, head pitched down 0.09 rad — mannequin
   stillness instead of the vanilla idle sway. **ADOPTED.**
3. **Reveal accents** — on aggression: fragments detach and orbit, head cants 0.12 rad off
   vertical — the "mask slipping" read. **ADOPTED.**
4. Vanilla-model swap kept minimal — `TheOtherModel extends HumanoidModel`, registered via
   `TheOtherModel::createBodyLayer` in `EclipseEntityRenderers`; `TheOtherRenderer` now
   instantiates it. No GeckoLib migration. **ADOPTED.**
5. Full GeckoLib port with bespoke geo/anims — **REJECTED**: destroys the "is that a
   player?" ambiguity that comes from pixel-identical vanilla rendering, for no visual
   gain the fragment layer doesn't already deliver.
6. Fragment glow/emissive pass — **REJECTED**: the disguise depends on nothing glowing;
   a lit crown fragment is visible before the reveal through cave darkness.
7. Body-cube scale pulse on reveal — **REJECTED**: scaling `HumanoidModel` parts distorts
   the armor/overlay layers that share the rig.
8. Mirror-pose (copying the player's pose) — **REJECTED**: needs per-player pose capture
   plumbing — behavior/AI adjacent, out of scope.

### IMPLEMENT

New `TheOtherModel` (vanilla `HumanoidModel` subclass): `createBodyLayer()` adds the three
fragment cubes at silhouette-clearing offsets; `setupAnim()` gates fragments on
`isAggressive()`, drives the drift sines and reveal head-cant, and applies the looming
idle when disguised and `limbSwingAmount < 0.05`; `hat.copyFrom(head)` keeps the overlay
in lockstep. `TheOtherRenderer` + `EclipseEntityRenderers` updated to the new model/layer.

### POLISH 2

- Preview render caught fragment/arm clipping: crown raised (−11.5), shoulder pushed out
  (−10.0 / 1.0), hip given a Z offset (4.5) — all three now clear the limb sweep at every
  drift phase.
- Looming idle originally also pinned the head yaw — reverted; head-tracking staying live
  while the body is mannequin-still is *more* wrong, and keeps look-at behavior intact.

### POLISH 3

- Re-rendered disguise vs. reveal panel: disguised silhouette is pixel-identical vanilla
  (fragments hidden); revealed state shows all three fragments clear of the body.
  `javac` green across model/renderer/registration; no assets touched (vanilla texture
  path unchanged).

**Verdict:** The Other holds a perfect vanilla disguise and breaks it on reveal with
drifting body fragments and a mask-slip head cant — model-side only.

---

## 6. RENDERER — glitch-blink pass timing (`GlitchedGeoRenderer`)

### PLAN

The family renderer's pose-pop (the whole-model offset during `glitch_blink`) lived for a
full tick per hash gate — at 20 TPS that's ~3 rendered frames at 60 fps, long enough to
read as lag. Brief: hold 1–2 frames max, add a chromatic ghost.

### IMPLEMENT

- **Pop hold**: offset computation extracted to a static `popOffset(entity, partialTick)`
  helper, gated by `POP_HOLD_PARTIAL = 0.4F` — the pop lives only for the first 40% of
  its gated tick (~1–2 rendered frames at 60 fps), then snaps home. Same hash gate, same
  `POP_OFFSET = 0.045F` amplitude — only the *duration* changed.
- **Chromatic ghost**: new `GlitchGhostLayer` (`GeoRenderLayer`, added for all four
  family renderers via the shared base constructor). While `popOffset` is non-null it
  re-renders the baked model twice with `RenderType.entityTranslucent`: a magenta ghost
  (`0x60FF3B6B`) pushed further along the pop vector (`+GHOST_SPREAD = 0.8`) and a cyan
  ghost (`0x6037F2E5`) mirrored behind the un-popped rest position (`−1.8×`) — an
  RGB-split of the *pose*, matching the texture pass's RGB-split language. Layer
  re-render can't recurse (layers don't run inside `reRender`; confirmed against the
  GeckoLib jar).

### POLISH

- Ghost alpha tuned to 0x60 (was 0x80 — double-image read too solid, ate the main
  silhouette at night). Spread tuned so ghosts never overlap the true model's bounding
  box at pop amplitude. Verified the layer no-ops entirely (single early return) outside
  pop frames — zero steady-state cost.

**Verdict:** blink now pops for 1–2 frames with a magenta/cyan pose ghost and returns to
a clean frame before the eye can call it lag.

---

## Final validation matrix

| Check | Scope | Result |
| --- | --- | --- |
| `validate_geo.py` | husk, hound, tick, wanderer geo+anim pairs (8 files) | 8/8 pass, 0 errors 0 warnings |
| `python3 -m json.tool` | all touched geo/anim JSONs (7 files) | all OK |
| `javac --release 21` | full cluster: 4 entities + `GlitchedMonster`, `GlitchedWandererEntity`, `TheOtherEntity`, 4 renderers + `GlitchedGeoRenderer` + `GlitchGhostLayer`, `TheOtherModel`, `TheOtherRenderer`, `EclipseEntityRenderers`, `BackroomsRenderers` | 0 errors (1 pre-existing deprecation note in `GlitchedTickEntity`) |
| Texture determinism | full regen of all 16 glitched/wanderer sheets | byte-identical (md5 before == after) |
| Java bone-ref sync | grep sweep of cluster Java for bone names | only `head` referenced; present in all geos |
| Hitbox/AI/balance | diff audit of all Java edits | visual-only (renderer layers, client anim selection, model class, one access widening) |
