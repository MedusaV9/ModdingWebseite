# IDEA-04 — Movement & Traversal Feel (Eclipse Event, collector 4/20)

Focus: sanctum edge-glide, breach descent/updraft, border pushback, day-1 containment bounce.
Sizing: **S** = one file / one seam, no new network shapes; **M** = 2–3 files or a new service class.
All code references verified against the current tree (read-only audit, no gradle run).

## Code audit — what exists today (exact seams)

- **Edge-glide geometry is built but the glide itself is dormant.**
  `worldgen/structure/FloatingSanctumBuilder.glideLedges(altarPos)` returns the 4 notch launch
  ledges (angles `GLIDE_NOTCH_ANGLES = {45,135,225,315}`, half-width `GLIDE_NOTCH_HALF_ANGLE = 9`);
  `buildGlideNotch` places the two-slab ledge + flanking up-facing amethyst markers. The javadoc
  contract: *P4 owns the safety rule, P2 the FX*. The P4 half exists —
  `protection/SpawnProtectionRules.isInFallSafeZone` (spawn radius + `edgeBandExtra`, default 16)
  cancels fall damage in `onIncomingDamage`. The P2 half exists client-side —
  `network/fx/FxPayloads.FX_GLIDE_START/FX_GLIDE_STOP` attach/detach the `glide_trail` Quasar
  emitter (`assets/eclipse/quasar/emitters/glide_trail.json`, present) via
  `veilfx/QuasarSpawner.ensureAttached/removeAttached`. **Nothing on the server ever sends
  `FX_GLIDE_START`** — grep confirms the only references are the constant + client handler.
- **Breach descent/updraft** (`worldgen/nether/BreachTransferService`): `tickOverworld` anti-skim
  suction (`setDeltaMovement(-dx/dist*0.18, min(vy,-0.08), …)`), `descend()` (8:1 offset clamp,
  fall vector clamped to −0.35, 160t Slow Falling, campfire smoke at origin / ash at arrival /
  `SOUL_ESCAPE` @ 0.75 pitch), `tickNether` updraft column (r 1.6, height 22, strength 0.42,
  centering pull `-dx*0.06`), `ascend()` (return pad drop-in, 30× `SOUL_FIRE_FLAME`,
  `SOUL_ESCAPE` @ 1.25), plus `onServerTick` baseline FX every 10 ticks (2 orbiting rim smoke
  plumes; chimney soul-fire + ash). Doc comment: *"P2 layers the cinematic smoke/quake over this"*.
- **Border pushback** (`border/SoftBorder`): `impulseInward` sets velocity
  `min(1.2, 0.25·(d−R)+0.4)` inward + 0.3 Y with `hurtMarked = true`; `playGlitchFeedback` is
  throttled 15t (`EclipseSounds.EVENT_BORDER_GLITCH` + `S2CQuasarPayload.BORDER_GLITCH` burst);
  `teleportInside` fallback beyond R+3. Client `border/client/BorderFxRenderer` already computes a
  per-frame proximity factor `prox` and owns `VeilPostController.BORDER_GLITCH_POST`.
- **Containment bounce** (`progression/ContainmentService`): below `protection.json`
  `containment.bounceY`, `applyBounce` sets velocity `(0.4x, 2.8, 0.4z)`, grants 100t fall
  immunity (`BOUNCED_UNTIL_TICK`), plays `AMETHYST_CLUSTER_BREAK` @ 1.35, 8× `REVERSE_PORTAL`
  particles, action-bar hint, and sends `CONTAINMENT_BOUNCE_EMITTER` Quasar payload (emitter asset
  is still the P2 TODO — fallback particles apply).

House constraints to respect: `FxPayloads` FX ids are FROZEN (extend semantics via `a`/`b` floats,
don't add ids casually); server-authoritative motion must use the `hurtMarked = true` velocity-sync
pattern; client particle work goes through `FxBudget` channels; every new static map resets on
`ServerStoppedEvent` (repo-wide rule).

---

## Ranked ideas

### 1. Wire the dormant edge-glide loop end-to-end (launch → trail → land) — **M**
The single highest-value seam: geometry, safety rule, client FX and the `glide_trail` emitter all
exist, but no server code flags glide state. New game-bus service `movement/EdgeGlideService`
(pattern-copy `ContainmentService`): on `PlayerTickEvent.Post` in the overworld, if the player is
airborne with negative vy, within ~2.5 blocks horizontally of any
`FloatingSanctumBuilder.glideLedges(EclipseWorldState.get(server).getSanctumAltarPos())` position
(cache the 4 positions on `ServerStartedEvent`, reset static on `ServerStoppedEvent`), and
`SpawnProtectionRules.isInFallSafeZone` holds → enter glide: damp vy to ≥ −0.18 each tick
(`hurtMarked = true`), fire `FxPayloads.sendFxEvent(level, FX_GLIDE_START, player.position(), 0, 0, 64)`
once; on `player.onGround()` or leaving the fall-safe band, fire `FX_GLIDE_STOP`. Ideas 2, 5 and 9
piggyback on this. Risk: none to frozen interfaces — this is exactly the consumer they were frozen for.

### 2. Glide wind particles + speed-doppler audio loop — **S** (after #1)
Extend the `FX_GLIDE_START` branch in `FxPayloads.handleFxEvent` (lines ~130–139) to also start a
client wind loop: new tiny `veilfx/GlideAudioClient` holding an `AbstractTickableSoundInstance`
positioned on the glider whose **pitch/volume track `player.getDeltaMovement().length()`** — that
speed-tracking *is* the doppler feel (0.8 → 1.3 pitch over 0.2 → 0.8 blocks/tick). Kill it in the
`FX_GLIDE_STOP` branch and in `QuasarSpawner.clearAttached`-style level-unload cleanup. Reuse an
existing wind-ish sound from `assets/eclipse/sounds/ambient/` or vanilla `ITEM_ELYTRA_FLYING` at
low volume; particle side needs zero work (`glide_trail` emitter already rate-scales).

### 3. Breach descent "glitch-drift" beauty pass — **M**
The 160-tick Slow Falling drop after `descend()` is currently a straight fall. Track descending
players in `BreachTransferService` (`Map<UUID,Integer> DESCENT_TICKS`, cleared on logout/stop like
`TRANSFER_COOLDOWN`): while active and in the Nether, add a per-tick sinusoidal drift
`motion.add(sin(t*0.13)*0.012, 0, cos(t*0.11)*0.012)` with `hurtMarked = true` — a leaf-on-the-wind
wobble that sells the 8:1 compression — plus every 8 ticks a short `ASH`/`SCULK_SOUL` streak pair at
the player via `nether.sendParticles`, and one mid-fall `SOUL_ESCAPE` echo at 0.6 pitch at t=80.
The "glitch" accent: send one `S2CQuasarPayload.BORDER_GLITCH` burst at t=0 arrival (payload and
client handling already exist). End the map entry on `onGround()` or effect expiry.

### 4. Universal soft-landing dust + thud — **S**
All four systems end in a protected landing (glide fall-safe band, breach Slow Falling, border
fallback Slow Falling, bounce fall immunity) and none of them mark the landing. New
`movement/SoftLandingFx` game-bus subscriber: on `PlayerTickEvent.Post`, when a tracked-airborne
player touches `onGround()` while `ContainmentService.hasFallImmunity(player)` OR has
`MobEffects.SLOW_FALLING`, emit a `ParticleTypes.BLOCK` dust ring of the block below
(`level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, stateBelow), …, 12, 0.5, 0.05, 0.5, 0.1)`)
plus a muffled `SoundEvents.WOOL_STEP`-family thud at 0.7 pitch scaled by prior fall speed.
One class, one airborne-tracking map (reset on `ServerStoppedEvent`), covers every traversal ending.

### 5. Updraft ride: soul helix + rising pitch ladder — **S**
Inside `BreachTransferService.tickNether`'s `inColumn` branch (lines ~171–183): every 5 ticks spawn
2 `SOUL` particles at `angle = (gameTime*0.35 + playerPhase)` on a r≈1.2 circle around the player
(a visible corkscrew that reads as "the column is carrying you"), and every 20 ticks play
`SOUL_ESCAPE` at pitch `0.7 + 0.6 * (player.getY() - updraft.getY()) / UPDRAFT_HEIGHT` — an audible
altimeter that resolves at 1.3 exactly when `ascend()` fires (its existing sting is 1.25; adjust to
match). Pure additions inside one existing method; budget is trivial next to the existing baseline FX.

### 6. Containment bounce anticipation squash — **S**
The bounce currently teleport-feels: instant velocity flip at `bounceY`. Add a pre-band in
`ContainmentService.onPlayerTick`: between `bounceY + 10` and `bounceY`, while falling
(vy < −0.4), send 2–3 `REVERSE_PORTAL` particles *below* the player per tick and one warning chime
(`AMETHYST_BLOCK_CHIME` @ 0.6, once per fall — reuse the `BOUNCED_UNTIL_TICK` map with a sentinel
or a second small map). Then in `applyBounce`, make the "squash": scale horizontal velocity 0.4 →
0.25 for the first 3 ticks after the bounce and restore (tiny per-player countdown), so the arc
visibly compresses then releases. Client-side stretch is optional; the server-side squash alone
reads clearly in third person and for bystanders.

### 7. Bounce crest shimmer + FOV kick via existing shockwave — **S**
At the top of the bounce arc the moment currently dies silently. Two hooks: (a) in
`ContainmentService.applyBounce`, immediately send
`FxPayloads.sendFxEvent(level, FX_SHOCKWAVE, player.position(), 0.3f, 8f, 32)` — the client
`EclipseFxState.startShockwave` path exists and gives a subtle radial ripple + implicit FOV punch;
(b) track apex (vy sign flip within the 100t immunity window, same tick loop as idea 6) and emit
6 `END_ROD` particles + `AMETHYST_BLOCK_CHIME` @ 1.6 at the crest. Also the natural place to finally
author the missing `containment_bounce` emitter JSON (copy `unlock_burst.json`, recolor to the
existing `HINT_COLOR = 0xB98CFF`).

### 8. Border "elastic band" pre-tension — **M**
Pushback today is binary (inside: nothing; outside: shove). Add an inner tension band in
`SoftBorder.onPlayerTick`: for `R − 4 < d ≤ R`, scale the player's *outward* horizontal velocity
component by `0.85` (project `motion` onto the outward normal; only damp the positive part) with
`hurtMarked = true` — running at the ring feels like leaning into rubber before the snap. Client
side, `BorderFxRenderer` already computes proximity `prox`: drive a low static-hum loop
(`EVENT_BORDER_GLITCH`-derived or a new quiet loop under `sounds/event/`) whose volume follows
`prox²`, started/stopped locally — no new payloads, the ring radius is already synced via
`S2CBorderPayload`. Keep the vehicle path (`onEntityTick`) untouched to avoid eject-rule interactions.

### 9. Notch launch ceremony: amethyst chime + marker pulse — **S** (after #1)
When `EdgeGlideService` fires `FX_GLIDE_START`, also play `SoundEvents.AMETHYST_BLOCK_CHIME`
(0.9 vol, 1.2 pitch) at the matched ledge BlockPos and send one `S2CQuasarPayload` burst
(`unlock_burst` or the `border_shard` emitter, both exist) at the two flanking marker positions —
recompute them exactly as `FloatingSanctumBuilder.buildGlideNotch` does (`perp ± 2` at `t − 0.3`),
or simpler: offset ±2 perpendicular from the ledge. The notches become *instruments* you play by
jumping through them; zero new assets required.

### 10. Descent depth-doppler ambience — **S**
During the overworld funnel drop (`tickOverworld`, the anti-skim band between `lipY − 8` and
`transferY`), play a per-player descent whoosh every 15 ticks whose pitch falls with depth
fraction `f = (lipY − y) / (lipY − transferY)`: `SOUL_ESCAPE` at `pitch 1.2 − 0.6f`, volume
`0.3 + 0.4f` via `player.playNotifySound` (private to the faller). The world drops in pitch as the
Nether approaches, then `descend()`'s existing 0.75-pitch sting lands as the resolution note.
Throttle with a per-player last-played tick in the existing cooldown-map style.

---

## Cross-cutting notes

- Ideas 1→2→9 form one workstream (glide activation, then dressing); land 1 first.
- Ideas 4 and 6/7 share the airborne-tracking pattern — if both are picked, host the map in one
  place (`SoftLandingFx`) and let `ContainmentService` query it.
- Nothing above touches frozen shapes: no new `S2CFxEventPayload` ids needed (reuse
  `FX_GLIDE_START/STOP`, `FX_SHOCKWAVE`, `S2CQuasarPayload`); all server motion uses the
  established `setDeltaMovement + hurtMarked` sync pattern.
