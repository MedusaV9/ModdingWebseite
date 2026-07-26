package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsRestrictions;
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
 * <p>C2S handlers run on the server main thread (NeoForge default) and dispatch into
 * {@link WandPowers}, where ALL validation lives. Item state syncs through data
 * components, animations through GeckoLib's own singleton-animatable channel, world FX
 * through the frozen {@code FxPayloads}/{@code S2CQuasarPayload} channels. The ONE S2C
 * payload, {@link S2CWandProgressPayload} (V6-FIXWIRE #5), carries what the components
 * cannot: the server's wand tuning + live cooldowns for the skill-tree wand tab; its
 * handler feeds the client-only {@code ClientWandProgress} cache (lazy classloading —
 * the {@code EclipsePayloads.handleRebirthState} pattern, safe on a dedicated server).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WandPayloads {
    private static final String VERSION = "w4wand3"; // WANDFIX-3 added wand/cycle

    private WandPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToServer(C2SWandCastPayload.TYPE, C2SWandCastPayload.STREAM_CODEC,
                WandPayloads::handleCast);
        registrar.playToServer(C2SWandChoosePathPayload.TYPE, C2SWandChoosePathPayload.STREAM_CODEC,
                WandPayloads::handleChoosePath);
        registrar.playToServer(C2SWandCyclePayload.TYPE, C2SWandCyclePayload.STREAM_CODEC,
                WandPayloads::handleCycle);
        registrar.playToClient(S2CWandProgressPayload.TYPE, S2CWandProgressPayload.STREAM_CODEC,
                WandPayloads::handleProgress);
    }

    private static void handleProgress(S2CWandProgressPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.wand.ClientWandProgress.update(payload);
    }

    private static void handleCast(C2SWandCastPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            if (BackroomsRestrictions.blocksCast(player)) {
                return; // backrooms lockdown (user decree) — refusal chime fires inside
            }
            WandPowers.handleCast(player, payload.mainHand());
        }
    }

    private static void handleChoosePath(C2SWandChoosePathPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            WandPowers.handleChoosePath(player, payload.pathId());
        }
    }

    private static void handleCycle(C2SWandCyclePayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            WandPowers.handleCycle(player, payload.forward());
        }
    }
}
