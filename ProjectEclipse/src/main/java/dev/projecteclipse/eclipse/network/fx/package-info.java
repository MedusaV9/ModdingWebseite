/**
 * P2 FX network layer (owned by P2-W1): the nine {@code eclipse:fx/...} payloads and their
 * self-registering registrar {@link dev.projecteclipse.eclipse.network.fx.FxPayloads}.
 * Registers on its own {@code RegisterPayloadHandlersEvent} subscriber (MOD bus) under its
 * own version group — {@code network.EclipsePayloads} stays untouched.
 */
package dev.projecteclipse.eclipse.network.fx;
