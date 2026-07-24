/**
 * Client-side rendering for the P4-owned logout ghost ({@code eclipse:logout_ghost},
 * plans_v3 P6 §2.7 / P4 §2.12). P4-B9's {@code ghosts/LogoutGhostService} owns all server
 * logic (spawn on logout, despawn on login, reveal payload); this package renders:
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.ghost.GhostPlayerRenderer} — the
 *       vanilla player model wearing the v2 eclipsed skin at ~40% alpha, hover bob, subtle
 *       glitch jitter, suppressed vanilla nameplate, and the glitch name-reveal tag driven
 *       by {@code S2CGhostRevealPayload}.</li>
 *   <li>{@link dev.projecteclipse.eclipse.client.entity.ghost.GhostRenderers} — renderer
 *       registration by registry lookup (build stays green while the entity type is
 *       absent) plus the client-side reveal-state cache fed from
 *       {@code ClientStateCache}'s ghost-reveal mailbox fields.</li>
 * </ul>
 *
 * <p>The renderer deliberately codes against plain {@link net.minecraft.world.entity.LivingEntity}
 * — the frozen contract requires the ghost to be a LivingEntity (humanoid-sized, hittable);
 * see {@code docs/plans_v3/handoff/P6_ghost_renderer.md}.</p>
 */
package dev.projecteclipse.eclipse.client.entity.ghost;
