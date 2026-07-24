package dev.projecteclipse.eclipse.buffs;

import java.util.Collection;
import java.util.List;

import net.minecraft.server.MinecraftServer;

/**
 * Server-side timed buff facade (R16/R17). P4-B9 supplies the real implementation;
 * until then the {@link #HOLDER} defaults to a no-op so wave-B compiles cleanly.
 *
 * <p>P5 Xbox rewards call {@link #start(MinecraftServer, String, int)} with ids like
 * {@code double_skill_xp}.</p>
 */
public interface TimedBuffApi {
    /**
     * Starts or extends a buff. Returns {@code false} when refused (stack rule / cap).
     *
     * @param minutesOverride {@code <= 0} uses the definition's default duration
     * @param magnitudeOverride {@code <= 0} uses the definition's default magnitude
     */
    boolean start(MinecraftServer server, String id, int minutesOverride, float magnitudeOverride);

    /** Convenience overload using default minutes and magnitude. */
    default boolean start(MinecraftServer server, String id, int minutesOverride) {
        return start(server, id, minutesOverride, 0.0F);
    }

    /** Stops an active buff by id. Returns {@code false} if it was not active. */
    boolean stop(MinecraftServer server, String id);

    /** Currently active buff ids (immutable snapshot). */
    List<String> active(MinecraftServer server);

    /** Product of active multiplier buffs for {@code tag}; {@code 1.0f} when none apply. */
    float multiplier(MinecraftServer server, String tag);

    /** Whether {@code id} is currently active. */
    boolean isActive(MinecraftServer server, String id);

    /** Known buff definition ids (for command suggestions). Empty until config loads. */
    Collection<String> knownIds();

    /** Global holder swapped by {@code buffs.TimedBuffService} on server start. */
    TimedBuffApi NO_OP = new TimedBuffApi() {
        @Override
        public boolean start(MinecraftServer server, String id, int minutesOverride, float magnitudeOverride) {
            return false;
        }

        @Override
        public boolean stop(MinecraftServer server, String id) {
            return false;
        }

        @Override
        public List<String> active(MinecraftServer server) {
            return List.of();
        }

        @Override
        public float multiplier(MinecraftServer server, String tag) {
            return 1.0F;
        }

        @Override
        public boolean isActive(MinecraftServer server, String id) {
            return false;
        }

        @Override
        public Collection<String> knownIds() {
            return List.of();
        }
    };

    /** Active implementation; defaults to {@link #NO_OP}. */
    final class Holder {
        private static TimedBuffApi delegate = NO_OP;

        private Holder() {}

        public static TimedBuffApi get() {
            return delegate;
        }

        public static void set(TimedBuffApi api) {
            delegate = api != null ? api : NO_OP;
        }

        public static void reset() {
            delegate = NO_OP;
        }
    }

    /** Resets the holder when the server stops so a SP relaunch never keeps a stale delegate. */
    @net.neoforged.fml.common.EventBusSubscriber(modid = dev.projecteclipse.eclipse.EclipseMod.MOD_ID)
    final class Lifecycle {
        private Lifecycle() {}

        @net.neoforged.bus.api.SubscribeEvent
        static void onServerStopped(net.neoforged.neoforge.event.server.ServerStoppedEvent event) {
            Holder.reset();
        }
    }
}
