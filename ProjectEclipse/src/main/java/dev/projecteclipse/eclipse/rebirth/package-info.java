/**
 * D11 rebirth system (server/state/API only — the skill-tree footer UI belongs to
 * W-SKILLTREE / PLANNER-A). One rebirth: pay the escalating personal umbral-shard price
 * ({@code round(8 * 1.6^n)} by default), lose ALL skill progression (XP, levels, tree),
 * gain one permanent Leben, and every future skill level costs
 * {@code levelCostMultiplierPerRebirth^n} times more (through
 * {@code skills.RebirthHooks.curveFor}).
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.rebirth.RebirthConfig} —
 *       {@code config/eclipse/rebirth.json} knobs.</li>
 *   <li>{@link dev.projecteclipse.eclipse.rebirth.RebirthState} — SavedData
 *       {@code eclipse_rebirth}: per-player count + ceremony timestamps.</li>
 *   <li>{@link dev.projecteclipse.eclipse.rebirth.RebirthService} — the all-or-nothing
 *       transaction, ceremony FX and {@code S2CRebirthStatePayload} sync.</li>
 *   <li>{@link dev.projecteclipse.eclipse.rebirth.RebirthApi} — frozen consumer surface.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.rebirth;
