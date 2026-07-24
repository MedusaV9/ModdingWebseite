package dev.projecteclipse.eclipse.voice;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

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
 * Loads {@code config/eclipse/voice_changer.json} (ProtectionConfig pattern, {@code /dev
 * reload}-aware): master enable, which presets players may self-select via {@code /voice},
 * the per-frame DSP time budget, and how many consecutive over-budget frames trip the
 * auto-disable kill switch. Dev commands ({@code /dev voice changer ...}) ignore the
 * self-select whitelist.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class VoiceChangerConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE = "voice_changer.json";

    private static volatile Snapshot current = Snapshot.defaults();
    private static volatile boolean loaded = false;
    private static volatile boolean reloadHookRegistered = false;

    private VoiceChangerConfig() {}

    public record Snapshot(
            boolean enabled,
            List<String> playerSelectablePresets,
            int frameBudgetMicros,
            int autoDisableStrikes) {

        public Snapshot {
            playerSelectablePresets = List.copyOf(playerSelectablePresets);
        }

        static Snapshot defaults() {
            return new Snapshot(true,
                    List.of("off", "deep", "high", "ghost", "glitch"),
                    2000, 5);
        }

        public boolean isPlayerSelectable(VoicePreset preset) {
            return playerSelectablePresets.contains(preset.id());
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
            EclipseMod.LOGGER.error("Failed to create voice changer config directory {}", configDir, e);
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
        EclipseMod.LOGGER.info("Voice changer config loaded (enabled={}, selfPresets={}, budget={}us)",
                current.enabled(), current.playerSelectablePresets(), current.frameBudgetMicros());
    }

    public static synchronized void reloadDefault() {
        reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (!reloadHookRegistered) {
            ReloadHooks.register("voice_changer", VoiceChangerConfig::reloadDefault);
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
        boolean enabled = root.has("enabled") ? root.get("enabled").getAsBoolean() : defaults.enabled();
        List<String> selectable = new ArrayList<>();
        if (root.has("playerSelectablePresets") && root.get("playerSelectablePresets").isJsonArray()) {
            for (JsonElement element : root.getAsJsonArray("playerSelectablePresets")) {
                String id = element.getAsString().toLowerCase(Locale.ROOT);
                if (VoicePreset.byId(id) != null) {
                    selectable.add(id);
                } else {
                    EclipseMod.LOGGER.warn("voice_changer.json: unknown preset '{}' ignored", id);
                }
            }
        } else {
            selectable.addAll(defaults.playerSelectablePresets());
        }
        int budget = root.has("frameBudgetMicros")
                ? Math.max(100, root.get("frameBudgetMicros").getAsInt())
                : defaults.frameBudgetMicros();
        int strikes = root.has("autoDisableStrikes")
                ? Math.max(1, root.get("autoDisableStrikes").getAsInt())
                : defaults.autoDisableStrikes();
        return new Snapshot(enabled, selectable, budget, strikes);
    }

    private static JsonObject defaultRoot() {
        Snapshot defaults = Snapshot.defaults();
        JsonObject root = new JsonObject();
        root.addProperty("enabled", defaults.enabled());
        JsonArray presets = new JsonArray();
        for (String id : defaults.playerSelectablePresets()) {
            presets.add(id);
        }
        root.add("playerSelectablePresets", presets);
        root.addProperty("frameBudgetMicros", defaults.frameBudgetMicros());
        root.addProperty("autoDisableStrikes", defaults.autoDisableStrikes());
        return root;
    }
}
