#!/usr/bin/env python3
"""GOOBY-WIDGETS: forensische Verifikation der eingebetteten Widget-Extension.

Laeuft im ios-ipa-Job NACH tools/ci/verify_ipa.py (das die App selbst prueft)
und beantwortet die Widget-spezifischen Fragen:

 1. Liegt PlugIns/GoobyWidgets.appex mit Binary + Info.plist in der App?
 2. Ist die Extension eine echte WidgetKit-Extension
    (NSExtensionPointIdentifier == com.apple.widgetkit-extension)?
 3. Tragen App UND Extension die App-Group in ihren beigelegten
    Entitlements-Dateien (unsignierte IPA: AltStore/SideStore lesen sie
    beim Re-Signieren)?
 4. Steht NSSupportsLiveActivities=true in der App-Info.plist?
 5. Sind goobykit-Laufzeit (App-Binary) und Widget-/Live-Activity-Code
    (Extension-Binary) tatsaechlich einkompiliert (Symbol-Spuren)?

Erwartungen (App-Group, Bundle-Ids) werden aus den eingecheckten Quellen
ABGELEITET (GoobyKitShared.swift), nicht hart kodiert — gleiche Lehre wie
verify_ipa.py.

Aufruf: python3 tools/ci/verify_widgets.py [ipa-pfad] [projekt-dir]
Exit 0 = PASS (druckt Zusammenfassung), sonst AssertionError/Exit 1.
"""

from __future__ import annotations

import os
import plistlib
import re
import sys
import zipfile
from pathlib import Path

APP = "Payload/GOOBY.app/"
APPEX = APP + "PlugIns/GoobyWidgets.appex/"


def expected_app_group(project: Path) -> str:
    shared = (project / "ios/widgets/GoobyKitShared.swift").read_text(encoding="utf-8")
    match = re.search(r'appGroupId\s*=\s*"([^"]+)"', shared)
    assert match, "appGroupId nicht in GoobyKitShared.swift gefunden"
    return match.group(1)


def entitlement_groups(archive: zipfile.ZipFile, name: str) -> list[str]:
    data = plistlib.loads(archive.read(name))
    return list(data.get("com.apple.security.application-groups", []))


def main() -> int:
    ipa = Path(sys.argv[1] if len(sys.argv) > 1 else "build/ios/GOOBY-godot-unsigned.ipa")
    project = Path(sys.argv[2] if len(sys.argv) > 2 else "GOOBY-GODOT")
    app_group = expected_app_group(project)

    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()

        # 1. Extension eingebettet (Binary + Plist).
        appex_names = [n for n in names if n.startswith(APPEX)]
        assert appex_names, f"{APPEX} fehlt in der IPA"
        assert APPEX + "GoobyWidgets" in names, "Extension-Binary fehlt"
        assert APPEX + "Info.plist" in names, "Extension-Info.plist fehlt"
        appex_binary = archive.read(APPEX + "GoobyWidgets")
        appex_size_kb = len(appex_binary) / 1024

        # 2. Echte WidgetKit-Extension mit korrekten Metadaten.
        info = plistlib.loads(archive.read(APPEX + "Info.plist"))
        point = info.get("NSExtension", {}).get("NSExtensionPointIdentifier", "")
        assert point == "com.apple.widgetkit-extension", f"Falscher Extension-Punkt: {point}"
        app_info = plistlib.loads(archive.read(APP + "Info.plist"))
        app_bundle_id = app_info["CFBundleIdentifier"]
        ext_bundle_id = info["CFBundleIdentifier"]
        assert ext_bundle_id.startswith(app_bundle_id + "."), (
            f"Extension-Bundle-Id {ext_bundle_id} liegt nicht unter {app_bundle_id}"
        )
        assert info["CFBundleShortVersionString"] == app_info["CFBundleShortVersionString"], (
            "Versions-Drift zwischen App und Extension"
        )
        min_os = info.get("MinimumOSVersion", "0")
        assert float(min_os.split(".")[0]) >= 16, f"Extension-Min-iOS zu alt: {min_os}"

        # 3. App-Group in beiden beigelegten Entitlements-Dateien.
        app_ent = [n for n in names if n.startswith(APP) and n.endswith(".entitlements")
                   and "/PlugIns/" not in n]
        ext_ent = [n for n in names if n.startswith(APPEX) and n.endswith(".entitlements")]
        assert app_ent, "App-Entitlements-Datei fehlt im Bundle"
        assert ext_ent, "Extension-Entitlements-Datei fehlt im Bundle"
        assert app_group in entitlement_groups(archive, app_ent[0]), (
            f"App-Group fehlt in {app_ent[0]}"
        )
        assert app_group in entitlement_groups(archive, ext_ent[0]), (
            f"App-Group fehlt in {ext_ent[0]}"
        )

        # 4. Live-Activity-Schalter in der App-Info.plist.
        assert app_info.get("NSSupportsLiveActivities") is True, (
            "NSSupportsLiveActivities fehlt in der App-Info.plist"
        )

        # 5. Symbol-Spuren: Swift-Laufzeit wirklich einkompiliert.
        app_binary = archive.read(APP + app_info["CFBundleExecutable"])
        assert b"GoobyKitRuntime" in app_binary, (
            "GoobyKitRuntime fehlt im App-Binary (inject_widgets.rb gelaufen?)"
        )
        assert b"goobykit" in app_binary, "goobykit-Plugin-Spuren fehlen im App-Binary"
        assert b"GoobyActivityAttributes" in appex_binary, (
            "Live-Activity-Attribute fehlen im Extension-Binary"
        )

    summary = (
        f"Widgets PASS: PlugIns/GoobyWidgets.appex eingebettet "
        f"({appex_size_kb:.0f} KB Binary, {len(appex_names)} Dateien), "
        f"App-Group {app_group} in App+Extension, NSSupportsLiveActivities=true, "
        f"Extension min iOS {min_os}"
    )
    print(summary)
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as handle:
            handle.write(f"**{summary}**\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
