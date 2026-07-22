/**
 * The six tab views of the Ledger of the Drowned ({@code docs/ideas/03_ui_ux.md} §B):
 * Status, Timeline, Rules, Rewards, Bestiary and Map. Each tab renders into the right-page
 * content rect assigned by {@code HandbookScreen} and reads live from
 * {@code client.ClientStateCache} (plus {@code worldgen.StageRadii}/{@code DiscGeometry}
 * shared constants for the map diagram) — no tab caches server state of its own.
 */
package dev.projecteclipse.eclipse.client.handbook.tabs;
