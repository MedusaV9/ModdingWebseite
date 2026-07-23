package dev.projecteclipse.eclipse.start;

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
 * Per-save event-start assignment state ({@code eclipse_start_assign.dat}). Assignments store
 * stable anchor indexes rather than transient entity/order data, so server restarts and
 * player reconnects resolve to the same disc.
 */
public final class StartState extends SavedData {
    public static final String DATA_NAME = "eclipse_start_assign";

    private static final String TAG_ASSIGNED = "assigned";
    private static final String TAG_ENTRIES = "entries";
    private static final String TAG_UUID = "uuid";
    private static final String TAG_INDEX = "discIndex";

    private boolean assigned;
    private final Map<UUID, Integer> assignments = new HashMap<>();

    public StartState() {}

    public static StartState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(StartState::new, StartState::load));
    }

    public static StartState load(CompoundTag tag, HolderLookup.Provider registries) {
        StartState state = new StartState();
        state.assigned = tag.getBoolean(TAG_ASSIGNED);
        for (Tag element : tag.getList(TAG_ENTRIES, Tag.TAG_COMPOUND)) {
            CompoundTag entry = (CompoundTag) element;
            if (entry.hasUUID(TAG_UUID)) {
                int index = entry.getInt(TAG_INDEX);
                if (index >= 0) {
                    state.assignments.put(entry.getUUID(TAG_UUID), index);
                }
            }
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_ASSIGNED, assigned);
        ListTag entries = new ListTag();
        assignments.entrySet().stream()
                .sorted(Map.Entry.comparingByKey(StartAssignmentService.UUID_ORDER))
                .forEach(mapEntry -> {
                    CompoundTag entry = new CompoundTag();
                    entry.putUUID(TAG_UUID, mapEntry.getKey());
                    entry.putInt(TAG_INDEX, mapEntry.getValue());
                    entries.add(entry);
                });
        tag.put(TAG_ENTRIES, entries);
        return tag;
    }

    public boolean isAssigned() {
        return assigned;
    }

    public Integer getIndex(UUID uuid) {
        return assignments.get(uuid);
    }

    public Map<UUID, Integer> assignments() {
        return Collections.unmodifiableMap(assignments);
    }

    /** Replaces the event-start cohort atomically. */
    public void setAssignments(Map<UUID, Integer> next) {
        assignments.clear();
        next.forEach((uuid, index) -> {
            if (uuid != null && index != null && index >= 0) {
                assignments.put(uuid, index);
            }
        });
        assigned = true;
        setDirty();
    }

    /** Adds one late joiner without disturbing already-persisted players. */
    public void putAssignment(UUID uuid, int index) {
        assignments.put(uuid, Math.max(0, index));
        assigned = true;
        setDirty();
    }
}
