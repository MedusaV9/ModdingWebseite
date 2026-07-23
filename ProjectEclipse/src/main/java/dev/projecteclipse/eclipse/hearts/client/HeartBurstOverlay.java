package dev.projecteclipse.eclipse.hearts.client;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Shatter animation rendered over the exact vanilla heart that was lost. This layer
 * augments, and never replaces, the vanilla health layer.
 *
 * <p>v2 (P2 R18(a), W10): the flash/crack intro is unchanged, but the shatter now throws
 * <b>14 fragments in two populations</b> — {@value #SHARD_COUNT} rotating glass shards on
 * gravity+drag arcs lasting {@value #SHARD_FLIGHT_TICKS} ticks (600&nbsp;ms), plus
 * {@value #SPARK_COUNT} short-lived spark pops that burst radially and die first. Shards
 * reuse the burst-sheet fragment sprites (no new textures); sparks are plain quads so the
 * sheet needs no new regions. All motion is a pure function of the animation time — no
 * per-frame allocations, no per-shard state.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class HeartBurstOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "heart_burst");

    private static final ResourceLocation BURST_SHEET =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/hearts/burst_sheet.png");
    private static final int FRAME_SIZE = 36;
    private static final int SHEET_WIDTH = FRAME_SIZE * 6;
    private static final int DRAW_SIZE = 9;

    /** Flash + crack intro length (unchanged from v1). */
    private static final int SHATTER_START_TICKS = 5;
    /** R18(a): shard arcs play out over 600 ms = 12 ticks. */
    private static final int SHARD_FLIGHT_TICKS = 12;
    private static final int ANIMATION_TICKS = SHATTER_START_TICKS + SHARD_FLIGHT_TICKS;

    private static final RandomSource JITTER_RANDOM = RandomSource.create();

    private static final int SHARD_COUNT = 8;
    private static final int SPARK_COUNT = 6;
    /** Screen-px gravity per tick² pulling shard arcs back down. */
    private static final float SHARD_GRAVITY = 0.10F;
    /** Per-tick drag factor slope; clamped so shards never fully stall. */
    private static final float SHARD_DRAG_PER_TICK = 0.028F;
    private static final float SHARD_DRAG_FLOOR = 0.55F;

    /**
     * Glass shards, one row each: {vx px/t, vy px/t, spin °/t, start °, draw px}.
     * Velocities fan upward-biased so gravity turns every path into a visible arc.
     */
    private static final float[][] SHARDS = {
            {-1.05F, -0.55F, -14.0F,  35.0F, 3.0F},
            {-0.65F, -1.00F,  11.0F, 190.0F, 2.0F},
            {-0.30F, -1.25F,  -9.0F,  80.0F, 3.0F},
            { 0.10F, -1.35F,  13.0F, 260.0F, 2.0F},
            { 0.55F, -1.15F, -12.0F, 140.0F, 3.0F},
            { 0.95F, -0.70F,   8.0F, 300.0F, 2.0F},
            {-0.45F, -0.28F,  15.0F,  20.0F, 2.0F},
            { 0.50F, -0.30F, -10.0F, 220.0F, 2.0F}
    };

    /** Spark pops, one row each: {angle °, pop radius px, lifetime ticks}. */
    private static final float[][] SPARKS = {
            { 15.0F,  9.0F, 7.0F},
            { 75.0F, 11.0F, 8.0F},
            {135.0F,  8.0F, 6.0F},
            {200.0F, 10.0F, 8.0F},
            {275.0F,  9.0F, 7.0F},
            {330.0F, 12.0F, 9.0F}
    };

    private static final int SPARK_WHITE_RED = 0xFF;
    private static final int SPARK_WHITE_GREEN = 0xFF;
    private static final int SPARK_WHITE_BLUE = 0xFF;
    /** Violet tail, matching the heart_burst emitter gradient (#C77DFF). */
    private static final int SPARK_VIOLET_RED = 0xC7;
    private static final int SPARK_VIOLET_GREEN = 0x7D;
    private static final int SPARK_VIOLET_BLUE = 0xFF;

    private static int heartIndex = -1;
    private static int animationTick = -1;

    private HeartBurstOverlay() {}

    /** Starts a fresh burst and plays its local glass-crack cue. */
    public static void trigger(int firstMissingHeart) {
        heartIndex = Math.max(0, firstMissingHeart);
        animationTick = 0;
        Minecraft minecraft = Minecraft.getInstance();
        minecraft.getSoundManager().play(
                SimpleSoundInstance.forUI(EclipseSounds.UI_HEART_SHATTER.get(), 0.92F, 0.85F));
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            heartIndex = -1;
            animationTick = -1;
            return;
        }
        if (minecraft.isPaused()) {
            // ClientTickEvent keeps firing while paused with tickCount frozen — without
            // this the % 40 heartbeat gate can hold true and re-fire every client tick.
            return;
        }

        if (animationTick >= 0 && ++animationTick >= ANIMATION_TICKS) {
            heartIndex = -1;
            animationTick = -1;
        }

        // Only 1–2 remaining lives warrant the heartbeat: 0 lives is an event-banned
        // ghost, who must not hear the death heartbeat forever. Opt-out via the
        // heartbeatSound settings toggle (B12) or reducedFx.
        int lives = ClientStateCache.lives;
        if (!EclipseClientConfig.reducedFx()
                && EclipseClientConfig.heartbeatSound()
                && lives >= 1 && lives <= 2
                && minecraft.player.isAlive()
                && minecraft.player.tickCount % 40 == 0) {
            // Pitch 0.5 is the sound engine's clamp floor — the deepest dread available.
            minecraft.getSoundManager().play(
                    SimpleSoundInstance.forUI(SoundEvents.WARDEN_HEARTBEAT, 0.5F, 0.62F));
        }
    }

    /**
     * GUI-layer body registered immediately above {@code PLAYER_HEALTH}. Draws nothing
     * under F1 ({@code hideGui}) — the tick driver keeps running so a mid-burst animation
     * still expires on schedule.
     */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.options.hideGui) {
            return;
        }

        renderLowHeartPulse(guiGraphics, minecraft);
        if (animationTick < 0 || heartIndex < 0) {
            return;
        }

        float partialTick = deltaTracker.getGameTimeDeltaPartialTick(false);
        float time = animationTick + partialTick;
        HeartPosition position = heartPosition(guiGraphics, minecraft, heartIndex);

        if (time < 2.0F) {
            drawFrame(guiGraphics, position.x(), position.y(), 0, 1.0F);
            drawRedVignette(guiGraphics, 0.30F * (1.0F - time / 2.0F));
        } else if (time < SHATTER_START_TICKS) {
            int crackFrame = 1 + Math.min(2, Mth.floor(time - 2.0F));
            drawFrame(guiGraphics, position.x(), position.y(), crackFrame, 1.0F);
        } else {
            float shatterTime = time - SHATTER_START_TICKS;
            float burstAlpha = Mth.clamp(1.0F - shatterTime / SHARD_FLIGHT_TICKS, 0.0F, 1.0F);
            drawFrame(guiGraphics, position.x(), position.y(),
                    shatterTime < 2.0F ? 4 : 5, burstAlpha * 0.55F);
            float centerX = position.x() + 4.5F;
            float centerY = position.y() + 4.5F;
            drawShards(guiGraphics, centerX, centerY, shatterTime, burstAlpha);
            drawSparks(guiGraphics, centerX, centerY, shatterTime);
        }
    }

    /**
     * Reconstructs vanilla's health origin from the public post-layer
     * {@code Gui.leftHeight}, including multi-row compression and low-health
     * random jitter.
     */
    private static HeartPosition heartPosition(GuiGraphics guiGraphics, Minecraft minecraft, int index) {
        float maxAndAbsorption = minecraft.player.getMaxHealth() + minecraft.player.getAbsorptionAmount();
        int heartSlots = Math.max(1, Mth.ceil(maxAndAbsorption / 2.0F));
        int rows = Math.max(1, Mth.ceil(heartSlots / 10.0F));
        int rowStep = Math.max(10 - (rows - 2), 3);
        int occupiedHeight = (rows - 1) * rowStep + 10;

        int x = guiGraphics.guiWidth() / 2 - 91 + (index % 10) * 8;
        int y = guiGraphics.guiHeight() - minecraft.gui.leftHeight
                + occupiedHeight - (index / 10) * rowStep;

        if (minecraft.player.getHealth() <= 4.0F) {
            JITTER_RANDOM.setSeed((long) minecraft.gui.getGuiTicks() * 312871L);
            for (int slot = heartSlots - 1; slot >= index; slot--) {
                int jitter = JITTER_RANDOM.nextInt(2);
                if (slot == index) {
                    y += jitter;
                }
            }
        }
        return new HeartPosition(x, y);
    }

    private static void drawFrame(GuiGraphics guiGraphics, int x, int y, int frame, float alpha) {
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(BURST_SHEET, x, y, DRAW_SIZE, DRAW_SIZE,
                (float) (frame * FRAME_SIZE), 0.0F, FRAME_SIZE, FRAME_SIZE, SHEET_WIDTH, FRAME_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    /**
     * Population 1: rotating glass shards on gravity+drag arcs. Position, spin and fade are
     * pure functions of {@code time}, so the flight is deterministic and allocation-free.
     * Sprites come from the sheet's existing 3×2 fragment grid at (180,12).
     */
    private static void drawShards(GuiGraphics guiGraphics, float centerX, float centerY,
            float time, float alpha) {
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        PoseStack pose = guiGraphics.pose();
        float drag = Math.max(SHARD_DRAG_FLOOR, 1.0F - SHARD_DRAG_PER_TICK * time);
        for (int i = 0; i < SHARD_COUNT; i++) {
            float[] shard = SHARDS[i];
            float shardX = centerX + shard[0] * time * drag;
            float shardY = centerY + shard[1] * time * drag + SHARD_GRAVITY * time * time;
            float angle = shard[3] + shard[2] * time;
            int size = (int) shard[4];
            int half = size / 2;
            int cell = i % 6;
            int sourceX = 180 + (cell % 3) * 6;
            int sourceY = 12 + (cell / 3) * 6;

            pose.pushPose();
            pose.translate(shardX, shardY, 0.0F);
            pose.mulPose(Axis.ZP.rotationDegrees(angle));
            guiGraphics.blit(BURST_SHEET, -half, -half, size, size,
                    (float) sourceX, (float) sourceY, 6, 6, SHEET_WIDTH, FRAME_SIZE);
            pose.popPose();
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    /**
     * Population 2: spark pops — plain quads that shoot out on an ease-out radius, flash
     * white, cool to violet and die within their own short lifetimes (all shorter than the
     * shard flight, so sparks read as the "pop" and shards as the debris). Drawn with
     * {@code fill} + ARGB alpha, deliberately outside any {@code setColor} tint.
     */
    private static void drawSparks(GuiGraphics guiGraphics, float centerX, float centerY, float time) {
        RenderSystem.enableBlend();
        for (int i = 0; i < SPARK_COUNT; i++) {
            float[] spark = SPARKS[i];
            float progress = time / spark[2];
            if (progress >= 1.0F) {
                continue;
            }
            float eased = 1.0F - (1.0F - progress) * (1.0F - progress);
            float radians = spark[0] * Mth.DEG_TO_RAD;
            int sparkX = Mth.floor(centerX + Mth.cos(radians) * spark[1] * eased);
            int sparkY = Mth.floor(centerY + Mth.sin(radians) * spark[1] * eased);

            boolean hot = progress < 0.35F;
            int size = progress < 0.5F ? 2 : 1;
            int color = hot
                    ? argb(1.0F - progress * 0.5F, SPARK_WHITE_RED, SPARK_WHITE_GREEN, SPARK_WHITE_BLUE)
                    : argb(1.0F - progress, SPARK_VIOLET_RED, SPARK_VIOLET_GREEN, SPARK_VIOLET_BLUE);
            guiGraphics.fill(sparkX, sparkY, sparkX + size, sparkY + size, color);
        }
        RenderSystem.disableBlend();
    }

    /** Pulsing red edge wash while at 1–2 lives (0 = ghost: no pulse, matching the heartbeat). */
    private static void renderLowHeartPulse(GuiGraphics guiGraphics, Minecraft minecraft) {
        int lives = ClientStateCache.lives;
        if (EclipseClientConfig.reducedFx() || lives < 1 || lives > 2 || !minecraft.player.isAlive()) {
            return;
        }
        float pulse = 0.5F + 0.5F * Mth.sin(minecraft.gui.getGuiTicks() * Mth.PI / 20.0F);
        drawRedVignette(guiGraphics, 0.025F + pulse * 0.045F);
    }

    /** Lightweight red edge wash; kept in the HUD layer for Sodium/Iris safety. */
    private static void drawRedVignette(GuiGraphics guiGraphics, float alpha) {
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        int color = argb(alpha, 0xB8, 0x08, 0x18);
        guiGraphics.fill(0, 0, width, 7, color);
        guiGraphics.fill(0, height - 7, width, height, color);
        guiGraphics.fill(0, 7, 7, height - 7, color);
        guiGraphics.fill(width - 7, 7, width, height - 7, color);
    }

    private static int argb(float alpha, int red, int green, int blue) {
        return (Mth.floor(Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | (red << 16) | (green << 8) | blue;
    }

    private record HeartPosition(int x, int y) {}
}
