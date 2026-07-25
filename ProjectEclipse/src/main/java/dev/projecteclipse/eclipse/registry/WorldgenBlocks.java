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
