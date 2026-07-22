/**
 * Client-only Veil integration for Project: Eclipse v2 — post-processing pipeline control
 * ({@link dev.projecteclipse.eclipse.veilfx.VeilPostController}) and Quasar particle system
 * spawning ({@link dev.projecteclipse.eclipse.veilfx.QuasarSpawner}).
 *
 * <p>Hard rules enforced here (see {@code docs/ideas/02_veil_vfx.md}):</p>
 * <ul>
 *   <li>Every post pipeline {@code add(...)} is gated behind
 *       {@code !EclipseIrisState.shaderPackActive() && EclipseClientConfig.veilPostFx()} —
 *       Veil post pipelines break under an active Iris shaderpack (Veil issue #34).</li>
 *   <li>Every Veil call is try/caught: the first failure per pipeline/emitter logs a warning,
 *       repeated failure disables that pipeline/emitter for the session.</li>
 *   <li>Quasar particles are NOT Iris-gated — they render fine under shaderpacks and remain
 *       as the particle fallback tier.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.veilfx;
