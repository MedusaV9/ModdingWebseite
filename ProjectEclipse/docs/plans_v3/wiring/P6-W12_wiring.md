# P6-W12 wiring notes — Player Skin v2 + emissive layer + The Other sync + Ghost renderer

**Zero hub edits.** No `EclipseMod`, `EclipsePayloads`, `EclipseEntityRenderers`,
`EclipseCommands`, lang JSON or `build.gradle` changes. Everything W12 landed
self-registers via `@EventBusSubscriber` classes:

- `client/entity/player/PlayerLayerHandler` — `EntityRenderersEvent.AddLayers` (mod bus,
  auto-routed) attaches `EclipsedPlayerGlowLayer` to both player renderers.
- `client/entity/ghost/GhostRenderers` — `EntityRenderersEvent.RegisterRenderers` (mod
  bus) + nested `RevealTicker` (`ClientTickEvent.Post` / `LoggingOut`, game bus).

## Integrator / sibling notes

1. **Ghost renderer is lookup-guarded, no action needed.** `GhostRenderers` registers
   `GhostPlayerRenderer` for `eclipse:logout_ghost` only if
   `BuiltInRegistries.ENTITY_TYPE.containsKey(...)` at `RegisterRenderers` time. P4-B9's
   entity type was absent from the tree at W12 compile time — boot logs
   `"eclipse:logout_ghost not registered (P4-B9 not merged yet)"` until it lands, then
   flips to `"ghost renderer registered"` with zero code changes. **Hard requirement on
   the entity class: it must extend `LivingEntity`** (`Mob` is fine) — the renderer is
   typed against `LivingEntity` per the frozen contract. Full contract + test steps:
   `docs/plans_v3/handoff/P6_ghost_renderer.md`.
2. **Entity id followed: `eclipse:logout_ghost`** (P4 plan §2.12, frozen) — supersedes the
   older `eclipse:ghost_player` draft id in P6 plan §2.7/§4.4. Renderer class names keep
   the §3 matrix names (`GhostPlayerRenderer`/`GhostRenderers`).
3. **`ClientStateCache.ghostReveal*` mailbox is consumed at runtime** (no file edit):
   `GhostRenderers.RevealTicker` copies `ghostRevealEntityId/OwnerName/Ticks` into its
   per-entity countdown map once per client tick and then resets the three fields to their
   `resetToDefaults()` values (`-1` / `""` / `0`) so an identical later payload (same ghost
   re-hit after the server's 5 s rate limit) re-triggers. If P3 ever wants a HUD-side
   reveal treatment, read `GhostRenderers.activeReveal(entityId)` instead of the raw
   mailbox fields (they are now transient).
4. **`scripts/placeholder_gen/EntitySkinArtist.writeTheOther()` is stale**: it derives
   `the_other.png` from `uniform_skin.png`, which no longer exists (the shipped skin path
   is `eclipsed_player.png`), so running that generator today would crash in
   `writeTheOther`. `the_other.png` is now regenerated (same two frozen deltas, same
   coordinates/colors) by `scripts/skin_gen/eclipsed_player_v2.py`. W12 does not own
   `EntitySkinArtist.java` — its owner should delete/guard `writeTheOther()` in a future
   pass.
5. **P2 hooks unchanged**: the reveal-burst particles (`eclipse:glitch_pop`) and any Veil
   bloom on the player heart are P2's additive layers (P6 plan §4.2); no W12 code change
   is needed when they land. Only `border_glitch` exists in `quasar/emitters/` today.
6. **Texture replacement contract**: `eclipsed_player.png`, `the_other.png`,
   `eclipsed_player_glow.png` are all 64×64 wide-arm layout, byte-for-byte replaceable by
   final AI art at the same paths/sizes. The glow PNG must keep glow pixels ONLY where
   things should be fullbright (alpha-graded; transparent elsewhere), and `the_other.png`
   must keep the two doppelganger deltas (pure-black 2×2 eyes at face cols 1-2/5-6 rows
   11-12; `#8367A8` seam down face col 3 rows 8-15, both skin layers).

## Langdrop

`docs/plans_v3/langdrop/P6-W12.json` — **0 keys** (empty en/de maps, file kept per
convention). The reveal nametag deliberately shows the raw player name (the one sanctioned
name leak, P4 §2.12); everything else W12 renders is non-textual.
