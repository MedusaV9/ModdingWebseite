# PLAN F-077 — "Das End erscheint" Cutscene (End-Ankunft V2 "GIGANTISMUS")

> **Feedback** (UserFeedback.md, F-077): _"Erstelle eine Cutscene samt riesen Effekten mit
> Photon und Veil wenn das End erscheint mach eventuell das mit dem neuen Altar Model dann
> so eine krasse Animation kommt wie der Altar die Blöcke ausspuckt oder überlege dir was
> krasses selber."_
>
> **Lineage note:** a first pass ("Der Altar ruft das End", ~50 s) is ALREADY SHIPPED in
> commit `1f78a59` (see `docs/plans_v3/wiring/end_arrival_status.md`). It implements the
> user's core suggestion — the altar visibly spits out the End blocks — end to end. This
> plan (a) freezes the audit of that v1 so future agents stop re-discovering it, and
> (b) specifies the **V2 upgrade pass** that closes the remaining gap to "RIESEN Effekte
> mit Photon und Veil": Veil grade ramp, sky-rift glyphs, a bigger multi-strand eruption,
> silhouette-true wave assembly with giant shock rings, an end-purple sky pulse, a
> permanent ambient rift, layered custom audio and an MSPT guard. All new ids use the
> `end_arrival2_` prefix so shipped `end_arrival_*` assets are never touched in place.

---

## 1. Audit — current End-arrival flow (audited 2026-07-27, all paths verified in source)

### 1.1 Trigger chain (day 12, F-023/F-047 timeline)

| Step | Where | Detail |
|---|---|---|
| Day slot | `worldgen/end/EndConfig` | `DEFAULT_TRIGGER = "day:12"` ("THE SKY SHARD"), `dragonDay = 13`, `configVersion 2` self-migration off the legacy `day:9`. Frozen per save in `end.json`. |
| Poll | `worldgen/end/EndDiscService.onServerTick` | Every `TRIGGER_POLL_TICKS`; `triggerMatches` reads `progression/DayScheduler.getDay(server)`; hard guard: never on/before `HeraldsLureItem.HERALD_DAY` (day 7). |
| Build | `EndDiscService.materialize(server)` | Idempotent; sets `EclipseWorldgenState.endDiscMaterialized`, starts the budgeted `Job` writer, fires `announceCrash` (global `S2CEndCrashPayload` + 2.0 shake + dragon growl + chat line + client `EndIslandCrashFx` timeline). |
| Cinematic seam | `EndDiscService.materialize` → `sequence/endarrival/EndArrivalSequence.interceptFirstMaterialize` | The VERY FIRST materialize is claimed by the show; the sequence re-enters `materialize` at its phase-3 boundary through the `buildingDisc` latch. Restart-resume (`materializationStarted == true`) bypasses the show ("restart skips to end state" house rule). |
| Disc geometry | `worldgen/EndDiscGeometry` | Pure functions: `footprintContains`, `surfaceYAt`, `topYAt`, `stateAt`, plus the 8 obsidian pillars (`PILLAR_COUNT = 8`, `PILLAR_RING_RADIUS = 56`, `pillarX/Z/TopY`, `pillarCaged`). Disc surface ~Y 360. **This is the silhouette source V2 needs.** |

### 1.2 Shipped v1 cinematic (what already plays)

| Layer | File | Role |
|---|---|---|
| Phase machine | `sequence/endarrival/EndArrivalSequence.java` | 1000 t / 50 s, phases OMEN 0–160 / CHARGE 160–400 / SPILL 400–800 / FINALE 800–1000; beat clock arms on first cutscene preload ACK (`CutsceneService.onNextClientReady`, `PRELOAD_TIMEOUT_TICKS` fallback); shake pulse train; dimension-wide cue broadcast (`range 0.0`). |
| Altar anchor | `ritual/AltarModelTriggers.erupt(overworld)` at CHARGE enter | **Already wired** (the F-076 GeckoLib `erupt`/`tierup`-style beat) — item 1 of `end_arrival_wiring.md` is stale. |
| Display swarm | `sequence/endarrival/EndArrivalDebrisFx.java` | 220 BlockDisplays (cap 260), `StormDebrisFx` doctrine: ONE mount on the pillar axis, view-range 8×64, batch spawn 10/2 t, 3-t interpolation slices, 384-block presence gate, 2400-t watchdog, tag `eclipse_end_arrival_debris` + live-UUID join sweep, arrival **recycling** (constant stream, zero churn). Flight: 50 t helix climb + 76 t outward spiral onto a random ring slot (0.30–0.96 × r), snap-out to 0-scale; every 4th landing stamps `CUE_PUFF` (max 2/t). |
| Cue ids | `sequence/endarrival/EndArrivalFxCues.java` | 8 cues via `FxCues.cue(…)`: `end_arrival_{suction,rings,pillar,maw,wisp,puff,implosion,glitter}`; `a`-lane carries the real pillar height for `pillar`/`glitter` Y-scaling. |
| Client rows | `veilfx/EndArrivalFxRows.java` | 8 REPLACE rows, `FxBudget.Channel.SEQUENCE`, Quasar floors; wisp/puff use `allowMulti` legs. |
| Photon assets | `assets/eclipse/fx/end_arrival_*.fx(+.fxproj)` from `tools/photon/end_arrival_fx.py` | Suction, rings, 260-block HDR pillar beam, r=14 maw vortex, wisp, puff, implosion, glitter. |
| Camera | `assets/eclipse/cutscenes/end_arrival.json` (registered in `CutscenePaths.DEFAULT_IDS`) | 1000-t LOCAL path (no teleport), `allowSkip: true`, letterbox, hideHud, per-keyframe FOV; played by `CutsceneService.play(..., TeleportPolicy.LOCAL_ONLY, viewDistance 12)` for players ≤128 blocks of the altar. Events deliberately empty — the server broadcasts sound/shake/captions dimension-wide so free watchers get the identical read. |
| Dev seams | `devtools/dev/DevEndArrivalCommands.java` | `/dev event start endarrival [fxonly]`, `/dev event stop endarrival` (own brigadier tree merged into the `/dev event` root — the `/dev event start herold` pattern from `DevEventCommands`). |
| Cleanup | `core/EclipseShutdownSweep.onServerStopping` | `EndArrivalDebrisFx.clearAll()` already hooked (single-instance-swarm rule, next to `StormDebrisFx`). |
| Sound doc | `docs/plans_v3/wiring/end_arrival_sounds.json` | v1 = ZERO new sound events: layered eclipse events (`event.end_shatter_rumble/rift_whoosh/rift_drone/rift_thud`) + vanilla (portal trigger, beacon activate, end_portal spawn, dragon growl, thunder, explode). Explicitly lists the choir/drone pad as "optional upgrade for later" → V2 takes it. |

### 1.3 Reusable infra for V2 (pattern donors, exact classes)

- **Camera/cutscene**: `cutscene/CutsceneService` (per-player skip via `allowSkip`, abort, `activePathId`, preload-ACK arming), `cutscene/CutscenePaths`. No camera entity/spectate — paths are client-side camera flights, LOCAL keeps players in place.
- **Display swarms**: `worldgen/stage/StructureFlightFx` (flight→snap for REAL placements + `forceClearNow`), `sequence/StormDebrisFx`, `stormfx/StormSiege.forceClearNow`, `ritual/CreditsMapRipAct` (crust ≈2190 + 700 accretion = **≈2890 finale peak, audited < 3000**), `ritual/CreditsSequence.DISPLAY_HARD_CAP = 3600`, `worldgen/stage/DisplayBrightnessFx` (brightness + view-range NBT).
- **Veil post**: `veilfx/VeilPostController` — `world_grade` pipeline (GRADE band) with frozen uniforms `EclipseAmount/NightAmount/DesatAmount/ExposureMul/PhaseTint(+Time/HorizonY/Detail)` in `pinwheel/shaders/program/world_grade.fsh`; the **"additive uniform, same feeder, same commit"** precedent (v2/v3 header comments) is the sanctioned way to extend it. Full-pipeline donors: `woah/chronostasis/client/ChronoGradeFx` (desat+vignette grade, `PipelineSpec` on GRADE band), `client/credits/CreditsSkyFx` (payload-driven eased `skyDarken`/`starBrightness` — credits-owned, resets on logout, do NOT reuse directly).
- **Ambience over the disc**: `client/end/EndVoidWisps` (1200 GPU-instanced wisps around the disc rim, windowed controller) already ships — V2's permanent rift ambient joins it, not replaces it.
- **MSPT guard**: `worldgen/stage/GrowthPacing`/`ExpansionTiming.PREGEN_MSPT_GUARD_MS` (`msptGuard` config, "issue nothing above N ms/tick") — the house pattern to copy.
- **Audio tooling**: `tools/music/treblo_generate.py` (Sonauto API, `TREBLO_API_KEY`, two-pass loudnorm −16 LUFS, 48 kHz Vorbis) + `tools/music/validate_oggs.py`. No offline SFX synthesizer exists yet in `tools/`.

### 1.4 Gap analysis (v1 vs the F-077 ask)

| Ask (storyboard beat) | v1 status | V2 work |
|---|---|---|
| B1 world dims (Veil vignette + desat ramp) | ✗ (only shake + suction) | WP-A |
| B1 sky-rift glyphs gather over altar | ✗ | WP-B |
| B2 helix geyser, 2–3 intertwined strands + comet trails | ~ (one 220-piece helix, no strands/trails) | WP-C |
| B3 blocks snap into **island silhouettes wave by wave** | ✗ (random ring slots) | WP-D |
| B3 giant Photon shockwave ring per completed wave | ~ (small `CUE_PUFF` only) | WP-D |
| B4 Veil sky shift (end-purple starfield tint pulse) | ✗ | WP-E |
| B4 permanent subtle end-rift ambient over the disc | ✗ (show ends clean) | WP-F |
| Layered custom audio (sub-boom, riser, choir, snap ticks) | ✗ (vanilla/eclipse reuse only) | WP-G |
| MSPT guard | ~ (presence gate only) | WP-H |
| Trigger day 12 + `/dev event start endarrival` + skippable camera + multiplayer scoping | ✓ shipped | regression-test only |

---

## 2. V2 storyboard — full timeline table

Keep the shipped 4-phase machine and boundaries (OMEN 160 / CHARGE 400 / SPILL 800 /
TOTAL 1000). The **action window** erupt→title (t 160–870 ≈ 35.5 s) sits inside the
25–40 s target; OMEN is the skippable pre-roll. Do not re-time a tuned, shipped sequence.

Legend: `[V2]` = new in this plan; everything else ships today and stays. Camera column
= the `end_arrival.json` leg covering that range (`t` = fraction of 1000).

| Ticks | Beat | Camera (existing path) | Displays | Photon cues | Veil uniforms `[V2]` | Sounds |
|---|---|---|---|---|---|---|
| 0–80 | **B1 Herzschlag I** — suction streaks collapse onto altar, world starts to dim | t 0–0.1 close orbit on altar | — | `CUE_SUCTION` (re-fire /80 t) | `ArrivalDim` 0→0.35, `DesatAmount` +0→0.25 ramp | `end_shatter_rumble` p0.4, cave ambience; `[V2]` `end_arrival2_subboom` every 40 t (heartbeat) |
| 80–160 | **B1 Herzschlag II** — glyph ring gathers in the sky over the altar | t 0.1–0.16 drift out | — | `[V2]` `CUE_GLYPHS` @ altar+40 (a = ring radius) | `ArrivalDim` hold 0.35 | `[V2]` `end_arrival2_riser` (8 s, ends ON t 160); portal ambient /64 t |
| 160 | **B2 Eruption-Schlag** — altar GeckoLib `erupt` anim (F-076 anchor) | t 0.16–0.24 tremor pull-back | — | `CUE_RINGS`; glyphs snap out | `ArrivalDim` spike 0.5→release 0.2 over 40 t | portal trigger p0.55, rumble p0.6, `[V2]` subboom ff |
| 200 | **B2 Säule** — violet pillar fires to the rift point | t 0.24–0.34 tilt-up | — | `CUE_PILLAR` (a = real height) | — | beacon activate, `rift_whoosh`, shake 0.65 |
| 240 | **B2 Riss** — giant maw tears open; END portal-spawn moment | t 0.34–0.46 ride the pillar | — | `CUE_MAW`, `FX_SHOCKWAVE`(0.5/25) | — | end_portal spawn p0.6, `rift_drone` p0.5 |
| 400 | **B3 Assembly-Start** — REAL `EndDiscService.materialize` + crash announce; debris stream arms | t 0.46–0.62 wide crane past the rift | `[V2]` stream fills to **600** (cap 700), **3 phase-offset helix strands** | `[V2]` `CUE_STRAND_TRAIL` ×3 (comet trails pinned to strand axes, a = pillar height) | `ArrivalDim` → 0.15 simmer | announceCrash (2.0 shake, growl, thunder, chat), `[V2]` `end_arrival2_choir` loop starts |
| 400–800 | **B3 Wellen** — `[V2]` wave-by-wave silhouette assembly: 5 waves of 80 t, targets sampled from `EndDiscGeometry.topYAt` columns (wave k = annulus k/5 of the footprint + pillars last); arrivals snap at REAL surface positions | t 0.62–0.78 crossing to the Totale (easeInOutQuart) | recycled stream, arrivals steered per wave | `CUE_WISP` /25 t, `CUE_PUFF` (≤2/t), `[V2]` `CUE_ISLAND_RING` at each wave's annulus mid-radius on wave completion (t 480/560/640/720/790, a = ring radius 30–96) + `FX_SHOCKWAVE`(0.6/30) on waves 3+5 | — | `[V2]` `end_arrival2_snap` (3 vars, ≤2/t, on puff-stamped arrivals); violet lightning /50 t (thunder p0.5–0.7 + whoosh); dragon-breath exhale |
| 800 | **B4 Implosion** — rift snaps shut, stream collapses (50 t rush) | t 0.78–0.9 implosion framing | collapse + discard | `CUE_IMPLOSION`, `CUE_GLITTER` (a = height), `FX_SHOCKWAVE`(0.9/45) | `[V2]` `EndTintPulse` 0→1 over 20 t (purple grade + star push) | `rift_thud` p0.9, explode p0.6, shake 0.85/45 |
| 850–870 | **B4 Reveal** — distant dragon herald + title | t 0.9–1.0 settle/push onto the disc | — | — | `EndTintPulse` decay 1→0.25 | growl p0.5 (+ per-player notify), caption `…arrived` STYLE_TITLE |
| 870–1000 | **B4 Ausklang** — fade back to player control | path ends, FOV eases back | — | `[V2]` first `CUE_RIFT_AMBIENT` fires @ disc center | `EndTintPulse` → 0, `ArrivalDim` → 0 | `[V2]` `end_arrival2_drone` one-shot; shake tail 0.12 |
| after | **Permanent** — subtle end-rift ambient over the disc, forever | — | — | `[V2]` `CUE_RIFT_AMBIENT` re-fired /600 t by `EndRiftAmbient` while disc exists | — | (silent; `EndVoidWisps` already covers rim ambience) |

Multiplayer/skip (unchanged, regression-test): camera ONLY for non-spectator players
≤128 blocks of the altar, `PlayOptions(LOCAL_ONLY, 12, false, true)`, `allowSkip: true`
(per-player skip; beats keep broadcasting); everyone else in the overworld sees the
sky-sized show + all sounds/captions/shakes (cue range `0.0` = whole dimension).

---

## 3. Work packages (V2)

- **WP-A Grade-Ramp (Veil)** — additive uniforms `ArrivalDim` + `EndTintPulse` in
  `world_grade.fsh` (vignette-weighted exposure drop + desat; purple tint + star-region
  lift), fed by `VeilPostController`'s existing feeder from a new client-side
  `client/end/EndArrivalGradeState` (eased from/target/startTick scalars — the
  `EclipseFxState` recipe). Server drives it via ONE new payload-less cue on the position
  lane: `CUE_GRADE` with `a` = target, `b` = ramp ticks. Respect `reducedFx` (gate off,
  the `ChronoGradeFx` rule). No new pass — stays inside the GRADE-band ≤3-pass budget.
- **WP-B Glyphs** — new Photon one-shot `end_arrival2_glyphs` (rotating rune ring, ~24
  glyph sprites converging + SAC-violet palette), cue `CUE_GLYPHS` at altar+40, fired
  t 80, snapped out at t 160 by row REPLACE.
- **WP-C Eruption upscale** — `EndArrivalDebrisFx`: `STREAM_TARGET 220→600`,
  `HARD_CAP 260→700`, `SPAWN_BATCH 10→14`; give `Piece` a `strand` (0–2) quantizing
  `climbAngle0` to three 120°-offset lanes with shared `climbSpin` sign per strand →
  three readable intertwined streams. New cue `CUE_STRAND_TRAIL` (long-lived comet-trail
  beam per strand, Y-scaled like `CUE_PILLAR`, re-fired on the 100-t long-cue cadence).
- **WP-D Silhouette waves** — replace random ring slots: at `begin`, sample ~400 landing
  columns from `EndDiscGeometry` (`footprintContains` grid stride + `topYAt`, pillars
  via `pillarX/Z/TopY` reserved for wave 5), bucket into 5 annulus waves; `rearm` draws
  targets only from the active wave's bucket (opened every 80 t). On bucket exhaustion
  fire `CUE_ISLAND_RING` (giant horizontal expanding ring, r up to ~96) + `FX_SHOCKWAVE`
  on waves 3/5. Landing Y = real `topYAt + 1` → the disc visibly "fills in" where blocks
  land (the writer materializes the truth underneath, `StructureFlightFx` flight→snap read).
- **WP-E Sky pulse** — covered by WP-A's `EndTintPulse` (no `CreditsSkyFx` reuse — that
  state is credits-owned and logout-reset).
- **WP-F Permanent rift ambient** — new Photon `end_arrival2_rift_ambient` (faint slow
  vortex shimmer + occasional spark fall, AMBIENT budget channel row) + tiny server
  ticker `worldgen/end/EndRiftAmbient` (re-fires `CUE_RIFT_AMBIENT` at disc center every
  600 t while `EndFightState.materializationComplete()`, 512-block range, presence-gated).
- **WP-G Audio** — new deterministic offline generator `tools/music/gen_endarrival_sfx.py`
  (numpy synth → ffmpeg loudnorm −16 LUFS/48 kHz Vorbis, validated by
  `tools/music/validate_oggs.py`): `end_arrival2_subboom` (40–60 Hz sine + click),
  `end_arrival2_riser` (8 s shepard-ish sweep), `end_arrival2_choir` (20 s loopable
  detuned pad), `end_arrival2_snap` ×3 (short chorus-flower-like ticks),
  `end_arrival2_drone` (12 s end-ambience tail). Register in `registry/EclipseSounds` +
  `assets/eclipse/sounds.json` (now unlocked). Fallback if synth quality disappoints:
  keep the shipped vanilla mix (documented in `end_arrival_sounds.json`) — swap is
  isolated to `EndArrivalSequence` sound calls. Optional: Treblo for the choir pad if
  `TREBLO_API_KEY` is available.
- **WP-H MSPT guard** — `EndArrivalDebrisFx.tick()`: read the server's average tick time;
  above 45 ms (constant, mirroring `ExpansionTiming.PREGEN_MSPT_GUARD_MS` doctrine) skip
  spawn batches and halve push slices (animate every 6 t; interpolation duration follows) —
  degrade smoothly, never discard mid-show.
- **WP-I Consolidation (from `end_arrival_wiring.md`)** — merge
  `docs/plans_v3/langdrop/end_arrival.json` into `en_us.json`/`de_de.json` (+ new V2 keys);
  optionally fold `EndArrivalFxCues` ids into `network/fx/FxCues`; delete the stale
  "erupt not wired" item.

---

## 4. New Photon assets (author via `tools/photon/end_arrival_fx.py`, fxlib validate)

| Asset (`assets/eclipse/fx/…`) | Type | Notes |
|---|---|---|
| `end_arrival2_glyphs` | one-shot ~80 t | converging rune ring @ altar+40, SAC violet + GLI sparks |
| `end_arrival2_strand_trail` | long-lived 620 t, Y-scaled (a/260) | comet-trail sheath per helix strand, additive HDR |
| `end_arrival2_island_ring` | one-shot ~50 t, XZ-scaled (a/60) | giant horizontal expanding shock ring, dark-on-light rim like `day_rift_maw` |
| `end_arrival2_rift_ambient` | looping ambient ~1200 t | faint vortex shimmer + rare spark fall over the disc |

Rows: extend `veilfx/EndArrivalFxRows` — 3 SEQUENCE-channel REPLACE rows (glyphs, trail
`allowMulti` ×3, ring `allowMulti`) + 1 AMBIENT-channel row (rift ambient). Cues: extend
`sequence/endarrival/EndArrivalFxCues` (`CUE_GLYPHS`, `CUE_STRAND_TRAIL`,
`CUE_ISLAND_RING`, `CUE_RIFT_AMBIENT`, `CUE_GRADE`) — same `FxCues.cue`/
`FxPayloads.sendFxEvent(id, pos, a, b, range)` wire format.

---

## 5. Performance / budget

- Peak concurrent BlockDisplays: **700 (hard cap)** — one swarm, far below the ≈2890
  credits-V3 audited peak and the 3600 `CreditsSequence` cap; no other cinematic swarm
  can legally run concurrently (single-instance rule + `SessionLock`-style begin guard).
- Packet budget unchanged in shape: 3-t slices ⇒ ~200 transform pushes/t at 600 pieces
  (v1: ~73). WP-H's MSPT guard halves that under load; the 384-block presence gate
  zeroes it with nobody near.
- Spawn/despawn: staggered 14/2 t fill (~86 t to full), recycling keeps churn at zero;
  collapse rush 50 t; watchdog 2400 t; `EclipseShutdownSweep` + join-sweep + `/kill
  @e[tag=eclipse_end_arrival_debris]` unchanged.
- Veil: zero new post passes (additive uniforms only); 4 new Photon rows inside existing
  SEQUENCE/AMBIENT budget channels.

## 6. Test checklist (RCON-driven + client observation)

1. `./gradlew build` clean; `python3 tools/photon/fxlib.py validate` green;
   `python3 tools/music/validate_oggs.py` green over new oggs.
2. RCON (`tools/rcon/rcon.py`), fresh dev world: `/dev event start endarrival fxonly` →
   log `End arrival sequence started`; verify no `EndFightState` flag committed after.
3. Client (observer ≤128 blocks of altar): letterbox camera starts after black hold;
   B1 world dim + desat ramp visible, glyph ring gathers; **skip (allowSkip)** returns
   control while sounds/shakes continue.
4. B2: altar `erupt` anim (F-076), rings, pillar, maw + small distortion ring on cue
   ticks 160/200/240 (count from the preload-ACK arm, not sequence start).
5. B3: three distinct intertwined strands with comet trails; arrivals land ON disc
   silhouette columns, filling annulus waves inward→outward, pillars last; giant ring +
   shockwave at each wave completion; snap ticks audible, ≤2/t.
6. B4: implosion, glitter, purple sky pulse that decays (not sticks), title caption,
   camera settles on the disc, FOV eases back; after t 1000 the ambient rift shimmer
   remains and survives relog + server restart (re-fired by `EndRiftAmbient`).
7. Real path: `/eclipse day set 12` (or wait) → poll fires → full show, then `/dev event
   start endarrival` refused (`…busy`/already built); disc writer completes; dragon fight
   arms on `dragonDay` 13 unchanged.
8. Abort/cleanup matrix: `/dev event stop endarrival` mid-B3 → zero displays
   (`/kill @e[tag=eclipse_end_arrival_debris]` count 0), cameras released, grade/tint
   uniforms decay to 0; server crash mid-B3 → join sweep discards strays, show restarts
   from top (pre-phase-3) or resumes writer silently (post-phase-3).
9. Perf: `/forge tps` (or `/dev stats`) during B3 with 600 pieces — MSPT guard halves
   pushes when artificially loaded; second player 500 blocks away sees zero packets
   (presence gate) and no camera.
10. Multiplayer: player at spawn (>128 blocks, same dimension) hears/sees sky show +
    captions but keeps camera; nether player unaffected.

## 7. Risks / open decisions

- Silhouette sampling cost (WP-D) is a one-off ~400-column `topYAt` pass at `begin` —
  cheap, but do it lazily on the SPILL boundary, never in the trigger poll.
- 600 pieces × 3-t slices is 2.7× v1's packet rate; if playtest MSPT spikes, first lever
  is `UPDATE_INTERVAL_TICKS 3→4` (imperceptible at these speeds), then stream size.
- Synth SFX quality is the plan's softest spot — the shipped vanilla mix stays the
  committed fallback (swap isolated to `EndArrivalSequence`).
- Camera keyframes are geometry-tolerant (rift assumed ~300–360 over the altar); a
  reshoot pass after the V2 playtest is budgeted, same as v1.

---

## 8. Status (implemented 2026-07-27 — awaiting orchestrator compile + RCON playtest)

- [x] **WP-A Grade-Ramp (Veil)** — `ArrivalDim`/`EndTintPulse` uniforms in
  `world_grade.fsh`, fed by `VeilPostController.feedWorldGrade`; eased scalars live in
  `EclipseFxState` (additive, the new-land-glow precedent) instead of a new
  `client/end/EndArrivalGradeState` class — same recipe, one fewer class, logout reset
  for free via `clearAll()`. Cues `CUE_GRADE`/`CUE_TINT` dispatch as explicit
  `FxPayloads` branches (the `CUE_GROWTH_RIDER` shape). `wantWorldGrade` keeps the pass
  alive in plain daylight while either feed is > 0.005.
- [x] **WP-B Glyphs** — `end_arrival2_glyphs.fx` (fxlib-validated), `CUE_GLYPHS` fired
  at t 80 @ altar+40; the ~80 t one-shot dies naturally ON the t 160 erupt.
- [x] **WP-C Eruption upscale** — `STREAM_TARGET 600` / `HARD_CAP 700` /
  `SPAWN_BATCH 14`; strand lane quantized in `rearm` (no `Piece.strand` field needed —
  the lane only shapes `climbAngle0`), all strands co-rotate at `STRAND_SPIN 0.26 ±10 %`;
  `CUE_STRAND_TRAIL` (one asset sheathing all three strands, Y-scaled a/260, 100-t
  refire cadence).
- [x] **WP-D Silhouette waves** — `sampleWaveTargets` grid (stride 9, ≈400 columns +
  8 pillar tops in the last bucket), 5 annulus waves opened every 80 t inward→outward;
  transit spiral lands EXACTLY on the sampled column (sweep wraps + full extra turn for
  near-radial paths). Wave rings fire on the SEQUENCE's deterministic clock
  (t 480/560/640/720 + hero ring at 790, not on bucket exhaustion — recycling reuses
  targets, so "exhaustion" never happens); `FX_SHOCKWAVE` 0.6/30 on waves 3 and 5.
- [x] **WP-E Sky pulse** — via WP-A `EndTintPulse` (flash 1.0 @ t 800 → afterglow 0.3
  @ t 840 → decay 0 @ t 980).
- [x] **WP-F Permanent rift ambient** — `end_arrival2_rift_ambient.fx` (~660 t
  one-shot, AMBIENT row) + `worldgen/end/EndRiftAmbient` (600-t refire, presence-gated
  512, only while `materializationComplete`); the sequence stamps the first ambient at
  t 980 so fxonly replays also show it once.
- [x] **WP-G Audio** — `tools/music/gen_endarrival_sfx.py` (numpy → ffmpeg loudnorm
  **−14 LUFS, mono 44.1 kHz** — matching the shipped `event/*.ogg` conventions, NOT the
  music-track −16/48k/stereo spec; `validate_oggs.py` is music-scoped so the generator
  self-verifies via ffprobe). 7 oggs generated (subboom/riser/choir/snap_a-c/drone, all
  ≤ 6 s — riser shortened from the planned 8 s, choir loops via 120-t refire instead of
  one 20 s file). Registered as `event.end_arrival_*` in `EclipseSounds` + `sounds.json`
  (ogg filenames use the sounds/event/ dir, hence no `2` in the asset names).
- [x] **WP-H MSPT guard** — 45 ms trip / 38 ms recover hysteresis, checked every 20 t:
  spawns pause + push windows double to 6 t (slices pre-assigned mod 6 so the degraded
  cadence stays even).
- [x] **WP-I Consolidation** — `docs/plans_v3/langdrop/end_arrival2.json` (5 subtitle
  keys en+de; lang files stay locked, merge later with `end_arrival.json`). Cue ids kept
  in `EndArrivalFxCues` (folding into `FxCues` deferred — no functional need, less churn).
- [x] **Photon assets** — `tools/photon/end_arrival2_fx.py` authored + run; all 4
  `.fx`/`.fxproj` pairs written and fxlib round-trip validated.
- [ ] Orchestrator: `./gradlew build` + RCON playtest (`/dev event start endarrival
  fxonly` → observe; `/dev event stop endarrival` → dim/tint release check).
