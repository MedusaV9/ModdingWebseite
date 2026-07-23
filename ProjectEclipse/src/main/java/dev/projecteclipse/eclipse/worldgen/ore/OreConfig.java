package dev.projecteclipse.eclipse.worldgen.ore;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
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
 */
public final class OreConfig {
    /** Hard ceiling for overworld ore blobs — prevents surface-exposed boulders (D5 / req 8). */
    public static final int OVERWORLD_MAX_Y_CAP = 52;

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

    /** One validated ore entry ready for placement. */
    public record ResolvedOre(String id, int salt, Block stoneOre, Block deepOre, int minY, int maxY,
            double cellP, double radius, int unlockStage, double[] bandFactor, boolean centerBias) {}

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

        double cellP = doubleOrDefault(obj, "cellP", 0.1D);
        double radius = doubleOrDefault(obj, "radius", 2.5D);
        int unlockStage = intOrDefault(obj, "unlockStage", 0);
        boolean centerBias = boolOrDefault(obj, "centerBias", false);
        double[] bandFactor = bandFactorOrDefault(obj);

        return new ResolvedOre(id, salt, stone.get(), deep, minY, maxY, cellP, radius, unlockStage, bandFactor,
                centerBias);
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

    // --- default ores.json (day-gating: coal/copper stage-1, iron/gold/quartz stage-2,
    // diamond/netherite stage-3+, mod ores gated by requiredMod) ---

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
        array.add(ore("coal", "minecraft:coal_ore", "minecraft:deepslate_coal_ore",
                -32, 52, 0.30D, 3.2D, 0, FLAT_BANDS, false, null));
        array.add(ore("copper", "minecraft:copper_ore", "minecraft:deepslate_copper_ore",
                -20, 52, 0.22D, 3.0D, 0, FLAT_BANDS, false, null));
        array.add(ore("iron", "minecraft:iron_ore", "minecraft:deepslate_iron_ore",
                -64, 52, 0.30D, 2.8D, 2, new double[] {1.0D, 1.25D, 1.1D, 0.9D, 0.9D, 0.7D}, false, null));
        array.add(ore("gold", "minecraft:gold_ore", "minecraft:deepslate_gold_ore",
                -64, -8, 0.11D, 2.6D, 2, new double[] {1.0D, 1.2D, 1.0D, 0.9D, 0.8D, 0.7D}, false, null));
        array.add(ore("redstone", "minecraft:redstone_ore", "minecraft:deepslate_redstone_ore",
                -96, -24, 0.13D, 2.8D, 2, FLAT_BANDS, false, null));
        array.add(ore("lapis", "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore",
                -80, -16, 0.07D, 2.4D, 2, FLAT_BANDS, false, null));
        array.add(ore("diamond", "minecraft:diamond_ore", "minecraft:deepslate_diamond_ore",
                -125, -40, 0.12D, 2.4D, 3,
                new double[] {1.3D, 1.0D, 0.7D, 0.45D, 0.3D, 0.2D}, true, null));
        array.add(ore("zinc", "create:zinc_ore", "create:deepslate_zinc_ore",
                -32, 52, 0.18D, 2.8D, 3, FLAT_BANDS, false, "create"));
        return array;
    }

    private static JsonArray defaultNether() {
        JsonArray array = new JsonArray();
        array.add(ore("quartz", "minecraft:nether_quartz_ore", "minecraft:nether_quartz_ore",
                36, 140, 0.25D, 3.0D, 2, FLAT_BANDS, false, null));
        array.add(ore("nether_gold", "minecraft:nether_gold_ore", "minecraft:nether_gold_ore",
                34, 110, 0.14D, 2.6D, 2, FLAT_BANDS, false, null));
        array.add(ore("netherite", "minecraft:ancient_debris", "minecraft:ancient_debris",
                34, 72, 0.022D, 1.6D, 3, FLAT_BANDS, true, null));
        return array;
    }

    private static JsonObject ore(String id, String block, String deepslate, int minY, int maxY, double cellP,
            double radius, int unlockStage, double[] bandFactor, boolean centerBias,
            @Nullable String requiredMod) {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        obj.addProperty("block", block);
        obj.addProperty("deepslate", deepslate);
        obj.addProperty("minY", minY);
        obj.addProperty("maxY", maxY);
        obj.addProperty("cellP", cellP);
        obj.addProperty("radius", radius);
        obj.addProperty("unlockStage", unlockStage);
        obj.addProperty("centerBias", centerBias);
        JsonArray bands = new JsonArray();
        for (double factor : bandFactor) {
            bands.add(factor);
        }
        obj.add("bandFactor", bands);
        if (requiredMod != null) {
            obj.addProperty("requiredMod", requiredMod);
        }
        return obj;
    }
}
