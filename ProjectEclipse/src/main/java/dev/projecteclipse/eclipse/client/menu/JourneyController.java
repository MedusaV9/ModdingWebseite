package dev.projecteclipse.eclipse.client.menu;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeParseException;

import javax.annotation.Nullable;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseJourneyConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.ConnectScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.multiplayer.ServerData;
import net.minecraft.client.multiplayer.resolver.ServerAddress;
import net.minecraft.network.chat.Component;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Client brain of the "Reise beginnen" flow ({@code docs/plans_v3/P3_ui.md} §3.8, P3-W8):
 * reads {@code eclipse-journey.toml} live (hot — the NeoForge file watcher reloads disk edits,
 * and every evaluation re-reads the spec values), decides the title-screen button matrix
 * (modpackMode x devUnlock x cached op), evaluates the DATE+TIME gate and performs the direct
 * {@link ConnectScreen} connect.
 *
 * <p><b>Gate & timezone semantics</b>: {@code activationIso} is parsed as ISO-8601. With an
 * offset/zone ({@code 2026-08-01T18:00:00+02:00}, {@code …Z}, {@code …[Europe/Berlin]}) it
 * denotes one ABSOLUTE instant — every player unlocks at the same real-world moment regardless
 * of their local timezone. A zoneless {@code 2026-08-01T18:00:00} falls back to the player's
 * system zone (each player unlocks at their own local 18:00 — tolerated, not recommended; the
 * config comment demands a zone). The comparison is {@code Instant.now() >= activation} against
 * the LOCAL system clock: deliberately a soft cosmetic gate, the server whitelist stays the
 * hard gate (plan §3.8 clock-source note + risk R-12).</p>
 *
 * <p><b>Op cache</b>: {@code config/eclipse-journey-state.json} {@code {"opGranted":bool}}
 * (§7.1b), rewritten from every {@code S2COpStatusPayload} so it mirrors server truth as of the
 * last modded-server login (granted OR revoked — revocation clears the flag, risk R-11).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class JourneyController {
    private static final String STATE_FILE_NAME = "eclipse-journey-state.json";

    // Parse cache keyed on the raw config string, so hot config edits re-parse exactly once.
    private static String cachedIsoRaw = null;
    @Nullable
    private static Instant cachedInstant = null;
    private static String warnedBadIso = null;

    private static boolean stateLoaded;
    private static boolean opGranted;

    private JourneyController() {}

    // ------------------------------------------------------------------ gate

    /** True when {@code activationIso} holds a parseable instant — the journey button exists at all. */
    public static boolean journeyConfigured() {
        return activationInstant() != null;
    }

    /** The parsed activation instant, or {@code null} when unset/malformed (button hidden). */
    @Nullable
    public static Instant activationInstant() {
        String raw = EclipseJourneyConfig.activationIso();
        if (!raw.equals(cachedIsoRaw)) {
            cachedIsoRaw = raw;
            cachedInstant = parseIso(raw);
        }
        return cachedInstant;
    }

    @Nullable
    private static Instant parseIso(String raw) {
        if (raw.isEmpty()) {
            return null;
        }
        try {
            // ISO_ZONED_DATE_TIME accepts plain offsets, Z and region-suffixed forms.
            return ZonedDateTime.parse(raw).toInstant();
        } catch (DateTimeParseException zonedFail) {
            try {
                // Graceful zoneless fallback: interpret in the player's system zone.
                return LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant();
            } catch (DateTimeParseException localFail) {
                if (!raw.equals(warnedBadIso)) {
                    warnedBadIso = raw;
                    EclipseMod.LOGGER.warn(
                            "eclipse-journey.toml activationIso '{}' is not ISO-8601 "
                                    + "(expected e.g. 2026-08-01T18:00:00+02:00) — journey button hidden",
                            raw);
                }
                return null;
            }
        }
    }

    /** Date gate: {@code devUnlock} bypasses; otherwise the local clock must have reached the instant. */
    public static boolean unlocked() {
        if (EclipseJourneyConfig.devUnlock()) {
            return true;
        }
        Instant activation = activationInstant();
        return activation != null && !Instant.now().isBefore(activation);
    }

    /** Milliseconds until activation (0 when reached/unset); display-only. */
    public static long remainingMillis() {
        Instant activation = activationInstant();
        if (activation == null) {
            return 0L;
        }
        return Math.max(0L, activation.toEpochMilli() - System.currentTimeMillis());
    }

    /** DIM countdown line / disabled-button tooltip: "Öffnet in 3T 14h 02m". */
    public static Component countdownComponent() {
        return EclipseLang.tr("gui.eclipse.journey.countdown", formatRemaining(remainingMillis()));
    }

    /** {@code 3T 14h 02m} / {@code 14h 02m 33s} / {@code 02m 33s} with a localized day suffix. */
    public static String formatRemaining(long millis) {
        long totalSeconds = (millis + 999L) / 1000L; // ceil: never shows zero while still locked
        long days = totalSeconds / 86400L;
        long hours = (totalSeconds % 86400L) / 3600L;
        long minutes = (totalSeconds % 3600L) / 60L;
        long seconds = totalSeconds % 60L;
        String daySuffix = EclipseLang.trString("gui.eclipse.journey.countdown.days");
        if (days > 0) {
            return String.format("%d%s %02dh %02dm", days, daySuffix, hours, minutes);
        }
        if (totalSeconds >= 3600L) {
            return String.format("%02dh %02dm %02ds", hours, minutes, seconds);
        }
        return String.format("%02dm %02ds", minutes, seconds);
    }

    // ---------------------------------------------------------- button matrix

    /** Singleplayer/Multiplayer visibility: modpack mode hides them unless dev/op unlocked. */
    public static boolean showVanillaEntries() {
        return !EclipseJourneyConfig.modpackMode() || EclipseJourneyConfig.devUnlock() || opGranted();
    }

    /**
     * Change-detection key for the title screen's per-tick rebuild check — covers every input
     * of the button matrix so hot config edits (file watcher) apply without reopening the menu.
     */
    public static String menuFingerprint() {
        return (journeyConfigured() ? 'j' : '-') + "" + (unlocked() ? 'u' : '-')
                + (EclipseJourneyConfig.modpackMode() ? 'm' : '-')
                + (showVanillaEntries() ? 'v' : '-');
    }

    // ---------------------------------------------------------------- op cache

    /** Cached op>=2 flag from the last modded-server login ({@code eclipse-journey-state.json}). */
    public static boolean opGranted() {
        if (!stateLoaded) {
            stateLoaded = true;
            opGranted = readStateFile();
        }
        return opGranted;
    }

    /** {@code S2COpStatusPayload} receipt (client main thread): mirror server truth, persist on change. */
    public static void onOpStatus(int opLevel) {
        boolean granted = opLevel >= 2;
        if (opGranted() != granted) {
            opGranted = granted;
            writeStateFile(granted);
            EclipseMod.LOGGER.info("Journey op cache updated: opLevel={} -> opGranted={}", opLevel, granted);
        }
    }

    private static Path stateFile() {
        return FMLPaths.CONFIGDIR.get().resolve(STATE_FILE_NAME);
    }

    private static boolean readStateFile() {
        try {
            Path file = stateFile();
            if (!Files.exists(file)) {
                return false;
            }
            JsonObject json = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8))
                    .getAsJsonObject();
            return json.has("opGranted") && json.get("opGranted").getAsBoolean();
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("Could not read {} — treating op cache as false", STATE_FILE_NAME, e);
            return false;
        }
    }

    private static void writeStateFile(boolean granted) {
        try {
            JsonObject json = new JsonObject();
            json.addProperty("opGranted", granted);
            Files.writeString(stateFile(), json + System.lineSeparator(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Could not write {} — op cache will reset next boot", STATE_FILE_NAME, e);
        }
    }

    // ------------------------------------------------------------------ connect

    /**
     * Direct connect to the configured event server via the vanilla
     * {@link ConnectScreen#startConnecting} API (1.21.1 signature: parent, minecraft, address,
     * serverData, isQuickPlay=false, transferState=null). Connect/auth failures land on the
     * vanilla DisconnectedScreen whose Back returns to {@code parent} (accepted per §3.8).
     *
     * @return {@code null} on success, otherwise a localized error line for the themed
     *         error panel — this method never throws (plan risk R-2).
     */
    @Nullable
    public static Component tryConnect(Screen parent) {
        String host = EclipseJourneyConfig.serverHost();
        if (host.isEmpty()) {
            return EclipseLang.tr("gui.eclipse.journey.error.nohost");
        }
        // An explicit host:port (incl. bracketed IPv6 "[::1]:25565") wins over serverPort.
        String full = host.contains(":") ? host : host + ":" + EclipseJourneyConfig.serverPort();
        try {
            if (!ServerAddress.isValidAddress(full)) {
                return EclipseLang.tr("gui.eclipse.journey.error.connect", full);
            }
            ServerData data = new ServerData(EclipseLang.trString("gui.eclipse.journey.server_name"),
                    full, ServerData.Type.OTHER);
            ConnectScreen.startConnecting(parent, Minecraft.getInstance(),
                    ServerAddress.parseString(full), data, false, null);
            return null;
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("Journey connect to '{}' failed before handshake", full, e);
            return EclipseLang.tr("gui.eclipse.journey.error.connect", full);
        }
    }
}
