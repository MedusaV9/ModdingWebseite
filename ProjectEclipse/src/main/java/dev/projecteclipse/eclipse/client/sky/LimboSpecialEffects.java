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

import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.DimensionSpecialEffects;
import net.minecraft.client.renderer.FogRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
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
    /** 0.02 °/frame at 60 fps ≈ 1.2 °/s; layer B spins the opposite way. */
    private static final float RAY_SPIN_DEG_PER_SEC = 1.2F;
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

    /** IDEA-18 §1: water-reflection streak shape (elongated fan on the water plane). */
    private static final int STREAK_SEGMENTS = 16;
    private static final float STREAK_MIN_HALF_LEN = 14.0F;
    private static final float STREAK_MAX_HALF_LEN = 55.0F;
    private static final float STREAK_HALF_WIDTH = 5.5F;
    /** The streak fades to nothing this many blocks of camera height above the waterline. */
    private static final double STREAK_FADE_HEIGHT = 70.0D;

    // Pre-allocated render scratch (§3.5: no per-frame heap allocations in render loops).
    private static final Quaternionf ZENITH_ROT = new Quaternionf();
    private static final Vector3f ZENITH_DIR = new Vector3f();

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
        setupFog.run();

        // --- eclipse at the exact zenith over the ship, with its radiating aura -------------
        Vec3 zenith = zenithWorldPoint(level);
        Vec3 cam = camera.getPosition();
        ZENITH_DIR.set((float) (zenith.x - cam.x), (float) (zenith.y - cam.y), (float) (zenith.z - cam.z));
        if (ZENITH_DIR.lengthSquared() < 1.0E-4F || ZENITH_DIR.y <= 0.0F) {
            ZENITH_DIR.set(0.0F, 1.0F, 0.0F); // degenerate (camera above the zenith point)
        }
        ZENITH_ROT.rotationTo(0.0F, 1.0F, 0.0F, ZENITH_DIR.x, ZENITH_DIR.y, ZENITH_DIR.z);

        poseStack.pushPose();
        poseStack.mulPose(ZENITH_ROT);
        Matrix4f zenithPose = poseStack.last().pose();

        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        float pulse = 0.85F + 0.15F * Mth.sin(seconds * 1.3F);

        // additive aura: glow floor first, then the two counter-rotating ray layers
        RenderSystem.blendFuncSeparate(
                GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        drawAuraGlow(zenithPose, pulse);
        drawAuraRays(zenithPose, seconds, pulse);

        // the eclipse disc itself, alpha-blended so its black core occludes the ray roots
        RenderSystem.defaultBlendFunc();
        RenderSystem.setShader(GameRenderer::getPositionTexShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.setShaderTexture(0, ECLIPSE_TEXTURE);
        SkyRenderUtil.drawCelestialQuad(zenithPose, DISC_SIZE, SKY_DISTANCE);
        poseStack.popPose();

        // IDEA-18 §1: smeared reflection streak on the water plane below the zenith —
        // additive, world-oriented (not in the zenith rotation), breathing with the same
        // pulse as the aura so disc and reflection never desync.
        RenderSystem.blendFuncSeparate(
                GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        drawWaterReflection(poseStack.last().pose(), zenith, cam, pulse);

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
        RenderSystem.depthMask(true);
        return true;
    }

    /**
     * IDEA-18 §1 — the eclipse's reflection on the black water: a long, thin additive
     * violet streak on the water plane directly below the zenith point, stretched toward
     * the camera (elongated triangle fan, {@code drawAuraGlow} builder pattern). Alpha
     * falls with camera height above the waterline; the waterline is the zenith source Y
     * ({@code ship_deck} anchor or shared spawn) minus 4 — deck sits ~waterline + 3.
     */
    private static void drawWaterReflection(Matrix4f pose, Vec3 zenith, Vec3 cam, float pulse) {
        double waterY = zenith.y - ZENITH_HEIGHT - 4.0D;
        double camAbove = cam.y - waterY;
        if (camAbove <= 0.5D) {
            return; // camera at/under the waterline — nothing to reflect
        }
        float heightFade = (float) Mth.clamp(1.0D - (camAbove - 4.0D) / STREAK_FADE_HEIGHT, 0.0D, 1.0D);
        if (heightFade <= 0.01F) {
            return;
        }
        float cx = (float) (zenith.x - cam.x);
        float cy = (float) (waterY - cam.y);
        float cz = (float) (zenith.z - cam.z);
        // Long axis: horizontal, pointing from the below-zenith point toward the camera.
        float dx = -cx;
        float dz = -cz;
        float horizLen = Mth.sqrt(dx * dx + dz * dz);
        if (horizLen < 1.0E-3F) {
            dx = 0.0F;
            dz = 1.0F;
        } else {
            dx /= horizLen;
            dz /= horizLen;
        }
        float perpX = -dz;
        float perpZ = dx;
        float halfLen = Mth.clamp(horizLen * 0.6F, STREAK_MIN_HALF_LEN, STREAK_MAX_HALF_LEN);
        float alpha = 0.35F * pulse * heightFade;

        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION_COLOR);
        builder.addVertex(pose, cx, cy, cz).setColor(0.62F, 0.30F, 1.0F, alpha);
        for (int i = 0; i <= STREAK_SEGMENTS; i++) {
            float angle = (float) i / STREAK_SEGMENTS * ((float) Math.PI * 2.0F);
            float along = Mth.cos(angle) * halfLen;
            float side = Mth.sin(angle) * STREAK_HALF_WIDTH;
            builder.addVertex(pose,
                            cx + dx * along + perpX * side,
                            cy,
                            cz + dz * along + perpZ * side)
                    .setColor(0.45F, 0.18F, 0.85F, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /** Soft radial glow fan behind the disc: violet center fading to nothing at the rim. */
    private static void drawAuraGlow(Matrix4f pose, float pulse) {
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION_COLOR);
        builder.addVertex(pose, 0.0F, SKY_DISTANCE, 0.0F)
                .setColor(0.55F, 0.22F, 0.95F, 0.30F * pulse);
        for (int i = 0; i <= GLOW_SEGMENTS; i++) {
            float angle = (float) i / GLOW_SEGMENTS * ((float) Math.PI * 2.0F);
            builder.addVertex(pose, Mth.cos(angle) * GLOW_RADIUS, SKY_DISTANCE, Mth.sin(angle) * GLOW_RADIUS)
                    .setColor(0.35F, 0.10F, 0.70F, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * The {@value #RAY_COUNT}-ray aura fan: two 6-ray layers counter-rotating at
     * ±{@value #RAY_SPIN_DEG_PER_SEC} °/s. Each ray is a tapered additive wedge from just
     * inside the disc silhouette out to its own 40–120-unit length, root alpha
     * {@value #RAY_ALPHA}·pulse fading to zero at the tip.
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

            builder.addVertex(pose, dirX * r0 - perpX * rootW, SKY_DISTANCE, dirZ * r0 - perpZ * rootW)
                    .setColor(0.78F, 0.42F, 1.0F, rootAlpha);
            builder.addVertex(pose, dirX * r0 + perpX * rootW, SKY_DISTANCE, dirZ * r0 + perpZ * rootW)
                    .setColor(0.78F, 0.42F, 1.0F, rootAlpha);
            builder.addVertex(pose, dirX * r1 + perpX * tipW, SKY_DISTANCE, dirZ * r1 + perpZ * tipW)
                    .setColor(0.45F, 0.15F, 0.85F, 0.0F);
            builder.addVertex(pose, dirX * r1 - perpX * tipW, SKY_DISTANCE, dirZ * r1 - perpZ * tipW)
                    .setColor(0.45F, 0.15F, 0.85F, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }
}
