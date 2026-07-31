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
 * {@code StepCount} (config tier × screen coverage, fullscreen-capped — see
 * {@link #stepCount}), {@code DetailTier} (the effective quality tier 0/1/2 — the
 * shader's gate for tier-priced density terms; tier 0 keeps the baseline look),
 * {@code Time}
 * (tick-clock seconds, pause-safe), {@code SunDir} ({@link SunTracker}), {@code Interior}
 * ({@link StormInteriorFx#interiorAmount()} — the grade hand-over), {@code FlashPos} +
 * {@code FlashAmount} (the W-B intra-wall flash injected as emissive light inside the
 * mass; anchor mirrors {@code StormWeatherFx.claimLight}), {@code Flash2Pos} +
 * {@code Flash2Amount} + {@code FlashSeed} (STORM-MASS B6 — the second, volume-only
 * flash cell and the per-flash vein seed {@code innerFlashSerial() % 64}),
 * {@code SiegeChurn} + {@code ChurnTime} + {@code CoreFade} (STORM-MASS B7 — the
 * F-031/F-032 combat state mirrored into the volume: turbulence, continuous rate
 * escalation, core tear-open).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormVolumeFx {
    public static final ResourceLocation STORM_VOLUME_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_volume");

    /**
     * F-034 LOD handover: the volume pass engages while a sphere storm's shell is inside
     * this distance — beyond it ONLY {@link StormWallRenderer}'s simple far/impostor wall
     * tiers render (the cheap far read). {@link StormNearfieldFx}'s Photon layers share
     * this window, so the volumetric mass and the near-field FX blend in together over
     * the same approach band.
     */
    static final float VOLUME_RANGE = 250.0F;
    /** Strength ramps 1 → 0 over [fade-start, range] — the F-034 handover blend zone. */
    static final float STRENGTH_FADE_START = 150.0F;
    /** Raymarch step budget by quality tier (2/1/0) — the shader's quality ladder. */
    private static final float STEPS_TIER2 = 64.0F;
    private static final float STEPS_TIER1 = 40.0F;
    private static final float STEPS_TIER0 = 24.0F;
    // --- AUDITFIX-4 coverage ladder (see stepCount) ---
    /**
     * Silhouette padding of the raymarch bounds — MUST mirror storm_volume.fsh
     * BOUNDS_MARGIN. STORM-MASS B3 raised it 1.55 → 1.70 for the convection towers
     * (max rEff ≈ 1.478, ×1.05 = 1.552 &lt; 1.70).
     */
    private static final float BOUNDS_MARGIN = 1.70F;
    /** Coverage (sine of the storm's angular radius) at/above which the full budget applies. */
    private static final float COVERAGE_FULL_STEPS = 0.60F;
    /** Coverage at/below which the budget bottoms out at {@link #MIN_STEP_FRACTION}. */
    private static final float COVERAGE_MIN_STEPS = 0.15F;
    /** Distant-storm floor: never fewer than half the tier budget from coverage alone. */
    private static final float MIN_STEP_FRACTION = 0.5F;
    /** Coverage at/above which the near-fullscreen safety cap engages. */
    private static final float COVERAGE_CAP_START = 0.92F;
    /** Hard ceiling once the cap engages: the fullscreen worst case is bounded at 48. */
    private static final float FULLSCREEN_STEP_CAP = 48.0F;
    /** Absolute Java-side floor (the shader clamps to its own floor of 12). */
    private static final float STEPS_MIN = 16.0F;
    /**
     * F-031b: hard step ceiling while the target storm is under siege (the boss fight
     * runs inside it — debris displays + block lifts + the grown radius all cost frame
     * time, so the raymarch gives some back).
     */
    private static final float SIEGE_STEP_CAP = 32.0F;
    /** Flash light anchor sits at this fraction of r on the flash bearing (W-C formula). */
    private static final double FLASH_RADIUS_FRAC = 0.92D;

    /** The one storm the raymarcher covers this tick ({@code null} = pipeline idle). */
    @Nullable
    private static StormFxClient.ClientStorm targetStorm;
    /** Cached per tick: the pipeline is genuinely active in Veil's post manager. */
    private static boolean pipelineLive;
    /**
     * STORM-MASS B7: the integrated churn clock (∫ churn dt, seconds) — the shader adds
     * it to {@code Time} so siege escalation multiplies the rotation/updraft RATES while
     * every angle stays continuous (a raw {@code rate × (1 + k·churn)} would scrub the
     * whole field by {@code Time × Δrate} on each churn change). Accumulated per client
     * tick (pause-safe, same clock as {@code Time}); stops growing the tick churn hits 0.
     */
    private static float churnTime;

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

    /**
     * STORM-MASS B8: the B7 churn clock in seconds — {@code StormPhotonFx} folds it
     * into the {@code eclStormSpin} expression variable exactly like the shader folds
     * {@code ChurnTime} into its spin clock, so the Photon parallax bands keep tracking
     * the volume rotation through a siege escalation instead of visibly falling behind.
     */
    static float churnTimeSeconds() {
        return churnTime;
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
        if (targetStorm != null) {
            churnTime += siegeChurn(targetStorm, 1.0F) * 0.05F; // B7 clock, 1 tick = 50 ms
        }
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
        pipeline.getUniform("StepCount").setFloat(stepCount(storm, camera, radius));
        // F-030f: 3 self-shadow taps on the top tier, 2 below it AND while the storm is
        // under siege (the shader rescales tap spacing so reach/optical depth hold).
        pipeline.getUniform("ShadowTaps").setFloat(
                effectiveTier(storm) >= 2 ? 3.0F : 2.0F);
        // STORM-MASS B9 foundation: the effective tier reaches the shader directly, so
        // tier-priced density terms (B2/B3/B4) gate in-shader instead of abusing the
        // ShadowTaps proxy. Tier 0 (the default floor) keeps every gate closed.
        pipeline.getUniform("DetailTier").setFloat(effectiveTier(storm));
        // STORM-MASS B7: combat state → shader. SiegeChurn (the F-031a growth ramp,
        // normalized against the payload's radius scale) drives warp turbulence;
        // ChurnTime (integrated, see field) escalates rotation/updraft continuously;
        // CoreFade mirrors the F-032 occluder dissolve so the volume opens the arena
        // in sync with the geometry.
        pipeline.getUniform("SiegeChurn").setFloat(siegeChurn(storm, partialTick));
        pipeline.getUniform("ChurnTime").setFloat(churnTime);
        pipeline.getUniform("CoreFade").setFloat(storm.siegeCoreFade(partialTick));
        // Tick clock, not wall clock: pause-safe and continuous (the shader integrates
        // rotation angles from it — a wall-clock wrap would snap the churn).
        pipeline.getUniform("Time").setFloat((StormFxClient.ticks() + partialTick) / 20.0F);
        Vector3f sun = SunTracker.sunDirWorld(partialTick); // shared scratch — consume now
        pipeline.getUniform("SunDir").setVector(sun.x(), sun.y(), sun.z());
        pipeline.getUniform("Interior").setFloat(StormInteriorFx.interiorAmount());

        // POLISH4 dev-only flash HOLD (/eclipsefx storm flashhold): forces BOTH B6 cells
        // to a fixed envelope with a slowly cycling vein seed so the 0.35 s double flash
        // becomes inspectable on seconds-per-frame rigs. Every hold branch below is
        // gated on this flag — OFF (the default) leaves each fed expression exactly as
        // shipped, so idle frames stay bit-identical (StormFlashDevHold idle rule).
        boolean hold = StormFlashDevHold.active();

        // W-B intra-wall flash → emissive light INSIDE the mass. Anchor mirrors
        // StormWeatherFx.claimLight: horiz = r·0.92·cos(latFrac·π/2), y = latFrac·height.
        float flash = storm.state == S2CStormStatePayload.STATE_ACTIVE
                ? StormWeatherFx.innerFlashAmount(storm.id)
                : 0.0F;
        if (hold) {
            flash = StormFlashDevHold.amount();
        }
        pipeline.getUniform("FlashAmount").setFloat(flash);
        if (flash > 0.01F) {
            double bearing = StormWeatherFx.innerFlashBearing(storm.id);
            float latFrac = StormWeatherFx.innerFlashLat(storm.id);
            if (hold && latFrac <= 0.0F) {
                // Slot never picked a cell (real picks have lat ≥ FLASH_LAT_MIN = 0.15):
                // distinct fallback so two separate held cells read immediately.
                bearing = Math.atan2(dz, dx) - StormFlashDevHold.FALLBACK_SPREAD;
                latFrac = StormFlashDevHold.FALLBACK_LAT1;
            }
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

        // STORM-MASS B6 flash v2: the SECOND independent cell (volume-only — no light,
        // no serial, no Photon vein; see StormWeatherFx) plus the shared vein seed.
        // The seed is fed unconditionally: it only modulates INSIDE the Amount gates,
        // so an idle frame stays bit-identical whatever value it holds.
        pipeline.getUniform("FlashSeed").setFloat(hold
                ? StormFlashDevHold.seed()
                : StormWeatherFx.innerFlashSerial() % 64);
        float flash2 = storm.state == S2CStormStatePayload.STATE_ACTIVE
                ? StormWeatherFx.innerFlash2Amount(storm.id)
                : 0.0F;
        if (hold) {
            flash2 = StormFlashDevHold.amount();
        }
        pipeline.getUniform("Flash2Amount").setFloat(flash2);
        if (flash2 > 0.01F) {
            double bearing2 = StormWeatherFx.innerFlash2Bearing(storm.id);
            float latFrac2 = StormWeatherFx.innerFlash2Lat(storm.id);
            if (hold && latFrac2 <= 0.0F) {
                bearing2 = Math.atan2(dz, dx) + StormFlashDevHold.FALLBACK_SPREAD;
                latFrac2 = StormFlashDevHold.FALLBACK_LAT2;
            }
            double horiz2 = storm.radius * FLASH_RADIUS_FRAC
                    * Math.cos(latFrac2 * (Math.PI / 2.0D));
            pipeline.getUniform("Flash2Pos").setVector(
                    (float) (storm.center.x + Math.cos(bearing2) * horiz2 - camera.x),
                    (float) (storm.center.y + latFrac2 * storm.height - camera.y),
                    (float) (storm.center.z + Math.sin(bearing2) * horiz2 - camera.z));
        } else {
            pipeline.getUniform("Flash2Pos").setVector(
                    (float) (storm.center.x - camera.x),
                    (float) (storm.center.y - camera.y),
                    (float) (storm.center.z - camera.z));
        }
    }

    /**
     * AUDITFIX-4 — the REAL quality ladder (the pre-audit code fed
     * {@code stepsForTier(FxBudget.qualityTier())}, and {@code qualityTier()} is by
     * construction always 2 whenever the pass is active — {@link #pickStorm} bails under
     * {@code reducedFx} — so the advertised 64/40/24 ladder never engaged and every frame
     * marched 64 steps). The budget now varies on two real axes:
     * <ul>
     *   <li><b>Config tier</b>: {@code stormVolumeQuality} (2/1/0 → 64/40/24 base steps,
     *       default 2) — the user knob {@code reducedFx} is too blunt for.</li>
     *   <li><b>Screen coverage</b>: {@code coverage = clamp(paddedRadius / centerDist, 0, 1)}
     *       is the sine of the storm's angular radius (1 with the camera inside the bounds).
     *       A distant storm covers few pixels AND needs less depth resolution per pixel, so
     *       the budget ramps linearly from 1.0× at coverage ≥ {@value #COVERAGE_FULL_STEPS}
     *       down to {@value #MIN_STEP_FRACTION}× at coverage ≤ {@value #COVERAGE_MIN_STEPS}
     *       (tier 2: 64 → 32 steps; the shader additionally shortens far ray segments and
     *       clamps to its own floor of 12).</li>
     * </ul>
     * Hard safety: at coverage ≥ {@value #COVERAGE_CAP_START} (camera right outside/inside
     * the wall — every pixel marches the dense band at full framebuffer resolution) the
     * budget is capped at {@value #FULLSCREEN_STEP_CAP} steps, so the worst case is bounded
     * at 48 steps × 3 shadow taps instead of the old unconditional 64 × 4.
     */
    private static float stepCount(StormFxClient.ClientStorm storm, Vec3 camera, float radius) {
        float steps = stepsForTier(effectiveTier(storm));
        double dx = camera.x - storm.center.x;
        double dy = camera.y - storm.center.y;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dy * dy + dz * dz);
        float padded = radius * BOUNDS_MARGIN;
        float coverage = centerDist <= padded ? 1.0F : (float) (padded / centerDist);
        steps *= Mth.clamp(MIN_STEP_FRACTION + (1.0F - MIN_STEP_FRACTION)
                        * (coverage - COVERAGE_MIN_STEPS) / (COVERAGE_FULL_STEPS - COVERAGE_MIN_STEPS),
                MIN_STEP_FRACTION, 1.0F);
        if (coverage >= COVERAGE_CAP_START) {
            steps = Math.min(steps, FULLSCREEN_STEP_CAP);
        }
        if (StormFxClient.siegeActive(storm.id)) {
            steps = Math.min(steps, SIEGE_STEP_CAP); // F-031b combat FPS guard
        }
        return Math.max(steps, STEPS_MIN);
    }

    /**
     * STORM-MASS B7: siege churn 0..1 — the F-031a growth ramp position, normalized
     * against the payload's own radius scale (default 1.3, {@code StormSiege.RADIUS_SCALE}
     * is server-private). 0 for storms that never saw a siege ({@code siegeScale} rests
     * at 1); ramps back to 0 over the same clock when the siege ends.
     */
    private static float siegeChurn(StormFxClient.ClientStorm storm, float partialTick) {
        float denom = Math.max(storm.siegeRadiusScale - 1.0F, 0.05F);
        return Mth.clamp((storm.siegeScale(partialTick) - 1.0F) / denom, 0.0F, 1.0F);
    }

    /**
     * F-031b: the config quality tier, dropped ONE tier while this storm is under siege
     * (the client's automatic combat downgrade — restored the tick the siege ends).
     */
    private static int effectiveTier(StormFxClient.ClientStorm storm) {
        int tier = EclipseClientConfig.stormVolumeQuality();
        return StormFxClient.siegeActive(storm.id) ? Math.max(0, tier - 1) : tier;
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
        churnTime = 0.0F; // B7: the clock is a Time offset — zeroing while idle is invisible
    }
}
