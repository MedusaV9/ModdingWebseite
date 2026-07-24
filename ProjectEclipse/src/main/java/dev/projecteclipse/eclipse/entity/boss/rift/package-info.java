/**
 * The Rift Warden mini-boss family (P6-W10/W910): the Collapsed Vault gauntlet's 2-phase
 * blade-wraith ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4) — rift-step
 * teleports, shadow-bolt volleys, phase-2 cultist adds, purple boss bar. Registered
 * through this family's own {@link dev.projecteclipse.eclipse.entity.boss.rift.RiftEntities}
 * registrar (zero edits to {@code EclipseEntities}); renderers live in
 * {@code dev.projecteclipse.eclipse.client.entity.rift}. NOT a spawner mob: P1's vault
 * boss room places it via
 * {@link dev.projecteclipse.eclipse.entity.boss.rift.RiftWardenEntity#summonAt} (the seam
 * documented in {@code docs/plans_v3/wiring/P6-W910_wiring.md}) — the fight self-pins its
 * r=12 arena wherever it stands, so plain {@code /summon eclipse:rift_warden} also works.
 */
package dev.projecteclipse.eclipse.entity.boss.rift;
