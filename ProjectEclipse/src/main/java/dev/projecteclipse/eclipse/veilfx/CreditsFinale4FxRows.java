package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-090/F-093 "Map-Zerreißen V3" {@link PhotonFxRegistry} row registrar — the map-rip
 * cues (the {@link CreditsFinale3FxRows} sibling; cue ids via {@link FxCues#cue} so the
 * shared {@code FxCues} class stays untouched). Assets are authored programmatically by
 * {@code tools/photon/credits4_fx.py} (fxlib) into {@code assets/eclipse/fx/*.fx};
 * re-run the script instead of hand-editing the gzip-NBT. All senders live in
 * {@code ritual.CreditsSequence.mapRipBeats} (+ the FX-only BLACKHOLE replay).
 *
 * <p>All three rows are Photon-only garnish (Quasar leg {@code null} — legal for NEW
 * cues, the {@code CUE_LANDMARK_ECHO} precedent): the rip itself is carried by the
 * {@code CreditsMapRipAct} display entities plus the shake/SFX beats, so photon-less
 * clients still read every event.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CreditsFinale4FxRows {

    /** V3 crack-front step: seam glow motes + rising dust curtain + a short debris jet. */
    public static final ResourceLocation CUE_CREDITS4_CRACKFRONT = FxCues.cue("credits4_crackfront");
    /** V3 mid-air sub-fracture: one sharp split flash + a shard puff at the snap point. */
    public static final ResourceLocation CUE_CREDITS4_PLATEBREAK = FxCues.cue("credits4_platebreak");
    /** V3 jet shred: two opposed fast particle streams + stretched sparks along ±jet axis. */
    public static final ResourceLocation CUE_CREDITS4_JETBURST = FxCues.cue("credits4_jetburst");

    private CreditsFinale4FxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // F-090/F-093 — crack-front step veil: glow motes hugging the seam + a rising
        // dust curtain + a short upward debris jet (~40t one-shot, fired at every
        // propagation step's segment midpoint — 18 fires across the three fronts).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS4_CRACKFRONT,
                fx("credits4_crackfront"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-090/F-093 — plate sub-fracture burst: one hot split flash + a handful of
        // slow shard puffs (~30t one-shot, fired once per plate at lift+40t, ≈40 fires
        // de-phased by the per-plate lift jitter).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS4_PLATEBREAK,
                fx("credits4_platebreak"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-090/F-093 — jet burst: two opposed fast particle streams up/down the maw's
        // polar axis + stretched sparks (~60t one-shot per shredded sub-plate crossing,
        // paired with the S2CCreditsJetPayload shader strobe).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS4_JETBURST,
                fx("credits4_jetburst"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
