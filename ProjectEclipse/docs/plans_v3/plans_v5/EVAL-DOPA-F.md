# EVAL-DOPAMINE-F — v5 reward-feel evaluation (game-designer pass)

**Scope:** read-only design review of the v5 dopamine loop: collections, XP curve, quest
ladder, reward surfaces, rebirth economy, heart theft, and the first 30 minutes. All
numbers are computed from the shipped defaults (`SkillConfig.defaultsJson`,
`CollectionsConfig.defaultRoot`, `GoalConfig` defaults) and the `run/config/eclipse/*.json`
files, which match the defaults except where noted. Complements `EVAL-DOPA-S.md`
(correctness audit) — findings there are cross-referenced, not repeated.

**Score: 6.5 / 10.** The celebration *plumbing* is excellent (CenterStageArbiter,
materialize ceremony, per-tier reward previews). The first session lands well. The
deductions are pacing/economy design: the shipped curve overshoots the plan's own retune
target ~2×, the rebirth ladder is economically dominated by a flat-price shop item, two of
the four advertised rebirth income lanes pay a different currency, and quest shard payouts
are invisible until after completion.

---

## 1. Collections

### 1.1 Tier-1 thresholds — genuinely first-session fast? YES

| Collection | T1 threshold | Time to T1 (normal play) | T1 XP |
|---|---|---|---|
| Iron | 15 ore | ~10–20 min (first cave trip) | 50 |
| Copper | 20 ore | ~15 min | 40 |
| Coal | 25 ore | ~10–15 min | 40 |
| Cobblestone | 50 blocks (stone/cobble/deepslate) | ~5–10 min | 50 |
| Timber | 40 logs | ~10 min (day-1 team quest wants 128) | 50 |
| Wheat / Carrot | 30 / 25 harvests | first farm cycle | 40 |
| Zombie / Bone / String | 10 / 10 / 8 kills | first night | 40 |
| Diamond | 5 ore | day 2–3 | 75 |
| Gold / Redstone | 10 ore | day 2 | 50 |

Verdict: the T1 band is exactly right — a normal first session crosses 4–6 tier-ups
(cobble, coal, iron, timber, plus a mob T1 at night). The "next tier only" reward preview
in `CollectionsTab` (progress bar + pips + "+275 XP · +1 SP · unlocks Anvil") is the
correct Skyblock anticipation pattern. T2s (coal 100, iron 75, copper 80) land in session
2 — good cadence.

### 1.2 Tier-up firing reliability — SOLID on all five lanes

`CollectionsService.sweep` fires, per newly crossed tier: XP (`SkillsApi.addXp`, source
`collection`, `XpGates`-exempt so it always pays), SP, `S2CCollectionTierPayload` (client
card + `UI_UNLOCK_STING`), a chat announcement (always, independent of `toastsEnabled`),
and a same-tick `RecipeGate.syncTo` so the unlock and the toast land together. The grant
is monotonic/idempotent. Lanes verified: natural-mine (placed-block filtered), max-age
harvest, kill, shard-bank, allowlisted pickup (see EVAL-DOPA-S lane table for the
producer trace; its DOPA-S-02 pickup-laundering and DOPA-S-06 crash-atomicity caveats
stand but do not affect normal-session feel).

Feel caveats:
- **Toast queue cap 4, oldest dropped** — fine live; a retro config-reload sweep eats
  cards, acceptable.
- **`dailyCreditCap` is 0 everywhere** — a cobble generator (naturally formed = not
  player-placed) makes cobble T5/T6 (6 000/12 500) AFK-farmable. Set
  `dailyCreditCap` ≈ 1 500 on cobblestone specifically.
- **SP drought:** almost every collection pays its first SP at T4–T6 (days 4–10+). Only
  levels (1 SP/level) feed the 25-node tree early. Consider moving one +1 SP down to a
  T2/T3 on two starter collections (coal, timber) for a day-1 "spend a point" beat.

### 1.3 XP flow vs the 150/1.55 curve — the ONE big pacing miss

Curve: `C(L) = 150·L^2.55 / 2.55 = 58.82·L^2.55`, softcap 50 (irrelevant this event).

| Level | 2 | 3 | 4 | 5 | 6 | 7 | 10 | 12 |
|---|---|---|---|---|---|---|---|---|
| Cumulative XP | 345 | 969 | 2 018 | 3 564 | 5 673 | 8 405 | 20 871 | 33 235 |

**The user's first-hour scenario, computed** (200 stone · 0.5 = 100; 30 coal ore · 3 = 90;
20 iron ore · 4 = 80; ~5 kills ≈ 40; 2 quests ≈ 340–440 (one 250-XP day-1 main + one
160–190-XP personal); collection T1s crossed by exactly this activity: cobble 50 + coal
40 + iron 50 = 140; incidentals (craft/smelt/`eclipse:root`) ≈ 50–100):

**Total ≈ 790–990 XP → exactly 2 level-ups** (L1 at 59 XP within minutes, L2 at 345
around minute 30–40), stalling 60–80 % of the way to L3 (969). A strong hour touches L3.
Hour 2 yields at most one level (L3→L4 gap alone is 1 049 XP ≈ another full hour). Day 1
total for a coordinated player ≈ 2 800–3 900 XP → L4, L5 for hardcore; day 14 ≈ L12–13.

**This overshoots the plan.** PLAN-D §D2 explicitly targeted `C(5) ≈ 1 900, C(7) ≈ 4 400,
C(12) ≈ 16 000` ("~×5.5 the old grind"). Shipped is `3 564 / 8 405 / 33 235` — **1.9–2.1×
harder than the plan's own anchors** (~×10 old grind, as the `_doc` admits). The early
game survives only because collections/quests carry it; the *leveling lane itself* goes
quiet after minute ~40, and the LevelUpOverlay milestone celebrations at **25 and 40 are
dead content** (L25 = 216 k XP — unreachable at ~3 k/day over 14 days).

**Recommendation (exact):** `curve.baseCost 150 → 90`, keep exponent 1.55. That prices
C(2)=207, C(3)=581, C(5)=2 138, C(7)=5 043, C(12)=19 941 — the first hour yields 3
levels, day 1 ends at L5, day 14 at ~L14–15, still ~6× the old grind late. Also retune
`LevelUpOverlay.MILESTONE_LEVELS {10,25,40} → {7,12,18}` (and the matching
`skill_10/25/40` advancement ids) so every milestone celebration can actually fire.

---

## 2. Quest ladder (GoalConfig defaults, days 1–3)

| Day | Goal | Per-player load (4–6 players) | Verdict |
|---|---|---|---|
| 1 | 128 logs (team) | 21–32 logs | Easy on-ramp, ~15 min |
| 1 | Stone pickaxe (TEAM_ALL) | trivial | Hostage to one AFK/no-show |
| 1 | Touch altar (TEAM_ALL, r10) | trivial | Same hostage risk |
| 2 | Enter Nether (each) | 1 portal/breach | Medium, right for day 2 |
| 2 | Smelt 32 gold (team) | 5–8 ingots | Hard-ish but fair (nether gold smelts) |
| 2 | Altar level 1 (beat) | shared | Fine |
| 3 | 12 iron gear pieces (team) | ~55–70 iron total | Hard but achievable — sides feed it (2× "mine 24 iron" sides on d2/d3) |
| 3 | Create kinetics (beat) | shared | Good variety |
| 3 | 96 chunks (team) | 16–24 chunks | Easy |

Quantities are well-judged: day 1–2 are an on-ramp, day 3 pushes. Two design notes:

- **TEAM_ALL hostage problem:** 2 of 3 day-1 mains block on every roster member. One
  no-show turns the strongest onboarding day into 1/3 mains done. Recommend day 1 uses
  TEAM_TOTAL or `each_player` scope only (move the TEAM_ALL "everyone" beats to day 4+
  where rosters have settled).
- **Shard payouts are NOT visible.** `S2CQuestStatePayload.QuestEntry` carries
  id/kind/text/progress/target/done — no reward fields. Players cannot see that
  `d02_altar_1` pays ◆1 or that a personal pays ◆1–2 until the materialize ceremony
  plays. Anticipation is half the dopamine; per D14 the personal-quest ladder is
  *the* rebirth income and it's advertised nowhere in the quest UI (only the generic
  earn-lane text in `RewardsTab`). **Add `rewardXp`/`rewardShards` to the payload and
  render a "◆2" chip on quest rows.**
- Personal pool (D14): every personal pays 1–2 shards ✓, weights/day-windows sane,
  `requiresUnlock` phase gates correct. 3/day is right. Day-1 draws can roll slow grinders
  (jump 1 000×, swim 500 m); consider `maxDay 0 → minDay 2` on `p_swimmer`/`p_leaper` so
  day 1 rolls stay snappy.

---

## 3. Reward surfaces

| Surface | Center-stage arbitrated? | Notes |
|---|---|---|
| `LevelUpOverlay` | ✓ `tryClaim`/`release` correct, queue coalesce | Milestones 25/40 unreachable (see §1.3) |
| `RewardMaterializeOverlay` | ✓ | The quest/award/boss ceremony — strong |
| `AnnouncementOverlay` day card | ✓ | |
| `BossIntroOverlay` | ✓ | |
| `AwardsOverlay` roulette | ✓ (hard-cap lease) | |
| `CollectionTierToast` | ✗ hotbar lane, own queue | h−84, 2 lines |
| `ShardGainToast` | ✗ hotbar lane, own queue | h−82, 1 line |

The h/3 hero band is clean — simultaneous level-up + reward materialization + day card
serialize correctly. **The hotbar band is not:** `CollectionTierToast` (h−84, pill spans
≈ h−87…h−62) and `ShardGainToast` (h−82, pill ≈ h−85…h−71) overlap almost completely when
both are active (each one's javadoc claims "one lane above the skill proc toast" but they
measured from different bases, 59 vs 70 — same finding as DOPA-S-05). A contract/minigame
shard gain landing during a tier card renders through it. **Fix: one shared bottom-toast
queue, or stack the lanes for real: proc 59, shard 82, collection 104.** Also note the
`SkillProcToast` materializing lift (→70) puts it under an active 2-line collection card
(card bottom ≈ h−62, lifted proc top ≈ h−73) — the shared queue solves this too.

`RewardsTab` teaser: the "???" GlitchText next-tier row + live shard balance + explicit
team-pool label is exactly right. One gap: it lists earn lanes as text but never the
*numbers* (personals 1–2, awards 3–4). Numbers create goals; add them.

---

## 4. Rebirth loop — reachable, but economically broken

**Costs** (`8·1.6^n`, personal balance): 8, 13, 20, 33, 52 — cumulative 8/21/41/74/126.

**Personal-shard income/day (5-player server, active player):**

| Source | Expected/day | Notes |
|---|---|---|
| Personal quests (3/day, ◆1–2, ~80 % done) | ~2.9 | The reliable base, as designed |
| Day mains/sides shard rewards | ~1.9 avg (0–1 on d1–3, 3–4 late) | Paid to every eligible player |
| Awards (3/day, ◆3–4 winner, ◆1 consolation) | ~2.5 | Needs ≥30 min playtime; day 2+ |
| Contracts | **0 — `autoDaily: false` in run config** | Even enabled: ~0.8/day expected |
| Minigames / offering | 0–1 | Event-driven |

**≈ 4–5/day on days 1–2, 6–8/day mid-event → cumulative ≈ 90–100 by day 14.** So the
ladder *is* reachable: rebirth #1 on day 2, #2 ~day 4, #3 ~day 6–7, #4 ~day 10–11 — a
well-paced 4-step ladder on paper. **But:**

1. **Boss "shards" don't fund it.** Herald (3 each), Rift Warden (2), Fog Tyrant
   (`3 + players−1`, cap 8) pay *physical* shards via `deliverShardItems` — team-pool
   value only, deliberately excluded from the personal balance (DOPA-S-03). Collections
   pay 0 shards. Two of the four lanes the design (and this eval's premise) name as
   rebirth income pay a currency rebirth cannot spend. The feel failure is concrete: kill
   the day-7 Herald, watch "+3 shards" materialize center-stage, open the rebirth panel —
   balance unchanged. **Route boss payouts (or half of them) through
   `ShardEconomy.addShards`, or rename the physical item's presentation so it never reads
   as rebirth currency.**
2. **The Vitae Shard dominates rebirth from n=1.** The altar shop sells +1 permanent
   Leben for a **flat 12 personal shards** (`ShardEconomy.OFFERS`), no side effects.
   Rebirth #2+ costs 13/20/33 **plus** a full skill+tree+points wipe **plus** a permanent
   `1.15^n` level-cost penalty — strictly worse than vitae on every axis. Rational play is
   "rebirth once at 8, buy vitae forever"; the 1.6 growth curve prices a product nobody
   should buy twice. Note also lives start at 5 with `MAX_HEARTS 7` (rebirth refused at
   cap), so rebirth demand only exists after deaths — it's a recovery loop, not an
   infinite prestige ladder. **Fix (exact): `costGrowth 1.6 → 1.3` (8, 10, 14, 18, 23),
   `levelCostMultiplierPerRebirth 1.15 → 1.0`, and raise the vitae shard 12 → 20 so
   rebirth is always the budget heart with the reset as its price.** Better: give each
   rebirth a small keepsake (+1 kept tree node, or a cosmetic rebirth aura tier) so the
   reset reads as prestige, not punishment — a *penalty* per prestige inverts the genre's
   dopamine contract.

---

## 5. Heart theft

**Drama: excellent.** Boss-style titles for killer and victim, a *named* global announce
(the one sanctioned anonymity breach), deep bell + `theft.steal` sting, global 0.35/16t
shake, purple heart-burst at the corpse. Kills feel like events. Refusals are quiet
(log-only) — correct; no ceremony for a non-steal.

**Safeguards: mostly tight, one hole.**
- Floor 1 (theft can never ghost anyone) ✓; floor/cooldown verdicts also freeze the
  victim's normal death loss (no farming someone into loss even without a steal) ✓.
- Pair cooldown 30 min, both directions, persisted ✓.
- No theft pre-event / in event dimensions / ghosts / spectators / active contract pair ✓.
- **The hole: the cooldown is per-PAIR only.** A geared killer can take 1 heart from
  *each* teammate per 30 min — on a 6-player server that's −5 hearts across the roster in
  minutes, repeatable every half hour. The floor stops ghosting-by-PvP, but a roster
  ground to 1 Leben each then loses players to any PvE death (0 → ban). That is the grief
  spiral. **Add a per-killer global cap: max 1 steal per 45 min or 2/day
  (`heartTheft.killerCooldownMinutes: 45`).**
- Lesser feel bug: a killer at `MAX_HEARTS` still takes the victim's heart, records the
  cooldown and plays the full steal ceremony while gaining nothing (`LifecycleEvents`) —
  the transfer becomes a sink wearing a celebration. Freeze the loss (treat like
  `NO_STEAL_FLOOR`) or at least skip the ceremony.

---

## 6. The first 30 minutes (limbo → intro → day-1 island)

Beat-by-beat with the shipped numbers:

| Time | Beat | Feedback |
|---|---|---|
| pre-event | Limbo ghost ship | Atmosphere only — XP gated (`preEvent`), no quests, no theft. Zero reward feedback for as long as admins hold; **the only >10 min dead stretch, and it's deliberate/admin-controlled** |
| t=0–8 s | Ship keels, submerge, portal-glitch to black | Spectacle |
| ~0–4 min | IntroSequence: eclipse ramp (5 s) → fusion flight (45 s) → vortex → lightning (30–60 s) → reveal (15 s) → sunrise (10 s); logbook hint +15 s | Spectacle; APPROACH re-nudge at 60 s prevents stalls |
| ~min 5 | Sidebar day-1 mains + 3 personal quests visible | First goals |
| ~min 6–9 | Craft stone pickaxe → quest ceremony (action bar + chime + 250 XP) → **LEVEL 1** (glyph + sting + quasar burst; L1 = 59 XP) | Double beat, lands great |
| ~min 8–14 | Timber T1 (40 logs): card + unlock sting + chat; team hits 128 logs → main-goal banner + 300 XP each | 2 beats |
| ~min 10–20 | Touch altar → 300 XP + 2 physical shards + materialize ceremony + action-bar receipt; **LEVEL 2** (~345 cum) lands for most here | Hero moment |
| ~min 15–30 | Cobble T1 (50), coal T1 (25), iron T1 (15) as mining starts; descend-Y-16 side (+150); scout side 32 chunks (+150); proc toasts + XP bar tick continuously | Steady drip |

**Verdict: no dead stretch >10 min after landing** — a quest-following player gets a
discrete celebration every 3–7 minutes for the whole first session, with the XP bar and
proc toasts as connective tissue. The two structural quiet zones are (a) pre-event limbo
(by design) and (b) the *leveling lane specifically* from ~minute 40 (L2) to ~minute
90–120 (L3) under the shipped curve — collections T2s and the quest ladder pad it, but
§1.3's `baseCost 90` puts a third level-up back inside hour 1, which is the single
highest-leverage change in this document.

Also flagged for the first session: award XP claims use source `"award"` which is not
`XpGates`-exempt — a claim while standing in limbo/minigame silently burns the XP after
the durable claim record is written (DOPA-S-04). Add `"award"` to the exemption set.

---

## Tuning changes, priority order (exact numbers)

1. **Curve:** `skills.json curve.baseCost 150 → 90` (keep 1.55). First hour = 3 levels
   (C(3)=581), day 1 = L5, day 14 = L14–15. Retune milestones `{10,25,40} → {7,12,18}`.
2. **Rebirth vs vitae:** `rebirth.json costGrowth 1.6 → 1.3`,
   `levelCostMultiplierPerRebirth 1.15 → 1.0`; vitae shard shop price `12 → 20`; add a
   per-rebirth keepsake (+1 kept tree node or cosmetic aura).
3. **Boss shards:** route Herald/Rift/Tyrant payouts (3/2/3–8) through
   `ShardEconomy.addShards` (personal) — or split 50/50 physical/personal — so the
   advertised rebirth lanes fund `8·1.6^n`.
4. **Quest UI:** add `rewardXp`/`rewardShards` to `S2CQuestStatePayload` and render
   "◆N · +XP" chips on sidebar/handbook quest rows.
5. **Toast lanes:** one shared bottom-toast queue (or fixed lanes 59/82/104) for
   proc/shard/collection cards.
6. **Contracts:** `contracts.json autoDaily false → true` (25 % real / 5 % prank is
   already tuned) — restores a whole drama+shard lane that is currently dead.
7. **Heart theft:** add `killerCooldownMinutes: 45` (global per-killer), and freeze the
   victim's loss when the killer is at `MAX_HEARTS`.
8. **Day 1 quests:** demote the two TEAM_ALL mains to TEAM_TOTAL/each_player;
   `p_swimmer`/`p_leaper` `minDay 2`.
9. **Collections:** `dailyCreditCap 1500` on cobblestone; move one +1 SP to a T2/T3 on
   coal and timber.

## Verification note

Read-only review: static analysis of the shipped Java defaults and `run/config` JSON, no
Gradle/git/code changes. Curve values recomputed from `SkillCurve` closed form
(`C(L)=baseCost·L^(exp+1)/(exp+1)`); anchors match the shipped `_doc` (C(5)=3564,
C(7)=8405, C(12)≈33 225). Cross-checked against `EVAL-DOPA-S.md` where scopes overlap.
