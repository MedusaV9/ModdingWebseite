# P6-W7 wiring — Fog Revenant + Storm Hound (fog-storm mob family, W7 half)

## The one wiring line (integrator)

`EclipseMod` constructor, next to the other entity registrars:

```java
dev.projecteclipse.eclipse.entity.fog.FogEntities.register(modEventBus);
```

That is the entire integration. Everything else is annotation-discovered:
attributes + spawn placements (`@EventBusSubscriber` inside `FogEntities`), renderers
(`client/entity/fog/FogRenderers`, client-event self-subscribed — same pattern as
`AmbientRenderers`). Until the line lands every listener no-ops via
`DeferredHolder.isBound()` (one warn log on attribute creation), so the build and both
run configs stay green with or without it.

## What shipped

| File | What it is |
|---|---|
| `entity/fog/FogEntities.java` | Family registrar (W7 half): `DeferredRegister<EntityType<?>>` with frozen ids `eclipse:fog_revenant` (MONSTER 0.7×2.2, eye 1.9) + `eclipse:storm_hound` (MONSTER 0.9×1.1, eye 0.8), attribute creation, standard on-ground monster spawn placements. |
| `entity/fog/FogRevenantEntity.java` | Tall hovering wraith, 30 HP / dmg 5 / speed 0.26 / kb-res 0.4. Hover-drift movement (capped fall speed −0.06, no fall damage, short-leash `DriftStrollGoal`), phantom voice pitched down, 40 t scripted death (disperses upward into wisps, then POOF). |
| `entity/fog/FogBlindBurstGoal.java` | The signature ability: 240–320 t cooldown, target ≤ 6 blocks + LOS → 30 t rooted channel (`cast_blind` anim + warden-charge cue + converging particles) → r=5 pulse: Blindness 4 s + Slowness II 3 s on players, `S2CQuasarPayload` `BOSS_SLAM` burst + vanilla CLOUD/SCULK_SOUL ring fallback, elder-guardian-curse sting. |
| `entity/fog/StormHoundEntity.java` | Charged pack hunter, 24 HP / dmg 4 / speed 0.34. Wolf voice pitched down, ambient `ELECTRIC_SPARK` crackle, pack aggro (`HurtByTargetGoal.setAlertOthers`), 30 t scripted side-collapse death. |
| `entity/fog/ChargedLungeGoal.java` | The signature ability: 160 t cooldown, target 6–14 blocks + LOS → 20 t rooted windup (`charge_windup` anim, spine sparks) → 12-block dash at 0.9 b/t with spark trail (`lunge` anim, riptide woosh) → hit: 6 dmg + Slowness IV 1 s (trident-thunder crack); miss/wall: 2 s self-stagger (whine + discharge smoke) — the player's counter-window. |
| `client/entity/fog/FogRenderers.java` | `EntityRenderersEvent.RegisterRenderers` self-subscriber (both renderers), `isBound()`-guarded. |
| `client/entity/fog/FogRevenantRenderer.java` / `StormHoundRenderer.java` | `EclipseGeoRenderer` subclasses: head tracking + glowmask layer + `withUprightDeath()` (both deaths are keyframed; vanilla tip-over suppressed). |
| `assets/eclipse/geo/entity/fog_revenant.geo.json` | 16-bone wraith: hooded skull (open hood front), 2-segment cascading robe skirt, long claw arms, shoulder fog-coral growth, 3 orbiting glow-wisps. Validated (`validate_geo.py`), zero UV overlaps. |
| `assets/eclipse/geo/entity/storm_hound.geo.json` | 18-bone quadruped: split jaw, swept horn antenna, 3 lightning-rod spine shards, 4 two-segment legs, 2-segment whip tail. Validated, zero UV overlaps. |
| `assets/eclipse/animations/entity/{fog_revenant,storm_hound}.animation.json` | Full sets — revenant: idle / walk / attack / cast_blind / death; hound: idle / walk / attack / charge_windup / lunge / death. Smooth-easing keyframes + molang sine layers; one-shots fired via the `action` controller triggers (deckhand pattern). |
| `scripts/geckolib_gen/mobs/{fog_revenant,storm_hound}.py` | Deterministic painters (paint_lib) → `textures/entity/<id>.png` + `<id>_glowmask.png`, 64×64 each. |
| `data/eclipse/loot_table/entities/{fog_revenant,storm_hound}.json` | Default-id entity loot (no code wiring): revenant = phantom membrane + 1–2 umbral shard + 25 % player-kill prismarine crystals ("fog-coral"); hound = bones + 0–2 umbral shard + 25 % player-kill glow ink sac ("storm gland"). Looting scales counts/chances. |
| `docs/uv/{fog_revenant,storm_hound}.md` | UV layout + art brief + regen commands. |
| `docs/plans_v3/langdrop/P6-W7.json` | `entity.eclipse.fog_revenant` / `entity.eclipse.storm_hound`, en+de (names match W56's bestiary de names). |

## Wiring asks (for other owners)

1. **Integrator:** apply the one-liner above; merge `docs/plans_v3/langdrop/P6-W7.json`.
2. **P2/VFX owner (optional, later):** `FogBlindBurstGoal.burst()` fires emitter
   `S2CQuasarPayload` id `BOSS_SLAM` as a stand-in; when a bespoke `eclipse:fog_burst`
   Quasar emitter lands, swap the constant at the single call site (marked with a
   comment). Vanilla-particle fallback already reads fine without Veil.

## Coordination notes

- **W8 (Fog Colossus)** creates SEPARATE `FogEliteEntities` / `FogEliteRenderers` files —
  nothing here references them; no merge conflicts by construction.
- **Natural spawning is P6-W56's `EventSpawnRules`** (storm-site gating, day ≥ 6, packs).
  It resolves the frozen ids from the registry at runtime, so spawns go live the moment
  the wiring line lands — zero coupling. The placements registered here only gate
  dungeon spawners / vanilla-style placement (standard monster rules).
- **Goal-flag safety:** `FogBlindBurstGoal` and `ChargedLungeGoal` claim
  `MOVE | LOOK | JUMP` (lunge) so `MeleeAttackGoal` / `LeapAtTargetGoal` back off during
  channels and dashes; both goals also `requiresUpdateEveryTick()`.
- **Sounds are vanilla events re-pitched** (phantom/wolf/warden/trident families) — no
  `sounds.json` edits, per the freeze.

## Risks

- Both mobs are invisible in-game until the one-liner lands (intended dormancy).
- `BOSS_SLAM` stand-in reads as a generic radial burst under Veil; acceptable until
  `eclipse:fog_burst` ships (ask #2).
- The hound's dash collision check is a simple expanding-AABB sweep per tick at
  0.9 b/t — fast targets strafing through the path edge can be missed; that's the
  designed dodge, not a bug, but tune `DASH_SPEED`/AABB inflation if QA wants it
  stickier.
- Loot: `eclipse:umbral_shard` is P4-owned; if P4 ever renames it the two loot tables
  need the same one-word edit (vanilla logs a table-load error, mobs still die clean).

## Test steps (runServer + RCON, AGENTS.md pattern)

1. `/summon eclipse:fog_revenant` → tall hooded wraith hovers with orbiting cyan wisps
   (glow in darkness), drifts short distances, descends slowly off ledges, no fall
   damage. Close to ≤ 6 blocks → it roots, wisps flare (cast anim), ~1.5 s later r=5
   pulse: Blindness + Slowness + fog ring. Kill it → it folds and streams UPWARD into
   wisps over 2 s, drops membrane/shards.
2. `/summon eclipse:storm_hound` ×2–3 → lean charcoal quadrupeds, spine shards + flank
   veins glow. Hit one → all aggro. Stand 6–14 blocks away → one crouches sparking
   (~1 s), then dashes ~12 blocks with a spark trail: hit = 6 dmg + heavy slow; sidestep
   = it tumbles past and staggers ~2 s (whine + smoke). Death = side collapse, bones/
   shards/rare glow ink.
3. `/kill` both while watching F3 → no errors; loot tables resolve (`/loot give @p loot
   eclipse:entities/fog_revenant`).
