package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayDeque;
import java.util.Iterator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.material.FogType;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.ViewportEvent;

/**
 * Everything the player experiences INSIDE a storm (P2 W9, R14 interior): vanilla fog clamped
 * to ~{@value #INTERIOR_FOG_FAR} blocks (a {@link ViewportEvent.RenderFog} subscription — no
 * mixin), the fog color pulled down to storm slate, looping {@code eclipse:storm_rain_sheet}
 * emitters in a rolling window around the camera, and the {@code eclipse:storm_interior}
 * post grade (uniforms {@code Interior, RainAmount, Time} — frozen §3.3) fed through
 * {@link EclipseFxState#setStormInterior}.
 *
 * <p>The interior amount rises from 0 to 1 while crossing the occluder band ({@code r −
 * }{@link StormWallRenderer#OCCLUDER_INSET} inward over {@value #INTERIOR_FEATHER} blocks),
 * fades over the storm's top/bottom bounds, scales with the storm's spawn/dissipate ramp and
 * is smoothed per tick — so fog/grade/rain all breathe in together and release together.
 * Fog + rain sheets work under Iris shaderpacks; only the post grade is gated off
 * ({@code VeilPostController} owns that gate).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormInteriorFx {
    public static final ResourceLocation STORM_INTERIOR_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_interior");
    private static final ResourceLocation RAIN_SHEET_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_rain_sheet");

    /** R14: fog end clamps to ~24 blocks inside. */
    private static final float INTERIOR_FOG_FAR = 24.0F;
    private static final float INTERIOR_FOG_NEAR = 6.0F;
    /** Blocks of feather from "at the occluder" to "fully interior". */
    private static final float INTERIOR_FEATHER = 3.0F;
    /** Interior fog color (storm slate; matches the wall palette). */
    private static final float FOG_R = 0.055F;
    private static final float FOG_G = 0.048F;
    private static final float FOG_B = 0.082F;
    /** Per-tick smoothing factor of the interior amount (≈ 6-tick ease). */
    private static final float SMOOTHING = 0.16F;

    /** Rain sheet cadence/window (loop emitters follow the camera; oldest culled). */
    private static final int RAIN_INTERVAL_TICKS = 14;
    private static final int MAX_RAIN_EMITTERS = 3;
    private static final double RAIN_SPAWN_RADIUS = 7.0D;
    private static final double RAIN_SPAWN_HEIGHT = 9.0D;

    /** Smoothed interior amount 0..1 (the render-facing value; raw target jumps at walls). */
    private static float smoothedInterior;

    private static final ArrayDeque<ParticleEmitter> RAIN_SHEETS = new ArrayDeque<>(MAX_RAIN_EMITTERS);
    private static int rainCountdown;

    static {
        // Feature-owned registration replaces nothing (new id) — GRADE priority per §3.3.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                STORM_INTERIOR_POST,
                VeilPostController.PipelinePriority.GRADE,
                () -> EclipseFxState.stormInterior() > 0.01F,
                pipeline -> {
                    pipeline.getUniform("Interior").setFloat(EclipseFxState.stormInterior());
                    pipeline.getUniform("RainAmount").setFloat(EclipseFxState.stormRain());
                    pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 100_000L) / 1000.0F);
                }));
    }

    private StormInteriorFx() {}

    /** Smoothed interior amount (0 outside every storm) — also read by sibling QA tooling. */
    public static float interiorAmount() {
        return smoothedInterior;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        float target = interiorTargetAt(camera);
        smoothedInterior += (target - smoothedInterior) * SMOOTHING;
        if (smoothedInterior < 0.002F) {
            smoothedInterior = 0.0F;
        }
        // Rain rides the interior amount (R14: rain exists only inside the storm).
        EclipseFxState.setStormInterior(smoothedInterior, smoothedInterior);
        tickRainSheets(level, camera);
    }

    /** Raw interior target: max over all storms of horizontal × vertical × ramp coverage. */
    private static float interiorTargetAt(Vec3 camera) {
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        float best = 0.0F;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            double dist = Math.sqrt(dx * dx + dz * dz);
            float horiz = (float) Mth.clamp(
                    ((storm.radius - StormWallRenderer.OCCLUDER_INSET) - dist) / INTERIOR_FEATHER,
                    0.0D, 1.0D);
            if (horiz <= 0.0F) {
                continue;
            }
            float top = (float) Mth.clamp((storm.center.y + storm.height + 8.0D - camera.y) / 8.0D, 0.0D, 1.0D);
            float bottom = (float) Mth.clamp((camera.y - (storm.center.y - 14.0D)) / 8.0D, 0.0D, 1.0D);
            float amount = horiz * top * bottom * storm.visibility(1.0F);
            if (amount > best) {
                best = amount;
            }
        }
        return best;
    }

    /** Rolling window of looping rain-sheet emitters around the camera (LimboAmbience pattern). */
    private static void tickRainSheets(ClientLevel level, Vec3 camera) {
        if (smoothedInterior < 0.25F) {
            if (smoothedInterior < 0.05F) {
                clearRain();
            }
            return;
        }
        pruneRain();
        if (--rainCountdown > 0) {
            return;
        }
        rainCountdown = EclipseClientConfig.reducedFx() ? RAIN_INTERVAL_TICKS * 2 : RAIN_INTERVAL_TICKS;
        RandomSource random = level.random;
        Vec3 pos = new Vec3(
                camera.x + (random.nextDouble() - 0.5D) * 2.0D * RAIN_SPAWN_RADIUS,
                camera.y + RAIN_SPAWN_HEIGHT + random.nextDouble() * 3.0D,
                camera.z + (random.nextDouble() - 0.5D) * 2.0D * RAIN_SPAWN_RADIUS);
        ParticleEmitter emitter = QuasarSpawner.spawnManaged(RAIN_SHEET_EMITTER, pos, FxBudget.Channel.STORM);
        if (emitter == null) {
            return; // budget refusal / Quasar unavailable — retry next interval
        }
        RAIN_SHEETS.addLast(emitter);
        while (RAIN_SHEETS.size() > MAX_RAIN_EMITTERS) {
            removeEmitter(RAIN_SHEETS.pollFirst());
        }
    }

    // ------------------------------------------------------------------ fog (works under Iris)

    /** Clamps the fog planes inside the storm — the event must be canceled to apply. */
    @SubscribeEvent
    static void onRenderFog(ViewportEvent.RenderFog event) {
        float interior = smoothedInterior;
        if (interior <= 0.02F || event.getType() != FogType.NONE) {
            return; // water/lava/powder-snow fog owns the camera
        }
        float far = event.getFarPlaneDistance();
        float near = event.getNearPlaneDistance();
        event.setFarPlaneDistance(Math.min(far, Mth.lerp(interior, far, INTERIOR_FOG_FAR)));
        event.setNearPlaneDistance(Math.min(near, Mth.lerp(interior, near, INTERIOR_FOG_NEAR)));
        event.setCanceled(true);
    }

    @SubscribeEvent
    static void onComputeFogColor(ViewportEvent.ComputeFogColor event) {
        float interior = smoothedInterior;
        if (interior <= 0.02F) {
            return;
        }
        float blend = interior * 0.92F;
        event.setRed(Mth.lerp(blend, event.getRed(), FOG_R));
        event.setGreen(Mth.lerp(blend, event.getGreen(), FOG_G));
        event.setBlue(Mth.lerp(blend, event.getBlue(), FOG_B));
    }

    // ------------------------------------------------------------------ housekeeping

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    private static void reset() {
        smoothedInterior = 0.0F;
        EclipseFxState.setStormInterior(0.0F, 0.0F);
        clearRain();
    }

    private static void pruneRain() {
        Iterator<ParticleEmitter> it = RAIN_SHEETS.iterator();
        while (it.hasNext()) {
            try {
                if (it.next().isRemoved()) {
                    it.remove();
                }
            } catch (Throwable t) {
                it.remove();
            }
        }
    }

    private static void clearRain() {
        if (RAIN_SHEETS.isEmpty()) {
            rainCountdown = 0;
            return;
        }
        for (ParticleEmitter emitter : RAIN_SHEETS) {
            removeEmitter(emitter);
        }
        RAIN_SHEETS.clear();
        rainCountdown = 0;
    }

    private static void removeEmitter(ParticleEmitter emitter) {
        try {
            if (!emitter.isRemoved()) {
                emitter.remove();
            }
        } catch (Throwable ignored) {
            // Teardown-order safe (QuasarSpawner.clearAttached pattern).
        }
    }
}
