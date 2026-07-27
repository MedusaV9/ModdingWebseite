# PLAN F-088 / F-089 — Limbo "big pink object" + structure-spawn blackscreen

Investigation notes + fix plan. Read-only audit of the code as of `b01dfb8` (27.07).
Both feedback items were logged 27.07 ~10:45–10:57 (+0200), i.e. AFTER the previous fix
wave landed (26.07 16:48 UTC: `5c3f733` LIMBOFIX2, `4d439dc` structures/no-blackscreen),
so the plan assumes both symptoms survive the current code. (Caveat for both bugs: if the
players' server was still on a pre-26.07-evening build, re-verify on the current build
first — see the verification recipes.)

---

## BUG 1 (F-088) — "großes pinkes Objekt" at the Limbo ship

### TL;DR root cause

The object is the **Limbo eclipse disc + its violet aura group** drawn by
`client/sky/LimboSpecialEffects` — not a missing texture, not the sea, not a Quasar
emitter. After LIMBOFIX2 it no longer *moves* with the camera, but it is still a
**~81°-wide additive violet/pink glow parked dead ahead of the ship's bow** (azimuth
`+X` = the buoy-lane heading = the direction the player looks at the ship start), at only
50° elevation. It dominates the entire forward sky and reads as "ein großes pinkes
Objekt, das die Sicht blockiert".

### Evidence (files / lines)

`ProjectEclipse/src/main/java/dev/projecteclipse/eclipse/client/sky/LimboSpecialEffects.java`:

- L223–229: `CELESTIAL_DIR` — compile-time constant direction: **azimuth `+X` ("dead
  ahead of the ship / the buoy-lane heading")**, elevation `ECLIPSE_ELEVATION_DEG`.
- L133: `ECLIPSE_ELEVATION_DEG = 50.0F`.
- L124/126: `SKY_DISTANCE = 100`, `DISC_SIZE = 38` → disc half-angle
  `atan(38/100) ≈ 20.8°` (a ~42°-wide disc).
- L165: `GLOW_RADIUS = 86` → aura-floor half-angle `atan(86/100) ≈ 40.7°` — the glow fan
  spans **~81° of sky**, its lower edge only ~9° above the horizon. Center color
  L469–470: `(0.55, 0.22, 0.95)`, alpha `0.30·pulse`, **additive** over a near-black sky
  → bright violet/pink.
- L143–162: 12 aura rays, tips out to `24 + 66 = 90` in-plane units (~42° from center).
- L199–210: aurora veils out to `88 + 2·8 + 22 ≈ 126` units.
- L357–406: the whole group draws with **depth test off inside the no-fog window**
  (never occluded, never fogged), disc quad at L401–406 (`eclipse.png` exists —
  `assets/eclipse/textures/environment/eclipse.png` — so NOT missing-texture magenta).

History (git): `5c3f733` (LIMBOFIX2, 26.07) fixed the earlier "giant purple thing moves
with every rotation" report by removing every camera term. What it did NOT change: the
group still sits **centered on the default view direction of the ship phase** and still
covers most of the forward sky.

### Ranked candidates

1. **Eclipse disc + aura group** (`LimboSpecialEffects`) — as above. Matches "groß",
   "pink", "nicht das Meer", "blockiert die Sicht ultra", and continuity with the earlier
   "giant purple portal" reports (same object, previous fix made it static but not
   smaller/off-axis).
2. `limbo_fog` Quasar sheets (`veilfx/LimboAmbience` L312–313 window: 2 live emitters
   spawned **8–22 blocks from the camera**; `assets/eclipse/quasar/emitters/limbo_fog.json`:
   billboards `8 ± 7` blocks, violet `#47257A`) — can drift right in front of the camera,
   but alpha caps at **0.13** (very dim); a contributing annoyance, not the main object.
3. Missing texture magenta — **ruled out** (all limbo sprites + `eclipse.png` exist).
4. `RiftFx`/portal at the gate — ruled out for "ganz am Anfang": the gate portal FX only
   plays during the start event (`StartEventCutscene`), not in the pre-event ship phase.

### Fix

All in `LimboSpecialEffects.java`; keep the LIMBOFIX2 invariant (zero camera terms):

1. **Rotate the fixed direction off the bow lane.** Give `CELESTIAL_DIR` a `±Z`
   component so the eclipse hangs ~45° to port of the lane instead of dead ahead, e.g.
   `dir = (cos50°·cos45°, sin50°, −cos50°·sin45°)` (keep it normalized; `CELESTIAL_ROT`
   derives from it). The god rays follow automatically (`LimboAmbience` reads
   `celestialDirection()` for `GodrayDir`, L457–467).
2. **Shrink + dim the aura** so even off-axis it reads as a celestial object, not a wall:
   `GLOW_RADIUS 86 → ~60`, glow center alpha `0.30 → ~0.20`, `RAY_ALPHA 0.4 → ~0.28`,
   `AURORA_BASE_RADIUS 88 → ~68`. (Horizon-clearance math still holds: at 50° elevation
   the horizon is at `100·tan(50°) ≈ 119` in-plane units; all extents stay ≤ ~100.)
3. Optional, if "pink" specifically bothers: nudge the glow center toward deep violet,
   e.g. `(0.55, 0.22, 0.95) → (0.42, 0.20, 0.92)` (less red ⇒ less pink).
4. (Candidate-2 polish, cheap): `LimboAmbience` FOG window `minDistance 8 → 14` so fog
   sheets never park directly in front of the camera.

### Verification recipe

1. Client + server (or singleplayer) with the mod; join pre-event → the limbo login gate
   spawns you on the ghost ship (or `/execute in eclipse:limbo run tp @s <ship coords>`;
   the deck anchor is `FxAnchors eclipse:ship_deck`, the shared spawn sits at the ship).
2. Look along the buoy lane (`+X`, yaw −90°), pitch up ~50°:
   - **Pre-fix:** the violet/pink disc+aura group fills the forward sky.
   - **Post-fix:** the lane view is clear; the (smaller, dimmer) eclipse hangs ~45°
     off to the side.
3. Regression (LIMBOFIX2 invariant): walk, jump, orbit in F5, spin the camera — the
   group must stay pinned to its sky direction (pans across the screen, never follows).
4. Regression: god rays (`eclipse:limbo` post pipeline) must still radiate from the disc.

---

## BUG 2 (F-089) — blackscreen when structures spawn

### What the previous fixes already covered (verified in code)

- `4d439dc` (26.07): (a) `RiftVolumeFx` camera-inside guard — `cameraClearance()`
  (L203–219) zeroes the raymarched volume below squashed-space depth
  `CAMERA_FADE_OUT = 1.15` and fades in by `1.55` (L74–75); the math is sound for both
  rift kinds (both are horizontal discs, normal `(0,1,0)`). (b) every `S2CScreenFadePayload`
  now has a client-side 3 s deadman in `CaptionRenderer` (only credits fades are
  `sustained`). (c) `ExpansionSequence` no longer sends screen fades at all (grep of all
  `new S2CScreenFadePayload(` senders: credits/finale/herald/cutscene/intro/limbo only).
- `1251597` (26.07): `ChunkPreload` fixed the expansion flyover "black screen" case.
- `FadeAmount` of the `rift_glitch` post pass only comes from portal enter/exit
  (`TransitionFx.envelopeFade`, L261) — structure spawns never drive it.

So the fade/post-processing hypotheses are **exhausted** — what remains is physical.

### TL;DR root cause (remaining)

**Players standing inside the footprint get entombed when the structure materializes.**
There is NO player-safety step anywhere in the placement path (verified by search over
`StructureFlightFx`, `SitePrep`, `StructurePendingRegistry`, `StructureStamper`,
`StructureGrounding`: no push/evacuate/teleport of players). The arrival animation
actively *attracts* players to the site (ground tear opens at enqueue, sky rift + flying
BlockDisplays hover-swirl overhead), then:

- `SitePrep` raises a plateau + packs foundations (terrain rises INTO the player), and
- the completion callback pastes the real blocks
  (`StructurePendingRegistry.place()` L363–377 → flight completion → `placeNow()` L390+
  → registered `SitePlacer`/`AsyncSitePlacer`).

A player inside the footprint at the snap ends up **inside solid blocks: the
inside-a-block overlay covers the screen (near-black) + darkness + suffocation** — read
by users as "Blackscreen beim Strukturen-Spawnen". This was never addressed by any
prior fix, which explains the "immernoch".

### The structure-arrival path (for reference)

1. Stage sweep completes → site enqueued PENDING
   (`worldgen/structure/StructurePendingRegistry`), server sends
   `S2CStructureRiftPayload` → client `EclipsePayloads.handleStructureRift` (L416–422)
   opens a **ground tear** at `anchor + (0.5, 1.0, 0.5)`, normal `(0,1,0)`, width
   `clamp(footprint·0.5, 4, 24)`, 200 ticks, style 0.
2. Expansion day STRUCTURES beat (`sequence/ExpansionSequence` class doc L104–115):
   close the ground tear, open a `STYLE_STRUCTURE` **sky rift** above the site
   (`FxPayloads` L175–177: normal `(0,1,0)`; client clamps width to `MAX_WIDTH = 72`,
   `RiftFx` L129/L204) at mouth height `RIFT_MOUTH_HEIGHT = 44` above the surface
   (`worldgen/stage/StructureFlightFx` L231, L480–500), 5 s hold, rolling lightning, up
   to 640 staged BlockDisplays hover-swirl, then the **snap** → `placeNow`.
3. `placeNow` runs the placer: `SitePrep` plateau/foundation + block paste. **No player
   handling anywhere.**

### Ranked candidates

1. **Entombment at the snap / plateau raise** (above) — literal, persistent-until-dug-out
   black screen; unfixed; players are drawn to the site by design. Also reproducible via
   the dev lane (`/dev structure place <id>` places at the operator's own feet,
   `DevStructureCommands` L143–156).
2. **Partial-strength rift-volume band**: `cameraClearance` fades over depth 1.15–1.55;
   standing ~14–19 blocks from a fully-open 24-wide ground tear leaves the near-black
   violet mass at partial strength filling much of a view looking across it — a
   momentary "almost black" under the eclipse grade. Cheap hardening available.
3. **Build mismatch**: the report may predate `4d439dc`+`1251597` on the players' server
   (fix commits 26.07 evening; feedback logged 27.07 morning). Verify before/after.
4. Screen fades / post FX — ruled out (3 s deadman; no fade senders in the structure
   path; `FadeAmount` portal-only; eclipse grade exposure floor 0.62).

### Fix

Primary (candidate 1) — add a **player evacuation seam** to the placement authority so
every lane (stage pipeline, retry auto-delay, dev commands) is covered:

1. New helper (suggested: `worldgen/structure/PlacementSafety.java`):
   `evacuate(ServerLevel, BoundingBox bounds, int seatY)` — for every player whose AABB
   intersects `bounds` (inflated ~1 block), teleport to the nearest footprint-edge column
   at `WORLD_SURFACE + 1` (or `seatY + 1` from `StructureGrounding`), give ~5 s of
   Slow Falling or clear fall distance.
2. Call it in `StructurePendingRegistry.placeNow()` (L390) immediately before invoking
   the placer — this covers the flight-completion snap AND the watchdog force-place —
   and from `SitePrep` right before the plateau fill touches columns (the terraform can
   bury a player even before the paste).
3. Post-paste sweep (belt-and-braces): after the placer reports PLACED, for any player
   still colliding with placed blocks (`!level.noCollision(player)`), lift them to the
   plateau top. Cheap: only players within the site bounds.

Secondary (candidate 2 hardening, one-line): widen the guard band in `RiftVolumeFx`
L74–75 to `CAMERA_FADE_OUT = 1.35`, `CAMERA_FADE_IN = 1.90` — the volume dissolves
earlier as the camera approaches; `RiftRenderer`'s star geometry keeps the spectacle.

### Verification recipe (RCON + one watching client)

Repro / entombment (pre-fix → post-fix):

1. Start the dedicated server, connect one client, op it (or `/devmode`).
2. `/dev structure list eclipse` → pick a mid-size id (e.g. an outpost).
3. Stand on flat ground and run `/dev structure place <id>` **with no pos argument**
   (places at your own feet, `DevStructureCommands` L148–149).
   - **Pre-fix:** the plateau/paste buries you → screen goes near-black (inside-block
     overlay), suffocation ticks.
   - **Post-fix:** you are moved to the footprint edge before the paste; no blackscreen,
     no suffocation.
4. Full-pipeline variant: while a second client stands ON a pending site during an
   expansion day (or force the stage beat), confirm the same before/after at the snap.

Rift-visual check (candidate 2, watching client):

5. `/eclipsefx sequence expansion structures` (FX-only replay, no world mutation) or
   watch a real beat; stand 10/15/20 blocks from the ground tear and directly under the
   sky rift: the raymarched mass must dissolve (never cover the full screen) at every
   distance; the star-tear geometry stays visible throughout.
6. Regression: rift look from 30+ blocks unchanged; `reducedFx`/quality tier 0 still
   shows the star geometry only.

Limbo pink-object check: see Bug 1 recipe above.
