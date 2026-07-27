package dev.projecteclipse.eclipse.woah.chronostasis.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-03 zone grade (plan §4.2): {@code eclipse:chrono_grade} — desaturated cool light,
 * gentle vignette and a very fine additive "time dust" glitter, driven by the eased
 * {@link ChronoZoneState#amount}. Registered from static init as a
 * {@link VeilPostController.PipelineSpec} on the GRADE band (the {@code XboxEraFx}
 * pattern), so the Iris gate, ≤3-pass budget and failure fuse all apply for free.
 *
 * <p>{@code reducedFx} gates the row off wholesale here (the amount itself stays alive
 * for the tick sound / rain mixin — plan §8). During a discharge the feeder adds the
 * {@link ChronoZoneState#dischargeFlash} white kick through the {@code Flash} uniform —
 * one uniform pulse, never a second pass.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ChronoGradeFx {
    public static final ResourceLocation CHRONO_GRADE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "chrono_grade");

    /** Time-dust clock wrap (~1 h; the glitter hash re-seeds invisibly on wrap). */
    private static final int TIME_WRAP_TICKS = 72_000;

    /** Pause-frozen glitter clock. */
    private static int dustTicks;

    static {
        VeilPostController.register(new VeilPostController.PipelineSpec(
                CHRONO_GRADE_POST,
                VeilPostController.PipelinePriority.GRADE,
                ChronoGradeFx::wantGrade,
                ChronoGradeFx::feedGrade));
    }

    private ChronoGradeFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!Minecraft.getInstance().isPaused()) {
            dustTicks++;
        }
    }

    private static boolean wantGrade() {
        return Minecraft.getInstance().level != null
                && !EclipseClientConfig.reducedFx()
                && ChronoZoneState.amount(partialTick()) > ChronoZoneState.MIN_ACTIVE;
    }

    /** Allocation-free per-frame feeder (plan §4.2 uniform set). */
    private static void feedGrade(PostPipeline pipeline) {
        pipeline.getUniform("Amount").setFloat(ChronoZoneState.amount(partialTick()));
        pipeline.getUniform("Time").setFloat(
                (dustTicks % TIME_WRAP_TICKS + partialTick()) / 20.0F);
        pipeline.getUniform("Tint").setVector(0.82F, 0.90F, 1.10F);
        pipeline.getUniform("Saturation").setFloat(0.55F);
        pipeline.getUniform("Contrast").setFloat(1.03F);
        pipeline.getUniform("Vignette").setFloat(1.3F);
        pipeline.getUniform("Flash").setFloat(ChronoZoneState.dischargeFlash());
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
