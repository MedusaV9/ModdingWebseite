/**
 * Client renderers for the dungeon mob family (P6-W10/W910): the Eclipse Cultist's
 * GeckoLib renderer, the Shadow Bolt's tiny geo spike-orb renderer, and this family's own
 * auto-subscribed {@link dev.projecteclipse.eclipse.client.entity.dungeon.DungeonRenderers}
 * registration (guarded on {@code DeferredHolder.isBound()} so the client boots green
 * until the {@code DungeonEntities.register(...)} wiring line from
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md} lands). Server-side family lives in
 * {@code dev.projecteclipse.eclipse.entity.dungeon}.
 */
package dev.projecteclipse.eclipse.client.entity.dungeon;
