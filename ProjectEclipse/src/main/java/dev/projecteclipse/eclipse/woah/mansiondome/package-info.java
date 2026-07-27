/**
 * WOAH-01 — the MANSION GLITCH DOME ({@code docs/plans_v3/woah/PLAN-01_mansion_glitch_dome.md}):
 * once the Woodland Mansion (landmark {@code eclipse:mansion}, stage 4) is PLACED, it sits
 * under an opaque glitch shield bubble. Inside runs the combined green outline + scanlines
 * GLITCHZONE effect ({@code dome}); outside only a black glitching shell sphere and a
 * 200-block sky beam are visible. The {@code glitch_emitter} device on the roof takes
 * {@value dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeState#MAX_HITS} player
 * melee hits; the final hit runs the destruction sequence (shell shatters into ~240
 * {@code BlockDisplay} shards, loot, the interior glitch fades, three scanline
 * aftershocks follow).
 *
 * <p>Ownership: {@link dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeService} is
 * the single lifecycle/tick owner; {@link
 * dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeState} persists everything
 * (restart-safe mid-sequence). Client half lives in {@code woah.mansiondome.client}
 * (never loaded on a dedicated server). Mod-bus bootstrap: one line in
 * {@code woah.WoahFeatures} under the WOAH-01 anchor.</p>
 */
package dev.projecteclipse.eclipse.woah.mansiondome;
