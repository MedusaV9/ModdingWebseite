package dev.projecteclipse.eclipse.entity.fog;

import java.util.EnumSet;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Fog Revenant special (plan §2.3): every {@value #COOLDOWN_MIN_TICKS}–{@value
 * #COOLDOWN_MAX_TICKS} t while a target stands inside {@value #TRIGGER_RANGE} blocks
 * with line of sight, the revenant roots itself for a {@value #CHANNEL_TICKS} t channel
 * (the {@code cast_blind} one-shot: claws rise, wisps flare and orbit-spin — the visual
 * telegraph; converging cloud motes underline it) and then detonates a r={@value
 * #BURST_RADIUS} AoE: <b>Blindness 4 s + Slowness II 3 s</b> on every survival player in
 * range, a Quasar fog puff (existing {@code boss_slam} emitter until P2 delivers
 * {@code eclipse:fog_burst}, plan §4.2 — vanilla CLOUD ring ships alongside as the
 * always-on backup) and the elder-guardian curse sting.
 *
 * <p>Counterplay: the 1.5 s rooted channel is the window — break line of sight or leave
 * the radius before the burst lands. The channel commits once started (it only aborts if
 * the target dies/disappears), and an aborted channel refunds most of the cooldown.</p>
 *
 * <p>Holds the MOVE+LOOK flags above the melee goal, so the revenant genuinely roots
 * while casting.</p>
 */
public class FogBlindBurstGoal extends Goal {
    private static final int CHANNEL_TICKS = 30;
    private static final int COOLDOWN_MIN_TICKS = 240;
    private static final int COOLDOWN_MAX_TICKS = 320;
    /** Cooldown refunded when the channel aborts early (target died mid-cast). */
    private static final int ABORT_COOLDOWN_TICKS = 80;
    private static final double TRIGGER_RANGE = 6.0D;
    private static final double BURST_RADIUS = 5.0D;
    private static final int BLINDNESS_TICKS = 80; // 4 s
    private static final int SLOWNESS_TICKS = 60;  // 3 s, amplifier II

    private final FogRevenantEntity revenant;
    /** Entity tick the burst becomes available again ({@code tickCount} clock). */
    private int readyAtTick;
    private int channelTicks = -1;
    private boolean burstFired;

    public FogBlindBurstGoal(FogRevenantEntity revenant) {
        this.revenant = revenant;
        // First cast never opens the encounter cold: give players a few seconds of melee.
        this.readyAtTick = 100;
        this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        if (this.revenant.tickCount < this.readyAtTick) {
            return false;
        }
        LivingEntity target = this.revenant.getTarget();
        return target != null && target.isAlive()
                && this.revenant.distanceTo(target) <= TRIGGER_RANGE
                && this.revenant.hasLineOfSight(target);
    }

    @Override
    public boolean canContinueToUse() {
        LivingEntity target = this.revenant.getTarget();
        return this.channelTicks > 0 && target != null && target.isAlive();
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }

    @Override
    public void start() {
        this.channelTicks = CHANNEL_TICKS;
        this.burstFired = false;
        this.revenant.getNavigation().stop();
        this.revenant.triggerAction(FogRevenantEntity.ANIM_CAST_BLIND);
        this.revenant.level().playSound(null, this.revenant.blockPosition(),
                SoundEvents.WARDEN_SONIC_CHARGE, SoundSource.HOSTILE, 0.7F, 1.4F);
        EclipseMod.LOGGER.info("Fog Revenant {} channels blind burst at {}",
                this.revenant.getId(), this.revenant.blockPosition());
    }

    @Override
    public void tick() {
        LivingEntity target = this.revenant.getTarget();
        if (target != null) {
            this.revenant.getLookControl().setLookAt(target, 30.0F, 30.0F);
        }
        this.revenant.getNavigation().stop();
        if (this.revenant.level() instanceof ServerLevel serverLevel && this.channelTicks % 3 == 0) {
            // Converging fog motes: the telegraph tightens as the burst approaches.
            double spread = 0.6D + 1.6D * (this.channelTicks / (double) CHANNEL_TICKS);
            serverLevel.sendParticles(ParticleTypes.CLOUD,
                    this.revenant.getX(), this.revenant.getY() + 1.4D, this.revenant.getZ(),
                    2, spread, 0.5D, spread, 0.0D);
            serverLevel.sendParticles(ParticleTypes.SCULK_SOUL,
                    this.revenant.getX(), this.revenant.getY() + 1.8D, this.revenant.getZ(),
                    1, 0.5D, 0.3D, 0.5D, 0.01D);
        }
        if (--this.channelTicks <= 0) {
            burst();
        }
    }

    @Override
    public void stop() {
        if (!this.burstFired) {
            // Aborted channel (target died/vanished): most of the cooldown is refunded.
            this.readyAtTick = this.revenant.tickCount + ABORT_COOLDOWN_TICKS;
        }
        this.channelTicks = -1;
    }

    /** The r=5 detonation: blind + slow every survival player in radius, puff the fog. */
    private void burst() {
        this.burstFired = true;
        this.channelTicks = 0;
        this.readyAtTick = this.revenant.tickCount + COOLDOWN_MIN_TICKS
                + this.revenant.getRandom().nextInt(COOLDOWN_MAX_TICKS - COOLDOWN_MIN_TICKS + 1);
        if (!(this.revenant.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        int blinded = 0;
        List<ServerPlayer> players = serverLevel.getEntitiesOfClass(ServerPlayer.class,
                this.revenant.getBoundingBox().inflate(BURST_RADIUS),
                player -> player.isAlive() && !player.isSpectator() && !player.isCreative()
                        && player.distanceTo(this.revenant) <= BURST_RADIUS);
        for (ServerPlayer player : players) {
            player.addEffect(new MobEffectInstance(MobEffects.BLINDNESS, BLINDNESS_TICKS), this.revenant);
            player.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, SLOWNESS_TICKS, 1), this.revenant);
            blinded++;
        }
        // Fog puff: Quasar cue (P2's fog_burst later; boss_slam is the sanctioned
        // stand-in emitter) + a vanilla cloud ring so the burst reads without Veil.
        PacketDistributor.sendToPlayersNear(serverLevel, null,
                this.revenant.getX(), this.revenant.getY(), this.revenant.getZ(), 64.0D,
                new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM,
                        this.revenant.position().add(0.0D, 1.2D, 0.0D)));
        for (int i = 0; i < 24; i++) {
            float angle = (float) (i * Math.PI * 2.0D / 24.0D);
            serverLevel.sendParticles(ParticleTypes.CLOUD,
                    this.revenant.getX() + Mth.cos(angle) * 2.0D, this.revenant.getY() + 0.9D,
                    this.revenant.getZ() + Mth.sin(angle) * 2.0D,
                    1, 0.1D, 0.05D, 0.1D, 0.12D);
        }
        serverLevel.sendParticles(ParticleTypes.SCULK_SOUL,
                this.revenant.getX(), this.revenant.getY() + 1.5D, this.revenant.getZ(),
                12, 1.6D, 0.8D, 1.6D, 0.02D);
        serverLevel.playSound(null, this.revenant.blockPosition(), SoundEvents.ELDER_GUARDIAN_CURSE,
                SoundSource.HOSTILE, 0.8F, 1.3F);
        EclipseMod.LOGGER.info("Fog Revenant {} blind burst: {} player(s) blinded (r={})",
                this.revenant.getId(), blinded, BURST_RADIUS);
    }
}
