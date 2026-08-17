#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("configure_release_endpoint.py")
SPEC = importlib.util.spec_from_file_location("configure_release_endpoint", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ConfigureReleaseEndpointTests(unittest.TestCase):
    def test_public_wss_endpoint_is_normalized(self) -> None:
        self.assertEqual(
            MODULE.parse_endpoint("wss://play.gooby-game.de:8443/ws"),
            {"host": "play.gooby-game.de", "port": 8443, "tls": True},
        )
        self.assertEqual(
            MODULE.parse_endpoint("wss://play.gooby-game.de"),
            {"host": "play.gooby-game.de", "port": 443, "tls": True},
        )

    def test_insecure_local_private_and_placeholder_endpoints_fail(self) -> None:
        rejected = [
            "ws://play.gooby-game.de/ws",
            "wss://localhost/ws",
            "wss://127.0.0.1/ws",
            "wss://10.2.3.4/ws",
            "wss://[2a01:4f8::1]/ws",
            "wss://gooby.local/ws",
            "wss://gooby.example/ws",
            "wss://play.example.org/ws",
            "wss://shortname/ws",
            "wss://bad host.example.com/ws",
            "wss://user:secret@play.gooby-game.de/ws",
            "wss://play.gooby-game.de/private",
            "wss://play.gooby-game.de/ws?token=secret",
        ]
        for endpoint in rejected:
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError):
                MODULE.parse_endpoint(endpoint)

    def test_release_detection_covers_tag_and_dispatch(self) -> None:
        self.assertTrue(MODULE.release_requested("refs/tags/ipa-v5.1.0", ""))
        self.assertTrue(MODULE.release_requested("refs/heads/main", "5.1.0"))
        self.assertFalse(MODULE.release_requested("refs/heads/main", ""))

    def test_write_replaces_only_net_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "config.json")
            config.write_text(
                json.dumps(
                    {
                        "schema": 1,
                        "manifest_url": "https://updates.gooby.example.com/manifest",
                        "net": {"host": "", "port": 443, "tls": True},
                        "flags": {"keep": True},
                    }
                ),
                encoding="utf-8",
            )
            net = MODULE.write_endpoint(config, "wss://play.gooby-game.de/ws")
            written = json.loads(config.read_text(encoding="utf-8"))
            self.assertEqual(
                net,
                {"host": "play.gooby-game.de", "port": 443, "tls": True},
            )
            self.assertEqual(written["net"], net)
            self.assertEqual(written["flags"], {"keep": True})
            self.assertEqual(
                written["manifest_url"],
                "https://updates.gooby.example.com/manifest",
            )

    def test_embedded_development_default_is_offline_not_loopback(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "config.json")
            config.write_text(
                json.dumps({"schema": 1, "net": {"host": "", "port": 443, "tls": True}}),
                encoding="utf-8",
            )
            self.assertEqual(
                MODULE.validate_embedded_config(config),
                {"host": "", "port": 443, "tls": True},
            )

    def test_release_cli_fails_closed_without_endpoint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "config.json")
            config.write_text(
                json.dumps({"schema": 1, "net": {"host": "", "port": 443, "tls": True}}),
                encoding="utf-8",
            )
            with (
                mock.patch.dict(
                    os.environ,
                    {"GITHUB_REF": "refs/tags/ipa-v5.1.0"},
                    clear=True,
                ),
                mock.patch.object(
                    sys,
                    "argv",
                    ["configure_release_endpoint.py", "--config", str(config)],
                ),
            ):
                self.assertEqual(MODULE.main(), 1)

    def test_release_cli_writes_public_endpoint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "config.json")
            original = {"schema": 1, "net": {"host": "", "port": 443, "tls": True}, "keep": 7}
            config.write_text(json.dumps(original), encoding="utf-8")
            with (
                mock.patch.dict(
                    os.environ,
                    {
                        "GITHUB_REF": "refs/tags/ipa-v5.1.0",
                        "GOOBY_RELEASE_WSS_URL": "wss://play.gooby-game.de/ws",
                    },
                    clear=True,
                ),
                mock.patch.object(
                    sys,
                    "argv",
                    ["configure_release_endpoint.py", "--config", str(config), "--write"],
                ),
            ):
                self.assertEqual(MODULE.main(), 0)
            written = json.loads(config.read_text(encoding="utf-8"))
            self.assertEqual(
                written["net"],
                {"host": "play.gooby-game.de", "port": 443, "tls": True},
            )
            self.assertEqual(written["keep"], 7)

    def test_normal_build_never_embeds_configured_release_variable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "config.json")
            original = {"schema": 1, "net": {"host": "", "port": 443, "tls": True}}
            config.write_text(json.dumps(original), encoding="utf-8")
            with (
                mock.patch.dict(
                    os.environ,
                    {
                        "GITHUB_REF": "refs/heads/feature",
                        "GOOBY_RELEASE_WSS_URL": "wss://play.gooby-game.de/ws",
                    },
                    clear=True,
                ),
                mock.patch.object(
                    sys,
                    "argv",
                    ["configure_release_endpoint.py", "--config", str(config), "--write"],
                ),
            ):
                self.assertEqual(MODULE.main(), 0)
            self.assertEqual(json.loads(config.read_text(encoding="utf-8")), original)


if __name__ == "__main__":
    unittest.main()
