/**
 * D1 collections — Skyblock-style lifetime gather counters with tiered rewards
 * (plans_v5 PLAN-D §D1, IDEAS-collections).
 *
 * <p>{@link dev.projecteclipse.eclipse.collections.CollectionsService} rides the sanctioned
 * {@code core/signal/EclipseSignals} lanes (mine/harvest/kill/shard_bank/pickup — never its
 * own NeoForge break/kill subscribers, P4 global rule 6), persists lifetime counts + granted
 * tiers in {@link dev.projecteclipse.eclipse.collections.CollectionsState} (SavedData
 * {@code eclipse_collections}, the store of record — analytics is retention-limited), and on
 * every threshold cross pays skill XP/points, unlocks recipes through the
 * {@code progression/RecipeGate} per-player lock provider and fires the tier toast payload.
 * Definitions load from the hot-reloadable
 * {@link dev.projecteclipse.eclipse.collections.CollectionsConfig}
 * ({@code config/eclipse/collections.json}, 17 authored defaults). Wire lives in
 * {@code network/collections}; the handbook tab and toast in {@code client/collections} +
 * {@code client/handbook/tabs/CollectionsTab}.</p>
 */
package dev.projecteclipse.eclipse.collections;
