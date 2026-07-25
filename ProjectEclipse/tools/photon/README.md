# tools/photon — programmatic Photon `.fx` authoring (PH-CORE)

`fxlib.py` authors Photon effect files (**gzip-compressed NBT**, NOT JSON) from Python,
field-for-field against the reverse-engineered schema in
`docs/plans_v3/plans_v5/photon/FX_FORMAT.md` (photon-neoforge-1.21.1-2.1.5). It ports and
expands the PHOTON-EXPLORE-2-validated generator; the shipped smoke-test templates are
deep-compare-identical to that generator's output. No third-party deps (stdlib only).

## Where files go

- **Repo-shipped (default):** `src/main/resources/assets/eclipse/fx/<path>.fx` →
  ResourceLocation **`eclipse:<path>`** (use `fxlib.FX_ASSETS_DIR`). Rides in the Eclipse
  jar; loaded lazily by Photon's `FXHelper` through the vanilla ResourceManager — no
  registration call.
- Resource-pack drop-in works identically (`assets/eclipse/fx/…` inside any pack).
- In-game reload after replacing a file: `/photon_client clear_client_fx_cache` + `F3+T`.

## CLI

```
python3 tools/photon/fxlib.py selfcheck          # build + round-trip both templates (CI-style gate)
python3 tools/photon/fxlib.py templates          # regenerate the two smoke-test assets
python3 tools/photon/fxlib.py validate <f.fx>…   # gzip + NBT parse + schema + byte round-trip
python3 tools/photon/fxlib.py dump <f.fx>        # pretty-print any .fx (incl. editor exports)
```

`FxBuilder.write(path)` round-trip-validates by default — a written file is guaranteed to
re-parse byte-identically. Always run `validate` on editor-exported files before committing.

## API surface (what content implementers use)

```python
from fxlib import *                       # run from tools/photon/ or sys.path.insert it

fx = FxBuilder("my_effect")               # -> eclipse:my_effect
pivot = fx.empty("root").at(0, 1, 0)      # grouping/pivot node (no rendering)

em = (fx.particle_emitter("sparks",       # kwargs = main block, all optional:
          duration=40, looping=False, prewarm=0, start_delay=0,
          start_lifetime=random_between(18, 32), start_speed=0.5,
          start_size=0.12, start_rotation=nf3(0, 0, random_between(0, 360)),
          start_color=color(0xFFFFCC88), simulation_space="World",  # or "Local"
          max_particles=256, parallel_update=False, parallel_rendering=False)
    .child_of(pivot)                      # Transform parent linking (UUID relink)
    .at(0, 0.5, 0).rotated(0, 45, 0).scaled(1.5)
    .with_emission(rate=1.5, bursts=[burst(time=0, count=40, cycles=1)])
    .with_shape(sphere(radius=0.35, thickness=0.0))   # or circle/cone/cylinder/box/
                                                      # mesh(model, emit_from="Triangle")/
                                                      # function_shape(x="0.8*cos(t*2*PI)",…)/dot()
    .with_material(texture_material("photon:textures/particle/circle.png",
                                    hdr=(2.0, 1.2, 0.4), blend=BLEND_ADDITIVE))
    .with_renderer(render_mode="Billboard", vertex_sorting="DISTANCE")
    .with_cull_box((-2, -0.5, -2), (2, 3, 2))
    .with_curves(color_over_lifetime=gradient([(0, 1), (1, 0)], [(0, 1, 1, 1)]),
                 size_over_lifetime=curve(0.0, 1.5, [SEG_POP_SHRINK]),
                 velocity_over_lifetime=dict(linear=nf3(0, 0.05, 0),
                                             orbital=nf3(0, 0.8, 0)),
                 noise=dict(frequency=0.8, position=nf3(0.05)))
    .with_physics(gravity=0.35, bounce_chance=0.6)    # world collision
    .with_lights(sky=15, block=15)                    # forced-lightmap fake glow
    .with_sub_emitters(sub_emitter("eclipse:child_fx", event="Death",
                                   inherit=("Color", "Size"))))

fx.trail_emitter("ribbon", time=20, width=0.2)        # standalone trail strip
fx.ara_trail_emitter("whip", thickness=0.2,           # premium physics ribbon
                     section=[(-0.5, 0), (0.5, 0)],
                     physics=dict(gravity=(0, -0.1, 0), damping=0.75))
fx.beam_emitter("laser", end=(0, 0, -8), width=0.3, raycast="BLOCKS")

raw_len, gz_len = fx.write(FX_ASSETS_DIR / "my_effect.fx")
```

NumberFunction helpers (any config knob accepts a scalar OR one of these):
`constant(n)` · `random_between(a, b)` · `curve(lower, upper, [8-float bezier segs])` ·
`random_curve(...)` · `color(0xAARRGGBB)` · `random_color(a, b)` ·
`gradient(alpha_pts, rgb_pts)` · `random_gradient(...)` · `nf3(x, y, z)` (vector form).
Materials: `texture_material` / `sprite_material` / `block_atlas_material` /
`custom_shader_material`; blend presets `BLEND_ADDITIVE`, `BLEND_ALPHA`, custom via
`blend(src, dst, …, func)`. HDR: `hdr=(r, g, b)` on any material = bloom emission boost.
Escape hatch for exotic modules: `.with_module("<nbtKey>", {raw compound})`.

Golden rules (FX_FORMAT.md §10): times in **ticks**, sizes in **blocks** ·
`looping=False` + a burst = one-shot; `looping=True` + `rate` = ambient ·
`simulation_space="World"` for debris, `"Local"` for auras that follow their anchor ·
loops need a cull box + modest `max_particles` · ara-trail `time`/`time_interval` are
in SECONDS (the one exception).

## Smoke-test templates (shipped)

- `eclipse:template_burst` — one-shot radial spark burst (physics bounce, additive HDR-ready
  dot, gradient fade, pop-shrink size curve). One-shot spawn reference.
- `eclipse:template_loop` — looping violet aura ring (prewarm 20, orbital velocity, noise,
  cull box, alpha blend). WINDOWED-loop reference (see `PhotonFxRegistry` loop rows).

In-game test (Photon installed): `/dev photon test eclipse:template_burst`, or vanilla
Photon `/photon fx eclipse:template_burst block ~ ~1 ~`. Through the Eclipse lane:
`PhotonBridge.spawn(...)` / `PhotonFxRegistry` rows (see
`docs/plans_v3/plans_v5/photon/INTEGRATION.md` §3–§4).
