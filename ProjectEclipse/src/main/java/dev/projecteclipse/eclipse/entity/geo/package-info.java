/**
 * FROZEN GeckoLib base layer for every P6 mob/boss family (P6-W1;
 * {@code docs/plans_v3/P6_mobs_models_builds.md} §2.1, conventions handoff in
 * {@code docs/plans_v3/handoff/P6_geckolib_conventions.md}). Provides the two-controller
 * idiom ({@code base} for idle/walk, {@code action} for server-triggered one-shots) via
 * {@link dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob} (PathfinderMob line) and
 * {@link dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster} (Monster line), plus the
 * frozen animation-id scheme {@code animation.<entity_path>.<name>} in
 * {@link dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations}. Client mirrors live
 * in {@code dev.projecteclipse.eclipse.client.entity.geo}.
 */
package dev.projecteclipse.eclipse.entity.geo;
