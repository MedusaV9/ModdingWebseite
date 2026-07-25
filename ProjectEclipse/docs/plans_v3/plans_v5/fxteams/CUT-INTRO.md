# FX Team — CUT-INTRO (round: intro cinematic reshoot)

Team process per shot: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: `assets/eclipse/cutscenes/intro_v3_ship.json` / `intro_v3_flight.json` /
`intro_v3_reveal.json`, `sequence/IntroSequence.java`, `sequence/IntroLightningPhase.java`.
Presentation ONLY: camera paths, per-keyframe `fov` (landed), rolls/easings, caption/FX/sound
beat timing, `S2CScreenFadePayload` envelopes, `S2CShakePayload` impulses. NO gameplay or
flow-logic changes — phase order, triggers, freezes, kickback, containment, teleports,
watchdogs and the R10 tick table (100 / 900 / 600 / 300 / 200) all untouched.

Hash bookkeeping (the CutscenePaths default-refresh contract): the PRE-EDIT SHA-256 of every
reshot bundled JSON is appended to `CutscenePaths.LEGACY_DEFAULT_HASHES`, verified against
`git show HEAD:` byte-for-byte, so servers whose config copies are untouched old defaults
upgrade in place:

| id | pre-edit hash appended |
|---|---|
| `intro_v3_ship` | `02da214a113afcd21ac34f75fe8368400909b927d95463d696e15ef297d59ac7` |
| `intro_v3_flight` | `f7188ad86c759a9b58e1d4f93af4020214a02d09d05ebe43428b7921951e1ee6` |
| `intro_v3_reveal` | `4ec430af2c612ab8d2519a86d26547b667a7573cda0e09be16815765255eecca` |

The 11th id overflowed `Map.of()`'s 10-pair limit (CUT-CREDITS left a note predicting this),
so the table migrated to `Map.ofEntries()` — semantics unchanged.

Self-checks: `javac --release 21 -proc:none -sourcepath src/main/java` over the three touched
Java files against the moddev legacy classpath + merged jar + Veil 4.3.0 + molang + geckolib
(green), a Python validator replaying `CutscenePath.parse` constraints on all three JSONs
(t-ordering, easing names vs Veil's `Easing` enum, lookAt shapes, event data grammars), and
the caption i18n check (every caption event id present in BOTH `en_us.json` and `de_de.json` —
no new keys were added, so no langdrop needed). No gradle, no git mutations.

---

## Shot 1 — ship keel-over (`intro_v3_ship.json`, 130 t, player-anchored, limbo)

### PLAN
Intent/emotion: intimacy → dread → helpless scale. The old shot teleported straight to a wide
flyaround; the brief wants to START tighter "on the wheel" and CRANE UP as the keel-over
begins, with a slow FOV squeeze 70→62. The shot must stay player-anchored and generic — it
doubles as the finale arrival flyaround (`ArenaFight`), so all beats read as "the ship
shudders", never intro-specific.

### IDEATE
1. **Seamless possession open** — keep keyframe 0 at the exact eye offset `[0,1.62,0]` yaw 0
   (the frozen hand-off trick) so the camera leaves the player's own eyes. **CHOSEN**
2. **Tight wheel shot** — settle at ~4 blocks, slightly above eye, `lookAt player`, dutch −2:
   an over-the-shoulder framing before any scale is revealed. **CHOSEN**
3. **Crane-up with deepening dutch** — as the oar TILT interpolates (t=0..100 of the intro
   play), the crane rises 2.6→24 while the dutch deepens −2→−5 with the ship's list, then
   releases to level at the apex — the horizon itself "keels". **CHOSEN**
4. **Monotonic FOV squeeze 70→62** — no breathing on this shot; a slow vice so the deck feels
   smaller the higher the camera rises. **CHOSEN**
5. **Heavy keel shake retune** — old `0.22,30,2.5` read as a rattle; a keel-over is a slow
   mass — retimed to `0.3,36,0.8` (low-frequency roll), plus a first small lurch `0.1,26,0.7`
   at t=0.3 so the big beat is foreshadowed. **CHOSEN**
6. **Deep hull groan** — one `minecraft:ambient.underwater.loop.additions.ultra_rare`
   (whale-like metallic groan) under the first lurch: "something below has taken hold".
   **CHOSEN**
7. Speed-ramp drop off the stern into the water. **REJECTED** — the portal glitch (t=120)
   owns the exit; a second motion accent would fight R13's hand-off.
8. Whip-pan to the horizon fleet at the apex. **REJECTED** — LimboHorizonShips are not
   guaranteed in frame for arbitrary player yaw (player-anchored shot).
9. Second groan near the apex. **REJECTED** — audio restraint; the submerge wash at 0.55
   already owns the mid-shot.

### IMPLEMENT
- Keyframes 6 (was 5): eye → `[2.2,2.6,-3.4]` (tight, −2 dutch) → `[5.5,6,-8]` (−4) →
  `[10,12,-12]` (−5, keel beat) → `[13,18.5,-5]` (−2.5) → `[10,24,6]` (level apex).
  All `lookAt player`; fovs 70 / 69 / 66.5 / 64 / 62.5 / 62.
- Easings: easeInOutSine ×3 → easeInOutCubic → easeInCubic (accelerating skyward under the
  portal glitch).
- Events: depart whisper kept at 0.08; NEW lurch shake 0.3 (`0.1,26,0.7`) + groan 0.32;
  submerge wash kept 0.55; keel shake 0.62 retuned `0.3,36,0.8`.
- `params._comment` documents the shot language; `params._doc` carries the standard fov /
  showOwnBody note (C6 convention). `showOwnBody: true` kept — the shot frames the watcher.

### POLISH 2
- Frame-check: 0.12→0.38 is ~34 t of slow crane at 4→11 blocks — covered by the whisper
  caption (70 t) and the TILT animation, no dead air. Keel shake at t≈81 lands at ~81% of
  the 100-t oar tilt — maximum list, correct sync.
- The t=0 → t=0.12 segment leaves the keyed eye orientation and blends into the player
  lookAt; the aim quat has zero weight exactly at the degenerate camera==eye instant, and
  the 90°/s lookAt clamp smooths the first frames — no whip (verified against
  `CameraDirector.orientate` blending rules).

### POLISH 3
- Micro-easing: apex segment easeInCubic so the exit accelerates INTO the R13 glitch cover
  (t=120 = 0.923) instead of drifting flat.
- i18n: `eclipse.caption.intro.depart` present in en_us + de_de ✓. reducedFx: shakes are
  camera noise only, peak offset 0.3 × 0.16 = 0.05 blocks, sub-second — motion-safe; the
  path events deliberately stay inside the small-amplitude band the whole cluster uses.

---

## Shot 2 — flight (`intro_v3_flight.json` t 0.0–0.8, 900 t, world-anchored)

### PLAN
Intent/emotion: awe → unease. The crane over the fusing discs should fly like a bird with a
will, not a dolly: BANK into every curve with 2–4° horizon roll, and let the cruise FOV
settle 68→62 so the vortex approach has somewhere to pull FROM.

### IDEATE
1. **Alternating banking rolls** — −3 / +3.5 / −3 through the descending spiral's direction
   changes, never past 4°, levelling before the dive. **CHOSEN**
2. **Cruise FOV settle 68→62** — a gentle tightening as the camera descends; parks at 62 so
   the approach pull spans the full 62→78 the brief asks for. **CHOSEN**
3. **Keep the whisper/vortex-spawn sync** — the 0.24 whisper (`...something gathers...`)
   aligns with the t=300-absolute `StormRegistry.spawnVortex`; every retime preserved this
   anchor. **CHOSEN**
4. **Hesitation at the edge** — the cruise segment's easeInOutSine derivative naturally hits
   ~0 at the t=0.8 keyframe: the camera pauses a breath before committing to the dive.
   Free (easing semantics), sold by the sting (shot 3). **CHOSEN**
5. Roll driven fully by curve curvature per keyframe (continuous bank). **REJECTED** — with
   only catmullrom keys the roll interpolates linearly anyway; alternating keyed banks read
   identically at a fraction of the tuning cost.
6. Extra low pass between discs (players visible on their discs). **REJECTED** — disc
   spots vary per world/player count; a guaranteed-empty low pass reads worse than height.
7. FOV overshoot to 58 mid-cruise. **REJECTED** — parking BELOW 62 makes the approach pull
   read as "recovering", not accelerating.

### IMPLEMENT
- Keyframes 0.0/0.2/0.42/0.64 keep their positions (chunk-preload probe envelope unchanged)
  but get rolls 0/−3/+3.5/−3 and fovs 68/65/62/62; lookAt ladder (y 12→22) kept.

### POLISH 2
- Bank direction alternates with the spiral's S-curves like the original ±2 did — deepened,
  not inverted; levels (−1) at the dive keyframe so the ramp reads straight-line stable.

### POLISH 3
- Rolls capped at 3.5 (brief allows 4): at fov 62 a 4° dutch over the disc horizon already
  reads strongly; 3.5 keeps the fusion geometry legible. i18n: fuse/vortex keys ✓.

---

## Shot 3 — vortex approach (`intro_v3_flight.json` t 0.8–1.0 + hand-off)

### PLAN
Intent/emotion: commitment — the camera stops observing and DIVES. Speed ramp into the smoke
wall with the FOV pulling 62(63)→78, buffet building, fade covering the hand-off at full
speed. The APPROACH phase logic (proximity watcher, re-nudge whisper) is untouched.

### IDEATE
1. **One long easeInQuad dive segment** — a single 0.8→1.0 segment (180 t, ~97 blocks) so
   easing and FOV interpolate monotonically across the WHOLE ramp; intermediate keyframes
   would re-zero the easing derivative and hitch the acceleration. **CHOSEN**
2. **FOV pull 63→78 on the same segment** — the pull is eased by the same quad curve, so
   lens breathing and true blocks/tick gain peak together at the wall. **CHOSEN**
3. **Dive-commit sting** — `eclipse:event.storm_pulse` exactly at the t=0.8 keyframe, selling
   the hesitation→commit beat. **CHOSEN**
4. **Wind buffet shake** — `vortex_close` retuned `0.12,30,2.0` → `0.14,50,3.2` and moved
   0.88→0.86: a longer, higher-frequency airframe flutter that overlaps the fade. **CHOSEN**
5. **Fade retime 0.955→0.96 with faster rise** — `16,12,26` (was `20,15,25`): 4 more visible
   ramp ticks, still fully black at t=880 < 900 (hand-off + GLOBAL_TELEPORT return stay
   covered; release ~t=918 into APPROACH matches the old ~919 envelope). **CHOSEN**
6. **End position pulled in 60→44 blocks from the wall axis** — the last visible frames fill
   with smoke wall; end-of-flight blend is behind black, so the closer park is free. **CHOSEN**
7. easeInCubic for the dive. **REJECTED (polish 2)** — cubic crawls for ~5 s after the sting
   (12 blocks in the first 99 t); quad tips over promptly and still doubles speed by the wall.
8. Roll wind-up (dutch 6°) during the dive. **REJECTED** — speed reads through FOV +
   parallax; stacking dutch on the pull risks nausea right before a hard cut.
9. Thunder sting at 0.9. **REJECTED** — thunder at 0.55 + storm_pulse at 0.8 + buffet is a
   full audio ramp; lightning-flavored sounds are LIGHTNING-phase currency.

### IMPLEMENT
- New dive keyframe t=0.8 `[-130,46,-6]` roll −1 fov 63 easeInQuad; final keyframe
  `[-40,12,-18]` roll 0.5 fov 78 (43.9 blocks from the vortex axis — outside the r=22 wall
  + kick envelope). Events: storm_pulse 0.8, buffet shake 0.86, fade 0.96 (`16,12,26`),
  approach caption kept at 0.97 (subtitles render ABOVE fades by `CaptionRenderer` order).

### POLISH 2
- **Retune found & fixed:** first-pass easeInCubic dive left ~5 s of near-hover after the
  commit sting (dead time); switched to easeInQuad + moved the keyframe 0.78→0.8 — the nose
  tips over within ~1 s of the sting and end-speed at the wall is ~1.1 blocks/t.
- Fade math re-verified: rise 864→880, hold to 892, release to ~918; flight ends 900 —
  hand-off and disc-return teleports fully covered.

### POLISH 3
- FOV crosses 70 at ~68% of the dive (t≈0.936) — most of the pull is on screen before the
  fade starts rising. i18n: approach key ✓ both locales. reducedFx: buffet strength 0.14
  (max offset 0.022 blocks) — texture, not throw.

---

## Shot 4 — lightning (`IntroLightningPhase.java`, presentation only)

### PLAN
Intent/emotion: the storm answers back — each close strike should be FELT in the camera, not
just heard, ramping with the R10 intensity curve. No cadence, kickback, push-zone or
containment changes.

### IDEATE
1. **Close-range strike shake riding the sting pick** — the per-player close/far branch in
   the sting loop already encodes distance; close players additionally get
   `S2CShakePayload.shake(...)` (client camera impulse stack — never movement input).
   **CHOSEN**
2. **Intensity-scaled strength** — `0.1 + 0.22 × intensity` (0.19→0.32 across the ramp) over
   8 t: a short CRACK, so late-ramp 15-t cadence never stacks two live impulses into mush
   (2-impulse worst case ≈ 0.6 × soft-cap 1.5). **CHOSEN**
3. **Giant burst rattle for everyone** — the `giant` strike forces `close` already; 0.55 over
   26 t rides into the flash sandwich (shot 5). **CHOSEN**
4. **Replays inherit it for free** — `strike()` is shared by live runs and FX-only replays;
   a shake is presentation, matching the replay contract (visuals/sounds/captions). **CHOSEN**
5. Whiteout micro-flash per strike (2-t fade payloads). **REJECTED** — strobing at 15-t
   cadence is a photosensitivity hazard; the vanilla visual bolt already flashes the world.
6. Per-strike caption whispers ("it sees you"). **REJECTED** — caption queue (cap 8) would
   flood during max fury; LIGHTNING already has its strike whisper on entry.
7. Distance-scaled shake strength (continuous falloff). **REJECTED** — the payload carries
   no falloff and the sting's binary close/far read is the established language; two tiers
   are enough at 64-block range.
8. Kick the FOV per strike. **REJECTED** — FOV is cutscene-path currency in this cluster;
   gameplay-camera FOV pokes fight sprint/speed FOV modifiers.

### IMPLEMENT
- `playStingByDistance` → `stingAndShakeByDistance`: close players get
  `S2CShakePayload.shake(giant ? 0.55 : 0.1 + 0.22·intensity, giant ? 26 : 8)`.
  Constants `STRIKE_SHAKE_BASE/GAIN/TICKS`, `GIANT_SHAKE_STRENGTH/TICKS`; class javadoc
  "Per strike" paragraph updated.

### POLISH 2
- Verified frozen players still receive the shake (correct — it is FX, and cutscene watchers
  during replays SHOULD feel it; kickback still checks `FreezeService.isFrozen`).
- Verified the hold-fury strikes during the pre-burst wait (`HOLD_STRIKE_INTERVAL_TICKS`)
  inherit the intensity-1.0 shake — the wait doesn't go numb.

### POLISH 3
- Budget: one 6-byte payload per close player per strike (~40 strikes/phase worst case) —
  negligible. Impulse ceiling audited against `CameraDirector`'s 1.5 soft cap and 0.16-block
  max offset. javac ✓.

---

## Shot 5 — burst (`IntroSequence.java` flash sandwich)

### PLAN
Intent/emotion: the world BREAKS for one unseeable instant. Replace R10's white→violet
double fade with the brief's shutter grammar: white snap-hold (2 t) → hard-cut shutter black
(3 t) → violet reopen. The scripted day switch keeps landing behind the cover.

### IDEATE
1. **Three chained `S2CScreenFadePayload`s** — white `(1,2,0)`, shutter `(0,3,0)` at +3,
   violet `(0,2,10)` at +6; `CaptionRenderer.fade` REPLACES the live envelope on each
   receipt, so the chain is stack-safe by construction (the "existing TransitionFx-style
   hook" — same client fade surface the R13 transitions ride). **CHOSEN**
2. **Hard cuts via zero in/out** — `in=0` snaps to peak, `out=0` self-clears instantly
   (verified against the `fadeEnvelope` branch order): a true shutter, no smoothstep bleed.
   **CHOSEN**
3. **Day switch + vortex dissipate behind the shutter** — unchanged calls, now hidden by
   white+black (6 t) instead of white alone: the sky-snap can never be seen mid-lerp. **CHOSEN**
4. **Violet reopen lengthened 8→10 t** — the morning sky arrives through the mod's signature
   violet, slightly slower now that the shutter pre-darkens the eye. **CHOSEN**
5. **Replay parity** — the FX-only BURST replay sends the same three envelopes per watcher
   (with `hasDisconnected` guards on the scheduled sends). **CHOSEN**
6. TransitionFx.glitchPulse on the burst. **REJECTED** — glitch language is rift/portal
   currency (GLITCH team's doctrine); the intro burst is lightning-white, not digital.
7. Double-strobe white (2 flashes). **REJECTED** — photosensitivity; total continuous white
   stays ≤ 3 ticks, matching the old envelope's exposure.
8. Slow-motion (tick-freeze illusion) via long white hold. **REJECTED** — holds > ~5 t make
   dedicated-server hitches indistinguishable from intent; 2 t is the brief's number.

### IMPLEMENT
- Constants: `FLASH_WHITE (1,2,0,#FFFFFFFF)`, `SHUTTER_BLACK (0,3,0,#FF000000)`,
  `FLASH_VIOLET (0,2,10,#CC8800FF)`, `SHUTTER_DELAY_TICKS 3`, `FLASH_VIOLET_DELAY_TICKS 6`.
- `beginBurst`: white now + scheduled shutter/violet; replay `case "BURST"` mirrors with
  per-watcher guards; class-doc BURST bullet updated.

### POLISH 2
- Envelope walk-through at tick resolution: t0 white rises (1 t) → holds t1–3 → shutter
  replaces at t3 (instant black) → violet replaces at t6 (instant peak, holds 2, releases
  over 10) → clear at t18. `BURST_HOLD_TICKS` 40 > 18: the reveal orbit starts on a clean
  screen. The giant-strike rattle (shot 4, 26 t) decays UNDER the sandwich — impact continuity
  across the cut.

### POLISH 3
- Alpha audit: violet tail `0xCC` peak matches the old grade; no new colors introduced.
  javac ✓; frozen payload shape (`in/hold/out/argb`) untouched — wire-compatible.

---

## Shot 6 — reveal (`intro_v3_reveal.json`, 300 t, world-anchored at the altar)

### PLAN
Intent/emotion: reverence. The old ~270° lap read as a survey; the brief wants a SLOW orbital
drift with foreground silhouette framing — the island as a hero object, rubble crossing the
lens.

### IDEATE
1. **~175° drift at ~0.6°/t** — same 300 t, ~35% less angular travel: stately, not touring.
   **CHOSEN**
2. **Low, far silhouette open** — start 48 out and 14 BELOW the altar: against the post-burst
   morning sky the island reads as a black cutout torn from the earth (the caption's exact
   text). **CHOSEN**
3. **Closest pass through the rubble's parallax band** — ease in to ~32 blocks: FloatingDecor's
   fragment ring (r 11–23, golden-angle band) sits between camera and island, so fragments
   cross the frame as foreground silhouettes with real depth; 32 > 23 keeps the lens out of
   clipping range of any fragment. **CHOSEN**
4. **FOV breathing 60→57→55→56→58** — tightest at the closest pass, relaxing out; the inhale/
   exhale the brief calls fov breathing. **CHOSEN**
5. **Rising lookAt exit (−2→+4)** — the final frames tilt up the island flank toward the
   crown, handing a sky-facing composition to SUNRISE's eclipse release. **CHOSEN**
6. **Counter-rolls ≤ 1.5** + settle shake softened `0.15,24,2.2` → `0.12,26,1.2`, moved
   0.88→0.9 — the island "docks" with a low rumble, not a rattle. **CHOSEN**
7. **Caption retime 0.1→0.12** — six more ticks of pure silhouette before the words. **CHOSEN**
8. Full 360° orbit. **REJECTED** — the far side of the island is fusion-crater backdrop;
   the drift keeps the sky behind it the whole shot.
9. Passing INSIDE the rubble band (r ~18). **REJECTED** — fragment positions are hash-derived
   per world; a guaranteed near-miss cannot be authored, and a face-full of stone would
   block the island for seconds.
10. Vertical crane reveal (rise bottom→top). **REJECTED** — competes with the lookAt climb;
    doing both makes the horizon swim.

### IMPLEMENT
- 5 keyframes: `[44,-14,20]`→`[30,-4,-16]`→`[12,4,-30]`→`[-14,8,-30]`→`[-30,2,-16]`,
  rolls 0/−1.5/0/+1.5/0, fovs 60/57/55/56/58, lookAt y −2/−4/0/+2/+4, easeInOutSine ×4 +
  easeOutCubic exit. Events: storm_burst 0.02 kept, caption 0.12, emerge 0.5 kept, settle
  shake 0.9 (`0.12,26,1.2`).

### POLISH 2
- Radius walk: 48 → 34 → 32 → 33 → 34 — a single ease-in/ease-out envelope, no pumping.
  Bearing walk: 24° → −28° → −68° → −115° → −152° — monotonic drift, ~0.59°/t peak.
- Y-envelope −14→+8 stays inside the old shot's −12→+10 (no terrain-clip regression under
  the island's crater).

### POLISH 3
- i18n: reveal key ✓ en+de. The `lookAt (0,4,0)` exit frames the altar crown lower-third —
  the SUNRISE title (`renderTitle` at 0.38 screen height) lands in clear sky, not on the
  island. reducedFx: single shake 0.12 — nominal.

---

## Shot 7 — sunrise (`IntroSequence.java` warm hold)

### PLAN
Intent/emotion: earned dawn. The eclipse releases over 200 t; the brief adds a warm bloom-in
and a 1.5 s longer rest before the machine calls the intro complete.

### IDEATE
1. **Warm gold bloom fade** — `S2CScreenFadePayload(50, 20, 70, 0x2EFFC994)`: an 18%-alpha
   warm veil rising over 2.5 s as the rim dims, holding a breath, releasing over 3.5 s —
   a bloom-in on the fade surface (no shader work, dist-neutral, Iris-safe). **CHOSEN**
2. **+20 t bloom delay** — waits out the reveal end-blend (12 t) and any violet remnant so
   the warm rise starts from a clean frame. **CHOSEN**
3. **`SUNRISE_HOLD_EXTRA_TICKS = 30`** — `finish()` now scheduled at ramp+30: the sequence
   rests on the fresh morning ~1.5 s before completion (delays only the completion latch and
   the downstream Logbook-hint clock — no player-facing logic sits in that window). **CHOSEN**
4. **Replay parity** — the SUNRISE FX-replay sends the same bloom (guarded, per-watcher).
   **CHOSEN**
5. **Bloom UNDER the title** — free: `CaptionRenderer` draws fades below caption text, so
   "IT BEGINS" tracks in over the warm veil. **CHOSEN (verified, no code)**
6. Extending the eclipse ramp itself 200→230. **REJECTED** — `SUNRISE_RAMP_TICKS` feeds the
   `S2CEclipsePhasePayload` ramp AND login-resync estimates; stretching the sky lerp buys
   less than the post-ramp rest and touches a frozen R10 number.
7. Warm color via the grade/post pipeline. **REJECTED** — GRADE team's cluster; the fade
   surface is this cluster's own tool and degrades identically everywhere.
8. Extra caption ("the sun remembers"). **REJECTED** — needs new lang keys (langdrop
   round-trip) and the moment is deliberately wordless after "IT BEGINS".

### IMPLEMENT
- Constants `SUNRISE_HOLD_EXTRA_TICKS 30`, `SUNRISE_WARM_BLOOM (50,20,70,0x2EFFC994)`,
  `SUNRISE_BLOOM_DELAY_TICKS 20`; `beginSunrise` schedules the bloom broadcast and the
  extended finish; replay `case "SUNRISE"` mirrors the bloom; class-doc SUNRISE bullet
  updated.

### POLISH 2
- Timeline audit: bloom 20+50+20+70 = fully clear at t=160 < 200 (ramp end) < 230 (finish) —
  nothing overlaps the completion latch or the +300 t Logbook hint.
- Restart-recovery path (`completeAbandonedRun`) untouched — it never enters SUNRISE, so the
  extra hold cannot wedge a recovering world.

### POLISH 3
- `0x2EFFC994` warm gold — deliberately NOT the loot-beacon warm hue family per the STORM
  team's "warm = over there" doctrine check: a 46/255-alpha fullscreen wash reads as light,
  not as a marker. javac ✓.

---

## Round summary (all shots)

| Shot | Surface | Self-check | Change in one line |
|---|---|---|---|
| ship keel-over | `intro_v3_ship.json` | json ✓ / parse rules ✓ | eye→wheel→crane with FOV 70→62 vice, heavy keel beats |
| flight | `intro_v3_flight.json` | json ✓ | banking rolls ≤ 3.5°, cruise FOV settles 68→62 |
| vortex approach | `intro_v3_flight.json` | json ✓ | easeInQuad dive, FOV 63→78 pull, buffet + retimed fade |
| lightning | `IntroLightningPhase.java` | javac ✓ | intensity-scaled close-strike camera cracks, giant rattle |
| burst | `IntroSequence.java` | javac ✓ | white 2 t → shutter black 3 t → violet 10 t sandwich |
| reveal | `intro_v3_reveal.json` | json ✓ | ~175° slow drift, rubble-band foreground pass, FOV breathing |
| sunrise | `IntroSequence.java` | javac ✓ | +30 t rest + warm gold bloom-in (live + replay) |

Frozen surfaces untouched: phase machine order/triggers, R10 tick table, kickback/containment/
push-zone numbers, payload wire shapes, replay contract (FX-only), restart recovery, freeze
lifecycles. All caption ids pre-existing (en+de verified) — no langdrop needed. Pre-edit
default hashes appended (table above) and `LEGACY_DEFAULT_HASHES` migrated to
`Map.ofEntries()` as CUT-CREDITS' note requested.

Note for sibling teams: verification here is scoped `javac -sourcepath src/main/java` over
the three touched files (compiles every transitive dependency it actually uses) — same
scoping rationale as STORM's round (parallel clusters may be mid-edit tree-wide).
