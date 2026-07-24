package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import net.minecraft.Util;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Quiet Eclipse sidebar v2. The panel consumes the server aggregate in
 * {@link ClientStateCache#sidebarDay} and companion payload-fed quest/buff caches; it never
 * computes or displays an online-player count.
 *
 * <p>LEFT/RIGHT anchoring, scale and overflow mode are live client settings. TAB (the
 * configured player-list key) morphs the edge card toward screen center for expanded detail.
 * Both vanilla sidebar and player-list layers stay suppressed while Eclipse's panel owns the
 * surface. F1 and {@code showSidebar=false} hide this layer exactly like vanilla HUD.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SidebarPanel {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "sidebar_panel");

    private static final ResourceLocation ICON_HEART = texture("icon_heart");
    private static final ResourceLocation ICON_DAY = texture("icon_day");
    private static final ResourceLocation ICON_ALTAR = texture("icon_altar");
    private static final ResourceLocation ICON_GOAL = texture("icon_goal");

    private static final int PANEL_WIDTH = 118;
    private static final int ROW_HEIGHT = 12;
    private static final int PADDING = 5;
    private static final int ICON_SIZE = 10;
    private static final int ICON_TEXT_INDENT = 14;
    private static final int GOAL_TEXT_INDENT = 12;
    private static final long SLIDE_MILLIS = 300L;
    private static final long TICK_SWEEP_MILLIS = 6L * 50L;

    private static int lastSlideHash = Integer.MIN_VALUE;
    private static long slideStartMillis;
    private static int lastRowsHash = Integer.MIN_VALUE;
    private static List<Row> cachedRows = List.of();
    private static final Map<String, Boolean> LAST_GOAL_DONE = new HashMap<>();
    private static final Map<String, Long> GOAL_SWEEP_STARTED = new HashMap<>();
    private static boolean hoveredLastFrame;
    private static long hoverStartMillis;

    private SidebarPanel() {}

    private static boolean isActive() {
        Minecraft minecraft = Minecraft.getInstance();
        return EclipseClientConfig.showSidebar()
                && minecraft.level != null
                && minecraft.player != null
                && !minecraft.options.hideGui;
    }

    /**
     * Suppresses both vanilla data surfaces while the Eclipse sidebar is active. The separate
     * anonymity hider also cancels TAB_LIST globally; keeping this guard local makes the TAB
     * expansion robust if that policy class changes later.
     */
    @SubscribeEvent
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (!isActive()) {
            return;
        }
        if (event.getName().equals(VanillaGuiLayers.SCOREBOARD_SIDEBAR)
                || event.getName().equals(VanillaGuiLayers.TAB_LIST)) {
            event.setCanceled(true);
        }
    }

    /** Client-session hygiene: no row/animation state may leak into the next server join. */
    @SubscribeEvent
    static void onLoggingOut(
            net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent.LoggingOut event) {
        lastSlideHash = Integer.MIN_VALUE;
        slideStartMillis = 0L;
        lastRowsHash = Integer.MIN_VALUE;
        cachedRows = List.of();
        LAST_GOAL_DONE.clear();
        GOAL_SWEEP_STARTED.clear();
        hoveredLastFrame = false;
        hoverStartMillis = 0L;
        SidebarExpanded.reset();
    }

    /** GUI-layer body registered by the existing GUI-layer hub. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        long now = Util.getMillis();
        if (!isActive()) {
            SidebarExpanded.update(false, EclipseClientConfig.reducedFx(), now);
            hoveredLastFrame = false;
            return;
        }

        boolean expansionRequested = minecraft.screen == null
                && minecraft.options.keyPlayerList.isDown();
        float expansion = SidebarExpanded.update(expansionRequested,
                EclipseClientConfig.reducedFx(), now);
        Font font = minecraft.font;
        float scale = (float) Mth.clamp(EclipseClientConfig.sidebarScale(), 0.6D, 1.4D);
        boolean leftSide = EclipseClientConfig.sidebarSide() == EclipseClientConfig.SidebarSide.LEFT;

        int slideHash = slideHash();
        if (slideHash != lastSlideHash) {
            lastSlideHash = slideHash;
            slideStartMillis = now;
        }
        float slideT = Mth.clamp((now - slideStartMillis) / (float) SLIDE_MILLIS, 0.0F, 1.0F);
        float slideEase = SidebarExpanded.easeOutCubic(slideT);
        float slideOffset = EclipseClientConfig.reducedFx()
                ? 0.0F : (1.0F - slideEase) * (PANEL_WIDTH + 8) * scale;

        int rowsHash = rowsHash(now);
        if (rowsHash != lastRowsHash) {
            lastRowsHash = rowsHash;
            cachedRows = buildRows();
        }
        updateGoalSweeps(now);
        int normalHeight = PADDING * 2 + cachedRows.size() * ROW_HEIGHT;

        // preferredHeight walks/splits every goal line; only pay for it while the TAB card
        // is actually (partially) expanded. Collapsed frames lerp toward normalHeight anyway.
        int expandedHeight = normalHeight;
        if (expansion > 0.0F || SidebarExpanded.visible()) {
            int maxExpandedHeight = Math.max(80,
                    (int) Math.floor((guiGraphics.guiHeight() - 8.0F) / scale));
            expandedHeight = Math.min(SidebarExpanded.preferredHeight(font), maxExpandedHeight);
        }

        float normalX = leftSide ? 3.0F
                : guiGraphics.guiWidth() - 3.0F - PANEL_WIDTH * scale;
        normalX += leftSide ? -slideOffset : slideOffset;
        float normalY = (guiGraphics.guiHeight() - normalHeight * scale) * 0.5F;
        float expandedX = (guiGraphics.guiWidth() - SidebarExpanded.WIDTH * scale) * 0.5F;
        float expandedY = (guiGraphics.guiHeight() - expandedHeight * scale) * 0.5F;

        float x = Mth.lerp(expansion, normalX, expandedX);
        float y = Mth.lerp(expansion, normalY, expandedY);
        int width = Math.round(Mth.lerp(expansion, PANEL_WIDTH, SidebarExpanded.WIDTH));
        int height = Math.round(Mth.lerp(expansion, normalHeight, expandedHeight));

        boolean hovered = mouseInside(minecraft, guiGraphics, x, y, width * scale, height * scale);
        if (hovered && !hoveredLastFrame) {
            hoverStartMillis = now;
        }
        hoveredLastFrame = hovered;
        boolean marqueeActive = hovered
                && expansion < 0.01F
                && EclipseClientConfig.sidebarOverflow() == EclipseClientConfig.SidebarOverflow.MARQUEE
                && !EclipseClientConfig.reducedFx();
        long marqueeMillis = marqueeActive ? Math.max(0L, now - hoverStartMillis) : 0L;

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(x, y, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        EclipseUiTheme.drawPanel(guiGraphics, 0, 0, width, height);

        float normalAlpha = 1.0F - smoothstep(0.16F, 0.58F, expansion);
        float expandedAlpha = smoothstep(0.52F, 0.92F, expansion);
        if (normalAlpha > 0.01F) {
            int originX = leftSide ? 0 : width - PANEL_WIDTH;
            renderCollapsed(guiGraphics, font, originX, normalHeight, normalAlpha, now,
                    marqueeMillis, marqueeActive, x, y, scale);
        }
        if (expandedAlpha > 0.01F) {
            SidebarExpanded.render(guiGraphics, font, width, height, expandedAlpha,
                    x, y, scale);
        }
        guiGraphics.pose().popPose();
    }

    private static void renderCollapsed(GuiGraphics guiGraphics, Font font, int originX,
            int normalHeight, float alpha, long now, long marqueeMillis, boolean marqueeActive,
            float panelScreenX, float panelScreenY, float scale) {
        int rowY = PADDING + 2;
        for (int i = 0; i < cachedRows.size(); i++) {
            Row row = cachedRows.get(i);
            int localX = originX + PADDING;
            if (row.icon() != null) {
                RenderSystem.enableBlend();
                guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
                guiGraphics.blit(row.icon(), localX, rowY - 1, ICON_SIZE, ICON_SIZE,
                        0.0F, 0.0F, 24, 24, 24, 24);
                guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
                RenderSystem.disableBlend();
                localX += ICON_TEXT_INDENT;
            } else {
                drawGoalBox(guiGraphics, localX, rowY, row, now, alpha);
                localX += GOAL_TEXT_INDENT;
            }

            int maxWidth = originX + PANEL_WIDTH - PADDING - localX;
            int color = row.goalDone() == null
                    ? EclipseUiTheme.TEXT
                    : (row.goalDone() ? EclipseUiTheme.GOOD : EclipseUiTheme.DIM);
            color = MarqueeText.faded(color, alpha);
            if (EclipseClientConfig.sidebarOverflow() == EclipseClientConfig.SidebarOverflow.ELLIPSIS) {
                guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, row.text(), maxWidth),
                        localX, rowY, color);
            } else {
                MarqueeText.render(guiGraphics, font, row.text(), localX, rowY, maxWidth,
                        color, marqueeMillis, row.phaseSalt(), marqueeActive,
                        screenFloor(panelScreenX + localX * scale),
                        screenFloor(panelScreenY + (rowY - 1) * scale),
                        screenCeil(panelScreenX + (localX + maxWidth) * scale),
                        screenCeil(panelScreenY + (rowY + font.lineHeight + 1) * scale));
            }
            rowY += ROW_HEIGHT;
            if (rowY > normalHeight - PADDING) {
                break;
            }
        }
    }

    private static void drawGoalBox(GuiGraphics guiGraphics, int x, int y, Row row,
            long now, float alpha) {
        int boxColor = MarqueeText.faded(EclipseUiTheme.HAIRLINE, alpha);
        guiGraphics.fill(x + 1, y, x + 8, y + 7, boxColor);
        guiGraphics.fill(x + 2, y + 1, x + 7, y + 6,
                MarqueeText.faded(EclipseUiTheme.PANEL_RAISED, alpha));
        if (!Boolean.TRUE.equals(row.goalDone())) {
            return;
        }
        long started = GOAL_SWEEP_STARTED.getOrDefault(row.id(), 0L);
        float sweep = started == 0L ? 1.0F
                : Mth.clamp((now - started) / (float) TICK_SWEEP_MILLIS, 0.0F, 1.0F);
        int fillWidth = Math.max(1, Math.round(5.0F * SidebarExpanded.easeOutCubic(sweep)));
        guiGraphics.fill(x + 2, y + 1, x + 2 + fillWidth, y + 6,
                MarqueeText.faded(EclipseUiTheme.GOOD, alpha));
    }

    private static List<Row> buildRows() {
        List<Row> rows = new ArrayList<>();
        String timer = SidebarExpanded.formatRemaining(SidebarExpanded.remainingMillis());
        rows.add(new Row("day", ICON_DAY,
                EclipseLang.trString("sidebar.eclipse.day_timer",
                        Math.max(1, ClientStateCache.sidebarDay), timer), null, 1));
        rows.add(new Row("hearts", ICON_HEART,
                EclipseLang.trString("sidebar.eclipse.hearts",
                        Math.max(0, ClientStateCache.lives)), null, 2));
        rows.add(new Row("altar", ICON_ALTAR,
                EclipseLang.trString("sidebar.eclipse.altar",
                        Math.max(0, ClientStateCache.sidebarAltarLevel)), null, 3));
        rows.add(new Row("mains", ICON_GOAL,
                EclipseLang.trString("sidebar.eclipse.goals",
                        safeDone(ClientStateCache.sidebarMainsDone, ClientStateCache.sidebarMainsTotal),
                        Math.max(0, ClientStateCache.sidebarMainsTotal)), null, 4));

        if (ClientStateCache.sidebarSidesTotal > 0 || ClientStateCache.sidebarPersonalsTotal > 0) {
            rows.add(new Row("optional", ICON_GOAL,
                    EclipseLang.trString("sidebar.eclipse.optional",
                            safeDone(ClientStateCache.sidebarSidesDone, ClientStateCache.sidebarSidesTotal),
                            Math.max(0, ClientStateCache.sidebarSidesTotal),
                            safeDone(ClientStateCache.sidebarPersonalsDone,
                                    ClientStateCache.sidebarPersonalsTotal),
                            Math.max(0, ClientStateCache.sidebarPersonalsTotal)), null, 5));
        }
        if (!ClientStateCache.sidebarBuffIds.isEmpty()) {
            rows.add(new Row("buffs", ICON_GOAL,
                    EclipseLang.trString("sidebar.eclipse.buffs",
                            Math.min(32, ClientStateCache.sidebarBuffIds.size())), null, 6));
        }

        if (ClientStateCache.questDay == ClientStateCache.sidebarDay) {
            int index = 0;
            for (S2CQuestStatePayload.QuestEntry goal : ClientStateCache.questEntries) {
                if (goal == null || goal.kind() != 0 || index >= 8) {
                    continue;
                }
                String text = EclipseLang.locale().startsWith("de") && !goal.textDe().isBlank()
                        ? goal.textDe() : goal.textEn();
                rows.add(new Row(goal.id(), null, text, goal.done(), 10 + index));
                index++;
            }
        }
        return List.copyOf(rows);
    }

    private static void updateGoalSweeps(long now) {
        for (Row row : cachedRows) {
            if (row.goalDone() == null) {
                continue;
            }
            boolean previous = LAST_GOAL_DONE.getOrDefault(row.id(), false);
            if (row.goalDone() && !previous) {
                GOAL_SWEEP_STARTED.put(row.id(), now);
            }
            LAST_GOAL_DONE.put(row.id(), row.goalDone());
        }
        GOAL_SWEEP_STARTED.entrySet().removeIf(entry -> now - entry.getValue() > TICK_SWEEP_MILLIS);
    }

    /** Major-content hash: progress/tick counters are deliberately excluded (B11). */
    private static int slideHash() {
        List<String> questIds = ClientStateCache.questDay == ClientStateCache.sidebarDay
                ? ClientStateCache.questEntries.stream()
                        .filter(Objects::nonNull)
                        .map(S2CQuestStatePayload.QuestEntry::id)
                        .toList()
                : List.of();
        return Objects.hash(ClientStateCache.sidebarDay,
                ClientStateCache.sidebarAltarLevel,
                ClientStateCache.sidebarSkillLevel,
                questIds,
                ClientStateCache.sidebarBuffIds,
                EclipseClientConfig.sidebarSide());
    }

    private static int rowsHash(long nowMillis) {
        return Objects.hash(
                ClientStateCache.sidebarDay,
                ClientStateCache.sidebarPaused,
                nowMillis / 1_000L,
                ClientStateCache.lives,
                ClientStateCache.sidebarAltarLevel,
                ClientStateCache.sidebarMainsDone,
                ClientStateCache.sidebarMainsTotal,
                ClientStateCache.sidebarSidesDone,
                ClientStateCache.sidebarSidesTotal,
                ClientStateCache.sidebarPersonalsDone,
                ClientStateCache.sidebarPersonalsTotal,
                ClientStateCache.sidebarBuffIds,
                ClientStateCache.questDay,
                ClientStateCache.questEntries,
                EclipseLang.generation());
    }

    private static int safeDone(int done, int total) {
        return Mth.clamp(done, 0, Math.max(0, total));
    }

    private static boolean mouseInside(Minecraft minecraft, GuiGraphics guiGraphics,
            float x, float y, float width, float height) {
        double mouseX = minecraft.mouseHandler.xpos()
                * guiGraphics.guiWidth() / minecraft.getWindow().getScreenWidth();
        double mouseY = minecraft.mouseHandler.ypos()
                * guiGraphics.guiHeight() / minecraft.getWindow().getScreenHeight();
        return mouseX >= x && mouseX < x + width && mouseY >= y && mouseY < y + height;
    }

    private static float smoothstep(float from, float to, float value) {
        if (to <= from) {
            return value >= to ? 1.0F : 0.0F;
        }
        float t = Mth.clamp((value - from) / (to - from), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }

    private static int screenFloor(float value) {
        return (int) Math.floor(value);
    }

    private static int screenCeil(float value) {
        return (int) Math.ceil(value);
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/gui/sidebar/" + name + ".png");
    }

    private record Row(String id, ResourceLocation icon, String text, Boolean goalDone,
            int phaseSalt) {}
}
