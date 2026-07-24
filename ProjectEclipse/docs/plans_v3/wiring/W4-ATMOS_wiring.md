# W4-ATMOS wiring notes — atmosphere quick wins (IDEA-15 / IDEA-18 / IDEA-14 / IDEA-07)

**No hub edits by this worker.** `EclipseSounds`, `sounds.json`, `FxPayloads`, `UiSounds`,
`DeathFlowController` and `HeraldEntity` were NOT touched — everything that needs them is a
documented ask below, and every consumer **self-heals**: the new loop classes and
`XboxPortal` resolve the ledger ids from the sound registry at play time and fall back to
shipped events re-pitched (the `UiSounds.play(String, ...)` pattern), and the new-land glow
degrades to a debug log until its 2-line dispatch lands.
Langdrop: `docs/plans_v3/langdrop/W4-ATMOS.json` (6 subtitle keys × en/de).

## What landed

### FOG STORM (IDEA-15, top 3 + prerequisite idea 6)
- `stormfx/StormInteriorFx.java` — **vortex interior clamp fix** (idea 6, EVAL-4 interior
  over-reach): `interiorTargetAt` now evaluates vortex-type storms against the **tilted**
  radius at camera height (`StormWallRenderer.TAN_TILT`, made package-visible for this),
  so looking down on a vortex from above no longer engages interior fog. Plus EVAL-4's M5
  **teleport snap**: a >32-block camera jump or a `ClientPlayerNetworkEvent.Clone` snaps
  `smoothedInterior`/`smoothedApproach` instead of easing (fast release on teleport-out).
- `stormfx/StormFxClient.java` — **approach dread ladder**: `tickApproachDread` off
  `tickStorm`'s `shellDist` — warden-heartbeat cadence lerps 50→22 ticks over 60→20 blocks
  (echo thump inside 20), ground fog tendrils crawl from the wall base at ≤40 blocks and
  ring the player's feet at ≤20; approach amount also pre-tints fog color (max 15%).
- `stormfx/StormInteriorFx.java` — **interior lightning silhouette reveals**: interior
  strikes/arcs call `flash(4..6)`; while `flashTicks > 0` the interior fog far plane lifts
  24→56 and the fog color blows toward violet-white for those 4–6 ticks.
- `stormfx/StormInteriorFx.java` — **loot-camp warm glow**: one `FxBudget.tryLight`-budgeted
  point light + `SMALL_FLAME` embers at the storm-center camp while `interior > 0.6`,
  released on interior drop / distance / teleport / logout.

### LIMBO (IDEA-18, top 3)
- `client/sky/LimboSpecialEffects.java` — **eclipse water reflection**: additive streak
  quad on the water plane below `zenithWorldPoint` in `renderSky` (height-faded), plus the
  free screen-space smear in `assets/eclipse/pinwheel/shaders/program/limbo.fsh` (mirrors
  the existing `GodrayDir` uniform across the horizon — **zero new uniforms**, §3.3 frozen).
- `client/sky/LimboHorizonShips.java` (NEW) — **silhouette ships that vanish when
  observed**: 3 black hull+mast silhouettes with soul-green stern lanterns at sky distance,
  drawn after `GREEN_STARS.draw` inside the same no-fog window; look-dot fade with a
  one-way latch, then a deterministic `ECLIPSE_SEED`-hashed reseed after 1200–2400 ticks.
- `assets/eclipse/quasar/emitters/limbo_fogbank.json` (NEW) + one `Window` line in
  `veilfx/LimboAmbience.java` — **fog banks rolling past** (wind-driven 20-block wisps,
  alpha ≤ 0.08).

### EXPANSION (IDEA-14, top 3)
- `worldgen/stage/RingGrowthService.java` (wave pulse only) — **per-player distance-scaled
  shake** (0.08→0.5 by radial closeness to the wave ring) replacing the old flat dimension
  broadcast.
- `sequence/ExpansionSequence.java` (FX beats only) — **once-per-sweep underfoot shock**:
  `ClientHooks.handleWavePulse` latches the first wave crossing per player and fires a
  local shockwave + `growth_dust_wall` burst; **slam dust rings at t+6/t+12** + **debris
  rain** (`assets/eclipse/quasar/emitters/slam_debris.json`, NEW gravity emitter) from
  `slamFx`/`slamBeat`, with **replay parity** in `replay("STRUCTURES")`.
- **post-expansion new-land glow**: `beginEnd` sends one `eclipse:fx/new_land_glow` cue
  (a = innerR, b = outerR); `veilfx/EclipseFxState.java` stores the band + a 12000-tick
  age fade; `ClientHooks.onClientTick` spawns AMBIENT-channel `map_expand_materialize`
  motes on the fresh annulus scaled by `1 − age/12000`. Needs the **FxPayloads ask** below.

### SOUND (IDEA-07, top 3 + notable finds)
- `client/sound/SanctumHum.java` (NEW) — positional aura loop at `FxAnchors.ALTAR_CENTER`,
  `volume = altarAberration() × (0.4 + 0.6 × verticalFactor)` (crater floor → island rim
  via `FloatingSanctumBuilder.islandTopY/ISLAND_LIFT`), plus one-shot `event.emerge`
  glide-notch whooshes (pitch 1.4, vol 0.6) off the frozen `glideLedges` geometry.
  Fallback while the alias is pending: `AMBIENT_LIMBO_LOOP` @ 1.3.
- `client/sound/BorderStaticSound.java` (NEW) + a 2-line hook in
  `border/client/BorderFxRenderer.onClientTick` — **soft-border static whisper**,
  `volume = borderProximity² × 0.5`. Fallback: `EVENT_BORDER_GLITCH` @ 0.4.
- `xboxevent/XboxPortal.java` (sound lines only) — placeholders dropped per the
  `EVENT_RIFT_OPEN` registry comment: open → `EVENT_RIFT_OPEN`, close →
  `EVENT_RIFT_SLAM`, periodic ambient → runtime-resolved `event.xbox_portal_loop`
  (fallback `EVENT_BEAM_HUM` @ 1.15).
- **Herald `_far` layers** and **`ui.door_open`**: pure asks below (files not owned).

---

## ASK 1 — `sounds.json` alias rows (listed exactly)

Six new entries, all re-pitches/layers of shipped oggs (no new binary assets). Keep the
alphabetical key order of the file; every row keeps the subtitle invariant.

```json
"ambient.border_static": {
  "sounds": [
    {
      "name": "eclipse:event/border_glitch",
      "pitch": 0.4,
      "volume": 0.5
    }
  ],
  "subtitle": "subtitles.eclipse.ambient.border_static"
},
"ambient.sanctum_hum": {
  "sounds": [
    {
      "name": "eclipse:ambient/gazer_whisper",
      "pitch": 0.55,
      "volume": 0.5
    },
    {
      "name": "eclipse:ambient/limbo_loop",
      "pitch": 1.3,
      "stream": true,
      "volume": 0.3
    }
  ],
  "subtitle": "subtitles.eclipse.ambient.sanctum_hum"
},
"boss.herald_roar_far": {
  "sounds": [
    {
      "attenuation_distance": 96,
      "name": "eclipse:boss/herald_ambient",
      "pitch": 0.5,
      "volume": 0.7
    }
  ],
  "subtitle": "subtitles.eclipse.boss.herald_roar_far"
},
"boss.herald_telegraph_far": {
  "sounds": [
    {
      "attenuation_distance": 64,
      "name": "eclipse:boss/herald_telegraph",
      "pitch": 0.75,
      "volume": 0.9
    }
  ],
  "subtitle": "subtitles.eclipse.boss.herald_telegraph_far"
},
"event.xbox_portal_loop": {
  "sounds": [
    {
      "attenuation_distance": 24,
      "name": "eclipse:ambient/gazer_whisper",
      "pitch": 1.35,
      "volume": 0.4
    }
  ],
  "subtitle": "subtitles.eclipse.event.xbox_portal_loop"
},
"ui.door_open": {
  "sounds": [
    {
      "name": "eclipse:ui/page_turn",
      "pitch": 0.55,
      "volume": 0.8
    }
  ],
  "subtitle": "subtitles.eclipse.ui.door_open"
}
```

Note `ambient.sanctum_hum` is the mod's **first multi-entry sounds array** (two-layer bed);
vanilla plays all entries of the array together, which is the intended blend.

## ASK 2 — `registry/EclipseSounds.java` W4-ATMOS block

Add after the P2-W1 FX suite (before the Quiet-Eclipse `uiEvent` block):

```java
// W4-ATMOS sound suite (IDEA-07 §1/§2/§3/§7) — all aliases of shipped oggs.

/** Sanctum aura hum loop (client.sound.SanctumHum resolves it at runtime, self-healing). */
public static final Supplier<SoundEvent> AMBIENT_SANCTUM_HUM = SOUNDS.register(
        "ambient.sanctum_hum",
        () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.sanctum_hum")));

/** Soft-border static whisper loop (client.sound.BorderStaticSound, relative bed). */
public static final Supplier<SoundEvent> AMBIENT_BORDER_STATIC = SOUNDS.register(
        "ambient.border_static",
        () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.border_static")));

/** Distant low howl layered under the Herald summon roar (heard disc-wide). */
public static final Supplier<SoundEvent> BOSS_HERALD_ROAR_FAR = SOUNDS.register(
        "boss.herald_roar_far",
        () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_roar_far")));

/** Muffled far-shell volley telegraph for players kiting outside the arena. */
public static final Supplier<SoundEvent> BOSS_HERALD_TELEGRAPH_FAR = SOUNDS.register(
        "boss.herald_telegraph_far",
        () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_telegraph_far")));

/** Periodic hum of the xbox portal (xboxevent.XboxPortal resolves it at runtime). */
public static final Supplier<SoundEvent> EVENT_XBOX_PORTAL_LOOP = SOUNDS.register(
        "event.xbox_portal_loop",
        () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.xbox_portal_loop")));
```

And close the W1-ledger gap in the Quiet-Eclipse block (the ONLY ledger id missing —
`UiSounds`' javadoc already promises it):

```java
/** Ship door creak of the death-flow door beat (W1-ledger id). */
public static final Supplier<SoundEvent> UI_DOOR_OPEN = uiEvent("ui.door_open");
```

No consumer waits on these constants — `SanctumHum`, `BorderStaticSound` and `XboxPortal`
resolve by id and pick the real events up automatically once registered.

## ASK 3 — `entity/boss/HeraldEntity.java` (two playSound lines, IDEA-07 §2)

**Summon roar** — in `summon(...)`, directly after the existing
`BOSS_HERALD_AMBIENT` line (~line 254):

```java
level.playSound(null, altarPos, EclipseSounds.BOSS_HERALD_AMBIENT.get(), SoundSource.HOSTILE, 1.2F, 0.8F);
// W4-ATMOS (IDEA-07 §2): disc-wide low howl under the full-band arena roar.
level.playSound(null, altarPos, EclipseSounds.BOSS_HERALD_ROAR_FAR.get(), SoundSource.HOSTILE, 1.0F, 1.0F);
```

**Volley telegraph** — directly after the existing `BOSS_HERALD_TELEGRAPH` line
(~line 525, in the telegraph-start branch):

```java
level.playSound(null, this.blockPosition(), EclipseSounds.BOSS_HERALD_TELEGRAPH.get(),
        SoundSource.HOSTILE, 1.0F, 1.0F);
// W4-ATMOS (IDEA-07 §2): muffled far-shell tell for players kiting outside the arena.
level.playSound(null, this.blockPosition(), EclipseSounds.BOSS_HERALD_TELEGRAPH_FAR.get(),
        SoundSource.HOSTILE, 1.0F, 1.0F);
```

The per-listener distance layering is done by the aliases' `attenuation_distance` (96/64)
against the base events' shorter effective ranges — same mechanism as
`event.lightning_close`/`_far` in `IntroLightningPhase`.

## ASK 4 — `network/fx/FxPayloads.java` (new-land glow dispatch, IDEA-14 §3)

Add the frozen id next to the other `FX_*` constants:

```java
/** pos unused (Vec3.ZERO), a = innerR, b = outerR of the fresh annulus (W4-ATMOS). */
public static final ResourceLocation FX_NEW_LAND_GLOW = fx("new_land_glow");
```

Add the dispatch in `handleFxEvent`, before the final `else` (lazy client resolve like its
neighbors):

```java
} else if (FX_NEW_LAND_GLOW.equals(id)) {
    dev.projecteclipse.eclipse.sequence.ExpansionSequence.ClientHooks
            .handleNewLandGlow(payload.a(), payload.b());
```

`ExpansionSequence` sends the byte-identical id `eclipse:fx/new_land_glow` from a local
constant (its javadoc marks the swap); after this ask lands, that local constant can be
replaced with `FxPayloads.FX_NEW_LAND_GLOW` — no behavior change either way. Until then the
cue hits the debug-log fallback and the glow is simply absent (graceful degrade).

## ASK 5 — `ui.door_open` consumers (IDEA-07 §8)

`client/handbook/UiSounds.java`, with the other §2.3 self-healing helpers:

```java
/** Ship door creak of the death-flow door beat (W1-ledger id, self-healing fallback). */
public static void doorOpen() {
    play("ui.door_open", 1.0F, 0.8F, EclipseSounds.UI_PAGE_TURN, 0.55F);
}
```

`client/death/DeathFlowController.java`, the `PHASE_DOOR_OPEN` case of the phase switch
(~line 114) — one call on phase entry, matching the `ShipDoorGlow` visual:

```java
case DeathFlowPayloads.PHASE_DOOR_OPEN -> {
    if (theaterOn()) {
        dev.projecteclipse.eclipse.client.handbook.UiSounds.doorOpen();
        prompt("message.eclipse.death.door_opening");
    }
}
```

## Coordination notes

- `sequence/ExpansionSequence.java`: W4-ATMOS owned ALL FX-beat edits this wave per the
  coordination rule — no other worker should have touched it.
- `stormfx/StormWallRenderer.TAN_TILT` went `private` → package-visible (same value) so
  `StormInteriorFx` clamps against the tilted vortex radius; no external contract change.
- `border/client/BorderFxRenderer.java` carries exactly the 2-line whisper hook + import;
  `xboxevent/XboxPortal.java` only its three sound call sites (+ the runtime-resolve
  constant); everything else in those files is untouched.
- Budgets: slam rings/debris ride the existing SEQUENCE channel spawns; new-land motes are
  AMBIENT-channel and `reducedFx`-halved; the camp glow light goes through
  `FxBudget.tryLight`. The three sound loops are one instance each, charged to nothing
  (IDEA-07 ground rule), and all inherit `LastMinuteHush` ducking for free.

## Risks

1. **Sanctum hum before the alias lands** — the fallback (`limbo_loop` @ 1.3) is airier
   than the intended two-layer bed; correct swell behavior, placeholder timbre. Same class
   of degrade as every `UiSounds` ledger fallback.
2. **`ambient.sanctum_hum` two-layer bed** — first multi-entry `sounds` array in the mod;
   if the integrator prefers single-layer, dropping the `limbo_loop` entry is safe (the
   class plays whatever the alias defines).
3. **Vortex clamp** — interior detection for vortices is now strictly tighter (tilt-reduced
   radius, never wider); anyone relying on the old over-reach (none found in-tree) would
   see interior FX engage slightly later.
4. **Horizon ships** — deterministic and purely cosmetic, but they assume the stars'
   no-fog window in `renderSky` stays where it is; if the sky pass is reordered, keep
   `LimboHorizonShips.draw` inside the fog-off region.
5. **New-land glow is transient by design** — a rejoin during the ~10 min fade loses the
   band (matches the grade's behavior); documented in `beginEnd`.
