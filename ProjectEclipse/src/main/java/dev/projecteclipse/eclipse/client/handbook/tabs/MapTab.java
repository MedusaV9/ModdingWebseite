package dev.projecteclipse.eclipse.client.handbook.tabs;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.core.BlockPos;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Map page, Quiet Eclipse v3 (plans_v3 P3 §3.1 — "kept, it's already vector-drawn;
 * recolor + legend spacing"): stylized top-down concentric ring diagram of the overworld
 * disc, now fully on §2.1 theme tokens — unlocked rings {@code ACCENT}, sealed rings
 * {@code HAIRLINE}, the soft border {@code DANGER}, spawn dot and landmark diamonds
 * {@code TEXT}. Rings come from the shared {@code worldgen.StageRadii} table; committed
 * stages render lit, future rings stay dim and unlabeled, the CURRENT stage ring pulses
 * softly ({@code reducedFx} = static). On top: the stage-0 satellite player discs
 * ({@code DiscGeometry}), the animated soft border circle from the border cache, the
 * spawn/sanctum dot and stage-gated landmark markers (decorative positions, not world
 * coordinates). The flow-wrapped legend anchors the bottom on the §2.2 baseline grid.
 */
@OnlyIn(Dist.CLIENT)
public class MapTab extends HandbookTab {
    private static final int RING_COLOR_UNLOCKED = ACCENT_COLOR;
    private static final int RING_COLOR_FUTURE = EclipseUiTheme.HAIRLINE & 0xFFFFFF;
    private static final int BORDER_COLOR = EclipseUiTheme.DANGER & 0xFFFFFF;
    private static final int MARKER_COLOR = TEXT_COLOR;

    /** Legend metrics (§2.2 rhythm): row height, swatch box, swatch→text and entry gaps. */
    private static final int LEGEND_ROW = 12;
    private static final int LEGEND_SWATCH = 6;
    private static final int LEGEND_TEXT_GAP = 4;
    private static final int LEGEND_ENTRY_GAP = 12;

    /** Default stage → landmark (v2 {@code stages.json} defaults); angle keeps markers apart. */
    private record Landmark(int stage, String labelKey, double angleDegrees) {}

    private static final Landmark[] LANDMARKS = {
            new Landmark(2, "gui.eclipse.handbook.map.landmark.desert_temple", 40.0D),
            new Landmark(3, "gui.eclipse.handbook.map.landmark.jungle_temple", 150.0D),
            new Landmark(4, "gui.eclipse.handbook.map.landmark.village", 250.0D),
            new Landmark(5, "gui.eclipse.handbook.map.landmark.stronghold", 330.0D)};

    @Override
    public String id() {
        return "map";
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        int legendHeight = legendRows() * LEGEND_ROW + EclipseUiTheme.GAP * 2;
        int diagramHeight = height - legendHeight;
        int centerX = x + width / 2;
        int centerY = y + diagramHeight / 2 + 4;

        int currentStage = ClientStateCache.stageOverworld;
        int maxStage = StageRadii.maxStage(DiscProfile.OVERWORLD);
        double borderRadius = ClientStateCache.currentBorderRadius(false, Util.getMillis());

        float worldRadius = StageRadii.radius(DiscProfile.OVERWORLD, maxStage) * 1.08F;
        worldRadius = Math.max(worldRadius, (float) borderRadius * 1.05F);
        // A zeroed radius table (bad stage config) must not become scale=∞ → segment hang.
        worldRadius = Math.max(1.0F, worldRadius);
        float scale = (Math.min(width, diagramHeight) / 2.0F - 6.0F) / worldRadius;

        guiGraphics.drawString(font,
                ellipsize(font, EclipseLang.trString("gui.eclipse.handbook.map.stage", currentStage), width),
                x, y, withAlpha(ACCENT_COLOR, alpha));

        guiGraphics.enableScissor(x, y, x + width, y + height);

        // Stage rings, inner to outer.
        for (int stage = 0; stage <= maxStage; stage++) {
            boolean unlocked = stage <= currentStage;
            float radius = StageRadii.radius(DiscProfile.OVERWORLD, stage) * scale;
            float ringAlpha = unlocked ? alpha * 0.9F : alpha * 0.8F;
            int color = unlocked ? RING_COLOR_UNLOCKED : RING_COLOR_FUTURE;
            boolean isCurrent = stage == currentStage;
            if (isCurrent && !EclipseClientConfig.reducedFx()) {
                ringAlpha = alpha * (0.75F + 0.25F * Mth.sin(Util.getMillis() / 240.0F));
            }
            drawCircle(guiGraphics, centerX, centerY, radius, withAlpha(color, ringAlpha), isCurrent ? 2 : 1, false);
        }

        // Stage-0 satellite player discs (visible context even after fusion).
        float satelliteRadius = DiscGeometry.PLAYER_DISC_RADIUS * scale;
        for (int i = 0; i < DiscGeometry.PLAYER_DISC_COUNT; i++) {
            BlockPos center = DiscGeometry.playerDiscCenter(i);
            drawCircle(guiGraphics, centerX + center.getX() * scale, centerY + center.getZ() * scale,
                    Math.max(2.0F, satelliteRadius), withAlpha(RING_COLOR_UNLOCKED, alpha * 0.5F), 1, false);
        }

        // Soft border circle (dashed, DANGER token — the one warning color), animated radius.
        if (borderRadius > 0.0D) {
            drawCircle(guiGraphics, centerX, centerY, (float) borderRadius * scale,
                    withAlpha(BORDER_COLOR, alpha * 0.9F), 1, true);
        }

        // Spawn / sanctum dot.
        guiGraphics.fill(centerX - 2, centerY - 2, centerX + 2, centerY + 2, withAlpha(MARKER_COLOR, alpha));

        // Stage-gated landmark markers on the annulus their stage revealed.
        for (Landmark landmark : LANDMARKS) {
            if (landmark.stage() > currentStage || landmark.stage() > maxStage) {
                continue; // never leak future structures
            }
            float outer = StageRadii.radius(DiscProfile.OVERWORLD, landmark.stage());
            float inner = StageRadii.radius(DiscProfile.OVERWORLD, landmark.stage() - 1);
            float radius = (inner + outer) / 2.0F * scale;
            double angle = Math.toRadians(landmark.angleDegrees());
            int markX = (int) (centerX + Math.cos(angle) * radius);
            int markY = (int) (centerY + Math.sin(angle) * radius);
            // Diamond marker.
            int diamond = withAlpha(MARKER_COLOR, alpha);
            guiGraphics.fill(markX - 1, markY - 3, markX + 1, markY + 3, diamond);
            guiGraphics.fill(markX - 3, markY - 1, markX + 3, markY + 1, diamond);
            // Labels center on the marker: clamp to what fits inside the page both ways
            // (the scissor would otherwise hard-chop long localizations mid-glyph).
            int labelMax = Math.max(12, 2 * Math.min(markX - x, x + width - markX));
            String label = ellipsize(font, EclipseLang.trString(landmark.labelKey()), labelMax);
            guiGraphics.drawCenteredString(font, label, markX, markY + 5, withAlpha(TEXT_COLOR, alpha));
        }
        guiGraphics.disableScissor();

        renderLegend(guiGraphics, y + height - legendHeight + EclipseUiTheme.GAP * 2, alpha);
    }

    private static final int[] LEGEND_COLORS = {RING_COLOR_UNLOCKED, RING_COLOR_FUTURE, BORDER_COLOR, MARKER_COLOR};
    private static final String[] LEGEND_KEYS = {
            "gui.eclipse.handbook.map.legend.unlocked",
            "gui.eclipse.handbook.map.legend.sealed",
            "gui.eclipse.handbook.map.legend.border",
            "gui.eclipse.handbook.map.legend.spawn"};

    private int legendEntryWidth(int index) {
        return LEGEND_SWATCH + LEGEND_TEXT_GAP + font.width(EclipseLang.trString(LEGEND_KEYS[index]))
                + LEGEND_ENTRY_GAP;
    }

    /** Rows the flow-wrapped legend needs at the current page width (localization-safe). */
    private int legendRows() {
        int rows = 1;
        int lineX = 0;
        for (int i = 0; i < LEGEND_KEYS.length; i++) {
            int entryWidth = legendEntryWidth(i);
            if (lineX > 0 && lineX + entryWidth > width) {
                rows++;
                lineX = 0;
            }
            lineX += entryWidth;
        }
        return rows;
    }

    /** Legend entries flow left-to-right and wrap so they never clip at the page edge. */
    private void renderLegend(GuiGraphics guiGraphics, int legendY, float alpha) {
        int lineX = x;
        int lineY = legendY;
        for (int i = 0; i < LEGEND_KEYS.length; i++) {
            int entryWidth = legendEntryWidth(i);
            if (lineX > x && lineX + entryWidth > x + width) {
                lineX = x;
                lineY += LEGEND_ROW;
            }
            guiGraphics.fill(lineX, lineY + 1, lineX + LEGEND_SWATCH, lineY + 1 + LEGEND_SWATCH,
                    withAlpha(LEGEND_COLORS[i], alpha));
            guiGraphics.drawString(font, EclipseLang.tr(LEGEND_KEYS[i]),
                    lineX + LEGEND_SWATCH + LEGEND_TEXT_GAP, lineY, withAlpha(DIM_COLOR, alpha));
            lineX += entryWidth;
        }
    }

    /** Dotted circle outline; {@code dashed} skips every other segment (soft border style). */
    private static void drawCircle(GuiGraphics guiGraphics, float centerX, float centerY, float radius,
            int color, int dotSize, boolean dashed) {
        if (radius < 2.0F) {
            return;
        }
        // Segment count follows the radius but stays bounded: a runaway radius must never
        // turn into a per-frame near-infinite fill loop (720 dots ring smoothly enough).
        int segments = Mth.clamp((int) (radius * 3.0F), 24, 720);
        for (int i = 0; i < segments; i++) {
            if (dashed && i % 4 >= 2) {
                continue;
            }
            double angle = i * Math.PI * 2 / segments;
            int dotX = Math.round(centerX + (float) Math.cos(angle) * radius);
            int dotY = Math.round(centerY + (float) Math.sin(angle) * radius);
            guiGraphics.fill(dotX, dotY, dotX + dotSize, dotY + dotSize, color);
        }
    }
}
