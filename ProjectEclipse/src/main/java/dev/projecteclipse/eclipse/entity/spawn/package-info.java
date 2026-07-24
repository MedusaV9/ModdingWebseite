/**
 * Spawn integration for the P6 mob families (P6-W6/W56,
 * {@code docs/plans_v3/P6_mobs_models_builds.md} §2.8): the pluggable area gates
 * ({@link dev.projecteclipse.eclipse.entity.spawn.SpawnGates}) and the 100 t spawner
 * pass ({@link dev.projecteclipse.eclipse.entity.spawn.EventSpawnRules}) that populates
 * fog storms, fresh glitch rings, the pale garden and the limbo buoy lane. Entity types
 * are resolved from frozen string ids at spawn time
 * ({@code BuiltInRegistries.ENTITY_TYPE.getOptional}) — a mob family that has not merged
 * yet is a logged-once no-op, never a crash. {@code entity/EclipseSpawner} (the legacy
 * v2 spawner) is never touched; its placement semantics are deliberately reimplemented
 * here.
 */
package dev.projecteclipse.eclipse.entity.spawn;
