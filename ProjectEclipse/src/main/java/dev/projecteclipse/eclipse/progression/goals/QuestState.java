package dev.projecteclipse.eclipse.progression.goals;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save quest progress (SavedData {@code eclipse_quests.dat}, overworld storage — plans_v3
 * P4 §2.2 "Storage"). Replaces the legacy {@code eclipse:goal_progress} attachment, which the
 * engine no longer writes. Everything is keyed by event day so day changes need zero cleanup
 * and admins can lower the day without losing history.
 *
 * <p>Held per (day): team counters + team done flags per goalId, announced mains, fired team
 * beats; per (day, uuid): progress + done per goalId, the drawn personal quest ids, stat
 * baselines captured at assignment, and distinct-token sets (visit_biomes). Held per uuid:
 * the lifetime set of completed personal quests (no repeats across the event).</p>
 */
public final class QuestState extends SavedData {
    public static final String DATA_NAME = "eclipse_quests";

    /** Frozen reward snapshot for a known team member who was offline at completion time. */
    public record PendingReward(String id, String goalId, byte kind, String scope,
            GoalSpec.Reward reward) {
        static PendingReward of(int day, GoalSpec spec) {
            return new PendingReward("quest:" + day + ":" + spec.id(), spec.id(), spec.kind(),
                    spec.scope().id(), spec.reward());
        }
    }

    /** Per-(day, player) slice. */
    static final class PlayerDay {
        final Map<String, Long> progress = new HashMap<>();
        final Set<String> done = new LinkedHashSet<>();
        List<String> personals = null; // null = not drawn yet
        final Map<String, Long> baselines = new HashMap<>();
        final Map<String, Set<String>> distinct = new HashMap<>();
        int rerollNonce = 0;
    }

    /** Per-day slice. */
    static final class DayData {
        final Map<String, Long> teamProgress = new HashMap<>();
        final Set<String> teamDone = new LinkedHashSet<>();
        final Set<String> announced = new LinkedHashSet<>();
        final Set<String> beatsFired = new LinkedHashSet<>();
        final Map<UUID, PlayerDay> players = new HashMap<>();
        boolean nightOpen;
        long nightId = Long.MIN_VALUE;
        final Set<UUID> nightEligible = new LinkedHashSet<>();
        final Set<UUID> nightDamaged = new LinkedHashSet<>();
    }

    private final Map<Integer, DayData> days = new HashMap<>();
    private final Map<UUID, Set<String>> lifetimePersonals = new HashMap<>();
    private final Map<UUID, List<PendingReward>> pendingRewards = new HashMap<>();

    public QuestState() {}

    public static QuestState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(QuestState::new, QuestState::load));
    }

    // --- team scope ---

    public long teamProgress(int day, String goalId) {
        DayData data = days.get(day);
        return data == null ? 0L : data.teamProgress.getOrDefault(goalId, 0L);
    }

    /** Adds to the shared team counter and returns the new value. */
    public long addTeamProgress(int day, String goalId, long delta) {
        DayData data = day(day);
        long next = Math.max(0L, data.teamProgress.getOrDefault(goalId, 0L) + delta);
        data.teamProgress.put(goalId, next);
        setDirty();
        return next;
    }

    public void setTeamProgress(int day, String goalId, long value) {
        day(day).teamProgress.put(goalId, Math.max(0L, value));
        setDirty();
    }

    public boolean isTeamDone(int day, String goalId) {
        DayData data = days.get(day);
        return data != null && data.teamDone.contains(goalId);
    }

    /** Marks the team goal done; returns false when it already was (idempotence guard). */
    public boolean setTeamDone(int day, String goalId) {
        boolean added = day(day).teamDone.add(goalId);
        if (added) {
            setDirty();
        }
        return added;
    }

    public void clearTeamDone(int day, String goalId) {
        DayData data = days.get(day);
        if (data != null && data.teamDone.remove(goalId)) {
            data.teamProgress.remove(goalId);
            setDirty();
        }
    }

    // --- per-player scope ---

    /** Records membership in the day's quest cohort even when no counter exists yet. */
    public void ensurePlayer(int day, UUID uuid) {
        DayData data = day(day);
        if (!data.players.containsKey(uuid)) {
            data.players.put(uuid, new PlayerDay());
            setDirty();
        }
    }

    public long playerProgress(int day, UUID uuid, String goalId) {
        PlayerDay player = playerOrNull(day, uuid);
        return player == null ? 0L : player.progress.getOrDefault(goalId, 0L);
    }

    /** Adds player progress and returns the new value. */
    public long addPlayerProgress(int day, UUID uuid, String goalId, long delta) {
        PlayerDay player = player(day, uuid);
        long next = Math.max(0L, player.progress.getOrDefault(goalId, 0L) + delta);
        player.progress.put(goalId, next);
        setDirty();
        return next;
    }

    /** Raises player progress to at least {@code value}; returns the effective value. */
    public long raisePlayerProgress(int day, UUID uuid, String goalId, long value) {
        PlayerDay player = player(day, uuid);
        long next = Math.max(player.progress.getOrDefault(goalId, 0L), value);
        player.progress.put(goalId, next);
        setDirty();
        return next;
    }

    public void resetPlayerProgress(int day, UUID uuid, String goalId) {
        PlayerDay player = playerOrNull(day, uuid);
        if (player != null) {
            player.progress.remove(goalId);
            player.done.remove(goalId);
            player.distinct.remove(goalId);
            setDirty();
        }
    }

    public boolean isPlayerDone(int day, UUID uuid, String goalId) {
        PlayerDay player = playerOrNull(day, uuid);
        return player != null && player.done.contains(goalId);
    }

    /** Marks the goal done for the player; returns false when it already was. */
    public boolean setPlayerDone(int day, UUID uuid, String goalId) {
        boolean added = player(day, uuid).done.add(goalId);
        if (added) {
            setDirty();
        }
        return added;
    }

    /** Adds a distinct token (e.g. biome id) for the goal; returns the new distinct count. */
    public int addDistinct(int day, UUID uuid, String goalId, String token) {
        Set<String> set = player(day, uuid).distinct.computeIfAbsent(goalId, key -> new LinkedHashSet<>());
        if (set.add(token)) {
            setDirty();
        }
        return set.size();
    }

    // --- personal assignment ---

    /** The player's drawn personal ids for the day, or {@code null} when not drawn yet. */
    public List<String> personals(int day, UUID uuid) {
        PlayerDay player = playerOrNull(day, uuid);
        return player == null || player.personals == null ? null
                : Collections.unmodifiableList(player.personals);
    }

    public void setPersonals(int day, UUID uuid, List<String> ids) {
        player(day, uuid).personals = new ArrayList<>(ids);
        setDirty();
    }

    public int rerollNonce(int day, UUID uuid) {
        PlayerDay player = playerOrNull(day, uuid);
        return player == null ? 0 : player.rerollNonce;
    }

    public int bumpRerollNonce(int day, UUID uuid) {
        PlayerDay player = player(day, uuid);
        player.rerollNonce++;
        setDirty();
        return player.rerollNonce;
    }

    public Set<String> lifetimeCompletedPersonals(UUID uuid) {
        Set<String> set = lifetimePersonals.get(uuid);
        return set == null ? Set.of() : Collections.unmodifiableSet(set);
    }

    public void addLifetimeCompletedPersonal(UUID uuid, String goalId) {
        if (lifetimePersonals.computeIfAbsent(uuid, key -> new LinkedHashSet<>()).add(goalId)) {
            setDirty();
        }
    }

    // --- stat baselines ---

    /** Baseline for the stat key captured at assignment, or {@code null} when absent. */
    public Long baseline(int day, UUID uuid, String statKey) {
        PlayerDay player = playerOrNull(day, uuid);
        return player == null ? null : player.baselines.get(statKey);
    }

    public void setBaseline(int day, UUID uuid, String statKey, long value) {
        player(day, uuid).baselines.put(statKey, value);
        setDirty();
    }

    public boolean hasBaseline(int day, UUID uuid, String statKey) {
        PlayerDay player = playerOrNull(day, uuid);
        return player != null && player.baselines.containsKey(statKey);
    }

    // --- announce / beats dedup ---

    /** Test-and-set of the first-completion announce for (day, goalId). */
    public boolean markAnnounced(int day, String goalId) {
        boolean added = day(day).announced.add(goalId);
        if (added) {
            setDirty();
        }
        return added;
    }

    public boolean isBeatFired(int day, String beatId) {
        DayData data = days.get(day);
        return data != null && data.beatsFired.contains(beatId);
    }

    /** Test-and-set of a team beat for the day. */
    public boolean markBeatFired(int day, String beatId) {
        boolean added = day(day).beatsFired.add(beatId);
        if (added) {
            setDirty();
        }
        return added;
    }

    /** Re-arms a team beat (admin revoke): a matching world state may re-fire it next poll. */
    public void clearBeatFired(int day, String beatId) {
        DayData data = days.get(day);
        if (data != null && data.beatsFired.remove(beatId)) {
            setDirty();
        }
    }

    public Set<String> beatsFired(int day) {
        DayData data = days.get(day);
        return data == null ? Set.of() : Collections.unmodifiableSet(data.beatsFired);
    }

    /** UUIDs with any recorded state for the day (payload rebuilds, team_all checks). */
    public Set<UUID> knownPlayers(int day) {
        DayData data = days.get(day);
        return data == null ? Set.of() : Collections.unmodifiableSet(data.players.keySet());
    }

    // --- offline team rewards ---

    /** Queues once by stable day/goal id. */
    public boolean queueReward(UUID uuid, PendingReward reward) {
        List<PendingReward> pending = pendingRewards.computeIfAbsent(uuid, key -> new ArrayList<>());
        if (pending.stream().anyMatch(existing -> existing.id().equals(reward.id()))) {
            return false;
        }
        pending.add(reward);
        setDirty();
        return true;
    }

    /** Removes before delivery so repeated logins cannot double-grant. */
    public List<PendingReward> takePendingRewards(UUID uuid) {
        List<PendingReward> pending = pendingRewards.remove(uuid);
        if (pending == null || pending.isEmpty()) {
            return List.of();
        }
        setDirty();
        return List.copyOf(pending);
    }

    // --- survive_night_no_damage window ---

    /**
     * Opens a Minecraft-night window. Re-entering the same persisted night after a restart
     * is a no-op, so its damage flags cannot be reset by process lifecycle.
     */
    public void beginNight(int day, long nightId, java.util.Collection<UUID> onlineAtDusk) {
        DayData data = day(day);
        if (data.nightOpen && data.nightId == nightId) {
            return;
        }
        data.nightOpen = true;
        data.nightId = nightId;
        data.nightEligible.clear();
        data.nightEligible.addAll(onlineAtDusk);
        data.nightDamaged.clear();
        setDirty();
    }

    public boolean isNightOpen(int day) {
        DayData data = days.get(day);
        return data != null && data.nightOpen;
    }

    public void markNightDamaged(int day, UUID uuid) {
        DayData data = days.get(day);
        if (data != null && data.nightOpen && data.nightEligible.contains(uuid)
                && data.nightDamaged.add(uuid)) {
            setDirty();
        }
    }

    public void forfeitNight(int day, UUID uuid) {
        DayData data = days.get(day);
        if (data != null && data.nightOpen && data.nightEligible.remove(uuid)) {
            setDirty();
        }
    }

    public boolean isNightEligible(int day, UUID uuid) {
        DayData data = days.get(day);
        return data != null && data.nightOpen && data.nightEligible.contains(uuid)
                && !data.nightDamaged.contains(uuid);
    }

    public Set<UUID> nightSurvivors(int day) {
        DayData data = days.get(day);
        if (data == null || !data.nightOpen) {
            return Set.of();
        }
        Set<UUID> survivors = new LinkedHashSet<>(data.nightEligible);
        survivors.removeAll(data.nightDamaged);
        return survivors;
    }

    public void endNight(int day) {
        DayData data = days.get(day);
        if (data == null || !data.nightOpen) {
            return;
        }
        data.nightOpen = false;
        data.nightId = Long.MIN_VALUE;
        data.nightEligible.clear();
        data.nightDamaged.clear();
        setDirty();
    }

    // --- internal ---

    private DayData day(int day) {
        return days.computeIfAbsent(day, key -> new DayData());
    }

    private PlayerDay player(int day, UUID uuid) {
        return day(day).players.computeIfAbsent(uuid, key -> new PlayerDay());
    }

    private PlayerDay playerOrNull(int day, UUID uuid) {
        DayData data = days.get(day);
        return data == null ? null : data.players.get(uuid);
    }

    // --- NBT ---

    public static QuestState load(CompoundTag tag, HolderLookup.Provider registries) {
        QuestState state = new QuestState();
        ListTag daysTag = tag.getList("days", Tag.TAG_COMPOUND);
        for (int i = 0; i < daysTag.size(); i++) {
            CompoundTag dayTag = daysTag.getCompound(i);
            DayData data = new DayData();
            CompoundTag team = dayTag.getCompound("team");
            for (String key : team.getAllKeys()) {
                data.teamProgress.put(key, team.getLong(key));
            }
            readStrings(dayTag.getList("teamDone", Tag.TAG_STRING), data.teamDone);
            readStrings(dayTag.getList("announced", Tag.TAG_STRING), data.announced);
            readStrings(dayTag.getList("beats", Tag.TAG_STRING), data.beatsFired);
            data.nightOpen = dayTag.getBoolean("nightOpen");
            data.nightId = dayTag.contains("nightId", Tag.TAG_LONG)
                    ? dayTag.getLong("nightId") : Long.MIN_VALUE;
            readUuids(dayTag.getList("nightEligible", Tag.TAG_STRING), data.nightEligible);
            readUuids(dayTag.getList("nightDamaged", Tag.TAG_STRING), data.nightDamaged);
            ListTag playersTag = dayTag.getList("players", Tag.TAG_COMPOUND);
            for (int p = 0; p < playersTag.size(); p++) {
                CompoundTag playerTag = playersTag.getCompound(p);
                if (!playerTag.hasUUID("uuid")) {
                    continue;
                }
                PlayerDay player = new PlayerDay();
                CompoundTag progress = playerTag.getCompound("progress");
                for (String key : progress.getAllKeys()) {
                    player.progress.put(key, progress.getLong(key));
                }
                readStrings(playerTag.getList("done", Tag.TAG_STRING), player.done);
                if (playerTag.contains("personals", Tag.TAG_LIST)) {
                    List<String> personals = new ArrayList<>();
                    readStrings(playerTag.getList("personals", Tag.TAG_STRING), personals);
                    player.personals = personals;
                }
                CompoundTag baselines = playerTag.getCompound("baselines");
                for (String key : baselines.getAllKeys()) {
                    player.baselines.put(key, baselines.getLong(key));
                }
                CompoundTag distinct = playerTag.getCompound("distinct");
                for (String goalId : distinct.getAllKeys()) {
                    Set<String> tokens = new LinkedHashSet<>();
                    readStrings(distinct.getList(goalId, Tag.TAG_STRING), tokens);
                    player.distinct.put(goalId, tokens);
                }
                player.rerollNonce = playerTag.getInt("nonce");
                data.players.put(playerTag.getUUID("uuid"), player);
            }
            state.days.put(dayTag.getInt("day"), data);
        }
        CompoundTag lifetime = tag.getCompound("lifetimePersonals");
        for (String uuidKey : lifetime.getAllKeys()) {
            try {
                Set<String> set = new LinkedHashSet<>();
                readStrings(lifetime.getList(uuidKey, Tag.TAG_STRING), set);
                state.lifetimePersonals.put(UUID.fromString(uuidKey), set);
            } catch (IllegalArgumentException ignored) {
                // Corrupt uuid key: drop the entry rather than poison the whole save.
            }
        }
        for (Tag raw : tag.getList("pendingRewards", Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) raw;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            List<PendingReward> rewards = new ArrayList<>();
            for (Tag rewardRaw : playerTag.getList("rewards", Tag.TAG_COMPOUND)) {
                rewards.add(readPendingReward((CompoundTag) rewardRaw));
            }
            if (!rewards.isEmpty()) {
                state.pendingRewards.put(playerTag.getUUID("uuid"), rewards);
            }
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag daysTag = new ListTag();
        for (Map.Entry<Integer, DayData> dayEntry : days.entrySet()) {
            DayData data = dayEntry.getValue();
            CompoundTag dayTag = new CompoundTag();
            dayTag.putInt("day", dayEntry.getKey());
            CompoundTag team = new CompoundTag();
            data.teamProgress.forEach(team::putLong);
            dayTag.put("team", team);
            dayTag.put("teamDone", writeStrings(data.teamDone));
            dayTag.put("announced", writeStrings(data.announced));
            dayTag.put("beats", writeStrings(data.beatsFired));
            if (data.nightOpen) {
                dayTag.putBoolean("nightOpen", true);
                dayTag.putLong("nightId", data.nightId);
                dayTag.put("nightEligible", writeUuids(data.nightEligible));
                dayTag.put("nightDamaged", writeUuids(data.nightDamaged));
            }
            ListTag playersTag = new ListTag();
            for (Map.Entry<UUID, PlayerDay> playerEntry : data.players.entrySet()) {
                PlayerDay player = playerEntry.getValue();
                CompoundTag playerTag = new CompoundTag();
                playerTag.putUUID("uuid", playerEntry.getKey());
                CompoundTag progress = new CompoundTag();
                player.progress.forEach(progress::putLong);
                playerTag.put("progress", progress);
                playerTag.put("done", writeStrings(player.done));
                if (player.personals != null) {
                    playerTag.put("personals", writeStrings(player.personals));
                }
                CompoundTag baselines = new CompoundTag();
                player.baselines.forEach(baselines::putLong);
                playerTag.put("baselines", baselines);
                CompoundTag distinct = new CompoundTag();
                for (Map.Entry<String, Set<String>> entry : player.distinct.entrySet()) {
                    distinct.put(entry.getKey(), writeStrings(entry.getValue()));
                }
                playerTag.put("distinct", distinct);
                if (player.rerollNonce != 0) {
                    playerTag.putInt("nonce", player.rerollNonce);
                }
                playersTag.add(playerTag);
            }
            dayTag.put("players", playersTag);
            daysTag.add(dayTag);
        }
        tag.put("days", daysTag);
        CompoundTag lifetime = new CompoundTag();
        for (Map.Entry<UUID, Set<String>> entry : lifetimePersonals.entrySet()) {
            lifetime.put(entry.getKey().toString(), writeStrings(entry.getValue()));
        }
        tag.put("lifetimePersonals", lifetime);
        ListTag pending = new ListTag();
        pendingRewards.forEach((uuid, rewards) -> {
            CompoundTag playerTag = new CompoundTag();
            playerTag.putUUID("uuid", uuid);
            ListTag rewardList = new ListTag();
            rewards.forEach(reward -> rewardList.add(writePendingReward(reward)));
            playerTag.put("rewards", rewardList);
            pending.add(playerTag);
        });
        tag.put("pendingRewards", pending);
        return tag;
    }

    private static CompoundTag writePendingReward(PendingReward pending) {
        CompoundTag tag = new CompoundTag();
        tag.putString("id", pending.id());
        tag.putString("goalId", pending.goalId());
        tag.putByte("kind", pending.kind());
        tag.putString("scope", pending.scope());
        tag.putInt("skillXp", pending.reward().skillXp());
        tag.putInt("shards", pending.reward().shards());
        ListTag items = new ListTag();
        for (GoalSpec.ItemReward item : pending.reward().items()) {
            CompoundTag itemTag = new CompoundTag();
            itemTag.putString("id", item.id());
            itemTag.putInt("count", item.count());
            items.add(itemTag);
        }
        tag.put("items", items);
        return tag;
    }

    private static PendingReward readPendingReward(CompoundTag tag) {
        List<GoalSpec.ItemReward> items = new ArrayList<>();
        for (Tag raw : tag.getList("items", Tag.TAG_COMPOUND)) {
            CompoundTag item = (CompoundTag) raw;
            items.add(new GoalSpec.ItemReward(item.getString("id"), item.getInt("count")));
        }
        return new PendingReward(tag.getString("id"), tag.getString("goalId"), tag.getByte("kind"),
                tag.getString("scope"), new GoalSpec.Reward(
                        tag.getInt("skillXp"), tag.getInt("shards"), items));
    }

    private static void readStrings(ListTag list, java.util.Collection<String> into) {
        for (int i = 0; i < list.size(); i++) {
            into.add(list.getString(i));
        }
    }

    private static ListTag writeStrings(java.util.Collection<String> values) {
        ListTag list = new ListTag();
        for (String value : values) {
            list.add(StringTag.valueOf(value));
        }
        return list;
    }

    private static void readUuids(ListTag list, java.util.Collection<UUID> into) {
        for (int i = 0; i < list.size(); i++) {
            try {
                into.add(UUID.fromString(list.getString(i)));
            } catch (IllegalArgumentException ignored) {
                // Corrupt UUID entries are isolated to this night's eligibility state.
            }
        }
    }

    private static ListTag writeUuids(java.util.Collection<UUID> values) {
        ListTag list = new ListTag();
        for (UUID value : values) {
            list.add(StringTag.valueOf(value.toString()));
        }
        return list;
    }
}
