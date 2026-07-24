# W4-CEREMONY wiring notes — day ritual, rewards, social, first hour (IDEA-09/-11/-10/-01 top-3s)

**No hub edits.** No `EclipseMod`, `EclipsePayloads`, `EclipseGuiLayers`, `registry/**`,
shipped lang JSON, `sounds.json` or `build.gradle` changes. New services/overlays
self-register (`@EventBusSubscriber` / nested `Registrar` / self-registrar payload group —
the `LevelUpOverlay` + `HeartsPayloads` conventions). Two shared-file diffs remain as asks
below (DayScheduler, FxPayloads); until they land the affected features are inert-safe.
Langdrop: `docs/plans_v3/langdrop/W4-CEREMONY.json` (7 keys × en/de).

## What landed

### Day ritual (IDEA-09 #1–#3)

- **`drama/DawnCeremony.java` (NEW)** — server-side beat sequencer for LOUD rollovers
  (the `ExpansionSequence` `Task`/`schedule()` pattern; statics reset on `ServerStopped`):
  T+10 sun pulse (`sendEclipsePhase` BUILDUP 0.35/10t → ENDING 0.0/30t; skipped while an
  expansion sweep is live), T+20 dawn toll (3 descending `BELL_BLOCK` strikes 1.0/0.84/0.7
  + quiet `event.eclipse_drone` tail), T+40 `AnnouncementService.onDayChanged` (moved, not
  changed), T+140 goals subtitle (`eclipse.caption.dawn.goals`, only if the day has
  goals), T+200 `AwardService.sendRevealNow` (non-expansion days only). **Inert until ask
  1 lands** — `isRunning()` is false, every rollover behaves exactly as today.
- **`awards/AwardService.onDayRollover` (POST)** — inline `sendRevealNow` now gated behind
  `DawnCeremony.isRunning(server)` so the ceremony owns the roulette timing; expansion
  days keep the END-seam call in `ExpansionSequence.beginEnd` (client dedupes by day via
  `AwardsOverlay.HANDLED_DAYS`).
- **`progression/realtime/RealtimeDayService`** — T-0 landing fix: inside the final 15 s
  (`NEAR_BOUNDARY_MILLIS`) the fire check runs on every 1 s bar pass instead of the 5 s
  `FIRE_CHECK_TICKS` poll (one extra long compare per second; epoch-day guard keeps the
  extra checks idempotent).
- **`client/hud/AnnouncementOverlay`** — the Day-Number Moment: a dequeued `STYLE_DAY`
  announcement first plays a center-screen "DAY N" numeral card (5× monospace digit
  cells, old→new odometer roll inside per-cell scissors — the `DayTimerLayer` craft — DAY
  word `GlitchText` settle, one `ui.roulette_win` sting, ~30t hold, shrink-flight toward
  the sidebar day row as the typewriter line begins). Day 14+ renders `ACCENT_DEEP`.
  `reducedFx`: static card, no roll/scramble/flight. Day number from
  `ClientStateCache.dayClockDay` (synced at T+0, ahead of the T+40 announce beat).

### Rewards (IDEA-11 #1–#3)

- **`network/rewards/RewardPayloads.java` (NEW self-registrar, version group
  `w4ceremony1`, id `eclipse:rewards/grant`)** — `S2CRewardGrantPayload(List<(itemId,
  count)>, shards, sourceKind, replay)`; presentation-only (grants already happened
  server-side), no names (anonymity law). Must NOT also be registered in
  `EclipsePayloads`.
- **`progression/goals/QuestEngine.grantRewardContents`** — now takes a `replay` flag
  (false from live `grantRewards`, true from the `deliverPendingRewards` login replay)
  and sends the payload carrying only what actually granted (unknown item ids stay
  skipped-and-warned).
- **`awards/AwardService.deliverPending`** — sends one payload per claimed pending
  reward. Public `deliverPending(player)` (login/restart callers) = replay; the
  immediate-online claim in `queueReward` after a live resolve = full variant. skill-XP-
  only rewards send nothing (XP strip + `LevelUpOverlay` own that stage).
- **`client/rewards/RewardMaterializeOverlay.java` (NEW)** — `LevelUpOverlay` skeleton
  clone (queue, `ClientTickEvent.Post`, self-registered above-all layer, F1/pause/HUD-
  suppression rules): the stack renders 2.6× in the upper third, floats down to the
  hotbar on ease-out, its name settles out of `GlitchText` noise with sparse flicker
  rects, absorb flash + `ui.unlock_sting` at touchdown. `reducedFx`: fade-in at the final
  position. `replay`: calm variant AND no sting. Shard-only grants borrow the
  `eclipse:umbral_shard` item as visual.
- **`client/awards/AwardsOverlay`** — podium moment: on SPIN-done with `localWon()`, a
  CLIENT-LOCAL `eclipse:unlock_burst` + 8-particle vanilla firework ring pop 2.4 blocks
  over the local player (visible behind the 0.85-alpha veil), `AWARD_STING` layered at
  land. Nothing is broadcast (anonymity). `reducedFx` keeps only the sting.
- **`ritual/AltarBlockEntity.completeMilestone`** — exactly ONE added send:
  `PacketDistributor.sendToAllPlayers(new S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE,
  Vec3.atCenterOf(worldPosition), 0.6F, 40.0F))` — map-wide radial light pulse (client
  path pre-exists: `EclipseFxState.startShockwave`). **Coordination W-ISLAND:** they edit
  the same method for beam/ring FX; on merge conflict keep both — this addition is only
  that one statement + comment.

### Social (IDEA-10 #1–#3)

- **`ritual/ReviveRitual`** — Witness Circle: crouching non-spectator/non-banned
  bystanders within `MAX_CONFIRMER_DISTANCE` (16) shave 40t per witness per beam pass off
  the ritual (cap −50% via `WITNESS_MAX_BONUS_TICKS`); witness count feeds the new
  `BeamEmitter.emit(level, pos, witnesses)` overload (slow-spinning ring of up to 8
  staggered `ALTAR_BEAM` quasars at r=2.5). `succeed()` now calls
  `DeathFlowHooks.onRevived(target)` directly AFTER `BanService.unban`.
  **Coordination W-HEARTS:** they add the vigil `S2CRitualVigilPayload` sends to
  `tick()`/`fail()`; this wave owns witness/duration logic only — both additive. Bonus
  ticks raise `ticksElapsed`, so their progress payload/bossbar jump forward consistently.
- **`drama/GestureGlyphService.java` (NEW)** — per-tick sneak-edge sampler
  (`WitnessedLossService` scanner model) + 4-slot ring buffer per player; recognizes
  greet (3 taps ≤2 s), danger (2 holds ≤4 s), follow-me (tap-hold-tap ≤4 s); 100t
  per-player cooldown; banned ghosts/spectators excluded. Broadcasts
  `FX_GLYPH` (`eclipse:fx/glyph`, `a` = glyph index, range 24) via the sanctioned
  `FxPayloads.sendFxEvent` seam. **Client dispatch is ask 2** — until it lands the id
  hits the unknown-id debug log (safe).
- **`client/drama/GestureGlyphFx.java` (NEW)** + emitters
  `assets/eclipse/quasar/emitters/glyph_{greet,danger,follow}.json` (NEW) — 2 s Quasar
  glyph above the gesturing player's head via the `ArmParticles`
  `QuasarSpawner.ensureAttached` pattern; FxBudget/`reducedFx` gated like every ambient
  loop.
- **`drama/HearthAuraService.java` (NEW)** — every 40t, ≥2 living players within 5 blocks
  of a lit (soul) campfire hold the circle: rotating `CAMPFIRE_COSY_SMOKE` ring + one
  heart (2 HP) regen per 30 s of continuously held circle (leaving resets the pulse).
  Ghost-ship variant: banned ghosts at the lit `ShipLanterns` soul campfires get rising
  vanilla `SOUL` motes (no regen — limbo economy untouched). No text, no names.

### First hour (IDEA-01 top 3)

- **`sequence/IntroSequence`** (this wave's edits ONLY): APPROACH stall re-nudge — every
  60 s of stalled APPROACH, re-whisper `eclipse.caption.intro.approach` + distant thunder
  (`playNotifySound` 0.3F/0.7F, per player). Logbook handoff — 15 s after the FIRST
  `finish()`, one subtitle caption + actionbar line with the live bound key name
  (`Component.keybind("key.eclipse.menu")`).
- **`limbo/LimboGate.gate`** — the ghost teleport is wrapped in
  `SequencePayloads.sendPortalEnter(4)` / `sendPortalExit(24)` + an arrival whisper
  (`eclipse.caption.limbo.arrive`).

## Wiring asks (integrator)

### 1. `DayScheduler.applyDay` — hand the loud-morning stack to the ceremony (owner: DayScheduler)

The `changed && !quiet` block currently rings the flat bell and announces inline; both
move into `DawnCeremony`'s spaced beats (persist/payload/trigger/signal order untouched):

```diff
         if (changed && !quiet) {
-            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
-                online.playNotifySound(SoundEvents.BELL_BLOCK, SoundSource.MASTER, 1.0F, 1.0F);
-            }
-            // W8: the bell is augmented by a typewriter/sweep announcement + the day's new
-            // unlock announcements, and the anonymized timeline is rebroadcast. Quiet
-            // catch-up days skip this whole stack — the unlock-key baseline then diffs all
-            // skipped days' keys into the FINAL (loud) day's announcements at once.
-            AnnouncementService.onDayChanged(server, previousDay, newDay);
+            // W4-CEREMONY IDEA-09 #1: the DawnCeremony spaces the morning beats (sun pulse →
+            // dawn toll → onDayChanged at T+40 → goals → awards roulette) over ~10 s. Quiet
+            // catch-up days still skip the whole stack (unchanged contract).
+            dev.projecteclipse.eclipse.drama.DawnCeremony.begin(server, previousDay, newDay);
         }
```

After this diff, check whether `SoundEvents`/`SoundSource`/`AnnouncementService` imports
in `DayScheduler` have other remaining uses; prune if not. **Until this lands** the
ceremony never runs and the `AwardService` POST gate falls through to today's inline
reveal — zero behavior change.

### 2. `FxPayloads.handleFxEvent` — one dispatch line for the gesture glyph (owner: FxPayloads)

```diff
         } else if (FX_DOOR_GLOW.equals(id)) {
             dev.projecteclipse.eclipse.client.ShipDoorGlow.handleDoorGlow(payload.a() > 0.5F);
+        } else if (dev.projecteclipse.eclipse.drama.GestureGlyphService.FX_GLYPH.equals(id)) {
+            // W4-CEREMONY IDEA-10 #2: pos = gesturing player, a = glyph 0 greet/1 danger/2 follow.
+            dev.projecteclipse.eclipse.client.drama.GestureGlyphFx.show(payload.pos(), (int) payload.a());
         } else {
```

The id constant (`eclipse:fx/glyph`) lives on `GestureGlyphService.FX_GLYPH`; the owner
may migrate it into the frozen `FxPayloads` id block later (string is frozen either way).
**Until this lands** glyph payloads hit the existing unknown-id debug log — safe.

### 3. Langdrop merge

Merge `docs/plans_v3/langdrop/W4-CEREMONY.json` into the shipped
`assets/eclipse/lang/en_us.json` / `de_de.json`. All 7 keys resolve client-side
(`EclipseLang` / caption renderer / `Component.translatable`), so both locales go into
the client lang files. No new sound events, no new textures (the three glyph emitters
reuse `textures/particle/purple_wisp.png`).

## Risks / behavior notes

- **Double-reveal safety:** `sendRevealNow` may fire from both the ceremony and the P2
  expansion END seam on weird day shapes; the client dedupes per day
  (`AwardsOverlay.HANDLED_DAYS`) — verified unchanged.
- **Ceremony vs. restart:** a server stop mid-ceremony drops pending beats (payloads are
  re-broadcastable presentation; day state was already committed at T+0).
- **Day card old number** is client-derived (`lastCardDay`, else `day-1`); a dev
  multi-day jump rolls from the last number that client actually saw.
- **Witness circle pacing:** each beam pass (20t) can shave at most
  `witnesses × 40t` capped at half the ritual; the W-HEARTS vigil payload reads the same
  `ticksElapsed`, so the ghost's fill jumps forward in sync.
- **Reward payload scope:** one payload per grant event; the overlay shows the first
  stack + "+n more" label (calm pacing) rather than one card per stack.
- **Hearth regen** is the event's only ambient regen (2 HP / 30 s / ≥2 players): tuned
  conservative, constants at the top of `HearthAuraService`.
