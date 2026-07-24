package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client-side FX blackboard (P2 §3.1, FROZEN API). All setters are safe to call from payload
 * handlers/tick; reads happen in render. Setters store raw targets; the eased getters
 * interpolate against the client tick counter (see {@link Ticker}), so animation pauses with
 * the game and every consumer (post feeders, sky renderer, world FX) reads the same curve.
 *
 * <p>Allocation discipline: {@link #shockwaveParams(float)} returns a pre-allocated scratch
 * {@link Vector4f} that is overwritten on every call — consume it immediately, never cache it
 * across frames.</p>
 */
public final class EclipseFxState {
    // Eclipse phases: 0=NONE, 1=BUILDUP, 2=TOTAL, 3=ENDING
    public static final int PHASE_NONE = 0;
    public static final int PHASE_BUILDUP = 1;
    public static final int PHASE_TOTAL = 2;
    public static final int PHASE_ENDING = 3;

    /**
     * Exposure dip target while the eclipse phase is TOTAL (R3), eased over
     * {@value #EXPOSURE_RAMP_TICKS} ticks. 0.62 keeps the totality readable — combined
     * with the world-grade crush the old 0.35 rendered the whole world near-black.
     */
    private static final float TOTAL_EXPOSURE = 0.62F;
    private static final int EXPOSURE_RAMP_TICKS = 60;
    /** Ghost grade ease length (R18). */
    private static final int GHOST_RAMP_TICKS = 30;

    /** Client tick counter driving every eased curve (advances only while the game runs). */
    private static int clientTicks;

    // --- eclipse ---
    private static int eclipsePhase = PHASE_NONE;
    private static float eclipseFrom;
    private static float eclipseTarget;
    private static int eclipseStartTick;
    private static int eclipseRampTicks = 1;
    private static boolean permanentSunRim;

    // --- exposure (driven by eclipse phase; separate ease so TOTAL dips independently) ---
    private static float exposureFrom = 1.0F;
    private static float exposureTarget = 1.0F;
    private static int exposureStartTick;

    // --- simple scalar feeds ---
    private static float borderProximity;
    private static float altarAberration;
    private static float stormInterior;
    private static float stormRain;

    // --- ghost grade ---
    private static boolean ghostActive;
    private static float ghostFrom;
    private static int ghostStartTick = -GHOST_RAMP_TICKS;

    // --- shockwave ---
    @Nullable
    private static Vec3 shockOrigin;
    private static float shockStrength;
    private static int shockStartTick;
    private static int shockDurationTicks;
    private static final Vector4f SHOCK_PARAMS = new Vector4f();
    private static final Vector4f SHOCK_SCRATCH = new Vector4f();

    // --- transition glitch/fade envelope (rift/portal/loading, driven by W8 TransitionFx) ---
    private static int transStartTick = Integer.MIN_VALUE;
    private static int transIn;
    private static int transHold;
    private static int transOut;

    // --- post-expansion new-land glow band (IDEA-14 §3; additive — the frozen API is untouched) ---
    /** New-land glow envelope: full at set time, gone after {@value} ticks (~10 min). */
    private static final int NEW_LAND_GLOW_TICKS = 12000;
    private static float newLandInnerR;
    private static float newLandOuterR;
    private static int newLandStartTick = Integer.MIN_VALUE;

    private EclipseFxState() {}

    // ------------------------------------------------------------------ eclipse

    /** Eclipse phases: 0=NONE, 1=BUILDUP, 2=TOTAL, 3=ENDING. */
    public static void setEclipse(int phase, float intensity, int rampTicks) {
        eclipseFrom = eclipseAmount(0.0F);
        eclipseTarget = Mth.clamp(intensity, 0.0F, 1.0F);
        eclipseStartTick = clientTicks;
        eclipseRampTicks = Math.max(1, rampTicks);
        eclipsePhase = Mth.clamp(phase, PHASE_NONE, PHASE_ENDING);
        // R3: during TOTAL the exposure dips to TOTAL_EXPOSURE (0.62) with its own 60-tick ease.
        float wantedExposure = eclipsePhase == PHASE_TOTAL ? TOTAL_EXPOSURE : 1.0F;
        if (wantedExposure != exposureTarget) {
            exposureFrom = exposureMul(0.0F);
            exposureTarget = wantedExposure;
            exposureStartTick = clientTicks;
        }
    }

    /** Eased eclipse amount in [0,1]; drives sky scale-up, world grade and halo growth. */
    public static float eclipseAmount(float partialTick) {
        return Mth.lerp(easedProgress(eclipseStartTick, eclipseRampTicks, partialTick), eclipseFrom, eclipseTarget);
    }

    public static int eclipsePhase() {
        return eclipsePhase;
    }

    /** Set once after intro v3 (persisted server-side by P4, re-sent at login). */
    public static void setPermanentSunRim(boolean rim) {
        permanentSunRim = rim;
    }

    public static boolean permanentSunRim() {
        return permanentSunRim;
    }

    /**
     * Screen exposure multiplier for the {@code eclipse:world_grade} pipeline: 1.0 normally,
     * easing to {@value #TOTAL_EXPOSURE} while the eclipse phase is TOTAL (R3).
     */
    public static float exposureMul(float partialTick) {
        return Mth.lerp(easedProgress(exposureStartTick, EXPOSURE_RAMP_TICKS, partialTick), exposureFrom, exposureTarget);
    }

    // ------------------------------------------------------------------ border / altar

    /** Moved here from {@code VeilPostController}: 0 = far from the soft border, 1 = touching. */
    public static void setBorderProximity(float p) {
        borderProximity = Mth.clamp(p, 0.0F, 1.0F);
    }

    public static float borderProximity() {
        return borderProximity;
    }

    /** Altar chromatic-aberration zone strength 0..1 (W4 feeds, `eclipse:altar_aberration` reads). */
    public static void setAltarAberration(float a) {
        altarAberration = Mth.clamp(a, 0.0F, 1.0F);
    }

    public static float altarAberration() {
        return altarAberration;
    }

    // ------------------------------------------------------------------ ghost grade

    /** 0-lives grade on/off; the eased amount ramps over {@value #GHOST_RAMP_TICKS} ticks. */
    public static void setGhost(boolean active) {
        if (active == ghostActive) {
            return;
        }
        ghostFrom = ghostAmount(0.0F);
        ghostActive = active;
        ghostStartTick = clientTicks;
    }

    /** Eased ghost-grade amount in [0,1]. */
    public static float ghostAmount(float partialTick) {
        return Mth.lerp(easedProgress(ghostStartTick, GHOST_RAMP_TICKS, partialTick),
                ghostFrom, ghostActive ? 1.0F : 0.0F);
    }

    // ------------------------------------------------------------------ shockwave

    /** Starts a world-anchored screen shockwave (R8); re-projected to NDC every frame. */
    public static void startShockwave(Vec3 worldOrigin, float strength, int durationTicks) {
        shockOrigin = worldOrigin;
        shockStrength = strength;
        shockStartTick = clientTicks;
        shockDurationTicks = Math.max(1, durationTicks);
    }

    /**
     * {@code null} when inactive; xy = screen ndc of origin, z = progress 0..1, w = strength.
     * Returns a shared scratch vector — consume immediately. When the origin is behind the
     * camera the xy components are pushed far offscreen (±10) so ring math stays finite.
     */
    @Nullable
    public static Vector4f shockwaveParams(float partialTick) {
        Vec3 origin = shockOrigin;
        if (origin == null) {
            return null;
        }
        float progress = (clientTicks + partialTick - shockStartTick) / shockDurationTicks;
        if (progress >= 1.0F) {
            shockOrigin = null;
            return null;
        }
        if (SunTracker.worldToNdc(origin, SHOCK_SCRATCH)) {
            SHOCK_PARAMS.set(SHOCK_SCRATCH.x, SHOCK_SCRATCH.y, Mth.clamp(progress, 0.0F, 1.0F), shockStrength);
        } else {
            SHOCK_PARAMS.set(10.0F, 10.0F, Mth.clamp(progress, 0.0F, 1.0F), shockStrength);
        }
        return SHOCK_PARAMS;
    }

    // ------------------------------------------------------------------ storm interior

    public static void setStormInterior(float amount, float rain) {
        stormInterior = Mth.clamp(amount, 0.0F, 1.0F);
        stormRain = Mth.clamp(rain, 0.0F, 1.0F);
    }

    public static float stormInterior() {
        return stormInterior;
    }

    public static float stormRain() {
        return stormRain;
    }

    // ------------------------------------------------------------------ new-land glow (IDEA-14 §3)

    /**
     * Records the freshly grown annulus ({@code fx/new_land_glow} band-radii payload) so the
     * ambient upwelling motes can fade over the next ~10 minutes. Transient by design:
     * a rejoin simply loses the remaining glow (matches the eclipse-grade rejoin behavior).
     */
    public static void setNewLandBand(float innerR, float outerR) {
        if (outerR <= innerR || outerR <= 0.0F) {
            clearNewLandBand();
            return;
        }
        newLandInnerR = innerR;
        newLandOuterR = outerR;
        newLandStartTick = clientTicks;
    }

    /** Dimension change / logout: the band is dimension-local, so it must not survive. */
    public static void clearNewLandBand() {
        newLandInnerR = 0.0F;
        newLandOuterR = 0.0F;
        newLandStartTick = Integer.MIN_VALUE;
    }

    /** New-land glow envelope 0..1: {@code 1 − age/12000}, 0 when unset or expired. */
    public static float newLandGlow() {
        if (newLandStartTick == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float glow = 1.0F - (clientTicks - newLandStartTick) / (float) NEW_LAND_GLOW_TICKS;
        if (glow <= 0.0F) {
            clearNewLandBand();
            return 0.0F;
        }
        return glow;
    }

    /** Whether a horizontal radius from the origin lies inside the glowing annulus. */
    public static boolean newLandBandContains(double radius) {
        return newLandStartTick != Integer.MIN_VALUE
                && radius >= newLandInnerR && radius <= newLandOuterR;
    }

    // ------------------------------------------------------------------ transition glitch

    /**
     * Rift/portal/loading transition envelope: glitch and fade rise over {@code inTicks},
     * hold for {@code holdTicks} (use a large hold to stay black until the exit call), then
     * release over {@code outTicks}. W8's {@code TransitionFx} sequences enter/exit pairs.
     */
    public static void startTransitionGlitch(int inTicks, int holdTicks, int outTicks) {
        transStartTick = clientTicks;
        transIn = Math.max(0, inTicks);
        transHold = Math.max(0, holdTicks);
        transOut = Math.max(0, outTicks);
    }

    /** Glitch amount 0..1 of the transition envelope (drives {@code eclipse:rift_glitch} GlitchAmount). */
    public static float transitionGlitch(float partialTick) {
        return transitionEnvelope(partialTick);
    }

    /** Fade-to-black amount 0..1 of the transition envelope (drives {@code eclipse:rift_glitch} FadeAmount). */
    public static float transitionFade(float partialTick) {
        return transitionEnvelope(partialTick);
    }

    private static float transitionEnvelope(float partialTick) {
        if (transStartTick == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float t = clientTicks + partialTick - transStartTick;
        if (t < transIn) {
            return smooth(transIn <= 0 ? 1.0F : t / transIn);
        }
        t -= transIn;
        if (t < transHold) {
            return 1.0F;
        }
        t -= transHold;
        if (t < transOut) {
            return smooth(1.0F - t / transOut);
        }
        transStartTick = Integer.MIN_VALUE; // envelope done
        return 0.0F;
    }

    // ------------------------------------------------------------------ lifecycle

    /** Logout/disconnect reset — every feed returns to its idle value. */
    public static void clearAll() {
        eclipsePhase = PHASE_NONE;
        eclipseFrom = 0.0F;
        eclipseTarget = 0.0F;
        eclipseRampTicks = 1;
        permanentSunRim = false;
        exposureFrom = 1.0F;
        exposureTarget = 1.0F;
        borderProximity = 0.0F;
        altarAberration = 0.0F;
        stormInterior = 0.0F;
        stormRain = 0.0F;
        ghostActive = false;
        ghostFrom = 0.0F;
        ghostStartTick = clientTicks - GHOST_RAMP_TICKS;
        shockOrigin = null;
        transStartTick = Integer.MIN_VALUE;
        clearNewLandBand();
    }

    /** Current client tick counter — shared time base for {@link FxBudget} windows. */
    static int clientTicks() {
        return clientTicks;
    }

    /** Smoothstep-eased progress of a tick ramp starting at {@code startTick}. */
    private static float easedProgress(int startTick, int rampTicks, float partialTick) {
        float linear = Mth.clamp((clientTicks + partialTick - startTick) / Math.max(1, rampTicks), 0.0F, 1.0F);
        return smooth(linear);
    }

    private static float smooth(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }

    /** Advances the shared FX clock and clears the blackboard on disconnect. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Ticker {
        private Ticker() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            clientTicks++;
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            clearAll();
        }
    }
}
