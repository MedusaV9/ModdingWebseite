package dev.projecteclipse.eclipse.worldgen.structure;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.SpawnerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.loot.BuiltInLootTables;

/**
 * The curated N1 fortress core ({@code eclipse:fortress_core}): a compact nether-brick
 * keep on the flat pad the nether terrain function reserves at the disc center (r &lt; 20
 * flattens to y≈132 — see {@code DiscTerrainFunction.computeSurfaceY}). Procedural
 * GhostShipBuilder-style build (vanilla {@code minecraft:fortress} is unusable here: its
 * pieces generate around y64, sprawl far beyond the N1 disc and need vanilla noise terrain).
 *
 * <p>Layout: 21×21 nether-brick platform, four corner turrets, a central 11×11 keep with a
 * caged blaze spawner on a blackstone dais (docs/ideas/01_world_terrain.md §D — blazes
 * gated behind crossing the moat bridges), a nether_bridge loot chest, and four 3-wide
 * cardinal bridge arms reaching towards the lava moat. Arms that line up with a moat
 * bridge causeway (E/W with the default map's 0°/180° {@code bridgeDeg}) extend all the
 * way to the moat's inner edge so keep → arm → causeway is one connected crossing; the
 * other arms stay short overlook stubs.</p>
 */
final class FortressCoreBuilder {
    private static final int PLATFORM_HALF = 10;
    private static final int KEEP_HALF = 5;
    private static final int BRIDGE_END = 26;

    private FortressCoreBuilder() {}

    static void build(ServerLevel level, DiscMapData.Landmark landmark) {
        int cx = landmark.x();
        int cz = landmark.z();
        int padY = DiscTerrainFunction.surfaceY(DiscProfile.NETHER, cx, cz);
        BlockState brick = Blocks.NETHER_BRICKS.defaultBlockState();
        BlockState cracked = Blocks.CRACKED_NETHER_BRICKS.defaultBlockState();
        BlockState chiseled = Blocks.CHISELED_NETHER_BRICKS.defaultBlockState();
        BlockState fence = Blocks.NETHER_BRICK_FENCE.defaultBlockState();
        BlockState air = Blocks.AIR.defaultBlockState();

        // Platform floor (replaces the pad surface) and cleared airspace above.
        for (int dx = -PLATFORM_HALF; dx <= PLATFORM_HALF; dx++) {
            for (int dz = -PLATFORM_HALF; dz <= PLATFORM_HALF; dz++) {
                int x = cx + dx;
                int z = cz + dz;
                level.getChunk(x >> 4, z >> 4);
                set(level, x, padY, z, FallbackBuilders.hash01(x, padY, z) < 0.15D ? cracked : brick);
                for (int y = padY + 1; y <= padY + 12; y++) {
                    set(level, x, y, z, air);
                }
            }
        }

        // Corner turrets with glowstone caps.
        for (int corner = 0; corner < 4; corner++) {
            int tx = cx + (corner % 2 == 0 ? -PLATFORM_HALF + 1 : PLATFORM_HALF - 1);
            int tz = cz + (corner / 2 == 0 ? -PLATFORM_HALF + 1 : PLATFORM_HALF - 1);
            for (int dy = 1; dy <= 7; dy++) {
                for (int ox = -1; ox <= 1; ox++) {
                    for (int oz = -1; oz <= 1; oz++) {
                        boolean shell = Math.abs(ox) == 1 || Math.abs(oz) == 1;
                        set(level, tx + ox, padY + dy, tz + oz,
                                dy == 7 ? chiseled : shell ? brick : air);
                    }
                }
            }
            set(level, tx, padY + 7, tz, Blocks.GLOWSTONE.defaultBlockState());
        }

        // Central keep: walls with cardinal doorways, open crenellated top.
        for (int dx = -KEEP_HALF; dx <= KEEP_HALF; dx++) {
            for (int dz = -KEEP_HALF; dz <= KEEP_HALF; dz++) {
                boolean wall = Math.abs(dx) == KEEP_HALF || Math.abs(dz) == KEEP_HALF;
                if (!wall) {
                    continue;
                }
                for (int dy = 1; dy <= 5; dy++) {
                    set(level, cx + dx, padY + dy, cz + dz, brick);
                }
                if ((dx + dz) % 2 == 0) {
                    set(level, cx + dx, padY + 6, cz + dz, fence);
                }
            }
        }
        for (Direction door : Direction.Plane.HORIZONTAL) {
            for (int dy = 1; dy <= 3; dy++) {
                BlockPos gap = new BlockPos(cx, padY + dy, cz).relative(door, KEEP_HALF);
                set(level, gap.getX(), gap.getY(), gap.getZ(), air);
            }
        }

        // Caged blaze spawner on a blackstone dais at the keep center.
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                set(level, cx + dx, padY + 1, cz + dz, Blocks.POLISHED_BLACKSTONE.defaultBlockState());
            }
        }
        BlockPos spawnerPos = new BlockPos(cx, padY + 2, cz);
        set(level, spawnerPos.getX(), spawnerPos.getY(), spawnerPos.getZ(), Blocks.SPAWNER.defaultBlockState());
        if (level.getBlockEntity(spawnerPos) instanceof SpawnerBlockEntity spawner) {
            spawner.setEntityId(EntityType.BLAZE, level.getRandom());
        }
        for (int dy = 2; dy <= 4; dy++) {
            for (Direction side : Direction.Plane.HORIZONTAL) {
                BlockPos cage = new BlockPos(cx, padY + dy, cz).relative(side, 2);
                set(level, cage.getX(), cage.getY(), cage.getZ(), fence);
            }
        }
        FallbackBuilders.lootChest(level, new BlockPos(cx + 3, padY + 1, cz + 3),
                Direction.WEST, BuiltInLootTables.NETHER_BRIDGE);

        // Four 3-wide bridge arms towards the lava moat, low fence stubs on the edges.
        // Arms aligned with a moat bridge causeway run on to the moat's inner edge so
        // the crossing connects (the moat land bridges sit at the causeway angles and
        // begin exactly there); misaligned arms keep the short overlook length.
        DiscMapData.Moat moat = DiscMapData.get().profile(DiscProfile.NETHER).moat();
        for (Direction arm : Direction.Plane.HORIZONTAL) {
            int armEnd = BRIDGE_END;
            if (moat != null && moat.withinBridge(armAngleDeg(arm), 0.0D)) {
                armEnd = Math.max(BRIDGE_END, moat.radius() - moat.halfWidth() + 2);
            }
            for (int d = PLATFORM_HALF + 1; d <= armEnd; d++) {
                for (int w = -1; w <= 1; w++) {
                    BlockPos deck = new BlockPos(cx, padY, cz).relative(arm, d)
                            .relative(arm.getClockWise(), w);
                    level.getChunk(deck.getX() >> 4, deck.getZ() >> 4);
                    set(level, deck.getX(), deck.getY(), deck.getZ(), brick);
                    for (int y = 1; y <= 4; y++) {
                        set(level, deck.getX(), deck.getY() + y, deck.getZ(), air);
                    }
                    if (Math.abs(w) == 1 && d % 4 == 0) {
                        set(level, deck.getX(), deck.getY() + 1, deck.getZ(), fence);
                    }
                }
            }
        }
        EclipseMod.LOGGER.info("PROCEDURAL: fortress core built at ({}, {}, {}) — blaze spawner at {}",
                cx, padY, cz, spawnerPos.toShortString());
    }

    /** Disc-map angle (degrees from +X towards +Z) a cardinal bridge arm points at. */
    private static double armAngleDeg(Direction arm) {
        return switch (arm) {
            case EAST -> 0.0D;
            case SOUTH -> 90.0D;
            case WEST -> 180.0D;
            default -> 270.0D; // NORTH
        };
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        FallbackBuilders.set(level, x, y, z, state);
    }
}
