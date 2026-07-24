package dev.projecteclipse.eclipse.limbo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;

/**
 * Pre-event containment: until the start event has run ({@code startEventDone}), every
 * player who logs in or respawns OUTSIDE limbo is brought to the ghost ship. This is the
 * "everyone waits in limbo until the event begins" rule — the overworld disc only becomes
 * reachable through {@code /start_event}'s intro sequence.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LimboGate {
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
        if (server == null || EclipseWorldState.get(server).isStartEventDone()) {
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
        player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D,
                player.getYRot(), 0.0F);
        EclipseMod.LOGGER.info("LimboGate: {} gated to the ghost ship (pre-event)",
                player.getScoreboardName());
    }
}
