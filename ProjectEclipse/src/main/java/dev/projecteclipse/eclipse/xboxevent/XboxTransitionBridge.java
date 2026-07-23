package dev.projecteclipse.eclipse.xboxevent;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;

/**
 * P3-W11's half of the P5-W9 portal-transition seam: installs the payload sender that
 * {@link XboxPayloads#sendPortalTransition} no-ops without (see the P5-W9 wiring notes —
 * {@code XboxPayloads} itself stays untouched by design). {@code XboxEventService} invokes
 * the sender right BEFORE every cross-dimension teleport (entry, death return, leave,
 * timeout, stop), so each hop is one {@code ENTER} choreography on the client:
 * glitch → black (covering the teleport) → self-releasing fade-in at the destination
 * ({@code client.loading.PortalTransitionController}). The frozen style/hold constants are
 * transmitted verbatim per the {@link XboxPayloads#setPortalTransitionSender} contract.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class XboxTransitionBridge {
    private XboxTransitionBridge() {}

    @SubscribeEvent
    static void onCommonSetup(FMLCommonSetupEvent event) {
        XboxPayloads.setPortalTransitionSender(player -> GatePayloads.sendPortalFx(player,
                new S2CPortalFxPayload(S2CPortalFxPayload.Phase.ENTER,
                        XboxPayloads.TRANSITION_STYLE, XboxPayloads.TRANSITION_HOLD_TICKS)));
    }
}
