/**
 * The day-14 Ferryman crossing rework (plans_v5 PLAN-C C10): altar dead-door →
 * wait-for-all gate on the limbo ghost ship → transformation beat → the fight in the
 * dedicated {@code eclipse:ferryman_arena} void dimension, with a spectator ship for
 * the fallen.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.ArenaDimension} — dimension key of
 *       the arena ({@code minigames/MinigameDimensions} pattern).</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.ArenaState} — tiny SavedData
 *       (overworld storage): arena build stamp, fight-running flag, altar-door
 *       bookkeeping for restart cleanup.</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.ArenaBuilder} — deterministic,
 *       idempotent builder of the ship-turned-ring-arena + spectator ship
 *       ({@code GhostShipBuilder} idempotence law).</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.AltarDoor} — the dead-door
 *       multiblock stamped at the altar at finale arm time (reuses the
 *       {@code limbo.door} registry via its API).</li>
 *   <li>{@link dev.projecteclipse.eclipse.ferryman.ArenaFight} — the crossing
 *       orchestrator: gate → arrival cutscene → morph → transport → fight →
 *       victory/reset handoffs.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.ferryman;
