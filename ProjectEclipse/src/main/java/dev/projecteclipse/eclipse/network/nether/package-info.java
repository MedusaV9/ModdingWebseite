/**
 * Network seam of the day-2 nether-opening sequence: {@link
 * dev.projecteclipse.eclipse.network.nether.S2CNetherOpenPayload} and its self-registering
 * registrar {@link dev.projecteclipse.eclipse.network.nether.NetherOpenPayloads}. Own
 * {@code RegisterPayloadHandlersEvent} subscriber under its own version group — the shared
 * payload hubs ({@code network.EclipsePayloads}, {@code network.fx.FxPayloads}) stay
 * untouched.
 */
package dev.projecteclipse.eclipse.network.nether;
