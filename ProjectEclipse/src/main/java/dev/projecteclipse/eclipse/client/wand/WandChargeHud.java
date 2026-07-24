package dev.projecteclipse.eclipse.client.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandConfig;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.ItemStack;

/**
 * Veilladung pips (IDEA-19 §charge economy): a single row of ten small diamonds floating
 * above the hotbar while a wand is in either hand. Fill = current charge / configured max
 * (partial pip = dimmed), tint follows the wand's path (violet/ember/star-cyan; neutral
 * lilac while pathless). F1-safe: gated on {@code hideGui}, plus spectator/no-wand
 * checks — and the layer simply isn't whitelisted for cutscene HUD suppression, so
 * letterboxed scenes hide it automatically.
 *
 * <p>Pure component reads ({@code wand_charge} is a synced data component) — zero custom
 * network traffic for this HUD.</p>
 */
public final class WandChargeHud {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand_charge");

    private static final int PIPS = 10;
    private static final int PIP_W = 5;
    private static final int PIP_H = 3;
    private static final int PIP_GAP = 2;
    private static final int EMPTY = 0x66150E22;
    private static final int RIM = 0x882E2347;

    private WandChargeHud() {}

    /** Tint per path: NONE lilac, RISS violet, GLUT ember, STERN star-cyan. */
    private static int tint(WandPath path) {
        return switch (path) {
            case RISS -> 0xFFB98CFF;
            case GLUT -> 0xFFFF9A4D;
            case STERN -> 0xFF7FE7FF;
            default -> 0xFF8E7BB8;
        };
    }

    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null || minecraft.options.hideGui || player.isSpectator()) {
            return;
        }
        ItemStack stack = player.getMainHandItem();
        if (!(stack.getItem() instanceof EclipseWandItem)) {
            stack = player.getOffhandItem();
            if (!(stack.getItem() instanceof EclipseWandItem)) {
                return;
            }
        }
        int max = Math.max(1, WandConfig.get().charge().max());
        int charge = Mth.clamp(stack.getOrDefault(WandItems.WAND_CHARGE.get(), 0), 0, max);
        int tint = tint(WandSoulbind.pathOf(stack));
        int dim = (tint & 0x00FFFFFF) | 0x55000000;

        int rowWidth = PIPS * PIP_W + (PIPS - 1) * PIP_GAP;
        int x0 = (guiGraphics.guiWidth() - rowWidth) / 2;
        int y0 = guiGraphics.guiHeight() - 51; // just above the food/armor row

        float perPip = max / (float) PIPS;
        for (int i = 0; i < PIPS; i++) {
            int x = x0 + i * (PIP_W + PIP_GAP);
            float fill = Mth.clamp((charge - i * perPip) / perPip, 0.0F, 1.0F);
            guiGraphics.fill(x - 1, y0 - 1, x + PIP_W + 1, y0 + PIP_H + 1, RIM);
            guiGraphics.fill(x, y0, x + PIP_W, y0 + PIP_H, EMPTY);
            if (fill >= 1.0F) {
                guiGraphics.fill(x, y0, x + PIP_W, y0 + PIP_H, tint);
            } else if (fill > 0.0F) {
                guiGraphics.fill(x, y0, x + Math.max(1, Math.round(PIP_W * fill)), y0 + PIP_H, dim);
            }
        }
    }
}
