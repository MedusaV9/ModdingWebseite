# W4-WAND wiring notes — Der Zauberstab (IDEA-19: paths, powers, soulbind, charge)

**ONE hub line.** Everything else self-registers (`@EventBusSubscriber` / self-registrar
payload group per the `GatePayloads`/`HeartsPayloads` conventions). No `EclipsePayloads`,
`EclipseGuiLayers`, `registry/**`, lang JSON, `sounds.json` or `build.gradle` edits.

## Integrator asks

1. **`EclipseMod` constructor — add one line** (next to the other registrar calls):

   ```java
   dev.projecteclipse.eclipse.wand.WandItems.register(modEventBus);
   ```

   Registers the `eclipse:eclipse_wand` item + the six `eclipse:wand_*` data components
   and hooks `config/eclipse/wand.json` onto `/dev reload`. Until this line lands, every
   wand class stays dormant (client extensions/HUD guard on `ECLIPSE_WAND.isBound()`).

2. **Langdrop**: apply `docs/plans_v3/langdrop/W4-WAND.json` (en+de) to
   `assets/eclipse/lang/en_us.json` / `de_de.json`.

3. **Ordering dependency (soft)**: the crafting recipe
   (`data/eclipse/recipe/eclipse_wand.json`) requires `eclipse:wizard_catalyst`, which is
   REGISTERED by the W4-WIZARD sibling (`entity/wizard/WizardEntities` — id frozen there;
   this worker deliberately does NOT register it again, that would be a duplicate-id
   crash). If W4-WAND is wired before W4-WIZARD, the recipe logs an unknown-item parse
   error at datapack load and the wand is uncraftable until the wizard registrar lands —
   nothing crashes. This worker DOES ship the catalyst's `models/item/wizard_catalyst.json`
   + `textures/item/wizard_catalyst.png` (the wizard side shipped neither).

## What landed

### Server / common (`wand/**` — all NEW)

| File | Role |
|---|---|
| `WandItems.java` | Registrar: item + data components (`wand_owner` UUID, `wand_path`, `wand_level`, `wand_xp`, `wand_charge`, `wand_selected` — all persistent + synced) + the `/dev reload` config hook. |
| `EclipseWandItem.java` | The mod's first GeckoLib ITEM (`GeoItem` + synced singleton animatable). `base` controller loops `animation.eclipse_wand.idle`; `action` controller holds triggerables `use`/`levelup`/`awaken`/`stall` fired server-side via `triggerWandAnim`. Right-click: pathless → client chooser, else C2S cast request. Sneak-right-click cycles the selected power. Inventory tick: soulbind upkeep + once-a-second charge regen (held > stowed, ×`nightMult` at night). |
| `WandPath.java` | Path enum (NONE/RISS/GLUT/STERN), frozen power keys, lang keys, `stageForLevel` (L1→s1, L2-3→s2, L4-5→s3). |
| `WandStore.java` | SavedData (`data/eclipse_wand.dat`): per-PLAYER progression table + globals (`perItemMode`, `trading`, `disabledUntilEpochMs`). |
| `WandSoulbind.java` | Conversion rules. PLAYER mode (default): store row is the truth, foreign wands CONVERT to the holder's own progression; ITEM mode: progression rides the stack, conversion only rewrites the owner; trading ON suppresses conversion entirely. |
| `WandConfig.java` | Reloadable `config/eclipse/wand.json`: charge economy, XP curve (`levelCosts` 120/260/450/700), one entry per power (`cost`, `cooldownTicks`, free-form float params). `*_2` entries are the L4/L5 upgraded re-runs. |
| `WandPowers.java` | ALL cast validation (held item, owner, disable switch, path, unlocked index, charge, per-player-per-power cooldown, protection zones) + the nine power implementations + XP/level-up (trigger anim + staggered `unlock_burst` flourish — deliberately NOT the LevelUpOverlay) + kill-bonus hook. |
| `WandPhaseService.java` | Crash-safe Phasenwelle engine: cone de-rez snapshots persisted to SavedData (`data/eclipse_wand_phase.dat`) BEFORE blocks vanish; staggered block-by-block re-materialize with `border_glitch`/`impact_light` pops; `restoreAllOnLoad` on server start makes a crash unable to eat terrain. Blacklist: block entities, spawn-protection zones, unbreakables, fluids. Restore never overwrites player-built blocks. |
| `WandTickService.java` | Server-tick engine: delayed one-shots (star volleys, rift closes, celebration pops), Feuerwelle ring march (visual-first, hit-once, zero block ignition), Magmasprung landing watcher (fall-damage forgiven once). Drives `WandPhaseService.tick` + crash recovery. |
| `WandEvents.java` | `LivingDeathEvent` → kill-bonus wand XP while holding your own wand. |

### Network (`network/wand/**` — all NEW)

`WandPayloads.java` (registrar version `w4wand1`), `C2SWandCastPayload` (hand only —
server reads everything else itself), `C2SWandChoosePathPayload` (first-choice lock,
server re-validates NONE state). No custom S2C: components + GeckoLib sync + frozen FX
channels cover it.

### Client (`client/wand/**` — all NEW)

| File | Role |
|---|---|
| `EclipseWandRenderer.java` | `GeoItemRenderer` on the defaulted item triple. Model evolution = ONE geo file with `p_<path>_s<stage>` bone groups toggled per frame from the synced components (`GeoBone#setHidden` propagates to children); texture swaps per path; `AutoGlowingGeoLayer` lights the per-variant `_glowmask`. Chosen over per-path geo files so idle/use/levelup animations are authored once. |
| `WandClientExtensions.java` | MOD-bus: `RegisterClientExtensionsEvent` → `IClientItemExtensions#getCustomRenderer` (lazy renderer), `RegisterGuiLayersEvent` → charge HUD above `HOTBAR`. Both guard on `isBound()`. |
| `WandPathScreen.java` | Quiet-Eclipse 3-card chooser (`EclipseUiTheme` panels, accent per path, L1-3 preview), opened on first right-click while pathless; ESC = decide later. Click sends the choose-path payload. |
| `WandChargeHud.java` | Ten Veilladung pips above the hotbar while a wand is held; tint follows the path; F1-safe (`hideGui`), not cutscene-whitelisted on purpose. |
| `WandClientHints.java` | Tooltip owner-name resolution from the tab list (lazy-loaded, dedicated-server safe). |

### Devtools

`devtools/dev/DevWandCommands.java` — `/dev wand disable <minutes>|enable`,
`trading on|off`, `mode player|item`, `set <player> path|level|xp|charge <v>`,
`reset <player>`. All perm 2, registered in `DevCommandRegistry` (`wand.*` doc ids,
category PLAYERS). `set`/`reset` edit the store row (PLAYER mode) AND all owned carried
wands so changes are visible instantly.

### Assets / data

- `assets/eclipse/geo/item/eclipse_wand.geo.json` — shared branch base (`handle`/`shaft`/
  `knot`/`tip`) + 9 ornament groups (riss shard crown ×3 stages, glut ember core + flame
  fins ×3, stern star/disc/orbiters ×3). Validated by `validate_geo.py` (PASS).
- `assets/eclipse/animations/item/eclipse_wand.animation.json` — `idle` (8 s seamless
  loop: float/orbit/pulse), `use`, `levelup`, `awaken`, `stall`. Validated (PASS).
- `assets/eclipse/models/item/eclipse_wand.json` — `builtin/entity` + staff-ish display
  transforms (tune here if the in-hand pose needs love — no code involved).
- `assets/eclipse/models/item/wizard_catalyst.json` + `textures/item/wizard_catalyst.png`.
- `assets/eclipse/textures/item/wand/eclipse_wand[_riss|_glut|_stern].png` + `_glowmask`s —
  painter `scripts/geckolib_gen/items/eclipse_wand.py` (deterministic; NEW `items/` dir).
- `data/eclipse/recipe/eclipse_wand.json` — shaped: 1 catalyst (tip) + 6 umbral shards +
  2 diamond blocks.

## Path / level cheat sheet (defaults; all in `config/eclipse/wand.json`)

| Path | L1 | L2 | L3 | L4/L5 |
|---|---|---|---|---|
| Phasenriss | Blink (12-block glitch teleport, no-clip refused = no cost) | Phasenwelle (10-block cone, ≤24 blocks de-rez 10 s, block-by-block return) | Rissschlag (portal-tear burst, 8 dmg r4) | Phasenwelle II (14/40/12 s), Rissschlag II (14 dmg r6) |
| Glutherz | Ember Bolt (ray, 5 dmg + 3 s fire) | Feuerwelle (12-block ground flame ring, 7 dmg, NEVER grief) | Magma Leap (launch + landing slam 6 dmg r4) | Feuerwelle II (18 blocks/10 dmg), Magma Leap II (higher/10 dmg r6) |
| Sternenfall | Spark Call (sky spark on aim, 5 dmg) | Star Shower (8-block zone, 1.5 s telegraph, 12 stars over 3 s) | Comet Strike (1 s telegraph, 12 dmg r5 + shockwave) | Star Shower II (10-block/20 stars), Comet Strike II (18 dmg r7) |

XP: `cost × 0.6` per successful cast + 8 per kill; level costs 120/260/450/700.
Charge: 100 max, 2/s held, 0.5/s stowed, ×2 at night; costs 12–55.

## Risks / notes

- **Item display transforms are authored blind** (`models/item/eclipse_wand.json`): the
  staff pose in hand/GUI may need a few-degree nudge in Blockbench. Pure JSON tweak.
- **Feuerwelle/Sternschauer FX queues are in-memory** (deliberate): a server stop mid-wave
  drops the remaining FX/damage ticks. The world-mutating Phasenwelle is the ONLY
  persisted schedule (crash-safe by SavedData snapshot).
- **`GeoItem.getOrAssignId` writes the GeckoLib stack-id component on first server-side
  trigger** — two freshly crafted wands stack-compare unequal after one is used (they are
  `stacksTo(1)` anyway).
- **PLAYER mode + `mode item` flips mid-run**: switching to ITEM mode freezes whatever the
  stacks currently mirror (by design — the store keeps its table for a flip back).
- **Cooldowns are in-memory per server run** (cleared on stop): a relog wipes them. Event
  scale: acceptable; persisting them would cost a SavedData write per cast.
