package dev.projecteclipse.eclipse.analytics;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * FROZEN query surface over the per-day analytics store (P4 §2.4). Consumers: P4-B6 awards
 * (candidate collection + leaderboards at {@code dayRollover PRE}), P5-W4 dev commands,
 * P4-B2 goal triggers ({@code travel_distance} deltas). All queries are read-only,
 * server-thread, and O(players × keys) at worst — safe at command/rollover cadence.
 *
 * <p>Category ids are the {@link AnalyticsKeys} namespace: static ids from
 * {@link #categories()} plus dynamic {@code kill:<entity_id>} / {@code mine:<block_id>} /
 * {@code craft:<item_id>} keys (see {@link AnalyticsKeys#dynamicPrefixes()}).</p>
 */
public final class AnalyticsApi {
    /** One leaderboard row: player UUID + counter value. */
    public record Entry(UUID uuid, long value) {}

    private AnalyticsApi() {}

    /** Counter value for (day, player, category); 0 when unknown. Offline players are queryable. */
    public static long value(MinecraftServer server, int day, UUID player, String key) {
        return AnalyticsState.get(server).value(day, player, key);
    }

    /**
     * Leaderboard for {@code key} on {@code day}: every player with ANY analytics that day,
     * sorted by value descending (missing key = 0, still listed so min-order award categories
     * can rank "untouched" players); ties break by UUID for determinism. {@code n <= 0}
     * returns all rows. Callers wanting "all tied at best" read rows until the value drops.
     */
    public static List<Entry> top(MinecraftServer server, int day, String key, int n) {
        return AnalyticsState.get(server).top(day, key, n);
    }

    /** Sum of {@code key} for one player across every retained day. */
    public static long sumAcrossDays(MinecraftServer server, UUID player, String key) {
        return AnalyticsState.get(server).sumAcrossDays(player, key);
    }

    /** Every counter key present on {@code day} (union across players; bounded by key caps). */
    public static Set<String> keys(MinecraftServer server, int day) {
        return AnalyticsState.get(server).keys(day);
    }

    /**
     * Union of currently-online player UUIDs and every UUID with analytics data on
     * {@code day} — the awards candidate universe (offline players included by design).
     */
    public static Set<UUID> onlineOrKnownUuids(MinecraftServer server, int day) {
        Set<UUID> uuids = new HashSet<>(AnalyticsState.get(server).knownUuids(day));
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            uuids.add(online.getUUID());
        }
        return uuids;
    }

    /** All static category ids, in documented order (see {@link AnalyticsKeys}). */
    public static List<String> categories() {
        return AnalyticsKeys.categories();
    }
}
