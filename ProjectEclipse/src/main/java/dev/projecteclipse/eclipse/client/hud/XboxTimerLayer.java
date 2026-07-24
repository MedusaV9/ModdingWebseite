package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import dev.projecteclipse.eclipse.xboxevent.XboxPayloads;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;

/**
 * C17 Xbox-event countdown HUD — the ONE timer surface for the tutorial-world event (the
 * {@code ServerBossEvent} fallback is deleted; no stacked bars, per A7/W-HUD). Renders the
 * server-authoritative remaining time from {@link XboxPayloads.TimerClientState} in the
 * {@code DayTimerLayer} bottom-center slot while the local player is INSIDE an Xbox
 * dimension; {@code DayTimerLayer} yields the slot via {@link #active()} (the A7 seam —
 * "one layer branch"), so the two countdowns can never stack.
 *
 * <ul>
 *   <li><b>Digits</b>: {@code MM:SS} at 1.5x (vanilla digit glyphs are uniformly 6&nbsp;px
 *       wide, so the line stays stable while ticking; only the width-identical digits
 *       change).</li>
 *   <li><b>Color</b>: classic plain white, flipping to yellow inside the final 5 minutes
 *       and red inside the final minute — mirroring the server's T-5/T-1 chat warnings.</li>
 *   <li><b>Underline</b>: remaining fraction of the largest window seen since activation
 *       (the frozen payload carries no total, §2.13.5 — the client tracks its own max).</li>
 *   <li><b>Caption</b>: the localized tutorial-world name in DIM above the digits.</li>
 *   <li><b>Anti-clutter</b>: hidden under F1 and cutscene HUD suppression (deliberately
 *       NOT letterbox-whitelisted, same policy as the day timer).</li>
 * </ul>
 *
 * <p>Hot path is allocation-free: the digit string re-bakes only when the shown second
 * changes, the caption only when the world id changes.</p>
 */
public final class XboxTimerLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "xbox_timer");

    private static final float SCALE = 1.5F;
    /** A7 bottom slot: block bottoms out at {@code guiHeight - 47} (DayTimerLayer parity). */
    private static final int BOTTOM_ANCHOR = 47;
    private static final long WARN_YELLOW_MILLIS = 5L * 60L * 1000L;
    private static final long WARN_RED_MILLIS = 60L * 1000L;

    // --- render caches (client thread only; zero allocations while the digits hold) ---
    private static long shownSeconds = -1L;
    private static String digits = "00:00";
    private static String captionWorldId = "";
    private static Component caption = Component.empty();
    /** Largest remaining window observed since the timer went active (fraction base). */
    private static long maxRemainingMillis;
    private static boolean wasActive;

    private XboxTimerLayer() {}

    /**
     * Whether this layer owns the bottom-center countdown slot this frame — the payload
     * says the event timer is live AND the local player is actually inside an Xbox
     * dimension (belt and braces: a stale {@code active} after a weird disconnect can
     * never paint a countdown into the overworld HUD).
     */
    public static boolean active() {
        Minecraft minecraft = Minecraft.getInstance();
        return XboxPayloads.TimerClientState.active()
                && minecraft.level != null
                && XboxDimensions.isXboxDimension(minecraft.level.dimension());
    }

    /** {@code LayeredDraw.Layer} body, registered by {@code EclipseGuiLayers}. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!active() || minecraft.player == null || minecraft.options.hideGui) {
            wasActive = false;
            return;
        }
        if (!wasActive) {
            wasActive = true;
            maxRemainingMillis = 0L;
            shownSeconds = -1L;
        }

        long remaining = XboxPayloads.TimerClientState.remainingMillis();
        maxRemainingMillis = Math.max(maxRemainingMillis, remaining);
        long seconds = (remaining + 999L) / 1000L;
        if (seconds != shownSeconds) {
            shownSeconds = seconds;
            long minutes = Math.min(99L, seconds / 60L);
            digits = String.format(java.util.Locale.ROOT, "%02d:%02d", minutes, seconds % 60L);
        }
        String worldId = XboxPayloads.TimerClientState.worldId();
        if (!worldId.equals(captionWorldId)) {
            captionWorldId = worldId;
            caption = Component.translatable("eclipse.xboxworld." + worldId + ".name");
        }

        int rgb;
        if (remaining <= WARN_RED_MILLIS) {
            rgb = 0xFF5555; // matches the server's red T-1 warning
        } else if (remaining <= WARN_YELLOW_MILLIS) {
            rgb = 0xFFFF55; // matches the yellow T-5 warning
        } else {
            rgb = EclipseUiTheme.TEXT & 0xFFFFFF;
        }
        int color = 0xFF000000 | rgb;

        Font font = minecraft.font;
        float widthAbs = font.width(digits) * SCALE;
        int baseX = Math.round((guiGraphics.guiWidth() - widthAbs) / 2.0F);
        int digitHeightAbs = Math.round(9.0F * SCALE);
        // Same lift rule as DayTimerLayer: above the vanilla status stack when it grows.
        int statusStack = Math.max(minecraft.gui.leftHeight, minecraft.gui.rightHeight);
        int blockBottom = guiGraphics.guiHeight() - Math.max(BOTTOM_ANCHOR, statusStack + 3);
        int underlineY = blockBottom - 1;
        int topY = underlineY - 2 - digitHeightAbs;

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(baseX, topY, 0.0F);
        guiGraphics.pose().scale(SCALE, SCALE, 1.0F);
        guiGraphics.drawString(font, digits, 0, 0, color);
        guiGraphics.pose().popPose();

        // Remaining-window underline (client-tracked max as the total).
        float fraction = maxRemainingMillis <= 0L ? 0.0F
                : Mth.clamp((float) remaining / maxRemainingMillis, 0.0F, 1.0F);
        int lineWidth = Math.round(widthAbs);
        guiGraphics.fill(baseX, underlineY, baseX + lineWidth, underlineY + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.9F));
        int filled = Math.round(lineWidth * fraction);
        if (filled > 0) {
            guiGraphics.fill(baseX, underlineY, baseX + filled, underlineY + 1, color);
        }

        int captionX = guiGraphics.guiWidth() / 2 - font.width(caption) / 2;
        guiGraphics.drawString(font, caption, captionX, topY - 12, EclipseUiTheme.DIM);
    }
}
