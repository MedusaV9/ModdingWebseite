package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;

/**
 * One typewriter announcement line ({@code docs/ideas/03_ui_ux.md} §E): reveals 1 character
 * per tick with an {@code eclipse:ui.typewriter} tick every 2 characters (played through
 * the {@code uiSounds}-gated {@link UiSounds#typewriter}); the moment the line completes,
 * the full {@link Component} is posted to chat ONCE, then the overlay copy holds briefly
 * and fades. Owned and rendered by {@link AnnouncementOverlay}.
 */
final class TypewriterLine {
    private static final int HOLD_TICKS = 50;
    private static final int FADE_TICKS = 20;

    private final Component line;
    private final String text;
    private int revealed;
    private int ticksAfterDone;
    private boolean postedToChat;

    TypewriterLine(Component line) {
        this.line = line;
        this.text = line.getString();
    }

    /** Advances one tick; returns {@code true} once the line has fully faded out. */
    boolean tick() {
        Minecraft minecraft = Minecraft.getInstance();
        if (revealed < text.length()) {
            revealed++;
            if (revealed % 2 == 0 || revealed == text.length()) {
                UiSounds.typewriter(0.9F + 0.2F * (float) Math.random());
            }
            return false;
        }
        if (!postedToChat) {
            postedToChat = true;
            minecraft.gui.getChat().addMessage(line);
        }
        return ++ticksAfterDone > HOLD_TICKS + FADE_TICKS;
    }

    /** Draws the (partially revealed) line centered at the given baseline. */
    void render(GuiGraphics guiGraphics, int centerX, int y) {
        float alpha = ticksAfterDone <= HOLD_TICKS ? 1.0F
                : 1.0F - (ticksAfterDone - HOLD_TICKS) / (float) FADE_TICKS;
        int alphaByte = Mth.clamp((int) (alpha * 255.0F), 0, 255);
        if (alphaByte < 8) {
            return; // drawString treats ~0 alpha as opaque; skip instead
        }
        Minecraft minecraft = Minecraft.getInstance();
        String shown = text.substring(0, revealed);
        // Blinking cursor while typing keeps the line readable as it grows.
        if (revealed < text.length() && (minecraft.gui.getGuiTicks() / 3) % 2 == 0) {
            shown = shown + "_";
        }
        guiGraphics.drawString(minecraft.font, shown,
                centerX - minecraft.font.width(text) / 2, y, (alphaByte << 24) | 0xFFEEDD);
    }
}
