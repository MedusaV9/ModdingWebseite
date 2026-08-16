package de.sonic0810.goobymod.block;

import com.mojang.serialization.MapCodec;
import de.sonic0810.goobymod.registry.ModSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.LevelAccessor;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.SimpleWaterloggedBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.level.material.Fluids;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Das Gooby-Plüschtier — ein sitzender Stoff-Gooby zum Hinstellen.
 * Knuddeln (Rechtsklick) quietscht und wirft Herzchen; wer darauf
 * landet, plumpst federweich wie auf Gooby-Wolle.
 */
public class GoobyPlushieBlock extends HorizontalDirectionalBlock implements SimpleWaterloggedBlock {
    public static final MapCodec<GoobyPlushieBlock> CODEC = simpleCodec(GoobyPlushieBlock::new);
    public static final BooleanProperty WATERLOGGED = BlockStateProperties.WATERLOGGED;

    // Weicher Korpus (Kollision): Landungen ploppen auf den Pluesch-Body.
    private static final VoxelShape NORTH_BODY = Block.box(3.5, 0, 4.5, 12.5, 11, 13.5);
    private static final VoxelShape SOUTH_BODY = Block.box(3.5, 0, 2.5, 12.5, 11, 11.5);
    private static final VoxelShape EAST_BODY = Block.box(2.5, 0, 3.5, 11.5, 11, 12.5);
    private static final VoxelShape WEST_BODY = Block.box(4.5, 0, 3.5, 13.5, 11, 12.5);

    // Auswahl-/Outline-Shape inkl. Ohren (Modell bis y=15), damit die
    // Hitbox das sichtbare Modell vollstaendig erfasst.
    private static final VoxelShape NORTH_SHAPE = Shapes.or(NORTH_BODY,
            Block.box(5.5, 10.5, 7.75, 10.5, 15, 9.25));
    private static final VoxelShape SOUTH_SHAPE = Shapes.or(SOUTH_BODY,
            Block.box(5.5, 10.5, 6.75, 10.5, 15, 8.25));
    private static final VoxelShape EAST_SHAPE = Shapes.or(EAST_BODY,
            Block.box(6.75, 10.5, 5.5, 8.25, 15, 10.5));
    private static final VoxelShape WEST_SHAPE = Shapes.or(WEST_BODY,
            Block.box(7.75, 10.5, 5.5, 9.25, 15, 10.5));

    public GoobyPlushieBlock(Properties properties) {
        super(properties);
        registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.NORTH)
                .setValue(WATERLOGGED, false));
    }

    @Override
    protected MapCodec<? extends HorizontalDirectionalBlock> codec() {
        return CODEC;
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(FACING, WATERLOGGED);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        FluidState fluid = context.getLevel().getFluidState(context.getClickedPos());
        return defaultBlockState()
                .setValue(FACING, context.getHorizontalDirection().getOpposite())
                .setValue(WATERLOGGED, fluid.getType() == Fluids.WATER);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return switch (state.getValue(FACING)) {
            case SOUTH -> SOUTH_SHAPE;
            case EAST -> EAST_SHAPE;
            case WEST -> WEST_SHAPE;
            default -> NORTH_SHAPE;
        };
    }

    /** Kollision bleibt der weiche Korpus ohne Ohren: man landet IM Pluesch, nicht auf den Ohrspitzen. */
    @Override
    protected VoxelShape getCollisionShape(BlockState state, BlockGetter level, BlockPos pos,
            CollisionContext context) {
        return switch (state.getValue(FACING)) {
            case SOUTH -> SOUTH_BODY;
            case EAST -> EAST_BODY;
            case WEST -> WEST_BODY;
            default -> NORTH_BODY;
        };
    }

    @Override
    protected FluidState getFluidState(BlockState state) {
        return state.getValue(WATERLOGGED) ? Fluids.WATER.getSource(false) : super.getFluidState(state);
    }

    @Override
    protected BlockState updateShape(BlockState state, Direction direction, BlockState neighborState,
            LevelAccessor level, BlockPos pos, BlockPos neighborPos) {
        if (state.getValue(WATERLOGGED)) {
            level.scheduleTick(pos, Fluids.WATER, Fluids.WATER.getTickDelay(level));
        }
        return super.updateShape(state, direction, neighborState, level, pos, neighborPos);
    }

    /**
     * Knuddeln: Quietscher + Herzchen. Bewusst ohne Cooldown — schnelles
     * Klicken quietscht schneller, genau wie Noteblocks (und ein Cooldown
     * braeuchte Zustand pro Position, den ein zustandsloser Block nicht hat).
     */
    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos,
            Player player, BlockHitResult hit) {
        level.playSound(player, pos, ModSounds.GOOBY_SQUEAK.get(), SoundSource.BLOCKS,
                0.6F, 1.1F + level.getRandom().nextFloat() * 0.25F);
        if (level instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.HEART,
                    pos.getX() + 0.5, pos.getY() + 0.85, pos.getZ() + 0.5,
                    2, 0.25, 0.15, 0.25, 0.01);
        }
        return InteractionResult.sidedSuccess(level.isClientSide);
    }

    /** Plueschweich: kein Fallschaden, nur ein leises Quietsch-Plumps. */
    @Override
    public void fallOn(Level level, BlockState state, BlockPos pos, Entity entity, float fallDistance) {
        if (fallDistance > 1.0F && level instanceof ServerLevel serverLevel) {
            serverLevel.playSound(null, pos, SoundEvents.WOOL_FALL, SoundSource.BLOCKS, 0.7F, 0.85F);
            serverLevel.playSound(null, pos, ModSounds.GOOBY_SQUEAK.get(), SoundSource.BLOCKS, 0.5F, 0.8F);
        }
        // Kein super-Aufruf: das Plueschtier daempft jede Landung komplett.
    }
}
