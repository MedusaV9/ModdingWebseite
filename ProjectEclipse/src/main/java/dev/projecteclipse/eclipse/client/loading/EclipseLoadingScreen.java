package dev.projecteclipse.eclipse.client.loading;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.ReceivingLevelScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;

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

        int w = this.width;
        int h = this.height;
        if (PortalTransitionController.active()) {
            // Pure-black variant: the transition controller owns all visuals on top (§3.11).
            guiGraphics.fill(0, 0, w, h, 0xFF000000);
            return;
        }

        long now = System.currentTimeMillis();
        boolean reduced = EclipseClientConfig.reducedFx();

        // Dark panel base + soft vertical vignette (no textures required).
        guiGraphics.fill(0, 0, w, h, 0xFF0A0714);
        guiGraphics.fillGradient(0, 0, w, h / 3, 0x66000000, 0x00000000);
        guiGraphics.fillGradient(0, h - h / 3, w, h, 0x00000000, 0x80000000);

        int cx = w / 2;
        int cy = Math.max(SIGIL_RADIUS + 12, h / 2 - 28);
        this.renderSigil(guiGraphics, cx, cy, now, reduced);

        // Title line.
        Component title = EclipseLang.tr(this.variant.titleKey);
        int titleY = cy + SIGIL_RADIUS + 18;
        guiGraphics.drawCenteredString(this.font, title, cx, titleY, EclipseUiTheme.TEXT);

        // Shimmer hairline (drifting highlight — deliberately NOT a progress bar).
        int barHalf = Math.min(70, w / 4);
        int barY = titleY + 14;
        guiGraphics.fill(cx - barHalf, barY, cx + barHalf, barY + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.9F));
        if (!reduced) {
            float sweep = (now % 2_200L) / 2_200.0F;
            int hx = cx - barHalf + Math.round(sweep * (barHalf * 2 - 18));
            guiGraphics.fill(hx, barY, hx + 18, barY + 1, EclipseUiTheme.ACCENT);
        }

        this.renderTip(guiGraphics, cx, Math.min(h - 12, barY + 26), now);
    }

    /** Breathing eclipse sigil: accent corona ring occluded by the dark disc. */
    private void renderSigil(GuiGraphics guiGraphics, int cx, int cy, long now, boolean reduced) {
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
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        }
        // Faint outer glow ring.
        int glowRadius = coronaRadius + 4;
        for (int i = 0; i < 48; i++) {
            float angle = i / 48.0F * Mth.TWO_PI;
            int x = cx + Math.round(Mth.cos(angle) * glowRadius);
            int y = cy + Math.round(Mth.sin(angle) * glowRadius);
            guiGraphics.fill(x, y, x + 1, y + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, breath * 0.35F));
        }
        // Occluding disc (the eclipse body), scanline-filled.
        int discRadius = SIGIL_RADIUS - 3;
        for (int dy = -discRadius; dy <= discRadius; dy++) {
            int half = (int) Math.floor(Math.sqrt((double) discRadius * discRadius - (double) dy * dy));
            guiGraphics.fill(cx - half, cy + dy, cx + half + 1, cy + dy + 1, 0xFF06030F);
        }
    }

    /** Rotating flavor line ({@code gui.eclipse.loading.tip.1..8}), crossfaded per slot. */
    private void renderTip(GuiGraphics guiGraphics, int cx, int y, long now) {
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
        Component tip = EclipseLang.tr("gui.eclipse.loading.tip." + (index + 1));
        guiGraphics.drawCenteredString(this.font, tip, cx, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // Fully custom visuals; never the vanilla portal/panorama backgrounds.
    }
}
