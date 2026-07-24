/**
 * Client renderers for the Rift Warden boss family (P6-W10/W910): the warden's GeckoLib
 * renderer plus this family's own auto-subscribed {@link
 * dev.projecteclipse.eclipse.client.entity.rift.RiftRenderers} registration (guarded on
 * {@code DeferredHolder.isBound()} so the client boots green until the
 * {@code RiftEntities.register(...)} wiring line from
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md} lands). Server-side family lives in
 * {@code dev.projecteclipse.eclipse.entity.boss.rift}; the cultist + shadow-bolt
 * renderers it fights alongside live in
 * {@code dev.projecteclipse.eclipse.client.entity.dungeon}.
 */
package dev.projecteclipse.eclipse.client.entity.rift;
