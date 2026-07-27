/**
 * WOAH-01 MANSION GLITCH DOME — client half (plan §4). Everything in here is
 * {@code @OnlyIn(Dist.CLIENT)} and reached only through lazy seams (the payload handler
 * in {@code MansionDomePayloads} and self-registering {@code @EventBusSubscriber}
 * classes), so the server never classloads it.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.woah.mansiondome.client.MansionDomeClient} —
 *       the snapshot cache + eased visibility, the {@code eclipse:dome_shell} post row
 *       (FEATURE) and feeder, the 48-block Photon loop window and the shield drone
 *       loop;</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.mansiondome.client.DomeShellRenderer} —
 *       the OPAQUE, depth-writing CPU shell sphere (the "you cannot see in" guarantee,
 *       shader-less and therefore Iris-proof);</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.mansiondome.client.DomeBeamRenderer} —
 *       the 200-block sky beam off the device antenna (SupplyBeamRenderer clone);</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.mansiondome.client.DomeEmitterRenderer} —
 *       the GeckoLib device renderer (glowmask core, crack-stage tint/jitter);</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.mansiondome.client.MansionDomeFxRows} —
 *       the {@code PhotonFxRegistry} rows for the four {@code DomeCues}.</li>
 * </ul>
 *
 * <p>The INTERIOR fullscreen effect ({@code eclipse:glitch_dome}) needs no code here:
 * {@code client.GlitchZoneFx} auto-registers one TRANSITION row per
 * {@code GlitchZoneEffects} id, and the server drives it through the persistent
 * {@code dome} glitch zone (§3.5).</p>
 */
package dev.projecteclipse.eclipse.woah.mansiondome.client;
