# PLAN-D — Systems & Progression (plans_v5)

PLANNER-D worker packages. Scope: SYSTEMS/PROGRESSION items from the v5 user feedback
round. Every package below was root-caused against the actual code (files cited per
package). Ownership is disjoint: no two packages edit the same file, and cross-planner
seams (PLANNER-A UI, PLANNER-B worldgen) are called out explicitly.

Conventions used below:

- **Effort** — S (≤ 3 files / < 1 focused session), M (4–10 files), L (> 10 files or new
  package + client UI + gametests).
- All new config files follow the `EclipseConfig.loadOrCreate` + `ReloadHooks` pattern
  (see `skills/SkillConfig.java` as the canonical example).
- All new `/dev` commands MUST register `DevCommandDoc` entries in
  `devtools/dev/DevCommandRegistry` (static initializer, see `DevContractCommands`) so
  `/dev help` and `/dev docs export` pick them up.
- "Event dimensions" = `limbo/LimboDimension.LIMBO`, `minigames/MinigameDimensions`
  (`minigame_arena`, `minigame_sky`), `xboxevent/XboxDimensions` (`xbox_tu1/tu12/tu14`).
  There is no dimension literally called "backrooms" in the repo — the user means the
  xbox/glitch event worlds; the gate below covers every non-progression dimension.

---

## D1 — COLLECTIONS system (Hypixel-Skyblock-style early-game dopamine engine)

**User item:** 1.

**Root cause / current state:** No collection system exists. All the rails it needs are
already in place and are the ONLY sanctioned hook points (P4 §2.0 rule 6: downstream
systems must not add their own break/death/craft subscribers):

- `analytics/AnalyticsService` is the single owner of the mine/craft/kill/smelt event
  lanes and fans out `EclipseSignals.fireNaturalBlockMined / fireMobKilled /
  fireItemCrafted / fireItemSmelted` exactly once per underlying event, natural-only for
  mining (via `PlacedBlockTracker`) and only for tracked (survival/adventure, non-fake)
  players — free anti-farm protection for collections.
- Mob DROPS (the user's "mob drops" collections) have no pickup signal today. Item
  pickup is only touched by `progression/ModGate.onItemPickup`. Collections that count
  "collect N of item X" should use a new `EclipseSignals.itemPickedUp` fan-out fired
  from ONE new `ItemEntityPickupEvent.Post` subscriber in `AnalyticsService` (it owns
  the shared-lane subscribers by contract).
- Recipe unlocking exists: `progression/UnlockState` (persisted key set) +
  `progression/RecipeGate` (config `recipegate.json` keyed by unlock keys; already
  broadcasts `S2CRecipeLocksPayload`, already integrated with EMI via
  `RecipeGateApi.lockedItemIds`). Collections only need to call
  `UnlockState.grant(server, key)` and `RecipeGateApi.rebroadcast`.
- Skill XP rewards: `skills/SkillsApi.addXp(player, source, amount)`.
- Handbook: `client/handbook/HandbookScreen` has a hardcoded 8-tab list (`StatusTab`,
  `TimelineTab`, …) — add a ninth `CollectionsTab` following `BestiaryTab`'s
  list-detail layout (it already demonstrates progress tiers + scroll).
- Toast pattern: `client/skills/SkillProcToast` (hotbar mini-toast) and
  `client/skills/LevelUpOverlay` (big ceremony) are the two existing tiers of feedback.

**Fix (new `collections/` package, server side):**

1. `collections/CollectionConfig.java` — data-driven `config/eclipse/collections.json`:
   `{ id, icon (item id), lane (mine|kill|craft|pickup|smelt), matcher (exact id or #tag),
   tiers: [{ count, rewardSkillXp (source "collection"), rewardShards?, unlockKeys? [],
   rewardItems? [] }], displayNameKey }`. Written with the fully-authored default set
   (15 collections, below). Hot-reload via `ReloadHooks`.
2. `collections/CollectionState.java` — `SavedData` (`eclipse_collections`), per-player
   `Map<collectionId, long count>` + claimed-tier index. Lifetime counters (NOT per-day —
   collections are the long arc; analytics day counters are the wrong store).
3. `collections/CollectionService.java` — registers `EclipseSignals` listeners
   (`onNaturalBlockMined`, `onMobKilled`, `onItemCrafted`, `onItemSmelted`, and the new
   `onItemPickedUp`) exactly like `skills/SkillService.onServerStarted` does; maps
   events → collection increments; on tier crossing: grant rewards
   (`SkillsApi.addXp(player, "collection", xp)`, `UnlockState.grant` + 
   `RecipeGateApi.rebroadcast` for unlock keys, `ShardEconomy.addShards`), fire a new
   `S2CCollectionTierPayload`, play `EclipseSounds.SKILL_LEVELUP` at a distinct pitch.
   Respect the D2 XP gate automatically (rewards flow through `SkillsApi`).
4. `network/S2CCollectionStatePayload` (login + on-change sync of counts/tiers, coalesced
   like `SkillService.DIRTY` at 20 ticks) and `S2CCollectionTierPayload` (tier-up event).
   Register in `network/EclipsePayloads` (one-liner wiring ask, same shape as skills).
5. Add `EclipseSignals.itemPickedUp(ServerPlayer, ItemStack)` + the single
   `ItemEntityPickupEvent.Post` owner in `AnalyticsService` (counts
   `AnalyticsKeys.PREFIX_PICKUP` dynamic keys too — useful for awards later).

**Fix (client):**

6. `client/handbook/tabs/CollectionsTab.java` — new tab: left rail = collection list
   grouped by lane (Ores / Crops / Mobs / Wood), right pane = per-collection progress bar
   with tier markers (diamond pips at each tier count, filled when claimed — reuse
   `EclipseUiTheme` accent + `BestiaryTab` scroll plumbing), reward preview lines per tier.
   Data from `ClientStateCache` (extend it with the collection payload cache).
7. `client/collections/CollectionToast.java` — tier-up toast (modelled on
   `SkillProcToast`): "✦ IRON COLLECTION II — Recipe unlocked: …", plus the payload's
   unlock names. Registered in `EclipseGuiLayers`.

**Default 15 collections (authored in the config defaults):**

| Lane | Collections (tier counts follow a ~4× ladder, e.g. 50/200/800/2500) |
|---|---|
| Ores (mine) | Coal (`#minecraft:coal_ores`), Iron, Copper, Gold, Redstone, Diamond (25/100/400/1200), Ancient Debris (8/24/64) |
| Crops (pickup/mine) | Wheat, Carrot/Potato (combined "Roots"), Nether Wart |
| Mob drops (pickup) | Bone, String, Gunpowder, Ender Pearl (8/24/64/128) |
| Wood (mine) | Logs (`#minecraft:logs`, 128/512/2048) |

Tier rewards: predominantly skill XP (100–800 per tier, source `"collection"` with its
own `dailyCaps` entry OFF); mid tiers unlock RecipeGate keys that make sense against the
day arc (e.g. Iron II → `iron_tools_plus` cosmetic recipes, Diamond I → grindstone
sharpening recipe, Ender Pearl II → `ender_chests` early personal unlock — final key list
to be agreed with the balance owner; keys that don't exist in `recipegate.json` yet are
added there by this package).

**Files:** new `collections/` (3), new client tab + toast (2), `EclipseSignals` (+1
signal), `AnalyticsService` (+1 subscriber), `EclipsePayloads`/2 new payloads,
`ClientStateCache`, `recipegate.json` defaults, lang keys (en/de). Gametest:
`gametest/collections/CollectionGameTests.java` (counter increments on the natural-mine
lane, tier grant idempotence across relog).

**Effort:** L.

---

## D2 — XP pacing: pre-event/dimension gating + curve retune

**User item:** 4 (level 7 after 5 minutes; level 5 already AT event start).

**Root cause (verified):**

1. **XP is live before the event starts.** `skills/SkillService.addXp` has NO gate on
   `EclipseWorldState.isStartEventDone()`. Every signal lane (mine/kill/explore/craft…)
   pays out from the moment the server starts. Pre-event lobby/limbo activity therefore
   accrues XP; that is the "level 5 at event start".
2. **XP is live in every dimension.** Neither `AnalyticsService`/`AnalyticsSampler`
   (signal producers) nor `SkillService` (consumer) filters by dimension. The 1 Hz
   sampler pays `exploreChunk` (5 XP) and `visitNewBiome` (40 XP) for walking around
   limbo, the minigame arenas and the xbox worlds; minigame kills pay the kill table.
3. **The curve is front-loaded-cheap.** `skills/SkillCurve` with the shipped defaults
   (`baseCost 20`, `exponent 1.3`) prices cumulative XP as C(L) = 20·L^2.3/2.3:
   C(5) ≈ 350 XP, C(7) ≈ 765 XP. With `visitNewBiome 40`, `exploreChunk 5`,
   kills 5–16 and the advancement table (25–200 each, `AdvancementXpBridge`), a normal
   first half-hour trivially clears level 7. The doc comment in `SkillConfig`
   ("~L12 after 4h") confirms the curve was tuned for a much lower XP/h than the
   actual earn tables produce.

**Fix (all inside `skills/`, one new helper):**

1. New `skills/XpGates.java` — single static predicate
   `boolean actionXpAllowed(ServerPlayer player)`:
   - `false` while `!EclipseWorldState.get(server).isStartEventDone()`;
   - `false` when `player.level().dimension()` is LIMBO, a `MinigameDimensions` id, or
     `XboxDimensions.isXboxDimension(...)` (import-free string/namespace check or direct
     API calls — the helpers exist);
   - `true` otherwise. Config toggles in `skills.json`: `"gates": { "preEvent": true,
     "eventDimensions": true }` so ops can re-enable for tests.
2. Apply the gate at the TOP of `SkillService.addXp` for positive amounts from ACTION
   sources (mine/kill/explore/craft/smelt/trade/breed). Explicit reward sources
   (`quest`, `altar`, `advancement`, `collection`, `contract`, `admin`, negative death
   XP) stay allowed — quests completed at the altar must keep paying. (Minigame payouts
   call `SkillsApi.addXp(player, …)` with their own source key from
   `minigames/MinigameService` — those are action-adjacent; gate them via the dimension
   check by keeping their source key OUT of the exempt list, per the user's "XP OFF in
   minigames".)
3. Curve retune in `SkillConfig.defaultsJson()` (and doc comment): `baseCost 45`,
   `exponent 1.45`, softcap unchanged. That prices C(5) ≈ 1 900, C(7) ≈ 4 400,
   C(12) ≈ 16 000 — early levels take meaningfully longer (~×5.5) while the softcap
   region keeps its shape. Additionally trim the two explore knobs that dominate the
   first hour: `exploreChunk 5 → 2`, `visitNewBiome 40 → 15`, and add
   `dailyCaps.explore 2000 → 800`.
4. NOTE for existing saves: config files already on disk are NOT rewritten (loadOrCreate).
   Add a `_doc` line + changelog entry telling ops to delete `skills.json` or apply the
   new curve values manually, then `/eclipse reload`.
5. **Seam for D11 (rebirth):** while editing `SkillService`, introduce the one-line
   indirection `SkillCurve.Params curve = RebirthHooks.curveFor(server, uuid, SkillConfig.get().curve())`
   at the three `SkillConfig.get().curve()` call sites (`addXp` → `handleLevelUps`,
   `syncTo`, `runLevelSweepAndSync`). `RebirthHooks` ships in THIS package as a static
   pass-through (returns the params unchanged); D11 replaces its body. This keeps
   `SkillService.java` owned by D2 alone.

**Files:** `skills/XpGates.java` (new), `skills/RebirthHooks.java` (new pass-through),
`skills/SkillService.java`, `skills/SkillConfig.java`, gametest
`gametest/skills/XpGateTests.java` (pre-event denial, limbo denial, quest-source
exemption, retuned-curve level anchor pins).

**Effort:** M.

---

## D3 — Kill-contract debuffs: window-scoped, not day-scoped

**User item:** 2.

**Root cause (verified — the user is right):** every SUCCESS/WRONG_KILL/TABLES_TURNED
modifier is granted with `expiresAfterDay = state.contractDay()` and only purged by
`ContractModifierService.onDayRollover` (POST). Since real days last a full real-world
day (`RealtimeDayService`), a wrong-kill Blutschuld or a target's damage/skills malus
lasts up to ~24 h of play instead of the hunting window. Evidence:
`contracts/ContractService.applyWrongKill/resolveSuccess/resolveTablesTurned` (grants with
`day`), `contracts/ContractModifierService.Entry.expiresAfterDay` + `removeExpired(newDay)`.

**Design decision (matches the user's ask):** DEBUFFS (anything with value < 1.0 for the
holder: damage malus, skills malus, negative temp hearts, grudge held AGAINST you) end
when the CONTRACT WINDOW ends. ADVANTAGES (hunter/survivor buffs) may keep the day scope
— they are the prize. Award-void (`AWARD_VOID`) stays day-scoped (it exists to void the
daily award).

**Fix:**

1. Extend `ContractModifierService.Entry` with `long expiresAtEpochMillis` (0 = day-scoped
   only; NBT-compatible: absent field loads as 0 for old saves).
2. New overloads `grantDamageMulUntil(server, holder, mul, epochMillis)` etc.; a 100-ticks
   sweep in `ContractModifierService` purges epoch-expired entries (reusing the exact
   restore logic of `onDayRollover`: reset `SkillsApi.setSecretMultiplier` to 1.0,
   `applyTempHearts` rebuild). Pause-aware: shift stored epochs on
   `RealtimeDayApi.isPaused` resume exactly like `ContractState.shiftDeadlines` does
   (copy the persisted-anchor pattern, FFIX-B).
3. `ContractService`: wrong-kill and target-side grants pass
   `state.endsAtEpochMillis()`; hunter-side advantage grants stay day-scoped. Because the
   window may already be near expiry when a wrong kill lands, floor the debuff at
   `windowEnd` but let `ContractConfig` add `debuffMinMinutes` (default 10) so a
   last-second Blutschuld still stings a little.
4. `/dev contract status` (`DevContractCommands` → `ContractModifierService.describe`)
   prints the remaining minutes for epoch-scoped rows.

**Files:** `contracts/ContractModifierService.java`, `contracts/ContractService.java`,
`contracts/ContractConfig.java`, `devtools/dev/DevContractCommands.java` (describe line
only), gametest `gametest/contracts/ModifierWindowTests.java` (epoch expiry sweep,
save/load round-trip of the new field, day-scoped advantage still clears on rollover).

**Effort:** M.

---

## D4 — Out-of-event kill = heart STEAL: ceremony + anti-farm safeguards

**User item:** 3.

**Root cause / current state (important — the transfer already EXISTS):**
`lives/LifecycleEvents.onLivingDeath` already moves a life on EVERY player kill: victim
loses 1 (`LivesApi.add(victim, -1)` — on any death), and a player killer gains +1 when
the victim actually lost one, capped at `HeartsService.MAX_HEARTS`; the umbral blade adds
a second. What is MISSING versus the user's rule:

- **No feedback ceremony** — deaths are deliberately chat-silent; the steal is invisible
  (no "X stole a heart" moment for killer/victim).
- **No safeguards** — the same pair can farm kills back-to-back; a PvP kill can push the
  victim to 0 lives → `BanService.ban` (run-ending by murder outside any event).
- **No event awareness** — during an ACTIVE REAL contract window the LifecycleEvents
  transfer STACKS with contract resolution rewards (hunter gets kill-transfer heart AND
  contract payout).
- **Ghost exception is already half-done**: a 0-heart victim mints nothing
  (`heartLost` check), and `ghosts/LogoutGhostEntity` proxies are not ServerPlayers so
  they never enter this path. Banned "ghost players" walking around DO enter it — they
  must be excluded explicitly.

**Fix (all in `lives/`, reading contract state via the existing public
`ContractService.stateOf(server)`):**

1. New `lives/HeartTheftRules.java` — policy + state:
   - `TheftVerdict evaluate(killer, victim)` → STEAL / NO_STEAL_(reason).
   - Applies ONLY outside an ACTIVE REAL contract window in which killer/victim are the
     contract pair (contract kills resolve through D3's economy instead; non-pair kills
     during a window remain normal steals — the wrong-kill Blutschuld already punishes
     the hunter case).
   - **Pair cooldown:** persisted `(killer, victim) → epochMillis` map (SavedData
     `eclipse_heart_theft`); default `pairCooldownHours 20` — within cooldown the victim
     still dies but NO life moves in either direction (no farming the same victim).
   - **Min-lives floor 1:** if the victim is at 1 life, an out-of-event player kill takes
     NOTHING (no victim loss, no killer gain) — murder can never ban outside events. The
     floor applies to the PvP branch only; PvE/environment deaths keep the current
     "0 → ban" flow untouched.
   - **Ghost exception:** skip when victim or killer `getData(EclipseAttachments.BANNED)`
     or `EclipseWorldState.isBanned(uuid)` (mirror `ContractService.isEligible`).
   - Config block in a new `config/eclipse/hearts.json` (`heartTheft`: enabled,
     pairCooldownHours, floorLives 1, ceremony toggles).
2. Restructure the transfer branch of `LifecycleEvents.onLivingDeath` to route through
   `HeartTheftRules` (keeping the umbral-blade bonus inside the STEAL branch, still
   capped).
3. **Ceremony** (never chat, per anonymity rules): killer gets
   `S2CHeartBurstPayload`-style gain FX + `message.eclipse.theft.taken` action bar;
   victim (on respawn, riding the existing `PENDING_HEART_LOSSES` handoff) gets the loss
   burst + `message.eclipse.theft.lost`; everyone else keeps only the anonymous thunder.
   One new sound cue (deep bell + heart pulse) via `EclipseSounds`.
4. `/dev` visibility: extend `DevPlayerCommands` STATUS output with active theft
   cooldowns for the inspected player.

**Files:** `lives/HeartTheftRules.java` (new), `lives/LifecycleEvents.java`,
`devtools/dev/DevPlayerCommands.java` (status line), lang keys, gametest
`gametest/lives/HeartTheftTests.java` (steal, pair cooldown, floor-at-1, contract-pair
exemption, ghost exemption).

**Effort:** M.

---

## D5 — Quests: phase-aware assignment + a genuinely harder ladder

**User item:** 5.

**Root cause (verified):**

1. **Phase-awareness exists structurally but is unused where it matters.**
   `GoalSpec.minDay/maxDay` window-gates PERSONAL draws (`QuestEngine.drawPersonals` →
   `spec.inDayWindow(day)`), but the authored personal pool in
   `GoalConfig.defaultQuestsJson()` leaves most windows open (0), so nether-flavoured
   personals can be drawn before the nether unlocks. Day MAINS are hard-authored per day
   and can't drift — but they were authored against the wrong gate: `EclipseConfig`
   `DayPlan(2, …)` unlocks `"nether"` on day 2 while fortress content waits until day 6,
   and personals never check `UnlockState` at all.
2. **Difficulty:** the shipped `defaultGoalsJson()` ladder barely escalates (day 3 mains:
   craft one iron pickaxe/axe/sword each — that IS day-1-shaped work; sides on day 3–5
   are "place 64 blocks", "jump 500 times"). The §2.2 "slightly harder" migration pass
   raised numbers ~20% but not shape.

**Fix (owns `progression/goals/` defaults + one engine filter):**

1. **Unlock-aware draw filter** in `QuestEngine.drawPersonals`: skip specs whose new
   optional `requiresUnlock` field (added to `GoalSpec`, default empty) names an
   `UnlockState` key that is not yet granted (`"nether"`, `"end"`, `"brewing"`,
   `"enchanting"`, `"create"`, …). This is the real phase gate — day windows remain as
   the coarse bound. Also apply it in `QuestEngine.resolved` when materializing SIDES
   (sides move with the day file, but a reroll after a stalled unlock must not show
   locked content). Payload/UI untouched — filtered specs simply never appear.
2. **Author `requiresUnlock` + tight `minDay` on the default personal pool** (every
   nether/end/brewing/enchanting-flavoured personal gets its key; early-game filler gets
   `maxDay` so late-game draws stop offering "craft a stone pickaxe").
3. **Retune the day ladder** in `defaultGoalsJson()` — keep day 1–2 as the on-ramp, then
   push shape, not just numbers (targets for the worker; final numbers with balance
   owner):
   - Day 3: replace the three "one iron tool each" mains with ONE team-scoped forge
     main (team crafts 2 full iron sets), a Create-contraption main (beat
     `create_kinetics_built`, day-3 unlock is `create`), and an exploration main
     (team charts 96 chunks). Sides: cave-depth Y ≤ -40, 20 hostile kills, 24 iron ore.
   - Day 4–5: food-chain main becomes "cook 12 Farmer's Delight MEALS" (craft lane
     detects FD ids), husbandry side doubles, piston main 16 → 24 + add a redstone side.
   - Day 6+: fortress/blaze mains get per-player minimums (`EACH_PLAYER` variants) so one
     rusher can't clear team goals alone; add altar-milestone beats as mains on 7/9/12
     (already-supported `beatId`s).
   - Scale all side XP by the D2 curve retune (sides 100–120 → 150–250) so quests remain
     the best XP source relative to grinding (that's the intended dopamine shift).
4. Config-migration note (same policy as D2): defaults only apply to fresh files; ship
   `docs/plans_v3/plans_v5/goals_v5_migration.md` with the JSON diff for live saves.

**Files:** `progression/goals/GoalSpec.java` (one field + parse/serialize),
`progression/goals/QuestEngine.java` (draw/resolve filter),
`progression/goals/GoalConfig.java` (defaults), migration note, gametest
`gametest/goals/PhaseAwareDrawTests.java` (locked-key spec never drawn; unlock →
becomes drawable after reroll).

**Effort:** M.

---

## D6 — Phase cadence: what "4 hours" actually is + real `/dev` control

**User items:** 6 + the phase-interval half of 13.

**Root cause (verified):** there is NO 4-hour phase timer in the code. The "next phase"
bossbar is `RealtimeDayService`'s day countdown; the arc advances once per REAL day at
`realtime.json` `boundaryTime` (default `Europe/Berlin 18:00`,
`progression/realtime/RealtimeConfig`). A "4 hours" experience can only come from a
manual one-shot (`/eclipse-rt set +4h` / legacy `/eclipse schedule`), which DISARMS after
firing (`onDayApplied` one-shot branch) — so whoever ran the event kept re-arming
one-shots by hand and never had a recurring knob. The user's frustration ("wo sind meine
Commands?") is justified: the commands exist (`/eclipse-rt arm|set|add|pause|status`,
`RealtimeCommands`) but (a) there is no recurring interval mode, and (b) none of it is
registered in `DevCommandRegistry`, so `/dev help` / the dev handbook never mention it.

**Fix:**

1. `RealtimeConfig`: add `cadenceMode: "daily" | "interval"` (default `daily`) and
   `intervalHours` (default 4.0, used only in interval mode). `RealtimeMath.nextBoundary`
   grows an interval overload (`prevBoundary + intervalHours`, clamped ≥ 5 s).
2. `RealtimeDayService`: route every `RealtimeMath.nextBoundary(now, zone, boundaryTime)`
   call through a single `nextBoundaryFor(state, cfg, anchorMillis)` helper that
   respects the mode (5 call sites: arm, clearManualOverride, onDayApplied re-anchor,
   runFireCheckNow rollover, catch-up step + skipGuardedSlot). The epoch-day dedup guard
   applies only in `daily` mode (interval mode legitimately advances twice per calendar
   day).
3. New `devtools/dev/DevPhaseCommands.java` (registered docs → `/dev help` under
   "Event"):
   - `/dev phase status` — day X/maxDay, mode, boundary, remaining (delegates
     `RealtimeDayService.status`).
   - `/dev phase interval <hours>` — set `cadenceMode=interval` + `intervalHours`,
     persist `realtime.json`, re-arm (answers the user's "2 hours instead of 4" with one
     command: `/dev phase interval 2`).
   - `/dev phase daily <HH:mm> [zone]` — back to daily mode.
   - `/dev phase next [<+NhNNm|HH:mm>]` — one-shot boundary (wraps
     `RealtimeDayService.setBoundarySpec`).
   - `/dev phase pause|resume` — wraps pause/resume.
4. `docs/DEV_COMMANDS.md` regenerates automatically via `/dev docs export`; also add a
   short "day/phase cadence" paragraph to `README` ops section.

**Files:** `progression/realtime/RealtimeConfig.java`, `RealtimeMath.java`,
`RealtimeDayService.java`, `devtools/dev/DevPhaseCommands.java` (new; registered from
`DevRoot`), README/ops doc touch, gametest `gametest/realtime/IntervalCadenceTests.java`
(interval boundary chain with injected `EclipseClock`, no epoch-day dedup in interval
mode, persistence round-trip).

**Effort:** M.

---

## D7 — Mod checker rework (allowlist truth, readable screen, dev bypass, version bumps)

**User item:** 7 (+ implements the dev-privilege path referenced by item 8).

**Root causes (each verified):**

- **(a) Bundling is NOT the bug.** The built jar
  (`build/libs/eclipse-2.1.0.jar`) verifiably contains
  `META-INF/jarjar/{emi-neoforge-1.1.18+1.21.1, geckolib-neoforge-1.21.1-4.9.2,
  mouse-tweaks-1.21-2.26.1-neoforge, veil-neoforge-1.21.1-4.3.0}.jar` — the
  `tasks.named('jar') { from(tasks.named('jarJar')) }` wiring in `build.gradle` works.
- **(b) "fabric api base" ROOT CAUSE FOUND:** the NeoForge builds of **Sodium
  0.8.12** and **Iris 1.8.14-beta.1** each jarJar four **Forgified Fabric API
  sub-modules** — verified by unpacking `run/mods-client/*`: mod ids
  `fabric_api_base`, `fabric_block_view_api_v2`, `fabric_renderer_api_v1`,
  `fabric_rendering_data_attachment_v1` (displayName "Forgified Fabric API …").
  `AntiCheatCheck.loadedMods()` includes nested jar-in-jar mods, the allowlist knows
  `sodium`/`iris` but not the sub-modules → UNKNOWN violations for every client running
  the optional performance extras. **No pack mod needs a standalone Forgified Fabric API
  install** — the sub-modules ride inside Sodium/Iris and only need allowlisting.
  Document exactly this in `docs/BUNDLING.md`.
- **(c) The "blurry" screen:** `bootstrap/BootstrapScreen` is opened via
  `ScreenEvent.Opening` replacing the title screen; on 1.21.1 vanilla applies the
  `Screen.renderBlurredBackground` menu-blur pass to child screens that don't override
  `renderBackground` — `BootstrapScreen.render` draws its own gradient but never
  overrides `renderBackground/renderBlurredBackground`, so vanilla blur composites over
  the panel. Rows are also raw `drawString` with `shadow=false` on a translucent panel
  (low contrast), 8 visible rows with wheel-only scroll and no version column alignment.
- **(d)** No dev/allow-bypass concept exists anywhere (grep confirms: no dev UUID list).
- **(e) Version research (Modrinth API, checked 2026-07-24):** EMI latest for 1.21.1
  NeoForge is **1.1.24+1.21.1+neoforge** (published 2026-05-13; 1.1.18 is from
  2024-11 — user is right that it's ancient). Mouse Tweaks: **1.21-2.26.1-neoforge is
  STILL the newest 1.21.1 NeoForge artifact** (2024-08-17) — no bump possible; record
  the verdict.

**Fix:**

1. **Allowlist truth** (`admin/AntiCheatCheck.defaults()` + baked
   `assets/eclipse/bootstrap.json`): add optional entries
   `fabric_api_base: "*"`, `fabric_block_view_api_v2: "*"`,
   `fabric_renderer_api_v1: "*"`, `fabric_rendering_data_attachment_v1: "*"`.
   Additionally make `snapshotRunningServer` the documented ops path (it already captures
   nested ids since `loadedMods()` walks the full ModList) and extend
   `/dev modcheck snapshot` (`DevModcheckCommands`) to ALSO regenerate the baked-manifest
   JSON to `run/bootstrap.json.suggested` so the client manifest can't drift from the
   server allowlist again.
2. **Screen rework** (`bootstrap/BootstrapScreen`): override
   `renderBackground`/`renderBlurredBackground` to kill the vanilla blur; two-column
   rows (mod id | installed → expected) with shadowed text, reason-grouped headers
   (Missing / Wrong version / Unknown / Blocked), a real scrollbar
   (`client/handbook/tabs/TabScrollbar` is reusable), a clickable download-hint button
   (`downloadHintUrl` → `Util.getPlatform().openUri`) and a "copy report" button
   (clipboard: violation list + loaded-mods dump) — no more squinting at a blurred wall.
3. **Dev bypass, UUID-pinned & config-listed** (the clean path item 8 asks for):
   new `devBypassUuids: []` array in `anticheat.json` (and mirrored optional
   `devBypassUuids` in the baked manifest for the local screen). Server side:
   `AntiCheatCheck.handleModlist` + the timeout sweep skip enforcement when
   `player.getUUID()` is listed (log INFO "modcheck bypass (dev)"), and grant the
   elevated dev rights by adding the UUID to the vanilla op-permission path is NOT ours —
   instead expose `AntiCheatCheck.isDevBypass(uuid)` and have `DevRoot` accept
   permission-2 OR dev-bypass UUIDs for `/dev` (single check point). Ship the config
   default with a commented placeholder — the operator inserts Sonic0810's real UUID
   (name→UUID pinning at runtime via `server.getProfileCache()` fallback if the config
   lists `"name:Sonic0810"`).
4. **EMI bump to 1.1.24+1.21.1** — `build.gradle` (compileOnly api + jarJar strict/prefer),
   `gradle.properties` if the version is extracted there, `AntiCheatCheck.defaults()`,
   `bootstrap.json`, `docs/BUNDLING.md` row + Mouse Tweaks "no newer NeoForge build
   exists (checked 2026-07)" note. Verify the EMI plugin (`client/emi/`) compiles against
   1.1.24 (EMI API is stable across 1.1.x; the plugin uses recipe-lock decoration only).
5. Regression gametest `gametest/admin/ModcheckEvaluateTests.java`: nested-id report
   containing the four fabric ids passes in allowlist mode; unknown id still fails;
   bypass UUID skips.

**Files:** `admin/AntiCheatCheck.java`, `bootstrap/BootstrapScreen.java`,
`bootstrap/PackBootstrap.java` (manifest field), `assets/eclipse/bootstrap.json`,
`devtools/dev/DevModcheckCommands.java`, `devtools/dev/DevRoot.java` (bypass check),
`build.gradle`, `docs/BUNDLING.md`, lang keys, gametest.

**Effort:** L.

---

## D8 — "Configs are just .json = easily bypassed": honest analysis + real hardening

**User item:** 8.

**Analysis to be written verbatim into the worker output (and a new
`docs/plans_v3/plans_v5/security_model.md`):**

- **Server-side JSON configs cannot be bypassed by clients.** `config/eclipse/*.json`
  (anticheat.json, skills.json, goals.json, …) live on the SERVER filesystem and are read
  only by server code (`FMLPaths.CONFIGDIR` on the dedicated server). A client cannot
  see or edit them; "it's plain JSON" affects only people with server file access, who
  are already trusted. Format is irrelevant to security; AUTHORITY is what matters.
- **What IS client-trusting today (the honest list, from code):**
  1. `C2SModlistPayload` is a self-report — a modified client can lie about its mod list
     (`AntiCheatCheck` javadoc already admits "deterrent rather than a security
     boundary"). Unfixable client-side by design; document it.
  2. The baked `assets/eclipse/bootstrap.json` (client-side manifest) decides
     `allowContinueOnMismatch` locally — a re-zipped jar can flip it. Harmless: the
     server check still runs; document it.
  3. `anticheat/AntiXrayConfig` + `OreExposureRules` are fully server-side — nothing to
     harden.
- **Real hardening delivered by this package:**
  1. Server-authoritative mismatch policy: move the effective "may continue with
     mismatch" decision to the server config (`anticheat.json` `allowContinueOnMismatch`)
     — on login the server sends its verdict; the client screen keeps its local warning
     but the server disconnect (already implemented in `handleModlist`) becomes the only
     authority. (One S2C field on an existing login payload; no new packet.)
  2. Audit pass over every `C2S*Payload` handler for server-side validation gaps, using
     `WandPowers.handleCast` (isActorValid + full server validation) as the gold
     standard; fix any handler that trusts client state (checklist output in the doc:
     `C2SConfigEditPayload` — verify permission check server-side; `C2SSkillNodeBuyPayload`
     — already validated in `SkillService.buyNode`; handbook run commands — validated by
     `DevCommandRegistry.matchSyntaxPrefix`).
  3. The Sonic0810/dev-UUID path is implemented in D7 (config-listed, UUID-pinned,
     name-fallback) — this package only documents its trust model (bypass grants CLIENT
     mod freedom + `/dev` access; it never grants op).

**Files:** `docs/plans_v3/plans_v5/security_model.md` (new),
`network/EclipsePayloads`-adjacent audit fixes (expected ≤ 2 small handler edits — the
audit itself lists them), server-verdict field wiring. No overlap with D7's files except
via the D7-owned `anticheat.json` schema (D8 adds no fields; it reuses D7's).

**Effort:** S–M (audit-driven).

---

## D9 — Distributable pack: Modrinth `.mrpack` + generator script

**User item:** 9.

**Root cause / current state:** No pack artifact exists in the repo; `docs/BUNDLING.md`
already contains the complete legal inventory (licenses, "may we redistribute" verdicts)
and `tools/modpack/fetch_dev_mods.py` already resolves exact Modrinth versions for the
dev environment — an `.mrpack` generator is a natural extension. The `.mrpack` format
(Modrinth pack spec) REFERENCES downloads by URL+hash instead of redistributing jars,
which sidesteps every ARR blocker listed in BUNDLING.md (Sophisticated*, Voice Chat,
Supplementaries, Aeronautics bundle, Create assets).

**Answer to the explicit question — must Forgified Fabric API be included?** **No.**
Verified (see D7): the only `fabric_*` ids in the pack come from sub-modules jarJar'd
INSIDE Sodium and Iris NeoForge builds. No pack mod declares a dependency on standalone
Forgified Fabric API; nothing to add to the pack. The ids just need allowlisting (D7).

**Fix:**

1. `tools/modpack/build_mrpack.py` (stdlib-only, same style as `fetch_dev_mods.py`):
   - Reads a new `tools/modpack/pack_manifest.json` (single source of truth: modrinth
     slug or direct URL, exact version id, client/server env flags, sha512 — initial
     content = the BUNDLING.md inventory incl. EMI 1.1.24 after D7's bump).
   - Emits `build/pack/eclipse-event-<version>.mrpack`: `modrinth.index.json` with
     `files[]` (downloads + hashes + env), `dependencies { minecraft: 1.21.1,
     neoforge: 21.1.238 }`, and an `overrides/` folder that carries ONLY
     redistributable content: the Eclipse jar itself (ARR but ours) and default
     `config/eclipse/` seeds.
   - Mods that are NOT on a public CDN (the Aeronautics bundled build, Sable per its
     PolyForm Shield policy) cannot be `files[]` entries: the script emits a
     `MANUAL_INSTALL.md` inside overrides listing them with the operator-source note —
     exactly the current BUNDLING.md policy, now machine-shipped.
   - `--verify` mode re-downloads and sha512-checks every reference (CI-friendly).
2. `tools/modpack/README.md` — how to build, what lands where, the legal rationale
   (link to BUNDLING.md), plus the FFAPI answer above.
3. `docs/BUNDLING.md`: new "### Modrinth pack (.mrpack)" section (D9 owns this section;
   D7 owns the version-row edits — no line overlap).

**Files:** 2 new tool files + manifest json + BUNDLING.md section. No Java.

**Effort:** M.

---

## D10 — Wand: per-path FX rework, findable progression UI, double-click buy

**User item:** 10.

**Root causes (verified):**

- **FX "all bad":** `wand/WandPowers` casts share generic assets: only TWO quasar
  emitters exist for all nine powers (`unlock_burst`, `eclipse_lightning_impact`), the
  rest is vanilla `ParticleTypes.FLAME/END_ROD/SMALL_FLAME` plus the shared
  `FxPayloads.FX_RIFT_OPEN/FX_SHOCKWAVE/FX_LIGHTNING_STRIKE` channels — GLUT and STERN
  read nearly identical (both end in white sparkles + a lightning ribbon), and nothing
  is composed per-path.
- **Skill tree unfindable:** wand progression state lives ONLY on the item
  (`WAND_LEVEL/WAND_XP` components) + `wand.eclipse.msg.levelup` chat lines; there is no
  screen, no tab, nothing in the skill screen (`client/skills/SkillTreeScreen`) or the
  handbook (`client/handbook/HandbookScreen` tab list) that mentions the wand.
- **No double-click buy:** `client/skills/SkillTreeWidget.onClick` only SELECTS a node;
  purchase requires the separate buy button in `SkillTreeScreen`.

**Fix:**

1. **FX rework — one distinct Veil/Quasar composition per power** (9 new emitter ids
   registered in the P2 quasar registry; server sends the SAME budgeted channels, so no
   new network surface). Concrete compositions for the worker (server changes limited
   to swapping emitter ids + adding 1–2 scheduled beats per cast in `WandPowers` /
   `WandTickService`):
   - RISS (glitch/void — palette 0xB98CFF/black): `riss_blink_tear` (two mirrored
     shard-implosions with chromatic sparks at from/to), `riss_wave_front`
     (ground-hugging violet scanline band, replaces flat FX_SHOCKWAVE visual for
     Phasenwelle), `riss_schlag_maw` (rift lips + inward debris streaks before the
     damage beat).
   - GLUT (ember/magma — palette 0xFF7B3C): `glut_stoss_lance` (compressed ember dart
     with heat-shimmer trail replacing the FLAME march), `glut_welle_ring` (rolling
     magma crescent wall with dripping embers riding the existing ring march ticks),
     `glut_sprung_crater` (launch scorch + landing lava-splash cone keyed to
     `trackMagmaJump`'s landing).
   - STERN (starlight — palette 0xBFD9FF/gold): `stern_funke_fall` (single needle
     star-streak + prismatic impact bloom), `stern_schauer_field` (telegraph = rotating
     constellation ring, per-star thin silver ribbons — reuse strikeLightning but width
     0.15 + emitter), `stern_komet_core` (huge trailing comet head with afterglow dome).
   - Each cast also gets a per-path CASTER hand flourish emitter (3 ids:
     `riss/glut/stern_cast_hand`) so the paths feel distinct even before impact.
2. **Wand progression UI — new handbook tab** (chosen over a skill-screen tab because
   the skill screen is a single-canvas widget; the handbook rail is the established
   multi-tab surface): `client/handbook/tabs/WandTab.java` — path banner, level 1–5
   ladder with the five power cards (name, cost, cooldown, param summary from
   `WandConfig`), XP bar (`WAND_XP` / `WandConfig.Xp.costForLevel`), "next unlock"
   highlight, and a "how to earn wand XP" footer (cast cost × perCostPoint + killBonus).
   Data: new `S2CWandProgressPayload` synced on wand change (server:
   `WandSoulbind.persistToStore` call sites) — the item components are already on the
   client, but the payload carries config-derived table rows so the tab works with the
   wand in a chest too. ALSO add an inventory-screen entry point: `WandClientHints`
   gains a "press H" hint line pointing at the handbook tab.
3. **Double-click-to-buy** in `client/skills/SkillTreeWidget.onClick`: if the clicked
   node id equals `selectedNodeId` and the last click was < 350 ms ago and the node is
   affordable+unlocked in `SkillTreeModel`, send `C2SSkillNodeBuyPayload` directly
   (same path as the buy button); keep single-click = select. Server side already fully
   validates (`SkillService.buyNode`), so this is client-only.

**Files:** `wand/WandPowers.java`, `wand/WandTickService.java` (beat scheduling),
quasar emitter registry JSONs (9 + 3 ids, P2's `assets/eclipse/quasar/…` format),
`client/handbook/tabs/WandTab.java` (new), `client/handbook/HandbookScreen.java`
(tab list +1), `network/S2CWandProgressPayload` (+ EclipsePayloads wiring),
`wand/WandSoulbind.java` (sync hook), `client/skills/SkillTreeWidget.java`,
`client/wand/WandClientHints.java`, lang keys.

**Effort:** L.

---

## D11 — REBIRTH system (service/state/API; UI is PLANNER-A's)

**User item:** 11.

**Current state:** no rebirth concept exists (grep-verified). All required primitives
exist: umbral shard balance (`economy/ShardEconomy.getShards/addShards`), lives
(`core/state/LivesApi`, capped by `hearts/HeartsService.MAX_HEARTS`), full skill reset
surfaces (`skills/SkillsApi.setTotalXp(0)` + `resetTree`), and D2 lands the
`skills/RebirthHooks` seam for per-player curve scaling.

**Fix (new `rebirth/` package — server/state/API only; PLANNER-A consumes the API +
payload for the ceremony/UI):**

1. `rebirth/RebirthConfig.java` — `config/eclipse/rebirth.json`:
   `baseCostShards` (default 32), `costGrowth` (default 1.75 → cost_n =
   round(base·growth^n)), `levelCostMultiplierPerRebirth` (default 1.15),
   `maxRebirths` (default 0 = uncapped), `lifeRewardPerRebirth` (1),
   `keepCollections: true`, `keepWand: true` (explicit non-goals of the reset).
2. `rebirth/RebirthState.java` — SavedData `eclipse_rebirth`: per-player rebirth count +
   timestamps (audit trail for awards/drama hooks).
3. `rebirth/RebirthService.java` — the transaction, all-or-nothing on the server tick:
   - Preconditions: player alive, not in an event dimension, personal shard balance ≥
     `costForNext(uuid)`, `LivesApi.get(player) < HeartsService.MAX_HEARTS` (a rebirth
     at the cap would burn the +1 — refuse with a message instead).
   - Execute: `ShardEconomy.addShards(player, -cost)`; `SkillsApi.resetTree(player)`;
     zero `spentPoints/bonusPoints/lastLevelSeen` + `SkillsApi.setTotalXp(player, 0)`
     (needs one new package-private reset helper in `SkillsApi` — coordinate: D2 owns
     `SkillService`, this package may ADD a method to `SkillsApi` only, no edits to
     existing methods); `LivesApi.add(player, +1)`; increment `RebirthState`; fire new
     `EclipseSignals.rebirth(player, count)` for drama/awards/PLANNER-A ceremony.
   - `RebirthApi` (frozen surface): `costForNext(server, uuid)`, `count(server, uuid)`,
     `tryRebirth(player) → Result enum`, `levelCostMultiplier(server, uuid)` =
     `levelCostMultiplierPerRebirth ^ count`.
4. **Curve integration:** implement the body of D2's `skills/RebirthHooks.curveFor`:
   returns `new SkillCurve.Params(base.baseCost() * RebirthApi.levelCostMultiplier(...),
   base.exponent(), base.softcapLevel(), base.softcapMult())` — the "global level-cost
   multiplier per rebirth". (File is owned by D2 as a stub; D11 fills the body — the
   only intentional shared file, one function body, sequenced D2 → D11.)
5. `network/S2CRebirthStatePayload` (count, next cost, multiplier) for PLANNER-A's UI;
   `/dev rebirth <player> [count]` + `/dev rebirth status` in a new
   `devtools/dev/DevRebirthCommands.java` (doc-registered).
6. Gametest `gametest/rebirth/RebirthTests.java`: cost ladder, refuse-at-cap,
   atomicity (insufficient shards = nothing changes), curve multiplier applied to
   `SkillsApi.getLevel` after re-earning XP.

**Files:** new `rebirth/` (4), `skills/SkillsApi.java` (+1 additive method),
`skills/RebirthHooks.java` (body only, D2-created), payload + wiring, dev command,
gametest.

**Effort:** M–L.

---

## D12 — Photon Editor: verdict + minimal adoption plan

**User item:** 12.

**Research result (Modrinth API, checked 2026-07-24) — the user is RIGHT, and
`docs/BUNDLING.md`'s "unresolved/ambiguous" row is STALE:**

- Modrinth project `photon-editor` (id `gzevkJbM`, author KilaBash / Low Drag MC,
  "Photon - Making mc effects as Unity"): **NeoForge 1.21.1 builds exist and are
  current** — latest `mc1.21.1-2.2.0-neoforge` (published 2026-07-21,
  `photon-neoforge-1.21.1-2.2.0.jar`), previous `2.1.5` (2026-06-26), `2.1.4`, `2.1.3.a`,
  … back through 2026-01.
- Dependencies: `2.2.0` declares one required Modrinth dependency → project `zZO0N3W6`
  = **KilaGraph** (MIT, Low-Drag-MC, LDLib2-based node/shader-graph toolkit; has a
  1.21.1 build). `2.1.5` and older declare no Modrinth dependency (self-contained).
- License: Photon is `LicenseRef-Custom-License` → treat as NOT redistributable;
  distribution path is a `.mrpack` reference (D9's format handles it) or manual install.
  Client+server sides are both "required" per the project metadata.

**Adoption plan (minimal, reversible — mirror the `voicechat-api` compileOnly pattern,
NOT a hard dependency):**

1. Target **2.1.5** (no extra dependency) unless testing shows 2.2.0+KilaGraph is
   needed; pin exact version in `gradle.properties`.
2. Soft integration exactly like `ModGate`'s no-compile-dependency stance where
   possible: Photon effects are DATA (`.photon` effect JSONs authored in its editor) +
   a small runtime API to spawn `PhotonFx` at a position. Wrap it in
   `veilfx/PhotonBridge.java` using reflection-or-compileOnly (compileOnly off the
   Modrinth maven `maven.modrinth:photon-editor:mc1.21.1-2.1.5-neoforge`) with a
   hard `ModList.get().isLoaded("photon")` guard and a null-object fallback to the
   existing Quasar emitter — absence of Photon must never crash or degrade below today.
3. Two flagship adoptions ONLY (per the user's ask):
   (a) the Herald summon beam (`entity/boss/HeraldEntity` cinematic) and
   (b) the D10 `stern_komet_core` comet — both authored as `.photon` assets in
   `assets/eclipse/photon/`, both behind the bridge fallback.
4. `anticheat.json`/`bootstrap.json` allowlist rows `photon: "*"` + optional
   `kilagraph: "*"` (OPTIONAL classification; server runs fine without), BUNDLING.md
   row replaces the stale "unresolved" verdict with the evidence above + license note.
5. If in-game testing on NeoForge 21.1.238 shows Photon 2.x mixin conflicts with Veil
   4.3.0 (both hook render pipelines), the fallback verdict is pre-authorized: keep the
   bridge merged but disabled by default (`veilfx.json` flag `photonEnabled=false`) and
   record the incompatibility with logs in BUNDLING.md. That is the "honest final
   verdict with evidence" branch.

**Files:** `veilfx/PhotonBridge.java` (new), `build.gradle`/`gradle.properties`
(compileOnly + maven), 2 photon asset JSONs, `HeraldEntity` + D10 comet call-site
(1-line emitter swaps behind the bridge), BUNDLING.md row (Photon row only — disjoint
from D7/D9 sections), allowlist rows (coordinate: D7 owns `AntiCheatCheck.defaults()` —
land D12 after D7 and add rows in the same schema).

**Effort:** M.

---

## D13 — Dev commands: `/dev lives give`, `/dev chunk regen` (shell)

**User item:** 13 (phase-interval commands are D6).

**Current state:** `/eclipse lives set|add <player> <n>` exists
(`admin/EclipseCommands.livesSet/livesAdd`, perm 3, with the important
`banIfOutOfLives` edge) but is not under `/dev`, not doc-registered, and grants ban on 0.
No chunk-regeneration command exists anywhere (grep: no `regen` in devtools; worldgen
has `StageBackups`/`PristineSnapshots` restore surfaces owned by PLANNER-B's domain).

**Fix:**

1. New `devtools/dev/DevLivesCommands.java`:
   - `/dev lives give <player> <n>` — wraps `LivesApi.add` (positive only; cap at
     `HeartsService.MAX_HEARTS` with a clamp message), perm 2, doc-registered
     (`Danger.CAUTION`). Deliberately no negative path — that stays on the perm-3
     `/eclipse lives` commands with their ban semantics.
   - `/dev lives status [player]` — lives + theft cooldowns (delegates D4's
     `HeartTheftRules` describe; if D4 lands later, ship without that line — additive).
2. `/dev chunk regen [<radius>]` — **command shell + doc only in this package**
   (PLANNER-B owns the regeneration engine per the coordination note): new
   `devtools/dev/DevChunkCommands.java` parses args, resolves the operator's chunk,
   perm 3 + `Danger.DESTRUCTIVE`, and calls a `ChunkRegenApi` interface (new file in
   `devtools/dev/`, default implementation = "not wired yet — see PLAN-B" failure
   message). PLANNER-B's package implements the interface against their pristine
   snapshot/worldgen machinery. This keeps the file ownership disjoint and the
   command/UX consistent regardless of engine landing order.
3. Register both in `DevRoot`, regenerate `docs/DEV_COMMANDS.md`.

**Files:** 3 new devtools files, `DevRoot` (+2 lines), docs regen. No engine code.

**Effort:** S.

---

## D14 — Umbral shard ("Umbral-Splitter") economy: reliable sources + visibility

**User item:** 14.

**Root cause (full source trace, verified):** the economy is TWO currencies sharing one
name, and both are nearly invisible:

- **Physical `eclipse:umbral_shard` items** drop from: `UmbralStalkerEntity` (1–3),
  `TheOtherEntity` (1–2), `HeraldEntity` (3/player) + `HeraldShardProjectile`,
  `RiftWardenEntity` (2, +4 enrage), `FogTyrantEntity` (3, +6), the skill-tree
  night-kill proc (`SkillPerks` shard chance), and day-1 goal `d01_touch_altar` item
  reward. Every one of these is a NIGHT EVENT / BOSS / RARE PROC — a normal player who
  avoids night bosses sees zero shards for days. Banking them (`ShardEconomy.deposit`)
  credits ONLY the team pool (intentional, FINAL-DOPA-SOL §3).
- **Personal balance** (`eclipse:shards` attachment) is granted by `QuestEngine` quest
  rewards, `AwardService` daily awards, `ContractService` payouts, `MinigameService`
  payouts, `/eclipse shards`. BUT: balance is only ever visible while sneaking at the
  altar (action-bar offer line in `ShardEconomy.showOffer`) or in the one-off
  `RewardMaterializeOverlay`. Players literally cannot see what they own → "we never
  really get them".

**Fix:**

1. **Visibility (the bigger half):**
   - HUD: new `client/hud/ShardCountLayer.java` — a small shard icon + personal balance
     (+ team pool in a tooltip-style secondary line) docked next to the skill XP bar
     (`SkillXpBarLayer` placement conventions), driven by a new `S2CShardBalancePayload`
     synced on every `ShardEconomy.setShards`/`EclipseWorldState.addShardPool` change
     (coalesced, login-synced). Fades in on change with a +N delta pop (dopamine).
   - Handbook: add balance + pool + "where shards come from" source list to the
     existing `RewardsTab` (data from the same payload cache; RewardsTab is owned here
     for this addition — no other package touches it).
   - Every personal-balance grant surfaces the delta on the action bar if
     `RewardMaterializeOverlay` didn't already play (single choke point:
     `ShardEconomy.addShards` gains an optional `announce` param used by
     quest/award/contract/minigame call sites).
2. **Reliable earn lanes** (config-tunable, all through existing systems — no new grind
   loops):
   - Personal quests: raise default shard rewards in the D5 ladder so EVERY personal
     quest pays 1–2 shards (currently most pay XP only) — coordinate with D5 (D5 owns
     `GoalConfig` defaults; this package specifies the values in its notes, D5 lands
     them — no file overlap).
   - `glitch/GlitchDrops`: add a guaranteed 1-shard drop to `#eclipse:glitched` kills
     (currently the glitch lane pays XP only) — a nightly, findable, repeatable source.
   - Offering returns: `offering/OfferingConfig` already values `eclipse:umbral_shard`
     as an INPUT; add a shard-strand to offering REWARDS (small chance of 2–4 shards)
     so the altar loop can return them.
   - Keep boss/night sources as the jackpot tier (untouched).
3. `/dev stats query <player> shards_banked` already works; add `shards` (balance) and
   `shard_pool` to `DevStatsCommands` query surface for ops debugging.

**Files:** `client/hud/ShardCountLayer.java` (new), `client/handbook/tabs/RewardsTab.java`,
`network/S2CShardBalancePayload` (+ wiring), `economy/ShardEconomy.java`,
`core/state/EclipseWorldState.java` (pool-change sync hook), `glitch/GlitchDrops.java`,
`offering/OfferingConfig.java`, `devtools/dev/DevStatsCommands.java`, lang keys.

**Effort:** M.

---

## Cross-package sequencing & ownership notes

- **Shared-file map (deliberate, sequenced):** `skills/RebirthHooks.java` is created by
  D2 (stub) and filled by D11 (body only). `AnticheatCheck.defaults()` schema lands in
  D7; D12 adds its two rows after. `GoalConfig` defaults are D5-owned; D14's quest-shard
  values are handed to D5 as numbers. `BUNDLING.md` sections: D7 = version rows,
  D9 = mrpack section, D12 = Photon row. Everything else is fully disjoint.
- **Recommended order:** D2 → D11; D7 → D12; D5 ∥ D14 (values handoff); D3, D4, D6, D1,
  D10, D13, D8, D9 independent.
- **PLANNER-A seam:** D11 exposes `RebirthApi` + `S2CRebirthStatePayload`; ceremony/UI
  is theirs. **PLANNER-B seam:** D13 defines `ChunkRegenApi`; the engine is theirs.
