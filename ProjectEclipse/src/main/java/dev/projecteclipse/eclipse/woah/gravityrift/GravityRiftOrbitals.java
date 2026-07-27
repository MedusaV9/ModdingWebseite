package dev.projecteclipse.eclipse.woah.gravityrift;

import java.util.ArrayDeque;
import java.util.List;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * WOAH-02 orbital choreographer (plan §5.1/§5.2): the ~220
 * {@link Display.BlockDisplay} pieces of the three debris shells + the pulsing heart
 * composite, animated under the full {@code SanctumOrbitals} law set:
 *
 * <ul>
 *   <li><b>Fixed-mount law</b> — every display SITS at one open-air point
 *       ({@value GravityRiftZone#MOUNT_ABOVE_FLOOR} blocks over the crater floor, the
 *       anchor column chunk owns all of them, sky-light sampled from open air); all
 *       motion lives in the transformation's translation.</li>
 *   <li><b>Stateless-push law</b> — every {@value #UPDATE_CADENCE_TICKS} t one
 *       interpolated transform per display targets {@code poseAt(gameTime + cadence)};
 *       every pose component is an absolute function of game time (orbit, wobble, bob,
 *       tumble, the pulse-lift envelope on the beat raster and the inversion drop from
 *       the persisted window), so pauses glide back instead of snapping.</li>
 *   <li><b>90°-window law</b> — the fastest bob/wobble periods and the pulse/invert
 *       envelope segments are chosen so no 40 t interpolation window spans more than
 *       ~90° of any sine (the VFXPOLISH-3 flattening threshold).</li>
 *   <li><b>Persistence + reconcile law</b> — displays persist with their chunk and
 *       carry {@value #TAG} + an identity tag ({@code eclipse_gravity_orbital_<index>});
 *       reconciliation adopts one per piece, discards duplicates/strays and tops up
 *       missing ones through a {@value #SPAWNS_PER_TICK}/tick budget queue
 *       ({@code /kill @e[tag=eclipse_gravity_orbital]} self-heals in seconds).</li>
 * </ul>
 *
 * <p>Packet math: 220 displays / 40 t ≈ 5.5 packets/t sustained while a player is
 * within {@value #PLAYER_GATE_RANGE} blocks — and ZERO when nobody is (the whole pass
 * early-outs; displays hold their last pose).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GravityRiftOrbitals {
    /** Frozen command tag marking every rift orbital display for scans/cleanup. */
    public static final String TAG = "eclipse_gravity_orbital";

    /** Transform push cadence == interpolation duration (the SanctumOrbitals 40 t law). */
    public static final int UPDATE_CADENCE_TICKS = 40;
    /** Full reconcile sweep cadence (adopt/dedupe/top-up) while a player is near. */
    private static final int RECONCILE_CADENCE_TICKS = 600;
    /** Animation pauses (zero packets, zero scans) with no player within this range. */
    private static final double PLAYER_GATE_RANGE = 96.0D;
    /** Display spawn budget per tick (no 220-entity addFreshEntity burst — plan §3.1). */
    private static final int SPAWNS_PER_TICK = 8;

    /** Pulse lift: rise 40 t → hold 20 t → settle 100 t, peak this × layerLift blocks. */
    private static final double PULSE_LIFT_BLOCKS = 3.0D;
    private static final int PULSE_RISE_TICKS = 40;
    private static final int PULSE_HOLD_TICKS = 20;
    private static final int PULSE_SETTLE_TICKS = 100;

    /** Inversion drop segments (plan §3.3): fall 80 t → chaotic hold → glide back. */
    private static final int INVERT_FALL_TICKS = 80;
    /** Extra chaotic tumble multiplier at full inversion (unwinds during the glide). */
    private static final double INVERT_TUMBLE_BOOST = 4.0D;

    /** Heart core scale breath: 1.4 ↔ 1.8 over 90 t (plan §4.5). */
    private static final double HEART_BREATH_PERIOD_TICKS = 90.0D;
    private static final float HEART_BREATH_AMP = 0.125F; // ×1.6 base → 1.4..1.8

    /** Tag-scan volume half extent around the mount (covers r 34 + composite arms). */
    private static final int SCAN_XZ_MARGIN = GravityRiftZone.ZONE_RADIUS + 6;

    /** Brightness per layer (block light; sky always 15 — open-air mount). */
    private static final int[] LAYER_BLOCK_LIGHT = {8, 9, 11, 15, 13};

    /** Cached live displays by piece index; {@code null} until the first reconcile. */
    @Nullable
    private static Display.BlockDisplay[] displays;
    /** Set once the boot reconcile succeeded; missing entities re-arm it. */
    private static boolean reconciled;
    /** Piece indices awaiting a budgeted spawn. */
    private static final ArrayDeque<Integer> SPAWN_QUEUE = new ArrayDeque<>();

    private GravityRiftOrbitals() {}

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        ServerLevel overworld = server.overworld();
        GravityRiftState state = GravityRiftState.get(server);
        BlockPos anchor = state.anchor();
        if (!state.built() || anchor == null) {
            return;
        }
        if (!SPAWN_QUEUE.isEmpty()) {
            drainSpawnQueue(overworld, anchor, state);
        }
        if (server.getTickCount() % UPDATE_CADENCE_TICKS != 0) {
            return;
        }
        if (!playerNear(overworld, anchor)) {
            return; // presence gate: zero packets, zero scans, displays hold their pose
        }
        long gameTime = overworld.getGameTime();
        if (!reconciled || gameTime % RECONCILE_CADENCE_TICKS < UPDATE_CADENCE_TICKS) {
            reconcile(overworld, anchor, false);
        }
        animate(overworld, anchor, state, gameTime);
    }

    /** World-scoped statics must not leak into the next world (singleplayer switches). */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        displays = null;
        reconciled = false;
        SPAWN_QUEUE.clear();
    }

    /**
     * F-080 shutdown sweep hook: discards every cached orbital display plus any tagged
     * stray in the rift volume NOW — on {@code ServerStoppingEvent}, before the final
     * save and level close. The persisted zone state is untouched; the next boot's
     * reconcile pass rebuilds the full set through the budgeted spawn queue (the same
     * self-heal that covers {@code /kill @e[tag=eclipse_gravity_orbital]}). Returns the
     * display count dropped.
     */
    public static int forceClearNow(MinecraftServer server) {
        int discarded = 0;
        Display.BlockDisplay[] current = displays;
        if (current != null) {
            for (Display.BlockDisplay display : current) {
                if (display != null && !display.isRemoved()) {
                    display.discard();
                    discarded++;
                }
            }
        }
        BlockPos anchor = GravityRiftState.get(server).anchor();
        if (anchor != null) {
            for (Display.BlockDisplay stray : scanTagged(server.overworld(), anchor)) {
                if (!stray.isRemoved()) {
                    stray.discard();
                    discarded++;
                }
            }
        }
        displays = null;
        reconciled = false;
        SPAWN_QUEUE.clear();
        return discarded;
    }

    private static boolean playerNear(ServerLevel overworld, BlockPos anchor) {
        double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
        for (ServerPlayer player : overworld.players()) {
            if (!player.isSpectator() && player.distanceToSqr(
                    anchor.getX() + 0.5D, anchor.getY(), anchor.getZ() + 0.5D) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ reconcile

    /**
     * Tag-scans the rift volume, adopts exactly one display per piece (identity tag),
     * discards duplicates/strays, and queues whatever is missing for the budgeted
     * spawn drain. {@code force} additionally discards the adopted ones first (dev
     * rebuild). The first pass of a boot waits for the mount chunk's entity section
     * (the Deckhand 4a load-race lesson).
     */
    private static void reconcile(ServerLevel overworld, BlockPos anchor, boolean force) {
        if (!overworld.isLoaded(anchor)
                || !overworld.areEntitiesLoaded(ChunkPos.asLong(anchor))) {
            if (!reconciled) {
                EclipseMod.LOGGER.info(
                        "GravityRiftOrbitals: mount chunk entity section not loaded — reconcile deferred");
            }
            return;
        }
        List<GravityRiftZone.Piece> pieces = GravityRiftZone.pieces();
        Display.BlockDisplay[] resolved = new Display.BlockDisplay[pieces.size()];

        int adopted = 0;
        int discarded = 0;
        for (Display.BlockDisplay display : scanTagged(overworld, anchor)) {
            int index = pieceIndexOf(display, pieces.size());
            if (force || index < 0 || resolved[index] != null) {
                display.discard(); // stray, duplicate, or dev-rebuild wipe
                discarded++;
            } else {
                resolved[index] = display;
                adopted++;
            }
        }

        SPAWN_QUEUE.clear();
        int queued = 0;
        for (int i = 0; i < pieces.size(); i++) {
            if (resolved[i] == null) {
                SPAWN_QUEUE.add(i);
                queued++;
            }
        }
        displays = resolved;
        reconciled = true;
        if (queued > 0 || discarded > 0 || force) {
            EclipseMod.LOGGER.info(
                    "GravityRiftOrbitals: adopted {}, queued {} spawn(s), discarded {} (of {} pieces)",
                    adopted, queued, discarded, pieces.size());
        }
    }

    /** Budgeted top-up: {@value #SPAWNS_PER_TICK} spawns/tick out of the queue. */
    private static void drainSpawnQueue(ServerLevel overworld, BlockPos anchor,
            GravityRiftState state) {
        Display.BlockDisplay[] current = displays;
        if (current == null) {
            SPAWN_QUEUE.clear();
            return;
        }
        List<GravityRiftZone.Piece> pieces = GravityRiftZone.pieces();
        long gameTime = overworld.getGameTime();
        for (int n = 0; n < SPAWNS_PER_TICK && !SPAWN_QUEUE.isEmpty(); n++) {
            int index = SPAWN_QUEUE.poll();
            if (index >= current.length || current[index] != null) {
                continue;
            }
            Display.BlockDisplay display = spawnDisplay(overworld, anchor, pieces.get(index),
                    state, gameTime);
            if (display != null) {
                current[index] = display;
            }
        }
    }

    /** Every tagged block display in the rift volume (loaded entity sections only). */
    private static List<Display.BlockDisplay> scanTagged(ServerLevel overworld, BlockPos anchor) {
        Vec3 mount = mountPos(anchor);
        AABB volume = new AABB(
                anchor.getX() - SCAN_XZ_MARGIN, anchor.getY() - 8.0D,
                anchor.getZ() - SCAN_XZ_MARGIN,
                anchor.getX() + SCAN_XZ_MARGIN, mount.y + 24.0D,
                anchor.getZ() + SCAN_XZ_MARGIN);
        return overworld.getEntities(EntityType.BLOCK_DISPLAY, volume,
                display -> display.getTags().contains(TAG));
    }

    /** Resolves a scanned display back to its piece via the identity tag, or −1. */
    private static int pieceIndexOf(Display.BlockDisplay display, int pieceCount) {
        for (String tag : display.getTags()) {
            if (tag.startsWith(TAG + "_") && tag.length() > TAG.length() + 1) {
                try {
                    int index = Integer.parseInt(tag.substring(TAG.length() + 1));
                    return index >= 0 && index < pieceCount ? index : -1;
                } catch (NumberFormatException ignored) {
                    return -1;
                }
            }
        }
        return -1;
    }

    /** The one fixed entity position ALL pieces mount at (open air over the bowl center). */
    private static Vec3 mountPos(BlockPos anchor) {
        return new Vec3(anchor.getX() + 0.5D,
                anchor.getY() + GravityRiftZone.MOUNT_ABOVE_FLOOR, anchor.getZ() + 0.5D);
    }

    @Nullable
    private static Display.BlockDisplay spawnDisplay(ServerLevel overworld, BlockPos anchor,
            GravityRiftZone.Piece piece, GravityRiftState state, long gameTime) {
        Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(overworld);
        if (display == null) {
            EclipseMod.LOGGER.error("GravityRiftOrbitals: failed to create block_display #{}",
                    piece.index());
            return null;
        }
        Vec3 mount = mountPos(anchor);
        display.moveTo(mount.x, mount.y, mount.z, 0.0F, 0.0F);
        display.setBlockState(piece.block());
        display.addTag(TAG);
        display.addTag(TAG + "_" + piece.index());
        // Initial pose without interpolation: born already mid-orbit at its phase angle.
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(poseAt(piece, anchor, mount, gameTime, state));
        int layer = Math.min(piece.layer(), LAYER_BLOCK_LIGHT.length - 1);
        DisplayBrightnessFx.set(display, LAYER_BLOCK_LIGHT[layer], 15, piece.viewRange());
        overworld.addFreshEntity(display);
        return display;
    }

    // ------------------------------------------------------------------ motion

    /** One interpolated transform push per display, targeting the NEXT cadence boundary. */
    private static void animate(ServerLevel overworld, BlockPos anchor, GravityRiftState state,
            long gameTime) {
        Display.BlockDisplay[] current = displays;
        if (current == null) {
            return;
        }
        List<GravityRiftZone.Piece> pieces = GravityRiftZone.pieces();
        Vec3 mount = mountPos(anchor);
        boolean missing = false;
        for (int i = 0; i < current.length && i < pieces.size(); i++) {
            Display.BlockDisplay display = current[i];
            if (display == null || display.isRemoved()) {
                missing = true; // killed/unloaded — next boundary reconciles + respawns
                continue;
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_CADENCE_TICKS);
            display.setTransformation(poseAt(pieces.get(i), anchor, mount,
                    gameTime + UPDATE_CADENCE_TICKS, state));
        }
        if (missing) {
            reconciled = false;
        }
    }

    /**
     * Absolute pose of one piece at {@code gameTime} (the whole §5.2 law in one place):
     * orbit + radial wobble + bob, the pulse-lift envelope on the shared beat raster
     * (shells breathe upward on every 45 s beat, outer shells more —
     * {@code layerLift} 0.6/1.0/1.4), the inversion drop from the PERSISTED window
     * (pieces sag toward the bowl floor with a boosted tumble that smoothly unwinds
     * during the glide-back), composite member offsets rotated with the shared tumble,
     * and the heart core's scale breath. Translation is relative to the fixed
     * {@code mount}; the rotation pivots the per-axis-scaled block around its own
     * center ({@code T = pos − mount − Q·(s/2)}).
     */
    private static Transformation poseAt(GravityRiftZone.Piece piece, BlockPos anchor, Vec3 mount,
            long gameTime, GravityRiftState state) {
        double tau = Math.PI * 2.0D;
        // --- envelopes on the shared absolute rasters -------------------------------
        double pulse = piece.layerLift() <= 0.0D ? 0.0D
                : pulseLift(gameTime, anchor) * piece.layerLift() * PULSE_LIFT_BLOCKS;
        double invert = 0.0D;
        double tumbleBoost = 0.0D;
        long invertUntil = state.invertUntilGameTime();
        if (invertUntil != 0L && piece.fallDepth() > 0.0D) {
            long invertStart = invertUntil - GravityRiftZone.INVERT_TOTAL_TICKS;
            double envelope = invertEnvelope(gameTime - invertStart);
            invert = envelope * piece.fallDepth();
            tumbleBoost = envelope * INVERT_TUMBLE_BOOST;
        }

        // --- orbit + wobble + bob ----------------------------------------------------
        double angle = piece.phase0() + piece.omega() * gameTime;
        double radius = piece.baseRadius()
                + Math.sin(tau * gameTime / piece.wobPeriod() + piece.wobPhase()) * piece.wobAmp();
        double bob = Math.sin(tau * gameTime / piece.bobPeriod() + piece.bobPhase())
                * piece.bobAmp();
        double px = mount.x + Math.cos(angle) * radius;
        double py = mount.y - GravityRiftZone.MOUNT_ABOVE_FLOOR
                + piece.baseY() + bob + pulse - invert;
        double pz = mount.z + Math.sin(angle) * radius;

        // --- tumble (shared per composite; boosted + unwound through the inversion) --
        Vector3f axis = new Vector3f(piece.axX(), piece.axY(), piece.axZ());
        if (axis.lengthSquared() < 1.0E-6F) {
            axis.set(0.0F, 1.0F, 0.0F);
        }
        axis.normalize();
        float spinAngle = (float) (piece.phase0() * 5.0D
                + piece.spinRate() * gameTime * (1.0D + tumbleBoost));
        Quaternionf rotation = new Quaternionf().rotationAxis(spinAngle, axis);

        // --- composite member offset (rotates with the shared tumble) ----------------
        if (piece.offX() != 0.0D || piece.offY() != 0.0D || piece.offZ() != 0.0D) {
            Vector3f offset = rotation.transform(new Vector3f(
                    (float) piece.offX(), (float) piece.offY(), (float) piece.offZ()),
                    new Vector3f());
            px += offset.x;
            py += offset.y;
            pz += offset.z;
        }

        // --- scale (heart core breathes 1.4↔1.8) --------------------------------------
        float sx = piece.sx();
        float sy = piece.sy();
        float sz = piece.sz();
        if (piece.layer() == 3) {
            float breath = 1.0F + HEART_BREATH_AMP
                    * (float) Math.sin(tau * gameTime / HEART_BREATH_PERIOD_TICKS);
            sx *= breath;
            sy *= breath;
            sz *= breath;
        }

        Vector3f translation = new Vector3f(
                (float) (px - mount.x), (float) (py - mount.y), (float) (pz - mount.z));
        // Re-center the [0,s]³ block mesh on the target point through the rotation.
        Vector3f half = new Vector3f(sx * 0.5F, sy * 0.5F, sz * 0.5F);
        translation.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(sx, sy, sz),
                new Quaternionf());
    }

    /**
     * Pulse-lift envelope 0..1 on the absolute beat raster (the same
     * {@code gameTime % PERIOD == phaseOffset} law the service launches on): smoothstep
     * rise over {@value #PULSE_RISE_TICKS} t from the beat, hold
     * {@value #PULSE_HOLD_TICKS} t, settle over {@value #PULSE_SETTLE_TICKS} t. Each
     * segment spans ≥ 1 full interpolation window (40/20/100 t), so the client tween
     * never flattens the ride.
     */
    private static double pulseLift(long gameTime, BlockPos anchor) {
        int offset = GravityRiftZone.pulsePhaseOffset(anchor);
        long phase = Math.floorMod(gameTime - offset, (long) GravityRiftZone.PULSE_PERIOD_TICKS);
        if (phase < PULSE_RISE_TICKS) {
            return GravityRiftZone.smoothstep(phase / (double) PULSE_RISE_TICKS);
        }
        phase -= PULSE_RISE_TICKS;
        if (phase < PULSE_HOLD_TICKS) {
            return 1.0D;
        }
        phase -= PULSE_HOLD_TICKS;
        if (phase < PULSE_SETTLE_TICKS) {
            return GravityRiftZone.smoothstep(1.0D - phase / (double) PULSE_SETTLE_TICKS);
        }
        return 0.0D;
    }

    /**
     * Inversion envelope 0..1 at {@code τ} ticks after the inversion start: smoothstep
     * fall over {@value #INVERT_FALL_TICKS} t, hold at 1 until
     * {@value GravityRiftZone#INVERT_ACTIVE_TICKS} t, smoothstep glide back to 0 at
     * {@value GravityRiftZone#INVERT_TOTAL_TICKS} t. Both boundary values are exactly 0
     * — the pose function is continuous when the window starts and when the state
     * clears, so there is never a snap.
     */
    private static double invertEnvelope(long tau) {
        if (tau < 0 || tau >= GravityRiftZone.INVERT_TOTAL_TICKS) {
            return 0.0D;
        }
        if (tau < INVERT_FALL_TICKS) {
            return GravityRiftZone.smoothstep(tau / (double) INVERT_FALL_TICKS);
        }
        if (tau < GravityRiftZone.INVERT_ACTIVE_TICKS) {
            return 1.0D;
        }
        double glide = (tau - GravityRiftZone.INVERT_ACTIVE_TICKS)
                / (double) (GravityRiftZone.INVERT_TOTAL_TICKS - GravityRiftZone.INVERT_ACTIVE_TICKS);
        return GravityRiftZone.smoothstep(1.0D - glide);
    }

    // ------------------------------------------------------------------ dev hook

    /**
     * Dev hook ({@code /dev woah gravity orbitals}): wipes every tagged display and
     * respawns the full set fresh (budgeted). Safe no-op when the rift is not built.
     */
    public static void rebuild(ServerLevel overworld) {
        GravityRiftState state = GravityRiftState.get(overworld.getServer());
        BlockPos anchor = state.anchor();
        if (!state.built() || anchor == null) {
            EclipseMod.LOGGER.info("GravityRiftOrbitals.rebuild: rift not built — nothing to do");
            return;
        }
        reconcile(overworld, anchor, true);
        EclipseMod.LOGGER.info("GravityRiftOrbitals.rebuild: {} spawn(s) queued at {}",
                SPAWN_QUEUE.size(), anchor.toShortString());
    }

    /** Live display count (dev status). */
    public static int liveCount() {
        Display.BlockDisplay[] current = displays;
        if (current == null) {
            return 0;
        }
        int alive = 0;
        for (Display.BlockDisplay display : current) {
            if (display != null && !display.isRemoved()) {
                alive++;
            }
        }
        return alive;
    }
}
