/**
 * WOAH-02 Gravitationsbruch — client-only classes (the {@code woah.resonance.client}
 * precedent: referenced fully-qualified from {@code GravityRiftPayloads}' handler so
 * nothing here ever loads on a dedicated server).
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.client.GravityRiftClientState}
 *       — payload mirror (built/anchor/inversion window), the eased inside-amount and
 *       the LOCAL pulse-beat raster (identical absolute math as the server).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.client.GravityRiftFxRows}
 *       — {@code PhotonFxRegistry} rows for the 3 one-shot cues + the 2 windowed
 *       loops (LAYER over Quasar baselines — photon-less degradation law).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.client.GravityRiftAmbience}
 *       — hysteresis windows for the light-column/motes loops + the positional
 *       drone (SanctumHum recipe, inversion pitch bend).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.gravityrift.client.GravityRiftLensFx}
 *       — the {@code eclipse:gravity_lens} Veil post pass (FEATURE priority):
 *       refraction shimmer, pulse shock front, inversion ripple.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.woah.gravityrift.client;
