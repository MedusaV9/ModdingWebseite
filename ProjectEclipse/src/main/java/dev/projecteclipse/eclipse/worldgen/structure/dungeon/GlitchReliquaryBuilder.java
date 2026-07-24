package dev.projecteclipse.eclipse.worldgen.structure.dungeon;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.AmethystClusterBlock;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.MultifaceBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.storage.loot.LootTable;

/**
 * The <b>Glitch Reliquary</b> — plans_v5 B12 custom dungeon #4: a deep, corrupted vault
 * on the stage-5 annulus. Distinct theme from the other three dungeons: a single square
 * deepslate-tile shrine whose fabric is "glitching" — hash-corrupted wall blocks (crying
 * obsidian, amethyst, sculk, blackstone), stray blocks floating loose in the chamber
 * air, and a caged lodestone pedestal holding the relic chest at the center.
 *
 * <p>Fully self-carving; callers relight via {@code SitePrep.finishBounds(...)} on the
 * returned bounds. Spawner mobs come from {@code config/eclipse/dungeons.json} (key
 * {@link DungeonSpawners#GLITCH_RELIQUARY} — the glitched family with vanilla
 * endermite/silverfish fallback); loot is {@code eclipse:dungeon/glitch_reliquary}
 * (glitch/umbral shards + custom items). Every roll is hashed from the frozen map seed —
 * the same save always builds the same reliquary.</p>
 */
public final class GlitchReliquaryBuilder {
    /** Loot table of every Glitch Reliquary chest. */
    public static final ResourceKey<LootTable> LOOT = ResourceKey.create(Registries.LOOT_TABLE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "dungeon/glitch_reliquary"));

    private GlitchReliquaryBuilder() {}

    /**
     * Builds the reliquary around {@code center} (vault floor midpoint, typically deep —
     * y ≈ −30…−18). Returns the disturbed bounds for relight/resend.
     */
    public static BoundingBox build(ServerLevel level, BlockPos center) {
        int x = center.getX();
        int y = center.getY();
        int z = center.getZ();

        vaultShell(level, x, y, z);
        reliquaryCore(level, x, y, z);
        glitchFloaters(level, x, y, z);
        // Guardian spawners in opposite corners; hidden second chest recessed in the
        // north wall (its niche block was carved by the shell pass).
        DungeonSpawners.applyTo(level, new BlockPos(x - 3, y, z - 3), DungeonSpawners.GLITCH_RELIQUARY, 0);
        DungeonSpawners.applyTo(level, new BlockPos(x + 3, y, z + 3), DungeonSpawners.GLITCH_RELIQUARY, 1);
        set(level, x, y - 1, z - 5, Blocks.POLISHED_BLACKSTONE.defaultBlockState());
        set(level, x, y, z - 5, Blocks.CAVE_AIR.defaultBlockState());
        lootChest(level, new BlockPos(x, y, z - 5), Direction.SOUTH);

        BoundingBox bounds = new BoundingBox(x - 6, y - 2, z - 6, x + 6, y + 6, z + 6);
        EclipseMod.LOGGER.info("Glitch Reliquary built at {} (bounds {})", center.toShortString(), bounds);
        return bounds;
    }

    // --- pieces ---

    /** Square vault: interior 9×9, air y..y+4, hash-corrupted deepslate-tile shell. */
    private static void vaultShell(ServerLevel level, int x, int y, int z) {
        for (int dx = -5; dx <= 5; dx++) {
            for (int dz = -5; dz <= 5; dz++) {
                boolean wall = Math.abs(dx) == 5 || Math.abs(dz) == 5;
                set(level, x + dx, y - 1, z + dz, corruptMix(x + dx, y - 1, z + dz));
                for (int dy = 0; dy <= 5; dy++) {
                    BlockState state = wall || dy == 5
                            ? corruptMix(x + dx, y + dy, z + dz)
                            : Blocks.CAVE_AIR.defaultBlockState();
                    set(level, x + dx, y + dy, z + dz, state);
                }
            }
        }
        // Soul lanterns flank the dais approach — the only steady light in the glitch.
        set(level, x - 2, y, z + 3, Blocks.SOUL_LANTERN.defaultBlockState());
        set(level, x + 2, y, z + 3, Blocks.SOUL_LANTERN.defaultBlockState());
        // Sculk creep across the floor edges.
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                if (Math.max(Math.abs(dx), Math.abs(dz)) >= 3
                        && hash01(x + dx, y - 1, z + dz) < 0.18D) {
                    set(level, x + dx, y - 1, z + dz, Blocks.SCULK.defaultBlockState());
                }
            }
        }
    }

    /** Caged obsidian dais: lodestone pedestal, relic chest, amethyst crown, bar cage. */
    private static void reliquaryCore(ServerLevel level, int x, int y, int z) {
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                set(level, x + dx, y, z + dz, Blocks.OBSIDIAN.defaultBlockState());
            }
        }
        set(level, x, y + 1, z, Blocks.LODESTONE.defaultBlockState());
        lootChest(level, new BlockPos(x, y + 2, z), Direction.SOUTH);
        // Amethyst crown on the dais corners.
        for (int dx = -1; dx <= 1; dx += 2) {
            for (int dz = -1; dz <= 1; dz += 2) {
                set(level, x + dx, y + 1, z + dz, Blocks.AMETHYST_CLUSTER.defaultBlockState()
                        .setValue(AmethystClusterBlock.FACING, Direction.UP));
            }
        }
        // Iron-bar cage at radius 2, one gap on the south face (the lantern approach).
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                if (Math.max(Math.abs(dx), Math.abs(dz)) != 2 || (dx == 0 && dz == 2)) {
                    continue;
                }
                for (int dy = 1; dy <= 3; dy++) {
                    set(level, x + dx, y + dy, z + dz, Blocks.IRON_BARS.defaultBlockState());
                }
            }
        }
    }

    /** Stray "glitched-loose" blocks hanging in the chamber air + sculk vein flickers. */
    private static void glitchFloaters(ServerLevel level, int x, int y, int z) {
        for (int i = 0; i < 6; i++) {
            int fx = x - 3 + (int) (hash01(x + i, y, z) * 7.0D);
            int fz = z - 3 + (int) (hash01(x, y + i, z) * 7.0D);
            int fy = y + 2 + (int) (hash01(x, y, z + i) * 3.0D);
            if (Math.max(Math.abs(fx - x), Math.abs(fz - z)) <= 2) {
                continue; // keep the cage volume clear
            }
            double pick = hash01(fx, fy ^ 41, fz);
            set(level, fx, fy, fz, pick < 0.4D
                    ? Blocks.CRYING_OBSIDIAN.defaultBlockState()
                    : pick < 0.7D ? Blocks.AMETHYST_BLOCK.defaultBlockState()
                            : Blocks.POLISHED_BLACKSTONE.defaultBlockState());
            if (pick > 0.85D) {
                set(level, fx, fy - 1, fz, Blocks.SCULK_VEIN.defaultBlockState()
                        .setValue(MultifaceBlock.getFaceProperty(Direction.UP), true));
            }
        }
    }

    // --- helpers ---

    /** The corrupted shell mix: deepslate tiles glitching into foreign matter. */
    private static BlockState corruptMix(int x, int y, int z) {
        double roll = hash01(x, y ^ 29, z);
        if (roll < 0.06D) {
            return Blocks.CRYING_OBSIDIAN.defaultBlockState();
        }
        if (roll < 0.10D) {
            return Blocks.AMETHYST_BLOCK.defaultBlockState();
        }
        if (roll < 0.14D) {
            return Blocks.SCULK.defaultBlockState();
        }
        if (roll < 0.22D) {
            return Blocks.POLISHED_BLACKSTONE.defaultBlockState();
        }
        return roll < 0.40D ? Blocks.CRACKED_DEEPSLATE_TILES.defaultBlockState()
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
