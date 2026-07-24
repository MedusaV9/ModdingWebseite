package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.boss.enderdragon.EndCrystal;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.loot.LootTable;
import net.minecraft.world.phys.AABB;

/**
 * Entity and structure-side companions to {@link EndDiscGeometry}'s pure spire blocks.
 * The geometry owns obsidian/cages so chunk generation and live materialization match;
 * this class owns real crystal entities and two deterministic, budget-writeable purpur
 * mini-cities (one tower above the disc, one hanging below it).
 */
public final class EndSpires {
    private static final String CRYSTAL_MARKER = "eclipseEndDiscCrystal";
    private static final String FALLBACK_LOOT = "eclipse:end_city/cache";

    /** One idempotent mini-city block operation. */
    public record BlockWrite(BlockPos pos, BlockState state, boolean lootChest) {}

    private EndSpires() {}

    /** Crystal bases in pillar-index order. */
    public static List<BlockPos> crystalPositions(int count) {
        int bounded = Math.max(0, Math.min(count, EndDiscGeometry.PILLAR_COUNT));
        List<BlockPos> positions = new ArrayList<>(bounded);
        for (int i = 0; i < bounded; i++) {
            positions.add(new BlockPos(
                    EndDiscGeometry.pillarX(i),
                    EndDiscGeometry.pillarTopY(i) + 1,
                    EndDiscGeometry.pillarZ(i)));
        }
        return List.copyOf(positions);
    }

    /**
     * Initial crystal pass. It is safe to resume after any individual spawn because each
     * UUID is persisted immediately. Call only before materialization is marked complete;
     * destroyed fight crystals are not silently recreated on restart.
     */
    public static List<EndCrystal> spawnInitialCrystals(
            ServerLevel level, EndFightState state, int desiredCount) {
        List<UUID> persisted = new ArrayList<>(state.crystalIds());
        List<EndCrystal> living = new ArrayList<>();
        List<BlockPos> positions = crystalPositions(desiredCount);

        for (int i = 0; i < positions.size(); i++) {
            BlockPos pos = positions.get(i);
            BudgetedBlockWriter.loadWithTicket(level, pos.getX() >> 4, pos.getZ() >> 4);
            EndCrystal crystal = existingAt(level, pos);
            if (crystal == null && i < persisted.size()) {
                var entity = level.getEntity(persisted.get(i));
                if (entity instanceof EndCrystal loaded && !loaded.isRemoved()) {
                    crystal = loaded;
                }
            }
            if (crystal == null) {
                crystal = new EndCrystal(level, pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D);
                crystal.setShowBottom(false);
                crystal.getPersistentData().putBoolean(CRYSTAL_MARKER, true);
                level.addFreshEntity(crystal);
            }
            crystal.setBeamTarget(null);
            living.add(crystal);
            if (i < persisted.size()) {
                persisted.set(i, crystal.getUUID());
            } else {
                persisted.add(crystal.getUUID());
            }
            state.setCrystals(persisted, living.size());
        }
        return List.copyOf(living);
    }

    /** Returns currently loaded, surviving crystals from the persisted fight set. */
    public static List<EndCrystal> livingCrystals(ServerLevel level, EndFightState state) {
        List<EndCrystal> living = new ArrayList<>();
        for (UUID id : state.crystalIds()) {
            var entity = level.getEntity(id);
            if (entity instanceof EndCrystal crystal && !crystal.isRemoved()) {
                living.add(crystal);
            }
        }
        state.setCrystals(state.crystalIds(), living.size());
        return List.copyOf(living);
    }

    /**
     * Optional non-default ritual behavior. Missing saved crystals are recreated only
     * when {@code crystalRespawn=true}; the default one-shot fight never calls this path.
     */
    public static List<EndCrystal> respawnMissingCrystals(
            ServerLevel level, EndFightState state, int desiredCount) {
        List<EndCrystal> living = livingCrystals(level, state);
        if (living.size() >= desiredCount) {
            return living;
        }
        List<UUID> ids = new ArrayList<>();
        List<EndCrystal> rebuilt = new ArrayList<>();
        for (BlockPos pos : crystalPositions(desiredCount)) {
            EndCrystal crystal = existingAt(level, pos);
            if (crystal == null) {
                crystal = new EndCrystal(level, pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D);
                crystal.setShowBottom(false);
                crystal.getPersistentData().putBoolean(CRYSTAL_MARKER, true);
                level.addFreshEntity(crystal);
            }
            ids.add(crystal.getUUID());
            rebuilt.add(crystal);
        }
        state.setCrystals(ids, rebuilt.size());
        return List.copyOf(rebuilt);
    }

    private static EndCrystal existingAt(ServerLevel level, BlockPos pos) {
        List<EndCrystal> found = level.getEntitiesOfClass(
                EndCrystal.class, new AABB(pos).inflate(1.75D),
                crystal -> !crystal.isRemoved()
                        && crystal.getPersistentData().getBoolean(CRYSTAL_MARKER));
        return found.isEmpty() ? null : found.get(0);
    }

    /**
     * Deterministic operations for two compact End-city silhouettes. The returned order
     * is stable and therefore safe to address with {@code EndFightState}'s persisted cursor.
     */
    public static List<BlockWrite> miniCityWrites() {
        List<BlockWrite> writes = new ArrayList<>();
        addUpperTower(writes, -68, 18);
        addHangingTower(writes, 58, -50);
        return List.copyOf(writes);
    }

    /** Applies one operation; chest loot switches tables with {@code allowElytra}. */
    public static void placeMiniCityWrite(
            ServerLevel level, BlockWrite write, EndConfig.Snapshot config) {
        level.setBlock(write.pos(), write.state(), Block.UPDATE_ALL);
        if (!write.lootChest()) {
            return;
        }
        if (level.getBlockEntity(write.pos()) instanceof RandomizableContainerBlockEntity chest) {
            String configured = config.allowElytra() ? config.elytraLootTable() : config.lootTable();
            ResourceLocation id = ResourceLocation.tryParse(configured);
            if (id == null) {
                EclipseMod.LOGGER.warn("Invalid End-city loot table '{}'; using {}", configured, FALLBACK_LOOT);
                id = ResourceLocation.parse(FALLBACK_LOOT);
            }
            ResourceKey<LootTable> table = ResourceKey.create(Registries.LOOT_TABLE, id);
            chest.setLootTable(table, FrozenParams.mapSeed() ^ write.pos().asLong());
        }
    }

    private static void addUpperTower(List<BlockWrite> out, int cx, int cz) {
        int ground = EndDiscGeometry.surfaceYAt(cx, cz);
        int base = ground + 1;
        // Five-sided-looking stepped landing around a narrow purpur tower.
        for (int dx = -6; dx <= 6; dx++) {
            for (int dz = -6; dz <= 6; dz++) {
                if (dx * dx + dz * dz <= 38) {
                    add(out, cx + dx, base, cz + dz, Blocks.END_STONE_BRICKS);
                }
            }
        }
        for (int y = 1; y <= 20; y++) {
            for (int dx = -4; dx <= 4; dx++) {
                for (int dz = -4; dz <= 4; dz++) {
                    boolean wall = Math.abs(dx) == 4 || Math.abs(dz) == 4;
                    boolean floor = y == 1 || y == 7 || y == 13 || y == 20;
                    boolean doorway = dz == 4 && Math.abs(dx) <= 1 && y <= 3;
                    if ((wall && !doorway) || floor) {
                        Block block = (Math.abs(dx) == 4 && Math.abs(dz) == 4)
                                ? Blocks.PURPUR_PILLAR : Blocks.PURPUR_BLOCK;
                        add(out, cx + dx, base + y, cz + dz, block);
                    }
                }
            }
        }
        for (int dx = -5; dx <= 5; dx++) {
            for (int dz = -5; dz <= 5; dz++) {
                if (Math.max(Math.abs(dx), Math.abs(dz)) == 5) {
                    add(out, cx + dx, base + 21, cz + dz, Blocks.PURPUR_SLAB);
                }
            }
        }
        add(out, cx, base + 14, cz, Blocks.CHEST, true);
        add(out, cx - 5, base + 22, cz, Blocks.END_ROD);
        add(out, cx + 5, base + 22, cz, Blocks.END_ROD);
        add(out, cx, base + 22, cz - 5, Blocks.END_ROD);
        add(out, cx, base + 22, cz + 5, Blocks.END_ROD);
    }

    private static void addHangingTower(List<BlockWrite> out, int cx, int cz) {
        int surface = EndDiscGeometry.surfaceYAt(cx, cz);
        // Surface cap and four chains/pillars announce the room hanging below the lens.
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                if (dx * dx + dz * dz <= 18) {
                    add(out, cx + dx, surface + 1, cz + dz, Blocks.PURPUR_BLOCK);
                }
            }
        }
        for (int y = surface; y >= surface - 25; y--) {
            add(out, cx - 3, y, cz - 3, Blocks.PURPUR_PILLAR);
            add(out, cx - 3, y, cz + 3, Blocks.PURPUR_PILLAR);
            add(out, cx + 3, y, cz - 3, Blocks.PURPUR_PILLAR);
            add(out, cx + 3, y, cz + 3, Blocks.PURPUR_PILLAR);
        }
        int roomFloor = surface - 27;
        for (int y = 0; y <= 8; y++) {
            for (int dx = -5; dx <= 5; dx++) {
                for (int dz = -5; dz <= 5; dz++) {
                    boolean shell = y == 0 || y == 8 || Math.abs(dx) == 5 || Math.abs(dz) == 5;
                    if (shell) {
                        Block block = (Math.abs(dx) == 5 && Math.abs(dz) == 5)
                                ? Blocks.PURPUR_PILLAR : Blocks.PURPUR_BLOCK;
                        add(out, cx + dx, roomFloor + y, cz + dz, block);
                    }
                }
            }
        }
        add(out, cx, roomFloor + 1, cz, Blocks.CHEST, true);
        add(out, cx - 3, roomFloor - 1, cz - 3, Blocks.END_ROD);
        add(out, cx + 3, roomFloor - 1, cz - 3, Blocks.END_ROD);
        add(out, cx - 3, roomFloor - 1, cz + 3, Blocks.END_ROD);
        add(out, cx + 3, roomFloor - 1, cz + 3, Blocks.END_ROD);
    }

    private static void add(List<BlockWrite> out, int x, int y, int z, Block block) {
        add(out, x, y, z, block, false);
    }

    private static void add(
            List<BlockWrite> out, int x, int y, int z, Block block, boolean lootChest) {
        out.add(new BlockWrite(new BlockPos(x, y, z), block.defaultBlockState(), lootChest));
    }
}
