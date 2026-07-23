package dev.projecteclipse.eclipse.awards;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
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
 * Restart-safe daily award ledger ({@code eclipse_awards.dat}): chosen categories and frozen
 * results per day, dev reroll nonces, queued offline rewards and per-player reveal replay state.
 */
public final class AwardsState extends SavedData {
    public static final String DATA_NAME = "eclipse_awards";

    public record CategoryResult(
            String id,
            String metric,
            String titleEn,
            String titleDe,
            String statLineEn,
            String statLineDe,
            String rewardLineEn,
            String rewardLineDe,
            List<AwardMath.Candidate> candidates,
            List<UUID> winners) {
        public CategoryResult {
            candidates = List.copyOf(candidates);
            winners = List.copyOf(winners);
        }
    }

    public record ResolvedDay(int day, List<String> chosenCategoryIds, List<CategoryResult> categories) {
        public ResolvedDay {
            chosenCategoryIds = List.copyOf(chosenCategoryIds);
            categories = List.copyOf(categories);
        }
    }

    public record PendingReward(String id, int skillXp, int shards, List<AwardConfig.ItemReward> items) {
        public PendingReward {
            items = List.copyOf(items);
        }

        public static PendingReward of(String id, AwardConfig.Reward reward) {
            return new PendingReward(id, reward.skillXp(), reward.shards(), reward.items());
        }
    }

    private final Map<Integer, ResolvedDay> resolvedDays = new HashMap<>();
    private final Map<Integer, Integer> rerollNonces = new HashMap<>();
    private final Map<UUID, List<PendingReward>> pendingRewards = new HashMap<>();
    private final Map<UUID, Integer> lastRevealSeen = new HashMap<>();

    public AwardsState() {}

    public static AwardsState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(AwardsState::new, AwardsState::load));
    }

    public Optional<ResolvedDay> resolved(int day) {
        return Optional.ofNullable(resolvedDays.get(day));
    }

    /** First writer wins; this is the rollover/catch-up idempotence guard. */
    public boolean putResolved(ResolvedDay day) {
        if (resolvedDays.containsKey(day.day())) {
            return false;
        }
        resolvedDays.put(day.day(), day);
        setDirty();
        return true;
    }

    /** Adds the fixed best-offering reveal if it was not already captured in the day's record. */
    public boolean appendCategory(int day, CategoryResult category) {
        ResolvedDay existing = resolvedDays.get(day);
        if (existing == null || existing.categories().stream().anyMatch(result -> result.id().equals(category.id()))) {
            return false;
        }
        List<CategoryResult> categories = new ArrayList<>(existing.categories());
        categories.add(category);
        resolvedDays.put(day, new ResolvedDay(day, existing.chosenCategoryIds(), categories));
        setDirty();
        return true;
    }

    public int latestResolvedDay() {
        return resolvedDays.keySet().stream().mapToInt(Integer::intValue).max().orElse(0);
    }

    public Map<Integer, ResolvedDay> resolvedDays() {
        return Collections.unmodifiableMap(resolvedDays);
    }

    public int rerollNonce(int day) {
        return rerollNonces.getOrDefault(day, 0);
    }

    /** Increments the persisted nonce unless the configured reroll cap has been reached. */
    public int reroll(int day, int maxRerolls) {
        int current = rerollNonce(day);
        if (current >= maxRerolls) {
            return -1;
        }
        int next = current + 1;
        rerollNonces.put(day, next);
        setDirty();
        return next;
    }

    /** Queues once by stable reward id. */
    public boolean queue(UUID player, PendingReward reward) {
        List<PendingReward> pending = pendingRewards.computeIfAbsent(player, key -> new ArrayList<>());
        if (pending.stream().anyMatch(existing -> existing.id().equals(reward.id()))) {
            return false;
        }
        pending.add(reward);
        setDirty();
        return true;
    }

    public List<PendingReward> pending(UUID player) {
        List<PendingReward> rewards = pendingRewards.get(player);
        return rewards == null ? List.of() : Collections.unmodifiableList(rewards);
    }

    /**
     * Removes before granting. A second login in the same server lifetime cannot double-grant;
     * the containing SavedData is marked dirty in the same tick as the player-data mutation.
     */
    public List<PendingReward> takePending(UUID player) {
        List<PendingReward> rewards = pendingRewards.remove(player);
        if (rewards == null || rewards.isEmpty()) {
            return List.of();
        }
        setDirty();
        return List.copyOf(rewards);
    }

    public boolean hasSeenReveal(UUID player, int day) {
        return lastRevealSeen.getOrDefault(player, 0) >= day;
    }

    public void markRevealSeen(UUID player, int day) {
        if (day > lastRevealSeen.getOrDefault(player, 0)) {
            lastRevealSeen.put(player, day);
            setDirty();
        }
    }

    public static AwardsState load(CompoundTag tag, HolderLookup.Provider registries) {
        AwardsState state = new AwardsState();
        for (Tag raw : tag.getList("resolved", Tag.TAG_COMPOUND)) {
            CompoundTag dayTag = (CompoundTag) raw;
            int day = dayTag.getInt("day");
            List<String> chosen = readStrings(dayTag.getList("chosen", Tag.TAG_STRING));
            List<CategoryResult> categories = new ArrayList<>();
            for (Tag categoryRaw : dayTag.getList("categories", Tag.TAG_COMPOUND)) {
                categories.add(readCategory((CompoundTag) categoryRaw));
            }
            state.resolvedDays.put(day, new ResolvedDay(day, chosen, categories));
        }
        CompoundTag rerolls = tag.getCompound("rerolls");
        for (String day : rerolls.getAllKeys()) {
            try {
                state.rerollNonces.put(Integer.parseInt(day), rerolls.getInt(day));
            } catch (NumberFormatException ignored) {
                // Drop only the corrupt key.
            }
        }
        for (Tag raw : tag.getList("pending", Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) raw;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            List<PendingReward> rewards = new ArrayList<>();
            for (Tag rewardRaw : playerTag.getList("rewards", Tag.TAG_COMPOUND)) {
                rewards.add(readReward((CompoundTag) rewardRaw));
            }
            if (!rewards.isEmpty()) {
                state.pendingRewards.put(playerTag.getUUID("uuid"), rewards);
            }
        }
        for (Tag raw : tag.getList("revealSeen", Tag.TAG_COMPOUND)) {
            CompoundTag seen = (CompoundTag) raw;
            if (seen.hasUUID("uuid")) {
                state.lastRevealSeen.put(seen.getUUID("uuid"), seen.getInt("day"));
            }
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag resolved = new ListTag();
        resolvedDays.entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(entry -> {
            ResolvedDay day = entry.getValue();
            CompoundTag dayTag = new CompoundTag();
            dayTag.putInt("day", day.day());
            dayTag.put("chosen", writeStrings(day.chosenCategoryIds()));
            ListTag categories = new ListTag();
            day.categories().forEach(category -> categories.add(writeCategory(category)));
            dayTag.put("categories", categories);
            resolved.add(dayTag);
        });
        tag.put("resolved", resolved);

        CompoundTag rerolls = new CompoundTag();
        rerollNonces.forEach((day, nonce) -> rerolls.putInt(Integer.toString(day), nonce));
        tag.put("rerolls", rerolls);

        ListTag pending = new ListTag();
        pendingRewards.forEach((uuid, rewards) -> {
            CompoundTag player = new CompoundTag();
            player.putUUID("uuid", uuid);
            ListTag rewardList = new ListTag();
            rewards.forEach(reward -> rewardList.add(writeReward(reward)));
            player.put("rewards", rewardList);
            pending.add(player);
        });
        tag.put("pending", pending);

        ListTag seenList = new ListTag();
        lastRevealSeen.forEach((uuid, day) -> {
            CompoundTag seen = new CompoundTag();
            seen.putUUID("uuid", uuid);
            seen.putInt("day", day);
            seenList.add(seen);
        });
        tag.put("revealSeen", seenList);
        return tag;
    }

    private static CompoundTag writeCategory(CategoryResult category) {
        CompoundTag tag = new CompoundTag();
        tag.putString("id", category.id());
        tag.putString("metric", category.metric());
        tag.putString("titleEn", category.titleEn());
        tag.putString("titleDe", category.titleDe());
        tag.putString("statEn", category.statLineEn());
        tag.putString("statDe", category.statLineDe());
        tag.putString("rewardEn", category.rewardLineEn());
        tag.putString("rewardDe", category.rewardLineDe());
        ListTag candidates = new ListTag();
        for (AwardMath.Candidate candidate : category.candidates()) {
            CompoundTag row = new CompoundTag();
            row.putUUID("uuid", candidate.uuid());
            row.putLong("value", candidate.value());
            candidates.add(row);
        }
        tag.put("candidates", candidates);
        ListTag winners = new ListTag();
        for (UUID winner : category.winners()) {
            CompoundTag row = new CompoundTag();
            row.putUUID("uuid", winner);
            winners.add(row);
        }
        tag.put("winners", winners);
        return tag;
    }

    private static CategoryResult readCategory(CompoundTag tag) {
        List<AwardMath.Candidate> candidates = new ArrayList<>();
        for (Tag raw : tag.getList("candidates", Tag.TAG_COMPOUND)) {
            CompoundTag row = (CompoundTag) raw;
            if (row.hasUUID("uuid")) {
                candidates.add(new AwardMath.Candidate(row.getUUID("uuid"), row.getLong("value")));
            }
        }
        List<UUID> winners = new ArrayList<>();
        for (Tag raw : tag.getList("winners", Tag.TAG_COMPOUND)) {
            CompoundTag row = (CompoundTag) raw;
            if (row.hasUUID("uuid")) {
                winners.add(row.getUUID("uuid"));
            }
        }
        return new CategoryResult(tag.getString("id"), tag.getString("metric"),
                tag.getString("titleEn"), tag.getString("titleDe"),
                tag.getString("statEn"), tag.getString("statDe"),
                tag.getString("rewardEn"), tag.getString("rewardDe"), candidates, winners);
    }

    private static CompoundTag writeReward(PendingReward reward) {
        CompoundTag tag = new CompoundTag();
        tag.putString("id", reward.id());
        tag.putInt("xp", reward.skillXp());
        tag.putInt("shards", reward.shards());
        ListTag items = new ListTag();
        for (AwardConfig.ItemReward item : reward.items()) {
            CompoundTag itemTag = new CompoundTag();
            itemTag.putString("id", item.id());
            itemTag.putInt("count", item.count());
            items.add(itemTag);
        }
        tag.put("items", items);
        return tag;
    }

    private static PendingReward readReward(CompoundTag tag) {
        List<AwardConfig.ItemReward> items = new ArrayList<>();
        for (Tag raw : tag.getList("items", Tag.TAG_COMPOUND)) {
            CompoundTag item = (CompoundTag) raw;
            items.add(new AwardConfig.ItemReward(item.getString("id"), item.getInt("count")));
        }
        return new PendingReward(tag.getString("id"), tag.getInt("xp"), tag.getInt("shards"), items);
    }

    private static ListTag writeStrings(List<String> values) {
        ListTag tag = new ListTag();
        values.forEach(value -> tag.add(StringTag.valueOf(value)));
        return tag;
    }

    private static List<String> readStrings(ListTag tag) {
        List<String> values = new ArrayList<>(tag.size());
        for (Tag value : tag) {
            values.add(value.getAsString());
        }
        return values;
    }
}
