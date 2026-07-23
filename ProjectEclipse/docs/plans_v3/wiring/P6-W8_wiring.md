# P6-W8 wiring notes — Fog Colossus + GLITCHED family (husk/hound/tick)

**Two integrator lines**, both in the `EclipseMod` constructor next to the existing
family-registrar block (`AmbientEntities.register(...)` etc.):

```java
dev.projecteclipse.eclipse.entity.fog.FogEliteEntities.register(modEventBus);
dev.projecteclipse.eclipse.entity.glitch.GlitchEntities.register(modEventBus);
```

Until they land, everything W8 shipped is dormant-but-green: all four
`@EventBusSubscriber` classes (`FogEliteEntities`, `GlitchEntities`,
`FogEliteRenderers`, `GlitchRenderers`) no-op via `DeferredHolder.isBound()` and the
server halves log one `... registrar not wired yet` warning each. No
`EclipsePayloads`, lang JSON, `sounds.json`, gradle or shared-registry edits.

## What wires itself once the lines land

- **Entities:** `eclipse:fog_colossus` (MONSTER 1.6×3.4), `eclipse:glitched_husk`
  (0.6×1.9), `eclipse:glitched_hound` (0.9×1.2), `eclipse:glitched_tick` (0.6×0.5) —
  attributes + standard on-ground monster spawn placements included.
- **Glitch pipeline hooks (already in-tree, zero edits by W8):**
  `glitch/GlitchConfig.DEFAULT_ENTITY_IDS` names exactly these three glitched ids, so
  `GlitchSpawnService` starts populating fresh rings the moment the types resolve;
  `data/eclipse/tags/entity_type/glitched.json` already lists them, so
  `glitch/GlitchDrops` pays the 1–2 `eclipse:glitch_shard` per kill.
  **Deliberate consequence:** the W8 loot tables
  (`data/eclipse/loot_table/entities/glitched_*.json`) contain corrupted vanilla
  scraps ONLY — shards are the tag hook's job; listing them again would double-drop
  the heart economy input.
- **Renderers:** self-registered on `EntityRenderersEvent.RegisterRenderers`
  (annotation-discovered, client dist).
- **Lang:** `docs/plans_v3/langdrop/P6-W8.json` (4 entity name keys, en+de — German
  names match W6's bestiary langdrop exactly).

## Sibling coordination (W7 — same `entity/fog` + `client/entity/fog` packages)

- W8 touched NONE of W7's files (`FogEntities`, `FogRevenantEntity`,
  `FogBlindBurstGoal`, future `StormHound*`/`FogRenderers`); W8's fog files are
  `FogColossusEntity`, `FogEliteEntities`, `GroundSlamGoal`, `FogColossusRenderer`,
  `FogEliteRenderers` — separate registrar, separate subscriber, per plan §3-W8.
- `client/entity/fog/package-info.java` did not exist when W8 landed; per the plan
  §3-W8 rule ("W7 owns both package-info files; if W8 lands first it creates them
  with an owner note") W8 created it with the `// owner: P6-W7` header — W7 keeps and
  may rewrite it freely.

## Deviations from the plan sheet (with reasons)

1. **Separate entity classes/ids instead of one `eclipse:glitched` + KIND byte**
   (plan §2.3 draft): the task freeze and the already-shipped consumers
   (`GlitchConfig.DEFAULT_ENTITY_IDS`, `#eclipse:glitched` tag, W6's bestiary keys
   `bestiary.eclipse.glitched_husk/...`) all use the three split ids — the split-id
   scheme is what the rest of the tree is built against, so W8 followed it.
2. **Colossus `fog_essence` drops:** the item is P4-owned and not registered yet, so
   per the §2.3 fallback rule the loot table ships 3–5 `umbral_shard` (base 3 + the
   essence stand-in) + a 25% killed-by-player Mending book. When P4 lands
   `eclipse:fog_essence`, edit `loot_table/entities/fog_colossus.json`: shard count
   back to 3 and add the essence entry (note embedded in the JSON).
3. **Colossus slam screen-shake:** used the existing `S2CShakePayload.shake(...)`
   (`sendToPlayersNear`, r=24) — slam 0.5f/12t, death impact 0.6f/15t per sheet.
4. **`eclipse:glitch_pop` emitter** (P2, §4.2) not in-tree yet: blink/death FX use the
   sanctioned `REVERSE_PORTAL` + `WHITE_ASH` stand-ins, swap points marked in
   `GlitchedMonster` javadoc.

## Behavior contract (for the orchestrator's QA pass)

- `/summon eclipse:fog_colossus`: 80 HP slow tank; roars once on first aggro; inside
  5 blocks every ~200 t it roots, raises arms 27 t, then slams — r=6 shockwave, 8 dmg
  core with falloff past r=3 (airborne victims beyond r=3 are missed), launch +
  Slowness, smoke-ring + sonic-boom stamp + screen shake; scripted 50 t forward
  collapse with shake on impact frame.
- `/summon eclipse:glitched_husk`: shambles at 0.27; look away while targeted → +50%
  speed burst (drops the instant you look back); blinks 4 blocks every 200–280 t.
- `/summon eclipse:glitched_hound`: 0.35 chaser with pounce; blinks every 120–200 t
  mid-chase.
- `/summon eclipse:glitched_tick`: 0.42 mite; a landed bite latches — 1 dmg re-bite
  every 20 t while within 2 blocks (max 100 t), broken by hitting it back or
  distance; natural (spawn-service) spawns arrive in threes, spawner/summon spawns
  stay single.
- All four flicker client-side between `<id>.png` and `<id>_alt.png` (glitched trio)
  in 2–4 t bursts every 40–80 t with ≥ 12 t gaps (colossus does not flicker — only
  glitched mobs carry `_alt` textures).
