/**
 * Client side of the Respawn Door (P6-W3, plans_v3 §2.5):
 * {@link dev.projecteclipse.eclipse.client.entity.door.RespawnDoorRenderer} draws the
 * whole 3×5 multiblock from the controller cell's GeckoLib model (glowmask seam/glyphs
 * included), and {@link dev.projecteclipse.eclipse.client.entity.door.DoorRenderers}
 * registers it, owns the per-viewer ghost rule ("ghosts always see the door closed" —
 * zero networking) and ingests the {@code S2CDoorCuePayload} personal pose cues.
 */
package dev.projecteclipse.eclipse.client.entity.door;
