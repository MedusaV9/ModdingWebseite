package dev.projecteclipse.eclipse.limbo.door;

import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * P6-W3 version stamp of the limbo ghost ship, persisted as its own tiny
 * {@code data/eclipse_ship_version.dat} in the LIMBO dimension's data storage
 * (deliberately NOT a new field on the cross-planner shared {@code EclipseWorldState} —
 * plans_v3 §2.5 migration rule; same pattern as P6-W4's
 * {@code worldgen/structure/SanctumVersionData}).
 *
 * <p>Versions:</p>
 * <ul>
 *   <li>{@link #VERSION_NONE} — no ship ever stamped by versioned code. Worlds saved
 *       before this class existed have a v1 ship but no version file;
 *       {@code GhostShipBuilder.buildIfNeeded} adopts those as {@link #VERSION_V1} when
 *       {@code EclipseWorldState.isGhostShipBuilt()} is already true.</li>
 *   <li>{@link #VERSION_V1} — the original minimal hull (flat wool sails, no
 *       superstructure). Cleared and rebuilt on the next boot without a live
 *       Ferryman.</li>
 *   <li>{@link #VERSION_V2} — the §2.5 rebuild (curved hull, forecastle/sterncastle,
 *       tattered sails, Respawn Door). Terminal: once v2, boots make ZERO block changes
 *       (restart-idempotence contract of the build).</li>
 * </ul>
 */
public final class ShipVersionData extends SavedData {
    public static final String DATA_NAME = "eclipse_ship_version";

    /** No versioned ship stamped yet (fresh world, or legacy pre-version save). */
    public static final int VERSION_NONE = 0;
    /** v1 minimal ship (pre-P6 rework). */
    public static final int VERSION_V1 = 1;
    /** v2 ghost ship (§2.5 rebuild + Respawn Door bulkhead). */
    public static final int VERSION_V2 = 2;

    private static final String TAG_VERSION = "version";

    private int version = VERSION_NONE;

    public ShipVersionData() {}

    /** The version stamp of the given level's data storage (use LIMBO). */
    public static ShipVersionData get(ServerLevel limbo) {
        return limbo.getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(ShipVersionData::new, ShipVersionData::load),
                DATA_NAME);
    }

    public static ShipVersionData load(CompoundTag tag, HolderLookup.Provider registries) {
        ShipVersionData data = new ShipVersionData();
        data.version = tag.getInt(TAG_VERSION);
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_VERSION, this.version);
        return tag;
    }

    /** Current ship version ({@link #VERSION_NONE} until a build stamps one). */
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
