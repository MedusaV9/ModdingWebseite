package dev.projecteclipse.eclipse.xboxevent;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.DevReloadRegistry;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/xboxevent.json} (plan §2.13.7). Missing file is created
 * with defaults on first load; parse errors keep the previous (or default) values in memory
 * (temp-parse-then-swap, the {@code EclipseConfig} pattern). Registered in
 * {@link DevReloadRegistry} so {@code /dev reload} step 4 covers it.
 *
 * <p>{@code announceKeys} — when {@code true} (default) announcements/titles use the
 * translatable world-name keys from the P5-W7 langdrop ({@code eclipse.xboxworld.<id>.name},
 * clients resolve per-locale); when {@code false} the literal English display name from the
 * manifest is used verbatim.</p>
 */
public final class XboxEventConfig {

    /** Immutable snapshot of the config file. */
    public record Values(
            int defaultMinutes,
            String rewardBuffId,
            int rewardMinutes,
            int portalSearchMinRadius,
            int portalSearchMaxRadius,
            boolean announceKeys,
            List<String> worlds) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final AtomicBoolean BOOTSTRAPPED = new AtomicBoolean();

    private static volatile Values values = defaults();

    private XboxEventConfig() {}

    public static Values get() {
        return values;
    }

    /** Registers the {@code /dev reload} hook and performs the initial load. Idempotent. */
    public static void bootstrap() {
        if (BOOTSTRAPPED.compareAndSet(false, true)) {
            DevReloadRegistry.register("xboxevent.json", XboxEventConfig::reload);
            reload();
        }
    }

    /** Re-reads the file; creates it with defaults when absent. Never leaves half-applied state. */
    public static void reload() {
        Path file = configFile();
        try {
            if (!Files.exists(file)) {
                writeDefaults(file);
            }
            String raw = Files.readString(file, StandardCharsets.UTF_8);
            Values parsed = parse(JsonParser.parseString(raw).getAsJsonObject());
            values = parsed;
            EclipseMod.LOGGER.info("Loaded {} (defaultMinutes={}, reward={} {}min, worlds={})",
                    file, parsed.defaultMinutes(), parsed.rewardBuffId(), parsed.rewardMinutes(), parsed.worlds());
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {} — keeping previous values", file, e);
        }
    }

    private static Path configFile() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("xboxevent.json");
    }

    private static Values defaults() {
        return new Values(30, "double_skill_xp", 60, 8, 24, true, List.of("tu1", "tu12", "tu14"));
    }

    private static Values parse(JsonObject root) {
        Values def = defaults();
        int defaultMinutes = root.has("defaultMinutes") ? root.get("defaultMinutes").getAsInt() : def.defaultMinutes();

        String rewardBuffId = def.rewardBuffId();
        int rewardMinutes = def.rewardMinutes();
        if (root.has("reward") && root.get("reward").isJsonObject()) {
            JsonObject reward = root.getAsJsonObject("reward");
            if (reward.has("buffId")) {
                rewardBuffId = reward.get("buffId").getAsString();
            }
            if (reward.has("minutes")) {
                rewardMinutes = reward.get("minutes").getAsInt();
            }
        }

        int searchMin = def.portalSearchMinRadius();
        int searchMax = def.portalSearchMaxRadius();
        if (root.has("portal") && root.get("portal").isJsonObject()) {
            JsonObject portal = root.getAsJsonObject("portal");
            if (portal.has("searchMinRadius")) {
                searchMin = portal.get("searchMinRadius").getAsInt();
            }
            if (portal.has("searchMaxRadius")) {
                searchMax = portal.get("searchMaxRadius").getAsInt();
            }
        }
        if (searchMax < searchMin) {
            int swap = searchMin;
            searchMin = searchMax;
            searchMax = swap;
        }

        boolean announceKeys = !root.has("announceKeys") || root.get("announceKeys").getAsBoolean();

        List<String> worlds = new ArrayList<>();
        if (root.has("worlds") && root.get("worlds").isJsonArray()) {
            for (JsonElement world : root.getAsJsonArray("worlds")) {
                worlds.add(world.getAsString());
            }
        }
        if (worlds.isEmpty()) {
            worlds = def.worlds();
        }

        return new Values(Math.max(1, defaultMinutes), rewardBuffId, Math.max(1, rewardMinutes),
                Math.max(1, searchMin), Math.max(1, searchMax), announceKeys, List.copyOf(worlds));
    }

    private static void writeDefaults(Path file) throws IOException {
        Values def = defaults();
        JsonObject root = new JsonObject();
        root.addProperty("defaultMinutes", def.defaultMinutes());
        JsonObject reward = new JsonObject();
        reward.addProperty("buffId", def.rewardBuffId());
        reward.addProperty("minutes", def.rewardMinutes());
        root.add("reward", reward);
        JsonObject portal = new JsonObject();
        portal.addProperty("searchMinRadius", def.portalSearchMinRadius());
        portal.addProperty("searchMaxRadius", def.portalSearchMaxRadius());
        root.add("portal", portal);
        root.addProperty("announceKeys", def.announceKeys());
        com.google.gson.JsonArray worlds = new com.google.gson.JsonArray();
        def.worlds().forEach(worlds::add);
        root.add("worlds", worlds);

        Files.createDirectories(file.getParent());
        Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
        EclipseMod.LOGGER.info("Created default {}", file);
    }
}
