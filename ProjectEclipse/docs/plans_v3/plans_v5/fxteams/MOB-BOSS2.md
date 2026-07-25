# FX Team — MOB-BOSS2 (round: boss model/texture/animation next-level pass)

Team process per boss: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: FOG TYRANT (`entity/boss/fog/FogTyrantEntity.java`,
`client/entity/fogboss/FogTyrantRenderer.java`, `geo/entity/fog_tyrant.geo.json`,
`animations/entity/fog_tyrant.animation.json`, `mobs/fog_tyrant.py` driver) +
RIFT WARDEN (`entity/boss/rift/RiftWardenEntity.java`,
`client/entity/rift/RiftWardenRenderer.java`, `geo/entity/rift_warden.geo.json`,
`animations/entity/rift_warden.animation.json`, `mobs/rift_warden.py` driver).

Hard rules this round (mirrors MOB-BOSS1 scope): hitboxes/AI/balance untouched, wiring
through the EXISTING controller patterns only (`EclipseGeoMonster` base/action
controllers + `triggerAction`), Java bone/animation references kept in sync, Blockbench
box-UV geo/anim JSONs, 128² frozen canvases. Self-checks: `validate_geo.py` on every
geo+anim pair, deterministic texture-driver reruns, programmatic UV-overlap audit,
`javac --release 21 -proc:none` against the moddev merged jar + geckolib 4.9.2 + Veil
4.3.0 + legacy classpath. NO gradle, NO git.

Phase reality check (drives the "phase-transition poses" line item): the Tyrant runs
THREE phases split at 60%/25% HP — the server already fires `crown_call` at the 2-push
and `enrage` at the 3-push (with roar/shake/nova FX), so the phase poses live INSIDE
those two anims. The Warden runs TWO phases and beats the break with `stagger` (the
weakpoint window). No new trigger IDs were needed anywhere — the sync surface is
unchanged.

---

## Boss 1 — FOG TYRANT

### PLAN
The monarch reads flat at melee range: shoulders end in bare slabs, the chest "cage" is
just two horizontal ribs, the robe is one uniform slate, and the big beats (slam, squall,
death) move only the arms/torso. Targets: (a) MODEL — fog-plume shoulder wisps + a
completed 4-bar core cage; (b) TEXTURE — layered fog gradient on the robe + hotter caged
core; (c) ANIMATION — idle hover-drift, slam with a fog-burst beat at contact, squall
(blind-burst) channel with an inhale→blast read on the wisps, death collapse that
dissipates UPWARD into the storm explosion, and phase flair inside `crown_call`/`enrage`.
Constraint: `robe` bone drives the skirt the hitbox visually hangs on — position drift
must stay ≤ ~0.5 px so the silhouette never lies about the 4.2-block hitbox.

### IDEATE
1. **Fog-plume shoulder wisps** — one `wisp_left`/`wisp_right` bone per shoulder
   (children of the pauldron bones so they inherit every shoulder beat for free), each a
   2×6×2 plume + offset 1×4×1 tip, pre-rolled ∓8° outward; painted as condensed fog
   (`#39414B` → `#8E9FB4` toward the dissolving tip), deliberately NON-emissive — fog,
   not storm-light. **CHOSEN**
2. **4-bar core cage** — two 1×5×1 uprights added to `chest_cage` (UV free block at
   (110,106)/(116,106)) closing the two existing ribs into a real cage around
   `glow_core`; middle rows of every bar catch the core light (emissive via a custom
   cage glow painter). **CHOSEN**
3. **Layered fog gradient robe** — `robe_fog` material: four dither-edged fog strata
   that LIGHTEN toward the hem, so the monarch reads as wading hip-deep in his own
   storm; electric seams unchanged on top. **CHOSEN**
4. **Hotter storm core** — `storm_core` re-ground: white-hot `#F6FEFF` heart, arc-flicker
   rim (deterministic hash flicker, same salt in albedo + glowmask). **CHOSEN**
5. **Idle hover-drift** — `robe` gets a slow two-axis positional drift
   (`math.sin(q.anim_time*45)*0.5` X / `*90+45`-phased 0.4 Z) under the existing breath
   bob; wisps counter-sway with a subtle scale breath so the fog never sits still.
   **CHOSEN**
6. **Slam anticipation-contact-recovery** — `attack` (0.8 s) gets a root weight-drop at
   contact, a `glow_core` contact pulse (scale spike), and the wisps snapping flat then
   BURSTING outward exactly on the hit frame — the "fog burst timing" beat the brief
   asks for. **CHOSEN**
7. **Squall blind-burst channel** — wisps pull INWARD + shrink through the 2.0 s channel
   wind-up (inhale), then blast outward oversized on the burst frame; torso pose leans
   into the gale. **CHOSEN**
8. **Death dissipate-upward** — through the 3.5 s held death: collapse forward as before,
   but the wisps RISE (position +Y), unroll, and scale out to ~1.6× as they thin — the
   fog leaving the body a beat before the storm `explode()` takes over. **CHOSEN**
9. Separate cage-door bone that swings open on death to free the core. **REJECTED** —
   needs a new bone the death FX (core gutter, already in the renderer) doesn't know
   about; the storm explosion already owns that beat.
10. Emissive wisps (glow-prefix bones). **REJECTED** — the light language is frozen:
    seams/core/crown are the storm-light; wisps must read as condensed fog or the
    silhouette turns into a christmas tree.

### IMPLEMENT
- `fog_tyrant.geo.json`: `wisp_left` (pivot 11,43,0, roll −8°, cubes (96,92)+(106,92))
  and `wisp_right` (mirrored, (112,92)+(122,92)) under the shoulder bones; `chest_cage`
  gains the two 1×5×1 uprights. 23→25 bones, 29→35 cubes. UVs placed in
  programmatically-verified free canvas (see POLISH 2).
- `fog_tyrant.py`: new `robe_fog` (4-strata dither gradient), `fog_wisp`
  (`CLOAK`→`WISP_PALE #8E9FB4` toward tip), hotter `storm_core` (`CORE_HOT #F6FEFF`
  heart + arc-flicker rim), `cage_bar`/`cage_glow` (core-lit middle rows, custom glow
  painter on `chest_cage`). Deterministic — reruns byte-identical.
- `fog_tyrant.animation.json`, all 10 anims touched where the new bones matter:
  `idle` (robe drift + wisp sway/breath, 22 bones), `stride` (wisps trail the glide),
  `attack` (root weight-drop, core contact pulse, wisp fog burst on the hit frame),
  `lance_volley` (wisps stream backward through the volley), `storm_step_out`/`_in`
  (wisps funnel UP into the step-out vanish / settle with overshoot on re-entry),
  `crown_call` (wisps rise with the crown — the phase-2 pose), `squall` (inhale→blast),
  `enrage` (wisp flare — the phase-3 pose), `death` (rise + unroll + scale-out
  dissipation feeding the storm explosion).
- Java: ZERO edits needed — `FogTyrantEntity` triggers by animation ID only
  (`stride`/`attack`/`lance_volley`/`storm_step_out`/`storm_step_in`/`crown_call`/
  `squall`/`enrage` + base `idle`/`death`), and `FogTyrantRenderer` references no bone
  names. Additive-only asset change ⇒ sync holds by construction.

### POLISH 2
- Visual audit of the regenerated 5×-upscaled albedo + glowmask: robe strata read as
  fog layers not stripes, cage uprights clearly lit at mid-height, wisp gradient
  dissolves cleanly, glowmask contains ONLY core/cage/seams/eyes/lances/crown (wisps
  dark as designed).
- Programmatic UV audit: rasterized every box-UV footprint of all 35 cubes — zero
  cross-bone overlaps on the 128² canvas.
- `stride` wisp keyframes rewritten to house style: base roll expressed as a ZERO-centered
  delta on top of the geo bone's −8° rest pose (`-6 + math.sin(...)` for a −14° total)
  — GeckoLib ADDS sampled animation rotation to the bone snapshot, so an animation
  baseline that repeats the rest angle double-counts it (fixed post-EVAL-V6-MOB D3:
  all wisp channels now carry deltas, the geo alone owns the ±8° pre-roll).

### POLISH 3
- Continuity pass over every action→base handoff: all one-shot anims end within ~0.1 of
  their rest pose (GeckoLib's controller transition smoothing absorbs the rest) — no
  pops; `storm_step_out` holds its last frame by design (the entity is gone).
- Molang loop-boundary check on `idle`/`stride` sine clocks: all robe/wisp frequencies
  chosen so `anim_time × f` completes whole cycles over the loop length (45/90 over
  4.0 s, 225 over 1.6 s).
- `validate_geo.py` geo+anim pair: PASS, 0 errors 0 warnings, 10 animations, bone-name
  cross-check clean.

---

## Boss 2 — RIFT WARDEN

### PLAN
The warden's rift half carries the character; the armor half is a flat obsidian slab and
the three shards are the only motion at idle. Targets: (a) MODEL — a 4th orbiting shard
+ two proud crack-line plates; (b) TEXTURE — obsidian-GLASS facets + emissive violet
fissures across the armor half; (c) ANIMATION — hover bob with drift, teleport-blink
wind-up (suck-in) and re-entry overshoot, shard-volley spin-up across all four shards,
summon beam-channel pose (rising shard halo), stagger sag (the 2-phase break beat), and
a death SHATTER that pairs with the existing 60 t `tickDeath` implosion FX. Constraint:
`body` is the hover root, `root` stays clean for the scripted death implosion.

### IDEATE
1. **4th orbiting shard** — `glow_shard_d` (1×2×1, torso child, UV (28,44)) on the
   armor-side upper chest, orbit-bobbing COUNTER-phase to a/b/c so the halo reads as a
   system, not a metronome; auto-emissive via the `glow_` prefix. **CHOSEN**
2. **Crack-line plates** — `crack_plate_chest` (4×6×1 proud of the torso armor half, UV
   (0,44)) + `crack_plate_faulds` (6×4×1 proud of the faulds, UV (12,44)): armor pieces
   already failing, each carrying a guaranteed burning crack path — the bones that get
   to PEEL OFF in the death shatter. **CHOSEN**
3. **Obsidian-glass facets** — `_facet` re-grind of `armor_plate`/`pauldron`/arm:
   diagonal facet cells with glassy catch-light edges replacing the flat plate tone.
   **CHOSEN**
4. **Violet fissures, same-salt emissive** — wandering hairline cracks
   `#B98CFF`→`#E9DCFF` (~14-texel spacing with breaks) across plate/pauldrons/arm; the
   glowmask REUSES the exact albedo pixel test (same salt) so mask and albedo can never
   drift — the MOB-BOSS1/Tyrant seam trick, violet edition. **CHOSEN**
5. **Idle hover-drift** — `body` gains a slow lateral sway under the existing bob; shard
   d counter-orbits; both crack plates "breathe" (sub-pixel proud-distance pulse) like
   plates barely held on. **CHOSEN**
6. **Blink wind-up/re-entry** — `blink_out` (0.5 s): shards + plates SUCK INWARD toward
   the rift core as anticipation before the vanish; `blink_in` (0.6 s): everything
   settles with a spring overshoot — teleport reads as violent displacement, not a cut.
   **CHOSEN**
7. **Volley shard-spin** — `volley` (1.4 s): all FOUR shards spin up around the warden
   with accelerating rotation into the release frame; plates flare proud at the shot.
   **CHOSEN**
8. **Summon = beam-channel pose** — `summon` (1.5 s): the four shards rise into a slow
   halo over the raised-arm channel pose; plates flare — this is the fight's channel
   read (the warden has no sustained hitscan beam; `summon` IS the channel). **CHOSEN**
9. **Death shatter** — 3.0 s held: shards eject upward then collapse down-and-out with
   360–540° spins (each a different signed rate), plates peel off on catmullrom arcs
   (chest −z/−x, faulds +x) and tumble away — timed so the frame-2.2→3.0 collapse hands
   off into the existing `tickDeath` implosion/FX finale. **CHOSEN**
10. Skirt-half separation on death (faulds splits into flying halves). **REJECTED** —
    needs re-cutting the faulds cube into new bones; the crack plates already sell the
    disintegration at 1/6 the surgery.
11. A 5th+6th shard ring. **REJECTED** — the volley AI fires three projectiles; four
    orbiters already outnumber the volley — more would promise ammo the fight never
    delivers.

### IMPLEMENT
- `rift_warden.geo.json`: `glow_shard_d` (torso child, pivot 6.5,35,1.5),
  `crack_plate_chest` (torso child, proud at z −3.5), `crack_plate_faulds` (faulds
  child, proud at z −3.75). 18→21 bones, 18→21 cubes; UVs in the free (0..32, 44..50)
  strip, overlap-audited.
- `rift_warden.py`: `_facet` diagonal facet-cell grinder, `fissure_at`/`fissure_color`/
  `fissure_glow` (same-salt albedo+glow violet cracks), re-ground `armor_plate` +
  `pauldron` + arm, new `crack_plate`/`crack_plate_glow` (guaranteed crack path down
  each plate face). Deterministic — reruns byte-identical.
- `rift_warden.animation.json`, all 9 anims touched where the new bones matter: `idle`
  (body sway, shard-d counter-orbit, plate breathing), `walk` (plates + shard d ride
  the glide), `attack` (0.6 s — plates jolt on the blade contact frame), `volley`
  (4-shard accelerating spin-up + plate flare), `blink_out` (inward suck), `blink_in`
  (overshoot settle), `summon` (rising 4-shard halo over the channel pose), `stagger`
  (2.0 s — plates sag with the weakpoint slump; the phase-break pose), `death` (shard
  ejection + plate peel, hand-off to the `tickDeath` implosion).
- Java: ZERO edits — `RiftWardenEntity` triggers by ID only
  (`attack`/`volley`/`blink_out`/`blink_in`/`summon`/`stagger` + base
  `idle`/`walk`/`death`), `RiftWardenRenderer` references no bone names.

### POLISH 2
- Visual audit of the 5× previews: facet cells read as ground glass (not noise), fissures
  land on plate/pauldron/arm and glow in EXACTLY the same pixels in the mask, both crack
  plates show their guaranteed crack path, shard d matches the a/b/c material, rift half
  untouched.
- Programmatic UV audit across all 21 cubes: zero cross-bone overlaps.
- Death-shatter timing re-checked against `tickDeath`: the plate/shard collapse
  completes by 3.0 s (60 t) so the held last frame is the "empty armor" pose the
  implosion FX detonates.

### POLISH 3
- Blink pair continuity: `blink_out` ends at the sucked-in pose (entity vanishes on the
  trigger's heels), `blink_in` STARTS from that pose and overshoots home — the two
  one-shots read as one motion across the teleport.
- Volley spin acceleration retimed so the max angular rate lands exactly on the release
  keyframe, not after it (anticipation-contact honesty).
- `validate_geo.py` geo+anim pair: PASS, 0 errors 0 warnings, 9 animations, bone-name
  cross-check clean.

---

## Round summary (both bosses)

| Surface | Change | Self-check | Result |
|---|---|---|---|
| `fog_tyrant.geo.json` | +2 bones (`wisp_left/right`), +6 cubes (wisps ×4, cage uprights ×2) → 25/35 | `validate_geo.py` + UV-overlap audit | PASS / 0 overlaps |
| `rift_warden.geo.json` | +3 bones (`glow_shard_d`, `crack_plate_chest/faulds`), +3 cubes → 21/21 | `validate_geo.py` + UV-overlap audit | PASS / 0 overlaps |
| `fog_tyrant.animation.json` | 10/10 anims refined (idle drift, slam fog-burst, squall inhale→blast, death dissipate-up, phase poses in `crown_call`/`enrage`) | `validate_geo.py` pair-mode bone cross-check | PASS 0/0 |
| `rift_warden.animation.json` | 9/9 anims refined (hover drift, blink suck/overshoot, 4-shard volley spin, summon halo channel, stagger phase sag, death shatter) | `validate_geo.py` pair-mode bone cross-check | PASS 0/0 |
| `fog_tyrant.py` → PNG + glowmask | `robe_fog` strata, `fog_wisp`, hot `storm_core`, lit `cage_bar` | deterministic rerun + 5× visual audit | regenerated, audited |
| `rift_warden.py` → PNG + glowmask | `_facet` obsidian glass, same-salt violet fissures, `crack_plate` paths | deterministic rerun + 5× visual audit | regenerated, audited |
| `FogTyrantEntity` / `RiftWardenEntity` / both renderers | ZERO edits (additive-only assets) | `javac --release 21 -proc:none`, moddev merged jar + geckolib 4.9.2 + Veil 4.3.0 + legacy classpath | 0 errors |
| Java↔asset sync | all 10 Tyrant + 9 Warden Java-referenced animation IDs present in the JSONs; renderers reference no bone names; NO new trigger IDs | scripted cross-check | in sync |
| `docs/uv/fog_tyrant.md` / `docs/uv/rift_warden.md` | new bone/cube/UV rows + refreshed art-brief/emissive sections | manual review against geo | updated |

Frozen surfaces untouched: hitboxes (4.2-block Tyrant / 1.1×3.0 Warden), AI goals,
damage/HP balance, wire payloads, controller wiring (`EclipseGeoMonster` base + action
+ `triggerAction`), death-FX ownership (Tyrant storm `explode()`, Warden `tickDeath`
implosion). Both bosses' phase transitions keep their existing trigger sites — the new
poses live inside the anims those sites already fire.

Note for sibling teams: the moddev `clientLegacyClasspath.txt` does NOT contain the
geckolib/Veil jars — cluster javac self-checks must append them from the gradle module
cache (`software.bernie.geckolib/geckolib-neoforge-1.21.1/4.9.2`,
`foundry.veil/veil-neoforge-1.21.1/4.3.0`) next to the merged NeoForge jar.
