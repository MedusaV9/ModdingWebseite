package dev.projecteclipse.eclipse.music;

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
 * Standalone client config for the custom score. Keeping this spec separate avoids changing the
 * frozen {@code EclipseClientConfig} schema.
 */
public final class MusicConfig {
    public static final String FILE_NAME = "eclipse-music.toml";

    private static final ModConfigSpec.Builder BUILDER = new ModConfigSpec.Builder();
    private static final ModConfigSpec.BooleanValue ENABLED = BUILDER
            .comment("Enable situation-driven Project: Eclipse music.")
            .define("enabled", true);
    private static final ModConfigSpec.DoubleValue VOLUME = BUILDER
            .comment("Volume multiplier applied in addition to Minecraft's Music slider.")
            .defineInRange("volumeMultiplier", 0.85D, 0.0D, 2.0D);

    public static final ModConfigSpec SPEC = BUILDER.build();
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    private MusicConfig() {}

    public static void register(ModContainer modContainer) {
        if (REGISTERED.compareAndSet(false, true)) {
            modContainer.registerConfig(ModConfig.Type.CLIENT, SPEC, FILE_NAME);
        }
    }

    public static boolean enabled() {
        return !SPEC.isLoaded() || ENABLED.get();
    }

    public static float volumeMultiplier() {
        return SPEC.isLoaded() ? VOLUME.get().floatValue() : 0.85F;
    }

    /** Client-only self-registration; no shared config hub edit is required. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
    static final class SelfRegistrar {
        private SelfRegistrar() {}

        @SubscribeEvent
        static void onConstruct(FMLConstructModEvent event) {
            event.enqueueWork(() -> ModList.get().getModContainerById(EclipseMod.MOD_ID)
                    .ifPresent(MusicConfig::register));
        }
    }
}
