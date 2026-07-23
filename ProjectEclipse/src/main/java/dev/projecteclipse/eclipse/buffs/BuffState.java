package dev.projecteclipse.eclipse.buffs;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Persisted active timed buffs ({@code eclipse_buffs.dat}, overworld storage).
 */
public final class BuffState extends SavedData {
    public static final String DATA_ID = "eclipse_buffs";

    private static final String TAG_ACTIVE = "active";
    private static final String TAG_ID = "id";
    private static final String TAG_ENDS = "endsAtEpochMillis";
    private static final String TAG_MAG = "magnitude";
    private static final String TAG_LAST_PERIODIC = "lastPeriodicEpochMillis";

    private final List<BuffMath.ActiveBuff> active = new ArrayList<>();

    public BuffState() {}

    public static BuffState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(BuffState::new, BuffState::load));
    }

    public static BuffState load(CompoundTag tag, HolderLookup.Provider registries) {
        BuffState state = new BuffState();
        if (tag.contains(TAG_ACTIVE, Tag.TAG_LIST)) {
            ListTag list = tag.getList(TAG_ACTIVE, Tag.TAG_COMPOUND);
            for (int i = 0; i < list.size(); i++) {
                CompoundTag entry = list.getCompound(i);
                state.active.add(new BuffMath.ActiveBuff(
                        entry.getString(TAG_ID),
                        entry.getLong(TAG_ENDS),
                        entry.getFloat(TAG_MAG),
                        entry.getLong(TAG_LAST_PERIODIC)));
            }
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (BuffMath.ActiveBuff buff : active) {
            CompoundTag entry = new CompoundTag();
            entry.putString(TAG_ID, buff.id());
            entry.putLong(TAG_ENDS, buff.endsAtEpochMillis());
            entry.putFloat(TAG_MAG, buff.magnitude());
            entry.putLong(TAG_LAST_PERIODIC, buff.lastPeriodicEpochMillis());
            list.add(entry);
        }
        tag.put(TAG_ACTIVE, list);
        return tag;
    }

    public List<BuffMath.ActiveBuff> active() {
        return List.copyOf(active);
    }

    public void setActive(List<BuffMath.ActiveBuff> next) {
        active.clear();
        active.addAll(next);
        setDirty();
    }

    public void updatePeriodicFire(String id, long epochMillis) {
        for (int i = 0; i < active.size(); i++) {
            BuffMath.ActiveBuff buff = active.get(i);
            if (buff.id().equals(id)) {
                active.set(i, new BuffMath.ActiveBuff(buff.id(), buff.endsAtEpochMillis(), buff.magnitude(), epochMillis));
                setDirty();
                return;
            }
        }
    }
}
