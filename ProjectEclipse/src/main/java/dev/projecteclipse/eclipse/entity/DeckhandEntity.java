package dev.projecteclipse.eclipse.entity;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.lives.BanService;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.PathfinderMob;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;

/**
 * Deckhand — the mute rowing crew of the limbo ghost ship ({@code docs/ideas/04_content.md}
 * §1.4). Pure ambience by default: no AI beyond an occasional {@link LookAtPlayerGoal} (it
 * sometimes tracks a passing ghost), invulnerable, unpushable, silent, and it refuses to
 * exist outside the limbo dimension. The rowing animation is procedural client-side
 * ({@code arm.xRot = -1.2 + sin(age*0.08)*0.35}) and matches the block-display oars'
 * cadence ({@code limbo.OarAnimator}).
 *
 * <p><b>Hostile mode</b> (W12, Ferryman P2 "Crew"): {@link #riseHostile} flips the synced
 * {@code HOSTILE} flag on the whole crew — a hostile deckhand becomes vulnerable, gains
 * walk speed (the passive base speed is 0) and its gated melee/target goals activate
 * against LIVING (non-banned) players only; ghosts are never valid targets.
 * {@link #calmCrew} reverses it (survivors sag back to idle where they stand; fallen crew
 * stay fallen — they were already dead). The flag persists so a mid-fight restart resumes
 * the crew phase intact.</p>
 *
 * <p>{@link #ensureCrew} seats one deckhand at each of the eight oar benches, once per
 * world — guarded exactly like the oars: entity UUIDs persist in
 * {@link EclipseWorldState#getDeckhandEntities()}, so restarts re-attach instead of
 * re-spawning. Called by {@code GhostShipBuilder} on server start.</p>
 */
public class DeckhandEntity extends PathfinderMob {
    /** X offsets of the oar benches along the hull; mirrors {@code OarAnimator}'s oar rows. */
    private static final int[] BENCH_X = {-12, -4, 4, 12};

    private static final double HOSTILE_SPEED = 0.30D;
    private static final double HOSTILE_ATTACK_DAMAGE = 4.0D;

    /** True while the crew has risen against the living (Ferryman P2). Synced for the model. */
    private static final EntityDataAccessor<Boolean> DATA_HOSTILE =
            SynchedEntityData.defineId(DeckhandEntity.class, EntityDataSerializers.BOOLEAN);

    public DeckhandEntity(EntityType<? extends DeckhandEntity> entityType, Level level) {
        super(entityType, level);
    }

    @Override
    protected void registerGoals() {
        // Hostile-gated combat goals: dormant while the crew rows (canUse checks the flag).
        this.goalSelector.addGoal(0, new MeleeAttackGoal(this, 1.0D, false) {
            @Override
            public boolean canUse() {
                return isHostile() && super.canUse();
            }

            @Override
            public boolean canContinueToUse() {
                return isHostile() && super.canContinueToUse();
            }
        });
        this.goalSelector.addGoal(1, new LookAtPlayerGoal(this, Player.class, 48.0F, 0.02F));
        // Only the LIVING are prey: banned ghosts share the ship with the crew.
        this.targetSelector.addGoal(1, new NearestAttackableTargetGoal<>(this, Player.class, 10, true, false,
                target -> target instanceof ServerPlayer serverPlayer && !BanService.isBanned(serverPlayer)) {
            @Override
            public boolean canUse() {
                return isHostile() && super.canUse();
            }

            @Override
            public boolean canContinueToUse() {
                return isHostile() && super.canContinueToUse();
            }
        });
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_HOSTILE, false);
    }

    // --- hostile mode ---

    public boolean isHostile() {
        return this.entityData.get(DATA_HOSTILE);
    }

    /**
     * Flips this deckhand between the seated rower and the risen fighter: toggles
     * vulnerability (via {@link #isInvulnerableTo}), walk speed and attack damage, and
     * clears any stale target when calming down.
     */
    public void setHostile(boolean hostile) {
        this.entityData.set(DATA_HOSTILE, hostile);
        if (!this.level().isClientSide) {
            this.getAttribute(Attributes.MOVEMENT_SPEED).setBaseValue(hostile ? HOSTILE_SPEED : 0.0D);
            this.getAttribute(Attributes.ATTACK_DAMAGE).setBaseValue(hostile ? HOSTILE_ATTACK_DAMAGE : 0.0D);
            if (!hostile) {
                this.setTarget(null);
                this.getNavigation().stop();
            }
        }
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
        if (isHostile()) {
            return super.isInvulnerableTo(source); // The risen crew can be cut down.
        }
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
        return isHostile() ? SoundEvents.DROWNED_HURT : null;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return isHostile() ? SoundEvents.DROWNED_DEATH : null;
    }

    // --- persistence (mid-fight restarts resume the crew phase) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putBoolean("Hostile", isHostile());
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        setHostile(compound.getBoolean("Hostile"));
    }

    // --- crew management (static, driven by GhostShipBuilder + FerrymanEntity) ---

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
        List<UUID> ids = new ArrayList<>();
        for (int[] bench : benches()) {
            DeckhandEntity deckhand = seatAt(limbo, bench);
            if (deckhand != null) {
                ids.add(deckhand.getUUID());
            }
        }
        state.setDeckhandEntities(ids);
        EclipseMod.LOGGER.info("Seated {} ghost ship deckhands in {}", ids.size(), LimboDimension.LIMBO.location());
    }

    /**
     * Ferryman fight opener (W12): re-seats every bench whose persisted deckhand is
     * missing or dead — the living cut the crew down in P2, and the Ferryman simply calls
     * them back for the next crossing. Living crew is left untouched. Returns how many
     * rowers returned. (Startup {@link #ensureCrew} deliberately does NOT do this: at that
     * point the persisted entities may simply not be loaded yet.)
     */
    public static int reseatFallen(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        List<UUID> ids = new ArrayList<>(state.getDeckhandEntities());
        if (ids.isEmpty()) {
            ensureCrew(limbo);
            return state.getDeckhandEntities().size();
        }
        List<int[]> benches = benches();
        int returned = 0;
        for (int i = 0; i < ids.size() && i < benches.size(); i++) {
            if (limbo.getEntity(ids.get(i)) instanceof DeckhandEntity existing && existing.isAlive()) {
                continue;
            }
            DeckhandEntity deckhand = seatAt(limbo, benches.get(i));
            if (deckhand != null) {
                ids.set(i, deckhand.getUUID());
                returned++;
            }
        }
        if (returned > 0) {
            state.setDeckhandEntities(ids);
            EclipseMod.LOGGER.info("Deckhand crew: {} fallen rower(s) returned to their benches", returned);
        }
        return returned;
    }

    /** The eight bench spots as {@code {x, side}} in {@link #ensureCrew}'s seating order. */
    private static List<int[]> benches() {
        List<int[]> benches = new ArrayList<>(2 * BENCH_X.length);
        for (int side = -1; side <= 1; side += 2) {
            for (int x : BENCH_X) {
                benches.add(new int[] {x, side});
            }
        }
        return benches;
    }

    /** Spawns one idle rower at the given {@code {x, side}} bench, facing outboard. */
    @Nullable
    private static DeckhandEntity seatAt(ServerLevel limbo, int[] bench) {
        int x = bench[0];
        int side = bench[1];
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        double benchZ = side * (GhostShipBuilder.halfWidthAt(x) - 1.0D);
        DeckhandEntity deckhand = EclipseEntities.DECKHAND.get().create(limbo);
        if (deckhand == null) {
            EclipseMod.LOGGER.error("Failed to create deckhand at bench x={} side={}", x, side);
            return null;
        }
        float outboardYaw = side < 0 ? 180.0F : 0.0F; // Face the oar, back to midship.
        deckhand.moveTo(x + 0.5D, deckY + 1.0D, benchZ + 0.5D, outboardYaw, 0.0F);
        deckhand.setYBodyRot(outboardYaw);
        deckhand.setYHeadRot(outboardYaw);
        deckhand.setPersistenceRequired();
        limbo.addFreshEntity(deckhand);
        return deckhand;
    }

    /**
     * Ferryman P2 opener: every persisted crew member that is still alive rises hostile.
     * Returns how many rose (spec calls for 6–8; the ship seats 8).
     */
    public static int riseHostile(ServerLevel limbo) {
        int risen = 0;
        for (DeckhandEntity deckhand : resolveCrew(limbo)) {
            if (deckhand.isAlive() && !deckhand.isHostile()) {
                deckhand.setHostile(true);
                risen++;
            }
        }
        if (risen > 0) {
            limbo.playSound(null, GhostShipBuilder.NOMINAL_CENTER, SoundEvents.DROWNED_AMBIENT_WATER,
                    SoundSource.HOSTILE, 2.0F, 0.5F);
        }
        EclipseMod.LOGGER.info("Deckhand crew rises hostile: {} up", risen);
        return risen;
    }

    /** Ferryman P2 closer: surviving crew sags back to the idle rower state. */
    public static int calmCrew(ServerLevel limbo) {
        int calmed = 0;
        for (DeckhandEntity deckhand : resolveCrew(limbo)) {
            if (deckhand.isAlive() && deckhand.isHostile()) {
                deckhand.setHostile(false);
                calmed++;
            }
        }
        EclipseMod.LOGGER.info("Deckhand crew calmed: {} survivor(s) back to the benches", calmed);
        return calmed;
    }

    /** How many risen crew members are still standing (the P2 no-ghosts fallback probe). */
    public static int countHostileAlive(ServerLevel limbo) {
        int alive = 0;
        for (DeckhandEntity deckhand : resolveCrew(limbo)) {
            if (deckhand.isAlive() && deckhand.isHostile()) {
                alive++;
            }
        }
        return alive;
    }

    private static List<DeckhandEntity> resolveCrew(ServerLevel limbo) {
        List<DeckhandEntity> crew = new ArrayList<>();
        for (UUID id : EclipseWorldState.get(limbo.getServer()).getDeckhandEntities()) {
            if (limbo.getEntity(id) instanceof DeckhandEntity deckhand) {
                crew.add(deckhand);
            }
        }
        return crew;
    }
}
