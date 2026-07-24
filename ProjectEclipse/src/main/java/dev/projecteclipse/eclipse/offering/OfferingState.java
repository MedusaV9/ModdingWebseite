package dev.projecteclipse.eclipse.offering;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import dev.projecteclipse.eclipse.awards.AwardConfig;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/** Per-save one-offering-per-player ledger ({@code eclipse_offerings.dat}). */
public final class OfferingState extends SavedData {
    public static final String DATA_NAME = "eclipse_offerings";

    /** The minimum stack facts needed to recompute the secret value at rollover. */
    public record Offer(UUID player, String itemId, boolean enchanted, boolean renamed) {}

    /** Frozen resolution; score zero includes junk and duplicate-type cancellations. */
    public record DayResult(
            int day,
            List<OfferingRules.Scored> offerings,
            List<UUID> winners,
            int bestValue,
            String winningItemId,
            AwardConfig.Reward winnerReward) {
        public DayResult {
            offerings = List.copyOf(offerings);
            winners = List.copyOf(winners);
            winningItemId = winningItemId == null ? "" : winningItemId;
            winnerReward = winnerReward == null ? AwardConfig.Reward.NONE : winnerReward;
        }

        /** Compatibility constructor for previews and records created before rewards were frozen. */
        public DayResult(int day, List<OfferingRules.Scored> offerings, List<UUID> winners,
                int bestValue, String winningItemId) {
            this(day, offerings, winners, bestValue, winningItemId, AwardConfig.Reward.NONE);
        }
    }

    private final Map<Integer, Map<UUID, Offer>> offersByDay = new HashMap<>();
    private final Map<Integer, DayResult> resolvedDays = new HashMap<>();

    public OfferingState() {}

    public static OfferingState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(OfferingState::new, OfferingState::load));
    }

    /** Records once; false means that UUID already offered on this event day. */
    public boolean add(int day, Offer offer) {
        Map<UUID, Offer> offers = offersByDay.computeIfAbsent(day, key -> new HashMap<>());
        if (offers.containsKey(offer.player())) {
            return false;
        }
        offers.put(offer.player(), offer);
        setDirty();
        return true;
    }

    public boolean hasOffered(int day, UUID player) {
        Map<UUID, Offer> offers = offersByDay.get(day);
        return offers != null && offers.containsKey(player);
    }

    public List<Offer> offers(int day) {
        Map<UUID, Offer> offers = offersByDay.get(day);
        if (offers == null) {
            return List.of();
        }
        List<Offer> sorted = new ArrayList<>(offers.values());
        sorted.sort(java.util.Comparator.comparing(Offer::player));
        return Collections.unmodifiableList(sorted);
    }

    public Optional<DayResult> resolved(int day) {
        return Optional.ofNullable(resolvedDays.get(day));
    }

    /** First writer wins, making repeated PRE/catch-up calls harmless. */
    public boolean putResolved(DayResult result) {
        if (resolvedDays.containsKey(result.day())) {
            return false;
        }
        resolvedDays.put(result.day(), result);
        setDirty();
        return true;
    }

    public static OfferingState load(CompoundTag tag, HolderLookup.Provider registries) {
        OfferingState state = new OfferingState();
        for (Tag rawDay : tag.getList("days", Tag.TAG_COMPOUND)) {
            CompoundTag dayTag = (CompoundTag) rawDay;
            int day = dayTag.getInt("day");
            Map<UUID, Offer> offers = new HashMap<>();
            for (Tag rawOffer : dayTag.getList("offers", Tag.TAG_COMPOUND)) {
                CompoundTag offerTag = (CompoundTag) rawOffer;
                if (!offerTag.hasUUID("uuid")) {
                    continue;
                }
                UUID uuid = offerTag.getUUID("uuid");
                offers.put(uuid, new Offer(uuid, offerTag.getString("item"),
                        offerTag.getBoolean("enchanted"), offerTag.getBoolean("renamed")));
            }
            state.offersByDay.put(day, offers);
        }
        for (Tag rawResult : tag.getList("resolved", Tag.TAG_COMPOUND)) {
            CompoundTag resultTag = (CompoundTag) rawResult;
            int day = resultTag.getInt("day");
            List<OfferingRules.Scored> scored = new ArrayList<>();
            for (Tag raw : resultTag.getList("offerings", Tag.TAG_COMPOUND)) {
                CompoundTag row = (CompoundTag) raw;
                if (row.hasUUID("uuid")) {
                    scored.add(new OfferingRules.Scored(row.getUUID("uuid"), row.getString("item"),
                            row.getInt("value"), row.getBoolean("duplicate")));
                }
            }
            List<UUID> winners = new ArrayList<>();
            for (Tag raw : resultTag.getList("winners", Tag.TAG_COMPOUND)) {
                CompoundTag row = (CompoundTag) raw;
                if (row.hasUUID("uuid")) {
                    winners.add(row.getUUID("uuid"));
                }
            }
            AwardConfig.Reward reward = resultTag.contains("reward", Tag.TAG_COMPOUND)
                    ? readReward(resultTag.getCompound("reward")) : AwardConfig.Reward.NONE;
            state.resolvedDays.put(day, new DayResult(day, scored, winners,
                    resultTag.getInt("best"), resultTag.getString("winningItem"), reward));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag days = new ListTag();
        offersByDay.entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(entry -> {
            CompoundTag dayTag = new CompoundTag();
            dayTag.putInt("day", entry.getKey());
            ListTag offers = new ListTag();
            entry.getValue().values().stream().sorted(java.util.Comparator.comparing(Offer::player)).forEach(offer -> {
                CompoundTag offerTag = new CompoundTag();
                offerTag.putUUID("uuid", offer.player());
                offerTag.putString("item", offer.itemId());
                offerTag.putBoolean("enchanted", offer.enchanted());
                offerTag.putBoolean("renamed", offer.renamed());
                offers.add(offerTag);
            });
            dayTag.put("offers", offers);
            days.add(dayTag);
        });
        tag.put("days", days);

        ListTag resolved = new ListTag();
        resolvedDays.entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(entry -> {
            DayResult result = entry.getValue();
            CompoundTag resultTag = new CompoundTag();
            resultTag.putInt("day", result.day());
            resultTag.putInt("best", result.bestValue());
            resultTag.putString("winningItem", result.winningItemId());
            resultTag.put("reward", writeReward(result.winnerReward()));
            ListTag offerings = new ListTag();
            for (OfferingRules.Scored score : result.offerings()) {
                CompoundTag row = new CompoundTag();
                row.putUUID("uuid", score.player());
                row.putString("item", score.itemId());
                row.putInt("value", score.value());
                row.putBoolean("duplicate", score.duplicate());
                offerings.add(row);
            }
            resultTag.put("offerings", offerings);
            ListTag winners = new ListTag();
            for (UUID winner : result.winners()) {
                CompoundTag row = new CompoundTag();
                row.putUUID("uuid", winner);
                winners.add(row);
            }
            resultTag.put("winners", winners);
            resolved.add(resultTag);
        });
        tag.put("resolved", resolved);
        return tag;
    }

    private static CompoundTag writeReward(AwardConfig.Reward reward) {
        CompoundTag tag = new CompoundTag();
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

    private static AwardConfig.Reward readReward(CompoundTag tag) {
        List<AwardConfig.ItemReward> items = new ArrayList<>();
        for (Tag raw : tag.getList("items", Tag.TAG_COMPOUND)) {
            CompoundTag item = (CompoundTag) raw;
            items.add(new AwardConfig.ItemReward(item.getString("id"), item.getInt("count")));
        }
        return new AwardConfig.Reward(tag.getInt("xp"), tag.getInt("shards"), items);
    }
}
