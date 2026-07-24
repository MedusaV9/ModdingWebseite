package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server-side storm REVEAL choreography (P2 W9, R14) — the two-phase handshake with P1's
 * fog-storm area apply (§6.1 contract):
 *
 * <pre>{@code
 * // P1 (FogStormSites / area apply), AFTER the area terrain has loaded under the future storm:
 * StormReveal.request(level, areaId, center, radius, height, () -> finishLoading(areaId));
 * }</pre>
 *
 * <p>Timeline from the request (constants frozen on {@link StormRegistry}): the storm is
 * announced immediately as a reveal-style SPAWN ({@code ticks =
 * }{@link StormRegistry#REVEAL_TOTAL_TICKS}) so every client holds it invisible → 40-tick
 * pause → the client pulses a 0.4 {@code rift_glitch} ({@link StormFxClient} runs that beat)
 * → five hammer strikes over 60 ticks (sent as {@code eclipse:fx/lightning_strike} events —
 * W1's dispatch reconstructs the sky origin and calls {@code StormFxClient.strikeLightning};
 * strike CRACKS are played here, per the sender-owns-audio rule) → the shells ramp in over
 * the final 80 ticks → {@code finishLoading} runs, letting P1 finalize the area interior
 * invisible to outside observers (the wall is fully opaque by then).</p>
 *
 * <p>Deviation from the §6.1 sketch, noted in the wiring doc: the signature carries the
 * {@link ServerLevel} up front — a reveal cannot broadcast without its dimension. Fallback
 * path (risk §7.10): if P1's two-phase hook never calls this, storms still stand up via
 * {@link StormRegistry#handleFogSite} / dev commands with the plain 80-tick ramp — the reveal
 * is purely additive drama. {@code finishLoading} is guaranteed to run exactly once, even if
 * the server stops mid-reveal (flushed on {@link ServerStoppedEvent}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StormReveal {
    /** First hammer strike, ticks after the request (pause + glitch). */
    private static final int STRIKE_START_TICKS =
            StormRegistry.REVEAL_PAUSE_TICKS + StormRegistry.REVEAL_GLITCH_TICKS;
    private static final int STRIKE_COUNT = 5;
    private static final int STRIKE_INTERVAL_TICKS = StormRegistry.REVEAL_STRIKE_TICKS / (STRIKE_COUNT - 1) - 3;

    private static final class PendingReveal {
        final ResourceKey<Level> dimension;
        final String areaId;
        final Vec3 center;
        final float radius;
        final float height;
        Runnable finishLoading;
        int elapsed;
        int strikesFired;

        PendingReveal(ResourceKey<Level> dimension, String areaId, Vec3 center,
                float radius, float height, Runnable finishLoading) {
            this.dimension = dimension;
            this.areaId = areaId;
            this.center = center;
            this.radius = radius;
            this.height = height;
            this.finishLoading = finishLoading;
        }

        /** Runs the P1 callback exactly once, shielded — a throwing callback must not stall others. */
        void finish() {
            Runnable callback = finishLoading;
            finishLoading = null;
            if (callback != null) {
                try {
                    callback.run();
                } catch (Throwable t) {
                    EclipseMod.LOGGER.error("Storm reveal finishLoading callback for area {} threw", areaId, t);
                }
            }
        }
    }

    private static final List<PendingReveal> PENDING = new ArrayList<>(4);

    private StormReveal() {}

    /**
     * Frozen P1 contract (§6.1): call AFTER the area terrain is loaded; P2 plays the reveal
     * and invokes {@code finishLoading} once the storm wall is fully opaque. {@code radius
     * <= 0} / {@code height <= 0} fall back to {@link StormRegistry#DEFAULT_RADIUS} /
     * {@link StormRegistry#heightFor}. A repeat request for a live area restarts the reveal
     * (the previous {@code finishLoading} runs first so P1 is never left hanging).
     */
    public static void request(ServerLevel level, String areaId, Vec3 center, float radius,
            float height, Runnable finishLoading) {
        float r = radius > 0.0F ? radius : StormRegistry.DEFAULT_RADIUS;
        float h = height > 0.0F ? height : StormRegistry.heightFor(r);
        for (int i = PENDING.size() - 1; i >= 0; i--) {
            if (PENDING.get(i).areaId.equals(areaId)) {
                EclipseMod.LOGGER.warn("Storm reveal for area {} re-requested mid-reveal; restarting", areaId);
                PENDING.remove(i).finish();
            }
        }
        StormRegistry.beginRevealStorm(level, areaId, center, r, h);
        PENDING.add(new PendingReveal(level.dimension(), areaId, center, r, h, finishLoading));
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (PENDING.isEmpty()) {
            return;
        }
        for (int i = PENDING.size() - 1; i >= 0; i--) {
            PendingReveal reveal = PENDING.get(i);
            reveal.elapsed++;
            ServerLevel level = event.getServer().getLevel(reveal.dimension);
            if (level == null) {
                reveal.finish();
                PENDING.remove(i);
                continue;
            }
            // Hammer strikes (beat 3): ramping intensity, cracks played server-side.
            while (reveal.strikesFired < STRIKE_COUNT
                    && reveal.elapsed >= STRIKE_START_TICKS + reveal.strikesFired * STRIKE_INTERVAL_TICKS) {
                fireStrike(level, reveal, reveal.strikesFired++);
            }
            if (reveal.elapsed >= StormRegistry.REVEAL_TOTAL_TICKS) {
                reveal.finish();
                PENDING.remove(i);
            }
        }
    }

    /** One hammer strike onto the storm's top rim; audio is the sender's job (W1 wiring rule). */
    private static void fireStrike(ServerLevel level, PendingReveal reveal, int index) {
        RandomSource random = level.getRandom();
        double angle = random.nextDouble() * Math.PI * 2.0D;
        double reach = reveal.radius * (0.15D + random.nextDouble() * 0.55D);
        Vec3 impact = new Vec3(
                reveal.center.x + Math.cos(angle) * reach,
                reveal.center.y + reveal.height + 4.0D,
                reveal.center.z + Math.sin(angle) * reach);
        float intensity = Mth.clamp(0.55F + 0.45F * (index / (float) (STRIKE_COUNT - 1)), 0.0F, 1.0F);
        // Whole dimension (range <= 0): reveal strikes are landmark events, like the storm itself.
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F, 0.0D);
        level.playSound(null, impact.x, impact.y, impact.z,
                EclipseSounds.EVENT_LIGHTNING_CLOSE.get(), SoundSource.WEATHER,
                2.5F + intensity * 1.5F, 0.8F + 0.08F * index);
        if (index == STRIKE_COUNT - 1) {
            // The last hammer doubles as the "storm takes hold" release.
            level.playSound(null, reveal.center.x, reveal.center.y, reveal.center.z,
                    EclipseSounds.EVENT_STORM_BURST.get(), SoundSource.WEATHER, 2.0F, 0.95F);
        }
    }

    /** Server stop mid-reveal: flush every pending P1 callback so no area stays half-loaded. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        for (int i = 0; i < PENDING.size(); i++) {
            PENDING.get(i).finish();
        }
        PENDING.clear();
    }
}
