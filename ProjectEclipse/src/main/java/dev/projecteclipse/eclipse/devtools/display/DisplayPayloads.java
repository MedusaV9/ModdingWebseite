package dev.projecteclipse.eclipse.devtools.display;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/** Self-registering display-wand payload registrar; never register it in EclipsePayloads. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class DisplayPayloads {
    private static final String VERSION = "display1";

    private DisplayPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToServer(C2SDisplayEditPayload.TYPE, C2SDisplayEditPayload.STREAM_CODEC,
                DisplayPayloads::handleEdit);
    }

    private static void handleEdit(C2SDisplayEditPayload payload, IPayloadContext context) {
        if (!(context.player() instanceof ServerPlayer player) || !player.hasPermissions(2)) {
            return;
        }
        boolean holdingWand = player.getMainHandItem().is(DevToolItems.DISPLAY_WAND.get())
                || player.getOffhandItem().is(DevToolItems.DISPLAY_WAND.get());
        if (!holdingWand) {
            return;
        }
        DisplayPlacerService service = DisplayPlacerService.get(player.server);
        if (payload.action() == C2SDisplayEditPayload.SELECT_OR_PLACE) {
            service.selectOrPlace(player);
        } else if (payload.action() == C2SDisplayEditPayload.DELETE) {
            service.deleteTargetedOrSelected(player);
        }
    }
}
