package dev.projecteclipse.eclipse.worldgen.end;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Reloadable {@code end.json} settings for the overworld End-disc event.
 *
 * <p>Fresh saves receive a save-local copy through {@link FrozenParams}; once a save is
 * active this loader deliberately reads that frozen copy. The {@code /eclipse reload}
 * path reaches {@link #reloadCurrent()} through {@link ReloadHooks}. Geometry fields are
 * parsed for the public config contract but constrained to {@link DiscProfile}'s values:
 * {@code EndDiscGeometry} and the chunk generator are pure, fixed geometry, so accepting
 * different live-writer values would create seams in chunks generated after the event.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndConfig {
    private static final Gson GSON =
            new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    public static final int MAX_CRYSTALS = 8;
    private static final int DEFAULT_BLOCK_BUDGET = 768;
    private static final int DEFAULT_VICTORY_XP = 12_000;

    /**
     * F-023 timeline slots. The authored {@code days.json} plan reserves day 7 for the
     * Herald ({@code HeraldsLureItem.HERALD_DAY}), day 12 for "THE SKY SHARD" (the End
     * disc arriving) and day 13 for "THE DRAGON" — the pre-F-023 default fired the disc
     * on day 9 and started the dragon the second the materialization writer finished, so
     * both End beats landed on one day, days ahead of their authored slots and right on
     * top of the Herald window on any save that caught up past day 7 in one session.
     */
    private static final String DEFAULT_TRIGGER = "day:12";
    private static final int DEFAULT_DRAGON_DAY = 13;
    /** The pre-F-023 default trigger, remapped once on {@code configVersion}-less files. */
    private static final String LEGACY_TRIGGER = "day:9";
    /** Bumped whenever a default table below needs to reach existing saves. */
    private static final int CONFIG_VERSION = 2;

    /** Immutable snapshot swapped atomically on reload. */
    public record Snapshot(
            String trigger,
            int centerX,
            int centerZ,
            int surfaceY,
            int radius,
            int crystalCount,
            float dragonHealth,
            boolean simpleDragonAi,
            boolean allowElytra,
            boolean crystalRespawn,
            String lootTable,
            String elytraLootTable,
            int victoryXp,
            int blockBudgetPerTick,
            int dragonDay) {}

    private static volatile Snapshot current = defaults();

    static {
        ReloadHooks.register("end", EndConfig::reloadCurrent);
    }

    private EndConfig() {}

    public static Snapshot current() {
        return current;
    }

    /**
     * Reloads the active save-local copy, or the global config before a save is active.
     * This is the safe target for both config reload hooks and server lifecycle events.
     */
    public static synchronized void reloadCurrent() {
        Path saveDir = FrozenParams.saveEclipseDir();
        reload(saveDir != null ? saveDir : FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Reads (or creates) {@code end.json} in {@code configDir}. */
    public static synchronized void reload(Path configDir) {
        Path file = configDir.resolve("end.json");
        JsonObject root = defaultRoot();
        try {
            Files.createDirectories(configDir);
            if (Files.isRegularFile(file)) {
                root = JsonParser.parseString(
                        Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
                migrate(file, root);
            } else {
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created End-disc config {}", file);
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {}; using safe End-disc defaults", file, e);
        }

        try {
            current = parse(root);
        } catch (RuntimeException e) {
            current = defaults();
            EclipseMod.LOGGER.error("Invalid values in {}; using safe End-disc defaults", file, e);
        }
        EclipseMod.LOGGER.info(
                "End config loaded: trigger={}, dragonDay={}, center=({},{}), y={}, r={}, crystals={}, "
                        + "dragon={} HP, elytra={}",
                current.trigger(), current.dragonDay(), current.centerX(), current.centerZ(),
                current.surfaceY(), current.radius(), current.crystalCount(),
                current.dragonHealth(), current.allowElytra());
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        reloadCurrent();
    }

    /**
     * F-023 self-migration (the v5 {@code configVersion} doctrine): a save frozen before
     * the End slots moved carries no {@code configVersion} and the legacy {@code day:9}
     * trigger. Such a file is backed up once and rewritten onto the authored day-12 slot
     * with the new {@code dragonDay} key; an operator who deliberately edited the trigger
     * keeps it (only the exact legacy value is remapped).
     */
    private static void migrate(Path file, JsonObject root) {
        if (root.has("configVersion") && root.get("configVersion").getAsInt() >= CONFIG_VERSION) {
            return;
        }
        boolean legacyTrigger = LEGACY_TRIGGER.equals(string(root, "trigger", DEFAULT_TRIGGER));
        if (legacyTrigger) {
            root.addProperty("trigger", DEFAULT_TRIGGER);
        }
        if (!root.has("dragonDay")) {
            root.addProperty("dragonDay", DEFAULT_DRAGON_DAY);
        }
        root.addProperty("configVersion", CONFIG_VERSION);
        try {
            Files.copy(file, file.resolveSibling("end.json.bak-v1"),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info(
                    "Migrated {} to configVersion {} (trigger {}{}, dragonDay {}); backup written",
                    file, CONFIG_VERSION, string(root, "trigger", DEFAULT_TRIGGER),
                    legacyTrigger ? " — remapped off the legacy " + LEGACY_TRIGGER : "",
                    integer(root, "dragonDay", DEFAULT_DRAGON_DAY));
        } catch (IOException e) {
            // The in-memory migration still applies; only the persisted copy stays old.
            EclipseMod.LOGGER.warn("Could not persist the migrated {}", file, e);
        }
    }

    private static Snapshot parse(JsonObject root) {
        Snapshot fallback = defaults();
        String trigger = string(root, "trigger", fallback.trigger());
        int requestedX = integer(root, "centerX", fallback.centerX());
        int requestedZ = integer(root, "centerZ", fallback.centerZ());
        int requestedY = integer(root, "surfaceY", fallback.surfaceY());
        int requestedRadius = integer(root, "radius", fallback.radius());
        warnFixedGeometry("centerX", requestedX, fallback.centerX());
        warnFixedGeometry("centerZ", requestedZ, fallback.centerZ());
        warnFixedGeometry("surfaceY", requestedY, fallback.surfaceY());
        warnFixedGeometry("radius", requestedRadius, fallback.radius());

        return new Snapshot(
                trigger,
                fallback.centerX(),
                fallback.centerZ(),
                fallback.surfaceY(),
                fallback.radius(),
                clamp(integer(root, "crystalCount", fallback.crystalCount()), 1, MAX_CRYSTALS),
                clamp((float) decimal(root, "dragonHealth", fallback.dragonHealth()), 1.0F, 2048.0F),
                bool(root, "simpleDragonAi", fallback.simpleDragonAi()),
                bool(root, "allowElytra", fallback.allowElytra()),
                bool(root, "crystalRespawn", fallback.crystalRespawn()),
                string(root, "lootTable", fallback.lootTable()),
                string(root, "elytraLootTable", fallback.elytraLootTable()),
                clamp(integer(root, "victoryXp", fallback.victoryXp()), 0, 1_000_000),
                clamp(integer(root, "blockBudgetPerTick", fallback.blockBudgetPerTick()), 16, 8192),
                clamp(integer(root, "dragonDay", fallback.dragonDay()), 1, 999));
    }

    private static void warnFixedGeometry(String field, int requested, int supported) {
        if (requested != supported) {
            EclipseMod.LOGGER.warn(
                    "end.json {}={} cannot be applied while EndDiscGeometry is fixed at {}; using {}",
                    field, requested, supported, supported);
        }
    }

    private static Snapshot defaults() {
        return new Snapshot(
                DEFAULT_TRIGGER,
                DiscProfile.END_DISC_CENTER_X,
                DiscProfile.END_DISC_CENTER_Z,
                DiscProfile.END_DISC_SURFACE_Y,
                DiscProfile.END_DISC_RADIUS,
                MAX_CRYSTALS,
                300.0F,
                true,
                false,
                false,
                "eclipse:end_city/cache",
                "eclipse:end_city/cache_with_elytra",
                DEFAULT_VICTORY_XP,
                DEFAULT_BLOCK_BUDGET,
                DEFAULT_DRAGON_DAY);
    }

    private static JsonObject defaultRoot() {
        Snapshot defaults = defaults();
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Frozen per save. Geometry fields require matching EndDiscGeometry values. "
                + "trigger = the day the sky shard arrives (days.json day 12); dragonDay = the day the dragon "
                + "wakes on it (days.json day 13). Both must stay clear of the day-7 Herald window.");
        root.addProperty("configVersion", CONFIG_VERSION);
        root.addProperty("trigger", defaults.trigger());
        root.addProperty("dragonDay", defaults.dragonDay());
        root.addProperty("centerX", defaults.centerX());
        root.addProperty("centerZ", defaults.centerZ());
        root.addProperty("surfaceY", defaults.surfaceY());
        root.addProperty("radius", defaults.radius());
        root.addProperty("crystalCount", defaults.crystalCount());
        root.addProperty("dragonHealth", defaults.dragonHealth());
        root.addProperty("simpleDragonAi", defaults.simpleDragonAi());
        root.addProperty("allowElytra", defaults.allowElytra());
        root.addProperty("crystalRespawn", defaults.crystalRespawn());
        root.addProperty("lootTable", defaults.lootTable());
        root.addProperty("elytraLootTable", defaults.elytraLootTable());
        root.addProperty("victoryXp", defaults.victoryXp());
        root.addProperty("blockBudgetPerTick", defaults.blockBudgetPerTick());
        return root;
    }

    private static String string(JsonObject root, String key, String fallback) {
        return root.has(key) ? root.get(key).getAsString() : fallback;
    }

    private static int integer(JsonObject root, String key, int fallback) {
        return root.has(key) ? root.get(key).getAsInt() : fallback;
    }

    private static double decimal(JsonObject root, String key, double fallback) {
        return root.has(key) ? root.get(key).getAsDouble() : fallback;
    }

    private static boolean bool(JsonObject root, String key, boolean fallback) {
        return root.has(key) ? root.get(key).getAsBoolean() : fallback;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }
}
