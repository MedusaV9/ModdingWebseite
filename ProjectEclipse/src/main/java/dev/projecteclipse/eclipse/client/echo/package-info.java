/**
 * WOAH-05 Echo-Grove client systems (plan §4): the zone grade, the windowed
 * Photon loops and the orb attach-loops. Server logic lives in
 * {@code dev.projecteclipse.eclipse.woah.echogrove}; renderers in
 * {@code client.entity.echo}.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.client.echo.EchoGroveClientState} —
 *       payload mirror of the quest/lifecycle snapshot + the "anchor without
 *       sync" tree-center derivation.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.echo.EchoGroveFx} — the
 *       {@code eclipse:echo_grade} pipeline (cold↔golden via Warmth) and the
 *       ground-fog/spores/tree-lights windowed loops.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.echo.EchoPhotonFxRows} — the
 *       {@code PhotonFxRegistry} row registrar for every {@code woah_echo_*}
 *       cue.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.echo.EchoOrbGlowFx} — the
 *       memory-orb halo attach-loops ({@code PhotonMobFx} schema, feature-local
 *       so the shared table stays untouched).</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.client.echo;
