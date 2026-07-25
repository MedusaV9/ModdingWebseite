/**
 * GeckoLib ITEM renderers for the plans-v7 item upgrade pass
 * ({@code docs/plans_v3/plans_v5/v7/PLAN-ITEMS.md}). Mirrors the shipped wand pilot
 * ({@code dev.projecteclipse.eclipse.client.wand}): each renderer is a
 * {@code GeoItemRenderer} over a {@code DefaultedItemGeoModel} triple
 * ({@code geo/item/<id>.geo.json} + {@code animations/item/<id>.animation.json} +
 * per-item texture folder under {@code textures/item/}) with an
 * {@code AutoGlowingGeoLayer} lighting the painted {@code _glowmask}. Registration is
 * self-contained in {@link dev.projecteclipse.eclipse.client.item.ItemsAClientExtensions}
 * ({@code IClientItemExtensions#getCustomRenderer}); the item models are
 * {@code builtin/entity} so vanilla routes every perspective here, GUI included.
 */
package dev.projecteclipse.eclipse.client.item;
