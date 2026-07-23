"""Minimal, dependency-free Java-edition NBT reader/writer.

Design goals for the Eclipse Xbox world pipeline (P5-W7):
  * exact round-trip fidelity (numeric tag widths preserved via wrapper types,
    string bytes preserved via surrogateescape so Java modified-UTF-8 oddities
    survive a read->write cycle byte-identically),
  * deterministic output (insertion order of compounds is preserved; gzip
    writers use mtime=0),
  * no third-party dependencies (reproducible on any stock Python 3.10+).

Only the features needed for 1.21.1 world data are implemented. Unknown or
malformed data fails loudly - this tool must never silently corrupt a world.
"""

from __future__ import annotations

import gzip
import io
import struct
import zlib

TAG_END = 0
TAG_BYTE = 1
TAG_SHORT = 2
TAG_INT = 3
TAG_LONG = 4
TAG_FLOAT = 5
TAG_DOUBLE = 6
TAG_BYTE_ARRAY = 7
TAG_STRING = 8
TAG_LIST = 9
TAG_COMPOUND = 10
TAG_INT_ARRAY = 11
TAG_LONG_ARRAY = 12


# --- typed value wrappers (exact type() dispatch keeps byte/short/int/long distinct) ---

class Byte(int):
    __slots__ = ()


class Short(int):
    __slots__ = ()


class Int(int):
    __slots__ = ()


class Long(int):
    __slots__ = ()


class Float(float):
    __slots__ = ()


class Double(float):
    __slots__ = ()


class ByteArray(bytes):
    __slots__ = ()


class IntArray(list):
    __slots__ = ()


class LongArray(list):
    __slots__ = ()


class TagList(list):
    """NBT list; `item_type` is the element tag id (TAG_END for empty lists)."""

    __slots__ = ("item_type",)

    def __init__(self, item_type: int = TAG_END, iterable=()):
        super().__init__(iterable)
        self.item_type = item_type


class Compound(dict):
    __slots__ = ()


_STRUCT_BY_TAG = {
    TAG_BYTE: struct.Struct(">b"),
    TAG_SHORT: struct.Struct(">h"),
    TAG_INT: struct.Struct(">i"),
    TAG_LONG: struct.Struct(">q"),
    TAG_FLOAT: struct.Struct(">f"),
    TAG_DOUBLE: struct.Struct(">d"),
}

_WRAP_BY_TAG = {
    TAG_BYTE: Byte,
    TAG_SHORT: Short,
    TAG_INT: Int,
    TAG_LONG: Long,
    TAG_FLOAT: Float,
    TAG_DOUBLE: Double,
}


class NbtError(ValueError):
    pass


# ------------------------------- reading -------------------------------

class _Reader:
    __slots__ = ("buf", "pos")

    def __init__(self, buf: bytes):
        self.buf = buf
        self.pos = 0

    def _take(self, n: int) -> bytes:
        b = self.buf[self.pos:self.pos + n]
        if len(b) != n:
            raise NbtError(f"unexpected end of NBT data at offset {self.pos}")
        self.pos += n
        return b

    def read_string(self) -> str:
        (n,) = struct.unpack(">H", self._take(2))
        raw = self._take(n)
        # surrogateescape keeps Java modified-UTF-8 bytes reversible.
        return raw.decode("utf-8", "surrogateescape")

    def read_payload(self, tag: int):
        if tag in _STRUCT_BY_TAG:
            st = _STRUCT_BY_TAG[tag]
            (v,) = st.unpack(self._take(st.size))
            return _WRAP_BY_TAG[tag](v)
        if tag == TAG_STRING:
            return self.read_string()
        if tag == TAG_BYTE_ARRAY:
            (n,) = struct.unpack(">i", self._take(4))
            return ByteArray(self._take(n))
        if tag == TAG_INT_ARRAY:
            (n,) = struct.unpack(">i", self._take(4))
            return IntArray(struct.unpack(f">{n}i", self._take(4 * n)))
        if tag == TAG_LONG_ARRAY:
            (n,) = struct.unpack(">i", self._take(4))
            return LongArray(struct.unpack(f">{n}q", self._take(8 * n)))
        if tag == TAG_LIST:
            item_type = self._take(1)[0]
            (n,) = struct.unpack(">i", self._take(4))
            out = TagList(item_type)
            append = out.append
            for _ in range(n):
                append(self.read_payload(item_type))
            return out
        if tag == TAG_COMPOUND:
            out = Compound()
            while True:
                t = self._take(1)[0]
                if t == TAG_END:
                    return out
                name = self.read_string()
                out[name] = self.read_payload(t)
        raise NbtError(f"unknown tag id {tag} at offset {self.pos}")


def loads(data: bytes) -> tuple[str, Compound]:
    """Parse an uncompressed NBT blob; returns (root_name, root_compound)."""
    r = _Reader(data)
    t = r._take(1)[0]
    if t != TAG_COMPOUND:
        raise NbtError(f"root tag must be a compound, got {t}")
    name = r.read_string()
    root = r.read_payload(TAG_COMPOUND)
    return name, root


# ------------------------------- writing -------------------------------

def _tag_of(value) -> int:
    t = type(value)
    if t is Byte:
        return TAG_BYTE
    if t is Short:
        return TAG_SHORT
    if t is Int:
        return TAG_INT
    if t is Long:
        return TAG_LONG
    if t is Float:
        return TAG_FLOAT
    if t is Double:
        return TAG_DOUBLE
    if t is str:
        return TAG_STRING
    if t is ByteArray:
        return TAG_BYTE_ARRAY
    if t is IntArray:
        return TAG_INT_ARRAY
    if t is LongArray:
        return TAG_LONG_ARRAY
    if t is TagList:
        return TAG_LIST
    if t is Compound:
        return TAG_COMPOUND
    raise NbtError(f"cannot serialize python type {t!r} - use the nbt wrapper types")


def _write_string(out: bytearray, s: str) -> None:
    raw = s.encode("utf-8", "surrogateescape")
    if len(raw) > 0xFFFF:
        raise NbtError("string too long for NBT")
    out += struct.pack(">H", len(raw))
    out += raw


def _write_payload(out: bytearray, tag: int, value) -> None:
    if tag in _STRUCT_BY_TAG:
        out += _STRUCT_BY_TAG[tag].pack(value)
        return
    if tag == TAG_STRING:
        _write_string(out, value)
        return
    if tag == TAG_BYTE_ARRAY:
        out += struct.pack(">i", len(value))
        out += value
        return
    if tag == TAG_INT_ARRAY:
        out += struct.pack(f">i{len(value)}i", len(value), *value)
        return
    if tag == TAG_LONG_ARRAY:
        out += struct.pack(f">i{len(value)}q", len(value), *value)
        return
    if tag == TAG_LIST:
        item_type = value.item_type if len(value) == 0 else _tag_of(value[0])
        for item in value:
            if _tag_of(item) != item_type:
                raise NbtError("heterogeneous NBT list")
        out += bytes((item_type,))
        out += struct.pack(">i", len(value))
        for item in value:
            _write_payload(out, item_type, item)
        return
    if tag == TAG_COMPOUND:
        for name, item in value.items():
            t = _tag_of(item)
            out += bytes((t,))
            _write_string(out, name)
            _write_payload(out, t, item)
        out += b"\x00"
        return
    raise NbtError(f"unknown tag id {tag}")


def dumps(root: Compound, root_name: str = "") -> bytes:
    out = bytearray()
    out += bytes((TAG_COMPOUND,))
    _write_string(out, root_name)
    _write_payload(out, TAG_COMPOUND, root)
    return bytes(out)


# ------------------------------- file helpers -------------------------------

def load_gzipped(path) -> tuple[str, Compound]:
    with gzip.open(path, "rb") as f:
        return loads(f.read())


def save_gzipped(path, root: Compound, root_name: str = "") -> None:
    raw = dumps(root, root_name)
    buf = io.BytesIO()
    # mtime=0 => deterministic output bytes for identical input (idempotent re-bake).
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=9, mtime=0) as gz:
        gz.write(raw)
    with open(path, "wb") as f:
        f.write(buf.getvalue())


def decompress_chunk(payload: bytes, compression: int) -> bytes:
    if compression == 2:
        return zlib.decompress(payload)
    if compression == 1:
        return gzip.decompress(payload)
    if compression == 3:
        return payload
    raise NbtError(f"unsupported region chunk compression id {compression} "
                   "(4=lz4/127=custom are not produced by vanilla saves)")


# ------------------------------- debug dump -------------------------------

def to_debug(value, max_seq: int = 24):
    """Lossy python-native view for pretty-printing / JSON reports."""
    t = type(value)
    if t in (Byte, Short, Int, Long):
        return int(value)
    if t in (Float, Double):
        return float(value)
    if t is str:
        return value
    if t is ByteArray:
        head = list(value[:max_seq])
        return {"<byte_array>": len(value), "head": head}
    if t in (IntArray, LongArray):
        name = "<int_array>" if t is IntArray else "<long_array>"
        return {name: len(value), "head": list(value[:max_seq])}
    if t is TagList:
        return [to_debug(v, max_seq) for v in value]
    if t is Compound:
        return {k: to_debug(v, max_seq) for k, v in value.items()}
    raise NbtError(f"unexpected type {t!r}")
