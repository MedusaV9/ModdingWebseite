package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.lwjgl.glfw.GLFW;

/**
 * Status page, Quiet Eclipse v3 (plans_v3 P3 §3.1): the day counter at 2x (never the loud
 * v2 3x — §2.2 caps the hero number at 2.0), the live heart row, a slim horizontal altar
 * progress bar (replacing the v2 texture ring), and today's goals with the kept tick
 * draw-in. Dropped from v2: the online-player count ("souls awake" — B10/§3.3, anonymity)
 * and the phantom hand-routed settings button (B4) — the settings entry is now a real
 * {@link #widgets()} widget that simply turns to the Settings tab (last page).
 *
 * <p>Altar level-up feedback (B6 pairing with the v3 frame): {@link #tick()} runs every
 * client tick for every tab, so the {@link UiSounds#unlockSting()} + bar pulse fire even
 * when the level changes while another page is open. Goal ticks likewise draw in when a
 * goal completes live, not only on {@link #onShown()}.</p>
 */
@OnlyIn(Dist.CLIENT)
public class StatusTab extends HandbookTab {
    private static final ResourceLocation HEART_FULL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_full.png");
    private static final ResourceLocation HEART_EMPTY =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_empty.png");

    /** Tick draw-in: per-goal stagger (on entry) and stroke duration, in ticks. */
    private static final int TICK_STAGGER = 4;
    private static final int TICK_DURATION = 8;
    /** Altar bar pulse length after a level-up (ticks). */
    private static final int PULSE_TICKS = 14;
    /** Slim progress bar height (§3.1 "slim horizontal progress bar"). */
    private static final int BAR_HEIGHT = 3;

    private int tickCounter;
    private int lastAltarLevel = -1;
    private int pulseTicks;
    /** Displayed bar fraction eases toward the real fraction (kept from the v2 ring). */
    private float displayedFraction = -1.0F;
    /**
     * Tick counter value when each goal flipped to done (-1 = not done): the draw-in
     * animates from the FLIP moment, so goals completing while the handbook is open (even
     * on another page — B6) still get their stroke instead of popping in finished.
     */
    private final List<Integer> doneSince = new ArrayList<>();
    private SettingsLink settingsLink;

    @Override
    public String id() {
        return "status";
    }

    @Override
    protected void onInit() {
        settingsLink = new SettingsLink();
    }

    @Override
    public void onShown() {
        pulseTicks = 0;
        displayedFraction = -1.0F;
        // Re-stagger the entry draw-in: goals already done replay their little stroke.
        doneSince.clear();
        List<Boolean> done = ClientStateCache.goalDone;
        for (int i = 0; i < done.size(); i++) {
            doneSince.add(done.get(i) ? tickCounter + i * TICK_STAGGER : -1);
        }
    }

    @Override
    public void tick() {
        tickCounter++;
        if (pulseTicks > 0) {
            pulseTicks--;
        }
        if (lastAltarLevel >= 0 && ClientStateCache.altarLevel > lastAltarLevel) {
            UiSounds.unlockSting();
            if (!EclipseClientConfig.reducedFx()) {
                pulseTicks = PULSE_TICKS;
            }
        }
        lastAltarLevel = ClientStateCache.altarLevel;

        // Track live goal completions so the draw-in starts at the flip, not at onShown.
        List<Boolean> done = ClientStateCache.goalDone;
        while (doneSince.size() < done.size()) {
            doneSince.add(-1);
        }
        while (doneSince.size() > done.size()) {
            doneSince.remove(doneSince.size() - 1);
        }
        for (int i = 0; i < done.size(); i++) {
            if (done.get(i) && doneSince.get(i) < 0) {
                doneSince.set(i, tickCounter);
            } else if (!done.get(i) && doneSince.get(i) >= 0) {
                doneSince.set(i, -1);
            }
        }
    }

    @Override
    public List<AbstractWidget> widgets() {
        return settingsLink == null ? List.of() : List.of(settingsLink);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }

        // Hero number: the day at 2x — the single scaled element of the page (§2.2).
        Component dayText = EclipseLang.tr("gui.eclipse.artifact.day", ClientStateCache.day);
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(x, y, 0);
        guiGraphics.pose().scale(2.0F, 2.0F, 1.0F);
        guiGraphics.drawString(font, ellipsize(font, dayText.getString(), width / 2),
                0, 0, withAlpha(ACCENT_COLOR, alpha));
        guiGraphics.pose().popPose();

        int heartsY = y + 20;
        renderHearts(guiGraphics, x, heartsY, alpha);

        int altarY = heartsY + 9 + EclipseUiTheme.GAP * 2;
        int altarBottom = renderAltarBar(guiGraphics, altarY, partialTick, alpha);

        int goalsY = Math.min(altarBottom + EclipseUiTheme.SECTION_GAP, y + height - 24);
        goalsY = EclipseUiTheme.drawHeader(guiGraphics, font,
                EclipseLang.tr("gui.eclipse.artifact.goals"), x, goalsY, width, alpha);
        renderGoals(guiGraphics, x, goalsY, partialTick, alpha);
    }

    /** Heart row: {@code HeartsService.MAX_HEARTS} slots, lives filled, "+N" past the cap. */
    private void renderHearts(GuiGraphics guiGraphics, int heartsX, int heartsY, float alpha) {
        int lives = Math.max(0, ClientStateCache.lives);
        // Icons that fit the page width cap the row (tiny windows), overflow becomes "+N".
        int slots = Math.min(HeartsService.MAX_HEARTS, Math.max(1, (width - 20) / 11));
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        for (int i = 0; i < slots; i++) {
            guiGraphics.blit(i < lives ? HEART_FULL : HEART_EMPTY,
                    heartsX + i * 11, heartsY, 0, 0, 9, 9, 9, 9);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (lives > slots) {
            guiGraphics.drawString(font, "+" + (lives - slots),
                    heartsX + slots * 11 + 2, heartsY + 1, withAlpha(TEXT_COLOR, alpha));
        }
    }

    /**
     * Slim altar progress bar (§3.1): label row (level left, {@code n/max} right), then a
     * {@value #BAR_HEIGHT}px track with an eased accent fill that flashes bright for
     * {@value #PULSE_TICKS} ticks after a level-up. Returns the y below the bar.
     */
    private int renderAltarBar(GuiGraphics guiGraphics, int barTop, float partialTick, float alpha) {
        int level = ClientStateCache.altarLevel;
        int maxLevel = maxAltarLevel();
        float targetFraction = maxLevel <= 0 ? 0.0F : Mth.clamp(level / (float) maxLevel, 0.0F, 1.0F);
        if (displayedFraction < 0.0F) {
            displayedFraction = targetFraction;
        }
        displayedFraction += (targetFraction - displayedFraction) * 0.15F;

        float pulse = pulseTicks <= 0 || EclipseClientConfig.reducedFx() ? 0.0F
                : Mth.clamp((pulseTicks - partialTick) / PULSE_TICKS, 0.0F, 1.0F);

        Component label = EclipseLang.tr("sidebar.eclipse.altar", level);
        String progress = level + "/" + maxLevel;
        int progressWidth = font.width(progress);
        guiGraphics.drawString(font,
                ellipsize(font, label.getString(), Math.max(20, width - progressWidth - 8)),
                x, barTop, withAlpha(pulse > 0.0F ? ACCENT_COLOR : DIM_COLOR, alpha));
        guiGraphics.drawString(font, progress, x + width - progressWidth, barTop,
                withAlpha(TEXT_COLOR, alpha));

        int trackY = barTop + 12;
        guiGraphics.fill(x, trackY, x + width, trackY + BAR_HEIGHT,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha));
        int fillWidth = Math.round(width * displayedFraction);
        if (fillWidth > 0) {
            guiGraphics.fill(x, trackY, x + fillWidth, trackY + BAR_HEIGHT,
                    withAlpha(ACCENT_COLOR, alpha));
            if (pulse > 0.0F) {
                // Level-up flash: a brief near-white wash over the filled part, no motion.
                guiGraphics.fill(x, trackY, x + fillWidth, trackY + BAR_HEIGHT,
                        withAlpha(TEXT_COLOR, alpha * pulse * 0.7F));
            }
        }
        return trackY + BAR_HEIGHT;
    }

    private void renderGoals(GuiGraphics guiGraphics, int goalsX, int goalsY, float partialTick, float alpha) {
        List<String> lines = ClientStateCache.goalLines.isEmpty() ? ClientStateCache.goals : ClientStateCache.goalLines;
        List<Boolean> done = ClientStateCache.goalDone;
        // Keep clear of the settings link row pinned to the page bottom.
        int bottom = y + height - 16;
        if (lines.isEmpty()) {
            for (FormattedCharSequence line : font.split(
                    EclipseLang.tr("gui.eclipse.artifact.goals.none"), width - 8)) {
                guiGraphics.drawString(font, line, goalsX, goalsY, withAlpha(TEXT_COLOR, alpha));
                goalsY += 10;
            }
            return;
        }
        int textWidth = width - 14;
        for (int i = 0; i < lines.size(); i++) {
            List<FormattedCharSequence> wrapped = font.split(Component.literal(lines.get(i)), textWidth);
            int entryHeight = wrapped.size() * 10 + 3;
            if (goalsY + entryHeight > bottom && i + 1 < lines.size()) {
                // No room for this goal AND more follow: a quiet counter instead of a chop.
                guiGraphics.drawString(font,
                        ellipsize(font, EclipseLang.trString("gui.eclipse.handbook.status.more",
                                lines.size() - i), width),
                        goalsX, goalsY, withAlpha(DIM_COLOR, alpha));
                return;
            }
            boolean goalDone = i < done.size() && done.get(i);
            renderCheckbox(guiGraphics, goalsX, goalsY, i, goalDone, partialTick, alpha);
            for (FormattedCharSequence line : wrapped) {
                if (goalsY + 10 > y + height) {
                    return;
                }
                guiGraphics.drawString(font, line, goalsX + 14, goalsY, withAlpha(TEXT_COLOR, alpha));
                goalsY += 10;
            }
            goalsY += 3;
        }
    }

    /** 9x9 box; when done, the tick draws itself in over {@value #TICK_DURATION} ticks. */
    private void renderCheckbox(GuiGraphics guiGraphics, int boxX, int boxY, int index, boolean done,
            float partialTick, float alpha) {
        int border = withAlpha(DIM_COLOR, alpha);
        guiGraphics.fill(boxX, boxY, boxX + 9, boxY + 1, border);
        guiGraphics.fill(boxX, boxY + 8, boxX + 9, boxY + 9, border);
        guiGraphics.fill(boxX, boxY + 1, boxX + 1, boxY + 8, border);
        guiGraphics.fill(boxX + 8, boxY + 1, boxX + 9, boxY + 8, border);
        if (!done) {
            return;
        }
        int since = index < doneSince.size() ? doneSince.get(index) : 0;
        float progress = EclipseClientConfig.reducedFx() || since < 0 ? 1.0F
                : Mth.clamp((tickCounter + partialTick - since) / TICK_DURATION, 0.0F, 1.0F);
        // Two strokes: (2,5)->(4,7) and (4,7)->(7,2), drawn dot by dot along the path.
        int[][] path = {{2, 5}, {3, 6}, {4, 7}, {5, 5}, {6, 4}, {7, 2}};
        int dots = Math.round(progress * path.length);
        int tickColor = EclipseUiTheme.withAlpha(EclipseUiTheme.GOOD, alpha);
        for (int i = 0; i < dots; i++) {
            guiGraphics.fill(boxX + path[i][0], boxY + path[i][1], boxX + path[i][0] + 2, boxY + path[i][1] + 2,
                    tickColor);
        }
    }

    /** Highest milestone level, from the synced milestone list (fallback 5 = v1/v2 default). */
    private static int maxAltarLevel() {
        int max = 0;
        for (var milestone : ClientStateCache.milestones) {
            max = Math.max(max, milestone.level());
        }
        return max > 0 ? max : 5;
    }

    /**
     * The page's settings entry, as a REAL widget through the frozen {@link #widgets()}
     * API (B4: focus, narration and input routing come from the screen). Clicking turns to
     * the Settings tab via the screen's public 1–8 hotkey path — Settings is pinned LAST
     * in the §3.1 roster, i.e. page 8. The press itself stays silent; the audible feedback
     * is the page-turn whoosh of the switch (§2.3 — no double sound).
     */
    private class SettingsLink extends EclipseWidget {
        SettingsLink() {
            super(0, 0, 10, 14, EclipseLang.tr("gui.eclipse.settings.open"));
            String label = getMessage().getString() + " \u00bb";
            setWidth(StatusTab.this.font.width(label) + 8);
            setPosition(StatusTab.this.x + StatusTab.this.width - getWidth(),
                    StatusTab.this.y + StatusTab.this.height - 14);
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            // Public route to the roster's last page (the frame's switchTab is frame-only).
            StatusTab.this.screen.keyPressed(GLFW.GLFW_KEY_8, 0, 0);
        }

        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            // Silent press: the tab switch already whooshes via UiSounds.pageTurn().
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            int color = isHoveredOrFocused() ? TEXT_COLOR : DIM_COLOR;
            String label = getMessage().getString() + " \u00bb";
            guiGraphics.drawString(StatusTab.this.font, label, getX() + 4, getY() + 3,
                    EclipseUiTheme.withAlpha(color, 1.0F));
        }
    }
}
