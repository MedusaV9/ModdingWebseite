/**
 * Dungeon mob family (P6-W10/W910): the Eclipse Cultist — the robed shadow-bolt caster
 * that populates the Collapsed Vault / Umbral Warrens spawners
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3) — and its
 * {@link dev.projecteclipse.eclipse.entity.dungeon.ShadowBoltProjectile}, which the Rift
 * Warden's volleys reuse. Registered through this family's own
 * {@link dev.projecteclipse.eclipse.entity.dungeon.DungeonEntities} registrar (zero edits
 * to {@code EclipseEntities}); renderers live in
 * {@code dev.projecteclipse.eclipse.client.entity.dungeon}. Spawning is dungeon-spawner
 * driven: {@code eclipse:eclipse_cultist} sits in the default per-dungeon arrays of
 * {@code worldgen/structure/dungeon/DungeonSpawners} and falls back to vanilla mobs until
 * the registrar wiring lands.
 */
package dev.projecteclipse.eclipse.entity.dungeon;
