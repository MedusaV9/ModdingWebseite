# FX Team MOB-BOSS1 — Ferryman + Herald upgrade log (planner → ideators → polishers)

Cluster: `entity/boss/FerrymanEntity` + `HeraldEntity` + `HeraldShardProjectile`, models/
renderers in `client/entity/` (`FerrymanModel`/`FerrymanRenderer`, `HeraldModel`/
`HeraldRenderer`), skins `textures/entity/ferryman.png` + `herald.png`, UV docs
`docs/uv/ferryman.md` + `herald.md`.

**Architecture finding (supersedes the briefing's GeckoLib framing):** these two bosses
are NOT GeckoLib mobs. There are no `geo/entity/{ferryman,herald}.geo.json` or
`animations/entity/*.animation.json` files — both are vanilla `HierarchicalModel`s
authored in Java (`createBodyLayer()` cube trees + fully procedural `setupAnim`), with
client-side eased pose clocks on the entities (`animAge`/`raiseLerp`/… — the repo's
"controller pattern" for these bosses; there are no `RawAnimation` constants to wire).
The briefing's scope therefore lands as: MODEL = `createBodyLayer()` geometry, ANIM =
`setupAnim` + entity clock fields, JSON validation = n/a (no Blockbench JSONs in this
cluster; nothing to keep in sync except Java-side bone names, which ARE audited below).
Glow layers: the repo's GeckoLib mobs use `AutoGlowingTexture` `_glowmask.png` pairs
(`EclipseGeoRenderer`), but this cluster uses the `RenderType.eyes` skipDraw pass over
the SAME sheet (Gazer pattern) — so "add emissive-map" lands as extended part-based glow
selections (Herald crown/halo joins), not a separate map.

Ground rules honored throughout:

- **Hitboxes/AI/balance untouched**: `EclipseEntities` sizes (Herald 2.2×3.2, Ferryman
  1.4×3.5, shard 0.4×0.4), attributes, every server-side fight timer/damage number and
  the whole `tickFight` scripting are byte-identical. All new entity code is inside the
  client-only `tickClientAnim` sections + new client accessor methods.
- **Existing bone names all kept** (Java `getChild` references, head tracking via
  `head`/`core`, emissive selections) — verified by a defined-vs-referenced audit after
  the edits; new bones are ADDITIVE.
- **Palette identity kept**: both v2 sheets repaint the exact placeholder-brief palettes
  (`docs/uv/*.md` art briefs) at 2× texel density; emissive regions stay bright (the
  eyes pass samples the same sheet).
- NO gradle, NO git. Validation after every pass: `javac --release 21 -proc:none
  -sourcepath src/main/java` over all 7 cluster files against
  `build/moddev/artifacts/neoforge-21.1.238-merged.jar` + `clientLegacyClasspath.txt` +
  Veil 4.3.0 + GeckoLib 4.9.2 + `build/classes/java/main` (BD-SHIP harness) — exit 0 at
  every checkpoint (only the repo-wide pre-existing deprecation note on
  `HeraldShardProjectile`, unchanged from baseline). Texture invariants scripted via
  Pillow (see Validation).

---

## 1. The Ferryman (day-14 finale boss)

### PLAN

Job: the drowned pilot — a floating robed rower whose whole fight is oar language
(rowing idle → raised telegraph → 180° sweep → planted P3) plus the lantern as the
emotional through-line (Gaze glow, death gutter). Emotional target: HEAVY dead water —
everything drags, nothing metronomes. Current weaknesses (code read): the sweep
telegraph raises the oar but the CONTACT frame doesn't exist (the raise just eases back
while the server deals damage — the biggest hit in the fight has no swing); the chain is
a bare 3-segment sine with constant amplitude (no pendulum feel, no reaction to his own
movement); the robe hem is 4 short strips with a single sway term; the idle body never
breathes (one bob sine); the death collapse is generic (bow + sink) despite the fight's
lantern-first storytelling; the skin is a 1px/texel placeholder.

### IDEATE

1. **Chain link crosspieces** — flat 2×2×1 cubes at each chain joint, alternating 0°/90°
   so the chain reads as interlocked iron instead of a rod. 3 cubes, zero anim cost
   (ride their parents). **ADOPTED.**
2. **Cloak lower tatters** — 3 longer 2×8×1 strips (flanks + back) as separate bones on
   a slower/deeper cadence than the hem strips, with torn ALPHA notches in the skin.
   **ADOPTED.**
3. **Lantern cap** — 3×1×3 iron crown the chain visually seats into. **ADOPTED.**
4. Oar grip collar cubes — **REJECTED**: the 2× repaint sells the leather wraps for
   free; cube budget better spent on the chain/tatters.
5. **Pendulum chain rework** — amplitude GROWS down the chain (0.22+0.08k — a bob leads
   its pivot), housing counter-swings against the last link (inertia), swing amplitude
   breathes (slow modulation) and scales with his actual deck drift (`swayBoost`,
   position-delta based). Keyframe-easing pendulum feel without any physics sim.
   **ADOPTED.**
6. **Sweep anticipation–contact–recovery** — anticipation = existing 25t raise, now with
   a body coil (yRot screw + slight crouch + skull looking up at the blade) and a
   late-windup quiver above raise 0.85; CONTACT = one-shot 14t whip fired on the
   telegraph's falling edge (the same tick the server deals sweep damage), ease-out
   cubic to a swung-through pose with body follow-through; RECOVERY = smoothstep back to
   the base blend. Client-only (`FerrymanEntity.sweepSwing`), guarded against
   kneel/death/phase-break cancels via the `raiseLerp > 0.6` + flags gate. **ADOPTED.**
7. **Idle breathing layer** — two incommensurate zRot roll sines on the body + slow head
   nod + arm shoulder drift; kneel swaps the bob for a heavier, slower breath + a skull
   bow (penitent read). **ADOPTED.**
8. **Death "collapse into the lantern"** — body lists toward the chain shoulder, skull
   turns to the last light, left arm reaches for it, chain swing stills and
   counter-rotates the list so the lantern hangs plumb while everything else folds; the
   existing server-side flame gutter (`isLanternFlameLit`) lands on top. **ADOPTED.**
9. Gaze presentation pose (chain lifted toward the marked player) — **REJECTED**: needs
   a 4th eased clock to avoid a pose snap on the synced flag, and the Gaze already owns
   a tell (lantern housing joins the glow pass + mark vignette + private bell).
10. Separate `_glowmask.png` — **REJECTED**: the `RenderType.eyes` pass samples the same
    sheet with part-level selection (eye slit / flame / lantern housing) — a mask adds a
    texture without adding capability here.
11. **2× skin repaint (256×256 over the frozen 128 UV space)** — vanilla normalizes UVs
    by the LayerDefinition size, so the sheet doubles with zero Java change: robe weave
    + salt tide line + barnacle colonies (denser at the waterline), skull cracks/socket
    rims/teeth, hood kept open-fronted (transparent north face), oar grain + leather
    grips + waterline stain, wet-iron chain glints, lantern frame with rivets + soul-lit
    glass gradient. Deterministic Pillow generator. **ADOPTED.**
12. Velocity-reactive robe lean (list into the movement direction) — **REJECTED**: the
    fight is telegraph-read-critical; a movement lean fights the coil/raise language for
    the same body bones.

### IMPLEMENT

Model (`FerrymanModel`, 17 → 24 cubes): `tatter0..2` (2×8×1 @ (24+i·8,76)), `link0..2`
(2×2×1 children of `chain{k}` @ y 3.5, alternating yRot), `cap` (3×1×3 child of
`lantern`); `setupAnim` rework per ideas 5–8 (breathing body/head/arms, strip zRot
cross-sway, tatter drag + flutter, pendulum chain + counter-swinging housing, coil +
quiver anticipation, one-shot contact whip with w-spike envelope, kneel breath + bow,
lantern-fold death with plumb chain). Entity (`FerrymanEntity`, client section only):
`SWEEP_SWING_TICKS`/`swingTicks`/`wasTelegraphing` one-shot clock + falling-edge trigger,
`swayBoost` eased position-delta drift factor, accessors `sweepSwing`/`swayBoost`.
Renderer: unchanged (new parts auto-join the skipDraw reset; emissive selection
untouched). Skin: `scripts/skin_gen/ferryman_v2.py` + shared
`scripts/skin_gen/boss_paint.py` (vanilla box-UV port of the `paint_lib` conventions —
directional face shading, inner outlines, hash dither, shadeless emissives). UV doc
updated (new cubes + 2× note + generator).

### POLISH PASS 2

- Contact pose deepened: the whip now swings THROUGH past horizontal (oar xRot target
  −0.35 → −0.1, arms follow) — the previous target parked the blade forward-up and read
  as a half-swing.
- `swayBoost` moved off `getDeltaMovement()` onto position deltas (`xo`/`zo`): remote
  entities lerp position while their synced velocity can sit stale, which would have
  frozen the drift boost at 0 for most viewers.
- Accepted (documented) quirk: a P2→P3 phase break mid-telegraph fires the whip without
  a damage event (the kneel path can't — the kneel flag lands the same tick and gates
  it). Reads as a frustrated lash into the transition; guarding it would need a synced
  "swept" event for a rare 14t cosmetic.

### POLISH PASS 3

- Cross-side audit: 2 new entity accessors ⇔ 2 model consumers; every animated field on
  every part (old + new) is assigned absolutely per frame (body.yRot/zRot and strip zRot
  were newly mutated — verified base-assigned before the additive terms); death block
  still forces the plant off the death clock (mid-death reload safe); `renderEmissive`
  skipDraw reset covers the new parts via `getAllParts`.
- Bone audit: `getChild` references ⊆ `addOrReplaceChild` definitions (scripted check,
  zero missing); head tracking (`head`), emissive parts (`eyes`/`flame`/`lantern`) all
  present.
- Skin invariants (scripted): hood north face 0 opaque px; eye slit / flame mean
  luminance 223/216 (bright, shadeless); robe north mean 37 (dark identity); tatter
  bottoms genuinely notched (57/64 opaque). Generator re-run byte-identical (md5).
- Re-validated javac — exit 0, no new notes.

---

## 2. The Herald of the Eclipse (day-7 boss)

### PLAN

Job: a broken godhead of black glass — hovering core + burning eye + corona of shards +
tentacle chains, fought in three phases with volley telegraphs ("shards glow"), the P2
gaze and the P3 collapse. Emotional target: WRONG GEOMETRY BREATHING — a hovering relic
that gathers, releases and finally comes apart in stages. Current weaknesses (code
read): all 4 tentacle chains whip in perfect sync (one shared phase); the volley
telegraph is glow-only (no gesture — the model doesn't DO anything before firing, and
nothing recoils after); phase breaks are a bossbar color + sound with zero body
language; the core never breathes (one bob sine); the death is one smooth uniform sag
(everything gives up at once); the skin is a 1px/texel placeholder with veins on one
face only.

### IDEATE

1. **Crown spikes** — 4 gold-tipped obsidian spikes (1×5×1) on the core's top corners as
   separate bones (children of `core`, so they track the look): idle shimmer, roar
   flare. **ADOPTED.**
2. **Floating halo shards** — 3 small crystals (1×3×1) on a new counter-rotating `halo`
   ring bone at r=9px between core and corona — visual depth + the volley's "ammo".
   **ADOPTED.**
3. **Phase-break ROAR** — client-detected off the synced phase (upward transitions only;
   `lastClientPhase` starts 0 so join/reload mid-fight can't fire a stale roar): 26t
   envelope (sharp attack, smoothstep release) rears the core up + back, swells the
   breathing scale, flares the crown out/up and splays every tentacle. Crown joins the
   `RenderType.eyes` pass while the envelope is hot (>0.35) — the "crown flare" is
   literal light. **ADOPTED.**
4. **Shard summon gesture** — eased weight of the synced telegraph flag
   (`telegraphAmount`): tentacles curl up into a claw (deeper per segment), core leans
   at its target, corona tips inward + spins up (accumulated `ringSpinExtra`, never
   rewinds), halo shards GATHER inward 3.5px. **ADOPTED.**
5. **Volley recoil kick** — 1→0 impulse (0.82/t decay) on the telegraph falling edge:
   core flinch, ring snap, corona flares back out, halo flung outward past rest radius
   (overshoot). **ADOPTED.**
6. **Tentacle desync + secondary sway** — per-chain phase offset (t·1.57) + a slower
   cross-axis zRot cosine; kills the metronome without touching the whip identity.
   **ADOPTED.**
7. **Core breathing scale pulse** — ±1.2% xyz scale on a slow clock (children inherit —
   the whole relic breathes); +5% swell through the roar. **ADOPTED.**
8. **Staggered death** — core sinks in three eased LURCHES (quantized smoothstep) instead
   of one slide; crown spikes keel over one by one (0.1 + 0.12i stagger); halo shards
   drop away and vanish (0.05 + 0.15i); tentacle chains die chain-by-chain (0.13t
   stagger, 0.3 window) — the wreck gives way joint by joint while the server's shard
   detach/crash choreography plays on top. **ADOPTED.**
9. Pupil dilation during the P2 gaze charge — **REJECTED**: the pupil is painted texels;
   animating it needs UV swapping or a second cube, and the gaze already owns beam +
   heartbeat + vignette tells.
10. Second corona ring (8 more shards) — **REJECTED**: `DATA_SHARDS_LEFT` maps 1:1 onto
    the 8 shard bones (P3 detach + death choreography); a decorative second ring breaks
    the HP→shards visual contract the fight teaches.
11. **2× skin repaint** — faceted glass core (coarse tonal patches + star dust + rim
    sheen), gold veins kept loud on the north face with dim hairline spill onto
    east/west/up, radial molten eye with the 2×2 void pupil + iris ring, crystal-gradient
    corona shards (dark root → hot tip, facet split), gold-tipped crown, hot-lavender
    halo, tentacles with joint banding + sheen column + sucker dots + fading tips.
    **ADOPTED.**
12. `HeraldShardProjectile` custom model — **REJECTED**: it renders as the umbral-shard
    item sprite by design (`ThrownItemRenderer`, fullbright, spin) — a model swap is a
    renderer replacement, not polish; entity untouched.

### IMPLEMENT

Model (`HeraldModel`, 26 → 33 cubes): `crown0..3` (1×5×1 @ (72+i·4,0), base lean 0.28
outward), `halo` bone + `halo0..2` (1×3×1 @ (72+i·4,8), r=9px); `setupAnim` rework per
ideas 3–8; `renderEmissive` gains `includeCrown` (roar) and pulls the halo into the
telegraph glow. Entity (`HeraldEntity`, client section only): `telegraphLerp` eased
gesture weight, `volleyKick` falling-edge impulse, `ringSpinExtra` accumulator,
`roarTicks`/`lastClientPhase` roar clock; accessors `telegraphAmount`/`volleyKick`/
`ringSpinExtra`/`roarAmount`. Renderer: emissive layer feeds
`isTelegraphing()` + `roarAmount(partialTick) > 0.35`. Skin:
`scripts/skin_gen/herald_v2.py` (same shared painter; vein random-walks precomputed,
seeded). UV doc updated (new cubes + 2× note + generator).

### POLISH PASS 2

- Corona gesture direction fixed: during the gather the ring shards now tip INWARD
  (−0.12·gesture) and only the recoil flares them out (+0.25·kick) — the first cut
  tipped them outward for both, which read as a flinch instead of a gather.
- Flare floor check: crown lean min = 0.28 − 0.1 (gesture) − 0.04 (shimmer) = 0.14 > 0 —
  no inversion when a roar and a telegraph overlap.
- Envelope monotonicity check: `roarAmount` rises then falls once — the >0.35 emissive
  gate opens/closes exactly once per roar (no glow flicker).

### POLISH PASS 3

- Cross-side audit: 4 new entity accessors ⇔ model/renderer consumers; every animated
  field on every part assigned absolutely per frame (tentacle zRot, crown x/z/y, halo
  x/z/y/zRot/visible, core scales were all newly mutated — verified); `haloShards`
  reset `visible = true` each frame before the death stagger hides them; `ringSpinExtra`
  float-precision growth bounded well past any realistic fight length (same class as the
  existing `animAge`).
- Bone audit: `getChild` ⊆ definitions (scripted, zero missing); `core` head-tracking
  and all emissive selections present.
- Skin invariants (scripted): inner-eye mean luminance 186 with pupil center 13 (void
  reads); crown north 145 (gold-lit); halo 215; shard 195; core north 42 (dark glass
  with veins). Generator re-run byte-identical (md5).
- Re-validated javac — exit 0, no new notes.

---

## Validation (final)

- `javac --release 21 -proc:none -sourcepath src/main/java` over all 7 cluster files
  (both entities, the shard projectile, both models, both renderers) against the moddev
  merged jar + legacy classpath + Veil 4.3.0 + GeckoLib 4.9.2 + compiled main classes:
  **exit 0** at every checkpoint (3 runs), only the pre-existing deprecation note.
- JSON validation: n/a for this cluster (no GeckoLib geo/anim JSONs exist for these two
  bosses — documented above); no resource JSONs were touched.
- Texture checks (Pillow, scripted): 256×256 RGBA both sheets; hood-front transparency,
  emissive brightness, dark-identity means, tatter raggedness all asserted; both
  generators deterministic (byte-identical md5 across re-runs).
- Bone-name audit: every Java `getChild` reference resolves against `createBodyLayer`
  definitions in both models (scripted defined-vs-referenced diff — empty).
- Hitbox/AI/balance freeze: `EclipseEntities` and both server fight scripts untouched;
  all entity diffs live in the client-anim sections + accessors.
