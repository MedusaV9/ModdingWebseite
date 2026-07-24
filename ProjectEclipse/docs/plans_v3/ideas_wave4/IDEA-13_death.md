# IDEA-13 — Death/Revive Emotional Arc (Wave 4, Collector 13/20)

Scope: `client/death/` (EclipseDeathScreen, DeathFlowController, DeathScreenSwap, GhostHeartsLayer),
`lives/DeathFlowHooks` + `lives/LifecycleEvents`, `ritual/ReviveRitual`, ghosts (`GhostGradeFx`,
`BanService` limbo state), and the user's explicit ask: **purple hearts as THE player hearts
renderer** + **lost hearts bursting over the hotbar on respawn**, with a verification of
`hearts/client/HeartBurstOverlay` and the exact completion.

All findings verified read-only against source; no gradle, no commits.

---

## 1. What exists today (verified)

**The death → ship → home arc is complete and robust.**
- `lives/LifecycleEvents.onLivingDeath` (NORMAL) decrements the heart, records a
  `PendingHeartLoss(previousHearts, heartIndex, diedAtMillis)` keyed by UUID (TTL 1 h,
  survives relog), does kill transfer, bans at 0.
- `lives/DeathFlowHooks.onLivingDeath` (LOW — after the decrement) sends
  `S2CDeathStatePayload(PHASE_DEATH, heartsRemaining, ghost, lostHeartIndex, causeKey, holdTicks)`.
- `client/death/DeathScreenSwap` swaps the exact vanilla `DeathScreen` for `EclipseDeathScreen`
  (kill-switch `customDeathScreen`, read per opening).
- `EclipseDeathScreen` plays the lost heart's shatter at 2× from the shared
  `textures/gui/hearts/burst_sheet.png` (ghost: last heart at 4× + translucent ghost row fade-in),
  hold-gated button with accent hairline, limbo-motes ash emitter, 15 s failsafe.
- `DeathFlowHooks.onPlayerRespawn` (LOWEST) captures the real respawn point and teleports to the
  limbo deck; `SHIP_WAKE (30 t) → DOOR_OPEN (walk / sneak-skip / 100 t auto) → RETURN_FADE (14 t)`
  with hard caps (160/240 t). The 30-tick ship-wake beat exists **specifically** "to let the
  hotbar heart burst play out" (comment on `SHIP_DOOR_DELAY_TICKS`).
- **The respawn hotbar burst already exists**: `LifecycleEvents.onPlayerRespawn` pops the pending
  loss and sends `S2CHeartBurstPayload(heartIndex)` (→ `HeartBurstOverlay.trigger`) plus a
  world-space `S2CQuasarPayload(HEART_BURST)` at the player.
- **Revive**: `DeathFlowHooks.watchForRevives` detects any banned→unbanned flip (altar ritual,
  admin, offline-revive login) and runs `onRevived` — `S2CRevivedPayload(heartsRestored)` →
  `GhostHeartsLayer.beginReviveBurst` (5 ghost hearts burst one-by-one, 8 t stagger,
  `UiSounds.ghostBurst()` each), deck teleport, `REVIVE_BURST (55 t)` → door → home.
- **Ghosts**: `GhostHeartsLayer` cancels `VanillaGuiLayers.PLAYER_HEALTH` while
  `ClientStateCache.lives <= 0` (with `leftHeight += 10` compensation) and renders 5 translucent
  cracked hearts (`hud/heart/frozen_full` + crack hairlines) + "GEIST" tag; `GhostGradeFx` runs the
  `eclipse:ghost_grade` post pipeline fed by `S2CGhostStatePayload` → `EclipseFxState.setGhost`.

**Adjacent drama already landed** (do not duplicate): `WitnessedLossService` (24-block purple
vignette pulse + muffled crack for bystanders on permanent heart loss, incl. the two non-death
call sites), `LastHeartEmber` (wisp trail on remote 1-heart players, read from synced MAX_HEALTH),
`LastMinuteHush` (accelerating heartbeat before day end).

## 2. Verification of `hearts/client/HeartBurstOverlay` — and the exact completion

What it does today:
- Renders flash (2 t) → crack frames (3 t) → 14-fragment shatter (8 rotating shards on
  gravity+drag arcs + 6 white→violet spark pops, 12 t) **over the exact vanilla heart lost**,
  reconstructing vanilla row geometry (multi-row compression, ≤4 hp jitter) from the public
  post-layer `Gui.leftHeight` in `heartPosition(...)`.
- Also owns the 1–2-lives dread: warden heartbeat at pitch floor 0.5 every 40 t + pulsing red
  edge vignette (both gated by `heartbeatSound`/`reducedFx`; silent for 0-lives ghosts).
- Registered `registerAbove(PLAYER_HEALTH, ...)` in `EclipseGuiLayers` and whitelisted against
  cutscene HUD suppression.
- Javadoc contract: *"This layer augments, and never replaces, the vanilla health layer."*

Three verified gaps:
1. **Base hearts are still vanilla red.** Nothing replaces `PLAYER_HEALTH` outside ghost mode.
   Meanwhile a purple heart asset already exists: `assets/eclipse/textures/gui/heart_full.png`
   (9×9, ~#7841B8 purple; `heart_empty.png` beside it) — today used only by the handbook
   StatusTab. `asset_audit.md` even flags the manifest-vs-code path split
   (`gui/hearts/heart_*.png` expected, `gui/heart_*.png` shipped).
2. **Single burst slot.** `trigger(int)` overwrites the static pair `heartIndex`/`animationTick`.
   Consequence today: `HeartExtractorItem` costs **2** hearts (`HEART_COST = 2`) but sends one
   `S2CHeartBurstPayload(heartsAfter)` → only ONE heart shatters. The altar heart sacrifice
   (`AltarBlockEntity`, `LivesApi.add(player, -1)` at ~line 271) sends **no** burst at all.
3. **Geometry coupling.** `heartPosition(...)` depends on the vanilla health layer having run
   (it reads `gui.leftHeight` post-layer). Replacing the renderer without sharing geometry
   desyncs the shatter from the drawn hearts.

**Exact completion (pairs with idea R1 + R2 below):**
- Replace the two static ints with a fixed-capacity queue (e.g. `int[8]` heartIndex +
  `int[8]` startOffset; capacity = `HeartsService.MAX_HEARTS + 1`), stagger repeated triggers by
  8 t (`GhostHeartsLayer.BURST_STAGGER_TICKS` precedent); one glass-crack cue per burst start.
- Extract the row math into a shared `hearts/client/HeartRowGeometry.heartPosition(...)` used by
  both `HeartBurstOverlay` and the new purple layer — pixel-exact shatter over the purple heart.
- Add the two missing senders: `AltarBlockEntity` heart sacrifice → one
  `S2CHeartBurstPayload(LivesApi.get(player))` (+ the `S2CQuasarPayload(HEART_BURST)` world echo,
  mirroring `LifecycleEvents.onPlayerRespawn`); `HeartExtractorItem` → two payloads
  (indices `heartsAfter`, `heartsAfter + 1`) that the queue staggers.
- When the purple layer is on, tint the burst frames toward the accent
  (`guiGraphics.setColor` with `EclipseUiTheme.ACCENT` family) so debris matches the heart color.

## 3. Ten ranked ideas

| # | Idea | Size | Primary hooks |
|---|------|------|---------------|
| R1 | Purple hearts as THE player hearts renderer | M | new `hearts/client/PurpleHeartsLayer`; `RenderGuiLayerEvent.Pre`; `EclipseGuiLayers` |
| R2 | HeartBurstOverlay completion: burst queue + non-death senders + shared geometry | S | `HeartBurstOverlay`; `AltarBlockEntity`; `HeartExtractorItem` |
| R3 | Revive re-light: real hearts return one-by-one after the ghost burst | S | `PurpleHeartsLayer`; `GhostHeartsLayer` BURST exit |
| R4 | Ritual vigil: the ghost's cracked hearts slowly re-knit with ritual progress | M | `ReviveRitual.tick`; new small S2C payload; `GhostHeartsLayer` |
| R5 | Kill-transfer reverse burst: a gained heart materializes | S/M | `LifecycleEvents.onLivingDeath` kill branch; `HeartBurstOverlay` reverse timeline |
| R6 | Ghost grade pre-warm at the death screen | S | `DeathFlowHooks.onLivingDeath`; `FxPayloads.sendGhostState` |
| R7 | Deck revive celebration: world-space bursts synced to the 5 HUD bursts | S | `DeathFlowHooks.tickShipFlow` REVIVE_BURST stage |
| R8 | Last-heart hush: quiet burst variant when dropping to 1 heart | S | `HeartBurstOverlay.trigger/render` |
| R9 | Witnessed loss: world-space heart burst at the victim for bystanders | S | `WitnessedLossService.onLivingDeathLate` |
| R10 | Ghost phantom pulse: sparse throb of the cracked row | S | `GhostHeartsLayer.onClientTick/render` |

### R1 — Purple hearts as THE player hearts renderer (M)
New `hearts/client/PurpleHeartsLayer` (self-registered `@EventBusSubscriber(Dist.CLIENT)`, the
GhostHeartsLayer convention). `RenderGuiLayerEvent.Pre` cancels `VanillaGuiLayers.PLAYER_HEALTH`
and re-adds vanilla's exact `leftHeight` increment (`10 + (rows-1)*rowStep`, the formula already
replicated in `HeartBurstOverlay.heartPosition`); layer body registered
`registerAbove(PLAYER_HEALTH, ...)` in `EclipseGuiLayers`, **below** `HeartBurstOverlay.LAYER_ID`
so shatters draw on top. Rendering: vanilla `hud/heart/container` sprite + the existing purple
9×9 `textures/gui/heart_full.png` (promote/copy to the manifest's canonical
`textures/gui/hearts/` path; add a purple `heart_half.png`, ~30 min of palette-shift art) with
vanilla parity: absorption row, regen-wave y-offset, damage-flash blink (container highlight),
≤4 hp jitter (reuse `HeartRowGeometry`). Precedence: defer entirely while
`GhostHeartsLayer` owns the slot (add package-private `GhostHeartsLayer.isOwningHealthSlot()`;
prevents double `leftHeight` compensation). Kill-switch: new `purpleHearts` toggle in
`EclipseClientConfig` (the `customDeathScreen` precedent) — off = pure vanilla layer, zero risk.
Bonus consistency: `EclipseDeathScreen.renderHeartRow`/`renderGhostHearts` swap
`hud/heart/full` for the purple sprite when the toggle is on. Risk note: mods hooking
PLAYER_HEALTH (none in-repo) see it cancelled — same exposure GhostHeartsLayer already accepts.

### R2 — HeartBurstOverlay completion (S)
Exactly §2 above: fixed-capacity burst queue with 8 t stagger, `HeartRowGeometry` extraction,
altar + extractor senders, accent tint under `purpleHearts`. Ships independently of R1 (queue +
senders are valuable against vanilla hearts too).

### R3 — Revive re-light: hearts return one-by-one (S)
Today `GhostHeartsLayer` BURST ends (`BURST_TOTAL_TICKS`) and the full red row snaps back.
With R1: when BURST exits to IDLE with `lives > 0`, hand `S2CRevivedPayload.heartsRestored`
to `PurpleHeartsLayer.beginRelight(count)` — hearts fill left-to-right 4 t apart, each with a
one-frame white flash and a soft chime (reuse `UiSounds` unlock family at low volume). The
55-tick server `REVIVE_BURST` beat (5×8 t bursts + tail) already leaves room before
`DOOR_OPEN`. Pure client state; no protocol change.

### R4 — Ritual vigil: the ghost watches their hearts re-knit (M)
During `ReviveRitual` (3 min, bossbar RED for everyone), the *target ghost* currently sees only
the same bossbar. Add: `ReviveRitual.tick()` every 20 t sends a tiny new
`S2CRitualVigilPayload(progress: float, active: boolean)` to the online target (register in
`network/death/DeathFlowPayloads` version group or a sibling registrar — NOT `EclipsePayloads`,
duplicate-id rule). `GhostHeartsLayer` renders the crack hairlines fading out and a faint violet
fill rising across the 5 hearts proportional to progress; on ritual fail send
`active=false` → cracks return over 20 t (a gut punch). No text, no names — consistent with the
anonymity law. Failure/logout cleanup mirrors the bossbar removal paths already in
`ReviveRitual` (`fail()`, `onServerStopping`).

### R5 — Kill-transfer reverse burst (S/M)
`LifecycleEvents.onLivingDeath` grants the killer +1 heart (+1 more for the umbral blade) with
zero HUD feedback today. Send the killer `S2CHeartBurstPayload` with a new `gained` flag (add a
boolean to the record — its `StreamCodec` is composite already; version-group bump is contained)
or a distinct payload id. Client: `HeartBurstOverlay` plays the shatter timeline REVERSED —
sparks converge, shards fly inward, heart materializes violet then settles — over the newly
filled slot (`index = LivesApi.get(killer) - 1` server-side). Emotional counterweight: taking a
heart should *feel* like taking one.

### R6 — Ghost grade pre-warm at the death screen (S)
`S2CGhostStatePayload(true)` is sent only on respawn (`DeathFlowHooks.onPlayerRespawn` banned
branch), so the ghost grade snaps in after the death screen closes. Move the first send earlier:
in `DeathFlowHooks.onLivingDeath`, when `flow.ghost`, also `FxPayloads.sendGhostState(victim,
true)` — `EclipseFxState` eases over 30 t behind the ghost death screen (the 40-tick
`HOLD_TICKS_GHOST` gate absorbs it), so "Als Geist erwachen" lands inside an already-graded
world. Safe: `BanService.ban` already ran (NORMAL before LOW); the respawn resend stays as the
idempotent refresh.

### R7 — Deck revive celebration world FX (S)
The 5 HUD ghost-heart bursts play during the server's `REVIVE_BURST` stage, but the deck itself
is static. In `DeathFlowHooks.tickShipFlow` case `REVIVE_BURST`: at `stageTicks % 8 == 0 &&
stageTicks <= 40` send `S2CQuasarPayload(HEART_BURST, player.position().add(0, 1.2, 0))` to
players in limbo (the `LifecycleEvents.onPlayerRespawn` pattern) — the revived player *and any
ghost still aboard* see five rising violet bursts in sync with the HUD. FX budget: HEART_BURST
is an existing one-shot emitter; 5 spawns over 2 s is within the IMPACT channel discipline.

### R8 — Last-heart hush burst variant (S)
When a burst leaves the player at exactly 1 heart (`ClientStateCache.lives == 1` at `trigger`
time), play the variant: no spark pops, shards fall almost straight down (gravity up, drag up),
the red vignette holds ~3× longer, and the glass-crack cue pitches down to 0.7. The very next
tick the existing 1–2-lives heartbeat + pulse take over — the hush hands off into the dread
loop. Pure constants branch inside `HeartBurstOverlay.render/drawShards`; `reducedFx` unaffected
(it already never gates the burst itself, only heartbeat/pulse).

### R9 — Witnessed loss: world-space burst for bystanders (S)
`WitnessedLossService.onLivingDeathLate` already sends witnesses the vignette pulse + muffled
crack. Add the visual anchor: one `S2CQuasarPayload(HEART_BURST, victim.position().add(0, 1.0,
0))` to each witness (NOT the victim — theirs replays on respawn) so bystanders see *where* the
heart broke. Same 24-block radius loop, one extra payload per witness; respects the existing
FX-budget client path.

### R10 — Ghost phantom pulse (S)
Ghosts deliberately lose the heartbeat (0 lives = silence). Give them a *sparser* signature:
every ~300 t (`modeTicks` in `GhostHeartsLayer.onClientTick`, GHOST mode only) one heart of the
cracked row throbs — alpha 0.62 → 0.78 → 0.62 over 12 t (index = `(modeTicks / 300) % 5`) with a
single muffled warden beat at 0.25 volume, gated by `heartbeatSound` + `reducedFx`. The ghost
feels *almost* dead — which is exactly what makes R4's re-knitting vigil land.

---

## Top 3

1. **R1 — PurpleHeartsLayer**: promote the existing purple 9×9 heart art to the always-on
   player hearts renderer (cancel PLAYER_HEALTH + leftHeight compensation, GhostHeartsLayer
   precedence, `purpleHearts` kill-switch, shared `HeartRowGeometry`).
2. **R2 — HeartBurstOverlay completion**: burst queue (fixes the extractor's missing second
   shatter), altar/extractor senders, geometry unification, accent tint — the respawn hotbar
   burst itself already exists and stays untouched.
3. **R4 — Ritual vigil**: sync `ReviveRitual` progress to the ghost's cracked HUD hearts so the
   3-minute revive becomes something the ghost *watches happen to their own hearts*.
