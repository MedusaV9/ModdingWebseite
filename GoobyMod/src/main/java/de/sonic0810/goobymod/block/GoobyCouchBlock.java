package de.sonic0810.goobymod.block;

import com.mojang.serialization.MapCodec;
import de.sonic0810.goobymod.entity.CouchSeatEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
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
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Die Gooby-Woll-Couch — das gemuetlichste Moebelstueck der Welt.
 * Spieler setzen sich per Rechtsklick drauf (unsichtbares Sitz-Entity),
 * Goobys waehlen sie nachts als bevorzugten Nickerchen-Platz, und wer
 * drauffaellt, landet federweich wie auf Gooby-Wolle.
 *
 * <p>Bewusst EIN Block mit Facing (wie Pluesch und Stall): kein
 * Multiblock-Zustand, der beim halben Abbau Geister-Haelften hinterlaesst.
 */
public class GoobyCouchBlock extends HorizontalDirectionalBlock implements SimpleWaterloggedBlock {
    public static final MapCodec<GoobyCouchBlock> CODEC = simpleCodec(GoobyCouchBlock::new);
    public static final BooleanProperty WATERLOGGED = BlockStateProperties.WATERLOGGED;

    /** Oberkante des Sitzkissens in Blockhoehe (Modell: y=8/16). */
    public static final double CUSHION_TOP = 0.5;

    // Modellraum (facing=NORTH): Front zeigt nach Norden, Lehne liegt auf der
    // Suedseite (z 13..16), Seitenpolster links/rechts (z 8..16).
    private static final double[][] SHAPE_BOXES = {
            {0, 0, 3, 16, 8, 16},    // Sockel, Kissen und Fuesse (unterer Rumpf)
            {2, 8, 13, 14, 13, 16},  // Rueckenlehne oberhalb des Kissens
            {0, 8, 8, 2, 12, 16},    // Seitenpolster (Modell-Ost)
            {14, 8, 8, 16, 12, 16},  // Seitenpolster (Modell-West)
    };

    private static final VoxelShape NORTH_SHAPE = buildShape(Direction.NORTH);
    private static final VoxelShape SOUTH_SHAPE = buildShape(Direction.SOUTH);
    private static final VoxelShape EAST_SHAPE = buildShape(Direction.EAST);
    private static final VoxelShape WEST_SHAPE = buildShape(Direction.WEST);

    public GoobyCouchBlock(Properties properties) {
        super(properties);
        registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.NORTH)
                .setValue(WATERLOGGED, false));
    }

    private static VoxelShape buildShape(Direction facing) {
        VoxelShape shape = Shapes.empty();
        for (double[] box : SHAPE_BOXES) {
            shape = Shapes.or(shape, rotatedBox(facing, box));
        }
        return shape;
    }

    /** Rotiert eine NORTH-Modellbox in die Facing-Richtung (gleiche Ableitung wie beim Pluesch). */
    private static VoxelShape rotatedBox(Direction facing, double[] box) {
        double x0 = box[0];
        double y0 = box[1];
        double z0 = box[2];
        double x1 = box[3];
        double y1 = box[4];
        double z1 = box[5];
        return switch (facing) {
            case SOUTH -> Block.box(16 - x1, y0, 16 - z1, 16 - x0, y1, 16 - z0);
            case EAST -> Block.box(16 - z1, y0, x0, 16 - z0, y1, x1);
            case WEST -> Block.box(z0, y0, 16 - x1, z1, y1, 16 - x0);
            default -> Block.box(x0, y0, z0, x1, y1, z1);
        };
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

    /** Rechtsklick mit leerer Hand: hinsetzen (serverautoritativ ueber das Sitz-Entity). */
    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos,
            Player player, BlockHitResult hit) {
        if (player.isPassenger() || player.isShiftKeyDown()) {
            return InteractionResult.PASS;
        }
        if (level instanceof ServerLevel serverLevel && !CouchSeatEntity.seatPlayer(serverLevel, pos, player)) {
            return InteractionResult.CONSUME;
        }
        if (level.isClientSide) {
            level.playLocalSound(pos, SoundEvents.WOOL_STEP, SoundSource.BLOCKS, 0.7F, 0.9F, false);
        }
        return InteractionResult.sidedSuccess(level.isClientSide);
    }

    /** Beim Abbau steht ein sitzender Spieler sofort wieder auf (Sitz-Entity raeumt sich selbst ab). */
    @Override
    protected void onRemove(BlockState state, Level level, BlockPos pos, BlockState newState, boolean moved) {
        if (!state.is(newState.getBlock()) && level instanceof ServerLevel serverLevel) {
            for (CouchSeatEntity seat : serverLevel.getEntitiesOfClass(CouchSeatEntity.class,
                    new AABB(pos))) {
                seat.ejectPassengers();
                seat.discard();
            }
        }
        super.onRemove(state, level, pos, newState, moved);
    }

    /** Wollweich: kein Fallschaden — nur ein flauschiges Plumps wie auf Gooby-Wolle. */
    @Override
    public void fallOn(Level level, BlockState state, BlockPos pos, Entity entity, float fallDistance) {
        if (fallDistance > 1.5F && level instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.CLOUD,
                    entity.getX(), pos.getY() + CUSHION_TOP + 0.55, entity.getZ(), 5, 0.25, 0.05, 0.25, 0.02);
            level.playSound(null, pos, SoundEvents.WOOL_FALL, SoundSource.BLOCKS, 0.7F, 0.9F);
        }
        // Kein super-Aufruf: die Couch daempft jede Landung komplett.
    }

    /** Sitzanker fuer das unsichtbare Sitz-Entity (mittig auf dem Kissen). */
    public static Vec3 seatAnchor(BlockPos pos) {
        return Vec3.atBottomCenterOf(pos).add(0.0, 0.28, 0.0);
    }

    /** Nickerchen-Anker: Gooby kuschelt sich mittig auf das Sitzkissen. */
    public static Vec3 napAnchor(BlockPos pos) {
        return Vec3.atBottomCenterOf(pos).add(0.0, CUSHION_TOP, 0.0);
    }

    /** Anlauf-/Absprungpunkt vor der Couch-Front. */
    public static Vec3 frontAnchor(BlockPos pos, Direction facing) {
        return Vec3.atBottomCenterOf(pos.relative(facing));
    }

    /**
     * Frei fuer ein Gooby-Nickerchen? Couch steht noch, kein sitzender Spieler
     * (belegtes Sitz-Entity) und kein ANDERER bereits schlafender Gooby auf dem
     * Kissen.
     */
    public static boolean isNapSpotFree(Level level, BlockPos pos, GoobyEntity self) {
        if (!(level.getBlockState(pos).getBlock() instanceof GoobyCouchBlock)) {
            return false;
        }
        if (!level.getEntitiesOfClass(CouchSeatEntity.class, new AABB(pos),
                seat -> seat.isVehicle()).isEmpty()) {
            return false;
        }
        Vec3 anchor = napAnchor(pos);
        return level.getEntitiesOfClass(GoobyEntity.class, new AABB(pos).inflate(0.5),
                gooby -> gooby != self && gooby.isGoobySleeping()
                        && gooby.position().distanceToSqr(anchor) < 1.0).isEmpty();
    }
}
