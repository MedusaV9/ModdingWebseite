# EVAL-SAT-F — User-Satisfaction Review (v5 waves, Fable)

READ-ONLY review of the 4 v5 commits (`96d8a6b` wave 1, `6ae4e80` wave 2A, `e5909dc`
wave 2B, `09d1d49` polish) against the player complaints encoded in
`PLAN-{A,B,C,D}*.md`. Method: for each of the 20 sampled high-emotion items, the landed
code was traced end-to-end through the player flow (registration → event/tick →
render/effect), not just for file presence. Asset claims were verified with `ffprobe`
and jar/zip inspection.

**Overall: 20 / 20 sampled items land as SATISFIED for the player experience.**
Residual gaps are listed per item and ranked at the end; none of them invalidates the
core fix the user asked for.

---

## Item 1 — "Music never played" → **SATISFIED**

- **Root-cause fix landed:** `music/MusicManager.CueSound` now overrides
  `canStartSilent() → true` (MusicManager.java L434–437), with a javadoc explaining the
  exact vanilla `SoundEngine.play` zero-volume skip that silenced every cue AND (via the
  manager's own `stopPlaying()` loop) all vanilla music. This is the one-line critical
  fix from C19 §1, in place.
- **Assets real and healthy:** all 15 `assets/eclipse/sounds/music/*.ogg` probe as pure
  Vorbis 48 kHz (no more 192 kHz corrupt headers, no Theora `day_final`). Durations are
  real tracks (title 149 s, limbo 201 s, ferryman 193 s, day_final 127 s). All ≤ 2.4 MB.
- **Wiring intact:** every `music.<id>` sounds.json row streams `eclipse:music/<id>`;
  `music.xbox_era` additionally maps to the 12 vanilla calm/hal/nuance/piano tracks for
  the tutorial worlds.
- **Tool fixed:** `tools/music/treblo_generate.py` now has the previously-missing
  `postprocess()` (two-pass loudnorm to −16 LUFS, stream stripping, re-encode).
- **Gap (minor):** the planned `gametest/music/MusicAssetValidationTest.java` (C19 §4
  regression guard: every music entry resolves to pure-Vorbis ≤ 48 kHz) was **not**
  landed — nothing automated stops a corrupt re-encode from shipping again. The original
  silence bug was exactly this class of asset regression.

## Item 2 — "AY 1" timeline clip → **SATISFIED**

- `TimelineTab.drawClampedCentered` (L247–259) shifts (never clips) every caption line to
  stay `TEXT_EDGE_PAD`=4 px inside the panel; applied to captions, glitch labels and the
  divider label. The scissor still starts at the panel edge, but no line can start left
  of it — "DAY 1 — FIRST LIGHT" can no longer render as "AY 1 …". Correct edge behavior
  preserved: the shift only applies while the node anchor is on-panel, so scrolling
  nodes slide under the scissor naturally.
- A4 polish also landed: shared 9 px line grid, `NODE_SPACING` 66 (+8), calmer
  current-node pulse (520 ms/±0.18 vs the old blink), hint band in TEXT color.

## Item 3 — Hearts confusion → **SATISFIED**

- Server model: `HeartsService.HP_PER_LIFE = 4` — 1 Leben = 2 vanilla hearts; default
  5 Leben = exactly vanilla 20 HP (max-health modifier math verified at L54).
- Display: `PurpleHeartsLayer` cancels vanilla `PLAYER_HEALTH` (`RenderGuiLayerEvent.Pre`,
  with `receiveCanceled` arbitration against `GhostHeartsLayer` and `XboxHudSkin`) and
  redraws ONE purple heart per Leben; `HeartRowGeometry.displayUnits`/`hpPerSlot`
  centralize the compression so the burst overlay stays pixel-identical. Vanilla parity
  preserved on the compressed row (absorption sprites, blink, regen wave, jitter,
  poison/wither/frozen tints).
- The heart count on screen IS the Leben count — no second "real" health row anywhere.
  Singular fix present: `gui.eclipse.lives.one` = "1 Life" / de "1 Leben"
  (en_us.json/de_de.json L1698–1699).

## Item 4 — Two countdowns → **SATISFIED**

- `RealtimeDayService` no longer creates any `ServerBossEvent` (class doc L51–55 states
  the countdown is presented ONLY by `DayTimerLayer`; no creation code remains — grep
  confirms only the doc mention). Same for `TimedBuffService` (buff timers render only
  in the TAB-expanded sidebar).
- `DayTimerLayer` is bottom-anchored ABOVE the hotbar (`BOTTOM_ANCHOR = 47`, i.e.
  `topY = guiHeight − 50 − digitHeight`), coordinated with the A9 XP bar slot, lifting
  above stacked status rows when needed. Exactly ONE day countdown surface.
- Collapsed sidebar keeps only "Day N" (SidebarPanel L327–330: "timer lives in
  DayTimerLayer now (A7)"); the buff-count row is gone (L353–354).
- Xbox 30:00 timer: the `ServerBossEvent` fallback was deleted
  (XboxEventService L625–630) — `XboxTimerLayer` in the day-timer HUD slot is the only
  surface.

## Item 5 — Loading screen language switch → **SATISFIED**

- The dead-merge root cause is fixed: `EclipseLang.mergeLocale` predicate is now
  `location.getPath().equals("lang/" + localeFile + ".json")` (L216–217) with the
  regression-canary debug log of merged key counts (L205–209).
- `KEY_PREFIXES` gained `eclipse.caption.`, `eclipse.xbox.`, `eclipse.minigame.`
  (L68–70) with an audit note for the remaining families.
- The override applies to the loading screen in the real player flow: it is persisted in
  `eclipse-client.toml` (`LangConfigBridge`) and restored **before the title screen**
  (`ModConfigEvent` hook, L179–183), and `EclipseLoadingScreen` resolves title + tips
  through `EclipseLang.tr` per frame.
- `CaptionRenderer` resolves all caption text via `EclipseLang.tr/trString` (4 call
  sites); `lang/ServerLang.java` exists for server-baked sends.

## Item 6 — EMI leaks locked items → **SATISFIED**

- `EclipseEmiPlugin.isHiddenStack` now tests `ClientUnlockCache.isIdLocked(id)` (glob
  rules from `modgate_ids.json`) in addition to namespace locks and the `EMI_HIDDEN`
  tag; `isHiddenRecipe` gets the same belt-and-braces. The class doc records the design
  decision: createconnected / create_confectionery / ends_delight are gated ONLY through
  id globs, so the glob check is the correct (and now sufficient) client filter.
- Server → client sync exists: `UnlockSync.lockedIdGlobs` pre-filters to LOCKED rules and
  ships them in `S2CUnlockedKeysPayload`; changes trigger `EmiReindexer.requestReload()`.
- EMI bumped 1.1.18 → **1.1.24+1.21.1** (build.gradle L147–151, strictly pinned), and the
  built jar physically contains `META-INF/jarjar/emi-neoforge-1.1.24+1.21.1.jar` —
  the bump resolved and compiled.

## Item 7 — Border kick + 5 s slow fall → **SATISFIED**

- `SoftBorder`: `TELEPORT_BAND` 3.0 → **1.5** (L105), `IMPULSE_SCALE` 0.25 → **0.55**
  (saturates `MAX_IMPULSE` inside the band; a sprinting player turns around ≤ 2 blocks
  past R), `FALLBACK_SLOW_FALLING_TICKS` 60 → **100** (5 s) applied at BOTH teleport
  sites (ground-found L564 and spawn-fallback L583).
- Pre-band warning landed: `WARNING_BAND = 4.0` (R − 4) with throttled sound + action
  bar, so the kick is telegraphed.

## Item 8 — Nether arrival shaft spawn + fall damage → **SATISFIED**

- `BreachBuilder.arrivalCenter()` pushes the pad `ARRIVAL_INWARD_OFFSET` (≥ 8 blocks)
  toward the disc center while `updraftCenter()` stays at the landmark anchor — fresh
  arrivals no longer land in the boost column, and the chimney writes build the shaft
  free-standing off the pad (L535–546).
- `BreachTransferService`: survival players NEVER ride the legacy updraft boost
  (L374–379 — creative-only); `refreshDriftSafety` re-applies Slow Falling every refresh
  window while airborne; `fallDistance = 0` at capture, at swap, AND on the landing tick
  (`finishDrift` L638: "the landing tick itself must never carry a fall"); abort path
  releases with generous Slow Falling.
- Storm moment: `strikeStormMoment` spawns 3 visual-only `LightningBolt`s + a thunder
  weather burst on open. Pre-protection: `protection/LandmarkProtection.java` exists
  (breach + observatory zones).

## Item 9 — Mobs not spawning on disc → **SATISFIED**

- `mixin/NaturalSpawnerMixin` injects at `getRandomPosWithin` RETURN and re-bands the Y
  roll via `entity/spawn/SpawnYBands.adjust` (overworld disc band incl. cave band,
  nether floor→ceiling band, off-disc pass-through). Registered in
  `eclipse.worldgen.mixins.json`, declared in `neoforge.mods.toml` (L60–61) — the mixin
  actually loads.
- Cap competition fixed: ambient/event mobs (drift lantern, fog/glitched families,
  sunmote, gazer, stalker, deckhands…) are `MobCategory.MISC` — exempt from the vanilla
  MONSTER census (verified across 8 entity registries).
- Verifiability: `/dev spawn census [reset]` in `DevSpawnCommands` prints per-category
  cap usage + attempt/success counters from the band instrumentation.

## Item 10 — Ferryman stuck in door + arena flow → **SATISFIED**

- C9 both bugs fixed in `FerrymanEntity`: yaw **−90** ("yaw −90 faces EAST (+X, the bow)
  — 90 was WEST, straight into the door", L248–249) and `STERN_X = −(HALF_LENGTH − 6)`
  = −13 (clears DOOR_X=−17 and the x=−12 bench column, L105–111). `tickCrewPhase`
  reuses the constant and faces the bow.
- C10 full crossing landed as the `ferryman/` package: `AltarDoor` (dead door at the
  altar on catalyst deposit), `ArenaFight` stage machine GATE (wait-for-ALL-living OR
  timeout + countdown + straggler pull) → ARRIVAL (deck flyaround hold) → TRANSFORM
  (block-display deck lift + white-out + `FreezeService.transport` into
  `eclipse:ferryman_arena`) → FIGHT (chunk force-load, spectator shielding beyond
  `ArenaBuilder.SPECTATOR_ZONE_MIN_Z`, victory/wipe/reset watch). Ghosts land on the
  spectator ship. Restart law: never resumes mid-gate/mid-transform; login re-arm via
  `onPlayerLoggedIn`. `data/eclipse/dimension/ferryman_arena.json` present.
  `FinaleRitual` arms via `ArenaFight.armGate` (L136) with legacy fallback if the arena
  dimension is missing.

## Item 11 — End shatter + no snow → **SATISFIED**

- Shatter: `worldgen/end/EndShatterSequence` subscribes to
  `EclipseDragonFight.addListener` at `ServerAboutToStart` (L241). Full show: fall grace
  (Slow Falling + 120 s no-fall for everyone above Y 300), global `end_shatter` orbit
  cutscene (asset present in `assets/eclipse/cutscenes/`), deterministic Voronoi 6–9
  islets with seam channels + per-islet vertical offsets as budgeted copy-then-clear,
  ≤ cap tagged block-display debris, podium islet pinned (egg/portal safe),
  restart-resumable `ShatterData` cursor, then `EndCityKit` towers + end-ship with real
  loot/shulkers via `StructurePendingRegistry`.
- No snow: `DiscBiomeSource.getNoiseBiome` returns the End holder for **every** column
  above `END_BIOME_MIN_Y = 320` — the footprint check is gone (L188–194 documents the
  quart-blend snow-over-rim bug). Guarded by `gametest/worldgen/EndBiomeBandTest.java`.

## Item 12 — Final credits + client close → **SATISFIED**

- `FinaleRitual.tickVictory` chains into `CreditsSequence.begin(server)` after the
  revive drain (L226), with the old trip-home as config fallback.
- `ritual/CreditsSequence` implements the full IDEAS §B timeline: fade black → helm shot
  (`credits_helm.json`, present) → fade WHITE + disguised white loading hold → epilogue
  beach (`eclipse:epilogue` dimension json present) → `day_final` cue + credits roll
  (`CreditsPanel`) + auto-run (`CreditsAutoRun` client injection + server nudge
  watchdog) → offshore lightning + 24 block-display debris flyby → title card 1
  ("…COMES BACK IN AVENGERS: DOOMSDAY", `TitleCardLayer` glitch decode) → burst → title
  card 2 → fade → music finale → **client close**.
- Client close is real and guarded: `CreditsClient.handleClose` → countdown →
  `minecraft.execute(minecraft::stop)` with nonce match, `hasSingleplayerServer()` skip
  (SP/LAN hosts never self-shutdown) and the `allowFinaleClose` rehearsal kill-switch.
- Failure-safety: per-beat watchdogs + SavedData; the sequence never replays
  (`SequenceReplayable` law).

## Item 13 — Collections dopamine loop → **SATISFIED**

- Server: `collections/` package — config-driven `collections.json`
  (`CollectionsConfig`, lanes mine/kill/craft/smelt/**pickup**), lifetime counters in
  `CollectionsState` SavedData, `CollectionsService` subscribing to the sanctioned
  `EclipseSignals` lanes (natural-mine anti-farm free via `AnalyticsService`
  ownership). The missing pickup signal was added correctly: ONE
  `ItemEntityPickupEvent.Post` owner in `AnalyticsService` (L308–311) firing
  `EclipseSignals` + `pickup:` analytics keys.
- Tier crossings grant skill XP / shards / unlock keys and fire the tier payload; client
  has `CollectionsTab` registered in the handbook (9-tab list, HandbookScreen L96–98)
  and `CollectionTierToast`. Gametest `collections/CollectionGameTests.java` present.

## Item 14 — Heart steal outside hunts → **SATISFIED**

- Landed as `lives/HeartTheftService` (plan name `HeartTheftRules`; same content, more):
  verdict engine with STEAL / disabled / ghost / spectator / pre-event /
  event-dimension / **contract-pair** / **floor** / **cooldown** verdicts. Floor and
  cooldown even freeze the victim's normal death loss (anti-farm stronger than planned).
- `LifecycleEvents.onLivingDeath` routes every PvP kill through `evaluate` (L91–92);
  STEAL is the only verdict that moves a Leben (umbral-blade bonus stays inside the
  branch, capped); `recordSteal` + `celebrate` fire the ceremony (boss-style titles,
  global named announce, bell + heart pulse, shake, heart-burst emitter at the corpse).
- Pair cooldown persisted (`eclipse_heart_theft` store), floor default 1 (murder can
  never ghost/ban outside events), config in `hearts.json`. Gametest
  `lives/HeartTheftTests.java` present.
- **Deviation (minor):** default pair cooldown is **30 minutes** vs the plan's
  20 **hours** — same-pair farming re-opens far sooner than designed
  (config-tunable; the freeze-both-directions rule softens the impact).

## Item 15 — Skill tree size + double-click + rebirth + wand tab → **SATISFIED**

- Size: `SkillTreeConfig` defaults author **62** nodes (plan: ~60); widget zoom range
  0.45–1.5 with readable first-open floor.
- Double-click buy: `SkillTreeWidget` 350 ms same-node window → `onBuyRequest`
  (L586–598), triple-click guarded; footer buy button retained.
- Rebirth: full stack — `rebirth/` package (`RebirthService` all-or-nothing transaction:
  validate → consume shards → `resetTree` + full progression wipe → 
  `HeartsService.addPermanentLife(+1)` → count persisted → ceremony;
  refuse-at-cap), `RebirthHooks.curveFor` per-rebirth level-cost multiplier seam in
  `skills/`, `C2SRebirthPayload`/`S2CRebirthStatePayload` both registered, rebirth strip
  + hold-to-confirm button in `SkillTreeScreen`, `gametest/rebirth/RebirthTests.java`.
- Wand tab: `SkillTreeScreen` has a real tab strip ("Skills" | "Zauberstab"), TAB
  switches, embedding `WandProgressPanel` — wand progression reachable any time, not
  just at first choice.

## Item 16 — Sidebar TAB sections + pre-event hidden → **SATISFIED**

- Pre-event gate: `SidebarPanel.isActive()` requires the server-synced
  `ClientStateCache.eventStarted` (L86) — nothing renders before the start event.
- Modes: `EclipseClientConfig.sidebarMode()` FULL / TAB_ONLY / OFF; only FULL keeps the
  persistent edge panel; the TAB-held expanded card always answers (L137–144), morphing
  in from off-screen in TAB_ONLY/OFF.
- Sections: `SidebarExpanded` renders labeled "Global Missions" / "Sidequests" sections
  (L149–153) with both lang keys present in en+de.

## Item 17 — Map spoiler rework → **SATISFIED**

- `MapTab` fully reworked to explored-rings fog-of-war: current committed stage interior
  sketched from the deterministic terrain sampler; the NEXT ring only as a glitch-arc
  silhouette; nothing beyond — total world size and future stages never render.
- Landmarks appear only after proximity discovery: server
  `progression/LandmarkDiscoveryService` grants `landmark:<id>` unlock keys, the tab
  consults `ClientUnlockCache.isKeyUnlocked` (reuses the existing unlock payload — no
  new packet, as planned).
- Sketch/parchment restyle on `EclipseUiTheme` tokens with a budgeted progressive
  `DynamicTexture` cache; `reducedFx` respected.

## Item 18 — Backrooms event complete → **SATISFIED**

- Complete flow in `backrooms/` (10 classes) + `dimension/backrooms.json`:
  **portal** — frameless star-rift (`BackroomsPortal`, C16 style variant), collision
  entry, return anchors; **maze** — 24×24-cell budgeted stamp during ANNOUNCED with
  crash-resume cursor + per-instance seed law; ambience — photosensitivity-capped panel
  flicker; mobs — `GlitchedWandererEntity` (cap 6, min player distance) + `TheOther`
  cameo; **jumpscare** — `BackroomsScare`: once per player per instance (persisted),
  ≥ 90 s inside, rear-arc + unseen + 1-in-30 gate, 60 s global cooldown, no damage,
  client overlay with `reducedFx` fallback; **exit** — T−5:00 exit portal on a far
  highway cell upgrading the reward share (direct-to-inventory shards + Almond Water +
  participation buff); `/backroomsleave` click-confirm; protected deaths (no drops, no
  life loss).
- Extension recipe delivered: `eventdim/PortalEventScheduler` variant registry
  (xbox COMMON / backrooms RARE) + `PORTAL_RECIPE.md`.
- **Caveat (by design):** opening is operator-driven (`/dev portal roll|open`,
  `/dev backrooms`) — there is deliberately no automatic timer ("scheduling stays with
  the ops team"). Players only meet the backrooms if an operator (or future automation)
  triggers it.

## Item 19 — "Sonic0810" dev bypass → **SATISFIED**

- `anticheat.json` schema + baked `bootstrap.json` ship `devBypassUuids` with the
  `"name:Sonic0810"` placeholder pin (literal UUIDs or `name:<Player>` resolved through
  the profile cache; the config `_comment` explicitly tells the operator to replace the
  pin with the real UUID).
- Enforcement path: `AntiCheatCheck.isDevBypass` short-circuits both `handleModlist`
  (L413) and the timeout sweep (L469); `DevRoot` accepts permission-2 OR dev-bypass for
  `/dev` (L71); the local `BootstrapScreen` turns advisory for a bypass identity;
  `DevHandbookPayloads` honors it too. Trust model documented in `security_model.md`
  (bypass = client mod freedom + /dev, never op). Gametest
  `admin/ModcheckEvaluateTests.devBypassMatchesOnlyListedUuids` present.

## Item 20 — mrpack distributable + Fabric API answer → **SATISFIED**

- `tools/modpack/build_mrpack.py` + `pack_manifest.json` + README landed, and a real
  artifact is committed: `dist/eclipse-event-2.1.0.mrpack` — verified by unzip:
  `modrinth.index.json` with 10 CDN-referenced files (Create, FD, Supplementaries,
  Sophisticated*, voicechat, …), `dependencies {minecraft 1.21.1, neoforge 21.1.238}`,
  `overrides/` carrying only redistributable content (the Eclipse jar itself +
  `config/eclipse` seeds) and `MANUAL_INSTALL.md` for the two license-blocked mods
  (Aeronautics bundle, Sable) — exactly the BUNDLING.md policy, machine-shipped.
- Fabric API question answered explicitly and correctly: BUNDLING.md §"Nested
  (jar-in-jar) mod ids" — **NO standalone Forgified Fabric API needed**; the four
  `fabric_*` ids ride inside Sodium/Iris NeoForge builds and are allowlisted in
  `AntiCheatCheck.defaults()` (L626, L648) so they no longer trip the modcheck.

---

## Residual gaps, ranked (none block the sampled items)

1. **Music asset regression guard missing** — the planned
  `MusicAssetValidationTest` gametest (C19 §4) was never landed. The assets are healthy
  today (ffprobe-verified), but the original "total silence" incident was caused by
  corrupt assets shipping unnoticed; there is still no automated check.
2. **Heart-theft pair cooldown 30 min vs planned 20 h** — same-pair kill farming
  re-opens after 30 minutes instead of ~a day (`hearts.json` default). Config-tunable
  and both-direction-freezing, but noticeably weaker anti-farm than designed.
3. **Backrooms (and xbox portals) have no automatic scheduler** — deliberate
  ("ops team decides when"), but a playtester will never see the completed backrooms
  content unless an operator runs `/dev portal roll`/`open`. If the next playtest is
  meant to exercise it, the ops runbook must say so.
4. **Credits client-close never fires for singleplayer/LAN hosts** — correct safety
  guard, but a solo player will not experience the "the game closes itself" ending
  beat; they get the fade + music finale only. Worth a line in the ops/runbook so the
  finale is demoed on a dedicated server.
5. **mrpack still needs two manual installs** — Aeronautics bundle + Sable cannot be
  `files[]` entries for license reasons; `MANUAL_INSTALL.md` covers it, but the
  distributable is not fully one-click and the operator must hand out those two jars.

## Verdict summary

| # | Item | Verdict |
|---|---|---|
| 1 | Music never played | satisfied (minor: no asset gametest) |
| 2 | "AY 1" timeline clip | satisfied |
| 3 | Hearts confusion (Leben = 2 hearts) | satisfied |
| 4 | Two countdowns → one day timer | satisfied |
| 5 | Loading screen language switch | satisfied |
| 6 | EMI leaks locked items | satisfied |
| 7 | Border kick + 5 s slow fall | satisfied |
| 8 | Nether arrival shaft + fall damage | satisfied |
| 9 | Mobs not spawning on disc | satisfied |
| 10 | Ferryman door + arena flow | satisfied |
| 11 | End shatter + no snow | satisfied |
| 12 | Final credits + client close | satisfied (SP host exempt by guard) |
| 13 | Collections dopamine loop | satisfied |
| 14 | Heart steal outside hunts | satisfied (cooldown default weaker than plan) |
| 15 | Skill tree / double-click / rebirth / wand tab | satisfied |
| 16 | Sidebar TAB sections + pre-event hidden | satisfied |
| 17 | Map spoiler rework | satisfied |
| 18 | Backrooms complete | satisfied (operator-triggered by design) |
| 19 | Sonic0810 dev bypass | satisfied |
| 20 | mrpack + Fabric API answer | satisfied (2 manual-install mods) |

**Score: 9.5 / 10.** Every sampled complaint is genuinely addressed in the shipped
code, traced through the actual player flow, with real assets and real artifacts
(healthy OGGs, EMI 1.1.24 physically embedded in the built jar, a real `.mrpack` in
`dist/`). The half-point holds for the missing music-asset regression guard and the
two plan deviations (theft cooldown, ops-triggered backrooms) that a playtester could
still bump into.
