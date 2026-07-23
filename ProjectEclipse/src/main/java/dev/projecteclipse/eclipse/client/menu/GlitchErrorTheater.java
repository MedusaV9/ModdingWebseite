package dev.projecteclipse.eclipse.client.menu;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

import javax.annotation.Nullable;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.lwjgl.glfw.GLFW;

/**
 * The pre-activation "glitch error theater" of the journey button ({@code docs/plans_v3/
 * P3_ui.md} §3.8, P3-W8): a sequence of 2–3 FAKE modal error panels — Quiet Eclipse panel
 * language (§2.1 palette, pure fills, no textures), {@link GlitchText}-flavored titles, a
 * digital-static burst per popup — followed by a short decaying shake of the journey button.
 * Pure client-side playfulness: nothing here ever throws, connects or blocks the title screen
 * (every panel dismisses on ANY click / Enter / Space / Esc and auto-dismisses after 6 s).
 *
 * <p>Also reused as the presenter for real connect errors via {@link #showSingle(Component)}
 * — a themed panel instead of a crash (plan risk R-2). That path stays functional under
 * {@code reducedFx} (calm variant: no scramble suffix, no static slivers, no shake), while the
 * decorative locked-gate sequence is never triggered under {@code reducedFx} (the screen shows
 * a plain disabled tooltip instead, per §3.8).</p>
 *
 * <p>Sound: {@code ui.error_glitch} is a W1-registered event that may not exist yet; per the
 * §2.3 procedural-fallback rule this plays the shipped {@code event.border_glitch} static
 * burst + a down-pitched {@code ui.tab} through {@code SimpleSoundInstance.forUI}, gated by
 * the {@code uiSounds} config (swap point documented in the P3-W8 wiring file).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class GlitchErrorTheater {
    // Frozen "Quiet Eclipse" tokens (§2.1). Mirrored privately because W1's EclipseUiTheme
    // lands in parallel — the integrator may swap these for the shared constants verbatim.
    private static final int PANEL = 0xF2120B1E;
    private static final int PANEL_RAISED = 0xF21A1128;
    private static final int HAIRLINE = 0xFF2E2347;
    private static final int ACCENT = 0xFFB98CFF;
    private static final int TEXT = 0xFFEDE7F8;
    private static final int DIM = 0xFF9A8FB8;
    private static final int DANGER = 0xFFE86078;
    private static final int VEIL = 0xB8060310;

    private static final String[] ERROR_KEYS = {
            "gui.eclipse.journey.error.1",
            "gui.eclipse.journey.error.2",
            "gui.eclipse.journey.error.3",
            "gui.eclipse.journey.error.4",
            "gui.eclipse.journey.error.5",
    };

    private static final int POP_IN_TICKS = 4;
    private static final int GAP_TICKS = 8;
    private static final int AUTO_DISMISS_TICKS = 120;
    private static final long SHAKE_DURATION_MILLIS = 420L;

    private enum State {
        IDLE, POPUP, GAP
    }

    /** Fired once when a full locked-gate sequence finished (arms the countdown line). */
    private final Runnable onSequenceEnd;

    private State state = State.IDLE;
    private final List<Component> queue = new ArrayList<>();
    private int panelIndex = -1;
    @Nullable
    private Component currentBody;
    private int stateTicks;
    private int jitterSeed;
    private boolean shakeWhenDone;
    private long shakeStartMillis;

    public GlitchErrorTheater(Runnable onSequenceEnd) {
        this.onSequenceEnd = onSequenceEnd;
    }

    /** True while a fake panel (or the beat between two panels) owns mouse + keyboard. */
    public boolean modalActive() {
        return state != State.IDLE;
    }

    /** Starts a randomized 2–3 panel locked-gate sequence (never call under reducedFx). */
    public void trigger() {
        queue.clear();
        List<String> keys = new ArrayList<>(List.of(ERROR_KEYS));
        Collections.shuffle(keys, ThreadLocalRandom.current());
        int count = 2 + ThreadLocalRandom.current().nextInt(2);
        for (int i = 0; i < count; i++) {
            queue.add(EclipseLang.tr(keys.get(i)));
        }
        jitterSeed = ThreadLocalRandom.current().nextInt(1 << 20);
        panelIndex = -1;
        shakeWhenDone = true;
        advance();
    }

    /** One themed panel with a concrete message (connect failures); no shake, reducedFx-safe. */
    public void showSingle(Component body) {
        queue.clear();
        queue.add(body);
        jitterSeed = ThreadLocalRandom.current().nextInt(1 << 20);
        panelIndex = -1;
        shakeWhenDone = false;
        advance();
    }

    /** Clears every panel + pending shake (used when the gate unlocks mid-sequence). */
    public void reset() {
        state = State.IDLE;
        queue.clear();
        currentBody = null;
        shakeStartMillis = 0L;
    }

    private void advance() {
        panelIndex++;
        if (panelIndex >= queue.size()) {
            boolean finishedGateSequence = shakeWhenDone;
            reset();
            if (finishedGateSequence) {
                shakeStartMillis = System.currentTimeMillis();
                onSequenceEnd.run();
            }
            return;
        }
        currentBody = queue.get(panelIndex);
        state = panelIndex == 0 ? State.POPUP : State.GAP;
        stateTicks = 0;
        if (state == State.POPUP) {
            playGlitchBurst();
        }
    }

    public void tick() {
        if (state == State.IDLE) {
            return;
        }
        stateTicks++;
        if (state == State.GAP && stateTicks >= GAP_TICKS) {
            state = State.POPUP;
            stateTicks = 0;
            playGlitchBurst();
        } else if (state == State.POPUP && stateTicks >= AUTO_DISMISS_TICKS) {
            advance();
        }
    }

    /** Decaying horizontal offset for the journey button after the last panel; 0 when idle. */
    public float buttonShakeOffset() {
        if (shakeStartMillis == 0L || EclipseClientConfig.reducedFx()) {
            return 0.0F;
        }
        long elapsed = System.currentTimeMillis() - shakeStartMillis;
        if (elapsed >= SHAKE_DURATION_MILLIS) {
            shakeStartMillis = 0L;
            return 0.0F;
        }
        float progress = elapsed / (float) SHAKE_DURATION_MILLIS;
        return Mth.sin(elapsed * 0.09F) * 4.0F * (1.0F - progress);
    }

    // ------------------------------------------------------------------ input

    /** Swallows everything while modal; any click dismisses the current panel. */
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (state == State.IDLE) {
            return false;
        }
        if (state == State.POPUP && button == GLFW.GLFW_MOUSE_BUTTON_LEFT) {
            advance();
        }
        return true;
    }

    /** Enter/Space/Esc acknowledge the current panel; all other keys are swallowed (modal). */
    public boolean keyPressed(int keyCode) {
        if (state == State.IDLE) {
            return false;
        }
        if (state == State.POPUP && (keyCode == GLFW.GLFW_KEY_ENTER || keyCode == GLFW.GLFW_KEY_KP_ENTER
                || keyCode == GLFW.GLFW_KEY_SPACE || keyCode == GLFW.GLFW_KEY_ESCAPE)) {
            advance();
        }
        return true;
    }

    // ----------------------------------------------------------------- render

    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick,
            int screenWidth, int screenHeight, Font font) {
        if (state == State.IDLE) {
            return;
        }
        guiGraphics.fill(0, 0, screenWidth, screenHeight, VEIL);
        if (state != State.POPUP || currentBody == null) {
            return;
        }

        boolean calm = EclipseClientConfig.reducedFx();
        int panelW = Math.min(340, screenWidth - 32);
        List<FormattedCharSequence> bodyLines = font.split(currentBody, panelW - 24);
        int bodyHeight = Math.max(9, bodyLines.size() * 10);
        int panelH = 22 + 6 + bodyHeight + 10 + 20 + 10;

        // Deterministic per-panel jitter: successive popups land slightly displaced,
        // like a cascade of separate broken dialogs.
        RandomSource jitter = RandomSource.create(jitterSeed * 31L + panelIndex * 7919L);
        int dx = calm ? 0 : jitter.nextInt(37) - 18;
        int dy = calm ? 0 : jitter.nextInt(25) - 12;
        int x = (screenWidth - panelW) / 2 + dx;
        int y = (screenHeight - panelH) / 2 + dy;

        float pop = calm ? 1.0F : Math.min(1.0F, (stateTicks + partialTick) / POP_IN_TICKS);
        float eased = pop * pop * (3.0F - 2.0F * pop);
        float alpha = eased;
        float scale = 0.92F + 0.08F * eased;

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(x + panelW / 2.0F, y + panelH / 2.0F, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        guiGraphics.pose().translate(-(x + panelW / 2.0F), -(y + panelH / 2.0F), 0.0F);
        RenderSystem.enableBlend();

        // Panel: fill + hairline border + 1px DANGER top edge (error variant of the accent edge).
        guiGraphics.fill(x, y, x + panelW, y + panelH, withAlpha(PANEL, alpha));
        guiGraphics.fill(x, y, x + panelW, y + 1, withAlpha(DANGER, alpha));
        guiGraphics.fill(x, y + panelH - 1, x + panelW, y + panelH, withAlpha(HAIRLINE, alpha));
        guiGraphics.fill(x, y + 1, x + 1, y + panelH - 1, withAlpha(HAIRLINE, alpha));
        guiGraphics.fill(x + panelW - 1, y + 1, x + panelW, y + panelH - 1, withAlpha(HAIRLINE, alpha));

        // Title row: localized "FEHLER 0xECL1PSE" + a live glitch suffix block.
        String title = EclipseLang.trString("gui.eclipse.journey.error.title");
        guiGraphics.drawString(font, title, x + 12, y + 8, withAlpha(DANGER, alpha));
        if (!calm) {
            String noise = GlitchText.scramble(4, jitterSeed + panelIndex);
            guiGraphics.drawString(font, noise, x + panelW - 12 - font.width(noise), y + 8,
                    withAlpha(ACCENT, alpha * 0.75F));
        }
        guiGraphics.fill(x + 1, y + 21, x + panelW - 1, y + 22, withAlpha(HAIRLINE, alpha));

        int lineY = y + 28;
        for (FormattedCharSequence line : bodyLines) {
            guiGraphics.drawString(font, line, x + 12, lineY, withAlpha(TEXT, alpha));
            lineY += 10;
        }

        // Fake [ OK ] acknowledge button (whole panel dismisses too — it is theater).
        int okW = 72;
        int okH = 20;
        int okX = x + (panelW - okW) / 2;
        int okY = y + panelH - 30;
        boolean okHovered = mouseX >= okX && mouseX < okX + okW && mouseY >= okY && mouseY < okY + okH;
        if (okHovered) {
            CursorManager.requestPointer();
        }
        guiGraphics.fill(okX, okY, okX + okW, okY + okH, withAlpha(PANEL_RAISED, alpha));
        int okBorder = okHovered ? ACCENT : HAIRLINE;
        guiGraphics.fill(okX, okY, okX + okW, okY + 1, withAlpha(okBorder, alpha));
        guiGraphics.fill(okX, okY + okH - 1, okX + okW, okY + okH, withAlpha(okBorder, alpha));
        guiGraphics.fill(okX, okY + 1, okX + 1, okY + okH - 1, withAlpha(okBorder, alpha));
        guiGraphics.fill(okX + okW - 1, okY + 1, okX + okW, okY + okH - 1, withAlpha(okBorder, alpha));
        Component okLabel = EclipseLang.tr("gui.eclipse.journey.error.ok");
        guiGraphics.drawString(font, okLabel, okX + (okW - font.width(okLabel)) / 2, okY + 6,
                withAlpha(okHovered ? ACCENT : DIM, alpha));

        // Two thin static slivers crossing the panel, re-rolled every 150 ms.
        if (!calm) {
            RandomSource sliver = RandomSource.create(System.currentTimeMillis() / 150L * 31L
                    + jitterSeed + panelIndex);
            for (int i = 0; i < 2; i++) {
                int sy = y + 4 + sliver.nextInt(Math.max(1, panelH - 8));
                int sx0 = x + 2 + sliver.nextInt(Math.max(1, panelW / 2));
                int sx1 = Math.min(x + panelW - 2, sx0 + 24 + sliver.nextInt(panelW / 2));
                guiGraphics.fill(sx0, sy, sx1, sy + 1,
                        withAlpha(i == 0 ? DANGER : ACCENT, alpha * 0.22F));
            }
        }

        RenderSystem.disableBlend();
        guiGraphics.pose().popPose();
    }

    // ------------------------------------------------------------------ sound

    /**
     * Procedural stand-in for W1's pending {@code ui.error_glitch} event (§2.3 fallback rule):
     * the shipped border-glitch static burst layered over a down-pitched tab click.
     */
    private void playGlitchBurst() {
        if (!EclipseClientConfig.uiSounds()) {
            return;
        }
        float pitchJitter = 0.9F + ThreadLocalRandom.current().nextFloat() * 0.2F;
        Minecraft minecraft = Minecraft.getInstance();
        minecraft.getSoundManager().play(
                SimpleSoundInstance.forUI(EclipseSounds.EVENT_BORDER_GLITCH.get(), pitchJitter, 0.5F));
        minecraft.getSoundManager().play(
                SimpleSoundInstance.forUI(EclipseSounds.UI_TAB.get(), 0.55F * pitchJitter, 0.6F));
    }

    private static int withAlpha(int argb, float alphaScale) {
        int alpha = (int) (((argb >>> 24) & 0xFF) * Mth.clamp(alphaScale, 0.0F, 1.0F));
        return (alpha << 24) | (argb & 0xFFFFFF);
    }
}
