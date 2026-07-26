package dev.projecteclipse.eclipse.worldgen.structure;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.StructureStart;

/**
 * RIFT-FX (user item: "the animation should spawn the BLOCKS OF THE STRUCTURE") — a
 * dry-run of a pending site's vanilla placement that captures the blocks the placer WILL
 * write, without touching the world. {@code StructureFlightFx} flies these exact states
 * to their exact resting cells, so the delivery preview assembles 1:1 into the structure
 * the game then places.
 *
 * <p><b>How</b>: the same deterministic pipeline as the real placer —
 * {@link StructureStamper#retryAnchor} → {@link StructureStamper#generateVanilla} under
 * the frozen map seed → the {@code VanillaLandmarks.placeVanillaAsync} piece-translation
 * rules (cavity recenter / plateau dy with terrain-matching re-seat, replicated here
 * because that class is owned elsewhere) → {@code StructureStart.placeInChunk} against a
 * <b>capturing {@link WorldGenLevel} proxy</b> that records every {@code setBlock} into a
 * map instead of writing it. Reads forward to the real level (with read-back of captured
 * states so pieces that inspect their own work stay coherent); entity spawns, tick
 * scheduling and block-entity lookups are swallowed — the dry run has zero world effect.
 * The real placer later re-generates the byte-identical start (same seed, same anchor,
 * same nudge) and places it for real; this class never shares state with it.</p>
 *
 * <p><b>Fidelity limits</b> (accepted — the preview is candy, the placer is authority):
 * world state may drift between sampling and placement (players building mid-flight);
 * procedural fallback builds and the {@code UndergroundSites} custom placers are not
 * sampled (no vanilla start) — callers fall back to the palette look for those.</p>
 *
 * <p><b>Budgets</b>: sampling is skipped for footprints over {@value #MAX_FOOTPRINT}
 * blocks, aborts beyond {@value #MAX_CAPTURED_BLOCKS} captured block writes, reduces to
 * the topmost visible block per column, and returns at most {@code maxPieces} samples
 * (deterministic hash-scatter selection). One dry run per delivery, timed and logged.</p>
 */
public final class StructureBlockSampler {
    /** One captured block of the future structure: resting cell + exact state. */
    public record Sample(BlockPos pos, BlockState state) {}

    /** Sites wider than this skip sampling (defensive cap — nothing configured is bigger). */
    private static final int MAX_FOOTPRINT = 150;
    /** Dry-run memory guard: past this many captured writes the sampler gives up. */
    private static final int MAX_CAPTURED_BLOCKS = 200_000;

    /** structureId → (vanilla structure id, prep mode); mirror of {@code registerPlacers}. */
    private static final Map<String, Target> TARGETS = Map.of(
            "eclipse:desert_temple", new Target(vanilla("desert_pyramid"), SitePrep.Mode.PLATEAU),
            "eclipse:jungle_temple", new Target(vanilla("jungle_pyramid"), SitePrep.Mode.PLATEAU),
            "eclipse:village_plains", new Target(vanilla("village_plains"), SitePrep.Mode.PLATEAU),
            "minecraft:pillager_outpost", new Target(vanilla("pillager_outpost"), SitePrep.Mode.PLATEAU),
            "minecraft:mansion", new Target(vanilla("mansion"), SitePrep.Mode.PLATEAU),
            "minecraft:trial_chambers", new Target(vanilla("trial_chambers"), SitePrep.Mode.CAVITY),
            "minecraft:ancient_city", new Target(vanilla("ancient_city"), SitePrep.Mode.CAVITY));

    private record Target(ResourceLocation structure, SitePrep.Mode mode) {}

    private StructureBlockSampler() {}

    private static ResourceLocation vanilla(String path) {
        return ResourceLocation.withDefaultNamespace(path);
    }

    /**
     * Captures the visible blocks (topmost non-air, non-fluid state per column) of the
     * structure {@code site} will place, at their final world positions, or an empty list
     * when the site has no sampleable vanilla start (custom/underground placers, failed
     * generation, oversized footprint, or any error — the dry run must never break a
     * delivery). Deterministic per site: every restartless replay captures the same set.
     */
    public static List<Sample> sampleVisible(ServerLevel level, PendingSite site, int maxPieces) {
        Target target = TARGETS.get(site.structureId());
        if (target == null || maxPieces <= 0 || site.footprint() > MAX_FOOTPRINT) {
            return List.of();
        }
        long startNanos = System.nanoTime();
        try {
            List<Sample> samples = capture(level, site, target, maxPieces);
            EclipseMod.LOGGER.info(
                    "StructureBlockSampler: dry run of {} ({}) captured {} visible piece(s) in {} ms",
                    site.siteId(), site.structureId(), samples.size(),
                    (System.nanoTime() - startNanos) / 1_000_000L);
            return samples;
        } catch (Throwable t) {
            EclipseMod.LOGGER.warn(
                    "StructureBlockSampler: dry run of {} failed after {} ms; falling back to the palette look",
                    site.siteId(), (System.nanoTime() - startNanos) / 1_000_000L, t);
            return List.of();
        }
    }

    private static List<Sample> capture(ServerLevel level, PendingSite site, Target target,
            int maxPieces) {
        int retry = StructurePendingRegistry.failureCount(site.siteId());
        BlockPos anchor = StructureStamper.retryAnchor(level, site, retry);
        StructureStart start = StructureStamper.generateVanilla(level, target.structure(), anchor,
                retry * StructureStamper.VANILLA_ATTEMPTS);
        if (start == null) {
            return List.of();
        }
        translatePieces(level, start, anchor, target.mode());
        BoundingBox bounds = StructureStamper.pieceUnion(start);

        // Mirror placeStart's chunk force-load: the terrain phase already wrote these
        // chunks and the real placer needs them materialized minutes later anyway.
        ChunkPos minChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.minX()),
                SectionPos.blockToSectionCoord(bounds.minZ()));
        ChunkPos maxChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.maxX()),
                SectionPos.blockToSectionCoord(bounds.maxZ()));
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos -> level.getChunk(chunkPos.x, chunkPos.z));

        CaptureHandler capture = new CaptureHandler(level);
        WorldGenLevel captureLevel = (WorldGenLevel) Proxy.newProxyInstance(
                WorldGenLevel.class.getClassLoader(), new Class<?>[] {WorldGenLevel.class}, capture);
        ChunkGenerator generator = level.getChunkSource().getGenerator();
        RandomSource random = StructureStamper.placementRandom(anchor);
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos -> {
            if (!capture.overflowed) {
                start.placeInChunk(captureLevel, level.structureManager(), generator, random,
                        new BoundingBox(chunkPos.getMinBlockX(), level.getMinBuildHeight(),
                                chunkPos.getMinBlockZ(), chunkPos.getMaxBlockX(),
                                level.getMaxBuildHeight(), chunkPos.getMaxBlockZ()),
                        chunkPos);
            }
        });
        if (capture.overflowed) {
            EclipseMod.LOGGER.warn("StructureBlockSampler: {} overflowed the {}-block capture guard",
                    site.siteId(), MAX_CAPTURED_BLOCKS);
            return List.of();
        }
        return reduceToVisible(capture.captured, maxPieces);
    }

    /**
     * Seats the dry-run start exactly like the real placer will. This used to be a
     * hand-copied replica of {@code placeVanillaAsync}'s translation rules and drifted
     * from it; it now CALLS the one definition ({@link VanillaLandmarks#seatPieces}), so
     * a future change to how structures sit can no longer desync the preview from the
     * paste. Seating is a pure function of {@link DiscTerrainFunction} and the generated
     * start, so both sides still land on identical cells without touching the world.
     */
    private static void translatePieces(ServerLevel level, StructureStart start, BlockPos anchor,
            SitePrep.Mode mode) {
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        VanillaLandmarks.seatPieces(profile != null ? profile : DiscProfile.OVERWORLD,
                start, anchor, mode);
    }

    /**
     * Reduces the raw capture to the topmost visible (non-air, non-fluid) state per
     * column, then to at most {@code maxPieces} samples via a deterministic hash scatter
     * (uniform coverage of the footprint, identical on every replay of the site).
     */
    private static List<Sample> reduceToVisible(Map<Long, BlockState> captured, int maxPieces) {
        Map<Long, Long> topPerColumn = new HashMap<>();
        for (Map.Entry<Long, BlockState> entry : captured.entrySet()) {
            BlockState state = entry.getValue();
            if (state.isAir() || state.liquid()) {
                continue;
            }
            long posLong = entry.getKey();
            int x = BlockPos.getX(posLong);
            int y = BlockPos.getY(posLong);
            int z = BlockPos.getZ(posLong);
            long column = ((long) x << 32) | (z & 0xFFFFFFFFL);
            Long best = topPerColumn.get(column);
            if (best == null || BlockPos.getY(best) < y) {
                topPerColumn.put(column, posLong);
            }
        }
        List<Long> positions = new ArrayList<>(topPerColumn.values());
        // Deterministic scatter: a mixed-hash order spreads the cap uniformly over the
        // footprint (a plain coordinate sort would clip one whole side off big builds).
        positions.sort(Comparator.comparingLong(pos ->
                Long.rotateLeft(pos * 0x9E3779B97F4A7C15L, 31)));
        int count = Math.min(maxPieces, positions.size());
        List<Sample> samples = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            long posLong = positions.get(i);
            samples.add(new Sample(BlockPos.of(posLong), captured.get(posLong)));
        }
        return samples;
    }

    // ------------------------------------------------------------------ capture proxy

    /**
     * Reflective {@link WorldGenLevel} facade over the real level: block writes are
     * recorded (last write per position wins — later passes erasing earlier scaffolding
     * behave exactly like the real placement), state reads prefer the recorded value,
     * entity spawns / tick schedules / block-entity lookups at captured positions are
     * swallowed, and everything else forwards to the wrapped {@link ServerLevel}. A
     * dynamic proxy keeps this robust against the interface's ~100 members without a
     * hand-written delegate for each.
     */
    private static final class CaptureHandler implements InvocationHandler {
        final ServerLevel level;
        final Map<Long, BlockState> captured = new HashMap<>(4096);
        boolean overflowed;

        CaptureHandler(ServerLevel level) {
            this.level = level;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            String name = method.getName();
            switch (name) {
                case "setBlock" -> {
                    record((BlockPos) args[0], (BlockState) args[1]);
                    return Boolean.TRUE;
                }
                case "removeBlock", "destroyBlock" -> {
                    record((BlockPos) args[0], net.minecraft.world.level.block.Blocks.AIR.defaultBlockState());
                    return Boolean.TRUE;
                }
                case "addFreshEntity" -> {
                    return Boolean.TRUE; // swallowed: the dry run must not spawn mobs
                }
                case "addFreshEntityWithPassengers" -> {
                    return null; // void
                }
                case "scheduleTick" -> {
                    return null; // void — no deferred world mutation may leak out
                }
                case "getBlockEntity" -> {
                    // Never expose a real-world BE at a captured position: loot seeding
                    // would corrupt whatever block currently sits there. Null is the
                    // vanilla "nothing here" answer every caller already guards.
                    if (this.captured.containsKey(((BlockPos) args[0]).asLong())) {
                        return null;
                    }
                    return forward(method, args);
                }
                case "getBlockState" -> {
                    BlockState recorded = this.captured.get(((BlockPos) args[0]).asLong());
                    return recorded != null ? recorded : forward(method, args);
                }
                case "getFluidState" -> {
                    BlockState recorded = this.captured.get(((BlockPos) args[0]).asLong());
                    return recorded != null ? recorded.getFluidState() : forward(method, args);
                }
                default -> {
                    return forward(method, args);
                }
            }
        }

        private void record(BlockPos pos, BlockState state) {
            if (this.overflowed) {
                return;
            }
            if (this.captured.size() >= MAX_CAPTURED_BLOCKS) {
                this.overflowed = true;
                return;
            }
            this.captured.put(pos.asLong(), state);
        }

        private Object forward(Method method, Object[] args) throws Throwable {
            try {
                return method.invoke(this.level, args);
            } catch (InvocationTargetException e) {
                throw e.getCause() != null ? e.getCause() : e;
            }
        }
    }
}
