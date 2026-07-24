# P2-W3 wiring notes — Limbo overhaul (R5 + R4-limbo)

Zero hub edits: no `EclipseMod` / `EclipsePayloads` / `EclipseCommands` / `FxPayloads` /
lang / sounds / config changes. Everything W3 shipped lives in W3-owned files
(`client/sky/LimboSpecialEffects.java`, `veilfx/LimboAmbience.java`, the `eclipse:limbo`
shader program, and the `limbo_godray` / `limbo_fog` / `limbo_motes` emitters). Langdrop
`P2-W3.json` is empty — no user-visible strings in this package.

## What W3 landed

- **`eclipse:limbo` post row migrated to `VeilPostController.register(...)`** (from
  `LimboAmbience`'s static init, GRADE priority). Per the P2-W1 wiring contract this
  REPLACES W1's backward-compat `Intensity`-only row regardless of class-load order.
  The v2 feeder supplies the frozen §3.3 uniforms: `Intensity` (~2 s eased fade after
  entering limbo, v1 curve), `GodrayDir` (vec2, see below), `CausticsAmount`, `Time`.
- **Zenith source of truth**: `LimboSpecialEffects.zenithWorldPoint(ClientLevel)`
  (public static) — the point 480 blocks above the ship-deck anchor that BOTH the
  sky-pass disc/aura and the post god-rays aim at. Sibling FX that want to point at the
  limbo eclipse should read this instead of re-deriving it.
- **Limbo ambience windows**: three rolling windows of looping emitters around the
  camera (`limbo_motes` ×4, `limbo_godray` ×3, `limbo_fog` ×2 live), all charged to
  `FxBudget.Channel.AMBIENT`, cadence doubled under `reducedFx`.
- **`LimboSpecialEffects` now overrides `renderClouds` → handled/empty** (R4-limbo).

## Notes for W1 (owner of `veilfx/VeilPostController.java`)

- The backward-compat `eclipse:limbo` default row (plus its `limboEnterMillis` /
  `feedLimbo` / `wantLimbo` / `limboIntensity` bookkeeping) is now dead weight: W3's
  registered row wins the `ROWS` slot. Safe to delete on your next pass — W3 did not
  touch your file. Nothing else in W3 shadows controller state.

## Notes for P6 (ship / limbo crew / ship rebuild — P6-W3 this wave)

- **Please publish `FxAnchors.set(FxAnchors.SHIP_DECK, limboLevel, deckCenterPos)`**
  when the ghost ship is (re)built. The limbo eclipse + aura is drawn toward the point
  480 blocks above that anchor, and the god-ray post effect radiates from the same
  point, so setting the anchor makes the eclipse sit EXACTLY over the new ship no
  matter where the rebuild places it. Until the anchor is set, W3 falls back to the
  shared spawn pos (which sits at the ship's x/z in the shipped limbo setup, so the
  fallback is already ship-accurate today).
- The anchor is assumed to be limbo-space; the client cache is not dimension-keyed
  (W1 design), and W3 only reads it while the local level IS limbo.

## Cross-worker file boundaries respected

- `limbo/GhostShipBuilder.java` + `limbo/LimboSeascape.java` (P6-W3's this wave): not
  touched, not referenced — the spawn fallback reads `level.getSharedSpawnPos()` only.
- `pinwheel/post/limbo.json` and `pinwheel/shaders/program/limbo.json` are byte-identical
  to v1 (single `veil:blit` stage into `veil:post`, program vertex `veil:blit_screen`) —
  the v2 work is entirely inside `limbo.fsh`. Both stay W3-owned.
