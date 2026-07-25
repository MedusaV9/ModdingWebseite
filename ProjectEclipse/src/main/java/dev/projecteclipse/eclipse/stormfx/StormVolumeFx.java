package dev.projecteclipse.eclipse.stormfx;

import java.util.List;

import javax.annotation.Nullable;

import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * STORM-VOL — the TRUE VOLUMETRIC layer of C8 sphere storms: owns the
 * {@code eclipse:storm_volume} Veil post pipeline (a scene-depth-clamped fBm raymarcher —
 * see {@code assets/eclipse/pinwheel/shaders/program/storm_volume.fsh}) and feeds its
 * uniforms per frame through the {@link VeilPostController} row pattern (the
 * {@link StormInteriorFx} static-init seam, FEATURE priority).
 *
 * <p><b>Target selection (per tick):</b> the nearest SPHERE storm whose shell is within
 * {@value #VOLUME_RANGE} blocks and still visible. Gates: quality tier ≥ 1, never under
 * {@code reducedFx} (a fullscreen raymarch is the definition of motion-bearing FX), and
 * the pipeline itself only runs when {@code VeilPostController}'s Iris/veilPostFx gate
 * opens — under a shaderpack the CPU shell stack stays the complete fallback look.</p>
 *
 * <p><b>Renderer handshake:</b> {@link #isVolumeStorm(int)} tells
 * {@link StormWallRenderer} that the raymarch owns this storm's interior mass THIS tick,
 * so the renderer thins its EXO stack one tier and lifts the (still fully opaque)
 * occluder from near-black to deep slate-green — the volume paints continuous cloud over
 * it instead of silhouetting a black balloon. The flag is false whenever the pipeline is
 * not actually active in Veil's manager (Iris on, veilPostFx off, budget eviction,
 * failure fuse), so the frozen pre-volume look is preserved bit-for-bit there.</p>
 *
 * <p><b>Uniform contract</b> (all fed here, names frozen with the shader):
 * {@code VolCenter} (camera-relative centre), {@code VolRadius} (explosion-expanded),
 * {@code VolYScale} (spawn/dissipate vertical squash — {@link StormWallRenderer#heightScale}),
 * {@code Visibility}, {@code Strength} (distance ramp × explosion dissolve),
 * {@code StepCount} (64/40/24 by {@link FxBudget#qualityTier()}), {@code Time}
 * (tick-clock seconds, pause-safe), {@code SunDir} ({@link SunTracker}), {@code Interior}
 * ({@link StormInteriorFx#interiorAmount()} — the grade hand-over), {@code FlashPos} +
 * {@code FlashAmount} (the W-B intra-wall flash injected as emissive light inside the
 * mass; anchor mirrors {@code StormWeatherFx.claimLight}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormVolumeFx {
    public static final ResourceLocation STORM_VOLUME_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_volume");

    /** The volume pass engages while a sphere storm's shell is inside this distance. */
    private static final float VOLUME_RANGE = 420.0F;
    /** Strength ramps 1 → 0 over [fade-start, range] so the pass never pops at range. */
    private static final float STRENGTH_FADE_START = 340.0F;
    /** Raymarch step budget by quality tier (2/1/0) — the shader's quality ladder. */
    private static final float STEPS_TIER2 = 64.0F;
    private static final float STEPS_TIER1 = 40.0F;
    private static final float STEPS_TIER0 = 24.0F;
    /** Flash light anchor sits at this fraction of r on the flash bearing (W-C formula). */
    private static final double FLASH_RADIUS_FRAC = 0.92D;

    /** The one storm the raymarcher covers this tick ({@code null} = pipeline idle). */
    @Nullable
    private static StormFxClient.ClientStorm targetStorm;
    /** Cached per tick: the pipeline is genuinely active in Veil's post manager. */
    private static boolean pipelineLive;

    static {
        // Feature-owned registration (StormInteriorFx static-init seam) — FEATURE
        // priority: the volume composites ON TOP of the grades and must survive the
        // ≤3-concurrent eviction against them.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                STORM_VOLUME_POST,
                VeilPostController.PipelinePriority.FEATURE,
                () -> targetStorm != null,
                StormVolumeFx::feedVolume));
    }

    private StormVolumeFx() {}

    // ------------------------------------------------------------------ renderer reads

    /** True while the volumetric pass is live for ANY storm (Veil manager confirmed). */
    static boolean isActive() {
        return pipelineLive && targetStorm != null;
    }

    /**
     * True while the volumetric pass is live for THIS storm — {@link StormWallRenderer}
     * thins its EXO stack / softens the occluder tint only on a {@code true} here, so
     * Iris-active / veilPostFx-off / evicted / fused sessions keep the frozen look.
     */
    static boolean isVolumeStorm(int stormId) {
        StormFxClient.ClientStorm storm = targetStorm;
        return pipelineLive && storm != null && storm.id == stormId;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        targetStorm = pickStorm(minecraft.gameRenderer.getMainCamera().getPosition());
        // Manager-confirmed (not just predicate-desired): eviction and the failure fuse
        // both read as "volume off" to the renderer, which then keeps its full stack.
        pipelineLive = targetStorm != null && VeilPostController.isActive(STORM_VOLUME_POST);
    }

    /**
     * Nearest eligible sphere storm by shell distance, or {@code null}. Quality tier ≥ 1
     * and no {@code reducedFx} (per-pixel raymarching is motion-bearing by definition).
     */
    @Nullable
    private static StormFxClient.ClientStorm pickStorm(Vec3 camera) {
        if (EclipseClientConfig.reducedFx() || FxBudget.qualityTier() < 1) {
            return null;
        }
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        StormFxClient.ClientStorm best = null;
        double bestShellDist = VOLUME_RANGE;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            if (storm.type != S2CStormStatePayload.TYPE_SPHERE
                    || storm.visibility(1.0F) <= 0.02F) {
                continue;
            }
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            double shellDist = Math.abs(Math.sqrt(dx * dx + dz * dz) - storm.radius);
            if (shellDist < bestShellDist) {
                bestShellDist = shellDist;
                best = storm;
            }
        }
        return best;
    }

    // ------------------------------------------------------------------ per-frame feeder

    /** Uniform feeder (render thread, zero allocations — primitives + shared scratch). */
    private static void feedVolume(PostPipeline pipeline) {
        StormFxClient.ClientStorm storm = targetStorm;
        Minecraft minecraft = Minecraft.getInstance();
        if (storm == null || minecraft.level == null) {
            // One idle frame is possible around activation edges: Strength 0 makes the
            // shader pass the scene through untouched.
            pipeline.getUniform("Strength").setFloat(0.0F);
            return;
        }
        float partialTick = minecraft.getTimer().getGameTimeDeltaPartialTick(false);
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        float vis = storm.visibility(partialTick);
        float yScale = Math.max(0.05F, StormWallRenderer.heightScale(storm, vis));
        // EXPLODE rides W-A's shockwave law: the volume expands with the shell (raw boom
        // = the outermost shell's stagger) and dissolves over the expansion.
        float boom = storm.explodeProgress(partialTick);
        float radius = storm.radius * StormWallRenderer.explodeRadiusScale(boom);

        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        float shellDist = (float) Math.abs(Math.sqrt(dx * dx + dz * dz) - radius);
        float strength = 1.0F - smoothstep(STRENGTH_FADE_START, VOLUME_RANGE, shellDist);
        if (boom > StormWallRenderer.EXPLODE_IMPLODE_FRAC) {
            float expand = (boom - StormWallRenderer.EXPLODE_IMPLODE_FRAC)
                    / (1.0F - StormWallRenderer.EXPLODE_IMPLODE_FRAC);
            strength *= 1.0F - 0.5F * expand; // the mass thins as the shockwave runs out
        }

        pipeline.getUniform("VolCenter").setVector(
                (float) (storm.center.x - camera.x),
                (float) (storm.center.y - camera.y),
                (float) (storm.center.z - camera.z));
        pipeline.getUniform("VolRadius").setFloat(radius);
        pipeline.getUniform("VolYScale").setFloat(yScale);
        pipeline.getUniform("Visibility").setFloat(vis);
        pipeline.getUniform("Strength").setFloat(strength);
        pipeline.getUniform("StepCount").setFloat(stepsForTier(FxBudget.qualityTier()));
        // Tick clock, not wall clock: pause-safe and continuous (the shader integrates
        // rotation angles from it — a wall-clock wrap would snap the churn).
        pipeline.getUniform("Time").setFloat((StormFxClient.ticks() + partialTick) / 20.0F);
        Vector3f sun = SunTracker.sunDirWorld(partialTick); // shared scratch — consume now
        pipeline.getUniform("SunDir").setVector(sun.x(), sun.y(), sun.z());
        pipeline.getUniform("Interior").setFloat(StormInteriorFx.interiorAmount());

        // W-B intra-wall flash → emissive light INSIDE the mass. Anchor mirrors
        // StormWeatherFx.claimLight: horiz = r·0.92·cos(latFrac·π/2), y = latFrac·height.
        float flash = storm.state == S2CStormStatePayload.STATE_ACTIVE
                ? StormWeatherFx.innerFlashAmount(storm.id)
                : 0.0F;
        pipeline.getUniform("FlashAmount").setFloat(flash);
        if (flash > 0.01F) {
            double bearing = StormWeatherFx.innerFlashBearing(storm.id);
            float latFrac = StormWeatherFx.innerFlashLat(storm.id);
            double horiz = storm.radius * FLASH_RADIUS_FRAC
                    * Math.cos(latFrac * (Math.PI / 2.0D));
            pipeline.getUniform("FlashPos").setVector(
                    (float) (storm.center.x + Math.cos(bearing) * horiz - camera.x),
                    (float) (storm.center.y + latFrac * storm.height - camera.y),
                    (float) (storm.center.z + Math.sin(bearing) * horiz - camera.z));
        } else {
            pipeline.getUniform("FlashPos").setVector(
                    (float) (storm.center.x - camera.x),
                    (float) (storm.center.y - camera.y),
                    (float) (storm.center.z - camera.z));
        }
    }

    private static float stepsForTier(int tier) {
        return tier >= 2 ? STEPS_TIER2 : tier == 1 ? STEPS_TIER1 : STEPS_TIER0;
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }

    // ------------------------------------------------------------------ housekeeping

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    /** Respawn/dimension change: the storm list is wiped, so the target must be too. */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        reset();
    }

    private static void reset() {
        targetStorm = null;
        pipelineLive = false;
    }
}
