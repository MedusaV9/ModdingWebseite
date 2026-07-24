package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.S2CBuffStatePayload;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;

/**
 * TAB-hold detail card for sidebar v2. It reads only payload-fed client caches and owns the
 * eight-tick open/close progress; the outer panel interpolates its edge anchor/size from this
 * value while this renderer crossfades in the detailed content.
 */
public final class SidebarExpanded {
    public static final int WIDTH = 220;
    private static final long ANIMATION_MILLIS = 8L * 50L;
    private static final int PAD = 10;
    private static final int BAR_HEIGHT = 2;

    private static float progress;
    private static long lastUpdateMillis;

    private SidebarExpanded() {}

    /**
     * Advances the hold animation and returns ease-out-cubic progress. Opening a screen makes
     * the caller pass {@code requested=false}, guaranteeing a clean release mid-hold.
     */
    public static float update(boolean requested, boolean reducedFx, long nowMillis) {
        if (reducedFx) {
            progress = requested ? 1.0F : 0.0F;
            lastUpdateMillis = nowMillis;
            return progress;
        }
        if (lastUpdateMillis == 0L) {
            lastUpdateMillis = nowMillis;
        }
        long elapsed = Math.max(0L, Math.min(100L, nowMillis - lastUpdateMillis));
        lastUpdateMillis = nowMillis;
        float step = elapsed / (float) ANIMATION_MILLIS;
        progress = Mth.clamp(progress + (requested ? step : -step), 0.0F, 1.0F);
        return easeOutCubic(progress);
    }

    /** Pure motion curve from the Quiet Eclipse motion specification. */
    public static float easeOutCubic(float value) {
        float t = Mth.clamp(value, 0.0F, 1.0F);
        float inverse = 1.0F - t;
        return 1.0F - inverse * inverse * inverse;
    }

    public static boolean visible() {
        return progress > 0.001F;
    }

    /** Clears client-session animation state on disconnect. */
    static void reset() {
        progress = 0.0F;
        lastUpdateMillis = 0L;
    }

    /** Natural logical height of the complete detail card at {@link #WIDTH}. */
    public static int preferredHeight(Font font) {
        int textWidth = WIDTH - PAD * 2 - 10;
        int height = PAD + 14 + 14 + 13; // title, vitals, goals header
        for (S2CQuestStatePayload.QuestEntry entry : validGoals()) {
            height += Math.max(1, font.split(Component.literal(goalText(entry)), textWidth).size())
                    * font.lineHeight + BAR_HEIGHT + 5;
        }
        height += 13; // side/personal summary
        List<S2CBuffStatePayload.Buff> buffs = validBuffs();
        if (!buffs.isEmpty()) {
            height += 13 + buffs.size() * 11;
        }
        height += 13 + 20 + 11 + PAD; // "you", skill rows, stage footer
        return Math.max(156, height);
    }

    /** Draws expanded content into an already-rendered/morphed panel rectangle. */
    public static void render(GuiGraphics guiGraphics, Font font, int width, int height,
            float alpha, float panelScreenX, float panelScreenY, float scale) {
        if (alpha <= 0.01F || width < 80 || height < 60) {
            return;
        }
        int left = PAD;
        int right = width - PAD;
        int y = PAD;
        int bottom = height - PAD;

        // GuiGraphics scissor coordinates are absolute GUI-space and do not follow pose
        // translation/scale, so convert this panel-local rectangle explicitly.
        guiGraphics.enableScissor(
                (int) Math.floor(panelScreenX + left * scale),
                (int) Math.floor(panelScreenY + y * scale),
                (int) Math.ceil(panelScreenX + right * scale),
                (int) Math.ceil(panelScreenY + bottom * scale));

        String timer = formatRemaining(remainingMillis());
        String title = EclipseLang.trString("sidebar.eclipse.expanded.title",
                ClientStateCache.sidebarDay, timer);
        guiGraphics.drawCenteredString(font, title, width / 2, y,
                MarqueeText.faded(EclipseUiTheme.TEXT, alpha));
        y += 11;
        EclipseUiTheme.drawHairline(guiGraphics, left, right, y,
                alpha);
        y += 5;

        String hearts = heartRow(ClientStateCache.lives);
        String altar = EclipseLang.trString("sidebar.eclipse.expanded.altar_shards",
                ClientStateCache.sidebarAltarLevel, ClientStateCache.sidebarShards);
        guiGraphics.drawString(font, hearts, left, y,
                MarqueeText.faded(EclipseUiTheme.DANGER, alpha));
        guiGraphics.drawString(font, altar, right - font.width(altar), y,
                MarqueeText.faded(EclipseUiTheme.TEXT, alpha));
        y += 14;

        y = section(guiGraphics, font, EclipseLang.tr("sidebar.eclipse.expanded.goals"),
                left, right, y, alpha);
        int goalTextWidth = right - left - 10;
        List<S2CQuestStatePayload.QuestEntry> goals = validGoals();
        if (goals.isEmpty()) {
            guiGraphics.drawString(font, EclipseLang.tr("sidebar.eclipse.expanded.no_goals"),
                    left, y, MarqueeText.faded(EclipseUiTheme.DIM, alpha));
            y += 12;
        } else {
            for (S2CQuestStatePayload.QuestEntry goal : goals) {
                int color = goal.done() ? EclipseUiTheme.GOOD : EclipseUiTheme.TEXT;
                String marker = goal.done() ? "\u2713" : kindMarker(goal.kind());
                guiGraphics.drawString(font, marker, left, y,
                        MarqueeText.faded(color, alpha));
                List<FormattedCharSequence> lines =
                        font.split(Component.literal(goalText(goal)), goalTextWidth);
                for (FormattedCharSequence line : lines) {
                    guiGraphics.drawString(font, line, left + 10, y,
                            MarqueeText.faded(color, alpha));
                    y += font.lineHeight;
                }
                drawBar(guiGraphics, left + 10, y + 1, goalTextWidth,
                        goal.progress(), goal.target(), goal.done(), alpha);
                y += BAR_HEIGHT + 5;
            }
        }

        String optional = EclipseLang.trString("sidebar.eclipse.expanded.optional",
                ClientStateCache.sidebarSidesDone, ClientStateCache.sidebarSidesTotal,
                ClientStateCache.sidebarPersonalsDone, ClientStateCache.sidebarPersonalsTotal);
        guiGraphics.drawString(font, optional, left, y,
                MarqueeText.faded(EclipseUiTheme.DIM, alpha));
        y += 13;

        List<S2CBuffStatePayload.Buff> buffs = validBuffs();
        if (!buffs.isEmpty()) {
            y = section(guiGraphics, font, EclipseLang.tr("sidebar.eclipse.expanded.buffs"),
                    left, right, y, alpha);
            for (S2CBuffStatePayload.Buff buff : buffs) {
                String titleText = EclipseLang.locale().startsWith("de")
                        ? buff.titleDe() : buff.titleEn();
                    String remaining = formatDuration(Math.max(0L,
                            buff.endsAtEpochMillis() - estimatedServerNow()));
                guiGraphics.drawString(font, "\u25c6 " + titleText, left, y,
                        MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
                guiGraphics.drawString(font, remaining, right - font.width(remaining), y,
                        MarqueeText.faded(EclipseUiTheme.DIM, alpha));
                y += 11;
            }
        }

        y = section(guiGraphics, font, EclipseLang.tr("sidebar.eclipse.expanded.you"),
                left, right, y, alpha);
        String skill = EclipseLang.trString("sidebar.eclipse.expanded.skill",
                ClientStateCache.sidebarSkillLevel,
                ClientStateCache.sidebarXpIntoLevel,
                ClientStateCache.sidebarXpForLevel);
        guiGraphics.drawString(font, skill, left, y,
                MarqueeText.faded(EclipseUiTheme.TEXT, alpha));
        y += 11;
        drawBar(guiGraphics, left, y, right - left,
                ClientStateCache.sidebarXpIntoLevel,
                ClientStateCache.sidebarXpForLevel, false, alpha);
        y += 7;
        String shards = EclipseLang.trString("sidebar.eclipse.expanded.shards",
                ClientStateCache.sidebarShards);
        guiGraphics.drawString(font, shards, left, y,
                MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
        y += 13;

        String stage = EclipseLang.trString("sidebar.eclipse.expanded.stage",
                ClientStateCache.stageOverworld, ClientStateCache.stageRadiusOverworld);
        guiGraphics.drawString(font, stage, left, y,
                MarqueeText.faded(EclipseUiTheme.DIM, alpha));

        guiGraphics.disableScissor();
    }

    private static int section(GuiGraphics guiGraphics, Font font, Component title,
            int left, int right, int y, float alpha) {
        guiGraphics.drawString(font, title, left, y,
                MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
        int lineStart = Math.min(right, left + font.width(title) + 5);
        EclipseUiTheme.drawHairline(guiGraphics, lineStart, right, y + 5, alpha);
        return y + 13;
    }

    private static void drawBar(GuiGraphics guiGraphics, int x, int y, int width,
            int progressValue, int targetValue, boolean done, float alpha) {
        guiGraphics.fill(x, y, x + width, y + BAR_HEIGHT,
                MarqueeText.faded(EclipseUiTheme.HAIRLINE, alpha));
        float fraction = targetValue <= 0 ? 0.0F
                : Mth.clamp(progressValue / (float) targetValue, 0.0F, 1.0F);
        if (done) {
            fraction = 1.0F;
        }
        int fill = Math.round(width * fraction);
        if (fill > 0) {
            guiGraphics.fill(x, y, x + fill, y + BAR_HEIGHT,
                    MarqueeText.faded(done ? EclipseUiTheme.GOOD : EclipseUiTheme.ACCENT, alpha));
        }
    }

    private static List<S2CQuestStatePayload.QuestEntry> validGoals() {
        List<S2CQuestStatePayload.QuestEntry> result = new ArrayList<>();
        int expectedDay = ClientStateCache.sidebarDay;
        if (ClientStateCache.questDay != expectedDay) {
            return result;
        }
        for (S2CQuestStatePayload.QuestEntry entry : ClientStateCache.questEntries) {
            if (entry != null && entry.kind() >= 0 && entry.kind() <= 2
                    && entry.target() > 0 && result.size() < 32) {
                result.add(entry);
            }
        }
        return result;
    }

    private static List<S2CBuffStatePayload.Buff> validBuffs() {
        Set<String> allowed = new HashSet<>(ClientStateCache.sidebarBuffIds);
        if (allowed.isEmpty()) {
            return List.of();
        }
        List<S2CBuffStatePayload.Buff> result = new ArrayList<>();
        for (S2CBuffStatePayload.Buff buff : ClientStateCache.activeBuffs) {
            if (buff != null && allowed.contains(buff.id()) && buff.endsAtEpochMillis() > 0L
                    && result.size() < 8) {
                result.add(buff);
            }
        }
        return result;
    }

    private static String goalText(S2CQuestStatePayload.QuestEntry entry) {
        return EclipseLang.locale().startsWith("de") && !entry.textDe().isBlank()
                ? entry.textDe() : entry.textEn();
    }

    private static String kindMarker(byte kind) {
        return switch (kind) {
            case 1 -> "\u2022";
            case 2 -> "\u25c7";
            default -> "\u2610";
        };
    }

    private static String heartRow(int lives) {
        int filled = Mth.clamp(lives, 0, 7);
        int slots = Math.max(5, filled);
        return "\u2764".repeat(filled) + "\u2661".repeat(Math.max(0, slots - filled));
    }

    static long remainingMillis() {
        if (ClientStateCache.sidebarBoundaryEpochMillis <= 0L) {
            return -1L;
        }
        if (ClientStateCache.sidebarPaused) {
            return ClientStateCache.dayClockDay == ClientStateCache.sidebarDay
                    ? Math.max(0L, ClientStateCache.pauseRemainingMillis) : 0L;
        }
        return Math.max(0L,
                ClientStateCache.sidebarBoundaryEpochMillis - estimatedServerNow());
    }

    /**
     * Server "now" from the last clock payload plus local epoch elapsed since receipt.
     * {@link ClientStateCache#clockSyncLocalMillis} is an epoch stamp
     * ({@code System.currentTimeMillis()} at payload receipt), so the delta MUST be computed
     * against the epoch clock — never against monotonic {@code Util.getMillis()} — mirroring
     * {@code DevHandbookScreen.timerText()}.
     */
    private static long estimatedServerNow() {
        long localNow = System.currentTimeMillis();
        if (ClientStateCache.serverNowEpochMillis > 0L
                && ClientStateCache.clockSyncLocalMillis > 0L) {
            return ClientStateCache.serverNowEpochMillis
                    + Math.max(0L, localNow - ClientStateCache.clockSyncLocalMillis);
        }
        return localNow;
    }

    static String formatRemaining(long millis) {
        if (millis < 0L) {
            return EclipseLang.trString("sidebar.eclipse.timer.inactive");
        }
        if (ClientStateCache.sidebarPaused) {
            return EclipseLang.trString("sidebar.eclipse.timer.paused");
        }
        return formatDuration(millis);
    }

    private static String formatDuration(long millis) {
        long totalSeconds = Math.max(0L, millis / 1_000L);
        long days = totalSeconds / 86_400L;
        long hours = totalSeconds / 3_600L % 24L;
        long minutes = totalSeconds / 60L % 60L;
        long seconds = totalSeconds % 60L;
        if (days > 0L) {
            return EclipseLang.trString("sidebar.eclipse.timer.days",
                    days, "%02d:%02d".formatted(hours, minutes));
        }
        if (totalSeconds >= 3_600L) {
            return "%02d:%02d:%02d".formatted(totalSeconds / 3_600L, minutes, seconds);
        }
        return "%02d:%02d".formatted(minutes, seconds);
    }
}
