/**
 * The W13 umbral-shard reward economy: the altar shard shop ({@link
 * dev.projecteclipse.eclipse.economy.ShardEconomy} — sneak-deposit shards, action-bar offer
 * cycling, sneak-punch purchase), the reward items (Compass of the Watcher, Grave Dowser,
 * Vitae Shard, the umbral tools) and the pooled team Supply Beacon drop ({@link
 * dev.projecteclipse.eclipse.economy.SupplyBeacon}).
 *
 * <p>Currency flow (FINAL-DOPA-SOL §3 double-spend fix): deposited physical shards credit
 * ONLY the global {@code EclipseWorldState#getShardPool()} (team purchases); the persisted
 * {@code eclipse:shards} attachment (personal purchases) is credited only by direct
 * rewards — goals, personal quests, contracts, admin grants. Personal buys deduct only the
 * personal balance; pooled buys deduct only the pool — each shard is spendable once.</p>
 */
package dev.projecteclipse.eclipse.economy;
