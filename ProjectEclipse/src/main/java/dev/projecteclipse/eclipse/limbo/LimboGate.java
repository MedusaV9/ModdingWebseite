package dev.projecteclipse.eclipse.limbo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.sequence.SequencePayloads;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Pre-event containment: until the start event has run ({@code startEventDone}), every
 * player who logs in or respawns OUTSIDE limbo is brought to the ghost ship. This is the
 * "everyone waits in limbo until the event begins" rule — the overworld disc only becomes
 * reachable through {@code /start_event}'s intro sequence.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LimboGate {

    /** W4-CEREMONY / IDEA-01 #2: R13 veil around the gate hop (same pair as the late-joiner path). */
    private static final int PORTAL_ENTER_TICKS = 4;
    private static final int PORTAL_EXIT_TICKS = 24;
    private static final String CAPTION_ARRIVE = "eclipse.caption.limbo.arrive";

    private LimboGate() {}

    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            gate(player);
        }
    }

    @SubscribeEvent
    static void onRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            gate(player);
        }
    }

    private static void gate(ServerPlayer player) {
        MinecraftServer server = player.getServer();
        if (server == null) {
            return;
        }
        if (StartEventCutscene.gatherLateJoiner(player)) {
            return;
        }
        if (EclipseWorldState.get(server).isStartEventDone()) {
            return;
        }
        if (player.level().dimension().equals(LimboDimension.LIMBO)) {
            return;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("LimboGate: limbo dimension missing; cannot gate {}",
                    player.getScoreboardName());
            return;
        }
        BlockPos arrival = GhostShipBuilder.platformArrivalPos(limbo);
        // W4-CEREMONY / IDEA-01 #2: wrap the hard snap in the R13 portal veil so the very
        // first frame of the event is a directed reveal of the ship, not a teleport pop —
        // exactly the enter-4/exit-24 pair the late-joiner path already uses.
        SequencePayloads.sendPortalEnter(player, PORTAL_ENTER_TICKS);
        player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D,
                player.getYRot(), 0.0F);
        SequencePayloads.sendPortalExit(player, PORTAL_EXIT_TICKS);
        PacketDistributor.sendToPlayer(player,
                new S2CCaptionPayload(CAPTION_ARRIVE, 80, S2CCaptionPayload.STYLE_WHISPER));
        EclipseMod.LOGGER.info("LimboGate: {} gated to the ghost ship (pre-event)",
                player.getScoreboardName());
    }
}
