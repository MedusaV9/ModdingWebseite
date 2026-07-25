package dev.projecteclipse.eclipse.stormfx;

import java.util.List;

import org.joml.Vector3f;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.MeshData;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.sky.OverworldPurpleEffects;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * World-space storm wall/vortex geometry (P2 W9, R14/R15) — camera-relative, drawn at
 * {@link #RENDER_STAGE} with the vanilla-border draw pattern ({@code POSITION_COLOR} +
 * {@link BufferUploader#drawWithShader}); switch the stage constant to
 * {@code AFTER_TRANSLUCENT_BLOCKS} if Sodium depth-sort artifacts appear (§7 risk 2 — same
 * matrices). Everything is per-vertex procedural (hash/value noise gray/alpha/displacement) —
 * zero textures, zero per-frame heap allocations, and NO Iris gate: world-space geometry is
 * the Iris fallback tier (§7 risk 1), so the wall stays opaque under shaderpacks.
 *
 * <p><b>Never-see-inside guarantee:</b> an opaque, unlit, near-black occluder cylinder at
 * {@code r - }{@value #OCCLUDER_INSET} with a cone lid is drawn depth-writing BEFORE the
 * translucent shells. It covers every angle and height (including straight down from above),
 * so no camera position outside can resolve anything inside — independent of shaders, fog or
 * config (R14/R15 frozen decision: geometry, not post). STORM 2.0 shells never cross it:
 * EXO displacement clamps to {@code occluderR + 0.3}, ENDO to {@code occluderR − 0.3}.</p>
 *
 * <p><b>STORM 2.0 (PLAN-STORM2 W-A) — the volumetric mass:</b> C8 sphere storms tessellate
 * as an <b>EXO stack of 8 nested noise-displaced dome shells</b> (r+3 → r−4.4, alternating
 * additive glow / alpha sheet, outer thin+fast, inner darker+slower) whose independent
 * {@link #fvnoise3} radial billow gives real motion parallax — the 8-block band around the
 * occluder reads as a volume, not wallpaper. Deep inside, an <b>ENDO stack</b> (3 shells
 * inside the occluder) gives the interior wall the same layered churn. On top: 4 vertical
 * <b>wind-band strata</b> (0.6×/1.0×/1.5×/−0.8× pattern speeds, brightened shear seams),
 * an <b>eyewall → eye</b> latitude envelope whose translucent apex opens onto the dark
 * occluder pit ringed by a 6-arm counter-rotating <b>polar vortex crown</b>, a two-band
 * <b>debris torus</b> ground skirt with tumbling hash-orbit debris, the per-vertex
 * <b>N·V limb law</b> (thick silhouettes from every camera angle — replaces the bearing-only
 * rim heuristic), <b>log-spiral rainband</b> alpha gates (the hurricane read), sun-side
 * <b>rim scatter</b> via {@link SunTracker} (bone-white day fringe, moon-silver night), and
 * the {@link StormWeatherFx} <b>lit-from-within pulse</b> (inner shells flash hardest).
 * {@code STATE_EXPLODE} detonates the stack with a per-shell stagger — nested shockwave
 * shells — while the frozen implosion→flash→shards→bloom staging and white-out are kept.</p>
 *
 * <p><b>LOD/tier ladder</b> (distance {@code d} from the shell, crossfaded over
 * ±{@value #LOD_FADE} blocks; sphere EXO shells by {@link FxBudget#qualityTier()}):</p>
 * <ul>
 *   <li>near ({@code d < 160}): 8 shells × 12 rings (tier 2) / 5 × 10 (tier 1) / 3 × 8
 *       (tier 0) × ≤ {@value #NEAR_SEGMENTS} segments; crown/torus/debris tier ≥ 1;</li>
 *   <li>far ({@code 160–320}): 3 shells × {@value #SPHERE_RINGS_FAR} rings ×
 *       {@value #FAR_SEGMENTS} segments (deep shells additionally need {@code d < 240});</li>
 *   <li>impostor ({@code > 320}): a single {@value #IMPOSTOR_SEGMENTS}-segment ring + lid.</li>
 * </ul>
 * <p>An alpha-floor cull skips any shell column whose peak alpha would be &lt; 0.015 —
 * the stack is fill-rate-bound, and the cull typically drops 15–25 % of columns.</p>
 *
 * <p>Camera-centered tangent-arc windows are LAW (EVAL-POL-F #1): geometry windows stay
 * pinned to the camera bearing; ALL rotation (bands, strata, arms, churn) lives in
 * noise-pattern indices. Displacement noise indexes the RAW world angle, so the billow is
 * world-stable while the window follows the camera.</p>
 *
 * <p>Also draws every live lightning ribbon: sky strikes ({@link StormFxClient#bolts()}, 6
 * jittered sub-segments × core+glow layers + impact cross flash = ≤ 14 quads each, 2-tick
 * white core then violet decay) and small shell arc crackles ({@link StormFxClient#arcs()}),
 * plus the living Tyrant's wall silhouette during {@link StormInteriorFx#flash} flickers
 * (ACTIVE sphere storms only — drawn ON the occluder, guarantee untouched).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormWallRenderer {
    /** Swap to {@code AFTER_TRANSLUCENT_BLOCKS} if Sodium depth-sorting artifacts appear (§7). */
    private static final RenderLevelStageEvent.Stage RENDER_STAGE =
            RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    // --- LOD ---
    private static final float NEAR_LOD_END = 160.0F;
    private static final float FAR_LOD_END = 320.0F;
    private static final float LOD_FADE = 16.0F;
    private static final int NEAR_SEGMENTS = 96;
    private static final int FAR_SEGMENTS = 48;
    private static final int IMPOSTOR_SEGMENTS = 8;
    /**
     * Occluder segment count is fixed (EVAL-4 M4): the old 48/24 distance step popped the
     * opaque rim silhouette against the sky once per approach (~0.9-block radius error on a
     * r=100 storm). 48-gon everywhere costs only 2·segments quads per storm — trivial.
     */
    private static final int OCCLUDER_SEGMENTS = 48;
    /** Extra visible-arc margin (radians) beyond the geometric tangent arc when outside. */
    private static final double ARC_MARGIN = 0.5D;
    /** The deep EXO shells (index ≥ 4) also need the camera this close (fill-rate guard). */
    private static final float DEEP_SHELL_MAX_DIST = 240.0F;

    // --- shape ---
    /** The opaque occluder sits this far inside the nominal radius. */
    static final float OCCLUDER_INSET = 5.0F;
    /**
     * STORM 2.0 cylinder shell ladder (A9): 6 radial offsets and their blend pass
     * (true = additive), plus per-shell churn clocks (outer fast → inner slow), gray
     * depth-darkening, alpha scaling and noise-displacement amplitude.
     */
    private static final float[] SHELL_OFFSETS = {3.0F, 2.0F, 0.0F, -1.5F, -3.0F, -4.4F};
    private static final boolean[] SHELL_ADDITIVE = {true, false, false, true, false, true};
    private static final float[] SHELL_CHURN_TICKS = {2.0F, 4.0F, 5.0F, 6.0F, 8.0F, 10.0F};
    private static final float[] SHELL_GRAY_MUL = {1.0F, 1.0F, 1.0F, 0.9F, 0.8F, 0.7F};
    private static final float[] SHELL_ALPHA_MUL = {0.9F, 0.55F, 1.0F, 0.8F, 0.6F, 0.65F};
    private static final float[] SHELL_DISP_AMP = {1.4F, 1.2F, 1.0F, 0.8F, 0.6F, 0.5F};
    /** Cylinder shell index sets per quality tier (near) and for the far band. */
    private static final int[] CYL_NEAR_TIER2 = {0, 1, 2, 3, 4, 5};
    private static final int[] CYL_NEAR_TIER1 = {0, 1, 2, 5};
    private static final int[] CYL_NEAR_TIER0 = {1, 2, 5};
    private static final int[] CYL_FAR = {0, 2};
    /**
     * Vortex shells lean inward 8° (R14): top radius shrinks by tan(8°) per block of height.
     * Package-visible so {@link StormInteriorFx} evaluates inside/outside against the TILTED
     * radius at camera height (IDEA-15 §6 — EVAL-4 post-eval interior over-reach).
     */
    static final float TAN_TILT = 0.1405F;
    /** Total geometric twist of a vortex shell column over its height (radians). */
    private static final float VORTEX_TWIST = 0.9F;
    /** Vortex swirl 0.35 rad/s (R14) at 20 ticks/s; walls only drift slowly. */
    private static final float SWIRL_RAD_PER_TICK = 0.0175F;
    private static final float WALL_DRIFT_RAD_PER_TICK = 0.002F;
    /** The wall band extends this far below the anchor Y (terrain irregularity skirt). */
    private static final float BASE_SKIRT = 4.0F;

    // --- palette (storm slate with the eclipse-violet cast) ---
    private static final float ALPHA_R = 0.10F;
    private static final float ALPHA_G = 0.075F;
    private static final float ALPHA_B = 0.145F;
    private static final float ADD_R = 0.30F;
    private static final float ADD_G = 0.20F;
    private static final float ADD_B = 0.47F;
    private static final float OCC_R = 0.014F;
    private static final float OCC_G = 0.010F;
    private static final float OCC_B = 0.026F;
    /**
     * STORM-VOL: sphere-occluder tint while {@link StormVolumeFx} raymarches this storm's
     * interior mass. Still drawn FULLY OPAQUE (the never-see-inside guarantee is
     * geometry/alpha, untouched) — only the COLOR lifts from near-black to a deep storm
     * slate-green so the volumetric fog in front of it reads as continuous mass instead
     * of silhouetting a black balloon wherever the shells thin out.
     */
    private static final float OCC_SOFT_R = 0.038F;
    private static final float OCC_SOFT_G = 0.052F;
    private static final float OCC_SOFT_B = 0.048F;

    // --- C8 sphere storms → STORM 2.0 volumetric EXO stack (PLAN-STORM2 §W-A A2) ---
    /**
     * The 8 nested EXO dome shells packed around the occluder: radial offsets, blend pass
     * (glow/sheet/glow/BODY/sheet/glow/sheet/rim), per-shell churn clocks (outer fast →
     * inner slow — the parallax depth cue), gray depth-darkening (inner shells darker),
     * alpha bases (body keeps the frozen 0.88; deep sheets 0.55/0.45; glows 0.30 → rim
     * 0.22), band-lead multipliers and {@link #fvnoise3} displacement amplitudes
     * (1.6 blocks outermost → 0.4 innermost; clamped to {@code occluderR + 0.3}).
     */
    private static final float[] EXO_OFFSETS = {3.0F, 2.0F, 1.0F, 0.0F, -1.2F, -2.4F, -3.6F, -4.4F};
    private static final boolean[] EXO_ADDITIVE = {true, false, true, false, false, true, false, true};
    private static final float[] EXO_CHURN_TICKS = {2.0F, 3.0F, 4.0F, 5.0F, 6.0F, 8.0F, 10.0F, 12.0F};
    private static final float[] EXO_GRAY_MUL = {1.0F, 1.0F, 0.95F, 1.0F, 0.9F, 0.85F, 0.8F, 0.65F};
    private static final float[] EXO_ALPHA_MUL = {0.30F, 0.40F, 0.28F, 0.88F, 0.55F, 0.26F, 0.45F, 0.22F};
    private static final float[] EXO_BAND_LEAD = {1.6F, 1.2F, 0.9F, 0.6F, -0.4F, -0.7F, 0.5F, 0.3F};
    private static final float[] EXO_DISP_AMP = {1.6F, 1.4F, 1.2F, 1.0F, 0.8F, 0.6F, 0.5F, 0.4F};
    /** A6 inner-flash depth scaling: light born INSIDE the mass — inner shells flash hardest. */
    private static final float[] EXO_PULSE_DEPTH = {0.35F, 0.44F, 0.54F, 0.63F, 0.72F, 0.81F, 0.91F, 1.0F};
    /** EXO shell index sets: 8/5/3 shells by quality tier at near LOD, 3 at far LOD. */
    private static final int[] EXO_NEAR_TIER2 = {0, 1, 2, 3, 4, 5, 6, 7};
    private static final int[] EXO_NEAR_TIER1 = {0, 1, 3, 5, 7};
    private static final int[] EXO_NEAR_TIER0 = {1, 3, 5};
    private static final int[] EXO_FAR = {0, 3, 5};
    /** Latitude bands of a sphere shell: near tier by quality (strata resolution), far fixed. */
    private static final int[] SPHERE_RINGS_BY_TIER = {8, 10, 12};
    private static final int SPHERE_RINGS_FAR = 6;
    /** Below-equator skirt (radians) so uneven terrain never opens a gap at the rim. */
    private static final float SPHERE_SKIRT_RAD = 0.16F;
    /** Base band drift (rad/tick); each latitude band leads the one below by +12%. */
    private static final float SPHERE_BAND_RAD_PER_TICK = 0.004F;
    /** Sphere alpha-shell base (slate pulled toward the fog-green cast). */
    private static final float SPH_ALPHA_R = 0.075F;
    private static final float SPH_ALPHA_G = 0.105F;
    private static final float SPH_ALPHA_B = 0.110F;
    /** Additive band hues: churn bands alternate fog-green ↔ eclipse-violet (green-violet glow). */
    private static final float SPH_GREEN_R = 0.22F;
    private static final float SPH_GREEN_G = 0.44F;
    private static final float SPH_GREEN_B = 0.32F;
    private static final float SPH_VIOLET_R = 0.30F;
    private static final float SPH_VIOLET_G = 0.20F;
    private static final float SPH_VIOLET_B = 0.47F;
    /** STATE_EXPLODE: the dome blows out to this many extra radii over the burst. */
    private static final float EXPLODE_EXPAND = 1.8F;
    /** White-hot flash target of the explosion flash beat. */
    private static final float EXPLODE_WHITE_R = 0.95F;
    private static final float EXPLODE_WHITE_G = 0.93F;
    private static final float EXPLODE_WHITE_B = 1.00F;
    /** A8: per-shell explosion stagger — outer shells release first (nested shockwaves). */
    private static final float EXPLODE_SHELL_STAGGER = 0.02F;

    // --- STORM 2.0 ENDO stack (A5): interior shells INSIDE the occluder ---
    /**
     * Deep-interior dome shells per quality tier (offsets from the nominal radius), their
     * blend pass and alpha bases; displacement clamps to {@code occluderR − 0.3} so the
     * occluder guarantee stays bit-for-bit. Character arrays index by position in the
     * tier list. Never drawn during EXPLODE (branch condition excludes it).
     */
    private static final float[] ENDO_OFFSETS_T2 = {-5.6F, -6.4F, -7.4F};
    private static final boolean[] ENDO_ADDITIVE_T2 = {false, true, false};
    private static final float[] ENDO_ALPHA_T2 = {0.50F, 0.35F, 0.25F};
    private static final float[] ENDO_OFFSETS_T1 = {-5.6F, -6.8F};
    private static final boolean[] ENDO_ADDITIVE_T1 = {false, true};
    private static final float[] ENDO_ALPHA_T1 = {0.50F, 0.35F};
    private static final float[] ENDO_OFFSETS_T0 = {-6.0F};
    private static final boolean[] ENDO_ADDITIVE_T0 = {false};
    private static final float[] ENDO_ALPHA_T0 = {0.50F};
    private static final float[] ENDO_CHURN_TICKS = {8.0F, 10.0F, 12.0F};
    private static final float[] ENDO_GRAY_MUL = {0.70F, 0.60F, 0.50F};
    private static final float[] ENDO_BAND_LEAD = {0.5F, -0.4F, 0.3F};
    private static final float[] ENDO_DISP_AMP = {0.5F, 0.4F, 0.35F};
    /** ENDO shells pulse 1.2× (A6) — the flash is born right next to them. */
    private static final float ENDO_PULSE_DEPTH = 1.2F;
    /** The Tyrant silhouette radius; ENDO shells outside it draw first (painter order). */
    private static final float ENDO_SILHOUETTE_SPLIT = -6.5F;
    /** Interior fog clamps reads to ~24 blocks; the ENDO arc window covers just that. */
    private static final double ENDO_ARC_REACH = 30.0D;
    /** Beyond this camera→interior-wall distance the fog has fully eaten the ENDO stack. */
    private static final float ENDO_VIEW_RANGE = 40.0F;

    // --- STORM 2.0 wind-band strata (A3) ---
    /** Ring → stratum lookup (master table over 12 rings; scaled for other ring counts). */
    private static final int[] STRATUM_OF_RING = {0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3};
    /** Heavy slow base, mid, fast upper, counter-rotating polar — pattern-index only. */
    private static final float[] STRATUM_SPEED = {0.6F, 1.0F, 1.5F, -0.8F};
    /** Brightened churning seam alpha between counter-shearing strata. */
    private static final float SHEAR_LINE_ALPHA = 0.08F;

    // --- STORM 2.0 eyewall → eye + polar crown (A4) ---
    private static final float EYE_START = 0.55F;
    private static final float EYEWALL_LO = 0.80F;
    private static final float EYEWALL_HI = 0.95F;
    /** Alpha collapse factor above the eyewall — the apex opens onto the occluder pit. */
    private static final float EYE_COLLAPSE = 0.15F;
    private static final float EYEWALL_RIM_ALPHA = 0.25F;
    private static final int CROWN_ARMS = 6;
    private static final int CROWN_SEGS = 8;
    /** Crown arms counter-rotate against the base band drift. */
    private static final float CROWN_SPEED_MUL = -1.3F;
    /** Reused crown-arm polyline scratch (9 points × xyz) — zero per-frame heap. */
    private static final float[] CROWN_PTS = new float[(CROWN_SEGS + 1) * 3];

    // --- STORM 2.0 log-spiral rainbands (IDEAS-STORM-1 #1) ---
    private static final float RAINBAND_ARMS = 3.0F;
    /** Latitude wrap: each arm winds ~half a turn from base to apex. */
    private static final float RAINBAND_WRAP = 1.4F;

    // --- STORM 2.0 N·V limb law (IDEAS-STORM-2 #1) ---
    /** Optical-thickness clamp so the silhouette never clips solid against the day carve. */
    private static final float LIMB_MAX = 2.2F;
    private static final float LIMB_NV_FLOOR = 1.0F / LIMB_MAX;

    // --- STORM 2.0 sun-side rim scatter (IDEAS-STORM-1 #5, via SunTracker) ---
    /** Desaturated bone-white day fringe (NOT warm gold — warm is the loot-camp beacon). */
    private static final float SCATTER_BONE_R = 0.85F;
    private static final float SCATTER_BONE_G = 0.82F;
    private static final float SCATTER_BONE_B = 0.74F;
    /** Moon-silver night fringe at 25% strength. */
    private static final float SCATTER_MOON_R = 0.72F;
    private static final float SCATTER_MOON_G = 0.76F;
    private static final float SCATTER_MOON_B = 0.90F;
    private static final float SCATTER_MOON_STRENGTH = 0.25F;
    /** Per-frame sun/moon azimuth + strength + tint (render thread, set before builds). */
    private static float scatterAzX;
    private static float scatterAzZ;
    private static float scatterStrength;
    private static float scatterR;
    private static float scatterG;
    private static float scatterB;

    // --- STORM 2.0 lit-from-within pulse cache (A6, per storm, render thread) ---
    private static float pulseAmt;
    private static double pulseBearing;
    private static float pulseLat;

    // --- FX-STORM round: multi-stage explosion (implosion → flash → shard ring → bloom) ---
    /** Fraction of the burst spent on the implosion suck-in before the shell releases. */
    static final float EXPLODE_IMPLODE_FRAC = 0.18F;
    /** Radius pinch depth at the implosion's deepest point. */
    private static final float EXPLODE_PINCH = 0.10F;
    /** Wall-fragment shard cross-quads riding the shockwave ring (reduced tier flies fewer). */
    private static final int EXPLODE_SHARDS_FULL = 22;
    private static final int EXPLODE_SHARDS_REDUCED = 12;

    // --- FX-STORM round: lightning veins crawling ALONG the wall surface (UV crawl) ---
    /** Vein head crawl speed in latitude-fraction per tick (base → apex in ~3 s). */
    private static final float VEIN_CRAWL_PER_TICK = 0.016F;
    /** A vein cell re-rolls its gate every this many ticks. */
    private static final int VEIN_WINDOW_TICKS = 44;
    /** Gate threshold — roughly 1 in 5 longitude cells carries a live vein. */
    private static final float VEIN_GATE = 0.80F;
    /** Latitude half-extent of the bright crawling head. */
    private static final float VEIN_HALF_WIDTH = 0.16F;

    // --- FX-STORM round: ground skirt dust → STORM 2.0 debris torus (A7) ---
    /** Neutral warm-gray so the skirt reads as kicked-up dust, not storm palette. */
    private static final float DUST_R = 0.135F;
    private static final float DUST_G = 0.125F;
    private static final float DUST_B = 0.115F;
    /** Tumbling debris cross-quads on stateless hash orbits around the torus. */
    private static final int TORUS_DEBRIS_FULL = 12;
    private static final int TORUS_DEBRIS_REDUCED = 6;

    // --- FX-STORM round: Tyrant wall silhouette (interior flicker beat, ACTIVE spheres) ---
    private static final float SIL_R = 0.010F;
    private static final float SIL_G = 0.008F;
    private static final float SIL_B = 0.018F;

    // --- daylight readability (EVAL-4 post-eval: wall reads flat from ~40 blocks at noon) ---
    /**
     * At night the dense base band holds a constant 0.86 alpha (the frozen R14 look). Against
     * a bright day sky that constant-alpha band reads as a featureless dark cylinder, so at
     * midday the churn noise is allowed to carve up to this much alpha out of each column —
     * per-column striping that restores the "swirling smoke" read without weakening the
     * never-see-inside guarantee (the opaque occluder sits 5 blocks further in regardless).
     */
    private static final float DAY_BASE_CARVE = 0.28F;
    /** Additive violet band alpha boost at full daylight (additive light washes out at noon). */
    private static final float DAY_ADDITIVE_BOOST = 0.55F;
    /** Extra downward spread of the churn gray range at full daylight (0.72 → 0.44 floor). */
    private static final float DAY_GRAY_SPREAD = 0.28F;
    /** Bolt ribbons widen up to this factor at noon so strikes stay readable at range. */
    private static final float DAY_BOLT_WIDEN = 0.35F;
    /**
     * Daylight factor of the current frame (0 night → 1 midday), written once per
     * {@link #onRenderLevelStage} before any build call — render-thread only, never stale.
     */
    private static float daylight;

    // --- bolts ---
    private static final int BOLT_SUB_SEGMENTS = 6;
    private static final int BOLT_CORE_TICKS = 2;
    /** Reused polyline scratch (7 points × xyz) — bolts allocate nothing per frame. */
    private static final float[] BOLT_PTS = new float[(BOLT_SUB_SEGMENTS + 1) * 3];

    private static final float TWO_PI = (float) (Math.PI * 2.0D);
    private static final float INV_TWO_PI = 1.0F / TWO_PI;

    private StormWallRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RENDER_STAGE) {
            return;
        }
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        List<StormFxClient.Bolt> bolts = StormFxClient.bolts();
        List<StormFxClient.Bolt> arcs = StormFxClient.arcs();
        if (storms.isEmpty() && bolts.isEmpty() && arcs.isEmpty()) {
            return; // zero cost while no storm/bolt exists anywhere
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        Vec3 camera = event.getCamera().getPosition();
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float time = StormFxClient.ticks() + partialTick;
        // Day/night readability factor (same cosine curve the sky pass uses); dimensions
        // without a sky light cycle keep the night look.
        boolean hasSkyLight = level.dimensionType().hasSkyLight();
        daylight = hasSkyLight ? OverworldPurpleEffects.dayFactor(level, partialTick) : 0.0F;
        updateRimScatter(hasSkyLight, partialTick);

        // PASS 1 — opaque occluders (depth-writing; the never-see-inside guarantee).
        if (!storms.isEmpty()) {
            BufferBuilder buffer = Tesselator.getInstance()
                    .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
            for (int i = 0; i < storms.size(); i++) {
                buildOccluder(buffer, storms.get(i), camera, partialTick);
            }
            draw(buffer, false, true);
        }

        // PASS 2 — alpha-blended shells (EXO sheets/body, ENDO, torus, impostor ring/lid).
        if (!storms.isEmpty()) {
            BufferBuilder buffer = Tesselator.getInstance()
                    .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
            for (int i = 0; i < storms.size(); i++) {
                buildShells(buffer, storms.get(i), camera, partialTick, time, false);
            }
            draw(buffer, false, false);
        }

        // PASS 3 — additive: glow shells, crown, caps, lightning ribbons, arc crackles.
        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int i = 0; i < storms.size(); i++) {
            buildShells(buffer, storms.get(i), camera, partialTick, time, true);
        }
        for (int i = 0; i < bolts.size(); i++) {
            buildBolt(buffer, bolts.get(i), camera, partialTick);
        }
        for (int i = 0; i < arcs.size(); i++) {
            buildBolt(buffer, arcs.get(i), camera, partialTick);
        }
        draw(buffer, true, false);
    }

    /**
     * Per-frame sun-side rim-scatter parameters (IDEAS-STORM-1 #5): sun azimuth from
     * {@link SunTracker} (fetched once, like {@link #daylight}), bone-white by day; the
     * anti-sun moon azimuth in silver at {@value #SCATTER_MOON_STRENGTH} strength by night.
     * Strength fades as the sun nears the zenith (no horizontal azimuth to scatter from).
     */
    private static void updateRimScatter(boolean hasSkyLight, float partialTick) {
        scatterStrength = 0.0F;
        if (!hasSkyLight) {
            return;
        }
        Vector3f sunDir = SunTracker.sunDirWorld(partialTick); // shared scratch — consume now
        float hx = sunDir.x();
        float hz = sunDir.z();
        boolean day = sunDir.y() >= 0.0F;
        float hLen = Mth.sqrt(hx * hx + hz * hz);
        if (hLen < 1.0E-3F) {
            return;
        }
        float sign = day ? 1.0F : -1.0F; // night: scatter from the moon (anti-sun) side
        scatterAzX = sign * hx / hLen;
        scatterAzZ = sign * hz / hLen;
        float horizon = Math.min(1.0F, hLen * 1.4F);
        scatterStrength = (day ? daylight : SCATTER_MOON_STRENGTH) * horizon;
        scatterR = day ? SCATTER_BONE_R : SCATTER_MOON_R;
        scatterG = day ? SCATTER_BONE_G : SCATTER_MOON_G;
        scatterB = day ? SCATTER_BONE_B : SCATTER_MOON_B;
    }

    // ------------------------------------------------------------------ occluder

    private static void buildOccluder(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float partialTick) {
        float vis = storm.visibility(partialTick);
        if (vis <= 0.01F) {
            return;
        }
        if (storm.state == S2CStormStatePayload.STATE_EXPLODE) {
            return; // C8: the shockwave reveals the interior — the sky clears immediately
        }
        if (storm.type == S2CStormStatePayload.TYPE_SPHERE) {
            buildSphereOccluder(buffer, storm, camera, vis);
            return;
        }
        int segments = OCCLUDER_SEGMENTS;

        float radius = Math.max(1.5F, storm.radius - OCCLUDER_INSET);
        float heightScale = heightScale(storm, vis);
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        float topY = (float) (storm.center.y - camera.y) + storm.height * heightScale;
        // Ramps briefly show the interior at low alpha — by design the reveal/intro places
        // content only once fully opaque (vis 1.6x → opaque at ~60% of the ramp).
        float alpha = Math.min(1.0F, vis * 1.6F);
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);

        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            float a0 = (float) (i * step);
            float a1 = (float) ((i + 1) * step);
            float x0 = cx + Mth.cos(a0) * radius;
            float z0 = cz + Mth.sin(a0) * radius;
            float x1 = cx + Mth.cos(a1) * radius;
            float z1 = cz + Mth.sin(a1) * radius;
            // Wall segment.
            buffer.addVertex(x0, baseY, z0).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x1, baseY, z1).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x1, topY, z1).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x0, topY, z0).setColor(OCC_R, OCC_G, OCC_B, alpha);
        }
        // Cone lid — blocks the view from above (vortexes get a taller spire, walls a low dome).
        float coneH = storm.height * heightScale
                * (storm.type == S2CStormStatePayload.TYPE_VORTEX ? 0.30F : 0.14F);
        float apexY = topY + coneH;
        for (int i = 0; i < segments; i++) {
            float a0 = (float) (i * step);
            float a1 = (float) ((i + 1) * step);
            float x0 = cx + Mth.cos(a0) * radius;
            float z0 = cz + Mth.sin(a0) * radius;
            float x1 = cx + Mth.cos(a1) * radius;
            float z1 = cz + Mth.sin(a1) * radius;
            buffer.addVertex(x0, topY, z0).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x1, topY, z1).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(OCC_R, OCC_G, OCC_B, alpha);
        }
    }

    /**
     * C8 opaque occluder dome of a sphere storm (never-see-inside, same guarantee as the
     * cylinder + cone lid): latitude bands at {@code r − }{@value #OCCLUDER_INSET} from the
     * below-ground skirt to the apex — no separate lid needed, the dome closes itself.
     */
    private static void buildSphereOccluder(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float vis) {
        float radius = Math.max(1.5F, storm.radius - OCCLUDER_INSET);
        float heightScale = heightScale(storm, vis);
        float alpha = Math.min(1.0F, vis * 1.6F);
        // STORM-VOL: color-only soften while the volumetric pass owns this storm's mass
        // (opacity untouched); false whenever Veil post is off / Iris is active / the
        // pipeline was evicted — the frozen near-black look is fully preserved there.
        boolean volumetric = StormVolumeFx.isVolumeStorm(storm.id);
        float occR = volumetric ? OCC_SOFT_R : OCC_R;
        float occG = volumetric ? OCC_SOFT_G : OCC_G;
        float occB = volumetric ? OCC_SOFT_B : OCC_B;
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        int segments = OCCLUDER_SEGMENTS;
        int rings = 8;
        double step = Math.PI * 2.0D / segments;
        float latSpan = (float) (Math.PI / 2.0D) + SPHERE_SKIRT_RAD;
        float latStep = latSpan / rings;
        for (int ring = 0; ring < rings; ring++) {
            float lat0 = -SPHERE_SKIRT_RAD + ring * latStep;
            float lat1 = lat0 + latStep;
            float ringR0 = Mth.cos(lat0) * radius;
            float ringR1 = Mth.cos(lat1) * radius;
            float y0 = cy + Mth.sin(lat0) * radius * heightScale;
            float y1 = cy + Mth.sin(lat1) * radius * heightScale;
            for (int i = 0; i < segments; i++) {
                float a0 = (float) (i * step);
                float a1 = (float) ((i + 1) * step);
                buffer.addVertex(cx + Mth.cos(a0) * ringR0, y0, cz + Mth.sin(a0) * ringR0)
                        .setColor(occR, occG, occB, alpha);
                buffer.addVertex(cx + Mth.cos(a1) * ringR0, y0, cz + Mth.sin(a1) * ringR0)
                        .setColor(occR, occG, occB, alpha);
                buffer.addVertex(cx + Mth.cos(a1) * ringR1, y1, cz + Mth.sin(a1) * ringR1)
                        .setColor(occR, occG, occB, alpha);
                buffer.addVertex(cx + Mth.cos(a0) * ringR1, y1, cz + Mth.sin(a0) * ringR1)
                        .setColor(occR, occG, occB, alpha);
            }
        }
    }

    // ------------------------------------------------------------------ shells

    private static void buildShells(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float partialTick, float time, boolean additivePass) {
        float vis = storm.visibility(partialTick);
        if (vis <= 0.01F) {
            return;
        }
        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dz * dz);
        // Deep inside the occluder the EXO shells are invisible anyway — the single d²
        // early-out. (Exploding storms skip it: the shockwave must stay visible from within.)
        // STORM 2.0 A5: the ENDO stack lives exactly HERE — the interior wall is a layered
        // churning mass from the other side of the occluder, not fog-only. Never during
        // EXPLODE (this branch is unreachable then — the occluder-drop pattern).
        if (storm.state != S2CStormStatePayload.STATE_EXPLODE
                && centerDist < storm.radius - OCCLUDER_INSET - 2.0D) {
            emitEndoStack(buffer, storm, camera, partialTick, time, additivePass,
                    Math.atan2(dz, dx), centerDist, vis);
            return;
        }
        float shellDist = (float) Math.abs(centerDist - storm.radius);

        // LOD crossfade weights (±LOD_FADE blocks around each boundary — smoother than a pop).
        float nearW = 1.0F - smoothstep(NEAR_LOD_END - LOD_FADE, NEAR_LOD_END + LOD_FADE, shellDist);
        float farW = smoothstep(NEAR_LOD_END - LOD_FADE, NEAR_LOD_END + LOD_FADE, shellDist)
                * (1.0F - smoothstep(FAR_LOD_END - LOD_FADE, FAR_LOD_END + LOD_FADE, shellDist));
        float impW = smoothstep(FAR_LOD_END - LOD_FADE, FAR_LOD_END + LOD_FADE, shellDist);

        boolean inside = centerDist < storm.radius;
        double camAngle = Math.atan2(dz, dx); // bearing of the camera around the storm axis
        boolean vortex = storm.type == S2CStormStatePayload.TYPE_VORTEX;
        float heightScale = heightScale(storm, vis);
        int tier = FxBudget.qualityTier();

        if (storm.type == S2CStormStatePayload.TYPE_SPHERE) {
            float boom = storm.explodeProgress(partialTick);
            updatePulse(storm);
            // STORM 2.0 EXO stack (A2): 8/5/3 nested shells by tier at near LOD, 3 at far.
            if (nearW > 0.02F || farW > 0.02F) {
                boolean near = nearW >= farW;
                float tierAlpha = Math.max(nearW, farW) * vis;
                int segments = near ? NEAR_SEGMENTS : FAR_SEGMENTS;
                int rings = near ? SPHERE_RINGS_BY_TIER[tier] : SPHERE_RINGS_FAR;
                // STORM-VOL: while the volumetric raymarch pass is live for THIS storm it
                // supplies the interior mass, so the near EXO stack thins ONE tier (the
                // volume + full stack would just multiply overdraw into mush). The gate is
                // false under Iris / veilPostFx-off / eviction — the frozen 8/5/3 ladder
                // is untouched there, and the far/impostor tiers never change.
                boolean volumetric = StormVolumeFx.isVolumeStorm(storm.id);
                int[] set = near
                        ? (tier >= 2 ? (volumetric ? EXO_NEAR_TIER1 : EXO_NEAR_TIER2)
                                : tier == 1 ? (volumetric ? EXO_NEAR_TIER0 : EXO_NEAR_TIER1)
                                : EXO_NEAR_TIER0)
                        : EXO_FAR;
                for (int k = 0; k < set.length; k++) {
                    // Painter order for the alpha sheets: deepest-first when the camera is
                    // outside, outermost-first when inside (additive is order-independent).
                    int s = inside ? set[k] : set[set.length - 1 - k];
                    if (EXO_ADDITIVE[s] != additivePass) {
                        continue;
                    }
                    if (s >= 4 && shellDist >= DEEP_SHELL_MAX_DIST) {
                        continue; // deep sheets/glows are a close-range read (fill-rate guard)
                    }
                    emitSphereShell(buffer, storm, camera, time, partialTick, s, false,
                            EXO_OFFSETS[s], additivePass, EXO_ALPHA_MUL[s], EXO_CHURN_TICKS[s],
                            EXO_GRAY_MUL[s], EXO_BAND_LEAD[s], EXO_DISP_AMP[s],
                            EXO_PULSE_DEPTH[s], segments, rings, tier, camAngle, centerDist,
                            inside, Math.PI, heightScale, tierAlpha);
                }
                if (near && boom <= 0.0F && tier >= 1) {
                    if (additivePass) {
                        // A4: 6-arm counter-rotating polar vortex crown twisting into the eye.
                        emitPolarCrown(buffer, storm, camera, time, heightScale, tierAlpha);
                    } else if (!inside) {
                        // A7: tumbling debris cross-quads orbiting the torus skirt (the
                        // orbits sit outside the wall — hidden by the occluder from inside).
                        emitDebrisOrbiters(buffer, storm, camera, time, tier, tierAlpha);
                    }
                }
            }
            if (additivePass && boom > 0.0F) {
                // FX-STORM explosion stages 3+4: glitch-dissolving wall-fragment shards on
                // the shockwave ring, then the late clear-sky bloom ring behind it.
                emitExplosionShards(buffer, storm, camera, time, partialTick);
                emitClearSkyRing(buffer, storm, camera, boom);
            }
            if (!additivePass && inside && boom <= 0.0F
                    && storm.state == S2CStormStatePayload.STATE_ACTIVE) {
                // FX-STORM: the living Tyrant flickers in the wall (ACTIVE = alive; the
                // EXPLODE death beat never draws him).
                emitTyrantSilhouette(buffer, storm, camera, time, camAngle, vis);
            }
            if (impW > 0.02F && !additivePass) {
                emitImpostor(buffer, storm, camera, time, heightScale, impW * vis, true);
            }
            return;
        }

        if (nearW > 0.02F) {
            float tierAlpha = nearW * vis;
            // A9: cylinders inherit the shell ladder (6/4/3 by tier), no strata/eye.
            int[] set = tier >= 2 ? CYL_NEAR_TIER2 : tier == 1 ? CYL_NEAR_TIER1 : CYL_NEAR_TIER0;
            for (int k = 0; k < set.length; k++) {
                int s = inside ? set[k] : set[set.length - 1 - k];
                if (SHELL_ADDITIVE[s] != additivePass) {
                    continue;
                }
                emitShell(buffer, storm, camera, time, s, NEAR_SEGMENTS, camAngle, centerDist,
                        inside, vortex, heightScale, tierAlpha, additivePass, true);
            }
            if (additivePass && vortex) {
                emitVortexCone(buffer, storm, camera, time, heightScale, tierAlpha);
            }
        }
        if (farW > 0.02F) {
            float tierAlpha = farW * vis;
            // Far tier: outer additive glow + main body shell only, no crowns.
            for (int k = 0; k < CYL_FAR.length; k++) {
                int s = CYL_FAR[k];
                if (SHELL_ADDITIVE[s] != additivePass) {
                    continue;
                }
                emitShell(buffer, storm, camera, time, s, FAR_SEGMENTS, camAngle, centerDist,
                        inside, vortex, heightScale, tierAlpha, additivePass, false);
            }
        }
        if (impW > 0.02F && !additivePass) {
            emitImpostor(buffer, storm, camera, time, heightScale, impW * vis, vortex);
        }
    }

    /** A6: caches this storm's live intra-wall flash (W-B contract) for the shell loops. */
    private static void updatePulse(StormFxClient.ClientStorm storm) {
        pulseAmt = storm.state == S2CStormStatePayload.STATE_ACTIVE
                ? StormWeatherFx.innerFlashAmount(storm.id)
                : 0.0F;
        if (pulseAmt > 0.01F) {
            pulseBearing = StormWeatherFx.innerFlashBearing(storm.id);
            pulseLat = StormWeatherFx.innerFlashLat(storm.id);
        }
    }

    /**
     * STORM 2.0 A5 — the ENDO stack, drawn only from the deep-interior branch: 3/2/1 dome
     * shells INSIDE the occluder (by quality tier) so players inside see the same layered
     * churning mass from the other side. Full 2π windows are wrong here — the arc window
     * stays camera-bearing and covers only the ~{@value #ENDO_ARC_REACH}-block fog reach.
     * The Tyrant silhouette (at occluderR − 1.5) is painter-ordered between the shells.
     * Cylinders get 2 interior shells so the vortex interior wall thickens too.
     */
    private static void emitEndoStack(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float partialTick, float time, boolean additivePass, double camAngle,
            double centerDist, float vis) {
        int tier = FxBudget.qualityTier();
        float heightScale = heightScale(storm, vis);
        if (storm.type == S2CStormStatePayload.TYPE_SPHERE) {
            updatePulse(storm);
            float[] offs = tier >= 2 ? ENDO_OFFSETS_T2 : tier == 1 ? ENDO_OFFSETS_T1 : ENDO_OFFSETS_T0;
            boolean[] adds = tier >= 2 ? ENDO_ADDITIVE_T2 : tier == 1 ? ENDO_ADDITIVE_T1 : ENDO_ADDITIVE_T0;
            float[] alphas = tier >= 2 ? ENDO_ALPHA_T2 : tier == 1 ? ENDO_ALPHA_T1 : ENDO_ALPHA_T0;
            int rings = SPHERE_RINGS_BY_TIER[tier];
            // Fog-reach gate: far from the interior wall (near the eye pit) the whole
            // stack is behind the fog clamp — emit nothing until it can actually read.
            boolean visible = storm.radius + offs[offs.length - 1] - (float) centerDist
                    < ENDO_VIEW_RANGE;
            if (!visible) {
                return;
            }
            // Painter order (camera is deep inside — larger radius = farther): shells
            // outside the silhouette radius first, then the Tyrant, then the deeper shells.
            for (int k = 0; k < offs.length; k++) {
                if (adds[k] != additivePass || offs[k] <= ENDO_SILHOUETTE_SPLIT) {
                    continue;
                }
                emitSphereShell(buffer, storm, camera, time, partialTick, k, true, offs[k],
                        additivePass, alphas[k], ENDO_CHURN_TICKS[k], ENDO_GRAY_MUL[k],
                        ENDO_BAND_LEAD[k], ENDO_DISP_AMP[k], ENDO_PULSE_DEPTH, NEAR_SEGMENTS,
                        rings, tier, camAngle, centerDist, true,
                        endoArcCap(storm.radius + offs[k]), heightScale, vis);
            }
            if (!additivePass && storm.state == S2CStormStatePayload.STATE_ACTIVE) {
                // FX-STORM: the Tyrant wall silhouette lives exactly HERE — deep interior,
                // pinned to the wall during an interior flicker.
                emitTyrantSilhouette(buffer, storm, camera, time, camAngle, vis);
            }
            for (int k = 0; k < offs.length; k++) {
                if (adds[k] != additivePass || offs[k] > ENDO_SILHOUETTE_SPLIT) {
                    continue;
                }
                emitSphereShell(buffer, storm, camera, time, partialTick, k, true, offs[k],
                        additivePass, alphas[k], ENDO_CHURN_TICKS[k], ENDO_GRAY_MUL[k],
                        ENDO_BAND_LEAD[k], ENDO_DISP_AMP[k], ENDO_PULSE_DEPTH, NEAR_SEGMENTS,
                        rings, tier, camAngle, centerDist, true,
                        endoArcCap(storm.radius + offs[k]), heightScale, vis);
            }
            return;
        }
        // Cylinder/vortex interior wall: 2 shells (1 at tier 0), same clocks and clamps.
        if (storm.radius - 6.8F - (float) centerDist >= ENDO_VIEW_RANGE) {
            return; // fog-reach gate — the interior wall cannot read from this far in
        }
        if (tier >= 1) {
            if (!additivePass) {
                emitEndoCylinder(buffer, storm, camera, time, 0, -5.6F, 0.50F, camAngle,
                        heightScale, vis);
            } else {
                emitEndoCylinder(buffer, storm, camera, time, 1, -6.8F, 0.35F, camAngle,
                        heightScale, vis);
            }
        } else if (!additivePass) {
            emitEndoCylinder(buffer, storm, camera, time, 0, -6.0F, 0.50F, camAngle,
                    heightScale, vis);
        }
    }

    /** ENDO arc half-width: the interior fog clamps reads, so cover just that arc + margin. */
    private static double endoArcCap(float endoRadius) {
        return Math.min(Math.PI, ENDO_ARC_REACH / Math.max(4.0F, endoRadius) + 0.35D);
    }

    /**
     * One cylindrical shell: full circle when inside, otherwise the camera-facing tangent arc
     * (+margin) so segment budget goes where it is seen. Alpha shells carry two height bands
     * (dense base + ragged fading top, plus a crown at near LOD for wall storms); additive
     * shells are a single band fading to zero at the top. STORM 2.0 (A9): per-shell
     * gray/alpha ladders and edge-shared {@link #fvnoise3} radial displacement (clamped so
     * the base never dips below {@code occluderR + 0.3}).
     */
    private static void emitShell(BufferBuilder buffer, StormFxClient.ClientStorm storm, Vec3 camera,
            float time, int shellIndex, int fullSegments, double camAngle, double centerDist,
            boolean inside, boolean vortex, float heightScale, float alphaMul, boolean additive,
            boolean nearTier) {
        float radius = storm.radius + SHELL_OFFSETS[shellIndex];
        if (radius < 1.0F) {
            return;
        }
        float occluderR = Math.max(1.5F, storm.radius - OCCLUDER_INSET);
        double halfArc = Math.PI;
        if (!inside) {
            halfArc = Math.min(Math.PI, Math.acos(Mth.clamp(radius / (float) centerDist, 0.0F, 1.0F)) + ARC_MARGIN);
        }
        double step = Math.PI * 2.0D / fullSegments;
        int columns = Math.min(fullSegments, (int) Math.ceil(2.0D * halfArc / step));

        // Swirl/drift rotation: vortices spin one way at staggered speeds, walls slowly shear.
        float rot = vortex
                ? time * SWIRL_RAD_PER_TICK * (0.8F + shellIndex * 0.13F)
                : time * WALL_DRIFT_RAD_PER_TICK * ((shellIndex & 1) == 0 ? 1.0F : -1.0F);
        // Layered churn: the outermost shell races, the innermost billows slowly — the
        // per-shell clock ladder is what makes the stack read as depth.
        int noiseT = (int) (time / SHELL_CHURN_TICKS[shellIndex]);

        float height = storm.height * heightScale;
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float topRadius = vortex ? Math.max(radius * 0.25F, radius - height * TAN_TILT) : radius;
        float twist = vortex ? VORTEX_TWIST : 0.0F;

        float r = additive ? ADD_R : ALPHA_R;
        float g = additive ? ADD_G : ALPHA_G;
        float b = additive ? ADD_B : ALPHA_B;
        float grayMul = SHELL_GRAY_MUL[shellIndex];
        float aMul = SHELL_ALPHA_MUL[shellIndex];
        float dispAmp = SHELL_DISP_AMP[shellIndex];
        float shellPhase = shellIndex * 1.7F;
        float dispTime = time / 24.0F;

        // Daylight contrast (EVAL-4 post-eval): widen the churn gray range so column-to-column
        // color variation survives a bright sky; at night the frozen R14 range is untouched.
        float grayFloor = 0.72F - DAY_GRAY_SPREAD * daylight;
        float graySpan = 1.0F - grayFloor;
        for (int i = 0; i < columns; i++) {
            // Window start stays camera-centered (EVAL-POL-F #1): rot lives ONLY in the noise
            // index, so the dressed slice never drifts off the camera bearing while the churn
            // pattern still scrolls with the swirl.
            double a0 = camAngle - halfArc + i * step;
            double a1 = a0 + step;
            int noiseSeg = Mth.floor((float) ((a0 + rot) / step)); // pattern moves with rot
            float churn = 0.45F + 0.55F * hash3(shellIndex, noiseSeg, noiseT);
            float churnHi = 0.45F + 0.55F * hash3(shellIndex, noiseSeg, noiseT + 7331);
            float gray0 = (grayFloor + graySpan * hash3(shellIndex + 8, noiseSeg, noiseT)) * grayMul;
            float gray1 = (grayFloor + graySpan * hash3(shellIndex + 8, noiseSeg, noiseT + 977)) * grayMul;

            // A9 displacement — edge-shared samples (a1 of column i = a0 of column i+1), so
            // adjacent columns stay watertight while each shell billows independently.
            float colC0 = (float) ((a0 + shellPhase) / step) * 0.5F;
            float colC1 = colC0 + 0.5F;
            float rB0 = Math.max(radius + (fvnoise3(0.6F, colC0, dispTime) - 0.5F) * dispAmp,
                    occluderR + 0.3F);
            float rB1 = Math.max(radius + (fvnoise3(0.6F, colC1, dispTime) - 0.5F) * dispAmp,
                    occluderR + 0.3F);
            float rT0 = Math.max(topRadius + (fvnoise3(2.6F, colC0, dispTime) - 0.5F) * dispAmp * 0.8F,
                    1.0F);
            float rT1 = Math.max(topRadius + (fvnoise3(2.6F, colC1, dispTime) - 0.5F) * dispAmp * 0.8F,
                    1.0F);

            if (additive) {
                // Single band, fading to zero at the (slightly ragged) top. In daylight the
                // additive violet is boosted — additive light washes out against a noon sky.
                float topJitter = hash3(shellIndex + 16, noiseSeg, noiseT / 2) * 4.0F;
                float aBot = 0.34F * churn * alphaMul * aMul * (1.0F + DAY_ADDITIVE_BOOST * daylight);
                emitColumnR(buffer, cx, cz, baseY, baseY + height * 1.02F + topJitter,
                        a0, a1, rB0, rB1, rT0, rT1, twist,
                        r * gray0, g * gray0, b * gray0, aBot,
                        r * gray1, g * gray1, b * gray1, 0.0F);
            } else {
                float split = height * 0.72F;
                // Night: the frozen constant 0.86 base. Day: churn carves per-column alpha
                // striping into the base band so the swirl reads instead of a flat cylinder.
                float aBase = 0.86F * alphaMul * aMul
                        * (1.0F - DAY_BASE_CARVE * daylight * (1.0F - churn));
                float aMid = 0.74F * churn * alphaMul * aMul;
                float rM0 = Mth.lerp(0.72F, rB0, rT0);
                float rM1 = Mth.lerp(0.72F, rB1, rT1);
                // Dense base band.
                emitColumnR(buffer, cx, cz, baseY, baseY + split,
                        a0, a1, rB0, rB1, rM0, rM1, twist * 0.72F,
                        r * gray0, g * gray0, b * gray0, aBase,
                        r * gray1, g * gray1, b * gray1, aMid);
                // Ragged top band, jittered rim, fades to nothing.
                float topJitter = (hash3(shellIndex + 24, noiseSeg, noiseT / 2) - 0.3F) * 6.0F;
                emitColumnR(buffer, cx, cz, baseY + split, baseY + height + topJitter,
                        a0, a1, rM0, rM1, rT0, rT1, twist,
                        r * gray1, g * gray1, b * gray1, aMid,
                        r, g, b, 0.0F);
                // Wall crown (near tier, main sheets only): torn lip leaning inward above the rim.
                if (nearTier && !vortex && shellIndex <= 2) {
                    float crownH = 3.0F + churnHi * 5.0F;
                    emitColumnR(buffer, cx, cz, baseY + height + topJitter,
                            baseY + height + topJitter + crownH,
                            a0, a1, rT0, rT1, rT0 - 3.0F, rT1 - 3.0F, 0.15F,
                            r * gray1, g * gray1, b * gray1, aMid * 0.55F,
                            r, g, b, 0.0F);
                }
                // Ground skirt dust (near tier, body shell only): a flared low-alpha band
                // where the wall meets terrain — kicked-up dust, not palette.
                if (nearTier && !vortex && shellIndex == 2) {
                    float groundY = (float) (storm.center.y - camera.y);
                    float dustJitter = hash3(shellIndex + 60, noiseSeg, noiseT / 2);
                    emitColumn(buffer, cx, cz, groundY - 1.2F, groundY + 2.6F,
                            a0, a1, radius + 2.2F + dustJitter * 0.8F, radius + 0.3F, 0.0F,
                            DUST_R, DUST_G, DUST_B, 0.40F * churn * alphaMul,
                            DUST_R, DUST_G, DUST_B, 0.0F);
                }
            }
        }
    }

    /**
     * A5/A9: one interior cylinder shell of the ENDO stack (deep-interior branch only) —
     * a camera-bearing arc window over the fog reach, churn-shaded, displacement clamped
     * to {@code occluderR − 0.3} so the occluder guarantee is untouched from inside too.
     */
    private static void emitEndoCylinder(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, int k, float radiusOffset, float baseAlpha, double camAngle,
            float heightScale, float alphaMul) {
        float occluderR = Math.max(1.5F, storm.radius - OCCLUDER_INSET);
        float re = storm.radius + radiusOffset;
        if (re < 1.0F) {
            return;
        }
        boolean additive = k == 1;
        double halfArc = endoArcCap(re);
        double step = Math.PI * 2.0D / NEAR_SEGMENTS;
        int columns = Math.min(NEAR_SEGMENTS, (int) Math.ceil(2.0D * halfArc / step));
        boolean vortex = storm.type == S2CStormStatePayload.TYPE_VORTEX;
        float rot = time * (vortex ? SWIRL_RAD_PER_TICK : WALL_DRIFT_RAD_PER_TICK)
                * ENDO_BAND_LEAD[k] * (vortex ? 1.0F : 3.0F);
        int noiseT = (int) (time / ENDO_CHURN_TICKS[k]);
        float height = storm.height * heightScale;
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float rr = additive ? ADD_R : ALPHA_R;
        float gg = additive ? ADD_G : ALPHA_G;
        float bb = additive ? ADD_B : ALPHA_B;
        float grayFloor = 0.72F - DAY_GRAY_SPREAD * daylight;
        float graySpan = 1.0F - grayFloor;
        float dispTime = time / 24.0F;
        for (int i = 0; i < columns; i++) {
            double a0 = camAngle - halfArc + i * step;
            double a1 = a0 + step;
            int noiseSeg = Mth.floor((float) ((a0 + rot) / step));
            float churn = 0.45F + 0.55F * hash3(120 + k, noiseSeg, noiseT);
            float gray0 = (grayFloor + graySpan * hash3(128 + k, noiseSeg, noiseT)) * ENDO_GRAY_MUL[k];
            float gray1 = (grayFloor + graySpan * hash3(128 + k, noiseSeg, noiseT + 977)) * ENDO_GRAY_MUL[k];
            float colC0 = (float) ((a0 + 5.1F + k * 2.3F) / step) * 0.5F;
            float colC1 = colC0 + 0.5F;
            float rA = Math.min(re + (fvnoise3(0.9F, colC0, dispTime) - 0.5F) * ENDO_DISP_AMP[k],
                    occluderR - 0.3F);
            float rB = Math.min(re + (fvnoise3(0.9F, colC1, dispTime) - 0.5F) * ENDO_DISP_AMP[k],
                    occluderR - 0.3F);
            float alpha = baseAlpha * (0.55F + 0.45F * churn) * alphaMul;
            float split = height * 0.7F;
            // Dense lower band + fading upper band (the interior read is fog-clamped anyway).
            emitColumnR(buffer, cx, cz, baseY, baseY + split,
                    a0, a1, rA, rB, rA, rB, 0.0F,
                    rr * gray0, gg * gray0, bb * gray0, alpha,
                    rr * gray1, gg * gray1, bb * gray1, alpha * 0.4F);
            emitColumnR(buffer, cx, cz, baseY + split, baseY + height,
                    a0, a1, rA, rB, rA, rB, 0.0F,
                    rr * gray1, gg * gray1, bb * gray1, alpha * 0.4F,
                    rr, gg, bb, 0.0F);
        }
    }

    /** Twisted additive swirl-cone cap of a vortex (R14 "top: swirl cone cap"). */
    private static void emitVortexCone(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float heightScale, float alphaMul) {
        int segments = 48;
        float height = storm.height * heightScale;
        float radius = Math.max(storm.radius * 0.25F, (storm.radius + 2.0F) - height * TAN_TILT);
        float coneTop = height * 0.32F;
        float apexRadius = storm.radius * 0.2F;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float baseY = (float) (storm.center.y - camera.y) + height;
        float rot = time * SWIRL_RAD_PER_TICK * 1.35F;
        int noiseT = (int) (time / 3.0F);
        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            double a0 = i * step + rot;
            double a1 = a0 + step;
            float churn = 0.4F + 0.6F * hash3(31, i, noiseT);
            float alpha = 0.30F * churn * alphaMul * (1.0F + DAY_ADDITIVE_BOOST * daylight);
            emitColumn(buffer, cx, cz, baseY, baseY + coneTop,
                    a0, a1, radius, apexRadius, 1.3F,
                    ADD_R, ADD_G, ADD_B, alpha,
                    ADD_R * 1.3F, ADD_G * 1.3F, ADD_B * 1.2F, 0.0F);
        }
        // Crown swirl collar (FX-STORM): a counter-rotating rim band under the cone so
        // the cap reads as a sheared double swirl instead of one solid spinning cone.
        float rot2 = -time * SWIRL_RAD_PER_TICK * 0.8F;
        for (int i = 0; i < segments; i++) {
            double a0 = i * step + rot2;
            double a1 = a0 + step;
            float churn = 0.4F + 0.6F * hash3(37, i, noiseT);
            float alpha = 0.20F * churn * alphaMul * (1.0F + DAY_ADDITIVE_BOOST * daylight);
            emitColumn(buffer, cx, cz, baseY - 1.0F, baseY + 2.5F,
                    a0, a1, radius + 1.5F, radius - 0.5F, -0.5F,
                    ADD_R * 0.9F, ADD_G * 0.9F, ADD_B, alpha,
                    ADD_R * 1.2F, ADD_G * 1.2F, ADD_B * 1.15F, 0.0F);
        }
    }

    /**
     * STORM 2.0 — one UV-sphere DOME shell of the volumetric stack (EXO outside the
     * occluder, ENDO inside it): latitude bands from the below-ground skirt to the apex,
     * camera-facing tangent arc when outside (same budget rule as the cylinders), and per
     * PLAN-STORM2 §W-A:
     * <ul>
     *   <li><b>A2 displacement</b> — edge-shared {@link #fvnoise3} radial billow per vertex
     *       (world-angle-indexed, continuous time), clamped against the occluder;</li>
     *   <li><b>A2 alpha-floor cull</b> — columns whose peak alpha &lt; 0.015 are skipped
     *       BEFORE the displacement noise runs (the stack is fill-rate-bound);</li>
     *   <li><b>A3 strata</b> — 4 altitude strata scale the per-ring pattern rotation
     *       (0.6/1.0/1.5/−0.8×), with brightened churning shear seams between them
     *       (pattern-index only — EVAL-POL-F #1 holds);</li>
     *   <li><b>A4 eyewall → eye</b> — {@link #eyeEnv} collapses alpha above latFrac
     *       {@value #EYEWALL_HI} so the apex opens onto the dark occluder pit, ringed by an
     *       additive eyewall rim in [{@value #EYEWALL_LO}, {@value #EYEWALL_HI}];</li>
     *   <li><b>A6 pulse</b> — the {@link StormWeatherFx} intra-wall flash lifts color toward
     *       violet-white with the depth-scaled multiplier (inner shells hardest);</li>
     *   <li><b>A8 stagger</b> — the explosion releases outer shells first
     *       ({@code boom − s·}{@value #EXPLODE_SHELL_STAGGER}), nesting the shockwaves;</li>
     *   <li><b>N·V limb law</b> (IDEAS-STORM-2 #1) — per-vertex view·normal opacity:
     *       alpha sheets thicken toward the silhouette ({@code min(2.2, 1/|N·V|)}), additive
     *       glows brighten as {@code (1−|N·V|)²} — correct from every camera angle,
     *       including top-down and inside (replaces the bearing-only rim heuristic);</li>
     *   <li><b>log-spiral rainbands</b> (IDEAS-STORM-1 #1) — 3 arms of clumpy bright cloud
     *       spiraling base → apex gate every shell's alpha (on-arm +15%, off-arm −12%);</li>
     *   <li><b>sun-side rim scatter</b> (IDEAS-STORM-1 #5) — the outer glow's silhouette
     *       burns bone-white toward the sun by day, moon-silver at night.</li>
     * </ul>
     * {@code STATE_EXPLODE} expands the dome up to {@value #EXPLODE_EXPAND} extra radii and
     * blows the palette white-hot for the first ~15 ticks while visibility fades it out.
     */
    private static void emitSphereShell(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float partialTick, int s, boolean endo, float radiusOffset,
            boolean additive, float baseAlpha, float churnTicks, float grayMul, float bandLead,
            float dispAmp, float pulseDepth, int fullSegments, int rings, int qualityTier,
            double camAngle, double centerDist, boolean inside, double halfArcCap,
            float heightScale, float alphaMul) {
        float boom = storm.explodeProgress(partialTick);
        // A8: staggered release — outer shells (small s) lead, the burst reads as 3+ nested
        // expanding shockwave shells (ENDO never draws during EXPLODE — branch condition).
        float boomS = Math.max(0.0F, boom - s * EXPLODE_SHELL_STAGGER);
        float white = storm.explodeWhite(partialTick);
        float radius = (storm.radius + radiusOffset) * explodeRadiusScale(boomS);
        if (radius < 1.0F) {
            return;
        }
        float occluderR = Math.max(1.5F, storm.radius - OCCLUDER_INSET);
        double halfArc = Math.PI;
        if (!inside && boom <= 0.0F) {
            halfArc = Math.min(Math.PI,
                    Math.acos(Mth.clamp(radius / (float) centerDist, 0.0F, 1.0F)) + ARC_MARGIN);
        }
        halfArc = Math.min(halfArc, halfArcCap);
        double step = Math.PI * 2.0D / fullSegments;
        int columns = Math.min(fullSegments, (int) Math.ceil(2.0D * halfArc / step));

        boolean nearTier = fullSegments == NEAR_SEGMENTS;
        // Lightning veins crawl only the OUTER additive glow at near tier, quality ≥ 1,
        // and never during the explosion (the shockwave owns the additive read there).
        boolean veins = additive && !endo && s == 0 && nearTier && boom <= 0.0F
                && qualityTier >= 1;
        boolean scatter = additive && !endo && s == 0 && scatterStrength > 0.005F;
        boolean pulsing = pulseAmt > 0.01F;
        int seedC = endo ? 100 + s * 3 : s;
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        int noiseT = (int) (time / churnTicks);
        float latSpan = (float) (Math.PI / 2.0D) + SPHERE_SKIRT_RAD;
        float latStep = latSpan / rings;
        float grayFloor = 0.72F - DAY_GRAY_SPREAD * daylight;
        float graySpan = 1.0F - grayFloor;
        float dayBoost = 1.0F + DAY_ADDITIVE_BOOST * daylight;
        float shellPhase = seedC * 1.7F;
        float dispTime = time / 24.0F;
        // Occluder guarantee clamps (§1): EXO never below occluderR + 0.3; ENDO never above
        // occluderR − 0.3. (During EXPLODE the expanded radius clears the clamp by itself.)
        float minR = endo ? 1.0F : occluderR + 0.3F;
        float maxR = endo ? occluderR - 0.3F : Float.MAX_VALUE;

        for (int ring = 0; ring < rings; ring++) {
            float lat0 = -SPHERE_SKIRT_RAD + ring * latStep;
            float lat1 = lat0 + latStep;
            float cosLat0 = Mth.cos(lat0);
            float sinLat0 = Mth.sin(lat0);
            float cosLat1 = Mth.cos(lat1);
            float sinLat1 = Mth.sin(lat1);
            float latFrac0 = (lat0 + SPHERE_SKIRT_RAD) / latSpan;
            float latFrac1 = (lat1 + SPHERE_SKIRT_RAD) / latSpan;
            float latMid = (latFrac0 + latFrac1) * 0.5F;
            // A4: the eye envelope (full density → eyewall → collapsed translucent apex).
            float eye0 = eyeEnv(latFrac0);
            float eye1 = eyeEnv(latFrac1);
            float ew0 = additive ? eyewallWindow(latFrac0) : 0.0F;
            float ew1 = additive ? eyewallWindow(latFrac1) : 0.0F;
            // A3: wind-band strata — the stratum scales the pattern rotation (index-only),
            // and rings that touch a stratum boundary carry the bright churning shear seam.
            int stratum = stratumAt(ring, rings);
            boolean shearRing = (ring > 0 && stratumAt(ring - 1, rings) != stratum)
                    || (ring < rings - 1 && stratumAt(ring + 1, rings) != stratum);
            float rot0 = time * SPHERE_BAND_RAD_PER_TICK * (1.0F + ring * 0.12F) * bandLead
                    * STRATUM_SPEED[stratum];
            // Band hue (additive pass): fog-green ↔ eclipse-violet, stable per band.
            float hue = hash3(seedC + 40, ring, 0);
            float bandR = Mth.lerp(hue, SPH_GREEN_R, SPH_VIOLET_R);
            float bandG = Mth.lerp(hue, SPH_GREEN_G, SPH_VIOLET_G);
            float bandB = Mth.lerp(hue, SPH_GREEN_B, SPH_VIOLET_B);

            for (int i = 0; i < columns; i++) {
                double a0 = camAngle - halfArc + i * step;
                double a1 = a0 + step;
                int noiseSeg = Mth.floor((float) ((a0 + rot0) / step)); // pattern scrolls per band
                // The two outermost EXO shells billow in coarse 2-column cells; deeper
                // sheets stay fine — widening the frequency spread between layers.
                int cell = !endo && s <= 1 ? noiseSeg >> 1 : noiseSeg;
                float churn = 0.45F + 0.55F * hash3(seedC, cell + ring * 131, noiseT);
                float gray0 = (grayFloor + graySpan * hash3(seedC + 8, cell + ring * 131, noiseT))
                        * grayMul;
                float gray1 = (grayFloor + graySpan * hash3(seedC + 8, cell + ring * 131, noiseT + 977))
                        * grayMul;
                // Log-spiral rainbands (IDEAS-STORM-1 #1): 3 arms wrap ~half a turn base →
                // apex; the phase rides the per-ring pattern rotation so the strata shear
                // ladder twists the arms naturally. Clumpy and bright ON the arm, thinner
                // and darker between arms — the satellite-photo hurricane read.
                float armPhase = fract((float) ((a0 + step * 0.5D + rot0)
                        * (RAINBAND_ARMS / (Math.PI * 2.0D))) + RAINBAND_WRAP * latMid);
                float arm = smoothstep(0.20F, 0.38F, armPhase)
                        * (1.0F - smoothstep(0.62F, 0.80F, armPhase));
                float armGate = 0.88F + 0.27F * arm;
                float churnEff = churn * (1.0F + 0.30F * arm);

                float r0;
                float g0;
                float b0;
                float aRow0;
                float aRow1;
                if (additive) {
                    r0 = bandR;
                    g0 = bandG;
                    b0 = bandB;
                    float aBand = baseAlpha * churnEff * alphaMul * dayBoost * armGate;
                    aRow0 = aBand * (1.0F - 0.45F * latFrac0) * eye0;
                    aRow1 = aBand * (1.0F - 0.45F * latFrac1) * eye1;
                    // A4: the eyewall rim ring — a steep bright collar around the eye.
                    if (ew0 > 0.0F || ew1 > 0.0F) {
                        float ew = EYEWALL_RIM_ALPHA * churn * alphaMul * dayBoost;
                        aRow0 += ew * ew0;
                        aRow1 += ew * ew1;
                    }
                    // A3: brightened churning shear seam between counter-shearing strata.
                    if (shearRing) {
                        float shearGlow = SHEAR_LINE_ALPHA * alphaMul * dayBoost
                                * fvnoise3((float) ((a0 + rot0) / step) * 0.5F,
                                        stratum * 7.7F, time / 6.0F);
                        aRow0 += shearGlow;
                        aRow1 += shearGlow;
                    }
                    // Lightning veins (FX-STORM): a gated longitude cell carries a bright
                    // head that crawls UP the latitude — animated UV crawl along the wall
                    // surface, zero extra quads (pure color/alpha modulation). The gate
                    // indexes the RAW angle (not the per-ring rotated pattern index) so a
                    // vein lines up vertically across every latitude band it crosses.
                    if (veins) {
                        int veinCell = Mth.floor((float) (a0 / step)) >> 2;
                        int veinT = (int) (time / VEIN_WINDOW_TICKS);
                        if (hash3(s + 55, veinCell, veinT) > VEIN_GATE) {
                            float head = fract(time * VEIN_CRAWL_PER_TICK
                                    + hash3(s + 56, veinCell, veinT));
                            float vein = Math.max(0.0F,
                                    1.0F - Math.abs(latMid - head) / VEIN_HALF_WIDTH);
                            vein *= vein; // sharp crawling head, soft tail
                            if (vein > 0.01F) {
                                r0 = Mth.lerp(vein, r0, 1.00F);
                                g0 = Mth.lerp(vein, g0, 0.95F);
                                b0 = Mth.lerp(vein, b0, 1.00F);
                                // Daylight boost mirrors the band alpha rule — additive
                                // veins would wash out against a noon sky otherwise.
                                float glow = 0.40F * vein * alphaMul * dayBoost;
                                aRow0 += glow;
                                aRow1 += glow;
                            }
                        }
                    }
                } else {
                    r0 = SPH_ALPHA_R;
                    g0 = SPH_ALPHA_G;
                    b0 = SPH_ALPHA_B;
                    // Day carve: churn stripes the base band so the dome never reads flat.
                    float aBase = baseAlpha * alphaMul * armGate
                            * (1.0F - DAY_BASE_CARVE * daylight * (1.0F - churnEff));
                    aRow0 = aBase * (1.0F - 0.45F * latFrac0) * eye0;
                    aRow1 = aBase * (1.0F - 0.45F * latFrac1) * eye1;
                }
                // A6: lit-from-within — the intra-wall flash (W-B) lifts the shells near
                // its (bearing, latitude) cell toward violet-white, scaled by shell depth:
                // inner EXO shells flash hardest, veiled by the outer layers. Color-only.
                if (pulsing) {
                    float db = wrapRad((float) (a0 + step * 0.5D - pulseBearing));
                    if (db > -0.5F && db < 0.5F) {
                        float dl = Math.abs(latMid - pulseLat);
                        if (dl < 0.18F) {
                            float fall = (1.0F - Math.abs(db) * 2.0F) * (1.0F - dl / 0.18F);
                            float px = pulseAmt * fall * pulseDepth;
                            float mix = Math.min(1.0F, px);
                            r0 = Mth.lerp(mix, r0, 0.82F);
                            g0 = Mth.lerp(mix, g0, 0.74F);
                            b0 = Mth.lerp(mix, b0, 1.00F);
                            if (additive) {
                                float glow = 0.5F * px;
                                aRow0 += glow;
                                aRow1 += glow;
                            }
                        }
                    }
                }
                // A2: alpha-floor column cull — the whole stack is overdraw-bound, so any
                // column that cannot reach 0.015 alpha (even limb-thickened / scatter-lifted)
                // is skipped before the displacement noise runs.
                if (Math.max(aRow0, aRow1) * (additive ? 1.35F : LIMB_MAX) < 0.015F) {
                    continue;
                }
                // A2: noise displacement — per-vertex, edge-shared (a1 of column i = a0 of
                // column i+1; lat1 of ring r = lat0 of ring r+1), so the billowing surface
                // stays watertight. Continuous time (never pops), raw-angle-indexed
                // (world-stable — EVAL-POL-F #1), clamped against the occluder.
                float colC0 = (float) ((a0 + shellPhase) / step) * 0.5F;
                float colC1 = colC0 + 0.5F;
                float lc0 = latFrac0 * 3.0F;
                float lc1 = latFrac1 * 3.0F;
                float rr00 = Mth.clamp(radius + (fvnoise3(lc0, colC0, dispTime) - 0.5F) * dispAmp, minR, maxR);
                float rr10 = Mth.clamp(radius + (fvnoise3(lc0, colC1, dispTime) - 0.5F) * dispAmp, minR, maxR);
                float rr01 = Mth.clamp(radius + (fvnoise3(lc1, colC0, dispTime) - 0.5F) * dispAmp, minR, maxR);
                float rr11 = Mth.clamp(radius + (fvnoise3(lc1, colC1, dispTime) - 0.5F) * dispAmp, minR, maxR);
                float c0 = (float) Math.cos(a0);
                float s0 = (float) Math.sin(a0);
                float c1 = (float) Math.cos(a1);
                float s1 = (float) Math.sin(a1);
                float x00 = cx + c0 * cosLat0 * rr00;
                float y00 = cy + sinLat0 * rr00 * heightScale;
                float z00 = cz + s0 * cosLat0 * rr00;
                float x10 = cx + c1 * cosLat0 * rr10;
                float y10 = cy + sinLat0 * rr10 * heightScale;
                float z10 = cz + s1 * cosLat0 * rr10;
                float x01 = cx + c0 * cosLat1 * rr01;
                float y01 = cy + sinLat1 * rr01 * heightScale;
                float z01 = cz + s0 * cosLat1 * rr01;
                float x11 = cx + c1 * cosLat1 * rr11;
                float y11 = cy + sinLat1 * rr11 * heightScale;
                float z11 = cz + s1 * cosLat1 * rr11;
                // N·V limb law (IDEAS-STORM-2 #1): per-vertex view·normal — correct from
                // every camera angle including top-down and inside (camera at origin, so
                // V is the vertex position itself).
                float nv00 = absNdotV(x00, y00, z00, cx, cy, cz);
                float nv10 = absNdotV(x10, y10, z10, cx, cy, cz);
                float nv01 = absNdotV(x01, y01, z01, cx, cy, cz);
                float nv11 = absNdotV(x11, y11, z11, cx, cy, cz);
                float f00;
                float f10;
                float f01;
                float f11;
                if (additive) {
                    // Limb BRIGHTENING (forward-scatter rim) with a floor so the face keeps
                    // its churn glow.
                    f00 = 0.30F + 0.70F * (1.0F - nv00) * (1.0F - nv00);
                    f10 = 0.30F + 0.70F * (1.0F - nv10) * (1.0F - nv10);
                    f01 = 0.30F + 0.70F * (1.0F - nv01) * (1.0F - nv01);
                    f11 = 0.30F + 0.70F * (1.0F - nv11) * (1.0F - nv11);
                } else {
                    // Limb THICKENING: the chord a view ray cuts through a thin shell is
                    // t/|N·V| — opacity diverges at the silhouette (clamped to LIMB_MAX so
                    // the rim never clips solid against the day-carve striping).
                    f00 = Math.min(LIMB_MAX, 1.0F / Math.max(nv00, LIMB_NV_FLOOR));
                    f10 = Math.min(LIMB_MAX, 1.0F / Math.max(nv10, LIMB_NV_FLOOR));
                    f01 = Math.min(LIMB_MAX, 1.0F / Math.max(nv01, LIMB_NV_FLOOR));
                    f11 = Math.min(LIMB_MAX, 1.0F / Math.max(nv11, LIMB_NV_FLOOR));
                }
                // Sun-side rim scatter (IDEAS-STORM-1 #5): the silhouette facing the sun
                // burns with a pale bone-white fringe (moon-silver at night) — additive rim
                // scatter only, never a darkening pass (navigates the prior rejection).
                if (scatter) {
                    double mid = a0 + step * 0.5D;
                    float facing = 0.5F + 0.5F * ((float) Math.cos(mid) * scatterAzX
                            + (float) Math.sin(mid) * scatterAzZ);
                    float rimRow = (f00 + f10 + f01 + f11) * 0.25F;
                    float sc = facing * scatterStrength * rimRow;
                    if (sc > 0.01F) {
                        float mix = Math.min(1.0F, sc);
                        r0 = Mth.lerp(mix, r0, scatterR);
                        g0 = Mth.lerp(mix, g0, scatterG);
                        b0 = Mth.lerp(mix, b0, scatterB);
                        float lift = 1.0F + 0.30F * sc;
                        aRow0 *= lift;
                        aRow1 *= lift;
                    }
                }
                // Explosion white-out: palette blows toward white-hot, alpha pops.
                if (white > 0.0F) {
                    r0 = Mth.lerp(white, r0, EXPLODE_WHITE_R);
                    g0 = Mth.lerp(white, g0, EXPLODE_WHITE_G);
                    b0 = Mth.lerp(white, b0, EXPLODE_WHITE_B);
                    aRow0 *= 1.0F + 1.2F * white;
                    aRow1 *= 1.0F + 1.2F * white;
                }
                // Face-darkened dense core (alpha sheets only): limb-darkening's inverse
                // read — the mass looks denser where the view ray meets it head-on.
                float m00 = additive ? 1.0F : 1.0F - 0.12F * nv00;
                float m10 = additive ? 1.0F : 1.0F - 0.12F * nv10;
                float m01 = additive ? 1.0F : 1.0F - 0.12F * nv01;
                float m11 = additive ? 1.0F : 1.0F - 0.12F * nv11;
                float a00 = Math.min(1.0F, aRow0 * f00);
                float a10 = Math.min(1.0F, aRow0 * f10);
                float a01 = Math.min(1.0F, aRow1 * f01);
                float a11 = Math.min(1.0F, aRow1 * f11);
                buffer.addVertex(x00, y00, z00)
                        .setColor(r0 * gray0 * m00, g0 * gray0 * m00, b0 * gray0 * m00, a00);
                buffer.addVertex(x10, y10, z10)
                        .setColor(r0 * gray0 * m10, g0 * gray0 * m10, b0 * gray0 * m10, a10);
                buffer.addVertex(x11, y11, z11)
                        .setColor(r0 * gray1 * m11, g0 * gray1 * m11, b0 * gray1 * m11, a11);
                buffer.addVertex(x01, y01, z01)
                        .setColor(r0 * gray1 * m01, g0 * gray1 * m01, b0 * gray1 * m01, a01);
                // A7 debris torus (body shell, equator ring, near tier): the old dust band
                // plus a second band flaring UP-and-out — a stacked two-lip torus where the
                // dome grinds the terrain, both alpha-jittered by the value noise.
                if (!endo && !additive && s == 3 && nearTier && ring == 0 && boom <= 0.0F) {
                    float dustJitter = hash3(seedC + 60, noiseSeg, noiseT / 2);
                    float fvLow = fvnoise3(colC0, 7.7F, time / 18.0F);
                    emitColumn(buffer, cx, cz, cy - 1.2F, cy + 2.6F,
                            a0, a1, radius + 2.2F + dustJitter * 0.8F, radius + 0.3F, 0.0F,
                            DUST_R, DUST_G, DUST_B,
                            0.40F * churn * alphaMul * (0.55F + 0.90F * fvLow),
                            DUST_R, DUST_G, DUST_B, 0.0F);
                    float fvHigh = fvnoise3(colC0 + 31.7F, 9.3F, time / 18.0F);
                    emitColumn(buffer, cx, cz, cy + 2.2F, cy + 4.6F,
                            a0, a1, radius + 0.3F, radius + 2.6F, 0.0F,
                            DUST_R * 1.1F, DUST_G * 1.1F, DUST_B * 1.1F,
                            0.30F * churn * alphaMul * (0.55F + 0.90F * fvHigh),
                            DUST_R, DUST_G, DUST_B, 0.0F);
                }
            }
        }
    }

    /**
     * A4: the polar vortex crown — {@value #CROWN_ARMS} additive spiral arms ×
     * {@value #CROWN_SEGS} segments (48 quads) twisting from latFrac 0.85 into the apex,
     * counter-rotating at {@value #CROWN_SPEED_MUL}× the base band speed, violet base →
     * violet-white tips. Near tier, quality ≥ 1, never during EXPLODE (caller gates).
     */
    private static void emitPolarCrown(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float heightScale, float alphaMul) {
        float radius = storm.radius + 0.6F;
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        float latSpan = (float) (Math.PI / 2.0D) + SPHERE_SKIRT_RAD;
        double rot = time * SPHERE_BAND_RAD_PER_TICK * CROWN_SPEED_MUL;
        int noiseT = (int) (time / 5.0F);
        float dayBoost = 1.0F + DAY_ADDITIVE_BOOST * daylight;
        for (int arm = 0; arm < CROWN_ARMS; arm++) {
            double phi = arm * (Math.PI * 2.0D / CROWN_ARMS) + rot;
            for (int j = 0; j <= CROWN_SEGS; j++) {
                float t = j / (float) CROWN_SEGS;
                float lat = (0.85F + 0.15F * t) * latSpan - SPHERE_SKIRT_RAD;
                double bearing = phi + t * 3.4D; // winds ~half a turn into the apex
                float ringR = Mth.cos(lat) * radius;
                CROWN_PTS[j * 3] = cx + (float) Math.cos(bearing) * ringR;
                CROWN_PTS[j * 3 + 1] = cy + Mth.sin(lat) * radius * heightScale;
                CROWN_PTS[j * 3 + 2] = cz + (float) Math.sin(bearing) * ringR;
            }
            float churn = 0.55F + 0.45F * hash3(97, arm, noiseT);
            for (int j = 0; j < CROWN_SEGS; j++) {
                float t = j / (float) CROWN_SEGS;
                float ax = CROWN_PTS[j * 3];
                float ay = CROWN_PTS[j * 3 + 1];
                float az = CROWN_PTS[j * 3 + 2];
                float bx = CROWN_PTS[j * 3 + 3];
                float by = CROWN_PTS[j * 3 + 4];
                float bz = CROWN_PTS[j * 3 + 5];
                float dxs = bx - ax;
                float dys = by - ay;
                float dzs = bz - az;
                // Camera-facing side vector (emitRibbon math — camera at origin).
                float mx = (ax + bx) * 0.5F;
                float my = (ay + by) * 0.5F;
                float mz = (az + bz) * 0.5F;
                float sx = dys * mz - dzs * my;
                float sy = dzs * mx - dxs * mz;
                float sz = dxs * my - dys * mx;
                float sLen = Mth.sqrt(sx * sx + sy * sy + sz * sz);
                if (sLen < 1.0E-4F) {
                    continue;
                }
                float halfW = Mth.lerp(t, 0.9F, 0.15F) / sLen; // taper into the eye
                sx *= halfW;
                sy *= halfW;
                sz *= halfW;
                // Violet base → violet-white tip.
                float rC = Mth.lerp(t, SPH_VIOLET_R, 0.85F);
                float gC = Mth.lerp(t, SPH_VIOLET_G, 0.80F);
                float bC = Mth.lerp(t, SPH_VIOLET_B, 1.00F);
                float alpha = 0.38F * churn * alphaMul * dayBoost * (0.5F + 0.5F * t);
                buffer.addVertex(ax - sx, ay - sy, az - sz).setColor(rC, gC, bC, alpha);
                buffer.addVertex(ax + sx, ay + sy, az + sz).setColor(rC, gC, bC, alpha);
                buffer.addVertex(bx + sx, by + sy, bz + sz).setColor(rC, gC, bC, alpha);
                buffer.addVertex(bx - sx, by - sy, bz - sz).setColor(rC, gC, bC, alpha);
            }
        }
    }

    /**
     * A7: tumbling debris cross-quads on stateless hash orbits around the torus skirt —
     * {@value #TORUS_DEBRIS_FULL} at tier 2 ({@value #TORUS_DEBRIS_REDUCED} reduced), each
     * fully derived from {@code (i, time)}: prograde orbit, sinus bob, size/tumble shimmer.
     * Near tier only; the far side hides behind the depth-written occluder for free.
     */
    private static void emitDebrisOrbiters(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, int qualityTier, float alphaMul) {
        int count = qualityTier >= 2 ? TORUS_DEBRIS_FULL : TORUS_DEBRIS_REDUCED;
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        for (int i = 0; i < count; i++) {
            float h1 = hash3(i, 71, 5);
            float h2 = hash3(i, 73, 9);
            float h3 = hash3(i, 79, 11);
            float h4 = hash3(i, 83, 13);
            double bearing = h1 * (Math.PI * 2.0D) + time * (0.03F + 0.02F * h2);
            float rad = storm.radius + 0.5F + 2.5F * h3;
            float y = cy + 0.5F + 3.0F * h4 + 0.6F * Mth.sin(time * 0.07F + i * 2.7F);
            float x = cx + (float) Math.cos(bearing) * rad;
            float z = cz + (float) Math.sin(bearing) * rad;
            float size = (0.5F + 0.6F * hash3(i, 89, 17))
                    * (0.75F + 0.25F * Mth.sin(time * 0.23F + i * 1.9F)); // tumble shimmer
            emitCrossFlash(buffer, x, y, z, size,
                    DUST_R * 1.4F, DUST_G * 1.4F, DUST_B * 1.4F, 0.55F * alphaMul);
        }
    }

    /**
     * FX-STORM stage curve of the C8 burst: a {@value #EXPLODE_PINCH}-deep implosion pinch
     * over the first {@value #EXPLODE_IMPLODE_FRAC} of the burst (releasing right after),
     * then an eased (t²) expansion out to {@code 1 + }{@value #EXPLODE_EXPAND} radii.
     * Package-visible (STORM-VOL): {@link StormVolumeFx} expands the raymarched bounds on
     * the SAME curve (raw boom = the outermost shell's stagger) during EXPLODE.
     */
    static float explodeRadiusScale(float boom) {
        if (boom <= 0.0F) {
            return 1.0F;
        }
        float pinch = EXPLODE_PINCH * smoothstep(0.0F, EXPLODE_IMPLODE_FRAC, boom)
                * (1.0F - smoothstep(EXPLODE_IMPLODE_FRAC, EXPLODE_IMPLODE_FRAC * 2.2F, boom));
        float expand = expandT(boom);
        return 1.0F - pinch + EXPLODE_EXPAND * expand * expand;
    }

    /** Expansion progress 0..1 of the post-implosion part of the burst. */
    private static float expandT(float boom) {
        return boom <= EXPLODE_IMPLODE_FRAC ? 0.0F
                : (boom - EXPLODE_IMPLODE_FRAC) / (1.0F - EXPLODE_IMPLODE_FRAC);
    }

    /**
     * FX-STORM explosion stage 3: wall-fragment shards riding the shockwave ring — up to
     * {@value #EXPLODE_SHARDS_FULL} cross-flash quad pairs ({@value #EXPLODE_SHARDS_REDUCED}
     * under reducedFx) flying outward slightly faster than the shell, shrinking as they go,
     * and dissolving as GLITCH VOXELS: a per-shard hash gate drops shards out for 2-tick
     * frame pairs with odds that rise with the expansion, so the debris field strobes apart
     * instead of fading.
     */
    private static void emitExplosionShards(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float partialTick) {
        float expand = expandT(storm.explodeProgress(partialTick));
        if (expand <= 0.0F || expand >= 1.0F) {
            return;
        }
        float white = storm.explodeWhite(partialTick);
        int shards = FxBudget.qualityTier() >= 2 ? EXPLODE_SHARDS_FULL : EXPLODE_SHARDS_REDUCED;
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        int flickerT = (int) (time / 2.0F);
        for (int i = 0; i < shards; i++) {
            if (hash3(i, flickerT, 977) < expand * 0.85F) {
                continue; // glitch-voxel dropout — odds rise as the shard dissolves
            }
            float bearing = hash3(i, 13, 7) * (float) (Math.PI * 2.0D);
            float lat = hash3(i, 29, 3) * 0.9F;
            float speed = 0.8F + 0.5F * hash3(i, 41, 11);
            float dist = storm.radius * (1.0F + (EXPLODE_EXPAND + 0.6F) * expand * speed);
            float x = cx + Mth.cos(bearing) * dist;
            float y = cy + Mth.sin(lat) * dist * 0.35F + 1.5F;
            float z = cz + Mth.sin(bearing) * dist;
            float size = (1.1F + 1.6F * hash3(i, 53, 17)) * (1.0F - 0.7F * expand);
            float hue = hash3(i, 61, 23);
            float r = Mth.lerp(white, Mth.lerp(hue, SPH_GREEN_R, SPH_VIOLET_R), EXPLODE_WHITE_R);
            float g = Mth.lerp(white, Mth.lerp(hue, SPH_GREEN_G, SPH_VIOLET_G), EXPLODE_WHITE_G);
            float b = Mth.lerp(white, Mth.lerp(hue, SPH_GREEN_B, SPH_VIOLET_B), EXPLODE_WHITE_B);
            emitCrossFlash(buffer, x, y, z, size, r, g, b, 0.85F * (1.0F - expand));
        }
    }

    /**
     * FX-STORM explosion stage 4: the clear-sky bloom moment — a thin pale additive ring
     * hugging the ground just behind the shockwave over the last stretch of the burst,
     * fading out as the burst completes and the sky opens.
     */
    private static void emitClearSkyRing(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float boom) {
        float expand = expandT(boom);
        float bloom = smoothstep(0.60F, 0.85F, expand) * (1.0F - smoothstep(0.85F, 1.0F, expand));
        if (bloom <= 0.02F) {
            return;
        }
        float ringR = storm.radius * (1.0F + (EXPLODE_EXPAND + 0.3F) * expand);
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        int segments = OCCLUDER_SEGMENTS;
        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            double a0 = i * step;
            double a1 = a0 + step;
            emitColumn(buffer, cx, cz, cy + 0.2F, cy + 3.2F,
                    a0, a1, ringR, ringR + 1.2F, 0.0F,
                    0.85F, 0.88F, 0.95F, 0.30F * bloom,
                    0.85F, 0.88F, 0.95F, 0.0F);
        }
    }

    /**
     * FX-STORM: the distant Tyrant flickering in the wall while he is alive. Interior-only
     * (drawn against the occluder — the never-see-inside guarantee is untouched), ACTIVE
     * sphere storms only, and only while a {@link StormInteriorFx#flash} silhouette flicker
     * is live: a ~7.5-block dark humanoid cutout (4 quads) pinned to the inner wall at a
     * per-flicker hash bearing near the camera bearing, hash-strobed so he is only there
     * on SOME frames of the flicker — gone when the fog closes again.
     */
    private static void emitTyrantSilhouette(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, double camAngle, float vis) {
        float flash = StormInteriorFx.flashAmount();
        if (flash <= 0.05F || vis < 0.8F) {
            return;
        }
        int serial = StormInteriorFx.flashSerial();
        if (hash3((int) (time / 2.0F), serial, 5) < 0.30F) {
            return; // strobe dropout: he is not there every frame
        }
        double bearing = camAngle + (hash3(serial, 91, 7) - 0.5F) * 1.6D;
        float dist = Math.max(4.0F, storm.radius - OCCLUDER_INSET - 1.5F);
        float bx = (float) (storm.center.x - camera.x) + (float) Math.cos(bearing) * dist;
        float bz = (float) (storm.center.z - camera.z) + (float) Math.sin(bearing) * dist;
        float by = (float) (storm.center.y - camera.y);
        // Wall-tangent axis: the cutout spans along the wall like a shadow cast onto it.
        float tx = -(float) Math.sin(bearing);
        float tz = (float) Math.cos(bearing);
        float sway = Mth.sin(time * 0.11F + serial) * 0.4F;
        float alpha = 0.85F * flash;
        // Legs, torso (swaying), shoulder spikes, head — deliberately wrong proportions.
        silQuad(buffer, bx, by, bz, tx, tz, 0.9F, 0.8F, 3.4F, 0.0F, alpha);
        silQuad(buffer, bx, by + 3.2F, bz, tx, tz, 1.1F, 1.5F, 2.9F, sway, alpha);
        silQuad(buffer, bx, by + 5.6F, bz, tx, tz, 2.4F, 1.7F, 0.8F, sway, alpha);
        silQuad(buffer, bx, by + 6.3F, bz, tx, tz, 0.55F, 0.5F, 1.2F, sway * 1.3F, alpha);
    }

    /** One vertical silhouette quad along the wall-tangent axis (bottom/top half-widths). */
    private static void silQuad(BufferBuilder buffer, float x, float y0, float z,
            float tx, float tz, float halfW0, float halfW1, float height, float shift, float alpha) {
        float x0 = x + tx * shift;
        float z0 = z + tz * shift;
        buffer.addVertex(x0 - tx * halfW0, y0, z0 - tz * halfW0).setColor(SIL_R, SIL_G, SIL_B, alpha);
        buffer.addVertex(x0 + tx * halfW0, y0, z0 + tz * halfW0).setColor(SIL_R, SIL_G, SIL_B, alpha);
        buffer.addVertex(x0 + tx * halfW1, y0 + height, z0 + tz * halfW1).setColor(SIL_R, SIL_G, SIL_B, alpha);
        buffer.addVertex(x0 - tx * halfW1, y0 + height, z0 - tz * halfW1).setColor(SIL_R, SIL_G, SIL_B, alpha);
    }

    /** Impostor ring + lid for storms beyond {@value #FAR_LOD_END} blocks (8 columns, dark). */
    private static void emitImpostor(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float heightScale, float alphaMul, boolean vortex) {
        int segments = IMPOSTOR_SEGMENTS;
        float radius = storm.radius;
        float height = storm.height * heightScale;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        int noiseT = (int) (time / 6.0F);
        float topRadius = vortex ? radius * 0.6F : radius;
        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            double a0 = i * step;
            double a1 = a0 + step;
            float churn = 0.7F + 0.3F * hash3(40, i, noiseT);
            float alpha = 0.85F * alphaMul;
            emitColumn(buffer, cx, cz, baseY, baseY + height,
                    a0, a1, radius, topRadius, 0.0F,
                    ALPHA_R * churn, ALPHA_G * churn, ALPHA_B * churn, alpha,
                    ALPHA_R, ALPHA_G, ALPHA_B, alpha * 0.35F);
            // Lid wedge toward the axis so the interior stays hidden from high vantage points.
            float x0 = cx + (float) Math.cos(a0) * topRadius;
            float z0 = cz + (float) Math.sin(a0) * topRadius;
            float x1 = cx + (float) Math.cos(a1) * topRadius;
            float z1 = cz + (float) Math.sin(a1) * topRadius;
            float lidY = baseY + height;
            float apexY = lidY + height * 0.12F;
            buffer.addVertex(x0, lidY, z0).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
            buffer.addVertex(x1, lidY, z1).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
        }
    }

    /** One vertical wall column quad between two angles, with independent bottom/top styling. */
    private static void emitColumn(BufferBuilder buffer, float cx, float cz, float y0, float y1,
            double a0, double a1, float radius0, float radius1, float twist,
            float r0, float g0, float b0, float alpha0,
            float r1, float g1, float b1, float alpha1) {
        emitColumnR(buffer, cx, cz, y0, y1, a0, a1, radius0, radius0, radius1, radius1, twist,
                r0, g0, b0, alpha0, r1, g1, b1, alpha1);
    }

    /**
     * One vertical wall column quad with per-edge radii (STORM 2.0: noise-displaced cylinder
     * shells need independent left/right edge radii so adjacent columns stay watertight).
     * {@code r00/r10} = bottom left/right, {@code r01/r11} = top left/right.
     */
    private static void emitColumnR(BufferBuilder buffer, float cx, float cz, float y0, float y1,
            double a0, double a1, float r00, float r10, float r01, float r11, float twist,
            float r0, float g0, float b0, float alpha0,
            float r1, float g1, float b1, float alpha1) {
        float x00 = cx + (float) Math.cos(a0) * r00;
        float z00 = cz + (float) Math.sin(a0) * r00;
        float x10 = cx + (float) Math.cos(a1) * r10;
        float z10 = cz + (float) Math.sin(a1) * r10;
        float x01 = cx + (float) Math.cos(a0 + twist) * r01;
        float z01 = cz + (float) Math.sin(a0 + twist) * r01;
        float x11 = cx + (float) Math.cos(a1 + twist) * r11;
        float z11 = cz + (float) Math.sin(a1 + twist) * r11;
        buffer.addVertex(x00, y0, z00).setColor(r0, g0, b0, alpha0);
        buffer.addVertex(x10, y0, z10).setColor(r0, g0, b0, alpha0);
        buffer.addVertex(x11, y1, z11).setColor(r1, g1, b1, alpha1);
        buffer.addVertex(x01, y1, z01).setColor(r1, g1, b1, alpha1);
    }

    // ------------------------------------------------------------------ lightning ribbons

    /**
     * A jittered ribbon bolt: {@value #BOLT_SUB_SEGMENTS} camera-facing sub-segments, re-seeded
     * every 2 ticks, white core for the first {@value #BOLT_CORE_TICKS} ticks then violet
     * decay; sky strikes add an outer glow layer + impact cross flash (≤ 14 quads total).
     */
    private static void buildBolt(BufferBuilder buffer, StormFxClient.Bolt bolt, Vec3 camera,
            float partialTick) {
        int life = bolt.arc ? StormFxClient.ARC_LIFE_TICKS : StormFxClient.BOLT_LIFE_TICKS;
        float age = StormFxClient.ticks() + partialTick - bolt.startTick;
        if (age >= life) {
            return;
        }
        float lifeFrac = age / life;
        boolean core = age < BOLT_CORE_TICKS;
        int jitterFrame = (int) (age / 2.0F);

        // Build the jittered polyline into the shared scratch (camera-relative floats).
        float fx = (float) (bolt.from.x - camera.x);
        float fy = (float) (bolt.from.y - camera.y);
        float fz = (float) (bolt.from.z - camera.z);
        float tx = (float) (bolt.to.x - camera.x);
        float ty = (float) (bolt.to.y - camera.y);
        float tz = (float) (bolt.to.z - camera.z);
        float dxT = tx - fx;
        float dyT = ty - fy;
        float dzT = tz - fz;
        float len = Mth.sqrt(dxT * dxT + dyT * dyT + dzT * dzT);
        if (len < 0.01F) {
            return;
        }
        // Two axes perpendicular to the strike direction for the jitter plane.
        float ux;
        float uy;
        float uz;
        if (Math.abs(dyT) > 0.9F * len) {
            ux = 1.0F;
            uy = 0.0F;
            uz = 0.0F;
        } else {
            ux = 0.0F;
            uy = 1.0F;
            uz = 0.0F;
        }
        // v = normalize(dir × u), u' = normalize(dir × v)
        float vx = (dyT * uz - dzT * uy) / len;
        float vy = (dzT * ux - dxT * uz) / len;
        float vz = (dxT * uy - dyT * ux) / len;
        float vLen = Math.max(1.0E-4F, Mth.sqrt(vx * vx + vy * vy + vz * vz));
        vx /= vLen;
        vy /= vLen;
        vz /= vLen;
        float wx = (dyT * vz - dzT * vy) / len;
        float wy = (dzT * vx - dxT * vz) / len;
        float wz = (dxT * vy - dyT * vx) / len;

        float amp = len * (bolt.arc ? 0.10F : 0.055F) * (1.0F + bolt.intensity * 0.5F);
        int seedBase = (int) (bolt.seed ^ (bolt.seed >>> 32)) + jitterFrame * 7919;
        for (int j = 0; j <= BOLT_SUB_SEGMENTS; j++) {
            float t = j / (float) BOLT_SUB_SEGMENTS;
            float envelope = 4.0F * t * (1.0F - t); // pinned at both endpoints
            float o1 = (hashF(seedBase, j * 2) - 0.5F) * 2.0F * amp * envelope;
            float o2 = (hashF(seedBase, j * 2 + 1) - 0.5F) * 2.0F * amp * envelope;
            BOLT_PTS[j * 3] = fx + dxT * t + vx * o1 + wx * o2;
            BOLT_PTS[j * 3 + 1] = fy + dyT * t + vy * o1 + wy * o2;
            BOLT_PTS[j * 3 + 2] = fz + dzT * t + vz * o1 + wz * o2;
        }

        float decay = 1.0F - Math.max(0.0F, (age - BOLT_CORE_TICKS) / (float) (life - BOLT_CORE_TICKS));
        // Daylight widening (EVAL-4 post-eval): additive ribbons lose apparent brightness
        // against a noon sky, so bolts trade a little width for the lost punch.
        float dayWiden = 1.0F + DAY_BOLT_WIDEN * daylight;
        if (bolt.arc) {
            float width = (0.10F + 0.22F * bolt.intensity) * dayWiden;
            float alpha = 0.8F * (1.0F - lifeFrac);
            emitRibbon(buffer, width, 0.85F, 0.72F, 1.0F, alpha);
        } else {
            // Outer violet glow layer (daylight also lifts its alpha — it carries the sky read).
            float coreWidth = (0.28F + 0.6F * bolt.intensity) * (core ? 1.0F : 0.55F + 0.45F * decay)
                    * dayWiden;
            float glowAlpha = (core ? 0.55F : 0.42F * decay) * (1.0F + 0.35F * daylight);
            emitRibbon(buffer, coreWidth * 2.6F, 0.62F, 0.42F, 1.0F, Math.min(0.8F, glowAlpha));
            // Core: white while hot, violet-white while decaying.
            float cr = core ? 1.0F : 0.88F;
            float cg = core ? 1.0F : 0.74F;
            emitRibbon(buffer, coreWidth, cr, cg, 1.0F, core ? 0.95F : 0.7F * decay);
            // Impact cross flash.
            float flashLife = Math.min(1.0F, age / 4.0F);
            float flashSize = (2.5F + 6.5F * bolt.intensity) * (1.0F - flashLife);
            if (flashSize > 0.05F) {
                emitCrossFlash(buffer, tx, ty + 0.5F, tz, flashSize, 0.9F, 0.8F, 1.0F,
                        0.75F * (1.0F - flashLife));
            }
        }
    }

    /** Camera-facing ribbon along the scratch polyline (one quad per sub-segment). */
    private static void emitRibbon(BufferBuilder buffer, float halfWidth,
            float r, float g, float b, float alpha) {
        if (alpha <= 0.01F) {
            return;
        }
        for (int j = 0; j < BOLT_SUB_SEGMENTS; j++) {
            float ax = BOLT_PTS[j * 3];
            float ay = BOLT_PTS[j * 3 + 1];
            float az = BOLT_PTS[j * 3 + 2];
            float bx = BOLT_PTS[j * 3 + 3];
            float by = BOLT_PTS[j * 3 + 4];
            float bz = BOLT_PTS[j * 3 + 5];
            float dx = bx - ax;
            float dy = by - ay;
            float dz = bz - az;
            // Camera at origin (camera-relative): view dir to the segment midpoint IS the midpoint.
            float mx = (ax + bx) * 0.5F;
            float my = (ay + by) * 0.5F;
            float mz = (az + bz) * 0.5F;
            // side = normalize(segment × toCamera) * halfWidth
            float sx = dy * mz - dz * my;
            float sy = dz * mx - dx * mz;
            float sz = dx * my - dy * mx;
            float sLen = Mth.sqrt(sx * sx + sy * sy + sz * sz);
            if (sLen < 1.0E-4F) {
                continue;
            }
            float scale = halfWidth / sLen;
            sx *= scale;
            sy *= scale;
            sz *= scale;
            buffer.addVertex(ax - sx, ay - sy, az - sz).setColor(r, g, b, alpha);
            buffer.addVertex(ax + sx, ay + sy, az + sz).setColor(r, g, b, alpha);
            buffer.addVertex(bx + sx, by + sy, bz + sz).setColor(r, g, b, alpha);
            buffer.addVertex(bx - sx, by - sy, bz - sz).setColor(r, g, b, alpha);
        }
    }

    /** Two crossed vertical quads at the impact point (cheap omnidirectional flash). */
    private static void emitCrossFlash(BufferBuilder buffer, float x, float y, float z,
            float size, float r, float g, float b, float alpha) {
        buffer.addVertex(x - size, y - size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x + size, y - size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x + size, y + size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x - size, y + size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x, y - size, z - size).setColor(r, g, b, alpha);
        buffer.addVertex(x, y - size, z + size).setColor(r, g, b, alpha);
        buffer.addVertex(x, y + size, z + size).setColor(r, g, b, alpha);
        buffer.addVertex(x, y + size, z - size).setColor(r, g, b, alpha);
    }

    // ------------------------------------------------------------------ draw + helpers

    private static void draw(BufferBuilder buffer, boolean additive, boolean depthWrite) {
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
        }
        RenderSystem.enableBlend();
        if (additive) {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        } else {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                    GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        }
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(depthWrite);
        BufferUploader.drawWithShader(mesh);
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
    }

    /**
     * SPAWN grows the wall out of the ground; DISSIPATE stretches it upward as it thins.
     * Package-visible (STORM-VOL): {@link StormVolumeFx} feeds the same law as the
     * {@code VolYScale} uniform so the raymarched ellipsoid tracks the shell dome exactly.
     */
    static float heightScale(StormFxClient.ClientStorm storm, float visibility) {
        if (storm.state == S2CStormStatePayload.STATE_DISSIPATE) {
            return 1.0F + 0.3F * (1.0F - visibility);
        }
        if (storm.state == S2CStormStatePayload.STATE_EXPLODE) {
            return 1.0F; // C8: the shockwave expands radially; no vertical stretch
        }
        return 0.25F + 0.75F * visibility;
    }

    /** Cheap 3-int hash in [0,1) — the churn noise (BorderFxRenderer.flicker pattern). */
    private static float hash3(int a, int b, int c) {
        int h = a * 668265261 ^ b * 374761393 ^ c * 0x85EBCA77;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0xFFFF) / 65536.0F;
    }

    private static float hashF(int seed, int index) {
        return hash3(seed, index * 31 + 17, seed >>> 8);
    }

    /**
     * A1: smoothed 3D value noise — trilinear interpolation of {@link #hash3} at the 8
     * surrounding integer lattice points with smoothstep fades. Pure math, no state, no
     * allocation. The displacement/organics workhorse of the STORM 2.0 shell stack.
     */
    private static float fvnoise3(float a, float b, float c) {
        int ia = Mth.floor(a);
        int ib = Mth.floor(b);
        int ic = Mth.floor(c);
        float fa = a - ia;
        float fb = b - ib;
        float fc = c - ic;
        fa = fa * fa * (3.0F - 2.0F * fa);
        fb = fb * fb * (3.0F - 2.0F * fb);
        fc = fc * fc * (3.0F - 2.0F * fc);
        float n00 = Mth.lerp(fa, hash3(ia, ib, ic), hash3(ia + 1, ib, ic));
        float n10 = Mth.lerp(fa, hash3(ia, ib + 1, ic), hash3(ia + 1, ib + 1, ic));
        float n01 = Mth.lerp(fa, hash3(ia, ib, ic + 1), hash3(ia + 1, ib, ic + 1));
        float n11 = Mth.lerp(fa, hash3(ia, ib + 1, ic + 1), hash3(ia + 1, ib + 1, ic + 1));
        return Mth.lerp(fc, Mth.lerp(fb, n00, n10), Mth.lerp(fb, n01, n11));
    }

    /**
     * A4: the eyewall → eye density envelope — full density up to latFrac
     * {@value #EYE_START}, smoothstep down to 0.35 at {@value #EYEWALL_HI}, then a tight
     * ×{@value #EYE_COLLAPSE} collapse: the apex opens into a translucent eye whose "pit"
     * is the dark occluder dome showing through (depth for free, guarantee untouched).
     */
    private static float eyeEnv(float latFrac) {
        float env = 1.0F - 0.65F * smoothstep(EYE_START, EYEWALL_HI, latFrac);
        return env * (1.0F - (1.0F - EYE_COLLAPSE) * smoothstep(EYEWALL_HI, 0.985F, latFrac));
    }

    /** A4: the additive eyewall rim window over latFrac [{@value #EYEWALL_LO}, {@value #EYEWALL_HI}]. */
    private static float eyewallWindow(float latFrac) {
        return smoothstep(EYEWALL_LO - 0.02F, EYEWALL_LO + 0.05F, latFrac)
                * (1.0F - smoothstep(EYEWALL_HI - 0.02F, EYEWALL_HI + 0.005F, latFrac));
    }

    /** A3: ring → wind-band stratum (master 12-ring table, rescaled to the live ring count). */
    private static int stratumAt(int ring, int rings) {
        return STRATUM_OF_RING[ring * 12 / rings];
    }

    /** N·V limb law: |dot(view, normal)| at a camera-relative vertex (camera at origin). */
    private static float absNdotV(float x, float y, float z, float cx, float cy, float cz) {
        float nx = x - cx;
        float ny = y - cy;
        float nz = z - cz;
        float nLen = Mth.sqrt(nx * nx + ny * ny + nz * nz);
        float vLen = Mth.sqrt(x * x + y * y + z * z);
        float denom = nLen * vLen;
        if (denom < 1.0E-3F) {
            return 1.0F;
        }
        return Math.abs((nx * x + ny * y + nz * z) / denom);
    }

    /** Wraps an angle to [−π, π] without branches or loops. */
    private static float wrapRad(float a) {
        float t = a * INV_TWO_PI + 0.5F;
        return (t - Mth.floor(t) - 0.5F) * TWO_PI;
    }

    private static float fract(float x) {
        return x - Mth.floor(x);
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }
}
