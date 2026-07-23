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
import net.minecraft.world.level.block.MultifaceBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.storage.loot.LootTable;

/**
 * The <b>Umbral Warrens</b> — custom dungeon #2 of design D7: a cave-web warren burrowed
 * into the deep-dark region under the giant mountain's flank. Fully self-carving (no
 * SitePrep envelope needed): a big irregular nest cavern webbed with sculk and cobwebs,
 * five winding radial burrows ending in egg-pod nests, and one steep chute that climbs
 * toward the cave band above so the warren connects to the mountain's cave network.
 *
 * <p>Spawner mobs come from {@code config/eclipse/dungeons.json} (key
 * {@link DungeonSpawners#UMBRAL_WARRENS} — P6 seam, vanilla cave-spider/zombie fallback);
 * loot is {@code eclipse:dungeon/umbral_warrens}. Every roll is hashed from the frozen
 * map seed: the same save always digs the same warren. Callers relight via
 * {@code SitePrep.finishBounds(...)} on the returned bounds.</p>
 */
public final class UmbralWarrensBuilder {
    /** Loot table of every Umbral Warrens chest. */
    public static final ResourceKey<LootTable> LOOT = ResourceKey.create(Registries.LOOT_TABLE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "dungeon/umbral_warrens"));

    /** Radial burrows leaving the nest cavern. */
    private static final int BURROWS = 5;

    private UmbralWarrensBuilder() {}

    /**
     * Digs the warren around {@code center} (nest-cavern midpoint, typically y ≈ −106
     * inside the deep-dark band under the mountain flank, see {@code CaveBiomeMap}).
     * Returns the disturbed bounds for relight/resend.
     */
    public static BoundingBox build(ServerLevel level, BlockPos center) {
        int cx = center.getX();
        int cy = center.getY();
        int cz = center.getZ();
        int minX = cx;
        int maxX = cx;
        int minZ = cz;
        int maxZ = cz;
        int minY = cy;
        int maxY = cy;

        // Nest cavern: an irregular flattened sphere (r≈8 XZ, r≈5 Y), rim modulated by
        // hash so it reads as a dug burrow, not a perfect ball.
        nestCavern(level, cx, cy, cz, 8, 5);

        // Radial burrows: winding r≈2 tubes to egg pods; alternating spawner/chest pods.
        for (int b = 0; b < BURROWS; b++) {
            double angle = (b + hash01(cx, cy + b, cz) * 0.5D) * (Math.PI * 2.0D / BURROWS);
            int length = 18 + (int) (hash01(cx + b, cy, cz) * 10.0D);
            int px = cx;
            int py = cy;
            int pz = cz;
            for (int i = 6; i <= length; i++) {
                double wobble = Math.sin(i * 0.35D + b * 1.7D) * 2.2D;
                px = cx + (int) Math.round(Math.cos(angle) * i - Math.sin(angle) * wobble);
                pz = cz + (int) Math.round(Math.sin(angle) * i + Math.cos(angle) * wobble);
                py = cy + (int) Math.round(Math.sin(i * 0.22D + b) * 1.5D);
                carveBlob(level, px, py, pz, 2.4D);
                if (hash01(px, py, pz) < 0.10D) {
                    set(level, px, py + 2, pz, Blocks.COBWEB.defaultBlockState());
                }
            }
            podNest(level, px, py, pz, b);
            minX = Math.min(minX, px - 5);
            maxX = Math.max(maxX, px + 5);
            minZ = Math.min(minZ, pz - 5);
            maxZ = Math.max(maxZ, pz + 5);
            minY = Math.min(minY, py - 4);
            maxY = Math.max(maxY, py + 4);
        }

        // Escape chute: a steep webbed climb from the nest roof up toward the cave band
        // above the deep-dark ceiling (y ≈ −66) so the warren ties into the mountain
        // root's cave network without poking into the Ancient City envelope higher up.
        int chuteTop = cy + 5;
        int steps = Math.max(8, Math.min(44, -66 - cy));
        double chuteAngle = hash01(cx, cy, cz) * Math.PI * 2.0D;
        for (int i = 0; i <= steps; i++) {
            int px = cx + (int) Math.round(Math.cos(chuteAngle) * i * 0.8D);
            int pz = cz + (int) Math.round(Math.sin(chuteAngle) * i * 0.8D);
            int py = cy + 4 + i;
            carveBlob(level, px, py, pz, 2.0D);
            if (i % 3 == 0) {
                set(level, px, py, pz, Blocks.COBWEB.defaultBlockState());
            }
            chuteTop = py;
            minX = Math.min(minX, px - 4);
            maxX = Math.max(maxX, px + 4);
            minZ = Math.min(minZ, pz - 4);
            maxZ = Math.max(maxZ, pz + 4);
        }
        maxY = Math.max(maxY, chuteTop + 3);

        // Nest décor AFTER all carving: sculk skin, webs, the two nest spawners, chests.
        dressNest(level, cx, cy, cz, 8, 5);

        minX = Math.min(minX, cx - 10);
        maxX = Math.max(maxX, cx + 10);
        minZ = Math.min(minZ, cz - 10);
        maxZ = Math.max(maxZ, cz + 10);
        minY = Math.min(minY, cy - 7);
        BoundingBox bounds = new BoundingBox(minX, minY, minZ, maxX, maxY, maxZ);
        EclipseMod.LOGGER.info("Umbral Warrens dug at {} (bounds {})", center.toShortString(), bounds);
        return bounds;
    }

    // --- pieces ---

    /** Carves the flattened, hash-rimmed nest sphere. */
    private static void nestCavern(ServerLevel level, int cx, int cy, int cz, int rXz, int rY) {
        for (int dx = -rXz; dx <= rXz; dx++) {
            for (int dz = -rXz; dz <= rXz; dz++) {
                for (int dy = -rY; dy <= rY; dy++) {
                    double d = (dx * dx + dz * dz) / (double) (rXz * rXz)
                            + (dy * dy) / (double) (rY * rY);
                    double rim = 0.85D + hash01(cx + dx, cy + dy, cz + dz) * 0.3D;
                    if (d <= rim) {
                        set(level, cx + dx, cy + dy, cz + dz, Blocks.CAVE_AIR.defaultBlockState());
                    }
                }
            }
        }
    }

    /**
     * Post-carve nest dressing: deepslate/sculk floor skin, sculk veins on the rim,
     * cobweb curtain, two config spawners flanking the egg cluster and two loot chests.
     */
    private static void dressNest(ServerLevel level, int cx, int cy, int cz, int rXz, int rY) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -rXz - 1; dx <= rXz + 1; dx++) {
            for (int dz = -rXz - 1; dz <= rXz + 1; dz++) {
                for (int dy = -rY - 1; dy <= rY + 1; dy++) {
                    cursor.set(cx + dx, cy + dy, cz + dz);
                    if (!level.getBlockState(cursor).isAir()) {
                        continue;
                    }
                    BlockPos below = cursor.below();
                    if (level.getBlockState(below).isSolidRender(level, below)) {
                        double roll = hash01(cx + dx, cy + dy, cz + dz);
                        if (dy <= -rY + 2 && roll < 0.45D) {
                            // Sculk floor skin on the cavern bottom.
                            set(level, below.getX(), below.getY(), below.getZ(),
                                    Blocks.SCULK.defaultBlockState());
                        } else if (roll < 0.10D) {
                            set(level, cursor.getX(), cursor.getY(), cursor.getZ(),
                                    Blocks.SCULK_VEIN.defaultBlockState()
                                            .setValue(MultifaceBlock.getFaceProperty(Direction.DOWN), true));
                        } else if (roll > 0.93D) {
                            set(level, cursor.getX(), cursor.getY(), cursor.getZ(),
                                    Blocks.COBWEB.defaultBlockState());
                        }
                    }
                }
            }
        }
        // Egg cluster: a calcite knot on a sculk pedestal marks the warren heart.
        int floorY = cy - rY + 1;
        set(level, cx, floorY - 1, cz, Blocks.SCULK.defaultBlockState());
        set(level, cx, floorY, cz, Blocks.CALCITE.defaultBlockState());
        set(level, cx + 1, floorY, cz, Blocks.CALCITE.defaultBlockState());
        set(level, cx, floorY, cz + 1, Blocks.CALCITE.defaultBlockState());
        set(level, cx, floorY + 1, cz, Blocks.SCULK_CATALYST.defaultBlockState());
        // Flanking spawners + hoard chests (indexes 0/1 rotate through config ids).
        floorPad(level, cx - 3, floorY - 1, cz - 3);
        DungeonSpawners.applyTo(level, new BlockPos(cx - 3, floorY, cz - 3),
                DungeonSpawners.UMBRAL_WARRENS, 0);
        floorPad(level, cx + 3, floorY - 1, cz + 3);
        DungeonSpawners.applyTo(level, new BlockPos(cx + 3, floorY, cz + 3),
                DungeonSpawners.UMBRAL_WARRENS, 1);
        floorPad(level, cx + 4, floorY - 1, cz - 4);
        lootChest(level, new BlockPos(cx + 4, floorY, cz - 4));
        floorPad(level, cx - 4, floorY - 1, cz + 4);
        lootChest(level, new BlockPos(cx - 4, floorY, cz + 4));
        // Soul lantern on the calcite knot so the heart glimmers in the deep dark.
        set(level, cx + 1, floorY + 1, cz, Blocks.SOUL_LANTERN.defaultBlockState());
    }

    /** One egg-pod burrow end: webbed bulb with a spawner (even) or hoard chest (odd). */
    private static void podNest(ServerLevel level, int px, int py, int pz, int index) {
        carveBlob(level, px, py, pz, 3.4D);
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                if (hash01(px + dx, py, pz + dz) < 0.4D) {
                    set(level, px + dx, py + 2, pz + dz, Blocks.COBWEB.defaultBlockState());
                }
            }
        }
        floorPad(level, px, py - 1, pz);
        if (index % 2 == 0) {
            DungeonSpawners.applyTo(level, new BlockPos(px, py, pz),
                    DungeonSpawners.UMBRAL_WARRENS, 2 + index);
        } else {
            lootChest(level, new BlockPos(px, py, pz));
        }
    }

    /** Carves one roughly spherical blob of cave air. */
    private static void carveBlob(ServerLevel level, int cx, int cy, int cz, double radius) {
        int r = (int) Math.ceil(radius);
        double r2 = radius * radius;
        for (int dx = -r; dx <= r; dx++) {
            for (int dy = -r; dy <= r; dy++) {
                for (int dz = -r; dz <= r; dz++) {
                    if (dx * dx + dy * dy * 1.4D + dz * dz <= r2) {
                        set(level, cx + dx, cy + dy, cz + dz, Blocks.CAVE_AIR.defaultBlockState());
                    }
                }
            }
        }
    }

    /** Guarantees a solid deepslate footing under a spawner/chest position. */
    private static void floorPad(ServerLevel level, int x, int y, int z) {
        BlockPos pos = new BlockPos(x, y, z);
        if (!level.getBlockState(pos).isSolidRender(level, pos)) {
            set(level, x, y, z, Blocks.COBBLED_DEEPSLATE.defaultBlockState());
        }
    }

    private static void lootChest(ServerLevel level, BlockPos pos) {
        set(level, pos.getX(), pos.getY(), pos.getZ(), Blocks.CHEST.defaultBlockState());
        if (level.getBlockEntity(pos) instanceof
                net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity chest) {
            chest.setLootTable(LOOT, FrozenParams.mapSeed() ^ pos.asLong());
        }
    }

    static double hash01(int x, int y, int z) {
        long h = FrozenParams.mapSeed() ^ (x * 341873128712L + y * 986534123L + z * 132897987541L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h >>> 11) & 0xFFFFF) / (double) 0x100000;
    }

    static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.setBlock(new BlockPos(x, y, z),
                state, net.minecraft.world.level.block.Block.UPDATE_CLIENTS
                        | net.minecraft.world.level.block.Block.UPDATE_KNOWN_SHAPE);
    }
}
