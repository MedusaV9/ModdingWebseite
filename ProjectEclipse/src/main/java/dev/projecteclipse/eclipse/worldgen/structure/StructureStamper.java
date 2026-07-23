package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import dev.projecteclipse.eclipse.worldgen.structure.dungeon.CollapsedVaultBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.Structure;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Structure system v2 entry point (design D7): the stage listener no longer places
 * blocks — it <b>enqueues</b> every structure site of the crossed stages into the
 * two-phase {@link StructurePendingRegistry} (PENDING → rift payload → P2
 * {@code trigger} / auto-delay → PLACED), and this class registers the
 * {@link StructurePendingRegistry.SitePlacer placers} that actually build when a site
 * fires:
 *
 * <ul>
 *   <li><b>Vanilla starts with terraforming</b> — temples, village, mansion, pillager
 *       outpost (plateau mode) and trial chambers, ancient city (cavity mode) all run
 *       through {@link VanillaLandmarks#placeVanilla} → SitePrep → {@link #placeStart},
 *       which fixes the "structures spawn weirdly on trees" bug: vegetation is cleared
 *       and the ground is terraformed BEFORE pieces snap to the re-primed heightmaps.</li>
 *   <li><b>Procedural set pieces</b> — fortress core, watcher statues (stage-1 flavor,
 *       placed directly), the {@link FallbackBuilders} fallbacks whenever a vanilla
 *       start refuses to generate (a listed structure never silently misses), and the
 *       stage-5 <b>stronghold surface vault</b>: a collapsed-keep ruin at the
 *       {@code eclipse:stronghold_emergence} rim landmark whose gauntlet descends to the
 *       portal room's doorstep in the mountain cavity
 *       ({@link CollapsedVaultBuilder#buildStrongholdGauntlet}).</li>
 *   <li><b>Underground tables</b> — {@link UndergroundSites} rows (mineshafts, monster
 *       rooms, both custom dungeons) enqueued alongside the stage's configured
 *       {@code structures[]}.</li>
 * </ul>
 *
 * <p>{@code stages.json} may list both {@code eclipse:*} landmark ids and
 * {@code minecraft:*} structure ids ({@code minecraft:mansion}…); the latter resolve
 * their landmark through {@link VanillaLandmarks#landmarkIdFor}. Erase sweeps clear the
 * registry's rows above the kept stage so a regrow re-enqueues deterministically.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StructureStamper {
    /** How often a vanilla {@code Structure.generate} is retried before falling back. */
    static final int VANILLA_ATTEMPTS = 2;

    /** Anchor depth of the trial chambers (D6: y ≈ −20 under the badlands ring). */
    private static final int TRIAL_CHAMBERS_Y = -20;
    /** Anchor depth of the ancient city (D6: y ≈ −40 inside the mountain). */
    private static final int ANCIENT_CITY_Y = -40;
    /** Implicit stage-5 companion site of the stronghold emergence (D8 table). */
    private static final String STRONGHOLD_VAULT_ID = "eclipse:stronghold_vault";
    /** Overworld stage that triggers the finale pair (emergence + surface vault). */
    private static final int FINALE_STAGE = 5;

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private StructureStamper() {}

    /**
     * Registers the stage listener once per JVM ({@code LISTENERS} is a static list) and
     * the site placers (idempotent map, safe to re-run) — placers must exist before
     * {@code ServerStartedEvent} resumes persisted pending sites.
     */
    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(StructureStamper::onStageTerrainComplete);
            EclipseMod.LOGGER.info("StructureStamper registered as world-stage listener");
        }
        registerPlacers();
    }

    // --- phase 1: terrain done -> enqueue ---

    /**
     * Stage listener: enqueues the sites of every newly reached stage. Erase sweeps
     * ({@code toStage <= fromStage}) enqueue nothing and instead clear the registry's
     * records above the kept stage — the terrain function already removed the annulus
     * (and any structure in it); regrowing re-enqueues deterministically.
     */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage) {
        if (toStage <= fromStage) {
            StructurePendingRegistry.clearPlacedAbove(profile.name(), toStage);
            return;
        }
        long gameTime = level.getGameTime();
        for (int stage = fromStage + 1; stage <= toStage; stage++) {
            if (profile == DiscProfile.OVERWORLD && stage == 1) {
                // §F flavor landmark, placed directly (tiny scenery, no rift moment):
                // watcher statues at the former team-disc centers once the intro fusion
                // swallows the player discs.
                try {
                    WatcherStatues.placeAll(level);
                } catch (Exception e) {
                    EclipseMod.LOGGER.error("Structure placement of eclipse:watcher_statues failed", e);
                }
            }
            EclipseConfig.StageEntry entry = EclipseConfig.stage(profile.name(), stage);
            if (entry != null) {
                for (String structureId : entry.structures()) {
                    enqueueConfigured(profile, stage, structureId, gameTime);
                }
            }
            if (profile == DiscProfile.OVERWORLD && stage == FINALE_STAGE) {
                enqueueStrongholdVault(stage, gameTime);
            }
            for (PendingSite site : UndergroundSites.sitesFor(profile, stage, gameTime)) {
                StructurePendingRegistry.enqueue(site);
            }
        }
    }

    /** Builds + enqueues the pending row of one {@code stages.json} structure id. */
    private static void enqueueConfigured(DiscProfile profile, int stage, String structureId, long gameTime) {
        String landmarkId = structureId;
        if (structureId.startsWith("minecraft:")) {
            String mapped = VanillaLandmarks.landmarkIdFor(ResourceLocation.parse(structureId));
            if (mapped == null) {
                EclipseMod.LOGGER.warn("Structure id {} (stage {} of {}) has no landmark mapping; skipping",
                        structureId, stage, profile.name());
                return;
            }
            landmarkId = mapped;
        }
        DiscMapData.Landmark landmark = findLandmark(profile, landmarkId);
        if (landmark == null) {
            EclipseMod.LOGGER.warn("No disc_map.json landmark {} for structure {} (stage {} of {}); skipping",
                    landmarkId, structureId, stage, profile.name());
            return;
        }
        BlockPos anchor = switch (structureId) {
            case "minecraft:trial_chambers" ->
                    new BlockPos(landmark.x(), TRIAL_CHAMBERS_Y, landmark.z());
            case "minecraft:ancient_city" ->
                    new BlockPos(landmark.x(), ANCIENT_CITY_Y, landmark.z());
            default -> surfaceAnchor(profile, landmark);
        };
        StructurePendingRegistry.enqueue(new PendingSite(landmarkId, structureId, profile.name(),
                anchor, stage, footprintOf(structureId, landmark), gameTime));
    }

    /** The finale's companion surface site at the stronghold rim landmark (D6/D8). */
    private static void enqueueStrongholdVault(int stage, long gameTime) {
        DiscMapData.Landmark landmark = findLandmark(DiscProfile.OVERWORLD, "eclipse:stronghold_emergence");
        if (landmark == null) {
            EclipseMod.LOGGER.warn("No eclipse:stronghold_emergence landmark; skipping the surface vault");
            return;
        }
        StructurePendingRegistry.enqueue(new PendingSite(STRONGHOLD_VAULT_ID, STRONGHOLD_VAULT_ID,
                DiscProfile.OVERWORLD.name(), surfaceAnchor(DiscProfile.OVERWORLD, landmark),
                stage, 44, gameTime));
    }

    /** Expected XZ extent of a structure (P2 rift sizing): measured minimums per id. */
    private static int footprintOf(String structureId, DiscMapData.Landmark landmark) {
        int fromRadius = landmark.radius() * 2;
        return switch (structureId) {
            case "eclipse:village_plains" -> Math.max(fromRadius, 120);
            case "minecraft:mansion" -> Math.max(fromRadius, 80);
            case "minecraft:ancient_city" -> Math.max(fromRadius, 110);
            case "minecraft:trial_chambers" -> Math.max(fromRadius, 80);
            case "minecraft:pillager_outpost" -> Math.max(fromRadius, 48);
            default -> Math.max(fromRadius, 24);
        };
    }

    // --- phase 2: the placers ---

    /** Registers every placer this package owns (first registration wins — idempotent). */
    private static void registerPlacers() {
        StructurePendingRegistry.registerPlacer("eclipse:desert_temple", (level, site) ->
                placeWithFallback(level, site, ResourceLocation.withDefaultNamespace("desert_pyramid"),
                        anchor -> FallbackBuilders.desertTemple(level, anchor)));
        StructurePendingRegistry.registerPlacer("eclipse:jungle_temple", (level, site) ->
                placeWithFallback(level, site, ResourceLocation.withDefaultNamespace("jungle_pyramid"),
                        anchor -> FallbackBuilders.jungleTemple(level, anchor)));
        StructurePendingRegistry.registerPlacer("eclipse:village_plains", (level, site) ->
                placeWithFallback(level, site, ResourceLocation.withDefaultNamespace("village_plains"),
                        anchor -> FallbackBuilders.village(level, anchor)));
        StructurePendingRegistry.registerPlacer("minecraft:pillager_outpost", (level, site) ->
                placeWithFallback(level, site, ResourceLocation.withDefaultNamespace("pillager_outpost"), null));
        StructurePendingRegistry.registerPlacer("minecraft:mansion", (level, site) ->
                placeWithFallback(level, site, ResourceLocation.withDefaultNamespace("mansion"), null));
        StructurePendingRegistry.registerPlacer("minecraft:trial_chambers", (level, site) ->
                placeCavity(level, site, ResourceLocation.withDefaultNamespace("trial_chambers")));
        StructurePendingRegistry.registerPlacer("minecraft:ancient_city", (level, site) ->
                placeCavity(level, site, ResourceLocation.withDefaultNamespace("ancient_city")));
        // The emergence runs its own quake/fissure/beam sequence — the rift phase of the
        // registry is its announcement; the sequence itself starts on trigger.
        StructurePendingRegistry.registerPlacer("eclipse:stronghold_emergence",
                (level, site) -> StrongholdEmergence.begin(level));
        StructurePendingRegistry.registerPlacer("eclipse:fortress_core", (level, site) -> {
            DiscMapData.Landmark landmark = findLandmark(DiscProfile.NETHER, "eclipse:fortress_core");
            if (landmark != null) {
                FortressCoreBuilder.build(level, landmark);
            }
        });
        StructurePendingRegistry.registerPlacer(STRONGHOLD_VAULT_ID, StructureStamper::placeStrongholdVault);
        UndergroundSites.registerPlacers();
    }

    /**
     * Plateau-mode vanilla placement via {@link VanillaLandmarks#placeVanilla} (SitePrep
     * terraform + heightmap re-prime + relight). When vanilla refuses after
     * {@value #VANILLA_ATTEMPTS} attempts, the procedural fallback builds on a SitePrep'd
     * pad instead — never on raw (tree-covered) ground; sites without a fallback builder
     * (mansion, outpost) log and consume the site.
     */
    private static void placeWithFallback(ServerLevel level, PendingSite site,
            ResourceLocation vanillaId, @Nullable FallbackBuild fallback) {
        BoundingBox placed = VanillaLandmarks.placeVanilla(level, vanillaId, site.anchor(), SitePrep.Mode.PLATEAU);
        if (placed != null) {
            return;
        }
        if (fallback == null) {
            EclipseMod.LOGGER.error("{} failed to generate at {} and has no procedural fallback; "
                    + "site {} consumed", vanillaId, site.anchor().toShortString(), site.siteId());
            return;
        }
        EclipseMod.LOGGER.warn("PROCEDURAL FALLBACK: {} failed to generate at {}; building the fallback piece",
                vanillaId, site.anchor().toShortString());
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        int pad = Math.max(12, site.footprint() / 4);
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level,
                profile != null ? profile : DiscProfile.OVERWORLD,
                site.anchor().getX() - pad, site.anchor().getZ() - pad,
                site.anchor().getX() + pad, site.anchor().getZ() + pad, site.anchor());
        fallback.build(new BlockPos(site.anchor().getX(), prepared.plateauY(), site.anchor().getZ()));
        SitePrep.finish(level, prepared);
    }

    /** Cavity-mode vanilla placement (underground envelope + entrance shaft). */
    private static void placeCavity(ServerLevel level, PendingSite site, ResourceLocation vanillaId) {
        BoundingBox placed = VanillaLandmarks.placeVanilla(level, vanillaId, site.anchor(), SitePrep.Mode.CAVITY);
        if (placed == null) {
            EclipseMod.LOGGER.error("{} failed to generate at {} — underground site {} consumed "
                    + "(no procedural equivalent exists)", vanillaId, site.anchor().toShortString(), site.siteId());
        }
    }

    /**
     * The stage-5 stronghold surface vault: collapsed-keep ruin on a SitePrep plateau at
     * the rim landmark + the Collapsed Vault gauntlet descending to the portal-room
     * doorstep — the cavity edge nearest the ruin, at portal-room floor height
     * ({@code StrongholdEmergence} stamps the stronghold centered in the mountain-core
     * cavity). Without a mountain the gauntlet dead-drops 40 blocks below the ruin into
     * a sealed antechamber (flavor only; the emergence fallback already placed a portal).
     */
    private static void placeStrongholdVault(ServerLevel level, PendingSite site) {
        BlockPos anchor = site.anchor();
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level,
                profile != null ? profile : DiscProfile.OVERWORLD,
                anchor.getX() - 12, anchor.getZ() - 12, anchor.getX() + 12, anchor.getZ() + 12, anchor);
        BlockPos surface = new BlockPos(anchor.getX(), prepared.plateauY(), anchor.getZ());

        DiscMapData.Mountain mountain = DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        BlockPos target;
        if (mountain == null) {
            target = surface.below(40).offset(24, 0, 0);
            EclipseMod.LOGGER.warn("No mountain in disc_map.json; stronghold gauntlet ends in a sealed antechamber");
        } else {
            double dx = surface.getX() - mountain.x();
            double dz = surface.getZ() - mountain.z();
            double len = Math.max(1.0D, Math.sqrt(dx * dx + dz * dz));
            int doorstepR = mountain.caveRadiusXz() + 5;
            target = new BlockPos(mountain.x() + (int) Math.round(dx / len * doorstepR),
                    mountain.caveY() - mountain.caveRadiusY() + 2,
                    mountain.z() + (int) Math.round(dz / len * doorstepR));
        }
        BoundingBox bounds = CollapsedVaultBuilder.buildStrongholdGauntlet(level, surface, target);
        SitePrep.finish(level, prepared);
        SitePrep.finishBounds(level, bounds.minX(), bounds.minZ(), bounds.maxX(), bounds.maxZ());
    }

    /** Procedural fallback builder taking the prepared plateau anchor. */
    @FunctionalInterface
    private interface FallbackBuild {
        void build(BlockPos anchor);
    }

    // --- shared landmark / vanilla-generate helpers (used by VanillaLandmarks,
    // StrongholdEmergence and UndergroundSites) ---

    /** The landmark entry for a structure id, or {@code null} when the map has none. */
    @Nullable
    static DiscMapData.Landmark findLandmark(DiscProfile profile, String structureId) {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(profile)) {
            if (landmark.id().equals(structureId)) {
                return landmark;
            }
        }
        return null;
    }

    /** Deterministic surface anchor of a landmark (terrain function, not world heightmap). */
    static BlockPos surfaceAnchor(DiscProfile profile, DiscMapData.Landmark landmark) {
        return new BlockPos(landmark.x(),
                DiscTerrainFunction.surfaceY(profile, landmark.x(), landmark.z()), landmark.z());
    }

    /**
     * Replicates the {@code /place structure} generate step under the frozen map seed
     * (attempt index nudges the seed). Returns {@code null} after
     * {@value #VANILLA_ATTEMPTS} invalid/failed attempts — callers must fall back.
     */
    @Nullable
    static StructureStart generateVanilla(ServerLevel level, ResourceLocation structureId, BlockPos anchor) {
        Structure structure = level.registryAccess().registryOrThrow(Registries.STRUCTURE).get(structureId);
        if (structure == null) {
            EclipseMod.LOGGER.error("Structure {} missing from registry", structureId);
            return null;
        }
        ChunkGenerator generator = level.getChunkSource().getGenerator();
        for (int attempt = 0; attempt < VANILLA_ATTEMPTS; attempt++) {
            try {
                StructureStart start = structure.generate(level.registryAccess(), generator,
                        generator.getBiomeSource(), level.getChunkSource().randomState(),
                        level.getStructureManager(), FrozenParams.mapSeed() + attempt,
                        new ChunkPos(anchor), 0, level, biome -> true);
                if (start != null && start.isValid()) {
                    return start;
                }
                EclipseMod.LOGGER.warn("Structure.generate attempt {}/{} for {} at {} produced no pieces",
                        attempt + 1, VANILLA_ATTEMPTS, structureId, anchor.toShortString());
            } catch (Exception e) {
                EclipseMod.LOGGER.warn("Structure.generate attempt {}/{} for {} at {} threw",
                        attempt + 1, VANILLA_ATTEMPTS, structureId, anchor.toShortString(), e);
            }
        }
        return null;
    }

    /**
     * Places every piece of a generated start, chunk by chunk like {@code /place structure}.
     * Bounds come from the piece union (NOT {@link StructureStart#getBoundingBox()}, whose
     * lazy cache would be stale after {@link StructurePiece#move} repositioning). Chunks are
     * force-materialised first — the ring sweep only rewrites already-generated chunks, so
     * a landmark area may still be ungenerated when its stage completes.
     */
    static BoundingBox placeStart(ServerLevel level, StructureStart start, RandomSource random) {
        BoundingBox bounds = pieceUnion(start);
        ChunkPos minChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.minX()),
                SectionPos.blockToSectionCoord(bounds.minZ()));
        ChunkPos maxChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.maxX()),
                SectionPos.blockToSectionCoord(bounds.maxZ()));
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos -> level.getChunk(chunkPos.x, chunkPos.z));
        ChunkGenerator generator = level.getChunkSource().getGenerator();
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos -> start.placeInChunk(level,
                level.structureManager(), generator, random,
                new BoundingBox(chunkPos.getMinBlockX(), level.getMinBuildHeight(), chunkPos.getMinBlockZ(),
                        chunkPos.getMaxBlockX(), level.getMaxBuildHeight(), chunkPos.getMaxBlockZ()),
                chunkPos));
        return pieceUnion(start); // recompute: scattered pieces may have self-moved vertically
    }

    /** Union of the current piece bounding boxes (move-safe, unlike the start's cache). */
    static BoundingBox pieceUnion(StructureStart start) {
        return BoundingBox.encapsulatingBoxes(
                start.getPieces().stream().map(StructurePiece::getBoundingBox).toList()).orElseThrow();
    }

    /**
     * Books the placed start into the chunk structure data (start + references), the same
     * bookkeeping natural generation performs — structure-aware features like
     * {@code /locate structure} can then resolve it from the chunk.
     */
    static void registerStart(ServerLevel level, StructureStart start, BoundingBox bounds) {
        Structure structure = start.getStructure();
        ChunkAccess startChunk = level.getChunk(start.getChunkPos().x, start.getChunkPos().z);
        startChunk.setStartForStructure(structure, start);
        ChunkPos minChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.minX()),
                SectionPos.blockToSectionCoord(bounds.minZ()));
        ChunkPos maxChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.maxX()),
                SectionPos.blockToSectionCoord(bounds.maxZ()));
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos ->
                level.getChunk(chunkPos.x, chunkPos.z).addReferenceForStructure(structure, start.getChunkPos().toLong()));
    }

    /** Deterministic placement random (chest loot, decoration rolls) per landmark. */
    static RandomSource placementRandom(BlockPos anchor) {
        return RandomSource.create(FrozenParams.mapSeed() ^ anchor.asLong());
    }
}
