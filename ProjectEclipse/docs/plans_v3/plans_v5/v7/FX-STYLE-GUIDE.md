# FX STYLE GUIDE v2 — "Quiet Eclipse, Loud Moments" (IDEAS-FX-NEW, v7)

Author: IDEAS-FX-NEW (partner to the PLAN-NEWFX planner — that catalog may not exist yet;
this guide is self-contained). Read-only pass over the live tree, no gradle, no git.

**What was studied** (all paths relative to repo root):

- Palette source of truth: `client/handbook/EclipseUiTheme.java` (frozen §2.1 tokens) +
  a color tally across all 65 `assets/eclipse/quasar/emitters/*.json`
  (`#B98CFF` ×23, `#7B4FD0` ×18, `#FFD166` ×11, `#E0AAFF` ×9, `#FFE9A8` ×4 …) and the
  wax-gold rift family in `veilfx/rift/RiftFx.java` (C18).
- The 68 Photon `.fx` under `assets/eclipse/fx/` (58 + 10 `boss/`), format + capability
  split per `docs/plans_v3/plans_v5/photon/FX_FORMAT.md` §7.
- The Quasar emitter families (`altar_*`, `stern_*`, `glut_*`, `riss_*`, `storm_*`,
  `limbo_*`, `glyph_*`), the 10 Veil post pipelines under `assets/eclipse/pinwheel/post/`
  and their upgrade law in `fxteams/GLITCH.md` (12 Hz frameSeed, 420 ms kick, `efxDither`).
- Runtime contracts: `veilfx/FxBudget.java` (channels AMBIENT/BURST/SEQUENCE/STORM, 16
  lights, reducedFx tiers), `veilfx/VeilPostController.java` (≤3 passes,
  GRADE(0) < FEATURE(1) < TRANSITION(2)), `veilfx/PhotonFxRegistry.java` (LAYER/REPLACE
  rows, WINDOWED-only loop law), `network/fx/FxCues.java`,
  `client/hud/CenterStageArbiter.java` (the HUD mutual-exclusion token this guide extends
  to world FX in §6), and the 82 sound aliases in `assets/eclipse/sounds.json`.

**Why v2 exists**: v1 identity grew bottom-up — each fxteam polished its own cluster
(ALTAR, GLITCH, STORM, RIFT…) against local briefs. The result is strong but tribal: gold
means "backrooms" in one file and "reward" in another; glitch snaps live at three different
reseed rates in ideation docs; new workers have no ruling on what a *sacred* impact frame
looks like vs a *storm* one. v2 freezes the shared language so the next FX generation
(the 12 signature compositions in §5) reads as ONE mod.

---

## §0 Design pillars (the identity, stated once)

1. **Quiet Eclipse, Loud Moments.** The world simmers at whisper level (AMBIENT channel,
   ≤0.6 post amounts, brightness — never hue — for routine responses, per ALTAR.md L3).
   Full-palette, full-post spectacle is rationed to cue-fired moments. If everything
   glows, nothing is sacred.
2. **One purple.** `#B98CFF` is THE violet everywhere (UI, wisps, auroras). Family
   variations exist (§1) but the anchor never drifts. Gold is the *counter*-color: it
   marks reward, memory and divinity — it is never ambient decoration.
3. **Corruption is a texture, not a color filter.** Glitch reads through *behavior*
   (quantized snaps, freeze-holds, RGB channel split, datamosh cells) — the GLITCH.md
   vocabulary. Tinting something magenta is not glitch; snapping it in 4 discrete steps is.
4. **Physics sells weight.** Debris bounces (Photon `physics` module), ribbons lag
   (`ara_trail_emitter` physicsSetting), pressure fronts dimple the screen (shockwave v3
   inner dimple). Nothing "floats away" unless it is a soul.
5. **Every moment degrades gracefully.** Photon → Quasar fallback → nothing, never below
   baseline (PhotonFxRegistry law). Every composition in §5 ships its reducedFx tier-1
   and tier-0 forms up front, not as an afterthought.

---

## §1 Palette token system v2

Tokens are named so recipes in §5 and future emitters can reference them symbolically.
Hex values are anchored to what already ships (EclipseUiTheme + emitter tally); NEW
tokens are marked. HDR column = suggested Photon material `hdr` RGB boost for bloom
(Photon materials only; Quasar has no bloom — use `additive: true` + dynamic light instead).

### 1.1 SACRED — violet/gold (altar, blessings, rewards, souls)

| Token | Hex | Exists as | HDR | Role |
|---|---|---|---|---|
| `SAC_HOT` | `#F6EFFF` | `sanctum_lightfall` t=0 | 1.6 | white-violet cores, first 2–4t of any impact |
| `SAC_VIOLET` | `#B98CFF` | `EclipseUiTheme.ACCENT`, ×23 emitters | 0.8 | THE purple; mid-life of every sacred particle |
| `SAC_DEEP` | `#7B4FD0` | `EclipseUiTheme.ACCENT_DEEP`, ×18 | 0.3 | tails, pressed states, outer glow |
| `SAC_GOLD` | `#FFD166` | ×11 emitters (awards, wax-gold rift) | 1.4 | divinity/reward accents — impact frames, glints |
| `SAC_GOLD_PALE` | `#FFE9A8` | ×4 emitters | 0.9 | gold afterglow, chime swells |
| `SAC_VOID` | `#2E2347` | `HAIRLINE`, ×8 emitters | 0 | fade-out target (never fade to black — fade to aubergine) |

Rule: sacred gradients run HOT → VIOLET → DEEP → VOID over lifetime (the
`sanctum_lightfall` curve). Gold enters only at impact/settle, ≤35 % of particles.

### 1.2 CORRUPTION — green-violet (rot, decay, the *wrong* kind of growth)

| Token | Hex | Exists as | HDR | Role |
|---|---|---|---|---|
| `COR_BILE` | `#9BD8B4` | `glyph_follow`/`glide_trail` greens | 0.6 | sick highlight — a green that is *almost* the UI `GOOD` green but desaturated |
| `COR_MOSS` | `#6FA98C` | same family | 0.2 | body color of rot particles |
| `COR_VIOLET` | `#9D4EDD` | ×4 emitters | 0.5 | the violet half — corruption is eclipse-stuff gone sour |
| `COR_INK` | `#3C096C` | ×2 emitters | 0 | drip/pool color, fade target |
| `COR_PALE` (NEW) | `#D9FFE8` | `stern` family pale | 0.9 | brief spore-pop cores only |

Rule: green and violet must *interleave* (alternating particles / gradient stripes),
never blend into teal-brown mud. Corruption never receives gold (see §6.4).

### 1.3 GLITCH — magenta/cyan RGB-split (rifts, husks, border, datamosh)

| Token | Hex | Exists as | HDR | Role |
|---|---|---|---|---|
| `GLI_MAGENTA` (NEW) | `#FF4FD8` | implicit in RGB-split shaders | 1.2 | + channel fringe, shard edges |
| `GLI_CYAN` (NEW) | `#4FE8FF` | implicit in RGB-split shaders | 1.2 | − channel fringe (always paired with magenta, offset opposite) |
| `GLI_WHITE` | `#FFFFFF` | ×23 emitters | 2.0 | 1–2t invert-pop / flash frames |
| `GLI_VIOLET` | `#B98CFF` | shared with SACRED | 0.6 | the "bleed" — ties glitch back to the eclipse (rift_glitch violet bleed) |
| `GLI_DEAD` (NEW) | `#241C38` | ×3 emitters | 0 | dropped-signal cells, hold-frame darkening |

Rule: magenta and cyan appear ONLY as split pairs displaced along one axis (the
`border_glitch`/`rift_glitch` `efxChroma` read) or on shard edges — never as body colors.
Particle-side glitch uses `glitch_shard.png` / `static_4x4.png` / `square_4x4.png`
(`assets/eclipse/textures/particle/`), hard quads, no soft wisps.

### 1.4 ERA — warm CRT (Xbox tutorial dimensions, memory flashes)

| Token | Hex | Exists as | HDR | Role |
|---|---|---|---|---|
| `ERA_CREAM` | `#FFF3C4` | ×2 emitters, xbox_era highlights | 0.7 | flash frames, highlight zone |
| `ERA_AMBER` | `#FFB25E` | ×3 emitters | 0.5 | particle body — warm mids (the xbox_era LUT mids made solid) |
| `ERA_EMBER` | `#FF7B3C` | ×2 emitters (`glut` family) | 0.8 | hot cores, phosphor trails |
| `ERA_SHADOW` (NEW) | `#3A3A55` | ×2 emitters | 0 | cool-shadow fade target (the xbox_era LUT's cool shadows) |

Rule: era FX are *soft* — alpha-blend not additive where possible, dust-like sizes,
zero hard edges. The `xbox_era` post grade (720p soft resolve + saturation bloom) does
the heavy lifting; particles only garnish.

### 1.5 STORM — slate/arc-blue (support palette, already shipped)

`STM_SLATE #3A3A55`, `STM_ARC #BFD9FF`, `STM_DEEP #5A8DEE` (the `stern`/`storm_arc`
blues). Storm is a *support* context: its compositions may host SACRED or GLITCH accents
but its own body stays desaturated — storms are weather, not magic.

---

## §2 Motion grammar

Each context owns *verbs*. A particle's palette can be ambiguous at distance; its motion
must not be.

| Context | Verbs | Concrete parameters |
|---|---|---|
| SACRED | **slow orbits + verticals** | orbital Y velocity 0.5–0.9 rad/s (template_loop's 0.8), vertical drift ±0.02–0.06 blk/t, arc write-ins (ALTAR.md L1 pen-tip), `sin(π·t)` swells. Easing: smoothstep everywhere, nothing linear. Nothing sacred moves fast except the first 2–4t of an impact. |
| GLITCH | **snaps + holds** | NO easing — values teleport between quantized states (0, ⅓, ⅔, 1 — the border_glitch datamosh quantization) on the shared **12 Hz reseed clock**, hold 2–8t, snap in 1t. Freeze-holds (motion = 0) are a first-class verb: stillness before violence. Rotation snaps in 90°/45° increments only. |
| STORM | **shear + spirals** | horizontal shear fronts (dust walls translating 0.3–0.6 blk/t with ±15° skew), logarithmic spiral indraw/outflow around the event axis, pressure ring + dimple (shockwave v3 vocabulary). Vertical motion only as *consequence* (updraft after the front passes). |
| CORRUPTION | **creep + drip** | growth-front crawl ≤0.1 blk/t, gravity drips with `removedWhenCollided:0` + collision sub-emitter pools, pulsing (breathing scale ±8 % at 0.25 Hz). Never orbits — corruption is too heavy to fly. |
| ERA | **drift + dissolve** | near-still dust (speed ≤0.05 blk/t), long cross-fades (30t grade ease is the master clock — `XboxEraFx`), soft focus pulls. No impacts harder than a flash frame. |

Shared clocks (do not invent new ones):

- **12 Hz frameSeed** — all glitch reseeds (border_glitch/rift_glitch established).
- **420 ms kick decay** (quadratic, wall-clock) — any "shove/impact echo" screen feedback.
- **30-tick grade ease** — any post grade in/out (xbox_era binder established).
- **34 s / 45 s slow-breath cycles** — ambient rearrangement beats (ALTAR.md L2/L5),
  chosen co-prime so beats rarely stack.

---

## §3 Timing standards

Units: ticks (20t = 1s). The three-beat spine every one-shot composition must scan to:

| Beat | Budget | What happens | Sound slot |
|---|---|---|---|
| **ANTICIPATION** | **8–12t** | telegraph: indraw, glyph write, seam creep, freeze-hold (glitch), pressure ring (storm). Light + audio lead the particles — the player's eye must arrive *before* the impact. | loop/riser alias, quiet |
| **IMPACT** | **2–4t** | the money frames: HOT/flash color, biggest size, post spike, dynamic light peak (FxBudget.tryLight for the impact window only). One impact per composition — doubles only via the shockwave v3 strength-gated echo (−0.16 progress offset). | ONE sting alias |
| **SETTLE** | **20–40t** | debris physics, orbit decay, grade wash-out, drips. Fade to context VOID token, never to transparent-black. Lights released by mid-settle. | tail/ambient alias |

Refinements:

- Glitch compositions may *invert* the spine: HOLD (8–12t of unnatural stillness) is
  their anticipation; the impact is the snap OUT of the hold.
- Loops (WINDOWED-only law) have no spine; they have a **materialize ramp ≤20t** and a
  **release fade ≤20t** driven by their hysteresis window controller (the
  `SanctumLightfall` pattern).
- Sub-second polish: impact flash frames are 2t at tier 2, 1t at tier 1, 0 at tier 0.
- Two impacts from *different* compositions may never land within 4t of each other —
  the de-confliction rule in §6.3.

---

## §4 Layer stack conventions (which engine plays which layer)

Frozen capability split (FX_FORMAT.md §7 + FxBudget/VeilPostController contracts):

| Layer job | Engine | Why |
|---|---|---|
| Ambient world beds, anything light-emitting, PR-diffable FX | **Quasar** (`quasar/emitters/*.json`) | MoLang interpolants, true dynamic lights, hand-editable |
| Bloom/HDR cores, mesh/model debris, physics bounces, ribbons, raycast beams, flipbooks | **Photon** (`fx/*.fx` via `PhotonBridge`) | per-material `hdr`, `mesh` shape, `ara_trail_emitter`, `beam_emitter` raycast, collision sub-emitters |
| Fullscreen reads: grades, lenses, pressure, tears | **Veil post** (`pinwheel/post/*.json`) | ≤3 concurrent, GRADE < FEATURE < TRANSITION |
| Weight, presence | **Dynamic light** (`FxBudget.tryLight`, ≤16) | impacts feel physical |
| Everything above the neck | **Sound** (`sounds.json` aliases) | 82 shipped aliases; §5 recipes reference them only |

Naming conventions for the new generation (matches shipped patterns):

- Photon asset: `assets/eclipse/fx/sig/<comp_id>.fx` (+ committed `.fxproj`) —
  new `sig/` folder mirrors the shipped `boss/` folder precedent.
- Quasar layers: `assets/eclipse/quasar/emitters/sig_<comp_id>_<layer>.json`.
- Cue: `FxCues.CUE_SIG_<COMP_ID>` + row in a new `SignaturePhotonFxRows` registrar
  (copy `PhotonFxRows`), Photon leg + Quasar fallback per row, `Mode.REPLACE` for
  one-shots (the Photon file IS the choreography; Quasar leg is the fallback sketch).
- Post passes: reuse the shipped 10 wherever possible (they are uniform-fed and generic);
  a composition may propose at most ONE new pass and must fit the single-stage
  `veil:blit` family invariant.

---

## §5 The 12 signature compositions

Reusable multi-layer recipes. Table columns: **L#** (layer), **Engine** element,
**Recipe** (shape/modules/palette tokens), **Timing** (start→end, ticks relative to cue).
Every composition lists: stage class (§6.1), FxBudget spend, sounds (existing aliases
only), reduced forms, and reuse pointers to shipped assets to clone from.

Shared budget note: Photon spawns charge `PhotonBridge.MAX_LIVE_EXECUTORS`, not
FxBudget; the Quasar legs charge the listed channel. SEQUENCE is reserved for scripted
sequences (cutscenes/ceremonies) — cue-fired compositions ride BURST/AMBIENT/STORM.

---

### C1 · SANCTUM BLOOM — sacred consecration (blessing, shrine activation, level-up at a holy site)

Class **S** (spectacle) · palette SACRED · spine 10 / 3 / 36 · spend: BURST ×2 + AMBIENT ×1 + 1 light

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 ground glyph | Quasar | horizontal billboard ring patch (clone `glyph_greet`), write-in as arc sweep 0→360° (ALTAR.md L1 pen-tip verb), `SAC_VIOLET` → `SAC_DEEP`, alpha 0→0.7 | 0→10 |
| L2 indraw motes | Quasar | sphere-shell radius 3.5, radial −0.25 blk/t inward, 12 motes, `purple_wisp.png`, `SAC_DEEP` | 2→10 |
| L3 light pillar | Photon `beam_emitter` | vertical, end [0,14,0], width curve 0.15→0.9→0.35, `beam_core.png`, `SAC_HOT` core hdr 1.6 + `SAC_GOLD` sheath hdr 1.4, raycast NONE | 10→46 (flash peak 10→13) |
| L4 bloom burst | Photon `particle_emitter` | burst 26 @ t=10, sphere shell 0.4, `SAC_HOT`→`SAC_GOLD_PALE` gradient, sizeOverLifetime pop-in curve, lights module 15/15 | 10→24 |
| L5 orbit motes | Quasar | cylinder shell r=1.2, orbital 0.7 rad/s + rise 0.04 blk/t (template_loop verbs), `SAC_VIOLET`, fade to `SAC_VOID` | 13→46 |
| L6 dynamic light | `FxBudget.tryLight` | violet point light, intensity peak at impact, release by t=30 | 10→30 |
| L7 chime | sound | `ambient.sanctum_hum` swell from t=0; **`ui.chime`** at t=10; `skill.levelup` variant when the trigger is a level | — |

Reduced: tier 1 drops L2+L5 count by half, flash 1t; tier 0 = L1 glyph + `ui.chime` only.
Clone from: `altar_pillar.json`, `altar_orbit_burst.json`, `sanctum_lightfall.json`, `altar_levelup.fx`.

### C2 · GOLD RUSH — reward burst (loot open, award, contract payout)

Class **A** (accent) · SACRED (gold-dominant — the one licensed gold lead) · spine 8 / 2 / 28 · spend: BURST ×1

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 glint gather | Quasar | 8 sparks arc inward along golden-angle spiral (reuse `WorldPhotonFxRows` END_ROD spiral math), `SAC_GOLD_PALE` | 0→8 |
| L2 flash frame | Photon | 1 quad, 2t, `GLI_WHITE`→`SAC_GOLD`, hdr 2.0, size 1.4 | 8→10 |
| L3 star shards | Photon `particle_emitter` | burst 30, physics ON (gravity 0.35, bounce 0.6/0.4 — template_burst numbers), `renderMode: Model` mini-shards OR `glitch_shard.png` recolored, `SAC_GOLD`→`SAC_GOLD_PALE`→`SAC_VOID` | 8→36 |
| L4 glint rain | Photon trails module | `trails` ratio 0.4 on L3, short ribbons, inheritParticleColor | 8→36 |
| L5 sting | sound | **`award.sting`** at t=8; `ui.unlock_sting` for unlock-flavored triggers | — |

Reduced: tier 1 shards ×0.5 no trails; tier 0 = flash frame + sting.
Clone from: `award_star_glint.fx`, `award_star_shower.fx`, `roulette_flare.json`.

### C3 · SOUL THREAD — transfer (soul theft, offering travel, life-force hand-off A→B)

Class **A** · SACRED (violet lead, gold only at arrival) · spine 12 / 3 / 24 · spend: BURST ×2

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 donor rise | Photon | 6 wisps rise from donor, `wisp_white.png`, `SAC_HOT`, slight orbit (sacred verticals) | 0→12 |
| L2 thread | Photon `ara_trail_emitter` | ONE ribbon, physics lag (inertia 0.4, damping 0.75 — it *sags* mid-flight), custom flat section, `SAC_HOT` core / `SAC_VIOLET` edge, travels donor→receiver over 20t on an `empty` parent animated along a raised arc | 12→32 |
| L3 arrival pop | Photon | burst 12 @ arrival, `SAC_GOLD_PALE` blink + soft ring (`ring_soft.png`) | 32→35 |
| L4 absorb orbit | Quasar | 8 motes spiral INTO the receiver (radial −0.2), `SAC_VIOLET`→`SAC_VOID` | 35→56 |
| L5 audio | sound | `ritual.extract` at t=0; **`theft.steal`** (hostile) or **`offering.accept`** (benign) at t=32 | — |

Entity-anchored: rides `S2CFxEntityEventPayload` with a custom `PhotonLeg` (degrade to
position anchor when the entity is untracked — registry law).
Reduced: tier 1 thread without physics lag; tier 0 = L1 + arrival sound.
Clone from: `theft_soul_launch/rise/arrive.fx`, `offering_swallow_soul.fx`, `offering_swallow.json`.

### C4 · WHISPER VEIL — concealment shroud (stealth buff, gazer hush, secret proximity)

Class **B** (bed, windowed loop) · SACRED-dark (VOID-heavy) · ramp ≤20t / release ≤20t · spend: AMBIENT ×1/window

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 curtain | Photon loop | cylinder shell r=0.9 thin, smoke material alpha-blend (template_loop base), `SAC_VOID` body + `SAC_DEEP` rim at 20 % alpha, downward drift −0.03 (an *inverted* sacred vertical: veils fall) | loop, prewarm 20 |
| L2 mote pulse | Quasar | 4 near-still motes, breathing alpha 0.25 Hz, `SAC_DEEP` | loop |
| L3 hush | sound | **`ambient.gazer_whisper`** quiet positional loop, volume = veil strength | loop |
| L4 release | Photon | on window close: single 20t dissolve burst upward (the veil lifts), `SAC_DEEP`→transparent | close→+20 |

WINDOWED-only row (loop=true); hysteresis controller owns ensureLoop/releaseLoop.
Reduced: tier 1 halves rates (automatic); tier 0: AMBIENT channel is off → sound-only veil.
Clone from: `template_loop.fx`, `wanderer_static_shroud.fx`, `other_dread_aura.fx`.

### C5 · GLITCH RUPTURE — corrupted break (husk death, blink-tear, forced desync)

Class **S** · GLITCH · inverted spine: HOLD 10 / SNAP 2+2 / drip 24 · spend: BURST ×1

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 freeze-hold | render/entity | target's animation freezes (MOB-GLITCH datamosh vocabulary); 2 dark cells (`GLI_DEAD` quads, Photon, rotation snapped 90°) flicker on the silhouette at 12 Hz | 0→10 |
| L2 RGB split snap | Veil post | feed the shipped `rift_glitch` ambient lane (`TransitionFx.setRiftAmbient` style feed, ≤0.6 cap): 2t spike — magenta/cyan fringes rip apart along one axis | 10→12 |
| L3 voxel scatter | Photon | `mesh` shape emission from the target's baked model (Vertex mode), `renderMode: Model`, block-atlas UV — the body *disassembles into its own voxels*; velocities quantized to 4 magnitudes, NO easing | 10→13 |
| L4 snap-back | Photon | scatter reverses (negative radial burst re-converging) OR collapses to floor with physics — pick per trigger: blink = reassemble, death = collapse | 13→15 |
| L5 residue drip | Photon | sparse `static_4x4.png` flecks drip off the seam, gravity, `COR_INK`-dark, 12 Hz gated | 15→39 |
| L6 audio | sound | **`ui.error_glitch`** at t=10 + `event.rift_thud` at t=13; hold is SILENT (silence is the anticipation) | — |

Reduced: tier 1 drops L2 post spike (source-fed 0, GLITCH.md law) and halves scatter; tier 0 = L1 flicker + sound.
Clone from: `glitch_pop.fx`, `riss_glitch_pop.fx`, `riss_blink_tear.json`, `border_shard.json`.

### C6 · VOID TEAR — reality tear opening (minor rift spawn, void event punctuation)

Class **S** · GLITCH body + SACRED bleed · spine 12 / 3 / 40 · spend: BURST ×1 + AMBIENT ×1

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 seam creep | Quasar | thin vertical scar of near-still shards (clone `riss_seam_scar`), `GLI_DEAD` + `GLI_VIOLET` flecks, grows bottom-up | 0→12 |
| L2 suction | Quasar | 10 motes drift INTO the seam line (radial −0.15), sizes shrink approaching it | 4→12 |
| L3 tear snap | Photon `beam_emitter` | vertical slit beam snaps open in 3t (width 0→0.5 in ONE step at t=12 then settle — glitch snap, not sacred ease), `GLI_WHITE` core hdr 2.0, `GLI_MAGENTA`/`GLI_CYAN` edge pair offset ±0.06 | 12→52 |
| L4 shard lick | Photon `ara_trail_emitter` ×2 | two short ribbons flick outward from the tear ends and *hold* mid-air (segment time long, no physics) | 15→52 |
| L5 post presence | Veil post | shipped `rift_glitch` ambient feed at ≤0.4 while open (voxel-sort streaks orient away from `RiftCenter` for free) | 12→close |
| L6 audio | sound | `ambient.border_static` sliver during creep; **`event.rift_open`** at t=12; `event.rift_drone` bed while open; `event.rift_resolve` on close | — |

Reduced: tier 1 → no L5 (source 0), ribbons 1; tier 0 = beam + open/close sounds.
Clone from: `wand_idle_riss.fx`, `expansion_rift_glow.fx`, `riss_wave_front.json`, `rift_spark.json`.

### C7 · VERDANT ROT — corruption spread (blight pocket forming, sour growth, curse zone)

Class **A** → **B** (one-shot bloom, then optional windowed bed) · CORRUPTION · spine 12 / 4 / 40 · spend: BURST ×1 then AMBIENT

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 tendril creep | Quasar | ground-hugging front crawling outward ≤0.1 blk/t (clone `growth_dust_wall`, re-palette), alternating `COR_MOSS` / `COR_VIOLET` particles (§1.2 interleave rule) | 0→12 |
| L2 spore pulse | Photon | soft 4t bloom: 14 spore motes pop `COR_PALE` cores → `COR_BILE`, gentle — corruption has no hard impact frame | 12→16 |
| L3 drip pools | Photon | 8 drips, gravity, `removedWhenCollided:0`, **Collision sub-emitter** spawns a flat pool splat fx (`COR_INK`), the shipped `structure_slam_mushroom` sub-emitter pattern | 14→56 |
| L4 breath bed | Quasar loop (optional window) | patch of near-still motes breathing ±8 % scale at 0.25 Hz, `COR_MOSS`→`COR_INK` | windowed |
| L5 audio | sound | `event.emerge` (pitched down at call site) at t=12; `ambient.limbo_loop` sliver as bed | — |

Reduced: tier 1 no L3 sub-emitters; tier 0 = L1 creep only.
Clone from: `growth_front_ribbon.fx`, `growth_dust_wall.json`, `breach_ash_geyser.fx` (drip/geyser physics).

### C8 · ERA FLASH — warm CRT memory flash (nostalgia sting, tutorial echo, xbox relic touched)

Class **S** (dimension-scoped, so rarely contested) · ERA · spine 8 / 2 / 30 · spend: BURST ×1

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 bloom-in | Veil post | `xbox_era` Amount eased 0→0.65 over 8t (faster than its 30t master ease — flash context; binder already supports fed amounts) | 0→8 |
| L2 flash frame | Photon | 2t fullbright quad `ERA_CREAM`, soft edge (`ring_soft.png` scaled up), alpha-blend NOT additive (era softness rule) | 8→10 |
| L3 dust settle | Photon | 16 near-still dust motes drift down 0.03 blk/t, `ERA_AMBER`→`ERA_SHADOW`, long lifetimes | 10→40 |
| L4 phosphor trail | Photon trails | ratio 0.2 short warm trails on L3 (`ERA_EMBER`), widthOverTrail decaying | 10→40 |
| L5 grade decay | Veil post | Amount 0.65→0 over 30t (the master grade ease) | 10→40 |
| L6 audio | sound | `ui.page_turn` at t=0 (the "memory opens" foley), **`ui.chime`** at t=8; `ambient.xbox_cave` swell as tail | — |

Reduced: tier 1 Amount ×0.5, no trails; tier 0 = sound only (grade already 0 under reducedFx per xbox_era law).
Clone from: `portal_iris_open_xbox.fx`, `portal_loop_xbox.fx`, `xbox_era.fsh` LUT zones for exact warm values.

### C9 · STORM HERALD — storm arrival (dome ignition, weather escalation, boss-weather tie-in)

Class **S** · STORM (+`STM_ARC` accents) · spine 12 / 4 / 40 · spend: STORM ×3

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 pressure ring | Veil post | shipped `shockwave` fed strength 0.25 (single-pulse by construction — below the 0.72 double-pulse gate), slow progress: the sky *pushes* | 0→12 |
| L2 dust rush | Quasar | horizontal shear wall sweeping the player position, ±15° skew, `STM_SLATE`, speed 0.45 blk/t (clone `growth_dust_wall` at storm palette) | 4→16 |
| L3 light dim | Veil post | `world_grade` exposure −18 % over 4t, hold, release over settle (GRADE priority — survives eviction) | 12→52 |
| L4 spiral inflow | Quasar | 12 motes on logarithmic spiral into the storm axis, `STM_ARC`, STORM channel | 16→52 |
| L5 arc flicker | Quasar | 2–3 one-frame arc sprites (`storm_arc.json` as-is) at random offsets | 16→52 |
| L6 audio | sound | `event.storm_pulse` at t=0; **`event.storm_burst`** at t=12; `event.storm_loop` / `ambient.storm_dome_drone` bed after | — |

Reduced: tier 1 halves STORM rates (automatic), dim −10 %; tier 0 = L3 dim + sounds.
Clone from: `storm_crown_halo.fx`, `storm_rain_sheet.json`, `storm_godfinger.json`, `StormInteriorFx` binder.

### C10 · DEEP RUMBLE — subterranean dread (pre-event warning, something-below, distant collapse)

Class **B** (bed — deliberately sub-visual) · palette-neutral (dust) · ramp 20 / bed / release 20 · spend: AMBIENT ×1/window

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 ceiling dust | Photon loop | sparse dust trickle from overhead surfaces, physics gravity, `ERA_SHADOW`-grey, collision removes | windowed |
| L2 pebble hop | Photon | every ~30t a 3-particle micro-burst at ground level "hops" 0.1 blk (physics bounce) — the floor is shivering | windowed |
| L3 pressure breath | Veil post | `shockwave` fed strength 0.1, progress oscillating slowly — only the inner dimple term reads: a sub-visible 1 % breathing of the frame | windowed |
| L4 audio | sound | **`event.end_shatter_rumble`** low loop (the composition IS this sound; visuals garnish it); `event.rift_thud` singles on L2 hops | — |

The composition intentionally fails the "did you see it?" test — players should *feel* it.
Reduced: tier 1 = L1+L4; tier 0 = L4 only (still fully functional as a warning).
Clone from: `slam_dust_puff.fx`, `fog_debris_puff.fx` (boss/), `crater_updraft.json`.

### C11 · CROWN VERDICT — boss defeat coda (kill confirm, dome release, world exhale)

Class **S-MAX** (outranks everything, §6.1) · SACRED gold-over-violet · spine 12 / 3 / 40+ · spend: SEQUENCE (scripted context)

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 world indraw | Photon | radial −0.4 blk/t motes from 6-block shell into the corpse (clone `tyrant_death_implosion` indraw), `SAC_DEEP` | 0→12 |
| L2 verdict flash | Photon + post | 3t `GLI_WHITE`→`SAC_GOLD` white-out quad + shipped `shockwave` at strength 1.0 (earns the v3 double-pulse) | 12→15 |
| L3 gold ash rain | Photon | 40 slow-falling ash flakes, `SAC_GOLD_PALE`→`SAC_VOID`, physics drift, long 40t+ tail — the world is gilded for a breath | 15→60 |
| L4 crown halo | Quasar | one soft expanding ring overhead (`ring_soft.png`), `SAC_GOLD` fading | 15→45 |
| L5 grade exhale | Veil post | `world_grade` brief warm lift then relax (the inverse of Storm Herald's dim) | 15→55 |
| L6 audio | sound | boss-specific telegraph silence 0→12; **`event.boss_down`** at t=12; `award.sting` at t=20 (staggered — §6.5 one-sting rule) | — |

Reduced: tier 1 ash ×0.5 single-pulse; tier 0 = flash + `event.boss_down`.
Clone from: `boss/tyrant_death_implosion.fx`, `boss/roar_shockwave.fx`, `heart_burst.json`.

### C12 · PALE CROSSING — limbo transit (death slip, ghost-state enter/exit)

Class **S** (player-exclusive moment) · SACRED desaturated (ghost) · spine 10 / 3 / 30 · spend: BURST ×1

| L# | Engine | Recipe | Timing |
|---|---|---|---|
| L1 desat sweep | Veil post | `ghost_grade` amount 0→1 sweeping over 10t (grade family, 30t-ease law bent for the crossing — document at binder) | 0→10 |
| L2 godray columns | Quasar | 3 vertical light shafts materialize around the player (clone `limbo_godray`), `SAC_HOT` at 30 % alpha | 4→40 |
| L3 soul ribbon | Photon `ara_trail_emitter` | one ribbon rises from the player's chest, physics sway, `SAC_HOT` core / pale `SAC_VIOLET` edge | 10→34 |
| L4 crossing blink | Photon | 3t soft flash + 8 upward wisps (`ghost_wisp.fx` verbs) | 10→13 |
| L5 mote drift | Quasar | limbo motes bed while in-state (`limbo_motes_near` as-is, windowed) | windowed |
| L6 audio | sound | **`ui.ghost_burst`** at t=10; `ambient.limbo_loop` bed; `event.submerge` reversed-feel on exit (`event.emerge`) | — |

Reduced: tier 1 no L2; tier 0 = L1 grade + sounds (grade is the crossing's core read).
Clone from: `ghost_wisp.fx`, `end_void_wisps.fx`, `limbo_godray.json`, `ghost_grade` pipeline.

---

## §6 COMBO RULES — when compositions collide

### 6.1 The WorldStage token (CenterStage's outdoor sibling)

`CenterStageArbiter` already serializes HUD hero moments (tryClaim/release + lease
failsafe, upper-center band). World FX need the same discipline but CANNOT queue the
same way — a boss dies *now*, a storm arrives *now*. So the world token **demotes
instead of deferring**:

- Proposed `veilfx/WorldStageArbiter` (copy the CenterStage shape: client-tick statics,
  `tryClaim(id, ticks)`, explicit `release`, lease failsafe, clear on level unload).
- Scope: one token per **24-block bubble** around the camera (world FX outside the
  bubble never contest — distance already de-emphasizes them).
- Classes per composition: **S-MAX** (C11 Crown Verdict), **S** (C1, C5, C6, C8, C9,
  C12), **A** (C2, C3, C7), **B** (C4, C10). Only S/S-MAX claim the token. A-class
  plays freely (they are accents by construction). B-class beds never claim.
- Collision rule: an S composition that fails `tryClaim` plays its **demoted form** —
  defined per §5 as the tier-1 reduced form with the post layer dropped and no light
  claim. It does NOT wait: world moments are simultaneous in fiction, so both play, but
  only one owns the *frame* (post passes, dynamic-light peak, sting slot).
- S-MAX preempts: Crown Verdict's claim forcibly releases a held S token (the only
  legal preemption — a boss death outranks weather).

### 6.2 Post-pass arithmetic (hard ceiling: 3)

`VeilPostController` evicts lowest priority first (GRADE < FEATURE < TRANSITION) and
runs grades first. Composition post spends: C1/C2/C3/C4/C7/C10 = 0–ambient only;
C5/C6 = rift_glitch feed; C8 = xbox_era; C9 = shockwave + world_grade; C11 = shockwave +
world_grade; C12 = ghost_grade. Rules:

1. A demoted S composition feeds its post lane 0 (source-side, the GLITCH.md reducedFx
   pattern — never fight the controller with duelling uniform writes).
2. Two claimants of the SAME pipeline merge at the feeder: strongest value wins per
   frame (shockwave already models "one lead ring + strength-gated echo"; the merged
   feed inherits that for free).
3. Never combine two TRANSITION-class passes by design: no §5 composition uses more
   than one, and simultaneous S compositions are already serialized by 6.1.

### 6.3 Timing interleave

- **Impact de-confliction**: two impacts within 4t → the lower-priority composition
  *extends its anticipation* to land its impact ≥6t after the winner's. Exception:
  glitch snaps (C5, C6) never extend — a delayed snap reads as lag, not drama — so vs a
  glitch composition the OTHER party shifts, whatever the priority.
- Anticipations may overlap freely (layered telegraphs read as escalation, which is good).
- Settles always overlap; that is the point of 20–40t tails — the world breathes out
  together.

### 6.4 Palette dominance

- The token holder owns the frame's hue. Non-holders clamp accent colors to ≤20 % of
  their particle count and drop HDR boosts to ≤0.5 (bloom is the holder's privilege).
- Forbidden simultaneous pairs (mud risk): `SAC_GOLD` + `COR_*` (poison-treasure read);
  `GLI_MAGENTA/CYAN` outside an actual glitch beat; `ERA_*` outside era dimensions or
  C8. When C7 (rot) and C2 (gold rush) trigger together, gold wins and rot's spore pulse
  recolors to pure `COR_VIOLET` for that instance (violet is the shared bridge tone —
  every context contains it, which is what keeps combos coherent).

### 6.5 Sound stacking

- **One sting per 40t** across all compositions (sting = the bolded alias in each §5
  recipe). Later stings within the window drop to their tail alias or stagger (C11
  already models this: `event.boss_down` t=12, `award.sting` t=20).
- Beds (`ambient.*`, `event.*_loop`) duck to −6 dB while any sting plays and while a
  spine is inside its impact beat.
- `ui.*` aliases stay non-positional (they are the player's private channel); world
  compositions may borrow them (C5's `ui.error_glitch`) only for player-caused events.

### 6.6 Budget arithmetic

Worst legal frame: one S-MAX + one demoted S + two A + beds =
BURST ≤ 15 ✓ (C11 rides SEQUENCE; C2+C3 = 3 BURST; demoted S ≤ 2), AMBIENT ≤ 12 ✓,
lights ≤ 3 claimed of 16 ✓, live particles: sum of §5 max_particles across that stack
≈ 700 < 1500 ✓. New compositions must show this sum in review before merging.

### 6.7 reducedFx ladder (restated as a combo rule)

Tier 1 halves every channel automatically (FxBudget) — recipes above list what *else*
they shed. Tier 0 kills AMBIENT: every B-class composition must remain *functionally*
legible at tier 0 through sound alone (C10 is the reference: the rumble IS the warning).

---

## §7 Authoring checklist (per new composition)

1. Name it (two words, noun-verb or adjective-noun, matches §5 register).
2. Fill the §5 table shape: class, palette context, spine, per-layer engine + timing.
3. Verify palette: only §1 tokens; gradient runs to the context VOID token.
4. Verify motion: only the context's §2 verbs; glitch = zero easing.
5. Spine within §3 budgets (8–12 / 2–4 / 20–40).
6. Budget sum (§6.6) + reduced tier-1/tier-0 forms written BEFORE implementation.
7. Wire: `FxCues.CUE_SIG_*` + `SignaturePhotonFxRows` row + Quasar fallback emitter;
   loops via a hysteresis window controller, never payload-fired.
8. Sounds: existing aliases only (82 in `sounds.json`); one sting, beds duck.
9. Commit `.fxproj` beside every `.fx` (binary-diff law, FX_FORMAT.md).
