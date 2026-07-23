# P6-W56 wiring — Sanctum Orbitals + Spawn Gates + Bestiary Data

## What shipped

| File | What it is |
|---|---|
| `worldgen/structure/SanctumOrbitals.java` | Rotating-debris ring around the floating sanctum: 12 persistent `Display.BlockDisplay` on two counter-rotating rings (W4's `FloatingSanctumBuilder.orbitalAnchors` data), orbit + per-fragment tumble + bob via interpolated `setTransformation` pushes (40 t cadence == interpolation duration — zero jitter, 0.3 packets/s per display), player-presence gate (96 blocks; zero packets/scans when nobody near), tag-based reconcile (adopt/dedupe/respawn) on boot/flip/periodically. |
| `entity/spawn/SpawnGates.java` | The pluggable area-gate seam: `FOG_STORM` / `NEW_RING` / `PALE_GARDEN` volatile `Gate` predicates with live in-tree defaults (`FogStormSites.sites()` radius test, `NewRingRegistry.isFreshRing`, baked `eclipse:pale_garden` biome). P1 upgrades precision with a single assignment. |
| `entity/spawn/EventSpawnRules.java` | 100 t spawner pass (phase-offset 50 t from legacy `EclipseSpawner`): fog_revenant / storm_hound packs / rare fog_colossus in active storm sites (night, day ≥ 6/9), glitched trio in fresh rings (day ≥ 8, night-biased caps, HUSK 45 / HOUND 35 / TICK 20, ticks in threes), pale_sentinel in the pale garden (night, day ≥ 10, cap 2), drift_lantern lane maintenance in limbo (top-up toward 8 via `DriftLanternEntity.spawnLane` — its first caller). All ids resolved from frozen strings at spawn time; absent → logged-once no-op. Peaceful early-out; NON-persistent `MobSpawnType.NATURAL` spawns (vanilla despawn). |
| `entity/spawn/package-info.java` | Package doc. |
| `docs/plans_v3/langdrop/P6-W56.json` | `bestiary.eclipse.<id>.name`/`.lore` for ALL 11 frozen ids, en+de. |
| `docs/plans_v3/handoff/P6_bestiary_entries.md` | id / names / 1-line lore / intro day / danger tier / silhouette notes for P3's BestiaryTab rework. |
| `docs/plans_v3/handoff/P6_dungeon_spawners.md` | Copy-pasteable `dungeons.json` arrays + per-mob spawner NBT tuning for the DungeonSpawners integrator. |

No `EclipseMod.java` wiring needed — both event classes are `@EventBusSubscriber`.

## Wiring asks (for other owners)

1. **`/dev` owner (devtools):** wire the orbitals dev hook — suggested subcommand
   `/dev display orbitals_rebuild` (or under `sanctum`), body:
   `SanctumOrbitals.rebuild(source.getServer().overworld()); return 1;`
   The hook wipes every `eclipse_sanctum_orbital`-tagged display and respawns the ring fresh;
   safe no-op while the sanctum is still grounded. (Same effect available today via
   `/kill @e[tag=eclipse_sanctum_orbital]` — reconcile self-heals within ~2 s when a player
   is near the altar.)
2. **Langdrop integrator:** merge `docs/plans_v3/langdrop/P6-W56.json`.
3. **P1 (optional, later):** replace gate defaults if sharper predicates land, e.g.
   `SpawnGates.FOG_STORM = FogStormService::isStormAt;` from a server-start hook. The fields
   are `volatile`; assignment is the whole integration.
4. **DungeonSpawners integrator:** apply `docs/plans_v3/handoff/P6_dungeon_spawners.md`
   (config-only; safe before mob families merge).
5. **P3 BestiaryTab worker:** consume `docs/plans_v3/handoff/P6_bestiary_entries.md`.

## Coordination notes

- **Glitched trio double-spawner:** P4's `glitch/GlitchSpawnService` (chance-per-sample bursts,
  own day/night/cap gates) also spawns `eclipse:glitched_husk/_hound/_tick` in fresh rings.
  Both spawners count the SAME live census (`level.getEntities(type, isAlive)`), so the live
  total never exceeds the larger cap; `EventSpawnRules` additionally spawns at most ONE group
  per 100 t pass. Ownership: GlitchSpawnService = event bursts, EventSpawnRules = ambient
  baseline. No code coupling between the two.
- **Frozen ids only:** the glitched family is three separate entity ids (matches
  `GlitchConfig` defaults), NOT `eclipse:glitched` + `Kind` NBT as older plan text says.
- **Accesstransformer dependency:** `SanctumOrbitals` uses the `Display` setters
  (`setTransformation`, `setTransformationInterpolationDelay/Duration`) opened in
  `META-INF/accesstransformer.cfg` — those lines are retained by P6-W4; do not remove.
- **DUNGEON spawn context is not code in this package** — it is the existing
  `DungeonSpawners` config seam (see handoff doc).

## Risks

- Most gated entities do not exist yet (parallel workers) — by design every lookup is
  `BuiltInRegistries.ENTITY_TYPE.getOptional` + skip; the only live effects today are
  drift_lantern lane maintenance and the orbitals ring.
- `Mob.finalizeSpawn` carries a NeoForge deprecation note (same usage as existing in-tree
  spawners, e.g. `GlitchSpawnService`); compiles clean, migrate all call sites together later.
- Orbital displays live in ONE fixed position (altar column chunk, spawn-chunk-loaded); if a
  future change moves the altar without a sanctum version flip, run the rebuild hook once.

## Test steps (runServer + RCON, AGENTS.md pattern)

1. **Orbitals:** new world → progress to the floating sanctum (or `/eclipse stage set` to the
   flip) → stand near the altar: 12 debris blocks orbit/tumble/bob smoothly.
   `/kill @e[tag=eclipse_sanctum_orbital]` → ring self-heals within ~2 s. Leave 96+ blocks →
   log/packet silence; return → motion resumes gliding (no snap). Restart server → no
   duplicates (count stays 12: `/execute if entity @e[tag=eclipse_sanctum_orbital]`).
2. **Glitch gates:** `/eclipse day set 8`, night → log lines `EventSpawnRules: eclipse:glitched_*
   x… in fresh ring …` only inside the newest ring band; `/eclipse day set 3` → zero spawns.
3. **Fog gates:** day ≥ 6, night, stand inside an active storm site → revenant/hound-pack log
   lines (packs announce with the private howl cue); nothing spawns outside sites; day ≥ 9 →
   at most one colossus worldwide.
4. **Caps:** idle 10 min at night → counts stay ≤ documented caps
   (`/execute if entity @e[type=eclipse:fog_revenant]` etc.).
5. **Lanterns:** `/eclipse tp_limbo` → within ~5 s lantern top-up logs; population settles in
   the 6–10 band and stays (they never despawn on their own).
