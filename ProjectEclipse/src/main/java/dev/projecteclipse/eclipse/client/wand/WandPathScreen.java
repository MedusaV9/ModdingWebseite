package dev.projecteclipse.eclipse.client.wand;

import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.wand.C2SWandChoosePathPayload;
import dev.projecteclipse.eclipse.wand.WandPath;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.neoforge.network.PacketDistributor;
import org.lwjgl.glfw.GLFW;

/**
 * The first-right-click path chooser (IDEA-19 §"three paths, one choice"): a quiet
 * three-card Eclipse panel — Phasenriss / Glutherz / Sternenfall — matching the
 * {@link EclipseUiTheme} handbook language (no busy radial, no textures; hairlines,
 * panel fills and one accent per path). Hover eases a card up; click (or ←/→ + Enter)
 * sends the {@code C2SWandChoosePathPayload} and closes — the SERVER locks the path
 * ({@code WandPowers.handleChoosePath} re-validates ownership + NONE state, so mashing
 * two cards or a stale screen cannot double-lock.
 *
 * <p>FFIX-A / POLISH V-3 brought the screen to house standard: §2.3 open motion (5-tick
 * fade + 4px rise, {@code reducedFx} snaps), eased hover lift, {@link UiSounds}
 * hover/click, {@link CursorManager} request/endFrame/reset lifecycle, keyboard
 * navigation (←/→ move the focus, Enter/Space chooses) and {@link EclipseLang} routing
 * so the {@code /lang} override covers the ceremony (L-1 pairs this with the
 * {@code wand.eclipse.} prefix registration).</p>
 *
 * <p>ESC = decide later (the wand stays pathless and simply reopens the chooser on the
 * next right-click). Pausing is disabled so the world keeps breathing behind the veil.</p>
 */
public final class WandPathScreen extends Screen {
    private static final WandPath[] PATHS = {WandPath.RISS, WandPath.GLUT, WandPath.STERN};
    private static final int[] ACCENTS = {0xFFB98CFF, 0xFFFF9A4D, 0xFF7FE7FF};

    private static final int CARD_W = 108;
    private static final int CARD_H = 138;
    private static final int CARD_GAP = 14;
    /** §2.3 open motion: 5-tick fade + 4px rise ({@code reducedFx} snaps). */
    private static final int OPEN_TICKS = 5;
    private static final int OPEN_RISE_PX = 4;
    /** Hover lift height; the lift progress eases over ~4 ticks instead of snapping. */
    private static final int HOVER_LIFT_PX = 3;
    private static final float HOVER_STEP_PER_TICK = 0.25F;

    // Client thread only.
    private int openTicks;
    /** Per-card hover-lift progress 0..1, eased at render time. */
    private final float[] hoverLift = new float[PATHS.length];
    /** Keyboard focus (←/→ + Enter); {@code -1} until the first arrow press. */
    private int focusedCard = -1;
    /** Last mouse-hovered card, for the {@link UiSounds#hover()} edge blip. */
    private int lastHovered = -1;

    private WandPathScreen() {
        super(EclipseLang.tr("wand.eclipse.screen.title"));
    }

    /** Client-side opener (called from {@code EclipseWandItem#use} on a pathless wand). */
    public static void open() {
        Minecraft.getInstance().setScreen(new WandPathScreen());
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void removed() {
        CursorManager.reset(); // P3 hard rule 5: the system cursor always returns
        super.removed();
    }

    @Override
    public void tick() {
        super.tick();
        openTicks++;
        int highlighted = highlightedCard();
        for (int i = 0; i < hoverLift.length; i++) {
            float target = i == highlighted ? 1.0F : 0.0F;
            if (EclipseClientConfig.reducedFx()) {
                hoverLift[i] = target; // calm variant: no motion, instant state
            } else {
                hoverLift[i] = Mth.clamp(hoverLift[i]
                        + (target > hoverLift[i] ? HOVER_STEP_PER_TICK : -HOVER_STEP_PER_TICK),
                        0.0F, 1.0F);
            }
        }
    }

    private int cardX(int index) {
        int total = PATHS.length * CARD_W + (PATHS.length - 1) * CARD_GAP;
        return (this.width - total) / 2 + index * (CARD_W + CARD_GAP);
    }

    private int cardY() {
        return (this.height - CARD_H) / 2;
    }

    private int hoveredCard(double mouseX, double mouseY) {
        int y = cardY();
        if (mouseY < y || mouseY >= y + CARD_H) {
            return -1;
        }
        for (int i = 0; i < PATHS.length; i++) {
            int x = cardX(i);
            if (mouseX >= x && mouseX < x + CARD_W) {
                return i;
            }
        }
        return -1;
    }

    /** The card highlighted this frame: mouse hover wins, else the keyboard focus. */
    private int highlightedCard() {
        Minecraft minecraft = Minecraft.getInstance();
        double scale = minecraft.getWindow().getGuiScale();
        int mouseHover = hoveredCard(
                minecraft.mouseHandler.xpos() / scale, minecraft.mouseHandler.ypos() / scale);
        return mouseHover >= 0 ? mouseHover : focusedCard;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // §2.3 open motion: the whole panel fades in over OPEN_TICKS with a small rise.
        float openT = EclipseClientConfig.reducedFx() ? 1.0F
                : Mth.clamp((openTicks + partialTick) / OPEN_TICKS, 0.0F, 1.0F);
        float openEase = easeOutCubic(openT);
        // Font rendering treats near-zero alpha as opaque — keep a readable floor.
        float alpha = Math.max(0.08F, openEase);

        guiGraphics.fill(0, 0, this.width, this.height,
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        super.render(guiGraphics, mouseX, mouseY, partialTick);

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F, (1.0F - openEase) * OPEN_RISE_PX, 0.0F);

        int titleY = cardY() - 28;
        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, titleY,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        guiGraphics.drawCenteredString(this.font,
                EclipseLang.tr("wand.eclipse.screen.final"), this.width / 2, titleY + 12,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));

        int hovered = hoveredCard(mouseX, mouseY);
        if (hovered >= 0) {
            CursorManager.requestPointer();
            if (hovered != lastHovered) {
                UiSounds.hover(); // edge blip, never per-frame
            }
        }
        lastHovered = hovered;

        int highlighted = hovered >= 0 ? hovered : focusedCard;
        for (int i = 0; i < PATHS.length; i++) {
            renderCard(guiGraphics, i, i == highlighted, alpha);
        }

        guiGraphics.drawCenteredString(this.font,
                EclipseLang.tr("wand.eclipse.screen.later"), this.width / 2,
                cardY() + CARD_H + 14, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
        guiGraphics.pose().popPose();

        CursorManager.endFrame();
    }

    private void renderCard(GuiGraphics guiGraphics, int index, boolean highlighted, float alpha) {
        WandPath path = PATHS[index];
        int accent = ACCENTS[index];
        int x = cardX(index);
        int y = cardY() - Math.round(easeOutCubic(hoverLift[index]) * HOVER_LIFT_PX);

        EclipseUiTheme.drawPanel(guiGraphics, x, y, CARD_W, CARD_H,
                (highlighted ? 1.0F : 0.86F) * alpha);
        // Accent top bar — each path announces its color before its words.
        guiGraphics.fill(x + 1, y + 1, x + CARD_W - 1, y + 3,
                EclipseUiTheme.withAlpha(accent, (highlighted ? 1.0F : 0.7F) * alpha));

        int textX = x + 9;
        int textY = y + 12;
        guiGraphics.drawString(this.font, EclipseLang.tr(path.langKey()), textX, textY,
                EclipseUiTheme.withAlpha(accent, alpha));
        textY += 12;
        String key = path.name().toLowerCase(Locale.ROOT);
        List<FormattedCharSequence> tag = this.font.split(
                EclipseLang.tr("wand.eclipse.screen." + key + ".tag"), CARD_W - 18);
        for (FormattedCharSequence line : tag) {
            guiGraphics.drawString(this.font, line, textX, textY,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
            textY += 10;
        }
        textY += 4;
        EclipseUiTheme.drawHairline(guiGraphics, textX, x + CARD_W - 9, textY);
        textY += 6;
        for (int power = 0; power < 3; power++) {
            guiGraphics.drawString(this.font, Component.literal("L" + (power + 1) + " ")
                            .append(EclipseLang.tr(path.powerLangKey(power))),
                    textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            textY += 10;
        }

        Component choose = EclipseLang.tr("wand.eclipse.screen.choose");
        guiGraphics.drawCenteredString(this.font, choose, x + CARD_W / 2, y + CARD_H - 14,
                EclipseUiTheme.withAlpha(highlighted ? accent : EclipseUiTheme.DIM, alpha));
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0) {
            int card = hoveredCard(mouseX, mouseY);
            if (card >= 0) {
                choose(card);
                return true;
            }
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }

    /** ←/→ move the card focus (wrapping), Enter/Space chooses the focused card. */
    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (keyCode == GLFW.GLFW_KEY_LEFT || keyCode == GLFW.GLFW_KEY_RIGHT) {
            int step = keyCode == GLFW.GLFW_KEY_LEFT ? -1 : 1;
            focusedCard = focusedCard < 0
                    ? (step > 0 ? 0 : PATHS.length - 1)
                    : Math.floorMod(focusedCard + step, PATHS.length);
            UiSounds.hover();
            return true;
        }
        if ((keyCode == GLFW.GLFW_KEY_ENTER || keyCode == GLFW.GLFW_KEY_KP_ENTER
                || keyCode == GLFW.GLFW_KEY_SPACE) && focusedCard >= 0) {
            choose(focusedCard);
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    /** The one deliberate action: lock the path server-side and close. */
    private void choose(int index) {
        UiSounds.click();
        PacketDistributor.sendToServer(new C2SWandChoosePathPayload(PATHS[index].id()));
        onClose();
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
