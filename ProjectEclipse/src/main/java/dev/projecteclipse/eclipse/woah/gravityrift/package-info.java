/**
 * WOAH-02 "Gravitationsbruch" (Gravity Rift) — a permanent walkable gravity anomaly in
 * the bamboo-jungle ring (plan {@code docs/plans_v3/woah/PLAN-02_gravity_rift.md};
 * landmark row {@code eclipse:gravity_rift, -239, 167, 40, 4} frozen in
 * {@code DiscMapDefaults}).
 *
 * <p>Server classes:</p>
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftZone} — pure
 *       geometry: crater profile, zone cylinder, parkour/island layout, the ~220
 *       deterministic orbital piece definitions and the local hash.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftState} — own tiny
 *       SavedData ({@code data/eclipse_gravity_rift.dat}, overworld storage).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftBuilder} — the
 *       budgeted crater carve + the static REAL block islands (parkour steps, two
 *       ambient mega floes, the loot floe, heart pedestal, buried sentinel).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftService} — tick
 *       owner: stage listener/catch-up, zone detection, low-G attributes, the 45 s
 *       pulse beat, the 10 s heart-hit inversion, item/XP drift, chunk tickets and
 *       payload sync.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftOrbitals} — the
 *       three-shell BlockDisplay choreographer + the pulsing heart composite +
 *       tag-reconcile (the {@code SanctumOrbitals} laws).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftCues} /
 *       {@link dev.projecteclipse.eclipse.woah.gravityrift.S2CGravityRiftPayload} /
 *       {@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftPayloads} — cue
 *       ids + the self-registering S2C payload lane (own registrar; {@code FxPayloads}
 *       and {@code EclipsePayloads} stay untouched).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftDevCommands} —
 *       {@code /dev woah gravity …} (own {@code literal("dev")} tree; Brigadier merges).</li>
 * </ul>
 *
 * <p>Client classes live in {@code woah.gravityrift.client} (the
 * {@code woah.resonance.client} precedent) and are only referenced fully-qualified from
 * payload handlers so they never load on a dedicated server.</p>
 */
package dev.projecteclipse.eclipse.woah.gravityrift;
