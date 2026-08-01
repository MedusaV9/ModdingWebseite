package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.DimensionSpecialEffects;
import net.minecraft.client.renderer.FogRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.material.FogType;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Sky for the Limbo dimension ({@code eclipse:limbo} effects id, referenced by
 * {@code data/eclipse/dimension_type/limbo.json}): a near-black dome, sparse green star
 * points, and the eclipse disc with its aura.
 *
 * <p>P2-W3 overhaul (R5/R4-limbo):</p>
 * <ul>
 *   <li><b>Exact zenith</b>: the disc is no longer pinned at a fixed {@code -25°} tilt in the
 *       southern sky. Its direction is computed per frame toward a point
 *       {@value #ZENITH_HEIGHT} blocks above the ship deck ({@code FxAnchors
 *       eclipse:ship_deck}, published by P6; fallback: the shared spawn pos, which sits at
 *       the ship's x/z in the shipped limbo setup). Standing on the deck and looking straight
 *       up puts the eclipse dead-center overhead; walking away parallaxes it only slightly
 *       (the anchor point is effectively "at altitude"), so it always reads as hanging
 *       <i>over the ship</i>.</li>
 *   <li><b>1.5× disc</b>: {@value #DISC_SIZE} half-extent (was 35).</li>
 *   <li><b>Aura</b>: a soft radial glow fan behind the disc plus a {@value #RAY_COUNT}-ray
 *       additive aura fan in two counter-rotating layers (0.02&nbsp;°/frame ≈
 *       {@value #RAY_SPIN_DEG_PER_SEC}&nbsp;°/s), ray lengths 40&ndash;120 units, root alpha
 *       ≤&nbsp;0.4 fading to zero at the tips, with a slow breathing pulse.</li>
 *   <li><b>No clouds</b>: cloud height stays {@code NaN} and {@link #renderClouds} reports
 *       handled so vanilla draws nothing.</li>
 * </ul>
 *
 * <p>PLAN-C C2 overhaul (the "giant glitchy purple thing" fix):</p>
 * <ul>
 *   <li><b>Stable celestial disc</b>: the disc/aura direction is low-pass filtered and the
 *       whole disc+aura group draws INSIDE the stars' no-fog window with the
 *       depth test off — camera-relative at effectively infinite distance, fixed angular
 *       size, no parallax jitter, no fog/horizon-plane pops.</li>
 *   <li><b>Sailing cues</b>: a sparse client-side lane of mist bands + foam glints streams
 *       astern past the hull ({@link #spawnDriftCues}, respects {@code reducedFx}), and
 *       {@link LimboHorizonShips} silhouettes slide astern and respawn ahead — combined
 *       with C1's {@code VoyageOffset} caustic stream, the world reads as moving around
 *       the anchored ship.</li>
 * </ul>
 *
 * <p>v4 overhaul (FXTEAM-LIMBO — craft pass on top of C2, none of whose fixes move):</p>
 * <ul>
 *   <li><b>Breathing corona</b>: the aura glow fan's radius now breathes on a slow
 *       ~27&nbsp;s cycle (alpha dims slightly as it expands, like a real corona thinning),
 *       independent of — and layered under — the existing dual-frequency alpha pulse.</li>
 *   <li><b>Coronal-mass wisps</b>: occasionally (deterministic {@code ECLIPSE_SEED} slot
 *       hash, ~every 90&nbsp;s on average) a faint curved plume detaches from the disc rim
 *       and dissolves outward over ~10&nbsp;s ({@link #drawCoronalWisp}) — subtle
 *       (peak alpha 0.15), root hidden behind the disc, skipped under {@code reducedFx}.</li>
 *   <li><b>Aura-ray spin</b>: slowed to {@value #RAY_SPIN_DEG_PER_SEC}&nbsp;°/s with
 *       layer B counter-rotating. (The v4 camera-walk parallax offset on layer B was
 *       REMOVED by LIMBOFIX2 below — it was a camera-position coupling.)</li>
 * </ul>
 *
 * <p>LIMBOFIX: the C2/v4 water-reflection streak is GONE. Standing almost directly under
 * the zenith made the mirrored direction's azimuth numerically degenerate — tiny camera
 * moves swung the streak wildly (the "giant purple thing rotates with the player" bug) and
 * it drew through the hull with the depth test off. The post-shader smear went with it
 * (limbo.fsh); the water simply shows no disc reflection now.</p>
 *
 * <p>v4.1 (VEIL-REPASS-2): <b>aurora veils</b> ({@link #drawAuroraVeils}) — three slow
 * soul-green polar-light curtains drifting around the eclipse beyond the glow floor,
 * framing it at altitude. Garnish tier (skipped under {@code reducedFx}, the wisp
 * ladder); pure function of the hourly clock, so every client sees the same sky.</p>
 *
 * <p>v5 (F-104, IDEA-18 §9): <b>green shooting stars</b> ({@link #drawShootingStreaks})
 * — a rare single green streak across the dome every 1–3 minutes, on the deterministic
 * {@code ECLIPSE_SEED} slot-hash law (own salts). Drawn in the stars' no-fog window
 * OUTSIDE the zenith rotation push (it streaks the dome, not the disc frame), purely
 * geometric — zero new post uniforms ({@code limbo.fsh} stays frozen), zero per-frame
 * allocations (§3.5). Garnish tier ({@code reducedFx} skips). The dev hold
 * {@code /eclipsefx limbo streakhold} ({@link #setStreakHold}) freezes one streak at a
 * fixed dome spot on a fixed envelope: the schedule rides the SECOND-based sky clock
 * that {@code tick rate} tweaks cannot stretch, so software-rendered rigs need the hold
 * to photograph a 0.9&nbsp;s event.</p>
 *
 * <p><b>LIMBOFIX2 (the "giant purple thing still moves with every rotation" fix)</b>: the
 * disc/aura direction is now a COMPILE-TIME CONSTANT — azimuth {@code +X} (dead ahead of
 * the ship, the buoy-lane heading), elevation {@value #ECLIPSE_ELEVATION_DEG}° above the
 * horizon ({@link #CELESTIAL_DIR}/{@link #CELESTIAL_ROT}). The C2 anchoring computed the
 * direction from {@code zenith − cameraPos} every frame and low-pass filtered it: every
 * camera move (walk, ship bob, third-person orbit) re-aimed the disc, and because it sat
 * AT the zenith with a sky-filling aura (aurora feet reached ~65° from center), any yaw
 * left the view "inside" the radially symmetric pattern — it read as glued to the camera.
 * Now zero camera terms exist in the transform: the eclipse hangs at one fixed spot in the
 * sky over the water ahead of the bow, pans across the screen when the player turns, and
 * leaves the screen when they look away — like a real celestial object. The v4 ray-layer
 * walk parallax (camera-offset coupled) went with it, and every aura extent is rescaled so
 * nothing dips below the horizon at the new {@value #ECLIPSE_ELEVATION_DEG}° elevation.</p>
 *
 * <p>The same fixed direction ({@link #celestialDirection}) feeds the {@code eclipse:limbo}
 * post pipeline's {@code GodrayDir} uniform (see {@code veilfx.LimboAmbience}), so the
 * screen-space god rays and the sky-pass aura radiate from one source of truth and cannot
 * diverge.</p>
 *
 * <p><b>F-088 (the "big pink object blocks the view" fix)</b>: LIMBOFIX2 froze the
 * direction but left the group parked at azimuth {@code +X} — dead ahead of the ship's
 * bow, exactly where the player looks at the ship-phase start — with a glow fan spanning
 * ~81° of sky. It still read as a huge pink wall over the whole forward view. The fixed
 * direction now swings {@value #ECLIPSE_AZIMUTH_DEG}° to port of the buoy lane (a
 * {@code −Z} component; still a compile-time constant, still zero camera terms) and the
 * aura is rescaled/dimmed to a distant celestial accent: glow floor 86 →
 * {@value #GLOW_RADIUS}, glow center alpha 0.30 → 0.20, ray root alpha 0.4 →
 * {@value #RAY_ALPHA}, aurora feet 88 → {@value #AURORA_BASE_RADIUS}, glow center hue
 * pulled off pink toward deep violet. The god rays follow automatically
 * ({@link #celestialDirection} stays the shared source of truth).</p>
 *
 * <p>Same Iris guard as the overworld: with a shaderpack active this defers entirely.</p>
 */
@OnlyIn(Dist.CLIENT)
public class LimboSpecialEffects extends DimensionSpecialEffects {
    private static final ResourceLocation ECLIPSE_TEXTURE =
            ResourceLocation.fromNamespaceAndPath("eclipse", "textures/environment/eclipse.png");

    /** Sparse green stars; distinct seed so Limbo's sky differs from the overworld's. */
    private static final StarField GREEN_STARS = new StarField(20846L, 420, 0.18F);

    /** Celestial distance the disc/aura plane is drawn at (vanilla sun convention). */
    private static final float SKY_DISTANCE = 100.0F;
    /** LIMBOFIX2: reduced from 52.5 — a discrete celestial disc, not a sky-filling decal. */
    private static final float DISC_SIZE = 38.0F;
    /**
     * LIMBOFIX2: elevation (degrees above the horizon) of the FIXED eclipse direction.
     * High enough that the whole aura clears the horizon (see the per-extent math on the
     * radius constants), low enough that the disc visibly hangs over the water ahead of
     * the bow instead of sitting at the degenerate zenith.
     */
    private static final float ECLIPSE_ELEVATION_DEG = 50.0F;
    /**
     * F-088: azimuth swing (degrees toward {@code −Z} / port) of the fixed eclipse
     * direction off the {@code +X} buoy-lane heading. {@code 0} (the LIMBOFIX2 value)
     * parked the group dead ahead of the bow — the default view direction of the ship
     * phase — so its aura dominated the entire forward sky. 45° keeps the disc framed
     * over the water but clears the lane view.
     */
    private static final float ECLIPSE_AZIMUTH_DEG = 45.0F;
    /**
     * Virtual altitude of the {@link #zenithWorldPoint} anchor above the ship deck. The
     * disc no longer draws toward this point (LIMBOFIX2 — fixed direction); the anchor
     * remains the seam for {@link #clientWaterlineY} and the ship-relative FX consumers
     * ({@code veilfx.LimboAmbience}'s soul shoal, the drift-cue lane).
     */
    private static final double ZENITH_HEIGHT = 480.0D;

    /** Aura ray fan: 12 rays in two counter-rotating 6-ray layers (R5 freeze). */
    private static final int RAY_COUNT = 12;
    private static final int RAYS_PER_LAYER = RAY_COUNT / 2;
    /** v4: VERY slow spin (was 1.2 °/s) — barely-perceptible drift; layer B counter-spins. */
    private static final float RAY_SPIN_DEG_PER_SEC = 0.35F;
    /** Rays start slightly inside the disc silhouette so their roots hide behind it. */
    private static final float RAY_INNER_RADIUS = 24.0F;
    /** Peak root alpha of a ray (F-088: 0.4 → 0.28 — the aura dims to an accent). */
    private static final float RAY_ALPHA = 0.28F;
    /**
     * Deterministic per-ray lengths and root half-widths. LIMBOFIX2: rescaled (×~0.55 of
     * the zenith-era 40–120 range) so the longest ray tip ({@code 24 + 66 = 90} in-plane
     * units) stays well above the horizon at the {@value #ECLIPSE_ELEVATION_DEG}°
     * elevation — the horizon sits at {@code SKY_DISTANCE·tan(50°) ≈ 119} in-plane units.
     */
    private static final float[] RAY_LENGTHS = {
            65.0F, 34.0F, 52.0F, 26.0F, 59.0F, 39.0F,
            30.0F, 56.0F, 24.0F, 47.0F, 36.0F, 66.0F};
    private static final float[] RAY_WIDTHS = {
            5.4F, 3.6F, 4.7F, 3.0F, 5.0F, 4.0F,
            3.3F, 4.9F, 2.9F, 4.3F, 3.7F, 5.6F};

    /**
     * Radial glow fan behind the disc (the aura "floor"); LIMBOFIX2: 135 → 86; F-088:
     * 86 → 60 — the fan's half-angle drops from ~41° to ~31° so it reads as a corona
     * around the disc, not a wall across the sky.
     */
    private static final float GLOW_RADIUS = 60.0F;
    private static final int GLOW_SEGMENTS = 24;
    /** v4 breathing corona: glow radius swells ±5% on a slow ~27 s cycle (0.23 rad/s). */
    private static final float CORONA_BREATH_RATE = 0.23F;

    /**
     * v4 coronal-mass wisps: deterministic slot schedule — every {@value #WISP_SLOT_SECONDS}
     * seconds a seed hash decides flash/no-flash (~45%), an ejection azimuth, a curl side
     * and a start offset; an active wisp grows from the disc rim over
     * {@value #WISP_DURATION_SECONDS} s and dissolves (sin-in-out alpha, peak
     * {@value #WISP_PEAK_ALPHA} · pulse — always subtler than the ray roots).
     */
    private static final float WISP_SLOT_SECONDS = 41.0F;
    private static final float WISP_DURATION_SECONDS = 10.0F;
    private static final float WISP_PEAK_ALPHA = 0.15F;
    /** Wisp reach beyond the disc rim (celestial-plane units); LIMBOFIX2: 62 → 48. */
    private static final float WISP_REACH = 48.0F;

    /**
     * v4.1 aurora veils: soul-green polar-light bands at extreme altitude, framing the
     * eclipse. In the zenith celestial frame the eclipse IS the topmost point, so "above"
     * means CLOSE AROUND it: three partial arcs beyond the glow floor
     * ({@value #GLOW_RADIUS}), each an undulating curtain of {@value #AURORA_SEGMENTS}
     * cheap gradient quads with the classic aurora read — sharp bright lower edge (outer
     * radius, i.e. farther from the zenith), feathered fade toward the zenith. Slow
     * independent drifts; garnish tier ({@code reducedFx} skips, the wisp ladder).
     */
    private static final int AURORA_VEILS = 3;
    private static final int AURORA_SEGMENTS = 18;
    /**
     * Innermost veil foot radius; each further veil steps {@value #AURORA_RADIUS_STEP} out.
     * LIMBOFIX2: 152/26/34 → 88/8/22; F-088 aura shrink: 88 → 68 — the outermost
     * undulated foot ({@code 68+2·8+5=89} in-plane units) stays above the horizon at
     * the fixed 50° elevation (horizon ≈ 119).
     */
    private static final float AURORA_BASE_RADIUS = 68.0F;
    private static final float AURORA_RADIUS_STEP = 8.0F;
    /** Radial depth of a curtain (bright outer edge → feathered inner fade). */
    private static final float AURORA_BAND_DEPTH = 22.0F;
    /** Peak alpha of a curtain's bright edge (before pulse/envelope shaping). */
    private static final float AURORA_PEAK_ALPHA = 0.085F;
    /** Per-veil azimuth drift speeds (rad/s) — non-commensurate, so veils never lock step. */
    private static final float[] AURORA_DRIFT = {0.011F, -0.008F, 0.014F};
    /** Per-veil arc spans (radians, ~70–110°). */
    private static final float[] AURORA_SPAN = {1.9F, 1.35F, 1.6F};
    /** Per-veil base azimuths (radians) — spread so the veils frame, never encircle. */
    private static final float[] AURORA_AZIMUTH = {0.6F, 2.9F, 4.6F};

    /** C2 sailing cues: ticks between drift-cue spawns (doubled under reducedFx). */
    private static final int DRIFT_CUE_INTERVAL_TICKS = 3;
    /** Mist bands/foam glints stream astern at this speed (blocks/t, −X = astern). */
    private static final float DRIFT_CUE_SPEED = 0.22F;

    /**
     * F-104 (IDEA-18 §9) shooting streaks: deterministic slot schedule on the hourly
     * second clock — each {@value #STREAK_SLOT_SECONDS}-second slot hosts one streak
     * (~50%, {@code ECLIPSE_SEED} hash with own salts → one streak every ~1.6 min on
     * average), with slot-hashed start offset, azimuth, start elevation and sweep side.
     * A streak lives {@value #STREAK_DURATION_SECONDS} s and sweeps ~35° of dome arc
     * (azimuth sweep + elevation drop — a falling star sinks), alpha 0 → 0.5 → 0.
     */
    private static final float STREAK_SLOT_SECONDS = 47.0F;
    private static final float STREAK_DURATION_SECONDS = 0.9F;
    private static final float STREAK_PEAK_ALPHA = 0.5F;
    /** Start elevation band (radians): ~35°–65° above the horizon. */
    private static final float STREAK_EL_MIN = 0.61F;
    private static final float STREAK_EL_RANGE = 0.52F;
    /** Azimuth sweep (~29°) and elevation drop (~18°) over one streak life. */
    private static final float STREAK_AZ_SWEEP = 0.50F;
    private static final float STREAK_EL_DROP = 0.31F;
    /** The tail lags the head by this fraction of the full path. */
    private static final float STREAK_TAIL_FRAC = 0.38F;
    /** Head half-width in celestial-plane units (~0.5° at {@value #SKY_DISTANCE}). */
    private static final float STREAK_HEAD_HALF_WIDTH = 0.9F;
    private static final float STREAK_TAIL_WIDTH_FRAC = 0.15F;

    /**
     * C7 dev-hold pose: a fixed dome spot (azimuth ~17° starboard of the bow heading
     * {@code +X}, elevation ~55° — look up the buoy lane from the deck) with the
     * envelope frozen mid-flight ({@code t01 = 0.55}, near peak alpha). Compile-time
     * constants: while the hold is on, every frame draws the IDENTICAL streak, so
     * seconds-per-frame rigs (llvmpipe) can photograph it at leisure.
     */
    private static final float STREAK_HOLD_AZIMUTH = 0.3F;
    private static final float STREAK_HOLD_ELEVATION = 0.96F;
    private static final float STREAK_HOLD_T01 = 0.55F;

    /** C7: flipped only by {@code /eclipsefx limbo streakhold} (via {@code FxDevClient}). */
    private static volatile boolean streakHold;

    /**
     * LIMBOFIX2/F-088: the FIXED world-space unit direction the eclipse hangs at —
     * azimuth {@value #ECLIPSE_AZIMUTH_DEG}° to port ({@code −Z}) of the {@code +X}
     * buoy-lane heading (F-088; LIMBOFIX2 had it dead ahead of the bow), elevation
     * {@value #ECLIPSE_ELEVATION_DEG}° above the horizon. Compile-time constant: no
     * camera term can ever re-aim the disc. Never mutated after class init. Unit length
     * by construction ({@code cos²el·(cos²az + sin²az) + sin²el = 1}).
     */
    private static final Vector3f CELESTIAL_DIR = new Vector3f(
            Mth.cos(ECLIPSE_ELEVATION_DEG * ((float) Math.PI / 180.0F))
                    * Mth.cos(ECLIPSE_AZIMUTH_DEG * ((float) Math.PI / 180.0F)),
            Mth.sin(ECLIPSE_ELEVATION_DEG * ((float) Math.PI / 180.0F)),
            -Mth.cos(ECLIPSE_ELEVATION_DEG * ((float) Math.PI / 180.0F))
                    * Mth.sin(ECLIPSE_AZIMUTH_DEG * ((float) Math.PI / 180.0F)));
    /** Rotation mapping the celestial plane's local {@code +Y} onto {@link #CELESTIAL_DIR}. */
    private static final Quaternionf CELESTIAL_ROT = new Quaternionf().rotationTo(
            0.0F, 1.0F, 0.0F, CELESTIAL_DIR.x, CELESTIAL_DIR.y, CELESTIAL_DIR.z);
    /** Game time of the last drift-cue spawn (C2 sailing illusion throttle). */
    private static long lastDriftCueGameTime = Long.MIN_VALUE;

    /** Cached zenith world point; rebuilt only when the anchor/spawn source moves. */
    private static Vec3 zenithPoint = Vec3.ZERO;
    private static double zenithSrcX = Double.NaN;
    private static double zenithSrcY = Double.NaN;
    private static double zenithSrcZ = Double.NaN;

    public LimboSpecialEffects() {
        // No clouds, no ground fog wrap, no vanilla sky shape; lightmap stays natural.
        super(Float.NaN, false, DimensionSpecialEffects.SkyType.NONE, false, false);
    }

    /** R4 (limbo): clouds are fully disabled — report handled so vanilla draws nothing. */
    @Override
    public boolean renderClouds(ClientLevel level, int ticks, float partialTick, PoseStack poseStack,
            double camX, double camY, double camZ, Matrix4f modelViewMatrix, Matrix4f projectionMatrix) {
        return true;
    }

    @Override
    public Vec3 getBrightnessDependentFogColor(Vec3 fogColor, float brightness) {
        // Crush fog toward black like the End so the horizon melts into the void.
        return fogColor.scale(0.15);
    }

    @Override
    public boolean isFoggyAt(int x, int y) {
        return false;
    }

    /**
     * The FIXED world-space unit direction the eclipse disc + aura hang at (LIMBOFIX2).
     * Consumed by {@code veilfx.LimboAmbience}'s {@code GodrayDir} feeder so the
     * screen-space god rays radiate from the exact direction the sky pass draws the disc
     * at. Shared read-only instance — never mutate, never store.
     */
    public static Vector3f celestialDirection() {
        return CELESTIAL_DIR;
    }

    /**
     * The ship-anchor reference point: {@value #ZENITH_HEIGHT} blocks above the ship deck
     * anchor ({@code eclipse:ship_deck}), or above the shared spawn until P6 publishes the
     * anchor. LIMBOFIX2: the disc no longer draws toward this point (it hangs at the fixed
     * {@link #celestialDirection}); this remains the seam for {@link #clientWaterlineY}
     * and {@code veilfx.LimboAmbience}'s ship-relative FX (soul shoal).
     * Returns a cached immutable {@link Vec3}, rebuilt only when the source position moves.
     */
    public static Vec3 zenithWorldPoint(ClientLevel level) {
        Vec3 anchor = FxAnchors.get(FxAnchors.SHIP_DECK);
        double sx;
        double sy;
        double sz;
        if (anchor != null) {
            sx = anchor.x;
            sy = anchor.y;
            sz = anchor.z;
        } else {
            // Shared spawn: sits at the ship's x/z in the shipped limbo setup (ship centered
            // on 0,0). Y barely matters against ZENITH_HEIGHT.
            var spawn = level.getSharedSpawnPos();
            sx = spawn.getX() + 0.5D;
            sy = spawn.getY();
            sz = spawn.getZ() + 0.5D;
        }
        if (sx != zenithSrcX || sy != zenithSrcY || sz != zenithSrcZ) {
            zenithSrcX = sx;
            zenithSrcY = sy;
            zenithSrcZ = sz;
            zenithPoint = new Vec3(sx, sy + ZENITH_HEIGHT, sz);
        }
        return zenithPoint;
    }

    /**
     * Client-side limbo waterline: the Y of the top water block of the limbo ocean. The
     * {@code ship_deck} anchor publishes {@code deckY + 1} and deck = waterline + 3
     * ({@code GhostShipBuilder} frozen contract), so the value is
     * {@code GhostShipBuilder.waterlineY} reaching the client through the anchor sync —
     * ONE seam shared by the C1 {@code WaterlineY} post uniform (via
     * {@code veilfx.LimboAmbience}) and the drift-cue lane.
     */
    public static double clientWaterlineY(ClientLevel level) {
        return zenithWorldPoint(level).y - ZENITH_HEIGHT - 4.0D;
    }

    @Override
    public boolean renderSky(ClientLevel level, int ticks, float partialTick, Matrix4f modelViewMatrix,
            Camera camera, Matrix4f projectionMatrix, boolean isFoggy, Runnable setupFog) {
        if (EclipseIrisState.shaderPackActive()) {
            return false; // shaderpack owns the sky
        }
        setupFog.run();
        if (isFoggy) {
            return true;
        }
        FogType fogType = camera.getFluidInCamera();
        if (fogType == FogType.POWDER_SNOW || fogType == FogType.LAVA
                || OverworldPurpleEffects.mobEffectBlocksSky(camera)) {
            return true;
        }

        PoseStack poseStack = new PoseStack();
        poseStack.mulPose(modelViewMatrix);

        // near-black dome
        FogRenderer.levelFogColor();
        RenderSystem.depthMask(false);
        RenderSystem.setShader(GameRenderer::getPositionShader);
        RenderSystem.setShaderColor(0.015F, 0.02F, 0.03F, 1.0F);
        SkyRenderUtil.drawSkyDisc(poseStack.last().pose(), 16.0F);

        RenderSystem.enableBlend();

        // sparse green star points (no fog so they stay crisp)
        RenderSystem.setShaderColor(0.35F, 0.9F, 0.45F, 0.85F);
        FogRenderer.setupNoFog();
        GREEN_STARS.draw(poseStack.last().pose(), projectionMatrix);
        // IDEA-18 §2: horizon silhouette ships share the stars' no-fog window.
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableCull();
        LimboHorizonShips.draw(poseStack.last().pose(), level, camera);
        // F-104 (IDEA-18 §9): the shooting streak shares the ships' no-fog window and
        // shader, but draws OUTSIDE the zenith rotation push below — it streaks the
        // dome, not the disc frame. Additive like a light trail; blend restored before
        // the window closes.
        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        RenderSystem.blendFuncSeparate(
                GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        drawShootingStreaks(poseStack.last().pose(), seconds);
        RenderSystem.defaultBlendFunc();
        RenderSystem.enableCull();

        // --- eclipse disc + aura: a FIXED celestial direction (LIMBOFIX2) -------------------
        // Drawn INSIDE the stars' no-fog window with the depth test off, at effectively
        // infinite distance (fixed angular size at SKY_DISTANCE). The transform contains
        // ZERO camera terms: the only camera dependence is the view rotation already baked
        // into the passed modelViewMatrix — exactly like the vanilla sun/moon. Rotating or
        // walking cannot move, re-aim or spin the disc; it pans across the screen like any
        // real celestial object.
        Vec3 cam = camera.getPosition();

        poseStack.pushPose();
        poseStack.mulPose(CELESTIAL_ROT);
        Matrix4f zenithPose = poseStack.last().pose();

        // Subtle dual-frequency aura pulse — primary 1.3 rad/s matches the post shader's
        // sea-breathing curve exactly (limbo.fsh), so the two can never desync.
        // (seconds is captured once above, before the streak draw — same hourly clock.)
        float pulse = 0.85F + 0.11F * Mth.sin(seconds * 1.3F)
                + 0.04F * Mth.sin(seconds * 0.37F + 1.7F);
        // v4 breathing corona: the glow fan swells ±5% on a slow independent cycle and
        // dims slightly while expanded (a corona thins as it grows) — layered UNDER the
        // alpha pulse, so the two periods beat against each other organically.
        float breath = 1.0F + 0.05F * Mth.sin(seconds * CORONA_BREATH_RATE + 0.9F);

        RenderSystem.disableDepthTest();

        // additive aura: glow floor first, then the two counter-rotating ray layers
        RenderSystem.blendFuncSeparate(
                GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        // v4.1: aurora veils first — the farthest sheet, everything else layers over it
        // (additive is commutative, but background-first order is free clarity).
        if (!EclipseClientConfig.reducedFx()) {
            drawAuroraVeils(zenithPose, seconds, pulse);
        }
        drawAuraGlow(zenithPose, pulse, breath);
        drawAuraRays(zenithPose, seconds, pulse);
        // v4: occasional coronal-mass wisp — drawn after the rays so the disc core still
        // occludes its root; garnish tier, so reducedFx skips it entirely.
        if (!EclipseClientConfig.reducedFx()) {
            drawCoronalWisp(zenithPose, seconds, pulse);
        }

        // the eclipse disc itself, alpha-blended so its black core occludes the ray roots
        RenderSystem.defaultBlendFunc();
        RenderSystem.setShader(GameRenderer::getPositionTexShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.setShaderTexture(0, ECLIPSE_TEXTURE);
        SkyRenderUtil.drawCelestialQuad(zenithPose, DISC_SIZE, SKY_DISTANCE);
        poseStack.popPose();

        RenderSystem.enableDepthTest();
        setupFog.run();

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
        RenderSystem.depthMask(true);

        // C2 (item 6, world half): mist bands + foam glints streaming astern past the hull.
        spawnDriftCues(level, cam);
        return true;
    }

    /**
     * C2 (item 6, world half) — sparse sailing cues: low mist bands (campfire smoke —
     * long-lived and velocity-honoring) plus occasional faint foam glints (end rod)
     * streaming astern (−X, the buoy-lane heading) just above the water surface. Purely
     * cosmetic and client-side, throttled by game time (this runs from the per-frame render
     * hook); {@code reducedFx} doubles the cadence and halves the density.
     */
    private static void spawnDriftCues(ClientLevel level, Vec3 cam) {
        long gameTime = level.getGameTime();
        boolean reduced = EclipseClientConfig.reducedFx();
        int interval = reduced ? DRIFT_CUE_INTERVAL_TICKS * 2 : DRIFT_CUE_INTERVAL_TICKS;
        long sinceLast = gameTime - lastDriftCueGameTime;
        if (lastDriftCueGameTime != Long.MIN_VALUE && sinceLast >= 0L && sinceLast < interval) {
            return;
        }
        lastDriftCueGameTime = gameTime;
        RandomSource random = level.random;
        double surfaceY = clientWaterlineY(level) + 1.0D;
        int bands = reduced ? 1 : 2;
        for (int i = 0; i < bands; i++) {
            // Spawned ahead/abeam so the astern drift visibly carries the band past the hull.
            double x = cam.x - 8.0D + random.nextDouble() * 44.0D;
            double z = cam.z + (random.nextBoolean() ? 1.0D : -1.0D)
                    * (5.0D + random.nextDouble() * 20.0D);
            level.addParticle(ParticleTypes.CAMPFIRE_COSY_SMOKE, x, surfaceY + 0.2D, z,
                    -DRIFT_CUE_SPEED * (0.8D + random.nextDouble() * 0.4D), 0.004D, 0.0D);
        }
        if (!reduced && random.nextInt(3) == 0) {
            double x = cam.x - 4.0D + random.nextDouble() * 30.0D;
            double z = cam.z + (random.nextBoolean() ? 1.0D : -1.0D)
                    * (4.0D + random.nextDouble() * 12.0D);
            level.addParticle(ParticleTypes.END_ROD, x, surfaceY + 0.05D, z,
                    -DRIFT_CUE_SPEED * 1.1D, 0.0D, 0.0D);
        }
    }

    /**
     * Soft radial glow fan behind the disc: violet center fading to nothing at the rim.
     * v4: the fan radius breathes with {@code breath} (±5%, ~27 s) and the center alpha
     * dims as it expands — energy conservation makes the breathing read physical instead
     * of like a scale wobble. F-088: center alpha 0.30 → 0.20 and the center hue pulled
     * off pink toward deep violet (less red), part of the aura-to-accent rescale.
     */
    private static void drawAuraGlow(Matrix4f pose, float pulse, float breath) {
        float radius = GLOW_RADIUS * breath;
        float centerAlpha = 0.20F * pulse * (1.96F - breath);
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION_COLOR);
        builder.addVertex(pose, 0.0F, SKY_DISTANCE, 0.0F)
                .setColor(0.42F, 0.20F, 0.92F, centerAlpha);
        for (int i = 0; i <= GLOW_SEGMENTS; i++) {
            float angle = (float) i / GLOW_SEGMENTS * ((float) Math.PI * 2.0F);
            builder.addVertex(pose, Mth.cos(angle) * radius, SKY_DISTANCE, Mth.sin(angle) * radius)
                    .setColor(0.35F, 0.10F, 0.70F, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * v4.1 — aurora veils: three soul-green partial-arc curtains drifting slowly around
     * the zenith at extreme radius (beyond the glow floor), framing the eclipse the way
     * polar bands frame a winter moon. Each curtain is {@value #AURORA_SEGMENTS} gradient
     * quads along its arc: the OUTER edge (farther from the zenith = lower in the sky) is
     * the sharp bright aurora foot, feathering to nothing toward the zenith; the foot
     * radius undulates on a slow 3-lobe wave and the per-segment brightness carries a
     * curtain-ray shimmer, so the band folds like drapery instead of reading as a ring
     * segment. Alpha peaks mid-arc (sin envelope — the arc ends feather out) and breathes
     * with the shared corona {@code pulse} plus a slow per-veil cycle. Soul-green fading
     * to violet ties the veils to the stars/glints palette. Pure function of the hourly
     * wall-clock {@code seconds} — deterministic, identical on every client, no state.
     * Garnish tier: the caller skips it under {@code reducedFx} (the wisp ladder).
     */
    private static void drawAuroraVeils(Matrix4f pose, float seconds, float pulse) {
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < AURORA_VEILS; v++) {
            float span = AURORA_SPAN[v];
            float azStart = AURORA_AZIMUTH[v] + seconds * AURORA_DRIFT[v] - span * 0.5F;
            float footRadius = AURORA_BASE_RADIUS + v * AURORA_RADIUS_STEP;
            // Slow per-veil breathing (non-commensurate rates) under the shared pulse.
            float veilAlpha = AURORA_PEAK_ALPHA * pulse
                    * (0.75F + 0.25F * Mth.sin(seconds * (0.09F + 0.02F * v) + v * 2.1F));
            for (int i = 0; i < AURORA_SEGMENTS; i++) {
                float t0 = (float) i / AURORA_SEGMENTS;
                float t1 = (float) (i + 1) / AURORA_SEGMENTS;
                float a0 = azStart + t0 * span;
                float a1 = azStart + t1 * span;
                // 3-lobe undulation of the curtain foot + a slow travelling fold
                // (LIMBOFIX2: amplitude 9 → 5, part of the horizon-clearance rescale).
                float r0 = footRadius + 5.0F * Mth.sin(a0 * 3.0F + seconds * 0.13F + v);
                float r1 = footRadius + 5.0F * Mth.sin(a1 * 3.0F + seconds * 0.13F + v);
                // Mid-arc alpha envelope × curtain-ray shimmer (per-edge, so quads share
                // edge values and the strip stays C0 — no banding between segments).
                float e0 = Mth.sin(t0 * (float) Math.PI)
                        * (0.70F + 0.30F * Mth.sin(a0 * 7.0F + seconds * 0.9F + v * 3.3F));
                float e1 = Mth.sin(t1 * (float) Math.PI)
                        * (0.70F + 0.30F * Mth.sin(a1 * 7.0F + seconds * 0.9F + v * 3.3F));
                float alpha0 = veilAlpha * e0;
                float alpha1 = veilAlpha * e1;
                float cos0 = Mth.cos(a0);
                float sin0 = Mth.sin(a0);
                float cos1 = Mth.cos(a1);
                float sin1 = Mth.sin(a1);
                // Bright foot edge (outer) → feathered zenith-side fade (inner).
                builder.addVertex(pose, cos0 * r0, SKY_DISTANCE, sin0 * r0)
                        .setColor(0.30F, 0.90F, 0.55F, alpha0);
                builder.addVertex(pose, cos1 * r1, SKY_DISTANCE, sin1 * r1)
                        .setColor(0.30F, 0.90F, 0.55F, alpha1);
                builder.addVertex(pose, cos1 * (r1 - AURORA_BAND_DEPTH), SKY_DISTANCE,
                                sin1 * (r1 - AURORA_BAND_DEPTH))
                        .setColor(0.40F, 0.30F, 0.85F, 0.0F);
                builder.addVertex(pose, cos0 * (r0 - AURORA_BAND_DEPTH), SKY_DISTANCE,
                                sin0 * (r0 - AURORA_BAND_DEPTH))
                        .setColor(0.40F, 0.30F, 0.85F, 0.0F);
            }
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * v4 — an occasional coronal-mass wisp: a faint curved plume that detaches from the
     * disc rim and dissolves outward. Deterministic ({@link LimboHorizonShips#hash01}, the
     * shared {@code ECLIPSE_SEED} mixer with wisp-specific salts): each
     * {@value #WISP_SLOT_SECONDS}-second slot of the hourly clock either hosts one wisp
     * (~45%) or none; azimuth, curl side and start offset are slot-hashed. Two chained
     * quads (root→mid→tip) with the mid bulging perpendicular — the classic CME loop —
     * growing with an ease-out and fading on a sin-in-out envelope, peak alpha
     * {@value #WISP_PEAK_ALPHA}·pulse. The root sits inside the disc silhouette
     * ({@code RAY_INNER_RADIUS}), so the black core occludes it like the ray roots.
     */
    private static void drawCoronalWisp(Matrix4f pose, float seconds, float pulse) {
        int slot = (int) (seconds / WISP_SLOT_SECONDS);
        if (LimboHorizonShips.hash01(slot * 31 + 5, 977) >= 0.45D) {
            return;
        }
        float start = (float) (LimboHorizonShips.hash01(slot * 31 + 6, 977)
                * (WISP_SLOT_SECONDS - WISP_DURATION_SECONDS - 1.0F));
        float t01 = (seconds - slot * WISP_SLOT_SECONDS - start) / WISP_DURATION_SECONDS;
        if (t01 <= 0.0F || t01 >= 1.0F) {
            return;
        }
        float grow = 1.0F - (1.0F - t01) * (1.0F - t01); // ease-out reach
        float alpha = WISP_PEAK_ALPHA * Mth.sin(t01 * (float) Math.PI) * pulse;
        float angle = (float) (LimboHorizonShips.hash01(slot * 31 + 7, 977) * Math.PI * 2.0D);
        float curl = LimboHorizonShips.hash01(slot * 31 + 8, 977) < 0.5D ? -1.0F : 1.0F;

        float dirX = Mth.cos(angle);
        float dirZ = Mth.sin(angle);
        float perpX = -dirZ * curl;
        float perpZ = dirX * curl;
        float reach = WISP_REACH * grow;
        float r0 = RAY_INNER_RADIUS;
        float r1 = RAY_INNER_RADIUS + reach * 0.5F;
        float r2 = RAY_INNER_RADIUS + reach;
        // The plume bows sideways as it extends (the detached-loop read).
        float bow1 = reach * 0.18F;
        float bow2 = reach * 0.55F;
        float w0 = 5.0F;
        float w1 = 8.0F;
        float w2 = 2.5F;

        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        // root → mid
        builder.addVertex(pose, dirX * r0 - perpX * w0, SKY_DISTANCE, dirZ * r0 - perpZ * w0)
                .setColor(0.82F, 0.50F, 1.0F, alpha);
        builder.addVertex(pose, dirX * r0 + perpX * w0, SKY_DISTANCE, dirZ * r0 + perpZ * w0)
                .setColor(0.82F, 0.50F, 1.0F, alpha);
        builder.addVertex(pose, dirX * r1 + perpX * (w1 + bow1), SKY_DISTANCE,
                        dirZ * r1 + perpZ * (w1 + bow1))
                .setColor(0.62F, 0.30F, 0.95F, alpha * 0.7F);
        builder.addVertex(pose, dirX * r1 + perpX * (bow1 - w1), SKY_DISTANCE,
                        dirZ * r1 + perpZ * (bow1 - w1))
                .setColor(0.62F, 0.30F, 0.95F, alpha * 0.7F);
        // mid → tip
        builder.addVertex(pose, dirX * r1 + perpX * (bow1 - w1), SKY_DISTANCE,
                        dirZ * r1 + perpZ * (bow1 - w1))
                .setColor(0.62F, 0.30F, 0.95F, alpha * 0.7F);
        builder.addVertex(pose, dirX * r1 + perpX * (w1 + bow1), SKY_DISTANCE,
                        dirZ * r1 + perpZ * (w1 + bow1))
                .setColor(0.62F, 0.30F, 0.95F, alpha * 0.7F);
        builder.addVertex(pose, dirX * r2 + perpX * (bow2 + w2), SKY_DISTANCE,
                        dirZ * r2 + perpZ * (bow2 + w2))
                .setColor(0.45F, 0.15F, 0.85F, 0.0F);
        builder.addVertex(pose, dirX * r2 + perpX * (bow2 - w2), SKY_DISTANCE,
                        dirZ * r2 + perpZ * (bow2 - w2))
                .setColor(0.45F, 0.15F, 0.85F, 0.0F);
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * F-104 (IDEA-18 §9) — the green shooting streak. Live path: deterministic slot
     * schedule over the hourly second clock ({@link LimboHorizonShips#hash01}, own
     * salts — every client sees the same streak at the same wall-clock second); at most
     * one streak is ever on screen. Dev path ({@code streakHold}): one streak frozen at
     * the fixed {@link #STREAK_HOLD_AZIMUTH}/{@link #STREAK_HOLD_ELEVATION} spot with
     * the envelope pinned at {@value #STREAK_HOLD_T01} — bit-identical geometry every
     * frame until {@code off} restores the live schedule with no residue. The live
     * schedule is garnish tier ({@code reducedFx} skips — the wisp ladder); the hold is
     * an explicit operator override and draws regardless, like a forced pipeline.
     * Pure scalar math — no per-frame allocations (§3.5).
     */
    private static void drawShootingStreaks(Matrix4f pose, float seconds) {
        if (streakHold) {
            emitStreak(pose, STREAK_HOLD_AZIMUTH, STREAK_HOLD_ELEVATION, STREAK_AZ_SWEEP,
                    STREAK_HOLD_T01);
            return;
        }
        if (EclipseClientConfig.reducedFx()) {
            return;
        }
        int slot = (int) (seconds / STREAK_SLOT_SECONDS);
        if (LimboHorizonShips.hash01(slot * 37 + 3, 1553) >= 0.5D) {
            return;
        }
        float start = (float) (LimboHorizonShips.hash01(slot * 37 + 4, 1553)
                * (STREAK_SLOT_SECONDS - STREAK_DURATION_SECONDS - 1.0F));
        float t01 = (seconds - slot * STREAK_SLOT_SECONDS - start) / STREAK_DURATION_SECONDS;
        if (t01 <= 0.0F || t01 >= 1.0F) {
            return;
        }
        float azimuth = (float) (LimboHorizonShips.hash01(slot * 37 + 5, 1553) * Math.PI * 2.0D);
        float elevation = STREAK_EL_MIN
                + (float) LimboHorizonShips.hash01(slot * 37 + 6, 1553) * STREAK_EL_RANGE;
        float sweep = (LimboHorizonShips.hash01(slot * 37 + 7, 1553) < 0.5D ? -1.0F : 1.0F)
                * STREAK_AZ_SWEEP;
        emitStreak(pose, azimuth, elevation, sweep, t01);
    }

    /**
     * One tapered additive quad from tail to head, both riding the dome sphere: the
     * path runs from {@code (az0, el0)} to {@code (az0+azSweep, el0−STREAK_EL_DROP)},
     * points are chord-lerped and renormalized to {@value #SKY_DISTANCE} (over ≤35° of
     * arc the chord shortening is invisible). The head is the bright leading edge
     * (alpha {@value #STREAK_PEAK_ALPHA}·sin-envelope, near-white green); the tail is
     * fully transparent star-green, so the wedge reads as a fading trail. Width sits
     * perpendicular to both the path and the view ray ({@code cross(path, radial)}).
     */
    private static void emitStreak(Matrix4f pose, float az0, float el0, float azSweep, float t01) {
        float az1 = az0 + azSweep;
        float el1 = el0 - STREAK_EL_DROP;
        float x0 = Mth.cos(el0) * Mth.cos(az0);
        float y0 = Mth.sin(el0);
        float z0 = Mth.cos(el0) * Mth.sin(az0);
        float x1 = Mth.cos(el1) * Mth.cos(az1);
        float y1 = Mth.sin(el1);
        float z1 = Mth.cos(el1) * Mth.sin(az1);

        float tTail = Math.max(0.0F, t01 - STREAK_TAIL_FRAC);
        float hx = Mth.lerp(t01, x0, x1);
        float hy = Mth.lerp(t01, y0, y1);
        float hz = Mth.lerp(t01, z0, z1);
        float hInv = SKY_DISTANCE / (float) Math.sqrt(hx * hx + hy * hy + hz * hz);
        hx *= hInv;
        hy *= hInv;
        hz *= hInv;
        float tx = Mth.lerp(tTail, x0, x1);
        float ty = Mth.lerp(tTail, y0, y1);
        float tz = Mth.lerp(tTail, z0, z1);
        float tInv = SKY_DISTANCE / (float) Math.sqrt(tx * tx + ty * ty + tz * tz);
        tx *= tInv;
        ty *= tInv;
        tz *= tInv;

        float px = hx - tx;
        float py = hy - ty;
        float pz = hz - tz;
        float pLen = (float) Math.sqrt(px * px + py * py + pz * pz);
        if (pLen < 1.0E-3F) {
            return; // degenerate first instants — nothing worth a draw yet
        }
        px /= pLen;
        py /= pLen;
        pz /= pLen;
        // Width axis: perpendicular to the path AND the view ray (radial ≈ head/|head|).
        float rx = hx / SKY_DISTANCE;
        float ry = hy / SKY_DISTANCE;
        float rz = hz / SKY_DISTANCE;
        float wx = py * rz - pz * ry;
        float wy = pz * rx - px * rz;
        float wz = px * ry - py * rx;
        float wLen = (float) Math.sqrt(wx * wx + wy * wy + wz * wz);
        if (wLen < 1.0E-4F) {
            return;
        }
        wx /= wLen;
        wy /= wLen;
        wz /= wLen;

        float alpha = STREAK_PEAK_ALPHA * Mth.sin(t01 * (float) Math.PI);
        float headW = STREAK_HEAD_HALF_WIDTH;
        float tailW = headW * STREAK_TAIL_WIDTH_FRAC;

        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        // Tail edge: transparent star-green; head edge: bright near-white green.
        builder.addVertex(pose, tx - wx * tailW, ty - wy * tailW, tz - wz * tailW)
                .setColor(0.35F, 0.9F, 0.45F, 0.0F);
        builder.addVertex(pose, tx + wx * tailW, ty + wy * tailW, tz + wz * tailW)
                .setColor(0.35F, 0.9F, 0.45F, 0.0F);
        builder.addVertex(pose, hx + wx * headW, hy + wy * headW, hz + wz * headW)
                .setColor(0.72F, 1.0F, 0.82F, alpha);
        builder.addVertex(pose, hx - wx * headW, hy - wy * headW, hz - wz * headW)
                .setColor(0.72F, 1.0F, 0.82F, alpha);
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * C7 ({@code /eclipsefx limbo streakhold}, via {@code FxDevClient}): while on, the
     * sky pass draws ONE shooting streak frozen mid-flight at a fixed dome spot instead
     * of the live schedule. The schedule rides the SECOND-based hourly clock —
     * {@code tick rate 2} stretches game ticks, not wall seconds, so a 0.9&nbsp;s streak
     * stays unphotographable on software renderers without this hold. {@code off}
     * restores the shipped path bit-identically (no residue: the hold branch is the
     * only consumer of the flag). Logout clears it (the {@code FxDevClient} hygiene
     * pattern).
     */
    public static void setStreakHold(boolean on) {
        streakHold = on;
    }

    /**
     * The {@value #RAY_COUNT}-ray aura fan: two 6-ray layers counter-rotating at
     * ±{@value #RAY_SPIN_DEG_PER_SEC} °/s (v4: slowed from 1.2 — a drift you only notice
     * by staring). Each ray is a tapered additive wedge from just inside the disc
     * silhouette out to its own length, root alpha {@value #RAY_ALPHA}·pulse fading to
     * zero at the tip. LIMBOFIX2: the v4 layer-B walk-parallax offset is GONE — it was a
     * camera-position term, and the whole point of the fix is that NO camera term may
     * move any part of the celestial group.
     */
    private static void drawAuraRays(Matrix4f pose, float seconds, float pulse) {
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        float spin = seconds * RAY_SPIN_DEG_PER_SEC;
        for (int i = 0; i < RAY_COUNT; i++) {
            boolean layerB = i >= RAYS_PER_LAYER;
            int slot = layerB ? i - RAYS_PER_LAYER : i;
            float baseDeg = slot * (360.0F / RAYS_PER_LAYER) + (layerB ? 30.0F - spin : spin);
            float angle = baseDeg * ((float) Math.PI / 180.0F);
            float dirX = Mth.cos(angle);
            float dirZ = Mth.sin(angle);
            // perpendicular in the celestial plane
            float perpX = -dirZ;
            float perpZ = dirX;

            float rootW = RAY_WIDTHS[i];
            float tipW = rootW * 0.12F;
            float r0 = RAY_INNER_RADIUS;
            float r1 = RAY_INNER_RADIUS + RAY_LENGTHS[i];
            float rootAlpha = RAY_ALPHA * pulse * (layerB ? 0.85F : 1.0F);

            builder.addVertex(pose, dirX * r0 - perpX * rootW, SKY_DISTANCE,
                            dirZ * r0 - perpZ * rootW)
                    .setColor(0.78F, 0.42F, 1.0F, rootAlpha);
            builder.addVertex(pose, dirX * r0 + perpX * rootW, SKY_DISTANCE,
                            dirZ * r0 + perpZ * rootW)
                    .setColor(0.78F, 0.42F, 1.0F, rootAlpha);
            builder.addVertex(pose, dirX * r1 + perpX * tipW, SKY_DISTANCE,
                            dirZ * r1 + perpZ * tipW)
                    .setColor(0.45F, 0.15F, 0.85F, 0.0F);
            builder.addVertex(pose, dirX * r1 - perpX * tipW, SKY_DISTANCE,
                            dirZ * r1 - perpZ * tipW)
                    .setColor(0.45F, 0.15F, 0.85F, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }
}
