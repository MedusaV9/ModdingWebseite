/**
 * Disc-world generation core (v2). One deterministic terrain function
 * ({@link dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction}), two consumers:
 * the {@link dev.projecteclipse.eclipse.worldgen.DiscChunkGenerator} for never-generated
 * chunks and the runtime ring-growth sweep (worker 4) for already-generated ones.
 * Everything is seeded exclusively from
 * {@link dev.projecteclipse.eclipse.worldgen.DiscMapData#ECLIPSE_SEED} — never the world seed.
 */
package dev.projecteclipse.eclipse.worldgen;
