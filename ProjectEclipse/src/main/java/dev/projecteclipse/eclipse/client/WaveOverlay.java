package dev.projecteclipse.eclipse.client;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.EnumMap;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CCutscenePayload.Phase;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WaveOverlay v2 (P2 R8, W5) — client visuals + audio muffling for the start-event cutscene,
 * driven by {@link ClientStateCache#cutscenePhase} (written by the {@code S2CCutscenePayload}
 * handler). The v1 flat tiled wave texture is gone; the submerge now reads as expanding
 * <b>refractive shockwave rings</b> through the {@code eclipse:shockwave} Veil post pipeline
 * (registered here, FEATURE priority, frozen uniforms {@code ShockCenter/ShockProgress/
 * ShockStrength} — §3.3):
 * <ul>
 *   <li>{@code TILT} — subtle pulsing screen darkening (kept from v1).</li>
 *   <li>{@code SUBMERGE}/{@code WAVES} — repeating refraction rings from screen center at
 *       rising strength + a slim underwater tint fill (40% of the v1 wash alpha);
 *       master/music/records/ambient volumes are temporarily scaled down (originals
 *       stored).</li>
 *   <li>{@code EMERGE} — rings and tint fade out over ~{@value #FADE_TICKS} ticks, volumes
 *       restored.</li>
 * </ul>
 *
 * <p>The same pipeline renders <b>world-anchored</b> shockwaves: whenever
 * {@link EclipseFxState#shockwaveParams} is live (fed by {@code eclipse:fx/shockwave} events —
 * intro v3's storm burst, expansion slams), those params win over the submerge rings, with
 * {@code ShockCenter} at the projected world origin. Under an Iris shaderpack or with
 * {@code veilPostFx} off the pipeline is hard-gated away by {@link VeilPostController} and
 * only the slim tint + audio muffle remain (§7 fallback).</p>
 *
 * <p>Relog-robust: state auto-clears (and volumes restore) {@value #AUTO_CLEAR_TICKS} ticks after
 * the last phase change, or immediately when the level goes away (disconnect) or the player logs
 * out. The GUI layer is registered above the HUD by {@link EclipseGuiLayers}; the tick driver here
 * is on the game bus.</p>
 *
 * <p>Crash-robust: the muffle mutates the REAL sound options, so the originals are persisted to
 * {@code config/}{@value #RESTORE_MARKER_NAME} before the first mutation and the marker is deleted
 * after a successful restore. If a session crashes mid-muffle, the next launch's first client tick
 * finds the marker, restores the saved volumes, re-saves the options and deletes it — reduced
 * volumes can never stick permanently.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WaveOverlay {
    static final ResourceLocation LAYER_ID = ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wave_overlay");
    /** {@code eclipse:shockwave} post pipeline (P2 §3.3, owned by W5). */
    private static final ResourceLocation SHOCKWAVE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "shockwave");

    /** Ticks for the waves to ramp in (SUBMERGE) and fade out (EMERGE). */
    private static final int RAMP_TICKS = 40;
    private static final int FADE_TICKS = 40;
    /** Auto-clear after ~30s without a new phase packet (relog / lost EMERGE safety net). */
    private static final int AUTO_CLEAR_TICKS = 600;

    /** One submerge ring cycle (rings re-fire from the center for the whole phase). */
    private static final float WAVE_CYCLE_TICKS = 45.0F;
    /** Peak ShockStrength of the submerge rings (world shockwave events carry their own). */
    private static final float WAVE_BASE_STRENGTH = 0.55F;
    /** Underwater tint at 40% of the v1 wash alpha (0.35) — the rings carry the effect now. */
    private static final float TINT_ALPHA = 0.14F;

    private static final float MASTER_MUFFLE = 0.35F;
    private static final float SECONDARY_MUFFLE = 0.5F;
    private static final SoundSource[] SECONDARY_MUFFLED =
            {SoundSource.MUSIC, SoundSource.RECORDS, SoundSource.AMBIENT};

    /** Crash-recovery marker in the config dir: the pre-muffle volumes, JSON by source name. */
    private static final String RESTORE_MARKER_NAME = "eclipse-volume-restore.json";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    /** Phase currently animated by the overlay; {@code null} = overlay inactive. */
    private static Phase activePhase;
    /** Ticks spent in {@link #activePhase}. */
    private static int phaseTicks;
    /** Ring clock — keeps counting across SUBMERGE→WAVES so the ring rhythm never stutters. */
    private static int waveTicks;
    /** Ticks since the last observed phase change, for the auto-clear safety net. */
    private static int ticksSinceLastChange;
    /** Original sound-category volumes while muffled, or {@code null} when not muffled. */
    private static Map<SoundSource, Double> savedVolumes;
    /** One-shot flag: the crash-recovery marker check runs on the very first client tick. */
    private static boolean recoveryChecked;

    static {
        // Class-loads on the client during mod construction (@EventBusSubscriber scan), well
        // before the first frame — the row is predicate-driven from then on.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                SHOCKWAVE_POST, VeilPostController.PipelinePriority.FEATURE,
                WaveOverlay::wantShockwave, WaveOverlay::feedShockwave));
    }

    private WaveOverlay() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!recoveryChecked) {
            recoveryChecked = true;
            recoverCrashedMuffle(minecraft);
        }
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
        if (activePhase == Phase.SUBMERGE || activePhase == Phase.WAVES || activePhase == Phase.EMERGE) {
            waveTicks++;
        }
        if (ticksSinceLastChange > AUTO_CLEAR_TICKS || (activePhase == Phase.EMERGE && phaseTicks > FADE_TICKS)) {
            clear();
        }
    }

    /** Disconnect reset hook (mirrors {@code QuasarSpawner.DisconnectReset}). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        if (activePhase != null || savedVolumes != null) {
            clear();
        }
    }

    /** Fully resets the overlay and restores audio; also drops the stale cached phase. */
    private static void clear() {
        restoreAudio(Minecraft.getInstance());
        activePhase = null;
        phaseTicks = 0;
        waveTicks = 0;
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
        // Crash safety: persist the originals BEFORE the first mutation — if this session
        // dies mid-muffle, the next launch restores them from the marker.
        writeRestoreMarker(saved);
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
        deleteRestoreMarker(); // Restore complete: the crash marker has nothing left to undo.
    }

    // --- crash-recovery marker (config/eclipse-volume-restore.json) ---

    private static Path restoreMarkerPath() {
        return FMLPaths.CONFIGDIR.get().resolve(RESTORE_MARKER_NAME);
    }

    private static void writeRestoreMarker(Map<SoundSource, Double> saved) {
        JsonObject root = new JsonObject();
        for (Map.Entry<SoundSource, Double> entry : saved.entrySet()) {
            root.addProperty(entry.getKey().getName(), entry.getValue());
        }
        Path file = restoreMarkerPath();
        try {
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write {}; a crash mid-cutscene could keep the muffled volumes", file, e);
        }
    }

    private static void deleteRestoreMarker() {
        Path file = restoreMarkerPath();
        try {
            Files.deleteIfExists(file);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to delete {}", file, e);
        }
    }

    /**
     * First-tick crash recovery: a leftover marker means the previous session died between
     * muffle and restore — put its saved volumes back, persist the options (the crashed
     * session may have saved the muffled values into options.txt) and drop the marker.
     */
    private static void recoverCrashedMuffle(Minecraft minecraft) {
        Path file = restoreMarkerPath();
        if (!Files.exists(file)) {
            return;
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            int restored = 0;
            for (SoundSource source : SoundSource.values()) {
                if (root.has(source.getName())) {
                    minecraft.options.getSoundSourceOptionInstance(source)
                            .set(root.get(source.getName()).getAsDouble());
                    restored++;
                }
            }
            minecraft.options.save();
            EclipseMod.LOGGER.info("Restored {} sound volume(s) left muffled by a crashed cutscene session", restored);
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to restore volumes from {}", file, e);
        }
        deleteRestoreMarker();
    }

    // --- eclipse:shockwave pipeline feed (P2 R8) ---

    /**
     * Pipeline activation: any live world shockwave ({@code eclipse:fx/shockwave} →
     * {@link EclipseFxState#startShockwave}) or the submerge/emerge ring phases.
     */
    private static boolean wantShockwave() {
        float partialTick = partialTick();
        return EclipseFxState.shockwaveParams(partialTick) != null || waveStrength(partialTick) > 0.01F;
    }

    /**
     * Frozen uniforms (§3.3): {@code ShockCenter (vec2 NDC), ShockProgress, ShockStrength}.
     * A live world shockwave wins (its origin re-projected every frame by
     * {@code EclipseFxState}/{@code SunTracker}); otherwise the submerge rings pulse from the
     * screen center for fullscreen immersion.
     */
    private static void feedShockwave(PostPipeline pipeline) {
        float partialTick = partialTick();
        Vector4f world = EclipseFxState.shockwaveParams(partialTick);
        if (world != null) {
            pipeline.getUniform("ShockCenter").setVector(world.x(), world.y());
            pipeline.getUniform("ShockProgress").setFloat(world.z());
            pipeline.getUniform("ShockStrength").setFloat(world.w());
            return;
        }
        pipeline.getUniform("ShockCenter").setVector(0.0F, 0.0F);
        pipeline.getUniform("ShockProgress").setFloat(((waveTicks + partialTick) % WAVE_CYCLE_TICKS) / WAVE_CYCLE_TICKS);
        pipeline.getUniform("ShockStrength").setFloat(waveStrength(partialTick));
    }

    /** Submerge-ring strength envelope: ramp in (SUBMERGE/WAVES), hold, fade out (EMERGE). */
    private static float waveStrength(float partialTick) {
        Phase phase = activePhase;
        if (phase == null || Minecraft.getInstance().level == null) {
            return 0.0F;
        }
        float time = phaseTicks + partialTick;
        return switch (phase) {
            case SUBMERGE, WAVES -> Mth.clamp(time / RAMP_TICKS, 0.0F, 1.0F) * WAVE_BASE_STRENGTH;
            case EMERGE -> Mth.clamp(1.0F - time / FADE_TICKS, 0.0F, 1.0F) * WAVE_BASE_STRENGTH;
            default -> 0.0F;
        };
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }

    // --- GUI layer (slim tint only — the ring visual lives in the post pipeline) ---

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
                drawUnderwaterTint(guiGraphics, width, height, ramp);
            }
            case EMERGE -> {
                float fade = Mth.clamp(1.0F - time / FADE_TICKS, 0.0F, 1.0F);
                if (fade > 0.0F) {
                    drawUnderwaterTint(guiGraphics, width, height, fade);
                }
            }
        }
    }

    /** Slim dark-blue "underwater" wash (v1 kept the wash — at 40% alpha — and lost the tiles). */
    private static void drawUnderwaterTint(GuiGraphics guiGraphics, int width, int height, float strength) {
        guiGraphics.fill(0, 0, width, height, argb(strength * TINT_ALPHA, 0.02F, 0.08F, 0.16F));
    }

    private static int argb(float alpha, float red, float green, float blue) {
        return ((int) (Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | ((int) (red * 255.0F) << 16)
                | ((int) (green * 255.0F) << 8)
                | (int) (blue * 255.0F);
    }
}
