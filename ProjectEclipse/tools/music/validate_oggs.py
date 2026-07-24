#!/usr/bin/env python3
"""Validates the shipped Eclipse music assets (C19 guard).

Every ``music.*`` entry in assets/eclipse/sounds.json must resolve to an existing OGG
under assets/eclipse/sounds/, and every referenced file must be a Minecraft-playable
stream: a single logical Ogg stream, codec Vorbis (NOT Theora video, NOT Opus — the
engine cannot decode either), sample rate <= 48 kHz, stereo, within the size budget.
Only Ogg page/identification headers are parsed — no audio decode, no dependencies.

Usage (from ProjectEclipse/):
  python3 tools/music/validate_oggs.py            # validate assets tree via sounds.json
  python3 tools/music/validate_oggs.py FILE...    # validate specific .ogg files

Exit code 0 = all good, 1 = at least one violation. Run this after any
tools/music/treblo_generate.py install and before committing new music.
"""
import json
import struct
import sys
from pathlib import Path

MAX_SAMPLE_RATE = 48000
REQUIRED_CHANNELS = 2
SIZE_BUDGET_BYTES = 2_500_000  # keep in sync with treblo_generate.SIZE_BUDGET_BYTES

REPO = Path(__file__).resolve().parents[2]
ASSETS = REPO / "src/main/resources/assets/eclipse"


def parse_ogg_streams(path):
    """Yields (serial, first_packet_prefix) for every BOS (beginning-of-stream) page."""
    data = path.read_bytes()
    offset = 0
    streams = []
    while offset + 27 <= len(data):
        if data[offset:offset + 4] != b"OggS":
            raise ValueError(f"bad Ogg capture pattern at byte {offset:,}")
        header_type = data[offset + 5]
        serial = struct.unpack_from("<I", data, offset + 14)[0]
        segments = data[offset + 26]
        table = data[offset + 27:offset + 27 + segments]
        body_len = sum(table)
        body = data[offset + 27 + segments:offset + 27 + segments + body_len]
        if header_type & 0x02:  # BOS page: body starts with the codec id header
            streams.append((serial, bytes(body[:16])))
        offset += 27 + segments + body_len
        if len(streams) > 0 and not header_type & 0x02 and len(streams) >= 4:
            break  # BOS pages must be first; no need to scan the whole file
    return streams


def vorbis_id(prefix, path):
    """Returns (sample_rate, channels) from a Vorbis identification header prefix."""
    # \x01 + "vorbis" + version(u32) + channels(u8) + sample_rate(u32), little-endian.
    channels = prefix[11]
    sample_rate = struct.unpack_from("<I", prefix, 12)[0]
    return sample_rate, channels


def validate_file(path):
    errors = []
    size = path.stat().st_size
    if size > SIZE_BUDGET_BYTES:
        errors.append(f"{size:,} bytes exceeds the {SIZE_BUDGET_BYTES:,}-byte budget")
    try:
        streams = parse_ogg_streams(path)
    except ValueError as err:
        return [str(err)]
    if not streams:
        return ["no Ogg streams found"]
    codecs = []
    for _, prefix in streams:
        if prefix.startswith(b"\x01vorbis"):
            codecs.append("vorbis")
        elif prefix.startswith(b"\x80theora"):
            codecs.append("THEORA VIDEO")
        elif prefix.startswith(b"OpusHead"):
            codecs.append("OPUS")
        else:
            codecs.append(f"unknown({prefix[:8]!r})")
    if len(streams) != 1 or codecs != ["vorbis"]:
        errors.append(f"expected exactly one Vorbis stream, found: {', '.join(codecs)}")
    else:
        sample_rate, channels = vorbis_id(streams[0][1], path)
        if sample_rate > MAX_SAMPLE_RATE:
            errors.append(f"sample rate {sample_rate} Hz > {MAX_SAMPLE_RATE} Hz "
                          "(raw generation-API download?)")
        if channels != REQUIRED_CHANNELS:
            errors.append(f"{channels} channel(s), expected stereo")
    return errors


def music_files_from_sounds_json():
    """Every OGG referenced by a music.* sounds.json entry, keyed by event id."""
    sounds = json.loads((ASSETS / "sounds.json").read_text())
    out = {}
    for event, definition in sounds.items():
        if not event.startswith("music."):
            continue
        for entry in definition.get("sounds", []):
            name = entry["name"] if isinstance(entry, dict) else entry
            rel = name.split(":", 1)[-1]
            out.setdefault(event, []).append(ASSETS / "sounds" / f"{rel}.ogg")
    return out


def main(argv):
    failures = 0
    if len(argv) > 1:
        targets = {f"file:{arg}": [Path(arg)] for arg in argv[1:]}
    else:
        targets = music_files_from_sounds_json()
    for label in sorted(targets):
        for path in targets[label]:
            if not path.is_file():
                print(f"FAIL {label}: missing file {path}")
                failures += 1
                continue
            errors = validate_file(path)
            if errors:
                failures += 1
                print(f"FAIL {label} ({path.name}): " + "; ".join(errors))
            else:
                print(f"ok   {label} ({path.name})")
    if failures:
        print(f"\n{failures} violation(s).")
        return 1
    print(f"\nAll {sum(len(v) for v in targets.values())} file(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
