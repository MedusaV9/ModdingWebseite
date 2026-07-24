package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.serialization.DataResult;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.NonNullList;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtOps;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.RegistryOps;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save state machine of the portal minigame events (the {@code XboxEventState}
 * pattern), SavedData {@code eclipse_minigame_event} in overworld storage.
 * {@code IDLE → OPEN → RUNNING → CLOSING → IDLE}; {@link #openCount()} increments per
 * {@link #beginInstance} and doubles as the deterministic course seed, so a crash
 * mid-build can always re-derive (and re-clear) the exact same layout.
 *
 * <p><b>Tickets</b> are the safety core: one {@link Ticket} per entered player holds the
 * return anchor, the previous game mode, health/food and the FULL inventory (main, armor,
 * offhand — encoded slot-by-slot with {@code ItemStack.OPTIONAL_CODEC} at capture time,
 * stored as opaque NBT). Tickets survive server restarts AND new instances — they are only
 * removed after a successful restore, so a player who logged out mid-event gets rescued at
 * next login no matter what happened in between.</p>
 */
public final class MinigameState extends SavedData {
    public static final String DATA_NAME = "eclipse_minigame_event";

    /** Event lifecycle phase; {@code CLOSING} survives a crash and resumes on boot. */
    public enum Phase {
        IDLE, OPEN, RUNNING, CLOSING;

        static Phase byName(String name) {
            for (Phase phase : values()) {
                if (phase.name().equalsIgnoreCase(name)) {
                    return phase;
                }
            }
            return IDLE;
        }
    }

    /** Where a participant entered from — restored verbatim on any exit path. */
    public record ReturnAnchor(ResourceKey<Level> dimension, double x, double y, double z,
            float yaw, float pitch) {}

    /**
     * Everything needed to make a participant whole again on ANY exit path: return
     * anchor, previous game mode, health/food and the opaque-NBT inventory snapshot
     * (lists of per-slot tags, encoded at capture time).
     */
    public record Ticket(ReturnAnchor anchor, int gameModeId, float health, int foodLevel,
            float saturation, ListTag main, ListTag armor, ListTag offhand) {}

    private static final String TAG_PHASE = "phase";
    private static final String TAG_GAME_ID = "gameId";
    private static final String TAG_ENDS_AT = "endsAtEpochMillis";
    private static final String TAG_OPEN_COUNT = "openCount";
    private static final String TAG_ROUND_ENDS_AT = "roundEndsAtEpochMillis";
    private static final String TAG_PORTAL = "portal";
    private static final String TAG_PARTICIPANTS = "participants";
    private static final String TAG_TICKETS = "tickets";
    private static final String TAG_REWARDED = "rewardedParticipation";
    private static final String TAG_KILLS = "kills";
    private static final String TAG_RACE_PROGRESS = "raceProgress";
    private static final String TAG_RACE_LAP_START = "raceLapStart";
    private static final String TAG_RACE_FINISHERS = "raceFinishers";
    private static final String TAG_BEST_LAP = "bestLapMillis";
    private static final String TAG_BUILT_SEED_ARENA = "builtSeedArena";
    private static final String TAG_BUILT_SEED_RACE = "builtSeedRace";

    private Phase phase = Phase.IDLE;
    private String gameId = "";
    private long endsAtEpochMillis;
    private int openCount;
    private long roundEndsAtEpochMillis;
    @Nullable
    private ResourceKey<Level> portalDimension;
    @Nullable
    private BlockPos portalPos;
    private final Set<UUID> participants = new HashSet<>();
    private final Map<UUID, Ticket> tickets = new HashMap<>();
    private final Set<UUID> rewardedParticipation = new HashSet<>();
    private final Map<UUID, Integer> kills = new HashMap<>();
    private final Map<UUID, Integer> raceProgress = new HashMap<>();
    private final Map<UUID, Long> raceLapStart = new HashMap<>();
    private final List<UUID> raceFinishers = new ArrayList<>();
    private long bestLapMillis;
    /** Last generated course seed per dimension; {@code -1} = never built. */
    private int builtSeedArena = -1;
    private int builtSeedRace = -1;

    public MinigameState() {}

    public static MinigameState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(MinigameState::new, MinigameState::load),
                DATA_NAME);
    }

    // ------------------------------------------------------------------ phase & core fields

    public Phase phase() {
        return phase;
    }

    public void setPhase(Phase newPhase) {
        this.phase = newPhase;
        setDirty();
    }

    public boolean isActive() {
        return phase == Phase.OPEN || phase == Phase.RUNNING;
    }

    /** Active (or last) game id ({@code arena}/{@code race}); empty when never started. */
    public String gameId() {
        return gameId;
    }

    public long endsAtEpochMillis() {
        return endsAtEpochMillis;
    }

    /** Clamped to {@code >= nowMillis} by callers (xbox §2.13.3 convention). */
    public void setEndsAtEpochMillis(long endsAt) {
        this.endsAtEpochMillis = endsAt;
        setDirty();
    }

    /** Instance counter — also the deterministic course seed of the current instance. */
    public int openCount() {
        return openCount;
    }

    /** Arena round deadline (epoch millis); {@code 0} while no round runs. */
    public long roundEndsAtEpochMillis() {
        return roundEndsAtEpochMillis;
    }

    public void setRoundEndsAtEpochMillis(long endsAt) {
        this.roundEndsAtEpochMillis = endsAt;
        setDirty();
    }

    /**
     * Starts a fresh event instance: bumps {@link #openCount()}, clears all per-instance
     * scoring/reward bookkeeping and records game + end time. Tickets are deliberately
     * NOT cleared — an unrestored ticket means a player still owed their inventory.
     */
    public void beginInstance(String newGameId, long endsAt) {
        this.openCount++;
        this.gameId = newGameId;
        this.endsAtEpochMillis = endsAt;
        this.roundEndsAtEpochMillis = 0L;
        this.participants.clear();
        this.rewardedParticipation.clear();
        this.kills.clear();
        this.raceProgress.clear();
        this.raceLapStart.clear();
        this.raceFinishers.clear();
        this.bestLapMillis = 0L;
        this.phase = Phase.OPEN;
        setDirty();
    }

    // ------------------------------------------------------------------ portal

    @Nullable
    public ResourceKey<Level> portalDimension() {
        return portalDimension;
    }

    @Nullable
    public BlockPos portalPos() {
        return portalPos;
    }

    public void setPortal(@Nullable ResourceKey<Level> dimension, @Nullable BlockPos pos) {
        this.portalDimension = dimension;
        this.portalPos = pos == null ? null : pos.immutable();
        setDirty();
    }

    // ------------------------------------------------------------------ participants & rewards

    public boolean addParticipant(UUID uuid) {
        boolean added = participants.add(uuid);
        if (added) {
            setDirty();
        }
        return added;
    }

    public boolean isParticipant(UUID uuid) {
        return participants.contains(uuid);
    }

    public Set<UUID> participantsSnapshot() {
        return Collections.unmodifiableSet(new HashSet<>(participants));
    }

    /**
     * Persists the once-per-instance participation payout BEFORE it is granted.
     *
     * @return true only for the first attempt per player in this event instance
     */
    public boolean markParticipationRewarded(UUID uuid) {
        boolean added = rewardedParticipation.add(uuid);
        if (added) {
            setDirty();
        }
        return added;
    }

    // ------------------------------------------------------------------ arena scoring

    /** Increments the killer's round score and returns the new value. */
    public int addKill(UUID uuid) {
        int newValue = kills.merge(uuid, 1, Integer::sum);
        setDirty();
        return newValue;
    }

    public int killsOf(UUID uuid) {
        return kills.getOrDefault(uuid, 0);
    }

    public Map<UUID, Integer> killsSnapshot() {
        return Collections.unmodifiableMap(new HashMap<>(kills));
    }

    /** Round rollover: wipes the scoreboard (podium is announced by the caller first). */
    public void clearKills() {
        if (!kills.isEmpty()) {
            kills.clear();
            setDirty();
        }
    }

    // ------------------------------------------------------------------ race bookkeeping

    /** Index of the NEXT checkpoint the player must pass ({@code 0} = start ring). */
    public int raceProgress(UUID uuid) {
        return raceProgress.getOrDefault(uuid, 0);
    }

    public void setRaceProgress(UUID uuid, int nextCheckpoint) {
        raceProgress.put(uuid, nextCheckpoint);
        setDirty();
    }

    /** Epoch millis the player's current lap started; {@code 0} = lap not armed. */
    public long raceLapStart(UUID uuid) {
        return raceLapStart.getOrDefault(uuid, 0L);
    }

    public void setRaceLapStart(UUID uuid, long epochMillis) {
        raceLapStart.put(uuid, epochMillis);
        setDirty();
    }

    /** Records a finisher (once); returns 1-based finish position, or 0 when already listed. */
    public int addRaceFinisher(UUID uuid) {
        if (raceFinishers.contains(uuid)) {
            return 0;
        }
        raceFinishers.add(uuid);
        setDirty();
        return raceFinishers.size();
    }

    public List<UUID> raceFinishersSnapshot() {
        return List.copyOf(raceFinishers);
    }

    /** Best lap millis of this instance; {@code 0} = no lap completed yet. */
    public long bestLapMillis() {
        return bestLapMillis;
    }

    /** Records {@code lapMillis} if it beats the instance best; returns true on a new record. */
    public boolean offerBestLap(long lapMillis) {
        if (lapMillis > 0L && (bestLapMillis == 0L || lapMillis < bestLapMillis)) {
            bestLapMillis = lapMillis;
            setDirty();
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ course build seeds

    /** Last built course seed for a game id; {@code -1} = never built. */
    public int builtSeed(String forGameId) {
        return MinigameDimensions.GAME_RACE.equals(forGameId) ? builtSeedRace : builtSeedArena;
    }

    public void setBuiltSeed(String forGameId, int seed) {
        if (MinigameDimensions.GAME_RACE.equals(forGameId)) {
            this.builtSeedRace = seed;
        } else {
            this.builtSeedArena = seed;
        }
        setDirty();
    }

    // ------------------------------------------------------------------ tickets

    public void putTicket(UUID uuid, Ticket ticket) {
        tickets.put(uuid, ticket);
        setDirty();
    }

    @Nullable
    public Ticket ticket(UUID uuid) {
        return tickets.get(uuid);
    }

    public void removeTicket(UUID uuid) {
        if (tickets.remove(uuid) != null) {
            setDirty();
        }
    }

    public Map<UUID, Ticket> ticketsSnapshot() {
        return Collections.unmodifiableMap(new HashMap<>(tickets));
    }

    /**
     * Captures a full safety ticket from the player's CURRENT position/mode/inventory.
     * Encoding happens now (with the player's registry access), so restoring later never
     * depends on who is looking at the SavedData.
     */
    public static Ticket captureTicket(ServerPlayer player) {
        RegistryOps<Tag> ops = RegistryOps.create(NbtOps.INSTANCE, player.registryAccess());
        Inventory inventory = player.getInventory();
        return new Ticket(
                new ReturnAnchor(player.level().dimension(),
                        player.getX(), player.getY(), player.getZ(),
                        player.getYRot(), player.getXRot()),
                player.gameMode.getGameModeForPlayer().getId(),
                player.getHealth(),
                player.getFoodData().getFoodLevel(),
                player.getFoodData().getSaturationLevel(),
                encodeSlots(inventory.items, ops),
                encodeSlots(inventory.armor, ops),
                encodeSlots(inventory.offhand, ops));
    }

    /**
     * Makes the player whole again from a ticket: clears whatever they carry (the kit),
     * decodes the snapshot back into the exact slots, restores game mode, health and
     * food, and syncs the container. Does NOT teleport — callers own positioning.
     */
    public static void restoreTicket(ServerPlayer player, Ticket ticket) {
        Inventory inventory = player.getInventory();
        inventory.clearContent();
        decodeSlots(ticket.main(), inventory.items, player);
        decodeSlots(ticket.armor(), inventory.armor, player);
        decodeSlots(ticket.offhand(), inventory.offhand, player);
        player.inventoryMenu.broadcastChanges();
        player.containerMenu.broadcastChanges();

        player.setGameMode(GameType.byId(ticket.gameModeId()));
        player.setHealth(Mth.clamp(ticket.health(), 1.0F, player.getMaxHealth()));
        player.getFoodData().setFoodLevel(ticket.foodLevel());
        player.getFoodData().setSaturation(ticket.saturation());
    }

    private static ListTag encodeSlots(NonNullList<ItemStack> stacks, RegistryOps<Tag> ops) {
        ListTag list = new ListTag();
        for (ItemStack stack : stacks) {
            DataResult<Tag> encoded = ItemStack.OPTIONAL_CODEC.encodeStart(ops, stack);
            list.add(encoded.resultOrPartial(
                    error -> EclipseMod.LOGGER.error("Minigame ticket: cannot encode {}: {}", stack, error))
                    .orElseGet(CompoundTag::new));
        }
        return list;
    }

    private static void decodeSlots(ListTag list, NonNullList<ItemStack> target, ServerPlayer player) {
        RegistryOps<Tag> ops = RegistryOps.create(NbtOps.INSTANCE, player.registryAccess());
        for (int i = 0; i < list.size() && i < target.size(); i++) {
            int slot = i;
            Tag tag = list.get(i);
            target.set(i, ItemStack.OPTIONAL_CODEC.parse(ops, tag)
                    .resultOrPartial(error -> EclipseMod.LOGGER.error(
                            "Minigame ticket: cannot decode slot {} from {}: {}", slot, tag, error))
                    .orElse(ItemStack.EMPTY));
        }
    }

    // ------------------------------------------------------------------ NBT

    public static MinigameState load(CompoundTag tag, HolderLookup.Provider registries) {
        MinigameState state = new MinigameState();
        state.phase = Phase.byName(tag.getString(TAG_PHASE));
        state.gameId = tag.getString(TAG_GAME_ID);
        state.endsAtEpochMillis = tag.getLong(TAG_ENDS_AT);
        state.openCount = tag.getInt(TAG_OPEN_COUNT);
        state.roundEndsAtEpochMillis = tag.getLong(TAG_ROUND_ENDS_AT);

        if (tag.contains(TAG_PORTAL, Tag.TAG_COMPOUND)) {
            CompoundTag portal = tag.getCompound(TAG_PORTAL);
            ResourceLocation dim = ResourceLocation.tryParse(portal.getString("dim"));
            if (dim != null) {
                state.portalDimension = ResourceKey.create(Registries.DIMENSION, dim);
                state.portalPos = new BlockPos(portal.getInt("x"), portal.getInt("y"), portal.getInt("z"));
            }
        }

        for (Tag participant : tag.getList(TAG_PARTICIPANTS, Tag.TAG_INT_ARRAY)) {
            state.participants.add(NbtUtils.loadUUID(participant));
        }
        for (Tag rewarded : tag.getList(TAG_REWARDED, Tag.TAG_INT_ARRAY)) {
            state.rewardedParticipation.add(NbtUtils.loadUUID(rewarded));
        }

        for (Tag ticketTag : tag.getList(TAG_TICKETS, Tag.TAG_COMPOUND)) {
            CompoundTag entry = (CompoundTag) ticketTag;
            ResourceLocation dim = ResourceLocation.tryParse(entry.getString("dim"));
            if (dim == null) {
                continue;
            }
            state.tickets.put(entry.getUUID("uuid"), new Ticket(
                    new ReturnAnchor(ResourceKey.create(Registries.DIMENSION, dim),
                            entry.getDouble("x"), entry.getDouble("y"), entry.getDouble("z"),
                            entry.getFloat("yaw"), entry.getFloat("pitch")),
                    entry.getInt("gameMode"),
                    entry.getFloat("health"),
                    entry.getInt("food"),
                    entry.getFloat("saturation"),
                    entry.getList("main", Tag.TAG_COMPOUND),
                    entry.getList("armor", Tag.TAG_COMPOUND),
                    entry.getList("offhand", Tag.TAG_COMPOUND)));
        }

        readUuidIntMap(tag.getList(TAG_KILLS, Tag.TAG_COMPOUND), state.kills);
        readUuidIntMap(tag.getList(TAG_RACE_PROGRESS, Tag.TAG_COMPOUND), state.raceProgress);
        for (Tag lapTag : tag.getList(TAG_RACE_LAP_START, Tag.TAG_COMPOUND)) {
            CompoundTag entry = (CompoundTag) lapTag;
            state.raceLapStart.put(entry.getUUID("uuid"), entry.getLong("value"));
        }
        for (Tag finisher : tag.getList(TAG_RACE_FINISHERS, Tag.TAG_INT_ARRAY)) {
            state.raceFinishers.add(NbtUtils.loadUUID(finisher));
        }
        state.bestLapMillis = tag.getLong(TAG_BEST_LAP);
        state.builtSeedArena = tag.contains(TAG_BUILT_SEED_ARENA) ? tag.getInt(TAG_BUILT_SEED_ARENA) : -1;
        state.builtSeedRace = tag.contains(TAG_BUILT_SEED_RACE) ? tag.getInt(TAG_BUILT_SEED_RACE) : -1;
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putString(TAG_PHASE, phase.name().toLowerCase(Locale.ROOT));
        tag.putString(TAG_GAME_ID, gameId);
        tag.putLong(TAG_ENDS_AT, endsAtEpochMillis);
        tag.putInt(TAG_OPEN_COUNT, openCount);
        tag.putLong(TAG_ROUND_ENDS_AT, roundEndsAtEpochMillis);

        if (portalDimension != null && portalPos != null) {
            CompoundTag portal = new CompoundTag();
            portal.putString("dim", portalDimension.location().toString());
            portal.putInt("x", portalPos.getX());
            portal.putInt("y", portalPos.getY());
            portal.putInt("z", portalPos.getZ());
            tag.put(TAG_PORTAL, portal);
        }

        ListTag participantsTag = new ListTag();
        for (UUID uuid : participants) {
            participantsTag.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_PARTICIPANTS, participantsTag);

        ListTag rewardedTag = new ListTag();
        for (UUID uuid : rewardedParticipation) {
            rewardedTag.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_REWARDED, rewardedTag);

        ListTag ticketsTag = new ListTag();
        for (Map.Entry<UUID, Ticket> entry : tickets.entrySet()) {
            Ticket ticket = entry.getValue();
            CompoundTag ticketTag = new CompoundTag();
            ticketTag.putUUID("uuid", entry.getKey());
            ticketTag.putString("dim", ticket.anchor().dimension().location().toString());
            ticketTag.putDouble("x", ticket.anchor().x());
            ticketTag.putDouble("y", ticket.anchor().y());
            ticketTag.putDouble("z", ticket.anchor().z());
            ticketTag.putFloat("yaw", ticket.anchor().yaw());
            ticketTag.putFloat("pitch", ticket.anchor().pitch());
            ticketTag.putInt("gameMode", ticket.gameModeId());
            ticketTag.putFloat("health", ticket.health());
            ticketTag.putInt("food", ticket.foodLevel());
            ticketTag.putFloat("saturation", ticket.saturation());
            ticketTag.put("main", ticket.main().copy());
            ticketTag.put("armor", ticket.armor().copy());
            ticketTag.put("offhand", ticket.offhand().copy());
            ticketsTag.add(ticketTag);
        }
        tag.put(TAG_TICKETS, ticketsTag);

        tag.put(TAG_KILLS, writeUuidIntMap(kills));
        tag.put(TAG_RACE_PROGRESS, writeUuidIntMap(raceProgress));
        ListTag lapStarts = new ListTag();
        for (Map.Entry<UUID, Long> entry : raceLapStart.entrySet()) {
            CompoundTag lapTag = new CompoundTag();
            lapTag.putUUID("uuid", entry.getKey());
            lapTag.putLong("value", entry.getValue());
            lapStarts.add(lapTag);
        }
        tag.put(TAG_RACE_LAP_START, lapStarts);
        ListTag finishersTag = new ListTag();
        for (UUID uuid : raceFinishers) {
            finishersTag.add(NbtUtils.createUUID(uuid));
        }
        tag.put(TAG_RACE_FINISHERS, finishersTag);
        tag.putLong(TAG_BEST_LAP, bestLapMillis);
        tag.putInt(TAG_BUILT_SEED_ARENA, builtSeedArena);
        tag.putInt(TAG_BUILT_SEED_RACE, builtSeedRace);
        return tag;
    }

    private static void readUuidIntMap(ListTag list, Map<UUID, Integer> target) {
        for (Tag entryTag : list) {
            CompoundTag entry = (CompoundTag) entryTag;
            target.put(entry.getUUID("uuid"), entry.getInt("value"));
        }
    }

    private static ListTag writeUuidIntMap(Map<UUID, Integer> map) {
        ListTag list = new ListTag();
        for (Map.Entry<UUID, Integer> entry : map.entrySet()) {
            CompoundTag entryTag = new CompoundTag();
            entryTag.putUUID("uuid", entry.getKey());
            entryTag.putInt("value", entry.getValue());
            list.add(entryTag);
        }
        return list;
    }

    /** Helper for gametests/status: sorted online names of participants. */
    public List<String> debugParticipantNames(MinecraftServer server) {
        List<String> names = new ArrayList<>();
        for (UUID uuid : participants) {
            var player = server.getPlayerList().getPlayer(uuid);
            names.add(player != null ? player.getGameProfile().getName() : uuid.toString());
        }
        Collections.sort(names);
        return names;
    }
}
