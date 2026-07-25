# GOOBY-Godot für iOS bauen und installieren

## Was der CI-Build erzeugt

Der Workflow **GOOBY Godot** (`.github/workflows/gooby-godot.yml`) importiert und
testet das Projekt zuerst unter Linux. Danach exportiert der Job `ios-ipa` auf
macOS ein Xcode-Projekt, baut es für ein echtes iOS-Gerät und packt
`GOOBY-godot-unsigned.ipa`.

Die IPA ist absichtlich **unsigniert**:

- Sie enthält weder `_CodeSignature` noch `embedded.mobileprovision`.
- Sie lässt sich deshalb nicht direkt über Dateien, AirDrop oder einen einfachen
  IPA-Installer starten.
- AltStore oder Sideloadly signiert sie beim Installieren mit dem eigenen
  Apple-Entwicklerkonto neu.

Der CI-Job lädt die IPA nur hoch, wenn eine Post-Build-Prüfung unter anderem
Bundle-ID, iPhone-Unterstützung, arm64, Launch-Screen, Icons, PCK und alle
importierten Assets bestätigt.

## Artefakt aus GitHub Actions laden

1. Auf GitHub **Actions → GOOBY Godot** öffnen.
2. Den neuesten Lauf des gewünschten Commits wählen. Der Job `ios-ipa` muss grün
   sein.
3. Unter **Artifacts** `GOOBY-godot-unsigned-ipa` laden.
4. Das von GitHub geladene ZIP einmal entpacken. Darin liegt
   `GOOBY-godot-unsigned.ipa`; die IPA selbst nicht noch einmal entpacken.

Wichtig: Ein roter Gesamt-Lauf kann trotzdem einen grünen `ios-ipa`-Job und ein
gültiges Artefakt haben, wenn ein unabhängiger Lint-Job fehlgeschlagen ist. Für
eine Veröffentlichung sollten trotzdem alle Jobs grün sein.

## Mit AltStore installieren

1. AltServer auf macOS oder Windows installieren und das iPhone per Kabel oder
   korrekt eingerichtetem WLAN-Sync verbinden.
2. AltStore auf dem iPhone installieren und mit der gewünschten Apple-ID
   anmelden.
3. Die IPA auf das iPhone übertragen und über **Teilen → AltStore** öffnen oder
   in AltStore unter **My Apps → +** auswählen.
4. Die Signierung und Installation vollständig abwarten.
5. Falls iOS danach fragt:
   - **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** aktivieren
     (iOS 16 oder neuer; Neustart nötig).
   - **Einstellungen → Allgemein → VPN & Geräteverwaltung** öffnen und der
     Entwickler-App beziehungsweise Apple-ID vertrauen.

## Mit Sideloadly installieren

1. Sideloadly auf macOS oder Windows starten und das entsperrte iPhone verbinden.
2. `GOOBY-godot-unsigned.ipa` in Sideloadly ziehen.
3. Gerät und Apple-ID auswählen. Für ein Update mit Spielstanderhalt keine
   Option aktivieren, die die Bundle-ID ändert.
4. **Start** drücken, die Apple-Anmeldung abschließen und bis zum erfolgreichen
   Installationsende warten.
5. Entwicklermodus und Vertrauen wie im AltStore-Abschnitt aktivieren.

Bei einer kostenlosen Apple-ID gilt die Signatur normalerweise nur **7 Tage**.
Danach muss die App über AltStore/Sideloadly erneut signiert werden. Ein
kostenpflichtiges Apple Developer Program erlaubt längere Profile.

## Spielstand der alten App behalten

Die native App verwendet absichtlich dieselbe Bundle-ID wie die alte App:
`com.permissionmaxed.gooby`. Dadurch kann iOS eine Installation als Update
behandeln und den bestehenden App-Container behalten.

Für die beste Chance auf Spielstanderhalt:

1. Die alte App **nicht löschen**; Löschen entfernt normalerweise ihren
   App-Container und damit lokale Daten.
2. Dasselbe Sideload-Werkzeug und dieselbe Apple-ID beziehungsweise dasselbe
   Signing-Team wie bei der alten Installation verwenden.
3. Sicherstellen, dass das Werkzeug die Bundle-ID nicht umschreibt.
4. Vorher nach Möglichkeit den alten Spielstand beziehungsweise den
   GOOBY-Umzugskoffer exportieren und sichern.

Die gleiche Bundle-ID allein garantiert kein In-Place-Update: iOS kann ein
Überschreiben ablehnen, wenn die alte App von einem anderen Team signiert wurde
oder die Entitlements nicht zusammenpassen. In diesem Fall nicht vorschnell
deinstallieren, sondern zuerst den Spielstand exportieren und danach sauber neu
installieren.

## „App verschwindet sofort“ oder startet nicht

Typische Ursachen:

| Symptom/Ursache | Prüfung und Abhilfe |
|---|---|
| IPA wurde ohne Neu-Signierung installiert | Immer AltStore oder Sideloadly verwenden. Die CI-IPA ist absichtlich unsigniert. |
| Falsche Gerätefamilie | Aktuelle Builds enthalten `UIDeviceFamily = [1, 2]` und unterstützen iPhone und iPad. Alte iPad-only-IPAs verwerfen. |
| Signatur/Provisioning ungültig oder abgelaufen | In AltStore/Sideloadly neu signieren; bei Free-Apple-ID spätestens nach 7 Tagen. |
| Entwickler nicht vertraut | Unter **VPN & Geräteverwaltung** vertrauen und ab iOS 16 den Entwicklermodus aktivieren. |
| Andere App mit gleicher Bundle-ID, aber anderem Signing-Team | Nicht löschen, bevor der Spielstand gesichert ist; mit demselben Team aktualisieren oder nach Export neu installieren. |
| iOS zu alt | Die Mindestversion ist iOS 14.0. |
| Alte oder zwischengespeicherte IPA | Den Actions-Lauf und Commit prüfen und das Artefakt erneut laden. |

## Lokal exportieren und prüfen

Godot 4.4.1 und das passende iOS-Export-Template müssen installiert sein:

```bash
godot --headless --path GOOBY-GODOT --import
godot --headless --path GOOBY-GODOT \
  --export-release "ios" /tmp/iosverify/GOOBY.ipa
```

Unter Linux erzeugt dieser Befehl wegen
`application/export_project_only=true` das Xcode-Projekt, aber keine fertige
IPA. Zu prüfen sind insbesondere:

- `GOOBY/GOOBY-Info.plist`
- `GOOBY.xcodeproj/project.pbxproj`
- `GOOBY/Images.xcassets/AppIcon.appiconset`
- `GOOBY.pck`

Erwarteter Vertrag:

| Feld | Erwartung |
|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.permissionmaxed.gooby` |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` |
| `ARCHS` | `arm64` |
| `IPHONEOS_DEPLOYMENT_TARGET` | `14.0` |
| App-Icon | GOOBY-Original, 1024 px plus alle generierten Gerätegrößen |
| Orientierungen | Querformat zuerst; Hochformat ebenfalls erlaubt |
| Dateifreigabe | deaktiviert |
| Nicht ausgenommene Verschlüsselung | `false` |

Das eigentliche unsigned Device-Binary kann nur auf macOS mit Xcode gebaut
werden. Die maßgebliche, reproduzierbare Befehlsfolge steht im Job `ios-ipa` des
Workflows.
