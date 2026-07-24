package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering payload registrar for the journey / main-menu-v2 suite
 * ({@code docs/plans_v3/P3_ui.md} P3-W8). No {@code EclipsePayloads} hub edit — multiple
 * {@link RegisterPayloadHandlersEvent} subscribers are legal (plan hard rule 3).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class JourneyPayloads {
    private JourneyPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar("2");
        registrar.playToClient(S2COpStatusPayload.TYPE, S2COpStatusPayload.STREAM_CODEC,
                JourneyPayloads::handleOpStatus);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleOpStatus(S2COpStatusPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.menu.JourneyController.onOpStatus(payload.opLevel());
    }

    /**
     * Tiny server-side login sender (game bus): every login pushes the player's current op
     * level so the client-side cache mirrors server truth (op granted OR revoked) each session.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID)
    static final class LoginSender {
        private LoginSender() {}

        @SubscribeEvent
        static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
            if (event.getEntity() instanceof ServerPlayer player) {
                PacketDistributor.sendToPlayer(player,
                        new S2COpStatusPayload(player.server.getProfilePermissions(player.getGameProfile())));
            }
        }
    }
}
