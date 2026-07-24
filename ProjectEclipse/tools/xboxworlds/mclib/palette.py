"""Frozen classic-block palette mapping (plan P5 SS2.14) + packed-data helpers.

Naming scheme (FROZEN, shared with P5-W8 who registers the blocks in parallel):

    minecraft:<path>  ->  eclipse:classic_<path>        (properties preserved)

Exceptions (also frozen, keep this list in sync with docs/plans_v3/xbox_palette.json):
  * air family stays vanilla - air must remain air for game logic:
        minecraft:air, minecraft:cave_air, minecraft:void_air
  * fluids are baked to PROPERTYLESS solid deco blocks (SS2.14 FLUID_SOLID -
    "water becomes solid glassy deco"; flowing states collapse into the same id):
        minecraft:water[level=*] -> eclipse:classic_water   (no properties)
        minecraft:lava[level=*]  -> eclipse:classic_lava    (no properties)
  * `waterlogged` is force-normalized to "false" on every remapped entry:
    classic dimensions must contain zero vanilla fluid, otherwise a stray
    waterlogged block would become the only flowing water in the dimension.

Everything else is a mechanical rename; state properties pass through verbatim,
which is exactly what W8 gets for free by extending the vanilla base classes.
Any non-`minecraft:` palette id fails the bake loudly (fail-loud rule, SS2.13.1-4).
"""

from __future__ import annotations

from . import nbt

AIR_PASSTHROUGH = frozenset({"minecraft:air", "minecraft:cave_air", "minecraft:void_air"})

FLUID_SOLID = {
    "minecraft:water": "eclipse:classic_water",
    "minecraft:lava": "eclipse:classic_lava",
}

CLASSIC_PREFIX = "eclipse:classic_"


class PaletteError(ValueError):
    pass


def classic_id_for(vanilla_id: str) -> str | None:
    """None => entry passes through unchanged (air family)."""
    if vanilla_id in AIR_PASSTHROUGH:
        return None
    if vanilla_id in FLUID_SOLID:
        return FLUID_SOLID[vanilla_id]
    ns, sep, path = vanilla_id.partition(":")
    if not sep or ns != "minecraft":
        raise PaletteError(f"unmapped non-vanilla palette id: {vanilla_id!r}")
    return CLASSIC_PREFIX + path


def map_palette_entry(entry: nbt.Compound) -> tuple[nbt.Compound, dict]:
    """Returns (new_entry, info). info: {vanilla, mapped, fluid, waterlogged_flip}."""
    name = entry["Name"]
    info = {"vanilla": name, "fluid": False, "waterlogged_flip": False}
    target = classic_id_for(name)
    if target is None:
        info["mapped"] = name
        return entry, info
    new_entry = nbt.Compound()
    new_entry["Name"] = target
    if name in FLUID_SOLID:
        info["fluid"] = True  # drop level=* properties entirely
    else:
        props = entry.get("Properties")
        if props is not None:
            new_props = nbt.Compound()
            for k, v in props.items():
                if k == "waterlogged" and v == "true":
                    info["waterlogged_flip"] = True
                    new_props[k] = "false"
                else:
                    new_props[k] = v
            new_entry["Properties"] = new_props
    info["mapped"] = target
    return new_entry, info


# ---------------------- packed block_states data helpers ----------------------

def bits_for(palette_len: int) -> int:
    """Bits per index in a section's packed `data` long array (1.16+ layout)."""
    if palette_len <= 1:
        return 0
    return max(4, (palette_len - 1).bit_length())


def decode_indices(data: list[int], palette_len: int) -> list[int]:
    """Unpack a 4096-entry index list. Values never span longs (1.16+)."""
    bits = bits_for(palette_len)
    if bits == 0:
        return [0] * 4096
    vpl = 64 // bits
    mask = (1 << bits) - 1
    out = [0] * 4096
    i = 0
    for word in data:
        w = word & 0xFFFFFFFFFFFFFFFF
        for _ in range(vpl):
            if i >= 4096:
                break
            out[i] = w & mask
            w >>= bits
            i += 1
    if i < 4096:
        raise PaletteError(f"packed data too short: got {i} of 4096 indices")
    return out


def count_indices(data: list[int], palette_len: int) -> list[int]:
    """Per-palette-index occurrence counts over the 4096 blocks of a section."""
    bits = bits_for(palette_len)
    counts = [0] * palette_len
    if bits == 0:
        counts[0] = 4096
        return counts
    vpl = 64 // bits
    mask = (1 << bits) - 1
    remaining = 4096
    for word in data:
        w = word & 0xFFFFFFFFFFFFFFFF
        n = vpl if remaining >= vpl else remaining
        for _ in range(n):
            idx = w & mask
            if idx >= palette_len:
                raise PaletteError(f"palette index {idx} out of range ({palette_len})")
            counts[idx] += 1
            w >>= bits
        remaining -= n
        if remaining <= 0:
            break
    if remaining > 0:
        raise PaletteError(f"packed data too short: {remaining} indices missing")
    return counts


def encode_indices(indices: list[int], palette_len: int) -> nbt.LongArray:
    """Pack 4096 indices back into a signed-long array (1.16+ layout)."""
    bits = bits_for(palette_len)
    if bits == 0:
        return nbt.LongArray()
    vpl = 64 // bits
    out = []
    for base in range(0, 4096, vpl):
        w = 0
        shift = 0
        for idx in indices[base:base + vpl]:
            w |= (idx & ((1 << bits) - 1)) << shift
            shift += bits
        if w >= 1 << 63:
            w -= 1 << 64
        out.append(w)
    return nbt.LongArray(out)
