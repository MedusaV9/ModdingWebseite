// GENERATED FILE — do not edit by hand.
// Source of truth: tools/classicblocks/manifest.py  (regen: python3 tools/classicblocks/gen_assets.py)
package dev.projecteclipse.eclipse.classicblocks;

import java.util.List;

import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.material.MapColor;

/**
 * P5-W8 manifest of every {@code eclipse:classic_*} block (frozen naming scheme:
 * vanilla {@code minecraft:<path>} maps to {@code eclipse:classic_<path>}, identical
 * blockstate properties — P5-W7's region baker relies on these ids verbatim).
 *
 * <p>Assets (blockstates/models/loot/tags/lang) are generated from the same manifest
 * by {@code tools/classicblocks/gen_assets.py} into {@code src/generated/resources}.
 */
public final class ClassicBlockList {

    /** How an entry registers (see {@link ClassicBlocks#create}). */
    public enum Shape {
        SIMPLE, GRASS, PILLAR, LEAVES, SLAB, STAIRS, FENCE, PANE, LADDER, DOOR, TRAPDOOR,
        TORCH, WALL_TORCH, RS_TORCH, RS_WALL_TORCH, CROSS, SAPLING, CROP8, CANE, CACTUS,
        STEM, ATTACHED_STEM, FARMLAND, SNOW_LAYER, FLUID, CHEST, FURNACE_LIKE, DISPENSER,
        JUKEBOX, NOTE_BLOCK, TNT, RS_ORE, LEVER, BUTTON, PLATE, WIRE, REPEATER, PISTON,
        PISTON_HEAD, RAIL_FULL, RAIL_STRAIGHT, VINE, LILY, HORIZONTAL,
        // palette reconciliation (xbox_palette.json)
        WALL, CARPET, ANVIL, BREWING_STAND, ENCHANTING_TABLE, END_PORTAL_FRAME, ENDER_CHEST,
        RS_LAMP, NETHER_PORTAL, FIRE, FENCE_GATE, WALL_SIGN, BED, COCOA, MUSHROOM, TRIPWIRE,
        TRIPWIRE_HOOK, CAULDRON, POTTED, SKULL
    }

    /** How the matching item registers (never: recipes, fuel, vanilla tabs). */
    public enum ItemKind { BLOCK, NONE, TALL, STANDING_WALL }

    /**
     * @param id        path without the {@code classic_} prefix (vanilla twin's path)
     * @param shape     registration kind
     * @param hardness  destroy time (vanilla twin's value; -1 = unbreakable)
     * @param resistance explosion resistance
     * @param light     constant light emission (state-dependent light lives in the shape classes)
     * @param requiresTool vanilla twin's requiresCorrectToolForDrops
     * @param sound     vanilla twin's sound type
     * @param mapColor  vanilla twin's map color
     * @param noOcclusion true for glassy/leafy blocks
     * @param itemKind  BLOCK = plain BlockItem, TALL = door item, STANDING_WALL = torch-style,
     *                  NONE = technical block without an item
     * @param itemParam wall-block id for STANDING_WALL items
     * @param param     shape-specific extra (stairs base block, door set type, "slippery", ...)
     */
    public record Entry(String id, Shape shape, float hardness, float resistance, int light,
                        boolean requiresTool, SoundType sound, MapColor mapColor,
                        boolean noOcclusion, ItemKind itemKind, String itemParam, String param) {

        public String blockId() {
            return "classic_" + id;
        }
    }

    private static Entry e(String id, Shape shape, float hardness, float resistance, int light,
                           boolean requiresTool, SoundType sound, MapColor mapColor,
                           boolean noOcclusion, ItemKind itemKind, String itemParam, String param) {
        return new Entry(id, shape, hardness, resistance, light, requiresTool, sound, mapColor,
                noOcclusion, itemKind, itemParam, param);
    }

    /** Every classic block, in stable registration order. */
    public static final List<Entry> ENTRIES = List.of(
            e("stone", Shape.SIMPLE, 1.5F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("grass_block", Shape.GRASS, 0.6F, 0.6F, 0, false, SoundType.GRASS, MapColor.GRASS, false, ItemKind.BLOCK, null, null),
            e("dirt", Shape.SIMPLE, 0.5F, 0.5F, 0, false, SoundType.GRAVEL, MapColor.DIRT, false, ItemKind.BLOCK, null, null),
            e("cobblestone", Shape.SIMPLE, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("bedrock", Shape.SIMPLE, -1.0F, 3600000.0F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("sand", Shape.SIMPLE, 0.5F, 0.5F, 0, false, SoundType.SAND, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("gravel", Shape.SIMPLE, 0.6F, 0.6F, 0, false, SoundType.GRAVEL, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("clay", Shape.SIMPLE, 0.6F, 0.6F, 0, false, SoundType.GRAVEL, MapColor.CLAY, false, ItemKind.BLOCK, null, null),
            e("sandstone", Shape.SIMPLE, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("chiseled_sandstone", Shape.SIMPLE, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("cut_sandstone", Shape.SIMPLE, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("smooth_sandstone", Shape.SIMPLE, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("smooth_stone", Shape.SIMPLE, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("obsidian", Shape.SIMPLE, 50.0F, 1200.0F, 0, true, SoundType.STONE, MapColor.COLOR_BLACK, false, ItemKind.BLOCK, null, null),
            e("mossy_cobblestone", Shape.SIMPLE, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("ice", Shape.SIMPLE, 0.5F, 0.5F, 0, false, SoundType.GLASS, MapColor.ICE, true, ItemKind.BLOCK, null, "slippery"),
            e("snow", Shape.SNOW_LAYER, 0.1F, 0.1F, 0, false, SoundType.SNOW, MapColor.SNOW, false, ItemKind.BLOCK, null, null),
            e("snow_block", Shape.SIMPLE, 0.2F, 0.2F, 0, false, SoundType.SNOW, MapColor.SNOW, false, ItemKind.BLOCK, null, null),
            e("water", Shape.FLUID, 0.3F, 0.3F, 0, false, SoundType.GLASS, MapColor.WATER, true, ItemKind.BLOCK, null, null),
            e("lava", Shape.FLUID, 0.3F, 0.3F, 15, false, SoundType.GLASS, MapColor.FIRE, false, ItemKind.BLOCK, null, null),
            e("netherrack", Shape.SIMPLE, 0.4F, 0.4F, 0, true, SoundType.NETHERRACK, MapColor.NETHER, false, ItemKind.BLOCK, null, null),
            e("soul_sand", Shape.SIMPLE, 0.5F, 0.5F, 0, false, SoundType.SOUL_SAND, MapColor.COLOR_BROWN, false, ItemKind.BLOCK, null, null),
            e("glowstone", Shape.SIMPLE, 0.3F, 0.3F, 15, false, SoundType.GLASS, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("sponge", Shape.SIMPLE, 0.6F, 0.6F, 0, false, SoundType.GRASS, MapColor.COLOR_YELLOW, false, ItemKind.BLOCK, null, null),
            e("coal_ore", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("iron_ore", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("gold_ore", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("diamond_ore", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("redstone_ore", Shape.RS_ORE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("lapis_ore", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("emerald_ore", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("lapis_block", Shape.SIMPLE, 3.0F, 3.0F, 0, true, SoundType.STONE, MapColor.LAPIS, false, ItemKind.BLOCK, null, null),
            e("gold_block", Shape.SIMPLE, 3.0F, 6.0F, 0, true, SoundType.METAL, MapColor.GOLD, false, ItemKind.BLOCK, null, null),
            e("iron_block", Shape.SIMPLE, 5.0F, 6.0F, 0, true, SoundType.METAL, MapColor.METAL, false, ItemKind.BLOCK, null, null),
            e("diamond_block", Shape.SIMPLE, 5.0F, 6.0F, 0, true, SoundType.METAL, MapColor.DIAMOND, false, ItemKind.BLOCK, null, null),
            e("bricks", Shape.SIMPLE, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.COLOR_RED, false, ItemKind.BLOCK, null, null),
            e("stone_bricks", Shape.SIMPLE, 1.5F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("mossy_stone_bricks", Shape.SIMPLE, 1.5F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("cracked_stone_bricks", Shape.SIMPLE, 1.5F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("chiseled_stone_bricks", Shape.SIMPLE, 1.5F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("nether_bricks", Shape.SIMPLE, 2.0F, 6.0F, 0, true, SoundType.NETHER_BRICKS, MapColor.NETHER, false, ItemKind.BLOCK, null, null),
            e("oak_log", Shape.PILLAR, 2.0F, 2.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("spruce_log", Shape.PILLAR, 2.0F, 2.0F, 0, false, SoundType.WOOD, MapColor.PODZOL, false, ItemKind.BLOCK, null, null),
            e("birch_log", Shape.PILLAR, 2.0F, 2.0F, 0, false, SoundType.WOOD, MapColor.SAND, false, ItemKind.BLOCK, null, null),
            e("jungle_log", Shape.PILLAR, 2.0F, 2.0F, 0, false, SoundType.WOOD, MapColor.DIRT, false, ItemKind.BLOCK, null, null),
            e("oak_planks", Shape.SIMPLE, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("spruce_planks", Shape.SIMPLE, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("birch_planks", Shape.SIMPLE, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("jungle_planks", Shape.SIMPLE, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("oak_leaves", Shape.LEAVES, 0.2F, 0.2F, 0, false, SoundType.GRASS, MapColor.PLANT, true, ItemKind.BLOCK, null, null),
            e("spruce_leaves", Shape.LEAVES, 0.2F, 0.2F, 0, false, SoundType.GRASS, MapColor.PLANT, true, ItemKind.BLOCK, null, null),
            e("birch_leaves", Shape.LEAVES, 0.2F, 0.2F, 0, false, SoundType.GRASS, MapColor.PLANT, true, ItemKind.BLOCK, null, null),
            e("jungle_leaves", Shape.LEAVES, 0.2F, 0.2F, 0, false, SoundType.GRASS, MapColor.PLANT, true, ItemKind.BLOCK, null, null),
            e("oak_sapling", Shape.SAPLING, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("spruce_sapling", Shape.SAPLING, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("birch_sapling", Shape.SAPLING, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("jungle_sapling", Shape.SAPLING, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("oak_stairs", Shape.STAIRS, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "OAK_PLANKS"),
            e("spruce_stairs", Shape.STAIRS, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "SPRUCE_PLANKS"),
            e("birch_stairs", Shape.STAIRS, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "BIRCH_PLANKS"),
            e("jungle_stairs", Shape.STAIRS, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "JUNGLE_PLANKS"),
            e("cobblestone_stairs", Shape.STAIRS, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "COBBLESTONE"),
            e("brick_stairs", Shape.STAIRS, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "BRICKS"),
            e("stone_brick_stairs", Shape.STAIRS, 1.5F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "STONE_BRICKS"),
            e("sandstone_stairs", Shape.STAIRS, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "SANDSTONE"),
            e("nether_brick_stairs", Shape.STAIRS, 2.0F, 6.0F, 0, true, SoundType.NETHER_BRICKS, MapColor.STONE, false, ItemKind.BLOCK, null, "NETHER_BRICKS"),
            e("oak_slab", Shape.SLAB, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "oak_planks"),
            e("spruce_slab", Shape.SLAB, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "spruce_planks"),
            e("birch_slab", Shape.SLAB, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "birch_planks"),
            e("jungle_slab", Shape.SLAB, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, "jungle_planks"),
            e("petrified_oak_slab", Shape.SLAB, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "oak_planks"),
            e("smooth_stone_slab", Shape.SLAB, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "smooth_stone_slab_double"),
            e("sandstone_slab", Shape.SLAB, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "sandstone"),
            e("cobblestone_slab", Shape.SLAB, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "cobblestone"),
            e("brick_slab", Shape.SLAB, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "bricks"),
            e("stone_brick_slab", Shape.SLAB, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, "stone_bricks"),
            e("white_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.SNOW, false, ItemKind.BLOCK, null, null),
            e("orange_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_ORANGE, false, ItemKind.BLOCK, null, null),
            e("magenta_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_MAGENTA, false, ItemKind.BLOCK, null, null),
            e("light_blue_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_LIGHT_BLUE, false, ItemKind.BLOCK, null, null),
            e("yellow_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_YELLOW, false, ItemKind.BLOCK, null, null),
            e("lime_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_LIGHT_GREEN, false, ItemKind.BLOCK, null, null),
            e("pink_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_PINK, false, ItemKind.BLOCK, null, null),
            e("gray_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_GRAY, false, ItemKind.BLOCK, null, null),
            e("light_gray_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_LIGHT_GRAY, false, ItemKind.BLOCK, null, null),
            e("cyan_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_CYAN, false, ItemKind.BLOCK, null, null),
            e("purple_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_PURPLE, false, ItemKind.BLOCK, null, null),
            e("blue_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_BLUE, false, ItemKind.BLOCK, null, null),
            e("brown_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_BROWN, false, ItemKind.BLOCK, null, null),
            e("green_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_GREEN, false, ItemKind.BLOCK, null, null),
            e("red_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_RED, false, ItemKind.BLOCK, null, null),
            e("black_wool", Shape.SIMPLE, 0.8F, 0.8F, 0, false, SoundType.WOOL, MapColor.COLOR_BLACK, false, ItemKind.BLOCK, null, null),
            e("glass", Shape.SIMPLE, 0.3F, 0.3F, 0, false, SoundType.GLASS, MapColor.NONE, true, ItemKind.BLOCK, null, null),
            e("glass_pane", Shape.PANE, 0.3F, 0.3F, 0, false, SoundType.GLASS, MapColor.NONE, true, ItemKind.BLOCK, null, null),
            e("iron_bars", Shape.PANE, 5.0F, 6.0F, 0, true, SoundType.METAL, MapColor.NONE, true, ItemKind.BLOCK, null, null),
            e("bookshelf", Shape.SIMPLE, 1.5F, 1.5F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("crafting_table", Shape.SIMPLE, 2.5F, 2.5F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("chest", Shape.CHEST, 2.5F, 2.5F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("ladder", Shape.LADDER, 0.4F, 0.4F, 0, false, SoundType.LADDER, MapColor.NONE, true, ItemKind.BLOCK, null, null),
            e("oak_fence", Shape.FENCE, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("nether_brick_fence", Shape.FENCE, 2.0F, 6.0F, 0, true, SoundType.NETHER_BRICKS, MapColor.NETHER, false, ItemKind.BLOCK, null, null),
            e("oak_door", Shape.DOOR, 3.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, true, ItemKind.TALL, null, "OAK"),
            e("iron_door", Shape.DOOR, 5.0F, 5.0F, 0, true, SoundType.METAL, MapColor.METAL, true, ItemKind.TALL, null, "IRON"),
            e("oak_trapdoor", Shape.TRAPDOOR, 3.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, true, ItemKind.BLOCK, null, "OAK"),
            e("furnace", Shape.FURNACE_LIKE, 3.5F, 3.5F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("dispenser", Shape.DISPENSER, 3.5F, 3.5F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("jukebox", Shape.JUKEBOX, 2.0F, 6.0F, 0, false, SoundType.WOOD, MapColor.DIRT, false, ItemKind.BLOCK, null, null),
            e("note_block", Shape.NOTE_BLOCK, 0.8F, 0.8F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("tnt", Shape.TNT, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.FIRE, false, ItemKind.BLOCK, null, null),
            e("torch", Shape.TORCH, 0.0F, 0.0F, 14, false, SoundType.WOOD, MapColor.NONE, false, ItemKind.STANDING_WALL, "wall_torch", null),
            e("wall_torch", Shape.WALL_TORCH, 0.0F, 0.0F, 14, false, SoundType.WOOD, MapColor.NONE, false, ItemKind.NONE, null, null),
            e("redstone_torch", Shape.RS_TORCH, 0.0F, 0.0F, 0, false, SoundType.WOOD, MapColor.NONE, false, ItemKind.STANDING_WALL, "redstone_wall_torch", null),
            e("redstone_wall_torch", Shape.RS_WALL_TORCH, 0.0F, 0.0F, 0, false, SoundType.WOOD, MapColor.NONE, false, ItemKind.NONE, null, null),
            e("lever", Shape.LEVER, 0.5F, 0.5F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("stone_button", Shape.BUTTON, 0.5F, 0.5F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("oak_button", Shape.BUTTON, 0.5F, 0.5F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("stone_pressure_plate", Shape.PLATE, 0.5F, 0.5F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("oak_pressure_plate", Shape.PLATE, 0.5F, 0.5F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("redstone_wire", Shape.WIRE, 0.0F, 0.0F, 0, false, SoundType.STONE, MapColor.FIRE, false, ItemKind.BLOCK, null, null),
            e("repeater", Shape.REPEATER, 0.0F, 0.0F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("piston", Shape.PISTON, 1.5F, 1.5F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("sticky_piston", Shape.PISTON, 1.5F, 1.5F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("piston_head", Shape.PISTON_HEAD, 1.5F, 1.5F, 0, false, SoundType.STONE, MapColor.STONE, false, ItemKind.NONE, null, null),
            e("rail", Shape.RAIL_FULL, 0.7F, 0.7F, 0, false, SoundType.METAL, MapColor.NONE, false, ItemKind.BLOCK, null, null),
            e("powered_rail", Shape.RAIL_STRAIGHT, 0.7F, 0.7F, 0, false, SoundType.METAL, MapColor.NONE, false, ItemKind.BLOCK, null, null),
            e("detector_rail", Shape.RAIL_STRAIGHT, 0.7F, 0.7F, 0, false, SoundType.METAL, MapColor.NONE, false, ItemKind.BLOCK, null, null),
            e("farmland", Shape.FARMLAND, 0.6F, 0.6F, 0, false, SoundType.GRAVEL, MapColor.DIRT, false, ItemKind.BLOCK, null, null),
            e("wheat", Shape.CROP8, 0.0F, 0.0F, 0, false, SoundType.CROP, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("pumpkin", Shape.SIMPLE, 1.0F, 1.0F, 0, false, SoundType.WOOD, MapColor.COLOR_ORANGE, false, ItemKind.BLOCK, null, null),
            e("carved_pumpkin", Shape.HORIZONTAL, 1.0F, 1.0F, 0, false, SoundType.WOOD, MapColor.COLOR_ORANGE, false, ItemKind.BLOCK, null, null),
            e("jack_o_lantern", Shape.HORIZONTAL, 1.0F, 1.0F, 15, false, SoundType.WOOD, MapColor.COLOR_ORANGE, false, ItemKind.BLOCK, null, null),
            e("melon", Shape.SIMPLE, 1.0F, 1.0F, 0, false, SoundType.WOOD, MapColor.COLOR_LIGHT_GREEN, false, ItemKind.BLOCK, null, null),
            e("pumpkin_stem", Shape.STEM, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.NONE, null, null),
            e("melon_stem", Shape.STEM, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.NONE, null, null),
            e("attached_pumpkin_stem", Shape.ATTACHED_STEM, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.NONE, null, null),
            e("attached_melon_stem", Shape.ATTACHED_STEM, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.NONE, null, null),
            e("sugar_cane", Shape.CANE, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("cactus", Shape.CACTUS, 0.4F, 0.4F, 0, false, SoundType.WOOL, MapColor.PLANT, true, ItemKind.BLOCK, null, null),
            e("dead_bush", Shape.CROSS, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("short_grass", Shape.CROSS, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("fern", Shape.CROSS, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("dandelion", Shape.CROSS, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("poppy", Shape.CROSS, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("brown_mushroom", Shape.CROSS, 0.0F, 0.0F, 1, false, SoundType.GRASS, MapColor.COLOR_BROWN, false, ItemKind.BLOCK, null, null),
            e("red_mushroom", Shape.CROSS, 0.0F, 0.0F, 0, false, SoundType.GRASS, MapColor.COLOR_RED, false, ItemKind.BLOCK, null, null),
            e("cobweb", Shape.CROSS, 4.0F, 4.0F, 0, false, SoundType.COBWEB, MapColor.WOOL, false, ItemKind.BLOCK, null, null),
            e("vine", Shape.VINE, 0.2F, 0.2F, 0, false, SoundType.VINE, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("lily_pad", Shape.LILY, 0.0F, 0.0F, 0, false, SoundType.LILY_PAD, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("mycelium", Shape.GRASS, 0.6F, 0.6F, 0, false, SoundType.GRASS, MapColor.COLOR_PURPLE, false, ItemKind.BLOCK, null, null),
            e("infested_stone", Shape.SIMPLE, 0.75F, 0.75F, 0, false, SoundType.STONE, MapColor.CLAY, false, ItemKind.BLOCK, null, null),
            e("infested_cobblestone", Shape.SIMPLE, 0.75F, 0.75F, 0, false, SoundType.STONE, MapColor.CLAY, false, ItemKind.BLOCK, null, null),
            e("infested_stone_bricks", Shape.SIMPLE, 0.75F, 0.75F, 0, false, SoundType.STONE, MapColor.CLAY, false, ItemKind.BLOCK, null, null),
            e("quartz_block", Shape.SIMPLE, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.QUARTZ, false, ItemKind.BLOCK, null, null),
            e("quartz_pillar", Shape.PILLAR, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.QUARTZ, false, ItemKind.BLOCK, null, null),
            e("quartz_stairs", Shape.STAIRS, 0.8F, 0.8F, 0, true, SoundType.STONE, MapColor.QUARTZ, false, ItemKind.BLOCK, null, "QUARTZ_BLOCK"),
            e("cobblestone_wall", Shape.WALL, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("mossy_cobblestone_wall", Shape.WALL, 2.0F, 6.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.BLOCK, null, null),
            e("red_carpet", Shape.CARPET, 0.1F, 0.1F, 0, false, SoundType.WOOL, MapColor.COLOR_RED, false, ItemKind.BLOCK, null, null),
            e("yellow_carpet", Shape.CARPET, 0.1F, 0.1F, 0, false, SoundType.WOOL, MapColor.COLOR_YELLOW, false, ItemKind.BLOCK, null, null),
            e("anvil", Shape.ANVIL, 5.0F, 1200.0F, 0, true, SoundType.ANVIL, MapColor.METAL, false, ItemKind.BLOCK, null, null),
            e("brewing_stand", Shape.BREWING_STAND, 0.5F, 0.5F, 1, true, SoundType.STONE, MapColor.METAL, true, ItemKind.BLOCK, null, null),
            e("enchanting_table", Shape.ENCHANTING_TABLE, 5.0F, 1200.0F, 7, true, SoundType.STONE, MapColor.COLOR_RED, true, ItemKind.BLOCK, null, null),
            e("ender_chest", Shape.ENDER_CHEST, 22.5F, 600.0F, 7, true, SoundType.STONE, MapColor.COLOR_BLACK, false, ItemKind.BLOCK, null, null),
            e("end_portal_frame", Shape.END_PORTAL_FRAME, -1.0F, 3600000.0F, 1, false, SoundType.GLASS, MapColor.COLOR_GREEN, false, ItemKind.BLOCK, null, null),
            e("spawner", Shape.SIMPLE, 5.0F, 5.0F, 0, true, SoundType.METAL, MapColor.STONE, true, ItemKind.BLOCK, null, null),
            e("redstone_lamp", Shape.RS_LAMP, 0.3F, 0.3F, 0, false, SoundType.GLASS, MapColor.NONE, false, ItemKind.BLOCK, null, null),
            e("nether_portal", Shape.NETHER_PORTAL, -1.0F, 0.0F, 11, false, SoundType.GLASS, MapColor.NETHER, true, ItemKind.NONE, null, null),
            e("fire", Shape.FIRE, 0.0F, 0.0F, 15, false, SoundType.WOOL, MapColor.FIRE, false, ItemKind.NONE, null, null),
            e("oak_fence_gate", Shape.FENCE_GATE, 2.0F, 3.0F, 0, false, SoundType.WOOD, MapColor.WOOD, false, ItemKind.BLOCK, null, null),
            e("oak_wall_sign", Shape.WALL_SIGN, 1.0F, 1.0F, 0, false, SoundType.WOOD, MapColor.WOOD, true, ItemKind.NONE, null, null),
            e("red_bed", Shape.BED, 0.2F, 0.2F, 0, false, SoundType.WOOD, MapColor.COLOR_RED, true, ItemKind.BLOCK, null, null),
            e("carrots", Shape.CROP8, 0.0F, 0.0F, 0, false, SoundType.CROP, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("potatoes", Shape.CROP8, 0.0F, 0.0F, 0, false, SoundType.CROP, MapColor.PLANT, false, ItemKind.BLOCK, null, null),
            e("cocoa", Shape.COCOA, 0.2F, 3.0F, 0, false, SoundType.WOOD, MapColor.PLANT, true, ItemKind.NONE, null, null),
            e("brown_mushroom_block", Shape.MUSHROOM, 0.2F, 0.2F, 0, false, SoundType.WOOD, MapColor.DIRT, false, ItemKind.BLOCK, null, null),
            e("red_mushroom_block", Shape.MUSHROOM, 0.2F, 0.2F, 0, false, SoundType.WOOD, MapColor.COLOR_RED, false, ItemKind.BLOCK, null, null),
            e("mushroom_stem", Shape.MUSHROOM, 0.2F, 0.2F, 0, false, SoundType.WOOD, MapColor.WOOL, false, ItemKind.BLOCK, null, null),
            e("tripwire", Shape.TRIPWIRE, 0.0F, 0.0F, 0, false, SoundType.STONE, MapColor.NONE, false, ItemKind.NONE, null, null),
            e("tripwire_hook", Shape.TRIPWIRE_HOOK, 0.0F, 0.0F, 0, false, SoundType.WOOD, MapColor.NONE, false, ItemKind.BLOCK, null, null),
            e("water_cauldron", Shape.CAULDRON, 2.0F, 2.0F, 0, true, SoundType.STONE, MapColor.STONE, false, ItemKind.NONE, null, null),
            e("potted_dandelion", Shape.POTTED, 0.0F, 0.0F, 0, false, SoundType.STONE, MapColor.NONE, true, ItemKind.NONE, null, null),
            e("potted_poppy", Shape.POTTED, 0.0F, 0.0F, 0, false, SoundType.STONE, MapColor.NONE, true, ItemKind.NONE, null, null),
            e("potted_oak_sapling", Shape.POTTED, 0.0F, 0.0F, 0, false, SoundType.STONE, MapColor.NONE, true, ItemKind.NONE, null, null),
            e("skeleton_skull", Shape.SKULL, 1.0F, 1.0F, 0, false, SoundType.STONE, MapColor.NONE, false, ItemKind.BLOCK, null, null),
            e("wither_skeleton_skull", Shape.SKULL, 1.0F, 1.0F, 0, false, SoundType.STONE, MapColor.COLOR_BLACK, false, ItemKind.BLOCK, null, null),
            e("zombie_head", Shape.SKULL, 1.0F, 1.0F, 0, false, SoundType.STONE, MapColor.COLOR_GREEN, false, ItemKind.BLOCK, null, null),
            e("creeper_head", Shape.SKULL, 1.0F, 1.0F, 0, false, SoundType.STONE, MapColor.COLOR_GREEN, false, ItemKind.BLOCK, null, null),
            e("player_head", Shape.SKULL, 1.0F, 1.0F, 0, false, SoundType.STONE, MapColor.NONE, false, ItemKind.BLOCK, null, null)
    );

    private ClassicBlockList() {}
}
