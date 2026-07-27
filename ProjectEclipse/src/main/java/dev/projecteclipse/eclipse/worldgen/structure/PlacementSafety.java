package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * F-089 — player safety around structure materialization ("Blackscreen beim
 * Strukturen-Spawnen"). The arrival FX actively attract players to a pending site (ground
 * tear at enqueue, sky rift + hover-swirling BlockDisplays at the snap), yet the placement
 * path used to run with NO player handling at all: {@link SitePrep} raised the plateau
 * INTO anyone standing in a dip, and the placer pasted real blocks straight through
 * anyone on the footprint. A player left inside solid blocks gets the full-screen
 * inside-a-block overlay (near-black) plus darkness and suffocation — read by users as
 * "blackscreen when structures spawn". Two seams close it:
 *
 * <ol>
 *   <li><b>Evacuation</b> ({@link #evacuate}) — BEFORE any block of the site is written:
 *       every player intersecting the footprint volume (+{@value #INTERSECT_MARGIN}
 *       block) is set down on the nearest column just OUTSIDE the footprint edge, on top
 *       of whatever the terraform is about to make of that column
 *       ({@code max(WORLD_SURFACE, seat + 1)}), with fall protection. Called from
 *       {@code StructurePendingRegistry.placeNow} (covers the flight-completion snap,
 *       the auto-delay watchdog and operator triggers) and from
 *       {@link SitePrep#preparePlateau} (covers the terraform itself plus the W1.x/dev
 *       lanes that reach SitePrep without passing through the registry).</li>
 *   <li><b>Post-paste sweep</b> ({@link #sweepEntombed}) — AFTER the placer reports
 *       PLACED (belt-and-braces for players who wandered in during the budgeted prep):
 *       anyone still colliding with the placed blocks is popped up onto the
 *       motion-blocking surface — the {@code RingGrowthService} entombment-rescue
 *       recipe.</li>
 * </ol>
 *
 * <p>Spectators are exempt everywhere: they neither collide nor see the inside-a-block
 * overlay, and yanking a spectating operator around would only disrupt inspection.</p>
 */
public final class PlacementSafety {
    /** Footprint inflation (blocks) for the intersection tests — the "small margin". */
    private static final double INTERSECT_MARGIN = 1.0D;
    /** How far beyond the footprint edge an evacuated player is set down. */
    private static final int EDGE_CLEARANCE = 2;
    /** Fall protection for evacuated/lifted players (~5 s of Slow Falling). */
    private static final int SLOW_FALL_TICKS = 100;
    /** Grace window for a re-anchored cutscene freeze after a safety move (rescue recipe). */
    private static final int REANCHOR_GRACE_TICKS = 10;

    private PlacementSafety() {}

    /**
     * Teleports every non-spectator player whose bounding box intersects {@code bounds}
     * (+{@value #INTERSECT_MARGIN} block) to the nearest column {@value #EDGE_CLEARANCE}
     * blocks outside the footprint edge, standing at {@code max(WORLD_SURFACE, seat + 1)}
     * so the spot stays open even where the plateau skirt is about to raise the terrain.
     * A ridden vehicle is moved along (dismounted — the absolute-teleport convention).
     * Server thread only; call BEFORE any block of the site is written.
     *
     * @param seatY the plateau/seat height the placement will build at (the evacuation
     *              floor); pass the anchor Y when no seat has been computed yet
     */
    public static void evacuate(ServerLevel level, BoundingBox bounds, int seatY) {
        AABB danger = AABB.of(bounds).inflate(INTERSECT_MARGIN);
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (player.isSpectator() || !player.getBoundingBox().intersects(danger)) {
                continue;
            }
            int x = Mth.floor(player.getX());
            int z = Mth.floor(player.getZ());
            // Leave along the axis with the shortest way out — the nearest edge column.
            int west = x - bounds.minX();
            int east = bounds.maxX() - x;
            int north = z - bounds.minZ();
            int south = bounds.maxZ() - z;
            int shortest = Math.min(Math.min(west, east), Math.min(north, south));
            if (shortest == west) {
                x = bounds.minX() - EDGE_CLEARANCE;
            } else if (shortest == east) {
                x = bounds.maxX() + EDGE_CLEARANCE;
            } else if (shortest == north) {
                z = bounds.minZ() - EDGE_CLEARANCE;
            } else {
                z = bounds.maxZ() + EDGE_CLEARANCE;
            }
            double y = openY(level, x, z, seatY);
            Entity vehicle = player.getRootVehicle();
            if (vehicle != player) {
                player.stopRiding();
                vehicle.teleportTo(x + 0.5D, y, z + 0.5D);
            }
            player.teleportTo(level, x + 0.5D, y, z + 0.5D, player.getYRot(), player.getXRot());
            settle(player);
            EclipseMod.LOGGER.info(
                    "PlacementSafety: evacuated {} off the structure footprint [{}..{} x {}..{}] -> ({}, {}, {})",
                    player.getScoreboardName(), bounds.minX(), bounds.maxX(), bounds.minZ(),
                    bounds.maxZ(), x, (int) y, z);
        }
    }

    /**
     * Post-paste collision sweep: every non-spectator player inside {@code bounds}
     * (+{@value #INTERSECT_MARGIN}) whose bounding box still intersects solid blocks is
     * popped up onto the motion-blocking surface of their own column — the
     * {@code RingGrowthService.rescueFromReplay} recipe. Call AFTER the placer reported
     * PLACED; the live heightmaps already carry the placed blocks by then.
     */
    public static void sweepEntombed(ServerLevel level, BoundingBox bounds) {
        AABB placed = AABB.of(bounds).inflate(INTERSECT_MARGIN);
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (player.isSpectator() || !player.getBoundingBox().intersects(placed)
                    || level.noCollision(player)) {
                continue;
            }
            int x = Mth.floor(player.getX());
            int z = Mth.floor(player.getZ());
            int targetY = level.getHeight(Heightmap.Types.MOTION_BLOCKING, x, z);
            if (targetY <= level.getMinBuildHeight() || targetY <= player.getY()) {
                continue; // colliding with something above the surface — not this paste
            }
            player.teleportTo(level, player.getX(), targetY, player.getZ(),
                    player.getYRot(), player.getXRot());
            settle(player);
            EclipseMod.LOGGER.info(
                    "PlacementSafety: lifted {} out of placed blocks at ({}, {}) -> y {}",
                    player.getScoreboardName(), x, z, targetY);
        }
    }

    /**
     * The open standing Y of an evacuation column: the higher of the current
     * {@code WORLD_SURFACE} first-free block (vegetation-topped — landing on a canopy is
     * fine under Slow Falling) and one above the incoming seat (the plateau skirt may
     * raise this column right after the evacuation). Void columns (outside the disc rim)
     * fall back to the seat.
     */
    private static double openY(ServerLevel level, int x, int z, int seatY) {
        int surfaceY = level.getHeight(Heightmap.Types.WORLD_SURFACE, x, z);
        if (surfaceY <= level.getMinBuildHeight()) {
            return seatY + 1.0D;
        }
        return Math.max(surfaceY, seatY + 1);
    }

    /** Shared landing tail: kill momentum, clear fall state, brief Slow Falling, re-anchor a freeze. */
    private static void settle(ServerPlayer player) {
        player.setDeltaMovement(Vec3.ZERO);
        player.hurtMarked = true;
        player.resetFallDistance();
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                SLOW_FALL_TICKS, 0, false, false, true));
        if (FreezeService.isFrozen(player)) {
            FreezeService.reanchorWithGrace(player, REANCHOR_GRACE_TICKS);
        }
    }
}
