package dev.projecteclipse.eclipse.client.awards;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.hud.AnnouncementOverlay;
import dev.projecteclipse.eclipse.client.hud.CenterStageArbiter;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.LetterboxLayer;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.network.paper.MorningPaperPayloads;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;

/**
 * WAVE6 (F-106 C) — C1 "Today's Decrees" reveal + C5 "Morning Paper" recap card.
 *
 * <p><b>C1 (rollover mode).</b> When {@link ClientStateCache#dayClockDay} flips mid-session
 * and the NEXT quest-state sync for that day lands ({@code questDay} catches up), the new
 * day's decrees present as a center card: main decrees typewrite in one by one, then the
 * personal draws flip in with a {@code ui.page_turn} each. The old
 * {@code quest.eclipse.assigned} actionbar in {@code QuestEngine.ensurePlayer} is degraded
 * to the login/fallback path — at rollover THIS card is the announcement.</p>
 *
 * <p><b>C5 (paper mode).</b> A login AFTER a rollover means the player slept through the
 * whole morning ceremony; the server sends the compact
 * {@link MorningPaperPayloads.S2CMorningPaperPayload} instead of the full reveal payload
 * (which the late-join grace would have swallowed anyway). After a short settle delay the
 * same card presents as "the morning paper": day title, yesterday's honours (winner rows,
 * UUID-anonymous — YOU/glitch markers only) and today's decrees read from the quest cache
 * that the login sync already filled.</p>
 *
 * <p><b>Craft rules ({@code AwardsOverlay} pattern):</b> self-subscribed above-all GUI
 * layer, never a Screen — input stays with gameplay ({@code EclipseGuiLayers} stays
 * FROZEN). Start is gated on the cutscene letterbox ({@link LetterboxLayer#barPx} read-only
 * check), on {@link AnnouncementOverlay#isIdle()} (the C2 collision gate — the day-number
 * card/sweep finishes first) and on the {@link CenterStageArbiter}. {@code AwardsOverlay}
 * in turn waits on {@link #liveOrArmed()}, so the morning always reads day card → decrees →
 * roulette; the dependency chain is acyclic (this class never consults the roulette).
 * Sneak skips to the finished list; {@code reducedFx} shows the finished list immediately
 * with a longer hold; F1 hides the layer while state keeps advancing; pause freezes.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DecreesCard {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "decrees_card");
    /** {@link CenterStageArbiter} claim id. */
    private static final String STAGE_ID = "decrees_card";

    // --- timing (game ticks) ---
    /** Mirrors {@code AwardsOverlay}: syncs arriving this early are login replays, not news. */
    private static final int LATE_JOIN_GRACE_TICKS = 100;
    /**
     * How long an armed day-flip waits for its quest-state sync before giving up (quest
     * engine disabled, empty day). While armed, {@link #liveOrArmed()} keeps the roulette
     * queued — this cap guarantees the wait can never deadlock the morning.
     */
    private static final int ARM_TIMEOUT_TICKS = 200;
    /** Paper settle delay: let the join fade/chat burst pass before the recap presents. */
    private static final int PAPER_SETTLE_TICKS = 160;
    private static final int TYPE_CHARS_PER_TICK = 2;
    /** Small breath between finished line and the next line starting to type. */
    private static final int LINE_PAUSE_TICKS = 6;
    /** One personal-draw flip every this many ticks. */
    private static final int FLIP_INTERVAL_TICKS = 8;
    private static final int HOLD_TICKS = 90;
    private static final int HOLD_TICKS_REDUCED_FX = 150;
    private static final int FADE_TICKS = 14;
    /** Failsafe cap on one presentation (matches the arbiter-lease idiom). */
    private static final int SHOW_HARD_CAP_TICKS = 20 * 45;
    private static final int QUEUE_LIMIT = 2;
    private static final int PANEL_WIDTH_MAX = 320;
    private static final int MAX_LINES_PER_SECTION = 6;

    private enum Mode { DECREES, PAPER }

    private enum Phase { IDLE, TYPE, FLIP, HOLD, FADE }

    /**
     * One prepared card. {@code typeLines} typewrite sequentially; {@code flipLines} flip
     * in afterwards under {@code flipHeader}. {@code subtitle} is the paper's day title
     * ({@code ""} in decrees mode).
     */
    private record Card(Mode mode, int day, String header, String subtitle,
            String typeHeader, List<String> typeLines, String flipHeader, List<String> flipLines) {}

    // Client tick thread only.
    private static final ArrayDeque<Card> QUEUE = new ArrayDeque<>();
    /** Day-clock days already presented (or deliberately skipped) this session. */
    private static final Set<Integer> HANDLED_DAYS = new HashSet<>();

    private static Phase phase = Phase.IDLE;
    private static Card card;
    private static int phaseTicks;
    private static int showTicks;
    private static int typeLineIndex;
    private static int typeCharsShown;
    private static int linePauseTicks;
    private static int flipShown;
    private static boolean sneakWasDown;

    private static int ticksInWorld;
    private static int lastDayClockDay = Integer.MIN_VALUE;
    /** Armed day-flip waiting for its quest sync ({@code 0} = not armed). */
    private static int pendingDay;
    private static int armTicks;
    private static MorningPaperPayloads.S2CMorningPaperPayload pendingPaper;
    private static int paperDelayTicks;

    static {
        // C5 transport seam: the registrar stays dist-neutral; this client class installs
        // the consumer at class-load (@EventBusSubscriber scan happens during mod construct).
        MorningPaperPayloads.setClientPaperHandler(DecreesCard::handlePaper);
    }

    private DecreesCard() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAboveAll(LAYER_ID, DecreesCard::render);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            hardReset();
            return;
        }
        ticksInWorld++;
        watchDayClock();
        tickPaperDelay();
        if (phase == Phase.IDLE) {
            maybeStart();
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze mid-presentation; queue and phase state stay intact
        }
        if (++showTicks > SHOW_HARD_CAP_TICKS) {
            finishShow();
            return;
        }
        handleSneakSkip(minecraft);
        advance();
    }

    /**
     * Whether a decrees/paper presentation is running OR armed (queued, waiting for the
     * quest sync of a flipped day, or holding a settling morning paper).
     * {@code AwardsOverlay.maybeStart} consults this so the roulette always follows the
     * decrees; the armed states are hard-capped ({@link #ARM_TIMEOUT_TICKS},
     * {@link #PAPER_SETTLE_TICKS}), so the roulette can never be starved.
     */
    public static boolean liveOrArmed() {
        return phase != Phase.IDLE || !QUEUE.isEmpty() || pendingDay > 0 || pendingPaper != null;
    }

    // --- triggers ---

    /** C1: arms on a mid-session {@code dayClockDay} flip, then waits for the quest sync. */
    private static void watchDayClock() {
        int day = ClientStateCache.dayClockDay;
        if (lastDayClockDay == Integer.MIN_VALUE) {
            lastDayClockDay = day; // first observation of the session — login sync, not news
        } else if (day != lastDayClockDay) {
            lastDayClockDay = day;
            if (ticksInWorld > LATE_JOIN_GRACE_TICKS && !HANDLED_DAYS.contains(day)) {
                pendingDay = day;
                armTicks = 0;
            }
        }
        if (pendingDay <= 0) {
            return;
        }
        if (ClientStateCache.questDay == pendingDay) {
            buildDecrees(pendingDay);
            pendingDay = 0;
        } else if (++armTicks > ARM_TIMEOUT_TICKS) {
            HANDLED_DAYS.add(pendingDay); // quest engine silent for this day — no card
            pendingDay = 0;
        }
    }

    /** {@link MorningPaperPayloads} client consumer (main thread). */
    private static void handlePaper(MorningPaperPayloads.S2CMorningPaperPayload payload) {
        if (payload.awardsDay() <= 0) {
            return;
        }
        pendingPaper = payload;
        paperDelayTicks = PAPER_SETTLE_TICKS;
    }

    private static void tickPaperDelay() {
        if (pendingPaper == null) {
            return;
        }
        if (--paperDelayTicks > 0) {
            return;
        }
        buildPaper(pendingPaper);
        pendingPaper = null;
    }

    private static void buildDecrees(int day) {
        HANDLED_DAYS.add(day);
        boolean german = EclipseLang.locale().startsWith("de");
        List<String> mains = new ArrayList<>();
        List<String> personals = new ArrayList<>();
        for (S2CQuestStatePayload.QuestEntry entry : ClientStateCache.questEntries) {
            if (entry.kind() == 0 && mains.size() < MAX_LINES_PER_SECTION) {
                mains.add(pickLocale(entry.textEn(), entry.textDe(), german));
            } else if (entry.kind() == 2 && personals.size() < MAX_LINES_PER_SECTION) {
                personals.add(pickLocale(entry.textEn(), entry.textDe(), german));
            }
        }
        if (mains.isEmpty() && personals.isEmpty()) {
            return; // nothing to decree — the day sweep alone carries the morning
        }
        offer(new Card(Mode.DECREES, day,
                EclipseLang.trString("gui.eclipse.decrees.header", day), "",
                "", mains,
                personals.isEmpty() ? "" : EclipseLang.trString("gui.eclipse.decrees.personal"),
                personals));
    }

    private static void buildPaper(MorningPaperPayloads.S2CMorningPaperPayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        UUID localId = minecraft.player != null ? minecraft.player.getUUID() : null;
        boolean german = EclipseLang.locale().startsWith("de");
        List<String> honours = new ArrayList<>();
        for (MorningPaperPayloads.WinnerRow row : payload.winners()) {
            if (honours.size() >= MAX_LINES_PER_SECTION) {
                break;
            }
            String title = pickLocale(row.titleEn(), row.titleDe(), german);
            String marker = localId != null && row.winners().contains(localId)
                    ? EclipseLang.trString("gui.eclipse.awards.you")
                    : GlitchText.unknown(payload.awardsDay() * 31 + honours.size());
            honours.add(title + " — " + marker);
        }
        // Today's decrees ride the quest cache the login sync already filled — the payload
        // stays compact (see MorningPaperPayloads javadoc for the C5 transport decision).
        List<String> mains = new ArrayList<>();
        for (S2CQuestStatePayload.QuestEntry entry : ClientStateCache.questEntries) {
            if (entry.kind() == 0 && mains.size() < MAX_LINES_PER_SECTION) {
                mains.add(pickLocale(entry.textEn(), entry.textDe(), german));
            }
        }
        if (honours.isEmpty() && mains.isEmpty()) {
            return;
        }
        // Day titles arrive either as a receiver-baked literal or as a generic lang key.
        String subtitle = EclipseLang.hasKey(payload.dayTitle())
                ? EclipseLang.trString(payload.dayTitle())
                : payload.dayTitle();
        offer(new Card(Mode.PAPER, payload.day(),
                EclipseLang.trString("gui.eclipse.paper.header", payload.day()), subtitle,
                honours.isEmpty() ? "" : EclipseLang.trString("gui.eclipse.paper.honors", payload.awardsDay()),
                honours,
                mains.isEmpty() ? "" : EclipseLang.trString("gui.eclipse.paper.decrees"),
                mains));
    }

    private static void offer(Card built) {
        if (QUEUE.size() < QUEUE_LIMIT) {
            QUEUE.add(built);
        }
    }

    private static String pickLocale(String en, String de, boolean german) {
        String primary = german ? de : en;
        String fallback = german ? en : de;
        return primary == null || primary.isBlank() ? (fallback == null ? "" : fallback) : primary;
    }

    // --- phase machine ---

    private static void maybeStart() {
        if (QUEUE.isEmpty()) {
            return;
        }
        if (LetterboxLayer.barPx(1000) > 0) {
            return; // hold behind an active cutscene letterbox (read-only check)
        }
        if (!AnnouncementOverlay.isIdle()) {
            return; // C2 collision gate: the day card/sweep presentation finishes first
        }
        if (!CenterStageArbiter.tryClaim(STAGE_ID, SHOW_HARD_CAP_TICKS)) {
            return; // another hero moment owns the center band — retry next tick
        }
        card = QUEUE.poll();
        showTicks = 0;
        typeLineIndex = 0;
        typeCharsShown = 0;
        linePauseTicks = 0;
        flipShown = 0;
        sneakWasDown = true; // require a fresh sneak press before the first skip
        UiSounds.pageTurn(0.9F); // the one open cue (kept in reducedFx — it IS the arrival)
        if (card.mode() == Mode.DECREES) {
            EclipseMod.LOGGER.debug("[w6c-decrees] day={} mains={} personal={}", card.day(),
                    card.typeLines().size(), card.flipLines().size());
        }
        if (EclipseClientConfig.reducedFx()) {
            revealAll();
            setPhase(Phase.HOLD);
            return;
        }
        setPhase(card.typeLines().isEmpty() ? Phase.FLIP : Phase.TYPE);
    }

    private static void advance() {
        switch (phase) {
            case TYPE -> {
                if (linePauseTicks > 0) {
                    linePauseTicks--;
                    return;
                }
                String line = card.typeLines().get(typeLineIndex);
                if (typeCharsShown < line.length()) {
                    typeCharsShown = Math.min(line.length(), typeCharsShown + TYPE_CHARS_PER_TICK);
                    if (typeCharsShown % 4 == 0 || typeCharsShown == line.length()) {
                        UiSounds.typewriter(0.9F + 0.2F * (float) Math.random());
                    }
                } else if (typeLineIndex + 1 < card.typeLines().size()) {
                    typeLineIndex++;
                    typeCharsShown = 0;
                    linePauseTicks = LINE_PAUSE_TICKS;
                } else {
                    setPhase(card.flipLines().isEmpty() ? Phase.HOLD : Phase.FLIP);
                }
            }
            case FLIP -> {
                if (flipShown >= card.flipLines().size()) {
                    setPhase(Phase.HOLD);
                    return;
                }
                if (++phaseTicks >= FLIP_INTERVAL_TICKS) {
                    phaseTicks = 0;
                    flipShown++;
                    UiSounds.pageTurn(1.05F);
                }
            }
            case HOLD -> {
                if (++phaseTicks >= holdTicks()) {
                    setPhase(Phase.FADE);
                }
            }
            case FADE -> {
                if (++phaseTicks >= FADE_TICKS) {
                    finishShow();
                }
            }
            default -> {}
        }
    }

    /** Sneak edge (no screen open): skip to the finished list, then dismiss — C1 spec. */
    private static void handleSneakSkip(Minecraft minecraft) {
        boolean down = minecraft.options.keyShift.isDown();
        boolean pressed = down && !sneakWasDown;
        sneakWasDown = down;
        if (!pressed || minecraft.screen != null) {
            return;
        }
        switch (phase) {
            case TYPE, FLIP -> {
                revealAll();
                setPhase(Phase.HOLD);
            }
            case HOLD -> setPhase(Phase.FADE);
            default -> {}
        }
    }

    private static void revealAll() {
        typeLineIndex = Math.max(0, card.typeLines().size() - 1);
        typeCharsShown = card.typeLines().isEmpty()
                ? 0 : card.typeLines().getLast().length();
        flipShown = card.flipLines().size();
    }

    private static void setPhase(Phase next) {
        phase = next;
        phaseTicks = 0;
    }

    private static void finishShow() {
        phase = Phase.IDLE;
        phaseTicks = 0;
        showTicks = 0;
        card = null;
        CenterStageArbiter.release(STAGE_ID);
    }

    private static void hardReset() {
        finishShow();
        QUEUE.clear();
        HANDLED_DAYS.clear();
        ticksInWorld = 0;
        lastDayClockDay = Integer.MIN_VALUE;
        pendingDay = 0;
        armTicks = 0;
        pendingPaper = null;
        paperDelayTicks = 0;
    }

    private static int holdTicks() {
        return EclipseClientConfig.reducedFx() ? HOLD_TICKS_REDUCED_FX : HOLD_TICKS;
    }

    // --- rendering ---

    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (phase == Phase.IDLE || card == null || minecraft.options.hideGui) {
            return; // F1 hides; state keeps advancing so the card never stalls behind it
        }
        float partialTick = minecraft.isPaused() ? 0.0F
                : deltaTracker.getGameTimeDeltaPartialTick(true);
        float alpha = phase == Phase.FADE
                ? Mth.clamp(1.0F - (phaseTicks + partialTick) / FADE_TICKS, 0.0F, 1.0F)
                : 1.0F;
        if (alpha <= 0.01F) {
            return;
        }
        Font font = minecraft.font;
        int guiWidth = guiGraphics.guiWidth();
        int guiHeight = guiGraphics.guiHeight();
        int panelWidth = Math.min(PANEL_WIDTH_MAX, guiWidth - 40);
        int innerWidth = panelWidth - 2 * EclipseUiTheme.PAD;

        boolean subtitlePresent = !card.subtitle().isEmpty();
        boolean typeHeaderPresent = !card.typeHeader().isEmpty();
        boolean flipHeaderPresent = !card.flipHeader().isEmpty();
        int panelHeight = 2 * EclipseUiTheme.PAD
                + 12 + EclipseUiTheme.GAP // header + hairline
                + (subtitlePresent ? EclipseUiTheme.ROW : 0)
                + (typeHeaderPresent ? EclipseUiTheme.ROW : 0)
                + card.typeLines().size() * EclipseUiTheme.ROW
                + (card.flipLines().isEmpty() ? 0
                        : EclipseUiTheme.GAP + (flipHeaderPresent ? EclipseUiTheme.ROW : 0)
                                + card.flipLines().size() * EclipseUiTheme.ROW)
                + EclipseUiTheme.GAP + 10; // skip hint
        int x = (guiWidth - panelWidth) / 2;
        int y = Math.max(16, guiHeight / 4 - panelHeight / 3);

        EclipseUiTheme.drawPanel(guiGraphics, x, y, panelWidth, panelHeight, alpha);
        int textX = x + EclipseUiTheme.PAD;
        int textY = EclipseUiTheme.drawHeader(guiGraphics, font,
                net.minecraft.network.chat.Component.literal(card.header()),
                textX, y + EclipseUiTheme.PAD, innerWidth, alpha);
        if (subtitlePresent) {
            guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, card.subtitle(), innerWidth),
                    textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            textY += EclipseUiTheme.ROW;
        }
        if (typeHeaderPresent) {
            guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, card.typeHeader(), innerWidth),
                    textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha));
            textY += EclipseUiTheme.ROW;
        }
        for (int i = 0; i < card.typeLines().size(); i++) {
            String line = card.typeLines().get(i);
            String shown = visibleTypePortion(i, line);
            if (!shown.isEmpty()) {
                guiGraphics.drawString(font,
                        EclipseUiTheme.ellipsize(font, "\u2022 " + shown, innerWidth),
                        textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
            }
            textY += EclipseUiTheme.ROW;
        }
        if (!card.flipLines().isEmpty()) {
            textY += EclipseUiTheme.GAP;
            if (flipHeaderPresent) {
                guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, card.flipHeader(), innerWidth),
                        textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha));
                textY += EclipseUiTheme.ROW;
            }
            int visibleFlips = phase == Phase.TYPE ? 0 : flipShown;
            for (int i = 0; i < card.flipLines().size(); i++) {
                if (i < visibleFlips) {
                    guiGraphics.drawString(font,
                            EclipseUiTheme.ellipsize(font, "\u25B8 " + card.flipLines().get(i), innerWidth),
                            textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
                }
                textY += EclipseUiTheme.ROW;
            }
        }
        String hint = EclipseLang.trString("gui.eclipse.awards.skip_hint");
        guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, hint, innerWidth),
                textX, y + panelHeight - EclipseUiTheme.PAD - 2,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, 0.8F * alpha));
    }

    /** The typed-so-far portion of one main line (full once its index has passed). */
    private static String visibleTypePortion(int index, String line) {
        if (phase != Phase.TYPE || index < typeLineIndex) {
            return line;
        }
        if (index > typeLineIndex) {
            return "";
        }
        return line.substring(0, Math.min(typeCharsShown, line.length()));
    }
}
