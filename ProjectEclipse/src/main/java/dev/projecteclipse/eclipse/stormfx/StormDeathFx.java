package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.Holder;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * WAVE5 (F-105 B) B2 — "der Nebel schluckt den Schrei" (IDEA-15 §4): a player death INSIDE
 * a standing storm becomes a three-lane beat instead of silence.
 *
 * <ul>
 * <li><b>corpse</b> — the fog inhales the body: two shrinking CLOUD rings (6→2 blocks over
 *     {@value #INHALE_TICKS}t, particles rushing inward) + one muffled
 *     {@code event.storm_burst} at the corpse.</li>
 * <li><b>outside</b> — every in-dimension listener OUTSIDE the radius but within
 *     {@value #SHELL_HEARING_BLOCKS} blocks of the shell hears a muffled scream from THEIR
 *     nearest shell point ({@code center + n̂·radius}, the {@code StormLoopSound.updatePosition}
 *     projection — the wall screams, never the corpse), then {@value #RUMBLE_DELAY_TICKS}t
 *     later a far lightning rumble from the same point (the storm "digesting").</li>
 * <li><b>inside</b> — everyone inside the swallowing storm gets a {@value #SURGE_TICKS}t rain
 *     surge ({@link FxPayloads#FX_STORM_SURGE} → {@code EclipseFxState.startStormRainSurge},
 *     RainAmount ×{@value #SURGE_RAIN_MUL}).</li>
 * </ul>
 *
 * <p><b>Pure event subscriber</b> on {@link LivingDeathEvent} at {@link EventPriority#LOW}
 * (house precedent {@code drama.WitnessedLossService} — that file stays untouched): LOW runs
 * after the lives/hearts NORMAL chain, so a death another system cancels never fires the
 * swallow. The delayed beats ride a {@code StormReveal}-pattern pending list, flushed on
 * {@link ServerStoppedEvent}. Respawn/ghost flow is untouched — this class only ADDS fx.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StormDeathFx {
    /** Outside lane reach: listeners at most this many blocks from the SHELL (not center). */
    private static final double SHELL_HEARING_BLOCKS = 96.0D;
    /** Corpse-inhale ring choreography: radius 6→2 blocks over 10 ticks, two stacked rings. */
    private static final int INHALE_TICKS = 10;
    private static final float RING_START_RADIUS = 6.0F;
    private static final float RING_END_RADIUS = 2.0F;
    /** Points per ring per tick (2 rings × 12 × 10t = 240 particles — well under budget). */
    private static final int RING_POINTS = 12;
    private static final double RING_LOW_Y = 0.4D;
    private static final double RING_HIGH_Y = 1.3D;
    /** Inward rush speed of the ring particles (count-0 sendParticles velocity lane). */
    private static final double INHALE_SPEED = 0.18D;
    /** The muffled swallow boom at the corpse (plan §4: volume 0.6; pitched down = muffled). */
    private static final float CORPSE_BURST_VOLUME = 0.6F;
    private static final float CORPSE_BURST_PITCH = 0.7F;
    /** The scream through the wall (plan §4: PLAYER_HURT 0.9/0.55 — slow = big + far). */
    private static final float SCREAM_VOLUME = 0.9F;
    private static final float SCREAM_PITCH = 0.55F;
    /** The "digestion" rumble: far lightning from the same shell point, 8t after the scream. */
    private static final int RUMBLE_DELAY_TICKS = 8;
    private static final float RUMBLE_VOLUME = 0.7F;
    private static final float RUMBLE_PITCH = 0.85F;
    /** Inside lane: 15t RainAmount surge ×1.6 (IDEA-15 §4 numbers, carried in the payload). */
    private static final float SURGE_RAIN_MUL = 1.6F;
    private static final int SURGE_TICKS = 15;

    /** One outside listener's delayed rumble: resolved by UUID so a logout never NPEs. */
    private record ShellListener(UUID player, Vec3 shellPoint) {}

    /** One swallow's delayed beats (corpse inhale rings + outside rumbles), tick-driven. */
    private static final class PendingSwallow {
        final ResourceKey<Level> dimension;
        final Vec3 corpse;
        final Vec3 stormCenter;
        final List<ShellListener> rumbles;
        int elapsed;

        PendingSwallow(ResourceKey<Level> dimension, Vec3 corpse, Vec3 stormCenter,
                List<ShellListener> rumbles) {
            this.dimension = dimension;
            this.corpse = corpse;
            this.stormCenter = stormCenter;
            this.rumbles = rumbles;
        }
    }

    private static final List<PendingSwallow> PENDING = new ArrayList<>(2);

    private StormDeathFx() {}

    /** LOW: after the lives/hearts NORMAL death chain (WitnessedLossService bracket law). */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)
                || !(victim.level() instanceof ServerLevel level)) {
            return;
        }
        StormRegistry.StormData storm = swallowingStorm(level, victim.position());
        if (storm == null) {
            return;
        }
        Vec3 corpse = victim.position();
        EclipseMod.LOGGER.debug("[w5b-swallow] corpse player={} pos=({}, {}, {}) storm={} r={}",
                victim.getScoreboardName(), fmt(corpse.x), fmt(corpse.y), fmt(corpse.z),
                storm.stormId(), storm.radius());
        // Corpse lane, immediate half: the muffled boom (rings run on the pending ticker).
        level.playSound(null, corpse.x, corpse.y, corpse.z,
                EclipseSounds.EVENT_STORM_BURST.get(), SoundSource.WEATHER,
                CORPSE_BURST_VOLUME, CORPSE_BURST_PITCH);

        List<ShellListener> rumbles = new ArrayList<>(4);
        int insideCount = 0;
        for (ServerPlayer listener : level.players()) {
            double dx = listener.getX() - storm.center().x;
            double dz = listener.getZ() - storm.center().z;
            double dist = Math.sqrt(dx * dx + dz * dz);
            if (dist < storm.radius()) {
                // Inside lane: the swallowing storm's rain slams up for a beat (the victim
                // included — their client rides the surge into the death screen).
                FxPayloads.sendFxEventTo(listener, FxPayloads.FX_STORM_SURGE, corpse,
                        SURGE_RAIN_MUL, SURGE_TICKS);
                insideCount++;
            } else if (dist - storm.radius() <= SHELL_HEARING_BLOCKS) {
                // Outside lane: scream from the listener's OWN nearest shell point
                // (StormLoopSound.updatePosition projection — per-listener, so this is a
                // per-player sound packet, never a level.playSound broadcast).
                Vec3 shell = projectToShell(storm, listener, dist < 1.0E-3D ? null
                        : new Vec3(dx / dist, 0.0D, dz / dist));
                sendPositional(level, listener, SoundEvents.PLAYER_HURT, SoundSource.PLAYERS,
                        shell, SCREAM_VOLUME, SCREAM_PITCH);
                rumbles.add(new ShellListener(listener.getUUID(), shell));
                EclipseMod.LOGGER.debug("[w5b-swallow] outside listener={} shell=({}, {}, {})",
                        listener.getScoreboardName(), fmt(shell.x), fmt(shell.y), fmt(shell.z));
            }
        }
        EclipseMod.LOGGER.debug("[w5b-swallow] inside surge x{} for {}t to {} player(s)",
                SURGE_RAIN_MUL, SURGE_TICKS, insideCount);
        PENDING.add(new PendingSwallow(level.dimension(), corpse, storm.center(), rumbles));
    }

    /** Ticks the corpse-inhale rings and fires the delayed outside rumbles. */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (PENDING.isEmpty()) {
            return;
        }
        for (int i = PENDING.size() - 1; i >= 0; i--) {
            PendingSwallow swallow = PENDING.get(i);
            swallow.elapsed++;
            ServerLevel level = event.getServer().getLevel(swallow.dimension);
            if (level == null) {
                PENDING.remove(i);
                continue;
            }
            if (swallow.elapsed <= INHALE_TICKS) {
                emitInhaleRings(level, swallow);
            }
            if (swallow.elapsed == RUMBLE_DELAY_TICKS) {
                for (ShellListener rumble : swallow.rumbles) {
                    ServerPlayer listener = event.getServer().getPlayerList().getPlayer(rumble.player());
                    if (listener != null && listener.level() == level) {
                        sendPositional(level, listener, EclipseSounds.EVENT_LIGHTNING_FAR.get(),
                                SoundSource.WEATHER, rumble.shellPoint(), RUMBLE_VOLUME, RUMBLE_PITCH);
                    }
                }
            }
            if (swallow.elapsed >= Math.max(INHALE_TICKS, RUMBLE_DELAY_TICKS)) {
                PENDING.remove(i);
            }
        }
    }

    /**
     * The storm swallowing {@code pos}, or {@code null}: horizontally inside the radius of a
     * SPAWN/ACTIVE storm (a dissipating/exploding storm has released its grip — no swallow).
     * Ties go to the storm the position sits deepest inside of, matching what that player's
     * own {@code StormInteriorFx} shows them.
     */
    @Nullable
    private static StormRegistry.StormData swallowingStorm(ServerLevel level, Vec3 pos) {
        StormRegistry.StormData best = null;
        double bestDepth = 0.0D;
        for (StormRegistry.StormData storm : StormRegistry.storms(level)) {
            if (storm.state() != S2CStormStatePayload.STATE_SPAWN
                    && storm.state() != S2CStormStatePayload.STATE_ACTIVE) {
                continue;
            }
            double dx = pos.x - storm.center().x;
            double dz = pos.z - storm.center().z;
            double dist = Math.sqrt(dx * dx + dz * dz);
            double depth = 1.0D - dist / Math.max(1.0E-3D, storm.radius());
            if (depth > bestDepth) {
                bestDepth = depth;
                best = storm;
            }
        }
        return best;
    }

    /**
     * The listener's nearest shell point: {@code center + n̂·radius} on the horizontal plane,
     * y clamped into the wall band exactly like {@code StormLoopSound.updatePosition} — so
     * the scream comes from where that listener already hears the storm roaring.
     */
    private static Vec3 projectToShell(StormRegistry.StormData storm, ServerPlayer listener,
            @Nullable Vec3 outwardNormal) {
        double nx = outwardNormal == null ? 1.0D : outwardNormal.x;
        double nz = outwardNormal == null ? 0.0D : outwardNormal.z;
        double y = Mth.clamp(listener.getY(), storm.center().y + 2.0D,
                storm.center().y + storm.height() * 0.6D);
        return new Vec3(storm.center().x + nx * storm.radius(), y,
                storm.center().z + nz * storm.radius());
    }

    /** Two stacked CLOUD rings shrinking 6→2 blocks, every particle rushing at the corpse. */
    private static void emitInhaleRings(ServerLevel level, PendingSwallow swallow) {
        float shrink = swallow.elapsed / (float) INHALE_TICKS;
        double radius = Mth.lerp(shrink, RING_START_RADIUS, RING_END_RADIUS);
        // The two rings counter-rotate a little per tick so they read as a vortex, not a grid.
        double spin = swallow.elapsed * 0.35D;
        emitRing(level, swallow.corpse, radius, RING_LOW_Y, spin);
        emitRing(level, swallow.corpse, radius, RING_HIGH_Y, -spin + Math.PI / RING_POINTS);
    }

    private static void emitRing(ServerLevel level, Vec3 corpse, double radius, double yOffset,
            double phase) {
        double y = corpse.y + yOffset;
        for (int p = 0; p < RING_POINTS; p++) {
            double angle = phase + (Math.PI * 2.0D * p) / RING_POINTS;
            double x = corpse.x + Math.cos(angle) * radius;
            double z = corpse.z + Math.sin(angle) * radius;
            // count 0 → (dx,dy,dz) is a velocity: rush inward+slightly down onto the corpse.
            level.sendParticles(ParticleTypes.CLOUD, x, y, z, 0,
                    -Math.cos(angle), -0.1D, -Math.sin(angle), INHALE_SPEED);
        }
    }

    /** Positional one-shot to EXACTLY one player (the {@code BackroomsDread} packet law). */
    private static void sendPositional(ServerLevel level, ServerPlayer listener, SoundEvent sound,
            SoundSource source, Vec3 pos, float volume, float pitch) {
        Holder<SoundEvent> holder = BuiltInRegistries.SOUND_EVENT.wrapAsHolder(sound);
        listener.connection.send(new ClientboundSoundPacket(holder, source, pos.x, pos.y, pos.z,
                volume, pitch, level.getRandom().nextLong()));
    }

    /** Probe-friendly one-decimal coordinate (debug.log greps stay short). */
    private static String fmt(double v) {
        return String.format(java.util.Locale.ROOT, "%.1f", v);
    }

    /** Integrated-server restarts must never leak pending beats into the next world. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        PENDING.clear();
    }
}
