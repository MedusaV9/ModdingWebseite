package dev.projecteclipse.eclipse.core.state;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Global persistent state of the Eclipse event, stored in the overworld's data storage
 * as {@code data/eclipse_world_state.dat}. Obtain via {@link #get(MinecraftServer)}.
 * All mutators mark the data dirty so it is written back to disk.
 */
public final class EclipseWorldState extends SavedData {
    public static final String DATA_NAME = "eclipse_world_state";

    private static final String TAG_DAY = "day";
    private static final String TAG_ALTAR_LEVEL = "altarLevel";
    private static final String TAG_BORDER_SIZE = "borderSize";
    private static final String TAG_START_EVENT_DONE = "startEventDone";
    private static final String TAG_GHOST_SHIP_BUILT = "ghostShipBuilt";
    private static final String TAG_BANNED = "banned";
    private static final String TAG_MILESTONE_PROGRESS = "milestoneProgress";
    private static final String TAG_FORCE_VOICE_MUTED = "forceVoiceMuted";
    private static final String TAG_OAR_ENTITIES = "oarEntities";

    private int day = 1;
    private int altarLevel = 0;
    private double borderSize = 1000.0D;
    private boolean startEventDone = false;
    private boolean ghostShipBuilt = false;
    private final Set<UUID> banned = new HashSet<>();
    private final Map<String, Long> milestoneProgress = new HashMap<>();
    private final Set<UUID> forceVoiceMuted = new HashSet<>();
    private final List<UUID> oarEntities = new ArrayList<>();

    public EclipseWorldState() {}

    public static EclipseWorldState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(EclipseWorldState::new, EclipseWorldState::load),
                DATA_NAME);
    }

    public static EclipseWorldState load(CompoundTag tag, HolderLookup.Provider registries) {
        EclipseWorldState state = new EclipseWorldState();
        state.day = tag.contains(TAG_DAY) ? tag.getInt(TAG_DAY) : 1;
        state.altarLevel = tag.getInt(TAG_ALTAR_LEVEL);
        state.borderSize = tag.contains(TAG_BORDER_SIZE) ? tag.getDouble(TAG_BORDER_SIZE) : 1000.0D;
        state.startEventDone = tag.getBoolean(TAG_START_EVENT_DONE);
        state.ghostShipBuilt = tag.getBoolean(TAG_GHOST_SHIP_BUILT);
        for (Tag entry : tag.getList(TAG_OAR_ENTITIES, Tag.TAG_INT_ARRAY)) {
            state.oarEntities.add(NbtUtils.loadUUID(entry));
        }
        for (Tag entry : tag.getList(TAG_BANNED, Tag.TAG_INT_ARRAY)) {
            state.banned.add(NbtUtils.loadUUID(entry));
        }
        CompoundTag progress = tag.getCompound(TAG_MILESTONE_PROGRESS);
        for (String key : progress.getAllKeys()) {
            state.milestoneProgress.put(key, progress.getLong(key));
        }
        for (Tag entry : tag.getList(TAG_FORCE_VOICE_MUTED, Tag.TAG_INT_ARRAY)) {
            state.forceVoiceMuted.add(NbtUtils.loadUUID(entry));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_DAY, this.day);
        tag.putInt(TAG_ALTAR_LEVEL, this.altarLevel);
        tag.putDouble(TAG_BORDER_SIZE, this.borderSize);
        tag.putBoolean(TAG_START_EVENT_DONE, this.startEventDone);
        tag.putBoolean(TAG_GHOST_SHIP_BUILT, this.ghostShipBuilt);

        ListTag oarList = new ListTag();
        for (UUID uuid : this.oarEntities) {
            oarList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_OAR_ENTITIES, oarList);

        ListTag bannedList = new ListTag();
        for (UUID uuid : this.banned) {
            bannedList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_BANNED, bannedList);

        CompoundTag progress = new CompoundTag();
        for (Map.Entry<String, Long> entry : this.milestoneProgress.entrySet()) {
            progress.putLong(entry.getKey(), entry.getValue());
        }
        tag.put(TAG_MILESTONE_PROGRESS, progress);

        ListTag mutedList = new ListTag();
        for (UUID uuid : this.forceVoiceMuted) {
            mutedList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_FORCE_VOICE_MUTED, mutedList);
        return tag;
    }

    // --- day ---

    public int getDay() {
        return this.day;
    }

    public void setDay(int day) {
        this.day = day;
        setDirty();
    }

    // --- altar level ---

    public int getAltarLevel() {
        return this.altarLevel;
    }

    public void setAltarLevel(int altarLevel) {
        this.altarLevel = altarLevel;
        setDirty();
    }

    // --- border ---

    public double getBorderSize() {
        return this.borderSize;
    }

    public void setBorderSize(double borderSize) {
        this.borderSize = borderSize;
        setDirty();
    }

    // --- start event ---

    public boolean isStartEventDone() {
        return this.startEventDone;
    }

    public void setStartEventDone(boolean startEventDone) {
        this.startEventDone = startEventDone;
        setDirty();
    }

    // --- ghost ship (limbo) ---

    /** Whether the procedural ghost ship has already been built in the Limbo dimension. */
    public boolean isGhostShipBuilt() {
        return this.ghostShipBuilt;
    }

    public void setGhostShipBuilt(boolean ghostShipBuilt) {
        this.ghostShipBuilt = ghostShipBuilt;
        setDirty();
    }

    /** UUIDs of the persistent block-display oar entities on the ghost ship (ordered: port bow → stern, then starboard). */
    public List<UUID> getOarEntities() {
        return Collections.unmodifiableList(this.oarEntities);
    }

    public void setOarEntities(List<UUID> oarEntityIds) {
        this.oarEntities.clear();
        this.oarEntities.addAll(oarEntityIds);
        setDirty();
    }

    // --- banned ---

    public Set<UUID> getBanned() {
        return Collections.unmodifiableSet(this.banned);
    }

    public boolean isBanned(UUID playerId) {
        return this.banned.contains(playerId);
    }

    public void addBanned(UUID playerId) {
        if (this.banned.add(playerId)) {
            setDirty();
        }
    }

    public void removeBanned(UUID playerId) {
        if (this.banned.remove(playerId)) {
            setDirty();
        }
    }

    // --- milestone progress ---

    public Map<String, Long> getMilestoneProgress() {
        return Collections.unmodifiableMap(this.milestoneProgress);
    }

    public long getMilestoneProgress(String key) {
        return this.milestoneProgress.getOrDefault(key, 0L);
    }

    public void setMilestoneProgress(String key, long value) {
        this.milestoneProgress.put(key, value);
        setDirty();
    }

    /** Adds {@code delta} to the progress stored under {@code key} and returns the new value. */
    public long addMilestoneProgress(String key, long delta) {
        long updated = getMilestoneProgress(key) + delta;
        this.milestoneProgress.put(key, updated);
        setDirty();
        return updated;
    }

    // --- force voice muted (used by the voice worker) ---

    public Set<UUID> getForceVoiceMuted() {
        return Collections.unmodifiableSet(this.forceVoiceMuted);
    }

    public boolean isForceVoiceMuted(UUID playerId) {
        return this.forceVoiceMuted.contains(playerId);
    }

    public void addForceVoiceMuted(UUID playerId) {
        if (this.forceVoiceMuted.add(playerId)) {
            setDirty();
        }
    }

    public void removeForceVoiceMuted(UUID playerId) {
        if (this.forceVoiceMuted.remove(playerId)) {
            setDirty();
        }
    }
}
