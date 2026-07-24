# IDEA-08 — Music Integration Moments (Wave 4, collector 8/20)

**Scope:** `music/` (MusicManager, MusicCues, EclipseMusicSounds, MusicPayloads, MusicConfig)
— wiring the **7 incoming tracks** (`eclipse_totality`, `fog_storm`, `boss_rift_warden`,
`boss_fog_tyrant`, `kill_contract`, `wand_awakening`, `day_final`; prompts already authored in
`tools/music/treblo_generate.py` TRACKS) into the existing 8-cue situation score, plus the
cross-cutting mechanics they need: crossfade/handoff rules, ducking, **music memory** (no loop
restart on brief exits) and **first-time-vs-repeat** variants.

Grounded read-only against the current codebase; no code changes here.

---

## 0. Grounding — how the score works today (exact seams)

| Fact | Where |
| --- | --- |
| One managed music channel, 2 s crossfade (`FADE_TICKS = 40`); `CueSound extends AbstractTickableSoundInstance`, volume owned exclusively by the fade envelope (`volume = volumeMultiplier() * fade/40`); vanilla `MusicManager.stopPlaying()` is suppressed while any side of a fade is audible | `music/MusicManager.java` |
| Priority ladder in `naturalCue()`: explicit/forced cue → boss (bossbar-observed) → expansion (`ClientStateCache.stageAnimating*`) → Xbox dimension → Limbo → title screen | `MusicManager.naturalCue` |
| Boss detection = `CustomizeGuiOverlayEvent.BossEventProgress` translatable-key switch (`entity.eclipse.herald.bossbar`, `entity.eclipse.ferryman.bossbar`) with a **100-tick seen-grace** (`BOSS_SEEN_GRACE_MILLIS`) bridging F1/letterbox gaps — the existing "music memory" precedent | `MusicManager.onBossbar` |
| Cue catalog: `MusicCues(id, sound, looping, durationTicks)`; non-looping cues own the channel for `durationTicks` (`INTRO_STORM` 3 000 t, `VICTORY_THEME` 3 600 t) | `music/MusicCues.java` |
| Registration recipe: `EclipseMusicSounds.music("id")` → sound event `eclipse:music.<id>` → `sounds.json` entry `{"name": "eclipse:music/<id>", "stream": true}` (no subtitles for music) | `EclipseMusicSounds`, `assets/eclipse/sounds.json`, `docs/plans_v3/wiring/WB-MUSIC_wiring.md` §2 |
| Server → client transport: `MusicPayloads.sendPlay/sendStop(player)`; client-side triggers call `MusicCues.play(String)` (payload handlers only). `/dev music play|stop|list` suggests from `MusicCues.ids()` automatically | `MusicPayloads`, `DevMusicCommands` |
| `MusicManager.stop()` mutes the CURRENT natural situation until it *changes* (`suppressSituation`) — any "stop then resume natural" idea must clear `forcedCue` instead of calling `stop()` | `MusicManager.stop` |
| New-boss bossbar keys already exist: `entity.eclipse.rift_warden.bossbar` (PURPLE PROGRESS), `entity.eclipse.fog_tyrant.bossbar` (PURPLE NOTCHED_20); both send `THEME_BOSS` skin payloads per viewer | `entity/boss/rift/RiftWardenEntity.java` ~149, `entity/boss/fog/FogTyrantEntity.java` ~213 |
| Storm interior is a smoothed client scalar 0..1: `StormInteriorFx.interiorAmount()` (feather over 3 blocks at the wall, ~6-tick ease, 0 outside all storms) | `stormfx/StormInteriorFx.java` |
| Fog Tyrant summons when a player wanders within `TRIGGER_RANGE = 20` of a lair *inside* a mature storm | `entity/boss/fog/FogBankMarker.java` |
| Eclipse phase is a client blackboard: `EclipseFxState.eclipsePhase()` (`PHASE_TOTAL = 2`), fed by `S2CEclipsePhasePayload` (IntroSequence sends TOTAL at t=0, ENDING at sunrise; re-sent at login) | `veilfx/EclipseFxState.java`, `sequence/IntroSequence.java` |
| Day clock client-side: `DayTimerCache.day()/remainingMillis()/armed()`; the synced timeline carries `unlockDay` for **every** planned day (hidden future entries keep their day number), so the client can derive the final planned day (14, `FinaleRitual.FINALE_DAY`) without new packets | `client/hud/DayTimerCache.java`, `timeline/TimelineEntry.java`, `ClientStateCache.timeline` |
| "Last-minute hush": final 60 s before every day boundary ducks **MASTER** listener gain by up to 45% (`DUCK_DEPTH = 0.45`) + 15% screen dim + accelerating heartbeat — music inherits this duck for free (MUSIC is under MASTER) | `client/drama/LastMinuteHush.java` |
| Kill-contract fiction already exists twice: Ferryman **Lantern Gaze** (marks the fewest-permanent-hearts player for `GAZE_MARK_TICKS = 300` every 400 t; private `S2CShakePayload.mark` → `MarkVignetteOverlay` + private bell) and **Pale Nights** (doppelganger "The Other" hunts among friends; rolled/cleared in `EclipseSpawner.scheduleNightEvent/clearNightEvent`) | `entity/boss/FerrymanEntity.java` ~753, `network/EclipsePayloads.handleShake` ~192, `entity/EclipseSpawner.java` ~153 |
| The wand ("Zauberstab") is IDEA-19: path-choice attunement + `awaken_<path>` trigger anim + stage-up "Erwacht" reveal — the `wand_awakening` sting's home | `docs/plans_v3/ideas_wave4/IDEA-19_wand.md` §1.4/§1.5 |

---

## Ranked ideas

| # | Idea | Size | Track(s) |
|---:|---|---|---|
| 1 | Catalog + registrar wiring for all 7 tracks (one PR, zero behavior) | S | all |
| 2 | Rift Warden / Fog Tyrant boss cues via the existing bossbar switch | S | boss_rift_warden, boss_fog_tyrant |
| 3 | `fog_storm` interior-driven situation rung with hysteresis + Tyrant handoff | S | fog_storm |
| 4 | Music memory: per-cue linger + **un-fade resume** (no loop restart on brief exits) | M | fog_storm, limbo, xbox, totality |
| 5 | `eclipse_totality` phase rung under the black sun | S | eclipse_totality |
| 6 | `day_final` last-day bed, client-derived, stacking with the hush | M | day_final |
| 7 | `kill_contract` dual trigger: Pale Night owner + private Lantern Gaze override | M | kill_contract |
| 8 | `wand_awakening` attunement sting (IDEA-19 seam + interim milestone trigger) | S | wand_awakening |
| 9 | Duck envelope on the music channel + three new ducking moments | M | all |
| 10 | First-time-vs-repeat variants via a client "heard" ledger | M | totality, bosses, wand |

---

### 1. Catalog + registrar wiring for all 7 tracks — **S**

The mechanical enablement, deliberately its own zero-risk PR:

- `EclipseMusicSounds`: seven new `music("…")` suppliers (`ECLIPSE_TOTALITY`, `FOG_STORM`,
  `BOSS_RIFT_WARDEN`, `BOSS_FOG_TYRANT`, `KILL_CONTRACT`, `WAND_AWAKENING`, `DAY_FINAL`).
- `MusicCues` rows (looping/duration per the treblo prompts):
  `ECLIPSE_TOTALITY(loop)`, `FOG_STORM(loop)`, `BOSS_RIFT_WARDEN(loop)`, `BOSS_FOG_TYRANT(loop)`,
  `KILL_CONTRACT(loop)`, `WAND_AWAKENING(false, 1_200)` (45–60 s sting + tail),
  `DAY_FINAL(loop)`.
- `sounds.json`: seven `music.<id>` members, `stream: true`, no subtitles (WB-MUSIC §2 invariant).
- OGGs land at `assets/eclipse/sounds/music/<id>.ogg` from `tools/music/treblo_generate.py`
  (prompts already in TRACKS; run with `--only` for the seven ids).
- Update `CREDITS.md` + `assets/eclipse/credits.json` from 8 → 15 tracks (WB-MUSIC §6 says the
  two lists must stay reconciled).
- Free wins: `/dev music play <id>` tab-completes the new ids immediately (`MusicCues.ids()`),
  and `MusicPayloads` needs no change.

### 2. Rift Warden / Fog Tyrant boss cues — **S**

Extend the switch in `MusicManager.onBossbar` (~line 133) with the two keys that already render:

```java
case "entity.eclipse.rift_warden.bossbar" -> MusicCues.BOSS_RIFT_WARDEN;
case "entity.eclipse.fog_tyrant.bossbar" -> MusicCues.BOSS_FOG_TYRANT;
```

Everything else is inherited: the 100-tick `BOSS_SEEN_GRACE_MILLIS` bridges letterboxed
intros/F1; `observedBossCue` is single-slot, which is correct (the arenas are hundreds of
blocks apart); on boss death the bar disappears, grace expires, and the manager crossfades
back to whatever situation is under it — for the Tyrant that is the `fog_storm` bed (idea 3),
for the Warden usually silence in the vault. Crossfade behavior: the standard 2 s
`transitionTo` fade both ways; no special casing needed because bossbar rungs already outrank
everything except forced cues.

### 3. `fog_storm` interior rung with hysteresis + Tyrant handoff — **S**

The track is "inside a hunting fog storm", and the client already computes exactly that:
`StormInteriorFx.interiorAmount()` (0 outside, feathered 0→1 over ~3 blocks at the wall,
6-tick smoothed). Add one rung to `naturalCue()` between the boss branch and the
expansion branch:

```java
if (minecraft.level != null && FogStormMusicGate.active()) return MusicCues.FOG_STORM;
```

where `FogStormMusicGate` is a ~10-line hysteresis holder in `music/`: arms when
`interiorAmount() > 0.55F`, disarms when `< 0.15F`. The asymmetric thresholds stop
wall-skimming flap; the residual brief-exit case (dodging out of the wall mid-fight and back)
is covered by idea 4's linger. Handoffs come free from ladder order:

- walk into the wall → 2 s crossfade silence→`fog_storm`;
- trip the lair (`FogBankMarker.TRIGGER_RANGE = 20`) → Tyrant bossbar appears → boss rung
  outranks the storm rung → 2 s crossfade `fog_storm`→`boss_fog_tyrant`;
- Tyrant dies → grace expires → crossfade back down to `fog_storm` (still inside), then out
  to silence at the wall.

### 4. Music memory: per-cue linger + un-fade resume — **M** *(cross-cutting; the "don't restart the loop" mechanic)*

Two small changes inside `MusicManager` only:

1. **Linger.** Add `int lingerTicks()` to `MusicCues` (default 0; `FOG_STORM` 200,
   `LIMBO_AMBIENCE` 200, `XBOX_NOSTALGIA` 100, `ECLIPSE_TOTALITY` 100, `DAY_FINAL` 200,
   `KILL_CONTRACT` 100). In `onClientTick`, when `desired` would DROP from the current looping
   situation cue to `null` **or to a strictly lower-priority rung**, hold the current cue for
   its linger window first (mirror of `observedBossCue`'s grace, generalized). Rung upgrades
   (storm→boss) bypass linger so fights always take over instantly.
2. **Un-fade resume.** In `transitionTo`, before creating a new `CueSound`:
   ```java
   if (outgoing != null && outgoing.cue == cue) {
       outgoing.fadeDirection = 1;       // cancel the fade-out mid-flight
       current = outgoing; outgoing = null;
       return;
   }
   ```
   Because `CueSound` keeps streaming while it fades (stop only fires at fade==0), this
   resumes the SAME sound instance at the SAME playback position — a player who steps out of
   the storm wall for three seconds hears the bed dip and swell, never a restart from bar 1.
   (Seeking is impossible with `SoundInstance`s, so cancel-the-fade is the only true
   position-preserving memory; it costs ~6 lines.)

Together: brief exits < linger → nothing happens at all; exits that do start the fade but
return within 2 s → un-fade resume; longer exits → clean restart, which is correct.

### 5. `eclipse_totality` phase rung — **S**

The "standing under a black sun" drone maps 1:1 onto the client FX blackboard. New rung in
`naturalCue()` directly **below the boss branch and above expansion**:

```java
if (minecraft.level != null && EclipseFxState.eclipsePhase() == EclipseFxState.PHASE_TOTAL) {
    return MusicCues.ECLIPSE_TOTALITY;
}
```

Trigger timeline (all existing payloads, zero server work):

- Intro v3 `ECLIPSE_ON` sends `TOTAL` at t=0 — but the start-cutscene TILT phase force-plays
  `intro_storm` (`EclipsePayloads.handleCutscene`), and forced beats natural, so the storm
  sting owns the channel; when EMERGE calls `MusicCues.stop()`, the suppression clears on the
  next situation *change* — which is exactly this new totality rung becoming active → the
  drone fades in under the flight/altar reveal.
- `SUNRISE` sends `ENDING` → rung evaporates → standard 2 s fade out as the sun returns.
- Login mid-sequence: `IntroSequence` re-sends the phase payload, so late joiners get the
  drone with no extra code.
- Any future scripted totality (finale ideas, admin `/eclipsefx`) inherits the music for free
  because it keys off the phase, not the sequence.

### 6. `day_final` last-day bed + hush stack — **M**

"The last day: inevitability ambience" should color the WHOLE final day without stepping on
anything louder. New **weakest in-world rung** (just above the title-screen branch):

```java
if (minecraft.level != null && minecraft.level.dimension() == Level.OVERWORLD
        && DayTimerCache.armed() && FinalDayGate.isFinalDay()) {
    return MusicCues.DAY_FINAL;
}
```

`FinalDayGate` (~15 lines, `music/`): `ClientStateCache.dayClockDay >= maxPlannedDay()` where
`maxPlannedDay()` is the max `unlockDay` over `ClientStateCache.timeline` entries with
`id < 1000` (day entries; hidden future entries still carry their day number, so this is
computable on day 1 without de-anonymizing anything — it leaks only the arc LENGTH, which the
handbook timeline already shows as "???" nodes). No new packet; falls back gracefully (gate
false) when the timeline hasn't synced. Server alternative if the leak bothers anyone: an
`EclipseSignals.onDayRollover` POST listener comparing `newDay == EclipseConfig.maxDay()`
that broadcasts `sendPlay`, plus a login re-send — but the client derivation is one file.

Interplay, all automatic:

- Every other rung (bosses, storm, totality, limbo for ghosts, expansion) outranks it, so the
  bed is what plays "between" beats on day 14 — exactly the dread-glue the prompt describes.
- **Ducking moment:** `LastMinuteHush` ducks MASTER gain up to 45% over the final 60 s of the
  day — the funeral-bell bed inherits the duck and sinks under the heartbeat with no music
  code at all. Do NOT add a second music-side duck for the same window (double-attenuation).
- The finale ritual teleports everyone to Limbo → dimension rung takes over
  (`limbo_ambience` → `boss_ferryman` → forced `victory_theme`), so `day_final` bows out of
  the endgame naturally.

### 7. `kill_contract` dual trigger: Pale Night owner + Lantern Gaze private override — **M**

"Assassination hour: a hunt among friends" has two homes; both use existing private-targeting
machinery:

1. **Pale Night bed (all players).** Server-side ownership, XboxMusicHook-style
   (WB-MUSIC §4 precedent): in `EclipseSpawner.scheduleNightEvent` (~line 169), after
   `announceNightEvent(server, event)`, when the event is `NIGHT_EVENT_PALE`:
   `MusicPayloads.sendPlay(player, "kill_contract")` to every online player; in
   `clearNightEvent` (dawn) and on the `/eclipse event set none` path: `sendStop`. Add the
   same `sendPlay` in the login hook while `EclipseWorldState.getActiveNightEvent()` is PALE
   so mid-night joiners aren't silent. The whole night, "The Other" walks among teammates and
   the ticking-clock loop tells everyone something is wrong. Caveat to document: this is a
   *forced* looping cue, so it outranks boss rungs — acceptable because bosses are
   summon-gated (Herald altar lure, vault/lair proximity), but the honest fix is a one-flag
   "ambient-forced" tier in `MusicCues` that yields to boss rungs (~10 lines in
   `onClientTick`'s `desired` selection).
2. **Lantern Gaze private override (the marked player only).** Client-side, in
   `EclipsePayloads.handleShake` (~line 193) next to `MarkVignetteOverlay.trigger(ticks)`:
   `MusicCues.play("kill_contract")` — but ONLY when `payload.ticks() >= 100` (the Ferryman
   Gaze sends 300 t; the Herald charge vignette reuses the mark payload with shorter windows
   and must not hijack its own boss theme). Release without killing the boss track: do NOT
   call `MusicCues.stop()` (its `suppressSituation` would mute `boss_ferryman` until the
   situation changes); instead add `MusicManager.release(MusicCues cue)` that clears
   `forcedCue` iff it matches, called from `MarkVignetteOverlay.onClientTick` when
   `ticksLeft` crosses 0. Effect: for 15 s the hunted player's epic boss orchestra collapses
   into dry ticking paranoia while everyone else still hears `boss_ferryman` — the strongest
   private-danger read the score can produce, and it needs zero new packets.

### 8. `wand_awakening` attunement sting — **S**

A 45–60 s ceremonial one-shot (`looping=false, durationTicks=1_200`); after it elapses the
channel hands back to the situation ladder automatically (same ownership model as
`INTRO_STORM`). Trigger sites:

- **Primary (IDEA-19 seam, one line when the wand ships):** the path-choice confirmation
  (§1.4 — radial screen confirm / orrery ritual), server-side:
  `MusicCues.play("wand_awakening", serverPlayer)` — private, exactly like the reveal is
  private. Re-fire on stage-ups ("Erwacht"→"Gefestigt"→"Vollendet") but gate repeats via
  idea 10 (first attunement gets the full sting; later stages get nothing but the
  `unlock_burst` SFX so a 60 s track can't wear out).
- **Interim trigger so the track ships audible before IDEA-19 lands:** altar milestone
  level-ups — `AnnouncementService.pollAltar` already detects each level gained; add
  `MusicPayloads.sendPlay(player, "wand_awakening")` to all online players alongside the
  milestone announce (a "magic catalyst awakens" reading of the altar). Remove or keep when
  the wand arrives — the cue id stays honest either way.
- Always previewable via `/dev music play wand_awakening`.

### 9. Duck envelope on the music channel + three ducking moments — **M**

`LastMinuteHush` proves ducking works at MASTER level, but it is the only duck in the mod and
it drags ALL audio down. Add a music-only duck: a static
`MusicManager.duck(float target, int easeTicks)` writing a `duckTarget` that `CueSound.tick`
folds in — `volume = volumeMultiplier() * fadeEnv * duckEnv` (duckEnv eased per tick like the
hush's attack/release). Callers, each one line:

- **Boss intro letterbox:** while `CameraDirector.isActive()` (cutscene flights, boss
  intros), duck to 0.55 — the score breathes out for dialogue/camera beats and swells back
  on release; this also stops the totality drone from fighting intro captions.
- **Boss-kill silence beat:** in the client path that observes a matched Eclipse bossbar
  disappearing (grace expiry in `onClientTick`), duck to 0.0 over 10 t, hold ~40 t, release —
  a deliberate "held breath" before the next bed fades in; pairs with IDEA-07 #6's
  `event.boss_down` stinger, which plays into the ducked silence.
- **Lantern Gaze bell:** the private mark bell (`BOSS_FERRYMAN_BELL` + `BELL_RESONATE` in
  `MarkVignetteOverlay.trigger`) fires into a 20 t duck-to-0.3, so the toll cuts through
  before idea 7's `kill_contract` override fades in.
- Explicit NON-goal: the last-minute hush keeps ducking MASTER exactly as-is; the music duck
  must not run in that window (guard: skip when `LastMinuteHush` is active — or simply accept
  multiplicative stacking, ~25% floor, which still reads correctly).

### 10. First-time-vs-repeat variants via a client "heard" ledger — **M**

Some of the new tracks are awe-cues whose first hearing is sacred (`eclipse_totality`,
`wand_awakening`) or fight themes replayed dozens of times after wipes (`boss_rift_warden`,
`boss_fog_tyrant`). Mechanism:

- `music/MusicMemory` (client): a `Set<String>` of cue ids, persisted to
  `config/eclipse-music-memory.json` (the `MusicConfig` standalone-file precedent), keyed per
  server address so a new event/server resets the "first time". Written the first tick a cue
  actually becomes `current`.
- `MusicCues` gains an optional `repeatSound` supplier + `repeatVolume` float. Resolution
  happens once in the `CueSound` constructor: unheard → primary sound at full envelope; heard
  → `repeatSound` if present, else primary at `repeatVolume`.
- Concrete assignments: `eclipse_totality` repeat at 0.7 gain (the dread thins once known);
  `wand_awakening` repeat = **skip entirely** (`repeatVolume 0`, per idea 8 — SFX carries
  stage-ups); `boss_rift_warden`/`boss_fog_tyrant` repeat = `music.<id>_alt` variants — the
  treblo tool makes alternates one `--only boss_rift_warden` rerun away (V3 non-determinism is
  the feature: same prompt, fresh take), registered as extra `EclipseMusicSounds` entries so
  re-attempts after a wipe don't fatigue.
- `/dev music forget` (one added subcommand) clears the ledger for QA.

---

## Open questions for the synthesizer

- Idea 7's ambient-forced tier vs. accepting that a Pale Night bed outranks a
  simultaneously-summoned boss — recommend the tier flag; it is small and also future-proofs
  `day_final`-style beds if they ever move to server push.
- `fog_storm` hysteresis thresholds (0.55/0.15) and linger (200 t ≈ 10 s) want an in-storm
  playtest; both are single constants.
- Should the `day_final` client derivation be swapped for the `EclipseSignals` server push to
  avoid leaking arc length? (The handbook timeline already renders one "???" node per future
  day, so the length is arguably public.)
- Repeat variants (idea 10): per-server ledger key vs. global — per-server matches the
  one-shot event fantasy; global protects singleplayer testers from re-hearing awe cues.
