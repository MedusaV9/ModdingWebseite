package dev.projecteclipse.eclipse.ferryman;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * PLAN-C C10 crossing bookkeeping, persisted as its own tiny
 * {@code data/eclipse_ferryman_arena.dat} in the OVERWORLD data storage (the
 * {@code limbo.door.ShipVersionData} pattern; overworld because the altar door lives
 * there and the flags must be readable before the arena dimension is ever touched):
 *
 * <ul>
 *   <li>{@link #arenaVersion()} — build stamp of the arena + spectator ship in
 *       {@code eclipse:ferryman_arena} ({@code ArenaBuilder} idempotence law: once
 *       {@link #ARENA_V1}, boots make zero block changes).</li>
 *   <li>{@link #isFightRunning()} — true from the arena transport until
 *       victory/wipe/reset; drives {@code DeathFlowHooks}' spectator respawn branch and
 *       the restart-recovery decision ("resume the fight" vs "re-arm from the gate").</li>
 *   <li>{@link #doorPos()} — the stamped altar dead-door controller (position, facing,
 *       dimension), kept so a restart mid-gate can re-arm the crossing and stale door
 *       blocks can always be cleaned up.</li>
 * </ul>
 */
public final class ArenaState extends SavedData {
    public static final String DATA_NAME = "eclipse_ferryman_arena";

    /** No arena stamped yet. */
    public static final int ARENA_NONE = 0;
    /** The C10 ship-turned-ring-arena + spectator ship. Terminal: boots change nothing. */
    public static final int ARENA_V1 = 1;

    private static final String TAG_VERSION = "arenaVersion";
    private static final String TAG_FIGHT = "fightRunning";
    private static final String TAG_DOOR_POS = "doorPos";
    private static final String TAG_DOOR_FACING = "doorFacing";
    private static final String TAG_DOOR_DIM = "doorDimension";

    private int arenaVersion = ARENA_NONE;
    private boolean fightRunning;
    @Nullable
    private BlockPos doorPos;
    private Direction doorFacing = Direction.EAST;
    @Nullable
    private ResourceKey<Level> doorDimension;

    public ArenaState() {}

    public static ArenaState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(ArenaState::new, ArenaState::load),
                DATA_NAME);
    }

    public static ArenaState load(CompoundTag tag, HolderLookup.Provider registries) {
        ArenaState state = new ArenaState();
        state.arenaVersion = tag.getInt(TAG_VERSION);
        state.fightRunning = tag.getBoolean(TAG_FIGHT);
        if (tag.contains(TAG_DOOR_POS)) {
            state.doorPos = NbtUtils.readBlockPos(tag, TAG_DOOR_POS).orElse(null);
            state.doorFacing = Direction.byName(tag.getString(TAG_DOOR_FACING));
            if (state.doorFacing == null || state.doorFacing.getAxis().isVertical()) {
                state.doorFacing = Direction.EAST;
            }
            ResourceLocation dim = ResourceLocation.tryParse(tag.getString(TAG_DOOR_DIM));
            state.doorDimension = dim != null ? ResourceKey.create(Registries.DIMENSION, dim) : null;
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_VERSION, this.arenaVersion);
        tag.putBoolean(TAG_FIGHT, this.fightRunning);
        if (this.doorPos != null && this.doorDimension != null) {
            tag.put(TAG_DOOR_POS, NbtUtils.writeBlockPos(this.doorPos));
            tag.putString(TAG_DOOR_FACING, this.doorFacing.getSerializedName());
            tag.putString(TAG_DOOR_DIM, this.doorDimension.location().toString());
        }
        return tag;
    }

    public int arenaVersion() {
        return this.arenaVersion;
    }

    public void setArenaVersion(int version) {
        if (this.arenaVersion != version) {
            this.arenaVersion = version;
            setDirty();
        }
    }

    public boolean isFightRunning() {
        return this.fightRunning;
    }

    public void setFightRunning(boolean running) {
        if (this.fightRunning != running) {
            this.fightRunning = running;
            setDirty();
        }
    }

    /** Stamped altar dead-door controller cell, or {@code null} while no door stands. */
    @Nullable
    public BlockPos doorPos() {
        return this.doorPos;
    }

    /** Front direction of the stamped door (meaningless while {@link #doorPos} is null). */
    public Direction doorFacing() {
        return this.doorFacing;
    }

    /** Dimension holding the stamped door, or {@code null} while no door stands. */
    @Nullable
    public ResourceKey<Level> doorDimension() {
        return this.doorDimension;
    }

    public void setDoor(@Nullable ResourceKey<Level> dimension, @Nullable BlockPos pos, Direction facing) {
        this.doorDimension = dimension;
        this.doorPos = pos != null ? pos.immutable() : null;
        this.doorFacing = facing;
        setDirty();
    }

    public void clearDoor() {
        setDoor(null, null, Direction.EAST);
    }
}
