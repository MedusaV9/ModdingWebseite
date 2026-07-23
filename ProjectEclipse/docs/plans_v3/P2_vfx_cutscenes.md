# P2 — Veil VFX, Shaders, Cutscenes & Cinematic Sequences — Implementation Plan (plans_v3)

**Planner:** P2 (one of six parallel planners)
**Scope:** All Veil post pipelines/shaders, Quasar particle work, world-space FX renderers, the cutscene engine, and the three big cinematic sequences (intro v3, map expansion v2, storm reveals). Plus supporting FX for portals, loading transitions, supply drops, border, limbo, and death/respawn.
**Target:** NeoForge 21.1.238 / MC 1.21.1 / Veil 4.3.0 (jar-in-jar, required) / optional client Sodium 0.8.12 + Iris 1.8.14-beta.1.
**Audience:** implementation workers who CANNOT see the original user request. Everything needed is in this file.

## Hard constraints (apply to every worker package)

1. **NEVER modify** `admin/EclipseCommands.java`. New commands go into new classes that self-register on `RegisterCommandsEvent` (game bus, `@EventBusSubscriber`).
2. **NEVER modify** `assets/eclipse/lang/en_us.json` / `de_de.json`. Every new user-visible string is dropped as `docs/plans_v3/langdrop/<worker-id>.json` in the shape
   `{"en_us": {"key": "text", ...}, "de_de": {"key": "text", ...}}`. All strings ship **en + de**.
3. **`EclipseMod.java` is NOT edited.** No package below needs it: every new class self-registers via `@EventBusSubscriber` (game or MOD bus). New network payloads register through a MOD-bus `RegisterPayloadHandlersEvent` subscriber (`network/fx/FxPayloads.java`, owned by W1) — NeoForge allows any number of payload registrars; `EclipsePayloads.register(...)` stays untouched. New sounds go into the existing `registry/EclipseSounds.java` deferred register (owned by W1). Wiring summary per package is listed in §5; the total EclipseMod diff is **zero lines**.
4. **No two worker packages modify the same file.** §8.1 is the authoritative ownership matrix; if you think you need a file you don't own, you implement against the frozen API in §3/§8 instead.
5. **Performance budgets** (§3.5) are acceptance criteria, not suggestions: emitter caps, ≤ 3 concurrent fullscreen post passes, ≤ 16 concurrent Veil point lights from FX, zero per-frame heap allocations in render loops (pre-allocated scratch `Vector3f/4f/Matrix4f` fields, no streams, no iterators in hot paths).
6. **Iris gate**: every Veil post pipeline stays hard-gated behind `EclipseIrisState.shaderPackActive()` and `EclipseClientConfig.veilPostFx()`, exactly like today. World-space geometry FX (beams, storms, rifts, sky quads) render regardless — they are the Iris fallback (§7).
7. `git mv`/deletes are allowed only for files the package owns.

---

## 1. CURRENT-STATE AUDIT

All statements below were verified by reading the code on branch `cursor/project-eclipse` and by unzipping the Veil 4.3.0 jar (`/tmp/veiljar`, from the Gradle cache). No Gradle builds were run.

### 1.1 The `veilfx/` layer

- **`veilfx/VeilPostController.java`** — owns the three existing pipelines:
  - `eclipse:limbo` (purple grade + breathing vignette; `Intensity` uniform eased over ~3 s after entering limbo, `limboEnterMillis`),
  - `eclipse:sun_halo` (`SunDirection` uniform = `(-sin θ, cos θ, 0)`, θ from `level.getSunAngle(partialTick)`),
  - `eclipse:border_glitch` (`Proximity` + `Time` uniforms, fed from `BorderFxRenderer`).
  Uniforms are fed in a `VeilEventBus` **`preVeilPostProcessing`** hook keyed by pipeline id. Pipelines are added/removed per client tick based on dimension / proximity; everything is gated by `EclipseIrisState.shaderPackActive()` and `EclipseClientConfig.veilPostFx()`; a `MAX_FAILURES` counter (3) permanently disables a pipeline for the session after repeated exceptions (log-once). `onLoggingOut` removes all pipelines quietly.
- **`veilfx/QuasarSpawner.java`** — safe wrapper over Veil's `ParticleSystemManager`: `spawn`/`spawnManaged` (one-shot + handle), `spawnOrFallback` (vanilla `END_ROD`/`PORTAL` fallback when an emitter is broken/missing; `BROKEN`/`WARNED_UNKNOWN` sets make failures one-log), `ensureAttached`/`removeAttached`/`clearAttached` for looping per-entity emitters, `prune()` housekeeping. There is a ~30 spawns/s informal cap referenced by callers, but **no central budget object** (each caller throttles itself).
- **`veilfx/LimboAmbience.java`** — limbo-only ambience: rolling window of `eclipse:limbo_motes` managed emitters following the player + `ambient.limbo_loop` sound with fade in/out (`LimboLoopSound`).

### 1.2 Post pipelines & shaders today

All three pipelines are single-stage `veil:blit` into `veil:post` (`assets/eclipse/pinwheel/post/*.json` + `shaders/program/*.fsh|.json`):

- `limbo.fsh` — desaturate toward violet + soft breathing vignette, scalar `Intensity`.
- `sun_halo.fsh` — reconstructs a per-pixel **world-space view ray** via `veil:space_helper`'s `screenToWorldSpace(...)` (inverse view-projection from the `veil:camera` uniform block), takes `dot(viewDir, SunDirection)` and layers a tight rim + wide glow. Sun occlusion approximated with the depth sample.
- `border_glitch.fsh` — chromatic aberration + horizontal displacement driven by `Proximity`/`Time`; applied **fullscreen**, uniformly.

### 1.3 Sun-halo misalignment — root cause

The halo and the visible sun disc are drawn from **two different camera models**:

1. `OverworldPurpleEffects` (a `DimensionSpecialEffects`) draws the purple sun quad inside vanilla's sky pass using the **event pose stack** — which, in 1.21.1, includes **view bobbing** (and screen-shake pose modifications) baked into the modelview it receives.
2. `sun_halo.fsh` reconstructs its ray from Veil's `veil:camera` uniform block (`CameraMatrices`). Veil's `CameraMatrices.update()` deliberately **moves view bobbing out of the projection/modelview split** it maintains (it reconstructs `ViewMat` from camera yaw/pitch and position — decompiled and verified in `/tmp/veiljar` → `foundry/veil/api/client/render/CameraMatrices.class`). With *View Bobbing ON* (default) the two disagree every frame while walking; with FOV effects (sprint) there are additional transient differences.
3. The Java-side `SunDirection` **formula itself is correct**: vanilla's celestial transform is `rotY(-90°) · rotX(sunAngle·360°)` applied to local up `(0,1,0)` → world dir `(-sin θ, cos θ, 0)`, which is exactly what `VeilPostController` feeds. The error is **matrix-side, not angle-side**.

**Consequence:** any fix that keeps reconstructing rays from `veil:camera` will keep swimming. **Frozen fix (design R2, §4):** compute the sun's **screen position on the CPU once per frame** from the *exact* matrices of the render event (`RenderLevelStageEvent#getModelViewMatrix()` / `#getProjectionMatrix()` — both exist in NeoForge 21.1), pass `SunScreen` (vec4: NDC x/y, visibility flag, angular radius) as a plain uniform, and make the halo a pure screen-space radial effect around that point. The sky-quad renderer and the post shader then share one source of truth (`SunTracker`, §3.1) and cannot diverge by construction.

### 1.4 Night darkness & clouds — why the sky never darkens

- There is **no darkness treatment at all** right now: no post grade at night, and `OverworldPurpleEffects` only blends the *sky color* toward purple during the day. Perceived night brightness is dominated by the user's Brightness/gamma option and vanilla lightmap — untouched by the mod.
- Vanilla **clouds render normally** in the overworld (`OverworldPurpleEffects` doesn't override cloud rendering; limbo's `LimboSpecialEffects` has no clouds only because its dome covers them).
- Fix (R3/R4, §4): a consolidated `eclipse:world_grade` post pipeline (shadow-crushing tone curve at night / during eclipse phases — robust against user gamma because it operates on the final image), plus `renderClouds` overrides returning `true` (handled → nothing drawn) in both dimension effects.

### 1.5 Quasar emitter inventory & the per-particle light trap

`assets/eclipse/quasar/emitters/` (9 emitters, all verified):

| Emitter | rate | count | emitter life | loop | `veil:light` | `veil:trail` | Used by |
|---|---|---|---|---|---|---|---|
| `altar_beam` | 1 | 5 | 12 | no | **YES (radius 8)** | no | SupplyBeacon drop burst |
| `arm_wisps` | 4 | 1 | 20 | yes | no | yes | ARM artifact |
| `border_glitch` | 2 | 3 | 20 | no | no | no | SoftBorder pushback + BorderFxRenderer |
| `boss_slam` | 1 | 20 | 2 | no | no | no | boss |
| `cutscene_veil` | 2 | 12 | 8 | no | no | no | StartEventCutscene bursts |
| `heart_burst` | 1 | 6 | 2 | no | no | no | HeartBurstOverlay/lives |
| `limbo_motes` | 5 | 2 | 20 | yes | no | no | LimboAmbience |
| `map_expand_materialize` | 1 | 4 | 10 | no | **YES** | no | RingGrowthService sweep FX |
| `unlock_burst` | 2 | 10 | 4 | no | no | no | AnnouncementOverlay |

**Key perf finding:** Quasar's `veil:light` render module attaches a **dynamic point light to every particle**. `altar_beam` spawns 5 particles/tick for 12 ticks with 30±8-tick particle lifetimes → up to **~60 concurrent point lights** the moment a supply crate drops. Veil's light renderer (deferred light passes, `foundry/veil/api/client/render/light/`) is the expensive part — this is the primary "ultra lag on supply drop" cause, together with the packet flood in §1.10. `map_expand_materialize` has the same trap (fired every 5 ticks by `RingGrowthService` for the whole ~75 s sweep). **Frozen rule (§3.5): no `veil:light` module on any emitter with `count × lifetime > 8`; lights are attached as dedicated 1-particle "light carrier" emitters or via the FX renderer itself, within the global light budget.**

### 1.6 Cutscene engine

- **`cutscene/CutscenePath.java`** — JSON record: `id, enabled, allowSkip, interpolation (catmullrom|bezier), anchor (world|player), dimension, letterbox, hideHud, durationTicks, keyframes[t,x,y,z,yaw,pitch,roll,fov,easing], events[t,type,id], params`. Library JSONs in `assets/eclipse/cutscenes/`: `intro_submerge`, `intro_rise`, `unlock_ring`, `finale_return`.
- **`cutscene/client/CameraDirector.java`** — camera override on `onComputeCameraAngles`/`onComputeFov`: Catmull-Rom/Bezier position, per-keyframe easing, roll, FOV, shake (`S2CShakePayload`), an end-blend back to the player, `progress()` from `startNanos`, sound `fireEvents`. Known weaknesses: **t-uniform Catmull-Rom** (speed pumping between unevenly spaced keyframes), no look-at targets (yaw/pitch keyed by hand), single-octave shake.
- **`cutscene/CutsceneService.java`** — server orchestration: sessions, `FreezeService` freeze+invuln, `S2CCutscenePlayPayload`, client ACKs (`STARTED/FINISHED/SKIPPED` via `C2SCutsceneStatePayload`), watchdog for unresponsive clients, library sync at login (`S2CCutsceneLibraryPayload`). **No teleport/return support, no view-distance handling** — players far away or in the nether see void/unloaded chunks during "global" cutscenes.
- **`cutscene/FreezeService.java`** — transient `CutsceneLock` attachment: rubber-band to anchor, interaction block, invuln, watchdog.
- **`cutscene/client/LetterboxLayer.java`** + **`client/EclipseGuiLayers.java`** — cinematic bars, skip hint, and **HUD suppression**: while `CameraDirector.isHudSuppressed()`, every GUI layer not in the whitelist is cancelled.
- **`cutscene/UnlockCinematics.java`** — plays `unlock_ring` on stage growth for players in the growing dimension; aborts on completion.

### 1.7 Invisible subtitle bug — root cause

Cutscene "subtitles" are delivered as announcements (`S2CAnnouncePayload` → `client/hud/AnnouncementOverlay`, a GUI layer with typewriter text + bossbar sweep). `EclipseGuiLayers` registers the letterbox whitelist **without** the announcement layer id → while a cutscene runs with `hideHud=true`, `LetterboxLayer.onRenderGuiLayerPre` **cancels the announcement layer**, so the text is genuinely never drawn (not a z-order or alpha issue). Fix + upgrade in R12 (§4): whitelist it AND move cinematic captions into a dedicated `CaptionRenderer` drawn from within the letterbox layer itself (immune to suppression by construction).

### 1.8 `client/WaveOverlay.java` (event-start wave effect)

GUI layer + audio muffle driven by `ClientStateCache.cutscenePhase` (`S2CCutscenePayload.Phase`: `TILT, SUBMERGE, WAVES, EMERGE`, broadcast by `limbo/StartEventCutscene`):
- TILT → pulsing dark fill; SUBMERGE/WAVES → scrolling tiled `wave_overlay.png` at rising alpha over a dark blue wash + master/music/records/ambient volumes scaled down (originals persisted to `config/eclipse-volume-restore.json` for crash recovery); EMERGE → 40-tick fade + volume restore; auto-clear after 600 ticks without a phase packet.
- Verdict: the **audio-muffle + crash-restore machinery is good and stays**; the *visual* (flat tiled texture) is the weak part to replace (R8).

### 1.9 Border FX today

- **Server** `border/SoftBorder.java`: circular soft border per disc dimension, radius from stage commits (`stageOuterRadius + borderOffset`), area-proportional lerp coupled to the `RingGrowthService` sweep; pushback impulse / teleport fallback / pearl clamps; `S2CBorderPayload` sync (center, from/to radius, lerp ticks, fxRange); glitch sound + `BORDER_GLITCH` Quasar burst on pushback.
- **Client** `border/client/BorderFxRenderer.java`: (a) a **±25° arc strip** of ≤200 additive quads, ±12 blocks around player Y, scrolling `border_glitch.png`, per-quad flicker, drawn at `AFTER_PARTICLES` camera-relative; (b) throttled `BORDER_GLITCH` emitters along the arc; (c) proximity fed to `VeilPostController.setBorderProximity` → fullscreen chromatic aberration. The user's complaints map 1:1: the strip reads as a **long wall stripe** (it literally is an arc wall), and the post effect is **weak and unlocalized** (uniform fullscreen aberration at low strength).

### 1.10 Supply beacon — lag + lifecycle

`economy/SupplyBeacon.java`:
- `drop()` ticket-loads the target chunk, spawns a `FallingBlockEntity` barrel with `LootTable` blockData, registers a `Marker(surfacePos, expiry = now + 3600 ticks)` and sends **one `ALTAR_BEAM` Quasar payload to every player in the dimension** (unbounded range).
- `onServerTick` every 20 ticks per marker: builds **13 `ClientboundLevelParticlesPacket`s** (`END_ROD`, column height 48, step 4, `longDistance=true`) and fans each through `PlayerList.broadcast` with **512-block radius**. With N markers × P players that's `13·N` packet builds and up to `13·N·P` sends per second, plus END_ROD's client cost at long distance.
- **Lag at spawn** = the ~60 concurrent Quasar point lights (§1.5) + this packet/particle flood starting simultaneously.
- **Lifecycle bug** = markers expire **only by time** (180 s). Nothing observes the barrel: looting or breaking it leaves the beam running for the remainder. There is no barrel↔marker link beyond the position.

### 1.11 Sky renderers

- `client/sky/OverworldPurpleEffects.java` — purple sun quad (`SUN_PURPLE` texture) + soft halo quad + daytime sky-color blend toward purple; skips entirely when `EclipseIrisState.shaderPackActive()`. Sun quad size is vanilla-ish (~30 units) → the "too small" complaint.
- `client/sky/LimboSpecialEffects.java` — near-black dome, sparse green stars, **fixed eclipse disc** (`ECLIPSE_TEXTURE`) at a fixed sky position; same Iris skip.
- `client/mixin/LevelRendererMixin.java` — cancels vanilla world-border rendering (the only render mixin; the mixin config is **frozen — no P2 package adds mixins**).
- `client/sky/EclipseIrisState.java` — `shaderPackActive()` via Veil `IrisCompat`; the single gate used everywhere.

### 1.12 Intro sequence + ring growth visuals today

- `limbo/StartEventCutscene.java` — server timeline `TILT → SUBMERGE → WAVES → TELEPORT → REFILL → EMERGE`: ship tilt tease, wave overlay phases, teleport limbo→overworld (`risePlayerAt` velocity-sync pattern: set `deltaMovement` + `hurtMarked = true`), `cutscene_veil` bursts, plays `intro_submerge`/`intro_rise` via `CutsceneService`.
- `worldgen/stage/RingGrowthService.java` — tick-budgeted column sweep (~75 s per stage), sends `MAP_EXPAND_MATERIALIZE` Quasar payloads every 5 ticks near the front, rescues entombed players. Terrain simply pops in column-by-column — there is no camera treatment, no structure-separated phase (P1 owns adding the two-phase hook, §6.1).

### 1.13 Veil 4.3.0 — verified API surface (jar + wiki)

Unzipped jar contents (`foundry/veil/api/...`) confirm everything this plan uses:

- **Post**: `client.render.post.PostPipeline`, `PostProcessingManager` (+ `ProfileEntry`), stage classes (`blit`, `copy`, `mask`, `depth_function`), uniform helpers. JSON pipelines under `assets/<ns>/pinwheel/post/`, programs under `pinwheel/shaders/program/`. Built-ins shipped by Veil itself: `veil:core/bloom`, `veil:core/composite`, `veil:core/first_person`, blit/blur programs — **bloom can be enabled as-is** for beam/rift glows.
- **Framebuffers**: `AdvancedFbo` (+Builder), `FramebufferManager`, `FramebufferDefinition` — JSON-definable FBOs (`pinwheel/framebuffers/`), usable as pipeline `in`/`out`.
- **Shaders**: full shader manager with includes (`pinwheel/shaders/include/`), pre-processor events (`VeilAddShaderPreProcessorsEvent`), `veil:camera` + `veil:gui_info` uniform blocks, `space_helper.glsl` transforms.
- **Lights**: `client.render.light` — point/area/directional light data + instanced/indirect renderers (this is what Quasar's `veil:light` module feeds). Programmatic API: `VeilRenderSystem.renderer().getLightRenderer()`.
- **Quasar**: `quasar.data/emitters/fx/particle/registry` — data-driven emitters (shapes incl. `veil:cylinder/sphere/point`, modules incl. `veil:initial_velocity`, `veil:color` (gradient+interpolant Molang), `veil:light`, `veil:trail`, forces incl. **`veil:vortex`**, `veil:wind`, `veil:gravity`, `veil:drag`, collision), `ParticleSystemManager`, `ParticleEmitter` handles (position/rotation setters, attach-to-entity).
- **Events** (NeoForge bus): `VeilPostProcessingEvent.Pre/Post`, `VeilRenderLevelStageEvent` (+`Stage`), `VeilRegisterFixedBuffersEvent`, `VeilRegisterBlockLayersEvent`, `VeilRendererAvailableEvent`, `VeilShaderCompileEvent`, `VeilDynamicBuffersChangedEvent`.
- **Dynamic buffers**: `dynamicbuffer.DynamicBufferType` (albedo/normal/lightmap channels for post) — available but **not required** by this plan (kept as stretch, §7 risk table).
- **Misc**: `CameraMatrices`, `GuiInfo`, `MatrixStack`, `CullFrustum`, `VeilLevelPerspectiveRenderer` (render the level from an arbitrary camera into an `AdvancedFbo` — optional portal stretch goal only, OFF by default), Necromancer skinned-mesh animation (not used by this plan).

### 1.14 Iris/Sodium compat state (README-verified)

- Tested client pack: **Sodium 0.8.12 + Iris 1.8.14-beta.1** (`run/mods-client/`, copied into `run/mods/` for client runs only). Veil 4.3.0 hard-requires Sodium ≥ 0.8.12-alpha.2 and is incompatible with Embeddium/Rubidium; the old Sodium 0.6.13/Iris 1.8.12 pack no longer boots.
- Behavior contract already in the repo: **when an Iris shaderpack is active, ALL Veil post pipelines and the custom sky renderers are skipped** (`EclipseIrisState`). Sodium alone (no shaderpack) runs the full Veil stack. `BorderFxRenderer` documents the known Sodium depth-sort caveat: if artifacts appear at `AFTER_PARTICLES`, switch to `AFTER_TRANSLUCENT_BLOCKS` (same matrices) — this plan adopts that as a config-free constant swap fallback for every world-space FX renderer.

---

## 2. PHOTON VERDICT

**Available for NeoForge 1.21.1: YES. Adopt: NO.** Details:

- **Availability**: Photon's current line ("Photon Editor", LowDragMC) publishes `mc1.21.1-2.2.0-neoforge` (checked 2026-07, Modrinth/CurseForge files list; latest file published 2026-07-21). It requires its graph/runtime library (KilaGraph/LDLib family) as an additional runtime dependency.
- **What it would add**: a Unity-like in-game FX editor + runtime player (emitter graphs, curves, trails, meshes), i.e. authoring convenience — not a capability we lack: Veil's Quasar + post + light stack already covers every effect in §4.
- **Compat risk (deciding factor)**:
  1. Photon + Veil **both install their own rendering hooks**; there is no documented compatibility statement between them, and no known pack running both on 1.21.1 NeoForge. Debugging a double-pipeline interaction is unbudgeted risk.
  2. Our Iris/Sodium matrix is only validated for Veil (§1.14). Photon's Iris behavior is unknown → the gating story ("post off under shaderpacks, world FX stay") would fracture.
  3. It adds a second required client+server jar pair to a modpack that deliberately keeps hard dependencies to one (Veil, jar-in-jar). Licensing/redistribution for jar-in-jar is unverified.
  4. Every P2 asset would split across two runtimes — worker parallelism and review get harder, and dev-command tooling (§5 W2) would need duplicating.
- **Decision**: pure-Veil for all 18 requirements. This is not a fallback plan — §4 designs are Veil-native from the start. If a future planner revisits Photon, the only candidates worth the risk are the storm-vortex volumetrics and the portal surface, both of which have Veil designs below that meet the bar.

---

## 3. ARCHITECTURE — the shared FX core (FROZEN interfaces)

Everything in §3 is **frozen**: class names, method signatures, uniform names, payload shapes, resource ids. Workers code against these without seeing each other's diffs. W1 implements §3.1–§3.4; everyone else only *references* them.

### 3.1 New core classes (package `dev.projecteclipse.eclipse.veilfx`, owned by W1)

```java
/** Client-side FX blackboard. All setters are safe to call from payload handlers/tick; reads happen in render. */
public final class EclipseFxState {
    // Eclipse phases: 0=NONE, 1=BUILDUP, 2=TOTAL, 3=ENDING
    public static void setEclipse(int phase, float intensity, int rampTicks);
    public static float eclipseAmount(float partialTick);       // eased 0..1
    public static int eclipsePhase();
    public static void setPermanentSunRim(boolean rim);          // set once after intro v3
    public static boolean permanentSunRim();
    public static void setBorderProximity(float p);              // moved here from VeilPostController
    public static float borderProximity();
    public static void setAltarAberration(float a);              // 0..1
    public static float altarAberration();
    public static void setGhost(boolean active);                 // 0-lives grade
    public static float ghostAmount(float partialTick);          // eased
    public static void startShockwave(Vec3 worldOrigin, float strength, int durationTicks);
    /** null when inactive; xy = screen ndc of origin, z = progress 0..1, w = strength */
    public static Vector4f shockwaveParams(float partialTick);
    public static void setStormInterior(float amount, float rain); public static float stormInterior(); public static float stormRain();
    public static void startTransitionGlitch(int inTicks, int holdTicks, int outTicks); // rift/portal/loading
    public static float transitionGlitch(float partialTick); public static float transitionFade(float partialTick);
    public static void clearAll();                                // logout/disconnect
}

/** Global FX budgets. Every emitter spawn and FX light goes through this. */
public final class FxBudget {
    public enum Channel { AMBIENT, BURST, SEQUENCE, STORM }
    public static boolean tryEmitter(Channel c);                  // enforces per-channel spawns/sec + global live cap
    public static boolean tryLight();                             // max 16 concurrent FX lights, LRU-refused
    public static void releaseLight();
    public static int qualityTier();                              // 2=full, 1=reducedFx, 0=minimal (derived from EclipseClientConfig)
}

/** One source of truth for the sun. Updated once per frame from RenderLevelStageEvent(AFTER_SKY) matrices. */
public final class SunTracker {
    public static Vector3f sunDirWorld(float partialTick);        // (-sin θ, cos θ, 0)
    /** x,y = NDC pos; z = 1 when in front of camera else 0; w = angular radius in NDC-y units. Never null; z=0 when invalid. */
    public static Vector4f sunScreen();
    public static boolean sunOccluded();                          // cheap depth probe result from last frame
}

/** Named world positions other systems (P6 ship door, altar) publish for FX. Server sets, auto-synced. */
public final class FxAnchors {
    public static void set(ResourceLocation id, ServerLevel level, Vec3 pos);   // server; re-broadcasts
    public static void remove(ResourceLocation id, ServerLevel level);
    @Nullable public static Vec3 get(ResourceLocation id);                      // client read
    // frozen ids: eclipse:ship_door, eclipse:altar_center, eclipse:ship_deck
}
```

`VeilPostController` is **rewritten by W1** into a table-driven registry: each pipeline gets a row `(id, activationPredicate, uniformFeeder, priority)`; the controller enforces the ≤3 concurrent fullscreen cap by priority (`GRADE(0) < FEATURE(1) < TRANSITION(2)` — when over budget, lowest priority drops first), keeps the failure counter + Iris/config gate, and exposes:

```java
public final class VeilPostController {
    public static void register(PipelineSpec spec);   // called from each feature's static init (client)
    public static void setEnabled(ResourceLocation pipeline, boolean enabled); // dev commands
    public static boolean isActive(ResourceLocation pipeline);
}
```

### 3.2 New network payloads (`network/fx/FxPayloads.java`, owned by W1; shapes FROZEN)

Registered via a MOD-bus `@EventBusSubscriber` handling `RegisterPayloadHandlersEvent` (no `EclipsePayloads` edits). All are `S2C` `playToClient` unless noted. Handlers are thin: they call the frozen client entry points listed right here.

| Payload | Fields | Client dispatch |
|---|---|---|
| `S2CEclipsePhasePayload` | `int phase, float intensity, int rampTicks, boolean permanentRim` | `EclipseFxState.setEclipse(...)`, `setPermanentSunRim(...)` |
| `S2CFxEventPayload` | `ResourceLocation id, Vec3 pos, float a, float b` | switch on `id` → frozen hooks below |
| `S2CStormStatePayload` | `int stormId, Vec3 center, float radius, float height, int type(0=WALL,1=VORTEX), int state(0=SPAWN,1=ACTIVE,2=DISSIPATE), int ticks` | `StormFxClient.handle(...)` (W9) |
| `S2CSupplyMarkerPayload` | `boolean add, BlockPos pos, int fadeTicks` | `SupplyBeamClient.handle(...)` (W5) |
| `S2CViewDistancePayload` | `int chunks (0 = restore)` | `ViewDistanceClient.handle(...)` (W2) |
| `S2CScreenFadePayload` | `int inTicks, int holdTicks, int outTicks, int argb` | `CaptionRenderer.fade(...)` (W2) |
| `S2CCaptionPayload` | `String langKey, int durationTicks, int style(0=SUBTITLE,1=TITLE,2=WHISPER)` | `CaptionRenderer.enqueue(...)` (W2) |
| `S2CGhostStatePayload` | `boolean active` | `EclipseFxState.setGhost(...)` |
| `S2CAnchorPayload` | `ResourceLocation id, boolean set, Vec3 pos` | `FxAnchors` client cache |

Frozen `S2CFxEventPayload` ids (constants in `FxPayloads`): `eclipse:fx/lightning_strike` (pos = impact, a = intensity 0..1, b = 0 normal / 1 giant), `eclipse:fx/shockwave` (a = strength, b = durationTicks), `eclipse:fx/rift_open` (a = width blocks, b = style 0 structure/1 portal), `eclipse:fx/rift_close`, `eclipse:fx/glide_start`/`eclipse:fx/glide_stop` (pos = player), `eclipse:fx/door_glow` (a = 0 off / 1 on).

### 3.3 Pipeline registry (all P2 pipelines, ids FROZEN)

| Pipeline id | Priority | Uniforms (exact names) | Owner |
|---|---|---|---|
| `eclipse:world_grade` | GRADE | `EclipseAmount, NightAmount, DesatAmount, ExposureMul` | W1 |
| `eclipse:sun_halo` (rewrite) | FEATURE | `SunScreen (vec4), HaloStrength, RimOnly` | W1 |
| `eclipse:limbo` (rewrite) | GRADE | `Intensity, GodrayDir (vec2), CausticsAmount, Time` | W3 |
| `eclipse:border_glitch` (rewrite) | FEATURE | `Proximity, Time, GlitchDir (vec2), Seed` | W4 |
| `eclipse:altar_aberration` | FEATURE | `Aberration` | W4 |
| `eclipse:shockwave` | FEATURE | `ShockCenter (vec2), ShockProgress, ShockStrength` | W5 |
| `eclipse:storm_interior` | GRADE | `Interior, RainAmount, Time` | W9 |
| `eclipse:rift_glitch` | TRANSITION | `GlitchAmount, FadeAmount, Time` | W8 |
| `eclipse:ghost_grade` | GRADE | `Ghost` | W10 |

Shared GLSL: `assets/eclipse/pinwheel/shaders/include/eclipse_common.glsl` (W1): hash/value-noise (`float efxHash(vec2)`, `float efxNoise(vec2)`), chromatic sample helper (`vec3 efxChroma(sampler2D, vec2 uv, vec2 dir, float amt)`), scanline/datamosh block helper (`vec2 efxBlockOffset(vec2 uv, float seed, float amt)`), luma tone tools (`vec3 efxCrush(vec3 c, float amt)`). All new `.fsh` use **in-shader procedural noise — zero new textures required**.

### 3.4 Wiring (zero `EclipseMod` edits — mechanism list)

- Client tick/render classes: `@EventBusSubscriber(modid = "eclipse", value = Dist.CLIENT)`.
- Server services/sequences: `@EventBusSubscriber(modid = "eclipse")`.
- Payloads: MOD-bus subscriber in `FxPayloads` (§3.2).
- Sounds: added to existing `registry/EclipseSounds.java` (W1 adds ALL new `SoundEvent`s listed in §3.5; `assets/eclipse/sounds.json` maps them to **existing** ogg files as placeholders — no new binary assets are committed by P2).
- Dev commands: `RegisterCommandsEvent` in `cutscene/dev/FxDevCommands.java` (W2).
- Config: W1 adds `cinematicViewDistance` (bool, default `true`) to `EclipseClientConfig` — the only new config key.

### 3.5 Conventions & performance budgets (acceptance criteria for every package)

- **Emitters**: ≤ 30 spawns/s global (existing informal cap becomes `FxBudget` law); live Quasar particles ≤ 1500; `SEQUENCE` channel may burst to 60 spawns/s for ≤ 3 s during cutscenes. `reducedFx` halves every rate; tier 0 disables `AMBIENT`.
- **Lights**: ≤ 16 concurrent FX point lights (`FxBudget.tryLight`). **No `veil:light` module on bulk emitters** (§1.5 rule). Light radius ≤ 16.
- **Post**: ≤ 3 concurrent fullscreen passes (priority eviction, §3.1). Every pipeline must idle-skip (`setActive(false)` removes it from the manager rather than blitting a no-op).
- **World-space renderers**: one `d²` early-out per frame; vertex counts: border patches ≤ 240 quads, storm shells ≤ 4×96 segments (LOD §4 R14), beam ≤ 16 quads, rift ≤ 400 tris. No per-frame allocations: pre-sized `BufferBuilder` usage, scratch JOML objects as static fields.
- **Sounds** (W1 registers; all map to existing oggs as placeholders): `event.lightning_close`, `event.lightning_far`, `event.storm_loop`, `event.storm_burst`, `event.rift_open`, `event.rift_slam`, `event.eclipse_drone`, `event.beam_hum`, `ui.caption_tick` (alias of `ui.typewriter`).
- **Lang**: every caption/subtitle/toast key in `docs/plans_v3/langdrop/P2W<i>.json`, en+de, keys namespaced `eclipse.caption.*`, `eclipse.fx.*`, `eclipse.command.fx.*`.
- **Dimensions**: overworld = `DiscProfile.OVERWORLD` disc world; nether ring per §1.9; limbo custom.

---

## 4. DESIGNS PER REQUIREMENT (R1–R18)

**R1 — Bigger, global-feeling FX (cross-cutting)**
Concrete deltas, each owned by the package that owns the file: overworld sun quad 30 → **90 units during eclipse** with 3 additive rotating corona quads (90/140/200 units, 0.05/0.03/0.02 rot °/frame) (W1); `sun_halo` glow radius scales with `EclipseAmount` up to 0.55 NDC (W1); limbo eclipse disc 1.5× + 12-ray aura (W3); border patch height ±12 → full-screen-relative localized post punch (W4); every sequence gets screen-space support (grade + shockwave + captions), not just world particles. Rule of thumb frozen into acceptance criteria: **any hero effect must be visible in a 100°-FOV screenshot from 40 blocks away**.

**R2 — Sun halo alignment (fix)**
`SunTracker` (W1): subscribes `RenderLevelStageEvent` at `AFTER_SKY`; computes `dirWorld = (-sin θ, cos θ, 0)`; `clip = Proj · ModelView · vec4(dir, 0)` using the **event's matrices** (bobbing included); sun in front ⇔ `clip.w > 0`; `ndc = clip.xy / clip.w`; angular radius `w = tan(sunAngularRadius) · proj[1][1]` with sunAngularRadius = 5° (matches the 90-unit quad at sky distance). Result cached in a static `Vector4f` (no allocation). `OverworldPurpleEffects` renders the sun quad **from `SunTracker.sunDirWorld`** (same source), and `sun_halo.fsh` becomes screen-space: `d = length((uv*2-1 - SunScreen.xy) * vec2(aspect,1))`, rim = `smoothstep(w*1.15, w*0.95, d)`, glow = `exp(-d*k)·HaloStrength`, occlusion via one depth sample at `SunScreen.xy` (`RimOnly=1` when `sunOccluded`). Acceptance: with view bobbing ON, sprinting diagonally, halo center within 0.5° of the disc at all times.

**R3 — Real darkness (night + eclipse)**
`eclipse:world_grade` (W1, GRADE priority, active whenever `NightAmount>0.01 || EclipseAmount>0.01`): `NightAmount = clamp(1 − dayFactor, 0, 1) · 0.55` from client `level.getSkyDarken`/time curve; eclipse: `EclipseAmount` from `EclipseFxState`. Fragment: shadow-crush tone curve `c = mix(c, pow(c, vec3(1.35)) * 0.42, max(NightAmount, EclipseAmount·0.8))` + desat toward violet `DesatAmount = EclipseAmount·0.5` + sky-region extra dim (screen-space: pixels with depth==1). Because it operates on the final frame it defeats user gamma without touching options. During eclipse TOTAL, `ExposureMul` dips to 0.35 with a 60-tick ease. Iris fallback: none (shaderpack owns tone) — documented.

**R4 — No clouds**
`OverworldPurpleEffects` (W1) + `LimboSpecialEffects` (W3): override `renderClouds(...) { return true; }` (handled → nothing drawn) and pass `Float.NaN` cloud height in the constructor. Nether untouched (vanilla nether has no clouds).

**R5 — Limbo much more**
W3 owns. (a) **Sky**: eclipse disc repositioned to **exact zenith above the ship anchor** (`FxAnchors eclipse:ship_deck`, fallback: spawn), scaled 1.5×, plus a 12-quad rotating **aura ray fan** (additive, 0.4 alpha, lengths 40–120 units, slow 0.02 °/frame counter-rotation in two layers). (b) **Post** `eclipse:limbo` v2: keeps the violet grade; adds `GodrayDir` **screen-space radial god-rays from the zenith disc** (12-tap radial blur of the bright-pass along `GodrayDir`, strength ramps with looking up), `CausticsAmount` — animated voronoi-ish caustic ripple (procedural, `efxNoise`) applied only below the horizon line so the black water reads as "crazier purple water" from the deck; vignette kept. (c) **Ambience**: `limbo_godray` emitter (loop, vertical additive shafts, rate 10/count 1, size 6–10, life 80, **no lights**), `limbo_fog` (loop, size 8–14 soft quads, alpha ≤ 0.15, rate 8/count 2), `limbo_motes` densified near the ship (rate 5→3). All through `FxBudget.AMBIENT`.

**R6 — Border v2 (localized, stronger, nether variant)**
W4 owns. Replace the arc **strip** with **glitch patches**: 5–9 quad clusters (each 2–4 blocks, random offsets/rotations, additive, `border_glitch.png` UV-jittered) positioned on the ring **only within ±8° of the player's bearing**, re-seeded every 6–10 ticks (blocky "datamosh popping" instead of a wall) + 6 world-space "shard" sprites (`border_shard` emitter: count 6/rate 1/life 3, blocky sprites 0.4–1.4). Post `eclipse:border_glitch` v2: strength curve `Proximity^1.5`, and **localization** — `GlitchDir` = screen-space direction toward the nearest ring point (computed CPU-side per frame); the shader masks displacement/chroma/datamosh blocks to a lens centered on that screen side (`smoothstep` falloff), with 3 layered artifacts: RGB tear (`efxChroma`, up to 14 px), horizontal block displacement (`efxBlockOffset`, 8–48 px rows), 2-frame color-invert flickers at `Proximity > 0.85`. Nether variant: same renderer, palette swap uniform `Seed` offset + red-shifted tint constant (nether ring geometry comes from P1; the renderer reads the ring radius that already syncs via `S2CBorderPayload` for `DiscProfile.NETHER`). Acceptance: standing 10 blocks away and strafing, the effect stays glued around the border direction and NEVER shows as a full-height wall stripe.

**R7 — Supply drops: perf + lifecycle + real beam**
W5 owns. (a) **Perf**: `altar_beam.json` loses its `veil:light` module (replaced by ONE `FxBudget.tryLight` point light in the client beam renderer); server stops sending END_ROD columns entirely. (b) **Protocol**: `drop()` sends `S2CSupplyMarkerPayload(add=true, pos)` to dimension players (1 packet), login sync re-sends active markers (list kept server-side as today); expiry/loot sends `add=false, fadeTicks=40`. (c) **Lifecycle**: marker record gains the landed-barrel detection: each second, if the crate has landed (`FallingBlockEntity` gone) the marker binds to the barrel `BlockPos`; from then on `level.getBlockState(pos).is(Blocks.BARREL) == false` **or** first `PlayerInteractEvent.RightClickBlock` on that pos → remove + broadcast remove. (d) **Beam visual** (`veilfx/SupplyBeamClient` + `SupplyBeamRenderer`): world-space **two-plane crossed additive beam** (4 quads core + 4 quads outer haze, 64 blocks tall, widths 0.35/1.1), scrolling procedural noise alpha (shader-less: vertex-color pulses + `border_glitch.png` scroll), base **impact glow disc** + 1 pulsing Veil point light (radius 12, brightness 0.9±0.15, purple), `supply_spark` landing burst (count 12/rate 1/life 2). Distance LOD: beyond 192 blocks only the 4 core quads. Acceptance: 5 simultaneous drops cause no visible hitch (was: freeze), beam vanishes ≤ 2 s after looting.

**R8 — WaveOverlay replacement (event-start shockwave)**
W5 owns `client/WaveOverlay.java` (class name + `LAYER_ID` + `render(GuiGraphics, DeltaTracker)` signature + audio-muffle/crash-restore machinery kept; internals replaced): phases now drive (a) `eclipse:shockwave` post — expanding refractive ring: `uv' = uv + dir · sin((d − ShockProgress·R)·π·6) · falloff · ShockStrength` + chroma on the ring front + 8% desat inside the ring; `ShockCenter` = screen center for the submerge (fullscreen immersion), or projected world origin for world shockwaves (`EclipseFxState.startShockwave`); (b) a slim underwater tint fill (kept from today but 40% previous alpha). The same pipeline is reused by intro v3's storm burst and expansion slams (`S2CFxEventPayload eclipse:fx/shockwave`).

**R9 — Altar chromatic aberration zone**
W4 owns. `client/AltarAberration.java` (client tick): reads altar center (`FxAnchors eclipse:altar_center`, fallback world spawn) + spawn-area radius from `ClientStateCache` border data; `Aberration = clamp(1 − dist/zoneRadius, 0, 1)^2 · 0.85`, eased 10 ticks. Pipeline `eclipse:altar_aberration`: radial RGB split from screen center (max 10 px at center of zone), subtle 0.3 Hz breathing, plus 1% barrel distortion at `Aberration > 0.6` — "not normal", not nauseating. Mutually throttled with `border_glitch` (both FEATURE priority; controller keeps the stronger one when over budget).

**R10 — INTRO SEQUENCE v3** (full redesign; W6 owns orchestration; consumes W2 engine, W9 vortex, W1 eclipse state)
Server `sequence/IntroSequence.java` phases (all tick counts frozen; P4 triggers `IntroSequence.start(server)` after per-player disc teleports, §6.3):
1. `ECLIPSE_ON` (t=0): `S2CEclipsePhasePayload(TOTAL, 1.0, ramp 100)`; `eclipse.caption.intro.awaken` TITLE caption.
2. `FLIGHT` (t=100..1000): global cutscene `cutscenes/intro_v3_flight.json` via `CutsceneService.play(..., GLOBAL_TELEPORT)` — a 45 s crane path: start high above the player-disc ring, slow descending orbit showing discs + connecting bridges growing toward center (terrain fusion itself is P1/P4 servelogic; the camera just frames it), ends 60 blocks from center at 12 blocks altitude. At t=300 `StormFxClient` vortex spawns via `S2CStormStatePayload(VORTEX, center, r=22, h=48, SPAWN, 80)`; at t=500 the server places the altar structure **inside** the vortex (P4/P1 call, hidden — vortex is opaque by design §R14); at t=960 `S2CScreenFadePayload(20, 15, 25, 0xFF000000)`; t=1000 cutscene ends, control returns.
3. `APPROACH` (untimed): watcher on player distance to vortex shell; first player within **5 blocks** → `LIGHTNING`.
4. `LIGHTNING` (t=0..600): scheduled strikes from the eclipse onto the vortex top: visual = W9 `StormFxClient.strikeLightning(from = center + SunTracker dir·180, to = vortex top, intensity)`; audio `event.lightning_close`; strike times: t=0 (intensity 0.5, giant sound), then intervals 100→70→45→25→15 ramping intensity 0.4→1.0, purple tint rising; each strike near players ⇒ P2 applies the kickback impulse (radial from vortex, `0.8` horizontal + `0.25` Y, `hurtMarked=true` — the proven `risePlayerAt` pattern); P4's edge-protection guarantees nobody leaves the disc (§6.3). At t=600 the **GIANT** strike: `intensity 1, b=1`, `eclipse:fx/shockwave` (strength 1, 50 ticks), vortex `DISSIPATE 60`, screen flash white→violet 8 ticks (CaptionRenderer fade).
5. `REVEAL` (t=600..900): cutscene `cutscenes/intro_v3_reveal.json` — 15 s slow 270° orbit of the now-visible **floating altar island** (P1/P4 placed it hovering 10–20 blocks above the disc with the ripped hole below); server spawns decor via `sequence/FloatingDecor.java`: **28 block displays** (deepslate/obsidian/amethyst mix, scales 0.3–1.6), persistent tag `eclipse:intro_decor`, server-tick animated: rotation 0.2–1.0 °/tick around random axes, bob amplitude 0.05–0.25 blocks, periods 80–200 ticks (batch: one `Display` transform update per entity per 4 ticks, interpolation duration 4 — smooth at 1/4 rate).
6. `SUNRISE` (t=900..1100): `S2CEclipsePhasePayload(ENDING, 0, ramp 200, permanentRim=true)` — world brightens, `OverworldPurpleEffects` keeps a **permanent purple rim** on the sun forever after (`EclipseFxState.permanentSunRim` → rim pass in the sun quad + faint halo floor `HaloStrength ≥ 0.15`). Final caption `eclipse.caption.intro.begin`.
Auto-glide FX (motion/protection = P4): on `eclipse:fx/glide_start|stop`, client attaches `glide_trail` emitter (loop, rate 2/count 1, ribbon-ish wisps) + FOV +5 ease + soft wind loop; ends on stop.

**R11 — MAP EXPANSION SEQUENCE v2** (W7 owns; consumes W1 grade, W2 engine, W8 rift, P1 hooks)
Server `sequence/ExpansionSequence.java`, triggered by the stage-commit path that currently drives `UnlockCinematics` (which W7 **replaces**; file deleted, logic absorbed):
1. `SKYWARD` (t=0..80): global cutscene `expansion_skyward.json` (camera tilts up from the player's own position — `anchor=player`, 4 s); `EclipseAmount` ramps 0→1 over 60 ticks (`BUILDUP`); `event.eclipse_drone` starts.
2. `FLYOVER` (t=80..380): `expansion_flyover.json` with **runtime anchor substitution** (W2 engine feature: `params.dynamicAnchor = "growth_front"` — server fills the nearest point of the new ring band before sending): camera sweeps along the growth front at 25 blocks altitude.
3. `GROWTH` (t=120..sweep end): P1's `RingGrowthService` runs its sweep; FX upgrades (client, driven by existing `MAP_EXPAND_MATERIALIZE` payloads + new batching, §6.1): `map_expand_materialize` v2 (no light module, sprites 2×, count 4→6), NEW `growth_dust_wall` curtain emitter (count 10/rate 1/life 20, 12-block tall dust sheets along the front), continuous low rumble + `S2CShakePayload` amplitude by distance (0.15 within 40 blocks). The cutscene shows the first ~13 s, then control returns while growth continues (caption `eclipse.caption.expansion.growing`).
4. `STRUCTURES` (after P1 terrain-done callback, per structure): **rift drop** — `S2CFxEventPayload rift_open (width = structure diagonal · 1.2, style 0)` at the build site (W8 renders the tear + `eclipse:rift_glitch` pulse ≤ 0.5), 40-tick hold, then P1 applies the structure blocks in one paste while W7 triggers `structure_slam_dust` burst (count 16/rate 1/life 2) + `shockwave (0.5, 30)` + `event.rift_slam` + shake 0.4; rift closes 30 ticks. Block-display "pre-crash" animation was evaluated and **rejected** for v3 scope: a full ghost copy of a structure needs 1 display/block (hundreds of entities per structure) — the rift+slam+dust reading delivers the same beat at 1% of the cost (documented fallback if P1's two-phase hook slips: pure FX at paste time, no hold).
5. `END`: `EclipseAmount → 0` over 100 ticks; unfreeze/returns (W2); chat unlock list (P4/P3); P3's roulette overlay may start (we provide `unlock_burst` + new `roulette_flare` emitter: count 8/rate 2/life 6, lens-flare streak sprites, id frozen for P3: `eclipse:quasar/emitters/roulette_flare`).

**R12 — Cutscene engine rework** (W2 owns)
- **Paths**: arc-length reparameterized Catmull-Rom (precomputed 64-sample LUT per segment at path load → constant travel speed), optional `lookAt` per keyframe (`[x,y,z]` or `"anchor:<id>"` or `"player"`) with slerped smoothing (max 90°/s), roll/FOV kept, 2-octave Perlin shake (amp/freq per event), **dynamic anchors** (`params.dynamicAnchor` substituted server-side at play time — used by W7).
- **Captions**: fix per §1.7 (whitelist announcement layer) AND new `CaptionRenderer` (client, drawn inside `LetterboxLayer` render — immune to HUD suppression): 3 styles — SUBTITLE (lower third above the bar: 0.9-scale text, 140-alpha black gradient backing, 4-tick fade in/out, typewriter at 2 chars/tick with `ui.caption_tick`), TITLE (center, 2.0 scale, letter-spaced fade+track-in over 20 ticks), WHISPER (small italic, 60% alpha, jitter ±0.5 px). `S2CCaptionPayload` + `S2CScreenFadePayload` (also usable outside cutscenes). All caption strings en+de via langdrop.
- **Global cutscenes**: `CutsceneService.play(paths, players, PlayOptions)` with `PlayOptions{ TeleportPolicy (LOCAL_ONLY | GLOBAL_TELEPORT), viewDistance (chunks, 0=skip), returnAfter (bool) }`. GLOBAL_TELEPORT: snapshot each far/other-dimension player (pos, dim, vehicle dismount), teleport to the sequence area behind the fade (FreezeService already grants invuln; nether players included), restore exactly afterwards (fail-safe: restore also runs on ACK timeout/disconnect via the existing watchdog).
- **View distance**: `cutscene/ViewDistanceService.java` — server temporarily raises `PlayerList.setViewDistance(min(12, current+4))` for the session and sends `S2CViewDistancePayload(chunks)`; client (`ViewDistanceClient`) raises `options.renderDistance` for the duration **iff** `EclipseClientConfig.cinematicViewDistance()` (default ON, the player toggle the boss asked for), restores on end/timeout/logout (marker-file crash restore mirroring WaveOverlay's volume pattern).
- **Replay/revert**: every sequence exposes `replay(server, phaseId, players)` running in **FX-only mode** (no world mutations, no state commits); W2 defines the `SequenceReplayable` interface; dev commands below.
- **Recomposition of existing cutscenes**: `finale_return.json` reshot (arc-length + lookAt + captions); intro/unlock JSONs are replaced wholesale by W6/W7.
- **Dev commands** (`cutscene/dev/FxDevCommands.java`, permission 3, all under `/eclipsefx`): `post <id> on|off|list`, `uniform <pipeline> <name> <float>`, `emitter <id> [x y z]`, `cutscene play|stop|preview <id>` (preview = particle-traced path), `sequence intro <phase>|expansion <phase>`, `storm add|remove|bolt`, `rift <x y z> <width>`, `supplybeam test`, `sun debug` (HUD cross at `SunScreen` vs disc), `viewdist <n|reset>`, `caption <style> <key>`. These are the replay hooks P5 surfaces (§6.4).

**R13 — Custom loading/transition experience** (assets by W8; screens by P3)
W8 ships: (a) `eclipse:rift_glitch` pipeline — `GlitchAmount` (block displacement + chroma + 2-frame invert pops via `eclipse_common.glsl`) and `FadeAmount` (fade-to-black with violet edge bleed); (b) client API `veilfx/TransitionFx.java`:
```java
public final class TransitionFx {
    public static void playPortalEnter(int ticks);   // glitch↑ then fade→1  (screen goes black)
    public static void playPortalExit(int ticks);    // fade→0 with glitch tail-off
    public static void setLoadingPulse(float p01);   // P3's replacement screen drives a slow pulse while "receiving level"
}
```
(c) uniform contract documented for P3's screen (they render GUI; our pipeline supplies the world-side glitch); (d) the xbox-portal entry flow: entity contact (P5) → `TransitionFx.playPortalEnter(18)` → dimension change happens behind black → P3's eclipse-styled screen (never vanilla; P3 owns the `ReceivingLevelScreen` replacement) → `playPortalExit(24)` at destination. Limbo→overworld intro teleport reuses the same pair (W6 calls it at `FLIGHT` fade).

**R14 — Fog storm areas** (W9 owns visuals + reveal; placement by P1)
`stormfx/` package. **Geometry** (`StormWallRenderer`, `VeilRenderLevelStageEvent` or NeoForge `AFTER_PARTICLES` stage, camera-relative): per storm, concentric **cylinder shells** — near LOD (< 160 blocks): 4 shells (r, r−2, r−4, r+2) × ≤ 96 segments × height h, scrolling procedural noise alpha (two scroll speeds, vertex-gray noise via per-vertex hash — no texture), additive outer + alpha-blended inner; **an opaque unlit near-black occluder cylinder** at r−5 guarantees you can NEVER see inside from outside; top: swirl cone cap (vortex type) or ragged dome ring (wall type). Far LOD (160–320): 2 shells, 48 segments, no arcs; > 320: single billboard impostor ring (8 quads). **Interior**: `eclipse:storm_interior` pipeline (`Interior=1` inside: fog crush + desat + rain streak overlay `RainAmount`) + `ViewportEvent.RenderFog` subscription clamping fog end to 24 blocks inside (no mixin needed) + `storm_rain_sheet` emitter (loop, sheets, rate 4/count 2). **Lightning arcs**: `strikeLightning(from,to,intensity)` renders a 3-segment jittered ribbon bolt (8–14 quads, 2-tick white core + 6-tick violet decay, one budgeted point light at impact) + shell-surface arc flashes every 20–60 ticks per storm. **Vortex type** (used by intro v3): shells get tangential scroll (swirl 0.35 rad/s), inward tilt 8°, `vortex_wisp` emitter (force module `veil:vortex`, loop, rate 3/count 2) spiraling. **Reveal sequence** (server `stormfx/StormReveal.java`, invoked by P1's two-phase area apply, §6.1): terrain loads under the already-opaque storm → 40-tick pause → `rift_glitch` pulse 0.4 → 5 hammer strikes over 60 ticks → storm `SPAWN` ramps 80 ticks (shells fade/scale in) → callback to P1 `finishLoading()` → area interior finalizes invisible to outside observers. Sound: `event.storm_loop` (positional, 64-block falloff) + strike sounds.

**R15 — Spawn smoke/storm vortex** = the VORTEX storm type above (W9 tech), driven by W6's intro timeline. Decision: **layered scrolling shells + Quasar vortex wisps + interior occluder**, NOT a post-process fog sphere (post would vanish under Iris and can't hide the altar; geometry survives every config) and NOT pure Quasar volumetrics (fill-rate death at 22-block radius).

**R16 — Global eclipse shader during expansions** = `eclipse:world_grade`'s `EclipseAmount` path (W1) driven by `S2CEclipsePhasePayload` from W7's sequence (§R11) — screen grade shift + light crush, not just the sky sprite. The sky sprite ALSO grows (R1) via the same state.

**R17 — Xbox-360 tutorial-world event portal VFX** (W8 owns; event/dimension by P5)
`RiftFx.openRift(pos, normal, width, durationTicks, style=PORTAL)`: jagged **tear mesh** — star polygon, 8–14 arms, seeded per rift, arm length ease-out over 20 ticks, additive white-violet core + dark edge fringe + `rift_spark` edge crackle emitter (loop while open, rate 3/count 2); PORTAL style adds a persistent **elliptical portal surface**: 2 stacked quads with counter-scrolling procedural distortion + parallax depth fake (inner quad scaled 0.85, offset by view dir · 0.4 — cheap fake depth) + `portal_surface_motes` (loop, rate 4/count 1, sucked inward via reverse `veil:vortex`). Entry: `TransitionFx.playPortalEnter` (R13). Optional stretch (config-off, risk-flagged §7): `VeilLevelPerspectiveRenderer` destination-preview in the surface.

**R18 — Death/respawn-on-ship supporting FX** (W10 owns; UI/flow P3, door P6)
(a) `heart_burst` v2: count 6→14 across two sub-emitters (shard sprites with gravity+drag arcs, spark pops), `HeartBurstOverlay` shards get rotation + gravity arcs over 600 ms (overlay file owned by W10). (b) **Ship-door purple glow**: on `eclipse:fx/door_glow(on)` at `FxAnchors eclipse:ship_door`: one budgeted point light (radius 6, brightness pulsing 0.8–1.2 at 0.5 Hz, violet) + `door_glow_motes` loop emitter (rate 6/count 1, drifting upward, ≤ 12 live) — P6 fires the event on door state change (§6.5). (c) **Ghost grade** for 0-lives players: `S2CGhostStatePayload` (P3's death flow sends it) → `eclipse:ghost_grade` (GRADE): desat 70%, cold blue-violet lift, 12% vignette, 1.5 px chroma, subtle 0.2 Hz breathing; eases in/out 30 ticks. Iris fallback: none (grade-only, acceptable).

---

## 5. WORKER PACKAGES (W1–W10)

Rules recap: exact file ownership (create = C, modify = M, delete = D); no file appears in two packages; frozen APIs from §3; langdrop file per package; all sizes are S/M/L; **model: FABLE** for every package (all are visual/timing-critical; if a maintainer later splits the mechanical halves of W1/W5, those halves may go to SOL).

### W1 — FX core, sun truth, global grades, sky scale-up — **FABLE, L**
**Goal:** the shared FX backbone (§3.1–§3.4) + R1(sky)/R2/R3/R4(overworld)/R16 pipelines.
**Files:** C `veilfx/EclipseFxState.java`, C `veilfx/FxBudget.java`, C `veilfx/SunTracker.java`, C `veilfx/FxAnchors.java`, C `network/fx/FxPayloads.java` (+ the 9 payload records in `network/fx/`), M `veilfx/VeilPostController.java` (registry rewrite), M `veilfx/QuasarSpawner.java` (FxBudget hook), M `client/sky/OverworldPurpleEffects.java` (90-unit eclipse sun + coronas + permanent rim + cloud kill + SunTracker source), M `client/sky/EclipseIrisState.java` (per-priority gate helper), M `registry/EclipseSounds.java` + M `assets/eclipse/sounds.json` (all §3.5 events, mapped to existing oggs), M `core/config/EclipseClientConfig.java` (`cinematicViewDistance`), C `assets/eclipse/pinwheel/post/world_grade.json` + `shaders/program/world_grade.fsh/.json`, M `.../post/sun_halo.json` + `program/sun_halo.fsh/.json` (screen-space rewrite), C `.../shaders/include/eclipse_common.glsl`, C `docs/plans_v3/langdrop/P2W1.json`.
**Outline:** implement §3 verbatim → SunTracker event feed → sun_halo rewrite → world_grade → sky scale-up + permanent rim flag → budget plumbing → payload registrar with dispatch stubs calling the frozen client entry points (compile-safe: entry points of other packages are referenced; integration builds once all packages land — until then guard with try/NoClassDefFound is NOT needed since workers merge together).
**Acceptance (visual):** sun debug command shows halo center ≤ 0.5° off the disc while sprint-strafing with bobbing ON; night scene visibly dark at gamma 100%; eclipse ramp (dev: `/eclipsefx post eclipse:world_grade on` + phase payload) crushes the world convincingly; zero clouds; eclipse sun with coronas ≥ 3× vanilla sun visual diameter; no new allocations per frame (spark profiler or allocation logging spot check).

### W2 — Cutscene engine v2: paths, captions, global teleport, view distance, replay, dev commands — **FABLE, L**
**Goal:** R12 complete + caption/fade primitives used by every sequence.
**Files:** M `cutscene/CutscenePath.java` (lookAt, dynamicAnchor, caption events), M `cutscene/CutscenePaths.java`, M `cutscene/CutsceneService.java` (PlayOptions/GLOBAL_TELEPORT/return snapshots), M `cutscene/FreezeService.java` (return-transport helpers), M `cutscene/client/CameraDirector.java` (arc-length LUT, lookAt slerp, 2-octave shake), M `cutscene/client/LetterboxLayer.java` (whitelist fix + caption hosting), M `client/EclipseGuiLayers.java` (whitelist + caption layer registration), C `cutscene/client/CaptionRenderer.java`, C `cutscene/ViewDistanceService.java`, C `cutscene/client/ViewDistanceClient.java`, C `cutscene/SequenceReplayable.java`, C `cutscene/dev/FxDevCommands.java`, M `assets/eclipse/cutscenes/finale_return.json` (reshoot), C `docs/plans_v3/langdrop/P2W2.json`.
**Outline:** path math first (LUT at load), captions (3 styles, §R12), payload handlers (`S2CCaption/ScreenFade/ViewDistance` entry points), global-play snapshot/restore with watchdog-integrated failsafes, dev command tree.
**Acceptance (visual):** `/eclipsefx cutscene play finale_return` — constant camera speed (no pumping), captions readable and beautiful in en+de at GUI scale 2 and 4, letterbox + captions coexist; a player parked in the nether gets teleported behind a fade, sees the cutscene with bumped view distance, and is returned to the exact block+vehicle-free state; kill -9 the client mid-cutscene → next launch restores render distance.

### W3 — Limbo overhaul — **FABLE, M**
**Goal:** R5 + R4(limbo).
**Files:** M `client/sky/LimboSpecialEffects.java` (zenith disc 1.5×, 12-ray aura fan, cloud kill), M `veilfx/LimboAmbience.java` (godray/fog emitters, denser motes, budget channels), M `assets/eclipse/pinwheel/post/limbo.json` + `program/limbo.fsh/.json` (godrays + caustics + grade v2), C `assets/eclipse/quasar/emitters/limbo_godray.json`, C `.../limbo_fog.json`, M `.../limbo_motes.json`, C `docs/plans_v3/langdrop/P2W3.json` (empty allowed if no strings).
**Acceptance (visual):** from the ship deck, looking up: eclipse exactly overhead with radiating aura; looking down: purple caustic shimmer on the water; god-ray shafts drift by; radial god-ray post intensifies when looking up; total limbo emitter budget within AMBIENT channel; Iris shaderpack on → sky/emitters still present, post grade absent, no log spam.

### W4 — Border v2 + altar aberration — **FABLE, L**
**Goal:** R6 + R9.
**Files:** M `border/client/BorderFxRenderer.java` (patches replace strip; GlitchDir feed; nether palette), M `assets/eclipse/pinwheel/post/border_glitch.json` + `program/border_glitch.fsh/.json` (localized v2), C `.../post/altar_aberration.json` + `program/altar_aberration.fsh/.json`, C `client/AltarAberration.java`, C `assets/eclipse/quasar/emitters/border_shard.json`, M `.../emitters/border_glitch.json` (stronger burst), C `docs/plans_v3/langdrop/P2W4.json`.
**Acceptance (visual):** approach the border: glitch patches pop/reseed around the border bearing only (never a full wall stripe), post tearing/datamosh clearly reads at 5 blocks and is violent at 1 block; nether ring shows the red-shifted variant; walking from spawn-zone edge to altar, aberration ramps smoothly subtle→strong; both effects respect the 3-pipeline cap (verified with `/eclipsefx post list` during a storm).

### W5 — Supply beam + shockwave (WaveOverlay v2) — **FABLE, M**
**Goal:** R7 + R8.
**Files:** M `economy/SupplyBeacon.java` (payload protocol, loot/break lifecycle, no END_ROD flood), C `veilfx/SupplyBeamClient.java`, C `veilfx/SupplyBeamRenderer.java`, M `assets/eclipse/quasar/emitters/altar_beam.json` (light module removed, visual-only), C `.../emitters/supply_spark.json`, M `client/WaveOverlay.java` (drives `eclipse:shockwave`; audio machinery kept), C `assets/eclipse/pinwheel/post/shockwave.json` + `program/shockwave.fsh/.json`, C `docs/plans_v3/langdrop/P2W5.json`.
**Acceptance (visual):** drop 5 crates in a row (`/eclipse` economy or dev spawn): no frame hitch (before: freeze), each shows a tall pulsing violet beam visible from 200+ blocks, ONE dynamic light each; loot one barrel → its beam fades within 2 s, others stay; break one → same; relog → beams resync. Event-start submerge now shows the refractive shockwave rings instead of the flat tile texture; audio muffle + crash-restore still work (kill client mid-phase → volumes restored on next boot).

### W6 — Intro sequence v3 — **FABLE, L**
**Goal:** R10 end-to-end orchestration + auto-glide FX; replaces the submerge story where it conflicts.
**Files:** C `sequence/IntroSequence.java`, C `sequence/IntroLightningPhase.java`, C `sequence/FloatingDecor.java`, M `limbo/StartEventCutscene.java` (delegates to IntroSequence; keeps limbo-side tilt/teleport phases + WaveOverlay phase broadcasts), C `assets/eclipse/cutscenes/intro_v3_flight.json`, C `.../intro_v3_reveal.json`, D `assets/eclipse/cutscenes/intro_submerge.json`, D `.../intro_rise.json` (superseded; StartEventCutscene stops referencing them), M `assets/eclipse/quasar/emitters/cutscene_veil.json` (bigger), C `.../emitters/eclipse_lightning_impact.json`, C `.../emitters/impact_light.json` (1-particle light carrier), C `.../emitters/altar_reveal_burst.json`, C `.../emitters/glide_trail.json`, C `docs/plans_v3/langdrop/P2W6.json` (all intro captions en+de).
**Outline:** phase machine per R10 (frozen tick table), `SequenceReplayable` FX-only replays per phase, decor spawn/cleanup idempotent by tag (`/kill @e[tag=eclipse:intro_decor]`-safe), kickback impulses, proximity watcher, `TransitionFx` at the limbo→overworld hop.
**Acceptance (visual):** full run on a dev world with 2+ clients: flight frames the discs + vortex; fade; walk to storm → first-contact GIANT bolt + kickback (never off the disc — P4 protection assumed present, test with it); strikes ramp; burst → shockwave → reveal orbit shows floating island with rotating/bobbing displays; eclipse ends; sun keeps purple rim after relog (state persisted server-side by P4 world flag, §6.3). Every phase replayable: `/eclipsefx sequence intro LIGHTNING` re-fires FX without world edits.

### W7 — Map expansion sequence v2 + growth/structure FX — **FABLE, L**
**Goal:** R11 (+R16 trigger side); replaces `UnlockCinematics`.
**Files:** C `sequence/ExpansionSequence.java`, D `cutscene/UnlockCinematics.java` (absorbed), M `assets/eclipse/cutscenes/unlock_ring.json` → repurposed as `expansion` fallback shot (file stays, reshot), C `assets/eclipse/cutscenes/expansion_skyward.json`, C `.../expansion_flyover.json`, M `assets/eclipse/quasar/emitters/map_expand_materialize.json` (no light, bigger), C `.../emitters/growth_dust_wall.json`, C `.../emitters/structure_slam_dust.json`, C `.../emitters/roulette_flare.json` (P3 consumes), C `docs/plans_v3/langdrop/P2W7.json`.
**Outline:** subscribe the same stage-commit entry `UnlockCinematics` used; timeline per R11; structure rift beats via `RiftFx` + P1 two-phase callback (§6.1; degrade gracefully to paste-time FX if the hook isn't merged yet); eclipse ramps via `S2CEclipsePhasePayload`.
**Acceptance (visual):** trigger a stage commit on a dev world: camera up → global eclipse grade; flyover tracks the front; dust-wall curtain + shake + rumble along growth; each structure arrives via rift tear + slam + dust + shockwave; grade releases; nether player saw everything (W2 policy) and got returned; `/eclipsefx sequence expansion STRUCTURES` replays FX only.

### W8 — Rift & portal tech + transition assets — **FABLE, M**
**Goal:** R13 + R17 + the rift renderer W7/W9 consume.
**Files:** C `veilfx/rift/RiftFx.java` (frozen API: `openRift(pos, normal, width, ticks, style)`, `closeRift(...)`; handles `eclipse:fx/rift_open|close`), C `veilfx/rift/RiftRenderer.java`, C `veilfx/TransitionFx.java`, C `assets/eclipse/pinwheel/post/rift_glitch.json` + `program/rift_glitch.fsh/.json`, C `assets/eclipse/quasar/emitters/rift_spark.json`, C `.../emitters/portal_surface_motes.json`, C `docs/plans_v3/langdrop/P2W8.json`.
**Acceptance (visual):** `/eclipsefx rift ~ ~1 ~ 6` — jagged tear opens with edge crackle + screen glitch pulse, closes cleanly; PORTAL style shows the parallax surface + inward motes; `TransitionFx.playPortalEnter/Exit` produce the glitch→black→glitch-out arc with no vanilla screen visible in between (paired with P3's screen; standalone test via dev command acceptable); pipeline respects TRANSITION priority (evicts a FEATURE pass when needed, restores after).

### W9 — Storm walls & vortex system — **FABLE, L**
**Goal:** R14 + R15 tech; intro vortex + 2-3 placed fog storms.
**Files:** C `stormfx/StormFxClient.java` (frozen: `handle(S2CStormStatePayload)`, `strikeLightning(Vec3 from, Vec3 to, float intensity)`), C `stormfx/StormWallRenderer.java`, C `stormfx/StormInteriorFx.java` (fog event + post feed), C `stormfx/StormReveal.java` (server; P1 callback contract §6.1), C `stormfx/StormRegistry.java` (server state + login resync), C `assets/eclipse/pinwheel/post/storm_interior.json` + `program/storm_interior.fsh/.json`, C `assets/eclipse/quasar/emitters/storm_arc.json`, C `.../emitters/storm_rain_sheet.json`, C `.../emitters/vortex_wisp.json`, C `docs/plans_v3/langdrop/P2W9.json`.
**Acceptance (visual):** `/eclipsefx storm add 0 100 0 24 48 wall` — from outside: churning opaque storm wall with periodic arcs, NOTHING inside visible from any angle/height; enter: fog clamps to ~24 blocks, rain sheets, interior grade; walk 200/340 blocks away → shell count/LOD steps down with no pop harsher than a 10-tick fade; vortex type swirls with spiraling wisps; `strikeLightning` bolt reads violently at 100+ blocks; 3 storms + border + a cutscene stay within budgets (frame time spot check vs. baseline).

### W10 — Death/respawn & ship FX — **FABLE, S**
**Goal:** R18.
**Files:** M `client/hud/HeartBurstOverlay.java` (shard arcs), M `assets/eclipse/quasar/emitters/heart_burst.json` (v2), C `assets/eclipse/quasar/emitters/door_glow_motes.json`, C `client/ShipDoorGlow.java` (anchor light + motes on `door_glow` events), C `assets/eclipse/pinwheel/post/ghost_grade.json` + `program/ghost_grade.fsh/.json`, C `client/GhostGradeFx.java` (state feed), C `docs/plans_v3/langdrop/P2W10.json`.
**Acceptance (visual):** losing a heart: 14-shard burst with arcs + sparks; ghost state (dev: send payload) fades the world cold/desaturated within 1.5 s and releases on revive; door anchor set + `door_glow on` → pulsing purple light + motes at the door, exactly one FX light claimed, released on off.

---

## 6. INTERFACES (what P2 needs from / provides to the other planners)

### 6.1 P1 (worldgen, growth pacing, two-phase apply)
- **Needs from P1** (hook signatures P1 should plan; P2 degrades gracefully without them):
  - `RingGrowthService` FX hooks: `onSweepStarted(profile, fromStage, toStage, estTicks)`, `onColumnsApplied(ServerLevel, long[] packedXZ)` batched ≤ 64, `onSweepFinished(profile)` — W7 subscribes for curtain/shake pacing (today's 5-tick `MAP_EXPAND_MATERIALIZE` payload stream is the fallback).
  - **Two-phase structure apply**: terrain-done callback + per-structure `(structureId, BoundingBox, Runnable applyNow)` handed to `ExpansionSequence` so W7 can rift-then-apply (fallback: FX at paste time).
  - **Storm-area two-phase**: P1 calls `StormReveal.request(areaId, center, radius, height, Runnable finishLoading)` after terrain load; P2 runs the reveal and invokes `finishLoading` (fallback: P1 applies immediately and P2 plays the reveal cosmetically).
  - Nether border ring geometry (already synced via `S2CBorderPayload`) — nothing new needed.
- **Provides to P1**: nothing at runtime; visual pacing constants documented in W7 (sweep looks best ≥ 45 s, ≤ 120 s).

### 6.2 P3 (screens/overlays)
- P3 sends `S2CGhostStatePayload` from the death/respawn flow (or calls the server helper W1 exposes on `FxPayloads`).
- P3's dimension-change screen replacement calls `TransitionFx.setLoadingPulse(p)` and relies on `playPortalEnter/Exit`; the vanilla `ReceivingLevelScreen` suppression itself is P3's.
- Caption layer id `eclipse:cutscene_captions` and the whitelist policy live in W2's `EclipseGuiLayers` — P3 must NOT add another whitelist edit; new P3 overlays that must show during cutscenes get registered through the same list (coordinate key names, file owned by W2 until merge, then P3 may extend).
- Roulette FX assets provided: `eclipse:quasar/emitters/roulette_flare` + existing `unlock_burst`.

### 6.3 P4 (event triggers, protection, per-player discs)
- P4 calls `IntroSequence.start(server)` after per-player disc teleports; provides `Map<UUID, BlockPos> discCenters` (frozen param) for camera framing.
- P4 owns edge/auto-glide protection + the "never off the disc" guarantee; P2 sends `eclipse:fx/glide_start|stop` visuals when P4 flags glide state (P4 fires the `S2CFxEventPayload` or calls the server helper).
- Permanent-sun-rim persistence: P4's world state stores the post-intro flag and re-sends `S2CEclipsePhasePayload(permanentRim=true)` at login.
- Kickback: P2 applies impulses during `LIGHTNING`; P4's protection must tolerate them.
- Altar anchor: P4 (or P6) sets `FxAnchors eclipse:altar_center` when the altar is placed.

### 6.4 P5 (dev commands, xbox event)
- All replay/testing surface is `/eclipsefx ...` (W2). P5's `/eclipse dev` tree may alias these; P5 must NOT re-implement.
- Xbox portal: P5's event code calls `RiftFx.openRift(..., PORTAL)` + `TransitionFx.playPortalEnter` on entry; P2 provides no dimension logic.

### 6.5 P6 (ship/altar)
- P6 sets `FxAnchors eclipse:ship_door` / `eclipse:ship_deck` (+ altar if P4 doesn't) and fires `eclipse:fx/door_glow` on door state changes.
- Ship-respawn FX beats (heart burst, ghost grade) trigger from P3/P4 flows; P6 only guarantees the anchors exist.

---

## 7. RISKS & FALLBACKS

| # | Risk | Likelihood | Mitigation / fallback (frozen) |
|---|---|---|---|
| 1 | **Iris shaderpack active → entire post stack off** (existing hard gate) | Certain for shader users | Every requirement keeps a world-space component that still renders: sky quads (R1/R2 sun+rim), storm shells/occluder (R14/15 — opacity does NOT depend on post), beam (R7), rifts (R17), captions/letterbox (GUI). Grades/aberration/shockwave/god-rays simply absent. Documented per-feature in each worker's javadoc; NO attempt to run Veil post under Iris. |
| 2 | Sodium translucency/depth ordering artifacts on world-space additive meshes | Medium | The proven constant swap: render at `AFTER_TRANSLUCENT_BLOCKS` instead of `AFTER_PARTICLES` (same matrices; comment in `BorderFxRenderer` already documents it). Each renderer keeps the stage in one constant. |
| 3 | Veil light renderer cost explosion (the §1.5 trap re-introduced) | Medium | `FxBudget.tryLight` cap 16 + emitter JSON review rule (`veil:light` only on ≤ 8-particle emitters); acceptance criteria include light counts. |
| 4 | Fullscreen pass stacking (grade+feature+transition+storm simultaneously) | High during sequences | Priority eviction in `VeilPostController` (≤ 3); GRADE passes are algebraically mergeable later (stretch: single composite pipeline) — not needed for v3. |
| 5 | `CameraMatrices`/Veil camera block changes in a future Veil update re-breaking sun math | Low | Sun path no longer depends on `veil:camera` at all (CPU `SunScreen` uniform) — immune by design. |
| 6 | Server view-distance bump memory/CPU spike on big maps | Medium | Cap at 12 chunks, bump only for GLOBAL_TELEPORT sessions, restore via watchdog + login failsafe; client-side raise is behind the player toggle (default ON). |
| 7 | Block-display decor entity cost (intro island) | Low | Hard cap 28 displays, transform updates at 1/4 tick rate with interpolation, tag-based idempotent cleanup, removed entirely at `reducedFx` tier 0 (static displays). |
| 8 | Storm shell overdraw on iGPUs | Medium | LOD tiers frozen (4/2/impostor shells at 160/320 blocks), `reducedFx` forces far LOD everywhere, segments 96→48. |
| 9 | Replay commands mutating world state | Medium | `SequenceReplayable` contract: replays are FX-only (no block writes, no state commits, no teleports unless `--with-players` flag); enforced in code review via the interface's single entry point. |
| 10 | P1 two-phase hooks not landing in time | Medium | W7/W9 degrade: FX at paste time, cosmetic reveal (explicitly coded fallback paths, not TODOs). |
| 11 | Photon temptation | — | Verdict §2: not adopted; revisit only post-v3. |
| 12 | New payload registrar conflicting with `EclipsePayloads` ids | Low | All new payload ids prefixed `eclipse:fx/...`; registrar registers under its own version group. |
| 13 | Caption/letterbox regressions for non-cutscene announcements | Low | Whitelist change only ADDS ids; AnnouncementOverlay behavior outside cutscenes untouched; W2 acceptance includes a non-cutscene announcement smoke test. |

---

## 8. APPENDICES

### 8.1 File-ownership matrix (authoritative; C=create, M=modify, D=delete)

| File | Owner |
|---|---|
| `veilfx/EclipseFxState.java` C, `veilfx/FxBudget.java` C, `veilfx/SunTracker.java` C, `veilfx/FxAnchors.java` C, `network/fx/*` C, `veilfx/VeilPostController.java` M, `veilfx/QuasarSpawner.java` M, `client/sky/OverworldPurpleEffects.java` M, `client/sky/EclipseIrisState.java` M, `registry/EclipseSounds.java` M, `assets/eclipse/sounds.json` M, `core/config/EclipseClientConfig.java` M, `pinwheel post/program: world_grade` C, `sun_halo` M, `include/eclipse_common.glsl` C | **W1** |
| `cutscene/CutscenePath.java` M, `cutscene/CutscenePaths.java` M, `cutscene/CutsceneService.java` M, `cutscene/FreezeService.java` M, `cutscene/client/CameraDirector.java` M, `cutscene/client/LetterboxLayer.java` M, `client/EclipseGuiLayers.java` M, `cutscene/client/CaptionRenderer.java` C, `cutscene/ViewDistanceService.java` C, `cutscene/client/ViewDistanceClient.java` C, `cutscene/SequenceReplayable.java` C, `cutscene/dev/FxDevCommands.java` C, `assets/eclipse/cutscenes/finale_return.json` M | **W2** |
| `client/sky/LimboSpecialEffects.java` M, `veilfx/LimboAmbience.java` M, `pinwheel limbo` M, emitters `limbo_godray` C / `limbo_fog` C / `limbo_motes` M | **W3** |
| `border/client/BorderFxRenderer.java` M, `pinwheel border_glitch` M, `pinwheel altar_aberration` C, `client/AltarAberration.java` C, emitters `border_shard` C / `border_glitch` M | **W4** |
| `economy/SupplyBeacon.java` M, `veilfx/SupplyBeamClient.java` C, `veilfx/SupplyBeamRenderer.java` C, `client/WaveOverlay.java` M, `pinwheel shockwave` C, emitters `altar_beam` M / `supply_spark` C | **W5** |
| `sequence/IntroSequence.java` C, `sequence/IntroLightningPhase.java` C, `sequence/FloatingDecor.java` C, `limbo/StartEventCutscene.java` M, cutscenes `intro_v3_flight` C / `intro_v3_reveal` C / `intro_submerge` D / `intro_rise` D, emitters `cutscene_veil` M / `eclipse_lightning_impact` C / `impact_light` C / `altar_reveal_burst` C / `glide_trail` C | **W6** |
| `sequence/ExpansionSequence.java` C, `cutscene/UnlockCinematics.java` D, cutscenes `unlock_ring` M / `expansion_skyward` C / `expansion_flyover` C, emitters `map_expand_materialize` M / `growth_dust_wall` C / `structure_slam_dust` C / `roulette_flare` C | **W7** |
| `veilfx/rift/RiftFx.java` C, `veilfx/rift/RiftRenderer.java` C, `veilfx/TransitionFx.java` C, `pinwheel rift_glitch` C, emitters `rift_spark` C / `portal_surface_motes` C | **W8** |
| `stormfx/*` C (5 classes), `pinwheel storm_interior` C, emitters `storm_arc` C / `storm_rain_sheet` C / `vortex_wisp` C | **W9** |
| `client/hud/HeartBurstOverlay.java` M, `client/ShipDoorGlow.java` C, `client/GhostGradeFx.java` C, `pinwheel ghost_grade` C, emitters `heart_burst` M / `door_glow_motes` C | **W10** |
| **Frozen — nobody edits:** `EclipseMod.java`, `admin/EclipseCommands.java`, `network/EclipsePayloads.java`, `network/S2CQuasarPayload.java`, `client/ClientStateCache.java`, `assets/eclipse/lang/*.json`, mixin config + `client/mixin/*`, `worldgen/**` (P1), `client/hud/AnnouncementOverlay.java` (P3) | — |

Every package also creates its own `docs/plans_v3/langdrop/P2W<i>.json`.

### 8.2 Uniform/payload/id freeze — quick reference
Pipelines + uniforms: §3.3 table. Payloads: §3.2 table. FX event ids: §3.2 list. Anchor ids: `eclipse:ship_door`, `eclipse:altar_center`, `eclipse:ship_deck`. New emitter ids: exactly those in §8.1. New sounds: §3.5 list. New config key: `cinematicViewDistance`. Dev command root: `/eclipsefx` (permission 3).

### 8.3 Suggested landing order (packages are authored in parallel; merge order only matters for compile)
W1 → W2 → {W3, W4, W5, W8, W9, W10 in any order} → W6, W7 (consume the most APIs). Integration build + one full intro/expansion rehearsal on a fresh dev world closes P2.
