package de.sonic0810.goobymod.block;

import com.mojang.serialization.MapCodec;
import de.sonic0810.goobymod.block.entity.RabbitHutchBlockEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModParticles;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.Comparator;
import java.util.UUID;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.tags.ItemTags;
import net.minecraft.util.RandomSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.ItemInteractionResult;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.level.pathfinder.PathComputationType;
import net.minecraft.world.level.pathfinder.PathType;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;
import net.minecraft.world.phys.shapes.Shapes;

/**
 * Der Hasenstall — Goobys Zuhause. Nachts kuschelt er sich hinein,
 * morgens gibt es Herzchen.
 */
public class RabbitHutchBlock extends BaseEntityBlock {
    public static final MapCodec<RabbitHutchBlock> CODEC = simpleCodec(RabbitHutchBlock::new);
    public static final int MAX_COMFORT = 3;
    public static final IntegerProperty BEDDING = IntegerProperty.create("bedding", 0, MAX_COMFORT);

    private static final VoxelShape FLOOR = Block.box(1, 0, 1, 15, 1, 15);
    private static final VoxelShape ROOF = Block.box(0, 10, 0, 16, 13, 16);
    private static final VoxelShape NORTH_SHAPE = Shapes.or(FLOOR, ROOF,
            Block.box(1, 1, 1, 2, 10, 15), Block.box(14, 1, 1, 15, 10, 15),
            Block.box(2, 1, 14, 14, 10, 15),
            Block.box(2, 1, 1, 4, 10, 2), Block.box(12, 1, 1, 14, 10, 2));
    private static final VoxelShape SOUTH_SHAPE = Shapes.or(FLOOR, ROOF,
            Block.box(1, 1, 1, 2, 10, 15), Block.box(14, 1, 1, 15, 10, 15),
            Block.box(2, 1, 1, 14, 10, 2),
            Block.box(2, 1, 14, 4, 10, 15), Block.box(12, 1, 14, 14, 10, 15));
    private static final VoxelShape EAST_SHAPE = Shapes.or(FLOOR, ROOF,
            Block.box(1, 1, 1, 15, 10, 2), Block.box(1, 1, 14, 15, 10, 15),
            Block.box(1, 1, 2, 2, 10, 14),
            Block.box(14, 1, 2, 15, 10, 4), Block.box(14, 1, 12, 15, 10, 14));
    private static final VoxelShape WEST_SHAPE = Shapes.or(FLOOR, ROOF,
            Block.box(1, 1, 1, 15, 10, 2), Block.box(1, 1, 14, 15, 10, 15),
            Block.box(14, 1, 2, 15, 10, 14),
            Block.box(1, 1, 2, 2, 10, 4), Block.box(1, 1, 12, 2, 10, 14));

    public RabbitHutchBlock(Properties properties) {
        super(properties);
        registerDefaultState(this.stateDefinition.any()
                .setValue(HorizontalDirectionalBlock.FACING, Direction.NORTH)
                .setValue(BEDDING, 0));
    }

    @Override
    protected MapCodec<? extends BaseEntityBlock> codec() {
        return CODEC;
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(HorizontalDirectionalBlock.FACING, BEDDING);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        return defaultBlockState().setValue(HorizontalDirectionalBlock.FACING,
                context.getHorizontalDirection().getOpposite());
    }

    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new RabbitHutchBlockEntity(pos, state);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return switch (state.getValue(HorizontalDirectionalBlock.FACING)) {
            case SOUTH -> SOUTH_SHAPE;
            case EAST -> EAST_SHAPE;
            case WEST -> WEST_SHAPE;
            default -> NORTH_SHAPE;
        };
    }

    /**
     * The one-block model is a visual shell with an open entrance. Gooby is
     * wider than one block, so wall collision would make its promised sleep
     * anchor physically unreachable; the shell is intentionally non-solid.
     */
    @Override
    protected VoxelShape getCollisionShape(BlockState state, BlockGetter level, BlockPos pos,
            CollisionContext context) {
        return Shapes.empty();
    }

    @Override
    protected boolean isPathfindable(BlockState state, PathComputationType type) {
        return type == PathComputationType.LAND;
    }

    @Override
    public PathType getBlockPathType(BlockState state, BlockGetter level, BlockPos pos, @Nullable Mob mob) {
        return PathType.OPEN;
    }

    @Override
    public void animateTick(BlockState state, Level level, BlockPos pos, RandomSource random) {
        if (!(level.getBlockEntity(pos) instanceof RabbitHutchBlockEntity hutch)
                || !hutch.isOccupied() || random.nextInt(3) != 0) {
            return;
        }
        Direction facing = state.getValue(HorizontalDirectionalBlock.FACING);
        Vec3 entrance = Vec3.atBottomCenterOf(pos.relative(facing))
                .add(-facing.getStepX() * 0.32, 0.72 + random.nextDouble() * 0.22,
                        -facing.getStepZ() * 0.32);
        level.addParticle(ModParticles.ZZZ.get(),
                entrance.x + (random.nextDouble() - 0.5) * 0.22,
                entrance.y,
                entrance.z + (random.nextDouble() - 0.5) * 0.22,
                0.0, 0.025, 0.0);
    }

    @Override
    protected ItemInteractionResult useItemOn(ItemStack stack, BlockState state, Level level, BlockPos pos,
            Player player, InteractionHand hand, BlockHitResult hit) {
        if (!(level.getBlockEntity(pos) instanceof RabbitHutchBlockEntity hutch)) {
            return ItemInteractionResult.PASS_TO_DEFAULT_BLOCK_INTERACTION;
        }
        if (stack.is(ItemTags.WOOL)) {
            if (state.getValue(BEDDING) >= MAX_COMFORT) {
                player.displayClientMessage(Component.translatable("msg.goobymod.hutch_bedding_max"), true);
                return ItemInteractionResult.sidedSuccess(level.isClientSide);
            }
            if (!level.isClientSide) {
                int comfort = state.getValue(BEDDING) + 1;
                level.setBlock(pos, state.setValue(BEDDING, comfort), 3);
                hutch.setComfort(comfort);
                if (!player.getAbilities().instabuild) {
                    stack.shrink(1);
                }
                player.displayClientMessage(Component.translatable(
                        "msg.goobymod.hutch_bedding_upgraded", comfort, MAX_COMFORT), true);
                level.playSound(null, pos, ModSounds.GOOBY_HUTCH_RUSTLE.get(),
                        net.minecraft.sounds.SoundSource.BLOCKS, 0.75F, 1.0F + comfort * 0.05F);
            }
            return ItemInteractionResult.sidedSuccess(level.isClientSide);
        }
        if (stack.is(Items.NAME_TAG)) {
            if (!level.isClientSide) {
                GoobyEntity resident = findNearestOwnedGooby(level, pos, player);
                if (resident == null) {
                    player.displayClientMessage(Component.translatable("msg.goobymod.hutch_no_resident"), true);
                    return ItemInteractionResult.SUCCESS;
                }
                Component tagName = stack.get(DataComponents.CUSTOM_NAME);
                if (tagName != null) {
                    resident.setCustomName(tagName);
                } else {
                    player.displayClientMessage(Component.translatable("msg.goobymod.hutch_name_tag_empty"), true);
                    return ItemInteractionResult.SUCCESS;
                }
                hutch.bind(resident);
                resident.setHomePos(pos);
                if (!player.getAbilities().instabuild) {
                    stack.shrink(1);
                }
                player.displayClientMessage(Component.translatable(
                        "msg.goobymod.hutch_bound", resident.getName()), true);
                level.playSound(null, pos, ModSounds.GOOBY_HUTCH_CREAK.get(),
                        net.minecraft.sounds.SoundSource.BLOCKS, 0.7F, 1.05F);
            }
            return ItemInteractionResult.sidedSuccess(level.isClientSide);
        }
        return ItemInteractionResult.PASS_TO_DEFAULT_BLOCK_INTERACTION;
    }

    @Override
    protected void onRemove(BlockState state, Level level, BlockPos pos, BlockState newState, boolean moved) {
        if (!state.is(newState.getBlock())) {
            if (level.getBlockEntity(pos) instanceof RabbitHutchBlockEntity hutch) {
                UUID occupantId = hutch.getOccupant();
                if (occupantId != null && level instanceof net.minecraft.server.level.ServerLevel serverLevel
                        && serverLevel.getEntity(occupantId) instanceof GoobyEntity gooby) {
                    gooby.ejectFromBrokenHutch(pos, state.getValue(HorizontalDirectionalBlock.FACING));
                }
            }
            level.playSound(null, pos, ModSounds.GOOBY_HUTCH_CREAK.get(),
                    net.minecraft.sounds.SoundSource.BLOCKS, 0.85F, 0.8F);
        }
        super.onRemove(state, level, pos, newState, moved);
    }

    @Nullable
    private static GoobyEntity findNearestOwnedGooby(Level level, BlockPos pos, Player player) {
        return level.getEntitiesOfClass(GoobyEntity.class, new AABB(pos).inflate(16.0),
                        gooby -> gooby.isOwnedBy(player))
                .stream()
                .min(Comparator.comparingDouble(gooby -> gooby.distanceToSqr(pos.getCenter())))
                .orElse(null);
    }

    public static Vec3 interiorAnchor(BlockPos pos) {
        return Vec3.atBottomCenterOf(pos).add(0.0, 0.08, 0.0);
    }

    public static Vec3 exitAnchor(BlockPos pos, Direction facing) {
        return Vec3.atBottomCenterOf(pos.relative(facing));
    }
}
