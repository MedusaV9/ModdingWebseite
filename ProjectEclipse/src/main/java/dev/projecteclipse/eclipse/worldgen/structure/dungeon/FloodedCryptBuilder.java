package dev.projecteclipse.eclipse.worldgen.structure.dungeon;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.storage.loot.LootTable;

/**
 * The <b>Flooded Crypt</b> — plans_v5 B12 custom dungeon #3: a waterlogged burial nave
 * buried in the stage-4 annulus. Distinct theme from the Collapsed Vault (dry stone
 * keep) and Umbral Warrens (sculk burrow): a drowned chapel — stone-brick nave over a
 * standing water pool lit by sea lanterns under the surface, mud-brick burial alcoves
 * with skeleton skulls along both walls, a prismarine-columned apse holding the hoard,
 * and a silted antechamber whose far exit has collapsed into gravel.
 *
 * <p>Fully self-carving (no SitePrep terraform); callers relight via
 * {@code SitePrep.finishBounds(...)} on the returned bounds. Spawner mobs come from
 * {@code config/eclipse/dungeons.json} (key {@link DungeonSpawners#FLOODED_CRYPT} —
 * drowned-family fallback); loot is {@code eclipse:dungeon/flooded_crypt} (custom items
 * + umbral shards). Every roll is hashed from the frozen map seed — the same save always
 * builds the same crypt.</p>
 */
public final class FloodedCryptBuilder {
    /** Loot table of every Flooded Crypt chest. */
    public static final ResourceKey<LootTable> LOOT = ResourceKey.create(Registries.LOOT_TABLE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "dungeon/flooded_crypt"));

    private FloodedCryptBuilder() {}

    /**
     * Builds the crypt around {@code center} (nave floor midpoint, typically y ≈ −14…−4).
     * Returns the disturbed bounds for relight/resend.
     */
    public static BoundingBox build(ServerLevel level, BlockPos center) {
        int x = center.getX();
        int y = center.getY();
        int z = center.getZ();

        // Shells first (CollapsedVaultBuilder discipline: shells → openings → décor).
        naveShell(level, x, y, z);
        antechamberShell(level, x, y, z);
        apseShell(level, x, y, z);
        // Openings: antechamber → nave, nave → apse.
        for (int dy = 0; dy <= 1; dy++) {
            set(level, x - 6, y + dy, z, Blocks.CAVE_AIR.defaultBlockState());
            set(level, x + 6, y + dy, z, Blocks.CAVE_AIR.defaultBlockState());
        }
        // Collapsed far exit: the west face of the antechamber is a gravel slump.
        for (int dz = -1; dz <= 1; dz++) {
            set(level, x - 10, y, z + dz, Blocks.GRAVEL.defaultBlockState());
            set(level, x - 10, y + 1, z + dz, Blocks.GRAVEL.defaultBlockState());
            set(level, x - 9, y, z + dz, Blocks.GRAVEL.defaultBlockState());
        }
        // Décor + hazards last.
        pool(level, x, y, z);
        alcoves(level, x, y, z);
        dressNave(level, x, y, z);
        // Apse hoard: pedestal chest + guarding spawner; second spawner in the silt room.
        set(level, x + 7, y, z, Blocks.POLISHED_DEEPSLATE.defaultBlockState());
        lootChest(level, new BlockPos(x + 7, y + 1, z), Direction.WEST);
        DungeonSpawners.applyTo(level, new BlockPos(x + 8, y, z + 1), DungeonSpawners.FLOODED_CRYPT, 0);
        DungeonSpawners.applyTo(level, new BlockPos(x - 8, y, z), DungeonSpawners.FLOODED_CRYPT, 1);

        BoundingBox bounds = new BoundingBox(x - 11, y - 3, z - 6, x + 9, y + 5, z + 6);
        EclipseMod.LOGGER.info("Flooded Crypt built at {} (bounds {})", center.toShortString(), bounds);
        return bounds;
    }

    // --- shells ---

    /** Nave: interior 11×7, air y..y+3, mixed stone-brick shell, tiled double floor. */
    private static void naveShell(ServerLevel level, int x, int y, int z) {
        for (int dx = -6; dx <= 6; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                boolean wall = Math.abs(dx) == 6 || Math.abs(dz) == 4;
                set(level, x + dx, y - 2, z + dz, Blocks.DEEPSLATE_BRICKS.defaultBlockState());
                set(level, x + dx, y - 1, z + dz, tileMix(x + dx, y - 1, z + dz));
                for (int dy = 0; dy <= 4; dy++) {
                    BlockState state = wall || dy == 4
                            ? brickMix(x + dx, y + dy, z + dz)
                            : Blocks.CAVE_AIR.defaultBlockState();
                    set(level, x + dx, y + dy, z + dz, state);
                }
            }
        }
        // Prismarine corner columns — the drowned-chapel signature.
        for (int cx : new int[] {x - 5, x + 5}) {
            for (int cz : new int[] {z - 3, z + 3}) {
                for (int dy = 0; dy <= 3; dy++) {
                    set(level, cx, y + dy, cz, Blocks.PRISMARINE_BRICKS.defaultBlockState());
                }
            }
        }
    }

    /** Antechamber west of the nave (shares the nave's west wall): silt (mud) floor. */
    private static void antechamberShell(ServerLevel level, int x, int y, int z) {
        for (int dx = -10; dx <= -7; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                boolean wall = dx == -10 || Math.abs(dz) == 2;
                set(level, x + dx, y - 1, z + dz, Blocks.MUD.defaultBlockState());
                for (int dy = 0; dy <= 3; dy++) {
                    BlockState state = wall || dy == 3
                            ? brickMix(x + dx, y + dy, z + dz)
                            : Blocks.CAVE_AIR.defaultBlockState();
                    set(level, x + dx, y + dy, z + dz, state);
                }
            }
        }
    }

    /** Apse east of the nave (shares the nave's east wall): the hoard chamber. */
    private static void apseShell(ServerLevel level, int x, int y, int z) {
        for (int dx = 7; dx <= 9; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                boolean wall = dx == 9 || Math.abs(dz) == 2;
                set(level, x + dx, y - 1, z + dz, tileMix(x + dx, y - 1, z + dz));
                for (int dy = 0; dy <= 3; dy++) {
                    BlockState state = wall || dy == 3
                            ? brickMix(x + dx, y + dy, z + dz)
                            : Blocks.CAVE_AIR.defaultBlockState();
                    set(level, x + dx, y + dy, z + dz, state);
                }
            }
        }
    }

    // --- décor ---

    /** Central standing pool: recessed water over a sea-lantern-lit deepslate bed. */
    private static void pool(ServerLevel level, int x, int y, int z) {
        for (int dx = -3; dx <= 3; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                boolean lantern = (dx == -2 || dx == 2) && dz == 0;
                set(level, x + dx, y - 2, z + dz, lantern
                        ? Blocks.SEA_LANTERN.defaultBlockState()
                        : Blocks.DEEPSLATE_BRICKS.defaultBlockState());
                set(level, x + dx, y - 1, z + dz, Blocks.WATER.defaultBlockState());
            }
        }
    }

    /** Burial alcoves cut into both long walls: mud-brick beds, some with skulls. */
    private static void alcoves(ServerLevel level, int x, int y, int z) {
        for (int side = -1; side <= 1; side += 2) {
            for (int dx = -4; dx <= 4; dx += 2) {
                int ax = x + dx;
                int az = z + side * 4;
                set(level, ax, y - 1, az, Blocks.MUD_BRICKS.defaultBlockState());
                set(level, ax, y, az, Blocks.CAVE_AIR.defaultBlockState());
                set(level, ax, y + 1, az, Blocks.CAVE_AIR.defaultBlockState());
                set(level, ax, y + 2, az, Blocks.MUD_BRICKS.defaultBlockState());
                set(level, ax, y, az + side, Blocks.CHISELED_STONE_BRICKS.defaultBlockState());
                set(level, ax, y + 1, az + side, brickMix(ax, y + 1, az + side));
                double roll = hash01(ax, y, az);
                if (roll < 0.35D) {
                    set(level, ax, y, az, Blocks.SKELETON_SKULL.defaultBlockState());
                } else if (roll > 0.8D) {
                    set(level, ax, y + 1, az, Blocks.COBWEB.defaultBlockState());
                }
            }
        }
        // One alcove hides the second hoard chest (deterministic pick, east-south bed).
        set(level, x + 4, y - 1, z - 4, Blocks.MUD_BRICKS.defaultBlockState());
        lootChest(level, new BlockPos(x + 4, y, z - 4), Direction.SOUTH);
    }

    /** Wet dressing across the nave: drips, silt patches and hanging webs. */
    private static void dressNave(ServerLevel level, int x, int y, int z) {
        for (int dx = -5; dx <= 5; dx++) {
            for (int dz = -3; dz <= 3; dz++) {
                double roll = hash01(x + dx, y + 4, z + dz);
                if (roll < 0.06D) {
                    set(level, x + dx, y + 3, z + dz, Blocks.COBWEB.defaultBlockState());
                } else if (roll < 0.12D && Math.abs(dz) > 1) {
                    set(level, x + dx, y - 1, z + dz, Blocks.MUD.defaultBlockState());
                }
            }
        }
    }

    // --- helpers ---

    private static BlockState brickMix(int x, int y, int z) {
        double roll = hash01(x, y ^ 17, z);
        if (roll < 0.30D) {
            return Blocks.MOSSY_STONE_BRICKS.defaultBlockState();
        }
        return roll < 0.45D ? Blocks.CRACKED_STONE_BRICKS.defaultBlockState()
                : Blocks.STONE_BRICKS.defaultBlockState();
    }

    private static BlockState tileMix(int x, int y, int z) {
        return hash01(x, y ^ 23, z) < 0.3D
                ? Blocks.CRACKED_DEEPSLATE_TILES.defaultBlockState()
                : Blocks.DEEPSLATE_TILES.defaultBlockState();
    }

    private static void lootChest(ServerLevel level, BlockPos pos, Direction facing) {
        set(level, pos.getX(), pos.getY(), pos.getZ(),
                Blocks.CHEST.defaultBlockState().setValue(HorizontalDirectionalBlock.FACING, facing));
        if (level.getBlockEntity(pos) instanceof
                net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity chest) {
            chest.setLootTable(LOOT, FrozenParams.mapSeed() ^ pos.asLong());
        }
    }

    private static double hash01(int x, int y, int z) {
        long h = FrozenParams.mapSeed() ^ (x * 341873128712L + y * 986534123L + z * 132897987541L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h >>> 11) & 0xFFFFF) / (double) 0x100000;
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.setBlock(new BlockPos(x, y, z), state,
                net.minecraft.world.level.block.Block.UPDATE_CLIENTS
                        | net.minecraft.world.level.block.Block.UPDATE_KNOWN_SHAPE);
    }
}
