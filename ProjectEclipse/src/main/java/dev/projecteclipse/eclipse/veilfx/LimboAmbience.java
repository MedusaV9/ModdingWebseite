package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayDeque;
import java.util.Iterator;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
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

/**
 * Client-side ambience of the Limbo dimension, active only while the local level is
 * {@code eclipse:limbo}:
 * <ul>
 *   <li><b>Motes</b>: every {@value #MIN_SPAWN_INTERVAL_TICKS}&ndash;{@value
 *       #MAX_SPAWN_INTERVAL_TICKS} ticks (interval doubled under {@code reducedFx}, the
 *       {@code BorderFxRenderer} cadence pattern) one {@code eclipse:limbo_motes} Quasar
 *       emitter is spawned {@value #MIN_SPAWN_DISTANCE}&ndash;{@value #MAX_SPAWN_DISTANCE}
 *       blocks from the camera, biased slightly above the water plane. The emitter JSON is
 *       {@code loop: true} and Veil never expires a looping position-based emitter, so the
 *       handles returned by {@link QuasarSpawner#spawnManaged} are kept and the oldest is
 *       removed beyond {@value #MAX_LIVE_EMITTERS} live ones — a rolling window of mote
 *       clouds that follows the player without ever leaking emitters.</li>
 *   <li><b>Sound</b>: one looping {@code ambient.limbo_loop} instance
 *       ({@link SoundSource#AMBIENT}, peak volume {@code 0.6}) that fades in over
 *       {@value LimboLoopSound#FADE_TICKS} ticks after entering limbo and fades out (then
 *       stops) after leaving, modeled on vanilla's
 *       {@code BiomeAmbientSoundsHandler.LoopSoundInstance}. This class is the single owner
 *       of the loop — the limbo biome's {@code ambient_sound} wiring was removed so the bed
 *       cannot double-play.</li>
 * </ul>
 *
 * <p>Both halves reset on dimension change via the in-tick {@code inLimbo} check and on
 * disconnect via {@link ClientPlayerNetworkEvent.LoggingOut} (the
 * {@code QuasarSpawner.DisconnectReset} pattern), so neither stale emitter handles nor a
 * playing loop can survive into the next session.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LimboAmbience {
    private static final int MIN_SPAWN_INTERVAL_TICKS = 40;
    private static final int MAX_SPAWN_INTERVAL_TICKS = 60;
    private static final double MIN_SPAWN_DISTANCE = 12.0D;
    private static final double MAX_SPAWN_DISTANCE = 20.0D;
    /** Live looping mote emitters kept at once (oldest beyond this is removed). */
    private static final int MAX_LIVE_EMITTERS = 4;
    /** Mote cloud center floats this far (plus up to {@value #WATER_BIAS_RANGE}) above the water plane. */
    private static final double WATER_BIAS_MIN = 1.0D;
    private static final double WATER_BIAS_RANGE = 3.0D;

    /** Live mote emitters in spawn order (all {@code loop: true}; removed oldest-first). */
    private static final ArrayDeque<ParticleEmitter> LIVE_MOTES = new ArrayDeque<>();
    /** Ticks until the next mote emitter spawn; {@code <= 0} spawns immediately. */
    private static int moteCountdown;
    /** The playing loop instance, or {@code null} while none is live. */
    @Nullable
    private static LimboLoopSound loopSound;
    /**
     * Whether a loop instance was already started for the current limbo visit — one
     * {@code play(...)} attempt per visit, so a missing/broken sound file cannot cause a
     * per-tick retry (and warning) storm.
     */
    private static boolean soundStartedThisVisit;

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
        tickSound(minecraft, inLimbo);
        tickMotes(minecraft, level, inLimbo);
    }

    /** Disconnect reset hook (mirrors {@code QuasarSpawner.DisconnectReset}). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    /** Hard reset: kills the loop instantly (no fade) and drops every mote handle. */
    private static void reset() {
        LimboLoopSound sound = loopSound;
        if (sound != null) {
            sound.forceStop();
            loopSound = null;
        }
        soundStartedThisVisit = false;
        clearMotes();
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

    /** Spawns/prunes the rolling window of mote emitters while in limbo; clears it outside. */
    private static void tickMotes(Minecraft minecraft, ClientLevel level, boolean inLimbo) {
        if (!inLimbo) {
            clearMotes();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        prune();
        if (--moteCountdown > 0) {
            return;
        }
        RandomSource random = level.random;
        int interval = random.nextIntBetweenInclusive(MIN_SPAWN_INTERVAL_TICKS, MAX_SPAWN_INTERVAL_TICKS);
        // reducedFx halves the ambient density by doubling the cadence (BorderFxRenderer pattern).
        moteCountdown = EclipseClientConfig.reducedFx() ? interval * 2 : interval;

        ParticleEmitter emitter = QuasarSpawner.spawnManaged(
                S2CQuasarPayload.LIMBO_MOTES, pickSpawnPos(minecraft, level, random));
        if (emitter == null) {
            // Quasar unavailable/unknown id — QuasarSpawner logged it; ambience goes without motes.
            return;
        }
        LIVE_MOTES.addLast(emitter);
        while (LIVE_MOTES.size() > MAX_LIVE_EMITTERS) {
            removeEmitter(LIVE_MOTES.pollFirst());
        }
    }

    /**
     * A random spot {@value #MIN_SPAWN_DISTANCE}&ndash;{@value #MAX_SPAWN_DISTANCE} blocks
     * from the camera, biased slightly above the water plane. WORLD_SURFACE is one of the two
     * heightmaps synced to clients and counts water, so within 20 blocks of the camera (always
     * loaded) it lands on the limbo ocean surface — or the ship deck when over the ship, which
     * is where the player stands anyway. A void column (possible only if the limbo datapack
     * changed) falls back to camera height.
     */
    private static Vec3 pickSpawnPos(Minecraft minecraft, ClientLevel level, RandomSource random) {
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        double angle = random.nextDouble() * Math.PI * 2.0D;
        double distance = MIN_SPAWN_DISTANCE + random.nextDouble() * (MAX_SPAWN_DISTANCE - MIN_SPAWN_DISTANCE);
        double x = camera.x + Math.cos(angle) * distance;
        double z = camera.z + Math.sin(angle) * distance;
        int surfaceY = level.getHeight(Heightmap.Types.WORLD_SURFACE, Mth.floor(x), Mth.floor(z));
        double y = surfaceY > level.getMinBuildHeight()
                ? surfaceY + WATER_BIAS_MIN + random.nextDouble() * WATER_BIAS_RANGE
                : camera.y + (random.nextDouble() - 0.5D) * 6.0D;
        return new Vec3(x, y, z);
    }

    /** Drops handles Veil already removed (e.g. the particle manager cleared on level swap). */
    private static void prune() {
        Iterator<ParticleEmitter> it = LIVE_MOTES.iterator();
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

    /** Removes every live mote emitter — the leave-limbo/disconnect reset. */
    private static void clearMotes() {
        if (LIVE_MOTES.isEmpty()) {
            moteCountdown = 0;
            return;
        }
        for (ParticleEmitter emitter : LIVE_MOTES) {
            removeEmitter(emitter);
        }
        LIVE_MOTES.clear();
        moteCountdown = 0;
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
