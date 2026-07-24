package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayDeque;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.cutscene.client.CaptionRenderer;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client half of {@link S2CAnnouncePayload} ({@code docs/ideas/03_ui_ux.md} §E). Every
 * announcement plays two simultaneous pieces:
 * <ul>
 *   <li>a {@link TypewriterLine} above the hotbar (1 char/tick, tick sound every 2 chars,
 *       full line posted to chat once when typing completes), and</li>
 *   <li>a client-local bossbar sweep re-using {@link BossbarSkin#drawThemedBar}: the fill
 *       sweeps 0→1 over {@value #SWEEP_IN_TICKS}t with a bright leading edge, holds
 *       {@value #SWEEP_HOLD_TICKS}t showing the title, then fades. No {@code BossEvent} is
 *       involved — the bar exists purely in this overlay, stacked below any real bars via
 *       {@link BossbarSkin#nextFreeBarY()}.</li>
 * </ul>
 *
 * <p>Payload styles map onto the three bar skins: {@code day}→day, {@code boss}→boss,
 * {@code goal}/{@code unlock}→goal. Incoming announcements queue (cap
 * {@value #QUEUE_LIMIT}) so unlock bursts play one after another instead of overwriting.
 * Identical payloads that are still pending/visible (or started within
 * {@value #DEDUPE_WINDOW_TICKS}t) coalesce instead of replaying, and the queue defers —
 * poll, never drop — while a {@code CaptionRenderer} caption owns the shared text band;
 * captions return the politeness through {@link #isBandBusy()} (A15 two-way arbitration).
 * The layer IS letterbox-whitelisted (P2 §1.7: cutscene subtitles are delivered as
 * announcement lines, so suppression must not cancel this layer) — which is exactly why
 * the day-number card gates ITSELF on {@code CameraDirector.isHudSuppressed()} (FFIX-A /
 * POLISH S-1): a STYLE_DAY payload waits at the queue head while a flight runs, a card
 * already on screen freezes (no invisible roll/sting), and {@link #render} never paints
 * the 5× numeral over the cinematic frame. The card also claims the shared
 * {@link CenterStageArbiter} h/3 token (POLISH C-1/C-3) so it defers politely to a
 * running level-up glyph, reward materialization, boss intro or roulette veil.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AnnouncementOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "announcements");
    /** Celebratory Quasar fountain spawned once per UNLOCK-style announcement (client-only emitter). */
    private static final ResourceLocation UNLOCK_BURST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "unlock_burst");

    private static final int SWEEP_IN_TICKS = 30;
    private static final int SWEEP_HOLD_TICKS = 60;
    private static final int SWEEP_FADE_TICKS = 20;
    private static final int QUEUE_LIMIT = 8;
    /**
     * A15 dedupe window: an identical announcement arriving within this many ticks of the
     * last identical one coalesces into it instead of replaying. Sized to cover the whole
     * visible presentation (sweep {@value #SWEEP_IN_TICKS}+{@value #SWEEP_HOLD_TICKS}+
     * {@value #SWEEP_FADE_TICKS} ≈ 110t) plus margin, so a server double-send never shows
     * the same text twice back to back.
     */
    private static final int DEDUPE_WINDOW_TICKS = 200;
    private static final String UNLOCK_KEY_PREFIX = "announce.eclipse.unlock.key.";
    /** Typewriter baseline above the hotbar (clear of the vanilla actionbar at -68). */
    private static final int TYPEWRITER_BOTTOM_OFFSET = 80;

    // --- W4-CEREMONY / IDEA-09 #3: the Day-Number Moment (center-screen numeral card) ---
    /** Card fade/settle-in (shows the OLD day number). */
    private static final int CARD_IN_TICKS = 8;
    /** Breath between settle-in and the odometer roll. */
    private static final int CARD_ROLL_DELAY_TICKS = 4;
    /** Old → new digit roll (per-cell scissored, DayTimerLayer craft). */
    private static final int CARD_ROLL_TICKS = 8;
    /** Read hold on the new number (task spec ~30t). */
    private static final int CARD_HOLD_TICKS = 30;
    /** Shrink-away flight toward the sidebar day row while the typewriter line begins. */
    private static final int CARD_SHRINK_TICKS = 12;
    /** Numeral scale (task spec 4–6×); the DAY word renders at 0.4 of it. */
    private static final float CARD_SCALE = 5.0F;
    private static final float CARD_WORD_SCALE = 0.4F;
    /** Monospace digit cell at 1× (vanilla digits are uniformly ≤6px wide). */
    private static final int CARD_CELL_WIDTH = 7;
    /** Vertical odometer roll distance of one step at 1× (DayTimerLayer.CELL_ROLL_HEIGHT). */
    private static final float CARD_ROLL_HEIGHT = 10.0F;
    /** From day 14 on, the numeral renders in the warn accent (deep purple). */
    private static final int CARD_WARN_DAY = 14;
    /** {@link CenterStageArbiter} claim id (FFIX-A / POLISH C-1/C-3). */
    private static final String STAGE_ID = "day_card";
    /** Stage lease: longest card variant (~62t) + margin; renewed while the card lives. */
    private static final int CARD_LEASE_TICKS = 80;

    /** Client thread only. */
    private static final ArrayDeque<S2CAnnouncePayload> QUEUE = new ArrayDeque<>();
    private static TypewriterLine typewriter;
    private static Component sweepTitle;
    private static String sweepTheme;
    /** Ticks since the active sweep started; {@code -1} = no sweep running. */
    private static int sweepTicks = -1;
    /** Monotonic unpaused-tick clock backing the A15 dedupe window. */
    private static int clock;
    /** Identity of the most recently started announcement + its {@link #clock} stamp (A15 dedupe). */
    private static S2CAnnouncePayload lastStarted;
    private static int lastStartedClock = Integer.MIN_VALUE;

    // Day card state (client thread only). {@code cardTicks < 0} = no card running.
    private static int cardTicks = -1;
    private static int cardFromDay;
    private static int cardToDay;
    /** Last day a card was shown for, so dev day-jumps roll from the truly last seen number. */
    private static int lastCardDay = -1;
    /** The STYLE_DAY payload whose typewriter/sweep starts at the card's shrink beat. */
    private static S2CAnnouncePayload pendingDayLine;
    private static boolean cardStingPlayed;
    /** {@code reducedFx} latched at card start: static card, no roll/scramble/flight. */
    private static boolean cardReduced;

    private AnnouncementOverlay() {}

    /** {@link S2CAnnouncePayload} entry point (client main thread). */
    public static void handle(S2CAnnouncePayload payload) {
        if (isDuplicate(payload)) {
            return; // A15: same text already pending/visible/just shown — coalesce, don't replay
        }
        if (S2CAnnouncePayload.STYLE_UNLOCK.equals(payload.style())) {
            spawnUnlockBurst();
        }
        if (QUEUE.size() < QUEUE_LIMIT) {
            QUEUE.add(payload);
        }
    }

    /**
     * A15 dedupe: whether an identical payload (record equality — title, subtitle, style)
     * is already queued, is the pending day line of a live numeral card, or started within
     * the last {@value #DEDUPE_WINDOW_TICKS} ticks (i.e. is visible or only just faded).
     */
    private static boolean isDuplicate(S2CAnnouncePayload payload) {
        if (payload.equals(pendingDayLine)) {
            return true;
        }
        for (S2CAnnouncePayload queued : QUEUE) {
            if (payload.equals(queued)) {
                return true;
            }
        }
        return payload.equals(lastStarted) && clock - lastStartedClock < DEDUPE_WINDOW_TICKS;
    }

    /**
     * One {@code eclipse:unlock_burst} Quasar fountain (purple/gold sparks) at the local
     * player's feet per UNLOCK-style announcement — the style used only for timeline
     * milestone/config-key unlocks ({@code timeline.AnnouncementService}), never for
     * day/goal/boss lines. Spawned on payload arrival (the unlock moment) rather than when
     * the queued sweep plays; gated on {@code reducedFx} like the other non-essential
     * particle FX.
     */
    private static void spawnUnlockBurst() {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null || EclipseClientConfig.reducedFx()) {
            return;
        }
        QuasarSpawner.spawnOrFallback(UNLOCK_BURST, player.position());
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            typewriter = null;
            sweepTicks = -1;
            cardTicks = -1;
            pendingDayLine = null;
            lastCardDay = -1;
            lastStarted = null;
            lastStartedClock = Integer.MIN_VALUE;
            return;
        }
        if (minecraft.isPaused()) {
            // The client tick keeps firing while paused — announcements (typewriter
            // advancement + its tick sounds included) freeze; the queue stays intact.
            return;
        }
        clock++;
        // A15 two-way arbitration: while a cinematic caption is on screen, the whole
        // announcement queue defers (poll, never drop) so the two text systems never draw
        // over each other; CaptionRenderer extends the same politeness back via
        // isBandBusy(). Ordering within each queue is preserved.
        if (typewriter == null && sweepTicks < 0 && cardTicks < 0 && !QUEUE.isEmpty()
                && !CaptionRenderer.isBusy()) {
            // FFIX-A / POLISH S-1 + C-1: a STYLE_DAY payload that would begin the 5× card
            // waits at the queue head while a cutscene suppresses the HUD (the whitelist
            // exists for subtitles, not the numeral) or while another hero moment owns the
            // h/3 center stage. Everything queued behind it waits too — announcements stay
            // strictly ordered.
            if (dayCardWouldStart(QUEUE.peek())
                    && (CameraDirector.isHudSuppressed()
                            || !CenterStageArbiter.tryClaim(STAGE_ID, CARD_LEASE_TICKS))) {
                // defer politely; retry next tick
            } else {
                start(QUEUE.poll());
            }
        }
        tickDayCard();
        if (typewriter != null && typewriter.tick()) {
            typewriter = null;
        }
        if (sweepTicks >= 0 && ++sweepTicks > SWEEP_IN_TICKS + SWEEP_HOLD_TICKS + SWEEP_FADE_TICKS) {
            sweepTicks = -1;
        }
    }

    /** Whether dequeuing this payload would start the numeral card (mirror of {@link #beginDayCard}). */
    private static boolean dayCardWouldStart(S2CAnnouncePayload payload) {
        return S2CAnnouncePayload.STYLE_DAY.equals(payload.style()) && ClientStateCache.dayClockDay > 0;
    }

    /**
     * A15 two-way arbitration: whether the announcement presentation currently owns the
     * shared lower text band — a typewriter line is live, or the day-number card is live
     * (its typewriter line starts at the card's shrink beat, so the band is spoken for).
     * {@code CaptionRenderer} polls this before starting its next caption and defers while
     * true; its caption queue is preserved, nothing is ever dropped, only delayed.
     *
     * <p>Exception: while a cutscene suppresses the HUD, a running card is frozen AND
     * invisible (it gates itself off the cinematic frame, see {@link #render}) — it must
     * not starve cutscene subtitles, so only a live typewriter counts then.</p>
     */
    public static boolean isBandBusy() {
        if (typewriter != null) {
            return true;
        }
        return cardTicks >= 0 && !CameraDirector.isHudSuppressed();
    }

    private static void start(S2CAnnouncePayload payload) {
        lastStarted = payload;
        lastStartedClock = clock;
        if (S2CAnnouncePayload.STYLE_DAY.equals(payload.style()) && beginDayCard(payload)) {
            return; // the numeral card plays first; the line starts at its shrink beat
        }
        // No card began — free a stage claim taken for it (no-op unless we own the stage).
        CenterStageArbiter.release(STAGE_ID);
        startLine(payload);
    }

    private static void startLine(S2CAnnouncePayload payload) {
        Component title = EclipseLang.tr(payload.titleKey());
        Component subtitle = resolve(payload.subtitleKey());
        typewriter = new TypewriterLine(subtitle != null ? subtitle : title);
        sweepTitle = title;
        sweepTheme = switch (payload.style()) {
            case S2CAnnouncePayload.STYLE_BOSS -> S2CBossbarStylePayload.THEME_BOSS;
            case S2CAnnouncePayload.STYLE_DAY -> S2CBossbarStylePayload.THEME_DAY;
            default -> S2CBossbarStylePayload.THEME_GOAL; // goal + unlock share the goal skin
        };
        sweepTicks = 0;
    }

    // --- W4-CEREMONY / IDEA-09 #3: the Day-Number Moment ---

    /**
     * Starts the center-screen "DAY N" numeral card for a dequeued {@code STYLE_DAY}
     * announcement: the old day's digits odometer-roll up to the new day inside fixed
     * monospace cells (the {@code DayTimerLayer} per-cell scissor craft), the DAY word
     * settles out of {@link GlitchText} noise, one {@code ui.roulette_win} sting marks the
     * settle, then after a ~{@value #CARD_HOLD_TICKS}t hold the card shrinks toward the
     * sidebar day row while the existing typewriter line begins. Day
     * {@value #CARD_WARN_DAY}+ renders in the warn accent. Everything is client-local —
     * the day number rides {@link ClientStateCache#dayClockDay} (synced at T+0, well before
     * the DawnCeremony's T+40 announce beat). {@code reducedFx}: static card, no roll.
     */
    private static boolean beginDayCard(S2CAnnouncePayload payload) {
        int day = ClientStateCache.dayClockDay;
        if (day <= 0) {
            return false; // no synced day clock — plain line, no card
        }
        cardReduced = EclipseClientConfig.reducedFx();
        cardToDay = day;
        cardFromDay = Math.max(1, lastCardDay > 0 && lastCardDay != day ? lastCardDay : day - 1);
        lastCardDay = day;
        cardTicks = 0;
        cardStingPlayed = false;
        pendingDayLine = payload;
        return true;
    }

    private static void tickDayCard() {
        if (cardTicks < 0) {
            return;
        }
        // Renew the center-stage lease while the card lives — a cutscene freeze below may
        // outlast the initial lease (owner renewal always succeeds).
        CenterStageArbiter.tryClaim(STAGE_ID, CARD_LEASE_TICKS);
        if (CameraDirector.isHudSuppressed()) {
            return; // S-1: a flight starting mid-card freezes it — no invisible roll/sting
        }
        cardTicks++;
        int stingTick = cardReduced ? CARD_IN_TICKS
                : CARD_IN_TICKS + CARD_ROLL_DELAY_TICKS + CARD_ROLL_TICKS;
        if (!cardStingPlayed && cardTicks >= stingTick) {
            cardStingPlayed = true;
            UiSounds.rouletteWin();
        }
        // A15: the line normally begins as the card flies off — but never over an active
        // caption (two-way politeness). If a caption outlasts the card, the fully-faded
        // card state simply lingers invisibly (render alpha is 0 past the shrink) holding
        // the band until the caption ends, then the line plays — delayed, never dropped.
        if (pendingDayLine != null && cardTicks >= cardShrinkStartTick()
                && !CaptionRenderer.isBusy()) {
            startLine(pendingDayLine);
            pendingDayLine = null;
        }
        if (pendingDayLine == null && cardTicks > cardShrinkStartTick() + CARD_SHRINK_TICKS) {
            cardTicks = -1;
            CenterStageArbiter.release(STAGE_ID);
        }
    }

    private static int cardShrinkStartTick() {
        return cardReduced
                ? CARD_IN_TICKS + CARD_HOLD_TICKS + 10
                : CARD_IN_TICKS + CARD_ROLL_DELAY_TICKS + CARD_ROLL_TICKS + CARD_HOLD_TICKS;
    }

    /**
     * Resolves a subtitle key; empty → {@code null} (the typewriter falls back to the
     * title). Unlock announcements for NON-default config keys have no shipped lang line —
     * humanize the raw key instead of showing the untranslated lang key.
     */
    private static Component resolve(String key) {
        if (key.isEmpty()) {
            return null;
        }
        if (!EclipseLang.hasKey(key) && key.startsWith(UNLOCK_KEY_PREFIX)) {
            return EclipseLang.tr("announce.eclipse.unlock.key.generic",
                    key.substring(UNLOCK_KEY_PREFIX.length()).replace('_', ' '));
        }
        return EclipseLang.tr(key);
    }

    /** GUI layer body (registered above the boss overlay in {@code EclipseGuiLayers}). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.options.hideGui) {
            return;
        }
        // S-1: this layer is subtitle-whitelisted, so suppression does NOT cancel it — the
        // 5× numeral must gate itself off the cinematic frame (the frozen card resumes
        // when the flight ends; sweep/typewriter below stay live for subtitles).
        if (cardTicks >= 0 && !CameraDirector.isHudSuppressed()) {
            renderDayCard(guiGraphics, deltaTracker, minecraft);
        }
        if (sweepTicks >= 0) {
            float t = sweepTicks + deltaTracker.getGameTimeDeltaPartialTick(true);
            float progress = Mth.clamp(t / SWEEP_IN_TICKS, 0.0F, 1.0F);
            float alpha = t <= SWEEP_IN_TICKS + SWEEP_HOLD_TICKS ? 1.0F
                    : Mth.clamp(1.0F - (t - SWEEP_IN_TICKS - SWEEP_HOLD_TICKS) / SWEEP_FADE_TICKS, 0.0F, 1.0F);
            // Bright leading edge while sweeping, decaying pulse during the hold.
            float glow = t < SWEEP_IN_TICKS ? 1.0F
                    : Mth.clamp(1.0F - (t - SWEEP_IN_TICKS) / 20.0F, 0.25F, 1.0F);
            Component name = t >= SWEEP_IN_TICKS ? sweepTitle : null;
            BossbarSkin.drawThemedBar(guiGraphics, guiGraphics.guiWidth() / 2 - 91,
                    BossbarSkin.nextFreeBarY() + 12, sweepTheme, progress, glow, name, alpha);
        }
        if (typewriter != null) {
            typewriter.render(guiGraphics, guiGraphics.guiWidth() / 2,
                    guiGraphics.guiHeight() - TYPEWRITER_BOTTOM_OFFSET);
        }
    }

    /** The center-screen "DAY N" numeral card (see {@link #beginDayCard}). */
    private static void renderDayCard(GuiGraphics guiGraphics, DeltaTracker deltaTracker,
            Minecraft minecraft) {
        float t = cardTicks + (minecraft.isPaused() ? 0.0F
                : deltaTracker.getGameTimeDeltaPartialTick(true));
        float shrinkStart = cardShrinkStartTick();

        float centerX = guiGraphics.guiWidth() / 2.0F;
        float centerY = guiGraphics.guiHeight() / 3.0F;
        float scale = CARD_SCALE;
        float alpha;
        if (t < CARD_IN_TICKS) {
            float in = easeOutCubic(t / CARD_IN_TICKS);
            alpha = in;
            if (!cardReduced) {
                scale = CARD_SCALE * (0.9F + 0.1F * in);
            }
        } else if (t <= shrinkStart) {
            alpha = 1.0F;
        } else {
            // Shrink-away flight toward the sidebar day row (top-right); reducedFx just fades.
            float out = Mth.clamp((t - shrinkStart) / CARD_SHRINK_TICKS, 0.0F, 1.0F);
            alpha = 1.0F - out;
            if (!cardReduced) {
                float eased = out * out; // accelerate away
                scale = Mth.lerp(eased, CARD_SCALE, CARD_SCALE * 0.2F);
                centerX = Mth.lerp(eased, centerX, guiGraphics.guiWidth() - 40.0F);
                centerY = Mth.lerp(eased, centerY, guiGraphics.guiHeight() * 0.22F);
            }
        }
        if (alpha <= 0.01F) {
            return;
        }

        // The roll: old digits odometer up to the new day (reducedFx snaps to the new day).
        float rollT = cardReduced ? 1.0F
                : Mth.clamp((t - CARD_IN_TICKS - CARD_ROLL_DELAY_TICKS) / CARD_ROLL_TICKS, 0.0F, 1.0F);
        String toText = Integer.toString(cardToDay);
        String fromText = Integer.toString(cardFromDay);
        int cells = toText.length();
        boolean rolling = rollT > 0.0F && rollT < 1.0F && cardFromDay != cardToDay;

        int accent = cardToDay >= CARD_WARN_DAY ? EclipseUiTheme.ACCENT_DEEP : EclipseUiTheme.ACCENT;
        int color = EclipseUiTheme.withAlpha(accent, alpha);
        int shadow = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha * 0.7F);

        Font font = minecraft.font;
        float cellAbs = CARD_CELL_WIDTH * scale;
        float digitHeightAbs = 9.0F * scale;
        float baseX = centerX - cells * cellAbs / 2.0F;
        float topY = centerY - digitHeightAbs / 2.0F;

        for (int i = 0; i < cells; i++) {
            // Right-align the from-number into the to-number's cells (blank-pads a 9→10 grow).
            int fromIndex = i - (cells - fromText.length());
            String fromGlyph = fromIndex >= 0 ? String.valueOf(fromText.charAt(fromIndex)) : "";
            String toGlyph = String.valueOf(toText.charAt(i));
            float glyphX = baseX + i * cellAbs;
            if (rolling && !fromGlyph.equals(toGlyph)) {
                // DayTimerLayer craft: per-cell scissor, previous slides up-out, new rolls in.
                float progress = easeOutCubic(rollT);
                float currentOffset = (1.0F - progress) * CARD_ROLL_HEIGHT;
                float previousOffset = currentOffset - CARD_ROLL_HEIGHT;
                guiGraphics.enableScissor(Mth.floor(glyphX), Mth.floor(topY - scale),
                        Mth.ceil(glyphX + cellAbs), Mth.ceil(topY + digitHeightAbs + scale));
                drawCardGlyph(guiGraphics, font, glyphX, topY, scale, fromGlyph, previousOffset,
                        color, shadow);
                drawCardGlyph(guiGraphics, font, glyphX, topY, scale, toGlyph, currentOffset,
                        color, shadow);
                guiGraphics.disableScissor();
            } else {
                drawCardGlyph(guiGraphics, font, glyphX, topY, scale,
                        rollT >= 1.0F || cardFromDay == cardToDay ? toGlyph : fromGlyph, 0.0F,
                        color, shadow);
            }
        }

        // DAY word above the numeral, settling out of GlitchText noise as the digits roll.
        String word = EclipseLang.trString("gui.eclipse.announce.day_card");
        float settle = cardReduced ? 1.0F : Mth.clamp(
                (t - 2.0F) / (CARD_IN_TICKS + CARD_ROLL_DELAY_TICKS + CARD_ROLL_TICKS - 2.0F),
                0.0F, 1.0F);
        int settled = Math.min(word.length(), Math.round(word.length() * settle));
        String settledPart = word.substring(0, settled);
        String scrambled = settled < word.length()
                ? GlitchText.scramble(word.length() - settled, cardToDay * 31 + 7)
                : "";
        float wordScale = scale * CARD_WORD_SCALE;
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, topY - 9.0F * wordScale - 4.0F, 0.0F);
        guiGraphics.pose().scale(wordScale, wordScale, 1.0F);
        int wordX = -font.width(settledPart + scrambled) / 2;
        guiGraphics.drawString(font, settledPart, wordX, 0,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha), false);
        if (!scrambled.isEmpty()) {
            guiGraphics.drawString(font, scrambled, wordX + font.width(settledPart), 0,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha), false);
        }
        guiGraphics.pose().popPose();
    }

    /** One monospace numeral glyph, centered in its cell, deep-purple drop shadow for depth. */
    private static void drawCardGlyph(GuiGraphics guiGraphics, Font font, float cellX, float topY,
            float scale, String glyph, float yOffset, int color, int shadow) {
        if (glyph.isEmpty()) {
            return;
        }
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(cellX, topY, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        int x = (CARD_CELL_WIDTH - font.width(glyph)) / 2;
        int y = Math.round(yOffset);
        guiGraphics.drawString(font, glyph, x + 1, y + 1, shadow, false);
        guiGraphics.drawString(font, glyph, x, y, color, false);
        guiGraphics.pose().popPose();
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
