/**
 * Client HUD suite (worker 8): surgical bossbar skinning ({@link
 * dev.projecteclipse.eclipse.client.hud.BossbarSkin}), the Eclipse sidebar status panel
 * ({@link dev.projecteclipse.eclipse.client.hud.SidebarPanel}) and the typewriter/sweep
 * announcement overlay ({@link dev.projecteclipse.eclipse.client.hud.AnnouncementOverlay}
 * with {@link dev.projecteclipse.eclipse.client.hud.TypewriterLine}). Everything renders
 * from {@code ClientStateCache} + server payloads; all classes are client-only
 * ({@code Dist.CLIENT} subscribers, referenced only from client payload handlers).
 */
package dev.projecteclipse.eclipse.client.hud;
