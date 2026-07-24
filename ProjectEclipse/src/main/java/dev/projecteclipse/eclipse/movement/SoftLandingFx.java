package dev.projecteclipse.eclipse.movement;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.progression.ContainmentService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.BlockParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;

/**
 * W4-ISLAND / IDEA-04 #4 — universal soft-landing dust + thud. Every protected traversal
 * ending (edge-glide fall-safe band, breach descent Slow Falling, border fallback Slow
 * Falling, containment-bounce fall immunity) currently lands in silence; this single
 * game-bus subscriber marks them all. While a player is airborne it tracks the peak fall
 * speed and whether ANY protection was observed during the fall
 * ({@link ContainmentService#hasFallImmunity}, {@code MobEffects.SLOW_FALLING}, or
 * {@link EdgeGlideService#isGliding}); on the touchdown tick a shielded, non-trivial fall
 * gets a {@code ParticleTypes.BLOCK} dust ring of the block below plus a muffled
 * wool-step thud at {@value #THUD_PITCH} pitch, volume scaled by the prior fall speed.
 *
 * <p>Trivial-hop filter: the landing only fires when the fall peaked at
 * ≥ {@value #MIN_PEAK_FALL} blocks/tick OR lasted ≥ {@value #MIN_AIRBORNE_TICKS} ticks
 * (glides are damped to −0.18 vy, so the duration clause is what admits them). One
 * airborne-tracking map, reset on {@code ServerStoppedEvent} (repo-wide rule) — the
 * per-tick path allocates only when a real fall starts. Server-side
 * {@code sendParticles} means bystanders see the dust too; no client class needed.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SoftLandingFx {
    /** Peak fall speed (blocks/tick) that alone qualifies a landing (bounce/breach). */
    private static final double MIN_PEAK_FALL = 0.45D;
    /** Airborne duration (ticks) that alone qualifies a landing (damped glides). */
    private static final int MIN_AIRBORNE_TICKS = 12;
    /** Falls only start being tracked below this vy (skips jump apex jitter). */
    private static final double TRACK_START_VY = -0.20D;
    /** Dust ring shape (count + spread) per the IDEA-04 spec. */
    private static final int DUST_COUNT = 12;
    private static final double DUST_SPREAD_XZ = 0.5D;
    private static final double DUST_SPREAD_Y = 0.05D;
    private static final double DUST_SPEED = 0.1D;
    /** Muffled thud: fixed low pitch, volume rides the peak fall speed. */
    private static final float THUD_PITCH = 0.7F;
    private static final float THUD_VOLUME_MIN = 0.35F;
    private static final float THUD_VOLUME_MAX = 0.9F;

    /** Peak fall + shielded flag for one airborne player. */
    private static final class Airborne {
        double peakFall;
        int ticks;
        boolean shielded;
    }

    /** Airborne tracking, statics reset on ServerStopped (repo-wide rule). */
    private static final Map<UUID, Airborne> AIRBORNE = new HashMap<>();

    private SoftLandingFx() {}

    @SubscribeEvent
    public static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (!player.isAlive() || player.isSpectator() || player.getAbilities().flying
                || player.isPassenger() || player.isFallFlying() || player.isInWater()) {
            AIRBORNE.remove(player.getUUID());
            return;
        }
        if (player.onGround()) {
            Airborne air = AIRBORNE.remove(player.getUUID());
            if (air != null && air.shielded
                    && (air.peakFall >= MIN_PEAK_FALL || air.ticks >= MIN_AIRBORNE_TICKS)) {
                emitLanding(player, air.peakFall);
            }
            return;
        }
        double vy = player.getDeltaMovement().y;
        Airborne air = AIRBORNE.get(player.getUUID());
        if (air == null) {
            if (vy > TRACK_START_VY) {
                return; // not a real fall (yet) — zero-allocation early out
            }
            air = new Airborne();
            AIRBORNE.put(player.getUUID(), air);
        }
        air.ticks++;
        air.peakFall = Math.max(air.peakFall, -vy);
        if (!air.shielded) {
            air.shielded = ContainmentService.hasFallImmunity(player)
                    || player.hasEffect(MobEffects.SLOW_FALLING)
                    || EdgeGlideService.isGliding(player);
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        AIRBORNE.remove(event.getEntity().getUUID());
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        AIRBORNE.clear();
    }

    /** The dust ring of the block landed on + the muffled thud, for everyone nearby. */
    private static void emitLanding(ServerPlayer player, double peakFall) {
        ServerLevel level = player.serverLevel();
        BlockPos below = player.blockPosition().below();
        BlockState state = level.getBlockState(below);
        if (state.isAir()) {
            // Landed on a lip/slab edge: the supporting block can be one lower.
            below = below.below();
            state = level.getBlockState(below);
        }
        if (!state.isAir()) {
            level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, state),
                    player.getX(), player.getY() + 0.1D, player.getZ(),
                    DUST_COUNT, DUST_SPREAD_XZ, DUST_SPREAD_Y, DUST_SPREAD_XZ, DUST_SPEED);
        }
        float volume = Mth.clamp((float) (THUD_VOLUME_MIN + peakFall * 0.5D),
                THUD_VOLUME_MIN, THUD_VOLUME_MAX);
        level.playSound(null, player.blockPosition(), SoundEvents.WOOL_STEP,
                SoundSource.PLAYERS, volume, THUD_PITCH);
    }
}
