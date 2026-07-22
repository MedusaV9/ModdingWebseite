package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Status page: big day counter, live heart row ({@code ClientStateCache.lives}), altar
 * progress ring (256x256 {@code icons/altar_ring.png} with a code-drawn arc that lerps and
 * pulses on level-up), today's goals with an animated tick draw-in, and the online count
 * from the client's tab-list player info (visually hidden by the anonymity suite, but the
 * client still receives it).
 */
@OnlyIn(Dist.CLIENT)
public class StatusTab extends HandbookTab {
    private static final ResourceLocation HEART_FULL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_full.png");
    private static final ResourceLocation HEART_EMPTY =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_empty.png");
    private static final ResourceLocation ALTAR_RING =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/icons/altar_ring.png");

    private static final int MIN_HEART_ICONS = 5;
    private static final int MAX_HEART_ICONS = 10;
    private static final int RING_SIZE = 52;
    /** Tick draw-in: per-goal stagger and duration, in ticks. */
    private static final int TICK_STAGGER = 4;
    private static final int TICK_DURATION = 8;

    private int shownTicks;
    private int lastAltarLevel = -1;
    private int pulseTicks;
    /** Displayed ring fraction eases toward the real fraction. */
    private float displayedRingFraction = -1.0F;

    @Override
    public String id() {
        return "status";
    }

    @Override
    public void onShown() {
        shownTicks = 0;
        lastAltarLevel = ClientStateCache.altarLevel;
        pulseTicks = 0;
        displayedRingFraction = -1.0F;
    }

    @Override
    public void tick() {
        shownTicks++;
        if (pulseTicks > 0) {
            pulseTicks--;
        }
        if (lastAltarLevel >= 0 && ClientStateCache.altarLevel > lastAltarLevel && !EclipseClientConfig.reducedFx()) {
            pulseTicks = 14;
        }
        lastAltarLevel = ClientStateCache.altarLevel;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }

        // Big day counter (3x scale).
        Component dayText = Component.translatable("gui.eclipse.artifact.day", ClientStateCache.day);
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(x, y, 0);
        guiGraphics.pose().scale(3.0F, 3.0F, 1.0F);
        guiGraphics.drawString(font, dayText, 0, 0, withAlpha(ACCENT_COLOR, alpha));
        guiGraphics.pose().popPose();

        // Heart row under the counter.
        int heartsY = y + 32;
        renderHearts(guiGraphics, x, heartsY, alpha);

        // Altar progress ring, top-right of the page.
        renderAltarRing(guiGraphics, x + width - RING_SIZE - 4, y, partialTick, alpha);

        // Today's goals with tick draw-in.
        int goalsY = heartsY + 18;
        guiGraphics.drawString(font, Component.translatable("gui.eclipse.artifact.goals"),
                x, goalsY, withAlpha(ACCENT_COLOR, alpha));
        renderGoals(guiGraphics, x, goalsY + 12, partialTick, alpha);

        // Online count pinned to the page bottom.
        int online = minecraft.getConnection() != null ? minecraft.getConnection().getOnlinePlayers().size() : 0;
        guiGraphics.drawString(font, Component.translatable("gui.eclipse.handbook.status.online", online),
                x, y + height - 10, withAlpha(DIM_COLOR, alpha));
    }

    /** Lives as heart icons: {@code lives} full, padded to at least {@value #MIN_HEART_ICONS} slots. */
    private void renderHearts(GuiGraphics guiGraphics, int heartsX, int heartsY, float alpha) {
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        int lives = Math.max(0, ClientStateCache.lives);
        int total = Math.min(MAX_HEART_ICONS, Math.max(MIN_HEART_ICONS, lives));
        for (int i = 0; i < total; i++) {
            ResourceLocation texture = i < lives ? HEART_FULL : HEART_EMPTY;
            guiGraphics.blit(texture, heartsX + i * 11, heartsY, 0, 0, 9, 9, 9, 9);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (lives > MAX_HEART_ICONS) {
            guiGraphics.drawString(font, "+" + (lives - MAX_HEART_ICONS),
                    heartsX + total * 11 + 2, heartsY + 1, withAlpha(TEXT_COLOR, alpha));
        }
    }

    /** Ring texture + code-drawn progress arc; pulses (scale) for a few ticks after a level-up. */
    private void renderAltarRing(GuiGraphics guiGraphics, int ringX, int ringY, float partialTick, float alpha) {
        int level = ClientStateCache.altarLevel;
        int maxLevel = maxAltarLevel();
        float targetFraction = maxLevel <= 0 ? 0.0F : Mth.clamp(level / (float) maxLevel, 0.0F, 1.0F);
        if (displayedRingFraction < 0.0F) {
            displayedRingFraction = targetFraction;
        }
        displayedRingFraction += (targetFraction - displayedRingFraction) * 0.15F;

        float pulse = 1.0F;
        if (pulseTicks > 0 && !EclipseClientConfig.reducedFx()) {
            pulse = 1.0F + 0.15F * Mth.sin((pulseTicks - partialTick) / 14.0F * Mth.PI);
        }
        float cx = ringX + RING_SIZE / 2.0F;
        float cy = ringY + RING_SIZE / 2.0F;

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(cx, cy, 0);
        guiGraphics.pose().scale(pulse, pulse, 1.0F);
        guiGraphics.pose().translate(-cx, -cy, 0);

        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(ALTAR_RING, ringX, ringY, 0, 0, RING_SIZE, RING_SIZE, RING_SIZE, RING_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);

        // Progress arc: dots along the ring radius, clockwise from 12 o'clock.
        float radius = RING_SIZE * 0.40F;
        int steps = (int) (displayedRingFraction * 60.0F);
        int arcColor = withAlpha(ACCENT_COLOR, alpha);
        for (int i = 0; i <= steps; i++) {
            double angle = -Math.PI / 2 + i / 60.0D * Math.PI * 2;
            int dotX = (int) (cx + Math.cos(angle) * radius);
            int dotY = (int) (cy + Math.sin(angle) * radius);
            guiGraphics.fill(dotX - 1, dotY - 1, dotX + 2, dotY + 2, arcColor);
        }

        String label = level + "/" + maxLevel;
        guiGraphics.drawCenteredString(font, label, (int) cx, (int) cy - 4, withAlpha(TEXT_COLOR, alpha));
        guiGraphics.pose().popPose();

        guiGraphics.drawCenteredString(font, Component.translatable("gui.eclipse.artifact.altar", level),
                (int) cx, ringY + RING_SIZE + 4, withAlpha(DIM_COLOR, alpha));
    }

    private void renderGoals(GuiGraphics guiGraphics, int goalsX, int goalsY, float partialTick, float alpha) {
        List<String> lines = ClientStateCache.goalLines.isEmpty() ? ClientStateCache.goals : ClientStateCache.goalLines;
        List<Boolean> done = ClientStateCache.goalDone;
        int textWidth = width - RING_SIZE - 24;
        if (lines.isEmpty()) {
            for (FormattedCharSequence line : font.split(
                    Component.translatable("gui.eclipse.artifact.goals.none"), width - 8)) {
                guiGraphics.drawString(font, line, goalsX, goalsY, withAlpha(TEXT_COLOR, alpha));
                goalsY += 10;
            }
            return;
        }
        for (int i = 0; i < lines.size() && goalsY < y + height - 24; i++) {
            boolean goalDone = i < done.size() && done.get(i);
            renderCheckbox(guiGraphics, goalsX, goalsY, i, goalDone, partialTick, alpha);
            List<FormattedCharSequence> wrapped = new ArrayList<>(font.split(
                    Component.literal(lines.get(i)), textWidth));
            for (FormattedCharSequence line : wrapped) {
                guiGraphics.drawString(font, line, goalsX + 14, goalsY, withAlpha(TEXT_COLOR, alpha));
                goalsY += 10;
            }
            goalsY += 3;
        }
    }

    /** 9x9 box; when done, the tick draws itself in over {@value #TICK_DURATION} ticks (staggered). */
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
        float progress = EclipseClientConfig.reducedFx() ? 1.0F
                : Mth.clamp((shownTicks + partialTick - index * TICK_STAGGER) / TICK_DURATION, 0.0F, 1.0F);
        // Two strokes: (2,5)->(4,7) and (4,7)->(7,2), drawn dot by dot along the path.
        int[][] path = {{2, 5}, {3, 6}, {4, 7}, {5, 5}, {6, 4}, {7, 2}};
        int dots = Math.round(progress * path.length);
        int tickColor = withAlpha(ACCENT_COLOR, alpha);
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
}
