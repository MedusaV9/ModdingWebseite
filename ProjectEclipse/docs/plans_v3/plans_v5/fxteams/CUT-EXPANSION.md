# CUT-EXPANSION — map-expansion cutscene / camera-beat cluster

Team log (planner + ideators + polishers), process per shot: PLAN → IDEATE 6+ →
IMPLEMENT → POLISH 2 → POLISH 3. Cluster: cutscene JSONs `expansion_skyward` /
`expansion_flyover` / `unlock_ring`, `sequence/ExpansionSequence.java` camera/FX beat
timings, and the CAMERA-FACING presentation timing around `StructureFlightFx` deliveries.
**File ownership (frozen for this round)**: this team owns the three cutscene JSONs +
`ExpansionSequence` beats (+ the `CutscenePaths` legacy-hash ledger); BD-STRUCT owns
`StructureFlightFx.java` internals — read here only to sync cadence facts (batch stagger
6 t, flights 30–60 t, landing thud/shake 0.12/8 with a 4-tick cooldown, mouth height 26
mirroring `SKY_RIFT_HEIGHT`). Self-checks: `javac` against the moddev classpath
(`build/moddev` neoforge-merged jar + `build/classes` + gradle module cache) and a JSON
validator that mirrors `CutscenePath.parse` (keyframe order/range, easing whitelist,
event grammar, caption-key localization incl. the langdrop, registered sound ids, shake
caps, fade color format) plus JSON↔Java constant sync. NO gradle, NO git.

Shared laws respected throughout: caption events carry TRANSLATION KEYS only (new keys
ship via `docs/plans_v3/langdrop/CUT-EXPANSION.json`, en_us + de_de — never hand-edit the
lang JSONs); `reducedFx` safety (path events are camera/HUD primitives — fade/shake/
caption spawn zero particles; the only added spawns are single one-shot `cutscene_veil`
Quasar payloads per watcher, budgeted client-side like every other one-shot); frozen
payload/entry-point signatures untouched; every changed bundled JSON's PRE-EDIT SHA-256
appended to `CutscenePaths.LEGACY_DEFAULT_HASHES` (existing default-refresh mechanism) so
stale config copies upgrade in place.

---

## 1. SKYWARD RISE — `expansion_skyward.json` (+ `ExpansionSequence.scheduleSkywardPunch`)

**PLAN.** The old shot was a standing tilt (rise 1.6 → 5.8, fov narrowing 70 → 56) — no
launch, no altitude, nothing "skyward" about it. Asks: launch with FOV 70→85 rush,
world-curvature reveal at apex, cloud-layer punch-through (veil wisp burst). Player-
anchored bezier is right for this (offsets from the watcher's feet; bezier settles at the
apex and the sky hold instead of overshooting).

**IDEATE.**
1. Anticipation dip: t .12 keyframe crouches to y 1.3 / pitch +6 before the kick —
   coil-then-launch is the cheapest read of acceleration. ✔
2. FOV rush 70 → 78 → **85** across the ascent, easing back to 60 for the sky hold —
   wide FOV during vertical motion IS the speed read (CameraDirector lerps per-keyframe
   fov and eases back into the player's own FOV at the end). ✔
3. Cloud punch-through at t .40: 2/2/10 translucent pale-lilac fade (`#59EFE8FF`) in-path
   + one `cutscene_veil` wisp burst per watcher, server-scheduled at the same flight
   fraction (`SKYWARD_PUNCH_T = 0.40`, `SKYWARD_PUNCH_HEIGHT = 30` ≈ the path's y offset
   there). The burst is the proven submerge/emerge veil asset — zero new emitters. ✔
4. World-curvature reveal: pitch stays DOWN (+44 → +58) through 30 → 46 blocks so the
   receding disc's rim curve fills the frame at the apex; only then the 130°-in-38-ticks
   tilt up into the darkening sky. New whisper caption at t .60 (localized). ✔
5. `event.sky_launch` kick at t .14 + a sharp 0.18/14/1.6 launch jolt; the old 0.85
   shake becomes a low 0.10/18/0.7 grade rumble under the sky hold. ✔
6. Corkscrew roll during the ascent — rejected: a forced camera with roll spin is a
   motion-sickness risk and the FOV rush already carries the speed.
7. `lookAt: "player"` on the way up (look back at yourself) — rejected: `showOwnBody`
   defaults false for possessed-camera shots; a floating frozen body reads as a bug and
   breaks the anonymity language.
8. A real cloud layer (volumetric or an emitter curtain at cloud height) — rejected: no
   cloud hook in cluster scope; fade + wisp burst is the honest 2-primitive read.

**IMPLEMENT.** 7 keyframes / 100 ticks (was 4 / 80): dip → rush (y 14/30, fov 78/85) →
apex curvature hold (y 46, pitch 58, fov 76) → tilt up (pitch −20 → −72, fov 60).
Events: drone t .02 (kept), sky_launch t .14, launch jolt t .16, punch fade t .40, apex
whisper `eclipse.caption.expansion.apex` t .60, grade rumble t .86.
`ExpansionSequence`: `beginSkyward` caption 70 → 90 t (longer shot), new
`scheduleSkywardPunch(server, run, watchers)` sends one
`S2CQuasarPayload(CUTSCENE_VEIL)` per watcher at `durationTicks · SKYWARD_PUNCH_T`,
per-watcher position + 30 y, per-watcher send (a remote watcher's burst would be
subpixel). Replay `SKYWARD` gets the same call with `run = null` (parity).

**POLISH 2 (correctness).** Punch helper skips when the path is missing/disabled — the
play callback already ran synchronously and a burst would flash over free gameplay. Run
guard (`ended` / superseded) + `hasDisconnected` per watcher at fire time. Server-tick vs
client flight-clock drift is bounded by the preload hold, which for a player-anchored
path at the watcher's own loaded position releases ~immediately — burst lands inside the
10-tick fade window. A watcher who SKIPPED sees one soft overhead wisp burst — harmless,
noted. Easing names restricted to the shipped-proven set (easeInOutSine/easeInOutCubic/
easeOutCubic) — unknown names silently fall back to linear, so no experiments here.

**POLISH 3 (tuning).** Apex pitch capped at 58° (down) so the up-tilt is ≤ 130° over the
last 38 ticks ≈ 68°/s — brisk but under the engine's 90°/s lookAt slerp comfort law.
Fade alpha 0x59 (≈ 35 %) — a veil, not a whiteout; `reducedFx` unaffected (fade is a HUD
quad). Class javadoc timeline updated (~80 → ~100 ticks).

---

## 2. GROWTH-WAVE FLYOVER — `expansion_flyover.json` (+ `resolveGrowthFront` lead sync)

**PLAN.** The old path floated at 14–45 blocks — an aerial, not a flyover. Asks: LOW
skimming pass over the NEW terrain with terrain-hugging altitude variation, the growth
wave visible as a rolling front below, timing synced with the actual GrowthWave service
tick where exposed. Exposed seams found: `RingGrowthService.progressFraction` (live front
radius), `GrowthPacing.targetTicks()` (the pacing law animated sweeps steer toward), and
`RingGrowthService`'s own distance-scaled rumble pulses every `growth.shakeEveryRings`
rings — those already fire DURING the shot and are the genuine wave-tick-synced rumble.

**IDEATE.**
1. Dive-to-deck altitude profile: y offsets 42 → 18 → **9 → 6.5 → 11 → 8** → 34 — the
   9/6.5/11/8 bob IS the terrain-hugging variation (offsets ride the anchor's terrain
   height; the anchor sits 6 blocks inside the front on already-written ground). ✔
2. FOV opens to 80 on the deck (74 approach, 70 finish): near-ground + wide = speed. ✔
3. Lateral sweep along the front (x −95 → +50) with ground-level lookAts (y 2–4) so the
   wavefront terrain stays in frame from every approach angle. ✔
4. Anchor-lead sync to REAL wave speed: lead = `(toR − fromR) / targetTicks ·
   flyoverTicks · FLYOVER_SKIM_T(0.5)`, clamped to the remaining width — the rolling
   front passes beneath the camera mid-skim instead of only catching up at the shot's
   end (old code scaled the REMAINING width by `flyoverTicks/targetTicks`, which
   under-leads mid-sweep replays and aims at the shot end, not the skim). ✔
5. Keep in-path shakes LIGHT (0.10 dive rumble t .34, 0.14 front-cross t .78; the old
   mid-shot 0.15/30 deleted) because RingGrowthService's wave-synced 0.08–0.5
   distance-scaled rumbles ride on top for every watcher near the front. ✔
6. True per-frame heightmap hugging — rejected: the flight is a pre-sampled client
   spline (arc-length reparameterized at flight start, `PathSampler`); per-frame height
   queries are outside the engine contract and would jitter across the fresh chunk seam.
7. 9+ keyframes for micro-bob — rejected: catmullrom through 7 already bobs; extra
   control points fight the arc-length reparameterization and read as drift.
8. Roll banking beyond ±3° — rejected: aircraft language, off-tone for a possessed
   witness camera.
9. Path-timed `growth_dust_wall` spawns — rejected: `ClientHooks.handleWavePulse`
   already walks the curtain along the ACTUAL wave pulses (the honest source); path-timed
   spawns would desync from the real front.

**IMPLEMENT.** 7 keyframes / 220 ticks as above; events: drone t .02 + growing caption
t .15 (kept), deck rumble 0.10/16/0.7 t .34, front-cross 0.14/18/0.8 t .78.
`ExpansionSequence.resolveGrowthFront`: lead formula per idea 4 (`FLYOVER_SKIM_T = 0.5`
documented against the path's lowest keyframe t .48; validator asserts they stay within
0.05). Final keyframe pulls up into a high wide hold over the new land — deliberately the
hand-off framing for shot 3's rift beats.

**POLISH 2 (correctness).** No-run resolver case (`fromStage == toStage`) degrades to
lead 0 exactly as before (width 0). Lead clamp keeps the anchor on terrain that will
exist; the anchor already sits 6 blocks INSIDE the front so the height lookup lands on
written ground (unchanged). Growing caption stays inside the shot; `beginGrowth` still
covers the no-cutscene path.

**POLISH 3 (tuning).** Lowest deck at 6.5 blocks over anchor terrain — under 5 risks
clipping terrain that undulates away from the anchor column's height. Front-cross shake
freq 0.8 (heavy roll-under, not a rattle). Offsets are absolute-axis (world-anchor
contract), so the radial crossing direction varies per play — the t .78 cross beat is
representative, noted honestly.

---

## 3. RIFT DELIVERY VIEW — `ExpansionSequence` STRUCTURES beats (JSON-less shot; free camera)

**PLAN.** R11 deliberately returns control before STRUCTURES — the "shot" is the choreo
of server beats around a free camera, and BD-STRUCT's delivery flight now fills the
trigger → PLACED window. Asks: hold a wide establishing angle when pieces launch; camera
micro-shake per landing. Cadence facts read (not touched) from `StructureFlightFx`:
`begin()` at trigger re-opens the tear (surge) + 0.25/14 shake, batches launch every 6 t,
pieces fly 30–60 t, and every landing already fires the 0.12/8 micro-shake (4 t cooldown).

**IDEATE.**
1. Wide establishing gap: `STRUCTURES_ESTABLISH_TICKS = 20` between the structures
   caption and the FIRST tear — caption + open sky read before anything rips (was: same
   tick). Gated via `run.firstBeatReleased` so a late PENDING listener can't jump the
   window. ✔
2. Tear handoff stagger: ground-tear close at beat start, sky-tear open + its 0.2/12
   shake `GROUND_TEAR_HANDOFF_TICKS = 6` later — the two rift reads used to land in one
   tick and muddied each other (RiftFx close animation now reads first). ✔
3. Hold measured from the sky OPEN (trigger at handoff + 40): pieces launch into a frame
   the tear has owned for a full 40-tick hold — the "wide establishing angle when pieces
   launch", expressed as time-to-look rather than a forced camera. ✔
4. Replay parity for the delivery window: replay slam moves to `RIFT_HOLD +
   REPLAY_FLIGHT_TICKS(45)` (mid of BD-STRUCT's 30–60 + settle) with landing
   micro-shakes 0.12/8 at +16/+28/+38 after the trigger moment — the FX-only replay now
   rehearses what the live show feels like. ✔
5. Live per-landing micro-shake — ALREADY BD-STRUCT's (`landingFx`), coordinated and not
   duplicated here; ownership note recorded. ✔
6. A forced delivery cutscene — rejected: R11 returns control at GROWTH by design;
   re-freezing players once per site (up to N sites) would fight exploration.
7. Extra shake at the trigger tick — rejected: `StructureFlightFx.open()` fires the
   surge shake exactly then when a delivery actually plays; doubling would stack.
8. Longer hold (60 t) — rejected: the flight already adds 30–60 t; tear-to-slam on a
   10-site stage would crawl (beats are serialized by `BEAT_SPACING_TICKS`).

**IMPLEMENT.** `beginStructures`: caption → 20 t establish gap → release gate → first
beat. `maybeStartNextBeat`: gate check added; ground close at t 0; sky open + shake in a
+6 t task (guarded on `run.ended` / `activeBeat != beat` so aborts and auto-place races
never open a dead tear); trigger + timeout chain shifted to handoff + 40; log line shows
the true trigger delay. Replay `STRUCTURES`: `slamAt` offset + landing shake loop; rings/
debris/close all keyed off `slamAt` (window shape preserved).

**POLISH 2 (correctness).** The `firstBeatReleased` gate is only set by the establish
task, which re-checks run liveness; `slamBeat`/timeout re-entries run long after release
so the gate never wedges a mid-run beat. Auto-placed-before-beat race branch
(`onSitePhase` PLACED with a queued site) unchanged — it never depended on the open.
Watchdog force-END unchanged. `javac` confirms no seam drift.

**POLISH 3 (tuning).** Handoff 6 t ≈ RiftFx's close-read onset (same figure the RIFT
team's surge cadence used); establish 20 t = one caption line's read time at whisper
pace; replay landing offsets keep ≥ 4 t spacing under the slam (mirrors the live
cooldown, never strobes) and the last one sits 7 t before the slam so the big 0.4/18 hit
still dominates.

---

## 4. UNLOCK RING — `unlock_ring.json` (+ fallback-play beats in `beginFlyover`)

**PLAN.** W7's orbit was serviceable but flat: constant-radius sweep, no hero moment, no
caption, and — as the FLYOVER fallback — its growing caption only arrived AFTER the shot
(from `beginGrowth`). Asks: rotating hero shot of the ring with a god-ray backlight
moment. Constraint found: the sun's position is not authorable from a path (the custom
sky renderer owns it), so a literal backlight cannot be staged — the ray read must be
carried by bloom + silhouette framing.

**IDEATE.**
1. Low dramatic pickup: y 7 at radius ~37, edge looming overhead. ✔
2. Rising lookAt-tracked hero rotation: ~200° of orbit, radii 37 → 44, roll ±2. ✔
3. God-ray backlight moment at t .56–.58: camera dips low and tight (fov 54, the shot's
   minimum), lookAt raised to y 8 so the ring edge stands against the sky, warm-lilac
   bloom fade (`6,6,18,#4CEFE4FF`) + `event.beam_hum` + a sub-audible 0.08/14/0.6 awe
   rumble. ✔
4. One-shot `cutscene_veil` flare at the orbited anchor (+4 y) on the same beat for the
   FLYOVER-fallback plays (`RING_HERO_T = 0.58`, per-watcher anchor, per-watcher send) —
   the wisp backlight behind the silhouetted edge. ✔
5. New whisper caption `eclipse.caption.unlock.ring` at t .30 (localized, langdrop). ✔
6. Fallback caption timing: growing caption moves INSIDE the orbit (`beginFlyover`
   fallback branch sends it at play start and marks `flyoverPlayed` — field re-documented
   as "a front cutscene carried the caption"). ✔
7. Real god-ray via `limbo_godray` / `sanctum_lightfall` — rejected: both are LOOP
   emitters with managed lifecycles; a fire-and-forget payload could leak the loop, and
   the limbo godray is dimension-branded.
8. Aiming the orbit at the actual sun azimuth — rejected: not authorable (see PLAN);
   bloom + silhouette is the honest read.
9. Full 360° orbit — rejected: 1.6°/tick sweep never lets a hero angle hold; ~200° with
   the t .58 dip reads as deliberate.

**IMPLEMENT.** 6 keyframes / 220 ticks as above (high reveal finish kept from W7 —
its hand-off framing was already right); events per ideas 3/5. `beginFlyover` fallback
branch: caption + `flyoverPlayed` + per-watcher hero flare schedule (guards: `run.ended`,
`hasDisconnected`); empty-watchers case now enters GROWTH immediately instead of waiting
a phantom orbit out. `params.orbitRadius` 45 kept (template metadata for the
unlock-growth integration; hero dip radius ~38 noted in `_comment`).

**POLISH 2 (correctness).** The hero flare fires only on the fallback path this team
owns — direct `unlock_ring` plays by other integrations still get the full in-JSON
god-ray moment (bloom + hum + framing), so the shot never half-plays. Beacon-activate
pickup sting kept (t .05). Caption key literal-check passes `warnLiteralCaptions` (dotted
key, no spaces); en/de parity via langdrop.

**POLISH 3 (tuning).** Bloom alpha 0x4C (≈ 30 %) — backlight blowout, not a flashbang;
in-bloom fov floor 54 (not lower — the template must survive arbitrary anchor terrain);
awe rumble 0.08 stays under the beacon sting so audio hierarchy holds.

---

## Self-check results

- `javac` (Java 21, `build/moddev/artifacts/neoforge-21.1.238-merged.jar` +
  `build/classes/java/main` + gradle module cache, `-sourcepath src/main/java`):
  **PASS** for `ExpansionSequence.java` + `CutscenePaths.java`.
- JSON validator (schema mirror of `CutscenePath.parse`: keyframe t order/range 0..1,
  ≥ 2 keyframes, easing whitelist {linear, easeInOutSine, easeInOutCubic, easeOutCubic},
  event grammar per type, caption keys localized en+de incl. langdrop, `eclipse:` sound
  ids present in `sounds.json`, shake strengths ≤ 0.5, AARRGGBB fade colors, and JSON↔Java
  sync of `SKYWARD_PUNCH_T` / `RING_HERO_T` / `FLYOVER_SKIM_T` against the authored
  beats): **PASS** for all 3 paths.
  Profiles: skyward fov 70-68-78-85-76-66-60; flyover deck bob 42/18/9/6.5/11/8/34;
  ring orbit radii 36.8→43.9.
- Legacy default hashes appended (pre-edit SHA-256, default-refresh mechanism):
  `expansion_skyward` `ffe1fbd4…70ea`, `expansion_flyover` `5be44de1…ce2a`,
  `unlock_ring` `e118ac2b…506e` (full hashes in `CutscenePaths`).
- Langdrop: `docs/plans_v3/langdrop/CUT-EXPANSION.json` (2 keys × en_us/de_de) — merge
  with `python3 tools/langmerge/merge_langdrops.py CUT-EXPANSION.json`.

## Coordination notes (BD-STRUCT)

- `StructureFlightFx.java` untouched. The beat's sky tear now opens 6 t after beat start;
  the delivery surge's re-open at trigger time (its `open()`) is unaffected — same tear
  position, same RiftFx replace law, and the trigger still fires ≥ 40 t after the open.
- Replay constants `REPLAY_FLIGHT_TICKS = 45` / landing offsets mirror the flight's
  30–60 t window + `landingFx` cadence; if BD-STRUCT retunes those, only these two
  `ExpansionSequence` constants need a follow-up.

## Deferred (noted honestly)

- Skyward punch-burst timing rides the server tick clock against the client flight clock;
  the player-anchored preload hold makes drift ~0, but a pathological chunk-load stall
  could push the burst a few ticks past the fade. A path-event emitter type
  (`"emitter"` in `CameraDirector.fireEvents`) would make it exact — engine change, out
  of this cluster's write scope.
- Flyover offsets are absolute-axis (world-anchor contract), so the radial direction of
  the front crossing varies per play; a yaw-to-front anchor rotation would need engine
  support (same schema seam as above).
