package de.sonic0810.goobymod.block;

import com.mojang.serialization.MapCodec;
import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.Comparator;
import java.util.List;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * A cake covered with one jar of Nutella. It is a persistent ritual focus:
 * eligible parents may arrive after it was prepared, while pair cooldowns live
 * on the parents so replacing the cake cannot bypass the family limit.
 */
public final class NutellaCakeBlock extends Block {
    public static final MapCodec<NutellaCakeBlock> CODEC = simpleCodec(NutellaCakeBlock::new);
    private static final VoxelShape SHAPE = Block.box(1.0, 0.0, 1.0, 15.0, 8.0, 15.0);
    private static final double RITUAL_RADIUS = 6.0;

    public NutellaCakeBlock(Properties properties) {
        super(properties);
    }

    @Override
    protected MapCodec<? extends Block> codec() {
        return CODEC;
    }

    @Override
    protected VoxelShape getShape(BlockState state, net.minecraft.world.level.BlockGetter level, BlockPos pos,
            CollisionContext context) {
        return SHAPE;
    }

    @Override
    protected void onPlace(BlockState state, Level level, BlockPos pos, BlockState oldState, boolean movedByPiston) {
        super.onPlace(state, level, pos, oldState, movedByPiston);
        if (!level.isClientSide) {
            level.scheduleTick(pos, this, 20);
        }
    }

    @Override
    protected void tick(BlockState state, ServerLevel level, BlockPos pos, RandomSource random) {
        if (!tryRitual(level, pos, null)) {
            level.scheduleTick(pos, this, 20);
        }
    }

    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos, Player player,
            BlockHitResult hitResult) {
        if (!level.isClientSide && level instanceof ServerLevel serverLevel) {
            tryRitual(serverLevel, pos, player);
        }
        return InteractionResult.sidedSuccess(level.isClientSide);
    }

    /**
     * Performs the whole ritual on the server thread. The cake is removed
     * before this method returns, making repeated calls in the same tick safe.
     */
    public static boolean tryRitual(ServerLevel level, BlockPos pos, @Nullable Player initiator) {
        if (!level.getBlockState(pos).is(ModBlocks.NUTELLA_CAKE.get())) {
            return false;
        }
        List<GoobyEntity> nearbyAdults = level.getEntitiesOfClass(GoobyEntity.class,
                new AABB(pos).inflate(RITUAL_RADIUS),
                gooby -> gooby.isAlive() && gooby.isTame() && !gooby.isBaby());
        nearbyAdults.sort(Comparator.comparing(GoobyEntity::getUUID));

        long now = level.getGameTime();
        GoobyEntity first = null;
        GoobyEntity second = null;
        for (int left = 0; left < nearbyAdults.size() && first == null; left++) {
            for (int right = left + 1; right < nearbyAdults.size(); right++) {
                GoobyEntity candidateA = nearbyAdults.get(left);
                GoobyEntity candidateB = nearbyAdults.get(right);
                if (candidateA.canStartFamilyWith(candidateB, now)) {
                    first = candidateA;
                    second = candidateB;
                    break;
                }
            }
        }

        if (first == null || second == null) {
            if (initiator != null) {
                boolean hasTwoBonded = nearbyAdults.stream().filter(GoobyEntity::isFamilyRitualEligible).count() >= 2;
                initiator.displayClientMessage(Component.translatable(hasTwoBonded
                        ? "msg.goobymod.ritual_cooldown" : "msg.goobymod.ritual_requires_friend"), true);
            }
            return false;
        }

        GoobyEntity baby = first.createRitualOffspring(level, second, initiator, familyNest(level, pos));
        if (baby == null) {
            return false;
        }
        baby.moveTo(pos.getX() + 0.5, pos.getY(), pos.getZ() + 0.5,
                level.random.nextFloat() * 360.0F, 0.0F);
        if (!level.addFreshEntity(baby)) {
            return false;
        }

        // The pair lease is committed only after the child exists.
        first.recordFamilyRitual(second, now);
        second.recordFamilyRitual(first, now);
        first.setInLove(initiator);
        second.setInLove(initiator);
        first.tryTriggerAction("parent_nuzzle", 34);
        second.tryTriggerAction("parent_nuzzle", 34);
        level.removeBlock(pos, false);
        level.sendParticles(ParticleTypes.HEART, baby.getX(), baby.getY() + 0.8, baby.getZ(),
                18, 0.9, 0.5, 0.9, 0.04);
        level.sendParticles(ParticleTypes.HAPPY_VILLAGER, baby.getX(), baby.getY() + 0.5, baby.getZ(),
                12, 0.7, 0.35, 0.7, 0.03);
        level.playSound(null, pos, ModSounds.GOOBY_NUZZLE.get(), SoundSource.NEUTRAL, 0.9F, 1.0F);

        grantFamilyAdvancement(initiator);
        grantFamilyAdvancement(first.getOwner());
        grantFamilyAdvancement(second.getOwner());
        if (initiator != null) {
            initiator.displayClientMessage(Component.translatable("msg.goobymod.ritual_success",
                    baby.getName()), true);
        }
        return true;
    }

    private static BlockPos familyNest(ServerLevel level, BlockPos ritualPos) {
        return BlockPos.findClosestMatch(ritualPos, 8, 4,
                        candidate -> level.getBlockState(candidate).is(ModBlocks.RABBIT_HUTCH.get()))
                .map(hutch -> {
                    Direction facing = level.getBlockState(hutch).getValue(HorizontalDirectionalBlock.FACING);
                    return hutch.relative(facing);
                })
                .orElse(ritualPos);
    }

    private static void grantFamilyAdvancement(@Nullable net.minecraft.world.entity.LivingEntity entity) {
        if (entity instanceof ServerPlayer player) {
            GoobyAdvancements.grant(player, GoobyAdvancements.GOOBY_FAMILY);
        }
    }
}
