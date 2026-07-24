/**
 * The v2 custom mobs ({@code docs/ideas/04_content.md} §1) and their day/event-keyed
 * server-tick spawner. Entity types + attributes are registered in
 * {@link dev.projecteclipse.eclipse.entity.EclipseEntities}; hand-coded cube models and
 * renderers live client-side in {@code dev.projecteclipse.eclipse.client.entity}.
 * {@link dev.projecteclipse.eclipse.entity.EclipseSpawner} owns all spawn rules plus the
 * Pale/Umbral night-event scheduling (persisted in
 * {@code core.state.EclipseWorldState#getActiveNightEvent}).
 */
package dev.projecteclipse.eclipse.entity;
