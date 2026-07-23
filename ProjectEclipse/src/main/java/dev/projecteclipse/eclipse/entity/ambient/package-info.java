/**
 * Ambience/flavor mob family (P6-W1): entities that dress the world without fighting in
 * it. Registered through this family's own
 * {@link dev.projecteclipse.eclipse.entity.ambient.AmbientEntities} registrar (zero edits
 * to {@code EclipseEntities}); renderers live in
 * {@code dev.projecteclipse.eclipse.client.entity.ambient}. First resident: the Drift
 * Lantern, the GeckoLib pipeline pilot ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.3). Spawning is owned by P6-W6's spawn rules — this package only exposes the
 * {@code DriftLanternEntity.spawnLane} placement helper.
 */
package dev.projecteclipse.eclipse.entity.ambient;
