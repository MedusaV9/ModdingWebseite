package dev.projecteclipse.eclipse.client.awards;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.mojang.math.Axis;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.LetterboxLayer;
import dev.projecteclipse.eclipse.network.S2CAwardRevealPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Daily-awards head-roulette overlay (P3-W10, {@code docs/plans_v3/P3_ui.md} §3.10): plays
 * the {@code S2CAwardRevealPayload} reveal as N sequential roulette cards — spinning head
 * strip with {@code ui.roulette_tick} per marker pass, exact deterministic landing on the
 * winner ({@link RouletteStrip}), flare + pop on the winner head, typewritten stat line,
 * purple per-character glitch-settle reward line with {@code ui.roulette_win}, 2 s hold,
 * crossfade to the next category, then a compact summary card.
 *
 * <p><b>Not a Screen.</b> A self-registered above-all GUI layer: gameplay continues behind
 * the veil and input is never captured. The single deliberate exception: while the show is
 * running (pre-summary), opening the vanilla pause screen from gameplay — i.e. pressing
 * ESC — is cancelled once and skips to the summary instead (task spec "ESC skips to
 * summary"); this reinterpretation is bounded by the show's own duration. Sneak
 * fast-forwards one reveal (§3.10 accessibility). {@code F1} hides the layer (state keeps
 * advancing), pause freezes it, and the cutscene letterbox both delays show start (queue)
 * and suppresses the layer mid-show via the existing whitelist mechanism.</p>
 *
 * <p><b>Trigger path (no hub edits).</b> {@code EclipsePayloads.handleAwardReveal} already
 * caches the payload into {@link ClientStateCache#awardRevealDay}/{@code awardCategories};
 * this class polls those fields each client tick and reacts to the cached list instance
 * changing. Shows are deduped per day (re-sends of the same reveal — login replay, the P2
 * cinematic-seam re-broadcast, payload spam — collapse into one show), queued up to
 * {@value #QUEUE_LIMIT} behind an active show/cutscene, and suppressed entirely when the
 * payload arrives within the first {@value #LATE_JOIN_GRACE_TICKS} ticks of joining a
 * world (late joins get no replay by design).</p>
 *
 * <p><b>Anonymity.</b> The payload carries UUIDs only; heads all wear the uniform eclipsed
 * skin and are labelled with {@link GlitchText} shimmer — the only real name ever shown is
 * the localized "YOU"/"DU" when the local player is among the winners (client-local
 * knowledge, no leak). Ties ({@code winners.size() > 1} per {@code AwardMath.resolve})
 * land on the first winner and fan the co-winner heads out beside it with a localized
 * "shared" note. All server strings (bilingual literals) render verbatim; the en/de pick
 * follows {@link EclipseLang#locale()}.</p>
 *
 * <p>{@code reducedFx}: no spin, no flare — each category shows as a pre-landed reveal
 * card with instant text and a longer read hold.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AwardsOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "awards_roulette");

    // --- timing (game ticks) ---
    private static final int INTRO_TICKS = 18;
    /** Spin length — inside the task's 4–6 s deceleration window. */
    private static final int SPIN_DURATION_TICKS = 80;
    private static final int LAND_TICKS = 10;
    private static final int STAT_CHARS_PER_TICK = 2;
    private static final int REWARD_SETTLE_TICKS = 18;
    private static final int HOLD_TICKS = 40;
    private static final int HOLD_TICKS_REDUCED_FX = 70;
    private static final int FADE_TICKS = 6;
    private static final int SUMMARY_HOLD_TICKS = 90;
    private static final int SUMMARY_FADE_TICKS = 14;
    /** Failsafe: a show can never outlive this many ticks (~75 s), whatever happens. */
    private static final int SHOW_HARD_CAP_TICKS = 1500;

    // --- queue / replay policy ---
    private static final int QUEUE_LIMIT = 3;
    private static final int MAX_REVEALS = 5;
    /** Payloads cached within this many ticks of world join are login replays — never played. */
    private static final int LATE_JOIN_GRACE_TICKS = 100;

    /** Flare ray palette mirroring {@code quasar/emitters/roulette_flare.json} (warm → purple). */
    private static final int[] FLARE_COLORS = {0xFFF3C4, 0xFFD166, 0xC77DFF, 0x7B2CBF};

    /** Podium-moment flourish over the local winner (client-local; IDEA-11 #2). */
    private static final ResourceLocation PODIUM_BURST_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "unlock_burst");

    private enum Phase { IDLE, INTRO, SPIN, LAND, STAT, REWARD, HOLD, FADE, SUMMARY, DONE_FADE }

    /** One parsed category reveal; server strings verbatim, title/stat split on the first newline. */
    private record Reveal(String title, String statLine, String rewardLine, List<UUID> winners,
            boolean localWon, boolean tie, RouletteStrip strip, int salt) {}

    private record PendingShow(int day, List<S2CAwardRevealPayload.Category> categories) {}

    // Client thread only.
    private static final ArrayDeque<PendingShow> QUEUE = new ArrayDeque<>();
    private static final Set<Integer> HANDLED_DAYS = new HashSet<>();
    private static List<S2CAwardRevealPayload.Category> lastSeenCategories = null;
    private static int ticksInWorld;

    private static Phase phase = Phase.IDLE;
    private static int phaseTicks;
    private static int showTicks;
    private static int showDay;
    private static List<Reveal> reveals = List.of();
    private static int revealIndex;
    private static int statRevealed;
    /** Ticks since the strip landed (drives pop/flare through STAT/REWARD/HOLD). */
    private static int landAge;
    private static boolean sneakWasDown;
    /** One cancelled pause opening per show — see {@link #onScreenOpening} (M-5). */
    private static boolean escSkipUsed;

    private AwardsOverlay() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAboveAll(LAYER_ID, AwardsOverlay::render);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            hardReset();
            return;
        }
        ticksInWorld++;
        pollPayload();
        if (phase == Phase.IDLE) {
            maybeStart(minecraft);
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze mid-animation; the queue and phase state stay intact
        }
        if (++showTicks > SHOW_HARD_CAP_TICKS) {
            finishShow();
            return;
        }
        handleSneakSkip(minecraft);
        advance();
    }

    /**
     * ESC-to-summary: while the show is running, an ESC pause-menu opening from gameplay is
     * reinterpreted once as "skip to summary" (exact vanilla {@link PauseScreen} only, and
     * only when no screen was open — menus opened from other screens are untouched).
     * At most ONE pause opening is ever cancelled per show ({@code escSkipUsed}, M-5): a
     * player who genuinely wants the menu gets it on the next press, whatever phase the
     * show is in.
     */
    @SubscribeEvent
    static void onScreenOpening(ScreenEvent.Opening event) {
        if (phase == Phase.IDLE || phase == Phase.SUMMARY || phase == Phase.DONE_FADE
                || escSkipUsed) {
            return;
        }
        Screen opening = event.getNewScreen();
        if (opening != null && opening.getClass() == PauseScreen.class
                && Minecraft.getInstance().screen == null) {
            escSkipUsed = true;
            setPhase(Phase.SUMMARY);
            event.setCanceled(true);
        }
    }

    // --- trigger / queue ---

    /** Reacts to {@code EclipsePayloads.handleAwardReveal} writing the shared client cache. */
    private static void pollPayload() {
        List<S2CAwardRevealPayload.Category> categories = ClientStateCache.awardCategories;
        if (categories == lastSeenCategories) {
            return;
        }
        lastSeenCategories = categories;
        int day = ClientStateCache.awardRevealDay;
        if (day <= 0 || categories.isEmpty() || HANDLED_DAYS.contains(day)) {
            return;
        }
        if (ticksInWorld <= LATE_JOIN_GRACE_TICKS) {
            HANDLED_DAYS.add(day); // login replay of an old reveal — late join shows nothing
            return;
        }
        // Mark handled BEFORE the capacity check: a payload dropped at a full queue must
        // not replay the same day when the server re-sends after the queue drains (M-4).
        HANDLED_DAYS.add(day); // dedupes the P2 cinematic-seam re-broadcast + payload spam
        if (QUEUE.size() >= QUEUE_LIMIT) {
            return;
        }
        QUEUE.add(new PendingShow(day, categories));
    }

    private static void maybeStart(Minecraft minecraft) {
        if (QUEUE.isEmpty() || LetterboxLayer.barPx(1000) > 0) {
            return; // hold behind an active cutscene letterbox
        }
        PendingShow pending = QUEUE.poll();
        UUID localId = minecraft.player != null ? minecraft.player.getUUID() : null;
        List<Reveal> built = buildReveals(pending.day(), pending.categories(), localId);
        if (built.isEmpty()) {
            return;
        }
        showDay = pending.day();
        reveals = built;
        revealIndex = 0;
        showTicks = 0;
        sneakWasDown = true; // require a fresh sneak press before the first skip
        escSkipUsed = false;
        setPhase(Phase.INTRO);
    }

    private static List<Reveal> buildReveals(int day, List<S2CAwardRevealPayload.Category> categories,
            UUID localId) {
        boolean german = EclipseLang.locale().startsWith("de");
        boolean reducedFx = EclipseClientConfig.reducedFx();
        List<Reveal> built = new ArrayList<>();
        for (S2CAwardRevealPayload.Category category : categories) {
            if (built.size() >= MAX_REVEALS) {
                break;
            }
            if (category.candidates().isEmpty() || category.winners().isEmpty()) {
                continue;
            }
            // P4-B6 packs "title\nstatLine" into the frozen payload's title fields — split
            // defensively (no newline = title only, empty stat row).
            String raw = pickLocale(category.titleEn(), category.titleDe(), german);
            int newline = raw.indexOf('\n');
            String title = newline >= 0 ? raw.substring(0, newline) : raw;
            String stat = newline >= 0 ? raw.substring(newline + 1).replace('\n', ' ') : "";
            String reward = pickLocale(category.rewardTextEn(), category.rewardTextDe(), german);
            List<UUID> candidates = new ArrayList<>(category.candidates().size());
            for (S2CAwardRevealPayload.Candidate candidate : category.candidates()) {
                candidates.add(candidate.uuid());
            }
            List<UUID> winners = category.winners();
            long seed = day * 1_000_003L + category.id().hashCode();
            RouletteStrip strip = new RouletteStrip(candidates, winners.getFirst(), seed,
                    reducedFx ? 0 : SPIN_DURATION_TICKS);
            built.add(new Reveal(title, stat, reward, winners,
                    localId != null && winners.contains(localId), winners.size() > 1, strip,
                    day * 100 + built.size()));
        }
        return built;
    }

    private static String pickLocale(String en, String de, boolean german) {
        String primary = german ? de : en;
        String fallback = german ? en : de;
        return primary == null || primary.isBlank() ? (fallback == null ? "" : fallback) : primary;
    }

    // --- phase machine ---

    private static void advance() {
        Reveal reveal = currentReveal();
        if (landAgeRunning()) {
            landAge++;
        }
        switch (phase) {
            case INTRO -> {
                if (++phaseTicks >= INTRO_TICKS) {
                    startCategory(0);
                }
            }
            case SPIN -> {
                int passes = reveal.strip().tick();
                if (passes > 0) {
                    // At most one tick blip per game tick even while several heads blur past.
                    UiSounds.rouletteTick(RouletteStrip.tickPitch(reveal.strip().progress()));
                }
                if (reveal.strip().done()) {
                    landAge = 0;
                    if (reveal.localWon()) {
                        podiumBurst();
                    }
                    setPhase(Phase.LAND);
                }
            }
            case LAND -> {
                if (++phaseTicks >= LAND_TICKS) {
                    statRevealed = EclipseClientConfig.reducedFx() ? reveal.statLine().length() : 0;
                    setPhase(Phase.STAT);
                }
            }
            case STAT -> {
                if (statRevealed < reveal.statLine().length()) {
                    statRevealed = Math.min(reveal.statLine().length(),
                            statRevealed + STAT_CHARS_PER_TICK);
                    if (statRevealed % 4 == 0 || statRevealed == reveal.statLine().length()) {
                        UiSounds.typewriter(0.9F + 0.2F * (float) Math.random());
                    }
                } else {
                    UiSounds.rouletteWin();
                    if (EclipseClientConfig.reducedFx()) {
                        setPhase(Phase.HOLD);
                    } else {
                        setPhase(Phase.REWARD);
                    }
                }
            }
            case REWARD -> {
                if (++phaseTicks >= REWARD_SETTLE_TICKS) {
                    setPhase(Phase.HOLD);
                }
            }
            case HOLD -> {
                if (++phaseTicks >= holdTicks()) {
                    setPhase(Phase.FADE);
                }
            }
            case FADE -> {
                if (++phaseTicks >= FADE_TICKS) {
                    if (revealIndex + 1 < reveals.size()) {
                        startCategory(revealIndex + 1);
                    } else {
                        setPhase(Phase.SUMMARY);
                    }
                }
            }
            case SUMMARY -> {
                if (++phaseTicks >= SUMMARY_HOLD_TICKS) {
                    setPhase(Phase.DONE_FADE);
                }
            }
            case DONE_FADE -> {
                if (++phaseTicks >= SUMMARY_FADE_TICKS) {
                    finishShow();
                }
            }
            default -> {}
        }
    }

    /**
     * W4-CEREMONY / IDEA-11 #2 — PODIUM MOMENT: the instant the strip lands on "YOU" the
     * celebration escapes the UI. A CLIENT-LOCAL {@code eclipse:unlock_burst} Quasar flourish
     * plus a small vanilla firework ring pop ~2.4 blocks above the local player — visible in
     * the world behind the 0.85-alpha veil. Nothing is broadcast, so co-players learn
     * nothing (the reveal's UUID-only anonymity design stays intact); the award sting layers
     * at land instead of waiting for the stat-line end. {@code reducedFx} keeps only the
     * sting; ties included ({@code localWon} covers shared wins).
     */
    private static void podiumBurst() {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null) {
            return;
        }
        minecraft.getSoundManager().play(
                SimpleSoundInstance.forUI(EclipseSounds.AWARD_STING.get(), 1.0F, 0.85F));
        if (EclipseClientConfig.reducedFx()) {
            return;
        }
        Vec3 top = player.position().add(0.0D, 2.4D, 0.0D);
        QuasarSpawner.spawnOrFallback(PODIUM_BURST_EMITTER, top);
        for (int i = 0; i < 8; i++) {
            double angle = Math.PI * 2.0D * i / 8.0D;
            double dx = Math.cos(angle);
            double dz = Math.sin(angle);
            player.level().addParticle(ParticleTypes.FIREWORK,
                    top.x + dx * 0.6D, top.y, top.z + dz * 0.6D,
                    dx * 0.18D, 0.05D, dz * 0.18D);
        }
    }

    /** Sneak edge (no screen open) fast-forwards the current reveal — §3.10 accessibility. */
    private static void handleSneakSkip(Minecraft minecraft) {
        boolean down = minecraft.options.keyShift.isDown();
        boolean pressed = down && !sneakWasDown;
        sneakWasDown = down;
        if (!pressed || minecraft.screen != null) {
            return;
        }
        switch (phase) {
            case SPIN, LAND, STAT, REWARD, HOLD -> setPhase(Phase.FADE);
            case SUMMARY -> setPhase(Phase.DONE_FADE);
            default -> {}
        }
    }

    private static void startCategory(int index) {
        revealIndex = index;
        statRevealed = 0;
        landAge = 0;
        setPhase(Phase.SPIN);
    }

    private static void setPhase(Phase next) {
        phase = next;
        phaseTicks = 0;
    }

    private static void finishShow() {
        phase = Phase.IDLE;
        phaseTicks = 0;
        showTicks = 0;
        reveals = List.of();
        revealIndex = 0;
    }

    private static void hardReset() {
        finishShow();
        QUEUE.clear();
        HANDLED_DAYS.clear();
        lastSeenCategories = null;
        ticksInWorld = 0;
    }

    private static Reveal currentReveal() {
        return reveals.isEmpty() ? null : reveals.get(Math.min(revealIndex, reveals.size() - 1));
    }

    private static boolean landAgeRunning() {
        return phase == Phase.LAND || phase == Phase.STAT || phase == Phase.REWARD
                || phase == Phase.HOLD;
    }

    private static int holdTicks() {
        return EclipseClientConfig.reducedFx() ? HOLD_TICKS_REDUCED_FX : HOLD_TICKS;
    }

    // --- rendering ---

    /** Above-all GUI layer body (self-registered). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (phase == Phase.IDLE || minecraft.options.hideGui) {
            return; // F1 hides; state keeps advancing so the show never stalls behind it
        }
        float partialTick = minecraft.isPaused() ? 0.0F
                : deltaTracker.getGameTimeDeltaPartialTick(true);
        float showAlpha = switch (phase) {
            case INTRO -> Mth.clamp((phaseTicks + partialTick) / INTRO_TICKS, 0.0F, 1.0F);
            case DONE_FADE -> Mth.clamp(1.0F - (phaseTicks + partialTick) / SUMMARY_FADE_TICKS,
                    0.0F, 1.0F);
            default -> 1.0F;
        };
        if (showAlpha <= 0.01F) {
            return;
        }
        int guiWidth = guiGraphics.guiWidth();
        int guiHeight = guiGraphics.guiHeight();
        guiGraphics.fill(0, 0, guiWidth, guiHeight,
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, 0.85F * showAlpha));
        if (phase == Phase.SUMMARY || phase == Phase.DONE_FADE) {
            renderSummary(guiGraphics, minecraft.font, guiWidth, guiHeight, showAlpha);
        } else {
            renderCategory(guiGraphics, minecraft.font, guiWidth, guiHeight, partialTick, showAlpha);
        }
    }

    private static void renderCategory(GuiGraphics guiGraphics, Font font, int guiWidth,
            int guiHeight, float partialTick, float showAlpha) {
        Reveal reveal = currentReveal();
        if (reveal == null) {
            return;
        }
        // Per-category crossfade: quick ramp-in at spin start, ramp-out during FADE.
        float contentAlpha = showAlpha;
        if (phase == Phase.SPIN) {
            contentAlpha *= Mth.clamp((phaseTicks + partialTick) / 6.0F, 0.0F, 1.0F);
        } else if (phase == Phase.FADE) {
            contentAlpha *= Mth.clamp(1.0F - (phaseTicks + partialTick) / FADE_TICKS, 0.0F, 1.0F);
        } else if (phase == Phase.INTRO) {
            contentAlpha = 0.0F;
        }

        int panelWidth = Math.min(360, (int) (guiWidth * 0.86F));
        int panelHeight = 168;
        int panelX = (guiWidth - panelWidth) / 2;
        int panelY = (guiHeight - panelHeight) / 2 - 10;
        int innerX = panelX + EclipseUiTheme.PAD;
        int innerWidth = panelWidth - 2 * EclipseUiTheme.PAD;
        int centerX = panelX + panelWidth / 2;
        EclipseUiTheme.drawPanel(guiGraphics, panelX, panelY, panelWidth, panelHeight, showAlpha);

        EclipseUiTheme.drawHeader(guiGraphics, font,
                EclipseLang.tr("gui.eclipse.awards.header", showDay),
                innerX, panelY + 10, innerWidth, showAlpha);
        String counter = (revealIndex + 1) + "/" + reveals.size();
        guiGraphics.drawString(font, counter, panelX + panelWidth - EclipseUiTheme.PAD
                - font.width(counter), panelY + 10,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, showAlpha));
        if (contentAlpha <= 0.02F) {
            return;
        }

        String title = EclipseUiTheme.ellipsize(font, reveal.title(), innerWidth);
        guiGraphics.drawString(font, title, centerX - font.width(title) / 2, panelY + 30,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, contentAlpha));

        boolean landed = reveal.strip().done();
        int stripCenterY = panelY + 62;
        drawMarker(guiGraphics, centerX, panelY + 44, panelY + 84, contentAlpha, landed);
        guiGraphics.enableScissor(panelX + 1, panelY + 42, panelX + panelWidth - 1, panelY + 88);
        reveal.strip().render(guiGraphics, font, centerX, stripCenterY,
                innerWidth / 2 - 2, partialTick, contentAlpha, landed);
        guiGraphics.disableScissor();

        if (landed) {
            float landTime = landAge + partialTick;
            guiGraphics.enableScissor(panelX + 1, panelY + 40, panelX + panelWidth - 1, panelY + 90);
            if (!EclipseClientConfig.reducedFx()) {
                renderFlare(guiGraphics, centerX, stripCenterY, landTime, contentAlpha);
            }
            renderWinnerHeads(guiGraphics, reveal, centerX, stripCenterY, landTime, contentAlpha);
            guiGraphics.disableScissor();
            renderWinnerLabel(guiGraphics, font, reveal, centerX, panelY + 92, contentAlpha);
        }

        if ((phase == Phase.STAT || phase == Phase.REWARD || phase == Phase.HOLD
                || phase == Phase.FADE) && !reveal.statLine().isEmpty()) {
            renderStatLine(guiGraphics, font, reveal, centerX, innerWidth, panelY + 104,
                    contentAlpha);
        }
        if ((phase == Phase.REWARD || phase == Phase.HOLD || phase == Phase.FADE)
                && !reveal.rewardLine().isEmpty()) {
            renderRewardLine(guiGraphics, font, reveal, centerX, innerWidth, panelY + 128,
                    partialTick, contentAlpha);
        }

        EclipseUiTheme.drawHairline(guiGraphics, innerX, innerX + innerWidth,
                panelY + panelHeight - 20, showAlpha);
        String hint = EclipseLang.trString("gui.eclipse.awards.skip_hint");
        hint = EclipseUiTheme.ellipsize(font, hint, innerWidth);
        guiGraphics.drawString(font, hint, centerX - font.width(hint) / 2,
                panelY + panelHeight - 14,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, showAlpha * 0.9F));
    }

    /** Center marker: accent needle with small arrow blocks above/below the strip band. */
    private static void drawMarker(GuiGraphics guiGraphics, int centerX, int top, int bottom,
            float alpha, boolean landed) {
        int color = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha * (landed ? 0.35F : 0.8F));
        guiGraphics.fill(centerX, top, centerX + 1, bottom, color);
        guiGraphics.fill(centerX - 2, top - 3, centerX + 3, top - 1, color);
        guiGraphics.fill(centerX - 1, top - 1, centerX + 2, top, color);
        guiGraphics.fill(centerX - 2, bottom + 1, centerX + 3, bottom + 3, color);
        guiGraphics.fill(centerX - 1, bottom, centerX + 2, bottom + 1, color);
    }

    /**
     * Screen-space flare behind the winner head. The checked-in {@code eclipse:roulette_flare}
     * Quasar emitter is world-space (camera-dependent — unusable behind a fixed overlay), so
     * the robust option renders here in code: rotating warm→purple rays + soft glow quads
     * mirroring the emitter's gradient. Skipped under {@code reducedFx}.
     */
    private static void renderFlare(GuiGraphics guiGraphics, int centerX, int centerY,
            float landTime, float alpha) {
        float grow = 1.0F - (float) Math.pow(1.0F - Math.min(landTime / 14.0F, 1.0F), 3.0D);
        float fade = Mth.clamp(1.15F - landTime / 60.0F, 0.18F, 1.0F) * alpha;
        int glowOuter = (int) (20.0F * grow);
        int glowInner = (int) (13.0F * grow);
        guiGraphics.fill(centerX - glowOuter, centerY - glowOuter, centerX + glowOuter,
                centerY + glowOuter, EclipseUiTheme.withAlpha(0xC77DFF, 0.10F * fade));
        guiGraphics.fill(centerX - glowInner, centerY - glowInner, centerX + glowInner,
                centerY + glowInner, EclipseUiTheme.withAlpha(0x7B2CBF, 0.16F * fade));
        for (int ray = 0; ray < 10; ray++) {
            float angle = ray * 36.0F + landTime * 1.6F;
            float pulse = 0.8F + 0.2F * Mth.sin(landTime * 0.31F + ray * 1.7F);
            int length = (int) ((10.0F + 20.0F * grow) * pulse);
            int color = EclipseUiTheme.withAlpha(FLARE_COLORS[ray % FLARE_COLORS.length],
                    0.5F * fade);
            guiGraphics.pose().pushPose();
            guiGraphics.pose().translate(centerX, centerY, 0.0F);
            guiGraphics.pose().mulPose(Axis.ZP.rotationDegrees(angle));
            guiGraphics.fill(9, -1, 9 + length, 1, color);
            guiGraphics.pose().popPose();
        }
    }

    /** The popped winner head (overshoot zoom) plus fanned-out co-winner heads on a tie. */
    private static void renderWinnerHeads(GuiGraphics guiGraphics, Reveal reveal, int centerX,
            int centerY, float landTime, float alpha) {
        float pop = easeOutBack(Math.min(landTime / 12.0F, 1.0F));
        float scale = 1.0F + (EclipseClientConfig.reducedFx() ? 0.2F : 0.45F * pop);
        int half = (int) (RouletteStrip.HEAD_SIZE * scale / 2.0F) + 3;
        drawAccentFrame(guiGraphics, centerX, centerY, half, alpha);
        RouletteStrip.drawHead(guiGraphics, centerX, centerY, scale, alpha);
        if (!reveal.tie()) {
            return;
        }
        int coWinners = Math.min(reveal.winners().size() - 1, 3);
        float slide = 1.0F - (float) Math.pow(1.0F - Mth.clamp((landTime - 5.0F) / 10.0F, 0.0F, 1.0F), 3.0D);
        if (slide <= 0.01F) {
            return;
        }
        for (int i = 0; i < coWinners; i++) {
            int direction = i % 2 == 0 ? 1 : -1;
            int rank = i / 2 + 1;
            int offset = (int) (direction * rank * 38 * slide);
            float coAlpha = alpha * slide;
            drawAccentFrame(guiGraphics, centerX + offset, centerY,
                    RouletteStrip.HEAD_SIZE / 2 + 3, coAlpha * 0.8F);
            RouletteStrip.drawHead(guiGraphics, centerX + offset, centerY, 1.0F, coAlpha);
        }
    }

    private static void drawAccentFrame(GuiGraphics guiGraphics, int centerX, int centerY,
            int half, float alpha) {
        int color = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha);
        guiGraphics.fill(centerX - half, centerY - half, centerX + half, centerY - half + 1, color);
        guiGraphics.fill(centerX - half, centerY + half - 1, centerX + half, centerY + half, color);
        guiGraphics.fill(centerX - half, centerY - half + 1, centerX - half + 1, centerY + half - 1, color);
        guiGraphics.fill(centerX + half - 1, centerY - half + 1, centerX + half, centerY + half - 1, color);
    }

    /**
     * Winner identity row. The server sent no names (anonymity by design), so the label is
     * the localized "YOU"/"DU" when the local player won, else a shimmering glitch scramble;
     * ties append the localized "shared (n)" note.
     */
    private static void renderWinnerLabel(GuiGraphics guiGraphics, Font font, Reveal reveal,
            int centerX, int y, float alpha) {
        String label = reveal.localWon()
                ? EclipseLang.trString("gui.eclipse.awards.you")
                : GlitchText.scramble(6, reveal.salt());
        if (reveal.tie()) {
            label = label + " · "
                    + EclipseLang.trString("gui.eclipse.awards.shared", reveal.winners().size());
        }
        int color = reveal.localWon() ? EclipseUiTheme.ACCENT : EclipseUiTheme.TEXT;
        guiGraphics.drawString(font, label, centerX - font.width(label) / 2, y,
                EclipseUiTheme.withAlpha(color, alpha));
    }

    /** Typewritten stat line (2 chars/tick, blinking cursor), wrapped to at most two rows. */
    private static void renderStatLine(GuiGraphics guiGraphics, Font font, Reveal reveal,
            int centerX, int innerWidth, int y, float alpha) {
        String shown = reveal.statLine().substring(0,
                Math.min(statRevealed, reveal.statLine().length()));
        boolean typing = statRevealed < reveal.statLine().length();
        if (typing && (Minecraft.getInstance().gui.getGuiTicks() / 3) % 2 == 0) {
            shown = shown + "_";
        }
        drawWrappedCentered(guiGraphics, font, shown, centerX, innerWidth, y, 2,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
    }

    /**
     * Reward line materializing with the purple glitch: settled prefix in plain ACCENT (fully
     * readable), the unsettled tail as a re-rolling {@link GlitchText} scramble in deep
     * purple. {@code reducedFx} settles instantly (the scramble itself also calms to "?"s).
     */
    private static void renderRewardLine(GuiGraphics guiGraphics, Font font, Reveal reveal,
            int centerX, int innerWidth, int y, float partialTick, float alpha) {
        String reward = reveal.rewardLine();
        int settled = reward.length();
        if (phase == Phase.REWARD && !EclipseClientConfig.reducedFx()) {
            float progress = Mth.clamp((phaseTicks + partialTick) / REWARD_SETTLE_TICKS, 0.0F, 1.0F);
            settled = Math.min(reward.length(), (int) (reward.length() * progress));
            // Sparse glitch flicker rects around the settling line — the client-side stand-in
            // for the P2 post flash (§3.10 flourish fallback).
            int flickerSeed = (int) (landAge / 2) * 31 + reveal.salt();
            for (int i = 0; i < 4; i++) {
                int hash = (flickerSeed * 0x9E3779B9 + i * 0x85EBCA6B);
                int fx = centerX + (hash % (innerWidth / 2 - 8));
                int fy = y + ((hash >> 8) % 10) - 2;
                int fw = 3 + ((hash >> 16) & 7);
                guiGraphics.fill(fx, fy, fx + fw, fy + 2,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP,
                                0.30F * alpha * (1.0F - progress)));
            }
        }
        String settledPart = reward.substring(0, settled);
        String scrambled = settled < reward.length()
                ? GlitchText.scramble(reward.length() - settled, reveal.salt() * 7 + 1)
                : "";
        // Keep the two segments on one measured line so the text never jumps while settling.
        String full = settledPart + scrambled;
        int width = font.width(full);
        int x = centerX - width / 2;
        if (width > innerWidth) {
            x = centerX - innerWidth / 2;
        }
        guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, settledPart, innerWidth), x, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        if (!scrambled.isEmpty()) {
            int settledWidth = font.width(settledPart);
            if (settledWidth < innerWidth) {
                guiGraphics.drawString(font,
                        EclipseUiTheme.ellipsize(font, scrambled, innerWidth - settledWidth),
                        x + settledWidth, y,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha));
            }
        }
    }

    private static void drawWrappedCentered(GuiGraphics guiGraphics, Font font, String text,
            int centerX, int innerWidth, int y, int maxLines, int color) {
        List<FormattedCharSequence> lines = font.split(Component.literal(text), innerWidth);
        for (int i = 0; i < Math.min(lines.size(), maxLines); i++) {
            FormattedCharSequence line = lines.get(i);
            guiGraphics.drawString(font, line, centerX - font.width(line) / 2, y + i * 10, color);
        }
    }

    /** Compact end card: every category with its winner head(s), reward line and YOU/shared marks. */
    private static void renderSummary(GuiGraphics guiGraphics, Font font, int guiWidth,
            int guiHeight, float showAlpha) {
        int rows = reveals.size();
        int panelWidth = Math.min(360, (int) (guiWidth * 0.86F));
        int panelHeight = 40 + rows * 32 + 12;
        int panelX = (guiWidth - panelWidth) / 2;
        int panelY = (guiHeight - panelHeight) / 2 - 10;
        int innerX = panelX + EclipseUiTheme.PAD;
        int innerWidth = panelWidth - 2 * EclipseUiTheme.PAD;
        EclipseUiTheme.drawPanel(guiGraphics, panelX, panelY, panelWidth, panelHeight, showAlpha);
        int contentY = EclipseUiTheme.drawHeader(guiGraphics, font,
                EclipseLang.tr("gui.eclipse.awards.summary", showDay),
                innerX, panelY + 10, innerWidth, showAlpha);
        for (int i = 0; i < rows; i++) {
            Reveal reveal = reveals.get(i);
            int rowY = contentY + i * 32;
            RouletteStrip.drawHead(guiGraphics, innerX + 8, rowY + 12, 16.0F / RouletteStrip.HEAD_SIZE,
                    showAlpha);
            String marker = reveal.localWon() ? EclipseLang.trString("gui.eclipse.awards.you")
                    : GlitchText.unknown(reveal.salt());
            if (reveal.tie()) {
                marker = marker + " · "
                        + EclipseLang.trString("gui.eclipse.awards.shared", reveal.winners().size());
            }
            int markerWidth = font.width(marker);
            guiGraphics.drawString(font, marker, innerX + innerWidth - markerWidth, rowY + 1,
                    EclipseUiTheme.withAlpha(
                            reveal.localWon() ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM,
                            showAlpha));
            String title = EclipseUiTheme.ellipsize(font, reveal.title(),
                    innerWidth - 24 - markerWidth - 6);
            guiGraphics.drawString(font, title, innerX + 22, rowY + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, showAlpha));
            String reward = EclipseUiTheme.ellipsize(font, reveal.rewardLine(), innerWidth - 24);
            guiGraphics.drawString(font, reward, innerX + 22, rowY + 13,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, showAlpha * 0.95F));
        }
    }

    private static float easeOutBack(float x) {
        float c1 = 1.70158F;
        float c3 = c1 + 1.0F;
        float shifted = x - 1.0F;
        return 1.0F + c3 * shifted * shifted * shifted + c1 * shifted * shifted;
    }
}
