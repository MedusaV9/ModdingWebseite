package dev.projecteclipse.eclipse.woah.chronostasis;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * WOAH-03 site lifecycle (plan §2): materializes the Chrono-Stasis clearing when the
 * overworld stage-3 terrain sweep completes — the exact {@code FogStormSites} two-phase
 * shape (stage listener → {@link StructurePendingRegistry#enqueue} → async placer →
 * {@link SitePrep#preparePlateau} → budgeted carve → {@link SitePrep#finish}).
 *
 * <p>The landmark row {@code eclipse:chrono_stasis, -24, 240, 26, 3} already lives in
 * {@code DiscMapDefaults.overworldDefaults()}; this class only READS the frozen landmark
 * (falling back to the mirrored constants below). On success it persists
 * {@code placed=true} + rolls the scene seed in {@link ChronoStasisData}, publishes the
 * {@link FxAnchors#CHRONO_CENTER} anchor and hands off to {@link ChronoStasisService}
 * (scene reconcile, aura, statemachine). Server-start restore re-publishes the anchor for
 * already-placed saves; stage rollback tears the scene down and resets the flags.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ChronoStasisSite {
    /** Landmark id in {@code DiscMapDefaults} AND pending-registry structure/site id. */
    public static final String STRUCTURE_ID = "eclipse:chrono_stasis";
    /** Stage gate — mirrors the frozen landmark row (stage 3, Forest-Wedge). */
    public static final int STAGE = 3;

    // Single source set for the client classes (plan §2.2): landmark constants mirrored.
    public static final int CENTER_X = -24;
    public static final int CENTER_Z = 240;
    /** Gameplay/grade radius (slowness aura, grade ease target, tick sound). */
    public static final int RADIUS = 26;
    /** Photon rain-field radius — slightly larger so the edge transition reads soft. */
    public static final int FX_RADIUS = 34;
    /** Carved sink radius (cosine bowl, depth {@value #BOWL_DEPTH} at the center). */
    public static final int BOWL_RADIUS = 24;
    /** Sink depth at the center (blocks). */
    public static final double BOWL_DEPTH = 3.0D;

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private ChronoStasisSite() {}

    // ------------------------------------------------------------------ shared geometry

    /**
     * Depth of the carved bowl at local offset (dx, dz) — cosine bell, {@value #BOWL_DEPTH}
     * at the center, 0 at r ≥ {@value #BOWL_RADIUS}. {@link ChronoSceneBuilder#floorY}
     * mirrors this (the carve and the scene share one law).
     */
    public static double bowlDepth(double dx, double dz) {
        double dist = Math.hypot(dx, dz);
        if (dist >= BOWL_RADIUS) {
            return 0.0D;
        }
        return BOWL_DEPTH * (0.5D + 0.5D * Math.cos(Math.PI * dist / BOWL_RADIUS));
    }

    /** Frozen landmark center (x, z) — reads the {@code DiscMapData} row, else constants. */
    public static BlockPos landmarkXZ() {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.OVERWORLD)) {
            if (STRUCTURE_ID.equals(landmark.id())) {
                return new BlockPos(landmark.x(), 0, landmark.z());
            }
        }
        return new BlockPos(CENTER_X, 0, CENTER_Z);
    }

    /** Site center at the terraformed surface Y (FogStormSites.surfaceCenter recipe). */
    public static BlockPos surfaceCenter(ServerLevel level) {
        BlockPos xz = landmarkXZ();
        int y = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, xz.getX(), xz.getZ());
        if (y <= level.getMinBuildHeight()) {
            y = DiscMapData.get().surfaceOverrideAt(xz.getX(), xz.getZ());
            if (y <= level.getMinBuildHeight()) {
                y = (int) DiscProfile.OVERWORLD.surfaceBaseY();
            }
        }
        return new BlockPos(xz.getX(), y, xz.getZ());
    }

    // ------------------------------------------------------------------ lifecycle events

    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(ChronoStasisSite::onStageTerrainComplete);
            EclipseMod.LOGGER.info("ChronoStasisSite registered as world-stage listener");
        }
        StructurePendingRegistry.registerAsyncPlacer(STRUCTURE_ID,
                (level, pending, complete, failure) -> materialize(level, complete, failure));
    }

    /** Restart restore: an already-placed site re-publishes its anchor + wakes the service. */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        ServerLevel level = event.getServer().overworld();
        ChronoStasisData data = ChronoStasisData.get(event.getServer());
        if (data.placed()) {
            BlockPos center = surfaceCenter(level);
            FxAnchors.set(FxAnchors.CHRONO_CENTER, level, ChronoSceneBuilder.sphereCenter(center));
            ChronoStasisService.onSitePlaced(level, center);
            EclipseMod.LOGGER.info("ChronoStasisSite: restored placed site at {}", center);
        }
    }

    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile != DiscProfile.OVERWORLD) {
            return;
        }
        if (toStage <= fromStage) {
            // Stage rollback (dev erase): tear the scene down if the site's stage is gone.
            if (STAGE > toStage) {
                rollback(level);
            }
            return;
        }
        if (STAGE > toStage || STAGE <= fromStage) {
            return;
        }
        BlockPos center = surfaceCenter(level);
        StructurePendingRegistry.enqueue(new PendingSite(STRUCTURE_ID, STRUCTURE_ID,
                DiscProfile.OVERWORLD.name(), center, STAGE, RADIUS * 2, level.getGameTime()));
    }

    // ------------------------------------------------------------------ materialize

    /**
     * Two-phase materialization (FogStormSites.materializeSite shape): plateau prep, then
     * a budgeted carve sweep (bowl + broken birches + blast crater + tower stump), then
     * relight/resend, SavedData flags, anchor publish and service hand-off. Exactly one of
     * {@code onComplete}/{@code onFailure} fires.
     */
    public static void materialize(ServerLevel level, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        ChronoStasisData data = ChronoStasisData.get(level.getServer());
        if (data.placed()) {
            onComplete.run();
            return;
        }
        BlockPos center = surfaceCenter(level);
        int surfaceY = center.getY();
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                center.getX() - RADIUS, center.getZ() - RADIUS,
                center.getX() + RADIUS, center.getZ() + RADIUS, center);
        prepared.whenReady(() -> carveClearing(level, center, surfaceY, () -> {
            placeTowerStump(level, center, surfaceY);
            placeBrokenBirches(level, center, surfaceY);
            SitePrep.touchBounds(prepared,
                    center.getX() - RADIUS, center.getZ() - RADIUS,
                    center.getX() + RADIUS, center.getZ() + RADIUS);
            SitePrep.finish(level, prepared);
            if (data.sceneSeed() == 0L) {
                data.setSceneSeed(FrozenParams.mapSeed() ^ 0xC4805EEDL);
            }
            data.setPlaced(true);
            FxAnchors.set(FxAnchors.CHRONO_CENTER, level, ChronoSceneBuilder.sphereCenter(center));
            ChronoStasisService.onSitePlaced(level, center);
            EclipseMod.LOGGER.info("ChronoStasisSite: materialized at {}", center);
            onComplete.run();
        }, onFailure), onFailure);
    }

    /** Stage-rollback teardown: displays + pad discarded, anchor removed, flags reset. */
    public static void rollback(ServerLevel level) {
        ChronoStasisData data = ChronoStasisData.get(level.getServer());
        if (!data.placed()) {
            return;
        }
        BlockPos center = surfaceCenter(level);
        int discarded = ChronoSceneBuilder.discardAllTagged(level, center);
        ChronoStasisService.onSiteRemoved(level, center);
        FxAnchors.remove(FxAnchors.CHRONO_CENTER, level);
        data.setPlaced(false);
        data.setJoltCount(0);
        // rewardClaimed/discharges survive on purpose — a regrow must not re-drop the core.
        EclipseMod.LOGGER.info("ChronoStasisSite: rolled back ({} display(s) discarded)", discarded);
    }

    // ------------------------------------------------------------------ terraforming

    /**
     * Budgeted column sweep over the 53×53 footprint (plan §2.3): carves the cosine bowl
     * (air out to +10 over the old surface inside r {@value #BOWL_RADIUS}), paints the
     * moss/coarse-dirt/podzol core, and sinks the 2×2 blackstone/magma blast crater. No
     * water on purpose. Runs on the {@link BudgetedBlockWriter} rail like every site job.
     */
    private static void carveClearing(ServerLevel level, BlockPos center, int surfaceY,
            Runnable onComplete, Consumer<Throwable> onFailure) {
        int radius = RADIUS;
        int span = radius * 2 + 1;
        int total = span * span;
        int[] cursor = {0};
        BudgetedBlockWriter.enqueue(level, budget -> {
            int end = Math.min(total, cursor[0] + budget);
            for (; cursor[0] < end; cursor[0]++) {
                int dx = cursor[0] % span - radius;
                int dz = cursor[0] / span - radius;
                if (dx * dx + dz * dz <= radius * radius) {
                    carveColumn(level, center, surfaceY, dx, dz);
                }
            }
            return cursor[0] >= total;
        }, onComplete, onFailure);
    }

    private static void carveColumn(ServerLevel level, BlockPos center, int surfaceY,
            int dx, int dz) {
        int x = center.getX() + dx;
        int z = center.getZ() + dz;
        double dist = Math.hypot(dx, dz);
        if (dist >= BOWL_RADIUS) {
            return; // ring: edge birches stay untouched
        }
        int depth = (int) Math.round(bowlDepth(dx, dz));
        int floorY = surfaceY - depth;
        // Clear the bowl air space (removes grass/foliage/trunks inside the clearing).
        for (int y = floorY + 1; y <= surfaceY + 10; y++) {
            BlockPos pos = new BlockPos(x, y, z);
            if (!level.getBlockState(pos).isAir()) {
                level.setBlock(pos, Blocks.AIR.defaultBlockState(), 3);
            }
        }
        // Blast crater (plan §5.2 "Quelle am Boden"): 2×2 at local (−2, −10).
        boolean crater = (dx == ChronoSceneBuilder.BLAST_DX || dx == ChronoSceneBuilder.BLAST_DX + 1)
                && (dz == ChronoSceneBuilder.BLAST_DZ || dz == ChronoSceneBuilder.BLAST_DZ + 1);
        BlockState floor;
        if (crater) {
            floor = Math.floorMod(x + z, 2) == 0
                    ? Blocks.BLACKSTONE.defaultBlockState()
                    : Blocks.MAGMA_BLOCK.defaultBlockState();
        } else if (dist <= 16.0D) {
            int hash = Math.floorMod(x * 31 + z * 17, 7);
            floor = switch (hash) {
                case 0, 1, 2 -> Blocks.MOSS_BLOCK.defaultBlockState();
                case 3, 4 -> Blocks.COARSE_DIRT.defaultBlockState();
                default -> Blocks.PODZOL.defaultBlockState();
            };
        } else {
            floor = Blocks.GRASS_BLOCK.defaultBlockState();
        }
        level.setBlock(new BlockPos(x, floorY, z), floor, 3);
        // Keep the slope solid where the carve exposed the block below the new floor.
        BlockPos below = new BlockPos(x, floorY - 1, z);
        if (!level.getBlockState(below).isSolid()) {
            level.setBlock(below, Blocks.DIRT.defaultBlockState(), 3);
        }
    }

    /**
     * East-rim watchtower foundation (plan §2.3): a 6×6 hollow wall ring at local
     * (+14, −6), 4–7 high with an irregularly broken top — real blocks (the flying debris
     * above it are displays; Kulisse law: displays never change the world, foundations do).
     */
    private static void placeTowerStump(ServerLevel level, BlockPos center, int surfaceY) {
        RandomSource random = RandomSource.create(FrozenParams.mapSeed() ^ 0x70335L);
        int baseX = center.getX() + ChronoSceneBuilder.TOWER_DX;
        int baseZ = center.getZ() + ChronoSceneBuilder.TOWER_DZ;
        int baseY = surfaceY - (int) Math.round(
                bowlDepth(ChronoSceneBuilder.TOWER_DX, ChronoSceneBuilder.TOWER_DZ));
        for (int dx = -3; dx <= 2; dx++) {
            for (int dz = -3; dz <= 2; dz++) {
                boolean wall = dx == -3 || dx == 2 || dz == -3 || dz == 2;
                if (!wall) {
                    // Interior: a walkable stone-brick floor slab-of-blocks at the base.
                    level.setBlock(new BlockPos(baseX + dx, baseY, baseZ + dz),
                            Blocks.STONE_BRICKS.defaultBlockState(), 3);
                    continue;
                }
                int height = 4 + random.nextInt(4); // 4–7, broken irregularly per column
                for (int dy = 0; dy <= height; dy++) {
                    if (dy == height && random.nextFloat() < 0.4F) {
                        continue; // jagged top
                    }
                    BlockState state = switch (random.nextInt(5)) {
                        case 0 -> Blocks.CRACKED_STONE_BRICKS.defaultBlockState();
                        case 1 -> Blocks.COBBLESTONE.defaultBlockState();
                        default -> Blocks.STONE_BRICKS.defaultBlockState();
                    };
                    level.setBlock(new BlockPos(baseX + dx, baseY + dy, baseZ + dz), state, 3);
                }
            }
        }
    }

    /**
     * Rim garnish (plan §2.3): 7 birches around the ring snapped to 2–4 trunk blocks,
     * plus 2 short fallen {@code birch_log} lines on the crater rim.
     */
    private static void placeBrokenBirches(ServerLevel level, BlockPos center, int surfaceY) {
        RandomSource random = RandomSource.create(FrozenParams.mapSeed() ^ 0xB19C4E5L);
        for (int i = 0; i < 7; i++) {
            double angle = i * Mth.TWO_PI / 7.0D + random.nextDouble() * 0.4D;
            int x = center.getX() + (int) Math.round(Math.cos(angle) * (BOWL_RADIUS + 0.5D));
            int z = center.getZ() + (int) Math.round(Math.sin(angle) * (BOWL_RADIUS + 0.5D));
            int height = 2 + random.nextInt(3); // 2–4 trunk blocks
            for (int dy = 1; dy <= height; dy++) {
                level.setBlock(new BlockPos(x, surfaceY + dy, z),
                        Blocks.BIRCH_LOG.defaultBlockState(), 3);
            }
        }
        for (int i = 0; i < 2; i++) {
            double angle = 0.9D + i * Math.PI;
            Direction.Axis axis = i == 0 ? Direction.Axis.X : Direction.Axis.Z;
            int x = center.getX() + (int) Math.round(Math.cos(angle) * 21.0D);
            int z = center.getZ() + (int) Math.round(Math.sin(angle) * 21.0D);
            int floorY = surfaceY - (int) Math.round(
                    bowlDepth(x - center.getX(), z - center.getZ()));
            BlockState log = Blocks.BIRCH_LOG.defaultBlockState()
                    .setValue(RotatedPillarBlock.AXIS, axis);
            for (int step = 0; step < 3; step++) {
                BlockPos pos = new BlockPos(
                        x + (axis == Direction.Axis.X ? step : 0), floorY + 1,
                        z + (axis == Direction.Axis.Z ? step : 0));
                if (level.getBlockState(pos).isAir()) {
                    level.setBlock(pos, log, 3);
                }
            }
        }
    }

    /** The Chronosphere world position for the current save (anchor + pad target). */
    public static Vec3 sphereCenter(ServerLevel level) {
        return ChronoSceneBuilder.sphereCenter(surfaceCenter(level));
    }
}
