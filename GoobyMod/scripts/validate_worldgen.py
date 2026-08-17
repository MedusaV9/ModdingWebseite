#!/usr/bin/env python3
"""Fail-closed Worldgen-Validator fuer die Gooby-Strukturen.

Prueft (Exit-Code != 0 bei jedem Fehler):
  1. NBT-Integritaet aller Templates unter data/goobymod/structure/**:
     gzip lesbar, DataVersion, size > 0, Positionen in den Grenzen,
     keine Duplikate, State-Indizes im Palettenbereich.
  2. Paletten: jede Block-Id ist wohlgeformt; goobymod-Bloecke muessen in
     ModBlocks.java registriert sein, Vanilla-Bloecke stehen auf einer
     expliziten Allowlist. Properties nur aus bekannten Wertemengen.
  3. Loot-Referenzen: jede LootTable-Referenz in Truhen-NBT zeigt auf eine
     existierende JSON; jede Item-Id in chests-Loot-Tables ist registriert
     (goobymod via ModItems.java, Vanilla via Allowlist).
  4. Jigsaw-Verbindungen: jeder Socket (pool != minecraft:empty) findet in
     seinem Pool mindestens ein Piece mit passendem Plug-Namen; die
     Fallback-Kette endet in minecraft:empty und der letzte nicht-leere
     Pool ist ein echter Terminator (Pieces ohne weitere Sockets).
     Boundary-Regel: die Anschlussposition jedes expandierenden Sockets
     (Socket + Blickrichtung) muss AUSSERHALB der Template-Bounds liegen —
     sonst kippt Vanillas JigsawPlacement in den Innen-Expansionsmodus und
     verwirft jedes Kind-Piece, das nicht in die eigene Box passt. Plugs
     und Terminator-Kappen (pool == minecraft:empty) sind bewusst
     ausgenommen: sie expandieren nie und duerfen nach innen zeigen.
  5. Pool-Termination: Pool-Graph ist azyklisch und die maximale
     Expansionstiefe liegt unter der size der jeweiligen Structure.
  6. Structure-/Structure-Set-/Tag-JSONs: Pflichtfelder, existierende
     Referenzen, spacing > separation, eindeutige Salts.
  7. Reproduzierbarkeit: alle committeten NBT-Dateien sind byte-identisch
     mit dem Output von scripts/gen_structure.py.

Aufruf:  python3 scripts/validate_worldgen.py [--root PFAD]
"""
from __future__ import annotations

import argparse
import gzip
import io
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_structure  # noqa: E402

DATA_BASE = os.path.join("src", "main", "resources", "data", "goobymod")
JAVA_BASE = os.path.join("src", "main", "java", "de", "sonic0810", "goobymod")

VANILLA_BLOCKS = {
    "minecraft:air", "minecraft:cave_air", "minecraft:dirt", "minecraft:grass_block",
    "minecraft:rooted_dirt", "minecraft:coarse_dirt", "minecraft:oak_planks",
    "minecraft:chest", "minecraft:torch", "minecraft:hay_block",
    "minecraft:white_carpet", "minecraft:pink_carpet", "minecraft:cake",
    "minecraft:lantern", "minecraft:jigsaw", "minecraft:poppy", "minecraft:dandelion",
    "minecraft:stone_bricks", "minecraft:mossy_stone_bricks",
}
VANILLA_ITEMS = {
    "minecraft:carrot", "minecraft:golden_carrot", "minecraft:bread",
    "minecraft:cookie", "minecraft:cake", "minecraft:wheat", "minecraft:sweet_berries",
}
VANILLA_BIOME_TAGS = {"minecraft:is_overworld"}
ALLOWED_PROPERTY_VALUES = {
    "facing": {"north", "south", "east", "west"},
    "orientation": {"north_up", "south_up", "east_up", "west_up",
                    "up_north", "up_south", "up_east", "up_west",
                    "down_north", "down_south", "down_east", "down_west"},
    "waterlogged": {"true", "false"},
    "hanging": {"true", "false"},
    "type": {"single", "left", "right"},
}
HORIZONTAL_ORIENTATIONS = {"north_up", "south_up", "east_up", "west_up"}
# Blickrichtung (erster Orientierungs-Teil) -> Einheitsvektor der Anschlussposition.
FRONT_VECTORS = {
    "north": (0, 0, -1), "south": (0, 0, 1),
    "west": (-1, 0, 0), "east": (1, 0, 0),
    "up": (0, 1, 0), "down": (0, -1, 0),
}
VALID_STEPS = {
    "raw_generation", "lakes", "local_modifications", "underground_structures",
    "surface_structures", "strongholds", "underground_ores", "underground_decoration",
    "fluid_springs", "vegetal_decoration", "top_layer_modification",
}
VALID_ADAPTATION = {"none", "beard_thin", "beard_box", "bury", "encapsulate"}
EMPTY_POOL = "minecraft:empty"

ID_RE = re.compile(r"^[a-z0-9_.-]+:[a-z0-9_./-]+$")

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


# ---------------------------------------------------------------------------
# Minimaler NBT-Reader (Big-Endian, gzip)
# ---------------------------------------------------------------------------

class NbtReader:
    def __init__(self, data: bytes):
        self.stream = io.BytesIO(data)

    def read(self):
        tag_type = self._byte()
        if tag_type != 10:
            raise ValueError(f"Root-Tag ist kein Compound (Typ {tag_type})")
        self._string()
        return self._payload(10)

    def _byte(self):
        return struct.unpack(">b", self.stream.read(1))[0]

    def _string(self):
        (length,) = struct.unpack(">H", self.stream.read(2))
        return self.stream.read(length).decode("utf-8")

    def _payload(self, tag_type):
        s = self.stream
        if tag_type == 1:
            return self._byte()
        if tag_type == 2:
            return struct.unpack(">h", s.read(2))[0]
        if tag_type == 3:
            return struct.unpack(">i", s.read(4))[0]
        if tag_type == 4:
            return struct.unpack(">q", s.read(8))[0]
        if tag_type == 5:
            return struct.unpack(">f", s.read(4))[0]
        if tag_type == 6:
            return struct.unpack(">d", s.read(8))[0]
        if tag_type == 7:
            (count,) = struct.unpack(">i", s.read(4))
            return list(struct.unpack(f">{count}b", s.read(count)))
        if tag_type == 8:
            return self._string()
        if tag_type == 9:
            element_type = self._byte()
            (count,) = struct.unpack(">i", s.read(4))
            return [self._payload(element_type) for _ in range(count)]
        if tag_type == 10:
            result = {}
            while True:
                child_type = self._byte()
                if child_type == 0:
                    return result
                name = self._string()
                result[name] = self._payload(child_type)
        if tag_type == 11:
            (count,) = struct.unpack(">i", s.read(4))
            return list(struct.unpack(f">{count}i", s.read(4 * count)))
        if tag_type == 12:
            (count,) = struct.unpack(">i", s.read(4))
            return list(struct.unpack(f">{count}q", s.read(8 * count)))
        raise ValueError(f"Unbekannter NBT-Tag-Typ {tag_type}")


def read_nbt_file(path: str):
    with gzip.open(path, "rb") as handle:
        return NbtReader(handle.read()).read()


# ---------------------------------------------------------------------------
# Registrierte Ids aus den Java-Registries parsen
# ---------------------------------------------------------------------------

def parse_registered_ids(root: str):
    blocks_src = open(os.path.join(root, JAVA_BASE, "registry", "ModBlocks.java"),
                      encoding="utf-8").read()
    items_src = open(os.path.join(root, JAVA_BASE, "registry", "ModItems.java"),
                     encoding="utf-8").read()
    entities_src = open(os.path.join(root, JAVA_BASE, "registry", "ModEntities.java"),
                        encoding="utf-8").read()

    block_const_to_id = dict(re.findall(
        r"(\w+)\s*=\s*BLOCKS\.register\(\s*\"([a-z0-9_]+)\"", blocks_src))
    blocks = {f"goobymod:{block_id}" for block_id in block_const_to_id.values()}

    items = {f"goobymod:{item_id}" for item_id in
             re.findall(r"ITEMS\.register\(\s*\"([a-z0-9_]+)\"", items_src)}
    for const in re.findall(r"ITEMS\.registerSimpleBlockItem\(ModBlocks\.(\w+)\)", items_src):
        if const not in block_const_to_id:
            fail(f"ModItems referenziert unbekannte ModBlocks-Konstante {const}")
        else:
            items.add(f"goobymod:{block_const_to_id[const]}")

    entities = {f"goobymod:{entity_id}" for entity_id in
                re.findall(r"\.register\(\s*\"([a-z0-9_]+)\"", entities_src)}
    return blocks, items, entities


# ---------------------------------------------------------------------------
# Struktur-NBT-Validierung
# ---------------------------------------------------------------------------

class TemplateInfo:
    def __init__(self, size, jigsaws):
        self.size = size        # [sx, sy, sz]
        self.jigsaws = jigsaws  # [{pos, orientation, name, target, pool, final_state}]

    @property
    def sockets(self):
        return [j for j in self.jigsaws if j["pool"] != EMPTY_POOL]

    @property
    def plug_names(self):
        return {j["name"] for j in self.jigsaws}


def validate_template(path: str, rel: str, mod_blocks, mod_entities,
                      loot_refs: list) -> TemplateInfo | None:
    try:
        root = read_nbt_file(path)
    except Exception as exc:  # noqa: BLE001 — fail-closed Reporting
        fail(f"{rel}: NBT nicht lesbar ({exc})")
        return None

    if root.get("DataVersion") != gen_structure.DATA_VERSION:
        fail(f"{rel}: DataVersion {root.get('DataVersion')} != {gen_structure.DATA_VERSION}")
    size = root.get("size")
    if not (isinstance(size, list) and len(size) == 3 and all(s > 0 for s in size)):
        fail(f"{rel}: ungueltige size {size}")
        return None

    palette = root.get("palette", [])
    for index, entry in enumerate(palette):
        name = entry.get("Name", "")
        if not ID_RE.match(name):
            fail(f"{rel}: Palette[{index}] hat ungueltige Id '{name}'")
            continue
        if name.startswith("goobymod:"):
            if name not in mod_blocks:
                fail(f"{rel}: goobymod-Block '{name}' ist nicht in ModBlocks registriert")
        elif name.startswith("minecraft:"):
            if name not in VANILLA_BLOCKS:
                fail(f"{rel}: Vanilla-Block '{name}' steht nicht auf der Allowlist")
        else:
            fail(f"{rel}: fremder Namespace in Palette: '{name}'")
        for prop, value in entry.get("Properties", {}).items():
            allowed = ALLOWED_PROPERTY_VALUES.get(prop)
            if allowed is None:
                fail(f"{rel}: unbekannte Blockstate-Property '{prop}' an {name}")
            elif value not in allowed:
                fail(f"{rel}: Property {prop}={value} an {name} unzulaessig")

    jigsaws = []
    seen_positions = set()
    for block in root.get("blocks", []):
        pos = tuple(block.get("pos", ()))
        state = block.get("state", -1)
        if len(pos) != 3 or not all(0 <= pos[i] < size[i] for i in range(3)):
            fail(f"{rel}: Blockposition {pos} ausserhalb von {size}")
            continue
        if pos in seen_positions:
            fail(f"{rel}: doppelte Blockposition {pos}")
        seen_positions.add(pos)
        if not (0 <= state < len(palette)):
            fail(f"{rel}: State-Index {state} ausserhalb der Palette")
            continue
        entry = palette[state]
        name = entry.get("Name", "")
        nbt = block.get("nbt")
        if name == "minecraft:jigsaw":
            if not nbt:
                fail(f"{rel}: Jigsaw bei {pos} ohne Block-NBT")
                continue
            orientation = entry.get("Properties", {}).get("orientation", "")
            record = {
                "pos": pos,
                "orientation": orientation,
                "name": nbt.get("name", ""),
                "target": nbt.get("target", ""),
                "pool": nbt.get("pool", ""),
                "final_state": nbt.get("final_state", ""),
            }
            for key in ("name", "target", "pool", "final_state"):
                if not ID_RE.match(record[key]):
                    fail(f"{rel}: Jigsaw bei {pos} hat ungueltiges Feld {key}='{record[key]}'")
            if record["final_state"].split("[")[0] not in VANILLA_BLOCKS | mod_blocks:
                fail(f"{rel}: Jigsaw-final_state '{record['final_state']}' unbekannt")
            jigsaws.append(record)
        elif name == "minecraft:chest":
            if not nbt or "LootTable" not in nbt:
                fail(f"{rel}: Truhe bei {pos} ohne LootTable")
            else:
                loot_refs.append((rel, nbt["LootTable"]))

    for entity in root.get("entities", []):
        entity_id = entity.get("nbt", {}).get("id", "")
        if entity_id.startswith("goobymod:") and entity_id not in mod_entities:
            fail(f"{rel}: Entity '{entity_id}' ist nicht registriert")
        block_pos = tuple(entity.get("blockPos", ()))
        if len(block_pos) != 3 or not all(0 <= block_pos[i] < size[i] for i in range(3)):
            fail(f"{rel}: Entity-Position {block_pos} ausserhalb von {size}")

    return TemplateInfo(size, jigsaws)


# ---------------------------------------------------------------------------
# Loot-Tables
# ---------------------------------------------------------------------------

def loot_table_path(root: str, ref: str) -> str | None:
    if not ref.startswith("goobymod:"):
        return None
    return os.path.join(root, DATA_BASE, "loot_table", *ref.split(":", 1)[1].split("/")) + ".json"


def validate_loot_tables(root: str, loot_refs, mod_items):
    for rel, ref in loot_refs:
        path = loot_table_path(root, ref)
        if path is None:
            fail(f"{rel}: LootTable-Referenz '{ref}' liegt nicht im goobymod-Namespace")
            continue
        if not os.path.isfile(path):
            fail(f"{rel}: LootTable '{ref}' hat keine JSON unter {os.path.relpath(path, root)}")

    chests_dir = os.path.join(root, DATA_BASE, "loot_table", "chests")
    for file_name in sorted(os.listdir(chests_dir)):
        path = os.path.join(chests_dir, file_name)
        rel = os.path.relpath(path, root)
        try:
            table = json.load(open(path, encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"{rel}: JSON-Fehler ({exc})")
            continue
        if table.get("type") != "minecraft:chest":
            fail(f"{rel}: type != minecraft:chest")
        for pool in table.get("pools", []):
            entries = pool.get("entries", [])
            if not entries:
                fail(f"{rel}: leerer Loot-Pool")
            for entry in entries:
                if entry.get("type") != "minecraft:item":
                    fail(f"{rel}: unerwarteter Entry-Typ {entry.get('type')}")
                    continue
                item = entry.get("name", "")
                if item.startswith("goobymod:"):
                    if item not in mod_items:
                        fail(f"{rel}: goobymod-Item '{item}' nicht in ModItems registriert")
                elif item.startswith("minecraft:"):
                    if item not in VANILLA_ITEMS:
                        fail(f"{rel}: Vanilla-Item '{item}' steht nicht auf der Allowlist")
                else:
                    fail(f"{rel}: ungueltige Item-Id '{item}'")


# ---------------------------------------------------------------------------
# Pools, Structures, Structure-Sets, Tags
# ---------------------------------------------------------------------------

def pool_file(root: str, pool_id: str) -> str:
    return os.path.join(root, DATA_BASE, "worldgen", "template_pool",
                        *pool_id.split(":", 1)[1].split("/")) + ".json"


def load_pools(root: str, templates):
    pools = {}
    pool_dir = os.path.join(root, DATA_BASE, "worldgen", "template_pool")
    for dirpath, _dirnames, filenames in os.walk(pool_dir):
        for file_name in sorted(filenames):
            path = os.path.join(dirpath, file_name)
            rel = os.path.relpath(path, root)
            pool_id = "goobymod:" + os.path.relpath(path, pool_dir)[:-len(".json")].replace(os.sep, "/")
            try:
                data = json.load(open(path, encoding="utf-8"))
            except json.JSONDecodeError as exc:
                fail(f"{rel}: JSON-Fehler ({exc})")
                continue
            if data.get("name") != pool_id:
                fail(f"{rel}: Pool-name '{data.get('name')}' != Dateipfad-Id '{pool_id}'")
            elements = data.get("elements", [])
            if not elements:
                fail(f"{rel}: Pool ohne Elemente")
            locations = []
            for element in elements:
                if element.get("weight", 0) <= 0:
                    fail(f"{rel}: Element mit weight <= 0")
                inner = element.get("element", {})
                if inner.get("element_type") != "minecraft:single_pool_element":
                    fail(f"{rel}: unerwarteter element_type {inner.get('element_type')}")
                    continue
                if inner.get("processors") != "minecraft:empty":
                    fail(f"{rel}: unerwarteter processors-Eintrag {inner.get('processors')}")
                if inner.get("projection") not in ("rigid", "terrain_matching"):
                    fail(f"{rel}: ungueltige projection {inner.get('projection')}")
                location = inner.get("location", "")
                if location not in templates:
                    fail(f"{rel}: Template '{location}' existiert nicht unter structure/")
                else:
                    locations.append(location)
            pools[pool_id] = {"fallback": data.get("fallback", ""), "locations": locations,
                              "rel": rel}
    return pools


def fallback_chain(pools, pool_id, rel):
    chain = []
    current = pool_id
    seen = set()
    while current != EMPTY_POOL:
        if current in seen:
            fail(f"{rel}: Fallback-Zyklus ab Pool '{pool_id}'")
            return chain
        seen.add(current)
        if current not in pools:
            fail(f"{rel}: Pool '{current}' existiert nicht")
            return chain
        chain.append(current)
        current = pools[current]["fallback"]
    return chain


def validate_jigsaw_graph(pools, templates, structures):
    # 4a) Jeder Socket findet Anschluss und einen garantierten Terminator.
    for template_id, info in sorted(templates.items()):
        if info is None:
            continue
        for socket in info.sockets:
            where = f"structure/{template_id.split(':', 1)[1]} Socket {socket['pos']}"
            if socket["orientation"] not in HORIZONTAL_ORIENTATIONS:
                fail(f"{where}: nicht-horizontale Orientierung {socket['orientation']}")
            # Boundary-Regel: Anschlussposition muss ausserhalb der Bounds liegen.
            # Nur expandierende Sockets — Plugs/Terminator-Kappen (pool ==
            # minecraft:empty) sind hier per Definition von info.sockets ausgenommen.
            front = FRONT_VECTORS.get(socket["orientation"].split("_", 1)[0])
            if front is None:
                fail(f"{where}: Orientierung '{socket['orientation']}' hat keine "
                     f"bekannte Blickrichtung")
            else:
                conn = tuple(socket["pos"][i] + front[i] for i in range(3))
                if all(0 <= conn[i] < info.size[i] for i in range(3)):
                    fail(f"{where}: Anschlussposition {conn} liegt innerhalb der "
                         f"Template-Bounds {tuple(info.size)} — JigsawPlacement kippt "
                         f"in den Innen-Expansionsmodus und verwirft Tunnel/Kammern; "
                         f"Socket auf die aeusserste Schicht verschieben")
            chain = fallback_chain(pools, socket["pool"], where)
            if not chain:
                continue
            primary = pools[chain[0]]
            if not any(socket["target"] in templates[loc].plug_names
                       for loc in primary["locations"] if templates.get(loc)):
                fail(f"{where}: Pool '{chain[0]}' enthaelt kein Piece mit Plug "
                     f"'{socket['target']}'")
            terminator = pools[chain[-1]]
            terminal_ok = False
            for loc in terminator["locations"]:
                piece = templates.get(loc)
                if piece and socket["target"] in piece.plug_names and not piece.sockets:
                    terminal_ok = True
            if not terminal_ok:
                fail(f"{where}: Terminator-Pool '{chain[-1]}' hat keinen socketfreien "
                     f"Plug fuer '{socket['target']}'")

    # 4b/5) Pool-Graph azyklisch; Expansionstiefe < structure.size.
    def max_depth(pool_id, stack):
        if pool_id == EMPTY_POOL or pool_id not in pools:
            return 0
        if pool_id in stack:
            fail(f"Pool-Zyklus ueber '{pool_id}'")
            return 99
        depth = 0
        chain = [pool_id]
        current = pools[pool_id]["fallback"]
        while current != EMPTY_POOL and current in pools and current not in chain:
            chain.append(current)
            current = pools[current]["fallback"]
        for member in chain:
            for location in pools[member]["locations"]:
                info = templates.get(location)
                if not info:
                    continue
                for socket in info.sockets:
                    depth = max(depth, 1 + max_depth(socket["pool"], stack | {pool_id}))
        return depth

    for structure_id, structure in sorted(structures.items()):
        depth = 1 + max_depth(structure["start_pool"], frozenset())
        if depth > structure["size"]:
            fail(f"{structure_id}: Expansionstiefe {depth} uebersteigt size "
                 f"{structure['size']} — offene Enden ohne Terminator moeglich")


def load_structures(root: str, pools):
    structures = {}
    structure_dir = os.path.join(root, DATA_BASE, "worldgen", "structure")
    for file_name in sorted(os.listdir(structure_dir)):
        path = os.path.join(structure_dir, file_name)
        if not file_name.endswith(".json"):
            continue
        rel = os.path.relpath(path, root)
        structure_id = "goobymod:" + file_name[:-len(".json")]
        try:
            data = json.load(open(path, encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"{rel}: JSON-Fehler ({exc})")
            continue
        if data.get("type") != "minecraft:jigsaw":
            fail(f"{rel}: type != minecraft:jigsaw")
        if data.get("step") not in VALID_STEPS:
            fail(f"{rel}: ungueltiger step {data.get('step')}")
        if data.get("terrain_adaptation") not in VALID_ADAPTATION:
            fail(f"{rel}: ungueltige terrain_adaptation {data.get('terrain_adaptation')}")
        if data.get("spawn_overrides") != {}:
            fail(f"{rel}: spawn_overrides erwartet leeres Objekt")
        size = data.get("size")
        if not isinstance(size, int) or not 0 <= size <= 7:
            fail(f"{rel}: size {size} ausserhalb 0..7")
        distance = data.get("max_distance_from_center")
        if not isinstance(distance, int) or not 1 <= distance <= 128:
            fail(f"{rel}: max_distance_from_center {distance} ausserhalb 1..128")
        start_pool = data.get("start_pool", "")
        if start_pool not in pools:
            fail(f"{rel}: start_pool '{start_pool}' existiert nicht")
        biomes = data.get("biomes", "")
        if biomes.startswith("#goobymod:"):
            tag_path = os.path.join(root, DATA_BASE, "tags", "worldgen", "biome",
                                    biomes.split(":", 1)[1] + ".json")
            if not os.path.isfile(tag_path):
                fail(f"{rel}: Biome-Tag '{biomes}' hat keine Tag-Datei")
            else:
                tag = json.load(open(tag_path, encoding="utf-8"))
                if not tag.get("values"):
                    fail(f"{rel}: Biome-Tag '{biomes}' ist leer")
        elif biomes.startswith("#minecraft:"):
            if biomes.split(":", 1)[1] not in {t.split(":", 1)[1] for t in VANILLA_BIOME_TAGS}:
                fail(f"{rel}: Vanilla-Biome-Tag '{biomes}' steht nicht auf der Allowlist")
        else:
            fail(f"{rel}: biomes '{biomes}' ist kein Tag")
        structures[structure_id] = {"start_pool": start_pool, "size": size or 0}
    return structures


def validate_structure_sets(root: str, structures):
    set_dir = os.path.join(root, DATA_BASE, "worldgen", "structure_set")
    salts = {}
    for file_name in sorted(os.listdir(set_dir)):
        path = os.path.join(set_dir, file_name)
        rel = os.path.relpath(path, root)
        try:
            data = json.load(open(path, encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"{rel}: JSON-Fehler ({exc})")
            continue
        for member in data.get("structures", []):
            if member.get("structure") not in structures:
                fail(f"{rel}: Structure '{member.get('structure')}' existiert nicht")
            if member.get("weight", 0) <= 0:
                fail(f"{rel}: weight <= 0")
        placement = data.get("placement", {})
        if placement.get("type") != "minecraft:random_spread":
            fail(f"{rel}: placement.type != minecraft:random_spread")
        spacing, separation = placement.get("spacing", 0), placement.get("separation", -1)
        if not 0 < spacing <= 4096 or separation < 0 or separation >= spacing:
            fail(f"{rel}: spacing/separation ({spacing}/{separation}) ungueltig")
        if spacing < 32:
            fail(f"{rel}: spacing {spacing} < 32 — Gooby-Begegnungen sollen selten bleiben")
        salt = placement.get("salt")
        if not isinstance(salt, int) or salt <= 0:
            fail(f"{rel}: salt fehlt oder <= 0")
        elif salt in salts:
            fail(f"{rel}: salt {salt} kollidiert mit {salts[salt]}")
        else:
            salts[salt] = rel


def validate_structure_tags(root: str, structures):
    tag_dir = os.path.join(root, DATA_BASE, "tags", "worldgen", "structure")
    if not os.path.isdir(tag_dir):
        return
    for file_name in sorted(os.listdir(tag_dir)):
        path = os.path.join(tag_dir, file_name)
        rel = os.path.relpath(path, root)
        data = json.load(open(path, encoding="utf-8"))
        for value in data.get("values", []):
            if value not in structures:
                fail(f"{rel}: Structure '{value}' existiert nicht")


# ---------------------------------------------------------------------------
# Reproduzierbarkeit: Dateien == Generator-Output
# ---------------------------------------------------------------------------

def validate_reproducibility(root: str):
    def compare(path, expected, label):
        if not os.path.isfile(path):
            fail(f"{label}: Datei fehlt — scripts/gen_structure.py ausfuehren")
            return
        with gzip.open(path, "rb") as handle:
            actual = handle.read()
        if actual != expected:
            fail(f"{label}: NBT weicht vom Generator ab — scripts/gen_structure.py ausfuehren")

    for base in ("goobymod", "goobymod_create"):
        for name, size in gen_structure.ARENAS.items():
            compare(os.path.join(root, "src", "main", "resources", "data", base,
                                 "structure", name),
                    gen_structure.build(size), f"data/{base}/structure/{name}")
    for rel_path, builder in gen_structure.PIECES.items():
        compare(os.path.join(root, DATA_BASE, "structure", rel_path), builder(),
                f"data/goobymod/structure/{rel_path.replace(os.sep, '/')}")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=os.path.join(os.path.dirname(__file__), ".."),
                        help="Projektwurzel (Default: Repo-Root relativ zum Skript)")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    mod_blocks, mod_items, mod_entities = parse_registered_ids(root)

    structure_root = os.path.join(root, DATA_BASE, "structure")
    templates = {}
    loot_refs = []
    for dirpath, _dirnames, filenames in os.walk(structure_root):
        for file_name in sorted(filenames):
            if not file_name.endswith(".nbt"):
                continue
            path = os.path.join(dirpath, file_name)
            rel = os.path.relpath(path, root)
            template_id = "goobymod:" + os.path.relpath(path, structure_root)[:-len(".nbt")] \
                .replace(os.sep, "/")
            templates[template_id] = validate_template(path, rel, mod_blocks,
                                                       mod_entities, loot_refs)

    validate_loot_tables(root, loot_refs, mod_items)
    pools = load_pools(root, templates)
    structures = load_structures(root, pools)
    validate_structure_sets(root, structures)
    validate_structure_tags(root, structures)
    validate_jigsaw_graph(pools, templates, structures)
    validate_reproducibility(root)

    if errors:
        print(f"FEHLGESCHLAGEN — {len(errors)} Problem(e):")
        for message in errors:
            print("  -", message)
        return 1
    print(f"OK — {len(templates)} Templates, {len(pools)} Pools, "
          f"{len(structures)} Structures validiert; Generator-Output reproduzierbar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
