# FINAL-DOPA-SOL — Reward Math / Cadence Evaluation

**Evaluator:** DOPA-SOL · **Scope:** shipped runtime configs and their consuming code; static/read-only audit, no Gradle.

## Executive verdict

**FAIL as shipped.** The skill curve itself lands near the intended anchor (**L12 at 4 h** at 660 XP/h), T2 proc feedback is not throughput-throttled, and contract wrong-kill math is severe but bounded. However:

1. **UNREACHABLE — altar progression deadlocks before L1.** Vanilla mineral features are removed, while iron/gold/diamond are generated only in annuli unlocked by milestones that require those same ores.
2. **UNREACHABLE — Altar L3 by day 5.** It needs 24 diamonds gated behind L3 itself plus 8 emerald blocks (72 emeralds) with no Eclipse emerald ore.
3. **DEGENERATE — banked shards spend twice.** One physical shard credits both a spendable personal balance and a separately spendable pool.
4. **DEGENERATE — wand L3 takes 25–55 successful casts, minutes to <1 h, not day-long play.**
5. **SPEC FAIL — contract success/target multipliers are 1.5×/0.75×, not the requested 2.5×/0.5×; automatic contracts are disabled.**
6. **UNREACHABLE/UNRELIABLE bestiary rows:** Deckhand (only 8 in one finale vs 10 kills), The Other (only 45.77% of events generate 10), Rift Warden (no production caller of `summonAt`), plus every stage-3/4 family behind the altar deadlock.

---

## 1. Skill XP curve and four-hour timing

### Curve

`SkillCurve` uses the runtime `skills.json` values:

```text
C(L) = round(20 × L^(1.3 + 1) / (1.3 + 1))
     = round(20 × L^2.3 / 2.3)
```

`C(L)` is lifetime XP required to hold level L. The relevant exact rounded points are:

| Level | Cumulative XP | Increment from prior level |
|---:|---:|---:|
| 10 | 1,735 | 373 |
| 11 | 2,160 | 425 |
| 12 | 2,639 | 479 |
| 13 | 3,172 | 533 |
| 14 | 3,762 | 590 |
| 15 | 4,409 | 647 |

### Realistic 60/20/20 rate model

The assumptions below are deliberately explicit so the estimate can be replaced with telemetry:

- **Mining focused hour: 650 XP/h.** Example: 360 stone/deepslate × 0.5 + 100 coal × 3 + 85 copper × 2 = 650 XP over 545 blocks (9.1 blocks/min including movement).
- **Combat focused hour: 250 XP/h.** About 28 ordinary hostiles/h × roughly 9 XP/kill.
- **Quest focused hour: 1,100 XP/h.** Days 1–5 contain 1,250–1,390 authored goal XP, plus about 401–416 expected XP from three weighted personal draws. Using only 1,100/h for the 48-minute quest slice assumes roughly half of one full slate completes in that slice.

Therefore:

```text
R = 0.60(650) + 0.20(250) + 0.20(1,100)
  = 390 + 50 + 220
  = 660 XP/h

4 h × 660 = 2,640 XP ≈ C(12) = 2,639
```

| Target | XP | Time at 600 XP/h | Time at 660 XP/h | Time at 800 XP/h |
|---:|---:|---:|---:|---:|
| L10 | 1,735 | 2.89 h | 2.63 h | 2.17 h |
| L12 | 2,639 | 4.40 h | **4.00 h** | 3.30 h |
| L15 | 4,409 | 7.35 h | **6.68 h** | 5.51 h |

Reality check: completing a whole typical day while doing the mining/combat actions pays about 1,719 quest XP (1,308 average authored daily XP + about 411 personal XP). Adding 2.4 × 650 mining and 0.8 × 250 combat gives about **3,479 XP**, or **L13 after four hours**. The goal payouts overlap the actions that complete them, so this is the likely diligent-player case.

**Verdict:** the useful target is **L12–13 in ~4 h**. “L10–15 in ~4 h” is too broad: L10 arrives around hour 2–3, and L15 is not a normal four-hour result. No curve change is needed if L12 was the actual anchor; change the specification to L12–13. This cadence is conditional on fixing the ore deadlock, because the shipped world cannot supply the assumed mining mix.

---

## 2. T2 double-ore proc rate and toast throughput

`skilltree.json` gives T2 Fortune's Echo `double_ore_drop_chance = 0.02`. S3 can add one percentage point later; the T2-only calculation is:

```text
E[procs/h] = natural ore blocks/h × 0.02
```

| Natural ore blocks in a focused mining hour | Expected T2 procs/h | Mean gap | P(no proc in that hour) |
|---:|---:|---:|---:|
| 60 | 1.20 | 50.0 min | 29.8% |
| 100 | 2.00 | 30.0 min | 13.3% |
| 120 | **2.40** | **25.0 min** | **8.9%** |

Across a whole mixed-play hour with mining at 60%, the 120-ore focused assumption becomes 72 ore/h:

```text
72 × 0.02 = 1.44 procs per mixed hour
P(0) = 0.98^72 = 23.35%
```

`SkillProcToast` displays one entry for 49 ticks = 2.45 s, a sustained rate of **24.49 toasts/min**, and queues four. T2 generates only 0.02–0.04 toasts/min, hundreds of times below that capacity. Therefore the toast throttle does **not** hide T2 procs in ordinary mining.

There are two real loss edges, but neither explains low observed T2 frequency:

- the shared client cache retains only the latest payload in one client tick, so two different procs arriving in the same tick collapse to one toast;
- a burst that fills the four-entry queue drops the oldest entry.

Sound, sparkle and optional chat are sent independently, so even those rare toast losses do not suppress the proc itself.

**Verdict:** rate is rare but mathematically honest; no throttle bug. If T2 is intended as a frequent “jackpot” beat, raise it to 3–4%. Otherwise keep 2% and communicate that a no-proc hour is still 9–30% likely depending on ore volume.

---

## 3. Goals, shards, and Altar L2–3 by day 5

### Authored per-player goal income

Team-scoped goals credit every eligible known player, not one team pot. The table is the maximum authored slate per credited player:

| Day | Daily-goal skill XP | Expected 3-personal XP* | Direct balance shards | Physical shards |
|---:|---:|---:|---:|---:|
| 1 | 1,250 | 401 | 0 | 2 |
| 2 | 1,290 | 406 | 1 | 0 |
| 3 | 1,390 | 416 | 1 | 0 |
| 4 | 1,270 | 416 | 1 | 0 |
| 5 | 1,340 | 416 | 1 | 0 |
| **Total** | **6,540** | **≈2,056** | **4** | **2** |

\*Weighted eligible-pool expectation; lifetime no-repeat shifts the exact draw slightly.

If every goal were completable, the five-day quest-only total is about **8,596 XP/player = L20**, before action XP.

For a team of `N`:

- Day-1 `d01_touch_altar` grants **2 physical umbral shards to each player**.
- Banking them produces personal `+2` for each player **and pool `+2N`**.
- Days 2–5 fixed shard rewards add `+4` directly to each personal balance and do not touch the pool.
- Personal quests add about `+1.24` expected direct shards/player through day 5.

Thus the intended no-spend position is approximately:

```text
personal per player = 2 banked + 4 fixed + 1.24 expected = 7.24
team pool            = 2N
four-player example  = about 7.24 personal each, pool 8
```

This does **not** finance altar levels: milestones consume ordinary items, not shards, and there is no shard→milestone-resource exchange.

### Actual altar flow: hard circular gates

| Milestone | Cost | Required resource location | Result |
|---:|---|---|---|
| L1 | 48 iron ingots + 32 coal | Iron has `unlockStage: 2`; initial overworld exposes bands 0–1 only | **UNREACHABLE normally** |
| L2 | 32 gold ingots + 16 amethyst | Overworld gold and Nether gold are both `unlockStage: 2`; stage 2 is triggered by completing milestone 2 | **UNREACHABLE / circular** |
| L3 | 24 diamonds + 8 emerald blocks | Diamond is `unlockStage: 3`; stage 3 is triggered by milestone 3. No Eclipse emerald ore exists. | **UNREACHABLE / circular** |

The key implementation facts are:

1. `BiomeFeatureFilter` removes all vanilla iron, gold, diamond, emerald, quartz and Nether-gold features.
2. `OreField` rejects an ore whenever `annulusBand < unlockStage`.
3. The fresh overworld starts with radii `[96, 150, ...]`, so only bands 0 and 1 exist.
4. Overworld stage 2 is triggered by `milestone:2`; stage 3 by `milestone:3`.
5. Nether stage 1 opens on day 2, but every configured Nether ore uses `unlockStage: 2`; the second Nether annulus does not open until day 10.

Structure loot can theoretically leak small quantities, but that is neither guaranteed nor enough to make 48 iron, 32 gold, 24 diamonds and 72 emeralds a normal day-5 path. The deadlock also makes iron-dependent day-3/4/5 goals and their shard payouts unavailable.

**Verdict:** a normal team cannot reach L2 or L3 by day 5; it cannot reliably reach **L1**.

### Concrete fix

Resources must be available one stage before the milestone that consumes them:

- iron: `unlockStage 0` (available across the starting disc);
- overworld gold: `unlockStage 1`;
- Nether quartz and Nether gold: `unlockStage 1` (available when the Nether opens on day 2);
- diamond: `unlockStage 2`;
- add emerald ore at `unlockStage 2`, or replace 8 emerald blocks with **8 emeralds** and guarantee a pre-L3 trading route.

After that change, 48 iron + 32 gold + 16 amethyst are reasonable pooled team costs by day 2–3, and 24 diamonds are reasonable by day 5 for four players. Seventy-two emeralds are not.

### Shard double-spend degeneracy

`ShardEconomy.deposit` adds every banked physical shard to both the personal spendable balance and the team spendable pool. Personal purchases only debit personal; pooled purchases only debit pool. Therefore one banked shard can buy **one unit of personal value and one unit of pooled value**.

**Fix:** bank physical shards into the pool only, while tracking a non-spendable personal contribution counter; or make pooled spending debit contributors' personal balances proportionally. Direct personal goal rewards may remain personal-only.

---

## 4. Wand XP curve

Default wand XP is `round(charge cost × 0.6)` per successful cast, with an additional 8 XP per kill while holding the owned wand. Costs to level are 120 (L1→L2) and 260 (L2→L3); leftover XP carries.

| Path | L1 spell | XP/cast | Casts to L2 | Total casts to L3 using L1 only | Total casts to L3 using unlocked L2 spell |
|---|---:|---:|---:|---:|---:|
| Riss | 15 charge | 9 | 14 | 43 | **25** (then 11 × 40-charge casts) |
| Glut | 12 charge | 7 | 18 | 55 | **28** (then 10 × 45-charge casts) |
| Stern | 12 charge | 7 | 18 | 55 | **28** (then 10 × 45-charge casts) |

At one successful cast/minute, L2 takes 14–18 min and L3 takes **25–55 min**. Even charge-limited continuous daytime casting is roughly a five-minute lower bound: the 100-charge pool plus 2 charge/s held regeneration replaces about 550–566 charge for the efficient L3 route. Night regeneration halves that bound. The +8 kill bonus only accelerates it.

**Verdict: DEGENERATE for a day-long progression target.** It is reasonable only if L2/L3 are intended to unlock in the wand's first hour.

**Concrete fix:** increase early costs by roughly 5×, e.g. `levelCosts: [600, 1800, 3600, 6000]`. That puts the efficient L3 path around 140 successful casts (about 2.3 h at one cast/min, 4–5 h at a more normal one cast/two minutes). Alternatively add a per-power XP cooldown so charge dumping cannot become the optimal training loop.

---

## 5. Contract reward/penalty magnitude

Baseline comparison uses the curve's 660 XP/h active rate and the fixed day-2–5 goal cadence of one direct shard/day/player.

| Outcome | Shipped package | Baseline value / magnitude | Verdict |
|---|---|---|---|
| Success: hunter | 1.5× skills, +10% damage, +1 temp heart, 12 shards, 400 base XP | The multiplier is installed before the XP grant, so 400 becomes at least **600 applied XP** = 54.5 min baseline; 12 shards = 3× the entire fixed D2–5 shard payout | Large package, but multipliers are not “massive” |
| Success: target | 0.75× skills, −15% damage | Loses 25% XP and 15% damage for remainder of day | Noticeable, not massive; missing spec's −1 heart/hunger/grave penalties |
| Expiry: survivor | 250 XP + 4 shards | 22.7 min baseline; 4 shards = all fixed D2–5 shard rewards | Fair and clearly below success |
| Wrong killer | 0.5× skills, −20% damage, next award void | Half progression plus meaningful combat loss | **Massive but bounded** |
| Wrong victim | −1 temp heart, +35% damage only vs murderer | Sharp directed comeback; health clamp prevents run-ending state | **Massive but fair** |

The design specification says success should grant hunter **2.5×** skill XP and inflict **0.5×** on the target. Runtime config ships **1.5× / 0.75×**. It also leaves `hunterGlobalBuffId` empty, so the specified ore/shard favor does not happen. `autoDaily` is `false`, meaning no contract occurs in the normal 14-day cadence unless an operator starts one.

There is also an inconsistent stacking rule:

- damage rows multiply together;
- heart rows add together;
- skill rows are stored as multiple ledger entries but each grant directly **overwrites** the one `SkillsApi` multiplier, so the most recent skill effect wins rather than stacking.

**Verdict:** wrong-kill justice meets “massive but fair”; success/target does not meet the written spec, and the feature has zero automatic cadence.

**Concrete fix:** either (a) ship the spec values (`hunterSkillsMul: 2.5`, `targetSkillsMul: 0.5`, target −1 heart, per-player drop favor) and enable the intended daily roll, or (b) explicitly revise the spec to “strong but not massive” and retain 1.5×/0.75×. In both cases, recompute one effective skill multiplier from all active ledger rows on every grant/expiry, with a documented composition rule and clamp, instead of last-write-wins.

---

## 6. Bestiary T3 reachability over 14 days

T2/T3 defaults are 3/10 kills or sightings. Herald, Ferryman, Rift Warden and Fog Tyrant override both thresholds to one kill. Counts are **per player**, so limited world spawns are even less reachable for a team than the world-total bounds below.

| Entry / family | Actual availability and rate | T3 verdict |
|---|---|---|
| Deckhand | Exactly 8 benches; only hostile/killable during Ferryman P2 on day 14 | **UNREACHABLE:** one player can kill at most 8 in the single normal finale |
| Drift Lantern | Limbo population tops up toward 8 by 2 every 5 s; killable | Reachable (though farming ambient mobs is thematically odd) |
| Gazer | One per ~4 players at night from day 3; spawns/relocates 20–40 blocks away, but sightings require ≤16 blocks and count only once/60 s; direct stare despawns it after 2 s | **UNRELIABLE/DEGENERATE:** requires at least 9 minutes of close pursuit, not natural observation |
| The Other | 2–3 per Pale Night; guaranteed day 4 and 12 plus seven 25% rolls | **UNREACHABLE in 54.23% of events:** E = 9.375 world spawns; P(spawns ≥10) = 45.77% |
| Umbral Stalker | Nights from day 5; cap ≥4, doubled on days 6/10; packs refill every 5 s when killed | Reachable |
| Fog Revenant | Active stage-3 fog sites, night, day ≥6; global cap `2 + online/4`, refill every 5 s | Spawn rate supports T3, but **unavailable as shipped** behind altar L3 |
| Storm Hound | Active stage-3 fog sites; packs 2–3, cap 6/site, refill every 5 s | Spawn rate supports T3, but **unavailable as shipped** behind altar L3 |
| Herald | Set piece; boss override makes first kill T3 | Reachable if the day-7 fight is completed |
| Glitched Husk | `GlitchSpawnService`: night from day 3, 6 samples × 35% every 5 s, shared cap 12; second spawner begins day 8 | Reachable; handbook day-8 intro disagrees with actual day-3 spawn |
| Glitched Hound | Same shared cap; equal random choice in `GlitchSpawnService`, 35% weight in second spawner | Reachable with active hunting |
| Glitched Tick | Same shared cap; second spawner creates groups of three | Reachable |
| Fog Colossus | Active stage-3 fog site, night, day ≥9; global cap 1 but refills every 5 s after death | Mechanically farmable to 10, but **unavailable as shipped** behind altar L3 |
| Eclipse Cultist | Stage-3 dungeon spawners can replenish; Rift Warden only summons two | Reachable with dungeon access, but **unavailable as shipped**; two boss adds alone cannot reach 10 |
| Pale Sentinel | Day ≥10, night, pale-garden biome only; biome starts around r >300 (stage-4 terrain), cap 2 and refill every 5 s | Rate supports T3, but **unavailable as shipped** behind altar progression |
| Rift Warden | Boss threshold = 1, intended for Collapsed Vault | **UNREACHABLE:** `RiftWardenEntity.summonAt` has no production caller; Collapsed Vault contains no Warden hook |
| Wizard Orin | Unique stage-3 observatory NPC; sightings once/60 s | Conditional on stage 3; then trivially reachable by standing nearby for ≥9 min |
| Fog Tyrant | One proximity-triggered boss at an active stage-3 fog lair; boss threshold = 1 | Correct threshold, but **unavailable as shipped** behind altar L3 |
| Ferryman | Day-14 set piece; boss threshold = 1 | Reachable |

For The Other, the exact schedule calculation is:

```text
Pale events = 2 guaranteed + Binomial(7, 0.25)
E[events]   = 2 + 7(0.25) = 3.75
E[spawns]   = 3.75 × mean(2,3) = 9.375
P(spawns ≥ 10) = 0.4577217102
```

### Concrete bestiary fixes

1. Fix the altar/ore stage deadlock first; this restores fog, dungeon, sentinel, Orin and fog-boss availability.
2. Add explicit per-id thresholds: Deckhand T3 = **8**; The Other T3 = **6** (current schedule then reaches it in 89.99% of worlds).
3. Give Gazer a per-id sighting range of **40 blocks** or a 20–30 s sighting cooldown. Its current spawn range deliberately sits outside the global 16-block observation scanner.
4. Wire the Collapsed Vault boss-room trigger to `RiftWardenEntity.summonAt`.
5. Align glitched-mob documentation and gates: either move `GlitchConfig.minDay` to 8 or change the handbook intro to day 3.

---

## Ranked release blockers

1. **P0:** break the milestone/ore circular dependencies (iron 0, gold/Nether ores 1, diamond/emerald 2).
2. **P0:** wire Rift Warden's production summon.
3. **P1:** fix Deckhand and The Other per-id T3 thresholds; make Gazer sighting geometry agree with its spawn geometry.
4. **P1:** increase wand level costs about 5× or explicitly redefine L3 as a first-hour unlock.
5. **P1:** choose whether contracts follow the 2.5×/0.5× spec; enable automatic scheduling if they are part of normal cadence.
6. **P1:** remove shard double-spending or document it as an intentional 2× contribution subsidy.
