package dev.projecteclipse.eclipse.entity;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.limbo.OarAnimator;
import dev.projecteclipse.eclipse.lives.BanService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
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
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.LevelTickEvent;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.animation.RawAnimation;

/**
 * Deckhand — the mute rowing crew of the limbo ghost ship ({@code docs/ideas/04_content.md}
 * §1.4), remodeled on GeckoLib for P6-W2 ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.3 "deckhand v2"): the hooded rower now carries a real two-handed oar as part of its
 * own skeleton ({@code oar/oar_loom/oar_shaft/oar_blade} bones in
 * {@code geo/entity/deckhand.geo.json}), which kills user bugs 4c (bladeless "staff" cube)
 * and 4d (block-display oars swinging on a clock unrelated to the arms) at the root: one
 * skeleton, one {@code row} loop (exactly 3.0 s = 60 t), rower and oar can never desync.
 * {@code limbo.OarAnimator} keeps only the legacy display cleanup + the cutscene tilt flag.
 *
 * <p><b>Base animation state machine</b> (GeckoLib {@code base} controller,
 * {@link #handleBaseState}): {@code tilt} while the start-event cutscene keels the ship
 * over ({@link #isTilt}, driven by {@link OarAnimator#isTiltActive}), else {@code row}
 * while calm, else {@code walk}/{@code idle_sag} for the risen fighter. One-shots on the
 * {@code action} controller: {@code rise} (bench → standing, fired by {@link #riseHostile}),
 * {@code attack} (two-beat claw, fired from {@link #doHurtTarget}), {@code death}
 * (crumple, 30 t scripted removal in {@link #tickDeath}).</p>
 *
 * <p><b>Hostile mode</b> (Ferryman P2 "Crew"): {@link #riseHostile} reconciles the crew
 * (bug 4a sweep) then flips the synced {@code HOSTILE} flag — a hostile deckhand becomes
 * vulnerable, gains walk speed (the passive base speed is 0) and its gated melee/target
 * goals activate against LIVING (non-banned) players only. {@link #calmCrew} reverses it
 * AND snaps every survivor back onto its own bench (bug 4b: they used to sag "where they
 * stand", unhittable, forever); a per-entity self-heal calms + reseats any hostile
 * deckhand that has had no living Ferryman in the dimension for
 * {@value #ORPHAN_CALM_TICKS} t (covers {@code /kill}ed bosses, crashes, wipes).</p>
 *
 * <p><b>Bench identity + duplicates (bug 4a)</b>: every deckhand persists its
 * {@code BenchIndex} (0–7) in NBT; the crew's entity UUIDs persist in
 * {@link EclipseWorldState#getDeckhandEntities()}. {@link #reseatFallen} no longer trusts
 * an immediate {@code getEntity(uuid) == null} (entity sections load asynchronously after
 * block chunks — the old code seated a SECOND rower while the first was still loading):
 * it opens a {@value #RESEAT_WINDOW_TICKS} t resolve window on the level tick and only
 * re-seats benches that stay unresolved after the window with the bench's entity section
 * actually loaded ({@link ServerLevel#areEntitiesLoaded}). {@link #reconcileCrew} discards
 * any deckhand not on the persisted list (fight start, crew seeding), and each entity
 * self-checks every {@value #RECONCILE_SELF_CHECK_TICKS} t so late-loading orphans remove
 * themselves.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public class DeckhandEntity extends EclipseGeoMob {
    /** X offsets of the four bench columns along the hull (both sides seat one each). */
    private static final int[] BENCH_X = {-12, -4, 4, 12};
    /** Benches aboard = one rower per {@code BENCH_X} entry per side. */
    public static final int BENCH_COUNT = BENCH_X.length * 2;

    private static final double HOSTILE_SPEED = 0.30D;
    private static final double HOSTILE_ATTACK_DAMAGE = 4.0D;

    /** The shared row clock: {@code animation.deckhand.row} is authored at exactly 3.0 s. */
    public static final int ROW_SYNC_PERIOD_TICKS = 60;
    /** Scripted death crumple length ({@code animation.deckhand.death} is 1.5 s). */
    private static final int DEATH_DURATION_TICKS = 30;
    /** Bug 4a: how long a hostile deckhand tolerates a Ferryman-less dimension. */
    private static final int ORPHAN_CALM_TICKS = 100;
    /** Bug 4a: cadence of the per-entity "am I still on the crew list?" self-check. */
    private static final int RECONCILE_SELF_CHECK_TICKS = 200;
    /** Bug 4a: how long {@link #reseatFallen} waits for entity sections before re-seating. */
    private static final int RESEAT_WINDOW_TICKS = 100;

    private static final String ANIM_ROW = "row";
    private static final String ANIM_IDLE_SAG = "idle_sag";
    private static final String ANIM_RISE = "rise";
    private static final String ANIM_TILT = "tilt";

    /** True while the crew has risen against the living (Ferryman P2). Synced for anims. */
    private static final EntityDataAccessor<Boolean> DATA_HOSTILE =
            SynchedEntityData.defineId(DeckhandEntity.class, EntityDataSerializers.BOOLEAN);
    /** True during the start-event keel-over (transient — never saved; see {@link #tick}). */
    private static final EntityDataAccessor<Boolean> DATA_TILT =
            SynchedEntityData.defineId(DeckhandEntity.class, EntityDataSerializers.BOOLEAN);

    private static final RawAnimation ROW_ANIM = EclipseGeoAnimations.loop("deckhand", ANIM_ROW);
    private static final RawAnimation TILT_ANIM = EclipseGeoAnimations.loop("deckhand", ANIM_TILT);

    // --- deferred-reseat window (bug 4a load race; single limbo level -> plain statics) ---
    private static int pendingReseatTicks;
    private static int reseatResolvedMask;

    /** This rower's bench (0–7, {@code -1} for pre-P6 legacy entities), persisted in NBT. */
    private int benchIndex = -1;
    /** Consecutive hostile ticks without a living Ferryman (bug 4b self-heal). */
    private int hostileOrphanTicks;

    /** Renderer bookkeeping: last game time the {@code row} loop was clock-synced. */
    public long clientRowResetAt = Long.MIN_VALUE;
    /** Renderer bookkeeping: last row cycle that spawned the blade-dip splash. */
    public long clientSplashCycle = Long.MIN_VALUE;

    public DeckhandEntity(EntityType<? extends DeckhandEntity> entityType, Level level) {
        super(entityType, level);
    }

    // --- GeckoLib wiring (EclipseGeoMob contract) ---

    @Override
    public String geoId() {
        return "deckhand";
    }

    /**
     * {@code base} controller: cutscene tilt beats everything; a calm deckhand always rows
     * (there is no calm standing state — calm implies seated at its bench); a risen one
     * shambles ({@code walk}) or sags ({@code idle_sag}, via the overridden idle).
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        if (isTilt()) {
            return state.setAndContinue(TILT_ANIM);
        }
        if (!isHostile()) {
            return state.setAndContinue(ROW_ANIM);
        }
        return state.setAndContinue(state.isMoving() ? walkAnim() : idleAnim());
    }

    /** The sheet names the hostile stand-around loop {@code idle_sag}, not {@code idle}. */
    @Override
    protected RawAnimation idleAnim() {
        return EclipseGeoAnimations.loop(geoId(), ANIM_IDLE_SAG);
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(ANIM_RISE, EclipseGeoAnimations.once(geoId(), ANIM_RISE));
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(geoId(), EclipseGeoAnimations.ANIM_ATTACK));
    }

    // --- AI (unchanged from v1: hostile-gated combat, occasional ghost-watching) ---

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
        builder.define(DATA_TILT, false);
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
        this.hostileOrphanTicks = 0;
        if (!this.level().isClientSide) {
            this.getAttribute(Attributes.MOVEMENT_SPEED).setBaseValue(hostile ? HOSTILE_SPEED : 0.0D);
            this.getAttribute(Attributes.ATTACK_DAMAGE).setBaseValue(hostile ? HOSTILE_ATTACK_DAMAGE : 0.0D);
            if (!hostile) {
                this.setTarget(null);
                this.getNavigation().stop();
            }
        }
    }

    /** Start-event cutscene pose flag (oars shipped skyward while the ship keels over). */
    public boolean isTilt() {
        return this.entityData.get(DATA_TILT);
    }

    private void setTilt(boolean tilt) {
        this.entityData.set(DATA_TILT, tilt);
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            return;
        }
        // Limbo only: a deckhand outside the ghost ship's dimension simply is not.
        if (!this.level().dimension().equals(LimboDimension.LIMBO)) {
            this.discard();
            return;
        }
        // Cutscene tilt follows OarAnimator's static flag (never persisted: a restart
        // mid-cutscene must not leave the crew frozen mid-salute — the flag boots false).
        boolean tiltActive = OarAnimator.isTiltActive();
        if (isTilt() != tiltActive) {
            setTilt(tiltActive);
        }
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        // Bug 4a self-heal: a deckhand that is not on the persisted crew list is an orphan
        // (duplicate from a load race or a state reset) and removes itself. Spread the
        // check across the crew via entity id so 8 rowers don't all scan on the same tick.
        if ((this.tickCount + this.getId()) % RECONCILE_SELF_CHECK_TICKS == 0) {
            List<UUID> listed = EclipseWorldState.get(serverLevel.getServer()).getDeckhandEntities();
            if (!listed.isEmpty() && !listed.contains(this.getUUID())) {
                EclipseMod.LOGGER.info("Deckhand {} is not on the crew list — discarding orphan (bench {})",
                        this.getUUID(), this.benchIndex);
                this.discard();
                return;
            }
        }
        // Bug 4b self-heal: hostile with no living Ferryman anywhere in limbo (killed via
        // command, crashed fight, discarded boss) -> calm down and return to the bench.
        if (isHostile() && this.tickCount % 20 == 0) {
            boolean ferrymanAlive = !serverLevel.getEntities(EclipseEntities.FERRYMAN.get(),
                    LivingEntity::isAlive).isEmpty();
            this.hostileOrphanTicks = ferrymanAlive ? 0 : this.hostileOrphanTicks + 20;
            if (this.hostileOrphanTicks >= ORPHAN_CALM_TICKS) {
                EclipseMod.LOGGER.info(
                        "Deckhand at bench {} was hostile with no Ferryman alive for {}t — self-calming",
                        this.benchIndex, ORPHAN_CALM_TICKS);
                setHostile(false);
                snapToBench(serverLevel);
            }
        }
    }

    // --- combat/death hooks (GeckoLib one-shots) ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // two-beat claw
        }
        return hurt;
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_DEATH); // crumple, held on last frame
        }
    }

    /** Scripted 30 t crumple window, then the vanilla poof (Ferryman precedent). */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        if (this.deathTime % 10 == 0) {
            serverLevel.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 0.8D, this.getZ(),
                    2, 0.25D, 0.3D, 0.25D, 0.01D);
        }
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, (byte) 60); // poof cloud
            this.remove(Entity.RemovalReason.KILLED);
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
    protected void doPush(Entity entity) {
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

    // --- persistence (mid-fight restarts resume the crew phase; bench identity survives) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putBoolean("Hostile", isHostile());
        compound.putInt("BenchIndex", this.benchIndex);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        setHostile(compound.getBoolean("Hostile"));
        this.benchIndex = compound.contains("BenchIndex") ? compound.getInt("BenchIndex") : -1;
    }

    // --- bench geometry ---

    /** This rower's persisted bench slot (0–7), or {@code -1} for pre-P6 legacy entities. */
    public int benchIndex() {
        return this.benchIndex;
    }

    /**
     * The block position of bench {@code index} (0–7): benches 0–3 sit portside
     * ({@code -Z}) at x −12/−4/4/12, benches 4–7 starboard, one block inboard of the
     * gunwale on the deck at {@code waterlineY + 3} (P6-W3 ship-rebuild contract).
     */
    public static BlockPos benchPos(ServerLevel limbo, int index) {
        return BlockPos.containing(benchCenter(limbo, index));
    }

    /** Exact seat position of bench {@code index} (entity feet). */
    private static Vec3 benchCenter(ServerLevel limbo, int index) {
        int x = BENCH_X[index % BENCH_X.length];
        int side = index < BENCH_X.length ? -1 : 1;
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        double benchZ = side * (GhostShipBuilder.halfWidthAt(x) - 1.0D);
        return new Vec3(x + 0.5D, deckY + 1.0D, benchZ + 0.5D);
    }

    /** Rowers face outboard: portside benches look {@code -Z} (yaw 180), starboard 0. */
    private static float benchYaw(int index) {
        return index < BENCH_X.length ? 180.0F : 0.0F;
    }

    /**
     * Snaps this deckhand back onto its bench, facing outboard (bug 4b: the crew is
     * spectral — an instant reseat with a soul-puff reads intentional, and passive
     * movement speed is 0 so walking back is not an option). Also restores full health:
     * the fight is over and the next crossing starts from a clean state. Legacy entities
     * without a bench index derive one from their crew-list slot.
     */
    private void snapToBench(ServerLevel limbo) {
        int index = this.benchIndex;
        if (index < 0 || index >= BENCH_COUNT) {
            index = EclipseWorldState.get(limbo.getServer()).getDeckhandEntities().indexOf(this.getUUID());
            if (index < 0 || index >= BENCH_COUNT) {
                EclipseMod.LOGGER.warn("Deckhand {} has no bench index and no crew-list slot — left in place",
                        this.getUUID());
                return;
            }
            this.benchIndex = index;
        }
        Vec3 seat = benchCenter(limbo, index);
        float yaw = benchYaw(index);
        limbo.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 1.0D, this.getZ(),
                6, 0.25D, 0.4D, 0.25D, 0.015D);
        this.teleportTo(seat.x, seat.y, seat.z);
        this.setYRot(yaw);
        this.setYBodyRot(yaw);
        this.setYHeadRot(yaw);
        this.setDeltaMovement(Vec3.ZERO);
        this.getNavigation().stop();
        this.setHealth(this.getMaxHealth());
        limbo.sendParticles(ParticleTypes.SPLASH, seat.x, seat.y + 0.5D, seat.z,
                8, 0.3D, 0.3D, 0.3D, 0.0D);
    }

    // --- crew management (static, driven by GhostShipBuilder + FerrymanEntity) ---

    /**
     * Seats the eight-strong rowing crew at the oar benches, once (no-op while
     * {@link EclipseWorldState#getDeckhandEntities()} is non-empty — the persisted
     * entities re-attach by themselves on world load), then sweeps orphans
     * ({@link #reconcileCrew}). Called by {@code GhostShipBuilder} on server start.
     */
    public static void ensureCrew(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        if (!state.getDeckhandEntities().isEmpty()) {
            EclipseMod.LOGGER.info("Re-attached to {} persisted ghost ship deckhands",
                    state.getDeckhandEntities().size());
            reconcileCrew(limbo);
            return;
        }
        List<UUID> ids = new ArrayList<>();
        for (int index = 0; index < BENCH_COUNT; index++) {
            DeckhandEntity deckhand = seatAt(limbo, index);
            if (deckhand != null) {
                ids.add(deckhand.getUUID());
            }
        }
        state.setDeckhandEntities(ids);
        EclipseMod.LOGGER.info("Seated {} ghost ship deckhands in {}", ids.size(), LimboDimension.LIMBO.location());
        reconcileCrew(limbo);
    }

    /**
     * Bug 4a orphan sweep: discards every loaded deckhand whose UUID is not on the
     * persisted crew list. Orphans are produced by the old reseat load race and by
     * world-state resets; they are passive → invulnerable → they used to stand at the
     * benches forever as "duplicates". Late-loading orphans are covered by the
     * per-entity self-check in {@link #tick}. Returns how many were discarded.
     */
    public static int reconcileCrew(ServerLevel limbo) {
        List<UUID> listed = EclipseWorldState.get(limbo.getServer()).getDeckhandEntities();
        if (listed.isEmpty()) {
            return 0; // Nothing authoritative to reconcile against.
        }
        Set<UUID> keep = new HashSet<>(listed);
        int discarded = 0;
        for (DeckhandEntity deckhand : limbo.getEntities(EclipseEntities.DECKHAND.get(), entity -> true)) {
            if (!keep.contains(deckhand.getUUID())) {
                deckhand.discard();
                discarded++;
            }
        }
        if (discarded > 0) {
            EclipseMod.LOGGER.info("Deckhand reconciliation: discarded {} orphan crew duplicate(s)", discarded);
        }
        return discarded;
    }

    /**
     * Ferryman fight opener (W12): brings every bench back to strength for the next
     * crossing — but NO LONGER by trusting an immediate {@code getEntity(uuid) == null}
     * (bug 4a: entity sections load asynchronously after block chunks, so right after
     * boot a perfectly alive rower resolves null and the old code seated a duplicate).
     * Instead this opens a {@value #RESEAT_WINDOW_TICKS} t window on the limbo level tick
     * ({@link #onLevelTick}): benches whose rower resolves during the window are left
     * alone; benches still unresolved at the end are re-seated only if their entity
     * section is actually loaded. Returns 0 — re-seating is asynchronous now; the P2
     * crew rise happens minutes later at the phase break, long after the window closes.
     */
    public static int reseatFallen(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        if (state.getDeckhandEntities().isEmpty()) {
            ensureCrew(limbo);
            return state.getDeckhandEntities().size();
        }
        pendingReseatTicks = RESEAT_WINDOW_TICKS;
        reseatResolvedMask = 0;
        EclipseMod.LOGGER.info("Deckhand reseat window opened: verifying {} listed rower(s) over {}t",
                state.getDeckhandEntities().size(), RESEAT_WINDOW_TICKS);
        return 0;
    }

    /** Drives the deferred-reseat window (bug 4a) on the limbo level tick. */
    @SubscribeEvent
    public static void onLevelTick(LevelTickEvent.Post event) {
        if (pendingReseatTicks <= 0 || !(event.getLevel() instanceof ServerLevel level)
                || !level.dimension().equals(LimboDimension.LIMBO)) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(level.getServer());
        List<UUID> ids = new ArrayList<>(state.getDeckhandEntities());
        int benches = Math.min(ids.size(), BENCH_COUNT);
        for (int i = 0; i < benches; i++) {
            if ((reseatResolvedMask & (1 << i)) != 0) {
                continue;
            }
            if (level.getEntity(ids.get(i)) instanceof DeckhandEntity existing && existing.isAlive()) {
                reseatResolvedMask |= 1 << i;
            }
        }
        pendingReseatTicks--;
        boolean allResolved = reseatResolvedMask == (1 << benches) - 1;
        if (allResolved) {
            pendingReseatTicks = 0;
            EclipseMod.LOGGER.info("Deckhand reseat: all {} rowers accounted for — nothing to do", benches);
            return;
        }
        if (pendingReseatTicks > 0) {
            return;
        }
        // Window closed with unresolved benches: those rowers are genuinely dead/missing
        // (or their sections never loaded — skipped, they may well be alive out there).
        int returned = 0;
        for (int i = 0; i < benches; i++) {
            if ((reseatResolvedMask & (1 << i)) != 0) {
                continue;
            }
            BlockPos bench = benchPos(level, i);
            if (!level.areEntitiesLoaded(ChunkPos.asLong(bench))) {
                EclipseMod.LOGGER.info(
                        "Deckhand reseat: bench {} unresolved but its entity section is not loaded — skipped", i);
                continue;
            }
            DeckhandEntity deckhand = seatAt(level, i);
            if (deckhand != null) {
                ids.set(i, deckhand.getUUID());
                returned++;
            }
        }
        if (returned > 0) {
            state.setDeckhandEntities(ids);
            EclipseMod.LOGGER.info("Deckhand crew: {} fallen rower(s) returned to their benches", returned);
            reconcileCrew(level);
        }
    }

    /** Restart hygiene: never leak a half-open reseat window into the next world. */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        pendingReseatTicks = 0;
        reseatResolvedMask = 0;
    }

    /** Spawns one idle rower seated at bench {@code index}, facing outboard. */
    @Nullable
    private static DeckhandEntity seatAt(ServerLevel limbo, int index) {
        DeckhandEntity deckhand = EclipseEntities.DECKHAND.get().create(limbo);
        if (deckhand == null) {
            EclipseMod.LOGGER.error("Failed to create deckhand for bench {}", index);
            return null;
        }
        Vec3 seat = benchCenter(limbo, index);
        float yaw = benchYaw(index);
        deckhand.benchIndex = index;
        deckhand.moveTo(seat.x, seat.y, seat.z, yaw, 0.0F);
        deckhand.setYBodyRot(yaw);
        deckhand.setYHeadRot(yaw);
        deckhand.setPersistenceRequired();
        limbo.addFreshEntity(deckhand);
        return deckhand;
    }

    /**
     * Ferryman P2 opener: sweeps orphans first (bug 4a — stragglers must not stand around
     * passive while the listed crew fights), then every listed crew member that is still
     * alive rises hostile with the {@code rise} one-shot (bench → standing claw).
     * Returns how many rose (spec calls for 6–8; the ship seats 8).
     */
    public static int riseHostile(ServerLevel limbo) {
        reconcileCrew(limbo);
        int risen = 0;
        for (DeckhandEntity deckhand : resolveCrew(limbo)) {
            if (deckhand.isAlive() && !deckhand.isHostile()) {
                deckhand.setHostile(true);
                deckhand.triggerAction(ANIM_RISE);
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

    /**
     * Ferryman P2 closer / fight-end reset (bug 4b): every surviving crew member calms
     * AND snaps back onto its own bench at full health — the old behavior only cleared
     * the flag, leaving survivors sagging mid-deck, invulnerable, in the rowing pose,
     * forever. Returns how many survivors were calmed.
     */
    public static int calmCrew(ServerLevel limbo) {
        int calmed = 0;
        for (DeckhandEntity deckhand : resolveCrew(limbo)) {
            if (!deckhand.isAlive()) {
                continue; // Fallen crew stays fallen; reseatFallen replaces them next fight.
            }
            if (deckhand.isHostile()) {
                deckhand.setHostile(false);
                calmed++;
            }
            deckhand.snapToBench(limbo); // Idempotent for rowers already seated.
        }
        EclipseMod.LOGGER.info("Deckhand crew calmed: {} survivor(s) back on the benches", calmed);
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
