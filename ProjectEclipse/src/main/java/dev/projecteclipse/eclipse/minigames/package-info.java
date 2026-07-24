/**
 * Command-triggered portal minigame events (W4-MINIGAMES) — the "old console minigames"
 * beat: {@code /dev minigame start (arena|race) [minutes]} spawns a restyled rift portal
 * near spawn; walking in teleports players into a temporary minigame dimension in
 * ADVENTURE mode with their real inventory snapshotted into SavedData and restored on
 * every exit path (including crash rescue at login). Deaths inside are cancelled before
 * the lives pipeline can run — no item loss, no Eclipse life loss, no grave, no ban.
 *
 * <p>The package deliberately REUSES the proven {@code xboxevent} architecture: the same
 * {@code IDLE → OPEN → RUNNING → CLOSING} SavedData state machine, the same
 * interaction-entity + block-display portal construct (restyled), the same
 * HIGHEST-priority {@code LivingDeathEvent} cancel, the same bossbar countdown fallback
 * and the same login-rescue seams. Where xbox installs baked region payloads, minigames
 * GENERATE their courses at open time through {@code BudgetedBlockWriter} — seeded by the
 * persisted open counter, so every open looks slightly different but a crash mid-build
 * can always resume/rebuild deterministically.</p>
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.minigames.MinigameService} — lifecycle, portal
 *       entries, inventory tickets, death protection, timer, closing.</li>
 *   <li>{@link dev.projecteclipse.eclipse.minigames.ArenaGame} — circular FFA fight
 *       platform in {@code eclipse:minigame_arena}, kit combat, kill scoring, 5-minute
 *       rounds with an anonymized podium.</li>
 *   <li>{@link dev.projecteclipse.eclipse.minigames.ElytraRace} — floating ring course in
 *       {@code eclipse:minigame_sky}, elytra + fireworks, sequential checkpoints, lap
 *       timing, first-finish/best-time announcements.</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.minigames;
