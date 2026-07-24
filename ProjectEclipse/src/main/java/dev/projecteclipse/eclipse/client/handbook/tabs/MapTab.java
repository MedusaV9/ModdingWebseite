package dev.projecteclipse.eclipse.client.handbook.tabs;

import com.mojang.blaze3d.platform.NativeImage;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.client.progression.ClientUnlockCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.progression.LandmarkDiscoveryService;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.client.renderer.texture.DynamicTexture;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Map page, wave-5 rework (plans_v5 PLAN-A §A6 — "explored-rings fog-of-war, sketch
 * style"): a hand-sketched parchment chart floating in the void, drawn only as far as the
 * expedition has actually gone.
 *
 * <ul>
 *   <li><b>Explored rings only.</b> The interior of the CURRENT committed stage is fully
 *       sketched (terrain sampled from the deterministic {@link DiscTerrainFunction}
 *       sampler — height contours, biome stipple hatching, rivers/pools). The NEXT ring
 *       exists only as a glitch-arc silhouette; beyond it there is nothing but void
 *       static. Future rings, the total world size and future landmarks never render.</li>
 *   <li><b>Landmark discovery.</b> Structure markers appear only once someone has stood
 *       near them: the server's {@code progression.LandmarkDiscoveryService} adds
 *       {@code landmark:<id>} keys to the existing unlock snapshot on proximity, and this
 *       tab consults {@link ClientUnlockCache#isKeyUnlocked}. Player markers and the
 *       central altar are always visible.</li>
 *   <li><b>Sketch cache.</b> Terrain is sampled ONCE into a {@link DynamicTexture}
 *       (2 texels per gui px, capped at {@value #MAX_TEX_SIZE}), filled progressively a
 *       few rows per frame under a strict per-frame budget, and re-used until the stage,
 *       page size or map data change — per-frame cost after the fill is one blit plus
 *       bounded vector overlays. No world access, no per-frame sampling.</li>
 * </ul>
 *
 * <p>Palette stays on {@link EclipseUiTheme} tokens: parchment tones are TEXT↔PANEL
 * blends, ink is HAIRLINE, water ACCENT_DEEP, the soft border DANGER, players ACCENT.
 * {@code reducedFx} freezes the static/glitch shimmer into calm dashes.</p>
 */
@OnlyIn(Dist.CLIENT)
public class MapTab extends HandbookTab {
    private static final int BORDER_COLOR = EclipseUiTheme.DANGER & 0xFFFFFF;
    private static final int INK_COLOR = EclipseUiTheme.HAIRLINE & 0xFFFFFF;
    private static final int MARKER_COLOR = TEXT_COLOR;
    private static final int ALTAR_COLOR = EclipseUiTheme.ACCENT_DEEP & 0xFFFFFF;

    // --- sketch palette (ARGB; theme-token blends, converted to ABGR at write time) ---
    private static final int PARCH_LIGHT = mixArgb(EclipseUiTheme.TEXT, EclipseUiTheme.PANEL, 0.12F);
    private static final int PARCH_DARK = mixArgb(EclipseUiTheme.TEXT, EclipseUiTheme.PANEL, 0.44F);
    private static final int PARCH_SNOW = mixArgb(EclipseUiTheme.TEXT, EclipseUiTheme.PANEL, 0.02F);
    private static final int INK_ARGB = EclipseUiTheme.HAIRLINE | 0xFF000000;
    private static final int WATER_ARGB = mixArgb(EclipseUiTheme.ACCENT_DEEP, EclipseUiTheme.PANEL, 0.30F);
    private static final int WATER_DARK_ARGB = mixArgb(EclipseUiTheme.ACCENT_DEEP, EclipseUiTheme.PANEL, 0.52F);

    /** Legend metrics (§2.2 rhythm): row height, swatch box, swatch→text and entry gaps. */
    private static final int LEGEND_ROW = 12;
    private static final int LEGEND_SWATCH = 6;
    private static final int LEGEND_TEXT_GAP = 4;
    private static final int LEGEND_ENTRY_GAP = 12;

    /** Contour interval in blocks of the sketch height lines. */
    private static final int CONTOUR_STEP = 8;
    /** Snow-cap sketch threshold (matches the terrain function's ~y150 snowline). */
    private static final int SNOWLINE_Y = 150;
    /** Texture resolution: texels per gui pixel (sample density; A6 quality bump). */
    private static final int TEX_PER_GUI_PX = 2;
    private static final int MAX_TEX_SIZE = 512;
    /** Progressive-fill budget: samples per frame AND a hard nanotime cap per frame. */
    private static final int FILL_SAMPLES_PER_FRAME = 4096;
    private static final long FILL_NANOS_PER_FRAME = 5_000_000L;
    /** GlitchText's 3-tick shimmer bucket (150 ms), reused for arc/static rolls. */
    private static final long ROLL_MILLIS = 150L;
    /** Void static speck count outside the charted world. */
    private static final int STATIC_SPECKS = 130;

    /** Reused roll source for static/glitch overlays (render thread only). */
    private static final RandomSource RANDOM = RandomSource.create();

    /** Ids of authored landmarks that are ambient events, not chartable structures. */
    private static boolean chartable(String landmarkId) {
        return !landmarkId.contains("fog_storm");
    }

    // ------------------------------------------------------------------
    // Cached terrain sketch (survives tab switches AND handbook reopen)
    // ------------------------------------------------------------------

    private static final ResourceLocation SKETCH_TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "handbook/map_sketch");

    /** One progressively-filled sketch; invalidated by stage / size / map-data changes. */
    private static final class Sketch {
        final DynamicTexture texture;
        final int texSize;
        final int stage;
        final float viewRadius;
        final DiscMapData map;
        final int[] prevRowHeights;
        int nextRow;

        Sketch(int texSize, int stage, float viewRadius, DiscMapData map) {
            this.texture = new DynamicTexture(texSize, texSize, true);
            this.texSize = texSize;
            this.stage = stage;
            this.viewRadius = viewRadius;
            this.map = map;
            this.prevRowHeights = new int[texSize];
            java.util.Arrays.fill(this.prevRowHeights, Integer.MIN_VALUE);
        }

        boolean matches(int texSize, int stage, float viewRadius, DiscMapData map) {
            return this.texSize == texSize && this.stage == stage && this.map == map
                    && Math.abs(this.viewRadius - viewRadius) < 0.5F;
        }
    }

    private static Sketch sketch;

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

        int maxStage = StageRadii.maxStage(DiscProfile.OVERWORLD);
        int currentStage = Mth.clamp(ClientStateCache.stageOverworld, 0, maxStage);
        double borderRadius = ClientStateCache.currentBorderRadius(false, Util.getMillis());

        // Explored extent: stage 0 reaches out to the satellite player discs; from stage 1
        // it is the fused disc of the CURRENT ring. The view is scaled to explored + the
        // next-ring silhouette ONLY — never the final world radius (that was the spoiler).
        float exploredR = currentStage <= 0
                ? DiscGeometry.PLAYER_DISC_RING_RADIUS + DiscGeometry.PLAYER_DISC_RADIUS
                : StageRadii.radius(DiscProfile.OVERWORLD, currentStage);
        float nextR = currentStage < maxStage
                ? StageRadii.radius(DiscProfile.OVERWORLD, currentStage + 1) : -1.0F;
        float viewRadius = Math.max(1.0F, Math.max(exploredR, nextR) * 1.08F);
        float scale = (Math.min(width, diagramHeight) / 2.0F - 6.0F) / viewRadius;

        guiGraphics.drawString(font,
                ellipsize(font, EclipseLang.trString("gui.eclipse.handbook.map.stage", currentStage), width),
                x, y, withAlpha(ACCENT_COLOR, alpha));

        guiGraphics.enableScissor(x, y, x + width, y + height);

        // 1) Void static: sparse shimmer specks outside the charted world (calm when reducedFx).
        drawVoidStatic(guiGraphics, centerX, centerY, diagramHeight, exploredR * scale, alpha);

        // 2) The cached parchment terrain sketch of the explored interior.
        int drawSide = Math.round(viewRadius * scale * 2.0F);
        if (drawSide > 8) {
            int texSize = Mth.clamp(drawSide * TEX_PER_GUI_PX, 64, MAX_TEX_SIZE);
            ensureSketch(texSize, currentStage, viewRadius);
            int blitX = Math.round(centerX - viewRadius * scale);
            int blitY = Math.round(centerY - viewRadius * scale);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
            guiGraphics.blit(SKETCH_TEXTURE, blitX, blitY, drawSide, drawSide,
                    0.0F, 0.0F, texSize, texSize, texSize, texSize);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        }

        // 3) Hairline ink seams of rings already explored (physical scars, no future info).
        for (int stage = 1; stage < currentStage; stage++) {
            drawCircle(guiGraphics, centerX, centerY,
                    StageRadii.radius(DiscProfile.OVERWORLD, stage) * scale,
                    withAlpha(INK_COLOR, alpha * 0.35F), 1, false);
        }

        // 4) Hand-drawn double-stroke ink rim on the explored edge + Veil static fringe.
        if (currentStage <= 0) {
            drawWobbleRing(guiGraphics, centerX, centerY, DiscGeometry.MAIN_DISC_RADIUS, scale, 0.0F,
                    withAlpha(INK_COLOR, alpha * 0.5F));
            drawWobbleRing(guiGraphics, centerX, centerY, DiscGeometry.MAIN_DISC_RADIUS, scale, 2.1F,
                    withAlpha(INK_COLOR, alpha * 0.35F));
            for (int i = 0; i < DiscGeometry.PLAYER_DISC_COUNT; i++) {
                BlockPos c = DiscGeometry.playerDiscCenter(i);
                drawWobbleRing(guiGraphics, centerX + c.getX() * scale, centerY + c.getZ() * scale,
                        DiscGeometry.PLAYER_DISC_RADIUS, scale, 1.3F + i,
                        withAlpha(INK_COLOR, alpha * 0.5F));
                drawStaticFringe(guiGraphics, centerX + c.getX() * scale, centerY + c.getZ() * scale,
                        DiscGeometry.PLAYER_DISC_RADIUS * scale, alpha * 0.8F, 31 + i);
            }
            drawStaticFringe(guiGraphics, centerX, centerY, DiscGeometry.MAIN_DISC_RADIUS * scale, alpha, 7);
        } else {
            drawWobbleRing(guiGraphics, centerX, centerY, exploredR, scale, 0.0F,
                    withAlpha(INK_COLOR, alpha * 0.5F));
            drawWobbleRing(guiGraphics, centerX, centerY, exploredR, scale, 2.1F,
                    withAlpha(INK_COLOR, alpha * 0.35F));
            drawStaticFringe(guiGraphics, centerX, centerY, exploredR * scale, alpha, 7);
        }

        // 5) NEXT ring: glitch-arc silhouette only — flickering dashes, a scrambled label,
        //    zero geometry beyond it. Clamped outside the explored extent (stage 0's
        //    satellites reach past the stage-1 fusion radius).
        if (nextR > 0.0F) {
            float arcR = Math.max(nextR, exploredR + 8.0F);
            drawGlitchArc(guiGraphics, centerX, centerY, arcR * scale, alpha);
            String hint = GlitchText.scramble(8, 421);
            int hintY = Math.max(y + 12, (int) (centerY - arcR * scale) - 10);
            guiGraphics.drawCenteredString(font, hint, centerX, hintY, withAlpha(DIM_COLOR, alpha * 0.6F));
        }

        // 6) Soft border circle (dashed, DANGER token — the one warning color), animated radius.
        if (borderRadius > 0.0D) {
            drawCircle(guiGraphics, centerX, centerY, (float) borderRadius * scale,
                    withAlpha(BORDER_COLOR, alpha * 0.9F), 1, true);
        }

        // 7) Hand-drawn compass rose (top-right of the diagram, below the header line).
        drawCompassRose(guiGraphics, x + width - 16, y + 28, alpha);

        // 8) Altar / spawn — ALWAYS visible.
        drawAltar(guiGraphics, centerX, centerY, alpha);

        // 9) Discovered landmarks only (real authored positions; never future/undiscovered).
        drawDiscoveredLandmarks(guiGraphics, centerX, centerY, scale, exploredR, alpha);

        // 10) Player markers — ALWAYS visible (self with facing tick, others as dots).
        drawPlayerMarkers(guiGraphics, centerX, centerY, scale, alpha);

        guiGraphics.disableScissor();

        renderLegend(guiGraphics, y + height - legendHeight + EclipseUiTheme.GAP * 2, alpha);
    }

    // ------------------------------------------------------------------
    // Terrain sketch cache
    // ------------------------------------------------------------------

    /** (Re)builds the cache when its key changed, then advances the progressive fill. */
    private void ensureSketch(int texSize, int stage, float viewRadius) {
        DiscMapData map = DiscMapData.get();
        Sketch current = sketch;
        if (current == null || !current.matches(texSize, stage, viewRadius, map)) {
            current = new Sketch(texSize, stage, viewRadius, map);
            // register() replaces AND closes any previous sketch texture safely.
            minecraft.getTextureManager().register(SKETCH_TEXTURE, current.texture);
            sketch = current;
        }
        if (current.nextRow < current.texSize) {
            fillSketchRows(current);
        }
    }

    /**
     * Fills a bounded batch of texture rows from the deterministic terrain sampler
     * ({@link DiscTerrainFunction#surfaceY} + {@link DiscMapData#biomeAt} +
     * {@link DiscMapData#riverDistance}) and uploads. Never exceeds
     * {@value #FILL_SAMPLES_PER_FRAME} samples or {@value #FILL_NANOS_PER_FRAME} ns per
     * frame, so the map "sketches itself in" over a few frames without hitching.
     */
    private static void fillSketchRows(Sketch s) {
        NativeImage pixels = s.texture.getPixels();
        if (pixels == null) {
            return;
        }
        long deadline = System.nanoTime() + FILL_NANOS_PER_FRAME;
        int budget = FILL_SAMPLES_PER_FRAME;
        double worldPerTexel = 2.0D * s.viewRadius / s.texSize;
        float exploredR = s.stage <= 0 ? DiscGeometry.MAIN_DISC_RADIUS
                : StageRadii.radius(DiscProfile.OVERWORLD, s.stage);
        int seaLevel = DiscProfile.OVERWORLD.seaLevel();

        while (s.nextRow < s.texSize && budget > 0 && System.nanoTime() < deadline) {
            int py = s.nextRow;
            double wz = -s.viewRadius + (py + 0.5D) * worldPerTexel;
            int leftHeight = Integer.MIN_VALUE;
            for (int px = 0; px < s.texSize; px++) {
                double wx = -s.viewRadius + (px + 0.5D) * worldPerTexel;
                float edgeDist = exploredEdgeDistance(s.stage, exploredR, wx, wz);
                if (edgeDist <= 0.0F) {
                    pixels.setPixelRGBA(px, py, 0);
                    s.prevRowHeights[px] = Integer.MIN_VALUE;
                    leftHeight = Integer.MIN_VALUE;
                    continue;
                }
                int bx = Mth.floor(wx);
                int bz = Mth.floor(wz);
                int h = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, bx, bz);
                boolean water = s.map.riverDistance(DiscProfile.OVERWORLD, wx, wz)
                        < DiscTerrainFunction.RIVER_HALF_WIDTH || h < seaLevel;
                int argb = sketchColor(s.map, wx, wz, px, py, h, water,
                        leftHeight, s.prevRowHeights[px]);
                // Soft 2-block alpha falloff against the void so the rim reads torn, not cut.
                int a = (int) (255.0F * Mth.clamp(edgeDist / 2.0F, 0.35F, 1.0F));
                pixels.setPixelRGBA(px, py, toAbgr(argb, a));
                s.prevRowHeights[px] = h;
                leftHeight = h;
            }
            budget -= s.texSize;
            s.nextRow++;
        }
        s.texture.upload();
    }

    /**
     * Distance in blocks from (wx, wz) to the explored edge (positive = inside), with a
     * deterministic hand-wobble so the sketch boundary meanders like an ink stroke.
     * Stage 0 = main disc + the eight satellite player discs; stage 1+ = the fused ring.
     */
    private static float exploredEdgeDistance(int stage, float exploredR, double wx, double wz) {
        double r = Math.sqrt(wx * wx + wz * wz);
        double angle = Math.atan2(wz, wx);
        if (stage > 0) {
            return (float) (exploredR + rimWobble(angle, 0.0F) - r);
        }
        float best = (float) (DiscGeometry.MAIN_DISC_RADIUS + rimWobble(angle, 0.0F) - r);
        for (int i = 0; i < DiscGeometry.PLAYER_DISC_COUNT; i++) {
            BlockPos c = DiscGeometry.playerDiscCenter(i);
            double dx = wx - c.getX();
            double dz = wz - c.getZ();
            double sr = Math.sqrt(dx * dx + dz * dz);
            double sa = Math.atan2(dz, dx);
            best = Math.max(best,
                    (float) (DiscGeometry.PLAYER_DISC_RADIUS + rimWobble(sa, 1.3F + i) - sr));
        }
        return best;
    }

    /** Fixed two-octave sine wobble (±~3 blocks) — deterministic, no noise objects needed. */
    private static double rimWobble(double angleRad, float phase) {
        return Math.sin(angleRad * 7.0D + 1.7D + phase) * 2.0D
                + Math.sin(angleRad * 17.0D + 0.5D + phase * 1.9D) * 1.2D;
    }

    /** Parchment sketch shade of one sample: height tone, biome stipple, contours, water. */
    private static int sketchColor(DiscMapData map, double wx, double wz, int px, int py,
            int h, boolean water, int leftHeight, int upHeight) {
        if (water) {
            return ((px + (py << 1)) & 3) < 2 ? WATER_ARGB : WATER_DARK_ARGB;
        }
        float heightT = Mth.clamp((h - 63) / 40.0F, 0.0F, 1.0F) * 0.6F
                + Mth.clamp((h - 110) / 170.0F, 0.0F, 1.0F) * 0.4F;
        int base = mixArgb(PARCH_LIGHT, PARCH_DARK, heightT);
        if (h >= SNOWLINE_Y) {
            base = mixArgb(base, PARCH_SNOW, 0.6F);
        } else if (hash01(3, px, py) < stippleDensity(map.biomeAt(DiscProfile.OVERWORLD, wx, wz))) {
            base = mixArgb(base, INK_ARGB, 0.35F);
        }
        // Height contour ink lines: bucket steps against the left/up neighbour samples.
        int bucket = Math.floorDiv(h, CONTOUR_STEP);
        boolean contour = (leftHeight != Integer.MIN_VALUE && Math.floorDiv(leftHeight, CONTOUR_STEP) != bucket)
                || (upHeight != Integer.MIN_VALUE && Math.floorDiv(upHeight, CONTOUR_STEP) != bucket);
        if (contour) {
            base = mixArgb(base, INK_ARGB, bucket % 4 == 0 ? 0.85F : 0.6F);
        }
        return base;
    }

    /** Ink stipple density per biome family — sketch texture instead of hue spoilage. */
    private static float stippleDensity(String biomeId) {
        if (biomeId.contains("jungle") || biomeId.contains("dark_forest") || biomeId.contains("mangrove")) {
            return 0.22F;
        }
        if (biomeId.contains("forest") || biomeId.contains("taiga") || biomeId.contains("swamp")
                || biomeId.contains("grove")) {
            return 0.14F;
        }
        if (biomeId.contains("snowy") || biomeId.contains("frozen") || biomeId.contains("peaks")
                || biomeId.contains("ice")) {
            return 0.02F;
        }
        if (biomeId.contains("desert") || biomeId.contains("badlands") || biomeId.contains("beach")) {
            return 0.04F;
        }
        return 0.07F; // plains / savanna / meadow — light grassland stipple
    }

    // ------------------------------------------------------------------
    // Vector overlays
    // ------------------------------------------------------------------

    /** Sparse void static outside the charted radius (GlitchText's 150 ms shimmer bucket). */
    private void drawVoidStatic(GuiGraphics guiGraphics, int centerX, int centerY,
            int diagramHeight, float exploredRadiusPx, float alpha) {
        long seed = EclipseClientConfig.reducedFx() ? 9176L
                : Util.getMillis() / ROLL_MILLIS * 31L + 9176L;
        RANDOM.setSeed(seed);
        float minDistSq = (exploredRadiusPx + 4.0F) * (exploredRadiusPx + 4.0F);
        for (int i = 0; i < STATIC_SPECKS; i++) {
            int sx = x + RANDOM.nextInt(Math.max(1, width));
            int sy = y + 10 + RANDOM.nextInt(Math.max(1, diagramHeight - 10));
            float dx = sx - centerX;
            float dy = sy - centerY;
            float speckAlpha = 0.05F + RANDOM.nextFloat() * 0.16F;
            if (dx * dx + dy * dy < minDistSq) {
                continue; // never sprinkle static over charted ground
            }
            guiGraphics.fill(sx, sy, sx + 1, sy + 1, withAlpha(TEXT_COLOR, alpha * speckAlpha));
        }
    }

    /** Torn static fringe just outside a charted rim (the Veil chewing at the map edge). */
    private void drawStaticFringe(GuiGraphics guiGraphics, float centerX, float centerY,
            float radiusPx, float alpha, int salt) {
        if (radiusPx < 4.0F) {
            return;
        }
        int bucket = EclipseClientConfig.reducedFx() ? 0
                : (int) (Util.getMillis() / ROLL_MILLIS & 0x7FFFFFFF);
        int segments = Mth.clamp((int) (radiusPx * 2.5F), 32, 540);
        for (int i = 0; i < segments; i++) {
            float roll = hash01(salt + bucket * 31, i, 113);
            if (roll > 0.4F) {
                continue; // sparse, torn — not a solid ring
            }
            double angle = i * Math.PI * 2 / segments;
            float jitter = 1.5F + hash01(salt + bucket * 31, i, 977) * 4.5F;
            int dotX = Math.round(centerX + (float) Math.cos(angle) * (radiusPx + jitter));
            int dotY = Math.round(centerY + (float) Math.sin(angle) * (radiusPx + jitter));
            guiGraphics.fill(dotX, dotY, dotX + 1, dotY + 1,
                    withAlpha(DIM_COLOR, alpha * (0.15F + roll * 0.5F)));
        }
    }

    /** The NEXT ring as a flickering glitch-arc silhouette (no radius text, no fill). */
    private void drawGlitchArc(GuiGraphics guiGraphics, int centerX, int centerY,
            float radiusPx, float alpha) {
        if (radiusPx < 4.0F) {
            return;
        }
        int bucket = EclipseClientConfig.reducedFx() ? 0
                : (int) (Util.getMillis() / ROLL_MILLIS & 0x7FFFFFFF);
        int segments = Mth.clamp((int) (radiusPx * 2.5F), 40, 560);
        for (int i = 0; i < segments; i++) {
            float roll = hash01(bucket * 31 + 77, i, 501);
            if (roll > 0.55F) {
                continue; // broken transmission — most of the arc is missing
            }
            double angle = i * Math.PI * 2 / segments;
            float jitter = (hash01(bucket * 31 + 78, i, 502) - 0.5F) * 3.0F;
            int dotX = Math.round(centerX + (float) Math.cos(angle) * (radiusPx + jitter));
            int dotY = Math.round(centerY + (float) Math.sin(angle) * (radiusPx + jitter));
            // Rare radial "spike" dashes sell the static; everything else is 1px dots.
            if (roll < 0.05F) {
                int endX = Math.round(centerX + (float) Math.cos(angle) * (radiusPx + jitter + 3.0F));
                int endY = Math.round(centerY + (float) Math.sin(angle) * (radiusPx + jitter + 3.0F));
                guiGraphics.fill(Math.min(dotX, endX), Math.min(dotY, endY),
                        Math.max(dotX, endX) + 1, Math.max(dotY, endY) + 1,
                        withAlpha(DIM_COLOR, alpha * 0.6F));
            } else {
                guiGraphics.fill(dotX, dotY, dotX + 1, dotY + 1, withAlpha(DIM_COLOR, alpha * 0.55F));
            }
        }
    }

    /** Small hand-drawn compass rose: ink cross + N/E/S/W (localized — German O for east). */
    private void drawCompassRose(GuiGraphics guiGraphics, int cx, int cy, float alpha) {
        int ink = withAlpha(DIM_COLOR, alpha * 0.8F);
        guiGraphics.fill(cx, cy - 6, cx + 1, cy + 7, ink);
        guiGraphics.fill(cx - 6, cy, cx + 7, cy + 1, ink);
        for (int d = -1; d <= 1; d += 2) {
            guiGraphics.fill(cx + d * 3, cy + d * 3, cx + d * 3 + 1, cy + d * 3 + 1, ink);
            guiGraphics.fill(cx + d * 3, cy - d * 3, cx + d * 3 + 1, cy - d * 3 + 1, ink);
        }
        int letter = withAlpha(TEXT_COLOR, alpha * 0.9F);
        guiGraphics.drawCenteredString(font,
                EclipseLang.trString("gui.eclipse.handbook.map.compass.n"), cx, cy - 16, letter);
        guiGraphics.drawCenteredString(font,
                EclipseLang.trString("gui.eclipse.handbook.map.compass.s"), cx, cy + 9, letter);
        guiGraphics.drawString(font,
                EclipseLang.trString("gui.eclipse.handbook.map.compass.e"), cx + 9, cy - 4, letter);
        String west = EclipseLang.trString("gui.eclipse.handbook.map.compass.w");
        guiGraphics.drawString(font, west, cx - 9 - font.width(west), cy - 4, letter);
    }

    /** Tiny ziggurat glyph + label for the central altar/spawn (always visible). */
    private void drawAltar(GuiGraphics guiGraphics, int centerX, int centerY, float alpha) {
        int glyph = withAlpha(ALTAR_COLOR, alpha);
        guiGraphics.fill(centerX - 3, centerY, centerX + 3, centerY + 2, glyph);
        guiGraphics.fill(centerX - 2, centerY - 2, centerX + 2, centerY, glyph);
        guiGraphics.fill(centerX - 1, centerY - 4, centerX + 1, centerY - 2, glyph);
        guiGraphics.fill(centerX, centerY - 5, centerX + 1, centerY - 4, withAlpha(TEXT_COLOR, alpha));
        guiGraphics.drawCenteredString(font,
                ellipsize(font, EclipseLang.trString("gui.eclipse.handbook.map.altar"), 60),
                centerX, centerY + 4, withAlpha(DIM_COLOR, alpha * 0.9F));
    }

    /**
     * Diamond markers for landmarks the party has ACTUALLY visited: authored map
     * positions, gated on the server-synced {@code landmark:<id>} unlock keys and clamped
     * to the explored radius (an admin stage rollback must not leave markers in the
     * static). Undiscovered structures render nothing at all — not even a tease.
     */
    private void drawDiscoveredLandmarks(GuiGraphics guiGraphics, int centerX, int centerY,
            float scale, float exploredR, float alpha) {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.OVERWORLD)) {
            if (!chartable(landmark.id())
                    || !ClientUnlockCache.isKeyUnlocked(LandmarkDiscoveryService.KEY_PREFIX + landmark.id())) {
                continue;
            }
            double dist = Math.sqrt((double) landmark.x() * landmark.x()
                    + (double) landmark.z() * landmark.z());
            if (dist > exploredR + DiscTerrainFunction.RIM_NOISE_AMP) {
                continue;
            }
            int markX = Math.round(centerX + landmark.x() * scale);
            int markY = Math.round(centerY + landmark.z() * scale);
            int diamond = withAlpha(MARKER_COLOR, alpha);
            guiGraphics.fill(markX - 1, markY - 3, markX + 1, markY + 3, diamond);
            guiGraphics.fill(markX - 3, markY - 1, markX + 3, markY + 1, diamond);
            // Labels center on the marker: clamp to what fits inside the page both ways
            // (the scissor would otherwise hard-chop long localizations mid-glyph).
            int labelMax = Math.max(12, 2 * Math.min(markX - x, x + width - markX));
            String path = landmark.id().substring(landmark.id().indexOf(':') + 1);
            String label = ellipsize(font,
                    EclipseLang.trString("gui.eclipse.handbook.map.landmark." + path), labelMax);
            guiGraphics.drawCenteredString(font, label, markX, markY + 5, withAlpha(TEXT_COLOR, alpha));
        }
    }

    /** Self = accent dot + facing tick; other overworld players = small text-tone dots. */
    private void drawPlayerMarkers(GuiGraphics guiGraphics, int centerX, int centerY,
            float scale, float alpha) {
        if (minecraft.level == null || minecraft.level.dimension() != Level.OVERWORLD) {
            return;
        }
        for (AbstractClientPlayer player : minecraft.level.players()) {
            int px = Math.round(centerX + (float) player.getX() * scale);
            int py = Math.round(centerY + (float) player.getZ() * scale);
            if (player == minecraft.player) {
                float yaw = player.getYRot() * Mth.DEG_TO_RAD;
                int tipX = Math.round(px + -Mth.sin(yaw) * 4.0F);
                int tipY = Math.round(py + Mth.cos(yaw) * 4.0F);
                guiGraphics.fill(Math.min(px, tipX), Math.min(py, tipY),
                        Math.max(px, tipX) + 1, Math.max(py, tipY) + 1,
                        withAlpha(ACCENT_COLOR, alpha * 0.7F));
                guiGraphics.fill(px - 2, py - 2, px + 2, py + 2, withAlpha(ACCENT_COLOR, alpha));
            } else {
                guiGraphics.fill(px - 1, py - 1, px + 1, py + 1, withAlpha(MARKER_COLOR, alpha * 0.9F));
            }
        }
    }

    // ------------------------------------------------------------------
    // Legend
    // ------------------------------------------------------------------

    private static final int[] LEGEND_COLORS = {
            mixArgb(PARCH_LIGHT, PARCH_DARK, 0.5F) & 0xFFFFFF,
            DIM_COLOR,
            BORDER_COLOR,
            ALTAR_COLOR,
            ACCENT_COLOR,
            MARKER_COLOR};
    private static final String[] LEGEND_KEYS = {
            "gui.eclipse.handbook.map.legend.explored",
            "gui.eclipse.handbook.map.legend.veiled",
            "gui.eclipse.handbook.map.legend.border",
            "gui.eclipse.handbook.map.legend.altar",
            "gui.eclipse.handbook.map.legend.players",
            "gui.eclipse.handbook.map.legend.landmark"};

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

    // ------------------------------------------------------------------
    // Small drawing / color helpers
    // ------------------------------------------------------------------

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

    /** Ink circle following the same hand-wobble as the sketch mask (matched rims). */
    private static void drawWobbleRing(GuiGraphics guiGraphics, float centerX, float centerY,
            float worldRadius, float scale, float phase, int color) {
        float radiusPx = worldRadius * scale;
        if (radiusPx < 2.0F) {
            return;
        }
        int segments = Mth.clamp((int) (radiusPx * 3.0F), 32, 720);
        for (int i = 0; i < segments; i++) {
            double angle = i * Math.PI * 2 / segments;
            float rr = (float) ((worldRadius + rimWobble(angle, phase)) * scale);
            int dotX = Math.round(centerX + (float) Math.cos(angle) * rr);
            int dotY = Math.round(centerY + (float) Math.sin(angle) * rr);
            guiGraphics.fill(dotX, dotY, dotX + 1, dotY + 1, color);
        }
    }

    /** Deterministic 0..1 hash (avalanche mix) for stipple/static rolls. */
    private static float hash01(int salt, int a, int b) {
        int h = a * 0x2545F491 ^ b * 0x9E3779B9 ^ salt * 0x85EBCA6B;
        h ^= h >>> 15;
        h *= 0x2C1B3C6D;
        h ^= h >>> 12;
        h *= 0x297A2D39;
        h ^= h >>> 15;
        return (h >>> 8) * (1.0F / (1 << 24));
    }

    /** Per-channel ARGB lerp ({@code t}=0 → {@code from}). */
    private static int mixArgb(int from, int to, float t) {
        int a = Math.round(Mth.lerp(t, from >>> 24, to >>> 24));
        int r = Math.round(Mth.lerp(t, from >> 16 & 0xFF, to >> 16 & 0xFF));
        int g = Math.round(Mth.lerp(t, from >> 8 & 0xFF, to >> 8 & 0xFF));
        int b = Math.round(Mth.lerp(t, from & 0xFF, to & 0xFF));
        return a << 24 | r << 16 | g << 8 | b;
    }

    /** ARGB → {@link NativeImage} ABGR with an explicit alpha. */
    private static int toAbgr(int argb, int alpha) {
        int r = argb >> 16 & 0xFF;
        int g = argb >> 8 & 0xFF;
        int b = argb & 0xFF;
        return alpha << 24 | b << 16 | g << 8 | r;
    }
}
