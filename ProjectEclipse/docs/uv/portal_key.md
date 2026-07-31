# UV map — Portal Key (`assets/eclipse/textures/entity/portal_key.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/portal_key.geo.json` — **10 bones / 13
cubes** (MA5 pass; was 5 bones / 8 cubes). The ~3-block golden-violet finale key that
hovers over the altar and then flies to the gate keyhole. The MA5 change that matters is
the **bit split**: the old single `teeth` cube became three independently rotatable ward
bits (`bit_1..bit_3`, bottom → top), each carrying its own emissive **Bart-Glyphe**
plate — that is what makes the three-detent `unlock_turn` legible. The geo file **is**
the UV source of truth; the painter computes each face rect itself, so only the layout
is frozen here:

| Bone | Cube | Box W×H×D | Box-UV | Notes |
|---|---|---|---|---|
| root | — (cube-less) | — | — | the precession/turn axis — `idle` and `unlock_turn` both drive this |
| body | shaft | 4×26×4 | (0,0) | hammered gold with a violet filigree inlay spiralling down |
| body | ferrule/collar | 6×4×6 | (0,30) | banded collar under the bow, two violet seam rings |
| head | ring bar (top) | 14×3×4 | (0,48) | notch-etched gold — the bow |
| head | ring bar (bottom) | 14×3×4 | (0,55) | |
| head | ring side (left) | 3×8×4 | (16,0) | |
| head | ring side (right) | 3×8×4 | (30,0) | |
| glow_gem | heart gem | 4×4×5 | (24,30) | **emissive** — white-violet core in a violet skin; pulses once per detent |
| bit_1 | ward bit | 6×4×4 | (42,30) | longest bit — detent 1 (0.40 s) |
| glow_glyph_1 | Bart-Glyphe | 4×4×1 | (36,55) | **emissive** — ward pattern 0 (checker) |
| bit_2 | ward bit | 5×4×4 | (0,40) | detent 2 (1.10 s) |
| glow_glyph_2 | Bart-Glyphe | 3×4×1 | (46,55) | **emissive** — ward pattern 1 (banded) |
| bit_3 | ward bit | 4×4×4 | (18,40) | shortest bit — detent 3 (1.80 s), the "master" ward |
| glow_glyph_3 | Bart-Glyphe | 2×4×1 | (54,55) | **emissive** — ward pattern 2 (spine) |

**Art brief:** a ceremonial key, not a tool. Hammered gold `#FAD173` / `#C89A4B`
(tarnish pits `#8A6A2E`, glint facets toward `#FFF3C4`) with facet dither and edge wear;
the bits are deliberately **darker, work-scarred** gold with a lit chamfer on the
turning edge so the ward faces catch the light as they snap. Finale violet `#9C7BE0`
carries the shaft filigree and collar seams; the glyph plates and gem run hotter —
`#D0B3FF` glyph, `#C9A9FF` gem mid, `#E8DAFF` gem core.

**Emissive (glowmask):** `glow_gem` + `glow_glyph_1..3` (auto-included by the painter —
for these the albedo IS the glow source), plus a **custom glow painter on `body`** that
lifts ONLY the shaft's filigree line and the collar's two seam rings. Glow painters bind
per *bone*, not per cube, so that one painter distinguishes the two body cubes by face
width (`px.fw`) — the 4px-wide shaft gets the spiral, the 6px collar gets the rings.
All emissive pixels are ALSO bright in the albedo (conventions §4).

**Animation hooks:** `idle` (8 s) is the majesty pass — slow **precession** on `root`
(Molang), a gentle bob on `body`, and the three glyphs pulsing on staggered phases.
`fly` (1 s) is the fast flight spin. `unlock_turn` (2.4 s, `hold_on_last_frame`) is the
three-detent tumbler turn: `root` rotates in three rasts with pre-load → snap →
overshoot → settle, and each `bit_N` slams home on its own detent while
`glow_glyph_N` flashes. **The detents sit at 0.40 s / 1.10 s / 1.80 s = UNLOCK tick
8 / 22 / 36**, which is exactly `FinaleSequence.KEYGLYPH_CLICKS_AT` and B7's baked
glyph-ring snaps in `beat_finale_keyglyphs`. The sheet is 48t and the entity removes
itself at 46t, so the turn always finishes inside the `UNLOCK_HOLD_TICKS` window and
before `BREACH_AT_TICK` (50).

**Generator:** `python3 scripts/geckolib_gen/mobs/portal_key.py` (deterministic —
byte-identical on rerun; writes albedo + glowmask in one run).
