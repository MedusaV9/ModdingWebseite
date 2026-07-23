# P6 GeckoLib conventions (P6-W1 handoff — READ BEFORE AUTHORING ANY MOB)

Everything below is **verified against the shipped GeckoLib 4.9.2 jar** (decompiled
signatures + constant pools) and proven end-to-end by the Drift Lantern pilot
(`eclipse:drift_lantern`). The plan is `docs/plans_v3/P6_mobs_models_builds.md`; this doc
is the working contract. **Frozen** means: do not rename/move — sibling workers and the
integrator rely on it.

## 0. Bundling — already done, touch NOTHING

`build.gradle` (Cloudsmith repo + jarJar `software.bernie.geckolib:geckolib-neoforge-1.21.1`,
strictly `[4.9.2,)` prefer `4.9.2`), `gradle.properties` (`geckolib_version=4.9.2`) and
`src/main/templates/META-INF/neoforge.mods.toml` (required dep, side `BOTH`) already carry
the GeckoLib lines (P6-W1, coordinated with P5 per plan §4.5). **No other P6 worker edits
those three files.** GeckoLib runs client+server; jar-in-jar covers `runServer`.

## 1. Asset paths (FROZEN — verified `DefaultedGeoModel` format strings)

| Asset | Path (under `src/main/resources/assets/eclipse/`) |
|---|---|
| Geometry | `geo/entity/<id>.geo.json` (blocks: `geo/block/<id>.geo.json`) |
| Animations | `animations/entity/<id>.animation.json` (blocks: `animations/block/...`) |
| Texture | `textures/entity/<id>.png` |
| Emissive glowmask | `textures/entity/<id>_glowmask.png` — **same canvas size** (enforced at runtime) |

These are the OLD-style GeckoLib-4 paths — NOT the `geckolib/models` layout the
GeckoLib-5 wiki shows. One string `<id>` resolves the whole triple via
`DefaultedEntityGeoModel` (wrapped by our renderer base, §3). Texture canvases: 64×64
default; 128×128 for `fog_colossus`, `rift_warden`, `fog_tyrant`, `respawn_door` (§6 of
the plan). `.bbmodel` project files may be committed next to geo files (excluded from the
jar by `build.gradle`), but the runtime loads only `.geo.json`/`.animation.json`.

## 2. Geometry + animation file format (real Blockbench, Bedrock-model project type)

* `.geo.json`: `format_version "1.12.0"`, `minecraft:geometry[0]` with `description`
  (`identifier: "geometry.<id>"`, `texture_width/height`), `bones[]` each `name`,
  `pivot`, optional `parent`/`rotation`, `cubes[]` (`origin`, `size`, box-UV `uv: [u,v]`
  or per-face UV map, optional `inflate`/`mirror`).
* `.animation.json`: `format_version "1.8.0"`,
  `animations["animation.<id>.<name>"] = { loop: true|false|"hold_on_last_frame",
  animation_length: seconds, bones: { "<bone>": { rotation|position|scale: ... } } }`.
  Keyframes: `"0.5": [x,y,z]`, or `{"post": [...], "lerp_mode": "catmullrom"}`, or a
  static channel array. Degrees for rotation, model px for position. Molang works in any
  component (e.g. `"math.sin(query.anim_time * 120) * 6"` — `query.anim_time` is SECONDS
  since the anim started, `math.sin` takes DEGREES; a `* 120` sweep loops seamlessly over
  a 3s animation).

**Bone naming (FROZEN):** root bone `root`; head-tracked bone MUST be `head` (that exact
name is what GeckoLib's auto head tracking targets); attack limbs `arm_left/arm_right` or
`leg_fl/fr/bl/br`; emissive-only geometry under bones prefixed `glow_` (the painter
auto-includes those in the glowmask). Minimum anim set per mob: `idle`, `walk`, `attack`,
one special, `death` — exact special names per your §2.3/§2.4 sheet.

**Render order matters for translucency:** bones render in file order (parents before
children). If a glowing core sits inside a translucent shell, list the CORE bone before
the SHELL bone (see `drift_lantern.geo.json`: `glow_flame` before `cage`) so the shell
alpha-blends over it.

## 3. Java pattern (FROZEN base classes — extend, don't reinvent)

Server/common (`dev.projecteclipse.eclipse.entity.geo`):

```
EclipseGeoAnimations   — CONTROLLER_BASE="base", CONTROLLER_ACTION="action",
                         ANIM_IDLE/WALK/ATTACK/DEATH, animId(path,name),
                         loop(path,name) / once(path,name) / hold(path,name)
EclipseGeoMob          — extends PathfinderMob implements GeoEntity (passive/ambient line)
EclipseGeoMonster      — extends Monster implements GeoEntity (hostile/boss line)
```

Both bases are identical in shape (Java single inheritance forces the mirror; P6-W1 keeps
them in lockstep). Subclass contract:

```java
public class FogRevenantEntity extends EclipseGeoMonster {
    @Override public String geoId() { return "fog_revenant"; }   // keys assets + anim ids

    @Override protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action);                    // keeps the death trigger
        action.triggerableAnim("cast_blind", EclipseGeoAnimations.once(geoId(), "cast_blind"));
    }
    // optional: handleBaseState(AnimationState<?>) — default plays walk while
    // state.isMoving() else idle; override for hover-drift mobs (Drift Lantern reads its
    // own per-tick position delta because slow tick-driven motion never trips isMoving()).
    // optional: baseTransitionTicks() — blend ticks, default 4.
}
// server-side, anywhere in fight/AI code:
this.triggerAction("cast_blind");   // syncs to clients on GeckoLib's own channel
```

`registerControllers` is **final** in the bases: every mob gets exactly two controllers,
`base` (looping idle/walk) + `action` (transition 0, triggerables only). Do not add a
third controller without talking to the integrator — the names are frozen in plan §6.

Client (`dev.projecteclipse.eclipse.client.entity.geo`):

```java
public class FogRevenantRenderer extends EclipseGeoRenderer<FogRevenantEntity> {
    public FogRevenantRenderer(EntityRendererProvider.Context ctx) {
        super(ctx, "fog_revenant", true);        // true = head tracking (bone MUST be `head`)
        withGlowmask();                          // ships textures/entity/<id>_glowmask.png
        withUprightDeath();                      // zero death tip-over for scripted deaths
        // withTranslucency();                   // ONLY if the albedo uses partial alpha
    }
}
```

Registration is a one-liner in your family's own `@EventBusSubscriber(Dist.CLIENT)` class
(no layer definitions, no bakeLayer) — copy `client/entity/ambient/AmbientRenderers.java`
including the `DeferredHolder.isBound()` guard.

**Registrar + wiring:** one `DeferredRegister<EntityType<?>>` class per family (copy
`entity/ambient/AmbientEntities.java`): attributes via a guarded
`@SubscribeEvent EntityAttributeCreationEvent` in the same class, a static
`register(IEventBus)` hook, and ONE wiring line dropped in your worker's wiring doc under
`docs/plans_v3/wiring/` — never edit `EclipseMod.java` yourself. The `isBound()` guards
keep boots green until the integrator applies the line.

**Death convention:** trigger `death` from `die()` (the base's default `action` trigger
plays-and-holds `animation.<id>.death`), override `tickDeath()` for the scripted window
(sheet length, e.g. 30t; end with `broadcastEntityEvent(this, EntityEvent.POOF)` +
`remove(RemovalReason.KILLED)` — Ferryman precedent), and call `withUprightDeath()` on
the renderer. Without all three you get the vanilla 20t red-flash tip-over.

## 4. Textures — painter pipeline (deterministic Pillow)

Driver per mob: `scripts/geckolib_gen/mobs/<id>.py` (copy `drift_lantern.py`). It parses
YOUR geo (no hand-written UV tables), declares palette + per-bone materials, and one run
writes `<id>.png` AND `<id>_glowmask.png`. Fixed seed per mob → byte-identical reruns
(commit script + both PNGs; AI art replaces PNGs later at identical paths/sizes).

```python
p = GeoPainter(GEO_PATH, seed=0x...)
p.set_material("body", metal(hexc("#3B3F46")))       # exact name or fnmatch ("tendril_*")
p.set_cube_material("body", 0, glass(hexc("#9FB8C4", 102)))   # per-cube override
p.set_glow("glow_*")            # optional — glow_ bones are ALREADY auto-included
p.set_glow_painter("cage", fn)  # custom glowmask pixels (rims, shine-through)
p.paint(OUT_PNG)
```

Built-in materials: `flat`, `weave` (cloth/fur, 3 grain directions), `wood`, `metal`,
`glass` (partial alpha + opaque-ish rim), `flame` (shadeless emissive core→tip), `kelp`
(ragged alpha-cutout hems). All get per-face directional shading (top 1.18 / bottom 0.62
/ sides mid) + a 1px inner outline unless the material sets `.shadeless = True`
(emissive regions stay full painted brightness — `EntitySkinArtist` rule, and the reason
glowmasked pixels still read under Iris shaderpacks, which dim glow layers to albedo).

**Glowmask rules:** emissive pixels only, transparent elsewhere, same canvas.
**Inner glow through a translucent shell:** the glow layer re-renders geometry at its
original depth, so an inner `glow_` bone's glowmask is depth-rejected underneath a
translucent covering cube — paint the shine-through INTO THE SHELL's glowmask pixels
instead (see `mobs/drift_lantern.py::cage_glow` + `docs/uv/drift_lantern.md`).

## 5. Validation loop (MANDATORY per mob, plan §2.2)

1. Author geo per your sheet's silhouette (16 px = 1 block; keep inside the hitbox).
2. `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>` — pass BOTH files in one
   call so animation bone names are cross-checked. Zero errors before continuing
   (warnings are judgement calls). It prints the bone tree + keyframe stats.
3. Run your painter driver; eyeball both PNGs (any image viewer; 8× nearest-neighbor).
4. `./gradlew build` → `runClient` → world → `/summon eclipse:<id> ~2 ~ ~` → screenshot
   front/side/¾ + one clip per animation (walk by luring, attack by getting hit, special
   via its trigger, death via `/kill`). Missing-asset errors in the log name the exact
   path GeckoLib wanted. Iterate until the silhouette matches the sheet.
5. Commit `docs/uv/<id>.md` (art brief + palette + emissive regions + generator command).

Testability note (in-game steps require the wiring line): until the integrator applies
your `register(modEventBus)` line, `/summon eclipse:<id>` reports an unknown entity —
apply your wiring line locally while testing, but COMMIT only the wiring doc entry.

## 6. Known runtime gotchas (pre-verified so you don't rediscover them)

* `state.isMoving()` uses vanilla limb-swing — tick-driven drifters (setPos movement)
  never trip it; read your own position delta in `handleBaseState` (Drift Lantern).
* Partial-alpha albedo NEEDS `withTranslucency()`; the cutout default renders 40%-alpha
  pixels fully opaque.
* GeckoLib triggered anims (`triggerAction`) are server→client synced by GeckoLib itself;
  no payloads needed. Controllers exist on both sides — never touch client classes from
  entity code.
* Veil post pipelines are orthogonal to GeckoLib render types (plan §5); under Iris
  shaderpacks glowmasks dim — keep emissive regions bright in the ALBEDO too (the
  painter's shadeless materials already do).
* `AutoGlowingTexture` hard-fails mismatched glowmask dimensions at texture load: always
  regenerate both PNGs together (one driver run does).
