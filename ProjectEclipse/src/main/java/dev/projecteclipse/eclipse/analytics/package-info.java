/**
 * Per-player-per-day analytics + the placed-block tracker (plans_v3 P4-B5, design §2.4).
 *
 * <p>{@link dev.projecteclipse.eclipse.analytics.AnalyticsService} is the SINGLE owner of the
 * shared break/place/death/damage/craft/smelt/trade/breed subscribers and fans out via
 * {@code core/signal/EclipseSignals}; other systems must not add their own break/place
 * subscribers (P4 global rule 6). Counters live in
 * {@link dev.projecteclipse.eclipse.analytics.AnalyticsState} (SavedData
 * {@code eclipse_analytics}, day-keyed, UUID-keyed so offline players stay queryable);
 * {@link dev.projecteclipse.eclipse.analytics.AnalyticsApi} is the frozen query surface for
 * awards (P4-B6) and dev commands (P5-W4). The
 * {@link dev.projecteclipse.eclipse.analytics.PlacedBlockTracker} natural-check primitive is
 * consumed by skills (T2/T6), buffs (double ore) and goal {@code naturalOnly} triggers.</p>
 */
package dev.projecteclipse.eclipse.analytics;
