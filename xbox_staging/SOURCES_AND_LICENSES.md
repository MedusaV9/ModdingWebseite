# Xbox tutorial world payloads — sources & licenses (P5-W7)

Staged by `ProjectEclipse/tools/xboxworlds/` (fetch → upgrade → trim → bake →
package). Binaries wait here for the orchestrator's size-gate approval before
being copied to `src/main/resources/assets/eclipse/xboxworlds/` (plan §3 P5-W7
commit gate; ladder R2 if ever over budget).

## Staged payloads

| file | bytes | sha256 |
|---|---|---|
| `tu1.zip` | 6,598,826 | `9e04f097ae736e476cd1a5ed47e1ba55e415ff4ff39824146917eac43707687a` |
| `tu12.zip` | 6,539,810 | `015d60bbf756251d3fcfff2c1dbfe15dbf61618146de8d07f23dbdd1277a696f` |
| `tu14.zip` | 6,560,905 | `3071a02ef77e53d9580f9bb254fcd404fe85726b55b2307d440e46ee7ef455a9` |

Total **19,699,541 bytes (18.79 MiB)** — within the ≤30 MB budget. Zips are
deterministic; re-baking identical inputs reproduces these hashes exactly.

## Sources (downloaded 2026-07-23)

| item | URL | integrity | license note |
|---|---|---|---|
| TU1 world ("JE Latest", DataVersion 3839) | https://downloads.theminecraftarchitect.com/tutorial-worlds/TU1%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip | sha256 `206e49ca4f8dae07bb21427f280ad03cf81419593c6a61b155722f268ae09f7a` (12,677,984 B) | Worlds © Mojang / 4J Studios; Java conversion courtesy of theminecraftarchitect.com (no explicit license). Private event use, credited, no re-hosting — plan §5 R5 documents that NO legal clearance is claimed. |
| TU12 world (planner's verified download, re-used from /tmp) | https://downloads.theminecraftarchitect.com/tutorial-worlds/TU12%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip | sha256 `ebe10f2c20bd757e8d6b0fdcab0ba08c3f0b06bafcdb99af68a0ff2b81821d1a` (12,516,355 B) | same |
| TU14 world | https://downloads.theminecraftarchitect.com/tutorial-worlds/TU14%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip | sha256 `0f558e2d3635651183e3ed8cf81d5083dd3e15a9cef33c30f0956061d252c83a` (12,913,151 B) | same |
| Vanilla 1.21.1 server.jar (DFU upgrade tool only) | https://piston-data.mojang.com/v1/objects/59353fb40c36d304f2035d51e7d6e6baa98dc05c/server.jar (resolved via piston-meta version_manifest_v2) | sha1 `59353fb40c36d304f2035d51e7d6e6baa98dc05c` (official, 51,627,615 B) | Minecraft EULA (https://aka.ms/MinecraftEULA) accepted for local tool runs; jar is NOT redistributed and NOT part of any payload. |
| (fallback, unused) Fridtjof-DE GitHub conversions | https://github.com/Fridtjof-DE/Minecraft-Xbox-360-Tutorial-Worlds | clone at /tmp/xbox-tutorial-worlds | 1.13.2-era conversions, TU12-13 missing, no LICENSE file. |
| (fallback, unused) CurseForge mirror | https://www.curseforge.com/minecraft/worlds/console-edition-tutorial-worlds | — | manual download only. |

CREDITS.md wording for W11: see `docs/plans_v3/wiring/P5-W7_wiring.md`.

## Contents

* `<id>.zip` — baked world payload (`region/*.mca`, `entities/*.mca`,
  `level.dat`); extract into `<world>/dimensions/eclipse/xbox_<id>/`.
* `manifest.json` — copy of the committed mod manifest
  (`assets/eclipse/xboxworlds/manifest.json`).
* `<id>_manifest.json` — per-world detail: spawn (+ verification trace),
  bounds, stats, full block-id inventory (vanilla id → classic id → count).
* `reports/` — upgrade DataVersion histograms, bake reports, loot + palette
  reports, `xbox_palette.json` copy, upgrade server log tails.
