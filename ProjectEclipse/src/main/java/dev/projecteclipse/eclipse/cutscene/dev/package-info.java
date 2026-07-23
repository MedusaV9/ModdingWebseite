/**
 * Dev/QA tooling of the cutscene+FX stack (P2 R12):
 * {@link dev.projecteclipse.eclipse.cutscene.dev.FxDevCommands} registers the
 * {@code /eclipsefx} Brigadier tree (permission 3) plus its
 * {@code devtools.dev.DevCommandRegistry} docs;
 * {@link dev.projecteclipse.eclipse.cutscene.dev.FxDevPayloads} bridges the client-only
 * actions (Veil post overrides, uniform overrides, emitter spawns, sun-debug HUD) to
 * {@link dev.projecteclipse.eclipse.cutscene.dev.FxDevClient}. Everything here is
 * operator-facing debug surface — gameplay code must not depend on this package.
 */
package dev.projecteclipse.eclipse.cutscene.dev;
