package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * WOAH-05 quest + lifecycle persistence (plan §3.7) — {@code eclipse_echo_grove.dat}
 * in the overworld store (the {@code ghosts/GhostsState} pattern via
 * {@link EclipseSavedData#getOverworld}).
 *
 * <p>Holds: {@code placed} (terraforming done), {@code treeCenter}, the
 * {@code collectedOrbs} bitmask (0–4), {@code deposited} (0–5), {@code finaleDone}
 * and the uuid lists of the persistent static displays / orbs so repair
 * ({@code /dev woah echo reset}) can find everything again.</p>
 */
public final class EchoGroveState extends SavedData {
    public static final String DATA_ID = "eclipse_echo_grove";

    private static final String TAG_PLACED = "placed";
    private static final String TAG_TREE = "treeCenter";
    private static final String TAG_COLLECTED = "collectedOrbs";
    private static final String TAG_DEPOSITED = "deposited";
    private static final String TAG_FINALE = "finaleDone";
    private static final String TAG_STATIC = "staticDisplays";
    private static final String TAG_ORBS = "orbs";

    private boolean placed;
    @Nullable
    private BlockPos treeCenter;
    private int collectedOrbs;
    private int deposited;
    private boolean finaleDone;
    private final List<UUID> staticDisplayUuids = new ArrayList<>();
    private final List<UUID> orbUuids = new ArrayList<>();

    public EchoGroveState() {}

    public static EchoGroveState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(EchoGroveState::new, EchoGroveState::load));
    }

    public static EchoGroveState load(CompoundTag tag, HolderLookup.Provider registries) {
        EchoGroveState state = new EchoGroveState();
        state.placed = tag.getBoolean(TAG_PLACED);
        state.treeCenter = NbtUtils.readBlockPos(tag, TAG_TREE).orElse(null);
        state.collectedOrbs = tag.getInt(TAG_COLLECTED);
        state.deposited = tag.getInt(TAG_DEPOSITED);
        state.finaleDone = tag.getBoolean(TAG_FINALE);
        readUuids(tag, TAG_STATIC, state.staticDisplayUuids);
        readUuids(tag, TAG_ORBS, state.orbUuids);
        return state;
    }

    private static void readUuids(CompoundTag tag, String key, List<UUID> into) {
        if (tag.contains(key, Tag.TAG_LIST)) {
            ListTag list = tag.getList(key, Tag.TAG_INT_ARRAY);
            for (Tag entry : list) {
                into.add(NbtUtils.loadUUID(entry));
            }
        }
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_PLACED, placed);
        if (treeCenter != null) {
            tag.put(TAG_TREE, NbtUtils.writeBlockPos(treeCenter));
        }
        tag.putInt(TAG_COLLECTED, collectedOrbs);
        tag.putInt(TAG_DEPOSITED, deposited);
        tag.putBoolean(TAG_FINALE, finaleDone);
        tag.put(TAG_STATIC, writeUuids(staticDisplayUuids));
        tag.put(TAG_ORBS, writeUuids(orbUuids));
        return tag;
    }

    private static ListTag writeUuids(List<UUID> uuids) {
        ListTag list = new ListTag();
        for (UUID uuid : uuids) {
            list.add(NbtUtils.createUUID(uuid));
        }
        return list;
    }

    // ------------------------------------------------------------------ accessors

    public boolean placed() {
        return placed;
    }

    @Nullable
    public BlockPos treeCenter() {
        return treeCenter;
    }

    public void setPlaced(BlockPos treeCenter) {
        this.placed = true;
        this.treeCenter = treeCenter.immutable();
        setDirty();
    }

    /** Bitmask of collected lost orbs (bits 0–4). */
    public int collectedOrbs() {
        return collectedOrbs;
    }

    public boolean orbCollected(int kind) {
        return kind >= 0 && kind <= 4 && (collectedOrbs & (1 << kind)) != 0;
    }

    public void collectOrb(int kind) {
        if (kind >= 0 && kind <= 4) {
            collectedOrbs |= 1 << kind;
            setDirty();
        }
    }

    public int deposited() {
        return deposited;
    }

    /** Increments the deposit counter (caller checked the cap) and returns the new value. */
    public int deposit() {
        deposited = Math.min(5, deposited + 1);
        setDirty();
        return deposited;
    }

    public boolean finaleDone() {
        return finaleDone;
    }

    public void setFinaleDone() {
        finaleDone = true;
        setDirty();
    }

    public List<UUID> staticDisplayUuids() {
        return staticDisplayUuids;
    }

    public List<UUID> orbUuids() {
        return orbUuids;
    }

    public void rememberStaticDisplay(UUID uuid) {
        staticDisplayUuids.add(uuid);
        setDirty();
    }

    public void rememberOrb(UUID uuid) {
        orbUuids.add(uuid);
        setDirty();
    }

    public void clearOrbUuids() {
        orbUuids.clear();
        setDirty();
    }

    /** Quest reset ({@code /dev woah echo reset}): terrain + static displays stay. */
    public void resetQuest() {
        collectedOrbs = 0;
        deposited = 0;
        finaleDone = false;
        setDirty();
    }
}
