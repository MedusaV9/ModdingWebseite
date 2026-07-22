package dev.projecteclipse.eclipse.core.state;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Global persistent state of the Eclipse event, stored in the overworld's data storage
 * as {@code data/eclipse_world_state.dat}. Obtain via {@link #get(MinecraftServer)}.
 * All mutators mark the data dirty so it is written back to disk.
 */
public final class EclipseWorldState extends SavedData {
    public static final String DATA_NAME = "eclipse_world_state";

    // Night-event identifiers (W10). Stored as plain strings so the state class stays
    // decoupled from the spawner; anything else normalizes to NIGHT_EVENT_NONE on load.
    public static final String NIGHT_EVENT_NONE = "none";
    public static final String NIGHT_EVENT_PALE = "pale";
    public static final String NIGHT_EVENT_UMBRAL = "umbral";

    private static final String TAG_DAY = "day";
    private static final String TAG_ALTAR_LEVEL = "altarLevel";
    private static final String TAG_BORDER_SIZE = "borderSize";
    private static final String TAG_START_EVENT_DONE = "startEventDone";
    private static final String TAG_GHOST_SHIP_BUILT = "ghostShipBuilt";
    private static final String TAG_BANNED = "banned";
    private static final String TAG_MILESTONE_PROGRESS = "milestoneProgress";
    private static final String TAG_FORCE_VOICE_MUTED = "forceVoiceMuted";
    private static final String TAG_OAR_ENTITIES = "oarEntities";
    private static final String TAG_DECKHAND_ENTITIES = "deckhandEntities";
    private static final String TAG_NIGHT_EVENT = "activeNightEvent";
    private static final String TAG_NIGHT_EVENT_DAY = "nightEventDay";
    private static final String TAG_FIRST_PALE_NIGHT_DONE = "firstPaleNightDone";
    private static final String TAG_WORLD_STAGE_OVERWORLD = "worldStageOverworld";
    private static final String TAG_WORLD_STAGE_NETHER = "worldStageNether";
    private static final String TAG_GROWTH_DIMENSION = "growthDimension";
    private static final String TAG_GROWTH_FROM_STAGE = "growthFromStage";
    private static final String TAG_GROWTH_CURSOR = "growthCursor";
    private static final String TAG_SANCTUM_BUILT = "sanctumBuilt";
    private static final String TAG_SANCTUM_ALTAR_POS = "sanctumAltarPos";
    private static final String TAG_DISABLED_CUTSCENES = "disabledCutscenes";
    private static final String TAG_BORDER_CENTER_X = "borderCenterX";
    private static final String TAG_BORDER_CENTER_Z = "borderCenterZ";
    private static final String TAG_SOFT_BORDER_RADIUS_OVERWORLD = "softBorderRadiusOverworld";
    private static final String TAG_SOFT_BORDER_RADIUS_NETHER = "softBorderRadiusNether";
    private static final String TAG_BORDER_FX_RANGE = "borderFxRange";
    private static final String TAG_HERALD_DEFEATED = "heraldDefeated";
    private static final String TAG_FERRYMAN_DEFEATED = "ferrymanDefeated";
    private static final String TAG_SHARD_POOL = "shardPool";
    private static final String TAG_GRAVE_POSITIONS = "gravePositions";
    private static final String TAG_LAST_LOADED_STAGE_OVERWORLD = "lastLoadedStageOverworld";
    private static final String TAG_LAST_LOADED_STAGE_NETHER = "lastLoadedStageNether";

    private int day = 1;
    private int altarLevel = 0;
    private double borderSize = 1000.0D;
    private boolean startEventDone = false;
    private boolean ghostShipBuilt = false;
    private int worldStageOverworld = 0;
    private int worldStageNether = 0;
    private String growthDimension = "";
    private int growthFromStage = 0;
    private long growthCursor = 0L;
    private boolean sanctumBuilt = false;
    private long sanctumAltarPos = 0L;
    private double borderCenterX = 0.5D;
    private double borderCenterZ = 0.5D;
    private double softBorderRadiusOverworld = -1.0D;
    private double softBorderRadiusNether = -1.0D;
    private double borderFxRange = -1.0D;
    private final Set<UUID> banned = new HashSet<>();
    private final Map<String, Long> milestoneProgress = new HashMap<>();
    private final Set<UUID> forceVoiceMuted = new HashSet<>();
    private final List<UUID> oarEntities = new ArrayList<>();
    private final List<UUID> deckhandEntities = new ArrayList<>();
    private String activeNightEvent = NIGHT_EVENT_NONE;
    private int nightEventDay = 0;
    private boolean firstPaleNightDone = false;
    private boolean heraldDefeated = false;
    private boolean ferrymanDefeated = false;
    private int shardPool = 0;
    private int lastLoadedStageOverworld = -1;
    private int lastLoadedStageNether = -1;
    private final Map<UUID, List<GlobalPos>> gravePositions = new HashMap<>();
    private final Set<String> disabledCutscenes = new HashSet<>();

    public EclipseWorldState() {}

    public static EclipseWorldState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(EclipseWorldState::new, EclipseWorldState::load),
                DATA_NAME);
    }

    public static EclipseWorldState load(CompoundTag tag, HolderLookup.Provider registries) {
        EclipseWorldState state = new EclipseWorldState();
        state.day = tag.contains(TAG_DAY) ? tag.getInt(TAG_DAY) : 1;
        state.altarLevel = tag.getInt(TAG_ALTAR_LEVEL);
        state.borderSize = tag.contains(TAG_BORDER_SIZE) ? tag.getDouble(TAG_BORDER_SIZE) : 1000.0D;
        state.startEventDone = tag.getBoolean(TAG_START_EVENT_DONE);
        state.ghostShipBuilt = tag.getBoolean(TAG_GHOST_SHIP_BUILT);
        // World stage fields default to 0 / "no cursor" so pre-v2 saves keep loading.
        state.worldStageOverworld = tag.getInt(TAG_WORLD_STAGE_OVERWORLD);
        state.worldStageNether = tag.getInt(TAG_WORLD_STAGE_NETHER);
        state.growthDimension = tag.getString(TAG_GROWTH_DIMENSION);
        state.growthFromStage = tag.getInt(TAG_GROWTH_FROM_STAGE);
        state.growthCursor = tag.getLong(TAG_GROWTH_CURSOR);
        // Sanctum fields default to "not built" so pre-W5 saves keep loading (the
        // sanctum then builds on their next start).
        state.sanctumBuilt = tag.getBoolean(TAG_SANCTUM_BUILT);
        state.sanctumAltarPos = tag.getLong(TAG_SANCTUM_ALTAR_POS);
        // Soft border fields default to "unset" (-1): SoftBorder derives the radius from the
        // committed stage and re-pins the center to spawn on server start (pre-W7 saves).
        state.borderCenterX = tag.contains(TAG_BORDER_CENTER_X) ? tag.getDouble(TAG_BORDER_CENTER_X) : 0.5D;
        state.borderCenterZ = tag.contains(TAG_BORDER_CENTER_Z) ? tag.getDouble(TAG_BORDER_CENTER_Z) : 0.5D;
        state.softBorderRadiusOverworld = tag.contains(TAG_SOFT_BORDER_RADIUS_OVERWORLD)
                ? tag.getDouble(TAG_SOFT_BORDER_RADIUS_OVERWORLD) : -1.0D;
        state.softBorderRadiusNether = tag.contains(TAG_SOFT_BORDER_RADIUS_NETHER)
                ? tag.getDouble(TAG_SOFT_BORDER_RADIUS_NETHER) : -1.0D;
        state.borderFxRange = tag.contains(TAG_BORDER_FX_RANGE) ? tag.getDouble(TAG_BORDER_FX_RANGE) : -1.0D;
        for (Tag entry : tag.getList(TAG_OAR_ENTITIES, Tag.TAG_INT_ARRAY)) {
            state.oarEntities.add(NbtUtils.loadUUID(entry));
        }
        for (Tag entry : tag.getList(TAG_DECKHAND_ENTITIES, Tag.TAG_INT_ARRAY)) {
            state.deckhandEntities.add(NbtUtils.loadUUID(entry));
        }
        state.activeNightEvent = normalizeNightEvent(tag.getString(TAG_NIGHT_EVENT));
        state.nightEventDay = tag.getInt(TAG_NIGHT_EVENT_DAY);
        state.firstPaleNightDone = tag.getBoolean(TAG_FIRST_PALE_NIGHT_DONE);
        // Defaults to false so pre-W11 saves keep loading (boss not fought yet).
        state.heraldDefeated = tag.getBoolean(TAG_HERALD_DEFEATED);
        // Defaults to false so pre-W12 saves keep loading (finale not fought yet).
        state.ferrymanDefeated = tag.getBoolean(TAG_FERRYMAN_DEFEATED);
        // W13 economy fields default to 0/empty so pre-W13 saves keep loading.
        state.shardPool = tag.getInt(TAG_SHARD_POOL);
        // W14 stage-snapshot fields default to -1 ("nothing loaded yet") on pre-W14 saves.
        state.lastLoadedStageOverworld = tag.contains(TAG_LAST_LOADED_STAGE_OVERWORLD)
                ? tag.getInt(TAG_LAST_LOADED_STAGE_OVERWORLD) : -1;
        state.lastLoadedStageNether = tag.contains(TAG_LAST_LOADED_STAGE_NETHER)
                ? tag.getInt(TAG_LAST_LOADED_STAGE_NETHER) : -1;
        for (Tag entry : tag.getList(TAG_GRAVE_POSITIONS, Tag.TAG_COMPOUND)) {
            CompoundTag grave = (CompoundTag) entry;
            if (!grave.hasUUID("owner")) {
                continue;
            }
            GlobalPos pos = GlobalPos.of(
                    ResourceKey.create(Registries.DIMENSION, ResourceLocation.parse(grave.getString("dim"))),
                    BlockPos.of(grave.getLong("pos")));
            state.gravePositions.computeIfAbsent(grave.getUUID("owner"), owner -> new ArrayList<>()).add(pos);
        }
        for (Tag entry : tag.getList(TAG_BANNED, Tag.TAG_INT_ARRAY)) {
            state.banned.add(NbtUtils.loadUUID(entry));
        }
        CompoundTag progress = tag.getCompound(TAG_MILESTONE_PROGRESS);
        for (String key : progress.getAllKeys()) {
            state.milestoneProgress.put(key, progress.getLong(key));
        }
        for (Tag entry : tag.getList(TAG_FORCE_VOICE_MUTED, Tag.TAG_INT_ARRAY)) {
            state.forceVoiceMuted.add(NbtUtils.loadUUID(entry));
        }
        for (Tag entry : tag.getList(TAG_DISABLED_CUTSCENES, Tag.TAG_STRING)) {
            state.disabledCutscenes.add(entry.getAsString());
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt(TAG_DAY, this.day);
        tag.putInt(TAG_ALTAR_LEVEL, this.altarLevel);
        tag.putDouble(TAG_BORDER_SIZE, this.borderSize);
        tag.putBoolean(TAG_START_EVENT_DONE, this.startEventDone);
        tag.putBoolean(TAG_GHOST_SHIP_BUILT, this.ghostShipBuilt);
        tag.putInt(TAG_WORLD_STAGE_OVERWORLD, this.worldStageOverworld);
        tag.putInt(TAG_WORLD_STAGE_NETHER, this.worldStageNether);
        tag.putString(TAG_GROWTH_DIMENSION, this.growthDimension);
        tag.putInt(TAG_GROWTH_FROM_STAGE, this.growthFromStage);
        tag.putLong(TAG_GROWTH_CURSOR, this.growthCursor);
        tag.putBoolean(TAG_SANCTUM_BUILT, this.sanctumBuilt);
        tag.putLong(TAG_SANCTUM_ALTAR_POS, this.sanctumAltarPos);
        tag.putDouble(TAG_BORDER_CENTER_X, this.borderCenterX);
        tag.putDouble(TAG_BORDER_CENTER_Z, this.borderCenterZ);
        tag.putDouble(TAG_SOFT_BORDER_RADIUS_OVERWORLD, this.softBorderRadiusOverworld);
        tag.putDouble(TAG_SOFT_BORDER_RADIUS_NETHER, this.softBorderRadiusNether);
        tag.putDouble(TAG_BORDER_FX_RANGE, this.borderFxRange);

        ListTag oarList = new ListTag();
        for (UUID uuid : this.oarEntities) {
            oarList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_OAR_ENTITIES, oarList);

        ListTag deckhandList = new ListTag();
        for (UUID uuid : this.deckhandEntities) {
            deckhandList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_DECKHAND_ENTITIES, deckhandList);

        tag.putString(TAG_NIGHT_EVENT, this.activeNightEvent);
        tag.putInt(TAG_NIGHT_EVENT_DAY, this.nightEventDay);
        tag.putBoolean(TAG_FIRST_PALE_NIGHT_DONE, this.firstPaleNightDone);
        tag.putBoolean(TAG_HERALD_DEFEATED, this.heraldDefeated);
        tag.putBoolean(TAG_FERRYMAN_DEFEATED, this.ferrymanDefeated);
        tag.putInt(TAG_SHARD_POOL, this.shardPool);
        tag.putInt(TAG_LAST_LOADED_STAGE_OVERWORLD, this.lastLoadedStageOverworld);
        tag.putInt(TAG_LAST_LOADED_STAGE_NETHER, this.lastLoadedStageNether);

        ListTag graveList = new ListTag();
        for (Map.Entry<UUID, List<GlobalPos>> entry : this.gravePositions.entrySet()) {
            for (GlobalPos pos : entry.getValue()) {
                CompoundTag grave = new CompoundTag();
                grave.putUUID("owner", entry.getKey());
                grave.putString("dim", pos.dimension().location().toString());
                grave.putLong("pos", pos.pos().asLong());
                graveList.add(grave);
            }
        }
        tag.put(TAG_GRAVE_POSITIONS, graveList);

        ListTag bannedList = new ListTag();
        for (UUID uuid : this.banned) {
            bannedList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_BANNED, bannedList);

        CompoundTag progress = new CompoundTag();
        for (Map.Entry<String, Long> entry : this.milestoneProgress.entrySet()) {
            progress.putLong(entry.getKey(), entry.getValue());
        }
        tag.put(TAG_MILESTONE_PROGRESS, progress);

        ListTag mutedList = new ListTag();
        for (UUID uuid : this.forceVoiceMuted) {
            mutedList.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_FORCE_VOICE_MUTED, mutedList);

        ListTag disabledCutsceneList = new ListTag();
        for (String id : this.disabledCutscenes) {
            disabledCutsceneList.add(StringTag.valueOf(id));
        }
        tag.put(TAG_DISABLED_CUTSCENES, disabledCutsceneList);
        return tag;
    }

    // --- day ---

    public int getDay() {
        return this.day;
    }

    public void setDay(int day) {
        this.day = day;
        setDirty();
    }

    // --- altar level ---

    public int getAltarLevel() {
        return this.altarLevel;
    }

    public void setAltarLevel(int altarLevel) {
        this.altarLevel = altarLevel;
        setDirty();
    }

    // --- border ---

    /**
     * v1 field, since W7 repointed: the VANILLA FAILSAFE border diameter (soft ring + 48,
     * doubled). Kept in sync by {@code BorderController.applyFailsafe}; the authoritative
     * playable boundary is the soft ring ({@link #getSoftBorderRadius}).
     */
    public double getBorderSize() {
        return this.borderSize;
    }

    public void setBorderSize(double borderSize) {
        this.borderSize = borderSize;
        setDirty();
    }

    // --- soft border ring (worker 7) ---

    /** Ring center X (the world spawn; re-pinned by {@code SoftBorder} every server start). */
    public double getBorderCenterX() {
        return this.borderCenterX;
    }

    /** Ring center Z (the world spawn; re-pinned by {@code SoftBorder} every server start). */
    public double getBorderCenterZ() {
        return this.borderCenterZ;
    }

    public void setBorderCenter(double x, double z) {
        this.borderCenterX = x;
        this.borderCenterZ = z;
        setDirty();
    }

    /**
     * Soft ring radius of a disc dimension. {@code -1} = unset (derive from the committed
     * stage at startup); {@code 0} = ring inactive (nether before its first disc stage).
     */
    public double getSoftBorderRadius(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? this.softBorderRadiusNether : this.softBorderRadiusOverworld;
    }

    public void setSoftBorderRadius(DiscProfile profile, double radius) {
        if (profile == DiscProfile.NETHER) {
            this.softBorderRadiusNether = radius;
        } else {
            this.softBorderRadiusOverworld = radius;
        }
        setDirty();
    }

    /** Border FX visibility band override in blocks; {@code <= 0} = use general.json {@code borderFxRange}. */
    public double getBorderFxRange() {
        return this.borderFxRange;
    }

    public void setBorderFxRange(double blocks) {
        this.borderFxRange = blocks;
        setDirty();
    }

    // --- world stage ---

    /** Committed world stage of the given disc dimension (default 0 = pre-intro geometry). */
    public int getWorldStage(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? this.worldStageNether : this.worldStageOverworld;
    }

    /**
     * Persists a committed world stage. Only {@code WorldStageService.setStage} should call
     * this — it also has to publish the stage into the {@code WorldStageAccess} chunkgen seam
     * and kick the terrain sweep.
     */
    public void setWorldStage(DiscProfile profile, int stage) {
        int clamped = Math.max(0, stage);
        if (profile == DiscProfile.NETHER) {
            this.worldStageNether = clamped;
        } else {
            this.worldStageOverworld = clamped;
        }
        setDirty();
    }

    // --- ring growth cursor (restart-resume of a mid-animation sweep) ---

    /** Whether a ring-growth sweep was mid-flight when the world last saved. */
    public boolean hasGrowthCursor() {
        return !this.growthDimension.isEmpty();
    }

    /** Disc profile name ({@code "overworld"} / {@code "nether"}) of the interrupted sweep, or {@code ""}. */
    public String getGrowthDimension() {
        return this.growthDimension;
    }

    /** Stage the interrupted sweep started from (its target is the committed world stage). */
    public int getGrowthFromStage() {
        return this.growthFromStage;
    }

    /** Index of the next unwritten column in the sweep's deterministic column ordering. */
    public long getGrowthCursor() {
        return this.growthCursor;
    }

    /** Saves the sweep position; {@code RingGrowthService} calls this every ~100 columns. */
    public void setGrowthCursor(String dimensionName, int fromStage, long columnIndex) {
        this.growthDimension = dimensionName;
        this.growthFromStage = fromStage;
        this.growthCursor = columnIndex;
        setDirty();
    }

    /** Clears the cursor once a sweep completes (or is cancelled by a newer stage commit). */
    public void clearGrowthCursor() {
        this.growthDimension = "";
        this.growthFromStage = 0;
        this.growthCursor = 0L;
        setDirty();
    }

    // --- stage snapshots (W14 devtools) ---

    /**
     * The stage number whose annulus snapshot ({@code <world>/eclipse/stages/<n>.bin}) was
     * last applied to the dimension by {@code devtools.StageIO}, or {@code -1} when no
     * snapshot has been loaded yet. {@code /eclipse stage revert} re-applies this snapshot.
     */
    public int getLastLoadedStage(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? this.lastLoadedStageNether : this.lastLoadedStageOverworld;
    }

    public void setLastLoadedStage(DiscProfile profile, int stage) {
        if (profile == DiscProfile.NETHER) {
            this.lastLoadedStageNether = stage;
        } else {
            this.lastLoadedStageOverworld = stage;
        }
        setDirty();
    }

    // --- altar sanctum (worker 5) ---

    /** Whether the altar sanctum has been built at spawn (build-once guard). */
    public boolean isSanctumBuilt() {
        return this.sanctumBuilt;
    }

    /**
     * The altar block position the sanctum was centered on, or {@code null} while the
     * sanctum has not been built yet. Protection and the sundial derive their geometry
     * from this position.
     */
    @Nullable
    public BlockPos getSanctumAltarPos() {
        return this.sanctumBuilt ? BlockPos.of(this.sanctumAltarPos) : null;
    }

    /** Marks the sanctum built around the given altar position. */
    public void setSanctumBuilt(BlockPos altarPos) {
        this.sanctumBuilt = true;
        this.sanctumAltarPos = altarPos.asLong();
        setDirty();
    }

    // --- start event ---

    public boolean isStartEventDone() {
        return this.startEventDone;
    }

    public void setStartEventDone(boolean startEventDone) {
        this.startEventDone = startEventDone;
        setDirty();
    }

    // --- ghost ship (limbo) ---

    /** Whether the procedural ghost ship has already been built in the Limbo dimension. */
    public boolean isGhostShipBuilt() {
        return this.ghostShipBuilt;
    }

    public void setGhostShipBuilt(boolean ghostShipBuilt) {
        this.ghostShipBuilt = ghostShipBuilt;
        setDirty();
    }

    /** UUIDs of the persistent block-display oar entities on the ghost ship (ordered: port bow → stern, then starboard). */
    public List<UUID> getOarEntities() {
        return Collections.unmodifiableList(this.oarEntities);
    }

    public void setOarEntities(List<UUID> oarEntityIds) {
        this.oarEntities.clear();
        this.oarEntities.addAll(oarEntityIds);
        setDirty();
    }

    /** UUIDs of the persistent Deckhand crew mobs seated at the ghost-ship oar benches (W10). */
    public List<UUID> getDeckhandEntities() {
        return Collections.unmodifiableList(this.deckhandEntities);
    }

    public void setDeckhandEntities(List<UUID> deckhandEntityIds) {
        this.deckhandEntities.clear();
        this.deckhandEntities.addAll(deckhandEntityIds);
        setDirty();
    }

    // --- night events (W10) ---

    /**
     * The active night event: {@link #NIGHT_EVENT_NONE}, {@link #NIGHT_EVENT_PALE} or
     * {@link #NIGHT_EVENT_UMBRAL}. Scheduled by {@code entity.EclipseSpawner} on nightfall,
     * cleared at dawn; {@code /eclipse event set} overrides it for testing.
     */
    public String getActiveNightEvent() {
        return this.activeNightEvent;
    }

    /** The eclipse day stamped when the current night event was scheduled (0 = never). */
    public int getNightEventDay() {
        return this.nightEventDay;
    }

    public void setActiveNightEvent(String event, int dayStamp) {
        this.activeNightEvent = normalizeNightEvent(event);
        this.nightEventDay = dayStamp;
        setDirty();
    }

    /** Whether the guaranteed first Pale Night (day 4+) has already happened. */
    public boolean isFirstPaleNightDone() {
        return this.firstPaleNightDone;
    }

    public void setFirstPaleNightDone(boolean done) {
        this.firstPaleNightDone = done;
        setDirty();
    }

    private static String normalizeNightEvent(String event) {
        return NIGHT_EVENT_PALE.equals(event) || NIGHT_EVENT_UMBRAL.equals(event)
                ? event : NIGHT_EVENT_NONE;
    }

    // --- herald boss (W11) ---

    /**
     * Whether the day-7 Herald has been defeated. {@code UnlockState} unions in the
     * derived key {@code herald_slain} while this is set (the boss's on-kill unlock arc;
     * W13 finalizes which config unlock is gated behind it).
     */
    public boolean isHeraldDefeated() {
        return this.heraldDefeated;
    }

    public void setHeraldDefeated(boolean defeated) {
        this.heraldDefeated = defeated;
        setDirty();
    }

    // --- ferryman boss (W12) ---

    /**
     * Whether the day-14 Ferryman finale has been won. Set by the boss's death path right
     * before the mass-revive ending fires; blocks the finale ritual from re-running.
     */
    public boolean isFerrymanDefeated() {
        return this.ferrymanDefeated;
    }

    public void setFerrymanDefeated(boolean defeated) {
        this.ferrymanDefeated = defeated;
        setDirty();
    }

    // --- umbral shard pool (W13 economy) ---

    /**
     * The TEAM shard pool: every umbral shard sneak-deposited at the altar also feeds this
     * counter (in addition to the depositor's personal {@code eclipse:shards} balance).
     * Pooled rewards such as the Supply Beacon draw from here ({@code economy.ShardEconomy}).
     */
    public int getShardPool() {
        return this.shardPool;
    }

    /** Adds {@code delta} (may be negative) to the shard pool, clamped to {@code >= 0}; returns the new value. */
    public int addShardPool(int delta) {
        this.shardPool = Math.max(0, this.shardPool + delta);
        setDirty();
        return this.shardPool;
    }

    public void setShardPool(int value) {
        this.shardPool = Math.max(0, value);
        setDirty();
    }

    // --- grave positions (W13 economy: Grave Dowser) ---

    /**
     * All known grave positions of the given owner, newest last. Appended by
     * {@code lives.LifecycleEvents} when a death grave is placed and pruned by
     * {@code lives.GraveBlock#onRemove} on every removal path (looted, scattered, mined,
     * exploded). Read by the Grave Dowser's {@code inventoryTick}.
     */
    public List<GlobalPos> getGravePositions(UUID owner) {
        List<GlobalPos> graves = this.gravePositions.get(owner);
        return graves == null ? List.of() : Collections.unmodifiableList(graves);
    }

    public void addGravePosition(UUID owner, GlobalPos pos) {
        this.gravePositions.computeIfAbsent(owner, key -> new ArrayList<>()).add(pos);
        setDirty();
    }

    /** Removes a tracked grave position; unknown positions are ignored (legacy graves predating W13). */
    public void removeGravePosition(UUID owner, GlobalPos pos) {
        List<GlobalPos> graves = this.gravePositions.get(owner);
        if (graves != null && graves.remove(pos)) {
            if (graves.isEmpty()) {
                this.gravePositions.remove(owner);
            }
            setDirty();
        }
    }

    // --- banned ---

    public Set<UUID> getBanned() {
        return Collections.unmodifiableSet(this.banned);
    }

    public boolean isBanned(UUID playerId) {
        return this.banned.contains(playerId);
    }

    public void addBanned(UUID playerId) {
        if (this.banned.add(playerId)) {
            setDirty();
        }
    }

    public void removeBanned(UUID playerId) {
        if (this.banned.remove(playerId)) {
            setDirty();
        }
    }

    // --- milestone progress ---

    public Map<String, Long> getMilestoneProgress() {
        return Collections.unmodifiableMap(this.milestoneProgress);
    }

    public long getMilestoneProgress(String key) {
        return this.milestoneProgress.getOrDefault(key, 0L);
    }

    public void setMilestoneProgress(String key, long value) {
        this.milestoneProgress.put(key, value);
        setDirty();
    }

    /** Adds {@code delta} to the progress stored under {@code key} and returns the new value. */
    public long addMilestoneProgress(String key, long delta) {
        long updated = getMilestoneProgress(key) + delta;
        this.milestoneProgress.put(key, updated);
        setDirty();
        return updated;
    }

    // --- disabled cutscenes (runtime toggle behind /eclipse cutscene enable|disable) ---

    /** Path ids whose playback is disabled in this world (they complete instantly instead). */
    public Set<String> getDisabledCutscenes() {
        return Collections.unmodifiableSet(this.disabledCutscenes);
    }

    public boolean isCutsceneDisabled(String pathId) {
        return this.disabledCutscenes.contains(pathId);
    }

    /** Adds/removes a path id from the disabled set; returns whether anything changed. */
    public boolean setCutsceneDisabled(String pathId, boolean disabled) {
        boolean changed = disabled ? this.disabledCutscenes.add(pathId) : this.disabledCutscenes.remove(pathId);
        if (changed) {
            setDirty();
        }
        return changed;
    }

    // --- force voice muted (used by the voice worker) ---

    public Set<UUID> getForceVoiceMuted() {
        return Collections.unmodifiableSet(this.forceVoiceMuted);
    }

    public boolean isForceVoiceMuted(UUID playerId) {
        return this.forceVoiceMuted.contains(playerId);
    }

    public void addForceVoiceMuted(UUID playerId) {
        if (this.forceVoiceMuted.add(playerId)) {
            setDirty();
        }
    }

    public void removeForceVoiceMuted(UUID playerId) {
        if (this.forceVoiceMuted.remove(playerId)) {
            setDirty();
        }
    }
}
