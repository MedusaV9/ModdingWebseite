package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.List;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
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
 * P6-W5/W56 (plans_v3 §2.6, build pass 2): the floating sanctum's rotating-debris ring —
 * twelve persistent {@link Display.BlockDisplay} entities on two counter-rotating rings
 * around the island, slowly orbiting the altar axis while each fragment tumbles about its
 * own tilted axis and bobs ±{@value #BOB_AMPLITUDE} blocks, "as if held by magic".
 *
 * <p><b>Anchor data is W4's frozen interface</b>
 * ({@link FloatingSanctumBuilder#orbitalAnchors}): ring/center/radius/phase/base scale/
 * block state per debris piece. This class owns the presentation on top: a per-anchor
 * {@link #SCALE_VARIATION size spread} (final display scales
 * {@value #MIN_FINAL_SCALE}–{@value #MAX_FINAL_SCALE} — a couple of big purpur chunks
 * down to small obsidian shards), initial rotations, and all motion.</p>
 *
 * <p><b>Animation transport</b> (OarAnimator precedent — the accesstransformer-opened
 * {@code Display} setters): every {@value #UPDATE_CADENCE_TICKS} ticks the server pushes
 * one interpolated transformation per display ({@code setTransformationInterpolationDelay(0)}
 * + {@code setTransformationInterpolationDuration(}{@value #UPDATE_CADENCE_TICKS}{@code )}
 * + {@code setTransformation(poseAt(gameTime + cadence))}), so clients tween each 40 t
 * window seamlessly into the next — continuous motion, zero jitter, no per-tick packets.
 * All pose components are absolute functions of game time, so pushes are stateless and a
 * paused ring glides (rather than snaps) back on track when animation resumes. Packet
 * math: 12 displays × 1 entity-data packet / 40 t = 0.3 packets/s each, 6 packets/s
 * total while a player is near — and ZERO while nobody is within
 * {@value #PLAYER_GATE_RANGE} blocks of the altar (the whole pass early-outs, displays
 * simply hold their last pose).</p>
 *
 * <p><b>Why the entities never move:</b> every display sits at ONE fixed open-air point
 * above the island top ({@link #anchorMountPos}) — the orbit offset (radius ≤ 13 + bob)
 * lives entirely inside the transformation's translation. Fixed position means: one
 * chunk owns all twelve (the altar column chunk — spawn chunks, always loaded), the
 * light sample comes from open sky instead of the island's solid interior (displays
 * sample light at the ENTITY position, which would render them pitch black from inside
 * the mass), and there is no dependency on the not-AT-opened teleport interpolation.</p>
 *
 * <p><b>Persistence + self-healing</b> (plan §2.6 — no {@code EclipseWorldState} schema
 * change): displays are persistent entities saved with their chunk and carry the frozen
 * command tag {@value #TAG} plus a per-anchor identity tag
 * ({@code eclipse_sanctum_orbital_r<ring>_<index>}). Reconciliation (boot, live sanctum
 * flip, every {@value #RECONCILE_CADENCE_TICKS} t, and whenever a cached display goes
 * missing) tag-scans the island volume, adopts one display per anchor, discards
 * duplicates/strays, and respawns whatever is missing — {@code /kill
 * @e[tag=eclipse_sanctum_orbital]} self-heals within two seconds of a player being near.
 * The first reconcile of a boot waits for the altar chunk's entity section
 * ({@link ServerLevel#areEntitiesLoaded}) so late-loading persisted displays are adopted
 * instead of duplicated (the Deckhand 4a load-race lesson).</p>
 *
 * <p><b>Dev hook:</b> {@link #rebuild(ServerLevel)} discards every tagged display and
 * respawns the full ring fresh (for {@code /dev} wiring — see
 * {@code docs/plans_v3/wiring/P6-W56_wiring.md}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SanctumOrbitals {
    /** Frozen command tag (plan §6) marking every orbital display for scans/cleanup. */
    public static final String TAG = "eclipse_sanctum_orbital";

    /** Transform push cadence == interpolation duration (plan §2.6: ~40 t for smoothness). */
    public static final int UPDATE_CADENCE_TICKS = 40;
    /** Full reconcile sweep cadence (adopt/dedupe/top-up) while a player is near. */
    public static final int RECONCILE_CADENCE_TICKS = 600;
    /** Animation pauses (zero packets, zero scans) with no player within this range. */
    public static final double PLAYER_GATE_RANGE = 96.0D;

    /** Orbit rate: ~3°/s around the island axis (6° per 40 t push — plan §2.6). */
    private static final double ORBIT_DEG_PER_TICK = 0.15D;
    /** Gentle vertical bob amplitude (blocks). */
    private static final double BOB_AMPLITUDE = 0.4D;
    /** Bob period base; each anchor stretches it via its variation row (~6–10 s). */
    private static final double BOB_BASE_PERIOD_TICKS = 140.0D;
    /** Individual tumble rate base (deg/tick, ~1.6–4.4°/s across the ring). */
    private static final double SPIN_DEG_PER_TICK_BASE = 0.08D;

    /**
     * Per-anchor size spread multiplied onto the frozen anchor scales (W4 bases run
     * 0.40–0.70) so the debris reads as genuinely different sizes: final scales span
     * {@value #MIN_FINAL_SCALE}–{@value #MAX_FINAL_SCALE} (task spec 0.4–1.6). Index =
     * anchor order of {@link FloatingSanctumBuilder#orbitalAnchors} (low ring 0–6, high
     * ring 7–11).
     */
    private static final float[] SCALE_VARIATION = {
            2.3F, 1.0F, 1.5F, 1.2F, 1.0F, 1.8F, 1.15F, // low ring: big purpur slab → shards
            1.6F, 1.0F, 1.3F, 2.0F, 1.1F};             // high ring
    public static final float MIN_FINAL_SCALE = 0.40F;
    public static final float MAX_FINAL_SCALE = 1.61F;

    /** Mount height of the fixed entity position above the island top (open sky light). */
    private static final int MOUNT_ABOVE_TOP = 16;
    /** Tag-scan half extent around the altar column (covers both rings + margin). */
    private static final int SCAN_XZ_MARGIN = 20;

    /** Cached live displays by anchor order; {@code null} until the first reconcile. */
    @Nullable
    private static Display.BlockDisplay[] displays;
    /** Set once the boot/flip reconcile succeeded; missing entities re-arm it. */
    private static boolean reconciled;

    private SanctumOrbitals() {}

    // --- server tick loop ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % UPDATE_CADENCE_TICKS != 0) {
            return;
        }
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = sanctumAltar(overworld);
        if (altarPos == null) {
            return; // not floating (stage 0 grounded sanctum) or no sanctum yet
        }
        if (!playerNear(overworld, altarPos)) {
            return; // presence gate: zero packets, zero scans, displays hold their pose
        }
        long gameTime = overworld.getGameTime();
        if (!reconciled || gameTime % RECONCILE_CADENCE_TICKS < UPDATE_CADENCE_TICKS) {
            reconcile(overworld, altarPos, false);
        }
        animate(overworld, altarPos, gameTime);
    }

    /** World-scoped statics must not leak into the next world (singleplayer switches). */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        displays = null;
        reconciled = false;
    }

    /** The altar position IF the v2 floating sanctum is stamped, else {@code null}. */
    @Nullable
    private static BlockPos sanctumAltar(ServerLevel overworld) {
        if (SanctumVersionData.get(overworld).version() < SanctumVersionData.VERSION_FLOATING) {
            return null;
        }
        return EclipseWorldState.get(overworld.getServer()).getSanctumAltarPos();
    }

    private static boolean playerNear(ServerLevel overworld, BlockPos altarPos) {
        double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
        for (ServerPlayer player : overworld.players()) {
            if (!player.isSpectator() && player.distanceToSqr(
                    altarPos.getX() + 0.5D, altarPos.getY(), altarPos.getZ() + 0.5D) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    // --- reconciliation (adopt / dedupe / top-up / discard extras) ---

    /**
     * Tag-scans the island volume, adopts exactly one display per anchor (identity tag),
     * discards duplicates and unidentifiable tagged strays, and spawns whatever is
     * missing. {@code force} additionally discards the adopted ones first (dev rebuild).
     * The first pass of a boot is deferred until the altar chunk's entity section is
     * loaded, so persisted displays are adopted instead of duplicated.
     */
    private static void reconcile(ServerLevel overworld, BlockPos altarPos, boolean force) {
        if (!overworld.isLoaded(altarPos)
                || !overworld.areEntitiesLoaded(ChunkPos.asLong(altarPos))) {
            if (!reconciled) {
                EclipseMod.LOGGER.info(
                        "SanctumOrbitals: altar chunk entity section not loaded yet — reconcile deferred");
            }
            return;
        }
        List<FloatingSanctumBuilder.OrbitalAnchor> anchors =
                FloatingSanctumBuilder.orbitalAnchors(altarPos);
        Display.BlockDisplay[] resolved = new Display.BlockDisplay[anchors.size()];

        int adopted = 0;
        int discarded = 0;
        for (Display.BlockDisplay display : scanTagged(overworld, altarPos)) {
            int index = anchorIndexOf(display, anchors);
            if (force || index < 0 || resolved[index] != null) {
                display.discard(); // stray, duplicate, or dev-rebuild wipe
                discarded++;
            } else {
                resolved[index] = display;
                adopted++;
            }
        }

        long gameTime = overworld.getGameTime();
        int spawned = 0;
        for (int i = 0; i < anchors.size(); i++) {
            if (resolved[i] != null) {
                continue;
            }
            Display.BlockDisplay display = spawnDisplay(overworld, altarPos, anchors.get(i), i, gameTime);
            if (display != null) {
                resolved[i] = display;
                spawned++;
            }
        }
        displays = resolved;
        reconciled = true;
        if (spawned > 0 || discarded > 0 || force) {
            EclipseMod.LOGGER.info(
                    "SanctumOrbitals: adopted {} orbital display(s), spawned {}, discarded {} (of {} anchors)",
                    adopted, spawned, discarded, anchors.size());
        }
    }

    /** Every tagged block display in the island volume (loaded entity sections only). */
    private static List<Display.BlockDisplay> scanTagged(ServerLevel overworld, BlockPos altarPos) {
        int topY = FloatingSanctumBuilder.islandTopY(altarPos);
        AABB volume = new AABB(
                altarPos.getX() - SCAN_XZ_MARGIN, topY - 22.0D, altarPos.getZ() - SCAN_XZ_MARGIN,
                altarPos.getX() + SCAN_XZ_MARGIN, topY + MOUNT_ABOVE_TOP + 8.0D,
                altarPos.getZ() + SCAN_XZ_MARGIN);
        return overworld.getEntities(EntityType.BLOCK_DISPLAY, volume,
                display -> display.getTags().contains(TAG));
    }

    /** Resolves a scanned display back to its anchor via the identity tag, or −1. */
    private static int anchorIndexOf(Display.BlockDisplay display,
            List<FloatingSanctumBuilder.OrbitalAnchor> anchors) {
        for (int i = 0; i < anchors.size(); i++) {
            if (display.getTags().contains(anchorTag(anchors.get(i)))) {
                return i;
            }
        }
        return -1;
    }

    private static String anchorTag(FloatingSanctumBuilder.OrbitalAnchor anchor) {
        return TAG + "_r" + anchor.ring() + "_" + anchor.index();
    }

    /** The one fixed entity position all twelve displays mount at (open sky above the top). */
    private static Vec3 anchorMountPos(BlockPos altarPos) {
        return new Vec3(altarPos.getX() + 0.5D,
                FloatingSanctumBuilder.islandTopY(altarPos) + MOUNT_ABOVE_TOP,
                altarPos.getZ() + 0.5D);
    }

    @Nullable
    private static Display.BlockDisplay spawnDisplay(ServerLevel overworld, BlockPos altarPos,
            FloatingSanctumBuilder.OrbitalAnchor anchor, int orderIndex, long gameTime) {
        Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(overworld);
        if (display == null) {
            EclipseMod.LOGGER.error("SanctumOrbitals: failed to create block_display for anchor r{} #{}",
                    anchor.ring(), anchor.index());
            return null;
        }
        Vec3 mount = anchorMountPos(altarPos);
        display.moveTo(mount.x, mount.y, mount.z, 0.0F, 0.0F);
        display.setBlockState(anchor.block());
        display.addTag(TAG);
        display.addTag(anchorTag(anchor));
        // Initial pose without interpolation: born already mid-orbit at its phase angle.
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(poseAt(anchor, orderIndex, mount, gameTime));
        overworld.addFreshEntity(display);
        return display;
    }

    // --- motion ---

    /** One interpolated transform push per display, targeting the NEXT cadence boundary. */
    private static void animate(ServerLevel overworld, BlockPos altarPos, long gameTime) {
        Display.BlockDisplay[] current = displays;
        if (current == null) {
            return;
        }
        List<FloatingSanctumBuilder.OrbitalAnchor> anchors =
                FloatingSanctumBuilder.orbitalAnchors(altarPos);
        Vec3 mount = anchorMountPos(altarPos);
        boolean missing = false;
        for (int i = 0; i < current.length && i < anchors.size(); i++) {
            Display.BlockDisplay display = current[i];
            if (display == null || display.isRemoved()) {
                missing = true; // killed/unloaded — next pass reconciles + respawns
                continue;
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_CADENCE_TICKS);
            display.setTransformation(poseAt(anchors.get(i), i, mount,
                    gameTime + UPDATE_CADENCE_TICKS));
        }
        if (missing) {
            reconciled = false;
        }
    }

    /**
     * Absolute pose of one debris piece at {@code gameTime}: orbit around the island axis
     * (ring 0 clockwise, ring 1 counter-clockwise), per-anchor bob, per-anchor tumble
     * about a fixed tilted axis, all folded into a single {@link Transformation} whose
     * translation is relative to the fixed {@code mount} entity position. The rotation
     * pivots the SCALED block around its own center
     * ({@code T = orbitPoint − mount − Q·(s/2)}, matrix order T·L·S).
     */
    private static Transformation poseAt(FloatingSanctumBuilder.OrbitalAnchor anchor,
            int orderIndex, Vec3 mount, long gameTime) {
        int variationIndex = Math.min(orderIndex, SCALE_VARIATION.length - 1);
        float scale = anchor.scale() * SCALE_VARIATION[variationIndex];
        double direction = anchor.ring() == 0 ? 1.0D : -1.0D; // counter-rotating rings
        double orbitAngle = anchor.phaseRadians()
                + direction * Math.toRadians(ORBIT_DEG_PER_TICK) * gameTime;

        double bobPeriod = BOB_BASE_PERIOD_TICKS * (0.8D + 0.35D * (orderIndex % 4));
        double bob = Math.sin((Math.PI * 2.0D / bobPeriod) * gameTime
                + anchor.phaseRadians() * 3.0D) * BOB_AMPLITUDE;

        Vec3 center = anchor.center();
        Vector3f translation = new Vector3f(
                (float) (center.x + Math.cos(orbitAngle) * anchor.radius() - mount.x),
                (float) (center.y + bob - mount.y),
                (float) (center.z + Math.sin(orbitAngle) * anchor.radius() - mount.z));

        // Tumble: fixed tilted axis per anchor, rate varying across the ring, starting
        // from a per-anchor initial angle so no two fragments are ever pose-synced.
        Vector3f axis = new Vector3f(
                (float) Math.sin(anchor.phaseRadians() * 2.0D + anchor.ring()),
                1.2F,
                (float) Math.cos(anchor.phaseRadians() * 2.0D)).normalize();
        double spinRate = Math.toRadians(SPIN_DEG_PER_TICK_BASE * (1.0D + 0.35D * (orderIndex % 5)));
        float spinAngle = (float) (anchor.phaseRadians() * 5.0D
                - direction * spinRate * gameTime);
        Quaternionf rotation = new Quaternionf().rotationAxis(spinAngle, axis);

        // Re-center the [0,scale]^3 block mesh on the orbit point through the rotation.
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        translation.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    // --- dev hook ---

    /**
     * Dev hook (for {@code /dev} — wiring doc): wipes every tagged orbital display and
     * respawns the full ring fresh from the current anchor data. Safe no-op when the
     * sanctum is not floating yet. Runs on the server thread.
     */
    public static void rebuild(ServerLevel overworld) {
        BlockPos altarPos = sanctumAltar(overworld);
        if (altarPos == null) {
            EclipseMod.LOGGER.info("SanctumOrbitals.rebuild: sanctum not floating — nothing to do");
            return;
        }
        reconcile(overworld, altarPos, true);
        EclipseMod.LOGGER.info("SanctumOrbitals.rebuild: orbital ring rebuilt at {}",
                altarPos.toShortString());
    }
}
