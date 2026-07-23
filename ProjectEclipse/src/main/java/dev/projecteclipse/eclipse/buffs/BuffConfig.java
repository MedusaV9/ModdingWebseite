package dev.projecteclipse.eclipse.buffs;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Loads {@code config/eclipse/buffs.json} (R16/R17). Defaults mirror the P4 plan schema;
 * B3 may commit authored values under {@code run/config/eclipse/buffs.json}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BuffConfig {
    public enum StackRule {
        EXTEND,
        REFUSE
    }

    public sealed interface EffectSpec permits MultiplierEffect, PeriodicEffect, MagnetEffect {
    }

    public record MultiplierEffect(String tag, float value) implements EffectSpec {}

    public record PeriodicEffect(String action, int periodSeconds) implements EffectSpec {}

    public record MagnetEffect(float radius) implements EffectSpec {}

    public record LocalizedText(String en, String de) {}

    public record BuffDefinition(String id, LocalizedText title, EffectSpec effect, int defaultMinutes,
            StackRule stack) {}

    public record Config(int maxActive, Map<String, BuffDefinition> buffs) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "buffs.json";

    private static volatile Config config = defaultConfig();
    private static volatile Path configDir = FMLPaths.CONFIGDIR.get().resolve("eclipse");

    private BuffConfig() {}

    public static Config get() {
        return config;
    }

    public static void setConfigDirForTests(Path dir) {
        configDir = dir;
        reload();
    }

    public static void reload() {
        Path file = configDir.resolve(FILE_NAME);
        try {
            Files.createDirectories(configDir);
            if (!Files.isRegularFile(file)) {
                Files.writeString(file, GSON.toJson(defaultJson()), StandardCharsets.UTF_8);
            }
            String json = Files.readString(file, StandardCharsets.UTF_8);
            config = parse(json);
            EclipseMod.LOGGER.info("BuffConfig loaded: {} definitions, maxActive={}",
                    config.buffs().size(), config.maxActive());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("BuffConfig failed to load {}; using defaults", file, e);
            config = defaultConfig();
        }
    }

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        ReloadHooks.register("buffs", BuffConfig::reload);
        reload();
    }

    public static Config defaultConfig() {
        return parse(GSON.toJson(defaultJson()));
    }

    private static JsonObject defaultJson() {
        JsonObject root = new JsonObject();
        root.addProperty("maxActive", 3);
        JsonArray buffs = new JsonArray();

        buffs.add(def("double_skill_xp", "Double Skill XP", "Doppelte Skill-EP",
                multiplier("skill_xp", 2.0F), 30, "extend"));
        buffs.add(def("double_ore_drops", "Ore Surge", "Erz-Flut",
                multiplier("ore_drops", 2.0F), 15, "extend"));
        buffs.add(def("half_hunger", "Well Fed", "Wohlgenährt",
                multiplier("hunger", 0.5F), 30, "extend"));
        buffs.add(def("double_shard_finds", "Shard Rush", "Splitter-Rausch",
                multiplier("shard_drops", 2.0F), 20, "extend"));
        buffs.add(def("supply_rush", "Supply Rush", "Nachschub-Regen",
                periodic("supply_drop", 600), 30, "refuse"));
        buffs.add(def("xp_magnet", "XP Magnet", "EP-Magnet",
                magnet(8.0F), 15, "extend"));
        buffs.add(def("glitch_surge", "Glitch Surge", "Glitch-Welle",
                multiplier("glitch_spawn", 2.0F), 20, "extend"));

        root.add("buffs", buffs);
        return root;
    }

    private static JsonObject def(String id, String en, String de, JsonObject effect, int minutes, String stack) {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        JsonObject title = new JsonObject();
        title.addProperty("en", en);
        title.addProperty("de", de);
        obj.add("title", title);
        obj.add("effect", effect);
        obj.addProperty("defaultMinutes", minutes);
        obj.addProperty("stack", stack);
        return obj;
    }

    private static JsonObject multiplier(String tag, float value) {
        JsonObject obj = new JsonObject();
        obj.addProperty("type", "multiplier");
        obj.addProperty("tag", tag);
        obj.addProperty("value", value);
        return obj;
    }

    private static JsonObject periodic(String action, int periodSeconds) {
        JsonObject obj = new JsonObject();
        obj.addProperty("type", "periodic");
        obj.addProperty("action", action);
        obj.addProperty("periodSeconds", periodSeconds);
        return obj;
    }

    private static JsonObject magnet(float radius) {
        JsonObject obj = new JsonObject();
        obj.addProperty("type", "magnet");
        obj.addProperty("radius", radius);
        return obj;
    }

    private static Config parse(String json) {
        JsonObject root = JsonParser.parseString(json).getAsJsonObject();
        int maxActive = root.has("maxActive") ? root.get("maxActive").getAsInt() : 3;
        Map<String, BuffDefinition> buffs = new LinkedHashMap<>();
        if (root.has("buffs")) {
            for (JsonElement el : root.getAsJsonArray("buffs")) {
                BuffDefinition def = parseDefinition(el.getAsJsonObject());
                if (def != null) {
                    buffs.put(def.id(), def);
                }
            }
        }
        return new Config(maxActive, Map.copyOf(buffs));
    }

    private static BuffDefinition parseDefinition(JsonObject obj) {
        if (!obj.has("id")) {
            return null;
        }
        String id = obj.get("id").getAsString();
        LocalizedText title = parseTitle(obj.getAsJsonObject("title"));
        EffectSpec effect = parseEffect(obj.getAsJsonObject("effect"));
        int minutes = obj.has("defaultMinutes") ? obj.get("defaultMinutes").getAsInt() : 30;
        StackRule stack = StackRule.EXTEND;
        if (obj.has("stack")) {
            stack = "refuse".equalsIgnoreCase(obj.get("stack").getAsString())
                    ? StackRule.REFUSE : StackRule.EXTEND;
        }
        return new BuffDefinition(id, title, effect, minutes, stack);
    }

    private static LocalizedText parseTitle(JsonObject title) {
        if (title == null) {
            return new LocalizedText(idFallback(""), "");
        }
        return new LocalizedText(
                title.has("en") ? title.get("en").getAsString() : "",
                title.has("de") ? title.get("de").getAsString() : "");
    }

    private static String idFallback(String s) {
        return s;
    }

    private static EffectSpec parseEffect(JsonObject effect) {
        if (effect == null || !effect.has("type")) {
            return new MultiplierEffect("unknown", 1.0F);
        }
        return switch (effect.get("type").getAsString()) {
            case "multiplier" -> new MultiplierEffect(
                    effect.get("tag").getAsString(),
                    effect.has("value") ? effect.get("value").getAsFloat() : 2.0F);
            case "periodic" -> new PeriodicEffect(
                    effect.get("action").getAsString(),
                    effect.has("periodSeconds") ? effect.get("periodSeconds").getAsInt() : 600);
            case "magnet" -> new MagnetEffect(effect.has("radius") ? effect.get("radius").getAsFloat() : 8.0F);
            default -> new MultiplierEffect("unknown", 1.0F);
        };
    }
}
