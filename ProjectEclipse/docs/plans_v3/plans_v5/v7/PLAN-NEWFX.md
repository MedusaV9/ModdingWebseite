# PLAN-NEWFX — 20 NEW Veil/Photon effects for FX-naked moments (v7)

Author: PLAN-FX-NEW (read-only sweep, 2026-07). Mission: the user wants MORE **new** Veil
(Quasar/post) and Photon effects beyond polishing existing ones. This plan is the result of
a full-game sweep for **FX-naked moments** — player-visible beats that currently have weak
or zero world-side FX — and defines the TOP 20 as buildable specs split into four disjoint
worker packages (NEWFX-A/B/C/D).

Read-first (frozen laws, do NOT renegotiate):

- `docs/plans_v3/plans_v5/photon/INTEGRATION.md` — §3 registry lane (`FxCues` →
  `S2CFxEventPayload`/`S2CFxEntityEventPayload` → `PhotonFxRegistry.Row`), §4 loop law
  (WINDOWED-only, `SanctumLightfall` hysteresis pattern), degradation invariant
  ("no code path may make Photon absence worse than baseline").
- `docs/plans_v3/plans_v5/photon/API.md` — Photon runtime surface; `.fx` authoring workflow
  (§6): author in-editor, export, ship in `assets/eclipse/fx/`; `tools/photon/fxlib.py` is
  the scripted-generation precedent (every prior FX wave shipped generator scripts).
- `src/main/java/dev/projecteclipse/eclipse/veilfx/FxBudget.java` — channels
  AMBIENT/BURST/SEQUENCE/STORM, per-window caps, `qualityTier()` (2 full / 1 reducedFx /
  0 minimal; tier 0 kills AMBIENT). Photon spawns are never budget-charged; `reducedFx`
  hard-disables the whole Photon leg inside `PhotonBridge.available()` and
  `MAX_LIVE_EXECUTORS = 24` caps live executors.
- `src/main/java/dev/projecteclipse/eclipse/veilfx/PhotonFxRegistry.java` — row API,
  LAYER/REPLACE modes, `ensureLoop`/`releaseLoop`, duplicate-id refusal (first wins).
- House rules: server stays photon-blind (only `FxCues` ids on the wire); never register a
  high-frequency cue with a Photon leg; loop assets ship a cull box + modest
  `maxParticles`; sender owns audio; statics reset on `ServerStoppedEvent`.

---

## 1. Sweep result — every candidate verified

Sweep method: read the event/service classes of each candidate seam and checked for any
Quasar payload, `FxPayloads` cue, Photon row, or client renderer tied to the moment.
"NAKED" = text/sound only. "WEAK" = vanilla `sendParticles` or a grade-only accent.
"COVERED" = existing FX judged sufficient → dropped from the TOP 20 (§4 lists why).

| # | Moment | Verdict | Evidence (file, behavior found) |
|---|--------|---------|--------------------------------|
| 1 | Day rollover dawn ceremony | **WEAK** (sky pulse + bells only) | `drama/DawnCeremony` — eclipse-phase sun pulse + 3 bell tolls + captions; zero particles anywhere |
| 2 | Quest completion | **NAKED** | `progression/goals/QuestEngine.feedback` — action-bar line + chime, nothing world-side |
| 3 | Collection tier-up world-side | **NAKED** | `collections/CollectionsService.applyTierGrant` — toast payload + chat line only |
| 4 | Rebirth ceremony | **WEAK** (vanilla only) | `rebirth/RebirthService.ceremony` — TOTEM/REVERSE_PORTAL/END_ROD `sendParticles`; no Veil/Photon |
| 5 | Heart loss/gain | **COVERED** | `hearts/client/HeartBurstOverlay` + `HEART_BURST` Quasar (`LifecycleEvents`, `AltarBlockEntity`) + `CUE_HEART_THEFT` soul arc |
| 6 | Altar offering rejection | **NAKED** | `ritual/AltarBlockEntity.handleOffering` "already" branch — action bar + FIRE_EXTINGUISH; acceptance has a full swallow/beam show, rejection has nothing |
| 7 | Border first-approach discovery | **NAKED** (as a discovery beat) | `border/client/BorderFxRenderer` only lights up within `fxRange` (default 8 blocks); no one-time "the world has edges" reveal |
| 8 | Nether descent transit (in-hole flight) | **WEAK** | `worldgen/nether/BreachTransferService` drift tick — vanilla REVERSE_PORTAL orbit + WHITE_ASH/SOUL server particles; client `BreachClientFx` only pulses the glitch at hand-off |
| 9 | End sky-launcher flight trail | **COVERED** | `CUE_SKY_LAUNCH` contrail rides the flyer (entity lane), `CUE_SKY_LAUNCH_CHARGE` helix (`WorldPhotonFxRows`) |
| 10 | Dungeon entrance discovery | **NAKED** | `worldgen/structure/UndergroundSites` sites have no discovery moment at all (not in `DiscMapData` landmarks; `DungeonSpawners` has no first-entry hook) |
| 11 | Boss spawn announcements world-side | **WEAK** (distance gap) | `network/boss/BossPayloads.sendIntro` — intro card + `CUE_BOSS_INTRO_SHOCKWAVE` capped at `INTRO_RANGE = 96`; distant players get nothing visible |
| 12 | Contract window open/close world cues | **NAKED** | `contracts/ContractService.beginOmen/beginActive/resolveExpired` — announce + shake + music cue; zero world visuals |
| 13 | Minigame start/finish | **NAKED/WEAK** | `minigames/MinigameService.start/beginClosing` — chat broadcasts; portal only has the cheap soul-flame ambient; `ElytraRace.finishLap` — chat only |
| 14 | Supply drop incoming warning | **NAKED** (pre-drop) | `economy/SupplyBeacon.drop` — crate + beam appear instantly; no warning beat exists before the marker |
| 15 | Wizard trade moment | **WEAK** | `entity/wizard/WizardOrinEntity.tryQuestTurnIn` — vanilla END_ROD puff + chime + `trade` anim |
| 16 | Bestiary unlock | **COVERED (client)** | `progression/bestiary/BestiaryService.sync` → client sting + caption; world halo would duplicate #3's celebration language → dropped |
| 17 | Skill point spend | **NAKED** | `skills/SkillService.buyNode` — sound + action bar only |
| 18 | Death→ghost transition (world-side) | **NAKED** | `lives/LifecycleEvents`/`BanService` — ban at 0 hearts is invisible to bystanders at the corpse (ship theater is HUD/limbo-side only, `DeathFlowHooks`) |
| 19 | Revive completion | **WEAK** | `ritual/ReviveRitual.complete` — global thunder SOUND only; beams exist only during the ritual |
| 20 | Xbox/backrooms portal ambient draw-in | **WEAK** | `xboxevent/XboxPortal.ambientTick` / `backrooms/BackroomsPortal.ambientTick` — vanilla fallback columns; star-rift renders but nothing is *pulled in* |
| 21 | Map-edge void wall visuals | **COVERED** | `border/client/BorderFxRenderer` glitch patches + `BORDER_GLITCH` bursts + Veil post proximity grade; `CUE_END_VOID_WISPS` owns the end disc |
| 22 | Eclipse totality peak moment | **WEAK** | grade ramps smoothly (`S2CEclipsePhasePayload` → `VeilPostController`), `ECLIPSE_TOTALITY` music rung exists; no visual *peak* punctuation (`SunTracker` gives screen-space sun pos, unused for this) |
| 23 | Music track transitions | **COVERED enough / dropped** | `music/MusicManager` crossfades; a visual accent on an audio event risks reading as a glitch and has the weakest moment-value of the sweep |
| 24 | Storm approach warning | **WEAK** | `stormfx/StormInteriorFx.approachAmount` — 15 % fog pre-tint only (60→20 block band); zero particle layer outside the wall |
| 25 | Village/landmark discovery flare | **NAKED** | `progression/LandmarkDiscoveryService.discover` — log line + unlock-key resync; the discovering player sees literally nothing |

**Dropped (5):** #5 hearts, #9 sky-launcher trail, #21 void wall (all genuinely covered),
#16 bestiary (client celebration exists; world-side would duplicate the collection halo
language), #23 music transitions (lowest value; audio-triggered visuals read as bugs).
The remaining **20** are the plan.

---

## 2. TOP 20 effect specs

Format per effect — **Name** (`cue id` / asset id) · TRIGGER SEAM (file + method) · TECH
(Photon / Veil-Quasar / both, LAYER|REPLACE, one-shot|WINDOWED loop) · VISUAL (2 lines) ·
BUDGET (Quasar-leg channel) · REDUCEDFX.

New cue ids follow `FxCues.cue("<name>")`; new Photon assets ship as
`assets/eclipse/fx/<name>.fx` (generator script per package, `fxlib.py` pattern); new
Quasar emitters as `assets/eclipse/quasar/emitters/<name>.json`. Every cue keeps a Quasar
fallback leg unless noted (Photon-only garnish is legal for NEW cues — pre-row baseline
was nothing, `PhotonFxRegistry.Row` javadoc).

### NEWFX-A — progression & personal celebration (server seams, entity lane heavy)

**A1. Decree Sigil Burst** (`cue/quest_complete`, `eclipse:quest_sigil_burst`)
- SEAM: `progression/goals/QuestEngine.feedback(player, spec)` — one
  `sendFxEntityEvent` beside the existing chime; `a` = goalKind ordinal (MAIN gets the
  large variant). Team completions fire per credited online player (dedup-free: entity
  anchors differ).
- TECH: both, LAYER, one-shot (~30 t). Photon entity-anchored; Quasar fallback ring.
- VISUAL: a rune-ring snaps open at chest height and shatters upward into gold-violet
  glyph shards; MAIN goals add a 2-block light pillar for one beat.
- BUDGET: BURST. REDUCEDFX: Photon leg auto-off; Quasar ring at halved rate; no light.

**A2. Collection Tier Halo** (`cue/collection_tier`, `eclipse:collection_tier_halo`)
- SEAM: `collections/CollectionsService.applyTierGrant` (announce branch, beside the
  toast payload) — entity lane on the collector; `a` = tierNumber (scale ladder).
- TECH: both, LAYER, one-shot (~40 t).
- VISUAL: a horizontal halo of item-glint motes rises boot→head and tightens into a
  crown flash; tier ≥ 4 (shard-paying tiers) adds a brief gold rain.
- BUDGET: BURST. REDUCEDFX: Quasar-only, mote count halves via channel budget.

**A3. Skill Spark Column** (`cue/skill_spend`, `eclipse:skill_spend_spark`)
- SEAM: `skills/SkillService.buyNode` OK branch (beside `SKILL_LEVELUP` sound).
  Entity lane; `a` = node cost (1–3 sparks). Deliberately small — spends can be rapid;
  the server sends at most one cue per player per second (guard in the seam).
- TECH: Quasar-first; Photon leg only a subtle lens glint (REPLACE would be overkill →
  LAYER with a near-invisible Photon garnish, or Photon leg `null` if authoring time is
  short — registrar decides, both legal).
- VISUAL: 2–3 cyan sparks orbit the hand once and pop; a hint of the skill-tree
  constellation flickers over the forearm for 10 t.
- BUDGET: BURST. REDUCEDFX: unchanged Quasar (cheap), Photon off.

**A4. Landmark Discovery Flare** (`cue/landmark_discovered`, `eclipse:landmark_flare`)
- SEAM: `progression/LandmarkDiscoveryService` — the sweep loop knows the discovering
  player and the landmark center; send ONE position-lane cue at the landmark center
  (range 128, everyone nearby shares the reveal) + the entity-lane echo on the
  discoverer. `discover(server, id)` keeps its signature; the sweep call site passes pos.
- TECH: both, LAYER, one-shot (~60 t).
- VISUAL: a cartographer's compass-rose of light unfurls over the landmark and
  dissolves into drifting map-ink motes that sink toward the site; discoverer gets a
  small personal glint echo.
- BUDGET: SEQUENCE (rare, landmark-grade). REDUCEDFX: Quasar-only, no discoverer echo.

**A5. Catalyst Handover** (`cue/wizard_catalyst`, `eclipse:wizard_catalyst_handover`)
- SEAM: `entity/wizard/WizardOrinEntity.tryQuestTurnIn` success branch (replaces
  nothing; the END_ROD puff stays as photon-less floor). Entity lane anchored on Orin;
  `a` = 0 reserved.
- TECH: both, LAYER, one-shot (~50 t, delay-choreographed to the `trade` anim).
- VISUAL: amethyst + umbral shards spiral from the player's hands into Orin's staff,
  fuse in a white-violet flash, and the catalyst drops out riding a tiny star trail.
- BUDGET: BURST. REDUCEDFX: existing vanilla END_ROD baseline only.

### NEWFX-B — altar, souls & ceremonies (ritual/lives server seams)

**B1. Dawn Toll Bloom** (`cue/dawn_toll`, `eclipse:dawn_toll_bloom`)
- SEAM: `drama/DawnCeremony.dawnToll` — one position-lane cue per player (their own
  pos, range 0-ish/personal) per toll is too spammy; instead ONE cue per player at
  T+BEAT_TOLL via the entity lane, asset internally paced to the 3×8 t toll rhythm.
- TECH: both, LAYER, one-shot (~40 t; startDelay stages inside the asset).
- VISUAL: three soft god-ray petals bloom overhead in sync with the descending bells,
  each shedding a ring of bell-glint dust that sinks and fades — the sky briefly reads
  as a cathedral.
- BUDGET: SEQUENCE (ceremony window). REDUCEDFX: skip entirely (the sun pulse + bells
  already carry the beat; ceremony law: reduced players keep pre-plan behavior).

**B2. Starfall Rebirth** (`cue/rebirth_ceremony`, `eclipse:rebirth_starfall`)
- SEAM: `rebirth/RebirthService.ceremony` — entity lane on the reborn player, sent to
  64-block bystanders; existing vanilla totem/portal spam becomes the photon-less floor.
- TECH: both, **REPLACE** (Photon supersedes the vanilla-ish Quasar composition; Quasar
  leg `eclipse:rebirth_ring` runs when Photon is absent).
- VISUAL: the sky drops 5–7 slow star-streaks that converge into the player, an indraw
  shell collapses to a blinding seam, then a wing-shaped shell of violet fire snaps
  open and rains ash-glitter — a proper "reborn" exclamation.
- BUDGET: SEQUENCE. REDUCEDFX: vanilla ceremony untouched (current behavior).

**B3. Offering Gutter** (`cue/offering_reject`, `eclipse:offering_gutter`)
- SEAM: `ritual/AltarBlockEntity.handleOffering` — both refusal branches ("already
  offered": pre-check AND post-`acceptWithValue` empty), position lane at the altar
  crown, range 32. The anti-climax to the swallow's climax.
- TECH: both, LAYER, one-shot (~25 t).
- VISUAL: the altar's flame shrinks to a cold ember, coughs one gray ash puff that
  falls (never rises), and two dim violet wisps retreat INTO the stone — refusal read
  in one glance, values stay secret.
- BUDGET: BURST. REDUCEDFX: Quasar puff only.

**B4. Soul Departure** (`cue/ghost_departure`, `eclipse:ghost_soul_departure`)
- SEAM: `lives/LifecycleEvents` — the exact ban-at-0-hearts branch (where
  `BanService` is invoked for a final death), position lane at the corpse, range 64.
  Bystanders finally SEE a permanent death differ from a normal one.
- TECH: both, LAYER, one-shot (~70 t).
- VISUAL: a pale player-silhouette of mist peels off the corpse, kneels for a beat,
  then is drawn skyward as a stretching soul-ribbon that tears with a faint glitch pop
  — the ferry has taken them.
- BUDGET: SEQUENCE (rare, dramatic). REDUCEDFX: single Quasar soul-wisp rise.

**B5. Revive Thunderbloom** (`cue/revive_complete`, `eclipse:revive_thunderbloom`)
- SEAM: `ritual/ReviveRitual.complete` success branch (beside the global thunder
  sound), position lane at `altarPos`, range 96; a second short cue fires for witness
  circle positions is NOT needed (asset covers the ring).
- TECH: both, LAYER, one-shot (~60 t).
- VISUAL: every ritual beam snaps to white simultaneously, collapses into the sigil,
  and re-erupts as a ground-hugging ring of violet lightning filaments + rising heart
  motes — thunder finally has its picture.
- BUDGET: SEQUENCE. REDUCEDFX: Quasar ring only, no filaments.

### NEWFX-C — world events & contests (world/event server seams)

**C1. Summon Beacon** (`cue/boss_summon_beacon`, `eclipse:boss_summon_beacon`)
- SEAM: `network/boss/BossPayloads.sendIntro` — one ADDITIONAL position-lane send with
  world-wide range (the existing 96-block shockwave stays untouched); `a` = boss kind
  ordinal (palette tint). One choke point covers Herald/Ferryman/Tyrant/Warden.
- TECH: both, LAYER, one-shot (~100 t). Photon column is tall (needs cull box sized
  accordingly); Quasar fallback is a thin light pillar.
- VISUAL: a mile-high hair-thin light column punches the sky at the summon site, holds
  3 s while shedding slow orbit sparks, then frays downward — readable from anywhere on
  the disc, an invitation and a warning.
- BUDGET: SEQUENCE. REDUCEDFX: Quasar pillar only (distant players still get the info).

**C2. Omen Ripple** (`cue/contract_omen`, `eclipse:contract_omen_ripple`)
- SEAM: `contracts/ContractService` — `beginOmen` (b=0, the dread) and the
  close/expiry path in `resolveExpired`/`finishWindow` (b=1, the release). Position
  lane per online player (their own pos — the omen is everywhere, leaking nothing).
- TECH: both, LAYER, one-shot each (~50 t open / ~30 t close).
- VISUAL: open — a crimson ring ripples outward at ankle height through the world like
  a dropped stone in blood, leaving 2 s of drifting red cinders. close — the cinders
  reverse and snuff out with a cold exhale of gray.
- BUDGET: SEQUENCE (twice per window max). REDUCEDFX: skip (shake + music already
  carry it; anonymity design keeps text primacy).

**C3. Gate Fanfare & Finish Ribbon** (`cue/minigame_gate`, `cue/race_finish`;
`eclipse:minigame_gate_fanfare`, `eclipse:race_finish_ribbon`)
- SEAMS (one worker, two files): `minigames/MinigameService.start` (portal spawn spot,
  b=0) and `beginClosing` (b=1, collapse) — position lane range 96;
  `minigames/ElytraRace.finishLap` — position lane at the start/finish ring center,
  range 128, `a` = podium position (1 = gold burst).
- TECH: both, LAYER, one-shots (~60 t fanfare / ~40 t collapse / ~30 t ribbon).
- VISUAL: fanfare — the portal frame ignites edge-running light that leaps off as
  confetti-sparks; collapse — the frame light unwinds and implodes to one point.
  ribbon — the finish ring flashes and sheds a checkered light-ribbon spiral.
- BUDGET: BURST. REDUCEDFX: Quasar-only; ribbon only for position 1.

**C4. Supply Herald** (`cue/supply_incoming`, `eclipse:supply_herald`)
- SEAM: `economy/SupplyBeacon.drop` — send the cue at `surfacePos` ~3 s BEFORE crate +
  marker (the method already computes the pos first; the drop body is deferred by a
  scheduled task, the coordinates stay secret because the cue is dimension-wide but the
  visual is at altitude, findable exactly like the beam). Position lane, dimension range.
- TECH: both, LAYER, one-shot (~60 t, sky-anchored at surface+70).
- VISUAL: a patch of sky shimmers, tears a slit of white, and coughs one falling ember
  streak straight down — 3 s later the crate + beam appear on that line.
- BUDGET: SEQUENCE (rare). REDUCEDFX: skip pre-beat (beam remains the announcement).

**C5. Dungeon Maw Breath** (`cue/dungeon_found`, `eclipse:dungeon_maw_breath` +
windowed loop `eclipse:dungeon_maw_idle`)
- SEAM: NEW tiny server latch `worldgen/structure/DungeonDiscovery.java` (package C
  owns it) — 1 Hz poll (phase-offset, `LandmarkDiscoveryService` pattern) against the
  deterministic `UndergroundSites.sitesFor` anchors of committed stages; first player
  within 24 blocks fires the one-shot cue (persisted per site id in its own SavedData,
  same `Data` pattern). The idle loop is CLIENT-windowed off the same anchor set once
  discovered (unlock key `dungeon:<siteId>` unioned via `UnlockSync`, A6 precedent).
- TECH: one-shot both LAYER; idle loop Photon-first REPLACE, WINDOWED-only
  (materialize ≤ 32 blocks, release > 48, the hysteresis law).
- VISUAL: one-shot — the entrance exhales a slow bank of cold dust + two eye-glint
  sparks deep in the dark. idle — a faint periodic breath of dust and a heartbeat-dim
  glow, telling passers-by "this hole is authored".
- BUDGET: BURST (one-shot) / AMBIENT (loop's Quasar stand-in). REDUCEDFX: loop
  released unconditionally (loop law); one-shot Quasar-only.

### NEWFX-D — client atmosphere & transit (client-only seams, no wire changes)

**D1. First-Contact Seam** (client-latched, `eclipse:border_first_contact`)
- SEAM: `border/client/BorderFxRenderer` client tick — when camera-to-ring distance
  first crosses 48 blocks (well before the 8-block `fxRange` patches), play once per
  save (client-side latch keyed by level id, stored in the existing client config dir).
- TECH: Photon one-shot + Quasar fallback, LAYER, client-spawned directly via
  `PhotonBridge.spawn`/`QuasarSpawner` (no cue — nothing crosses the wire).
- VISUAL: a single floor-to-sky hairline of datamosh static flickers along the ring
  bearing for ~2 s, sheds three drifting glitch shards, and vanishes — "the world has
  edges" said once, quietly.
- BUDGET: BURST. REDUCEDFX: skip (discovery accent only; pushback FX still teach it).

**D2. Drift Cocoon** (windowed off drift phases, `eclipse:breach_drift_cocoon`)
- SEAM: `network/breach/BreachClientFx.handle` — DRIFT_BEGIN opens a client window,
  DRIFT_END/dimension change/logout closes it; while open, an entity-attached Photon
  loop rides the LOCAL player (`PhotonBridge.spawnOnEntity`, AutoRotate.NONE) with a
  Quasar orbit stand-in. Server vanilla particles stay as the photon-less floor.
- TECH: both, REPLACE, WINDOWED loop (transit-scoped, ~10–20 s).
- VISUAL: a loose cocoon of glitch-embers and stretched light-threads wraps the faller,
  stuttering sideways on the drift's frame-skip ticks; threads snap and re-form —
  falling through the world's seams, not through air.
- BUDGET: AMBIENT (stand-in leg). REDUCEDFX: window never opens (loop law).

**D3. Rift Draw-In** (windowed at open rifts, `eclipse:portal_draw_in`)
- SEAM: NEW client controller `veilfx/rift/RiftDrawIn.java` beside `RiftFx` — windows
  on the client's live rift anchors (xbox + backrooms portals both open rifts via the
  frozen `FX_RIFT_OPEN` lane); materialize ≤ 24 blocks, release > 32, one loop per
  anchor, max 2 concurrent (executor-budget courtesy).
- TECH: Photon-first REPLACE with a Quasar in-draw stand-in, WINDOWED loop.
- VISUAL: dust motes and thin light-streamers within ~4 blocks bend and accelerate INTO
  the rift plane, compressing to sparks at the event line — the portal finally *pulls*.
- BUDGET: AMBIENT. REDUCEDFX: released unconditionally; vanilla reverse-portal columns
  (server fallback) remain.

**D4. Diamond Ring** (client-latched, `eclipse:totality_diamond_ring`)
- SEAM: NEW client observer `veilfx/TotalityPeakFx.java` — watches
  `EclipseFxState.eclipseAmount()`; on a rising crest through 0.95 (once per ramp,
  hysteresis re-arm below 0.6 — the music rung's threshold neighborhood) spawns a
  one-shot anchored on the `SunTracker` sun direction ~60 blocks out from camera
  (skip when the sun probe reports occluded).
- TECH: Photon one-shot + Quasar glint fallback, LAYER, client-local.
- VISUAL: at the moment the sun goes fully black, one blinding bead of light flares on
  the rim, streaks a short arc, and dies — the eclipse "diamond ring", 1.5 s, then the
  drone owns the dark.
- BUDGET: SEQUENCE. REDUCEDFX: skip (post grade already tells the story).

**D5. Storm Outrunners** (approach-band accent, `eclipse:storm_outrunners`)
- SEAM: `stormfx/StormInteriorFx` — the existing `approachTargetAt` band (60→20
  blocks, outside only) gains a particle layer driven from the same smoothed value;
  cadence-gated Quasar spawns + one optional Photon ribbon while `approach > 0.5`.
- TECH: both; Quasar cadence bursts (the baseline) + ONE Photon wind-ribbon loop
  windowed on `approach > 0.5` (release < 0.3).
- VISUAL: ragged gray wisps tear off the ground and race TOWARD the wall low over the
  terrain, vanishing into it; closer in, a torn horizontal wind-ribbon whips past at
  head height — the storm inhales you before you touch it.
- BUDGET: **STORM** (its own channel, per-window cap 12). REDUCEDFX: Photon ribbon
  off; Quasar cadence halves automatically (channel law).

---

## 3. Worker packages — NEWFX-A/B/C/D (disjoint trigger-file ownership)

Ownership law: a trigger file below belongs to EXACTLY ONE package; nobody else edits it.
Shared-file law: `network/fx/FxCues.java` is append-only — each package adds ONE
contiguous constant block tagged `// NEWFX-<X>`; each package registers rows in its OWN
new registrar class (never in another package's `*PhotonFxRows`) and ships its own
generator script under `tools/photon/` + assets. No package touches
`PhotonFxRegistry`/`PhotonBridge`/`FxBudget` (frozen core).

| Package | Effects | Trigger files owned (exclusive) | New client classes | Registrar |
|---|---|---|---|---|
| **NEWFX-A** progression & celebration | A1 quest sigil, A2 collection halo, A3 skill spark, A4 landmark flare, A5 catalyst handover | `progression/goals/QuestEngine.java`, `collections/CollectionsService.java`, `skills/SkillService.java`, `progression/LandmarkDiscoveryService.java`, `entity/wizard/WizardOrinEntity.java` | — | `veilfx/ProgressionPhotonFxRows.java` |
| **NEWFX-B** altar, souls & ceremonies | B1 dawn toll, B2 rebirth starfall, B3 offering gutter, B4 soul departure, B5 revive thunderbloom | `drama/DawnCeremony.java`, `rebirth/RebirthService.java`, `ritual/AltarBlockEntity.java`, `ritual/ReviveRitual.java`, `lives/LifecycleEvents.java` | — | `veilfx/CeremonyPhotonFxRows.java` |
| **NEWFX-C** world events & contests | C1 summon beacon, C2 omen ripple, C3 gate fanfare + finish ribbon, C4 supply herald, C5 dungeon maw | `network/boss/BossPayloads.java`, `contracts/ContractService.java`, `minigames/MinigameService.java`, `minigames/ElytraRace.java`, `economy/SupplyBeacon.java`, NEW `worldgen/structure/DungeonDiscovery.java` | — | `veilfx/WorldEventPhotonFxRows.java` |
| **NEWFX-D** client atmosphere & transit | D1 first-contact seam, D2 drift cocoon, D3 rift draw-in, D4 diamond ring, D5 storm outrunners | `border/client/BorderFxRenderer.java`, `network/breach/BreachClientFx.java`, `stormfx/StormInteriorFx.java`, NEW `veilfx/rift/RiftDrawIn.java`, NEW `veilfx/TotalityPeakFx.java` | the two NEW classes | `veilfx/AtmospherePhotonFxRows.java` (D2/D3/D5 loop rows + D1/D4 assets) |

Cross-checks (verified against the current tree):
- No file appears in two packages; A/B/C are server-seam packages (plus their registrar),
  D is client-only (no wire changes at all — D1/D4 are latched locally, D2 windows on an
  existing payload, D3/D5 window on existing client state).
- Existing cue namespace collision: none of the 18 new cue ids exist in `FxCues`
  (checked against all 24 current `CUE_*` constants).
- Executor budget: worst case concurrent loops = D2 (1) + D3 (≤2) + C5 idle (1) + D5
  ribbon (1) = 5 of 24 — safe under the existing altar/breach/end loops.
- Every package: dev-test via `/dev photon test <fxId>` + the seam's existing dev
  triggers (`/dev rebirth`, `/eclipse supply drop`, `/dev minigame`, storm dev commands,
  `FxDevCommands` beams); acceptance = cue fires exactly once per moment, Photon absent
  ⇒ Quasar baseline plays, `reducedFx` ⇒ behavior column above, no WARN spam in the log.

## 4. Explicitly out of scope

Heart loss/gain, sky-launcher trail, map-edge void wall (already covered — §1 rows 5/9/21),
bestiary world-side halo (client celebration exists; would duplicate A2's language),
music-transition visual accents (rejected: audio-driven visuals read as rendering bugs).
No changes to `PhotonFxRegistry`, `PhotonBridge`, `FxBudget`, payload types, or the wire
protocol anywhere in this plan.
