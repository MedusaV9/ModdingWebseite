#!/usr/bin/env python3
"""Erzeugt die leeren GameTest-Arena-Strukturen als gzip-NBT:
arena (5x8x5) und arena_large (17x10x17, fuer Follow-/Jar-Spawn-Tests).

Aufruf:  python3 scripts/gen_structure.py
"""
import gzip
import os
import struct

DATA_ROOT = os.path.join(os.path.dirname(__file__), "..", "src", "main", "resources", "data")
BASES = (
    os.path.join(DATA_ROOT, "goobymod", "structure"),
    os.path.join(DATA_ROOT, "goobymod_create", "structure"),
)
DATA_VERSION = 3955  # Minecraft 1.21.1

STRUCTURES = {
    "arena.nbt": (5, 8, 5),
    "arena_large.nbt": (17, 10, 17),
}
BURROW_OUT = os.path.join(DATA_ROOT, "goobymod", "structure", "burrow", "gooby_burrow.nbt")
CACHE_OUT = os.path.join(DATA_ROOT, "goobymod", "structure", "treasure_cache", "gooby_treasure_cache.nbt")


def tag_name(s):
    b = s.encode("utf-8")
    return struct.pack(">H", len(b)) + b


def named(tag_type, name, payload):
    return bytes((tag_type,)) + tag_name(name) + payload


def string_payload(value):
    return tag_name(value)


def int_tag(name, value):
    return named(3, name, struct.pack(">i", value))


def long_tag(name, value):
    return named(4, name, struct.pack(">q", value))


def byte_tag(name, value):
    return named(1, name, struct.pack(">b", value))


def string_tag(name, value):
    return named(8, name, string_payload(value))


def list_tag(name, element_type, payloads):
    return named(9, name, bytes((element_type,)) + struct.pack(">i", len(payloads)) + b"".join(payloads))


def compound_payload(entries):
    return b"".join(entries) + b"\x00"


def compound_tag(name, entries):
    return named(10, name, compound_payload(entries))


def build(size):
    buf = b"\x0a" + tag_name("")  # Root-Compound
    buf += b"\x03" + tag_name("DataVersion") + struct.pack(">i", DATA_VERSION)
    buf += b"\x09" + tag_name("size") + b"\x03" + struct.pack(">i", 3) + struct.pack(">iii", *size)
    buf += b"\x09" + tag_name("entities") + b"\x00" + struct.pack(">i", 0)
    buf += b"\x09" + tag_name("blocks") + b"\x00" + struct.pack(">i", 0)
    buf += b"\x09" + tag_name("palette") + b"\x00" + struct.pack(">i", 0)
    buf += b"\x00"  # End
    return buf


def build_burrow():
    size = (9, 5, 9)
    palette_names = (
        "minecraft:air",
        "minecraft:dirt",
        "minecraft:grass_block",
        "minecraft:oak_planks",
        "minecraft:chest",
    )
    palette = [
        compound_payload([string_tag("Name", name)])
        for name in palette_names
    ]
    blocks = {}

    def put(x, y, z, state):
        blocks[(x, y, z)] = state

    # Floor and a low, grass-topped mound.
    for x in range(9):
        for z in range(9):
            put(x, 0, z, 1)
    for y in range(1, 4):
        for x in range(1, 8):
            for z in range(1, 8):
                boundary = x in (1, 7) or z in (1, 7)
                put(x, y, z, 1 if boundary else 0)
    for x in range(1, 8):
        for z in range(1, 8):
            put(x, 4, z, 2)

    # South-facing tunnel, warm chamber trim, and guaranteed loot chest.
    for z in (7, 8):
        for y in (1, 2):
            for x in (3, 4, 5):
                put(x, y, z, 0)
    for x, z in ((2, 2), (6, 2), (2, 6), (6, 6)):
        put(x, 1, z, 3)
    put(4, 1, 3, 4)

    block_payloads = []
    for (x, y, z), state in sorted(blocks.items(), key=lambda entry: (entry[0][1], entry[0][2], entry[0][0])):
        entries = [
            list_tag("pos", 3, [struct.pack(">i", value) for value in (x, y, z)]),
            int_tag("state", state),
        ]
        if state == 4:
            entries.append(compound_tag("nbt", [
                string_tag("id", "minecraft:chest"),
                string_tag("LootTable", "goobymod:chests/gooby_burrow"),
                long_tag("LootTableSeed", 0),
            ]))
        block_payloads.append(compound_payload(entries))

    gooby_nbt = compound_payload([
        string_tag("id", "goobymod:gooby"),
        byte_tag("BurrowResident", 1),
        byte_tag("ShyUntilFed", 1),
        byte_tag("PersistenceRequired", 1),
    ])
    entity = compound_payload([
        list_tag("pos", 6, [struct.pack(">d", value) for value in (4.5, 1.0, 5.5)]),
        list_tag("blockPos", 3, [struct.pack(">i", value) for value in (4, 1, 5)]),
        compound_tag("nbt", [
            string_tag("id", "goobymod:gooby"),
            byte_tag("BurrowResident", 1),
            byte_tag("ShyUntilFed", 1),
            byte_tag("PersistenceRequired", 1),
        ]),
    ])

    return (b"\x0a" + tag_name("")
            + int_tag("DataVersion", DATA_VERSION)
            + list_tag("size", 3, [struct.pack(">i", value) for value in size])
            + list_tag("palette", 10, palette)
            + list_tag("blocks", 10, block_payloads)
            + list_tag("entities", 10, [entity])
            + b"\x00")


def build_treasure_cache():
    """A tiny terrain-matched buried chamber with one guaranteed loot chest."""
    size = (5, 4, 5)
    palette_names = (
        "minecraft:air",
        "minecraft:stone_bricks",
        "minecraft:mossy_stone_bricks",
        "minecraft:chest",
        "minecraft:dirt",
    )
    palette = [compound_payload([string_tag("Name", name)]) for name in palette_names]
    blocks = {}

    def put(x, y, z, state):
        blocks[(x, y, z)] = state

    for y in range(4):
        for x in range(5):
            for z in range(5):
                boundary = y in (0, 3) or x in (0, 4) or z in (0, 4)
                if boundary:
                    put(x, y, z, 2 if (x * 7 + y * 5 + z * 11) % 6 == 0 else 1)
                else:
                    put(x, y, z, 0)
    put(2, 1, 2, 3)
    for x in range(5):
        for z in range(5):
            put(x, 3, z, 4)

    block_payloads = []
    for (x, y, z), state in sorted(blocks.items(), key=lambda entry: (entry[0][1], entry[0][2], entry[0][0])):
        entries = [
            list_tag("pos", 3, [struct.pack(">i", value) for value in (x, y, z)]),
            int_tag("state", state),
        ]
        if state == 3:
            entries.append(compound_tag("nbt", [
                string_tag("id", "minecraft:chest"),
                string_tag("LootTable", "goobymod:chests/gooby_treasure_cache"),
                long_tag("LootTableSeed", 0),
            ]))
        block_payloads.append(compound_payload(entries))

    return (b"\x0a" + tag_name("")
            + int_tag("DataVersion", DATA_VERSION)
            + list_tag("size", 3, [struct.pack(">i", value) for value in size])
            + list_tag("palette", 10, palette)
            + list_tag("blocks", 10, block_payloads)
            + list_tag("entities", 10, [])
            + b"\x00")


if __name__ == "__main__":
    for base in BASES:
        os.makedirs(base, exist_ok=True)
        for name, size in STRUCTURES.items():
            out = os.path.join(base, name)
            with gzip.GzipFile(filename=out, mode="wb", mtime=0) as f:
                f.write(build(size))
            print("Struktur geschrieben:", out)
    os.makedirs(os.path.dirname(BURROW_OUT), exist_ok=True)
    with gzip.GzipFile(filename=BURROW_OUT, mode="wb", mtime=0) as f:
        f.write(build_burrow())
    print("Struktur geschrieben:", BURROW_OUT)
    os.makedirs(os.path.dirname(CACHE_OUT), exist_ok=True)
    with gzip.GzipFile(filename=CACHE_OUT, mode="wb", mtime=0) as f:
        f.write(build_treasure_cache())
    print("Struktur geschrieben:", CACHE_OUT)
