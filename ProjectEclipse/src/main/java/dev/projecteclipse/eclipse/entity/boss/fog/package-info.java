/**
 * The Fog Tyrant apex-boss family (P6-W11/WB-TYRANT): the 4-block crowned storm monarch
 * that lairs in the strongest fog storm ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.4) — fog-lance volleys, storm-step teleports, crown lightning, blind squalls,
 * storm-hound/colossus adds, purple notched boss bar. Registered through this family's
 * own {@link dev.projecteclipse.eclipse.entity.boss.fog.FogBossEntities} registrar (zero
 * edits to {@code EclipseEntities}); renderers live in
 * {@code dev.projecteclipse.eclipse.client.entity.fogboss}. NOT a spawner mob: P1's
 * mature-storm flow marks the lair via
 * {@link dev.projecteclipse.eclipse.entity.boss.fog.FogBankMarker#markLair} or summons
 * directly via
 * {@link dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity#summonAt} (seams
 * documented in {@code docs/plans_v3/wiring/WB-TYRANT_wiring.md}) — the fight self-pins
 * its r=16 arena wherever it stands, so plain {@code /summon eclipse:fog_tyrant} also
 * works anywhere.
 */
package dev.projecteclipse.eclipse.entity.boss.fog;
