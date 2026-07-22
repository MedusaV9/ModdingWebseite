package dev.projecteclipse.eclipse.entity;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.PathfinderMob;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;

/**
 * Deckhand — the mute rowing crew of the limbo ghost ship ({@code docs/ideas/04_content.md}
 * §1.4). Pure ambience: no AI beyond an occasional {@link LookAtPlayerGoal} (it sometimes
 * tracks a passing ghost), invulnerable, unpushable, silent, and it refuses to exist
 * outside the limbo dimension. The rowing animation is procedural client-side
 * ({@code arm.xRot = -1.2 + sin(age*0.08)*0.35}) and matches the block-display oars'
 * cadence ({@code limbo.OarAnimator}).
 *
 * <p>{@link #ensureCrew} seats one deckhand at each of the eight oar benches, once per
 * world — guarded exactly like the oars: entity UUIDs persist in
 * {@link EclipseWorldState#getDeckhandEntities()}, so restarts re-attach instead of
 * re-spawning. Called by {@code GhostShipBuilder} on server start.</p>
 */
public class DeckhandEntity extends PathfinderMob {
    /** X offsets of the oar benches along the hull; mirrors {@code OarAnimator}'s oar rows. */
    private static final int[] BENCH_X = {-12, -4, 4, 12};

    public DeckhandEntity(EntityType<? extends DeckhandEntity> entityType, Level level) {
        super(entityType, level);
    }

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(1, new LookAtPlayerGoal(this, Player.class, 48.0F, 0.02F));
    }

    @Override
    public void tick() {
        super.tick();
        // Limbo only: a deckhand outside the ghost ship's dimension simply is not.
        if (!this.level().isClientSide && !this.level().dimension().equals(LimboDimension.LIMBO)) {
            this.discard();
        }
    }

    @Override
    public boolean isInvulnerableTo(DamageSource source) {
        return !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY); // /kill still works.
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void doPush(net.minecraft.world.entity.Entity entity) {
        // Never shoves players around the deck.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // The crew rows forever.
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return null; // Mute.
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return null;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return null;
    }

    /**
     * Seats the eight-strong rowing crew at the oar benches, once (no-op while
     * {@link EclipseWorldState#getDeckhandEntities()} is non-empty — the persisted
     * entities re-attach by themselves on world load). Bench positions sit one block
     * inboard of each oar, facing outboard.
     */
    public static void ensureCrew(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        if (!state.getDeckhandEntities().isEmpty()) {
            EclipseMod.LOGGER.info("Re-attached to {} persisted ghost ship deckhands",
                    state.getDeckhandEntities().size());
            return;
        }
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        List<UUID> ids = new ArrayList<>();
        for (int side = -1; side <= 1; side += 2) {
            for (int x : BENCH_X) {
                double benchZ = side * (GhostShipBuilder.halfWidthAt(x) - 1.0D);
                DeckhandEntity deckhand = EclipseEntities.DECKHAND.get().create(limbo);
                if (deckhand == null) {
                    EclipseMod.LOGGER.error("Failed to create deckhand at bench x={} side={}", x, side);
                    continue;
                }
                float outboardYaw = side < 0 ? 180.0F : 0.0F; // Face the oar, back to midship.
                deckhand.moveTo(x + 0.5D, deckY + 1.0D, benchZ + 0.5D, outboardYaw, 0.0F);
                deckhand.setYBodyRot(outboardYaw);
                deckhand.setYHeadRot(outboardYaw);
                deckhand.setPersistenceRequired();
                limbo.addFreshEntity(deckhand);
                ids.add(deckhand.getUUID());
            }
        }
        state.setDeckhandEntities(ids);
        EclipseMod.LOGGER.info("Seated {} ghost ship deckhands in {}", ids.size(), LimboDimension.LIMBO.location());
    }
}
