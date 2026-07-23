package dev.projecteclipse.eclipse.analytics;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.neoforged.fml.loading.FMLPaths;

/**
 * READ-ONLY view of the secret offering value table for the {@code altar_value} analytics
 * counter (P4 §2.4: "offering + milestone deposits × value points"). The file of record,
 * {@code config/eclipse/offering_values.json}, is OWNED by P4-B6 (offerings) — analytics
 * only reads it and NEVER creates or writes it; while it does not exist the plan §2.6
 * default table below applies, so both packages score identically once B6 lands.
 *
 * <p>Lookup order matches {@code OfferingRules}: exact item id → first matching tag →
 * default tier. The {@code altarDeposit} signal carries only {@code (itemId, count)}, so
 * the enchanted ×1.5 bonus is NOT applied here — analytics deliberately under-credits
 * enchanted deposits rather than guessing (fail-safe direction; the award-deciding exact
 * value lives in B6's resolution, not in this counter).</p>
 */
public final class DepositValues {
    private record Table(Map<String, Integer> tiers, Map<String, String> byItem,
            Map<String, String> byTag, String defaultTier) {

        long value(ResourceLocation itemId) {
            String tier = byItem.get(itemId.toString());
            if (tier == null) {
                tier = tagTier(itemId);
            }
            if (tier == null) {
                tier = defaultTier;
            }
            Integer points = tiers.get(tier);
            return points == null ? 0L : Math.max(0L, points.longValue());
        }

        private String tagTier(ResourceLocation itemId) {
            var holder = BuiltInRegistries.ITEM.getHolder(itemId);
            if (holder.isEmpty()) {
                return null;
            }
            Holder<net.minecraft.world.item.Item> ref = holder.get();
            for (Map.Entry<String, String> entry : byTag.entrySet()) {
                String raw = entry.getKey();
                String tagId = raw.startsWith("#") ? raw.substring(1) : raw;
                ResourceLocation tagLocation = ResourceLocation.tryParse(tagId);
                if (tagLocation != null && ref.is(TagKey.create(Registries.ITEM, tagLocation))) {
                    return entry.getValue();
                }
            }
            return null;
        }
    }

    // statics reset on ServerStopped (via AnalyticsService.onServerStopped -> invalidate)
    private static volatile Table table = null;

    private DepositValues() {}

    /** Value points for one item of {@code itemId} (≥ 0; junk tier = 0). */
    public static long valuePerItem(ResourceLocation itemId) {
        return activeTable().value(itemId);
    }

    /** Re-reads {@code offering_values.json} if present (called from the analytics reload hook). */
    public static void reload() {
        table = loadFrom(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Drops the cached table so the next lookup re-reads (server stop / test isolation). */
    static void invalidate() {
        table = null;
    }

    private static Table activeTable() {
        Table current = table;
        if (current == null) {
            synchronized (DepositValues.class) {
                current = table;
                if (current == null) {
                    current = loadFrom(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
                    table = current;
                }
            }
        }
        return current;
    }

    /** Loads {@code offering_values.json} from {@code dir}, falling back to plan §2.6 defaults. */
    static Table loadFrom(Path dir) {
        Path file = dir.resolve("offering_values.json");
        if (!Files.exists(file)) {
            return defaults();
        }
        try {
            return fromJson(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)));
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("Analytics could not read {}; using built-in offering value defaults",
                    file, e);
            return defaults();
        }
    }

    private static Table fromJson(JsonElement json) {
        JsonObject obj = json.getAsJsonObject();
        Table def = defaults();
        Map<String, Integer> tiers = new HashMap<>(def.tiers());
        if (obj.has("tiers")) {
            tiers.clear();
            for (var entry : obj.getAsJsonObject("tiers").entrySet()) {
                tiers.put(entry.getKey(), entry.getValue().getAsInt());
            }
        }
        Map<String, String> byItem = new HashMap<>(def.byItem());
        if (obj.has("byItem")) {
            byItem.clear();
            for (var entry : obj.getAsJsonObject("byItem").entrySet()) {
                byItem.put(entry.getKey(), entry.getValue().getAsString());
            }
        }
        Map<String, String> byTag = new HashMap<>(def.byTag());
        if (obj.has("byTag")) {
            byTag.clear();
            for (var entry : obj.getAsJsonObject("byTag").entrySet()) {
                byTag.put(entry.getKey(), entry.getValue().getAsString());
            }
        }
        String defaultTier = obj.has("default") ? obj.get("default").getAsString() : def.defaultTier();
        return new Table(Map.copyOf(tiers), Map.copyOf(byItem), Map.copyOf(byTag), defaultTier);
    }

    /** The plan §2.6 default table, used until B6's {@code offering_values.json} exists. */
    private static Table defaults() {
        return new Table(
                Map.of("junk", 0, "common", 5, "useful", 15, "valuable", 40, "rare", 100, "epic", 250),
                Map.ofEntries(
                        Map.entry("minecraft:iron_ingot", "useful"),
                        Map.entry("minecraft:gold_block", "valuable"),
                        Map.entry("minecraft:diamond", "valuable"),
                        Map.entry("minecraft:diamond_block", "rare"),
                        Map.entry("minecraft:netherite_ingot", "rare"),
                        Map.entry("minecraft:netherite_block", "epic"),
                        Map.entry("minecraft:ender_pearl", "valuable"),
                        Map.entry("minecraft:totem_of_undying", "epic"),
                        Map.entry("eclipse:heart_fragment", "epic"),
                        Map.entry("eclipse:umbral_shard", "useful"),
                        Map.entry("eclipse:herald_core", "epic"),
                        Map.entry("minecraft:dragon_egg", "epic")),
                Map.of("#minecraft:dirt", "junk", "#minecraft:logs", "common", "#minecraft:iron_ores", "useful"),
                "junk");
    }
}
