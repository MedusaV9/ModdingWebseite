package dev.projecteclipse.eclipse.collections;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
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
        /**
         * DOPA-S-06 crash-safety journal: 1-based tiers whose CLAIM is durable but whose
         * XP/point/shard payout has not been confirmed applied yet. Written (and flushed)
         * BEFORE any grant; a row that survives a crash is replayed exactly once at the
         * player's next login ({@code CollectionsService.replayPendingGrants}).
         */
        public final Map<String, java.util.Set<Integer>> pendingGrants = new HashMap<>();
        /**
         * uipolish item lexicon: ids of {@link ItemLexicon} items this player has carried
         * at least once. Monotonic (nothing is ever un-discovered); insertion order =
         * discovery order. Maintained by {@link ItemLexiconService}.
         */
        public final java.util.Set<String> discoveredItems = new java.util.LinkedHashSet<>();

        public long count(String collectionId) {
            return counts.getOrDefault(collectionId, 0L);
        }

        public int grantedTier(String collectionId) {
            return grantedTiers.getOrDefault(collectionId, 0);
        }

        /** Journals one claimed-but-not-yet-paid tier (caller flushes + setDirty). */
        public void addPendingGrant(String collectionId, int tier) {
            pendingGrants.computeIfAbsent(collectionId, ignored -> new java.util.LinkedHashSet<>())
                    .add(tier);
        }

        /** Confirms one tier's payout applied (caller calls setDirty). */
        public void clearPendingGrant(String collectionId, int tier) {
            java.util.Set<Integer> tiers = pendingGrants.get(collectionId);
            if (tiers != null) {
                tiers.remove(tier);
                if (tiers.isEmpty()) {
                    pendingGrants.remove(collectionId);
                }
            }
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
            CompoundTag pending = playerTag.getCompound("pendingGrants");
            for (String key : pending.getAllKeys()) {
                for (int tier : pending.getIntArray(key)) {
                    if (tier > 0) {
                        entry.addPendingGrant(key, tier);
                    }
                }
            }
            for (Tag discovered : playerTag.getList("discoveredItems", Tag.TAG_STRING)) {
                entry.discoveredItems.add(discovered.getAsString());
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
            if (!entry.pendingGrants.isEmpty()) {
                CompoundTag pending = new CompoundTag();
                for (Map.Entry<String, java.util.Set<Integer>> grant : entry.pendingGrants.entrySet()) {
                    pending.putIntArray(grant.getKey(),
                            grant.getValue().stream().mapToInt(Integer::intValue).toArray());
                }
                playerTag.put("pendingGrants", pending);
            }
            if (!entry.discoveredItems.isEmpty()) {
                ListTag discovered = new ListTag();
                for (String itemId : entry.discoveredItems) {
                    discovered.add(StringTag.valueOf(itemId));
                }
                playerTag.put("discoveredItems", discovered);
            }
            list.add(playerTag);
        }
        tag.put("players", list);
        return tag;
    }
}
