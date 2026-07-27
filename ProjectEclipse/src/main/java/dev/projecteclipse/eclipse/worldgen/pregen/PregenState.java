package dev.projecteclipse.eclipse.worldgen.pregen;

import java.util.HashMap;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * F-091 persistent progress of the full-map pregeneration ({@link MapPregenService}),
 * stored as {@code data/eclipse_pregen.dat} in overworld storage (the
 * {@link EclipseSavedData} pattern). One {@link Entry} per disc profile carries the
 * frozen target radius, the deterministic spiral-cursor index (see
 * {@link MapPregenService#chunkAtIndex}), the completed-chunk counter and the done flag —
 * everything an interrupted run needs to resume across restarts.
 *
 * <p><b>Fingerprint invalidation</b>: progress is only meaningful against the exact
 * frozen generator inputs it was produced with. {@link #get} therefore validates a
 * fingerprint of {@link FrozenParams#mapSeed()} + both frozen stage-radius tables on
 * every load; a refrozen or re-authored save (different seed / different radii) clears
 * all entries so the next run starts clean instead of trusting a stale cursor.</p>
 */
public final class PregenState extends SavedData {
    public static final String DATA_NAME = "eclipse_pregen";

    private static final String TAG_FINGERPRINT = "fingerprint";
    private static final String TAG_TARGET_RADIUS = "targetRadius";
    private static final String TAG_CURSOR = "cursor";
    private static final String TAG_CHUNKS_DONE = "chunksDone";
    private static final String TAG_DONE = "done";

    /** Per-dimension resumable progress. {@code targetRadius <= 0} = never started. */
    public static final class Entry {
        private int targetRadius;
        private long cursor;
        private long chunksDone;
        private boolean done;

        /** Pregen radius in blocks this job was started with; {@code <= 0} = no job yet. */
        public int targetRadius() {
            return this.targetRadius;
        }

        /** Spiral index of the first chunk NOT yet issued (the resume point). */
        public long cursor() {
            return this.cursor;
        }

        /** Chunks confirmed generated (freshly promoted or region-probe skipped). */
        public long chunksDone() {
            return this.chunksDone;
        }

        public boolean done() {
            return this.done;
        }
    }

    /** {@link #currentFingerprint()} of the save this progress belongs to; 0 = unset. */
    private long fingerprint;
    /** Keyed by {@link DiscProfile#name()}. */
    private final Map<String, Entry> entries = new HashMap<>();

    public PregenState() {}

    /**
     * Loads (or creates) the state and validates the generator fingerprint — stale
     * progress from a refrozen save is dropped here, before any caller can resume it.
     */
    public static PregenState get(MinecraftServer server) {
        PregenState state = EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(PregenState::new, PregenState::load));
        state.validateFingerprint();
        return state;
    }

    /**
     * Stable hash of every frozen input the pregenerated chunks depend on: the map seed
     * plus both per-save stage-radius tables. Biomes/terrain are pure functions of these
     * (plan F-091 §2.2), so equality means stored progress is still trustworthy.
     */
    public static long currentFingerprint() {
        long h = FrozenParams.mapSeed();
        for (int radius : FrozenParams.stageRadii(DiscProfile.OVERWORLD)) {
            h = h * 31L + radius;
        }
        h = h * 31L + 17L; // separator so [a|b] never collides with [a,b|]
        for (int radius : FrozenParams.stageRadii(DiscProfile.NETHER)) {
            h = h * 31L + radius;
        }
        return h == 0L ? 1L : h; // 0 is the "unset" sentinel
    }

    private void validateFingerprint() {
        long current = currentFingerprint();
        if (this.fingerprint == current) {
            return;
        }
        if (this.fingerprint != 0L && !this.entries.isEmpty()) {
            EclipseMod.LOGGER.info(
                    "PregenState: generator fingerprint changed ({} -> {}) — dropping stale "
                            + "pregen progress for {} dimension(s)",
                    this.fingerprint, current, this.entries.size());
        }
        this.entries.clear();
        this.fingerprint = current;
        this.setDirty();
    }

    /** The (possibly fresh) entry of a profile; never null. */
    public Entry entry(DiscProfile profile) {
        return this.entries.computeIfAbsent(profile.name(), key -> new Entry());
    }

    /**
     * Arms (or re-arms) a job: a changed target radius restarts the spiral from zero —
     * a wider re-run must revisit every ring, and the probe skip makes that cheap.
     */
    public void beginJob(DiscProfile profile, int targetRadius) {
        Entry entry = entry(profile);
        if (entry.targetRadius != targetRadius) {
            entry.cursor = 0L;
            entry.chunksDone = 0L;
        }
        entry.targetRadius = targetRadius;
        entry.done = false;
        this.setDirty();
    }

    /** Persists the resume point (called every ~64 completions + on server stop). */
    public void setProgress(DiscProfile profile, long cursor, long chunksDone) {
        Entry entry = entry(profile);
        entry.cursor = cursor;
        entry.chunksDone = chunksDone;
        this.setDirty();
    }

    public void markDone(DiscProfile profile) {
        Entry entry = entry(profile);
        entry.done = true;
        this.setDirty();
    }

    /** Cancel semantics: forget the job entirely (a later start begins from zero). */
    public void reset(DiscProfile profile) {
        this.entries.remove(profile.name());
        this.setDirty();
    }

    public static PregenState load(CompoundTag tag, HolderLookup.Provider registries) {
        PregenState state = new PregenState();
        state.fingerprint = tag.getLong(TAG_FINGERPRINT);
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            if (!tag.contains(profile.name())) {
                continue;
            }
            CompoundTag sub = tag.getCompound(profile.name());
            Entry entry = new Entry();
            entry.targetRadius = sub.getInt(TAG_TARGET_RADIUS);
            entry.cursor = sub.getLong(TAG_CURSOR);
            entry.chunksDone = sub.getLong(TAG_CHUNKS_DONE);
            entry.done = sub.getBoolean(TAG_DONE);
            state.entries.put(profile.name(), entry);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putLong(TAG_FINGERPRINT, this.fingerprint);
        for (Map.Entry<String, Entry> mapEntry : this.entries.entrySet()) {
            Entry entry = mapEntry.getValue();
            if (entry.targetRadius <= 0) {
                continue; // never-started placeholder — nothing worth persisting
            }
            CompoundTag sub = new CompoundTag();
            sub.putInt(TAG_TARGET_RADIUS, entry.targetRadius);
            sub.putLong(TAG_CURSOR, entry.cursor);
            sub.putLong(TAG_CHUNKS_DONE, entry.chunksDone);
            sub.putBoolean(TAG_DONE, entry.done);
            tag.put(mapEntry.getKey(), sub);
        }
        return tag;
    }
}
