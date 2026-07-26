package dev.projecteclipse.eclipse.client.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.network.wand.C2SWandCyclePayload;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.InputEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WANDFIX-3 client input hook: <b>sneak + mouse scroll</b> cycles the wand's selected
 * power in both directions while a path-locked wand sits in either hand. This was THE
 * usability hole — the only switch gesture was sneak-right-click (one direction, one
 * step per click, easily eaten by block interactions), and the natural gesture players
 * try (sneak-scroll) switched their hotbar slot instead. The scroll event is cancelled
 * so the hotbar never moves while the gesture means "switch spell".
 *
 * <p>Comfort-only client checks (screen open, cutscene flight active, spectator) mirror
 * the authoritative server gates in {@code WandPowers.handleCycle}; the payload carries
 * nothing but the direction.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WandSelectInput {
    private WandSelectInput() {}

    @SubscribeEvent
    static void onMouseScrolling(InputEvent.MouseScrollingEvent event) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null || minecraft.screen != null || player.isSpectator()
                || !player.isShiftKeyDown() || CameraDirector.isActive()) {
            return;
        }
        ItemStack stack = player.getMainHandItem();
        if (!(stack.getItem() instanceof EclipseWandItem)) {
            stack = player.getOffhandItem();
            if (!(stack.getItem() instanceof EclipseWandItem)) {
                return;
            }
        }
        if (WandSoulbind.pathOf(stack) == WandPath.NONE) {
            return; // nothing to cycle yet — let the scroll keep its hotbar meaning
        }
        double delta = event.getScrollDeltaY();
        if (delta == 0.0D) {
            return;
        }
        PacketDistributor.sendToServer(new C2SWandCyclePayload(delta > 0.0D));
        event.setCanceled(true);
    }
}
