# P6-W910 wiring — Pale Sentinel + Eclipse Cultist/Shadow Bolt + Rift Warden (W9+W10)

## The three wiring lines (integrator)

`EclipseMod` constructor, next to the other entity registrars:

```java
dev.projecteclipse.eclipse.entity.pale.PaleEntities.register(modEventBus);
dev.projecteclipse.eclipse.entity.dungeon.DungeonEntities.register(modEventBus);
dev.projecteclipse.eclipse.entity.boss.rift.RiftEntities.register(modEventBus);
```

That is the entire integration. Everything else is annotation-discovered: attributes
(`@EventBusSubscriber` inside each registrar), renderers (`client/entity/{pale,dungeon,
rift}/*Renderers`, client-event self-subscribed — `FogRenderers` pattern). Until a line
lands its family no-ops via `DeferredHolder.isBound()` guards, so the build and both run
configs stay green with any subset applied.

## Vault boss-room summon seam (P1)

`rift_warden` is **NOT a spawner mob** — nothing in `DungeonSpawners` references it.
The Collapsed Vault's boss room places it through the dedicated seam:

```java
RiftWardenEntity.summonAt(serverLevel, arenaCenterBlockPos);
```

(`entity/boss/rift/RiftWardenEntity#summonAt` — finalizes spawn, pins the r=12 arena at
that position via `RiftAnchor`, snapshots player-count HP scaling, returns the entity or
null if the type isn't bound yet.) Alternatively P1 can `/summon eclipse:rift_warden` at
the arena center — `ensureFightInitialized` self-pins on first tick either way. Arena
room should be ≥ 20×20×8 with a flat floor (plan §2.4/§4.1). Ask: call the seam (or
place the summon mechanism) when the vault boss room is stamped.

## What shipped

| File | What it is |
|---|---|
| `entity/pale/PaleEntities.java` | Registrar: frozen id `eclipse:pale_sentinel` (MONSTER 0.8×2.6, eye 2.3), attributes, on-ground monster spawn placement. |
| `entity/pale/PaleSentinelEntity.java` | Weeping-angel guardian, 40 HP / dmg 6 / speed 0.45 / kb-res 0.6. Frozen = `isImmobile()` full stop + synced FROZEN flag + statue-pose anim + 60% damage resistance + petal-burst root-step flinch instead of knockback; unfrozen = fast creep. Private wood-creak whispers to observers ≤ 8 blocks (~60 t). Day → 40 t bark-flake burrow despawn. 35 t upright crumble death. |
| `entity/pale/ObservedFreezeHelper.java` | The precise is-any-player-looking check per plan §2.3: non-spectator players ≤ 32, view-cone dot ≥ 0.5 (forgiving), `level.clip` COLLIDER occlusion both to eye and body center. 5 t hysteresis both ways lives in the entity (`UNSEEN_GRACE_TICKS`) — no strobe at cone edges. |
| `entity/dungeon/DungeonEntities.java` | Registrar: frozen ids `eclipse:eclipse_cultist` (MONSTER 0.6×1.9) + `eclipse:shadow_bolt` (MISC projectile 0.35×0.35), attributes, spawner-friendly placement. |
| `entity/dungeon/EclipseCultistEntity.java` | Robed dungeon caster, 20 HP / dmg 3 / speed 0.3, no persistence quirks (dungeon spawners re-supply). 30 t kneel-collapse death; 10% `cultist_sigil` bonus drop hook (registry lookup, skip-if-absent). |
| `entity/dungeon/RangedShadowBoltGoal.java` | Kite 8–14 blocks, every 60 t a 20 t rooted cast (`cast` anim + rune flare) → 3-bolt fan (±12°); panic knife swipe when crowded ≤ 2 blocks. |
| `entity/dungeon/ShadowBoltProjectile.java` | `AbstractHurtingProjectile`-style bolt (SmallFireball movement, no gravity), homing-lite steering, purple trail (PORTAL/WITCH), hit = 5 dmg + Wither I 2 s, passes through fellow `Enemy` mobs (no friendly fire), 100 t fuse. |
| `entity/boss/rift/RiftEntities.java` | Registrar: frozen id `eclipse:rift_warden` (MONSTER 1.1×3.0, fire/drown-immune). |
| `entity/boss/rift/RiftWardenEntity.java` | Mini-boss, 200 HP ×(1+0.35·(n−1)) / dmg 7 / armor 4 / kb-res 1.0. PURPLE `ServerBossEvent`. P1: 5-bolt shadow volleys every 120 t (20 t telegraph) + rift-step blink every 200 t (15 t rising GLASS chime AT the destination → 10 t vanish → reappear behind target). P2 ≤ 50%: summon 2 cultists (registry lookup by id, skip if absent), volleys every 70 t, 40 t weakpoint stagger (+50% damage taken) after each volley. Soft enrage 6 min (−25% cadence), Herald-pattern wipe/reset + outside-ring damage deflect, 60 t scripted implosion death + participant-feet drops. |
| `entity/boss/rift/RiftAnchor.java` | Immutable arena anchor: r=12 ring at summon pos, contains/impulse/particle-wall helpers (SoftBorder pattern). |
| `client/entity/{pale,dungeon,rift}/*.java` | Self-subscribed renderer registrars + `EclipseGeoRenderer` subclasses (`withGlowmask().withUprightDeath()`); `ShadowBoltRenderer` is a raw `GeoEntityRenderer` (non-living): fullbright + glow layer, no shadow. |
| `worldgen/structure/dungeon/DungeonSpawners.java` | (Shared file, owned arrays only) default spawner rotations now lead with `eclipse:eclipse_cultist` in COLLAPSED_VAULT (2 spawners) + UMBRAL_WARRENS (1), vanilla fallbacks intact. |
| `assets/eclipse/geo/entity/{pale_sentinel,eclipse_cultist,rift_warden,shadow_bolt}.geo.json` | 16/13/18/3-bone models — validated (`validate_geo.py`), zero UV overlaps. Warden torso is the split-knight: armor half cube + `glow_rift_core` void-tear filling the missing half. |
| `assets/eclipse/animations/entity/*.animation.json` | Full sets — sentinel: idle/walk/**freeze** (constant-pose loop — rock-solid, no molang drift)/attack/death; cultist: idle/walk/cast/attack/death; warden: idle/walk/attack/volley/blink_out/blink_in/summon/stagger/death; bolt: idle spin. Lengths match server timings (cast 20 t, stagger 40 t, deaths 35/30/60 t). |
| `scripts/geckolib_gen/mobs/{pale_sentinel,eclipse_cultist,rift_warden,shadow_bolt}.py` | Deterministic painters → `textures/entity/<id>.png` + `_glowmask.png` (64/64/128/32 canvases, §2.3/§2.4 palettes). |
| `data/eclipse/loot_table/entities/{pale_sentinel,eclipse_cultist,rift_warden}.json` | Default-id entity loot: sentinel = pale-oak log/moss + phantom membrane; cultist = purple candle/ink/lapis + rare umbral shard; warden = guaranteed umbral shards + `eclipse:replant` enchanted book + otherside-disc-or-echo-shard trophy roll. |
| `docs/uv/{pale_sentinel,eclipse_cultist,rift_warden,shadow_bolt}.md` | UV layouts + art briefs + regen commands. |
| `docs/plans_v3/langdrop/P6-W910.json` | Names + `entity.eclipse.rift_warden.bossbar`, en+de. |

## Wiring asks (for other owners)

1. **Integrator:** apply the three one-liners above; merge `docs/plans_v3/langdrop/P6-W910.json`.
2. **P1 (Collapsed Vault):** call the boss-room summon seam (section above) when the
   vault's boss room is stamped; spawner arrays already carry the cultist.
3. **P4 (items, optional):** cultist's 10% bonus drop looks up `eclipse:cultist_sigil`
   and the sentinel/warden loot references `eclipse:umbral_shard` + enchantment
   `eclipse:replant` — all resolved by id at runtime/table-load; if any id changes,
   it's a one-word edit per table (skip-if-absent in code paths).

## Coordination notes

- **No shared-registry edits**: each family owns its own `DeferredRegister`; the frozen
  entity ids match §6 of the plan.
- **Sentinel freeze is server-authoritative**: `ObservedFreezeHelper` runs server-side
  each tick; the synced FROZEN flag drives both `isImmobile()` (hard stop — navigation,
  look control and knockback all gated) and the client statue-pose loop. The freeze
  anim is a constant-keyframe loop, so there is zero client-side jitter even if the
  server flag flaps within the 5 t hysteresis window.
- **Warden fairness cues**: volley has a 20 t two-arm raise + core flare telegraph;
  blink chime plays AT the destination for 15 t before the reappear; stagger is the
  scripted punish window after every volley.
- **Sounds are vanilla events re-pitched** (creaking/wood, evoker/illusioner, warden/
  enderman families) — no `sounds.json` edits, per the freeze.
- **Spawn gating**: pale sentinel natural spawning waits on P1's Pale Garden ring
  (plan §2.5 — default gate FALSE; `/summon` for testing); cultist arrives via dungeon
  spawners only; warden only via the summon seam.

## Risks

- All three families are invisible in-game until the one-liners land (intended dormancy).
- Warden P2 cultist summons no-op (with a single warn log) if `DungeonEntities` isn't
  wired — fight still completes, just without adds.
- Loot references P4-owned ids (`umbral_shard`, `replant` enchantment) — table-load
  logs an error and drops nothing for a bad id, mobs still die clean.
- The sentinel's observed-freeze check raycasts per player per tick (≤ 32 blocks); with
  many players in the pale garden this is the priciest per-tick cost of the family —
  profile if server TPS complains (easy fix: stagger scans across ticks).

## Test steps (runServer + RCON, AGENTS.md pattern)

1. `/summon eclipse:pale_sentinel` at night → gaunt birch-white figure stands utterly
   still while you look at it (statue pose, ember eyes glow); look away (or turn > ~60°)
   → fast jerky creep towards you with wood-creak whispers; look back → instant freeze,
   zero jitter. Hit it while frozen → pale petal burst + 1-block root-step flinch, damage
   reduced. Kill → 35 t upright crumble, pale-oak drops. At dawn → sinks into the ground
   in bark flakes.
2. `/summon eclipse:eclipse_cultist` → robed caster kites to 8–14 blocks, roots, raises
   both arms (runes flare) for 1 s, then a 3-bolt purple fan homes gently onto you
   (5 dmg + Wither 2 s each). Crowd it ≤ 2 blocks → panic knife swipe. Kill → kneel
   collapse, candle/ink/lapis drops.
3. `/summon eclipse:rift_warden` in a ≥ 20×20 flat room → purple bossbar fills, r=12
   ring pins. P1: blade sweeps + 5-bolt volleys (2-arm raise telegraph) + blink-behind
   every 10 s (rising chimes at the destination first). Damage it from outside the ring
   → deflected with a cue. Below 50% → 2 cultists summoned, faster volleys, and after
   each volley a 2 s kneel stagger (hit it hard — +50% damage). Kill → 60 t implosion
   (blades plant, rift swallows the body), shards + book + trophy drop at participants'
   feet.
