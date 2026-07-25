package dev.projecteclipse.eclipse.stormfx;

import java.util.List;

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
 * STORM 2.0 W-B (PLAN-STORM2 §W-B): the weather EMBEDDED inside the storm mass — geometry
 * half of the weather-in-the-mass package ({@link StormWeatherFx} owns tick/state). Own
 * {@link RenderLevelStageEvent} subscription at {@code AFTER_PARTICLES}, same renderer law
 * as {@link StormWallRenderer}: camera-relative {@code POSITION_COLOR} +
 * {@link BufferUploader#drawWithShader}, zero textures, zero per-frame heap allocations,
 * no Iris gate, zero Quasar spend.
 *
 * <p><b>Everything here draws in ONE ADDITIVE pass</b> (§W-B header rule): additive
 * blending is order-independent, so listener order vs. W-A's alpha pass can never produce
 * sort seams. Any future alpha-blended weather must move into {@code StormWallRenderer}'s
 * file instead (§7 risk 3 — noted in both class javadocs).</p>
 *
 * <p>Layers (all near-LOD only, {@code shellDist < }{@value #NEAR_RANGE}; §5 tier ladder
 * drops clumps → curtains → ribbons in that order as quality falls):</p>
 * <ul>
 *   <li><b>B2 bolt ribbons</b> — during a {@link StormWeatherFx} flash, 1–2 jittered
 *       ribbons + forks (2–4 strands) arcing radially INWARD between the shell radii
 *       (r+2 → r−4) so W-A's outer shells veil them; core + glow, ≤ 14 quads per ribbon,
 *       ≤ 28 per flash. Tier 2 only.</li>
 *   <li><b>B3 rain curtains</b> — 3 inter-shell radii {r+1.5, r−0.8, r−3.0} (between the
 *       frozen EXO shell radius table {+3,+2,+1,0,−1.2,−2.4,−3.6,−4.4}), camera-bearing
 *       arcs of {@value #CURTAIN_COLUMNS} sheared columns × 3 stacked sub-quads; a
 *       luminous band slides DOWN each column (the {@code storm_interior.fsh} rainLayer
 *       trick in world space); curtain pattern rotation rides the frozen stratum band
 *       clock table (noise-index only — EVAL-POL-F #1). Spheres + cylinders, tier 2,
 *       ≤ 126 quads.</li>
 *   <li><b>B4 debris streaks</b> — {@value #STREAKS_FULL} (12 at tier 1) STATELESS
 *       streaks corkscrewing upward through the 3 orbit bands {r−2, r+1, r+4} with
 *       vertical migration; closed-form position from game time, velocity-oriented
 *       2-quad crosses with a brighter head. The EXPLODE implosion pulls their radii
 *       to 0 — the suck-in grabs the debris field.</li>
 *   <li><b>B5 cloud-clump fans</b> — {@value #CLUMPS_FULL} (8 at tier 1) soft 4-quad
 *       octagon fans (bright shared center → alpha-0 rim; IDEAS-STORM-1 cauliflower
 *       billboards: 2-tone lit-top/dark-base gradient + silhouette rim pop) riding the
 *       strata at r+2.5 ± 1, painter-ordered far-band → near-band between the shells
 *       (IDEAS-STORM-2 #7 distance bands). Spheres only, 64 quads.</li>
 *   <li><b>B6 gust coupling</b> — curtain fall ×(1+0.6·gust), clump alpha ×(1+0.3·gust),
 *       streak orbit ×(1+0.4·gust), via {@link StormWeatherFx#weatherTimeSkew()} so the
 *       stateless clocks accelerate without phase jumps.</li>
 * </ul>
 *
 * <p>Frozen ground rules honored: geometry windows stay camera-centered (rotation lives in
 * pattern indices; discrete orbiters follow the A7 hash-orbit precedent), every radius
 * stays ≥ occluderR + 0.3 outside the occluder, daylight rules
 * ({@code DAY_ADDITIVE_BOOST}/{@code DAY_BOLT_WIDEN}) apply to every new alpha, and the
 * never-see-inside occluder is untouched. Steady budget ≤ ~240 additive quads + ≤ 28
 * during a flash.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
final class StormWeatherRenderer {
    /** Same stage as {@link StormWallRenderer} (swap together if Sodium artifacts appear). */
    private static final RenderLevelStageEvent.Stage RENDER_STAGE =
            RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    /** All W-B weather is near-LOD only; alpha fades out over the last blocks to the gate. */
    private static final float NEAR_RANGE = 160.0F;
    private static final float NEAR_FADE = 16.0F;
    /** Extra visible-arc margin (rad) beyond the tangent arc (StormWallRenderer pattern). */
    private static final double ARC_MARGIN = 0.5D;

    // --- frozen cross-package tables (PLAN-STORM2 §3/§4; file-local copies by ownership) ---
    /**
     * Band clock table (W-A A3, frozen): 4 altitude strata × pattern-rotation speed
     * multipliers on the base sphere band drift (0.004 rad/t). Index 3 counter-rotates.
     */
    private static final float[] STRATUM_SPEED = {0.6F, 1.0F, 1.5F, -0.8F};
    /** Stratum boundaries over latFrac (heavy base / mid / fast upper / counter polar). */
    private static final float[] STRATUM_LAT_EDGE = {0.30F, 0.55F, 0.85F};
    /** Base band drift rad/tick (frozen copy of W-A's {@code SPHERE_BAND_RAD_PER_TICK}). */
    private static final float BAND_RAD_PER_TICK = 0.004F;
    /** Daylight rules (§1, frozen): every new additive alpha takes the noon boost/widen. */
    private static final float DAY_ADDITIVE_BOOST = 0.55F;
    private static final float DAY_BOLT_WIDEN = 0.35F;

    // --- B3 rain curtains (radii between the frozen EXO shell radius table) ---
    private static final float[] CURTAIN_OFFSETS = {1.5F, -0.8F, -3.0F};
    /** Stratum each curtain radius rides (outer fast upper, mid, inner heavy base). */
    private static final int[] CURTAIN_STRATUM = {2, 1, 0};
    private static final int CURTAIN_COLUMNS = 14;
    private static final int CURTAIN_SUB_QUADS = 3;
    /** Column angular step — the near-tier shell column step (2π / 96). */
    private static final double CURTAIN_STEP = Math.PI * 2.0D / 96.0D;
    /** Hash gate: ~40% of columns carry rain, re-rolled per fall cycle. */
    private static final float CURTAIN_GATE = 0.40F;
    /** Vertical span: bottom pad up to 65% of the storm height. */
    private static final float CURTAIN_SPAN_FRAC = 0.65F;
    /** Faint slate-blue additive (B3 frozen tint), alpha capped at 0.22·churn. */
    private static final float CURTAIN_R = 0.35F;
    private static final float CURTAIN_G = 0.40F;
    private static final float CURTAIN_B = 0.60F;
    private static final float CURTAIN_ALPHA = 0.22F;
    /** Bearing shear of a column top vs its base (the "sheared quad columns" lean). */
    private static final float CURTAIN_SHEAR = 0.10F;

    // --- B4 debris streaks (3 orbit bands, §2 diagram: r−2 / r+1 / r+4) ---
    private static final int STREAKS_FULL = 24;
    private static final int STREAKS_REDUCED = 12;
    private static final float[] STREAK_BAND_OFF = {-2.0F, 1.0F, 4.0F};
    /** Streak body slate-gray; the head lerps toward the bright tone. */
    private static final float STREAK_R = 0.32F;
    private static final float STREAK_G = 0.33F;
    private static final float STREAK_B = 0.40F;
    private static final float STREAK_HEAD_R = 0.62F;
    private static final float STREAK_HEAD_G = 0.63F;
    private static final float STREAK_HEAD_B = 0.72F;

    // --- B5 cloud-clump fans (IDEAS-STORM-1 cauliflower billboards, no texture) ---
    private static final int CLUMPS_FULL = 16;
    private static final int CLUMPS_REDUCED = 8;
    /** Clump anchor radius: r + 2.5 ± 1 (slow fvnoise-style jitter). */
    private static final float CLUMP_RADIUS_OFF = 2.5F;
    private static final float CLUMP_RADIUS_JITTER = 1.0F;
    /** 2-tone shading: lit violet-gray top petals, dark slate base petals. */
    private static final float LIT_R = 0.55F;
    private static final float LIT_G = 0.50F;
    private static final float LIT_B = 0.68F;
    private static final float DARK_R = 0.10F;
    private static final float DARK_G = 0.09F;
    private static final float DARK_B = 0.14F;
    /** Band hue tint endpoints (frozen sphere palette: fog-green ↔ eclipse-violet). */
    private static final float HUE_GREEN_R = 0.22F;
    private static final float HUE_GREEN_G = 0.44F;
    private static final float HUE_GREEN_B = 0.32F;
    private static final float HUE_VIOLET_R = 0.30F;
    private static final float HUE_VIOLET_G = 0.20F;
    private static final float HUE_VIOLET_B = 0.47F;
    /** IDEAS-STORM-2 #7 painter ordering: quantized radial distance bands, far → near. */
    private static final int CLUMP_BANDS = 3;
    /** Per-frame clump scratch (computed once, emitted in band order — zero alloc). */
    private static final float[] CLUMP_PX = new float[CLUMPS_FULL];
    private static final float[] CLUMP_PY = new float[CLUMPS_FULL];
    private static final float[] CLUMP_PZ = new float[CLUMPS_FULL];
    private static final float[] CLUMP_HALF = new float[CLUMPS_FULL];
    private static final float[] CLUMP_ALPHA = new float[CLUMPS_FULL];
    private static final float[] CLUMP_HUE = new float[CLUMPS_FULL];
    private static final int[] CLUMP_BAND = new int[CLUMPS_FULL];

    // --- B2 embedded bolt ribbons (file-local 6-segment ribbon math — ownership disjoint) ---
    private static final int RIBBON_SUB_SEGMENTS = 6;
    private static final int FORK_SUB_SEGMENTS = 2;
    /** Reused polyline scratch (BOLT_PTS pattern) — ribbons allocate nothing per frame. */
    private static final float[] RIBBON_PTS = new float[(RIBBON_SUB_SEGMENTS + 1) * 3];
    private static final float[] FORK_PTS = new float[(FORK_SUB_SEGMENTS + 1) * 3];
    /** Ribbon span between shell radii: r+2 (outer glow shell) → r−4 (inner rim shell). */
    private static final float RIBBON_R_OUT = 2.0F;
    private static final float RIBBON_R_IN = -4.0F;

    /** Daylight factor of the current frame (StormWallRenderer pattern; render thread only). */
    private static float daylight;

    private StormWeatherRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RENDER_STAGE) {
            return;
        }
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        if (storms.isEmpty()) {
            return; // zero cost while no storm exists anywhere
        }
        int tier = FxBudget.qualityTier();
        if (tier <= 0) {
            return; // §5 ladder: tier 0 runs no W-B weather at all
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        Vec3 camera = event.getCamera().getPosition();
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float time = StormFxClient.ticks() + partialTick;
        daylight = level.dimensionType().hasSkyLight()
                ? OverworldPurpleEffects.dayFactor(level, partialTick)
                : 0.0F;

        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int i = 0; i < storms.size(); i++) {
            buildStormWeather(buffer, storms.get(i), camera, partialTick, time, tier);
        }
        drawAdditive(buffer);
    }

    // ------------------------------------------------------------------ per-storm dispatch

    private static void buildStormWeather(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float partialTick, float time, int tier) {
        float vis = storm.visibility(partialTick);
        if (vis <= 0.01F) {
            return;
        }
        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dz * dz);
        // Deep-interior early-out (StormWallRenderer rule): W-A's ENDO stack owns that view.
        if (centerDist < storm.radius - StormWallRenderer.OCCLUDER_INSET - 2.0D) {
            return;
        }
        float shellDist = (float) Math.abs(centerDist - storm.radius);
        if (shellDist >= NEAR_RANGE) {
            return; // ALL W-B weather is near-LOD only (§5)
        }
        float boom = storm.explodeProgress(partialTick);
        if (boom >= StormWallRenderer.EXPLODE_IMPLODE_FRAC) {
            return; // post-implosion burst: the shockwave owns the frame (W-A/W-D)
        }
        // Implosion suck-in 1 → 0 over the pinch: streak radii lerp to 0, the rest fades.
        float implode = 1.0F - smoothstep(0.0F, StormWallRenderer.EXPLODE_IMPLODE_FRAC, boom);
        // Fade out over the last NEAR_FADE blocks before the gate (no pop at 160).
        float alphaMul = vis * (1.0F - smoothstep(NEAR_RANGE - NEAR_FADE, NEAR_RANGE, shellDist));
        if (alphaMul <= 0.01F) {
            return;
        }
        boolean inside = centerDist < storm.radius;
        double camAngle = Math.atan2(dz, dx);
        double halfArc = Math.PI;
        if (!inside) {
            halfArc = Math.min(Math.PI, Math.acos(Mth.clamp(
                    storm.radius / (float) centerDist, 0.0F, 1.0F)) + ARC_MARGIN);
        }
        float heightScale = heightScale(storm, vis);
        float gust = StormInteriorFx.gustAmount();
        float skew = StormWeatherFx.weatherTimeSkew();
        boolean sphere = storm.type == S2CStormStatePayload.TYPE_SPHERE;

        // §5 tier ladder: clumps drop (16 → 8 → 0), then curtains (tier 2 only), then
        // ribbons (tier 2 only — tier 1 keeps the flash color-only via W-A's pulse).
        if (tier >= 2) {
            emitRainCurtains(buffer, storm, camera, time, camAngle, heightScale,
                    alphaMul * implode, skew);
        }
        if (sphere) {
            int streaks = tier >= 2 ? STREAKS_FULL : STREAKS_REDUCED;
            emitDebrisStreaks(buffer, storm, camera, time, camAngle, halfArc, inside,
                    heightScale, alphaMul, implode, skew, streaks);
            int clumps = tier >= 2 ? CLUMPS_FULL : CLUMPS_REDUCED;
            emitCloudClumps(buffer, storm, camera, time, camAngle, halfArc, inside,
                    heightScale, alphaMul * implode, gust, clumps, centerDist);
            if (tier >= 2 && boom <= 0.0F) {
                emitBoltRibbons(buffer, storm, camera, time, heightScale, alphaMul);
            }
        }
    }

    // ------------------------------------------------------------------ B3 rain curtains

    /**
     * Falling rain curtains at 3 inter-shell radii: camera-bearing arcs of
     * {@value #CURTAIN_COLUMNS} sheared columns × {@value #CURTAIN_SUB_QUADS} stacked
     * sub-quads. Per column a hash gate (~40% on, re-rolled per fall cycle) and a luminous
     * band whose phase {@code fract(y·0.13 + t·fallSpeed)} slides DOWN the column (phase
     * grows with time ⇒ the constant-phase height falls — the world-space rainLayer trick).
     * Curtain pattern rotation rides the frozen stratum band clocks, noise-index only
     * (EVAL-POL-F #1); gusts speed the fall via the integrated time skew (B6).
     */
    private static void emitRainCurtains(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, double camAngle, float heightScale, float alphaMul,
            float skew) {
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        float height = storm.height * heightScale;
        float yBot = 0.5F;
        float ySpan = Math.max(2.0F, height * CURTAIN_SPAN_FRAC - yBot);
        float subSpan = ySpan / CURTAIN_SUB_QUADS;
        // B6: gusts accelerate the fall — integrated skew, so phases never jump.
        float fallTime = time + 0.6F * skew;
        boolean vortex = storm.type == S2CStormStatePayload.TYPE_VORTEX;
        boolean sphereType = storm.type == S2CStormStatePayload.TYPE_SPHERE;
        int churnT = (int) (time / 6.0F);
        float dayBoost = 1.0F + DAY_ADDITIVE_BOOST * daylight;

        for (int c = 0; c < CURTAIN_OFFSETS.length; c++) {
            float curtainR = storm.radius + CURTAIN_OFFSETS[c];
            if (curtainR < 2.0F) {
                continue;
            }
            // Rotation rides the stratum clock — PATTERN INDEX ONLY, geometry stays pinned
            // to the camera bearing (EVAL-POL-F #1).
            float rot = time * BAND_RAD_PER_TICK * STRATUM_SPEED[CURTAIN_STRATUM[c]];
            float shearDir = STRATUM_SPEED[CURTAIN_STRATUM[c]] < 0.0F ? -1.0F : 1.0F;
            for (int col = 0; col < CURTAIN_COLUMNS; col++) {
                double a0 = camAngle + (col - CURTAIN_COLUMNS * 0.5D) * CURTAIN_STEP;
                int noiseCol = Mth.floor((float) ((a0 + rot) / CURTAIN_STEP));
                float fallSpeed = 0.09F + 0.04F * hash3(c * 8 + 70, noiseCol, 0);
                float phase = fallTime * fallSpeed;
                // Gate re-rolls once per fall cycle (one full band pass down the column).
                if (hash3(c * 8 + 71, noiseCol, Mth.floor(phase)) > CURTAIN_GATE) {
                    continue;
                }
                float churn = 0.45F + 0.55F * hash3(c * 8 + 72, noiseCol, churnT);
                float aMax = CURTAIN_ALPHA * churn * alphaMul * dayBoost;
                if (aMax < 0.015F) {
                    continue; // alpha-floor cull (fill-rate guard, W-A rule)
                }
                double a1 = a0 + CURTAIN_STEP;
                for (int sub = 0; sub < CURTAIN_SUB_QUADS; sub++) {
                    float y0 = yBot + sub * subSpan;
                    float y1 = y0 + subSpan;
                    float alpha0 = aMax * rainBand(fract(y0 * 0.13F + phase));
                    float alpha1 = aMax * rainBand(fract(y1 * 0.13F + phase));
                    if (alpha0 < 0.015F && alpha1 < 0.015F) {
                        continue;
                    }
                    // Sheared columns: radius follows the dome chord (sphere) or the 8°
                    // vortex lean, and the bearing leans with height in the stratum's
                    // flow direction — the curtain visibly shears with its band.
                    float r0 = curtainRadiusAt(curtainR, storm.radius, y0, heightScale,
                            sphereType, vortex);
                    float r1 = curtainRadiusAt(curtainR, storm.radius, y1, heightScale,
                            sphereType, vortex);
                    double shear0 = CURTAIN_SHEAR * shearDir * (y0 - yBot) / ySpan;
                    double shear1 = CURTAIN_SHEAR * shearDir * (y1 - yBot) / ySpan;
                    buffer.addVertex(cx + (float) Math.cos(a0 + shear0) * r0, cy + y0,
                                    cz + (float) Math.sin(a0 + shear0) * r0)
                            .setColor(CURTAIN_R, CURTAIN_G, CURTAIN_B, alpha0);
                    buffer.addVertex(cx + (float) Math.cos(a1 + shear0) * r0, cy + y0,
                                    cz + (float) Math.sin(a1 + shear0) * r0)
                            .setColor(CURTAIN_R, CURTAIN_G, CURTAIN_B, alpha0);
                    buffer.addVertex(cx + (float) Math.cos(a1 + shear1) * r1, cy + y1,
                                    cz + (float) Math.sin(a1 + shear1) * r1)
                            .setColor(CURTAIN_R, CURTAIN_G, CURTAIN_B, alpha1);
                    buffer.addVertex(cx + (float) Math.cos(a0 + shear1) * r1, cy + y1,
                                    cz + (float) Math.sin(a0 + shear1) * r1)
                            .setColor(CURTAIN_R, CURTAIN_G, CURTAIN_B, alpha1);
                }
            }
        }
    }

    /** Luminous falling band: bright head at phase 0, soft base glow between passes. */
    private static float rainBand(float f) {
        float nearHead = Math.min(f, 1.0F - f); // distance to the band center (wraps)
        float band = Math.max(0.0F, 1.0F - nearHead / 0.35F);
        return 0.25F + 0.75F * band * band;
    }

    /** Curtain radius at column height: dome chord (sphere) / 8° lean (vortex) / straight. */
    private static float curtainRadiusAt(float curtainR, float stormR, float y,
            float heightScale, boolean sphereType, boolean vortex) {
        if (sphereType) {
            float sinLat = Mth.clamp(y / (stormR * Math.max(0.05F, heightScale)), 0.0F, 0.95F);
            return curtainR * Mth.sqrt(1.0F - sinLat * sinLat);
        }
        if (vortex) {
            return Math.max(stormR * 0.25F, curtainR - y * StormWallRenderer.TAN_TILT);
        }
        return curtainR;
    }

    // ------------------------------------------------------------------ B4 debris streaks

    /**
     * Stateless debris streaks: every position is a closed form of {@code (i, time)} — no
     * entity state anywhere. Orbit band from {@code hash(i)} → {r−2, r+1, r+4}, signed
     * angular speed 0.02–0.05 rad/t (hash-orbit precedent of W-A's A7 torus), vertical
     * migration {@code (baseY + t·climb) mod 0.9·height + 1.5·sin(t·0.07+i)} — the streaks
     * corkscrew UP through the mass and wrap. The orbit radius follows the dome chord so
     * high streaks spiral up-and-in with the shell. Velocity-oriented 2-quad cross with a
     * brighter head; the EXPLODE implosion lerps radii to 0 (suck-in).
     */
    private static void emitDebrisStreaks(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, double camAngle, double halfArc, boolean inside,
            float heightScale, float alphaMul, float implode, float skew, int count) {
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        float wrapH = Math.max(4.0F, 0.9F * storm.height * heightScale);
        float orbitTime = time + 0.4F * skew; // B6: orbits accelerate with the gust bar
        float dayBoost = 1.0F + DAY_ADDITIVE_BOOST * daylight;

        for (int i = 0; i < count; i++) {
            int seed = storm.id * 97 + i;
            float bandOff = STREAK_BAND_OFF[(int) (hash3(seed, 3, 11) * 2.999F)];
            float omega = (0.02F + 0.03F * hash3(seed, 5, 13))
                    * (hash3(seed, 7, 17) < 0.5F ? -1.0F : 1.0F);
            double bearing = hash3(seed, 9, 19) * (Math.PI * 2.0D) + orbitTime * omega;
            if (!inside && Math.abs(wrapRad(bearing - camAngle)) > halfArc + 0.4D) {
                continue; // tangent-arc cull: unseen far-side streaks cost nothing
            }
            float climb = 0.02F + 0.04F * hash3(seed, 21, 23);
            float y = fmodPos(hash3(seed, 25, 29) * wrapH + time * climb, wrapH)
                    + 1.5F * Mth.sin(time * 0.07F + i);
            float sinLat = Mth.clamp(y / (storm.radius * Math.max(0.05F, heightScale)),
                    0.0F, 0.95F);
            float chord = Mth.sqrt(1.0F - sinLat * sinLat);
            float hr = (storm.radius + bandOff) * chord * implode;
            if (hr < 1.0F) {
                continue;
            }
            float px = cx + (float) Math.cos(bearing) * hr;
            float py = cy + y;
            float pz = cz + (float) Math.sin(bearing) * hr;

            // Velocity direction: tangential orbit + upward climb (the corkscrew axis).
            float sign = omega < 0.0F ? -1.0F : 1.0F;
            float vx = -(float) Math.sin(bearing) * sign * Math.abs(omega) * hr;
            float vy = climb + 0.105F * Mth.cos(time * 0.07F + i); // d/dt of the bob term
            float vz = (float) Math.cos(bearing) * sign * Math.abs(omega) * hr;
            float vLen = Math.max(1.0E-3F, Mth.sqrt(vx * vx + vy * vy + vz * vz));
            vx /= vLen;
            vy /= vLen;
            vz /= vLen;

            float halfLen = (0.6F + 0.7F * hash3(seed, 31, 37)); // length 1.2–2.6
            float halfWidth = 0.12F + 0.18F * hash3(seed, 41, 43);
            float alpha = 0.30F * alphaMul * dayBoost;
            emitStreakCross(buffer, px, py, pz, vx, vy, vz, bearing, halfLen, halfWidth, alpha);
        }
    }

    /** 2-quad cross along the velocity axis: radial-normal + binormal planes, bright head. */
    private static void emitStreakCross(BufferBuilder buffer, float px, float py, float pz,
            float dx, float dy, float dz, double bearing, float halfLen, float halfWidth,
            float alpha) {
        // Normal 1: the radial direction, orthogonalized against the velocity axis.
        float rx = (float) Math.cos(bearing);
        float rz = (float) Math.sin(bearing);
        float dot = rx * dx + rz * dz;
        float n1x = rx - dot * dx;
        float n1y = -dot * dy;
        float n1z = rz - dot * dz;
        float n1Len = Math.max(1.0E-3F, Mth.sqrt(n1x * n1x + n1y * n1y + n1z * n1z));
        n1x = n1x / n1Len * halfWidth;
        n1y = n1y / n1Len * halfWidth;
        n1z = n1z / n1Len * halfWidth;
        // Normal 2: velocity × normal1 (unit axis × perpendicular ⇒ already halfWidth long).
        float n2x = dy * n1z - dz * n1y;
        float n2y = dz * n1x - dx * n1z;
        float n2z = dx * n1y - dy * n1x;
        float hx = px + dx * halfLen; // head (leading end — brighter)
        float hy = py + dy * halfLen;
        float hz = pz + dz * halfLen;
        float tx = px - dx * halfLen; // tail
        float ty = py - dy * halfLen;
        float tz = pz - dz * halfLen;
        float headAlpha = Math.min(1.0F, alpha * 1.6F);
        // Plane 1 (radial-normal), tail pair then head pair.
        buffer.addVertex(tx - n1x, ty - n1y, tz - n1z)
                .setColor(STREAK_R, STREAK_G, STREAK_B, alpha * 0.5F);
        buffer.addVertex(tx + n1x, ty + n1y, tz + n1z)
                .setColor(STREAK_R, STREAK_G, STREAK_B, alpha * 0.5F);
        buffer.addVertex(hx + n1x, hy + n1y, hz + n1z)
                .setColor(STREAK_HEAD_R, STREAK_HEAD_G, STREAK_HEAD_B, headAlpha);
        buffer.addVertex(hx - n1x, hy - n1y, hz - n1z)
                .setColor(STREAK_HEAD_R, STREAK_HEAD_G, STREAK_HEAD_B, headAlpha);
        // Plane 2 (binormal).
        buffer.addVertex(tx - n2x, ty - n2y, tz - n2z)
                .setColor(STREAK_R, STREAK_G, STREAK_B, alpha * 0.5F);
        buffer.addVertex(tx + n2x, ty + n2y, tz + n2z)
                .setColor(STREAK_R, STREAK_G, STREAK_B, alpha * 0.5F);
        buffer.addVertex(hx + n2x, hy + n2y, hz + n2z)
                .setColor(STREAK_HEAD_R, STREAK_HEAD_G, STREAK_HEAD_B, headAlpha);
        buffer.addVertex(hx - n2x, hy - n2y, hz - n2z)
                .setColor(STREAK_HEAD_R, STREAK_HEAD_G, STREAK_HEAD_B, headAlpha);
    }

    // ------------------------------------------------------------------ B5 cloud clumps

    /**
     * Soft cloud-clump fans (the chunk read): textureless radial-gradient billboards —
     * each clump is a 4-quad camera-facing octagon fan sharing a bright center vertex
     * (center alpha 0.30·churn → rim alpha 0; the vertex interpolation IS the soft
     * falloff). 2-tone gradient (lit top petals / dark base petals) + rim pop per the
     * IDEAS-STORM-1 cauliflower billboards, body tinted by the band hue. Anchors ride the
     * strata (hash bearing + stratum clock — A7 orbit precedent), slow size breathing,
     * gust-lifted alpha. Emitted in quantized radial distance bands far → near between
     * the shells (IDEAS-STORM-2 #7 painter ordering).
     */
    private static void emitCloudClumps(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, double camAngle, double halfArc, boolean inside,
            float heightScale, float alphaMul, float gust, int count, double centerDist) {
        float cx = (float) (storm.center.x - camera.x);
        float cy = (float) (storm.center.y - camera.y);
        float cz = (float) (storm.center.z - camera.z);
        float dayBoost = 1.0F + DAY_ADDITIVE_BOOST * daylight;
        float gustBoost = 1.0F + 0.3F * gust;
        int churnT = (int) (time / 8.0F);
        // Distance-band quantum: the clump belt spans ~2 block-radii of radial jitter, so
        // thirds of the near shell gap bucket cleanly (band = |anchorDist − camDist| / 12).
        for (int i = 0; i < count; i++) {
            CLUMP_BAND[i] = -1;
            int seed = storm.id * 131 + i;
            float lat = 0.1F + 0.7F * hash3(seed, 51, 3);
            int stratum = stratumOfLat(lat);
            double bearing = hash3(seed, 53, 5) * (Math.PI * 2.0D)
                    + time * BAND_RAD_PER_TICK * STRATUM_SPEED[stratum];
            if (!inside && Math.abs(wrapRad(bearing - camAngle)) > halfArc + 0.6D) {
                continue;
            }
            // Slow smoothed radial jitter (fvnoise-style 1-D value noise, ±1 block).
            float jitter = (vnoise1(seed, time / 40.0F) - 0.5F) * 2.0F * CLUMP_RADIUS_JITTER;
            float clumpR = storm.radius + CLUMP_RADIUS_OFF + jitter;
            float latAngle = lat * (float) (Math.PI / 2.0D);
            float hr = clumpR * Mth.cos(latAngle);
            float py = cy + Mth.sin(latAngle) * clumpR * heightScale;
            float px = cx + (float) Math.cos(bearing) * hr;
            float pz = cz + (float) Math.sin(bearing) * hr;
            float size = 6.0F + 8.0F * hash3(seed, 57, 7);
            float breathe = 1.0F + 0.08F * Mth.sin(time * 0.03F + i * 2.1F);
            float churn = 0.45F + 0.55F * hash3(seed, 59, churnT);
            // Rim pop: silhouette-edge clumps glow brighter (emitSphereShell rim rule).
            float edge = halfArc <= 0.0D ? 0.0F
                    : (float) Math.abs(wrapRad(bearing - camAngle) / halfArc);
            float rim = inside ? 0.55F : 0.35F + 0.65F * smoothstep(0.55F, 0.95F, edge);
            CLUMP_PX[i] = px;
            CLUMP_PY[i] = py;
            CLUMP_PZ[i] = pz;
            CLUMP_HALF[i] = size * 0.5F * breathe;
            CLUMP_ALPHA[i] = 0.30F * churn * alphaMul * gustBoost * dayBoost * rim;
            CLUMP_HUE[i] = hash3(seed, 61, 9);
            // IDEAS-STORM-2 #7: quantized |anchor radial dist − camera dist| painter bands.
            CLUMP_BAND[i] = Math.min(CLUMP_BANDS - 1,
                    (int) (Math.abs(clumpR - centerDist) / 12.0D));
        }
        for (int band = CLUMP_BANDS - 1; band >= 0; band--) {
            for (int i = 0; i < count; i++) {
                if (CLUMP_BAND[i] == band && CLUMP_ALPHA[i] >= 0.015F) {
                    emitClumpFan(buffer, CLUMP_PX[i], CLUMP_PY[i], CLUMP_PZ[i],
                            CLUMP_HALF[i], CLUMP_ALPHA[i], CLUMP_HUE[i]);
                }
            }
        }
    }

    /** One camera-facing octagon fan: 4 quads sharing the bright center vertex. */
    private static void emitClumpFan(BufferBuilder buffer, float px, float py, float pz,
            float half, float centerAlpha, float hue) {
        // Camera-facing basis (camera at origin: the view dir IS the position).
        float vLen = Math.max(1.0E-3F, Mth.sqrt(px * px + py * py + pz * pz));
        float vx = px / vLen;
        float vy = py / vLen;
        float vz = pz / vLen;
        float rx = -vz; // v × worldUp (guarded against the vertical degenerate case)
        float rz = vx;
        float rLen = Mth.sqrt(rx * rx + rz * rz);
        if (rLen < 1.0E-3F) {
            rx = 1.0F;
            rz = 0.0F;
            rLen = 1.0F;
        }
        rx /= rLen;
        rz /= rLen;
        // Billboard-up = cross(right, view) with right = (rx, 0, rz).
        float ux = -rz * vy;
        float uy = rz * vx - rx * vz;
        float uz = rx * vy;
        float uLen = Math.max(1.0E-3F, Mth.sqrt(ux * ux + uy * uy + uz * uz));
        ux /= uLen;
        uy /= uLen;
        uz /= uLen;

        // Band hue tint (fog-green ↔ eclipse-violet, stable per clump).
        float hueR = Mth.lerp(hue, HUE_GREEN_R, HUE_VIOLET_R);
        float hueG = Mth.lerp(hue, HUE_GREEN_G, HUE_VIOLET_G);
        float hueB = Mth.lerp(hue, HUE_GREEN_B, HUE_VIOLET_B);
        // Center: bright mid-tone leaning lit, tinted by the band hue.
        float ctrR = Mth.lerp(0.35F, Mth.lerp(0.75F, DARK_R, LIT_R), hueR);
        float ctrG = Mth.lerp(0.35F, Mth.lerp(0.75F, DARK_G, LIT_G), hueG);
        float ctrB = Mth.lerp(0.35F, Mth.lerp(0.75F, DARK_B, LIT_B), hueB);

        // 4 quads over 8 rim points: rim[2k], rim[2k+1], rim[2k+2], center.
        for (int k = 0; k < 4; k++) {
            emitClumpRimVertex(buffer, px, py, pz, rx, rz, ux, uy, uz, half, k * 2,
                    hueR, hueG, hueB);
            emitClumpRimVertex(buffer, px, py, pz, rx, rz, ux, uy, uz, half, k * 2 + 1,
                    hueR, hueG, hueB);
            emitClumpRimVertex(buffer, px, py, pz, rx, rz, ux, uy, uz, half, (k * 2 + 2) & 7,
                    hueR, hueG, hueB);
            buffer.addVertex(px, py, pz).setColor(ctrR, ctrG, ctrB, centerAlpha);
        }
    }

    /** One octagon rim vertex: alpha 0, 2-tone color by petal "topness" + hue tint. */
    private static void emitClumpRimVertex(BufferBuilder buffer, float px, float py, float pz,
            float rx, float rz, float ux, float uy, float uz, float half, int k,
            float hueR, float hueG, float hueB) {
        float phi = k * (float) (Math.PI / 4.0D);
        float cos = Mth.cos(phi);
        float sin = Mth.sin(phi);
        float topness = (sin + 1.0F) * 0.5F; // 2-tone: lit top petals, dark slate base
        float r = Mth.lerp(0.35F, Mth.lerp(topness, DARK_R, LIT_R), hueR);
        float g = Mth.lerp(0.35F, Mth.lerp(topness, DARK_G, LIT_G), hueG);
        float b = Mth.lerp(0.35F, Mth.lerp(topness, DARK_B, LIT_B), hueB);
        buffer.addVertex(px + (rx * cos + ux * sin) * half,
                        py + (uy * sin) * half,
                        pz + (rz * cos + uz * sin) * half)
                .setColor(r, g, b, 0.0F);
    }

    // ------------------------------------------------------------------ B2 embedded bolt ribbons

    /**
     * Embedded bolt ribbons during a live {@link StormWeatherFx} flash: 1–2 jittered
     * ribbons (hash off the flash serial) + a fork branch each — 2–4 strands — arcing
     * radially INWARD from {@code r + }{@value #RIBBON_R_OUT} down to
     * {@code r − 4} between the shell radii, so W-A's outer shells veil the light born
     * inside the mass. File-local 6-segment ribbon math (BOLT_PTS pattern), core + glow
     * ≤ 14 quads per ribbon, ≤ 28 per flash; jitter re-seeds every 2 ticks; daylight
     * widens the ribbons ({@code DAY_BOLT_WIDEN} rule).
     */
    private static void emitBoltRibbons(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float heightScale, float alphaMul) {
        float amount = StormWeatherFx.innerFlashAmount(storm.id);
        if (amount <= 0.02F) {
            return;
        }
        int serial = StormWeatherFx.innerFlashSerial();
        double bearing = StormWeatherFx.innerFlashBearing(storm.id);
        float lat = StormWeatherFx.innerFlashLat(storm.id);
        int jitterFrame = (int) (time / 2.0F); // re-seeded every 2 ticks (bolt pattern)
        int ribbons = 1 + (hash3(serial, storm.id, 3) < 0.5F ? 1 : 0);
        float dayWiden = 1.0F + DAY_BOLT_WIDEN * daylight;

        for (int rb = 0; rb < ribbons; rb++) {
            float dir = rb == 0 ? 1.0F : -1.0F;
            int seed = serial * 31 + rb * 7 + jitterFrame * 7919;
            // Path endpoints (B2 frozen shape): (bearing±0.1, lat+0.25, r+2) down-and-in
            // to (bearing∓0.15, lat−0.1, r−4) — a radial arc BETWEEN the shell radii.
            fillSurfPoint(RIBBON_PTS, 0, storm, camera, heightScale,
                    bearing + 0.1D * dir, lat + 0.25F, storm.radius + RIBBON_R_OUT);
            fillSurfPoint(RIBBON_PTS, RIBBON_SUB_SEGMENTS * 3, storm, camera, heightScale,
                    bearing - 0.15D * dir, lat - 0.1F, storm.radius + RIBBON_R_IN);
            jitterPolyline(RIBBON_PTS, RIBBON_SUB_SEGMENTS, seed, 0.09F);
            // Glow then core (additive — order is free; glow first reads intentional).
            float width = (0.16F + 0.10F * amount) * dayWiden;
            emitPolyline(buffer, RIBBON_PTS, RIBBON_SUB_SEGMENTS, width * 2.6F,
                    0.62F, 0.42F, 1.0F, 0.45F * amount * (1.0F + 0.35F * daylight) * alphaMul);
            emitPolyline(buffer, RIBBON_PTS, RIBBON_SUB_SEGMENTS, width,
                    1.0F, 0.95F, 1.0F, 0.9F * amount * alphaMul);
            // Fork strand: branches from the ribbon midpoint out to a side cell (core only).
            FORK_PTS[0] = RIBBON_PTS[9]; // polyline point 3 — mid-arc
            FORK_PTS[1] = RIBBON_PTS[10];
            FORK_PTS[2] = RIBBON_PTS[11];
            fillSurfPoint(FORK_PTS, FORK_SUB_SEGMENTS * 3, storm, camera, heightScale,
                    bearing + 0.4D * dir, lat + 0.05F, storm.radius - 1.0F);
            jitterPolyline(FORK_PTS, FORK_SUB_SEGMENTS, seed ^ 0x9E37, 0.14F);
            emitPolyline(buffer, FORK_PTS, FORK_SUB_SEGMENTS, width * 0.6F,
                    0.95F, 0.88F, 1.0F, 0.7F * amount * alphaMul);
        }
    }

    /** Writes the camera-relative dome surface point of (bearing, latFrac, radius). */
    private static void fillSurfPoint(float[] pts, int at, StormFxClient.ClientStorm storm,
            Vec3 camera, float heightScale, double bearing, float latFrac, float radius) {
        float latAngle = Mth.clamp(latFrac, 0.0F, 0.98F) * (float) (Math.PI / 2.0D);
        float hr = radius * Mth.cos(latAngle);
        pts[at] = (float) (storm.center.x - camera.x) + (float) Math.cos(bearing) * hr;
        pts[at + 1] = (float) (storm.center.y - camera.y)
                + Mth.sin(latAngle) * radius * heightScale;
        pts[at + 2] = (float) (storm.center.z - camera.z) + (float) Math.sin(bearing) * hr;
    }

    /**
     * Fills the interior points of a polyline whose endpoints are already written at
     * index 0 and {@code segments·3}, jittering them perpendicular to the chord
     * (endpoint-pinned envelope — the buildBolt math, file-local by ownership).
     */
    private static void jitterPolyline(float[] pts, int segments, int seed, float ampFrac) {
        float fx = pts[0];
        float fy = pts[1];
        float fz = pts[2];
        float dxT = pts[segments * 3] - fx;
        float dyT = pts[segments * 3 + 1] - fy;
        float dzT = pts[segments * 3 + 2] - fz;
        float len = Mth.sqrt(dxT * dxT + dyT * dyT + dzT * dzT);
        if (len < 0.01F) {
            len = 0.01F;
        }
        float ux = Math.abs(dyT) > 0.9F * len ? 1.0F : 0.0F;
        float uy = 1.0F - ux;
        // v = normalize(dir × u), w = normalize(dir × v).
        float vx = (dyT * 0.0F - dzT * uy) / len;
        float vy = (dzT * ux - dxT * 0.0F) / len;
        float vz = (dxT * uy - dyT * ux) / len;
        float vLen = Math.max(1.0E-4F, Mth.sqrt(vx * vx + vy * vy + vz * vz));
        vx /= vLen;
        vy /= vLen;
        vz /= vLen;
        float wx = (dyT * vz - dzT * vy) / len;
        float wy = (dzT * vx - dxT * vz) / len;
        float wz = (dxT * vy - dyT * vx) / len;
        float amp = len * ampFrac;
        for (int j = 1; j < segments; j++) {
            float t = j / (float) segments;
            float envelope = 4.0F * t * (1.0F - t); // pinned at both endpoints
            float o1 = (hash3(seed, j * 2, 101) - 0.5F) * 2.0F * amp * envelope;
            float o2 = (hash3(seed, j * 2 + 1, 103) - 0.5F) * 2.0F * amp * envelope;
            pts[j * 3] = fx + dxT * t + vx * o1 + wx * o2;
            pts[j * 3 + 1] = fy + dyT * t + vy * o1 + wy * o2;
            pts[j * 3 + 2] = fz + dzT * t + vz * o1 + wz * o2;
        }
    }

    /** Camera-facing ribbon along a scratch polyline (emitRibbon math, file-local copy). */
    private static void emitPolyline(BufferBuilder buffer, float[] pts, int segments,
            float halfWidth, float r, float g, float b, float alpha) {
        if (alpha <= 0.01F) {
            return;
        }
        for (int j = 0; j < segments; j++) {
            float ax = pts[j * 3];
            float ay = pts[j * 3 + 1];
            float az = pts[j * 3 + 2];
            float bx = pts[j * 3 + 3];
            float by = pts[j * 3 + 4];
            float bz = pts[j * 3 + 5];
            float dx = bx - ax;
            float dy = by - ay;
            float dz = bz - az;
            // Camera at origin: the view dir to the segment midpoint IS the midpoint.
            float mx = (ax + bx) * 0.5F;
            float my = (ay + by) * 0.5F;
            float mz = (az + bz) * 0.5F;
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

    // ------------------------------------------------------------------ draw + helpers

    /** The single additive draw (W-A's additive branch — §W-B one-pass rule). */
    private static void drawAdditive(BufferBuilder buffer) {
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
        }
        RenderSystem.enableBlend();
        RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(false);
        BufferUploader.drawWithShader(mesh);
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
    }

    /** Altitude stratum of a latFrac (band clock table index; 3 = counter-rotating polar). */
    private static int stratumOfLat(float latFrac) {
        for (int s = 0; s < STRATUM_LAT_EDGE.length; s++) {
            if (latFrac < STRATUM_LAT_EDGE[s]) {
                return s;
            }
        }
        return 3;
    }

    /** SPAWN/DISSIPATE/EXPLODE height envelope (StormWallRenderer rule, file-local copy). */
    private static float heightScale(StormFxClient.ClientStorm storm, float visibility) {
        if (storm.state == S2CStormStatePayload.STATE_DISSIPATE) {
            return 1.0F + 0.3F * (1.0F - visibility);
        }
        if (storm.state == S2CStormStatePayload.STATE_EXPLODE) {
            return 1.0F;
        }
        return 0.25F + 0.75F * visibility;
    }

    /** Cheap 3-int hash in [0,1) — the shared churn-noise pattern, file-local copy. */
    private static float hash3(int a, int b, int c) {
        int h = a * 668265261 ^ b * 374761393 ^ c * 0x85EBCA77;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0xFFFF) / 65536.0F;
    }

    /** 1-D smoothed value noise in [0,1) (fvnoise-style; smoothstep-faded lattice hash). */
    private static float vnoise1(int seed, float t) {
        int i = Mth.floor(t);
        float f = t - i;
        float fade = f * f * (3.0F - 2.0F * f);
        return Mth.lerp(fade, hash3(seed, i, 205), hash3(seed, i + 1, 205));
    }

    private static float fract(float x) {
        return x - Mth.floor(x);
    }

    /** Positive floating modulo (the vertical-migration wrap). */
    private static float fmodPos(float x, float m) {
        float r = x % m;
        return r < 0.0F ? r + m : r;
    }

    /** Wraps an angle difference into [−π, π] (O(1) — orbit angles grow unbounded). */
    private static double wrapRad(double a) {
        a %= Math.PI * 2.0D;
        if (a > Math.PI) {
            a -= Math.PI * 2.0D;
        } else if (a < -Math.PI) {
            a += Math.PI * 2.0D;
        }
        return a;
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }
}
