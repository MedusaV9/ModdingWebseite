package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelAccessor;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.NoteBlockInstrument;
import net.minecraft.world.level.material.MapColor;
import net.minecraft.world.level.material.PushReaction;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Signature blocks of the WG2 biome expansion (the eclipse:* ring/cave biomes added in
 * plans_v3 worldgen2): one custom block per new biome, placed exclusively by that
 * biome's worldgen features — none are craftable, all are collectable. Same
 * self-contained registry pattern as {@link PaleGardenBlocks} (deferred registers wired
 * via {@code WorldgenBlocks.register(modEventBus)} in {@code EclipseMod}; REQUIRED
 * before boot — the WG2 configured-feature JSONs reference these block states, and a
 * missing block fails the whole biome out of the datapack).
 *
 * <p>Block ↔ biome map: ash block → {@code eclipse:ashen_forest}, gloomcap →
 * {@code eclipse:gloom_mire}, moonflower → {@code eclipse:moonlit_grove}, amber block →
 * {@code eclipse:amber_savanna}, cinderstone → {@code eclipse:scorched_expanse},
 * glowcap → {@code eclipse:fungal_hollows}, duskstone → {@code eclipse:crystal_chasms},
 * emberstone → {@code eclipse:ember_depths}, umbral bloom →
 * {@code eclipse:umbral_depths}.</p>
 *
 * <p>WG3 (F-059, 10 → 20 biomes) additions: withered sunflower + runestone →
 * {@code eclipse:sunflower_ruins}, voidglass + voidbloom →
 * {@code eclipse:obsidian_wastes}, luster crystal + prism sprouts →
 * {@code eclipse:crystal_steppe}, wisp cap + peat block → {@code eclipse:mist_moor},
 * lumishroom → {@code eclipse:glowshroom_grotto}, scoria + emberbloom →
 * {@code eclipse:molten_veins}, amber tendril → {@code eclipse:tangled_roots}, frost
 * crystal → {@code eclipse:frost_crystal_cavern}, echo crystal →
 * {@code eclipse:echoing_hollow}, sculk gleam → {@code eclipse:sculk_depths}.</p>
 */
public final class WorldgenBlocks {
    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(Registries.BLOCK, EclipseMod.MOD_ID);
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    // --- surface biome blocks ---

    /** Ashen forest ground heaps — soft, shovel-class (minecraft:mineable/shovel tag). */
    public static final Supplier<Block> ASH_BLOCK = BLOCKS.register("ash_block",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_LIGHT_GRAY)
                    .strength(0.5F)
                    .sound(SoundType.SNOW)
                    .pushReaction(PushReaction.DESTROY)));

    /** Gloom-mire mushroom, dim violet shine (light 7). */
    public static final Supplier<Block> GLOOMCAP = BLOCKS.register("gloomcap",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_PURPLE, 7)));

    /** Moonlit-grove flower, bright cold shine (light 10). */
    public static final Supplier<Block> MOONFLOWER = BLOCKS.register("moonflower",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_LIGHT_BLUE, 10)));

    /** Amber-savanna outcrop block, warm glow (light 7); pickaxe-class. */
    public static final Supplier<Block> AMBER_BLOCK = BLOCKS.register("amber_block",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .instrument(NoteBlockInstrument.HAT)
                    .strength(1.5F)
                    .sound(SoundType.AMETHYST)
                    .lightLevel(state -> 7)));

    /** Scorched-expanse charred stone with ember cracks (light 3); pickaxe-class. */
    public static final Supplier<Block> CINDERSTONE = BLOCKS.register("cinderstone",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_BLACK)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(1.5F, 6.0F)
                    .sound(SoundType.BASALT)
                    .lightLevel(state -> 3)));

    // --- cave biome blocks ---

    /** Fungal-hollows mushroom, strong teal shine (light 9). */
    public static final Supplier<Block> GLOWCAP = BLOCKS.register("glowcap",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_CYAN, 9)));

    /** Crystal-chasms sparkle stone, faint shimmer (light 2); pickaxe-class. */
    public static final Supplier<Block> DUSKSTONE = BLOCKS.register("duskstone",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_PURPLE)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(3.0F, 6.0F)
                    .sound(SoundType.DEEPSLATE)
                    .lightLevel(state -> 2)));

    /** Ember-depths smoulder stone (light 5); pickaxe-class. */
    public static final Supplier<Block> EMBERSTONE = BLOCKS.register("emberstone",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_RED)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(1.5F, 6.0F)
                    .sound(SoundType.BASALT)
                    .lightLevel(state -> 5)));

    /** Umbral-depths flower, barely-there violet shimmer (light 3). */
    public static final Supplier<Block> UMBRAL_BLOOM = BLOCKS.register("umbral_bloom",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_PURPLE, 3)));

    // --- WG3 surface biome blocks (F-059) ---

    /** Sunflower-ruins husk flower — dried out, no glow. */
    public static final Supplier<Block> WITHERED_SUNFLOWER = BLOCKS.register("withered_sunflower",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_YELLOW, 0)));

    /** Sunflower-ruins rubble stone with faintly glowing glyphs (light 3); pickaxe-class. */
    public static final Supplier<Block> RUNESTONE = BLOCKS.register("runestone",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_GRAY)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(2.0F, 6.0F)
                    .sound(SoundType.DEEPSLATE)
                    .lightLevel(state -> 3)));

    /** Obsidian-wastes glassy rock, dull violet sheen (light 2); pickaxe-class. */
    public static final Supplier<Block> VOIDGLASS = BLOCKS.register("voidglass",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_BLACK)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(3.0F, 9.0F)
                    .sound(SoundType.DEEPSLATE)
                    .lightLevel(state -> 2)));

    /** Obsidian-wastes flower, violet void shimmer (light 6). */
    public static final Supplier<Block> VOIDBLOOM = BLOCKS.register("voidbloom",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_PURPLE, 6)));

    /** Crystal-steppe crystal boulder, strong cyan shine (light 10); pickaxe-class. */
    public static final Supplier<Block> LUSTER_CRYSTAL = BLOCKS.register("luster_crystal",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_CYAN)
                    .instrument(NoteBlockInstrument.HAT)
                    .strength(1.5F)
                    .sound(SoundType.AMETHYST)
                    .lightLevel(state -> 10)));

    /** Crystal-steppe grass shot through with crystal splinters (light 5). */
    public static final Supplier<Block> PRISM_SPROUTS = BLOCKS.register("prism_sprouts",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_CYAN, 5)));

    /** Mist-moor will-o'-wisp mushroom, pale cold shine (light 8). */
    public static final Supplier<Block> WISP_CAP = BLOCKS.register("wisp_cap",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_LIGHT_BLUE, 8)));

    /** Mist-moor peat ground heaps — soft, shovel-class (minecraft:mineable/shovel tag). */
    public static final Supplier<Block> PEAT_BLOCK = BLOCKS.register("peat_block",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.TERRACOTTA_BROWN)
                    .strength(0.5F)
                    .sound(SoundType.MUD)
                    .pushReaction(PushReaction.DESTROY)));

    // --- WG3 cave biome blocks (F-059) ---

    /** Glowshroom-grotto mushroom, the brightest plant shine of the set (light 12). */
    public static final Supplier<Block> LUMISHROOM = BLOCKS.register("lumishroom",
            () -> new GlowPlantBlock(plantProperties(MapColor.EMERALD, 12)));

    /** Molten-veins porous slag stone, ember glow in the pores (light 4); pickaxe-class. */
    public static final Supplier<Block> SCORIA = BLOCKS.register("scoria",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_BROWN)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(1.5F, 6.0F)
                    .sound(SoundType.BASALT)
                    .lightLevel(state -> 4)));

    /** Molten-veins flower, hot orange flicker (light 7). */
    public static final Supplier<Block> EMBERBLOOM = BLOCKS.register("emberbloom",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_ORANGE, 7)));

    /** Tangled-roots sprout, warm amber glow like its namesake block (light 5). */
    public static final Supplier<Block> AMBER_TENDRIL = BLOCKS.register("amber_tendril",
            () -> new GlowPlantBlock(plantProperties(MapColor.COLOR_ORANGE, 5)));

    /** Frost-crystal-cavern ice crystal, cold blue shine (light 8); pickaxe-class. */
    public static final Supplier<Block> FROST_CRYSTAL = BLOCKS.register("frost_crystal",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.ICE)
                    .instrument(NoteBlockInstrument.HAT)
                    .strength(1.5F)
                    .sound(SoundType.AMETHYST)
                    .lightLevel(state -> 8)));

    /** Echoing-hollow dark crystal, faint teal pulse (light 4); pickaxe-class. */
    public static final Supplier<Block> ECHO_CRYSTAL = BLOCKS.register("echo_crystal",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_CYAN)
                    .instrument(NoteBlockInstrument.HAT)
                    .strength(3.0F, 6.0F)
                    .sound(SoundType.AMETHYST)
                    .lightLevel(state -> 4)));

    /** Sculk-depths accent stone, glowing soul speckles (light 6); pickaxe-class. */
    public static final Supplier<Block> SCULK_GLEAM = BLOCKS.register("sculk_gleam",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_CYAN)
                    .instrument(NoteBlockInstrument.BASEDRUM)
                    .strength(1.5F, 6.0F)
                    .sound(SoundType.SCULK)
                    .lightLevel(state -> 6)));

    // --- block items ---

    public static final Supplier<BlockItem> ASH_BLOCK_ITEM = blockItem("ash_block", ASH_BLOCK);
    public static final Supplier<BlockItem> GLOOMCAP_ITEM = blockItem("gloomcap", GLOOMCAP);
    public static final Supplier<BlockItem> MOONFLOWER_ITEM = blockItem("moonflower", MOONFLOWER);
    public static final Supplier<BlockItem> AMBER_BLOCK_ITEM = blockItem("amber_block", AMBER_BLOCK);
    public static final Supplier<BlockItem> CINDERSTONE_ITEM = blockItem("cinderstone", CINDERSTONE);
    public static final Supplier<BlockItem> GLOWCAP_ITEM = blockItem("glowcap", GLOWCAP);
    public static final Supplier<BlockItem> DUSKSTONE_ITEM = blockItem("duskstone", DUSKSTONE);
    public static final Supplier<BlockItem> EMBERSTONE_ITEM = blockItem("emberstone", EMBERSTONE);
    public static final Supplier<BlockItem> UMBRAL_BLOOM_ITEM = blockItem("umbral_bloom", UMBRAL_BLOOM);
    public static final Supplier<BlockItem> WITHERED_SUNFLOWER_ITEM =
            blockItem("withered_sunflower", WITHERED_SUNFLOWER);
    public static final Supplier<BlockItem> RUNESTONE_ITEM = blockItem("runestone", RUNESTONE);
    public static final Supplier<BlockItem> VOIDGLASS_ITEM = blockItem("voidglass", VOIDGLASS);
    public static final Supplier<BlockItem> VOIDBLOOM_ITEM = blockItem("voidbloom", VOIDBLOOM);
    public static final Supplier<BlockItem> LUSTER_CRYSTAL_ITEM =
            blockItem("luster_crystal", LUSTER_CRYSTAL);
    public static final Supplier<BlockItem> PRISM_SPROUTS_ITEM =
            blockItem("prism_sprouts", PRISM_SPROUTS);
    public static final Supplier<BlockItem> WISP_CAP_ITEM = blockItem("wisp_cap", WISP_CAP);
    public static final Supplier<BlockItem> PEAT_BLOCK_ITEM = blockItem("peat_block", PEAT_BLOCK);
    public static final Supplier<BlockItem> LUMISHROOM_ITEM = blockItem("lumishroom", LUMISHROOM);
    public static final Supplier<BlockItem> SCORIA_ITEM = blockItem("scoria", SCORIA);
    public static final Supplier<BlockItem> EMBERBLOOM_ITEM = blockItem("emberbloom", EMBERBLOOM);
    public static final Supplier<BlockItem> AMBER_TENDRIL_ITEM =
            blockItem("amber_tendril", AMBER_TENDRIL);
    public static final Supplier<BlockItem> FROST_CRYSTAL_ITEM =
            blockItem("frost_crystal", FROST_CRYSTAL);
    public static final Supplier<BlockItem> ECHO_CRYSTAL_ITEM =
            blockItem("echo_crystal", ECHO_CRYSTAL);
    public static final Supplier<BlockItem> SCULK_GLEAM_ITEM = blockItem("sculk_gleam", SCULK_GLEAM);

    private WorldgenBlocks() {}

    private static Supplier<BlockItem> blockItem(String name, Supplier<Block> block) {
        return ITEMS.register(name, () -> new BlockItem(block.get(), new Item.Properties()));
    }

    private static BlockBehaviour.Properties plantProperties(MapColor color, int light) {
        return BlockBehaviour.Properties.of()
                .mapColor(color)
                .noCollission()
                .instabreak()
                .sound(SoundType.GRASS)
                .offsetType(BlockBehaviour.OffsetType.XZ)
                .pushReaction(PushReaction.DESTROY)
                .lightLevel(state -> light);
    }

    /** Orchestrator wiring point ({@code EclipseMod} mod constructor). */
    public static void register(IEventBus modEventBus) {
        BLOCKS.register(modEventBus);
        ITEMS.register(modEventBus);
    }

    /** Vanilla-tab visibility (mod-bus event, auto-discovered — no EclipseMod line needed). */
    @net.neoforged.fml.common.EventBusSubscriber(modid = EclipseMod.MOD_ID)
    static final class TabContents {
        private TabContents() {}

        @SubscribeEvent
        static void onBuildCreativeTabs(BuildCreativeModeTabContentsEvent event) {
            if (event.getTabKey() == CreativeModeTabs.NATURAL_BLOCKS) {
                event.accept(ASH_BLOCK_ITEM.get());
                event.accept(GLOOMCAP_ITEM.get());
                event.accept(MOONFLOWER_ITEM.get());
                event.accept(AMBER_BLOCK_ITEM.get());
                event.accept(CINDERSTONE_ITEM.get());
                event.accept(GLOWCAP_ITEM.get());
                event.accept(DUSKSTONE_ITEM.get());
                event.accept(EMBERSTONE_ITEM.get());
                event.accept(UMBRAL_BLOOM_ITEM.get());
                event.accept(WITHERED_SUNFLOWER_ITEM.get());
                event.accept(RUNESTONE_ITEM.get());
                event.accept(VOIDGLASS_ITEM.get());
                event.accept(VOIDBLOOM_ITEM.get());
                event.accept(LUSTER_CRYSTAL_ITEM.get());
                event.accept(PRISM_SPROUTS_ITEM.get());
                event.accept(WISP_CAP_ITEM.get());
                event.accept(PEAT_BLOCK_ITEM.get());
                event.accept(LUMISHROOM_ITEM.get());
                event.accept(SCORIA_ITEM.get());
                event.accept(EMBERBLOOM_ITEM.get());
                event.accept(AMBER_TENDRIL_ITEM.get());
                event.accept(FROST_CRYSTAL_ITEM.get());
                event.accept(ECHO_CRYSTAL_ITEM.get());
                event.accept(SCULK_GLEAM_ITEM.get());
            }
        }
    }

    /**
     * Small decorative glow plant (flowers + mushrooms of the WG2 biomes): flower-sized
     * cross model, no collision, instant break, survives on any up-sturdy face (grass,
     * dirt, stone AND deepslate — the cave plants seed onto bare cave floors, so no
     * dirt-tag restriction). Deliberately extends {@link Block} rather than the vanilla
     * bush hierarchy — same reasoning as {@code PaleGardenBlocks.PaleHangingMossBlock}
     * (full control of the survive predicate, no codec/bone-meal baggage).
     */
    static final class GlowPlantBlock extends Block {
        private static final VoxelShape SHAPE = Block.box(5.0D, 0.0D, 5.0D, 11.0D, 12.0D, 11.0D);

        GlowPlantBlock(Properties properties) {
            super(properties);
        }

        @Override
        protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos,
                CollisionContext context) {
            Vec3 offset = state.getOffset(level, pos);
            return SHAPE.move(offset.x, offset.y, offset.z);
        }

        @Override
        protected boolean canSurvive(BlockState state, LevelReader level, BlockPos pos) {
            BlockPos below = pos.below();
            return level.getBlockState(below).isFaceSturdy(level, below, Direction.UP);
        }

        @Override
        protected BlockState updateShape(BlockState state, Direction direction, BlockState neighborState,
                LevelAccessor level, BlockPos pos, BlockPos neighborPos) {
            if (direction == Direction.DOWN && !state.canSurvive(level, pos)) {
                return Blocks.AIR.defaultBlockState();
            }
            return super.updateShape(state, direction, neighborState, level, pos, neighborPos);
        }
    }
}
