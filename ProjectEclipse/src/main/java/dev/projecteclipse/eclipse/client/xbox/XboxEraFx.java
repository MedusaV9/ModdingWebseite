package dev.projecteclipse.eclipse.client.xbox;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * CONSOLE-ERA screen filter for the Xbox tutorial dimensions (C17 fix 4). Registers the
 * {@code eclipse:xbox_era} pipeline (GRADE priority, single uniform {@code Amount}) with
 * {@link VeilPostController} from static init — the landed W1 pattern, so the Iris gate,
 * the ≤3-pass budget and the failure fuse all apply for free.
 *
 * <p><b>State feed:</b> no payload needed — the filter is a pure dimension check
 * ({@link XboxDimensions#isXboxDimension}) eased over {@value #EASE_TICKS} ticks so
 * entering/leaving through the portal fades the grade instead of snapping it.</p>
 *
 * <p><b>reducedFx-safe:</b> the {@code reducedFx} client toggle drives the ease target to
 * zero — the pipeline row deactivates completely (idle-skip below {@value #MIN_ACTIVE}),
 * not merely dims. Iris shaderpacks gate the row off wholesale via the controller.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class XboxEraFx {
    public static final ResourceLocation XBOX_ERA_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "xbox_era");

    /** Portal-transition-friendly fade length (matches the 30-tick ghost grade ease). */
    private static final int EASE_TICKS = 30;
    /** Below this the release is over — drop the pipeline entirely (idle-skip, §3.5). */
    private static final float MIN_ACTIVE = 0.003F;
    /**
     * {@code Time} uniform wrap: ~one hour (the ghost_grade/limbo clock precedent), but
     * snapped to a whole number of scan-band periods — 327 × 11 s × 20 = 71 940 ticks —
     * so the shader's {@code Time / 11.0} band phase is continuous across the wrap (a
     * plain 72 000 would teleport the band ~27% of frame height once per hour).
     */
    private static final int TIME_WRAP_TICKS = 71_940;

    private static float amount;
    private static float previousAmount;
    /** v3 scan-band clock; advances only while unpaused (the grade holds still on pause). */
    private static int bandTicks;

    static {
        // Feature rows register from static init (W1 wiring note): the @EventBusSubscriber
        // scan loads this class during client mod construction, well before the first tick.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                XBOX_ERA_POST,
                VeilPostController.PipelinePriority.GRADE,
                XboxEraFx::wantEraGrade,
                XboxEraFx::feedEraGrade));
    }

    private XboxEraFx() {}

    /** Eased 0..1 grade amount (used by sibling xbox-era classes as the shared curve). */
    public static float amount(float partialTick) {
        return Mth.lerp(partialTick, previousAmount, amount);
    }

    /** Raw dimension gate: inside any Xbox tutorial dimension and effects allowed. */
    public static boolean inXboxDimension() {
        ClientLevel level = Minecraft.getInstance().level;
        return level != null && XboxDimensions.isXboxDimension(level.dimension());
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        previousAmount = amount;
        float target = inXboxDimension() && !EclipseClientConfig.reducedFx() ? 1.0F : 0.0F;
        amount = Mth.clamp(amount + Math.signum(target - amount) * (1.0F / EASE_TICKS),
                Math.min(amount, target), Math.max(amount, target));
        if (!Minecraft.getInstance().isPaused()) {
            bandTicks++;
        }
    }

    private static boolean wantEraGrade() {
        return Minecraft.getInstance().level != null && amount(partialTick()) > MIN_ACTIVE;
    }

    /**
     * Per-frame feeder (no allocations): the frozen {@code Amount} plus the v3 additive
     * {@code Time} (pause-frozen scan-band clock, band-period-aligned ~1 h wrap; int
     * modulo BEFORE the float divide, so long sessions never hit a precision cliff).
     */
    private static void feedEraGrade(PostPipeline pipeline) {
        pipeline.getUniform("Amount").setFloat(amount(partialTick()));
        pipeline.getUniform("Time").setFloat((bandTicks % TIME_WRAP_TICKS + partialTick()) / 20.0F);
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
