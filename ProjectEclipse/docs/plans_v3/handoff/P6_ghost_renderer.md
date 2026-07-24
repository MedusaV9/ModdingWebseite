# P6-W12 → P4-B9 handoff — logout-ghost renderer (`eclipse:logout_ghost`)

**Status: the client side is COMMITTED and live** — this is an upgrade over P6 plan
§2.7's "handoff doc with a code block" fallback. Because the renderer is typed against
`LivingEntity` (not the concrete entity class), it registers by registry lookup and the
build stays green whether or not the entity exists yet:

- `client/entity/ghost/GhostPlayerRenderer` — the renderer (player model, v2 eclipsed
  skin, ~40% alpha translucent, +2px hover bob, glitch jitter, no shadow, no vanilla
  nameplate, payload-driven glitch name reveal via `GlitchText`).
- `client/entity/ghost/GhostRenderers` — `RegisterRenderers` subscriber:
  `BuiltInRegistries.ENTITY_TYPE.containsKey(eclipse:logout_ghost)` → register, else log +
  skip (`containsKey`, not `getOptional` — ENTITY_TYPE is a defaulted registry). Also owns
  the client reveal cache (see "Reveal flow").

**The moment P4-B9's entity registration merges, the ghost renders — no code change on
either side.**

## Contract the entity class MUST satisfy (frozen, P4 plan §2.12)

| Requirement | Why |
|---|---|
| Entity type id `eclipse:logout_ghost` | `GhostRenderers` looks this exact id up |
| Class `extends LivingEntity` (a `Mob` subclass is fine) | renderer is `LivingEntityRenderer<LivingEntity, PlayerModel<LivingEntity>>`; a non-living Entity would `ClassCastException` at render time |
| Humanoid-sized (~0.6×1.8), `clientTrackingRange` ~10 | player-model proportions + reveal broadcast radius (32) inside tracking range |
| Attributes registered (`EntityAttributeCreationEvent`; `Mob.createMobAttributes()` suffices) | every LivingEntity type needs an attribute supplier or the client/server crash on spawn |
| `hurt()` → `LogoutGhostService.onGhostHurt(ghost, attacker)`, damage refused | reveal trigger (server-side; rate-limit + payload live in the service) |
| 100t self-check `LogoutGhostService.isValid(ghost)` | orphan cleanup per §2.12 |
| `OWNER_NAME` stays server-side NBT only | the name must travel ONLY in `S2CGhostRevealPayload` (anonymity) |
| synced `REVEAL_TICKS` optional for the client | the renderer times the reveal from the payload alone (see below) — keep the field for server bookkeeping if convenient, the renderer never reads it |

## Reveal flow (already wired end-to-end on the client)

1. Server (P4-B9): `onGhostHurt` → rate limit →
   `S2CGhostRevealPayload(ghost.getId(), ownerName, 60)` to players within 32 blocks.
2. `EclipsePayloads.handleGhostReveal` (hub, pre-existing) writes the
   `ClientStateCache.ghostReveal*` mailbox fields.
3. `GhostRenderers.RevealTicker` (client tick) ingests the mailbox into an
   `entityId → Reveal(ownerName, startMillis, totalTicks)` map, **then resets the mailbox
   to defaults** so identical repeat payloads re-trigger. Map pruned each tick, cleared on
   logout.
4. `GhostPlayerRenderer` renders, while a reveal is active: body alpha flicker
   (~0.18–0.65), stronger jitter, and a nametag that resolves from `GlitchText.scramble`
   glyphs (color `#8367A8`) left-to-right into the owner name (color `#E7D6FF`) across the
   middle 60% of the window, with brief full re-scramble pops. `reducedFx` calms the
   scramble automatically (GlitchText behavior).

Known corner (inherent to the hub's single-slot mailbox, not fixable from W12-owned
files): if TWO different ghosts get reveal payloads inside the same client tick, only the
last one shows (the mailbox holds one entry). Server-side rate limiting makes this
near-impossible in practice; if it ever matters, P4 can stagger the second broadcast by a
tick or the integrator can turn the mailbox into a queue inside `handleGhostReveal`.

## Visual spec implemented (for review against the sheet)

`RenderType.entityTranslucent(eclipsed_player.png)`, whole-model alpha 0.40 (plan quotes
~0.45/~40% — tune `GhostPlayerRenderer.BASE_ALPHA`), hover +2px + `sin(t·0.05)·0.035`
bob, deterministic whole-model micro-jitter (~19% of 3-tick windows, ±0.5px; every window
±1px during reveal), shadow radius 0, `shouldShowName` = false always.

**WB-GHOSTFX update:** the bob now rides on a slower ±0.05-block drift sine (~15 s,
per-entity phase), idle alpha shimmers 0.40 ± 0.04 (steady under `reducedFx`), and a
nested `HeartGlowLayer` re-renders the model over `eclipsed_player_glow.png` with
`RenderType.eyes` (alpha breathing 0.60–0.82 on the skin's ~2 s heartbeat) so the purple
heart stays visible through the translucency at night. Contract, reveal flow and entity
requirements are unchanged (see `docs/plans_v3/wiring/WB-GHOSTFX_wiring.md`).

## Testing once the entity lands

1. Boot client into a world. Log check: `ghost renderer registered for eclipse:logout_ghost`.
2. Spawn: log a second account out (or `/summon eclipse:logout_ghost` if spawn data allows)
   → translucent purple-mythic figure hovering/bobbing, no nameplate, no shadow.
3. Hit it → glitchy nametag scrambles then resolves to the owner name for ~3 s, body
   flickers; re-hit ≥5 s later → repeats. `/eclipsefx`-independent (no Veil requirement).
4. Dedicated-server parity: all W12 classes are `Dist.CLIENT`-gated `@EventBusSubscriber`s
   — nothing loads server-side.

P2 later layers `eclipse:glitch_pop` particles + shimmer on the same trigger (P6 §4.2);
no renderer change needed.
