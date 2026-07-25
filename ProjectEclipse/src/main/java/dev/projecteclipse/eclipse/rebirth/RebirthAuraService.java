package dev.projecteclipse.eclipse.rebirth;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * D11 rebirth keepsake (V6 gap-fix): a subtle purple {@code WITCH} particle ring slowly
 * orbiting the feet of every player with at least one completed rebirth — the durable,
 * wordless marker of the ceremony. Toggleable per player via {@code /skills aura on|off}
 * ({@code RebirthState.Entry#auraEnabled}; the marker itself is {@code count > 0} and
 * never expires).
 *
 * <p>Deliberately lightweight, following the {@code drama.HearthAuraService}
 * {@code sendParticles} craft (server-side vanilla particles — every nearby client sees
 * the ring with zero extra payloads or render hooks): every {@value #EMIT_INTERVAL_TICKS}
 * ticks, {@value #RING_POINTS} single particles on a r={@value #RING_RADIUS} circle whose
 * phase advances with game time, so the ring visibly rotates instead of strobing. Hidden
 * for spectators, the invisible (potion/sneak-gameplay respect) and banned ghosts —
 * a cosmetic must never leak positions.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RebirthAuraService {
    /** Emit cadence (0.5 s) — slow enough to stay subtle, fast enough to read as a ring. */
    private static final int EMIT_INTERVAL_TICKS = 10;
    /** Ring radius around the player's feet. */
    private static final double RING_RADIUS = 0.85D;
    /** Particles per emit — kept tiny (subtle keepsake, not a boss telegraph). */
    private static final int RING_POINTS = 3;
    /** Ring rotation speed (radians per tick). */
    private static final double SPIN_PER_TICK = 0.05D;

    private RebirthAuraService() {}

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % EMIT_INTERVAL_TICKS != 0
                || server.getPlayerList().getPlayerCount() == 0) {
            return;
        }
        RebirthState state = RebirthState.get(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator() || player.isDeadOrDying() || player.isInvisible()
                    || player.getData(EclipseAttachments.BANNED)
                    || !state.auraVisible(player.getUUID())) {
                continue;
            }
            ServerLevel level = player.serverLevel();
            double spin = level.getGameTime() * SPIN_PER_TICK;
            for (int i = 0; i < RING_POINTS; i++) {
                double angle = spin + i * (Math.PI * 2.0D / RING_POINTS);
                level.sendParticles(ParticleTypes.WITCH,
                        player.getX() + Math.cos(angle) * RING_RADIUS,
                        player.getY() + 0.15D,
                        player.getZ() + Math.sin(angle) * RING_RADIUS,
                        1, 0.02D, 0.05D, 0.02D, 0.0D);
            }
        }
    }
}
