package dev.projecteclipse.eclipse.woah.resonance;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * WOAH-04 §3.5 persistence — its own tiny file {@code data/eclipse_resonance_field.dat}
 * in the overworld storage (the {@code SkyLauncher.LauncherData} school; plans_v3 §2.5
 * forbids new fields on shared state). Holds the built flag + geometry seeds + the
 * melody-machine state. Deliberately NO entity UUIDs: displays and interactions are
 * resolved via tags + radius queries and rebuilt deterministically from the seeds when
 * missing — self-healing beats UUID bookkeeping (a {@code /kill @e[tag=…]} heals in
 * ≤ 200 ticks).
 */
public final class ResonanceFieldData extends SavedData {
    public static final String DATA_NAME = "eclipse_resonance_field";

    /** One monolith's deterministic build inputs + tone wiring (§3.5). */
    public static final class Monolith {
        /** 0 = S, 1 = M, 2 = L (§5.2 layer table). */
        public final int sizeClass;
        /** Base anchor on the bowl floor (entity anchor of every display layer). */
        public final BlockPos basePos;
        /** Visual height in blocks (20–40). */
        public final float height;
        /** Base girth in blocks (3.0–6.0). */
        public final float girth;
        /** Seed of the global lean quaternion (2–10° about a random XZ axis). */
        public final long tiltSeed;
        /** Seed of the layer set (core segments / facet shells / glints). */
        public final long layerSeed;
        /** Pentatonic tone index 0–8 ({@link ResonanceTones}). */
        public final int toneIndex;
        /** Neighbor-graph crystal indices (2–3 entries). */
        public final int[] neighbors;

        public Monolith(int sizeClass, BlockPos basePos, float height, float girth,
                long tiltSeed, long layerSeed, int toneIndex, int[] neighbors) {
            this.sizeClass = sizeClass;
            this.basePos = basePos;
            this.height = height;
            this.girth = girth;
            this.tiltSeed = tiltSeed;
            this.layerSeed = layerSeed;
            this.toneIndex = toneIndex;
            this.neighbors = neighbors;
        }
    }

    private boolean built;
    @Nullable
    private BlockPos anchor;
    @Nullable
    private BlockPos altarPos;
    private int plateauY;
    private final List<Monolith> monoliths = new ArrayList<>(ResonanceTones.TONE_COUNT);

    // --- melody statemachine (§3.2) ---
    private long melodySeed;
    private int[] melody = new int[0];
    private int progressIndex;
    private int failCount;
    private int stateOrdinal;
    private long stateSince;
    private long cooldownUntil;
    private int solveCount;

    public ResonanceFieldData() {}

    public static ResonanceFieldData get(ServerLevel overworld) {
        return overworld.getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(ResonanceFieldData::new, ResonanceFieldData::load),
                DATA_NAME);
    }

    public static ResonanceFieldData load(CompoundTag tag, HolderLookup.Provider registries) {
        ResonanceFieldData data = new ResonanceFieldData();
        data.built = tag.getBoolean("built");
        if (tag.contains("anchor")) {
            data.anchor = BlockPos.of(tag.getLong("anchor"));
        }
        if (tag.contains("altar")) {
            data.altarPos = BlockPos.of(tag.getLong("altar"));
        }
        data.plateauY = tag.getInt("plateauY");
        ListTag rows = tag.getList("monoliths", Tag.TAG_COMPOUND);
        for (int i = 0; i < rows.size(); i++) {
            CompoundTag row = rows.getCompound(i);
            data.monoliths.add(new Monolith(row.getInt("sizeClass"),
                    BlockPos.of(row.getLong("basePos")), row.getFloat("height"),
                    row.getFloat("girth"), row.getLong("tiltSeed"), row.getLong("layerSeed"),
                    row.getInt("toneIndex"), row.getIntArray("neighbors")));
        }
        data.melodySeed = tag.getLong("melodySeed");
        data.melody = tag.getIntArray("melody");
        data.progressIndex = tag.getInt("progressIndex");
        data.failCount = tag.getInt("failCount");
        data.stateOrdinal = tag.getInt("state");
        data.stateSince = tag.getLong("stateSince");
        data.cooldownUntil = tag.getLong("cooldownUntil");
        data.solveCount = tag.getInt("solveCount");
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean("built", this.built);
        if (this.anchor != null) {
            tag.putLong("anchor", this.anchor.asLong());
        }
        if (this.altarPos != null) {
            tag.putLong("altar", this.altarPos.asLong());
        }
        tag.putInt("plateauY", this.plateauY);
        ListTag rows = new ListTag();
        for (Monolith monolith : this.monoliths) {
            CompoundTag row = new CompoundTag();
            row.putInt("sizeClass", monolith.sizeClass);
            row.putLong("basePos", monolith.basePos.asLong());
            row.putFloat("height", monolith.height);
            row.putFloat("girth", monolith.girth);
            row.putLong("tiltSeed", monolith.tiltSeed);
            row.putLong("layerSeed", monolith.layerSeed);
            row.putInt("toneIndex", monolith.toneIndex);
            row.putIntArray("neighbors", monolith.neighbors);
            rows.add(row);
        }
        tag.put("monoliths", rows);
        tag.putLong("melodySeed", this.melodySeed);
        tag.putIntArray("melody", this.melody);
        tag.putInt("progressIndex", this.progressIndex);
        tag.putInt("failCount", this.failCount);
        tag.putInt("state", this.stateOrdinal);
        tag.putLong("stateSince", this.stateSince);
        tag.putLong("cooldownUntil", this.cooldownUntil);
        tag.putInt("solveCount", this.solveCount);
        return tag;
    }

    // --- geometry ---

    public boolean built() {
        return this.built;
    }

    @Nullable
    public BlockPos anchor() {
        return this.anchor;
    }

    @Nullable
    public BlockPos altarPos() {
        return this.altarPos;
    }

    public int plateauY() {
        return this.plateauY;
    }

    public List<Monolith> monoliths() {
        return this.monoliths;
    }

    /** Writes the geometry after a successful build (the builder is the only caller). */
    public void setGeometry(BlockPos anchor, BlockPos altarPos, int plateauY,
            List<Monolith> monoliths) {
        this.anchor = anchor;
        this.altarPos = altarPos;
        this.plateauY = plateauY;
        this.monoliths.clear();
        this.monoliths.addAll(monoliths);
        this.built = true;
        setDirty();
    }

    // --- melody machine ---

    public long melodySeed() {
        return this.melodySeed;
    }

    public int[] melody() {
        return this.melody;
    }

    /** Re-rolls the melody seed and derives the redundant melody array (debuggability). */
    public void rerollMelody(long seed) {
        this.melodySeed = seed;
        this.melody = ResonanceTones.rollMelody(seed);
        this.progressIndex = 0;
        setDirty();
    }

    public int progressIndex() {
        return this.progressIndex;
    }

    public void setProgressIndex(int index) {
        if (this.progressIndex != index) {
            this.progressIndex = index;
            setDirty();
        }
    }

    public int failCount() {
        return this.failCount;
    }

    public void setFailCount(int count) {
        if (this.failCount != count) {
            this.failCount = count;
            setDirty();
        }
    }

    public int stateOrdinal() {
        return this.stateOrdinal;
    }

    public long stateSince() {
        return this.stateSince;
    }

    public void setState(int ordinal, long gameTime) {
        this.stateOrdinal = ordinal;
        this.stateSince = gameTime;
        setDirty();
    }

    public long cooldownUntil() {
        return this.cooldownUntil;
    }

    public void setCooldownUntil(long gameTime) {
        if (this.cooldownUntil != gameTime) {
            this.cooldownUntil = gameTime;
            setDirty();
        }
    }

    public int solveCount() {
        return this.solveCount;
    }

    public void incrementSolveCount() {
        this.solveCount++;
        setDirty();
    }
}
