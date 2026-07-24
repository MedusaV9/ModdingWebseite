#!/usr/bin/env python3
"""Minimal RCON client for dev smoke-tests.
Usage: python3 tools/rcon/rcon.py "<command>" ["<command>" ...]
"""
import socket
import struct
import sys

HOST, PORT, PASSWORD = "127.0.0.1", 25575, "eclipsedev"


def send_packet(sock, req_id, ptype, payload):
    data = struct.pack("<ii", req_id, ptype) + payload.encode("utf-8") + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(data)) + data)


def read_packet(sock):
    raw_len = sock.recv(4)
    if len(raw_len) < 4:
        return None, None, ""
    (length,) = struct.unpack("<i", raw_len)
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    req_id, ptype = struct.unpack("<ii", data[:8])
    return req_id, ptype, data[8:-2].decode("utf-8", errors="replace")


def main():
    commands = sys.argv[1:]
    with socket.create_connection((HOST, PORT), timeout=15) as sock:
        send_packet(sock, 1, 3, PASSWORD)
        req_id, _, _ = read_packet(sock)
        if req_id == -1:
            print("AUTH FAILED")
            return 1
        for i, cmd in enumerate(commands, start=2):
            send_packet(sock, i, 2, cmd)
            _, _, body = read_packet(sock)
            print(f"$ {cmd}\n{body}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
