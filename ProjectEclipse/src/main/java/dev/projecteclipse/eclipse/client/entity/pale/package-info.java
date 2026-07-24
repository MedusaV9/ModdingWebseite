/**
 * Client renderers for the pale-garden mob family (P6-W9/W910): the Pale Sentinel's
 * GeckoLib renderer plus this family's own auto-subscribed {@link
 * dev.projecteclipse.eclipse.client.entity.pale.PaleRenderers} registration (guarded on
 * {@code DeferredHolder.isBound()} so the client boots green until the
 * {@code PaleEntities.register(...)} wiring line from
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md} lands). Server-side family lives in
 * {@code dev.projecteclipse.eclipse.entity.pale}.
 */
package dev.projecteclipse.eclipse.client.entity.pale;
