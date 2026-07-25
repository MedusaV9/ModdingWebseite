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
 *   <li><b>Parallax-layered aura rays</b>: the spin is slowed to
 *       {@value #RAY_SPIN_DEG_PER_SEC}&nbsp;°/s and layer B (the counter-rotating one) is
 *       offset opposite the camera's walk offset from the ship anchor
 *       ({@value #RAY_PARALLAX}, clamped) — the two fans read as depth-separated sheets
 *       when the player moves on deck. The disc quad itself is untouched (C2 stability).</li>
 * </ul>
 *
 * <p>LIMBOFIX: the C2/v4 water-reflection streak is GONE. Standing almost directly under
 * the zenith made the mirrored direction's azimuth numerically degenerate — tiny camera
 * moves swung the streak wildly (the "giant purple thing rotates with the player" bug) and
 * it drew through the hull with the depth test off. The post-shader smear went with it
 * (limbo.fsh); the water simply shows no disc reflection now.</p>
 *
 * <p>v4.1 (VEIL-REPASS-2): <b>aurora veils</b> ({@link #drawAuroraVeils}) — three slow
 * soul-green polar-light curtains drifting around the zenith beyond the glow floor,
 * framing the eclipse at extreme altitude. Garnish tier (skipped under {@code reducedFx},
 * the wisp ladder); pure function of the hourly clock, so every client sees the same sky.</p>
 *
 * <p>The same zenith point feeds the {@code eclipse:limbo} post pipeline's {@code GodrayDir}
 * uniform (see {@code veilfx.LimboAmbience}), so the screen-space god rays and the sky-pass
 * aura radiate from one source of truth and cannot diverge.</p>
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
    /** R5: 1.5× the v1 disc (35 → 52.5 half-extent). */
    private static final float DISC_SIZE = 52.5F;
    /**
     * Virtual altitude of the eclipse above the ship-deck anchor. High enough that the disc
     * stays "overhead" across the whole play area around the ship, low enough that it visibly
     * hangs over the ship rather than following the camera like a skybox decal.
     */
    private static final double ZENITH_HEIGHT = 480.0D;

    /** Aura ray fan: 12 rays in two counter-rotating 6-ray layers (R5 freeze). */
    private static final int RAY_COUNT = 12;
    private static final int RAYS_PER_LAYER = RAY_COUNT / 2;
    /** v4: VERY slow spin (was 1.2 °/s) — barely-perceptible drift; layer B counter-spins. */
    private static final float RAY_SPIN_DEG_PER_SEC = 0.35F;
    /**
     * v4 parallax depth layering: ray layer B is offset opposite the camera's horizontal
     * walk offset from the ship anchor by this factor (celestial-plane units per block,
     * clamped to ±{@value #RAY_PARALLAX_MAX}). Layer A stays locked to the disc — the two
     * fans separate into near/far sheets as the player moves, and converge again at the
     * anchor. Zero effect on the disc quad itself (the C2 stability freeze).
     */
    private static final float RAY_PARALLAX = 0.06F;
    private static final float RAY_PARALLAX_MAX = 5.0F;
    /** Rays start slightly inside the disc silhouette so their roots hide behind it. */
    private static final float RAY_INNER_RADIUS = 30.0F;
    /** Peak root alpha of a ray (plan: additive, 0.4 alpha). */
    private static final float RAY_ALPHA = 0.4F;
    /** Deterministic per-ray lengths (40–120 units) and root half-widths. */
    private static final float[] RAY_LENGTHS = {
            118.0F, 62.0F, 94.0F, 47.0F, 108.0F, 71.0F,
            55.0F, 101.0F, 43.0F, 86.0F, 66.0F, 120.0F};
    private static final float[] RAY_WIDTHS = {
            7.5F, 5.0F, 6.5F, 4.2F, 7.0F, 5.6F,
            4.6F, 6.8F, 4.0F, 6.0F, 5.2F, 7.8F};

    /** Radial glow fan behind the disc (the aura "floor"). */
    private static final float GLOW_RADIUS = 135.0F;
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
    /** Wisp reach beyond the disc rim (units in the celestial plane) when fully extended. */
    private static final float WISP_REACH = 62.0F;

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
    /** Innermost veil center radius; each further veil steps {@value #AURORA_RADIUS_STEP} out. */
    private static final float AURORA_BASE_RADIUS = 152.0F;
    private static final float AURORA_RADIUS_STEP = 26.0F;
    /** Radial depth of a curtain (bright outer edge → feathered inner fade). */
    private static final float AURORA_BAND_DEPTH = 34.0F;
    /** Peak alpha of a curtain's bright edge (before pulse/envelope shaping). */
    private static final float AURORA_PEAK_ALPHA = 0.085F;
    /** Per-veil azimuth drift speeds (rad/s) — non-commensurate, so veils never lock step. */
    private static final float[] AURORA_DRIFT = {0.011F, -0.008F, 0.014F};
    /** Per-veil arc spans (radians, ~70–110°). */
    private static final float[] AURORA_SPAN = {1.9F, 1.35F, 1.6F};
    /** Per-veil base azimuths (radians) — spread so the veils frame, never encircle. */
    private static final float[] AURORA_AZIMUTH = {0.6F, 2.9F, 4.6F};

    /**
     * C2: per-frame low-pass factor for the disc direction. Kills single-frame pops (anchor
     * republish, degenerate snap, ship bob) while converging within ~10 frames — walking
     * parallax stays imperceptible, jitter cannot.
     */
    private static final float DIR_SMOOTHING = 0.2F;

    /** C2 sailing cues: ticks between drift-cue spawns (doubled under reducedFx). */
    private static final int DRIFT_CUE_INTERVAL_TICKS = 3;
    /** Mist bands/foam glints stream astern at this speed (blocks/t, −X = astern). */
    private static final float DRIFT_CUE_SPEED = 0.22F;

    // Pre-allocated render scratch (§3.5: no per-frame heap allocations in render loops).
    private static final Quaternionf ZENITH_ROT = new Quaternionf();
    private static final Vector3f ZENITH_DIR = new Vector3f();
    /** Low-pass filtered disc direction (C2); world axes, unit length. */
    private static final Vector3f SMOOTH_DIR = new Vector3f();
    private static boolean hasSmoothDir;
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
     * The world point the eclipse hangs at: {@value #ZENITH_HEIGHT} blocks above the ship
     * deck anchor ({@code eclipse:ship_deck}), or above the shared spawn until P6 publishes
     * the anchor. Also consumed by {@code veilfx.LimboAmbience}'s {@code GodrayDir} feeder so
     * the post god-rays radiate from the exact same spot the sky pass draws the disc at.
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
        RenderSystem.enableCull();

        // --- eclipse disc + aura: a stable camera-relative celestial (C2) -------------------
        // Drawn INSIDE the stars' no-fog window with the depth test off, at effectively
        // infinite distance (normalized direction, fixed angular size at SKY_DISTANCE): no
        // parallax jitter, no fog/horizon-plane pops, no clipping.
        Vec3 zenith = zenithWorldPoint(level);
        Vec3 cam = camera.getPosition();
        ZENITH_DIR.set((float) (zenith.x - cam.x), (float) (zenith.y - cam.y), (float) (zenith.z - cam.z));
        if (ZENITH_DIR.lengthSquared() < 1.0E-4F || ZENITH_DIR.y <= 0.0F) {
            ZENITH_DIR.set(0.0F, 1.0F, 0.0F); // degenerate (camera above the zenith point)
        }
        ZENITH_DIR.normalize();
        // Low-pass the direction: a snap only on the first frame or a genuinely new source
        // (dimension change / anchor jump); otherwise any per-frame pop is eased away.
        if (!hasSmoothDir || SMOOTH_DIR.dot(ZENITH_DIR) < 0.5F) {
            SMOOTH_DIR.set(ZENITH_DIR);
            hasSmoothDir = true;
        } else {
            SMOOTH_DIR.lerp(ZENITH_DIR, DIR_SMOOTHING).normalize();
        }
        ZENITH_ROT.rotationTo(0.0F, 1.0F, 0.0F, SMOOTH_DIR.x, SMOOTH_DIR.y, SMOOTH_DIR.z);

        poseStack.pushPose();
        poseStack.mulPose(ZENITH_ROT);
        Matrix4f zenithPose = poseStack.last().pose();

        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        // Subtle dual-frequency aura pulse — primary 1.3 rad/s matches the post shader's
        // sea-breathing curve exactly (limbo.fsh), so the two can never desync.
        float pulse = 0.85F + 0.11F * Mth.sin(seconds * 1.3F)
                + 0.04F * Mth.sin(seconds * 0.37F + 1.7F);
        // v4 breathing corona: the glow fan swells ±5% on a slow independent cycle and
        // dims slightly while expanded (a corona thins as it grows) — layered UNDER the
        // alpha pulse, so the two periods beat against each other organically.
        float breath = 1.0F + 0.05F * Mth.sin(seconds * CORONA_BREATH_RATE + 0.9F);
        // v4 parallax depth layering: layer B shifts opposite the camera's walk offset
        // from the ship anchor (the zenith point's x/z IS the anchor x/z), clamped small.
        float parX = Mth.clamp((float) (cam.x - zenith.x) * -RAY_PARALLAX,
                -RAY_PARALLAX_MAX, RAY_PARALLAX_MAX);
        float parZ = Mth.clamp((float) (cam.z - zenith.z) * -RAY_PARALLAX,
                -RAY_PARALLAX_MAX, RAY_PARALLAX_MAX);

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
        drawAuraRays(zenithPose, seconds, pulse, parX, parZ);
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
     * of like a scale wobble.
     */
    private static void drawAuraGlow(Matrix4f pose, float pulse, float breath) {
        float radius = GLOW_RADIUS * breath;
        float centerAlpha = 0.30F * pulse * (1.96F - breath);
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION_COLOR);
        builder.addVertex(pose, 0.0F, SKY_DISTANCE, 0.0F)
                .setColor(0.55F, 0.22F, 0.95F, centerAlpha);
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
                // 3-lobe undulation of the curtain foot + a slow travelling fold.
                float r0 = footRadius + 9.0F * Mth.sin(a0 * 3.0F + seconds * 0.13F + v);
                float r1 = footRadius + 9.0F * Mth.sin(a1 * 3.0F + seconds * 0.13F + v);
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
     * The {@value #RAY_COUNT}-ray aura fan: two 6-ray layers counter-rotating at
     * ±{@value #RAY_SPIN_DEG_PER_SEC} °/s (v4: slowed from 1.2 — a drift you only notice
     * by staring). Each ray is a tapered additive wedge from just inside the disc
     * silhouette out to its own 40–120-unit length, root alpha {@value #RAY_ALPHA}·pulse
     * fading to zero at the tip. v4: layer B is shifted by the clamped parallax offset
     * {@code (parX, parZ)} — nearer sheet, moves against the camera walk — while layer A
     * stays locked to the disc; the offsets are continuous in camera position, so nothing
     * can pop (the C2 law).
     */
    private static void drawAuraRays(Matrix4f pose, float seconds, float pulse,
            float parX, float parZ) {
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
            // v4 parallax: the whole layer-B fan translates in the celestial plane.
            float offX = layerB ? parX : 0.0F;
            float offZ = layerB ? parZ : 0.0F;

            float rootW = RAY_WIDTHS[i];
            float tipW = rootW * 0.12F;
            float r0 = RAY_INNER_RADIUS;
            float r1 = RAY_INNER_RADIUS + RAY_LENGTHS[i];
            float rootAlpha = RAY_ALPHA * pulse * (layerB ? 0.85F : 1.0F);

            builder.addVertex(pose, offX + dirX * r0 - perpX * rootW, SKY_DISTANCE,
                            offZ + dirZ * r0 - perpZ * rootW)
                    .setColor(0.78F, 0.42F, 1.0F, rootAlpha);
            builder.addVertex(pose, offX + dirX * r0 + perpX * rootW, SKY_DISTANCE,
                            offZ + dirZ * r0 + perpZ * rootW)
                    .setColor(0.78F, 0.42F, 1.0F, rootAlpha);
            builder.addVertex(pose, offX + dirX * r1 + perpX * tipW, SKY_DISTANCE,
                            offZ + dirZ * r1 + perpZ * tipW)
                    .setColor(0.45F, 0.15F, 0.85F, 0.0F);
            builder.addVertex(pose, offX + dirX * r1 - perpX * tipW, SKY_DISTANCE,
                            offZ + dirZ * r1 - perpZ * tipW)
                    .setColor(0.45F, 0.15F, 0.85F, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }
}
