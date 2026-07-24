/**
 * Client renderers for the ambience mob family (P6-W1) — this family's own
 * {@code @EventBusSubscriber(Dist.CLIENT)} registration class per the P6 no-shared-file
 * rule ({@code EclipseEntityRenderers} is never touched; GeckoLib needs no layer
 * definitions). The Drift Lantern renderer doubles as the reference use of the frozen
 * {@link dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer} base:
 * glowmask + upright death + translucency in one constructor.
 */
package dev.projecteclipse.eclipse.client.entity.ambient;
