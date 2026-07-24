package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.levelgen.Heightmap;

/**
 * Registry of freshly-grown ring annuli (design D11, compile seam §3.10) — the P4/P6
 * seam for glitched-mob spawn rules: newly materialized land is "unstable" for a decay
 * window ({@code worldgen_tuning.json → glitch.freshTicks}, default 3 in-game days).
 *
 * <p>Rows ({@link EclipseWorldgenState.NewRing}) are appended ONLY by genuine stage-commit
 * sweeps ({@code WorldStageService.onSweepComplete} → {@link #onRingCommitted}): rebuilds
 * ({@code /eclipse stage rebuild}) never reach that path, StageIO snapshot loads bypass the
 * sweep entirely, and erase/downgrade sweeps are filtered by the {@code toStage > fromStage}
 * guard — so only land players have never touched reads as fresh.</p>
 *
 * <p>All queries are server-thread reads against the SavedData-backed row list; freshness
 * is computed live from the row's {@code committedGameTime}, so a {@code glitch.freshTicks}
 * reload immediately re-scales decay. Expired rows are pruned opportunistically whenever a
 * new ring commits.</p>
 */
public final class NewRingRegistry {
    /** Sampling over-draw factor: how many random probes to try per requested position. */
    private static final int SAMPLE_ATTEMPTS_PER_POSITION = 4;

    private NewRingRegistry() {}

    /**
     * Whether {@code pos} lies inside a grown annulus that has not fully decayed yet.
     * Fresh means glitched-mob spawn rules may apply here (P4 owns the actual rules).
     */
    public static boolean isFreshRing(ServerLevel level, BlockPos pos) {
        return freshness(level, pos) > 0.0D;
    }

    /**
     * Freshness of {@code pos} in {@code [0, 1]}: {@code 1} the moment its ring's sweep
     * committed, linearly decaying to {@code 0} over {@code glitch.freshTicks}. Positions
     * outside every recorded ring (or in non-disc dimensions) are {@code 0}. Overlapping
     * rows (an annulus erased and re-grown) report the freshest row.
     */
    public static double freshness(ServerLevel level, BlockPos pos) {
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null) {
            return 0.0D;
        }
        double r = Math.sqrt((double) pos.getX() * pos.getX() + (double) pos.getZ() * pos.getZ());
        long now = level.getGameTime();
        int freshTicks = GrowthPacing.glitchFreshTicks();
        double best = 0.0D;
        for (EclipseWorldgenState.NewRing ring : rows(level)) {
            if (!ring.dim().equals(profile.name()) || r < ring.innerR() || r > ring.outerR()) {
                continue;
            }
            double freshness = 1.0D - (double) (now - ring.committedGameTime()) / freshTicks;
            if (freshness > best) {
                best = Math.min(1.0D, freshness);
            }
        }
        return best;
    }

    /**
     * Up to {@code count} surface positions inside still-fresh rings of this level, for
     * glitched-mob spawner placement (P4/P6). Positions are drawn area-uniformly inside
     * randomly picked fresh annuli, restricted to CURRENTLY LOADED chunks (no chunk is
     * ever loaded or generated for a sample — spawners want positions near players
     * anyway); void columns (rim wobble gaps, never-generated land) are skipped. May
     * return fewer than {@code count} entries, or an empty list when nothing is fresh
     * or nothing relevant is loaded. Y is the motion-blocking surface + 1.
     */
    public static List<BlockPos> sampleFreshPositions(ServerLevel level, int count) {
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null || count <= 0) {
            return List.of();
        }
        long now = level.getGameTime();
        int freshTicks = GrowthPacing.glitchFreshTicks();
        List<EclipseWorldgenState.NewRing> fresh = new ArrayList<>();
        for (EclipseWorldgenState.NewRing ring : rows(level)) {
            if (ring.dim().equals(profile.name()) && now - ring.committedGameTime() < freshTicks) {
                fresh.add(ring);
            }
        }
        if (fresh.isEmpty()) {
            return List.of();
        }

        RandomSource random = level.getRandom();
        List<BlockPos> positions = new ArrayList<>(count);
        int attempts = count * SAMPLE_ATTEMPTS_PER_POSITION;
        for (int i = 0; i < attempts && positions.size() < count; i++) {
            EclipseWorldgenState.NewRing ring = fresh.get(random.nextInt(fresh.size()));
            // Area-uniform radius inside the annulus: r = sqrt(lerp(inner^2, outer^2, u)).
            double innerSq = (double) ring.innerR() * ring.innerR();
            double outerSq = (double) ring.outerR() * ring.outerR();
            double r = Math.sqrt(innerSq + (outerSq - innerSq) * random.nextDouble());
            double angle = random.nextDouble() * Math.PI * 2.0D;
            int x = (int) Math.round(r * Math.cos(angle));
            int z = (int) Math.round(r * Math.sin(angle));
            LevelChunk chunk = level.getChunkSource().getChunkNow(x >> 4, z >> 4);
            if (chunk == null) {
                continue;
            }
            int surfaceY = chunk.getHeight(Heightmap.Types.MOTION_BLOCKING, x & 15, z & 15);
            if (surfaceY <= chunk.getMinBuildHeight()) {
                continue; // void column (rim wobble / never-written land)
            }
            positions.add(new BlockPos(x, surfaceY + 1, z));
        }
        return positions;
    }

    /**
     * Records a genuinely committed growth annulus — called by
     * {@code WorldStageService.onSweepComplete} on the server thread for GROW transitions
     * only (never rebuilds, erases or snapshot loads). The row band spans the radii of
     * every stage crossed by the transition ({@code radius(fromStage)..radius(toStage)}),
     * so multi-stage day-jump commits flag the whole grown area. Also prunes rows that
     * decayed past twice the current freshness window.
     */
    static void onRingCommitted(ServerLevel level, DiscProfile profile, int fromStage, int toStage) {
        if (toStage <= fromStage) {
            return;
        }
        int innerR = StageRadii.radius(profile, fromStage);
        int outerR = StageRadii.radius(profile, toStage);
        if (outerR <= innerR) {
            return;
        }
        long now = level.getGameTime();
        EclipseWorldgenState state = EclipseWorldgenState.get(level.getServer());
        state.addNewRing(new EclipseWorldgenState.NewRing(
                profile.name(), innerR, outerR, toStage, now));
        state.pruneNewRings(now - 2L * GrowthPacing.glitchFreshTicks());
        EclipseMod.LOGGER.info(
                "New ring registered: {} r {}..{} (stage {}) at game time {} — fresh for {} ticks",
                profile.name(), innerR, outerR, toStage, now, GrowthPacing.glitchFreshTicks());
    }

    private static List<EclipseWorldgenState.NewRing> rows(ServerLevel level) {
        return EclipseWorldgenState.get(level.getServer()).newRings();
    }
}
