package dev.projecteclipse.eclipse.limbo.door;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;

/**
 * P2-W10 relog seam fix (WB-GHOSTFX): the ship-door glow's desired on/off state lives
 * client-side in {@code client.ShipDoorGlow} and resets on disconnect, while the
 * {@code eclipse:fx/door_glow} event otherwise only travels on door state CHANGES — so a
 * player who relogs while the door is lit would see no glow until the next change. This
 * hook re-fires the current cue per player at login via
 * {@link RespawnDoorApi#resyncGlowFor} (which no-ops safely while limbo/the door is
 * absent). Mirrors the {@code FxAnchors} login re-send pattern; the anchor and the event
 * may arrive in either order — {@code ShipDoorGlow} latches both.
 *
 * <p>Server-side only by nature ({@code PlayerLoggedInEvent} never fires on the client
 * game bus for remote players); no client classes are referenced.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DoorLoginResync {
    private DoorLoginResync() {}

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            RespawnDoorApi.resyncGlowFor(player);
        }
    }
}
