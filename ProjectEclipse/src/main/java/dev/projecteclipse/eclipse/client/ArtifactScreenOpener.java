package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import dev.projecteclipse.eclipse.network.C2SOpenArtifactPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Opens the handbook ({@link HandbookScreen} — since W9 the artifact menu IS the Ledger of
 * the Drowned). Two entry points:
 *
 * <ul>
 *   <li>{@link #open()} — in response to {@code S2COpenArtifactPayload}. Referenced from
 *       {@code network.EclipsePayloads} only inside a play-to-client handler body, so this
 *       class is never resolved (classloaded) on the dedicated server.</li>
 *   <li>{@link #openFromInventory()} — from a right-click on the pinned slot-17 artifact
 *       ({@code ArmArtifactItem#overrideOtherStackedOnMe}, same lazy-classload rule).</li>
 * </ul>
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

    /**
     * Right-click-on-the-artifact path (plans_v3 P3 §3.1). Called mid-{@code doClick} from
     * inside the open container screen, so everything is DEFERRED one frame via
     * {@link Minecraft#tell}: the click finishes processing and its packet goes out first,
     * then the runnable closes the container the vanilla way ({@code closeContainer} sends
     * the container-close packet and resets {@code containerMenu}) and only then swaps in
     * the handbook. A {@link C2SOpenArtifactPayload} rides along for the state refresh —
     * the server answers with fresh lives/day payloads (the screen renders live from
     * {@code ClientStateCache}) plus an open payload that {@link #open()} no-ops.
     *
     * <p>{@code tell} (not {@code execute}) is deliberate: {@code execute} runs immediately
     * when already on the render thread, which would tear the menu down while
     * {@code doClick} is still walking it.</p>
     */
    public static void openFromInventory() {
        Minecraft minecraft = Minecraft.getInstance();
        minecraft.tell(() -> {
            if (minecraft.player == null) {
                return;
            }
            if (minecraft.screen instanceof AbstractContainerScreen<?>) {
                minecraft.player.closeContainer(); // close packet + setScreen(null)
            }
            if (minecraft.screen == null) {
                PacketDistributor.sendToServer(new C2SOpenArtifactPayload());
                minecraft.setScreen(new HandbookScreen());
            }
        });
    }
}
