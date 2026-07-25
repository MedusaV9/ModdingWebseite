# FXTEAM-CUT-END — dragon-victory shatter + ferry transform + finale return

Team log (planner + ideators + polishers), process per shot: PLAN → IDEATE 6+ →
IMPLEMENT → POLISH 2 → POLISH 3. Cluster: `cutscenes/end_shatter.json`,
`cutscenes/finale_return.json`, `worldgen/end/EndShatterSequence.java` camera/FX beat
timings (presentation ONLY — carve logic untouched: `Layout`, `sample`, `shatterColumn`,
the budgeted `Job` writer shape, `ShatterData`, grace/heal/kit flow are all frozen), and
the `ferryman/ArenaFight.java` TRANSFORM beat presentation (stage machine, gate/arrival/
fight flow, freeze/transport, whiteout semantics frozen). Self-checks: `javac -proc:none`
against the moddev NeoForge 21.1.238 merged jar + Veil 4.3.0 + full modules cache +
`build/classes/java/main` (with `-sourcepath` for concurrently-landed team sources), and
a JSON validator that parses both paths and checks the `CutscenePath.parse` schema:
keyframe ordering/ranges, easing names against the Veil `Easing` enum extracted from the
jar (`javap`), event types/data grammars per `CameraDirector.fireEvents`, sound ids
against `sounds.json`, caption ids against `en_us.json`, and lookAt anchor ids against
the frozen synced set (`eclipse:altar_center` et al.). NO gradle, NO git.

Cross-team interleave (observed live this round): CUT-INTRO migrated
`CutscenePaths.LEGACY_DEFAULT_HASHES` from `Map.of()` to `Map.ofEntries()` (the
CUT-CREDITS note's 10-pair limit) and preserved this team's two in-flight hash entries;
a display-FX team landed `DisplayBrightnessFx` import + debris-animator constants
(`DEBRIS_UPDATE_TICKS`/`DEBRIS_GRAVITY`/tumble/dissolve family) into
`EndShatterSequence.java` mid-round — left untouched here (their cluster), compile
verified against their fresh source.

Shared laws respected: frozen payload shapes (`S2CShakePayload` has NO freq field — the
low-frequency rumble shaping is only expressible in JSON `shake` events, which carry
`strength,ticks,freq`), one-shot-only quasar emitters over `S2CQuasarPayload`
(`growth_dust_wall`, `slam_debris`, `cutscene_veil` — all `loop:false`; loop emitters
would leak through the one-shot payload), client `FxBudget` BURST channel absorbs
excess, and the C10.5/C13 restart law (cinematic presentation never resumes — the new
beat schedule is transient and dropped on stop).

Pre-edit bundled-default hashes appended to `CutscenePaths.LEGACY_DEFAULT_HASHES`:
- `end_shatter` ← `dfe571268d427b708554b573d47ad3414aa8b7831b80ddf7dcc25bf314c226e1`
- `finale_return` ← `0bcf7ed27add164030fb20d78c14b2c8a66064d46b7ea373034b2d506e176dfe`

---

## 1. DRAGON-DEATH BEAT — the silence before the first crack
(`end_shatter.json` t 0–0.10 + `EndShatterSequence.beginShatter`)

**PLAN.** Ask: a 1 s hold of TRUE silence before the first crack, "audio duck if
achievable via existing sound stops". Audit FIRST: there is no sound-stop mechanism
anywhere in the mod (no `ClientboundStopSoundPacket` use, no stop payload, no
`SoundManager.stop` call server-reachable), and the cutscene event engine only knows
`sound|caption|fade|shake` (unknown types are ignored). Verdict: a real duck is **not
achievable in-cluster** — build the silence by *scheduling*, not stopping: beat 0
previously fired rumble + 1.5-strength shake + ALL seam flashes in one tick.

**IDEATE.**
1. Dead-air hold: strip every beat-0 sound/shake; JSON fires nothing until t 0.10
   (24 t = 1.2 s); server-side rumble/shake wait out the same window on a new transient
   beat schedule. ✔
2. Camera holds its breath too: opening segment slowed to ~0.8 blocks/t creep (was
   ~1.7), tight fov 60, low pitch — stillness read. ✔
3. First crack = a *sharp* stinger, not the rumble: `end_shatter_crack` + a
   freq-3.0 10 t shake jolt at t 0.10; the bass rumble enters UNDER it at t 0.15. ✔
4. Keep the grace caption + broadcast at beat 0: safety information must not wait for a
   cinematic beat (accepted cost: the caption's faint UI tick; scene audio stays dead). ✔
5. New "sound_stop" event type in the engine: rejected — CameraDirector is out of
   cluster; event schema frozen this round.
6. Silence via a music-volume S2C nudge: rejected — no such payload exists; new payload
   = frozen-contract break.
7. Hold the letterbox/fade closed until the crack: rejected — the preload veil already
   owns entry framing; a second fade would double-veil on slow chunk loads.

**IMPLEMENT.** JSON: kf0 `[-112,41,-14]`→kf1 `[-106,44,4]` over t 0–0.10 (easeInOutSine,
fov 60→62), zero events in the window. Java: new `Beat(dueGameTime, action)` record +
transient `BEATS` list ticked from `onServerTick` (cleared in `onServerStopped`);
`beginShatter` moves the world rumble + per-player notify + dimension shake (1.5/60 →
1.2/50, JSON carries the rest) onto `now + SILENCE_HOLD_TICKS` (24).

**POLISH 2 (correctness).** Beats are added from the poll branch and ticked on
subsequent ticks — no concurrent modification; a restart drops `BEATS` with the rest of
the transient state (the C13 "cinematic never resumes" law, now explicit in the
javadoc). Honest sync caveat: the JSON clock starts at preload-hold release, the server
schedule at beat 0 — under a slow chunk preload the server-side race can run behind the
black veil. Normal case (server tickets columns at play time) is a few ticks of skew;
accepted and documented rather than "fixed" with an out-of-cluster READY-ack seam.

**POLISH 3 (tuning).** Opening drift retimed after a speed recount (chord ~19 blocks /
24 t ≈ 0.8 b/t — held breath, not a dolly); first-crack jolt kept SHORT (10 t) so the
silence→crack transient stays a cliff, not a ramp.

---

## 2. DISC CRACK PROPAGATION — cracks race outward, light bleeds up
(`end_shatter.json` t 0.10–0.42 + `EndShatterSequence` crack race)

**PLAN.** Beat-0 previously flashed every future seam SIMULTANEOUSLY (one
`fx/rift_open` per outer islet midpoint, one tick). Ask: cracks RACE outward with
sequential sharp cracks + light bleeding up from the fissures, via emitters.

**IDEATE.**
1. Stagger the existing seam flashes center-out: sort outer islets by site radius
   (`Math.hypot(siteX, siteZ)`), one flash every 4 t from +24 t — the violet rift tear
   IS "light bleeding up from the fissure" (existing id, frozen a/b semantics kept:
   width 6.0, style 0). ✔
2. Positional crack stinger rides each flash, pitch climbing 0.85 → +0.06/step — the
   race is audible as a rising scale, spatialized along the disc. ✔
3. JSON mirror for the cutscene watchers: 4 crack events t 0.10→0.35 with shake freq
   falling 3.0→1.8 (sharp rattles gaining weight as fissures widen). ✔
4. `impact_light` bloom per flash: rejected — the rift tear already carries its own
   flash core; doubling reads as strobe at 5–8 seams in 30 t.
5. Sequential `sanctum_lightfall` columns at seams: rejected — `loop:true` emitter,
   leaks through the one-shot payload.
6. Carve-phase `playCrack` cadence retune (48 t): rejected — it already pitch-salts per
   islet and its first stinger lands at +108 t, clear of the race; changing cadence
   risks stepping on the separation rumble.
7. Particle crack-line tracing the actual Voronoi seam polyline: rejected — needs a new
   emitter walk driven per-tick (new sender surface); the seam-midpoint flash race
   carries the read at a fraction of the spend.

**IMPLEMENT.** `beginShatter`: race list sorted by radius, flash `i` scheduled at
`+SILENCE_HOLD_TICKS + i·CRACK_RACE_STEP_TICKS` (24, 28, 32 … ≤ 52 for the max 8 outer
islets), each beat = `S2CFxEventPayload(FX_RIFT_OPEN)` + `playSound(crack, 3.0F,
0.85F + 0.06F·step)` at the seam midpoint. JSON events as ideated.

**POLISH 2.** Lambda captures audited (all effectively final); flash positions computed
eagerly at schedule time from the deterministic layout — a same-tick chunk edit cannot
shift them; last race beat (+52 t) lands before the separation beat (+58 t) for every
possible islet count (6–9).

**POLISH 3.** Race step held at 4 t (not 6/8): the full race must fit inside the JSON's
crack window (t 0.10–0.42 ≈ 24–101 t) with margin for the preload skew; pitch ceiling
0.85 + 7·0.06 = 1.27 stays under the chipmunk line.

---

## 3. SHATTER SEPARATION — wide pull with mass, dust curtains, debris trails
(`end_shatter.json` t 0.42–0.72 + `EndShatterSequence` separation beat)

**PLAN.** Ask: camera pulls WIDE + slight tilt as islets separate with mass (slow heavy
easing), dust curtains falling from break faces, debris trails. The islet translation
itself is instant per-column (carve law, untouchable) — mass is built from camera
weight, low shake, dust and debris timing.

**IDEATE.**
1. Wide pull: fov 66→79 + roll 2→4 over t 0.42–0.72, leaving kf 0.42 on
   `easeInOutQuart` — the heaviest in/out ramp in the Veil enum short of quint; ~125
   block sweep to the high apex `[128,96,52]`. ✔
2. Heavy low shakes under the pull: strength 0.9 freq 0.55 (55 t), then 0.6/0.5 — the
   2-octave noise at freq <1 is the documented "heavy ground rumble" mode. ✔
3. Dust curtains: one-shot `growth_dust_wall` (the expansion curtain, `loop:false`,
   6×6 spawn volume) at every seam midpoint, scheduled at +58 t — 2 t before the carve
   starts biting, so curtains fall exactly as break faces appear. ✔
4. Debris re-timed INTO the separation: `spawnDebris` moved from beat 0 to the +58 t
   beat — chunks must not tumble off a disc that still looks whole (shot 1/2 window). ✔
5. Debris trails: every 40 t, a rotating window of 3 live debris displays sheds a
   one-shot `slam_debris` ember burst at its position (~22 bursts across the 300 t TTL,
   BURST-channel budgeted client-side). ✔
6. Second rumble under the curtain drop (pitch 0.8) — the separation gets its own bass
   voice distinct from the beat-0 rumble. ✔
7. Attached trail emitters on debris (glide-trail style `ensureAttached`): rejected —
   the attach path is keyed to the nearest PLAYER client-side (`FX_GLIDE_START`
   semantics); no entity-id payload exists for displays, and adding one breaks frozen
   shapes.
8. Slow-eased actual islet translation (display-animated blocks): rejected loudly —
   that is the carve pass, explicitly out of scope.

**IMPLEMENT.** JSON kf 0.42/0.72 as ideated; Java: `SEPARATION_FX_DELAY_TICKS = 58`
beat spawns curtains (sender-local `GROWTH_DUST_WALL`/`SLAM_DEBRIS` ids — the
`ExpansionSequence` local-constant pattern), plays the 0.8-pitch rumble, then
`spawnDebris`; `tickDebris` gains `debrisTrailClock` + rotating `debrisTrailCursor`.

**POLISH 2.** Trail window arithmetic safe when `DEBRIS.size() < 3` (start clamps, no
wrap, fewer samples — cosmetic); trail sends only when `entity.level()` is a
`ServerLevel` (defensive cast, free); debris TTL/cap/velocities untouched — only WHEN
things happen moved, matching the "timing windows" scope line.

**POLISH 3.** Curtain count = outer islet count (5–8 one-shots, once) ≪ BURST ceiling;
ember cadence 40 t × 3 keeps worst-case debris spend ~4.5 emitters/s, invisible next to
the carve's own resend traffic.

---

## 4. ISLET DRIFT SETTLE — overshoot, settle 2–3 blocks, low rumble fade
(`end_shatter.json` t 0.72–1.0 + `Job.complete()`)

**PLAN.** Ask: islets overshoot then settle 2–3 blocks with a low rumble fade. Real
overshoot of terrain is carve logic (translation is one-shot) — the settle is staged on
the camera (sink past the final height, lift back 3 blocks) and in the audio floor.

**IDEATE.**
1. Camera settle: descend t 0.72→0.90 (`easeOutSine`), sink to y 45.5 at t 0.955, then
   rise +3.0 to y 48.5 at t 1.0 — the overshoot-and-settle read in the camera's own
   vertical, mostly-vertical final leg. ✔
2. Low rumble fade: shake ladder 0.35/freq 0.4 (55 t) → 0.18/freq 0.35 (45 t) — decaying
   strength AND sinking frequency = a rumble dying into the floor. ✔
3. Settle thump: `event.rift_thud` at t 0.90 + one 0.9-freq 12 t shake — the isles
   "landing" accent under the caption. ✔
4. `easeOutBack` on the final segment for a sampler-native overshoot: rejected — Back
   easing exceeds [0,1] and `PathSampler.position`'s LUT behavior past 1.0 is
   unverified; explicit keyframes give the same read with zero sampler risk.
5. Carve-completion echo: `Job.complete()` (which fires when the isles are ACTUALLY
   done, minutes later) plays a 0.6-pitch rift thud at the disc center + one soft long
   dimension shake (0.45/45) — the world-state settle for anyone still on the disc. ✔
6. Debris overshoot-settle (chunks bounce at a rest height): rejected — debris
   deliberately falls into the void (TTL/void-kill law); a bounce would need rest-height
   scanning per chunk = new logic for a background prop.
7. Final-frame fov breathe (74→70→74): rejected — the end-blend already eases fov back
   to the player's own; an authored breathe would fight it.

**IMPLEMENT.** JSON keyframes t 0.90/0.955/1.0 + events as ideated; `Job.complete()`
gains the thud + soft shake before the existing broadcast (flow order unchanged).

**POLISH 2.** `S2CShakePayload` has no freq field — the completion shake stays at the
payload's fixed freq 1.0 and compensates with LOW strength/long ticks; the freq-shaped
settle lives only in the JSON events (documented in the code comment so nobody "fixes"
it into a payload change). Settle-leg lateral motion trimmed (~11 blocks) so the rise
reads vertical.

**POLISH 3.** Completion thud pitch 0.6 sits an octave-ish under the race stingers —
same asset family, unmistakably "after". Camera sink depth 5 → rise 3 blocks: matches
the brief's "2–3 blocks" on the recovery side, where the eye measures it.

---

## 5. FERRY TRANSFORM — staggered mast spirals, veil peel + wind gust
(`ArenaFight.java` TRANSFORM beat: `spawnMorphDisplays`/`pushMorphRise`/`tickTransform`)

**PLAN.** The morph layer lifted all pieces with ONE uniform push (delay 0, duration
`TRANSFORM_TICKS−2` for every piece). Ask: masts spiral with staggered (non-uniform)
timing; the shroud veil peels off with a wind gust burst at the end. Flow frozen:
freeze/transport, whiteout tick, sweep, arena summon untouched.

**IDEATE.**
1. Per-piece interpolation-start delays (the display entity's native
   `setTransformationInterpolationDelay`): deck planks 0–8 t, masts 6–16 t, each with
   duration shortened to `TRANSFORM_TICKS−2−delay` so every piece still ARRIVES by the
   beat end — stagger without flow drift. ✔
2. Mast pieces get the spiral emphasis: ±2.75π spin (vs ±1.5π deck), rise 10–16, radial
   drift cut to 0.8–2.0 (vs 2–5) — masts corkscrew in place; the deck scatters. ✔
3. Alternating spiral handedness between neighbouring mast pieces (index parity flip)
   — counter-rotating helix pairs, the "not uniform" ask at a glance. ✔
4. Deck/mast discrimination via `morphDeckPieces` split index recorded at spawn time
   (deck pieces are appended first): zero new state on the displays, sweep-safe. ✔
5. Veil peel + gust: at the exact `WHITEOUT_TICK`, one `event.rift_whoosh` (1.6 vol,
   0.85 pitch — a low wind tear), one sharp 0.9/14 shake, and one last `cutscene_veil`
   one-shot ABOVE the deck (y +8) so the shroud visibly leaves up-and-away as the
   white-out swallows the ship. ✔
6. Escalating mid-beat shakes: the flat 0.5/16 every 15 t becomes 0.45→0.75 rising with
   `transformTicks` — the spiral gathers force. ✔
7. Discriminate masts by block state (`getBlockState().is(DARK_OAK_LOG)`): rejected —
   accessor visibility varies across mappings; the split index is guaranteed by the
   spawn order this class itself owns.
8. Per-mast fore→aft wave (delay keyed to `MAST_X` group): rejected — needs the piece→
   mast mapping derived from spawn-loop arithmetic (3 dy steps per mast), a hidden
   coupling to the builder's loop shape; hash stagger already reads non-uniform.
9. Creak sounds per mast lift (`ui.door_open` ship creak): rejected — a UI-kit id in a
   world beat; and 9 staggered creaks in 60 t reads as comedy.

**IMPLEMENT.** As ideated: `morphDeckPieces` field (reset in `sweepMorphDisplays`, set
in `spawnMorphDisplays`), rewritten `pushMorphRise` (per-piece delay/duration/rise/
spin/drift), escalating shake line, gust block at `WHITEOUT_TICK` ahead of the existing
portal-fx loop. `TRANSFORM_TICKS`, `WHITEOUT_TICK`, freeze windows: untouched.

**POLISH 2.** Duration floor `max(10, …)` keeps the worst-case mast piece (delay 16)
interpolating 42 t — no teleport-snap; the gust fires exactly once (tick equality, not
`>=`); `morphDeckPieces` stays in lockstep with the list through every clear path
(spawn/sweep/stop). Parity flip uses the post-increment index — arbitrary but stable
per piece; documented rather than "fixed" into extra state.

**POLISH 3.** Mast delay window (6–16 t) overlaps the deck window's tail (0–8 t) so the
lift reads as one gathering motion, not two mechanical waves; all pieces are airborne
well before `WHITEOUT_TICK` 25, so the gust peels a fully-spiraling silhouette.

---

## 6. FINALE RETURN — warm slow descent, the altar glowing in frame
(`finale_return.json`)

**PLAN.** The W2 descent was a neutral 240 t player-orbit behind a black fade. Ask:
warm, slow, with the altar in frame. JSON-only shot (senders out of cluster): warmth
from the fade color + a hum, altar from the synced `eclipse:altar_center` FX anchor,
slowness from duration + easing.

**IDEATE.**
1. Warm dawn fade: `finale_open` fade `1,16,44,FFF6E7C8` — opaque warm cream instead of
   black, longer 44 t bloom-out; still fully covers the teleport home. ✔
2. Altar in the opening frame: kf0 `lookAt: "anchor:eclipse:altar_center"` (synced by
   IntroSequence, re-set idempotently after restart); the 90°/s slerp clamp hands the
   aim off to `lookAt: "player"` across the first segment — dawn-over-the-altar, then
   the camera finds the returning player. Missing anchor degrades to the keyed
   yaw/pitch (kept sensible on kf0) by engine contract. ✔
3. Slow: durationTicks 240 → 280 (+17 % travel time, arc-length pacing spreads it
   evenly), early segments `linear` → `easeInOutSine` so the descent drifts instead of
   gliding mechanically. ✔
4. Warm audio floor: one `ambient.sanctum_hum` UI one-shot at t 0.04 under the dawn
   caption — the altar's hum is IN the frame with it. ✔
5. Keep the t 0.85 `emerge` + settle shake (`0.18,26,2.5`) — the touch-down beat
   already reads; retuning it would fight shot 4's settle language. ✔
6. Altar glow FX burst (`altar_beam`/`altar_afterglow` via payload): rejected — JSON
   events cannot spawn emitters and the finale senders are out of cluster; the altar's
   own resident FX carry the glow.
7. lookAt altar through kf1 too (handoff at 0.62): rejected — showOwnBody true makes
   this shot ABOUT the player (C6 doctrine in the file's own _comment); one segment of
   altar framing is a reveal, two is a different shot.
8. New warm caption line: rejected — lang files out of cluster; existing
   `finale.dawn`/`finale.home` keys already carry the words.

**IMPLEMENT.** As ideated; `_comment` updated to document the anchor-lookAt degrade
path and the CUT-END restage.

**POLISH 2.** Anchor id validated against the frozen synced set
(`S2CAnchorPayload` doc: `ship_door`/`altar_center`/`ship_deck`); fade color is
8-hex AARRGGBB per the parser (`FFF6E7C8` — alpha FF, warm cream); duration change is
watchdog-safe (server reads the same JSON's durationTicks).

**POLISH 3.** kf1 raised 18→19 y so the altar→player handoff pivots above the horizon
line (no ground smear mid-slerp); hum at 0.04 (not 0.0) so it swells INSIDE the
fade-out rather than popping at frame zero.

---

## Self-check results

- `javac -proc:none` (moddev NeoForge 21.1.238 merged jar + Veil 4.3.0 + modules cache +
  `build/classes/java/main`, `-sourcepath src/main/java` for the concurrently-landed
  `DisplayBrightnessFx`): **PASS** for `EndShatterSequence.java`, `ArenaFight.java`,
  `CutscenePaths.java` (baseline pre-edit compile also PASS — toolchain verified first).
- JSON validator (parse + full `CutscenePath.parse` schema, Veil `Easing` enum
  whitelist from jar bytecode, event data grammars per `CameraDirector.fireEvents`,
  sound ids vs `sounds.json`, caption keys vs `en_us.json`, frozen lookAt anchor ids):
  **PASS** for both paths (end_shatter: 8 kf / 18 events / 240 t; finale_return:
  5 kf / 6 events / 280 t).
- `LEGACY_DEFAULT_HASHES`: both pre-edit hashes recorded (see header); table now
  `Map.ofEntries` (CUT-INTRO's migration, this team's entries preserved and verified).

## Deferred (noted honestly)

- True audio duck for the dragon-death silence: no sound-stop surface exists anywhere
  in the mod. Candidate: a tiny `S2CSoundStopPayload` (vanilla
  `ClientboundStopSoundPacket` wrap) — new payload shape, out of this cluster's write
  scope by the frozen-contract law.
- Server↔JSON beat sync under slow chunk preloads: the crack race is scheduled from
  beat 0, the JSON clock from preload-hold release; a many-second hold desyncs them
  (race runs behind the veil). Fix would need a READY-ack callback seam on
  `CutsceneService` — out of cluster.
- Debris display animator upgrade (tumble/dissolve/brightness constants already landed
  in-file from the display-FX team): their round; the trail-burst windows here attach
  cleanly to whatever `tickDebris` body they land.
