package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Ghost-state screen grade for 0-lives players (P2 R18(c), W10). Registers the
 * {@code eclipse:ghost_grade} pipeline (GRADE priority, frozen §3.3 — single uniform
 * {@code Ghost}) with {@link VeilPostController} from static init, the landed W1 pattern.
 *
 * <p><b>State feed:</b> P3/P4's death flow sends {@code S2CGhostStatePayload}; W1's
 * {@code FxPayloads} handler already dispatches it into
 * {@link EclipseFxState#setGhost(boolean)}, which eases the amount over 30 ticks. This class
 * only turns that eased amount into the pipeline row: activation predicate (idle-skip when
 * fully released, §3.5) plus the per-frame uniform feeder.</p>
 *
 * <p><b>Breathing:</b> the design's subtle 0.2&nbsp;Hz breathing rides the {@code Ghost}
 * scalar CPU-side (a ±4% modulation of the eased amount) because the frozen uniform list
 * for this pipeline is {@code Ghost} only — no {@code Time} uniform to animate in-shader.
 * The breath clock advances only while unpaused, so the grade holds still on the pause
 * screen like every other eased FX curve.</p>
 *
 * <p><b>Iris fallback:</b> none, by design (R18: grade-only, acceptable) — the pipeline is
 * gated off with the rest of the post stack while a shaderpack is active.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GhostGradeFx {
    public static final ResourceLocation GHOST_GRADE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ghost_grade");

    /** 0.2 Hz = one breath every 100 ticks. */
    private static final int BREATH_PERIOD_TICKS = 100;
    /** The eased amount is modulated by ±{@value}/2 (subtle, per R18). */
    private static final float BREATH_DEPTH = 0.08F;
    /** Below this the 30-tick release is over — drop the pipeline entirely (idle-skip). */
    private static final float MIN_ACTIVE = 0.003F;

    /** Breath clock; advances only while the game runs (pause freezes the throb). */
    private static int breathTicks;

    static {
        // Feature rows register from static init (W1 wiring note): the @EventBusSubscriber
        // scan loads this class during client mod construction, well before the first tick.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                GHOST_GRADE_POST,
                VeilPostController.PipelinePriority.GRADE,
                GhostGradeFx::wantGhostGrade,
                GhostGradeFx::feedGhostGrade));
    }

    private GhostGradeFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!Minecraft.getInstance().isPaused()) {
            breathTicks++;
        }
    }

    /** Active while the eased ghost amount is above the release floor (in any dimension). */
    private static boolean wantGhostGrade() {
        return Minecraft.getInstance().level != null
                && EclipseFxState.ghostAmount(partialTick()) > MIN_ACTIVE;
    }

    /** Per-frame feeder (no allocations): the single frozen uniform. */
    private static void feedGhostGrade(PostPipeline pipeline) {
        pipeline.getUniform("Ghost").setFloat(ghostUniform(partialTick()));
    }

    /** Eased ghost amount with the 0.2 Hz breath premultiplied (0..1). */
    private static float ghostUniform(float partialTick) {
        float amount = EclipseFxState.ghostAmount(partialTick);
        float breath = 0.5F + 0.5F * Mth.sin(
                (breathTicks + partialTick) * (Mth.TWO_PI / BREATH_PERIOD_TICKS));
        return amount * (1.0F - BREATH_DEPTH + BREATH_DEPTH * breath);
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
