package dev.projecteclipse.eclipse.worldgen.structure.dungeon;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.Vec3i;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.LadderBlock;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.storage.loot.LootTable;

/**
 * The <b>Collapsed Vault</b> — custom dungeon #1 of design D7: a buried stone-brick vault
 * of rooms and trap corridors in the {@code FallbackBuilders} procedural style. Two
 * instances exist per save:
 *
 * <ul>
 *   <li>{@link #buildStandalone} — one underground instance placed by
 *       {@code UndergroundSites} (stage 3 annulus): ladder shaft under a collapsed hatch
 *       → entry hall → trap corridor → guard room → treasure room.</li>
 *   <li>{@link #buildStrongholdGauntlet} — the stage-5 stronghold gauntlet: a big
 *       collapsed-keep SURFACE ruin at the stronghold landmark whose inner stair drops
 *       into a descending gauntlet (three spawner rooms, trap plates, web chokes) that
 *       runs down to the end-portal room's doorstep — the "surface entrance → dungeon →
 *       portal room" path of design D6.</li>
 * </ul>
 *
 * <p>Spawner mobs come from {@code config/eclipse/dungeons.json} (key
 * {@link DungeonSpawners#COLLAPSED_VAULT}, P6 seam — vanilla zombie/skeleton fallback);
 * loot is {@code eclipse:dungeon/collapsed_vault}. All rolls are hashed from the frozen
 * map seed — deterministic per save. Callers relight via
 * {@code SitePrep.finishBounds(...)} on the returned bounds.</p>
 */
public final class CollapsedVaultBuilder {
    /** Loot table of every Collapsed Vault chest. */
    public static final ResourceKey<LootTable> LOOT = ResourceKey.create(Registries.LOOT_TABLE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "dungeon/collapsed_vault"));

    private CollapsedVaultBuilder() {}

    // --- standalone instance ---

    /**
     * The buried standalone vault. {@code center} is the underground anchor (entry-hall
     * center); the vault extends ~36 blocks along +X from it. Returns the built bounds.
     */
    public static BoundingBox buildStandalone(ServerLevel level, BlockPos center, int surfaceY) {
        int x = center.getX();
        int y = center.getY();
        int z = center.getZ();

        // Shells first: entry hall x-8..x, guard room x+14..x+20, treasure room x+22..x+30,
        // trap corridor interior x+1..x+13 between hall and guard room.
        room(level, x - 4, y, z, 4, 4, 3, false);
        room(level, x + 17, y, z, 3, 4, 4, false);
        room(level, x + 26, y, z, 4, 4, 3, true);
        corridor(level, x + 1, y, z, 13);
        ladderShaft(level, x - 6, y, z, surfaceY);
        // Openings after every shell exists so nothing re-seals them: hall→corridor,
        // corridor→guard room, guard room→gate slab→treasure room.
        door(level, x, y, z);
        door(level, x + 14, y, z);
        door(level, x + 20, y, z);
        gate(level, x + 21, y, z);
        door(level, x + 22, y, z);
        // Décor + hazards last (never overwritten by shell passes).
        DungeonSpawners.applyTo(level, new BlockPos(x + 17, y + 1, z), DungeonSpawners.COLLAPSED_VAULT, 0);
        lootChest(level, new BlockPos(x + 15, y + 1, z + 2), Direction.NORTH);
        DungeonSpawners.applyTo(level, new BlockPos(x + 26, y + 3, z), DungeonSpawners.COLLAPSED_VAULT, 1);
        lootChest(level, new BlockPos(x + 28, y + 1, z - 1), Direction.WEST);
        lootChest(level, new BlockPos(x + 28, y + 1, z + 1), Direction.WEST);
        set(level, x + 29, y + 1, z, Blocks.GOLD_BLOCK.defaultBlockState());

        BoundingBox bounds = new BoundingBox(x - 9, y - 3, z - 6, x + 31, surfaceY + 2, z + 6);
        EclipseMod.LOGGER.info("Collapsed Vault (standalone) built at {} (bounds {})",
                center.toShortString(), bounds);
        return bounds;
    }

    // --- stronghold gauntlet ---

    /**
     * The stage-5 gauntlet: surface ruin at {@code surfaceAnchor} (its Y = plateau ground),
     * then a carved descent to {@code portalTarget} — the doorstep of the stronghold
     * portal room (mountain cavity center when the map has a mountain). Three gauntlet
     * rooms sit at 30/60/85 % of the path. Returns the overall bounds.
     */
    public static BoundingBox buildStrongholdGauntlet(ServerLevel level, BlockPos surfaceAnchor,
            BlockPos portalTarget) {
        buildSurfaceRuin(level, surfaceAnchor, portalTarget);

        // Path: overlapping tunnel spheres along the anchor→target line with a lateral
        // swerve that fades to zero at BOTH ends (sin(pi*t)) so the tunnel starts exactly
        // under the ruin stair mouth and lands exactly on the antechamber center. Steps
        // are stretched so the slope stays walkable (~1 down per 2 forward).
        BlockPos from = surfaceAnchor.below();
        double dx = portalTarget.getX() - from.getX();
        double dy = portalTarget.getY() - from.getY();
        double dz = portalTarget.getZ() - from.getZ();
        int steps = (int) Math.max(Math.max(Math.abs(dx), Math.abs(dz)), Math.abs(dy) * 2.0D);
        steps = Math.max(16, Math.min(steps, 320));
        int[][] path = new int[steps + 1][3];
        for (int i = 0; i <= steps; i++) {
            double t = i / (double) steps;
            double fade = Math.sin(Math.PI * t);
            path[i][0] = from.getX() + (int) Math.round(dx * t + swerve(from, i, 0) * fade);
            path[i][1] = from.getY() + (int) Math.round(dy * t);
            path[i][2] = from.getZ() + (int) Math.round(dz * t + swerve(from, i, 1) * fade);
        }
        int[] roomSteps = {(int) (steps * 0.30D), (int) (steps * 0.60D), (int) (steps * 0.85D)};

        // Pass 1 — room shells (gauntlet rooms + portal antechamber) BEFORE carving, so the
        // tunnel spheres punch entry/exit doorways straight through their walls.
        for (int r = 0; r < roomSteps.length; r++) {
            int[] p = path[roomSteps[r]];
            room(level, p[0], p[1], p[2], 4, 4, 4, r == 2);
        }
        room(level, portalTarget.getX(), portalTarget.getY(), portalTarget.getZ(), 4, 5, 4, true);

        // Pass 2 — carve the full descent.
        for (int[] p : path) {
            carveTunnelSphere(level, p[0], p[1], p[2]);
        }

        // Pass 3 — hazards + décor inside the shells (placed after carving so nothing is
        // scooped back out).
        for (int r = 0; r < roomSteps.length; r++) {
            int[] p = path[roomSteps[r]];
            DungeonSpawners.applyTo(level, new BlockPos(p[0], p[1] + 1, p[2] + 2),
                    DungeonSpawners.COLLAPSED_VAULT, r);
            trapPlate(level, p[0] + 1, p[1], p[2] - 1);
            trapPlate(level, p[0] - 1, p[1], p[2] + 1);
            set(level, p[0] + 2, p[1] + 2, p[2] - 2, Blocks.COBWEB.defaultBlockState());
            if (r == 1) {
                lootChest(level, new BlockPos(p[0] - 2, p[1] + 1, p[2] - 2), Direction.EAST);
            }
        }
        // Antechamber: treasure at the portal-room doorstep + exit doorway continuing the
        // path direction (toward the portal room proper).
        lootChest(level, new BlockPos(portalTarget.getX() - 2, portalTarget.getY() + 1,
                portalTarget.getZ() - 2), Direction.SOUTH);
        DungeonSpawners.applyTo(level, new BlockPos(portalTarget.getX() + 2,
                portalTarget.getY() + 1, portalTarget.getZ() + 2), DungeonSpawners.COLLAPSED_VAULT, 3);
        Direction exit = Direction.getNearest(dx, 0, dz);
        if (exit.getAxis().isVertical()) {
            exit = Direction.NORTH;
        }
        BlockPos exitDoor = portalTarget.relative(exit, 4);
        door(level, exitDoor.getX(), portalTarget.getY(), exitDoor.getZ());

        BoundingBox bounds = BoundingBox.fromCorners(
                new Vec3i(Math.min(from.getX(), portalTarget.getX()) - 12,
                        Math.min(from.getY(), portalTarget.getY()) - 4,
                        Math.min(from.getZ(), portalTarget.getZ()) - 12),
                new Vec3i(Math.max(from.getX(), portalTarget.getX()) + 12,
                        Math.max(from.getY(), portalTarget.getY()) + 6,
                        Math.max(from.getZ(), portalTarget.getZ()) + 12));
        EclipseMod.LOGGER.info("Collapsed Vault (stronghold gauntlet) built: surface {} -> portal {} ({} steps)",
                surfaceAnchor.toShortString(), portalTarget.toShortString(), steps);
        return bounds;
    }

    /**
     * The stronghold-edge SURFACE structure: a collapsed keep — broken double wall ring,
     * corner stubs, rubble, an arch gate facing the descent — big enough to read from a
     * distance (r = 10), crumbled by hash so it looks ancient, never pristine.
     */
    private static void buildSurfaceRuin(ServerLevel level, BlockPos anchor, BlockPos toward) {
        int ax = anchor.getX();
        int ay = anchor.getY();
        int az = anchor.getZ();
        Direction gate = Direction.getNearest(toward.getX() - ax, 0, toward.getZ() - az);
        if (gate.getAxis().isVertical()) {
            gate = Direction.NORTH;
        }
        for (int dx = -10; dx <= 10; dx++) {
            for (int dz = -10; dz <= 10; dz++) {
                int ring = Math.max(Math.abs(dx), Math.abs(dz));
                boolean wall = ring == 10 || ring == 6;
                boolean corner = ring == 10 && Math.abs(dx) == 10 && Math.abs(dz) == 10;
                if (!wall) {
                    // Sparse rubble in the courtyard.
                    if (hash01(ax + dx, ay, az + dz) < 0.06D) {
                        set(level, ax + dx, ay + 1, az + dz, brickMix(ax + dx, ay + 1, az + dz));
                    }
                    continue;
                }
                // Gate gap on the wall segment facing the descent.
                int facing = gate.getStepX() != 0 ? dz : dx;
                boolean gateSide = (gate.getStepX() != 0 && Integer.signum(dx) == gate.getStepX())
                        || (gate.getStepZ() != 0 && Integer.signum(dz) == gate.getStepZ());
                if (gateSide && Math.abs(facing) <= 1) {
                    continue;
                }
                int height = corner ? 5 : 1 + (int) (hash01(ax + dx, ay, az + dz) * 4.0D);
                for (int dy = 1; dy <= height; dy++) {
                    set(level, ax + dx, ay + dy, az + dz, brickMix(ax + dx, ay + dy, az + dz));
                }
            }
        }
        // Arch over the outer gate gap.
        BlockPos gateCenter = anchor.relative(gate, 10);
        Direction side = gate.getClockWise();
        for (int i = -2; i <= 2; i++) {
            BlockPos top = gateCenter.relative(side, i).above(4);
            set(level, top.getX(), top.getY(), top.getZ(), brickMix(top.getX(), top.getY(), top.getZ()));
        }
        for (int dy = 1; dy <= 4; dy++) {
            BlockPos l = gateCenter.relative(side, -2).above(dy);
            BlockPos r = gateCenter.relative(side, 2).above(dy);
            set(level, l.getX(), l.getY(), l.getZ(), brickMix(l.getX(), l.getY(), l.getZ()));
            set(level, r.getX(), r.getY(), r.getZ(), brickMix(r.getX(), r.getY(), r.getZ()));
        }
        // Central stair mouth into the gauntlet (3×3 opening with chiseled rim).
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                set(level, ax + dx, ay, az + dz, Blocks.CAVE_AIR.defaultBlockState());
                set(level, ax + dx, ay - 1, az + dz, Blocks.CAVE_AIR.defaultBlockState());
            }
        }
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                if (Math.max(Math.abs(dx), Math.abs(dz)) == 2) {
                    set(level, ax + dx, ay, az + dz, Blocks.CHISELED_STONE_BRICKS.defaultBlockState());
                }
            }
        }
    }

    // --- shared vault pieces ---

    /** Hollow brick room centered on (x, y, z); {@code gilded} floors get treasure accents. */
    private static void room(ServerLevel level, int x, int y, int z,
            int halfX, int height, int halfZ, boolean gilded) {
        for (int dx = -halfX; dx <= halfX; dx++) {
            for (int dz = -halfZ; dz <= halfZ; dz++) {
                boolean wall = Math.abs(dx) == halfX || Math.abs(dz) == halfZ;
                BlockState floor = gilded && !wall && hash01(x + dx, y, z + dz) < 0.18D
                        ? Blocks.GILDED_BLACKSTONE.defaultBlockState()
                        : brickMix(x + dx, y, z + dz);
                set(level, x + dx, y, z + dz, floor);
                for (int dy = 1; dy < height; dy++) {
                    set(level, x + dx, y + dy, z + dz,
                            wall ? brickMix(x + dx, y + dy, z + dz) : Blocks.CAVE_AIR.defaultBlockState());
                }
                set(level, x + dx, y + height, z + dz, brickMix(x + dx, y + height, z + dz));
            }
        }
        set(level, x - halfX + 1, y + 1, z - halfZ + 1, Blocks.LANTERN.defaultBlockState());
    }

    /** 3-wide trap corridor along +X with hashed pressure-plate TNT traps and webs. */
    private static void corridor(ServerLevel level, int startX, int y, int z, int length) {
        for (int i = 0; i < length; i++) {
            int x = startX + i;
            for (int dz = -1; dz <= 1; dz++) {
                set(level, x, y, z + dz, brickMix(x, y, z + dz));
                for (int dy = 1; dy <= 3; dy++) {
                    set(level, x, y + dy, z + dz, Blocks.CAVE_AIR.defaultBlockState());
                }
                set(level, x, y + 4, z + dz, brickMix(x, y + 4, z + dz));
                set(level, x, y, z - 2, brickMix(x, y, z - 2));
                set(level, x, y, z + 2, brickMix(x, y, z + 2));
            }
            double roll = hash01(x, y, z);
            if (roll < 0.18D) {
                trapPlate(level, x, y, z + (roll < 0.09D ? -1 : 1));
            } else if (roll > 0.88D) {
                set(level, x, y + 2, z, Blocks.COBWEB.defaultBlockState());
            }
        }
    }

    /** Pressure plate over a buried TNT charge (vanilla desert-pyramid pattern). */
    private static void trapPlate(ServerLevel level, int x, int floorY, int z) {
        set(level, x, floorY, z, Blocks.STONE_BRICKS.defaultBlockState());
        set(level, x, floorY - 1, z, Blocks.TNT.defaultBlockState());
        set(level, x, floorY + 1, z, Blocks.STONE_PRESSURE_PLATE.defaultBlockState());
    }

    /** 1-wide 2-high doorway carved through a wall column at (x, z). */
    private static void door(ServerLevel level, int x, int y, int z) {
        set(level, x, y + 1, z, Blocks.CAVE_AIR.defaultBlockState());
        set(level, x, y + 2, z, Blocks.CAVE_AIR.defaultBlockState());
    }

    /** Iron-bar treasure gate slab across the corridor at x (2-high center opening). */
    private static void gate(ServerLevel level, int x, int y, int z) {
        for (int dz = -1; dz <= 1; dz++) {
            set(level, x, y, z + dz, brickMix(x, y, z + dz));
            for (int dy = 1; dy <= 3; dy++) {
                set(level, x, y + dy, z + dz, Blocks.IRON_BARS.defaultBlockState());
            }
            set(level, x, y + 4, z + dz, brickMix(x, y + 4, z + dz));
        }
        set(level, x, y + 1, z, Blocks.CAVE_AIR.defaultBlockState());
        set(level, x, y + 2, z, Blocks.CAVE_AIR.defaultBlockState());
    }

    /**
     * Ladder shaft from the vault floor up to the surface, capped by a collapsed hatch
     * collar. Starts one above the hall floor so the landing block stays solid; the brick
     * spine west of the ladder gives it support the whole way up.
     */
    private static void ladderShaft(ServerLevel level, int x, int y, int z, int surfaceY) {
        BlockState ladder = Blocks.LADDER.defaultBlockState()
                .setValue(LadderBlock.FACING, Direction.EAST);
        for (int cy = y + 1; cy <= surfaceY + 1; cy++) {
            set(level, x - 1, cy, z, brickMix(x - 1, cy, z));
            set(level, x, cy, z, ladder);
        }
        // Broken hatch collar at the surface.
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                if ((dx != 0 || dz != 0) && hash01(x + dx, surfaceY + 1, z + dz) < 0.5D) {
                    set(level, x + dx, surfaceY + 1, z + dz, brickMix(x + dx, surfaceY + 1, z + dz));
                }
            }
        }
    }

    /** Carves one r≈2.4 tunnel sphere with a solid floor pad under the walk line. */
    private static void carveTunnelSphere(ServerLevel level, int cx, int cy, int cz) {
        for (int dx = -2; dx <= 2; dx++) {
            for (int dy = -1; dy <= 3; dy++) {
                for (int dz = -2; dz <= 2; dz++) {
                    double d = dx * dx + (dy - 1) * (dy - 1) * 0.8D + dz * dz;
                    if (d <= 5.8D) {
                        set(level, cx + dx, cy + dy, cz + dz, Blocks.CAVE_AIR.defaultBlockState());
                    }
                }
            }
        }
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                BlockPos floor = new BlockPos(cx + dx, cy - 1, cz + dz);
                if (!level.getBlockState(floor).isSolidRender(level, floor)) {
                    set(level, floor.getX(), floor.getY(), floor.getZ(),
                            brickMix(floor.getX(), floor.getY(), floor.getZ()));
                }
            }
        }
    }

    // --- primitives ---

    /** Gentle lateral wobble of the gauntlet path (deterministic, ±2 blocks). */
    private static double swerve(BlockPos seedPos, int step, int axis) {
        return Math.sin((step + axis * 37) * 0.22D + (seedPos.asLong() & 0xFF) * 0.1D) * 2.0D;
    }

    private static BlockState brickMix(int x, int y, int z) {
        double roll = hash01(x, y, z);
        if (roll < 0.30D) {
            return Blocks.CRACKED_STONE_BRICKS.defaultBlockState();
        }
        if (roll < 0.55D) {
            return Blocks.MOSSY_STONE_BRICKS.defaultBlockState();
        }
        if (roll < 0.62D) {
            return Blocks.COBBLESTONE.defaultBlockState();
        }
        return Blocks.STONE_BRICKS.defaultBlockState();
    }

    private static void lootChest(ServerLevel level, BlockPos pos, Direction facing) {
        set(level, pos.getX(), pos.getY(), pos.getZ(),
                Blocks.CHEST.defaultBlockState().setValue(HorizontalDirectionalBlock.FACING, facing));
        if (level.getBlockEntity(pos) instanceof RandomizableContainerBlockEntity chest) {
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
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
    }
}
