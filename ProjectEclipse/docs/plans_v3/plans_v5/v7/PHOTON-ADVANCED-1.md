# PHOTON-ADVANCED-1 — Unused Advanced Capabilities (2nd-gen deep dive)

**Provenance**: Vineflower decompile of `run/mods/photon-neoforge-1.21.1-2.1.5.jar`
(pre-existing full decompile at `/tmp/photon_dec2`) plus fresh Vineflower decompiles of
`run/mods/ldlib2-neoforge-1.21.1-2.2.29-all.jar` packages `client.shader`, `client.renderer`,
`client.model`, `editor` (at `/tmp/ldlib2_full/src_*`). Every class/field/NBT key below was read
from bytecode, 2026-07 (PHOTON-DEEP-1). Companion docs: `../photon/FX_FORMAT.md`, `../photon/API.md`.

Scope: capabilities we have **NOT** used in the 68 shipped `.fx`: (1) custom shader materials,
(2) lights module, (3) mesh/model particles, (4) UV animation, (5) LOD, (6) sub-emitter events,
(7) `.fxproj` generation.

---

## 1. Custom shader materials (`custom_shader`) — YES, per-emitter GLSL, huge for storm clouds

Class: `com.lowdragmc.photon.client.gameobject.emitter.data.material.CustomShaderMaterial`
(registry `photon:material`, name `custom_shader`), extends `ShaderInstanceMaterial`, backed by
LDLib2 `com.lowdragmc.lowdraglib2.client.shader.LDShaderHolder` / `LDShaderInstance` /
`LDProgramDefineManager`.

### 1.1 What it is

A renderer material whose shader is a **vanilla-format core shader JSON we ship ourselves**:
`shaderLocation: "eclipse:storm_cloud"` resolves to
`assets/eclipse/shaders/core/storm_cloud.json` (path built in `LDShaderInstance.create`:
`"shaders/core/" + location.getPath() + ".json"`). The JSON references `.vsh`/`.fsh` (and
optionally geometry, see 1.6) programs exactly like vanilla; `#moj_import` works, including
cross-namespace imports such as `#moj_import <photon:particle.glsl>`. Vertex format is fixed to
`DefaultVertexFormat.BLOCK` (`LDShaderHolder.create(shaderLocation, DefaultVertexFormat.BLOCK)`
in `CustomShaderMaterial.loadShaderHolder`). Compilation is lazy at first render
(`getShader` → `recompile()`); **any compile error falls back to `photon:hdr_particle`** and the
error string shows in the editor material preview (`isCompiledError()`), so a broken shader never
crashes — it renders with the default HDR shader.

Works everywhere a `MaterialSetting` exists: particle emitters, **trail**, **ara_trail**, and
**beam** emitters (all share `RendererSetting.materials`). Multi-material = multi-pass with
independent blend state per pass.

### 1.2 Auto-wired samplers (name-triggered — just declare them in the JSON)

`CustomShaderMaterial.attachDynamicSamplers` checks the JSON's `samplers` list by **name**:

| sampler name | bound to | use |
|---|---|---|
| `SamplerBlockAtlas` | block atlas (`InventoryMenu.BLOCK_ATLAS`) | block-texture lookups |
| `SamplerCurve` | this material's `CurveTexture` LUT (128×128, R channel) | authored curves in GLSL |
| `SamplerGradient` | this material's `GradientTexture` LUT (128×128, RGBA) | authored gradients in GLSL |
| `SamplerSceneColor` | `RenderPassPipeline.getCurrent().getSceneSampler().getColorTextureId()` | **scene color behind the particle → refraction/distortion/heat-haze** |
| `SamplerSceneDepth` | scene depth texture id | **soft particles / depth fade — the storm-cloud killer feature** |
| `Sampler2` | vanilla lightmap (bind yourself as in `photon:particle.vsh`) | world lighting |
| any other name **not** starting with `Sampler` | user-assignable in the editor; persisted as a texture ResourceLocation | extra noise/LUT textures |

The scene sampler is a copy of the Photon draw target (which itself copied the main framebuffer
color+depth, incl. Iris FBOs — `RenderPassPipeline.prepareTarget`); it is re-snapshotted between
render passes (`markSceneSamplerDirty` per pass in `RenderPassPipeline.build`), so later-ordered
emitters can refract earlier ones.

### 1.3 Auto-wired uniforms (name-triggered, `U_` prefix = "builtin")

`CustomShaderMaterial.attachDynamicUniforms` (set every frame if declared):

| uniform | type | value |
|---|---|---|
| `U_CameraPosition` | vec3 | camera world position |
| `U_InverseProjectionMatrix` | mat4 | inverted `RenderSystem.getProjectionMatrix()` |
| `U_InverseViewMatrix` | mat4 | inverted model-view — with the two above + `SamplerSceneDepth` you can reconstruct world position per pixel |
| `U_ViewPort` | vec4 | (x, y, w, h) of the GL viewport |

Plus everything vanilla `ShaderInstance` auto-fills when declared: `ModelViewMat`, `ProjMat`,
`ColorModulator`, `FogStart/FogEnd/FogColor/FogShape`, `GameTime` (⇽ animate clouds!),
`ScreenSize`, `Light0_Direction/Light1_Direction`, etc. (`LDShaderHolder.isBuiltinUniform` list).

### 1.4 Custom uniforms = free editor knobs, persisted in NBT

**Any uniform whose name does NOT start with `U_` and is not a vanilla builtin becomes an
editor-editable, NBT-persisted parameter** (`LDShaderHolder.buildConfigurator` +
`serializeNBT`). Editor widget by name heuristics: contains `color`/`rgb`(`rgba`) → color picker;
vec4 containing `hdr`/`emission` → **HDR color picker (feeds bloom)**; otherwise
number/vec2/vec3/vec4 fields. Values are saved per material instance:

```
material: { type: "custom_shader", data: {
  shaderLocation: "eclipse:storm_cloud",                  // String RL, @Persisted
  curveTexture:   [ <Curve compound>, ... ],              // ListTag; row i of SamplerCurve
  gradientTexture:[ {a:[t,alpha…], rgb:[t,r,g,b…]}, … ],  // ListTag; row i of SamplerGradient
  _additional: {                                          // PersistedParser "_additional" hook
    shaderData: {                                         // LDShaderHolder.serializeNBT
      uniforms: { MyFloat:[0.5f], MyColor:[1f,0.2f,0.1f,1f], MyInt:[I;3], … },
                                                          // float uniform → ListTag<Float>,
                                                          // int uniform → IntArrayTag
      samplers: { MyNoise: {type:"texture", resource:"eclipse:textures/misc/noise.png"} }
    } } } }
```

(`Curve` compound = `{min, max, curves: ECBCurves, xAxis, yAxis, lockControlPoint, lower, upper}`
— same as the NumberFunction curve, class
`com.lowdragmc.photon.client.gameobject.emitter.data.number.curve.Curve`.)

### 1.5 Curve/Gradient LUTs — authored animation curves readable in GLSL

`CurveTexture`/`GradientTexture` (128×128, `MAX_SAMPLER = MAX_SAMPLING = 128` per material) bake
each list entry into one texture **row**; re-uploaded lazily when dirty. Curve value goes to the
**R channel** (0–255); gradients are full RGBA. Photon ships ready-made helpers in
`assets/photon/shaders/include/particle_utils.glsl`:

```glsl
#moj_import <photon:particle_utils.glsl>
float v   = getCurveValue(SamplerCurve, 0, t);       // row 0, x∈[0,1]
vec4 tint = getGradientValue(SamplerGradient, 1, t); // row 1
```

Combine with `addition_gpu_data.t` (see 1.7) → **per-particle lifetime-driven shading entirely on
the GPU** (e.g. cloud density ramp, lightning-flash gradient).

### 1.6 Defines, instancing variants, geometry shaders

- Every custom shader gets a unique define `LD_SHADER_%d` (`LDShaderHolder.SHADER_UID_DEFINE`);
  extra defines produce cached recompiled variants (`shadersWithDefines`), with non-builtin
  uniform values copied over from the base instance.
- GPU-instanced rendering requests define **`PARTICLE_INSTANCE`** (billboard) or
  **`PARTICLE_MODEL_INSTANCE`** (model) — `MaterialContext.PARTICLE_INSTANCE` /
  `PARTICLE_MODEL_INSTANCE`, chosen in `ParticleConfig` when `useGPUInstance` is on. Write one
  vertex shader that works in both immediate and instanced mode by importing
  `photon:particle.glsl` and calling `getParticleData()` (exact pattern of
  `assets/photon/shaders/core/particle.vsh`). Instanced attribute layouts (from
  `particle.glsl` + `ParticleInstanceRenderer.createOrResizeInstanceData`):
  - `PARTICLE_INSTANCE`: loc0 `aPos` (unit quad ±1); per-instance loc1 `iPos` vec3, loc2 `iSize`
    vec2, loc3 `iScale` vec3, loc4 `iRot` vec4 quat, loc5 `iColor` vec4, loc6 `iUV` vec4,
    loc7 `iLight` int; **custom channels start at loc 8**.
  - `PARTICLE_MODEL_INSTANCE`: loc0 `aPos`, loc1 `aUV`, loc2 `aNormal`, loc3 `aBrightness`
    (static mesh); per-instance loc4 `iPos`, loc5 `iScale`, loc6 `iRot`, loc7 `iColor`,
    loc8 `iLight`; **custom channels start at loc 9**.
- **Geometry shaders are supported**: `LDShaderInstance.onCreateShader` reads an optional
  `"geometry"` key in the shader JSON (`LDLibShaders.GEOMETRY_TYPE`, suffix `.gsh`). Unused
  anywhere in Photon's own shaders — free real estate.

### 1.7 `additionalGPUDataSetting` — per-particle CPU→GPU channels (instance mode only)

Module key `additionalGPUDataSetting` on the particle config (`{_enable: 1b, additionalData:
[String…]}`), class `ParticleAdditionalGPUDataSetting`. Enabled channel names, sizes (floats) and
sources (declare matching `layout(location = 8/9+…) in float/vec3 …;` yourself, in list order —
providers upload in the fixed order of `SUPPORTED_DATA_PROVIDERS`):

| name | size | value |
|---|---|---|
| `addition_gpu_data.random` | 1 | memoized per-particle random (`getMemRandom("instance_random")`) |
| `addition_gpu_data.t` | 1 | particle lifetime progress 0–1 |
| `addition_gpu_data.age` | 1 | int bits in float (`intBitsToFloat` — use `floatBitsToInt` in GLSL) |
| `addition_gpu_data.lifetime` | 1 | int bits |
| `addition_gpu_data.position` | 3 | local pos |
| `addition_gpu_data.velocity` | 3 | real velocity |
| `addition_gpu_data.isCollided` | 1 | int bits 0/1 |
| `addition_gpu_data.emitter_t` | 1 | emitter cycle progress |
| `addition_gpu_data.emitter_age` | 1 | int bits |
| `addition_gpu_data.emitter_position` | 3 | emitter transform pos |
| `addition_gpu_data.emitter_velocity` | 3 | emitter velocity |

### 1.8 Baseline shaders to copy from (all in `assets/photon/shaders/core/`)

`particle.vsh` (shared vertex, instancing-aware), `circle.fsh` (procedural soft dot — uniforms
`HDR` vec4, `DiscardThreshold`, `Radius`), `hdr_particle.fsh` (`HDRMode==0` add / `==1` multiply
emission), `sprite_hdr_particle` (`U_SpriteUV` atlas remap), `pixel_hdr_particle` (`Bits`
pixel-art AA). `TextureMaterial.setupUniform` shows the uniform-setting pattern
(`DiscardThreshold`, `HDR`, `HDRMode`).

**Storm-cloud recipe**: `custom_shader` material on a GPU-instanced billboard emitter;
fsh samples `SamplerSceneDepth` for depth-fade (soft intersection with terrain), a shipped noise
texture (custom sampler) scrolled by `GameTime` for wispy density, `getGradientValue(…, t)` for
white→dark-grey→green-tinge ramp, editor-tweakable `CloudDensity`/`HDRBoost` uniforms; bloom via
HDR output on lightning flashes.

---

## 2. Lights module — forced lightmap, NOT dynamic world lights

Class: `LightOverLifetimeSetting`; NBT key **`lights`** = `{_enable: 1b, skyLight: NF,
blockLight: NF}` (both int NF 0–15, Constant/RandomConstant/Curve/RandomCurve, input axis =
particle lifetime `t`, per-particle random memoized as `"sky-light"`/`"block-light"`).

- `getLight` packs `sky << 20 | block << 4` — the vanilla **lightmap coordinate** written into
  each vertex (`TileParticle.getRealLight`). It overrides how *the particle itself is lit*, it
  does **not** emit light into the world. There is **no dynamic-light module in the jar** (no
  Veil `DynamicLightModule` equivalent; verified by class-list scan). For real light casting keep
  Quasar/Veil.
- Available on ALL emitter types (particle/trail/ara-trail/beam configs each embed `lights`;
  it defaults to `enable = true` in the constructor — BUT serialized files omit it unless the
  editor wrote it, and absent compound ⇒ Java default which is enabled-with-15/15… note:
  `ToggleGroup` default `enable` is false for other modules; `LightOverLifetimeSetting` sets
  `this.enable = true` in its constructor, so **omitting `lights` entirely = fullbright 15/15**.
  To get world-lit particles you must ship `lights: {_enable: 0b}` explicitly.)
- **Perf trait (inverted from intuition)**: with `lights` ENABLED there are no world queries —
  light is computed from the curves. With it DISABLED, `TileParticle.updateLight` queries block
  light at the particle's `BlockPos` **every tick per particle**
  (`emitter.getLightColor(blockPos)`); this is also the path that breaks under
  `parallelUpdate` (level access). For 10⁴-particle storm systems: keep `lights` enabled with a
  curve (e.g. flash to 15 then decay) — it is cheaper AND animatable.
- Curve trick: `blockLight` RandomCurve between rows ⇒ per-particle flicker (embers, lightning
  strobes) with zero CPU cost beyond curve eval.

---

## 3. Mesh/model particles — bake ANY model in, ours included

Two independent features share the model system (LDLib2 `ModelFactory` →
vanilla `ModelBakery.getModel`):

### 3.1 Emission from model geometry — shape `mesh`

Classes `shape.Mesh` + `shape.MeshData`. NBT (inside `shape.shape`):

```
shape: { type: "mesh", data: {
  type: "Vertex" | "Edge" | "Triangle",     // Mesh.Type, default Triangle
  meshData: { modelLocation: "eclipse:block/storm_totem" }   // default "block/stone"
} }
```

- `modelLocation` is an **UnbakedModel path**: `assets/<ns>/models/<path>.json` — any vanilla
  block/item model JSON, including ones with parents, and **any NeoForge model-loader JSON**
  (e.g. `{"loader":"neoforge:obj","model":"eclipse:models/misc/debris.obj"}` wrapper JSON works,
  because baking goes through the normal bakery). **`.bbmodel` is NOT loadable directly** —
  export Blockbench → Java block/item JSON (or OBJ + wrapper). Bad location silently falls back
  to `block/stone` (`MeshData.loadFromModel`).
- Baked quads are decomposed to vertices (positions recentred −0.5 so the model is centered on
  the emitter), edges (per-quad 5 incl. one diagonal) and triangles (2/quad);
  `Vertex` picks uniformly from vertices, `Edge` length-weighted + lerp along the edge,
  `Triangle` area-weighted + uniform barycentric point (`getRandomVertex/Edge/Triangle`).
  Initial velocity is **zeroed** (`setInternalVelocity(0,0,0)`) — use `startSpeed`=0 +
  `velocityOverLifetime`/forces for motion. Shape `position/rotation/scale` NF3 still apply.
- Use: emit cloud clumps across a big authored "cloud shell" model; spawn debris off a tornado
  funnel model's surface.

### 3.2 Rendering particles AS models — `renderMode: "Model"`

Class `ParticleRendererSetting` (embedded as `renderer`). Exact NBT keys:

```
renderer: {
  renderMode: "Model",
  model: { modelLocation: "eclipse:block/debris_chunk" },  // LDLib2 IModelRenderer ("json_model");
                                                           // ONLY written when renderMode==Model
                                                           // (ParticleRendererSetting.serializeNBT)
  shade: 1b,          // baked directional brightness: UP/DOWN .9, N/S .8, W/E .6, unsided 1.0
  useBlockUV: 1b,     // true: keep atlas UVs (pair with block_atlas material);
                      // false: UVs remapped 0-1 per sprite → ANY material/custom shader wraps the model!
  modelPivot: [0f,0f,0f],  // added to every vertex BEFORE rotate/scale (rotation pivot shift)
  materials: …, layer: …, etc.
}
```

- **The render model is a separate field from the mesh shape** (correction to older notes):
  `renderer.model` is its own `IModelRenderer`; the emission `mesh` shape and the rendered model
  can differ. Default model is `block/dirt`.
- Immediate path (`TileParticle.renderInternal`): matrix =
  `translate(pos) · rotateXYZ(realRotation) · scale(realSize · spaceScale) · translate(-0.5)` —
  i.e. **full per-particle 3-axis rotation and non-uniform per-axis scale, all curve-drivable**:
  - `startRotation` NF3 (deg→rad at spawn), `rotationOverLifetime` (`roll/pitch/yaw` NF deg/tick,
    ADDITIVE integration), `rotationBySpeed`, `noise.rotation` — all sum into `realRotation`
    (`TileParticle.updateRotation`). For tumbling debris: `rotationOverLifetime` with
    RandomConstant ±15°/tick on all three axes.
  - `startSize` NF3 × `sizeOverLifetime` NF3 × `sizeBySpeed` NF3 ⇒ per-axis curves (stretch a
    cloud clump horizontally over life etc.).
- GPU-instanced path (`ParticleInstanceRenderer.createStaticData`): model baked ONCE into a
  static VBO (9 floats/vertex: pos3 uv2 normal3 brightness1, EBO 6 idx/quad), per-instance
  15 floats (pos3 scale3 rotQuat4 color4 light1) + custom channels; drawn with
  `glDrawElementsInstanced` — **thousands of debris chunks ≈ one draw call per material pass**.
  Caveat: model/shade/useBlockUV/pivot changes need `particleRenderType.clearInstance()` (editor
  does it via setters) — in shipped files it's baked at load, fine.
- Lighting: model particles still use the particle `light` (lightmap) + baked `shade` factors —
  no smooth/AO. `block_atlas` material (`BlockTextureSheetMaterial`) + `useBlockUV: 1b` renders
  with real block textures; or `useBlockUV: 0b` + `custom_shader` to shade OUR debris/clump
  models with the storm shader.

---

## 4. UV animation (`uvAnimation`) — flipbook atlases, all emitter types

Class `UVAnimationSetting`; NBT: `uvAnimation: {_enable: 1b, tiles: [cols, rows] (List<Int>[2],
Vector2i), animation: "WholeSheet"|"SingleRow", frameOverTime: NF, startFrame: NF
(Constant/RandomConstant only), cycle: Float=1.0}`.

Exact math (`getUVs`, t = lifetime progress incl. partialTicks):
`frame = startFrame(t) + cycle * frameOverTime(t)`;
`WholeSheet`: `X = frame % cols`, `Y = frame / cols` (row-major over the whole grid);
`SingleRow`: `X = frame % cols`, `Y = fixed random row per particle` (memoized
`getMemRandom("randomRow")` — great for texture variation: N cloud puffs in N rows, each particle
locks one row). UV rect = `[X*cellU, Y*cellV, +cellU, +cellV]`.

- **`frameOverTime` is a NumberFunction, not a frame rate** — for a linear flipbook use a Curve
  0→1 over lifetime with `cycle = totalFrames` (or a Curve with `upper=frames`). Constant 0
  (default) = static frame. Non-linear curves = ease-in/hold/ease-out playback; RandomCurve =
  desynced playback per particle. There is NO frame interpolation/blending — snap only.
- Applied CPU-side into vertex UVs (`TileParticle.getRealUVs` → quad corners; instanced path
  packs it as `iUV` vec4 `(u0, v1, u1, v0)`). Works with:
  - `texture` material — the PNG itself is the sheet;
  - `sprite` material — 0–1 UV is remapped into the atlas sprite rect by `U_SpriteUV` uniform
    (`SpriteMaterial.setupUniform`), so a sheet packed as one atlas sprite animates too — note
    `spriteLocation` here is a **vanilla particle sprite-set id** from `particles/*.json`
    (`Minecraft.particleEngine.spriteSets`), and it always takes sprite index `get(0,1)`;
  - `custom_shader` — you receive the animated UV in `texCoord0`; free to add your own blending.
- Also present in **beam** (`BeamConfig.uvAnimation` — animate the beam texture!) and **trail**
  configs. Input axis for beams/trails = emitter/segment t.
- Storm use: 8×8 smoke flipbook billboard clouds (WholeSheet, curve-eased), 4-row puff variation
  (SingleRow), lightning-arc beam with animated UV.

## 5. LOD system — DOES NOT EXIST (negative finding, verified)

Searched the full decompile and jar class list for `lod`/`LOD`/`levelOfDetail`/distance
thresholds: **Photon 2.1.5 has no LOD system** — no distance-based emitter switching, no
particle-count scaling by distance, no camera-distance module. (The FX_FORMAT LOD mention was a
misread; nothing in bytecode.) What exists instead, cheapest first:

1. `renderer.cull: {_enable: 1b, cullBox: {min:[x,y,z], max:[…]}}` — AABB frustum-cull per
   emitter (`RendererSetting`); particles still simulate, only rendering skips.
2. Vanilla `ParticleEngine` limits — FXObjects live in the vanilla engine; camera-frustum and
   particle-limit behavior is vanilla's.
3. `maxParticles`, `parallelUpdate`/`parallelRendering`, `useGPUInstance` for budget.
4. **Roll our own LOD at spawn time** (recommended): our client bridge picks between
   `eclipse:storm_near.fx` / `eclipse:storm_far.fx` based on
   `camera.distanceToSqr(pos)` before calling the executor — Photon can't do it, our spawner can.
   Also viable: `FXRuntime.findObject(name)` + per-emitter kill for staged degradation.

---

## 6. Sub-emitter events — all five, exact trigger semantics

Module `subEmitters` (class `SubEmittersSetting`), entries
`{uid: Int(count), payload: [{fxLocation: String RL, event: String, emitProbability: NF,
tickInterval: Int=1, inheritColor/inheritSize/inheritRotation/inheritLifetime/inheritDuration:
Byte}]}` — enum `SubEmittersSetting.Event`, fire sites in `TileParticle`:

| event | fires (from `TileParticle.updateTick` / `onCollision`) |
|---|---|
| `Birth` | once, on the particle's **first update tick** (`age == 0`), i.e. 1 tick after spawn, after `delay` |
| `Death` | on natural expiry (`age >= lifetime`) **and** on `physics.removedWhenCollided` removal — NOT on emitter force-kill |
| `Tick` | **every update tick** of the particle (gate with `tickInterval` + probability!) |
| `Collision` | **every** collision event (per `PhysicsSetting` world collision) |
| `FirstCollision` | once, on the first collision (flag `isFirstCollision`); fires **in addition to** `Collision` |

Spawn mechanics (`SubEmittersSetting.Emitter.spawnEmitter`):
- Gate: `fxLocation != null && age % tickInterval == 0 && random() < emitProbability(t)`.
  **`emitProbability` defaults to constant 0 — nothing spawns unless you set it** (use 1 for
  always). It's a full NF: a Curve over father-lifetime = e.g. only spawn micro-lightning in the
  last 20% of a cloud particle's life. `tickInterval` applies to ALL events (an `age%interval`
  check), not just Tick.
- Spawns a **whole child `.fx` file** (`FXHelper.getFX` → `fx.createRuntime()` → runtime root
  positioned at the father particle's **world pos**, `runtime.emmit(father's executor)`).
  Recursion is legal (child may itself have subEmitters — no depth guard: don't self-reference).
- Inheritance flags apply **once at spawn** to every `IParticleEmitter` in the child runtime:
  `inheritLifetime` → child emitter `setAge(father.age)`; `inheritDuration` →
  `setLifetime(father.lifetime)`; `inheritColor` → `setRGBAColor(father.getRealColor(0))`
  (multiplies child `startColor`); `inheritSize` → child transform scale = father real size;
  `inheritRotation` → child transform rotation from father real rotation. Velocity is NOT
  inheritable (child starts at rest relative to world).
- Storm uses: raindrop particle + `FirstCollision` → splash `.fx`; debris chunk + `Collision` →
  dust puff; cloud clump `Death` → dissipation wisp; `Tick` @ interval 20, probability-curve →
  intermittent internal lightning flashes.

---

## 7. `.fxproj` — YES, we can generate it (trivial wrapper, keeps effects editor-editable)

Classes: `com.lowdragmc.photon.gui.editor.FXProject` (LDLib2 `IProject`/`ProjectType`).

### 7.1 Exact file format

```
<root> Compound — written with NbtIo.write => *** UNCOMPRESSED NBT *** (not gzip!)
├─ meta: {                       // IProject.getMetadata + FXProject override
│    version: "3.0",             // String, "%d.0" of FXProject.VERSION
│    suffix: ".fxproj",
│    name: "fx_project",
│    version_num: 3              // Int — the ONLY field the loader reads (fixer chain input)
│  }
└─ data: {
     fx: { fxData: { fxObjects: [ … ] } }   // EXACTLY the same compound as the exported .fx
   }
```

- **Difference vs `.fx`**: the `.fx` export is `NbtIo.writeCompressed(fx.serializeNBT(...))`
  (gzip, `FXProject.onLoad` export menu); the `.fxproj` save is plain `NbtIo.write`
  (`ProjectType.saveProjectToFile`). Same inner `fxData`, byte-for-byte.
- **Resources are NOT stored in the project file** (correction to FX_FORMAT §1.1): 2.x moved the
  editor resource panel (materials/colors/curves/gradients/meshes) to a global store —
  `<gamedir>/ldlib2/assets/ldlib2/resources/<name>.meta.nbt` per `ResourceInstance`, with
  file-based custom providers. `FXProject.serializeProject` writes only `fx`. So a generated
  `.fxproj` is fully self-contained and standalone-editable.
- Load path: `deserializeNBT` reads `meta.version_num` (missing ⇒ 1 — **always write 3** or the
  v1→v2→v3 fixers will mangle modern data), runs `PhotonFXProjectDataFixer.applyFixes(version,
  3, data)`, then reads `data.fx`.

### 7.2 Generator plan (extend `tools/photon/fxlib.py`)

Our generator already builds the `{fxData: …}` compound. To also emit `.fxproj`:
write `{meta: {version:"3.0", suffix:".fxproj", name:"fx_project", version_num:3},
data: {fx: <the same compound>}}` **uncompressed** next to each gzip `.fx`. ~10 lines. Then any
effect we generate can be opened in `/photon_editor` (singleplayer) via File → Open (file dialog
roots at `<gamedir>/ldlib2/assets`; `ProjectType.loadProjectFromFile` accepts any path), tweaked
visually, and re-exported — closing the "binary blob is unauthorable" gap. Recommendation: commit
generated `.fxproj` beside sources; artists round-trip; re-export overwrites `.fx`.
(Editor open = `/photon_editor`, singleplayer-only guard in `ClientCommands`.)

---

## 8. Cross-cutting notes

- All new module NBT lands inside the existing `config` compound of `particle_emitter` (or
  trail/beam configs where noted) — no format version bump needed (`version: 2` unchanged).
- Custom-shader materials fully coexist with `blendMode`/`cull`/`depthTest`/`depthMask` per
  `MaterialSetting`, bloom (write >1.0 RGB or use an `hdr`-named uniform), and Iris compat
  (scene copy handles shader-pack FBOs — `RenderPassPipeline.prepareTarget` Iris branch).
- Shipping checklist for a custom shader: `assets/eclipse/shaders/core/<name>.json` + `.vsh` +
  `.fsh` (+ optional includes under `assets/eclipse/shaders/include/`), reference as
  `shaderLocation: "eclipse:<name>"`. Test with `/photon_editor` material preview (compile errors
  render as red text in the preview tile).
- Perf order for storm scene: GPU-instanced billboards + custom shader (cheapest per particle) →
  instanced model debris → CPU billboards → CPU model particles → physics-colliding particles
  (world queries) — and remember `lights` module ENABLED is cheaper than disabled (§2).
