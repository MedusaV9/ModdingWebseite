# Xbox-360 Tutorial World Pipeline (P5-W7)

Reproducible, offline pipeline that produces the three bundled Xbox-360 tutorial
world payloads for the Eclipse Xbox event (plan `docs/plans_v3/P5_devtools_xbox_bundling.md`
§2.13.1 + §2.14): **fetch → upgrade → trim → bake → package/manifests**.

Pure Python 3.10+ stdlib (no pip deps) + Java 21 (only to run the official
vanilla server jar as the DFU upgrade tool). Never run at player runtime.

> Plan deviation (orchestrator-directed): the plan sketched an in-mod
> `/dev xboxevent bake` command (`devtools/xbox/XboxWorldBaker.java`) plus
> `scripts/xbox_fetch.sh`. This directory replaces both with offline Python -
> same inputs, same frozen outputs, no game required. See
> `docs/plans_v3/wiring/P5-W7_wiring.md`.

## TL;DR

```bash
cd ProjectEclipse/tools/xboxworlds
python3 run_all.py                 # fetch + upgrade + bake + package (all 3 worlds)
python3 run_all.py --worlds tu12   # single world
python3 run_all.py --skip-fetch --skip-upgrade   # re-bake/re-package only
```

Stages (each is independently re-runnable):

| # | Script | What it does | Output |
|---|---|---|---|
| 1 | `fetch.py` | Downloads the three TMA "JE Latest" zips (sha256-pinned in `worlds.json`) + the official vanilla 1.21.1 `server.jar` (sha1-verified via Mojang's version manifest). `--pin` records fresh hashes. | `/tmp/xboxworlds/downloads/` |
| 2 | `upgrade.py` | Extracts each zip, prunes to `level.dat` + `region/` + `entities/` (drops DIM-1/DIM1/poi/player junk), then runs `java -jar server.jar --forceUpgrade --nogui` (one DFU hop 3839→3955), stops the server right after `Done`, verifies DataVersions. | `/tmp/xboxworlds/upgraded/<id>/` |
| 3 | `bake.py` | TRIM + BAKE: chunk purge, section/field stripping, palette remap to `eclipse:classic_*`, chest-loot extraction + block-entity blanking, entity strip (paintings/item frames only), spawn verification. Deterministic output. | `/tmp/xboxworlds/baked/<id>/` + reports |
| 4 | `package.py` | Deterministic zips + all manifests; enforces the ≤30 MB size gate report. | `/workspace/xbox_staging/` + repo manifests |

Helper: `inspect_nbt.py` (`level` / `chunk` / `palette` / `block` / `dvhist`
sub-commands) for NBT spot checks without any game runtime.

## Frozen contracts (consumed by P5-W8 / P5-W9)

* **Classic naming scheme** (`mclib/palette.py`, mirrors plan §2.14):
  `minecraft:<path>` → `eclipse:classic_<path>`, state properties preserved
  verbatim. Exceptions: `minecraft:air|cave_air|void_air` pass through;
  `minecraft:water|lava[level=*]` collapse to **propertyless**
  `eclipse:classic_water|classic_lava` (FLUID_SOLID); `waterlogged` is forced
  to `"false"` everywhere (zero fluid in the baked dimensions). Any
  non-`minecraft:` palette id fails the bake loudly.
* **Palette report for W8**: `docs/plans_v3/xbox_palette.json` - every distinct
  vanilla id in the shipped worlds with counts, per-world breakdown and every
  property VALUE used. Classic blocks must declare identical property sets
  (vanilla base classes provide them).
* **World zips** (staged in `/workspace/xbox_staging/`, committed to
  `src/main/resources/assets/eclipse/xboxworlds/<id>.zip` only after the
  orchestrator size gate): entries `region/r.X.Z.mca`, `entities/r.X.Z.mca`
  (optional), `level.dat` at archive root - extract directly into
  `<world>/dimensions/eclipse/xbox_<id>/`. `level.dat` exists only so the baked
  world opens in a dev client; the installer may ignore it.
* **Mod manifest**: `src/main/resources/assets/eclipse/xboxworlds/manifest.json`
  `{worldId, displayName{en_us,de_de}, zip, spawn[x,y,z], spawnYaw, dataVersion,
  sha256, sizeBytes, chunkCount, bounds, lootManifest}` per world (plan §2.13.1
  step 5 schema + bounds).
* **Loot manifests**: `src/main/resources/data/eclipse/xboxworlds/<id>_loot.json`
  - container positions + items in the **vanilla `ItemStack` JSON codec shape**
  (`{"id","count","components"}`), decodable with `ItemStack.CODEC` + `JsonOps`.
  Ids are the original vanilla ids; W9 decides at spill time what stays vanilla
  (music discs = playable souvenirs) vs maps to classic items.

## What the bake does to each chunk (details)

* Keeps chunks with status ≥ `initialize_light` and forces `minecraft:full`
  (old console conversions surface as `minecraft:spawn` after DFU - terrain is
  complete, light is stripped/relit anyway). Earlier statuses are dropped.
* Purge box: chunks with `InhabitedTime == 0` outside the ±27-chunk box around
  the **world footprint center** are dropped, plus any all-air chunk anywhere.
  (Plan wrote "radius from spawn"; TU12's spawn sits ~6 chunks off-center and
  the literal rule would slice built map edge - intent is "drop empty OUTER
  chunks" of the 864×864 map. Documented deviation.)
* Drops sections outside Y 0..15 (dimension_type `xbox_classic` is `min_y 0,
  height 256`); refuses silently losing non-air content (reported per chunk).
* Strips: `Heightmaps`, light arrays + `isLightOn` (relit on first load),
  `structures`, `PostProcessing`, `UpgradeData`, `blending_data`,
  `below_zero_retrogen`; empties `block_ticks`/`fluid_ticks`/`block_entities`;
  `yPos` = 0. Chunk NBT is rebuilt from a whitelist - nothing else survives.
* Entity chunks: only `minecraft:painting`, `minecraft:item_frame`,
  `minecraft:glow_item_frame` survive; wrappers keep the SOURCE DataVersion
  (vanilla `--forceUpgrade` rewrites entity chunks only when DFU changed them;
  the game DFUs entity chunks at load - `DataFixTypes.ENTITY_CHUNK`).
* Block entities: any BE with `Items` (chests etc.) or `RecordItem` (jukeboxes)
  is recorded in the loot manifest, then ALL BEs are blanked (classic blocks
  have no block entities, plan §2.14).
* `level.dat`: spawn re-verified against the baked blocks (feet/head passable,
  solid floor; Y auto-adjusted if obstructed - reported), `allowCommands=1` for
  dev-client convenience, embedded `Player` tag removed.

Determinism: same inputs ⇒ byte-identical region files and zips (sorted chunk
order, zlib-9, zeroed region timestamps, gzip `mtime=0`, fixed zip dates).
Verified: re-running bake+package reproduces identical zip sha256s.

## `--forceUpgrade` notes (plan risk R6)

* The 1.21.1 server upgrades **and then boots**; `upgrade.py` watches for
  `Done (` and immediately sends `stop`. Transient run dir:
  `/tmp/xboxworlds/server/` (bundler `libraries/` extraction is shared across
  runs; per-world logs `upgrade_<id>_world.log` kept there).
* `upgrade.py` writes `eula.txt` with `eula=true`: running it constitutes
  accepting the Minecraft EULA (https://aka.ms/MinecraftEULA). The server jar
  is used strictly as a local upgrade tool and is never redistributed.
* The brief boot runs at `difficulty=peaceful`, `view-distance=3`, port 25599,
  offline mode; only the ~25 spawn chunks tick for a few seconds (bake strips
  mobs anyway).
* Expected outcome per world: all 2916 region chunks + `level.dat` at
  DataVersion **3955**; entity chunks may legitimately keep 3839 (see above).
* The `key missing: DragonFight` ERROR line during boot is a benign vanilla
  complaint about the converted `level.dat` (server injects defaults).

## Sources & licenses (for CREDITS.md - keep in sync with the wiring note)

| What | Source | License / note |
|---|---|---|
| TU1 / TU12 / TU14 tutorial worlds ("JE Latest" zips, DataVersion 3839) | `https://downloads.theminecraftarchitect.com/tutorial-worlds/TU{1,12,14}%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip` (linked from https://theminecraftarchitect.com/tutorial-worlds) | Worlds are **Mojang / 4J Studios** copyrighted content; Java conversions courtesy of **theminecraftarchitect.com** (no explicit license). Private-event use, full credit, no standalone re-hosting; this pipeline does NOT claim legal clearance (plan §5 R5). sha256 pins in `worlds.json`. |
| Fallback world source | https://github.com/Fridtjof-DE/Minecraft-Xbox-360-Tutorial-Worlds | 1.13.2-era conversions (DataVersion 1631), TU12-13 missing, no LICENSE file; needs a two-hop upgrade. Cloned at `/tmp/xbox-tutorial-worlds` during research. |
| Fallback mirror | https://www.curseforge.com/minecraft/worlds/console-edition-tutorial-worlds | manual download only. |
| Vanilla 1.21.1 `server.jar` (DFU tool) | Mojang piston-data via `https://piston-meta.mojang.com/mc/game/version_manifest_v2.json` | Minecraft EULA; local tool only, never redistributed, sha1-verified. |

## Troubleshooting

* A TMA URL dies → all direct links are embedded in the site's JS bundle; grep
  `https://downloads.theminecraftarchitect.com/tutorial-worlds/` out of the
  bundle referenced by https://theminecraftarchitect.com/tutorial-worlds, update
  `worlds.json`, re-run `fetch.py --pin`. Otherwise use the fallback sources
  above (two-hop upgrade: any old JE version → run the matching vanilla server
  chain, or open once in 1.20.6 then this pipeline).
* Bake fails with `unmapped non-vanilla palette id` → the source world was
  touched by a modded tool; clean the source or extend the exception list in
  `mclib/palette.py` (coordinate with P5-W8 - the id list is a frozen contract).
* Size gate exceeded → fallback ladder per plan R2: tighten `trimChunkRadius`,
  drop to 2 worlds, then 1 (tu12), then move zips out of the jar into a
  first-boot download.
