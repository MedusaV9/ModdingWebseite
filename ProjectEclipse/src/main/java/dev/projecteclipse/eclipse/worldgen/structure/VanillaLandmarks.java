package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.Map;
import java.util.function.Consumer;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.PoolElementStructurePiece;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.world.level.levelgen.structure.pools.StructureTemplatePool;

/**
 * Single owner of the vanilla-structure ↔ eclipse-landmark table and of the
 * {@code generateVanilla} placement wrappers (compile seam §3.10; used by
 * {@code DiscChunkGenerator.findNearestMapStructure} for {@code /locate structure} and by
 * W1.7/W1.8 for bastion/end-city sites).
 *
 * <p>{@link #locateSites()} maps vanilla structure registry ids to the landmark ids of
 * {@code disc_map.json} — the generator resolves a landmark to its authored (x, z) and
 * only reports it once its stage is committed. Multiple landmarks may share one id
 * (mineshafts); the generator then reports the nearest.</p>
 */
public final class VanillaLandmarks {
    /**
     * vanilla structure id → landmark id. Immutable — thread-safe for locate reads. The
     * first four entries preserve the generator's original hardcoded table (regression
     * contract, see {@code docs/plans_v3/wiring/P1-W1.1_wiring.md}; the stronghold row
     * was removed with the stronghold itself — plan B15 seam executed here); the rest
     * are the D6 set-piece sites + the deterministic underground mineshaft sites.
     */
    private static final Map<ResourceLocation, String> LOCATE_SITES = Map.ofEntries(
            Map.entry(ResourceLocation.withDefaultNamespace("desert_pyramid"), "eclipse:desert_temple"),
            Map.entry(ResourceLocation.withDefaultNamespace("jungle_pyramid"), "eclipse:jungle_temple"),
            Map.entry(ResourceLocation.withDefaultNamespace("village_plains"), "eclipse:village_plains"),
            Map.entry(ResourceLocation.withDefaultNamespace("fortress"), "eclipse:fortress_core"),
            Map.entry(ResourceLocation.withDefaultNamespace("mansion"), "eclipse:mansion"),
            Map.entry(ResourceLocation.withDefaultNamespace("pillager_outpost"), "eclipse:pillager_outpost"),
            Map.entry(ResourceLocation.withDefaultNamespace("trial_chambers"), "eclipse:trial_chambers"),
            Map.entry(ResourceLocation.withDefaultNamespace("ancient_city"), "eclipse:ancient_city"),
            Map.entry(ResourceLocation.withDefaultNamespace("mineshaft"), "eclipse:mineshaft"),
            Map.entry(ResourceLocation.withDefaultNamespace("bastion_remnant"), "eclipse:bastion_remnant"),
            Map.entry(ResourceLocation.withDefaultNamespace("end_city"), "eclipse:end_city"));

    private VanillaLandmarks() {}

    /**
     * The {@code /locate structure} table (compile seam §3.10): vanilla structure id →
     * landmark id in {@code disc_map.json}. Immutable, safe for concurrent reads.
     */
    public static Map<ResourceLocation, String> locateSites() {
        return LOCATE_SITES;
    }

    /** The landmark id a vanilla structure anchors to, or {@code null} if untracked. */
    @Nullable
    public static String landmarkIdFor(ResourceLocation structureId) {
        return LOCATE_SITES.get(structureId);
    }

    /**
     * Places a vanilla structure at a fixed anchor with terraforming (compile seam §3.10;
     * W1.7 bastion remnants, W1.8 end cities, and the stamper's mansion/outpost/trial
     * chambers/ancient city all come through here — the single {@code generateVanilla}
     * wrapper):
     *
     * <ol>
     *   <li>{@code Structure.generate} at the anchor chunk under the frozen map seed
     *       ({@link StructureStamper#generateVanilla});</li>
     *   <li>{@link SitePrep.Mode#CAVITY} sites are piece-translated so the piece-union
     *       center lands exactly on the anchor (vanilla picked its own Y);
     *       {@link SitePrep.Mode#PLATEAU} pieces are translated vertically onto the
     *       deterministic plateau height (plan B4) — jigsaw pieces get no ground snap
     *       at placement and would otherwise keep the pre-plateau slope's Y;</li>
     *   <li>{@link SitePrep} queues its resumable plateau/cavity worker (cavity mode
     *       carves per-piece envelopes, plan B3);</li>
     *   <li>once prep completes, pieces place chunk-by-chunk, the start is registered
     *       for {@code /locate}, and {@link SitePrep#finish} relights/resends.</li>
     * </ol>
     *
     * @return generated piece bounds whose placement is now queued, or {@code null} when
     *         vanilla generation refused after all attempts
     */
    @Nullable
    public static BoundingBox placeVanilla(ServerLevel level, ResourceLocation structureId,
            BlockPos anchor, SitePrep.Mode mode) {
        return placeVanillaAsync(level, structureId, anchor, mode, ignored -> {},
                error -> EclipseMod.LOGGER.error("Queued placement of {} at {} failed",
                        structureId, anchor.toShortString(), error));
    }

    /**
     * Callback-aware variant for {@link StructurePendingRegistry.AsyncSitePlacer}. The
     * success callback fires only after SitePrep, piece placement, structure bookkeeping
     * and relight scheduling all complete; failure leaves error handling to the registry.
     *
     * @return generated piece bounds whose prep is queued, or {@code null} if generation
     *         produced no valid start
     */
    @Nullable
    public static BoundingBox placeVanillaAsync(ServerLevel level, ResourceLocation structureId,
            BlockPos anchor, SitePrep.Mode mode, Consumer<BoundingBox> onComplete,
            Consumer<Throwable> onFailure) {
        return placeVanillaAsync(level, structureId, anchor, mode, 0, onComplete, onFailure);
    }

    /**
     * {@code seedNudge} variant (registry retries): rolls fresh {@code Structure.generate}
     * layouts instead of re-failing the identical deterministic attempt.
     */
    @Nullable
    public static BoundingBox placeVanillaAsync(ServerLevel level, ResourceLocation structureId,
            BlockPos anchor, SitePrep.Mode mode, int seedNudge, Consumer<BoundingBox> onComplete,
            Consumer<Throwable> onFailure) {
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null) {
            EclipseMod.LOGGER.warn("placeVanilla({}) called for non-disc dimension {}; skipping",
                    structureId, level.dimension().location());
            return null;
        }
        StructureStart start = StructureStamper.generateVanilla(level, structureId, anchor, seedNudge);
        if (start == null) {
            return null;
        }
        BoundingBox bounds = StructureStamper.pieceUnion(start);
        if (mode == SitePrep.Mode.CAVITY) {
            // Vanilla picked its own position (jigsaw starts anchor to their own Y and the
            // chunk corner); translate every piece so the union centers on our anchor.
            BlockPos center = bounds.getCenter();
            int dx = anchor.getX() - center.getX();
            int dy = anchor.getY() - center.getY();
            int dz = anchor.getZ() - center.getZ();
            for (StructurePiece piece : start.getPieces()) {
                piece.move(dx, dy, dz);
            }
            bounds = StructureStamper.pieceUnion(start);
        } else {
            // Plan B4: Structure.generate Y-snapped the jigsaw start + roads against the
            // LIVE pre-plateau heightmaps, and jigsaw pieces get no per-piece ground snap
            // at placement — wherever the plateau ends up lower than the old slope, the
            // pieces float. Translate every RIGID piece vertically so the start piece's
            // base sits on the deterministic plateau SitePrep is about to build (rigid
            // pieces are jigsaw-connected to each other, so a single vertical delta keeps
            // streets, farms and houses seamless).
            //
            // FIX-STRUCT (BUG B): TERRAIN_MATCHING pieces (outpost tents/cages/targets,
            // village decor) must NOT take the uniform delta. Jigsaw assembly seated each
            // of them individually on the pre-plateau slope via getFirstFreeHeight at its
            // OWN column; the uniform shift preserved those per-column differences onto
            // the flat plateau, floating every piece whose column was higher than the
            // start's (and burying the lower ones). Re-seat each terrain-matching piece
            // by its own column's surface delta — after the flatten the local surface is
            // plateauY everywhere, so the piece keeps exactly the seat depth assembly
            // gave it relative to the local ground (the +1 first-free convention and any
            // groundLevelDelta cancel in the difference).
            int plateauY = DiscTerrainFunction.surfaceY(profile, anchor.getX(), anchor.getZ());
            int groundY = start.getPieces().get(0).getBoundingBox().minY();
            int dy = plateauY - groundY;
            for (StructurePiece piece : start.getPieces()) {
                int pieceDy = dy;
                if (isTerrainMatching(piece)) {
                    BlockPos center = piece.getBoundingBox().getCenter();
                    pieceDy = plateauY - DiscTerrainFunction.surfaceY(profile, center.getX(), center.getZ());
                }
                if (pieceDy != 0) {
                    piece.move(0, pieceDy, 0);
                }
            }
            bounds = StructureStamper.pieceUnion(start);
        }

        SitePrep.PreparedGround prepared = mode == SitePrep.Mode.CAVITY
                // Plan B3 seam: hand SitePrep the per-piece boxes so the cavity carve hugs
                // each piece instead of blowing out the whole union box.
                ? SitePrep.prepareCavity(level, profile,
                        start.getPieces().stream().map(StructurePiece::getBoundingBox).toList(),
                        anchor)
                : SitePrep.preparePlateau(level, profile, bounds.minX(), bounds.minZ(),
                        bounds.maxX(), bounds.maxZ(), anchor);
        prepared.whenReady(() -> {
            BoundingBox placed = StructureStamper.placeStart(level, start,
                    StructureStamper.placementRandom(anchor));
            StructureStamper.registerStart(level, start, placed);
            SitePrep.touchBounds(prepared, placed.minX(), placed.minZ(), placed.maxX(), placed.maxZ());
            SitePrep.finish(level, prepared);
            EclipseMod.LOGGER.info("VANILLA GENERATE: placed {} ({} mode) at {} (bounds {})",
                    structureId, mode, anchor.toShortString(), placed);
            onComplete.accept(placed);
        }, onFailure);
        return bounds;
    }

    /**
     * FIX-STRUCT (BUG B): whether a piece was assembled with per-column ground snapping
     * ({@link StructureTemplatePool.Projection#TERRAIN_MATCHING} — outpost feature
     * pieces, village decor/animal pens). Only jigsaw pool pieces carry a projection;
     * everything else (template pieces, jigsaw RIGID trees) is rigid.
     */
    private static boolean isTerrainMatching(StructurePiece piece) {
        return piece instanceof PoolElementStructurePiece pool
                && pool.getElement().getProjection() == StructureTemplatePool.Projection.TERRAIN_MATCHING;
    }
}
