package dev.projecteclipse.eclipse.start;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.server.ServerLifecycleHooks;

/**
 * Persistent, deterministic player-to-start-disc assignment.
 *
 * <p>The first event-start cohort is de-duplicated and sorted by UUID, then distributed
 * round-robin over {@link DiscGeometry#PLAYER_DISC_COUNT}. Existing persisted assignments are
 * never moved: reconnects and server restarts resolve to the same anchor. Players added after
 * the initial cohort take a least-loaded disc, with the disc index as the stable tie-breaker.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StartAssignmentService {
    /** Stable ordering shared by persistence and deterministic assignment tests. */
    public static final Comparator<UUID> UUID_ORDER = UUID::compareTo;

    private StartAssignmentService() {}

    /**
     * Assigns the supplied player UUIDs and returns their resolved disc centers.
     *
     * <p>Calling this method again is idempotent for already-assigned UUIDs. New UUIDs are
     * appended without disturbing the event-start cohort.</p>
     */
    public static Map<UUID, BlockPos> assign(MinecraftServer server,
            Collection<UUID> playerIds) {
        if (server == null) {
            throw new IllegalArgumentException("server");
        }
        List<UUID> requested = sortedUnique(playerIds);
        StartState state = StartState.get(server);
        Map<UUID, Integer> next = new HashMap<>(state.assignments());

        if (!requested.isEmpty()) {
            if (next.isEmpty()) {
                next.putAll(assignIndexes(requested, DiscGeometry.PLAYER_DISC_COUNT));
            } else {
                int[] loads = anchorLoads(next.values(), DiscGeometry.PLAYER_DISC_COUNT);
                for (UUID uuid : requested) {
                    if (next.containsKey(uuid)) {
                        continue;
                    }
                    int index = leastLoaded(loads);
                    next.put(uuid, index);
                    loads[index]++;
                }
            }
        }

        if (!state.isAssigned() || !next.equals(state.assignments())) {
            state.setAssignments(next);
        }

        LinkedHashMap<UUID, BlockPos> result = new LinkedHashMap<>();
        for (UUID uuid : requested) {
            Integer index = next.get(uuid);
            if (index != null) {
                result.put(uuid, DiscGeometry.playerDiscCenter(index).immutable());
            }
        }
        return Map.copyOf(result);
    }

    /** Convenience overload for live player collections. */
    public static Map<UUID, BlockPos> assign(MinecraftServer server,
            Iterable<ServerPlayer> players) {
        LinkedHashSet<UUID> ids = new LinkedHashSet<>();
        if (players != null) {
            for (ServerPlayer player : players) {
                if (player != null) {
                    ids.add(player.getUUID());
                }
            }
        }
        return assign(server, ids);
    }

    /** Assigns every online player. */
    public static Map<UUID, BlockPos> assignAll(MinecraftServer server) {
        return assign(server, server.getPlayerList().getPlayers());
    }

    /** Resolves one assignment from the current server, if a server is running. */
    public static Optional<BlockPos> getAssigned(UUID uuid) {
        MinecraftServer server = ServerLifecycleHooks.getCurrentServer();
        return server == null ? Optional.empty() : getAssigned(server, uuid);
    }

    /** Resolves one persisted assignment without mutating state. */
    public static Optional<BlockPos> getAssigned(MinecraftServer server, UUID uuid) {
        if (server == null || uuid == null) {
            return Optional.empty();
        }
        Integer index = StartState.get(server).getIndex(uuid);
        return index == null
                ? Optional.empty()
                : Optional.of(DiscGeometry.playerDiscCenter(index).immutable());
    }

    /** Compatibility name from the P4 planner interface. */
    public static Optional<BlockPos> assignedAnchor(MinecraftServer server, UUID uuid) {
        return getAssigned(server, uuid);
    }

    /**
     * Pure deterministic mapping used by the live first cohort and gametests.
     *
     * @throws IllegalArgumentException when no anchors are available
     */
    public static Map<UUID, Integer> assignIndexes(Collection<UUID> playerIds,
            int anchorCount) {
        if (anchorCount <= 0) {
            throw new IllegalArgumentException("anchorCount must be positive");
        }
        List<UUID> sorted = sortedUnique(playerIds);
        LinkedHashMap<UUID, Integer> result = new LinkedHashMap<>();
        for (int i = 0; i < sorted.size(); i++) {
            result.put(sorted.get(i), i % anchorCount);
        }
        return Map.copyOf(result);
    }

    /**
     * Once event-start assignment exists, a late joiner receives a stable free/least-loaded
     * anchor immediately. Before event start, login does not create assignment state.
     */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        StartState state = StartState.get(player.server);
        if (state.isAssigned() && state.getIndex(player.getUUID()) == null) {
            assign(player.server, List.of(player.getUUID()));
        }
    }

    private static List<UUID> sortedUnique(Collection<UUID> playerIds) {
        if (playerIds == null || playerIds.isEmpty()) {
            return List.of();
        }
        ArrayList<UUID> sorted = new ArrayList<>();
        for (UUID uuid : new LinkedHashSet<>(playerIds)) {
            if (uuid != null) {
                sorted.add(uuid);
            }
        }
        sorted.sort(UUID_ORDER);
        return List.copyOf(sorted);
    }

    private static int[] anchorLoads(Collection<Integer> indexes, int anchorCount) {
        int[] loads = new int[anchorCount];
        for (Integer index : indexes) {
            if (index != null && index >= 0) {
                loads[Math.floorMod(index, anchorCount)]++;
            }
        }
        return loads;
    }

    private static int leastLoaded(int[] loads) {
        int best = 0;
        for (int i = 1; i < loads.length; i++) {
            if (loads[i] < loads[best]) {
                best = i;
            }
        }
        return best;
    }
}
