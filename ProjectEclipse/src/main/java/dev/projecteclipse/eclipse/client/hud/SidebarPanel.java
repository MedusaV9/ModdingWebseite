package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * The Eclipse sidebar status panel ({@code docs/ideas/03_ui_ux.md} §D): a right-anchored
 * 110px panel rendered ENTIRELY from {@link ClientStateCache} — vanilla scoreboard data is
 * never touched, so ops keep the scoreboard free for their own use. Rows: hearts, day,
 * altar level, online count and the personal goal tick list
 * ({@code S2CGoalProgressPayload}; all-false until W13 wires real goal ticking).
 *
 * <p>While this panel is on, a server-set vanilla sidebar objective is suppressed by
 * cancelling {@link RenderGuiLayerEvent.Pre} for {@link VanillaGuiLayers#SCOREBOARD_SIDEBAR}
 * — with {@code showSidebar=false} (honored live) the panel disappears and the vanilla
 * sidebar renders again. On any content change the panel re-slides in from the right
 * (skipped under {@code reducedFx}). Cutscene HUD suppression hides this layer like any
 * other non-whitelisted layer — intended.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SidebarPanel {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "sidebar_panel");

    private static final ResourceLocation PANEL = texture("panel");
    private static final ResourceLocation ICON_HEART = texture("icon_heart");
    private static final ResourceLocation ICON_DAY = texture("icon_day");
    private static final ResourceLocation ICON_ALTAR = texture("icon_altar");
    private static final ResourceLocation ICON_PLAYERS = texture("icon_players");
    private static final ResourceLocation ICON_GOAL = texture("icon_goal");

    private static final int PANEL_WIDTH = 110;
    private static final int ROW_HEIGHT = 12;
    private static final int PADDING = 4;
    /** Nine-slice corner size of {@code panel.png} (64x64, 8px corners). */
    private static final int SLICE = 8;
    private static final long SLIDE_MILLIS = 300L;

    private static final int TEXT_COLOR = 0xFFE8DEFF;
    private static final int MUTED_COLOR = 0xFFB0A6C8;
    private static final int DONE_COLOR = 0xFF9AF0B0;

    /** Hash of the last rendered content; any change restarts the slide-in. */
    private static int lastContentHash;
    private static long slideStartMillis;

    private SidebarPanel() {}

    /** Whether the Eclipse panel is currently replacing the vanilla sidebar. */
    private static boolean isActive() {
        Minecraft minecraft = Minecraft.getInstance();
        return EclipseClientConfig.showSidebar() && minecraft.level != null && minecraft.player != null;
    }

    /** Suppress a server-set vanilla sidebar objective while our panel is on. */
    @SubscribeEvent
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (event.getName().equals(VanillaGuiLayers.SCOREBOARD_SIDEBAR) && isActive()) {
            event.setCanceled(true);
        }
    }

    /** GUI-layer body, registered above {@code SCOREBOARD_SIDEBAR} by {@code EclipseGuiLayers}. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        if (!isActive()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();

        int lives = ClientStateCache.lives;
        int day = ClientStateCache.day;
        int altarLevel = ClientStateCache.altarLevel;
        int online = minecraft.getConnection() != null ? minecraft.getConnection().getOnlinePlayers().size() : 1;
        List<String> goals = ClientStateCache.goalLines.isEmpty() ? ClientStateCache.goals : ClientStateCache.goalLines;
        List<Boolean> done = ClientStateCache.goalDone;
        int doneCount = 0;
        for (int i = 0; i < goals.size(); i++) {
            if (i < done.size() && Boolean.TRUE.equals(done.get(i))) {
                doneCount++;
            }
        }

        int contentHash = Objects.hash(lives, day, altarLevel, online, goals, doneCount);
        long now = Util.getMillis();
        if (contentHash != lastContentHash) {
            lastContentHash = contentHash;
            slideStartMillis = now;
        }
        float slide = Mth.clamp((now - slideStartMillis) / (float) SLIDE_MILLIS, 0.0F, 1.0F);
        float eased = 1.0F - (1.0F - slide) * (1.0F - slide) * (1.0F - slide); // ease-out cubic
        int slideOffset = EclipseClientConfig.reducedFx() ? 0 : Math.round((1.0F - eased) * (PANEL_WIDTH + 8));

        List<Row> rows = new ArrayList<>();
        rows.add(new Row(ICON_HEART, Component.literal("\u2764 " + lives), null));
        rows.add(new Row(ICON_DAY, Component.translatable("gui.eclipse.artifact.day", day), null));
        rows.add(new Row(ICON_ALTAR, Component.translatable("sidebar.eclipse.altar", altarLevel), null));
        rows.add(new Row(ICON_PLAYERS, Component.translatable("sidebar.eclipse.online", online), null));
        rows.add(new Row(ICON_GOAL, Component.translatable("sidebar.eclipse.goals", doneCount, goals.size()), null));
        for (int i = 0; i < goals.size(); i++) {
            boolean ticked = i < done.size() && Boolean.TRUE.equals(done.get(i));
            rows.add(new Row(null, Component.literal(goals.get(i)), ticked));
        }

        int panelHeight = rows.size() * ROW_HEIGHT + PADDING * 2;
        int x = guiGraphics.guiWidth() - PANEL_WIDTH - 2 + slideOffset;
        int y = guiGraphics.guiHeight() / 2 - panelHeight / 2;

        drawNineSlice(guiGraphics, x, y, PANEL_WIDTH, panelHeight);

        int rowY = y + PADDING + 2;
        for (Row row : rows) {
            int textX = x + PADDING;
            if (row.icon() != null) {
                RenderSystem.enableBlend();
                guiGraphics.blit(row.icon(), textX, rowY - 2, 12, 12, 0.0F, 0.0F, 24, 24, 24, 24);
                RenderSystem.disableBlend();
                textX += 15;
            } else if (row.ticked() != null) {
                // Goal row: 7x7 tick box in place of an icon.
                int boxY = rowY - 1;
                guiGraphics.fill(textX + 1, boxY, textX + 8, boxY + 7, 0xA0140A24);
                if (row.ticked()) {
                    guiGraphics.fill(textX + 3, boxY + 2, textX + 6, boxY + 5, DONE_COLOR);
                }
                guiGraphics.fill(textX + 1, boxY, textX + 8, boxY + 1, 0xFF6E4FA8);
                guiGraphics.fill(textX + 1, boxY + 6, textX + 8, boxY + 7, 0xFF6E4FA8);
                textX += 12;
            }
            int color = row.ticked() == null ? TEXT_COLOR : (row.ticked() ? DONE_COLOR : MUTED_COLOR);
            String text = minecraft.font.plainSubstrByWidth(
                    row.text().getString(), PANEL_WIDTH - (textX - x) - PADDING);
            guiGraphics.drawString(minecraft.font, text, textX, rowY, color);
            rowY += ROW_HEIGHT;
        }
    }

    /** Manual nine-slice of the 64x64 panel texture ({@value #SLICE}px corners). */
    private static void drawNineSlice(GuiGraphics guiGraphics, int x, int y, int width, int height) {
        int tex = 64;
        int edge = tex - SLICE;
        RenderSystem.enableBlend();
        // Corners.
        guiGraphics.blit(PANEL, x, y, SLICE, SLICE, 0, 0, SLICE, SLICE, tex, tex);
        guiGraphics.blit(PANEL, x + width - SLICE, y, SLICE, SLICE, edge, 0, SLICE, SLICE, tex, tex);
        guiGraphics.blit(PANEL, x, y + height - SLICE, SLICE, SLICE, 0, edge, SLICE, SLICE, tex, tex);
        guiGraphics.blit(PANEL, x + width - SLICE, y + height - SLICE, SLICE, SLICE, edge, edge, SLICE, SLICE, tex, tex);
        // Edges (stretched).
        guiGraphics.blit(PANEL, x + SLICE, y, width - 2 * SLICE, SLICE, SLICE, 0, tex - 2 * SLICE, SLICE, tex, tex);
        guiGraphics.blit(PANEL, x + SLICE, y + height - SLICE, width - 2 * SLICE, SLICE,
                SLICE, edge, tex - 2 * SLICE, SLICE, tex, tex);
        guiGraphics.blit(PANEL, x, y + SLICE, SLICE, height - 2 * SLICE, 0, SLICE, SLICE, tex - 2 * SLICE, tex, tex);
        guiGraphics.blit(PANEL, x + width - SLICE, y + SLICE, SLICE, height - 2 * SLICE,
                edge, SLICE, SLICE, tex - 2 * SLICE, tex, tex);
        // Center (stretched).
        guiGraphics.blit(PANEL, x + SLICE, y + SLICE, width - 2 * SLICE, height - 2 * SLICE,
                SLICE, SLICE, tex - 2 * SLICE, tex - 2 * SLICE, tex, tex);
        RenderSystem.disableBlend();
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/sidebar/" + name + ".png");
    }

    /** One panel row: an optional 12x12 icon OR a goal tick box, plus the text. */
    private record Row(ResourceLocation icon, Component text, Boolean ticked) {}
}
