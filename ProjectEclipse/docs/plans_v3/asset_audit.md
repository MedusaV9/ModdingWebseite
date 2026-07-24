# Eclipse Event — Asset Integration Audit

**Generated:** 2026-07-23  
**Mod:** Eclipse Event (`eclipse`) — NeoForge 1.21.1  
**Scope:** `src/main/resources/assets/eclipse/`, `data/eclipse/`, `data/minecraft/`  
**Method:** File inventory + cross-reference against `src/main/java/**` and JSON assets (models, blockstates, sounds.json, quasar emitters, pinwheel pipelines, particles, cutscenes). No Gradle run.

## Executive summary

- **279** resource files inventoried (~28.64 MB).
- **279** classified **USED** (reachable from Java, JSON, registry, or datapack linkage).
- **0** classified **UNREFERENCED** on disk.
- **4** **MISSING** or path-mismatched vs manifest/code expectations.

The complaint that generated assets were not integrated is **partially true, mostly a hearts-HUD gap**: handbook/title/bossbar/entity/quasar/pinwheel/cutscene assets are referenced and should load. What is **not** integrated: Batch B **custom hearts bar** (`heart_cracked`, 36×36 `gui/hearts/*` layout), and the **eclipse_event_logo** artifact never copied into resources. Several large handbook/title PNGs **are** wired via dynamic `handbookTexture()` / `titleTexture()` helpers (not literal string greps).

## Inventory summary (by category)

| Category | Files | Used | Unreferenced | Total size |
|---|---:|---:|---:|---:|
| blockstate | 2 | 2 | 0 | 134 B |
| cutscene | 4 | 4 | 0 | 3.4 KB |
| data_eclipse | 6 | 6 | 0 | 5.2 KB |
| data_minecraft | 5 | 5 | 0 | 1.3 KB |
| lang | 2 | 2 | 0 | 36.1 KB |
| model | 80 | 80 | 0 | 14.4 KB |
| particle | 1 | 1 | 0 | 50 B |
| pinwheel | 9 | 9 | 0 | 4.0 KB |
| quasar | 9 | 9 | 0 | 17.7 KB |
| sound | 15 | 15 | 0 | 274.8 KB |
| sounds_json | 1 | 1 | 0 | 2.6 KB |
| texture | 145 | 145 | 0 | 28.29 MB |
| **TOTAL** | **279** | **279** | **0** | **28.64 MB** |

## Full inventory (path + size)

### `assets/eclipse/` (1 files)

| Path | Size |
|---|---:|
| `assets/eclipse/sounds.json` | 2.6 KB |

### `assets/eclipse/blockstates/` (2 files)

| Path | Size |
|---|---:|
| `assets/eclipse/blockstates/altar.json` | 67 B |
| `assets/eclipse/blockstates/grave.json` | 67 B |

### `assets/eclipse/cutscenes/` (4 files)

| Path | Size |
|---|---:|
| `assets/eclipse/cutscenes/finale_return.json` | 801 B |
| `assets/eclipse/cutscenes/intro_rise.json` | 672 B |
| `assets/eclipse/cutscenes/intro_submerge.json` | 926 B |
| `assets/eclipse/cutscenes/unlock_ring.json` | 1.0 KB |

### `assets/eclipse/lang/` (2 files)

| Path | Size |
|---|---:|
| `assets/eclipse/lang/de_de.json` | 18.7 KB |
| `assets/eclipse/lang/en_us.json` | 17.4 KB |

### `assets/eclipse/models/block/` (2 files)

| Path | Size |
|---|---:|
| `assets/eclipse/models/block/altar.json` | 192 B |
| `assets/eclipse/models/block/grave.json` | 140 B |

### `assets/eclipse/models/item/` (78 files)

_Collapsed: assets/eclipse/models/item/altar.json … assets/eclipse/models/item/vitae_shard.json — 78 files, 14.0 KB total._

| Path (sample) | Size |
|---|---:|
| `assets/eclipse/models/item/altar.json` | 38 B |
| `assets/eclipse/models/item/grave_dowser_01.json` | 109 B |
| `assets/eclipse/models/item/vitae_shard.json` | 105 B |

### `assets/eclipse/particles/` (1 files)

| Path | Size |
|---|---:|
| `assets/eclipse/particles/purple_wisp.json` | 50 B |

### `assets/eclipse/pinwheel/post/` (3 files)

| Path | Size |
|---|---:|
| `assets/eclipse/pinwheel/post/border_glitch.json` | 157 B |
| `assets/eclipse/pinwheel/post/limbo.json` | 149 B |
| `assets/eclipse/pinwheel/post/sun_halo.json` | 152 B |

### `assets/eclipse/pinwheel/shaders/program/` (6 files)

| Path | Size |
|---|---:|
| `assets/eclipse/pinwheel/shaders/program/border_glitch.fsh` | 1.7 KB |
| `assets/eclipse/pinwheel/shaders/program/border_glitch.json` | 74 B |
| `assets/eclipse/pinwheel/shaders/program/limbo.fsh` | 640 B |
| `assets/eclipse/pinwheel/shaders/program/limbo.json` | 66 B |
| `assets/eclipse/pinwheel/shaders/program/sun_halo.fsh` | 1.0 KB |
| `assets/eclipse/pinwheel/shaders/program/sun_halo.json` | 69 B |

### `assets/eclipse/quasar/emitters/` (9 files)

| Path | Size |
|---|---:|
| `assets/eclipse/quasar/emitters/altar_beam.json` | 2.2 KB |
| `assets/eclipse/quasar/emitters/arm_wisps.json` | 2.4 KB |
| `assets/eclipse/quasar/emitters/border_glitch.json` | 2.1 KB |
| `assets/eclipse/quasar/emitters/boss_slam.json` | 2.0 KB |
| `assets/eclipse/quasar/emitters/cutscene_veil.json` | 1.9 KB |
| `assets/eclipse/quasar/emitters/heart_burst.json` | 1.8 KB |
| `assets/eclipse/quasar/emitters/limbo_motes.json` | 2.0 KB |
| `assets/eclipse/quasar/emitters/map_expand_materialize.json` | 1.2 KB |
| `assets/eclipse/quasar/emitters/unlock_burst.json` | 2.1 KB |

### `assets/eclipse/sounds/ambient/` (2 files)

| Path | Size |
|---|---:|
| `assets/eclipse/sounds/ambient/gazer_whisper.ogg` | 19.8 KB |
| `assets/eclipse/sounds/ambient/limbo_loop.ogg` | 83.1 KB |

### `assets/eclipse/sounds/boss/` (4 files)

| Path | Size |
|---|---:|
| `assets/eclipse/sounds/boss/ferryman_ambient.ogg` | 23.0 KB |
| `assets/eclipse/sounds/boss/ferryman_bell.ogg` | 21.6 KB |
| `assets/eclipse/sounds/boss/herald_ambient.ogg` | 8.0 KB |
| `assets/eclipse/sounds/boss/herald_telegraph.ogg` | 4.8 KB |

### `assets/eclipse/sounds/event/` (3 files)

| Path | Size |
|---|---:|
| `assets/eclipse/sounds/event/border_glitch.ogg` | 15.7 KB |
| `assets/eclipse/sounds/event/emerge.ogg` | 33.0 KB |
| `assets/eclipse/sounds/event/submerge.ogg` | 31.4 KB |

### `assets/eclipse/sounds/ui/` (6 files)

| Path | Size |
|---|---:|
| `assets/eclipse/sounds/ui/heart_shatter.ogg` | 13.3 KB |
| `assets/eclipse/sounds/ui/hover.ogg` | 3.5 KB |
| `assets/eclipse/sounds/ui/page_turn.ogg` | 4.9 KB |
| `assets/eclipse/sounds/ui/tab.ogg` | 3.9 KB |
| `assets/eclipse/sounds/ui/typewriter.ogg` | 3.5 KB |
| `assets/eclipse/sounds/ui/unlock_sting.ogg` | 5.3 KB |

### `assets/eclipse/textures/block/` (5 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/block/altar_bottom.png` | 166 B |
| `assets/eclipse/textures/block/altar_side.png` | 172 B |
| `assets/eclipse/textures/block/altar_top.png` | 175 B |
| `assets/eclipse/textures/block/grave.png` | 131 B |
| `assets/eclipse/textures/block/grave_side.png` | 109 B |

### `assets/eclipse/textures/entity/` (8 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/entity/deckhand.png` | 2.7 KB |
| `assets/eclipse/textures/entity/eclipsed_player.png` | 995 B |
| `assets/eclipse/textures/entity/ferryman.png` | 6.3 KB |
| `assets/eclipse/textures/entity/gazer.png` | 3.0 KB |
| `assets/eclipse/textures/entity/herald.png` | 2.2 KB |
| `assets/eclipse/textures/entity/sunmote.png` | 205 B |
| `assets/eclipse/textures/entity/the_other.png` | 549 B |
| `assets/eclipse/textures/entity/umbral_stalker.png` | 2.8 KB |

### `assets/eclipse/textures/environment/` (3 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/environment/border_glitch.png` | 81.2 KB |
| `assets/eclipse/textures/environment/eclipse.png` | 5.8 KB |
| `assets/eclipse/textures/environment/sun_purple.png` | 1.8 KB |

### `assets/eclipse/textures/gui/` (3 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/heart_empty.png` | 332 B |
| `assets/eclipse/textures/gui/heart_full.png` | 401 B |
| `assets/eclipse/textures/gui/wave_overlay.png` | 58.8 KB |

### `assets/eclipse/textures/gui/bossbar/` (6 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/bossbar/boss_frame.png` | 44.1 KB |
| `assets/eclipse/textures/gui/bossbar/day_frame.png` | 72.4 KB |
| `assets/eclipse/textures/gui/bossbar/fill.png` | 28.4 KB |
| `assets/eclipse/textures/gui/bossbar/glow.png` | 7.7 KB |
| `assets/eclipse/textures/gui/bossbar/goal_frame.png` | 61.7 KB |
| `assets/eclipse/textures/gui/bossbar/scroll.png` | 21.6 KB |

### `assets/eclipse/textures/gui/cursor/` (3 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/cursor/arrow.png` | 1.8 KB |
| `assets/eclipse/textures/gui/cursor/grab.png` | 2.2 KB |
| `assets/eclipse/textures/gui/cursor/hand.png` | 2.1 KB |

### `assets/eclipse/textures/gui/handbook/` (18 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/handbook/book_spread.png` | 4.22 MB |
| `assets/eclipse/textures/gui/handbook/divider.png` | 58.5 KB |
| `assets/eclipse/textures/gui/handbook/hero_bestiary.png` | 1.01 MB |
| `assets/eclipse/textures/gui/handbook/hero_map.png` | 1.64 MB |
| `assets/eclipse/textures/gui/handbook/hero_rewards.png` | 1.28 MB |
| `assets/eclipse/textures/gui/handbook/hero_rules.png` | 1.44 MB |
| `assets/eclipse/textures/gui/handbook/hero_status.png` | 1.31 MB |
| `assets/eclipse/textures/gui/handbook/hero_timeline.png` | 1.40 MB |
| `assets/eclipse/textures/gui/handbook/parchment_tile.png` | 1.90 MB |
| `assets/eclipse/textures/gui/handbook/tab_bestiary.png` | 6.5 KB |
| `assets/eclipse/textures/gui/handbook/tab_map.png` | 7.5 KB |
| `assets/eclipse/textures/gui/handbook/tab_rewards.png` | 6.6 KB |
| `assets/eclipse/textures/gui/handbook/tab_rules.png` | 5.9 KB |
| `assets/eclipse/textures/gui/handbook/tab_status.png` | 6.9 KB |
| `assets/eclipse/textures/gui/handbook/tab_timeline.png` | 3.6 KB |
| `assets/eclipse/textures/gui/handbook/timeline_node_current.png` | 26.4 KB |
| `assets/eclipse/textures/gui/handbook/timeline_node_locked.png` | 23.6 KB |
| `assets/eclipse/textures/gui/handbook/timeline_node_unlocked.png` | 26.7 KB |

### `assets/eclipse/textures/gui/hearts/` (1 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/hearts/burst_sheet.png` | 17.9 KB |

### `assets/eclipse/textures/gui/icons/` (1 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/icons/altar_ring.png` | 93.9 KB |

### `assets/eclipse/textures/gui/sidebar/` (6 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/sidebar/icon_altar.png` | 1.2 KB |
| `assets/eclipse/textures/gui/sidebar/icon_day.png` | 1.7 KB |
| `assets/eclipse/textures/gui/sidebar/icon_goal.png` | 1.1 KB |
| `assets/eclipse/textures/gui/sidebar/icon_heart.png` | 1.3 KB |
| `assets/eclipse/textures/gui/sidebar/icon_players.png` | 1.7 KB |
| `assets/eclipse/textures/gui/sidebar/panel.png` | 451 B |

### `assets/eclipse/textures/gui/title/` (16 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/gui/title/background.png` | 877.4 KB |
| `assets/eclipse/textures/gui/title/button.png` | 254 B |
| `assets/eclipse/textures/gui/title/button_highlighted.png` | 232 B |
| `assets/eclipse/textures/gui/title/flare_sweep.png` | 76.9 KB |
| `assets/eclipse/textures/gui/title/gear.png` | 3.9 KB |
| `assets/eclipse/textures/gui/title/logo.png` | 63.1 KB |
| `assets/eclipse/textures/gui/title/panorama_0.png` | 1.63 MB |
| `assets/eclipse/textures/gui/title/panorama_1.png` | 1.63 MB |
| `assets/eclipse/textures/gui/title/panorama_2.png` | 1.63 MB |
| `assets/eclipse/textures/gui/title/panorama_3.png` | 1.63 MB |
| `assets/eclipse/textures/gui/title/panorama_4.png` | 1.63 MB |
| `assets/eclipse/textures/gui/title/panorama_5.png` | 1.63 MB |
| `assets/eclipse/textures/gui/title/parallax_far.png` | 908.8 KB |
| `assets/eclipse/textures/gui/title/parallax_mid.png` | 946.4 KB |
| `assets/eclipse/textures/gui/title/parallax_near.png` | 848.9 KB |
| `assets/eclipse/textures/gui/title/wisp.png` | 1.1 KB |

### `assets/eclipse/textures/item/` (74 files)

_Collapsed: assets/eclipse/textures/item/arm_artifact.png … assets/eclipse/textures/item/vitae_shard.png — 74 files, 13.4 KB total._

| Path (sample) | Size |
|---|---:|
| `assets/eclipse/textures/item/arm_artifact.png` | 155 B |
| `assets/eclipse/textures/item/grave_dowser_03.png` | 188 B |
| `assets/eclipse/textures/item/vitae_shard.png` | 131 B |

### `assets/eclipse/textures/particle/` (1 files)

| Path | Size |
|---|---:|
| `assets/eclipse/textures/particle/purple_wisp.png` | 145 B |

### `data/eclipse/dimension/` (1 files)

| Path | Size |
|---|---:|
| `data/eclipse/dimension/limbo.json` | 375 B |

### `data/eclipse/dimension_type/` (1 files)

| Path | Size |
|---|---:|
| `data/eclipse/dimension_type/limbo.json` | 479 B |

### `data/eclipse/loot_table/` (1 files)

| Path | Size |
|---|---:|
| `data/eclipse/loot_table/supply_crate.json` | 3.2 KB |

### `data/eclipse/recipe/` (2 files)

| Path | Size |
|---|---:|
| `data/eclipse/recipe/heralds_lure.json` | 311 B |
| `data/eclipse/recipe/revive_sigil.json` | 430 B |

### `data/eclipse/worldgen/biome/` (1 files)

| Path | Size |
|---|---:|
| `data/eclipse/worldgen/biome/limbo.json` | 424 B |

### `data/minecraft/dimension/` (2 files)

| Path | Size |
|---|---:|
| `data/minecraft/dimension/overworld.json` | 113 B |
| `data/minecraft/dimension/the_nether.json` | 111 B |

### `data/minecraft/dimension_type/` (2 files)

| Path | Size |
|---|---:|
| `data/minecraft/dimension_type/overworld.json` | 544 B |
| `data/minecraft/dimension_type/the_nether.json` | 481 B |

### `data/minecraft/tags/entity_type/` (1 files)

| Path | Size |
|---|---:|
| `data/minecraft/tags/entity_type/can_breathe_under_water.json` | 89 B |

## USED — summary

**279 / 279** files are referenced. Key wiring points:

| Subsystem | Asset types | Primary reference sites |
|---|---|---|
| Handbook UI | `textures/gui/handbook/*`, cursors | `HandbookScreen`, `HandbookTab.handbookTexture()`, tab classes |
| Title screen | `textures/gui/title/*` | `EclipseTitleScreen.titleTexture()`, `CubeMap` panorama |
| Bossbar skin | `textures/gui/bossbar/*` | `BossbarSkin.texture()` / `frameTexture()` |
| Sidebar HUD | `textures/gui/sidebar/*` | `SidebarPanel.texture()` |
| Hearts (partial) | `gui/heart_*.png`, `hearts/burst_sheet.png` | `StatusTab`, `HeartBurstOverlay`; **no vanilla heart-bar replacer** |
| Entities | `textures/entity/*` | `*Renderer.TEXTURE` constants |
| Quasar FX | `quasar/emitters/*.json` | `S2CQuasarPayload`, `QuasarSpawner`, gameplay systems |
| Pinwheel/Veil | `pinwheel/post/*`, shaders | `VeilPostController`, `BorderFxRenderer` |
| Sounds | `sounds/**/*.ogg`, `sounds.json` | `EclipseSounds`, cutscene JSON `sound` events |
| Items/blocks | models, blockstates, item/block textures | Registries + model JSON chains |
| Cutscenes | `cutscenes/*.json` | `CutscenePaths`, `CutsceneService.play()` |
| Data pack | `data/eclipse/*`, `data/minecraft/*` | Dimension/recipe/loot/tag JSON + Java loaders |

Full per-file list omitted (see inventory tables above).

## UNREFERENCED

**0 files** on disk with no detected reference.

_None — every on-disk asset under audit paths is referenced directly or via model/datapack chains._

## MISSING

Paths referenced in Java/JSON or documented in `docs/ASSET_MANIFEST_V2.md` but absent or at wrong path.

| Expected path | Referenced from | Issue |
|---|---|---|
| `assets/eclipse/textures/block/altar.png` | block model — altar | File not found |
| `assets/eclipse/textures/gui/hearts/heart_cracked.png` | docs/ASSET_MANIFEST_V2.md Batch B | Not generated; no Java HUD reference yet — custom heart bar not implemented |
| `assets/eclipse/textures/gui/hearts/heart_full.png` | Manifest vs code path split | Manifest expects gui/hearts/; StatusTab uses textures/gui/heart_full.png (9×9 placeholder at different path) |
| `assets/eclipse/textures/gui/hearts/heart_empty.png` | Manifest vs code path split | Same as heart_full — exists at textures/gui/heart_empty.png |

## GENERATED-BUT-NOT-INSTALLED

| Artifact path | Size | Intended purpose (inferred) |
|---|---:|---|
| `/opt/cursor/artifacts/assets/eclipse_event_logo.png` | 1.32 MB | Event/marketing logo — not installed under `assets/eclipse/`; candidate for title screen replacement or docs |

### Manifest paths not at exact on-disk path

| Manifest path | Notes |
|---|---|
| `assets/eclipse/textures/gui/hearts/heart_full.png` | See MISSING — code uses alternate `textures/gui/heart_*.png` paths |
| `assets/eclipse/textures/gui/hearts/heart_empty.png` | See MISSING — code uses alternate `textures/gui/heart_*.png` paths |
| `assets/eclipse/textures/gui/hearts/heart_cracked.png` | Never generated |
| `assets/eclipse/textures/item/compass_of_watcher.png` | Animated items use `*_00..31` frame strips instead of base name |
| `assets/eclipse/textures/item/grave_dowser.png` | Animated items use `*_00..31` frame strips instead of base name |

## PLACEHOLDER-SUSPECTS

Programmer-art / silent-audio candidates (intentional per manifest until final art drop).

| Path | Size | Dims | Reason |
|---|---:|---|---|
| `assets/eclipse/sounds/ui/hover.ogg` | 3.5 KB | — | OGG <4KB (3602 B) |
| `assets/eclipse/sounds/ui/tab.ogg` | 3.9 KB | — | OGG <4KB (3981 B) |
| `assets/eclipse/sounds/ui/typewriter.ogg` | 3.5 KB | — | OGG <4KB (3572 B) |
| `assets/eclipse/textures/block/altar_bottom.png` | 166 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/block/altar_side.png` | 172 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/block/altar_top.png` | 175 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/block/grave.png` | 131 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/block/grave_side.png` | 109 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/entity/eclipsed_player.png` | 995 B | 64×64 | low bytes for dimensions |
| `assets/eclipse/textures/entity/sunmote.png` | 205 B | 32×32 | tiny/small PNG |
| `assets/eclipse/textures/entity/the_other.png` | 549 B | 64×64 | low bytes for dimensions |
| `assets/eclipse/textures/gui/heart_empty.png` | 332 B | 9×9 | tiny/small PNG |
| `assets/eclipse/textures/gui/heart_full.png` | 401 B | 9×9 | tiny/small PNG |
| `assets/eclipse/textures/gui/sidebar/panel.png` | 451 B | 64×64 | tiny/small PNG |
| `assets/eclipse/textures/gui/title/button.png` | 254 B | 200×20 | tiny/small PNG |
| `assets/eclipse/textures/gui/title/button_highlighted.png` | 232 B | 200×20 | tiny/small PNG |
| `assets/eclipse/textures/gui/title/wisp.png` | 1.1 KB | 32×32 | low bytes for dimensions |
| `assets/eclipse/textures/item/arm_artifact.png` | 155 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_00.png` | 199 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_01.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_02.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_03.png` | 189 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_04.png` | 185 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_05.png` | 192 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_06.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_07.png` | 187 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_08.png` | 189 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_09.png` | 185 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_10.png` | 187 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_11.png` | 184 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_12.png` | 186 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_13.png` | 193 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_14.png` | 199 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_15.png` | 195 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_16.png` | 196 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_17.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_18.png` | 201 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_19.png` | 194 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_20.png` | 189 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_21.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_22.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_23.png` | 182 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_24.png` | 185 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_25.png` | 187 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_26.png` | 195 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_27.png` | 193 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_28.png` | 193 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_29.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_30.png` | 205 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/compass_of_watcher_31.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/ferryman_toll.png` | 167 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_00.png` | 199 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_01.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_02.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_03.png` | 188 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_04.png` | 185 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_05.png` | 192 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_06.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_07.png` | 187 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_08.png` | 189 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_09.png` | 185 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_10.png` | 187 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_11.png` | 184 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_12.png` | 186 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_13.png` | 193 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_14.png` | 199 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_15.png` | 195 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_16.png` | 196 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_17.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_18.png` | 201 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_19.png` | 194 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_20.png` | 191 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_21.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_22.png` | 190 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_23.png` | 182 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_24.png` | 185 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_25.png` | 187 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_26.png` | 195 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_27.png` | 193 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_28.png` | 193 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_29.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_30.png` | 205 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/grave_dowser_31.png` | 197 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/heart_fragment.png` | 135 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/herald_core.png` | 172 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/heralds_lure.png` | 157 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/revive_sigil.png` | 132 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/umbral_blade.png` | 119 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/umbral_pick.png` | 139 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/umbral_shard.png` | 145 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/item/vitae_shard.png` | 131 B | 16×16 | tiny/small PNG |
| `assets/eclipse/textures/particle/purple_wisp.png` | 145 B | 8×8 | tiny/small PNG |

### Duplicated textures (identical MD5)

- **6×** `assets/eclipse/textures/gui/title/panorama_0.png`, `assets/eclipse/textures/gui/title/panorama_1.png`, `assets/eclipse/textures/gui/title/panorama_2.png`, `assets/eclipse/textures/gui/title/panorama_3.png`, `assets/eclipse/textures/gui/title/panorama_4.png`, `assets/eclipse/textures/gui/title/panorama_5.png`

## DIVERGENT-CUTSCENES

`run/config/eclipse/cutscenes/` vs bundled `assets/eclipse/cutscenes/`.

| Filename | Bundled | Config copy |
|---|---:|---:|
| `unlock_ring.json` | 1.0 KB | 1.4 KB |

Only `unlock_ring.json` differs in this workspace — config copy is larger (likely hand-edited keyframes). Re-copy bundled default or export/sync intentionally.

## Prioritized integration recommendations (top 10)

| # | Asset / system | Suggested usage site |
|---:|---|---|
| 1 | `textures/gui/hearts/heart_cracked.png` (+ full/empty 36×36) | Implement custom heart bar renderer (`docs/ASSET_MANIFEST_V2.md` Batch B); hook into `HeartsService` / `HeartBurstOverlay` layer |
| 2 | Relocate or dual-bind `textures/gui/heart_{full,empty}.png` → `gui/hearts/` | Align with manifest + future HUD; update `StatusTab` paths |
| 3 | `/opt/cursor/artifacts/assets/eclipse_event_logo.png` | Copy to `textures/gui/title/logo.png` or handbook hero if replacing placeholder logo |
| 4 | Custom cursor PNGs (`gui/cursor/*`) | Already referenced in `CursorManager` — verify `HandbookScreen` calls `CursorManager.endFrame()` each frame |
| 5 | Handbook hero/tab art (6×2 PNGs) | Wired via `HandbookTab.icon()` / `hero()` — if blank in-game, debug render scissor/alpha not missing files |
| 6 | Title parallax + panorama | Wired in `EclipseTitleScreen`; **panorama_0..5 are identical files** (placeholder cube — replace with 6 distinct faces) |
| 7 | `unlock_burst` quasar emitter | Wired in `AnnouncementOverlay` on unlock announcements — test milestone unlock flow |
| 8 | `map_expand_materialize` emitter | Wired in `RingGrowthService` — verify ring expansion column FX |
| 9 | `unlock_ring.json` cutscene divergence | Sync `run/config` copy with bundled resource or document operator override |
| 10 | UI sound placeholders (`hover/tab/typewriter.ogg` <4KB) | Replace with final chimes per manifest Sounds section |