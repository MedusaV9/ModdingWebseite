package dev.projecteclipse.eclipse.offering;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import net.minecraft.core.Holder;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;

/** Pure/value-table rules for one-per-day offerings and duplicate-type cancellation. */
public final class OfferingRules {
    public record Input(UUID player, String itemId, int value) {}

    public record Scored(UUID player, String itemId, int value, boolean duplicate) {}

    public record Resolution(List<Scored> offerings, List<UUID> winners, int bestValue, String winningItemId) {
        public Resolution {
            offerings = List.copyOf(offerings);
            winners = List.copyOf(winners);
            winningItemId = winningItemId == null ? "" : winningItemId;
        }
    }

    private OfferingRules() {}

    /** Exact id → ordered tag table → default tier, then component bonuses. */
    public static int value(ItemStack stack, OfferingConfig.Data config) {
        ResourceLocation id = BuiltInRegistries.ITEM.getKey(stack.getItem());
        return value(id, stack.isEnchanted(), stack.get(DataComponents.CUSTOM_NAME) != null, config);
    }

    /** Component-free overload used by persistence, resolution and pure gametests. */
    public static int value(ResourceLocation itemId, boolean enchanted, boolean renamed,
            OfferingConfig.Data config) {
        if (config.junk().contains(itemId.toString())) {
            return 0;
        }
        String tier = config.byItem().get(itemId.toString());
        if (tier == null) {
            tier = matchingTagTier(itemId, config);
        }
        if (tier == null) {
            tier = config.defaultTier();
        }
        int base = Math.max(0, config.tiers().getOrDefault(tier, 0));
        double multiplied = enchanted ? base * config.enchantedMultiplier() : base;
        long value = (long) Math.floor(multiplied);
        if (renamed) {
            value += config.renamedBonus();
        }
        return (int) Math.min(Integer.MAX_VALUE, Math.max(0L, value));
    }

    /** Base value without stored-component modifiers (the amount the frozen signal credits). */
    public static int baseValue(ResourceLocation itemId, OfferingConfig.Data config) {
        return value(itemId, false, false, config);
    }

    private static String matchingTagTier(ResourceLocation itemId, OfferingConfig.Data config) {
        var holder = BuiltInRegistries.ITEM.getHolder(itemId);
        if (holder.isEmpty()) {
            return null;
        }
        Holder<Item> item = holder.get();
        for (Map.Entry<String, String> entry : config.byTag().entrySet()) {
            String raw = entry.getKey();
            ResourceLocation tagId = ResourceLocation.tryParse(raw.startsWith("#") ? raw.substring(1) : raw);
            if (tagId != null && item.is(TagKey.create(Registries.ITEM, tagId))) {
                return entry.getValue();
            }
        }
        return null;
    }

    /**
     * Any item id offered by at least two players scores zero for every copy. Highest remaining
     * positive score wins; equal highest values produce co-winners.
     */
    public static Resolution resolve(List<Input> inputs) {
        Map<String, Integer> copies = new HashMap<>();
        for (Input input : inputs) {
            copies.merge(input.itemId(), 1, Integer::sum);
        }
        List<Scored> scored = new ArrayList<>(inputs.size());
        for (Input input : inputs) {
            boolean duplicate = copies.getOrDefault(input.itemId(), 0) >= 2;
            scored.add(new Scored(input.player(), input.itemId(), duplicate ? 0 : Math.max(0, input.value()),
                    duplicate));
        }
        scored.sort(Comparator.comparingInt(Scored::value).reversed().thenComparing(Scored::player));
        if (scored.isEmpty() || scored.getFirst().value() <= 0) {
            return new Resolution(scored, List.of(), 0, "");
        }
        int best = scored.getFirst().value();
        List<UUID> winners = new ArrayList<>();
        for (Scored offering : scored) {
            if (offering.value() != best) {
                break;
            }
            winners.add(offering.player());
        }
        // Equal values can come from different item types; the announcement stays item-only and
        // uses the first UUID-sorted winner's item as a deterministic representative.
        String winningItem = scored.stream()
                .filter(row -> row.value() == best)
                .min(Comparator.comparing(Scored::player))
                .map(Scored::itemId).orElse("");
        return new Resolution(scored, winners, best, winningItem);
    }

    /** Whether a second click is still required for this item at this game time. */
    public static boolean needsConfirmation(long now, Long pendingAt, String pendingItem,
            String currentItem, long windowTicks) {
        return pendingAt == null || now < pendingAt || now - pendingAt > windowTicks
                || !currentItem.equals(pendingItem);
    }
}
