# ALTAR-MODEL wiring notes — F-076 GeckoLib-Altar + F-075 Stufen-Aura

Zero foreign-file edits: no `EclipseMod` / `FxCues` / `EclipsePayloads` / lang /
`sounds.json` / `AltarScreen` / `AltarPayloads` changes. Every class self-registers
(`@EventBusSubscriber` or static init); the four aura cues are built with the public
`FxCues.cue("altar_aura_…")` helper inside `veilfx/AltarAuraFxRows.java`. No new lang
keys and no new sounds were needed (the altar block name exists; all one-shots ride
existing ceremony audio) — `langdrop/altar_model.json` is the empty en/de shape (the
P2-W9 precedent) and there is no sounds drop.

## What landed

| File | What |
|---|---|
| `assets/eclipse/geo/block/altar.geo.json` C | The monument: 4-step deepslate plinth (26→22 px wide) + 4 corner horns + 4 floating rune plates, floating eclipse core (8³ px, 45°-rotated) + inner glow shell, three counter-rotating rune rings (r≈11/15/8 px at y 19/25/30) + 4 orbiting debris chips. 256×128 atlas. Validated (`scripts/geckolib_gen/validate_geo.py`: PASS) |
| `assets/eclipse/animations/block/altar.animation.json` C | `idle` (12 s loop: core bob/spin, rings counter-rotate, runes breathe, debris drift), `heartbeat` (1.2 s pulse), `gift` (3.5 s: rings open + core lifts + light bursts), `erupt` (6 s: rings race, core climbs ~1 block, whole monument quakes), `stage_up` (2.5 s ring-pop fanfare). Validated: PASS |
| `tools/altar/gen_altar_texture.py` C | Deterministic PIL painter (uses `scripts/geckolib_gen/paint_lib.GeoPainter`): deepslate/obsidian plinth, violet rune script, eclipse core with corona rim, ring ticks, crown inlay — writes `textures/block/altar.png` + `altar_glowmask.png` (822 emissive px: runes, core, ring ticks, horn tips, crown inlay) |
| `textures/block/altar.png` + `altar_glowmask.png` C | Generated output (256×128 RGBA) |
| `ritual/AltarBlockEntity.java` M | Implements `GeoBlockEntity`: one controller `state` (idle loop) + 4 `triggerableAnim` one-shots. Fires `heartbeat` itself on every accepted payment (milestone deposit w/o completion, shard banking, accepted offering) and `stage_up` from `completeMilestone`. NBT/logic untouched |
| `ritual/AltarBlock.java` M | `getRenderShape` → `INVISIBLE` (respawn-door pattern; hitbox/collision/loot/interactions unchanged — `blockstates/altar.json` + `models/block/altar.json` stay for breaking particles + the admin BlockItem) + `heartbeat` on shard banking |
| `client/altarmodel/AltarModelRenderer.java` C | `GeoBlockRenderer<AltarBlockEntity>` + `DefaultedBlockGeoModel` (id `eclipse:altar` resolves the geo/anim/texture triple) + `AutoGlowingGeoLayer` (`_glowmask` convention) + widened `getRenderBoundingBox` (±2 xz, +5 y — the `RespawnDoorRenderer` precedent) |
| `client/altarmodel/AltarModelRenderers.java` C | BER registration on `EntityRenderersEvent.RegisterRenderers` (client bus) |
| `client/altarmodel/package-info.java` C | Package doc |
| `ritual/AltarModelTriggers.java` C | **The facade for other agents**: `trigger(ServerLevel, String)`, plus `gift(level)` / `erupt(level)` / `heartbeat(level)` conveniences. Altar found via `EclipseWorldState.getSanctumAltarPos()`; unloaded/missing altar → logged no-op `false`. No new payloads — GeckoLib's own BE trigger sync |
| `tools/photon/altar_aura_fx.py` C | Generates the four aura loop assets (fxlib; all PASS `fxlib.validate_file`) |
| `assets/eclipse/fx/altar_aura_{motes,glyphs,pillar,bands}.fx` (+`.fxproj`) C | Stage 1: rising violet motes + ground-fog ring · Stage 2: orbiting rune-spark band + ground pulse · Stage 2 far tell: one soft pulsing light column · Stage 4+: two counter-orbiting tilted light bands + occasional energy arcs |
| `veilfx/AltarAuraFxRows.java` C | Four LOOP rows (`FxCues.cue("altar_aura_…")`), `quasarEmitter=null` (Photon-only garnish — legal for NEW cues; the shipped Quasar idle stack stays the photon-less read), channel AMBIENT, Mode LAYER |
| `client/drama/AltarAuraIdle.java` C | The WINDOWED loop driver: per-row hysteresis windows off `FxAnchors.ALTAR_CENTER` + `ClientStateCache.altarLevel`. Near band 88/96 (the "< 96" LOD law), far tell 200/220. Releases on reducedFx/anchor loss/stage drop/dimension/logout; refused spawns back off 40 t. Worst case 4 aura executors + corona = 5 of `PhotonBridge.MAX_LIVE_EXECUTORS` |
| `client/drama/AltarAuraGrade.java` C | Veil garnish: registers `eclipse:altar_aura_grade` at **GRADE priority** (= evicted FIRST when the ≤3-pass budget fills — the sanctioned "nur wenn frei" contract). Strength = stageFactor(L3⅓/L4⅔/L5 1) × (1−d/72)², eased 20 t; zero under reducedFx / below L3 / no anchor |
| `pinwheel/post/altar_aura_grade.json` + `shaders/program/altar_aura_grade.{json,fsh}` C | The shimmer: [g1] rising heat-haze UV wobble ≤ ~0.9 px (Detail-gated), [g2] violet-gold highlight bloom lift ≤ +12 %, [g3] parabolic midtone consecration tint, output dither. Uniforms `Aura, Time, Detail`; `eclipse:eclipse_common` helpers, zero textures |

## Frozen surface delivered (exact, for consumers)

```java
// server — fire a one-shot on the altar's GeckoLib model from ANY system:
boolean AltarModelTriggers.trigger(ServerLevel overworld, String animName); // ANIM_* names
boolean AltarModelTriggers.gift(ServerLevel);      // post-purchase "the altar gives"
boolean AltarModelTriggers.erupt(ServerLevel);     // End reveal / finale quake
boolean AltarModelTriggers.heartbeat(ServerLevel); // "the altar noticed" pulse
// names: AltarBlockEntity.ANIM_HEARTBEAT / ANIM_GIFT / ANIM_ERUPT / ANIM_STAGE_UP
// (CONTROLLER_STATE = "state"; GEO_ID = "altar")
```

## Open wiring (for other agents)

- **`gift`**: the ALTARUI agent should call `AltarModelTriggers.gift(serverLevel)` when a
  shop purchase completes (server side of the buy flow). Not wired here — the buy flow
  belongs to that agent.
- **`erupt`**: whoever owns the End-reveal / finale beat should call
  `AltarModelTriggers.erupt(overworld)` at the reveal moment.
- `heartbeat` + `stage_up` are already fired internally by the ritual code; no action.
- The old `blockstates/altar.json` + `models/block/altar.json` are intentionally KEPT
  (breaking particles + admin BlockItem inventory look). Do not delete them.

## Test-Anleitung

1. `/setblock ~ ~ ~ eclipse:altar` (or visit the sanctum) — the monument renders: plinth,
   floating core, three slowly counter-rotating rings, drifting debris; rune plates, core,
   ring ticks and horn tips glow in the dark (glowmask). Block hitbox is still the full
   cube; breaking shows stone-ish particles; interactions (deposit/offering/UI) unchanged.
2. One-shots: `AltarModelTriggers` from any server hook, or organically — deposit a
   milestone item (heartbeat), complete a milestone (`stage_up` fanfare under the level-up
   ceremony), sneak-confirm an offering (heartbeat).
3. Aura: set the altar level (`/eclipse altar set 1..5` — the admin lane that resyncs
   `ClientStateCache.altarLevel` via `S2CDayStatePayload`) and stand near the island: L1 motes+fog ring; L2 adds
   rune sparks + ground pulse + (from anywhere < 200 blocks) the far light column; L4 adds
   the orbit bands + arcs. Walk out past ~96 blocks: near loops fade, the column stays
   until ~220. `reducedFx` kills all aura loops + the shimmer instantly.
4. Shimmer: at L3+ near the island (< 72 blocks, no Iris pack, `veilPostFx` on) the air
   gains a subtle rising heat-haze + violet bloom. Force-check: `/eclipsefx post
   eclipse:altar_aura_grade on`. Budget check: when night grade + sun halo + altar
   aberration all run, the shimmer yields (GRADE evicts first) — intended.

## Risiken

- **Glow layer**: `AutoGlowingGeoLayer` uses GeckoLib's emissive render type — if the
  pack ever swaps GeckoLib majors, re-verify the `_glowmask` suffix convention.
- **Render box**: the geo overhangs the block cell (~±1 block, ~2.4 high; erupt lifts the
  core ~1 more). `getRenderBoundingBox` covers ±2/+5 — if a future anim moves bones
  further, widen it.
- **Executor budget**: worst case the island holds 7 live loop executors since F-075 V2
  (4 V1 aura + L5 corona + one rim tier + one spiral tier — the V2 families tier-swap,
  never stack; see `docs/plans_v3/feedback3/PLAN-F075-altar-insel-aura.md`). If
  `PhotonBridge.MAX_LIVE_EXECUTORS` is ever lowered below ~10, revisit.
- **No compile run**: per order no `./gradlew` — all signatures verified via `javap`
  (GeckoLib 4.9.2 jar) + repo precedents (`RespawnDoorRenderer`, `GhostGradeFx`,
  `AltarAberration`, `SanctumLightfall`). Assets machine-validated (geo/anim validator,
  fxlib round-trip, PIL).
