package dev.projecteclipse.eclipse.progression.bestiary;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save bestiary knowledge store ({@code data/eclipse_bestiary.dat}, overworld storage —
 * {@link EclipseSavedData} house pattern, mirrors {@code analytics.AnalyticsState}): player
 * UUID → mob id (registry path, {@code eclipse:} namespace implied) → LIFETIME progress
 * count (kills, or sightings for {@link BestiaryTiers#isSightingProgress} ids) plus the
 * per-player encountered-id set (drives T0 → T1 before any kill lands). Keyed by UUID so
 * offline players keep their knowledge. Mutators mark dirty; disk writes happen on
 * autosave only. Bounded by construction: only {@code eclipse:} mob ids ever enter
 * (checked upstream in {@link BestiaryService}), so a player map tops out at the roster
 * size (~18 entries).
 */
public final class BestiaryState extends SavedData {
    public static final String DATA_NAME = "eclipse_bestiary";

    private static final String TAG_PLAYERS = "players";
    private static final String TAG_PLAYER_ID = "id";
    private static final String TAG_COUNTS = "k";
    private static final String TAG_ENCOUNTERED = "e";

    /** One player's lifetime knowledge (counts + encountered ids). */
    private static final class Progress {
        final Object2IntOpenHashMap<String> counts = new Object2IntOpenHashMap<>();
        final Set<String> encountered = new HashSet<>();
    }

    private final Map<UUID, Progress> players = new HashMap<>();

    public BestiaryState() {}

    public static BestiaryState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(BestiaryState::new, BestiaryState::load));
    }

    public static BestiaryState load(CompoundTag tag, HolderLookup.Provider registries) {
        BestiaryState state = new BestiaryState();
        for (Tag entry : tag.getList(TAG_PLAYERS, Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) entry;
            if (!playerTag.hasUUID(TAG_PLAYER_ID)) {
                continue;
            }
            Progress progress = new Progress();
            CompoundTag counts = playerTag.getCompound(TAG_COUNTS);
            for (String id : counts.getAllKeys()) {
                progress.counts.put(id, counts.getInt(id));
            }
            for (Tag id : playerTag.getList(TAG_ENCOUNTERED, Tag.TAG_STRING)) {
                progress.encountered.add(id.getAsString());
            }
            state.players.put(playerTag.getUUID(TAG_PLAYER_ID), progress);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag playerList = new ListTag();
        for (Map.Entry<UUID, Progress> entry : players.entrySet()) {
            CompoundTag playerTag = new CompoundTag();
            playerTag.putUUID(TAG_PLAYER_ID, entry.getKey());
            CompoundTag counts = new CompoundTag();
            entry.getValue().counts.object2IntEntrySet()
                    .forEach(count -> counts.putInt(count.getKey(), count.getIntValue()));
            playerTag.put(TAG_COUNTS, counts);
            ListTag encountered = new ListTag();
            entry.getValue().encountered.stream().sorted()
                    .forEach(id -> encountered.add(StringTag.valueOf(id)));
            playerTag.put(TAG_ENCOUNTERED, encountered);
            playerList.add(playerTag);
        }
        tag.put(TAG_PLAYERS, playerList);
        return tag;
    }

    // --- reads ---

    /** Lifetime progress count (kills/sightings) for one mob id; 0 when unknown. */
    public int count(UUID player, String id) {
        Progress progress = players.get(player);
        return progress == null ? 0 : progress.counts.getInt(id);
    }

    /** Whether the player has ever encountered this mob (proximity or kill). */
    public boolean isEncountered(UUID player, String id) {
        Progress progress = players.get(player);
        return progress != null && progress.encountered.contains(id);
    }

    /** Current knowledge tier for one mob id. */
    public byte tier(UUID player, String id) {
        return BestiaryTiers.tierFor(id, count(player, id), isEncountered(player, id));
    }

    /**
     * Every mob id this player has any knowledge of (encountered or counted), sorted for
     * deterministic payloads.
     */
    public Set<String> knownIds(UUID player) {
        Progress progress = players.get(player);
        if (progress == null) {
            return Set.of();
        }
        Set<String> ids = new TreeSet<>(progress.counts.keySet());
        ids.addAll(progress.encountered);
        return ids;
    }

    // --- writes ---

    /**
     * Adds one progress count (kill or throttled sighting), marking the id encountered
     * as a side effect. Returns the new count.
     */
    public int addCount(UUID player, String id) {
        Progress progress = players.computeIfAbsent(player, key -> new Progress());
        int updated = progress.counts.addTo(id, 1) + 1;
        progress.encountered.add(id);
        setDirty();
        return updated;
    }

    /** Marks the id encountered; returns true only the first time (the T0 → T1 moment). */
    public boolean markEncountered(UUID player, String id) {
        Progress progress = players.computeIfAbsent(player, key -> new Progress());
        boolean added = progress.encountered.add(id);
        if (added) {
            setDirty();
        }
        return added;
    }
}
