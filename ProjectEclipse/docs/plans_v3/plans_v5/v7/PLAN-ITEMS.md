# PLAN-ITEMS — Custom Item Upgrade Pass (plans v7)

**Planner:** PLAN-ITEMS (one of the v7 parallel planners). **Scope:** EVERY custom item —
icon quality, 3D (GeckoLib/Blockbench-format) upgrade candidacy, glint/rarity/tooltip
hygiene, and held/first-person transforms. Split into three disjoint worker packages
(ITEMS-A / ITEMS-B / ITEMS-C).

**Workers: this document is the complete specification. Read §0 (conventions) before
touching any file. Ownership is disjoint — the files-owned matrices in §4 are
authoritative; never edit a file another package owns.**

---

## 0. Conventions & references (all FROZEN, read before coding)

- **GeckoLib item flow** — mirror the shipped wand pilot exactly. Contract doc:
  `docs/plans_v3/handoff/P6_geckolib_conventions.md` (paths verified against GeckoLib
  4.9.2). Item asset triple: `geo/item/<id>.geo.json` +
  `animations/item/<id>.animation.json` + textures under `textures/item/<folder>/`
  (per-item folder, e.g. `textures/item/wand/`); `models/item/<id>.json` is
  `builtin/entity` + hand-tuned `display` blocks (copy `models/item/eclipse_wand.json`
  as the starting point — it is the only tuned example).
- **Java pattern** — `wand/EclipseWandItem` (implements `GeoItem`, `base` controller
  loops `idle`, `action` controller holds triggerable one-shots, server-side
  `triggerAnim` via `SingletonGeoAnimatable.registerSyncedAnimatable(this)` in the
  constructor); renderer = `client/wand/EclipseWandRenderer` (`GeoItemRenderer` +
  `DefaultedItemGeoModel` + `AutoGlowingGeoLayer` for `_glowmask.png`); registration =
  `client/wand/WandClientExtensions` (`IClientItemExtensions#getCustomRenderer`).
- **Icon style contract** — `scripts/item_art/eclipse_palette.py`: flat mid-tone shapes,
  shared `finish()` pass (2px black-purple edge, 3-tone shading, protected 1px glow
  accents), palette mirrors the frozen `EclipseUiTheme` tokens (ACCENT `#B98CFF`,
  ACCENT_DEEP `#7B4FD0`, PANEL `#120B1E`, …) plus the registered secondary ramps
  (bone/parchment, crimson/vitae, herald gold, ferryman soul-teal). Deterministic
  reruns. Every icon change goes through a painter script (new or existing) —
  **never hand-edit committed PNGs**.
- **Geo validation** — run `scripts/geckolib_gen/validate_geo.py` on every new/changed
  geo file. `.bbmodel` project files may be committed next to geo files.
- **Lang** — new keys ship as a langdrop (`docs/plans_v3/langdrop/ITEMS-<A|B|C>.json`,
  en+de maps) — do NOT edit `en_us.json`/`de_de.json` directly (integrator merges;
  32/32 key parity currently holds and must be preserved).
- **Bone naming** — root bone `root`; emissive-only geometry under bones prefixed
  `glow_` (the painter + `AutoGlowingGeoLayer` rely on it); animation minimum for items:
  `idle` loop + relevant one-shots. Texture canvases 64×64 (wand precedent).
- **Baked lore pattern** — `DataComponents.LORE` at registration with a translatable
  key, as `storm_heart` already does (`EclipseItems` line ~162). One line, ≤ 8 words,
  en+de.

---

## 1. Inventory & per-item verdict

Icon metrics measured from the committed PNGs (opaque-color count / canvas coverage /
luminance range). The on-style family sits at **8–21 colors, lum 15–244** (that is the
`finish()` fingerprint); outliers are called out.

### 1.1 `registry/EclipseItems.java`

| # | Item | Class / props | Icon today | Verdict | Pkg |
|---|---|---|---|---|---|
| 1 | `grave` | `BlockItem` (admin) | 3D block render (`parent eclipse:block/grave`) | **keep-3D-block-icon** — verify only | C |
| 2 | `heart_fragment` | `Item`, glint, common | 8 colors, dim (lum max 169) | **keep-2D-polish** (brighten highlight; +UNCOMMON, +lore) | B |
| 3 | `heart_extractor` | `HeartExtractorItem`, 60t SPEAR channel, durability 4, UNCOMMON | 14 colors, handheld | **3D-upgrade** — syringe/heart-tap geo, plunger channel anim | A |
| 4 | `glitch_shard` | `Item`, EPIC, glint | 9 colors, on-style | **keep-2D-polish** (minor; +lore) | B |
| 5 | `umbral_shard` | `UmbralShardItem` (currency) | 14 colors, on-style | **keep-2D-polish** (+lore) | B |
| 6 | `compass_of_watcher` | `WatcherCompassItem`, `angle` predicate | 32-frame needle wheel, on-style | **keep-2D-polish** — the frame wheel IS the needle spin (§2.2); regen frames | C |
| 7 | `grave_dowser` | `GraveDowserItem`, `angle` predicate | 32-frame wheel | **keep-2D-polish** (same rationale) | C |
| 8 | `vitae_shard` | `VitaeShardItem`, 32t use, RARE, glint | 14 colors, on-style | **keep-2D-polish** (+lore) | B |
| 9 | `umbral_pick` | `PickaxeItem`, UmbralTier | 16 colors, `item/handheld` | **keep-2D-polish** (tool feel + real enchants; +RARE) | C |
| 10 | `umbral_blade` | `SwordItem`, UmbralTier | 12 colors, `item/handheld` | **keep-2D-polish** (+RARE) | C |
| 11 | `revive_sigil` | `ReviveSigilItem`, glint | 11 colors | **3D-upgrade** — rune-disc geo, glyph glowmask pulse, ritual trigger (+RARE) | B |
| 12 | `heralds_lure` | `HeraldsLureItem`, glint | 21 colors | **3D-upgrade** — shard cage + pulsing heart-fragment core, offering trigger (+RARE) | B |
| 13 | `herald_core` | `Item`, EPIC, glint, stacks 16 | 12 colors | **keep-2D-polish** (stackable trophy; +lore, glint → off §2.3) | B |
| 14 | `ferryman_toll` | `Item`, EPIC, glint, stacks 16 | 9 colors | **keep-2D-polish** (+lore, glint → off) | B |
| 15 | `fog_core` | `Item`, EPIC, glint, stacks 16 | **158 colors, off-palette, no painter script** — worst icon in the set | **keep-2D-REDRAW** via new painter (+lore, glint → off) | B |
| 16 | `fog_cloak_trim` | `Item`, EPIC, glint, stacks 1 | **25 colors, soft contrast (46–223), no painter** | **keep-2D-redraw** via new painter (+lore, glint → off) | B |
| 17 | `storm_heart` | `Item`, EPIC, glint, baked lore | 14 colors, on-style | **3D-upgrade** — caged rotating core + lightning-arc glow bones (glint → off) | B |
| 18 | `altar` | `BlockItem` (admin) | 3D block render | **keep-3D-block-icon** — verify only | C |
| 19 | `arm_artifact` | `ArmArtifactItem`, EPIC, glint, fireproof, slot-locked hotbar 8 | 12 colors (severed arm + ledger-light) | **3D-upgrade** — held/worn severed-arm geo, ledger-glow idle pulse, open-ledger flick (glint → off) | A |

### 1.2 `wand/WandItems.java` + satellites

| # | Item | Registered in | Icon today | Verdict | Pkg |
|---|---|---|---|---|---|
| 20 | `eclipse_wand` | `WandItems`, EPIC | **geo item EXISTS** (64×64 ×4 path textures + glowmasks, 5 anims, tuned transforms) | **3D-improve** — richer geo, use-anim reaches ornament bones, glow/transform pass | A |
| 21 | `wizard_catalyst` | `entity/wizard/WizardEntities`, EPIC | **101 colors** — `ImageDraw` anti-aliasing leaks through `finish()` | **keep-2D-polish** — flatten to ≤ 20 colors in its painter | C |
| 22 | `display_wand` | `devtools/display/DevToolItems` (op-only) | 14 colors, on-style | **keep-2D** — verify only (dev tool) | C |
| 23 | `respawn_door` | `limbo/door/DoorRegistry` `BlockItem` (admin) | **borrows `minecraft:item/dark_oak_door` sprite** | **keep-2D, custom icon** (purple seam door sprite) | C |
| 24 | `pale_*` (8 block items) | `registry/PaleGardenBlocks` | block-model parents (3D) except `pale_hanging_moss` sprite (57 colors, lum 135–200, weak) | **keep as-is**; polish only the `pale_hanging_moss` sprite | C |
| 25 | `classic_*` (~170 gen. block items) + 10 hand sprites in `textures/item/classic/` | `classicblocks/*` (generated — `tools/classicblocks/gen_assets.py`) | vanilla-twin look (deliberate Xbox nostalgia) | **out of scope for redraw** — audit-only pass (§3.C6); never fight the generator | C |
| 26 | `almond_water`, `yellow_wallpaper`, `eclipses_favor`, `supply_beacon` | NOT items — renamed vanilla stacks (`backrooms/BackroomsMaze`, `economy/ShardEconomy`) | n/a | **out of scope** (no assets to own) | — |

---

## 2. Assessment detail

### 2.1 Icon quality

The generated set (`scripts/item_art/gen_shards|relics|trackers|umbral_tools|b8_items|
storm_heart|display_wand.py`) is coherent: shared outline ink, 3-tone shading, palette
locked to `EclipseUiTheme`. Defects found:

- `fog_core.png` / `fog_cloak_trim.png` — **no painter scripts exist**; the PNGs are
  gradient-heavy (158 / 25 colors), miss the 2px edge, and sit off-palette. They are the
  only two icons that visibly do not belong to the family. Fix: new
  `scripts/item_art/gen_fog_relics.py` painting both in the DIM/HAIRLINE fog-grey ramp +
  soul-teal glow accents, `finish()` applied.
- `wizard_catalyst.png` — has a painter but uses `PIL.ImageDraw` ellipses → 101 colors of
  AA fuzz. Fix: repaint flat (put()-based) in the same gold/eclipse design, ≤ 20 colors.
- `heart_fragment.png` — reads muddy at gui scale 2 (max luminance 169 vs family's 244).
  Fix: SCARLET rim-light pass in `gen_b8_items.py`.
- `pale_hanging_moss.png` — low contrast (135–200), 22% coverage; silhouette nearly
  invisible on the handbook panel. Fix: darken strand cores toward `#575044`.
- Everything else: silhouettes read at 16px, keep with at most parameter-level tweaks.

### 2.2 3D candidacy rules applied

**Upgrade when** the item is a hero/ceremony piece the player stares at (held in
first-person during a channel, presented at the altar, displayed as a trophy) and an
idle/use animation adds felt value. **Stay 2D when** the item is a stackable
currency/ingredient (geo BER cost per gui cell, and sprites read better in lists), a
vanilla-feel tool (enchant glint + `item/handheld` expectations), or already solved by a
better vanilla mechanism:

- `compass_of_watcher` / `grave_dowser`: the shipped 32-frame `angle` predicate wheel
  (`client/EclipseClient` + `CompassItemPropertyFunction`) already delivers a smooth,
  server-synced needle spin in every context including gui — a GeckoLib needle would
  re-implement lodestone math in a renderer for zero visible gain. Deliberately
  **rejected** for 3D; polish the frames instead.
- `umbral_pick`/`umbral_blade`: real enchantable tools; keep vanilla handheld pipeline.
- Trophy stackables (`herald_core`, `ferryman_toll`, `fog_core`, `fog_cloak_trim`,
  shards, `heart_fragment`): stay 2D sprites.
- Upgrades: `eclipse_wand` (exists — improve), `arm_artifact`, `heart_extractor`
  (60-tick channel begs a plunger anim), `revive_sigil`, `heralds_lure`, `storm_heart`
  (finale trophy worth an item-frame showpiece).

### 2.3 Glint / rarity / tooltip rules (single source of truth — implemented by ITEMS-B in `EclipseItems.java`)

**Glint discipline (recommended rule):** glint = "charged consumable/ritual fuel".
Trophies and geo-upgraded items drop `ENCHANTMENT_GLINT_OVERRIDE` (they get custom
icons/glowmasks + rarity color instead) — this kills the current "glint soup" where 12
items all shimmer identically in the handbook.

| Item | Rarity now → target | Glint now → target | Lore/tooltip key (new unless noted) |
|---|---|---|---|
| heart_fragment | common → **UNCOMMON** | on → on | `item.eclipse.heart_fragment.lore` |
| heart_extractor | UNCOMMON (keep) | off (keep) | `item.eclipse.heart_extractor.lore` |
| glitch_shard | EPIC (keep) | on → on | `item.eclipse.glitch_shard.lore` |
| umbral_shard | common (keep — currency) | off (keep) | `item.eclipse.umbral_shard.lore` |
| compass_of_watcher | common → **UNCOMMON** | off | `item.eclipse.compass_of_watcher.lore` |
| grave_dowser | common → **UNCOMMON** | off | `item.eclipse.grave_dowser.lore` |
| vitae_shard | RARE (keep) | on → on | `item.eclipse.vitae_shard.lore` |
| umbral_pick / umbral_blade | common → **RARE** | off (enchants provide it) | `item.eclipse.umbral_pick/.umbral_blade.lore` |
| revive_sigil | common → **RARE** | on → on (ritual fuel) | `item.eclipse.revive_sigil.lore` |
| heralds_lure | common → **RARE** | on → on (ritual fuel) | `item.eclipse.heralds_lure.lore` |
| herald_core / ferryman_toll / fog_core / fog_cloak_trim | EPIC (keep) | on → **off** | `.lore` each |
| storm_heart | EPIC (keep) | on → **off** | `item.eclipse.storm_heart.lore` (EXISTS — keep) |
| arm_artifact | EPIC (keep) | on → **off** (geo glow replaces it) | `item.eclipse.arm_artifact.tooltip` (EXISTS — keep) |
| eclipse_wand | EPIC (keep) | off (keep; dynamic tooltip exists) | keep `wand.eclipse.tooltip.*` |
| wizard_catalyst | EPIC (keep — owned by `WizardEntities`, see seam §5) | off | `item.eclipse.wizard_catalyst.lore` |

Lore lines are baked at registration via `DataComponents.LORE` (storm_heart pattern),
one italic-grey line each, en+de via langdrop.

**Geo + foil caveat:** `GeoItemRenderer` renders foil from `ItemStack#hasFoil` — after
the geo upgrades, verify no double-shimmer with `AutoGlowingGeoLayer`; the table above
already turns glint off for every geo item except none (wand/artifact/extractor/sigil/
lure/storm_heart all end glint-off or ritual-fuel-on-2D).

### 2.4 Transforms

Only `models/item/eclipse_wand.json` carries hand-tuned display blocks today; all 2D
items ride vanilla `item/generated`/`item/handheld` defaults (correct). Every NEW geo
item ships its own `builtin/entity` model JSON with all 8 display blocks tuned (gui /
firstperson L+R / thirdperson L+R / ground / fixed / head), starting from the wand's
values. Acceptance requires screenshots per perspective (§4).

---

## 3. Per-item work specs

### Hero pieces (ITEMS-A)

**A1 — `eclipse_wand` improve (geo exists).**
Geo (`geo/item/eclipse_wand.geo.json`): sculpt the shared base — taper the shaft (split
the single 2×7×2 cube into 2–3 tapering segments with a 2° counter-twist), add a 1px
bark-wrap cube on the handle, keep ALL frozen bone names (`root`, `handle`, `shaft`,
`knot`, `tip`, `p_<path>_s<1..3>`, `glow_*`) — `EclipseWandRenderer.preRender` hides
`p_<path>_s<n>` by name and MUST keep working. Anims
(`animations/item/eclipse_wand.animation.json`): `use` currently only kicks `root`+`tip`
— add per-path ornament reaction (riss shards flare outward, glut flames stretch, stern
points scatter) since hidden bones animating is free; keep `idle`, `levelup`, `awaken`,
`stall` names frozen (`EclipseWandItem.ANIM_*`). Textures: contrast pass on the four
64×64 paths + glowmasks via `scripts/geckolib_gen/items/eclipse_wand.py` (rim-light the
knot, brighten rune lines in `_glowmask`). Transforms: nudge gui scale 0.62 → ~0.70 so
the wand fills its slot like the 2D family does; re-verify first-person.

**A2 — `arm_artifact` 3D upgrade.**
New geo `geo/item/arm_artifact.geo.json` (64×64 canvas, painter
`scripts/geckolib_gen/items/arm_artifact.py`): a severed forearm (bone/parchment ramp,
crimson stump ring) whose palm cups a floating ledger-light mote (`glow_ledger` bone,
ACCENT purple in `_glowmask`). Bones: `root`, `forearm`, `hand`, `fingers`,
`glow_ledger`, `glow_stump`. Anims: `idle` loop (mote orbit + 0.5px bob, slow finger
curl every ~6s), triggerable `open` (fingers splay, mote flares — fired server-side when
the ledger opens, `triggerWandAnim` pattern) and `deny` (short shake — fired on the
slot-lock refusing a move, only if a server hook already exists; otherwise skip `deny`,
do NOT add new slot-lock hooks). Java: `ArmArtifactItem` implements `GeoItem` (wand
boilerplate); `models/item/arm_artifact.json` → `builtin/entity` + tuned displays (held
= forearm along the player's own arm axis — the "worn/held look"). Old 16×16 sprite
stays on disk (harmless, `gen_relics.py` untouched — B owns it).

**A3 — `heart_extractor` 3D upgrade.**
New geo `geo/item/heart_extractor.geo.json` (64×64, painter
`scripts/geckolib_gen/items/heart_extractor.py`): a brass-and-glass heart-tap — needle
cube, glass chamber (`glow_vitae` fill bone, DANGER crimson glowmask), thumb-ring
plunger (`plunger` bone). Anims: `idle` (chamber glow breathing), `channel` loop
(plunger draws back over ~3s, vitae fill scales up — matches
`HeartExtractorItem.USE_DURATION_TICKS` = 60), triggerable `extract` (snap-finish flash,
fired from `finishUsingItem`) and `refuse` (shake, fired from the existing `refuse()`
path). Java: `HeartExtractorItem` implements `GeoItem`; keep `UseAnim.SPEAR` (arm pose)
— the geo `channel` loop is driven by an `AnimationController` predicate on
`LivingEntity#isUsingItem` for the holder (client-side check in the controller, wand
conventions). `models/item/heart_extractor.json` → `builtin/entity` + displays.

### Shards / sigils / cores (ITEMS-B)

**B1 — `storm_heart` 3D upgrade.** New geo (64×64): slate cage (4 curved rib cubes)
around a rotating inner core cube (`glow_core`, TEXT-white/ACCENT), 2–3 thin
`glow_arc_*` planes that flicker via keyframed scale 0↔1 (lightning arcs). Anims: `idle`
loop only (core rotation + arc flickers, staggered so item frames desync nicely). No
use anim (it is a trophy). New class `ritual/StormHeartItem` (plain `Item` + `GeoItem`;
keeps the baked LORE component), registration swap in `EclipseItems`. Painter
`scripts/geckolib_gen/items/storm_heart.py`. Old sprite retires from the model.

**B2 — `heralds_lure` 3D upgrade.** New geo: 4 obsidian shard prongs (corona-glass
black-purple) caging a floating heart-fragment core (`glow_core`, CRIMSON→GOLD
glowmask). Anims: `idle` (core pulse ~1.2s + slow prong counter-rotation), triggerable
`offering` (prongs open, core surges — fired from `HeraldsLureItem`'s altar-use success
path server-side). `HeraldsLureItem` implements `GeoItem`.

**B3 — `revive_sigil` 3D upgrade.** New geo: flat octagonal rune tablet (2px thick,
bone/parchment ramp) with an engraved glyph on both faces (`glow_glyph`, ACCENT purple).
Anims: `idle` (glyph glow pulse + 1px hover-bob), triggerable `ritual` (tablet spins up
and over-glows — fired when the altar consumes it). `ReviveSigilItem` implements
`GeoItem`. `fixed` display tuned so item frames show the full face (it will hang on
sanctum walls).

**B4 — fog relic redraws (2D).** New `scripts/item_art/gen_fog_relics.py` →
`fog_core.png` (condensed storm knot: DIM/HAIRLINE fog-grey swirl body, single SOUL_TEAL
lightning glint, `finish()`), `fog_cloak_trim.png` (folded mantle cut: layered grey-purple
drape, 1px TEXT clasp). Both ≤ 20 colors, silhouette-first.

**B5 — sprite polish (2D).** `gen_b8_items.py`: heart_fragment rim-light (SCARLET, lum
parity with family), glitch_shard: keep, optional 1px magenta/cyan fringe check.
`gen_shards.py`: umbral/vitae — parameter-only tweaks if any. `gen_relics.py`:
herald_core/ferryman_toll — leave art, no changes needed beyond regen determinism check.

**B6 — registry hygiene (sole owner of `EclipseItems.java`).** Apply the ENTIRE §2.3
table: rarity bumps (incl. ITEMS-C's compass/dowser/pick/blade — C does NOT touch this
file), glint drops, baked `LORE` components for every listed item, registration swaps
for B1–B3 classes. Ship `docs/plans_v3/langdrop/ITEMS-B.json` with all new `.lore` keys
(en+de) including the ones for A- and C-package items (single langdrop keeps lore voice
consistent; A/C langdrops carry only their non-lore keys).

### Tools / trackers / misc / block items (ITEMS-C)

**C1 — tracker frame regen.** `gen_trackers.py`: bump needle contrast (TEXT tip pixel),
dial rim-light; regenerate all 64 frames + verify the two override chains still resolve
(`models/item/compass_of_watcher*.json`, `grave_dowser*.json` untouched).

**C2 — umbral tools polish.** `gen_umbral_tools.py`: edge-light the pick head / blade
edge (1px TEXT), keep silhouettes; regen 2 PNGs.

**C3 — `wizard_catalyst` flatten.** Rewrite `gen_wizard_catalyst.py` drawing with
`put()` rectangles/discs instead of `ImageDraw` AA ellipses; same design (gold orb,
eclipse crescent bite, flare spikes), ≤ 20 colors, `finish()`.

**C4 — `respawn_door` custom icon.** New painter `scripts/item_art/gen_respawn_door_icon.py`
→ `textures/item/respawn_door.png` (dark door slab, ACCENT `#B98CFF` glowing seam +
glyphs — matches the 128×128 block texture's identity); repoint
`models/item/respawn_door.json` `layer0` from `minecraft:item/dark_oak_door` to
`eclipse:item/respawn_door`.

**C5 — pale + display polish.** `pale_hanging_moss.png` contrast pass (needs a new
painter entry — add to `gen_respawn_door_icon.py`'s script or a small
`gen_misc_sprites.py`; keep one file). `display_wand.png`: verify only (regen to confirm
determinism; art is fine).

**C6 — audits (no art changes).** (a) `grave`/`altar` BlockItem 3D gui renders:
screenshot at gui scale 2; only if unreadable, add a `gui` display override in
`models/item/grave.json`/`altar.json` (C owns both). (b) `textures/item/classic/`
10 sprites: confirm they match their vanilla twins' silhouettes (they are deliberate
nostalgia twins — do NOT restyle to the eclipse palette); log findings in the final
message. (c) generated `classic_*` family: explicitly untouched.

---

## 4. Worker packages (disjoint files)

Effort: S ≤ 3 files, M 4–10, L > 10.

### ITEMS-A — hero pieces (wand improve + artifact + extractor) — **L**

| Owns | Files |
|---|---|
| Java | `artifact/ArmArtifactItem.java`, `ritual/HeartExtractorItem.java` |
| Client (new pkg `client/item/`) | `package-info.java`, `ArmArtifactRenderer.java`, `HeartExtractorRenderer.java`, `ItemsAClientExtensions.java` |
| Client (existing) | `client/wand/EclipseWandRenderer.java` (improvements only) |
| Assets | `geo/item/eclipse_wand.geo.json`, `geo/item/arm_artifact.geo.json`, `geo/item/heart_extractor.geo.json`; matching `animations/item/*.animation.json` (3); `textures/item/wand/*` (8 PNG), new `textures/item/artifact/arm_artifact.png|_glowmask.png`, new `textures/item/extractor/heart_extractor.png|_glowmask.png`; `models/item/eclipse_wand.json`, `models/item/arm_artifact.json`, `models/item/heart_extractor.json` |
| Scripts | `scripts/geckolib_gen/items/eclipse_wand.py`, `scripts/geckolib_gen/items/arm_artifact.py`, `scripts/geckolib_gen/items/heart_extractor.py` |
| Lang | `docs/plans_v3/langdrop/ITEMS-A.json` (non-lore keys only, if any) |

Acceptance: validate_geo green on 3 geos; clips/screens of (1) wand idle+use per path in
first person, gui slot fill; (2) artifact held look third+first person, `open` trigger on
ledger open; (3) extractor 60t channel with plunger draw + `extract` snap; (4) all 8
display blocks screenshot per item; (5) no `EclipseItems.java` edits (rarity/lore is B's).

### ITEMS-B — shards / sigils / cores + registry hygiene — **L**

| Owns | Files |
|---|---|
| Java | `registry/EclipseItems.java` (SOLE owner — §2.3 table), `ritual/ReviveSigilItem.java`, `ritual/HeraldsLureItem.java`, new `ritual/StormHeartItem.java` |
| Client | `client/item/ReviveSigilRenderer.java`, `client/item/HeraldsLureRenderer.java`, `client/item/StormHeartRenderer.java`, `client/item/ItemsBClientExtensions.java` |
| Assets | `geo/item/revive_sigil|heralds_lure|storm_heart.geo.json` + matching `animations/item/*` (3); new `textures/item/sigil/*`, `textures/item/lure/*`, `textures/item/stormheart/*` (png+glowmask each); `models/item/revive_sigil.json`, `heralds_lure.json`, `storm_heart.json`; regenerated `textures/item/fog_core.png`, `fog_cloak_trim.png`, `heart_fragment.png`, (`glitch_shard.png`, `umbral_shard.png`, `vitae_shard.png` if touched) |
| Scripts | `scripts/geckolib_gen/items/revive_sigil.py`, `heralds_lure.py`, `storm_heart.py`; new `scripts/item_art/gen_fog_relics.py`; `scripts/item_art/gen_b8_items.py`, `gen_shards.py`, `gen_relics.py` |
| Lang | `docs/plans_v3/langdrop/ITEMS-B.json` (ALL `.lore` keys en+de, incl. A/C items) |

Acceptance: validate_geo green ×3; clips of sigil pulse + ritual trigger at the altar,
lure offering trigger, storm_heart item-frame showcase (arc flicker desync across 3
frames); before/after grid of every regenerated sprite at 400%; rarity-color + lore
tooltip screenshot per §2.3 row; glint visibly gone on the five trophies; de/en parity.

### ITEMS-C — tools / trackers / misc / block items — **M**

| Owns | Files |
|---|---|
| Assets | `textures/item/compass_of_watcher_00..31.png`, `grave_dowser_00..31.png`, `umbral_pick.png`, `umbral_blade.png`, `wizard_catalyst.png`, new `textures/item/respawn_door.png`, `pale_hanging_moss.png`, (`display_wand.png` regen-verify); `models/item/respawn_door.json`; `models/item/grave.json` + `altar.json` (only if C6a fails) |
| Scripts | `scripts/item_art/gen_trackers.py`, `gen_umbral_tools.py`, `gen_wizard_catalyst.py`, `gen_display_wand.py`, new `scripts/item_art/gen_misc_sprites.py` (respawn_door icon + pale moss) |
| Lang | `docs/plans_v3/langdrop/ITEMS-C.json` (usually empty — keep file with empty maps) |

Acceptance: compass/dowser needle sweep clip (all 32 frames cycle in-world); tool icons
before/after; catalyst color count ≤ 20 verified by the §1 metric script; respawn_door
icon no longer the vanilla sprite; classic/grave/altar audit findings in final message.
No Java files owned — rarity changes for C's items land via B.

**Scheduling:** all three fully parallel (zero shared files). Integrator merges the three
langdrops into `en_us.json`/`de_de.json` last.

---

## 5. Seams & risks

- **`wizard_catalyst` rarity/lore** lives in `entity/wizard/WizardEntities.java` — owned
  by no package here (frozen W4-WIZARD file). Its `.lore` key ships in ITEMS-B's
  langdrop; the one-line `.component(LORE, …)` addition to `WizardEntities` is a
  **wiring ask** for the integrator (`docs/plans_v3/wiring/` note, one line).
- **Geo-item gui cost:** 6 geo items total (wand + 5 new) render through the BER path in
  gui cells (handbook, EMI, inventory). Wand precedent shows this is fine; if the
  handbook's collections grid ever lists trophies en masse, storm_heart is the only geo
  stackable — acceptable.
- **`GeoItem` on stackables:** `GeoItem.getOrAssignId` writes a stack component on first
  server render-trigger; storm_heart/lure/sigil stack sizes stay as registered — triggers
  are fired per-player-held stack only (wand precedent), no dupe-id risk.
- **Slot-lock `deny` anim (A2)** is opportunistic — only wire it if
  `artifact/ArtifactSlotLock` already exposes a refusal hook; adding new hooks is out of
  scope.
- **Do not** rename any registry id, bone that `EclipseWandRenderer` toggles, or anim
  name in `EclipseWandItem.ANIM_*` / `EclipseGeoAnimations` — all frozen.
- **Painter determinism** is a shipped guarantee (byte-identical reruns) — every new
  painter must keep it (no randomness).

## 6. Frozen new ids/paths introduced by this plan

- Geo triples: `geo/item/{arm_artifact,heart_extractor,revive_sigil,heralds_lure,storm_heart}.geo.json`
  (+ same-name animation files; anim namespaces `animation.<id>.*`).
- Texture folders: `textures/item/{artifact,extractor,sigil,lure,stormheart}/`.
- New class: `ritual/StormHeartItem`. New client package: `client/item/`.
- Lang keys: `item.eclipse.<id>.lore` for every §2.3 row marked new.
- Scripts: `scripts/geckolib_gen/items/{arm_artifact,heart_extractor,revive_sigil,heralds_lure,storm_heart}.py`,
  `scripts/item_art/{gen_fog_relics,gen_misc_sprites}.py`.
