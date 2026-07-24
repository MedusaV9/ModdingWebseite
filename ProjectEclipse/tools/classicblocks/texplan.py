"""Shared helper: resolve which OUT textures every manifest entry needs.

Used by import_textures.py (what to build) and gen_assets.py / validate.py
(what to reference). Keeps the two sides in lockstep.
"""

import manifest


def slots_for(block):
    """Return {model slot -> OUT block-texture name} for one manifest entry."""
    kind = block["model"]
    tex = block["tex"]
    bid = block["id"]
    if kind == "cube_all":
        return {"all": tex.get("all", bid)}
    if kind == "cube_bottom_top":
        return {k: tex[k] for k in ("top", "bottom", "side")}
    if kind in ("cube_column_static", "pillar"):
        return {k: tex[k] for k in ("end", "side")}
    if kind == "grass_block":
        return {k: tex[k] for k in ("top", "side", "snow_side", "bottom")}
    if kind == "leaves":
        return {"all": tex["all"]}
    if kind == "crafting_table":
        return {k: tex[k] for k in ("top", "front", "side", "bottom")}
    if kind == "chest":
        return {k: tex[k] for k in ("front", "side", "top")}
    if kind == "furnace":
        return {k: tex[k] for k in ("front", "front_on", "side", "top")}
    if kind == "dispenser":
        return {k: tex[k] for k in ("front", "front_vertical", "side", "top")}
    if kind == "jukebox":
        return {k: tex[k] for k in ("top", "side")}
    if kind == "tnt":
        return {k: tex[k] for k in ("top", "side", "bottom")}
    if kind in ("slab", "stairs"):
        return {k: tex[k] for k in ("bottom", "top", "side")}
    if kind == "fence":
        return {"texture": tex["texture"]}
    if kind == "pane":
        return {"pane": tex["pane"], "edge": tex["edge"]}
    if kind == "ladder":
        return {"texture": tex["texture"]}
    if kind == "door":
        return {"bottom": tex["bottom"], "top": tex["top"]}
    if kind == "trapdoor":
        return {"texture": tex["texture"]}
    if kind in ("torch", "wall_torch"):
        return {"torch": tex["torch"]}
    if kind in ("rs_torch", "rs_wall_torch"):
        return {"on": tex["on"], "off": tex["off"]}
    if kind == "cross":
        return {"cross": tex["cross"]}
    if kind == "crop8":
        return {f"stage{i}": f"{tex['stages']}{i}" for i in range(8)}
    if kind == "stem":
        return {"stem": tex["stem"]}
    if kind == "attached_stem":
        return {"stem": tex["stem"], "upperstem": tex["upperstem"]}
    if kind == "farmland":
        return {k: tex[k] for k in ("top", "moist", "dirt")}
    if kind == "snow_layer":
        return {"texture": tex["texture"]}
    if kind == "orientable":
        return {k: tex[k] for k in ("front", "side", "top")}
    if kind == "rail_full":
        return {"flat": tex["flat"], "corner": tex["corner"]}
    if kind == "rail_straight":
        return {"flat": tex["flat"], "flat_on": tex["flat_on"]}
    if kind == "lever":
        return {"base": tex["base"], "lever": tex["lever"]}
    if kind in ("button", "plate"):
        return {"texture": tex["texture"]}
    if kind == "wire":
        return {k: tex[k] for k in ("line0", "line1", "dot", "overlay")}
    if kind == "repeater":
        return {k: tex[k] for k in ("off", "on", "stone")}
    if kind == "piston":
        return {k: tex[k] for k in ("platform", "side", "bottom", "inner")}
    if kind == "piston_head":
        return {k: tex[k] for k in ("platform", "sticky", "side")}
    if kind == "vine":
        return {"vine": tex["vine"]}
    if kind == "lily":
        return {"texture": tex["texture"]}
    if kind == "cactus":
        return {k: tex[k] for k in ("top", "side", "bottom")}
    # --- palette reconciliation kinds ---
    if kind == "mycelium":
        return {k: tex[k] for k in ("top", "side", "bottom")}
    if kind == "cube_all_inner":
        return {"all": tex.get("all", bid)}
    if kind == "wall":
        return {"wall": tex["wall"]}
    if kind == "carpet":
        return {"wool": tex["wool"]}
    if kind == "anvil":
        return {"body": tex["body"], "top": tex["top"]}
    if kind == "brewing_stand":
        return {"stand": tex["stand"], "base": tex["base"]}
    if kind == "enchanting_table":
        return {k: tex[k] for k in ("top", "side", "bottom")}
    if kind == "end_portal_frame":
        return {k: tex[k] for k in ("top", "side", "bottom", "eye")}
    if kind == "rs_lamp":
        return {"off": tex["off"], "on": tex["on"]}
    if kind == "nether_portal":
        return {"portal": tex["portal"]}
    if kind == "fire":
        return {"fire0": tex["fire0"], "fire1": tex["fire1"]}
    if kind == "fence_gate":
        return {"texture": tex["texture"]}
    if kind == "wall_sign":
        return {"board": tex["board"]}
    if kind == "bed":
        return {"sheet": tex["sheet"]}
    if kind == "crop4":
        return {f"stage{i}": f"{tex['stages']}{i}" for i in range(4)}
    if kind == "cocoa":
        return {f"stage{i}": f"{tex['stages']}{i}" for i in range(3)}
    if kind == "mushroom":
        # every huge-mushroom block shares the pore "inside" face texture
        return {"outside": tex["outside"], "inside": "mushroom_block_inside"}
    if kind == "tripwire":
        return {"texture": tex["texture"]}
    if kind == "tripwire_hook":
        return {k: tex[k] for k in ("hook", "wood", "tripwire")}
    if kind == "cauldron":
        return {k: tex[k] for k in ("top", "bottom", "side", "inside", "content")}
    if kind == "potted":
        return {"plant": tex["plant"], "flowerpot": "flower_pot", "dirt": "dirt"}
    if kind == "skull":
        return {"skin": tex["skin"]}
    raise KeyError(f"unknown model kind {kind} for {bid}")


def needed_block_textures():
    """All OUT block-texture names required by the manifest."""
    out = set()
    for b in manifest.BLOCKS:
        out.update(slots_for(b).values())
    return sorted(out)


def needed_item_textures():
    """All OUT item-texture names (textures/item/classic/) required."""
    out = set()
    for b in manifest.BLOCKS:
        item = b["item"]
        if isinstance(item, str) and item.startswith("generated:item/classic/"):
            out.add(item.split("/")[-1])
        if b["model"] == "door":
            out.add(b["tex"]["item"])
    return sorted(out)


if __name__ == "__main__":
    bt = needed_block_textures()
    it = needed_item_textures()
    print(f"{len(bt)} block textures, {len(it)} item textures")
    print(bt)
    print(it)
