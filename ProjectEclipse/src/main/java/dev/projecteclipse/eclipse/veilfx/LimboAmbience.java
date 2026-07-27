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
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
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
 * after entering limbo, as in v1), {@code GodrayDir} (LIMBOFIX2: NDC of the FIXED eclipse
 * direction {@link LimboSpecialEffects#celestialDirection} projected through
 * {@link SunTracker#dirToNdc} — a {@code w=0} direction projection, the exact sky-pass
 * transform; pushed far offscreen while behind the camera), {@code CausticsAmount} and
 * {@code Time}.</p>
 *
 * <p><b>Post pipeline (v3, PLAN-C C1)</b>: the feeder additionally supplies the water-mask /
 * horizon set — {@code InvViewProj} + {@code CameraPos} (this frame's exact AFTER_SKY render
 * matrices captured by {@link #onRenderLevelStage}, view bobbing included, inverted once per
 * frame — the {@link SunTracker} law: never reconstruct from {@code veil:camera}),
 * {@code WaterlineY} ({@code GhostShipBuilder.waterlineY} reaching the client through the
 * {@code ship_deck} anchor sync, see {@link LimboSpecialEffects#clientWaterlineY}),
 * {@code VoyageOffset} (steadily increasing world-XZ scroll along ship forward −X→+X — the
 * caustic field streams slowly astern past the hull: the shader half of the "sailing"
 * illusion; accumulates continuously from the limbo-entry instant instead of wrapping
 * hourly like {@code Time}, so it never jumps mid-visit) and {@code FarDist} (effective
 * render distance in blocks, where the loaded sea geometry ends). LIMBOFIX: the
 * {@code CurveAmount} horizon-curvature uniform is gone — the shader's UV warp produced
 * a visible seam line across the screen and was removed on both sides.</p>
 *
 * <p><b>v4 (FXTEAM-LIMBO)</b>: three additions, all inside the existing budget/ladder:</p>
 * <ul>
 *   <li><b>{@code LightningGlow} uniform</b> — deterministic far storm-glow pulses
 *       ({@link #feedStormGlow}): an {@code ECLIPSE_SEED}-hashed slot schedule (~every
 *       67&nbsp;s on average) picks a horizon azimuth and a ≤2&nbsp;s lead+echo flash
 *       envelope; every client sees the same flash at the same wall-clock second because
 *       the schedule derives from the same hourly {@code Time} base. Fed {@code (1,0,0)}
 *       (strength 0) under {@code reducedFx} — the reduced-FX ladder.</li>
 *   <li><b>God-ray sway</b> — the {@code GODRAYS} window carries a per-emitter base
 *       position and leans its live emitters on a shared ~12.5&nbsp;s roll phase
 *       ({@code Z} dominant, slight {@code X} lean — the ship rolls about its +X long
 *       axis), so the shaft colonnade sways with the hull. Pure
 *       {@link ParticleEmitter#setPosition} moves, zero extra particles.</li>
 *   <li><b>Near-focus motes</b> ({@code eclipse:limbo_motes_near}) — a fourth rolling
 *       window of few, LARGE, very faint wisps 3–7 blocks from the camera: the bokeh
 *       foreground of the depth-layered dust (the existing motes JSON was retuned smaller
 *       + crisper as the in-focus mid layer). Skipped AND cleared entirely under
 *       {@code reducedFx} (the drift-cue foam-glint ladder: garnish layers drop first —
 *       big near-camera billboards are the most expensive overdraw in the scene).</li>
 * </ul>
 *
 * <p><b>v4.1 (VEIL-REPASS-2)</b>: the {@code SoulShoal} uniform ({@link #feedSoulShoal}) —
 * rare deterministic soul-shoal crossings under the water surface, on the same
 * {@code ECLIPSE_SEED}-hashed slot law as the storm glow (distinct salts, so the two
 * schedules cannot correlate). Zero vector when idle or under {@code reducedFx}.</p>
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
    private static final ResourceLocation LIMBO_MOTES_NEAR =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_motes_near");

    /** Limbo grade fade-in length after entering the dimension (~2 s, kept from v1). */
    private static final long POST_FADE_MILLIS = 2000L;

    /**
     * v4 god-ray sway: shared roll period (seconds). 12.5 s divides the 12000-tick sway
     * clock exactly (600 s = 48 periods), so the {@code gameTime % 12000} wrap is seamless.
     */
    private static final double ROLL_PERIOD_SECONDS = 12.5D;
    /** v4 storm glow: schedule slot length (seconds). ~55% of slots flash → ~67 s average. */
    private static final float STORM_SLOT_SECONDS = 37.0F;

    /** v4.1 soul shoal: schedule slot length (seconds). ~30% of slots host one → ~4 min average. */
    private static final float SHOAL_SLOT_SECONDS = 73.0F;
    /** v4.1 soul shoal: duration of one crossing (seconds), fade-in/out included. */
    private static final float SHOAL_CROSS_SECONDS = 26.0F;
    /** v4.1 soul shoal: swim speed (blocks/s) — ~83 blocks of path per crossing. */
    private static final float SHOAL_SPEED = 3.2F;

    /**
     * Rolling window of looping position-based emitters around the camera. Spawn cadence,
     * live cap and placement band are per-window; all spawns go through
     * {@link FxBudget.Channel#AMBIENT} and {@code reducedFx} doubles the cadence.
     *
     * <p>v4: a window may additionally carry a <b>roll sway</b> ({@code swayAmplitude} > 0
     * leans live emitters on the shared {@value #ROLL_PERIOD_SECONDS}-second roll phase —
     * god-ray shafts sway with the ship) and/or be marked <b>garnish</b>
     * ({@code skipUnderReducedFx}: the window is skipped AND cleared while
     * {@code reducedFx} is on — the drift-cue foam-glint ladder).</p>
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
        /** v4: lateral roll-sway amplitude in blocks ({@code 0} = static emitters). */
        private final double swayAmplitude;
        /** v4: garnish window — skipped and cleared entirely under {@code reducedFx}. */
        private final boolean skipUnderReducedFx;

        /** v4: live handle + its spawn anchor + a small per-emitter roll-phase offset. */
        private record Live(ParticleEmitter emitter, Vec3 base, float phase) {}

        private final ArrayDeque<Live> live = new ArrayDeque<>();
        private int countdown;

        Window(ResourceLocation emitterId, int maxLive, int minIntervalTicks, int maxIntervalTicks,
                double minDistance, double maxDistance, double yBiasMin, double yBiasRange,
                double swayAmplitude, boolean skipUnderReducedFx) {
            this.emitterId = emitterId;
            this.maxLive = maxLive;
            this.minIntervalTicks = minIntervalTicks;
            this.maxIntervalTicks = maxIntervalTicks;
            this.minDistance = minDistance;
            this.maxDistance = maxDistance;
            this.yBiasMin = yBiasMin;
            this.yBiasRange = yBiasRange;
            this.swayAmplitude = swayAmplitude;
            this.skipUnderReducedFx = skipUnderReducedFx;
        }

        void tick(Minecraft minecraft, ClientLevel level) {
            if (skipUnderReducedFx && EclipseClientConfig.reducedFx()) {
                // Garnish tier: clear (not just skip) so a mid-session toggle cannot leave
                // looping emitters behind forever.
                clear();
                return;
            }
            prune();
            sway(level);
            if (--countdown > 0) {
                return;
            }
            RandomSource random = level.random;
            int interval = random.nextIntBetweenInclusive(minIntervalTicks, maxIntervalTicks);
            // reducedFx halves ambient density by doubling the cadence (BorderFxRenderer pattern).
            countdown = EclipseClientConfig.reducedFx() ? interval * 2 : interval;

            Vec3 pos = pickSpawnPos(minecraft, level, random);
            ParticleEmitter emitter = QuasarSpawner.spawnManaged(
                    emitterId, pos, FxBudget.Channel.AMBIENT);
            if (emitter == null) {
                // Budget refusal or Quasar unavailable/unknown id — skip silently; the
                // window simply stays thinner until the next cadence.
                return;
            }
            live.addLast(new Live(emitter, pos, (random.nextFloat() - 0.5F) * 0.8F));
            while (live.size() > maxLive) {
                removeEmitter(live.pollFirst().emitter());
            }
        }

        /**
         * v4: leans every live emitter on the shared roll phase — Z sway dominant plus a
         * slight, slower X lean (the ship rolls about its +X long axis, so the god-ray
         * colonnade tips sideways). Only fresh particles spawn from the moved origin;
         * with ~5 s particle lifetimes the whole shaft visibly lags into the lean, which
         * is exactly the heavy, pendulous read a tall light shaft should have. Costs a
         * handful of {@link ParticleEmitter#setPosition} calls per tick, zero particles.
         */
        private void sway(ClientLevel level) {
            if (swayAmplitude <= 0.0D || live.isEmpty()) {
                return;
            }
            // 12000-tick clock = 48 exact roll periods (and 24 exact lean periods) — no wrap pop.
            double sec = (level.getGameTime() % 12000L) / 20.0D;
            double omega = (Math.PI * 2.0D) / ROLL_PERIOD_SECONDS;
            for (Live entry : live) {
                double sway = Math.sin(sec * omega + entry.phase()) * swayAmplitude;
                double lean = Math.sin(sec * omega * 0.5D + entry.phase() * 1.7D)
                        * swayAmplitude * 0.45D;
                Vec3 base = entry.base();
                entry.emitter().setPosition(base.x + lean, base.y, base.z + sway);
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
            Iterator<Live> it = live.iterator();
            while (it.hasNext()) {
                try {
                    if (it.next().emitter().isRemoved()) {
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
            for (Live entry : live) {
                removeEmitter(entry.emitter());
            }
            live.clear();
            countdown = 0;
        }
    }

    /** Small wisp clouds just above the water (v1 window; density now lives in the JSON). */
    private static final Window MOTES = new Window(
            S2CQuasarPayload.LIMBO_MOTES, 4, 40, 60, 12.0D, 20.0D, 1.0D, 3.0D, 0.0D, false);
    /**
     * Tall soft god-ray shafts hanging higher up, drifting through the mid-air band.
     * v4: sways ±0.9 blocks on the shared roll phase — the shafts lean with the ship.
     */
    private static final Window GODRAYS = new Window(
            LIMBO_GODRAY, 3, 90, 130, 10.0D, 24.0D, 8.0D, 7.0D, 0.9D, false);
    /**
     * Dim violet fog sheets hugging the water surface (alpha-blended, so keep them few).
     * F-088 polish: spawn window pushed out 8 → 14 blocks — the emitter's billboards
     * reach ~8 ± 7 blocks around their center, so an 8-block spawn could park a sheet
     * directly in front of the camera.
     */
    private static final Window FOG = new Window(
            LIMBO_FOG, 2, 110, 160, 14.0D, 22.0D, 0.4D, 1.2D, 0.0D, false);
    /**
     * IDEA-18 §3: big slow middle-distance fog banks rolling +X past the ship (the
     * buoy-lane heading) — the emitter's raised wind sells that the sea moves.
     */
    private static final Window FOGBANKS = new Window(
            LIMBO_FOGBANK, 2, 140, 200, 35.0D, 70.0D, 0.5D, 2.0D, 0.0D, false);
    /**
     * v4 depth-layered dust, bokeh foreground: 1–2 LARGE very faint wisps 3–7 blocks out
     * (big + dim + soft sprite = out-of-focus read; the retuned {@code limbo_motes} JSON is
     * the smaller, crisper in-focus layer behind them). Garnish tier — near-camera
     * billboards are the scene's costliest overdraw, so the whole window drops under
     * {@code reducedFx} instead of merely halving.
     */
    private static final Window NEAR_MOTES = new Window(
            LIMBO_MOTES_NEAR, 2, 70, 100, 3.0D, 7.0D, 0.8D, 2.5D, 0.0D, true);
    private static final Window[] WINDOWS = {MOTES, GODRAYS, FOG, FOGBANKS, NEAR_MOTES};

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
        // LIMBOFIX2: the god rays track the FIXED eclipse direction (the sky pass's
        // LimboSpecialEffects.CELESTIAL_DIR) through a w=0 direction projection — the
        // same transform the sky pass renders with, so the screen-space rays sit exactly
        // on the disc no matter where the camera is or how it turns. The old feeder
        // projected the finite zenith WORLD POINT, which re-aimed with every camera move.
        boolean valid = level != null
                && level.dimension() == LimboDimension.LIMBO
                && SunTracker.dirToNdc(LimboSpecialEffects.celestialDirection(), GODRAY_NDC);
        if (valid) {
            pipeline.getUniform("GodrayDir").setVector(GODRAY_NDC.x(), GODRAY_NDC.y());
        } else {
            // Disc behind the camera (looking away): push the ray origin far offscreen so
            // the shader's look-up ramp fades the god rays out instead of popping.
            pipeline.getUniform("GodrayDir").setVector(10.0F, 10.0F);
        }

        // --- v3 (C1): water mask + world anchoring + voyage drift ------------------------
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
        // toward −X, i.e. slowly astern past the hull (the item-6 sailing illusion).
        // Continuous accumulation from the limbo-entry instant — unlike the hourly Time
        // base, this never wraps mid-visit, so the caustic field cannot teleport once an
        // hour (the shader feeds it into non-periodic noise, so no modulo is seamless).
        // It resets to 0 on the next limbo entry, while the pipeline is faded out anyway.
        long enter = limboEnterMillis;
        float voyageSeconds = enter < 0L ? 0.0F : (System.currentTimeMillis() - enter) / 1000.0F;
        pipeline.getUniform("VoyageOffset").setVector(voyageSeconds * VOYAGE_BLOCKS_PER_SECOND, 0.0F);
        pipeline.getUniform("FarDist").setFloat(farDistBlocks());
        // v4 reduced-motion gate: swells, micro-ripples and glints
        // flatten back to the v3 water look under reduced FX —
        // "cheap ALU" covers performance, not the reduced-motion contract.
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);

        // --- v4: far storm-glow pulses -----------------------------------------------------
        feedStormGlow(pipeline, seconds, intensity);

        // --- v4.1: soul shoal crossings ----------------------------------------------------
        feedSoulShoal(pipeline, seconds, intensity, level);
    }

    /**
     * v4 — the {@code LightningGlow} uniform: occasional soft far-storm glow on the horizon
     * (no bolts). Deterministic slot schedule over the hourly {@code Time} base: each
     * {@value #STORM_SLOT_SECONDS}-second slot is hashed ({@code ECLIPSE_SEED} mixer, so
     * every client flashes together) into flash/no-flash (~55%), a start offset, and a
     * horizon azimuth; an active flash runs a ≤2 s lead+echo envelope (sharp attack,
     * exponential decay, one dimmer echo ~0.45 s later — the classic distant
     * cloud-lightning double pulse). Fed strength 0 under {@code reducedFx} (the
     * reduced-FX ladder) — the shader then skips its ray reconstruction too.
     * Pure per-frame math: no allocations, no state.
     */
    private static void feedStormGlow(PostPipeline pipeline, float seconds, float intensity) {
        float strength = 0.0F;
        float azimuth = 0.0F;
        // haveFrameMatrices guard: the glow direction comes from a shader-side ray through
        // InvViewProj — while that uniform is parked at identity (first frame / mid-resize)
        // a nonzero strength would paint a spurious glow through a garbage ray.
        if (!EclipseClientConfig.reducedFx() && intensity > 0.0F && haveFrameMatrices) {
            int slot = (int) (seconds / STORM_SLOT_SECONDS);
            if (hash01(slot, 0) < 0.55D) {
                float start = (float) (hash01(slot, 1) * (STORM_SLOT_SECONDS - 3.0F));
                float t = seconds - slot * STORM_SLOT_SECONDS - start;
                if (t >= 0.0F && t <= 2.0F) {
                    float lead = (float) Math.exp(-t * 4.0D);
                    float echo = (float) Math.exp(-(t - 0.45F) * (t - 0.45F) * 22.0D) * 0.6F;
                    strength = Math.min(1.0F, lead + echo) * 0.85F * intensity;
                }
                azimuth = (float) (hash01(slot, 2) * Math.PI * 2.0D);
            }
        }
        pipeline.getUniform("LightningGlow").setVector(
                Mth.cos(azimuth), Mth.sin(azimuth), strength);
    }

    /**
     * v4.1 — the {@code SoulShoal} uniform: rare deterministic crossings of a school of
     * tiny soul-green lights under the water surface. Same schedule law as
     * {@link #feedStormGlow}: each {@value #SHOAL_SLOT_SECONDS}-second slot of the hourly
     * {@code Time} base is hashed ({@code ECLIPSE_SEED} mixer, distinct salts — every
     * client sees the same shoal at the same second) into crossing/no-crossing (~30%), a
     * start offset, a swim heading and a closest-approach offset 6–20&nbsp;blocks abeam of
     * the ship anchor; the school then swims a straight {@value #SHOAL_SPEED}&nbsp;blocks/s
     * line through that point, mid-crossing at the closest approach, with a sin fade-in/out
     * envelope. The shader renders the fish in shoal-local space, so the formation visibly
     * translates (unlike the world-anchored glints). Packed {@code (centerX, centerZ,
     * headingX·env, headingZ·env)}; idle/{@code reducedFx} feeds a zero vector (the
     * reduced-FX ladder), and the anchor-relative path keeps the world-space
     * float math small. Pure per-frame math: no allocations, no state.
     */
    private static void feedSoulShoal(PostPipeline pipeline, float seconds, float intensity,
            @Nullable ClientLevel level) {
        float cx = 0.0F;
        float cz = 0.0F;
        float dx = 0.0F;
        float dz = 0.0F;
        if (!EclipseClientConfig.reducedFx() && intensity > 0.0F && haveFrameMatrices
                && level != null && level.dimension() == LimboDimension.LIMBO) {
            int slot = (int) (seconds / SHOAL_SLOT_SECONDS);
            if (hash01(slot, 3) < 0.30D) {
                float start = (float) (hash01(slot, 4)
                        * (SHOAL_SLOT_SECONDS - SHOAL_CROSS_SECONDS - 2.0F));
                float t = seconds - slot * SHOAL_SLOT_SECONDS - start;
                if (t >= 0.0F && t <= SHOAL_CROSS_SECONDS) {
                    Vec3 zenith = LimboSpecialEffects.zenithWorldPoint(level);
                    float heading = (float) (hash01(slot, 5) * Math.PI * 2.0D);
                    float hx = Mth.cos(heading);
                    float hz = Mth.sin(heading);
                    // Closest-approach point: a hashed 6–20 blocks abeam of the ship
                    // anchor, on a hashed side — the school passes NEAR the hull, never
                    // exactly under the keel.
                    float abeam = (float) (6.0D + hash01(slot, 6) * 14.0D)
                            * (hash01(slot, 7) < 0.5D ? -1.0F : 1.0F);
                    float along = (t - SHOAL_CROSS_SECONDS * 0.5F) * SHOAL_SPEED;
                    cx = (float) zenith.x - hz * abeam + hx * along;
                    cz = (float) zenith.z + hx * abeam + hz * along;
                    float env = Mth.sin(t / SHOAL_CROSS_SECONDS * (float) Math.PI);
                    dx = hx * env * intensity;
                    dz = hz * env * intensity;
                }
            }
        }
        pipeline.getUniform("SoulShoal").setVector(cx, cz, dx, dz);
    }

    /**
     * Fixed-seed hash 0..1 (the {@code LimboSeascape.hash01} mixer with its own salt so the
     * storm schedule cannot correlate with the horizon-ship reseeds) — deterministic on
     * every client, which is what synchronizes the storm flashes.
     */
    private static double hash01(int a, int b) {
        long h = DiscMapData.ECLIPSE_SEED ^ (a * 341873128712L + b * 132897987541L + 0x7C3A9E15L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
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
