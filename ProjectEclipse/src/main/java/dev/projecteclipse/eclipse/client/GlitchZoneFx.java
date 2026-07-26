package dev.projecteclipse.eclipse.client;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.glitchzone.GlitchColors;
import dev.projecteclipse.eclipse.glitchzone.GlitchZoneEffects;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client half of the GLITCHZONE event: holds the last synced sample from
 * {@code S2CGlitchZonePayload} and registers ONE {@link VeilPostController} row per
 * {@link GlitchZoneEffects} id ({@code eclipse:glitch_outline}, {@code glitch_datamosh},
 * {@code glitch_scanlines}, {@code glitch_invert}, {@code glitch_void}) — the
 * {@code GhostGradeFx} static-init pattern, five times over.
 *
 * <p><b>Smoothing:</b> the server syncs coarse strength steps (epsilon-gated, so the wire
 * stays quiet); each effect keeps its own client-eased strength that lerps toward its
 * target every tick and interpolates by partialTick per frame — entering, leaving, expiry
 * and even switching effects mid-zone are all gradients, never pops. Only the synced
 * effect has a nonzero target, so at most two rows overlap for the ~0.5&nbsp;s of an
 * effect-to-effect cross-fade; the rest idle-skip below {@value #MIN_ACTIVE}.</p>
 *
 * <p><b>Accent colour (F-049):</b> one GLOBAL eased accent, not one per row — only one zone
 * owns the screen at a time, and during an effect-to-effect cross-fade both rows wearing the
 * same colour is the correct read. {@code AccentAmount} is the "is a colour commanded at
 * all" ramp: at 0 every shader falls back to its own shipped constant, so a zone with no
 * colour is bit-identical to the pre-F-049 build. A "no zone" sample HOLDS the accent target
 * instead of resetting it — otherwise a zone would drain toward its default colour while it
 * fades out.</p>
 *
 * <p><b>Impulse origin (F-048):</b> {@code Origin} is the sample's world origin expressed
 * CAMERA-RELATIVE (the {@code StormVolumeFx.VolCenter} convention — the subtraction happens
 * here in doubles, so the float uniform never carries absolute world magnitudes), and
 * {@code OriginMode} selects it over the camera. Only {@code glitch_void} declares the pair;
 * Veil's {@code getUniform} is a no-op for undeclared names, so the feeder stays uniform
 * across all five rows.</p>
 *
 * <p><b>Priority:</b> TRANSITION — these are deliberate full-screen reality takeovers, so
 * they must composite LAST (on top of world grades and feature passes, Veil manager
 * priority 1000) and be the last row the over-budget eviction drops. The
 * {@code eclipse:rift_glitch} transition shares the band; visually they speak the same
 * corruption language, so stacking order between them is not load-bearing.</p>
 *
 * <p><b>Iris/off gate:</b> inherited from {@link VeilPostController} — with a shaderpack
 * active or {@code veilPostFx} off the rows are simply never added (silent event, silent
 * degrade; there is no world-space fallback by design).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GlitchZoneFx {
    /** Below this eased strength a row idle-skips (the spec's {@code strength > 0.01} gate). */
    private static final float MIN_ACTIVE = 0.01F;
    /** Per-tick approach factor toward the synced target (~90% of a step in 12 ticks). */
    private static final float EASE_RATE = 0.18F;
    /** Snap distance so the ease terminates exactly at the target instead of crawling. */
    private static final float SNAP = 0.004F;

    /** Effect ids in registration order; index-aligned with the smoothing arrays. */
    private static final List<String> EFFECTS = GlitchZoneEffects.IDS;

    /** Last synced sample (written by the payload handler on the client main thread). */
    private static String targetEffect = "";
    private static float targetStrength;
    private static float targetAccentR = 1.0F;
    private static float targetAccentG = 1.0F;
    private static float targetAccentB = 1.0F;
    private static float targetAccentAmount;
    private static boolean originValid;
    private static double originX;
    private static double originY;
    private static double originZ;

    /** Per-effect eased strengths: previous tick + current tick (partialTick interpolation). */
    private static final float[] PREV = new float[EFFECTS.size()];
    private static final float[] CURRENT = new float[EFFECTS.size()];

    /** Eased accent (r, g, b, amount) shared by every row — see the class doc. */
    private static final float[] ACCENT_PREV = {1.0F, 1.0F, 1.0F, 0.0F};
    private static final float[] ACCENT_CURRENT = {1.0F, 1.0F, 1.0F, 0.0F};

    static {
        for (int i = 0; i < EFFECTS.size(); i++) {
            final int index = i;
            VeilPostController.register(new VeilPostController.PipelineSpec(
                    GlitchZoneEffects.pipelineId(EFFECTS.get(index)),
                    VeilPostController.PipelinePriority.TRANSITION,
                    () -> strength(index, partialTick()) > MIN_ACTIVE,
                    pipeline -> feed(pipeline, index)));
        }
    }

    private GlitchZoneFx() {}

    /** {@code S2CGlitchZonePayload} entry point ({@code effect} may be {@code ""} = none). */
    public static void handle(String effect, float strength, String colour,
            boolean hasOrigin, BlockPos origin) {
        targetEffect = effect;
        targetStrength = Mth.clamp(strength, 0.0F, 1.0F);
        // "No zone" carries no colour: hold the current accent so the fade-out keeps the
        // colour it started in. The strength ramp alone takes the effect off screen.
        if (!effect.isEmpty()) {
            GlitchColors.Rgb rgb = GlitchColors.rgb(colour);
            targetAccentR = rgb.r();
            targetAccentG = rgb.g();
            targetAccentB = rgb.b();
            targetAccentAmount = GlitchColors.amount(colour);
        }
        originValid = hasOrigin;
        // Block centre: the impulse leaves the middle of the altar block, not its corner.
        originX = origin.getX() + 0.5D;
        originY = origin.getY() + 0.5D;
        originZ = origin.getZ() + 0.5D;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        for (int i = 0; i < EFFECTS.size(); i++) {
            PREV[i] = CURRENT[i];
            float target = EFFECTS.get(i).equals(targetEffect) ? targetStrength : 0.0F;
            CURRENT[i] = ease(CURRENT[i], target);
        }
        System.arraycopy(ACCENT_CURRENT, 0, ACCENT_PREV, 0, ACCENT_CURRENT.length);
        ACCENT_CURRENT[0] = ease(ACCENT_CURRENT[0], targetAccentR);
        ACCENT_CURRENT[1] = ease(ACCENT_CURRENT[1], targetAccentG);
        ACCENT_CURRENT[2] = ease(ACCENT_CURRENT[2], targetAccentB);
        ACCENT_CURRENT[3] = ease(ACCENT_CURRENT[3], targetAccentAmount);
    }

    /** One exponential-approach step with a terminating snap (the house ease law). */
    private static float ease(float current, float target) {
        float next = current + (target - current) * EASE_RATE;
        return Math.abs(target - next) < SNAP ? target : next;
    }

    /** Frame-smooth eased strength of one effect (prev→current by partialTick). */
    private static float strength(int index, float partialTick) {
        return Mth.lerp(partialTick, PREV[index], CURRENT[index]);
    }

    /**
     * Per-frame uniform feeder (no allocations). {@code Time} is wall-clock like the
     * sibling glitch passes ({@code rift_glitch}/{@code storm_interior}): corruption keeps
     * crawling even when client ticks stall. {@code Detail} gates the motion-bearing
     * layers (jitter, tears, static, sonar sweep) to 0 under reduced FX — the static
     * grade of each effect survives, matching the storm-interior contract.
     */
    private static void feed(PostPipeline pipeline, int index) {
        float partialTick = partialTick();
        pipeline.getUniform("Strength").setFloat(strength(index, partialTick));
        pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 100_000L) / 1000.0F);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
        pipeline.getUniform("AccentColor").setVector(
                Mth.lerp(partialTick, ACCENT_PREV[0], ACCENT_CURRENT[0]),
                Mth.lerp(partialTick, ACCENT_PREV[1], ACCENT_CURRENT[1]),
                Mth.lerp(partialTick, ACCENT_PREV[2], ACCENT_CURRENT[2]));
        pipeline.getUniform("AccentAmount").setFloat(
                Mth.lerp(partialTick, ACCENT_PREV[3], ACCENT_CURRENT[3]));

        // Camera-relative world origin (VeilCamera local space; camera at the origin).
        Vec3 camera = Minecraft.getInstance().gameRenderer.getMainCamera().getPosition();
        pipeline.getUniform("Origin").setVector(
                (float) (originX - camera.x), (float) (originY - camera.y), (float) (originZ - camera.z));
        pipeline.getUniform("OriginMode").setFloat(originValid ? 1.0F : 0.0F);
    }

    /** Session reset: a zone from the last world must never bleed into the next login. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        targetEffect = "";
        targetStrength = 0.0F;
        targetAccentR = 1.0F;
        targetAccentG = 1.0F;
        targetAccentB = 1.0F;
        targetAccentAmount = 0.0F;
        originValid = false;
        originX = 0.0D;
        originY = 0.0D;
        originZ = 0.0D;
        for (int i = 0; i < EFFECTS.size(); i++) {
            PREV[i] = 0.0F;
            CURRENT[i] = 0.0F;
        }
        ACCENT_PREV[0] = 1.0F;
        ACCENT_PREV[1] = 1.0F;
        ACCENT_PREV[2] = 1.0F;
        ACCENT_PREV[3] = 0.0F;
        System.arraycopy(ACCENT_PREV, 0, ACCENT_CURRENT, 0, ACCENT_PREV.length);
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
