package dev.projecteclipse.eclipse.devtools.dev;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/** Persistent per-player client render-distance pins ({@code eclipse_client_push.dat}). */
public final class DevViewDistanceData extends SavedData {
    public static final String DATA_ID = "eclipse_client_push";

    private static final String TAG_PINS = "pins";
    private static final String TAG_UUID = "uuid";
    private static final String TAG_CHUNKS = "chunks";

    private final Map<UUID, Integer> pins = new LinkedHashMap<>();

    public DevViewDistanceData() {}

    public static DevViewDistanceData get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(DevViewDistanceData::new, DevViewDistanceData::load));
    }

    private static DevViewDistanceData load(CompoundTag tag, HolderLookup.Provider registries) {
        DevViewDistanceData data = new DevViewDistanceData();
        if (tag.contains(TAG_PINS, Tag.TAG_LIST)) {
            ListTag list = tag.getList(TAG_PINS, Tag.TAG_COMPOUND);
            for (int index = 0; index < list.size(); index++) {
                CompoundTag pin = list.getCompound(index);
                if (pin.hasUUID(TAG_UUID)) {
                    int chunks = pin.getInt(TAG_CHUNKS);
                    if (chunks >= 2 && chunks <= 32) {
                        data.pins.put(pin.getUUID(TAG_UUID), chunks);
                    }
                }
            }
        }
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        pins.forEach((uuid, chunks) -> {
            CompoundTag pin = new CompoundTag();
            pin.putUUID(TAG_UUID, uuid);
            pin.putInt(TAG_CHUNKS, chunks);
            list.add(pin);
        });
        tag.put(TAG_PINS, list);
        return tag;
    }

    public int pin(UUID uuid) {
        return pins.getOrDefault(uuid, 0);
    }

    public void setPin(UUID uuid, int chunks) {
        if (!Integer.valueOf(chunks).equals(pins.put(uuid, chunks))) {
            setDirty();
        }
    }

    public boolean removePin(UUID uuid) {
        if (pins.remove(uuid) != null) {
            setDirty();
            return true;
        }
        return false;
    }

    public Map<UUID, Integer> pinsSnapshot() {
        return Map.copyOf(pins);
    }
}
