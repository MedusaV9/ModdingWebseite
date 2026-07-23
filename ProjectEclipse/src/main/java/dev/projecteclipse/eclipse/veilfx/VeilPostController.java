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
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
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
 *   <li>{@code eclipse:border_glitch} — chromatic aberration + horizontal displacement
 *       bands near the soft border (W7). Active while {@code border.client.BorderFxRenderer}
 *       reports a border proximity &gt; 0 via {@link #setBorderProximity}; the
 *       {@code Proximity} and {@code Time} uniforms are fed per frame.</li>
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
    public static final ResourceLocation BORDER_GLITCH_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border_glitch");

    /** Limbo grade fade-in length (~2 s). */
    private static final int LIMBO_FADE_TICKS = 40;
    private static final long LIMBO_FADE_MILLIS = LIMBO_FADE_TICKS * 50L;
    /** A pipeline that throws this many times is disabled for the session. */
    private static final int MAX_FAILURES = 2;

    private static final Map<ResourceLocation, Integer> FAILURES = new HashMap<>();
    private static final Set<ResourceLocation> DISABLED = ConcurrentHashMap.newKeySet();

    /** Epoch millis of entering limbo, or {@code -1} while not in limbo (drives the fade). */
    private static volatile long limboEnterMillis = -1L;

    /** Soft-border proximity in [0,1], fed each tick by {@code BorderFxRenderer}. */
    private static volatile float borderProximity = 0.0F;

    private VeilPostController() {}

    /** W7 hook: 0 = far from the soft border (pipeline off), 1 = touching the ring. */
    public static void setBorderProximity(float proximity) {
        borderProximity = Mth.clamp(proximity, 0.0F, 1.0F);
    }

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
                    } else if (BORDER_GLITCH_POST.equals(name)) {
                        pipeline.getUniform("Proximity").setFloat(borderProximity);
                        pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 100_000L) / 1000.0F);
                    }
                } catch (Throwable t) {
                    recordFailure(name, t);
                }
            });
        } catch (Throwable t) {
            EclipseMod.LOGGER.warn("Failed to register Veil post-processing uniform hook; Eclipse post FX disabled", t);
            DISABLED.add(LIMBO_POST);
            DISABLED.add(SUN_HALO_POST);
            DISABLED.add(BORDER_GLITCH_POST);
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
        setPipelineActive(BORDER_GLITCH_POST, borderProximity > 0.01F);
    }

    /**
     * Disconnect reset hook (mirrors {@code QuasarSpawner.DisconnectReset}): drops the fade
     * and proximity state and removes every Eclipse pipeline immediately. The tick handler
     * would also remove them one tick later on the title screen, but a Veil call that throws
     * during disconnect teardown must not count toward the {@value #MAX_FAILURES}-strikes
     * session disable — so this path removes quietly instead of via
     * {@link #setPipelineActive}, and a limbo session can never leak its grade into the next
     * world.
     */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        limboEnterMillis = -1L;
        borderProximity = 0.0F;
        removeQuietly(LIMBO_POST);
        removeQuietly(SUN_HALO_POST);
        removeQuietly(BORDER_GLITCH_POST);
    }

    /** Best-effort removal that never counts as a pipeline failure (teardown-order safe). */
    private static void removeQuietly(ResourceLocation pipeline) {
        try {
            PostProcessingManager manager = VeilRenderSystem.renderer().getPostProcessingManager();
            if (manager.isActive(pipeline)) {
                manager.remove(pipeline);
            }
        } catch (Throwable ignored) {
            // Veil may already be tearing down; the next-tick gate re-removes if needed.
        }
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
