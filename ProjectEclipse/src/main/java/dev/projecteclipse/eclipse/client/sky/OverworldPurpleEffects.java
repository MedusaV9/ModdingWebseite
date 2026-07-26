package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;
import com.mojang.math.Axis;

import org.joml.Matrix4f;

import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.DimensionSpecialEffects;
import net.minecraft.client.renderer.FogRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.level.material.FogType;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Overworld sky for the Eclipse event ({@code eclipse:overworld} effects id): a close port of
 * the vanilla 1.21.1 {@code LevelRenderer#renderSky} NORMAL-sky path with a large purple sun
 * (from {@code eclipse:textures/environment/sun_purple.png}) plus a soft additive halo, and the
 * sky disc shifted toward purple during the day. Moon, sunrise band, stars and the below-horizon
 * dark disc are kept vanilla-like so nights stay intact.
 *
 * <p>P2-W1 additions (R1/R2/R4/R10):</p>
 * <ul>
 *   <li><b>Sun truth</b>: the celestial rotation angle comes from
 *       {@link dev.projecteclipse.eclipse.veilfx.SunTracker#sunAngleRadians} — the same number
 *       {@code SunTracker} projects into the {@code SunScreen} uniform, so the sky-pass sun
 *       and the {@code eclipse:sun_halo} post halo share one source of truth and can never
 *       drift apart (the old bug: the post shader reconstructed rays from Veil's bobbing-free
 *       camera block while this quad rendered with the bobbing modelview).</li>
 *   <li><b>Eclipse scale-up</b>: the sun quad grows 38 → {@value #SUN_SIZE_ECLIPSE} units with
 *       {@code EclipseFxState.eclipseAmount}, backed by three slowly counter-rotating additive
 *       corona quads (90/140/200 units) — a screen-filling presence instead of a postage
 *       stamp.</li>
 *   <li><b>Permanent rim</b> (post-intro): a purple rim pass behind the sun disc whenever
 *       {@code EclipseFxState.permanentSunRim()} is set.</li>
 *   <li><b>No clouds</b>: cloud height {@code NaN} + {@link #renderClouds} handled-empty.</li>
 * </ul>
 *
 * <p>SKYDAY additions (see {@link EclipseSkyState}):</p>
 * <ul>
 *   <li><b>Day escalation</b>: the sky escalates with the synced event day 1..14 — deeper
 *       purple grading, a baseline corona, a swelling idle sun, a stronger halo, stars
 *       bleeding into the day and the {@link DaySkyEscalation} aurora curtains, all
 *       culminating on day 14. Additive extras ride the tier-scaled
 *       {@link EclipseSkyState#dayFxEscalation()} (reducedFx halves, tier 0 disables).</li>
 *   <li><b>Zenith hold</b>: after the first altar completion the ECLIPSE frame (sun +
 *       halo + coronas + rim + altar veil + day aurora) glides to and stays at the very
 *       top of the sky ({@link EclipseSkyState#celestialAngleRadians} — angle 0, the
 *       vanilla tick-6000 noon zenith); the moon, stars and sunrise band keep the vanilla
 *       angle so nights stay intact.</li>
 * </ul>
 *
 * <p>Iris guard: while a shaderpack is active ({@link EclipseIrisState#shaderPackActive()}) this
 * returns {@code false} immediately so the shader pipeline owns the sky; the vanilla sun.png
 * override and the fog tint still apply in that case. The cloud kill applies either way
 * (vanilla asks {@link #renderClouds} regardless of the sky owner).</p>
 */
@OnlyIn(Dist.CLIENT)
public class OverworldPurpleEffects extends DimensionSpecialEffects {
    private static final ResourceLocation SUN_PURPLE =
            ResourceLocation.fromNamespaceAndPath("eclipse", "textures/environment/sun_purple.png");
    private static final ResourceLocation MOON_LOCATION =
            ResourceLocation.withDefaultNamespace("textures/environment/moon_phases.png");

    /** Purple target the day sky is blended toward (matches the fog tint). */
    private static final float PURPLE_R = 0.35F;
    private static final float PURPLE_G = 0.10F;
    private static final float PURPLE_B = 0.45F;
    private static final float SKY_BLEND = 0.35F;
    /** SKYDAY: day-14 endpoint of the sky-disc purple blend (day 1 keeps {@value #SKY_BLEND}). */
    private static final float SKY_BLEND_LAST_DAY = 0.55F;

    /** Sun quad size: idle (v1 look) → full eclipse (R1: "30 → 90 units", ours idles at 38). */
    private static final float SUN_SIZE_IDLE = 38.0F;
    private static final float SUN_SIZE_ECLIPSE = 90.0F;
    /** SKYDAY: idle sun size by day 14 — the eclipse visibly swells across the event. */
    private static final float SUN_SIZE_LAST_DAY = 56.0F;
    /** SKYDAY: corona baseline the day escalation sustains without a live eclipse phase. */
    private static final float DAY_CORONA_MAX = 0.85F;
    /** Soft halo quad size behind the sun (grows with the eclipse). */
    private static final float HALO_SIZE_IDLE = 60.0F;
    private static final float HALO_SIZE_ECLIPSE = 150.0F;
    /** Corona layers: size in units / rotation °·s⁻¹ (≈0.05/0.03/0.02 °/frame at 60 fps) / alpha. */
    private static final float[] CORONA_SIZES = {90.0F, 140.0F, 200.0F};
    private static final float[] CORONA_DEG_PER_SEC = {3.0F, -1.8F, 1.2F};
    private static final float[] CORONA_ALPHAS = {0.30F, 0.22F, 0.16F};

    /** Vanilla star field (seed/count as in {@code LevelRenderer#drawStars}). */
    private static final StarField STARS = new StarField(10842L, 1500, 0.15F);

    public OverworldPurpleEffects() {
        // Overworld-like: hasGround, NORMAL sky, no forced-bright lightmap, no constant
        // ambient light. Cloud height NaN = "no cloud layer" (R4), belt to renderClouds' braces.
        super(Float.NaN, true, DimensionSpecialEffects.SkyType.NORMAL, false, false);
    }

    /** R4: clouds are fully disabled — report handled so vanilla draws nothing. */
    @Override
    public boolean renderClouds(ClientLevel level, int ticks, float partialTick, PoseStack poseStack,
            double camX, double camY, double camZ, Matrix4f modelViewMatrix, Matrix4f projectionMatrix) {
        return true;
    }

    @Override
    public Vec3 getBrightnessDependentFogColor(Vec3 fogColor, float brightness) {
        // Same curve as vanilla OverworldEffects.
        return fogColor.multiply(brightness * 0.94F + 0.06F, brightness * 0.94F + 0.06F, brightness * 0.91F + 0.09F);
    }

    @Override
    public boolean isFoggyAt(int x, int y) {
        return false;
    }

    @Override
    public boolean renderSky(ClientLevel level, int ticks, float partialTick, Matrix4f modelViewMatrix,
            Camera camera, Matrix4f projectionMatrix, boolean isFoggy, Runnable setupFog) {
        if (EclipseIrisState.shaderPackActive()) {
            return false; // shaderpack owns the sky; sun.png override + fog tint still apply
        }
        setupFog.run();
        if (isFoggy) {
            return true; // vanilla draws no sky in this case either
        }
        FogType fogType = camera.getFluidInCamera();
        if (fogType == FogType.POWDER_SNOW || fogType == FogType.LAVA || mobEffectBlocksSky(camera)) {
            return true;
        }

        PoseStack poseStack = new PoseStack();
        poseStack.mulPose(modelViewMatrix);

        float eclipse = EclipseFxState.eclipseAmount(partialTick);
        // SKYDAY escalation drivers: raw day factor for zero-cost grading, tier-scaled fx
        // factor for everything that adds draw calls (coronas, stars, aurora curtains).
        float dayEsc = EclipseSkyState.dayEscalation();
        float fxEsc = EclipseSkyState.dayFxEscalation();

        // --- sky disc, blended toward purple during the day -------------------------------
        // SKYDAY: the purple grading deepens with the event day (0.35 → 0.55 by day 14).
        Vec3 skyColor = level.getSkyColor(camera.getPosition(), partialTick);
        float day = dayFactor(level, partialTick);
        float blend = Mth.lerp(dayEsc, SKY_BLEND, SKY_BLEND_LAST_DAY) * day;
        float skyR = Mth.lerp(blend, (float) skyColor.x, PURPLE_R);
        float skyG = Mth.lerp(blend, (float) skyColor.y, PURPLE_G);
        float skyB = Mth.lerp(blend, (float) skyColor.z, PURPLE_B);
        if (eclipse > 0.001F) {
            // R16: the eclipse crushes the sky dome toward a near-black violet even at noon
            // (the world-side crush is eclipse:world_grade's job; this keeps the dome in sync).
            float crush = eclipse * 0.85F;
            skyR = Mth.lerp(crush, skyR, 0.055F);
            skyG = Mth.lerp(crush, skyG, 0.020F);
            skyB = Mth.lerp(crush, skyB, 0.095F);
        }
        FogRenderer.levelFogColor();
        RenderSystem.depthMask(false);
        RenderSystem.setShaderColor(skyR, skyG, skyB, 1.0F);
        RenderSystem.setShader(GameRenderer::getPositionShader);
        SkyRenderUtil.drawSkyDisc(poseStack.last().pose(), 16.0F);

        RenderSystem.enableBlend();

        // --- sunrise/sunset band (vanilla formula) -----------------------------------------
        float[] sunrise = this.getSunriseColor(level.getTimeOfDay(partialTick), partialTick);
        if (sunrise != null) {
            RenderSystem.setShader(GameRenderer::getPositionColorShader);
            RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
            poseStack.pushPose();
            poseStack.mulPose(Axis.XP.rotationDegrees(90.0F));
            float sunDirection = Mth.sin(level.getSunAngle(partialTick)) < 0.0F ? 180.0F : 0.0F;
            poseStack.mulPose(Axis.ZP.rotationDegrees(sunDirection));
            poseStack.mulPose(Axis.ZP.rotationDegrees(90.0F));
            Matrix4f pose = poseStack.last().pose();
            BufferBuilder builder = Tesselator.getInstance().begin(VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION_COLOR);
            builder.addVertex(pose, 0.0F, 100.0F, 0.0F).setColor(sunrise[0], sunrise[1], sunrise[2], sunrise[3]);
            for (int i = 0; i <= 16; i++) {
                float angle = (float) i * ((float) Math.PI * 2.0F) / 16.0F;
                float sin = Mth.sin(angle);
                float cos = Mth.cos(angle);
                builder.addVertex(pose, sin * 120.0F, cos * 120.0F, -cos * 40.0F * sunrise[3])
                        .setColor(sunrise[0], sunrise[1], sunrise[2], 0.0F);
            }
            BufferUploader.drawWithShader(builder.buildOrThrow());
            poseStack.popPose();
        }

        // --- celestial bodies (additive, like vanilla) ---------------------------------------
        RenderSystem.blendFuncSeparate(
                GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        poseStack.pushPose();
        float rainAlpha = 1.0F - level.getRainLevel(partialTick);
        poseStack.mulPose(Axis.YP.rotationDegrees(-90.0F));
        // R2: same celestial angle SunTracker projects into SunScreen — one source of truth
        // — now routed through the SKYDAY zenith hold ({@link EclipseSkyState}): after the
        // first altar completion the ECLIPSE frame (sun, halo, coronas, rim, altar veil,
        // day aurora) glides to and pins at the very top of the sky, while the moon, stars
        // and sunrise band keep the vanilla angle below so nights stay intact.
        poseStack.pushPose();
        poseStack.mulPose(Axis.XP.rotationDegrees(
                (float) Math.toDegrees(EclipseSkyState.celestialAngleRadians(level, partialTick))));
        Matrix4f celestialPose = poseStack.last().pose();

        RenderSystem.setShader(GameRenderer::getPositionTexShader);
        RenderSystem.setShaderTexture(0, SUN_PURPLE);

        // R1: three slowly rotating additive corona quads carry the eclipse's screen
        // presence. SKYDAY: the day escalation sustains a baseline corona (up to
        // DAY_CORONA_MAX by day 14) even without a live eclipse phase.
        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        float coronaDrive = Math.max(eclipse, fxEsc * DAY_CORONA_MAX);
        if (coronaDrive > 0.001F) {
            for (int i = 0; i < CORONA_SIZES.length; i++) {
                poseStack.pushPose();
                poseStack.mulPose(Axis.YP.rotationDegrees(seconds * CORONA_DEG_PER_SEC[i]));
                // Slow phase-offset breathing per layer (±10%) so the corona shimmers as a
                // living thing instead of holding three frozen alpha rings.
                float breathe = 0.90F + 0.10F * Mth.sin(seconds * 0.7F + i * 2.1F);
                RenderSystem.setShaderColor(
                        0.75F - 0.12F * i, 0.40F - 0.09F * i, 1.00F - 0.05F * i,
                        CORONA_ALPHAS[i] * breathe * coronaDrive * rainAlpha);
                SkyRenderUtil.drawCelestialQuad(poseStack.last().pose(), CORONA_SIZES[i], 100.0F);
                poseStack.popPose();
            }
        }

        // soft halo: the same texture drawn much larger at low alpha behind the sun
        // (SKYDAY: it brightens and widens a little as the days pass)
        RenderSystem.setShaderColor(0.72F, 0.35F, 0.95F,
                (0.40F + 0.25F * eclipse + 0.18F * fxEsc) * rainAlpha);
        SkyRenderUtil.drawCelestialQuad(celestialPose,
                Mth.lerp(eclipse, HALO_SIZE_IDLE + 25.0F * fxEsc, HALO_SIZE_ECLIPSE), 100.0F);

        // SKYDAY: the idle sun swells 38 → 56 units across the event; a live eclipse
        // still scales the result to its full 90.
        float sunSize = Mth.lerp(eclipse,
                Mth.lerp(dayEsc, SUN_SIZE_IDLE, SUN_SIZE_LAST_DAY), SUN_SIZE_ECLIPSE);

        // R10 SUNRISE: permanent purple rim pass behind the sun disc after the intro. A very
        // slow ±0.04 breath around the frozen 0.50 keeps the rim from reading as a static
        // decal without changing its average strength.
        if (EclipseFxState.permanentSunRim()) {
            float rimBreathe = 0.50F + 0.04F * Mth.sin(seconds * 0.45F);
            RenderSystem.setShaderColor(0.62F, 0.22F, 1.00F, rimBreathe * rainAlpha);
            SkyRenderUtil.drawCelestialQuad(celestialPose, sunSize * 1.35F, 100.0F);
        }

        // the purple sun itself, growing from its idle size to eclipse scale
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, rainAlpha);
        SkyRenderUtil.drawCelestialQuad(celestialPose, sunSize, 100.0F);

        // W-P-ALTAR: the altar level's permanent veil signature around the eclipse
        // (ring → glyph constellation → aurora bands → halo beams → corona crown),
        // keyed off the synced ClientStateCache.altarLevel. Additive blend and
        // depthMask(false) are still active here; the moon pass below rebinds the
        // tex pipeline, so the position-color swap inside needs no restore.
        AltarVeilSky.render(celestialPose, partialTick, eclipse, rainAlpha);

        // SKYDAY: the day escalation's aurora curtains + late-event ember ring — they
        // ride the (possibly zenith-held) eclipse frame like the altar veil above.
        DaySkyEscalation.render(celestialPose, seconds, rainAlpha);
        poseStack.popPose();

        // vanilla moon (phases from the shared moon sheet), in the VANILLA celestial
        // frame — deliberately outside the zenith hold so nights keep their moon.
        poseStack.mulPose(Axis.XP.rotationDegrees(
                (float) Math.toDegrees(SunTracker.sunAngleRadians(level, partialTick))));
        Matrix4f moonPose = poseStack.last().pose();
        RenderSystem.setShader(GameRenderer::getPositionTexShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, rainAlpha);
        RenderSystem.setShaderTexture(0, MOON_LOCATION);
        int moonPhase = level.getMoonPhase();
        int px = moonPhase % 4;
        int py = moonPhase / 4 % 2;
        float u0 = (float) (px + 0) / 4.0F;
        float v0 = (float) (py + 0) / 2.0F;
        float u1 = (float) (px + 1) / 4.0F;
        float v1 = (float) (py + 1) / 2.0F;
        float moonSize = 20.0F;
        BufferBuilder moon = Tesselator.getInstance().begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX);
        moon.addVertex(moonPose, -moonSize, -100.0F, moonSize).setUv(u1, v1);
        moon.addVertex(moonPose, moonSize, -100.0F, moonSize).setUv(u0, v1);
        moon.addVertex(moonPose, moonSize, -100.0F, -moonSize).setUv(u0, v0);
        moon.addVertex(moonPose, -moonSize, -100.0F, -moonSize).setUv(u1, v0);
        BufferUploader.drawWithShader(moon.buildOrThrow());

        // stars, faintly purple-tinted; a strong eclipse pulls them out even at noon —
        // SKYDAY: so do the last event days (fx-tier-scaled, cheap single draw).
        float starBrightness = Math.max(level.getStarBrightness(partialTick),
                Math.max(eclipse * 0.5F, fxEsc * 0.30F)) * rainAlpha;
        if (starBrightness > 0.0F) {
            RenderSystem.setShaderColor(starBrightness * 0.9F, starBrightness * 0.8F, starBrightness, starBrightness);
            FogRenderer.setupNoFog();
            STARS.draw(poseStack.last().pose(), projectionMatrix);
            setupFog.run();
        }

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
        poseStack.popPose();

        // --- dark disc below the horizon (vanilla behavior) ---------------------------------
        RenderSystem.setShaderColor(0.0F, 0.0F, 0.0F, 1.0F);
        double distanceAboveHorizon = camera.getPosition().y - level.getLevelData().getHorizonHeight(level);
        if (distanceAboveHorizon < 0.0) {
            poseStack.pushPose();
            poseStack.translate(0.0F, 12.0F, 0.0F);
            RenderSystem.setShader(GameRenderer::getPositionShader);
            SkyRenderUtil.drawSkyDisc(poseStack.last().pose(), -16.0F);
            poseStack.popPose();
        }

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.depthMask(true);
        return true;
    }

    /**
     * 0 at night, 1 at midday — same cosine curve vanilla uses for sky brightness. Public:
     * {@code veilfx.VeilPostController} derives the {@code eclipse:world_grade} NightAmount
     * from it (R3).
     */
    public static float dayFactor(ClientLevel level, float partialTick) {
        float cos = Mth.cos(level.getTimeOfDay(partialTick) * ((float) Math.PI * 2.0F)) * 2.0F + 0.5F;
        return Mth.clamp(cos, 0.0F, 1.0F);
    }

    /** Mirror of the private {@code LevelRenderer#doesMobEffectBlockSky}. */
    static boolean mobEffectBlocksSky(Camera camera) {
        return camera.getEntity() instanceof LivingEntity living
                && (living.hasEffect(MobEffects.BLINDNESS) || living.hasEffect(MobEffects.DARKNESS));
    }
}
