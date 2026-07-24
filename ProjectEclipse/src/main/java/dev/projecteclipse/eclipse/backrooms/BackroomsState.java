package dev.projecteclipse.eclipse.backrooms;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
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
 * Per-save state machine of the Backrooms event (plans_v5 PLAN-C C18, the
 * {@code XboxEventState} skeleton): SavedData {@code eclipse_backrooms_event} in overworld
 * storage, {@code IDLE → ANNOUNCED → OPEN → CLOSING → IDLE}. Extra fields beyond the xbox
 * template:
 *
 * <ul>
 *   <li>{@link #stampCursor()} — budgeted-maze-stamp progress during ANNOUNCED (IDEAS
 *       §A1: OPEN flips only once the stamp finishes); persists so a crash mid-stamp
 *       resumes where it stopped — the maze itself is a pure function of
 *       {@link BackroomsMaze#mazeSeed}, so re-stamped cells are byte-identical.</li>
 *   <li>{@link #markScared(UUID)} — the once-per-instance jumpscare set (IDEAS §A4,
 *       the {@code markRewardGranted()} persistence law: relogs cannot re-arm it).</li>
 *   <li>{@link #markWhispered(UUID)} — the rare once-per-instance WHISPER caption
 *       (IDEAS §A6.5).</li>
 *   <li>{@link #exitPortalPos()} — the T-5:00 EXIT portal cell (IDEAS §A5); walking out
 *       through it marks {@link #markExitUpgraded(UUID)} for the upgraded reward share.</li>
 *   <li>Entry timestamps ({@link #enteredAtEpochMillis(UUID)}) — the jumpscare's
 *       "inside &gt; 90 s" arm condition, persisted so relogs don't reset the clock.</li>
 * </ul>
 *
 * <p>Lockouts are voluntary-exit only (IDEAS §A5: deaths never lock — "the horror
 * dimension must be safe to be scary"), scoped by {@link #instanceId()} exactly like the
 * xbox lockout map.</p>
 */
public final class BackroomsState extends SavedData {
    public static final String DATA_NAME = "eclipse_backrooms_event";

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

    /** Where a participant entered from — restored verbatim on any exit path. */
    public record ReturnAnchor(ResourceKey<Level> dimension, double x, double y, double z,
            float yaw, float pitch) {}

    private Phase phase = Phase.IDLE;
    private long endsAtEpochMillis;
    private int instanceId;
    /** Budgeted stamp progress: next {@link BackroomsMaze#stampUnit} index to run. */
    private int stampCursor;
    @Nullable
    private ResourceKey<Level> portalDimension;
    @Nullable
    private BlockPos portalPos;
    /** T-5:00 EXIT portal inside the maze ({@code null} until spawned). */
    @Nullable
    private BlockPos exitPortalPos;
    private final Set<UUID> participants = new HashSet<>();
    private final Map<UUID, Integer> lockedOut = new HashMap<>();
    private final Map<UUID, ReturnAnchor> returnAnchors = new HashMap<>();
    private final Map<UUID, Long> enteredAt = new HashMap<>();
    private final Set<UUID> scared = new HashSet<>();
    private final Set<UUID> whispered = new HashSet<>();
    private final Set<UUID> exitUpgraded = new HashSet<>();
    private boolean rewardGranted;

    public BackroomsState() {}

    public static BackroomsState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(BackroomsState::new, BackroomsState::load),
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

    public long endsAtEpochMillis() {
        return endsAtEpochMillis;
    }

    /** Clamped to {@code >= nowMillis} by callers (the xbox §2.13.3 law). */
    public void setEndsAtEpochMillis(long endsAt) {
        this.endsAtEpochMillis = endsAt;
        setDirty();
    }

    public int instanceId() {
        return instanceId;
    }

    /** Per-instance maze seed (IDEAS §A1: {@code ECLIPSE_SEED ^ salt ^ instanceId}). */
    public long mazeSeed() {
        return BackroomsMaze.mazeSeed(instanceId);
    }

    /**
     * Starts a fresh event instance: bumps {@link #instanceId()} (which reseeds the maze),
     * resets the stamp cursor and all per-instance sets, prunes stale lockouts.
     */
    public void beginInstance(long endsAt) {
        this.instanceId++;
        this.endsAtEpochMillis = endsAt;
        this.stampCursor = 0;
        this.exitPortalPos = null;
        this.participants.clear();
        this.returnAnchors.clear();
        this.enteredAt.clear();
        this.scared.clear();
        this.whispered.clear();
        this.exitUpgraded.clear();
        this.rewardGranted = false;
        int current = this.instanceId;
        this.lockedOut.values().removeIf(instance -> instance != current);
        this.phase = Phase.ANNOUNCED;
        setDirty();
    }

    // ------------------------------------------------------------------ stamp cursor

    public int stampCursor() {
        return stampCursor;
    }

    public void setStampCursor(int cursor) {
        this.stampCursor = cursor;
        setDirty();
    }

    public boolean stampComplete() {
        return stampCursor >= BackroomsMaze.totalStampUnits();
    }

    // ------------------------------------------------------------------ portals

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

    @Nullable
    public BlockPos exitPortalPos() {
        return exitPortalPos;
    }

    public void setExitPortalPos(@Nullable BlockPos pos) {
        this.exitPortalPos = pos == null ? null : pos.immutable();
        setDirty();
    }

    // ------------------------------------------------------------------ participants & timers

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

    /** Entry wall-clock stamp (jumpscare arming clock); {@code 0} when never entered. */
    public long enteredAtEpochMillis(UUID uuid) {
        return enteredAt.getOrDefault(uuid, 0L);
    }

    public void recordEntry(UUID uuid, long epochMillis) {
        enteredAt.put(uuid, epochMillis);
        setDirty();
    }

    // ------------------------------------------------------------------ lockouts (voluntary only)

    public void lockOut(UUID uuid) {
        lockedOut.put(uuid, instanceId);
        setDirty();
    }

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

    public long lockedOutCountThisInstance() {
        return lockedOut.values().stream().filter(instance -> instance == instanceId).count();
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

    // ------------------------------------------------------------------ once-per-instance sets

    /** @return true only for the FIRST scare of this player this instance (IDEAS §A4). */
    public boolean markScared(UUID uuid) {
        boolean added = scared.add(uuid);
        if (added) {
            setDirty();
        }
        return added;
    }

    public boolean isScared(UUID uuid) {
        return scared.contains(uuid);
    }

    /** @return true only for the first WHISPER caption of this player this instance. */
    public boolean markWhispered(UUID uuid) {
        boolean added = whispered.add(uuid);
        if (added) {
            setDirty();
        }
        return added;
    }

    /** Marks {@code uuid} as having walked out through the EXIT portal (reward upgrade). */
    public void markExitUpgraded(UUID uuid) {
        if (exitUpgraded.add(uuid)) {
            setDirty();
        }
    }

    public boolean isExitUpgraded(UUID uuid) {
        return exitUpgraded.contains(uuid);
    }

    /** @return true only for the first close-sequence reward attempt of this instance. */
    public boolean markRewardGranted() {
        if (rewardGranted) {
            return false;
        }
        rewardGranted = true;
        setDirty();
        return true;
    }

    // ------------------------------------------------------------------ NBT

    public static BackroomsState load(CompoundTag tag, HolderLookup.Provider registries) {
        BackroomsState state = new BackroomsState();
        state.phase = Phase.byName(tag.getString("phase"));
        state.endsAtEpochMillis = tag.getLong("endsAtEpochMillis");
        state.instanceId = tag.getInt("instanceId");
        state.stampCursor = tag.getInt("stampCursor");
        state.rewardGranted = tag.getBoolean("rewardGranted");

        if (tag.contains("portal", Tag.TAG_COMPOUND)) {
            CompoundTag portal = tag.getCompound("portal");
            ResourceLocation dim = ResourceLocation.tryParse(portal.getString("dim"));
            if (dim != null) {
                state.portalDimension = ResourceKey.create(
                        net.minecraft.core.registries.Registries.DIMENSION, dim);
                state.portalPos = new BlockPos(portal.getInt("x"), portal.getInt("y"), portal.getInt("z"));
            }
        }
        if (tag.contains("exitPortal", Tag.TAG_COMPOUND)) {
            CompoundTag exit = tag.getCompound("exitPortal");
            state.exitPortalPos = new BlockPos(exit.getInt("x"), exit.getInt("y"), exit.getInt("z"));
        }

        for (Tag participant : tag.getList("participants", Tag.TAG_INT_ARRAY)) {
            state.participants.add(NbtUtils.loadUUID(participant));
        }
        for (Tag scaredTag : tag.getList("scared", Tag.TAG_INT_ARRAY)) {
            state.scared.add(NbtUtils.loadUUID(scaredTag));
        }
        for (Tag whisperTag : tag.getList("whispered", Tag.TAG_INT_ARRAY)) {
            state.whispered.add(NbtUtils.loadUUID(whisperTag));
        }
        for (Tag upgradeTag : tag.getList("exitUpgraded", Tag.TAG_INT_ARRAY)) {
            state.exitUpgraded.add(NbtUtils.loadUUID(upgradeTag));
        }
        for (Tag lockTag : tag.getList("lockedOut", Tag.TAG_COMPOUND)) {
            CompoundTag lock = (CompoundTag) lockTag;
            state.lockedOut.put(lock.getUUID("uuid"), lock.getInt("instance"));
        }
        for (Tag entryTag : tag.getList("enteredAt", Tag.TAG_COMPOUND)) {
            CompoundTag entry = (CompoundTag) entryTag;
            state.enteredAt.put(entry.getUUID("uuid"), entry.getLong("millis"));
        }
        for (Tag anchorTag : tag.getList("returnAnchors", Tag.TAG_COMPOUND)) {
            CompoundTag anchor = (CompoundTag) anchorTag;
            ResourceLocation dim = ResourceLocation.tryParse(anchor.getString("dim"));
            if (dim == null) {
                continue;
            }
            state.returnAnchors.put(anchor.getUUID("uuid"), new ReturnAnchor(
                    ResourceKey.create(net.minecraft.core.registries.Registries.DIMENSION, dim),
                    anchor.getDouble("x"), anchor.getDouble("y"), anchor.getDouble("z"),
                    anchor.getFloat("yaw"), anchor.getFloat("pitch")));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putString("phase", phase.name().toLowerCase(Locale.ROOT));
        tag.putLong("endsAtEpochMillis", endsAtEpochMillis);
        tag.putInt("instanceId", instanceId);
        tag.putInt("stampCursor", stampCursor);
        tag.putBoolean("rewardGranted", rewardGranted);

        if (portalDimension != null && portalPos != null) {
            CompoundTag portal = new CompoundTag();
            portal.putString("dim", portalDimension.location().toString());
            portal.putInt("x", portalPos.getX());
            portal.putInt("y", portalPos.getY());
            portal.putInt("z", portalPos.getZ());
            tag.put("portal", portal);
        }
        if (exitPortalPos != null) {
            CompoundTag exit = new CompoundTag();
            exit.putInt("x", exitPortalPos.getX());
            exit.putInt("y", exitPortalPos.getY());
            exit.putInt("z", exitPortalPos.getZ());
            tag.put("exitPortal", exit);
        }

        tag.put("participants", uuidList(participants));
        tag.put("scared", uuidList(scared));
        tag.put("whispered", uuidList(whispered));
        tag.put("exitUpgraded", uuidList(exitUpgraded));

        ListTag lockedOutTag = new ListTag();
        for (Map.Entry<UUID, Integer> entry : lockedOut.entrySet()) {
            CompoundTag lock = new CompoundTag();
            lock.putUUID("uuid", entry.getKey());
            lock.putInt("instance", entry.getValue());
            lockedOutTag.add(lock);
        }
        tag.put("lockedOut", lockedOutTag);

        ListTag enteredAtTag = new ListTag();
        for (Map.Entry<UUID, Long> entry : enteredAt.entrySet()) {
            CompoundTag entryTag = new CompoundTag();
            entryTag.putUUID("uuid", entry.getKey());
            entryTag.putLong("millis", entry.getValue());
            enteredAtTag.add(entryTag);
        }
        tag.put("enteredAt", enteredAtTag);

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
        tag.put("returnAnchors", anchorsTag);
        return tag;
    }

    private static ListTag uuidList(Set<UUID> uuids) {
        ListTag list = new ListTag();
        for (UUID uuid : uuids) {
            list.add(NbtUtils.createUUID(uuid));
        }
        return list;
    }
}
