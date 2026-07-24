package dev.projecteclipse.eclipse.lives;

import com.mojang.serialization.MapCodec;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Containers;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.RenderShape;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.entity.BlockEntityTicker;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.BlockHitResult;

import dev.projecteclipse.eclipse.registry.EclipseBlockEntities;

/**
 * Grave placed where a player died, holding their drops in a {@link GraveBlockEntity}.
 * The owner may open it anytime; others only after the configured grace period.
 * Never drops itself (no loot table); removing it by any means scatters the stored items.
 */
public class GraveBlock extends BaseEntityBlock {
    public static final MapCodec<GraveBlock> CODEC = simpleCodec(GraveBlock::new);

    public GraveBlock(Properties properties) {
        super(properties);
    }

    @Override
    protected MapCodec<GraveBlock> codec() {
        return CODEC;
    }

    @Override
    protected RenderShape getRenderShape(BlockState state) {
        return RenderShape.MODEL;
    }

    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new GraveBlockEntity(pos, state);
    }

    @Override
    public <T extends BlockEntity> BlockEntityTicker<T> getTicker(Level level, BlockState state, BlockEntityType<T> type) {
        return level.isClientSide
                ? null
                : createTickerHelper(type, EclipseBlockEntities.GRAVE.get(), GraveBlockEntity::serverTick);
    }

    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos, Player player, BlockHitResult hitResult) {
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(level.getBlockEntity(pos) instanceof GraveBlockEntity grave) || !(player instanceof ServerPlayer serverPlayer)) {
            return InteractionResult.PASS;
        }
        if (!grave.canOpen(serverPlayer)) {
            serverPlayer.displayClientMessage(Component.translatable("block.eclipse.grave.locked"), true);
            return InteractionResult.CONSUME;
        }
        grave.giveTo(serverPlayer);
        return InteractionResult.CONSUME;
    }

    @Override
    protected void onRemove(BlockState state, Level level, BlockPos pos, BlockState newState, boolean movedByPiston) {
        // Safety net: any removal path (mining, explosions, /setblock, ...) scatters stored items
        // instead of voiding them. giveTo()/scatter() empty the BE first, so there is no double drop.
        if (!state.is(newState.getBlock()) && level.getBlockEntity(pos) instanceof GraveBlockEntity grave) {
            for (ItemStack stack : grave.removeAllItems()) {
                Containers.dropItemStack(level, pos.getX() + 0.5D, pos.getY() + 0.5D, pos.getZ() + 0.5D, stack);
            }
            // W13: every removal path (looted, scattered, mined, exploded) unregisters the
            // grave from the Grave Dowser index.
            if (level instanceof ServerLevel serverLevel && grave.getOwnerUuid() != null) {
                EclipseWorldState.get(serverLevel.getServer())
                        .removeGravePosition(grave.getOwnerUuid(), GlobalPos.of(serverLevel.dimension(), pos));
            }
        }
        super.onRemove(state, level, pos, newState, movedByPiston);
    }
}
