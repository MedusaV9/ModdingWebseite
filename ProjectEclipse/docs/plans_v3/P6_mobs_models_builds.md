# P6 — Mobs, Bosses, Models, Animations & Signature Builds (plans_v3)

**Planner:** P6 (one of six parallel planners). **Scope:** GeckoLib adoption, new mobs + bosses with real Blockbench-format models/animations/textures, limbo ship-fight bug fixes, ghost-ship rework + respawn door, altar/spawn-island rework, player skin v2, ghost rendering (client side), spawn integration, dungeon mob sets.

**Repo:** `/workspace` (branch `cursor/project-eclipse`), project `/workspace/ProjectEclipse`, package `dev.projecteclipse.eclipse`, mod id `eclipse`, MC 1.21.1, NeoForge 21.1.238, Veil 4.3.0 (jar-in-jar), Java 21, ModDevGradle 2.0.142. No unit tests — verification is `./gradlew build` green + `runServer` clean boot + `runClient` visual checks on the VM desktop (see `AGENTS.md` in `ProjectEclipse/`).

**Workers: read §0 (constraints) and §6 (frozen IDs) before writing any code. Workers cannot see the user's original message — this document is the complete specification.**

---

## 0. Global constraints for every P6 worker package

1. **NEVER modify** `admin/EclipseCommands.java`. Test with existing commands (`/eclipse boss <herald|ferryman> summon`, `/eclipse day set <n>`, `/eclipse stage set`, `/eclipse tp_limbo`, `/eclipse event set <pale|umbral|none>`) plus vanilla `/summon`, `/tp`, `/kill`, `/gamemode`. New bosses/mobs MUST be fully testable via plain `/summon eclipse:<id>` (self-initializing fights, `ensureFightInitialized` pattern from `FerrymanEntity`).
2. **NEVER edit** `assets/eclipse/lang/en_us.json` / `de_de.json`. Every new user-visible string goes to `docs/plans_v3/langdrop/<worker>.json` with shape `{"en_us": {"key": "..."}, "de_de": {"key": "..."}}`. Both languages ALWAYS. An integrator merges langdrops.
3. **NEVER edit** `EclipseMod.java`. If your registrar needs a constructor wiring line (e.g. `FogEntities.register(modEventBus);`), append it to `docs/plans_v3/wiring/P6_wiring.md` (create dir/file if absent) under a heading with your worker id. Prefer `@EventBusSubscriber`-annotated classes which need NO wiring (NeoForge 21.1 auto-routes mod-bus events like `RegisterPayloadHandlersEvent`, `EntityAttributeCreationEvent`, `EntityRenderersEvent.*` from annotated classes).
4. **File ownership is exclusive** — the matrix in §3 lists every file a worker may create/edit. Do not touch another P6 worker's files. Shared legacy files each have exactly ONE P6 owner (e.g. `client/entity/EclipseEntityRenderers.java` → P6-W2 only).
5. **Textures are authored procedurally**: python3 + Pillow are installed on the VM. Commit deterministic generator scripts under `scripts/geckolib_gen/` (shared lib by P6-W1) and run them to produce PNGs; commit both. AI-generated art may replace pixels later at identical paths/sizes — never change a path or canvas size. Repo precedent for procedural texture quality: `scripts/placeholder_gen/EntitySkinArtist.java` (hash-dithered materials, per-face directional shading, 1px inner outlines, unshaded emissive regions).
6. **Sounds: vanilla `SoundEvents` only** (pitch/volume shifted — precedent: Umbral Stalker uses `WOLF_GROWL` at 0.5 pitch). Do NOT edit `registry/EclipseSounds.java` or `sounds.json` (both are cross-planner shared). If a bespoke sound is truly needed, list it in your handoff notes for the audio pass.
7. **Every acceptance criterion that says "screenshot" or "video" is mandatory**: `./gradlew runClient` opens a real window on the VM desktop; drive it via computer use, take screenshots (F2 → `run/screenshots/`, copy to artifacts). Boss fights and animation sets require screen recordings.
8. Commit style: one commit per logical change, message prefix `eclipse v3: P6-Wn — ...`. `./gradlew build` MUST be green before each commit. Kill stray game JVMs by specific PID only (`ps -eo pid,args | grep devlaunch.Main`) — never `pkill`.
9. Keep the codebase conventions: `package-info.java` per new package, server-authoritative logic, action-bar hints (no chat spam), extensive `EclipseMod.LOGGER.info` breadcrumbs on state transitions (this repo's fights are log-verified).
10. `.bbmodel` files are excluded from the jar by `build.gradle` (`exclude("**/*.bbmodel")`) — you MAY commit Blockbench project files next to your geo files for future human editing, but the runtime loads only `.geo.json`/`.animation.json`.

---

## 1. CURRENT-STATE AUDIT

### 1.1 Entity system inventory (all hand-coded vanilla cube models)

| Entity (`entity/`) | Registration | Model/renderer (`client/entity/`) | Notes |
|---|---|---|---|
| `TheOtherEntity` | `EclipseEntities.THE_OTHER`, MONSTER, 0.6×1.8 | vanilla `HumanoidModel` + `TheOtherRenderer`, own texture copy `the_other.png` | Doppelganger; texture is a derivative of the uniform player skin (black eyes + purple face seam) — MUST be regenerated whenever the player skin changes (P6-W12) |
| `GazerEntity` | CREATURE, 0.8×2.1 | `GazerModel` (6 cubes) + emissive face | `VanishWhenSeenGoal`: look-vector dot ≥ 0.985 for 40t → vanish. **This is the in-repo precedent for the Pale Sentinel's inverse "freeze when observed" mechanic** |
| `UmbralStalkerEntity` | MONSTER, 0.9×1.2 | `UmbralStalkerModel` (11 cubes) | Classic goal-based AI: `LeapAtTargetGoal`, `MeleeAttackGoal(1.3,true)`, `HurtByTargetGoal().setAlertOthers()` |
| `DeckhandEntity` | CREATURE, 0.7×1.6 | `DeckhandModel` (7 cubes incl. the bogus "oar" stick) | See §1.2 — subject of bugs 4a–4d |
| `SunmoteEntity` | CREATURE, 0.4×0.4 | fullbright wisp | Orbit driven in `tick()` |
| `HeraldEntity` (boss, day 7) | MONSTER, 2.2×3.2 | `HeraldModel` ~27 cubes + emissive layer | Fully scripted fight in `tick()` (no goals); uses `AltarSanctumBuilder.pillarBases()/pillarTopY()` for line-of-sight cover — **the altar rework must preserve that API's semantics** |
| `FerrymanEntity` (boss, day 14) | MONSTER, 1.4×3.5 | `FerrymanModel` + `FerrymanRenderer.EmissiveLayer` (`RenderType.eyes`, `renderEmissive(...)` skipDraw pattern) | Scripted 3-phase limbo ship fight; drives Deckhand crew via `riseHostile`/`calmCrew`/`reseatFallen`/`countHostileAlive` |
| `HeraldShardProjectile` | MISC, `ThrownItemRenderer` | — | Reusable homing-projectile pattern for the Cultist's shadow bolt |

- Layer definitions + renderers all register in `client/entity/EclipseEntityRenderers.java` (`@EventBusSubscriber(Dist.CLIENT)`).
- Attributes in `EclipseEntities.onEntityAttributeCreation`.
- **No natural biome spawning** — `entity/EclipseSpawner.java` is a server-tick spawner (100t cadence) keyed off `DayScheduler.getDay`, night state, and night events (Pale/Umbral) stored in `EclipseWorldState`. Placement helper `findSurfaceSpawn(...)` (min/max distance from a random player + min distance from every player) is the pattern to copy.
- Textures: procedural via `scripts/placeholder_gen/EntitySkinArtist.java`; UV layouts frozen in `docs/uv/<mob>.md`.
- Bestiary: `client/handbook/tabs/BestiaryTab.java` holds a client-side hardcoded list `Creature(id, introDay)` with lang keys `bestiary.eclipse.<id>.name/.lore` and code-drawn silhouettes. P3 owns that file — P6 delivers data (§4.3).

### 1.2 Limbo ship stack — exact root causes for user bugs 4a–4d

Files: `entity/DeckhandEntity.java`, `limbo/OarAnimator.java`, `limbo/GhostShipBuilder.java`, `limbo/ShipLanterns.java`, `limbo/LimboSeascape.java`, `limbo/StartEventCutscene.java`, `entity/boss/FerrymanEntity.java`, state in `core/state/EclipseWorldState` (`getDeckhandEntities()` / `getOarEntities()` UUID lists).

How the crew works today: `GhostShipBuilder.onServerStarted` → `DeckhandEntity.ensureCrew(limbo)` seats 8 rowers at benches (x ∈ {−12,−4,4,12} × side ∈ {−1,+1}, `deckY = waterlineY+3`), persists their UUIDs in world state. `FerrymanEntity.summon` → `DeckhandEntity.reseatFallen` re-seats benches whose persisted rower is "missing or dead". Ferryman P2 (≤66% HP) → `riseHostile` flips the synced `HOSTILE` flag **only on entities resolved from the persisted UUID list** (`resolveCrew`). Passive deckhands are invulnerable (`isInvulnerableTo` blocks everything but bypass damage), speed 0, never despawn (`removeWhenFarAway=false` + `setPersistenceRequired`).

**Bug 4a — old passive deckhands stand around during the fight (duplicates).** Root cause: **orphaned deckhand entities that are no longer in the world-state UUID list**. Two concrete paths produce orphans:
1. **Entity-section load race in `reseatFallen`** (`DeckhandEntity.java` ~line 247): the guard `limbo.isLoaded(benchPos(...))` checks the *block* chunk, but `limbo.getEntity(uuid)` only resolves once the chunk's *entity section* is loaded — entity storage loads asynchronously after block chunks (`PersistentEntitySectionManager`). On a summon shortly after boot / first limbo entry, `getEntity` returns `null` for a perfectly alive rower → a NEW deckhand is seated and `ids[i]` is overwritten → the old entity finishes loading moments later as an orphan.
2. **World-state resets**: any path that clears/loses the deckhand UUID list while entities persist in the dimension (state file desync, dev resets) makes `ensureCrew` seat a fresh crew next start; the old crew remains as orphans.
Orphans are passive → invulnerable → unkillable, never despawn, and `riseHostile` never touches them: they stand at benches "duplicated" while the listed crew fights. There is **no reconciliation sweep anywhere** that discards deckhands not present in the list.

**Bug 4b — player dies during the fight → "fishermen" stand around forever, unhittable.** Root cause chain (`FerrymanEntity.java`): when the last living fighter dies, either `checkWipe` (all participants dead/banned → `restoreShip` + `discard`) or `tickReset` (no living fighter aboard for 1200t → same) fires. Both call `DeckhandEntity.calmCrew`, which ONLY flips the `HOSTILE` flag: the Javadoc says it literally — *"survivors sag back to idle **where they stand**"*. Consequences: risen crew that chased players around the deck become passive (→ invulnerable = "unhittable") **standing mid-deck at arbitrary positions, in the seated-rowing pose, forever**. There is no return-to-bench behavior anywhere (`calmCrew` doesn't reposition; passive movement speed is 0 so they can't walk back; `reseatFallen` at the next summon only replaces *dead/missing* rowers, never repositions living ones). Additionally, the instant a player dies they are banned (`BanService`) → the target predicate (`!BanService.isBanned`) invalidates them → hostile deckhands freeze in place even before the wipe check lands. Fix requirements: bench-index persistence per deckhand, snap/walk back to bench on calm, plus a server-side self-heal (a hostile deckhand with no valid fight context calms + reseats itself).

**Bug 4c — deckhands hold a "weird staff".** Root cause: `DeckhandModel.createBodyLayer()` — the "oar" is a bladeless **1×22×1 cube** (`texOffs(56,16)`, child of `arm_right`, xRot 0.4, painted plain dark wood per `docs/uv/deckhand.md`). It reads as a staff because it has no blade, no loom, and both arms don't grip it. It's model geometry, not a held `ItemStack` — the fix is a proper two-handed oar (shaft + blade) as bones of the new GeckoLib model (§2.3 Deckhand v2), not an item.

**Bug 4d — water oars move disconnected from the rowers.** Root cause: **two unrelated animation clocks on two unrelated objects.**
- Server `OarAnimator`: 8 persistent `BLOCK_DISPLAY` entities (stripped dark oak log scaled 0.25×3.0×0.25 — vertical poles), positioned 1.5 blocks outboard at `waterline+2`, swung **±25° about the world Z axis** every 30 ticks (60t full cycle) with display interpolation. (Display transformation setters are opened via `accesstransformer.cfg`.)
- Client `DeckhandModel`: arm pull `xRot = −1.2 + sin(ageInTicks·0.08)·0.35` → period ≈ **78.5 ticks**, phase = per-entity `tickCount` (every rower differs).
Different period (60 vs 78.5t), per-entity random phase, different rotation axis (arm pitch vs display roll), and a 1.5–2 block spatial gap between hand and oar. They can never sync. Correct fix: **delete the block-display oars entirely and make the oar part of the deckhand's skeleton** — one clock, one object (§3 P6-W2). `OarAnimator.beginTilt/endTilt` are called by `StartEventCutscene` (t=TILT_TICK) and must keep their signatures (retargeted to deckhand tilt poses or reduced to a no-op shim + cutscene note).

### 1.3 Ghost ship / seascape / lanterns audit (rework constraints)

`GhostShipBuilder.build()` — the current ship is minimal: single-material dark-oak hull 39 long (X, bow +X) × 9 wide, taper via `halfWidthAt(dx)` (4/3/2/1), keel at `waterline−2`, solid deck at `waterline+3`, fence railing, two 9-tall log masts at x=±8 each carrying a **flat black-wool wall** (7 wide across the ship — perpendicular "sails"), plus a starboard spawn platform (z 10..14) + walkway. Guarded once by `EclipseWorldState.isGhostShipBuilt()`. `waterlineY()` samples column (256,256), = 48 with the shipped datapack; fallback 63.

**Hard contracts the ship v2 rebuild must preserve** (all consumed by `FerrymanEntity` + `DeckhandEntity` + `OarAnimator` + `ShipLanterns` + `StartEventCutscene` + `BanService` arrival):
- `HALF_LENGTH=19`, `halfWidthAt(dx)` signature/behavior, `waterlineY()`, deck at `waterline+3`, `NOMINAL_CENTER`, `platformArrivalPos()` (ghost arrival — keep a safe landing).
- Ferryman P3 sink floods `deckY+1..deckY+4` over the `halfWidthAt` footprint (air-only), and `restoreShip` does a **blanket water→air sweep of that same volume** — deck-level superstructure must tolerate that (no legit water blocks in `deckY+1..+4` inside the footprint; waterlogged-block use in that volume is forbidden, lanterns are restored by `ShipLanterns.relightAll`).
- Ferryman hovers at `deckY+1` and sweep/slam checks allow |Δy| ≤ 4 — keep a mostly-open main deck; raised fore/aft decks of +2..+3 are fine, but don't wall off the stern anchor (`STERN_X = −16`) or the mast lanes.
- Deckhand benches at x∈{−12,−4,4,12}, 1 block inboard of the gunwale, both sides — keep those cells clear with open sky to the water (oar reach).
- `ShipLanterns` owns the 4 lantern positions (`positions()`), the ghost re-light channel (60t, r=3), `extinguish/relightAll/relightOne/replaceMissing/allLit/litCount` — v2 may move lanterns but MUST keep exactly 4 and update `positions()` in the same commit.

`LimboSeascape` (wrecks, spires, buoy lane on a 120–260 ring) is fine — untouched.

### 1.4 Altar sanctum audit (rework constraints)

`worldgen/structure/AltarSanctumBuilder.java` builds once at overworld spawn (guarded by `EclipseWorldState.getSanctumAltarPos()`): 3-step blackstone dais, altar at `ground+4`, 8 pillars on r=9 ring (2×2 obsidian base + purpur shafts, heights `{4,6,7,5,6,4,7,5}`, 3 snapped, 4 with lantern arms), floating glass ring y+8 + crying obsidian cardinal ring y+11, amethyst/sculk/candles decor, 4 approach paths, flatten r=12, spawn re-pinned to the south path each start. `SundialPlaza.buildDial/placeShadow` renders the day sundial around it. `SanctumProtection.refresh` protects r=16. **Consumers that must keep working after the floating-island rework:**
- `HeraldEntity` uses `pillarBases(altarPos)` + `pillarTopY(altarPos, k)` for gaze LOS cover and fights inside `ARENA_RADIUS=15` of the altar — pillars must remain an r=9 ring around wherever the altar ends up, and the arena surface must extend ≥ r=16 around the altar (island top must fit it; no falling out of the arena ring into the crater during P3 pull).
- `AltarBlockEntity` / `ReviveRitual` / `FinaleRitual` / `ShardEconomy` / `EclipseSpawner.maintainSunmotes` all key off the altar **block position** — they follow the altar wherever the builder puts it (sunmote orbit radius `6+level` must stay on-island).
- `findExistingAltar` centering contract + `repinSpawn` (players must never spawn inside the dais; with the island, re-pin to the crater rim approach).
- `SundialPlaza` needs a flat disc around the altar — relocates onto the island top.
- The world spawn area is terrain-flattened by `DiscTerrainFunction.surfaceY(OVERWORLD,0,0)` (y70).

### 1.5 Player skin override path

`client/mixin/AbstractClientPlayerMixin` cancels `AbstractClientPlayer.getSkin` at HEAD and returns a static `PlayerSkin` (texture `assets/eclipse/textures/entity/eclipsed_player.png` 64×64 RGBA, cape/elytra `null`, model **WIDE** forced, `secure=true`), registered in `eclipse.client.mixins.json`. Applies to every player incl. F5/inventory. Not config-gated (anonymity-critical). **Skin v2 = replace that PNG byte-for-byte at the same path** (64×64, wide-arm layout, both base + overlay layers) — the mixin needs no change. `the_other.png` must be regenerated as its derivative (§1.1). Ghost/limbo players currently render with the same skin (no translucency).

### 1.6 Registration & wiring map (how P6 avoids shared-file conflicts)

- New entity families register in **their own `DeferredRegister` classes** (one per worker package, e.g. `entity/fog/FogEntities.java`) with their own `EntityAttributeCreationEvent` listeners via `@EventBusSubscriber` — zero edits to `EclipseEntities.java`.
- New renderers register in **their own `@EventBusSubscriber(Dist.CLIENT)` classes** — zero edits to `EclipseEntityRenderers.java` (GeckoLib needs no layer definitions). Exception: P6-W2 removes the Deckhand layer/renderer lines from `EclipseEntityRenderers.java` (sole P6 owner of that file).
- New payloads register via a static `@SubscribeEvent` on `RegisterPayloadHandlersEvent` in the owning package (unique registrar version string per worker, e.g. `event.registrar("p6w3")`) — zero edits to `network/EclipsePayloads.java`.
- New blocks/items for the door register in `limbo/door/DoorRegistry.java` (own `DeferredRegister<Block>` / `<Item>` / `<BlockEntityType>`), wiring line listed per constraint 3.
- `EclipseWorldState` is cross-planner shared — P6 workers use only its existing public getters/setters (`setOarEntities(List.of())` for oar cleanup) and otherwise persist via **entity NBT, scoreboard-style command tags (`entity.addTag("eclipse_sanctum_orbital")` + tag scans), or their own `SavedData`**.

### 1.7 Asset/texture pipeline as-is

Java single-file generators under `scripts/placeholder_gen/` (run `java scripts/placeholder_gen/X.java`), UV docs under `docs/uv/`, final-art replacement contract in `docs/ASSET_MANIFEST_V2.md` (exact path + canvas size, byte-for-byte drop-in). P6 extends this with a python pipeline for GeckoLib assets (§2.2) because geo files carry their own per-cube UVs — the painter parses the geo instead of a hand-written UV doc. python3 + Pillow verified present on the VM.

---

## 2. DESIGN

### 2.1 GeckoLib adoption

**Version (verified 2026-07-23 via Modrinth API):** GeckoLib **4.9.2** for NeoForge 1.21.1 (published 2026-07-01; 4.x is the correct line for 1.21.1 — GeckoLib 5 targets 1.21.2+). Maven: repo `https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/`, artifact `software.bernie.geckolib:geckolib-neoforge-1.21.1:4.9.2`.

**Bundling (P5 owns; P6-W1 verifies/coordinates)** — mirror the Veil jar-in-jar pattern in `build.gradle`:

```groovy
repositories {
    maven {
        name = 'GeckoLib'
        url = 'https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/'
        content { includeGroup 'software.bernie.geckolib' }
    }
}
dependencies {
    jarJar(implementation("software.bernie.geckolib:geckolib-neoforge-${minecraft_version}")) {
        version { strictly "[4.9.2,)"; prefer "4.9.2" }
    }
}
```

plus `geckolib_version=4.9.2` in `gradle.properties` and a `required` dependency entry in `META-INF/neoforge.mods.toml`. Open range so any other pack mod shipping GeckoLib dedupes to the highest version. GeckoLib runs client+server (dedicated server safe).

**Resource path conventions (verified by decompiling `DefaultedGeoModel` in the 4.9.2 jar — note these are the OLD-style paths, NOT the `geckolib/models` layout the GeckoLib-5 wiki shows):**

| Asset | Path |
|---|---|
| Geometry | `assets/eclipse/geo/entity/<id>.geo.json` (blocks: `geo/block/<id>.geo.json`) |
| Animations | `assets/eclipse/animations/entity/<id>.animation.json` |
| Texture | `assets/eclipse/textures/entity/<id>.png` |
| Emissive glowmask | `assets/eclipse/textures/entity/<id>_glowmask.png` (same canvas size — `AutoGlowingTexture` enforces matching dimensions and appends the literal `_glowmask` suffix) |

**Entity pattern (GeckoLib 4.x, verified API surface):**

```java
public class FogRevenantEntity extends Monster implements GeoEntity {
    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    @Override public AnimatableInstanceCache getAnimatableInstanceCache() { return geoCache; }

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, "base", 4, state -> {
            if (state.isMoving()) return state.setAndContinue(WALK); // RawAnimation.begin().thenLoop("animation.fog_revenant.walk")
            return state.setAndContinue(IDLE);
        }));
        controllers.add(new AnimationController<>(this, "action", 0, state -> PlayState.STOP)
                .triggerableAnim("cast_blind", CAST)     // PLAY_ONCE
                .triggerableAnim("death", DEATH));
    }
}
// server-side, anywhere in fight/AI code:
this.triggerAnim("action", "cast_blind");
```

**Renderer pattern:** `class FogRevenantRenderer extends GeoEntityRenderer<FogRevenantEntity> { public FogRevenantRenderer(Context ctx) { super(ctx, new DefaultedEntityGeoModel<>(ResourceLocation.fromNamespaceAndPath("eclipse", "fog_revenant"), true)); } }` — the boolean enables automatic head-bone tracking (bone MUST be named `head`). Emissive: `addRenderLayer(new AutoGlowingGeoLayer<>(this))` + ship a `_glowmask.png` (paint ONLY the emissive pixels, transparent elsewhere). No layer definitions, no `bakeLayer` — registration is a one-liner in the family's `RegisterRenderers` subscriber. Blocks use `GeoBlockRenderer` + `DefaultedBlockGeoModel`.

**Geometry/animation file format** (what "real Blockbench models" means here — files authored in this format open in Blockbench directly, Bedrock-model project type):
- `.geo.json`: `format_version "1.12.0"`, `minecraft:geometry` array with `description` (`identifier: "geometry.<id>"`, `texture_width/height`), `bones[]` each with `name`, `pivot`, optional `parent`, `rotation`, `cubes[]` (`origin`, `size`, `uv` box-UV origin or per-face UV, optional `inflate`, `mirror`).
- `.animation.json`: `format_version "1.8.0"`, `animations: { "animation.<id>.<name>": { "loop": true|false|"hold_on_last_frame", "animation_length": seconds, "bones": { "<bone>": { "rotation"/"position"/"scale": { "0.0": [x,y,z], "0.5": {"post":[...], "lerp_mode":"catmullrom"} } } } } }`. Degrees for rotation, model units (px) for position. Molang expressions allowed in values (e.g. `"math.sin(query.anim_time*90)*3"`).

**Bone naming conventions (frozen):** root bone `root`; head-tracked bone `head`; attack limbs `arm_left/arm_right` or `leg_fl/fr/bl/br`; emissive-only geometry grouped under bones prefixed `glow_` (helps the painter, §2.2). Animation names frozen per mob in §2.3 sheets: minimum set `idle`, `walk`, `attack`, one `special`, `death` (user requirement).

**Migration policy for existing mobs:** migrate **only the Deckhand** (P6-W2 — it must be remodeled anyway for the oar, its AI is trivial, and the pose blend maps 1:1 to two looped anims + a rise trigger). Keep The Other (must stay vanilla `HumanoidModel` to be indistinguishable from players), Gazer/Stalker/Sunmote (done, tested, cheap), and Herald/Ferryman (their models are driven frame-by-frame by fight code — migration risk exceeds value; new bosses showcase GeckoLib instead).

**Death animations:** GeckoLib mobs keep the vanilla 20t red-flash/tip-over unless suppressed. Convention for P6 mobs: override `tickDeath()` for a scripted window (Ferryman precedent, 40–70t), trigger the `death` anim on the `action` controller from `die()`, and suppress the vanilla flip in the renderer via a `setupRotations`-style guard (`GeoEntityRenderer` respects `isShaking`/death rotation — override `getDeathMaxRotation(entity) → 0` for upright deaths).

### 2.2 Authoring pipeline (models → animations → textures → in-game validation)

No Blender MCP is available in this environment; the pipeline is **direct authoring of Blockbench-format JSON** (which IS producing real Blockbench models — they open in Blockbench), validated by loading them in-game. P6-W1 builds the shared tooling; every mob worker uses it:

1. **Silhouette sketch (in doc):** every mob sheet in §2.3 fixes proportions in model units (16 px = 1 block) before any JSON is written.
2. **Author `geo.json`** per conventions above. Run `python3 scripts/geckolib_gen/validate_geo.py <file>` (P6-W1): checks format_version, unique bone names, parent references, per-cube UV rects inside `texture_width/height`, prints an ASCII bone tree + cube count. Fail = fix before continuing.
3. **Author `animation.json`**; validator also lints animation files (bone names must exist in the geo; loop flags; length vs last keyframe).
4. **Textures:** `scripts/geckolib_gen/paint_lib.py` (P6-W1) parses the geo, computes every cube's box-UV face rects, and paints them via material callbacks (deterministic hash dither, per-face directional shading — top lit / bottom dark, 1px inner outline; port the technique of `EntitySkinArtist.java` to python/Pillow). Per-mob driver script `scripts/geckolib_gen/mobs/<id>.py` declares the palette + per-bone materials + emissive bones; running it writes `<id>.png` AND `<id>_glowmask.png` (glowmask = emissive pixels at full brightness, all else transparent; `glow_*` bones auto-included). Deterministic seed → reproducible bytes. AI art may later replace the PNG at the same path/size.
5. **In-game validation loop (mandatory, every mob):** `./gradlew build` → `runClient` → world → `/summon eclipse:<id> ~2 ~ ~` → screenshot front/side/¾ + one screenshot or clip per animation (walk by luring, attack by getting hit, special via its trigger condition, death via `/kill`). Missing-asset errors log clearly (GeckoLib names the missing path). Iterate until the silhouette matches the sheet.
6. **UV/design doc:** commit `docs/uv/<id>.md` in the existing style (art brief + palette hexes + emissive regions + generator command) so the later art pass has the same contract Batch D had.

### 2.3 Mob roster — per-mob design sheets

Roster overview (7 new mobs — 9 skins — + 1 remodel + 2 bosses):

| id | Family | Worker | Category | Size (w×h) | Role |
|---|---|---|---|---|---|
| `drift_lantern` | ambience (limbo) | W1 | CREATURE | 0.6×1.1 | pipeline pilot; limbo sea ambience |
| `deckhand` (remodel) | limbo crew | W2 | CREATURE | 0.7×1.6 | rower/fighter, oar in skeleton |
| `fog_revenant` | fog storm | W7 | MONSTER | 0.7×2.2 | fog-consumed wraith, blind burst |
| `storm_hound` | fog storm | W7 | MONSTER | 0.9×1.1 | lightning lunge pack hunter |
| `fog_colossus` | fog storm elite | W8 | MONSTER | 1.6×3.4 | slow tank, slam shockwave |
| `glitched` (3 kinds) | glitch rings | W8 | MONSTER | per kind | datamosh variants, ring-gated |
| `pale_sentinel` | pale garden | W9 | MONSTER | 0.8×2.6 | moves only when unseen |
| `eclipse_cultist` | dungeons | W10 | MONSTER | 0.6×1.9 | spawner caster mob |
| `rift_warden` | boss | W10 | MONSTER | 1.1×3.0 | dungeon mini-boss |
| `fog_tyrant` | boss | W11 | MONSTER | 2.4×4.2 | fog-storm apex boss |

All get `clientTrackingRange(10)`, attributes via family registrar, en+de names (`entity.eclipse.<id>`), bestiary entries (§4.3), and the anim minimum set. Drops reference P4 economy items **by registry lookup with fallback** (`BuiltInRegistries.ITEM.get(ResourceLocation.fromNamespaceAndPath("eclipse","<item>"))`, fallback `umbral_shard`) — zero compile-time coupling to P4.

**`drift_lantern` — Drift Lantern / Treiblaterne (W1 pilot).** Silhouette: a soul-lantern "jellyfish" — glass-cage head (6×6×6 px) with inner `glow_flame` cube, 4 hanging kelp-chain tendrils (2×8×1, staggered z). Palette: iron `#3B3F46`, glass `#9FB8C4` @ 40% alpha faces, soul flame `#7FE3D2`, tendrils `#2E4A44`. Anims: `idle` (bob ±2px, tendril sway molang sin), `walk` (=drift, stronger sway), `attack` (unused, flare), `special:flicker` (trigger; flame scale pulse), `death` (tendrils collapse, flame gutters, 30t). AI: no goals; `tick()` drift like `SunmoteEntity` around a slow random waypoint 0–6 above the limbo water; limbo-only (discard outside like Deckhand). 6 HP, killable → 1 glowstone dust. Spawn: W6 maintains 6–10 along the buoy lane (x 32..240) when players are in limbo. Emissive: flame + faint cage rim.

**`deckhand` v2 (W2 remodel — same entity id, same registration).** Silhouette: keep the hunched hooded rower (robe base, torso, head+hood, arms) but add: proper **two-handed oar bone chain** (`oar_loom` in hands → `oar_shaft` 2×30×2 angled outboard/down → `oar_blade` 6×10×1) and 2 rope-belt tatters. Palette: keep `docs/uv/deckhand.md` (waterlogged gray-greens `#3A4038/#2E3430/#262B24`, wood `#5A452E`, blade edge kelp `#22301F`); NO emissive. Anims: `row` (loop, **exactly 3.0s = 60t**, both arms + oar sweep: catch → pull → feather → return; blade dips below gunwale line at pull), `idle_sag` (hostile-calm standing sag), `rise` (trigger, 1.25s bench → standing claw), `walk` (shamble), `attack` (two-beat claw, trigger from `MeleeAttackGoal` via `triggerAnim`), `death` (crumple, 30t). Row phase sync: controller animation progress is client-side per entity — sync by setting the `base` controller's anim speed handler so `row` restarts on a shared clock (`level.getGameTime() % 60`), or simpler: all rowers `forceAnimationReset()` on a 60t game-time boundary observed client-side in the renderer's `preRender`. Acceptance: all 8 rowers visibly stroke together, blades entering water.

**`fog_revenant` — Fog Revenant / Nebel-Wiedergänger (W7).** Silhouette: tall thin wraith; torn robe cone (10×20×8 tapering), no legs (hover 4px), rib-cage of fog "coral" growths on one shoulder (asymmetry!), long claw arms (3×14×3), small hooded skull head; 3 `glow_` fog wisps orbit bones. Palette: robe `#23262E`, fog growth `#5E6B7A` → tips `#9DB3C9`, claws bone `#C9C4B4`, glow wisps `#8FD5E8`. 30 HP, dmg 5, speed 0.26 (hover-drift; `setNoGravity` false but slow-fall). AI: FloatGoal, custom `DriftStrollGoal`, `MeleeAttackGoal(1.1,false)`, `NearestAttackableTargetGoal<Player>`, HurtByTarget; custom `FogBlindBurstGoal`: every 240–320t when target within 6: 30t channel (`special:cast_blind` trigger, wisps flare) → r=5 AoE: Blindness 4s + Slowness II 3s + `S2CQuasarPayload` fog puff (existing emitter until P2 delivers `eclipse:fog_burst`, §4.2). Anims: `idle` (hover sway, wisps orbit), `walk`, `attack` (claw rake), `cast_blind`, `death` (disperse upward into wisps, 40t, upright). Spawn: fog storm areas only (§2.8). Drops: 1–2 umbral_shard + `fog_essence` (P4 lookup, fallback shard). Emissive: wisps + eye slits.

**`storm_hound` — Storm Hound / Sturmhund (W7).** Silhouette: lean quadruped (body 8×7×16), swept-back head with split jaw, **lightning-rod spines** (3 `glow_spine` shards along back), whip tail; crackling hackles. Palette: storm-grey fur `#3A4148` dithered `#2C3238`, jaw `#1E2126`, spines/veins electric `#9FE8FF`, inner mouth `#D9F6FF`. 24 HP, dmg 4, speed 0.34. AI: stalker pack (copy Umbral Stalker goal set: leap, melee 1.3 true, alert-others hurt goal) + custom `ChargedLungeGoal`: when target 6–14 blocks away & LOS & 160t cooldown: 20t windup standing still (`special:charge_windup`, glowmask ramps via anim scale on `glow_spine`) → 12-block dash line (0.9/t velocity), first entity hit takes 6 dmg + Slowness IV 1s ("static-locked") + crackle particles (`ELECTRIC_SPARK`); miss → 2s self-stagger (counterplay). Anims: `idle`, `walk` (=run gallop), `attack` (bite), `charge_windup`, `lunge` (hold_on_last_frame during dash), `death` (side collapse + spine flicker-out). Spawn: fog storms, packs 2–3. Drops: 0–2 umbral_shard, 25% `storm_gland` (P4 lookup).

**`fog_colossus` — Fog Colossus / Nebelkoloss (W8, elite).** Silhouette: hulking round-shouldered brute overgrown by the fog — body is cracked stone `#3E444D` with glowing fissures, fog-coral shelf growths on back/shoulders `#77879B→#B7C9DC`, tiny head sunk between shoulders, massive flat-knuckle arms (walks half-gorilla). 80 HP, dmg 10, speed 0.22, KB resist 1.0. AI: melee brute + `GroundSlamGoal` every 200t when target ≤ 5: 25t telegraph (`special:slam` raise, fissures flare) → r=6 shockwave 8 dmg + launch (`player.setDeltaMovement(...)`, `hurtMarked=true` — SoftBorder/Ferryman pattern) + ring of `CAMPFIRE_COSY_SMOKE`+`SONIC_BOOM` particle stamp; jumpable if you're outside r=3 (damage falloff by distance). Anims: `idle` (heavy breathing, shelf sway), `walk` (knuckle gait), `attack` (backhand), `slam`, `roar` (trigger on first target), `death` (forward collapse, 50t, screen-shake `S2CShakePayload.shake(0.6f,15)` nearby). Cap 1 per storm. Drops: 3 umbral_shard + 1 `fog_essence`×2.

**`glitched` — Glitched Variant system / Glitch-Kreatur (W8).** ONE entity class `GlitchedVariantEntity` (`eclipse:glitched`), synced byte `KIND` ∈ {`HUSK`, `HOUND`, `TICK`} set at spawn (spawner API + `readAdditionalSaveData`). One `GeoModel` subclass whose `getModelResource/getTextureResource/getAnimationResource` switch on the entity's kind (GeckoLib passes the animatable instance): geos `geo/entity/glitched_husk|glitched_hound|glitched_tick.geo.json`. Design language shared: bodies look like the vanilla silhouette **datamoshed** — cubes split and offset 1–3px off-axis (a shoulder floats detached, half the face is displaced), `glow_seam` slivers between displaced parts. Textures: base palettes desaturated `#4A4A52` family with RGB-split fringes (`#FF3B6B`/`#37F2E5` 1px offsets) painted by the shared painter's `glitch()` material; **renderer swaps between `<id>.png` and `<id>_alt.png` for 2–4t bursts every 40–80t** (override `getTextureResource(animatable)` on `level.getGameTime()` hash) for a datamosh flicker without animated textures. Kind stats: HUSK 30 HP/5 dmg/0.27 (humanoid, 1.9h); HOUND 24/4/0.35 (quadruped, reuses stalker proportions with glitch offsets); TICK 12/3/0.42 (0.6×0.5 skittering shard-mite, spawns in 3s). Shared anims per kind file: `idle` (micro-jitter: 1-frame position pops via stepped keyframes — no smooth lerp, deliberately), `walk`, `attack`, `special:glitch_blink` (trigger: 4-block random offset teleport with pair of `REVERSE_PORTAL` bursts, 200t cd, HUSK/HOUND only), `death` (frame-freeze then collapse into `glow_seam` slivers). Glitch particles/FX: P2 delivers `eclipse:glitch_pop` emitter (§4.2); until then `REVERSE_PORTAL`+`WHITE_ASH`. Spawn: only in rings opened after day 8 (§2.8). Drops: `glitch_shard` ×1–2 (P4 heart-crafting economy input — P4 owns item + recipes; fallback umbral_shard).

**`pale_sentinel` — Pale Sentinel / Fahler Wächter (W9, Creaking-like for P1's Pale Garden port).** Silhouette: 2.6-block lanky tree-revenant of pale-oak: log-grain torso `#D8D2C4`/`#B9B2A2` with dark bark fissures `#575044`, twig-antler crown, long thin arms past knees ending in root-claw hands, legs like stilts, **orange-ember eyes `#FF9A3C`** (the only glow). Anims: `idle` (utterly still — 0.5px breathing), `walk` (fast jerky stride 0.5s cycle — unsettling), `attack` (overhead double-claw), `special:freeze` (instant — see below), `death` (crumble: torso splits, 35t, drops to a bark pile). **Signature mechanic (server-side, Gazer-precedent inverse):** each tick, scan non-spectator living players within 32 blocks; the sentinel is OBSERVED if any player has line-of-sight (`level.clip` ClipContext COLLIDER) AND `player.getViewVector(1f).normalize().dot(normalize(sentinelEyePos − playerEyePos)) ≥ 0.5` (wide cone — deliberately forgiving so it freezes reliably on-screen). Observed → freeze: navigation stopped, body/head rotation locked, `AnimationController` speed handler returns 0 (true mid-pose freeze — juicier than a freeze pose), attack goal gated off. Unobserved → speed 0.45 pursuit. Hysteresis: 5t grace both ways to avoid strobe at the cone edge. Damage while frozen: takes it normally (40 HP, dmg 6) but emits pale petal burst + 1-block root-step flinch backward. Extra dread: while frozen and observed within 8 blocks, faint `WOOD_STEP` creaks at the player's ear every ~60t (private sound packet — `EclipseSpawner.howlAround` pattern). Night-only activity; day → burrows (despawn with bark particles). Spawn: Pale Garden biome/ring only (P1, §4.1); cap 2. Drops: 2 `pale_resin` (P4 lookup, fallback umbral_shard).

**`eclipse_cultist` — Eclipse Cultist / Eklipsen-Kultist (W10, dungeon spawner mob).** Silhouette: kneeling-height robed figure (mirrors the player-skin hood language — same charcoal robe family as eclipsed players, `#26232E` with `#B98CFF` trim), floating rune page bones around left hand (`glow_rune` ×3), ritual knife. Anims: `idle` (=`idle_chant`, runes orbit, sway), `walk` (hunched scurry), `attack` (knife swipe), `special:cast` (trigger, 20t: runes flare + both arms raise), `death` (kneel forward, hood empties — cloth collapses flat, 30t). AI: `RangedShadowBoltGoal` (hold 8–14 distance, every 60t cast `ShadowBoltProjectile` — new small projectile copying `HeraldShardProjectile`'s homing-lite pattern, 5 dmg, `ThrownItemRenderer` fullbright with umbral-shard sprite scaled 1.0) + melee panic swipe when crowded (≤2 blocks), `NearestAttackableTargetGoal<Player>`, avoid-water stroll. 20 HP, dmg 3, speed 0.3. Spawner-friendly: MONSTER, no persistence quirks, despawns normally (dungeon spawners re-supply). Drops: 0–1 umbral_shard, 10% `cultist_sigil` (P4 lookup). Bestiary intro day 9.

### 2.4 Boss fight designs

Both bosses follow the house pattern (audited from Herald/Ferryman): `Monster` subclass, **no vanilla goals — everything scripted in `tick()`**, `ServerBossEvent` + `S2CBossbarStylePayload(THEME_BOSS)` on `startSeenByPlayer`, HP-fraction phases with `EntityDataAccessor` synced pose flags → GeckoLib triggerable anims instead of hand-lerped pose weights, player-count HP scaling snapshotted at summon, participant tracking + wipe/reset handling, scripted `tickDeath` collapse, `LOGGER.info` breadcrumbs on every transition, custom-name → bossbar name passthrough, `forcePhase(int)` test hook (health snap — works with `/data` if needed; no command edits).

**`rift_warden` — The Rift Warden / Der Risswächter (W10, MUST). Mid-event dungeon mini-boss (day 9–10, P1's stronghold-edge dungeon).**
- **Stats:** 200 HP × (1 + 0.35·(n−1)) for n living players within 32 at summon; dmg 7 (blade), armor 4, KB resist 1.0. Arena: self-pinned r=12 circle at own summon position (`ensureFightInitialized`); works in any ≥ 20×20 flat room; players beyond r=14 get the SoftBorder-style inward impulse; damage from outside the ring is deflected (Herald pattern — no doorway cheese in a dungeon).
- **Silhouette (128×128 tex):** 3-block vertically-split knight — the LEFT half is polished obsidian armor `#1B1D26`/`#2E3242`, the RIGHT half is missing, replaced by a `glow_rift` void-tear volume `#B98CFF→#5E2EA8` with drifting shard bones; single horned helm, twin curved rift-blades (bone chain per arm). Emissive: rift half + blade edges.
- **P1 "Blades" (100–50%):** deck-stalker melee (Ferryman movement style, hover 1 above floor): telegraphed **triple sweep combo** (`special:sweep_combo`, 20t raise + `TRIDENT_RIPTIDE_3`; 3 hits over 30t, 5+5+7 dmg frontal arcs — sidestep between beats); **Rift Step** every 200t: `blink_out` (10t, collapses into the rift half) → reappears 8 blocks BEHIND the current target (`blink_in`, glitch tear FX: `REVERSE_PORTAL` implosion; P2 emitter `eclipse:rift_tear` later) → immediate single sweep. Blink is telegraphed by 15t of rising `GLASS` chimes at the destination (fairness cue: audio-place the packet at the destination point).
- **P2 "Rifts" (≤50%):** adds every 300t up to 3 **void rift anchors** (small invisible marker entities or the boss's own tracked BlockPos list + client FX): each pulses every 80t — r=10 pull 0.06/t for 60t then a jumpable r=4 burst (6 dmg, `SOUL_FIRE_FLAME` floor markers, Herald ring pattern); each active rift spawns 1 glitched TICK every 200t (cap 4 adds). Destroying adds is the pressure valve. Blades keep coming at 1.5× cooldown.
- **Soft enrage:** after 6 min, rift pulse interval −25%.
- **Wipe/reset:** Herald rules (participants all dead/banned → announce lite; nobody within 24 for 60s → heal + despawn).
- **Death:** 60t scripted implosion — blades plant, armor half kneels, rift half expands and swallows the body inward (`death_implode`, upright, `getDeathMaxRotation=0`), final `S2CShakePayload.shake(0.8f, 18)` + soul burst. Drops: 1 `rift_core` (P4 progression/heart economy; fallback: 4 umbral_shard) + 2 umbral_shard at each participant's feet (Herald pattern). Bossbar: PURPLE, PROGRESS; name `entity.eclipse.rift_warden.bossbar`.
- **Anims:** `idle` (hover, rift half boils), `stride`, `sweep_combo`, `blink_out`, `blink_in`, `summon_rift`, `stagger` (post-blink miss), `death_implode`.

**`fog_tyrant` — The Fog Tyrant / Der Nebeltyrann (W11, SHOULD; apex of a mature fog storm).**
- **Stats:** 350 HP × (1 + 0.4·(n−1)); dmg 9; slow (0.2) but relentless; fire-immune; 2.4×4.2.
- **Silhouette (128×128):** the Fog Colossus language taken monarch-tier — a mountain-shouldered husk whose upper half dissolves into a permanent crown of storm-fog (layered `glow_crown` wisp bones), chest cavity holds a caged `glow_heart` storm core `#9FE8FF`, arms end in condensed-fog cleaver fists. Palette: wet slate `#2F343C`, fog banks `#8496AB`, core/lightning `#CFF3FF`.
- **P1 "Veils" (100–66%):** on entry places 4 **fog banks** (marker-entity clusters w/ `CAMPFIRE_SIGNAL_SMOKE` columns; P2 upgrade `eclipse:fog_bank` volume later) on a r=10 ring; every 140t **Storm Call**: telegraph ring on a targeted player's position (30t, `ELECTRIC_SPARK` circle) → lightning strike 8 dmg (visual `LightningBolt` with `setVisualOnly(true)`, damage applied manually inside r=2.5 — precise + no fire grief). Melee cleaver swing for huggers.
- **P2 "Consume" (66–33%):** every 400t channels 100t on the nearest surviving bank (`special:consume_channel`, fog streams boss-ward): completes → bank consumed, boss heals 40; **interrupted if ≥1 player stands INSIDE that bank's r=3 for the final 60t** ("anchor the fog") → channel fails, boss staggered 80t taking ×1.5 damage (`stagger` anim). Banks NEVER respawn — consuming/anchoring all 4 permanently removes the heal.
- **P3 "Frenzy" (≤33%):** alternates storm-hound-style **triple lunge chains** (3 dashes with 15t gaps, 7 dmg each, dodgeable sideways) and **Blind Nova** every 200t (r=8, 30t telegraph as the crown collapses inward, Blindness 3s + 4 dmg — break LOS or leave radius); at 25% summons 2 storm_hounds (once).
- **Wipe/reset:** Ferryman rules; reset also despawns leftover banks/hounds.
- **Death:** 70t `death_stormburst` — core cage shatters first (glowmask gutter, Ferryman `isLanternFlameLit` pattern), body sags to knees, crown fog disperses upward, final thunderclap + shake. Drops: 1 `storm_heart` (P4; fallback 6 umbral_shard) + 3 umbral_shard per participant.
- **Summoning:** P1 flags mature storm centers (§4.1) and calls `FogTyrantEntity.summon(level, pos)`; ALSO fully functional via `/summon eclipse:fog_tyrant` anywhere (self-pins arena r=16, spawns its own banks) so it ships/testable independent of P1 timing.
- **Anims:** `idle` (crown boil, heavy breath), `stalk`, `strike_call`, `consume_channel` (loop), `lunge`, `nova`, `stagger`, `attack` (cleaver), `death_stormburst`.

### 2.5 Ghost ship v2 + Respawn Door

**Ship v2 (W3).** Same footprint contract (§1.3) — everything from the keel up is rebuilt for silhouette and detail while `halfWidthAt`/deck height stay binding:
- **Hull:** 3-tone shipwright mix — dark oak planks + `dark_oak_log` ribs every 4x + `stripped_dark_oak` wale stripe at waterline+1; mud-brick/blackstone barnacle dither below waterline; stair-block bow flare and stern tuck (stairs along the taper cells so the hull curves instead of stepping); proper **sternpost + curved bowsprit** (logs + fences angling up from the bow tip, 6 long) with a **bone-block/skull figurehead**.
- **Decks:** main deck as today (open — Ferryman constraint); raised **forecastle** (+2, x 14..19) and **quarterdeck** (+3, x −19..−13) with stair transitions and fence-and-chain railings; the stern anchor cell (x=−16, z=0) stays open sky (Ferryman kneels there).
- **Masts & sails:** two masts get yards (horizontal stripped logs at +5 and +8) carrying **angled tattered sails**: wool panels stepped 1 block per row in X (reads as wind-filled instead of a flat wall), hash-eaten holes (LimboSeascape `snappedMastRaft` technique), black wool + gray wool 80/20 dither; loose **chain rigging** from mastheads to gunwales; a crow's nest (fence ring) on the aft mast.
- **Dressing:** oarlock notches at the 8 bench cells (trapdoor + chain), rope coils (brown-carpet-on-fence? no — use stripped-log + trapdoor barrels), 2 soul-fire deck braziers (soul soil + soul campfire — NOT in the sink volume issue: campfires are fine, they're not water), stern great-lantern cluster (the 4 `ShipLanterns` relocate: 2 on masts, 1 forecastle, 1 quarterdeck — update `positions()`), captain's-cabin front wall under the quarterdeck facing the bow: **this is where the Respawn Door lives**, flanked by purple-stained-glass portholes.
- **Migration:** add `ghostShipVersion` guard **without touching `EclipseWorldState`**: version marker via a block signature check (e.g. presence of the bowsprit tip fence at a known pos) or a small own `SavedData` (`limbo/door/ShipVersionData`). Rebuild = clear old volume (keel..deck+12 over footprint+2) then build v2, then `ShipLanterns.ensurePlaced` + `DeckhandEntity` reseat. Skip rebuild if a live `FerrymanEntity` exists (log + retry next start).
- **Regression tests (mandatory):** full Ferryman fight on v2 (P1 sweep/slam, P2 crew+lanterns, P3 sink flood + restore drain) — the sink volume must flood/drain cleanly around new deck furniture.

**Respawn Door (W3).** The imposing 3-wide × 5-tall double door in the quarterdeck bulkhead, purple light spilling through the seam — the death/respawn stage prop (flow logic is P3/P4).
- **Implementation: custom block + block entity + GeckoLib block model** (block displays can't do doors justice and P2 can't shader-light an entity cluster as cleanly). `limbo/door/RespawnDoorBlock` (controller, renders nothing itself — `RenderShape.INVISIBLE`), `RespawnDoorFillerBlock` (invisible, collidable, 14 filler positions), `RespawnDoorBlockEntity` (GeoBlockEntity: anims `closed_idle` (seam pulse), `open` (hold_on_last_frame), `close`, `locked_shudder` (trigger)), `DoorRegistry` (own DeferredRegisters: 2 blocks, 1 BE type, 1 BlockItem for admin placement), `RespawnDoorRenderer extends GeoBlockRenderer` + `DefaultedBlockGeoModel` (`geo/block/respawn_door.geo.json`, 128×128 texture + `_glowmask` for the seam/glyphs: `#B98CFF` blaze).
- **Model:** twin 24×64×4-px leaves with eclipse-glyph relief, blackened-oak + tarnished silver banding, oversized ring handles, arched header with a glowing eclipse disc; light spill is glowmask + (P2) a Veil area light hook (§4.2).
- **State model:** server-authoritative global `DoorState { SEALED, CLOSED, OPEN }` on the BE (synced via BE data). **Per-viewer rule rendered client-side:** ghosts always SEE it closed — the renderer checks the local viewer (`Minecraft.player` team `eclipse_ghosts` OR `ClientStateCache.lives <= 0`) and renders the closed pose regardless of global OPEN. This needs zero per-player networking. A tiny payload `S2CDoorCuePayload(pose)` (registrar `p6w3`) lets P3/P4 play a personal open sequence for one player (their client alone animates `open` + walk-through moment during revive).
- **Server API for P3/P4** (`limbo/door/RespawnDoorApi`): `setGlobalState(ServerLevel, DoorState)`, `playOpenFor(ServerPlayer)` (sends cue payload + sound), `doorFrontPos(ServerLevel)` (a `BlockPos` + facing for respawn/cinematic placement). Collision: fillers stay solid to ghosts always (they see it closed AND can't pass); when P4's flow opens it for a revived player, P4 teleports them through via the API (no per-player collision hacking in v1 — documented limitation).

### 2.6 Altar / spawn island rework (floating sanctum)

**Concept (W4 + W5):** after the intro, the sanctum is no longer parked on flat ground — the whole altar plateau has been **ripped out of the disc and hangs 14 blocks up**, with the wound (crater) below and slow orbiting debris around it. References to channel (build vocabulary, not files): SkyBlock-spire shrine builds — inverted-cone underside with hanging roots and chains; Hollow-Knight-style pale monuments — thin tall silhouettes + glow accents; classic "eclipse ziggurat" concentric ring composition. Grief-safe: it all sits inside `SanctumProtection` r=16 (W4 may bump to r=18 + vertical range).

- **Island (W4):** ellipse ~r=16/14 top surface at `groundY+14`; top keeps the v2 sanctum layout language (3-step dais, altar at top+4 → the absolute altar Y moves up; every consumer keys off `getSanctumAltarPos()` so this is transparent); **8 pillars stay on the r=9 ring** (Herald LOS contract intact, heights unchanged); `SundialPlaza` dial re-stamped on the island top. Underside: 3 inverted taper layers (grass/dirt lip → deepslate/blackstone mix → bedrock-black tip) with hanging **chains + amethyst clusters + dripping crying obsidian**, 2 "torn root" log strands reaching down toward the crater (NOT connecting — 3-block gap, emphasizes the rip).
- **Crater (W4):** below, r=12 bowl 4 deep into the flattened ground: exposed strata (coarse dirt/tuff/blackstone dither), rubble boulders (2–3 block clumps), scorch ring (blackstone + soul soil flecks), a few snapped pillar stumps fallen at angles, sparse `glow_lichen`. World spawn re-pins to the **crater rim south approach** (repinSpawn update), where a **switchback bridge** (blackstone slabs + fence, 2 flights) + a fallen-pillar ramp climb to the island lip — mind: players must reach the altar on foot Day 1.
- **Orbitals (W5):** 12 block displays (cap 16) on 2 counter-rotating rings (r=13 at island mid-height, r=9 above the glass halo): purpur blocks, obsidian shards (scaled 0.4–0.7), 2 crying obsidian, 2 amethyst clusters; server animator `SanctumOrbitals` (OarAnimator pattern: interpolated transform push every 40t = orbit step ~3°/s + sin bob ±0.4, per-display phase offset; suspend when no player within 64). Persistence WITHOUT `EclipseWorldState`: displays carry command tag `eclipse_sanctum_orbital`; on start, tag-scan the loaded spawn chunks, re-attach, top up to 12, discard extras — self-healing, no state schema change. P2 may add shader flourish on top (§4.2); ownership: P6 owns placement + motion, P2 owns any bloom/light.
- **Trigger/timing ("after the intro"):** rebuild runs at `ServerStartedEvent` **only when overworld stage ≥ 1** (post-intro fusion; `WorldStageService.stage(server, DiscProfile.OVERWORLD)`), plus a `WorldStageService.StageListener` so a live stage-0→1 transition upgrades the sanctum the moment the intro completes. Guarded by its own `SanctumVersionData` SavedData (v1 ground sanctum → v2 island): clears the old sanctum volume (r=13, ground..+16) before building.
- **Iterative build-and-review loops (mandatory, both W4 and W5):** each worker runs ≥2 full iterations of: build → `runClient` → screenshot canonical angles (N ground level, S bridge approach, top-down, below-crater looking up; W5 adds 2 orbit-motion clips) → self-critique against the checklist (silhouette readable from 40 blocks? underside interesting? palette gradient dark→glow upward? no floating-grass artifacts? bridge walkable?) → adjust constants → rebuild (`/eclipse stage set` re-trigger or version-bump dev flag). Final screenshots are acceptance artifacts.

### 2.7 Player skin v2 + ghost rendering

**Skin v2 (W12) — "Purple Mythic".** Replace `textures/entity/eclipsed_player.png` (64×64 RGBA, wide-arm layout, byte-for-byte path swap; mixin untouched). Design: near-black charcoal-violet bodysuit `#1C1826/#241E31` with woven dither; **glowing purple heart** dead-center chest (8×6px rounded diamond, core `#E7D6FF`, halo `#B98CFF`) — the mod's lifesteal icon made flesh; **lightning/energy veins** branching from the heart across torso→arms→legs→spine (1px main channels `#B98CFF`, 2px forks fading `#6E4DA8`; asymmetric left/right for silhouette interest), faint glyph collar, hood-like head shading with **two soft glowing eyes** `#CBB2F2` (keep face minimal — anonymity read), overlay layer (jacket/hat) used for the hood rim + floating ember pixels (alpha). Deliver via `scripts/skin_gen/eclipsed_player_v2.py` (Pillow, deterministic; commit script + PNG). Regenerate `the_other.png` from the SAME generator with the two spec deltas (pure-black eyes, faint purple face seam) so the doppelganger read survives (§1.1).
**Optional emissive pass (same worker, small):** `client/entity/player/EclipsedPlayerGlowLayer` — a `RenderLayer<AbstractClientPlayer, PlayerModel>` added to both player renderers ("default" + "slim" keys) via `EntityRenderersEvent.AddLayers`, re-rendering the body with `RenderType.eyes(eclipsed_player_glow.png)` (separate 64×64 texture: heart+veins+eyes only). Fullbright heart at night = strong. Coordinate P2 for any Veil bloom on top; ship the layer OFF-safe (config-independent, but rendering no-ops if the glow texture is missing).

**Ghost rendering (W12; P4 owns logic/entity).** Contract (also in §4.4): P4 registers `eclipse:ghost_player` (`ghost/GhostPlayerEntity`, humanoid-sized) with synced fields `ownerName` (String) + `revealTicks` (int, counts down after being hit). P6 provides the client side: `client/entity/ghost/GhostPlayerRenderer` — vanilla `HumanoidModel` baked from the player layer (The Other pattern), texture = the v2 eclipsed skin, rendered translucent (`RenderType.entityTranslucent`, alpha ~0.45, slight +2px hover bob, subtle vertex jitter every few ticks), nameplate suppressed; while `revealTicks > 0`, render the glitch-reveal name above the head using `client/handbook/GlitchText` (existing scramble renderer — P3-owned file but READ-only use) resolving to `ownerName`, plus brief alpha flicker. P2 adds hit-FX burst (§4.2). If P4's entity hasn't landed when W12 runs, W12 commits the renderer + registration guarded behind `if (BuiltInRegistries.ENTITY_TYPE.containsKey(...))` lookup — actually: renderer registration needs the concrete class, so fallback = deliver `docs/plans_v3/handoff/P6_ghost_renderer.md` with the finished code block for P4 to drop in (keeps the build green either way).

### 2.8 Spawn integration, bestiary, dungeon sets (W6 + per-family hooks)

New spawner `entity/spawn/EventSpawnRules.java` (own `@EventBusSubscriber`, 100t cadence, NEVER touches `EclipseSpawner.java`), driven by `entity/spawn/SpawnGates.java` — a static holder of pluggable predicates with safe defaults, so P6 ships day-1 without P1's systems and P1 upgrades precision later by installing real predicates (one setter call each; see §4.1):

| Mob | Gate (default until P1 wires the real one) | Cap / cadence | Placement |
|---|---|---|---|
| fog_revenant | `SpawnGates.FOG_STORM.test(level,pos)` — default: day ≥ 6 AND night AND deterministic noise patch (hash01 like `LimboSeascape`) | cap = 2 + online/4 | surface, 24–48 from a player inside a storm area |
| storm_hound | same gate | packs 2–3, cap 6, howl cue (reuse `EclipseSpawner.howlAround` technique locally) | pack scatter r=4 |
| fog_colossus | same gate AND day ≥ 9 | 1 per storm, 1 global | storm center ±8 |
| glitched (kind-weighted HUSK 45/HOUND 35/TICK 20) | `SpawnGates.NEW_RING.test(level,pos)` — default: overworld stage ≥ 3 AND pos radius inside the two newest ring bands (from `WorldStageService.stageEntries` radii) AND day ≥ 8 | cap = 4 + online/3, night-biased ×2 | surface in the ring band, ≥ 24 from players |
| pale_sentinel | `SpawnGates.PALE_GARDEN.test(level,pos)` — default: FALSE (spawns only once P1 lands the biome/ring; admin `/summon` for testing) | cap 2, night only | inside pale garden area |
| drift_lantern | limbo, players present | 6–10 along buoy lane | x 32..240 lane, waterline+2..+6 |

Bestiary + dungeon handoffs are W6 deliverables (docs; §4.3): entry data for P3's `BestiaryTab` (`{id, introDay}` — fog_revenant 6, storm_hound 6, glitched 8, fog_colossus 9, eclipse_cultist 9, rift_warden 10, pale_sentinel 10, fog_tyrant 12, drift_lantern 1) with `bestiary.eclipse.<id>.name/.lore` keys in W6's langdrop (en+de lore, 2–3 lines each, in the mod's dread-tinged voice), and the **dungeon spawner sheet** for P1: recommended vanilla-spawner `SpawnData` NBT blocks per dungeon theme — stronghold-edge dungeon: `eclipse:eclipse_cultist` (2 spawners), `eclipse:glitched` w/ `Kind:HUSK` (1), rift antechamber trap: `eclipse:glitched` `Kind:TICK` burst; fog shrine dungeon: storm_hound + fog_revenant spawners — plus per-spawner `RequiredPlayerRange/MaxNearbyEntities` tuning values.

---

## 3. WORKER PACKAGES (12 — model rec, size, exact file ownership)

**Model policy (from the boss):** FABLE for ALL model/animation/build/visual work (Fable is better at visual work); SOL only for mechanical registration/plumbing. **Scheduling:** W1 first (foundation). Then W2, W3, W7, W8, W9, W10, W11, W12 fully parallel. W4 → W5 sequential chain (W5 polishes W4's output). W6 parallel any time (IDs are frozen in §6). Cross-worker file collisions: none (matrix below is exhaustive; same-package workers own disjoint files; `package-info.java` belongs to the first-listed owner of the package).

Common acceptance for every package: `./gradlew build` green; `runServer` boots clean (no registry/mixin errors in log); langdrop file present with en+de; wiring lines (if any) appended to `docs/plans_v3/wiring/P6_wiring.md`; screenshots/videos copied to artifacts.

---

### P6-W1 — GeckoLib foundation, authoring pipeline, Drift Lantern pilot — **L, FABLE**

**Goal:** GeckoLib 4.9.2 compiled + bundled (coordinate P5: if `build.gradle` already has geckolib when you start, skip the gradle/mods.toml edits), shared python tooling, conventions handoff doc, and ONE complete pilot mob proving the whole chain (geo → anim → texture → glowmask → renderer → in-game).

**Files owned:** `build.gradle` + `gradle.properties` + `META-INF/neoforge.mods.toml` (geckolib lines ONLY, guarded — P5 coordination per §4.5); `scripts/geckolib_gen/validate_geo.py`, `scripts/geckolib_gen/paint_lib.py`, `scripts/geckolib_gen/mobs/drift_lantern.py`; `entity/ambient/` (`package-info.java`, `AmbientEntities.java` registrar+attributes, `DriftLanternEntity.java`); `client/entity/ambient/` (`package-info.java`, `AmbientRenderers.java`, `DriftLanternRenderer.java`); assets: `geo/entity/drift_lantern.geo.json`, `animations/entity/drift_lantern.animation.json`, `textures/entity/drift_lantern.png` + `_glowmask.png`; `docs/uv/drift_lantern.md`; `docs/plans_v3/handoff/P6_geckolib_conventions.md` (THE doc every later worker reads: verified paths §2.1, bone/anim naming, controller idioms, painter usage, validation-loop checklist); langdrop `docs/plans_v3/langdrop/p6_w1.json` (`entity.eclipse.drift_lantern` en+de).

**Outline:** gradle dep → conventions doc → validator → painter lib → drift_lantern per §2.3 sheet → spawn NOTHING automatically (W6 owns spawn rules; expose `DriftLanternEntity.spawnLane(ServerLevel)` helper for W6).

**Acceptance (screenshots):** (1) `runClient` screenshot of drift_lantern in limbo (`/eclipse tp_limbo` + `/summon eclipse:drift_lantern`) showing glass cage + glowing flame at night-dark; (2) clip of `idle` bob + tendril sway; (3) `/kill` death anim clip; (4) `validate_geo.py` output in the final message; (5) dedicated-server boot log line proving geckolib loaded server-side.

---

### P6-W2 — Limbo crew overhaul: bugs 4a–4d, Deckhand GeckoLib remodel, oar unification — **L, FABLE**

**Goal:** kill all four user-reported bugs at the root (§1.2) and make the rowing read as one organism: rower + oar + water.

**Files owned:** `entity/DeckhandEntity.java`; `client/entity/DeckhandModel.java` (**delete**), `client/entity/DeckhandRenderer.java` (rewrite as `GeoEntityRenderer`), `client/entity/EclipseEntityRenderers.java` (remove Deckhand layer-def + move renderer reg — SOLE P6 owner of this file); `limbo/OarAnimator.java` (gut: keep `beginTilt/endTilt/ensureOars` signatures — `ensureOars` becomes the display-oar **cleanup/migration** (resolve persisted UUIDs → discard → `EclipseWorldState.setOarEntities(List.of())` via existing setter), tilt methods re-target the crew: set a synced `TILT` pose flag on deckhands for the cutscene keel-over, or no-op with a log if the cutscene reads fine without — verify `StartEventCutscene` visually); assets `geo/entity/deckhand.geo.json`, `animations/entity/deckhand.animation.json`, regenerated `textures/entity/deckhand.png` (painter script `scripts/geckolib_gen/mobs/deckhand.py`); update `docs/uv/deckhand.md`; langdrop `p6_w2.json` (no new strings expected — keep file with empty maps if so).

**Do NOT touch:** `FerrymanEntity.java` (all crew calls keep signatures), `EclipseWorldState.java`, `GhostShipBuilder.java` (W3 owns), `StartEventCutscene.java`.

**Mechanics fixes (server):**
1. **Bench identity:** each deckhand persists `BenchIndex` (0–7) in NBT; `ensureCrew/reseatFallen/seatAt` assign it; static `benchPos(index)` exposed.
2. **4a orphan reconciliation:** new `reconcileCrew(ServerLevel)` — collect ALL `DeckhandEntity` in limbo (`level.getEntities(EclipseEntities.DECKHAND.get(), e -> true)`); any entity whose UUID is NOT in the world-state list → `discard()` (log count). Called from `riseHostile` (fight start), `ensureCrew`, and a slow self-heal in `DeckhandEntity.tick` (every 200t, if not in list → discard self — covers entities that load in late).
3. **4a load race:** `reseatFallen` no longer trusts `getEntity==null` immediately: it defers — `FerrymanEntity.summon`'s call now schedules (a `pendingReseatTicks=100` countdown inside `DeckhandEntity`'s static tick hook or a small `@EventBusSubscriber` level-tick in `DeckhandEntity`): each tick try to resolve all listed UUIDs; reseat a bench only when its UUID stays unresolved after the window AND the bench's entity section is actually loaded (`limbo.areEntitiesLoaded(ChunkPos.asLong(benchPos))` — NeoForge exposes `ServerLevel#areEntitiesLoaded(long)`; if unavailable, use `limbo.getEntity(...)` retry-until-timeout alone). P2-crew rise waits for reseat completion (riseHostile already runs at phase break, ≥ minutes later — safe).
4. **4b return-to-bench:** `calmCrew` → each survivor: `setHostile(false)` + teleport to its bench pos/rotation (they're spectral — a snap + soul-puff particles reads intentional) + `getNavigation().stop()`. Plus self-heal in `tick()`: hostile deckhand with no `FerrymanEntity` alive in the dimension for 100 consecutive ticks → self-calm + snap to bench (covers `/kill @e[type=eclipse:ferryman]`, crashes, discards).
5. **4c/4d oar unification:** remove block-display oars (migration above); the new geo's oar bones swing inside the 60t `row` loop; synchronized phase across the crew (§2.3 sheet); client splash: renderer `preRender` spawns 2–3 `SPLASH` particles at the blade tip world-pos on the dip beat (derive from anim clock — cheap, client-only).

**Acceptance (all mandatory, screenshots/clips):**
1. **Pre-fix repro of 4a:** on the CURRENT commit (before your fix), boot, `/eclipse tp_limbo`, `/eclipse boss ferryman summon` immediately after boot; screenshot showing >8 deckhands / passive rowers standing during P2 (if the race doesn't fire after 3 attempts, force it: temporarily clear the deckhand UUID list via a dev-only line, document it). Then the same steps post-fix: exactly 8, all rise in P2.
2. **Pre/post 4b:** post-fix — summon Ferryman, reach P2 (`/eclipse boss ferryman phase` if present, else damage), die on purpose; within 10s the crew is back on benches rowing (clip); repeat with 2nd fight — no leftovers, crew hittable when risen.
3. **4c/4d:** clip of the 8 rowers stroking **in unison** with proper bladed oars dipping toward the water; no free-floating pole displays anywhere (`/kill @e[type=block_display]` count check = 0 in limbo after migration).
4. Restart persistence: stop server, start, crew count still 8, still rowing in sync; `StartEventCutscene` (`/eclipse` start-event or its test hook) still plays without visual regressions (clip of the tilt moment).

---

### P6-W3 — Ghost ship v2 rebuild + Respawn Door — **L, FABLE**

**Goal:** §2.5 in full: the ship finally looks like a ghost ship; the respawn door exists, animates, glows, and exposes the P3/P4 API.

**Files owned:** `limbo/GhostShipBuilder.java`, `limbo/ShipLanterns.java`; new package `limbo/door/` (`package-info.java`, `DoorRegistry.java`, `RespawnDoorBlock.java`, `RespawnDoorFillerBlock.java`, `RespawnDoorBlockEntity.java`, `RespawnDoorApi.java`, `S2CDoorCuePayload.java` + its `@EventBusSubscriber` registrar class `DoorPayloads.java`, `ShipVersionData.java` SavedData); client `client/entity/door/` (`RespawnDoorRenderer.java`, `DoorRenderers.java` subscriber) — (block renderers may live under `client/` anywhere; keep this package); assets: `geo/block/respawn_door.geo.json`, `animations/block/respawn_door.animation.json` (GeckoLib block animations live under `animations/` too — mirror entity conventions), `textures/block/respawn_door.png` + `_glowmask.png` (painter script `scripts/geckolib_gen/mobs/respawn_door.py`), `blockstates/respawn_door.json` + minimal item/block model JSONs (empty-cube model — BER draws everything); wiring line for `DoorRegistry.register(modEventBus)` in `docs/plans_v3/wiring/P6_wiring.md`; langdrop `p6_w3.json` (`block.eclipse.respawn_door` en+de + any actionbar hints).

**Outline:** build v2 per §2.5 (constants-driven builder methods, keep every §1.3 contract); version-gated rebuild via `ShipVersionData` (skip + log if a Ferryman is alive); relocate 4 lanterns + update `ShipLanterns.positions()`; door multiblock placed by the builder into the quarterdeck bulkhead; renderer with viewer-side ghost rule (§2.5); `RespawnDoorApi` for P3/P4 (§4.3/§4.4).

**Acceptance (screenshots/clips):** (1) beauty shots: bow ¾, broadside, deck-level toward the door, stern; night shot with lanterns + door glow spill; (2) clip: door `open` → `close` triggered via `RespawnDoorApi` from a dev hook (temporary code, removed before commit — trigger it e.g. on first tick after summon, then delete); (3) ghost-view check: `/eclipse` ban/ghost a test path OR temporarily force the viewer-check to true (documented temp toggle, removed) → screenshot proving the closed render while global state is OPEN; (4) **Ferryman full-fight regression on v2**: video P1 sweep/slam → P2 crew + lantern relight → P3 sink flooding around new furniture → kill → `restoreShip` drains everything (final screenshot of dry deck); (5) `platformArrivalPos` still lands on solid planks.

---

### P6-W4 — Floating sanctum island + crater (build pass 1) — **L, FABLE**

**Goal:** §2.6 island + crater + access, stage-gated, with the Herald arena intact on top.

**Files owned:** `worldgen/structure/AltarSanctumBuilder.java` (becomes the v2 entry: stage gate + version guard + delegates), new `worldgen/structure/FloatingSanctumBuilder.java`, `worldgen/structure/SanctumCrater.java`, `worldgen/structure/SanctumVersionData.java`; `worldgen/structure/SundialPlaza.java` (re-anchor onto island top); `worldgen/structure/SanctumProtection.java` (radius/vertical extension only); langdrop `p6_w4.json` (likely empty — keep file).

**Do NOT touch:** `HeraldEntity`, `AltarBlockEntity`, rituals, `EclipseWorldState` (altar pos setter already exists and is called with the new pos through the existing `setSanctumBuilt(altarPos)` path).

**Outline:** per §2.6; keep `pillarBaseCorner/pillarBases/pillarTopY` formulas identical relative to `altarPos` (they float up with it); `repinSpawn` → crater rim; ≥2 iterative build-review loops with the §2.6 checklist.

**Acceptance (screenshots):** (1) the 4 canonical angles + below-crater shot; (2) day-1 walkability clip: spawn → bridge → altar on foot, no jumps > 1; (3) **Herald smoke test on the island**: `/eclipse boss herald summon` (after dusk or day-set), video of P2 gaze being blocked behind an island pillar (LOS mechanic alive) + P3 pull not yeeting players off the island edge (rim rail visible in frame); (4) restart idempotence: second boot makes zero block changes (log proof); (5) stage-0 world: sanctum stays grounded (screenshot), flips to island right after stage 1 fires.

---

### P6-W5 — Sanctum orbitals + island polish (build pass 2) — **M, FABLE** *(depends: W4 merged)*

**Goal:** the slow rotating/bobbing block-display debris ring + a polish pass over W4's build with fresh eyes.

**Files owned:** new `worldgen/structure/SanctumOrbitals.java` (+ its `@EventBusSubscriber` tick loop, tag-based persistence per §2.6); bounded polish edits inside `FloatingSanctumBuilder.java`/`SanctumCrater.java` (W4 is done and merged at this point; you are the second owner in SEQUENCE, never in parallel); langdrop `p6_w5.json` (empty likely).

**Outline:** 12 displays, 2 counter-rings, 40t interpolated pushes, phase offsets, player-presence gate, tag reconciliation on start (scan → adopt → top-up → discard extras); polish loop ≥2 iterations (underside depth, palette gradient, glow accents).

**Acceptance:** (1) 20–30s video of both rings rotating + bobbing smoothly (no teleport-snapping — interpolation visibly working); (2) restart → same 12 displays adopted (log line `adopted 12 orbital displays, spawned 0`); (3) `/kill @e[tag=eclipse_sanctum_orbital]` → next start self-heals to 12 (log); (4) perf note in final message: measured `/debug` or spark-free tick cost statement + packet cadence math; (5) final beauty screenshot set (this is the money shot of the whole sanctum — dusk lighting).

---

### P6-W6 — Spawn rules & gating + bestiary/dungeon data handoff — **M, SOL** *(pure plumbing/data — no visuals)*

**Goal:** §2.8 wired: every new mob spawns per its gate with caps; handoff docs for P1 (dungeon spawners, gate predicates) and P3 (bestiary) written; ALL bestiary lore text (en+de) authored.

**Files owned:** new `entity/spawn/` (`package-info.java`, `SpawnGates.java`, `EventSpawnRules.java`); `docs/plans_v3/handoff/P6_bestiary_entries.md`; `docs/plans_v3/handoff/P6_dungeon_spawners.md`; langdrop `p6_w6.json` (all `bestiary.eclipse.<id>.name/.lore` keys en+de).

**Outline:** copy `EclipseSpawner`'s placement helpers into the new class (do NOT import private statics — reimplement; keep `findSurfaceSpawn` semantics); entity lookups by `ResourceLocation` via `BuiltInRegistries.ENTITY_TYPE.getOptional(...)` so W6 builds green even if some mob workers haven't merged yet (skip absent types with a debug log); gates per §2.8 table with the documented defaults; caps counted per type; peaceful-difficulty early-out (EclipseSpawner precedent).

**Acceptance:** (1) `runServer` + RCON (AGENTS.md pattern): `/eclipse day set 8`, night — log lines showing glitched spawns inside the newest ring band and NOT inside old rings (log the ring radius check); (2) day 6 storm-noise default: fog mobs spawn in patches, none outside; (3) `/eclipse day set 3` → zero new-family spawns (gates hold); (4) both handoff docs complete (bestiary table incl. intro days + icon notes; spawner NBT blocks copy-pasteable); (5) caps hold: 10 min idle at night doesn't exceed documented caps (`/execute if entity` counts via RCON).

---

### P6-W7 — Fog Revenant + Storm Hound — **L, FABLE**

**Goal:** the two core fog-storm mobs per §2.3 sheets, attacks + custom effects included.

**Files owned:** new `entity/fog/` (`package-info.java`, `FogEntities.java` registrar+attributes for BOTH, `FogRevenantEntity.java`, `StormHoundEntity.java`, goal classes `FogBlindBurstGoal.java`, `ChargedLungeGoal.java`); new `client/entity/fog/` (`package-info.java`, `FogRenderers.java`, `FogRevenantRenderer.java`, `StormHoundRenderer.java`); assets: geo/anim/texture(+glowmask) for both ids + `scripts/geckolib_gen/mobs/fog_revenant.py`, `storm_hound.py`; `docs/uv/fog_revenant.md`, `docs/uv/storm_hound.md`; langdrop `p6_w7.json`.

**Acceptance (per mob):** (1) turntable screenshots front/side/¾; (2) anim evidence: idle, walk/run (lure), attack (melee hit clip), special (blind burst clip showing the Blindness overlay on the player + particles; hound windup-glow + lunge clip incl. the miss-stagger), death; (3) glowmask proof: screenshot in pitch dark (wisps/spines visible); (4) pack behavior: 3 hounds alert-aggro together; (5) `/summon` on dedicated server — no client-class crashes (boot + summon via RCON).

---

### P6-W8 — Fog Colossus + Glitched Variant system — **L, FABLE**

**Goal:** the elite tank + the 3-kind glitch wrapper per §2.3, incl. the datamosh texture-flicker renderer and stepped-keyframe jitter anims.

**Files owned:** `entity/fog/FogColossusEntity.java` + `entity/fog/FogEliteEntities.java` (registrar; SAME package as W7, DIFFERENT files — do not touch W7's) + `entity/fog/GroundSlamGoal.java`; new `entity/glitch/` (`package-info.java`, `GlitchEntities.java`, `GlitchedVariantEntity.java` w/ `Kind` enum + synced byte + spawn-data support for spawner NBT `{Kind:"HUSK"}`); new `client/entity/glitch/` (`GlitchRenderers.java`, `GlitchedVariantRenderer.java`, `GlitchedVariantModel.java` — kind-switching GeoModel) + `client/entity/fog/FogColossusRenderer.java` (W8-owned file in W7's package — allowed, distinct file; coordinate: W7 creates the package first OR whoever lands first creates `package-info.java`… **rule: W7 owns both `package-info.java` files; if W8 lands first it creates them with a `// owner: P6-W7` note and W7 keeps them**); assets: colossus + `glitched_husk`/`glitched_hound`/`glitched_tick` geos/anims/textures + `_alt.png` flicker variants + glowmasks + painter scripts; `docs/uv/*.md` ×4; langdrop `p6_w8.json`.

**Acceptance:** (1) colossus slam clip: telegraph → shockwave → player launched (falloff visible: near hit hard, far player hops); (2) each glitch kind: turntable + idle-jitter clip (stepped pops, NOT smooth), texture flicker visible in a 10s clip, `glitch_blink` teleport clip; (3) spawner NBT test: place a vanilla spawner via `/setblock` with the W6 handoff NBT, kinds spawn correctly (screenshot); (4) drops land (item entities visible; log the resolved item ids incl. fallback path); (5) dark-room glowmask shots ×4.

---

### P6-W9 — Pale Sentinel — **M, FABLE**

**Goal:** the Creaking-like guardian per §2.3 — the freeze-when-observed mechanic is the acceptance centerpiece.

**Files owned:** new `entity/pale/` (`package-info.java`, `PaleEntities.java`, `PaleSentinelEntity.java`, `ObservedFreezeHelper.java`); new `client/entity/pale/` (`PaleRenderers.java`, `PaleSentinelRenderer.java` — incl. the anim-speed-0 freeze wiring via the controller's speed handler reading the synced FROZEN flag); assets geo/anim/texture(+glowmask eyes) + painter script; `docs/uv/pale_sentinel.md`; langdrop `p6_w9.json`.

**Acceptance:** (1) THE clip: player looks at sentinel → dead stop mid-stride (pose frozen mid-frame, not snapped to a pose); pan camera away and back repeatedly → it has advanced only during look-aways; (2) hysteresis: no strobe at screen edge (slow pan clip); (3) attack only lands off-screen (clip with hurt flash while camera turned, F5 rear view allowed as evidence); (4) frozen-hit reaction: petal burst + flinch clip; (5) night gate + dawn burrow-despawn (time-set clip); (6) private creak audio noted in final message (can't screenshot audio — state test method + logs).

---

### P6-W10 — Rift Warden boss + Eclipse Cultist (dungeon set) — **L, FABLE**

**Goal:** the full §2.4 Rift Warden fight + the §2.3 cultist, both `/summon`-ready for P1's dungeons.

**Files owned:** new `entity/boss/rift/` (`package-info.java`, `RiftEntities.java` — registers warden + cultist + bolt, `RiftWardenEntity.java`, `RiftAnchor.java` marker/logic); new `entity/dungeon/` (`package-info.java`, `EclipseCultistEntity.java`, `ShadowBoltProjectile.java`, `RangedShadowBoltGoal.java`); new `client/entity/rift/` (`RiftRenderers.java`, `RiftWardenRenderer.java`, `EclipseCultistRenderer.java`, bolt uses `ThrownItemRenderer`); assets: warden (128×128) + cultist geos/anims/textures/glowmasks + painter scripts; `docs/uv/rift_warden.md`, `docs/uv/eclipse_cultist.md`; langdrop `p6_w10.json` (`entity.eclipse.rift_warden(.bossbar)`, `entity.eclipse.eclipse_cultist`, telegraph actionbar hints — en+de).

**Acceptance:** (1) **full fight video** on a flat dev arena: P1 sweep combo (sidestep beats visible) + rift-step blink-behind with destination chime, P2 rift anchors pulsing + TICK adds + jumpable bursts, soft-enrage log, death implosion upright; (2) bossbar screenshot with THEME_BOSS skin + PURPLE color; (3) arena lock: outside-ring arrow deflect (chime + zero damage log) + inward impulse clip; (4) wipe + abandon-reset both logged and ship-shape (no leftover anchors/adds); (5) cultist: cast loop clip (bolt volley homing-lite), knife panic swipe, kneel death; (6) restart mid-fight: phase + anchors resume (Ferryman NBT pattern proof via log).

---

### P6-W11 — Fog Tyrant apex boss — **L, FABLE** *(stretch-gated: run after W7/W8 land the fog family; independent of P1 timing — standalone summon works)*

**Goal:** §2.4 Fog Tyrant complete, self-sufficient via `/summon`, with the P1 summon hook exposed.

**Files owned:** new `entity/boss/fog/` (`package-info.java`, `FogBossEntities.java`, `FogTyrantEntity.java`, `FogBankMarker.java`); new `client/entity/fogboss/` (`FogBossRenderers.java`, `FogTyrantRenderer.java`); assets 128×128 geo/anim/texture/glowmask + painter script; `docs/uv/fog_tyrant.md`; langdrop `p6_w11.json` (bossbar name + anchor-the-fog actionbar hint en+de).

**Acceptance:** (1) full fight video: P1 veils + telegraphed visual-only lightning (no fire, damage log matches r=2.5), P2 consume-channel interrupted by standing in the bank (stagger + ×1.5 damage window log) AND one successful consume (heal log), P3 lunge chain + blind nova + hound adds at 25%, storm-burst death with core-gutter; (2) bank lifecycle: all 4 consumed/anchored → no more heals (log); (3) reset cleans banks + hounds; (4) `FogTyrantEntity.summon(level,pos)` javadoc'd for P1 + noted in §4.1 handoff terms.

---

### P6-W12 — Player Skin v2 + emissive layer + The Other sync + Ghost renderer — **M, FABLE**

**Goal:** §2.7 complete: purple-mythic uniform skin, matching doppelganger, optional glow layer, ghost renderer per P4 contract.

**Files owned:** `scripts/skin_gen/eclipsed_player_v2.py` (also regenerates `the_other.png`); `assets/eclipse/textures/entity/eclipsed_player.png`, `the_other.png`, new `eclipsed_player_glow.png`; new `client/entity/player/` (`package-info.java`, `EclipsedPlayerGlowLayer.java`, `PlayerLayerHandler.java` AddLayers subscriber); new `client/entity/ghost/` (`GhostPlayerRenderer.java`, `GhostRenderers.java`) OR `docs/plans_v3/handoff/P6_ghost_renderer.md` if P4's entity is absent (§2.7 fallback); langdrop `p6_w12.json` (likely empty).

**Do NOT touch:** `AbstractClientPlayerMixin` (path unchanged), `TheOtherRenderer` (texture path unchanged), `GlitchText` (read-only use).

**Acceptance:** (1) screenshots: third-person + F5 front (heart + veins readable at 5 blocks), inventory doll, TWO clients' worth if cheap (else two summoned The Others beside the player); (2) night shot with the glow layer: heart/veins/eyes fullbright while body stays dark; (3) The Other side-by-side with a player — indistinguishable at 10 blocks (screenshot), black eyes visible ≤ 6 blocks (close-up); (4) skin renders correctly with WIDE layout (no arm texture bleed — check both arms raised in F5 while sprinting); (5) ghost renderer (if P4 landed): translucent hover clip + hit → glitch name-reveal resolving to `ownerName`; else the handoff doc with finished code committed.

---

## 4. INTERFACES TO OTHER PLANNERS

### 4.1 P1 (world / biomes / dungeons / fog areas / rings)

| Topic | Contract |
|---|---|
| Fog storm areas | P1 lands `FogStormService` (any package) exposing `boolean isStormAt(ServerLevel, BlockPos)` + `List<BlockPos> matureStormCenters(ServerLevel)`; P1 (or an integrator) installs it via `SpawnGates.FOG_STORM = FogStormService::isStormAt` (one line, `SpawnGates` javadocs show it). Until then P6 uses the documented noise-patch default. Storm visuals = P2. |
| New-ring flags | Preferred: P1 exposes `int ringIndexAt(BlockPos)` + `int newestOpenRing(server)`; installed into `SpawnGates.NEW_RING`. Default fallback derives ring bands from `WorldStageService.stageEntries` radii. |
| Pale Garden | P1 builds the biome/area port (`eclipse:pale_garden` or an area predicate) and installs `SpawnGates.PALE_GARDEN`. Until then the sentinel is admin-summon only (deliberate: never spawns in the wrong biome). |
| Dungeons | P1 places vanilla spawners using `docs/plans_v3/handoff/P6_dungeon_spawners.md` (W6): ids `eclipse:eclipse_cultist`, `eclipse:glitched` (+`Kind` NBT), `eclipse:storm_hound`, `eclipse:fog_revenant`, with tuning values. Rift Warden: P1 triggers `RiftWardenEntity` via `/summon` mechanism of their choice at the arena center — the fight self-pins (r=12; arena room should be ≥ 20×20×8, flat floor). |
| Fog Tyrant | P1 calls `FogTyrantEntity.summon(ServerLevel, BlockPos)` at a mature storm center (or leaves it admin-only this event). |
| Altar island | P6-W4 owns the sanctum builders; if P1's biome-spawn fixes touch `FinalizeSpawnEvent` near spawn, note `SanctumProtection` suppression already exists — coordinate rather than duplicate. |

### 4.2 P2 (VFX / shaders / particles / emissive)

- **Quasar emitters requested** (P6 uses vanilla-particle stand-ins until they exist; ids frozen so P6 code can switch by constant): `eclipse:fog_burst` (revenant blind), `eclipse:glitch_pop` (glitched hit/blink + ghost hit), `eclipse:rift_tear` (warden blink), `eclipse:fog_bank` (tyrant banks), `eclipse:pale_petals` (sentinel). Delivery = new `S2CQuasarPayload` type constants or emitter jsons — P2's call; P6 workers isolate FX calls in one `<Mob>Fx` helper method each for a one-line swap.
- **Emissive**: P6 handles mob emissive via GeckoLib glowmasks (self-contained). P2 owns any Veil bloom/post enhancements on top (incl. the player heart glow bloom + respawn-door area light). Door hook: `RespawnDoorBlockEntity` exposes `getGlowStrength()` (0..1, animated) for P2's light sampling.
- **Ghost FX**: name-reveal glitch burst + translucent shimmer on hit — P6 renders base translucency + `GlitchText` name; P2 layers particles/post.
- **Reduced motion / Iris**: P6 mobs use no custom shaders — nothing to gate. P2's flourishes must self-gate (existing `EclipseIrisState` pattern).

### 4.3 P3 (UI: bestiary, bossbars, door/death UI)

- **Bestiary**: P3 owns `BestiaryTab.java`. P6-W6 delivers `docs/plans_v3/handoff/P6_bestiary_entries.md` (id + introDay table per §2.8) and ALL `bestiary.eclipse.<id>.name/.lore` keys (en+de) in `p6_w6.json`. Silhouettes are code-drawn by P3; the handoff doc includes a 1-line silhouette description per mob to draw from.
- **Bossbars**: both new bosses reuse the existing `S2CBossbarStylePayload(THEME_BOSS)` — zero P3 work required. OPTIONAL ask: a `THEME_RIFT` variant (purple-glitch frame) — P3's discretion; P6 code passes a constant either way.
- **Door/death UI**: P3's death/respawn screens may call `RespawnDoorApi.playOpenFor(player)` + `doorFrontPos()` for the walk-through moment; the ghost-sees-closed rule is client-automatic (§2.5).

### 4.4 P4 (economy / drops / ghost logic)

- **Drop items**: P6 mobs/bosses drop by registry lookup with umbral_shard fallback (§2.3/§2.4): P4 registers `fog_essence`, `storm_gland`, `glitch_shard` (heart-crafting input), `pale_resin`, `cultist_sigil`, `rift_core`, `storm_heart` and their economy sinks. Quantities in the sheets are initial balance — P4 may tune drop counts in the entity files afterward (listed as the one sanctioned cross-edit, post-merge).
- **Glitched gating**: heart-crafting economy pacing is P4's; P6 gates glitched SPAWNS by ring/day only (§2.8) — if P4 needs harder gates (e.g. spawn only after first heart craft), install a predicate into `SpawnGates.NEW_RING` composite.
- **Logout ghosts**: P4 owns `ghost/GhostPlayerEntity` (server logic: spawn on logout, position, hittability, name reveal trigger setting `revealTicks`). Contract fields (synced): `String ownerName`, `int revealTicks`. P6-W12 provides the renderer (§2.7). Registration split: P4 registers the entity type + attributes; P6 registers only the renderer.
- **Respawn door flow**: P4's death flow calls `RespawnDoorApi` (§2.5); door stays a prop — no lives logic inside P6 code.

### 4.5 P5 (packaging / bundling)

- **GeckoLib bundling is P5's** (this plan supplies the verified coordinates + snippet, §2.1): `software.bernie.geckolib:geckolib-neoforge-1.21.1:4.9.2`, Cloudsmith repo, jarJar strictly `[4.9.2,)` prefer `4.9.2`, `neoforge.mods.toml` required-dependency entry. P6-W1 applies it ONLY if absent when W1 starts (guarded; whoever lands second must no-op).
- Dedicated-server parity: jar-in-jar covers `runServer`; nothing to add to `run/mods` for dev. P5 should verify no OTHER pack mod ships an older GeckoLib (open range dedupes to highest — same policy as Veil).
- Server-pack docs: P5 adds GeckoLib to the README "Server pack"/mod-matrix section.

---

## 5. RISKS & FALLBACKS

| Risk | Assessment | Fallback |
|---|---|---|
| **GeckoLib × Veil render compat** | Low: GeckoLib renders through vanilla `RenderType`s; Veil post pipelines are orthogonal (and self-disable under Iris shaderpacks already). Glowmask emissive uses an eyes-style rendertype like the existing hand-coded emissive layers. | If a Veil post pass washes out glowmasks, paint emissive regions bright in the ALBEDO too (current `EntitySkinArtist` already does this) so mobs read even without the glow pass. |
| **Iris shaderpack dims glowmasks** | Known GeckoLib-under-shaders behavior (emissive becomes albedo-lit). The dev-target client runs Sodium 0.8.12 + Iris only WITH shaderpack optionally. | Same albedo-brightness fallback; document in conventions doc; no code gate needed. |
| **GeckoLib version collision with pack mods** | `run/mods` audited list (Create, FD, Supplementaries, Sable, …) — none known to bundle GeckoLib; open-range jarJar dedupes anyway. | Pin check in P5's smoke boot: log `geckolib` version at startup. |
| **Entity-section load race fix insufficient** (4a) | The retry-window + reconciliation sweep is belt-and-braces; reconciliation alone already guarantees no visible duplicates (orphans discarded at fight start). | Worst case = a bench briefly empty until the window closes; acceptable, logged. |
| **Ship rebuild vs live worlds** | Rebuild clears+rebuilds above-keel volume; guarded to skip while a Ferryman exists; deck/waterline contracts unchanged so persisted fights resume. | If regression testing shows sink/restore issues around new furniture, restrict furniture out of the `deckY+1..+4` footprint entirely (design already mostly does). |
| **Block-display perf (orbitals + any leftovers)** | 12 displays × 1 transform packet / 40t ≈ 6 packets/s total — negligible; W2 deletes the 8 oar displays (net count drops). | Player-presence gate already specified; halve cadence to 80t with longer interpolation if needed. |
| **Skin mixin edge cases** | Mixin returns a fixed `PlayerSkin` — texture swap is zero-risk; WIDE is forced so the new skin must use wide-arm UV (acceptance checks it). Glow layer touches player renderers via supported `AddLayers` — guard with `instanceof PlayerRenderer` and null-safe texture lookup. | Glow layer is optional and isolated in one class — revert = delete registration, skin still ships. |
| **Anim-sync for rowers across clients** | Sync via shared game-time boundary is approximate (client clocks track server ticks closely); worst case ±2t phase drift between rowers. | Acceptable visually; if not, drive the row cycle off `level.getGameTime()` inside a custom animation-speed/seek handler (single source clock). |
| **Pale Sentinel look-check cost** | Dot products vs ≤ a handful of players within 32 blocks + one raycast per player per tick — trivial; raycast only when the dot passes (cheap early-out). | Throttle raycasts to every 2t if profiling ever flags it. |
| **Parallel-worker asset id collisions** | Prevented structurally: ids, packages, and files frozen in §6/§3; registrars are per-family. | Integrator resolves any stray collision by the §3 matrix (it is authoritative). |
| **P1/P2/P4 deliverables late** | Every P6 feature has a documented default/fallback (SpawnGates defaults, vanilla-particle stand-ins, drop-item fallbacks, ghost-renderer handoff doc). Nothing in P6 hard-depends on another planner landing first except door-flow UX (prop still ships). | Ship with defaults; integrator flips predicates/constants when the other planners land. |
| **Herald fight on the floating island** | Pillar API preserved relative to altarPos; arena r=15 fits the r=16 island; P3 pull is inward (crater is outside the pull). Edge-fall risk mitigated by rim railing + W4 acceptance test. | If testing shows edge deaths, add an invisible-barrier ring at r=15 during the fight only (one setBlock ring in `HeraldEntity` summon/cleanup — coordinate as a follow-up, NOT in W4 scope). |

---

## 6. FROZEN IDs, KEYS, PATHS (collision-proofing for parallel workers)

**Entity ids:** `eclipse:drift_lantern`, `eclipse:fog_revenant`, `eclipse:storm_hound`, `eclipse:fog_colossus`, `eclipse:glitched`, `eclipse:pale_sentinel`, `eclipse:eclipse_cultist`, `eclipse:shadow_bolt`, `eclipse:rift_warden`, `eclipse:fog_tyrant` (+ existing `eclipse:deckhand` unchanged; P4's `eclipse:ghost_player`).

**Blocks/BEs (W3):** `eclipse:respawn_door`, `eclipse:respawn_door_filler`, BE `eclipse:respawn_door`.

**Command tags:** `eclipse_sanctum_orbital` (W5).

**Anim id scheme:** `animation.<entity_path>.<name>`; controllers `base` (idle/walk logic) + `action` (triggerables). Trigger names are the `special`/`attack`/`death` names in each §2.3/§2.4 sheet.

**Lang key scheme:** `entity.eclipse.<id>`, `entity.eclipse.<id>.bossbar`, `block.eclipse.respawn_door`, `bestiary.eclipse.<id>.name/.lore`, actionbar hints `message.eclipse.<feature>.<hint>` — all via langdrop files only.

**Asset paths (per §2.1, verified):** `geo/entity/<id>.geo.json`, `geo/block/respawn_door.geo.json`, `animations/entity/<id>.animation.json`, `animations/block/respawn_door.animation.json`, `textures/entity/<id>.png` (+`_glowmask.png`, glitched adds `_alt.png`), `textures/block/respawn_door.png` (+glowmask). Texture canvases: 64×64 default; 128×128 for `fog_colossus`, `rift_warden`, `fog_tyrant`, `respawn_door`.

**Handoff/wiring docs:** `docs/plans_v3/wiring/P6_wiring.md` (EclipseMod lines, integrator-applied), `docs/plans_v3/handoff/P6_geckolib_conventions.md` (W1), `P6_bestiary_entries.md` + `P6_dungeon_spawners.md` (W6), `P6_ghost_renderer.md` (W12 fallback), langdrops `docs/plans_v3/langdrop/p6_w{1..12}.json`.
