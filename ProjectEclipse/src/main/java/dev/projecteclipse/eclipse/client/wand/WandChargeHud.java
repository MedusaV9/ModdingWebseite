package dev.projecteclipse.eclipse.client.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandConfig;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import dev.projecteclipse.eclipse.wand.WandSpell;
import dev.projecteclipse.eclipse.wand.WandSpells;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
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
 * <p>F-039 spell readout: with a path locked, a persistent line above the pips names the
 * SELECTED spell plus its Veilladung cost — path-tinted when castable, dim red when the
 * charge can't pay (F-040: no cooldown state exists anymore) — and a cycle indicator
 * shows where in the unlocked list you are (dots up to {@value #MAX_DOTS} spells, a
 * compact "n/m" counter beyond). This is the always-on feedback the sneak-scroll/
 * sneak-click switching writes into.</p>
 *
 * <p>Component reads ({@code wand_charge}/{@code wand_spell}/{@code wand_path} are
 * synced data components) plus the {@code ClientWandProgress} sync cache (effective
 * costs, owned nodes) — zero custom network traffic for this HUD.</p>
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
    private static final int DOT = 3;
    private static final int DOT_GAP = 3;
    /** Above this many unlocked spells the dot row becomes an "n/m" counter. */
    private static final int MAX_DOTS = 12;
    private static final int NO_CHARGE = 0xFFC96A6A;

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
        // WANDFIX-4: prefer the synced per-player max (wand-branch perks folded in, REAL
        // on dedicated servers); the local config value stays the pre-sync fallback.
        int max = Math.max(1, ClientWandProgress.synced
                ? ClientWandProgress.chargeMax : WandConfig.get().charge().max());
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

        renderSelection(guiGraphics, minecraft, stack, charge, tint, dim, y0);
    }

    /**
     * F-039: the persistent selected-SPELL line + a cycle indicator over the unlocked
     * list. Sits directly above the charge pips so the whole wand state reads as one
     * block. F-040: no cooldown display — cost is the only gate left.
     */
    private static void renderSelection(GuiGraphics guiGraphics, Minecraft minecraft,
            ItemStack stack, int charge, int tint, int dim, int pipY) {
        WandPath path = WandSoulbind.pathOf(stack);
        if (path == WandPath.NONE) {
            return;
        }
        WandSpell selected = WandSpells.byKey(stack.get(WandItems.WAND_SPELL.get()));
        if (selected == null) {
            return; // no spell selected/unlocked yet — pips alone tell the story
        }
        java.util.List<WandSpell> unlocked = ClientWandProgress.synced
                ? ClientWandProgress.unlockedSpells() : java.util.List.of(selected);
        int count = Math.max(1, unlocked.size());
        int index = Math.max(0, unlocked.indexOf(selected));

        // Cycle indicator: dots while the list is short, a compact counter beyond.
        int dotsY = pipY - 7;
        if (count <= MAX_DOTS) {
            int dotsWidth = count * DOT + (count - 1) * DOT_GAP;
            int dotsX = (guiGraphics.guiWidth() - dotsWidth) / 2;
            for (int i = 0; i < count; i++) {
                int x = dotsX + i * (DOT + DOT_GAP);
                guiGraphics.fill(x - 1, dotsY - 1, x + DOT + 1, dotsY + DOT + 1, RIM);
                guiGraphics.fill(x, dotsY, x + DOT, dotsY + DOT, i == index ? tint : dim);
            }
        } else {
            guiGraphics.drawCenteredString(minecraft.font, (index + 1) + "/" + count,
                    guiGraphics.guiWidth() / 2, dotsY - 2, dim);
        }

        // Name line: "<spell> · <cost>" — tinted when castable, red when the charge
        // can't pay. Effective costs come from the ClientWandProgress sync cache.
        int cost = ClientWandProgress.spellCost(selected.key());
        MutableComponent line = Component.translatable(selected.langKey())
                .append(Component.literal(" · " + cost));
        int color = ClientWandProgress.synced && charge < cost ? NO_CHARGE : tint;
        guiGraphics.drawCenteredString(minecraft.font, line,
                guiGraphics.guiWidth() / 2, dotsY - 11, color);
    }
}
