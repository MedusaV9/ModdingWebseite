package dev.projecteclipse.eclipse.ferryman.finale;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import dev.projecteclipse.eclipse.lives.BanService;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;

/**
 * F-045b / F-046b — the violet soul wisp: a small vex-like shade that pours out of the
 * breached portal gate and answers the Ferryman's Geisterbeschwörung. Deliberately
 * simple and SELF-LIMITING:
 *
 * <ul>
 *   <li><b>Hard lifespan</b> ({@link #setLifespan}, default {@value #DEFAULT_LIFESPAN_TICKS}t):
 *       at zero it winks out in a soul-puff — no fight cleanup can ever leak one.</li>
 *   <li><b>Never saved</b> ({@link #shouldBeSaved} = false): a crash mid-swarm leaves
 *       nothing on disk — the despawn guarantee without any sweep bookkeeping.</li>
 *   <li><b>Script-driven drift</b> (no vanilla goals): hovers toward the nearest living
 *       fighter within {@value #AGGRO_RANGE} blocks (vex-like {@code noPhysics} phase
 *       through deck/rails), bites for {@value #CONTACT_DAMAGE} on contact with a
 *       {@value #BITE_COOLDOWN_TICKS}t per-wisp cooldown; without a target it swirls
 *       around its spawn anchor.</li>
 *   <li><b>Panic scatter</b> (MA5): a fighter BRUSHING through the swarm at speed
 *       ({@value #PANIC_RADIUS} blocks, &gt; {@value #PANIC_PLAYER_SPEED} b/t) makes
 *       each touched wisp burst sideways and play {@code panic_scatter} — the swarm
 *       parts around a running player instead of ignoring him. Per-wisp cooldown
 *       {@value #PANIC_COOLDOWN_TICKS}t, steering suspended for
 *       {@value #PANIC_SCATTER_TICKS}t so the burst reads; the bite loop is untouched.
 *       Other systems can fire the same beat via {@link #panicScatter(Vec3)}.</li>
 * </ul>
 */
public class SoulWispEntity extends EclipseGeoMonster {
    public static final float MAX_HEALTH = 8.0F;
    public static final float CONTACT_DAMAGE = 3.0F;
    public static final int DEFAULT_LIFESPAN_TICKS = 1200; // 60 s
    private static final double AGGRO_RANGE = 20.0D;
    private static final double CHASE_SPEED = 0.16D;
    private static final double SWIRL_SPEED = 0.05D;
    private static final int BITE_COOLDOWN_TICKS = 30;
    private static final double BITE_RANGE = 1.4D;

    /** MA5 panic gate: a player must be this close AND actually moving through. */
    private static final double PANIC_RADIUS = 1.7D;
    private static final double PANIC_PLAYER_SPEED = 0.12D;
    private static final int PANIC_COOLDOWN_TICKS = 40;
    /** Steering-free window after a scatter (the 0.9 s sheet's readable part). */
    private static final int PANIC_SCATTER_TICKS = 12;
    private static final double PANIC_PUSH = 0.42D;
    /** Scripted 3-bone decay length (sheet 1.2 s; vanilla would cut it at 20t). */
    public static final int DEATH_DURATION_TICKS = 24;

    /** Sheet one-shots beyond the frozen attack/death set (see soul_wisp.animation.json). */
    public static final String ANIM_PANIC_SCATTER = "panic_scatter";

    private static final String TAG_LIFESPAN = "WispLifespan";

    private int lifespan = DEFAULT_LIFESPAN_TICKS;
    private int biteCooldown;
    private int panicCooldown;
    private int scatterTicks;
    @Nullable
    private Vec3 anchor;

    public SoulWispEntity(EntityType<? extends SoulWispEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noPhysics = true;
        this.xpReward = 2;
    }

    @Override
    public String geoId() {
        return "soul_wisp";
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action);
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(geoId(), EclipseGeoAnimations.ANIM_ATTACK));
        action.triggerableAnim(ANIM_PANIC_SCATTER,
                EclipseGeoAnimations.once(geoId(), ANIM_PANIC_SCATTER));
    }

    /**
     * POLISH2 contract-v2 blend-in (EVAL2-C P-1): {@code panic_scatter}/{@code attack}
     * snap 34°/20° out of {@code walk} — the finale swarm shows many instances popping
     * at once → 2 t each. {@code death} stays hard: the
     * {@value #DEATH_DURATION_TICKS} t hold window equals the MA5 clip exactly.
     */
    @Override
    protected int actionTransitionTicks(String animName) {
        return switch (animName) {
            case ANIM_PANIC_SCATTER, EclipseGeoAnimations.ANIM_ATTACK -> 2;
            default -> 0;
        };
    }

    /** Caps the wisp's remaining life (clamped ≥ 1; spawners tune breach vs. summon). */
    public void setLifespan(int ticks) {
        this.lifespan = Math.max(1, ticks);
    }

    /** Optional outward shove at spawn (the gate breach pours them out). */
    public void shove(Vec3 velocity) {
        this.setDeltaMovement(velocity);
        this.hurtMarked = true;
    }

    // --- ticking ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        if (this.anchor == null) {
            this.anchor = this.position();
        }
        if (--this.lifespan <= 0) {
            serverLevel.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 0.5D,
                    this.getZ(), 8, 0.2D, 0.3D, 0.2D, 0.02D);
            this.discard();
            return;
        }
        if (this.biteCooldown > 0) {
            this.biteCooldown--;
        }
        if (this.panicCooldown > 0) {
            this.panicCooldown--;
        }
        if (this.scatterTicks > 0) {
            this.scatterTicks--;
            return; // the burst owns the velocity while it reads
        }
        if (this.panicCooldown <= 0) {
            ServerPlayer runner = brushingRunner(serverLevel);
            if (runner != null) {
                panicScatter(runner.position());
                return;
            }
        }
        ServerPlayer target = nearestFighter(serverLevel);
        if (target != null) {
            Vec3 to = target.position().add(0.0D, target.getBbHeight() * 0.6D, 0.0D)
                    .subtract(this.position());
            double dist = to.length();
            if (dist > 1.0E-3D) {
                this.setDeltaMovement(this.getDeltaMovement().scale(0.6D)
                        .add(to.normalize().scale(CHASE_SPEED)));
            }
            faceToward(target.position());
            if (dist <= BITE_RANGE && this.biteCooldown <= 0) {
                bite(serverLevel, target);
            }
        } else {
            // Swirl around the anchor: a slow deterministic figure keyed off the id.
            double phase = (this.tickCount + this.getId() * 37) * 0.045D;
            Vec3 want = this.anchor.add(Math.cos(phase) * 2.5D,
                    Math.sin(phase * 0.7D) * 1.2D, Math.sin(phase) * 2.5D);
            Vec3 to = want.subtract(this.position());
            if (to.lengthSqr() > 0.04D) {
                this.setDeltaMovement(this.getDeltaMovement().scale(0.7D)
                        .add(to.normalize().scale(SWIRL_SPEED)));
            }
        }
    }

    private void bite(ServerLevel level, ServerPlayer target) {
        this.biteCooldown = BITE_COOLDOWN_TICKS;
        triggerAction(EclipseGeoAnimations.ANIM_ATTACK);
        target.hurt(this.damageSources().mobAttack(this), CONTACT_DAMAGE);
        level.playSound(null, this.blockPosition(), SoundEvents.VEX_CHARGE,
                net.minecraft.sounds.SoundSource.HOSTILE, 0.7F, 0.6F);
        level.sendParticles(ParticleTypes.SCULK_SOUL, target.getX(),
                target.getY() + 1.0D, target.getZ(), 5, 0.2D, 0.3D, 0.2D, 0.02D);
    }

    /**
     * The MA5 scatter beat: the wisp bursts away from {@code from} (sideways + up, so
     * the swarm PARTS instead of being punted straight back) and plays
     * {@code panic_scatter}. Server-side; safe to call from any system that wants the
     * swarm to react (breach gush, cutscene beats, a boss stomp).
     */
    public void panicScatter(Vec3 from) {
        if (this.level().isClientSide || !this.isAlive()) {
            return;
        }
        Vec3 away = this.position().subtract(from);
        away = away.lengthSqr() < 1.0E-4D
                ? new Vec3(this.random.nextDouble() - 0.5D, 0.0D, this.random.nextDouble() - 0.5D)
                : new Vec3(away.x, 0.0D, away.z);
        if (away.lengthSqr() < 1.0E-4D) {
            away = new Vec3(1.0D, 0.0D, 0.0D);
        }
        // Sideways bias keyed off the id: neighbours fan out instead of stacking.
        Vec3 side = new Vec3(-away.z, 0.0D, away.x).normalize()
                .scale((this.getId() % 2 == 0 ? 1.0D : -1.0D) * 0.6D);
        this.setDeltaMovement(away.normalize().add(side).normalize().scale(PANIC_PUSH)
                .add(0.0D, 0.16D + this.random.nextDouble() * 0.12D, 0.0D));
        this.hurtMarked = true;
        this.panicCooldown = PANIC_COOLDOWN_TICKS;
        this.scatterTicks = PANIC_SCATTER_TICKS;
        triggerAction(ANIM_PANIC_SCATTER);
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.SOUL_ESCAPE.value(),
                    net.minecraft.sounds.SoundSource.HOSTILE, 0.5F, 1.4F);
            serverLevel.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 0.4D,
                    this.getZ(), 3, 0.15D, 0.2D, 0.15D, 0.02D);
        }
    }

    /** A living fighter moving THROUGH this wisp's hover volume (the scatter trigger). */
    @Nullable
    private ServerPlayer brushingRunner(ServerLevel level) {
        for (ServerPlayer player : level.players()) {
            if (!player.isAlive() || player.isSpectator() || BanService.isBanned(player)) {
                continue;
            }
            if (player.distanceToSqr(this) > PANIC_RADIUS * PANIC_RADIUS) {
                continue;
            }
            // getKnownMovement, NOT position()-xo: the move-packet handler calls
            // absMoveTo, which rewrites a player's xo/yo/zo to the new position, so the
            // usual previous-tick delta is always zero for a ServerPlayer.
            Vec3 step = player.getKnownMovement();
            if (step.horizontalDistanceSqr() > PANIC_PLAYER_SPEED * PANIC_PLAYER_SPEED) {
                return player;
            }
        }
        return null;
    }

    @Nullable
    private ServerPlayer nearestFighter(ServerLevel level) {
        ServerPlayer nearest = null;
        double best = AGGRO_RANGE * AGGRO_RANGE;
        for (ServerPlayer player : level.players()) {
            if (!player.isAlive() || player.isSpectator() || player.isCreative()
                    || BanService.isBanned(player)) {
                continue;
            }
            double dist = player.distanceToSqr(this);
            if (dist < best) {
                best = dist;
                nearest = player;
            }
        }
        return nearest;
    }

    private void faceToward(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }

    // --- floating-shade chassis ---

    @Override
    public void travel(Vec3 travelVector) {
        if (this.isControlledByLocalInstance()) {
            this.move(MoverType.SELF, this.getDeltaMovement());
            this.setDeltaMovement(this.getDeltaMovement().scale(0.91D));
        }
    }

    @Override
    public boolean causeFallDamage(float fallDistance, float multiplier, DamageSource source) {
        return false;
    }

    /** Despawn guarantee: a wisp NEVER reaches disk — a crash can leak nothing. */
    @Override
    public boolean shouldBeSaved() {
        return false;
    }

    @Override
    public void checkDespawn() {
        // The lifespan is the despawn; distance rules never apply.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt(TAG_LIFESPAN, this.lifespan);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains(TAG_LIFESPAN)) {
            this.lifespan = Math.max(1, compound.getInt(TAG_LIFESPAN));
        }
    }

    // --- sounds ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.VEX_AMBIENT;
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.VEX_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.VEX_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.75F;
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        triggerAction(EclipseGeoAnimations.ANIM_DEATH);
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 0.5D,
                    this.getZ(), 10, 0.2D, 0.3D, 0.2D, 0.03D);
        }
    }

    /**
     * Holds the body for the full {@value #DEATH_DURATION_TICKS}t of the MA5 3-bone
     * decay sheet (core flare + both shroud shells drifting apart) — vanilla's 20t cut
     * removed the wisp while the fragments were still travelling — then the standard
     * POOF + KILLED removal (P6 death convention; the renderer runs
     * {@code withUprightDeath()}).
     */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.level().isClientSide()
                && !this.isRemoved()) {
            this.level().broadcastEntityEvent(this, (byte) 60);
            this.remove(Entity.RemovalReason.KILLED);
        }
    }

    /** Wisps never push or get pushed (a swarm through a doorway must not pinball). */
    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void doPush(Entity entity) {
        // No push.
    }
}
