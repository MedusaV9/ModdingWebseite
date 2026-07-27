package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * F-075's Veil garnish: the {@code eclipse:altar_aura_grade} post pass — a subtle
 * heat-shimmer + highlight-bloom + consecration-tint grade that makes the air over the
 * sanctum island read "magisch" once the altar reaches the high stages. Registered from
 * static init ({@link dev.projecteclipse.eclipse.client.GhostGradeFx} pattern) at
 * {@link VeilPostController.PipelinePriority#GRADE} — deliberately the LOWEST priority:
 * when the ≤3-concurrent-pass budget fills (night grade + sun halo + the altar
 * aberration zone all want in around the island), THIS row is evicted first. That is
 * the sanctioned F-075 contract — "GRADE-Pass nur wenn frei, Photon ist die Baseline":
 * the {@code AltarAuraIdle} Photon loops carry the stage read on their own, and losing
 * this pass costs only garnish.
 *
 * <p><b>Strength script</b> (computed per tick, eased over ~{@value #EASE_TICKS} ticks
 * so anchor sync / stage changes / walking never pop):
 * {@code stageFactor((altarLevel − 2) / 3, levels 3..5) × proximity((1 − d/72)²)}
 * against the {@link FxAnchors#ALTAR_CENTER} anchor — zero below stage
 * {@value #MIN_STAGE}, zero beyond {@value #ZONE_RADIUS} blocks, full only at L5 on the
 * island itself. The proximity radius sits INSIDE the near-field aura band (96), so the
 * shimmer always arrives after the particle aura already established the place.</p>
 *
 * <p><b>Gates:</b> overworld + anchor synced + stage ≥ {@value #MIN_STAGE};
 * {@code reducedFx} zeroes the tick target (the pass eases out and the predicate
 * idle-skips it — pure decoration, unlike the ghost grade there is no state-feedback
 * leg to preserve). Iris/config gating, the pass budget and the 3-strikes failure fuse
 * all come from {@link VeilPostController}. Feeder allocates nothing.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarAuraGrade {
    public static final ResourceLocation ALTAR_AURA_GRADE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_aura_grade");

    /** The Veil garnish is a HIGH-stage tell: dead below altar level 3. */
    private static final int MIN_STAGE = 3;
    /** Proximity zone radius (blocks) — inside the 96-block near-field aura LOD band. */
    private static final double ZONE_RADIUS = 72.0D;
    /** Full strength change completes in ~1 s (20 ticks) — the AltarAberration cadence. */
    private static final int EASE_TICKS = 20;
    private static final float SLEW_PER_TICK = 1.0F / EASE_TICKS;
    /** Below this eased strength the pipeline drops entirely (idle-skip, §3.5). */
    private static final float MIN_ACTIVE = 0.01F;
    /** Breath: 0.15 Hz, ±8% — slower than the aberration's 0.3 Hz so the two never beat. */
    private static final float BREATH_HZ = 0.15F;

    /** Eased zone×stage strength; fed as the frozen {@code Aura} scalar (breath on top). */
    private static float eased;

    static {
        VeilPostController.register(new VeilPostController.PipelineSpec(
                ALTAR_AURA_GRADE_POST,
                VeilPostController.PipelinePriority.GRADE,
                AltarAuraGrade::wantPost,
                AltarAuraGrade::feedPost));
    }

    private AltarAuraGrade() {}

    // ------------------------------------------------------------------ per-tick strength

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        float target = tickTarget();
        if (eased < target) {
            eased = Math.min(target, eased + SLEW_PER_TICK);
        } else if (eased > target) {
            eased = Math.max(target, eased - SLEW_PER_TICK);
        }
    }

    /** {@code stageFactor × (1 − d/72)²} — 0 while gated (wrong dim / no anchor / reducedFx). */
    private static float tickTarget() {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            return 0.0F;
        }
        int stage = Math.min(ClientStateCache.altarLevel, 5);
        if (stage < MIN_STAGE) {
            return 0.0F;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null) {
            return 0.0F;
        }
        double dist = minecraft.gameRenderer.getMainCamera().getPosition().distanceTo(anchor);
        float proximity = (float) Mth.clamp(1.0D - dist / ZONE_RADIUS, 0.0D, 1.0D);
        return (stage - (MIN_STAGE - 1)) / (float) (5 - (MIN_STAGE - 1)) * proximity * proximity;
    }

    /** Disconnect reset: a sanctum visit never leaks its shimmer into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        eased = 0.0F;
    }

    // ------------------------------------------------------------------ pipeline row

    private static boolean wantPost() {
        return Minecraft.getInstance().level != null && eased > MIN_ACTIVE;
    }

    /**
     * Frozen {@code Aura} scalar with the 0.15 Hz breath premultiplied (flattened to its
     * mean under {@code reducedFx} — only reachable through the dev force-on override,
     * the tick target is already zero there) + the shared wrap clock + the Detail gate.
     */
    private static void feedPost(PostPipeline pipeline) {
        float seconds = (System.currentTimeMillis() % 100_000L) / 1000.0F;
        float breath = EclipseClientConfig.reducedFx()
                ? 0.96F
                : 0.96F + 0.04F * Mth.sin(seconds * Mth.TWO_PI * BREATH_HZ);
        pipeline.getUniform("Aura").setFloat(eased * breath);
        pipeline.getUniform("Time").setFloat(seconds);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }
}
