/**
 * Client-side render additions for the uniform "eclipsed" player skin (P6-W12, plans_v3
 * P6 §2.7). The skin itself is swapped by {@code client.mixin.AbstractClientPlayerMixin}
 * (untouched); this package only layers the emissive pass on top:
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.player.EclipsedPlayerGlowLayer} —
 *       re-renders the player model with {@code RenderType.eyes} over
 *       {@code textures/entity/eclipsed_player_glow.png} (heart + veins + eyes only), so
 *       the purple heart stays fullbright at night.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.player.PlayerLayerHandler} — the
 *       {@code EntityRenderersEvent.AddLayers} subscriber that attaches the layer to both
 *       player renderers (WIDE + SLIM skin models). Self-registering; no
 *       {@code EclipseMod} wiring required.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.client.entity.player;
