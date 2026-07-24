# W4-BOSSJUICE wiring — boss spectacle + new music tracks

Everything this worker added self-registers (`BossPayloads` and `BossIntroOverlay` are
`@EventBusSubscriber` classes; the seven new `SoundEvent`s ride the existing
`EclipseMusicSounds.register(modEventBus)` line from WB-MUSIC wiring §1). The only
required integration is the `sounds.json` merge below plus the asset drop.

## 1. `assets/eclipse/sounds.json` — required entries (7 NEW tracks, exactly these)

Merge these top-level members (WB-MUSIC pattern; do not add subtitles for
MUSIC-category tracks):

```json
"music.eclipse_totality": {
  "sounds": [{ "name": "eclipse:music/eclipse_totality", "stream": true }]
},
"music.fog_storm": {
  "sounds": [{ "name": "eclipse:music/fog_storm", "stream": true }]
},
"music.boss_rift_warden": {
  "sounds": [{ "name": "eclipse:music/boss_rift_warden", "stream": true }]
},
"music.boss_fog_tyrant": {
  "sounds": [{ "name": "eclipse:music/boss_fog_tyrant", "stream": true }]
},
"music.kill_contract": {
  "sounds": [{ "name": "eclipse:music/kill_contract", "stream": true }]
},
"music.wand_awakening": {
  "sounds": [{ "name": "eclipse:music/wand_awakening", "stream": true }]
},
"music.day_final": {
  "sounds": [{ "name": "eclipse:music/day_final", "stream": true }]
}
```

## 2. Asset drop (orchestrator)

The seven OGGs generated into `/tmp/treblo_out/*_raw.ogg` land at:

```
assets/eclipse/sounds/music/eclipse_totality.ogg
assets/eclipse/sounds/music/fog_storm.ogg
assets/eclipse/sounds/music/boss_rift_warden.ogg
assets/eclipse/sounds/music/boss_fog_tyrant.ogg
assets/eclipse/sounds/music/kill_contract.ogg
assets/eclipse/sounds/music/wand_awakening.ogg
assets/eclipse/sounds/music/day_final.ogg
```

Mono OGG recommended (streamed music ignores attenuation anyway; the cues play
`relative`). Until a file lands, triggering its cue logs a missing-sound warning and
plays silence — no crash.

## 3. New-track trigger map (who starts what)

Automatic (no foreign edits needed — `MusicManager` already selects these):

* `boss_rift_warden` / `boss_fog_tyrant` — observed via the
  `entity.eclipse.rift_warden.bossbar` / `entity.eclipse.fog_tyrant.bossbar`
  translatable bossbar names (same mechanism as Herald/Ferryman, incl. the 100-tick
  render-gap grace).
* `fog_storm` — while `StormInteriorFx.interiorAmount()` arms above 0.55; releases
  below 0.15 (asymmetric hysteresis) and then lingers 200 ticks (music memory).
* `eclipse_totality` — while `EclipseFxState.eclipseAmount() > 0.6`, below boss/storm
  priority; 100-tick linger.
* `day_final` — overworld, `ClientStateCache.day >= FinaleRitual.FINALE_DAY` (14);
  weakest in-world rung; 200-tick linger.

Owned by OTHER workers (the cues exist and are validated; call them like this):

* `kill_contract` (looping hunt bed — Pale Night owner / Lantern Gaze override):
  * server: `MusicCues.play("kill_contract", player)`
  * client (payload handler): `MusicCues.play("kill_contract")`
  * end it with `MusicCues.release("kill_contract")` (client side) — release, unlike
    `stop()`, hands the channel straight back to the situation ladder, so the boss
    theme underneath un-ducks immediately. If the owner needs a server-side release,
    add a release payload to `MusicPayloads` mirroring `sendStop` (not owned here).
* `wand_awakening` (non-looping ~60 s ceremonial sting — wand worker):
  `MusicCues.play("wand_awakening", player)`; it self-expires after its
  `durationTicks` (1 200 t) like `INTRO_STORM` and the ladder resumes.

All transitions inherit the 2 s crossfade; a cue re-selected while still fading out is
resumed in place (un-fade), never restarted.

## 4. Lang

Merge `docs/plans_v3/langdrop/W4-BOSSJUICE.json` into both real language files
(4 `announce.eclipse.boss.intro.*` subtitle keys, en+de). Boss NAME keys
(`entity.eclipse.<boss>`) already exist — the intro card reuses them.

## 5. Risks / notes

* `MusicManager.naturalCue` now touches `StormInteriorFx`, `EclipseFxState`,
  `ClientStateCache` and `FinaleRitual.FINALE_DAY` — all client-safe statics already
  imported elsewhere client-side; `FINALE_DAY` is a plain int constant (no server
  class initialization risk).
* The Fog Tyrant P3 ring lightning and all arena-transform upgrades are visual-only
  (particles + `LightningBolt.setVisualOnly(true)`); no block or damage changes.
* Boss intro cards render via their own `RenderGuiEvent.Post` overlay
  (`BossIntroOverlay`), deliberately NOT `AnnouncementOverlay` (other owner). If both
  fire simultaneously they overlap mid-screen; current summon sites only send the
  intro payload, but future callers should pick one channel per beat.
* Death slow-motion is a client-side render illusion (anim-speed ease to ~0.2 while
  `deathTime > 0`); server death timelines (`DEATH_DURATION_TICKS`, payout keyframes)
  are unchanged.
* The `DATA_ENRAGE_STACKS` / `DATA_STAGGERED` renderer flourishes and the death
  slow-mo degrade under `reducedFx` (steady glows, no strobe/speed lines).
