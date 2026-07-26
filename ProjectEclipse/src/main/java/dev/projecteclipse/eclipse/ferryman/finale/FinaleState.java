package dev.projecteclipse.eclipse.ferryman.finale;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * FERRYMAN2 finale-arc bookkeeping, persisted as its own tiny
 * {@code data/eclipse_ferryman_finale.dat} in the OVERWORLD data storage (the
 * {@code ArenaState} pattern — overworld because the island, the portal and the key all
 * live there):
 *
 * <ul>
 *   <li>{@link #orbitCount()} / {@link #orbitSeed()} — the accumulated day-rift orbit
 *       swarm (F-044). Only the COUNT and the SEED persist; the block-display entities
 *       themselves are respawned deterministically on every boot
 *       ({@link DayRiftOrbits}), never saved-and-adopted.</li>
 *   <li>{@link #lastRiftDay()} — dedup so one event day only ever drops one rift beat
 *       (rollover + catch-up steps can both fire on the same boot).</li>
 *   <li>{@link #stage()} — the finale-arc restart law: {@link #STAGE_ORBITS} respawns
 *       the swarm, {@link #STAGE_FORMING} never resumes mid-animation (the boot
 *       finishes the formation instantly), {@link #STAGE_PORTAL_READY} re-ensures the
 *       gate + key entities, {@link #STAGE_DONE} leaves only the standing gate.</li>
 *   <li>{@link #portalPos()} — the gate's anchor cell over the water, chosen once when
 *       the formation starts (deterministic off the altar, but persisted so a later
 *       altar rebuild can never strand the standing gate).</li>
 * </ul>
 */
public final class FinaleState extends SavedData {
    public static final String DATA_NAME = "eclipse_ferryman_finale";

    /** Debris accumulates in orbit; no portal yet. */
    public static final int STAGE_ORBITS = 0;
    /** The day-14 formation animation runs (transient; a restart finishes it instantly). */
    public static final int STAGE_FORMING = 1;
    /** Gate + key stand; the key sequence may start (re-armed after a mid-flight crash). */
    public static final int STAGE_PORTAL_READY = 2;
    /** The key was used and the crossing handed off; only the gate remains standing. */
    public static final int STAGE_DONE = 3;

    private static final String TAG_ORBIT_COUNT = "orbitCount";
    private static final String TAG_ORBIT_SEED = "orbitSeed";
    private static final String TAG_LAST_RIFT_DAY = "lastRiftDay";
    private static final String TAG_STAGE = "stage";
    private static final String TAG_PORTAL_POS = "portalPos";

    private int orbitCount;
    private long orbitSeed;
    private int lastRiftDay;
    private int stage = STAGE_ORBITS;
    @Nullable
    private BlockPos portalPos;

    public FinaleState() {}

    public static FinaleState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(FinaleState::new, FinaleState::load),
                DATA_NAME);
    }

    public static FinaleState load(CompoundTag tag, HolderLookup.Provider registries) {
        FinaleState state = new FinaleState();
        state.orbitCount = Math.max(0, tag.getInt(TAG_ORBIT_COUNT));
        state.orbitSeed = tag.getLong(TAG_ORBIT_SEED);
        state.lastRiftDay = tag.getInt(TAG_LAST_RIFT_DAY);
        state.stage = tag.getInt(TAG_STAGE);
        if (tag.contains(TAG_PORTAL_POS)) {
            state.portalPos = NbtUtils.readBlockPos(tag, TAG_PORTAL_POS).orElse(null);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_ORBIT_COUNT, this.orbitCount);
        tag.putLong(TAG_ORBIT_SEED, this.orbitSeed);
        tag.putInt(TAG_LAST_RIFT_DAY, this.lastRiftDay);
        tag.putInt(TAG_STAGE, this.stage);
        if (this.portalPos != null) {
            tag.put(TAG_PORTAL_POS, NbtUtils.writeBlockPos(this.portalPos));
        }
        return tag;
    }

    /** Live orbit-debris count (0 once the formation consumed the swarm). */
    public int orbitCount() {
        return this.orbitCount;
    }

    public void setOrbitCount(int count) {
        if (this.orbitCount != count) {
            this.orbitCount = Math.max(0, count);
            setDirty();
        }
    }

    /** Deterministic per-index parameter seed; lazily rolled once, then frozen. */
    public long orbitSeed() {
        if (this.orbitSeed == 0L) {
            // Rolled exactly once per world (persisted), never 0 again — the |1 keeps a
            // pathological nanoTime()==0 from re-rolling on the next boot.
            this.orbitSeed = System.nanoTime() | 1L;
            setDirty();
        }
        return this.orbitSeed;
    }

    /** Last event day a rift beat already dropped debris for (dedup). */
    public int lastRiftDay() {
        return this.lastRiftDay;
    }

    public void setLastRiftDay(int day) {
        if (this.lastRiftDay != day) {
            this.lastRiftDay = day;
            setDirty();
        }
    }

    public int stage() {
        return this.stage;
    }

    public void setStage(int stage) {
        if (this.stage != stage) {
            this.stage = stage;
            setDirty();
        }
    }

    /** The gate's anchor cell (feet, over the water), or null before the formation. */
    @Nullable
    public BlockPos portalPos() {
        return this.portalPos;
    }

    public void setPortalPos(@Nullable BlockPos pos) {
        this.portalPos = pos != null ? pos.immutable() : null;
        setDirty();
    }
}
