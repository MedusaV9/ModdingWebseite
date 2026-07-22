package dev.projecteclipse.eclipse.hearts.client;

import com.mojang.blaze3d.systems.RenderSystem;

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
 * Twelve-tick shatter animation rendered over the exact vanilla heart that was
 * lost. This layer augments, and never replaces, the vanilla health layer.
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
    private static final int ANIMATION_TICKS = 12;
    private static final RandomSource JITTER_RANDOM = RandomSource.create();

    private static final float[][] SHARD_VELOCITIES = {
            {-0.80F, -0.72F}, {-0.42F, -1.02F}, {0.18F, -1.12F},
            {0.72F, -0.78F}, {-0.58F, -0.22F}, {0.62F, -0.18F}
    };

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

        if (animationTick >= 0 && ++animationTick >= ANIMATION_TICKS) {
            heartIndex = -1;
            animationTick = -1;
        }

        if (!EclipseClientConfig.reducedFx()
                && ClientStateCache.lives <= 2
                && minecraft.player.isAlive()
                && minecraft.player.tickCount % 40 == 0) {
            minecraft.getSoundManager().play(
                    SimpleSoundInstance.forUI(SoundEvents.WARDEN_HEARTBEAT, 0.62F, 0.16F));
        }
    }

    /** GUI-layer body registered immediately above {@code PLAYER_HEALTH}. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null) {
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
        } else if (time < 5.0F) {
            int crackFrame = 1 + Math.min(2, Mth.floor(time - 2.0F));
            drawFrame(guiGraphics, position.x(), position.y(), crackFrame, 1.0F);
        } else {
            float shatterTime = time - 5.0F;
            float alpha = Mth.clamp(1.0F - shatterTime / 7.0F, 0.0F, 1.0F);
            drawFrame(guiGraphics, position.x(), position.y(), shatterTime < 2.0F ? 4 : 5, alpha * 0.55F);
            drawShards(guiGraphics, position.x(), position.y(), shatterTime, alpha);
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

    private static void drawShards(GuiGraphics guiGraphics, int x, int y, float time, float alpha) {
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        for (int i = 0; i < SHARD_VELOCITIES.length; i++) {
            float vx = SHARD_VELOCITIES[i][0];
            float vy = SHARD_VELOCITIES[i][1];
            int shardX = Mth.floor(x + 4.0F + vx * time);
            int shardY = Mth.floor(y + 4.0F + vy * time + 0.12F * time * time);
            int sourceX = 180 + (i % 3) * 6;
            int sourceY = 12 + (i / 3) * 6;
            guiGraphics.blit(BURST_SHEET, shardX, shardY, 2, 2,
                    (float) sourceX, (float) sourceY, 6, 6, SHEET_WIDTH, FRAME_SIZE);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    private static void renderLowHeartPulse(GuiGraphics guiGraphics, Minecraft minecraft) {
        if (EclipseClientConfig.reducedFx() || ClientStateCache.lives > 2 || !minecraft.player.isAlive()) {
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
