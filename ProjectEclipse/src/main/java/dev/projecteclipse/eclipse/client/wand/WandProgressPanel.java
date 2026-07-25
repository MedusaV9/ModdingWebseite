package dev.projecteclipse.eclipse.client.wand;

import java.util.UUID;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.wand.C2SWandChoosePathPayload;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.narration.NarratedElementType;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;

import javax.annotation.Nullable;

/**
 * Embedded wand progression panel — the "Zauberstab" tab of {@code SkillTreeScreen}
 * (wave-5 A14 §4 / D10 item 10: wand progression was unfindable after the one-shot
 * {@link WandPathScreen}). Renders live from the player's own wand stack: the wand data
 * components ({@code wand_path}/{@code wand_level}/{@code wand_xp}/{@code wand_charge}/
 * {@code wand_selected}) are network-synchronized, so the panel needs no extra payload
 * for state.
 *
 * <p>Three states: no wand in the inventory (hint), pathless wand (compact three-card
 * chooser — same {@code C2SWandChoosePathPayload} contract as {@link WandPathScreen};
 * the server re-validates ownership + NONE state in {@code WandPowers.handleChoosePath},
 * so this surface cannot double-lock), and a chosen path (level ladder: XP bar toward the
 * next level plus the five power rows with cost/cooldown, the selected power and the next
 * unlock highlighted).</p>
 *
 * <p>Server tuning (power cost/cooldown, level-cost curve, charge max, earn-hint numbers)
 * and live per-power cooldowns come from {@link ClientWandProgress}, the cache of the
 * {@code S2CWandProgressPayload} sync (V6-FIXWIRE #5) — REAL server values on dedicated
 * servers too, replacing the old local-{@code WandConfig} estimation. Until the first
 * payload lands (login sends one, so at most a few frames) the ladder shows a syncing
 * hint instead of guessed numbers.</p>
 *
 * <p>UIPOLISH: hovering an unlocked (or next-unlock) power row swaps the footer hints for
 * that power's effect explanation ({@code wand.eclipse.power.<path>.<n>.desc}), so the
 * ladder finally says what each spell DOES, not just what it costs.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class WandProgressPanel extends AbstractWidget {
    private static final WandPath[] PATHS = {WandPath.RISS, WandPath.GLUT, WandPath.STERN};
    /** Riss / Glut / Stern accents — same trio as {@link WandPathScreen}. */
    private static final int[] ACCENTS = {0xFFB98CFF, 0xFFFF9A4D, 0xFF7FE7FF};

    private static final int CARD_W = 104;
    private static final int CARD_H = 92;
    private static final int CARD_GAP = 12;
    private static final int ROW_H = 17;
    private static final long PULSE_PERIOD_MILLIS = 2000L;
    /** After a path click, ignore further card clicks until the server mirror lands. */
    private static final long CHOOSE_PENDING_MILLIS = 3000L;

    /** Panel alpha, driven by the owning screen's open/close fade. */
    private float alpha = 1.0F;
    private long choseAtMillis;
    private int hoveredCard = -1;
    private int lastHoveredCard = -1;

    public WandProgressPanel(int x, int y, int width, int height) {
        super(x, y, width, height, EclipseLang.tr("gui.eclipse.skills.tab.wand"));
    }

    /** Called by the screen each frame before widgets render (§2.3 open fade). */
    public void setAlpha(float alpha) {
        this.alpha = Math.max(0.08F, alpha);
    }

    // ------------------------------------------------------------------
    // Wand lookup (client inventory scan; own soulbound wand preferred)
    // ------------------------------------------------------------------

    @Nullable
    private static ItemStack findWand() {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null) {
            return null;
        }
        Inventory inventory = player.getInventory();
        ItemStack fallback = null;
        for (int slot = 0; slot < inventory.getContainerSize(); slot++) {
            ItemStack stack = inventory.getItem(slot);
            if (stack.getItem() instanceof EclipseWandItem) {
                UUID owner = stack.get(WandItems.WAND_OWNER.get());
                if (owner != null && owner.equals(player.getUUID())) {
                    return stack;
                }
                if (fallback == null) {
                    fallback = stack;
                }
            }
        }
        return fallback;
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------

    @Override
    protected void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        hoveredCard = -1;
        ItemStack wand = findWand();
        if (wand == null) {
            renderNoWand(guiGraphics);
        } else if (WandSoulbind.pathOf(wand) == WandPath.NONE) {
            renderChooser(guiGraphics, mouseX, mouseY);
        } else {
            renderProgress(guiGraphics, wand, mouseX, mouseY);
        }
        if (hoveredCard != lastHoveredCard && hoveredCard >= 0) {
            UiSounds.hover(); // edge blip, never per-frame
        }
        lastHoveredCard = hoveredCard;
    }

    private void renderNoWand(GuiGraphics guiGraphics) {
        var font = Minecraft.getInstance().font;
        int centerX = getX() + this.width / 2;
        int y = getY() + this.height / 2 - 10;
        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.none"),
                centerX, y, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.none_hint"),
                centerX, y + 12, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
    }

    // --- pathless: compact three-card chooser -------------------------

    private int cardW() {
        return Math.min(CARD_W, (this.width - 2 * CARD_GAP - 16) / 3);
    }

    private int cardX(int index) {
        int w = cardW();
        int total = 3 * w + 2 * CARD_GAP;
        return getX() + (this.width - total) / 2 + index * (w + CARD_GAP);
    }

    private int cardY() {
        return getY() + Math.max(30, (this.height - CARD_H) / 2);
    }

    private int cardAt(double mouseX, double mouseY) {
        int y = cardY();
        if (mouseY < y || mouseY >= y + CARD_H) {
            return -1;
        }
        for (int i = 0; i < PATHS.length; i++) {
            int x = cardX(i);
            if (mouseX >= x && mouseX < x + cardW()) {
                return i;
            }
        }
        return -1;
    }

    private boolean choicePending() {
        return choseAtMillis != 0L && Util.getMillis() - choseAtMillis < CHOOSE_PENDING_MILLIS;
    }

    private void renderChooser(GuiGraphics guiGraphics, int mouseX, int mouseY) {
        var font = Minecraft.getInstance().font;
        int centerX = getX() + this.width / 2;
        int titleY = cardY() - 26;
        boolean pending = choicePending();

        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.choose"),
                centerX, titleY, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        guiGraphics.drawCenteredString(font,
                EclipseLang.tr(pending ? "gui.eclipse.skills.wand.pending" : "gui.eclipse.skills.wand.choose_hint"),
                centerX, titleY + 12, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));

        if (!pending && isHovered()) {
            hoveredCard = cardAt(mouseX, mouseY);
            if (hoveredCard >= 0) {
                CursorManager.requestPointer();
            }
        }

        int w = cardW();
        for (int i = 0; i < PATHS.length; i++) {
            WandPath path = PATHS[i];
            int accent = ACCENTS[i];
            int x = cardX(i);
            int y = cardY();
            boolean highlighted = i == hoveredCard;
            float cardAlpha = (pending ? 0.5F : highlighted ? 1.0F : 0.86F) * alpha;

            EclipseUiTheme.drawPanel(guiGraphics, x, y, w, CARD_H, cardAlpha);
            guiGraphics.fill(x + 1, y + 1, x + w - 1, y + 3,
                    EclipseUiTheme.withAlpha(accent, (highlighted ? 1.0F : 0.7F) * cardAlpha));

            int textX = x + 8;
            int textY = y + 10;
            guiGraphics.drawString(font,
                    EclipseUiTheme.ellipsize(font, EclipseLang.trString(path.langKey()), w - 16),
                    textX, textY, EclipseUiTheme.withAlpha(accent, cardAlpha));
            textY += 13;
            for (int power = 0; power < 3; power++) {
                guiGraphics.drawString(font,
                        EclipseUiTheme.ellipsize(font,
                                "L" + (power + 1) + " " + EclipseLang.trString(path.powerLangKey(power)), w - 16),
                        textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, cardAlpha));
                textY += 10;
            }
            guiGraphics.drawCenteredString(font, EclipseLang.tr("wand.eclipse.screen.choose"),
                    x + w / 2, y + CARD_H - 13,
                    EclipseUiTheme.withAlpha(highlighted ? accent : EclipseUiTheme.DIM, cardAlpha));
        }
    }

    // --- chosen path: level ladder -------------------------------------

    private static int accentOf(WandPath path) {
        for (int i = 0; i < PATHS.length; i++) {
            if (PATHS[i] == path) {
                return ACCENTS[i];
            }
        }
        return EclipseUiTheme.ACCENT;
    }

    private void renderProgress(GuiGraphics guiGraphics, ItemStack wand, int mouseX, int mouseY) {
        var font = Minecraft.getInstance().font;
        if (!ClientWandProgress.synced) {
            // Login sends the first payload before any screen can open; this is a
            // few-frames guard at worst — never render guessed numbers (V6-FIXWIRE #5).
            guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.syncing"),
                    getX() + this.width / 2, getY() + this.height / 2 - 4,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            return;
        }
        WandPath path = WandSoulbind.pathOf(wand);
        int accent = accentOf(path);
        int level = WandSoulbind.levelOf(wand);
        int xp = Math.max(0, wand.getOrDefault(WandItems.WAND_XP.get(), 0));
        int selected = Mth.clamp(wand.getOrDefault(WandItems.WAND_SELECTED.get(), 0), 0, level - 1);

        int left = getX() + EclipseUiTheme.PAD;
        int right = getX() + this.width - EclipseUiTheme.PAD;
        int y = getY() + 7;

        // Banner: path name left, "Stufe L/5" + Veilladung right.
        guiGraphics.drawString(font, EclipseLang.tr(path.langKey()), left, y,
                EclipseUiTheme.withAlpha(accent, alpha));
        String levelLine = EclipseLang.trString("gui.eclipse.skills.wand.level", level, WandPath.MAX_LEVEL);
        guiGraphics.drawString(font, levelLine, right - font.width(levelLine), y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        y += 12;

        // XP bar toward the next wand level (server-synced curve).
        int needed = ClientWandProgress.costForLevel(level);
        boolean maxed = level >= WandPath.MAX_LEVEL;
        float fill = maxed ? 1.0F : Mth.clamp(xp / (float) Math.max(1, needed), 0.0F, 1.0F);
        int barW = right - left;
        guiGraphics.fill(left, y, right, y + 5,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
        guiGraphics.fill(left, y, left + Math.round(barW * fill), y + 5,
                EclipseUiTheme.withAlpha(accent, alpha * 0.9F));
        y += 8;
        String xpLine = maxed
                ? EclipseLang.trString("gui.eclipse.skills.wand.xp_max")
                : EclipseLang.trString("gui.eclipse.skills.wand.xp", xp, needed);
        Integer charge = wand.get(WandItems.WAND_CHARGE.get());
        if (charge != null) {
            String chargeLine = EclipseLang.trString("gui.eclipse.skills.wand.charge",
                    charge, ClientWandProgress.chargeMax);
            guiGraphics.drawString(font, chargeLine, right - font.width(chargeLine), y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
        }
        guiGraphics.drawString(font, xpLine, left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
        y += 11;
        EclipseUiTheme.drawHairline(guiGraphics, left, right, y, alpha);
        y += 5;

        // The five power rows: unlocked / next unlock / locked.
        long now = Util.getMillis();
        boolean reduced = EclipseClientConfig.reducedFx();
        // UIPOLISH: hovering a known (unlocked or next-unlock) row swaps the footer hints
        // for that power's effect explanation (wand.eclipse.power.<path>.<n>.desc).
        int hoveredPower = -1;
        for (int i = 0; i < path.powerCount() && i < WandPath.MAX_LEVEL; i++) {
            boolean unlocked = level >= i + 1;
            boolean next = !unlocked && level == i;
            boolean isSelected = unlocked && i == selected;
            int rowY = y + i * ROW_H;
            if ((unlocked || next) && isHovered()
                    && mouseX >= left - 4 && mouseX < right + 4
                    && mouseY >= rowY - 2 && mouseY < rowY + ROW_H - 4) {
                hoveredPower = i;
            }

            if (isSelected) {
                guiGraphics.fill(left - 4, rowY - 2, right + 4, rowY + ROW_H - 4,
                        EclipseUiTheme.withAlpha(accent, 0.12F * alpha));
            }
            if (next && !reduced) {
                float pulse = pulse(now);
                guiGraphics.fill(left - 4, rowY - 2, left - 2, rowY + ROW_H - 4,
                        EclipseUiTheme.withAlpha(accent, (0.35F + 0.5F * pulse) * alpha));
            }

            String name = "L" + (i + 1) + " " + EclipseLang.trString(path.powerLangKey(i));
            if (isSelected) {
                name = "▶ " + name;
            }
            int nameColor = unlocked ? (isSelected ? accent : EclipseUiTheme.TEXT) : EclipseUiTheme.DIM;
            guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, name, this.width / 2),
                    left, rowY, EclipseUiTheme.withAlpha(nameColor, alpha * (unlocked ? 1.0F : 0.8F)));

            String meta;
            boolean cooling = false;
            if (unlocked || next) {
                String powerKey = path.powerKey(i);
                ClientWandProgress.Power power = ClientWandProgress.power(powerKey);
                meta = EclipseLang.trString("gui.eclipse.skills.wand.power_meta",
                        power.cost(), power.cooldownTicks() / 20);
                int coolingSeconds = unlocked ? ClientWandProgress.cooldownRemainingSeconds(powerKey) : 0;
                if (coolingSeconds > 0) {
                    // Live countdown from the sync — the power is actively cooling down.
                    cooling = true;
                    meta = EclipseLang.trString("gui.eclipse.skills.wand.cooling", coolingSeconds)
                            + " · " + meta;
                }
                if (next) {
                    meta = EclipseLang.trString("gui.eclipse.skills.wand.next_unlock") + " · " + meta;
                }
            } else {
                meta = EclipseLang.trString("gui.eclipse.skills.wand.unlock_at", i + 1);
            }
            int metaColor = next ? accent : cooling ? EclipseUiTheme.TEXT : EclipseUiTheme.DIM;
            guiGraphics.drawString(font, meta, right - font.width(meta), rowY,
                    EclipseUiTheme.withAlpha(metaColor, alpha * 0.95F));
        }
        y += WandPath.MAX_LEVEL * ROW_H + 2;

        // "How to earn wand XP" + cycle hint (D10 §2 footer) — or, while a power row is
        // hovered, that power's effect explanation (UIPOLISH: wand effects were opaque).
        if (y + 20 <= getY() + this.height) {
            EclipseUiTheme.drawHairline(guiGraphics, left, right, y, alpha);
            y += 5;
            String descKey = hoveredPower >= 0 ? path.powerLangKey(hoveredPower) + ".desc" : null;
            if (descKey != null && EclipseLang.hasKey(descKey)) {
                for (FormattedCharSequence line : font.split(EclipseLang.tr(descKey), right - left)) {
                    if (y + 9 > getY() + this.height) {
                        break;
                    }
                    guiGraphics.drawString(font, line, left, y,
                            EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha * 0.95F));
                    y += 10;
                }
            } else {
                guiGraphics.drawString(font,
                        EclipseUiTheme.ellipsize(font, EclipseLang.trString("gui.eclipse.skills.wand.earn_hint",
                                ClientWandProgress.xpPerCostPoint, (int) ClientWandProgress.xpKillBonus),
                                right - left),
                        left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
                y += 10;
                if (y + 9 <= getY() + this.height) {
                    guiGraphics.drawString(font,
                            EclipseUiTheme.ellipsize(font,
                                    EclipseLang.trString("gui.eclipse.skills.wand.cycle_hint"), right - left),
                            left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
                }
            }
        }
    }

    private static float pulse(long now) {
        double phase = (now % PULSE_PERIOD_MILLIS) / (double) PULSE_PERIOD_MILLIS;
        return (float) (0.5D + 0.5D * Math.sin(phase * Math.PI * 2.0D));
    }

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------

    @Override
    public void onClick(double mouseX, double mouseY) {
        ItemStack wand = findWand();
        if (wand == null || WandSoulbind.pathOf(wand) != WandPath.NONE || choicePending()) {
            return;
        }
        int card = cardAt(mouseX, mouseY);
        if (card >= 0) {
            // Same contract as WandPathScreen.choose — the server locks + re-validates.
            UiSounds.click();
            PacketDistributor.sendToServer(new C2SWandChoosePathPayload(PATHS[card].id()));
            choseAtMillis = Util.getMillis();
        }
    }

    /** The panel is silent — card clicks play their own {@code ui.click}. */
    @Override
    public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
    }

    @Override
    protected void updateWidgetNarration(NarrationElementOutput narrationElementOutput) {
        narrationElementOutput.add(NarratedElementType.TITLE,
                EclipseLang.tr("gui.eclipse.skills.tab.wand"));
    }
}
