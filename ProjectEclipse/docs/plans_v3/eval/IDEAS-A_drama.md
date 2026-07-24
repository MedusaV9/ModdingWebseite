# IDEAS-A — Gameplay Drama & Player Emotion (12 ideas, ranked best-first)

Collector: IDEAS-A (Fable). Scope: small-to-medium hooks into EXISTING systems only — no new
engines, no new dimensions, no new bosses. Priorities: (1) first-hour feel, (2) multiplayer
social moments, (3) tension between big events. Every idea names the exact files/systems to
hook and an effort tag (S/M).

---

## 1. The Last Minute — pre-rollover hush *(S)*

For the final 60 seconds before every realtime day boundary, the client fades all music out
(`MusicCues.stop`), dims the day-timer and sidebar to ~40% alpha, and layers a slow heartbeat
that accelerates over the last 10 seconds; at T-0 the normal day announcement lands into total
silence, so the rollover *hits*. This is entirely client-computable — `S2CDayClockPayload`
already tells the client the boundary instant — so no new packets and no server timing changes.
Recurs 13 times, so it trains dread of every boundary, including the first one in hour one.

- Hook: `client/hud/DayTimerLayer.java` + `client/hud/DayTimerCache.java` (remaining-time is
  already cached), `music/MusicClientHooks.java` (fade), `client/hud/SidebarPanel.java` (dim),
  one heartbeat `.ogg` in `EclipseMusicSounds`.
- Guard: skip while a cutscene lock or `IntroSequence` phase is live.

## 2. First Blood — the world flinches once *(S)*

The very first time any player dies in the event, every online player gets a 0.8s screen shake
(`S2CShakePayload`), one deep bell sound, and a typewriter announcement — "Someone has fallen."
No name (anonymity holds), which is exactly why voice chat erupts: everyone asks "who was it?
what happened?" — the single strongest social moment available in hour one, and it costs one
latch flag plus one broadcast.

- Hook: `lives/LifecycleEvents.java` / `lives/DeathFlowHooks.java` (death entry point),
  `timeline/AnnouncementService.announce`, `network/S2CShakePayload`, one-shot latch via
  `EclipseWorldState.setMilestoneProgress("first_death_done", 1)`.

## 3. "Speak." — the synchronized voice unmute *(S)*

The ten-minute first-Overworld entry mute currently just… ends. Instead, lift it for the whole
join-cohort at the same server tick with a title card ("Speak.") and a soft rising cue — the
first time a dozen anonymous strangers hear each other simultaneously is a guaranteed goosebump
and immediately kicks off introductions, alliances, and confusion (nobody knows who anyone is).
Turns an invisible timer expiry into the emotional end of the intro hour.

- Hook: `voice/VoiceMuteEvents.java` (`entryMuteRemainingMillis` already exists in
  `VoiceMuteApi`) — batch expiries within a ~30s window to one instant;
  `timeline/AnnouncementService`, `music/MusicCues.play` per-player overload.

## 4. Witnessed loss — heart-shatter ripple *(S)*

When a player loses a permanent heart, the owner already gets the HUD shatter
(`S2CHeartBurstPayload`); additionally send every player within 16 blocks a half-second red
vignette pulse and the muffled shatter sound. Bystanders physically *feel* a teammate's
permanent loss without any text, which reliably produces the "oh no, are you okay?!" voice
moment and makes escorting low-heart players an instinct rather than a rule.

- Hook: the `LivesApi.add(-1)` call sites in `lives/LifecycleEvents.java`; reuse
  `S2CShakePayload(strength, ticks, marked=true)` → `client/hud/MarkVignetteOverlay.java`
  already renders a marked vignette, so no new payload is needed.

## 5. Ember of the last heart — visible fragility *(S)*

Players at exactly 1 heart passively emit a faint drifting ember/wisp trail (existing Quasar
emitter, server-triggered, ~1 particle/sec — well inside `FxBudget`). No announcement, no HUD:
other players just *notice* someone burning low, and because names are hidden, protecting "the
ember" becomes a wordless social ritual; it also paints boss fights and Pale Nights with
walking stakes.

- Hook: `hearts/HeartsService.apply` (knows the heart count at every change),
  `veilfx/QuasarSpawner` + `network/S2CQuasarPayload` (both exist), throttle in a small tick
  check on the server player list.

## 6. The Wrongness — night-event dread tell *(M)*

Thirty seconds before a Pale/Umbral Night activates, play a "tell" instead of announcing:
the sun-halo flickers twice (`SunTracker` drives the halo), ambient mob sounds cut out, and one
distant horn plays from a random compass direction. Veterans learn to read the sky and warn the
group ("get inside, NOW") — converting a spawner state flip into recurring anticipation between
the big scripted events, which is exactly the day-4→day-12 tension gap.

- Hook: `entity/EclipseSpawner.java` (add a pre-warn stage before
  `announceNightEvent`), `veilfx/SunTracker.java` + `veilfx/VeilPostController.java` (halo
  flicker), `music/MusicCues` for the horn; state stamp via existing
  `EclipseWorldState.setActiveNightEvent` day-stamp fields.

## 7. Faces at the end — the finale unmasking *(M)*

At the day-14 Ferryman victory, `ritual/FinaleRitual` already mass-revives everyone; add one
broadcast flag that suspends the anonymity visuals — real skins return, name tags render, tab
list unhides — as the victory theme plays. Fourteen days of facelessness resolving into "wait,
THAT was you?!" is the single biggest emotional payoff the event can buy, and every blocker is
already a client-side toggle with a single enforcement point.

- Hook: `ritual/FinaleRitual.java` (send flag), `client/NameTagHider.java`,
  `client/TabListHider.java`, the uniform-skin mixin under `client/mixin/` (all gate on one
  new boolean in `client/ClientStateCache.java`), `music/MusicCues.play("victory_theme")`.
  Server keeps chat/sign blocks on; this is visuals-only.

## 8. Counted, not named — offering pressure *(S)*

When `OfferingService.resolveDay` runs, broadcast only the tally — "4 of 12 made an offering
today." — and light one candle/flame column per offering at the altar via the existing beam
emitter. Nobody knows *who* abstained, so the number becomes nightly social theater
(accusations, confessions, guilt-tripping in voice), and the altar visually keeps score of the
group's devotion between boss days.

- Hook: `offering/OfferingService.resolveDay` (count is already computed),
  `timeline/AnnouncementService.announce`, `ritual/BeamEmitter.java` /
  `ritual/AltarBlockEntity.java` for the candle dressing.

## 9. First footprint — the expansion race *(S/M)*

After an `ExpansionSequence` completes, the first player to physically cross into the new ring
triggers an anonymous global line — "Someone has set foot in the new lands." — plus a small
growth-shimmer burst at their position (reuse `S2CGrowthWavePayload`). It converts the minutes
*after* each map expansion (currently a lull) into a sprint, and the anonymity makes the race
result deliciously arguable in voice chat.

- Hook: `sequence/ExpansionSequence.java` (arm a one-shot on completion), ring-radius check
  against `EclipseWorldState.getWorldStage`/`ContainmentService` boundary math in
  `progression/`, `network/growth/` payloads, latch via `setMilestoneProgress("first_step_<stage>", 1)`.

## 10. It sees you — The Other's private glance *(S/M)*

When `TheOtherEntity` first acquires a player as its stare target, that player — and only that
player — gets a 0.5s desaturation flash (existing ghost/limbo grade in `VeilPostController`)
and a whisper sound; no text, no announcement. Private, deniable horror is the best kind for
an anonymous voice server: "did ANYONE else just see that?" spreads the fear socially without
the mod saying a word.

- Hook: `entity/TheOtherEntity.java` (target-acquired transition), a per-player send of the
  existing grade one-shot via `veilfx/VeilPostController` + `client/GhostGradeFx.java`,
  whisper in `music/EclipseMusicSounds`.

## 11. Breath of the storm — approach heartbeat, exit exhale *(S/M)*

Fog storms already have interior FX (`StormInteriorFx`) and wall rendering; add a client-side
proximity ramp — within ~12 blocks of a wall, low-pass the ambience and fade in a heartbeat that
peaks at the boundary — and on *leaving* a storm play a single exhale plus a half-second color
rebound. Entering the Tyrant's weather becomes a decision your body objects to, and surviving
it gets a visceral "you made it" beat that needs zero new server logic.

- Hook: `stormfx/StormFxClient.java` (client already knows storm center/radius via
  `S2CFogStormPayload`), `stormfx/StormInteriorFx.java`, `veilfx/VeilPostController` rebound,
  sounds in `EclipseMusicSounds`.

## 12. Struck while you slept — logout-ghost gossip *(S)*

`LogoutGhostService.onGhostHurt` already knows when someone's sleeping body is attacked; queue
a private note delivered on the owner's next login — "Your ghost was struck while you were
away." (and, if it died, by-a-player vs by-the-world flavor). It makes offline hours emotionally
sticky, seeds paranoia and revenge arcs between the big events, and pairs perfectly with
anonymity: you know *someone* did it, never who.

- Hook: `ghosts/LogoutGhostService.onGhostHurt` (attacker is passed in), persistence via a
  small key on `EclipseWorldState.setMilestoneProgress("ghost_hurt_<uuid>", …)` or a
  `GhostsState` field, delivery on login next to `AwardService.deliverPending` in the existing
  login flow.

---

### Ranking rationale (one line)

1–3 own the first hour (rollover dread, first death, first voices); 4–5 make loss communal and
visible; 6, 9, 11–12 fill the tension gaps between scripted set pieces; 7–8, 10 spend the
anonymity system for its emotional payoff — the cheapest drama this mod owns.
