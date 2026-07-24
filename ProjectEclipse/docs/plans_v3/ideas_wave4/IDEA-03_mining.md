# IDEA-03 — Mining/Gathering Dopamine (Collector 3/20, Eclipse Event wave 4)

Focus: ore discovery, day-gated ore unlocks, skill procs, ore-drop buffs. 10 ranked concrete
ideas, each with exact hooks and S/M sizing. Read-only survey — no code changed.

## Grounding: the systems these ideas hang off

- **Deterministic veins.** `worldgen/ore/OreField.tryOre` derives one vein candidate per 16³
  cell per ore from `hash3(H_ORE + ore.salt(), cx, cy, cz)` + `FrozenParams.mapSeed()` — vein
  center `(vx, vy, vz)`, radius, and full blob membership are recomputable server-side at any
  time. This makes vein-size reveals, vein-complete detection, and future-vein hints cheap and
  exact (no chunk scans, no new persistence).
- **Day → band gating.** `progression/DayScheduler` day rollover → `WorldStageService
  .applyDayTriggers` commits a world stage → border ring moves → new annulus band becomes
  reachable; `OreField` only places an ore where `band >= ore.unlockStage()`
  (`ores.json`: coal/copper stage 0; iron/gold/redstone/lapis/quartz stage 2;
  diamond/zinc stage 3). Query seam: `OreGateApi.unlockedInBand(band)` /
  `unlockStageOf(oreId)` / `bandAt(profile, pos)`.
- **Mining signal.** `EclipseSignals.onNaturalBlockMined` → `SkillService` grants
  `SOURCE_MINE` XP and calls `SkillPerks.onNaturalOreMined(player, state, pos)` (T2
  Fortune's Echo `double_ore_drop_chance` → proc id `double_ore`; T6 Earthen Bond
  `bonus_raw_ore_chance` → proc id `bonus_ore`). Natural-only is already guaranteed
  (`SkillPerks.isPlaced` re-check).
- **Proc feedback trio.** `SkillPerks.sendProcFeedback(player, procId, magnitude)` =
  `EclipseSounds.SKILL_PROC` (fixed 0.7F vol / 1.0F pitch) + `S2CSkillProcPayload` +
  optional chat line. Client `client/skills/SkillProcToast` queues toasts (cap 4) and
  **degrades gracefully on unknown proc ids** (underscores → spaces) — new proc ids ship
  server-side for free; a lang key upgrades them later.
- **Ore-drops buff is silent today.** `buffs/BuffEffects.onBlockDrops` multiplies natural ore
  drops via `TimedBuffService.multiplier(server, "ore_drops")` with **zero feedback** — extra
  items just appear in the pile.
- **Per-player counters already exist.** `analytics/AnalyticsKeys.PREFIX_MINE`
  (`mine:<block_id>`, natural-only), `MINE_TOTAL`, `DEPTH_MIN_Y`; read via
  `AnalyticsApi.value(...)` / `sumAcrossDays(...)`.
- **One-shot FX seam.** `network/fx/S2CFxEventPayload(id, pos, a, b)` — frozen shape, handler
  switches on id constants in `FxPayloads`; adding a new id constant is the sanctioned way to
  ship a new positional client effect.

---

## Ranked ideas

### 1. First-ore-of-a-tier fanfare ("Ore Codex" sting) — **S/M**
The single highest dopamine-per-line idea: the first time a player naturally mines each ore
id, play a discovery fanfare — `EclipseSounds.UI_UNLOCK_STING` + proc toast
`ore_first_<oreId>` ("✦ First iron! ") + a one-off sparkle burst at the block.
- **Hook:** end of `SkillPerks.onNaturalOreMined` (or a sibling static in `worldgen/ore`),
  map `state` → ore id via a small block→id lookup built from `OreConfig.current()`.
- **First-time detection:** `AnalyticsApi.sumAcrossDays(server, uuid, "mine:" + blockId) == 1`
  right after the analytics increment (zero new persistence), or a tiny `SkillState.Entry`
  string set if ordering vs. the analytics listener proves fragile.
- **Feedback:** `sendProcFeedback(player, "ore_first_" + oreId, 0F)` — toast works day one via
  the unknown-id fallback; add `message.eclipse.skill.proc.ore_first_*` lang keys for polish.
- **Why #1:** every player hits it 8–11 times across the event, exactly aligned with the
  day-gating beats (day-2 iron, day-3 diamond feel like *events*).

### 2. Vein-complete chime + vein-size reveal — **M**
On breaking the first block of a vein, actionbar shows "Iron vein · 7 blocks"; when the last
blob block is mined, a bright two-note chime + toast "Vein cleared ×7". Turns every vein into
a micro progress bar with a payoff note.
- **Hook:** new `worldgen/ore/VeinTracker` (server-only, no state) called from the
  `SkillService` `onNaturalBlockMined` listener alongside `SkillPerks.onNaturalOreMined`.
- **Math:** re-derive the vein for the mined block's cell with the exact `OreField.tryOre`
  hash (expose a package-private `veinAt(ore, cx, cy, cz)` returning center+radius); blob
  membership test is the existing ellipsoid check (`dy² × 1.6`), ≤ ~7³ candidate positions at
  max radius 3.2 — scan only on ore breaks, only in the already-loaded chunk.
- **Feedback:** completion via `sendProcFeedback(player, "vein_clear", blockCount)` (toast
  renders "×7" through the existing magnitude suffix); size reveal via
  `player.displayClientMessage(..., true)` actionbar.
- **Why #2:** rewards finishing a vein instead of strip-run ADHD; deterministic worldgen makes
  it exact, cheap, and cheat-proof.

### 3. Proc juice upgrade: sparkle burst at the block for `double_ore`/`bonus_ore` — **S**
Today a T2/T6 proc is a sound + a text line while the player stares at the *block*; the extra
drops are visually identical to normal drops. Add an ore-colored particle ring + item-glint
pop at `pos` so the eye sees the jackpot where it happened.
- **Hook:** `SkillPerks.onNaturalOreMined`, right after each `Block.popResource(...)` +
  `sendProcFeedback(...)` pair.
- **Wire:** new `FxPayloads.FX_ORE_PROC` id on `S2CFxEventPayload(id, pos, magnitude,
  colorIndex)`; client handler spawns a small burst (reuse `EclipseClientParticles` /
  `PurpleWispParticle` infra), gated by `EclipseClientConfig.reducedFx()`.
- **Why #3:** smallest diff of the top tier; upgrades an already-shipped reward loop that
  currently under-sells its own payout.

### 4. Make the `ore_drops` buff *feel* active: drop glints + first-hit note — **S**
`BuffEffects.onBlockDrops` silently mints extra copies — most players never notice the buff
fired. Add: (a) the same `FX_ORE_PROC` burst (idea 3) at the drop position for each extra
copy, and (b) one actionbar line per buff activation per player ("Ore surge! drops ×2 — 4:32
left") on their first boosted break.
- **Hook:** `BuffEffects.onBlockDrops` where `extras` is non-empty; a per-player
  "seen this buff instance" set keyed by the buff's expiry timestamp (cleared in the existing
  `ServerStoppedEvent` reset).
- **Why #4:** buffs that go unnoticed are wasted dopamine budget; two tiny call sites.

### 5. Tomorrow's-ore forecast at day rollover — **S**
When the day advances, diff `OreGateApi.unlockedInBand(newMaxBand)` against the previous
band's list and announce the *upcoming* unlocks: "The ring widens at dawn — iron and gold lie
in the new lands." Anticipation is half the dopamine of a gate.
- **Hook:** a POST `dayRollover` signal listener (same seam `DayScheduler` already fires for
  quest re-roll/sidebar sync), broadcasting via `timeline/AnnouncementService` /
  `S2CAnnouncePayload` so it uses the existing announcement overlay + `UI_UNLOCK_STING`.
- **Why #5:** pure config-diff + existing broadcast path; makes the day-gating system legible
  to players who never read the wiki.

### 6. Band-entry "new frontier" banner — **S/M**
First time each player physically crosses into a band that unlocked *today*, show the marquee
banner ("NEW FRONTIER — iron · gold · redstone") + sting. The walk across the old border
becomes a doorway moment.
- **Hook:** per-player band check in an existing sweep (`SkillPerks.onServerTick` 20-tick
  sweep pattern, or `BorderController` if it already iterates players): compare
  `OreGateApi.bandAt(profile, player.blockPosition())` against a per-player last-band map;
  fire once per (player, band) via a `SkillState.Entry`-style persisted set.
- **Feedback:** `client/hud/AnnouncementOverlay` + `MarqueeText` via `S2CAnnouncePayload`;
  list = diff of `unlockedInBand(band)` vs `band - 1`.
- **Why #6:** converts spatial progression into a felt reward; slightly more state than #5.

### 7. Mining streak combo ("Prospector's rhythm") — **S/M**
Consecutive natural ore blocks mined without a >8s gap build a streak; at 10 / 25 / 50 fire an
escalating toast (`ore_streak` ×10/×25/×50) with rising pitch on the proc sound.
- **Hook:** `SkillPerks.onNaturalOreMined` + a `Map<UUID, StreakState>` (count + last-millis
  via `EclipseClock.epochMillis()`), cleared in the existing `SkillPerks.resetStatics()`.
- **Wire:** add a `sendProcFeedback(player, procId, magnitude, pitch)` overload so milestone
  pitch can climb (0.9F → 1.1F → 1.3F); toast magnitude suffix renders the streak count free.
- **Why #7:** classic variable-interval reinforcement layered on the existing trio; keep
  thresholds sparse so it never spams the 4-deep toast queue.

### 8. Global first-strike world echo for top-tier ores — **S**
The first diamond / ancient debris of the *event* (server-wide, once per ore id) triggers a
subtle global line: "⚒ Kael struck diamond beyond the third ring." Social proof + envy = a
server-wide dig night.
- **Hook:** same detection point as idea 1; server-wide once-guard in a `SavedData`-style
  flag (or an `AwardsState`-adjacent set); restrict to `unlockStage >= 3` ores via
  `OreGateApi.unlockStageOf(oreId)`.
- **Feedback:** `S2CAnnouncePayload` to all players (respect the existing anonymity package
  toggles when naming players).
- **Why #8:** one broadcast per ore per event — maximal FOMO per byte, zero spam risk.

### 9. Border-edge shimmer hints at *real* future vein sites — **M**
For players standing near the soft border ring, the server precomputes a handful of next-band
vein candidates (`OreField` hash math for `band + 1` cells within ~24 blocks beyond the ring)
and pulses a faint shimmer FX at those true positions — "tomorrow, ore surfaces *right
there*." Since worldgen is frozen-deterministic the hints are honest.
- **Hook:** new small `OreHintService` with a 100-tick sweep over online players; ring radius
  from `FrozenParams.stageRadii(profile)`; per-ore gate `unlockStage == currentMaxBand + 1`.
- **Wire:** new `FxPayloads.FX_ORE_HINT` on `S2CFxEventPayload` (pos = vein center, `a` =
  fade seed); client renders a sparse column shimmer, `reducedFx()`-gated.
- **Why #9:** the strongest anticipation mechanic of the set, but needs FX taste + tuning to
  avoid revealing exact dig coordinates too hard (jitter the hint pos by 2–3 blocks).

### 10. Depth-milestone fanfares + "Deep Delver" active chip — **M**
First time a player passes Y=0 / Y=-32 / Y=-64 / Y=-96, play a low drone sting + toast
("Depths unlocked: −64 — diamonds sleep below"); while T4 Deep Delver's
`break_speed_below0_pct` is live, show a tiny pickaxe chip near the skill XP bar so the perk's
uptime is visible.
- **Hook:** depth is already aggregated (`AnalyticsKeys.DEPTH_MIN_Y`, max-wins); milestone
  check where that sampler updates (`AnalyticsSampler`), fanfare via `sendProcFeedback`.
  Chip: a sibling mini-layer to `client/skills/SkillXpBarLayer`, driven by the owned-node
  state the skill tree client model already syncs.
- **Why #10:** solid but the least novel; depth milestones partially overlap the existing
  `deep_diver` award, so coordinate with `awards.json` before building.

---

## Notes / constraints observed

- All server hooks above sit on **already-natural-only** paths (`naturalBlockMined` signal,
  `PlacedBlockCheck` / `SkillPerks.isPlaced`) — no new anti-abuse surface.
- `network/**` payload shapes are frozen: everything here rides existing payloads
  (`S2CSkillProcPayload`, `S2CAnnouncePayload`) or the sanctioned `S2CFxEventPayload`
  new-id-constant path.
- The toast queue caps at 4 with oldest-dropped — ideas 7/2 should keep milestone density low
  so fanfares (ideas 1/8) never get evicted by streak chatter.
