# FX Team MOB-FOG — fog-storm mob upgrade log (planner → ideators → polishers)

Cluster: `eclipse:fog_colossus` + `eclipse:fog_revenant` + `eclipse:storm_hound` —
`entity/fog/*.java` (server), `client/entity/fog/*Renderer.java`, GeckoLib asset triples
under `assets/eclipse/geo/entity/`, `assets/eclipse/animations/entity/`,
`assets/eclipse/textures/entity/` (painted by `scripts/geckolib_gen/mobs/<id>.py`).

Ground rules honored throughout:

- NO gradle, NO git. Validation after every pass: `python3 scripts/geckolib_gen/
  validate_geo.py <geo> <anim>` (Blockbench 1.12.0/1.8.0 formats, bone cross-check),
  a UV-rect overlap audit across every cube face, deterministic repaint via the
  per-mob painter drivers (same seeds — reruns stay byte-identical), and `javac`
  (release 21) against the cached moddev merged-jar (`build/moddev/artifacts/
  neoforge-21.1.238-merged.jar`) + GeckoLib 4.9.2 + the legacy classpath +
  `build/classes/java/main` for every touched Java file. All green at every checkpoint.
- Hitboxes, AI goals, attributes and balance UNTOUCHED. The only Java behavior addition
  is the Storm Hound's cosmetic first-target howl, a verbatim mirror of the Fog
  Colossus roar pattern (`setTarget` override, not persisted, no combat effect).
- Frozen Java timing contracts kept bone-exact: Colossus slam contact 1.35 s
  (`GroundSlamGoal.IMPACT_TICK = 27`), Colossus death 2.5 s w/ torso landing 1.4 s
  (`DEATH_ANIM_TICKS = 50`, `DEATH_IMPACT_TICK = 28`), Revenant channel 1.5 s
  (`FogBlindBurstGoal` 30 t) + death 2.0 s (40 t), Hound windup 1.0 s
  (`ChargedLungeGoal.WINDUP_TICKS = 20`) + death 1.5 s (30 t).
- MOB-FOG family palette (this pass): deep storm slate bases (`#2A313A`–`#4A525D`
  family) + SICK GREEN-VIOLET glow — core `#E9FFD8`, green `#A9F07E`, violet `#9C63E8`,
  dim rim `#6F52B8`. Emissive pixels are always ALSO painted bright in the albedo
  (conventions §4 — Iris parity), and every new glow rides the existing
  `AutoGlowingGeoLayer` glowmask pattern (all three renderers already `withGlowmask()`).
- New bones only ADD; every pre-existing bone name survives, so no anim id, Java
  constant, or head-tracking (`head`) reference broke.

---

## 1. eclipse:fog_colossus (→ v2)

### PLAN

Job: the 3.4-block rare heavy elite of the fog storms. Emotional target: WEIGHT — every
gesture should feel like architecture falling over. Current weaknesses (geo/anim/driver
read): the silhouette is perfectly symmetric (a brute this old should be lopsided), the
chest is a flat unbroken slab (no focal point at player eye height), the slam lifts and
drops on nearly equal timing (1.25 s up, 0.15 s down, 0.6 s recover — the drop reads
fine but the recovery snaps back too fast for 80 HP of stone), and the walk is a smooth
symmetric swing with no impact frames at all.

### IDEATE

1. **Asymmetric right arm via `inflate`** — bulk the slam arm (+1.0 upper, +1.75
   forearm, +1.25 fist) so it visibly out-masses the left, plus a knuckle-ridge cube
   protruding from the fist front. `inflate` grows cubes WITHOUT touching UV rects —
   zero re-layout risk, the Blockbench-native way to do asymmetry. A rest-pose
   `shoulders` z-tilt (2.5°) makes the whole torso hunch toward the big arm (GeckoLib
   anim rotations stack on the geo rest pose). **ADOPTED.**
2. **Back spines** — three slate shards (`spine_a/b/c`) parented to the existing
   `back_slab_low/high` chain so they inherit the slab sway for free; glowing
   green→violet tips. **ADOPTED.**
3. **Chest maw** — a `maw` bone with a north-face-only overlay cube (per-face UV, 1 px
   proud of the chest): a jagged glowing gash with slate teeth, breathing in idle,
   gaping through the slam lift, flaring at the roar, dying to a sliver in death.
   **ADOPTED** (the fog is EATING him from the inside — the elite's "wrongness" beat).
4. **Weighted slam retiming** — slow lift 0→1.15 s, tremble hover to 1.3 s (molang
   shiver on body/arms), 0.05 s drop landing EXACTLY at the frozen 1.35 s contact, then
   a LONG recovery (root stays sunk −2.2 → −1.4 until 1.75 s). Anticipation-contact-
   recovery with the mass budget shifted into anticipation + recovery. **ADOPTED.**
5. **Stomp walk cycle** — two hard down-beats per 1.6 s cycle (root 1.7 → −0.5 in
   0.12 s with an impact dip), body lurch on each beat, maw squash-flare. **ADOPTED**
   (the "charged stomp" read for a knuckle-walker).
6. Second parasite head / shoulder growth — **REJECTED**: silhouette noise; the maw
   already owns the "the fog got inside" beat and a second focal point dilutes both.
7. Emissive palm + knuckle drag trail during walk — **REJECTED**: palms face
   down/backward (never read), and a particle trail would be Java-side (AI frozen).
8. **Violet silhouette rim glow** — top pixel row of the vertical faces on
   shoulders/back slabs tinted `#6F52B8` in albedo + low-alpha (90) glowmask copy:
   storm light grazing the crown line. **ADOPTED.**

### IMPLEMENT

Geo: `maw` bone (north-only UV at 108,14), `spine_a/b/c` (UVs 114,51 / 120,14 /
120,23), knuckle ridge (96,9), inflates on the right arm chain, shoulders rest-tilt.
Anims: all six rewritten per the sheet above — idle gains maw breathing + spine sway +
heavier right-arm hang; attack becomes a right-arm haymaker (anticipation −118° wind at
0.22, contact 0.32, settle to 0.8); roar gains a pre-crouch (body +6° at 0.25) before
the throw plus maw gape + spine rattle; death keeps the frozen 1.4 s/2.5 s keys and adds
the fog-mote dissolve read (maw scale y → 0.05, spine sag + shrink) syncing with the
existing WHITE_ASH bleed + POOF in `tickDeath`. Driver: family palette, maw/spine
painters, rim glow painters (fissures now green with violet flecks, eyes `#D6FFB8`,
coral tips pale violet `#B9B3DC`). Validated (validate_geo + overlap audit + repaint).

### POLISH PASS 2

- **Real catch:** the painter's directional shading + 1 px outline dimmed the maw's and
  spines' EDGE glow pixels in the albedo while the glowmask copy stayed full-bright —
  under Iris (which dims glow layers) the gash would read duller than vanilla. Both
  painters are emissive-dominant → marked `shadeless` (same rule as the `flame`
  factory); ASCII-dump re-verified albedo == glowmask brightness on the gash.
- Knuckle ridge originally sat INSIDE the inflated forearm volume (invisible); moved to
  protrude from the fist front (z −8.5 → −5.5 vs. fist front −6.25).

### POLISH PASS 3

- Cross-side audit: slam contact 1.35 s ⇔ `IMPACT_TICK 27` ✓ (stale Java comment
  "raise runs 0–1.25 s" updated to the new lift/hover/drop split — comment-only);
  death keys 1.4/2.5 s ⇔ ticks 28/50 ✓; trigger names `attack/slam/roar/death`
  unchanged ✓; `head` bone intact for head tracking ✓; renderer javadoc updated for
  the new glowmask contents. UV overlap audit: 127 face rects, 0 overlaps. Re-validated.

---

## 2. eclipse:fog_revenant (→ v2)

### PLAN

Job: the tall drifting wraith of the fog patches. Emotional target: it isn't WALKING,
it's being CARRIED by the fog — and when it attacks, those arms are far too long.
Current weaknesses: the lower half ends in one clean-cut ragged hem (reads as a skirt,
not as cloth the storm is actively shredding), the arms are single 13 px sticks (the
"long grasp" fantasy stops at the elbow that doesn't exist), and every sinusoidal chain
in idle/walk used INCREASING phase offsets down the chain — which makes children LEAD
their parents instead of trailing (the wave visually travels tip→root, the opposite of
drag).

### IDEATE

1. **Forearm segment insert** — new `forearm_right/left` (3×6×3) spliced between arm
   and claw; claws re-parented and dropped 6 px (now reaching y≈3.5, almost scraping
   the ground it hovers over). Existing `arm_*`/`claw_*` names and UVs survive.
   **ADOPTED.**
2. **Four tatter bones** (`tatter_a..d`) hanging off `skirt_low` below the hem — thin
   1-deep strips with heavier ragged alpha cuts and a stronger violet mist wash; they
   inherit the skirt's death-shrink for free. **ADOPTED.**
3. **True trail-delay phasing** — phase DECREASES down every chain (arm → forearm −45°
   → claw −90°; skirt_low +200 → tatters +130..160) so children lag. **ADOPTED**
   (direction fixed in pass 2 — see below).
4. **Grasp attack lunge rework** — anticipation 0→0.18 s (torso rears −14°, BOTH long
   arms wind to −150°/−142° with forearms cocking +46°), contact 0.28 s (body lunges
   −3 forward, arms sweep through, claws splay +44°), recovery drift to 0.6 s. The old
   anim was a one-arm swipe with the left arm idling. **ADOPTED.**
5. Hood/veil lag bone — **REJECTED**: `head` is head-tracked; a lagging veil child
   fights the tracking and can clip the eye slits at high look angles.
6. Detached floating pelvis (visible gap under the torso) — **REJECTED**: resizes the
   read of the frozen hitbox and the tatters + ragged hem already sell "no legs".
7. **Violet mist creep + hood rim glow** — hem creep re-tinted from slate to
   `#6B5F8C`, hood crown gets the family rim (`#6F52B8`, alpha 80 glowmask).
   **ADOPTED.**
8. Wisp count increase (3 → 5) — **REJECTED**: the cast_blind scale ramp already makes
   the wisps the loudest element; more of them muddies the blind-burst telegraph.

### IMPLEMENT

Geo: forearms (UVs 36,54 / 48,54), claws re-parented (UVs unchanged), tatters (UVs
0,58 / 8,58 / 16,58 / 24,58 — all inside the 64×64 canvas, 0 overlaps). Anims: idle and
walk gain forearm/tatter channels with lagging phases; cast_blind keeps its frozen
1.5 s envelope and adds forearm splay + tatters lifting outward while the fog swells;
attack rebuilt per idea 4; death keeps the 2.0 s upward dispersal and adds tatter
unravel (rot ±85–100° + scale y → 0.35) and limp forearm fold. Driver: family palette
(eyes `#A9F07E`/`#E9FFD8`, wisps pale-green→violet flame, coral tips `#B9B3DC`), new
`tatter`/`forearm` materials, hood rim painter. Validated.

### POLISH PASS 2

- **Real catch (the phase-direction bug):** first implementation reused the repo's
  established "+phase down the chain" habit — but `sin(t·ω + φ)` with larger φ peaks
  EARLIER, i.e. the claw led the arm. All new chains (arms, tatters) rewritten to
  decreasing phase so motion propagates root→tip like actual drag. The legacy
  torso→skirt chain keeps its original (small-amplitude) phasing — not this pass's
  churn to re-tune a read that already shipped.

### POLISH PASS 3

- Cross-side audit: `cast_blind` 1.5 s ⇔ 30 t channel ✓, death 2.0 s ⇔ 40 t ✓,
  claws' new parent `forearm_*` exists ✓ (validator bone cross-check), `DriftStrollGoal`
  and all Java untouched ✓, renderer javadoc's "cyan eye slits" corrected to the
  family palette. UV audit: 131 face rects, 0 overlaps. Re-validated.

---

## 3. eclipse:storm_hound (→ v2)

### PLAN

Job: the charged pack hunter. Emotional target: a LIVE WIRE on four legs — lean, coiled,
visibly holding more charge than its body wants. Current weaknesses: the body is a
box-y 8-wide slab (reads stocky, not lean), there is nothing at the neck (the "storm
mane" of the design language is missing — the windup only had the spine shards to
flare), the tail is a 2-segment paddle rather than a whip, and the pack has no vocal
moment at all (the colossus roars; the hound just growls per-hit).

### IDEATE

1. **Lean silhouette** — body cube 8×7×16 → 7×7×16 (legs now sit 0.5 px proud, correct
   for a lean quadruped); walk gains deeper spine flex (pitch 8/−6 vs 5/−4, bounce
   1.1/−0.2) so the sprint reads as a bounding gallop. **ADOPTED.**
2. **Storm-mane bones** — `mane_a/b/c` (top + flanking tufts at the neck, angled back),
   slate fur with violet charge strands (partial-alpha glow): flutter in the sprint,
   FLARE outward + scale up alongside the spine-glow ramp in the windup, stream back
   flat during the lunge, wilt + shrink in death. **ADOPTED.**
3. **`tail_c` whip segment** — third, thinner (1×1×5) segment; whip chain phases made
   properly TRAILING (tail_b −70°, tail_c −140° — the old tail_b actually led tail_a).
   **ADOPTED.**
4. **Howl one-shot** — head throw back (−38°), jaw 32°, mane flared, spine glow pulsing
   through a 0.6 s sustain with molang tremble, 1.6 s total; wired exactly like the
   colossus roar (first target acquisition, `setTarget` override, cosmetic, not
   persisted; `SoundEvents.WOLF_HOWL` at 0.75 pitch). Pack-alert mechanics stay on
   `HurtByTargetGoal.setAlertOthers()` — the howl just announces them. **ADOPTED.**
5. `glow_mane_*` naming (full-emissive mane) — **REJECTED**: auto-glow would copy the
   whole albedo into the glowmask and the mane becomes neon foam; strand-only glow at
   alpha 150 keeps it fur that HOLDS charge.
6. Longer legs for the lean read — **REJECTED**: moves the ground contact of every
   existing leg key in five animations for marginal silhouette gain.
7. **Palette shift** — veins/mouth/eyes cyan → sick green (`#A9F07E`/`#E9FFD8`), spine
   shards + horn now green-core → violet-tip flame, whip tip violet at the crack.
   **ADOPTED.**
8. Windup crouch deepened further (−1.8 → −2.6) — **REJECTED**: the −1.8 crouch is the
   dodge-window telegraph players already learned; deepening it re-tunes counterplay
   optics for style points.

### IMPLEMENT

Geo: slim body, manes (UVs 37,24 / 48,6 / 48,13), tail_c (UV 20,57) — 132 face rects,
0 overlaps. Anims: all six reworked + the new `howl`; pose continuity across the
windup→lunge handoff preserved for the new bones (mane rot/scale at lunge 0.0 ==
windup 1.0 values, same rule the spine shards already followed). Java
(`StormHoundEntity`): `ANIM_HOWL` constant + triggerable registration + first-target
`setTarget` override mirroring `FogColossusEntity`; class javadoc documents the howl.
Driver: mane material + strand glow painters, `tail_c` whip-crack material, family
palette. Validated (validate_geo + overlap + repaint + javac).

### POLISH PASS 2

- **Real catch (box-UV axis):** the whip-tip charge gradient ran along `fx` for ALL
  long faces — but on a z-long cube the up/down faces map their length to `fy` (their
  box-UV rects are w×d = 1×5), so the TOP of the whip (the view players actually see on
  a quadruped) never got the charge. New `_whip_t()` resolves the length axis per face;
  re-painted and pixel-verified the top-face gradient (fy=4 tip now violet).
- Mane albedo/glowmask alignment ASCII-verified (strands emit, fur stays dark).

### POLISH PASS 3

- Cross-side audit: `howl` id ⇔ `animation.storm_hound.howl` ✓ registered on the
  `action` controller ✓; windup 1.0 s ⇔ 20 t ✓ (lunge anim deliberately outlives the
  ≤0.7 s dash into recovery — pre-existing contract); death 1.5 s ⇔ 30 t with the
  spine flicker-out choreography preserved and manes added ✓; `javac` green on
  `StormHoundEntity` (confirms `SoundEvents.WOLF_HOWL` exists in the 21.1.238 merged
  jar). Renderer javadoc updated for mane strands + whip tips. Re-validated.

---

## Final validation matrix

| Artifact | Tool | Result |
|---|---|---|
| 3 `.geo.json` + 3 `.animation.json` (all 6 in one invocation for bone cross-check) | `scripts/geckolib_gen/validate_geo.py` | PASS, 0 errors 0 warnings |
| all 3 geos | UV face-rect overlap audit | 0 overlaps (127/131/132 rects) |
| 3 painter drivers | run twice, `sha256` compare | byte-identical (deterministic seeds kept) |
| `StormHoundEntity`, `GroundSlamGoal`, `FogColossusRenderer`, `FogRevenantRenderer`, `StormHoundRenderer` (+ unchanged fog package compile-checked) | `javac` release 21, moddev merged-jar + GeckoLib 4.9.2 classpath | OK |
| 6 texture PNGs | repainted; glowmask == albedo canvas (128²/64²/64²) | OK |
