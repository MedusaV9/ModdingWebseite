/**
 * Client renderers for the GLITCHED family (P6-W8,
 * {@code docs/plans_v3/P6_mobs_models_builds.md} §2.3 "glitched"). The signature
 * datamosh flicker lives in
 * {@link dev.projecteclipse.eclipse.client.entity.glitch.GlitchedGeoRenderer}: the
 * texture swaps between {@code <id>.png} and {@code <id>_alt.png} in short
 * hash-scheduled bursts (2–4 t every 40–80 t, deterministic per entity — no animated
 * textures, no config), the glowmask layer follows automatically (GeckoLib appends
 * {@code _glowmask} to whichever albedo is active, so the alt frame's chromatic seams
 * glow too), plus a rare 1-tick pose pop that reads as a UV/render glitch.
 * Registration: {@link dev.projecteclipse.eclipse.client.entity.glitch.GlitchRenderers}
 * (annotation-discovered, no-ops until the {@code GlitchEntities} wiring line lands).
 */
package dev.projecteclipse.eclipse.client.entity.glitch;
