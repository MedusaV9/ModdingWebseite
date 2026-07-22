/**
 * Structure placement for the disc world (worker 5). The
 * {@link dev.projecteclipse.eclipse.worldgen.structure.StructureStamper} subscribes to
 * {@code WorldStageService} stage completions and stamps each stage's {@code stages.json}
 * {@code structures[]} at its {@code disc_map.json} landmark — via programmatic vanilla
 * {@code Structure.generate(...)} (temples, village, stronghold) with guaranteed
 * {@link dev.projecteclipse.eclipse.worldgen.structure.FallbackBuilders procedural fallbacks},
 * or via pure set-piece builders (fortress core, watcher statues, sundial). The
 * {@link dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder} raises the
 * spawn sanctum once per world and
 * {@link dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection} keeps its grounds
 * grief-free. All placements are deterministic (fixed landmark positions,
 * {@code ECLIPSE_SEED}-derived randomness) so stage reverts and rebuilds reproduce them.
 */
package dev.projecteclipse.eclipse.worldgen.structure;
