/**
 * Pale Garden mob family (P6-W9/W910): the Pale Sentinel, a weeping-angel-style guardian
 * that creeps at players while unobserved and freezes solid the moment anyone looks at
 * it ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3). Registered through this
 * family's own {@link dev.projecteclipse.eclipse.entity.pale.PaleEntities} registrar
 * (zero edits to {@code EclipseEntities}); renderers live in
 * {@code dev.projecteclipse.eclipse.client.entity.pale}. The observed check (FOV cone +
 * raycast occlusion + hysteresis) is isolated in
 * {@link dev.projecteclipse.eclipse.entity.pale.ObservedFreezeHelper}. Spawning is owned
 * by P6-W6's spawn rules gated on {@code SpawnGates.PALE_GARDEN} (default FALSE — admin
 * {@code /summon eclipse:pale_sentinel} until P1 lands the biome).
 */
package dev.projecteclipse.eclipse.entity.pale;
