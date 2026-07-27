package dev.projecteclipse.eclipse.woah.mansiondome;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * WOAH-01 §3.7 — the shield-shatter choreography: at the {@code T_SHATTER} beat the
 * opaque hull "breaks" into ~{@value #SHARD_CAP} {@link Display.BlockDisplay} glass
 * plates seeded on a Fibonacci grid over the upper hemisphere (plus an equator ring),
 * each flying outward-and-up on a cubic ease-out, tumbling, and scaling to zero over an
 * individual 80–120 t life.
 *
 * <p>All {@code StormDebrisFx}/{@code CreditsShatterAct} doctrine applies verbatim:
 * every shard is mounted at ONE fixed entity position (the shell centre — the always
 * relevant chunk; no shard is lost to a chunk unload) with all motion in the
 * transformation translation, pushed every {@value #UPDATE_INTERVAL_TICKS} ticks with a
 * matching interpolation duration and a one-window keyframe lead; every shard carries
 * {@code brightness 15/15} + a {@value #VIEW_RANGE}× view-range override (~256 blocks —
 * without it the show is invisible past 64); every shard carries the command tag
 * {@value #ENTITY_TAG} and is tracked in a live-UUID set, so crash strays are swept on
 * join, the {@value #WATCHDOG_TICKS} t watchdog force-clears a wedged run, and
 * {@code /kill @e[tag=eclipse_dome_shatter]} always works.</p>
 *
 * <p>Budget (§9): spawn is sliced to {@value #SPAWN_PER_TICK}/tick (4 ticks); flight
 * pushes average {@code SHARD_CAP / UPDATE_INTERVAL_TICKS} = ~24 entity updates/tick —
 * far under the FIN-6 ceiling (CreditsShatterAct runs 185/t).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DomeShatterFx {
    /** Frozen command tag on every shard — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_dome_shatter";

    /** Hard cap on shards (~240 per the plan; 200 hemisphere + 40 equator ring). */
    private static final int SHARD_CAP = 240;
    private static final int HEMISPHERE_SHARDS = 200;
    private static final int EQUATOR_SHARDS = 40;
    /** Spawn budget per tick (240 over 4 ticks). */
    private static final int SPAWN_PER_TICK = 60;
    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 10;
    /** Individual shard flight life band (scale hits 0 at the end). */
    private static final int LIFE_MIN_TICKS = 80;
    private static final int LIFE_MAX_TICKS = 120;
    /** Force-clear after this long (wedged run / lost hand-off). */
    private static final int WATCHDOG_TICKS = 400;
    /** Nobody within this range of the centre at begin → the show is skipped entirely. */
    private static final double PLAYER_GATE_RANGE = 600.0D;
    /** view_range override (× 64 blocks ≈ 256) — shards mount at the shell centre. */
    private static final float VIEW_RANGE = 4.0F;

    /** Plate proportions (blocks): a thin pane shard of the hull. */
    private static final float PLATE_SIZE = 2.6F;
    private static final float PLATE_THICKNESS = 0.25F;
    private static final float PLATE_SIZE_VARIANCE = 0.35F;
    /** Outward flight distance band as a fraction of the shell radius. */
    private static final double FLIGHT_MIN_FACTOR = 0.35D;
    private static final double FLIGHT_MAX_FACTOR = 0.85D;
    /** Up-bias band (plan §5: 0.4–1.0 of the flight distance goes skyward). */
    private static final double UP_BIAS_MIN = 0.4D;
    private static final double UP_BIAS_MAX = 1.0D;
    /** End-of-life gravity sag (blocks, quadratic in q — the arc's falling tail). */
    private static final double SAG_MIN = 5.0D;
    private static final double SAG_MAX = 14.0D;
    /** Tumble: total revolutions over a shard's life (decays with the ease-out). */
    private static final float TUMBLE_MIN_TURNS = 0.75F;
    private static final float TUMBLE_MAX_TURNS = 2.5F;

    /** Hull palette (plan §3.7): 60% green glass, 30% tinted glass, 10% emerald glints. */
    private static final BlockState GLASS_GREEN = Blocks.GREEN_STAINED_GLASS.defaultBlockState();
    private static final BlockState GLASS_TINTED = Blocks.TINTED_GLASS.defaultBlockState();
    private static final BlockState GLINT = Blocks.EMERALD_BLOCK.defaultBlockState();

    /** The single live show (one dome at a time), or {@code null}. Server thread only. */
    @Nullable
    private static Show show;
    /** UUIDs of shards spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private DomeShatterFx() {}

    // ------------------------------------------------------------------ public beats

    /**
     * Fires the shatter show. Idempotent while one runs (a restart-replayed t30 beat
     * cannot double it); silently skipped when no player is within
     * {@value #PLAYER_GATE_RANGE} blocks (nobody would see a single frame).
     */
    public static void begin(ServerLevel level, Vec3 centre, float radius) {
        if (show != null) {
            return;
        }
        if (!playerNear(level, centre)) {
            EclipseMod.LOGGER.info("DomeShatterFx: no viewer within {} blocks — show skipped",
                    (int) PLAYER_GATE_RANGE);
            return;
        }
        show = new Show(level, centre, radius);
        EclipseMod.LOGGER.info("DomeShatterFx: {} shard(s) armed at {} (r {})",
                SHARD_CAP, centre, radius);
    }

    /** Discards the show immediately (dev reset, abort paths). */
    public static void clearAll() {
        Show current = show;
        if (current != null) {
            current.discardAll();
            show = null;
        }
    }

    /** Whether the shard show is currently live (dev status). */
    public static boolean isActive() {
        return show != null;
    }

    private static boolean playerNear(ServerLevel level, Vec3 centre) {
        double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator()
                    && player.distanceToSqr(centre.x, centre.y, centre.z) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: shards that made it to disk are swept by the join check on the
        // next boot (they can never be adopted — LIVE_DISPLAYS is cleared here).
        show = null;
        LIVE_DISPLAYS.clear();
    }

    /** StructureFlightFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
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
        Show current = show;
        if (current == null) {
            return;
        }
        if (current.level.getServer() != event.getServer()) {
            return;
        }
        current.tick();
        if (current.done) {
            show = null;
        }
    }

    // ------------------------------------------------------------------ the show

    /** One flying hull plate. All motion is a pure function of the show age. */
    private static final class Shard {
        @Nullable
        Display.BlockDisplay display;
        final BlockState state;
        /** Unit outward normal — seed position on the sphere AND flight direction. */
        final Vector3f normal;
        /** Tangent orientation of the plate on the sphere (thin axis along the normal). */
        final Quaternionf facing;
        final float size;
        final int lifeTicks;
        final double flightDist;
        final double upBias;
        final double sag;
        final Vector3f tumbleAxis;
        final float tumbleTotal;
        /** Push slice: only pushed on show ticks where {@code age % interval == phase}. */
        final int pushPhase;
        /** Show age the shard was spawned at (spawn is sliced over 4 ticks). */
        int bornAge = -1;

        Shard(BlockState state, Vector3f normal, Quaternionf facing, float size, int lifeTicks,
                double flightDist, double upBias, double sag, Vector3f tumbleAxis,
                float tumbleTotal, int pushPhase) {
            this.state = state;
            this.normal = normal;
            this.facing = facing;
            this.size = size;
            this.lifeTicks = lifeTicks;
            this.flightDist = flightDist;
            this.upBias = upBias;
            this.sag = sag;
            this.tumbleAxis = tumbleAxis;
            this.tumbleTotal = tumbleTotal;
            this.pushPhase = pushPhase;
        }
    }

    private static final class Show {
        final ServerLevel level;
        final Vec3 centre;
        final float radius;
        final List<Shard> pending = new ArrayList<>(SHARD_CAP);
        final List<Shard> flying = new ArrayList<>(SHARD_CAP);

        int age;
        boolean done;

        Show(ServerLevel level, Vec3 centre, float radius) {
            this.level = level;
            this.centre = centre;
            this.radius = radius;
            RandomSource random = RandomSource.create(
                    level.getGameTime() * 37L + Double.hashCode(centre.x));
            buildShards(random);
        }

        /** Fibonacci grid over the upper hemisphere + an equator ring (plan §3.7). */
        private void buildShards(RandomSource random) {
            double goldenAngle = Math.PI * (3.0D - Math.sqrt(5.0D));
            for (int i = 0; i < HEMISPHERE_SHARDS; i++) {
                // cos(theta) even in (0.04, 0.98): pole to just above the horizon.
                double cosTheta = 0.04D + 0.94D * (i + 0.5D) / HEMISPHERE_SHARDS;
                double sinTheta = Math.sqrt(Math.max(0.0D, 1.0D - cosTheta * cosTheta));
                double phi = i * goldenAngle;
                this.pending.add(buildShard(random, new Vector3f(
                        (float) (Math.cos(phi) * sinTheta), (float) cosTheta,
                        (float) (Math.sin(phi) * sinTheta))));
            }
            for (int i = 0; i < EQUATOR_SHARDS; i++) {
                double phi = (Math.PI * 2.0D / EQUATOR_SHARDS) * i + random.nextDouble() * 0.1D;
                float y = 0.02F + random.nextFloat() * 0.1F;
                Vector3f normal = new Vector3f((float) Math.cos(phi), y, (float) Math.sin(phi));
                normal.normalize();
                this.pending.add(buildShard(random, normal));
            }
        }

        private Shard buildShard(RandomSource random, Vector3f normal) {
            float roll = random.nextFloat();
            BlockState state = roll < 0.6F ? GLASS_GREEN : roll < 0.9F ? GLASS_TINTED : GLINT;
            // Plate tangent to the sphere: local +Z (the thin axis) rotated onto the
            // normal, plus a random spin AROUND the normal so the grid does not read.
            Quaternionf facing = new Quaternionf()
                    .rotationTo(0.0F, 0.0F, 1.0F, normal.x(), normal.y(), normal.z())
                    .premul(new Quaternionf().rotationAxis(
                            random.nextFloat() * Mth.TWO_PI, normal));
            Vector3f tumbleAxis = new Vector3f(random.nextFloat() - 0.5F,
                    random.nextFloat() - 0.5F, random.nextFloat() - 0.5F);
            if (tumbleAxis.lengthSquared() < 1.0E-4F) {
                tumbleAxis.set(0.0F, 1.0F, 0.0F);
            }
            tumbleAxis.normalize();
            return new Shard(state, normal, facing,
                    PLATE_SIZE * (1.0F - PLATE_SIZE_VARIANCE
                            + random.nextFloat() * PLATE_SIZE_VARIANCE * 2.0F),
                    LIFE_MIN_TICKS + random.nextInt(LIFE_MAX_TICKS - LIFE_MIN_TICKS + 1),
                    this.radius * (FLIGHT_MIN_FACTOR
                            + random.nextDouble() * (FLIGHT_MAX_FACTOR - FLIGHT_MIN_FACTOR)),
                    UP_BIAS_MIN + random.nextDouble() * (UP_BIAS_MAX - UP_BIAS_MIN),
                    SAG_MIN + random.nextDouble() * (SAG_MAX - SAG_MIN),
                    tumbleAxis,
                    Mth.TWO_PI * (TUMBLE_MIN_TURNS
                            + random.nextFloat() * (TUMBLE_MAX_TURNS - TUMBLE_MIN_TURNS))
                            * (random.nextBoolean() ? 1.0F : -1.0F),
                    (this.pending.size() + this.flying.size()) % UPDATE_INTERVAL_TICKS);
        }

        void tick() {
            this.age++;
            if (this.age > WATCHDOG_TICKS) {
                EclipseMod.LOGGER.warn("DomeShatterFx: show outlived its watchdog ({} ticks) "
                        + "— force-clearing", WATCHDOG_TICKS);
                discardAll();
                this.done = true;
                return;
            }
            spawnBatch();
            animate();
            if (this.pending.isEmpty() && this.flying.isEmpty()) {
                this.done = true;
            }
        }

        private void spawnBatch() {
            if (this.pending.isEmpty()) {
                return;
            }
            BlockPos mountPos = BlockPos.containing(this.centre);
            if (!this.level.isLoaded(mountPos)) {
                return; // Centre chunk momentarily unloaded: retry next tick.
            }
            int budget = Math.min(SPAWN_PER_TICK, this.pending.size());
            for (int i = 0; i < budget; i++) {
                Shard shard = this.pending.remove(this.pending.size() - 1);
                Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(this.level);
                if (display == null) {
                    continue;
                }
                shard.bornAge = this.age;
                display.setBlockState(shard.state);
                display.moveTo(this.centre.x, this.centre.y, this.centre.z, 0.0F, 0.0F);
                display.addTag(ENTITY_TAG);
                // Full-bright + 4× view range in ONE NBT round-trip, before the first pose.
                DisplayBrightnessFx.set(display, 15, 15, VIEW_RANGE);
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(0);
                display.setTransformation(poseAt(shard, this.age));
                LIVE_DISPLAYS.add(display.getUUID());
                this.level.addFreshEntity(display);
                shard.display = display;
                this.flying.add(shard);
            }
        }

        /** One interpolated push per shard in this tick's slice (keyframe lead law). */
        private void animate() {
            int slice = this.age % UPDATE_INTERVAL_TICKS;
            boolean expired = false;
            for (Shard shard : this.flying) {
                Display.BlockDisplay display = shard.display;
                if (display == null || display.isRemoved()) {
                    expired = true;
                    continue;
                }
                int life = this.age - shard.bornAge;
                if (life >= shard.lifeTicks) {
                    LIVE_DISPLAYS.remove(display.getUUID());
                    display.discard();
                    shard.display = null;
                    expired = true;
                    continue;
                }
                if (shard.pushPhase != slice) {
                    continue;
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                display.setTransformation(poseAt(shard, this.age + UPDATE_INTERVAL_TICKS));
            }
            if (expired) {
                this.flying.removeIf(shard -> shard.display == null || shard.display.isRemoved());
            }
        }

        /**
         * Absolute pose of one shard at show age {@code t}: sphere seat + outward flight
         * on a cubic ease-out (the CreditsShatterAct {@code 1−(1−q)^3} law), up-bias,
         * quadratic gravity sag, decaying tumble and scale → 0 — one translation relative
         * to the shared centre mount. Pure function of {@code t}: pushes are stateless.
         */
        private Transformation poseAt(Shard shard, int t) {
            float q = Mth.clamp((t - shard.bornAge) / (float) shard.lifeTicks, 0.0F, 1.0F);
            float ease = 1.0F - (1.0F - q) * (1.0F - q) * (1.0F - q);
            double dist = this.radius + shard.flightDist * ease;
            double px = shard.normal.x() * dist;
            double py = shard.normal.y() * dist
                    + shard.upBias * shard.flightDist * ease
                    - shard.sag * q * q;
            double pz = shard.normal.z() * dist;
            float scale = shard.size * (1.0F - ease * 0.35F) * (1.0F - q * q); // shrink late

            Quaternionf rotation = new Quaternionf()
                    .rotationAxis(shard.tumbleTotal * ease, shard.tumbleAxis)
                    .mul(shard.facing);
            Vector3f translation = new Vector3f((float) px, (float) py, (float) pz);
            // Re-centre the [0,scale]-cornered plate mesh on the flight point.
            Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F,
                    scale * (PLATE_THICKNESS / PLATE_SIZE) * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale * (PLATE_THICKNESS / PLATE_SIZE)),
                    new Quaternionf());
        }

        void discardAll() {
            for (Shard shard : this.flying) {
                Display.BlockDisplay display = shard.display;
                if (display != null) {
                    LIVE_DISPLAYS.remove(display.getUUID());
                    if (!display.isRemoved()) {
                        display.discard();
                    }
                    shard.display = null;
                }
            }
            this.flying.clear();
            this.pending.clear();
        }
    }
}
