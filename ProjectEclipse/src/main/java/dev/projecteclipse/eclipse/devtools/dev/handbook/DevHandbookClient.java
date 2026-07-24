package dev.projecteclipse.eclipse.devtools.dev.handbook;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ConfigRefEntry;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Client-side cache + dispatcher for the Dev Handbook (P5-W2). Written exclusively by
 * {@link DevHandbookPayloads.S2CDevHandbookPayload} receipt, read by {@link DevHandbookScreen}.
 * There is NO client-side opening path (no keybind, no menu entry): the screen only ever
 * appears after the server decided to send data, so a non-op client never holds — and can
 * never display — any registry information. The cache is wiped on logout for the same reason
 * (op on server A, pleb on server B must not leak A's command list).
 */
@OnlyIn(Dist.CLIENT)
public final class DevHandbookClient {
    private static volatile List<DevCommandDoc> entries = List.of();
    private static volatile List<ConfigRefEntry> configRefs = List.of();

    private DevHandbookClient() {}

    /**
     * Payload receipt (client main thread): cache the snapshot, then open the screen — or,
     * when the handbook is already open (refresh round-trip), update it in place. Mirrors
     * {@code GoalEditorScreen.open}: never interrupts an unrelated open screen (running
     * {@code /dev} from chat closes the chat screen before the payload arrives).
     */
    static void handleSync(DevHandbookPayloads.S2CDevHandbookPayload payload) {
        entries = List.copyOf(payload.entries());
        configRefs = List.copyOf(payload.configRefs());
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.screen instanceof DevHandbookScreen screen) {
            screen.onDataUpdated();
        } else if (minecraft.player != null && minecraft.screen == null) {
            minecraft.setScreen(new DevHandbookScreen());
        }
    }

    /** Screen refresh hook (open / F5 / after a reload click). Server re-validates permission. */
    static void requestRefresh() {
        if (Minecraft.getInstance().getConnection() != null) {
            PacketDistributor.sendToServer(new DevHandbookPayloads.C2SDevHandbookRequestPayload());
        }
    }

    /** Synced registry snapshot (already permission-filtered server-side); empty until first sync. */
    static List<DevCommandDoc> entries() {
        return entries;
    }

    /** Synced config reference table for the Configs tab; empty until first sync. */
    static List<ConfigRefEntry> configRefs() {
        return configRefs;
    }

    /** Logout wipe ({@code ClientStateCache.DisconnectReset} pattern): no cross-server leaks. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class DisconnectReset {
        private DisconnectReset() {}

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            entries = List.of();
            configRefs = List.of();
        }
    }
}
