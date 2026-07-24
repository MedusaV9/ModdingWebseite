/**
 * Handbook 2.0 — "The Ledger of the Drowned" ({@code docs/ideas/03_ui_ux.md} §B): the
 * six-tab full-screen codex that replaced the v1 artifact popup. {@code HandbookScreen} is
 * the shell (book layout sized as percentages of the screen, unfold/page-turn animations,
 * parallax); the per-tab views live in {@code tabs/}. Shared UI plumbing intended for reuse
 * by later workers (W15 menu/settings): {@code EclipseWidget} (hover edge-detect → sound +
 * glow + cursor), {@code UiSounds} (config-gated {@code SimpleSoundInstance.forUI} helpers),
 * {@code CursorManager} (GLFW cursor lifecycle) and {@code GlitchText} (redacted "???"
 * text). Everything in this package is client-only.
 */
package dev.projecteclipse.eclipse.client.handbook;
