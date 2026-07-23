package dev.projecteclipse.eclipse.progression;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;

/**
 * Loads {@code config/eclipse/recipegate.json} (day-tier recipe locks). Hot-reload via
 * {@link ReloadHooks} when {@code /eclipse reload} runs.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RecipeGateConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE = "recipegate.json";

    private static volatile Snapshot current = Snapshot.empty();
    private static volatile boolean loaded = false;
    private static volatile boolean reloadHookRegistered = false;

    private RecipeGateConfig() {}

    /** One unlock tier: entries stay locked while {@code currentDay < unlockDay}. */
    public record Tier(int unlockDay, List<String> items, List<String> recipes) {
        public Tier {
            items = List.copyOf(items);
            recipes = List.copyOf(recipes);
        }
    }

    public record Snapshot(List<Tier> tiers) {
        static Snapshot empty() {
            return new Snapshot(List.of());
        }
    }

    public static Snapshot current() {
        ensureLoaded();
        return current;
    }

    public static synchronized void reload(Path configDir) {
        Path file = configDir.resolve(FILE);
        try {
            Files.createDirectories(configDir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create recipe gate config directory {}", configDir, e);
        }

        JsonObject root;
        if (!Files.exists(file)) {
            root = defaultRoot();
            try {
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        } else {
            try {
                root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error("Failed to read config {}; using built-in defaults", file, e);
                root = defaultRoot();
            }
        }

        current = parseRoot(root);
        loaded = true;
        EclipseMod.LOGGER.info("Recipe gate config loaded ({} tier(s))", current.tiers().size());
    }

    public static synchronized void reloadDefault() {
        reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (!reloadHookRegistered) {
            ReloadHooks.register("recipegate", RecipeGateConfig::reloadDefault);
            reloadHookRegistered = true;
        }
        reloadDefault();
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reloadDefault();
        }
    }

    private static Snapshot parseRoot(JsonObject root) {
        if (!root.has("tiers") || !root.get("tiers").isJsonArray()) {
            return Snapshot.empty();
        }
        JsonArray array = root.getAsJsonArray("tiers");
        List<Tier> tiers = new ArrayList<>(array.size());
        for (JsonElement element : array) {
            if (!element.isJsonObject()) {
                continue;
            }
            JsonObject tierObj = element.getAsJsonObject();
            int unlockDay = tierObj.has("unlockDay") ? tierObj.get("unlockDay").getAsInt() : 1;
            JsonObject locks = tierObj.has("locks") && tierObj.get("locks").isJsonObject()
                    ? tierObj.getAsJsonObject("locks")
                    : new JsonObject();
            List<String> items = readStringList(locks, "items");
            List<String> recipes = readStringList(locks, "recipes");
            tiers.add(new Tier(Math.max(1, unlockDay), items, recipes));
        }
        return new Snapshot(List.copyOf(tiers));
    }

    private static List<String> readStringList(JsonObject obj, String key) {
        if (!obj.has(key) || !obj.get(key).isJsonArray()) {
            return List.of();
        }
        JsonArray array = obj.getAsJsonArray(key);
        List<String> out = new ArrayList<>(array.size());
        for (JsonElement element : array) {
            if (element.isJsonPrimitive()) {
                out.add(element.getAsString());
            }
        }
        return out;
    }

    private static JsonObject defaultRoot() {
        JsonObject root = new JsonObject();
        JsonArray tiers = new JsonArray();

        JsonObject tier1 = new JsonObject();
        tier1.addProperty("unlockDay", 1);
        JsonObject locks1 = new JsonObject();
        JsonArray items1 = new JsonArray();
        items1.add("#eclipse:tier_diamond_gear");
        items1.add("#eclipse:tier_netherite_gear");
        items1.add("minecraft:enchanting_table");
        items1.add("minecraft:anvil");
        locks1.add("items", items1);
        locks1.add("recipes", new JsonArray());
        tier1.add("locks", locks1);
        tiers.add(tier1);

        JsonObject tier2 = new JsonObject();
        tier2.addProperty("unlockDay", 5);
        JsonObject locks2 = new JsonObject();
        JsonArray items2 = new JsonArray();
        items2.add("#eclipse:tier_diamond_gear");
        locks2.add("items", items2);
        tier2.add("locks", locks2);
        tiers.add(tier2);

        JsonObject tier3 = new JsonObject();
        tier3.addProperty("unlockDay", 10);
        JsonObject locks3 = new JsonObject();
        JsonArray items3 = new JsonArray();
        items3.add("#eclipse:tier_netherite_gear");
        locks3.add("items", items3);
        tier3.add("locks", locks3);
        tiers.add(tier3);

        root.add("tiers", tiers);
        return root;
    }
}
