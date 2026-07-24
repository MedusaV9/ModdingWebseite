# IDEA-19 — Der Zauberstab (The Veil Wand)

Collector 19/20, Eclipse Event ideas wave 4. Focus: a GeckoLib-animated magic wand whose
**model evolves** along a chosen, **locked** skill path; **per-player soulbound** (picking up
another player's wand converts it to yours); dev commands for trading / per-item mode /
global disable; **expensive craft** gated on a catalyst dropped by a **wizard NPC** living in
a hut on the highest mountain (toggleable via command). User seed ideas honored: temporary
glitch-vanish blocks (slow reappear), giant fire wave, star shower.

Everything below is grounded against the current codebase (read-only survey, no code changes).

---

## 0. Grounding — exact hooks that already exist

| Hook | Where | What the wand uses it for |
| --- | --- | --- |
| `QuasarSpawner.spawn / spawnManaged / ensureAttached(id, …, FxBudget.Channel)` | `veilfx/QuasarSpawner.java` | Every per-power particle cue; budget law (P2 §3.5) is already enforced, silent drop on refusal |
| `RiftFx.openRift(pos, normal, width, durationTicks, style)` / `closeRift(pos)` | `veilfx/rift/RiftFx.java` (FROZEN signatures, dispatched by `network/fx/FxPayloads` `FX_RIFT_OPEN`/`FX_RIFT_CLOSE`) | Glitch-path teleport + capstone tears (`STYLE_PORTAL` self-orients upright) |
| `StormFxClient.strikeLightning(from, to, intensity)` | `stormfx/StormFxClient.java` (FROZEN, via `FX_LIGHTNING_STRIKE`) | Cinder-path sky spear; contract: visual-only, **sender owns audio** |
| `TransitionFx.glitchPulse(amplitude, decayTicks)`, `playPortalEnter/Exit(ticks)` | `veilfx/TransitionFx.java` | Screen feedback on de-rez, rift step, overheat lockout (respect the ≤0.5 pulse ceiling RiftFx uses) |
| `FxPayloads.sendFxEvent(level, FX_*, pos, …)` | `network/fx/FxPayloads.java` | Server→client dispatch for all wand FX; add `FX_WAND_*` ids following the frozen-id convention |
| `FxBudget.tryLight` / channels `BURST`/`AMBIENT`/`STORM`/`SEQUENCE` | `veilfx/FxBudget.java` | Point lights for star impacts / ward circles; wand fx should charge `BURST` (one-shots) and `AMBIENT` (held loops) |
| Quasar emitter JSONs (`rift_spark`, `border_glitch`, `storm_arc`, `vortex_wisp`, `unlock_burst`, `heart_burst`, `eclipse_lightning_impact`, `impact_light`, …) | `assets/eclipse/quasar/emitters/` | Reuse as placeholders; new wand emitters follow the same JSON pattern |
| `SkillsApi.addXp(player, sourceKey, base)` (source scale → S2 → buff → secret multiplier → remainder → daily cap) | `skills/SkillsApi.java`, `SkillService` | Wand XP as a new `SOURCE_WAND` key so caps/multipliers apply for free; `SkillTreeConfig` nodes for synergy perks |
| `LevelUpOverlay`, `SkillProcToast`, `SkillXpBarLayer` | `client/skills/` | Path-choice reveal, wand proc toasts, wand charge HUD precedent |
| `ArmArtifactItem` + `ArtifactSlotLock` + `ArtifactDropGuard` | `artifact/` | The proven soulbound-item playbook: toss-cancel, grave exclusion (B17), container-nesting ban |
| GeckoLib bundled via jarJar; entity conventions frozen (`EclipseGeoMob`/`EclipseGeoMonster`, two controllers `base`+`action`, `triggerAction(String)`) | `build.gradle`, `entity/geo/`, `docs/plans_v3/handoff/P6_geckolib_conventions.md` | Wizard NPC rides the existing base class; wand is the mod's **first GeckoLib item** (`GeoItem` + client render provider + `triggerAnim`) |
| `GlitchedGeoRenderer`, `glitch/` package (`GlitchSpawnService`, `GlitchedMonster`s) | `client/entity/glitch/`, `glitch/` | Visual language for "de-rezzed" things already exists — glitch-vanish blocks should quote it |
| Structure builder pipeline (`StructureStamper`, `SitePrep`, `WatcherStatues`, `SundialPlaza`, …) | `worldgen/structure/` | The wizard's mountain hut is one more stamped site (highest-peak site selection like existing landmark placement) |
| `/dev …` command tree + generated `docs/DEV_COMMANDS.md`, `/eclipsefx …` client-FX debug root | `devtools/`, `DEV_COMMANDS.md` | All wand admin commands live under `/dev wand …`; FX preview via `/eclipsefx emitter` already works today |

Naming caution: `/dev display give` already hands out an op-only "Display Wand" — the player
item should be `eclipse:veil_wand` ("Zauberstab") to avoid confusion.

---

## 1. Core design

### 1.1 Item tech — the first GeckoLib *item*
`VeilWandItem implements GeoItem`, client rendering through GeckoLib's item render provider
(same asset layout as mobs: `geo/item/veil_wand.geo.json`, `animations/item/veil_wand.animation.json`,
per-path textures). One geo file with **bone groups per path and per stage**; the renderer
hides/shows bone sets from two item data components (`wand_path`, `wand_stage`), so the model
"evolves" without swapping items — enchantments, name, ownership all persist. Idle animation
(slow orbiting fragments, pulsing core) runs on the `base` controller; cast/levelup one-shots
fire via `triggerAnim` on the `action` controller — deliberately mirroring the frozen entity
controller convention so P6 workers feel at home.

### 1.2 Soulbind & conversion
Data component `wand_owner` (UUID + name). Rules:
- Owner-held: full function. Non-owner holding it: powers refuse with a glitch flicker
  (`TransitionFx.glitchPulse(0.15F, 6)`) and a tooltip line "Gehört <owner>".
- **Pickup conversion**: `ItemEntityPickupEvent` — if the picker isn't the owner, a 5-second
  "Attunement" runs (wand hums, `border_glitch` attached emitter), then owner rewrites to the
  picker, **stage resets by one** (conversion tax) and the old owner gets a chat whisper.
- Death handling copies `ArtifactDropGuard`: by default the wand DOES drop (it is loot — that
  is the point of conversion), but a config/per-item mode can pin it grave-exempt like the arm.

### 1.3 Acquisition — expensive craft + wizard catalyst
Recipe (altar or crafting): 1× **Sonnenkern-Katalysator** (wizard drop, §4) + high-tier
economy sinks (e.g. netherite ingot, echo shards, eclipse-event drops from `GlitchDrops`).
The catalyst is the gate; everything else is expense. Crafting yields a **stage-0, pathless**
wand ("Roher Zauberstab": a bent dark branch, faint purple seam).

### 1.4 Path choice — locked
First use of a pathless wand opens a 3-way radial choice screen (client screen in the
`SkillTreeScreen` visual family). Confirming plays a `LevelUpOverlay`-style reveal + wand
`awaken_<path>` trigger anim. `wand_path` is then **immutable** — no respec (dev command can
override, §5). The choice can also be made diegetically at the wizard's orrery (§4, idea R12).

### 1.5 Leveling — wand XP from use + skill-tree synergy
- Per successful cast: `SkillsApi.addXp(player, "wand", cost * 0.4F)` — a new
  `SkillService.SOURCE_WAND` key, so daily caps / secret multipliers / buffs apply with zero
  new pipeline code. **Wand stage XP** is tracked separately on the item (`wand_xp` component)
  and only accrues from *hitting something meaningful* (damage dealt, blocks de-rezzed,
  mobs slowed) — no AFK cast-at-wall leveling.
- Stages: 0 (raw) → 1 (Erwacht, ~30 min active use) → 2 (Gefestigt) → 3 (Vollendet). Each
  stage unlocks the next power tier AND the next model evolution.
- **Synergy nodes** in `SkillTreeConfig`: e.g. "Kanalisierung" (+15% wand charge regen),
  "Doppelfokus" (−10% cooldowns), "Nachhall" (wand kills grant skill XP at 1.5×). Wand feeds
  tree, tree feeds wand — one loop.

### 1.6 Cost economy — charge, not durability
Wand has **no durability** (it is a legendary soulbound item; breaking it would fight the
fantasy). Instead a **Veilladung** charge pool (0–100) on the item, regenerating ~2/s held,
faster at night/eclipse phases (read the timeline like `SunTracker` consumers do). Powers
cost 10–60 charge and carry individual cooldowns (tier-scaled). Overspending to 0 triggers
**Überhitzung**: 8 s lockout, wand model plays a `stall` anim, screen gets
`glitchPulse(0.3F, 20)`, and an attached `border_glitch` emitter crackles on the player.
HUD: thin charge bar above the hotbar when the wand is held (pattern: `SkillXpBarLayer`).

---

## 2. The three skill paths

### Path A — **Fadenriss** (Glitch / Veilbreaker) — "the world is negotiable"
Identity: reality-editing trickster; utility + control; palette violet/black, FX quote
`RiftFx`/`GlitchedGeoRenderer`. Model evolution: branch splinters into floating shards →
stage 2 a slowly rotating tear hovers in the head → stage 3 the head is a permanent mini
star-polygon rift (bone-animated arms, like a handheld `RiftRenderer` tear).

| Tier | Power | Effect | FX (exact hooks) |
| --- | --- | --- | --- |
| 1 | **Phasenriss** (glitch-vanish volley) | Cone of up to 24 blocks "de-rez": collision + render vanish for 10 s, then blocks **reappear one by one** (~2/s, randomized) | Server snapshots states in a `GlitchedBlocksService`; per-block vanish → `QuasarSpawner.spawn(border_glitch, pos, BURST)`; each reappear → `rift_spark` micro-burst; caster screen `glitchPulse(0.2F, 8)` |
| 2 | **Blinkschritt** (rift step) | 12-block teleport through a fist-sized tear | `RiftFx.openRift(pos, up, 2.0F, 15, STYLE_PORTAL)` at both ends (portal style self-orients upright), `TransitionFx.playPortalEnter(6)` / `playPortalExit(6)` |
| 3 | **Trugbild** | Leaves a glitching decoy clone (GlitchedGeoRenderer-style shimmer) that mobs target; caster gets 3 s of 30% transparency | attached `vortex_wisp` loop via `ensureAttached(…, AMBIENT)`; decoy despawn = `unlock_burst` |
| 4 | **Entrissene Zone** | 8-block sphere: hostile projectiles de-rez mid-flight (deleted with a spark), 12 s | rim walk of one managed `rift_spark` emitter — literally the `Rift.tickEmitters` rim-walk trick at sphere radius |
| 5 (capstone) | **Weltnaht** | Opens a real 10-block rift tear for 6 s that pulls mobs toward it (no damage; terror + reposition) | `RiftFx.openRift(width 10, durationTicks 120, STYLE_PORTAL)` + server-side pull vectors; close is the built-in collapse |

### Path B — **Aschensog** (Cinder / Sunfall) — "borrowed fire of the dying sun"
Identity: frontal damage, area denial; palette ember-orange on black; audio-heavy (sender
owns audio per the `strikeLightning` contract). Model evolution: charred branch → glowing
fissures → stage 2 a caged ember core (pulsing emissive) → stage 3 a floating shard-crown
that ignites during casts (trigger anim `flare`).

| Tier | Power | Effect | FX (exact hooks) |
| --- | --- | --- | --- |
| 1 | **Glutstoß** | Short flame jet, ignites 3 s | new `ember_jet` quasar emitter (clone of `storm_arc` with flame sprites), `BURST` channel |
| 2 | **Sonnenspeer** | Calls a sky strike on the aimed block (2.5 s telegraph circle) | server sends `FX_LIGHTNING_STRIKE` → `StormFxClient.strikeLightning(from-along-sun, to, 0.8F)` recolored variant or reused as-is (violet reads "veil-fire"); impact `eclipse_lightning_impact` + `FxBudget.tryLight` point light; **server plays the crack sound** (contract) |
| 3 | **Aschenmantel** | 6 s: melee attackers take burn, fire immunity | attached `vortex_wisp`-clone `ember_shroud` loop, AMBIENT channel |
| 4 | **Feuerwoge** (giant fire wave) | Expanding ground ring, radius 1→14 blocks over 2 s; damage + knock-up at the front, leaves 4 s ember patches | reuse `FX_SHOCKWAVE` payload for the ground ring; per-quadrant `ember_wave` bursts marched outward server-tick; heat-haze via a `VeilPostController` uniform ramp (Iris-gated like other post FX) |
| 5 (capstone) | **Kleine Sonne** | Hovering fire orb (5 s) that lobs 6 mini Sonnenspeere at nearby hostiles | orb = managed loop emitter + budgeted light; each lob is a low-intensity `strikeLightning(orbPos, target, 0.35F)` |

### Path C — **Sternenfall** (Astral / Star Shower) — "the night sky answers"
Identity: ranged artillery + ally support; palette white-gold/deep blue; quietest, most
elegant FX. Model evolution: pale wood inlaid with silver → stage 2 three orbiting star
motes (bone orbit anim) → stage 3 a slowly turning constellation disc behind the tip,
motes flare on cast (`triggerAnim("cast_flare")`).

| Tier | Power | Effect | FX (exact hooks) |
| --- | --- | --- | --- |
| 1 | **Sternsplitter** | Fast homing bolt, low damage, generous cooldown (bread & butter) | projectile modeled on `ShadowBoltProjectile`/`ShadowBoltRenderer` (dungeon pkg) with star texture; impact `unlock_burst` |
| 2 | **Sternenkarte** (constellation ward) | 6-block ground circle, 10 s: hostiles inside slowed 30%, allies +regen | 5 managed `limbo_motes`-style emitters at pentagram points + ONE `FxBudget.tryLight` light; rim walk like `RiftFx` |
| 3 | **Lichtsegel** | 4 s glide/slow-fall with a star-trail | reuse `FX_GLIDE_START`/`FX_GLIDE_STOP` payloads + `glide_trail` emitter — the whole hook already exists |
| 4 | **Sternschauer** (star shower) | Marked 10-block zone; after 1.5 s, 12 comets rain over 3 s (damage + brief stun on direct hit) | each comet: thin `strikeLightning(skyPos, impact, 0.25F)` ribbon reads as a falling star + `heart_burst`-clone `star_impact` emitter + budgeted impact light; charge `STORM` channel to share the arc budget |
| 5 (capstone) | **Supernova** | 3 s channel, then screen-white bloom + 12-block knockback/blind, allies shielded | `TransitionFx.setLoadingPulse` ramp for the white-out (already a full-screen fade knob), `unlock_burst` ×N, one `FX_SHOCKWAVE`; hard-capped once per 60 s |

---

## 3. Wizard NPC — **Orin der Sonnenleser**
- **Character**: a hermit astronomer who watched the first eclipse through his orrery and
  never came back down. Half his robe is embroidered with accurate constellations; the other
  half is burned bare. Speaks in eclipse-timeline riddles (hooks into `timeline` phase for
  dialogue variants). Not hostile until provoked — the catalyst can be **earned** (fetch
  quest: bring 3 storm-hound essences from `GlitchDrops`) **or taken** (fight him).
- **Tech**: `EclipseGeoMob` subclass (`geoId() = "sun_reader"`), frozen two-controller
  layout; fight one-shots via `triggerAction` ("staff_slam", "star_call" — his star_call is
  literally Sternschauer tier-4, so the boss teaches the player what the wand can become).
- **Home**: "Observatorium" hut stamped by a new builder in `worldgen/structure/`
  (`StructureStamper` pipeline, highest-peak site selection; interior: bed, telescope out the
  roof, the **path-choice orrery**, a locked chest with lore pages).
- **Drop**: 1× Sonnenkern-Katalysator guaranteed on quest turn-in or death; respawns with a
  long cooldown (config) so multiplayer servers can gear multiple players.
- **Toggleable**: `/dev wizard enable|disable` (despawns/blocks respawn, structure stays),
  `/dev wizard tp`, `/dev wizard givecatalyst <player>` for testing.

---

## 4. Dev commands (all under `/dev wand …`, exported by `/dev docs export`)

| Command | Effect | perm |
| --- | --- | --- |
| `/dev wand give <player> [path] [stage]` | Spawn a configured wand | 2 |
| `/dev wand setpath <player> <path>` / `setstage <n>` / `addxp <n>` | Override lock/progression | 3, *caution* |
| `/dev wand trading <on\|off>` | Global: allow deliberate hand-over without conversion (owner sneak-drops = gift) | 3 |
| `/dev wand mode <held-item> <soulbound\|tradable\|inert>` | **Per-item mode** component override | 3 |
| `/dev wand disable <on\|off>` | Global kill-switch: all wands inert (tooltip says so) — event-ops panic button | 3, *caution* |
| `/dev wizard enable\|disable\|tp\|givecatalyst` | See §3 | 3 |
| `/eclipsefx emitter eclipse:<wand emitter>` | Already works today for FX preview | 3 |

---

## 5. The 12 ranked ideas

Ranked by (impact on the wand fantasy) × (how much existing code carries it).

1. **R1 — Phasenriss: glitch-vanish blocks with staggered reappear** *(Path A tier 1; the user's seed idea, and the wand's signature)*. Server `GlitchedBlocksService` snapshots up to 24 block states, swaps to air (block-entity positions blacklisted, snapshot persisted so a crash restores on load), then restores 1 block every ~10 ticks in random order. Every vanish/restore fires `QuasarSpawner.spawn(border_glitch/rift_spark, pos, BURST)`; caster gets `TransitionFx.glitchPulse(0.2F, 8)`. The slow one-by-one reappear IS the fantasy — the world "re-rendering" itself.
2. **R2 — The evolving GeoItem core**: first GeckoLib item in the mod; one geo with per-path/per-stage bone groups toggled from `wand_path`/`wand_stage` data components; `base` idle controller + `action` trigger controller mirroring the frozen P6 entity convention; `triggerAnim("levelup")` moment with `unlock_burst` + `LevelUpOverlay`-style banner. Everything else (soulbind, paths) hangs off this item.
3. **R3 — Orin der Sonnenleser + Observatorium + catalyst loop**: the acquisition story (§3). Boss reuses `EclipseGeoMonster` fight conventions; hut reuses the `StructureStamper` pipeline; his "star_call" attack foreshadows the Sternenfall capstone. `/dev wizard` toggles.
4. **R4 — Soulbind with pickup-conversion + attunement tax** (§1.2): `ArtifactDropGuard`/`ArtifactSlotLock` playbook, minus the slot pin; conversion drops one stage so stealing is viable but not strictly better than earning.
5. **R5 — Feuerwoge (giant fire wave)** *(user seed idea)*: `FX_SHOCKWAVE` ground ring + marched `ember_wave` bursts + `VeilPostController` heat-haze uniform; server-side expanding damage annulus with knock-up; leaves ember patches.
6. **R6 — Sternschauer (star shower)** *(user seed idea)*: 12 thin `StormFxClient.strikeLightning(skyPos, impact, 0.25F)` ribbons as falling stars over a telegraphed zone, `star_impact` bursts + `FxBudget.tryLight` lights, charged to the `STORM` channel so storm-scene budgets still hold.
7. **R7 — Veilladung charge economy + Überhitzung lockout** (§1.6): no durability; charge bar HUD (pattern `SkillXpBarLayer`), night/eclipse regen bonus read from the timeline, overheat = 8 s lockout + `stall` anim + `glitchPulse(0.3F, 20)` — cost UX that never brick-breaks a soulbound legendary.
8. **R8 — Wand XP through `SkillsApi` + synergy tree nodes** (§1.5): new `SOURCE_WAND` key rides the whole existing pipeline (caps, secret multipliers, buffs); item-side `wand_xp` only from meaningful hits; 3 `SkillTreeConfig` nodes (charge regen, cooldown, Nachhall XP echo) close the loop both directions.
9. **R9 — Blinkschritt rift-step**: `RiftFx.openRift(…, 2.0F, 15, STYLE_PORTAL)` at both ends + `TransitionFx.playPortalEnter/Exit(6)`; cheapest "wow" in the kit since portal orientation, collapse and budget-retry are already written.
10. **R10 — Path-locked choice with diegetic orrery ritual** (UX): pathless wand + 3-way radial screen, but choosing *at Orin's orrery* grants +5 starting charge — nudges players to visit the hut and reads the lock as ceremony, not menu. Reveal via `LevelUpOverlay` visual family; procs via `SkillProcToast`.
11. **R11 — Weltnaht capstone (pull-rift)**: a real `RiftFx.openRift(width 10, 120 ticks, STYLE_PORTAL)` with server-side suction — mob repositioning ultimate with zero new renderer work; close collapse is free.
12. **R12 — Trugbild glitch decoy + Entrissene Zone projectile de-rez**: control duo that quotes `GlitchedGeoRenderer` shimmer on a decoy and rim-walks one managed `rift_spark` emitter around a projectile-deleting sphere (the exact `Rift.tickEmitters` trick).

---

## 6. Open questions for the synthesizer
- Should Sonnenspeer/Sternschauer ribbons get a recolor parameter on `strikeLightning`, or
  ship v1 with the existing violet bolt (reads fine for "veil" magic, zero frozen-API risk)?
- Grave interaction default: wand drops on death (loot economy) vs. arm-style grave-exempt —
  suggest config default `drops`, per-item override via `/dev wand mode`.
- Multiplayer catalyst pacing: wizard respawn cooldown vs. one-catalyst-per-player quest flag.
