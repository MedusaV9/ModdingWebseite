# REPASS-BD — fresh-eyes pass over ALL block-display animation systems (post-v6)

Team log. Process per system: **VERIFY** (the v6 interpolation claims, live in code) →
**POLISH** (the new craft items) → **AUDIT** (brightness NBT, sweep coverage, budgets) —
three passes each. Prior logs: `plans_v5/fxteams/BD-STRUCT.md` + `BD-SHIP.md`; fixes
landed since v6 and re-verified here: the per-piece arena morph stagger (interpolation
start delay = `launch − pushTick`) and the debris chunk-load sweeps (`LIVE_DEBRIS` +
join-time stray guard). Self-checks: `javac --release 21 -proc:none` against the moddev
neoforge-21.1.238 classpath + `build/classes/java/main` (`javac.repassbd.args`).
NO gradle, NO git.

## Cluster-wide VERIFY (pass 1, all systems)

Grepped `teleportTo` / `setPos` / `moveTo` / `teleport_duration` across the mod:
**zero per-tick display transport anywhere.** Every `moveTo` on a Display entity is a
spawn-time placement (flight pieces, debris, morph pieces, wheel/flyers/pucks, assembly
stones, shard, decor, orbitals, accents) or a one-shot operator command
(`DisplayPlacerService.move` — `/dev display move`, allowed). The keyframe-lead pattern
(pose targets the window END) and duration == update stride verified live in all nine
systems:

| System | Lead target | Duration / stride | Verdict |
| --- | --- | --- | --- |
| StructureFlightFx | `min(pieceAge+2, flight+settle)` | 2 / 2 | ✔ |
| EndShatterSequence debris | `age + 4` | 4 / 4 | ✔ |
| ArenaFight morph | `windowEnd` (8t keys), per-piece delay stagger | `8 − hold` / 8 | ✔ |
| ArenaBuilder accents | `gameTime + 20` | 20 / 20 | ✔ |
| CreditsSequence wheel | `wheelAngle(t + 4)` | 4 / 4 | ✔ |
| CreditsSequence flyers/pucks | `progress + 2t` lookahead | 2 / 2 | ✔ |
| AltarDoor assembly | one push, delay-choreographed (18t rise / 6t snap) | ✔ by construction | ✔ |
| SkyLauncher shard | `gameTime + 20` ambient, `+3` charge (charge owns the stride) | 20/20, 3/3 | ✔ |
| FloatingDecor | `gameTime + 4` | 4 / 4 | ✔ |
| DisplayPlacerService | `gameTime + TICK_INTERVAL` + sub-0.4 s bob presentation clamp | 2 / 2 | ✔ |
| SanctumOrbitals | `gameTime + 40`, rebuild pushes an immediate glide keyframe | 40 / 40 | ✔ |

---

## 1. StructureFlightFx — VERIFIED + material glow + mass dust

**VERIFY.** Lead/duration/anchor-only-entity all hold (table). Spiral launch order,
overshoot-settle scale, bottom-anchored squash, 3-stage brightness ramp, interpolation-
end landing seam (`fxDueAge`) — all present as logged. Launch ticks are multiples of 6,
so piece age parity always matches the even push stride (no phantom half-windows).

**POLISH (new).** (1) *Material-aware glow*: each `Piece` computes `warmGlow` once at
build time — `state.getLightEmission() > 0` (crying obsidian, sculk) or membership in
`ORE_GLOW_BLOCKS` (copper block, gilded blackstone, amethyst block — ore/crystal that
emits nothing but should hold heat). The mid-flight brightness step becomes
block 13 (warm) vs 8 (plain), sky 15 for both; spawn full-bright and the landing clear
are unchanged, so the round-trip count stays ≤ 3 per piece — only the stepped-to VALUE
is material-aware. Ore-bearing masonry now visibly carries the rift's warmth across the
sky while plain stone cools. (2) *Mass-scaled landing dust*: the interpolation-end seam
now also kicks `BlockParticleOption(BLOCK, piece.state)` crumbs at the cell — count
`clamp(4 + explosionResistance, 4..14)` (wool ≈ 4 barely puffs, planks ≈ 7, deepslate ≈
10, obsidian clamps at 14). Dust fires PER PIECE (it is the "this piece really hit its
own cell" read, and it rides the piece's own block state); the thud/shake keep their
4t rate limit so a landing hail still cannot strobe. Plunge pieces dust at their
punch-in point — the dirt-spray read was free.

**AUDIT.** Brightness NBT: `DisplayBrightnessFx.set(display, block, sky)` writes
`brightness.block` / `brightness.sky` — all call sites pass (block, sky) in the right
order. Sweeps: `ENTITY_TAG` + `LIVE_DISPLAYS` join guard + PLACED sweep + fallback
discard — intact. Budget: zero new entities/pushes; dust ≤ 80 bursts × ≤ 14 particles
spread across the whole delivery window.

---

## 2. EndShatterSequence — VERIFIED + straggler personality

**VERIFY.** Closed-form drift/tumble/dissolve, fixed anchors, batched 4t pushes
targeting `age + 4`, `LIVE_DEBRIS` + join-time chunk-load stray guard + boot sweep —
all live. The old `teleportTo`/`teleport_duration` path is gone without residue.

**POLISH (new).** *Stragglers*: the 5th and 23rd spawned chunks (the seed-hashed grid
scan is deterministic, so replays pick the same columns; degenerate small spawns just
get fewer stragglers) CLING to the break face and chase the flock. Implemented as a
closed-form **monotonic time warp on the motion clock** (`Debris.motionAge`): lag
smoothsteps 0→26t over the first 48t (cling — clock never dips below 0.18× real, so
angular momentum stays signed and nothing ever plays backward), holds through 96t,
then smoothsteps back to zero by 176t (catch-up peaks ≈ 1.49× real → terminal fall ≈
2.1 blocks and spin ≈ 9.6° per 4t window, both inside the tween comfort zone). Drift,
tumble and precession read the warped clock; **dissolve and TTL stay on real age** (the
warp is identity again before the dissolve starts, so the fade beat stays shared).
Ember-trail bursts and the void-removal check now sample the warped arc — the trail
follows what the eye sees. Stateless: warp is a pure function of real age, re-pushes
always agree.

**Rejected shapes** (ideation): per-straggler re-rolled launch velocity (changes where
the chunk lands — the lag/catch-up read wants the SAME path, later); a stateful "pause
then boost" integrator (breaks the absolute-function-of-age law); >2 stragglers (the
personality read needs the flock to clearly NOT straggle).

**AUDIT.** Zero packet delta (same cadence, same push count). Brightness dissolve
steps NBT-correct ((4,8) → (1,3), block ≤ sky — void-lit from above). Cap 120 / TTL
300 frozen. Sweep coverage unchanged.

---

## 3. ArenaFight morph + ArenaBuilder accents — VERIFIED + guard fix; shadow-dim SKIPPED

**VERIFY.** The since-v6 per-piece stagger fix is correct in code: a piece launching
inside the current window rides `delay = clamp(launch − pushTick, 0, window−1)` and
tweens `window − hold` — every piece starts at its OWN launch tick, and pre-launch
pieces re-push identity poses (equal synched values never dirty). Windows end-targeted,
worst rotation per window ≈ 78° (masts, ease-in-out) — under the ~90° law. Accents:
20t stride == duration, absolute clock, tag sweep + join guard.

**POLISH (assessed, then SKIPPED — the brief's "only if cheap" clause).** Morph
shadow-dim on the deck below: three passes over the options said no. (a) Per-piece
shadow pucks (the credits tinted-glass pattern) ≈ +40 displays and double the beat's
push count — the morph budget is frozen, and the fighters STAND ON the morphing deck,
so deck-level quads intersect their own legs at eye −1.6 blocks; the credits pucks work
because the beach is viewed from a distant tracking camera. (b) One ship-wide dark
quad: same leg/z-fight problem, plus a 36×10 tinted-glass sheet reads as a render
glitch from any deck-level angle. (c) The whiteout at t=25 swallows the ship — any
shadow would be on stage ≤ 23 ticks. Cost and read both fail; skipped with conviction.

**FIX (audit find).** MORPH was the ONE display family without a join-time stray
guard: a crash mid-beat persists pieces, and the boot `sweepMorphDisplays` only reaches
limbo chunks already loaded at start — an async-loading chunk could stream a ghost
plank in later. Closed exactly like the other families: `spawnMorphPiece` now records
the UUID **before** `addFreshEntity` (so the guard never eats a live spawn), and
`onEntityJoin` discards any `MORPH_TAG` joiner not in the live list.

**AUDIT.** Accent budget 5 displays × 1 push/s unchanged; both gate arms + `endFight`
+ `onServerStopping` sweep paths re-checked; `AltarDoor.cancelAssembly` on stop intact.

---

## 4. CreditsSequence wheel + flyers — VERIFIED + sunrise glint

**VERIFY.** Wheel: continuous rotation + two incommensurate noise sines + grip
envelope, 4t lookahead windows, discard-guarded. Flyers: staggered renormalized arcs,
golden tumble phases, damped spin, scale envelope, shadow pucks mirrored — all as
logged; `LIVE_DISPLAYS` + join guard + FX-replay isolation intact.

**POLISH (new).** *The glint catches the sunrise*: (1) **phase-lock** — the fixed 50t
cycle is shifted by `WHEEL_GLINT_OFFSET` (= 22t, computed from the constants: the run
tick where the MEAN wheel angle first crosses the low-east dawn spoke angle
`WHEEL_GLINT_SUN_DEG = 25°` mod the 45° spoke symmetry, minus half the ramp so the
PEAK sits on the crossing). The flash now happens where a spoke sweeps the sunrise
line instead of on a bare run clock — and true noisy-crossing detection stays rejected
for the v6 reason (rate noise double-blinks it; the constant shift is branch-free).
(2) **Warm bias** — the ramp splits: block light leads 6→15→6 while sky trails
6→11→6, so the catch reads as low dawn light on varnished wood rather than a neutral
fullbright pop. `floorMod` keeps the pre-offset ticks dark (the wheel enters the shot
before its first catch — anticipation for free).

**AUDIT.** Same round-trip count per cycle (one set per 4t sample inside the 14t ramp
+ one clear); the clear window [14,18) is still guaranteed exactly one 4t sample at any
phase drift (50 mod 4 = 2 walks the sample phase, window length == stride). Helm-skip
discard still cannot leave a stale bright frame (entity discard, not override).

---

## 5. AltarDoor assembly — VERIFIED + pitch-laddered snap chimes (+ seam-law fix)

**VERIFY.** Record-first restart anchor, delay-choreographed one-push rise (golden
stagger 0–8t, 18t duration — last piece finishes at t=27 < snap 28), unison 6t snap,
`ensureStamped` crash repair, tag sweeps + `isLivePiece` join guard — all live.

**POLISH (new).** *One soft chime per stone, pitch-laddered, as they snap*: a
fifteen-note semitone gliss on `AMETHYST_BLOCK_CHIME` (the run's existing crystal
voice — altar ack, wand, launcher charge all speak it; no sounds.json edits), pitch
`2^((i−7)/12)` ≈ 0.67→1.5, volume 0.35, spread 2–3 stones per tick across the snap
window (`slot = i·6/15`), each note spatialized at ITS OWN aperture cell — the
col-major piece order makes the ladder audibly walk up each column of the door.
Killed stones stay silent (a gap in the gliss is the honest read). **Seam-law fix
found by pass 3**: the deepslate lock-thunk fired at the SEND tick (t=28); it now
lands at t=34 — the tick the snap interpolation ENDS on the client, the visual moment
fifteen stones become one mass — with the gliss rising into it. The brightness flash
deliberately STAYS on the push tick: brightness syncs un-interpolated, and the law
says snaps hide inside motion — at t=34 the stones stop moving, so a flash there would
pop on static geometry.

**AUDIT.** Chimes: ≤ 15 one-shot sounds over 6 ticks, once per door arm — noise
budget trivial, and `cancelAssembly` mid-window silences the remainder (assembly
null-check gates every tick). No new entities, no new pushes, crash matrix unchanged.

---

## 6. SkyLauncher wind shard — VERIFIED + launch-direction telegraph

**VERIFY.** Ambient 20t windows off the absolute clock, charge-stride 3t boost
ownership (ambient holds while a charge runs — the v6 defect-6 fix confirmed live),
`SHARD_TAG` in `sweepPadEntities` + 200t self-heal, return pad shard-free.

**POLISH (new).** *Idle telegraphs the launch direction*: the shard's 12° tilt is no
longer carried around by the yaw (it used to precess — pointing everywhere, saying
nothing). It is now a FIXED world-frame **lean toward the launch target** (`shardLeanDir`
— the exact `launch()` ring-point geometry, a pure function of pad + End config, so the
stateless-push law holds), with the spin turning UNDER the lean; and at the top of each
bob the hover **strains up to 0.16 blocks along that direction** (drift rides the same
bob sine, phase-aligned so the "reach" peaks with the rise). Standing on the pad you
can read where the sky will throw you before you ever charge. The charge spin-up whips
around the leaned axis unchanged. Existing worlds glide into the new pose family over
one interpolated window on the first push (delay-0 retarget — no snap).

**AUDIT.** Zero new entities/pushes; per-window rotation delta unchanged (yaw rate
untouched, lean is constant); `shardLeanDir` costs two sqrt per 20t ambient stride
(3t during a charge) — off any hot path. Degenerate pad-at-disc-center guarded (+X).

---

## 7. FloatingDecor — VERIFIED, no change

Lead (`gameTime + 4`), duration == cadence, fixed axes + pole precession (salts 15/16),
deterministic ensure/reconcile rebuild, spawn-only `moveTo`. Pass 2/3 found nothing to
add that v6's ideation had not already correctly rejected (brightness ramps, scale
breathing, phase coupling — the rejections still hold). Untouched.

## 8. DisplayPlacerService / DisplayAnimator — VERIFIED, no change

Keyframe lead + the 0.4 s bob presentation clamp both live and commented with the law
names; `move()` is a one-shot operator reposition (not animation transport — allowed);
respawn/adopt path re-tags before animating. Reference-implementation status holds.
Untouched.

## 9. SanctumOrbitals — VERIFIED, no change

40t cadence == duration, `gameTime + 40` targets, counter-rotating rings + breath +
fixed tumble axes, `rebuild()` pushes the immediate post-reconcile glide keyframe (the
v6 fix, confirmed live). Untouched.

---

## Micro-audit summary (pass 3, cluster-wide)

- **Brightness NBT**: both writers (`DisplayBrightnessFx.set(block, sky)` and
  `CreditsSequence.applyBrightnessOverride(sky, block)`) have OPPOSITE parameter
  orders but both write the correct `brightness.{block,sky}` compound keys; every call
  site audited against its intent — flight ramp, debris dissolve, flyer dimming, wheel
  glint, door flash all correct. Clears go through tag-absent round-trips (the vanilla
  reset path). New glow/glint values keep all channels in 0–15.
- **Sweep coverage**: every display family = tag + session UUID set + join-time stray
  guard + boot/lifecycle sweep. The one gap (MORPH_TAG had no join guard, and its UUID
  registered after `addFreshEntity`) is closed this pass. Placer devtool keeps its
  SavedData-driven clear + defensive orphan sweep.
- **Budgets**: no new entities anywhere; no new steady-state pushes anywhere; new
  costs are ≤ 80 landing-dust bursts per delivery, ≤ 15 chime one-shots per door arm,
  and two sqrt per shard stride. All display caps frozen (80 / 120 / ~40+5 / 25+12 /
  15 / 1 / 28 / 12).

## Self-check matrix

| Files | Check | Result |
| --- | --- | --- |
| `StructureFlightFx`, `DisplayBrightnessFx` (unchanged, compile-guarded), `EndShatterSequence`, `ArenaFight`, `ArenaBuilder` (unchanged, compile-guarded), `AltarDoor`, `CreditsSequence`, `SkyLauncher`, `FloatingDecor` / `DisplayPlacerService` / `DisplayAnimator` / `SanctumOrbitals` (unchanged, compile-guarded) | `javac --release 21 -proc:none` @ `javac.repassbd.args` (moddev 21.1.238 classpath + `build/classes/java/main`) | exit 0 — only the repo-wide pre-existing deprecation notes |
