/**
 * Client-only dimensional-rift FX (P2-W8, R17): the reusable glitch-tear effect consumed by
 * structure-spawn animations (P2-W7), the xbox event portal (P5-W9) and fog-storm reveals
 * (P2-W9).
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.veilfx.rift.RiftFx} — rift registry + lifecycle;
 *       the FROZEN {@code openRift}/{@code closeRift} handlers behind the
 *       {@code eclipse:fx/rift_open|close} payload events.</li>
 *   <li>{@link dev.projecteclipse.eclipse.veilfx.rift.RiftRenderer} — world-space star-tear
 *       + portal-surface geometry (renders under Iris shaderpacks — it is the post-FX
 *       fallback tier; ≤ 400 tris per rift, zero per-frame allocations).</li>
 * </ul>
 *
 * <p>The screen-side half of the effect (the {@code eclipse:rift_glitch} post pipeline and
 * the portal/loading transition API) lives in
 * {@link dev.projecteclipse.eclipse.veilfx.TransitionFx}.</p>
 */
package dev.projecteclipse.eclipse.veilfx.rift;
