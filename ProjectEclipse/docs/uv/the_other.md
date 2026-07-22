# UV map — The Other (`assets/eclipse/textures/entity/the_other.png`)

**Texture size:** 64×64 — this is the STANDARD vanilla player-skin layout (the model reuses
vanilla `HumanoidModel` geometry unchanged: head 8×8×8 @ (0,0), body 8×12×4 @ (16,16),
right arm 4×12×4 @ (40,16), left arm 4×12×4 @ (32,48), right leg 4×12×4 @ (0,16), left leg
4×12×4 @ (16,48), plus the +0.5-inflated overlay layers of the modern skin format).
Any player-skin editor/reference applies 1:1.

**Art brief (spec §1.1):** the texture MUST be a derivative of
`assets/eclipse/textures/entity/uniform_skin.png` (the anonymity uniform every player
wears) so The Other is indistinguishable from a teammate at distance. Exactly two changes:

| Change | Base-layer pixels | Hat-layer pixels (renders on top, fully opaque) |
|---|---|---|
| Pure-black 2×2 eyes | (9–10, 11–12) and (13–14, 11–12) | (41–42, 11–12) and (45–46, 11–12) |
| Faint purple face seam (1 px vertical, face center) | column x=11, y 8–15 | column x=43, y 8–15 |

Seam color: subtle shift off the uniform base (placeholder uses `#8367A8` over `#997EB5`).
Both layers must be edited — the uniform skin's hat-layer face is opaque and covers the base.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java` (reads
`uniform_skin.png`, applies the table above).

**Renderer notes:** `TheOtherRenderer` extends `HumanoidMobRenderer`; no emissive layer.
The mob is silent and player-like — do NOT add glowing features that would break the
doppelganger read.
