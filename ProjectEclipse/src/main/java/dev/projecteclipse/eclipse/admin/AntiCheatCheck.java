package dev.projecteclipse.eclipse.admin;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
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
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.C2SModlistPayload;
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

    /**
     * Version stamp of the SHIPPED default allowlist ({@link #defaults()}). Bump this
     * whenever new default allowed/optional ids or corrected version pins ship; on-disk
     * files with an older (or absent) {@code allowlistVersion} get the new default ids
     * UNIONED in on load (EVAL-POL-S #3) — operator-added ids are never removed.
     * Version 1 = every pre-versioning extended file; version 2 = the v5 nested-id wave
     * ({@code fabric_*}, {@code mixinsquared}, photon/ldlib2/kilagraph, …); version 3 =
     * the pins corrected to the versions the pack mods actually REPORT to the loader
     * (see {@link #mergeNewDefaults}).
     */
    public static final int CURRENT_ALLOWLIST_VERSION = 3;

    /**
     * Immutable runtime schema for the extended {@code anticheat.json}.
     *
     * <p>{@code allowContinueOnMismatch} is the SERVER-authoritative mismatch policy (D8):
     * {@code false} (default) keeps the historical disconnect-on-mismatch behaviour, {@code true}
     * lets a mismatched client stay connected with a warning. The client's baked manifest flag of
     * the same name only affects the local title-screen warning and is never trusted here.</p>
     *
     * <p>{@code devBypassUuids} (D7) lists identities that skip mod-set enforcement entirely and
     * may use {@code /dev} without permission level 2. Entries are either literal UUIDs
     * ({@code "01234567-89ab-…"}) or name pins ({@code "name:Sonic0810"}) resolved at runtime via
     * the online player list and the server profile cache.</p>
     *
     * <p>{@code allowlistVersion} (EVAL-POL-S #3) is the default-id migration stamp — see
     * {@link #CURRENT_ALLOWLIST_VERSION}. Files without the field parse as version 1.</p>
     */
    public record Config(
            ModlistMode mode,
            List<String> blockedModIdSubstrings,
            Map<String, String> allowedMods,
            List<String> requiredMods,
            List<String> optionalMods,
            String downloadHintUrl,
            boolean allowContinueOnMismatch,
            List<String> devBypassUuids,
            int allowlistVersion) {
        public Config {
            blockedModIdSubstrings = List.copyOf(blockedModIdSubstrings);
            allowedMods = Collections.unmodifiableMap(new LinkedHashMap<>(allowedMods));
            requiredMods = List.copyOf(requiredMods);
            optionalMods = List.copyOf(optionalMods);
            downloadHintUrl = downloadHintUrl == null ? "" : downloadHintUrl;
            devBypassUuids = List.copyOf(devBypassUuids);
        }

        /** Pre-versioning shape (gametests, mode/snapshot rewrites): stamps the CURRENT version. */
        public Config(ModlistMode mode, List<String> blockedModIdSubstrings,
                Map<String, String> allowedMods, List<String> requiredMods,
                List<String> optionalMods, String downloadHintUrl,
                boolean allowContinueOnMismatch, List<String> devBypassUuids) {
            this(mode, blockedModIdSubstrings, allowedMods, requiredMods, optionalMods,
                    downloadHintUrl, allowContinueOnMismatch, devBypassUuids,
                    CURRENT_ALLOWLIST_VERSION);
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

    /**
     * Re-reads the extended schema. Legacy blocklist-only files are migrated in place, and
     * (EVAL-POL-S #3) files with an older {@code allowlistVersion} acquire the newly shipped
     * default allowed/optional ids via {@link #mergeNewDefaults} before being saved back.
     */
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
                    "downloadHintUrl", "allowContinueOnMismatch", "devBypassUuids")) {
                migrate |= !root.has(key);
            }
            Config parsed = parse(root, fallback);
            if (parsed.allowlistVersion() < CURRENT_ALLOWLIST_VERSION) {
                parsed = mergeNewDefaults(parsed, fallback);
                migrate = true;
                EclipseMod.LOGGER.info("Modcheck allowlist migrated to version {}: new default ids "
                                + "unioned in, shipped pins refreshed (operator ids and '*' pins kept) "
                                + "— now {} allowed / {} optional",
                        CURRENT_ALLOWLIST_VERSION, parsed.allowedMods().size(),
                        parsed.optionalMods().size());
            }
            config = parsed;
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

    /**
     * EVAL-POL-S #3 upgrade path: UNION the shipped default allowed/optional ids into an
     * older on-disk config and stamp {@link #CURRENT_ALLOWLIST_VERSION}. Operator-added ids
     * are never removed, and {@code requiredMods} is deliberately NOT unioned —
     * force-requiring new ids could lock out currently valid clients; new requirements stay
     * an explicit operator decision.
     *
     * <p>Version pins for ids that Eclipse itself ships ARE refreshed to the new default: the
     * pack decides which build of its own mods is correct, and a stale pin only ever produces
     * a bogus "wrong version" line in {@code /dev modcheck} and in the manifest written by
     * {@code /dev modcheck snapshot}. An operator opt-out is preserved: a pin an operator
     * relaxed to {@code "*"} stays {@code "*"}.</p>
     */
    static Config mergeNewDefaults(Config loaded, Config defaults) {
        Map<String, String> allowed = new LinkedHashMap<>(loaded.allowedMods());
        defaults.allowedMods().forEach((id, pin) -> {
            if (!ModVersionCheck.ANY.equals(allowed.get(id))) {
                allowed.put(id, pin);
            }
        });
        Set<String> optional = new LinkedHashSet<>(loaded.optionalMods());
        optional.addAll(defaults.optionalMods());
        return new Config(loaded.mode(), loaded.blockedModIdSubstrings(), allowed,
                loaded.requiredMods(), List.copyOf(optional), loaded.downloadHintUrl(),
                loaded.allowContinueOnMismatch(), loaded.devBypassUuids(),
                CURRENT_ALLOWLIST_VERSION);
    }

    /** Evaluates a report using the current mode. Blocklist substrings apply in both modes. */
    public static Evaluation evaluate(Collection<String> modIds) {
        return evaluate(config(), modIds);
    }

    /** Config-explicit evaluation used by gametests; behaviour identical to {@link #evaluate(Collection)}. */
    public static Evaluation evaluate(Config current, Collection<String> modIds) {
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

    /**
     * Whether the identity is on the {@code devBypassUuids} list (D7). Bypass identities skip
     * mod-set enforcement (modlist verdict + report timeout) and gain {@code /dev} access via
     * {@code DevRoot.canUseDev}; they NEVER gain op/permission-level rights beyond that.
     */
    public static boolean isDevBypass(MinecraftServer server, UUID uuid) {
        return isDevBypass(config(), server, uuid);
    }

    /** Config-explicit variant used by gametests. Malformed list entries are ignored. */
    public static boolean isDevBypass(Config current, MinecraftServer server, UUID uuid) {
        if (uuid == null) {
            return false;
        }
        for (String entry : current.devBypassUuids()) {
            if (entry == null || entry.isBlank()) {
                continue;
            }
            String trimmed = entry.strip();
            if (trimmed.regionMatches(true, 0, "name:", 0, 5)) {
                String name = trimmed.substring(5).strip();
                if (!name.isEmpty() && uuid.equals(resolveNameUuid(server, name))) {
                    return true;
                }
                continue;
            }
            try {
                if (uuid.equals(UUID.fromString(trimmed))) {
                    return true;
                }
            } catch (IllegalArgumentException ignored) {
                // Not a UUID and not a name pin — skip; reloadConfig already logged the load.
            }
        }
        return false;
    }

    /** Name→UUID pinning: online player first, then the server profile cache. */
    private static UUID resolveNameUuid(MinecraftServer server, String name) {
        if (server == null) {
            return null;
        }
        ServerPlayer online = server.getPlayerList().getPlayerByName(name);
        if (online != null) {
            return online.getUUID();
        }
        var cache = server.getProfileCache();
        if (cache != null) {
            var profile = cache.get(name);
            if (profile.isPresent()) {
                return profile.get().getId();
            }
        }
        return null;
    }

    /** Short hex digest of the current server mod policy (D8 drift detector, sent on login). */
    public static String policyHash() {
        Config current = config();
        return policyHash(current.allowedMods(), current.requiredMods(), current.optionalMods(),
                current.blockedModIdSubstrings());
    }

    /**
     * Canonical policy digest shared by server config and client manifest: SHA-256 over the
     * sorted allowed/required/optional/blocked ID sets, first 8 bytes as hex. Version pins are
     * deliberately excluded — the client manifest legitimately globs metadata suffixes the
     * server pins exactly, and the drift detector must only fire on real id-set divergence.
     * Purely diagnostic — this is not a security boundary.
     */
    public static String policyHash(Map<String, String> allowed, Collection<String> required,
            Collection<String> optional, Collection<String> blocked) {
        StringBuilder canonical = new StringBuilder();
        appendSorted(canonical, "a:", allowed.keySet());
        appendSorted(canonical, "r:", required);
        appendSorted(canonical, "o:", optional);
        appendSorted(canonical, "b:", blocked);
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(canonical.toString().getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(16);
            for (int i = 0; i < 8; i++) {
                hex.append(String.format(Locale.ROOT, "%02x", hash[i]));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            return "unavailable";
        }
    }

    private static void appendSorted(StringBuilder canonical, String prefix, Collection<String> values) {
        values.stream()
                .map(value -> value.toLowerCase(Locale.ROOT))
                .sorted()
                .forEach(value -> canonical.append(prefix).append(value).append('\n'));
    }

    /** Changes mode and persists the full schema. */
    public static synchronized void setMode(ModlistMode mode) throws IOException {
        Config old = config();
        Config updated = new Config(mode, old.blockedModIdSubstrings(), old.allowedMods(),
                old.requiredMods(), old.optionalMods(), old.downloadHintUrl(),
                old.allowContinueOnMismatch(), old.devBypassUuids());
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
                required, old.optionalMods(), old.downloadHintUrl(),
                old.allowContinueOnMismatch(), old.devBypassUuids());
        writeConfig(updated);
        config = updated;
        return updated;
    }

    /**
     * Writes the current allowlist in the shape of the baked client manifest
     * ({@code assets/eclipse/bootstrap.json}) so ops can copy it verbatim after a snapshot and
     * the client manifest can no longer drift from the server allowlist (D7).
     */
    public static synchronized Path writeSuggestedManifest(Path file) throws IOException {
        Config current = config();
        JsonObject root = new JsonObject();
        root.addProperty("_comment",
                "Generated by /dev modcheck snapshot from the running server's allowlist. Review, then copy over assets/eclipse/bootstrap.json (keep bundledMods maintained by hand).");
        root.addProperty("schemaVersion", 1);
        root.addProperty("allowContinueOnMismatch", current.allowContinueOnMismatch());
        root.addProperty("downloadHintUrl", current.downloadHintUrl());
        JsonObject allowed = new JsonObject();
        current.allowedMods().forEach(allowed::addProperty);
        root.add("allowedMods", allowed);
        root.add("requiredMods", array(current.requiredMods()));
        root.add("optionalMods", array(current.optionalMods()));
        root.add("blockedModIdSubstrings", array(current.blockedModIdSubstrings()));
        root.add("devBypassUuids", array(current.devBypassUuids()));
        Files.createDirectories(file.toAbsolutePath().getParent());
        Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
        return file;
    }

    /** Server handler for {@link C2SModlistPayload}; wired in {@code EclipsePayloads}. */
    public static void handleModlist(C2SModlistPayload payload, ServerPlayer player) {
        awaitingModlist.remove(player.getUUID());
        List<String> normalized = normalize(payload.modIds()).stream().sorted().toList();
        reportedModlists.put(player.getUUID(), normalized);
        Evaluation result = evaluate(normalized);
        if (!result.accepted()) {
            if (isDevBypass(player.server, player.getUUID())) {
                EclipseMod.LOGGER.info("Modcheck bypass (dev) for {}: {}",
                        player.getScoreboardName(), result.summary());
                return;
            }
            if (config().allowContinueOnMismatch()) {
                // Server-authoritative continue verdict (D8): mismatch is tolerated this
                // session, logged and surfaced to the player — never decided client-side.
                EclipseMod.LOGGER.warn("Modcheck mismatch tolerated for {} (allowContinueOnMismatch): {}",
                        player.getScoreboardName(), result.summary());
                player.sendSystemMessage(ServerLang.tr(player,
                        "message.eclipse.modcheck.server_warn", result.summary()));
                return;
            }
            EclipseMod.LOGGER.warn("Modcheck rejected {}: {}", player.getScoreboardName(), result.summary());
            String hint = config().downloadHintUrl();
            player.connection.disconnect(ServerLang.tr(player,
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
            if (isDevBypass(server, entry.getKey())) {
                EclipseMod.LOGGER.info("Modcheck bypass (dev): {} never reported; timeout waived",
                        entry.getKey());
                continue;
            }
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            if (player != null) {
                EclipseMod.LOGGER.warn("Modcheck: {} never reported within {} ms; disconnecting",
                        player.getScoreboardName(), MODLIST_TIMEOUT_MILLIS);
                player.connection.disconnect(ServerLang.tr(player, "disconnect.eclipse.modcheck.timeout"));
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
        boolean allowContinue = root.has("allowContinueOnMismatch")
                && root.get("allowContinueOnMismatch").isJsonPrimitive()
                        ? root.get("allowContinueOnMismatch").getAsBoolean()
                        : fallback.allowContinueOnMismatch();
        List<String> devBypass = strings(root, "devBypassUuids", fallback.devBypassUuids());
        // A missing allowlistVersion means a pre-versioning file (= 1), NOT the fallback's
        // current stamp — otherwise old files would silently skip the default-id migration.
        int allowlistVersion = root.has("allowlistVersion") && root.get("allowlistVersion").isJsonPrimitive()
                ? root.get("allowlistVersion").getAsInt()
                : 1;
        return new Config(mode, blocked, allowed, required, optional,
                string(root, "downloadHintUrl", fallback.downloadHintUrl()),
                allowContinue, devBypass, allowlistVersion);
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
                "Allowlist is exact by mod id; version pins are checked by the client bootstrap because the legacy C2S payload carries ids only. A pin is the version the mod REPORTS to the loader, not its jar name: '*' accepts anything, '[x,)' is a Maven range, a value containing '*' is a glob, and trailing SemVer '+build' metadata is tolerated when the rest matches exactly (admin/ModVersionCheck).");
        root.addProperty("_comment_devBypass",
                "devBypassUuids entries are literal UUIDs or 'name:<PlayerName>' pins (resolved via the profile cache). Listed identities skip modcheck enforcement and may use /dev without op. Prefer the UUID form; the shipped 'name:Sonic0810' placeholder should be replaced with the player's real UUID.");
        root.addProperty("modlistMode", value.mode().configName());
        root.addProperty("allowlistVersion", value.allowlistVersion());
        root.add("blockedModIdSubstrings", array(value.blockedModIdSubstrings()));
        JsonObject allowed = new JsonObject();
        value.allowedMods().forEach(allowed::addProperty);
        root.add("allowedMods", allowed);
        root.add("requiredMods", array(value.requiredMods()));
        root.add("optionalMods", array(value.optionalMods()));
        root.addProperty("downloadHintUrl", value.downloadHintUrl());
        root.addProperty("allowContinueOnMismatch", value.allowContinueOnMismatch());
        root.add("devBypassUuids", array(value.devBypassUuids()));
        return root;
    }

    private static JsonArray array(Collection<String> values) {
        JsonArray array = new JsonArray();
        values.forEach(array::add);
        return array;
    }

    /**
     * Defaults cover every external jar listed in README's Server pack plus optional additions.
     * Public so gametests can evaluate against the shipped policy without touching disk.
     *
     * <p>Every pin is the version the mod REPORTS to the loader (its {@code neoforge.mods.toml}
     * {@code version}), which is regularly not the version in its jar/Maven coordinate — EMI
     * resolves from {@code dev.emi:emi-neoforge:1.1.24+1.21.1} but registers as
     * {@code 1.1.24+1.21.1+neoforge}, and Sophisticated Backpacks ships as
     * {@code …-3.25.71.1997.jar} but registers as {@code 3.25.71}. Verified against the mod
     * list of a dev client boot; pin syntax is documented in {@link ModVersionCheck}.</p>
     */
    public static Config defaults() {
        Map<String, String> allowed = new LinkedHashMap<>();
        allowed.put("minecraft", "1.21.1");
        allowed.put("neoforge", "21.1.238");
        allowed.put("eclipse", "2.1.0");
        // Veil/GeckoLib are jar-in-jar'd with an open range (build.gradle), so a newer build
        // provided by another pack mod legitimately wins the dedupe — pin the same range.
        allowed.put("veil", "[4.3.0,)");
        allowed.put("geckolib", "[4.9.2,)");
        allowed.put("emi", "1.1.24+1.21.1+neoforge");
        allowed.put("mousetweaks", "2.26.1");
        allowed.put("create", "6.0.10");
        allowed.put("aeronautics", "1.3.0");
        allowed.put("simulated", "1.3.0");
        allowed.put("offroad", "1.3.0");
        allowed.put("sable", "2.0.3");
        allowed.put("sablecompanion", "*");
        allowed.put("voicechat", "1.21.1-2.6.16");
        allowed.put("voicechat_api", "*");
        // FD reports its version WITHOUT the MC prefix at runtime (jar name differs).
        allowed.put("farmersdelight", "1.3.2");
        allowed.put("supplementaries", "1.21.1-3.8.3");
        allowed.put("moonlight", "1.21.1-3.1.1");
        allowed.put("sophisticatedbackpacks", "3.25.71");
        allowed.put("sophisticatedcore", "1.4.77");
        allowed.put("createaddition", "1.6.0");
        // Library ids that ride INSIDE another pack jar: the parent picks the version, so
        // pinning them would only produce false mismatches after a parent bugfix release.
        allowed.put("flywheel", "*");
        allowed.put("ponder", "*");
        allowed.put("registrate", "*");
        allowed.put("curios", "*");
        allowed.put("aeronautics_bundled", "1.3.0");
        allowed.put("codecui", "*");
        // Client extras and the C19 content proposal are optional.
        allowed.put("sodium", "0.8.12+mc1.21.1");
        allowed.put("iris", "1.8.14-beta.1+mc1.21.1");
        allowed.put("ends_delight", "2.6.1+neoforge.1.21.1");
        allowed.put("create_confectionery", "1.1.2");
        allowed.put("createconnected", "1.3.2-mc1.21.1");
        // Forgified-Fabric-API sub-modules jarJar'd INSIDE the Sodium/Iris NeoForge builds
        // (verified by unpacking run/mods-client/*): they show up as loaded mods on any client
        // running the optional performance extras. No standalone Forgified Fabric API install
        // exists or is needed — see docs/BUNDLING.md.
        allowed.put("fabric_api_base", "*");
        allowed.put("fabric_block_view_api_v2", "*");
        allowed.put("fabric_renderer_api_v1", "*");
        allowed.put("fabric_rendering_data_attachment_v1", "*");
        // MixinSquared is jarJar'd inside Supplementaries and registers as a real mod id.
        allowed.put("mixinsquared", "*");
        // D12: Photon VFX layer is an OPTIONAL client extra (PhotonBridge no-ops without it).
        // Photon 2.1.x requires LDLib2 at runtime; 2.2.x additionally pulls KilaGraph —
        // allow all three so an optional install never trips the modcheck. docs/BUNDLING.md.
        allowed.put("photon", "2.1.5");
        allowed.put("ldlib2", "2.2.29");
        allowed.put("kilagraph", "*");

        List<String> required = List.of(
                "minecraft", "neoforge", "eclipse", "veil", "geckolib",
                "create", "aeronautics", "simulated", "offroad", "sable", "voicechat",
                "farmersdelight", "supplementaries", "moonlight",
                "sophisticatedbackpacks", "sophisticatedcore", "createaddition");
        List<String> optional = List.of(
                "emi", "mousetweaks", "sodium", "iris",
                "flywheel", "ponder", "registrate", "curios",
                "ends_delight", "create_confectionery", "createconnected",
                "fabric_api_base", "fabric_block_view_api_v2",
                "fabric_renderer_api_v1", "fabric_rendering_data_attachment_v1",
                "mixinsquared",
                "photon", "ldlib2", "kilagraph");
        return new Config(
                ModlistMode.ALLOWLIST,
                EclipseConfig.antiCheat().blockedModIdSubstrings(),
                allowed,
                required,
                optional,
                "See docs/BUNDLING.md and README.md#server-pack-external-mods",
                false,
                List.of("name:Sonic0810"));
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
