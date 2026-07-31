package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * F-047 (a): the VISIBLE fall of one shattered End islet — a cluster of
 * {@link Display.BlockDisplay} fragments that leaves the sky where the islet stood and
 * crashes into the ground at its impact site.
 *
 * <p>Deliberately a separate, purely cosmetic service beside {@link EndShatterSequence}:
 * the orchestrator owns the restart-safe phases (raze cursor, ground heaps), this owns
 * only the show. A restart therefore drops every cluster mid-air — the same law the
 * shatter cinematic already follows — while the ground rubble it was flying towards is
 * still guaranteed by the orchestrator's persisted impact mask.</p>
 *
 * <p><b>Transport</b> (the {@code StormDebrisFx}/{@code SanctumOrbitals} law): all
 * fragments of one cluster mount at ONE fixed entity anchor at the middle of the fall,
 * and the whole descent lives in the transformation's translation as a closed-form
 * function of the cluster age, pushed as one interpolated keyframe every
 * {@value #UPDATE_INTERVAL_TICKS} ticks. Nothing is ever teleported, the entities never
 * change chunk, and the {@value #VIEW_RANGE}× view-range override keeps a 250-block fall
 * visible from the ground.</p>
 *
 * <p><b>Despawn guarantee</b> (the {@code StormDebrisFx} doctrine): every fragment carries
 * the command tag {@value #ENTITY_TAG} and is tracked in a live-UUID set; a tagged display
 * that joins a level without being tracked was persisted by a crash mid-fall and is
 * discarded on load. A boot sweep clears the ones in already-loaded chunks, each cluster
 * force-clears itself after {@value #WATCHDOG_TICKS} ticks whatever happens, and
 * {@code /kill @e[tag=eclipse_end_crash_debris]} always works.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndIslandCrashFx {
    /** Frozen command tag on every falling fragment. */
    public static final String ENTITY_TAG = "eclipse_end_crash_debris";

    // ------------------------------------------------------------------ tuning constants

    /** Fragments per crashing islet (W13-B3: 34 → 42, guarded by the MSPT lever below). */
    private static final int CLUSTER_PIECES = 42;
    /** Absolute live ceiling across all concurrent clusters. */
    private static final int HARD_CAP = 190;
    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 4;
    /** Force-clear a cluster this long after launch even if its landing never arrives. */
    private static final int WATCHDOG_TICKS = 1200;
    /** Fragment size spread (these are ISLAND chunks, not gravel — they read large). */
    private static final float MIN_SCALE = 1.6F;
    private static final float MAX_SCALE = 5.2F;
    /** Horizontal scatter of the fragments around the cluster axis, in blocks. */
    private static final double SPREAD_RADIUS = 22.0D;
    /** Vertical stagger of the fragments at launch (the islet tears apart as it goes). */
    private static final double LAUNCH_STAGGER = 14.0D;
    /** Tumble rate band (degrees per tick). */
    private static final double SPIN_MIN_DEG = 0.8D;
    private static final double SPIN_MAX_DEG = 3.4D;
    /**
     * W13-B3 mass law (the {@code StormDebrisFx} sediment pattern): the fragment SIZE
     * is rolled first and the impact STAGGER is derived from it — light shards land
     * FIRST (lag up to {@value #LAG_LIGHT} of the fall), heavy plates land LAST and on
     * the beat (lag down to {@value #LAG_HEAVY}), ±{@value #LAG_JITTER} jitter — so an
     * islet impact reads as a light→heavy drum roll into the main slam instead of one
     * undifferentiated clump. Tumble is derived too: light whips at
     * {@value #SPIN_MAX_DEG}°/t, heavy grinds at {@value #SPIN_MIN_DEG}°/t.
     */
    private static final double LAG_LIGHT = 0.30D;
    private static final double LAG_HEAVY = 0.04D;
    private static final double LAG_JITTER = 0.04D;
    /**
     * Every {@value #KEYSTONE_EVERY}th fragment is a KEYSTONE plate: scale
     * {@value #KEYSTONE_SCALE} (≈ ×2.4 the 2.8 band mean), zero head-start, lag ≤ 0.04
     * — it hits exactly on the main beat and stamps a GROUND SHOCKRING cue at its
     * impact column ({@code FX_SHOCKWAVE} + the existing {@code CUE_STRUCTURE_SLAM}
     * dust mushroom, {@code a} = its scale → small client mushroom). Rings rate-limit
     * at {@value #KEYSTONE_FX_COOLDOWN_TICKS} t so stacked keystones cannot strobe.
     */
    private static final int KEYSTONE_EVERY = 9;
    private static final float KEYSTONE_SCALE = 6.8F;
    private static final int KEYSTONE_FX_COOLDOWN_TICKS = 5;
    /** Shockring cue parameters (existing frozen FX ids only — no new registrar rows). */
    private static final float KEYSTONE_SHOCKWAVE_STRENGTH = 0.5F;
    private static final float KEYSTONE_SHOCKWAVE_TICKS = 24.0F;
    /**
     * PERF — the StormSiege/StormDebrisFx MSPT lever, shared across clusters: over
     * {@value #MSPT_DEGRADE_NANOS} ns average tick time the push window doubles
     * (4 t → 8 t), recovering below {@value #MSPT_RECOVER_NANOS} ns (hysteresis).
     */
    private static final long MSPT_DEGRADE_NANOS = 45_000_000L;
    private static final long MSPT_RECOVER_NANOS = 38_000_000L;
    private static final int MSPT_CHECK_INTERVAL_TICKS = 20;
    /** Fragments dim as they leave the lit sky band. */
    private static final int DEBRIS_BLOCK_LIGHT = 3;
    private static final int MAX_SKY_LIGHT = 15;
    /** Display view-range override in vanilla units (× 64 blocks) — a 250-block fall. */
    private static final float VIEW_RANGE = 8.0F;
    /** Whole cluster sleeps (zero packets) while nobody is this close to its axis. */
    private static final double PLAYER_GATE_RANGE = 384.0D;

    /** End-island palette. */
    private static final BlockState[] PALETTE = {
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE_BRICKS.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.PURPUR_BLOCK.defaultBlockState()};

    /** Live clusters (server thread only). */
    private static final List<Cluster> CLUSTERS = new ArrayList<>();
    /** UUIDs of fragments spawned THIS session; tagged joiners outside it are strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());
    /** True while the shared MSPT guard has the clusters on the halved push cadence. */
    private static boolean msptDegraded;

    private EndIslandCrashFx() {}

    // ------------------------------------------------------------------ public beat

    /**
     * Launches one crashing cluster from {@code from} (the islet's sky position) towards
     * {@code impact} (its ground site), arriving after {@code fallTicks}. Purely visual and
     * always safe to skip: the caller's ground rubble does not depend on it.
     */
    public static void crash(ServerLevel level, Vec3 from, Vec3 impact, int fallTicks, long seed) {
        int budget = Math.min(CLUSTER_PIECES, HARD_CAP - livePieces());
        if (budget <= 0) {
            EclipseMod.LOGGER.info("EndIslandCrashFx: hard cap {} reached — cluster skipped", HARD_CAP);
            return;
        }
        Cluster cluster = new Cluster(level, from, impact, Math.max(20, fallTicks), seed);
        cluster.spawn(budget);
        if (cluster.pieces.isEmpty()) {
            return;
        }
        CLUSTERS.add(cluster);
        EclipseMod.LOGGER.info("EndIslandCrashFx: {} fragment(s) falling from y{} to y{} over {}t",
                cluster.pieces.size(), (int) from.y, (int) impact.y, fallTicks);
    }

    /** Discards every live cluster (abort paths, dev revert, restart recovery). */
    public static void clearAll() {
        for (Cluster cluster : CLUSTERS) {
            cluster.discardAll();
        }
        CLUSTERS.clear();
    }

    public static boolean isActive() {
        return !CLUSTERS.isEmpty();
    }

    private static int livePieces() {
        int live = 0;
        for (Cluster cluster : CLUSTERS) {
            live += cluster.pieces.size();
        }
        return live;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        // Boot sweep of fragments a crash mid-fall persisted; strays in still-unloaded
        // chunks are caught by the join guard the moment their chunk loads.
        ServerLevel overworld = event.getServer().overworld();
        AABB bounds = new AABB(
                DiscProfile.END_DISC_CENTER_X - DiscProfile.END_DISC_RADIUS - 64, -64.0D,
                DiscProfile.END_DISC_CENTER_Z - DiscProfile.END_DISC_RADIUS - 64,
                DiscProfile.END_DISC_CENTER_X + DiscProfile.END_DISC_RADIUS + 64,
                overworld.getMaxBuildHeight(),
                DiscProfile.END_DISC_CENTER_Z + DiscProfile.END_DISC_RADIUS + 64);
        overworld.getEntities((Entity) null, bounds,
                entity -> entity.getTags().contains(ENTITY_TAG)).forEach(Entity::discard);
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        CLUSTERS.clear();
        LIVE_DISPLAYS.clear();
        msptDegraded = false;
    }

    /** A tagged display we did not spawn this session is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(ENTITY_TAG)
                && !LIVE_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (CLUSTERS.isEmpty()) {
            return;
        }
        tickMsptGuard(event.getServer());
        Iterator<Cluster> iterator = CLUSTERS.iterator();
        while (iterator.hasNext()) {
            Cluster cluster = iterator.next();
            if (cluster.level.getServer() != event.getServer()) {
                iterator.remove();
                continue;
            }
            cluster.tick();
            if (cluster.done) {
                iterator.remove();
            }
        }
    }

    /** The shared W12 MSPT lever: halved push cadence over 45 ms, recovery below 38 ms. */
    private static void tickMsptGuard(MinecraftServer server) {
        if (server.getTickCount() % MSPT_CHECK_INTERVAL_TICKS != 0) {
            return;
        }
        long avgNanos = server.getAverageTickTimeNanos();
        if (msptDegraded) {
            if (avgNanos < MSPT_RECOVER_NANOS) {
                msptDegraded = false;
                EclipseMod.LOGGER.info("EndIslandCrashFx: MSPT recovered ({} ms) — full push cadence",
                        avgNanos / 1_000_000L);
            }
        } else if (avgNanos > MSPT_DEGRADE_NANOS) {
            msptDegraded = true;
            EclipseMod.LOGGER.info("EndIslandCrashFx: MSPT guard tripped ({} ms > 45 ms) — pushes halved",
                    avgNanos / 1_000_000L);
        }
    }

    // ------------------------------------------------------------------ the cluster

    /** One falling fragment; every pose is a closed-form function of the cluster age. */
    private static final class Piece {
        final Display.BlockDisplay display;
        final double offsetX;
        final double offsetZ;
        /** Vertical head start (blocks) — the islet does not tear off as one flat slab. */
        final double lead;
        /** Fraction of the fall this fragment lags behind the cluster (mass-derived). */
        final double lag;
        final float scale;
        final Vector3f spinAxis;
        final double spinRate;
        final double spinPhase;
        /** Assigned over the DOUBLED window so the degraded cadence stays evenly spread. */
        final int pushPhase;
        /** Keystone plate: lands on the beat and stamps the ground shockring cue. */
        final boolean keystone;
        /** One-shot latch for the keystone's landing FX. */
        boolean landedFx;

        Piece(Display.BlockDisplay display, double offsetX, double offsetZ, double lead,
                double lag, float scale, Vector3f spinAxis, double spinRate, double spinPhase,
                int pushPhase, boolean keystone) {
            this.display = display;
            this.offsetX = offsetX;
            this.offsetZ = offsetZ;
            this.lead = lead;
            this.lag = lag;
            this.scale = scale;
            this.spinAxis = spinAxis;
            this.spinRate = spinRate;
            this.spinPhase = spinPhase;
            this.pushPhase = pushPhase;
            this.keystone = keystone;
        }
    }

    private static final class Cluster {
        final ServerLevel level;
        final Vec3 from;
        final Vec3 impact;
        final int fallTicks;
        final long seed;
        /** The one fixed entity anchor every fragment mounts at (mid-fall on the axis). */
        final Vec3 mount;
        final List<Piece> pieces = new ArrayList<>(CLUSTER_PIECES);
        int age;
        int lastKeystoneFxAge = -KEYSTONE_FX_COOLDOWN_TICKS;
        boolean done;

        Cluster(ServerLevel level, Vec3 from, Vec3 impact, int fallTicks, long seed) {
            this.level = level;
            this.from = from;
            this.impact = impact;
            this.fallTicks = fallTicks;
            this.seed = seed;
            this.mount = new Vec3((from.x + impact.x) * 0.5D,
                    (from.y + impact.y) * 0.5D, (from.z + impact.z) * 0.5D);
        }

        void spawn(int budget) {
            BlockPos mountPos = BlockPos.containing(this.mount);
            BudgetedBlockWriter.loadWithTicket(this.level, mountPos.getX() >> 4, mountPos.getZ() >> 4);
            if (!this.level.isLoaded(mountPos)) {
                return;
            }
            for (int i = 0; i < budget; i++) {
                double h1 = to01(mix(this.seed, i, 1L));
                double h2 = to01(mix(this.seed, i, 2L));
                double h3 = to01(mix(this.seed, i, 3L));
                double h4 = to01(mix(this.seed, i, 4L));
                double angle = h1 * Math.PI * 2.0D;
                double radius = Math.sqrt(h2) * SPREAD_RADIUS;
                Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(this.level);
                if (display == null) {
                    continue;
                }
                display.setBlockState(PALETTE[(int) (h3 * PALETTE.length) % PALETTE.length]);
                display.moveTo(this.mount.x, this.mount.y, this.mount.z, 0.0F, 0.0F);
                display.addTag(ENTITY_TAG);
                DisplayBrightnessFx.set(display, DEBRIS_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
                Vector3f axis = new Vector3f(
                        (float) (h2 * 2.0D - 1.0D), 1.0F, (float) (h4 * 2.0D - 1.0D));
                if (axis.lengthSquared() < 1.0E-4F) {
                    axis.set(0.0F, 1.0F, 0.0F);
                }
                axis.normalize();
                // W13-B3 mass law: size FIRST (every KEYSTONE_EVERYth ordinal promoted
                // to a KEYSTONE plate — deterministic, so replays match), then lag,
                // head-start and tumble DERIVED from it: light shards tear off high,
                // spin fast and land first; heavy plates tear off low, grind slowly
                // and hammer in last — the drum-roll into the main slam.
                boolean keystone = i % KEYSTONE_EVERY == KEYSTONE_EVERY / 2;
                float scale = keystone ? KEYSTONE_SCALE
                        : (float) (MIN_SCALE + (MAX_SCALE - MIN_SCALE) * Math.pow(h2, 1.7D));
                double mass = keystone ? 1.0D
                        : Mth.clamp((scale - MIN_SCALE) / (double) (MAX_SCALE - MIN_SCALE),
                                0.0D, 1.0D);
                double lag = keystone ? h4 * LAG_HEAVY
                        : Mth.clamp(LAG_HEAVY + (LAG_LIGHT - LAG_HEAVY) * (1.0D - mass)
                                + (h4 - 0.5D) * 2.0D * LAG_JITTER, 0.0D, LAG_LIGHT + LAG_JITTER);
                double lead = keystone ? 0.0D : (1.0D - mass) * LAUNCH_STAGGER * (0.5D + h3);
                double spinDeg = SPIN_MAX_DEG - mass * (SPIN_MAX_DEG - SPIN_MIN_DEG);
                Piece piece = new Piece(display,
                        Math.cos(angle) * radius, Math.sin(angle) * radius,
                        Math.min(lead, LAUNCH_STAGGER),
                        lag,
                        scale,
                        axis,
                        Math.toRadians(spinDeg) * (h1 < 0.5D ? -1.0D : 1.0D),
                        h1 * Math.PI * 2.0D,
                        i % (UPDATE_INTERVAL_TICKS * 2),
                        keystone);
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(0);
                display.setTransformation(poseAt(piece, 0));
                LIVE_DISPLAYS.add(display.getUUID());
                if (this.level.addFreshEntity(display)) {
                    this.pieces.add(piece);
                } else {
                    LIVE_DISPLAYS.remove(display.getUUID());
                }
            }
        }

        void tick() {
            this.age++;
            if (this.age > this.fallTicks || this.age > WATCHDOG_TICKS) {
                discardAll();
                this.done = true;
                return;
            }
            if (!playerNear()) {
                return; // presence gate: fragments hold their last pose, zero packets
            }
            // Push-cadence law: the interpolation duration IS the push interval; under
            // the MSPT guard the window doubles (slices were assigned mod 8, so the
            // degraded cadence stays evenly spread — the StormDebrisFx pattern).
            int interval = msptDegraded ? UPDATE_INTERVAL_TICKS * 2 : UPDATE_INTERVAL_TICKS;
            int slice = this.age % interval;
            boolean missing = false;
            for (Piece piece : this.pieces) {
                if (piece.keystone && !piece.landedFx
                        && this.age >= this.fallTicks * (1.0D - piece.lag)) {
                    piece.landedFx = true;
                    keystoneShockring(piece);
                }
                boolean pushNow = msptDegraded
                        ? piece.pushPhase == slice
                        : piece.pushPhase % UPDATE_INTERVAL_TICKS == slice;
                if (!pushNow) {
                    continue;
                }
                if (piece.display.isRemoved()) {
                    missing = true;
                    continue;
                }
                piece.display.setTransformationInterpolationDelay(0);
                piece.display.setTransformationInterpolationDuration(interval);
                piece.display.setTransformation(poseAt(piece, this.age + interval));
            }
            if (missing) {
                this.pieces.removeIf(piece -> piece.display.isRemoved());
            }
        }

        /**
         * W13-B3 keystone impact: one ground shockring + dust mushroom at the plate's
         * own impact column, fired at its landing instant (existing frozen cues only:
         * {@code FX_SHOCKWAVE} radial distortion + {@code CUE_STRUCTURE_SLAM} mushroom
         * with {@code a} = plate scale → small executor scale on the client). The
         * cluster-wide cooldown keeps stacked keystones from strobing the ring.
         */
        private void keystoneShockring(Piece piece) {
            if (this.age - this.lastKeystoneFxAge < KEYSTONE_FX_COOLDOWN_TICKS) {
                return;
            }
            this.lastKeystoneFxAge = this.age;
            Vec3 ground = new Vec3(this.impact.x + piece.offsetX * 0.35D,
                    this.impact.y, this.impact.z + piece.offsetZ * 0.35D);
            FxPayloads.sendFxEvent(this.level, FxPayloads.FX_SHOCKWAVE, ground,
                    KEYSTONE_SHOCKWAVE_STRENGTH, KEYSTONE_SHOCKWAVE_TICKS, PLAYER_GATE_RANGE);
            FxPayloads.sendFxEvent(this.level, FxCues.CUE_STRUCTURE_SLAM, ground,
                    piece.scale, 0.0F, PLAYER_GATE_RANGE);
        }

        private boolean playerNear() {
            double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
            for (ServerPlayer player : this.level.players()) {
                if (!player.isSpectator()
                        && player.distanceToSqr(this.mount.x, this.mount.y, this.mount.z) <= rangeSq) {
                    return true;
                }
            }
            return false;
        }

        /**
         * Absolute pose of one fragment at cluster age {@code t}: an ease-IN descent (the
         * islet lets go slowly and then plummets) from its scattered sky slot onto the
         * impact column, converging horizontally as it falls, plus its own tumble.
         */
        private Transformation poseAt(Piece piece, int t) {
            double span = this.fallTicks * (1.0D - piece.lag);
            float raw = (float) Mth.clamp(t / Math.max(1.0D, span), 0.0D, 1.0D);
            // Gravity read: quadratic ease-in, so the last third is the fast part.
            float eased = raw * raw;
            double startX = this.from.x + piece.offsetX;
            double startZ = this.from.z + piece.offsetZ;
            double startY = this.from.y + piece.lead;
            // Fragments converge onto the impact column but keep a little scatter so the
            // rubble field reads wider than a point.
            double endX = this.impact.x + piece.offsetX * 0.35D;
            double endZ = this.impact.z + piece.offsetZ * 0.35D;
            double px = Mth.lerp(eased, startX, endX);
            double pz = Mth.lerp(eased, startZ, endZ);
            double py = Mth.lerp(eased, startY, this.impact.y);
            Quaternionf rotation = new Quaternionf().rotationAxis(
                    (float) (piece.spinPhase + piece.spinRate * t), piece.spinAxis);
            Vector3f translation = new Vector3f(
                    (float) (px - this.mount.x),
                    (float) (py - this.mount.y),
                    (float) (pz - this.mount.z));
            Vector3f half = new Vector3f(
                    piece.scale * 0.5F, piece.scale * 0.5F, piece.scale * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(piece.scale, piece.scale, piece.scale), new Quaternionf());
        }

        void discardAll() {
            for (Piece piece : this.pieces) {
                LIVE_DISPLAYS.remove(piece.display.getUUID());
                if (!piece.display.isRemoved()) {
                    piece.display.discard();
                }
            }
            this.pieces.clear();
        }
    }

    // ------------------------------------------------------------------ deterministic mixer

    /** SplitMix64-style mixer (the {@code EndShatterSequence} local-mixer idiom). */
    private static long mix(long seed, long a, long b) {
        long h = seed ^ (a * 0x9E3779B97F4A7C15L) ^ (b * 0xC2B2AE3D27D4EB4FL);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return h ^ (h >>> 31);
    }

    private static double to01(long h) {
        return (h >>> 11) * 0x1.0p-53D;
    }
}
