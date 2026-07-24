/**
 * The vanilla-integration pipeline of the disc world (P1 design D1): real per-biome
 * placed features, real vanilla carvers and chunk-generation mob seeding layered on top
 * of the pure {@link dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction} base, with
 * hull protection and fixed-map-seed determinism.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline} — the unified
 *       carve → decorate → seed sequence, callable both from chunk generation and (via
 *       {@code runOnLiveChunk}) from the ring-growth sweep on live chunks.</li>
 *   <li>{@link dev.projecteclipse.eclipse.worldgen.vanilla.BiomeFeatureFilter} — each
 *       biome's real {@code BiomeGenerationSettings} minus the deny-listed vanilla ore
 *       features (the {@code worldgen/ore} engine replaces them).</li>
 *   <li>{@link dev.projecteclipse.eclipse.worldgen.vanilla.DiscCarverEngine} — vanilla
 *       cave/canyon carvers run with a fixed seed, a disabled aquifer and self-built
 *       carving context (no {@code NoiseRouter} terrain, no ProtoChunk state).</li>
 *   <li>{@link dev.projecteclipse.eclipse.worldgen.vanilla.FixedSeedGenRegion} — a
 *       delegating {@code WorldGenLevel} whose {@code getSeed()} (and biome-zoom seed)
 *       is the frozen map seed, so decoration is identical in every save.</li>
 *   <li>{@link dev.projecteclipse.eclipse.worldgen.vanilla.HullRepair} — re-asserts the
 *       bedrock seal, stalactite fringe and rim knife-edge after carving/decoration so
 *       the floating hull is never punctured.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.worldgen.vanilla;
