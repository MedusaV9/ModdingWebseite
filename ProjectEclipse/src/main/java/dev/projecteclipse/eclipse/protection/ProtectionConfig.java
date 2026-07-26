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
 *
 * <p><b>ALTARFIX2 #2 self-migration:</b> the file carries a {@code configVersion}. A file
 * older than {@link #CONFIG_VERSION} whose {@code spawn.radius} is still the shipped
 * legacy default is rewritten in place to the new default (backed up as
 * {@code protection.json.bak-v<old>} first) and re-stamped, so the shrunken zone reaches
 * live saves without deleting configs. An operator-tuned radius is preserved untouched —
 * only the stamp is refreshed.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ProtectionConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE = "protection.json";
    /**
     * Version 2 = ALTARFIX2 #2: the broad gameplay/no-build zone shrank from
     * {@value #LEGACY_SPAWN_RADIUS} to {@value #DEFAULT_SPAWN_RADIUS} blocks (and with it
     * the fall-safe zone, which is {@code radius + edgeBandExtra}).
     */
    public static final int CONFIG_VERSION = 2;
    /** The pre-ALTARFIX2 default of {@code spawn.radius}; only THIS value is migrated. */
    private static final int LEGACY_SPAWN_RADIUS = 96;
    /**
     * ALTARFIX2 #2: {@code max(96 - 25, 24)}. Fall-damage safety is
     * {@code radius + edgeBandExtra} = {@value #DEFAULT_SPAWN_RADIUS} + 16 = 87 blocks
     * (was 112) — the same 25-block shave. The sanctum build cylinder
     * ({@code SanctumProtection.RADIUS} = 18) is deliberately NOT touched: it is the
     * altar plus its immediate platform and already sits below the 24-block floor.
     */
    private static final int DEFAULT_SPAWN_RADIUS = Math.max(LEGACY_SPAWN_RADIUS - 25, 24);

    private static volatile Snapshot current = Snapshot.defaults();
    private static volatile boolean loaded = false;
    private static volatile boolean reloadHookRegistered = false;

    private ProtectionConfig() {}

    /**
     * {@code noBuild} (plans_v5 PLAN-B B10, default true) extends the break/place/
     * explosion cancels from the r=18 sanctum cylinder to the whole broad spawn zone;
     * {@code buildRadius} (default 0 = use {@code radius()}) lets servers tune the
     * no-build ring independently of the PvP/grief ring.
     */
    public record SpawnRules(
            int radius,
            int verticalFrom,
            int verticalTo,
            boolean noBuild,
            int buildRadius,
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
                    new SpawnRules(DEFAULT_SPAWN_RADIUS, -64, 320, true, 0, true, true, true, true, true,
                            16, 3, true),
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
                migrateIfOutdated(file, root);
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

    /**
     * ALTARFIX2 #2 targeted migration: mutates {@code root} in place (and rewrites the
     * file) when its {@code configVersion} is older than {@link #CONFIG_VERSION}. Only a
     * {@code spawn.radius} that still holds the shipped legacy default is replaced — a
     * server that tuned the ring keeps its number and just gets the new stamp. The old
     * file is copied to {@code protection.json.bak-v<old>} first.
     */
    private static void migrateIfOutdated(Path file, JsonObject root) {
        int fileVersion = root.has("configVersion") ? root.get("configVersion").getAsInt() : 1;
        if (fileVersion >= CONFIG_VERSION) {
            return;
        }
        JsonObject spawn = root.has("spawn") && root.get("spawn").isJsonObject()
                ? root.getAsJsonObject("spawn") : null;
        boolean shrank = false;
        if (spawn != null && spawn.has("radius") && spawn.get("radius").getAsInt() == LEGACY_SPAWN_RADIUS) {
            spawn.addProperty("radius", DEFAULT_SPAWN_RADIUS);
            shrank = true;
        }
        root.addProperty("configVersion", CONFIG_VERSION);
        try {
            Files.copy(file, file.resolveSibling(file.getFileName() + ".bak-v" + fileVersion),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.warn("{} migrated v{} -> v{}{} (old file kept as {}.bak-v{})",
                    file.getFileName(), fileVersion, CONFIG_VERSION,
                    shrank ? "; spawn.radius " + LEGACY_SPAWN_RADIUS + " -> " + DEFAULT_SPAWN_RADIUS
                            + " (fall-safe zone shrinks with it)"
                            : "; spawn.radius left at its operator value",
                    file.getFileName(), fileVersion);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write migrated config {} — running with the in-memory "
                    + "migration only", file, e);
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
                boolOr(obj, "noBuild", fallback.noBuild()),
                intOr(obj, "buildRadius", fallback.buildRadius()),
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
        root.addProperty("configVersion", CONFIG_VERSION);

        JsonObject spawn = new JsonObject();
        spawn.addProperty("radius", defaults.spawn().radius());
        spawn.addProperty("verticalFrom", defaults.spawn().verticalFrom());
        spawn.addProperty("verticalTo", defaults.spawn().verticalTo());
        spawn.addProperty("noBuild", defaults.spawn().noBuild());
        spawn.addProperty("buildRadius", defaults.spawn().buildRadius());
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
