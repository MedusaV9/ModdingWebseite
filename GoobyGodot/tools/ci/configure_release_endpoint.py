#!/usr/bin/env python3
"""Validate and inject the public WSS endpoint used by release builds."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

BLOCKED_NAMES = {"localhost", "example.com", "example.net", "example.org"}
BLOCKED_SUFFIXES = (
    ".local",
    ".localhost",
    ".test",
    ".invalid",
    ".example",
    ".example.com",
    ".example.net",
    ".example.org",
)
DNS_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def _validate_host(host: str) -> None:
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        try:
            host.encode("ascii")
        except UnicodeEncodeError as error:
            raise ValueError("Release-Endpunkt braucht einen ASCII-DNS-Namen") from error
        labels = host.split(".")
        if len(host) > 253 or len(labels) < 2 or any(
            not DNS_LABEL.fullmatch(label) for label in labels
        ):
            raise ValueError(f"Release-Endpunkt ist kein gültiger öffentlicher DNS-Name: {host}")
    else:
        if address.version != 4:
            raise ValueError("IPv6-Literale werden nicht unterstützt; öffentlichen DNS-Namen nutzen")
        if not address.is_global:
            raise ValueError(f"Release-Endpunkt ist keine öffentliche IP: {host}")


def parse_endpoint(endpoint: str) -> dict[str, object]:
    value = endpoint.strip()
    if not value:
        raise ValueError("GOOBY_RELEASE_WSS_URL fehlt")
    parsed = urlsplit(value)
    if parsed.scheme.lower() != "wss":
        raise ValueError("Release-Endpunkt muss wss:// verwenden")
    if parsed.username or parsed.password:
        raise ValueError("Release-Endpunkt darf keine Zugangsdaten in der URL tragen")
    if parsed.query or parsed.fragment:
        raise ValueError("Release-Endpunkt darf keinen Query oder Fragment tragen")
    if parsed.path not in ("", "/", "/ws"):
        raise ValueError("Release-Endpunkt darf nur den WebSocket-Pfad /ws verwenden")
    host = (parsed.hostname or "").strip().lower().rstrip(".")
    if not host:
        raise ValueError("Release-Endpunkt hat keinen Host")
    if host in BLOCKED_NAMES or host.endswith(BLOCKED_SUFFIXES):
        raise ValueError(f"Release-Endpunkt ist lokal/reserviert: {host}")
    _validate_host(host)
    if parsed.netloc.endswith(":"):
        raise ValueError("Release-Endpunkt hat einen leeren Port")
    try:
        port = parsed.port or 443
    except ValueError as error:
        raise ValueError("Release-Endpunkt hat einen ungültigen Port") from error
    if not 1 <= port <= 65535:
        raise ValueError(f"Release-Endpunkt-Port außerhalb 1..65535: {port}")
    return {"host": host, "port": port, "tls": True}


def release_requested(github_ref: str, input_version: str) -> bool:
    return github_ref.startswith("refs/tags/ipa-v") or bool(input_version.strip())


def validate_embedded_config(config_file: Path) -> dict[str, object]:
    payload = json.loads(config_file.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON-Wurzel in {config_file} muss ein Objekt sein")
    net = payload.get("net")
    if not isinstance(net, dict):
        raise ValueError(f"net-Objekt fehlt in {config_file}")
    host = str(net.get("host", "")).strip()
    try:
        port = int(net.get("port", 0))
    except (TypeError, ValueError) as error:
        raise ValueError("Eingebetteter Netz-Port ist ungültig") from error
    if not host:
        if port != 443 or net.get("tls") is not True:
            raise ValueError("Unkonfigurierter Netz-Default muss host='', port=443, tls=true sein")
        return {"host": "", "port": 443, "tls": True}
    scheme = "wss" if net.get("tls") is True else "ws"
    return parse_endpoint(f"{scheme}://{host}:{port}/ws")


def write_endpoint(config_file: Path, endpoint: str) -> dict[str, object]:
    net = parse_endpoint(endpoint)
    payload = json.loads(config_file.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON-Wurzel in {config_file} muss ein Objekt sein")
    payload["net"] = net
    config_file.write_text(
        json.dumps(payload, ensure_ascii=False, indent="\t") + "\n",
        encoding="utf-8",
    )
    return net


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--config",
        default="GOOBY-GODOT/content/config/data/config.json",
        type=Path,
    )
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    endpoint = os.environ.get("GOOBY_RELEASE_WSS_URL", "").strip()
    requested = release_requested(
        os.environ.get("GITHUB_REF", ""),
        os.environ.get("INPUT_VERSION", ""),
    )
    try:
        embedded = validate_embedded_config(args.config)
        if endpoint:
            parsed = parse_endpoint(endpoint)
        else:
            parsed = {}
        if requested and not parsed:
            raise ValueError("Release angefordert, aber GOOBY_RELEASE_WSS_URL fehlt")
        if requested and args.write:
            embedded = write_endpoint(args.config, endpoint)
        elif requested:
            embedded = parsed
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"RELEASE-WSS ROT: {error}")
        return 1

    if requested:
        action = "eingebettet" if args.write else "validiert"
        print(
            f"RELEASE-WSS PASS: wss://{embedded['host']}:{embedded['port']}/ws {action}"
        )
    elif endpoint:
        print(
            f"RELEASE-WSS PASS: Release-Variable valid "
            f"(wss://{parsed['host']}:{parsed['port']}/ws); normaler Build bleibt unverändert"
        )
    else:
        print("RELEASE-WSS PASS: normaler Build bleibt ehrlich unkonfiguriert")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
