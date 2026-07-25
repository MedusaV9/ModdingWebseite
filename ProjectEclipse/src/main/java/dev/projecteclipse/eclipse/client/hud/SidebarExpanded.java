package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CBuffStatePayload;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import net.minecraft.Util;
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
    /** A8 widened 220 → 280; UIPOLISH ("sehr gepackt") 280 → 320 + looser row rhythm. */
    public static final int WIDTH = 320;
    /** Goal kinds: 0 = global mission; 1 = sidequest and 2 = personal share one section. */
    private static final int[] GLOBAL_KINDS = {0};
    private static final int[] SIDE_KINDS = {1, 2};
    private static final long ANIMATION_MILLIS = 8L * 50L;
    /** UIPOLISH: inner padding aligned with {@link EclipseUiTheme#PAD} (was 10). */
    private static final int PAD = 12;
    private static final int BAR_HEIGHT = 2;
    /** Checkmark draw-on window (W4-FEEL, IDEA-05 #2): two strokes over ~8 ticks. */
    private static final long CHECK_DRAW_MILLIS = 8L * 50L;
    /**
     * UIPOLISH TAB auto-scroll: when the card's natural content is taller than the screen
     * allows, the body (everything below the pinned title row) slowly ping-pong-scrolls —
     * hold TAB, dwell {@value #SCROLL_DWELL_MILLIS} ms at the top, ease down over one slow
     * leg, dwell at the bottom, ease back up, loop. Purely wall-clock driven off
     * {@link #fullyOpenSinceMillis}; {@code reducedFx} keeps the old clamp (no motion, the
     * card simply shows what fits).
     */
    private static final long SCROLL_DWELL_MILLIS = 3_000L;
    /** Scroll speed of one leg — slow enough to read every row as it passes. */
    private static final float SCROLL_PX_PER_SECOND = 18.0F;

    private static float progress;
    private static long lastUpdateMillis;
    /** Wall-clock stamp of the card reaching full expansion; 0 while (partially) closed. */
    private static long fullyOpenSinceMillis;

    private SidebarExpanded() {}

    /**
     * Advances the hold animation and returns ease-out-cubic progress. Opening a screen makes
     * the caller pass {@code requested=false}, guaranteeing a clean release mid-hold.
     */
    public static float update(boolean requested, boolean reducedFx, long nowMillis) {
        if (reducedFx) {
            progress = requested ? 1.0F : 0.0F;
            lastUpdateMillis = nowMillis;
            trackFullyOpen(nowMillis);
            return progress;
        }
        if (lastUpdateMillis == 0L) {
            lastUpdateMillis = nowMillis;
        }
        long elapsed = Math.max(0L, Math.min(100L, nowMillis - lastUpdateMillis));
        lastUpdateMillis = nowMillis;
        float step = elapsed / (float) ANIMATION_MILLIS;
        progress = Mth.clamp(progress + (requested ? step : -step), 0.0F, 1.0F);
        trackFullyOpen(nowMillis);
        return easeOutCubic(progress);
    }

    /** Arms/disarms the auto-scroll dwell clock as the card reaches/leaves full expansion. */
    private static void trackFullyOpen(long nowMillis) {
        if (progress >= 0.999F) {
            if (fullyOpenSinceMillis == 0L) {
                fullyOpenSinceMillis = nowMillis;
            }
        } else {
            fullyOpenSinceMillis = 0L;
        }
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
        fullyOpenSinceMillis = 0L;
    }

    /**
     * Natural logical height of the complete detail card at {@link #WIDTH}. UIPOLISH: the
     * arithmetic mirrors {@link #render} row for row (the old footer estimate was ~9px
     * short, which cropped the stage line) — keep both in lockstep when touching spacing.
     */
    public static int preferredHeight(Font font) {
        int textWidth = WIDTH - PAD * 2 - 10;
        int height = PAD + 18 + 16; // title block, vitals row
        height += 15 + goalListHeight(font, validGoals(GLOBAL_KINDS), textWidth); // global missions
        height += 15 + goalListHeight(font, validGoals(SIDE_KINDS), textWidth); // sidequests
        height += 15; // side/personal summary
        List<S2CBuffStatePayload.Buff> buffs = validBuffs();
        if (!buffs.isEmpty()) {
            height += 15 + buffs.size() * 12;
            for (S2CBuffStatePayload.Buff buff : buffs) {
                String descKey = buffDescKey(buff.id());
                if (EclipseLang.hasKey(descKey)) {
                    // Same wrap width as render: (right - left) - 10 == textWidth.
                    height += font.split(EclipseLang.tr(descKey), textWidth).size()
                            * (font.lineHeight + 1) + 2;
                }
            }
        }
        height += 15 + 12 + 8 + 15 + 9 + PAD; // "you", skill row+bar, shards, stage footer
        return Math.max(156, height);
    }

    /** Height of one rendered goal list; an empty list still spends its placeholder row. */
    private static int goalListHeight(Font font, List<S2CQuestStatePayload.QuestEntry> goals,
            int textWidth) {
        if (goals.isEmpty()) {
            return 14;
        }
        int height = 0;
        for (S2CQuestStatePayload.QuestEntry entry : goals) {
            height += Math.max(1,
                    font.split(Component.literal(goalText(entry)),
                            entryTextWidth(font, entry, textWidth)).size())
                    * font.lineHeight + BAR_HEIGHT + 7;
        }
        return height;
    }

    /**
     * Rows with reward chips (FIX-ECON "◆N" + EVAL-DOPA-F "+N XP") wrap their text short
     * of the right-aligned chip pair.
     */
    private static int entryTextWidth(Font font, S2CQuestStatePayload.QuestEntry entry,
            int textWidth) {
        int chips = chipsWidth(font, entry);
        return chips == 0 ? textWidth : Math.max(20, textWidth - chips - 4);
    }

    /** Combined pixel width of the right-aligned reward chips ({@code 0} = no chips). */
    private static int chipsWidth(Font font, S2CQuestStatePayload.QuestEntry entry) {
        int width = 0;
        if (entry.rewardShards() > 0) {
            width += font.width("\u25c6" + entry.rewardShards());
        }
        if (entry.rewardXp() > 0) {
            width += font.width("+" + entry.rewardXp() + "XP") + (width > 0 ? 3 : 0);
        }
        return width;
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

        // Pinned header (title + hairline) — the auto-scroll below never moves it.
        String timer = formatRemaining(remainingMillis());
        String title = EclipseLang.trString("sidebar.eclipse.expanded.title",
                ClientStateCache.sidebarDay, timer);
        guiGraphics.drawCenteredString(font, title, width / 2, y,
                MarqueeText.faded(EclipseUiTheme.TEXT, alpha));
        y += 12;
        EclipseUiTheme.drawHairline(guiGraphics, left, right, y,
                alpha);
        y += 6;

        // UIPOLISH auto-scroll: overflow beyond the clamped panel height ping-pongs the
        // body inside the scissor (see SCROLL_DWELL_MILLIS); reducedFx keeps the clamp.
        // GuiGraphics scissor coordinates are absolute GUI-space and do not follow pose
        // translation/scale, so convert this panel-local rectangle explicitly.
        guiGraphics.enableScissor(
                (int) Math.floor(panelScreenX + left * scale),
                (int) Math.floor(panelScreenY + y * scale),
                (int) Math.ceil(panelScreenX + right * scale),
                (int) Math.ceil(panelScreenY + bottom * scale));
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F,
                -scrollOffset(preferredHeight(font) - height, Util.getMillis()), 0.0F);

        String hearts = heartRow(ClientStateCache.lives);
        String altar = EclipseLang.trString("sidebar.eclipse.expanded.altar_shards",
                ClientStateCache.sidebarAltarLevel, ClientStateCache.sidebarShards);
        guiGraphics.drawString(font, hearts, left, y,
                MarqueeText.faded(EclipseUiTheme.DANGER, alpha));
        guiGraphics.drawString(font, altar, right - font.width(altar), y,
                MarqueeText.faded(EclipseUiTheme.TEXT, alpha));
        y += 16;

        // A8 §3: two clearly labeled goal sections — global missions, then sidequests.
        int goalTextWidth = right - left - 10;
        y = section(guiGraphics, font, EclipseLang.tr("gui.eclipse.sidebar.section.global"),
                left, right, y, alpha);
        y = renderGoalList(guiGraphics, font, validGoals(GLOBAL_KINDS),
                left, y, goalTextWidth, alpha);
        y = section(guiGraphics, font, EclipseLang.tr("gui.eclipse.sidebar.section.side"),
                left, right, y, alpha);
        y = renderGoalList(guiGraphics, font, validGoals(SIDE_KINDS),
                left, y, goalTextWidth, alpha);

        String optional = EclipseLang.trString("sidebar.eclipse.expanded.optional",
                ClientStateCache.sidebarSidesDone, ClientStateCache.sidebarSidesTotal,
                ClientStateCache.sidebarPersonalsDone, ClientStateCache.sidebarPersonalsTotal);
        guiGraphics.drawString(font, optional, left, y,
                MarqueeText.faded(EclipseUiTheme.DIM, alpha));
        y += 15;

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
                y += 12;
                // UIPOLISH: one dim explanation line per buff — what the effect actually
                // does. Keys are per buff id; unknown (admin-added) ids skip the line.
                String descKey = buffDescKey(buff.id());
                if (EclipseLang.hasKey(descKey)) {
                    for (FormattedCharSequence line : font.split(
                            EclipseLang.tr(descKey), right - left - 10)) {
                        guiGraphics.drawString(font, line, left + 10, y,
                                MarqueeText.faded(EclipseUiTheme.DIM, alpha * 0.9F));
                        y += font.lineHeight + 1;
                    }
                    y += 2;
                }
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
        y += 12;
        drawBar(guiGraphics, left, y, right - left,
                ClientStateCache.sidebarXpIntoLevel,
                ClientStateCache.sidebarXpForLevel, false, alpha);
        y += 8;
        String shards = EclipseLang.trString("sidebar.eclipse.expanded.shards",
                ClientStateCache.sidebarShards);
        guiGraphics.drawString(font, shards, left, y,
                MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
        y += 15;

        String stage = EclipseLang.trString("sidebar.eclipse.expanded.stage",
                ClientStateCache.stageOverworld, ClientStateCache.stageRadiusOverworld);
        guiGraphics.drawString(font, stage, left, y,
                MarqueeText.faded(EclipseUiTheme.DIM, alpha));

        guiGraphics.pose().popPose();
        guiGraphics.disableScissor();
    }

    /**
     * UIPOLISH auto-scroll offset in logical px: 0 until the card has been fully open for
     * {@value #SCROLL_DWELL_MILLIS} ms, then one slow eased leg down ({@code overflow} px
     * at {@value #SCROLL_PX_PER_SECOND} px/s), a dwell at the bottom, an eased leg back up,
     * looping. No overflow or {@code reducedFx} (motion-reduction contract: clamp, don't
     * animate) always pins the top.
     */
    private static float scrollOffset(int overflow, long now) {
        if (overflow <= 0 || fullyOpenSinceMillis == 0L || EclipseClientConfig.reducedFx()) {
            return 0.0F;
        }
        long leg = Math.max(1L, (long) (overflow * 1_000.0F / SCROLL_PX_PER_SECOND));
        long t = (now - fullyOpenSinceMillis) % (2L * (SCROLL_DWELL_MILLIS + leg));
        if (t < SCROLL_DWELL_MILLIS) {
            return 0.0F; // dwell at the top
        }
        t -= SCROLL_DWELL_MILLIS;
        if (t < leg) {
            return overflow * easeInOut(t / (float) leg); // slow leg down
        }
        t -= leg;
        if (t < SCROLL_DWELL_MILLIS) {
            return overflow; // dwell at the bottom
        }
        return overflow * (1.0F - easeInOut((t - SCROLL_DWELL_MILLIS) / (float) leg)); // back up
    }

    /** Smoothstep ease-in-out — both scroll legs start and stop gently. */
    private static float easeInOut(float t) {
        t = Mth.clamp(t, 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }

    private static int section(GuiGraphics guiGraphics, Font font, Component title,
            int left, int right, int y, float alpha) {
        guiGraphics.drawString(font, title, left, y,
                MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
        int lineStart = Math.min(right, left + font.width(title) + 5);
        EclipseUiTheme.drawHairline(guiGraphics, lineStart, right, y + 5, alpha);
        return y + 15;
    }

    /** One goal section's entries (marker/check, wrapped text, progress bar); returns new y. */
    private static int renderGoalList(GuiGraphics guiGraphics, Font font,
            List<S2CQuestStatePayload.QuestEntry> goals, int left, int y,
            int goalTextWidth, float alpha) {
        if (goals.isEmpty()) {
            guiGraphics.drawString(font, EclipseLang.tr("sidebar.eclipse.expanded.no_goals"),
                    left, y, MarqueeText.faded(EclipseUiTheme.DIM, alpha));
            return y + 14;
        }
        long now = Util.getMillis();
        boolean reduced = EclipseClientConfig.reducedFx();
        for (S2CQuestStatePayload.QuestEntry goal : goals) {
            int color = goal.done() ? EclipseUiTheme.GOOD : EclipseUiTheme.TEXT;
            // Checkmark draw-on (IDEA-05 #2): keyed off the shared stamp timestamp —
            // holding TAB when the payload lands shows it live, opening within the
            // TTL catches the tail; no live stamp = fully-drawn check.
            float stampT = 1.0F;
            if (goal.done() && !reduced) {
                long stamp = SidebarPanel.goalStampStarted(goal.id());
                if (stamp > 0L) {
                    stampT = Mth.clamp((now - stamp) / (float) CHECK_DRAW_MILLIS,
                            0.0F, 1.0F);
                }
            }
            if (goal.done() && !reduced) {
                drawCheckmark(guiGraphics, left, y, easeOutCubic(stampT),
                        MarqueeText.faded(EclipseUiTheme.GOOD, alpha));
            } else {
                String marker = goal.done() ? "\u2713" : kindMarker(goal.kind());
                guiGraphics.drawString(font, marker, left, y,
                        MarqueeText.faded(color, alpha));
            }
            // FIX-ECON quest shard chip + EVAL-DOPA-F XP chip half: right-aligned "◆N" in
            // accent with a dim "+N XP" beside it on the first row line — both payouts
            // are advertised before completion.
            int chipRight = left + 10 + goalTextWidth;
            if (goal.rewardShards() > 0) {
                String chip = "\u25c6" + goal.rewardShards();
                chipRight -= font.width(chip);
                guiGraphics.drawString(font, chip, chipRight, y,
                        MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
                chipRight -= 3;
            }
            if (goal.rewardXp() > 0) {
                String xpChip = "+" + goal.rewardXp() + "XP";
                chipRight -= font.width(xpChip);
                guiGraphics.drawString(font, xpChip, chipRight, y,
                        MarqueeText.faded(EclipseUiTheme.DIM, alpha));
            }
            List<FormattedCharSequence> lines =
                    font.split(Component.literal(goalText(goal)),
                            entryTextWidth(font, goal, goalTextWidth));
            for (FormattedCharSequence line : lines) {
                guiGraphics.drawString(font, line, left + 10, y,
                        MarqueeText.faded(color, alpha));
                y += font.lineHeight;
            }
            drawBar(guiGraphics, left + 10, y + 1, goalTextWidth,
                    goal.progress(), goal.target(), goal.done(), alpha,
                    reduced ? 1.0F : easeOutCubic(stampT));
            y += BAR_HEIGHT + 7;
        }
        return y;
    }

    private static void drawBar(GuiGraphics guiGraphics, int x, int y, int width,
            int progressValue, int targetValue, boolean done, float alpha) {
        drawBar(guiGraphics, x, y, width, progressValue, targetValue, done, alpha, 1.0F);
    }

    /**
     * {@code doneSweep} 0..1 recolors a done bar ACCENT → GOOD left-to-right over the
     * checkmark draw-on window (IDEA-05 #2) instead of the instant recolor; 1 = plain.
     */
    private static void drawBar(GuiGraphics guiGraphics, int x, int y, int width,
            int progressValue, int targetValue, boolean done, float alpha, float doneSweep) {
        guiGraphics.fill(x, y, x + width, y + BAR_HEIGHT,
                MarqueeText.faded(EclipseUiTheme.HAIRLINE, alpha));
        float fraction = targetValue <= 0 ? 0.0F
                : Mth.clamp(progressValue / (float) targetValue, 0.0F, 1.0F);
        if (done) {
            fraction = 1.0F;
        }
        int fill = Math.round(width * fraction);
        if (fill <= 0) {
            return;
        }
        if (done && doneSweep < 1.0F) {
            int good = Math.round(fill * Mth.clamp(doneSweep, 0.0F, 1.0F));
            if (good > 0) {
                guiGraphics.fill(x, y, x + good, y + BAR_HEIGHT,
                        MarqueeText.faded(EclipseUiTheme.GOOD, alpha));
            }
            if (good < fill) {
                guiGraphics.fill(x + good, y, x + fill, y + BAR_HEIGHT,
                        MarqueeText.faded(EclipseUiTheme.ACCENT, alpha));
            }
            return;
        }
        guiGraphics.fill(x, y, x + fill, y + BAR_HEIGHT,
                MarqueeText.faded(done ? EclipseUiTheme.GOOD : EclipseUiTheme.ACCENT, alpha));
    }

    /**
     * Two-stroke vector check drawn from six 1×2 {@code fill()} pixels (IDEA-05 #2): the
     * short stroke (down-right) lands in the first ~35% of {@code t}, the long stroke
     * (up-right) draws over the rest. {@code t} is already eased by the caller.
     */
    private static void drawCheckmark(GuiGraphics guiGraphics, int x, int y, float t, int color) {
        // Pixel columns of the check, left to right: short stroke (2), long stroke (4).
        float shortT = Mth.clamp(t / 0.35F, 0.0F, 1.0F);
        float longT = Mth.clamp((t - 0.35F) / 0.65F, 0.0F, 1.0F);
        int shortLen = Math.round(2.0F * shortT);
        int longLen = Math.round(4.0F * longT);
        if (shortLen >= 1) {
            guiGraphics.fill(x, y + 3, x + 1, y + 5, color);
        }
        if (shortLen >= 2) {
            guiGraphics.fill(x + 1, y + 4, x + 2, y + 6, color);
        }
        if (longLen >= 1) {
            guiGraphics.fill(x + 2, y + 5, x + 3, y + 7, color);
        }
        if (longLen >= 2) {
            guiGraphics.fill(x + 3, y + 4, x + 4, y + 6, color);
        }
        if (longLen >= 3) {
            guiGraphics.fill(x + 4, y + 3, x + 5, y + 5, color);
        }
        if (longLen >= 4) {
            guiGraphics.fill(x + 5, y + 2, x + 6, y + 4, color);
        }
    }

    /** Today's payload-fed goals filtered to the given kinds, in payload order (cap 32). */
    private static List<S2CQuestStatePayload.QuestEntry> validGoals(int... kinds) {
        List<S2CQuestStatePayload.QuestEntry> result = new ArrayList<>();
        int expectedDay = ClientStateCache.sidebarDay;
        if (ClientStateCache.questDay != expectedDay) {
            return result;
        }
        for (S2CQuestStatePayload.QuestEntry entry : ClientStateCache.questEntries) {
            if (entry == null || entry.target() <= 0 || result.size() >= 32) {
                continue;
            }
            for (int kind : kinds) {
                if (entry.kind() == kind) {
                    result.add(entry);
                    break;
                }
            }
        }
        return result;
    }

    /**
     * UIPOLISH: lang key of the one-line effect explanation for a buff id. Rides the
     * {@code sidebar.eclipse.} prefix (already in the {@code EclipseLang} table) because
     * the TAB card is the only buff timer surface — ids come from {@code BuffConfig}.
     */
    private static String buffDescKey(String buffId) {
        return "sidebar.eclipse.buff." + buffId + ".desc";
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
