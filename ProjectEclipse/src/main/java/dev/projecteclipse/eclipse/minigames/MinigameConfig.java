package dev.projecteclipse.eclipse.minigames;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/minigames.json} (the {@code XboxEventConfig} pattern:
 * missing file is created with defaults, parse errors keep the previous values in memory,
 * registered in {@link ReloadHooks} so {@code /eclipse reload} and {@code /dev reload}
 * both refresh it).
 *
 * <p>Rewards are shard + skill-XP amounts paid through the existing APIs
 * ({@code ShardEconomy.addShards}, {@code SkillsApi.addXp}): {@code participation*} is
 * granted once per event instance to every participant on their exit; {@code podium*}
 * index 0/1/2 pays the anonymized top-3 of an arena round and the first three race
 * finishers.</p>
 */
public final class MinigameConfig {

    /** Immutable snapshot of the config file. */
    public record Values(
            int defaultMinutes,
            int roundMinutes,
            int portalSearchMinRadius,
            int portalSearchMaxRadius,
            int participationShards,
            int participationSkillXp,
            List<Integer> podiumShards,
            List<Integer> podiumSkillXp) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final AtomicBoolean BOOTSTRAPPED = new AtomicBoolean();

    private static volatile Values values = defaults();

    private MinigameConfig() {}

    public static Values get() {
        return values;
    }

    /** Registers the shared reload hook and performs the initial load. Idempotent. */
    public static void bootstrap() {
        if (BOOTSTRAPPED.compareAndSet(false, true)) {
            ReloadHooks.register("minigames.json", MinigameConfig::reload);
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
            EclipseMod.LOGGER.info(
                    "Loaded {} (defaultMinutes={}, roundMinutes={}, participation={}s/{}xp, podium={}s/{}xp)",
                    file, parsed.defaultMinutes(), parsed.roundMinutes(),
                    parsed.participationShards(), parsed.participationSkillXp(),
                    parsed.podiumShards(), parsed.podiumSkillXp());
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {} — keeping previous values", file, e);
        }
    }

    private static Path configFile() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("minigames.json");
    }

    private static Values defaults() {
        return new Values(30, 5, 8, 24, 2, 40, List.of(8, 5, 3), List.of(120, 80, 50));
    }

    private static Values parse(JsonObject root) {
        Values def = defaults();
        int defaultMinutes = root.has("defaultMinutes")
                ? root.get("defaultMinutes").getAsInt() : def.defaultMinutes();
        int roundMinutes = root.has("roundMinutes")
                ? root.get("roundMinutes").getAsInt() : def.roundMinutes();

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

        int participationShards = def.participationShards();
        int participationSkillXp = def.participationSkillXp();
        List<Integer> podiumShards = def.podiumShards();
        List<Integer> podiumSkillXp = def.podiumSkillXp();
        if (root.has("reward") && root.get("reward").isJsonObject()) {
            JsonObject reward = root.getAsJsonObject("reward");
            if (reward.has("participationShards")) {
                participationShards = reward.get("participationShards").getAsInt();
            }
            if (reward.has("participationSkillXp")) {
                participationSkillXp = reward.get("participationSkillXp").getAsInt();
            }
            podiumShards = intList(reward, "podiumShards", podiumShards);
            podiumSkillXp = intList(reward, "podiumSkillXp", podiumSkillXp);
        }

        return new Values(Math.max(1, defaultMinutes), Math.max(1, roundMinutes),
                Math.max(1, searchMin), Math.max(1, searchMax),
                Math.max(0, participationShards), Math.max(0, participationSkillXp),
                padToThree(podiumShards), padToThree(podiumSkillXp));
    }

    private static List<Integer> intList(JsonObject parent, String key, List<Integer> fallback) {
        if (!parent.has(key) || !parent.get(key).isJsonArray()) {
            return fallback;
        }
        List<Integer> out = new ArrayList<>();
        for (JsonElement element : parent.getAsJsonArray(key)) {
            out.add(Math.max(0, element.getAsInt()));
        }
        return out.isEmpty() ? fallback : out;
    }

    /** Podium lists are always addressed with index 0..2 — pad short configs with zeros. */
    private static List<Integer> padToThree(List<Integer> list) {
        List<Integer> out = new ArrayList<>(list);
        while (out.size() < 3) {
            out.add(0);
        }
        return List.copyOf(out.subList(0, 3));
    }

    private static void writeDefaults(Path file) throws IOException {
        Values def = defaults();
        JsonObject root = new JsonObject();
        root.addProperty("defaultMinutes", def.defaultMinutes());
        root.addProperty("roundMinutes", def.roundMinutes());
        JsonObject portal = new JsonObject();
        portal.addProperty("searchMinRadius", def.portalSearchMinRadius());
        portal.addProperty("searchMaxRadius", def.portalSearchMaxRadius());
        root.add("portal", portal);
        JsonObject reward = new JsonObject();
        reward.addProperty("participationShards", def.participationShards());
        reward.addProperty("participationSkillXp", def.participationSkillXp());
        JsonArray podiumShards = new JsonArray();
        def.podiumShards().forEach(podiumShards::add);
        reward.add("podiumShards", podiumShards);
        JsonArray podiumSkillXp = new JsonArray();
        def.podiumSkillXp().forEach(podiumSkillXp::add);
        reward.add("podiumSkillXp", podiumSkillXp);
        root.add("reward", reward);

        Files.createDirectories(file.getParent());
        Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
        EclipseMod.LOGGER.info("Created default {}", file);
    }
}
