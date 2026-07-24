package dev.projecteclipse.eclipse.worldgen.ore;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import javax.annotation.Nullable;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.block.Block;
import net.neoforged.fml.ModList;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loads {@code ores.json} from {@code <configDir>/ores.json} (typically
 * {@code config/eclipse/}). Missing files are written with day-gated defaults on first load.
 * Hot reload swaps an immutable {@link Snapshot} via {@link #current()}.
 *
 * <p>B2 (PLAN-B plans_v5): each ore now carries vanilla-style {@code layers} — per layer a
 * vein {@code size} ({@code OreConfiguration.size}), a per-chunk vein {@code count}
 * ({@code CountPlacement}) and a height {@code distribution} ({@code HeightRangePlacement}
 * uniform/triangle over {@code minY..maxY}). The default tables below are vanilla 1.21.1
 * ({@code OreFeatures} + {@code OrePlacements}) so vein caliber and density match vanilla
 * 1:1; the SHAPE comes from {@link OreVeinShape}. Progression gates (unlockStage /
 * bandFactor / centerBias, FINAL-DOPA-SOL §3) are unchanged. Legacy entries without
 * {@code layers} keep working: {@code cellP}/{@code radius} are converted into one
 * per-cell-probability layer of an equivalent vein size.</p>
 */
public final class OreConfig {
    /** Hard ceiling for overworld ore veins — prevents surface-exposed ore (D5 / req 8). */
    public static final int OVERWORLD_MAX_Y_CAP = 52;
    /**
     * Largest allowed vein size (vanilla's biggest is copper large, 20). Above this the
     * chain could poke out of its 16³ cell and break {@link OreVeinShape}'s containment
     * invariant, so bigger configured sizes are clamped with a warning.
     */
    public static final int MAX_VEIN_SIZE = 20;

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final double[] FLAT_BANDS = {1.0D, 1.0D, 1.0D, 1.0D, 1.0D, 1.0D};

    private static volatile Snapshot current = Snapshot.empty();
    private static volatile boolean loaded = false;

    private OreConfig() {}

    /** Immutable, reload-swappable ore table used by {@link OreField} and {@link OreGateApi}. */
    public record Snapshot(List<ResolvedOre> overworld, List<ResolvedOre> nether,
            Map<String, Integer> unlockStages) {

        static Snapshot empty() {
            return new Snapshot(List.of(), List.of(), Map.of());
        }

        List<ResolvedOre> oresOf(DiscProfile profile) {
            return profile == DiscProfile.NETHER ? this.nether : this.overworld;
        }

        @Nullable
        ResolvedOre byId(String id) {
            for (ResolvedOre ore : this.overworld) {
                if (ore.id().equals(id)) {
                    return ore;
                }
            }
            for (ResolvedOre ore : this.nether) {
                if (ore.id().equals(id)) {
                    return ore;
                }
            }
            return null;
        }
    }

    /** How a layer's per-chunk vein count is spread over Y (vanilla HeightRangePlacement). */
    public enum Distribution {
        /** Vanilla {@code HeightRangePlacement.uniform(minY, maxY)}. */
        UNIFORM,
        /** Vanilla {@code HeightRangePlacement.triangle(minY, maxY)} (peak at the midpoint). */
        TRIANGLE,
        /**
         * Legacy semantics: {@code count} is the per-16³-cell vein probability directly
         * (the old {@code cellP}), independent of Y. Used by converted legacy entries.
         */
        CELL
    }

    /**
     * One placement layer: vanilla vein {@code size}, per-chunk vein {@code count}
     * (fractions allowed — e.g. vanilla's rarity-1/9 large diamond is 0.111) and the
     * height distribution it is spread with. {@code distMinY..distMaxY} is the
     * distribution's own range; the ore's {@code minY}/{@code maxY} gate still clips
     * blocks (e.g. the overworld y≤{@value #OVERWORLD_MAX_Y_CAP} cap).
     */
    public record Layer(int size, double count, Distribution distribution, int distMinY, int distMaxY) {

        /**
         * Share of this layer's veins whose anchor falls in the 16-block cell band
         * starting at {@code cellFloorY} — the vanilla height-distribution mass at
         * 16-block resolution.
         */
        public double cellMass(int cellFloorY) {
            return switch (this.distribution) {
                case CELL -> 1.0D;
                case UNIFORM -> {
                    int lo = Math.max(cellFloorY, this.distMinY);
                    int hi = Math.min(cellFloorY + 15, this.distMaxY);
                    yield hi < lo ? 0.0D : (hi - lo + 1) / (double) (this.distMaxY - this.distMinY + 1);
                }
                case TRIANGLE -> triangleCdf(cellFloorY + 16) - triangleCdf(cellFloorY);
            };
        }

        private double triangleCdf(int y) {
            double width = this.distMaxY + 1.0D - this.distMinY;
            double t = (y - this.distMinY) / width;
            if (t <= 0.0D) {
                return 0.0D;
            }
            if (t >= 1.0D) {
                return 1.0D;
            }
            return t <= 0.5D ? 2.0D * t * t : 1.0D - 2.0D * (1.0D - t) * (1.0D - t);
        }
    }

    /** One validated ore entry ready for placement. */
    public record ResolvedOre(String id, int salt, Block stoneOre, Block deepOre, int minY, int maxY,
            List<Layer> layers, int unlockStage, double[] bandFactor, boolean centerBias) {}

    /** The active ore snapshot; safe to read from worldgen threads after a volatile read. */
    public static Snapshot current() {
        ensureLoaded();
        return current;
    }

    /**
     * Re-reads {@code ores.json} under {@code configDir}, creating the default file when absent.
     * Unknown blocks and mod-absent entries are skipped with a localized warning.
     */
    public static synchronized void reload(Path configDir) {
        Path file = configDir.resolve("ores.json");
        try {
            Files.createDirectories(configDir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create ore config directory {}", configDir, e);
        }

        JsonObject root;
        if (!Files.exists(file)) {
            root = defaultRoot();
            try {
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info(Component.translatable("config.eclipse.ores.created", file.toString()).getString());
            } catch (IOException e) {
                EclipseMod.LOGGER.error(Component.translatable("config.eclipse.ores.write_failed", file.toString()).getString(), e);
            }
        } else {
            try {
                root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error(Component.translatable("config.eclipse.ores.read_failed", file.toString()).getString(), e);
                root = defaultRoot();
            }
        }

        current = buildSnapshot(root);
        loaded = true;
        EclipseMod.LOGGER.info(Component.translatable("config.eclipse.ores.loaded",
                current.overworld().size(), current.nether().size()).getString());
    }

    /** Convenience reload of {@code config/eclipse/}. */
    public static synchronized void reloadDefault() {
        reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reloadDefault();
        }
    }

    private static Snapshot buildSnapshot(JsonObject root) {
        Map<String, Integer> unlockStages = new LinkedHashMap<>();
        List<ResolvedOre> overworld = parseList(root, "overworld", DiscProfile.OVERWORLD, unlockStages);
        List<ResolvedOre> nether = parseList(root, "nether", DiscProfile.NETHER, unlockStages);
        return new Snapshot(List.copyOf(overworld), List.copyOf(nether), Map.copyOf(unlockStages));
    }

    private static List<ResolvedOre> parseList(JsonObject root, String key, DiscProfile profile,
            Map<String, Integer> unlockStages) {
        if (!root.has(key) || !root.get(key).isJsonArray()) {
            return List.of();
        }
        JsonArray array = root.getAsJsonArray(key);
        List<ResolvedOre> out = new ArrayList<>(array.size());
        int salt = 1;
        for (JsonElement element : array) {
            if (!element.isJsonObject()) {
                continue;
            }
            ResolvedOre ore = parseEntry(element.getAsJsonObject(), profile, salt);
            if (ore != null) {
                out.add(ore);
                unlockStages.put(ore.id(), ore.unlockStage());
                salt++;
            }
        }
        return out;
    }

    @Nullable
    private static ResolvedOre parseEntry(JsonObject obj, DiscProfile profile, int salt) {
        String id = stringOrNull(obj, "id");
        if (id == null || id.isEmpty()) {
            EclipseMod.LOGGER.warn(Component.translatable("config.eclipse.ores.missing_id").getString());
            return null;
        }

        String requiredMod = stringOrNull(obj, "requiredMod");
        if (requiredMod != null && !requiredMod.isEmpty() && !ModList.get().isLoaded(requiredMod)) {
            EclipseMod.LOGGER.debug(Component.translatable("config.eclipse.ores.skip_mod", id, requiredMod).getString());
            return null;
        }

        String blockId = stringOrNull(obj, "block");
        if (blockId == null) {
            EclipseMod.LOGGER.warn(Component.translatable("config.eclipse.ores.missing_block", id).getString());
            return null;
        }

        Optional<Block> stone = resolveBlock(blockId);
        if (stone.isEmpty()) {
            EclipseMod.LOGGER.warn(Component.translatable("config.eclipse.ores.skip_unknown", id, blockId).getString());
            return null;
        }

        String deepId = stringOrNull(obj, "deepslate");
        Block deep = deepId != null ? resolveBlock(deepId).orElse(stone.get()) : stone.get();

        int minY = intOrDefault(obj, "minY", profile.minY());
        int configuredMaxY = intOrDefault(obj, "maxY", profile.minY() + profile.height() - 1);
        int maxY = profile == DiscProfile.OVERWORLD
                ? Math.min(configuredMaxY, OVERWORLD_MAX_Y_CAP)
                : configuredMaxY;
        if (maxY < minY) {
            EclipseMod.LOGGER.warn(Component.translatable("config.eclipse.ores.invalid_range", id, minY, maxY).getString());
            return null;
        }

        int unlockStage = intOrDefault(obj, "unlockStage", 0);
        boolean centerBias = boolOrDefault(obj, "centerBias", false);
        double[] bandFactor = bandFactorOrDefault(obj);
        List<Layer> layers = parseLayers(obj, id, minY, maxY);
        if (layers.isEmpty()) {
            EclipseMod.LOGGER.warn("Ore '{}' has no usable placement layers; skipping entry", id);
            return null;
        }

        return new ResolvedOre(id, salt, stone.get(), deep, minY, maxY, layers, unlockStage, bandFactor,
                centerBias);
    }

    /**
     * Parses the {@code layers} array; entries without one fall back to the legacy
     * {@code cellP}/{@code radius} pair, converted to one {@link Distribution#CELL} layer
     * (λ = cellP per cell) of roughly equivalent vein size, so pre-B2 config files keep
     * their tuned density and only pick up the vanilla vein SHAPE.
     */
    private static List<Layer> parseLayers(JsonObject obj, String id, int minY, int maxY) {
        if (obj.has("layers") && obj.get("layers").isJsonArray()) {
            List<Layer> out = new ArrayList<>();
            for (JsonElement element : obj.getAsJsonArray("layers")) {
                if (!element.isJsonObject()) {
                    continue;
                }
                JsonObject layer = element.getAsJsonObject();
                int size = intOrDefault(layer, "size", 9);
                if (size < 1 || size > MAX_VEIN_SIZE) {
                    EclipseMod.LOGGER.warn("Ore '{}' layer size {} outside 1..{}; clamping", id, size, MAX_VEIN_SIZE);
                    size = Math.max(1, Math.min(size, MAX_VEIN_SIZE));
                }
                double count = doubleOrDefault(layer, "count", 1.0D);
                if (count <= 0.0D) {
                    continue;
                }
                Distribution distribution = parseDistribution(stringOrNull(layer, "distribution"), id);
                int distMinY = intOrDefault(layer, "minY", minY);
                int distMaxY = intOrDefault(layer, "maxY", maxY);
                if (distMaxY < distMinY) {
                    EclipseMod.LOGGER.warn("Ore '{}' layer has minY {} > maxY {}; skipping layer", id, distMinY, distMaxY);
                    continue;
                }
                out.add(new Layer(size, count, distribution, distMinY, distMaxY));
            }
            return List.copyOf(out);
        }
        // Legacy pre-B2 entry: cellP was the per-cell blob probability, radius the blob
        // half-extent. size ≈ radius·4.5 keeps the per-vein block yield in the same
        // ballpark as the old ellipsoid.
        double cellP = doubleOrDefault(obj, "cellP", 0.1D);
        double radius = doubleOrDefault(obj, "radius", 2.5D);
        if (cellP <= 0.0D) {
            return List.of();
        }
        int size = Math.max(4, Math.min((int) Math.round(radius * 4.5D), MAX_VEIN_SIZE));
        return List.of(new Layer(size, cellP, Distribution.CELL, minY, maxY));
    }

    private static Distribution parseDistribution(@Nullable String raw, String id) {
        if (raw == null || raw.isEmpty()) {
            return Distribution.UNIFORM;
        }
        return switch (raw.toLowerCase(Locale.ROOT)) {
            case "uniform" -> Distribution.UNIFORM;
            case "triangle", "trapezoid" -> Distribution.TRIANGLE;
            case "cell" -> Distribution.CELL;
            default -> {
                EclipseMod.LOGGER.warn("Ore '{}' has unknown distribution '{}'; using uniform", id, raw);
                yield Distribution.UNIFORM;
            }
        };
    }

    private static Optional<Block> resolveBlock(String id) {
        ResourceLocation loc = ResourceLocation.tryParse(id);
        if (loc == null) {
            return Optional.empty();
        }
        return BuiltInRegistries.BLOCK.getOptional(loc);
    }

    private static double[] bandFactorOrDefault(JsonObject obj) {
        if (!obj.has("bandFactor") || !obj.get("bandFactor").isJsonArray()) {
            return FLAT_BANDS.clone();
        }
        JsonArray array = obj.getAsJsonArray("bandFactor");
        double[] factors = FLAT_BANDS.clone();
        for (int i = 0; i < Math.min(array.size(), factors.length); i++) {
            factors[i] = array.get(i).getAsDouble();
        }
        return factors;
    }

    @Nullable
    private static String stringOrNull(JsonObject obj, String key) {
        if (!obj.has(key) || obj.get(key).isJsonNull()) {
            return null;
        }
        return obj.get(key).getAsString();
    }

    private static int intOrDefault(JsonObject obj, String key, int fallback) {
        return obj.has(key) ? obj.get(key).getAsInt() : fallback;
    }

    private static double doubleOrDefault(JsonObject obj, String key, double fallback) {
        return obj.has(key) ? obj.get(key).getAsDouble() : fallback;
    }

    private static boolean boolOrDefault(JsonObject obj, String key, boolean fallback) {
        return obj.has(key) ? obj.get(key).getAsBoolean() : fallback;
    }

    // --- default ores.json ---
    // FINAL-DOPA-SOL §3 "Concrete fix": every ore must be mineable one stage BEFORE the
    // milestone that consumes it. Ladder: coal/copper/iron (+emerald) stage 0 (starting
    // disc), gold + Nether quartz/gold stage 1 (Nether opens day 2), redstone/lapis/
    // diamond stage 2 (post-milestone-2), netherite stage 2 in the Nether (second
    // annulus, day 10). Mod ores keep requiredMod.
    //
    // B2: size/count/distribution values are vanilla 1.21.1 (OreFeatures/OrePlacements).
    // Layers above the OVERWORLD_MAX_Y_CAP (coal upper y136+, iron upper y80+, gold
    // extra) are omitted — they can never place on the disc. The air-exposure "buried"
    // discard has no per-block equivalent here and is dropped; triangle masses above the
    // cap self-limit density exactly like vanilla's unreachable heights would (e.g.
    // emerald's 100@triangle(-16..480) yields only ~3.7 sub-cap veins per chunk).
    // Netherite deliberately KEEPS its event-tuned scarcity (way below vanilla): only
    // its vein shape/caliber went vanilla (sizes 3/2).

    /** Default {@code ores.json} root for freeze snapshots and first-run file creation. */
    public static JsonObject defaultRootJson() {
        return defaultRoot();
    }

    private static JsonObject defaultRoot() {
        JsonObject root = new JsonObject();
        root.add("overworld", defaultOverworld());
        root.add("nether", defaultNether());
        return root;
    }

    private static JsonArray defaultOverworld() {
        JsonArray array = new JsonArray();
        // Coal: vanilla ore_coal_lower — size 17 ("coal 17@large"), 20/chunk, triangle 0..192.
        array.add(ore("coal", "minecraft:coal_ore", "minecraft:deepslate_coal_ore",
                0, 192, 0, FLAT_BANDS, false, null,
                layer(17, 20.0D, "triangle", 0, 192)));
        // Copper: vanilla ore_copper (size 10, 16/chunk, triangle -16..112) plus a small
        // size-20 share standing in for the dripstone-cave ore_copper_large variant
        // (this per-block field has no biome routing).
        array.add(ore("copper", "minecraft:copper_ore", "minecraft:deepslate_copper_ore",
                -16, 112, 0, FLAT_BANDS, false, null,
                layer(10, 16.0D, "triangle", -16, 112),
                layer(20, 3.0D, "triangle", -16, 112)));
        // Iron stage 0: milestone L2 costs 48 iron (FINAL-DOPA-SOL §3). Vanilla
        // ore_iron_middle (9, 10/chunk, triangle -24..56) + ore_iron_small (4, 10/chunk,
        // uniform -64..72); ore_iron_upper lives above the cap.
        array.add(ore("iron", "minecraft:iron_ore", "minecraft:deepslate_iron_ore",
                -64, 72, 0, new double[] {1.0D, 1.25D, 1.1D, 0.9D, 0.9D, 0.7D}, false, null,
                layer(9, 10.0D, "triangle", -24, 56),
                layer(4, 10.0D, "uniform", -64, 72)));
        // Gold stage 1: milestone L3 costs 32 gold; band 1 exists from event start
        // (FINAL-DOPA-SOL §3). Vanilla ore_gold (9, 4/chunk, triangle -64..32) +
        // ore_gold_lower (9, avg 0.5/chunk, uniform -64..-48).
        array.add(ore("gold", "minecraft:gold_ore", "minecraft:deepslate_gold_ore",
                -64, 32, 1, new double[] {1.0D, 1.2D, 1.0D, 0.9D, 0.8D, 0.7D}, false, null,
                layer(9, 4.0D, "triangle", -64, 32),
                layer(9, 0.5D, "uniform", -64, -48)));
        // Redstone: vanilla ore_redstone (8, 4/chunk, uniform -64..15) + ore_redstone_lower
        // (8, 8/chunk, triangle -96..-32).
        array.add(ore("redstone", "minecraft:redstone_ore", "minecraft:deepslate_redstone_ore",
                -96, 15, 2, FLAT_BANDS, false, null,
                layer(8, 4.0D, "uniform", -64, 15),
                layer(8, 8.0D, "triangle", -96, -32)));
        // Lapis: vanilla ore_lapis (7, 2/chunk, triangle -32..32) + ore_lapis_buried
        // (7, 4/chunk, uniform -64..64).
        array.add(ore("lapis", "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore",
                -64, 64, 2, FLAT_BANDS, false, null,
                layer(7, 2.0D, "triangle", -32, 32),
                layer(7, 4.0D, "uniform", -64, 64)));
        // Diamond stage 2: milestone L4 (day 8) costs 24 diamonds (FINAL-DOPA-SOL §3).
        // Vanilla ore_diamond (4, 7/chunk) + medium (8, 2/chunk uniform -64..-4) + large
        // (12, rarity 1/9 => 0.111/chunk) + buried (8, 4/chunk), triangles -144..16.
        array.add(ore("diamond", "minecraft:diamond_ore", "minecraft:deepslate_diamond_ore",
                -144, 16, 2, new double[] {1.3D, 1.0D, 0.7D, 0.45D, 0.3D, 0.2D}, true, null,
                layer(4, 7.0D, "triangle", -144, 16),
                layer(8, 2.0D, "uniform", -64, -4),
                layer(12, 0.111D, "triangle", -144, 16),
                layer(8, 4.0D, "triangle", -144, 16)));
        // Emerald: vanilla ore_emerald (3, 100/chunk, triangle -16..480). The mass above
        // the y<=52 cap self-limits this to ~3.7 veins/chunk of size 3 — the vanilla
        // sub-surface emerald experience without biome routing.
        array.add(ore("emerald", "minecraft:emerald_ore", "minecraft:deepslate_emerald_ore",
                -16, 480, 0, FLAT_BANDS, false, null,
                layer(3, 100.0D, "triangle", -16, 480)));
        // Create zinc: no vanilla table — keeps its legacy event tuning as a CELL layer
        // (count = old cellP 0.18, size ≈ old radius 2.8 blob yield).
        array.add(ore("zinc", "create:zinc_ore", "create:deepslate_zinc_ore",
                -32, 52, 3, FLAT_BANDS, false, "create",
                layer(11, 0.18D, "cell", -32, 52)));
        return array;
    }

    private static JsonArray defaultNether() {
        JsonArray array = new JsonArray();
        // Stage 1 for quartz + Nether gold: the first Nether annulus opens on day 2
        // (FINAL-DOPA-SOL §3). Vanilla calibers/counts (ore_quartz_nether 14@16,
        // ore_gold_nether 10@10), spread uniformly over the disc's own gate band (the
        // disc floor/ceiling sit elsewhere than vanilla's 10..117 world band).
        array.add(ore("quartz", "minecraft:nether_quartz_ore", "minecraft:nether_quartz_ore",
                36, 140, 1, FLAT_BANDS, false, null,
                layer(14, 16.0D, "uniform", 36, 140)));
        array.add(ore("nether_gold", "minecraft:nether_gold_ore", "minecraft:nether_gold_ore",
                34, 110, 1, FLAT_BANDS, false, null,
                layer(10, 10.0D, "uniform", 34, 110)));
        // Deliberately still stage 2 AND deliberately far below vanilla density:
        // netherite is the L5 era and the day-10 second annulus is its intended window
        // (FINAL-DOPA-SOL §3). Vanilla vein calibers (large 3 / small 2), old total
        // rarity (~0.05 veins/chunk, ex-cellP 0.022).
        array.add(ore("netherite", "minecraft:ancient_debris", "minecraft:ancient_debris",
                34, 72, 2, FLAT_BANDS, true, null,
                layer(3, 0.033D, "triangle", 34, 72),
                layer(2, 0.021D, "uniform", 34, 72)));
        return array;
    }

    private static JsonObject ore(String id, String block, String deepslate, int minY, int maxY,
            int unlockStage, double[] bandFactor, boolean centerBias, @Nullable String requiredMod,
            JsonObject... layers) {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        obj.addProperty("block", block);
        obj.addProperty("deepslate", deepslate);
        obj.addProperty("minY", minY);
        obj.addProperty("maxY", maxY);
        obj.addProperty("unlockStage", unlockStage);
        obj.addProperty("centerBias", centerBias);
        JsonArray bands = new JsonArray();
        for (double factor : bandFactor) {
            bands.add(factor);
        }
        obj.add("bandFactor", bands);
        JsonArray layerArray = new JsonArray();
        for (JsonObject layer : layers) {
            layerArray.add(layer);
        }
        obj.add("layers", layerArray);
        if (requiredMod != null) {
            obj.addProperty("requiredMod", requiredMod);
        }
        return obj;
    }

    private static JsonObject layer(int size, double count, String distribution, int minY, int maxY) {
        JsonObject obj = new JsonObject();
        obj.addProperty("size", size);
        obj.addProperty("count", count);
        obj.addProperty("distribution", distribution);
        obj.addProperty("minY", minY);
        obj.addProperty("maxY", maxY);
        return obj;
    }
}
