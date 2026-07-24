# IDEAS — Backrooms Event Dimension + Final Credits Sequence (collector, Eclipse Event)

Two creative briefs enriched with concrete designs. Idea-collector document only — no code
was changed. Grounded in a full read of:
`xboxevent/XboxEventService` + `XboxPortal` + `XboxEventState`/`XboxDimensions`/`XboxWorldsManifest`,
`minigames/MinigameDimensions` (void-dim + open-time generation pattern),
`worldgen/DiscMapData` (`ECLIPSE_SEED`, deterministic-hash law) + `structure/StructureStamper`,
`entity/glitch/GlitchedHuskEntity`/`GlitchedMonster`, `entity/TheOtherEntity` (+ `MimicWalkGoal`),
`cutscene/CutsceneService`/`FreezeService`/`client/CaptionRenderer`/`client/CameraDirector`,
`veilfx/TransitionFx`, `client/loading/PortalTransitionController`, `client/hud/BossIntroOverlay`,
`sequence/IntroSequence`/`IntroLightningPhase`/`FloatingDecor`, `devtools/display/DisplayPlacerService`,
`music/MusicManager`/`MusicCues`/`EclipseMusicSounds`, `ritual/FinaleRitual`,
`core/config/EclipseClientConfig` (`reducedFx`), `registry/EclipseSounds` (alias suite).

House rules every design respects:
- **Deterministic worldgen**: seed-hashed from `DiscMapData.ECLIPSE_SEED`-derived constants,
  never the vanilla world seed; idempotent set-block loops (the `GhostShipBuilder` law).
- **Event lifecycle**: mirror the xbox state machine (`IDLE → ANNOUNCED → OPEN → CLOSING → IDLE`,
  persisted SavedData, crash resume, protected deaths, lockout modes, `TimedBuffApi` reward).
- **Client FX**: `reducedFx` caps everything; Veil pipelines self-disable under Iris, so every
  beat needs the GUI-side fallback (the `PortalTransitionController` doctrine, §7 risk 1).
- **Restart mid-sequence skips to the end state** (IntroSequence pattern) — never resume a
  half-played cinematic.
- **Lang**: all new strings ship en_us+de_de via `docs/plans_v3/langdrop/<PKG>.json`.

---

# A) BACKROOMS EVENT DIMENSION (`eclipse:backrooms`)

User brief: yellow maze, horror mobs, a possible mini-jumpscare, portal entry like the
xbox event.

## A1. Maze generation — deterministic pipeline

**Dimension**: new `eclipse:backrooms` following the `MinigameDimensions` pattern (datapack
JSON `data/eclipse/dimension/backrooms.json`, void flat generator, one static key class
`BackroomsDimension`). Dim type: `has_skylight: false`, `fixed_time: 18000` (midnight —
CRITICAL: keeps `level.isDay()` false so `TheOtherEntity.despawnAtDawn()` never fires and
the cameo works with ZERO entity changes), `min_y: 0`, `height: 32`, ambient_light 0
(all light comes from the froglight panels — flicker reads).

**Finite stamped maze, not a chunk generator** (recommendation): at event `start()` the
maze is stamped into the void dim (StructureStamper-style idempotent set-block pass),
mirroring how `ArenaGame`/`ElytraRace` build courses at open time and how xbox worlds are
per-instance installed/reset (`XboxWorldInstaller.stageReset`). Size: **24×24 cells of
8×8 blocks = 192×192**, floor y=8, interior height 3 (rare double-height halls to 6).
~40 s stamp worst-case; run it at `ANNOUNCED` so `OPEN` flips only when the stamp is done.
An infinite `BackroomsChunkGenerator` is the stretch variant (same cell math per chunk:
16×16 = 2×2 cells), only worth it if ops want >30 min sessions.

**Seed-hashed layout**: `mazeSeed = DiscMapData.ECLIPSE_SEED ^ 0xBAC2C0035EEDL ^ instanceId.hashCode()`
— per-instance layout that is *reproducible within the instance*: a crash-restart re-stamp
(instanceId persists in the event SavedData) rebuilds the identical maze, so players
relogging mid-event recognize where they were.

**Cell algorithm** (no global solver, O(1) per cell, works for finite AND infinite):
1. Every shared edge between two adjacent cells opens iff
   `hash(mazeSeed, min(cellA,cellB), max(cellA,cellB)) % 100 < 58`. Bond percolation on the
   square lattice has threshold 0.5 — at 0.58 the connected cluster spans the map, while
   sealed pockets still occur (deliberate dread: rooms with no exit you can *see into*
   through 1-block gaps).
2. **Highways guarantee reachability**: every 8th cell row/column carves a straight
   corridor end to end (hash-jittered ±1 cell so they don't read as a grid). Spawn cell
   (center) and exit cell sit on highways by construction.
3. Per-cell prefab pick, hashed: `CORRIDOR` 40%, `OFFICE` (open, 2 pillar stubs) 25%,
   `PILLAR_HALL` (double height) 12%, `WET_ROOM` (sponge floor, drips) 12%,
   `DEAD_END_CLOSET` 8%, `LOOT_ALCOVE` (barrel cache) 3%.

**Mono-yellow palette** (answering "which vanilla blocks read as backrooms?"):

| Surface | Block | Why |
|---|---|---|
| Walls, lower course | `yellow_terracotta` | THE backrooms mustard — muted, matte |
| Walls, upper 2 courses | `stripped_bamboo_block` | pale yellow + vertical grain = wallpaper |
| Floor | `sponge` | mottled damp-carpet read (better than wool) |
| Floor accent (highways) | `yellow_carpet` on sponge | worn walking path |
| Ceiling | `smooth_sandstone` | office-tile beige |
| Light strips | `ochre_froglight` (2×1 every 4 blocks) | the ONLY vanilla warm-white light-15 panel block — fluorescent strip, perfect |
| Dead panels | `yellow_stained_glass` | unlit froglight lookalike (also the flicker swap target) |
| Skirting/trim | `cut_sandstone_slab` | baseboard shadowline |

Avoid `yellow_wool` (too saturated, reads "wool") and `yellow_concrete` except as rare
hazard-stripe accents in WET_ROOMs.

## A2. Ambience — buzz + flicker

- **Buzz loop via alias pitching**: new alias sound event `ambient.backrooms_buzz`
  (the W4-ATMOS self-healing alias pattern in `EclipseSounds`) whose `sounds.json` entry
  initially points at the shipped `event.beam_hum` ogg. Client loop `BackroomsBuzz`
  (`SanctumHum`/`BorderStaticSound` `AbstractTickableSoundInstance` pattern): follows the
  nearest froglight panel, base pitch **0.55** (drops the hum an octave-ish into mains-buzz
  territory), volume by panel distance. When the nearest panel is mid-flicker the pitch
  dips to 0.4 for 10t — the buzz "browns out" with the light.
- **Flicker via light-block swaps, not block displays**: display entities emit no light, so
  they cannot flicker actual lighting; they're only good for the *hanging half-dead panel*
  prop. Server-side: 6% of panels are hashed "faulty" (`hash(mazeSeed, panelPos)`); a
  per-panel schedule (off 2–6t, on 20–90t, hashed) swaps `ochre_froglight ↔
  yellow_stained_glass` with `setBlock` flag 3. Only panels within 32 blocks of a player
  tick (the `XboxPortal.ambientTick` proximity discipline) — relights stay localized and
  cheap. `reducedFx` note: flicker is world-side (photosensitivity-safe cadence: a faulty
  panel never cycles faster than 3 Hz, and no two adjacent panels are both faulty by
  hash-rejection).

## A3. Horror mobs — two reuses, zero new AI frameworks

1. **"Wanderer"** — glitched-husk variant. Cheapest correct form: a second registered
   entity type reusing `GlitchedHuskEntity`'s class with `geoId()` → `"glitched_wanderer"`
   (GeckoLib triple = same geo/anim, ONE new texture: mono-yellow suit, features smeared
   like wet paint). It already ships the two perfect backrooms behaviors:
   - **unseen burst** (enderman-style gaze test → +0.5 speed while you look away, portal
     static tell) — the "it's closer every time you turn around" mechanic, free;
   - **glitch blink** stutter-teleport on the 200–280t husk cadence.
   Stalking tune for backrooms: `FOLLOW_RANGE` 48 (long corridors), MeleeAttack only within
   3 blocks (a `TheOtherEntity.ATTACK_TRIGGER_RANGE`-style predicate on the target selector)
   — otherwise it *paces you at exactly corridor-walking speed and keeps 12 blocks*
   (a `MimicWalkGoal` clone with STARE_RANGE=12). Ambient voice: `ZOMBIE_AMBIENT` through the
   existing unstable `getVoicePitch()` (0.6–1.4 random) — corrupted playback, already in.
   Spawn: `EclipseSpawner` event pattern — 1 per ~40×40 blocks, cap 6, ≥24 blocks from
   players, never in the spawn cell's highway cross.
2. **The Other cameo** — spawn 1–2 literal `TheOtherEntity` ≥64 blocks from the spawn cell.
   Zero code: `fixed_time 18000` disarms the dawn-despawn, and its existing
   walk-toward-you-then-STOP-AT-5-BLOCKS-AND-STARE goal plus the 180°-in-2t head snap *is*
   a backrooms encounter. Players who've met it on Pale Nights get the "why is a teammate
   down here" gut-drop; it still only fights if crowded (≤3 blocks) or hit.

## A4. THE jumpscare — trigger + presentation (photosensitivity-capped)

**Trigger rules (server-side, `BackroomsScare` on the event tick):**
- Armed only while OPEN, per player, **once per instance** (a `scaredPlayers` UUID set in
  the event SavedData, `markRewardGranted()`-style — persists across relogs so nobody gets
  double-scared).
- Conditions, checked every 10t: player inside >90 s; a Wanderer within 7 blocks in the
  player's rear 180° arc (dot(lookVec, toMob) < 0); mob currently *unseen* (reuse the
  husk's `isLookedAtBy` test — proximity + lookaway exactly as briefed); random gate
  1/30 per check (expected ~5 min of exposure). Global 60 s cooldown so a group never
  chain-scares (one scream at a time reads scarier anyway).
- After firing: the Wanderer immediately consumes its glitch-blink (teleports 10–14 blocks
  away). No damage. The scare is the attack.

**Presentation (client, `S2CJumpscarePayload` → new `JumpscareOverlay`):**
- **Single envelope, no strobe**: face texture (see assets) at 70% screen height, centered,
  2t in → 8t hold → 6t out = **16t ≈ 0.8 s total**, one event, alpha capped at 0.85.
  Layered under `CaptionRenderer`'s layer, over the letterbox (register via
  `EclipseGuiLayers` like the caption layer).
- Sound: `ui.error`-family glitch burst + `WARDEN_SONIC_CHARGE` at 0.9F/0.7F pitch
  (the `TheOtherEntity.die()` palette, recognizably "the entity family").
- One `CameraDirector.addShakeImpulse()` (the existing W4 ~2 s impulse; no new shake code).
- **`reducedFx` / photosensitivity cap**: NO fullscreen face — replaced by a 25%-alpha
  dark vignette pulse + the sound at 0.5 volume, **no shake impulse** (the config comment
  already promises "screen shake, pulsing overlays" are reduced). Both variants: no
  repeated flashing, single fade envelope, < 1 s — comfortably inside 3-flashes/sec rules.

## A5. Loot/reward + exit rules (mirror of the xbox event)

- **Lifecycle**: clone the `XboxEventService` skeleton — persisted phase state machine,
  `/dev backrooms start|stop|time|portal here` (register through `DevReloadRegistry`),
  default 30:00 window, T-5/T-1 warnings, bossbar fallback + overlay-ack, 20 s timer
  resync, crash resume on boot.
- **Portal entry "like the xbox event"**: `XboxPortal` pattern verbatim — one
  `minecraft:interaction` 3×4 trigger + block-display frame, but the frame is
  `stripped_bamboo_block` + `ochre_froglight` corners (yellow tear). Entry sends the
  `S2CPortalFxPayload` with a new styleId `"backrooms"` — `PortalTransitionController`'s
  hold tints pale yellow and the loading screen line reads "no-clipping…" (lang key gag).
  Same rift open/close FX payloads (`a`=5.0, `b`=1).
- **Protected deaths**: identical `LivingDeathEvent` HIGHEST-priority cancel → exit to the
  return anchor; the exit line reads "you no-clipped back out" (death costs nothing, like
  xbox — the horror dimension must be safe to be scary).
- **Voluntary exit**: `/backroomsleave` with the 15 s click-confirm + per-instance lockout
  modes, verbatim `XboxLeaveCommand` pattern.
- **Loot**: LOOT_ALCOVE barrels use the `ClassicChestLoot`-style provider with
  `consumeChestPosition` one-shot semantics per instance. Table: **Almond Water**
  (re-skinned potion item: instant darkness/blindness clear + 30 s Regen I — the community
  in-joke and a genuinely useful mid-event heal), 1–2 `glitch_shard` (existing drop
  economy), rare `yellow wallpaper` trophy block (1 per instance).
- **Exit rules**: at T-5:00 the warning doubles as a diegetic beat — "an EXIT sign hums to
  life somewhere" and an exit portal spawns in a hashed far cell (≥100 blocks from spawn
  cell, on a highway). Walking out through it (vs `/backroomsleave` or timeout) upgrades
  your share of the participation reward. On CLOSING: everyone exits to anchors with full
  inventory, `TimedBuffApi.Holder.get().start(...)` participation buff, portal despawns,
  maze region reset staged — the full xbox closing choreography.

## A6. Eight quick ambience details, ranked

1. **Faulty-panel flicker + buzz brown-out** (A2) — the signature; sells the whole place.
2. **The hum ceases**: all buzz fades over 20t whenever a Wanderer is ≤16 blocks and
   unseen — silence as the tell, mirroring the unseen-burst. Players learn to fear quiet.
3. **Distant ballast clunk**: every 60–120 s a far-attenuated `event.beam_hum` one-shot at
   pitch 0.3, quiet, positioned 20–30 blocks down a random open corridor (audio lure).
4. **WET_ROOM drips**: `DRIPPING_WATER` particles from hashed ceiling spots + vanilla drip
   sounds; sponge floor squish = slowness 5% walk-speed aura inside the cell (barely felt,
   subconsciously wrong).
5. **WHISPER captions**: rare (1/instance/player) `CaptionRenderer` WHISPER-style line
   ("es hat dich gesehen" / "it noticed you") — the style with the ±0.5 px jitter exists.
6. **The office chair**: 1/200 cells gets a lone block-display prop cluster (dark oak
   stairs + trapdoor "chair", slightly rotated off-grid via `DisplayPlacerService`
   transforms) — off-grid rotation is what makes it uncanny.
7. **Wall stains**: hashed 3% wall blocks swap to `yellow_concrete_powder` (damp) —
   breaks texture tiling so corridors stop reading as copy-paste.
8. **Exit-sign glow**: after T-5:00, corridor junctions within 24 blocks of the exit cell
   get a redstone-lamp + red-stained-glass block-display "EXIT" smear — navigable dread.

---

# B) FINAL CREDITS SEQUENCE (day-14 post-Ferryman)

User's exact vision honored beat for beat. New server phase machine `CreditsSequence`
(IntroSequence skeleton: persisted phase SavedData, `SequenceReplayable` id `"credits"`,
per-beat FX replay via `/eclipsefx sequence credits <BEAT>`). Trigger: in
`FinaleRitual.tickVictory`, when the revive queue drains, call `CreditsSequence.start()`
*instead of* `bringEveryoneHome()` (config flag `creditsEnabled` falls back to the current
`finale_return` behavior).

## B1. Shot list with tick timings + systems per beat

`t` = ticks since `CreditsSequence.start()` (players are in limbo, Ferryman dead,
`victory_theme` playing).

| t | Beat | Systems used |
|---|---|---|
| 0–40 | **FADE BLACK** | `S2CScreenFadePayload(10, ∞hold, black)` via `FxPayloads` → `CaptionRenderer.fade`; `MusicCues.stop(player)` fades `victory_theme` out (2 s crossfade is built into `MusicManager`) |
| 40 | (behind black) all players teleported to ghost-ship stern; the **egg-offerer** (ritual starter UUID, recorded by `FinaleRitual`; fallback first online player) posed AT the wheel, yaw locked | `FreezeService.freeze` (survives-dimension-change flag), `GhostShipBuilder.waterlineY` for deck coords |
| 40–200 | **HELM SHOT** — new cutscene path `credits_helm` (world-anchored limbo, 140t): slow 12-block push-in from stern-high down to the wheel, ending framed on hands-on-wheel; path `fade` event opens from black over 20t | `CutsceneService.play` (LOCAL — everyone is already there), path JSON in the synced library |
| 200–230 | **FADE WHITE** — 30t rise to `0xFFFFFFFF`, held | `CaptionRenderer.fade` (any-ARGB is already supported) |
| 230 | **DISGUISED WHITE LOADING SCREEN** — `S2CPortalFxPayload` new styleId `"credits_white"`: `PortalTransitionController` holds WHITE instead of black and `EclipseLoadingScreen` renders a plain-white variant with a fake vanilla progress line ("Building terrain…" lang key) — the gag is that it looks like a real load. Server teleports everyone limbo → `eclipse:epilogue` behind the hold | `XboxTransitionBridge` pattern; controller's self-release on level-received already handles variable chunk-load time |
| ~290 | **BEACH/SUNRISE** — fade-in from white 40t onto a stamped beach: new one-shot void dim `eclipse:epilogue` (MinigameDimensions pattern), StructureStamper beach strip ~96×24 (sand, scattered `suspicious_sand` nothing-burgers, water plane east), `fixed_time: 23200` = frozen sunrise; players face east into the sun. **Music cue `credits_finale` starts** (`MusicPayloads.sendPlay`). **Credits panel scroll starts** (B4) | dim JSON + stamp at sequence start (not at t=230 — pre-stamp during FADE BLACK so chunks are warm) |
| 290–590 | **AUTO-RUN into sunrise** — all players run forward east (mechanic in B2); barrier-block side rails keep the line | client input injection + server nudge watchdog |
| 410–470 | **MASSIVE LIGHTNING + BLOCK DISPLAYS FLYING** — 6 strikes over 60t, intensity 0.6→1.0, offshore in front of the runners: `fx/lightning_strike` events + visual-only `LightningBolt`s (`IntroLightningPhase` per-strike recipe, kickback OFF); simultaneously 20–30 block displays (ship planks, altar stone, disc-basalt chunks — the run's greatest hits) launch from behind the players on ballistic display-interpolation arcs overhead toward the sun | `IntroLightningPhase` FX-replay path, `FloatingDecor`/`DisplayPlacerService` transform+interpolation pattern |
| 470–640 | **TITLE CARD** — "MINECRAFT ECLIPSE COMES BACK IN AVENGERS: DOOMSDAY" decodes in glitch-noise, 2t/char (≈54 chars ≈ 108t) + 70t hold | reuse `S2CBossIntroPayload` verbatim (`BossIntroOverlay` = the BossIntro-style card the brief asks for: GlitchText decode, scrim band, hairlines); nameKey `eclipse.credits.title.doomsday`, empty subtitle |
| 640–655 | **BURST FX** — `fx/shockwave (1.0, 50)` + white flash (fade white 8t in / 6 hold / 10 out) — the intro-BURST mirror | `FxPayloads` + `CaptionRenderer.fade` |
| 655–735 | **CORRECTION CARD** — small, deadpan: `CaptionRenderer` TITLE caption `eclipse.credits.title.correction` = "ECLIPSE : DOOMSDAY" (80t; the letter-spaced track-in style sells "legal-department correction") | `S2CCaptionPayload` TITLE style |
| 735–795 | **FADE BLACK** — 60t rise, held to the end | `CaptionRenderer.fade` |
| 795–1095 | **MUSIC FINALE over black** (~15 s): `credits_finale` plays its written outro; credits panel finishes its scroll; single TITLE caption "ECLIPSE" at t=1000 | music cue keeps running (non-looping, `durationTicks` covers it) |
| 1055 | **CLOSE BROADCAST** — `S2CCreditsClosePayload(delayTicks=40, nonce)` to all | new payload in `EclipsePayloads` |
| 1095 | **CLIENT CLOSES ITSELF** (B3) | client-side `Minecraft.getInstance().stop()` |
| 1195 | Server `halt(false)` — stragglers/vanilla clients get a normal "server closed" screen 5 s later | server thread |

## B2. Auto-run mechanic — client input injection, server nudge fallback

**Recommendation: client-side forced walk input, NOT server velocity.** The mod is
MANDATORY on clients (anonymity/anti-cheat already depend on it — AGENTS.md), so client
cooperation is guaranteed. `CutsceneInput` already owns input swallowing during cutscenes;
extend it with an `autoRun` mode (set by a flag on the credits payload): forces the
forward impulse (`input.up`) + sprint OFF (walk reads more cinematic), locks yaw to 90°E
with free ±20° look-around. This yields REAL walk animation, head bob, footstep audio and
FOV — everything `setDeltaMovement` gliding lacks (server-pushed velocity has no walk
anim and rubber-bands against client prediction; `FreezeService` is the opposite tool —
it pins players).
**Server safety net**: a per-tick watchdog nudges (0.15 blocks/t `teleportTo` east) any
player whose x hasn't advanced in 20t (crashed/vanilla client, AFK) so the wide shot
never shows a straggler statue. Beach floor is stamped flat; barrier rails prevent
drift into the water.

## B3. Client-close mechanic — `Minecraft.getInstance().stop()`

- **Payload**: `S2CCreditsClosePayload(delayTicks, nonce)` — nonce = the credits instance
  id the client received at sequence start; a client that missed the sequence (logged in
  late, different server) ignores it.
- **Timing**: broadcast at music-end minus 40t; client counts down, then
  `Minecraft.getInstance().execute(minecraft::stop)` — `stop()` is the graceful quit path
  (same as the title-screen Quit button: saves options, stops sounds, destroys the window).
  Executing via `execute()` guarantees render-thread safety.
- **Guards (all client-side)**: never when `minecraft.hasSingleplayerServer()`
  (singleplayer/LAN dev), never when the nonce mismatches, and a client config
  `allowFinaleClose` (default **true** — this is an event pack; ops flip it for rehearsals).
- **Server side**: `server.halt(false)` 100t after the broadcast — modded clients are
  already gone; vanilla/late clients get the normal disconnect screen. Order matters:
  clients close FIRST so the intended experience is "the game quietly closed itself",
  not "connection lost".

## B4. Credits text scroll — right-side panel (per user)

New client overlay `CreditsPanel` (registered like `CaptionRenderer`'s layer, letterbox-
whitelisted): right third of the screen (x from 68%→96%), lines scroll bottom→top at
~0.35 px/tick over the whole beach+black span (~800t), 0.9 scale, `EclipseUiTheme.TEXT`
with DIM section headers, soft 110-alpha left-edge gradient so it reads over the sunrise.
Content: lang-keyed lines generated from `CREDITS.md` (one `eclipse.credits.roll.NN` key
per line via the langdrop protocol — keeps de/en parity enforceable). Starts at the
beach fade-in, ends before the final "ECLIPSE" card.

## B5. Failure-safety

- `/eclipse credits skip` (GAMEMASTERS): jump to the t=735 fade-black beat — music finale
  still plays, **no client close** (skip implies rehearsal). `/eclipse credits abort`:
  full `CutsceneService.abort` + everyone to overworld spawn.
- Replayable: `SequenceReplayable` id `credits`, every beat FX-only standalone
  (`/eclipsefx sequence credits HELM|WHITEOUT|BEACH|LIGHTNING|TITLE|CORRECTION|OUTRO`).
- **Restart mid-sequence**: IntroSequence law — persisted phase, restart skips to end
  state (players at overworld spawn, `ferrymanDefeated` already persisted) and NEVER
  fires the close broadcast after a restart.
- **Solo player**: identical flow; the solo player IS the egg-offerer/helm double;
  `CutsceneService` groups are count-based so 1 works; auto-run wide shot degrades fine.
- **Disconnect mid-credits**: `CutsceneService.PendingReturns` already restores them at
  next login; close payload goes only to online, nonce-matched clients.
- **Iris/`veilPostFx=false` clients**: every world-side FX beat has a GUI fallback
  (fades are `CaptionRenderer`, cards are GUI overlays) — the sequence fully reads with
  zero Veil pipelines.

## B6. New assets needed

1. **ONE music cue** — `assets/eclipse/sounds/music/credits_finale.ogg` (~70 s: beach
   swell → lightning hit at 0:20 → comedic brass sting under the title → 15 s emotional
   outro that ENDS, no loop). Treblo/Sonauto pipeline (`tools/music/treblo_generate.py`),
   post-process to OGG **Vorbis**; register in `EclipseMusicSounds` + `MusicCues`
   (`CREDITS_FINALE`, looping=false, durationTicks≈1500).
2. **No title textures required** — both cards are text-rendered (`BossIntroOverlay`
   decode + `CaptionRenderer` TITLE). Optional polish: a stylized
   `textures/gui/credits_correction.png` card; ship text-only v1.
3. Part A: 1 reskin texture `glitched_wanderer.png` (recolor of the glitched_husk sheet),
   1 jumpscare face texture (128×128 — an upscaled, smeared crop of the_other's face
   keeps it in-universe), optional real `backrooms_buzz.ogg` (alias pitching covers v1).
4. Lang keys en/de for: backrooms announce/exit/leave lines, credits titles + roll.

## B7. Open questions, ranked

1. **Legal/tone check on the fake-out title** — "COMES BACK IN AVENGERS: DOOMSDAY" is a
   parody beat on a private server; owner should sign off on the exact wording (the
   correction card "ECLIPSE : DOOMSDAY" is the joke either way).
2. **Beach location**: new `eclipse:epilogue` dim (recommended — controlled sky, frozen
   sunrise, no terrain risk) vs. the disc's east rim (real-world continuity, but rim
   terrain + storm FX state make the shot fragile).
3. **`victory_theme` handoff**: `beginVictory` force-plays it (3600t ownership); confirm
   `stop()` at t=0 doesn't fight `MusicManager`'s suppress-situation latch when
   `credits_finale` starts at t≈290 (order: stop → forced play is the safe pattern).
4. **`minecraft.stop()` while connected**: verify the server sees a clean disconnect
   (it should — identical to closing the window) and that no lives/grave hook reacts to
   the disconnect during the OUTRO phase.
5. **Title-card theme**: reuse `BossIntroOverlay` as-is (DANGER red reads "threat") or add
   a payload theme param for a gold/credits variant (~40 LOC in the overlay).
6. **Backrooms maze scale**: 24×24 cells for 30 min — playtest whether the exit-portal
   walk at T-5:00 is findable; bump highways from every 8 to every 6 cells if not.
7. **Jumpscare scope**: once per *instance* (designed) vs once per *player per event
   evening* across re-entries — lockout-mode interaction decides.
8. **Flicker load**: ~50 light relights/min near players — measure on the event server;
   fallback is halving faulty-panel density (hash threshold 6%→3%).
