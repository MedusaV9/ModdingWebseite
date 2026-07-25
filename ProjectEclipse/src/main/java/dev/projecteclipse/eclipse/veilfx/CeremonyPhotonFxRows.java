package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * NEWFX-B's {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the altar/souls/ceremonies package of PLAN-NEWFX §2 (B1–B5). Assets are
 * fxlib-generated ({@code tools/photon/ceremony_fx.py} is the committed source); Quasar
 * fallback emitters live beside the shipped set under
 * {@code assets/eclipse/quasar/emitters/}.
 *
 * <p>Per-row shape (PLAN-NEWFX §2 specs):</p>
 * <ul>
 *   <li><b>B1 dawn toll</b> — custom leg, both layers spawned in-leg so the plan's
 *       reducedFx law ("skip entirely; reduced players keep the pre-plan bells-only
 *       dawn") can gate Photon AND Quasar with one check. Entity lane, personal send.</li>
 *   <li><b>B2 rebirth starfall</b> — the package's one {@code Mode.REPLACE} row: the
 *       Photon file IS the ceremony; the {@code eclipse:rebirth_ring} Quasar leg runs
 *       only when the Photon spawn refuses (photon-less / reducedFx clients). The old
 *       vanilla TOTEM/REVERSE_PORTAL/END_ROD spam was removed at the seam.</li>
 *   <li><b>B3 offering gutter</b> — plain LAYER row. Default {@code allowMulti=false}
 *       doubles as the anti-spam: repeated "already offered" clicks inside the ~40t
 *       runtime dedup the Photon show while the cheap Quasar ash puff still answers
 *       every click (BURST budget caps the worst case).</li>
 *   <li><b>B4 soul departure / B5 revive thunderbloom</b> — plain LAYER rows on the
 *       SEQUENCE channel (rare, dramatic); under reducedFx the Photon leg is off by
 *       {@code PhotonBridge.available()} and the Quasar wisp/ring stays — exactly the
 *       plan's reduced forms.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CeremonyPhotonFxRows {
    /**
     * B1 Quasar layer: bell-glint dust shed under the petal triangle. The Photon petals
     * hang ~7 blocks over the EYE anchor; the glint emitter is spawned at feet + this.
     */
    private static final double DAWN_GLINT_HEIGHT = 8.0D;
    /** B1 position-anchor degrade: approximate the missing entity's eye height. */
    private static final double DAWN_EYE_FALLBACK = 1.6D;

    private CeremonyPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // B1 — dawn toll bloom (entity lane, personal; asset paces itself to the bells).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_DAWN_TOLL,
                fx("dawn_toll_bloom"),
                null, // Quasar layer spawned in-leg (reducedFx gates both legs at once)
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                CeremonyPhotonFxRows::dawnTollBloom));
        // B2 — Starfall Rebirth (entity lane on the reborn player, REPLACE hero).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_REBIRTH_CEREMONY,
                fx("rebirth_starfall"),
                quasar("rebirth_ring"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // B3 — offering gutter (position lane at the altar crown, the anti-climax).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_OFFERING_REJECT,
                fx("offering_gutter"),
                quasar("offering_gutter_puff"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B4 — soul departure (position lane at the corpse of a FINAL death).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_GHOST_DEPARTURE,
                fx("ghost_soul_departure"),
                quasar("ghost_departure_wisp"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B5 — revive thunderbloom (position lane at the altar crown, range 96).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_REVIVE_COMPLETE,
                fx("revive_thunderbloom"),
                quasar("revive_thunderbloom_ring"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    /**
     * {@code CUE_DAWN_TOLL} leg — PLAN-NEWFX B1. reducedFx skips the WHOLE composition
     * (the ceremony's sun pulse + bells already carry the beat; reduced players keep the
     * exact pre-plan dawn), which is why the Quasar glint layer is spawned here instead
     * of riding the row's quasar column: a LAYER row would play it under reducedFx.
     * Consumed cues always return {@code true} — with a {@code null} row emitter there
     * is no REPLACE re-entry to drive.
     */
    private static boolean dawnTollBloom(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true;
        }
        Vec3 feet = entity != null ? entity.position() : pos;
        // Bell-glint dust under the petal triangle (the photon-less baseline too).
        QuasarSpawner.spawn(quasar("dawn_toll_glint"),
                feet.add(0.0D, DAWN_GLINT_HEIGHT, 0.0D), FxBudget.Channel.SEQUENCE);
        if (entity != null) {
            // The receiving player is always client-tracked (the cue is addressed to
            // them alone), so this is the live path; petals ride the eye anchor.
            PhotonBridge.spawnOnEntity(photonFx, entity,
                    PhotonBridge.AUTO_ROTATE_NONE, (Vec3) null);
        } else {
            PhotonBridge.spawn(photonFx, pos.add(0.0D, DAWN_EYE_FALLBACK, 0.0D));
        }
        return true;
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    private static ResourceLocation quasar(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
