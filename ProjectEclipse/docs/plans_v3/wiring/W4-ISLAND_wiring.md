# W4-ISLAND wiring — island geometry v3, edge-glide, altar ceremony, universal soft landing

## Files

| File | New/Edit | Role |
|---|---|---|
| `worldgen/structure/FloatingSanctumBuilder.java` | edit | Geometry v3 dress pass (`dressV3`): belly tendrils + amethyst pockets, 4 satellite islets, rune ring; `upgradeToV3` migration entry; ring-2 islet companion anchors added to `orbitalAnchors`. |
| `worldgen/structure/AltarSanctumBuilder.java` | edit | `ensureSanctum` revision gate: floating island with `revision() < REVISION_ISLAND_V3` runs `upgradeToV3` once, then stamps the revision terminal. |
| `worldgen/structure/SanctumCrater.java` | edit | `dressTerraces`: two layered slab terrace bands (r 9.6–10.4, 11.0–11.8) on the bowl rim, south walk sector kept clear. |
| `worldgen/structure/SanctumOrbitals.java` | edit | Level-scaled debris rings (+0.35 r / +8 % bob per altar level, cap 5) on rings 0/1; ring-2 islet companion shards animate through the existing pass with fixed tight orbits. |
| `worldgen/structure/SanctumVersionData.java` | edit | New `revision` counter (`REVISION_NONE`/`REVISION_ISLAND_V3`) + NBT tag — `version()` stays FROZEN for `IntroSequence`'s exact-equality checks. |
| `movement/EdgeGlideService.java` + `package-info.java` | NEW | IDEA-04 #1 end-to-end: down-glide + up-glide server brain (details below), `isGliding` query for `SoftLandingFx`. |
| `movement/SoftLandingFx.java` | NEW | IDEA-04 #4: one game-bus subscriber marking every protected landing (glide / breach / border / bounce) with a block-dust ring + muffled wool thud. |
| `ritual/AltarBlockEntity.java` | edit | `handleOffering`: swallow payload before the beam + offerer-only pitch tell; `completeMilestone`: `ALTAR_LEVELUP_RING` payload next to the beam. |
| `offering/OfferingService.java` | edit | `acceptWithValue` overload returning the secret exact value (`accept` delegates — gametest behavior byte-identical). |
| `network/S2CQuasarPayload.java` | edit | `ALTAR_LEVELUP_RING`, `OFFERING_SWALLOW` ids + `offeringSwallow(item)` / `offeringSwallowItem(emitterId)` — the offered item rides the emitter-id path (`offering_swallow/<ns>/<path>`), no new payload shape. |
| `network/EclipsePayloads.java` | edit | One seam in `handleQuasar`: `OfferingSwallowFx.intercept` consumes swallow ids and (while a flight is live) holds matching `ALTAR_BEAM`s; everything else flows to `spawnOrFallback` unchanged. |
| `client/drama/OfferingSwallowFx.java` | NEW | Offering spiral: item billboard hand → altar over 32 t (shrink to zero), trail emitter dragged along, beam held until arrival (arrival-beat sync), `reducedFx`/no-anchor/no-Quasar fallbacks. |
| `client/drama/AltarIdleMotes.java` | edit | `MAX_LIVE` → `maxLive()`: 3 + `ClientStateCache.altarLevel`, capped 6 — the idle window thickens permanently per level. |
| `client/sanctum/SanctumLightfall.java` + `package-info.java` | NEW | Waterfall-of-light + crater updraft: two looping managed emitters keyed on `ALTAR_CENTER`, physical floating-gate probe (details below). |
| `assets/eclipse/quasar/emitters/offering_swallow.json`, `altar_levelup_ring.json`, `sanctum_lightfall.json`, `crater_updraft.json` | NEW | Emitters (no `veil:light` anywhere). The ring uses `veil:point_force` — codec field names verified from the Veil 4.3.0 jar (`point`, `localPoint`, `range`, `strength`; positive strength pushes AWAY = true radial expansion). |
| `assets/eclipse/lang/en_us.json`, `de_de.json` | edit | 2 keys: `movement.eclipse.glide.lift` / `.soften` (en+de, alphabetical slots). Langdrop mirror: `docs/plans_v3/langdrop/W4-ISLAND.json`. |

## Versioning / migration (how v2→v3 adopts)

`version()` is left FROZEN at `VERSION_FLOATING` — `IntroSequence` compares it with `==`,
so bumping to a "3" would silently kill the intro/anchor re-sync paths. Instead
`SanctumVersionData` grew a second `revision` counter (old saves load as
`REVISION_NONE`): `ensureSanctum`'s terminal branch now checks `floating &&
revision() < REVISION_ISLAND_V3` → `FloatingSanctumBuilder.upgradeToV3` (ONLY the
additive `dressV3`, no clears/airspace sweeps — lived-in worlds keep every player
block) → stamp. Fresh builds run `dressV3` inline in `buildOrUpgrade` and stamp both.
Everything in the dress pass is deterministic (`FallbackBuilders.hash01` only) and
idempotent (fixed positions, plain `setBlock`) — a re-run is a no-op visually.

## What the island looks like now

- **Underside**: between the v2 torn roots/chains, hash-scattered glow-berry cave-vine
  tendrils (2–5 long, lit berries) and inset amethyst pockets (block + down-facing
  cluster) hang from the belly; the central d<0.30 core is kept clear — that is where the
  **waterfall of light** (client `sanctum_lightfall` emitter, pale-gold→violet streaks)
  pours ~9 blocks below the belly down into the crater bowl.
- **Around the rim**: four small hash-carved islets (deepslate/blackstone/tuff, lawn cap,
  up-facing amethyst glint, hanging root) float at r 23–26 / 6–10 above ground — placed
  between the SSE bridge (72–85°), the glide notches (45/135/225/315°) and outside the
  crater rim. Each has a ring-2 companion debris shard tightly arcing around it (the
  "connecting particle-arc" is the shard's Veil-culled display trail — anchors ride the
  frozen `orbitalAnchors` list so `SanctumOrbitals` needed no new spawn path).
- **On top**: a 16-tile rune ring (alternating glowstone / crying obsidian — the gold→
  violet milestone identity) inlaid flush in the lawn on the r≈6.5 band, strictly outside
  the dais slab skirt (r ≤ 6) and inside the sundial shadow band (r 7–10) so neither ever
  stamps over it.
- **Crater**: two slab terrace bands (polished blackstone / blackstone / cobbled
  deepslate) layer the bowl rim into stepped strata; faint violet updraft motes
  (client `crater_updraft`) breathe up out of the bowl.
- **Alive**: debris rings widen and bob deeper per altar level (server), the altar idle
  motes window deepens per level (client) — the island visibly "levels up" with the run.

## Edge-glide (IDEA-04 #1 + auto-up-glide)

`movement/EdgeGlideService` (game bus, `ContainmentService` pattern, statics reset on
`ServerStoppedEvent`): survival/adventure players in the overworld, near a cached
`glideLedges` column (r ≤ 2.5) and inside `SpawnProtectionRules.isInFallSafeZone`:

- **Down-glide**: airborne, vy < −0.10 → vy damped to ≥ −0.18/t, horizontal speed
  clamped to 0.30 (`setDeltaMovement` + `hurtMarked` sync pattern), `fallDistance`
  zeroed. Never a fling: the clamp only ever *reduces* horizontal velocity.
- **Up-glide**: standing below a notch, looking up (pitch ≤ −45°), jumping → gentle lift
  (+0.10/t, cap 0.42) with a soft centering pull onto the column; cresting the lip hands
  a small inward nudge onto the lawn. Sneak cancels; water/vehicle/elytra never enter.
- FX: `FxPayloads.sendFxEvent(FX_GLIDE_START/STOP, r 64)` — the existing client handler
  attaches/detaches the `glide_trail` emitter; no client code was touched. Ledge cache
  refreshes every 100 t (catches the live stage flip); one action-bar hint per mode per
  session (en+de).

## Altar ceremony (IDEA-12 top 3)

1. **Swallow**: `handleOffering` sends `offering_swallow/<item-id>` at the captured hand
   position, THEN the beam (same connection ⇒ ordered). Client: item billboard spirals
   hand → `ALTAR_CENTER`+0.9 over 32 t (ease-in-out, 2 turns, radius zero at both ends),
   shrinking to zero, trail emitter dragged along; a matching `ALTAR_BEAM` (within 4
   blocks of a live flight target) is held and released the tick the item vanishes (+2 t
   pad) — the column erupts exactly on arrival. Unrelated beams (revive ritual etc.)
   pass through. `reducedFx`/missing anchor → plain burst at the hand, beam immediate;
   flights hard-capped at 4.
2. **Chime tell**: `acceptWithValue` returns the exact value; the OFFERER hears
   `OFFERING_ACCEPT` at bucket pitch 0.85 (≤5) / 1.0 (≤40) / 1.15 (>40) ± 0.03 jitter;
   bystanders keep the neutral 1.0 cue. No text, no numbers — ear-training only,
   deniable by design.
3. **Level-up**: `completeMilestone` adds the `ALTAR_LEVELUP_RING` payload (gold→violet
   `point_force` radial bloom) beside the existing beam; the PERMANENT tells ride the
   already-synced `altarLevel`: `AltarIdleMotes` window 3→6 and the `SanctumOrbitals`
   radius/bob growth (cap 5 keeps r ≤ ~14.8, inside the display-entity scan margin).

## Universal soft landing (IDEA-04 #4)

`movement/SoftLandingFx`: tracks falling players (entry vy < −0.20); a fall is
"shielded" once `ContainmentService.hasFallImmunity` OR Slow Falling OR
`EdgeGlideService.isGliding` is observed on any airborne tick. On touchdown, shielded
falls that peaked ≥ 0.45 b/t **or** lasted ≥ 12 t (the duration clause admits the damped
glides) emit a 12-particle `BLOCK` dust ring of the supporting block + `WOOL_STEP` at
pitch 0.7, volume scaled by peak fall speed. Server-side `sendParticles` ⇒ bystanders
see it; zero allocation until a real fall starts; map cleared on logout/stop.

## SanctumLightfall floating gate (read before touching)

The `ALTAR_CENTER` anchor is synced at R10 t=500 while the altar is still GROUNDED — a
naive lightfall would render underground. Gate: the block 15 below the anchor
(`ALTAR_ABOVE_GROUND + ISLAND_LIFT − 3`, inside the island/ground air gap, below the
deepest belly ≈ −13, above the ground datum −18) must be in a loaded chunk AND air —
true only once the island actually floats. All offsets derive from the published
builder constants, so client FX and server geometry cannot drift apart.

## Verification performed (no gradle, per rules)

- All 14 touched/new java files compile via the repo's `javac --release 21 -sourcepath`
  harness against the NeoForge 21.1.238 merged jar + Veil 4.3.0 classpath — exit 0;
  `-Xlint:deprecation,removal` clean for owned files (one `hasChunkAt` deprecation found
  and replaced with `hasChunk(sectionX, sectionZ)`).
- All 4 emitter JSONs + both lang JSONs parse (`python3 -m json.tool`).
- `veil:point_force` semantics verified from bytecode (Veil 4.3.0 jar): codec fields
  `point`/`localPoint`/`range`/`strength`; `applyForce` does
  `velocity.sub((point − particle).normalize(strength))` ⇒ positive strength pushes
  away — the ring genuinely expands.
- Rune ring cells re-checked against `SundialPlaza` (shadow band r 7–10 erase contract)
  and the dais skirt (r ≤ 6): all 16 cells have r² ∈ [37, 47].
- NOT done: `runClient`/`runServer` smoke (forbidden this pass) — visuals (emitter
  tuning values, spiral feel) and the glide feel need one integrator boot.

## Integrator asks

1. Merge `docs/plans_v3/langdrop/W4-ISLAND.json` via `tools/langmerge` if the direct
   lang edits are dropped in favor of a batch merge (both are in this branch; keys are
   identical).
2. Smoke boot on an EXISTING v2 floating save: expect one
   `Sanctum island upgraded v2 -> geometry v3 …` log line, then terminal boots log
   `Sanctum v2 (rev 3) present … zero block changes`.
3. Feel-check the glide (never a fling — horizontal is only ever clamped down) and the
   up-glide look-up gesture threshold (−45°); both constants are top-of-file.
4. Emitter tuning to taste: `point_force.strength` 3.0 (ring bloom speed),
   `sanctum_lightfall` initial_velocity 4.5 (column length ≈ 10 blocks).

## Risks

- **Islet overlap**: islets place unconditionally (no airspace clears — deliberately, so
  the migration can't eat player builds). On a heavily built-up save an islet can
  interlock with a player structure; it reads as torn debris, and every position is
  deterministic if a manual cleanup is ever needed.
- **Ring-2 culling**: companion shards mount on the shared altar-column display carrier;
  if the carrier is frustum-culled while an islet is on-screen the shard blinks out.
  Accepted (matches the existing rings' behavior; keeps the W5 entity budget at one
  carrier).
- **Held-beam edge case**: if a player disconnects mid-swallow the held beam dies with
  the flight (LoggingOut clear) — the beam is cosmetic-only, server truth unaffected.
- **`WOOL_STEP` at volume ≥ 0.35 on every protected landing** could feel spammy around
  the bounce ceiling during day-1 chaos; the trivial-hop filter (≥ 0.45 b/t or ≥ 12 t)
  bounds it, and the constants sit top-of-file for tuning.
- **Pitch-tell metagame**: 3 buckets ± jitter leak coarse value tiers to the offerer by
  design (user-approved secret tell); bystanders provably hear the fixed 1.0 cue.
