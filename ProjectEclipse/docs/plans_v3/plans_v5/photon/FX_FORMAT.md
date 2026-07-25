# Photon `.fx` Effect File Format — Complete Reverse-Engineered Reference

**Source of truth**: full Vineflower decompile of `run/mods-client/photon-neoforge-1.21.1-2.1.5.jar`
(and `ldlib2-neoforge-1.21.1-2.2.29.jar` for the serialization framework), decompiled to
`/tmp/photon_dec2` / `/tmp/ldlib2_dec` (PHOTON-EXPLORE-2, 2026-07). Every field name, default,
enum constant and NBT encoding below was read from bytecode, not docs or memory.
Companion docs: `API.md` (runtime API), `INTEGRATION.md` (Eclipse wiring/safety).

**Headline facts**

- A `.fx` file is **NOT JSON**. It is a **gzip-compressed NBT CompoundTag** written by
  `NbtIo.writeCompressed` and read by `NbtIo.readCompressed` (`FXHelper.loadFX`).
- The jar ships **zero bundled example `.fx` files** — `assets/photon/` contains only shaders,
  textures, GUI icons and lang. The format is defined 100% in code; effects are authored in the
  in-game editor (`/photon_editor`, singleplayer only) and exported via *File → Export → export fx*.
- Load path: `assets/<namespace>/fx/<path>.fx` for `ResourceLocation <namespace>:<path>`
  (`FXHelper.FX_PATH = "fx/"`, suffix `".fx"` appended automatically). Cached forever in a static
  map (cleared by `/photon_client clear_client_fx_cache`); a failed load returns `null` and is not cached.
- Conceptually it is a **Unity ParticleSystem clone**: one file = a scene of emitter
  "GameObjects" with Transforms, each carrying a config of toggleable modules whose values are
  Unity-style `NumberFunction`s (constant / random-between / Bézier curve / random-between-curves /
  color / gradient / random-gradient).

---

## 1. Container & top-level schema

```
<root> (CompoundTag, gzip)
└─ fxData: Compound
   └─ fxObjects: List<Compound>           // FLAT list of all objects incl. children
      └─ each: { type: String, data: Compound }   // registry-dispatch wrapper
```

- `type` is a **plain string key** into the client registry `photon:fx_object`
  (LDLib `LDLRegistry.String`); `data` is produced by `PersistedParser` (see §2).
- Registered `type` values (from `@LDLRegisterClient` annotations):

| `type` | Class | Purpose |
|---|---|---|
| `particle_emitter` | `ParticleEmitter` | Unity-style billboard/model particle system |
| `trail_emitter` | `TrailEmitter` | standalone emitter-following trail strip |
| `ara_trail_emitter` | `AraTrailEmitter` | high-quality ribbon trail (Ara-style, physics, custom cross-section) |
| `beam_emitter` | `BeamEmitter` | start→end beam quad with raycast clipping |
| `empty` | `EmptyFXObject` | grouping/pivot node (no rendering) |

- **Hierarchy is flat + UUID-relinked**: every object's `data.transform` persists
  `id` (UUID string), `_parentId` (UUID string, absent for root-level objects) and
  `_childrenId` (list of UUID strings, defines child order). `FXRuntime` re-parents anything
  without a parent under an internal root (`UUID(0,0)`). Nesting emitters under an `empty`
  gives shared transform animation.

### 1.1 `.fxproj` vs `.fx`

The editor project file (`.fxproj`) wraps the same data as
`{meta: {version_num: 3, ...}, data: {fx: {fxData: ...}, resources: ...}}` and runs a
DataFixerUpper chain on load (see §8). The exported `.fx` file contains **only**
`{fxData: {...}}` — no top-level version field; per-emitter versioning is inside `data.version`.

---

## 2. Serialization framework (how `data` compounds are built)

LDLib2's `PersistedParser` reflects over `@Configurable` / `@Persisted` fields:

- **NBT key = Java field name** (unless annotation `key` overrides — none in Photon).
- Fields marked `subConfigurable/subPersisted = true` become **nested compounds**.
- Any field whose value implements `INBTSerializable` uses its own `serializeNBT`.
- Missing keys on read ⇒ field keeps its Java default. So minimal hand-written files
  are legal: **omit anything you leave at default** (this is also what keeps files small).
- **Toggle modules** (`ToggleGroup`/`IToggleConfigurable`) write `_enable: Byte(0|1)`. When
  disabled they serialize *only* `{_enable:0b}`; when a module compound is absent entirely the
  module is disabled (Java default `enable=false`).
- **`@ReadOnlyManaged` lists** (bursts, sub-emitter entries, renderer materials) encode as
  `{uid: Int(count), payload: List<Compound>}` — `uid` is literally the element count used to
  pre-instantiate defaults, `payload` the per-element compounds.

Leaf-type NBT encodings (from `AccessorRegistries` + `LDLibExtraCodecs`):

| Java type | NBT encoding |
|---|---|
| `boolean` | Byte 0/1 |
| `int/float/...` | matching numeric tag |
| `Number` (e.g. `Constant.number`) | tag type preserved (Int vs Float both accepted; readers call `.intValue()/.floatValue()`) |
| enums | String of the enum constant name (e.g. `"Exacting"`, `"Translucent"`, `"SRC_ALPHA"`) |
| `Vector2i` | List\<Int\>[2] |
| `Vector3f` | List\<Float\>[3] (vanilla `ExtraCodecs.VECTOR3F`) |
| `Vector4f` | List\<Float\>[4] |
| `Quaternionf` | List\<Float\>[4] = x,y,z,w |
| `UUID` | String |
| `ResourceLocation` | String |
| `AABB` | `{min: List<Double>[3], max: List<Double>[3]}` |
| `GradientColor` | `{a: List<Float> flat (t,alpha)*, rgb: List<Float> flat (t,r,g,b)*}` (floats 0–1) |
| `ECBCurves` | List of segments; each segment = List\<Float\>[8] = p0x,p0y,c0x,c0y,c1x,c1y,p1x,p1y (x and y normalized 0–1) |

### 2.1 `NumberFunction` — the universal value type

Registry `photon:number_function`, same `{type,data}` wrapper. This is the single most
important concept: nearly every knob is one of these.

| `type` | `data` fields | Semantics |
|---|---|---|
| `constant` | `number: Number` | fixed value |
| `random_constant` | `a, b: Number` | uniform random in [min(a,b),max(a,b)], **memoized per particle** |
| `curve` | `min,max,lower,upper: Float; xAxis,yAxis: String; lockControlPoint: Byte; curves: ECBCurves` | value = `lower + (upper-lower) * bezierY(t)`; `t` is the module-specific input (emitter t, particle lifetime t, speed…). `min/max/xAxis/yAxis` are editor metadata only |
| `random_curve` | like `curve` but `curves0`, `curves1` | random lerp between two curves (lerp factor memoized per particle) |
| `color` | `number: Int` (ARGB) | fixed color, −1 = opaque white |
| `random_color` | `a, b: Int` | random ARGB lerp between two colors |
| `gradient` | `gradientColor: GradientColor` | color over the input axis |
| `random_gradient` | `gradientColor0, gradientColor1` | random lerp between two gradients |

`NumberFunction3` (vector version, e.g. `startSize`, `velocityOverLifetime.linear`) = plain
**List of exactly 3 NumberFunction wrappers** `[{type,data},{type,data},{type,data}]` (x,y,z).
When one random lerp `Supplier` is shared across the 3 axes the same roll is used (uniform scale
if all three are identical random functions).

Time units everywhere: **ticks** (durations, lifetimes, delays); rates are per tick.
Colors: packed ARGB ints or normalized floats in gradients.

---

## 3. `particle_emitter` full schema (`data` compound)

```
data: {
  version: Int = 2                    // written by ParticleEmitter.serializeNBT
  name: String                        // FXObject.name — findObject(name) handle
  transform: { id, localPosition, localRotation(quat), localScale, _parentId?, _childrenId }
  config: ParticleConfig {...}        // everything below
}
```

### 3.1 Main block (always present)

| key | type | default | notes |
|---|---|---|---|
| `duration` | Int | 100 | emitter cycle length in ticks |
| `looping` | Byte | 1 | restart cycle when duration ends |
| `prewarm` | Int | 0 | simulate N update steps on first tick (loop warm-up) |
| `startDelay` | NF (Constant/Random/Curve/RandomCurve, int) | 0 | per-emitter delay ticks |
| `startLifetime` | NF int | 100 | per-particle lifetime ticks |
| `startSpeed` | NF | 1 | initial speed along shape normal |
| `startSize` | NF3 | (0.1,0.1,0.1) | blocks; billboards use x/y |
| `startRotation` | NF3 | (0,0,0) | degrees; only Z (roll) for billboards |
| `startColor` | NF color-family | −1 (white) | ARGB tint |
| `simulationSpace` | enum `Local`\|`World` | `Local` | Local = particles follow the emitter transform |
| `maxParticles` | Int | 2000 | hard cap (emission stops at cap) |
| `parallelUpdate` | Byte | 0 | multithreaded particle update (no level access allowed in updates) |
| `parallelRendering` | Byte | 0 | multithreaded vertex building |

### 3.2 Always-on sub-compounds

**`emission`** (`EmissionSetting`, no `_enable`):
`emissionRate` NF (particles/tick, fractional accumulates; default 0.5) · `distanceRate` NF
(particles per block moved) · `emissionMode` enum `Exacting`|`Random` (how fractional rate is
dithered) · `bursts` ROM-list of `{time: Int(tick in cycle), count: NF, cycles: Int (0 = ∞),
interval: Int(ticks), probability: Float 0–1}`.

**`shape`** (`ShapeSetting`): `shape: {type,data}` from registry `photon:shape` +
`position`/`rotation`(deg)/`scale` NF3 evaluated over emitter t (animatable emission origin).

| shape `type` | `data` fields (defaults) | notes |
|---|---|---|
| `dot` | — | point emission, zero velocity |
| `sphere` | `radius:0.5, radiusThickness:1.0 (0=shell only), arc:360, shapeArc:{...}` | velocity = radial |
| `circle` | same as sphere | XZ ring/disc |
| `cone` | `angle:25, radius:0.5, radiusThickness:1, arc:360, shapeArc` | classic fountain |
| `cylinder` | `radius:0.5, radiusThickness:1, arc:360, shapeArc` | volume column |
| `box` | `emitFrom: enum Volume|Shell|Edge` | unit cube scaled by shape scale |
| `mesh` | `type: enum Vertex|Edge|Triangle, meshData:{modelLocation: RL = "block/stone"}` | **emit from any baked block/item model geometry** |
| `function` | `x,y,z,speedX,speedY,speedZ: String` | math expressions, see §7 |

`shapeArc` sub-compound: `{arcMode: enum Random|Loop|PingPong|BurstSpread, arcSpread: Float,
arcSpeed: NF}` — Unity's arc emission modes for ring sweeps.

**`renderer`** (`ParticleRendererSetting`, no `_enable`):

- `materials`: ROM-list of `MaterialSetting` (multi-material = multi-pass!). Each:
  `{material: {type,data} (§6), blendMode: {enableBlend: Byte=1, srcColorFactor/dstColorFactor/
  srcAlphaFactor/dstAlphaFactor: GL factor enum names (SRC_ALPHA, ONE, ONE_MINUS_SRC_ALPHA, ZERO…),
  blendFunc: enum ADD|SUB|REVERSE_SUB|MIN|MAX}, cull: Byte=1, depthTest: Byte=1, depthMask: Byte=0}`
- `renderMode`: enum `None | Billboard | Horizontal | Vertical | VerticalBillboard |
  StretchedBillboard | Model` — `Model` renders each particle as the baked model from the mesh
  shape/`useBlockUV`; `StretchedBillboard` uses `velocityScale` (stretch × speed) + `lengthScale`.
- `facingMode`: enum `DEFAULT | ROTATE_Y | LOOKAT_XYZ | LOOKAT_Y | LOOKAT_DIRECTION |
  DIRECTION_X/Y/Z | EMITTER_TRANSFORM_XY/XZ/YZ` + `facingDirection:
  {mode: DERIVE_FROM_VELOCITY|CUSTOM_DIRECTION, minSpeedThreshold: 0.01, customDirection: [0,1,0]}`
- `shade: Byte=1` (apply world lightmap), `useGPUInstance: Byte=0` (**GPU instanced path**),
  `modelPivot: Vector3f`, `layer: enum Opaque|Translucent`, `orderInLayer: Int`,
  `vertexSortingMode: enum NONE|DISTANCE`, `cull: {_enable, cullBox: AABB}` (render-culling box,
  editor icon "cull_box").

### 3.3 Toggle modules (each `{_enable: Byte, ...}`; omit = off)

| module key | fields (defaults) | input axis |
|---|---|---|
| `physics` | `hasCollision:1b, removedWhenCollided:0b, friction: NF=1 (velocity ×/tick), collidedFriction: NF=0.7, gravity: NF=0 (blocks/tick², applied ×0.04), bounceChance: NF=1, bounceRate: NF=1, bounceSpreadRate: NF=0` | real world-collider (`Entity.collideBoundingBox`), per-axis bounce reflection |
| `lights` | `skyLight: NF=15, blockLight: NF=15` | **forced lightmap** over particle lifetime (fake glow, not a dynamic light) |
| `velocityOverLifetime` | `linear: NF3, orbitalMode: AngularVelocity\|LinearVelocity\|FixedVelocity, orbital: NF3, offset: NF3 (orbit center), radial: NF, speedModifier: NF=1` | particle t |
| `inheritVelocity` | `mode: CURRENT\|INITIAL, multiply: NF=1` | emitter velocity → particle |
| `lifetimeByEmitterSpeed` | `multiplier: NF=1, speedRange: {min,max}=0–1` | kill faster when emitter fast |
| `forceOverLifetime` | `force: NF3, simulationSpace: Local\|World` | acceleration/tick |
| `colorOverLifetime` | `color: NF gradient-family` | multiplied with startColor |
| `colorBySpeed` | `color: NF gradient-family, speedRange: {min,max}` | speed remap 0–1 |
| `sizeOverLifetime` | `size: NF3` | multiplier |
| `sizeBySpeed` | `size: NF3, speedRange` | multiplier |
| `rotationOverLifetime` | `roll, pitch, yaw: NF` (deg/tick) | additive spin |
| `rotationBySpeed` | `roll, pitch, yaw: NF, speedRange` | |
| `noise` | `frequency: 1.0, quality: Noise1D\|Noise2D\|Noise3D, remap: {_enable, remapCurve: NF curve}, position: NF3=0.1, rotation: NF=0, size: NF=0` | procedural turbulence on pos/rot/size |
| `uvAnimation` | `tiles: [Int,Int]=[1,1], animation: WholeSheet\|SingleRow, frameOverTime: NF=0, startFrame: NF=0, cycle: Float=1` | sprite-sheet flipbook over lifetime |
| `trails` | `ratio:1.0, lifetime: NF 0–1 (fraction of particle lifetime), dieWithParticles:0b, sizeAffectsWidth:1b, sizeAffectsLifetime:0b, inheritParticleColor:1b, colorOverLifetime: NF color-family, trailType: TRAIL\|ARA_TRAIL` **plus embedded full `config` (TrailConfig §4.2) and `araConfig` (AraTrailConfig §4.3)** | per-particle ribbon trails |
| `subEmitters` | `emitters` ROM-list of `{fxLocation: RL of another .fx!, event: Birth\|Death\|Collision\|FirstCollision\|Tick, emitProbability: NF, tickInterval: Int=1, inheritColor/Size/Rotation/Lifetime/Duration: Byte}` | spawns whole child FX files on particle events |
| `additionalGPUDataSetting` | `additionalData: List<String>` of channel names: `addition_gpu_data.random/t/age/lifetime/position/velocity/isCollided/emitter_t/emitter_age/emitter_position/emitter_velocity` | extra per-instance vertex data for custom shaders (GPU-instance mode) |

---

## 4. Other emitter types

### 4.1 `beam_emitter` → `data.config` (`BeamConfig`)

`duration: 100, looping: 1b, startDelay: Int, end: Vector3f=[0,0,-3] (local-space endpoint),
width: NF=0.2, emitRate: NF=0 (re-trigger interval; 0 = continuous),
raycast: NONE|BLOCKS|ENTITIES|BLOCKS_AND_ENTITIES` (beam clipped to first hit!),
`raycastBlockMode: ClipContext.Block enum (VISUAL…), raycastFluidMode: ClipContext.Fluid enum (NONE…),
color: NF color-family, renderer: RendererSetting (materials/layer/cull/order/sort),
uvAnimation, lights`. Writes `version: 2`.

### 4.2 `trail_emitter` → `data.config` (`TrailConfig`) — also embedded in `trails.config`

`duration, looping, startDelay, time: Int=20` (segment retention ticks = trail length),
`minVertexDistance: 0.05` (min blocks between vertices), `smoothInterpolation: 0b`
(Catmull-Rom smoothing — GPU compute shader `catmull_rom.comp`), `parallelRendering: 0b`,
`uvMode: enum Stretch|PerSegment|DistancePerSegment(?)` (`TrailParticle.UVMode`),
`widthOverTrail: NF (Constant/Curve only) = 0.2, colorOverTrail: NF color-family,
renderer, lights, uvAnimation`. Writes `version: 2`.

### 4.3 `ara_trail_emitter` → `data.config` (`AraTrailConfig`) — also embedded as `trails.araConfig`

The premium ribbon: `section: {vertices: List<Vector2f>}` (**custom 2D cross-section polygon** —
default flat strip, can be a star/tube), `space: World|Local|Custom (+customSpace TransformRef)`,
`alignment: View|Velocity|Local`, `sorting: OlderOnTop|NewerOnTop`, `thickness: 0.2`,
`smoothness: Int 1–8` (Catmull-Rom subdivision), `smoothingDistance: 0.05`,
`highQualityCorners: 0b`, `cornerRoundness: Int 5 (0–12)`,
`thicknessOverLength/thicknessOverTime/thicknessOverSegmentTime: NF (Constant/Curve)`,
`colorOverLength/colorOverTime/colorOverSegmentTime: NF color-family`,
`emit: 1b, initialThickness: 1.0, initialColor: Int=-1, initialVelocity: Vector3f,
timeInterval: 0.05 (s between segment drops), minDistance: 0.025, time: 1.0 (segment life, seconds)`,
`physicsSetting: {warmup: 0.0, gravity: Vector3f, inertia: 0–1, velocitySmoothing: 0.75, damping: 0.75}`
(ribbon segments physically lag/swing!), `textureMode: Stretch|Tile|WorldTile`,
`uvFactor/uvWidthFactor: 1.0, tileAnchor: 0–1`, `renderer`. Writes `version: 2`.

---

## 5. Materials (registry `photon:material`, wrapper `{type,data}`)

| `type` | `data` fields | use |
|---|---|---|
| `texture` | `texture: RL = "photon:textures/particle/circle.png", discardThreshold: 0.1, hdr: Vector4f=[0,0,0,1] (RGB emission boost), hdrMode: ADDITIVE\|MULTIPLICATIVE, pixelArt: {_enable,...bits: 8}` | any standalone PNG; **hdr feeds the bloom pipeline** |
| `sprite` | `spriteLocation: RL, discardThreshold, hdr, hdrMode` | atlas sprite (works with animated `.mcmeta` sprites) |
| `block_atlas` | — (singleton) | vanilla block atlas; pair with `useBlockUV` + Model mode |
| `custom_shader` | `shaderLocation: RL = "photon:circle", curveTexture: {curves: List<Curve>}, gradientTexture: {gradients: List<GradientColor>}` | **own fragment shader**, with authored curves/gradients uploaded as 128×128 LUT textures |
| `ui_resource_material` | `resourcePath` | editor UI resource |
| `missing` | — | fallback (pink) |

Bloom/HDR: shaders `hdr_particle`, `sprite_hdr_particle`, `pixel_hdr_particle` write emissive
output; `PhotonPostProcessing` runs bright-pass → mip down/up-sampling → `unreal_composite`
(or scatter mode). Global client config `photon-client.toml`: `enable_bloom` (default true),
`bloom_mip_level` 5, `bloom_threshold` 1.0, `bloom_intensity` 0.7, `enable_bloom_with_iris_shader`,
`iris_shader_compatible_mode` (mixins hook Iris' `ExtendedShader`).

---

## 6. Expression language (`function` shape only)

Photon embeds a tiny recursive-descent parser (`expr` package — not Molang, not MoLang-compatible):

- Variables: `t` (emitter cycle progress 0–1), `PI`, `randomA`–`randomE` (fresh uniform rolls per emission).
- Unary functions: `abs acos asin atan ceil cos exp floor log round sin sqrt tan`; binary: `atan2 max min`.
- Operators: `+ - * / ^` (pow), comparisons `< <= = != >= >` (1/0), logical and/or; `x?y:z` conditional (ConditionalExpr).
- Six string fields: `x y z` (spawn position) and `speedX speedY speedZ` (initial velocity).
- Example spiral: `x = "0.8*cos(t*2*PI)"`, `z = "0.8*sin(t*2*PI)"`, `y = "t*2"`.

Everywhere else animation is **cubic-Bézier curves, not expressions** (no Molang anywhere).

---

## 7. Capability comparison vs our Veil/Quasar stack

Quasar (Veil 4.3.0, `foundry.veil.api.quasar`) — what it has that Photon lacks: MoLang
interpolants (`q.agePercent` etc.), true **dynamic deferred lights** (`DynamicLightModule` — Photon's
`lights` module only forces lightmap values), vector-field/wind/vortex/point-attractor forces,
hand-editable JSON (`assets/eclipse/quasar/emitters/*.json`, 63 files in repo), server-safe data
definitions. Keep Quasar for: ambient world FX, light-emitting FX, anything we want diffable in PRs.

**What Photon can do that Quasar CANNOT** (these drive where we use Photon):

1. **Bloom/HDR emissive particles** — per-material `hdr` boost + full post-processing bloom chain
   with Iris/Sodium compat. Quasar/Veil has post pipelines but no per-particle-material bloom tagging.
2. **Mesh/model particles** — emit *from* any baked model's vertices/edges/triangles (`mesh` shape)
   and render particles *as* models (`renderMode: Model`, block-atlas UVs). Quasar is billboard/quad only.
3. **Ribbons/beams as first-class emitters** — `ara_trail_emitter` (physics-lagged ribbon, custom
   cross-section polygon, Catmull-Rom GPU smoothing, corner rounding) and `beam_emitter` with
   **raycast clipping** vs blocks/entities. Quasar's `TrailParticleModule` is a simple point trail.
3. **GPU instancing + parallel update/render** (`useGPUInstance`, `parallelUpdate`,
   `parallelRendering`, custom per-instance data channels) — 10⁴–10⁵ particle budgets.
4. **Unity-grade authoring**: in-game visual editor, Bézier curves & gradients on ~40 properties,
   random-between-curves, bursts (cycles/interval/probability), distance-rate emission, prewarm,
   arc emission modes, UV flipbooks (sheet/row), speed-mapped color/size/rotation, noise fields
   with remap curves, sub-emitters on Birth/Death/Collision/FirstCollision/Tick that spawn
   *other .fx files* with inheritance flags.
5. **Real collision physics** — world-collider + bounce chance/rate/spread + collided friction +
   `removedWhenCollided` + collision-triggered sub-emitters. Quasar's collision module is basic.
6. **Custom shader materials** with authored curve/gradient LUT textures and per-material GL blend
   equations (ADD/SUB/REVERSE_SUB/MIN/MAX, separate alpha factors), depth-mask/cull/depth-test control,
   layer + explicit order + distance sorting, per-emitter cull boxes, pixel-art AA mode.

Trade-offs to remember: `.fx` is a **binary blob** (bad diffs — commit the `.fxproj` too),
client-only mod (our reflection bridge, see `INTEGRATION.md`), editor is singleplayer-only.

---

## 8. Versioning & migration

- **Emitter-level**: `data.version` Int — currently **2** for particle/trail/beam/ara-trail
  emitters. Written on save; there is no read-side fixer for it in 2.1.5 (it is a forward marker).
- **Project-level** (`.fxproj` only): `meta.version_num` — currently **3**; DataFixerUpper chain
  `PhotonFXProjectDataFixer`:
  - v1→v2 `MaterialToRendererMaterialsFix`: single `config.material` → `config.renderer.materials`
    ROM-list (`{uid:1, payload:[material]}`), also inside `trails.config`.
  - v2→v3 `UVAnimationTilesFix`: `uvAnimation.tiles` `{a,b}` compound → `[Int,Int]` list.
- **Photon 1.x → 2.x**: whole-format break; `/photon convert` command migrates old files from
  `ldlib2/assets/photon/fx_old`.
- Unknown `type` strings or failed codec parses are **silently dropped** (objects) or fall back to
  defaults (`Dot` shape, `MISSING` material, `ZERO` number function) — hand-written files fail soft.

## 9. File size & performance characteristics

- Format is gzip NBT: our two structurally-complete templates below measured
  **raw NBT ≈ 3.5–3.6 KB, gzipped ≈ 1.25–1.3 KB** each (built + re-parsed with a Python NBT
  writer at `/tmp/build_fx.py`, outputs `/tmp/template_burst.fx`, `/tmp/template_loop.fx`).
  Rich multi-emitter editor exports are typically a few 10s of KB. Negligible vs textures.
- Loaded `FX` objects are cached; each play deep-copies `fxData` through the codec
  (`createRuntime()`), so file complexity costs CPU per spawn — prefer `allow multi=false`
  executor semantics for repeating effects.
- Perf knobs, cheapest first: `maxParticles`, cull box (`renderer.cull`), `vertexSortingMode: NONE`,
  `parallelUpdate/parallelRendering` (no world access in update), `useGPUInstance` for big counts,
  bloom off via config. Physics collision is the most expensive module (world queries per particle).
- Prewarm runs full update steps on first tick — keep `prewarm` modest (< duration).

---

## 10. Authoring cheat-sheet + two commented templates

Workflow options:
1. **Editor (recommended)**: singleplayer → `/photon_editor` → author → File→Export→`.fx` into
   `assets/eclipse/fx/…` (also keep the `.fxproj`). Reload with `/photon_client clear_client_fx_cache` + F3+T.
2. **Programmatic**: write the NBT below with any NBT lib and `NbtIo.writeCompressed` (or our
   `/tmp/build_fx.py` generator pattern) — legal because absent keys = defaults.

Golden rules: omit modules you don't use · `_enable:1b` on every module you do use ·
`looping:0b` + a burst = one-shot; `looping:1b` + `emissionRate` = ambient ·
World space for debris that must linger, Local for auras that follow ·
color = `colorOverLifetime` gradient × `startColor` · sizes in blocks, times in ticks.

Below are the two validated templates in annotated SNBT-style pseudocode
(`b`=Byte, `f`=Float, bare=Int, `[…]`=List; comments `//` are not part of the file).

### Template A — `template_burst.fx` (one-shot impact burst)

```snbt
{ fxData: { fxObjects: [
  { type: "particle_emitter",
    data: {
      version: 2,
      name: "spark_burst",                       // lookup handle: runtime.findObject("spark_burst")
      transform: {                                // identity transform at executor origin
        id: "5be0c18e-...uuid...",                // any unique UUID string
        localPosition: [0f,0f,0f], localRotation: [0f,0f,0f,1f], localScale: [1f,1f,1f],
        _childrenId: [] },                        // no _parentId => parented to runtime root
      config: {
        duration: 40, looping: 0b,                // ONE-SHOT: 2s window, no restart
        startLifetime: {type:"random_constant", data:{a:18, b:32}},   // 0.9–1.6s sparks
        startSpeed:    {type:"random_constant", data:{a:0.35f, b:0.85f}},
        startSize: [ {type:"random_constant", data:{a:0.08f, b:0.16f}},  // NF3 = [x,y,z]
                     {type:"random_constant", data:{a:0.08f, b:0.16f}},
                     {type:"random_constant", data:{a:0.08f, b:0.16f}} ],
        startRotation: [ {type:"constant",data:{number:0}}, {type:"constant",data:{number:0}},
                         {type:"random_constant", data:{a:0f, b:360f}} ],  // random roll
        startColor: {type:"color", data:{number:-1}},                  // white, tinted below
        simulationSpace: "World",                 // debris keeps flying if source moves
        maxParticles: 256,
        emission: {                               // rate 0 — bursts only
          emissionRate: {type:"constant", data:{number:0f}},
          distanceRate: {type:"constant", data:{number:0}},
          emissionMode: "Exacting",
          bursts: { uid: 1, payload: [            // @ReadOnlyManaged: uid = count
            { time: 0,                            // fire at tick 0 of the cycle
              count: {type:"constant", data:{number:40}},
              cycles: 1, interval: 1, probability: 1.0f } ] } },
        shape: {                                  // spherical shell => clean radial spray
          shape: { type: "sphere", data: {
            radius: 0.35f, radiusThickness: 0f,   // 0 = surface only
            arc: 360f,
            shapeArc: { arcMode:"Random", arcSpread:0f,
                        arcSpeed:{type:"constant",data:{number:1f}} } } },
          position: [ {type:"constant",data:{number:0}} x3 ],   // (write all three entries)
          rotation: [ {type:"constant",data:{number:0}} x3 ],
          scale:    [ {type:"constant",data:{number:1}} x3 ] },
        renderer: {
          materials: { uid: 1, payload: [ {
            material: { type: "texture", data: {
              texture: "photon:textures/particle/circle.png",   // bundled soft dot
              discardThreshold: 0.05f,
              hdr: [0f,0f,0f,1f], hdrMode: "ADDITIVE",          // raise RGB for bloom glow
              pixelArt: {_enable: 0b} } },
            blendMode: { enableBlend:1b, srcColorFactor:"SRC_ALPHA", dstColorFactor:"ONE",
                         srcAlphaFactor:"ONE", dstAlphaFactor:"ZERO", blendFunc:"ADD" }, // additive
            cull:1b, depthTest:1b, depthMask:0b } ] },
          layer: "Translucent", cull: {_enable:0b}, orderInLayer: 0,
          vertexSortingMode: "NONE",              // additive => order-independent
          renderMode: "Billboard", shade: 0b, useBlockUV: 0b,
          modelPivot: [0f,0f,0f], velocityScale: 0f, lengthScale: 2f,
          useGPUInstance: 0b, facingMode: "DEFAULT" },
        physics: { _enable: 1b,                   // sparks bounce off the floor
          hasCollision: 1b, removedWhenCollided: 0b,
          friction:         {type:"constant", data:{number:0.98f}},  // air drag ×/tick
          collidedFriction: {type:"constant", data:{number:0.6f}},
          gravity:          {type:"constant", data:{number:0.35f}},
          bounceChance:     {type:"constant", data:{number:0.6f}},
          bounceRate:       {type:"constant", data:{number:0.4f}},   // 40% energy kept
          bounceSpreadRate: {type:"constant", data:{number:0.1f}} },
        colorOverLifetime: { _enable: 1b,         // white-hot -> ember -> fade out
          color: { type: "gradient", data: { gradientColor: {
            a:   [0f,1f,  0.6f,0.9f,  1f,0f],                      // flat (t,alpha) pairs
            rgb: [0f,1f,0.95f,0.7f,  0.5f,1f,0.65f,0.2f,  1f,0.6f,0.1f,0.05f] } } } }, // (t,r,g,b)
        sizeOverLifetime: { _enable: 1b,          // pop in, shrink to 0
          size: [ { type:"curve", data: { min:0f, max:1.5f, lower:0f, upper:1.5f,
                    xAxis:"lifetime", yAxis:"size", lockControlPoint:1b,
                    curves: [[0f,0.66f, 0.1f,1f, 0.9f,0.2f, 1f,0f]] } }  x3 ] },  // 1 bezier seg
        lights: { _enable: 1b,                    // fake glow: fullbright sparks
          skyLight:   {type:"constant",data:{number:15}},
          blockLight: {type:"constant",data:{number:15}} }
} } } ] } }
```

### Template B — `template_loop.fx` (looping magical aura column)

```snbt
{ fxData: { fxObjects: [
  { type: "particle_emitter",
    data: {
      version: 2,
      name: "aura_loop",
      transform: { id:"...uuid...", localPosition:[0f,0f,0f],
                   localRotation:[0f,0f,0f,1f], localScale:[1f,1f,1f], _childrenId: [] },
      config: {
        duration: 60, looping: 1b, prewarm: 20,   // LOOP; prewarm hides cold start
        startLifetime: {type:"random_constant", data:{a:40, b:60}},   // 2–3s motes
        startSpeed:    {type:"random_constant", data:{a:0.05f, b:0.15f}},
        startSize: [ {type:"random_constant", data:{a:0.15f,b:0.3f}} x3 ],
        startRotation: [ {type:"constant",data:{number:0}}, {type:"constant",data:{number:0}},
                         {type:"random_constant",data:{a:0f,b:360f}} ],
        startColor: {type:"color", data:{number:-1}},
        simulationSpace: "Local",                 // aura follows its anchor entity/block
        maxParticles: 400,
        emission: {                               // steady trickle, no bursts
          emissionRate: {type:"constant", data:{number:1.5f}},        // 1.5 motes/tick
          distanceRate: {type:"constant", data:{number:0}},
          emissionMode: "Exacting",
          bursts: { uid: 0, payload: [] } },
        shape: {                                  // ring wall sweeping around anchor
          shape: { type: "cylinder", data: {
            radius: 0.9f, radiusThickness: 0.15f, // thin shell => ring, not volume
            arc: 360f,
            shapeArc: { arcMode: "Loop",          // emission point ORBITS the ring
                        arcSpread: 0f,
                        arcSpeed: {type:"constant",data:{number:0.5f}} } } },  // laps/cycle
          position: [ {type:"constant",data:{number:0}} x3 ],
          rotation: [ {type:"constant",data:{number:0}} x3 ],
          scale:    [ {type:"constant",data:{number:1}} x3 ] },
        renderer: {
          materials: { uid: 1, payload: [ {
            material: { type: "texture", data: {
              texture: "photon:textures/particle/smoke.png",
              discardThreshold: 0.05f, hdr:[0f,0f,0f,1f], hdrMode:"ADDITIVE",
              pixelArt: {_enable:0b} } },
            blendMode: { enableBlend:1b, srcColorFactor:"SRC_ALPHA",
                         dstColorFactor:"ONE_MINUS_SRC_ALPHA",       // alpha blend (soft smoke)
                         srcAlphaFactor:"ONE", dstAlphaFactor:"ZERO", blendFunc:"ADD" },
            cull:1b, depthTest:1b, depthMask:0b } ] },
          layer: "Translucent",
          cull: { _enable: 1b,                    // cheap skip when off-screen
                  cullBox: { min:[-2d,-0.5d,-2d], max:[2d,3d,2d] } },
          orderInLayer: 0,
          vertexSortingMode: "DISTANCE",          // alpha blend needs back-to-front
          renderMode: "Billboard", shade: 0b, useBlockUV: 0b,
          modelPivot: [0f,0f,0f], velocityScale: 0f, lengthScale: 2f,
          useGPUInstance: 0b, facingMode: "DEFAULT" },
        velocityOverLifetime: { _enable: 1b,      // rise + swirl
          linear:  [ {type:"constant",data:{number:0}},
                     {type:"random_constant",data:{a:0.02f,b:0.06f}},  // upward drift
                     {type:"constant",data:{number:0}} ],
          orbitalMode: "AngularVelocity",
          orbital: [ {type:"constant",data:{number:0}},
                     {type:"constant",data:{number:0.8f}},             // rad/s around Y
                     {type:"constant",data:{number:0}} ],
          offset:  [ {type:"constant",data:{number:0}} x3 ],
          radial:       {type:"constant",data:{number:0f}},
          speedModifier:{type:"constant",data:{number:1}} },
        noise: { _enable: 1b,                     // organic wobble
          frequency: 0.8f, quality: "Noise2D", remap: {_enable:0b},
          position: [ {type:"constant",data:{number:0.05f}},
                      {type:"constant",data:{number:0.02f}},
                      {type:"constant",data:{number:0.05f}} ],
          rotation: {type:"constant",data:{number:0}},
          size:     {type:"constant",data:{number:0}} },
        colorOverLifetime: { _enable: 1b,         // fade in, hold, fade out (loop-safe)
          color: { type:"gradient", data: { gradientColor: {
            a:   [0f,0f,  0.2f,0.7f,  0.8f,0.55f,  1f,0f],
            rgb: [0f,0.55f,0.35f,0.9f,  1f,0.3f,0.15f,0.6f] } } } }   // violet -> deep purple
} } } ] } }
```

(`x3` above is shorthand meaning "repeat that compound three times in the list" — the real file
contains all three entries; see `/tmp/build_fx.py` for the exact generated bytes.)

### Spawning for test

`/photon fx eclipse:my_effect block <pos> [offset] [rotation] [scale] [delay] [force-death] [allow-multi] [check-state]`
or `... entity <selector> [offset] [auto rotate] [delay] ...`; removal via `/photon fx remove ...`.
In Eclipse, effects go through `veilfx/PhotonBridge` (see `INTEGRATION.md`).
