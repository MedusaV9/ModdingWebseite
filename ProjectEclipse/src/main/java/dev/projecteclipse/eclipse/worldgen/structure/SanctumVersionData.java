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
 *
 * <p><b>Island revision (W4-ISLAND):</b> {@link #version()} is a FROZEN interface — several
 * consumers ({@code IntroSequence}, {@code SanctumOrbitals}) compare against
 * {@link #VERSION_FLOATING} with exact equality, so the geometry v3 dress pass is stamped
 * in a separate {@link #revision()} counter instead of a new version number. Semantics:
 * {@code version() >= VERSION_FLOATING && revision() < REVISION_ISLAND_V3} → the island is
 * floating but still wears the v2 dressing; {@code AltarSanctumBuilder.ensureSanctum} runs
 * the additive {@link FloatingSanctumBuilder#upgradeToV3 v3 dress pass} once and stamps
 * {@link #REVISION_ISLAND_V3} (same adopt/flip idempotence contract as the v1→v2 flip —
 * old saves have no revision tag, load as {@link #REVISION_NONE} and migrate on boot).</p>
 */
public final class SanctumVersionData extends SavedData {
    public static final String DATA_NAME = "eclipse_sanctum_version";

    /** No versioned sanctum stamped yet (fresh world, or legacy pre-version save). */
    public static final int VERSION_NONE = 0;
    /** v1 grounded sanctum (stage-0 world, pre-intro). */
    public static final int VERSION_GROUNDED = 1;
    /** v2 floating island + crater (stage 1+, post-intro fusion). */
    public static final int VERSION_FLOATING = 2;

    /** No island dress revision stamped (pre-W4-ISLAND save, or not floating yet). */
    public static final int REVISION_NONE = 0;
    /** Geometry v3 dress pass (belly tendrils, satellite islets, rune ring, crater terraces). */
    public static final int REVISION_ISLAND_V3 = 3;

    private static final String TAG_VERSION = "version";
    private static final String TAG_REVISION = "revision";

    private int version = VERSION_NONE;
    private int revision = REVISION_NONE;

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
        data.revision = tag.getInt(TAG_REVISION);
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_VERSION, this.version);
        tag.putInt(TAG_REVISION, this.revision);
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

    /** Current island dress revision ({@link #REVISION_NONE} until a dress pass stamps one). */
    public int revision() {
        return this.revision;
    }

    /** Stamps a new island dress revision (no-op when unchanged; marks dirty otherwise). */
    public void setRevision(int revision) {
        if (this.revision != revision) {
            this.revision = revision;
            setDirty();
        }
    }
}
