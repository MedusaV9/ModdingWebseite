# WB-GHOSTFX wiring notes — ghost/skin visual upgrades + P2 seam fixes

**Zero hub edits.** No `EclipseMod`, `EclipsePayloads`, `FxPayloads`, `network/**`,
`registry/**`, lang JSON, `sounds.json` or `build.gradle` changes. The one new class
(`limbo/door/DoorLoginResync`) self-registers via `@EventBusSubscriber`; everything else
modifies files already owned by this worker's scope (plus the two sanctioned dead rows in
`veilfx/VeilPostController`). **No langdrop** — WB-GHOSTFX ships zero user-visible strings
(P2-W10 "empty allowed" precedent, file omitted entirely).

## What landed

### 1. Uniform skin upgrade (heart + lightning arcs)

- `scripts/skin_gen/eclipsed_player_v2.py` — heart strengthened (larger hot core/ring
  bands; glow alphas ring 220→235, halo 190→215, edge 150→180, 1px halo bleed 90→130 and
  albedo bleed 0.55→0.65) and THREE new sparse lightning-arc overlay frames generated:
  `textures/entity/eclipsed_player_arcs_{0,1,2}.png` (64×64, transparent except jagged
  1px violet bolts over a different subset of body faces per frame). Separate textures
  were chosen over spare-region baking — robust: the base skin/glow layouts stay
  byte-replaceable by AI art, and the arc pass self-disables if any frame is missing.
  Regenerated outputs verified **byte-identical across runs** (fixed seed) and confined
  to the heart bbox (x20–27, y21–28) on `eclipsed_player.png` / `_glow.png` /
  `the_other.png` — the two frozen doppelganger deltas are untouched.
- `client/entity/player/EclipsedPlayerGlowLayer.java` — two additive passes, both
  `reducedFx`-gated and allocation-free (primitive math + pre-created `RenderType`s):
  - **Heartbeat pulse**: glow alpha 0.75→1.0 on a ~2 s sine (40 ticks), phase-offset per
    entity id (`heartbeatAlpha`, public — the ghost layer breathes on the same clock).
    Under `reducedFx`: steady 1.0 (config comment says no pulsing overlays).
  - **Arc flicker**: one 7-tick (~350 ms) burst per 180-tick window at a hashed offset
    inside the window's first 60 ticks → consecutive bursts land **120–240 ticks
    (6–12 s) apart**, deterministic per entity id. Frames switch every 2 ticks;
    alpha ≤ ~0.6 with a taper — vein-crawl, not strobe.

### 2. Logout-ghost renderer refinements

- `client/entity/ghost/GhostPlayerRenderer.java`:
  - Slow vertical **drift** (±0.05 blocks, ~15 s sine, per-entity phase) layered under
    the existing 0.05-speed bob; idle body-alpha **shimmer** 0.40 ± 0.04 (~0.09 speed,
    steady 0.40 under `reducedFx`). Reveal flicker unchanged.
  - New nested `HeartGlowLayer`: re-renders the posed model over the shared
    `eclipsed_player_glow.png` with `RenderType.eyes` at fullbright, alpha breathing
    0.60–0.82 on the same heartbeat — **the purple heart reads through the 40%
    translucency at any light level**. Skips invisible entities; no-ops forever if the
    glow texture is missing (shares `EclipsedPlayerGlowLayer.glowTextureAvailable()`,
    now public). Class marked `final` (nothing subclassed it; silences this-escape).

### 3. P2-W10 relog seam fix (door glow)

- `limbo/door/DoorLoginResync.java` (NEW) — `PlayerLoggedInEvent` →
  `RespawnDoorApi.resyncGlowFor(player)`. Mirrors the `FxAnchors` login re-send pattern.
- `limbo/door/RespawnDoorApi.resyncGlowFor(ServerPlayer)` (pure-additive; no existing
  method fit "re-send current state to ONE player") — no-op while limbo/the door is
  absent (client login default is glow-off, matching); otherwise sends the current cue.
  **Glow mapping chosen: on = `DoorState != SEALED`** (mirrors the multiblock's LIT
  rule: seam breathes CLOSED, blazes OPEN, dead SEALED). Trivially adjustable in one
  line if P4's lives flow wants OPEN-only.
- `limbo/door/DoorPayloads.sendDoorGlow(player, pos, on)` (additive, inside limbo/door
  ownership per the resync carve-out) — sends the pre-registered
  `eclipse:fx/door_glow` `S2CFxEventPayload` (W1's untouched `fx1` registrar) to one
  player, `a = 1/0`.
- **Still P4/P6's side of the contract**: broadcasting the event on door state CHANGES
  (`FxPayloads.sendFxEvent(...FX_DOOR_GLOW...)` from wherever `setGlobalState` is
  driven) remains theirs per P2-W10 wiring — grep shows no state-change broadcaster in
  the tree yet, so today the login re-fire is the only sender. Event/anchor arrival
  order is irrelevant (`ShipDoorGlow` latches both).

### 4. VeilPostController dead-row cleanup (sanctioned)

Verified before removal: `LimboAmbience` (static init, `@EventBusSubscriber(CLIENT)`)
registers `eclipse:limbo` and `BorderFxRenderer` (same pattern) registers
`eclipse:border_glitch`; P2-W3 wiring ("safe to delete on your next pass") and P2-W4
wiring ("dead at runtime … fold it away") both sanction the deletion. Removed: the two
`registerDefault(...)` rows, the `registerDefault` helper, the `Row.isDefault` flag,
`wantLimbo`/`feedLimbo`/`limboIntensity`, `wantBorderGlitch`/`feedBorderGlitch`, the
`limboEnterMillis` bookkeeping (field + tick tracking + logout reset,
`LIMBO_FADE_*` constants) and the now-unused `Easing`/`LimboDimension` imports. The
public surface (`register`, `setEnabled`, `clearOverride`, `isActive`, the four
`*_POST` ids) is untouched — all 8 registering/consuming classes recompiled clean
against the new file.

### 5. EntitySkinArtist writeTheOther() guard

`scripts/placeholder_gen/EntitySkinArtist.writeTheOther()` is now a deliberate no-op
with a pointer to `scripts/skin_gen/eclipsed_player_v2.py` (per P6-W12 wiring note 4:
its old input `uniform_skin.png` was deleted, so the previous body crashed on
`ImageIO.read`). Verified by running the full painter: no crash, `the_other.png`
untouched. **Caveat for the file's owner**: the shipped `deckhand.png` has diverged
from what this painter generates (re-running it overwrites the newer shipped art — we
restored `deckhand.png` from git after the verification run). Sync `writeDeckhand()`
to the shipped art, or retire it the same way, in a future pass.

## Verification

- `javac --release 21` (sandbox pattern — no gradle): all 6 touched main-tree files +
  `PlayerLayerHandler`, `GhostRenderers`, `ShipDoorGlow` and the 8 `VeilPostController`
  consumers → 0 errors, 0 warnings on owned files. `EntitySkinArtist.java` compiles and
  runs standalone.
- `python3 scripts/skin_gen/eclipsed_player_v2.py` run twice → all 6 PNGs byte-identical
  (md5), landing exactly at
  `src/main/resources/assets/eclipse/textures/entity/eclipsed_player{,_glow,_arcs_0,_arcs_1,_arcs_2}.png`
  and `.../the_other.png`.

## Perf notes (zero per-frame allocations)

Per player per frame the new work is: 1 sine + 1 hash (pulse) and ~3 int hashes (arc
gate; the extra model pass only runs ~4% of the time). The ghost adds 2 sines + 2 hashes
and one extra model pass over a texture that is ~97% transparent pixels. All
`RenderType`s and `ResourceLocation`s are static finals; no boxing, no lambdas in the
render path, resource-presence checks memoized once per session.
