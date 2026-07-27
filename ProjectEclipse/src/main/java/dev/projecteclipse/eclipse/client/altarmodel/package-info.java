/**
 * Client side of the altar's GeckoLib monument model (F-076):
 * {@link dev.projecteclipse.eclipse.client.altarmodel.AltarModelRenderer} draws the
 * plinth / rune plates / floating eclipse core / counter-rotating rune rings / debris
 * satellites from the altar block entity (glowmask emissives included), and
 * {@link dev.projecteclipse.eclipse.client.altarmodel.AltarModelRenderers} registers it.
 * Server-side one-shot triggers (heartbeat / gift / erupt / stage_up) ride GeckoLib's
 * own BE trigger network path — see {@code ritual.AltarModelTriggers}.
 */
package dev.projecteclipse.eclipse.client.altarmodel;
