package dev.projecteclipse.eclipse.client.xbox;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import dev.projecteclipse.eclipse.xboxevent.XboxEraProfile;
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
 * <p><b>TUT2 — PER-ERA grade.</b> {@code Amount} used to be the whole story, so all seven
 * tutorial worlds shared one console look and only the (now deleted) bundled retro textures
 * were meant to tell them apart. The era now comes from {@link XboxEraProfile}: tint,
 * saturation, contrast and vignette are looked up per WORLD and fed as their own uniforms,
 * and they ease on the same {@value #EASE_TICKS}-tick curve as {@code Amount} — so a portal
 * hop straight from one tutorial world to another (where {@code Amount} never leaves 1)
 * crossfades between the two era looks instead of snapping.</p>
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

    /**
     * TUT2 eased era parameters, in {@link XboxEraProfile} order:
     * {@code tintR, tintG, tintB, saturation, contrast, vignette}. Held in a plain array so
     * the per-frame feeder never allocates; the neutral rest state below is what the shader
     * sees outside the tutorial worlds and while the first era eases in.
     */
    private static final float[] NEUTRAL_ERA = {1.0F, 1.0F, 1.0F, 0.0F, 1.0F, 1.0F};
    private static final float[] ERA = NEUTRAL_ERA.clone();
    private static final float[] ERA_TARGET = NEUTRAL_ERA.clone();
    /**
     * Per-parameter ease rate: the WIDEST swing any era row asks for, spread over
     * {@value #EASE_TICKS} ticks. One shared rate per parameter (rather than one derived
     * from the current pair) keeps every transition the same visual speed, including the
     * ease back to neutral when the player leaves — the {@code Amount} fade would otherwise
     * be racing a grade that had already snapped.
     */
    private static final float[] ERA_RATE = eraRates();

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

    /** The era grade of the world the client is standing in, or {@code null} outside. */
    @Nullable
    public static XboxEraProfile currentEra() {
        ClientLevel level = Minecraft.getInstance().level;
        return level == null ? null : XboxEraProfile.byDimension(level.dimension());
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        previousAmount = amount;
        float target = inXboxDimension() && !EclipseClientConfig.reducedFx() ? 1.0F : 0.0F;
        amount = Mth.clamp(amount + Math.signum(target - amount) * (1.0F / EASE_TICKS),
                Math.min(amount, target), Math.max(amount, target));
        easeEra(currentEra());
        if (!Minecraft.getInstance().isPaused()) {
            bandTicks++;
        }
    }

    /**
     * Walks the six era parameters toward the current world's row (or back to neutral when
     * there is none). Same clamp trick as {@code amount}: step toward the target and never
     * overshoot it. Allocation-free — {@link #ERA_TARGET} is a reused scratch buffer.
     */
    private static void easeEra(@Nullable XboxEraProfile era) {
        writeEra(era, ERA_TARGET);
        for (int i = 0; i < ERA.length; i++) {
            float step = Math.signum(ERA_TARGET[i] - ERA[i]) * ERA_RATE[i];
            ERA[i] = Mth.clamp(ERA[i] + step, Math.min(ERA[i], ERA_TARGET[i]),
                    Math.max(ERA[i], ERA_TARGET[i]));
        }
    }

    private static void writeEra(@Nullable XboxEraProfile era, float[] out) {
        if (era == null) {
            System.arraycopy(NEUTRAL_ERA, 0, out, 0, out.length);
            return;
        }
        out[0] = era.tintR();
        out[1] = era.tintG();
        out[2] = era.tintB();
        out[3] = era.saturation();
        out[4] = era.contrast();
        out[5] = era.vignette();
    }

    private static float[] eraRates() {
        float[] widest = new float[NEUTRAL_ERA.length];
        float[] row = new float[NEUTRAL_ERA.length];
        for (XboxEraProfile era : XboxEraProfile.values()) {
            writeEra(era, row);
            for (int i = 0; i < widest.length; i++) {
                widest[i] = Math.max(widest[i], Math.abs(row[i] - NEUTRAL_ERA[i]));
            }
        }
        for (int i = 0; i < widest.length; i++) {
            // A zero-width parameter would freeze; give it the smallest useful step.
            widest[i] = Math.max(widest[i], 1.0E-3F) / EASE_TICKS;
        }
        return widest;
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
        // TUT2 per-era row (already eased on the tick; no interpolation needed at 30 t).
        pipeline.getUniform("EraTint").setVector(ERA[0], ERA[1], ERA[2]);
        pipeline.getUniform("EraSaturation").setFloat(ERA[3]);
        pipeline.getUniform("EraContrast").setFloat(ERA[4]);
        pipeline.getUniform("EraVignette").setFloat(ERA[5]);
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }
}
