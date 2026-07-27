package dev.projecteclipse.eclipse.client.credits;

import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * F-056 black-hole post distortion ({@code eclipse:black_hole}, FEATURE priority): a
 * radial UV pull + swirl toward the hole center, an event-horizon black-out with a thin
 * photon ring, and the finale's "Farben ergrauen" desaturation — all riding
 * {@link CreditsSkyFx#holeAmount} (server-driven via {@code S2CCreditsSkyPayload} SPACE
 * mode), so the pass is registered permanently but idle-skips whenever no black-hole
 * finale is live (the {@code GhostGradeFx} activation-predicate pattern).
 *
 * <p>The hole's screen position is re-projected every frame from
 * {@link CreditsSkyFx#holeCenter} through {@link SunTracker#worldToNdc} (the exact render
 * matrices — the same seam the shockwave/sun-halo passes use). While the projection fails
 * (hole behind the camera during a look-around) the last good screen point is kept, so
 * the distortion never snaps.</p>
 *
 * <p>Iris fallback: none needed — {@link VeilPostController} gates the whole post stack
 * off while a shaderpack is active, and the finale still reads through the display
 * entities, the Photon maw and the space sky.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsBlackHolePostFx {
    public static final ResourceLocation BLACK_HOLE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "black_hole");

    /** Below this the release ramp is over — drop the pipeline entirely (idle-skip). */
    private static final float MIN_ACTIVE = 0.003F;
    /** {@code Time} uniform wrap (one hour of ticks — the limbo clock-wrap precedent). */
    private static final int TIME_WRAP_TICKS = 72_000;

    /** Pause-frozen shimmer clock. */
    private static int fxTicks;
    /** Last successfully projected hole center (UV space); starts at screen center-high. */
    private static float holeU = 0.5F;
    private static float holeV = 0.62F;
    /** Per-frame projection scratch (no allocations in the feeder). */
    private static final Vector4f NDC_SCRATCH = new Vector4f();

    static {
        VeilPostController.register(new VeilPostController.PipelineSpec(
                BLACK_HOLE_POST,
                VeilPostController.PipelinePriority.FEATURE,
                CreditsBlackHolePostFx::wantBlackHole,
                CreditsBlackHolePostFx::feedBlackHole));
    }

    private CreditsBlackHolePostFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!Minecraft.getInstance().isPaused()) {
            fxTicks++;
        }
    }

    private static boolean wantBlackHole() {
        return Minecraft.getInstance().level != null
                && CreditsSkyFx.holeAmount(partialTick()) > MIN_ACTIVE;
    }

    private static void feedBlackHole(PostPipeline pipeline) {
        float partialTick = partialTick();
        if (SunTracker.worldToNdc(CreditsSkyFx.holeCenter(), NDC_SCRATCH)) {
            holeU = NDC_SCRATCH.x * 0.5F + 0.5F;
            holeV = NDC_SCRATCH.y * 0.5F + 0.5F;
        }
        Minecraft minecraft = Minecraft.getInstance();
        float aspect = minecraft.getWindow().getHeight() <= 0 ? 1.0F
                : (float) minecraft.getWindow().getWidth() / minecraft.getWindow().getHeight();
        pipeline.getUniform("Strength").setFloat(CreditsSkyFx.holeAmount(partialTick));
        pipeline.getUniform("Hole").setVector(holeU, holeV);
        pipeline.getUniform("Aspect").setFloat(aspect);
        pipeline.getUniform("Time").setFloat((fxTicks % TIME_WRAP_TICKS + partialTick) / 20.0F);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
        // F-072 V3: the server's gulp beats — horizon breath + ring flare envelope.
        pipeline.getUniform("Pulse").setFloat(CreditsSkyFx.holePulse(partialTick));
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
