package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.LangService;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering payload registrar for locale sync ({@code docs/plans_v3/P3_ui.md} P3-W4).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class LangPayloads {
    private LangPayloads() {}

    @SubscribeEvent
    public static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar("2");
        registrar.playToServer(C2SLocalePayload.TYPE, C2SLocalePayload.STREAM_CODEC,
                LangPayloads::handleLocale);
    }

    private static void handleLocale(C2SLocalePayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            LangService.applyLocale(player, payload.locale(), payload.explicit());
        }
    }
}
