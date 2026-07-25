package dev.projecteclipse.eclipse.client.loading;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.ReceivingLevelScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.RenderGuiEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * The Quiet-Eclipse loading screen (P3 §3.11, R10): replaces {@code ReceivingLevelScreen}
 * (world join + every dimension change) and {@code LevelLoadingScreen} (SP spawn-chunk load)
 * via {@link LoadingScreenSwap}. Dark panel, breathing eclipse sigil (code-drawn corona +
 * disc — the optional P2 art {@code textures/gui/loading/ring.png} can replace it later),
 * rotating localized flavor line, subtle shimmer hairline. No fake progress bars (progress
 * is unknowable here). While {@link PortalTransitionController#active()} the screen renders
 * its pure-black variant instead — the controller draws the glitch/fade on top (R13c).
 *
 * <p><b>Safety model ("never traps"):</b> the replaced vanilla screen instance is kept as a
 * hidden delegate — {@link #tick()} forwards to it so the untouched vanilla close logic
 * (level-received check + vanilla's own 30 s limit) runs and closes us via its
 * {@code minecraft.setScreen} call; {@link #render} is never forwarded. Belt+braces: a
 * wall-clock failsafe (checked in render too, because {@code Minecraft.doWorldLoad} does not
 * tick the current screen) force-closes after {@link Variant#failsafeMillis}. The
 * {@code customLoadingScreens} killswitch lives in {@link LoadingScreenSwap}.</p>
 *
 * <p>Extends {@link ReceivingLevelScreen} (with an inert supplier — its close logic is never
 * used; the delegate owns closing) so vanilla {@code instanceof ReceivingLevelScreen} checks
 * keep their meaning, e.g. {@code LocalPlayer.aiStep}'s portal-confusion suppression. The
 * plan's "replicate, don't extend" concern was about reusing the private level-received
 * supplier — the delegate pattern already covers that; the subclassing is purely for the
 * instanceof contract.</p>
 *
 * <p>While rendering, {@link TransitionFx#setLoadingPulse(float)} is refreshed every frame
 * (world-side glitch breathing per the frozen R13 contract) and zeroed in {@link #removed()}.</p>
 *
 * <p><b>Dismissal (Wave-5 A2):</b> a plain (non-portal) close no longer hard-cuts — see
 * {@link DismissFade}.</p>
 */
public final class EclipseLoadingScreen extends ReceivingLevelScreen {
    /** Which vanilla screen this replaces (affects title line + failsafe budget). */
    public enum Variant {
        /** {@code ReceivingLevelScreen}: server join / dimension change (vanilla self-caps at 30 s). */
        RECEIVING("gui.eclipse.loading.receiving", 60_000L),
        /** {@code LevelLoadingScreen}: SP spawn-chunk preparation (can be legitimately slow). */
        PREPARING("gui.eclipse.loading.preparing", 90_000L);

        private final String titleKey;
        private final long failsafeMillis;

        Variant(String titleKey, long failsafeMillis) {
            this.titleKey = titleKey;
            this.failsafeMillis = failsafeMillis;
        }
    }

    private static final int TIP_COUNT = 8;
    private static final long TIP_ROTATE_MILLIS = 4_000L;
    private static final long TIP_FADE_MILLIS = 350L;
    private static final float LOADING_PULSE = 0.5F;
    private static final int SIGIL_RADIUS = 22;

    private final Screen delegate;
    private final Variant variant;
    private final long createdAtMillis = System.currentTimeMillis();
    private final int tipOffset = (int) (Math.random() * TIP_COUNT);
    private boolean failsafeFired;

    public EclipseLoadingScreen(Screen delegate, Variant variant) {
        // Inert supplier/reason: the base class close logic is bypassed (we never call
        // super.tick()); the DELEGATE's untouched vanilla logic decides when to close.
        super(() -> false, ReceivingLevelScreen.Reason.OTHER);
        this.delegate = delegate;
        this.variant = variant;
        DismissFade.cancel(); // a new load supersedes any lingering dismissal fade
    }

    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void init() {
        // Give the hidden delegate a valid minecraft/font/dimensions so its tick() and
        // onClose() can run; called again automatically on resize (Screen.resize → init).
        this.delegate.init(this.minecraft, this.width, this.height);
    }

    @Override
    public void tick() {
        // Vanilla close logic lives in the delegate; when the level is received (or vanilla's
        // own 30 s limit passes) it calls minecraft.setScreen itself, which closes us.
        this.delegate.tick();
        this.checkFailsafe();
    }

    @Override
    public void removed() {
        TransitionFx.setLoadingPulse(0.0F);
        this.delegate.removed();
        // Wave-5 A2: a plain world join/dimension change pops this screen the frame the
        // level is ready — hand the last frame to the DismissFade overlay for a smooth
        // ease-out instead of a hard cut. Portal-driven closes are excluded: the
        // PortalTransitionController already owns that fade (its black hold + fade-in).
        Minecraft minecraft = this.minecraft != null ? this.minecraft : Minecraft.getInstance();
        if (minecraft != null && minecraft.level != null && !PortalTransitionController.active()) {
            DismissFade.begin(this);
        }
    }

    /**
     * Hard failsafe (also called from {@link #render}: during the SP load loop
     * {@code Minecraft.doWorldLoad} renders but never ticks the current screen).
     */
    private void checkFailsafe() {
        if (this.failsafeFired || this.minecraft == null || this.minecraft.screen != this) {
            return;
        }
        if (System.currentTimeMillis() - this.createdAtMillis > this.variant.failsafeMillis) {
            this.failsafeFired = true;
            EclipseMod.LOGGER.warn(
                    "Eclipse loading screen ({}) exceeded {} ms without the delegate closing it — failsafe close",
                    this.variant, this.variant.failsafeMillis);
            this.onClose();
        }
    }

    // ------------------------------------------------------------------ rendering

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // Frozen R13 contract: refresh at least every 100 ticks; per-frame is fine.
        TransitionFx.setLoadingPulse(LOADING_PULSE);
        this.checkFailsafe();

        if (PortalTransitionController.active()) {
            if (PortalTransitionController.whiteout()) {
                // C15 credits: the disguised WHITE loading screen with a fake vanilla
                // progress line — the gag is that it looks like a real load.
                this.renderCreditsWhite(guiGraphics);
                return;
            }
            // Pure-black variant: the transition controller owns all visuals on top (§3.11).
            guiGraphics.fill(0, 0, this.width, this.height, 0xFF000000);
            return;
        }
        this.renderPanel(guiGraphics, this.width, this.height, System.currentTimeMillis(), 1.0F);
    }

    /**
     * The C15 white credits variant (IDEAS-backrooms_finale §B1 t=230): plain white fill,
     * a deadpan vanilla-styled "Building terrain…" line and a percentage that creeps toward
     * (and never reaches) 100 — no sigil, no tips, none of the Eclipse dressing. FXTEAM
     * CUT-CREDITS gag polish: the line's trailing ellipsis types 1→3 dots (500 ms cadence)
     * and the percentage deadpan-stalls at ~62% for 1.2 s before resuming, the way a real
     * terrain load hitches. With {@code reducedFx} both animations are dropped (static
     * translated line only, no percentage).
     */
    private void renderCreditsWhite(GuiGraphics guiGraphics) {
        guiGraphics.fill(0, 0, this.width, this.height, 0xFFFFFFFF);
        int centerX = this.width / 2;
        int centerY = this.height / 2;
        Component line = EclipseLang.tr("gui.eclipse.loading.credits_fake");
        if (EclipseClientConfig.reducedFx()) {
            drawCenteredNoShadow(guiGraphics, line.getString(), centerX, centerY - 10, 0xFF404040);
            return;
        }
        long elapsed = System.currentTimeMillis() - this.createdAtMillis;
        // Typing ellipsis: strip the translation's own trailing "…"/dots, re-grow 1→3.
        int dots = 1 + (int) ((elapsed / 500L) % 3L);
        drawCenteredNoShadow(guiGraphics, stripTrailingEllipsis(line.getString()) + ".".repeat(dots),
                centerX, centerY - 10, 0xFF404040);
        // Fake progress: fast out of the gate, one mid-load stall, asymptotically stuck
        // in the high 90s (the exp curve reaches ~62% at the 2.5 s stall window).
        long effective = elapsed < 2_500L ? elapsed : elapsed < 3_700L ? 2_500L : elapsed - 1_200L;
        int percent = (int) Math.min(99L, Math.round(99.0D * (1.0D - Math.exp(-effective / 2_500.0D))));
        drawCenteredNoShadow(guiGraphics, percent + "%", centerX, centerY + 4, 0xFF808080);
    }

    /**
     * Vanilla-clean centered text: {@code drawCenteredString} always drops a shadow, which
     * reads as a smudge on the pure-white credits fill — the real vanilla loading overlay
     * draws its text shadowless, so the gag line must too.
     */
    private void drawCenteredNoShadow(GuiGraphics guiGraphics, String text, int centerX, int y, int color) {
        guiGraphics.drawString(this.font, text, centerX - this.font.width(text) / 2, y, color, false);
    }

    /** Trims any trailing "…", '.' or spaces so the animated ellipsis never doubles up. */
    private static String stripTrailingEllipsis(String text) {
        int end = text.length();
        while (end > 0) {
            char last = text.charAt(end - 1);
            if (last == '…' || last == '.' || last == ' ') {
                end--;
            } else {
                break;
            }
        }
        return text.substring(0, end);
    }

    /**
     * The full loading composition (panel, sigil, title, hairline, tip) at a master
     * {@code alpha} — {@code 1.0} while the screen is live; the {@link DismissFade}
     * overlay replays it with a decaying alpha for the A2 ease-out dismissal.
     */
    void renderPanel(GuiGraphics guiGraphics, int w, int h, long now, float alpha) {
        boolean reduced = EclipseClientConfig.reducedFx();

        // Dark panel base + soft vertical vignette (no textures required).
        guiGraphics.fill(0, 0, w, h, EclipseUiTheme.withAlpha(0xFF0A0714, alpha));
        guiGraphics.fillGradient(0, 0, w, h / 3,
                EclipseUiTheme.withAlpha(0x66000000, alpha), 0x00000000);
        guiGraphics.fillGradient(0, h - h / 3, w, h, 0x00000000,
                EclipseUiTheme.withAlpha(0x80000000, alpha));

        int cx = w / 2;
        int cy = Math.max(SIGIL_RADIUS + 12, h / 2 - 28);
        this.renderSigil(guiGraphics, cx, cy, now, reduced, alpha);

        // Title line (resolved at render time so /lang switches apply mid-load).
        Component title = EclipseLang.tr(this.variant.titleKey);
        int titleY = cy + SIGIL_RADIUS + 18;
        guiGraphics.drawCenteredString(this.font, title, cx, titleY,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));

        // Shimmer hairline (drifting highlight — deliberately NOT a progress bar).
        int barHalf = Math.min(70, w / 4);
        int barY = titleY + 14;
        guiGraphics.fill(cx - barHalf, barY, cx + barHalf, barY + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.9F * alpha));
        if (!reduced) {
            float sweep = (now % 2_200L) / 2_200.0F;
            int hx = cx - barHalf + Math.round(sweep * (barHalf * 2 - 18));
            guiGraphics.fill(hx, barY, hx + 18, barY + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        }

        this.renderTip(guiGraphics, cx, Math.min(h - 12, barY + 26), now, alpha);
    }

    /** Breathing eclipse sigil: accent corona ring occluded by the dark disc. */
    private void renderSigil(GuiGraphics guiGraphics, int cx, int cy, long now, boolean reduced,
            float masterAlpha) {
        float breath = reduced ? 0.7F
                : 0.55F + 0.25F * Mth.sin((float) (now % 2_400L) / 2_400.0F * Mth.TWO_PI);
        float highlightAngle = reduced ? -Mth.HALF_PI
                : (float) (now % 8_000L) / 8_000.0F * Mth.TWO_PI;

        // Corona: 72 segments, brighter near the slowly-orbiting highlight.
        int coronaRadius = SIGIL_RADIUS;
        for (int i = 0; i < 72; i++) {
            float angle = i / 72.0F * Mth.TWO_PI;
            int x = cx + Math.round(Mth.cos(angle) * coronaRadius);
            int y = cy + Math.round(Mth.sin(angle) * coronaRadius);
            float highlight = 0.5F + 0.5F * Mth.cos(angle - highlightAngle);
            float alpha = breath * (0.25F + 0.6F * highlight * highlight);
            guiGraphics.fill(x - 1, y - 1, x + 1, y + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha * masterAlpha));
        }
        // Faint outer glow ring.
        int glowRadius = coronaRadius + 4;
        for (int i = 0; i < 48; i++) {
            float angle = i / 48.0F * Mth.TWO_PI;
            int x = cx + Math.round(Mth.cos(angle) * glowRadius);
            int y = cy + Math.round(Mth.sin(angle) * glowRadius);
            guiGraphics.fill(x, y, x + 1, y + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, breath * 0.35F * masterAlpha));
        }
        // Occluding disc (the eclipse body), scanline-filled.
        int discRadius = SIGIL_RADIUS - 3;
        int discColor = EclipseUiTheme.withAlpha(0xFF06030F, masterAlpha);
        for (int dy = -discRadius; dy <= discRadius; dy++) {
            int half = (int) Math.floor(Math.sqrt((double) discRadius * discRadius - (double) dy * dy));
            guiGraphics.fill(cx - half, cy + dy, cx + half + 1, cy + dy + 1, discColor);
        }
    }

    /** Rotating flavor line ({@code gui.eclipse.loading.tip.1..8}), crossfaded per slot. */
    private void renderTip(GuiGraphics guiGraphics, int cx, int y, long now, float masterAlpha) {
        long slot = (now - this.createdAtMillis) / TIP_ROTATE_MILLIS;
        int index = (int) ((this.tipOffset + slot) % TIP_COUNT);
        long within = (now - this.createdAtMillis) % TIP_ROTATE_MILLIS;
        float alpha = 1.0F;
        if (within < TIP_FADE_MILLIS) {
            alpha = within / (float) TIP_FADE_MILLIS;
        } else if (within > TIP_ROTATE_MILLIS - TIP_FADE_MILLIS) {
            alpha = (TIP_ROTATE_MILLIS - within) / (float) TIP_FADE_MILLIS;
        }
        if (EclipseClientConfig.reducedFx()) {
            alpha = 1.0F;
        }
        // Resolved at render time (never cached) so a /lang switch mid-load applies.
        Component tip = EclipseLang.tr("gui.eclipse.loading.tip." + (index + 1));
        guiGraphics.drawCenteredString(this.font, tip, cx, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * masterAlpha));
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // Fully custom visuals; never the vanilla portal/panorama backgrounds.
    }

    /**
     * Wave-5 A2 dismissal fade: when a plain (non-portal) load finishes, the screen pops
     * immediately — the vanilla delegate owns closing and its {@code setScreen(null)} is
     * not interceptable ({@code ScreenEvent.Closing} is informational) — and this overlay
     * replays the final loading frame over the now-live world with a
     * {@value #FADE_MILLIS} ms ease-out-cubic alpha ramp ({@link FadeCurve#easeOutCubic}).
     *
     * <p><b>No soft-lock by construction:</b> the pop has already happened before the fade
     * begins; the overlay is pure cosmetics, is not a screen, captures no input, expires on
     * the wall clock even when rendering stalls, and resets on logout or whenever a new
     * {@link EclipseLoadingScreen} takes over.</p>
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class DismissFade {
        private static final long FADE_MILLIS = 400L;

        @Nullable
        private static EclipseLoadingScreen source;
        private static long startMillis;

        private DismissFade() {}

        static void begin(EclipseLoadingScreen screen) {
            source = screen;
            startMillis = System.currentTimeMillis();
        }

        static void cancel() {
            source = null;
        }

        /** World-visible frames; screen frames are covered by {@link #onScreenRender}. */
        @SubscribeEvent
        static void onRenderGui(RenderGuiEvent.Post event) {
            if (Minecraft.getInstance().screen == null) {
                render(event.getGuiGraphics());
            }
        }

        /** Frames where a screen (chat, …) opened right after the load: keep fading on top. */
        @SubscribeEvent
        static void onScreenRender(ScreenEvent.Render.Post event) {
            if (!(event.getScreen() instanceof EclipseLoadingScreen)) {
                render(event.getGuiGraphics());
            }
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            cancel();
        }

        private static void render(GuiGraphics guiGraphics) {
            EclipseLoadingScreen screen = source;
            if (screen == null) {
                return;
            }
            if (Minecraft.getInstance().level == null) {
                cancel(); // world already gone (disconnect) — nothing to fade over
                return;
            }
            float progress = (System.currentTimeMillis() - startMillis) / (float) FADE_MILLIS;
            float alpha = 1.0F - FadeCurve.easeOutCubic(progress);
            if (alpha <= 0.02F) {
                cancel();
                return;
            }
            screen.renderPanel(guiGraphics, guiGraphics.guiWidth(), guiGraphics.guiHeight(),
                    System.currentTimeMillis(), alpha);
        }
    }
}
