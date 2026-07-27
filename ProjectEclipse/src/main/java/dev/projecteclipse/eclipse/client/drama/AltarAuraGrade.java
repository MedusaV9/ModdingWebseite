package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
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
 * <p><b>F-075 V2 additions:</b></p>
 * <ul>
 *   <li><b>{@code Edge}</b> — the boundary-crossing tell: a Gaussian band around the
 *       aura shell at {@value #EDGE_RADIUS} blocks (σ {@value #EDGE_SIGMA}) drives a
 *       narrow refraction ripple + chroma split in the shader, so WALKING ONTO the
 *       island gives one soft "surface tension" wobble. Active from stage
 *       {@value #EDGE_MIN_STAGE} (weak, {@value #EDGE_WEAK_FACTOR}×) — noticeable
 *       before the shimmer era — and scaling with the stage factor above it.</li>
 *   <li><b>{@code Gold}</b> — the stage colour ladder (0.15 / 0.5 / 1.0 at L3/L4/L5):
 *       mixes the highlight-lift and consecration-tint colours from deep violet toward
 *       gold-white, following the Photon layers' per-stage palette.</li>
 *   <li><b>{@link #pulse()}</b> — the stage-up beat: {@code AltarCeremonyFx} fires it
 *       under the {@code altar_aura_powerup} ring wave; a short envelope (attack
 *       {@value #PULSE_ATTACK_TICKS} t, decay {@value #PULSE_DECAY_TICKS} t) adds up to
 *       +{@value #PULSE_MAX} on the fed {@code Aura} scalar (clamped 1) — the whole
 *       grade visibly brightens once. No-op while a cutscene camera runs.</li>
 * </ul>
 *
 * <p><b>Gates:</b> overworld + anchor synced + stage ≥ {@value #MIN_STAGE} (Edge:
 * ≥ {@value #EDGE_MIN_STAGE}); {@code reducedFx} and a live cutscene camera
 * ({@link CameraDirector#isActive()}) zero the tick targets (the pass eases out and the
 * predicate idle-skips it — pure decoration, unlike the ghost grade there is no
 * state-feedback leg to preserve). Iris/config gating, the pass budget and the
 * 3-strikes failure fuse all come from {@link VeilPostController}. Feeder allocates
 * nothing.</p>
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

    /** V2 boundary tell: radius of the aura shell the crossing band sits on (blocks). */
    private static final double EDGE_RADIUS = 24.0D;
    /** Gaussian half-width of the crossing band (blocks). */
    private static final double EDGE_SIGMA = 3.0D;
    /** The boundary tell starts one stage BEFORE the full grade era. */
    private static final int EDGE_MIN_STAGE = 2;
    /** Edge strength floor for the pre-grade stages (L2/L3). */
    private static final float EDGE_WEAK_FACTOR = 0.35F;

    /** V2 stage-up pulse: attack/decay (ticks) and the added Aura headroom. */
    private static final int PULSE_ATTACK_TICKS = 3;
    private static final int PULSE_DECAY_TICKS = 30;
    private static final float PULSE_MAX = 0.5F;

    /** Eased zone×stage strength; fed as the frozen {@code Aura} scalar (breath on top). */
    private static float eased;
    /** Eased boundary-band strength; fed as the {@code Edge} scalar. */
    private static float edgeEased;
    /** Eased stage colour ladder; fed as the {@code Gold} scalar. */
    private static float goldEased;
    /** Ticks since {@link #pulse()}; {@link Integer#MIN_VALUE} = no pulse live. */
    private static int pulseAge = Integer.MIN_VALUE;

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
        boolean gated = isGated();
        eased = slew(eased, gated ? 0.0F : auraTarget());
        edgeEased = slew(edgeEased, gated ? 0.0F : edgeTarget());
        goldEased = slew(goldEased, gated ? 0.0F : goldTarget());
        if (pulseAge != Integer.MIN_VALUE
                && ++pulseAge > PULSE_ATTACK_TICKS + PULSE_DECAY_TICKS) {
            pulseAge = Integer.MIN_VALUE;
        }
    }

    /**
     * F-075 V2 stage-up beat: brightens the whole grade once (fired by
     * {@code AltarCeremonyFx} under the {@code altar_aura_powerup} ring wave). Armed
     * only for WITNESSES — camera inside the {@value #ZONE_RADIUS}-block zone (the
     * ceremony script runs world-wide; a screen-space brighten must not) — and no-op
     * while a cutscene camera owns the frame: the pass targets are zero there and the
     * pulse must not force it back in.
     */
    public static void pulse() {
        if (CameraDirector.isActive()) {
            return;
        }
        Double dist = anchorDistance();
        if (dist != null && dist <= ZONE_RADIUS) {
            pulseAge = 0;
        }
    }

    /** Shared hard gates: wrong dim / no level / reducedFx / cutscene camera. */
    private static boolean isGated() {
        ClientLevel level = Minecraft.getInstance().level;
        return level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx() || CameraDirector.isActive();
    }

    /** {@code stageFactor × (1 − d/72)²} — 0 while below stage {@value #MIN_STAGE}. */
    private static float auraTarget() {
        int stage = clampedStage();
        if (stage < MIN_STAGE) {
            return 0.0F;
        }
        Double dist = anchorDistance();
        if (dist == null) {
            return 0.0F;
        }
        float proximity = (float) Mth.clamp(1.0D - dist / ZONE_RADIUS, 0.0D, 1.0D);
        return stageFactor(stage) * proximity * proximity;
    }

    /** Gaussian band at the {@value #EDGE_RADIUS}-block shell × stage strength. */
    private static float edgeTarget() {
        int stage = clampedStage();
        if (stage < EDGE_MIN_STAGE) {
            return 0.0F;
        }
        Double dist = anchorDistance();
        if (dist == null) {
            return 0.0F;
        }
        double delta = dist - EDGE_RADIUS;
        float band = (float) Math.exp(-(delta * delta) / (2.0D * EDGE_SIGMA * EDGE_SIGMA));
        return Math.max(EDGE_WEAK_FACTOR, stageFactor(stage)) * band;
    }

    /** The stage colour ladder (plan table): 0 below L3, then 0.15 / 0.5 / 1.0. */
    private static float goldTarget() {
        return switch (clampedStage()) {
            case 3 -> 0.15F;
            case 4 -> 0.5F;
            case 5 -> 1.0F;
            default -> 0.0F;
        };
    }

    /** {@code (stage − 2) / 3} for stages 3..5, i.e. ⅓ / ⅔ / 1 (0 below). */
    private static float stageFactor(int stage) {
        return Mth.clamp((stage - (MIN_STAGE - 1)) / (float) (5 - (MIN_STAGE - 1)), 0.0F, 1.0F);
    }

    private static int clampedStage() {
        return Math.min(Math.max(ClientStateCache.altarLevel, 0), 5);
    }

    /** Camera distance to the altar anchor, or {@code null} while the anchor is unset. */
    private static Double anchorDistance() {
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null) {
            return null;
        }
        return Minecraft.getInstance().gameRenderer.getMainCamera().getPosition()
                .distanceTo(anchor);
    }

    private static float slew(float value, float target) {
        if (value < target) {
            return Math.min(target, value + SLEW_PER_TICK);
        }
        if (value > target) {
            return Math.max(target, value - SLEW_PER_TICK);
        }
        return value;
    }

    /** Stage-up pulse envelope 0..1 (attack 3 t, decay 30 t; 0 while idle). */
    private static float pulseEnvelope() {
        if (pulseAge == Integer.MIN_VALUE) {
            return 0.0F;
        }
        if (pulseAge <= PULSE_ATTACK_TICKS) {
            return pulseAge / (float) PULSE_ATTACK_TICKS;
        }
        return Mth.clamp(1.0F - (pulseAge - PULSE_ATTACK_TICKS) / (float) PULSE_DECAY_TICKS,
                0.0F, 1.0F);
    }

    /** Disconnect reset: a sanctum visit never leaks its shimmer into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        eased = 0.0F;
        edgeEased = 0.0F;
        goldEased = 0.0F;
        pulseAge = Integer.MIN_VALUE;
    }

    // ------------------------------------------------------------------ pipeline row

    private static boolean wantPost() {
        return Minecraft.getInstance().level != null
                && (eased > MIN_ACTIVE || edgeEased > MIN_ACTIVE
                        || pulseAge != Integer.MIN_VALUE);
    }

    /**
     * Frozen {@code Aura} scalar with the 0.15 Hz breath premultiplied (flattened to its
     * mean under {@code reducedFx} — only reachable through the dev force-on override,
     * the tick target is already zero there) plus the stage-up pulse headroom (clamped
     * at 1), the {@code Edge} boundary band, the {@code Gold} colour ladder, the shared
     * wrap clock and the Detail gate.
     */
    private static void feedPost(PostPipeline pipeline) {
        float seconds = (System.currentTimeMillis() % 100_000L) / 1000.0F;
        float breath = EclipseClientConfig.reducedFx()
                ? 0.96F
                : 0.96F + 0.04F * Mth.sin(seconds * Mth.TWO_PI * BREATH_HZ);
        pipeline.getUniform("Aura").setFloat(
                Math.min(1.0F, eased * breath + PULSE_MAX * pulseEnvelope()));
        pipeline.getUniform("Edge").setFloat(edgeEased);
        pipeline.getUniform("Gold").setFloat(goldEased);
        pipeline.getUniform("Time").setFloat(seconds);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }
}
