// owner: P6-W7 (created by W8 which landed first — plan §3-W8 package-info rule;
// W7 keeps/extends this file, W8 will not touch it again)
/**
 * Client renderers for the fog-storm mob family (P6-W7/W8,
 * {@code docs/plans_v3/P6_mobs_models_builds.md} §2.3). All are thin
 * {@code EclipseGeoRenderer} subclasses — the asset triple resolves off the entity's
 * geo id. W7 residents: Fog Revenant + Storm Hound renderers registered via
 * {@code FogRenderers}. W8 residents (separate files per the no-shared-file rule):
 * {@code FogColossusRenderer} registered via {@code FogEliteRenderers}. Registration
 * no-ops while the matching entity registrar is unwired ({@code isBound()} guards).
 */
package dev.projecteclipse.eclipse.client.entity.fog;
