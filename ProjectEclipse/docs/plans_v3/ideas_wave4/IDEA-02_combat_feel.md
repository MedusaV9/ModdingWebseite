# IDEA-02 — Combat Feel (Eclipse Event, wave 4, collector 2/20)

Focus: hit feedback, kill satisfaction, damage readability against the custom mobs/bosses
(`entity/`, `client/entity/`, `veilfx/QuasarSpawner`, `network/S2CShakePayload`).
Ranked by impact-per-effort. Sizes: S = one class / one seam, M = touches 2–4 classes or adds a payload/param.

---

## 1. Universal hurt-spark hit feedback for every custom mob (S/M)

The GLITCHED family already has the best hit feedback in the mod: `GlitchedGeoRenderer.HurtSparks`
spawns one BURST-budgeted `eclipse:rift_spark` crackle on the first `hurtTime` frame, deduped per
entity (FIX-5 / IDEAS-C #2). Hoist that inner class into the shared `client/entity/geo/EclipseGeoRenderer`
base (or a sibling `HurtSparkLayer`) so fog hounds, colossi, cultists, sentinels, revenants and both
bosses all pop the same crackle on hit — right now only 3 of ~12 custom mobs confirm your hits beyond
the vanilla red flash.
**Hooks:** move `GlitchedGeoRenderer.HurtSparks` → `client/entity/geo/`; call `HurtSparks.onHurtFrame(entity)`
from `EclipseGeoRenderer.preRender` when `entity.hurtTime > 0`; budget stays `FxBudget.Channel.BURST`
via `QuasarSpawner.spawnManaged`.

## 2. Kill-confirm sting for the killing player (S)

Killing an Eclipse mob currently sounds identical to wounding it (warden/vanilla death voice only).
Add a private, dry "confirm" layer — e.g. `AMETHYST_BLOCK_CHIME` at low pitch + `PLAYER_ATTACK_CRIT`
ghosted under it — sent only to the killer, with a deeper variant for elites (colossus, hound) and
none for bosses (their scripted deaths already own the moment). The drama package already isolates
exactly this event.
**Hooks:** new `LivingDeathEvent` listener modeled on `drama/FirstBloodService.onLivingDeath`
(check `event.getSource().getEntity() instanceof ServerPlayer` and victim `instanceof EclipseGeoMonster`);
deliver via `ServerPlayer.playNotifySound(...)` — no new payload needed.

## 3. Hit-stop "punch" impulse when melee connects on elites/bosses (M)

`CameraDirector`'s shake stack already supports per-impulse frequency and duration
(`addShakeImpulse(strength, ticks)` with the 2-octave noise, freq multiplier per `ShakeImpulse`).
A 2-tick, high-frequency, low-strength impulse (`shake(0.12F, 2)`) sent to the attacker on a landed
melee hit against `FogColossusEntity`/`FogTyrantEntity`/`RiftWardenEntity` reads as hit-stop weight
without actually pausing the tick loop (safe in multiplayer).
**Hooks:** `LivingDamageEvent.Post` listener (pattern: `analytics/AnalyticsService.onLivingDamagePost`)
→ `PacketDistributor.sendToPlayer(attacker, S2CShakePayload.shake(0.12F, 2))`; optionally add a
`freq` field to `S2CShakePayload` so the client can route it as a sharp rattle rather than a rumble.

## 4. Stagger = visible punish window (Warden + Storm Hound) (S)

`RiftWardenEntity` syncs `DATA_STAGGERED` and takes `STAGGER_DAMAGE_FACTOR` bonus damage, and
`ChargedLungeGoal` leaves the hound "sparking and helpless" for 40t — but neither window has a
sustained client-side tell, so players don't learn that this is free-damage time. Attach a looping
`eclipse:rift_spark` (or `storm_arc`) emitter while staggered plus a soft rising chime, and pulse the
glowmask.
**Hooks:** `RiftWardenRenderer` reads `RiftWardenEntity.isStaggered()` →
`QuasarSpawner.ensureAttached(emitter, entity, FxBudget.Channel.BURST)` / `removeAttached` on exit;
same pattern keyed off a new synced flag set in `ChargedLungeGoal` `Phase.STAGGER`.

## 5. Crit sparkles via the existing quasar cue payload (S)

Vanilla crit particles vanish against the Eclipse palette. On a player critical hit against an
Eclipse mob, fire the already-shipped `impact_light` emitter at the victim's chest through the
already-shipped server→client cue path — one event listener, zero new assets.
**Hooks:** NeoForge `CriticalHitEvent` (see `progression/ModGate.onAttackEntity` for the attack-event
subscriber pattern) → `PacketDistributor.sendToPlayersNear(..., new S2CQuasarPayload(eclipse:impact_light, pos))`;
client lands in `QuasarSpawner.spawnOrFallback` on the BURST channel.

## 6. Damage-magnitude readability: scaled impact bursts (S)

All hits currently look the same whether they deal 2 or 20. Bucket player-dealt damage in a
`LivingDamageEvent.Post` listener (≥8 = big, ≥4 = medium) and scale a `ELECTRIC_SPARK`/`CRIT`
`sendParticles` count (3/6/12) at the victim — cheap server particles, no emitter budget, and heavy
weapons instantly feel heavier.
**Hooks:** extend the `analytics/AnalyticsService.onLivingDamagePost` pattern (new listener in
`entity/` or `drama/`); guard to `EclipseGeoMonster` victims so vanilla farms don't glitter.

## 7. Glitch death dissolve: alpha fade into the seams (M)

`GlitchedMonster.tickDeath` already does the portal-static collapse and the renderers hold the
freeze-frame (`withUprightDeath()`), but the body still POOFs at full opacity. Fade the model out
over the last ~10 ticks of `deathAnimTicks()` using the translucent render-type seam that
`EclipseGeoRenderer.getRenderType` already exposes, so the corpse literally de-rezzes instead of
popping.
**Hooks:** `GlitchedGeoRenderer.preRender` / `getRenderType` — switch to
`RenderType.entityTranslucent` when `entity.deathTime > 0` and drive alpha from
`deathTime / deathAnimTicks()`; entity side is untouched.

## 8. Elite kill punctuation: colossus/hound death slam (S)

Boss deaths get the 70t storm-burst with `S2CShakePayload.shake(0.8F, 18)` at the thunderclap
(`FogTyrantEntity.tickDeath`), but elite kills end flat. Give the Fog Colossus a ground-thud on the
final death frame — `boss_slam` emitter + `shake(0.3F, 8)` to players within 16 blocks — and the
Storm Hound a short static-burst pop.
**Hooks:** `FogColossusEntity.tickDeath` (body-hits-ground frame) and `StormHoundEntity.tickDeath`
→ `PacketDistributor.sendToPlayersNear(..., S2CShakePayload.shake(...))` +
`S2CQuasarPayload(eclipse:boss_slam / eclipse:rift_spark)`; mirrors the tyrant's own thunderclap seam.

## 9. Dodge-reward "whiff" cue on telegraphed attacks (S)

Every big telegraph (lance volley, ground slam, blind squall) resolves loudly when it hits but
silently when dodged, so successful counterplay feels like nothing happened. Play a private
wind-pass (`ENDER_DRAGON_FLAP` low pitch or `TRIDENT_RETURN`) to each player who was inside the
threat shape at lock time but escaped it at release.
**Hooks:** `FogTyrantEntity.releaseLances` (players in `livingParticipants` not in `struck`),
`GroundSlamGoal.slam` (victims skipped by the airborne check), `releaseSquall` (the `covered`
branch) → `ServerPlayer.playNotifySound(...)`.

## 10. Tyrant desperation core flicker (S)

`DATA_CORE_LIT` is synced but only ever flips during the death gutter, and `DATA_PHASE` is synced
"for future renderer hooks" that don't exist yet. In P3 (≤25% HP), make the chest core flicker —
glowmask intensity stutter keyed off a deterministic hash of game time (reuse the
`GlitchedGeoRenderer.scramble` scheduling trick) — so the whole raid can read "it's almost dead"
from the boss body, not just the bar.
**Hooks:** `client/entity/fogboss/FogTyrantRenderer` reads `FogTyrantEntity.getPhase() >= 3` and
`isCoreLit()`; pure client render change, entity already syncs everything needed.

---

*Survey basis: `FogTyrantEntity`, `RiftWardenEntity`, `GlitchedMonster` + `GlitchedGeoRenderer`
(hit-flash/HurtSparks precedent), `GroundSlamGoal`, `ChargedLungeGoal`, `QuasarSpawner`/`FxBudget`
budget law, `S2CShakePayload` → `CameraDirector` impulse stack, `S2CQuasarPayload`, existing quasar
emitters (`rift_spark`, `impact_light`, `boss_slam`, `storm_arc`), and the `drama/`+`analytics/`
event-listener patterns. No code changed.*
