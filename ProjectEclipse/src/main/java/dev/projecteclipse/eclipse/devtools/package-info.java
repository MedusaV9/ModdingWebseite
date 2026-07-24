/**
 * Operator/dev tooling suite (W14): {@link dev.projecteclipse.eclipse.devtools.StageIO}
 * (stage annulus snapshots — save/load/revert {@code <world>/eclipse/stages/<n>.bin});
 * {@link dev.projecteclipse.eclipse.devtools.PristineSnapshots} (whole-region pristine
 * world snapshots, restored via marker file at server start);
 * {@link dev.projecteclipse.eclipse.devtools.PhaseScheduler} (real-time day advance with a
 * global countdown bossbar); {@link dev.projecteclipse.eclipse.devtools.TimelineInspector}
 * ({@code /eclipse timeline} state dump); and
 * {@link dev.projecteclipse.eclipse.devtools.ConfigEditor} (server side of the goal editor
 * GUI — perm-checked {@code days.json}/{@code milestones.json} writes). All wired into the
 * {@code /eclipse} command tree by {@code admin.EclipseCommands}.
 */
package dev.projecteclipse.eclipse.devtools;
