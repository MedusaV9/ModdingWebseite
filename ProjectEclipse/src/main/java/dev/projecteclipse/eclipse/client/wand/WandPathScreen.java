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
 * The first-right-click path chooser (IDEA-19 §"three paths, one choice"): three
 * ceremony cards — Phasenriss / Glutherz / Sternenfall — in the {@link EclipseUiTheme}
 * handbook language (no busy radial, no structural textures; hairlines, panel fills and
 * one accent world per path). Hover eases a card up; click (or ←/→ + Enter) sends the
 * {@code C2SWandChoosePathPayload} — the SERVER locks the path
 * ({@code WandPowers.handleChoosePath} re-validates ownership + NONE state, so mashing
 * two cards or a stale screen cannot double-lock).
 *
 * <p>F-070 ceremony redesign (visuals only — the choose flow is unchanged): each card
 * carries its path's full color identity — a procedural fill-drawn glyph (glitch shard /
 * ember flame / four-point star; §2.2 law: pure fills, nothing stretches), an animated
 * hover GLOW (nested accent outlines breathing at ~1&nbsp;Hz; {@code reducedFx}: one calm
 * static outline), a lore line under the essence tag and the first three ladder spells
 * with accent-tinted tier tags. Choosing plays a CONFIRMATION beat: the payload is sent
 * immediately (server-authoritative, exactly as before), then input locks while the
 * chosen card flares — expanding accent rings, the other two cards folding to dark —
 * and the screen closes after {@value #CONFIRM_TICKS} ticks ({@code reducedFx} closes
 * instantly). New strings ride the {@code wand.eclipse.screen.*} family
 * ({@code docs/plans_v3/langdrop/wandfx2.json}).</p>
 *
 * <p>FFIX-A / POLISH V-3 house standard kept: §2.3 open motion (5-tick fade + 4px rise,
 * {@code reducedFx} snaps), eased hover lift, {@link UiSounds} hover/click,
 * {@link CursorManager} request/endFrame/reset lifecycle, keyboard navigation and
 * {@link EclipseLang} routing. ESC = decide later (the wand stays pathless and reopens
 * the chooser on the next right-click); pausing stays disabled.</p>
 */
public final class WandPathScreen extends Screen {
    private static final WandPath[] PATHS = {WandPath.RISS, WandPath.GLUT, WandPath.STERN};
    /** Primary path accents (the HUD/WandChargeHud tints — violet / ember / star-cyan). */
    private static final int[] ACCENTS = {0xFFB98CFF, 0xFFFF9A4D, 0xFF7FE7FF};
    /** Secondary identity colors (F-070 palette: glitch cyan / white-gold / pale gold). */
    private static final int[] SPARKS = {0xFF4FE8FF, 0xFFFFE9A8, 0xFFF7E3B0};

    private static final int CARD_W = 112;
    private static final int CARD_H = 172;
    private static final int CARD_GAP = 12;
    /** §2.3 open motion: 5-tick fade + 4px rise ({@code reducedFx} snaps). */
    private static final int OPEN_TICKS = 5;
    private static final int OPEN_RISE_PX = 4;
    /** Hover lift height; the lift progress eases over ~4 ticks instead of snapping. */
    private static final int HOVER_LIFT_PX = 3;
    private static final float HOVER_STEP_PER_TICK = 0.25F;
    /** Confirmation beat length before the screen closes ({@code reducedFx}: instant). */
    private static final int CONFIRM_TICKS = 18;
    /** How far the confirmation rings expand past the card edge. */
    private static final int CONFIRM_RING_PX = 14;

    // Client thread only.
    private int openTicks;
    /** Per-card hover-lift progress 0..1, eased at render time. */
    private final float[] hoverLift = new float[PATHS.length];
    /** Keyboard focus (←/→ + Enter); {@code -1} until the first arrow press. */
    private int focusedCard = -1;
    /** Last mouse-hovered card, for the {@link UiSounds#hover()} edge blip. */
    private int lastHovered = -1;
    /** Confirmation state: chosen card index, {@code -1} while still choosing. */
    private int chosenCard = -1;
    private int confirmTicks;

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
        if (chosenCard >= 0) {
            // Confirmation beat: hold the chosen card lifted, fold the others, close.
            confirmTicks++;
            if (confirmTicks > CONFIRM_TICKS) {
                onClose();
                return;
            }
        }
        int highlighted = chosenCard >= 0 ? chosenCard : highlightedCard();
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
        // Confirmation fold: everything except the chosen card eases toward dark.
        float confirmEase = chosenCard < 0 ? 0.0F
                : easeOutCubic(Mth.clamp((confirmTicks + partialTick) / CONFIRM_TICKS, 0.0F, 1.0F));
        float foldAlpha = Math.max(0.08F, alpha * (1.0F - confirmEase));

        guiGraphics.fill(0, 0, this.width, this.height,
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        super.render(guiGraphics, mouseX, mouseY, partialTick);

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F, (1.0F - openEase) * OPEN_RISE_PX, 0.0F);

        int titleY = cardY() - 28;
        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, titleY,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, foldAlpha));
        guiGraphics.drawCenteredString(this.font,
                EclipseLang.tr("wand.eclipse.screen.final"), this.width / 2, titleY + 12,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, foldAlpha));

        int hovered = chosenCard >= 0 ? -1 : hoveredCard(mouseX, mouseY);
        if (hovered >= 0) {
            CursorManager.requestPointer();
            if (hovered != lastHovered) {
                UiSounds.hover(); // edge blip, never per-frame
            }
        }
        lastHovered = hovered;

        int highlighted = chosenCard >= 0 ? chosenCard : (hovered >= 0 ? hovered : focusedCard);
        for (int i = 0; i < PATHS.length; i++) {
            boolean isChosen = i == chosenCard;
            float cardAlpha = chosenCard >= 0 && !isChosen ? foldAlpha : alpha;
            renderCard(guiGraphics, i, i == highlighted, isChosen, cardAlpha, confirmEase,
                    partialTick);
        }

        guiGraphics.drawCenteredString(this.font,
                EclipseLang.tr("wand.eclipse.screen.later"), this.width / 2,
                cardY() + CARD_H + 14, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, foldAlpha));
        guiGraphics.pose().popPose();

        CursorManager.endFrame();
    }

    private void renderCard(GuiGraphics guiGraphics, int index, boolean highlighted,
            boolean chosen, float alpha, float confirmEase, float partialTick) {
        WandPath path = PATHS[index];
        int accent = ACCENTS[index];
        int spark = SPARKS[index];
        int x = cardX(index);
        int y = cardY() - Math.round(easeOutCubic(hoverLift[index]) * HOVER_LIFT_PX);

        // F-070 animated hover glow: nested accent outlines breathing around the card.
        // reducedFx keeps a single calm outline; the confirmation beat pins full glow.
        float glow = chosen ? 1.0F : easeOutCubic(hoverLift[index]);
        if (glow > 0.02F) {
            if (EclipseClientConfig.reducedFx()) {
                drawOutline(guiGraphics, x - 1, y - 1, CARD_W + 2, CARD_H + 2,
                        EclipseUiTheme.withAlpha(accent, 0.5F * glow * alpha));
            } else {
                float pulse = 0.7F + 0.3F * Mth.sin((openTicks + partialTick) * (Mth.PI / 10.0F));
                float[] rings = {0.4F, 0.22F, 0.1F};
                for (int r = 0; r < rings.length; r++) {
                    drawOutline(guiGraphics, x - 1 - r, y - 1 - r,
                            CARD_W + 2 + 2 * r, CARD_H + 2 + 2 * r,
                            EclipseUiTheme.withAlpha(accent, rings[r] * glow * pulse * alpha));
                }
            }
        }
        // Confirmation rings: two accent squares expanding off the chosen card and
        // fading as the rest of the screen folds to dark.
        if (chosen && !EclipseClientConfig.reducedFx() && confirmEase > 0.0F) {
            for (int ring = 0; ring < 2; ring++) {
                float ringT = Mth.clamp(confirmEase * 1.4F - ring * 0.35F, 0.0F, 1.0F);
                if (ringT <= 0.0F) {
                    continue;
                }
                int spread = 2 + Math.round(ringT * CONFIRM_RING_PX);
                drawOutline(guiGraphics, x - spread, y - spread,
                        CARD_W + 2 * spread, CARD_H + 2 * spread,
                        EclipseUiTheme.withAlpha(accent, 0.55F * (1.0F - ringT)));
            }
        }

        EclipseUiTheme.drawPanel(guiGraphics, x, y, CARD_W, CARD_H,
                (highlighted ? 1.0F : 0.86F) * alpha);
        // Accent top bar — each path announces its color before its words.
        guiGraphics.fill(x + 1, y + 1, x + CARD_W - 1, y + 3,
                EclipseUiTheme.withAlpha(accent, (highlighted ? 1.0F : 0.7F) * alpha));

        // Path glyph: procedural fill-drawn identity mark (never a stretched texture).
        drawGlyph(guiGraphics, index, x + CARD_W / 2, y + 19,
                EclipseUiTheme.withAlpha(accent, alpha),
                EclipseUiTheme.withAlpha(spark, alpha));

        int textX = x + 9;
        int textY = y + 33;
        guiGraphics.drawCenteredString(this.font, EclipseLang.tr(path.langKey()),
                x + CARD_W / 2, textY, EclipseUiTheme.withAlpha(accent, alpha));
        textY += 13;
        String key = path.name().toLowerCase(Locale.ROOT);
        List<FormattedCharSequence> tag = this.font.split(
                EclipseLang.tr("wand.eclipse.screen." + key + ".tag"), CARD_W - 18);
        for (int line = 0; line < 2 && line < tag.size(); line++) {
            guiGraphics.drawString(this.font, tag.get(line), textX, textY,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
            textY += 10;
        }
        textY += 3;
        EclipseUiTheme.drawHairline(guiGraphics, textX, x + CARD_W - 9, textY, alpha);
        textY += 5;
        // F-070 lore: one whispered line of who this path IS, in the path's own voice.
        List<FormattedCharSequence> lore = this.font.split(
                EclipseLang.tr("wand.eclipse.screen." + key + ".lore"), CARD_W - 18);
        for (int line = 0; line < 4 && line < lore.size(); line++) {
            guiGraphics.drawString(this.font, lore.get(line), textX, textY,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            textY += 10;
        }
        textY += 3;
        EclipseUiTheme.drawHairline(guiGraphics, textX, x + CARD_W - 9, textY, alpha);
        textY += 5;
        // F-039: preview the path's first three ladder spells (of ten — the card teases,
        // the wand tree in the skill screen shows the full ladder). Tier tag in accent.
        List<dev.projecteclipse.eclipse.wand.WandSpell> spells =
                dev.projecteclipse.eclipse.wand.WandSpells.ofPath(path);
        for (int spell = 0; spell < 3 && spell < spells.size(); spell++) {
            guiGraphics.drawString(this.font, Component.literal("T" + spells.get(spell).tier()),
                    textX, textY, EclipseUiTheme.withAlpha(accent, 0.85F * alpha));
            guiGraphics.drawString(this.font,
                    EclipseLang.tr(spells.get(spell).langKey()), textX + 16, textY,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            textY += 10;
        }

        // Footer: the choose prompt — replaced by the confirmation line on the pick.
        Component footer = chosen ? EclipseLang.tr("wand.eclipse.screen.chosen")
                : EclipseLang.tr("wand.eclipse.screen.choose");
        guiGraphics.drawCenteredString(this.font, footer, x + CARD_W / 2, y + CARD_H - 14,
                EclipseUiTheme.withAlpha(chosen || highlighted ? accent : EclipseUiTheme.DIM,
                        alpha));
    }

    // ------------------------------------------------------------------ glyphs
    // Per-row half-widths (index = distance from the glyph's center row). Pure fills,
    // drawn 1px row by 1px row — crisp at every gui scale, nothing ever stretches.

    /** GLUT flame silhouette, top row first (15 rows, half-widths). */
    private static final int[] FLAME_HW =
            {0, 1, 1, 2, 2, 3, 4, 5, 6, 7, 7, 7, 6, 5, 3};

    /** Draws the path identity glyph centered at ({@code cx}, {@code cy}). */
    private static void drawGlyph(GuiGraphics guiGraphics, int index, int cx, int cy,
            int accent, int spark) {
        switch (index) {
            case 0 -> { // RISS: void shard — a razor diamond with glitch displacement.
                for (int dy = -7; dy <= 7; dy++) {
                    int hw = Math.max(0, 7 - Math.abs(dy));
                    if (dy == 2) {
                        // One displaced slice — the glitch identity in a single row.
                        fillRow(guiGraphics, cx - hw + 3, cy + dy, 2 * hw + 1, spark);
                        continue;
                    }
                    fillRow(guiGraphics, cx - hw, cy + dy, 2 * hw + 1, accent);
                }
                // Dark core seam down the middle (the void inside the shard).
                for (int dy = -4; dy <= 4; dy++) {
                    int hw = Math.max(0, 2 - Math.abs(dy) / 2);
                    fillRow(guiGraphics, cx - hw, cy + dy, 2 * hw + 1,
                            EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, 0.85F));
                }
                // Stray glitch squares breaking off the shard.
                guiGraphics.fill(cx + 7, cy - 6, cx + 9, cy - 4, spark);
                guiGraphics.fill(cx - 9, cy + 4, cx - 7, cy + 6, spark);
            }
            case 1 -> { // GLUT: ember flame — flowing silhouette with a white-gold core.
                for (int row = 0; row < FLAME_HW.length; row++) {
                    int hw = FLAME_HW[row];
                    if (hw > 0) {
                        fillRow(guiGraphics, cx - hw, cy - 7 + row, 2 * hw + 1, accent);
                    }
                }
                for (int row = 5; row < FLAME_HW.length - 1; row++) {
                    int hw = Math.max(0, FLAME_HW[row] - 3);
                    if (hw > 0) {
                        fillRow(guiGraphics, cx - hw, cy - 7 + row, 2 * hw + 1, spark);
                    }
                }
                // Two embers rising off the tip.
                guiGraphics.fill(cx + 4, cy - 8, cx + 5, cy - 7, spark);
                guiGraphics.fill(cx - 5, cy - 6, cx - 4, cy - 5, accent);
            }
            default -> { // STERN: four-point star — radiant geometry plus sparkles.
                int[] starHw = {3, 2, 2, 1, 1, 1, 1, 1, 0};
                for (int dy = -8; dy <= 8; dy++) {
                    int hw = starHw[Math.abs(dy)];
                    if (hw > 0) {
                        fillRow(guiGraphics, cx - hw, cy + dy, 2 * hw + 1, accent);
                    }
                }
                for (int dx = -8; dx <= 8; dx++) {
                    int hw = starHw[Math.abs(dx)];
                    if (hw > 0) {
                        guiGraphics.fill(cx + dx, cy - hw, cx + dx + 1, cy + hw + 1, accent);
                    }
                }
                // Hot center + diagonal sparkles.
                guiGraphics.fill(cx - 1, cy - 1, cx + 2, cy + 2, spark);
                guiGraphics.fill(cx + 5, cy - 6, cx + 6, cy - 5, spark);
                guiGraphics.fill(cx - 6, cy + 5, cx - 5, cy + 6, spark);
            }
        }
    }

    private static void fillRow(GuiGraphics guiGraphics, int x, int y, int width, int color) {
        guiGraphics.fill(x, y, x + width, y + 1, color);
    }

    /** 1px rectangle outline from four fills (the glow/confirmation ring primitive). */
    private static void drawOutline(GuiGraphics guiGraphics, int x, int y, int width, int height,
            int color) {
        guiGraphics.fill(x, y, x + width, y + 1, color);
        guiGraphics.fill(x, y + height - 1, x + width, y + height, color);
        guiGraphics.fill(x, y + 1, x + 1, y + height - 1, color);
        guiGraphics.fill(x + width - 1, y + 1, x + width, y + height - 1, color);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (chosenCard >= 0) {
            return true; // confirmation beat: input is locked, the choice is sent
        }
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
        if (chosenCard >= 0) {
            return true; // confirmation beat: input is locked, the choice is sent
        }
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

    /**
     * The one deliberate action: lock the path server-side, then play the confirmation
     * beat and close. The payload is sent IMMEDIATELY (server-authoritative, same flow
     * as ever) — the beat is pure client ceremony; {@code reducedFx} skips it.
     */
    private void choose(int index) {
        if (chosenCard >= 0) {
            return;
        }
        UiSounds.click();
        UiSounds.unlockSting();
        PacketDistributor.sendToServer(new C2SWandChoosePathPayload(PATHS[index].id()));
        if (EclipseClientConfig.reducedFx()) {
            onClose();
            return;
        }
        chosenCard = index;
        confirmTicks = 0;
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
