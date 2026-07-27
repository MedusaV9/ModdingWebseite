package dev.projecteclipse.eclipse.woah.mansiondome;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * WOAH-01 §3.1 — the persisted mansion-dome record ({@code data/eclipse_mansion_dome.dat},
 * the {@code GlitchZoneState} overworld house pattern). ALL dome state lives here — the
 * probed geometry is persisted at arm time and never re-guessed, and a restart in the
 * middle of the destruction sequence resumes from {@link #collapseStartGameTime}.
 *
 * <p>All mutators {@code setDirty()}. The only transient sibling cache is the shard
 * choreography cursor in {@link DomeShatterFx} (reset on {@code ServerStoppedEvent} —
 * house rule).</p>
 */
public final class MansionDomeState extends SavedData {
    public static final String DATA_NAME = "eclipse_mansion_dome";

    /** Player melee hits the emitter takes before the shield falls. */
    public static final int MAX_HITS = 8;

    // Lifecycle (§3.1 status byte).
    public static final byte STATUS_UNARMED = 0;
    public static final byte STATUS_ACTIVE = 1;
    public static final byte STATUS_COLLAPSING = 2;
    public static final byte STATUS_DESTROYED = 3;

    private static final String TAG_STATUS = "status";
    private static final String TAG_DIMENSION = "dimension";
    private static final String TAG_CENTRE = "centre";
    private static final String TAG_SHELL_RADIUS = "shellRadius";
    private static final String TAG_GROUND_Y = "groundY";
    private static final String TAG_ROOF_Y = "roofY";
    private static final String TAG_DEVICE_POS = "devicePos";
    private static final String TAG_DEVICE_UUID = "deviceUuid";
    private static final String TAG_HITS = "hitsRemaining";
    private static final String TAG_ZONE_ID = "zoneId";
    private static final String TAG_COLLAPSE_START = "collapseStartGameTime";
    private static final String TAG_LOOT_DROPPED = "lootDropped";
    private static final String TAG_AFTERSHOCKS = "aftershocksRemaining";
    private static final String TAG_NEXT_AFTERSHOCK = "nextAftershockGameTime";
    private static final String TAG_TEST_DOME = "testDome";

    private byte status = STATUS_UNARMED;
    /** Dimension the dome lives in (the mansion's disc; test domes may sit elsewhere). */
    private ResourceKey<Level> dimension = Level.OVERWORLD;
    private BlockPos centre = BlockPos.ZERO;
    private float shellRadius;
    private int groundY;
    private int roofY;
    private BlockPos devicePos = BlockPos.ZERO;
    @Nullable
    private UUID deviceUuid;
    private int hitsRemaining = MAX_HITS;
    @Nullable
    private UUID zoneId;
    private long collapseStartGameTime;
    private boolean lootDropped;
    private int aftershocksRemaining;
    private long nextAftershockGameTime;
    /** {@code /dev dome arm here} marker: this dome was NOT armed at the real mansion. */
    private boolean testDome;

    public MansionDomeState() {}

    public static MansionDomeState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(MansionDomeState::new, MansionDomeState::load));
    }

    public static MansionDomeState load(CompoundTag tag, HolderLookup.Provider registries) {
        MansionDomeState state = new MansionDomeState();
        state.status = tag.getByte(TAG_STATUS);
        if (tag.contains(TAG_DIMENSION)) {
            state.dimension = ResourceKey.create(Registries.DIMENSION,
                    ResourceLocation.parse(tag.getString(TAG_DIMENSION)));
        }
        state.centre = BlockPos.of(tag.getLong(TAG_CENTRE));
        state.shellRadius = tag.getFloat(TAG_SHELL_RADIUS);
        state.groundY = tag.getInt(TAG_GROUND_Y);
        state.roofY = tag.getInt(TAG_ROOF_Y);
        state.devicePos = BlockPos.of(tag.getLong(TAG_DEVICE_POS));
        state.deviceUuid = tag.hasUUID(TAG_DEVICE_UUID) ? tag.getUUID(TAG_DEVICE_UUID) : null;
        state.hitsRemaining = tag.getInt(TAG_HITS);
        state.zoneId = tag.hasUUID(TAG_ZONE_ID) ? tag.getUUID(TAG_ZONE_ID) : null;
        state.collapseStartGameTime = tag.getLong(TAG_COLLAPSE_START);
        state.lootDropped = tag.getBoolean(TAG_LOOT_DROPPED);
        state.aftershocksRemaining = tag.getInt(TAG_AFTERSHOCKS);
        state.nextAftershockGameTime = tag.getLong(TAG_NEXT_AFTERSHOCK);
        state.testDome = tag.getBoolean(TAG_TEST_DOME);
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putByte(TAG_STATUS, this.status);
        tag.putString(TAG_DIMENSION, this.dimension.location().toString());
        tag.putLong(TAG_CENTRE, this.centre.asLong());
        tag.putFloat(TAG_SHELL_RADIUS, this.shellRadius);
        tag.putInt(TAG_GROUND_Y, this.groundY);
        tag.putInt(TAG_ROOF_Y, this.roofY);
        tag.putLong(TAG_DEVICE_POS, this.devicePos.asLong());
        if (this.deviceUuid != null) {
            tag.putUUID(TAG_DEVICE_UUID, this.deviceUuid);
        }
        tag.putInt(TAG_HITS, this.hitsRemaining);
        if (this.zoneId != null) {
            tag.putUUID(TAG_ZONE_ID, this.zoneId);
        }
        tag.putLong(TAG_COLLAPSE_START, this.collapseStartGameTime);
        tag.putBoolean(TAG_LOOT_DROPPED, this.lootDropped);
        tag.putInt(TAG_AFTERSHOCKS, this.aftershocksRemaining);
        tag.putLong(TAG_NEXT_AFTERSHOCK, this.nextAftershockGameTime);
        tag.putBoolean(TAG_TEST_DOME, this.testDome);
        return tag;
    }

    // ------------------------------------------------------------------ getters

    public byte status() {
        return this.status;
    }

    public ResourceKey<Level> dimension() {
        return this.dimension;
    }

    public BlockPos centre() {
        return this.centre;
    }

    public float shellRadius() {
        return this.shellRadius;
    }

    public int groundY() {
        return this.groundY;
    }

    public int roofY() {
        return this.roofY;
    }

    public BlockPos devicePos() {
        return this.devicePos;
    }

    @Nullable
    public UUID deviceUuid() {
        return this.deviceUuid;
    }

    public int hitsRemaining() {
        return this.hitsRemaining;
    }

    @Nullable
    public UUID zoneId() {
        return this.zoneId;
    }

    public long collapseStartGameTime() {
        return this.collapseStartGameTime;
    }

    public boolean lootDropped() {
        return this.lootDropped;
    }

    public int aftershocksRemaining() {
        return this.aftershocksRemaining;
    }

    public long nextAftershockGameTime() {
        return this.nextAftershockGameTime;
    }

    public boolean testDome() {
        return this.testDome;
    }

    /** Whether the shield (and therefore the build protection) is up. */
    public boolean shieldUp() {
        return this.status == STATUS_ACTIVE || this.status == STATUS_COLLAPSING;
    }

    // ------------------------------------------------------------------ mutators

    /** One-shot arm write: geometry + ACTIVE + full hits (the §2.2 probe results). */
    public void arm(ResourceKey<Level> dimension, BlockPos centre, float shellRadius,
            int groundY, int roofY, BlockPos devicePos, boolean testDome) {
        this.status = STATUS_ACTIVE;
        this.dimension = dimension;
        this.centre = centre;
        this.shellRadius = shellRadius;
        this.groundY = groundY;
        this.roofY = roofY;
        this.devicePos = devicePos;
        this.hitsRemaining = MAX_HITS;
        this.collapseStartGameTime = 0L;
        this.lootDropped = false;
        this.aftershocksRemaining = 0;
        this.nextAftershockGameTime = 0L;
        this.testDome = testDome;
        setDirty();
    }

    public void setStatus(byte status) {
        this.status = status;
        setDirty();
    }

    public void setDeviceUuid(@Nullable UUID deviceUuid) {
        this.deviceUuid = deviceUuid;
        setDirty();
    }

    /** Geometry heal (reset-time re-probe of a void-parked device stand). */
    public void setDevicePos(BlockPos devicePos) {
        this.devicePos = devicePos;
        setDirty();
    }

    public void setHitsRemaining(int hitsRemaining) {
        this.hitsRemaining = Math.max(0, Math.min(MAX_HITS, hitsRemaining));
        setDirty();
    }

    public void setZoneId(@Nullable UUID zoneId) {
        this.zoneId = zoneId;
        setDirty();
    }

    public void setCollapseStartGameTime(long gameTime) {
        this.collapseStartGameTime = gameTime;
        setDirty();
    }

    public void setLootDropped(boolean lootDropped) {
        this.lootDropped = lootDropped;
        setDirty();
    }

    public void setAftershocks(int remaining, long nextGameTime) {
        this.aftershocksRemaining = remaining;
        this.nextAftershockGameTime = nextGameTime;
        setDirty();
    }
}
