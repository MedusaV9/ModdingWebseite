package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.PoolElementStructurePiece;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.world.level.levelgen.structure.pools.JigsawJunction;
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
        int plateauY = seatPieces(profile, start, anchor, mode);
        BoundingBox bounds = StructureStamper.pieceUnion(start);
        SitePrep.PreparedGround prepared = mode == SitePrep.Mode.CAVITY
                // Plan B3 seam: hand SitePrep the per-piece boxes so the cavity carve hugs
                // each piece instead of blowing out the whole union box.
                ? SitePrep.prepareCavity(level, profile,
                        start.getPieces().stream().map(StructurePiece::getBoundingBox).toList(),
                        anchor)
                : SitePrep.preparePlateau(level, profile, bounds.minX(), bounds.minZ(),
                        bounds.maxX(), bounds.maxZ(), plateauY);
        prepared.whenReady(() -> {
            BoundingBox placed = StructureStamper.placeStart(level, start,
                    StructureStamper.placementRandom(anchor));
            StructureStamper.registerStart(level, start, placed);
            SitePrep.touchBounds(prepared, placed.minX(), placed.minZ(), placed.maxX(), placed.maxZ());
            if (mode == SitePrep.Mode.CAVITY) {
                finishPlacement(level, prepared, structureId, mode, anchor, placed, onComplete);
                return;
            }
            // FIX-FLOAT: pack whatever gap the paste still left between the build and the
            // prepared ground (uneven columns, per-piece seats) before the relight pass,
            // so the resend the player sees already carries the foundations.
            StructureGrounding.fillFoundations(level, profile, prepared, placed,
                    () -> finishPlacement(level, prepared, structureId, mode, anchor, placed, onComplete),
                    onFailure);
        }, onFailure);
        return bounds;
    }

    /**
     * Moves a freshly generated start onto the ground {@link SitePrep} is about to build
     * and returns that seat height (the anchor's own Y for {@link SitePrep.Mode#CAVITY},
     * which positions by union center instead). This is the SINGLE definition of where a
     * stamped structure sits: {@link StructureBlockSampler} runs it on its dry-run start
     * too, so the delivery preview and the real paste can never disagree about a cell.
     *
     * <ul>
     *   <li><b>CAVITY</b> — vanilla picked its own position (jigsaw starts anchor to
     *       their own Y and the chunk corner); translate every piece so the union centers
     *       on the anchor.</li>
     *   <li><b>PLATEAU</b> — plan B4: {@code Structure.generate} Y-snapped the jigsaw
     *       start and its roads against the LIVE pre-plateau heightmaps, and jigsaw
     *       pieces get no per-piece ground snap at placement, so wherever the plateau
     *       ends up lower than the old slope the pieces float. Every RIGID piece takes
     *       one shared vertical delta (they are jigsaw-connected, so a uniform shift
     *       keeps streets, farms and houses seamless).</li>
     * </ul>
     *
     * <p>FIX-FLOAT: the seat is sampled over the whole piece footprint and taken at its
     * minimum ({@link StructureGrounding#seatY}) rather than read off the anchor's single
     * column — a site whose anchor happened to sit on a local rise hung that rise's worth
     * of air under its far side. The start's ground line is also read correctly as
     * {@code minY + groundLevelDelta - 1}: {@code JigsawPlacement} moves the start so that
     * {@code minY + groundLevelDelta} lands on the first FREE block above the terrain, so
     * reading {@code minY} only happened to work while every element kept the default
     * delta of 1.</p>
     */
    static int seatPieces(DiscProfile profile, StructureStart start, BlockPos anchor,
            SitePrep.Mode mode) {
        BoundingBox bounds = StructureStamper.pieceUnion(start);
        if (mode == SitePrep.Mode.CAVITY) {
            BlockPos center = bounds.getCenter();
            int dx = anchor.getX() - center.getX();
            int dy = anchor.getY() - center.getY();
            int dz = anchor.getZ() - center.getZ();
            for (StructurePiece piece : start.getPieces()) {
                piece.move(dx, dy, dz);
            }
            return anchor.getY();
        }
        int seatY = StructureGrounding.seatY(profile, bounds.minX(), bounds.minZ(),
                bounds.maxX(), bounds.maxZ(), anchor.getY());
        List<StructurePiece> pieces = start.getPieces();
        int dy = seatY - (pieces.get(0).getBoundingBox().minY()
                + groundLevelDelta(pieces.get(0)) - 1);
        for (int i = 0; i < pieces.size(); i++) {
            StructurePiece piece = pieces.get(i);
            int pieceDy = i > 0 && isTerrainMatching(piece) ? terrainMatchingDy(profile, piece, seatY) : dy;
            if (pieceDy != 0) {
                piece.move(0, pieceDy, 0);
            }
        }
        return seatY;
    }

    /**
     * FIX-STRUCT (BUG B): the vertical delta of a {@code TERRAIN_MATCHING} piece (village
     * decor, the outpost's feature plate). Such a piece must NOT take the start's uniform
     * delta — jigsaw assembly snapped it individually, placing it so its connecting
     * jigsaw block landed on {@code getFirstFreeHeight} at its PARENT's jigsaw column
     * rather than at the start's. Re-seating it is therefore a pure change of ground
     * line: shift it by however much that same column's ground moved when the plateau
     * flattened it. The piece's own unknown internal offset to its jigsaw block cancels
     * out of that difference, which is why this is read as a delta rather than by
     * pinning the piece's box to the plateau (pinning silently assumed the connecting
     * jigsaw sat on the piece's bottom layer — true for the outpost plate, false for
     * plenty of village decor).
     *
     * <p>The parent's jigsaw column is recorded on the piece itself: a non-start piece's
     * FIRST junction is the one written when jigsaw assembly created it from its parent,
     * and it carries exactly the coordinates {@code getFirstFreeHeight} was called with.
     * Pieces without that record (non-pool pieces) fall back to their own box center.</p>
     */
    private static int terrainMatchingDy(DiscProfile profile, StructurePiece piece, int seatY) {
        BoundingBox box = piece.getBoundingBox();
        int refX = box.getCenter().getX();
        int refZ = box.getCenter().getZ();
        if (piece instanceof PoolElementStructurePiece pool && !pool.getJunctions().isEmpty()) {
            JigsawJunction parent = pool.getJunctions().get(0);
            refX = parent.getSourceX();
            refZ = parent.getSourceZ();
        }
        return (seatY + 1) - StructureGrounding.assembledGroundLineY(profile, refX, refZ, seatY + 1);
    }

    /** Shared tail of both prep modes: relight/resend the site and report completion. */
    private static void finishPlacement(ServerLevel level, SitePrep.PreparedGround prepared,
            ResourceLocation structureId, SitePrep.Mode mode, BlockPos anchor, BoundingBox placed,
            Consumer<BoundingBox> onComplete) {
        SitePrep.finish(level, prepared);
        EclipseMod.LOGGER.info("VANILLA GENERATE: placed {} ({} mode) at {} (bounds {})",
                structureId, mode, anchor.toShortString(), placed);
        onComplete.accept(placed);
    }

    /**
     * The piece's jigsaw ground-level delta. Non-pool pieces (the scattered-feature
     * temples) carry no delta and already sit with their bottom layer on the ground, so
     * they answer the neutral 1 — {@code minY + 1 - 1} leaves their seat untouched.
     */
    private static int groundLevelDelta(StructurePiece piece) {
        return piece instanceof PoolElementStructurePiece pool ? pool.getGroundLevelDelta() : 1;
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
