# IDEA-11 — Reward Ceremonies (Eclipse Event, ideas wave 4, collector 11/20)

Scope: awards roulette (`client/awards/AwardsOverlay` + `RouletteStrip`, server `awards/AwardService`),
level-ups (`client/skills/LevelUpOverlay`), advancement unlocks (`skills/AdvancementXpBridge`),
altar milestone rewards (`ritual/AltarBlockEntity.completeMilestone` + `progression/UnlockState`),
quest completion (`progression/goals/QuestEngine.completeForPlayer/completeTeam/grantRewardContents`).

## House laws every idea below already respects

- **FX budget law (P2 §3.5):** every Quasar spawn goes through `veilfx/QuasarSpawner` and charges
  `FxBudget` (BURST for one-shots). Budget refusal = silent drop, never a vanilla fallback flood.
- **`reducedFx` gate:** all non-essential flourishes skip or calm down under
  `EclipseClientConfig.reducedFx()` (see `LevelUpOverlay.start`, `AwardsOverlay.renderFlare`).
- **Anonymity law:** the daily-awards reveal carries UUIDs only; the ONLY identity ever shown is the
  localized "YOU" for the local player (`AwardsOverlay.renderWinnerLabel`). Any *in-world* FX visible
  to others over a winner's head would deanonymize — winner-targeted FX must stay **client-local**.
- **HUD overlay, never a Screen:** celebrations are GUI layers registered via
  `RegisterGuiLayersEvent`; input is never captured (AwardsOverlay/LevelUpOverlay pattern).
- **Offline rewards exist:** team-quest rewards can be queued and delivered at login
  (`QuestEngine.deliverPendingRewards`) — reward FX hooks must handle the login-replay path
  (play a calm variant or skip, mirroring the AwardsOverlay `LATE_JOIN_GRACE_TICKS` rule).

## Ranked ideas

### 1. Reward item materialization — item floats down with glitch shimmer (M)

When a quest/award grants items or shards, the stack visibly *materializes*: the reward item
renders 2–3× scale in the upper third of the screen, floats down toward the hotbar on an
ease-out curve, its name settling out of `GlitchText.scramble` noise (the settled-prefix +
scrambled-tail trick from `AwardsOverlay.renderRewardLine`), with sparse `ACCENT_DEEP` flicker
rects, then an absorb-flash + sting as it lands.

- **Server hook:** `QuestEngine.grantRewardContents(player, goalId, reward)` is the single choke
  point for shard + item quest rewards (also reached by `deliverPendingRewards` login replays —
  send a `replay` flag so the client plays the calm variant). Award-day reward delivery lives in
  `awards/AwardService`; same payload from there.
- **Transport:** new `S2CRewardGrantPayload(List<(itemId,count)>, shards, sourceKind, replay)`
  registered in `network/EclipsePayloads`, cached into `ClientStateCache` like the award reveal.
- **Client:** new `client/rewards/RewardMaterializeOverlay`, a carbon copy of the
  `LevelUpOverlay` skeleton (ArrayDeque queue, `ClientTickEvent.Post`, above-all layer,
  `CameraDirector.isHudSuppressed()` deferral, F1/pause rules). Item drawn with
  `GuiGraphics.renderItem` under a scaled pose; landing flash reuses `easeOutBack` from
  `AwardsOverlay`. Sound: `EclipseSounds.UI_UNLOCK_STING` on land. `reducedFx`: fade-in at final
  position, no scramble/flicker.
- **Why #1:** one payload + one overlay upgrades *every* reward surface (quests, awards, and
  later altar/advancement grants can reuse the payload).

### 2. Roulette podium moment — in-world flare over the local winner (S)

The instant the head strip lands on "YOU", the celebration escapes the UI: a client-local
firework/flare burst pops ~2.4 blocks above the local player in the world (visible around the
overlay veil's edges — gameplay renders behind the 0.85-alpha veil, so the world lights up purple
behind the card).

- **Hook (one method):** `AwardsOverlay.advance()`, `case SPIN` — inside the
  `reveal.strip().done()` branch (where `landAge = 0; setPhase(Phase.LAND)`): if
  `reveal.localWon() && !EclipseClientConfig.reducedFx()`, call
  `QuasarSpawner.spawnOrFallback(eclipse:unlock_burst, player.position().add(0, 2.4, 0))`
  (BURST channel) plus a ring of ~8 vanilla `ParticleTypes.FIREWORK` via `level.addParticle`.
- **Anonymity:** client-local only — nothing is broadcast, so co-players learn nothing.
  (A server-broadcast "fireworks over the winner" variant is deliberately rejected: it would
  break the reveal's UUID-only anonymity design. See idea 7 for the anonymity-safe global cue.)
- **Polish:** layer `EclipseSounds.AWARD_STING` at land instead of only at stat-line end;
  optionally re-trigger a smaller burst per additional category won.

### 3. Altar milestone map-wide light pulse (S)

Completing an altar milestone ripples a radial light pulse across the whole map for every
player — the world itself acknowledges the unlock.

- **Hook:** `AltarBlockEntity.completeMilestone(serverLevel, state, milestone)` — after the
  `S2CDayStatePayload` broadcast, add
  `PacketDistributor.sendToAllPlayers(new S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE,
  Vec3.atCenterOf(worldPosition), strength, durationTicks))`.
- **Client path already exists:** `network/fx/FxPayloads` routes `FX_SHOCKWAVE` into
  `EclipseFxState.startShockwave(pos, a, b)`, whose eased `shockwaveParams` scratch vector is
  already consumed by the registered Veil post pipeline (`VeilPostController` rows) — zero new
  client code for the base version.
- **Stretch (still S/M):** scale `strength` with `milestone.level()`; couple with a 40-tick
  golden `exposureMul` lift in `EclipseFxState` (new scalar fed to `eclipse:world_grade`) so the
  pulse reads as *light*, not impact. Iris-shaderpack sessions gracefully skip (post FX hard
  gate in `VeilPostController`), which is why the beam in idea 4 should ship together.

### 4. Altar milestone reward-beam ceremony (S)

The milestone completion cue today is only 150 portal particles + an end-portal sound
(`completeMilestone`). Give it the offering treatment, scaled up: the checked-in
`eclipse:altar_beam` Quasar column fires skyward from the altar plus an `altar_reveal_burst`
crown, so anyone in render distance sees *where* the ceremony happened.

- **Hook:** `AltarBlockEntity.completeMilestone` — copy the exact
  `PacketDistributor.sendToPlayersNear(..., new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM,
  Vec3.atCenterOf(worldPosition).add(0, 0.7, 0)))` call from `handleOffering` (lines ~236–240),
  widen the radius, and add a second `S2CQuasarPayload` for `eclipse:altar_reveal_burst`
  (emitter JSON already exists in `assets/eclipse/quasar/emitters/`, currently unreferenced
  by any payload constant — add it to `S2CQuasarPayload`'s well-known ids).
- **Pairs with idea 3:** beam = world-space anchor (works under Iris), pulse = post-FX glory.
  `FxAnchors.ALTAR_CENTER` already syncs the altar position to all clients if a longer
  client-side afterglow loop is wanted.

### 5. Skill milestone level crescendo — 10/25/40 (S)

Levels 10/25/40 already award advancements (`AdvancementXpBridge.MILESTONE_LEVELS`), but the
level-up celebration is identical for level 2 and level 40. Milestone levels deserve a crescendo:
bigger world flourish + longer glyph hold + a client-local mini-shockwave.

- **Hook (one method):** `LevelUpOverlay.start(int level)` — when
  `level ∈ {10, 25, 40}` (mirror the constant, or expose it from `AdvancementXpBridge`), swap the
  `unlock_burst` flourish for `eclipse:altar_reveal_burst` at the player position, call
  `EclipseFxState.startShockwave(player.position(), smallStrength, 20)` client-locally, and use a
  longer `HOLD_TICKS` for that entry (make the hold a per-celebration field instead of a constant).
- **Note:** keep the queue-coalescing logic (`M-6`) untouched; a milestone level inside a
  coalesced jump should win the "first + final" pick — the final level already always plays.

### 6. Awards summary epilogue — "you took N" golden footer + exit burst (S)

The summary card lists categories but never totals the local player's night. Add a footer line
on the summary panel — "You claimed N award(s)" in breathing accent gold (reuse
`LevelUpOverlay`'s `lerpColor` sine breath) — and, when N > 0, one client-local `unlock_burst`
at the player as the show fades out.

- **Hooks:** `AwardsOverlay.renderSummary` (footer line; count = `reveals` with `localWon()`),
  and `AwardsOverlay.finishShow()` (spawn burst iff the finished show had a local win and the
  phase reached DONE_FADE naturally — guard so the `SHOW_HARD_CAP_TICKS` failsafe path and ESC
  skip also count, they still end a *watched* show).
- `reducedFx`: footer yes, burst no. Zero new assets.

### 7. Reveal-night collective fireworks — anonymity-safe global cue (S)

When the daily reveal broadcasts, *every* online player gets a small firework burst over their
head simultaneously — the whole server celebrates the awards moment together, and because
everyone gets one, zero information about winners leaks.

- **Hook:** `AwardService.sendRevealNow(server)` — right after
  `PacketDistributor.sendToAllPlayers(payload(resolved))`, loop
  `server.getPlayerList().getPlayers()` and `serverLevel.sendParticles(ParticleTypes.FIREWORK,
  x, y + 2.5, z, ...)` per player (plus a soft `AMETHYST_BLOCK_CHIME` notify).
- **Guard:** only on the fresh broadcast, never on the per-player login replay path
  (`AwardService` line ~81 `hasSeenReveal` branch) — mirrors the client's late-join grace rule.
- Cheap, server-side only, works for vanilla-particle clients and under Iris.

### 8. Advancement unlock in-world echo (S)

Eclipse-namespace advancements currently pay skill XP silently (`AdvancementXpBridge
.onAdvancementEarned`) with only the vanilla toast. Add a small world echo: an END_ROD/purple
spark column over the earning player, visible to nearby players.

- **Hook:** `AdvancementXpBridge.onAdvancementEarned` — after the `xp > 0` grant,
  `player.serverLevel().sendParticles(END_ROD, ...)` above the player and
  `player.playNotifySound(EclipseSounds.UI_UNLOCK_STING.get(), ...)`.
- **Anonymity:** fine — vanilla advancement chat announcements are already public, so a visible
  burst leaks nothing new (unlike award winners). For the `skill_10/25/40` milestone
  advancements granted by `AdvancementXpBridge.onSkillLevelReached`, idea 5's crescendo already
  covers the first-person view; this covers the spectators.

### 9. Sidebar quest "stamp" — completion settle animation on the goal row (M)

Quest completion feedback today is an action bar line + chime (`QuestEngine.feedback`). The
sidebar goal row should visibly *stamp done*: a strike-through sweep across the row, the row text
glitch-settling once (GlitchText scramble → plain), and the checkbox flaring accent for ~20 ticks.

- **Hooks:** client side where `S2CQuestStatePayload` lands in `ClientStateCache` — diff the
  done-set per goal id and record `completedAtTick`; `client/hud/SidebarPanel` (and
  `SidebarExpanded`) read that map during row render and drive the 20-tick sweep with
  `partialTick` easing. No new payloads; M because two render sites + a diff cache.
- **Guard:** seed silently on the first sync of a session (the `LevelUpOverlay.lastSeenLevel < 0`
  login-seed pattern) so joining never replays stamps.

### 10. Shard reward count-up roll (M)

When `ShardEconomy.addShards` lands a quest/award shard reward, the HUD shard readout rolls up
`old → new` over ~15 ticks with `UiSounds` tick blips every few digits and 3–5 accent flicker
rects drifting into the counter — the "cash register" moment.

- **Hooks:** client-side diff of the synced shard balance in `ClientStateCache` (same
  seed-on-first-sync rule); the roll renders wherever the balance is displayed —
  `client/hud/SidebarPanel` and the handbook `tabs/RewardsTab` (locate the draw call for the
  shard count in each and swap the literal for an eased interpolated value).
- M because the display sites are multiple and the interpolation state must pause with the game
  (`Minecraft.isPaused()` — follow the `EclipseFxState.Ticker` client-tick counter pattern).

## Effort key

- **S** — single-file hook, existing payloads/emitters/sounds only.
- **M** — new payload/overlay or multi-site client change; still no new art or shader work.
