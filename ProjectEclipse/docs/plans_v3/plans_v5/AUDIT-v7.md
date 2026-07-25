# AUDIT-v7 — Third-Pass Completeness Audit (AUDIT-3)

Read-only audit. Sources: `AUDIT-early.md`, `AUDIT-recent.md` (item catalogs), `EVAL-V6-FX.md`,
`EVAL-V6-CUTBD.md`, `EVAL-V6-PHOTON.md`, `EVAL-V6-MOB.md`, `EVAL-V6-RACES.md`, `EVAL-V6-COMPLETE.md`
(v6 eval-fix wave defect lists). Method: targeted source/asset inspection (`rg`, JSON/PNG validation
scripts); no gradle, no git.

**Verdict summary**

| Group | Checked | Closed/Fixed | Partial | Broken |
|---|---|---|---|---|
| Previously PARTIAL/MISSING (13 items) | 13 | 12 | 1 | 0 |
| v6 eval-fix wave claims (19 defect groups) | 19 | 19 | 0 | 0 |
| Spot-checks of older DONE features (10) | 10 | 10 intact | 0 | 0 |

The single PARTIAL: **cobblestone `dailyCreditCap` is 600, not the 1500 required by
`EVAL-DOPA-F.md` and re-flagged by `EVAL-V6-COMPLETE.md`** (migration machinery itself is in
place and correct). Everything else verified closed.

---

## 1. The 13 previously-PARTIAL/MISSING items

### 1.1 `/dev timer color` — **CLOSED**
- `devtools/dev/DevTimerCommands.java`: `/dev timer color <auto|preset|#hex>` registered, perm-gated,
  validates hex, persists to `RealtimeState`, immediately rebroadcasts via
  `RealtimeDayService.broadcastClock`.
- `progression/realtime/RealtimeState.java` loads/saves `timerColorMode`;
  `network/S2CDayClockPayload.java` encodes it; `client/hud/DayTimerLayer.java` applies preset/hex or
  falls back to the auto urgency ramp when mode is `auto`.

### 1.2 `storm_heart` item + texture + drop — **CLOSED**
- `registry/EclipseItems.java` registers `STORM_HEART`; `entity/boss/fog/FogTyrantEntity.java`
  `dropCustomDeathLoot` spawns it explicitly.
- `assets/eclipse/models/item/storm_heart.json` present; `assets/eclipse/textures/item/storm_heart.png`
  exists and validates as 16×16 RGBA.

### 1.3 Rebirth aura keepsake — **CLOSED**
- `rebirth/RebirthAuraService.java` emits WITCH particles around reborn players, gated by
  `RebirthState.auraVisible`; `/skills aura on|off` in `skills/SkillCommands.java`; toggle persisted
  in `rebirth/RebirthState.java`.

### 1.4 `rewardXp` chips — **CLOSED**
- `network/S2CQuestStatePayload.java` encodes/decodes `rewardXp`; `progression/goals/QuestEngine.java`
  populates it from `GoalSpec.reward().skillXp()`; `client/hud/SidebarPanel.java` renders the `+N XP`
  chip in both collapsed and expanded quest rows.

### 1.5 Heart-theft global cooldown + capped-killer symmetric freeze — **CLOSED**
- `lives/HeartTheftService.java`: `Verdict` includes `NO_STEAL_KILLER_CAPPED` and
  `NO_STEAL_KILLER_COOLDOWN`, both with `freezesDeathLoss=true`; `killerCooldownMinutes=45`.
- `lives/LifecycleEvents.java` consults `HeartTheftService.evaluate` and checks
  `freezesDeathLoss()` before applying the victim's heart loss (symmetric freeze).

### 1.6 d01 goal scopes — **CLOSED**
- `progression/goals/GoalConfig.java`: `d01_stone_age` and `d01_touch_altar` are `Scope.EACH_PLAYER`;
  `CONFIG_VERSION = 3` drives migration of stale saved configs.

### 1.7 `p_swimmer`/`p_leaper` minDay — **CLOSED**
- Same file: both pool goals carry `minDay = 2` (no more day-1 appearance).

### 1.8 Cobblestone cap + SP moves + config migration — **PARTIAL**
- `collections/CollectionsConfig.java`: `CONFIG_VERSION = 2` with `migrateIfOutdated` rewriting the
  stale cobblestone `dailyCreditCap` in old save files — migration mechanism CLOSED.
- Coal T2 and Timber T3 each grant `+1 SP` — CLOSED.
- **Deviation**: `COBBLESTONE_DAILY_CREDIT_CAP = 600L`, but `EVAL-DOPA-F.md` explicitly required
  **1500**, and `EVAL-V6-COMPLETE.md` marked the 600 value BROKEN and instructed changing it to 1500.
  Value still 600 → this sub-item remains open.

### 1.9 Collection exactly-once journal — **CLOSED**
- `collections/CollectionsService.java`: tier-grant journal is flushed before payout
  (`EclipseSavedData.flushOverworld`); payouts routed through idempotent destinations
  (`SkillsApi.grantOnce`, `grantShardsOnce` backed by the `SHARD_GRANT_RECEIPTS` attachment in
  `registry/EclipseAttachments.java`); journal cleared only after payout persisted; crash recovery
  replays idempotently.

### 1.10 `PENDING_HEART_LOSSES` clear — **CLOSED**
- `lives/LifecycleEvents.java` `onServerStopped` clears the static map (no leak across
  server restarts in the same JVM / integrated-server relaunch).

### 1.11 `limbo.fsh` facing/eps/VoyageOffset — **CLOSED**
- `pinwheel/shaders/program/limbo.fsh`: `eps` growth capped at 1.65; both camera-height and
  downward-ray facing gates rewritten as ascending-edge `smoothstep`.
- `veilfx/LimboAmbience.java`: `VoyageOffset` derived continuously from limbo-entry time (no hourly
  wrap jump).

### 1.12 Credits shadowless text — **CLOSED**
- `client/loading/EclipseLoadingScreen.java`: `renderCreditsWhite` →
  `drawCenteredNoShadow` (explicit shadow-off draw path).

### 1.13 DE micro-fixes — **CLOSED**
- `assets/eclipse/lang/de_de.json`: "Ein Riss ächzt" (no "auf"), plural "Macht euch bereit",
  arena takedowns "ausgeschaltet". Key parity EN/DE: 2144 = 2144.

---

## 2. v6 eval-fix wave claims (EVAL-V6-*)

### EVAL-V6-FX
1. **GLSL reverse smoothstep sweep — FIXED.** `sun_halo.fsh` and `storm_interior.fsh` descending
   ramps rewritten as `1.0 - smoothstep(lo, hi, x)` (comment at `sun_halo.fsh` line 83 documents the
   rule). Repo-wide scan: no remaining `smoothstep(hi, lo, x)` call sites with constant reversed edges.
2. **`altar_indraw` codec keys — FIXED.** `quasar/emitters/altar_indraw.json`
   `veil:point_attractor` now camelCase (`localPosition`, `strengthByDistance`,
   `invertDistanceModifier`); `veil:vortex` keeps its documented snake_case `local_position`.
3. **`rift_glitch` NaN guard — FIXED.** Mirror-shard branch gated by
   `if (shardZone > 0.003 && lensDist > 1.0e-4)` — no `atan(0,0)` at dead center.

### EVAL-V6-CUTBD
4. **EndShatter debris chunk-load sweep — FIXED.** `worldgen/end/EndShatterSequence.java`
   `sweepDebris` covers loaded chunks at `ServerStartedEvent`; `onEntityJoin` discards
   `DEBRIS_TAG`-tagged entities not in `LIVE_DEBRIS` as their chunks load later.
5. **ArenaFight per-piece stagger — FIXED.** `ferryman/ArenaFight.java` `pushMorphKeyframe`
   computes `setTransformationInterpolationDelay/Duration` per piece from its launch tick.
6. **END preload ack gating — FIXED.** `beatZeroGameTime` armed by first
   `C2SCutsceneReadyPayload` ACK via `CutsceneService.onNextClientReady`, with
   `PRELOAD_TIMEOUT_TICKS` fallback.
7. **Flyover crossing clamp — FIXED.** `sequence/ExpansionSequence.java` `resolveGrowthFront`
   derives `skimRadial` from `pathOffsetAt` and clamps `anchorR` so the camera geometry-guarantees
   the wave crossing.
8. **Credits caption timing + hash appended — FIXED.** `cutscenes/credits_helm.json` wheel caption
   at `t=0.77` (matches `CreditsSequence.WHEEL_SETTLE_AT = 148`); `cutscene/CutscenePaths.java`
   `LEGACY_DEFAULT_HASHES` includes the pre-fix hash
   `a0efa5f9…459d3e04` so edited saves don't false-positive as user-customized.

### EVAL-V6-PHOTON
9. **Growth-rider reducedFx/dimension cleanup — FIXED.** `ExpansionSequence.ClientHooks.tickRiderRibbon`
   checks Photon `available()` each tick (reducedFx kills ribbon); `onClone`/`onLoggingOut` call
   `releaseRiderRibbon(false)`.
10. **Credits replay parity — FIXED.** `ritual/CreditsSequence.java` `replay` (CORRECTION phase)
    sends `FX_SHOCKWAVE` + `CUE_CREDITS_BURST`, matching live `beatBurst`.
11. **AutoRotate name-based resolve — FIXED.** `veilfx/PhotonBridge.java` resolves
    `AUTO_ROTATE_NONE/FORWARD/LOOK/XROT` by enum name (`autoRotateByName`), falling back to `NONE`.
12. (Adjacent §7.6) `veilfx/HeraldFerrymanFxRows.java` `heraldShardTrail` uses
    `>= MAX_ENTITY_EXECUTORS_FOR_TRAIL` — seventh executor no longer admitted.

### EVAL-V6-MOB
13. **Warden/tyrant death arc lengths — FIXED.** `RiftWardenEntity.DEATH_DURATION_TICKS = 60`,
    `FogTyrantEntity.DEATH_DURATION_TICKS = 70`; death `animation_length` in
    `rift_warden.animation.json` / `fog_tyrant.animation.json` match (3.0 s / 3.5 s at 1×).
14. **Wisp double-rotation — FIXED.** `fog_tyrant.geo.json` wisp bones carry the rest roll (−8/8);
    idle animation Z-rotations are zero-centered sines; action clips start/end at 0.
15. **Hound glowmask — FIXED.** `glitched_hound_glowmask.png` + `_alt_` variant: 0 glow pixels over
    fully transparent albedo (pixel-level scan).
16. **Fractional UVs — FIXED.** `deckhand.geo.json`, `wizard_orin.geo.json`,
    `drift_lantern.geo.json` use per-face integer UV rects; geo validator reports 0 warnings.

### EVAL-V6-RACES / EVAL-V6-COMPLETE
17. **Kinetics producer — FIXED.** `QuestDetectors.detectKineticsBuilt` (from `handleBlockPlaced`)
    sets `EclipseWorldState.kineticsBuilt`; `QuestEngine.evaluateBuiltinBeat` polls
    `world.isKineticsBuilt()` for `create_kinetics_built`.
18. **Wand progress sync — FIXED.** `S2CWandProgressPayload` registered in
    `network/wand/WandPayloads.java`; `wand/WandProgressSync.syncTo` pushes server config values;
    `client/wand/ClientWandProgress` caches; `WandProgressPanel` shows "syncing" until first payload.
19. **Sound aliases registered — FIXED.** `registry/EclipseSounds.java` registers
    `EVENT_BOSS_DOWN`, `UI_CHIME`, `UI_STAMP`; `drama/BossDownSting.java` and
    `client/handbook/UiSounds.java` resolve through them. All 35 OGGs present; every
    `sounds.json` entry (incl. `storm_shatter`) resolves to an existing `eclipse` OGG.
20. **SEAM cleanup — FIXED.** `rg "// SEAM" src/main/java` → 0 hits.

Residual (documentation only, pre-existing, not a v6 fix claim): `INTEGRATION.md`/`API.md` still
contain drifted/self-contradictory Photon + `fxlib.py` prose. No functional impact; all 68 `.fx`
files pass the deepened `tools/photon/fxlib.py` validation.

---

## 3. Spot-checks of 10 older DONE features (v6 regression sweep)

Selection biased toward features sharing files/assets with v6 edits (shaders, quasar emitters,
geo/animation JSONs, cutscene/END code, handbook sounds).

| # | Feature (catalog item) | Verdict | Evidence |
|---|---|---|---|
| 1 | Supply-drop beam disappears after loot (early #9) | INTACT | `economy/SupplyBeacon.java`: `REMOVE_FADE_TICKS = 40`, remove-marker payload `S2CSupplyMarkerPayload(false, beamPos, REMOVE_FADE_TICKS)` still sent on loot/break/expiry. |
| 2 | Sun halo aligned with purple sun (early #26) | INTACT | `VeilPostController` still feeds `pipeline.getUniform("SunScreen").setVector(SunTracker.sunScreen())`; `sun_halo.fsh` retains `uniform vec4 SunScreen` after the v6 smoothstep edits. |
| 3 | Event-start wave effect v2 (early #17) | INTACT | `client/WaveOverlay.java`: `eclipse:shockwave` pipeline id, world-anchored `ShockCenter` reprojection, Iris/reducedFx fallback all present. |
| 4 | Ship oars 60-tick row loop (early #29) | INTACT | Post-v6-UV-edit cross-check: every bone referenced by all 7 `deckhand.animation.json` clips exists in `deckhand.geo.json` (0 dangling); `animation.deckhand.row` length = 3.0 s (60 ticks). |
| 5 | Cutscene caption visibility (early #28) | INTACT | `cutscene/client/CaptionRenderer.java`: caption layer registered above letterbox, on the letterbox whitelist; queue cap + stop/disconnect clearing documented and present. |
| 6 | End crash announcement (early #14) | INTACT | `worldgen/end/EndDiscService.java` (same package as heavy v6 EndShatter edits): `announceCrash` still sends `S2CEndCrashPayload` + double `ENDER_DRAGON_GROWL` (vol 4.0 / MASTER 1.4). |
| 7 | Deckhand bench identity + calmCrew (early #21) | INTACT | `entity/DeckhandEntity.java`: 73 hits for `calmCrew|bench|reconcile` — bug 4a/4b machinery untouched. |
| 8 | Altar multi-cost milestones (early #24) | INTACT | `ritual/AltarBlockEntity.java`: 32 hits for `altar_level_|milestone` — per-item counter keys and milestone costs intact. |
| 9 | Border FX only visible nearby (early #11) | INTACT | `border/client/BorderFxRenderer.java`: `fxIntensity`/`fxRange` gating present (6 hits). |
| 10 | Handbook UI sound suite (early #27) | INTACT | `client/handbook/UiSounds.java` plays via registered aliases (`"ui.chime"` etc.) with vanilla fallbacks — consistent with the v6 sound-alias fix, no regression. |

Asset-integrity sweeps (regression net for the v6 parallel edits):
- All 65 `assets/eclipse/quasar/**/*.json` parse.
- All `geo/**`, `animations/**`, `cutscenes/*` JSONs parse.

---

## 4. Bottom line

- 12 / 13 previously-PARTIAL/MISSING items **CLOSED**; 1 **PARTIAL** (cobblestone
  `dailyCreditCap` 600 vs required 1500 — one-line constant change in
  `collections/CollectionsConfig.java`, plus its migration default).
- 19 / 19 v6 eval-fix defect groups verified **FIXED** as claimed.
- 10 / 10 spot-checked older DONE features **INTACT** — no regressions found from the v6 waves.
- Non-blocking residual: `INTEGRATION.md` / `API.md` Photon documentation drift.
