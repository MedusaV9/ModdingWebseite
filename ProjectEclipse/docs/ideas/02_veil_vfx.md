# Collector #2 — Veil / Shaders / Particles / VFX

## A) Verified facts

- **Veil 4.3.0 targets NeoForge 1.21.1 — confirmed** (Modrinth API: `game_versions: ["1.21.1"]`, `loaders: ["neoforge"]`, released 2026-07-02, file `veil-neoforge-1.21.1-4.3.0.jar`). Changelog: Quasar particle editor (PR #163), improved trails module (PR #164). Deps: `sodium` optional (compatible), `imguimc` optional, `embeddium`+`rubidium` INCOMPATIBLE. Iris not flagged.
- **License**: LGPL-3.0-only — safe to depend on + jar-in-jar.
- **Gradle**:
```groovy
repositories {
    maven { url = 'https://maven.blamejared.com' }               // Veil
    maven { url = 'https://maven.ryanhcode.dev/releases' }       // ImGuiMC (dev tools)
}
dependencies {
    implementation("foundry.veil:veil-neoforge-1.21.1:4.3.0") {
        exclude group: "maven.modrinth"; exclude group: "me.fallenbreath"
    }
}
```
- ImGuiMC powers in-game editor overlay (default **F6**; `/veilc buffers`; Quasar particle editor). Dev-only; end users don't need it.
- **Iris/Sodium**: Sodium fine (Veil ships `SodiumShaderPreProcessor`). Veil has first-party `foundry.veil.api.compat.IrisCompat` (`INSTANCE` null without Iris; `areShadersLoaded()` = pack active) — replaces our reflection IrisCompat. With active shaderpack, Veil world-geometry shaders bypass Iris pipeline and break (Veil issue #34; bridge mod `iris-veil-compat` exists, NeoForge, Iris 1.8.1+/Veil 4.0.0+). **Decision: gate all Veil post pipelines behind `areShadersLoaded()`; optionally recommend iris-veil-compat.**
- **Sable / Aeronautics — UPDATED**: Create Aeronautics IS publicly released on Modrinth (repo Creators-of-Aeronautics/Simulated-Project, ~2026-04; requires Create + Sable). Sable (`modrinth.com/mod/sable`, ryanhcode) = sub-level/Rapier-physics lib; `sable-neoforge-1.21.1-2.0.3.jar` jar-in-jars `veil-neoforge-1.21.1-4.1.4` with OPEN range `[4.1.4,)` → jarjar picks highest → our Veil 4.3.0 wins cleanly. **No conflict.**
- **Lodestone**: `lodestonelib` has NeoForge 1.21.1 builds (latest 1.8.2, 2026-01). Coexists with Veil but **SKIP**: Quasar covers particles, `foundry.veil.api.client.util.Easing` covers easing, post pipelines cover screen FX; two render libs doubles compat surface.
- **Veil 4.x breaking changes**: shader injections moved to `pinwheel/shader_injection/*.json` + GLSL `void head()/tail()` markers. Quasar `init_size`/`init_random_rotation` deprecated (use ParticleSettings fields). Wiki regenerated 2026-06-26 (matches 4.2/4.3).

## B) Wish → Veil mechanism

**Wiring**: Veil assets in `assets/eclipse/pinwheel/...`; Quasar in `assets/eclipse/quasar/...`; Flare in `assets/eclipse/flare/...`. Post pipelines toggled via `VeilRenderSystem.renderer().getPostProcessingManager().add(id)/.remove(id)/.isActive(id)` (verified in PostProcessingManager). Per-frame uniforms via `VeilEventPlatform.INSTANCE.preVeilPostProcessing((name, pipeline, ctx) -> pipeline.getUniform("X").setFloat(...))`.

**1. Limbo post shader**:
- `assets/eclipse/pinwheel/post/limbo.json`:
```json5
{ "stages": [ { "type": "veil:blit", "shader": "eclipse:limbo", "in": "minecraft:main", "out": "veil:post" } ] }
```
- `assets/eclipse/pinwheel/shaders/program/limbo.json`: `{ "vertex": "veil:blit_screen", "fragment": "eclipse:limbo" }`
- `assets/eclipse/pinwheel/shaders/program/limbo.fsh`:
```glsl
uniform sampler2D DiffuseSampler0; uniform sampler2D DiffuseDepthSampler;
uniform float Intensity; in vec2 texCoord; out vec4 fragColor;
void main() {
    vec4 c = texture(DiffuseSampler0, texCoord);
    float gray = dot(c.rgb, vec3(0.299,0.587,0.114));
    vec3 purple = mix(c.rgb, gray * vec3(0.75,0.45,1.1), 0.55);
    float d = distance(texCoord, vec2(0.5));
    purple *= 1.0 - smoothstep(0.45, 0.95, d) * 0.6;
    fragColor = vec4(mix(c.rgb, purple, Intensity), 1.0);
}
```
- Toggle on ClientTick/dimension change: in limbo & no Iris pack → `postManager.add(LIMBO_POST)` else remove. Fade `Intensity` 0→1 over ~40t with `Easing.EASE_OUT_QUAD`. Keep biome water_color/fog as Iris-active fallback.
- **Purple water bonus**: shader injection `assets/eclipse/pinwheel/shader_injection/limbo_water.json` targeting `minecraft:shaders/core/rendertype_translucent.fsh` with `void tail()` deep-tinting fragColor — gated by Veil definition (`getShaderDefinitions().set("eclipse_in_limbo")` + `#ifdef`).

**2. Sun purple rim** (`post/sun_halo.json`): pass `SunDirection` uniform (from `level.getSunAngle`) in preVeilPostProcessing; project to screen UV via `#veil:buffer veil:camera VeilCamera`; where `texture(DiffuseDepthSampler, uv).r >= 1.0` (sky only) add `vec3(0.6,0.2,1.0) * pow(max(dot(viewDir, sunDir),0.0), 400.0)`. Add when dimension == OVERWORLD, same Iris gate (fallback: existing sun.png override).

**3. Quasar** replaces vanilla particle call sites in BeamEmitter, ArmParticles, StartEventCutscene.

**4. Polish**:
- *Expansion FX*: Quasar `veil:cube` emitters sized to new chunk area, `block` module + `light` module — "blocks materializing". Trigger via S2C payload.
- *Unlock celebrations*: one-shot `postManager.runPipeline(...)` with `Progress` uniform + `Easing.EASE_OUT_ELASTIC`; Quasar burst.
- *Camera*: **Veil has NO cinematic camera API.** Closest: `VeilLevelPerspectiveRenderer` (render level from arbitrary camera into AdvancedFbo — picture-in-picture shots) and Necromancer `KeyframeTimeline` (bone anim, WIP). Build own camera engine; use Veil post for letterbox/grade.
- *UI shaders*: `VeilRenderSystem.setShader(ResourceLocation)` returns ShaderProgram w/ getUniform, usable in GUI rendering; `#veil:buffer veil:gui_info VeilGuiInfo` uniform block designed for GUI-space shaders. Pattern: custom RenderType with Veil shader shard for animated handbook backgrounds.

## C) Quasar deep-dive

Layout under `assets/eclipse/quasar/`:

| Folder | Content |
|---|---|
| `emitters/` | ParticleEmitterData: `max_lifetime`, `loop`, `rate`, `count`, `emitter_settings{shape, particle_settings, force_spawn}`, `particle_data` |
| `modules/emitter/shape/` | `veil:point/sphere/hemisphere/cylinder/cube/torus/disc/plane`, `dimensions`, `rotation`, `from_surface` |
| `modules/emitter/particle/` | ParticleSettings: lifetime/size/speed/direction + randomization (all fields required) |
| `modules/particle_data/` | QuasarParticleData: `render_type` (CUBE/BILLBOARD), `init_modules`, `update_modules`, `collision_modules`, `forces`, `render_modules`, `sprite_data{sprite, frame_count, frame_time, stretch_to_lifetime}`, `additive`, `should_collide`, `face_velocity`, `velocity_stretch_factor` |

Built-in modules (verified ParticleModuleTypeRegistry): init `initial_velocity`, `init_sub_emitter`, `light` (dynamic colored light!), `lightmap`, `block`; render `trail`, `color` (Molang gradient); update `size`, `tick_sub_emitter`; collision `die_on_collision`, `sub_emitter_collision`; forces `gravity`, `vortex`, `point_attractor`, `vector_field`, `drag`, `wind`, `point_force`. Molang: `q.agePercent` etc.

Spawning (CLIENT only):
```java
ParticleSystemManager mgr = VeilRenderSystem.renderer().getParticleManager();
ParticleEmitter e = mgr.createEmitter(ResourceLocation.fromNamespaceAndPath("eclipse","altar_beam"));
e.setPosition(pos); // or e.setAttachedEntity(entity)
mgr.addParticleSystem(e);
```
Server logic needs S2C payload w/ emitter id + pos. Wrap in try/catch. Dev: `/quasar <emitter> <pos>` client command + F3+T hot reload + 4.3.0 editor.

**Emitter set**: `altar_beam` (looping cylinder, violet gradient, light, upward), `arm_wisps` (entity-attached, trail + vortex, additive), `map_expand_materialize` (cube volume, block module + light), `border_glitch` (plane along border face, Molang flicker, additive), `boss_slam` (burst, gravity + die_on_collision), `heart_burst` (heart sprite, stretch_to_lifetime), `limbo_motes` (looping sphere around camera, vector_field drift, low alpha), `cutscene_veil` (hemisphere, additive streaks, velocity_stretch).

## D) Fallback — recommendation: REQUIRED dependency

Jar-in-jar Veil 4.3.0, range `[4.3.0,)` (matches Sable pattern; jarjar dedupes). Justification: Quasar/post assets are data files (dead weight without Veil); dual code path doubles testing; ecosystem precedent (Sable ships Veil embedded on same MC/loader); LGPL. **Real degradation axis is Iris shaderpacks, not Veil absence**: swap reflection IrisCompat → Veil `IrisCompat.INSTANCE.areShadersLoaded()`, gate post pipelines + injections off when pack active (biome colors, sun.png, Quasar particles remain), document iris-veil-compat.

## E) Ranked VFX ideas

1. [MUST] Limbo grade + vignette post (desaturate→violet, breathing vignette) — 2
2. [MUST] Quasar altar ritual beam — 2
3. [MUST] Sun purple rim/corona post (depth-masked additive) — 3
4. [MUST] Arm-artifact wisps w/ trails — 2
5. [SHOULD] Map-expansion materialize volume (block cubes + light) — 2
6. [SHOULD] Worldborder purple glitch (plane emitter flicker + chromatic aberration post w/ BorderDist uniform) — 3
7. [SHOULD] Desaturation heartbeat at 1 heart — 2
8. [SHOULD] Limbo ambience motes + caustic shimmer — 2
9. [SHOULD] Cutscene letterbox + film grade post — 2
10. [SHOULD] Unlock celebration: radial shockwave post one-shot + confetti burst — 3
11. [NICE] Eclipse corona flicker (noise-driven rim) — 2
12. [NICE] Limbo water shader injection — 2
13. [NICE] Boss telegraph decals via Flare (`assets/eclipse/flare/`) — 4
14. [NICE] Ghost-ship picture-in-picture via VeilLevelPerspectiveRenderer — 5
15. [NICE] Handbook UI shimmer shader (VeilGuiInfo) — 3

**Summary**: Veil 4.3.0 required jar-in-jar (no Sable/Aeronautics/Create conflict), skip Lodestone, Veil IrisCompat, gate post/injection behind shaderpack-active, Quasar for all 8 particle systems, own camera engine + Veil post for cinema look.
