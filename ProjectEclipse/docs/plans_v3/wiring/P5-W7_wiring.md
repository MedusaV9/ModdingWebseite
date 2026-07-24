# P5-W7 wiring notes (Xbox world pipeline)

W7 ships **no Java code** — no `EclipseMod.java` lines, no DeferredRegisters, no
payloads. Everything below is hand-off/context for W1, W8, W9, W11 and the
orchestrator.

## Deviation from the plan file list (orchestrator-directed)

The plan (§3 P5-W7) listed `devtools/xbox/XboxWorldBaker.java` +
`devtools/xbox/RegionPaletteScanner.java` (`/dev xboxevent bake <world>`, perm 3)
and `scripts/xbox_fetch.sh` / `scripts/XBOX_WORLD_PREP.md`. Per the worker
instructions, the pipeline was instead built as **reproducible offline Python**
under `tools/xboxworlds/` (README there = the prep doc). Consequences:

* **W1/W9**: do NOT seed a `DevCommandDoc` for `xboxevent.bake` as a runnable
  command; if the handbook should mention it, mark it "offline tool:
  `tools/xboxworlds/run_all.py`" (or drop the entry — orchestrator's call).
* `/dev xboxevent reset <world>` (W9) is unaffected.

## Commit gate (orchestrator)

Measured, deterministic staged sizes (sha256s also inside
`assets/eclipse/xboxworlds/manifest.json` and `/workspace/xbox_staging/manifest.json`):

| zip | bytes | sha256 |
|---|---|---|
| `/workspace/xbox_staging/tu1.zip` | 6,598,826 | `9e04f097ae736e476cd1a5ed47e1ba55e415ff4ff39824146917eac43707687a` |
| `/workspace/xbox_staging/tu12.zip` | 6,539,810 | `015d60bbf756251d3fcfff2c1dbfe15dbf61618146de8d07f23dbdd1277a696f` |
| `/workspace/xbox_staging/tu14.zip` | 6,560,905 | `3071a02ef77e53d9580f9bb254fcd404fe85726b55b2307d440e46ee7ef455a9` |
| **total** | **19,699,541 (18.79 MiB)** | ≤ 30 MB budget ✔ |

After approval: copy the three zips to
`src/main/resources/assets/eclipse/xboxworlds/` (next to the committed
`manifest.json`; sha256 must match it — the installer verifies at extract time).
No other change needed; manifest/loot/palette JSONs are already committed.

## For P5-W8 (classic blocks)

* Authoritative block list: `docs/plans_v3/xbox_palette.json` — **156 distinct
  vanilla ids** across tu1/tu12/tu14 with counts, per-world breakdown, and every
  property VALUE occurring in the baked palettes. Zero unmapped entries; the
  mapping is total by construction (`minecraft:<path>` → `eclipse:classic_<path>`).
* `classic_water` / `classic_lava` must be registered **without blockstate
  properties** (bake collapses `level=*`); `waterlogged` is always `"false"` in
  the baked data, so waterloggable vanilla base classes are safe (default state
  matches — no fluid exists in the baked worlds).
* Property sets must match vanilla (they do automatically when extending the
  vanilla base classes, plan §2.14 shape kinds). Watch the property-rich ones:
  `tripwire`, `brown/red_mushroom_block`, `cobblestone_wall`, `fire`, `vine`,
  fences/panes/stairs/doors.

## For P5-W9 (event runtime)

* `assets/eclipse/xboxworlds/manifest.json` (committed) — schema per plan
  §2.13.1 step 5 **plus** `bounds` and `chunkCount`. `displayName` en/de strings
  are embedded; equivalent lang keys are provided in the W7 langdrop
  (`eclipse.xboxworld.<id>.name`) if the title screen prefers translatables —
  keep them consistent.
* Zip layout (frozen): `region/*.mca`, optional `entities/*.mca`, `level.dat`
  at archive root → extract straight into `<world>/dimensions/eclipse/xbox_<id>/`.
  `level.dat` is dev-client sugar; the installer may skip or ignore it.
* Loot: `data/eclipse/xboxworlds/<id>_loot.json` — containers keyed by pos,
  items in the vanilla `ItemStack` JSON codec shape (decode via
  `ItemStack.CODEC` + `JsonOps`); ids are ORIGINAL vanilla ids (music discs stay
  vanilla per §2.14; block items may be classic-mapped at spill time with W8's
  registry). TU12 contains 18 music-disc containers (the disc quest).
* Spawns (verified standable against baked blocks): tu1 `(-4, 70, -36)`,
  tu12 `(97, 72, -106)`, tu14 `(97, 72, -106)`; `spawnYaw 0.0` for all three.
* Worlds ship with **no light data / no heightmaps** (`isLightOn` absent) —
  first chunk load relights; harmless, but don't be surprised by first-entry
  light engine work. All chunks are `minecraft:full`, DataVersion 3955; entity
  chunks may carry 3839 (game DFUs entity chunks at load — vanilla-supported).
* Dimension type must stay `min_y 0, height 256` (§2.13.2) — sections outside
  0..15 were trimmed away.
* Item frames keep their vanilla contained items (decorative souvenirs on
  walls); only paintings/item frames/glow frames exist as entities.

## For P5-W11 (CREDITS.md / credits.json)

Add under "tutorial worlds" (plan §2.20 wording):

> Xbox-360 Tutorial Worlds (TU1, TU12, TU14) — worlds by **Mojang / 4J Studios**;
> Java Edition conversions courtesy of **theminecraftarchitect.com**
> (https://theminecraftarchitect.com/tutorial-worlds). Additional archive
> reference: Fridtjof-DE/Minecraft-Xbox-360-Tutorial-Worlds (GitHub). Used in a
> private, non-commercial community event; no standalone re-hosting.

Tooling note (no credit strictly required, keep for transparency): worlds were
upgraded with the official vanilla 1.21.1 `server.jar --forceUpgrade`
(Mojang piston-data; local tool only, not redistributed).

## Verification summary (details in `/workspace/xbox_staging/reports/`)

* DataVersion: 2916/2916 region chunks + level.dat = **3955** per world
  (upgrade_report.json histograms).
* Palette: zero `minecraft:` ids left in baked palettes except
  `minecraft:air` (cave/void air never occurred); 68/127/151 distinct classic
  ids per world; spot-check NBT dumps in the reports.
* Re-bake idempotent: identical zip sha256s across two full runs.
* Structural: vanilla 1.21.1 server booted an identity-mapped bake of tu12
  (same pipeline, no rename) and loaded/re-saved spawn chunks with **zero**
  chunk errors — proves region format, whitelisted chunk NBT, forced-full
  status and relight path. The `eclipse:` ids themselves resolve once W8's
  blocks exist (bake acceptance item "opens in a dev client with classic
  terrain" is deferred to the W8+W9 integration wave).
