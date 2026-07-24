package dev.projecteclipse.eclipse.ritual;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.config.ModConfig;
import net.neoforged.fml.event.lifecycle.FMLConstructModEvent;
import net.neoforged.fml.loading.FMLEnvironment;
import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * Standalone config of the C15 final credits sequence ({@code MusicConfig} pattern —
 * keeping these specs separate avoids touching the frozen {@code EclipseConfig} /
 * {@code EclipseClientConfig} schemas):
 * <ul>
 *   <li><b>Common</b> {@code creditsEnabled} — the server-side kill-switch. When off,
 *       {@code CreditsSequence.begin} refuses and {@code FinaleRitual} falls back to the
 *       pre-C15 {@code bringEveryoneHome} + {@code finale_return} ending.</li>
 *   <li><b>Client</b> {@code allowFinaleClose} — the {@code Minecraft.stop()} kill-switch
 *       (IDEAS §B3). Default <b>true</b>: this is an event pack and the self-closing client
 *       IS the ending; ops flip it off for rehearsals.</li>
 * </ul>
 */
public final class CreditsConfig {
    public static final String COMMON_FILE_NAME = "eclipse-credits-common.toml";
    public static final String CLIENT_FILE_NAME = "eclipse-credits-client.toml";

    private static final ModConfigSpec.Builder COMMON_BUILDER = new ModConfigSpec.Builder();
    private static final ModConfigSpec.BooleanValue CREDITS_ENABLED = COMMON_BUILDER
            .comment("Run the day-14 final credits sequence after the Ferryman victory",
                    "(false = the pre-credits behavior: trip home + finale_return descent).")
            .define("creditsEnabled", true);
    public static final ModConfigSpec COMMON_SPEC = COMMON_BUILDER.build();

    private static final ModConfigSpec.Builder CLIENT_BUILDER = new ModConfigSpec.Builder();
    private static final ModConfigSpec.BooleanValue ALLOW_FINALE_CLOSE = CLIENT_BUILDER
            .comment("Allow the final credits sequence to close your game at the very end",
                    "(never applies in singleplayer/LAN; false = the close request is ignored).")
            .define("allowFinaleClose", true);
    public static final ModConfigSpec CLIENT_SPEC = CLIENT_BUILDER.build();

    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    private CreditsConfig() {}

    public static void register(ModContainer modContainer) {
        if (REGISTERED.compareAndSet(false, true)) {
            modContainer.registerConfig(ModConfig.Type.COMMON, COMMON_SPEC, COMMON_FILE_NAME);
            if (FMLEnvironment.dist.isClient()) {
                modContainer.registerConfig(ModConfig.Type.CLIENT, CLIENT_SPEC, CLIENT_FILE_NAME);
            }
        }
    }

    /** Server-side: whether the credits sequence replaces the plain finale return. */
    public static boolean creditsEnabled() {
        return !COMMON_SPEC.isLoaded() || CREDITS_ENABLED.get();
    }

    /** Client-side: whether the close broadcast may actually stop this client. */
    public static boolean allowFinaleClose() {
        return !CLIENT_SPEC.isLoaded() || ALLOW_FINALE_CLOSE.get();
    }

    /** Self-registration on both dists; no shared config hub edit is required. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    static final class SelfRegistrar {
        private SelfRegistrar() {}

        @SubscribeEvent
        static void onConstruct(FMLConstructModEvent event) {
            event.enqueueWork(() -> ModList.get().getModContainerById(EclipseMod.MOD_ID)
                    .ifPresent(CreditsConfig::register));
        }
    }
}
