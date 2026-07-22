package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Opens the handbook ({@link HandbookScreen} — since W9 the artifact menu IS the Ledger of
 * the Drowned) in response to {@code S2COpenArtifactPayload}. Referenced from
 * {@code network.EclipsePayloads} only inside a play-to-client handler body, so this
 * class is never resolved (classloaded) on the dedicated server.
 */
@OnlyIn(Dist.CLIENT)
public final class ArtifactScreenOpener {
    private ArtifactScreenOpener() {}

    /**
     * Opens the screen only when no other screen is open: a duplicate open request while the
     * handbook is already showing is a no-op (it renders live from the cache anyway),
     * and other screens (inventory, chat, ...) are never interrupted.
     */
    public static void open() {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player != null && minecraft.screen == null) {
            minecraft.setScreen(new HandbookScreen());
        }
    }
}
