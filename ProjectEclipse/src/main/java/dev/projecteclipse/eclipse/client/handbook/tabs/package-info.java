/**
 * The eight tab views of the Ledger of the Drowned, Quiet Eclipse v3 (plans_v3 P3 §3.1):
 * Status, Timeline, Rules, Revival, Rewards, Bestiary, Map and Settings (the Settings tab
 * is W3's thin {@code SettingsPanel} wrapper; everything else is W2). Each tab renders
 * into the full-width content rect assigned by {@code HandbookScreen} and reads live from
 * {@code client.ClientStateCache} (plus {@code worldgen.StageRadii}/{@code DiscGeometry}
 * shared constants for the map diagram, and the synced {@code RecipeManager} for the
 * Revival chain) — no tab caches server state of its own. All colors come from
 * {@code EclipseUiTheme} tokens, all user-facing strings resolve through
 * {@code EclipseLang.tr}, and every scrollable tab shares the minimal
 * {@code TabScrollbar} helper (B7 affordance parity).
 */
package dev.projecteclipse.eclipse.client.handbook.tabs;
