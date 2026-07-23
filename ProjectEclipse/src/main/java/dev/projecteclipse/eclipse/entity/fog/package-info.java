/**
 * Fog-storm mob family (P6-W7/W8): the creatures living inside the fog storms that roll
 * in from day 6 ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3). Registered through
 * this family's own {@link dev.projecteclipse.eclipse.entity.fog.FogEntities} registrar
 * (zero edits to {@code EclipseEntities}); renderers live in
 * {@code dev.projecteclipse.eclipse.client.entity.fog}. W7 residents: the Fog Revenant
 * (hovering wraith, r=5 blind burst) and the Storm Hound (charged pack hunter,
 * telegraphed 12-block lunge). W8 adds the Fog Colossus in its own files
 * ({@code FogEliteEntities}). Spawning is owned by P6-W6's spawn rules — placements here
 * only gate vanilla-spawner/natural placement to standard monster rules.
 */
package dev.projecteclipse.eclipse.entity.fog;
