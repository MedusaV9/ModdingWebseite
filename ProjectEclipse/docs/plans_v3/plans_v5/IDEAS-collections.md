# IDEAS — COLLECTIONS (Skyblock-style), Eclipse Event

Collector doc, read-only survey — no code changed. Loop: **farm enough of X → tier up →
recipe unlocks + skill XP → early-game dopamine.** Tuned for the 14-day arc
(`RealtimeDayService`, Ferryman finale day 14).

## 0. Grounding — the seams this design hangs off (verified in-repo)

- **Signal lanes exist** (`core/signal/EclipseSignals`, server-thread, single owning
  subscriber per lane): `onNaturalBlockMined(player, state, pos)` (already
  placed-block-filtered), `onBlockPlaced`, `onMobKilled(player, victim)`,
  `onItemCrafted(player, stack)`, `onItemSmelted`, `onAltarDeposit(player, itemId, count,
  purpose)` with `AltarDepositPurpose.SHARD_BANK`, `onDayRollover`.
- **Counters exist** (`analytics/AnalyticsKeys` + `AnalyticsApi`): dynamic `mine:<block_id>`
  (natural-only), `kill:<entity_id>`, `craft:<item_id>` (allowlisted), static
  `SHARDS_BANKED`; `AnalyticsApi.sumAcrossDays(server, uuid, key)` reads lifetime-ish sums
  BUT retention is 20 days and the per-day dynamic-key cap drops per-id detail on overflow
  (fail-safe under-crediting) — good for verification, **not** good as the collection store
  of record (see §4.4).
- **Recipe locking exists** (`progression/RecipeGate` + `RecipeGateConfig` +
  `RecipeGateMath`): day-tier locks from `config/eclipse/recipegate.json`
  (`locked while day < unlockDay`; item ids and `#tags`), enforced by stripping the result
  on `PlayerEvent.ItemCraftedEvent` with a hint line, EMI-hidden via
  `S2CRecipeLocksPayload`. Crucially `RecipeGate.syncTo(player)` is already per-player —
  the wire shape supports per-player locks today; only lock *resolution* is global (§4.2).
- **XP grants exist** (`skills/SkillsApi.addXp(player, sourceKey, baseAmount)`): unknown
  source keys behave as uncapped/unscaled, so a new `SOURCE_COLLECTION = "collection"`
  works day one; `SkillsApi.addPoints(player, n)` grants free tree points (reward surface).
  Calibration: curve default `C(12)=2639` (~L12 after 4h at ~660 XP/h); quest rewards run
  150–500 XP (`GoalConfig`).
- **Anti-abuse primitive exists** (`buffs/PlacedBlockCheck.isPlaced/isNatural`, O(1) chunk
  bitset via `analytics/PlacedBlockTracker`) — `fireNaturalBlockMined` only fires for
  natural blocks, and `SkillPerks` re-checks; collections inherit this for free.
- **UI home exists** (`client/handbook/HandbookScreen` + `tabs/HandbookTab`): 8 tabs today
  (`StatusTab, TimelineTab, RulesTab, RevivalTab, RewardsTab, BestiaryTab, MapTab,
  SettingsTab`), frozen v3 tab API (`widgets()`, `keyPressed`, rail icon
  `textures/gui/handbook/rail_<id>.png` with first-letter fallback, lang
  `gui.eclipse.handbook.tab.<id>`). Toast precedent: `client/skills/SkillProcToast`
  (queue cap 4, ~2s hold, unknown-proc-id fallback renders underscores→spaces).
- **Event items exist**: `eclipse:umbral_shard` (boss drops: Herald 3, Rift Warden 2/4,
  Fog Tyrant 3/6; banked at `AltarBlockEntity` → `SHARDS_BANKED`), `eclipse:glitch_shard`
  (`glitch/GlitchDrops` on `#eclipse:glitched` kills), and one real modded recipe consuming
  umbral shards: `data/eclipse/recipe/eclipse_wand.json`.
- **Existing gates to not collide with**: `recipegate.json` defaults (anvil < day 2,
  enchanting table < day 3, `#eclipse:tier_diamond_gear` < day 5, `#eclipse:tier_netherite_gear`
  < day 10) and `UnlockState` (enchanting additionally Herald-gated; End arc opens day 12).
  Ore availability is day/band-gated (`ores.json`: coal/copper band 0; iron/gold/redstone
  band 2 ≈ day 2–3; diamond band 3 ≈ day 3+) — tier pacing below respects this.

---

## 1. Collection definitions (17 shipped + 1 rejected ≈ the ~18 asked)

Conventions:

- **Unit = source event, not item drops** — mining counts *blocks* (Fortune-neutral),
  farming counts *mature crops broken*, mobs count *kills*, event counts *shards banked /
  picked up*. See §2.
- **Tier rewards auto-grant** the moment the threshold is crossed (no claim click —
  dopamine now, handbook later). Rewards: skill XP via
  `SkillsApi.addXp(player, "collection", xp)`, skill points via `SkillsApi.addPoints`,
  recipe unlocks via the per-player RecipeGate extension (§4.2).
- **Single-gate rule**: every gated recipe result is owned by exactly ONE collection tier.
  Two deliberate unions with existing day gates are flagged ⚠ inline.
- **XP budget**: full 17/17 completion ≈ **15.3k XP** (hardcore chase ≈ +L20-ish on the
  default curve); a casual T1–T2 sweep ≈ **2.8k XP**. Tier-1s are all first-session-sized.

### 1.1 Mining (7) — lane `mine` (natural blocks only)

| Collection | Counted block ids | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|---|---|
| **Cobblestone** | `stone`, `cobblestone`, `deepslate`, `cobbled_deepslate` | 50 | 250 | 1 000 | 2 500 | 6 000 | 12 500 |
| **Coal** | `coal_ore`, `deepslate_coal_ore` | 25 | 100 | 300 | 750 | 1 500 | 3 000 |
| **Copper** | `copper_ore`, `deepslate_copper_ore` | 20 | 80 | 250 | 600 | 1 200 | 2 400 |
| **Iron** | `iron_ore`, `deepslate_iron_ore` | 15 | 75 | 250 | 600 | 1 250 | 2 500 |
| **Gold** | `gold_ore`, `deepslate_gold_ore`, `nether_gold_ore` | 10 | 40 | 120 | 300 | 600 | 1 200 |
| **Redstone** | `redstone_ore`, `deepslate_redstone_ore` | 10 | 40 | 150 | 400 | 800 | 1 600 |
| **Diamond** | `diamond_ore`, `deepslate_diamond_ore` | 5 | 20 | 60 | 150 | 400 | — |

Per-tier rewards (XP / points / recipe unlocks — all recipes are real vanilla recipes):

- **Cobblestone**: T1 `+50xp` · T2 `+100xp` + **stonecutter** · T3 `+150xp` +
  **dispenser, dropper** · T4 `+250xp` + **piston, sticky piston** · T5 `+400xp, +1pt` ·
  T6 `+600xp, +1pt` (prestige tier — the "cobble monster" badge in the tab).
- **Coal**: T1 `+40xp` · T2 `+75xp` + **campfire** · T3 `+125xp` + **fire charge** ·
  T4 `+200xp` · T5 `+300xp, +1pt` · T6 `+450xp`.
- **Copper**: T1 `+40xp` · T2 `+75xp` + **lightning rod** · T3 `+125xp` + **brush** ·
  T4 `+200xp` + **spyglass** · T5 `+300xp` · T6 `+450xp, +1pt`.
- **Iron**: T1 `+50xp` · T2 `+100xp` + **shield** · T3 `+175xp` + **crossbow, minecart,
  rail** · T4 `+275xp` + **anvil** ⚠ *(unions with the existing day-2 lock in
  `recipegate.json`; day 2 passes fast so the collection is the binding gate — intended)* ·
  T5 `+400xp, +1pt` + **blast furnace** · T6 `+600xp, +1pt`.
- **Gold**: T1 `+50xp` · T2 `+100xp` + **clock** · T3 `+175xp` + **powered rail** ·
  T4 `+275xp` + **golden apple** · T5 `+400xp, +1pt` · T6 `+600xp`.
- **Redstone**: T1 `+50xp` · T2 `+100xp` + **repeater** · T3 `+175xp` + **hopper,
  comparator** · T4 `+275xp` + **observer** · T5 `+400xp, +1pt` · T6 `+600xp, +1pt`.
- **Diamond** (5 tiers, starts ~day 3 with band 3): T1 `+75xp` · T2 `+150xp` +
  **jukebox** · T3 `+250xp` + **smithing table** · T4 `+400xp, +2pt` · T5 `+600xp, +1pt`.
  *Deliberately does NOT touch the enchanting table (day-3 + Herald gate via `UnlockState`)
  or `#eclipse:tier_diamond_gear` (day-5 gate) — no triple-gating confusion.*

### 1.2 Farming (3) — lane `harvest` (mature crops only, §2.2)

| Collection | Counted | T1 | T2 | T3 | T4 | T5 |
|---|---|---|---|---|---|---|
| **Wheat** | `wheat` broken at max age | 30 | 150 | 500 | 1 250 | 2 500 |
| **Carrot** | `carrots` broken at max age | 25 | 125 | 400 | 1 000 | 2 000 |
| **Pumpkin** | `pumpkin` block mined (stem-grown, §2.2) | 10 | 50 | 150 | 400 | 800 |

- **Wheat**: T1 `+40xp` · T2 `+100xp` + **hay bale** · T3 `+175xp` + **cake** ·
  T4 `+275xp` + **target** *(4 redstone + hay bale — a cute cross-category nod)* ·
  T5 `+450xp, +1pt`. *Bread is deliberately NEVER gated (early-food safety).*
- **Carrot**: T1 `+40xp` · T2 `+100xp` + **carrot on a stick** · T3 `+175xp` ·
  T4 `+275xp` + **golden carrot** *(owned here, not by Gold — single-gate rule)* ·
  T5 `+450xp, +1pt`.
- **Pumpkin**: T1 `+40xp` · T2 `+100xp` + **jack o'lantern** · T3 `+175xp` +
  **pumpkin pie** · T4 `+275xp` · T5 `+450xp, +1pt`.

### 1.3 Wood (1) — lane `mine` on `#minecraft:logs`

| Collection | Counted | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|---|---|
| **Timber** | any `#minecraft:logs` natural block | 40 | 200 | 600 | 1 500 | 3 000 | 6 000 |

- T1 `+50xp` · T2 `+100xp` + **barrel** · T3 `+175xp` + **smoker** · T4 `+275xp` +
  **loom, cartography table** · T5 `+400xp, +1pt` · T6 `+600xp, +1pt`.
  *Crafting table, chest, sticks, boats: never gated (survival staples).*

### 1.4 Mobs (4) — lane `kill` (kills, not drops — Looting-neutral, §2.3)

| Collection | Counted kills | T1 | T2 | T3 | T4 | T5 |
|---|---|---|---|---|---|---|
| **Rotten Flesh** | `zombie`, `zombie_villager`, `husk`, `drowned` | 10 | 50 | 150 | 400 | 800 |
| **Bone** | `skeleton`, `stray`, `bogged` | 10 | 50 | 150 | 400 | 800 |
| **String** | `spider`, `cave_spider` | 8 | 40 | 120 | 300 | 600 |
| **Ender Pearl** | `enderman` | 3 | 10 | 30 | 75 | 150 |

- **Rotten Flesh** (reward-only — vanilla has no flesh recipes): T1 `+40xp` · T2 `+100xp` ·
  T3 `+200xp, +1pt` · T4 `+325xp` · T5 `+500xp, +1pt`.
- **Bone**: T1 `+40xp` · T2 `+100xp` + **bone block** · T3 `+200xp` ·
  T4 `+325xp, +1pt` · T5 `+500xp, +1pt`.
- **String**: T1 `+40xp` · T2 `+100xp` + **fishing rod** · T3 `+200xp` + **scaffolding** ·
  T4 `+325xp` + **lead** · T5 `+500xp, +1pt`. *The bow is deliberately ungated (core
  combat safety); the crossbow is owned by Iron T3.*
- **Ender Pearl**: T1 `+75xp` · T2 `+150xp` + **eye of ender** ⚠ *(unions with the day-12
  "end" arc key from `UnlockState` — pearls hunted early still pay XP, eyes craft only when
  both pass; flag in the reward preview as "requires End open")* · T3 `+250xp` +
  **ender chest** · T4 `+400xp` + **end crystal** · T5 `+600xp, +2pt`.

### 1.5 Event (2) — lanes `shard_bank` / `pickup`

| Collection | Counted | T1 | T2 | T3 | T4 | T5 |
|---|---|---|---|---|---|---|
| **Umbral Shards** | shards banked at the altar (`SHARDS_BANKED` semantics) | 5 | 25 | 75 | 200 | 500 |
| **Glitch Shards** | `eclipse:glitch_shard` picked up (thrower-null, §2.4) | 3 | 15 | 50 | 125 | 300 |

- **Umbral Shards**: T1 `+75xp` · T2 `+150xp` + **`eclipse:eclipse_wand`** *(real modded
  recipe in `data/eclipse/recipe/eclipse_wand.json` — the flagship collection unlock)* ·
  T3 `+250xp, +1pt` · T4 `+400xp, +1pt` · T5 `+600xp, +2pt`. Banking is one-way (altar
  consumes), so the counter is inherently abuse-proof and synergizes with the altar-level
  arc.
- **Glitch Shards** (reward-only): T1 `+75xp` · T2 `+150xp` · T3 `+250xp, +1pt` ·
  T4 `+400xp, +1pt` · T5 `+600xp, +2pt`.

### 1.6 Rejected 18th: Obsidian — and why

Water-over-lava creates obsidian via `setBlock` with **no placement event**, so the placed
bitset never marks it → infinitely "natural" and farmable with two buckets. The same
loophole is *accepted* for Cobblestone (a cobble generator IS the Skyblock fantasy and the
T5/T6 thresholds assume it), but obsidian has no fun grind identity beyond bucket-clicking.
Cut; revisit only with a dedicated "created-by-fluid" bit.

---

## 2. Counting rules

1. **Mining/Timber (`mine` lane)** — subscribe `EclipseSignals.onNaturalBlockMined`; the
   lane is *already* natural-only (analytics' `BlockEvent` owner consults
   `PlacedBlockTracker`; `PlacedBlockCheck.isPlaced` is the O(1) re-check seam if a
   listener needs to be paranoid). Credit = **1 per block**, never per item drop: Fortune,
   ore-drop buffs (`TimedBuffService "ore_drops"`), and T2 Fortune's Echo procs change
   loot, never collection speed. Silk-touching stone then re-mining is irrelevant for the
   same reason (replaced blocks carry the placed bit).
2. **Farming (`harvest` lane, NEW)** — planted crops are player-placed, so
   `onNaturalBlockMined` never fires for them. Add a sibling signal
   `EclipseSignals.onCropHarvested(player, state, pos)` fired by the same analytics
   `BlockEvent` owner when the broken block is a `CropBlock` **at max age** (`isMaxAge`).
   The max-age check is the rate limiter: plant-and-break spam credits nothing; regrowth
   time (or bone meal, which costs the Bone grind) is the cost. **Pumpkin is the
   exception**: stem-grown pumpkin blocks are set by the stem (no placement event → no
   placed bit), so plain `mine:minecraft:pumpkin` on the existing lane works; hand-placed
   pumpkins carry the bit and never count.
3. **Mobs (`kill` lane)** — subscribe `EclipseSignals.onMobKilled(player, victim)`, match
   `victim` type against the collection's entity list. Counting kills (like
   `kill:<entity_id>`) instead of item pickups removes drop-RNG, Looting inflation, and
   drop-dupe abuse in one move. Display still uses the item icon/name ("Rotten Flesh") —
   the fantasy is the item, the math is the kill.
4. **Event (`shard_bank` / `pickup` lanes)** — Umbral: subscribe
   `EclipseSignals.onAltarDeposit` and credit `count` when
   `purpose == AltarDepositPurpose.SHARD_BANK` (mirrors `SHARDS_BANKED`). Glitch: NEW
   signal `EclipseSignals.onItemCollected(player, stack)` fired from a single
   `ItemEntityPickupEvent` owner, **only when the `ItemEntity` has no thrower** — mob/boss
   drops have none, player-tossed stacks do, so drop-and-repickup never double-counts.
   Filtered to a tiny allowlist (`eclipse:glitch_shard`) so the lane stays bounded.
   Hopper pickup doesn't credit — accepted under-crediting, consistent with the repo's
   fail-safe principle.
5. **Crafted items count nowhere.** `onItemCrafted` / `craft:<item_id>` deliberately feed
   no collection: crafting converts, it doesn't gather. (It stays the *reward* side —
   unlocked recipes — not the *progress* side.)
6. **Where does progress live?** A dedicated `CollectionsState` `SavedData`
   (per-player map `collectionId → long`, plus highest-granted tier per collection —
   `SkillState` pattern). NOT derived from `AnalyticsApi.sumAcrossDays`: analytics has a
   20-day retention window and drops per-id detail past the daily dynamic-key cap
   (under-crediting by design). `sumAcrossDays` remains useful for a one-shot backfill on
   first install mid-event and for `/eclipse collections audit` dev verification.

---

## 3. UI — handbook Collections tab + tier-up toast

**Tab**: new `tabs/CollectionsTab` (id `collections`), inserted in `HandbookScreen.tabs`
after `RewardsTab`. Rail icon `textures/gui/handbook/rail_collections.png` (the screen's
first-letter fallback renders "C" until art lands); lang key
`gui.eclipse.handbook.tab.collections`. Note: the screen's number hotkeys cover 1–8 and
this is tab #9 — arrows/PgUp/PgDn already page past 8, so no API change needed, but the
hotkey doc string should mention it.

**Layout** (inside the content rect, drag-scroll + `TabScrollbar` like Bestiary):

- **Category rail** (left, ~72px): `Mining · Farming · Wood · Mobs · Event`, ACCENT when
  active, DIM otherwise, small "n/m tiers" fraction under each label.
- **Collection rows** (right, one per collection, ~30px tall):
  - item icon (config `icon`, e.g. `minecraft:iron_ingot`) + name;
  - **progress bar** to the NEXT tier only (`current − prevThreshold` /
    `nextThreshold − prevThreshold`), numeric `1 240 / 2 500` right-aligned, ACCENT fill
    on `EclipseUiTheme` track;
  - **tier pips**: 5–6 diamonds under the bar — filled = granted, hollow = future; all
    filled ⇒ row header flips to the gold "maxed" treatment;
  - **reward preview, NEXT tier only** (the Skyblock dopamine trick — never show the whole
    ladder): `+275 XP · unlocks [anvil icon]` as a sub-line; recipe icons get item-stack
    tooltips; union-gated entries (eye of ender) suffix "(requires End open)".
- Maxed collections sink to the bottom of their category; category completion shows on the
  rail.

**Data sync**: `S2CCollectionsPayload` (all counters + granted tiers) on login and after
any tier grant; cheap delta payload `S2CCollectionDeltaPayload(collectionId, newCount)`
at most 1/s per collection while the handbook is open (client-side cache pattern:
`ClientBestiaryCache`).

**Toast on tier-up**: new `S2CCollectionTierPayload(collectionId, tier, xp, points,
unlockedItemIds)`. Client renders a `SkillProcToast`-style card (queue cap shared): line 1
`✦ Iron Collection II`, line 2 `+100 XP · Shield unlocked`, with
`EclipseSounds.UI_UNLOCK_STING` (the discovery sting, distinct from `SKILL_PROC`).
Recipe-bearing tiers additionally re-sync locks (§4.2) so EMI un-hides instantly.
Chunky tiers (any tier granting points) may optionally ride the
`RewardMaterializeOverlay` shard-burst for extra ceremony.

**Locked-craft hint upgrade**: `RecipeGate.hint(player)` currently says a generic
`message.eclipse.recipe.locked`. Add `message.eclipse.recipe.locked.collection` with args
`(collectionName, tierRoman)` — "Locked — reach Iron Collection II" — actionable, not
mysterious.

---

## 4. Integration contracts (exact names)

### 4.1 Signals feeding counters

| Lane | Signal (existing unless marked NEW) | Filter |
|---|---|---|
| `mine` | `EclipseSignals.onNaturalBlockMined(player, state, pos)` | block id/tag ∈ collection `ids` |
| `harvest` | `EclipseSignals.onCropHarvested(player, state, pos)` **NEW** (fired by the analytics `BlockEvent` owner, `CropBlock.isMaxAge` only) | crop id ∈ `ids` |
| `kill` | `EclipseSignals.onMobKilled(player, victim)` | entity type ∈ `ids` |
| `shard_bank` | `EclipseSignals.onAltarDeposit(player, itemId, count, purpose)` | `purpose == SHARD_BANK`, `itemId == eclipse:umbral_shard` |
| `pickup` | `EclipseSignals.onItemCollected(player, stack)` **NEW** (single `ItemEntityPickupEvent` owner, thrower-null, allowlisted ids) | item id ∈ `ids` |

`CollectionsService` registers all listeners once at `ServerStartedEvent`
(`SkillService.onServerStarted` pattern; `EclipseSignals` auto-clears on server stop).
Analytics keys `mine:<block_id>` / `kill:<entity_id>` / `SHARDS_BANKED` stay untouched as
the independent observability layer + backfill/audit source.

### 4.2 RecipeGate — per-player collection locks

Today `RecipeGate.resolveLocks(server)` is global (day only), but `syncTo(player)` and
`S2CRecipeLocksPayload` are already per-player. Extension (no wire change):

- `RecipeGate.registerPlayerLockProvider(Function<ServerPlayer, Set<String>> provider)` —
  collections registers one provider returning the item ids of every not-yet-reached
  `unlockItems` entry for that player (tags allowed, same `#` syntax).
- `payloadFor(player)` / `isItemLockedFor(player, stack)` = day locks ∪ provider locks;
  `onItemCrafted` switches to the per-player overload; `broadcastAll` iterates
  `syncTo(player)` (it already does).
- `RecipeGateApi` gains `isItemLockedFor(ServerPlayer, ItemStack)` and keeps the old
  global methods for EMI/devtools.
- On tier grant: `RecipeGate.syncTo(player)` immediately (toast and EMI un-hide land in
  the same tick).
- Day locks and collection locks compose as a union — a result is craftable only when
  every gate that names it passes (the two ⚠ unions in §1 are the only intentional
  overlaps).

### 4.3 Skills

- `SkillService` gains `SOURCE_COLLECTION = "collection"`; grants via
  `SkillsApi.addXp(player, SOURCE_COLLECTION, tierXp)` (unknown keys already behave
  uncapped, so this works even before the constant lands; adding it enables an optional
  `dailyCaps.collection` knob in `skills.json`).
- Points via `SkillsApi.addPoints(player, tierPoints)`.
- Tier grants are lump sums on threshold-cross; the per-action `SOURCE_MINE`/`SOURCE_KILL`
  trickle continues independently — collections are the *milestone* layer on top.

### 4.4 State & lifecycle

- `CollectionsState extends SavedData` (`eclipse_collections`): per player
  `Map<String, long count>` + `Map<String, int grantedTier>`; ~17 longs/player, trivial.
- Threshold sweep on every credit (counts only go up; grants are idempotent —
  `grantedTier` is monotonic, mirroring `SkillsApi.setTotalXp`'s "newly reached only"
  contract).
- Config hot-reload (`/eclipse reload` via `ReloadHooks.register("collections", …)`)
  re-runs the sweep so *lowered* thresholds grant retroactively; raised thresholds never
  revoke XP/points (fail-safe), only re-lock un-reached recipes on next sync.
- `EclipseSignals.onDayRollover` is NOT needed (lifetime counters), except for the
  optional `dailyCreditCap` (§5).

---

## 5. Anti-abuse

1. **No farming placed blocks** — inherited: `fireNaturalBlockMined` only fires for
   blocks the `PlacedBlockTracker` bitset says are natural; place-and-remine credits 0.
   `PlacedBlockCheck.isPlaced` is the belt-and-braces re-check if the listener ever moves.
2. **Fortune/Looting/buff-neutral** — blocks and kills are counted, never drops, so every
   drop multiplier in the repo (`ore_drops` buff, `double_ore` proc, Looting) is
   collection-irrelevant by construction.
3. **Crop cycling** — `isMaxAge` only; replant-regrow time is the throttle; bone meal is
   paid for by the Bone grind (closed economy, acceptable).
4. **Pickup dupes** — `onItemCollected` ignores `ItemEntity`s with a thrower; drop/repick
   loops credit once, ever. Container/hopper laundering under-credits (never over).
5. **One-way sinks** — Umbral counts on *banking* (altar consumes the shard); you cannot
   recount what you no longer own.
6. **Cobble generators are a feature, obsidian farming is not** — accepted loophole
   (§1.6); the fluid-created-block gap is why Obsidian was cut rather than patched.
7. **Optional throttle knob** — per-collection `dailyCreditCap` (0 = off) resets at
   `onDayRollover POST`; ship OFF by default, keep as the emergency lever if a spawner-adjacent
   kill farm appears mid-event (dark-room grinding is otherwise deemed in-spirit).
8. **Fail-safe direction** — every ambiguity above resolves to under-crediting, matching
   the analytics contract ("overflow drops detail but never aggregates").

---

## 6. Config schema — `config/eclipse/collections.json`

`RecipeGateConfig` pattern: written with defaults on first run, hot-reload via
`ReloadHooks` (`/eclipse reload`), parse failure keeps previous snapshot.

```jsonc
{
  "_doc": "Collections: lanes mine|harvest|kill|shard_bank|pickup; ids take block/entity/item ids or #tags; thresholds strictly increasing; unlockItems use recipegate syntax (ids or #tags).",
  "toastsEnabled": true,
  "xpSourceKey": "collection",
  "collections": [
    {
      "id": "iron",
      "category": "mining",                       // mining|farming|wood|mobs|event (rail order)
      "icon": "minecraft:iron_ingot",             // row/tooltip icon (display only)
      "lane": "mine",
      "ids": ["minecraft:iron_ore", "minecraft:deepslate_iron_ore"],
      "dailyCreditCap": 0,                        // 0 = uncapped (default)
      "tiers": [
        { "threshold": 15,   "xp": 50 },
        { "threshold": 75,   "xp": 100, "unlockItems": ["minecraft:shield"] },
        { "threshold": 250,  "xp": 175, "unlockItems": ["minecraft:crossbow", "minecraft:minecart", "minecraft:rail"] },
        { "threshold": 600,  "xp": 275, "unlockItems": ["minecraft:anvil"] },
        { "threshold": 1250, "xp": 400, "points": 1, "unlockItems": ["minecraft:blast_furnace"] },
        { "threshold": 2500, "xp": 600, "points": 1 }
      ]
    },
    {
      "id": "umbral_shards",
      "category": "event",
      "icon": "eclipse:umbral_shard",
      "lane": "shard_bank",
      "ids": ["eclipse:umbral_shard"],
      "tiers": [
        { "threshold": 5,   "xp": 75 },
        { "threshold": 25,  "xp": 150, "unlockItems": ["eclipse:eclipse_wand"] },
        { "threshold": 75,  "xp": 250, "points": 1 },
        { "threshold": 200, "xp": 400, "points": 1 },
        { "threshold": 500, "xp": 600, "points": 2 }
      ]
    }
    // … remaining 15 per §1 tables
  ]
}
```

Validation on load: unknown lane → collection skipped with WARN; non-increasing thresholds
→ tier list truncated at the violation; `unlockItems` never validated against the recipe
registry (tags may load later — same leniency as `RecipeGate`'s missing-tag DEBUG).
Lang keys: `collection.eclipse.<id>` (name), `gui.eclipse.handbook.tab.collections`,
`message.eclipse.collection.tier` (toast), `message.eclipse.recipe.locked.collection`.
