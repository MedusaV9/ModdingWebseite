package dev.projecteclipse.eclipse.entity.fog;

import java.util.EnumSet;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Fog Colossus special (plan §2.3): every ~{@value #COOLDOWN_TICKS} t while a target
 * stands inside {@value #TRIGGER_RANGE} blocks, the colossus roots itself, raises both
 * arms for the {@value #IMPACT_TICK} t telegraph (the {@code slam} one-shot — the
 * matching raise runs 0–1.25 s in the anim file, fissures flaring with the pose) and
 * hammers the ground: a r={@value #RADIUS} ground shockwave dealing {@value #DAMAGE}
 * at the core with linear falloff past r={@value #INNER_RADIUS}, plus launch
 * (the SoftBorder/Ferryman {@code setDeltaMovement + hurtMarked} pattern) and Slowness.
 *
 * <p>Counterplay (plan: "jumpable if you're outside r=3"): the wave hugs the ground —
 * any victim beyond {@value #INNER_RADIUS} blocks who is airborne at impact is skipped
 * entirely. Inside {@value #INNER_RADIUS} you are under the fists; no dodge.</p>
 *
 * <p>Presentation: campfire-smoke ring stamp + a sparse SONIC_BOOM flash-ring at
 * impact, generic explosion crunch, and {@code S2CShakePayload.shake(0.5f, 12)} for
 * players within {@value #SHAKE_RANGE} blocks (§2.2 "screen-shake via existing FX
 * payload"). Holds MOVE+LOOK+JUMP above melee, so the wind-up genuinely roots.</p>
 */
public class GroundSlamGoal extends Goal {
    /** Telegraph length — matches the anim's arm-raise (25 t) + drop (impact frame 1.35 s). */
    static final int IMPACT_TICK = 27;
    /** A short follow-through after impact before the goal releases (anim recovery). */
    private static final int RECOVER_TICKS = 12;
    private static final int COOLDOWN_TICKS = 200;
    private static final int COOLDOWN_JITTER_TICKS = 40;
    static final double TRIGGER_RANGE = 5.0D;
    private static final double RADIUS = 6.0D;
    /** Full-damage core; beyond it the wave falls off linearly and can be jumped. */
    private static final double INNER_RADIUS = 3.0D;
    private static final float DAMAGE = 8.0F;
    private static final int SLOWNESS_TICKS = 60; // 3 s
    private static final double SHAKE_RANGE = 24.0D;

    private final FogColossusEntity colossus;
    /** Entity tick the slam becomes available again ({@code tickCount} clock). */
    private int readyAtTick;
    private int slamTicks = -1;

    public GroundSlamGoal(FogColossusEntity colossus) {
        this.colossus = colossus;
        // First slam never opens the encounter cold: let the walk-up land first.
        this.readyAtTick = 80;
        this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK, Goal.Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        if (this.colossus.tickCount < this.readyAtTick || !this.colossus.onGround()) {
            return false;
        }
        LivingEntity target = this.colossus.getTarget();
        return target != null && target.isAlive()
                && this.colossus.distanceTo(target) <= TRIGGER_RANGE;
    }

    @Override
    public boolean canContinueToUse() {
        // Committed once started — the telegraph is the counterplay window.
        return this.slamTicks >= 0 && this.slamTicks < IMPACT_TICK + RECOVER_TICKS
                && this.colossus.isAlive();
    }

    @Override
    public boolean isInterruptable() {
        return false;
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }

    @Override
    public void start() {
        this.slamTicks = 0;
        this.colossus.getNavigation().stop();
        this.colossus.triggerAction(FogColossusEntity.ANIM_SLAM);
        this.colossus.level().playSound(null, this.colossus.blockPosition(),
                SoundEvents.RAVAGER_ROAR, SoundSource.HOSTILE, 1.2F, 0.5F);
        EclipseMod.LOGGER.info("Fog Colossus {} telegraphs ground slam at {}",
                this.colossus.getId(), this.colossus.blockPosition());
    }

    @Override
    public void tick() {
        LivingEntity target = this.colossus.getTarget();
        if (target != null && this.slamTicks < IMPACT_TICK) {
            this.colossus.getLookControl().setLookAt(target, 30.0F, 30.0F);
        }
        this.colossus.getNavigation().stop();
        if (this.colossus.level() instanceof ServerLevel serverLevel
                && this.slamTicks < IMPACT_TICK && this.slamTicks % 4 == 0) {
            // Fissure flare: ash motes shivering off the raised slabs during the wind-up.
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.colossus.getX(), this.colossus.getY() + 2.6D, this.colossus.getZ(),
                    3, 0.9D, 0.7D, 0.9D, 0.01D);
        }
        if (++this.slamTicks == IMPACT_TICK) {
            slam();
        }
    }

    @Override
    public void stop() {
        this.slamTicks = -1;
        this.readyAtTick = this.colossus.tickCount + COOLDOWN_TICKS
                + this.colossus.getRandom().nextInt(COOLDOWN_JITTER_TICKS + 1);
    }

    /** The r=6 ground shockwave: falloff damage + launch + Slowness, ring stamp, shake. */
    private void slam() {
        if (!(this.colossus.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        int struck = 0;
        List<LivingEntity> victims = serverLevel.getEntitiesOfClass(LivingEntity.class,
                this.colossus.getBoundingBox().inflate(RADIUS, 2.0D, RADIUS),
                victim -> victim != this.colossus && victim.isAlive()
                        && !(victim instanceof FogColossusEntity)
                        && !(victim instanceof Player player
                                && (player.isSpectator() || player.isCreative())));
        for (LivingEntity victim : victims) {
            double distance = victim.distanceTo(this.colossus);
            if (distance > RADIUS) {
                continue;
            }
            boolean core = distance <= INNER_RADIUS;
            if (!core && !victim.onGround()) {
                continue; // The wave hugs the ground — a well-timed jump clears it.
            }
            // Linear falloff: 100% inside the core, down to 25% at the rim.
            float falloff = core ? 1.0F
                    : 1.0F - 0.75F * (float) ((distance - INNER_RADIUS) / (RADIUS - INNER_RADIUS));
            if (victim.hurt(this.colossus.damageSources().mobAttack(this.colossus), DAMAGE * falloff)) {
                Vec3 away = victim.position().subtract(this.colossus.position())
                        .multiply(1.0D, 0.0D, 1.0D).normalize();
                victim.setDeltaMovement(victim.getDeltaMovement()
                        .add(away.x * 0.4D * falloff, 0.3D + 0.45D * falloff, away.z * 0.4D * falloff));
                victim.hurtMarked = true; // SoftBorder/Ferryman pattern: force velocity sync.
                victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN,
                        SLOWNESS_TICKS, core ? 1 : 0), this.colossus);
                struck++;
            }
        }
        // Impact stamp: smoke ring rolling outward + a sparse sonic-flash ring.
        this.colossus.stampDustRing(serverLevel, INNER_RADIUS, 20);
        this.colossus.stampDustRing(serverLevel, RADIUS - 1.0D, 28);
        for (int i = 0; i < 4; i++) {
            float angle = (float) (i * Math.PI / 2.0D) + 0.4F;
            serverLevel.sendParticles(ParticleTypes.SONIC_BOOM,
                    this.colossus.getX() + Mth.cos(angle) * 2.2D, this.colossus.getY() + 0.4D,
                    this.colossus.getZ() + Mth.sin(angle) * 2.2D, 1, 0.0D, 0.0D, 0.0D, 0.0D);
        }
        serverLevel.playSound(null, this.colossus.blockPosition(),
                SoundEvents.GENERIC_EXPLODE.value(), SoundSource.HOSTILE, 1.0F, 0.6F);
        PacketDistributor.sendToPlayersNear(serverLevel, null,
                this.colossus.getX(), this.colossus.getY(), this.colossus.getZ(), SHAKE_RANGE,
                S2CShakePayload.shake(0.5F, 12));
        EclipseMod.LOGGER.info("Fog Colossus {} ground slam: {} victim(s) struck (r={})",
                this.colossus.getId(), struck, RADIUS);
    }
}
