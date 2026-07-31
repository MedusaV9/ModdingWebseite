# UV map — Soul Wisp (`assets/eclipse/textures/entity/soul_wisp.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/soul_wisp.geo.json` — **10 bones / 8 cubes**
(MA5 pass; was 7 bones / 6 cubes on a 32² sheet). The small violet gate ghost that pours
out of the opened portal during the finale. Two MA5 additions drive the layout: the
**shell fragments** (`shell_l` / `shell_r`), which hug the shroud in life and tumble
apart in the 3-bone death decay, and the cube-less **`trail_tail` locator**, which is
the FX anchor at the tail tip. The geo file **is** the UV source of truth; the painter
computes each face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | Box-UV | Notes |
|---|---|---|---|---|
| root | — (cube-less) | — | — | scatter/collapse pivot — `panic_scatter` and `death` drive this |
| body | shroud | 6×8×4 | (24,0) | hooded translucent weave, brighter rim edge |
| glow_core | soul core | 3×4×1 | (8,15) | **emissive** — the inner light; flares then collapses in `death` |
| glow_eyes | eye slit | 4×1×1 | (16,15) | **emissive** — narrow slit (painter kills the two end pixels) |
| shell_l | shroud fragment | 1×10×5 | (0,0) | torn cloth plate, lit break edge + frayed hem |
| shell_r | shroud fragment | 1×10×5 | (12,0) | mirror of `shell_l` |
| tail | ragged tail | 4×5×2 | (44,0) | alpha bleeds out toward the tip, torn hem holes |
| trail_tail | — (cube-less) | — | — | **FX locator** at the tail tip — A3's trail/mote anchor |
| arm_l | shroud arm | 2×5×2 | (56,0) | wispy hand tip |
| arm_r | shroud arm | 2×5×2 | (0,15) | |

**Art brief:** a shade, not a mob — it should read as cloth with a light inside it. Shroud
violet `#4A2E73` over deep `#2E1C4A` with a `#9C7BE0` rim; the renderer runs
`entityTranslucent`, so the painter writes real alpha (shroud ~150, rim ~170, tail fading
to ~30 at the tip, hand tips ~120). The shells are painted slightly **more opaque**
(~160/190) with a lit break edge along the outer seam and frayed hem holes, so that once
they drift off in `death` they read as *pieces of the same cloth* rather than as loose
geometry. Core `#E8DAFF`, eyes `#D0B3FF`.

**Emissive (glowmask):** `glow_core` + `glow_eyes` (auto-included by the painter — for
these the albedo IS the glow source), plus a **custom glow painter on `shell_*`**. That
one is deliberately narrow: the shell faces are 1px deep, so *every* pixel on the side
faces is an edge pixel — an edge rule would light the whole fragment fullbright and kill
the translucent read. Instead only the top two rows (the shoulder break seam, where the
core light spills through) plus sparse weave flecks glow. All emissive pixels are ALSO
bright in the albedo (conventions §4).

**Animation hooks:** `idle` (2.5 s) and `walk` (2.0 s) add shell breathing/flutter on top
of the old bob. `attack` (0.5 s) is unchanged in shape. `panic_scatter` (0.9 s, one-shot)
is the MA5 flinch — recoil + spin on `body`, the shells snap open, arms whip, the tail
cracks, and the core/eyes flash; the entity fires it from `SoulWispEntity` when a player
sprints within `PANIC_RADIUS`. `death` (1.2 s, `hold_on_last_frame`) is the **3-bone
decay** that replaced the 1-bone fade: `body` shrinks and spins down, `glow_core` flares
then collapses to nothing, and `shell_l`/`shell_r` drift apart with their own rotation
and scale while tail/arms/eyes fold in. The sheet is 24t long and
`SoulWispEntity.tickDeath()` holds removal for `DEATH_DURATION_TICKS = 24`, so the decay
always plays out fully. The renderer must keep `withUprightDeath()` — the vanilla
sideways flip would fight the scripted collapse.

**Generator:** `python3 scripts/geckolib_gen/mobs/soul_wisp.py` (deterministic —
byte-identical on rerun; writes albedo + glowmask in one run).
