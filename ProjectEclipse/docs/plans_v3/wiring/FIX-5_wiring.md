# FIX-5 wiring notes (idea-round quick wins, IDEAS-A #1/#2/#4/#5 + IDEAS-C #1/#2/#3)

## What shipped (self-contained, no owner action required to function)

- `client/drama/LastMinuteHush` — pre-rollover hush off the `S2CDayClockPayload` cache
  (`DayTimerCache`). Ducks the master listener gain via
  `SoundManager.updateSourceVolume(MASTER, …)` (MusicManager has no public volume API; its
  `CueSound` volume is crossfade-owned), dims the screen ≤ 15% via an OWN GUI layer
  (registered below `VanillaGuiLayers.CROSSHAIR` from a nested mod-bus registrar — no
  `EclipseGuiLayers` edit), and accelerates a quiet warden heartbeat over the last 10 s.
  Gates: `CameraDirector.isActive()`, day-clock armed/unpaused, `reducedFx` (dim +
  heartbeat off), `heartbeatSound`, F1.
- `drama/FirstBloodService` — first-ever player death: anonymous
  `announce.eclipse.first_blood.title` announcement (STYLE_BOSS, empty subtitle = "type the
  title"), global `S2CShakePayload.shake(0.35, 16)`, one deep `BELL_RESONATE` toll per
  player. Latch persists in its OWN SavedData `data/eclipse_first_blood.dat`
  (`EclipseSavedData.getOverworld`; `EclipseWorldState` untouched).
- `drama/WitnessedLossService` — pure event subscriber bracketing
  `LifecycleEvents.onLivingDeath` (HIGHEST snapshots `LivesApi.get`, LOWEST compares):
  a real MAX-heart loss sends every player within 24 blocks `S2CShakePayload.mark(24)`
  (→ existing `MarkVignetteOverlay` pulse) + a muffled `ui.heart_shatter` at volume 0.4 /
  pitch 0.6. Public seam: `WitnessedLossService.onHeartLost(ServerPlayer)`.
- `client/drama/LastHeartEmber` — OTHER players at exactly 1 heart wear a faint
  `eclipse:door_glow_motes` loop via `QuasarSpawner.ensureAttached(…, AMBIENT)`. Lives are
  read WITHOUT a new packet: `HeartsService` projects hearts onto MAX_HEALTH
  (`hearts × 2 − 20`), which vanilla syncs to tracking clients — synced max health ≈ 2.0
  is the 1-heart band (0-heart ghosts clamp to 1.0 and are excluded).
- `client/entity/glitch/GlitchedGeoRenderer` (owned for this task) — `hurtTime ≥ 8` ORs
  into `isAltFrame` (~3 t corruption pop per hit, ≥ 8 t guard held by vanilla
  invulnerability) + one tiny `rift_spark` puff on the first hurt frame (nested
  `HurtSparks` manages the loop-emitter handles, BURST-budgeted, 8 t lifetime).
- `client/drama/AltarIdleMotes` — LimboAmbience-style rolling window of ≤ 3
  `door_glow_motes` loops around `FxAnchors.ALTAR_CENTER` within 64 blocks (72 release
  hysteresis), AMBIENT channel, overworld-gated, fully paused (released) under `reducedFx`.
- `client/drama/HorizonLightning` — every 30–90 s (doubled under `reducedFx`) one silent
  `StormFxClient.strikeLightning` at a random azimuth 120–180 blocks out, intensity
  0.15–0.3, overworld + `dayFactor < 0.1` only, skipped during `CameraDirector.isActive()`,
  `stageAnimating*` and any non-NONE `EclipseFxState.eclipsePhase()`; each beat pre-charges
  one `FxBudget` AMBIENT slot.

## Lang

- `docs/plans_v3/langdrop/FIX-5.json` → merge `announce.eclipse.first_blood.title`
  (en: "Someone has fallen." / de: "Jemand ist gefallen.") into
  `assets/eclipse/lang/en_us.json` + `de_de.json`. No other keys.

## Diffs for owners of other-active-worker files (optional, small)

Witnessed heart-loss currently covers the death path only (event-bracketing needs no
seam). The two NON-death permanent-heart-loss sites are owned elsewhere; to ripple those
too, add one line after each `LivesApi.add(player, -…)`:

1. `ritual/AltarBlockEntity` (heart sacrifice, ~line 271):

```java
        LivesApi.add(player, -1);
+       dev.projecteclipse.eclipse.drama.WitnessedLossService.onHeartLost(player);
```

2. `ritual/HeartExtractorItem` (~line 89):

```java
        int heartsAfter = LivesApi.add(player, -HEART_COST);
+       dev.projecteclipse.eclipse.drama.WitnessedLossService.onHeartLost(player);
```

## EclipseMod / sounds.json asks

- **None required.** All audio reuses shipped events: `BELL_RESONATE` (first-blood toll —
  same family as the mark bell), `WARDEN_HEARTBEAT` (hush heartbeat — the
  `HeartBurstOverlay` precedent), `ui.heart_shatter` re-pitched 0.6 (muffled witness
  shatter). Horizon bolts are deliberately silent (IDEAS-C #1 "silent violet bolts";
  `strikeLightning` is visual-only by contract).
- **Optional polish aliases** (the established `sounds.json` re-pitch trick), if the
  integrator wants dedicated ids later — drop-in, no code changes needed if named:
  - `event.first_blood_bell` → alias a bell/deep OGG (replaces the vanilla toll in
    `FirstBloodService`).
  - `event.heart_shatter_far` → alias `ui.heart_shatter` at pitch 0.6 / volume 0.5
    (replaces the re-pitch in `WitnessedLossService`).

## Notes / known trade-offs

- `MarkVignetteOverlay.trigger` also tolls its own bell client-side on a fresh mark, so
  witnesses hear bell + muffled shatter. Acceptable per the "reuse the marked payload"
  order; a dedicated quieter payload variant would be the refinement if the double cue
  reads too loud in playtests.
- The hush duck sets the sound-engine listener gain (master) each tick from the CURRENT
  options value and restores it on release/disconnect; it never writes options, so a
  crash can at worst leave one session's gain ducked until the next volume change.
- `LastHeartEmber` needs no reducedFx special-case: `FxBudget` tier 0 disables the
  AMBIENT channel outright and tier 1 halves it.
