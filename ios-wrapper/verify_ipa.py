#!/usr/bin/env python3
"""Forensische .ipa-Verifikation für den MONKEY-MONEY-iPad-Wrapper.

Aufruf:  python3 ios-wrapper/verify_ipa.py <pfad/zur.ipa> <ios-wrapper-dir>

Erwartungen werden aus den Repo-Quellen ABGELEITET (Godot-Muster aus
tools/ci/verify_ipa.py der GOOBY-Pipeline — hart kodierte Sets veralten):
  - Orientierungen / Vollbild / Status-Bar / ATS  ← ios-wrapper/Info.plist
  - Bundle-Id                                     ← ios-wrapper/project.yml

Geprüft wird die GEBAUTE App im Payload: Info.plist-Keys, Mach-O-Executable,
kompilierter Asset-Katalog (App-Icon). Druckt am Ende die Erfolgszeile
„.ipa gebaut: X MB, Y Dateien im Payload".

Nur Python-Stdlib — läuft ohne pip auf dem macos-Runner.
"""

import plistlib
import re
import sys
import zipfile
from pathlib import Path

MACH_O_MAGICS = {
    b"\xca\xfe\xba\xbe",  # Fat Binary
    b"\xcf\xfa\xed\xfe",  # Mach-O 64-bit little-endian
    b"\xce\xfa\xed\xfe",  # Mach-O 32-bit little-endian
}

VERGLEICHS_KEYS = [
    "UISupportedInterfaceOrientations",
    "UISupportedInterfaceOrientations~ipad",
    "UIRequiresFullScreen",
    "UIStatusBarHidden",
    "CFBundleDisplayName",
]


def fehler(text: str) -> None:
    print(f"::error::{text}")
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 3:
        fehler("Aufruf: verify_ipa.py <pfad/zur.ipa> <ios-wrapper-dir>")
    ipa_pfad = Path(sys.argv[1])
    wrapper_dir = Path(sys.argv[2])
    if not ipa_pfad.is_file():
        fehler(f".ipa fehlt: {ipa_pfad}")

    # --- Erwartungen aus den Repo-Quellen ableiten -------------------------
    quelle_plist = plistlib.loads((wrapper_dir / "Info.plist").read_bytes())
    project_yml = (wrapper_dir / "project.yml").read_text(encoding="utf-8")
    m = re.search(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", project_yml)
    if not m:
        fehler("PRODUCT_BUNDLE_IDENTIFIER nicht in project.yml gefunden")
    erwartete_bundle_id = m.group(1).strip("\"'")

    # --- Payload öffnen ----------------------------------------------------
    probleme: list[str] = []
    with zipfile.ZipFile(ipa_pfad) as zf:
        namen = zf.namelist()
        app_prefixe = sorted({n.split("/")[1] for n in namen if re.match(r"^Payload/[^/]+\.app/", n)})
        if len(app_prefixe) != 1:
            fehler(f"Erwartet genau EIN .app im Payload, gefunden: {app_prefixe}")
        app = f"Payload/{app_prefixe[0]}"

        gebaut = plistlib.loads(zf.read(f"{app}/Info.plist"))

        # 1) Feste Keys 1:1 gegen die Quelle (Landscape-Lock, Vollbild, Status-Bar, Name).
        for key in VERGLEICHS_KEYS:
            soll, ist = quelle_plist.get(key), gebaut.get(key)
            if ist != soll:
                probleme.append(f"{key}: gebaut={ist!r}, erwartet={soll!r}")

        # 2) ATS: HTTP muss erlaubt sein (AMP-/LAN-Pfad ist bewusst NUR http://).
        ats = gebaut.get("NSAppTransportSecurity", {})
        if ats.get("NSAllowsArbitraryLoads") is not True:
            probleme.append(f"NSAppTransportSecurity.NSAllowsArbitraryLoads fehlt/falsch: {ats!r}")

        # 3) Bundle-Id aus project.yml.
        if gebaut.get("CFBundleIdentifier") != erwartete_bundle_id:
            probleme.append(
                f"CFBundleIdentifier: gebaut={gebaut.get('CFBundleIdentifier')!r}, "
                f"erwartet={erwartete_bundle_id!r}"
            )

        # 4) Executable existiert und ist Mach-O.
        exe_name = gebaut.get("CFBundleExecutable", "")
        exe_pfad = f"{app}/{exe_name}"
        if exe_pfad not in namen:
            probleme.append(f"Executable fehlt im Bundle: {exe_pfad}")
        else:
            magic = zf.read(exe_pfad)[:4]
            if magic not in MACH_O_MAGICS:
                probleme.append(f"Executable ist kein Mach-O (Magic {magic.hex()})")

        # 5) Kompilierter Asset-Katalog (App-Icon) ist dabei.
        if f"{app}/Assets.car" not in namen:
            probleme.append(f"Assets.car (App-Icon-Katalog) fehlt in {app}/")

        # 6) Standalone-Bundle (iPad = Server): der CI-Job kopiert client/dist →
        #    WebDist/ und die Laufzeit-Medien → Media/. Ohne diese Dateien wäre
        #    die 3. Start-Option („iPad ist der Server") in der App tot.
        for pflicht in (
            f"{app}/WebDist/host.html",
            f"{app}/WebDist/host-content.json",
            f"{app}/WebDist/screen.html",
            f"{app}/WebDist/player.html",
            f"{app}/Media/video/logo_stinger.mp4",
        ):
            if pflicht not in namen:
                probleme.append(f"Standalone-Bundle unvollständig: {pflicht} fehlt")
        webdist_dateien = sum(1 for n in namen if n.startswith(f"{app}/WebDist/") and not n.endswith("/"))
        media_dateien = sum(1 for n in namen if n.startswith(f"{app}/Media/") and not n.endswith("/"))

        payload_dateien = sum(1 for n in namen if n.startswith("Payload/") and not n.endswith("/"))

    if probleme:
        for p in probleme:
            print(f"::error::{p}")
        sys.exit(1)

    mb = ipa_pfad.stat().st_size / (1024 * 1024)
    print(f"Bundle-Id: {erwartete_bundle_id} · Landscape-Lock ✓ · Vollbild ✓ · ATS-HTTP ✓ · Mach-O ✓")
    print(f"Standalone ✓ (WebDist: {webdist_dateien} Dateien, Media: {media_dateien} Dateien)")
    print(f".ipa gebaut: {mb:.1f} MB, {payload_dateien} Dateien im Payload")


if __name__ == "__main__":
    main()
