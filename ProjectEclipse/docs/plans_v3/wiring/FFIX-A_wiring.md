# FFIX-A wiring notes (final-eval CEREMONY/OVERLAY/FEEL fixes)

Scope: FINAL-SAT-FABLE defects D1–D3, FINAL-POLISH-FABLE V-1 / S-1 / S-2 / C-1..C-3 /
L-1 / V-3, FINAL-DOPA-FABLE top-5. **Zero hub edits landed**: no `EclipseMod`,
`EclipsePayloads`, `EclipseGuiLayers`, `registry/**`, lang JSON, `sounds.json` or
`build.gradle` changes. New classes self-register via `@EventBusSubscriber`.
Langdrop: `docs/plans_v3/langdrop/FFIX-A.json` (7 keys × en/de, one of them a value
CHANGE — see §Lang).

## What landed (self-contained code changes)

1. **SAT-D1 — winner rewards no longer materialize at T+0.**
   `awards/AwardService`: new `queueRewardForReveal` (queues silently, no immediate
   online delivery); `queueResolvedRewards` and
   `offering/OfferingService.queueWinnerRewards` use it; `sendRevealNow` now also runs
   `deliverPending(player, false)` so held winner rewards land WITH the reveal
   (offline winners keep the calm login-claim replay). Client side,
   `client/rewards/RewardMaterializeOverlay` defers queued playback behind
   `client/awards/AwardsOverlay.showLiveOrArmed()` (new) — a touchdown can never play
   through the roulette veil even on packet-order races.
2. **POLISH C-1..C-3 — center-stage arbitration.** NEW
   `client/hud/CenterStageArbiter.java` (static `tryClaim(id, ticks)` / `release(id)` /
   `isFree()`; tick-lease failsafe, pause-frozen, level-unload cleared). Claimants:
   `LevelUpOverlay`, `RewardMaterializeOverlay`, the day-number card in
   `AnnouncementOverlay`, `BossIntroOverlay`, and the `AwardsOverlay` roulette — all
   defer politely (queues stay intact) until the h/3 band is free. C-2:
   `client/skills/SkillProcToast` lifts its lane from `h-59` to `h-70` while
   `RewardMaterializeOverlay.isMaterializing()` (new) so proc toast and reward
   touchdown (`h-58`) never stack.
3. **SAT-D3 — offering announcement joined the ceremony.**
   `offering/OfferingService.resolveDay` no longer announces; new `announceResult` is
   fired by `drama/DawnCeremony` at its new `BEAT_OFFERING` (T+90, between the day
   announcement and the goals reveal — the card's roll finishes ~T+102 but the
   announcement QUEUE keeps card → day line → offering line strictly ordered).
   Non-ceremony rollovers announce inline at POST behind a
   `DawnCeremony.isRunning` gate (the `AwardService.sendRevealNow` pattern).
4. **POLISH S-1 — day card vs letterbox.** `AnnouncementOverlay` is
   subtitle-whitelisted, so the 5× numeral card now gates ITSELF: a STYLE_DAY payload
   waits at the queue head during a flight, a running card freezes (no invisible
   roll/sting), and `renderDayCard` is skipped while `CameraDirector.isHudSuppressed()`.
5. **POLISH S-2 — contract ceremonies fully pause.**
   `client/contracts/ContractRevealOverlay`: `startOrDefer` holds ceremony requests in
   `pendingShow` during suppression; the tick driver freezes entirely (no stage
   advancement, no roulette/stamp/typewriter audio) and resumes/starts when the bars
   lift. Held reveals for a window that closed mid-flight are dropped.
6. **POLISH V-1 — no raw vanilla sounds in the contract ceremony.**
   `client/handbook/UiSounds`: new `stamp()` and `chime()` (ledger ids `ui.stamp` /
   `ui.chime`, self-healing fallbacks reproduce the shipped anvil+bell / amethyst read
   behind the `uiSounds` kill-switch + `uiSoundVolume` slider);
   `ContractRevealOverlay` routes through them.
7. **POLISH V-3 — WandPathScreen to house standard.**
   `client/wand/WandPathScreen`: §2.3 open motion (5t fade + 4px rise, `reducedFx`
   snaps), eased hover lift, `UiSounds.hover()` edge blips + `click()`,
   keyboard navigation (←/→ + Enter/Space), `CursorManager`
   requestPointer/endFrame/reset lifecycle, `EclipseLang` routing throughout.
8. **POLISH L-1 — `/lang` override coverage.** `client/lang/EclipseLang.KEY_PREFIXES`
   += `"wand.eclipse."`. (`contract.eclipse.` is NOT used anywhere — contract strings
   ride `gui.eclipse.contract.*`, already covered.)
9. **DOPA #1 — proc chime pitch families.** `skills/SkillPerks.sendProcFeedback`:
   `vein_clear` pitched `1.0 + min(0.3, magnitude·0.02)` (magnitude IS the vein size),
   `ore_first_*` on the ore tier ladder (coal 0.90 → netherite 1.30, ids from
   `ores.json`), `double_*` 1.1, `bonus_*` 1.15, everything else hashed into a 4-step
   set; volume gently magnitude-nudged. Chat-line return semantics untouched (procmsg
   gametest pins them).
10. **DOPA #2 — vein countdown.** `drama/MiningFeelService.onNaturalOreMined`: breaks
    2…n−1 show an actionbar `"Iron Ore vein · 3/7"` (mined/total, new key
    `message.eclipse.vein.progress`) + a 0.35-volume `UI_TYPEWRITER` blip whose pitch
    rises 0.9→1.4 as the vein empties.
11. **DOPA #3 — boss-down release sting** (closes IDEA-07 #6). NEW
    `drama/BossDownSting.java`: `LivingDeathEvent` at LOW matched on the four boss ids
    (`herald`, `ferryman`, `rift_warden`, `fog_tyrant`); broadcasts
    `eclipse:event.boss_down` to ALL online players (`playNotifySound`, ambient) with
    a brighter private `UI_UNLOCK_STING` (0.7 vol, 1.1 pitch) for the killer.
    Self-healing: falls back to `EVENT_STORM_BURST` @ 0.6 pitch until the ledger row
    lands (§Sound ledger). `KillConfirmService` javadoc cross-references it.
12. **DOPA #4 — milestone level-ups.** `client/skills/LevelUpOverlay`: levels 10/25/40
    (mirror of `AdvancementXpBridge.MILESTONE_LEVELS`) render the glyph at 2.5× (vs
    2.0×), hold 14t longer and layer `UiSounds.unlockSting()` over a deeper
    `UiSounds.levelUp(0.8)`.
13. **DOPA #5 — unspent-point handoff.** `client/skills/InventorySkillButton`: 3×3
    accent beacon dot (slow pulse, steady under `reducedFx`) while
    `ClientStateCache.skillUnspent > 0`; `LevelUpOverlay` draws a DIM "a skill point
    awaits" line under the glyph (`gui.eclipse.skills.point(s)_available`); the server
    actionbar line `message.eclipse.skill.levelup` gains "— a skill point awaits."
    (lang value change, no code change).

## Sound ledger — 3 new events (integrator)

Register in `EclipseSounds` + `sounds.json` when the ledger next opens. Until then the
self-healing fallbacks above keep every beat audible; **no code change is needed after
the merge** (`UiSounds.resolve` / `BossDownSting.resolveBossDown` pick the registered
events up automatically).

`EclipseSounds` entries (standard `createVariableRangeEvent` W-block rows):
`ui.stamp`, `ui.chime`, `event.boss_down`.

`sounds.json` rows (house alias pattern — existing files re-pitched, no new oggs;
subtitle keys ship in the FFIX-A langdrop):

```json
"ui.stamp": {
  "sounds": [{ "name": "eclipse:ui/heart_shatter", "pitch": 0.7, "volume": 0.7 }],
  "subtitle": "subtitles.eclipse.ui.stamp"
},
"ui.chime": {
  "sounds": [{ "name": "eclipse:ui/unlock_sting", "pitch": 1.3, "volume": 0.5 }],
  "subtitle": "subtitles.eclipse.ui.chime"
},
"event.boss_down": {
  "sounds": [{ "name": "eclipse:event/submerge", "pitch": 0.48 }],
  "subtitle": "subtitles.eclipse.event.boss_down"
}
```

`event.boss_down` intent is "`event.storm_burst` re-pitched 0.6"; `event.storm_burst`
is itself `event/submerge` @ 0.8, so the composed file pitch is 0.8 × 0.6 = 0.48.

## Lang

Merge `docs/plans_v3/langdrop/FFIX-A.json` into `assets/eclipse/lang/en_us.json` +
`de_de.json`:

- NEW: `message.eclipse.vein.progress`, `gui.eclipse.skills.point_available`,
  `gui.eclipse.skills.points_available`, `subtitles.eclipse.ui.stamp`,
  `subtitles.eclipse.ui.chime`, `subtitles.eclipse.event.boss_down`.
- **VALUE CHANGE**: `message.eclipse.skill.levelup` → "Skill level %s reached — a
  skill point awaits." / "Skill-Level %s erreicht — ein Skill-Punkt wartet."
  (DOPA #5; `SkillService.handleLevelUps` grants 1 point per level, so the clause is
  always true at send time). The subtitle keys render as raw keys only in the vanilla
  subtitle overlay until merged; `point(s)_available` and `vein.progress` fall back to
  their raw keys until merged (client-only cosmetics, nothing breaks).

## Operational notes

- `CenterStageArbiter` is deliberately NOT consulted by cutscene machinery — letterbox
  suppression stays the outer gate; the token only serializes the overlays against each
  other. Leases are failsafes; owners release explicitly.
- `DawnCeremony` beat map is now T+0 sun pulse / T+20 toll / T+40 day announce /
  **T+90 offering line** / T+140 goals / T+200 roulette.
- `AwardsOverlay.showLiveOrArmed()` polls the payload cache first, so
  `RewardMaterializeOverlay`'s tick can run before `AwardsOverlay`'s in the same client
  tick without a one-tick leak through the veil.
- The proc-pitch tier map in `SkillPerks.ORE_FIRST_PITCH` mirrors the shipped
  `ores.json` ids; a NEW configured ore id simply falls into the 4-step hash set until
  someone adds a ladder entry (fails musical, never silent).
