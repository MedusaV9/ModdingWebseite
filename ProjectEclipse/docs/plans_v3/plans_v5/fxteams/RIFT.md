# FXTEAM-RIFT — rift tear / portal star / expansion-slam cluster

Team log (planner + ideators + polishers), process per component: PLAN → IDEATE 6+ →
IMPLEMENT → POLISH 2 → POLISH 3. Cluster: `veilfx/rift/RiftRenderer.java`,
`veilfx/rift/RiftFx.java`, quasar emitters `rift_spark` / `portal_surface_motes` /
`map_expand_materialize` / `growth_dust_wall` / `structure_slam_dust` / `slam_debris` /
`impact_light` / `eclipse_lightning_impact`, plus the portal-star FX consumed by
`xboxevent/XboxPortal` and `backrooms/BackroomsPortal` (server senders untouched — frozen
payload contracts). Self-checks: `javac` against the moddev classpath + Veil 4.3.0 jar,
and a JSON validator that parses every emitter, whitelists module ids against the module
registry extracted from the Veil jar bytecode, checks required codec fields
(trail/vortex/attractor/wind/size/color), gradient ordering, sprite existence, and
recomputes spawn/live-particle budgets. NO gradle, NO git.

Shared laws respected throughout: `reducedFx` (tier 1 halves rates, tier 0 kills AMBIENT;
renderer collapses to the pre-C7 single shell), `FxBudget` channels on every spawn, the
frozen ≤ 400-tri per-rift render cap, frozen payload/entry-point signatures, zero
per-frame heap allocations in the renderer, and the EVAL-POL-F #7 continuity law (all
time-scrolled patterns use whole cycles per 100 s `swirlSeconds` wrap).

---

## 1. RIFT CORE — `RiftRenderer.java` (tear body)

**PLAN.** The C7 tear is 5 counter-rotating shells + edge arcs (continuity fixed last
round) with adaptive size. Asks this round: interior "void depth" illusion, event-horizon
rim distortion, forking arc strikes. Post-hook check FIRST (user question): a fullscreen
post stack exists (`VeilPostController`, ≤ 3 concurrent passes) and there is even a
screen-space shockwave feed (`EclipseFxState.startShockwave`) — but every post pass is
hard-gated off under Iris (`EclipseIrisState.postFxAllowed`) and the rift renderer is
explicitly the *Iris fallback* (§7). A refraction post pass would delete the effect for
exactly the players the renderer exists for, and would burn one of the 3 pass slots per
rift. Verdict: **fake it with additive rim geometry** (the brief's own fallback).

**IDEATE.**
1. Void well: 2 dark fans behind the star pushed along the camera→rift axis (the portal
   swirl's parallax trick, deeper + darker) → interior visibly recedes as you strafe. ✔
2. Lensing rim: dashed additive band outside the fringe whose brightness pattern scrolls
   *against* the shell spin — light smearing backwards around a rim is the classic
   gravitational-lensing tell. ✔
3. Forking arcs: first two arcs grow a thinner, dimmer branch at 40 % length when their
   strobe gate runs hot (> 0.72) — forks strobe rarer than arcs. ✔
4. Depth-tinted shells (rear shells darker): rejected — fights `SHELL_FADE`'s additive
   falloff which already encodes depth; double-encoding muddies the core.
5. True refraction via `sub_emitter` screen-copy tricks: rejected, no such hook; post
   stack Iris-gated (see PLAN).
6. Per-arm "tearing" vertex jitter increase: rejected — VFXPOLISH-3 already deepened arm
   shudder to 0.82; more reads as noise at 14 arms.
7. Void well as star-shaped (perimeter-matched) fans: rejected on budget (28 tris/layer
   vs 12) — the well sits inside the valley floor where a circle is indistinguishable.

**IMPLEMENT.** `buildVoidWell` (alpha pass, STRUCTURE only, full quality): 2 × 12-seg
fans at 0.34/0.21 of the tear radius, pushed 0.35/0.80 × `clamp(width·0.10, 0.25..1.4)`
blocks along the view direction, deeper layer darker (α 0.80/0.92), colored `dim·0.6`.
`buildLensing` (additive): every-other perimeter pair → 14 quads from fringe-inset to
`width·0.075` out, per-vertex brightness `0.55+0.45·sin(k·0.9 + scroll)` with
`scroll = swirlSeconds · 2π/100 · −40` (whole cycles per wrap). Fork branch in
`buildArcs`: `FORK_X/Y/Z[4]` static scratch, base at arc point 2, 3 segments diverging
±0.34 rad (side hash-picked per flicker frame), half width, α 0.60 · gate; ribbon
emission extracted into `emitBillboardSegment` (camera-extruded, StormWall pattern) now
shared by arcs, forks and entry streamers.

**POLISH 2 (correctness).** Lensing scroll originally `swirlSeconds·ROTATION_SPEED·−1.9`
— popped at the 100 s wrap; rewritten to whole-cycle form (−40 cycles/100 s ≈ same speed).
Void well early-outs when the camera sits inside the tear (`len < 1e−3`, no parallax
direction). Fork reuses the parent's gate so a dark arc can never show a floating fork.

**POLISH 3 (budget + tuning).** Full recount in the class javadoc: STRUCTURE
140+84+56+30+12+28+24 = **374**, PORTAL/BACKROOMS 140+28+56+30+12+28+48 = **342** steady
(+32 ping ⊕ 24 flash, mutually exclusive) = **≤ 374** — both under the frozen 400 cap.
Paid for by two honest trims: portal-like tears keep the inner hot fan on the center
shell only (the discs cover the center anyway), forks limited to 2 arcs × 3 segments.
`reducedFx` = exactly the pre-C7 single shell (no arcs/forks/lensing/void/ping).

---

## 2. RIFT CORE — `RiftFx.java` (lifecycle + delivery surge)

**PLAN.** Asks: materialization sparks "sucked IN before delivery then burst OUT on each
piece launch". The client never sees `StructureFlightFx`'s piece spawns — but it DOES see
the delivery's signature: the flight `open()` re-sends `fx/rift_open` on top of the
live beat tear (the documented "surge convulses the tear" replace). That replace is the
client-side delivery detector; batch launches then follow the server's fixed 6-tick
stagger from that instant.

**IDEATE.**
1. Detect STRUCTURE-replacing-STRUCTURE opens as surge start. ✔
2. Inhale: park the existing `portal_surface_motes` loop (vortex + point-attractor =
   sucked inward, now with orbit trails) at the mouth for 20 t, then remove. ✔ (zero new
   assets)
3. Burst OUT: one `map_expand_materialize` one-shot at the mouth every 6 t for 36 t —
   mirrors `BATCH_STAGGER_TICKS`, so bursts land on actual batch launches. ✔
4. New dedicated `rift_inhale.json` emitter: rejected — motes emitter already IS the
   suck-in behavior; new asset = new budget surface for no new read.
5. Parse whoosh sounds to time bursts: rejected, fragile and reversed dependency.
6. Server-side payload additions: rejected — frozen payload set, out of cluster.
7. Surge also on portal styles: rejected — portal re-sends are login resyncs
   (exactly-once per stay, `XboxPortal.FX_SYNCED`), not deliveries.

**IMPLEMENT.** `openRift` flags `surge` when a live non-closing STRUCTURE rift is
replaced by a STRUCTURE open (frozen signature untouched); `Rift.tickSurge` runs the
inhale loop (SEQUENCE channel, `spawnManaged`, handle removed at window end and in
`removeEmitters`) and the 6-tick launch bursts (`QuasarSpawner.spawn`, SEQUENCE, silent
budget drops). `reducedFx`: no inhale, burst cadence halved (12 t). Also mapped C18's
reserved style byte here — see §3.

**POLISH 2.** Inhale emitter also torn down when the surge window is skipped mid-way
(rift replaced again / closing) — `tickSurge`'s out-of-window branch removes it; disposal
covered in `removeEmitters` so logout/dimension-change can't leak the loop. Surge spend:
1 loop + 7 one-shots per delivery ≪ SEQUENCE's 60/window burst ceiling.

**POLISH 3.** Class javadoc documents the FXTEAM additions and the surge heuristic's
honest limits (a genuine double-send would false-positive once; budgeted and harmless).

---

## 3. PORTAL STAR — styles, breathing, ping, entry moment
(`RiftFx` + `RiftRenderer`; senders `XboxPortal`/`BackroomsPortal` read-only)

**PLAN.** Portals are frameless star-rifts (C16). Asks: idle breathing with a periodic
"pulse ping" ring, and an entry moment (iris-open flash + streamer whoosh). Found gap
while auditing senders: `BackroomsPortal` ships style byte 2 (C18's reserved coordinate,
"until C7's volumetric renderer maps it") — the tear currently renders as a FLAT sky-tear
with no portal surface. Mapping it is portal-star completion work, in-cluster.

**IDEATE.**
1. `STYLE_BACKROOMS = 2`: upright orientation + void/swirl discs + motes + WAX-GOLD
   palette (per-rift `hot/mid/dim` triple chosen at construction; violet elsewhere). ✔
2. Ping as pure function of time (`(now − openTick + seed&63) % 90`): zero state, all
   clients agree, neighbouring portals de-phased by seed. ✔
3. Entry detection client-side: any non-spectator player within `width·0.35` of the star
   center (mid-height), 60 t per-rift cooldown → iris flash + streamers + local
   `event.rift_whoosh` + one rim-spark burst + glitch pulse if the entrant is YOU. ✔
4. Breathing: reuse the VFXPOLISH-3 core-breath sine to scale BOTH portal discs
   (±8 %, seed-phased) — one shared `breathe()` helper, no new motion language. ✔
5. Ping as a quasar ring emitter: rejected — a crisp expanding ring wants geometry, not
   14 billboards; and geometry is free of spawn budgets.
6. Audible ping every period: rejected — 90 t cadence near a base would be fatiguing;
   the whoosh stays reserved for actual entries.
7. Entry flash via `TransitionFx.glitchPulse` full-screen only: rejected — bystanders
   would see nothing at the portal itself; world-space flash serves everyone.
8. Hooking the server teleport payload for entry: rejected — `S2CPortalFxPayload` covers
   only the entrant's screen fade, and senders are out of cluster.

**IMPLEMENT.** `Rift.portalLike` + palette fields; `orientedNormal` stands style 2
upright; motes/discs gate on `portalLike`. Renderer: `buildPing` (16-quad ring detaching
from the rim, travels 0.85 × radius over 22 t, α (1−t)²·0.5) and `buildEntryFlash`
(12-seg hot iris fan snapping open + 6 camera-extruded streamers with seed spin, 12 t),
mutually exclusive so the transient budget never stacks. `Rift.tickEntryWatch` drives
`entryFlashTick`. Backrooms palette: hot `#FFF5DB`-ish, mid `#FAC04D`-ish, dim umber —
arcs, fringe, discs, lensing, ping and flash all read from the triple, so the gold
variant costs zero extra code paths.

**POLISH 2.** Flash suppressed until `OPEN_TICKS` so a portal opening around a standing
player doesn't insta-strobe; spectators ignored; cooldown prevents conga-line strobing;
`reducedFx` keeps only the 12-tri iris fan (entry feedback is gameplay-relevant, not
candy). Purple spark/mote emitters intentionally stay shared for backrooms — geometry
carries the gold read; the mod's glitch-purple particle language stays uniform (same call
the server-side fallback made with `WAX_ON`).

**POLISH 3.** Ping thickness eases down as it travels (reads as dissipation); ping and
breathing both derive phase from the seed so no two portals sync; budget notes in §1.

---

## 4. `rift_spark.json` — rim crackle

**PLAN.** Loop emitter walked along the rim by `RiftFx` every tick. Ask: support the
forked-arc language at particle scale.

**IDEATE.** (1) short `veil:trail` filaments ✔; (2) higher velocity stretch for spark
elongation ✔; (3) snappier lifetime 10→9 ✔; (4) point-attractor suck-in — rejected
(emitter origin is the rim point itself, would just clump); (5) additive→false for soot
— rejected, crackle must glow; (6) more spawns — rejected, spawn budget frozen;
(7) sharper strobe alpha — deferred, current 6-point strobe already reads.

**IMPLEMENT.** Trail (len 4, width 0.03, lilac α 0.4), `velocity_stretch_factor`
0.35→0.6, lifetime 9.

**POLISH 2.** Trail keys byte-identical to the proven `offering_swallow`/`glide_trail`
schema; steady-state live ≈ 6 particles (validator).

**POLISH 3.** Trail alpha kept ≤ 0.4 so filaments never out-glow the arc geometry.

---

## 5. `portal_surface_motes.json` — portal surface / surge inhale

**PLAN.** Ask: orbit trails with tail fade. Doubles as the surge inhale (§2) — same
motion (orbit + suck-in), new legibility.

**IDEATE.** (1) `veil:trail` len 10 with translucent tail ✔; (2) vortex 0.015→0.05 for
visible orbital arcs ✔; (3) attractor 0.012→0.02 (stronger inhale) ✔; (4) face_velocity
+ stretch 0.7 → motes streak along their orbit ✔; (5) lifetime 45→50 (longer orbits) ✔;
(6) second counter-orbiting emitter — rejected (new asset + double budget for symmetry
candy); (7) trail `parentRotation` — rejected, billboard trails suffice.

**IMPLEMENT/POLISH 2.** As above; range 7 / local-position vortex+attractor untouched so
the surge reuse at STRUCTURE mouths keeps working. Spawn rate untouched (5/s).

**POLISH 3.** Trail width 0.035 < mote size 0.07 — tail reads as fade, not ribbon.

---

## 6. `map_expand_materialize.json` — materialize twinkle / launch burst

**PLAN.** Serves three sites: `RingGrowthService` column materialize, new-land ambient
motes, and now the §2 launch bursts. Ask: "sucked in … then burst out" — the converge
half lives here; the OUT timing comes from the surge cadence.

**IDEATE.** (1) local `point_attractor` (range 3, strengthByDistance) so the cube shards
CONVERGE on the spawn point ✔; (2) livelier pop: speed 0.04→0.14 + new drag 0.25 so
shards leap then hang ✔; (3) alpha peak moved to 0.3 (materialize "snap") ✔;
(4) `init_random_rotation` — rejected, `random_initial_rotation` already set;
(5) `veil:size` growth — rejected here (uniform size would kill the per-shard variation
that sells rubble); (6) negative-strength attractor for pure explosion — rejected, would
break the terrain-materialize read at its other two call sites; (7) block-display chunks
— out of scope per brief ("keep particles").

**IMPLEMENT/POLISH 2.** Attractor + drag inserted after `veil:block`; validator confirms
codec fields (`localPosition`/`strengthByDistance` camelCase, proven in motes JSON).

**POLISH 3.** Burst live ≈ 36 shards for 16 t — surge worst case (7 bursts + inhale +
spark) ≈ 90 live ≪ 1500 cap.

---

## 7. `growth_dust_wall.json` — expansion dust curtain

**PLAN.** Ask: rolling front with tumbling debris (particles only, vary sizes/rotation)
+ leading-edge glow.

**IDEATE.** (1) size spread 2.6±1.2 → 2.2±1.9: chunky boulders-in-dust mix ✔;
(2) leading-edge glow by AGE, not position — the front line is where the freshest
particles are, so a bright-lilac birth color + fast alpha ramp IS the leading edge,
honestly ✔; (3) wind straightened to pure up (was +0.15 z — wrong for most arc
directions) and strengthened, speed 0.14 with random speed = differential tumble ✔;
(4) drag 0.06 so the wall rolls then hangs ✔; (5) lifetime 36→42 (taller curtain) ✔;
(6) fixed-axis horizontal vortex for literal rolling — rejected: JSON axis is world-fixed
but the wall spawns along an arbitrary arc; wrong for half the compass; (7) second
block-chunk emitter — rejected (sender `ExpansionSequence.ClientHooks` is out of
cluster; one emitter id per pulse is the frozen seam).

**IMPLEMENT/POLISH 2/3.** Gradient `#9D86C9 → #473A63 → #241C38`, α 0→0.38@12 %→0.26→0;
alpha ceiling kept < 0.4 — the curtain must veil terrain, not paint over it.

---

## 8. `structure_slam_dust.json` — slam dust mushroom

**PLAN.** Ask: ground shock ring decal + dust mushroom + lingering. The expanding shock
RINGS already exist server-side (IDEA-14 §2: 6-point emitter rings at t+6/t+12 — the
"decal" read); this emitter's job is the mushroom + linger.

**IDEATE.** (1) gravity 0.35→0.16: dust stops raining, columns and hangs — mushroom cap ✔;
(2) lifetime 26→36 + long alpha tail (0.28 @ 80 %) = lingering pall ✔; (3) bigger softer
puffs 0.9±0.5 ✔; (4) speed 0.5 for a harder initial punch ✔; (5) `veil:size` growth —
rejected: uniform tick-size kills the size variation that makes dust read granular;
(6) ember tint in gradient — rejected, embers are `slam_debris`'s job (palette
separation); (7) collision — rejected, `should_collide` costs and the hemisphere spawn
already hugs the ground.

**IMPLEMENT/POLISH 2/3.** Drag 0.9→0.7 so the punch carries before the hang; alpha curve
0.9→0.55@45 %→0.28@80 %→0. Burst spend unchanged (15 emitter spawns/slam, the frozen
BURST window fit from IDEA-14 §2 — only per-particle look changed).

---

## 9. `slam_debris.json` — lingering ember rain

**PLAN.** Ask: lingering ember rain out of the closing tear (sent twice per slam at the
rift mouth).

**IDEATE.** (1) additive ON + hot→dark violet gradient: glowing embers that cool as they
fall ✔; (2) `veil:trail` len 5: falling streak read ✔; (3) lifetime 40→52±14: embers
reach the ground from 26 blocks up ✔; (4) drag 0.6→0.35 + speed 1.0: wider, longer arcs ✔;
(5) gravity kept 0.8 (it's rain, not ash); (6) collision die — rejected (cost, and
embers winking out mid-air reads fine); (7) sub-emitter sparks on "impact" — rejected,
`sub_emitter_collision` needs collision on.

**IMPLEMENT/POLISH 2/3.** Gradient `#EFE4FF→#B98CFF→#7B4FD0→#3A2C5E`, α 1→0.85@60 %→0;
face_velocity + stretch 0.25 already present, trail width 0.05 tuned under the 0.4 α so
streaks don't bloom into ribbons. Live ≈ 36/burst (validator).

---

## 10. `impact_light.json` — impact flash

**PLAN.** Shared emissive pop (slams, wand restore, lightning). Ask (portal star / slam
support): a flash that BLOOMS instead of a static sprite.

**IDEATE.** (1) `veil:size` molang `1.2 + q.agePercent * 3.4`: the flash expands as it
dies — reads as a shock bloom / iris ✔ (uniformity is fine at count 3; module verified
against the jar: same molang env as the proven `veil:color` interpolant, worst-case
failure is a logged exception, not a crash); (2) lifetime 5→7 ✔; (3) faster alpha knee
(0.6 @ 30 %) so the bloom is bright-short-soft ✔; (4) `veil:light` dynamic light —
rejected, §7 explicitly bans FX dynamic lights here; (5) ring texture — rejected, no new
art assets; (6) doubling count — rejected, spawn budget frozen.

**IMPLEMENT/POLISH 2/3.** First in-repo `veil:size` use — documented here as the
reference pattern (string molang, `q.agePercent` only). `base_particle_size` now inert
(overridden per tick); left in place for schema compatibility.

---

## 11. `eclipse_lightning_impact.json` — strike spray

**PLAN.** Grouped with the portal-star cluster (shared strike language with the rift
arcs). Ask: spray that FORKS like the new arc geometry.

**IDEATE.** (1) `veil:trail` len 4: every spark drags a filament — the fork read at
particle scale ✔; (2) stretch 1.6→1.9: harder radial lances ✔; (3) drag 0.9→0.65 +
gravity 0.22→0.3: sparks carry further then bend down (real strike splash) ✔;
(4) lifetime 9→11 with a 0.25 α shelf at 85 %: brief ionized afterglow ✔; (5) second
ring-shaped ground emitter — rejected (sender out of cluster, one id per strike);
(6) white→gold ramp — rejected, strikes stay in the violet eclipse language.

**IMPLEMENT/POLISH 2/3.** As above; burst live ≈ 42 ≪ cap. Alpha shelf kept below 0.3 so
the afterglow never reads as smoke.

---

## Self-check results

- `javac` (moddev classpath + Veil 4.3.0 + molang-compiler + fresh `TransitionFx.java`
  from the concurrently-landed GLITCH-team ambient feed): **PASS** for
  `RiftRenderer.java` + `RiftFx.java`.
- JSON validator (parse, module whitelist from jar bytecode, required codec fields,
  trail-settings schema, gradient monotonicity, sprite existence, spawn/live budgets):
  **PASS** for all 8 emitters. Steady/burst live counts: spark 6, motes 12.5,
  materialize 30 (5 waves × 6), dust wall 12, slam dust 48, debris 36,
  impact 6 (2 waves × 3), lightning 42 — worst realistic stack ≪ 1500 live cap.
- Render budget recount (class javadoc): STRUCTURE 374 / PORTAL 342+32 ⊕ 24 ≤ 374 —
  under the frozen 400-tri cap; `reducedFx` = pre-C7 geometry + 12-tri entry-flash fan.

## Deferred (noted honestly)

- Slam ground shock-ring *decal* (a flat world-space ring quad): needs a renderer at the
  slam site; `RiftRenderer` only knows tears, and the closing tear is 26 blocks above
  the impact. Candidate: tiny `SlamRingRenderer` fed by the existing `fx/shockwave`
  payload — out of this cluster's write scope.
- Backrooms-gold particle variants (spark/motes): would need per-instance emitter tinting
  Veil doesn't expose, or duplicate gold JSONs; geometry carries the gold read for now.
