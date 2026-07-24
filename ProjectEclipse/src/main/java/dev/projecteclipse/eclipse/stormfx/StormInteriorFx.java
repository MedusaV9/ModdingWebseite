package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayDeque;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.light.data.PointLightData;
import foundry.veil.api.client.render.light.renderer.LightRenderHandle;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.particles.ParticleTypes;
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
 *
 * <p><b>Wave-4 additions (IDEA-15):</b> vortex storms judge inside/outside against the tilted
 * radius at camera height (§6; EVAL-4 obs #1), camera teleports snap the smoothing instead of
 * easing (EVAL-4 M5), an {@link #approachAmount()} pre-tint drains daylight up to 15 % on the
 * outside approach (§1), interior arc/bolt {@link #flash(int)} beats lift the far plane 24→56
 * with a violet-white color blow (§2), and the storm-center loot camp bleeds ONE budgeted warm
 * point light + ember motes through the fog at 12–45 blocks (§3).</p>
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

    /** IDEA-15 §6 (EVAL-4 M5): camera jumps beyond this in one tick snap the smoothing. */
    private static final double TELEPORT_SNAP_DIST_SQ = 32.0D * 32.0D;

    /** IDEA-15 §1 pre-tint: approach band (blocks from the shell) and max fog-color pull. */
    private static final float APPROACH_FAR = 60.0F;
    private static final float APPROACH_NEAR = 20.0F;
    private static final float APPROACH_TINT_MAX = 0.15F;

    /** IDEA-15 §2: arc/bolt flashes lift the fog far plane toward this (silhouette reveal). */
    private static final float FLASH_FOG_FAR = 56.0F;
    private static final int FLASH_MAX_TICKS = 6;
    /** Violet-white flash color — interior mobs become backlit cutouts for 4–6 ticks. */
    private static final float FLASH_R = 0.55F;
    private static final float FLASH_G = 0.50F;
    private static final float FLASH_B = 0.70F;

    /** IDEA-15 §3: loot-camp warm-glow window (horizontal blocks from storm center). */
    private static final double CAMP_GLOW_MIN_DIST = 12.0D;
    private static final double CAMP_GLOW_MAX_DIST = 45.0D;
    private static final double CAMP_GLOW_RELEASE_DIST = 50.0D;
    private static final float CAMP_GLOW_ENGAGE = 0.6F;
    private static final float CAMP_GLOW_RELEASE = 0.3F;
    private static final int EMBER_INTERVAL_TICKS = 10;

    /** Smoothed interior amount 0..1 (the render-facing value; raw target jumps at walls). */
    private static float smoothedInterior;
    /** Smoothed outside-approach amount 0..1 (1 at ≤20 blocks from a visible shell). */
    private static float smoothedApproach;
    /** Remaining silhouette-reveal flash ticks (decremented pause-safe in the client tick). */
    private static int flashTicks;
    /** Last camera position for the M5 teleport snap ({@code null} = fresh level/first tick). */
    @Nullable
    private static Vec3 lastCameraPos;

    /** ONE budgeted warm point light at the loot camp (Bolt.claimImpactLight pattern). */
    @Nullable
    private static LightRenderHandle<PointLightData> campLight;
    private static boolean campLightBudgeted;
    private static int emberCountdown;

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

    /** Outside-approach dread amount 0..1 (IDEA-15 §1); always 0 while interior. */
    public static float approachAmount() {
        return smoothedApproach;
    }

    /**
     * Silhouette-reveal flash (IDEA-15 §2): lifts the interior fog far plane 24→56 and blows
     * the slate toward violet-white for {@code ticks} ticks. Callers gate on
     * {@link #interiorAmount()} &gt; 0.5 (interior arcs/bolts only).
     */
    static void flash(int ticks) {
        flashTicks = Math.max(flashTicks, Math.min(ticks, FLASH_MAX_TICKS));
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
        float approachTarget = approachTargetAt(camera, target);
        // EVAL-4 M5: a teleport (> 32 blocks in one tick) snaps instead of easing — interior
        // fog must never linger for ~1–2 s after warping out of (or into) a storm.
        boolean snap = lastCameraPos != null
                && camera.distanceToSqr(lastCameraPos) > TELEPORT_SNAP_DIST_SQ;
        lastCameraPos = camera;
        if (snap) {
            smoothedInterior = target;
            smoothedApproach = approachTarget;
        } else {
            smoothedInterior += (target - smoothedInterior) * SMOOTHING;
            smoothedApproach += (approachTarget - smoothedApproach) * SMOOTHING;
        }
        if (smoothedInterior < 0.002F) {
            smoothedInterior = 0.0F;
        }
        if (smoothedApproach < 0.002F) {
            smoothedApproach = 0.0F;
        }
        if (flashTicks > 0) {
            flashTicks--; // pause-safe: same guard as smoothedInterior (IDEA-15 §2)
        }
        // Rain rides the interior amount (R14: rain exists only inside the storm).
        EclipseFxState.setStormInterior(smoothedInterior, smoothedInterior);
        tickRainSheets(level, camera);
        tickCampGlow(level, camera);
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
            // IDEA-15 §6 (EVAL-4 obs #1): vortex shells lean inward 8°, so "inside" must be
            // judged against the TILTED radius at camera height (mirror of emitShell's
            // topRadius math) — never the base radius, which over-reaches for high cameras.
            double effectiveRadius = storm.radius;
            if (storm.type == S2CStormStatePayload.TYPE_VORTEX) {
                double above = Math.max(0.0D, camera.y - storm.center.y);
                effectiveRadius = Math.max(storm.radius * 0.25D,
                        storm.radius - above * StormWallRenderer.TAN_TILT);
            }
            float horiz = (float) Mth.clamp(
                    ((effectiveRadius - StormWallRenderer.OCCLUDER_INSET) - dist) / INTERIOR_FEATHER,
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

    /**
     * IDEA-15 §1 pre-tint target: {@code smoothstep(60, 20, shellDist)} of the nearest
     * sufficiently-visible storm — outside only (any interior coverage zeroes it so the
     * interior grade owns the palette during and after the crossing).
     */
    private static float approachTargetAt(Vec3 camera, float interiorTarget) {
        if (interiorTarget > 0.0F) {
            return 0.0F;
        }
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        float best = 0.0F;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            float visibility = storm.visibility(1.0F);
            if (visibility < 0.5F) {
                continue;
            }
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            float shellDist = (float) Math.abs(Math.sqrt(dx * dx + dz * dz) - storm.radius);
            float t = Mth.clamp((APPROACH_FAR - shellDist) / (APPROACH_FAR - APPROACH_NEAR), 0.0F, 1.0F);
            float amount = t * t * (3.0F - 2.0F * t) * visibility;
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
        // IDEA-15 §2: an interior arc/bolt flash lifts the far plane 24→56 for 4–6 ticks so
        // everything sharing the fog reads as a black silhouette. Near stays pinched at 6 —
        // depth snaps into view, not clarity.
        float lift = Mth.clamp(flashTicks / (float) FLASH_MAX_TICKS, 0.0F, 1.0F);
        float farTarget = Mth.lerp(lift, INTERIOR_FOG_FAR, FLASH_FOG_FAR);
        event.setFarPlaneDistance(Math.min(far, Mth.lerp(interior, far, farTarget)));
        event.setNearPlaneDistance(Math.min(near, Mth.lerp(interior, near, INTERIOR_FOG_NEAR)));
        event.setCanceled(true);
    }

    @SubscribeEvent
    static void onComputeFogColor(ViewportEvent.ComputeFogColor event) {
        float interior = smoothedInterior;
        float approach = smoothedApproach;
        if (interior <= 0.02F && approach <= 0.02F) {
            return;
        }
        // IDEA-15 §2: flash blows the slate toward violet-white — backlit cutouts.
        float lift = interior > 0.02F
                ? Mth.clamp(flashTicks / (float) FLASH_MAX_TICKS, 0.0F, 1.0F) * 0.7F
                : 0.0F;
        float targetR = Mth.lerp(lift, FOG_R, FLASH_R);
        float targetG = Mth.lerp(lift, FOG_G, FLASH_G);
        float targetB = Mth.lerp(lift, FOG_B, FLASH_B);
        // IDEA-15 §1: outside, daylight drains up to 15 % toward the storm slate as you close.
        float blend = Math.max(interior * 0.92F, approach * APPROACH_TINT_MAX);
        event.setRed(Mth.lerp(blend, event.getRed(), targetR));
        event.setGreen(Mth.lerp(blend, event.getGreen(), targetG));
        event.setBlue(Mth.lerp(blend, event.getBlue(), targetB));
    }

    // ------------------------------------------------------------------ loot-camp glow (IDEA-15 §3)

    /**
     * ONE budgeted warm point light + ember motes at the storm-center loot camp: engages at
     * interior &gt; {@value #CAMP_GLOW_ENGAGE} within 12–45 blocks of the center, releases
     * below {@value #CAMP_GLOW_RELEASE} interior or beyond 50 blocks. The only warm hue in
     * the storm palette — an "over there" beacon with no UI. Interior-only by construction
     * (the occluder never-see-inside guarantee is untouched).
     */
    private static void tickCampGlow(ClientLevel level, Vec3 camera) {
        StormFxClient.ClientStorm storm = nearestStorm(camera);
        double dist = Double.MAX_VALUE;
        if (storm != null) {
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            dist = Math.sqrt(dx * dx + dz * dz);
        }
        if (campLight == null) {
            if (storm == null || smoothedInterior < CAMP_GLOW_ENGAGE
                    || dist < CAMP_GLOW_MIN_DIST || dist > CAMP_GLOW_MAX_DIST) {
                return;
            }
            claimCampLight(storm);
        } else if (storm == null || smoothedInterior < CAMP_GLOW_RELEASE
                || dist > CAMP_GLOW_RELEASE_DIST) {
            releaseCampLight();
            return;
        }
        if (campLight == null || storm == null) {
            return;
        }
        try {
            campLight.getLightData().setBrightness(0.5F * smoothedInterior);
            campLight.markDirty();
        } catch (Throwable t) {
            releaseCampLight();
            return;
        }
        // Fog "cracks": one rising ember mote per ~10 ticks so the smudge flickers alive.
        if (--emberCountdown <= 0) {
            emberCountdown = EclipseClientConfig.reducedFx()
                    ? EMBER_INTERVAL_TICKS * 2 : EMBER_INTERVAL_TICKS;
            RandomSource random = level.random;
            level.addParticle(ParticleTypes.SMALL_FLAME,
                    storm.center.x + (random.nextDouble() - 0.5D) * 3.0D,
                    storm.center.y + 0.6D + random.nextDouble() * 1.4D,
                    storm.center.z + (random.nextDouble() - 0.5D) * 3.0D,
                    0.0D, 0.03D + random.nextDouble() * 0.03D, 0.0D);
        }
    }

    @Nullable
    private static StormFxClient.ClientStorm nearestStorm(Vec3 camera) {
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        StormFxClient.ClientStorm nearest = null;
        double bestSq = Double.MAX_VALUE;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            double distSq = dx * dx + dz * dz;
            if (distSq < bestSq) {
                bestSq = distSq;
                nearest = storm;
            }
        }
        return nearest;
    }

    private static void claimCampLight(StormFxClient.ClientStorm storm) {
        if (!FxBudget.tryLight()) {
            return; // over the global light budget — the camp keeps its vanilla fire glow
        }
        campLightBudgeted = true;
        try {
            PointLightData data = new PointLightData()
                    .setPosition(storm.center.x, storm.center.y + 3.0D, storm.center.z)
                    .setColor(1.0F, 0.62F, 0.25F)
                    .setBrightness(0.5F * smoothedInterior)
                    .setRadius(14.0F);
            campLight = VeilRenderSystem.renderer().getLightRenderer().addLight(data);
        } catch (Throwable t) {
            releaseCampLight();
        }
    }

    private static void releaseCampLight() {
        LightRenderHandle<PointLightData> handle = campLight;
        campLight = null;
        if (handle != null) {
            try {
                handle.free();
            } catch (Throwable ignored) {
                // Veil may already be tearing down.
            }
        }
        if (campLightBudgeted) {
            campLightBudgeted = false;
            FxBudget.releaseLight();
        }
        emberCountdown = 0;
    }

    // ------------------------------------------------------------------ housekeeping

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    /** Respawn/dimension change (EVAL-4 M5): interior fog must never survive the warp. */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        reset();
    }

    private static void reset() {
        smoothedInterior = 0.0F;
        smoothedApproach = 0.0F;
        flashTicks = 0;
        lastCameraPos = null;
        EclipseFxState.setStormInterior(0.0F, 0.0F);
        clearRain();
        releaseCampLight();
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
