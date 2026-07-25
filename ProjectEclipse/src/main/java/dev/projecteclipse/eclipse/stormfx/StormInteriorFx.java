package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayDeque;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
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
import net.minecraft.sounds.SoundSource;
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
 * post grade (uniforms {@code Interior, RainAmount, Time} — frozen §3.3 — plus the C8
 * {@code Sphere} variant flag, EVAL-POL-F #4) fed through
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
 *
 * <p><b>C8 sphere-interior variant</b> (site storms; keyed off the storm type): a clearly
 * different treatment from the intro vortex — a lightning-less <i>green-violet</i> fog grade
 * instead of the rain-slate, NO rain sheets (drifting ash/spore motes and ground-fog ribbons
 * instead), self-scheduled silent silhouette flickers, a relative interior drone loop plus
 * heartbeat-adjacent sub-bass pulses (both gated behind
 * {@link EclipseClientConfig#heartbeatSound()} where pulse-like), and the exterior roar
 * muffled via the loop sound's pitch alias (see {@code StormFxClient.StormLoopSound}). The
 * interior scalar feeds {@code MusicManager}'s {@code fog_storm} cue exactly like before —
 * sphere interiors arm the same 0.55/0.15 hysteresis. {@link #explodeWhiteout} is the C8
 * tyrant-death beat: a ~15-tick white-out riding the fog color while the shockwave shell
 * expands, after which the sky clears with the released interior.</p>
 *
 * <p><b>FX-STORM round:</b> a roar-loop-bar gust clock ({@link #gustAmount} — rain cadence
 * and bearing, the grade's {@code RainAmount}, the roar volume swell and the wisp updraft
 * all ride it), rotating rain sheets (advancing spawn bearing), god-fingers of light
 * through the dome eye (≤ 2 managed {@code storm_godfinger} loops, tier-laddered),
 * ash-devil mini-whirls near the ground, the post-white-out clear-sky bloom tail, and the
 * {@code WallProx} uniform (heat-shimmer refraction near the wall inside) plus
 * {@link #flashAmount}/{@link #flashSerial} for the renderer's Tyrant silhouette.</p>
 *
 * <p><b>STORM2 round (PLAN-STORM2 §W-D):</b> four additive uniforms — {@code EyeDim}
 * (0..1 "under the apex eye", also deepens the drone pitch and gates the god-fingers),
 * {@code BandFlow} (signed −1..1 stratum wind flow at camera height off W-A's §A3 speed
 * table — the grade's rain shears sideways with it), {@code InnerFlash} (W-B's intra-wall
 * flash-scheduler max envelope pulsing the interior grade) and {@code WallBand}
 * (IDEAS-STORM-2 #5: symmetric crossing scalar peaking mid-wall-band so pushing THROUGH
 * the wall reads as meters of mass — the pipeline predicate widens to fire on it even
 * with zero interior). Interior weather couples to the mass: rain-sheet bearings bias
 * toward the wall above 0.4 {@code WallProx}, motes stream tangentially at stratum flow,
 * and mote/ribbon cadence quickens near the eyewall / calms under the eye. The explosion
 * gains a 6-tick pre-release fog "gulp" (24→14→24 inhale during the implosion charge);
 * {@code BandFlow}/{@code InnerFlash} are motion-bearing and feed 0 under reducedFx
 * (the {@code WallProx} rule); {@code EyeDim}/{@code WallBand} are static grades.</p>
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

    // --- C8 sphere-interior variant (site storms: green-violet, lightning-less) ---
    /** Sphere interior fog (deep fog-green with a violet under-hue — NOT the vortex slate). */
    private static final float SPH_FOG_R = 0.045F;
    private static final float SPH_FOG_G = 0.082F;
    private static final float SPH_FOG_B = 0.064F;
    /** Sphere silhouette-flicker blow color (pale sick green instead of violet-white). */
    private static final float SPH_FLASH_R = 0.50F;
    private static final float SPH_FLASH_G = 0.68F;
    private static final float SPH_FLASH_B = 0.54F;
    /** Sphere ambience engages above this interior amount (and releases with it). */
    private static final float SPHERE_AMBIENCE_GATE = 0.30F;
    /** Drifting ash/spore mote cadence (doubled under reducedFx). */
    private static final int MOTE_INTERVAL_TICKS = 2;
    /** Ground-fog ribbon cadence (low crawling smoke around the player's feet). */
    private static final int RIBBON_INTERVAL_TICKS = 5;
    /** Heartbeat-adjacent sub-bass pulse window (ticks) — gated by heartbeatSound(). */
    private static final int PULSE_MIN_TICKS = 55;
    private static final int PULSE_MAX_TICKS = 80;
    /** Silent silhouette-flicker window (ticks) — the lightning-less scare rhythm. */
    private static final int FLICKER_MIN_TICKS = 240;
    private static final int FLICKER_MAX_TICKS = 440;
    /** C8 explosion white-out length (ticks). */
    private static final int WHITEOUT_TICKS = 15;

    // --- FX-STORM round: gust clock / god-fingers / ash devils / bloom / wall shimmer ---
    /** Gust clock period (ticks) — one bar of the 8 s {@code event.storm_loop} roar loop. */
    private static final int GUST_PERIOD_TICKS = 160;
    /** Gust envelope length inside each period (smoothstep up over 40%, down over 60%). */
    private static final int GUST_LENGTH_TICKS = 30;
    /** RainAmount lift at gust peak (vortex interiors — the grade's streaks burst). */
    private static final float GUST_RAIN_BOOST = 0.35F;
    /** Rain sheet spawn bearing advance per tick — the sheets orbit the camera. */
    private static final float RAIN_ROTATE_RAD_PER_TICK = 0.02F;

    /** God-fingers of light through the dome "eye" (sphere interiors only). */
    private static final ResourceLocation GODFINGER_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_godfinger");
    private static final int MAX_GODFINGERS = 2;
    /** Fingers engage above this interior amount within this distance of the eye. */
    private static final float GODFINGER_ENGAGE = 0.5F;
    private static final double GODFINGER_MAX_CENTER_DIST = 48.0D;
    /** Fingers drift slowly around the eye (opposite directions per finger). */
    private static final float GODFINGER_DRIFT_RAD_PER_TICK = 0.003F;

    /** Ash-devil mini-whirls near the ground (sphere interiors; reducedFx keeps one). */
    private static final int ASH_DEVILS_FULL = 2;
    private static final int ASH_DEVIL_RESEED_TICKS = 180;
    private static final double ASH_DEVIL_MIN_DIST = 8.0D;
    private static final double ASH_DEVIL_MAX_DIST = 16.0D;

    /** Clear-sky bloom tail after the explosion white-out releases (ticks). */
    private static final int BLOOM_TICKS = 40;
    /** How far inside the shell the heat-shimmer band reaches (blocks; 1 at the occluder). */
    private static final float SHIMMER_BAND = 8.0F;

    // --- STORM2 round (PLAN-STORM2 §W-D): eye light / band flow / wall band / gulp ---
    /** D1: EyeDim engages under horizontal centerDist &lt; 0.35·r (sphere interiors only). */
    private static final double EYE_RADIUS_FRAC = 0.35D;
    /** W-A's frozen §A3 stratum-speed table (base/mid/upper/polar) sampled at camera height. */
    private static final float[] STRATUM_FLOW = {0.6F, 1.0F, 1.5F, -0.8F};
    /** BandFlow normalizer (|max| of the stratum table) — the uniform stays in −1..1. */
    private static final float STRATUM_FLOW_MAX = 1.5F;
    /** D3: god-fingers additionally require this much EyeDim — fingers are the EYE's light. */
    private static final float GODFINGER_EYE_GATE = 0.3F;
    /** D3: rain-sheet spawn bearings bias toward the nearest wall above this WallProx. */
    private static final float RAIN_WALL_BIAS_GATE = 0.4F;
    /** IDEAS-STORM-2 #5: half-width (blocks) of the symmetric WallBand crossing scalar. */
    private static final double WALL_BAND_HALF_WIDTH = 6.0D;
    /** D5 pre-release "gulp": the fog far plane pinches 24→this and back over GULP_TICKS. */
    private static final float GULP_FOG_FAR = 14.0F;
    private static final int GULP_TICKS = 6;

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

    // --- C8 sphere-interior state ---
    /** True while the dominant interior storm is a TYPE_SPHERE (drives the variant). */
    private static boolean interiorSphere;
    /** Relative interior drone loop (LimboAmbience pattern; volume rides the interior). */
    @Nullable
    private static SphereDroneSound droneSound;
    private static int moteCountdown;
    private static int ribbonCountdown;
    private static int pulseCountdown;
    private static int flickerCountdown;
    /** Slowly-rotating bearing the ground-fog ribbons crawl along. */
    private static float ribbonAngle;
    /** C8 explosion white-out (ticks left + peak strength 0..1 at detonation). */
    private static int whiteoutTicks;
    private static float whiteoutStrength;

    // --- FX-STORM round state ---
    /** Gust envelope 0..1 (roar-loop-bar clock × interior amount). */
    private static float gustAmount;
    /** Advancing spawn bearing of the rotating rain sheets. */
    private static float rainAngle;
    /** Serial incremented per flicker so per-flicker hashes (silhouette bearing) hold. */
    private static int flashSerial;
    /** Smoothed wall proximity 0..1 (1 near the occluder band inside) → `WallProx` uniform. */
    private static float smoothedWallProx;
    /** Raw wall-proximity target of the winning interior storm (set by interiorTargetAt). */
    private static float wallProxTarget;
    /** God-finger loop emitters + their drift bearings (sphere interiors). */
    private static final ParticleEmitter[] GODFINGERS = new ParticleEmitter[MAX_GODFINGERS];
    private static final float[] GODFINGER_ANGLES = new float[MAX_GODFINGERS];
    /** Ash-devil whirl anchors (positions re-seeded around the camera). */
    private static final double[] DEVIL_X = new double[ASH_DEVILS_FULL];
    private static final double[] DEVIL_Z = new double[ASH_DEVILS_FULL];
    private static final float[] DEVIL_PHASE = new float[ASH_DEVILS_FULL];
    private static int devilReseedCountdown;
    /** Clear-sky bloom tail (ticks left + strength captured from the dying white-out). */
    private static int bloomTicks;
    private static float bloomStrength;

    // --- STORM2 round (W-D) state ---
    /** Smoothed "under the eye" factor 0..1 → {@code EyeDim} (also drone pitch + finger gate). */
    private static float smoothedEyeDim;
    private static float eyeDimTarget;
    /** Smoothed signed stratum flow at camera height −1..1 → {@code BandFlow}. */
    private static float smoothedBandFlow;
    private static float bandFlowTarget;
    /** Smoothed symmetric wall-crossing scalar 0..1 → {@code WallBand} (IDEAS-STORM-2 #5). */
    private static float smoothedWallBand;
    private static float wallBandTarget;
    /** D5: remaining pre-release gulp ticks (armed by {@link #explodeWhiteout}, pause-safe). */
    private static int gulpTicks;

    static {
        // Feature-owned registration replaces nothing (new id) — GRADE priority per §3.3.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                STORM_INTERIOR_POST,
                VeilPostController.PipelinePriority.GRADE,
                // STORM2 (IDEAS-STORM-2 #5): the wall-band crossing grades BOTH sides of
                // the wall — the row must also fire with zero interior mid-crossing.
                () -> EclipseFxState.stormInterior() > 0.01F || smoothedWallBand > 0.01F,
                pipeline -> {
                    pipeline.getUniform("Interior").setFloat(EclipseFxState.stormInterior());
                    pipeline.getUniform("RainAmount").setFloat(EclipseFxState.stormRain());
                    pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 100_000L) / 1000.0F);
                    // EVAL-POL-F #4: sphere interiors grade green-violet (C8 identity)
                    // instead of the vortex blue-slate.
                    pipeline.getUniform("Sphere").setFloat(interiorSphere ? 1.0F : 0.0F);
                    // FX-STORM: heat-shimmer refraction strength — wall proximity inside.
                    // Fed 0 under reduced FX: a fullscreen animated refraction must degrade
                    // with the rest of the storm layers (reduced-motion contract).
                    boolean reduced = EclipseClientConfig.reducedFx();
                    pipeline.getUniform("WallProx").setFloat(reduced ? 0.0F : smoothedWallProx);
                    // STORM2 (W-D D1): EyeDim/WallBand are static light/mass grades and
                    // survive reducedFx; BandFlow/InnerFlash are motion-bearing and feed 0
                    // there (the WallProx rule). InnerFlash is W-B's flash-scheduler max
                    // envelope — already smoothstep-shaped, fed raw by contract (§3).
                    pipeline.getUniform("EyeDim").setFloat(smoothedEyeDim);
                    pipeline.getUniform("WallBand").setFloat(smoothedWallBand);
                    pipeline.getUniform("BandFlow").setFloat(reduced ? 0.0F : smoothedBandFlow);
                    pipeline.getUniform("InnerFlash").setFloat(
                            reduced ? 0.0F : StormWeatherFx.innerFlashMax());
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

    /** Gust envelope 0..1 (FX-STORM roar-loop-bar clock) — read by StormFxClient audio/wisps. */
    static float gustAmount() {
        return gustAmount;
    }

    /** Flash lift 0..1 of the live silhouette flicker (renderer Tyrant-silhouette read). */
    static float flashAmount() {
        return Mth.clamp(flashTicks / (float) FLASH_MAX_TICKS, 0.0F, 1.0F);
    }

    /** Serial of the current flicker — stable per flicker, new bearing per flicker. */
    static int flashSerial() {
        return flashSerial;
    }

    /**
     * Silhouette-reveal flash (IDEA-15 §2): lifts the interior fog far plane 24→56 and blows
     * the slate toward violet-white for {@code ticks} ticks. Callers gate on
     * {@link #interiorAmount()} &gt; 0.5 (interior arcs/bolts only).
     */
    static void flash(int ticks) {
        if (flashTicks == 0) {
            flashSerial++; // a fresh flicker re-rolls the per-flicker hashes (FX-STORM)
        }
        flashTicks = Math.max(flashTicks, Math.min(ticks, FLASH_MAX_TICKS));
    }

    /**
     * C8 tyrant-death white-out: {@code strength} 1 inside the shell feathering to 0 well
     * outside ({@code StormFxClient.handle} computes it on the EXPLODE transition). Rides
     * the fog color toward white for {@value #WHITEOUT_TICKS} ticks — inside the pinched
     * interior fog that IS the whole view — then releases with the dying interior: the sky
     * clears in seconds.
     */
    static void explodeWhiteout(float strength) {
        if (strength <= 0.05F) {
            return;
        }
        whiteoutTicks = Math.max(whiteoutTicks, WHITEOUT_TICKS);
        whiteoutStrength = Math.max(whiteoutStrength, Mth.clamp(strength, 0.0F, 1.0F));
        // STORM2 (W-D D5): arm the pre-release "gulp" — over the next GULP_TICKS (the
        // implosion charge, before the shell's white peak at the pinch release) the fog
        // far plane pinches 24→14 and back: the storm inhales before it dies.
        gulpTicks = Math.max(gulpTicks, GULP_TICKS);
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
            smoothedWallProx = wallProxTarget;
            smoothedEyeDim = eyeDimTarget;
            smoothedBandFlow = bandFlowTarget;
            smoothedWallBand = wallBandTarget;
        } else {
            smoothedInterior += (target - smoothedInterior) * SMOOTHING;
            smoothedApproach += (approachTarget - smoothedApproach) * SMOOTHING;
            smoothedWallProx += (wallProxTarget - smoothedWallProx) * SMOOTHING;
            smoothedEyeDim += (eyeDimTarget - smoothedEyeDim) * SMOOTHING;
            smoothedBandFlow += (bandFlowTarget - smoothedBandFlow) * SMOOTHING;
            smoothedWallBand += (wallBandTarget - smoothedWallBand) * SMOOTHING;
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
        if (smoothedWallBand < 0.002F) {
            smoothedWallBand = 0.0F; // the pipeline predicate reads it — clean release
        }
        if (gulpTicks > 0) {
            gulpTicks--; // D5: pause-safe like flashTicks
        }
        if (whiteoutTicks > 0 && --whiteoutTicks == 0) {
            // C8: the white-out released — the clear-sky bloom moment rides out on its
            // strength (FX-STORM stage 4) before the sky fully opens.
            bloomTicks = BLOOM_TICKS;
            bloomStrength = whiteoutStrength;
            whiteoutStrength = 0.0F;
        }
        if (bloomTicks > 0) {
            bloomTicks--;
        }
        tickGust();
        // Rain rides the interior amount (R14) — but NOT in sphere interiors (C8: motes
        // and ground ribbons own that space; the grade's rain uniform stays 0 there).
        // FX-STORM: gusts burst the grade's streak layer on top of the base amount.
        EclipseFxState.setStormInterior(smoothedInterior, interiorSphere ? 0.0F
                : Math.min(1.0F, smoothedInterior * (1.0F + GUST_RAIN_BOOST * gustAmount)));
        tickRainSheets(level, camera);
        tickSphereAmbience(minecraft, level, camera);
        tickGodFingers(camera);
        tickCampGlow(level, camera);
    }

    /**
     * Raw interior target: max over all storms of horizontal × vertical × ramp coverage.
     * Also latches {@link #interiorSphere} to the winning storm's type (C8 variant key),
     * and (STORM2 W-D) refreshes the {@code EyeDim}/{@code BandFlow} targets off the
     * winning storm plus the max-over-storms {@code WallBand} crossing scalar
     * (IDEAS-STORM-2 #5 — computed for OUTSIDE cameras too, unlike everything else here).
     */
    private static float interiorTargetAt(Vec3 camera) {
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        float best = 0.0F;
        wallProxTarget = 0.0F;
        eyeDimTarget = 0.0F;
        bandFlowTarget = 0.0F;
        wallBandTarget = 0.0F;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            double dist = Math.sqrt(dx * dx + dz * dz);
            // IDEA-15 §6 (EVAL-4 obs #1): vortex shells lean inward 8°, so "inside" must be
            // judged against the TILTED radius at camera height (mirror of emitShell's
            // topRadius math) — never the base radius, which over-reaches for high cameras.
            // C8: sphere domes shrink with the chord at camera height, same principle.
            double effectiveRadius = storm.radius;
            if (storm.type == S2CStormStatePayload.TYPE_VORTEX) {
                double above = Math.max(0.0D, camera.y - storm.center.y);
                effectiveRadius = Math.max(storm.radius * 0.25D,
                        storm.radius - above * StormWallRenderer.TAN_TILT);
            } else if (storm.type == S2CStormStatePayload.TYPE_SPHERE) {
                double above = Math.max(0.0D, camera.y - storm.center.y);
                double chordSq = (double) storm.radius * storm.radius - above * above;
                if (chordSq <= 0.0D) {
                    continue; // above the dome apex
                }
                effectiveRadius = Math.sqrt(chordSq);
            }
            float top = (float) Mth.clamp((storm.center.y + storm.height + 8.0D - camera.y) / 8.0D, 0.0D, 1.0D);
            float bottom = (float) Mth.clamp((camera.y - (storm.center.y - 14.0D)) / 8.0D, 0.0D, 1.0D);
            float visibility = storm.visibility(1.0F);
            // STORM2 (IDEAS-STORM-2 #5): symmetric wall-band scalar — peaks mid-band at
            // r − OCCLUDER_INSET/2 and reads on BOTH sides of the crossing, so it must be
            // taken before the interior early-out. Skipped while EXPLODE runs (the wall is
            // detonating outward off its base radius — the whiteout owns that beat).
            if (storm.state != S2CStormStatePayload.STATE_EXPLODE) {
                double bandMid = effectiveRadius - StormWallRenderer.OCCLUDER_INSET * 0.5D;
                float band = 1.0F - (float) Mth.clamp(
                        Math.abs(dist - bandMid) / WALL_BAND_HALF_WIDTH, 0.0D, 1.0D);
                band *= top * bottom * visibility;
                if (band > wallBandTarget) {
                    wallBandTarget = band;
                }
            }
            float horiz = (float) Mth.clamp(
                    ((effectiveRadius - StormWallRenderer.OCCLUDER_INSET) - dist) / INTERIOR_FEATHER,
                    0.0D, 1.0D);
            if (horiz <= 0.0F) {
                continue;
            }
            float amount = horiz * top * bottom * visibility;
            if (amount > best) {
                best = amount;
                interiorSphere = storm.type == S2CStormStatePayload.TYPE_SPHERE;
                // FX-STORM heat shimmer: wall proximity — 1 right at the fully-interior
                // line, fading to 0 SHIMMER_BAND blocks further inside.
                double inset = (effectiveRadius - StormWallRenderer.OCCLUDER_INSET) - dist;
                wallProxTarget = amount
                        * (1.0F - (float) Mth.clamp(inset / SHIMMER_BAND, 0.0D, 1.0D));
                // STORM2 (W-D D1): "under the eye" factor — smoothstep from the 0.35·r
                // eye footprint down to ~0.12·r, sphere interiors only (the eye is a
                // dome-apex feature; vortex interiors keep EyeDim 0).
                if (interiorSphere) {
                    float eye = (float) Mth.clamp(
                            1.0D - dist / (storm.radius * EYE_RADIUS_FRAC), 0.0D, 1.0D);
                    eyeDimTarget = amount * eye * eye * (3.0F - 2.0F * eye);
                }
                // STORM2 (W-D D1): signed stratum wind flow at the camera's height inside
                // the mass (W-A §A3 table, normalized −1..1); the grade shears rain with it.
                float heightFrac = (float) Mth.clamp(
                        (camera.y - storm.center.y) / storm.height, 0.0D, 1.0D);
                bandFlowTarget = amount * stratumFlow(heightFrac) / STRATUM_FLOW_MAX;
            }
        }
        return best;
    }

    /**
     * Signed wind-band flow at a normalized height 0..1 — W-A's frozen 4-stratum speed
     * table (heavy slow base 0.6×, mid 1.0×, fast upper 1.5×, counter-rotating polar
     * −0.8×) piecewise-lerped between band CENTERS with a smoothstep fade, so
     * {@code BandFlow} never pops when the camera crosses a stratum boundary.
     */
    private static float stratumFlow(float heightFrac) {
        float x = Mth.clamp(heightFrac, 0.0F, 1.0F) * STRATUM_FLOW.length - 0.5F;
        int s = Mth.clamp((int) Math.floor(x), 0, STRATUM_FLOW.length - 2);
        float f = Mth.clamp(x - s, 0.0F, 1.0F);
        f = f * f * (3.0F - 2.0F * f);
        return Mth.lerp(f, STRATUM_FLOW[s], STRATUM_FLOW[s + 1]);
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
        if (smoothedInterior < 0.25F || interiorSphere) {
            if (smoothedInterior < 0.05F || interiorSphere) {
                clearRain(); // C8: sphere interiors are rain-less — motes/ribbons instead
            }
            return;
        }
        pruneRain();
        // FX-STORM: the sheets orbit the camera on an advancing bearing (faster in gusts).
        rainAngle += RAIN_ROTATE_RAD_PER_TICK * (1.0F + 1.5F * gustAmount);
        if (--rainCountdown > 0) {
            return;
        }
        int interval = EclipseClientConfig.reducedFx() ? RAIN_INTERVAL_TICKS * 2 : RAIN_INTERVAL_TICKS;
        // Gust burst: the cadence halves while the gust envelope is high (roar-loop timed).
        rainCountdown = gustAmount > 0.5F ? Math.max(4, interval / 2) : interval;
        RandomSource random = level.random;
        double angle = rainAngle + (random.nextDouble() - 0.5D) * 1.2D;
        // STORM2 (W-D D3): near the wall inside, the sheet bearings lean toward it (up to
        // 70 % of the angular gap at full WallProx) — so W-B's between-shell rain curtains
        // continue seamlessly into the interior sheets across the wall band.
        if (smoothedWallProx > RAIN_WALL_BIAS_GATE) {
            StormFxClient.ClientStorm storm = nearestStorm(camera);
            if (storm != null) {
                double wallBearing = Math.atan2(camera.z - storm.center.z, camera.x - storm.center.x);
                double bias = (smoothedWallProx - RAIN_WALL_BIAS_GATE)
                        / (1.0D - RAIN_WALL_BIAS_GATE) * 0.7D;
                // Shortest signed angular gap (wrap-safe) eased toward the wall bearing.
                angle += Math.atan2(Math.sin(wallBearing - angle), Math.cos(wallBearing - angle)) * bias;
            }
        }
        double dist = 2.0D + random.nextDouble() * (RAIN_SPAWN_RADIUS - 2.0D);
        Vec3 pos = new Vec3(
                camera.x + Math.cos(angle) * dist,
                camera.y + RAIN_SPAWN_HEIGHT + random.nextDouble() * 3.0D,
                camera.z + Math.sin(angle) * dist);
        ParticleEmitter emitter = QuasarSpawner.spawnManaged(RAIN_SHEET_EMITTER, pos, FxBudget.Channel.STORM);
        if (emitter == null) {
            return; // budget refusal / Quasar unavailable — retry next interval
        }
        RAIN_SHEETS.addLast(emitter);
        while (RAIN_SHEETS.size() > MAX_RAIN_EMITTERS) {
            removeEmitter(RAIN_SHEETS.pollFirst());
        }
    }

    // ------------------------------------------------------------------ FX-STORM gust clock

    /**
     * Wind-gust clock (FX-STORM): one gust per {@value #GUST_PERIOD_TICKS}-tick period —
     * one bar of the roar loop — with a {@value #GUST_LENGTH_TICKS}-tick smoothstep
     * envelope (fast attack, slower release). Scaled by the interior amount so gusts only
     * exist inside; consumers: rain cadence + spawn bearing, the grade's RainAmount, the
     * roar-loop volume swell and the vortex wisp updraft (all read {@link #gustAmount()}).
     */
    private static void tickGust() {
        int phase = StormFxClient.ticks() % GUST_PERIOD_TICKS;
        float env = 0.0F;
        if (phase < GUST_LENGTH_TICKS) {
            float t = phase / (float) GUST_LENGTH_TICKS;
            float x = t < 0.4F ? t / 0.4F : 1.0F - (t - 0.4F) / 0.6F;
            env = x * x * (3.0F - 2.0F * x);
        }
        gustAmount = env * smoothedInterior;
    }

    // ------------------------------------------------------------------ FX-STORM god-fingers

    /**
     * God-fingers of light through the dome "eye" (FX-STORM, sphere interiors): up to
     * {@value #MAX_GODFINGERS} managed {@code storm_godfinger} loop emitters drifting
     * slowly around the storm center at ~0.35r offset — pale sick-green shafts falling
     * from the apex. Quality ladder: tier 2 = 2 fingers, tier 1 = 1, tier 0 = none; the
     * emitters release the moment the interior (or the storm) goes away.
     */
    private static void tickGodFingers(Vec3 camera) {
        StormFxClient.ClientStorm storm = nearestStorm(camera);
        // STORM2 (W-D D3): fingers additionally require EyeDim — they are the apex EYE's
        // light falling through, not random shafts anywhere under the dome.
        boolean wanted = interiorSphere && smoothedInterior > GODFINGER_ENGAGE && storm != null
                && storm.type == S2CStormStatePayload.TYPE_SPHERE
                && smoothedEyeDim > GODFINGER_EYE_GATE
                && FxBudget.qualityTier() >= 1;
        if (wanted) {
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            wanted = dx * dx + dz * dz < GODFINGER_MAX_CENTER_DIST * GODFINGER_MAX_CENTER_DIST;
        }
        int cap = !wanted ? 0 : FxBudget.qualityTier() >= 2 ? MAX_GODFINGERS : 1;
        for (int k = 0; k < MAX_GODFINGERS; k++) {
            ParticleEmitter finger = GODFINGERS[k];
            if (k >= cap) {
                if (finger != null) {
                    removeEmitter(finger);
                    GODFINGERS[k] = null;
                }
                continue;
            }
            GODFINGER_ANGLES[k] += GODFINGER_DRIFT_RAD_PER_TICK * (k == 0 ? 1.0F : -0.8F);
            double a = GODFINGER_ANGLES[k] + k * Math.PI;
            double r = storm.radius * 0.35D;
            double x = storm.center.x + Math.cos(a) * r;
            double y = storm.center.y + storm.radius * 0.45D;
            double z = storm.center.z + Math.sin(a) * r;
            if (finger == null || finger.isRemoved()) {
                // Budget-refused spawns retry next tick (same rule as the vortex wisps).
                GODFINGERS[k] = QuasarSpawner.spawnManaged(GODFINGER_EMITTER,
                        new Vec3(x, y, z), FxBudget.Channel.STORM);
            } else {
                finger.setPosition(x, y, z);
            }
        }
    }

    private static void clearGodFingers() {
        for (int k = 0; k < MAX_GODFINGERS; k++) {
            if (GODFINGERS[k] != null) {
                removeEmitter(GODFINGERS[k]);
                GODFINGERS[k] = null;
            }
        }
    }

    // ------------------------------------------------------------------ C8 sphere ambience

    /**
     * The sphere-interior sensory kit (engages above {@value #SPHERE_AMBIENCE_GATE} interior,
     * all cadences halved-rate under reducedFx): drifting ash/spore motes, ground-fog ribbons
     * crawling along a slowly rotating bearing at the player's feet, occasional SILENT
     * silhouette flickers (the lightning-less scare — same fog-lift as an arc flash, sphere
     * palette, only a quiet hiss sting), a relative interior drone loop, and
     * heartbeat-adjacent sub-bass pulses that respect
     * {@link EclipseClientConfig#heartbeatSound()}.
     */
    private static void tickSphereAmbience(Minecraft minecraft, ClientLevel level, Vec3 camera) {
        boolean wanted = interiorSphere && smoothedInterior > SPHERE_AMBIENCE_GATE;
        SphereDroneSound drone = droneSound;
        if (wanted) {
            if (drone == null || drone.isStopped()) {
                droneSound = new SphereDroneSound();
                minecraft.getSoundManager().play(droneSound);
            }
        } else {
            if (drone != null && drone.isStopped()) {
                droneSound = null; // ticks itself silent below the gate, then stops
            }
            return;
        }
        RandomSource random = level.random;
        boolean reduced = EclipseClientConfig.reducedFx();
        // STORM2 (W-D D3): the interior weather leans toward the eyewall — mote/ribbon
        // cadence quickens near the wall band and calms under the eye, so crossing
        // eye → wall reads as walking INTO the weather. The reducedFx interval doubling
        // stays layered on top (tier contract unchanged).
        StormFxClient.ClientStorm ambienceStorm = nearestStorm(camera);
        float weatherBias = 1.0F + 0.6F * smoothedWallProx - 0.5F * smoothedEyeDim;
        // Drifting ash/spore motes in a bubble around the camera.
        if (--moteCountdown <= 0) {
            int moteInterval = reduced ? MOTE_INTERVAL_TICKS * 2 : MOTE_INTERVAL_TICKS;
            moteCountdown = Math.max(1, Math.round(moteInterval / weatherBias));
            double mx = camera.x + (random.nextDouble() - 0.5D) * 18.0D;
            double my = camera.y + (random.nextDouble() - 0.3D) * 8.0D;
            double mz = camera.z + (random.nextDouble() - 0.5D) * 18.0D;
            // D3: the spawn bubble drifts toward the wall as WallProx rises (denser near
            // the eyewall), and motes stream tangentially at the stratum flow of their
            // height — the wind bands live inside the mass, not just in the grade.
            double vx = 0.0D;
            double vz = 0.0D;
            if (ambienceStorm != null) {
                double wallBearing = Math.atan2(camera.z - ambienceStorm.center.z,
                        camera.x - ambienceStorm.center.x);
                mx += Math.cos(wallBearing) * 5.0D * smoothedWallProx;
                mz += Math.sin(wallBearing) * 5.0D * smoothedWallProx;
                double moteBearing = Math.atan2(mz - ambienceStorm.center.z,
                        mx - ambienceStorm.center.x);
                float heightFrac = (float) Mth.clamp(
                        (my - ambienceStorm.center.y) / ambienceStorm.height, 0.0D, 1.0D);
                double flow = 0.04D * stratumFlow(heightFrac) / STRATUM_FLOW_MAX;
                vx = -Math.sin(moteBearing) * flow;
                vz = Math.cos(moteBearing) * flow;
            }
            level.addParticle(random.nextInt(6) == 0
                            ? ParticleTypes.SPORE_BLOSSOM_AIR : ParticleTypes.ASH,
                    mx, my, mz, vx, -0.005D - random.nextDouble() * 0.01D, vz);
        }
        // Ground-fog ribbons: low smoke crawling along a slowly rotating bearing.
        ribbonAngle += 0.012F;
        if (--ribbonCountdown <= 0) {
            int ribbonInterval = reduced ? RIBBON_INTERVAL_TICKS * 2 : RIBBON_INTERVAL_TICKS;
            ribbonCountdown = Math.max(1, Math.round(ribbonInterval / weatherBias));
            double along = 2.0D + random.nextDouble() * 7.0D;
            double side = (random.nextDouble() - 0.5D) * 3.0D;
            double cos = Math.cos(ribbonAngle);
            double sin = Math.sin(ribbonAngle);
            level.addParticle(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                    camera.x + cos * along - sin * side,
                    camera.y - 1.5D + random.nextDouble() * 0.4D,
                    camera.z + sin * along + cos * side,
                    cos * 0.02D, 0.002D, sin * 0.02D);
        }
        // Ash-devil mini-whirls (FX-STORM): wandering spiral anchors near the ground —
        // each lifts one tangential ash mote per cadence tick into a twisting column.
        int devils = reduced ? 1 : ASH_DEVILS_FULL;
        if (--devilReseedCountdown <= 0) {
            devilReseedCountdown = ASH_DEVIL_RESEED_TICKS;
            for (int d = 0; d < ASH_DEVILS_FULL; d++) {
                double a = random.nextDouble() * Math.PI * 2.0D;
                double dist = ASH_DEVIL_MIN_DIST
                        + random.nextDouble() * (ASH_DEVIL_MAX_DIST - ASH_DEVIL_MIN_DIST);
                DEVIL_X[d] = camera.x + Math.cos(a) * dist;
                DEVIL_Z[d] = camera.z + Math.sin(a) * dist;
            }
        }
        for (int d = 0; d < devils; d++) {
            if (reduced && (StormFxClient.ticks() + d) % 2 != 0) {
                continue; // reducedFx halves the whirl cadence too
            }
            DEVIL_PHASE[d] += 0.38F + d * 0.05F;
            // The anchor wanders slowly so the whirl snakes across the ground.
            DEVIL_X[d] += Math.cos(DEVIL_PHASE[d] * 0.11D) * 0.05D;
            DEVIL_Z[d] += Math.sin(DEVIL_PHASE[d] * 0.13D) * 0.05D;
            double h = random.nextDouble() * 2.5D;
            double whirlR = 0.5D + h * 0.25D;
            double wa = DEVIL_PHASE[d] + h * 2.1D;
            double px = DEVIL_X[d] + Math.cos(wa) * whirlR;
            double pz = DEVIL_Z[d] + Math.sin(wa) * whirlR;
            level.addParticle(random.nextInt(5) == 0 ? ParticleTypes.WHITE_ASH : ParticleTypes.ASH,
                    px, camera.y - 1.6D + h, pz,
                    -Math.sin(wa) * 0.06D, 0.03D + random.nextDouble() * 0.02D,
                    Math.cos(wa) * 0.06D);
        }
        // Heartbeat-adjacent sub-bass pulse — user opt-out honored (B12 setting).
        if (--pulseCountdown <= 0) {
            pulseCountdown = PULSE_MIN_TICKS + random.nextInt(PULSE_MAX_TICKS - PULSE_MIN_TICKS + 1);
            if (EclipseClientConfig.heartbeatSound()) {
                level.playLocalSound(camera.x, camera.y, camera.z,
                        EclipseSounds.EVENT_STORM_PULSE.get(), SoundSource.AMBIENT,
                        0.38F * smoothedInterior, 0.72F + random.nextFloat() * 0.12F, false);
            }
        }
        // Silent silhouette flicker (lightning-less): fog lifts, shapes read, fog closes.
        if (--flickerCountdown <= 0) {
            flickerCountdown = FLICKER_MIN_TICKS + random.nextInt(FLICKER_MAX_TICKS - FLICKER_MIN_TICKS + 1);
            flash(5);
            level.playLocalSound(camera.x, camera.y, camera.z,
                    EclipseSounds.EVENT_STORM_FLICKER.get(), SoundSource.AMBIENT,
                    0.3F * smoothedInterior, 0.85F + random.nextFloat() * 0.2F, false);
        }
    }

    /** Relative drone bed of a sphere interior; volume rides the interior, self-stopping. */
    private static final class SphereDroneSound
            extends net.minecraft.client.resources.sounds.AbstractTickableSoundInstance {
        private static final float MAX_VOLUME = 0.65F;

        SphereDroneSound() {
            super(EclipseSounds.AMBIENT_STORM_DOME_DRONE.get(), SoundSource.AMBIENT,
                    net.minecraft.client.resources.sounds.SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.relative = true;
            this.x = 0.0D;
            this.y = 0.0D;
            this.z = 0.0D;
            this.volume = 0.0F;
        }

        @Override
        public void tick() {
            if (!interiorSphere || smoothedInterior < 0.05F) {
                this.stop();
                return;
            }
            this.volume = MAX_VOLUME * smoothedInterior;
            // STORM2 (W-D D6): the drone sinks deeper under the apex eye — the calm
            // luminous core hums lower than the churn near the wall (existing sound only).
            this.pitch = 1.0F - 0.06F * smoothedEyeDim;
        }

        void forceStop() {
            this.stop();
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
        // STORM2 (W-D D5) pre-release "gulp": a sin half-wave pinch 24→14→24 over the
        // GULP_TICKS implosion charge — full pinch at the middle tick, released by the
        // time the white-out owns the frame. Wins against the flash lift by construction
        // (the sin envelope zeroes at both ends, so there is no pop either way).
        if (gulpTicks > 0) {
            float inhale = Mth.sin((float) Math.PI * (1.0F - gulpTicks / (float) GULP_TICKS));
            farTarget = Mth.lerp(inhale, farTarget, GULP_FOG_FAR);
        }
        event.setFarPlaneDistance(Math.min(far, Mth.lerp(interior, far, farTarget)));
        event.setNearPlaneDistance(Math.min(near, Mth.lerp(interior, near, INTERIOR_FOG_NEAR)));
        event.setCanceled(true);
    }

    @SubscribeEvent
    static void onComputeFogColor(ViewportEvent.ComputeFogColor event) {
        float interior = smoothedInterior;
        float approach = smoothedApproach;
        // C8 explosion white-out (decays over WHITEOUT_TICKS, scaled by shell proximity).
        float white = whiteoutTicks > 0
                ? (whiteoutTicks / (float) WHITEOUT_TICKS) * whiteoutStrength : 0.0F;
        // FX-STORM stage 4: the clear-sky bloom tail after the white-out releases.
        float bloom = bloomTicks > 0
                ? (bloomTicks / (float) BLOOM_TICKS) * bloomStrength : 0.0F;
        if (interior <= 0.02F && approach <= 0.02F && white <= 0.02F && bloom <= 0.02F) {
            return;
        }
        // IDEA-15 §2: flash blows the palette toward its blow color — backlit cutouts.
        // C8: sphere interiors run the green-violet grade + pale-green flicker blow, so the
        // site storms read nothing like the intro vortex's rain-slate.
        float lift = interior > 0.02F
                ? Mth.clamp(flashTicks / (float) FLASH_MAX_TICKS, 0.0F, 1.0F) * 0.7F
                : 0.0F;
        boolean sphere = interiorSphere;
        float targetR = sphere ? Mth.lerp(lift, SPH_FOG_R, SPH_FLASH_R) : Mth.lerp(lift, FOG_R, FLASH_R);
        float targetG = sphere ? Mth.lerp(lift, SPH_FOG_G, SPH_FLASH_G) : Mth.lerp(lift, FOG_G, FLASH_G);
        float targetB = sphere ? Mth.lerp(lift, SPH_FOG_B, SPH_FLASH_B) : Mth.lerp(lift, FOG_B, FLASH_B);
        // IDEA-15 §1: outside, daylight drains up to 15 % toward the storm palette as you close.
        float blend = Math.max(interior * 0.92F, approach * APPROACH_TINT_MAX);
        if (white > 0.0F) {
            targetR = Mth.lerp(white, targetR, 0.96F);
            targetG = Mth.lerp(white, targetG, 0.96F);
            targetB = Mth.lerp(white, targetB, 1.00F);
            blend = Math.max(blend, white * 0.92F);
        }
        if (bloom > 0.0F) {
            // Pale morning blue-white — the "sky opens" beat riding out of the white-out.
            targetR = Mth.lerp(bloom, targetR, 0.74F);
            targetG = Mth.lerp(bloom, targetG, 0.80F);
            targetB = Mth.lerp(bloom, targetB, 0.94F);
            blend = Math.max(blend, bloom * 0.35F);
        }
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
        // C8 sphere-interior state.
        interiorSphere = false;
        whiteoutTicks = 0;
        whiteoutStrength = 0.0F;
        moteCountdown = 0;
        ribbonCountdown = 0;
        pulseCountdown = 0;
        flickerCountdown = 0;
        // FX-STORM round state.
        gustAmount = 0.0F;
        smoothedWallProx = 0.0F;
        wallProxTarget = 0.0F;
        bloomTicks = 0;
        bloomStrength = 0.0F;
        devilReseedCountdown = 0;
        // STORM2 round (W-D) state — M5: nothing survives Clone/LoggingOut/level-null.
        smoothedEyeDim = 0.0F;
        eyeDimTarget = 0.0F;
        smoothedBandFlow = 0.0F;
        bandFlowTarget = 0.0F;
        smoothedWallBand = 0.0F;
        wallBandTarget = 0.0F;
        gulpTicks = 0;
        clearGodFingers();
        SphereDroneSound drone = droneSound;
        droneSound = null;
        if (drone != null) {
            drone.forceStop();
        }
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
