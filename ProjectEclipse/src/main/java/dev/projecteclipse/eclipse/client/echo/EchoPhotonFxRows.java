package dev.projecteclipse.eclipse.client.echo;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.woah.echogrove.EchoGroveCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * WOAH-05 {@link PhotonFxRegistry} row registrar (plan §4.2) — the
 * {@code FerrymanFinaleFxRows} pattern. Assets are authored programmatically by
 * {@code tools/photon/echo_grove_fx.py} (fxlib) into
 * {@code assets/eclipse/fx/echo_*.fx}; re-run the script instead of hand-editing
 * the gzip-NBT.
 *
 * <p>The three loops are <b>WINDOWED-only</b> (INTEGRATION.md §4 law — never
 * payload-fired); {@code EchoGroveFx} drives them through
 * {@code ensureLoop}/{@code releaseLoop}. Quasar fallbacks: the ground fog gets
 * the thin {@code limbo_fogbank} stand-in (REPLACE — the mist IS the mood
 * floor); spores/tree-lights/whisper/collect/bloom-rain are Photon-only garnish
 * (legal: pre-row baseline was nothing — the displays, captions and note-block
 * motif carry the moment on photon-less clients).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class EchoPhotonFxRows {
    /** WINDOWED loop ids (client-only mint — the server never fires these). */
    public static final ResourceLocation LOOP_GROUND_FOG = FxCues.cue("woah_echo_ground_fog");
    public static final ResourceLocation LOOP_SPORES = FxCues.cue("woah_echo_spores");
    public static final ResourceLocation LOOP_TREE_LIGHTS = FxCues.cue("woah_echo_tree_lights");

    /** Ash-flakes decay shot fires this long before the flood window ends (plan §3.5 t140). */
    private static final int ASH_LEAD_TICKS = 20;

    private EchoPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // §4.2 #1 — bowl ground fog (WINDOWED). REPLACE: the mist is the mood floor,
        // photon-less clients get the thin limbo fogbank stand-in.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                LOOP_GROUND_FOG,
                fx("echo_ground_fog"),
                fx("limbo_fogbank"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                true));
        // §4.2 #2 — GPU-instanced spore motes (WINDOWED, Photon-only garnish).
        // Tier pick at setup: 1400-mote hero asset on tier 2, the 400-mote _lite
        // otherwise (rows register once; the loops die under reducedFx anyway,
        // so a mid-session tier change only matters on the way back UP — where
        // the setup-time pick is the conservative one).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                LOOP_SPORES,
                fx(FxBudget.qualityTier() >= 2 ? "echo_spores" : "echo_spores_lite"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
        // §4.2 #3 — memory-tree gold motes + glint bursts (WINDOWED, garnish).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                LOOP_TREE_LIGHTS,
                fx("echo_tree_lights"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
        // §4.2 #4/#5 — the memory flood: custom leg latches the grade warmth
        // (a = holdTicks, b = afterglow variant), starts the HDR bloom column and
        // schedules the ash-fall decay shot for the shrink beat.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EchoGroveCues.CUE_ECHO_FLOOD,
                fx("echo_flood_bloom"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                EchoPhotonFxRows::floodLeg));
        // §4.2 #6 — finale blossom rain over the tree (600t one-shot).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EchoGroveCues.CUE_ECHO_BLOOM_RAIN,
                fx("echo_bloom_rain"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // §4.2 #7 — whisper wisps riding the clicked orb (entity lane; the default
        // entity branch in dispatchInternal handles attach + position degrade).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EchoGroveCues.CUE_ECHO_WHISPER,
                fx("echo_whisper_wisp"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // §4.2 #9 — lost-orb collect implosion.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EchoGroveCues.CUE_ECHO_ORB_COLLECT,
                fx("echo_orb_collect"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    /**
     * The flood leg (plan §4.2 cue table): latch first — the grade warmth and the
     * ash schedule must arm even when the Photon spawn itself is refused (budget /
     * photon-less), because the display pool + note motif still play server-side.
     */
    private static boolean floodLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        EchoGroveFx.onFloodCue(a, b);
        boolean played = PhotonBridge.spawn(photonFx, pos);
        int delay = Math.max(40, (int) a - ASH_LEAD_TICKS);
        PhotonBridge.spawn(fx("echo_ash_fall"),
                pos.add(0.0D, 10.0D, 0.0D),
                PhotonBridge.SpawnOptions.DEFAULT.withDelay(delay));
        return played;
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
