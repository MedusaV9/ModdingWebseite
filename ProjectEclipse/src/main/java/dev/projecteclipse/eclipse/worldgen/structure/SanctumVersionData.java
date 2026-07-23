package dev.projecteclipse.eclipse.worldgen.structure;

import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * P6-W4 version stamp of the spawn sanctum, persisted as its own tiny
 * {@code data/eclipse_sanctum_version.dat} in the overworld data storage (deliberately
 * NOT a new field on the cross-planner shared {@code EclipseWorldState} — plans_v3 §1.6).
 *
 * <p>Versions:</p>
 * <ul>
 *   <li>{@link #VERSION_NONE} — no sanctum ever stamped by versioned code. Worlds saved
 *       before this class existed have a grounded sanctum but no version file;
 *       {@code AltarSanctumBuilder.ensureSanctum} adopts those as
 *       {@link #VERSION_GROUNDED} when {@code EclipseWorldState.isSanctumBuilt()} is
 *       already true.</li>
 *   <li>{@link #VERSION_GROUNDED} — the v1 ground-level sanctum (pre-intro stage 0).</li>
 *   <li>{@link #VERSION_FLOATING} — the v2 floating island + crater
 *       ({@link FloatingSanctumBuilder}). Terminal: once floating, boots make ZERO block
 *       changes (restart-idempotence contract of the build).</li>
 * </ul>
 */
public final class SanctumVersionData extends SavedData {
    public static final String DATA_NAME = "eclipse_sanctum_version";

    /** No versioned sanctum stamped yet (fresh world, or legacy pre-version save). */
    public static final int VERSION_NONE = 0;
    /** v1 grounded sanctum (stage-0 world, pre-intro). */
    public static final int VERSION_GROUNDED = 1;
    /** v2 floating island + crater (stage 1+, post-intro fusion). */
    public static final int VERSION_FLOATING = 2;

    private static final String TAG_VERSION = "version";

    private int version = VERSION_NONE;

    public SanctumVersionData() {}

    /** The version stamp of the given level's data storage (use the OVERWORLD). */
    public static SanctumVersionData get(ServerLevel overworld) {
        return overworld.getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(SanctumVersionData::new, SanctumVersionData::load),
                DATA_NAME);
    }

    public static SanctumVersionData load(CompoundTag tag, HolderLookup.Provider registries) {
        SanctumVersionData data = new SanctumVersionData();
        data.version = tag.getInt(TAG_VERSION);
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_VERSION, this.version);
        return tag;
    }

    /** Current sanctum version ({@link #VERSION_NONE} until a build stamps one). */
    public int version() {
        return this.version;
    }

    /** Stamps a new version (no-op when unchanged; marks dirty otherwise). */
    public void setVersion(int version) {
        if (this.version != version) {
            this.version = version;
            setDirty();
        }
    }
}
