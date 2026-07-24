package dev.projecteclipse.eclipse.core.config;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.config.ModConfig;
import net.neoforged.fml.event.lifecycle.FMLConstructModEvent;
import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * "Reise beginnen" journey settings ({@code docs/plans_v3/P3_ui.md} §3.8 / §7.1b, P3-W8).
 * Deliberately a SEPARATE file from {@code eclipse-client.toml}: {@code eclipse-journey.toml}
 * is the single switch P5 ships in the modpack config overrides (activation instant + event
 * server address + modpack mode), while W3's cosmetic toggles stay player-owned.
 *
 * <p>Keys (all hot-read — NeoForge's config-file watcher reloads edited TOMLs at runtime, and
 * every getter reads the live value, so a disk edit applies on the next click / title-screen
 * tick without a game restart):</p>
 * <ul>
 *   <li>{@code serverHost} (default {@code ""}) — event server host/IP. May carry an explicit
 *       {@code host:port} (wins over {@code serverPort}); IPv6 literals must be bracketed.</li>
 *   <li>{@code serverPort} (default {@code 25565}) — event server port.</li>
 *   <li>{@code activationIso} (default {@code ""}) — the activation instant, ISO-8601 WITH
 *       zone/offset, e.g. {@code 2026-08-01T18:00:00+02:00}. Empty/unparseable = journey
 *       button hidden. Parsed by {@code client.menu.JourneyController} on every evaluation.</li>
 *   <li>{@code modpackMode} (default {@code false}) — hides Singleplayer/Multiplayer on the
 *       custom title screen (Realms/Mods never exist there). Default OFF so dev testing keeps
 *       the full menu; P5 flips it to {@code true} in the shipped pack.</li>
 *   <li>{@code devUnlock} (default {@code false}) — dev escape hatch: restores all buttons AND
 *       bypasses the date gate.</li>
 * </ul>
 *
 * <p>All getters are safe on either dist and before the file is loaded (built-in default).
 * Registration is idempotent: the nested {@link SelfRegistrar} registers the spec during mod
 * construction on the client, and an explicit {@code EclipseJourneyConfig.register(modContainer)}
 * hub line (if the integrator prefers the {@code EclipseMod} convention) simply wins the flag —
 * never both.</p>
 */
public final class EclipseJourneyConfig {
    public static final String FILE_NAME = "eclipse-journey.toml";

    private static final ModConfigSpec.Builder BUILDER = new ModConfigSpec.Builder();

    private static final ModConfigSpec.ConfigValue<String> SERVER_HOST = BUILDER
            .comment("Event server host or IP for the 'Reise beginnen' direct connect.",
                    "May include an explicit port as host:port (then serverPort is ignored).",
                    "Bracket raw IPv6 literals: [2001:db8::1]:25565.")
            .define("serverHost", "");
    private static final ModConfigSpec.IntValue SERVER_PORT = BUILDER
            .comment("Event server port (ignored when serverHost already carries host:port).")
            .defineInRange("serverPort", 25565, 1, 65535);
    private static final ModConfigSpec.ConfigValue<String> ACTIVATION_ISO = BUILDER
            .comment("Activation instant for the journey button, ISO-8601 with zone/offset,",
                    "e.g. 2026-08-01T18:00:00+02:00 or 2026-08-01T16:00:00Z.",
                    "Before this instant clicking plays the glitch-error theater; after it the",
                    "button connects directly. Empty = journey button hidden entirely.",
                    "NOTE: evaluated against the PLAYER'S LOCAL CLOCK — cosmetic soft gate only;",
                    "the server whitelist remains the hard gate (P3 plan §3.8/§5.3).")
            .define("activationIso", "");
    private static final ModConfigSpec.BooleanValue MODPACK_MODE = BUILDER
            .comment("Modpack mode: remove Singleplayer/Multiplayer from the custom Eclipse title",
                    "screen (Realms/Mods buttons do not exist on it). Buttons reappear for",
                    "devUnlock=true or a cached op>=2 flag (config/eclipse-journey-state.json).",
                    "Default false so development keeps the full menu; the shipped pack sets true.")
            .define("modpackMode", false);
    private static final ModConfigSpec.BooleanValue DEV_UNLOCK = BUILDER
            .comment("Developer unlock: restores all title buttons and bypasses the date gate.")
            .define("devUnlock", false);

    public static final ModConfigSpec SPEC = BUILDER.build();

    private static final AtomicBoolean REGISTERED = new AtomicBoolean(false);

    private EclipseJourneyConfig() {}

    /**
     * Registers the CLIENT-type spec under {@value #FILE_NAME}. Idempotent — safe to call from
     * an {@code EclipseMod} ledger line even though {@link SelfRegistrar} exists.
     */
    public static void register(ModContainer modContainer) {
        if (REGISTERED.compareAndSet(false, true)) {
            modContainer.registerConfig(ModConfig.Type.CLIENT, SPEC, FILE_NAME);
        }
    }

    public static String serverHost() {
        return SPEC.isLoaded() ? SERVER_HOST.get().trim() : "";
    }

    public static int serverPort() {
        return SPEC.isLoaded() ? SERVER_PORT.get() : 25565;
    }

    public static String activationIso() {
        return SPEC.isLoaded() ? ACTIVATION_ISO.get().trim() : "";
    }

    public static boolean modpackMode() {
        return SPEC.isLoaded() && MODPACK_MODE.get();
    }

    public static boolean devUnlock() {
        return SPEC.isLoaded() && DEV_UNLOCK.get();
    }

    /**
     * Client-only self-registration during mod construction — runs BEFORE FML's "Config
     * loading" stage (verified against NeoForge 21.1 {@code CommonModLoader.begin} ordering),
     * so no {@code EclipseMod} hub edit is required. The dedicated server never registers the
     * spec; getters then return built-in defaults, matching {@code EclipseClientConfig}.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
    static final class SelfRegistrar {
        private SelfRegistrar() {}

        @SubscribeEvent
        static void onConstruct(FMLConstructModEvent event) {
            event.enqueueWork(() -> ModList.get().getModContainerById(EclipseMod.MOD_ID)
                    .ifPresent(EclipseJourneyConfig::register));
        }
    }
}
