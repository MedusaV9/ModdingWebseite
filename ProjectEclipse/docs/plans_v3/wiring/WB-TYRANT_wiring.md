# WB-TYRANT wiring — Fog Tyrant apex boss (P6-W11)

## The one wiring line (integrator)

`EclipseMod` constructor, next to the other entity registrars:

```java
dev.projecteclipse.eclipse.entity.boss.fog.FogBossEntities.register(modEventBus);
```

That is the entire integration. Everything else is annotation-discovered: attributes
(`@EventBusSubscriber` inside the registrar), renderers
(`client/entity/fogboss/FogBossRenderers`, client-event self-subscribed — `FogRenderers`
pattern), and the lair proximity trigger (`FogBankMarker`, game-bus self-subscribed).
Until the line lands the whole family no-ops via `DeferredHolder.isBound()` guards (one
warn log at attribute time), so the build and both run configs stay green either way.

Also merge `docs/plans_v3/langdrop/WB-TYRANT.json` (entity name + bossbar key, en+de).
Bestiary keys for `fog_tyrant` already exist from P6-W56 — nothing to add there.

## Mature-storm summon seam (P1 / `FogStormSites`)

`fog_tyrant` is **NOT a spawner mob** — nothing in `DungeonSpawners` or the storm
spawner sets references it. P1's mature-storm flow has two entry points (pick one per
site; both self-pin the r=16 arena):

**Preferred — mark the lair (proximity-triggered, dramatic):**

```java
dev.projecteclipse.eclipse.entity.boss.fog.FogBankMarker.markLair(serverLevel, stormCenterBlockPos);
```

One line inside `FogStormSites.materializeSite`'s completion block for the strongest
(highest-stage) storm site — and again on the restart-restore path, because lairs are
deliberately NOT persisted (same lifecycle as the storm-wall re-announce; `markLair` is
idempotent, safe to call every boot). The marker dresses the center with ambient
fog-bank smoke pillars (r=10 ring — vanilla stand-ins until P2's `eclipse:fog_bank`
emitter, plan §4.2) and summons the tyrant through `FogTyrantEntity.summonAt` when a
player comes within 20 blocks (kept inside the boss's 24-block reset ring so the fight
can't flap). After a summon the trigger disarms; call `markLair` again (or let players
re-approach a re-marked lair) to re-arm. `clearLair`/`clearAll` unmark on storm
downgrade.

**Direct — summon now:**

```java
FogTyrantEntity tyrant = FogTyrantEntity.summonAt(serverLevel, arenaCenterBlockPos);
```

(`entity/boss/fog/FogTyrantEntity#summonAt` — finalizes spawn, pins the r=16 arena,
snapshots player-count HP scaling (350 × (1 + 0.4·(n−1)), n within 32 blocks), dedups
against a live tyrant within 64 blocks, returns the entity or null if the type isn't
bound yet.) Plain `/summon eclipse:fog_tyrant` also works anywhere —
`ensureFightInitialized` self-pins on first tick. Arena should be ≥ 34×34 open ground
with a mostly flat floor (r=16 ring + wall FX).

## What shipped

| File | What it is |
|---|---|
| `entity/boss/fog/FogBossEntities.java` | Registrar: frozen id `eclipse:fog_tyrant` (MONSTER 2.4×4.2, eye 3.0, fire-immune, tracking 10), attributes. |
| `entity/boss/fog/FogTyrantEntity.java` | The apex boss, 350 HP ×(1+0.4·(n−1)) / dmg 9 / speed 0.2 / kb-res 1.0 / armor 6. PURPLE NOTCHED_20 `ServerBossEvent` (notch lines sit exactly on the 60%/25% phase splits). P1 "Court": cleaver melee + fog-lance volleys every 140 t (25 t rooted raise, 3 locked lance lines glitter with electric warning trails, then 7 dmg down the exact trails — sidestep; raycasts budgeted 1 clip/lance at lock) + hound howl every 500 t (pack topped to 2 `eclipse:storm_hound` by id, skip-if-absent) + storm-step every 220 t (10 t vanish with a gathering fog column AT the destination, reappears on the target's flank). P2 ≤60%: crown lightning every 160 t (2 marked rings, 30 t = 1.5 s spark telegraph, visual-only `LightningBolt` + manual 8 dmg r=2.5 — no fire grief) + blind squall every 300 t (30 t rising sonic-charge cue while the crown collapses → Blindness 3 s + 4 dmg to everyone WITH line of sight — hide behind cover) + slow enrage stacking (1 stack/400 t, max 5: −6% special cooldowns, +4% speed each, transient attribute modifier). P3 ≤25%: one-time colossus call (1 `eclipse:fog_colossus` by id if none lives) + desperation barrage (volleys 70 t/5 lances, steps 120 t). One rooted telegraph at a time + 20 t gap between specials — no stunlocks. Herald wipe/reset (60 s empty ring → full heal + add cleanup + despawn), outside-ring damage deflect with cue, 70 t scripted storm-burst death (crown falls → core gutters at t32, synced CORE_LIT → thunderclap + `S2CShakePayload` at t60) + participant-feet drops. |
| `entity/boss/fog/FogTyrantArena.java` | Immutable arena anchor: r=16 ring at summon pos, contains/clamp/impulse/particle-wall helpers (RiftAnchor/SoftBorder pattern), NBT save/load. |
| `entity/boss/fog/FogBankMarker.java` | The lair marker + P1 seam (section above): idempotent `markLair`, ambient smoke-pillar dressing, 20-block proximity summon trigger, live-tyrant dedup, `clearLair`/`clearAll`, server-stop hygiene. |
| `client/entity/fogboss/{FogBossRenderers,FogTyrantRenderer}.java` | Self-subscribed renderer registrar (isBound-guarded) + `EclipseGeoRenderer` subclass: head-tracked, `withGlowmask()` (crown/eyes/core/lance edges/seams) + `withUprightDeath()` (scripted collapse), shadow 1.1. |
| `assets/eclipse/geo/entity/fog_tyrant.geo.json` | 23 bones / 29 cubes, 4.2-block crowned storm wraith — layered robe + 4 tatters, chest cavity with caged `glow_core`, two cloak layers, twin lance arms, hooded head, floating crown ring + 4 `glow_crown_*` shard-spikes. Validated (`validate_geo.py`), zero UV overlaps. |
| `assets/eclipse/animations/entity/fog_tyrant.animation.json` | 10 clips: `idle` (hover-sway, crown orbit), `stride`, `attack`, `lance_volley` (raise → thrust), `storm_step_out`/`storm_step_in`, `crown_call` (summon raise), `squall` (crown collapse → burst), `enrage`, `death` (crown falls first, core sag, collapse — eased). Lengths match server timings (raise 25 t, squall windup 30 t, death 70 t). |
| `scripts/geckolib_gen/mobs/fog_tyrant.py` | Deterministic painter → `textures/entity/fog_tyrant.png` + `_glowmask.png` (128², §2.4 palette: storm blue-black + electric seams; run from repo root). |
| `data/eclipse/loot_table/entities/fog_tyrant.json` | Default-id entity loot: 6–9 umbral shards (+looting), the `eclipse:replant` enchanted book (degrades gracefully pre-P4), storm-trophy roll (worn trident / heart of the sea). Code adds 1 `storm_heart` (fallback 6 shards) + 3 shards per participant. |
| `docs/uv/fog_tyrant.md` | UV layout + art brief + regen command. |
| `docs/plans_v3/langdrop/WB-TYRANT.json` | `entity.eclipse.fog_tyrant` + `.bossbar`, en+de. |

## Wiring asks (for other owners)

1. **Integrator:** apply the one-liner above; merge `docs/plans_v3/langdrop/WB-TYRANT.json`.
2. **P1 (`FogStormSites`):** add the `FogBankMarker.markLair(...)` line (section above)
   for the strongest storm site when it materializes AND on restart-restore; call
   `clearLair` if a storm downgrades. Alternatively call `summonAt` directly or leave
   the tyrant admin-summon this event — everything works standalone.
3. **P2 (FX, optional):** ambient banks + step bursts use vanilla particles behind
   single helper methods (`fogBurstFx`, `FogBankMarker` pillar loop) — one-line swaps
   when the `eclipse:fog_bank` emitter lands (plan §4.2).
4. **P4 (items, optional):** loot references `eclipse:umbral_shard` + enchantment
   `eclipse:replant` (table-load resolved) and looks up `eclipse:storm_heart` at drop
   time (fallback 6 shards + one info log) — id changes are one-word edits.

## Coordination notes

- **No shared-registry edits**: the family owns its own `DeferredRegister`; the frozen
  id matches §6. No file outside `entity/boss/fog/**`, `client/entity/fogboss/**` and
  this worker's assets/scripts/docs was touched (FogStormSites, stormfx, other entity
  packages, EclipseMod and lang assets untouched).
- **Summoned adds are guests, not dependencies**: hounds/colossus arrive by registry-id
  lookup with skip-if-absent warn logs, get the `eclipse_tyrant_add` command tag, and
  are despawned by wipe/reset hygiene. The fight completes without W7/W8 wired — just
  lonelier.
- **Fairness cues**: every special is telegraphed (lance trails 25 t, lightning rings
  1.5 s, squall audio 1.5 s + crown-collapse read, step destination fog column), only
  one rooted telegraph runs at a time with a 20 t gap, and the squall respects
  line-of-sight cover.
- **Sounds are vanilla events re-pitched** (warden/lightning/trident/wolf/elder-guardian
  families) — no `sounds.json` edits, per the freeze.
- **Boss bar** uses `NOTCHED_20` so bar notches land exactly on the 60%/25% phase
  thresholds; the boss-theme bar skin ships to viewers via the existing
  `S2CBossbarStylePayload` pattern.

## Risks

- Family is invisible in-game until the one-liner lands (intended dormancy, warn log).
- Hound howl / colossus call no-op (with warn logs) if W7/W8 registrars aren't wired —
  fight still completes, just without adds.
- Loot references P4-owned ids (`umbral_shard`, `replant`, `storm_heart`) — table-load
  logs and drops nothing for a bad id; the code path falls back to shards.
- `FogBankMarker` lairs live in memory only — P1 must re-mark on restore (documented
  above; matches the storm-wall re-announce lifecycle). Until P1 wires the seam the
  tyrant is admin-summon only (deliberate).
- The blind squall's LOS check raycasts once per participant per squall (≤ every 15 s)
  — negligible; lance volleys clip once per lance at lock time (≤ 5 clips per volley).

## Test steps (runServer + RCON, AGENTS.md pattern)

1. `/summon eclipse:fog_tyrant` on ≥ 34×34 open ground → purple NOTCHED bossbar fills,
   r=16 fog ring pins. P1: slow relentless stalk + cleaver swings up close; every 7 s a
   rooted raise with 3 electric lines drawn to player positions — sidestep and the
   lances miss; every 11 s it vanishes in a fog burst (watch the gathering column — it
   reappears there, on your flank); periodically howls 2 storm hounds in.
2. Hit it below 60% → thunder + roar + shake; marked spark rings appear under up to 2
   players (1.5 s) then lightning hits the rings (no fire); every 15 s a rising charge
   sound while the crown collapses — break line of sight behind a block to dodge the
   blindness pulse. Watch it slowly speed up (enrage stacks, log lines).
3. Below 25% → it calls 1 fog colossus (if W8 wired) and the volleys double up (5
   lances, twice as often).
4. Damage it from outside the ring → deflected with a fizzle cue at your crosshair.
5. Walk everyone > 24 blocks away for 60 s → full heal, adds despawn, tyrant despawns
   clean (logs).
6. Kill it → 70 t storm-burst: crown falls, chest core gutters out mid-collapse, final
   thunderclap + camera shake; loot-table purse (shards + Replant book + trophy) plus
   storm-heart-or-shards and 3 shards at each participant's feet.
7. Seam dry-run: from a dev hook call
   `FogBankMarker.markLair(level, pos)` → smoke pillars ring the point; walk within 20
   blocks → the tyrant rises exactly as in step 1.
