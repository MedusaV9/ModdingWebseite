# VFXPOLISH-2 — Quasar emitter audit & polish (all 35 emitters)

Pass over every JSON in `assets/eclipse/quasar/emitters/` against the **actual Veil 4.3.0
codecs** (field tables extracted from `veil-neoforge-1.21.1-4.3.0.jar` via `javap`, not
guessed from examples). Cross-checked against the proven `cutscene_veil.json` /
`border_glitch.json`. Structural validator re-run after edits: **35/35 pass** (schema keys,
shape/render-style ids, sprites on disk, no `veil:light`, every color module fades to 0).

## Ground rules used

- **Perf ban honored**: zero `veil:light` modules anywhere (verified by grep + validator).
- **Spawn math**: `count` particles spawn every `rate` ticks (`scheduleAtFixedRate(1, rate)`),
  so one-shots with `max_lifetime` N and rate R fire ceil(N/R) waves. `max_particles`
  (optional top-level, default unbounded) gates `spawn()` — used as a safety cap on loopers.
- **Codec key gotchas** (from the jar — the ImGui labels differ from the JSON keys!):
  - `veil:point_attractor`: `position`, `localPosition`, `range`, `strength`,
    `strengthByDistance` (**required**, camelCase), `invertDistanceModifier`.
  - `veil:point_force`: `point`, `localPoint` (camelCase), `range`, `strength`.
  - `veil:vortex` uses snake_case `local_position`; `veil:initial_velocity` uses
    snake_case `take_parent_rotation`. Mixed conventions are real, not a mistake.
  - `sprite_data` is optional (block-render emitters legally omit it).
  - Trails without `trailTexture` render with Veil's `textures/special/blank.png` fallback — fine.
  - `velocity_stretch_factor` applies even when `face_velocity=false`, but then stretches in
    billboard-local space instead of along motion; strongly stretched directional emitters
    must pair it with `face_velocity: true` (as proven `cutscene_veil` does).

## Palette normalization

Eclipse tokens: deep `#2E2347`, accent `#7B4FD0`, light `#B98CFF`, white-violet highlight
`#EFE4FF`, plus a shared alpha-blend **dust ramp** `#7A6B99 → #473A63 → #241C38`.
Mapping applied: light violets (`#E0AAFF #D9A8FF #D9A7FF #C77DFF #C9B8E8`) → `#B98CFF`;
mid/deep accents (`#B65CFF #9D4EDD #A87BDD #8A4DD8 #7A2FD0 #7B2CBF #6B2FB3`) → `#7B4FD0`;
tail purples (`#5B1E99 #3C096C #4A0E80`) → `#2E2347`; near-whites (`#F4E9FF #E8D4FF`) →
`#EFE4FF`. Additive ramps: snappy sparks end on ACCENT, long glows/motes melt into DEEP.
**Semantic accents kept**: reward gold (`#FFF1B8/#FFD166/#FFE9A8/#FFF3C4`), danger red,
follow blue, storm steel-blue, heart pink. **Exempt files** (proven or post-pipeline-graded
looks): `cutscene_veil`, `border_glitch`, `border_shard`, `heart_burst`, `limbo_fog`,
`limbo_fogbank`, `limbo_godray` (colors untouched).

## Per-emitter verdicts

| Emitter | Schema | Perf/feel verdict | Changes applied |
|---|---|---|---|
| `altar_beam` | OK | ~60 concurrent column particles is the documented supply-drop budget (`SupplyBeamClient`) — kept | colors → light/accent/deep |
| `altar_levelup_ring` | OK (`localPoint` is the correct camelCase key) | rate 1 fired 4 waves ×12 = 48 for a "ring burst"; smeary + heavy | **rate 1→2** (2 crisp pulses, 24 total); ring tail colors → light/accent (golds kept) |
| `altar_reveal_burst` | OK | 2 waves ×12, floaty gravity/drag pair reads well | colors → light + deep tail (golds kept) |
| `arm_wisps` | OK | vortex+trail, ~6 alive — cheap | colors + trailColor → light/accent |
| `border_glitch` | OK (proven reference) | deliberate strobe alpha — untouched | none |
| `border_shard` | OK; sprite `textures/environment/border_glitch.png` exists | family-consistent with proven sibling | none |
| `boss_slam` | OK (`should_collide` + `die_on_collision` correctly paired) | 2 waves ×20 = 40 **colliding** particles — the most expensive per-particle path in the set | **count 20→14** (28 total); colors → light/accent/deep |
| `crater_updraft` | OK | weightless mote family (wind up + drag 0.02) ✓, ~30 tiny alive | colors → light/accent/deep |
| `cutscene_veil` | OK (proven reference) | untouched baseline | none |
| `door_glow_motes` | OK | weightless mote family ✓, ~9 alive | colors → light/accent/deep |
| `eclipse_lightning_impact` | OK | white-hot head, face_velocity+stretch 1.6 correct, 28 total | colors → white/light/accent/deep ramp |
| `glide_trail` | OK | 1/2-tick trail mote, cheap per-player | colors + trailColor → light/accent |
| `glyph_danger` | OK | red semantic kept; snappy drag 0.92 ✓ | tail → accent |
| `glyph_follow` | OK | blue semantic kept; trail fine | tail → light |
| `glyph_greet` | OK | gold semantic kept | tail → light |
| `growth_dust_wall` | OK | 8 huge alpha-blend quads, alpha ≤0.28 — acceptable wall | colors → dust ramp |
| `heart_burst` | OK; sprite `textures/gui/heart_full.png` exists | alpha-blend correct for shaped sprite; pink semantic kept | none |
| `impact_light` | OK | 3–6 big additive flash quads, lifetime 5 — classic cheap flash | colors → highlight/accent |
| `limbo_fog` | OK | density managed by `LimboAmbience` rolling windows — rates untouched | **`max_particles: 20`** safety cap |
| `limbo_fogbank` | OK | 20-size quads at alpha 0.08, ~5 alive — fillrate-heavy but few; graded look kept | **`max_particles: 8`** safety cap |
| `limbo_godray` | OK (face_velocity+stretch 2.5 correct) | ~8 alive shafts | **`max_particles: 10`** safety cap |
| `limbo_motes` | OK | "denser since v2" is deliberate (code comment) — rate kept | **`max_particles: 64`** safety cap; colors → light/accent |
| `map_expand_materialize` | OK (`sprite_data` legally absent for `veil:cube` + `veil:block`) | rate 1 spawned 60 ghost cubes/burst; cubes popped in/out with no fade | **rate 1→2** (30 total); **added `veil:color` white fade-in/out module** |
| `offering_swallow` | OK | 1/tick stream along scripted spiral path (`OfferingSwallowFx`) — correct pattern | colors → light/accent (gold head + gold trail kept) |
| `portal_surface_motes` | **BUG — emitter failed to decode**: `strength_by_distance` etc. are wrong keys; `strengthByDistance` is a *required* camelCase field, so DFU rejected the whole file | after fix: slow vortex+attractor surface crawl, ~11 alive — good | **fixed keys** `localPosition` / `strengthByDistance` / `invertDistanceModifier`; colors → light/accent/deep |
| `rift_spark` | OK | strobe alpha intentional; snappy | colors → highlight/light/accent |
| `roulette_flare` | OK | additive gold flare, 28 total ✓ | colors → light/accent (golds kept) |
| `sanctum_lightfall` | OK | rate 1 = 20 spawns/s ≈ 45 alive for an *always-on* ambience — heavy; streaks weren't aligned to fall | **rate 1→2** (~22 alive) + **`max_particles: 32`**; **`face_velocity: true`** (stretch 0.9 now streaks along the fall); colors → highlight/light/deep |
| `slam_debris` | OK | drag 0.98 + gravity 0.8 froze debris mid-air (drag kills velocity before gravity arcs read); 50t too long for chunks | **drag 0.98→0.6, lifetime 50→40**; colors → dust ramp |
| `storm_arc` | OK | stretch 1.2 with `face_velocity: false` stretched quads off-axis | **`face_velocity: true`**; colors → white/light/accent |
| `storm_rain_sheet` | OK | steel-blue semantic kept; stretch 1.6 needs motion alignment | **`face_velocity: true`** |
| `structure_slam_dust` | OK | head `#8A7B6F` was **brown** — off-palette outlier | colors → dust ramp |
| `supply_spark` | OK | fountain arcs (init-vel up + gravity) ✓ | **`face_velocity: true`** (stretch 0.4 along arc); colors → light/accent |
| `unlock_burst` | OK | gold reward burst, 20 total ✓ | colors → light/accent (golds kept) |
| `vortex_wisp` | OK | alpha-blend smoke column ✓, ~33 alive moderate | mid/tail snapped to dust ramp |

## Verification

- `python3` structural validator (schema tables from the jar): pre-edit tree fails with
  exactly the `portal_surface_motes` missing-required-key error; post-edit tree **35/35 OK**.
- All 35 files re-parsed as strict JSON.
- Sprite audit: 33× `textures/particle/purple_wisp.png`, 1× `textures/environment/border_glitch.png`,
  1× `textures/gui/heart_full.png` — all present on disk.
- Remaining non-token colors are confined to the exempt files listed above (checked by grep).
