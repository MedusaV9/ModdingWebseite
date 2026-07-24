/**
 * The cutscene engine's server/shared side: the camera-path model + library
 * ({@link dev.projecteclipse.eclipse.cutscene.CutscenePath},
 * {@link dev.projecteclipse.eclipse.cutscene.CutscenePaths}), playback orchestration + ACK
 * watchdog ({@link dev.projecteclipse.eclipse.cutscene.CutsceneService}) and the
 * server-authoritative freeze ({@link dev.projecteclipse.eclipse.cutscene.FreezeService}).
 * Client-only camera code lives in {@code cutscene.client}.
 */
package dev.projecteclipse.eclipse.cutscene;
