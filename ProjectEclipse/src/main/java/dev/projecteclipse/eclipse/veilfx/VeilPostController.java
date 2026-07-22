package dev.projecteclipse.eclipse.veilfx;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.sky.EclipseIrisState;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.post.PostProcessingManager;
import foundry.veil.api.client.util.Easing;
import foundry.veil.platform.VeilEventPlatform;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Owns the Eclipse Veil post-processing pipelines:
 * <ul>
 *   <li>{@code eclipse:limbo} — purple grade + vignette, auto-on in the limbo dimension.
 *       The {@code Intensity} uniform fades 0&rarr;1 over ~{@value #LIMBO_FADE_TICKS} ticks
 *       ({@link Easing#EASE_OUT_QUAD}) after entering limbo.</li>
 *   <li>{@code eclipse:sun_halo} — depth-masked additive purple rim around the sun,
 *       auto-on in the overworld. The {@code SunDirection} uniform is fed per frame from
 *       {@code level.getSunAngle(partialTick)}.</li>
 * </ul>
 *
 * <p>HARD GATE: pipelines are only ever added while no Iris shaderpack is active
 * ({@link EclipseIrisState#shaderPackActive()}) and {@link EclipseClientConfig#veilPostFx()}
 * is enabled — with a pack active the v1 fallbacks (limbo biome water/fog colors, the
 * {@code sun.png} override + fog tint) carry the look instead. Every Veil call is try/caught;
 * a pipeline that throws twice is disabled for the rest of the session.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class VeilPostController {
    public static final ResourceLocation LIMBO_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo");
    public static final ResourceLocation SUN_HALO_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "sun_halo");

    /** Limbo grade fade-in length (~2 s). */
    private static final int LIMBO_FADE_TICKS = 40;
    private static final long LIMBO_FADE_MILLIS = LIMBO_FADE_TICKS * 50L;
    /** A pipeline that throws this many times is disabled for the session. */
    private static final int MAX_FAILURES = 2;

    private static final Map<ResourceLocation, Integer> FAILURES = new HashMap<>();
    private static final Set<ResourceLocation> DISABLED = ConcurrentHashMap.newKeySet();

    /** Epoch millis of entering limbo, or {@code -1} while not in limbo (drives the fade). */
    private static volatile long limboEnterMillis = -1L;

    private VeilPostController() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Per-frame uniform feed; fires only while one of our pipelines is actually active.
        try {
            VeilEventPlatform.INSTANCE.preVeilPostProcessing((name, pipeline, context) -> {
                try {
                    if (LIMBO_POST.equals(name)) {
                        pipeline.getUniform("Intensity").setFloat(limboIntensity());
                    } else if (SUN_HALO_POST.equals(name)) {
                        ClientLevel level = Minecraft.getInstance().level;
                        if (level != null) {
                            float partialTick = Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
                            float angle = level.getSunAngle(partialTick);
                            // Same celestial frame as the vanilla sky: RotY(-90°) * RotX(angle) * (0,100,0).
                            pipeline.getUniform("SunDirection").setFloats(-Mth.sin(angle), Mth.cos(angle), 0.0F);
                        }
                    }
                } catch (Throwable t) {
                    recordFailure(name, t);
                }
            });
        } catch (Throwable t) {
            EclipseMod.LOGGER.warn("Failed to register Veil post-processing uniform hook; Eclipse post FX disabled", t);
            DISABLED.add(LIMBO_POST);
            DISABLED.add(SUN_HALO_POST);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        ClientLevel level = Minecraft.getInstance().level;
        boolean inLimbo = level != null && level.dimension() == LimboDimension.LIMBO;
        boolean inOverworld = level != null && level.dimension() == Level.OVERWORLD;

        if (inLimbo) {
            if (limboEnterMillis < 0L) {
                limboEnterMillis = System.currentTimeMillis();
            }
        } else {
            limboEnterMillis = -1L;
        }

        setPipelineActive(LIMBO_POST, inLimbo);
        setPipelineActive(SUN_HALO_POST, inOverworld);
    }

    /**
     * Adds/removes the pipeline to match {@code wanted}. The add path additionally requires the
     * hard gate ({@code !shaderPackActive() && veilPostFx()}), so flipping the config off or
     * enabling a shaderpack mid-flight removes active pipelines on the next tick.
     */
    private static void setPipelineActive(ResourceLocation pipeline, boolean wanted) {
        if (DISABLED.contains(pipeline)) {
            return;
        }
        boolean gate = !EclipseIrisState.shaderPackActive() && EclipseClientConfig.veilPostFx();
        try {
            PostProcessingManager manager = VeilRenderSystem.renderer().getPostProcessingManager();
            boolean active = manager.isActive(pipeline);
            if (wanted && gate && !active) {
                manager.add(pipeline);
            } else if (active && (!wanted || !gate)) {
                manager.remove(pipeline);
            }
        } catch (Throwable t) {
            recordFailure(pipeline, t);
        }
    }

    /** Current limbo grade intensity in [0,1]; eased fade-in after entering limbo. */
    private static float limboIntensity() {
        long start = limboEnterMillis;
        if (start < 0L) {
            return 0.0F;
        }
        float linear = Mth.clamp((System.currentTimeMillis() - start) / (float) LIMBO_FADE_MILLIS, 0.0F, 1.0F);
        return Easing.EASE_OUT_QUAD.ease(linear);
    }

    private static void recordFailure(ResourceLocation pipeline, Throwable t) {
        int count = FAILURES.merge(pipeline, 1, Integer::sum);
        if (count == 1) {
            EclipseMod.LOGGER.warn("Veil post pipeline {} threw; retrying once", pipeline, t);
        } else if (count >= MAX_FAILURES && DISABLED.add(pipeline)) {
            EclipseMod.LOGGER.warn("Veil post pipeline {} failed {} times; disabling it for this session", pipeline, count);
            try {
                VeilRenderSystem.renderer().getPostProcessingManager().remove(pipeline);
            } catch (Throwable ignored) {
                // Removing a broken pipeline is best-effort; it is disabled either way.
            }
        }
    }
}
