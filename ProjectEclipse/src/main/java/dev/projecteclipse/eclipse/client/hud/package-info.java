/**
 * Client HUD suite (worker 8): surgical bossbar skinning ({@link
 * dev.projecteclipse.eclipse.client.hud.BossbarSkin}) and the Eclipse sidebar status panel
 * ({@link dev.projecteclipse.eclipse.client.hud.SidebarPanel}). Everything renders from
 * {@code ClientStateCache} + server payloads; all classes are client-only
 * ({@code Dist.CLIENT} subscribers, referenced only from client payload handlers).
 */
package dev.projecteclipse.eclipse.client.hud;
