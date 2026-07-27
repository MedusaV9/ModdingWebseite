package dev.projecteclipse.eclipse.woah.gravityrift.client;

import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-02 Veil-lensing post pass ({@code eclipse:gravity_lens}, FEATURE priority,
 * plan §4.4): a gravitational refraction shimmer around the heart — upward-streaming
 * heat-haze ripples (anti-gravity read), a mild radial pull toward the heart's screen
 * point, a pulse shock front riding the local beat raster, and the inversion's
 * full-frame up-drift ripple + hue lift. Registered permanently (the
 * {@code CreditsBlackHolePostFx} static-init pattern) and idle-skipped whenever the
 * eased {@link GravityRiftClientState#amount} is ~0 — the pass costs nothing outside
 * the zone approach.
 *
 * <p>The heart's screen position is re-projected every frame through
 * {@link SunTracker#worldToNdc} (the exact render matrices); while the projection
 * fails (heart behind the camera) the last good screen point is kept so the
 * distortion never snaps.</p>
 *
 * <p>Iris fallback: none needed — {@link VeilPostController} gates the whole post
 * stack off while a shaderpack is active; the rift still reads through the orbital
 * displays and the Photon loops.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GravityRiftLensFx {
    public static final ResourceLocation GRAVITY_LENS_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "gravity_lens");

    /** Below this amount (and with no pulse/invert live) the pipeline drops entirely. */
    private static final float MIN_ACTIVE = GravityRiftClientState.MIN_ACTIVE;
    /** {@code Time} uniform wrap (one hour of ticks — the limbo clock-wrap precedent). */
    private static final int TIME_WRAP_TICKS = 72_000;

    /** Pause-frozen shimmer clock. */
    private static int fxTicks;
    /** Last successfully projected heart center (UV space). */
    private static float heartU = 0.5F;
    private static float heartV = 0.45F;
    /** Per-frame projection scratch (no allocations in the feeder). */
    private static final Vector4f NDC_SCRATCH = new Vector4f();

    static {
        VeilPostController.register(new VeilPostController.PipelineSpec(
                GRAVITY_LENS_POST,
                VeilPostController.PipelinePriority.FEATURE,
                GravityRiftLensFx::wantLens,
                GravityRiftLensFx::feedLens));
    }

    private GravityRiftLensFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!Minecraft.getInstance().isPaused()) {
            fxTicks++;
        }
    }

    private static boolean wantLens() {
        if (Minecraft.getInstance().level == null || !GravityRiftClientState.built()) {
            return false;
        }
        float partialTick = partialTick();
        return GravityRiftClientState.amount(partialTick) > MIN_ACTIVE;
    }

    private static void feedLens(PostPipeline pipeline) {
        float partialTick = partialTick();
        Vec3 heart = GravityRiftClientState.heartCenter();
        if (heart != null && SunTracker.worldToNdc(heart, NDC_SCRATCH)) {
            heartU = NDC_SCRATCH.x * 0.5F + 0.5F;
            heartV = NDC_SCRATCH.y * 0.5F + 0.5F;
        }
        Minecraft minecraft = Minecraft.getInstance();
        float aspect = minecraft.getWindow().getHeight() <= 0 ? 1.0F
                : (float) minecraft.getWindow().getWidth() / minecraft.getWindow().getHeight();
        pipeline.getUniform("Strength").setFloat(GravityRiftClientState.amount(partialTick));
        pipeline.getUniform("Center").setVector(heartU, heartV);
        pipeline.getUniform("Aspect").setFloat(aspect);
        pipeline.getUniform("Time").setFloat((fxTicks % TIME_WRAP_TICKS + partialTick) / 20.0F);
        pipeline.getUniform("Pulse").setFloat(GravityRiftClientState.pulseKick());
        pipeline.getUniform("Invert").setFloat(GravityRiftClientState.invertAmount());
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
