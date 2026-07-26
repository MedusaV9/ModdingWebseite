package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.border.SoftBorder;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * RIFT-FX (user item 4) — the CHUNK-GATED border expansion spectacle. When an animated
 * ring growth starts, this class:
 * <ol>
 *   <li><b>holds the soft border at the OLD ring</b> ({@link SoftBorder#holdGrowthAtCurrent}
 *       — cancelling the classic sweep-coupled lerp), so the border only expands once the
 *       {@link RingGrowthService} sweep has written, lit and resent EVERY chunk of the
 *       new annulus;</li>
 *   <li><b>raises giant boulders</b> — huge slow-tumbling {@code BLOCK_DISPLAY} rocks —
 *       out of the rim near every player watching the frontier, with a shake pulse, a
 *       drone and a caption: the world visibly strains against its own edge;</li>
 *   <li>on {@link WorldStageService.StageListener terrain completion} (the "all chunks
 *       finished loading" signal — {@code RingGrowthService.complete} fires it after its
 *       relight/resend pass) <b>releases the border</b> in one dramatic
 *       {@value #RELEASE_LERP_MS} ms surge and <b>sinks the boulders away</b>.</li>
 * </ol>
 *
 * <p><b>Caps</b> (stated per the plan): ≤ {@value #MAX_BOULDERS} boulders per gate, ≤
 * {@value #MAX_PER_CLUSTER} per viewer cluster, viewers must be within
 * {@value #VIEW_RANGE} blocks of the rim, ≤ {@value #MAX_SPAWNS_PER_TICK} display spawns
 * per tick, pose updates every {@value #UPDATE_INTERVAL_TICKS} ticks with matching client
 * interpolation, and guaranteed cleanup: sink-and-discard on release, instant discard on
 * gate replacement, a sweep-stopped fallback release (the terrain-complete listener can
 * never be missed for long), an absolute {@value #GATE_WATCHDOG_TICKS}-tick watchdog, the
 * {@code StructureFlightFx} join-time stray sweep for crash leftovers, and a full clear
 * on server stop. A restart mid-gate degrades gracefully: the in-memory hold vanishes and
 * {@code WorldStageService.onServerStarted} resumes the classic sweep-coupled lerp.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ExpansionBorderFx {
    /** Tag on every boulder display — strays from a crash are swept on entity load. */
    public static final String ENTITY_TAG = "eclipse_border_boulder";

    /** Hard boulder cap per gate (both rings share the cap if both ever grow at once). */
    private static final int MAX_BOULDERS = 24;
    /** Boulders raised around one viewer's stretch of the rim. */
    private static final int MAX_PER_CLUSTER = 6;
    /** A viewer must be this close to the rim circle for their cluster to spawn. */
    private static final double VIEW_RANGE = 160.0D;
    /** Display spawn budget per server tick (the flight-fx smoothing doctrine). */
    private static final int MAX_SPAWNS_PER_TICK = 4;
    /** Pose update cadence; interpolation duration matches (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /** FX broadcast radius for shakes/sounds (matches ExpansionSequence.slamFx). */
    private static final double FX_RANGE = 192.0D;
    /** Rise animation length (boulders heave out of the ground). */
    private static final int RISE_TICKS = 36;
    /** Sink animation length on release; the display discards at its end. */
    private static final int SINK_TICKS = 34;
    /** Boulders rise from this far below their hover point (and sink back through it). */
    private static final float RISE_FROM_BELOW = 10.0F;
    private static final float SINK_DEPTH = 14.0F;
    /** Hover bob amplitude (blocks) and angular speed of the slow tumble (rad/tick). */
    private static final float BOB_AMPLITUDE = 0.7F;
    private static final float BOB_SPEED = 0.045F;
    private static final float TUMBLE_SPEED = 0.012F;
    /** Boulder scale range — GIANT rocks (a display block is 1 m³ at scale 1). */
    private static final float MIN_SCALE = 3.0F;
    private static final float MAX_SCALE = 6.5F;
    /** Low ambient rumble cadence while the frontier is straining. */
    private static final int RUMBLE_PERIOD_TICKS = 90;
    /** Missed-signal fallback: sweep stopped but no terrain-complete after this many ticks. */
    private static final int SWEEP_STOPPED_GRACE_TICKS = 60;
    /** Absolute gate watchdog — a wedged sweep can never hold the border forever. */
    private static final int GATE_WATCHDOG_TICKS = 24_000; // 20 min; big sweeps take minutes
    /** Release surge: the held border expands to the new ring over this many ms. */
    private static final long RELEASE_LERP_MS = 8_000L;

    private static final String CAPTION_HOLD = "eclipse.caption.expansion.frontier_hold";
    private static final String CAPTION_RELEASE = "eclipse.caption.expansion.frontier_open";

    /** Rocky boulder palette (weighted by array position — index² roll, stone-first). */
    private static final BlockState[] BOULDER_BLOCKS = {
            Blocks.STONE.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.TUFF.defaultBlockState(),
            Blocks.ANDESITE.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState()};

    /** Live gates by profile; mutations on the server thread only. */
    private static final Map<DiscProfile, Gate> GATES = new HashMap<>();
    /** UUIDs of displays spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());
    private static final AtomicBoolean LISTENERS_REGISTERED = new AtomicBoolean();

    private ExpansionBorderFx() {}

    // ------------------------------------------------------------------ wiring

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (!LISTENERS_REGISTERED.compareAndSet(false, true)) {
            return;
        }
        WorldStageService.addGrowthStartListener(ExpansionBorderFx::onStageGrowthStart);
        WorldStageService.addListener(ExpansionBorderFx::onStageTerrainComplete);
        EclipseMod.LOGGER.info("ExpansionBorderFx registered (chunk-gated border expansion)");
    }

    /** Growth start: hold the ring, raise the rocks, shake the frontier. */
    private static void onStageGrowthStart(ServerLevel level, DiscProfile profile, int fromStage,
            int toStage, boolean animate) {
        if (toStage <= fromStage || !animate) {
            return; // erases and instant stamps keep the classic border behavior
        }
        MinecraftServer server = level.getServer();
        if (!SoftBorder.holdGrowthAtCurrent(server, profile)) {
            return; // inactive ring (nether stage 0) — nothing to gate
        }
        Gate previous = GATES.remove(profile);
        if (previous != null) {
            previous.discardBoulders(); // superseded sweep: old props vanish instantly
        }
        Gate gate = new Gate(level, profile, SoftBorder.radius(server, profile));
        GATES.put(profile, gate);
        gate.open();
    }

    /** Terrain complete = every chunk written/lit/resent: release the ring, sink the rocks. */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        Gate gate = GATES.get(profile);
        if (gate != null && !gate.released) {
            gate.release("terrain sweep complete");
        } else {
            // Safety: a hold must never outlive its sweep, gate or not.
            SoftBorder.releaseGrowthHold(level.getServer(), profile, 0L);
        }
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: SoftBorder clears its hold in its own stop hook; boulders that
        // made it to disk are swept by the join-time stray check on next boot.
        GATES.clear();
        LIVE_DISPLAYS.clear();
    }

    /** OarAnimator sweep doctrine: a tagged display we did not spawn is a crash stray. */
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
        if (GATES.isEmpty()) {
            return;
        }
        MinecraftServer server = event.getServer();
        for (DiscProfile profile : GATES.keySet().toArray(new DiscProfile[0])) {
            Gate gate = GATES.get(profile);
            if (gate == null || gate.level.getServer() != server) {
                continue;
            }
            gate.tick();
            if (gate.done) {
                GATES.remove(profile, gate);
            }
        }
    }

    // ------------------------------------------------------------------ the gate

    /** One straining boulder: rise → hover (bob + slow tumble) → sink → discard. */
    private static final class Boulder {
        final Vec3 hoverPos;
        final BlockState state;
        final float scale;
        final Vector3f tumbleAxis;
        final float bobPhase;
        @Nullable
        Display.BlockDisplay display;
        int spawnAge = -1;

        Boulder(Vec3 hoverPos, BlockState state, float scale, Vector3f tumbleAxis, float bobPhase) {
            this.hoverPos = hoverPos;
            this.state = state;
            this.scale = scale;
            this.tumbleAxis = tumbleAxis;
            this.bobPhase = bobPhase;
        }
    }

    private static final class Gate {
        final ServerLevel level;
        final DiscProfile profile;
        final double heldRadius;
        final List<Boulder> boulders = new ArrayList<>(MAX_BOULDERS);
        final Deque<Boulder> spawnQueue = new ArrayDeque<>(MAX_BOULDERS);

        int age = -1;
        boolean released;
        int releaseAge;
        boolean done;

        Gate(ServerLevel level, DiscProfile profile, double heldRadius) {
            this.level = level;
            this.profile = profile;
            this.heldRadius = heldRadius;
            planBoulders();
        }

        /** Gate start: caption (the per-cluster shake/drone fired during planning). */
        void open() {
            PacketDistributor.sendToPlayersInDimension(level, new S2CCaptionPayload(
                    CAPTION_HOLD, 60, S2CCaptionPayload.STYLE_WHISPER));
            EclipseMod.LOGGER.info("ExpansionBorderFx: {} gate open at held radius {} — {} boulder(s) planned",
                    profile.name(), String.format(java.util.Locale.ROOT, "%.1f", heldRadius),
                    spawnQueue.size());
        }

        /**
         * Plans the boulder ring: for every player within {@value #VIEW_RANGE} blocks of
         * the rim circle, up to {@value #MAX_PER_CLUSTER} giant rocks fan out along
         * their stretch of the rim (angle-deduplicated between neighbors), hard-capped
         * at {@value #MAX_BOULDERS}. Hover height rides the terrain just INSIDE the old
         * rim (the outside is void until the sweep writes it).
         */
        private void planBoulders() {
            Vec3 center = SoftBorder.center(level.getServer());
            RandomSource random = RandomSource.create(level.getGameTime() * 31L + profile.name().hashCode());
            List<Double> takenAngles = new ArrayList<>(MAX_BOULDERS);
            for (ServerPlayer player : level.players()) {
                if (spawnQueue.size() >= MAX_BOULDERS) {
                    break;
                }
                double dx = player.getX() - center.x;
                double dz = player.getZ() - center.z;
                double dist = Math.sqrt(dx * dx + dz * dz);
                if (Math.abs(dist - heldRadius) > VIEW_RANGE) {
                    continue; // too far from the frontier to see it strain
                }
                double playerAngle = Math.atan2(dz, dx);
                // Angular fan sized so the cluster spans ~120 blocks of rim arc.
                double arcStep = Math.max(0.02D, 24.0D / Math.max(heldRadius, 24.0D));
                int planned = 0;
                for (int i = 0; i < MAX_PER_CLUSTER && spawnQueue.size() < MAX_BOULDERS; i++) {
                    double angle = playerAngle + (i - (MAX_PER_CLUSTER - 1) * 0.5D) * arcStep
                            + (random.nextDouble() - 0.5D) * arcStep * 0.4D;
                    if (angleTaken(takenAngles, angle, arcStep * 0.5D)) {
                        continue; // a neighbor's cluster already owns this stretch
                    }
                    takenAngles.add(angle);
                    Boulder boulder = planBoulder(center, angle, random);
                    if (boulder != null) {
                        spawnQueue.add(boulder);
                        planned++;
                    }
                }
                if (planned > 0) {
                    // The frontier CRACKS at this cluster: shake + deep drone, per cluster.
                    double cx = center.x + Math.cos(playerAngle) * heldRadius;
                    double cz = center.z + Math.sin(playerAngle) * heldRadius;
                    PacketDistributor.sendToPlayersNear(level, null, cx, player.getY(), cz,
                            FX_RANGE, S2CShakePayload.shake(0.35F, 24));
                    level.playSound(null, cx, player.getY(), cz,
                            EclipseSounds.EVENT_RIFT_DRONE.get(), SoundSource.AMBIENT, 1.0F, 0.6F);
                }
            }
        }

        private static boolean angleTaken(List<Double> taken, double angle, double tolerance) {
            for (int i = 0; i < taken.size(); i++) {
                double diff = Math.abs(Mth.wrapDegrees(Math.toDegrees(taken.get(i) - angle)));
                if (diff < Math.toDegrees(tolerance)) {
                    return true;
                }
            }
            return false;
        }

        /** One boulder plan just outside the old rim, hovering over the future annulus. */
        @Nullable
        private Boulder planBoulder(Vec3 center, double angle, RandomSource random) {
            // Ground probe INSIDE the rim (outside is still void); hover floats out over
            // the edge where the new land is about to appear.
            double probeR = Math.max(8.0D, heldRadius - 10.0D);
            int probeX = Mth.floor(center.x + Math.cos(angle) * probeR);
            int probeZ = Mth.floor(center.z + Math.sin(angle) * probeR);
            level.getChunk(probeX >> 4, probeZ >> 4);
            int groundY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, probeX, probeZ);
            if (groundY <= level.getMinBuildHeight()) {
                return null; // void column even inside the rim — nothing to anchor to
            }
            double hoverR = heldRadius + 2.0D + random.nextDouble() * 12.0D;
            double x = center.x + Math.cos(angle) * hoverR;
            double z = center.z + Math.sin(angle) * hoverR;
            double y = groundY + 7.0D + random.nextDouble() * 9.0D;
            // Index² weighting keeps most rocks plain stone with darker accents mixed in.
            BlockState state = BOULDER_BLOCKS[(int) (random.nextFloat() * random.nextFloat()
                    * BOULDER_BLOCKS.length)];
            float scale = MIN_SCALE + random.nextFloat() * (MAX_SCALE - MIN_SCALE);
            Vector3f axis = new Vector3f(random.nextFloat() - 0.5F, 1.0F,
                    random.nextFloat() - 0.5F).normalize();
            return new Boulder(new Vec3(x, y, z), state, scale, axis,
                    random.nextFloat() * Mth.TWO_PI);
        }

        void tick() {
            this.age++;
            if (!this.released) {
                // Fallback releases: the sweep stopped without our listener firing
                // (superseded edge cases), or the absolute watchdog tripped.
                if (this.age > SWEEP_STOPPED_GRACE_TICKS && !RingGrowthService.isRunning(profile)) {
                    release("sweep no longer running (fallback)");
                } else if (this.age > GATE_WATCHDOG_TICKS) {
                    release("gate watchdog (border safety beats spectacle)");
                }
            }
            // Spawn budget: at most MAX_SPAWNS_PER_TICK boulders enter the world per tick.
            for (int i = 0; i < MAX_SPAWNS_PER_TICK && !spawnQueue.isEmpty() && !released; i++) {
                Boulder boulder = spawnQueue.poll();
                spawn(boulder);
                boulders.add(boulder);
            }
            // Ambient strain rumble while held (small, per boulder cluster, throttled).
            if (!released && this.age > 0 && this.age % RUMBLE_PERIOD_TICKS == 0 && !boulders.isEmpty()) {
                Boulder anchor = boulders.get((this.age / RUMBLE_PERIOD_TICKS) % boulders.size());
                PacketDistributor.sendToPlayersNear(level, null, anchor.hoverPos.x,
                        anchor.hoverPos.y, anchor.hoverPos.z, FX_RANGE,
                        S2CShakePayload.shake(0.08F, 10));
            }
            if (this.age % UPDATE_INTERVAL_TICKS == 0) {
                for (Boulder boulder : boulders) {
                    animate(boulder);
                }
            }
            if (this.released && this.age - this.releaseAge > SINK_TICKS + UPDATE_INTERVAL_TICKS) {
                discardBoulders();
                this.done = true;
            }
        }

        /** All chunks are in: the border surges to the new ring and the rocks go home. */
        void release(String reason) {
            if (this.released) {
                return;
            }
            this.released = true;
            this.releaseAge = Math.max(this.age, 0);
            this.spawnQueue.clear(); // never raise new rocks into the goodbye
            SoftBorder.releaseGrowthHold(level.getServer(), profile, RELEASE_LERP_MS);
            PacketDistributor.sendToPlayersInDimension(level, new S2CCaptionPayload(
                    CAPTION_RELEASE, 60, S2CCaptionPayload.STYLE_WHISPER));
            for (Boulder boulder : boulders) {
                if (boulder.display != null && !boulder.display.isRemoved()) {
                    PacketDistributor.sendToPlayersNear(level, null, boulder.hoverPos.x,
                            boulder.hoverPos.y, boulder.hoverPos.z, FX_RANGE,
                            S2CShakePayload.shake(0.22F, 16));
                    level.playSound(null, boulder.hoverPos.x, boulder.hoverPos.y, boulder.hoverPos.z,
                            EclipseSounds.EVENT_RIFT_THUD.get(), SoundSource.AMBIENT, 0.9F, 0.55F);
                    break; // one goodbye beat carries the whole rim
                }
            }
            EclipseMod.LOGGER.info("ExpansionBorderFx: {} gate released ({}) — {} boulder(s) sinking",
                    profile.name(), reason, boulders.size());
        }

        private void spawn(Boulder boulder) {
            Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
            display.setBlockState(boulder.state);
            display.moveTo(boulder.hoverPos.x, boulder.hoverPos.y, boulder.hoverPos.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            boulder.spawnAge = this.age;
            display.setTransformation(poseAt(boulder, 0));
            // Sky-hovering displays light-sample at their anchor over the void — pin a
            // readable dusk-stone brightness instead of letting them render pitch black.
            DisplayBrightnessFx.set(display, 4, 15);
            LIVE_DISPLAYS.add(display.getUUID());
            level.addFreshEntity(display);
            boulder.display = display;
        }

        private void animate(Boulder boulder) {
            Display.BlockDisplay display = boulder.display;
            if (display == null || display.isRemoved()) {
                return;
            }
            // Keyframe lead (SanctumOrbitals law): push the pose this interpolation
            // window ENDS on, so the client tween never trails the server.
            int poseAge = this.age - boulder.spawnAge + UPDATE_INTERVAL_TICKS;
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
            display.setTransformation(poseAt(boulder, poseAge));
        }

        /**
         * Boulder pose at a given age: an eased {@value #RISE_TICKS}-tick heave from
         * {@value #RISE_FROM_BELOW} blocks below, then a slow bob + tumble hover, and
         * after release an accelerating {@value #SINK_TICKS}-tick sink to
         * {@value #SINK_DEPTH} blocks below with a shrink — rocks return to the earth
         * that birthed them. Entity anchor never moves; motion lives in the
         * transformation (the DisplayPlacerService law).
         */
        private Transformation poseAt(Boulder boulder, int poseAge) {
            float riseT = Mth.clamp(poseAge / (float) RISE_TICKS, 0.0F, 1.0F);
            float riseEase = 1.0F - (1.0F - riseT) * (1.0F - riseT) * (1.0F - riseT);
            float sinkT = 0.0F;
            if (this.released) {
                int sinkAge = (boulder.spawnAge + poseAge) - this.releaseAge;
                sinkT = Mth.clamp(sinkAge / (float) SINK_TICKS, 0.0F, 1.0F);
            }
            float bob = Mth.sin(boulder.bobPhase + poseAge * BOB_SPEED) * BOB_AMPLITUDE * riseEase;
            float yOff = -RISE_FROM_BELOW * (1.0F - riseEase) + bob
                    - SINK_DEPTH * sinkT * sinkT;
            float scale = boulder.scale * (0.35F + 0.65F * riseEase) * (1.0F - 0.45F * sinkT * sinkT);
            Quaternionf rotation = new Quaternionf().rotationAxis(
                    boulder.bobPhase + poseAge * TUMBLE_SPEED, boulder.tumbleAxis);
            Vector3f corner = new Vector3f(-scale * 0.5F, -scale * 0.5F, -scale * 0.5F)
                    .rotate(rotation);
            Vector3f translation = new Vector3f(corner.x, yOff + corner.y, corner.z);
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        void discardBoulders() {
            this.spawnQueue.clear();
            for (Boulder boulder : boulders) {
                Display.BlockDisplay display = boulder.display;
                if (display != null) {
                    LIVE_DISPLAYS.remove(display.getUUID());
                    if (!display.isRemoved()) {
                        display.discard();
                    }
                    boulder.display = null;
                }
            }
            boulders.clear();
        }
    }
}
