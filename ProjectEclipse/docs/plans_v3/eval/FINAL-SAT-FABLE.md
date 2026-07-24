# FINAL-SAT-FABLE — Satisfaction Evaluation (final wave)

**Evaluator:** SAT-FABLE · **Scope:** every player-facing loop must resolve COMPLETE and rewarding — no dead ends (action without feedback), no doubled feedback (two systems firing over each other), correct en+de.
**Method:** end-to-end code-path reads (read-only, no gradle). All timings below are server/game ticks relative to the day-rollover tick (T+0).

---

## 1. Loop-by-loop verdicts

| # | Loop | Verdict |
|---|------|---------|
| 1 | Quest complete → reward → feedback (`QuestEngine` → `RewardPayloads` → `RewardMaterializeOverlay`) | **PASS with collisions** (see D2, D6) |
| 2 | Offering → ack → daily winner | **PASS with spoiler** (see D1, D3) |
| 3 | Kill → confirm chime → bestiary progress → tier-up | **PASS** (minor action-bar contention, D6) |
| 4 | Wand cast → cost → effect → XP | **PASS** — cleanest loop in the mod |
| 5 | Contract resolution ceremonies | **PASS with gaps** (D5, D7) |
| 6 | Minigame podium | **PASS** (offline top-3 payout gap, D8) |
| 7 | Awards roulette → podium moment | **PASS with spoiler + join-window gap** (D1, D4) |
| 8 | Revive arc | **PASS with silent-failure gap** (D9) |
| 9 | Day ceremony arc (`DawnCeremony`) | **DESIGN GOOD, EXECUTION COLLIDES** (D1–D3) |

en+de: `en_us.json` and `de_de.json` have **identical key sets (1751/1751)**, zero `%s`-placeholder mismatches, and every loop-facing key checked (quest.*, gui.eclipse.awards.*, gui.eclipse.contract.*, wand.eclipse.msg.*, ritual.eclipse.*, eclipse.minigame.arena.podium.*, announce.eclipse.*) exists in both. i18n is in excellent shape; the only softness is English-only *hardcoded fallbacks* (`ClientBestiaryCache.celebrateTierUp` fallback strings, `AwardService.rewardLine`'s baked bilingual literals are fine).

---

## 2. The rollover overlap analysis (requested focus)

`DawnCeremony` (wired in `DayScheduler.applyDay`, `changed && !quiet`) schedules: T+10 sun pulse, T+20 toll (strikes to ~T+44), T+40 `AnnouncementService.onDayChanged`, T+140 goals caption, **T+200 `AwardService.sendRevealNow`** (roulette). `AwardService.onDayRollover` POST correctly gates its inline send behind `DawnCeremony.isRunning`. On paper the spacing works. In practice three things break it:

**(a) Award/offering rewards materialize at T+0, 10 s BEFORE the roulette reveals the winner.**
`AwardService.resolveDay` runs at rollover **PRE** (T+0) and calls `queueResolvedRewards` → `queueReward` → for online winners `deliverPending(online, false)` — `replay=false`, i.e. the **full-fanfare** `RewardMaterializeOverlay` animation (item descends from guiHeight/3, label glitch-settles, `ui.unlock_sting` at landing). The winner therefore watches "Rewarded with N Umbral Shards" materialize into their hotbar at T+0 — then at T+200 the roulette pretends to build suspense about who won. The offering winner rides the same path (`OfferingService.queueWinnerRewards` → `AwardService.queueReward`). **The reveal is structurally spoiled every single day for every winner.**

**(b) The announcement queue shifts the whole client-side choreography.**
`OfferingService.resolveDay` (PRE, T+0) broadcasts the best-offering announcement (`STYLE_GOAL`) immediately. `AnnouncementOverlay` is a strict FIFO (one typewriter+sweep at a time, sweep = 30+60+20 = 110t). So on any day with ≥1 offering (the common case): offering sweep T+0→T+110 → day card starts ~T+110 (not T+40 as the ceremony assumes) → day-line sweep runs ~T+160→T+270. Consequences: the T+140 goals caption plays over the still-rolling day card, and the **T+200 roulette veil (0.85 alpha, full-screen) slams down mid-day-sweep**, with typewriter tick sounds continuing under the roulette. Queued unlock announcements play even later — under or after the roulette — while their celebratory `unlock_burst` particles fired at payload *arrival* (T+40), disjoint from their own sweeps by 200+ ticks.

**(c) Three systems share the guiHeight/3 anchor with zero cross-coordination.**
`RewardMaterializeOverlay` starts its descent at `guiHeight / 3`; `AnnouncementOverlay`'s day card renders centered at `guiHeight / 3`; `LevelUpOverlay` renders at `guiHeight / 3`. At rollover, a quest-beat completion or the T+0 award materialization (56t live variant) overlaps the day card window (T+40..T+102+). Independently, ANY quest whose reward has items/shards *and* enough skillXp to level up fires `RewardMaterializeOverlay` and `LevelUpOverlay` in the same tick at the same screen position. Both are `registerAboveAll` layers with no mutual exclusion or shared queue.

---

## 3. Concrete defects

| ID | Sev | File(s) | Defect |
|----|-----|---------|--------|
| **D1** | **HIGH** | `awards/AwardService.java` (`queueReward` → `deliverPending(online, false)` at PRE), `offering/OfferingService.java` (`queueWinnerRewards`) | Daily award + offering rewards are delivered with the full live materialization at rollover T+0, spoiling the T+200 roulette reveal and colliding with the dawn toll/sun pulse/day card. Fix direction: hold online winners' delivery until after `sendRevealNow` (or send `replay=true` pre-reveal and celebrate at the roulette's REWARD phase). |
| **D2** | **HIGH** | `client/rewards/RewardMaterializeOverlay.java`, `client/skills/LevelUpOverlay.java`, `client/hud/AnnouncementOverlay.java` (day card) | Three above-all overlays render at the same `guiHeight/3` anchor with no arbitration. Mixed reward (items + skillXp level-up) = two overlays over each other same tick; rollover adds the day card. Needs a shared "center-stage" mutex or offset lanes. |
| **D3** | **MED** | `offering/OfferingService.resolveDay` (announce at PRE), `drama/DawnCeremony.java`, `client/hud/AnnouncementOverlay.java` | The T+0 offering announcement occupies the FIFO announcement slot for 110t, displacing the day card to ~T+110 and pushing the day sweep under the T+200 roulette veil. The ceremony's server-side spacing does not account for client-side queue depth. Move the offering line into the ceremony (e.g. a beat before goals) or into the roulette's `best_offering` card only. |
| **D4** | **MED** | `client/awards/AwardsOverlay.java` (`LATE_JOIN_GRACE_TICKS`), `awards/AwardService.sendRevealNow` (`markRevealSeen`) | A player joining within 100 ticks before the T+200 reveal has the payload suppressed client-side as a "login replay", while the server marks it seen — that day's roulette is never shown to them (no replay at next login either). Their rewards still arrive (calm), but the WHO/ceremony is a permanent dead end for that player+day. |
| **D5** | **MED-HIGH** | `contracts/ContractService.resolveExpired` (`"contract_survived"`), `awards/AwardsState.queue`/`claim` | Offline survivor consolation uses the **non-day-scoped** stable id `contract_survived`. After the first claim the id sits in `deliveredRewardIds` forever, so `queue()` returns false on every later offline survival — the second+ consolation reward is silently swallowed (action → nothing). Every other ledger id is day-scoped (`award:day:cat:uuid`, `offering:day:uuid`, `quest:day:goal`). Should be `"contract_survived:" + day + ":" + uuid`. |
| **D6** | **MED** | `progression/goals/QuestEngine.feedback` (action bar), `client/progression/ClientBestiaryCache.celebrateTierUp` (`setOverlayMessage`) | Both write the single vanilla action-bar line. A kill that simultaneously completes a kill quest and crosses a bestiary tier (e.g. 10th storm-hound kill) overwrites one message with the other — one of the two celebrations is lost, plus sting stacking (`SKILL_PROC`/chime + `unlockSting`). |
| **D7** | **MED** | `contracts/ContractService.resolveVoided` | VOIDED is the only resolution with **no global closure**: SUCCESS/EXPIRED/TABLES broadcast a `STYLE_BOSS` banner, but VOIDED sends only the hunter a private line. Uninvolved players saw the omen and the window flag flip on (`sendStateToAll(true)` reaches everyone) and then it silently flips off — the arc never resolves for them. The dead target never learns a contract existed (arguably intended, but the bystander dead end is not). |
| **D8** | **LOW-MED** | `minigames/ArenaGame.endRound` | Podium payout is `if (winner != null)` — a top-3 player who disconnected before round end silently loses shards/XP and their private placement line (no award-ledger queue fallback, unlike every other reward system in the mod). |
| **D9** | **MED** | `ritual/ReviveRitual.fail` / `succeed` | Failure feedback is a positional `FIRE_EXTINGUISH` at the altar + bossbar vanish; the *reason* goes only to the log. A confirmer who strayed >16 blocks (or whose sigil vanished — checked only at the 3-minute mark!) gets no text, while the `none_banned` abort DOES get an action-bar line. Inconsistent; the lost-sigil case (3 minutes of vigil → quiet fizzle) is the worst felt moment in the arc. |
| **D10** | **LOW** | `client/hud/AnnouncementOverlay.spawnUnlockBurst` | Unlock particle burst fires at payload arrival while its sweep may be queued 100–300 ticks behind — celebration and message are decoupled on busy mornings. |
| **D11** | **LOW** | `client/rewards/RewardMaterializeOverlay.enqueue` (QUEUE_LIMIT=4 drops OLDEST), `client/awards/AwardsOverlay.pollPayload` (M-4 drop-at-full-queue marks handled) | Presentation-only losses under burst conditions (>4 queued grants at login; reveal payload during a full show queue). Acknowledged in comments; acceptable but worth knowing. |
| **D12** | **LOW** | `client/progression/ClientBestiaryCache.celebrateTierUp` | Hardcoded fallback strings are English-only; harmless while the lang keys exist (they do), but a future key rename regresses German silently. |

Verified NON-defects worth recording: `DawnCeremony` **is** wired (`DayScheduler.applyDay` line ~136 — the class-doc's "until the diff lands this class is inert" note is stale); the `AwardService` POST gate + `HANDLED_DAYS` client dedupe correctly prevent double roulette shows on both normal and expansion days (`ExpansionSequence.beginEnd` seam checked); quest offline rewards are day-scoped and replay calm (`replay=true`); the kill→chime→bestiary→tier-up chain is complete with correct killer-private audio (`KillConfirmService`, boss exclusions deliberate); the wand loop refuses with distinct feedback on every gate (disabled/owner/cooldown/charge/protection/no-room) and pays cost+anim+XP only after `execute()` returns true; the offering ack's split chime (offerer-only quantized pitch tell, neutral bystander cue, swallow-then-beam ordering) is genuinely excellent.

---

## 4. Top 5 satisfaction gaps

1. **The winner already knows.** (D1) The nightly award/offering rewards land with full fanfare at T+0; the roulette at T+200 is retelling old news. This inverts the single biggest daily suspense beat the mod has.
2. **Dawn is a pile-up, not a ceremony.** (D2+D3) The ~10 s spaced server beats degrade into overlapping client presentation (offering sweep → displaced day card → goals caption over the card → roulette veil over the day sweep) on exactly the days with the most activity.
3. **Rewards can eat each other at center stage.** (D2) Materialization, level-up and the day card all own `guiHeight/3` with no arbitration — the more a player achieves at once, the messier their celebration.
4. **Quiet swallowed rewards.** (D5+D8) The second offline contract survival and the disconnected arena podium winner both lose real rewards with zero feedback — the exact "action without resolution" pattern this audit exists to catch.
5. **Failures that don't say why.** (D9+D7) The revive ritual's stray/lost-sigil failures and the contract VOIDED outcome resolve into silence for most or all of their audience; three minutes of shared vigil deserves at least a one-line epitaph.

*Everything else — bestiary tiers, wand progression, contract ceremonies, minigame podiums, en/de coverage — is genuinely complete and often crafted with unusual care.*
