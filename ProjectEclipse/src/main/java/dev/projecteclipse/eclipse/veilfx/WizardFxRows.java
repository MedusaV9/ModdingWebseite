package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * POLISH1-FXCOUPLING — Wizard Orin's {@link PhotonFxRegistry} row registrar
 * ({@code MobPhotonFxRows} reference pattern), the MB2 §7.2 registrar built for real.
 * One row, {@code Mode.LAYER} with a {@code null} Quasar leg: the star_call trigger
 * point already ships a complete vanilla baseline (EVOKER_PREPARE_SUMMON + rising
 * AMETHYST chimes + END_ROD zone sparkles + the per-bolt Firework/END_ROD impacts),
 * which stays bit-identical on photon-less clients — Photon only lays the Kür on top.
 *
 * <p>Custom {@code PhotonLeg} (INTEGRATION §3.5): the cue rides the ENTITY lane so the
 * staff-tip column follows the (rooted but torso-turning) wizard. {@code
 * AutoRotate.XROT} rotates the effect root with Orin's body yaw, so the asset's baked
 * staff-tip offset (local z +0.31 = the geo's 5 px entity-RIGHT staff line) stays on
 * the staff through the whole raise — the {@code wizard_catalyst_indraw} anchor
 * convention, upgraded from "lateral offset zeroed" to "lateral offset baked + rotated".
 * The leg also resolves MB2 §9.2's single-sheet honesty gap: {@code a} (seconds to the
 * release beat) at or below {@value #FAST_BEAT_CUTOFF_S} picks the
 * {@code wizard_star_call_fast} variant (19t release + 70t shower) instead of the base
 * asset (26t + 50t), so the unveiled cast's flash lands ON its 0.95 s beat instead of
 * 0.35 s late. Untracked targets degrade to the payload's position anchor at staff-tip
 * height (the {@code FxPayloads} glide law).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class WizardFxRows {
    /**
     * Eye→staff-tip anchor drop on Orin: eye 1.80 minus the MB2 §7.4 anchor height
     * y +1.40 over foot. The lateral staff-line offset is BAKED into the asset (local
     * z +0.31) because executor offsets are world-space and would not turn with the
     * body — only local coordinates rotate under {@code AutoRotate.XROT}.
     */
    private static final Vec3 STAR_TIP_OFFSET = new Vec3(0.0D, -0.40D, 0.0D);
    /** Position-lane degrade: re-lift the feet-anchored payload pos to tip height. */
    private static final double STAR_TIP_ABOVE_FEET = 1.40D;
    /**
     * Cue {@code a} (seconds to the release beat) at or below this plays the
     * {@code _fast} variant. Base sends 1.30, unveiled 0.95 — the cutoff sits between
     * with margin on both sides, so float wobble can never flip the pick.
     */
    private static final float FAST_BEAT_CUTOFF_S = 1.1F;

    private static final ResourceLocation STAR_CALL_FAST = fx("wizard_star_call_fast");

    private WizardFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // MB2 §7.2 — star_call conducting partner (entity lane, variant-picking leg).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WIZARD_STAR_CALL,
                fx("wizard_star_call"),
                null,                      // vanilla chimes/END_ROD stay the baseline
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                WizardFxRows::playStarCall));
    }

    /** The variant-picking XROT staff-tip leg (see the class javadoc). */
    private static boolean playStarCall(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        ResourceLocation asset = a > 0.0F && a <= FAST_BEAT_CUTOFF_S ? STAR_CALL_FAST : photonFx;
        if (entity != null) {
            return PhotonBridge.spawnOnEntity(asset, entity,
                    PhotonBridge.AUTO_ROTATE_XROT, STAR_TIP_OFFSET);
        }
        return PhotonBridge.spawn(asset, pos.add(0.0D, STAR_TIP_ABOVE_FEET, 0.0D));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
