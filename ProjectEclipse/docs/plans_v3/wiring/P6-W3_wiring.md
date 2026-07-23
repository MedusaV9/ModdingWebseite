# P6-W3 wiring (ghost ship v2 rebuild + Respawn Door)

**ONE integrator wiring line** (everything else is annotation-discovered or
self-registering):

```java
// EclipseMod constructor, with the other deferred registers (e.g. right after
// dev.projecteclipse.eclipse.entity.ambient.AmbientEntities.register(modEventBus); ~line 46):
dev.projecteclipse.eclipse.limbo.door.DoorRegistry.register(modEventBus);
```

Until that line lands every consumer no-ops safely with one log line
(`DoorRegistry.isBound()` guard, P6-W1 pattern): `RespawnDoorApi.ensureDoor` skips
placement, the client renderer registration skips, and boot stays green on both dists.
No other hub files need touching: `GhostShipBuilder` keeps its existing
`@EventBusSubscriber`, `DoorPayloads` self-registers a NEW payload registrar
(`p6w3`; `RegisterPayloadHandlersEvent` allows any number — `EclipsePayloads` and
`FxPayloads` untouched), and `DoorRenderers` self-registers the BER client-side.

## Files touched (all P6-W3-owned per the plan §3 matrix)

| File | Change |
|---|---|
| `limbo/GhostShipBuilder.java` | Rewritten: v2 ship (§2 build design) + `ShipVersionData` version-gated migration. Boot chain now: `buildIfNeeded` → `LimboSeascape.buildIfNeeded` → `OarAnimator.ensureOars` → `DeckhandEntity.ensureCrew` → `ShipLanterns.ensurePlaced` → `RespawnDoorApi.ensureDoor` → `RespawnDoorApi.publishAnchors`. After a v1→v2 migration it calls `DeckhandEntity.calmCrew` once (W2 wiring note §4). |
| `limbo/ShipLanterns.java` | Lantern spots relocated to the v2 deck plan (version-aware: v1 spots stay served while a deferred migration keeps the old ship — see "Migration" below). Fight logic untouched. |
| `limbo/door/*` (NEW, 10 files) | `DoorState`, `ShipVersionData`, `DoorRegistry`, `RespawnDoorBlock` (controller), `RespawnDoorFillerBlock`, `RespawnDoorBlockEntity` (GeckoLib), `RespawnDoorApi` (frozen P3/P4 surface), `S2CDoorCuePayload` + `DoorPayloads` (registrar `p6w3`), `package-info`. |
| `client/entity/door/*` (NEW, 3 files) | `RespawnDoorRenderer` (GeoBlockRenderer + `AutoGlowingGeoLayer`), `DoorRenderers` (self-registration, ghost-view rule, cue ingest), `package-info`. |
| Assets (NEW) | `geo/block/respawn_door.geo.json` (6 bones/14 cubes), `animations/block/respawn_door.animation.json` (4 anims), `blockstates/respawn_door{,_filler}.json`, `models/block/respawn_door.json` (particle-only), `models/item/respawn_door.json`, `textures/block/respawn_door.png` + `_glowmask.png` (128×128, generated), `scripts/geckolib_gen/mobs/respawn_door.py`, `docs/uv/respawn_door.md`. |
| `docs/plans_v3/langdrop/P6-W3.json` | **4 keys** ×2 locales: `block.eclipse.respawn_door`, `block.eclipse.respawn_door_filler`, `message.eclipse.door.locked`, `message.eclipse.door.closed`. |

**Deliberately NOT touched:** `EclipseMod`, `EclipsePayloads`, `FxPayloads` (P2-W10's
`S2CShipDoorPayload`/`ShipDoorGlow` stay theirs — see FX handshake below),
`EclipseCommands`, `DeckhandEntity`/`OarAnimator` (P6-W2's; consumed via their frozen
statics only), `FerrymanEntity`, `LimboSeascape` (owned but v2 needs no seascape change),
src lang JSONs, `build.gradle`.

## Ship v2 — frozen geometry other workers consume

Bow = +X. `deckY = waterlineY(limbo) + 3` (waterline 48 with the shipped datapack →
deck 51). All pre-P6 public statics kept byte-compatible: `NOMINAL_CENTER`,
`HALF_LENGTH=19`, `HALF_WIDTH=4`, `MAST_X={-8,8}`, `halfWidthAt` (4→|x|≤12, 3→≤15,
2→≤17, 1→≤19), `waterlineY`, `platformArrivalPos` (0, waterline+4, 12). New frozen
constant: `GhostShipBuilder.DOOR_X = -17` (sterncastle bulkhead plane).

### For P6-W2 (oars/benches — answers to your wiring doc §"Notes for P6-W3")

| Your requirement | v2 status |
|---|---|
| No oar displays / oarlock display anchors | None placed. `ensureOars` (legacy purge) still called every boot. |
| Benches x∈{−12,−4,4,12}, seat = deck level `waterline+3`, one block inboard of gunwale | UNCHANGED — same `halfWidthAt`, same deckY. Seat cells and the air above them are untouched by all v2 dressing. |
| `ensureCrew` + `ensureOars` from `onServerStarted` | Kept, same order (after `buildIfNeeded`). |
| `calmCrew` once after a rebuild | Done — `buildIfNeeded` calls it right after a v1→v2 migration (no-op on fresh builds / v2 boots). |
| Oarlock cosmetics aligned with bench columns | Open-trapdoor notches dip the gunwale rail exactly at the 8 bench cells (rail is fence/chain elsewhere). Freeboard stays 3 (≤ your 7-block splash probe). |
| Rigging clearance | Chain backstays cross the gunwale line at (±12, deck+4, ±4) — 3 blocks above the notch, outside the oar arc (loom exits ~0.9 above seat, blade dips below deck). Sail cloth stays at deck+5+. |

### For P2-W10 (door glow FX — `ShipDoorGlow`)

Published by `RespawnDoorApi.publishAnchors` on every server start once the ship is v2
(re-published, never stale; `FxAnchors` re-sends at login):

| Anchor id | Value (relative) | Absolute w/ shipped datapack |
|---|---|---|
| `eclipse:ship_door` (`FxAnchors.SHIP_DOOR`) | (DOOR_X+1, deck+3.5, 0.5) = center of the door's FRONT plane | (−16.0, 54.5, 0.5) |
| `eclipse:ship_deck` (`FxAnchors.SHIP_DECK`) | (0.5, deck+1, 0.5) = midship feet level | (0.5, 52.0, 0.5) |

Door front faces **EAST** (+X, toward the bow) — spill your glow toward +X.
Purple: `#B98CFF` blaze / `#6E4DA8` fade (§2.5). Live intensity hook: on the client,
`level.getBlockEntity(pos) instanceof RespawnDoorBlockEntity be ? be.getGlowStrength() : 0`
(controller cell = `RespawnDoorApi.controllerPos`; block at `eclipse:ship_door` minus
1 on x). Returns animated 0..1: 0.12 sealed, 0.3–0.8 breathing closed, 1.0 open —
already per-viewer (ghost rule + personal cues applied), so your FX and my leaves can
never disagree on a client. The multiblock also emits real block light 7 while LIT
(every state except SEALED). Your `S2CShipDoorPayload`/`ShipDoorGlow` remain untouched
and complementary; the door's own per-player cue uses my separate `p6w3` registrar.

### For P3-W7 / P4 (death/respawn flow) — door state contract

Global state machine (`DoorState`, server-authoritative, persisted in the controller
BE, synced via plain BE data): `SEALED` (dark, light off) / `CLOSED` (default; purple
seam breathing) / `OPEN` (leaves held wide, full blaze). **Ghost viewers always SEE
CLOSED even while globally OPEN** — client-automatic
(`DoorRenderers.viewerSeesClosed()`: `eclipse_ghosts` team OR synced lives ≤ 0); no
server code needed.

`RespawnDoorApi` (all no-op-safe while the door/registry is absent):

| Call | Use |
|---|---|
| `setGlobalState(limbo, state)` | P4 drives the world-visible door (lives flow). Flips LIT + plays the transition sound. |
| `playOpenFor(player)` / `playCloseFor(player)` / `clearCueFor(player)` | Personal revive walk-through: ONE client swings the door (cue outranks the ghost rule on that client until cleared/level change). |
| `playLockedShudder(limbo)` | Global "the door refuses" rattle; also auto-fired when a ghost right-clicks the door. |
| `doorFrontPos(limbo)` / `doorFacing()` / `controllerPos(limbo)` | Respawn/cinematic placement. `doorFrontPos` = (−16, deck+1, 0) — **shared with the Ferryman kneel anchor**; offset +1x further out while a Ferryman fight is live. |
| `globalState(limbo)` | Reads back the current state (CLOSED while absent). |

Documented v1 limitation (plan §2.5): collision is solid for EVERYONE in every state —
"open" is visual/narrative. Teleport the revived player through via `doorFrontPos`.
Right-clicks never open it (ghosts get shudder + `message.eclipse.door.locked`, living
get `message.eclipse.door.closed`).

## Migration & idempotence (verification reasoning)

- Fresh world: `ShipVersionData` (own `eclipse_ship_version.dat` in LIMBO storage —
  the shared `EclipseWorldState` is NOT extended) is NONE → v2 built directly, stamped.
- Legacy save: `EclipseWorldState.isGhostShipBuilt()` && version NONE → adopted as v1 →
  volume x±21/z±6/keel..deck+12 reset to open sea and rebuilt v2 in the same
  server-thread pass (no fluid tick between), then `calmCrew`. Skipped (retried next
  boot) while a Ferryman is alive; `ShipLanterns.positions()` keeps serving v1 spots in
  that window so a persisted mid-fight lantern phase keeps its counters.
- v2 boot: version check short-circuits before any block write — **zero block changes**
  (the "second boot" contract). All dressing randomness is `DiscMapData.ECLIPSE_SEED`
  positional hashes; `build()` writes every cell in the same order with the same state
  → byte-identical rebuilds. `ensureDoor`/`ensurePlaced` compare-before-write.
- Painter is deterministic: reruns verified byte-identical (md5).

Compile: sandbox `javac --release 21` over all 15 owned java files → 0 errors/warnings
(only foreign AT-dependent files error when dragged in via `-sourcepath`, expected).
`./gradlew compileJava` currently fails on ONE foreign in-flight seam —
`devtools/dev/DevRoot.java:92` unreported `CommandSyntaxException` around the
`DevHandbookBridge.tryOpenHandbook` call (handbook worker's wave) — zero diagnostics on
any P6-W3 file. `validate_geo.py`: 2/2 PASS, 0 warnings.

## Visual QA checklist (orchestrator pass — needs runClient)

1. **Silhouette** from the spawn platform (+Z side), bow-on (+X) and stern-on (−X):
   3-tone hull (planks + log ribs every 4x + stripped wale stripe at waterline+1),
   barnacle dither below waterline, stair-fillet curves at |x|=13/16/18, raised
   forecastle, sterncastle wings + transom + poop lanterns, two masts with stepped
   tattered sails (holes vary per column), crow's nest aft mast, bone figurehead +
   skull + bowsprit with hanging soul lantern.
2. **Door states** (after the `DoorRegistry` wiring line): boot log "Respawn door
   multiblock placed/repaired… (15 cell(s) changed)" once, then silent on reboot.
   `closed_idle` seam pulse; `setGlobalState OPEN` → swing + hold + louder glow;
   `CLOSED` → slam-with-rebound then idle; `SEALED` → block light off, glow near-dead;
   right-click as ghost → shudder + action-bar whisper; as living → hint only.
   Ghost view: while globally OPEN, a lives=0/`eclipse_ghosts` client renders it closed.
3. **Per-player cue**: `playOpenFor` on client A → A sees it open, client B doesn't.
4. **Migration**: load a pre-P6 save → "cleared back to open sea …" + "rebuilt from
   v1" logs once, benches/rowers intact after `calmCrew`, lanterns at the four v2 spots
   (2 mast bases flanking the king plank, forecastle top, starboard wing), wing ladders
   at (−16, ±2) climbable by a ghost to the quarterdeck lantern (3-block channel range).
5. **Second boot**: "Ghost ship v2 present … zero block changes" and no door/lantern
   placement logs.

## Deviations from the plan text

- Door state sync: plan offered "own registrar or reuse `S2CShipDoorPayload`" — chose
  OWN registrar (`p6w3`) because the global state needs no payload at all (plain BE
  data), and only the per-player CUE payload is custom. `FxPayloads` untouched.
- `EventBusSubscriber(bus = …)` attribute omitted in new classes (deprecated-for-removal
  in NeoForge 21.1; the event type auto-routes) — avoids adding new removal warnings.
- Filler blocks carry COL/ROW state (self-describing multiblock repair) instead of the
  plan's implicit "dumb filler" — keeps `ensureDoor` strictly compare-before-write.
