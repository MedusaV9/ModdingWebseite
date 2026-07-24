# FINAL-DOPA-FABLE — Micro-Reward Cadence Evaluation (final wave)

**Evaluator:** DOPA-FABLE · **Question:** is there a satisfying hit every 30–90 s of normal play?
**Method:** static read of the shipped reward stack (`skills/SkillConfig` + `SkillCurve` + `SkillTreeConfig`, `progression/goals/GoalConfig` + `QuestEngine`, `worldgen/ore/OreConfig` + `VeinTracker`, `drama/*`, `client/skills/*`, `client/hud/Sidebar*`, `client/rewards/RewardMaterializeOverlay`, `UiSounds`/`EclipseSounds`/`sounds.json`) mapped onto a typical **day-2 hour** (morning goal check → branch mine → nether trip → smelt → dusk).

**Verdict: STRONG while mining and fighting, THIN while traveling and building, INVERTED at the very top of the ladder.** The W4-FEEL layer (vein feel, XP strip motion, goal stamps, level glyphs) gives active play a genuinely well-spaced hit cadence. The two weak spots are structural, not cosmetic: (a) whole activity classes (overland travel, base work) fall out of the 30–90 s band entirely, and (b) the feedback hierarchy sags exactly where it should peak — skill milestones and boss deaths celebrate *less* than a cleared iron vein.

---

## 1. The day-2 hour, minute-mapped

Assumptions: player is skill L5–L9 (`SkillCurve` L5–L9 cost 141–323 XP each; curve doc anchors ~660 XP/h average, a focused mining hour earns 800–1200), owns `T1`+`T2` (points = level, `handleLevelUps` grants 1/level; T1+T2 cost 3). Day-2 goals from `GoalConfig`: mains `d02_burning_door` (enter Nether), `d02_gold_rush` (team smelts 24 gold), `d02_altar_1` (altar level 1); sides pest control ×10 / 12 iron ore / 64 placed blocks; 3 personal quests (`personalPerDay = 3`).

| Cadence band | Beats that actually land there | Source |
|---|---|---|
| **1–5 s** (micro) | XP strip pulse + leading spark on every whole XP grant (stone 0.5/blk with remainder carry → pulse every ~2 blocks; ore 2–12) | `SkillXpBarLayer` (12t white pulse), `SkillConfig.xp.mine` |
| **30–90 s** (the DOPAMIN band) | vein reveal actionbar → vein-clear two-note chime + "Vein cleared ×7" toast (iron `cellP 0.30 × band 1.25` ⇒ ~37 % of 16³ cells carry a vein; a branch-miner hits one every 2–6 min); kill-confirm chime per Eclipse-mob kill; **at night only:** horizon lightning every 600–1800 t (30–90 s — the one ambient beat tuned exactly to this band) | `MiningFeelService`, `VeinTracker`, `KillConfirmService`, `HorizonLightning` |
| **2–10 min** | goal stamps (≤ 9/player/day: 3 mains + 3 sides + 3 personals; pitch-salted `ui.goal_stamp` + sidebar sweep + TAB checkmark draw-on + actionbar; MAIN adds amethyst chime 1.2 + global `STYLE_GOAL` announcement); first-ore fanfares (day 2 still has gold/redstone/lapis + quartz/nether-gold firsts: `UI_UNLOCK_STING` + toast); reward materialization for shard/item goals (`d02_altar_1` = 350 XP + 1 shard → floating-stack overlay + absorb flash) | `SidebarPanel.updateGoalSweeps`, `QuestEngine.feedback`, `MiningFeelService`, `RewardMaterializeOverlay` |
| **10–25 min** | level-up: world-audible `skill.levelup` + center-screen glitch glyph + XP-strip specular sweep + quasar burst at feet (L5–L9 at day-2 income) | `SkillService.handleLevelUps`, `LevelUpOverlay`, `SkillXpBarLayer` |
| **~1/hour** | chance procs: T2 double-ore at 2 % (+1 % with S3, a late luxury) over ~60–100 ore blocks/h ⇒ **1–2 procs/hour**; each is the full trio (chime + toast + colored sparkle burst + chat line) | `SkillPerks`, `SkillTreeConfig` (T2 0.02, T6 0.01, U2 0.02, U4 0.03, T5 0.05), `OreProcFxClient` |
| **1/day** | dawn ceremony (5 beats spread over ~10 s: sun pulse → triple toll → day announce → goals reveal → awards roulette); altar level (`STYLE_UNLOCK` announce + unlock sting); advancements (50 XP default table) | `DawnCeremony`, `AnnouncementService`, `AdvancementXpBridge` |

**Per-activity frequency verdict:**

| Activity | 30–90 s hit present? | Notes |
|---|---|---|
| Branch mining / caving | **YES — best-in-mod** | pulse + vein pair + fanfare + level cadence stack cleanly; vein reveal (silent) → clear (two-note) is a textbook anticipation→payoff loop |
| Combat | **YES** | kill XP 5–20/mob + private kill-confirm chime + hit-stop punch on heavies (`HitStopService`) |
| Overland travel / exploration | **NO (daytime)** | `exploreChunk` 5 XP fires every ~10–30 s of movement but is a silent 2-px pulse only; `visitNewBiome` 40 XP likewise unvoiced; at night horizon lightning alone carries the band |
| Base building / smelting | **THIN (acceptable)** | craft 0.5 / smelt 1 XP pulses; placed blocks earn nothing (correct anti-abuse); hearth aura heart every 30 s of held circle is deliberately whisper-quiet (Quiet-Eclipse rest moment) |
| Mid-day goal lull | **PARTIAL** | day-2 mains front-load (Nether entry completes in the first minutes); stamps cluster at day edges, awards at dawn — the mid-day stretch leans entirely on mining/leveling |

---

## 2. FREQUENCY audit

- **XP curve is well-shaped for the event window.** `SkillCurve` (base 20, exp 1.3): L1 = 9 XP, L2 = 34, L5 = 141, L9 = 323, L12 cum = 2 639 (the documented ~4 h anchor). Early levels land minutes apart on day 1, stretching to ~45 min by L12 — fast-then-slow, never a dead first session.
- **Daily caps never bind in honest play** (mine 3000/day vs ~660–1200/h income; kill 3000, explore 2000) — pure anti-grind, invisible to the timeline. Correct.
- **Zero-value guards are right:** planks/sticks craft 0, netherrack 0.25, remainder carry makes fractions honest (`stone: 0.5` pays every 2nd block).
- **Too rare:** the chance-proc layer. 1–2 % base rates mean the entire "jackpot" system (sound + toast + sparkle + chat — the mod's richest single feedback) fires ~once an hour on day 2. It is tuned as a late-game texture but *presented* as a core mining loop.
- **Too clustered:** day-edge pileup. Dawn ceremony + goals reveal + awards + (often) 2–3 quick main completions land in the first ~20 min of a day; `QuestEngine` has no mechanism to spread easy mains, and 3 personals drawn at dawn usually finish early too.
- **Silent earners:** `exploreChunk` (5), `visitNewBiome` (40 + V6's 100), `trade` (10), `breed` (6), altar deposits (2/pt, 3/shard) grant XP with **no sound and no toast** — only the strip pulse. Travel is the biggest 30–90 s hole in the mod.

## 3. ESCALATION audit

Measured intensity ladder (audio × visual × reach), small → large:

| Beat | Feedback | Hierarchy check |
|---|---|---|
| XP tick | strip pulse + spark, silent, private | ✓ correct floor |
| Vein clear | amethyst 1.4 + proc chime + toast | ✓ |
| First-ore | unlock sting + toast | ✓ (but same sting for coal and ancient debris — tier signal wasted) |
| Chance proc | chime + toast + sparkle + chat | ✓ |
| Side/personal goal | proc chime 0.8 + stamp + actionbar (+ materialize) | ✓ |
| MAIN goal | amethyst 1.2 + stamp + **global announcement** | ✓ |
| Level-up | world-audible sting + LEVEL glyph + sweep + quasar burst | ✓ |
| **Skill milestone 10/25/40** | *identical to any other level* + a vanilla advancement toast (`AdvancementXpBridge`) | ✗ **flat** — the three authored milestone levels celebrate exactly like L7 |
| Altar level | `STYLE_UNLOCK` announce + unlock reveal + sting | ✓ |
| **Boss kill (Herald 400 XP / Ferryman 600 XP)** | `KillConfirmService` **deliberately excludes bosses**; Ferryman gets the `FinaleRitual` set piece, but the Herald's death and the killer's personal moment have no bespoke release sting (IDEA-07 #6 is still open) | ✗ **inverted** — a Fog Colossus elite gives its killer a deeper chime than the Herald does |

Multi-level jumps (Warden 150 / Wither 300 / Dragon 500 XP) are handled beautifully — queued glyphs, ≤ 3 carry sweeps arpeggiating 1.0/1.06/1.12, odometer numeral. The escalation problem is confined to the two ✗ rows: the ladder's top rungs are its flattest.

## 4. VARIETY audit

All 63 `sounds.json` events ship exactly **1 file** each (house rule: no new binary assets), so pitch/volume salting is the only anti-monotony tool. Where it exists, it is excellent; where it is missing, the same note repeats verbatim:

| Salted ✓ | Flat ✗ |
|---|---|
| `goalStamp` 0.9 + (phaseSalt % 8)·0.045 — 8-step arpeggio for back-to-back completions | `SkillPerks.sendProcFeedback` hardcodes **0.7F / 1.0F for all 15 proc ids** (double_ore, bonus_ore, vein_clear, smelt_xp, double_loot, bonus_shard, ore_first_*) — one identical chime for every proc semantic |
| level-up carry sweeps 1.0/1.06/1.12 | `SkillService.handleLevelUps` 0.8/1.0 every level; `buyNode` 0.6/1.3 every node |
| hover/slider/typewriter jitter, directional page-turn, `toggleSettle` ON 1.1 / OFF 0.75 | vein-clear amethyst always 1.4 regardless of `scan.total()` (magnitude is right there) |
| kill-confirm regular vs elite (2 fixed variants) | …but within each class every kill is identical |
| | first-ore fanfare: same sting at 1.0 for every ore family |

## 5. ANTICIPATION audit

- **XP strip: exemplary.** Eased count-up, gain pulse, leading spark, level numeral, sweep-then-refill; TAB card shows `level + xpInto/xpFor`. Players always see the next hit coming.
- **Goal progress: good on TAB, adequate ambient.** `SidebarExpanded` draws per-goal progress bars from `QuestEntry.progress/target`; compact sidebar shows aggregate x/y. **Gap:** no "one-away" emphasis — a goal at target−1 looks identical to one at 10 %.
- **Vein: reveal then silence.** First break announces "Iron Ore vein · 7 blocks", last break chimes — but breaks 2…n−1 give nothing. The counter that would build the ramp already exists in `VeinTracker.Scan.present()`.
- **Ore tier hints: built and never wired.** `OreGateApi` ("P4-facing progression seam… for P4 progression UI") has **zero consumers** outside its own package. Iron/gold gate at stage 2, diamond at stage 3 (`ores.json unlockStage`), and nothing in the handbook, sidebar or expansion announcements tells players a new ore tier just unlocked or is one expansion away. Pure invisible anticipation fuel.
- **Unspent skill point: invisible outside the tree.** `S2CSkillStatePayload` syncs `unspentPoints`, but `InventorySkillButton` draws a plain ✦ with no badge, and the level-up actionbar line ("Skill level %s reached!") never mentions the point. The earn→spend two-beat chain breaks at the handoff.

---

## 6. Concrete gaps (ranked)

1. **Travel/exploration dead zone** — explore/biome/trade/breed XP is completely unvoiced; daytime overland play has no 30–90 s beat at all.
2. **Top-of-ladder inversion** — no boss-down release sting (Herald especially); milestone levels 10/25/40 celebrate like ordinary levels.
3. **One chime, 15 procs** — `sendProcFeedback`'s fixed 0.7/1.0 wastes the mod's best feedback moment and makes rare procs sound like routine vein-clears.
4. **Proc layer effectively absent on day 2** — 1–2 % rates × early ore volume ≈ 1/hour; the sparkle/jackpot system barely exists when players form their impression of mining.
5. **Vein mid-progress silent**; clear-chime pitch ignores vein size.
6. **`OreGateApi` unconsumed** — ore-tier anticipation (the strongest "keep digging" hook the worldgen offers) is never surfaced.
7. **Unspent-point handoff broken** (no badge, no actionbar mention).
8. **Day-edge clustering** — dawn stacks 5 beats in 10 s while mid-day has none to spare; no "one-away" goal emphasis to build the pre-stamp ramp.

## 7. Five highest-impact improvements (all S effort, exact hooks)

1. **Pitch-family the proc chime** — `SkillPerks.sendProcFeedback(player, procId, magnitude)`: replace the hardcoded `0.7F, 1.0F` with a small `switch` on proc-id family — `ore_first_*` pitched by ore tier (coal 0.9 → debris 1.3), `vein_clear` at `1.0 + Math.min(0.3F, magnitude * 0.02F)` (magnitude is already the vein size), `double_*` 1.1, `bonus_*` 1.15, volume nudged by magnitude. One method body, both args already at the call site, zero new assets. Fixes gaps 3 + half of 5 at the exact layer the 30–90 s band lives in.
2. **Vein countdown ticks** — `MiningFeelService.onNaturalOreMined`, between the `present == total` reveal and the `present == 1` clear: actionbar `"Iron Ore vein · 3/7"` (new lang key next to `message.eclipse.vein.reveal`) + a soft `EclipseSounds.UI_TYPEWRITER` blip whose pitch rises as `present` shrinks. All data is in the existing `scan`; ~10 lines. Turns every multi-block vein into an anticipation ramp instead of reveal→silence→payoff.
3. **Boss-down release sting** (closes IDEA-07 #6) — sounds.json alias `boss.down` → `event.storm_burst` re-pitched 0.6 + one `EclipseSounds` W-block entry; broadcast via `playNotifySound` to all players from the Herald's death seam and `FinaleRitual.beginVictory` (Ferryman), with a brighter private layer (`UI_UNLOCK_STING` 0.7) for the killer — mirroring the `KillConfirmService` private/public split it deliberately left empty. Fixes the ladder inversion with no new oggs.
4. **Milestone-level celebration variant** — `LevelUpOverlay.start(level)`: when `level` ∈ {10, 25, 40} (mirror of `AdvancementXpBridge.MILESTONE_LEVELS`), layer `UiSounds.unlockSting()` over `UiSounds.levelUp()` and extend `HOLD_TICKS` for that celebration; optionally have `SkillXpBarLayer` queue a second sweep. ~10 client-only lines; makes the authored milestones read as milestones.
5. **Unspent-point beacon** — `InventorySkillButton.Widget`: draw a 3×3 accent dot (slow `EclipseUiTheme.ACCENT` pulse, `reducedFx`-gated) when `ClientStateCache` unspent points > 0 (already synced in `S2CSkillStatePayload`), and extend `message.eclipse.skill.levelup` to "Skill level %s reached — a skill point awaits." Every level-up becomes a two-beat chain (earn → spend), roughly doubling encounters with the node-buy feedback (`ui.skill_buy` + cascade whoosh) that currently only tree-regulars ever hear.

*Honorable mention (S+, not top-5 only because it needs one new client ticker): a faint explore-chunk UI blip — `EclipseSignals.onChunkExplored` is already the seam; even a 0.3-volume `UI_HOVER` re-pitch at ≥ 20 s throttle would put overland travel back inside the 30–90 s band.*

---

## 8. Bottom line

The mining loop is a model dopamine lane — micro (pulse), meso (vein pair, fanfare), macro (level glyph) all present, with real anticipation mechanics. Spend the final wave's polish budget on (a) voicing the silent earners, (b) un-flattening the top of the ladder, and (c) the five S-effort hooks above — none of which require new assets, new payloads, or touching frozen seams.
