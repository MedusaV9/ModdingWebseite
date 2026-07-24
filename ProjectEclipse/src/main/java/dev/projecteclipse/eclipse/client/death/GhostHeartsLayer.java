package dev.projecteclipse.eclipse.client.death;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.hearts.client.HeartRowGeometry;
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
    /** Row metrics shared with the W4-HEARTS geometry (identical to the old locals). */
    private static final int HEART_STEP = HeartRowGeometry.HEART_STEP_X;
    private static final int HEART_SIZE = HeartRowGeometry.HEART_SIZE;

    private static final float GHOST_HEART_ALPHA = 0.62F;
    private static final int FADE_IN_TICKS = 12;
    /** Crack hairlines inside a ghost heart (translucent near-black aubergine). */
    private static final int CRACK_COLOR = 0x8C0A0614;

    /** Ritual-vigil fill (W4-HEARTS R4): violet, the ACCENT family (#B98CFF). */
    private static final int VIGIL_FILL_COLOR = 0xFFB98CFF;
    /** Displayed fill catch-up per tick while the ritual runs (payloads land every 20 t). */
    private static final float VIGIL_RISE_PER_TICK = 0.004F;
    /** Drain per tick after a ritual failure: a full row re-cracks over ~20 ticks. */
    private static final float VIGIL_REVERT_PER_TICK = 0.05F;

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

    /** Ritual-vigil progress last synced by {@code S2CRitualVigilPayload} (0..1). */
    private static float vigilTarget;
    /** Smoothed on-screen vigil fill (eases toward {@link #vigilTarget} per tick). */
    private static float vigilShown;

    private GhostHeartsLayer() {}

    // ------------------------------------------------------------------ public seam

    /**
     * Whether this layer currently replaces the vanilla health slot. W4-HEARTS R1:
     * {@code PurpleHeartsLayer} defers (never cancels, never compensates) while this
     * returns {@code true}, so the {@code leftHeight} compensation is applied exactly once.
     */
    public static boolean isOwningHealthSlot() {
        return mode != Mode.IDLE;
    }

    /**
     * {@code S2CRitualVigilPayload} entry (W4-HEARTS R4): while a revive ritual targets
     * this ghost, a violet fill rises across the cracked hearts proportional to ritual
     * progress and the crack hairlines knit shut. {@code active=false} (ritual failed or
     * aborted) drains the fill and the cracks return over ~20 ticks. Only stores the
     * sync target — the fill is drawn (and eased) exclusively while the ghost row owns
     * the health slot, and resets on revive burst / level unload.
     */
    public static void setRitualVigil(float progress, boolean active) {
        vigilTarget = active ? Mth.clamp(progress, 0.0F, 1.0F) : 0.0F;
    }

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
        drawGhostHeart(guiGraphics, x, y, size, alpha, 1.0F);
    }

    /**
     * {@link #drawGhostHeart(GuiGraphics, int, int, int, float)} with a separate crack
     * opacity — the ritual vigil (R4) knits the hairlines shut as its fill rises.
     */
    private static void drawGhostHeart(GuiGraphics guiGraphics, int x, int y, int size,
            float alpha, float crackAlpha) {
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha * 0.85F);
        guiGraphics.blitSprite(HEART_CONTAINER_SPRITE, x, y, size, size);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blitSprite(HEART_GHOST_SPRITE, x, y, size, size);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (crackAlpha > 0.02F) {
            int unit = size / HEART_SIZE;
            int crack = EclipseUiTheme.withAlpha(CRACK_COLOR, alpha * crackAlpha);
            guiGraphics.fill(x + 4 * unit, y + 2 * unit, x + 5 * unit, y + 4 * unit, crack);
            guiGraphics.fill(x + 3 * unit, y + 4 * unit, x + 4 * unit, y + 6 * unit, crack);
            guiGraphics.fill(x + 5 * unit, y + 5 * unit, x + 6 * unit, y + 7 * unit, crack);
        }
        RenderSystem.disableBlend();
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAbove(VanillaGuiLayers.PLAYER_HEALTH, LAYER_ID, GhostHeartsLayer::render);
    }

    /**
     * Replaces (never stacks with) the vanilla hearts while the ghost row owns the slot.
     * {@code leftHeight} is compensated by vanilla's exact one-row increment so
     * armor/vehicle rows keep their vanilla position.
     */
    @SubscribeEvent
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (isOwningHealthSlot() && event.getName().equals(VanillaGuiLayers.PLAYER_HEALTH)) {
            event.setCanceled(true);
            Minecraft.getInstance().gui.leftHeight += HeartRowGeometry.leftHeightIncrement(1);
        }
    }

    // ------------------------------------------------------------------ state driver

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            mode = Mode.IDLE;
            modeTicks = 0;
            resetVigil();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        modeTicks++;
        tickVigil();
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
                    resetVigil();
                }
            }
            case BURST -> {
                resetVigil(); // the revive celebration owns the row from here
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

    /** Eases the on-screen vigil fill toward the last synced ritual progress. */
    private static void tickVigil() {
        if (vigilShown < vigilTarget) {
            // Rising: slow knit — steady-state trails the 20-tick progress payloads.
            vigilShown = Math.min(vigilTarget, vigilShown + VIGIL_RISE_PER_TICK);
        } else if (vigilShown > vigilTarget) {
            // Failure (or abort): the fill drains and the cracks return over ~20 ticks.
            vigilShown = Math.max(vigilTarget, vigilShown - VIGIL_REVERT_PER_TICK);
        }
    }

    private static void resetVigil() {
        vigilTarget = 0.0F;
        vigilShown = 0.0F;
    }

    // ------------------------------------------------------------------ layer body

    /** GUI-layer body (self-registered above {@code PLAYER_HEALTH}). Draws nothing under F1. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (mode == Mode.IDLE || minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        float time = modeTicks + deltaTracker.getGameTimeDeltaPartialTick(false);
        int rowX = HeartRowGeometry.rowLeft(guiGraphics);
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
            // R4 ritual vigil: the fill knits left-to-right across the row; each heart's
            // crack hairlines fade out exactly as its own fill completes.
            float heartFill = Mth.clamp(vigilShown * GHOST_HEART_COUNT - i, 0.0F, 1.0F);
            drawGhostHeart(guiGraphics, x, rowY, HEART_SIZE, rowAlpha, 1.0F - heartFill);
            if (heartFill > 0.02F) {
                drawVigilFill(guiGraphics, x, rowY, heartFill, rowAlpha);
            }
        }

        if (mode != Mode.BURST) {
            String tag = EclipseLang.trString("gui.eclipse.death.ghost_tag");
            guiGraphics.drawString(minecraft.font, tag,
                    rowX + GHOST_HEART_COUNT * HEART_STEP + 5, rowY + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, rowAlpha));
        }
    }

    /**
     * R4 vigil: a faint violet fill rising bottom-up through one cracked heart — the
     * ghost heart sprite re-blitted ACCENT-tinted, cropped to the filled rows, with a
     * 1px brighter waterline. Pure function of {@code fill}; allocation-free.
     */
    private static void drawVigilFill(GuiGraphics guiGraphics, int x, int y, float fill, float rowAlpha) {
        int filledPx = Mth.clamp(Mth.floor(fill * HEART_SIZE + 0.5F), 1, HEART_SIZE);
        int top = y + HEART_SIZE - filledPx;
        RenderSystem.enableBlend();
        guiGraphics.setColor(0.725F, 0.549F, 1.0F, rowAlpha * 0.85F);
        guiGraphics.blitSprite(HEART_GHOST_SPRITE, HEART_SIZE, HEART_SIZE,
                0, HEART_SIZE - filledPx, x, top, HEART_SIZE, filledPx);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (filledPx < HEART_SIZE) {
            // Waterline shimmer just above the fill (skipped once the heart is whole).
            guiGraphics.fill(x + 2, top - 1, x + HEART_SIZE - 2, top,
                    EclipseUiTheme.withAlpha(VIGIL_FILL_COLOR, rowAlpha * 0.55F));
        }
        RenderSystem.disableBlend();
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
