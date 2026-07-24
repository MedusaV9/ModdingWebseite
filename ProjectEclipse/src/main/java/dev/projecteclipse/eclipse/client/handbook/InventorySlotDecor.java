package dev.projecteclipse.eclipse.client.handbook;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArtifactSlotLock;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.inventory.InventoryScreen;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.Slot;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ContainerScreenEvent;

/**
 * The slot-17 lock affordance (plans_v3 P3 §3.1): a quiet {@link EclipseUiTheme#ACCENT_DEEP}
 * frame around the pinned artifact's inventory slot plus a small corner padlock badge
 * ({@code textures/gui/handbook/slot_lock.png}, authored in final palette colors), drawn
 * via {@link ContainerScreenEvent.Render.Foreground} — no screen mixin. The event fires
 * with the pose already translated to the container's origin, above slot items but below
 * tooltips and the carried stack, exactly where a slot overlay belongs.
 *
 * <p>Deliberately {@link InventoryScreen} only (the survival inventory is where the pin
 * matters; the creative screen has its own scrolled grid) and only while the slot really
 * holds the artifact, so an un-granted or admin-cleared slot is never decorated. The slot
 * is found by container index — never by menu index — so this cannot drift if another mod
 * reorders menu slots. Static accent, nothing animated: nothing to gate on
 * {@code reducedFx}, and screens render under F1 by design (B19 exempts container UIs).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class InventorySlotDecor {
    private static final ResourceLocation LOCK_BADGE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/handbook/slot_lock.png");
    private static final int BADGE_SIZE = 8;

    private InventorySlotDecor() {}

    @SubscribeEvent
    static void onRenderForeground(ContainerScreenEvent.Render.Foreground event) {
        if (!(event.getContainerScreen() instanceof InventoryScreen screen)) {
            return;
        }
        for (Slot slot : screen.getMenu().slots) {
            if (slot.container instanceof Inventory
                    && slot.getContainerSlot() == ArtifactSlotLock.ARTIFACT_SLOT
                    && slot.getItem().is(EclipseItems.ARM_ARTIFACT.get())) {
                draw(event.getGuiGraphics(), slot.x, slot.y);
                return;
            }
        }
    }

    /** 1px deep-accent ring around the 16x16 slot + padlock badge riding the top-right corner. */
    private static void draw(GuiGraphics guiGraphics, int x, int y) {
        int frame = EclipseUiTheme.ACCENT_DEEP;
        guiGraphics.fill(x - 1, y - 1, x + 17, y, frame);
        guiGraphics.fill(x - 1, y + 16, x + 17, y + 17, frame);
        guiGraphics.fill(x - 1, y, x, y + 16, frame);
        guiGraphics.fill(x + 16, y, x + 17, y + 16, frame);
        guiGraphics.blit(LOCK_BADGE, x + 11, y - 3, 0, 0, BADGE_SIZE, BADGE_SIZE, BADGE_SIZE, BADGE_SIZE);
    }
}
