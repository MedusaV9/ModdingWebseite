package dev.projecteclipse.eclipse.core.state;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save worldgen-overhaul state (design D9), stored in the overworld's data storage as
 * {@code data/eclipse_worldgen_state.dat} — deliberately a SEPARATE file from
 * {@link EclipseWorldState} so the P1 worldgen packages never collide with other planners
 * on file ownership. Obtain via {@link #get(MinecraftServer)}.
 *
 * <p><b>Pure storage</b>: typed accessors only, no behavior. The consumers are:</p>
 * <ul>
 *   <li>{@link #pendingStructures()} — W1.6's {@code StructurePendingRegistry} rows (opaque
 *       {@link CompoundTag}s; the registry owns the row schema, this class only persists
 *       them).</li>
 *   <li>{@link #newRings()} — W1.5's {@code worldgen.stage.NewRingRegistry} rows: annuli
 *       grown by genuine stage commits, consumed by P4/P6 glitched-mob spawn rules.</li>
 *   <li>{@link #breachOpen()} / {@link #endDiscMaterialized()} — W1.7/W1.8 event-geometry
 *       flags. The setters (and load) mirror both flags into
 *       {@link FrozenParams#mirrorMaterializationFlags} so worldgen worker threads see them
 *       without touching SavedData (the terrain function reads the mirror per column).</li>
 *   <li>{@link #fogChests()} — W1.9's fog-storm chest index ({@code siteId → placed chest
 *       positions}), so P5 loot commands can find placed chests after a restart.</li>
 * </ul>
 */
public final class EclipseWorldgenState extends SavedData {
    public static final String DATA_NAME = "eclipse_worldgen_state";

    private static final String TAG_PENDING_STRUCTURES = "pendingStructures";
    private static final String TAG_NEW_RINGS = "newRings";
    private static final String TAG_BREACH_OPEN = "breachOpen";
    private static final String TAG_END_DISC_MATERIALIZED = "endDiscMaterialized";
    private static final String TAG_FOG_CHESTS = "fogChests";

    /**
     * One freshly-grown annulus (design D11): {@code dim} is the disc profile name
     * ({@code "overworld"} / {@code "nether"}), {@code innerR}/{@code outerR} the radius
     * band of the grown ring, {@code stage} the stage that grew it and
     * {@code committedGameTime} the overworld game time when its sweep completed
     * (freshness decays from this timestamp).
     */
    public record NewRing(String dim, int innerR, int outerR, int stage, long committedGameTime) {
        CompoundTag toTag() {
            CompoundTag tag = new CompoundTag();
            tag.putString("dim", this.dim);
            tag.putInt("innerR", this.innerR);
            tag.putInt("outerR", this.outerR);
            tag.putInt("stage", this.stage);
            tag.putLong("committedGameTime", this.committedGameTime);
            return tag;
        }

        static NewRing fromTag(CompoundTag tag) {
            return new NewRing(tag.getString("dim"), tag.getInt("innerR"), tag.getInt("outerR"),
                    tag.getInt("stage"), tag.getLong("committedGameTime"));
        }
    }

    private final List<CompoundTag> pendingStructures = new ArrayList<>();
    private final List<NewRing> newRings = new ArrayList<>();
    private final Map<String, List<BlockPos>> fogChests = new LinkedHashMap<>();
    private boolean breachOpen = false;
    private boolean endDiscMaterialized = false;

    public EclipseWorldgenState() {}

    public static EclipseWorldgenState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(EclipseWorldgenState::new, EclipseWorldgenState::load),
                DATA_NAME);
    }

    public static EclipseWorldgenState load(CompoundTag tag, HolderLookup.Provider registries) {
        EclipseWorldgenState state = new EclipseWorldgenState();
        for (Tag entry : tag.getList(TAG_PENDING_STRUCTURES, Tag.TAG_COMPOUND)) {
            state.pendingStructures.add(((CompoundTag) entry).copy());
        }
        for (Tag entry : tag.getList(TAG_NEW_RINGS, Tag.TAG_COMPOUND)) {
            state.newRings.add(NewRing.fromTag((CompoundTag) entry));
        }
        state.breachOpen = tag.getBoolean(TAG_BREACH_OPEN);
        state.endDiscMaterialized = tag.getBoolean(TAG_END_DISC_MATERIALIZED);
        CompoundTag chests = tag.getCompound(TAG_FOG_CHESTS);
        for (String siteId : chests.getAllKeys()) {
            List<BlockPos> positions = new ArrayList<>();
            for (long packed : chests.getLongArray(siteId)) {
                positions.add(BlockPos.of(packed));
            }
            state.fogChests.put(siteId, positions);
        }
        // Worker threads read the flags through the FrozenParams mirror (the volatile
        // context activates on ServerAboutToStartEvent, before any SavedData can load).
        FrozenParams.mirrorMaterializationFlags(state.breachOpen, state.endDiscMaterialized);
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag pendingList = new ListTag();
        for (CompoundTag row : this.pendingStructures) {
            pendingList.add(row.copy());
        }
        tag.put(TAG_PENDING_STRUCTURES, pendingList);

        ListTag ringList = new ListTag();
        for (NewRing ring : this.newRings) {
            ringList.add(ring.toTag());
        }
        tag.put(TAG_NEW_RINGS, ringList);

        tag.putBoolean(TAG_BREACH_OPEN, this.breachOpen);
        tag.putBoolean(TAG_END_DISC_MATERIALIZED, this.endDiscMaterialized);

        CompoundTag chests = new CompoundTag();
        for (Map.Entry<String, List<BlockPos>> entry : this.fogChests.entrySet()) {
            long[] packed = new long[entry.getValue().size()];
            for (int i = 0; i < packed.length; i++) {
                packed[i] = entry.getValue().get(i).asLong();
            }
            chests.putLongArray(entry.getKey(), packed);
        }
        tag.put(TAG_FOG_CHESTS, chests);
        return tag;
    }

    // --- pending structures (W1.6 StructurePendingRegistry rows; schema owned there) ---

    /** Snapshot of the persisted pending-structure rows, in enqueue order. */
    public List<CompoundTag> pendingStructures() {
        List<CompoundTag> copy = new ArrayList<>(this.pendingStructures.size());
        for (CompoundTag row : this.pendingStructures) {
            copy.add(row.copy());
        }
        return Collections.unmodifiableList(copy);
    }

    /** Replaces the persisted pending-structure rows (W1.6 writes back after every mutation). */
    public void setPendingStructures(List<CompoundTag> rows) {
        this.pendingStructures.clear();
        for (CompoundTag row : rows) {
            this.pendingStructures.add(row.copy());
        }
        setDirty();
    }

    // --- new-ring rows (W1.5 NewRingRegistry; design D11) ---

    /** Unmodifiable view of the recorded fresh-ring rows (may contain decayed rows). */
    public List<NewRing> newRings() {
        return Collections.unmodifiableList(this.newRings);
    }

    /** Appends one freshly-grown annulus row. Only {@code NewRingRegistry} should call this. */
    public void addNewRing(NewRing ring) {
        this.newRings.add(ring);
        setDirty();
    }

    /** Drops every row whose {@code committedGameTime} is older than {@code oldestKept}. */
    public void pruneNewRings(long oldestKept) {
        if (this.newRings.removeIf(ring -> ring.committedGameTime() < oldestKept)) {
            setDirty();
        }
    }

    // --- event-geometry flags (W1.7 breach, W1.8 end disc) ---

    /** Whether the nether breach crater has been materialized in this save. */
    public boolean breachOpen() {
        return this.breachOpen;
    }

    /** Flips the breach flag and mirrors it into {@link FrozenParams} for worker threads. */
    public void setBreachOpen(boolean open) {
        this.breachOpen = open;
        FrozenParams.mirrorMaterializationFlags(this.breachOpen, this.endDiscMaterialized);
        setDirty();
    }

    /** Whether the in-sky End disc has been materialized in this save. */
    public boolean endDiscMaterialized() {
        return this.endDiscMaterialized;
    }

    /** Flips the End-disc flag and mirrors it into {@link FrozenParams} for worker threads. */
    public void setEndDiscMaterialized(boolean materialized) {
        this.endDiscMaterialized = materialized;
        FrozenParams.mirrorMaterializationFlags(this.breachOpen, this.endDiscMaterialized);
        setDirty();
    }

    // --- fog-storm chest index (W1.9 FogStormSites / P5 loot commands) ---

    /** Unmodifiable view of the placed fog-storm chests per site id. */
    public Map<String, List<BlockPos>> fogChests() {
        Map<String, List<BlockPos>> copy = new LinkedHashMap<>();
        for (Map.Entry<String, List<BlockPos>> entry : this.fogChests.entrySet()) {
            copy.put(entry.getKey(), Collections.unmodifiableList(new ArrayList<>(entry.getValue())));
        }
        return Collections.unmodifiableMap(copy);
    }

    /** Records the placed chest positions of one fog-storm site (index order = chest idx). */
    public void setFogChests(String siteId, List<BlockPos> positions) {
        this.fogChests.put(siteId, new ArrayList<>(positions));
        setDirty();
    }
}
