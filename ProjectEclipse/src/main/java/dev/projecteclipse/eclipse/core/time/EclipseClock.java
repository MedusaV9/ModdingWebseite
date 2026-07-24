package dev.projecteclipse.eclipse.core.time;

import java.util.function.LongSupplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Injectable wall-clock for real-time P4 systems (day boundaries, timed buffs).
 * Production code reads {@link #epochMillis()}; gametests swap in a deterministic
 * supplier via {@link #setEpochMillisSupplier(LongSupplier)}.
 */
@EventBusSubscriber(modid = dev.projecteclipse.eclipse.EclipseMod.MOD_ID)
public final class EclipseClock {
    // statics reset on ServerStopped
    private static LongSupplier epochMillisSupplier = System::currentTimeMillis;

    private EclipseClock() {}

    /** Current epoch millis from the active supplier (system clock by default). */
    public static long epochMillis() {
        return epochMillisSupplier.getAsLong();
    }

    /**
     * Replaces the clock source. Gametests should restore with {@link #resetToSystem()}
     * or rely on {@link #onServerStopped}.
     */
    public static void setEpochMillisSupplier(LongSupplier supplier) {
        epochMillisSupplier = supplier != null ? supplier : System::currentTimeMillis;
    }

    /** Restores the JVM system clock supplier. */
    public static void resetToSystem() {
        epochMillisSupplier = System::currentTimeMillis;
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        resetToSystem();
        EclipseMod.LOGGER.debug("EclipseClock supplier reset to system default");
    }
}
