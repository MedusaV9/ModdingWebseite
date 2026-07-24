# IDEA-10 — Multiplayer Social Moments under Anonymity (Wave 4, collector 10/20)

**Focus:** social moments that work when proximity voice (Simple Voice Chat, soft-dep via
`voice.EclipseVoicePlugin`) is the ONLY channel — chat is cancelled (`anonymity.ChatBlocker`),
signs/books/anvil names are blocked (`anonymity.TextInputBlocker`,
`anonymity.mixin.ServerGamePacketListenerImplMixin`), tab list / name tags are hidden, and every
player wears `assets/eclipse/textures/entity/uniform_skin.png`. Ghosts
(`lives.BanService` limbo ghosts + `ghosts.LogoutGhostService` logout ghosts) and revives
(`ritual.ReviveRitual`, `lives.DeathFlowHooks`) are the strongest existing social beats.

All FX below ride the existing frozen plumbing: `network.fx.FxPayloads.sendFxEvent(level, id,
pos, a, b, range)` (add new frozen `eclipse:fx/*` ids next to `FX_LIGHTNING_STRIKE` etc.),
`S2CQuasarPayload` + `veilfx.QuasarSpawner.ensureAttached/spawnOrFallback` for emitters
(new JSONs go in `assets/eclipse/quasar/emitters/`, budget-guarded by `veilfx.FxBudget`),
and the server-side signal bus `core.signal.EclipseSignals`. No idea introduces text or names.

Sizes: **S** = one new service class + one FX id/emitter, no schema changes.
**M** = new service + payload/emitter + 1–2 seams in existing frozen classes.

---

## Ranked ideas

### 1. Revive Witness Circle — the ritual becomes a ceremony (M)
The 3-minute `ritual.ReviveRitual` already broadcasts a global RED bossbar and a
`BeamEmitter.emit` beam every 10 ticks, but bystanders are scenery. Make witnessing mechanical:
every player (other than the confirmer) crouching within `ReviveRitual.MAX_CONFIRMER_DISTANCE`
(16 blocks) of the altar counts as a *witness*.
- **Hook:** in `ReviveRitual.tick()`, alongside the existing confirmer distance check, count
  crouchers via `level.players()` + `player.isShiftKeyDown()` (same predicate
  `ritual.AltarBlock` line ~74 and `ritual.FinaleRitual` line ~103 already use).
- **Effect:** each witness shaves 2 s/tick-batch off `DURATION_TICKS` (cap: −50%) and bumps the
  beam: pass a witness count into `BeamEmitter.emit` and send one extra staggered
  `S2CQuasarPayload(ALTAR_BEAM)` ring per witness. On success, call
  `lives.DeathFlowHooks.onRevived` directly — its javadoc explicitly says the revive ritual
  *may call it right before `BanService.unban` for a flash-free celebration* and it is
  currently only reached via the per-tick unban watch. The revived ghost walks out of the
  Respawn Door into a crowd that made it faster. Voice does the rest.

### 2. Sneak-Pattern Gesture Glyphs — body language becomes vocabulary (M)
Uniform skins erase identity but not motion. Detect short sneak rhythms server-side and echo
them as particle glyphs above the head — a wordless, name-free emote system.
- **Hook:** new `social/GestureService` `@EventBusSubscriber` on `ServerTickEvent.Post`
  (pattern of `drama.WitnessedLossService`): sample `player.isShiftKeyDown()` per player,
  keep a small ring buffer of press edges. 3 taps <2 s = *greet*; 2 long holds = *danger*;
  tap-hold-tap = *follow me*.
- **Effect:** on recognition, `FxPayloads.sendFxEvent(level, FX_GLYPH, player.position(),
  glyphIndex, 0, 24)` (new frozen id; `a` = glyph index like the existing `a`/`b` semantics
  table in `FxPayloads`). Client handler attaches a 2-s one-shot emitter above the head via
  `QuasarSpawner` — new `glyph_greet.json` / `glyph_danger.json` / `glyph_follow.json`
  emitters (copy `unlock_burst.json` scale). `client.ArmParticles` is the exact template for
  the per-player attach/remove loop. Anti-spam: 5 s cooldown per player, `FxBudget` gate.

### 3. Campfire Hearth Aura — a place to gather is a reason to talk (S)
Proximity voice needs proximity magnets. Lit (soul) campfires already exist in the world
(`worldgen.fog.FogStormSites` places one; the ghost ship's four soul-campfire lanterns are
pinned by `limbo.ShipLanterns.positions`).
- **Hook:** new `social/HearthService` scanning every 40 ticks (server tick, cheap AABB) for
  ≥2 non-ghost players within 5 blocks of a lit campfire block.
- **Effect:** while the circle holds, send a shared warm ring — `sendParticles` with
  `ParticleTypes.CAMPFIRE_COSY_SMOKE` exactly as `entity.boss.fog.FogBankMarker` does for its
  fog pillars — plus a 1-heart-per-30 s regen pulse (only regen source in a hardcore event =
  strong pull). Ghost-ship variant: banned ghosts idling at `ShipLanterns` campfires get soul
  motes (`limbo_motes.json` emitter), making limbo waiting a shared vigil instead of solitary.

### 4. Team-Goal Joint Cheer — everyone flares at once (S)
`progression.goals.QuestEngine` fires the `EclipseSignals.questCompleted` signal and
`timeline.AnnouncementService.announceGoalCompleted` shows the typewriter banner — but the
moment is per-screen, not spatial.
- **Hook:** register a `QuestCompletedListener` on `EclipseSignals` (kind 0 = main / team, per
  `QuestSpecRef.kind()` wire encoding) in a new `social/CheerService`.
- **Effect:** for every online player, spawn `unlock_burst.json` at their own position via
  `S2CQuasarPayload` — so groups standing together see a *cluster* of bursts and instinctively
  cheer on voice. Bonus window: players who crouch within 5 s add one extra burst at their
  feet (reuse the `GestureService` sampler from idea 2), turning completion into a shared
  physical "raise the glass" beat. `QuestApi.completeTeamBeat(server, "player_revived")`
  already routes revives through this same path, so idea 1 stacks for free.

### 5. Silent Trade Ritual — commerce without a single word (M)
Trading today is toss-and-trust. Formalize it: two crouching players within 3 blocks each
drop one item; the stacks hover between them in a wisp pillar for 3 s, then cross over.
- **Hook:** new `social/SilentTradeService` subscribing to `ItemTossEvent` + the crouch
  proximity check; hold both `ItemEntity`s with `setPickUpDelay`, swap owner targeting after
  the dwell (abort + return if either player stops crouching or steps away — same
  "confirmer strayed" guard style as `ReviveRitual.tick()`).
- **Effect:** pillar FX = `supply_spark.json` emitter at the midpoint via `S2CQuasarPayload`;
  completion chime = each side's `playNotifySound` (pattern: `ReviveRitual.succeed()`).
  Fire the existing `EclipseSignals.TRADE` signal so analytics/awards
  (`awards.AwardService`) can count silent trades — a natural "Merchant of the Veil" award.

### 6. Whisper Motes — directed voice made visible (M)
Simple Voice Chat's `MicrophonePacketEvent` (already consumed by
`voice.EclipseVoicePlugin.onMicrophonePacket` for mutes) exposes whisper state on the packet.
- **Hook:** in the same plugin (the *only* class allowed to import the SVC API, per its
  javadoc), on a non-cancelled whisper packet from a crouching sender, throttle-send
  `FxPayloads.sendFxEvent(FX_WHISPER_ARC, senderPos, 0, 0, 8)` at most once per second.
- **Effect:** a faint mote arc (new `whisper_arc.json`, additive, low count) drifts from the
  whisperer toward their look vector — nearby players *see* someone confiding without hearing
  it, and conspiracies become visible theater. Respects `VoiceMuteApi.isMuted` automatically
  because the event is already cancelled before this code runs. Entry-muted newcomers
  (10-min `FIRST_OVERWORLD_JOIN` mute) get nothing — correct, since they cannot speak.

### 7. Offering Chorus — synchronized daily tribute (S)
`offering.OfferingService.accept` consumes one item per player per day at the altar and fires
`EclipseSignals.altarDeposit(purpose = OFFERING)`.
- **Hook:** new listener on `AltarDepositListener` in `social/ChorusService`: track offering
  timestamps per altar; when ≥3 distinct players offer at the same altar within a rolling
  60 s window, trigger the chorus.
- **Effect:** one shared `altar_reveal_burst.json` emitter + a low bell via `playNotifySound`
  for everyone within `BeamEmitter.VIEW_RANGE`-style radius (use 64), and credit a small
  award-point bonus through `awards.AwardService`/`AwardMath` (OfferingService already
  imports both). Creates a daily "meet at the altar at dusk" appointment that voice groups
  self-organize around — no schedule text needed, the world teaches it.

### 8. Last-Heart Ember Escort — visible fragility invites protection (S)
`drama.WitnessedLossService` pulses witnesses when a MAX heart shatters (24-block
`S2CShakePayload` marked-vignette + muffled crack), and `client.drama.LastHeartEmber` shows
the *owner* their own last-heart state — but escorts can't see who to shield.
- **Hook:** server side, in the same place `WitnessedLossService.onHeartLost` runs, check
  `LivesApi.get(victim) == 1` and start a persistent per-player FX flag; sync via the existing
  `S2CFxEventPayload` (id `FX_EMBER_ON`/`FX_EMBER_OFF`, pos = player) to players within 16.
- **Effect:** client attaches a dim ember wisp at chest height (reuse `arm_wisps.json`
  parameters, ember palette; attach loop copied from `ArmParticles.onClientTick`). No name, no
  bar — just a small fire that says *walk close to me*. Clears on heart regain
  (`hearts.HeartsService`) or death.

### 9. Peaceful Ghost Reveal — kneel instead of punch (S)
`ghosts.LogoutGhostService.onGhostHurt` reveals a logout ghost's owner name (32-block
`S2CGhostRevealPayload`) — but only violence triggers it, which reads hostile for a mourning
mechanic.
- **Hook:** extract the reveal body of `onGhostHurt` into `reveal(LogoutGhostEntity)` (keeps
  the `revealCooldownSeconds` map), then add a check in `LogoutGhostEntity`'s server tick
  (next to the existing 100-tick `LogoutGhostService.isValid` self-check cadence): any player
  crouching within 2 blocks for 40 consecutive ticks triggers `reveal`.
- **Effect:** kneeling at a ghost to learn who left becomes a quiet social ritual — groups on
  voice gather, kneel, and react to the name together. Zero new payloads; the existing
  `GhostConfig` cooldown prevents spam.

### 10. Send-Off Vigil — farewell for the newly banned (M)
When `lives.BanService.ban` ships a 0-heart player to the limbo ghost ship, they vanish
mid-fight with no beat for the survivors.
- **Hook:** in `lives.DeathFlowHooks` (which already layers "theater" on top of the untouched
  `LifecycleEvents`/`BanService` economy — LOW-priority `LivingDeathEvent`), when the death
  produced a ban (post-death `BANNED` attachment true, the same post-truth ordering the class
  documents), open a 30 s vigil window at the death position.
- **Effect:** each player who crouches within 8 blocks during the window adds one soul mote
  that spirals up (`vortex_wisp.json` one-shot per participant via `S2CQuasarPayload`); when
  the window closes, participants ≥2 → one `FX_DOOR_GLOW`-style flash and the ghost receives
  `playNotifySound` (soul bell) *in limbo* — they learn, wordlessly, that people knelt for
  them. Ties directly into the revive economy: vigils emotionally prime the group to farm the
  `REVIVE_SIGIL` (consumed in `ReviveRitual.consumeSigil`).

---

## Cross-cutting notes

- **No text anywhere** — every idea communicates via particles, sound cues and the existing
  bossbar/vignette surfaces, matching the "No chat output anywhere" contract stated in
  `ReviveRitual`'s javadoc.
- **Ghost exclusion:** ideas 2–5 and 7 should skip banned ghosts (check
  `EclipseAttachments.BANNED`, the same predicate `LogoutGhostService.shouldSkip` uses) so
  limbo stays muted except where deliberately included (ideas 3, 10).
- **Lang:** any new subtitle/actionbar keys ship as `docs/plans_v3/langdrop/IDEA-10.json`
  (en_us + de_de) per the langdrop workflow — never edit the two lang JSONs directly.
- **Perf guardrails:** all tick scanners follow the `WitnessedLossService` model (early-out on
  empty, radius² comparisons); all client FX go through `FxBudget`.
