package dev.projecteclipse.eclipse.xboxevent;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save state machine of the Xbox tutorial event (plan §2.13.3), SavedData
 * {@code eclipse_xbox_event} in overworld storage. {@code IDLE → ANNOUNCED → OPEN →
 * CLOSING → IDLE}; lockouts are scoped by {@link #instanceId()} which increments per
 * event start, so they expire automatically with the instance.
 */
public final class XboxEventState extends SavedData {
    public static final String DATA_NAME = "eclipse_xbox_event";

    /** Event lifecycle phase; {@code CLOSING} survives a crash and resumes on boot. */
    public enum Phase {
        IDLE, ANNOUNCED, OPEN, CLOSING;

        static Phase byName(String name) {
            for (Phase phase : values()) {
                if (phase.name().equalsIgnoreCase(name)) {
                    return phase;
                }
            }
            return IDLE;
        }
    }

    /** Exit reasons that lock re-entry for the current event instance. */
    public enum LockoutMode {
        VOLUNTARY(true, false),
        DEATH(false, true),
        BOTH(true, true);

        private final boolean lockVoluntaryExit;
        private final boolean lockDeath;

        LockoutMode(boolean lockVoluntaryExit, boolean lockDeath) {
            this.lockVoluntaryExit = lockVoluntaryExit;
            this.lockDeath = lockDeath;
        }

        public boolean locksVoluntaryExit() {
            return lockVoluntaryExit;
        }

        public boolean locksDeath() {
            return lockDeath;
        }

        static LockoutMode byName(String name, LockoutMode fallback) {
            for (LockoutMode mode : values()) {
                if (mode.name().equalsIgnoreCase(name)) {
                    return mode;
                }
            }
            return fallback;
        }
    }

    /** Where a participant entered from — restored verbatim on any exit path. */
    public record ReturnAnchor(ResourceKey<Level> dimension, double x, double y, double z,
            float yaw, float pitch) {}

    private record ConsumedChest(String worldId, long packedPos) {}

    private static final String TAG_PHASE = "phase";
    private static final String TAG_WORLD_ID = "worldId";
    private static final String TAG_ENDS_AT = "endsAtEpochMillis";
    private static final String TAG_INSTANCE_ID = "instanceId";
    private static final String TAG_PORTAL = "portal";
    private static final String TAG_PARTICIPANTS = "participants";
    private static final String TAG_LOCKED_OUT = "lockedOut";
    private static final String TAG_LOCKOUT_MODE = "lockoutMode";
    private static final String TAG_CONSUMED_CHESTS = "consumedChests";
    private static final String TAG_ANCHORS = "returnAnchors";
    private static final String TAG_REWARD_BUFF = "rewardBuffId";
    private static final String TAG_REWARD_MINUTES = "rewardMinutes";
    private static final String TAG_REWARD_GRANTED = "rewardGranted";

    private Phase phase = Phase.IDLE;
    private String worldId = "";
    private long endsAtEpochMillis;
    private int instanceId;
    @Nullable
    private ResourceKey<Level> portalDimension;
    @Nullable
    private BlockPos portalPos;
    private final Set<UUID> participants = new HashSet<>();
    private final Map<UUID, Integer> lockedOut = new HashMap<>();
    private LockoutMode lockoutMode = LockoutMode.VOLUNTARY;
    private final Set<ConsumedChest> consumedChests = new HashSet<>();
    private final Map<UUID, ReturnAnchor> returnAnchors = new HashMap<>();
    /** Empty string / {@code 0} = fall back to {@code xboxevent.json} values. */
    private String rewardBuffId = "";
    private int rewardMinutes;
    private boolean rewardGranted;

    public XboxEventState() {}

    public static XboxEventState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(XboxEventState::new, XboxEventState::load),
                DATA_NAME);
    }

    // ------------------------------------------------------------------ phase & core fields

    public Phase phase() {
        return phase;
    }

    public void setPhase(Phase newPhase) {
        this.phase = newPhase;
        setDirty();
    }

    /** Active (or last) world id, e.g. {@code tu12}; empty when never started. */
    public String worldId() {
        return worldId;
    }

    public long endsAtEpochMillis() {
        return endsAtEpochMillis;
    }

    /** Clamped to {@code >= nowMillis} by callers per plan §2.13.3. */
    public void setEndsAtEpochMillis(long endsAt) {
        this.endsAtEpochMillis = endsAt;
        setDirty();
    }

    public int instanceId() {
        return instanceId;
    }

    /**
     * Starts a fresh event instance: bumps {@link #instanceId()}, clears participants and
     * stale anchors/consumed chest positions, prunes lockouts from earlier instances,
     * resets the reward override, and records world + end time.
     */
    public void beginInstance(String newWorldId, long endsAt) {
        this.instanceId++;
        this.worldId = newWorldId;
        this.endsAtEpochMillis = endsAt;
        this.participants.clear();
        this.returnAnchors.clear();
        this.consumedChests.clear();
        this.rewardBuffId = "";
        this.rewardMinutes = 0;
        this.rewardGranted = false;
        this.lockoutMode = configuredDefaultLockoutMode();
        int current = this.instanceId;
        this.lockedOut.values().removeIf(instance -> instance != current);
        this.phase = Phase.ANNOUNCED;
        setDirty();
    }

    // ------------------------------------------------------------------ portal

    @Nullable
    public ResourceKey<Level> portalDimension() {
        return portalDimension;
    }

    @Nullable
    public BlockPos portalPos() {
        return portalPos;
    }

    public void setPortal(@Nullable ResourceKey<Level> dimension, @Nullable BlockPos pos) {
        this.portalDimension = dimension;
        this.portalPos = pos == null ? null : pos.immutable();
        setDirty();
    }

    // ------------------------------------------------------------------ participants

    public boolean addParticipant(UUID uuid) {
        boolean added = participants.add(uuid);
        if (added) {
            setDirty();
        }
        return added;
    }

    public boolean isParticipant(UUID uuid) {
        return participants.contains(uuid);
    }

    public Set<UUID> participantsSnapshot() {
        return Collections.unmodifiableSet(new HashSet<>(participants));
    }

    // ------------------------------------------------------------------ lockouts

    /** Locks {@code uuid} out of the current instance after a configured exit reason. */
    public void lockOut(UUID uuid) {
        lockedOut.put(uuid, instanceId);
        setDirty();
    }

    /** Whether {@code uuid} is locked out of the current instance. */
    public boolean isLockedOut(UUID uuid) {
        Integer lockedInstance = lockedOut.get(uuid);
        return lockedInstance != null && lockedInstance == instanceId;
    }

    public boolean clearLockout(UUID uuid) {
        boolean removed = lockedOut.remove(uuid) != null;
        if (removed) {
            setDirty();
        }
        return removed;
    }

    public int clearAllLockouts() {
        int count = lockedOut.size();
        if (count > 0) {
            lockedOut.clear();
            setDirty();
        }
        return count;
    }

    public Map<UUID, Integer> lockoutsSnapshot() {
        return Collections.unmodifiableMap(new HashMap<>(lockedOut));
    }

    /** Exit reasons that create a lockout for this event instance. */
    public LockoutMode lockoutMode() {
        return lockoutMode;
    }

    /** Runtime override used by {@code /dev xboxevent lockout mode}. */
    public void setLockoutMode(LockoutMode mode) {
        this.lockoutMode = mode == null ? configuredDefaultLockoutMode() : mode;
        setDirty();
    }

    // ------------------------------------------------------------------ one-shot chest loot

    /**
     * Atomically marks a baked manifest chest as consumed for this instance.
     *
     * @return {@code true} only for the first lookup of this world/position pair
     */
    public boolean consumeChestPosition(String manifestWorldId, BlockPos pos) {
        if (phase != Phase.OPEN || !worldId.equals(manifestWorldId)) {
            return false;
        }
        boolean added = consumedChests.add(new ConsumedChest(manifestWorldId, pos.asLong()));
        if (added) {
            setDirty();
        }
        return added;
    }

    /** Test/status hook for restart-safe one-shot loot accounting. */
    public boolean isChestPositionConsumed(String manifestWorldId, BlockPos pos) {
        return consumedChests.contains(new ConsumedChest(manifestWorldId, pos.asLong()));
    }

    // ------------------------------------------------------------------ return anchors

    public void putReturnAnchor(UUID uuid, ReturnAnchor anchor) {
        returnAnchors.put(uuid, anchor);
        setDirty();
    }

    @Nullable
    public ReturnAnchor returnAnchor(UUID uuid) {
        return returnAnchors.get(uuid);
    }

    public void removeReturnAnchor(UUID uuid) {
        if (returnAnchors.remove(uuid) != null) {
            setDirty();
        }
    }

    public Map<UUID, ReturnAnchor> returnAnchorsSnapshot() {
        return Collections.unmodifiableMap(new HashMap<>(returnAnchors));
    }

    // ------------------------------------------------------------------ reward override

    /** Persisted within the current instance; empty = config default. */
    public String rewardBuffIdOverride() {
        return rewardBuffId;
    }

    /** Persisted override; {@code 0} = config default. */
    public int rewardMinutesOverride() {
        return rewardMinutes;
    }

    public void setRewardOverride(String buffId, int minutes) {
        this.rewardBuffId = buffId == null ? "" : buffId;
        this.rewardMinutes = Math.max(0, minutes);
        setDirty();
    }

    /**
     * Persists the close-sequence reward step before the global buff is started.
     *
     * @return true only for the first attempt in this event instance
     */
    public boolean markRewardGranted() {
        if (rewardGranted) {
            return false;
        }
        rewardGranted = true;
        setDirty();
        return true;
    }

    public boolean rewardGranted() {
        return rewardGranted;
    }

    // ------------------------------------------------------------------ NBT

    public static XboxEventState load(CompoundTag tag, HolderLookup.Provider registries) {
        XboxEventState state = new XboxEventState();
        state.phase = Phase.byName(tag.getString(TAG_PHASE));
        state.worldId = tag.getString(TAG_WORLD_ID);
        state.endsAtEpochMillis = tag.getLong(TAG_ENDS_AT);
        state.instanceId = tag.getInt(TAG_INSTANCE_ID);
        LockoutMode configuredMode = configuredDefaultLockoutMode();
        state.lockoutMode = tag.contains(TAG_LOCKOUT_MODE, Tag.TAG_STRING)
                ? LockoutMode.byName(tag.getString(TAG_LOCKOUT_MODE), configuredMode)
                : configuredMode;

        if (tag.contains(TAG_PORTAL, Tag.TAG_COMPOUND)) {
            CompoundTag portal = tag.getCompound(TAG_PORTAL);
            ResourceLocation dim = ResourceLocation.tryParse(portal.getString("dim"));
            if (dim != null) {
                state.portalDimension = ResourceKey.create(Registries.DIMENSION, dim);
                state.portalPos = new BlockPos(portal.getInt("x"), portal.getInt("y"), portal.getInt("z"));
            }
        }

        for (Tag participant : tag.getList(TAG_PARTICIPANTS, Tag.TAG_INT_ARRAY)) {
            state.participants.add(NbtUtils.loadUUID(participant));
        }

        for (Tag lockTag : tag.getList(TAG_LOCKED_OUT, Tag.TAG_COMPOUND)) {
            CompoundTag lock = (CompoundTag) lockTag;
            state.lockedOut.put(lock.getUUID("uuid"), lock.getInt("instance"));
        }

        for (Tag chestTag : tag.getList(TAG_CONSUMED_CHESTS, Tag.TAG_COMPOUND)) {
            CompoundTag chest = (CompoundTag) chestTag;
            String manifestWorldId = chest.getString("world");
            if (!manifestWorldId.isBlank()) {
                state.consumedChests.add(new ConsumedChest(manifestWorldId, chest.getLong("pos")));
            }
        }

        for (Tag anchorTag : tag.getList(TAG_ANCHORS, Tag.TAG_COMPOUND)) {
            CompoundTag anchor = (CompoundTag) anchorTag;
            ResourceLocation dim = ResourceLocation.tryParse(anchor.getString("dim"));
            if (dim == null) {
                continue;
            }
            state.returnAnchors.put(anchor.getUUID("uuid"), new ReturnAnchor(
                    ResourceKey.create(Registries.DIMENSION, dim),
                    anchor.getDouble("x"), anchor.getDouble("y"), anchor.getDouble("z"),
                    anchor.getFloat("yaw"), anchor.getFloat("pitch")));
        }

        state.rewardBuffId = tag.getString(TAG_REWARD_BUFF);
        state.rewardMinutes = tag.getInt(TAG_REWARD_MINUTES);
        state.rewardGranted = tag.getBoolean(TAG_REWARD_GRANTED);
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putString(TAG_PHASE, phase.name().toLowerCase(Locale.ROOT));
        tag.putString(TAG_WORLD_ID, worldId);
        tag.putLong(TAG_ENDS_AT, endsAtEpochMillis);
        tag.putInt(TAG_INSTANCE_ID, instanceId);

        if (portalDimension != null && portalPos != null) {
            CompoundTag portal = new CompoundTag();
            portal.putString("dim", portalDimension.location().toString());
            portal.putInt("x", portalPos.getX());
            portal.putInt("y", portalPos.getY());
            portal.putInt("z", portalPos.getZ());
            tag.put(TAG_PORTAL, portal);
        }

        ListTag participantsTag = new ListTag();
        for (UUID uuid : participants) {
            participantsTag.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_PARTICIPANTS, participantsTag);

        ListTag lockedOutTag = new ListTag();
        for (Map.Entry<UUID, Integer> entry : lockedOut.entrySet()) {
            CompoundTag lock = new CompoundTag();
            lock.putUUID("uuid", entry.getKey());
            lock.putInt("instance", entry.getValue());
            lockedOutTag.add(lock);
        }
        tag.put(TAG_LOCKED_OUT, lockedOutTag);
        tag.putString(TAG_LOCKOUT_MODE, lockoutMode.name().toLowerCase(Locale.ROOT));

        ListTag consumedChestsTag = new ListTag();
        for (ConsumedChest chest : consumedChests) {
            CompoundTag chestTag = new CompoundTag();
            chestTag.putString("world", chest.worldId());
            chestTag.putLong("pos", chest.packedPos());
            consumedChestsTag.add(chestTag);
        }
        tag.put(TAG_CONSUMED_CHESTS, consumedChestsTag);

        ListTag anchorsTag = new ListTag();
        for (Map.Entry<UUID, ReturnAnchor> entry : returnAnchors.entrySet()) {
            ReturnAnchor anchor = entry.getValue();
            CompoundTag anchorTag = new CompoundTag();
            anchorTag.putUUID("uuid", entry.getKey());
            anchorTag.putString("dim", anchor.dimension().location().toString());
            anchorTag.putDouble("x", anchor.x());
            anchorTag.putDouble("y", anchor.y());
            anchorTag.putDouble("z", anchor.z());
            anchorTag.putFloat("yaw", anchor.yaw());
            anchorTag.putFloat("pitch", anchor.pitch());
            anchorsTag.add(anchorTag);
        }
        tag.put(TAG_ANCHORS, anchorsTag);

        tag.putString(TAG_REWARD_BUFF, rewardBuffId);
        tag.putInt(TAG_REWARD_MINUTES, rewardMinutes);
        tag.putBoolean(TAG_REWARD_GRANTED, rewardGranted);
        return tag;
    }

    private static LockoutMode configuredDefaultLockoutMode() {
        return XboxEventConfig.get().lockoutOnDeath() ? LockoutMode.BOTH : LockoutMode.VOLUNTARY;
    }

    /** Helper for gametests: list of member names for status dumps, sorted for determinism. */
    public List<String> debugParticipantNames(MinecraftServer server) {
        List<String> names = new ArrayList<>();
        for (UUID uuid : participants) {
            var player = server.getPlayerList().getPlayer(uuid);
            names.add(player != null ? player.getGameProfile().getName() : uuid.toString());
        }
        Collections.sort(names);
        return names;
    }
}
