# P2-W6 wiring notes — Intro sequence v3 (R10)

Zero `EclipseMod` / `EclipsePayloads` / `FxPayloads` / `EclipseSounds` / `sounds.json`
edits. Every new class self-registers (`@EventBusSubscriber`); the one new payload rides
its own registrar (`sequence/SequencePayloads`, version group `seq1` — the documented
multi-registrar pattern, no id collisions: `eclipse:seq/portal_hop`). **No new sound
aliases** — the sequence reuses `event.eclipse_drone`, `event.storm_burst`,
`event.lightning_close/far`, `event.submerge`, `event.emerge` plus vanilla
`entity.lightning_bolt.thunder` / `ambient.underwater.enter`.

## What W6 landed

- **`sequence/IntroSequence`** — the R10 phase machine, `SequenceReplayable` id `"intro"`
  (phases `ECLIPSE_ON, FLIGHT, APPROACH, LIGHTNING, BURST, REVEAL, SUNRISE`). Frozen §6.3
  entry point: `IntroSequence.start(MinecraftServer, Map<UUID, BlockPos> discCenters)` —
  currently invoked by the reworked `StartEventCutscene`; P4 may call it directly once its
  own disc-teleport trigger lands. Phase persists in its own `SavedData`
  (`data/eclipse_intro_sequence.dat`); a restart mid-sequence **skips to the end state**
  (eclipse ended + rim, lingering vortexes dissipated, decor ensured once the sanctum is
  floating) — never resumes mid-cinematic. `permanentRim` persists there too and re-sends
  per login (explicit fallback until P4's world flag owns it, §6.3 — when P4 lands, delete
  the login re-send in `IntroSequence.onLoggedIn`, keep the rest).
- **`sequence/IntroLightningPhase`** — the ramping strike controller (interval 100→15
  eased, intensity 0.4→1.0, first strike 0.5 + burst sting; per strike: frozen
  `eclipse:fx/lightning_strike` event → W9 draws the bolt FROM the eclipse, one
  visual-only vanilla `LightningBolt` at the vortex foot, `eclipse_lightning_impact` +
  `impact_light` Quasar one-shots, distance-picked close/far stings). Kickback = the
  proven `risePlayerAt` impulse (0.8 horizontal radial + 0.25 Y, `hurtMarked`), clamped
  INWARD whenever the predicted landing column would leave the disc footprint
  (`DiscGeometry.isInStageZeroFootprint` / fused `mainDiscRadius(stage)` − 2) — P4's
  containment stays the hard guarantee, our impulse just never aims off the rim. Frozen
  players are never pushed; FX-only replays construct it with `applyKickback=false`.
- **`sequence/FloatingDecor`** — 28 animated block-display rubble fragments
  (deepslate/obsidian/amethyst mix, scales 0.3–1.6) in a golden-angle band (r 11–23)
  around/under the floating island, biased to the underside so the rip reads from the
  ground. Idempotent by tag `eclipse_intro_decor` (+ `eclipse_intro_decor_<i>` identity
  tags): ensure/reconcile adopts, dedupes, tops up — `/kill @e[tag=eclipse_intro_decor]`
  heals on the next pass. NOTE: the plan wrote the tag as `eclipse:intro_decor`; vanilla
  selectors/`/tag` reject `:`, so the underscore form is the frozen id. Animation: one
  interpolated transform per entity per 4 ticks (rotation 0.2–1.0°/t, bob 0.05–0.25 over
  80–200t), all poses absolute functions of game time (stateless, restart-safe), whole
  pass gated to players within 96 blocks. Orbitals stay `SanctumOrbitals`' (P6-W5) — this
  class never touches entities without its own tag.
- **`sequence/SequencePayloads`** — S2C `eclipse:seq/portal_hop` (`enter`, `ticks`)
  dispatching to W8's frozen `TransitionFx.playPortalEnter/Exit` (R13). Server-side
  senders: `sendPortalEnter/Exit(ServerPlayer, int)`. Client class resolved lazily in the
  handler body — never loads on a dedicated server.
- **`limbo/StartEventCutscene`** (M) — the limbo half only, then delegates. Kept: v1
  `TILT`/`SUBMERGE`/`WAVES`/`EMERGE` `S2CCutscenePayload` broadcasts (WaveOverlay
  regression path), `OarAnimator.beginTilt/endTilt`, `startEventDone`,
  `first_overworld_join` stamps, cutscene_veil bursts. New timeline: t=0 ship flyaround
  (`intro_v3_ship`, 130t, freeze survives the hop via the `intro_*` id rule) → t=120
  portal-enter (18t; glitch → hold-black covers the ship path's ACK at t≈130 AND the
  dimension change — the vanilla dimension screen is never the visible surface) → t=140
  per-player disc teleports (`DiscGeometry.playerDiscCenter(i % 8)`, surface-snapped,
  facing world center; >8 players ring the same discs 3·round blocks out; re-freeze +
  `FreezeService.transport`) → t=150 portal-exit (24t) → t=160 EMERGE +
  `IntroSequence.start(server, discCenters)`. The v1 carved-pocket "rise out of the
  ground" beat and its `intro_rise` chain are gone; `FusionSequence.maybeStartIntroFusion`
  moved from EMERGE into IntroSequence's FLIGHT (the camera must frame the sweep).
- **`ritual/FinaleRitual`** (M, reconcile only) — its arrival beat played the deleted
  `intro_submerge`; now plays `intro_v3_ship` (player-anchored deck flyaround, 130t).
  `SUMMON_TICK=100` still lands mid-flight, same as v1: the camera catches the Ferryman
  rising. No timing changes.
- **Cutscene assets** — C `intro_v3_ship.json` (limbo, player-anchored, 130t),
  C `intro_v3_flight.json` (overworld, world-anchored, 900t — keyframes are OFFSETS from
  the play anchor = vortex ground center; crane over the disc ring, ends 60 blocks out at
  ~14 up; carries its own captions, the t=0.955 fade-out and the shake), C
  `intro_v3_reveal.json` (300t orbit, offsets from the play anchor = altar position).
  D `intro_submerge.json` / D `intro_rise.json`; their SHA-256 appended to
  `CutscenePaths.LEGACY_DEFAULT_HASHES` and both removed from `DEFAULT_IDS` (per W2
  wiring). Operator note: stale `config/eclipse/cutscenes/intro_submerge|intro_rise.json`
  copies of deleted ids are left on disk by design — delete them manually if unwanted.
- **Quasar emitters** — C `eclipse_lightning_impact` (purple-white sparks, velocity
  stretch), C `impact_light` (emissive additive flash quads — NO `veil:light`, §7 trap),
  C `altar_reveal_burst` (purple+gold reveal fountain), C `glide_trail` (loop wisps —
  `FxPayloads`' glide events already attach/detach `eclipse:glide_trail`; the asset now
  exists), M `cutscene_veil` (bigger/denser per plan). None carry light modules.
- **Langdrop** `docs/plans_v3/langdrop/P2-W6.json` — 8 caption keys
  (`eclipse.caption.intro.depart/awaken/fuse/vortex/approach/strike/reveal/begin`), en+de.

## Wiring asks

- **`EclipseMod`**: none. **`sounds.json` aliases**: none.
- **Lang merge**: fold `langdrop/P2-W6.json` into `assets/eclipse/lang/en_us.json` +
  `de_de.json` at integration (frozen files this wave).
- **P4 (§6.3)**: when P4's trigger ships, call
  `IntroSequence.start(server, discCenters)` after its own disc teleports and remove the
  call in `StartEventCutscene.emerge` (or keep StartEventCutscene as the caller — the
  entry point is idempotent-guarded either way). When P4's permanent-rim world flag +
  login re-send land, remove the fallback re-send in `IntroSequence.onLoggedIn` (the
  `IntroData.permanentRim` field can stay; it is harmless).
- **`FxAnchors eclipse:altar_center`**: W6 sets it at FLIGHT t=500 and again at BURST
  (idempotent). §6.3 says P4/P6 own it — double-setting the same position is safe; keep
  whichever lands first.

## Risks / known trade-offs

- **FLIGHT gather**: `GLOBAL_TELEPORT` parks disc players (~170 blocks out) on the 6-block
  ring around the vortex center for the shot (clients must hold the chunks the camera
  crosses; W2 restores everyone to their exact disc spot after). They are frozen +
  invulnerable and the vortex is client FX, but they ARE physically at the center for
  ~45 s while the fusion sweep runs — W2's snapshots + SanctumProtection make this safe
  today; flag if P1 ever writes terrain at the gather ring.
- **BURST waits for the island flip**: the giant burst reveals the FLOATING island, so if
  the fusion sweep (budget-bound) has not flipped the sanctum to v2 when the lightning
  ramp ends, BURST holds at max fury (strike every 15t) until the flip or a 1200t timeout
  — a starved sweep degrades to revealing the grounded altar rather than wedging.
- **Straggler ACK gap**: a laggy client's ship-path ACK landing after the t=140 re-freeze
  would unfreeze that player until ECLIPSE_ON re-freezes at t=160 — behind the held black,
  ~1 s, cosmetic only.
- **Late joiners mid-cinematic** get the eclipse phase re-synced and a plain freeze for
  the rest of an active camera phase (no retro camera flight) — deliberate, keeps the
  group ACK machinery simple.
- **Replay contract**: `/eclipsefx sequence intro <phase>` is FX-only — LOCAL plays (no
  gather), raw `S2CStormStatePayload`s under reserved storm id 999006 (never touches
  `StormRegistry`), kickback off, no decor spawn, no `IntroData`/world-state writes.

## Test steps (dev world, 2+ clients, permission 3)

1. **Full run**: `/start_event` from limbo — expect: ship keel + deck flyaround → glitch
   to black (NO vanilla dimension screen) → wake standing on YOUR OWN disc facing center →
   eclipse ramps overhead + "THE ECLIPSE RISES" → crane flight over fusing discs (fusion
   sweep visibly running), vortex forms mid-flight at center → fade to black → control
   returns at your disc spot.
2. **Approach**: walk toward the smoke wall. At ~5 blocks from it: loud first strike from
   the eclipse straight down + kickback (never off the disc — repeat standing at the disc
   rim: the push flips inward). Strikes ramp faster/purpler over ~30 s.
3. **Burst + reveal**: giant center bolt → white→violet flash + shockwave → vortex
   collapses → 15 s orbit of the floating altar island with bobbing/rotating rubble
   displays → eclipse ends, "ES BEGINNT"/"IT BEGINS" → sun keeps the purple rim.
4. **Persistence**: relog — rim still there. Stop the server mid-FLIGHT and restart —
   world comes back in the end state (no eclipse, rim on, no stuck freeze, vortex gone).
5. **Replays** (each FX-only, no world edits): `/eclipsefx sequence intro ECLIPSE_ON`,
   `... intro FLIGHT` (vortex appears mid-shot, gone after), `... intro LIGHTNING` (full
   30 s ramp, no kickback), `... intro BURST`, `... intro REVEAL`, `... intro SUNRISE`.
6. **Decor idempotence**: `/kill @e[tag=eclipse_intro_decor]` near the island — the cloud
   re-appears within ~10 s (next reconcile pass).
7. **Finale regression**: day-14 egg ritual — arrival now plays `intro_v3_ship`; Ferryman
   still rises at t=100 mid-flight.
