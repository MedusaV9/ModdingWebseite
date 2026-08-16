#!/usr/bin/env python3
"""Minimaler RCON-Client fuer Test-Automatisierung des Dev-Servers."""
import socket
import struct
import sys
import time


def _pack(req_id, ptype, payload):
    data = struct.pack('<ii', req_id, ptype) + payload.encode('utf-8') + b'\x00\x00'
    return struct.pack('<i', len(data)) + data


def _recv_packet(sock):
    raw_len = sock.recv(4)
    if len(raw_len) < 4:
        return None, None, ''
    (length,) = struct.unpack('<i', raw_len)
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    req_id, ptype = struct.unpack('<ii', data[:8])
    payload = data[8:-2].decode('utf-8', errors='replace')
    return req_id, ptype, payload


def run_commands(host, port, password, commands, delay=0.3):
    sock = socket.create_connection((host, port), timeout=10)
    sock.sendall(_pack(1, 3, password))
    req_id, _, _ = _recv_packet(sock)
    if req_id == -1:
        print('AUTH FAILED')
        return 1
    for cmd in commands:
        if cmd.startswith('SLEEP '):
            time.sleep(float(cmd.split()[1]))
            continue
        sock.sendall(_pack(2, 2, cmd))
        _, _, payload = _recv_packet(sock)
        print(f'> {cmd}\n{payload}')
        time.sleep(delay)
    sock.close()
    return 0


if __name__ == '__main__':
    import os
    port = int(os.environ.get('RCON_PORT', '26575'))
    cmds = [line.strip() for line in sys.stdin if line.strip()]
    sys.exit(run_commands('127.0.0.1', port, os.environ.get('RCON_PW', 'goobytest'), cmds))
