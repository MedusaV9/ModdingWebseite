# Xbox Tutorial Worlds — era authenticity & provenance (C17)

What the Xbox-event dimensions ship, where every asset comes from, and what a
true 1:1 console look still needs from the server owner. Companion docs:
`tools/xboxworlds/README.md` (world pipeline), `docs/plans_v3/xbox_palette.json`
(frozen 156-id classic block contract), `tools/classicblocks/provenance.json`
(per-texture provenance ledger).

## Bundled worlds (7)

| id | display name | origin |
|---|---|---|
| `tu1` | Tutorial World (TU1) — 2012 | TMA "JE Latest" conversion, baked by `tools/xboxworlds/` (fetch → DFU upgrade → trim → bake) |
| `tu12` | Tutorial World (TU12) — 2012 | same pipeline |
| `tu14` | Tutorial World (TU14) — 2013 | same pipeline |
| `tu19` | Tutorial World (TU19) — 2014 | DERIVED from `tu12` by `tools/xboxworlds/variants.py` |
| `tu31` | Tutorial World (TU31) — 2015 | derived, see below |
| `tu69` | Tutorial World (TU69) — 2018 | derived, see below (V5 request; 30×30 trim) |
| `tu75` | Tutorial World (TU75) — 2019 | derived, see below |

**Why TU19/TU31/TU69/TU75 are derived:** theminecraftarchitect.com hosts no
Java conversions for them (probed 404), and more full bakes would blow the
30 MB size gate. The 4J tutorial map itself did not change layout across these
title updates — so each variant reuses the TU12 layout trimmed to the inner
36×36 chunks (~3.1 MB each; `tu69` uses a tighter 30×30 trim ≈ 2.2 MB because
the gate had ~2.3 MB of headroom left when it was added — all 7 zips total
≈ 29.9 MiB, within the gate) with a deterministic **era-aging palette pass**
(every remap stays inside the frozen classic palette contract):

* `tu19` (2014): ~18 % of cobblestone mossed, ~10 % of stone bricks cracked —
  the map after two years of title updates.
* `tu31` (2015): ~30 % of oak planks rebuilt in spruce, stone-brick patches in
  the cobble, ferns in the grass — the renovation era.
* `tu69` (2018): the aquatic-preview twilight — ~34 % cobble moss, ~20 % stone
  bricks mossed, ~34 % ferns, ~12 % of sand gone gravelly (the Update-Aquatic
  era beach read), poppies displacing dandelions.
* `tu75` (2019): heavy moss (~40 % cobble, ~25 % stone bricks), overgrowth
  ferns, poppies — the last Xbox-360 title update; the world nobody resets.

Regenerate with `python3 tools/xboxworlds/variants.py` then
`python3 tools/xboxworlds/frames.py` (both deterministic; manifest + loot JSONs
are rewritten in place). Note on TU numbering: TU75 is the real final Xbox-360
update; TU19/TU31 are the nearest real neighbours of the originally requested
mid-era updates, and TU69 (a real ~2018 title update, never archived as a Java
conversion) was added on explicit request in the V5 wave.

## Block/item texture provenance (what is authentic, what is recreated)

The era look ships WITHOUT any Mojang-copyrighted texture bytes. Ledger:
`tools/classicblocks/provenance.json` (229 entries).

* **~205 textures** — copied (190) or tint-baked (15) from the MIT-licensed
  resource pack *"Minecraft: Classic Edition"* by JS03
  (https://modrinth.com/resourcepack/minecraft-classic-edition, license
  verified via the Modrinth API; sha512 pinned in the ledger).
* **3 procedural era recreations** — `grass_block_side`, `cobblestone`,
  `oak_planks` (`tools/classicblocks/procedural_era.py`, seeded + byte-stable).
  The MIT pack targets the 2009 *Classic* look; these three read most wrong for
  the 2012-era console worlds, so they are re-authored numerically in the
  X360-era palette (bright uneven grass lip, chunky high-contrast cobble
  stones, flat golden 4-px plank rows). No Mojang bytes are copied.
* **Remainder** — drawn/derived placeholders per the ledger (`drawn`,
  `palette-sampled`, sized entries).
* **Classic HUD skin** — `hotbar_classic`, `hotbar_selection_classic`,
  `heart_container_classic`, `heart_full_classic`, `heart_half_classic` under
  `textures/gui/xbox/` are original procedural art
  (`tools/art/gen_xbox_hud.py`), styled after the era's chunky gray hotbar and
  uncompressed hearts.

**True 1:1 era textures need the user's own legacy pack.** The authentic
pre-1.14 (console-era) textures are Mojang-copyrighted and cannot be
redistributed by this mod. If you own a legitimate legacy texture pack (e.g.
extracted from your own copy via a tool like the "Programmer Art" pack or a
console-edition rip), drop its block textures over
`assets/eclipse/textures/block/classic/` at resource-pack level — the classic
blocks resolve textures by name, no code changes needed. Keep
`provenance.json` in sync if you rebake the shipped set.

## Era immersion stack (client, dimension-gated, reducedFx-safe)

* **Console-era filter** — `client/xbox/XboxEraFx` + the
  `eclipse:xbox_era` Veil post pipeline (saturation lift, X360 gamma S-curve,
  warm cast, 4:3-era vignette hint). Eases over 30 ticks; `reducedFx` (or an
  Iris pack) disables the row entirely.
* **Classic HUD skin** — `client/xbox/XboxHudSkin` swaps hotbar + hearts for
  the classic textures inside the dims (cancels the vanilla layers, keeps
  `leftHeight` bookkeeping for the layers above).
* **One timer** — `client/hud/XboxTimerLayer` renders the event countdown in
  the day-timer slot (`DayTimerLayer` yields); the server bossbar is deleted.
* **Old music** — `client/xbox/XboxEraSounds` schedules the C418 *Volume
  Alpha* in-game tracks (`eclipse:music.xbox_era` — a sounds.json pool of
  VANILLA `music/game/*` files, nothing bundled) with era-style gaps; the
  custom `xbox_nostalgia` bed (C19) plays as intro and between tracks.
* **Old sounds** — same class remaps, only inside the dims:
  `block.netherrack.*`/`block.nether_bricks.*` → `block.stone.*` (both got
  bespoke sounds in 1.16; era consoles used stone sounds) and `ambient.cave` →
  `eclipse:ambient.xbox_cave` (cave1–13, the pre-1.13 set). The famous old
  "oof" and pre-1.10 grass steps were REMOVED from vanilla assets and stay
  gone — restoring them would require bundling copyrighted audio.
* **Quests/XP off** — `skills/XpGates.isEventDimension` covers all xbox dims
  (XP), `progression/goals/QuestEngine.increment` drops quest-goal signals
  inside them.

## Display frames & chest loot

Chest loot is the ORIGINAL baked tutorial-world chest content (period-correct
by construction; music discs stay vanilla as playable souvenirs, block items
spill classic-mapped). Item frames are a C17 addition: `frames.py` scans each
committed zip for solid classic walls near spawn and writes 8 era-museum
frames (iron sword, diamond, clock, disc, bread, compass …) into each
`<id>_loot.json`; `XboxWorldInstaller.decorate` hangs them at event start,
idempotent via the `eclipse_xbox_frame` entity tag.

Functionality note: baked `classic_water`/`classic_lava` are deliberately
SOLID deco blocks (zero fluid in the payload). Fresh VANILLA water/lava and
redstone remain fully functional inside the dims — covered by the
`fluidsAndRedstoneClockWorkInTuWorld` gametest.
