package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.wand.WandPowers;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the W4-WAND payloads (the {@code GatePayloads} /
 * {@code HeartsPayloads} pattern): own MOD-bus {@link RegisterPayloadHandlersEvent}
 * subscriber on its own version — {@code EclipsePayloads} and {@code EclipseMod} stay
 * untouched. Ids are prefixed {@code eclipse:wand/} and registered nowhere else.
 *
 * <p>Both payloads are C2S-only; handlers run on the server main thread (NeoForge
 * default) and dispatch into {@link WandPowers}, where ALL validation lives. There is no
 * custom S2C traffic: item state syncs through data components, animations through
 * GeckoLib's own singleton-animatable channel, world FX through the frozen
 * {@code FxPayloads}/{@code S2CQuasarPayload} channels.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WandPayloads {
    private static final String VERSION = "w4wand1";

    private WandPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToServer(C2SWandCastPayload.TYPE, C2SWandCastPayload.STREAM_CODEC,
                WandPayloads::handleCast);
        registrar.playToServer(C2SWandChoosePathPayload.TYPE, C2SWandChoosePathPayload.STREAM_CODEC,
                WandPayloads::handleChoosePath);
    }

    private static void handleCast(C2SWandCastPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            WandPowers.handleCast(player, payload.mainHand());
        }
    }

    private static void handleChoosePath(C2SWandChoosePathPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            WandPowers.handleChoosePath(player, payload.pathId());
        }
    }
}
