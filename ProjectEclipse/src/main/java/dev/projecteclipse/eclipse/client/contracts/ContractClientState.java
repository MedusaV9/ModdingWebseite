package dev.projecteclipse.eclipse.client.contracts;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.contracts.ContractPayloads;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client cache of the contract window flag (fed by
 * {@link ContractPayloads.S2CContractStatePayload}). {@link #windowActive()} is the single
 * gate read by the armor-blackout mixin ({@code client/mixin/HumanoidArmorLayerMixin}) and
 * the overlay chrome. The deadline is re-anchored to the LOCAL clock on receipt so client
 * and server wall clocks never need to agree.
 *
 * <p>Cleared on level unload — a stale blackout can never survive into another world
 * (the {@code MarkVignetteOverlay} rule).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ContractClientState {
    private static volatile boolean windowActive;
    /** Window deadline re-anchored to the local {@code System.currentTimeMillis()} axis. */
    private static volatile long endsAtLocalMillis;

    private ContractClientState() {}

    /** Payload entry point (client main thread). */
    public static void handleState(ContractPayloads.S2CContractStatePayload payload) {
        boolean wasActive = windowActive;
        windowActive = payload.windowActive();
        endsAtLocalMillis = System.currentTimeMillis()
                + (payload.endsAtEpochMillis() - payload.serverNowMillis());
        if (wasActive != windowActive) {
            ContractRevealOverlay.onWindowChanged(windowActive);
        }
    }

    /** Whether the contract window (and thus the armor blackout) is live. Render-thread safe. */
    public static boolean windowActive() {
        return windowActive;
    }

    /** Remaining window millis on the local clock axis (0 when idle/overrun). */
    public static long remainingMillis() {
        return windowActive ? Math.max(0L, endsAtLocalMillis - System.currentTimeMillis()) : 0L;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (Minecraft.getInstance().level == null && windowActive) {
            windowActive = false;
            endsAtLocalMillis = 0L;
        }
    }
}
