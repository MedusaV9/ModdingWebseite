package dev.projecteclipse.eclipse.rebirth;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.LongTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save rebirth persistence (D11; SavedData {@code eclipse_rebirth} in overworld storage
 * — dies with the save by construction). Keyed by UUID so offline players stay queryable
 * (curve multipliers must survive relogs and apply to {@code SkillsApi.getLevel} lookups).
 *
 * <p>Alongside the count, every ceremony's epoch-millis timestamp is kept as an audit
 * trail for awards/drama hooks ("first rebirth of the event", "3 rebirths in one day").</p>
 */
public final class RebirthState extends SavedData {
    public static final String DATA_NAME = "eclipse_rebirth";

    /** Mutable per-player record. Call {@link RebirthState#setDirty()} after writes. */
    public static final class Entry {
        /** Completed rebirths; never decreases outside dev commands. */
        public int count = 0;
        /** Epoch millis of each ceremony, oldest first (audit trail; size tracks {@code count}). */
        public final List<Long> timestamps = new ArrayList<>();
    }

    private final Map<UUID, Entry> players = new HashMap<>();

    public RebirthState() {}

    public static RebirthState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(RebirthState::new, RebirthState::load));
    }

    /** Existing entry or a fresh default one (not persisted until something marks dirty). */
    public Entry entry(UUID uuid) {
        return players.computeIfAbsent(uuid, ignored -> new Entry());
    }

    /** Completed rebirths for {@code uuid} without materializing an entry. */
    public int count(UUID uuid) {
        Entry entry = players.get(uuid);
        return entry != null ? entry.count : 0;
    }

    /** Records one completed ceremony: increments the count, appends the timestamp, dirties. */
    public int recordRebirth(UUID uuid, long epochMillis) {
        Entry entry = entry(uuid);
        entry.count++;
        entry.timestamps.add(epochMillis);
        setDirty();
        return entry.count;
    }

    /** Read-only view for iteration (dev status command / debug). */
    public Map<UUID, Entry> entries() {
        return Collections.unmodifiableMap(players);
    }

    public static RebirthState load(CompoundTag tag, HolderLookup.Provider registries) {
        RebirthState state = new RebirthState();
        for (Tag element : tag.getList("players", Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) element;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            Entry entry = new Entry();
            entry.count = Math.max(0, playerTag.getInt("count"));
            for (Tag stamp : playerTag.getList("times", Tag.TAG_LONG)) {
                if (stamp instanceof LongTag longTag) {
                    entry.timestamps.add(longTag.getAsLong());
                }
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
            playerTag.putInt("count", entry.count);
            ListTag times = new ListTag();
            for (Long stamp : entry.timestamps) {
                times.add(LongTag.valueOf(stamp));
            }
            playerTag.put("times", times);
            list.add(playerTag);
        }
        tag.put("players", list);
        return tag;
    }
}
