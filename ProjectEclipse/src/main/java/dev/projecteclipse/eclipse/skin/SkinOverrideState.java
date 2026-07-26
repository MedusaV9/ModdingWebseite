package dev.projecteclipse.eclipse.skin;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Restart-safe register of active skin overrides ({@code eclipse_skins.dat}): who has one,
 * where it came from and what the cached PNG hashed to.
 *
 * <p>Deliberately does NOT store the image — that lives in {@code config/eclipse/skins}
 * (see {@link SkinStore}). Keeping the two apart is what makes the restart path a pure
 * disk re-read instead of a download storm against Mojang/NameMC.</p>
 */
public final class SkinOverrideState extends SavedData {
    public static final String DATA_NAME = "eclipse_skins";

    /**
     * @param source  operator input or {@code asset:<path>} for the bundled admin skin — kept
     *                for the audit trail and for a future manual refresh
     * @param sha256  hash of the cached PNG, so a swapped cache file is visible in the log
     * @param slim    Alex (3 px arms) instead of Steve (4 px arms)
     */
    public record Entry(String source, String sha256, boolean slim, long updatedEpochMillis) {}

    private final Map<UUID, Entry> overrides = new LinkedHashMap<>();

    public SkinOverrideState() {}

    public static SkinOverrideState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(SkinOverrideState::new, SkinOverrideState::load));
    }

    public Map<UUID, Entry> all() {
        return Collections.unmodifiableMap(overrides);
    }

    @Nullable
    public Entry get(UUID player) {
        return overrides.get(player);
    }

    public int size() {
        return overrides.size();
    }

    public void put(UUID player, Entry entry) {
        overrides.put(player, entry);
        setDirty();
    }

    public boolean remove(UUID player) {
        if (overrides.remove(player) == null) {
            return false;
        }
        setDirty();
        return true;
    }

    public static SkinOverrideState load(CompoundTag tag, HolderLookup.Provider registries) {
        SkinOverrideState state = new SkinOverrideState();
        for (Tag raw : tag.getList("overrides", Tag.TAG_COMPOUND)) {
            CompoundTag entry = (CompoundTag) raw;
            if (!entry.hasUUID("uuid")) {
                continue;
            }
            state.overrides.put(entry.getUUID("uuid"), new Entry(
                    entry.getString("source"),
                    entry.getString("sha256"),
                    entry.getBoolean("slim"),
                    entry.getLong("updated")));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        overrides.forEach((uuid, entry) -> {
            CompoundTag row = new CompoundTag();
            row.putUUID("uuid", uuid);
            row.putString("source", entry.source());
            row.putString("sha256", entry.sha256());
            row.putBoolean("slim", entry.slim());
            row.putLong("updated", entry.updatedEpochMillis());
            list.add(row);
        });
        tag.put("overrides", list);
        return tag;
    }
}
