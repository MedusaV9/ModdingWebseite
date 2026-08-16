#!/usr/bin/env python3
"""Reproduzierbarer Struktur-Generator fuer alle Gooby-NBT-Templates.

Erzeugt (gzip-NBT, mtime=0, deterministische Bytes):
  * arena / arena_large            — leere GameTest-Arenen (goobymod + goobymod_create)
  * arena_worldgen                 — grosse leere Arena (48x10x48) fuer den
                                     End-to-End-Jigsaw-Assembly-GameTest
  * treasure_cache/gooby_treasure_cache — vergrabene Schatzkammer
  * burrow/gooby_burrow            — Jigsaw-Startraum des Gooby-Baus (3 Sockets)
  * burrow/tunnel_straight         — gerader Gang (Plug + Far-Socket)
  * burrow/tunnel_corner           — Eck-Gang (Plug + Far-Socket)
  * burrow/den_small               — Kuschelkammer (Plug, terminal)
  * burrow/pantry                  — Vorratskammer mit Loot-Truhe (Plug, terminal)
  * burrow/end_cap                 — Terminator-Kappe, versiegelt offene Gaenge
  * picnic/gooby_picnic            — oberirdisches Gooby-Picknick mit Loot-Korb

Jigsaw-Konvention des Bau-Sets:
  Sockets (expandierende Anschluesse) heissen  goobymod:burrow_socket und
  zielen auf das Plug-Target goobymod:burrow_plug. Plugs (anschliessbare
  Enden) heissen goobymod:burrow_plug und expandieren nie (pool
  minecraft:empty). Kette: Startraum -> tunnel_pool -> den_pool; beide Pools
  fallen auf terminator_pool (end_cap) zurueck, damit jede offene Flaeche
  garantiert versiegelt wird.

  WICHTIG (Boundary-Regel): Jeder expandierende Socket muss auf der
  aeussersten Template-Schicht liegen, sodass seine Anschlussposition
  (Socket + Blickrichtung) AUSSERHALB der Bounding Box liegt. Sitzt der
  Socket auch nur eine Schicht tiefer, prueft Vanillas JigsawPlacement die
  Kind-Pieces im Innen-Expansionsmodus gegen die eigene Box — Tunnel und
  Kammern werden dann grundsaetzlich verworfen und jeder Socket sofort mit
  der Terminator-Kappe versiegelt. scripts/validate_worldgen.py erzwingt
  diese Regel.

  Optik: Alle Bau-Pieces tragen ein Grasdach auf der obersten Schicht und
  deterministisch gemischte Erd-Flanken (rooted/coarse dirt), damit die an
  der Oberflaeche liegenden Gaenge wie bewachsene Huegelruecken wirken.

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
GOOBY_STRUCTURES = os.path.join(DATA_ROOT, "goobymod", "structure")
DATA_VERSION = 3955  # Minecraft 1.21.1

ARENAS = {
    "arena.nbt": (5, 8, 5),
    "arena_large.nbt": (17, 10, 17),
}

BURROW_TUNNEL_POOL = "goobymod:burrow/tunnel_pool"
BURROW_DEN_POOL = "goobymod:burrow/den_pool"
BURROW_SOCKET = "goobymod:burrow_socket"
BURROW_PLUG = "goobymod:burrow_plug"
EMPTY_POOL = "minecraft:empty"


# ---------------------------------------------------------------------------
# Minimaler Big-Endian-NBT-Writer
# ---------------------------------------------------------------------------

def tag_name(s):
    b = s.encode("utf-8")
    return struct.pack(">H", len(b)) + b


def named(tag_type, name, payload):
    return bytes((tag_type,)) + tag_name(name) + payload


def int_tag(name, value):
    return named(3, name, struct.pack(">i", value))


def long_tag(name, value):
    return named(4, name, struct.pack(">q", value))


def byte_tag(name, value):
    return named(1, name, struct.pack(">b", value))


def string_tag(name, value):
    return named(8, name, tag_name(value))


def list_tag(name, element_type, payloads):
    return named(9, name, bytes((element_type,)) + struct.pack(">i", len(payloads)) + b"".join(payloads))


def compound_payload(entries):
    return b"".join(entries) + b"\x00"


def compound_tag(name, entries):
    return named(10, name, compound_payload(entries))


# ---------------------------------------------------------------------------
# Arena-Format der GameTest-Arenen (byte-identisch zu den bisherigen Dateien)
# ---------------------------------------------------------------------------

def build(size):
    buf = b"\x0a" + tag_name("")  # Root-Compound
    buf += b"\x03" + tag_name("DataVersion") + struct.pack(">i", DATA_VERSION)
    buf += b"\x09" + tag_name("size") + b"\x03" + struct.pack(">i", 3) + struct.pack(">iii", *size)
    buf += b"\x09" + tag_name("entities") + b"\x00" + struct.pack(">i", 0)
    buf += b"\x09" + tag_name("blocks") + b"\x00" + struct.pack(">i", 0)
    buf += b"\x09" + tag_name("palette") + b"\x00" + struct.pack(">i", 0)
    buf += b"\x00"  # End
    return buf


# ---------------------------------------------------------------------------
# Piece-Builder: Palette-Dedupe, Block-NBT, Jigsaws, Entities
# ---------------------------------------------------------------------------

class Piece:
    """Sammelt Bloecke/Entities und serialisiert sie als Vanilla-Template-NBT."""

    def __init__(self, size):
        self.size = size
        self._palette = []      # [(name, ((key, value), ...))]
        self._palette_index = {}
        self._blocks = {}       # (x, y, z) -> (state_index, nbt_entries|None)
        self._entities = []

    def _state(self, name, props=None):
        key = (name, tuple(sorted((props or {}).items())))
        if key not in self._palette_index:
            self._palette_index[key] = len(self._palette)
            self._palette.append(key)
        return self._palette_index[key]

    def put(self, x, y, z, name, props=None, nbt=None):
        sx, sy, sz = self.size
        if not (0 <= x < sx and 0 <= y < sy and 0 <= z < sz):
            raise ValueError(f"Block {name} ausserhalb der Groesse {self.size}: {(x, y, z)}")
        self._blocks[(x, y, z)] = (self._state(name, props), nbt)

    def fill(self, x0, y0, z0, x1, y1, z1, name, props=None):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.put(x, y, z, name, props)

    def jigsaw(self, x, y, z, facing, name, target, pool, final_state,
               placement_priority=0, selection_priority=0):
        self.put(x, y, z, "minecraft:jigsaw", {"orientation": f"{facing}_up"}, nbt=[
            string_tag("id", "minecraft:jigsaw"),
            string_tag("name", name),
            string_tag("target", target),
            string_tag("pool", pool),
            string_tag("final_state", final_state),
            string_tag("joint", "rollable"),
            int_tag("placement_priority", placement_priority),
            int_tag("selection_priority", selection_priority),
        ])

    def chest(self, x, y, z, loot_table, facing=None):
        props = {"facing": facing} if facing else None
        self.put(x, y, z, "minecraft:chest", props, nbt=[
            string_tag("id", "minecraft:chest"),
            string_tag("LootTable", loot_table),
            long_tag("LootTableSeed", 0),
        ])

    def entity(self, pos, entity_id, flags):
        x, y, z = pos
        nbt_entries = [string_tag("id", entity_id)]
        for flag in flags:
            nbt_entries.append(byte_tag(flag, 1))
        self._entities.append(compound_payload([
            list_tag("pos", 6, [struct.pack(">d", value) for value in (x, y, z)]),
            list_tag("blockPos", 3, [struct.pack(">i", int(value)) for value in (x, y, z)]),
            compound_tag("nbt", nbt_entries),
        ]))

    def build(self):
        palette = []
        for name, props in self._palette:
            entries = [string_tag("Name", name)]
            if props:
                entries.append(compound_tag(
                    "Properties", [string_tag(key, value) for key, value in props]))
            palette.append(compound_payload(entries))

        block_payloads = []
        for (x, y, z), (state, nbt) in sorted(
                self._blocks.items(), key=lambda entry: (entry[0][1], entry[0][2], entry[0][0])):
            entries = [
                list_tag("pos", 3, [struct.pack(">i", value) for value in (x, y, z)]),
                int_tag("state", state),
            ]
            if nbt:
                entries.append(compound_tag("nbt", nbt))
            block_payloads.append(compound_payload(entries))

        return (b"\x0a" + tag_name("")
                + int_tag("DataVersion", DATA_VERSION)
                + list_tag("size", 3, [struct.pack(">i", value) for value in self.size])
                + list_tag("palette", 10, palette)
                + list_tag("blocks", 10, block_payloads)
                + list_tag("entities", 10, self._entities)
                + b"\x00")


# ---------------------------------------------------------------------------
# Gooby-Bau: Startraum + Gang-/Kammer-Varianten + Terminator
# ---------------------------------------------------------------------------

def shell_block(x, y, z):
    """Deterministische Erd-Varianz fuer sichtbare Huegelflanken."""
    h = (x * 7 + y * 5 + z * 11) % 9
    if h == 0:
        return "minecraft:rooted_dirt"
    if h == 4:
        return "minecraft:coarse_dirt"
    return "minecraft:dirt"


def build_burrow():
    """Startraum 9x5x9: Grashuegel mit 7x7-Kammer, Sued-Eingang, Truhe,
    Bewohner und drei Jigsaw-Sockets (Ost/West/Nord) fuer das Gang-Set.

    Die Sockets liegen direkt in der Aussenwand auf der Bounding-Box-Grenze
    (x=0/8, z=0): nur so faellt ihre Anschlussposition aus der Box heraus
    und Kind-Pieces werden gegen den Struktur-Freiraum statt gegen die
    eigene Box geprueft (Boundary-Regel, siehe Modul-Docstring)."""
    piece = Piece((9, 5, 9))

    for x in range(9):
        for z in range(9):
            piece.put(x, 0, z, "minecraft:dirt")
    for y in range(1, 4):
        for x in range(9):
            for z in range(9):
                boundary = x in (0, 8) or z in (0, 8)
                piece.put(x, y, z, shell_block(x, y, z) if boundary else "minecraft:air")
    for x in range(9):
        for z in range(9):
            piece.put(x, 4, z, "minecraft:grass_block")

    # Sued-Eingang: 3 breit, 2 hoch durch die Aussenwand; das Grasdach
    # darueber bleibt stehen und bildet einen bewachsenen Bogen.
    for x in (3, 4, 5):
        for y in (1, 2):
            piece.put(x, y, 8, "minecraft:air")
    # Stuetzbalken in den Ecken der Kammer.
    for x, z in ((1, 1), (7, 1), (1, 7), (7, 7)):
        piece.put(x, 1, z, "minecraft:oak_planks")

    piece.chest(4, 1, 3, "goobymod:chests/gooby_burrow")

    # Drei Sockets in der Aussenwand; darueber je ein Luftblock als oberer
    # Teil des Durchgangs (der Socket selbst wird via final_state zu Luft).
    for x, y, z, facing in ((8, 1, 4, "east"), (0, 1, 4, "west"), (4, 1, 0, "north")):
        piece.jigsaw(x, y, z, facing, BURROW_SOCKET, BURROW_PLUG,
                     BURROW_TUNNEL_POOL, "minecraft:air")
        piece.put(x, y + 1, z, "minecraft:air")

    piece.entity((4.5, 1.0, 5.5), "goobymod:gooby",
                 ("BurrowResident", "ShyUntilFed", "PersistenceRequired"))
    return piece.build()


def build_tunnel_straight():
    """Gerader Gang 6x5x5 als grasbedeckter Erdruecken: Plug bei x0,
    expandierender Far-Socket bei x5 (beide auf der Box-Grenze)."""
    piece = Piece((6, 5, 5))
    for x in range(6):
        for z in range(5):
            piece.put(x, 0, z, "minecraft:dirt")
            piece.put(x, 4, z, "minecraft:grass_block")
            for y in range(1, 4):
                piece.put(x, y, z, shell_block(x, y, z))
    for x in range(6):
        for y in (1, 2):
            piece.put(x, y, 2, "minecraft:air")
    # Deckenstuetzen aus Eichenbrettern, Fackel in Gangmitte.
    piece.put(1, 3, 2, "minecraft:oak_planks")
    piece.put(4, 3, 2, "minecraft:oak_planks")
    piece.put(3, 1, 2, "minecraft:torch")

    piece.jigsaw(0, 1, 2, "west", BURROW_PLUG, BURROW_PLUG, EMPTY_POOL, "minecraft:air")
    piece.jigsaw(5, 1, 2, "east", BURROW_SOCKET, BURROW_PLUG,
                 BURROW_DEN_POOL, "minecraft:air")
    return piece.build()


def build_tunnel_corner():
    """Eck-Gang 5x5x5 als grasbedeckter Erdruecken: Plug bei x0/z2,
    Far-Socket bei x2/z4 (Knick nach Sueden, beide auf der Box-Grenze)."""
    piece = Piece((5, 5, 5))
    for x in range(5):
        for z in range(5):
            piece.put(x, 0, z, "minecraft:dirt")
            piece.put(x, 4, z, "minecraft:grass_block")
            for y in range(1, 4):
                piece.put(x, y, z, shell_block(x, y, z))
    for y in (1, 2):
        for x in (0, 1, 2):
            piece.put(x, y, 2, "minecraft:air")
        for z in (3, 4):
            piece.put(2, y, z, "minecraft:air")
    piece.put(2, 3, 2, "minecraft:oak_planks")
    piece.put(1, 0, 2, "minecraft:rooted_dirt")
    piece.put(2, 0, 3, "minecraft:rooted_dirt")

    piece.jigsaw(0, 1, 2, "west", BURROW_PLUG, BURROW_PLUG, EMPTY_POOL, "minecraft:air")
    piece.jigsaw(2, 1, 4, "south", BURROW_SOCKET, BURROW_PLUG,
                 BURROW_DEN_POOL, "minecraft:air")
    return piece.build()


def build_den_small():
    """Kuschelkammer 7x5x7 als bewachsener Huegel: Pluesch-Gooby, Woll-Nest,
    Heu und Fackel. Terminal."""
    piece = Piece((7, 5, 7))
    for x in range(7):
        for z in range(7):
            piece.put(x, 0, z, "minecraft:dirt")
            piece.put(x, 4, z, "minecraft:grass_block")
    for y in range(1, 4):
        for x in range(7):
            for z in range(7):
                boundary = x in (0, 6) or z in (0, 6)
                piece.put(x, y, z, shell_block(x, y, z) if boundary else "minecraft:air")

    piece.put(3, 1, 3, "goobymod:gooby_plushie",
              {"facing": "west", "waterlogged": "false"})
    piece.put(4, 1, 4, "goobymod:gooby_wool")
    piece.put(5, 1, 4, "goobymod:gooby_wool")
    piece.put(5, 1, 1, "minecraft:hay_block")
    piece.put(1, 1, 5, "minecraft:torch")

    piece.jigsaw(0, 1, 3, "west", BURROW_PLUG, BURROW_PLUG, EMPTY_POOL, "minecraft:air")
    piece.put(0, 2, 3, "minecraft:air")
    return piece.build()


def build_pantry():
    """Vorratskammer 7x5x7 als bewachsener Huegel: Loot-Truhe, Heustapel und
    Bretter-Regal. Terminal."""
    piece = Piece((7, 5, 7))
    for x in range(7):
        for z in range(7):
            piece.put(x, 0, z, "minecraft:dirt")
            piece.put(x, 4, z, "minecraft:grass_block")
    for y in range(1, 4):
        for x in range(7):
            for z in range(7):
                boundary = x in (0, 6) or z in (0, 6)
                piece.put(x, y, z, shell_block(x, y, z) if boundary else "minecraft:air")

    piece.chest(3, 1, 3, "goobymod:chests/gooby_burrow_pantry", facing="west")
    piece.put(1, 1, 1, "minecraft:hay_block")
    piece.put(1, 2, 1, "minecraft:hay_block")
    piece.put(2, 1, 1, "minecraft:hay_block")
    piece.put(5, 1, 1, "minecraft:oak_planks")
    piece.put(5, 1, 2, "minecraft:oak_planks")
    piece.put(5, 1, 5, "minecraft:torch")

    piece.jigsaw(0, 1, 3, "west", BURROW_PLUG, BURROW_PLUG, EMPTY_POOL, "minecraft:air")
    piece.put(0, 2, 3, "minecraft:air")
    return piece.build()


def build_end_cap():
    """Terminator 1x5x5: grasgekroente Erdscheibe, deren Plug sich selbst
    mit Erde versiegelt. Bewusst ohne Flanken-Varianz (Versiegelung)."""
    piece = Piece((1, 5, 5))
    piece.fill(0, 0, 0, 0, 3, 4, "minecraft:dirt")
    for z in range(5):
        piece.put(0, 4, z, "minecraft:grass_block")
    piece.jigsaw(0, 1, 2, "west", BURROW_PLUG, BURROW_PLUG, EMPTY_POOL, "minecraft:dirt")
    return piece.build()


# ---------------------------------------------------------------------------
# Gooby-Picknick: oberirdische Mini-Begegnung
# ---------------------------------------------------------------------------

def build_picnic():
    """Picknick 11x4x11: Karo-Decke, Kuchen, Pluesch-Gast, Statue, Heubaenke,
    Laterne und der Loot-Korb (Truhe). Ein scheuer Wild-Gooby schaut zu."""
    piece = Piece((11, 4, 11))
    for x in range(11):
        for z in range(11):
            piece.put(x, 0, z, "minecraft:grass_block")

    # 5x5-Karodecke aus Teppichen; Kuchen und Pluesch ersetzen je ein Feld.
    for x in range(3, 8):
        for z in range(3, 8):
            if (x, z) in ((5, 5), (4, 4)):
                continue
            carpet = "minecraft:white_carpet" if (x + z) % 2 == 0 else "minecraft:pink_carpet"
            piece.put(x, 1, z, carpet)
    piece.put(5, 1, 5, "minecraft:cake")
    piece.put(4, 1, 4, "goobymod:gooby_plushie",
              {"facing": "east", "waterlogged": "false"})

    # Sitzbereich, Denkmal, Licht und Picknickkorb.
    piece.put(2, 1, 2, "minecraft:hay_block")
    piece.put(8, 1, 2, "minecraft:hay_block")
    piece.put(8, 1, 8, "minecraft:hay_block")
    piece.put(8, 2, 8, "minecraft:lantern", {"hanging": "false"})
    piece.put(2, 1, 8, "goobymod:gooby_statue",
              {"facing": "east", "waterlogged": "false"})
    piece.chest(5, 1, 8, "goobymod:chests/gooby_picnic", facing="north")

    for x, z, flower in ((1, 5, "minecraft:dandelion"), (9, 4, "minecraft:poppy"),
                         (4, 9, "minecraft:dandelion"), (9, 9, "minecraft:poppy")):
        piece.put(x, 1, z, flower)

    piece.entity((5.5, 1.0, 2.5), "goobymod:gooby",
                 ("ShyUntilFed", "PersistenceRequired"))
    return piece.build()


# ---------------------------------------------------------------------------
# Schatzkammer (Inhalt unveraendert zur bisherigen Version)
# ---------------------------------------------------------------------------

def build_treasure_cache():
    """Kleine terrain-angepasste vergrabene Kammer mit garantierter Loot-Truhe."""
    piece = Piece((5, 4, 5))
    for y in range(4):
        for x in range(5):
            for z in range(5):
                boundary = y in (0, 3) or x in (0, 4) or z in (0, 4)
                if boundary:
                    mossy = (x * 7 + y * 5 + z * 11) % 6 == 0
                    piece.put(x, y, z,
                              "minecraft:mossy_stone_bricks" if mossy else "minecraft:stone_bricks")
                else:
                    piece.put(x, y, z, "minecraft:air")
    piece.chest(2, 1, 2, "goobymod:chests/gooby_treasure_cache")
    for x in range(5):
        for z in range(5):
            piece.put(x, 3, z, "minecraft:dirt")
    return piece.build()


# Ausgabepfad (relativ zu data/goobymod/structure) -> Builder.
PIECES = {
    # Grosse leere Arena fuer den End-to-End-Jigsaw-Assembly-GameTest:
    # 48x48 deckt Hub (9) + Tunnel (6) + Kammer (7) in jeder Richtung ab,
    # inklusive zufaelliger Start-Rotation und Socket-Anker (+/-22 Bloecke).
    "arena_worldgen.nbt": lambda: build((48, 10, 48)),
    os.path.join("burrow", "gooby_burrow.nbt"): build_burrow,
    os.path.join("burrow", "tunnel_straight.nbt"): build_tunnel_straight,
    os.path.join("burrow", "tunnel_corner.nbt"): build_tunnel_corner,
    os.path.join("burrow", "den_small.nbt"): build_den_small,
    os.path.join("burrow", "pantry.nbt"): build_pantry,
    os.path.join("burrow", "end_cap.nbt"): build_end_cap,
    os.path.join("picnic", "gooby_picnic.nbt"): build_picnic,
    os.path.join("treasure_cache", "gooby_treasure_cache.nbt"): build_treasure_cache,
}


def write_gzip(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with gzip.GzipFile(filename=path, mode="wb", mtime=0) as f:
        f.write(payload)
    print("Struktur geschrieben:", path)


if __name__ == "__main__":
    for base in BASES:
        os.makedirs(base, exist_ok=True)
        for name, size in ARENAS.items():
            write_gzip(os.path.join(base, name), build(size))
    for rel_path, builder in PIECES.items():
        write_gzip(os.path.join(GOOBY_STRUCTURES, rel_path), builder())
