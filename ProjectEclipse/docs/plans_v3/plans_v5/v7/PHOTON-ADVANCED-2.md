# PHOTON-ADVANCED-2 — Runtime Control + Composition (second-generation deep dive)

Source of truth: full **Vineflower 1.10.1** decompile of `run/mods/photon-neoforge-1.21.1-2.1.5.jar`
(+ `ldlib2-neoforge-1.21.1-2.2.29-all.jar` for `Transform`, + `neoforge-21.1.238-sources.jar` for the
vanilla tick path). Every signature below is copied from decompiled bytecode, not memory.
Complements `docs/plans_v3/plans_v5/photon/API.md` (loader/executor basics) — this file covers what
that one does not: live mutation, movement, composition, pause, versioning.

**Verdicts up front**

| # | Question | Verdict |
|---|----------|---------|
| 1 | Live parameter injection | **YES — two channels** (config-object mutation re-read every tick; global `expr.Variable` for shape expressions) |
| 2 | KilaGraph / node graphs | **NOT in Photon 2.1.5** — zero references; graph-driven effects impossible in this version |
| 3 | Move/re-anchor a live executor | **YES** — `executor.getRuntime().getRoot().updatePos/updateRotation/updateScale(...)`; executor `setScale` etc. are **inert after `start()`** |
| 4 | Cross-`.fx` composition | Sub-emitters reference **other `.fx` files by ResourceLocation** (Birth/Death/Collision/FirstCollision/Tick events); no prefab nesting |
| 5 | Sound hooks in `.fx` | **NONE** — zero audio code in the entire jar; layer sounds in our own code |
| 6 | Performance instrumentation | Per-emitter `getParticleAmount()` only; no built-in profiler — budget system must sample it |
| 7 | Pause semantics | Menu pause **and** `/tick freeze` both freeze all Photon effects (verified in `Minecraft.tick()`) |
| 8 | Serialization stability | `version` fields are **written but never read** in the runtime path; unknown data degrades silently — our 68 assets are safe on 2.1.5, re-verify on any jar bump |

---

## 1. Live runtime parameter injection — YES, two channels

### The tick chain that makes it work

Every FX object is a vanilla `Particle` registered into `Minecraft.particleEngine`
(`IFXObject.emmit(...)` → `Minecraft.getInstance().particleEngine.add(particle)`), so each client
tick runs:

```
FXObject.tick()                              // final; decrements delay, then
 └ Emitter.updateTick()                      // final; computes velocity from transform delta, then
    └ ParticleEmitter.update()               // prewarm on first update, then
       └ ParticleEmitter.emitParticle()
          └ EmissionSetting.getEmissionCount(ParticleEmitter, RandomSource)   // ← re-evaluated EVERY TICK
             └ this.emissionRate.get(randomSource, t)                          // NumberFunction lookup
```

`EmissionSetting.getEmissionCount` calls `emissionRate.get(...)` and `distanceRate.get(...)` fresh
each tick — there is **no caching**. Whatever `NumberFunction` object sits in the field at that
moment is used. Same live-evaluation pattern holds for `startLifetime`/`startSpeed`/`startSize`/
`startColor` (read per particle at spawn in `TileParticle`) and `velocityOverLifetime.linear/orbital/
offset/radial/speedModifier` (read per particle per tick in
`VelocityOverLifetimeSetting.getVelocityAddition(TileParticle)`).

### Channel A — mutate the config object (per-FX, storm intensity)

`ParticleEmitter` exposes its config as a **public final field**:

```java
// com.lowdragmc.photon.client.gameobject.emitter.particle.ParticleEmitter
public final ParticleConfig config;
public int getParticleAmount();

// com.lowdragmc.photon.client.gameobject.emitter.data.EmissionSetting (field of ParticleConfig)
public void setEmissionRate(NumberFunction emissionRate);   // Lombok-generated, plain field write
public NumberFunction getEmissionRate();
public void setDistanceRate(NumberFunction distanceRate);
public void setBursts(List<EmissionSetting.Burst> bursts);

// com.lowdragmc.photon.client.gameobject.emitter.data.number.NumberFunction
static NumberFunction constant(Number constant);            // → new Constant(n)
Number get(float t, Supplier<Float> randomSupplier);
```

Storm-intensity driver (0..1 → emission rate), applied to a live runtime:

```java
FXRuntime rt = executor.getRuntime();                       // @Nullable until start()
for (IFXObject obj : rt.getObjects().values()) {
    if (obj instanceof ParticleEmitter pe) {
        pe.config.emission.setEmissionRate(NumberFunction.constant(baseRate * stormIntensity));
    }
}
// Or target a single named emitter authored in the editor:
IFXObject rain = rt.findObject("rain_core");                // FXRuntime.findObject(String) → first match
```

Other live-mutable knobs, all plain setters on `ParticleConfig` and its settings objects:
`setMaxParticles(int)`, `setDuration(int)`, `setLooping(boolean)`,
`setStartColor(NumberFunction)`, `setStartSize(NumberFunction3)`,
`velocityOverLifetime.setLinear(NumberFunction3)` (a wind *vector*, evaluated per particle per
tick — a legit wind-direction channel), `noise`, `forceOverLifetime`, etc.
`BeamConfig` additionally has `setWidth/setEmitRate/setRaycast` and — big one —
`getEnd()` returns the **live mutable `Vector3f`** used by `BeamParticle.getRealEnd(...)` every
frame: `beamCfg.getEnd().set(x,y,z)` retargets a running beam.

**⚠️ Shared-config semantics (critical for the storm design).**
`FXHelper.getFX(loc)` caches one `FX` per location forever, and every executor calls
`fx.createRuntime()` = `createRuntime(false)` = shallow copy. `ParticleEmitter.shallowCopy()` is
`new ParticleEmitter(this.config)` — **all live instances of the same cached `.fx` share ONE
`ParticleConfig`**, and the mutation persists for all *future* spawns until
`FXHelper.clearCache()` / `/photon_client clear_client_fx_cache`.
- For a *global* storm parameter this is free fan-out: one write drives every storm cell.
- For *per-instance* control, isolate first: `FXHelper.getFX(loc, false)` (fresh uncached `FX`) or
  build the runtime yourself from `fx.createRuntime(true)` (deep copy via NBT round-trip — costs a
  serialize+parse, don't do it per tick).

### Channel B — global expression variables (`expr` package)

Photon embeds Darius Bacon's `expr` library. The **`Function` shape**
(`photon:shape` registry name `"function"`) parses its six string fields (`x,y,z,speedX,speedY,speedZ`)
with `expr.Parser.parse(String)`:

```java
// expr.Variable — GLOBAL registry (static Hashtable keyed by name, process-wide)
public static synchronized Variable make(String name);
public void setValue(double value);
public double value();

// expr.Parser
public static Expr parse(String input) throws SyntaxException;  // new Parser(): allowedVariables == null
                                                                 // → ANY identifier auto-creates Variable.make(name)
```

`Function.prepareExpr(IParticleEmitter)` overwrites only `t`, `PI`, `randomA..randomE` before each
evaluation — **any other variable name keeps whatever Java last wrote**. So an `.fx` authored with
shape-function `speedX = "windX"`, `speedZ = "windZ"` is driven live by:

```java
expr.Variable.make("windX").setValue(wind.x);   // one write → every effect using the variable
expr.Variable.make("windZ").setValue(wind.z);
```

Scope limits: expressions exist **only** in the `Function` emission shape (spawn position + initial
velocity). Emission *rate*, color, size etc. do NOT go through `expr` — use Channel A for those.
There is **no other "bindings" system**: `grep -ri binding` over the whole decompile = zero hits.

## 2. KilaGraph — not in this Photon

- `photon-neoforge-1.21.1-2.1.5.jar` contains **zero** `kilagraph` references. `neoforge.mods.toml`
  dependencies: `neoforge [21.0.0-alpha,)`, `minecraft 1.21.1`, `ldlib2 [2.2.24,)` — nothing else.
- LDLib2 2.2.29 ships `com.lowdragmc.lowdraglib2.nodegraphtookit.*` (graph API + `GraphView` UI),
  but Photon 2.1.5 never imports it. The only "graphs" in Photon are `CurveGraph`/`RandomCurveGraph`
  (curve editors for `NumberFunction`, not node graphs).
- KilaGraph is the separately-shipped node-graph mod that **Photon 2.2.x** requires (our
  `bootstrap.json` already allowlists modid `kilagraph` as `"*"` for exactly that future; see
  `docs/plans_v3/plans_v5/photon/INTEGRATION.md` row "Photon 2.2.x installed").
- **Consequence**: effects cannot react to game values through node graphs on 2.1.5. Reactivity =
  Channel A/B above, driven from our Java tick. Do not architect the storm around graph features.

## 3. Executor transform control — move the runtime root, not the executor

### What `setOffset/setRotation/setScale` really do post-start

`FXEffectExecutor` fields (`protected Vector3f offset/scale; protected Quaternionf rotation`) are
consumed **once**, inside `start()`:

```java
// BlockEffectExecutor.start() — decompiled
this.runtime = this.fx.createRuntime();
IFXObject root = this.runtime.getRoot();
root.updatePos(new Vector3f(pos.getX(), pos.getY(), pos.getZ()).add(offset.x+0.5F, offset.y+0.5F, offset.z+0.5F));
root.updateRotation(this.rotation);
root.updateScale(this.scale);
this.runtime.emmit(this, this.delay);
```

After `start()`, calling `executor.setScale(...)`/`setOffset(...)`/`setRotation(...)` only writes
the field — **nothing re-reads it. They are inert.** (Exception: `EntityEffectExecutor` re-reads
`offset` and `rotation` each frame — see below — but still never re-reads `scale`.)

### The supported live-move path (Photon does it itself)

`EntityEffectExecutor.updateFXObjectFrame(IFXObject, float)` proves runtime movement is a
first-class operation — every frame it does:

```java
this.runtime.root.updatePos(new Vector3f(entityEye.x + offset.x, ...));
this.runtime.root.updateRotation(newRotation);   // FORWARD / LOOK / XROT auto-rotate modes
```

`IFXObject` default methods (root is an `EmptyFXObject`, registered name `"empty"`):

```java
default void updatePos(Vector3f newPos)        { this.transform().position(newPos); }
default void updateRotation(Quaternionf newRot){ this.transform().rotation(newRot); }
default void updateRotation(Vector3f eulerXYZ);
default void updateScale(Vector3f newScale)    { this.transform().scale(newScale); }
```

`com.lowdragmc.lowdraglib2.math.Transform` is a Unity-style hierarchy: world setters
(`position(Vector3f)`, `rotation(Quaternionf)`, `scale(Vector3f)`) convert to local via the parent
matrix and `onTransformChanged()` dirty-cascades to all children, so **moving the root moves the
whole effect tree**. Extras usable on the root transform: `lookAt(Vector3f target)`,
`translate(Vector3f dir, float dist)`, `rotate(Vector3f axis, float angle)`, `forward()/up()/right()`.

### Growth-front (traveling effect) recipe

```java
BlockEffectExecutor exec = new BlockEffectExecutor(fx, level, anchorPos);
exec.start();
FXRuntime rt = exec.getRuntime();                 // null if dedup refused (allowMulti=false + same fx at pos)
// per client tick or per frame:
rt.getRoot().updatePos(new Vector3f(frontX, frontY, frontZ));
```

Facts that decide the architecture:
- **Nothing fights you on `BlockEffectExecutor`**: its `updateFXObjectTick` only kill-checks; it
  never re-writes the transform. (On `EntityEffectExecutor` your manual `updatePos` is overwritten
  every frame — use `setOffset` there instead, which IS re-read per frame.)
- **Kill-switch stays at the anchor**: `updateFXObjectTick` destroys the runtime when the chunk at
  `pos` unloads or the *block* at `pos` changes (`lastState.getBlock() !=` current; exact-state if
  `setCheckState(true)`). A far-traveling front should anchor to something stable, or use a custom
  executor (below).
- **Emitter velocity is derived from movement**: `Emitter.updateTick()` sets
  `velocity = transform.position() - previousPosition`, which feeds `distanceRate` emission
  (particles-per-block-moved — *ideal* for a growth front) and `InheritVelocitySetting`.
- **`simulationSpace` decides what trails behind**: `TileParticle.getSpaceTransform()` returns the
  emitter's live `localToWorldMatrix()` for `Space.Local` (existing particles ride along) vs the
  particle's birth-time `initialTransform` for `Space.World` (particles stay put — the effect
  "paints" a trail as the root moves). World-space is the growth-front look.
- **Live rescale/rotate**: `rt.getRoot().updateScale(new Vector3f(s))` works mid-flight (Local-space
  particles rescale; World-space ones keep their birth scale — only new spawns change).
- **Cleanest long-term option**: subclass the executor — `IEffectExecutor` is tiny:
  ```java
  public interface IEffectExecutor {
      Level getLevel();
      default void updateFXObjectTick(IFXObject fxObject) {}
      default void updateFXObjectFrame(IFXObject fxObject, float partialTicks) {}
      default RandomSource getRandomSource() { return getLevel().random; }
  }
  ```
  Extend `FXEffectExecutor`, implement `start()` (copy the 6-line body above), and drive
  `runtime.root.updatePos(...)` from `updateFXObjectFrame` exactly like `EntityEffectExecutor` —
  own lifetime rules, no block anchor, smooth per-frame motion for free.

## 4. Multi-effect orchestration / composition

- **In-editor, in-file**: one `.fx` = `FXData(List<IFXObject> objects)` with a full transform
  hierarchy (`_parentId`/`_childrenId` UUID wiring, rebuilt by `FXRuntime.initRuntime()`; orphans
  get parented to the runtime root). Registered object types: `particle_emitter`, `trail_emitter`,
  `beam_emitter`, `aratrail_emitter`, `empty` (grouping node).
- **Cross-file**: `SubEmittersSetting.Emitter` holds `@Persisted ResourceLocation fxLocation` — a
  reference to **another whole `.fx`**. On `Event {Birth, Death, Collision, FirstCollision, Tick}`
  (gated by `emitProbability` NumberFunction + `tickInterval`), `spawnEmitter(TileParticle father)`
  does `FXHelper.getFX(fxLocation)` → `fx.createRuntime()` → `runtime.root.updatePos(father.getWorldPos())`
  → optional inherit flags (`inheritLifetime/Duration/Color/Size/Rotation`) →
  `runtime.emmit(father.getEmitter().getEffectExecutor())`. So chained/recursive `.fx` trees work
  today (cycles = infinite spawn cascade, nothing guards it — don't author cycles).
- **No prefab system**: editor resources are only `CurveResource/GradientResource/MaterialResource/
  MeshResource`; `grep -i prefab` = zero hits. You cannot *embed* one `.fx` inside another in the
  editor beyond the sub-emitter reference above.
- **Java-side orchestration**: `FXRuntime.emmit(IEffectExecutor effect, int delay)` re-arms every
  object; `FXRuntime.findObject(String name)` / `findObjects(String name)` target authored names;
  spawn N executors and drive their roots for constellations. (Parenting one runtime's root into
  another runtime's transform is mechanically possible via `Transform.parent(...)` but crosses
  `IScene` ownership — treat as unsupported.)

## 5. Sound hooks — none

Zero matches for `SoundEvent|playSound|sound|audio` across the entire decompiled jar (code and
`assets/photon/`). The `.fx` format has no audio field of any kind. Our pattern stays: fire sounds
from the same call-site that calls `PhotonBridge.spawn*` (or from a custom executor's
`updateFXObjectTick` for per-phase cues, e.g. keyed off `emitter.getT()`).

## 6. Performance instrumentation — build it, Photon won't

What exists:

```java
// IParticleEmitter (implemented by all 4 emitter types)
int getParticleAmount();     // ParticleEmitter: sum of per-renderpass queues + waitToAdded
int getAge();  float getT(); // progress through duration
// FXRuntime
public final Map<UUID, IFXObject> objects;  public boolean isAlive();
```

Per-effect cost sample for the budget system (`FxBudget` / `PhotonBridge` sweep is the natural
host — it already iterates live executors once per client tick):

```java
int cost = 0;
for (IFXObject o : runtime.getObjects().values())
    if (o instanceof IParticleEmitter pe) cost += pe.getParticleAmount();
```

Caps that already exist: `ParticleConfig.maxParticles` (default 2000, hard-clamped per emitter per
tick in `emitParticle()`; live-settable via `setMaxParticles(int)` — a budget system can *degrade*
a storm by lowering it); vanilla `ParticleEngine` holds at most 16384 particles per render type,
but each Photon **emitter** counts as ONE vanilla particle (internal particles live in the
emitter's own queues), so the vanilla cap is a non-issue. No timing hooks (`grep profiler` = only
vanilla `Minecraft.profiler` in our own code) — wall-clock cost must be measured by wrapping our
spawn sites or timing `particleEngine.tick()` externally. The editor shows per-emitter counts via
`IParticleEmitter.inspectSceneInformation` (label `photon.gui.editor.fx_info.particles`) — handy
for authoring-time budgeting of the 68 assets.

Emergency lever: `/photon_client clear_particles` wipes every Photon queue + both executor caches
(`ClientCommands`, via `ParticleEngineAccessor.getParticles().entrySet().removeIf(...)`).

## 7. Pause / resume semantics

Photon has **no pause API of its own** — it inherits vanilla gating because every FX object ticks
inside `ParticleEngine`. From `neoforge-21.1.238-sources.jar`, `Minecraft.tick()`:

```java
this.profiler.popPush("particles");
if (!this.pause && this.isLevelRunningNormally()) {   // isLevelRunningNormally() =
    this.particleEngine.tick();                        //   level.tickRateManager().runsNormally()
}
```

- **Menu pause** (singleplayer ESC, not LAN-opened): `this.pause` true → emitters, particles,
  trails all freeze in place. Render keeps happening but `this.timer.updatePauseState` freezes
  partial ticks, and `FXObject.render` computes `deltaTime = (lastTick + partialTicks) − lastTickTime`
  → ~0, so frame-driven visuals (trail interpolation, `EntityEffectExecutor` follow) also hold still.
  Nothing dies; on unpause everything resumes exactly where it was (ages/durations are tick-counted,
  not wall-clock).
- **`/tick freeze`**: the `TickRateManager` frozen flag is synced to clients, `runsNormally()` goes
  false → **Photon freezes under `/tick freeze` too** (same branch), and
  `timer.updateFrozenState(...)` freezes partials. This makes `/tick freeze` a genuinely useful
  "photograph the storm" debug tool.
- **Delay ticks still consume during... no**: `FXObject.tick()` itself is what decrements `delay`,
  and it isn't called while frozen — delayed effects also hold.
- Executor kill-checks (`updateFXObjectTick`) don't run while frozen either — no false deaths.

## 8. Serialization stability across Photon versions

Format recap (`FX.serializeNBT`): `{fxData: {fxObjects: [{type: "<registry name>", data: {...}} ...]}}`,
each object encoded by `PersistedParser.createCodec` from `@Persisted`/`@Configurable` fields.

Version fields that exist in our 68 assets:

```java
// ParticleEmitter / TrailEmitter / BeamEmitter / AraTrailEmitter — all:
public static int VERSION = 2;
serializeNBT(...) → tag.putInt("version", VERSION);      // ("_version" was the photon-1 key)
// FXProject (EDITOR project files, .fxproj-style — NOT runtime .fx):
public static int VERSION = 3;  meta.putInt("version_num", VERSION);
```

How versions are actually consumed:
- **Runtime `.fx` load (`FXHelper.loadFX`) never reads `version`.** No fixer runs. Grep confirms
  `getInt("version")` appears only in the photon-1→2 compat mappers.
- **DataFixerUpper exists but is editor-only**: `PhotonFXProjectDataFixer.INSTANCE.applyFixes(from,
  FXProject.VERSION, data)` (schemas: `PhotonSchemas`, fixes: `MaterialToRendererMaterialsFix`,
  `UVAnimationTilesFix`) runs inside `FXProject.deserializeNBT` — i.e. when a project is opened in
  the editor, not when the game loads an `.fx`.
- **Photon 1 → 2 is an offline converter**: `/photon_client convert` → `FXCompat.convertFX()` reads
  `ldlib2/assets/photon/fx_old/*` and rewrites (`_type`/`_version` → `type`/`version` wrapper). Our
  assets are already photon-2 format; irrelevant unless we import ancient files.
- **Failure modes are silent-degrade, not crash**: unknown object `type` → `deserializeWrapper`
  returns null → object dropped from the effect; unknown `NumberFunction` type → `ZERO`; unknown
  fields ignored; missing fields → Java-side defaults. `loadFX` catches ALL exceptions → `null` FX
  → our `PhotonBridge` spawn returns false. So a Photon upgrade can *visually gut* an asset with
  zero log noise.

**Forward-compat policy for the 68 assets**: (a) pin `2.1.5` until a bump is deliberate; (b) on any
bump, diff `VERSION` constants and the `fixer`/`compat` packages of the new jar first (2.2.x is
known to add a KilaGraph dependency and per-emitter fixers may start consuming `version`); (c) after
a bump, smoke-load all 68 via a dev command that asserts `FXHelper.getFX(loc) != null` **and**
`fx.getFxData().objects().size()` matches a recorded manifest count — that catches the silent
object-drop mode which `!= null` alone misses.

---

## Appendix — signature quick sheet (all decompiled, photon 2.1.5)

```java
// com.lowdragmc.photon.client.fx.FXRuntime
public FXRuntime(FXData fxData)
public final FXData fxData;  public final Map<UUID, IFXObject> objects;  public final IFXObject root;
public void emmit(IEffectExecutor effect);  public void emmit(IEffectExecutor effect, int delay)
public boolean isAlive();  public void destroy(boolean force)
@Nullable public IFXObject findObject(String name);  public List<IFXObject> findObjects(String name)
public IFXObject getRoot();  public Map<UUID, IFXObject> getObjects()

// com.lowdragmc.photon.client.fx.FX
public FXRuntime createRuntime()                 // shallow: emitters SHARE ParticleConfig
public FXRuntime createRuntime(boolean deepCopy) // true = NBT round-trip deep copy
public FXRuntime createInternalRuntime()         // no copy at all (editor use)

// com.lowdragmc.photon.client.gameobject.IFXObject (defaults)
void updatePos(Vector3f);  void updateRotation(Quaternionf);  void updateRotation(Vector3f eulerXYZ)
void updateScale(Vector3f);  void setDelay(int);  void setSelfVisible(boolean);  boolean isAlive()
void emmit(IEffectExecutor effect, @Nullable Vector3f pos, @Nullable Quaternionf rot, @Nullable Vector3f scale)

// com.lowdragmc.photon.client.fx.BlockEffectExecutor
public BlockEffectExecutor(FX fx, Level level, BlockPos pos)
public void start();  public void setCheckState(boolean)     // exact-blockstate kill check
public static Map<BlockPos, List<BlockEffectExecutor>> CACHE

// com.lowdragmc.photon.client.fx.EntityEffectExecutor
public EntityEffectExecutor(FX fx, Level level, Entity entity, AutoRotate autoRotate)
public void updateFXObjectFrame(IFXObject, float)            // re-applies eye pos + offset + autoRotate per frame
enum AutoRotate { NONE, FORWARD, LOOK, XROT }

// com.lowdragmc.photon.client.gameobject.emitter.Emitter
public void setPos(double x, double y, double z);  public Vector3f getVelocity()
public int getAge();  public void setAge(int);  public float getT();  public float getT(float partialTicks)

// com.lowdragmc.lowdraglib2.math.Transform (world-space setters convert to local, dirty-cascade to children)
public Vector3f position();      public void position(Vector3f)
public Quaternionf rotation();   public void rotation(Quaternionf)
public Vector3f scale();         public void scale(Vector3f)
public void lookAt(Vector3f target);  public void translate(Vector3f dir, float dist)
public void parent(@Nullable Transform parent, boolean keepWorldTransform)

// expr (global variable bindings for shape "function" expressions)
expr.Variable.make(String name).setValue(double)   // static global; survives prepareExpr except t/PI/randomA-E
expr.Parser.parse(String)                          // unknown identifiers auto-create Variables
```
