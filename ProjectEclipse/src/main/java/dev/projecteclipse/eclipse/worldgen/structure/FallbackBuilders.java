package dev.projecteclipse.eclipse.worldgen.structure;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.EndPortalFrameBlock;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.entity.SpawnerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.loot.BuiltInLootTables;
import net.minecraft.world.level.storage.loot.LootTable;
import net.minecraft.resources.ResourceKey;

/**
 * Compact procedural stand-ins (GhostShipBuilder pattern: deterministic setBlock loops) used
 * ONLY when a vanilla {@code Structure.generate} refuses to produce pieces in the disc
 * context after {@value StructureStamper#VANILLA_ATTEMPTS} attempts — a {@code stages.json}
 * structure never silently misses. Every caller logs loudly which path ran.
 */
final class FallbackBuilders {
    private FallbackBuilders() {}

    /** 13×13 sandstone step pyramid with a small loot chamber (desert_pyramid loot). */
    static void desertTemple(ServerLevel level, BlockPos base) {
        BlockState sandstone = Blocks.SANDSTONE.defaultBlockState();
        BlockState cut = Blocks.CUT_SANDSTONE.defaultBlockState();
        BlockState chiseled = Blocks.CHISELED_SANDSTONE.defaultBlockState();
        // Five shrinking tiers.
        for (int tier = 0; tier < 5; tier++) {
            int half = 6 - tier;
            int y = base.getY() + 1 + tier;
            for (int dx = -half; dx <= half; dx++) {
                for (int dz = -half; dz <= half; dz++) {
                    boolean edge = Math.abs(dx) == half || Math.abs(dz) == half;
                    set(level, base.getX() + dx, y, base.getZ() + dz, edge ? cut : sandstone);
                }
            }
        }
        set(level, base.getX(), base.getY() + 6, base.getZ(), chiseled);
        // Hollow loot chamber under the peak with the vanilla desert pyramid loot table.
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                for (int y = base.getY() + 1; y <= base.getY() + 3; y++) {
                    set(level, base.getX() + dx, y, base.getZ() + dz, Blocks.AIR.defaultBlockState());
                }
            }
        }
        // South-facing entrance corridor.
        for (int dz = 3; dz <= 6; dz++) {
            set(level, base.getX(), base.getY() + 1, base.getZ() + dz, Blocks.AIR.defaultBlockState());
            set(level, base.getX(), base.getY() + 2, base.getZ() + dz, Blocks.AIR.defaultBlockState());
        }
        lootChest(level, base.offset(0, 1, -1), Direction.SOUTH, BuiltInLootTables.DESERT_PYRAMID);
        set(level, base.getX() - 2, base.getY() + 1, base.getZ() - 2, Blocks.TNT.defaultBlockState());
        EclipseMod.LOGGER.info("Fallback desert temple built at {}", base.toShortString());
    }

    /** 9×9 three-tier mossy cobblestone shrine with jungle_temple loot. */
    static void jungleTemple(ServerLevel level, BlockPos base) {
        for (int tier = 0; tier < 3; tier++) {
            int half = 4 - tier;
            int y = base.getY() + 1 + tier * 2;
            for (int dx = -half; dx <= half; dx++) {
                for (int dz = -half; dz <= half; dz++) {
                    for (int dy = 0; dy < 2; dy++) {
                        boolean wall = Math.abs(dx) == half || Math.abs(dz) == half;
                        BlockState state = wall || dy == 0 ? mossyMix(base.getX() + dx, y + dy, base.getZ() + dz)
                                : Blocks.AIR.defaultBlockState();
                        set(level, base.getX() + dx, y + dy, base.getZ() + dz, state);
                    }
                }
            }
        }
        set(level, base.getX(), base.getY() + 7, base.getZ(), Blocks.MOSSY_STONE_BRICKS.defaultBlockState());
        // Entrance gap on the +X face and the loot chest inside the ground tier.
        for (int dy = 1; dy <= 2; dy++) {
            set(level, base.getX() + 4, base.getY() + dy, base.getZ(), Blocks.AIR.defaultBlockState());
        }
        lootChest(level, base.offset(-3, 1, 0), Direction.EAST, BuiltInLootTables.JUNGLE_TEMPLE);
        EclipseMod.LOGGER.info("Fallback jungle temple built at {}", base.toShortString());
    }

    /** Central well plus three oak huts — a minimal hamlet stand-in for village_plains. */
    static void village(ServerLevel level, BlockPos anchor) {
        buildWell(level, anchor);
        buildHut(level, anchor.offset(9, 0, 0), Direction.WEST);
        buildHut(level, anchor.offset(-9, 0, 2), Direction.EAST);
        buildHut(level, anchor.offset(1, 0, 9), Direction.NORTH);
        EclipseMod.LOGGER.info("Fallback village (well + 3 huts) built at {}", anchor.toShortString());
    }

    private static void buildWell(ServerLevel level, BlockPos base) {
        BlockState cobble = Blocks.COBBLESTONE.defaultBlockState();
        for (int dx = -1; dx <= 2; dx++) {
            for (int dz = -1; dz <= 2; dz++) {
                boolean rim = dx == -1 || dx == 2 || dz == -1 || dz == 2;
                set(level, base.getX() + dx, base.getY() + 1, base.getZ() + dz,
                        rim ? cobble : Blocks.WATER.defaultBlockState());
                set(level, base.getX() + dx, base.getY(), base.getZ() + dz, cobble);
            }
        }
        for (int corner = 0; corner < 4; corner++) {
            int cx = base.getX() + (corner % 2 == 0 ? -1 : 2);
            int cz = base.getZ() + (corner / 2 == 0 ? -1 : 2);
            for (int dy = 2; dy <= 4; dy++) {
                set(level, cx, base.getY() + dy, cz, Blocks.OAK_FENCE.defaultBlockState());
            }
        }
        for (int dx = -1; dx <= 2; dx++) {
            for (int dz = -1; dz <= 2; dz++) {
                set(level, base.getX() + dx, base.getY() + 5, base.getZ() + dz, cobble);
            }
        }
    }

    /** 5×5 oak-plank hut with a doorway facing {@code facing} and a bed + torch inside. */
    private static void buildHut(ServerLevel level, BlockPos base, Direction facing) {
        BlockState planks = Blocks.OAK_PLANKS.defaultBlockState();
        BlockState log = Blocks.OAK_LOG.defaultBlockState();
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                set(level, base.getX() + dx, base.getY(), base.getZ() + dz, planks);
                boolean corner = Math.abs(dx) == 2 && Math.abs(dz) == 2;
                boolean wall = Math.abs(dx) == 2 || Math.abs(dz) == 2;
                for (int dy = 1; dy <= 3; dy++) {
                    BlockState state = corner ? log : wall ? planks : Blocks.AIR.defaultBlockState();
                    set(level, base.getX() + dx, base.getY() + dy, base.getZ() + dz, state);
                }
                set(level, base.getX() + dx, base.getY() + 4, base.getZ() + dz, planks);
            }
        }
        BlockPos door = base.relative(facing, 2);
        set(level, door.getX(), base.getY() + 1, door.getZ(), Blocks.AIR.defaultBlockState());
        set(level, door.getX(), base.getY() + 2, door.getZ(), Blocks.AIR.defaultBlockState());
        set(level, base.getX(), base.getY() + 3, base.getZ(),
                Blocks.TORCH.defaultBlockState());
    }

    /**
     * Mini stronghold portal room stamped into the mountain cavity: stone-brick shell, lava
     * moat, silverfish spawner and the 12-frame end portal ring — frames WITHOUT eyes
     * ({@code EndPortalFrameBlock.HAS_EYE=false}), matching the vanilla-path contract.
     */
    static void strongholdPortalRoom(ServerLevel level, BlockPos center) {
        BlockState brick = Blocks.STONE_BRICKS.defaultBlockState();
        BlockState air = Blocks.CAVE_AIR.defaultBlockState();
        int floorY = center.getY();
        // 15×9 shell, 6 high, floor + walls + roof.
        for (int dx = -7; dx <= 7; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                boolean wall = Math.abs(dx) == 7 || Math.abs(dz) == 4;
                set(level, center.getX() + dx, floorY, center.getZ() + dz,
                        crackedMix(center.getX() + dx, floorY, center.getZ() + dz));
                for (int dy = 1; dy <= 5; dy++) {
                    set(level, center.getX() + dx, floorY + dy, center.getZ() + dz, wall ? brick : air);
                }
                set(level, center.getX() + dx, floorY + 6, center.getZ() + dz, brick);
            }
        }
        // Entrance gap on the -X face.
        for (int dy = 1; dy <= 3; dy++) {
            set(level, center.getX() - 7, floorY + dy, center.getZ(), air);
        }
        // Raised portal dais with a lava moat, frames on the raised ring.
        int daisX = center.getX() + 3;
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                boolean rim = Math.abs(dx) == 2 || Math.abs(dz) == 2;
                set(level, daisX + dx, floorY + 1, center.getZ() + dz,
                        rim ? brick : Blocks.LAVA.defaultBlockState());
            }
        }
        for (Direction side : Direction.Plane.HORIZONTAL) {
            for (int i = -1; i <= 1; i++) {
                BlockPos framePos = new BlockPos(daisX, floorY + 2, center.getZ())
                        .relative(side, 2).relative(side.getClockWise(), i);
                set(level, framePos.getX(), framePos.getY(), framePos.getZ(),
                        Blocks.END_PORTAL_FRAME.defaultBlockState()
                                .setValue(EndPortalFrameBlock.FACING, side.getOpposite())
                                .setValue(EndPortalFrameBlock.HAS_EYE, false));
            }
        }
        // Silverfish spawner opposite the dais, like the vanilla room.
        BlockPos spawnerPos = new BlockPos(center.getX() - 4, floorY + 1, center.getZ());
        set(level, spawnerPos.getX(), spawnerPos.getY(), spawnerPos.getZ(), Blocks.SPAWNER.defaultBlockState());
        if (level.getBlockEntity(spawnerPos) instanceof SpawnerBlockEntity spawner) {
            spawner.setEntityId(EntityType.SILVERFISH, level.getRandom());
        }
        EclipseMod.LOGGER.info("Fallback stronghold portal room built at {} (12 frames, no eyes)",
                center.toShortString());
    }

    // --- shared helpers ---

    static void lootChest(ServerLevel level, BlockPos pos, Direction facing, ResourceKey<LootTable> lootTable) {
        set(level, pos.getX(), pos.getY(), pos.getZ(),
                Blocks.CHEST.defaultBlockState().setValue(HorizontalDirectionalBlock.FACING, facing));
        if (level.getBlockEntity(pos) instanceof RandomizableContainerBlockEntity chest) {
            chest.setLootTable(lootTable, DiscMapData.ECLIPSE_SEED ^ pos.asLong());
        }
    }

    private static BlockState mossyMix(int x, int y, int z) {
        return hash01(x, y, z) < 0.55D
                ? Blocks.MOSSY_COBBLESTONE.defaultBlockState()
                : Blocks.COBBLESTONE.defaultBlockState();
    }

    private static BlockState crackedMix(int x, int y, int z) {
        return hash01(x, y, z) < 0.2D
                ? Blocks.CRACKED_STONE_BRICKS.defaultBlockState()
                : Blocks.STONE_BRICKS.defaultBlockState();
    }

    static double hash01(int x, int y, int z) {
        long h = DiscMapData.ECLIPSE_SEED ^ (x * 341873128712L + y * 986534123L + z * 132897987541L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h >>> 11) & 0xFFFFF) / (double) 0x100000;
    }

    static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_ALL);
    }
}
