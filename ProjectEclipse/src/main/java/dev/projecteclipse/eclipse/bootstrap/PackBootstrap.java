package dev.projecteclipse.eclipse.bootstrap;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck;
import dev.projecteclipse.eclipse.client.menu.EclipseTitleScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Client-only first-title-screen pack verifier.
 *
 * <p>The baked {@code assets/eclipse/bootstrap.json} is the distributable pack manifest:
 * allowed ids and versions, required/optional classification, blocklist and the operator's
 * decision whether a user may acknowledge a mismatch. Unknown, missing, blocklisted and
 * version-mismatched entries are shown by {@link BootstrapScreen}; no client is crashed during
 * mod loading. The server independently evaluates the id report at connection time.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PackBootstrap {
    private static final String MANIFEST = "/assets/eclipse/bootstrap.json";

    public enum Reason {
        UNKNOWN,
        MISSING,
        VERSION,
        BLOCKED
    }

    /** One itemized manifest violation rendered by the warning screen. */
    public record Violation(String modId, String installedVersion, String expectedVersion, Reason reason) {}

    /** Immutable client check result. */
    public record Report(
            List<Violation> violations,
            Map<String, String> loadedMods,
            boolean allowContinue,
            String downloadHintUrl) {
        public Report {
            violations = List.copyOf(violations);
            loadedMods = Collections.unmodifiableMap(new LinkedHashMap<>(loadedMods));
            downloadHintUrl = downloadHintUrl == null ? "" : downloadHintUrl;
        }

        public boolean clean() {
            return violations.isEmpty();
        }
    }

    private record ManifestData(
            Map<String, String> allowedMods,
            List<String> requiredMods,
            List<String> optionalMods,
            List<String> blockedModIdSubstrings,
            boolean allowContinueOnMismatch,
            String downloadHintUrl) {}

    private static volatile Report report;
    private static boolean screenHandled;

    private PackBootstrap() {}

    /** Loads and evaluates the baked manifest. Safe to invoke more than once. */
    public static synchronized void prepareCheck() {
        try {
            ManifestData manifest = loadManifest();
            report = evaluate(manifest, AntiCheatCheck.loadedMods());
            if (report.clean()) {
                EclipseMod.LOGGER.info("Pack bootstrap check passed ({} loaded mods)", report.loadedMods().size());
            } else {
                EclipseMod.LOGGER.warn("Pack bootstrap found {} mod-set issue(s): {}",
                        report.violations().size(),
                        report.violations().stream().map(Violation::modId).toList());
            }
        } catch (IOException | RuntimeException e) {
            // A bad embedded manifest must never trap the user behind an unusable screen.
            report = new Report(List.of(), AntiCheatCheck.loadedMods(), true, "");
            EclipseMod.LOGGER.error("Could not read {}; skipping local pack warning", MANIFEST, e);
        }
    }

    public static Report currentReport() {
        Report current = report;
        if (current == null) {
            prepareCheck();
            current = report;
        }
        return current;
    }

    /**
     * Runs after title-screen replacement hooks, so the warning wraps either vanilla or the
     * custom Eclipse title screen and returns to the effective parent after acknowledgement.
     */
    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onScreenOpening(ScreenEvent.Opening event) {
        if (screenHandled || event.getNewScreen() instanceof BootstrapScreen) {
            return;
        }
        Screen opening = event.getNewScreen();
        if (!(opening instanceof TitleScreen) && !(opening instanceof EclipseTitleScreen)) {
            return;
        }
        Report current = currentReport();
        screenHandled = true;
        if (!current.clean()) {
            event.setNewScreen(new BootstrapScreen(opening, current));
        }
    }

    private static Report evaluate(ManifestData manifest, Map<String, String> loadedMods) {
        Map<String, String> normalizedLoaded = new LinkedHashMap<>();
        loadedMods.forEach((id, version) ->
                normalizedLoaded.put(id.toLowerCase(Locale.ROOT), version));

        Set<String> accepted = new LinkedHashSet<>(manifest.allowedMods().keySet());
        accepted.addAll(manifest.requiredMods());
        accepted.addAll(manifest.optionalMods());
        List<Violation> violations = new ArrayList<>();

        for (Map.Entry<String, String> loaded : normalizedLoaded.entrySet()) {
            String id = loaded.getKey();
            String version = loaded.getValue();
            boolean blocked = manifest.blockedModIdSubstrings().stream()
                    .filter(fragment -> !fragment.isBlank())
                    .map(fragment -> fragment.toLowerCase(Locale.ROOT))
                    .anyMatch(id::contains);
            if (blocked) {
                violations.add(new Violation(id, version, "", Reason.BLOCKED));
                continue;
            }
            if (!accepted.contains(id)) {
                violations.add(new Violation(id, version, "", Reason.UNKNOWN));
                continue;
            }
            String expected = manifest.allowedMods().getOrDefault(id, "*");
            if (!versionMatches(version, expected)) {
                violations.add(new Violation(id, version, expected, Reason.VERSION));
            }
        }

        for (String required : manifest.requiredMods()) {
            if (!normalizedLoaded.containsKey(required)) {
                violations.add(new Violation(required, "", manifest.allowedMods().getOrDefault(required, "*"),
                        Reason.MISSING));
            }
        }

        violations.sort(java.util.Comparator
                .comparing((Violation violation) -> violation.reason().ordinal())
                .thenComparing(Violation::modId));
        return new Report(violations, normalizedLoaded, manifest.allowContinueOnMismatch(),
                manifest.downloadHintUrl());
    }

    private static boolean versionMatches(String installed, String expected) {
        if (expected == null || expected.isBlank() || "*".equals(expected)) {
            return true;
        }
        // Manifest pins may use a glob solely to absorb metadata build suffixes while keeping
        // the human-facing release fixed (for example 3.25.71.*).
        StringBuilder regex = new StringBuilder("^");
        for (int i = 0; i < expected.length(); i++) {
            char c = expected.charAt(i);
            if (c == '*') {
                regex.append(".*");
            } else {
                if ("\\.^$|?+()[]{}".indexOf(c) >= 0) {
                    regex.append('\\');
                }
                regex.append(c);
            }
        }
        return installed.matches(regex.append('$').toString());
    }

    private static ManifestData loadManifest() throws IOException {
        try (InputStream stream = PackBootstrap.class.getResourceAsStream(MANIFEST)) {
            if (stream == null) {
                throw new IOException("Embedded bootstrap manifest is missing");
            }
            JsonObject root = JsonParser.parseReader(
                    new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
            Map<String, String> allowed = new LinkedHashMap<>();
            for (Map.Entry<String, JsonElement> entry : root.getAsJsonObject("allowedMods").entrySet()) {
                allowed.put(entry.getKey().toLowerCase(Locale.ROOT), entry.getValue().getAsString());
            }
            return new ManifestData(
                    Collections.unmodifiableMap(allowed),
                    strings(root, "requiredMods"),
                    strings(root, "optionalMods"),
                    strings(root, "blockedModIdSubstrings"),
                    root.has("allowContinueOnMismatch") && root.get("allowContinueOnMismatch").getAsBoolean(),
                    root.has("downloadHintUrl") ? root.get("downloadHintUrl").getAsString() : "");
        }
    }

    private static List<String> strings(JsonObject root, String key) {
        if (!root.has(key) || !root.get(key).isJsonArray()) {
            return List.of();
        }
        List<String> values = new ArrayList<>();
        for (JsonElement element : root.getAsJsonArray(key)) {
            values.add(element.getAsString().toLowerCase(Locale.ROOT));
        }
        return List.copyOf(values);
    }
}
