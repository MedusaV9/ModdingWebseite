/**
 * The W13 umbral-shard reward economy: the altar shard shop ({@link
 * dev.projecteclipse.eclipse.economy.ShardEconomy} — sneak-deposit shards, action-bar offer
 * cycling, sneak-punch purchase), the reward items (Compass of the Watcher, Grave Dowser,
 * Vitae Shard, the umbral tools) and the pooled team Supply Beacon drop ({@link
 * dev.projecteclipse.eclipse.economy.SupplyBeacon}).
 *
 * <p>Currency flow: every deposited umbral shard credits BOTH the depositor's persisted
 * {@code eclipse:shards} attachment (personal purchases) and the global
 * {@code EclipseWorldState#getShardPool()} (team purchases). Personal buys deduct only the
 * personal balance; pooled buys deduct only the pool.</p>
 */
package dev.projecteclipse.eclipse.economy;
