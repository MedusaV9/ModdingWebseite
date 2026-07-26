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
| `tu69` | Tutorial World (TU69) — 2018 | derived, see below (V5 request) |
| `tu75` | Tutorial World (TU75) — 2019 | derived, see below |

**Why TU19/TU31/TU69/TU75 are derived:** theminecraftarchitect.com hosts no
Java conversions for them (probed 404), and more full bakes would blow the
30 MB size gate.

**TUT2 rework — "the tutorial worlds are all the same".** The first cut derived
all four variants from the SAME inner box around the TU12 footprint centre and
copied TU12's spawn verbatim, so every era loaded identical terrain seen from an
identical spawn view; the only difference was a sparse palette recolour that
never touched a surface block (`tu12` and `tu19` rendered PIXEL-IDENTICAL from
above). Each variant now takes its **own 26×26-chunk window** of the 864×864
map — a different corner with a different biome mix, height profile and skyline
— plus an auto-verified spawn inside that window, an era pass that also rewrites
**surface** blocks and tree species, and an **era biome remap** (biome drives
sky/fog/water colour, so the worlds read differently the moment you arrive).
Every remap target stays inside the frozen 156-id classic palette contract.

| id | window (chunks) | region | spawn | era read |
|---|---|---|---|---|
| `tu19` | x −18..7, z −26..−1 | north shore, the plains/swamp coast holding the tutorial build | −56, 88, −120 | the "only oaks" world: every birch/spruce/jungle tree oaked, cobble lightly mossed, first cracked stone bricks |
| `tu31` | x −27..−2, z 0..25 | south-west dune sea + desert outpost | −280, 84, 264 | renovation era: spruce-plank rebuilds, stone-brick patches, grass creeping back to sand in blotches, dead bushes; savanna/desert sky |
| `tu69` | x 1..26, z −20..5 | east highlands, the windswept hill coast | 232, 63, −120 | aquatic-preview twilight: spruce stands on half the hills, gravel beaches, deep moss and ferns, poppies; cool ocean sky |
| `tu75` | x 0..25, z 1..26 | south-east taiga/jungle border | 172, 75, 240 | console sunset: heavy moss, snowed-over ground, iced-over water; snowy biome sky |

The three BASE worlds keep their full authentic 54×54-chunk map. `tu1` is a
genuinely different download; `tu12` and `tu14` are not — TU14 is the console's
TU12 map after a content update, ~79 % of its surface columns still render
identically, and `package.py` had derived the SAME spawn (97, 72, −106) for
both. `variants.py` therefore also **re-anchors** the TU14 spawn (`BASE_RESPAWN`)
into the densest TU12↔TU14 delta region, ~390 blocks away, so the two open on
different landmarks. Manifest-only: the committed TU14 zip bytes (and its
sha256) are untouched.

Regenerate with `python3 tools/xboxworlds/variants.py` then
`python3 tools/xboxworlds/frames.py` (both deterministic; manifest + loot JSONs
are rewritten in place). Note on TU numbering: TU75 is the real final Xbox-360
update; TU19/TU31 are the nearest real neighbours of the originally requested
mid-era updates, and TU69 (a real ~2018 title update, never archived as a Java
conversion) was added on explicit request in the V5 wave.

## Block/item textures — the era is a COLOUR FILTER, not a texture pack (TUT2)

The mod used to bundle ~220 hand-made "retro" `eclipse:block/classic/*` and
`eclipse:item/classic/*` PNGs plus 5 `textures/gui/xbox/*` HUD sheets. They are
**deleted**. Recreated retro textures never looked like the console era, they
fought every resource pack the player already had, and they cost ~1 MB of jar
for the privilege. The era is now carried entirely by a **client-side colour
grade** (see the era stack below).

What remains bundled: **13 block + 1 item texture** — the geometry sheets that
have no vanilla block-texture counterpart because vanilla renders those blocks
as entities or from an entity atlas (`chest_*`, `ender_chest_*`, `red_bed_sheet`
/ `red_bed`, `sign_oak`, `skull_*`). Everything else in the classic block set
now points at `minecraft:block/<name>` / `minecraft:item/<name>`, which means a
player's own legacy/console texture pack applies to the classic blocks with no
extra steps. Ledger: `tools/classicblocks/provenance.json`; regenerate the
models with `python3 tools/classicblocks/gen_assets.py` and check with
`python3 tools/classicblocks/validate.py`.

Deleted along with the textures: `client/xbox/XboxHudSkin` (the retro hotbar +
hearts overlay), `tools/art/gen_xbox_hud.py`,
`tools/classicblocks/procedural_era.py` and
`tools/classicblocks/import_textures.py`.

## Era immersion stack (client, dimension-gated, reducedFx-safe)

* **Console-era filter** — `client/xbox/XboxEraFx` + the
  `eclipse:xbox_era` Veil post pipeline (saturation lift, X360 gamma S-curve,
  soft 720p resolve, saturation bloom, 4:3-era vignette hint, slow scan band).
  Eases over 30 ticks; `reducedFx` (or an Iris pack) disables the row entirely.
* **PER-ERA colour grade (TUT2)** — on top of the shared filter, every world
  gets its own tint / saturation / contrast / vignette row from
  `xboxevent/XboxEraProfile`, fed as the `EraTint`, `EraSaturation`,
  `EraContrast` and `EraVignette` uniforms and eased on the same 30-tick curve,
  so a portal hop straight from one tutorial world to another crossfades between
  the two looks. This is what replaced the deleted retro textures.

  | id | look | reads as (a flat 50 % grey comes out at) |
  |---|---|---|
  | `tu1` 2012 | ALPHA | vivid green, washed blacks, heavy vignette — `(121,162,95)` |
  | `tu12` 2012 | ALPHA | the same green, one step calmer — `(129,151,110)` |
  | `tu14` 2013 | BETA | warm amber cast, blue pulled down — `(160,143,98)` |
  | `tu19` 2014 | BETA | warm but lighter, contrast returning — `(152,142,115)` |
  | `tu31` 2015 | RELEASE_EARLY | neutral with a contrast boost — `(134,134,134)` |
  | `tu69` 2018 | RELEASE_LATE | faintly cool, clean, almost no vignette — `(130,134,141)` |
  | `tu75` 2019 | SUNSET | cool desaturated dusk — `(126,132,144)` |

  The tint numbers are FITTED, not eyeballed: the shared grade already carries a
  warm mid-tone LUT, so a literal `1,1,1` would still render warm and
  "neutral early release" would be indistinguishable from the beta rows.
  `/dev xboxevent status` names the running world's look.
* **One timer** — `client/hud/XboxTimerLayer` renders the event countdown in
  the day-timer slot (`DayTimerLayer` yields); the server bossbar is deleted.
* **Old music (TUT2: ONE voice)** — `client/xbox/XboxEraSounds` is a pure
  SCHEDULER. It owns no sound instance; it answers `xboxCue()` with
  `XBOX_ERA_TRACK` (the C418 *Volume Alpha* pool `eclipse:music.xbox_era` — a
  sounds.json pool of VANILLA `music/game/*` files, nothing bundled), with the
  custom `xbox_nostalgia` bed (C19) that fills the era-style gaps, or with
  `null` for the 40-tick hand-over silence between them. `music/MusicManager`
  plays that answer on its single managed voice, so both xbox cues share one
  rung and the old one is at zero before the new one starts.

  Before TUT2 the track was streamed on a PARALLEL `SoundManager` channel at
  full volume while the bed was still fading out on the managed one — two music
  voices for two seconds on every hand-over, plus a hard `soundManager.stop()`
  on the way out that bypassed the MUSICFADE envelope. That was the reported
  "music overlaps in the tutorial worlds". Both `MusicManager` and the scheduler
  also reset on `ClientPlayerNetworkEvent.Clone`, because `Minecraft.setLevel`
  runs `SoundEngine.stopAll()`: the voices a hop leaves behind are dead
  references and must not be waited on (or "resumed") in the new world.
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
