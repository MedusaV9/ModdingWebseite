package dev.projecteclipse.eclipse.classicblocks;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicAnvilBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicAttachedStemBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicBedBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicBrewingStandBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicButtonBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicCactusBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicCaneBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicCauldronBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicChestBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicCocoaBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicCropBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicDispenserBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicDoorBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicEnchantingTableBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicEndPortalFrameBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicEnderChestBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicFarmlandBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicFenceGateBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicFireBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicFurnaceBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicHorizontalBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicJukeboxBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicLeavesBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicLeverBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicLilyPadBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicMushroomBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicNetherPortalBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicNoteBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicPistonBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicPistonHeadBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicPlantBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicPottedPlantBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicPressurePlateBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRailBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRedstoneLampBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRedstoneOreBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRedstoneTorchBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRedstoneWallTorchBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRedstoneWireBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicRepeaterBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicSaplingBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicSkullBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicSnowLayerBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicSnowyBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicStemBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicStraightRailBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicTntBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicTrapdoorBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicTripwireBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicTripwireHookBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicVineBlock;
import dev.projecteclipse.eclipse.classicblocks.block.ClassicWallSignBlock;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.Registries;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CarpetBlock;
import net.minecraft.world.level.block.FenceBlock;
import net.minecraft.world.level.block.IronBarsBlock;
import net.minecraft.world.level.block.LadderBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.SlabBlock;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.world.level.block.TorchBlock;
import net.minecraft.world.level.block.WallBlock;
import net.minecraft.world.level.block.WallTorchBlock;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockSetType;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.material.PushReaction;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Programmatic registration of every {@code eclipse:classic_*} block from
 * {@link ClassicBlockList} (plan §2.14). All blocks are decorative twins of their vanilla
 * counterparts: same blockstate properties (P5-W7's baked region palettes resolve against
 * them verbatim), same shapes/hardness/tools, but no block entities, no GUIs, no redstone
 * signals, no growth/spread ticking. Doors and trapdoors still open/close by hand.
 */
public final class ClassicBlocks {

    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(Registries.BLOCK, EclipseMod.MOD_ID);

    /**
     * Openable "iron" set type for classic iron doors: the tutorial worlds gate paths with
     * button-driven iron doors, but classic redstone is inert — hand-opening keeps those
     * paths explorable (deliberate deviation, documented in the worker report).
     */
    public static final BlockSetType CLASSIC_IRON = BlockSetType.register(new BlockSetType(
            "eclipse:classic_iron", true, true, false,
            BlockSetType.PressurePlateSensitivity.EVERYTHING, SoundType.METAL,
            SoundEvents.IRON_DOOR_CLOSE, SoundEvents.IRON_DOOR_OPEN,
            SoundEvents.IRON_TRAPDOOR_CLOSE, SoundEvents.IRON_TRAPDOOR_OPEN,
            SoundEvents.METAL_PRESSURE_PLATE_CLICK_OFF, SoundEvents.METAL_PRESSURE_PLATE_CLICK_ON,
            SoundEvents.STONE_BUTTON_CLICK_OFF, SoundEvents.STONE_BUTTON_CLICK_ON));

    /** Vanilla plants that placement may overwrite (mirrors the vanilla twins). */
    private static final Set<String> REPLACEABLE_PLANTS = Set.of("short_grass", "fern", "dead_bush");

    private static final Map<String, Supplier<Block>> BY_ID = new LinkedHashMap<>();

    static {
        for (ClassicBlockList.Entry entry : ClassicBlockList.ENTRIES) {
            BY_ID.put(entry.id(), BLOCKS.register(entry.blockId(), () -> create(entry)));
        }
    }

    private ClassicBlocks() {}

    /** Registered classic block for a vanilla twin path (e.g. {@code "oak_planks"}). */
    public static Supplier<Block> byId(String vanillaPath) {
        Supplier<Block> supplier = BY_ID.get(vanillaPath);
        if (supplier == null) {
            throw new IllegalArgumentException("unknown classic block id: " + vanillaPath);
        }
        return supplier;
    }

    /** All classic blocks keyed by vanilla twin path, in registration order. */
    public static Map<String, Supplier<Block>> all() {
        return Collections.unmodifiableMap(BY_ID);
    }

    public static void register(IEventBus modEventBus) {
        BLOCKS.register(modEventBus);
    }

    // ------------------------------------------------------------------------------

    private static Block create(ClassicBlockList.Entry e) {
        BlockBehaviour.Properties p = props(e);
        return switch (e.shape()) {
            case SIMPLE -> new Block("slippery".equals(e.param()) ? p.friction(0.98F) : p);
            case GRASS -> new ClassicSnowyBlock(p);
            case PILLAR -> new RotatedPillarBlock(p);
            case LEAVES -> new ClassicLeavesBlock(p
                    .isSuffocating(ClassicBlocks::never).isViewBlocking(ClassicBlocks::never));
            case SLAB -> new SlabBlock(p);
            case STAIRS -> new StairBlock(stairsBase(e.param()), p);
            case FENCE -> new FenceBlock(p);
            case PANE -> new IronBarsBlock(p);
            case LADDER -> new LadderBlock(p.noOcclusion());
            case DOOR -> new ClassicDoorBlock(setType(e.param()), p);
            case TRAPDOOR -> new ClassicTrapdoorBlock(setType(e.param()), p);
            case TORCH -> new TorchBlock(ParticleTypes.FLAME, fragile(p));
            case WALL_TORCH -> new WallTorchBlock(ParticleTypes.FLAME, fragile(p));
            case RS_TORCH -> new ClassicRedstoneTorchBlock(fragile(litLight(p, 7)));
            case RS_WALL_TORCH -> new ClassicRedstoneWallTorchBlock(fragile(litLight(p, 7)));
            // Cobweb floats like its vanilla twin (no support check, forceSolidOn).
            case CROSS -> "cobweb".equals(e.id())
                    ? new ClassicPlantBlock(ClassicPlantBlock.PlantShape.FULL, false,
                            fragile(p).forceSolidOn())
                    : new ClassicPlantBlock(crossShape(e.id()), true,
                            REPLACEABLE_PLANTS.contains(e.id()) ? fragile(p).replaceable() : fragile(p));
            case SAPLING -> new ClassicSaplingBlock(fragile(p));
            case CROP8 -> new ClassicCropBlock(fragile(p));
            case CANE -> new ClassicCaneBlock(fragile(p));
            case CACTUS -> new ClassicCactusBlock(p.pushReaction(PushReaction.DESTROY));
            case STEM -> new ClassicStemBlock(fragile(p));
            case ATTACHED_STEM -> new ClassicAttachedStemBlock(fragile(p));
            case FARMLAND -> new ClassicFarmlandBlock(p);
            case SNOW_LAYER -> new ClassicSnowLayerBlock(p.replaceable().forceSolidOff()
                    .pushReaction(PushReaction.DESTROY));
            case FLUID -> new Block(p);
            case CHEST -> new ClassicChestBlock(p);
            case FURNACE_LIKE -> new ClassicFurnaceBlock(p);
            case DISPENSER -> new ClassicDispenserBlock(p);
            case JUKEBOX -> new ClassicJukeboxBlock(p);
            case NOTE_BLOCK -> new ClassicNoteBlock(p);
            case TNT -> new ClassicTntBlock(p);
            case RS_ORE -> new ClassicRedstoneOreBlock(litLight(p, 9));
            case LEVER -> new ClassicLeverBlock(fragile(p));
            case BUTTON -> new ClassicButtonBlock(buttonSetType(e.id()), fragile(p));
            case PLATE -> new ClassicPressurePlateBlock(plateSetType(e.id()), fragile(p));
            case WIRE -> new ClassicRedstoneWireBlock(fragile(p));
            case REPEATER -> new ClassicRepeaterBlock(fragile(p));
            case PISTON -> new ClassicPistonBlock(p);
            case PISTON_HEAD -> new ClassicPistonHeadBlock(p.noLootTable().pushReaction(PushReaction.BLOCK));
            case RAIL_FULL -> new ClassicRailBlock(fragile(p));
            case RAIL_STRAIGHT -> new ClassicStraightRailBlock(fragile(p));
            case VINE -> new ClassicVineBlock(fragile(p).replaceable());
            case LILY -> new ClassicLilyPadBlock(p.pushReaction(PushReaction.DESTROY));
            case HORIZONTAL -> new ClassicHorizontalBlock(p);
            // palette reconciliation (xbox_palette.json)
            case WALL -> new WallBlock(p);
            case CARPET -> new CarpetBlock(p);
            case ANVIL -> new ClassicAnvilBlock(p.pushReaction(PushReaction.BLOCK));
            case BREWING_STAND -> new ClassicBrewingStandBlock(p);
            case ENCHANTING_TABLE -> new ClassicEnchantingTableBlock(p);
            case END_PORTAL_FRAME -> new ClassicEndPortalFrameBlock(p);
            case ENDER_CHEST -> new ClassicEnderChestBlock(p);
            case RS_LAMP -> new ClassicRedstoneLampBlock(litLight(p, 15));
            case NETHER_PORTAL -> new ClassicNetherPortalBlock(
                    p.noCollission().pushReaction(PushReaction.BLOCK));
            case FIRE -> new ClassicFireBlock(fragile(p).replaceable());
            case FENCE_GATE -> new ClassicFenceGateBlock(p);
            case WALL_SIGN -> new ClassicWallSignBlock(fragile(p));
            case BED -> new ClassicBedBlock(p.pushReaction(PushReaction.DESTROY));
            case COCOA -> new ClassicCocoaBlock(p.pushReaction(PushReaction.DESTROY));
            case MUSHROOM -> new ClassicMushroomBlock(p);
            case TRIPWIRE -> new ClassicTripwireBlock(fragile(p));
            case TRIPWIRE_HOOK -> new ClassicTripwireHookBlock(fragile(p));
            case CAULDRON -> new ClassicCauldronBlock(p);
            case POTTED -> new ClassicPottedPlantBlock(p.pushReaction(PushReaction.DESTROY));
            case SKULL -> new ClassicSkullBlock(p.pushReaction(PushReaction.DESTROY));
        };
    }

    private static BlockBehaviour.Properties props(ClassicBlockList.Entry e) {
        BlockBehaviour.Properties p = BlockBehaviour.Properties.of()
                .mapColor(e.mapColor())
                .sound(e.sound())
                .strength(e.hardness(), e.resistance());
        if (e.light() > 0) {
            int light = e.light();
            p.lightLevel(state -> light);
        }
        if (e.requiresTool()) {
            p.requiresCorrectToolForDrops();
        }
        if (e.noOcclusion()) {
            p.noOcclusion();
        }
        return p;
    }

    /** Thin decorative attachments: walk-through, destroyed instead of pushed by pistons. */
    private static BlockBehaviour.Properties fragile(BlockBehaviour.Properties p) {
        return p.noCollission().pushReaction(PushReaction.DESTROY);
    }

    private static BlockBehaviour.Properties litLight(BlockBehaviour.Properties p, int litLevel) {
        return p.lightLevel(state -> state.getValue(BlockStateProperties.LIT) ? litLevel : 0);
    }

    private static boolean never(BlockState state, BlockGetter level, BlockPos pos) {
        return false;
    }

    private static BlockState stairsBase(String param) {
        // Vanilla twin base states; StairBlock keeps them for legacy behaviour lookups only.
        return switch (param) {
            case "OAK_PLANKS" -> Blocks.OAK_PLANKS.defaultBlockState();
            case "SPRUCE_PLANKS" -> Blocks.SPRUCE_PLANKS.defaultBlockState();
            case "BIRCH_PLANKS" -> Blocks.BIRCH_PLANKS.defaultBlockState();
            case "JUNGLE_PLANKS" -> Blocks.JUNGLE_PLANKS.defaultBlockState();
            case "COBBLESTONE" -> Blocks.COBBLESTONE.defaultBlockState();
            case "BRICKS" -> Blocks.BRICKS.defaultBlockState();
            case "STONE_BRICKS" -> Blocks.STONE_BRICKS.defaultBlockState();
            case "SANDSTONE" -> Blocks.SANDSTONE.defaultBlockState();
            case "NETHER_BRICKS" -> Blocks.NETHER_BRICKS.defaultBlockState();
            case "QUARTZ_BLOCK" -> Blocks.QUARTZ_BLOCK.defaultBlockState();
            default -> throw new IllegalArgumentException("unknown stairs base: " + param);
        };
    }

    private static BlockSetType setType(String param) {
        return switch (param) {
            case "OAK" -> BlockSetType.OAK;
            case "IRON" -> CLASSIC_IRON;
            default -> throw new IllegalArgumentException("unknown block set type: " + param);
        };
    }

    private static BlockSetType buttonSetType(String id) {
        return id.startsWith("stone") ? BlockSetType.STONE : BlockSetType.OAK;
    }

    private static BlockSetType plateSetType(String id) {
        return id.startsWith("stone") ? BlockSetType.STONE : BlockSetType.OAK;
    }

    /** Vanilla twin outline shapes for the fixed-pose cross plants. */
    private static ClassicPlantBlock.PlantShape crossShape(String id) {
        return switch (id) {
            case "dandelion", "poppy" -> ClassicPlantBlock.PlantShape.FLOWER;
            case "brown_mushroom", "red_mushroom" -> ClassicPlantBlock.PlantShape.MUSHROOM;
            case "cobweb" -> ClassicPlantBlock.PlantShape.FULL;
            default -> ClassicPlantBlock.PlantShape.BUSH; // short_grass, fern, dead_bush
        };
    }
}
