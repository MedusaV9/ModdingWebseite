package dev.projecteclipse.eclipse.glitchzone;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CGlitchZonePayload;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server tick driver of the GLITCHZONE event: expires zones, computes each player's active
 * zone + strength (spatial edge falloff × temporal fade, best zone wins when spheres
 * overlap) and syncs {@link S2CGlitchZonePayload} — but only when a player's value
 * MEANINGFULLY changes. The per-player change-detection cache means an idle server sends
 * ZERO glitch packets, a player standing deep inside a zone gets exactly one, and a player
 * walking the edge band gets a handful per second (strength epsilon {@value #EPSILON});
 * the client eases between samples so the coarse quantization never shows.
 *
 * <p>The event is SILENT by contract: this class never sends chat/titles/boss bars —
 * only the FX payload. {@code /dev glitch test} routes through {@link #startTest} so the
 * self-test participates in the same change-detection cache instead of fighting it.</p>
 *
 * <p>Static caches are transient per server run and cleared on {@link ServerStoppedEvent}
 * (the house rule: static state must never leak across singleplayer relaunches). A player
 * who logs in inside a zone needs no login hook — the absent cache entry reads as
 * "nothing sent yet", so the first tick sync covers it.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GlitchZoneService {
    /** Minimum strength delta worth a packet (client eases over it; ~50 steps edge-to-core). */
    private static final float EPSILON = 0.02F;
    /** Below this the player is "outside" and the sync snaps to an exact (none, 0). */
    private static final float MIN_STRENGTH = 0.005F;
    /** Fade-out window of a {@code /dev glitch test} self-test (1 s; fade-in is client-eased). */
    private static final int TEST_FADE_TICKS = 20;

    /** Last (effect, strength) actually synced per player — the change-detection cache. */
    private static final Map<UUID, Sent> LAST_SENT = new HashMap<>();
    /** Live {@code /dev glitch test} overrides per player (transient, never persisted). */
    private static final Map<UUID, TestOverride> TEST_OVERRIDES = new HashMap<>();

    private record Sent(String effect, float strength) {}

    private record TestOverride(String effect, long endGameTime) {}

    private GlitchZoneService() {}

    /**
     * Arms a personal self-test: the caller sees {@code effect} at full strength for
     * {@code seconds}, ramping out over the last {@value #TEST_FADE_TICKS} ticks. Runs
     * through the regular tick/sync path (never a direct send), so the cache stays honest.
     */
    public static void startTest(ServerPlayer player, String effect, int seconds) {
        long now = player.getServer().overworld().getGameTime();
        TEST_OVERRIDES.put(player.getUUID(), new TestOverride(effect, now + seconds * 20L));
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        long now = server.overworld().getGameTime();
        GlitchZoneState state = GlitchZoneState.get(server);
        state.removeExpired(now);
        TEST_OVERRIDES.values().removeIf(override -> override.endGameTime() <= now);

        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            sync(player, computeFor(player, state, now));
        }
    }

    /** Strongest (effect, strength) affecting the player right now, or (\"\", 0) outside. */
    private static Sent computeFor(ServerPlayer player, GlitchZoneState state, long now) {
        String bestEffect = "";
        float bestStrength = 0.0F;

        Vec3 pos = player.position();
        for (GlitchZone zone : state.all()) {
            if (zone.dim() != player.level().dimension()) {
                continue;
            }
            double distSqr = pos.distanceToSqr(
                    zone.centre().getX() + 0.5D, zone.centre().getY() + 0.5D, zone.centre().getZ() + 0.5D);
            float strength = zone.spatialStrength(distSqr) * zone.temporalStrength(now);
            if (strength > bestStrength) {
                bestStrength = strength;
                bestEffect = zone.effect();
            }
        }

        TestOverride test = TEST_OVERRIDES.get(player.getUUID());
        if (test != null) {
            long remaining = test.endGameTime() - now;
            float strength = Math.min(1.0F, remaining / (float) TEST_FADE_TICKS);
            if (strength > bestStrength) {
                bestStrength = strength;
                bestEffect = test.effect();
            }
        }

        if (bestStrength < MIN_STRENGTH) {
            return new Sent("", 0.0F);
        }
        return new Sent(bestEffect, Math.min(bestStrength, 1.0F));
    }

    /** Sends only on a meaningful change: effect switch, > epsilon move, or the 0/1 rails. */
    private static void sync(ServerPlayer player, Sent computed) {
        Sent last = LAST_SENT.get(player.getUUID());
        if (last == null) {
            last = new Sent("", 0.0F);
        }
        boolean changed = !computed.effect().equals(last.effect())
                || Math.abs(computed.strength() - last.strength()) > EPSILON
                // Snap the endpoints exactly: fully-in must reach 1, fully-out must reach 0.
                || (computed.strength() != last.strength()
                        && (computed.strength() == 0.0F || computed.strength() == 1.0F));
        if (!changed) {
            return;
        }
        LAST_SENT.put(player.getUUID(), computed);
        PacketDistributor.sendToPlayer(player,
                new S2CGlitchZonePayload(computed.effect(), computed.strength()));
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        LAST_SENT.remove(event.getEntity().getUUID());
        TEST_OVERRIDES.remove(event.getEntity().getUUID());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        LAST_SENT.clear();
        TEST_OVERRIDES.clear();
    }
}
