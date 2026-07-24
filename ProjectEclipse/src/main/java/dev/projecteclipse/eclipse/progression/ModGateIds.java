package dev.projecteclipse.eclipse.progression;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.DevReloadRegistry;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Optional resource-id-level companion to {@link ModGate}'s namespace gate.
 *
 * <p>{@code config/eclipse/modgate_ids.json} maps a namespaced glob to an unlock key. The
 * namespace is exact and glob metacharacters ({@code *} and {@code ?}) apply only to the path,
 * for example {@code create:*_casing}. A matching id is sealed until its key appears in
 * {@link UnlockState}. This keeps the existing namespace fast path intact while allowing a mod
 * such as Aeronautics to expose civil and industrial content in separate progression tiers.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ModGateIds {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "modgate_ids.json";

    /** One compiled config entry, retained in file order for deterministic diagnostics. */
    public record GateRule(String glob, String unlockKey, String namespace, Pattern pathPattern) {
        boolean matches(ResourceLocation id) {
            return namespace.equals(id.getNamespace()) && pathPattern.matcher(id.getPath()).matches();
        }
    }

    private static volatile List<GateRule> rules = List.of();
    private static volatile boolean loaded;

    static {
        DevReloadRegistry.register(FILE_NAME, ModGateIds::reloadDefault);
    }

    private ModGateIds() {}

    /** Whether this exact registry id matches at least one rule whose unlock key is locked. */
    public static boolean isLocked(MinecraftServer server, ResourceLocation id) {
        for (GateRule rule : rules()) {
            if (rule.matches(id) && !UnlockState.isUnlocked(server, rule.unlockKey())) {
                return true;
            }
        }
        return false;
    }

    /** Whether any configured id rule is currently locked; used to skip unnecessary sweeps. */
    public static boolean hasLockedEntries(MinecraftServer server) {
        for (GateRule rule : rules()) {
            if (!UnlockState.isUnlocked(server, rule.unlockKey())) {
                return true;
            }
        }
        return false;
    }

    /** Immutable, file-ordered rules for diagnostics such as {@code /dev modcheck}. */
    public static List<GateRule> rules() {
        ensureLoaded();
        return rules;
    }

    /** Re-reads the standard runtime file, creating it from {@link #defaultRoot()} when absent. */
    public static synchronized void reloadDefault() {
        reload(FMLPaths.CONFIGDIR.get().resolve(EclipseMod.MOD_ID));
    }

    static synchronized void reload(Path configDirectory) {
        Path file = configDirectory.resolve(FILE_NAME);
        JsonObject root = defaultRoot();
        try {
            Files.createDirectories(configDirectory);
            if (Files.isRegularFile(file)) {
                root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            } else {
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {}; using built-in id-gate defaults", file, e);
        }

        rules = parse(root);
        loaded = true;
        EclipseMod.LOGGER.info("ModGateIds loaded {} id glob(s)", rules.size());
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        reloadDefault();
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        rules = List.of();
        loaded = false;
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reloadDefault();
        }
    }

    private static List<GateRule> parse(JsonObject root) {
        if (!root.has("gatedIds") || !root.get("gatedIds").isJsonObject()) {
            return List.of();
        }
        List<GateRule> parsed = new ArrayList<>();
        for (Map.Entry<String, JsonElement> entry : root.getAsJsonObject("gatedIds").entrySet()) {
            String glob = entry.getKey().strip().toLowerCase(java.util.Locale.ROOT);
            String unlockKey = entry.getValue().getAsString().strip();
            int colon = glob.indexOf(':');
            if (colon <= 0 || colon != glob.lastIndexOf(':') || colon == glob.length() - 1
                    || !glob.substring(0, colon).matches("[a-z0-9_.-]+")
                    || !glob.substring(colon + 1).matches("[a-z0-9_./*?-]+")
                    || unlockKey.isEmpty()) {
                EclipseMod.LOGGER.warn("Ignoring invalid modgate_ids entry '{}': '{}'", glob, unlockKey);
                continue;
            }
            String namespace = glob.substring(0, colon);
            String pathGlob = glob.substring(colon + 1);
            parsed.add(new GateRule(glob, unlockKey, namespace, Pattern.compile(globToRegex(pathGlob))));
        }
        return List.copyOf(parsed);
    }

    private static String globToRegex(String glob) {
        StringBuilder regex = new StringBuilder(glob.length() * 2 + 2).append('^');
        for (int i = 0; i < glob.length(); i++) {
            char c = glob.charAt(i);
            if (c == '*') {
                regex.append(".*");
            } else if (c == '?') {
                regex.append('.');
            } else {
                if ("\\.^$|()[]{}+".indexOf(c) >= 0) {
                    regex.append('\\');
                }
                regex.append(c);
            }
        }
        return regex.append('$').toString();
    }

    private static JsonObject defaultRoot() {
        JsonObject root = new JsonObject();
        root.addProperty("_comment",
                "Exact namespace + globbed path gates. '*' matches any path span; '?' matches one character.");
        JsonObject gatedIds = new JsonObject();
        gatedIds.addProperty("aeronautics:balloon", "aeronautics_civil");
        gatedIds.addProperty("aeronautics:engine_*", "aeronautics_industrial");
        // C19 optional content proposals: whole-namespace globs keep them sealed on the
        // intended existing progression days without modifying EclipseConfig's shared schema.
        gatedIds.addProperty("ends_delight:*", "end");
        gatedIds.addProperty("create_confectionery:*", "farmersdelight");
        gatedIds.addProperty("createconnected:*", "create");
        root.add("gatedIds", gatedIds);
        return root;
    }
}
