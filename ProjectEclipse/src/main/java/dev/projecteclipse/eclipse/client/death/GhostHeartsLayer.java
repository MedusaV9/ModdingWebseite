package dev.projecteclipse.eclipse.client.death;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Ghost health bar (P3 §3.7, WB-DEATH): while the player is an event-banned ghost
 * (synced {@code lives <= 0}), the vanilla {@code PLAYER_HEALTH} layer is cancelled
 * ({@code SidebarPanel} precedent) and {@value #GHOST_HEART_COUNT} translucent, cracked
 * ghost hearts render in its place over the hotbar, with a DIM "GEIST" tag. On revive
 * ({@code S2CRevivedPayload} → {@link #beginReviveBurst}) the ghost hearts burst upward
 * one by one — {@value #BURST_STAGGER_TICKS} ticks apart, each with
 * {@link UiSounds#ghostBurst()} — before the real heart row returns.
 *
 * <p>Self-registered: both the GUI layer ({@code RegisterGuiLayersEvent}, mod bus) and the
 * health-cancel hook ({@code RenderGuiLayerEvent.Pre}, game bus) live here — the shared
 * {@code EclipseGuiLayers} hub and {@code client/hud/**} stay untouched (auto-routing
 * {@code @EventBusSubscriber}, the P6-W3 convention).</p>
 *
 * <p><b>Release timing:</b> {@code BanService.unban} syncs {@code lives = 1} a moment
 * before {@code S2CRevivedPayload} arrives, so the layer holds the ghost render through a
 * short {@link #PENDING_REVIVE_GRACE_TICKS} grace instead of flashing vanilla hearts; if
 * no revive payload ever arrives (admin {@code /eclipse} lives edit) it releases after the
 * grace. F1 ({@code hideGui}) is respected; the tick driver keeps running so animations
 * expire on schedule.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GhostHeartsLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ghost_hearts");

    /** Ghosts always show a full (cracked) row — the wireframe's five hearts. */
    public static final int GHOST_HEART_COUNT = 5;

    private static final ResourceLocation HEART_CONTAINER_SPRITE =
            ResourceLocation.withDefaultNamespace("hud/heart/container");
    private static final ResourceLocation HEART_GHOST_SPRITE =
            ResourceLocation.withDefaultNamespace("hud/heart/frozen_full");

    /** Vanilla single-row health baseline (ghosts have exactly one row, no absorption). */
    private static final int ROW_BOTTOM_OFFSET = 39;
    private static final int HEART_STEP = 8;
    private static final int HEART_SIZE = 9;
    /** Vanilla health-layer leftHeight increment for one heart row (restored on cancel). */
    private static final int LEFT_HEIGHT_COMPENSATION = 10;

    private static final float GHOST_HEART_ALPHA = 0.62F;
    private static final int FADE_IN_TICKS = 12;
    /** Crack hairlines inside a ghost heart (translucent near-black aubergine). */
    private static final int CRACK_COLOR = 0x8C0A0614;

    static final int BURST_STAGGER_TICKS = 8;
    private static final int BURST_LEN_TICKS = 12;
    /** Idle beat after the last heart burst before vanilla hearts return. */
    private static final int BURST_TAIL_TICKS = 10;
    private static final int BURST_TOTAL_TICKS =
            (GHOST_HEART_COUNT - 1) * BURST_STAGGER_TICKS + BURST_LEN_TICKS + BURST_TAIL_TICKS;

    /** Per-heart burst sparks: {angle°, radius px}. Upward-biased fountain. */
    private static final float[][] BURST_SPARKS = {
            {250.0F, 10.0F}, {275.0F, 13.0F}, {295.0F, 11.0F}, {225.0F, 8.0F}, {315.0F, 9.0F}
    };
    private static final int SPARK_HOT = 0xFFFFFFFF;
    /** Violet cool-down, the heart-burst emitter gradient family (#C77DFF). */
    private static final int SPARK_VIOLET = 0xFFC77DFF;

    /** Waiting-for-revive-payload grace after lives flips 0 → positive. */
    private static final int PENDING_REVIVE_GRACE_TICKS = 40;

    private enum Mode { IDLE, GHOST, PENDING_REVIVE, BURST }

    private static Mode mode = Mode.IDLE;
    private static int modeTicks;
    /** Index of the next heart whose burst sound has not fired yet (BURST mode). */
    private static int nextBurstSound;

    private GhostHeartsLayer() {}

    // ------------------------------------------------------------------ public seam

    /** {@code S2CRevivedPayload} entry (via {@link DeathFlowController}): start the one-by-one burst. */
    public static void beginReviveBurst(int heartsRestored) {
        if (mode == Mode.BURST) {
            return;
        }
        if (mode == Mode.IDLE && ClientStateCache.lives <= 0) {
            // Payload raced ahead of the lives sync — still celebrate.
            mode = Mode.GHOST;
        }
        if (mode == Mode.GHOST || mode == Mode.PENDING_REVIVE) {
            mode = Mode.BURST;
            modeTicks = 0;
            nextBurstSound = 0;
        }
    }

    /**
     * One translucent cracked ghost heart (container + frozen heart + crack hairlines) —
     * shared with {@link EclipseDeathScreen}'s ghost row. {@code size} must be a multiple
     * of {@value #HEART_SIZE} for crisp cracks (9 on the HUD, 18 on the screen).
     */
    public static void drawGhostHeart(GuiGraphics guiGraphics, int x, int y, int size, float alpha) {
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha * 0.85F);
        guiGraphics.blitSprite(HEART_CONTAINER_SPRITE, x, y, size, size);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blitSprite(HEART_GHOST_SPRITE, x, y, size, size);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        int unit = size / HEART_SIZE;
        int crack = EclipseUiTheme.withAlpha(CRACK_COLOR, alpha);
        guiGraphics.fill(x + 4 * unit, y + 2 * unit, x + 5 * unit, y + 4 * unit, crack);
        guiGraphics.fill(x + 3 * unit, y + 4 * unit, x + 4 * unit, y + 6 * unit, crack);
        guiGraphics.fill(x + 5 * unit, y + 5 * unit, x + 6 * unit, y + 7 * unit, crack);
        RenderSystem.disableBlend();
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAbove(VanillaGuiLayers.PLAYER_HEALTH, LAYER_ID, GhostHeartsLayer::render);
    }

    /**
     * Replaces (never stacks with) the vanilla hearts while the ghost row owns the slot.
     * {@code leftHeight} is compensated so armor/vehicle rows keep their vanilla position.
     */
    @SubscribeEvent
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (mode != Mode.IDLE && event.getName().equals(VanillaGuiLayers.PLAYER_HEALTH)) {
            event.setCanceled(true);
            Minecraft.getInstance().gui.leftHeight += LEFT_HEIGHT_COMPENSATION;
        }
    }

    // ------------------------------------------------------------------ state driver

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            mode = Mode.IDLE;
            modeTicks = 0;
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        modeTicks++;
        boolean ghostLives = ClientStateCache.lives <= 0;
        switch (mode) {
            case IDLE -> {
                if (ghostLives) {
                    mode = Mode.GHOST;
                    modeTicks = 0;
                }
            }
            case GHOST -> {
                if (!ghostLives) {
                    // Revive sync order: lives=1 lands just before S2CRevivedPayload — hold.
                    mode = Mode.PENDING_REVIVE;
                    modeTicks = 0;
                }
            }
            case PENDING_REVIVE -> {
                if (ghostLives) {
                    mode = Mode.GHOST;
                    modeTicks = 0;
                } else if (modeTicks >= PENDING_REVIVE_GRACE_TICKS) {
                    mode = Mode.IDLE; // no celebration came (plain lives edit) — release
                    modeTicks = 0;
                }
            }
            case BURST -> {
                int due = Math.min(GHOST_HEART_COUNT - 1, modeTicks / BURST_STAGGER_TICKS);
                while (nextBurstSound <= due) {
                    UiSounds.ghostBurst();
                    nextBurstSound++;
                }
                if (modeTicks >= BURST_TOTAL_TICKS) {
                    mode = ghostLives ? Mode.GHOST : Mode.IDLE;
                    modeTicks = 0;
                }
            }
            default -> { }
        }
    }

    // ------------------------------------------------------------------ layer body

    /** GUI-layer body (self-registered above {@code PLAYER_HEALTH}). Draws nothing under F1. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (mode == Mode.IDLE || minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        float time = modeTicks + deltaTracker.getGameTimeDeltaPartialTick(false);
        int rowX = guiGraphics.guiWidth() / 2 - 91;
        int rowY = guiGraphics.guiHeight() - ROW_BOTTOM_OFFSET;

        float rowAlpha = mode == Mode.GHOST
                ? GHOST_HEART_ALPHA * Mth.clamp(time / FADE_IN_TICKS, 0.0F, 1.0F)
                : GHOST_HEART_ALPHA;

        for (int i = 0; i < GHOST_HEART_COUNT; i++) {
            int x = rowX + i * HEART_STEP;
            if (mode == Mode.BURST) {
                float local = time - i * BURST_STAGGER_TICKS;
                if (local >= BURST_LEN_TICKS) {
                    continue; // burst finished — this slot is gone (real hearts follow)
                }
                if (local >= 0.0F) {
                    drawBurstingHeart(guiGraphics, x, rowY, local);
                    continue;
                }
            }
            drawGhostHeart(guiGraphics, x, rowY, HEART_SIZE, rowAlpha);
        }

        if (mode != Mode.BURST) {
            String tag = EclipseLang.trString("gui.eclipse.death.ghost_tag");
            guiGraphics.drawString(minecraft.font, tag,
                    rowX + GHOST_HEART_COUNT * HEART_STEP + 5, rowY + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, rowAlpha));
        }
    }

    /**
     * One heart mid-burst: it lifts, swells slightly and fades over
     * {@value #BURST_LEN_TICKS} ticks while a small deterministic spark fountain pops
     * upward above the hotbar (pure function of {@code local} — allocation-free).
     */
    private static void drawBurstingHeart(GuiGraphics guiGraphics, int x, int y, float local) {
        float progress = local / BURST_LEN_TICKS;
        float alpha = GHOST_HEART_ALPHA * (1.0F - progress);
        int lift = Mth.floor(progress * 6.0F);
        if (alpha > 0.03F) {
            drawGhostHeart(guiGraphics, x, y - lift, HEART_SIZE, alpha);
        }

        RenderSystem.enableBlend();
        float centerX = x + HEART_SIZE / 2.0F;
        float centerY = y + HEART_SIZE / 2.0F;
        float eased = 1.0F - (1.0F - progress) * (1.0F - progress);
        for (float[] spark : BURST_SPARKS) {
            float radians = spark[0] * Mth.DEG_TO_RAD;
            int sparkX = Mth.floor(centerX + Mth.cos(radians) * spark[1] * eased);
            int sparkY = Mth.floor(centerY + Mth.sin(radians) * spark[1] * eased);
            int size = progress < 0.5F ? 2 : 1;
            int color = EclipseUiTheme.withAlpha(progress < 0.35F ? SPARK_HOT : SPARK_VIOLET,
                    1.0F - progress);
            guiGraphics.fill(sparkX, sparkY, sparkX + size, sparkY + size, color);
        }
        RenderSystem.disableBlend();
    }
}
