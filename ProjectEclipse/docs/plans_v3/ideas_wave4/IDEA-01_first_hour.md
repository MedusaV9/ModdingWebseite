# IDEA-01 — First-Hour Satisfaction & Onboarding Feel (Wave 4, Collector 1/20)

Scope: what a brand-new player experiences from the title screen, through the limbo ghost-ship
wait, through the `/start_event` intro cinematic, into their first overworld day. All ideas are
small/medium polish on EXISTING hooks — no new systems. Ranked by expected wonder/clarity/dopamine
per unit of effort.

Code surveyed: `client/menu/` (EclipseTitleScreen, GlitchErrorTheater, JourneyController,
TitleScreenSwap), `limbo/` (LimboGate, StartEventCutscene, GhostShipBuilder, LimboSeascape,
ShipLanterns, door/), `sequence/` (IntroSequence, SequencePayloads, IntroLightningPhase),
`entity/DeckhandEntity`, `progression/ContainmentService`, `client/handbook/` (HandbookScreen,
InventorySlotDecor, UiSounds), `assets/eclipse/cutscenes/intro_v3_*.json`, `lang/en_us.json`.

---

## 1. APPROACH stall re-nudge (S)

The only instruction to leave the disc and walk into the storm is one subtitle at t=0.97 of
`intro_v3_flight.json` (`eclipse.caption.intro.approach`, ~6.5 s on screen). The APPROACH phase is
untimed by design — if the group hesitates, tabs out, or simply doesn't grok "walk toward the
scary smoke wall", the whole intro stalls silently forever. Add a gentle re-whisper: in the
`case APPROACH` branch of `IntroSequence.onServerTick`, if no player has tripped
`firstPlayerNearVortex` after ~1200 ticks, re-send `CAPTION_APPROACH` as `STYLE_WHISPER` plus a
distant `minecraft:entity.lightning_bolt.thunder` at the vortex center, repeating every minute.

- Hooks: `sequence/IntroSequence.java` (APPROACH tick case, existing `CAPTION_APPROACH` constant,
  `S2CCaptionPayload`), lang keys already shipped.

## 2. Limbo arrival veil — first ten seconds (S)

`LimboGate.gate()` hard-snaps a fresh login onto the ghost ship with a bare `teleportTo` — no
transition at all — while the late-joiner path (`StartEventCutscene.gatherLateJoiner`) already
wraps its hop in the R13 portal glitch (`SequencePayloads.sendPortalEnter/Exit`). Reuse exactly
that pair (enter 4 t, exit 24 t) around the gate teleport, and follow with a one-shot WHISPER
caption (new key, e.g. `eclipse.caption.limbo.arrive` — "The oars never stop.") so the very first
frame of the event is a directed reveal of the ship instead of a teleport pop.

- Hooks: `limbo/LimboGate.java` (gate), `sequence/SequencePayloads.java` (reuse),
  `network/fx/S2CCaptionPayload`, `lang/en_us.json` + `de_de.json` (1 new key).

## 3. Post-sunrise Logbook handoff hint (S)

After `IntroSequence.beginSunrise` flashes "IT BEGINS", the cinematic ends and the player is
simply… standing there. The artifact is pinned in slot 17 and the J keybind opens the handbook,
but nothing in hour one ever says so. Schedule (via the existing `schedule()` helper) a one-time
SUBTITLE caption ~300 ticks after `finish()` — "The Logbook stirs — it remembers everything"
plus the actual bound key name rendered client-side (the caption/lang can use `%s` filled from
`EclipseKeyMappings` on the client, same pattern as `gui.eclipse.handbook.hint`).

- Hooks: `sequence/IntroSequence.java` (`finish()` + `schedule()`), `client/EclipseKeyMappings`,
  lang (1 new key). Guard with the existing `IntroData.isCompleted()` so it fires once per world.

## 4. Deckhands skip a stroke (M)

The bestiary sells the crew hard — "They never look up — pray they never do." — but during the
limbo wait the rowers are pure wallpaper. Once per player per limbo visit: if a player stands
within ~3 blocks of a rowing deckhand for 10+ seconds, that one deckhand freezes mid-stroke for
~20 ticks (hold the `row` frame — no head turn, honoring the lore) with a single quiet wood-creak
sound, then resumes. A tiny synced flag on the existing GeckoLib `base` controller state machine
(`handleBaseState`) is enough; no new model or anim file strictly required (frame-hold).

- Hooks: `entity/DeckhandEntity.java` (tick proximity check + one synced accessor,
  `handleBaseState`), optional short `hesitate` clip in `geo`/animations later.

## 5. Containment bounce — variant lines + pitch ramp (S)

The day-1 void bounce is the first repeatable dopamine toy ("trampoline"), but it always prints
the identical actionbar line (`message.eclipse.containment.bounce`) with the identical
amethyst chime. Add 2–3 flavor variants (`.bounce.2`, `.bounce.3` — escalating "the void is
getting annoyed" tone) cycled per consecutive bounce, and raise the chime pitch slightly per
bounce within the immunity window (the `BOUNCED_UNTIL_TICK` map already tracks recency).

- Hooks: `progression/ContainmentService.java` (`applyBounce`), lang (2 new keys per locale).

## 6. Persist the armed title countdown across restarts (S)

On the title screen, the DIM countdown line under "Reise beginnen" only appears after the player
clicks through the glitch-error theater once (`countdownArmed`), and the flag "survives
resize/rebuild by design" — but not a game restart. A player who saw the theater yesterday gets
a bare button again and no countdown until they re-click. Persist one boolean next to
`opGranted` in `config/eclipse-journey-state.json` (`JourneyController` already owns
read/write), and initialize `countdownArmed` from it in `EclipseTitleScreen.init()`. The theater
still plays on click; the anticipation line just never disappears again.

- Hooks: `client/menu/JourneyController.java` (state file), `client/menu/EclipseTitleScreen.java`
  (init + theater end callback).

## 7. Void rescue speaks the containment language (S)

During APPROACH/LIGHTNING, `IntroSequence.rescueVoidFallers` silently teleports fusion-gap
fallers back up with portal particles — while every other under-disc moment in hour one says
"The void beneath the disc rejects you" with the amethyst chime (`ContainmentService`). Reuse the
same actionbar line + `AMETHYST_CLUSTER_BREAK` sound (or just call a small shared snippet) in the
rescue, so the world's "the void rejects you" grammar is consistent the very first time a new
player meets it — mid-cinematic confusion ("did I just get teleported? bug?") becomes lore.

- Hooks: `sequence/IntroSequence.java` (`rescueVoidFallers`), reuse
  `message.eclipse.containment.bounce` (no new lang).

## 8. Mid-intro joiners get the drone and the title (S)

`IntroSequence.onLoggedIn` re-syncs the eclipse phase and freeze for players who (re)connect
during the cinematic, but not the `EVENT_ECLIPSE_DRONE` sound or the "THE ECLIPSE RISES" title —
they materialize under a silent black sun with no framing. In the live-run branch, when the phase
is ECLIPSE_ON/FLIGHT, replay `CAPTION_AWAKEN` (TITLE style) and the drone `playNotifySound` to
that one player; cheap, and a disconnect during the opening no longer costs the goosebumps beat.

- Hooks: `sequence/IntroSequence.java` (`onLoggedIn`, live-run branch), existing constants only.

## 9. Artifact slot pulse until the first Logbook open (S)

`InventorySlotDecor` draws a deliberately static accent frame + padlock on slot 17. New players
open their inventory on day 1, see a mystery item they cannot move, and get no signal that it is
THE interface. Until the handbook has been opened once (client-persisted flag — same tiny-JSON
pattern as `JourneyController`'s state file, or an `EclipseClientConfig` value), let the frame
breathe: a slow 2 s alpha pulse of the existing `ACCENT_DEEP` ring, `reducedFx`-gated back to
static. One conditional and a `Mth.sin` in `draw()`.

- Hooks: `client/handbook/InventorySlotDecor.java`, `client/handbook/HandbookScreen.java`
  (set flag in the `!shownOnce` branch), `core/config/EclipseClientConfig` or a state file.

## 10. Title screen hum (M)

`EclipseTitleScreen` is gorgeous (panorama, wisps, parallax, flare) and completely silent — no
music hooks exist in `client/menu/` at all. Loop the already-registered limbo ambience
(`EclipseMusicSounds.LIMBO_AMBIENCE`, subtitle "Limbo hums") at low volume as a
`SimpleSoundInstance` started in `init()` and stopped in `removed()`/on-connect, gated behind the
existing `uiSounds`/`reducedFx` client config. The mood of the ghost sea starts before the first
click, and the submerge cutscene's audio no longer arrives cold.

- Hooks: `client/menu/EclipseTitleScreen.java` (init/removed), `music/EclipseMusicSounds.java`
  (reuse), `client/handbook/UiSounds.java` (volume/gate conventions).

---

### Non-goals / rejected

- Respawn-door foreshadowing: already covered — `RespawnDoorBlock.handleUse` plays a locked
  shudder anim + "Barred from beyond" line pre-flow.
- Anything touching the frozen R10 intro tick table, ship fight contracts (§1.3), or new
  handbook tabs — out of scope for polish-sized work.
