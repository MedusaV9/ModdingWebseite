# WB-ART wiring — final pixel-art pass on placeholder item/block textures

**Worker:** WB-ART (final art pass, 2026-07-23)
**Scope:** every documented programmer-art placeholder among the `eclipse` ITEM + BLOCK
pixel textures (see `docs/ASSET_MANIFEST_V2.md` Batch E + WB-ART addendum, and the
PLACEHOLDER-SUSPECTS section of `docs/plans_v3/asset_audit.md`).
**Method:** deterministic python painters under `scripts/item_art/` sharing
`scripts/item_art/eclipse_palette.py` (palette constants mirror the frozen
`client/handbook/EclipseUiTheme.java` tokens; shared `finish()` pass = 2px black-purple
edge, 3-tone shading, top-left rim light, selective 1px magenta/cyan glow accents, no
noise fills). All paths, canvas sizes and alpha/channel modes are byte-compatible with
the placeholders they replace. Reruns are byte-identical (verified). No gradle run.

## Generator scripts

| Script | Regenerates |
|---|---|
| `scripts/item_art/eclipse_palette.py` | (shared palette + finishing pass — no output) |
| `scripts/item_art/gen_shards.py` | `umbral_shard`, `vitae_shard` |
| `scripts/item_art/gen_relics.py` | `herald_core`, `heralds_lure`, `ferryman_toll`, `revive_sigil`, `arm_artifact` |
| `scripts/item_art/gen_umbral_tools.py` | `umbral_pick`, `umbral_blade` |
| `scripts/item_art/gen_display_wand.py` (reworked) | `display_wand` |
| `scripts/item_art/gen_trackers.py` | `compass_of_watcher_00..31`, `grave_dowser_00..31` |
| `scripts/item_art/gen_event_blocks.py` | `altar_top`, `altar_side`, `altar_bottom`, `grave`, `grave_side` |
| `scripts/item_art/gen_b8_items.py` (heart_extractor repainted) | `heart_extractor` (also `glitch_shard`, `heart_fragment` — byte-identical, left as committed) |

## Regenerated files → model references

All texture paths below are relative to `src/main/resources/assets/eclipse/textures/`;
all model paths relative to `src/main/resources/assets/eclipse/models/`. Every output
path was grep-verified against the model JSONs (80 PNGs regenerated, 80/80 referenced).

### Items (16×16, RGBA, `minecraft:item/generated` layer0)

| Texture | Referencing model |
|---|---|
| `item/umbral_shard.png` | `item/umbral_shard.json` |
| `item/vitae_shard.png` | `item/vitae_shard.json` |
| `item/herald_core.png` | `item/herald_core.json` |
| `item/heralds_lure.png` | `item/heralds_lure.json` |
| `item/ferryman_toll.png` | `item/ferryman_toll.json` |
| `item/revive_sigil.png` | `item/revive_sigil.json` |
| `item/arm_artifact.png` | `item/arm_artifact.json` |
| `item/umbral_pick.png` | `item/umbral_pick.json` |
| `item/umbral_blade.png` | `item/umbral_blade.json` |
| `item/display_wand.png` | `item/display_wand.json` |
| `item/heart_extractor.png` | `item/heart_extractor.json` |
| `item/compass_of_watcher_NN.png` (NN = 00..31, 32 files) | `item/compass_of_watcher_NN.json` (one per frame); `_16` additionally layer0 of the base `item/compass_of_watcher.json`, whose `angle` override chain selects the frame models |
| `item/grave_dowser_NN.png` (NN = 00..31, 32 files) | `item/grave_dowser_NN.json` (one per frame); `_16` additionally layer0 of the base `item/grave_dowser.json` (`angle` override chain) |

Tracker frame semantics preserved from the placeholders: frame 00 needle DOWN,
08 LEFT, 16 UP, 24 RIGHT (direction `(-sin, cos)` of `2π·frame/32`).

### Blocks (16×16)

| Texture | Referencing model |
|---|---|
| `block/altar_top.png` (RGBA opaque) | `block/altar.json` (`top`; `item/altar.json` via parent) |
| `block/altar_side.png` (RGBA opaque) | `block/altar.json` (`side`) |
| `block/altar_bottom.png` (RGBA opaque) | `block/altar.json` (`bottom`) |
| `block/grave.png` (RGB) | `block/grave.json` (`end`; `item/grave.json` via parent) |
| `block/grave_side.png` (RGB) | `block/grave.json` (`side`) |

`grave*.png` are saved as RGB to match the channel layout of the placeholders they
replace (solid cube faces, no alpha channel).

## Evaluated, deliberately NOT regenerated

- **Pale garden set** (`block/pale_*`, `block/stripped_pale_*`, `item/pale_hanging_moss`):
  fresh from `tools/palegarden/gen_textures.py`, reviewed at 8× — bark furrows, growth
  rings, plank rows and foliage cutouts all read; not flat. The pale desaturated look is
  a frozen design decision (manifest addendum P1-W1.4), so the generator was left as-is.
- **`gen_b8_items.py` `glitch_shard` / `heart_fragment`**: reviewed at 8× — silhouettes
  and glitch accents already read at 16px; regenerated output is byte-identical.
- **`block/respawn_door.png` + `_glowmask`**: GeckoLib texture painted by
  `scripts/geckolib_gen/mobs/respawn_door.py` — P6 pipeline, out of scope.
- **Hard-rule exclusions**: hero art (title bg/logo/panorama/sun/eclipse disc/artifact
  menu panel), `textures/entity/*`, `block|item/classic/*`, GUI nine-slices.
- **`supply_beacon` / `eclipses_favor`**: lang entries exist but no models or texture
  paths are registered — nothing to regenerate without inventing new paths (forbidden).

## Review artifacts

BEFORE/AFTER contact sheets (8× nearest-neighbor, alpha checkerboard) per family:
`/opt/cursor/artifacts/wb_art_before_after_{shards,relics,tools,compass,dowser,b8,event_blocks}.png`.

## Verification performed

- Size/mode/alpha: 75 item PNGs 16×16 RGBA with transparent background; 5 block PNGs
  16×16 with placeholder-matching channel modes, fully opaque. PASS.
- Model references: every regenerated texture id appears in a model JSON. PASS (80/80).
- Determinism: rerunning all 7 generators reproduces byte-identical files. PASS.
- No gradle invoked; no commits/pushes made (per WB-ART hard rules).
