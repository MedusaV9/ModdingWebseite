package dev.projecteclipse.eclipse.protection;

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
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Loads {@code config/eclipse/protection.json} for spawn-protection toggles, villager
 * restrictions, and day-1 containment. Zone geometry for break/place remains
 * {@link dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection#isProtected} (P6).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ProtectionConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE = "protection.json";

    private static volatile Snapshot current = Snapshot.defaults();
    private static volatile boolean loaded = false;
    private static volatile boolean reloadHookRegistered = false;

    private ProtectionConfig() {}

    public record SpawnRules(
            int radius,
            int verticalFrom,
            int verticalTo,
            boolean noPvp,
            boolean noFluidPlace,
            boolean noVehiclePlace,
            boolean noMobGriefing,
            boolean noFallDamage,
            int edgeBandExtra,
            int exemptPermission,
            boolean exemptCreative) {}

    public record VillagerRules(
            boolean blockLibrarian,
            boolean blockEnchantedBookTrades,
            boolean disableWanderingTrader) {}

    public record ContainmentRules(List<Integer> containmentDays, int bounceY) {
        public ContainmentRules {
            containmentDays = List.copyOf(containmentDays);
        }
    }

    public record Snapshot(SpawnRules spawn, VillagerRules villagers, ContainmentRules containment) {
        static Snapshot defaults() {
            return new Snapshot(
                    new SpawnRules(96, -64, 320, true, true, true, true, true, 16, 3, true),
                    new VillagerRules(true, true, true),
                    new ContainmentRules(List.of(1), -180));
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
            EclipseMod.LOGGER.error("Failed to create protection config directory {}", configDir, e);
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
        EclipseMod.LOGGER.info("Protection config loaded");
    }

    public static synchronized void reloadDefault() {
        reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (!reloadHookRegistered) {
            ReloadHooks.register("protection", ProtectionConfig::reloadDefault);
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
        Snapshot defaults = Snapshot.defaults();
        SpawnRules spawn = parseSpawn(root.has("spawn") ? root.getAsJsonObject("spawn") : new JsonObject(), defaults.spawn());
        VillagerRules villagers = parseVillagers(
                root.has("villagers") ? root.getAsJsonObject("villagers") : new JsonObject(), defaults.villagers());
        ContainmentRules containment = parseContainment(
                root.has("containment") ? root.getAsJsonObject("containment") : new JsonObject(), defaults.containment());
        return new Snapshot(spawn, villagers, containment);
    }

    private static SpawnRules parseSpawn(JsonObject obj, SpawnRules fallback) {
        return new SpawnRules(
                intOr(obj, "radius", fallback.radius()),
                intOr(obj, "verticalFrom", fallback.verticalFrom()),
                intOr(obj, "verticalTo", fallback.verticalTo()),
                boolOr(obj, "noPvp", fallback.noPvp()),
                boolOr(obj, "noFluidPlace", fallback.noFluidPlace()),
                boolOr(obj, "noVehiclePlace", fallback.noVehiclePlace()),
                boolOr(obj, "noMobGriefing", fallback.noMobGriefing()),
                boolOr(obj, "noFallDamage", fallback.noFallDamage()),
                intOr(obj, "edgeBandExtra", fallback.edgeBandExtra()),
                intOr(obj, "exemptPermission", fallback.exemptPermission()),
                boolOr(obj, "exemptCreative", fallback.exemptCreative()));
    }

    private static VillagerRules parseVillagers(JsonObject obj, VillagerRules fallback) {
        return new VillagerRules(
                boolOr(obj, "blockLibrarian", fallback.blockLibrarian()),
                boolOr(obj, "blockEnchantedBookTrades", fallback.blockEnchantedBookTrades()),
                boolOr(obj, "disableWanderingTrader", fallback.disableWanderingTrader()));
    }

    private static ContainmentRules parseContainment(JsonObject obj, ContainmentRules fallback) {
        List<Integer> days = new ArrayList<>();
        if (obj.has("containmentDays") && obj.get("containmentDays").isJsonArray()) {
            for (JsonElement element : obj.getAsJsonArray("containmentDays")) {
                days.add(element.getAsInt());
            }
        } else {
            days.addAll(fallback.containmentDays());
        }
        return new ContainmentRules(days, intOr(obj, "bounceY", fallback.bounceY()));
    }

    private static int intOr(JsonObject obj, String key, int fallback) {
        return obj.has(key) ? obj.get(key).getAsInt() : fallback;
    }

    private static boolean boolOr(JsonObject obj, String key, boolean fallback) {
        return obj.has(key) ? obj.get(key).getAsBoolean() : fallback;
    }

    private static JsonObject defaultRoot() {
        Snapshot defaults = Snapshot.defaults();
        JsonObject root = new JsonObject();

        JsonObject spawn = new JsonObject();
        spawn.addProperty("radius", defaults.spawn().radius());
        spawn.addProperty("verticalFrom", defaults.spawn().verticalFrom());
        spawn.addProperty("verticalTo", defaults.spawn().verticalTo());
        spawn.addProperty("noPvp", defaults.spawn().noPvp());
        spawn.addProperty("noFluidPlace", defaults.spawn().noFluidPlace());
        spawn.addProperty("noVehiclePlace", defaults.spawn().noVehiclePlace());
        spawn.addProperty("noMobGriefing", defaults.spawn().noMobGriefing());
        spawn.addProperty("noFallDamage", defaults.spawn().noFallDamage());
        spawn.addProperty("edgeBandExtra", defaults.spawn().edgeBandExtra());
        spawn.addProperty("exemptPermission", defaults.spawn().exemptPermission());
        spawn.addProperty("exemptCreative", defaults.spawn().exemptCreative());
        root.add("spawn", spawn);

        JsonObject villagers = new JsonObject();
        villagers.addProperty("blockLibrarian", defaults.villagers().blockLibrarian());
        villagers.addProperty("blockEnchantedBookTrades", defaults.villagers().blockEnchantedBookTrades());
        villagers.addProperty("disableWanderingTrader", defaults.villagers().disableWanderingTrader());
        root.add("villagers", villagers);

        JsonObject containment = new JsonObject();
        JsonArray days = new JsonArray();
        for (int day : defaults.containment().containmentDays()) {
            days.add(day);
        }
        containment.add("containmentDays", days);
        containment.addProperty("bounceY", defaults.containment().bounceY());
        root.add("containment", containment);

        return root;
    }
}
