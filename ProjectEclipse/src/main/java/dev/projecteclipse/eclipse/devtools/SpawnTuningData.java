package dev.projecteclipse.eclipse.devtools;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/** Per-save overrides written by {@code /dev spawn}. */
public final class SpawnTuningData extends SavedData {
    public static final String DATA_NAME = "eclipse_spawn_tuning";

    private static final String TAG_RADIUS = "radiusOverride";
    private static final String TAG_PREVIEW = "previewOn";
    private static final String TAG_SPAWN = "spawnOverride";

    private int radiusOverride = -1;
    private boolean previewOn;
    @Nullable
    private BlockPos spawnOverride;

    public SpawnTuningData() {}

    public static SpawnTuningData get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(SpawnTuningData::new, SpawnTuningData::load),
                DATA_NAME);
    }

    public static SpawnTuningData load(CompoundTag tag, HolderLookup.Provider registries) {
        SpawnTuningData data = new SpawnTuningData();
        data.radiusOverride = tag.contains(TAG_RADIUS, Tag.TAG_INT) ? tag.getInt(TAG_RADIUS) : -1;
        data.previewOn = tag.getBoolean(TAG_PREVIEW);
        data.spawnOverride = NbtUtils.readBlockPos(tag, TAG_SPAWN).orElse(null);
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_RADIUS, radiusOverride);
        tag.putBoolean(TAG_PREVIEW, previewOn);
        if (spawnOverride != null) {
            tag.put(TAG_SPAWN, NbtUtils.writeBlockPos(spawnOverride));
        }
        return tag;
    }

    public int radiusOverride() {
        return radiusOverride;
    }

    public void setRadiusOverride(int radius) {
        if (radiusOverride != radius) {
            radiusOverride = radius;
            setDirty();
        }
    }

    public boolean previewOn() {
        return previewOn;
    }

    public void setPreviewOn(boolean previewOn) {
        if (this.previewOn != previewOn) {
            this.previewOn = previewOn;
            setDirty();
        }
    }

    @Nullable
    public BlockPos spawnOverride() {
        return spawnOverride;
    }

    public void setSpawnOverride(BlockPos pos) {
        BlockPos immutable = pos.immutable();
        if (!immutable.equals(spawnOverride)) {
            spawnOverride = immutable;
            setDirty();
        }
    }
}
