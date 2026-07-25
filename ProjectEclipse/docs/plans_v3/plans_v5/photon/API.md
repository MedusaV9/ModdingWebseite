# Photon Runtime API — Definitive Guide

Verified by `javap` disassembly of the exact jars we ship in `run/mods-client/`:
`photon-neoforge-1.21.1-2.1.5.jar` (modid `photon`) and
`ldlib2-neoforge-1.21.1-2.2.29.jar` (modid `ldlib2`, photon requires `[2.2.24,)`).
All class/method names below are copied verbatim from bytecode — not from docs or memory.

There is **no `EffectManager`** class. The runtime API is three concepts:
`FXHelper` (loader/cache) → `FX` (deserialized asset) → `FXEffectExecutor` subclasses
(`BlockEffectExecutor` / `EntityEffectExecutor`) which internally create a `FXRuntime`.

---

## 1. Core classes (exact signatures)

### `com.lowdragmc.photon.client.fx.FXHelper` — loader + cache
```
public static FX getFX(ResourceLocation)              // = getFX(loc, true)
public static FX getFX(ResourceLocation, boolean useCache)
public static int clearCache()                        // returns #entries cleared
public static final String FX_PATH = "fx/"
```
- `loadFX` (private) resolves `ResourceLocation.fromNamespaceAndPath(ns, "fx/" + path + ".fx")`
  and opens it through **`Minecraft.getInstance().getResourceManager().open(...)`**, then
  `NbtIo.readCompressed(stream, NbtAccounter.unlimitedHeap())` → `new FX()` →
  `fx.deserializeNBT(Platform.getFrozenRegistry(), tag)`.
- **Any `Exception` → returns `null`** (missing asset = `null`, never throws out).
- Successful loads are cached in a static `HashMap` forever (a `null` result is NOT cached,
  so a later resource-pack reload that adds the file will succeed). In-game command
  `/photon_client clear_client_fx_cache` calls `clearCache()`.

### `com.lowdragmc.photon.client.fx.FX` — the deserialized `.fx` asset
```
public FX()                                            // empty; fill via deserializeNBT
public FXRuntime createRuntime()                       // = createRuntime(false)
public FXRuntime createRuntime(boolean deepCopyData)   // new FXRuntime(fxData.copy(b))
public ResourceLocation getFxLocation() / setFxLocation(ResourceLocation)
public FXData getFxData()
public static final String SUFFIX = ".fx"
// implements INBTSerializable<CompoundTag> (serializeNBT/deserializeNBT)
```
`FXData` is a record wrapping `List<IFXObject> objects` (the editor-authored emitter tree).

### `com.lowdragmc.photon.client.fx.FXEffectExecutor` (abstract) — shared knobs
```
protected FXEffectExecutor(FX, Level)
public void setOffset(Vector3f)       // org.joml
public void setRotation(Quaternionf)  // org.joml
public void setScale(Vector3f)
public void setDelay(int)             // ticks before emission
public void setForcedDeath(boolean)   // passed to FXRuntime.destroy(force) on auto-kill
public void setAllowMulti(boolean)    // default FALSE — see dedup rule below
public FX getFx();  public Level getLevel();  public FXRuntime getRuntime()
```
The `IFXEffectExecutor` interface adds convenience defaults (degrees in, XYZ euler):
```
default void setOffset(double x, double y, double z)
default void setRotation(double xDeg, double yDeg, double zDeg)  // Math.toRadians → Quaternionf.rotationXYZ
default void setScale(double x, double y, double z)
```

### `com.lowdragmc.photon.client.fx.BlockEffectExecutor` — anchor at a block
```
public BlockEffectExecutor(FX, Level, BlockPos)     // ← exactly what PhotonBridge reflects
public void start()
public void setCheckState(boolean)                  // kill effect if the Block at pos changes
public static Map<BlockPos, List<BlockEffectExecutor>> CACHE   // live effects registry
public final BlockPos pos
```
`start()` semantics (from bytecode):
1. Get `CACHE.computeIfAbsent(pos)` list; prune entries whose runtime is dead.
2. **Dedup**: if `allowMulti == false` and an ALIVE executor with the same `FX`
   (or same `fx.getFxLocation()`) already exists at this `BlockPos` → `return` silently.
3. `runtime = fx.createRuntime()`; `root.updatePos(new Vector3f(pos) + offset + (0.5, 0.5, 0.5))`
   (i.e. the effect plays at the **block center + offset**), then `updateRotation(rotation)`,
   `updateScale(scale)`, `runtime.emmit(this, delay)`, remember `lastState`, add to CACHE.
- With `setCheckState(true)`, `updateFXObjectTick` kills the runtime
  (`runtime.destroy(forcedDeath)`) when the block at `pos` changes (also default-kills on unloaded chunk logic path).

### `com.lowdragmc.photon.client.fx.EntityEffectExecutor` — attach to an entity
```
public EntityEffectExecutor(FX, Level, Entity, EntityEffectExecutor.AutoRotate)
public void start()
public static Map<Entity, List<EntityEffectExecutor>> CACHE
public enum AutoRotate { NONE, FORWARD, LOOK, XROT }
```
- Every render frame (`updateFXObjectFrame`) the root is moved to
  **`entity.getEyePosition(partialTicks) + offset`**; `autoRotate` orients the effect
  (`NONE` = keep set rotation, `FORWARD`/`LOOK`/`XROT` follow the entity's facing).
- Every tick (`updateFXObjectTick`): when `!entity.isAlive()` → `runtime.destroy(forcedDeath)`
  and self-removal from `CACHE`. Attachment/cleanup is automatic.
- Same `allowMulti` dedup rule as blocks, keyed per `Entity`.

### `com.lowdragmc.photon.client.fx.FXRuntime` — a live playing instance
```
public FXRuntime(FXData)
public void emmit(IEffectExecutor)             // note the spelling: "emmit"
public void emmit(IEffectExecutor, int delay)
public boolean isAlive()                       // any IFXObject still alive
public void destroy(boolean forced)            // forced=true kills particles instantly,
                                               // false lets emitters stop + fade naturally
public IFXObject findObject(String name);  public List<IFXObject> findObjects(String name)
public IFXObject getRoot();  public Map<UUID, IFXObject> getObjects()
// implements com.lowdragmc.lowdraglib2.editor.ui.sceneeditor.sceneobject.IScene
```
Rendering/ticking: `FXObject extends net.minecraft.client.particle.Particle`; `emmit` adds
each object to **`Minecraft.getInstance().particleEngine`** (vanilla `ParticleEngine.add`),
so effects tick/render/cull through the vanilla particle pipeline (Photon mixes into
`ParticleEngine`/`Minecraft` for level-change cleanup; an LDLib2 `DummyWorld` particle
manager path exists only for editor previews).

---

## 2. `.fx` addressing — CAN our mod ship them? **YES**

- An id `eclipse:altar_levelup` resolves to the resource
  **`assets/eclipse/fx/altar_levelup.fx`** (pattern: `assets/<namespace>/fx/<path>.fx`,
  constants `FX_PATH="fx/"`, `SUFFIX=".fx"`).
- Loading goes through the **vanilla `ResourceManager`**, so ANY provider works:
  our own mod jar's `src/main/resources/assets/eclipse/fx/…`, a resource pack, or
  another mod. Nothing needs to live in Photon's config folder, and no registration
  call is needed — files are discovered lazily on first `getFX`.
- Proof it's namespace-agnostic: `FxLocationArgument` (the `/photon fx` argument type)
  tab-completes via `ResourceManager.listResources("fx", p -> p.endsWith(".fx"))` across
  **all namespaces**, stripping `fx/` + `.fx` to suggest ids.
- Format: **compressed NBT** authored in Photon's in-game editor (`/photon_editor fx_editor`),
  NOT hand-writable JSON. Author in-game, save, copy the produced `.fx` into
  `assets/eclipse/fx/`. The photon jar itself ships zero `.fx` examples.

## 3. Lifecycle summary

- **One-shot vs looping is a property of the asset**, not the spawn call: each
  `ParticleEmitter` inside the `.fx` has `duration` (ticks), `looping` (bool), `prewarm`,
  `startDelay`, `maxParticles` (see `ParticleConfig`). A non-looping effect emits for
  `duration` and dies on its own (`FXRuntime.isAlive()` → false, executor pruned from CACHE).
  A looping effect plays until something calls `destroy`.
- **Stop programmatically**: keep the executor (or scan `BlockEffectExecutor.CACHE` /
  `EntityEffectExecutor.CACHE`), then `executor.getRuntime().destroy(force)` —
  `force=false` = graceful fade, `force=true` = instant.
- **Auto-stop**: entity death (entity executor), block change with `checkState=true`
  (block executor), level change (Photon's `MinecraftMixin`/`ParticleEngineMixin` clear the engine).
- **Repeat-fire gotcha**: with default `allowMulti=false`, re-spawning the SAME fx id at the
  SAME BlockPos/Entity while the previous runtime is still alive is a **silent no-op**.
  Call `setAllowMulti(true)` for stackable bursts.

## 4. Client/server split

- **Spawning is 100% client-side.** All `com.lowdragmc.photon.client.fx.*` classes live in
  the client package; executors construct `Particle`s and touch `Minecraft.getInstance()`.
  Photon's own mods.toml even marks its minecraft/neoforge deps `side = "CLIENT"`.
- Vanilla Photon's in-world trigger is exactly our payload pattern: the **server** command
  `/photon fx <location> block <pos> [offset|rotation|scale|delay|force death|allow multi|check state]`
  (and `… entity <targets> [auto rotate …]`) builds a `CustomPacketPayload`
  (`BlockEffectCommand` / `EntityEffectCommand`, both extend `EffectCommand`) and sends it
  S2C; the nested `*Command$Client.execute(cmd, IPayloadContext)` handler then does
  `FXHelper.getFX(location)` → `new (Block|Entity)EffectExecutor(...)` → setters → `start()`.
  `RemoveBlockEffectCommand` / `RemoveEntityEffectCommand` are the stop payloads: they scan
  the executor `CACHE` (optionally filtered by fx location) and call `runtime.destroy(force)`.
- So our architecture (`S2CQuasarPayload` → client handler → `PhotonBridge.spawn`) is
  **the same shape Photon itself uses**. There is no server-side spawn API to call.
- Photon has NO block/blockentity that plays effects; triggers are commands (or other mods
  calling the executor API client-side). Client-only utility commands:
  `/photon_client clear_particles`, `/photon_client clear_client_fx_cache`,
  and `/photon_editor fx_editor` (opens the editor).

## 5. Our bridge (`veilfx/PhotonBridge.java`) vs the real jar — audit result

All three reflected points match the 2.1.5 bytecode **exactly**. No mismatches:

| Bridge reflection | Real signature (javap) | Status |
|---|---|---|
| `FXHelper.getMethod("getFX", ResourceLocation.class)` | `public static FX getFX(ResourceLocation)` | ✅ exact |
| `BlockEffectExecutor.getConstructor(FX, Level, BlockPos)` | `public BlockEffectExecutor(FX, Level, BlockPos)` | ✅ exact |
| `blockExecutor.getMethod("start")` | `public void start()` | ✅ exact |
| `getFX` returns `null` on missing asset (bridge's `missing()` path) | `loadFX` catches `Exception` → `null`; null not cached | ✅ correct |

Optional (non-blocking) refinements, all verified available:
1. **Sub-block precision**: the executor plays at `BlockPos + 0.5 + offset`. For an exact
   `Vec3 pos`, reflect `setOffset(Vector3f)` (or the `IFXEffectExecutor` default
   `setOffset(double,double,double)`) and pass `pos - (blockCenter)` before `start()`.
2. **Session-skip via `MISSING_FX` is stricter than Photon**: since null results are never
   cached, a `/reload` that adds the asset would start working — our session-skip forgoes that
   (acceptable, just know it).
3. **`allowMulti` default false** means rapid repeat cues at one altar BlockPos are deduped
   while the previous effect is alive — desirable for us, but if a design ever needs stacking,
   reflect `setAllowMulti(true)`.
4. For entity-attached effects later: reflect
   `EntityEffectExecutor(FX, Level, Entity, EntityEffectExecutor$AutoRotate)` +
   `EntityEffectExecutor$AutoRotate.valueOf("NONE")`; death-cleanup is automatic.

## 6. Working reflection recipe (client thread only)

```java
// resolve once (all names verified against photon-neoforge-1.21.1-2.1.5.jar)
Class<?> fxHelper  = Class.forName("com.lowdragmc.photon.client.fx.FXHelper");
Class<?> fxClass   = Class.forName("com.lowdragmc.photon.client.fx.FX");
Class<?> blockExec = Class.forName("com.lowdragmc.photon.client.fx.BlockEffectExecutor");
Method getFX  = fxHelper.getMethod("getFX", ResourceLocation.class);      // static
Constructor<?> ctor = blockExec.getConstructor(fxClass, Level.class, BlockPos.class);
Method start  = blockExec.getMethod("start");
// optional knobs (declared on abstract FXEffectExecutor, inherited public):
Method setOffset = blockExec.getMethod("setOffset", org.joml.Vector3f.class);
Method setAllowMulti = blockExec.getMethod("setAllowMulti", boolean.class);

// spawn: MUST run on the client main thread with a live ClientLevel
Object fx = getFX.invoke(null, ResourceLocation.fromNamespaceAndPath("eclipse", "altar_levelup"));
if (fx != null) {                                    // null == assets/eclipse/fx/altar_levelup.fx absent
    ClientLevel level = Minecraft.getInstance().level;
    BlockPos bp = BlockPos.containing(pos);
    Object exec = ctor.newInstance(fx, level, bp);
    // optional exact-Vec3 anchoring (executor adds bp + 0.5 itself):
    setOffset.invoke(exec, new org.joml.Vector3f(
            (float) (pos.x - (bp.getX() + 0.5)),
            (float) (pos.y - (bp.getY() + 0.5)),
            (float) (pos.z - (bp.getZ() + 0.5))));
    start.invoke(exec);
    // to stop a looping effect later: Object rt = blockExec.getMethod("getRuntime").invoke(exec);
    // rt.getClass().getMethod("destroy", boolean.class).invoke(rt, false);
}
```

## 7. LDLib2 (2.2.29) surface we transitively depend on

Our bridge reflects **zero** LDLib2 classes directly — good. Photon internally pulls in:
- `com.lowdragmc.lowdraglib2.Platform.getFrozenRegistry()` — registry access for
  `FX.deserializeNBT` during `FXHelper.loadFX`.
- `com.lowdragmc.lowdraglib2.editor.ui.sceneeditor.sceneobject.IScene` / `ISceneObject` —
  implemented by `FXRuntime` / `IFXObject` (only matters if we ever hold typed references;
  reflection shields us).
- `com.lowdragmc.lowdraglib2.registry.ILDLRegisterClient`, `syncdata.IPersistedSerializable`,
  `configurator.IConfigurable` — supertypes of `IFXObject` (emitter (de)serialization registry).
- `com.lowdragmc.lowdraglib2.client.scene.ParticleManager` + `utils.virtuallevel.DummyWorld` —
  editor-preview only; in-world playback uses the vanilla `ParticleEngine`.

Keep both jars versioned together: photon 2.1.5 requires `ldlib2 [2.2.24,)`; we ship 2.2.29. ✅
