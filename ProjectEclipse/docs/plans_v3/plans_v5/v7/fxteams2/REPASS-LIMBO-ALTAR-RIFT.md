# VEIL-REPASS-2 — fresh-eyes second polish: LIMBO / ALTAR / RIFT

Team log for the second-pass polish over three clusters previously craft-passed by the v6
fxteams (`fxteams/LIMBO.md`, `ALTAR.md`, `RIFT.md` — done + rejected lists read first):

- **Limbo pipeline** — `limbo.fsh`, `veilfx/LimboAmbience`, `client/sky/LimboSpecialEffects`
  (`LimboHorizonShips` audited, untouched).
- **Altar suite** — `client/sky/AltarVeilSky`, `client/drama/AltarCeremonyFx`,
  `worldgen/structure/SanctumOrbitals` (+ the payload seam: `ritual/AltarBlockEntity`,
  `network/fx/FxPayloads`). `AltarIdleMotes` / `OfferingSwallowFx` audited, untouched —
  see the ALTAR rejected list.
- **Rift renderer** — `veilfx/rift/RiftRenderer`, `veilfx/rift/RiftFx`.

**Frozen-fix audit (mandate item 0) — all four later fixes verified INTACT before work:**
- *facing smoothstep* — `limbo.fsh` water mask: `facing = smoothstep(surfaceY+0.1,
  surfaceY+0.9, CameraPos.y) * smoothstep(0.005, 0.05, -rel.y)` (POL-F 8). Untouched.
- *eps cap* — `eps = min(0.55 + dist*0.012, 1.65)` keeps the far band below deck
  (waterline+3). Untouched.
- *VoyageOffset accumulation* — `LimboAmbience.feedLimboPost` accumulates from
  `limboEnterMillis` (never the hourly wrap). Untouched.
- *Detail uniform gating* — `Detail = reducedFx ? 0 : 1` gates every v4 water-motion layer;
  all NEW motion layers below ride the same gate (or feed 0 at the CPU, or both).

**Validation (per task constraints — no gradle, no git):**
- `limbo.fsh` compiles clean with `glslangValidator -S frag` (Veil preprocessing emulated:
  `#version 450 core` header + `#include eclipse:eclipse_common` inlined).
- All 9 touched Java files compile clean in ONE `javac -proc:none -nowarn` invocation
  against the real NeoForge 21.1.238 merged jar + Veil 4.3.0 + full modules classpath +
  `build/classes/java/main` (`-sourcepath src/main/java` for in-project deps):
  `LimboAmbience`, `LimboSpecialEffects`, `AltarVeilSky`, `AltarCeremonyFx`, `FxPayloads`,
  `AltarBlockEntity`, `SanctumOrbitals`, `RiftFx`, `RiftRenderer`.
- No JSON was touched; the full 109-file `assets/eclipse/quasar/**` + `pinwheel/**` sweep
  still parses (`python3 json.load`).

---

## Component 1 — LIMBO (limbo.fsh + LimboAmbience + LimboSpecialEffects)

**RE-PLAN.** v4 made the sea read as water at three distance scales; what it still lacks
is (a) a sky above the eclipse that feels like an atmosphere rather than empty black,
(b) any coupling between the sky's heartbeat and the sea, and (c) LIFE below the surface
(v4's glints are anchored flotsam — nothing *swims*). Everything must sit on top of the
frozen v3/v4 machinery without moving it.

**IDEATE (7 new).**
1. **Aurora veils framing the eclipse** (frontier) — cheap gradient-quad curtains at
   extreme altitude. Spatial note: in the zenith celestial frame the eclipse IS the
   topmost point, so "above" = close *around* it — partial arcs beyond the glow floor,
   not a horizon band. **PICKED.**
2. **Sea breathing synced to the corona pulse** (frontier) — the "uniform exists" is
   `Time`: the dual-frequency aura curve is already re-derived in the shader for the
   reflection smear; hoist it and multiply into the water field. **PICKED.**
3. **Soul shoal** (frontier) — a school of tiny soul-green lights crossing under the
   surface near the ship. Needs shoal-LOCAL space (the formation swims — the exact
   opposite of the world-anchored glints). **PICKED.**
4. Aurora reflection on the water (mirror the veils like the disc smear). **REJECTED** —
   the v4 team already rejected a second mirrored term for the storm glow ("why is the
   sea flashing?"); same restraint call, and the veils are dimmer than the glow was.
5. Shoal fleeing the storm glow (suppress `SoulShoal` while `LightningGlow.z` is high).
   **REJECTED** — cross-coupling two rare deterministic events makes both harder to QA
   for near-zero observable payoff (they almost never overlap: ~30% × ~55% of disjoint
   slot grids).
6. Aurora veils tinting the god-ray shafts green while overhead. **REJECTED** — the
   god-ray colonnade is a violet identity anchor (v2 freeze); recoloring it reads as a
   palette bug.
7. Ship wake responding to the sea breathing (swell the drift-cue foam cadence with the
   pulse). **REJECTED** — particle cadence is budget-law territory; the breathing is a
   POST-only statement by design.

**IMPLEMENT.**
- `limbo.fsh` v4.1:
  - Corona pulse `0.85 + 0.11·sin(1.3t) + 0.04·sin(0.37t + 1.7)` hoisted to the top of
    `main` — ONE curve now feeds the reflection-smear shimmer (formerly a duplicate
    inline derivation) *and* the new sea breathing. Sky pass, smear and sea can never
    desync pairwise.
  - **Sea breathing**: `seaBreath = mix(1.0, 1.0 + (pulse − 0.85) · 0.5, Detail)` —
    ±7.5% re-centered on the steady v4 exposure, multiplied over the whole violet block
    (lift + web + sparkle + micro). Glints stay unbreathed: they are creatures *in* the
    water, not light *of* the water. `Detail`-gated (scene-wide luminance motion is
    exactly what the reduced contract removes).
  - **Soul shoal**: new `vec4 SoulShoal` (xy = shoal center world-XZ, zw = heading ×
    strength). Shoal-local frame (x along heading, y abeam) → elliptical formation
    envelope (~±13 × ±5 blocks) → ~1.2-block fish cells (58% occupied), each one
    stretched gaussian dash with a per-fish swim wiggle, brightness carried by
    `0.45 + 0.55·web` so the lights shimmer as if refracted from below. Gated on the
    water mask + `Detail`; strength 0 = zero cost.
- `LimboAmbience` — `feedSoulShoal`: the storm-glow slot law with distinct salts
  (73-s slots, ~30% host a crossing → ~4 min average; every client sees the same shoal
  at the same second). Path: hashed heading + hashed 6–20-block closest approach abeam
  of the ship anchor, 3.2 blocks/s for 26 s, sin fade-in/out envelope. Zero vector under
  `reducedFx` / idle / parked `InvViewProj` (the CurveAmount ladder + the LightningGlow
  matrices guard).
- `LimboSpecialEffects` — `drawAuroraVeils`: three partial-arc curtains (70–110°) at
  radii 152/178/204 (beyond the 135 glow floor, just past the 150-max ray tips), each
  18 gradient quads: bright soul-green foot at the outer edge undulating on a 3-lobe
  wave, feathering violet toward the zenith; per-edge shared shimmer values keep the
  strip C0. Peak alpha 0.085·pulse with slow non-commensurate per-veil breathing; drifts
  0.011/−0.008/0.014 rad/s. Garnish tier — skipped under `reducedFx` (the wisp ladder);
  pure function of the hourly clock (deterministic, stateless).

**POLISH 1 (correctness).** Breathing range re-derived (0.925–1.075 ✓); shoal formation /
cell math traced at the boundary (hash offset `(91,47)` decorrelates the fish grid from
the glint grid); `SoulShoal` uniform defaulted safe (feeder always writes it); aurora arc
end-feathering via `sin(πt)` shares edge values between segments (no banding).

**POLISH 2 (restraint/laws).** Aurora alpha ceiling kept BELOW every existing sky layer
(0.085 vs glow 0.30 / rays 0.4); veils framed (3 arcs), never encircling — the eclipse
stays the subject; shoal crossing never passes under the keel (6-block minimum abeam);
uniform-parity audit: 12 non-sampler uniforms declared, 12 fed.

---

## Component 2 — ALTAR (AltarVeilSky + AltarCeremonyFx + SanctumOrbitals + payload seam)

**RE-PLAN.** The W-P-ALTAR2 motif pass gave every tier a behavior; what the suite still
lacks is (a) a *transition* language — level-ups snap layers on, (b) social awareness —
a 5-player ceremony looks identical to a solo one, and (c) a rare orbital showpiece.

**IDEATE (7 new).**
1. **Tier-transition MORPH** (frontier) — 3 s of visible transformation instead of a
   snap. **PICKED.**
2. **L2 glyph connect lines** (frontier) — hairline light joining the glyphs during the
   rearrange glide. **PICKED.**
3. **Crowd-aware ceremonies** (frontier) — payload audit found `S2CFxEventPayload.b`
   sent as a hard `0.0F` for `FX_ALTAR_LEVELUP`: a free, contract-safe carrier for the
   server-side crowd count. **PICKED.**
4. **Orbital alignment event** (frontier) — all big-ring debris into one line for 2 s on
   a deterministic schedule. **PICKED.**
5. Crowd-scaled glyph-rain particle waves (more players = more waves). **REJECTED** —
   particle counts are FxBudget law; the burst-radius carriers (screen shockwaves) are
   the sanctioned "wider" knob, and they are world-visible so every witness sees the
   crowd effect.
6. Morph also replaying on login when the synced level is higher than last session.
   **REJECTED** — the write-in intro deliberately adopts silently on login (trackLevel
   law); the morph follows the same rule or login becomes a fireworks show.
7. `AltarIdleMotes` column pulsing with the ceremony crowd factor. **REJECTED** — the
   idle motes are the *permanent* tell; wiring them to a transient ceremony parameter
   crosses the permanent/ceremony separation the suite is built on.

**IMPLEMENT.**
- `AltarVeilSky` — **morph**: `trackLevel` arms `morphStart/morphFromLevel` on a genuine
  ≥1→higher increase (0→1 keeps the write-in; login/decrease adopts silently; a
  multi-step jump morphs once). During the 3 s window: newborn layers (above
  `morphFromLevel`) draw through `layerPose` — the pre-allocated `MORPH_POSE` scratch
  scaled 55%→100% in the celestial plane (they GROW out of the disc) with alpha ×
  smooth(t); surviving layers swell once (×`1 + 0.35·sin(πt)`); one bridge ring sweeps
  from the L1 ring radius to the newborn layer's home radius (per-level target table),
  peaking mid-morph. Tier 0 keeps its ring-only contract.
- `AltarVeilSky` — **connect lines**: the glyph loop stores centers into pre-sized
  scratch (`GLYPH_X/Z`); while `chime > 0` (rearrange window — tier-2-only by
  construction, so the lines inherit the ladder gate) each glyph links to the next
  around the loop: hairline quads (half-width 0.55), trimmed 5 units to the diamond
  rims, alpha 35%→100% toward the destination — the light *flows* along the glide,
  and dies with the chime.
- **Crowd seam** — `AltarBlockEntity.completeMilestone` counts players within
  `CROWD_RANGE = 20` of the altar and sends it in the previously-unused `b`;
  `FxPayloads` forwards `(int) b`; `AltarCeremonyFx.start(pos, level, crowd)` computes
  `crowdF = clamp((crowd−1)/4, 0, 1)` (solo = 0, 5+ = 1) and widens the burst-radius
  carriers: L2 shockwave strength ×(1 + 0.5·crowdF), 36 → 50 t travel; L4 shockwave
  ×(1 + 0.4·crowdF), 50 → 66 t. `b = 0` (old servers / solo) is bit-exactly the
  pre-crowd composition.
- `SanctumOrbitals` — **alignment event**: every 4800 t (4 min; divisible by the 40 t
  push cadence, so envelope corners land exactly on push boundaries) the twelve big-ring
  fragments glide into one line through the altar: 120 t smoothstep gather → 40 t hold
  (the 2 s) → 120 t disperse. Positions lerp COMPONENTWISE between the (still-rotating)
  orbit point and a per-fragment slot (2.6-block spacing, ±14.3 span inside the 20-block
  scan margin, at island-top + 6) — no angular interpolation anywhere, so the summary's
  sweep-wrap risk is structurally impossible. Line azimuth advances by the golden angle
  per event. Absolute function of game time: stateless pushes, pause-glide behavior and
  the ring-2 islet exclusion all inherited unchanged.

**POLISH 1 (correctness).** Morph target table indices re-checked for multi-step jumps
(clamped level−2); `MORPH_POSE` sequential reuse safe (draws are immediate); connect
lines skip sub-trim segments; crowd factor saturates, never divides by zero; alignment
event tick arithmetic uses `Math.floorMod`/`floorDiv` (negative-safe) and the gather
worst-case glide (~28 blocks / 120 t eased) stays under the interpolation-window
flattening threshold at every boundary.

**POLISH 2 (restraint/laws).** Bridge ring capped at 0.28·strength (below the crown's
pulse flare); connect-line alpha rides GLYPH_ALPHA·chime·0.5 so lines can never outshine
the glyphs they join; crowd widens ONLY the two shockwaves (world-visible, budget-free) —
emitter counts untouched; alignment leaves tumble/bob running so the line still feels
"held by magic", and the islet companions keep their orbits like every other
big-ring-only behavior.

---

## Component 3 — RIFT (RiftRenderer + RiftFx)

**RE-PLAN.** FXTEAM-RIFT gave the tear depth (void well), refraction (lensing) and
moments (entry, surge). Two gaps: the delivery surge *sounds* like launches but the tear
itself never reacts physically, and the void well is dark but not *deep* — nothing in it
has scale.

**IDEATE (6 new).**
1. **Piece-launch recoil** (frontier) — the whole rift compresses 4% on each launch.
   **PICKED.**
2. **Void-well depth starfield** (frontier) — tiny stars inside the void shells.
   **PICKED.**
3. Recoil as an asymmetric squash (compress along the normal, bulge in-plane).
   **REJECTED** — needs a second scale axis through every builder signature for a
   subtlety invisible at the 8-tick rebound; the uniform compression reads identically
   and multiplies through ONE existing value (open).
4. Stars also inside portal void discs. **REJECTED** — the portal surface is a *surface*
   (the swirl counter-scroll sells it); stars behind it would fight the R17 parallax
   read and the budget line is already 398 worst-case for portals.
5. Star streaks during the delivery surge (stars smear toward the mouth while pieces
   launch). **REJECTED** — motion inside the well during surge competes with the
   materialize bursts at the mouth; one subject per beat.
6. Recoil on entry flashes too (portal squash when a player steps through).
   **REJECTED** — entry already owns three simultaneous tells (iris, whoosh, streamers);
   a fourth reads as jitter, and "recoil" is semantically a LAUNCH thing.

**IMPLEMENT.**
- `RiftFx.Rift` — `lastLaunchTick` anchored in `tickSurge` at every launch-burst tick
  (the exact 6 t StructureFlightFx batch cadence, still halved under `reducedFx`);
  `recoilScale(now)`: instant `RECOIL_AMOUNT = 0.04` compression, quadratic ease-out
  rebound over `RECOIL_TICKS = 8`. The 6 t cadence re-triggers before the 8 t rebound
  completes — a delivery volley reads as the rift PUMPING its pieces out.
- `RiftRenderer` — recoil applied once at cull time (`VIS_OPEN = open · recoilScale`):
  every layer (shells, fringe, arcs, lensing, well, stars) squashes coherently. Pure
  scale math, zero extra geometry → stays live under `reducedFx` (launch feedback, not
  candy — the entry-flash precedent).
- `RiftRenderer` — `buildVoidStars` (STRUCTURE, full quality, additive pass so they
  layer OVER the alpha-pass dark fans): 12 tiny in-plane triangles, positions/depths
  seed-hashed once (stable — deliberately NOT the 90 ms flicker cadence), each pushed
  its own distance along the camera→rift direction (`1.1×` outer-fan push … `1.3×`
  deep-fan push). Deeper = more parallax + dimmer + smaller: walking past the tear
  shears the star layers apart — infinite depth from 12 triangles. Twinkle rates are
  whole cycles per 100 s (the EVAL-POL-F #7 wrap law) with golden-angle phases.
- Budget recount (class javadoc updated): STRUCTURE 374 + 12 = **386 ≤ 400**;
  PORTAL/BACKROOMS unchanged (≤ 374 — stars are structure-only).

**POLISH 1 (correctness).** Recoil is portal-inert by construction (`lastLaunchTick`
only moves inside the structure-only surge); the raw `open` still drives the ≤0.005
cull; star scatter uses √(hash) for a uniform disc (no center clump); degenerate
camera-inside-tear guarded like the fans.

**POLISH 2 (restraint/laws).** Star twinkle frequencies converted to integer cycles per
100 s so the `swirlSeconds` wrap is seamless (the one wrap-unsafe sine caught in
review); star alpha ceiling 0.85·open before depth dimming — below the arc peaks, so
the rim stays the brightest thing; zero per-frame allocations preserved (no new scratch
needed — stars are computed inline from hashes).

---

## Cross-component notes

- **New uniforms:** `SoulShoal` (vec4) only. No frozen §3.3 name touched; no payload
  record shape touched (`b` was already on the wire, hard-zeroed).
- **Determinism:** every new scheduled event (shoal, aurora drift, alignment, morph)
  is a pure function of a shared clock (hourly wall-clock seconds, game time, or the
  synced altar level) — no render-loop RNG anywhere.
- **reducedFx ladder:** aurora veils + soul shoal + void stars = garnish (skip/zero);
  sea breathing = Detail-gated motion; morph/connect/crowd/alignment/recoil = tier-gated
  by their host systems or zero-cost scale math (documented per item above).
