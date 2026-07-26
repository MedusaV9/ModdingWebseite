/**
 * FERRYMAN2 — the finale arc that BUILDS UP to the C10 crossing
 * (F-044/F-045/F-045b/F-046/F-046b):
 *
 * <ol>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.finale.DayRiftOrbits} — every dawn a
 *       dark rift opens over the center island and drops block-display debris that
 *       accumulates into a slow orbit (count/seed persisted, entities never).</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.finale.PortalFormation} — on day 14
 *       the whole orbit synchronizes, spirals down and assembles the portal gate over
 *       the water off the island.</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.finale.FinaleSequence} — the giant
 *       key over the altar, its flight to the gate, the breach (ghosts + purple veil)
 *       and the teleport handoff into the existing
 *       {@link dev.projecteclipse.eclipse.ferryman.ArenaFight} crossing.</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.finale.ArenaMorphLayer} — the F-046
 *       fight-scoped ship→arena dressing (deck-expansion plank ring, violet mast/rail
 *       glow, the fog wall) applied at fight start and swept at fight end.</li>
 * </ol>
 *
 * <p>Server-authoritative: sequence state persists in
 * {@link dev.projecteclipse.eclipse.ferryman.finale.FinaleState}; every display/ghost
 * carries a command tag + live-set despawn guarantee (the {@code StormDebrisFx}
 * doctrine). Client-side pieces live in {@code client.entity.finale} (renderers) and
 * {@code veilfx.FerrymanFinaleFxRows} (Photon rows).</p>
 */
package dev.projecteclipse.eclipse.ferryman.finale;
