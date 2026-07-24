package dev.projecteclipse.eclipse.analytics;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import it.unimi.dsi.fastutil.ints.IntOpenHashSet;
import it.unimi.dsi.fastutil.objects.Object2LongMap;
import it.unimi.dsi.fastutil.objects.Object2LongOpenHashMap;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save analytics store ({@code data/eclipse_analytics.dat}, overworld storage): day →
 * player UUID → counter key → long, plus the per-player LIFETIME visited-biome set (stored
 * once, not per day — P4 §2.4). Keyed by UUID (not attachments) so offline players stay
 * queryable for awards. Serialized compactly: one compound of {@code key → long} per
 * (day, player). All mutators mark dirty; disk writes happen on autosave only.
 *
 * <p>Bounded by construction: static keys are a fixed set ({@link AnalyticsKeys}); dynamic
 * {@code kill:/mine:/craft:} keys are capped per (player, day) via
 * {@link #addDynamic(int, UUID, String, long, int)} and craft ids are allowlisted upstream.
 * {@link #pruneDaysBefore(int)} applies the {@code retentionDays} window on rollover.</p>
 */
public final class AnalyticsState extends SavedData {
    public static final String DATA_NAME = "eclipse_analytics";

    private static final String TAG_DAYS = "days";
    private static final String TAG_DAY = "d";
    private static final String TAG_PLAYERS = "p";
    private static final String TAG_PLAYER_ID = "id";
    private static final String TAG_COUNTERS = "k";
    private static final String TAG_PLACE_TYPES = "placeTypes";
    private static final String TAG_CHUNKS = "chunks";
    private static final String TAG_BIOMES = "biomes";
    private static final String TAG_BIOME_VALUES = "v";

    private final Map<Integer, Map<UUID, Object2LongOpenHashMap<String>>> days = new HashMap<>();
    private final Map<Integer, Map<UUID, IntOpenHashSet>> placeTypeHashesByDay = new HashMap<>();
    private final Map<Integer, Map<UUID, Set<String>>> chunksByDay = new HashMap<>();
    private final Map<UUID, Set<String>> biomesLifetime = new HashMap<>();

    public AnalyticsState() {}

    public static AnalyticsState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(AnalyticsState::new, AnalyticsState::load));
    }

    public static AnalyticsState load(CompoundTag tag, HolderLookup.Provider registries) {
        AnalyticsState state = new AnalyticsState();
        for (Tag dayEntry : tag.getList(TAG_DAYS, Tag.TAG_COMPOUND)) {
            CompoundTag dayTag = (CompoundTag) dayEntry;
            int day = dayTag.getInt(TAG_DAY);
            Map<UUID, Object2LongOpenHashMap<String>> players = new HashMap<>();
            for (Tag playerEntry : dayTag.getList(TAG_PLAYERS, Tag.TAG_COMPOUND)) {
                CompoundTag playerTag = (CompoundTag) playerEntry;
                if (!playerTag.hasUUID(TAG_PLAYER_ID)) {
                    continue;
                }
                Object2LongOpenHashMap<String> counters = new Object2LongOpenHashMap<>();
                CompoundTag counterTag = playerTag.getCompound(TAG_COUNTERS);
                for (String key : counterTag.getAllKeys()) {
                    counters.put(key, counterTag.getLong(key));
                }
                UUID player = playerTag.getUUID(TAG_PLAYER_ID);
                players.put(player, counters);
                if (playerTag.contains(TAG_PLACE_TYPES, Tag.TAG_INT_ARRAY)) {
                    state.placeTypeHashesByDay
                            .computeIfAbsent(day, ignored -> new HashMap<>())
                            .put(player, new IntOpenHashSet(playerTag.getIntArray(TAG_PLACE_TYPES)));
                }
                if (playerTag.contains(TAG_CHUNKS, Tag.TAG_LIST)) {
                    Set<String> chunks = new HashSet<>();
                    for (Tag value : playerTag.getList(TAG_CHUNKS, Tag.TAG_STRING)) {
                        chunks.add(value.getAsString());
                    }
                    state.chunksByDay.computeIfAbsent(day, ignored -> new HashMap<>())
                            .put(player, chunks);
                }
            }
            state.days.put(day, players);
        }
        for (Tag biomeEntry : tag.getList(TAG_BIOMES, Tag.TAG_COMPOUND)) {
            CompoundTag biomeTag = (CompoundTag) biomeEntry;
            if (!biomeTag.hasUUID(TAG_PLAYER_ID)) {
                continue;
            }
            Set<String> visited = new HashSet<>();
            for (Tag value : biomeTag.getList(TAG_BIOME_VALUES, Tag.TAG_STRING)) {
                visited.add(value.getAsString());
            }
            state.biomesLifetime.put(biomeTag.getUUID(TAG_PLAYER_ID), visited);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag dayList = new ListTag();
        for (Map.Entry<Integer, Map<UUID, Object2LongOpenHashMap<String>>> dayEntry : days.entrySet()) {
            CompoundTag dayTag = new CompoundTag();
            dayTag.putInt(TAG_DAY, dayEntry.getKey());
            ListTag playerList = new ListTag();
            for (Map.Entry<UUID, Object2LongOpenHashMap<String>> playerEntry : dayEntry.getValue().entrySet()) {
                CompoundTag playerTag = new CompoundTag();
                playerTag.putUUID(TAG_PLAYER_ID, playerEntry.getKey());
                CompoundTag counterTag = new CompoundTag();
                for (Object2LongMap.Entry<String> counter : playerEntry.getValue().object2LongEntrySet()) {
                    counterTag.putLong(counter.getKey(), counter.getLongValue());
                }
                playerTag.put(TAG_COUNTERS, counterTag);
                IntOpenHashSet placeTypes = placeTypeHashesByDay
                        .getOrDefault(dayEntry.getKey(), Map.of()).get(playerEntry.getKey());
                if (placeTypes != null) {
                    playerTag.putIntArray(TAG_PLACE_TYPES, placeTypes.toIntArray());
                }
                Set<String> chunks = chunksByDay
                        .getOrDefault(dayEntry.getKey(), Map.of()).get(playerEntry.getKey());
                if (chunks != null) {
                    ListTag values = new ListTag();
                    chunks.stream().sorted().forEach(chunk -> values.add(StringTag.valueOf(chunk)));
                    playerTag.put(TAG_CHUNKS, values);
                }
                playerList.add(playerTag);
            }
            dayTag.put(TAG_PLAYERS, playerList);
            dayList.add(dayTag);
        }
        tag.put(TAG_DAYS, dayList);

        ListTag biomeList = new ListTag();
        for (Map.Entry<UUID, Set<String>> entry : biomesLifetime.entrySet()) {
            CompoundTag biomeTag = new CompoundTag();
            biomeTag.putUUID(TAG_PLAYER_ID, entry.getKey());
            ListTag values = new ListTag();
            for (String biome : entry.getValue()) {
                values.add(StringTag.valueOf(biome));
            }
            biomeTag.put(TAG_BIOME_VALUES, values);
            biomeList.add(biomeTag);
        }
        tag.put(TAG_BIOMES, biomeList);
        return tag;
    }

    // --- write paths ---

    /** Adds {@code delta} to a STATIC counter (never capped) and returns the new value. */
    public long add(int day, UUID player, String key, long delta) {
        Object2LongOpenHashMap<String> counters = countersFor(day, player);
        long updated = counters.addTo(key, delta) + delta;
        setDirty();
        return updated;
    }

    /**
     * Adds {@code delta} to a DYNAMIC ({@code kill:/mine:/craft:}) counter unless the
     * (player, day) map already holds {@code maxKeysPerPlayer} distinct keys and this key
     * is new — then the per-id detail is dropped (fail-safe under-crediting; the caller's
     * {@code *_total} aggregate still counts). Returns whether the counter was credited.
     */
    public boolean addDynamic(int day, UUID player, String key, long delta, int maxKeysPerPlayer) {
        Object2LongOpenHashMap<String> counters = countersFor(day, player);
        if (!counters.containsKey(key) && counters.size() >= maxKeysPerPlayer) {
            return false;
        }
        counters.addTo(key, delta);
        setDirty();
        return true;
    }

    /** Raises a counter to {@code value} if it is higher than the stored one (depth tracking). */
    public void max(int day, UUID player, String key, long value) {
        Object2LongOpenHashMap<String> counters = countersFor(day, player);
        if (value > counters.getLong(key)) {
            counters.put(key, value);
            setDirty();
        }
    }

    /**
     * Marks one block-type hash as seen for this player/day. Old saves with a positive
     * aggregate but no identity set fail closed for the rest of that day after an upgrade.
     */
    public boolean markPlaceType(int day, UUID player, int blockTypeHash) {
        Map<UUID, IntOpenHashSet> players =
                placeTypeHashesByDay.computeIfAbsent(day, ignored -> new HashMap<>());
        IntOpenHashSet types = players.get(player);
        if (types == null) {
            if (value(day, player, AnalyticsKeys.PLACE_TYPES) > 0L) {
                return false;
            }
            types = new IntOpenHashSet();
            players.put(player, types);
        }
        boolean added = types.add(blockTypeHash);
        if (added) {
            setDirty();
        }
        return added;
    }

    /**
     * Marks one dimension-qualified chunk identity as seen for this player/day. The set is
     * persisted and capped, so restarts cannot re-fire exploration rewards.
     */
    public boolean markChunkVisited(int day, UUID player, String chunkId, int maxChunks) {
        Map<UUID, Set<String>> players = chunksByDay.computeIfAbsent(day, ignored -> new HashMap<>());
        Set<String> chunks = players.get(player);
        if (chunks == null) {
            if (value(day, player, AnalyticsKeys.CHUNKS_NEW) > 0L) {
                return false;
            }
            chunks = new HashSet<>();
            players.put(player, chunks);
        }
        if (chunks.contains(chunkId) || chunks.size() >= maxChunks) {
            return false;
        }
        chunks.add(chunkId);
        setDirty();
        return true;
    }

    /** Drops distinct-identity sets once an ended day has frozen. */
    public void clearDistinctDay(int day) {
        boolean changed = placeTypeHashesByDay.remove(day) != null;
        changed |= chunksByDay.remove(day) != null;
        if (changed) {
            setDirty();
        }
    }

    /**
     * Marks a biome as visited in the player's LIFETIME set; returns true only on the first
     * ever visit (the caller then bumps the per-day {@code biomes} counter + fires the signal).
     */
    public boolean markBiomeVisited(UUID player, String biomeId) {
        boolean added = biomesLifetime.computeIfAbsent(player, key -> new HashSet<>()).add(biomeId);
        if (added) {
            setDirty();
        }
        return added;
    }

    /** Drops all day maps with {@code day < minDayKept}; returns how many days were pruned. */
    public int pruneDaysBefore(int minDayKept) {
        int before = days.size();
        days.keySet().removeIf(day -> day < minDayKept);
        placeTypeHashesByDay.keySet().removeIf(day -> day < minDayKept);
        chunksByDay.keySet().removeIf(day -> day < minDayKept);
        int pruned = before - days.size();
        if (pruned > 0) {
            setDirty();
        }
        return pruned;
    }

    // --- read paths (AnalyticsApi delegates here) ---

    /** Counter value, 0 when the day/player/key is unknown. */
    public long value(int day, UUID player, String key) {
        Map<UUID, Object2LongOpenHashMap<String>> players = days.get(day);
        if (players == null) {
            return 0L;
        }
        Object2LongOpenHashMap<String> counters = players.get(player);
        return counters == null ? 0L : counters.getLong(key);
    }

    /**
     * Every player with any data on {@code day}, sorted by {@code key} value descending
     * (missing key = 0, still listed); ties break by UUID for determinism. {@code n <= 0}
     * returns the full list.
     */
    public List<AnalyticsApi.Entry> top(int day, String key, int n) {
        Map<UUID, Object2LongOpenHashMap<String>> players = days.get(day);
        if (players == null || players.isEmpty()) {
            return List.of();
        }
        List<AnalyticsApi.Entry> entries = new ArrayList<>(players.size());
        for (Map.Entry<UUID, Object2LongOpenHashMap<String>> entry : players.entrySet()) {
            entries.add(new AnalyticsApi.Entry(entry.getKey(), entry.getValue().getLong(key)));
        }
        entries.sort((a, b) -> {
            int byValue = Long.compare(b.value(), a.value());
            return byValue != 0 ? byValue : a.uuid().compareTo(b.uuid());
        });
        if (n > 0 && entries.size() > n) {
            return List.copyOf(entries.subList(0, n));
        }
        return Collections.unmodifiableList(entries);
    }

    /** Sum of {@code key} for one player across every retained day. */
    public long sumAcrossDays(UUID player, String key) {
        long sum = 0L;
        for (Map<UUID, Object2LongOpenHashMap<String>> players : days.values()) {
            Object2LongOpenHashMap<String> counters = players.get(player);
            if (counters != null) {
                sum += counters.getLong(key);
            }
        }
        return sum;
    }

    /** Union of all counter keys present on {@code day} (bounded by the key-cap discipline). */
    public Set<String> keys(int day) {
        Map<UUID, Object2LongOpenHashMap<String>> players = days.get(day);
        if (players == null) {
            return Set.of();
        }
        Set<String> keys = new HashSet<>();
        for (Object2LongOpenHashMap<String> counters : players.values()) {
            keys.addAll(counters.keySet());
        }
        return keys;
    }

    /** UUIDs with any analytics data on {@code day}. */
    public Set<UUID> knownUuids(int day) {
        Map<UUID, Object2LongOpenHashMap<String>> players = days.get(day);
        return players == null ? Set.of() : Set.copyOf(players.keySet());
    }

    /** Days currently retained (for the dump command). */
    public Set<Integer> knownDays() {
        return Set.copyOf(days.keySet());
    }

    private Object2LongOpenHashMap<String> countersFor(int day, UUID player) {
        return days.computeIfAbsent(day, key -> new HashMap<>())
                .computeIfAbsent(player, key -> new Object2LongOpenHashMap<>());
    }
}
