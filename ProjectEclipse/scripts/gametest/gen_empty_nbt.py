#!/usr/bin/env python3
"""Generate the minimal 1×1×1 empty GameTest structure."""

from __future__ import annotations

import gzip
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "src/main/resources/data/eclipse/structure/gametest/empty.nbt"


def named(tag_type: int, name: str, payload: bytes) -> bytes:
    encoded = name.encode("utf-8")
    return bytes((tag_type,)) + struct.pack(">H", len(encoded)) + encoded + payload


def empty_compound_list(name: str) -> bytes:
    return named(9, name, bytes((10,)) + struct.pack(">i", 0))


def main() -> None:
    size = bytes((3,)) + struct.pack(">i", 3) + struct.pack(">iii", 1, 1, 1)
    root_payload = b"".join(
        (
            named(3, "DataVersion", struct.pack(">i", 3955)),
            named(9, "size", size),
            empty_compound_list("entities"),
            empty_compound_list("blocks"),
            empty_compound_list("palette"),
            b"\x00",
        )
    )
    raw = named(10, "", root_payload)
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    assert gzip.decompress(compressed) == raw
    assert raw.startswith(b"\x0a\x00\x00") and raw.endswith(b"\x00")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(compressed)
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({len(compressed)} bytes)")


if __name__ == "__main__":
    main()
