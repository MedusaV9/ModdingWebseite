# IDEA-12 — Altar & Offering Ceremony Feel

Collector: 12/20, Eclipse Event wave 4. Ranked best-first. Every idea names the exact
existing hook(s); none require new systems or new binary assets (new "sounds" follow the
established `sounds.json` alias/re-pitch convention; new particles are Quasar emitter
JSONs cloned from `altar_beam.json` / `altar_reveal_burst.json`).

Effort: **S** = one class + maybe one JSON touched, no new protocol/uniform.
**M** = 2–3 files, or a tiny new payload field / emitter JSON.

Grounding (verified in source):

- Server brain: `ritual/AltarBlockEntity` — `handleOffering` (sneak+item, two-click
  confirm via `OfferingRules.needsConfirmation`, 100 t window), `handleMilestoneDeposit`
  (right-click item), `handleHeartSacrifice`, `completeMilestone` (END_PORTAL_SPAWN
  0.4F to all + 150 PORTAL particles). Routing: `ritual/AltarBlock.onSneakRightClick`
  (LOWEST-priority `RightClickBlock`; shards branch to `ShardEconomy.deposit`).
- Values: `offering/OfferingService.accept` computes `exactValue` from
  `OfferingRules.value` (junk=0 … epic=250, enchanted ×1.5) but **discards it** for
  feedback purposes; `OfferingState` persists only item/enchanted/renamed facts;
  `resolveDay` settles winners at PRE day rollover; duplicates cancel to 0.
- Client FX: `client/AltarAberration` (post pipeline, one frozen uniform `Aberration`,
  eased zone strength + 0.3 Hz CPU-side breathing in `feedPost`),
  `client/drama/AltarIdleMotes` (rolling window of ≤3 looping mote emitters around
  `FxAnchors.ALTAR_CENTER`), `veilfx/QuasarSpawner.spawnOrFallback` handling
  `network/S2CQuasarPayload` well-known emitter ids (`ALTAR_BEAM`, …).
- Altar level is client-synced (`ClientStateCache.altarLevel` via `S2CDayStatePayload`);
  `client/handbook/tabs/StatusTab.tick` already detects level-ups (unlock sting + pulse).
- Server always knows the altar position: `EclipseWorldState.getSanctumAltarPos()`.

---

## 1. Offering swallow: item spirals into the altar under a light column — M

The most-repeated ritual (once per player per day) currently pays off with a flat 36
PORTAL-particle puff. Make the altar visibly *take* the offering: on the confirm click,
`AltarBlockEntity.handleOffering` sends one extra `S2CQuasarPayload` with a new
well-known id `OFFERING_SWALLOW` at the player's hand position; a small client class in
`client/drama/` (register like `AltarIdleMotes`, `ClientTickEvent.Post`) renders the
offered item as a billboard (vanilla `ItemRenderer`, item id can ride in the existing
`S2CQuasarPayload` pattern as a second emitter-suffixed payload or a 2-field sibling
payload) spiraling from hand → `FxAnchors.ALTAR_CENTER` over ~30 t, shrinking to zero.
The already-sent `ALTAR_BEAM` becomes the arrival beat: delay it client-side ~30 t so
the light column erupts exactly when the item vanishes into the stone. Fallback path
(Quasar unavailable) keeps today's PORTAL burst via `QuasarSpawner.spawnOrFallback`.

**Extend:** `ritual/AltarBlockEntity.handleOffering`, `network/S2CQuasarPayload`
(new constant; optionally sibling payload with item id), new
`client/drama/OfferingSwallowFx`, emitter clone `quasar/emitters/offering_swallow.json`.

## 2. Secret-value TELL: the ack chime's pitch hints the tier — S

Values must stay secret until rollover, but a *tell* the offerer can learn to read is
pure ceremony. `OfferingService.accept` already computes `exactValue` and returns only
a boolean — add an `acceptWithValue` overload returning `OptionalInt` (keep `accept`
delegating; `gametest/offering/OfferingGameTests` untouched). In
`handleOffering`, replace the fixed-pitch `EclipseSounds.OFFERING_ACCEPT` for the
**offerer only** (`player.playNotifySound`) with a quantized pitch band: 3 buckets
(0–5 → 0.85, 15–40 → 1.0, 100+ → 1.15) plus ±0.03 random jitter so adjacent tiers stay
deniable. Bystanders (`serverLevel.playSound` at the block) keep neutral 1.0 — the tell
is private, so the daily-winner metagame (duplicate cancellation!) is not leaked to
rivals standing at the altar. No text, no numbers — pure ear-training, exactly the
"action bar + sounds only" house rule.

**Extend:** `offering/OfferingService` (returning-value overload),
`ritual/AltarBlockEntity.handleOffering` (split offerer/bystander sound, pitch map).

## 3. Altar level-up transformation moment — M

`completeMilestone` fires a one-shot global sound + one particle burst and life moves
on; a season-defining progression beat deserves a *state change you can see*. Two
layers, both riding the already-synced `ClientStateCache.altarLevel`:
(a) **Moment** — in `completeMilestone`, besides the existing cue, send `ALTAR_BEAM`
plus a new `altar_levelup_ring.json` (clone `altar_reveal_burst.json`, sphere →
flattened ring, gold→violet gradient) to players within `BeamEmitter.VIEW_RANGE`;
(b) **Permanent tell** — `AltarIdleMotes` scales its window with level:
`MAX_LIVE = 2 + altarLevel`, `RING_MAX_RADIUS + 0.5·level`, so the idle altar visibly
"breathes bigger" every level, forever, with zero new server traffic (`FxBudget`
already caps the AMBIENT channel). `StatusTab`'s existing level-up sting stays as the
UI echo.

**Extend:** `ritual/AltarBlockEntity.completeMilestone`, `client/drama/AltarIdleMotes`
(level-scaled constants from `ClientStateCache.altarLevel`), new emitter JSON.

## 4. Aberration pulse on every deposit — S

The chromatic-aberration zone is the altar's "reality is wrong here" signature, but it
never *reacts*. Add a transient pulse: a static `AltarAberration.pulse(float)` sets a
decay field (e.g. +0.20, linear decay over ~15 t) that `onClientTick` adds on top of
`eased` before `EclipseFxState.setAltarAberration` (clamped ≤ `MAX_STRENGTH`, so the
frozen single-uniform contract and the border mutual-throttle predicate are untouched).
Trigger it client-side from `QuasarSpawner.spawnOrFallback` whenever the received
emitter id is `ALTAR_BEAM` (offerings + revive ritual pulses arrive for free — zero new
protocol). For shard banking, which currently sends no FX at all, add one
`S2CQuasarPayload(ALTAR_BEAM…)` after the `ShardEconomy.deposit` branch in
`AltarBlock.onSneakRightClick` — the bank clink gains a reality-shiver too. Respect
`EclipseClientConfig.reducedFx()` by skipping the pulse.

**Extend:** `client/AltarAberration` (pulse field + hook), `veilfx/QuasarSpawner`
(one-line notify), `ritual/AltarBlock.onSneakRightClick` (shard branch payload).

## 5. Milestone chime ladder: hear the altar fill up — S

`handleMilestoneDeposit` plays AMETHYST_BLOCK_CHIME at a fixed 0.8F pitch whether it's
shard 1 of 64 or the last one before the level-up. Both `updated` and `match.count()`
are already in scope — scale pitch with completion fraction:
`0.7F + 0.5F * (updated / (float) count)`, so grinding a milestone becomes an audible
ascending scale and the final deposit lands right under the END_PORTAL_SPAWN sting of
`completeMilestone` (a natural musical resolution). Multi-cost milestones get one
ladder per cost entry for free since progress keys are per-item. One line changed.

**Extend:** `ritual/AltarBlockEntity.handleMilestoneDeposit` (chime pitch expression).

## 6. Armed-offering tension window: motes hold their breath — S

Between the first (arm) and second (confirm) click there is a 100 t window carried only
by an action-bar line and a resonate ping. Make the *place* react: on the arm branch of
`handleOffering` (and `handleHeartSacrifice`), send one `S2CQuasarPayload` with a new
non-looping `offering_armed.json` (clone `altar_beam.json`: `max_lifetime` 100,
`particle_speed` ~0.05, dim #5B1E99 motes hovering in a tight column — a beam holding
its breath). If the player confirms, the accept FX punches through it; if the window
lapses, it just fades out — no cleanup needed because the emitter is one-shot with a
bounded lifetime (no `loop: true` handle obligations per `QuasarSpawner` docs).

**Extend:** `ritual/AltarBlockEntity.handleOffering` / `handleHeartSacrifice` (arm
branches), new emitter `quasar/emitters/offering_armed.json`.

## 7. Junk "sniff-and-swallow" — the altar is unimpressed — S

Junk (value 0) offerings currently get the identical triumphant beam as a diamond
block. Deliberate design tell (coarser than idea 2, still value-secret): using the same
`acceptWithValue` from idea 2, when `exactValue == 0` skip the `ALTAR_BEAM` payload and
swap the PORTAL burst for `ParticleTypes.SMOKE` plus `FIRE_EXTINGUISH` at 0.6F pitch —
the altar audibly *sighs*. This only reveals the junk/not-junk boundary (already
guessable from `config/eclipse/offering_values.json` defaults: dirt, cobble, rotten
flesh…), never the tier — and it teaches the daily ritual's stakes without text.

**Extend:** `ritual/AltarBlockEntity.handleOffering` (post-accept branch on value 0).

## 8. Shard bank counting arpeggio — M

`ShardEconomy.deposit` swallows a whole stack with a single chime — 40 shards feel
identical to 2. Add a tiny queue in `ShardEconomy` (it already subscribes
`ServerTickEvent.Post`): on deposit, enqueue `min(1 + amount / 8, 6)` follow-up chimes
for that player, pop one every 3 t, pitch rising 1.2F → 1.8F (AMETHYST_BLOCK_CHIME,
matching the existing bank sound identity). Clear the map in the existing
`onServerStopped`. Big deposits become a satisfying coin-count; the action-bar receipt
(`shop.eclipse.deposited`) already prints the totals.

**Extend:** `economy/ShardEconomy` (`deposit` + `onServerTick` queue + `onServerStopped`).

## 9. Altar breath quickens with level (idle aberration tell) — S

`AltarAberration.feedPost` bakes a fixed 0.3 Hz / ±10% breathing into the fed uniform.
Scale it with the already-synced `ClientStateCache.altarLevel`: frequency
`0.3 + 0.03·level` Hz, amplitude up to ±14% — a maxed altar breathes faster and deeper,
selling "the thing is waking up" across the whole spawn zone with zero protocol, zero
new uniforms (still CPU-side, still one frozen `Aberration`). Keep the wrap-seamless
property by choosing frequencies that divide the 100 s time wrap (0.30/0.33/0.36… all
give whole cycles per wrap if snapped to 0.01 — snap to multiples of 0.01 Hz exactly
like the existing constant).

**Extend:** `client/AltarAberration.feedPost` (+ constants), reading
`client/ClientStateCache.altarLevel`.

## 10. Dawn verdict bloom: the altar crowns yesterday's winner — M

`OfferingService.resolveDay` (PRE rollover) announces the winning *item* via
`AnnouncementService` but the altar itself stays inert. Add a physical verdict: after a
resolution with winners, fetch `EclipseWorldState.getSanctumAltarPos()` and call
`BeamEmitter.emit` 3× over ~40 t (small server-side counter in the existing rollover
listener, or three staggered sends) so everyone near spawn sees the column salute at
dawn; the winner (if online) additionally gets `EclipseSounds.OFFERING_ACCEPT` at 1.3F
via `playNotifySound` — a private "it was yours." Duplicate-cancelled days (no winners)
stay dark, which quietly teaches the duplicate rule. Guard: skip when
`getSanctumAltarPos()` is null (pre-intro worlds).

**Extend:** `offering/OfferingService.resolveDay` (post-resolution block),
`ritual/BeamEmitter` (reused as-is), winner lookup via `server.getPlayerList()`.
