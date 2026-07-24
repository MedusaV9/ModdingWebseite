# IDEA-07 — Sound Design & Audio Layering (Wave 4, collector 7/20)

**Scope:** `registry/EclipseSounds` + `assets/eclipse/sounds.json` aliases, ambient loops, UI sounds (`client/handbook/UiSounds`), event stingers.
**Ground rules honored:** the codebase's established "no new binary assets" convention — every idea below is either pure alias re-pitching of the 15 shipped oggs (the `event.beam_hum` = gazer_whisper@1.2 trick) or reuses the two proven loop templates (`LimboAmbience.LimboLoopSound` relative fade loop, `StormFxClient.StormLoopSound` positional visibility-scaled loop). Sizes: S = one class/file touch, M = new small client system.

---

## Ranked ideas

| # | Idea | Size | New oggs |
|---:|---|---|---|
| 1 | Sanctum aura hum that swells as you glide up | M | 0 |
| 2 | Distance-layered Herald roar & telegraph (close/far shells) | S | 0 |
| 3 | Soft-border static whisper (proximity loop) | S | 0 |
| 4 | Per-biome night ambience beds via alias pitching | M | 0 |
| 5 | Storm-interior sub-drone bed | S | 0 |
| 6 | Boss-down stinger (Herald/Ferryman kill release) | S | 0 |
| 7 | Xbox portal audio identity (drop vanilla placeholders) | S | 0 |
| 8 | Close the `ui.door_open` ledger gap (ship door creak) | S | 0 |
| 9 | Supply-beam countdown crackle ramp | S | 0 |
| 10 | Gazer outer "presence" halo (dual-ring whisper) | S | 0 |

---

### 1. Sanctum aura hum that swells as you glide up — **M**

The floating sanctum already publishes a perfect audio driver that nothing listens to: `client/AltarAberration` eases a radial 0..1 zone strength into `EclipseFxState.setAltarAberration()` (strongest at the altar, slewed over ~EASE_TICKS so it never pops). Add `veilfx/SanctumHum`, a positional `AbstractTickableSoundInstance` cloned from `LimboAmbience.LimboLoopSound`, anchored at the altar column, with per-tick `volume = altarAberration() * (0.4 + 0.6 * verticalFactor)` where `verticalFactor` ramps from ground Y to `FloatingSanctumBuilder.islandTopY(altarPos)` — so the hum literally swells as you rise past the underside strata and crests at the rim.

- **Alias:** `ambient.sanctum_hum` → `eclipse:ambient/gazer_whisper` pitch 0.55 vol 0.5 **layered with** `eclipse:ambient/limbo_loop` pitch 1.3 vol 0.3 `stream:true` (sounds.json supports multi-entry `sounds` arrays; first use of two-layer beds in the mod).
- **Glide-notch garnish:** the four launch ledges are frozen geometry (`FloatingSanctumBuilder.glideLedges`, `GLIDE_NOTCH_ANGLES = {45,135,225,315}`) — P2's glide FX hook can fire a one-shot `event.emerge` alias pitched 1.4 vol 0.6 when a player crosses a ledge AABB moving outward (same class, tiny AABB check).
- **Lifecycle:** copy `LimboAmbience`'s `soundStartedThisVisit` + `LoggingOut` reset pattern verbatim; charge nothing to `FxBudget` (one sound instance).

### 2. Distance-layered Herald roar & telegraph — **S**

The mod already proved the close/far split with `event.lightning_close` / `event.lightning_far` (border_glitch at pitch 0.55 vs 0.35, chosen per-listener in `IntroLightningPhase` line ~177). Apply the same layering to the Herald:

- **Summon roar** (`HeraldEntity.summon`, line ~243, currently a single `BOSS_HERALD_AMBIENT` at vol 1.2): also play a new `boss.herald_roar_far` — alias of `eclipse:boss/herald_ambient` pitch 0.5 vol 0.7 with `"attenuation_distance": 96` in sounds.json — so the whole disc hears a low distant howl when the fight starts, while arena players get the full-band roar.
- **Volley telegraph** (`HeraldEntity`, line ~497): add `boss.herald_telegraph_far` (same ogg, pitch 0.75, attenuation 64) played alongside; players kiting outside the arena still hear the "shoot me now" tell as a muffled chime instead of silence.
- Registry: two `SoundEvent.createVariableRangeEvent` entries in `EclipseSounds` W11 block + two sounds.json rows + two subtitle lang keys. No entity code beyond the two `playSound` lines.

### 3. Soft-border static whisper — **S**

`BorderFxRenderer` computes border proximity every client tick and feeds `EclipseFxState.setBorderProximity()` (0 = far, 1 = touching, already synced fx range from `S2CBorderPayload`). Today audio only fires *after* a pushback (`SoftBorder.playGlitchFeedback`, line ~596). Add a `BorderStaticSound` loop (LimboLoopSound pattern, `SoundSource.AMBIENT`, `relative = true`) owned by `BorderFxRenderer`'s tick handler: `volume = borderProximity()² * 0.5`, started when proximity > 0.05, faded out below.

- **Alias:** `ambient.border_static` → `eclipse:event/border_glitch` pitch 0.4 vol 0.5 (the 15.7 KB ogg loops acceptably at low pitch/volume as a static bed; `stream` unnecessary at that size).
- Squaring the proximity keeps it a whisper until the last few blocks — an audible "you are grinding the edge of the world" warning that precedes the W7 pushback burst instead of duplicating it.

### 4. Per-biome night ambience beds via alias pitching — **M**

New `veilfx/NightAmbience` client ticker (LimboAmbience template): active only in `Level.OVERWORLD`, `level.isNight()`, and after event start (gate on `ClientStateCache` world-stage flag, the same source `MusicManager.naturalCue` reads). Sample `level.getBiome(player.blockPosition())` every ~40 ticks and map biome **tags** (`is_forest`, `is_savanna`/plains, desert, swamp/jungle) to one of 3–4 alias beds — all re-pitches of the two shipped ambient oggs:

- `ambient.night_forest` → gazer_whisper pitch 0.7 vol 0.35 (breathy, close)
- `ambient.night_open` → limbo_loop pitch 1.15 vol 0.25 `stream:true` (thin, airy)
- `ambient.night_wet` → limbo_loop pitch 0.85 vol 0.3 `stream:true` (swampy low wash)
- `ambient.night_dry` → gazer_whisper pitch 0.45 vol 0.3 (desert hiss)

Crossfade by holding two `LoopSoundInstance`s (incoming fadeIn / outgoing fadeOut — the exact `MusicManager.transitionTo` shape, minus the music channel). Registered as fixed `createVariableRangeEvent`s in a new "W4 night beds" block of `EclipseSounds`. Respect `reducedFx()`? No — sound is cheap; instead gate on the existing `uiSounds`-style client config with a new `nightAmbience` toggle in `EclipseClientConfig` (one line, follows `uiSoundVolume` precedent).

### 5. Storm-interior sub-drone bed — **S**

`EclipseFxState.stormInterior()` already carries a 0..1 "inside the fog-storm" scalar (fed by `StormInteriorFx`), but only shaders consume it. Add one relative loop instance owned by `StormFxClient` (which already manages `StormLoopSound` lifecycles): `volume = stormInterior() * 0.7`, event alias `event.storm_interior` → `eclipse:ambient/limbo_loop` pitch 0.5 vol 0.8 `stream:true` — a claustrophobic sub-drone that exists only inside the wall, layering under the positional churn loop (which sits on the shell via `StormLoopSound.updatePosition`). Interior + churn + existing `event.lightning_far` strikes = three-deep storm mix with zero new assets.

### 6. Boss-down stinger — **S**

Kills currently end with the music crossfading to silence when the bossbar's `BOSS_SEEN_GRACE_MILLIS` expires in `MusicManager` — no punctuation. Add `event.boss_down`: alias layering `eclipse:boss/ferryman_bell` pitch 0.6 vol 1.0 with `eclipse:ui/unlock_sting` pitch 0.8 (multi-entry sounds array — one toll under a bright release). Play server-side in `HeraldEntity.die()` / `FerrymanEntity.die()` via `level.playSound(null, blockPosition(), ..., SoundSource.HOSTILE, 1.5F, 1.0F)`, mirroring the summon-roar call sites. Optionally follow with `MusicCues.play("victory_theme", player)` for arena players on the **Ferryman** only (finale boss; `VICTORY_THEME` is already a registered non-looping 3600-tick cue that nothing triggers automatically).

### 7. Xbox portal audio identity — **S**

`XboxPortal` is the only event set-piece still speaking vanilla: `END_PORTAL_SPAWN` (line ~159), `GLASS_BREAK` (~170), `PORTAL_AMBIENT` (~256). The registry comment for `EVENT_RIFT_OPEN` even names "xbox portal — W7/W8" as an intended consumer. Swap: open → `EclipseSounds.EVENT_RIFT_OPEN`, break → `EVENT_RIFT_SLAM`, and the periodic ambient → new alias `event.xbox_portal_loop` (→ `eclipse:ambient/gazer_whisper` pitch 1.35 vol 0.4, `"attenuation_distance": 24`) so the portal hums in the mod's glitch language instead of an End portal's. Three call-site edits + one registry/sounds.json row.

### 8. Close the `ui.door_open` ledger gap — **S**

`UiSounds`' W1-ledger javadoc promises `ui.door_open`, but it was never registered — it is absent from both `EclipseSounds`' Quiet-Eclipse `uiEvent(...)` block and sounds.json (the only ledger id missing). Register `UI_DOOR_OPEN = uiEvent("ui.door_open")`, alias → `eclipse:ui/page_turn` pitch 0.55 vol 0.8 (slow paper drag reads as a heavy wooden creak), add a `UiSounds.doorOpen()` helper, and fire it in the death-flow door beat: `DeathFlowController` `PHASE_DOOR_OPEN` handling (line ~114) client-side, matching the `ShipDoorGlow` visual. Because `UiSounds.play(String, ...)` resolves ledger ids at runtime with fallback, the helper self-heals even if the registry entry lands later — the documented pattern.

### 9. Supply-beam countdown crackle ramp — **S**

`SupplyBeamClient.BeamHumSound` (line ~341) already loops `event.beam_hum` at the drop marker with a 48-block presence. Layer anticipation on top: in the same client ticker, fire one-shot `event.beam_crackle` (alias → `eclipse:event/border_glitch` pitch 2.0 vol 0.35) at a cadence that shortens as the drop timer approaches — 40 ticks → 8 ticks over the final 15 s, plus a pitch ramp 1.6 → 2.2, the inverse of `UiSounds.rouletteTick`'s falling-pitch pattern. The beam then audibly "charges up" before the crate lands, and the existing hum loop needs no changes.

### 10. Gazer outer "presence" halo — **S**

`AMBIENT_GAZER_WHISPER` is a fixed-range-12 event returned from `GazerEntity.getAmbientSound()` (line ~134) — dread starts only once the Gazer is nearly on top of you. Add `ambient.gazer_presence` registered with `createFixedRangeEvent(..., 28.0F)`, alias → `eclipse:ambient/gazer_whisper` pitch 0.5 vol 0.3, and play it from `GazerEntity.aiStep()` server-side every 120–200 ticks (`level.playSound(null, blockPosition(), ...)`). Result: a sub-audible murmur ring at 12–28 blocks that resolves into intelligible whispering as you close — two-ring distance layering from one 19.8 KB ogg.

---

## Cross-cutting notes for the integrator

- **Subtitles:** every new alias needs a `subtitles.eclipse.*` row in `en_us.json`/`de_de.json` — sounds.json here consistently sets `subtitle` on non-music events; keep that invariant.
- **Loop templates:** ideas 1/3/4/5 are all instances of the two shipped patterns (`LimboLoopSound` relative-fade, `StormLoopSound` positional). Do not invent a third lifecycle; copy the `soundStartedThisVisit` one-shot guard and the `LoggingOut` reset every time.
- **Ducking interaction:** `LastMinuteHush` ducks the MASTER listener gain — all new beds inherit the hush for free; no per-idea handling needed.
- **`SoundResetOnDisconnect`** already exists client-side; new tickable instances that follow the reset patterns above stay leak-free.
