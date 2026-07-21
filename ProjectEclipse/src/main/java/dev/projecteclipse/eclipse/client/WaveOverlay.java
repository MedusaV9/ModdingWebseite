package dev.projecteclipse.eclipse.client;

import java.util.EnumMap;
import java.util.Map;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CCutscenePayload.Phase;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client visuals + audio muffling for the start-event cutscene, driven by
 * {@link ClientStateCache#cutscenePhase} (written by the {@code S2CCutscenePayload} handler):
 * <ul>
 *   <li>{@code TILT} — subtle pulsing screen darkening.</li>
 *   <li>{@code SUBMERGE}/{@code WAVES} — scrolling, pulsing tiled wave texture at rising alpha;
 *       master/music/records/ambient volumes are temporarily scaled down (originals stored).</li>
 *   <li>{@code EMERGE} — waves fade out over ~{@value #FADE_TICKS} ticks, volumes restored.</li>
 * </ul>
 *
 * <p>Relog-robust: state auto-clears (and volumes restore) {@value #AUTO_CLEAR_TICKS} ticks after
 * the last phase change, or immediately when the level goes away (disconnect). The GUI layer is
 * registered above the HUD by {@link EclipseGuiLayers}; the tick driver here is on the game bus.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WaveOverlay {
    static final ResourceLocation LAYER_ID = ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wave_overlay");
    private static final ResourceLocation WAVE_TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/wave_overlay.png");
    private static final int TEXTURE_SIZE = 256;

    /** Ticks for the waves to ramp in (SUBMERGE) and fade out (EMERGE). */
    private static final int RAMP_TICKS = 40;
    private static final int FADE_TICKS = 40;
    /** Auto-clear after ~30s without a new phase packet (relog / lost EMERGE safety net). */
    private static final int AUTO_CLEAR_TICKS = 600;

    private static final float MASTER_MUFFLE = 0.35F;
    private static final float SECONDARY_MUFFLE = 0.5F;
    private static final SoundSource[] SECONDARY_MUFFLED =
            {SoundSource.MUSIC, SoundSource.RECORDS, SoundSource.AMBIENT};

    /** Phase currently animated by the overlay; {@code null} = overlay inactive. */
    private static Phase activePhase;
    /** Ticks spent in {@link #activePhase}. */
    private static int phaseTicks;
    /** Ticks since the last observed phase change, for the auto-clear safety net. */
    private static int ticksSinceLastChange;
    /** Original sound-category volumes while muffled, or {@code null} when not muffled. */
    private static Map<SoundSource, Double> savedVolumes;

    private WaveOverlay() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            if (activePhase != null) {
                clear(); // disconnected mid-cutscene
            }
            return;
        }

        Phase latest = ClientStateCache.cutscenePhase;
        if (latest != activePhase) {
            activePhase = latest;
            phaseTicks = 0;
            ticksSinceLastChange = 0;
            if (latest == Phase.SUBMERGE || latest == Phase.WAVES) {
                muffleAudio(minecraft);
            } else if (latest == Phase.EMERGE) {
                restoreAudio(minecraft);
            }
            return;
        }
        if (activePhase == null) {
            return;
        }

        phaseTicks++;
        ticksSinceLastChange++;
        if (ticksSinceLastChange > AUTO_CLEAR_TICKS || (activePhase == Phase.EMERGE && phaseTicks > FADE_TICKS)) {
            clear();
        }
    }

    /** Fully resets the overlay and restores audio; also drops the stale cached phase. */
    private static void clear() {
        restoreAudio(Minecraft.getInstance());
        activePhase = null;
        phaseTicks = 0;
        ticksSinceLastChange = 0;
        ClientStateCache.cutscenePhase = null;
    }

    private static void muffleAudio(Minecraft minecraft) {
        if (savedVolumes != null) {
            return; // already muffled
        }
        Map<SoundSource, Double> saved = new EnumMap<>(SoundSource.class);
        saved.put(SoundSource.MASTER, minecraft.options.getSoundSourceOptionInstance(SoundSource.MASTER).get());
        for (SoundSource source : SECONDARY_MUFFLED) {
            saved.put(source, minecraft.options.getSoundSourceOptionInstance(source).get());
        }
        savedVolumes = saved;
        minecraft.options.getSoundSourceOptionInstance(SoundSource.MASTER)
                .set(saved.get(SoundSource.MASTER) * MASTER_MUFFLE);
        for (SoundSource source : SECONDARY_MUFFLED) {
            minecraft.options.getSoundSourceOptionInstance(source).set(saved.get(source) * SECONDARY_MUFFLE);
        }
    }

    private static void restoreAudio(Minecraft minecraft) {
        if (savedVolumes == null) {
            return;
        }
        for (Map.Entry<SoundSource, Double> entry : savedVolumes.entrySet()) {
            minecraft.options.getSoundSourceOptionInstance(entry.getKey()).set(entry.getValue());
        }
        savedVolumes = null;
    }

    /** {@code LayeredDraw.Layer} body, wired above the HUD via {@link EclipseGuiLayers}. */
    static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Phase phase = activePhase;
        if (phase == null || Minecraft.getInstance().level == null) {
            return;
        }
        float time = phaseTicks + deltaTracker.getGameTimeDeltaPartialTick(false);
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();

        switch (phase) {
            case TILT -> {
                // subtle darkening pulse
                float alpha = 0.10F + 0.06F * Mth.sin(time * 0.2F);
                guiGraphics.fill(0, 0, width, height, argb(alpha, 0.0F, 0.0F, 0.02F));
            }
            case SUBMERGE, WAVES -> {
                float ramp = Mth.clamp(time / RAMP_TICKS, 0.0F, 1.0F);
                drawWaves(guiGraphics, width, height, time, ramp);
            }
            case EMERGE -> {
                float fade = Mth.clamp(1.0F - time / FADE_TICKS, 0.0F, 1.0F);
                if (fade > 0.0F) {
                    drawWaves(guiGraphics, width, height, time, fade);
                }
            }
        }
    }

    /** Scrolling, sine-pulsing tiled wave texture over a dark blue "underwater" wash. */
    private static void drawWaves(GuiGraphics guiGraphics, int width, int height, float time, float strength) {
        float pulse = 0.72F + 0.12F * Mth.sin(time * 0.13F);
        float alpha = strength * pulse;
        guiGraphics.fill(0, 0, width, height, argb(strength * 0.35F, 0.02F, 0.08F, 0.16F));

        int scrollX = Mth.floor(time * 1.7F) % TEXTURE_SIZE;
        int scrollY = Mth.floor(time * 0.9F) % TEXTURE_SIZE;
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        for (int x = -scrollX; x < width; x += TEXTURE_SIZE) {
            for (int y = -scrollY; y < height; y += TEXTURE_SIZE) {
                guiGraphics.blit(WAVE_TEXTURE, x, y, 0.0F, 0.0F, TEXTURE_SIZE, TEXTURE_SIZE, TEXTURE_SIZE, TEXTURE_SIZE);
            }
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    private static int argb(float alpha, float red, float green, float blue) {
        return ((int) (Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | ((int) (red * 255.0F) << 16)
                | ((int) (green * 255.0F) << 8)
                | (int) (blue * 255.0F);
    }
}
