"""P5-W8 — Classic blocks manifest (single source of truth).

Every ``eclipse:classic_*`` block ships from this list:
  * tools/classicblocks/import_textures.py  -> bundles textures from the MIT
    "Minecraft: Classic Edition" resource pack (Modrinth, author JS03)
  * tools/classicblocks/gen_assets.py       -> blockstates / models / item models /
    loot tables / tags / langdrop / ClassicBlockList.java
  * tools/classicblocks/validate.py         -> consistency + JSON validation

Naming scheme (FROZEN, shared with P5-W7's region baker):
  vanilla ``minecraft:<path>``  ->  ``eclipse:classic_<path>`` (same path, same
  blockstate properties). W7 bakes region palettes against exactly these ids.

Display names: en "Classic — <Vanilla Name>", de "Klassisch — <German name>".

Shapes are the JAVA registration kinds (see ClassicBlockShapes). ``model`` is the
asset-generation kind. ``mirror`` names the vanilla blockstate whose (purely
functional) state->rotation table gen_assets.py remaps onto our models.
"""

# ---------------------------------------------------------------------------
# fixed classic-era colorization constants (no runtime BlockColors handlers:
# grayscale pack textures are pre-colorized at import time -> flat, old-school
# single-tone foliage, which is exactly the period look we want)
# ---------------------------------------------------------------------------
COLORS = {
    "GRASS": (0x91, 0xBD, 0x59),      # classic plains grass green
    "FOLIAGE": (0x48, 0xB5, 0x18),    # oak/jungle foliage default
    "SPRUCE": (0x61, 0x99, 0x61),
    "BIRCH": (0x80, 0xA7, 0x55),
    "LILY": (0x20, 0x80, 0x30),
    "STEM_GREEN": (0x4C, 0xB4, 0x28),
    "STEM_RIPE": (0xE0, 0xC7, 0x1C),
    "RED_DUST": (0x8B, 0x00, 0x00),   # unpowered-era dark dust red
}

# ---------------------------------------------------------------------------
# texture build plan: OUT name (under assets/eclipse/textures/block/classic/)
#   -> op spec. Default op for names not listed here: straight copy of the
#      same-named texture from the pack's block/ folder.
# ops:
#   copy:<pack block name>          plain copy under a different name
#   item:<pack item name>           copy from the pack's item/ folder
#   tint:<pack block name>:<COLOR>  grayscale multiply with COLORS[...]
#   tint_item:<pack item name>:<COLOR>
#   grass_side / chest_front / chest_side / chest_top / water / lava_frame0 /
#   redstone_dot                    procedural derivations (see import script)
# ---------------------------------------------------------------------------
TEXTURE_OPS = {
    "grass_block_top": "tint:grass_block_top:GRASS",
    "grass_block_side": "grass_side",           # side + overlay x GRASS
    "grass_block_snow": "copy:grass_block_snow",
    "oak_leaves": "tint:oak_leaves:FOLIAGE",
    "spruce_leaves": "tint:spruce_leaves:SPRUCE",
    "birch_leaves": "tint:birch_leaves:BIRCH",
    "jungle_leaves": "tint:jungle_leaves:FOLIAGE",
    "short_grass": "tint:grass:GRASS",           # pack still uses pre-1.20.3 name
    "fern": "tint:fern:GRASS",
    "vine": "tint:vine:FOLIAGE",
    "lily_pad": "tint:lily_pad:LILY",
    "pumpkin_stem": "tint:pumpkin_stem:STEM_GREEN",
    "melon_stem": "tint:melon_stem:STEM_GREEN",
    "attached_pumpkin_stem": "tint:attached_pumpkin_stem:STEM_RIPE",
    "attached_melon_stem": "tint:attached_melon_stem:STEM_RIPE",
    "redstone_dust_line0": "tint:redstone_dust_line0:RED_DUST",
    "redstone_dust_line1": "tint:redstone_dust_line1:RED_DUST",
    "redstone_dust_overlay": "copy:redstone_dust_overlay",
    "redstone_dust_dot": "redstone_dot",         # derived blob from tinted line
    "water_still": "water",                      # procedural (pack has none)
    "lava_still": "lava_frame0",                 # frame 0 of the animation strip
    "chest_front": "chest_front",                # derived from oak_planks (pack
    "chest_side": "chest_side",                  # has entity-chests only; old
    "chest_top": "chest_top",                    # cube-chest look re-drawn)
    # --- palette reconciliation (see BLOCKS tail section) ---
    "fire_0": "frame:campfire_fire:0",           # static frames of the pack's own
    "fire_1": "frame:campfire_fire:8",           # campfire flame strip
    "nether_portal": "frame:nether_portal:0",    # frame 0 of the pack's portal strip
    "end_stone": "end_stone",                    # pack lacks end textures: recreated
    "end_portal_frame_top": "end_frame_top",     # the classic way (inverted cobble
    "end_portal_frame_side": "end_frame_side",   # + fixed tints)
    "ender_chest_front": "echest:front",         # cube-chest faces over pack obsidian
    "ender_chest_side": "echest:side",
    "ender_chest_top": "echest:top",
    "skull_steve": "skin:steve",                 # 32x16 head crops of the pack's
    "skull_creeper": "skin:creeper/creeper",     # own entity skins
    "skull_skeleton": "skin:skeleton/skeleton",
    "skull_wither_skeleton": "skin:skeleton/wither_skeleton",
    "skull_zombie": "skin:zombie/zombie",
    "red_bed_sheet": "entity64:bed/red",         # full 64x64 bed sheet (UV-mapped)
    "sign_oak": "sign_board",                    # top 64x16 of entity/sign.png
}

# item-folder textures (OUT name under assets/eclipse/textures/item/classic/)
ITEM_TEXTURE_OPS = {
    "oak_door": "item:oak_door",
    "iron_door": "item:iron_door",
    "repeater": "item:repeater",
    "redstone": "item:redstone",
    "sugar_cane": "item:sugar_cane",
    "wheat": "item:wheat",
    "brewing_stand": "item:brewing_stand",
    "red_bed": "item:red_bed",
    "carrot": "item:carrot",
    "potato": "item:potato",
}

# ---------------------------------------------------------------------------
# block entries
# ---------------------------------------------------------------------------

def B(id, en, de, shape, model, *, tool=None, tier=None, hard=0.0, res=None,
      sound="STONE", light=0, req=False, color="NONE", noocc=False, render=None,
      item="block", tex=None, param=None, loot="self", climbable=False,
      mirror=None):
    """One classic block.

    shape : Java registration kind (ClassicBlockShapes enum name, lowercase)
    model : asset generation kind
    tool  : mineable tag (pickaxe/axe/shovel/hoe) or None
    tier  : needs_*_tool tag (stone/iron/diamond) or None
    hard/res : destroy time / explosion resistance (res defaults to hard)
    item  : block | none | tall | standing_wall:<wall id> | generated:<tex ref>
            | inventory  (uses <id>_inventory model)
    tex   : model-kind specific texture slot map (OUT names / refs)
    loot  : self | empty | door | slab | drop:<other classic id>
    mirror: vanilla blockstate id whose functional state table is remapped
    """
    return {
        "id": id, "en": en, "de": de, "shape": shape, "model": model,
        "tool": tool, "tier": tier, "hard": hard,
        "res": hard if res is None else res, "sound": sound, "light": light,
        "req": req, "color": color, "noocc": noocc, "render": render,
        "item": item, "tex": tex or {}, "param": param, "loot": loot,
        "climbable": climbable, "mirror": mirror,
    }


WOOL = [
    ("white", "White", "Weiße Wolle", "SNOW"),
    ("orange", "Orange", "Orange Wolle", "COLOR_ORANGE"),
    ("magenta", "Magenta", "Magenta Wolle", "COLOR_MAGENTA"),
    ("light_blue", "Light Blue", "Hellblaue Wolle", "COLOR_LIGHT_BLUE"),
    ("yellow", "Yellow", "Gelbe Wolle", "COLOR_YELLOW"),
    ("lime", "Lime", "Hellgrüne Wolle", "COLOR_LIGHT_GREEN"),
    ("pink", "Pink", "Rosa Wolle", "COLOR_PINK"),
    ("gray", "Gray", "Graue Wolle", "COLOR_GRAY"),
    ("light_gray", "Light Gray", "Hellgraue Wolle", "COLOR_LIGHT_GRAY"),
    ("cyan", "Cyan", "Türkise Wolle", "COLOR_CYAN"),
    ("purple", "Purple", "Violette Wolle", "COLOR_PURPLE"),
    ("blue", "Blue", "Blaue Wolle", "COLOR_BLUE"),
    ("brown", "Brown", "Braune Wolle", "COLOR_BROWN"),
    ("green", "Green", "Grüne Wolle", "COLOR_GREEN"),
    ("red", "Red", "Rote Wolle", "COLOR_RED"),
    ("black", "Black", "Schwarze Wolle", "COLOR_BLACK"),
]

WOOD = [
    ("oak", "Oak", "Eichen", "WOOD"),
    ("spruce", "Spruce", "Fichten", "PODZOL"),
    ("birch", "Birch", "Birken", "SAND"),
    ("jungle", "Jungle", "Tropen", "DIRT"),
]

BLOCKS = []
_add = BLOCKS.append

# --- terrain -----------------------------------------------------------------
_add(B("stone", "Stone", "Stein", "simple", "cube_all", tool="pickaxe", hard=1.5, res=6.0, req=True, color="STONE"))
_add(B("grass_block", "Grass Block", "Grasblock", "grass", "grass_block", tool="shovel", hard=0.6, sound="GRASS", color="GRASS", mirror="grass_block",
       tex={"top": "grass_block_top", "side": "grass_block_side", "snow_side": "grass_block_snow", "bottom": "dirt"}))
_add(B("dirt", "Dirt", "Erde", "simple", "cube_all", tool="shovel", hard=0.5, sound="GRAVEL", color="DIRT"))
_add(B("cobblestone", "Cobblestone", "Bruchstein", "simple", "cube_all", tool="pickaxe", hard=2.0, res=6.0, req=True, color="STONE"))
_add(B("bedrock", "Bedrock", "Grundgestein", "simple", "cube_all", hard=-1.0, res=3600000.0, color="STONE", loot="empty"))
_add(B("sand", "Sand", "Sand", "simple", "cube_all", tool="shovel", hard=0.5, sound="SAND", color="SAND"))
_add(B("gravel", "Gravel", "Kies", "simple", "cube_all", tool="shovel", hard=0.6, sound="GRAVEL", color="STONE"))
_add(B("clay", "Clay", "Ton", "simple", "cube_all", tool="shovel", hard=0.6, sound="GRAVEL", color="CLAY"))
_add(B("sandstone", "Sandstone", "Sandstein", "simple", "cube_bottom_top", tool="pickaxe", hard=0.8, req=True, color="SAND",
       tex={"top": "sandstone_top", "bottom": "sandstone_bottom", "side": "sandstone"}))
_add(B("chiseled_sandstone", "Chiseled Sandstone", "Gemeißelter Sandstein", "simple", "cube_column_static", tool="pickaxe", hard=0.8, req=True, color="SAND",
       tex={"end": "sandstone_top", "side": "chiseled_sandstone"}))
_add(B("cut_sandstone", "Cut Sandstone", "Geschnittener Sandstein", "simple", "cube_column_static", tool="pickaxe", hard=0.8, req=True, color="SAND",
       tex={"end": "sandstone_top", "side": "cut_sandstone"}))
_add(B("smooth_sandstone", "Smooth Sandstone", "Glatter Sandstein", "simple", "cube_all", tool="pickaxe", hard=2.0, res=6.0, req=True, color="SAND",
       tex={"all": "sandstone_top"}))
_add(B("smooth_stone", "Smooth Stone", "Glatter Stein", "simple", "cube_all", tool="pickaxe", hard=2.0, res=6.0, req=True, color="STONE"))
_add(B("obsidian", "Obsidian", "Obsidian", "simple", "cube_all", tool="pickaxe", tier="diamond", hard=50.0, res=1200.0, req=True, color="COLOR_BLACK"))
_add(B("mossy_cobblestone", "Mossy Cobblestone", "Bemooster Bruchstein", "simple", "cube_all", tool="pickaxe", hard=2.0, res=6.0, req=True, color="STONE"))
_add(B("ice", "Ice", "Eis", "simple", "cube_all", tool="pickaxe", hard=0.5, sound="GLASS", color="ICE", noocc=True, render="translucent", param="slippery"))
_add(B("snow", "Snow", "Schnee", "snow_layer", "snow_layer", tool="shovel", hard=0.1, sound="SNOW", color="SNOW", mirror="snow", tex={"texture": "snow"}))
_add(B("snow_block", "Snow Block", "Schneeblock", "simple", "cube_all", tool="shovel", hard=0.2, sound="SNOW", color="SNOW", tex={"all": "snow"}))
_add(B("water", "Water", "Wasser", "fluid", "cube_all", hard=0.3, sound="GLASS", color="WATER", noocc=True, render="translucent", tex={"all": "water_still"}))
_add(B("lava", "Lava", "Lava", "fluid", "cube_all", hard=0.3, sound="GLASS", light=15, color="FIRE", tex={"all": "lava_still"}))
_add(B("netherrack", "Netherrack", "Netherrack", "simple", "cube_all", tool="pickaxe", hard=0.4, req=True, color="NETHER", sound="NETHERRACK"))
_add(B("soul_sand", "Soul Sand", "Seelensand", "simple", "cube_all", tool="shovel", hard=0.5, sound="SOUL_SAND", color="COLOR_BROWN"))
_add(B("glowstone", "Glowstone", "Leuchtstein", "simple", "cube_all", hard=0.3, sound="GLASS", light=15, color="SAND"))
_add(B("sponge", "Sponge", "Schwamm", "simple", "cube_all", tool="hoe", hard=0.6, sound="GRASS", color="COLOR_YELLOW"))

# --- ores & mineral blocks -----------------------------------------------------
_add(B("coal_ore", "Coal Ore", "Steinkohle", "simple", "cube_all", tool="pickaxe", hard=3.0, req=True, color="STONE"))
_add(B("iron_ore", "Iron Ore", "Eisenerz", "simple", "cube_all", tool="pickaxe", tier="stone", hard=3.0, req=True, color="STONE"))
_add(B("gold_ore", "Gold Ore", "Golderz", "simple", "cube_all", tool="pickaxe", tier="iron", hard=3.0, req=True, color="STONE"))
_add(B("diamond_ore", "Diamond Ore", "Diamanterz", "simple", "cube_all", tool="pickaxe", tier="iron", hard=3.0, req=True, color="STONE"))
_add(B("redstone_ore", "Redstone Ore", "Redstone-Erz", "rs_ore", "cube_all", tool="pickaxe", tier="iron", hard=3.0, req=True, color="STONE"))
_add(B("lapis_ore", "Lapis Lazuli Ore", "Lapislazulierz", "simple", "cube_all", tool="pickaxe", tier="stone", hard=3.0, req=True, color="STONE"))
_add(B("emerald_ore", "Emerald Ore", "Smaragderz", "simple", "cube_all", tool="pickaxe", tier="iron", hard=3.0, req=True, color="STONE"))
_add(B("lapis_block", "Block of Lapis Lazuli", "Lapislazuliblock", "simple", "cube_all", tool="pickaxe", tier="stone", hard=3.0, req=True, color="LAPIS"))
_add(B("gold_block", "Block of Gold", "Goldblock", "simple", "cube_all", tool="pickaxe", tier="iron", hard=3.0, res=6.0, req=True, sound="METAL", color="GOLD"))
_add(B("iron_block", "Block of Iron", "Eisenblock", "simple", "cube_all", tool="pickaxe", tier="stone", hard=5.0, res=6.0, req=True, sound="METAL", color="METAL"))
_add(B("diamond_block", "Block of Diamond", "Diamantblock", "simple", "cube_all", tool="pickaxe", tier="iron", hard=5.0, res=6.0, req=True, sound="METAL", color="DIAMOND"))

# --- masonry -------------------------------------------------------------------
_add(B("bricks", "Bricks", "Ziegelsteine", "simple", "cube_all", tool="pickaxe", hard=2.0, res=6.0, req=True, color="COLOR_RED"))
_add(B("stone_bricks", "Stone Bricks", "Steinziegel", "simple", "cube_all", tool="pickaxe", hard=1.5, res=6.0, req=True, color="STONE"))
_add(B("mossy_stone_bricks", "Mossy Stone Bricks", "Bemooste Steinziegel", "simple", "cube_all", tool="pickaxe", hard=1.5, res=6.0, req=True, color="STONE"))
_add(B("cracked_stone_bricks", "Cracked Stone Bricks", "Rissige Steinziegel", "simple", "cube_all", tool="pickaxe", hard=1.5, res=6.0, req=True, color="STONE"))
_add(B("chiseled_stone_bricks", "Chiseled Stone Bricks", "Gemeißelte Steinziegel", "simple", "cube_all", tool="pickaxe", hard=1.5, res=6.0, req=True, color="STONE"))
_add(B("nether_bricks", "Nether Bricks", "Netherziegel", "simple", "cube_all", tool="pickaxe", hard=2.0, res=6.0, req=True, sound="NETHER_BRICKS", color="NETHER"))

# --- wood ------------------------------------------------------------------------
for wid, wen, wde, wcolor in WOOD:
    _add(B(f"{wid}_log", f"{wen} Log", f"{wde}stamm", "pillar", "pillar", tool="axe", hard=2.0, sound="WOOD", color=wcolor,
           tex={"end": f"{wid}_log_top", "side": f"{wid}_log"}))
for wid, wen, wde, wcolor in WOOD:
    _add(B(f"{wid}_planks", f"{wen} Planks", f"{wde}holzbretter", "simple", "cube_all", tool="axe", hard=2.0, res=3.0, sound="WOOD", color="WOOD"))
for wid, wen, wde, wcolor in WOOD:
    de_leaves = {"oak": "Eichenlaub", "spruce": "Fichtennadeln", "birch": "Birkenlaub", "jungle": "Tropenbaumlaub"}[wid]
    _add(B(f"{wid}_leaves", f"{wen} Leaves", de_leaves, "leaves", "leaves", tool="hoe", hard=0.2, sound="GRASS", color="PLANT",
           noocc=True, render="cutout_mipped", tex={"all": f"{wid}_leaves"}))
for wid, wen, wde, wcolor in WOOD:
    de_sap = {"oak": "Eichensetzling", "spruce": "Fichtensetzling", "birch": "Birkensetzling", "jungle": "Tropenbaumsetzling"}[wid]
    _add(B(f"{wid}_sapling", f"{wen} Sapling", de_sap, "sapling", "cross", sound="GRASS", color="PLANT", render="cutout",
           item=f"generated:block/classic/{wid}_sapling", tex={"cross": f"{wid}_sapling"}))

# --- stairs ----------------------------------------------------------------------
_STAIRS = [
    ("oak_stairs", "Oak Stairs", "Eichentreppe", "axe", None, 2.0, 3.0, "WOOD", False, "oak_planks", "OAK_PLANKS"),
    ("spruce_stairs", "Spruce Stairs", "Fichtentreppe", "axe", None, 2.0, 3.0, "WOOD", False, "spruce_planks", "SPRUCE_PLANKS"),
    ("birch_stairs", "Birch Stairs", "Birkentreppe", "axe", None, 2.0, 3.0, "WOOD", False, "birch_planks", "BIRCH_PLANKS"),
    ("jungle_stairs", "Jungle Stairs", "Tropenholztreppe", "axe", None, 2.0, 3.0, "WOOD", False, "jungle_planks", "JUNGLE_PLANKS"),
    ("cobblestone_stairs", "Cobblestone Stairs", "Bruchsteintreppe", "pickaxe", None, 2.0, 6.0, "STONE", True, "cobblestone", "COBBLESTONE"),
    ("brick_stairs", "Brick Stairs", "Ziegeltreppe", "pickaxe", None, 2.0, 6.0, "STONE", True, "bricks", "BRICKS"),
    ("stone_brick_stairs", "Stone Brick Stairs", "Steinziegeltreppe", "pickaxe", None, 1.5, 6.0, "STONE", True, "stone_bricks", "STONE_BRICKS"),
    ("sandstone_stairs", "Sandstone Stairs", "Sandsteintreppe", "pickaxe", None, 0.8, 0.8, "STONE", True, "sandstone", "SANDSTONE"),
    ("nether_brick_stairs", "Nether Brick Stairs", "Netherziegeltreppe", "pickaxe", None, 2.0, 6.0, "NETHER_BRICKS", True, "nether_bricks", "NETHER_BRICKS"),
]
for sid, sen, sde, stool, stier, shard, sres, ssound, sreq, stex, sbase in _STAIRS:
    wood = ssound == "WOOD"
    tex = ({"bottom": "sandstone_bottom", "top": "sandstone_top", "side": "sandstone"} if sid == "sandstone_stairs"
           else {"bottom": stex, "top": stex, "side": stex})
    _add(B(sid, sen, sde, "stairs", "stairs", tool=stool, hard=shard, res=sres, sound=ssound if ssound != "NETHER_BRICKS" else "NETHER_BRICKS",
           req=sreq, color="WOOD" if wood else "STONE", param=sbase, mirror="oak_stairs", tex=tex))

# --- slabs -----------------------------------------------------------------------
_SLABS = [
    ("oak_slab", "Oak Slab", "Eichenholzstufe", "axe", 2.0, 3.0, "WOOD", False, {"bottom": "oak_planks", "top": "oak_planks", "side": "oak_planks"}, "oak_planks"),
    ("spruce_slab", "Spruce Slab", "Fichtenholzstufe", "axe", 2.0, 3.0, "WOOD", False, {"bottom": "spruce_planks", "top": "spruce_planks", "side": "spruce_planks"}, "spruce_planks"),
    ("birch_slab", "Birch Slab", "Birkenholzstufe", "axe", 2.0, 3.0, "WOOD", False, {"bottom": "birch_planks", "top": "birch_planks", "side": "birch_planks"}, "birch_planks"),
    ("jungle_slab", "Jungle Slab", "Tropenholzstufe", "axe", 2.0, 3.0, "WOOD", False, {"bottom": "jungle_planks", "top": "jungle_planks", "side": "jungle_planks"}, "jungle_planks"),
    ("petrified_oak_slab", "Petrified Oak Slab", "Versteinerte Eichenholzstufe", "pickaxe", 2.0, 6.0, "STONE", True, {"bottom": "oak_planks", "top": "oak_planks", "side": "oak_planks"}, "oak_planks"),
    ("smooth_stone_slab", "Smooth Stone Slab", "Glatte Steinstufe", "pickaxe", 2.0, 6.0, "STONE", True, {"bottom": "smooth_stone", "top": "smooth_stone", "side": "smooth_stone_slab_side"}, "smooth_stone_slab_double"),
    ("sandstone_slab", "Sandstone Slab", "Sandsteinstufe", "pickaxe", 2.0, 6.0, "STONE", True, {"bottom": "sandstone_bottom", "top": "sandstone_top", "side": "sandstone"}, "sandstone"),
    ("cobblestone_slab", "Cobblestone Slab", "Bruchsteinstufe", "pickaxe", 2.0, 6.0, "STONE", True, {"bottom": "cobblestone", "top": "cobblestone", "side": "cobblestone"}, "cobblestone"),
    ("brick_slab", "Brick Slab", "Ziegelstufe", "pickaxe", 2.0, 6.0, "STONE", True, {"bottom": "bricks", "top": "bricks", "side": "bricks"}, "bricks"),
    ("stone_brick_slab", "Stone Brick Slab", "Steinziegelstufe", "pickaxe", 2.0, 6.0, "STONE", True, {"bottom": "stone_bricks", "top": "stone_bricks", "side": "stone_bricks"}, "stone_bricks"),
]
for sid, sen, sde, stool, shard, sres, ssound, sreq, stex, sdouble in _SLABS:
    _add(B(sid, sen, sde, "slab", "slab", tool=stool, hard=shard, res=sres, sound=ssound, req=sreq,
           color="WOOD" if ssound == "WOOD" else "STONE", loot="slab", param=sdouble, tex=stex))

# --- wool ------------------------------------------------------------------------
for cid, cen, cde, ccolor in WOOL:
    _add(B(f"{cid}_wool", f"{cen} Wool", cde, "simple", "cube_all", hard=0.8, sound="WOOL", color=ccolor))

# --- glass -----------------------------------------------------------------------
_add(B("glass", "Glass", "Glas", "simple", "cube_all", hard=0.3, sound="GLASS", noocc=True, render="cutout", loot="self"))
_add(B("glass_pane", "Glass Pane", "Glasscheibe", "pane", "pane", hard=0.3, sound="GLASS", noocc=True, render="cutout", mirror="glass_pane",
       item="generated:block/classic/glass", tex={"pane": "glass", "edge": "glass_pane_top"}))
_add(B("iron_bars", "Iron Bars", "Eisengitter", "pane", "pane", tool="pickaxe", hard=5.0, res=6.0, req=True, sound="METAL", noocc=True, render="cutout",
       mirror="glass_pane", item="generated:block/classic/iron_bars", tex={"pane": "iron_bars", "edge": "iron_bars"}))

# --- wood utility -------------------------------------------------------------
_add(B("bookshelf", "Bookshelf", "Bücherregal", "simple", "cube_column_static", tool="axe", hard=1.5, sound="WOOD", color="WOOD",
       tex={"end": "oak_planks", "side": "bookshelf"}))
_add(B("crafting_table", "Crafting Table", "Werkbank", "simple", "crafting_table", tool="axe", hard=2.5, sound="WOOD", color="WOOD",
       tex={"top": "crafting_table_top", "front": "crafting_table_front", "side": "crafting_table_side", "bottom": "oak_planks"}))
_add(B("chest", "Chest", "Truhe", "chest", "chest", tool="axe", hard=2.5, sound="WOOD", color="WOOD",
       tex={"front": "chest_front", "side": "chest_side", "top": "chest_top"}))
_add(B("ladder", "Ladder", "Leiter", "ladder", "ladder", tool="axe", hard=0.4, sound="LADDER", noocc=True, render="cutout", climbable=True,
       item="generated:block/classic/ladder", tex={"texture": "ladder"}))
_add(B("oak_fence", "Oak Fence", "Eichenzaun", "fence", "fence", tool="axe", hard=2.0, res=3.0, sound="WOOD", color="WOOD",
       mirror="oak_fence", item="inventory", tex={"texture": "oak_planks"}))
_add(B("nether_brick_fence", "Nether Brick Fence", "Netherziegelzaun", "fence", "fence", tool="pickaxe", hard=2.0, res=6.0, req=True,
       sound="NETHER_BRICKS", color="NETHER", mirror="oak_fence", item="inventory", tex={"texture": "nether_bricks"}))
_add(B("oak_door", "Oak Door", "Eichentür", "door", "door", tool="axe", hard=3.0, sound="WOOD", color="WOOD", noocc=True, render="cutout",
       mirror="oak_door", item="tall", loot="door", param="OAK",
       tex={"bottom": "oak_door_bottom", "top": "oak_door_top", "item": "oak_door"}))
_add(B("iron_door", "Iron Door", "Eisentür", "door", "door", tool="pickaxe", hard=5.0, req=True, sound="METAL", color="METAL", noocc=True, render="cutout",
       mirror="oak_door", item="tall", loot="door", param="IRON",
       tex={"bottom": "iron_door_bottom", "top": "iron_door_top", "item": "iron_door"}))
_add(B("oak_trapdoor", "Oak Trapdoor", "Eichenfalltür", "trapdoor", "trapdoor", tool="axe", hard=3.0, sound="WOOD", color="WOOD",
       noocc=True, render="cutout", mirror="oak_trapdoor", param="OAK", tex={"texture": "oak_trapdoor"}))

# --- utility / redstone era -----------------------------------------------------
_add(B("furnace", "Furnace", "Ofen", "furnace_like", "furnace", tool="pickaxe", hard=3.5, req=True, color="STONE", mirror="furnace",
       tex={"front": "furnace_front", "front_on": "furnace_front_on", "side": "furnace_side", "top": "furnace_top"}))
_add(B("dispenser", "Dispenser", "Werfer", "dispenser", "dispenser", tool="pickaxe", hard=3.5, req=True, color="STONE", mirror="dispenser",
       tex={"front": "dispenser_front", "front_vertical": "dispenser_front_vertical", "side": "furnace_side", "top": "furnace_top"}))
_add(B("jukebox", "Jukebox", "Plattenspieler", "jukebox", "jukebox", tool="axe", hard=2.0, res=6.0, sound="WOOD", color="DIRT",
       tex={"top": "jukebox_top", "side": "jukebox_side"}))
_add(B("note_block", "Note Block", "Notenblock", "note_block", "cube_all", tool="axe", hard=0.8, sound="WOOD", color="WOOD",
       tex={"all": "note_block"}))
_add(B("tnt", "TNT", "TNT", "tnt", "tnt", sound="GRASS", color="FIRE",
       tex={"top": "tnt_top", "side": "tnt_side", "bottom": "tnt_bottom"}))
_add(B("torch", "Torch", "Fackel", "torch", "torch", light=14, sound="WOOD", render="cutout",
       item="standing_wall:wall_torch", tex={"torch": "torch"}))
_add(B("wall_torch", "Wall Torch", "Wandfackel", "wall_torch", "wall_torch", light=14, sound="WOOD", render="cutout",
       mirror="wall_torch", item="none", loot="drop:torch", tex={"torch": "torch"}))
_add(B("redstone_torch", "Redstone Torch", "Redstone-Fackel", "rs_torch", "rs_torch", sound="WOOD", render="cutout",
       item="standing_wall:redstone_wall_torch", tex={"on": "redstone_torch", "off": "redstone_torch_off"}))
_add(B("redstone_wall_torch", "Redstone Wall Torch", "Redstone-Wandfackel", "rs_wall_torch", "rs_wall_torch", sound="WOOD", render="cutout",
       item="none", loot="drop:redstone_torch", tex={"on": "redstone_torch", "off": "redstone_torch_off"}))
_add(B("lever", "Lever", "Hebel", "lever", "lever", hard=0.5, color="STONE", mirror="lever", render="cutout",
       item="generated:block/classic/lever", tex={"base": "cobblestone", "lever": "lever"}))
_add(B("stone_button", "Stone Button", "Steinknopf", "button", "button", hard=0.5, color="STONE", mirror="stone_button",
       item="inventory", tex={"texture": "stone"}))
_add(B("oak_button", "Oak Button", "Eichenholzknopf", "button", "button", hard=0.5, sound="WOOD", color="WOOD", mirror="stone_button",
       item="inventory", tex={"texture": "oak_planks"}))
_add(B("stone_pressure_plate", "Stone Pressure Plate", "Steindruckplatte", "plate", "plate", tool="pickaxe", hard=0.5, req=True, color="STONE",
       mirror="oak_pressure_plate", tex={"texture": "stone"}))
_add(B("oak_pressure_plate", "Oak Pressure Plate", "Eichenholzdruckplatte", "plate", "plate", tool="axe", hard=0.5, sound="WOOD", color="WOOD",
       mirror="oak_pressure_plate", tex={"texture": "oak_planks"}))
_add(B("redstone_wire", "Redstone Wire", "Redstone-Leitung", "wire", "wire", color="FIRE", render="cutout", mirror="redstone_wire",
       item="generated:item/classic/redstone",
       tex={"line0": "redstone_dust_line0", "line1": "redstone_dust_line1", "dot": "redstone_dust_dot", "overlay": "redstone_dust_overlay"}))
_add(B("repeater", "Redstone Repeater", "Redstone-Verstärker", "repeater", "repeater", color="STONE", render="cutout",
       item="generated:item/classic/repeater",
       tex={"off": "repeater", "on": "repeater_on", "stone": "smooth_stone"}))
_add(B("piston", "Piston", "Kolben", "piston", "piston", tool="pickaxe", hard=1.5, color="STONE", mirror="piston", item="inventory",
       tex={"platform": "piston_top", "side": "piston_side", "bottom": "piston_bottom", "inner": "piston_inner"}))
_add(B("sticky_piston", "Sticky Piston", "Klebriger Kolben", "piston", "piston", tool="pickaxe", hard=1.5, color="STONE", mirror="piston", item="inventory",
       tex={"platform": "piston_top_sticky", "side": "piston_side", "bottom": "piston_bottom", "inner": "piston_inner"}))
_add(B("piston_head", "Piston Head", "Kolbenkopf", "piston_head", "piston_head", tool="pickaxe", hard=1.5, color="STONE", mirror="piston_head",
       item="none", loot="empty", tex={"platform": "piston_top", "sticky": "piston_top_sticky", "side": "piston_side"}))

# --- rails ----------------------------------------------------------------------
_add(B("rail", "Rail", "Schiene", "rail_full", "rail_full", hard=0.7, sound="METAL", render="cutout", mirror="rail",
       item="generated:block/classic/rail", tex={"flat": "rail", "corner": "rail_corner"}))
_add(B("powered_rail", "Powered Rail", "Antriebsschiene", "rail_straight", "rail_straight", hard=0.7, sound="METAL", render="cutout", mirror="powered_rail",
       item="generated:block/classic/powered_rail", tex={"flat": "powered_rail", "flat_on": "powered_rail_on"}))
_add(B("detector_rail", "Detector Rail", "Sensorschiene", "rail_straight", "rail_straight", hard=0.7, sound="METAL", render="cutout", mirror="powered_rail",
       item="generated:block/classic/detector_rail", tex={"flat": "detector_rail", "flat_on": "detector_rail_on"}))

# --- farm & flora ------------------------------------------------------------------
_add(B("farmland", "Farmland", "Ackerboden", "farmland", "farmland", tool="shovel", hard=0.6, sound="GRAVEL", color="DIRT", mirror="farmland",
       tex={"top": "farmland", "moist": "farmland_moist", "dirt": "dirt"}))
_add(B("wheat", "Wheat Crops", "Weizenpflanzen", "crop8", "crop8", sound="CROP", color="PLANT", render="cutout",
       item="generated:item/classic/wheat", tex={"stages": "wheat_stage"}))
_add(B("pumpkin", "Pumpkin", "Kürbis", "simple", "cube_column_static", tool="axe", hard=1.0, sound="WOOD", color="COLOR_ORANGE",
       tex={"end": "pumpkin_top", "side": "pumpkin_side"}))
_add(B("carved_pumpkin", "Carved Pumpkin", "Geschnitzter Kürbis", "horizontal", "orientable", tool="axe", hard=1.0, sound="WOOD", color="COLOR_ORANGE",
       mirror="carved_pumpkin", tex={"front": "carved_pumpkin", "side": "pumpkin_side", "top": "pumpkin_top"}))
_add(B("jack_o_lantern", "Jack o'Lantern", "Kürbislaterne", "horizontal", "orientable", tool="axe", hard=1.0, light=15, sound="WOOD", color="COLOR_ORANGE",
       mirror="carved_pumpkin", tex={"front": "jack_o_lantern", "side": "pumpkin_side", "top": "pumpkin_top"}))
_add(B("melon", "Melon", "Melone", "simple", "cube_column_static", tool="axe", hard=1.0, sound="WOOD", color="COLOR_LIGHT_GREEN",
       tex={"end": "melon_top", "side": "melon_side"}))
_add(B("pumpkin_stem", "Pumpkin Stem", "Kürbisstängel", "stem", "stem", sound="GRASS", color="PLANT", render="cutout",
       item="none", loot="empty", tex={"stem": "pumpkin_stem"}))
_add(B("melon_stem", "Melon Stem", "Melonenstängel", "stem", "stem", sound="GRASS", color="PLANT", render="cutout",
       item="none", loot="empty", tex={"stem": "melon_stem"}))
_add(B("attached_pumpkin_stem", "Attached Pumpkin Stem", "Tragender Kürbisstängel", "attached_stem", "attached_stem", sound="GRASS", color="PLANT",
       render="cutout", item="none", loot="empty", tex={"stem": "pumpkin_stem", "upperstem": "attached_pumpkin_stem"}))
_add(B("attached_melon_stem", "Attached Melon Stem", "Tragender Melonenstängel", "attached_stem", "attached_stem", sound="GRASS", color="PLANT",
       render="cutout", item="none", loot="empty", tex={"stem": "melon_stem", "upperstem": "attached_melon_stem"}))
_add(B("sugar_cane", "Sugar Cane", "Zuckerrohr", "cane", "cross", sound="GRASS", color="PLANT", render="cutout",
       item="generated:item/classic/sugar_cane", tex={"cross": "sugar_cane"}))
_add(B("cactus", "Cactus", "Kaktus", "cactus", "cactus", hard=0.4, sound="WOOL", color="PLANT", noocc=True, render="cutout",
       tex={"top": "cactus_top", "side": "cactus_side", "bottom": "cactus_bottom"}))
_add(B("dead_bush", "Dead Bush", "Toter Busch", "cross", "cross", sound="GRASS", color="WOOD", render="cutout",
       item="generated:block/classic/dead_bush", tex={"cross": "dead_bush"}))
_add(B("short_grass", "Short Grass", "Gras", "cross", "cross", sound="GRASS", color="PLANT", render="cutout",
       item="generated:block/classic/short_grass", tex={"cross": "short_grass"}))
_add(B("fern", "Fern", "Farn", "cross", "cross", sound="GRASS", color="PLANT", render="cutout",
       item="generated:block/classic/fern", tex={"cross": "fern"}))
_add(B("dandelion", "Dandelion", "Löwenzahn", "cross", "cross", sound="GRASS", color="PLANT", render="cutout",
       item="generated:block/classic/dandelion", tex={"cross": "dandelion"}))
_add(B("poppy", "Poppy", "Mohn", "cross", "cross", sound="GRASS", color="PLANT", render="cutout",
       item="generated:block/classic/poppy", tex={"cross": "poppy"}))
_add(B("brown_mushroom", "Brown Mushroom", "Brauner Pilz", "cross", "cross", light=1, sound="GRASS", color="COLOR_BROWN", render="cutout",
       item="generated:block/classic/brown_mushroom", tex={"cross": "brown_mushroom"}))
_add(B("red_mushroom", "Red Mushroom", "Roter Pilz", "cross", "cross", sound="GRASS", color="COLOR_RED", render="cutout",
       item="generated:block/classic/red_mushroom", tex={"cross": "red_mushroom"}))
_add(B("cobweb", "Cobweb", "Spinnennetz", "cross", "cross", hard=4.0, sound="COBWEB", color="WOOL", render="cutout",
       item="generated:block/classic/cobweb", tex={"cross": "cobweb"}))
_add(B("vine", "Vines", "Ranken", "vine", "vine", hard=0.2, sound="VINE", color="PLANT", render="cutout", climbable=True,
       mirror="vine", item="generated:block/classic/vine", tex={"vine": "vine"}))
_add(B("lily_pad", "Lily Pad", "Seerosenblatt", "lily", "lily", sound="LILY_PAD", color="PLANT", render="cutout",
       item="generated:block/classic/lily_pad", tex={"texture": "lily_pad"}))

# --- palette reconciliation ------------------------------------------------------
# Remaining ids from P5-W7's authoritative docs/plans_v3/xbox_palette.json (156
# distinct vanilla ids across tu1/tu12/tu14). Everything the baked worlds contain
# MUST exist as eclipse:classic_<path> with vanilla-identical property sets.
_add(B("mycelium", "Mycelium", "Myzel", "grass", "mycelium", tool="shovel", hard=0.6, sound="GRASS", color="COLOR_PURPLE",
       mirror="mycelium", tex={"top": "mycelium_top", "side": "mycelium_side", "bottom": "dirt"}))
_add(B("infested_stone", "Infested Stone", "Befallener Stein", "simple", "cube_all", hard=0.75, color="CLAY", tex={"all": "stone"}))
_add(B("infested_cobblestone", "Infested Cobblestone", "Befallener Bruchstein", "simple", "cube_all", hard=0.75, color="CLAY", tex={"all": "cobblestone"}))
_add(B("infested_stone_bricks", "Infested Stone Bricks", "Befallene Steinziegel", "simple", "cube_all", hard=0.75, color="CLAY", tex={"all": "stone_bricks"}))
_add(B("quartz_block", "Block of Quartz", "Quarzblock", "simple", "cube_bottom_top", tool="pickaxe", hard=0.8, req=True, color="QUARTZ",
       tex={"top": "quartz_block_top", "bottom": "quartz_block_bottom", "side": "quartz_block_side"}))
_add(B("quartz_pillar", "Quartz Pillar", "Quarzsäule", "pillar", "pillar", tool="pickaxe", hard=0.8, req=True, color="QUARTZ",
       tex={"end": "quartz_pillar_top", "side": "quartz_pillar"}))
_add(B("quartz_stairs", "Quartz Stairs", "Quarztreppe", "stairs", "stairs", tool="pickaxe", hard=0.8, req=True, color="QUARTZ",
       mirror="oak_stairs", param="QUARTZ_BLOCK",
       tex={"bottom": "quartz_block_bottom", "top": "quartz_block_top", "side": "quartz_block_side"}))
_add(B("cobblestone_wall", "Cobblestone Wall", "Bruchsteinmauer", "wall", "wall", tool="pickaxe", hard=2.0, res=6.0, req=True, color="STONE",
       mirror="cobblestone_wall", item="inventory", tex={"wall": "cobblestone"}))
_add(B("mossy_cobblestone_wall", "Mossy Cobblestone Wall", "Bemooste Bruchsteinmauer", "wall", "wall", tool="pickaxe", hard=2.0, res=6.0, req=True,
       color="STONE", mirror="cobblestone_wall", item="inventory", tex={"wall": "mossy_cobblestone"}))
_add(B("red_carpet", "Red Carpet", "Roter Teppich", "carpet", "carpet", hard=0.1, sound="WOOL", color="COLOR_RED", tex={"wool": "red_wool"}))
_add(B("yellow_carpet", "Yellow Carpet", "Gelber Teppich", "carpet", "carpet", hard=0.1, sound="WOOL", color="COLOR_YELLOW", tex={"wool": "yellow_wool"}))
_add(B("anvil", "Anvil", "Amboss", "anvil", "anvil", tool="pickaxe", hard=5.0, res=1200.0, req=True, sound="ANVIL", color="METAL",
       mirror="anvil", tex={"body": "anvil", "top": "anvil_top"}))
_add(B("brewing_stand", "Brewing Stand", "Braustand", "brewing_stand", "brewing_stand", tool="pickaxe", hard=0.5, req=True, light=1, color="METAL",
       noocc=True, render="cutout", mirror="brewing_stand", item="generated:item/classic/brewing_stand",
       tex={"stand": "brewing_stand", "base": "brewing_stand_base"}))
_add(B("enchanting_table", "Enchanting Table", "Zaubertisch", "enchanting_table", "enchanting_table", tool="pickaxe", hard=5.0, res=1200.0,
       req=True, light=7, color="COLOR_RED", noocc=True,
       tex={"top": "enchanting_table_top", "side": "enchanting_table_side", "bottom": "enchanting_table_bottom"}))
_add(B("ender_chest", "Ender Chest", "Endertruhe", "ender_chest", "chest", tool="pickaxe", hard=22.5, res=600.0, req=True, light=7,
       color="COLOR_BLACK", tex={"front": "ender_chest_front", "side": "ender_chest_side", "top": "ender_chest_top"}))
_add(B("end_portal_frame", "End Portal Frame", "Endportalrahmen", "end_portal_frame", "end_portal_frame", hard=-1.0, res=3600000.0, light=1,
       sound="GLASS", color="COLOR_GREEN", mirror="end_portal_frame", loot="empty",
       tex={"top": "end_portal_frame_top", "side": "end_portal_frame_side", "bottom": "end_stone", "eye": "end_portal_frame_eye"}))
_add(B("spawner", "Monster Spawner", "Monsterspawner", "simple", "cube_all_inner", tool="pickaxe", hard=5.0, req=True, sound="METAL",
       color="STONE", noocc=True, render="cutout", tex={"all": "spawner"}))
_add(B("redstone_lamp", "Redstone Lamp", "Redstone-Lampe", "rs_lamp", "rs_lamp", hard=0.3, sound="GLASS", mirror="redstone_lamp",
       tex={"off": "redstone_lamp", "on": "redstone_lamp_on"}))
_add(B("nether_portal", "Nether Portal", "Netherportal", "nether_portal", "nether_portal", hard=-1.0, res=0.0, light=11, sound="GLASS",
       color="NETHER", noocc=True, render="translucent", mirror="nether_portal", item="none", loot="empty",
       tex={"portal": "nether_portal"}))
_add(B("fire", "Fire", "Feuer", "fire", "fire", light=15, sound="WOOL", color="FIRE", render="cutout", mirror="fire",
       item="none", loot="empty", tex={"fire0": "fire_0", "fire1": "fire_1"}))
_add(B("oak_fence_gate", "Oak Fence Gate", "Eichenzauntor", "fence_gate", "fence_gate", tool="axe", hard=2.0, res=3.0, sound="WOOD",
       color="WOOD", mirror="oak_fence_gate", tex={"texture": "oak_planks"}))
_add(B("oak_wall_sign", "Oak Wall Sign", "Eichenholzwandschild", "wall_sign", "wall_sign", tool="axe", hard=1.0, sound="WOOD", color="WOOD",
       noocc=True, render="cutout", item="none", loot="empty", tex={"board": "sign_oak"}))
_add(B("red_bed", "Red Bed", "Rotes Bett", "bed", "bed", hard=0.2, sound="WOOD", color="COLOR_RED", noocc=True,
       item="generated:item/classic/red_bed", loot="bed", tex={"sheet": "red_bed_sheet"}))
_add(B("carrots", "Carrots", "Karotten", "crop8", "crop4", sound="CROP", color="PLANT", render="cutout", mirror="carrots",
       item="generated:item/classic/carrot", tex={"stages": "carrots_stage"}))
_add(B("potatoes", "Potatoes", "Kartoffeln", "crop8", "crop4", sound="CROP", color="PLANT", render="cutout", mirror="potatoes",
       item="generated:item/classic/potato", tex={"stages": "potatoes_stage"}))
_add(B("cocoa", "Cocoa", "Kakaopflanze", "cocoa", "cocoa", tool="axe", hard=0.2, res=3.0, sound="WOOD", color="PLANT", noocc=True,
       render="cutout", mirror="cocoa", item="none", loot="empty", tex={"stages": "cocoa_stage"}))
_add(B("brown_mushroom_block", "Brown Mushroom Block", "Brauner Pilzblock", "mushroom", "mushroom", tool="axe", hard=0.2, sound="WOOD",
       color="DIRT", mirror="brown_mushroom_block", tex={"outside": "brown_mushroom_block"}))
_add(B("red_mushroom_block", "Red Mushroom Block", "Roter Pilzblock", "mushroom", "mushroom", tool="axe", hard=0.2, sound="WOOD",
       color="COLOR_RED", mirror="red_mushroom_block", tex={"outside": "red_mushroom_block"}))
_add(B("mushroom_stem", "Mushroom Stem", "Pilzstiel", "mushroom", "mushroom", tool="axe", hard=0.2, sound="WOOD", color="WOOL",
       mirror="mushroom_stem", tex={"outside": "mushroom_stem"}))
_add(B("tripwire", "Tripwire", "Stolperdraht", "tripwire", "tripwire", color="NONE", render="cutout", mirror="tripwire",
       item="none", loot="empty", tex={"texture": "tripwire"}))
_add(B("tripwire_hook", "Tripwire Hook", "Haken", "tripwire_hook", "tripwire_hook", sound="WOOD", color="NONE", render="cutout",
       mirror="tripwire_hook", item="generated:block/classic/tripwire_hook",
       tex={"hook": "tripwire_hook", "wood": "oak_planks", "tripwire": "tripwire"}))
_add(B("water_cauldron", "Water Cauldron", "Wasserkessel", "cauldron", "cauldron", tool="pickaxe", hard=2.0, req=True, color="STONE",
       mirror="water_cauldron", item="none", loot="empty",
       tex={"top": "cauldron_top", "bottom": "cauldron_bottom", "side": "cauldron_side", "inside": "cauldron_inner", "content": "water_still"}))
_add(B("potted_dandelion", "Potted Dandelion", "Eingetopfter Löwenzahn", "potted", "potted", color="NONE", noocc=True, render="cutout",
       item="none", loot="drop:dandelion", tex={"plant": "dandelion"}))
_add(B("potted_poppy", "Potted Poppy", "Eingetopfter Mohn", "potted", "potted", color="NONE", noocc=True, render="cutout",
       item="none", loot="drop:poppy", tex={"plant": "poppy"}))
_add(B("potted_oak_sapling", "Potted Oak Sapling", "Eingetopfter Eichensetzling", "potted", "potted", color="NONE", noocc=True, render="cutout",
       item="none", loot="drop:oak_sapling", tex={"plant": "oak_sapling"}))
_add(B("skeleton_skull", "Skeleton Skull", "Skelettschädel", "skull", "skull", hard=1.0, color="NONE", tex={"skin": "skull_skeleton"}))
_add(B("wither_skeleton_skull", "Wither Skeleton Skull", "Witherskelettschädel", "skull", "skull", hard=1.0, color="COLOR_BLACK",
       tex={"skin": "skull_wither_skeleton"}))
_add(B("zombie_head", "Zombie Head", "Zombiekopf", "skull", "skull", hard=1.0, color="COLOR_GREEN", tex={"skin": "skull_zombie"}))
_add(B("creeper_head", "Creeper Head", "Creeperkopf", "skull", "skull", hard=1.0, color="COLOR_GREEN", tex={"skin": "skull_creeper"}))
_add(B("player_head", "Player Head", "Spielerkopf", "skull", "skull", hard=1.0, color="NONE", tex={"skin": "skull_steve"}))


# ---------------------------------------------------------------------------
# sanity constants shared by the scripts
# ---------------------------------------------------------------------------
MOD_ID = "eclipse"
PREFIX = "classic_"
TAB_KEY = "itemGroup.eclipse.classic"
TAB_EN = "Eclipse — Classic Blocks"
TAB_DE = "Eclipse — Klassische Blöcke"

# per-worker docs
LANGDROP = "docs/plans_v3/langdrop/P5-W8.json"

if __name__ == "__main__":
    ids = [b["id"] for b in BLOCKS]
    assert len(ids) == len(set(ids)), "duplicate ids in manifest"
    print(f"{len(BLOCKS)} classic blocks")
    from collections import Counter
    print(Counter(b["shape"] for b in BLOCKS))
