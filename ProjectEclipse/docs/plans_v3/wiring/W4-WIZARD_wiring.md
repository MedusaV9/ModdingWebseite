# W4-WIZARD wiring — Orin the Sun-Reader + mountain observatory + catalyst loop

## The one wiring line (integrator)

`EclipseMod` constructor, next to the other entity registrars:

```java
dev.projecteclipse.eclipse.entity.wizard.WizardEntities.register(modEventBus);
```

That is the entire integration. Everything else is annotation-discovered:
attributes (`@EventBusSubscriber` inside `WizardEntities`), renderer
(`client/entity/wizard/WizardRenderers`, client-event self-subscribed), the observatory
builder + stage listener (`worldgen/structure/WizardObservatory`), the presence/respawn
service (`entity/wizard/WizardService`) and `/dev wizard` (`devtools/dev/
DevWizardCommands`). Until the line lands every listener no-ops via
`DeferredHolder.isBound()` (one warn log on attribute creation), so the build and both
run configs stay green with or without it. The observatory also waits: `WizardService`
never spawns an unbound entity, and the hut itself only stamps once the overworld
reaches stage 3 regardless.

## What shipped

| File | What it is |
|---|---|
| `entity/wizard/WizardEntities.java` | Family registrar: frozen ids `eclipse:wizard_orin` (CREATURE 0.7×2.1, eye 1.8) + `eclipse:wizard_catalyst` (EPIC, glint, stack 16). Attribute creation self-subscribed. No spawn egg, no natural spawning. |
| `entity/wizard/WizardOrinEntity.java` | The neutral hermit: 60 HP, wanders his hut (`restrictTo` r=10), sky-gaze idle, greets approaching players (pitched villager hum + chime, 1/min/player), 4 rotating localized dialogue lines on right-click ("Orin:" chat caption, en+de), fetch quest 8 amethyst + 1 umbral shard → 1 catalyst (once per player, ledger-first = dupe-proof), star_call defense when attacked (25 t telegraphed raise → 8 sky-bolts via `FX_LIGHTNING_STRIKE` @ 0.25 over a marked r=3.5 zone, 5 dmg near impacts), guaranteed single catalyst drop on death (`dropCustomDeathLoot`, despawn-proof item), scripted 40 t sit-down-fade death. Player-only damage (environment can't strand the loop). |
| `entity/wizard/WizardData.java` | Own `SavedData` (`data/eclipse_wizard.dat`, overworld): enabled flag, once-per-player catalyst ledger, live-Orin UUID, home pos, last death day. |
| `entity/wizard/WizardService.java` | Presence/respawn: 100 t ensure pass — observatory built + enabled + next-day-after-death + entity sections loaded → resolve UUID, else adopt a near-home Orin, else spawn fresh at the stamped home cell. Disable despawns + blocks respawn. |
| `worldgen/structure/WizardObservatory.java` | The summit hut: enqueued into `StructurePendingRegistry` (site `eclipse:wizard_observatory`, stage 3 = first disc that contains the whole mountain) by an own `WorldStageService` listener + a LOW-priority `ServerStartedEvent` catch-up; async placer terraforms an 11×11 shelf (`SitePrep.preparePlateau` anchored on the footprint's LOWEST deterministic `DiscTerrainFunction.surfaceY` — the peak is cut, never stilted) and stamps the deterministic build: deepslate terrace + rail, round stone-brick room, glass portholes, copper-seamed dome, waxed-copper block telescope with tinted-glass lens, bed/cauldron/bookshelves/lectern + cartography star-chart desk/amethyst/lanterns/glowstone. Version-stamped in a nested `ObservatoryVersionData` SavedData (`ShipVersionData` pattern): once V1 is stamped, re-placements are block-for-block no-ops; a stage erase below 3 clears the stamp + the hermit so a regrow rebuilds. `StructureStamper`/other builders untouched. |
| `client/entity/wizard/WizardRenderers.java` / `WizardOrinRenderer.java` | Renderer self-registration (`isBound()`-guarded) + `EclipseGeoRenderer` subclass: head tracking, glowmask layer, `withUprightDeath()` (death is keyframed), shadow 0.5. |
| `devtools/dev/DevWizardCommands.java` | `/dev wizard enable|disable|tp|givecatalyst <player>|resetquest <player>` (perm 3, docs registered in `DevCommandRegistry`, `[DEV AUDIT]` logs). |
| `assets/eclipse/geo/entity/wizard_orin.geo.json` | 14-bone robed astronomer: robe skirt, torso, scarf, back-slung brass spyglass, head (front face = lit skin), 2-cube silver beard, 3-cube pointed hat + emissive star charm, staff arm + short staff + emissive starlit tip, free arm. Validated, zero UV overlaps. |
| `assets/eclipse/animations/entity/wizard_orin.animation.json` | idle (6 s sky-gaze: slow head tilt to the stars, beard sway molang, hat-star twinkle, spyglass raise beat), walk, star_call (1.5 s cast raise, staff-tip flare ×2.1), hurt flinch, death (2 s sit-down-fade = the entity's 40 t script). Validated against the geo. |
| `scripts/geckolib_gen/mobs/wizard_orin.py` | Deterministic painter → `textures/entity/wizard_orin.png` + `_glowmask.png` (64×64): midnight robe + embroidered constellation stitches (albedo and glowmask share one noise predicate, so day-art and night-glow always agree), warm lantern-lit face, silver beard, brass belt/spyglass. |
| `scripts/item_art/gen_wizard_catalyst.py` | Deterministic 16×16 icon → `textures/item/wizard_catalyst.png`: molten sun-core orb, void-purple eclipse crescent bite, flare spikes (shared `eclipse_palette` finishing pass). |
| `assets/eclipse/models/item/wizard_catalyst.json` | Standard `item/generated` model. |
| `docs/uv/wizard_orin.md` | UV layout + art brief + regen/validate commands. |
| `docs/plans_v3/langdrop/W4-WIZARD.json` | en+de: entity/item names, `name.eclipse.wizard_orin` ("Orin", his tag + caption prefix), the 4 dialogue lines + quest hint/done/already/provoked, `bestiary.eclipse.wizard_orin.name`/`.lore`, `/dev wizard` doc keys + feedback lines. |

## Wiring asks (for other owners)

1. **Integrator:** apply the one-liner above; merge `docs/plans_v3/langdrop/W4-WIZARD.json`.
2. **Nobody else.** Checked and deliberately NOT asked for:
   - **`NameTagHider`** only hides **`Player`** name tags client-side — Orin's
     `setCustomNameVisible(true)` renders untouched. No exemption needed, no edit made.
   - **Bestiary:** `BestiaryTab` already carries the `wizard_orin` roster line (day 11,
     W4-BESTIARY's forward-wiring) — the langdrop's `.name`/`.lore` keys complete it.
   - **`/locate` landmark table:** `VanillaLandmarks.locateSites()` is an immutable map
     of **vanilla structure ids** → authored `disc_map.json` landmarks; a custom-only
     site has no vanilla id to key off, so there is no clean registration without
     editing that shared table (or aliasing a lie like `minecraft:igloo` — rejected).
     `/dev wizard tp` covers the dev need; if design later wants a player-facing
     pointer, the owner of `VanillaLandmarks`/`DiscMapDefaults` would add a
     `new DiscMapData.Landmark("eclipse:wizard_observatory", 54, -129, 16, 3)` row plus
     whatever surfaces it (map tab, compass), — out of W4-WIZARD scope.

## Sound aliases (all vanilla events, no `sounds.json` edits)

| Moment | Alias |
|---|---|
| Ambient + greeting hum | `VILLAGER_AMBIENT` @ pitch 0.78 (+ `AMETHYST_BLOCK_CHIME` @ 1.4 on greet) |
| Dialogue line | `VILLAGER_TRADE` @ 0.75 |
| Quest turn-in | `VILLAGER_CELEBRATE` @ 0.8 + `AMETHYST_BLOCK_RESONATE` @ 1.3 |
| star_call telegraph | `EVOKER_PREPARE_SUMMON` @ 1.5 + rising `AMETHYST_BLOCK_CHIME` ladder |
| Star-bolt impact | `AMETHYST_CLUSTER_BREAK` @ 1.6 |
| Hurt / death | `VILLAGER_HURT` / `VILLAGER_DEATH` @ 0.78 (via `getVoicePitch`) |
| Respawn arrival | `AMETHYST_BLOCK_RESONATE` @ 1.2 |

## Coordination notes

- **`eclipse:umbral_shard` is P4-owned** and resolved BY ID at runtime
  (`BuiltInRegistries.ITEM.getOptional`) — zero compile-time coupling. If P4 renames it
  the quest simply never completes (turn-in requires the item); one string fixes it.
- **The observatory placer key doubles as the site id** (`eclipse:wizard_observatory`),
  so `StructurePendingRegistry.registerAsyncPlacer` collides with nobody.
- **`FallbackBuilders.hash01`** (package-private, same package) drives every "random"
  crack/rail gap — the build is a pure function of position, so re-stamps are
  byte-identical (idempotence contract).
- The wizard family never edits `EclipseEntities`, `EclipseItems`, `StructureStamper`,
  `NameTagHider`, `VanillaLandmarks` or any other shared file.

## Risks

- Everything is dormant (hut included: no entity to spawn, but the hut itself still
  stamps at stage 3) until the one-liner lands — intended dormancy, one warn log.
- The star bolts reuse the frozen `FX_LIGHTNING_STRIKE` payload at intensity 0.25; if
  P2 ever re-tunes that payload's client visuals, the "falling star" read should be
  re-checked (single constant at `WizardOrinEntity.dropStarBolt`).
- Orin (2.1 tall) does not fit the 2-tall doorway — deliberate: the hermit keeps to his
  round room and terrace-side interior, and `star_call` needs no line-of-sight walk.
  If design wants him strolling the terrace, raise the doorway to 3 in `buildAt`.
- Multiplayer pacing (IDEA-19 §7): the once-per-player ledger + next-day respawn means
  a group can farm one catalyst per member per death cycle via the take path — matches
  the ideas doc; tune `lastDeathDay` handling if that reads too generous.

## Test steps (runServer + RCON, AGENTS.md pattern)

1. Fresh world → `/dev stage set overworld 3` (or progress normally). Watch the log for
   `WizardObservatory v1 built at …` once the pending registry places the site; the
   summit (54, -129) now carries the domed hut. `WizardService spawned Orin …` follows
   within 100 t.
2. `/dev wizard tp` → you land beside Orin/on the terrace. Right-click him ×4 → three
   riddles + the quest hint with live remaining counts ("Orin: …" captions, en+de).
3. `/give @s minecraft:amethyst_shard 8`, `/give @s eclipse:umbral_shard 1`,
   right-click → shards consumed, ONE `eclipse:wizard_catalyst` handed over, celebrate
   flourish. Right-click again → "already given" line; `/dev wizard resetquest @s`
   re-opens it.
4. Hit him → provoked line, then the telegraphed raise (rising chimes + zone sparkles)
   and 8 falling-star bolts over where you stood (~5 dmg each near impact). Stop
   attacking 30 s → he calms and heals.
5. Kill him → sit-down-fade, exactly one catalyst drop. `/time add 24000` → he respawns
   at the hut with the arrival sparkle. `/dev wizard disable` → poof + no respawn;
   `/dev wizard enable` → back within 100 t.
