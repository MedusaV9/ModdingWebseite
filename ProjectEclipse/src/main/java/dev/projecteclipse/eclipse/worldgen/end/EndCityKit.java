package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.monster.Shulker;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.loot.LootTable;
import net.minecraft.world.phys.AABB;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * PLAN-C C13 §3: hand-authored end-city kits stamped on the shattered islets — two
 * purpur mini-towers and one end-ship silhouette, each carrying REAL loot
 * ({@code end.json}'s loot tables, elytra table on the ship when {@code allowElytra})
 * and live shulker guards. Deterministic setBlock builders (the {@code EndSpires}
 * mini-city school), registered as ONE {@link #STRUCTURE_ID} async placer that
 * branches on the site id; {@code EndShatterSequence} enqueues the three sites when
 * its carve pass completes, so the kits arrive through the standard pending-registry
 * rift reveals.
 *
 * <p>Writes drain through a small tick queue ({@value #WRITES_PER_TICK}/tick) so a
 * ~3k-block tower never spikes one tick; the pending row stays persisted until the
 * queue's completion callback fires (async-placer contract), making a shutdown
 * mid-build retry safely.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndCityKit {
    /** Structure id all three kit sites share (one placer, site-id branch). */
    public static final String STRUCTURE_ID = "eclipse:end_city_kit";
    public static final String SITE_TOWER_A = STRUCTURE_ID + "/tower_a";
    public static final String SITE_TOWER_B = STRUCTURE_ID + "/tower_b";
    public static final String SITE_SHIP = STRUCTURE_ID + "/ship";
    /** Command tag on every kit shulker (idempotent re-place sweeps by it). */
    public static final String ENTITY_TAG = "eclipse_end_city_kit";

    private static final int WRITES_PER_TICK = 600;
    private static final String FALLBACK_LOOT = "eclipse:end_city/cache";

    /** One pending write; {@code lootChest}/{@code elytraChest} pick the loot table. */
    private record Write(BlockPos pos, BlockState state, boolean lootChest, boolean elytraChest) {}

    /** One queued build drained by the tick handler. */
    private static final class Build {
        final ServerLevel level;
        final String siteId;
        final Deque<Write> writes;
        final List<BlockPos> shulkerPerches;
        final Runnable onComplete;
        final Consumer<Throwable> onFailure;

        Build(ServerLevel level, String siteId, Deque<Write> writes,
                List<BlockPos> shulkerPerches, Runnable onComplete, Consumer<Throwable> onFailure) {
            this.level = level;
            this.siteId = siteId;
            this.writes = writes;
            this.shulkerPerches = shulkerPerches;
            this.onComplete = onComplete;
            this.onFailure = onFailure;
        }
    }

    private static final Deque<Build> QUEUE = new ArrayDeque<>();

    private EndCityKit() {}

    // --- the AsyncSitePlacer (registered by EndShatterSequence's bootstrap) ---

    /** Authored writes + shulker perches for the site, queued for the tick drain. */
    public static void placeSite(ServerLevel level, PendingSite site, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        List<Write> writes = new ArrayList<>();
        List<BlockPos> perches = new ArrayList<>();
        BlockPos anchor = site.anchor();
        switch (site.siteId()) {
            case SITE_TOWER_A -> buildTowerA(writes, perches, anchor);
            case SITE_TOWER_B -> buildTowerB(writes, perches, anchor);
            case SITE_SHIP -> buildShip(writes, perches, anchor);
            default -> {
                onFailure.accept(new IllegalArgumentException(
                        "Unknown end-city kit site " + site.siteId()));
                return;
            }
        }
        // Idempotent retry: sweep this kit's shulkers before the fresh writes land.
        sweepShulkers(level, anchor, site.footprint());
        loadChunks(level, writes);
        QUEUE.addLast(new Build(level, site.siteId(), new ArrayDeque<>(writes), perches,
                onComplete, onFailure));
        EclipseMod.LOGGER.info("EndCityKit queued {} ({} writes, {} shulkers) at {}",
                site.siteId(), writes.size(), perches.size(), anchor.toShortString());
    }

    private static void loadChunks(ServerLevel level, List<Write> writes) {
        Set<Long> loaded = new HashSet<>();
        for (Write write : writes) {
            int chunkX = write.pos().getX() >> 4;
            int chunkZ = write.pos().getZ() >> 4;
            if (loaded.add(ChunkPos.asLong(chunkX, chunkZ))) {
                BudgetedBlockWriter.loadWithTicket(level, chunkX, chunkZ);
            }
        }
    }

    private static void sweepShulkers(ServerLevel level, BlockPos anchor, int footprint) {
        AABB bounds = new AABB(anchor).inflate(footprint, 40.0D, footprint);
        List<Entity> leftovers = level.getEntities((Entity) null, bounds,
                entity -> entity.getTags().contains(ENTITY_TAG));
        leftovers.forEach(Entity::discard);
    }

    // --- tick drain ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        Build build = QUEUE.peekFirst();
        if (build == null) {
            return;
        }
        try {
            int budget = WRITES_PER_TICK;
            while (budget-- > 0 && !build.writes.isEmpty()) {
                apply(build.level, build.writes.pollFirst());
            }
            if (build.writes.isEmpty()) {
                QUEUE.pollFirst();
                for (BlockPos perch : build.shulkerPerches) {
                    spawnShulker(build.level, perch);
                }
                EclipseMod.LOGGER.info("EndCityKit placed {}", build.siteId);
                build.onComplete.run();
            }
        } catch (Throwable error) {
            QUEUE.pollFirst();
            build.onFailure.accept(error);
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        QUEUE.clear();
    }

    /** One write; loot chests get their table + a position-salted deterministic seed. */
    private static void apply(ServerLevel level, Write write) {
        level.setBlock(write.pos(), write.state(), Block.UPDATE_ALL);
        if (!write.lootChest() && !write.elytraChest()) {
            return;
        }
        if (level.getBlockEntity(write.pos()) instanceof RandomizableContainerBlockEntity chest) {
            EndConfig.Snapshot config = EndConfig.current();
            String configured = write.elytraChest() && config.allowElytra()
                    ? config.elytraLootTable() : config.lootTable();
            ResourceLocation id = ResourceLocation.tryParse(configured);
            if (id == null) {
                EclipseMod.LOGGER.warn("Invalid End-city loot table '{}'; using {}",
                        configured, FALLBACK_LOOT);
                id = ResourceLocation.parse(FALLBACK_LOOT);
            }
            ResourceKey<LootTable> table = ResourceKey.create(Registries.LOOT_TABLE, id);
            chest.setLootTable(table, FrozenParams.mapSeed() ^ write.pos().asLong());
        }
    }

    private static void spawnShulker(ServerLevel level, BlockPos perch) {
        Shulker shulker = EntityType.SHULKER.create(level);
        if (shulker == null) {
            return;
        }
        shulker.moveTo(perch.getX() + 0.5D, perch.getY(), perch.getZ() + 0.5D, 0.0F, 0.0F);
        shulker.setPersistenceRequired();
        shulker.addTag(ENTITY_TAG);
        level.addFreshEntity(shulker);
    }

    // --- the deterministic builders (EndSpires mini-city school) ---

    /**
     * Tower A (largest islet): 9-radius stepped landing, a 7×7 four-storey purpur tower
     * with pillar corners and a south doorway, end-rod crown, loot chests on the second
     * and top floors, shulkers guarding both.
     */
    private static void buildTowerA(List<Write> out, List<BlockPos> perches, BlockPos anchor) {
        int cx = anchor.getX();
        int cz = anchor.getZ();
        int base = anchor.getY() + 1;
        for (int dx = -6; dx <= 6; dx++) {
            for (int dz = -6; dz <= 6; dz++) {
                if (dx * dx + dz * dz <= 38) {
                    add(out, cx + dx, base, cz + dz, Blocks.END_STONE_BRICKS);
                }
            }
        }
        for (int y = 1; y <= 22; y++) {
            for (int dx = -3; dx <= 3; dx++) {
                for (int dz = -3; dz <= 3; dz++) {
                    boolean wall = Math.abs(dx) == 3 || Math.abs(dz) == 3;
                    boolean floor = y == 1 || y == 8 || y == 15 || y == 22;
                    boolean doorway = dz == 3 && Math.abs(dx) <= 1 && y >= 2 && y <= 4;
                    if (doorway) {
                        add(out, cx + dx, base + y, cz + dz, Blocks.AIR);
                    } else if (wall || floor) {
                        Block block = (Math.abs(dx) == 3 && Math.abs(dz) == 3)
                                ? Blocks.PURPUR_PILLAR : Blocks.PURPUR_BLOCK;
                        add(out, cx + dx, base + y, cz + dz, block);
                    } else {
                        add(out, cx + dx, base + y, cz + dz, Blocks.AIR);
                    }
                }
            }
        }
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                if (Math.max(Math.abs(dx), Math.abs(dz)) == 4) {
                    add(out, cx + dx, base + 23, cz + dz, Blocks.PURPUR_SLAB);
                }
            }
        }
        add(out, cx - 4, base + 24, cz, Blocks.END_ROD);
        add(out, cx + 4, base + 24, cz, Blocks.END_ROD);
        add(out, cx, base + 24, cz - 4, Blocks.END_ROD);
        add(out, cx, base + 24, cz + 4, Blocks.END_ROD);
        addChest(out, cx, base + 9, cz);
        addChest(out, cx, base + 23, cz);
        perches.add(new BlockPos(cx - 2, base + 9, cz - 2));
        perches.add(new BlockPos(cx + 2, base + 16, cz + 2));
        perches.add(new BlockPos(cx, base + 23, cz + 2));
    }

    /** Tower B (second islet): compact 5×5 two-storey keep, one cache, two guards. */
    private static void buildTowerB(List<Write> out, List<BlockPos> perches, BlockPos anchor) {
        int cx = anchor.getX();
        int cz = anchor.getZ();
        int base = anchor.getY() + 1;
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                if (dx * dx + dz * dz <= 18) {
                    add(out, cx + dx, base, cz + dz, Blocks.END_STONE_BRICKS);
                }
            }
        }
        for (int y = 1; y <= 13; y++) {
            for (int dx = -2; dx <= 2; dx++) {
                for (int dz = -2; dz <= 2; dz++) {
                    boolean wall = Math.abs(dx) == 2 || Math.abs(dz) == 2;
                    boolean floor = y == 1 || y == 7 || y == 13;
                    boolean doorway = dz == 2 && dx == 0 && y >= 2 && y <= 3;
                    if (doorway) {
                        add(out, cx + dx, base + y, cz + dz, Blocks.AIR);
                    } else if (wall || floor) {
                        Block block = (Math.abs(dx) == 2 && Math.abs(dz) == 2)
                                ? Blocks.PURPUR_PILLAR : Blocks.PURPUR_BLOCK;
                        add(out, cx + dx, base + y, cz + dz, block);
                    } else {
                        add(out, cx + dx, base + y, cz + dz, Blocks.AIR);
                    }
                }
            }
        }
        add(out, cx - 2, base + 14, cz - 2, Blocks.END_ROD);
        add(out, cx + 2, base + 14, cz + 2, Blocks.END_ROD);
        addChest(out, cx, base + 8, cz);
        perches.add(new BlockPos(cx + 1, base + 8, cz - 1));
        perches.add(new BlockPos(cx, base + 14, cz));
    }

    /**
     * The end-ship silhouette (third islet): obsidian keel, purpur hull and deck sailing
     * west→east, a purpur-pillar mast with slab sails, the treasure bow chest (elytra
     * table when {@code allowElytra}) and a deck shulker.
     */
    private static void buildShip(List<Write> out, List<BlockPos> perches, BlockPos anchor) {
        int cx = anchor.getX();
        int cz = anchor.getZ();
        int deck = anchor.getY() + 4; // hull floats a little off the islet surface
        for (int dx = -8; dx <= 8; dx++) {
            int halfWidth = Math.abs(dx) >= 7 ? 1 : 2;
            for (int dz = -halfWidth; dz <= halfWidth; dz++) {
                add(out, cx + dx, deck - 2, cz + dz, Blocks.OBSIDIAN); // keel
                add(out, cx + dx, deck - 1, cz + dz, Blocks.PURPUR_BLOCK); // hull
                add(out, cx + dx, deck, cz + dz, Blocks.PURPUR_BLOCK); // deck
                for (int dy = 1; dy <= 6; dy++) {
                    add(out, cx + dx, deck + dy, cz + dz, Blocks.AIR);
                }
            }
        }
        // Raised stern cabin.
        for (int dx = 5; dx <= 8; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                add(out, cx + dx, deck + 1, cz + dz, Blocks.PURPUR_BLOCK);
            }
        }
        // Mast + slab sails.
        for (int dy = 1; dy <= 8; dy++) {
            add(out, cx - 1, deck + dy, cz, Blocks.PURPUR_PILLAR);
        }
        for (int dx = -4; dx <= 2; dx++) {
            for (int dy = 3; dy <= 7; dy++) {
                if (Math.abs(dx + 1) + Math.abs(dy - 5) <= 3) {
                    add(out, cx + dx, deck + dy, cz + 1, Blocks.PURPUR_SLAB);
                }
            }
        }
        // Bow lantern rods + the treasure chest below deck at the bow.
        add(out, cx - 8, deck + 1, cz, Blocks.END_ROD);
        add(out, cx + 8, deck + 2, cz, Blocks.END_ROD);
        out.add(new Write(new BlockPos(cx - 6, deck - 1, cz),
                Blocks.CHEST.defaultBlockState(), false, true));
        add(out, cx - 6, deck, cz, Blocks.AIR); // hatch over the treasure hold
        perches.add(new BlockPos(cx + 3, deck + 1, cz));
        perches.add(new BlockPos(cx - 6, deck, cz));
    }

    private static void add(List<Write> out, int x, int y, int z, Block block) {
        out.add(new Write(new BlockPos(x, y, z), block.defaultBlockState(), false, false));
    }

    private static void addChest(List<Write> out, int x, int y, int z) {
        out.add(new Write(new BlockPos(x, y, z), Blocks.CHEST.defaultBlockState(), true, false));
    }
}
