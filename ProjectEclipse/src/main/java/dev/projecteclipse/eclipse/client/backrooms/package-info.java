/**
 * Client presentation of the Backrooms portal event (plans_v5 PLAN-C C18,
 * {@code docs/plans_v3/plans_v5/IDEAS-backrooms_finale.md} §A). Server logic lives in
 * {@code dev.projecteclipse.eclipse.backrooms}; this package owns the three client-only
 * pieces:
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.client.backrooms.JumpscareOverlay} — THE
 *       0.8 s jumpscare envelope (face ≤ 85% alpha + sting + one CameraDirector shake
 *       impulse; {@code reducedFx} renders vignette+sound only). Installs itself as the
 *       {@code S2CJumpscarePayload} consumer on class load.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.backrooms.BackroomsBuzz} — the
 *       non-positional fluorescent mains-buzz loop (alias-pitched hum at 0.55), volume
 *       keyed off measured block light (dip on flicker) and Wanderer proximity
 *       (hush-when-stalked).</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.backrooms.BackroomsRenderers} — the
 *       Wanderer's {@code GlitchedGeoRenderer} registration over the
 *       {@code glitched_wanderer} asset triple.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.client.backrooms;
