/**
 * FROZEN client GeckoLib base layer (P6-W1): the shared renderer base
 * {@link dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer} every P6 mob
 * renderer extends — defaulted asset paths ({@code geo/entity/<id>.geo.json},
 * {@code animations/entity/<id>.animation.json}, {@code textures/entity/<id>.png}),
 * optional {@code _glowmask} emissive layer, upright-death suppression, and translucent
 * render-type opt-in. Registration stays a one-liner in each family's own
 * {@code @EventBusSubscriber(Dist.CLIENT)} class (no layer definitions, no bakeLayer).
 * See {@code docs/plans_v3/handoff/P6_geckolib_conventions.md}.
 */
package dev.projecteclipse.eclipse.client.entity.geo;
