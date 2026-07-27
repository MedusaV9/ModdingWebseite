package dev.projecteclipse.eclipse.woah.chronostasis;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * WOAH-03 persistence (plan §3.4): its own tiny SavedData in overworld storage
 * ({@code data/eclipse_chrono_stasis.dat}) — the {@code EclipseWorldgenState} ownership
 * law (own file instead of a field on a shared cross-planner schema; the
 * {@code LandmarkDiscoveryService.Data} pattern).
 *
 * <p>Fields: {@code placed} (site materialized — restart resync), {@code sceneSeed}
 * (deterministic rebuild/reconcile of the display scene), {@code joltCount} (time-jolts
 * since the last discharge, survives restarts), {@code discharges} (statistics + the
 * first-discharge reward gate), {@code rewardClaimed} (reward fires exactly once —
 * persisted BEFORE the item spawns, plan §11 risk 4).</p>
 */
public final class ChronoStasisData extends SavedData {
    static final String DATA_NAME = "eclipse_chrono_stasis";

    private boolean placed;
    private long sceneSeed;
    private int joltCount;
    private int discharges;
    private boolean rewardClaimed;

    public ChronoStasisData() {}

    static ChronoStasisData load(CompoundTag tag, HolderLookup.Provider registries) {
        ChronoStasisData data = new ChronoStasisData();
        data.placed = tag.getBoolean("placed");
        data.sceneSeed = tag.getLong("sceneSeed");
        data.joltCount = tag.getInt("joltCount");
        data.discharges = tag.getInt("discharges");
        data.rewardClaimed = tag.getBoolean("rewardClaimed");
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean("placed", this.placed);
        tag.putLong("sceneSeed", this.sceneSeed);
        tag.putInt("joltCount", this.joltCount);
        tag.putInt("discharges", this.discharges);
        tag.putBoolean("rewardClaimed", this.rewardClaimed);
        return tag;
    }

    public static ChronoStasisData get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(ChronoStasisData::new, ChronoStasisData::load));
    }

    public boolean placed() {
        return this.placed;
    }

    public void setPlaced(boolean placed) {
        this.placed = placed;
        setDirty();
    }

    public long sceneSeed() {
        return this.sceneSeed;
    }

    /** Rolled exactly once on first materialization; 0 = never rolled. */
    public void setSceneSeed(long sceneSeed) {
        this.sceneSeed = sceneSeed;
        setDirty();
    }

    public int joltCount() {
        return this.joltCount;
    }

    public void setJoltCount(int joltCount) {
        this.joltCount = Math.max(0, joltCount);
        setDirty();
    }

    public int discharges() {
        return this.discharges;
    }

    public void incrementDischarges() {
        this.discharges++;
        setDirty();
    }

    public boolean rewardClaimed() {
        return this.rewardClaimed;
    }

    public void setRewardClaimed(boolean rewardClaimed) {
        this.rewardClaimed = rewardClaimed;
        setDirty();
    }
}
