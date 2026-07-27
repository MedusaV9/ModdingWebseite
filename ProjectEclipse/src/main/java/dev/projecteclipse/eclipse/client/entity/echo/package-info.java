/**
 * WOAH-05 Echo-Grove renderers (plan §4.3): the pale scene-actor ghosts and the
 * memory orbs. Entities live in {@code dev.projecteclipse.eclipse.woah.echogrove};
 * client FX in {@code client.echo}.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.echo.EchoGhostRenderer} —
 *       the {@code GhostPlayerRenderer} bauart over {@code echo_ghost.png} with
 *       scene-ACTION poses (SIT/WAVE), fade/glow alpha and the moonlit
 *       silhouette pass.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.echo.EchoGhostWolfRenderer}
 *       — vanilla {@code WolfModel} with the same translucent-alpha technique.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.echo.MemoryOrbRenderer} —
 *       camera-facing emissive quad (photon-less baseline of the orb glow).</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.echo.EchoRenderers} —
 *       typed renderer registration.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.client.entity.echo;
