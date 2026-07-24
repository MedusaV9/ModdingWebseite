# P3-W2 — Handbook content tabs v3 (integration ledger)

## Shipped (all files W2-owned per plan §4)

| File | Change |
|---|---|
| `client/handbook/tabs/StatusTab.java` | Quiet Eclipse rework: 2x day numeral (was 3x), heart row, slim altar progress bar (texture ring retired), goal tick draw-in now keyed on the FLIP tick (fires live, B6-side), online count REMOVED (B10/§3.3), settings entry is a real `widgets()` widget (B4) that turns to the Settings tab |
| `client/handbook/tabs/TimelineTab.java` | Flat 10px fill-drawn nodes (textures retired), hairline+label milestone divider (divider art retired), icons opposite captions, B5 centering/scroll-range fixes, B20 click consumption |
| `client/handbook/tabs/RulesTab.java` | Parchment texture retired (flat on panel), shared `TabScrollbar`, B20-safe input |
| `client/handbook/tabs/RewardsTab.java` | Raised theme rows, `GOOD`-token sated state, scrollbar + content drag (B7), crossfade-safe item icons, B20-safe input |
| `client/handbook/tabs/BestiaryTab.java` | Flat raised cards, `drift_lantern` entry added, roster fully data-driven with graceful lang fallback (see below), scrollbar + drag |
| `client/handbook/tabs/MapTab.java` | Recolored to §2.1 tokens (sealed=HAIRLINE, border=DANGER, markers=TEXT), legend respaced on the §2.2 grid |
| `client/handbook/tabs/RevivalTab.java` | NEW — §3.1 revive-chain page (see contract below) |
| `client/handbook/tabs/TabScrollbar.java` | NEW — shared minimal scrollbar (package-private; HAIRLINE track / ACCENT thumb, jump+drag, `UiSounds.click()` on press) |
| `client/handbook/tabs/package-info.java` | Updated for the 8-tab roster |
| `client/handbook/HandbookScreen.java` | ONLY the W1-ledger roster edit: `new RevivalTab()` after `RulesTab`, `new SettingsTab()` LAST, + 2 imports |

No hub files touched, no new registrations, no new textures (`rail_revival.png` already
shipped by W1; the retired v2 tab art — `parchment_tile.png`, `timeline_node_*.png`,
`divider.png`, `icons/altar_ring.png` — is now unreferenced by the handbook and can go in
the P2 asset cleanup pass).

## Compile dependency — P3-W3 (wave-2 partner) — SATISFIED

`HandbookScreen` now references `client.handbook.tabs.SettingsTab` (W3-owned). Both halves
of the assumed contract have LANDED and were verified against W3's files:

- class `dev.projecteclipse.eclipse.client.handbook.tabs.SettingsTab extends HandbookTab`
  with a no-arg constructor and `id()` returning `"settings"` — matches.
- Lang key `gui.eclipse.handbook.tab.settings` (en+de) ships in W3's langdrop
  (`P3-W3.json`) — the rail tooltip resolves. `rail_settings.png` already exists (W1).

## StatusTab → Settings link (integration note)

The tab cannot reach the frame's protected `switchTab`, so the link routes through the
public hotkey path: `screen.keyPressed(GLFW_KEY_8, 0, 0)`. This is correct exactly while
Settings is the roster's LAST tab of 8 (frozen §3.1 order — the roster comment in
`HandbookScreen` says so too). If the roster ever grows past 8 tabs, W1 should expose a
public `openTab(String id)` and this link is the one call site to migrate. Known quirk
(consistent with the keyboard): a user who rebinds the menu-close key to literal `8`
closes the book from this link instead — same as pressing 8 by hand.

## Bestiary data contract (future mobs)

- Adding a mob = one line in `BestiaryTab.CREATURES` (`id`, `introDay`). Everything else
  degrades gracefully while lang keys live in another worker's pending langdrop:
  name resolves `bestiary.eclipse.<id>.name` → `entity.eclipse.<id>` → prettified id;
  missing `bestiary.eclipse.<id>.lore` renders the DIM `gui.eclipse.handbook.bestiary.pending`
  line (W2 key). Ids without a dedicated code-drawn silhouette get a generic wisp.
- `drift_lantern` (intro day 1, limbo ambience) currently resolves its name from P6-W1's
  `entity.eclipse.drift_lantern`. **Ask → P6**: ship `bestiary.eclipse.drift_lantern.name`
  + `.lore` (en+de) in a langdrop to replace the pending line; no code change needed.

## Revival page contract (P4 §5.1 / landed P4-B8)

- Math reads the LANDED `ritual.HeartExtractorItem` constants directly (`HEART_COST` = 2,
  `FRAGMENT_REWARD` = 4, `MIN_REMAINING_HEARTS` = 1) — hearts shown = whole channels to
  cover the fragment demand; the warning's "hold at least %s" is
  `HEART_COST + MIN_REMAINING_HEARTS` (= 3). Rebalancing the item auto-updates the page,
  zero W2 edits. Fragment demand + step-II materials are read LIVE from the synced
  `eclipse:revive_sigil` recipe via the client `RecipeManager` (fallback: shipped recipe —
  4x netherite ingot, nether star, dragon's breath). Items rendered:
  `eclipse:heart_extractor`, `eclipse:heart_fragment`, `eclipse:revive_sigil`,
  `eclipse:altar`, `eclipse:vitae_shard` (aftercare footnote) — all already registered.
- Step-III wording matches the shipped altar flow (`ReviveSigilItem`): right-click cycles
  the banned-player selection, sneak-use confirms. If P4 replaces this with the extractor
  ritual UI, only `gui.eclipse.handbook.revival.step3.text` needs a wording pass.

## Lang

- `docs/plans_v3/langdrop/P3-W2.json` — 15 keys x en+de (`gui.eclipse.handbook.tab.revival`,
  `…status.more`, `…bestiary.pending`, `…revival.*`). `revival.step1.text` formats
  `(HEART_COST, FRAGMENT_REWARD, fragmentsNeeded)`; `revival.warning` formats
  `(HEART_COST + MIN_REMAINING_HEARTS)`; `revival.step1.math` formats
  `(heartsPaid, fragmentsYielded)`.
- Now **unreferenced** after the online-count removal (B10):
  `gui.eclipse.handbook.status.online.one` / `.many` — safe to delete in the lang cleanup
  pass (same bucket as W1's `gui.eclipse.handbook.hint`).

## Bug ledger

B4 (phantom settings widget → real `widgets()` widget), B5 (timeline centering includes
the section gap; gap only counted when milestones exist), B6 status-side (sting/draw-in
keyed on flip ticks — pairs with the frame's tick-all-tabs), B7 (rewards scrollbar),
B10 status-side (online count gone), B20 (every tab consumes presses only when it can
actually scroll; scrollbar input gated the same way).

## Test steps (manual, client)

1. Open the handbook (J / right-click the slot-17 artifact) at guiScale 2 AND 3, en + de
   (`/lang de`): every tab readable, no scissor-chopped text, day numeral 2x, no
   "souls awake" line anywhere.
2. Status: complete a goal while the MAP tab is open → switch to Status → tick draw-in
   plays; `/eclipse` altar level-up while on another tab → sting fires once, bar flashes
   when you return. Click "Settings »" → Settings tab opens with a page-turn whoosh.
3. Timeline: with milestones reached, reopen the tab → newest reached node centered
   (not 64px off); with a day-only timeline there is no dead scroll zone at the right
   end; click without drag on a non-scrolling timeline falls through (no swallow).
4. Rules/Rewards/Bestiary/Revival: wheel, content drag AND scrollbar drag all scroll;
   scrollbar visible whenever scrollable; grab cursor while dragging either way.
5. Revival: verify the three strips render extractor/fragment/sigil/altar icons, the
   fragment count matches the live `revive_sigil` recipe (edit the datapack recipe →
   count follows), and captions drop cleanly at narrow widths.
6. Bestiary: day 1 → Deckhand + Drift Lantern unlocked (lantern name from the entity
   key, DIM pending-lore line), day <3 → Gazer still glitched; reducedFx → static "?"s.
7. reducedFx ON: no bar pulse, no node breathing, hint hidden, everything still usable.
