package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelAccessor;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CarpetBlock;
import net.minecraft.world.level.block.LeavesBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.NoteBlockInstrument;
import net.minecraft.world.level.material.MapColor;
import net.minecraft.world.level.material.PushReaction;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.neoforge.common.ItemAbilities;
import net.neoforged.neoforge.common.ItemAbility;
import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Pale Garden 1.21.1 port — the pale oak wood set + pale moss family (D6, P1-W1.4).
 * Sapling-less by design (pale oak trees only generate in the {@code eclipse:pale_garden}
 * biome via {@code eclipse:pale_oak_tree}); the Creaking-like mob is P6's and hooks into
 * the biome via a spawner biome modifier, never through this class.
 *
 * <p>Self-contained registry: own deferred registers (wired via
 * {@code PaleGardenBlocks.register(modEventBus)} in {@code EclipseMod} — see
 * {@code docs/plans_v3/wiring/P1-W1.4_wiring.md}; REQUIRED before boot, the pale-garden
 * worldgen JSONs reference these block states) plus an {@code @EventBusSubscriber}
 * creative-tab hook. Axe stripping is handled per-block through
 * {@link net.neoforged.neoforge.common.extensions.IBlockExtension#getToolModifiedState}
 * (the vanilla strippables map is not data-driven in 1.21.1); flammability matches the
 * vanilla wood family values (logs 5/5, planks 5/20, leaves 30/60, hanging moss 15/100).</p>
 */
public final class PaleGardenBlocks {
    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(Registries.BLOCK, EclipseMod.MOD_ID);
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    // --- wood set ---

    public static final Supplier<Block> STRIPPED_PALE_OAK_LOG = BLOCKS.register(
            "stripped_pale_oak_log",
            () -> new FlammablePillarBlock(logProperties(MapColor.QUARTZ, MapColor.QUARTZ), 5, 5));

    public static final Supplier<Block> STRIPPED_PALE_OAK_WOOD = BLOCKS.register(
            "stripped_pale_oak_wood",
            () -> new FlammablePillarBlock(logProperties(MapColor.QUARTZ, MapColor.QUARTZ), 5, 5));

    public static final Supplier<Block> PALE_OAK_LOG = BLOCKS.register("pale_oak_log",
            () -> new StrippablePillarBlock(logProperties(MapColor.QUARTZ, MapColor.STONE),
                    5, 5, STRIPPED_PALE_OAK_LOG));

    public static final Supplier<Block> PALE_OAK_WOOD = BLOCKS.register("pale_oak_wood",
            () -> new StrippablePillarBlock(logProperties(MapColor.STONE, MapColor.STONE),
                    5, 5, STRIPPED_PALE_OAK_WOOD));

    public static final Supplier<Block> PALE_OAK_PLANKS = BLOCKS.register("pale_oak_planks",
            () -> new FlammableBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.QUARTZ)
                    .instrument(NoteBlockInstrument.BASS)
                    .strength(2.0F, 3.0F)
                    .sound(SoundType.WOOD)
                    .ignitedByLava(), 5, 20));

    public static final Supplier<Block> PALE_OAK_LEAVES = BLOCKS.register("pale_oak_leaves",
            () -> new FlammableLeavesBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_LIGHT_GRAY)
                    .strength(0.2F)
                    .randomTicks()
                    .sound(SoundType.GRASS)
                    .noOcclusion()
                    .isValidSpawn((state, level, pos, type) ->
                            type == EntityType.OCELOT || type == EntityType.PARROT)
                    .isSuffocating((state, level, pos) -> false)
                    .isViewBlocking((state, level, pos) -> false)
                    .ignitedByLava()
                    .pushReaction(PushReaction.DESTROY)
                    .isRedstoneConductor((state, level, pos) -> false), 30, 60));

    // --- pale moss family ---

    public static final Supplier<Block> PALE_MOSS_BLOCK = BLOCKS.register("pale_moss_block",
            () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_LIGHT_GRAY)
                    .strength(0.1F)
                    .sound(SoundType.MOSS)
                    .pushReaction(PushReaction.DESTROY)));

    public static final Supplier<Block> PALE_MOSS_CARPET = BLOCKS.register("pale_moss_carpet",
            () -> new CarpetBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_LIGHT_GRAY)
                    .strength(0.1F)
                    .sound(SoundType.MOSS_CARPET)
                    .pushReaction(PushReaction.DESTROY)));

    public static final Supplier<Block> PALE_HANGING_MOSS = BLOCKS.register("pale_hanging_moss",
            () -> new PaleHangingMossBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_LIGHT_GRAY)
                    .noCollission()
                    .instabreak()
                    .sound(SoundType.HANGING_ROOTS)
                    .offsetType(BlockBehaviour.OffsetType.XZ)
                    .pushReaction(PushReaction.DESTROY)
                    .ignitedByLava()));

    // --- block items ---

    public static final Supplier<BlockItem> PALE_OAK_LOG_ITEM =
            blockItem("pale_oak_log", PALE_OAK_LOG);
    public static final Supplier<BlockItem> STRIPPED_PALE_OAK_LOG_ITEM =
            blockItem("stripped_pale_oak_log", STRIPPED_PALE_OAK_LOG);
    public static final Supplier<BlockItem> PALE_OAK_WOOD_ITEM =
            blockItem("pale_oak_wood", PALE_OAK_WOOD);
    public static final Supplier<BlockItem> STRIPPED_PALE_OAK_WOOD_ITEM =
            blockItem("stripped_pale_oak_wood", STRIPPED_PALE_OAK_WOOD);
    public static final Supplier<BlockItem> PALE_OAK_PLANKS_ITEM =
            blockItem("pale_oak_planks", PALE_OAK_PLANKS);
    public static final Supplier<BlockItem> PALE_OAK_LEAVES_ITEM =
            blockItem("pale_oak_leaves", PALE_OAK_LEAVES);
    public static final Supplier<BlockItem> PALE_MOSS_BLOCK_ITEM =
            blockItem("pale_moss_block", PALE_MOSS_BLOCK);
    public static final Supplier<BlockItem> PALE_MOSS_CARPET_ITEM =
            blockItem("pale_moss_carpet", PALE_MOSS_CARPET);
    public static final Supplier<BlockItem> PALE_HANGING_MOSS_ITEM =
            blockItem("pale_hanging_moss", PALE_HANGING_MOSS);

    private PaleGardenBlocks() {}

    private static Supplier<BlockItem> blockItem(String name, Supplier<Block> block) {
        return ITEMS.register(name, () -> new BlockItem(block.get(), new Item.Properties()));
    }

    private static BlockBehaviour.Properties logProperties(MapColor topColor, MapColor sideColor) {
        return BlockBehaviour.Properties.of()
                .mapColor(state -> state.getValue(RotatedPillarBlock.AXIS) == Direction.Axis.Y
                        ? topColor : sideColor)
                .instrument(NoteBlockInstrument.BASS)
                .strength(2.0F)
                .sound(SoundType.WOOD)
                .ignitedByLava();
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
            if (event.getTabKey() == CreativeModeTabs.BUILDING_BLOCKS) {
                event.accept(PALE_OAK_LOG_ITEM.get());
                event.accept(STRIPPED_PALE_OAK_LOG_ITEM.get());
                event.accept(PALE_OAK_WOOD_ITEM.get());
                event.accept(STRIPPED_PALE_OAK_WOOD_ITEM.get());
                event.accept(PALE_OAK_PLANKS_ITEM.get());
            } else if (event.getTabKey() == CreativeModeTabs.NATURAL_BLOCKS) {
                event.accept(PALE_OAK_LOG_ITEM.get());
                event.accept(PALE_OAK_LEAVES_ITEM.get());
                event.accept(PALE_MOSS_BLOCK_ITEM.get());
                event.accept(PALE_MOSS_CARPET_ITEM.get());
                event.accept(PALE_HANGING_MOSS_ITEM.get());
            }
        }
    }

    // --- block behaviour classes (nested: this registry is the file owner) ---

    /** Pillar with wood-family fire data ({@code ignite 5 / burn 5} for logs). */
    static class FlammablePillarBlock extends RotatedPillarBlock {
        private final int fireSpread;
        private final int flammability;

        FlammablePillarBlock(Properties properties, int fireSpread, int flammability) {
            super(properties);
            this.fireSpread = fireSpread;
            this.flammability = flammability;
        }

        @Override
        public boolean isFlammable(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return true;
        }

        @Override
        public int getFireSpreadSpeed(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return this.fireSpread;
        }

        @Override
        public int getFlammability(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return this.flammability;
        }
    }

    /** Bark/log pillar that strips to its {@code stripped} partner on axe use. */
    static final class StrippablePillarBlock extends FlammablePillarBlock {
        private final Supplier<Block> stripped;

        StrippablePillarBlock(Properties properties, int fireSpread, int flammability,
                Supplier<Block> stripped) {
            super(properties, fireSpread, flammability);
            this.stripped = stripped;
        }

        @Override
        public BlockState getToolModifiedState(BlockState state, UseOnContext context,
                ItemAbility itemAbility, boolean simulate) {
            if (itemAbility == ItemAbilities.AXE_STRIP) {
                return this.stripped.get().defaultBlockState()
                        .setValue(RotatedPillarBlock.AXIS, state.getValue(RotatedPillarBlock.AXIS));
            }
            return super.getToolModifiedState(state, context, itemAbility, simulate);
        }
    }

    /** Plain cube with fire data (planks: {@code ignite 5 / burn 20}). */
    static final class FlammableBlock extends Block {
        private final int fireSpread;
        private final int flammability;

        FlammableBlock(Properties properties, int fireSpread, int flammability) {
            super(properties);
            this.fireSpread = fireSpread;
            this.flammability = flammability;
        }

        @Override
        public boolean isFlammable(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return true;
        }

        @Override
        public int getFireSpreadSpeed(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return this.fireSpread;
        }

        @Override
        public int getFlammability(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return this.flammability;
        }
    }

    /** Leaves with fire data ({@code ignite 30 / burn 60}); decay behaviour is vanilla. */
    static final class FlammableLeavesBlock extends LeavesBlock {
        private final int fireSpread;
        private final int flammability;

        FlammableLeavesBlock(Properties properties, int fireSpread, int flammability) {
            super(properties);
            this.fireSpread = fireSpread;
            this.flammability = flammability;
        }

        @Override
        public boolean isFlammable(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return true;
        }

        @Override
        public int getFireSpreadSpeed(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return this.fireSpread;
        }

        @Override
        public int getFlammability(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return this.flammability;
        }
    }

    /**
     * Hanging pale moss strand: survives under any down-sturdy face, under leaves (the
     * pale-oak tree decorator hangs it beneath the canopy — leaves are not sturdy, so a
     * plain hanging-roots clone would pop off) and under itself (player-buildable
     * strands). No collision, instant break, shears-only drop (loot table).
     */
    static final class PaleHangingMossBlock extends Block {
        private static final VoxelShape SHAPE = Block.box(2.0D, 0.0D, 2.0D, 14.0D, 16.0D, 14.0D);

        PaleHangingMossBlock(Properties properties) {
            super(properties);
        }

        @Override
        protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos,
                CollisionContext context) {
            return SHAPE;
        }

        @Override
        protected boolean canSurvive(BlockState state, LevelReader level, BlockPos pos) {
            BlockPos above = pos.above();
            BlockState support = level.getBlockState(above);
            return support.isFaceSturdy(level, above, Direction.DOWN)
                    || support.getBlock() instanceof LeavesBlock
                    || support.is(this);
        }

        @Override
        protected BlockState updateShape(BlockState state, Direction direction, BlockState neighborState,
                LevelAccessor level, BlockPos pos, BlockPos neighborPos) {
            if (direction == Direction.UP && !state.canSurvive(level, pos)) {
                return Blocks.AIR.defaultBlockState();
            }
            return super.updateShape(state, direction, neighborState, level, pos, neighborPos);
        }

        @Override
        public boolean isFlammable(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return true;
        }

        @Override
        public int getFireSpreadSpeed(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return 15;
        }

        @Override
        public int getFlammability(BlockState state, BlockGetter level, BlockPos pos, Direction direction) {
            return 100;
        }
    }
}
