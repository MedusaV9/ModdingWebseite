# CUT-REPASS — fresh-eyes pass over all 9 cutscenes (post-v6, post-fix-wave)

Scope: `intro_v3_ship` / `intro_v3_flight` / `intro_v3_reveal` / `expansion_skyward` /
`expansion_flyover` / `unlock_ring` / `end_shatter` / `finale_return` / `credits_helm` after
the v6 reshoots (fxteams CUT-INTRO / CUT-EXPANSION / CUT-END / CUT-CREDITS) and the
EVAL-V6-CUTBD fix wave (wheel-caption retime to t=0.77, `end_shatter` ready-ACK beat-clock
arming via `CutsceneService.onNextClientReady`, the flyover `skimRadial` anchor projection,
C6 `validatedReturnPosition` healing on the global returns). The v6 shot designs stand —
this round polishes EXECUTION only: easing/velocity continuity, beat sync against the fixed
geometry/clocks, missing impact micro-shakes.

Method (THREE passes per cutscene — analyze → fix → re-verify):

- **Analyze**: a kinematics harness (`tools/repass_cutscenes.py`) mirrors `PathSampler`
  (same Catmull-Rom / damped-Hermite math, 64-sample arc-length LUT) and computes per
  segment: arc length, ticks, average blocks/tick, and JUNCTION velocities — because
  segments are arc-length reparameterized, in-segment speed = avgSpeed × easing derivative,
  so a junction where `v_out(seg i) ≠ v_in(seg i+1)` is a real on-screen velocity jump.
  Easing endpoint derivatives (per Veil's curves): `easeInOut*` = 0 at both ends;
  `easeOutSine` enters at π/2 ≈ 1.571; `easeOutCubic` enters at 3; `easeInQuad` exits at 2;
  `easeInCubic` exits at 3. Event timelines were replayed in ticks against
  `CameraDirector.fireEvents` semantics (shake = quadratic-decay impulse of `ticks` length,
  fade = in/hold/out envelope, captions render ABOVE fades) and against the sequence-Java
  beat constants (`SKYWARD_PUNCH_T`/`RING_HERO_T`/`FLYOVER_SKIM_T`, `WHEEL_SETTLE_AT`,
  `SILENCE_HOLD_TICKS`/`CRACK_RACE_STEP_TICKS`/`SEPARATION_FX_DELAY_TICKS`,
  intro flash-sandwich/bloom delays).
- **Fix**: surgical JSON edits only (one easing name or one event) — no keyframe positions,
  durations, flags, phase logic or payload shapes touched.
- **Re-verify**: harness re-run (all junctions 0→0 or design-covered), the REAL
  `CutscenePath.parse` + `PathSampler` Java harness over all nine documents (compiled
  against `build/classes` + the moddev classpath — 9/9 PASS, strict t-order, fov finite and
  in range), `javac --release 21 -proc:none` on the touched `CutscenePaths.java` (PASS),
  caption i18n parity re-checked (all caption ids in BOTH `en_us.json` and `de_de.json`;
  zero new keys, no langdrop), and every `eclipse:` sound id against `sounds.json`.

Hash bookkeeping (default-refresh contract): the PRE-EDIT SHA-256 of every edited bundled
JSON was appended to `CutscenePaths.LEGACY_DEFAULT_HASHES` (already `Map.ofEntries` since
CUT-INTRO's migration):

| id | pre-edit hash appended |
|---|---|
| `intro_v3_flight` | `c6ad4dfe2134c44d7c20e43f00deaba1bf26678a7695f0e2f1050c6a397f2ee8` |
| `expansion_skyward` | `dc276ae65d79aeed50152b7ece0a5c80b621ecde4456f9af6a2724a2e99dfcb5` |
| `expansion_flyover` | `6ad93e70e4f927edbdf98bde67fd6a158b548edf9f273e85a54810bd8f16e0bf` |
| `end_shatter` | `f79d338cb827d25399aef40c4eb754618bd31de98e893f18121ef72d8f0b2cb8` |
| `finale_return` | `31ab560550b02d8be49e45cc407acec05e289ef60db607012d0d05e1d4cb6fcb` |
| `credits_helm` | `fcabe22ea9fd2a54499fb6e17319defb8b740711e88576a8d356d917ae4f078d` |

`intro_v3_ship`, `intro_v3_reveal`, `unlock_ring`: byte-untouched, no ledger entries.

---

## 1. intro_v3_ship (130t, player-anchored) — CLEAN, no edit

All five junctions 0→0 (`easeInOut*` chain); the easeInCubic exit accelerates to 1.95 b/t
at t=1.0 by design, covered from t=120 (u≈0.923, v≈0.46 b/t at cover start) by the R13
portal glitch. FOV 70→62 monotonic vice (deliberate, "no breathing on this shot"). Keel
shake t=0.62 lands exactly on the −5-dutch keel keyframe where the segment velocity passes
through zero — impact + pause = weight, correct. Lurch (0.3) + groan (0.32) + wash (0.55)
ordering verified; depart whisper covers the slow-crane stretch (10→80 of a 70t caption vs
34t crane). Composition: lookAt player throughout, aim blend at kf0 verified against
`CameraDirector.orientate` (zero-weight at the degenerate camera==eye instant).

| beat | before | after |
|---|---|---|
| all | — | unchanged |

## 2. intro_v3_flight (900t, world-anchored) — 1 added event

Cruise banks/hesitation/dive all verified (junctions 0→0; the t=0.8 zero-velocity
"hesitation" is authored and sold by the storm_pulse sting at exactly 720). **Defect
found:** the wind buffet (t=0.86 → tick 774, 50t impulse) fully decays at tick 824, but the
fade only starts rising at 864 — the v6 POLISH-2 claim "flutter that overlaps the fade" was
arithmetically false, leaving the FASTEST 40 ticks of the dive (≈0.8→1.0 b/t) with a
perfectly smooth, turbulence-free camera right before the smoke wall. Fix: a second,
stronger wall gust at t=0.95 (tick 855, `0.2,36,3.6`) — alive through the whole fade rise
(864→880, envelope 0.56→0.14 across it), dead by 891 (< hold end 892). "Buffet building"
now reads as two rising gusts; approach caption (873) still renders above the fade.

| beat | before | after |
|---|---|---|
| dive commit sting | t=0.8 (720) | unchanged |
| buffet gust 1 | t=0.86 `0.14,50,3.2` (dead at 824) | unchanged |
| buffet gust 2 (wall) | — (40t shake-free gap at max speed) | t=0.95 `0.2,36,3.6` (live through fade rise) |
| fade out / caption | 0.96 / 0.97 | unchanged |

## 3. intro_v3_reveal (300t, world-anchored) — CLEAN, no edit

Junctions all 0→0; bearing drift monotonic (~0.59°/t peak), radius walk 48.3→34.0→32.3→
33.1→34.0 (single ease-in/out envelope, closest pass outside the r≤23 rubble band), FOV
breathes 60→57→55→56→58 with the minimum at the closest pass. Caption at 36 (silhouette
reads first), emerge at 150, settle rumble at 270 (ends 296 < 300). The silent 150→270
stretch is the authored reverent drift (audio-restraint doctrine). Exit lookAt +4 hands a
sky-facing frame to SUNRISE; title at 0.38 screen height stays in clear sky.

| beat | before | after |
|---|---|---|
| all | — | unchanged |

## 4. expansion_skyward (100t, bezier, player-anchored) — 1 added event

Launch grammar verified: dip → rush (FOV 70→85) → apex curvature hold → 130° tilt-up;
junctions 0→0 (bezier + `easeInOut*`); `SKYWARD_PUNCH_T = 0.40` matches the in-path fade at
t=0.4 and the server-scheduled `cutscene_veil` burst. **Defect found:** the cloud
punch-through — the shot's one physical CONTACT beat — was visual-only (fade + wisp), the
only impact in the whole cluster without a tactile mark (launch has its 0.18 jolt, the sky
hold its 0.1 rumble). Fix: a 10-tick `0.07,10,2.6` micro-buffet at t=0.4, synced to the
fade window (40→50 vs fade clear at 54); peak offset ~0.011 blocks — texture, motion-safe,
reducedFx-consistent (camera noise only). Apex whisper (60) and grade rumble (86)
unchanged.

| beat | before | after |
|---|---|---|
| launch jolt | t=0.16 `0.18,14,1.6` | unchanged |
| cloud punch | t=0.4 fade only | t=0.4 fade + `0.07,10,2.6` micro-buffet |
| apex whisper / grade rumble | 0.6 / 0.86 | unchanged |

## 5. expansion_flyover (220t, world-anchored, growth_front anchor) — 1 retimed event

Deck bob, FOV breathing (74→70→78→80→78→74→70) and junctions all verified. **Defect
found:** the fix wave landed the EVAL-V6-CUTBD defect-4 repair (`resolveGrowthFront` now
projects the skim-time keyframe offset onto the radial direction, so the camera's REAL
radius at `FLYOVER_SKIM_T = 0.5` sits just inside the led front for EVERY watcher angle —
the wave crossing is geometry-guaranteed at/just before the skim), but the `front_cross`
shake still fired at the pre-fix "representative" t=0.78 — now provably ~60 ticks AFTER
the crossing it names, on the pull-up instead of under the wave. Fix: retimed 0.78 → 0.5
(tick 110, the lowest deck at 6.5 blocks, the moment of maximum front proximity); payload
`0.14,18,0.8` kept — RingGrowthService's wave-tick-synced distance rumbles still ride on
top as the genuine continuous layer.

| beat | before | after |
|---|---|---|
| deck rumble | t=0.34 (74.8) | unchanged |
| front_cross shake | t=0.78 (171.6 — post-crossing since the defect-4 fix) | t=0.5 (110 — on the guaranteed skim crossing) |

## 6. unlock_ring (220t, world-anchored) — CLEAN, no edit

Hero stack lands as a correct audio→light→camera→impulse ladder: beam_hum 118.8 → bloom
rise 123.2 (peak 129.2–135.2) → hero-dip keyframe + awe rumble + server `cutscene_veil`
flare at 127.6 (`RING_HERO_T`·220 = 127.6, Java schedules 127 — co-timed). Junctions 0→0;
FOV 66→63→60→54→62→70 with the floor exactly on the hero dip; hero radius 38.5 (matches the
documented ~38); whisper (66→136) fades under the bloom but renders above it. Beacon pickup
sting at 11.

| beat | before | after |
|---|---|---|
| all | — | unchanged |

## 7. end_shatter (240t, world-anchored) — 2 easing swaps

Silence hold → crack race → separation verified against the fix wave's shared clock: beats
arm on the first `end_shatter` preload-ready ACK, so JSON t=0.1 (24) and the server's
`SILENCE_HOLD_TICKS = 24` rumble/first-flash now co-land; race steps (+4t, ≤52) sit inside
the JSON crack window; curtains/debris at +58 lead the carve bite. **Defect found (the
round's worst):** both settle legs carried `easeOutSine`, whose entry derivative is π/2 —
after the camera decelerates to a DEAD STOP on the t=0.9 rift-thud beat, it instantaneously
lurches to **3.40 blocks/tick** into the sink, and again to **1.72 b/t** at the t=0.955
turnaround (a turnaround must pass through zero velocity). The v6 log's own plan ("descend
… sink … then rise") reads as one continuous overshoot; the shipped easings broke it into
two lurches. Fix: both legs → `easeInOutSine`. Identical keyframe geometry (sink to 45.5,
rise +3), every junction now 0→0, the turnaround passes through rest like a real
overshoot-and-settle, and the thud lands on a held frame before the sink gathers.

| beat | before | after |
|---|---|---|
| silence → first crack | 0→24t (ACK-clocked) | unchanged |
| separation pull (quart) | t 0.42→0.72 | unchanged |
| return sweep | t 0.72→0.9, ends v=0 on the thud | unchanged |
| sink leg easing | easeOutSine — enters at 3.40 b/t off the stop | easeInOutSine — 0→0 |
| rise leg easing | easeOutSine — enters at 1.72 b/t at the turnaround | easeInOutSine — 0→0 |
| thud + settle shakes | 0.9 / 0.94 | unchanged |

## 8. finale_return (280t, player-anchored) — 1 easing swap

Warm open verified (cream fade 1/16/44, hum swells inside it at 11.2, dawn caption above
the fade at 16.8, altar-anchor lookAt → player handoff under the 90°/s clamp). **Defect
found:** the final handback leg carried `easeOutCubic` (entry derivative 3) — a 0→0.75 b/t
lurch at t=0.84, exactly on the emerge + settle-shake beat, and its front-loaded travel
parked the lens within ~1.4 blocks of the returning player's FACE (showOwnBody true) for
the last ~20 ticks of the shot — a near-clipped composition on the hero subject. Fix:
`easeInOutSine` — glides off the settle at zero velocity, spends the 11.2-block approach
evenly (≥1 block out until the last ~6 ticks), still arrives at rest in the watcher's own
eyes for the seamless handback.

| beat | before | after |
|---|---|---|
| open fade / hum / dawn caption | 0.0 / 0.04 / 0.06 | unchanged |
| emerge + settle shake | t=0.85 (238) | unchanged |
| handback leg easing | easeOutCubic — 0.75 b/t lurch on the settle, ~20t parked at the face | easeInOutSine — 0→0, even approach |

## 9. credits_helm (140t, world-anchored) — 1 easing swap

Fix-wave wheel whisper verified: t=0.77 → run ≈147.8 ≈ `WHEEL_SETTLE_AT` 148 (grip pull
148→158, relax 160). **Defect found:** the settle leg carried `easeOutCubic` — after the
dolly's full stop at t=0.78 (run ≈149.2) it resumed at 0.18 b/t, a camera micro-hitch
landing EXACTLY on the caption + grip-settle beat the fix wave had just aligned. Fix:
`easeInOutSine` — zero-velocity junction, peak settle speed ~0.096 b/t (still the "final
22% near-static settle" of the v6 design), so the hands-settle micro-anim plays over a
calm, continuous frame. FOV 66→63→60→58 squeeze and the fade/caption stack unchanged.

| beat | before | after |
|---|---|---|
| open fade / helm whisper | 0.0 / 0.12 | unchanged |
| wheel whisper | t=0.77 (run ≈148, fix wave) | unchanged |
| settle leg easing | easeOutCubic — 0.18 b/t hitch at run ≈149, mid-grip | easeInOutSine — 0→0, ≤0.096 b/t |

---

## Round summary

| cutscene | verdict | change in one line |
|---|---|---|
| `intro_v3_ship` | clean | — |
| `intro_v3_flight` | polished | terminal wall gust t=0.95 closes the 40t shake gap; buffet now truly overlaps the fade |
| `intro_v3_reveal` | clean | — |
| `expansion_skyward` | polished | cloud punch-through gains its missing 0.07 micro-buffet (felt, not just seen) |
| `expansion_flyover` | polished | front_cross shake 0.78 → 0.5, onto the now-geometry-guaranteed skim crossing |
| `unlock_ring` | clean | — |
| `end_shatter` | polished | settle legs easeOutSine → easeInOutSine (kills 3.4 / 1.7 b/t lurches at thud + turnaround) |
| `finale_return` | polished | handback leg easeOutCubic → easeInOutSine (kills 0.75 b/t lurch on the settle + face-park) |
| `credits_helm` | polished | settle leg easeOutCubic → easeInOutSine (kills the 0.18 b/t hitch on the grip beat) |

Self-checks: real `CutscenePath.parse` + `PathSampler` harness 9/9 PASS (strict t order,
finite in-range fov on every keyframe, lookAt shapes, event grammar); kinematics harness —
zero remaining junction velocity jumps outside design-covered exits (ship's glitch-covered
easeInCubic exit at t=1.0, flight's fade-covered easeInQuad dive end); caption i18n — all
14 caption ids present in BOTH `en_us.json` and `de_de.json`, zero new keys (no langdrop);
all `eclipse:` sound ids resolve in `sounds.json`; `javac --release 21 -proc:none` over the
touched `CutscenePaths.java` against the moddev classpath: PASS. NO gradle, NO git
mutations. Frozen surfaces untouched: keyframe positions/durations/flags, phase machines,
tick tables, payload shapes, replay contracts, the ready-ACK seam.

Deferred (noted honestly): the flyover crossing instant still shifts a few ticks earlier
than t=0.5 for slow waves (the −6-block inside margin divided by blocks-per-tick); an exact
per-play beat would need a server-fired shake at the measured crossing tick — sequence-Java
work beyond this round's JSON-polish scope, and the RingGrowthService distance rumbles
already cover the drift. The expansion_skyward tilt-up's eased angular peak (~136°/s for a
few ticks mid-segment) exceeds v6's quoted 68°/s average; it is keyed-slerp (the 90°/s
comfort law formally binds lookAt aims only) and reads as the authored dramatic whip —
left as shot design.
