package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

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
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CampfireBlock;
import net.minecraft.world.level.block.state.BlockState;
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
 *       every 3 ticks instead of 5): small drifting wisps just above the water plane.
 *       F-107 (part 4) hard-capped them to tiny far dust: alpha peak 0.28 → 0.05 in the
 *       JSON (size ≤ 0.085 half-edge and wind 0.0006 + 0.96 drag were already in).</li>
 *   <li><b>Fog layers</b> ({@code eclipse:limbo_fog}): big dim alpha-blended violet sheets
 *       hugging the water surface.</li>
 * </ul>
 *
 * <p><b>F-107 (part 4, radical removal)</b>: the world-space Quasar god-ray shafts
 * ({@code eclipse:limbo_godray}) and the near-focus bokeh motes
 * ({@code eclipse:limbo_motes_near}) are GONE — window, emitter JSONs, dedicated textures
 * and generator scripts. Three tuning rounds (parts 1–3) could not stop large additive
 * quads from reading as hard-edged violet capsules/discs at the frame edge on low-end /
 * software-GL clients (8-bit additive quantization + display gamma cut every falloff into
 * an iso-alpha contour). The scene keeps its ambience from the soft fog/fogbank sheets,
 * the tiny far motes, the water shader and the lanterns; the screen-space god rays of the
 * {@code eclipse:limbo} post pipeline (the {@code GodrayDir} uniform fed below) are
 * untouched — they never produced the artifact. NO replacement emitter may be added
 * here without a fresh look review.</p>
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
 * <p><b>v4 (FXTEAM-LIMBO)</b>: the {@code LightningGlow} uniform — deterministic far
 * storm-glow pulses ({@link #feedStormGlow}): an {@code ECLIPSE_SEED}-hashed slot schedule
 * (~every 67&nbsp;s on average) picks a horizon azimuth and a ≤2&nbsp;s lead+echo flash
 * envelope; every client sees the same flash at the same wall-clock second because the
 * schedule derives from the same hourly {@code Time} base. Fed {@code (1,0,0)} (strength 0)
 * under {@code reducedFx} — the reduced-FX ladder. (v4's other two additions — the god-ray
 * roll sway and the near-focus bokeh motes — were removed with their windows in F-107
 * part 4, see above.)</p>
 *
 * <p><b>v4.1 (VEIL-REPASS-2)</b>: the {@code SoulShoal} uniform ({@link #feedSoulShoal}) —
 * rare deterministic soul-shoal crossings under the water surface, on the same
 * {@code ECLIPSE_SEED}-hashed slot law as the storm glow (distinct salts, so the two
 * schedules cannot correlate). Zero vector when idle or under {@code reducedFx}.</p>
 *
 * <p><b>v5 (F-104, IDEA-18 §4/§6/§7/§8/§10)</b>: the inhabited ghost sea — a sixth
 * rolling window ({@code eclipse:limbo_moths}, spawns biased onto cached soul-light
 * positions instead of the camera ring), the fixed-position {@link SpireEmbers} handler
 * (≤1 looping {@code eclipse:limbo_embers} emitter per frozen seascape spire, ≤160 blocks
 * camera distance, garnish tier), and the {@link LimboRowChant} ticker (row dirge on the
 * 60&nbsp;t row clock, rigging creaks on the recovery beat, drowned bell tolls from below
 * the sea — all with tilt/hostile-crew guards). Everything rides the existing
 * budget/ladder and the window-clear seam.</p>
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
    private static final ResourceLocation LIMBO_FOG =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_fog");
    private static final ResourceLocation LIMBO_FOGBANK =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_fogbank");
    /** F-104 (IDEA-18 §6): tiny pale moths orbiting the soul lights. */
    private static final ResourceLocation LIMBO_MOTHS =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_moths");
    /** F-104 (IDEA-18 §8): soul-ember columns above the seascape spires. */
    private static final ResourceLocation LIMBO_EMBERS =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_embers");

    /** Limbo grade fade-in length after entering the dimension (~2 s, kept from v1). */
    private static final long POST_FADE_MILLIS = 2000L;

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
     * <p>F-107 (part 4): the v4 roll-sway and garnish-tier ({@code skipUnderReducedFx})
     * machinery left with the god-ray and near-mote windows — the only users.</p>
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
        /**
         * F-104 (IDEA-18 §6): bias spawns onto actual soul lights — instead of the
         * camera-ring {@link #pickSpawnPos}, spawn 0.5 blocks off a cached
         * soul-lantern/lit-soul-campfire position (see {@link #soulLightPositions});
         * the camera ring stays the fallback over open water (the buoy lanterns line
         * the lane anyway).
         */
        private final boolean biasToSoulLights;

        private final ArrayDeque<ParticleEmitter> live = new ArrayDeque<>();
        private int countdown;

        Window(ResourceLocation emitterId, int maxLive, int minIntervalTicks, int maxIntervalTicks,
                double minDistance, double maxDistance, double yBiasMin, double yBiasRange,
                boolean biasToSoulLights) {
            this.emitterId = emitterId;
            this.maxLive = maxLive;
            this.minIntervalTicks = minIntervalTicks;
            this.maxIntervalTicks = maxIntervalTicks;
            this.minDistance = minDistance;
            this.maxDistance = maxDistance;
            this.yBiasMin = yBiasMin;
            this.yBiasRange = yBiasRange;
            this.biasToSoulLights = biasToSoulLights;
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

            Vec3 pos = biasToSoulLights
                    ? pickSoulLightPos(minecraft, level, random)
                    : pickSpawnPos(minecraft, level, random);
            ParticleEmitter emitter = QuasarSpawner.spawnManaged(
                    emitterId, pos, FxBudget.Channel.AMBIENT);
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

        /**
         * F-104 (IDEA-18 §6): a spot 0.5 blocks off one of the cached soul-light
         * positions near the camera (ship fight lanterns, stern great-lantern cluster,
         * buoy lane) — the moths gather where the lights are. Falls back to the camera
         * ring when no light is cached (open water far from the lane).
         */
        private Vec3 pickSoulLightPos(Minecraft minecraft, ClientLevel level, RandomSource random) {
            List<BlockPos> lights = soulLightPositions(minecraft, level);
            if (lights.isEmpty()) {
                return pickSpawnPos(minecraft, level, random);
            }
            BlockPos pick = lights.get(random.nextInt(lights.size()));
            return new Vec3(
                    pick.getX() + 0.5D + (random.nextDouble() - 0.5D),
                    pick.getY() + 0.5D + random.nextDouble() * 0.5D,
                    pick.getZ() + 0.5D + (random.nextDouble() - 0.5D));
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

    /**
     * Small wisp clouds just above the water (v1 window; density now lives in the JSON).
     * F-107 (part 4): hard-capped to a far-dust read in the JSON — alpha peak
     * 0.28 → 0.05 (size 0.055 ± 0.03 and wind 0.0006 + {@code veil:drag} 0.96 already
     * met the caps). Tiny distant dust points only; this is the last remaining
     * mote layer after the near-bokeh window's removal.
     */
    private static final Window MOTES = new Window(
            S2CQuasarPayload.LIMBO_MOTES, 4, 40, 60, 12.0D, 20.0D, 1.0D, 3.0D, false);
    /**
     * Dim violet fog sheets hugging the water surface (alpha-blended, so keep them few).
     * F-088 polish first pushed the spawn window out 8 → 14 blocks; F-107 (part 2)
     * hardened that into a real clearance guarantee. Veil's billboard half-edge equals
     * the particle size, the sphere shape offsets a spawn up to dimensions/2 blocks
     * toward the camera, and the wind module is an UNDAMPED per-tick acceleration
     * (Veil 4.3.0 never applies the JSON wind strength to the force module), so the
     * old ring still let a 15-block half-edge sheet drift ~44 blocks over its life and
     * shove through the camera as a near-opaque dark wall during pans. The ring is now
     * 14–22 → 20–30 blocks and the emitter was retuned (size 8 ± 2, shape 9 → 7, wind
     * 0.012 → 0.0003, dedicated soft 128×128 sprite instead of the 8×8 wisp): worst
     * case the closest sheet edge stays ≥ ~5.4 blocks off the camera for the whole
     * particle life — 20 − 3.5 (shape) − 10 (half-edge) − ~1.1 (lifetime drift).
     */
    private static final Window FOG = new Window(
            LIMBO_FOG, 2, 110, 160, 20.0D, 30.0D, 0.4D, 1.2D, false);
    /**
     * IDEA-18 §3: big slow middle-distance fog banks rolling +X past the ship (the
     * buoy-lane heading) — the emitter's wind sells that the sea moves. F-107 (part 2):
     * the roll is now SPEED-BOUNDED. The old wind (0.05, undamped — see the FOG note)
     * accelerated every bank quadratically (~566 blocks of drift over a max life), so
     * an upwind bank swept through the camera as a huge, almost covering dark sheet.
     * The emitter now pairs a gentle wind (0.002) with a veil:drag velocity retention
     * of 0.96/tick: banks ease into a steady ~1 block/s roll — the "rolling past the
     * ship" read stays — and drift ≤ ~6.1 blocks per life. With the ring pushed
     * 35–70 → 50–80 blocks and the retune (size 24 ± 4, shape 26 → 16, dedicated 2:1
     * oval sprite) the closest bank edge stays ≥ ~7.9 blocks off the camera —
     * 50 − 8 (shape) − 28 (half-edge) − ~6.1 (lifetime drift).
     */
    private static final Window FOGBANKS = new Window(
            LIMBO_FOGBANK, 2, 140, 200, 50.0D, 80.0D, 0.5D, 2.0D, false);
    /**
     * F-104 (IDEA-18 §6): pale spirit-moths orbiting the soul lights — spawns are biased
     * onto cached soul-lantern/lit-soul-campfire positions ({@code biasToSoulLights});
     * the ring parameters only serve the open-water fallback. Standard ambient tier:
     * {@code reducedFx} doubles the cadence like the other windows.
     */
    private static final Window MOTHS = new Window(
            LIMBO_MOTHS, 3, 60, 90, 4.0D, 18.0D, 1.5D, 2.5D, true);
    private static final Window[] WINDOWS = {MOTES, FOG, FOGBANKS, MOTHS};

    // ------------------------------------------------------------------ soul-light cache (F-104)

    /** Soul-light scan: cube half-extent around the camera (IDEA-18 §6's 16-block cube). */
    private static final int SOUL_LIGHT_SCAN_RADIUS = 16;
    /** Cache refresh: rescan at most every this many ticks (scans run at window cadence). */
    private static final int SOUL_LIGHT_RESCAN_TICKS = 100;
    /** Rescan early once the camera strays this far from the scanned center (blocks). */
    private static final double SOUL_LIGHT_RESCAN_DIST = 8.0D;
    /** Plenty for the ship cluster + the nearest buoys; keeps the scan early-outable. */
    private static final int SOUL_LIGHT_CACHE_CAP = 12;

    /** Cached soul-light positions near the camera (immutable {@link BlockPos} copies). */
    private static final List<BlockPos> SOUL_LIGHT_CACHE = new ArrayList<>();
    private static long soulLightScanGameTime = Long.MIN_VALUE;
    private static Vec3 soulLightScanCenter = Vec3.ZERO;

    /**
     * The soul lights near the camera — soul lanterns plus LIT soul campfires (the ship's
     * four fight lanterns, the stern great-lantern cluster, the buoy lane). NEVER scanned
     * per tick: this runs only when a moth spawn fires (window cadence, every ~3–4 s) and
     * even then reuses the cache for {@value #SOUL_LIGHT_RESCAN_TICKS} ticks unless the
     * camera moved more than {@value #SOUL_LIGHT_RESCAN_DIST} blocks. The cache clears
     * with the windows on dimension change, so no stale positions survive a leave.
     */
    private static List<BlockPos> soulLightPositions(Minecraft minecraft, ClientLevel level) {
        long gameTime = level.getGameTime();
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        if (soulLightScanGameTime != Long.MIN_VALUE
                && gameTime - soulLightScanGameTime < SOUL_LIGHT_RESCAN_TICKS
                && gameTime >= soulLightScanGameTime
                && camera.distanceToSqr(soulLightScanCenter)
                        < SOUL_LIGHT_RESCAN_DIST * SOUL_LIGHT_RESCAN_DIST) {
            return SOUL_LIGHT_CACHE;
        }
        soulLightScanGameTime = gameTime;
        soulLightScanCenter = camera;
        SOUL_LIGHT_CACHE.clear();
        BlockPos center = BlockPos.containing(camera.x, camera.y, camera.z);
        for (BlockPos pos : BlockPos.betweenClosed(
                center.offset(-SOUL_LIGHT_SCAN_RADIUS, -SOUL_LIGHT_SCAN_RADIUS, -SOUL_LIGHT_SCAN_RADIUS),
                center.offset(SOUL_LIGHT_SCAN_RADIUS, SOUL_LIGHT_SCAN_RADIUS, SOUL_LIGHT_SCAN_RADIUS))) {
            BlockState state = level.getBlockState(pos);
            if (state.is(Blocks.SOUL_LANTERN)
                    || (state.is(Blocks.SOUL_CAMPFIRE) && state.getValue(CampfireBlock.LIT))) {
                SOUL_LIGHT_CACHE.add(pos.immutable());
                if (SOUL_LIGHT_CACHE.size() >= SOUL_LIGHT_CACHE_CAP) {
                    break;
                }
            }
        }
        return SOUL_LIGHT_CACHE;
    }

    // ------------------------------------------------------------------ spire embers (F-104)

    /**
     * F-104 (IDEA-18 §8) — soul-ember columns above the three frozen seascape spires.
     * A fixed-position variant of the window pattern: at most ONE live looping
     * {@code eclipse:limbo_embers} emitter per spire, spawned only while the camera is
     * within {@value #ACTIVATION_DISTANCE} blocks of that spire's constant coords and
     * removed the moment it strays farther (or the dimension is left — {@link #clear}
     * rides the {@code clearWindows()} seam). The crest Y derives from the client
     * waterline seam ({@code LimboSpecialEffects.clientWaterlineY}) + the frozen spire
     * heights, so no server traffic is needed. Garnish tier: skipped AND cleared under
     * {@code reducedFx} (the near-motes ladder — landmark accents drop first).
     */
    private static final class SpireEmbers {
        /**
         * The three {@code LimboSeascape.build} spire calls, frozen: {x, z, height}
         * (soul fire burns at {@code waterline + height + 1}).
         */
        private static final int[][] SPIRES = {{205, 40, 13}, {-95, -215, 16}, {-230, -35, 10}};
        private static final double ACTIVATION_DISTANCE = 160.0D;
        /** Distance re-check cadence (ticks) — no per-tick math for three constants. */
        private static final int CHECK_INTERVAL_TICKS = 20;

        private final ParticleEmitter[] live = new ParticleEmitter[SPIRES.length];
        private int countdown;

        void tick(Minecraft minecraft, ClientLevel level) {
            if (EclipseClientConfig.reducedFx()) {
                clear();
                return;
            }
            if (--countdown > 0) {
                return;
            }
            countdown = CHECK_INTERVAL_TICKS;
            Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
            double waterline = LimboSpecialEffects.clientWaterlineY(level);
            for (int i = 0; i < SPIRES.length; i++) {
                ParticleEmitter emitter = live[i];
                if (emitter != null) {
                    try {
                        if (emitter.isRemoved()) {
                            live[i] = null;
                            emitter = null;
                        }
                    } catch (Throwable t) {
                        live[i] = null;
                        emitter = null;
                    }
                }
                double dx = SPIRES[i][0] + 0.5D - camera.x;
                double dz = SPIRES[i][1] + 0.5D - camera.z;
                boolean near = dx * dx + dz * dz
                        < ACTIVATION_DISTANCE * ACTIVATION_DISTANCE;
                if (!near) {
                    if (emitter != null) {
                        removeEmitter(emitter);
                        live[i] = null;
                    }
                    continue;
                }
                if (emitter == null) {
                    // Emitter center just above the crest soul fire (top+1) — the column
                    // rises from the flame, marking the landmark from the ship.
                    Vec3 pos = new Vec3(SPIRES[i][0] + 0.5D,
                            waterline + SPIRES[i][2] + 1.5D, SPIRES[i][1] + 0.5D);
                    live[i] = QuasarSpawner.spawnManaged(
                            LIMBO_EMBERS, pos, FxBudget.Channel.AMBIENT);
                }
            }
        }

        /** Removes every live emitter — the leave-limbo/disconnect/reducedFx reset. */
        void clear() {
            for (int i = 0; i < live.length; i++) {
                if (live[i] != null) {
                    removeEmitter(live[i]);
                    live[i] = null;
                }
            }
            countdown = 0;
        }
    }

    private static final SpireEmbers SPIRE_EMBERS = new SpireEmbers();

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
        // F-104: fixed-position spire ember columns (IDEA-18 §8).
        SPIRE_EMBERS.tick(minecraft, level);
        // F-104: row dirge + rigging creaks + drowned bells (IDEA-18 §4/§10/§7).
        LimboRowChant.tick(minecraft, level);
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
        // F-104: the spire emitters, the soul-light cache and the chant/bell state share
        // the window-clear seam — leaving limbo (or disconnecting) drops everything.
        SPIRE_EMBERS.clear();
        SOUL_LIGHT_CACHE.clear();
        soulLightScanGameTime = Long.MIN_VALUE;
        LimboRowChant.reset();
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
