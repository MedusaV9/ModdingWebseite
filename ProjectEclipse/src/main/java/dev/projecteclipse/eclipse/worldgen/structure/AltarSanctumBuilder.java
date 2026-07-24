package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.registry.EclipseBlocks;
import dev.projecteclipse.eclipse.worldgen.DiscChunkGenerator;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CandleBlock;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.SlabBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.SlabType;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * P6-W4 v2 entry point of the "Sanctum of the Occluded Sun": stage gate + version guard
 * + delegates (GhostShipBuilder pattern: pure deterministic setBlock loops on
 * {@link ServerStartedEvent}).
 *
 * <p><b>Version flow ({@link SanctumVersionData}):</b></p>
 * <ul>
 *   <li><b>Stage 0 (pre-intro):</b> the v1 GROUNDED sanctum builds on the flat spawn pad
 *       ({@link #build}) exactly as before — three concentric polished-blackstone dais
 *       steps (r 5/3.5/2 at ground+1/+2/+3, 15% cracked, slab edge), the altar at
 *       ground+{@value #ALTAR_ABOVE_GROUND}, 8 pillars on the
 *       r={@value #PILLAR_RING_RADIUS} ring every 45° (2×2 obsidian base + purpur shafts,
 *       heights {@link #PILLAR_SHAFT_HEIGHTS}, three snapped, four with lantern arms),
 *       floating glass + crying-obsidian halos, decor, 4 approach paths, flattened
 *       r={@value #FLATTEN_RADIUS} grounds.</li>
 *   <li><b>Stage 1+ (post-intro fusion):</b> the sanctum is torn out of the disc —
 *       {@link FloatingSanctumBuilder} rebuilds it as a floating island
 *       {@value FloatingSanctumBuilder#ISLAND_LIFT} blocks up with the
 *       {@link SanctumCrater} wound below, a switchback-bridge walk from the re-pinned
 *       crater-rim spawn, glide-notch rim geometry and the W5 orbital anchor data. The
 *       flip happens on boot when the committed overworld stage is already ≥
 *       {@value #FLOATING_MIN_STAGE}, or live via a {@link WorldStageService.StageListener}
 *       the moment the intro's stage-1 terrain sweep completes. One-way and idempotent:
 *       once {@link SanctumVersionData#VERSION_FLOATING} is stamped, boots make ZERO
 *       block changes — except a one-shot ADDITIVE geometry dress migration when the
 *       island {@link SanctumVersionData#revision() revision} is behind
 *       {@link SanctumVersionData#REVISION_ISLAND_V3} (W4-ISLAND; pre-v3 floating saves
 *       gain the tendrils/islets/rune-ring/terraces exactly once, then go terminal).</li>
 * </ul>
 *
 * <p><b>Altar contract:</b> every consumer (rituals, Herald summon, sunmotes, shard
 * economy, goal tracker) keys off {@link EclipseWorldState#getSanctumAltarPos()}, which is
 * re-persisted through the existing {@code setSanctumBuilt} path whenever the altar moves
 * up onto the island; {@code AltarBlockEntity} holds only transient interaction state, so
 * the relocation is lossless. A pre-existing admin-placed altar still centers the build
 * ({@link #findExistingAltar}). The world spawn is re-pinned every start — south approach
 * path while grounded, crater-rim south plaza once floating — never inside the dais.</p>
 *
 * <p><b>W11 (Herald) API:</b> {@link #pillarBases(BlockPos)} + {@link #pillarTopY} expose
 * the exact pillar geometry for line-of-sight cover. Their formulas are UNCHANGED and
 * relative to {@code altarPos} — on the island the ring simply rides the altar up.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AltarSanctumBuilder {
    /** Pillar ring radius around the altar axis (blueprint: 8 pillars every 45°). */
    public static final int PILLAR_RING_RADIUS = 9;
    /** Purpur shaft heights per pillar index (angle = index · 45° from +X towards +Z). */
    public static final int[] PILLAR_SHAFT_HEIGHTS = {4, 6, 7, 5, 6, 4, 7, 5};
    /** Indices of the three "snapped" pillars finished with deepslate wall stumps. */
    private static final int[] SNAPPED_PILLARS = {0, 3, 5};
    /** Indices of the four tall pillars carrying chained soul lanterns. */
    private static final int[] LANTERN_PILLARS = {1, 2, 4, 6};
    /** Flattening radius of the sanctum grounds. */
    public static final int FLATTEN_RADIUS = 12;
    /** Vertical offset of the altar block above the flattened ground surface. */
    public static final int ALTAR_ABOVE_GROUND = 4;
    /** First overworld stage (intro fusion) at which the sanctum flips to the island. */
    public static final int FLOATING_MIN_STAGE = 1;

    /** Stage-listener registration is once per JVM ({@code LISTENERS} is a static list). */
    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private AltarSanctumBuilder() {}

    /** Registers the stage listener that flips the sanctum live when stage 1 completes. */
    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(AltarSanctumBuilder::onStageTerrainComplete);
            EclipseMod.LOGGER.info("AltarSanctumBuilder registered as world-stage listener (island flip at stage {})",
                    FLOATING_MIN_STAGE);
        }
    }

    /**
     * Runs at LOW priority so {@code DiscSpawnPlacement} (HIGH) has already pinned the
     * spawn to the pad center — the sanctum then takes over and re-pins it onto the south
     * approach (grounded) or the crater-rim plaza (floating).
     */
    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onServerStarted(ServerStartedEvent event) {
        ensureSanctum(event.getServer());
    }

    /**
     * Live stage-0→1 flip: the moment the intro fusion's terrain sweep completes, the
     * grounded sanctum is torn out into the floating island (version-gated no-op on
     * every later sweep). Fires on the server thread per the stage-service contract.
     */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile != DiscProfile.OVERWORLD || toStage < FLOATING_MIN_STAGE) {
            return;
        }
        if (SanctumVersionData.get(level).version() >= SanctumVersionData.VERSION_FLOATING) {
            return;
        }
        EclipseMod.LOGGER.info("Sanctum stage listener: overworld stage {} -> {} complete — flipping the sanctum to the floating island",
                fromStage, toStage);
        ensureSanctum(level.getServer());
    }

    /**
     * Single idempotent entry: builds/upgrades whatever the committed overworld stage and
     * {@link SanctumVersionData} demand, then re-pins spawn and refreshes protection.
     * With a matching version already stamped this makes ZERO block changes (the
     * restart-idempotence contract — grep "idempotent boot" in the log).
     */
    static void ensureSanctum(MinecraftServer server) {
        ServerLevel overworld = server.overworld();
        if (!(overworld.getChunkSource().getGenerator() instanceof DiscChunkGenerator)) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        SanctumVersionData version = SanctumVersionData.get(overworld);
        if (version.version() == SanctumVersionData.VERSION_NONE && state.isSanctumBuilt()) {
            // Pre-versioning world: a grounded sanctum exists but never got stamped.
            version.setVersion(SanctumVersionData.VERSION_GROUNDED);
            EclipseMod.LOGGER.info("Sanctum version adopt: legacy grounded sanctum stamped as v1");
        }
        int stage = WorldStageService.stage(server, DiscProfile.OVERWORLD);
        BlockPos altarPos = state.getSanctumAltarPos();
        boolean floating = version.version() >= SanctumVersionData.VERSION_FLOATING;
        if (stage >= FLOATING_MIN_STAGE && !floating) {
            altarPos = FloatingSanctumBuilder.buildOrUpgrade(overworld, altarPos);
            state.setSanctumBuilt(altarPos);
            version.setVersion(SanctumVersionData.VERSION_FLOATING);
            version.setRevision(SanctumVersionData.REVISION_ISLAND_V3);
            floating = true;
        } else if (altarPos == null) {
            altarPos = build(overworld);
            state.setSanctumBuilt(altarPos);
            version.setVersion(SanctumVersionData.VERSION_GROUNDED);
        } else if (floating && version.revision() < SanctumVersionData.REVISION_ISLAND_V3) {
            // W4-ISLAND: pre-v3 floating save — run the additive geometry v3 dress pass
            // once (no clears, player builds untouched) and stamp the revision terminal.
            FloatingSanctumBuilder.upgradeToV3(overworld, altarPos);
            version.setRevision(SanctumVersionData.REVISION_ISLAND_V3);
        } else {
            EclipseMod.LOGGER.info("Sanctum v{} (rev {}) present at {} — idempotent boot, zero block changes",
                    version.version(), version.revision(), altarPos.toShortString());
        }
        repinSpawn(overworld, altarPos, floating);
        SanctumProtection.refresh(server);
    }

    /**
     * World spawn re-pin, never inside the dais: south approach path while grounded,
     * crater-rim south plaza (start of the bridge walk) once the island is up.
     */
    private static void repinSpawn(ServerLevel overworld, BlockPos altarPos, boolean floating) {
        int walkGroundY = floating
                ? FloatingSanctumBuilder.groundY(altarPos)
                : altarPos.getY() - ALTAR_ABOVE_GROUND;
        int southOffset = floating ? FloatingSanctumBuilder.SPAWN_SOUTH_OFFSET : 8;
        BlockPos spawn = new BlockPos(altarPos.getX(), walkGroundY + 1, altarPos.getZ() + southOffset);
        overworld.setDefaultSpawnPos(spawn, 180.0F);
        EclipseMod.LOGGER.info("Sanctum active: spawn re-pinned to ({}, {}, {}) on the {} (altar {})",
                spawn.getX(), spawn.getY(), spawn.getZ(),
                floating ? "crater-rim south plaza" : "south approach path", altarPos.toShortString());
    }

    /**
     * Unconditionally builds the GROUNDED (v1, stage-0) sanctum, centering on a
     * pre-existing altar block near spawn when there is one (that block is preserved
     * untouched). Returns the altar pos. The floating v2 island reuses every sanctum-top
     * builder below with the island top as its ground, so both versions stay identical
     * from the dais up.
     */
    public static BlockPos build(ServerLevel level) {
        BlockPos existingAltar = findExistingAltar(level);
        int groundY;
        BlockPos altarPos;
        if (existingAltar != null) {
            altarPos = existingAltar;
            groundY = existingAltar.getY() - ALTAR_ABOVE_GROUND;
            EclipseMod.LOGGER.info("Sanctum centering on existing altar at {} (block + block entity preserved)",
                    existingAltar.toShortString());
        } else {
            groundY = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, 0, 0);
            altarPos = new BlockPos(0, groundY + ALTAR_ABOVE_GROUND, 0);
        }
        int cx = altarPos.getX();
        int cz = altarPos.getZ();

        flattenGrounds(level, cx, cz, groundY, altarPos);
        buildDais(level, cx, cz, groundY);
        buildPillars(level, cx, cz, groundY, altarPos);
        buildFloatingRings(level, cx, cz, groundY);
        buildDecor(level, cx, cz, groundY);
        buildApproachPaths(level, cx, cz, groundY);
        if (existingAltar == null) {
            set(level, altarPos, EclipseBlocks.ALTAR.get().defaultBlockState());
        }
        SundialPlaza.buildDial(level, altarPos);
        SundialPlaza.placeShadow(level, altarPos,
                EclipseWorldState.get(level.getServer()).getDay());
        EclipseMod.LOGGER.info("Altar sanctum built: altar {}, dais base y{}, pillar ring r={}, flattened r={}",
                altarPos.toShortString(), groundY + 1, PILLAR_RING_RADIUS, FLATTEN_RADIUS);
        return altarPos;
    }

    /** An admin-placed altar within r=12 of the spawn column, or {@code null}. */
    @Nullable
    static BlockPos findExistingAltar(ServerLevel level) {
        int surface = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, 0, 0);
        for (BlockPos pos : BlockPos.betweenClosed(-FLATTEN_RADIUS, surface - 10, -FLATTEN_RADIUS,
                FLATTEN_RADIUS, surface + 20, FLATTEN_RADIUS)) {
            level.getChunk(pos.getX() >> 4, pos.getZ() >> 4);
            if (level.getBlockState(pos).is(EclipseBlocks.ALTAR.get())) {
                return pos.immutable();
            }
        }
        return null;
    }

    /** Flattens r=12 to {@code groundY}: rubble-mixed top, cleared airspace, filled dips. */
    private static void flattenGrounds(ServerLevel level, int cx, int cz, int groundY, BlockPos altarPos) {
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -FLATTEN_RADIUS; dx <= FLATTEN_RADIUS; dx++) {
            for (int dz = -FLATTEN_RADIUS; dz <= FLATTEN_RADIUS; dz++) {
                if (dx * dx + dz * dz > FLATTEN_RADIUS * FLATTEN_RADIUS) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                level.getChunk(x >> 4, z >> 4);
                for (int y = groundY + 1; y <= groundY + 25; y++) {
                    cursor.set(x, y, z);
                    if (cursor.equals(altarPos)) {
                        continue; // never touch a pre-existing altar block
                    }
                    if (!level.getBlockState(cursor).isAir()) {
                        level.setBlock(cursor, air, 2);
                    }
                }
                for (int y = groundY - 3; y < groundY; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isSolidRender(level, cursor)) {
                        level.setBlock(cursor, Blocks.DIRT.defaultBlockState(), 2);
                    }
                }
                set(level, new BlockPos(x, groundY, z), groundMix(x, z));
            }
        }
    }

    /** Flattened-grounds surface mix (also used by the sundial to erase its shadow line). */
    static BlockState groundMix(int x, int z) {
        double roll = FallbackBuilders.hash01(x, 7, z);
        if (roll < 0.20D) {
            return Blocks.COARSE_DIRT.defaultBlockState();
        }
        if (roll < 0.25D) {
            return Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        }
        return Blocks.GRASS_BLOCK.defaultBlockState();
    }

    /**
     * Three concentric dais steps (r 5/3.5/2 at ground+1/+2/+3) with a slab skirt.
     * Package-private: {@link FloatingSanctumBuilder} reuses it with the island top as
     * {@code groundY} (same for the pillar/halo/decor/path builders below).
     */
    static void buildDais(ServerLevel level, int cx, int cz, int groundY) {
        double[] radii = {5.0D, 3.5D, 2.0D};
        for (int step = 0; step < radii.length; step++) {
            int y = groundY + 1 + step;
            for (int dx = -6; dx <= 6; dx++) {
                for (int dz = -6; dz <= 6; dz++) {
                    double r = Math.sqrt(dx * dx + dz * dz);
                    if (r <= radii[step]) {
                        set(level, new BlockPos(cx + dx, y, cz + dz), daisMix(cx + dx, y, cz + dz));
                    } else if (step == 0 && r <= 6.0D) {
                        set(level, new BlockPos(cx + dx, y, cz + dz),
                                Blocks.POLISHED_BLACKSTONE_SLAB.defaultBlockState());
                    }
                }
            }
        }
    }

    /** Blueprint: polished blackstone with 15% cracked (brick) variants. */
    private static BlockState daisMix(int x, int y, int z) {
        return FallbackBuilders.hash01(x, y, z) < 0.15D
                ? Blocks.CRACKED_POLISHED_BLACKSTONE_BRICKS.defaultBlockState()
                : Blocks.POLISHED_BLACKSTONE.defaultBlockState();
    }

    /** 8 pillars on the r=9 ring: obsidian bases, purpur shafts, snapped tops, lanterns. */
    static void buildPillars(ServerLevel level, int cx, int cz, int groundY, BlockPos altarPos) {
        BlockState obsidian = Blocks.OBSIDIAN.defaultBlockState();
        for (int k = 0; k < 8; k++) {
            BlockPos corner = pillarBaseCorner(altarPos, k);
            int shaftHeight = PILLAR_SHAFT_HEIGHTS[k];
            for (int ox = 0; ox <= 1; ox++) {
                for (int oz = 0; oz <= 1; oz++) {
                    int x = corner.getX() + ox;
                    int z = corner.getZ() + oz;
                    set(level, new BlockPos(x, groundY + 1, z), obsidian);
                    set(level, new BlockPos(x, groundY + 2, z), obsidian);
                    for (int h = 0; h < shaftHeight; h++) {
                        set(level, new BlockPos(x, groundY + 3 + h, z),
                                Blocks.PURPUR_PILLAR.defaultBlockState());
                    }
                }
            }
            int topY = pillarTopY(altarPos, k);
            if (isSnapped(k)) {
                // Broken-off stump: deepslate walls on three of the four shaft-top blocks.
                set(level, new BlockPos(corner.getX(), topY + 1, corner.getZ()),
                        Blocks.COBBLED_DEEPSLATE_WALL.defaultBlockState());
                set(level, new BlockPos(corner.getX() + 1, topY + 1, corner.getZ()),
                        Blocks.COBBLED_DEEPSLATE_WALL.defaultBlockState());
                set(level, new BlockPos(corner.getX(), topY + 1, corner.getZ() + 1),
                        Blocks.COBBLED_DEEPSLATE_WALL.defaultBlockState());
            }
            if (isLanternPillar(k)) {
                buildLanternArm(level, corner, topY, cx, cz);
            }
        }
    }

    /** Purpur arm reaching towards the altar with a chained soul lantern below. */
    private static void buildLanternArm(ServerLevel level, BlockPos corner, int topY, int cx, int cz) {
        Direction towardsAltar = Direction.getNearest(cx - corner.getX(), 0, cz - corner.getZ());
        BlockPos arm = new BlockPos(corner.getX(), topY, corner.getZ()).relative(towardsAltar);
        set(level, arm, Blocks.PURPUR_PILLAR.defaultBlockState()
                .setValue(RotatedPillarBlock.AXIS, towardsAltar.getAxis()));
        set(level, arm.below(), Blocks.CHAIN.defaultBlockState());
        set(level, arm.below(2), Blocks.SOUL_LANTERN.defaultBlockState()
                .setValue(LanternBlock.HANGING, true));
    }

    /** Unsupported eclipse-halo rings floating over the dais. */
    static void buildFloatingRings(ServerLevel level, int cx, int cz, int groundY) {
        // r=4 purple glass ring at y0+8, every other block.
        int glassY = groundY + 1 + 8;
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                double r = Math.sqrt(dx * dx + dz * dz);
                if (r >= 3.5D && r <= 4.5D && Math.floorMod(dx + dz, 2) == 0) {
                    set(level, new BlockPos(cx + dx, glassY, cz + dz),
                            Blocks.PURPLE_STAINED_GLASS.defaultBlockState());
                }
            }
        }
        // r=2.5 crying obsidian ring at y0+11, cardinals only.
        int cryY = groundY + 1 + 11;
        for (Direction cardinal : Direction.Plane.HORIZONTAL) {
            set(level, new BlockPos(cx, cryY, cz).relative(cardinal, 2),
                    Blocks.CRYING_OBSIDIAN.defaultBlockState());
        }
    }

    /** Amethyst clusters, sculk veins, purple candles. */
    static void buildDecor(ServerLevel level, int cx, int cz, int groundY) {
        // Amethyst clusters on 6 exposed dais-base blocks (r≈4.3 ring, top face).
        for (int i = 0; i < 6; i++) {
            double angle = Math.toRadians(15.0D + i * 60.0D);
            int x = cx + (int) Math.round(Math.cos(angle) * 4.3D);
            int z = cz + (int) Math.round(Math.sin(angle) * 4.3D);
            set(level, new BlockPos(x, groundY + 2, z), Blocks.AMETHYST_CLUSTER.defaultBlockState());
        }
        // Sculk veins on 20% of the dais perimeter ground (outside the slab skirt).
        for (int dx = -8; dx <= 8; dx++) {
            for (int dz = -8; dz <= 8; dz++) {
                double r = Math.sqrt(dx * dx + dz * dz);
                if (r > 6.0D && r <= 7.5D && FallbackBuilders.hash01(cx + dx, 3, cz + dz) < 0.20D) {
                    set(level, new BlockPos(cx + dx, groundY + 1, cz + dz),
                            Blocks.SCULK_VEIN.defaultBlockState()
                                    .setValue(BlockStateProperties.DOWN, true));
                }
            }
        }
        // Four diagonal stands of three purple candles (unlit — altar L2 lights them).
        for (int sx = -1; sx <= 1; sx += 2) {
            for (int sz = -1; sz <= 1; sz += 2) {
                set(level, new BlockPos(cx + 5 * sx, groundY + 1, cz + 5 * sz),
                        Blocks.PURPLE_CANDLE.defaultBlockState().setValue(CandleBlock.CANDLES, 3));
            }
        }
    }

    /** Four cardinal approach paths (length 5, width 2) of flush top slabs. */
    static void buildApproachPaths(ServerLevel level, int cx, int cz, int groundY) {
        BlockState pathSlab = Blocks.POLISHED_BLACKSTONE_SLAB.defaultBlockState()
                .setValue(SlabBlock.TYPE, SlabType.TOP);
        for (Direction cardinal : Direction.Plane.HORIZONTAL) {
            for (int d = 6; d <= 10; d++) {
                for (int w = -1; w <= 0; w++) {
                    BlockPos pos = new BlockPos(cx, groundY, cz)
                            .relative(cardinal, d).relative(cardinal.getClockWise(), w);
                    set(level, pos, pathSlab);
                }
            }
        }
    }

    // --- pillar geometry API (W11: Herald uses the pillars as LOS cover) ---

    /**
     * North-west corner of the 2×2 base of pillar {@code index} (0..7, angle = index·45°
     * from +X towards +Z on the r={@value #PILLAR_RING_RADIUS} ring). The base occupies
     * this block and +1 on both horizontal axes, from ground+1 (= altarY − 3) upward.
     */
    public static BlockPos pillarBaseCorner(BlockPos altarPos, int index) {
        double angle = Math.toRadians(index * 45.0D);
        int px = altarPos.getX() + (int) Math.round(Math.cos(angle) * PILLAR_RING_RADIUS);
        int pz = altarPos.getZ() + (int) Math.round(Math.sin(angle) * PILLAR_RING_RADIUS);
        return new BlockPos(px, altarPos.getY() - 3, pz);
    }

    /** All 8 pillar base corners (see {@link #pillarBaseCorner}), index order. */
    public static List<BlockPos> pillarBases(BlockPos altarPos) {
        List<BlockPos> bases = new ArrayList<>(8);
        for (int k = 0; k < 8; k++) {
            bases.add(pillarBaseCorner(altarPos, k));
        }
        return bases;
    }

    /** Y of the highest solid shaft block of pillar {@code index}. */
    public static int pillarTopY(BlockPos altarPos, int index) {
        int groundY = altarPos.getY() - ALTAR_ABOVE_GROUND;
        return groundY + 2 + PILLAR_SHAFT_HEIGHTS[index];
    }

    private static boolean isSnapped(int index) {
        for (int snapped : SNAPPED_PILLARS) {
            if (snapped == index) {
                return true;
            }
        }
        return false;
    }

    private static boolean isLanternPillar(int index) {
        for (int lantern : LANTERN_PILLARS) {
            if (lantern == index) {
                return true;
            }
        }
        return false;
    }

    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_ALL);
    }
}
