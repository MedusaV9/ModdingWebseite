package dev.projecteclipse.eclipse.admin;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.network.C2SModlistPayload;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Honest-client mod-set screening. {@code config/eclipse/anticheat.json} may run in strict
 * allowlist mode or retain the legacy substring blocklist mode; the substring blocklist is
 * applied in both modes.
 *
 * <p>The client still self-reports through {@link C2SModlistPayload}, so this is a pack-integrity
 * deterrent rather than a security boundary. The server verifies the report immediately after
 * login and retains the mandatory-client timeout. The local client warning is rendered by
 * {@code bootstrap.PackBootstrap} instead of crashing during FML setup.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AntiCheatCheck {
    /** How long after login a client may take to report its modlist before being kicked. */
    static final long MODLIST_TIMEOUT_MILLIS = 30_000L;
    private static final int CHECK_INTERVAL_TICKS = 20;
    private static final String CONFIG_FILE = "anticheat.json";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    public enum ModlistMode {
        BLOCKLIST,
        ALLOWLIST;

        static ModlistMode parse(String value) {
            return "blocklist".equalsIgnoreCase(value) ? BLOCKLIST : ALLOWLIST;
        }

        public String configName() {
            return name().toLowerCase(Locale.ROOT);
        }
    }

    /** Immutable runtime schema for the extended {@code anticheat.json}. */
    public record Config(
            ModlistMode mode,
            List<String> blockedModIdSubstrings,
            Map<String, String> allowedMods,
            List<String> requiredMods,
            List<String> optionalMods,
            String downloadHintUrl) {
        public Config {
            blockedModIdSubstrings = List.copyOf(blockedModIdSubstrings);
            allowedMods = Collections.unmodifiableMap(new LinkedHashMap<>(allowedMods));
            requiredMods = List.copyOf(requiredMods);
            optionalMods = List.copyOf(optionalMods);
            downloadHintUrl = downloadHintUrl == null ? "" : downloadHintUrl;
        }
    }

    /** Result of evaluating a reported set. Lists are sorted for stable chat, logs and tests. */
    public record Evaluation(List<String> blocked, List<String> missing, List<String> extra) {
        public Evaluation {
            blocked = blocked.stream().sorted().toList();
            missing = missing.stream().sorted().toList();
            extra = extra.stream().sorted().toList();
        }

        public boolean accepted() {
            return blocked.isEmpty() && missing.isEmpty() && extra.isEmpty();
        }

        public String summary() {
            List<String> parts = new ArrayList<>();
            if (!blocked.isEmpty()) {
                parts.add("blocked=" + String.join(", ", blocked));
            }
            if (!missing.isEmpty()) {
                parts.add("missing=" + String.join(", ", missing));
            }
            if (!extra.isEmpty()) {
                parts.add("extra=" + String.join(", ", extra));
            }
            return parts.isEmpty() ? "OK" : String.join("; ", parts);
        }
    }

    /** Online players that have not reported a modlist yet: player UUID → login epoch millis. */
    private static final Map<UUID, Long> awaitingModlist = new ConcurrentHashMap<>();
    /** Last normalized report per online player, used by the read-only dev checker. */
    private static final Map<UUID, List<String>> reportedModlists = new ConcurrentHashMap<>();
    private static volatile Config config = defaults();
    private static volatile boolean configLoaded;

    static {
        ReloadHooks.register("anticheat-allowlist", AntiCheatCheck::reloadConfig);
    }

    private AntiCheatCheck() {}

    public static Config config() {
        ensureConfigLoaded();
        return config;
    }

    /** Re-reads the extended schema. Legacy blocklist-only files are migrated in place. */
    public static synchronized void reloadConfig() {
        Path file = configPath();
        Config fallback = defaults();
        JsonObject root;
        boolean migrate = false;
        try {
            Files.createDirectories(file.getParent());
            if (Files.isRegularFile(file)) {
                root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            } else {
                root = toJson(fallback);
                migrate = true;
            }
            for (String key : List.of("modlistMode", "allowedMods", "requiredMods", "optionalMods",
                    "downloadHintUrl")) {
                migrate |= !root.has(key);
            }
            config = parse(root, fallback);
            configLoaded = true;
            if (migrate) {
                Files.writeString(file, GSON.toJson(toJson(config)), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created/migrated extended modcheck config {}", file);
            }
        } catch (IOException | RuntimeException e) {
            config = fallback;
            configLoaded = true;
            EclipseMod.LOGGER.error("Failed to load {}; using built-in modcheck defaults", file, e);
        }
        EclipseMod.LOGGER.info("Modcheck loaded: mode={}, allowed={}, required={}, optional={}, blocked={}",
                config.mode().configName(), config.allowedMods().size(), config.requiredMods().size(),
                config.optionalMods().size(), config.blockedModIdSubstrings().size());
    }

    /** Evaluates a report using the current mode. Blocklist substrings apply in both modes. */
    public static Evaluation evaluate(Collection<String> modIds) {
        Config current = config();
        Set<String> reported = normalize(modIds);
        Set<String> blocked = new LinkedHashSet<>();
        for (String modId : reported) {
            for (String fragment : current.blockedModIdSubstrings()) {
                if (!fragment.isBlank() && modId.contains(fragment.toLowerCase(Locale.ROOT))) {
                    blocked.add(modId);
                    break;
                }
            }
        }

        if (current.mode() == ModlistMode.BLOCKLIST) {
            return new Evaluation(List.copyOf(blocked), List.of(), List.of());
        }

        Set<String> missing = new LinkedHashSet<>(normalize(current.requiredMods()));
        missing.removeAll(reported);

        Set<String> acceptedIds = new LinkedHashSet<>(normalize(current.allowedMods().keySet()));
        acceptedIds.addAll(normalize(current.optionalMods()));
        acceptedIds.addAll(normalize(current.requiredMods()));
        Set<String> extra = new LinkedHashSet<>(reported);
        extra.removeAll(acceptedIds);
        return new Evaluation(List.copyOf(blocked), List.copyOf(missing), List.copyOf(extra));
    }

    /**
     * The first mod id that matches the configured blocklist, retained for compatibility with
     * older callers; {@code null} means clean.
     */
    public static String findBlockedModId(Collection<String> modIds) {
        List<String> blocked = evaluate(modIds).blocked();
        return blocked.isEmpty() ? null : blocked.get(0);
    }

    /** The sorted ids of every mod loaded in this game instance. */
    public static List<String> loadedModIds() {
        return loadedMods().keySet().stream().sorted().toList();
    }

    /** Sorted loaded mod id → metadata version. Includes nested jar-in-jar mods. */
    public static Map<String, String> loadedMods() {
        Map<String, String> loaded = new LinkedHashMap<>();
        ModList.get().getMods().stream()
                .sorted(java.util.Comparator.comparing(info -> info.getModId().toLowerCase(Locale.ROOT)))
                .forEach(info -> loaded.put(info.getModId().toLowerCase(Locale.ROOT),
                        info.getVersion().toString()));
        return Collections.unmodifiableMap(loaded);
    }

    /** Last mod-id report for an online player, if one has arrived. */
    public static Optional<List<String>> lastReport(UUID playerId) {
        return Optional.ofNullable(reportedModlists.get(playerId));
    }

    /** Changes mode and persists the full schema. */
    public static synchronized void setMode(ModlistMode mode) throws IOException {
        Config old = config();
        Config updated = new Config(mode, old.blockedModIdSubstrings(), old.allowedMods(),
                old.requiredMods(), old.optionalMods(), old.downloadHintUrl());
        writeConfig(updated);
        config = updated;
    }

    /**
     * Captures the running server's actual mod metadata into the allowlist. Existing optional
     * client-only entries are preserved; every non-optional loaded id becomes required.
     */
    public static synchronized Config snapshotRunningServer() throws IOException {
        Config old = config();
        Map<String, String> allowed = new LinkedHashMap<>(loadedMods());
        for (String optional : old.optionalMods()) {
            allowed.putIfAbsent(optional, old.allowedMods().getOrDefault(optional, "*"));
        }
        Set<String> optional = normalize(old.optionalMods());
        List<String> required = allowed.keySet().stream()
                .filter(id -> !optional.contains(id))
                .sorted()
                .toList();
        Config updated = new Config(ModlistMode.ALLOWLIST, old.blockedModIdSubstrings(), allowed,
                required, old.optionalMods(), old.downloadHintUrl());
        writeConfig(updated);
        config = updated;
        return updated;
    }

    /** Server handler for {@link C2SModlistPayload}; wired in {@code EclipsePayloads}. */
    public static void handleModlist(C2SModlistPayload payload, ServerPlayer player) {
        awaitingModlist.remove(player.getUUID());
        List<String> normalized = normalize(payload.modIds()).stream().sorted().toList();
        reportedModlists.put(player.getUUID(), normalized);
        Evaluation result = evaluate(normalized);
        if (!result.accepted()) {
            EclipseMod.LOGGER.warn("Modcheck rejected {}: {}", player.getScoreboardName(), result.summary());
            String hint = config().downloadHintUrl();
            player.connection.disconnect(Component.translatable(
                    "disconnect.eclipse.modcheck.failed",
                    String.join(", ", result.blocked()),
                    String.join(", ", result.missing()),
                    String.join(", ", result.extra()),
                    hint));
            return;
        }
        EclipseMod.LOGGER.info("Modcheck accepted {} ({} reported mods, mode={})",
                player.getScoreboardName(), normalized.size(), config().mode().configName());
    }

    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            ensureConfigLoaded();
            awaitingModlist.put(player.getUUID(), System.currentTimeMillis());
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        UUID id = event.getEntity().getUUID();
        awaitingModlist.remove(id);
        reportedModlists.remove(id);
    }

    /** Kicks players whose client never reported a modlist within the timeout. */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % CHECK_INTERVAL_TICKS != 0 || awaitingModlist.isEmpty()) {
            return;
        }
        long now = System.currentTimeMillis();
        for (Map.Entry<UUID, Long> entry : awaitingModlist.entrySet()) {
            if (now - entry.getValue() < MODLIST_TIMEOUT_MILLIS) {
                continue;
            }
            awaitingModlist.remove(entry.getKey());
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            if (player != null) {
                EclipseMod.LOGGER.warn("Modcheck: {} never reported within {} ms; disconnecting",
                        player.getScoreboardName(), MODLIST_TIMEOUT_MILLIS);
                player.connection.disconnect(Component.translatable("disconnect.eclipse.modcheck.timeout"));
            }
        }
    }

    private static void ensureConfigLoaded() {
        if (!configLoaded) {
            reloadConfig();
        }
    }

    private static Path configPath() {
        return FMLPaths.CONFIGDIR.get().resolve(EclipseMod.MOD_ID).resolve(CONFIG_FILE);
    }

    private static Set<String> normalize(Collection<String> ids) {
        Set<String> normalized = new LinkedHashSet<>();
        for (String id : ids) {
            if (id != null && !id.isBlank()) {
                normalized.add(id.strip().toLowerCase(Locale.ROOT));
            }
        }
        return normalized;
    }

    private static Config parse(JsonObject root, Config fallback) {
        ModlistMode mode = ModlistMode.parse(string(root, "modlistMode", fallback.mode().configName()));
        List<String> blocked = strings(root, "blockedModIdSubstrings", fallback.blockedModIdSubstrings());
        Map<String, String> allowed = stringMap(root, "allowedMods", fallback.allowedMods());
        List<String> required = strings(root, "requiredMods", fallback.requiredMods());
        List<String> optional = strings(root, "optionalMods", fallback.optionalMods());
        return new Config(mode, blocked, allowed, required, optional,
                string(root, "downloadHintUrl", fallback.downloadHintUrl()));
    }

    private static String string(JsonObject root, String key, String fallback) {
        return root.has(key) && root.get(key).isJsonPrimitive() ? root.get(key).getAsString() : fallback;
    }

    private static List<String> strings(JsonObject root, String key, List<String> fallback) {
        if (!root.has(key) || !root.get(key).isJsonArray()) {
            return fallback;
        }
        List<String> values = new ArrayList<>();
        for (JsonElement element : root.getAsJsonArray(key)) {
            if (element.isJsonPrimitive()) {
                values.add(element.getAsString().toLowerCase(Locale.ROOT));
            }
        }
        return List.copyOf(values);
    }

    private static Map<String, String> stringMap(JsonObject root, String key, Map<String, String> fallback) {
        if (!root.has(key) || !root.get(key).isJsonObject()) {
            return fallback;
        }
        Map<String, String> values = new LinkedHashMap<>();
        for (Map.Entry<String, JsonElement> entry : root.getAsJsonObject(key).entrySet()) {
            if (entry.getValue().isJsonPrimitive()) {
                values.put(entry.getKey().toLowerCase(Locale.ROOT), entry.getValue().getAsString());
            }
        }
        return values;
    }

    private static void writeConfig(Config value) throws IOException {
        Path file = configPath();
        Files.createDirectories(file.getParent());
        Files.writeString(file, GSON.toJson(toJson(value)), StandardCharsets.UTF_8);
        configLoaded = true;
    }

    private static JsonObject toJson(Config value) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment",
                "Allowlist is exact by mod id; version pins are checked by the client bootstrap because the legacy C2S payload carries ids only.");
        root.addProperty("modlistMode", value.mode().configName());
        root.add("blockedModIdSubstrings", array(value.blockedModIdSubstrings()));
        JsonObject allowed = new JsonObject();
        value.allowedMods().forEach(allowed::addProperty);
        root.add("allowedMods", allowed);
        root.add("requiredMods", array(value.requiredMods()));
        root.add("optionalMods", array(value.optionalMods()));
        root.addProperty("downloadHintUrl", value.downloadHintUrl());
        return root;
    }

    private static JsonArray array(Collection<String> values) {
        JsonArray array = new JsonArray();
        values.forEach(array::add);
        return array;
    }

    /** Defaults cover every external jar listed in README's Server pack plus optional additions. */
    private static Config defaults() {
        Map<String, String> allowed = new LinkedHashMap<>();
        allowed.put("minecraft", "1.21.1");
        allowed.put("neoforge", "21.1.238");
        allowed.put("eclipse", "2.1.0");
        allowed.put("veil", "4.3.0");
        allowed.put("geckolib", "4.9.2");
        allowed.put("emi", "1.1.18+1.21.1");
        allowed.put("mousetweaks", "2.26.1");
        allowed.put("create", "6.0.10");
        allowed.put("aeronautics", "1.3.0");
        allowed.put("simulated", "*");
        allowed.put("offroad", "*");
        allowed.put("sable", "2.0.3");
        allowed.put("voicechat", "2.6.16");
        allowed.put("farmersdelight", "1.21.1-1.3.2");
        allowed.put("supplementaries", "1.21.1-3.8.3");
        allowed.put("moonlight", "1.21.1-3.1.1");
        allowed.put("sophisticatedbackpacks", "1.21.1-3.25.71");
        allowed.put("sophisticatedcore", "1.21.1-1.4.77");
        allowed.put("createaddition", "1.6.0");
        // Common nested/library ids accepted when the external pack exposes them separately.
        allowed.put("flywheel", "*");
        allowed.put("ponder", "*");
        allowed.put("registrate", "*");
        allowed.put("curios", "*");
        // Client extras and the C19 content proposal are optional.
        allowed.put("sodium", "0.8.12+mc1.21.1");
        allowed.put("iris", "1.8.14-beta.1+mc1.21.1");
        allowed.put("ends_delight", "2.6.1+neoforge.1.21.1");
        allowed.put("create_confectionery", "1.1.2");
        allowed.put("createconnected", "1.3.2-mc1.21.1");

        List<String> required = List.of(
                "minecraft", "neoforge", "eclipse", "veil", "geckolib",
                "create", "aeronautics", "simulated", "offroad", "sable", "voicechat",
                "farmersdelight", "supplementaries", "moonlight",
                "sophisticatedbackpacks", "sophisticatedcore", "createaddition");
        List<String> optional = List.of(
                "emi", "mousetweaks", "sodium", "iris",
                "flywheel", "ponder", "registrate", "curios",
                "ends_delight", "create_confectionery", "createconnected");
        return new Config(
                ModlistMode.ALLOWLIST,
                EclipseConfig.antiCheat().blockedModIdSubstrings(),
                allowed,
                required,
                optional,
                "See docs/BUNDLING.md and README.md#server-pack-external-mods");
    }

    /** Client-side half: warning bootstrap + modlist reporting. Only classloaded on the client. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class Client {
        private Client() {}

        @SubscribeEvent
        static void onClientSetup(FMLClientSetupEvent event) {
            event.enqueueWork(dev.projecteclipse.eclipse.bootstrap.PackBootstrap::prepareCheck);
        }

        /** Reports the local modlist to the server as soon as the play connection is up. */
        @SubscribeEvent
        static void onLoggingIn(ClientPlayerNetworkEvent.LoggingIn event) {
            List<String> modIds = loadedModIds();
            PacketDistributor.sendToServer(new C2SModlistPayload(modIds));
            EclipseMod.LOGGER.info("Modcheck: sent client report ({} ids)", modIds.size());
        }
    }
}
