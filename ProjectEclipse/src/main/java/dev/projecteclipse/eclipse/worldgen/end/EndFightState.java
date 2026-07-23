package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Restart-safe state for the one-shot overworld End materialization and dragon fight.
 *
 * <p>This deliberately lives beside the fight instead of adding fields to the shared
 * {@code EclipseWorldgenState}: the latter is owned by another worldgen worker. The
 * materialization cursor is persisted at chunk boundaries, while entity UUIDs, health
 * and last position let the controller reattach (or safely reconstruct) after restart.</p>
 */
public final class EndFightState extends SavedData {
    public static final String DATA_NAME = "eclipse_end_fight";

    private static final String TAG_MATERIALIZATION_STARTED = "materializationStarted";
    private static final String TAG_MATERIALIZATION_COMPLETE = "materializationComplete";
    private static final String TAG_MATERIALIZATION_CURSOR = "materializationCursor";
    private static final String TAG_CRYSTALS = "crystals";
    private static final String TAG_CRYSTALS_REMAINING = "crystalsRemaining";
    private static final String TAG_DRAGON = "dragon";
    private static final String TAG_DRAGON_POS = "dragonPos";
    private static final String TAG_DRAGON_HEALTH = "dragonHealth";
    private static final String TAG_DEATH_STARTED = "deathStartedGameTime";
    private static final String TAG_DRAGON_KILLED = "dragonKilled";

    private boolean materializationStarted;
    private boolean materializationComplete;
    private long materializationCursor;
    private final List<UUID> crystalIds = new ArrayList<>();
    private int crystalsRemaining;
    @Nullable
    private UUID dragonId;
    @Nullable
    private BlockPos dragonPos;
    private float dragonHealth;
    private long deathStartedGameTime = -1L;
    private boolean dragonKilled;

    public EndFightState() {}

    public static EndFightState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(EndFightState::new, EndFightState::load),
                DATA_NAME);
    }

    public static EndFightState load(CompoundTag tag, HolderLookup.Provider registries) {
        EndFightState state = new EndFightState();
        state.materializationStarted = tag.getBoolean(TAG_MATERIALIZATION_STARTED);
        state.materializationComplete = tag.getBoolean(TAG_MATERIALIZATION_COMPLETE);
        state.materializationCursor = Math.max(0L, tag.getLong(TAG_MATERIALIZATION_CURSOR));
        for (Tag entry : tag.getList(TAG_CRYSTALS, Tag.TAG_COMPOUND)) {
            CompoundTag row = (CompoundTag) entry;
            if (row.hasUUID("id")) {
                state.crystalIds.add(row.getUUID("id"));
            }
        }
        state.crystalsRemaining = Math.max(0, tag.getInt(TAG_CRYSTALS_REMAINING));
        if (tag.hasUUID(TAG_DRAGON)) {
            state.dragonId = tag.getUUID(TAG_DRAGON);
        }
        if (tag.contains(TAG_DRAGON_POS, Tag.TAG_LONG)) {
            state.dragonPos = BlockPos.of(tag.getLong(TAG_DRAGON_POS));
        }
        state.dragonHealth = Math.max(0.0F, tag.getFloat(TAG_DRAGON_HEALTH));
        state.deathStartedGameTime = tag.contains(TAG_DEATH_STARTED, Tag.TAG_LONG)
                ? tag.getLong(TAG_DEATH_STARTED) : -1L;
        state.dragonKilled = tag.getBoolean(TAG_DRAGON_KILLED);
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_MATERIALIZATION_STARTED, this.materializationStarted);
        tag.putBoolean(TAG_MATERIALIZATION_COMPLETE, this.materializationComplete);
        tag.putLong(TAG_MATERIALIZATION_CURSOR, this.materializationCursor);
        ListTag crystals = new ListTag();
        for (UUID id : this.crystalIds) {
            CompoundTag row = new CompoundTag();
            row.putUUID("id", id);
            crystals.add(row);
        }
        tag.put(TAG_CRYSTALS, crystals);
        tag.putInt(TAG_CRYSTALS_REMAINING, this.crystalsRemaining);
        if (this.dragonId != null) {
            tag.putUUID(TAG_DRAGON, this.dragonId);
        }
        if (this.dragonPos != null) {
            tag.putLong(TAG_DRAGON_POS, this.dragonPos.asLong());
        }
        tag.putFloat(TAG_DRAGON_HEALTH, this.dragonHealth);
        tag.putLong(TAG_DEATH_STARTED, this.deathStartedGameTime);
        tag.putBoolean(TAG_DRAGON_KILLED, this.dragonKilled);
        return tag;
    }

    public boolean materializationStarted() {
        return this.materializationStarted;
    }

    public boolean materializationComplete() {
        return this.materializationComplete;
    }

    public long materializationCursor() {
        return this.materializationCursor;
    }

    /** Starts the job once; a resumed job retains its persisted cursor. */
    public void beginMaterialization() {
        if (!this.materializationStarted) {
            this.materializationStarted = true;
            this.materializationComplete = false;
            this.materializationCursor = 0L;
            setDirty();
        }
    }

    public void setMaterializationCursor(long cursor) {
        long safe = Math.max(0L, cursor);
        if (safe != this.materializationCursor) {
            this.materializationCursor = safe;
            setDirty();
        }
    }

    public void completeMaterialization() {
        if (!this.materializationComplete) {
            this.materializationStarted = true;
            this.materializationComplete = true;
            setDirty();
        }
    }

    public List<UUID> crystalIds() {
        return List.copyOf(this.crystalIds);
    }

    public int crystalsRemaining() {
        return this.crystalsRemaining;
    }

    public void setCrystals(List<UUID> ids, int remaining) {
        int safeRemaining = Math.max(0, remaining);
        if (this.crystalIds.equals(ids) && this.crystalsRemaining == safeRemaining) {
            return;
        }
        this.crystalIds.clear();
        this.crystalIds.addAll(ids);
        this.crystalsRemaining = safeRemaining;
        setDirty();
    }

    @Nullable
    public UUID dragonId() {
        return this.dragonId;
    }

    @Nullable
    public BlockPos dragonPos() {
        return this.dragonPos;
    }

    public float dragonHealth() {
        return this.dragonHealth;
    }

    /** Persists enough of a live dragon to reattach or reconstruct it. */
    public void updateDragon(UUID id, BlockPos pos, float health) {
        this.dragonId = id;
        this.dragonPos = pos.immutable();
        this.dragonHealth = Math.max(0.0F, health);
        setDirty();
    }

    public long deathStartedGameTime() {
        return this.deathStartedGameTime;
    }

    public void markDeathStarted(long gameTime) {
        if (this.deathStartedGameTime < 0L) {
            this.deathStartedGameTime = gameTime;
            setDirty();
        }
    }

    public boolean dragonKilled() {
        return this.dragonKilled;
    }

    public void setDragonKilled() {
        if (!this.dragonKilled) {
            this.dragonKilled = true;
            this.crystalsRemaining = 0;
            this.deathStartedGameTime = Math.max(0L, this.deathStartedGameTime);
            setDirty();
        }
    }
}
