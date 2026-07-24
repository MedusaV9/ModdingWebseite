package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayDeque;
import java.util.Iterator;

import javax.annotation.Nullable;

import org.joml.Matrix4f;
import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.sky.LimboSpecialEffects;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import foundry.veil.api.client.render.post.PostPipeline;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * Client-side ambience of the Limbo dimension, active only while the local level is
 * {@code eclipse:limbo}. P2-W3 overhaul (R5): three rolling windows of looping Quasar
 * emitters, the {@code eclipse:limbo} v2 post pipeline registration, and the ambient
 * sound bed.
 * <ul>
 *   <li><b>Motes</b> ({@code eclipse:limbo_motes}, denser since v2 — the emitter JSON emits
 *       every 3 ticks instead of 5): small drifting wisps just above the water plane.</li>
 *   <li><b>God-ray shafts</b> ({@code eclipse:limbo_godray}): tall soft additive light
 *       shafts hanging in the air around the ship, slowly sinking and swaying — the
 *       world-space companion of the screen-space god rays (they also survive Iris, when
 *       the post pipeline is gated off).</li>
 *   <li><b>Fog layers</b> ({@code eclipse:limbo_fog}): big dim alpha-blended violet sheets
 *       hugging the water surface.</li>
 * </ul>
 *
 * <p>Every window follows the proven mote pattern: the emitter JSONs are {@code loop: true}
 * and Veil never expires a looping position-based emitter, so the handles returned by
 * {@link QuasarSpawner#spawnManaged} are kept and the oldest is removed beyond each window's
 * live cap — rolling clouds that follow the player without ever leaking emitters. All three
 * charge {@link FxBudget.Channel#AMBIENT} (P2 §3.5); {@code reducedFx} doubles every cadence
 * (the {@code BorderFxRenderer} pattern) on top of the budget's own halving.</p>
 *
 * <p><b>Post pipeline (v2)</b>: the static init registers the {@code eclipse:limbo} row with
 * {@link VeilPostController#register}, replacing W1's backward-compat {@code Intensity}-only
 * row. The feeder supplies the frozen §3.3 uniforms — {@code Intensity} (eased ~2 s fade
 * after entering limbo, as in v1), {@code GodrayDir} (NDC of the zenith eclipse point from
 * {@link LimboSpecialEffects#zenithWorldPoint} projected through {@link SunTracker#worldToNdc},
 * pushed far offscreen while behind the camera), {@code CausticsAmount} and {@code Time}.</p>
 *
 * <p><b>Post pipeline (v3, PLAN-C C1)</b>: the feeder additionally supplies the water-mask /
 * horizon set — {@code InvViewProj} + {@code CameraPos} (this frame's exact AFTER_SKY render
 * matrices captured by {@link #onRenderLevelStage}, view bobbing included, inverted once per
 * frame — the {@link SunTracker} law: never reconstruct from {@code veil:camera}),
 * {@code WaterlineY} ({@code GhostShipBuilder.waterlineY} reaching the client through the
 * {@code ship_deck} anchor sync, see {@link LimboSpecialEffects#clientWaterlineY}),
 * {@code VoyageOffset} (steadily increasing world-XZ scroll along ship forward −X→+X — the
 * caustic field streams slowly astern past the hull: the shader half of the "sailing"
 * illusion; wraps hourly like {@code Time}), {@code CurveAmount} (horizon curvature strength,
 * forced 0 under {@code reducedFx}) and {@code FarDist} (effective render distance in
 * blocks, where the loaded sea geometry ends).</p>
 *
 * <p><b>Sound</b>: one looping {@code ambient.limbo_loop} instance
 * ({@link SoundSource#AMBIENT}, peak volume {@code 0.6}) that fades in over
 * {@value LimboLoopSound#FADE_TICKS} ticks after entering limbo and fades out (then stops)
 * after leaving, modeled on vanilla's {@code BiomeAmbientSoundsHandler.LoopSoundInstance}.
 * This class is the single owner of the loop — the limbo biome's {@code ambient_sound}
 * wiring was removed so the bed cannot double-play.</p>
 *
 * <p>Everything resets on dimension change via the in-tick {@code inLimbo} check and on
 * disconnect via {@link ClientPlayerNetworkEvent.LoggingOut} (the
 * {@code QuasarSpawner.DisconnectReset} pattern), so neither stale emitter handles nor a
 * playing loop can survive into the next session.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LimboAmbience {
    /** Looping ambience emitters spawned by this class (client-only, never server-sent). */
    private static final ResourceLocation LIMBO_GODRAY =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_godray");
    private static final ResourceLocation LIMBO_FOG =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_fog");
    private static final ResourceLocation LIMBO_FOGBANK =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_fogbank");

    /** Limbo grade fade-in length after entering the dimension (~2 s, kept from v1). */
    private static final long POST_FADE_MILLIS = 2000L;

    /**
     * Rolling window of looping position-based emitters around the camera. Spawn cadence,
     * live cap and placement band are per-window; all spawns go through
     * {@link FxBudget.Channel#AMBIENT} and {@code reducedFx} doubles the cadence.
     */
    private static final class Window {
        private final ResourceLocation emitterId;
        private final int maxLive;
        private final int minIntervalTicks;
        private final int maxIntervalTicks;
        private final double minDistance;
        private final double maxDistance;
        /** Emitter center floats {@code yBiasMin}..{@code yBiasMin + yBiasRange} above the water plane. */
        private final double yBiasMin;
        private final double yBiasRange;

        private final ArrayDeque<ParticleEmitter> live = new ArrayDeque<>();
        private int countdown;

        Window(ResourceLocation emitterId, int maxLive, int minIntervalTicks, int maxIntervalTicks,
                double minDistance, double maxDistance, double yBiasMin, double yBiasRange) {
            this.emitterId = emitterId;
            this.maxLive = maxLive;
            this.minIntervalTicks = minIntervalTicks;
            this.maxIntervalTicks = maxIntervalTicks;
            this.minDistance = minDistance;
            this.maxDistance = maxDistance;
            this.yBiasMin = yBiasMin;
            this.yBiasRange = yBiasRange;
        }

        void tick(Minecraft minecraft, ClientLevel level) {
            prune();
            if (--countdown > 0) {
                return;
            }
            RandomSource random = level.random;
            int interval = random.nextIntBetweenInclusive(minIntervalTicks, maxIntervalTicks);
            // reducedFx halves ambient density by doubling the cadence (BorderFxRenderer pattern).
            countdown = EclipseClientConfig.reducedFx() ? interval * 2 : interval;

            ParticleEmitter emitter = QuasarSpawner.spawnManaged(
                    emitterId, pickSpawnPos(minecraft, level, random), FxBudget.Channel.AMBIENT);
            if (emitter == null) {
                // Budget refusal or Quasar unavailable/unknown id — skip silently; the
                // window simply stays thinner until the next cadence.
                return;
            }
            live.addLast(emitter);
            while (live.size() > maxLive) {
                removeEmitter(live.pollFirst());
            }
        }

        /**
         * A random spot {@code minDistance}..{@code maxDistance} blocks from the camera,
         * biased into this window's height band above the water plane. WORLD_SURFACE is one
         * of the two heightmaps synced to clients and counts water, so within the spawn
         * range of the camera (always loaded) it lands on the limbo ocean surface — or the
         * ship deck when over the ship, which is where the player stands anyway. A void
         * column (possible only if the limbo datapack changed) falls back to camera height.
         */
        private Vec3 pickSpawnPos(Minecraft minecraft, ClientLevel level, RandomSource random) {
            Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
            double angle = random.nextDouble() * Math.PI * 2.0D;
            double distance = minDistance + random.nextDouble() * (maxDistance - minDistance);
            double x = camera.x + Math.cos(angle) * distance;
            double z = camera.z + Math.sin(angle) * distance;
            int surfaceY = level.getHeight(Heightmap.Types.WORLD_SURFACE, Mth.floor(x), Mth.floor(z));
            double y = surfaceY > level.getMinBuildHeight()
                    ? surfaceY + yBiasMin + random.nextDouble() * yBiasRange
                    : camera.y + (random.nextDouble() - 0.5D) * 6.0D;
            return new Vec3(x, y, z);
        }

        /** Drops handles Veil already removed (e.g. the particle manager cleared on level swap). */
        private void prune() {
            Iterator<ParticleEmitter> it = live.iterator();
            while (it.hasNext()) {
                try {
                    if (it.next().isRemoved()) {
                        it.remove();
                    }
                } catch (Throwable t) {
                    it.remove();
                }
            }
        }

        /** Removes every live emitter — the leave-limbo/disconnect reset. */
        void clear() {
            if (live.isEmpty()) {
                countdown = 0;
                return;
            }
            for (ParticleEmitter emitter : live) {
                removeEmitter(emitter);
            }
            live.clear();
            countdown = 0;
        }
    }

    /** Small wisp clouds just above the water (v1 window; density now lives in the JSON). */
    private static final Window MOTES = new Window(
            S2CQuasarPayload.LIMBO_MOTES, 4, 40, 60, 12.0D, 20.0D, 1.0D, 3.0D);
    /** Tall soft god-ray shafts hanging higher up, drifting through the mid-air band. */
    private static final Window GODRAYS = new Window(
            LIMBO_GODRAY, 3, 90, 130, 10.0D, 24.0D, 8.0D, 7.0D);
    /** Dim violet fog sheets hugging the water surface (alpha-blended, so keep them few). */
    private static final Window FOG = new Window(
            LIMBO_FOG, 2, 110, 160, 8.0D, 22.0D, 0.4D, 1.2D);
    /**
     * IDEA-18 §3: big slow middle-distance fog banks rolling +X past the ship (the
     * buoy-lane heading) — the emitter's raised wind sells that the sea moves.
     */
    private static final Window FOGBANKS = new Window(
            LIMBO_FOGBANK, 2, 140, 200, 35.0D, 70.0D, 0.5D, 2.0D);
    private static final Window[] WINDOWS = {MOTES, GODRAYS, FOG, FOGBANKS};

    /** The playing loop instance, or {@code null} while none is live. */
    @Nullable
    private static LimboLoopSound loopSound;
    /**
     * Whether a loop instance was already started for the current limbo visit — one
     * {@code play(...)} attempt per visit, so a missing/broken sound file cannot cause a
     * per-tick retry (and warning) storm.
     */
    private static boolean soundStartedThisVisit;

    /** Epoch millis of entering limbo, or {@code -1} outside (drives the post fade-in). */
    private static volatile long limboEnterMillis = -1L;

    /** Scratch NDC projection of the zenith point (feeder-only; never escapes). */
    private static final Vector4f GODRAY_NDC = new Vector4f();

    /** C1 voyage drift speed: the caustic field streams astern at this rate (blocks/s). */
    private static final float VOYAGE_BLOCKS_PER_SECOND = 0.55F;
    /** {@code WaterlineY} fallback pushed far below the world until the anchor sync lands. */
    private static final float WATERLINE_UNKNOWN = -1.0E5F;

    /** This frame's inverse {@code Proj · ModelView} (NDC → camera-relative world). */
    private static final Matrix4f INV_VIEW_PROJ = new Matrix4f();
    /** Scratch for the forward matrix before inversion (render-thread only). */
    private static final Matrix4f MVP_SCRATCH = new Matrix4f();
    private static Vec3 frameCameraPos = Vec3.ZERO;
    private static boolean haveFrameMatrices;

    static {
        // v2 pipeline row — replaces W1's backward-compat Intensity-only row regardless of
        // class-load order (P2-W1 wiring: feature rows always win over default rows).
        VeilPostController.register(new VeilPostController.PipelineSpec(
                VeilPostController.LIMBO_POST,
                VeilPostController.PipelinePriority.GRADE,
                LimboAmbience::wantLimboPost,
                LimboAmbience::feedLimboPost));
    }

    private LimboAmbience() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            reset();
            return;
        }
        boolean inLimbo = level.dimension() == LimboDimension.LIMBO;
        if (inLimbo) {
            if (limboEnterMillis < 0L) {
                limboEnterMillis = System.currentTimeMillis();
            }
        } else {
            limboEnterMillis = -1L;
        }
        tickSound(minecraft, inLimbo);
        if (!inLimbo) {
            clearWindows();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        for (Window window : WINDOWS) {
            window.tick(minecraft, level);
        }
    }

    /** Disconnect reset hook (mirrors {@code QuasarSpawner.DisconnectReset}). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    /**
     * C1: captures this frame's EXACT render matrices (AFTER_SKY, view bobbing included —
     * the {@link SunTracker} capture point) and inverts them once on the CPU. The limbo post
     * shader reconstructs per-pixel world positions from the depth buffer with this inverse,
     * so the water mask and the depth buffer can never disagree the way a
     * {@code veil:camera}-based reconstruction would (its modelview strips bobbing).
     */
    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_SKY) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || level.dimension() != LimboDimension.LIMBO) {
            haveFrameMatrices = false;
            return;
        }
        MVP_SCRATCH.set(event.getProjectionMatrix()).mul(event.getModelViewMatrix());
        // A degenerate matrix (mid-resize frame) must not poison the shader with NaNs.
        if (!Float.isFinite(MVP_SCRATCH.determinant()) || Math.abs(MVP_SCRATCH.determinant()) < 1.0E-12F) {
            haveFrameMatrices = false;
            return;
        }
        INV_VIEW_PROJ.set(MVP_SCRATCH).invert();
        frameCameraPos = event.getCamera().getPosition();
        haveFrameMatrices = true;
    }

    // ------------------------------------------------------------------ post pipeline (v2)

    private static boolean wantLimboPost() {
        ClientLevel level = Minecraft.getInstance().level;
        return level != null && level.dimension() == LimboDimension.LIMBO;
    }

    /**
     * Per-frame uniform feed for {@code eclipse:limbo} v2 (frozen §3.3 names). Must not
     * allocate: writes primitives plus the pre-allocated {@link #GODRAY_NDC} scratch.
     */
    private static void feedLimboPost(PostPipeline pipeline) {
        float intensity = postIntensity();
        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        pipeline.getUniform("Intensity").setFloat(intensity);
        pipeline.getUniform("CausticsAmount").setFloat(intensity);
        pipeline.getUniform("Time").setFloat(seconds);

        ClientLevel level = Minecraft.getInstance().level;
        boolean valid = level != null
                && level.dimension() == LimboDimension.LIMBO
                && SunTracker.worldToNdc(LimboSpecialEffects.zenithWorldPoint(level), GODRAY_NDC);
        if (valid) {
            pipeline.getUniform("GodrayDir").setVector(GODRAY_NDC.x(), GODRAY_NDC.y());
        } else {
            // Zenith behind the camera (looking down): push the ray origin far offscreen so
            // the shader's look-up ramp fades the god rays out instead of popping.
            pipeline.getUniform("GodrayDir").setVector(10.0F, 10.0F);
        }

        // --- v3 (C1): water mask + world anchoring + curvature + voyage drift ------------
        if (haveFrameMatrices && level != null && level.dimension() == LimboDimension.LIMBO) {
            pipeline.getUniform("InvViewProj").setMatrix(INV_VIEW_PROJ);
            pipeline.getUniform("CameraPos").setVector(
                    (float) frameCameraPos.x, (float) frameCameraPos.y, (float) frameCameraPos.z);
            pipeline.getUniform("WaterlineY").setFloat(
                    (float) LimboSpecialEffects.clientWaterlineY(level));
        } else {
            // No frame captured yet (first frame / mid-resize): park the waterline far below
            // the world so the band test is empty instead of reading NaN reconstructions.
            pipeline.getUniform("InvViewProj").setMatrix(MVP_SCRATCH.identity());
            pipeline.getUniform("CameraPos").setVector(0.0F, 0.0F, 0.0F);
            pipeline.getUniform("WaterlineY").setFloat(WATERLINE_UNKNOWN);
        }
        // Ship forward is +X: an increasing +X lookup offset streams the caustic features
        // toward −X, i.e. slowly astern past the hull (the item-6 sailing illusion). Wraps
        // hourly with the same period as Time (one small jump per hour, like Time itself).
        pipeline.getUniform("VoyageOffset").setVector(seconds * VOYAGE_BLOCKS_PER_SECOND, 0.0F);
        pipeline.getUniform("CurveAmount").setFloat(
                EclipseClientConfig.reducedFx() ? 0.0F : intensity);
        pipeline.getUniform("FarDist").setFloat(farDistBlocks());
    }

    /** Approximate distance (blocks) where the loaded sea geometry ends (≥ 96, ≤ 512). */
    private static float farDistBlocks() {
        int chunks = Minecraft.getInstance().options.getEffectiveRenderDistance();
        return Mth.clamp(chunks * 16.0F, 96.0F, 512.0F);
    }

    /** Current limbo grade intensity in [0,1]; eased ~2 s fade-in after entering limbo (v1 curve). */
    private static float postIntensity() {
        long start = limboEnterMillis;
        if (start < 0L) {
            return 0.0F;
        }
        float linear = Mth.clamp((System.currentTimeMillis() - start) / (float) POST_FADE_MILLIS, 0.0F, 1.0F);
        return 1.0F - (1.0F - linear) * (1.0F - linear); // ease-out quad, as in v1
    }

    // ------------------------------------------------------------------ lifecycle

    /** Hard reset: kills the loop instantly (no fade) and drops every emitter handle. */
    private static void reset() {
        LimboLoopSound sound = loopSound;
        if (sound != null) {
            sound.forceStop();
            loopSound = null;
        }
        soundStartedThisVisit = false;
        limboEnterMillis = -1L;
        haveFrameMatrices = false;
        clearWindows();
    }

    private static void clearWindows() {
        for (Window window : WINDOWS) {
            window.clear();
        }
    }

    /** Starts/fades the ambient loop to match {@code inLimbo}. */
    private static void tickSound(Minecraft minecraft, boolean inLimbo) {
        LimboLoopSound sound = loopSound;
        if (inLimbo) {
            if (sound == null || sound.isStopped()) {
                if (!soundStartedThisVisit) {
                    soundStartedThisVisit = true;
                    sound = new LimboLoopSound();
                    loopSound = sound;
                    minecraft.getSoundManager().play(sound);
                }
            } else {
                // Covers re-entering limbo mid-fade-out: the same instance fades back in.
                sound.fadeIn();
            }
            return;
        }
        soundStartedThisVisit = false;
        if (sound != null) {
            sound.fadeOut();
            if (sound.isStopped()) {
                loopSound = null;
            }
        }
    }

    private static void removeEmitter(ParticleEmitter emitter) {
        try {
            if (!emitter.isRemoved()) {
                emitter.remove();
            }
        } catch (Throwable ignored) {
            // Teardown-order safe (QuasarSpawner.clearAttached pattern): dropping the
            // reference is the part that matters.
        }
    }

    /**
     * The looping {@code ambient.limbo_loop} bed. Fade pattern of vanilla's
     * {@code BiomeAmbientSoundsHandler.LoopSoundInstance}: volume ramps linearly over
     * {@value #FADE_TICKS} ticks toward {@value #MAX_VOLUME} while fading in, back to zero
     * (then {@link #stop()}) while fading out. {@code relative} — the bed follows the
     * listener like vanilla biome ambience instead of sitting at a world position.
     */
    static final class LimboLoopSound extends AbstractTickableSoundInstance {
        private static final float MAX_VOLUME = 0.6F;
        private static final int FADE_TICKS = 40;

        /** {@code +1} fading in, {@code -1} fading out. */
        private int fadeDirection = 1;
        private int fade;

        private LimboLoopSound() {
            super(EclipseSounds.AMBIENT_LIMBO_LOOP.get(), SoundSource.AMBIENT,
                    SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = true;
        }

        @Override
        public void tick() {
            if (this.fade < 0) {
                this.stop();
                return;
            }
            this.fade = Math.min(this.fade + this.fadeDirection, FADE_TICKS);
            this.volume = MAX_VOLUME * Mth.clamp(this.fade / (float) FADE_TICKS, 0.0F, 1.0F);
        }

        void fadeIn() {
            this.fade = Math.max(0, this.fade);
            this.fadeDirection = 1;
        }

        void fadeOut() {
            this.fade = Math.min(this.fade, FADE_TICKS);
            this.fadeDirection = -1;
        }

        /** Disconnect teardown: kill the instance immediately, skipping the fade. */
        void forceStop() {
            this.stop();
        }
    }
}
