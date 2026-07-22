package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import dev.projecteclipse.eclipse.network.C2SOpenArtifactPayload;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Polls the menu keybind (game bus, client only). The handbook opens immediately from
 * {@link ClientStateCache} and a {@link C2SOpenArtifactPayload} is sent to refresh: the
 * server replies with fresh lives/day-state (the screen renders live from the cache) plus
 * an open payload that no-ops because the screen is already showing. Closing with the same
 * key is handled by {@code HandbookScreen#keyPressed} (this IN_GAME mapping never fires
 * while a screen is open).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ArtifactKeyHandler {
    private ArtifactKeyHandler() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        while (EclipseKeyMappings.OPEN_MENU.consumeClick()) {
            if (minecraft.player != null && minecraft.screen == null) {
                PacketDistributor.sendToServer(new C2SOpenArtifactPayload());
                minecraft.setScreen(new HandbookScreen());
            }
        }
    }
}
