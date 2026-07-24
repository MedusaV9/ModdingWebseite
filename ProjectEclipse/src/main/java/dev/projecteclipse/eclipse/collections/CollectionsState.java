package dev.projecteclipse.eclipse.collections;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * D1 collections persistence (SavedData {@code eclipse_collections} in overworld storage,
 * {@code SkillState} pattern — dies with the save, offline players stay queryable).
 * Deliberately NOT derived from {@code AnalyticsApi.sumAcrossDays}: analytics has a
 * 20-day retention window and drops per-id detail past the daily dynamic-key cap
 * (IDEAS-collections §2.6) — this is the collection store of record.
 *
 * <p>Per player: lifetime {@code collectionId → count} plus the highest GRANTED tier per
 * collection ({@code grantedTiers} is monotonic — raised config thresholds never revoke
 * XP/points, mirroring {@code SkillsApi.setTotalXp}'s "newly reached only" contract), and
 * the optional {@code dailyCreditCap} bookkeeping ({@code capDay}/{@code capUsed},
 * self-invalidating on day change like {@code SkillState.Entry}).</p>
 */
public final class CollectionsState extends SavedData {
    public static final String DATA_NAME = "eclipse_collections";

    /** Mutable per-player record. Call {@link CollectionsState#setDirty()} after writes. */
    public static final class Entry {
        /** Lifetime credit per collection id; counts only ever go up. */
        public final Map<String, Long> counts = new HashMap<>();
        /** Highest 1-based tier already granted per collection id. Never decreases. */
        public final Map<String, Integer> grantedTiers = new HashMap<>();
        /** Event day the daily-credit-cap counters belong to (self-invalidating). */
        public int capDay = 0;
        /** Credits already granted per collection id for {@code capDay}. */
        public final Map<String, Long> capUsed = new HashMap<>();

        public long count(String collectionId) {
            return counts.getOrDefault(collectionId, 0L);
        }

        public int grantedTier(String collectionId) {
            return grantedTiers.getOrDefault(collectionId, 0);
        }
    }

    private final Map<UUID, Entry> players = new HashMap<>();

    public CollectionsState() {}

    public static CollectionsState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(CollectionsState::new, CollectionsState::load));
    }

    /** Existing entry or a fresh default one (not persisted until something marks dirty). */
    public Entry entry(UUID uuid) {
        return players.computeIfAbsent(uuid, ignored -> new Entry());
    }

    /** Read-only view for iteration (dev commands / debug). */
    public Map<UUID, Entry> entries() {
        return Collections.unmodifiableMap(players);
    }

    public static CollectionsState load(CompoundTag tag, HolderLookup.Provider registries) {
        CollectionsState state = new CollectionsState();
        for (Tag element : tag.getList("players", Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) element;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            Entry entry = new Entry();
            CompoundTag counts = playerTag.getCompound("counts");
            for (String key : counts.getAllKeys()) {
                entry.counts.put(key, Math.max(0L, counts.getLong(key)));
            }
            CompoundTag tiers = playerTag.getCompound("tiers");
            for (String key : tiers.getAllKeys()) {
                entry.grantedTiers.put(key, Math.max(0, tiers.getInt(key)));
            }
            entry.capDay = playerTag.getInt("capDay");
            CompoundTag capUsed = playerTag.getCompound("capUsed");
            for (String key : capUsed.getAllKeys()) {
                entry.capUsed.put(key, Math.max(0L, capUsed.getLong(key)));
            }
            state.players.put(playerTag.getUUID("uuid"), entry);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (Map.Entry<UUID, Entry> mapEntry : players.entrySet()) {
            Entry entry = mapEntry.getValue();
            CompoundTag playerTag = new CompoundTag();
            playerTag.putUUID("uuid", mapEntry.getKey());
            CompoundTag counts = new CompoundTag();
            for (Map.Entry<String, Long> count : entry.counts.entrySet()) {
                counts.putLong(count.getKey(), count.getValue());
            }
            playerTag.put("counts", counts);
            CompoundTag tiers = new CompoundTag();
            for (Map.Entry<String, Integer> tier : entry.grantedTiers.entrySet()) {
                tiers.putInt(tier.getKey(), tier.getValue());
            }
            playerTag.put("tiers", tiers);
            playerTag.putInt("capDay", entry.capDay);
            CompoundTag capUsed = new CompoundTag();
            for (Map.Entry<String, Long> cap : entry.capUsed.entrySet()) {
                capUsed.putLong(cap.getKey(), cap.getValue());
            }
            playerTag.put("capUsed", capUsed);
            list.add(playerTag);
        }
        tag.put("players", list);
        return tag;
    }
}
