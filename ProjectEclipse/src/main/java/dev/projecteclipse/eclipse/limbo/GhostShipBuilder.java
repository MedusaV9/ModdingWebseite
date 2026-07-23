package dev.projecteclipse.eclipse.limbo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorApi;
import dev.projecteclipse.eclipse.limbo.door.ShipVersionData;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LadderBlock;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.world.level.block.TrapDoorBlock;
import net.minecraft.world.level.block.WallSkullBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Procedurally builds the ghost ship v2 floating on the Limbo ocean (plans_v3 §2.5) plus
 * the small spawn platform. Pure deterministic block loops — fixed layout constants and
 * {@link DiscMapData#ECLIPSE_SEED}-derived hashes only, never {@code level.random} — so
 * every build produces byte-identical blocks and a second run changes nothing.
 *
 * <p><b>Frozen fight contracts (§1.3 — DO NOT BREAK):</b> {@link #HALF_LENGTH},
 * {@link #halfWidthAt}, {@link #waterlineY}, deck at {@code waterline+3},
 * {@link #NOMINAL_CENTER}, {@link #platformArrivalPos}, benches at
 * x∈{−12,−4,4,12} one block inboard of the gunwale, the Ferryman's stern anchor column
 * (x=−16, z=0) open to the sky, and no water/waterlogged states placed inside the P3
 * sink volume ({@code deckY+1..+4} over the {@code halfWidthAt} footprint).</p>
 *
 * <p><b>v2 silhouette</b> (bow +X): 3-tone hull (dark-oak planks, log ribs every 4 x, a
 * stripped-log wale stripe at waterline+1, mud-brick/blackstone barnacle dither below the
 * waterline, stair fillets along the taper columns), a bone-stem figurehead with a
 * skeleton skull under a rising 6-log bowsprit, a raised forecastle (+2, x 14..19), a
 * sterncastle (wing decks +3 at x −15..−13, a 5-tall bulkhead at x=−17 holding the
 * {@code eclipse:respawn_door} multiblock flanked by purple portholes, solid transom and
 * poop at +6 with a hanging great-lantern cluster astern), two masts with yards at +5/+8
 * carrying wind-stepped tattered sails (80/20 black/gray wool dither, hash-eaten holes),
 * a crow's nest on the aft mast, chain fore/backstays, fence-and-chain railings with
 * trapdoor oarlock notches at the eight bench cells, and two soul-fire braziers on the
 * sterncastle wings.</p>
 *
 * <p><b>Versioned migration</b> ({@link ShipVersionData}, own SavedData — the shared
 * {@code EclipseWorldState} only keeps its legacy build-once flag): v1 ships are cleared
 * back to open sea over {@code x±21 / z±6 / keel..deck+12} and rebuilt as v2 in the same
 * server-thread pass (no fluid tick can run in between). The rebuild is skipped (and
 * retried next start) while a Ferryman is alive. Once stamped
 * {@link ShipVersionData#VERSION_V2}, boots make ZERO block changes.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GhostShipBuilder {
    /** Nominal ship center from the event spec, used as fallback when no water surface is found. */
    public static final BlockPos NOMINAL_CENTER = new BlockPos(0, 64, 0);

    /** Half length along X (bow at +X, stern at -X). Total length = 2*19 + 1 = 39. */
    public static final int HALF_LENGTH = 19;
    /** Maximum half width along Z (midship). Total width = 2*4 + 1 = 9. */
    public static final int HALF_WIDTH = 4;
    /** X offsets of the two masts. */
    public static final int[] MAST_X = {-8, 8};

    /**
     * Bulkhead plane of the sterncastle — the {@code eclipse:respawn_door} multiblock
     * fills its central 3×5 aperture (z −1..1, deckY+1..deckY+5), facing the bow (+X).
     * Consumed by {@code limbo.door.RespawnDoorApi}; frozen for P2 (door glow FX anchor)
     * and P3/P4 (death/respawn flow).
     */
    public static final int DOOR_X = -17;

    /** Bench columns along the hull (mirrors {@code DeckhandEntity.BENCH_X} — frozen). */
    private static final int[] BENCH_X = {-12, -4, 4, 12};
    /** Sterncastle front (wings above, door alley below); main deck spans −12..13. */
    private static final int CASTLE_FRONT_X = -13;
    /** Forecastle front wall; the raised +2 foredeck spans x 14..19. */
    private static final int FORECASTLE_FRONT_X = 14;

    private GhostShipBuilder() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        ServerLevel limbo = event.getServer().getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Limbo dimension {} is not loaded; ghost ship not built", LimboDimension.LIMBO.location());
            return;
        }
        buildIfNeeded(limbo);
        LimboSeascape.buildIfNeeded(limbo);
        OarAnimator.ensureOars(limbo);
        DeckhandEntity.ensureCrew(limbo);
        // W12: the four deck lanterns of the Ferryman fight. Placed every start (cheap,
        // idempotent) so pre-W12 worlds with an already-built ship get them too.
        ShipLanterns.ensurePlaced(limbo);
        // P6-W3: the respawn door multiblock (idempotent repair — no-op until the
        // DoorRegistry wiring line lands) + the frozen FX anchors for P2.
        RespawnDoorApi.ensureDoor(limbo);
        RespawnDoorApi.publishAnchors(limbo);
    }

    /** Column sampled for the water surface; far away from every block the builder places. */
    private static final int WATER_SAMPLE_X = 256;
    private static final int WATER_SAMPLE_Z = 256;

    /**
     * Version-gated build/migration entry (plans_v3 §2.5): fresh worlds build v2 directly;
     * legacy v1 ships are cleared and rebuilt once; v2 worlds are a guaranteed no-op
     * (restart idempotence — zero block changes). Skipped while a Ferryman is alive so a
     * persisted mid-fight ship is never yanked out from under the boss (retried next start).
     */
    public static void buildIfNeeded(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        ShipVersionData version = ShipVersionData.get(limbo);
        if (version.version() >= ShipVersionData.VERSION_V2) {
            EclipseMod.LOGGER.info("Ghost ship v2 present (version {}) — idempotent boot, zero block changes",
                    version.version());
            return;
        }
        if (state.isGhostShipBuilt() && version.version() == ShipVersionData.VERSION_NONE) {
            // Legacy pre-versioning save: adopt the existing build as v1 before migrating.
            version.setVersion(ShipVersionData.VERSION_V1);
            EclipseMod.LOGGER.info("Ghost ship version adopt: legacy un-versioned ship stamped v1 (rebuild pending)");
        }
        if (!limbo.getEntities(EclipseEntities.FERRYMAN.get(), FerrymanEntity::isAlive).isEmpty()) {
            EclipseMod.LOGGER.info("Ghost ship v2 rebuild SKIPPED: a Ferryman is alive on the v1 ship — retrying next start");
            return;
        }
        boolean migrating = state.isGhostShipBuilt();
        if (migrating) {
            clearLegacyVolume(limbo);
        }
        int waterline = build(limbo);
        state.setGhostShipBuilt(true);
        version.setVersion(ShipVersionData.VERSION_V2);
        if (migrating) {
            // P6-W2 wiring note: persisted living rowers keep their old coordinates
            // through a rebuild — one idempotent calmCrew snaps them onto their benches.
            DeckhandEntity.calmCrew(limbo);
        }
        EclipseMod.LOGGER.info("Ghost ship v2 {} in {} at waterline y={} around x=0, z=0 (version stamped {})",
                migrating ? "rebuilt from v1" : "built fresh", LimboDimension.LIMBO.location(), waterline,
                ShipVersionData.VERSION_V2);
    }

    /**
     * The Y of the top water block of the Limbo ocean (48 with the shipped datapack), or
     * {@code NOMINAL_CENTER.getY() - 1} if the sampled column contains no water (e.g. the
     * dimension JSON was changed). Sampled far away from the ship so the result is stable
     * before and after the build.
     */
    public static int waterlineY(ServerLevel limbo) {
        // Query the chunk directly: Level.getHeight consults hasChunk(), which can still be
        // false for freshly force-loaded chunks during server start.
        ChunkAccess chunk = limbo.getChunk(WATER_SAMPLE_X >> 4, WATER_SAMPLE_Z >> 4);
        int topY = chunk.getHeight(Heightmap.Types.WORLD_SURFACE, WATER_SAMPLE_X, WATER_SAMPLE_Z); // top non-air block
        BlockPos top = new BlockPos(WATER_SAMPLE_X, topY, WATER_SAMPLE_Z);
        if (topY > limbo.getMinBuildHeight() && chunk.getBlockState(top).is(Blocks.WATER)) {
            return topY;
        }
        return NOMINAL_CENTER.getY() - 1;
    }

    /**
     * Resets the v1 ship volume to open sea (water up to the waterline, air above) so the
     * v2 build starts from a clean slate: x −21..21, z −6..6, keel..deck+12 covers every
     * v1 block (hull ±19/±4, masts to +9, flat sails, rails, old mid-deck lanterns). The
     * v1 spawn platform (z 10..14) is NOT cleared — v2 re-places those exact cells. Runs
     * in the same server-thread pass as the rebuild, so no fluid tick can slip between
     * the water fill and the new hull sealing it out again.
     */
    private static void clearLegacyVolume(ServerLevel limbo) {
        int waterline = waterlineY(limbo);
        int keelY = waterline - 2;
        int topY = waterline + 3 + 12;
        BlockState water = Blocks.WATER.defaultBlockState();
        BlockState air = Blocks.AIR.defaultBlockState();
        int changed = 0;
        for (int x = -HALF_LENGTH - 2; x <= HALF_LENGTH + 2; x++) {
            for (int z = -HALF_WIDTH - 2; z <= HALF_WIDTH + 2; z++) {
                for (int y = keelY; y <= topY; y++) {
                    BlockState target = y <= waterline ? water : air;
                    if (!limbo.getBlockState(new BlockPos(x, y, z)).equals(target)) {
                        set(limbo, x, y, z, target);
                        changed++;
                    }
                }
            }
        }
        EclipseMod.LOGGER.info("Ghost ship migration: v1 volume cleared back to open sea ({} block(s) reset)", changed);
    }

    /**
     * Unconditionally builds the v2 ship and spawn platform; returns the waterline Y used.
     * Deterministic and idempotent block-wise (fixed constants + fixed-seed hashes; every
     * cell is written in the same order with the same state on every run).
     */
    public static int build(ServerLevel limbo) {
        int waterline = waterlineY(limbo);
        int keelY = waterline - 2;          // hull bottom, 2 blocks of draft
        int deckY = waterline + 3;

        hullShell(limbo, waterline, keelY, deckY);
        taperFillets(limbo, waterline, deckY);
        mainDeckDressing(limbo, deckY);
        bowAssembly(limbo, waterline, deckY);
        forecastle(limbo, deckY);
        sterncastle(limbo, waterline, deckY);
        mastsAndSails(limbo, deckY);
        spawnPlatform(limbo, deckY);
        return waterline;
    }

    // ------------------------------------------------------------------ hull

    /**
     * Keel floor, tapering side walls, hollow bilge and solid deck — the exact v1 sealed
     * envelope (the P3 sink/restore volume math depends on it) re-skinned: barnacle
     * dither below the waterline, a stripped wale stripe at waterline+1, vertical log
     * ribs every 4th column, and a stripped king plank down the main-deck centerline.
     */
    private static void hullShell(ServerLevel limbo, int waterline, int keelY, int deckY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockState wale = Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.X);
        BlockState rib = Blocks.DARK_OAK_LOG.defaultBlockState();

        for (int dx = -HALF_LENGTH; dx <= HALF_LENGTH; dx++) {
            int hw = halfWidthAt(dx);
            boolean endCap = Math.abs(dx) == HALF_LENGTH;
            boolean ribColumn = Math.floorMod(dx, 4) == 0;
            for (int dz = -hw; dz <= hw; dz++) {
                set(limbo, dx, keelY, dz, barnacle(dx, keelY, dz));
                for (int y = keelY + 1; y < deckY; y++) {
                    boolean isWall = dz == -hw || dz == hw || endCap;
                    if (!isWall) {
                        set(limbo, dx, y, dz, air);
                        continue;
                    }
                    boolean sideWall = dz == -hw || dz == hw;
                    BlockState state;
                    if (y <= waterline) {
                        state = barnacle(dx, y, dz);
                    } else if (y == waterline + 1 && sideWall && !endCap) {
                        state = wale;
                    } else if (ribColumn && sideWall) {
                        state = rib;
                    } else {
                        state = planks;
                    }
                    set(limbo, dx, y, dz, state);
                }
                set(limbo, dx, deckY, dz, planks);
            }
        }
        // King plank: a stripped-log inlay down the open main deck's centerline.
        for (int dx = -12; dx <= 13; dx++) {
            set(limbo, dx, deckY, 0, wale);
        }
    }

    /** Below-waterline shell material: dark planks eaten by blackstone/mud-brick growth. */
    private static BlockState barnacle(int x, int y, int z) {
        double h = hash01(x, y, z);
        if (h < 0.18D) {
            return Blocks.MUD_BRICKS.defaultBlockState();
        }
        if (h < 0.46D) {
            return Blocks.BLACKSTONE.defaultBlockState();
        }
        return Blocks.DARK_OAK_PLANKS.defaultBlockState();
    }

    /**
     * Stair fillets on the outer corners of every hull width transition (|x| = 13/16/18),
     * at deck and wale level, so bow and stern read as curves instead of 1-block steps.
     */
    private static void taperFillets(ServerLevel limbo, int waterline, int deckY) {
        int[][] corners = {{13, 4}, {16, 3}, {18, 2}};
        for (int[] corner : corners) {
            for (int sideX = -1; sideX <= 1; sideX += 2) {
                int x = corner[0] * sideX;
                // The full stair back leans against the wider midship side.
                Direction facing = sideX > 0 ? Direction.WEST : Direction.EAST;
                for (int sideZ = -1; sideZ <= 1; sideZ += 2) {
                    int z = corner[1] * sideZ;
                    BlockState stair = Blocks.DARK_OAK_STAIRS.defaultBlockState()
                            .setValue(StairBlock.FACING, facing);
                    set(limbo, x, deckY, z, stair);
                    set(limbo, x, waterline + 1, z, stair);
                }
            }
        }
    }

    // ------------------------------------------------------------------ main deck

    /**
     * Gunwale railing (fence posts every 3rd column, slack chains between), the eight
     * trapdoor oarlock notches at the bench columns, the boarding gap toward the spawn
     * platform, and the stripped-log-and-trapdoor deck barrels. Everything placed inside
     * the sink band ({@code deckY+1..+4}) is solid or waterlogged=false — the flood pass
     * only fills air and the restore sweep only drains water, so all of it survives P3.
     */
    private static void mainDeckDressing(ServerLevel limbo, int deckY) {
        int railY = deckY + 1;
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        BlockState railChain = Blocks.CHAIN.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.X);
        for (int dx = -12; dx <= 13; dx++) {
            int hw = halfWidthAt(dx);
            for (int side = -1; side <= 1; side += 2) {
                int z = hw * side;
                if (side > 0 && dx >= -1 && dx <= 1) {
                    continue; // Boarding gap toward the walkway/spawn platform.
                }
                if (isBenchColumn(dx)) {
                    // Oarlock notch: an open trapdoor dips the rail so the oar clears it.
                    set(limbo, dx, railY, z, Blocks.DARK_OAK_TRAPDOOR.defaultBlockState()
                            .setValue(TrapDoorBlock.FACING, side > 0 ? Direction.SOUTH : Direction.NORTH)
                            .setValue(TrapDoorBlock.OPEN, true));
                    continue;
                }
                set(limbo, dx, railY, z, Math.floorMod(dx, 3) == 0 ? fence : railChain);
            }
        }
        // Deck barrels: stripped-log drums with trapdoor lids, clear of benches and lanes.
        barrel(limbo, 13, deckY + 1, -2);
        barrel(limbo, 13, deckY + 1, 2);
        barrel(limbo, -11, deckY + 1, -2);
        barrel(limbo, 5, deckY + 1, 2);
    }

    private static boolean isBenchColumn(int x) {
        for (int benchX : BENCH_X) {
            if (benchX == x) {
                return true;
            }
        }
        return false;
    }

    private static void barrel(ServerLevel limbo, int x, int y, int z) {
        set(limbo, x, y, z, Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState());
        set(limbo, x, y + 1, z, Blocks.DARK_OAK_TRAPDOOR.defaultBlockState());
    }

    // ------------------------------------------------------------------ bow

    /**
     * Bone-block stem (cutwater) with a skeleton-skull figurehead, and the bowsprit: six
     * rising logs/fences off the bow tip with a chain-hung soul lantern at the end and a
     * bobstay chain back down to the stem. All of it sits outside the {@code halfWidthAt}
     * footprint, so the P3 flood/restore never touches it.
     */
    private static void bowAssembly(ServerLevel limbo, int waterline, int deckY) {
        BlockState bone = Blocks.BONE_BLOCK.defaultBlockState();
        // Stem: from just above the water to the rail, proud of the bow cap.
        for (int y = waterline + 1; y <= deckY + 1; y++) {
            set(limbo, HALF_LENGTH + 1, y, 0, bone);
        }
        set(limbo, HALF_LENGTH + 2, deckY + 1, 0, Blocks.SKELETON_WALL_SKULL.defaultBlockState()
                .setValue(WallSkullBlock.FACING, Direction.EAST));
        // Bowsprit: logs stepping up and out, fence tip.
        BlockState spritLog = Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.X);
        set(limbo, 20, deckY + 2, 0, spritLog);
        set(limbo, 21, deckY + 3, 0, spritLog);
        set(limbo, 22, deckY + 3, 0, spritLog);
        set(limbo, 23, deckY + 4, 0, spritLog);
        set(limbo, 24, deckY + 4, 0, spritLog);
        set(limbo, 25, deckY + 5, 0, Blocks.DARK_OAK_FENCE.defaultBlockState());
        // Bow light: chain + soul lantern swinging under the sprit tip.
        set(limbo, 25, deckY + 4, 0, Blocks.CHAIN.defaultBlockState());
        set(limbo, 25, deckY + 3, 0, Blocks.SOUL_LANTERN.defaultBlockState()
                .setValue(LanternBlock.HANGING, true));
        // Bobstay: chain sagging from the sprit back toward the stem head.
        set(limbo, 22, deckY + 2, 0, Blocks.CHAIN.defaultBlockState());
        set(limbo, 22, deckY + 1, 0, Blocks.CHAIN.defaultBlockState());
    }

    // ------------------------------------------------------------------ forecastle

    /**
     * Raised foredeck: solid plank mass (deck+1..+2) over x 14..19 with a centered
     * three-wide stair up from the main deck, fence-and-chain rails on the +2 top, and
     * the forecastle fight lantern spot kept clear at (16, deck+3, 0) for
     * {@link ShipLanterns}. Solid mass = nothing for the P3 flood to fill or drain here.
     */
    private static void forecastle(ServerLevel limbo, int deckY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        for (int dx = FORECASTLE_FRONT_X; dx <= HALF_LENGTH; dx++) {
            int hw = halfWidthAt(dx);
            for (int dz = -hw; dz <= hw; dz++) {
                set(limbo, dx, deckY + 1, dz, planks);
                set(limbo, dx, deckY + 2, dz, planks);
            }
        }
        // Grand stair up from the main deck (ascending toward +X).
        for (int dz = -1; dz <= 1; dz++) {
            set(limbo, FORECASTLE_FRONT_X - 1, deckY + 1, dz, Blocks.DARK_OAK_STAIRS.defaultBlockState()
                    .setValue(StairBlock.FACING, Direction.EAST));
        }
        // Fence-and-chain rail around the foredeck edge (skip the stair mouth).
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        BlockState chainX = Blocks.CHAIN.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.X);
        for (int dx = FORECASTLE_FRONT_X; dx <= 18; dx++) {
            int hw = halfWidthAt(dx);
            for (int side = -1; side <= 1; side += 2) {
                set(limbo, dx, deckY + 3, hw * side, Math.floorMod(dx, 2) == 0 ? fence : chainX);
            }
        }
        // Bow-cap rail on the foredeck tip (v1's deck-level cap is buried under the mass).
        for (int dz = -1; dz <= 1; dz++) {
            set(limbo, HALF_LENGTH, deckY + 3, dz, fence);
        }
    }

    // ------------------------------------------------------------------ sterncastle

    /**
     * The stern superstructure around the Respawn Door (plans_v3 §2.5):
     * <ul>
     *   <li><b>Door alley</b> — z −1..1 stays at main-deck level from the bulkhead out to
     *       the open deck; the Ferryman's stern anchor column (x=−16, z=0) keeps open sky
     *       (he kneels with his back to the door, and his P2 drift home crosses no wall).</li>
     *   <li><b>Bulkhead</b> at {@link #DOOR_X}: log pillars at z=±2 with purple-stained-glass
     *       portholes at eye level, the 3×5 door aperture (filled by
     *       {@code RespawnDoorApi.ensureDoor} once the registry is wired), and a plank
     *       header row at deck+6.</li>
     *   <li><b>Wing decks</b> (+3, x −15..−13, z ±2..±3) with access ladders on the
     *       bulkhead face at (−16, ±2) — backed by the door pillars, clear of the door
     *       alley, the Ferryman anchor column and W2's x=−12 bench cells. Ghosts MUST be
     *       able to climb up: the quarterdeck fight lantern at (−14, deck+4, 3) is only
     *       channelable within {@code ShipLanterns.CHANNEL_RANGE} (3 blocks) of a ghost's
     *       feet. One soul-fire brazier per wing.</li>
     *   <li><b>Transom + poop</b> — solid mass behind the bulkhead rising to a +6 poop cap
     *       with a rail, a sternpost + rudder below, and the great-lantern cluster
     *       hanging astern at x=−20 (outside the sink footprint).</li>
     * </ul>
     */
    private static void sterncastle(ServerLevel limbo, int waterline, int deckY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        BlockState log = Blocks.DARK_OAK_LOG.defaultBlockState();
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        BlockState chain = Blocks.CHAIN.defaultBlockState();

        // Wing decks +3 with raised hull walls under their outboard edge.
        for (int dx = -15; dx <= CASTLE_FRONT_X; dx++) {
            int hw = halfWidthAt(dx); // 3 across the wing span
            for (int side = -1; side <= 1; side += 2) {
                for (int y = deckY + 1; y <= deckY + 2; y++) {
                    set(limbo, dx, y, hw * side, planks); // raised outboard wall
                }
                for (int dz = 2; dz <= hw; dz++) {
                    set(limbo, dx, deckY + 3, dz * side, planks); // wing floor
                }
            }
        }
        // Wing front posts + wing access ladders. The ladders live on the bulkhead face
        // (x=−16, z=±2, FACING=EAST → attached to the pillar west of them; the pillar is
        // log/log/glass/log over the rung heights — all full sturdy cubes). They must NOT
        // sit at x=−12 (v-dev draft): that is a bench column and W2's seated rowers
        // straddle the z=±2/±3 cells there. Top rung at deck+4 lands the climber flush
        // on the wing floor top.
        for (int side = -1; side <= 1; side += 2) {
            for (int y = deckY + 1; y <= deckY + 2; y++) {
                set(limbo, CASTLE_FRONT_X, y, 2 * side, log);
            }
            for (int y = deckY + 1; y <= deckY + 4; y++) {
                set(limbo, DOOR_X + 1, y, 2 * side, Blocks.LADDER.defaultBlockState()
                        .setValue(LadderBlock.FACING, Direction.EAST));
            }
            // Soul-fire brazier on the wing lip (soul fire, NOT a campfire — the four
            // soul-campfire fight lanterns stay unambiguous): soil at the sink-band
            // ceiling, flame safely above it.
            set(limbo, -15, deckY + 4, 3 * side, Blocks.SOUL_SOIL.defaultBlockState());
            set(limbo, -15, deckY + 5, 3 * side, Blocks.SOUL_FIRE.defaultBlockState());
        }

        // Bulkhead at DOOR_X: pillars + portholes; the 3×5 aperture stays air here
        // (RespawnDoorApi.ensureDoor fills it with the door multiblock when wired).
        for (int side = -1; side <= 1; side += 2) {
            for (int y = deckY + 1; y <= deckY + 5; y++) {
                set(limbo, DOOR_X, y, 2 * side, y == deckY + 3
                        ? Blocks.PURPLE_STAINED_GLASS.defaultBlockState() : log);
            }
        }
        for (int dz = -2; dz <= 2; dz++) {
            set(limbo, DOOR_X, deckY + 6, dz, planks); // header cap over door + pillars
        }

        // Transom mass + poop cap.
        for (int dx = -HALF_LENGTH; dx <= -18; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                for (int y = deckY + 1; y <= deckY + 5; y++) {
                    set(limbo, dx, y, dz, Math.floorMod(dx + dz, 4) == 0 ? log : planks);
                }
                set(limbo, dx, deckY + 6, dz, planks);
            }
        }
        set(limbo, -HALF_LENGTH, deckY + 7, -1, fence);
        set(limbo, -HALF_LENGTH, deckY + 7, 1, fence);
        set(limbo, -HALF_LENGTH, deckY + 7, 0, Blocks.CHAIN.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.Z));

        // Stern great-lantern cluster hanging off the poop overhang (x=−20, outside the
        // sink footprint): two short drops port/starboard, one long drop on centerline.
        BlockState hangingLantern = Blocks.SOUL_LANTERN.defaultBlockState()
                .setValue(LanternBlock.HANGING, true);
        for (int dz = -1; dz <= 1; dz++) {
            set(limbo, -20, deckY + 6, dz, planks);
            set(limbo, -20, deckY + 5, dz, chain);
        }
        set(limbo, -20, deckY + 4, -1, hangingLantern);
        set(limbo, -20, deckY + 4, 1, hangingLantern);
        set(limbo, -20, deckY + 4, 0, chain);
        set(limbo, -20, deckY + 3, 0, hangingLantern);

        // Sternpost + rudder blade below the overhang.
        for (int y = waterline - 1; y <= deckY; y++) {
            set(limbo, -20, y, 0, log);
        }
        for (int y = waterline - 2; y <= waterline + 1; y++) {
            set(limbo, -21, y, 0, planks);
        }
    }

    // ------------------------------------------------------------------ masts & sails

    /**
     * Two log masts (deck+1..+11) with stripped-log yards at +5 and +8 spanning z −4..4,
     * wind-stepped tattered sails between them (rows step +1x per row down so the canvas
     * reads as filled, 80/20 black/gray dither with hash-eaten holes), a fore topsail, a
     * crow's nest on the aft mast, and chain fore/backstays from the yard tips down the
     * gunwale line. Sail cloth stays at deck+5 and higher — the bench cells keep open sky
     * to the water for the deckhand oars (P6-W2 contract).
     */
    private static void mastsAndSails(ServerLevel limbo, int deckY) {
        BlockState mast = Blocks.DARK_OAK_LOG.defaultBlockState();
        BlockState yard = Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.Z);
        BlockState chain = Blocks.CHAIN.defaultBlockState();

        for (int mastX : MAST_X) {
            for (int y = deckY + 1; y <= deckY + 11; y++) {
                set(limbo, mastX, y, 0, mast);
            }
            for (int yardY : new int[] {deckY + 5, deckY + 8}) {
                for (int dz = -4; dz <= 4; dz++) {
                    if (dz != 0) {
                        set(limbo, mastX, yardY, dz, yard);
                    }
                }
            }
            // Main course between the yards: each row steps one block toward the bow so
            // the sail bellies out; holes + gray dither make it ghost-tattered.
            sailRow(limbo, mastX + 1, deckY + 7, 4, 0.14D);
            sailRow(limbo, mastX + 2, deckY + 6, 4, 0.14D);
            sailRow(limbo, mastX + 2, deckY + 5, 4, 0.5D); // flying, half-gone foot
            // Stays from the upper-yard tips down the gunwale line (loose chain rigging).
            int stayDir = mastX > 0 ? 1 : -1;
            for (int i = 1; i <= 4; i++) {
                set(limbo, mastX + stayDir * i, deckY + 8 - i, -4, chain);
                set(limbo, mastX + stayDir * i, deckY + 8 - i, 4, chain);
            }
        }
        // Fore topsail above the upper yard.
        sailRow(limbo, MAST_X[1] + 1, deckY + 9, 3, 0.2D);
        sailRow(limbo, MAST_X[1] + 1, deckY + 10, 2, 0.45D);

        // Crow's nest on the aft mast: 3×3 plank basket at +9 with a fence ring at +10.
        int aft = MAST_X[0];
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                if (dx != 0 || dz != 0) {
                    set(limbo, aft + dx, deckY + 9, dz, Blocks.DARK_OAK_PLANKS.defaultBlockState());
                }
                if (Math.abs(dx) == 1 || Math.abs(dz) == 1) {
                    set(limbo, aft + dx, deckY + 10, dz, Blocks.DARK_OAK_FENCE.defaultBlockState());
                }
            }
        }
    }

    /** One tattered sail row across the ship at the given column: wool dither + holes. */
    private static void sailRow(ServerLevel limbo, int x, int y, int halfSpan, double holeChance) {
        for (int dz = -halfSpan; dz <= halfSpan; dz++) {
            double h = hash01(x, y, dz);
            if (h < holeChance) {
                continue; // wind-eaten hole
            }
            BlockState cloth = h > 0.8D
                    ? Blocks.GRAY_WOOL.defaultBlockState()
                    : Blocks.BLACK_WOOL.defaultBlockState();
            set(limbo, x, y, dz, cloth);
        }
    }

    // ------------------------------------------------------------------ spawn platform

    /**
     * The starboard ghost-arrival platform and walkway, exactly where v1 put them (the
     * {@link #platformArrivalPos} contract), plus corner posts and two soul lanterns.
     */
    private static void spawnPlatform(ServerLevel limbo, int deckY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = 10; dz <= 14; dz++) {
                set(limbo, dx, deckY, dz, planks);
            }
        }
        for (int dz = HALF_WIDTH + 1; dz <= 9; dz++) {
            for (int dx = -1; dx <= 1; dx++) {
                set(limbo, dx, deckY, dz, planks);
            }
        }
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        for (int sideX = -1; sideX <= 1; sideX += 2) {
            set(limbo, 2 * sideX, deckY + 1, 10, fence);
            set(limbo, 2 * sideX, deckY + 1, 14, fence);
            set(limbo, 2 * sideX, deckY + 2, 14, Blocks.SOUL_LANTERN.defaultBlockState());
        }
    }

    // ------------------------------------------------------------------ shared geometry

    /**
     * Feet-level arrival position in the middle of the spawn platform (see {@link #build}),
     * one block above the deck. Banned ghosts ({@code BanService}) and {@code /eclipse tp_limbo}
     * land here — NOT at the shared world spawn, which sits far from the ship over open
     * (drownable) ocean.
     */
    public static BlockPos platformArrivalPos(ServerLevel limbo) {
        return new BlockPos(0, waterlineY(limbo) + 4, 12);
    }

    /** Hull half width at the given X offset; tapers towards bow and stern. */
    public static int halfWidthAt(int dx) {
        int d = Math.abs(dx);
        if (d <= 12) {
            return HALF_WIDTH;
        }
        if (d <= 15) {
            return 3;
        }
        if (d <= 17) {
            return 2;
        }
        return 1;
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        // Force-load like LimboSeascape: bow/stern extents can poke past the loaded ring
        // during a cold server start.
        level.getChunk(x >> 4, z >> 4);
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_ALL);
    }

    /** Fixed-seed positional hash (0..1); mirrors the LimboSeascape mixer, local salt. */
    private static double hash01(int x, int y, int z) {
        long h = DiscMapData.ECLIPSE_SEED ^ (x * 979025471173L + y * 651372456529L + z * 293742185563L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
    }
}
