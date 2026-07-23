"""Anvil (.mca) region file reader/writer - stdlib only, deterministic output.

Reader accepts any vanilla-produced region file (zlib/gzip/uncompressed chunk
payloads). Writer always emits zlib level-9 payloads, chunks laid out in sorted
(z, x) order starting at sector 2, all timestamps zeroed - so identical input
chunks always produce byte-identical region files (idempotent re-bake).
"""

from __future__ import annotations

import os
import re
import struct
import zlib

from . import nbt

SECTOR = 4096
_NAME_RE = re.compile(r"^r\.(-?\d+)\.(-?\d+)\.mca$")


class RegionError(ValueError):
    pass


def region_coords_from_name(filename: str) -> tuple[int, int]:
    m = _NAME_RE.match(os.path.basename(filename))
    if not m:
        raise RegionError(f"not a region file name: {filename}")
    return int(m.group(1)), int(m.group(2))


def region_file_name(rx: int, rz: int) -> str:
    return f"r.{rx}.{rz}.mca"


class RegionReader:
    """Reads all chunks of one region file into memory."""

    def __init__(self, path: str):
        self.path = path
        self.rx, self.rz = region_coords_from_name(path)
        with open(path, "rb") as f:
            self.data = f.read()
        if len(self.data) == 0:
            self.offsets = b""
            return
        if len(self.data) < 2 * SECTOR:
            raise RegionError(f"{path}: truncated region header")
        self.offsets = self.data[:SECTOR]

    def chunks(self):
        """Yields (local_x, local_z, raw_nbt_bytes) for every present chunk."""
        if not self.offsets:
            return
        for lz in range(32):
            for lx in range(32):
                idx = 4 * (lx + 32 * lz)
                entry = self.offsets[idx:idx + 4]
                sector_off = (entry[0] << 16) | (entry[1] << 8) | entry[2]
                sector_cnt = entry[3]
                if sector_off == 0 and sector_cnt == 0:
                    continue
                start = sector_off * SECTOR
                if start + 5 > len(self.data):
                    raise RegionError(f"{self.path}: chunk ({lx},{lz}) points past EOF")
                (length,) = struct.unpack(">i", self.data[start:start + 4])
                comp = self.data[start + 4]
                if comp & 0x80:
                    raise RegionError(
                        f"{self.path}: chunk ({lx},{lz}) is oversized/external (.mcc) - unsupported")
                payload = self.data[start + 5:start + 4 + length]
                yield lx, lz, nbt.decompress_chunk(payload, comp)

    def chunk_positions(self) -> list[tuple[int, int]]:
        return [(lx, lz) for lx, lz, _ in self.chunks()]


def write_region(path: str, chunk_map: dict[tuple[int, int], bytes]) -> None:
    """chunk_map: {(local_x, local_z): raw uncompressed NBT bytes}."""
    if not chunk_map:
        raise RegionError("refusing to write an empty region file")
    offsets = bytearray(SECTOR)
    timestamps = bytes(SECTOR)  # all zero -> deterministic
    body = bytearray()
    next_sector = 2
    for (lx, lz) in sorted(chunk_map.keys(), key=lambda p: (p[1], p[0])):
        if not (0 <= lx < 32 and 0 <= lz < 32):
            raise RegionError(f"chunk local coords out of range: ({lx},{lz})")
        compressed = zlib.compress(chunk_map[(lx, lz)], 9)
        record = struct.pack(">ib", len(compressed) + 1, 2) + compressed
        sectors = (len(record) + SECTOR - 1) // SECTOR
        if sectors > 255:
            raise RegionError(f"chunk ({lx},{lz}) too large for in-file storage")
        record += bytes(sectors * SECTOR - len(record))
        idx = 4 * (lx + 32 * lz)
        offsets[idx] = (next_sector >> 16) & 0xFF
        offsets[idx + 1] = (next_sector >> 8) & 0xFF
        offsets[idx + 2] = next_sector & 0xFF
        offsets[idx + 3] = sectors
        body += record
        next_sector += sectors
    with open(path, "wb") as f:
        f.write(bytes(offsets))
        f.write(timestamps)
        f.write(bytes(body))


def iter_world_chunks(region_dir: str):
    """Yields (chunk_x, chunk_z, raw_nbt_bytes) across all region files in a dir."""
    for name in sorted(os.listdir(region_dir)):
        if not name.endswith(".mca"):
            continue
        path = os.path.join(region_dir, name)
        if os.path.getsize(path) == 0:
            continue
        reader = RegionReader(path)
        for lx, lz, raw in reader.chunks():
            yield reader.rx * 32 + lx, reader.rz * 32 + lz, raw
