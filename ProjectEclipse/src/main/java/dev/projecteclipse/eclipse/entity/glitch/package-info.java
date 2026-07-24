/**
 * The GLITCHED family (P6-W8, {@code docs/plans_v3/P6_mobs_models_builds.md} §2.3):
 * corrupted mob variants that haunt freshly expanded map rings — bodies datamoshed off
 * their vanilla silhouettes, textures flickering between a base and an {@code _alt}
 * corruption frame (client half in {@code client/entity/glitch}). Population comes from
 * the existing {@code glitch/GlitchSpawnService} (fresh-ring sampling, day ≥ 8), and
 * {@code glitch/GlitchDrops} pays 1–2 {@code eclipse:glitch_shard} per kill via the
 * {@code #eclipse:glitched} entity-type tag — the per-mob loot tables here only add
 * corrupted vanilla scraps, never shards (no double-dipping the heart economy).
 *
 * <p>Registrar: {@link dev.projecteclipse.eclipse.entity.glitch.GlitchEntities} (own
 * {@code DeferredRegister}; one wiring line per
 * {@code docs/plans_v3/wiring/P6-W8_wiring.md}). Shared behavior (blink teleport,
 * glitch ambience, scripted dissolve death) lives in
 * {@link dev.projecteclipse.eclipse.entity.glitch.GlitchedMonster}.</p>
 */
package dev.projecteclipse.eclipse.entity.glitch;
