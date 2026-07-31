# UV map — Portal Gate (`assets/eclipse/textures/entity/portal_gate.png` + `_glowmask.png`)

**Texture size:** 512×512 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/portal_gate.geo.json` — **22 bones / 39
cubes** (MA5 pass; was 8 bones / 11 cubes, and the census' §4 finding was that 11 flat
plates sat on an otherwise empty 512² sheet). The gate is the ~12-block finale arch:
twin basalt pillars built from **interlocking courses** (plinth → proud course → flush
course → proud course → capital), a **three-voussoir arch per side** climbing into a
proud keystone wedge, and two blackened-oak door wings with tarnished-silver banding.
As with every GeckoLib mob the geo file **is** the UV source of truth — the painter
(`scripts/geckolib_gen/paint_lib.py`) parses it and computes each face rect itself, so
only the layout is frozen here:

| Bone | Cube | Box W×H×D | Box-UV | Notes |
|---|---|---|---|---|
| root → frame | — (cube-less) | — | — | `frame` is the breathing group — the whole arch scales/lifts off this bone |
| pillar_l | plinth | 44×14×28 | (290,263) | widest course, sits on the waterline |
| pillar_l | course A (flush) | 32×34×16 | (363,157) | recessed course — the interlock's "in" |
| pillar_l | course B (proud) | 38×32×22 | (271,0) | proud course — the interlock's "out" |
| pillar_l | course C (flush) | 32×34×16 | (0,212) | recessed |
| pillar_l | course D (proud) | 38×30×22 | (121,157) | proud |
| pillar_l | capital | 44×16×28 | (0,263) | the arch springs from here |
| pillar_r | (same six) | — | (0,308) / (97,212) / (0,157) / (194,212) / (242,157) / (145,263) | mirrored column |
| glow_rune_l1..l4 | rune plate | 24×24×1 | (65,351) / (116,351) / (167,351) / (218,351) | **emissive** — one carved glyph each (variants 0–3), alternating z-depth so they read as set INTO the courses |
| glow_rune_r1..r4 | rune plate | 24×24×1 | (269,351) / (320,351) / (371,351) / (422,351) | **emissive** — glyph variants 4–7 |
| arch_l | voussoir 1 | 24×14×20 | (307,308) | springer wedge |
| arch_l | voussoir 2 | 24×20×16 | (145,308) | mid wedge |
| arch_l | voussoir 3 | 14×26×20 | (291,212) | crown-side wedge |
| arch_r | voussoir 1..3 | 24×14×20 / 24×20×16 / 14×26×20 | (396,308) / (226,308) / (360,212) | mirrored |
| glow_shimmer_l / _r | shimmer chip | 8×8×1 | (450,380) / (469,380) | **emissive** — cut violet facet, offset-phase twinkle |
| keystone_block | keystone wedge | 22×34×24 | (178,0) | proud of the arch plane (the interlock's apex) |
| keystone_block | crown | 12×8×20 | (0,351) | chamfered cap |
| glow_keystone | eclipse disc | 20×20×1 | (0,380) | **emissive** — violet annulus around a void core, gold rim ticks |
| glow_shimmer_top | shimmer bar | 10×4×1 | (488,380) | **emissive** — the third chip, over the crown |
| door_l / door_r | wing | 40×152×4 | (0,0) / (89,0) | blackened-oak strakes, opens on `unlock` |
| door_l / door_r | rail ×2 | 40×10×8 | (43,380) & (140,380) / (237,380) & (334,380) | proud silver-banded rails — the wings are no longer flat slabs |
| glow_keyhole | keyhole slot | 8×16×1 | (431,380) | **emissive** — the slot the flying key seats into |

**Art brief:** the finale portal conjured out of accumulated day-rift debris. Void
basalt `#17131E` / `#0E0B14` (chipped grain `#241E30`) in mortared courses with sparse
wandering **violet vein cracks** (`#4A2E73`→`#9C7BE0`); the voussoirs add radial joint
lines so the arch reads as CUT wedges rather than one slab; the keystone gets chamfered
gold-fleck edges (`#FAD173`). Doors are blackened oak `#241B14`/`#1A130E` in vertical
strakes with tarnished-silver `#8C8F9A`/`#6F7280` banding. Finale violet
`#9C7BE0` (mid) / `#D0B3FF` (hot) / `#4A2E73` (deep) carries every emissive.

**Emissive (glowmask):** the eleven `glow_*` bones. **The rune plates use CUSTOM glow
painters, not the default whole-bone lift** — only the carved strokes go into the
glowmask, so the runes read as light cut INTO dark stone instead of eleven glowing
tiles. Each of the eight rune plates carries a distinct glyph (shared corner ticks +
centre node so they read as a set; per-variant crossbars / chevrons / halo rings /
dotted bars / twin verticals). All emissive pixels are ALSO bright in the albedo
(conventions §4 — they must read under Iris shaderpacks).

**Animation hooks:** `idle` (8 s, breathing) scales/lifts `frame` and counter-breathes
the pillars, arches and keystone so the arch inhales as one body; the eight rune bones
and the keystone pulse on **Molang** (per-bone phase offsets — they glimmer
individually, which is the whole point of splitting them out). `unlock`
(6 s, `hold_on_last_frame`) is the door-open beat: the keyhole flares and the runes
ignite bottom-to-top in step with the key's three detents (0.4 s / 1.1 s / 1.8 s).

**Generator:** `python3 scripts/geckolib_gen/mobs/portal_gate.py` (deterministic —
byte-identical on rerun; writes albedo + glowmask in one run).
