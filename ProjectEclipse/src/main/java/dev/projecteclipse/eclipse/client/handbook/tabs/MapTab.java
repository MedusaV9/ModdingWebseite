package dev.projecteclipse.eclipse.client.handbook.tabs;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Map page: stylized top-down concentric ring diagram of the overworld disc. Rings come
 * from the shared {@code worldgen.StageRadii} table (one circle per stage radius);
 * committed stages ({@code stage <= ClientStateCache.stageOverworld}) render lit, future
 * rings stay dim and unlabeled, the CURRENT stage ring is highlighted with a soft pulse.
 * On top: the stage-0 satellite player discs ({@code DiscGeometry}), the animated soft
 * border circle from the border cache, the spawn/sanctum dot and stage-gated landmark
 * markers (fixed default stage → structure mapping; positions are decorative, not world
 * coordinates). A legend anchors the bottom.
 */
@OnlyIn(Dist.CLIENT)
public class MapTab extends HandbookTab {
    private static final int RING_COLOR_UNLOCKED = ACCENT_COLOR;
    private static final int RING_COLOR_FUTURE = 0x453A5E;
    private static final int BORDER_COLOR = 0xE86AA8;

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
        int legendHeight = 34;
        int diagramHeight = height - legendHeight;
        int centerX = x + width / 2;
        int centerY = y + diagramHeight / 2 + 4;

        int currentStage = ClientStateCache.stageOverworld;
        int maxStage = StageRadii.maxStage(DiscProfile.OVERWORLD);
        double borderRadius = ClientStateCache.currentBorderRadius(false, Util.getMillis());

        float worldRadius = StageRadii.radius(DiscProfile.OVERWORLD, maxStage) * 1.08F;
        worldRadius = Math.max(worldRadius, (float) borderRadius * 1.05F);
        float scale = (Math.min(width, diagramHeight) / 2.0F - 6.0F) / worldRadius;

        guiGraphics.drawString(font, Component.translatable("gui.eclipse.handbook.map.stage", currentStage),
                x, y, withAlpha(ACCENT_COLOR, alpha));

        guiGraphics.enableScissor(x, y, x + width, y + height);

        // Stage rings, inner to outer.
        for (int stage = 0; stage <= maxStage; stage++) {
            boolean unlocked = stage <= currentStage;
            float radius = StageRadii.radius(DiscProfile.OVERWORLD, stage) * scale;
            float ringAlpha = unlocked ? alpha * 0.9F : alpha * 0.45F;
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

        // Soft border circle (dashed, warm accent), animated radius from the cache.
        if (borderRadius > 0.0D) {
            drawCircle(guiGraphics, centerX, centerY, (float) borderRadius * scale,
                    withAlpha(BORDER_COLOR, alpha * 0.9F), 1, true);
        }

        // Spawn / sanctum dot.
        guiGraphics.fill(centerX - 2, centerY - 2, centerX + 2, centerY + 2, withAlpha(0xFFFFFF, alpha));

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
            int diamond = withAlpha(0xF2E2FF, alpha);
            guiGraphics.fill(markX - 1, markY - 3, markX + 1, markY + 3, diamond);
            guiGraphics.fill(markX - 3, markY - 1, markX + 3, markY + 1, diamond);
            guiGraphics.drawCenteredString(font, Component.translatable(landmark.labelKey()),
                    markX, markY + 5, withAlpha(TEXT_COLOR, alpha));
        }
        guiGraphics.disableScissor();

        renderLegend(guiGraphics, y + height - legendHeight + 6, alpha);
    }

    private void renderLegend(GuiGraphics guiGraphics, int legendY, float alpha) {
        int lineX = x;
        lineX = legendEntry(guiGraphics, lineX, legendY, RING_COLOR_UNLOCKED,
                "gui.eclipse.handbook.map.legend.unlocked", alpha);
        lineX = legendEntry(guiGraphics, lineX, legendY, RING_COLOR_FUTURE,
                "gui.eclipse.handbook.map.legend.sealed", alpha);
        int secondY = legendY + 12;
        lineX = x;
        lineX = legendEntry(guiGraphics, lineX, secondY, BORDER_COLOR,
                "gui.eclipse.handbook.map.legend.border", alpha);
        legendEntry(guiGraphics, lineX, secondY, 0xFFFFFF, "gui.eclipse.handbook.map.legend.spawn", alpha);
    }

    private int legendEntry(GuiGraphics guiGraphics, int entryX, int entryY, int color, String key, float alpha) {
        guiGraphics.fill(entryX, entryY + 2, entryX + 6, entryY + 8, withAlpha(color, alpha));
        Component label = Component.translatable(key);
        guiGraphics.drawString(font, label, entryX + 9, entryY, withAlpha(DIM_COLOR, alpha));
        return entryX + 9 + font.width(label) + 10;
    }

    /** Dotted circle outline; {@code dashed} skips every other segment (soft border style). */
    private static void drawCircle(GuiGraphics guiGraphics, float centerX, float centerY, float radius,
            int color, int dotSize, boolean dashed) {
        if (radius < 2.0F) {
            return;
        }
        int segments = Math.max(24, (int) (radius * 3.0F));
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
