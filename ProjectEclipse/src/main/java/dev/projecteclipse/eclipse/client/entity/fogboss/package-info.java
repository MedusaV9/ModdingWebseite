/**
 * Client renderers for the Fog Tyrant boss family (P6-W11): the tyrant's GeckoLib
 * renderer plus this family's own auto-subscribed {@link
 * dev.projecteclipse.eclipse.client.entity.fogboss.FogBossRenderers} registration
 * (guarded on {@code DeferredHolder.isBound()} so the client boots green until the
 * {@code FogBossEntities.register(...)} wiring line from
 * {@code docs/plans_v3/wiring/WB-TYRANT_wiring.md} lands). Server-side family lives in
 * {@code dev.projecteclipse.eclipse.entity.boss.fog}; the storm-pack adds it summons
 * (storm hounds, revenants, colossus) are rendered by
 * {@code dev.projecteclipse.eclipse.client.entity.fog}.
 */
package dev.projecteclipse.eclipse.client.entity.fogboss;
