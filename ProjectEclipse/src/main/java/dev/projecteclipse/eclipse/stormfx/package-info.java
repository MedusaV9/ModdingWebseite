/**
 * Fog-storm walls &amp; the intro smoke/storm vortex (P2 W9 — R14/R15).
 *
 * <p>Client side: {@link dev.projecteclipse.eclipse.stormfx.StormFxClient} owns the live
 * storm list, lightning bolts, shell arcs, vortex wisps and the churn loop;
 * {@link dev.projecteclipse.eclipse.stormfx.StormWallRenderer} draws the shells, the opaque
 * never-see-inside occluder and every lightning ribbon;
 * {@link dev.projecteclipse.eclipse.stormfx.StormInteriorFx} clamps fog, feeds the
 * {@code eclipse:storm_interior} post grade and rains inside.</p>
 *
 * <p>Server side: {@link dev.projecteclipse.eclipse.stormfx.StormRegistry} is the storm
 * source of truth (spawn/dissipate control API + login resync);
 * {@link dev.projecteclipse.eclipse.stormfx.StormReveal} runs the two-phase reveal
 * choreography for P1's fog-storm areas.</p>
 *
 * <p>Iris rule (§7 risk 1): the wall/occluder/bolt geometry and the Quasar emitters render
 * under shaderpacks; only the {@code storm_interior} post grade is Iris-gated (by
 * {@code VeilPostController}). Every emitter spawn and the bolt impact light run through
 * {@code FxBudget} (STORM channel / light slots).</p>
 */
package dev.projecteclipse.eclipse.stormfx;
