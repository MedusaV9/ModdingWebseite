# iOS 26-only: Runner-Befund & Entscheidung

Stand: August 2026 (v10.1 „Große Polish-Runde").

## Befund: Was bietet GitHub Actions wirklich?

Geprüft über die offizielle Runner-Image-Doku
([actions/runner-images → macos-26-Readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)):

| Runner-Image | Standard-Xcode | iOS-SDK | Status |
| ------------ | -------------- | ------- | ------ |
| `macos-15`   | Xcode 16.x     | iOS 18.x | bisheriger Runner — kann kein `glassEffect` |
| **`macos-26`** | **Xcode 26.6** (17F113) | **iOS 26.0 – 26.5** | **verfügbar → gewählt** |
| (Xcode 27)   | Public Preview auf macos-26 | 27.x beta | zu früh für Release-Builds |

`macos-26` bringt Xcode 26.0.1 bis 26.6 vor­installiert mit; 26.6 ist Default.
Kein `xcode-select`/`XCODE_VERSION`-Matrix-Umweg nötig — der Default passt.

## Entscheidung

- **Alle drei macOS-Jobs** (`build-ipa`, `build-ipa-lite`, `simulator-screenshots`)
  laufen jetzt auf `runs-on: macos-26`.
- **`deploymentTarget: iOS "26.0"`** in `SoooDreamy/ios/project.yml`.
  Die App ist privat und sideloaded — die beiden Zielgeräte laufen auf
  iOS 26/27, Abwärtskompatibilität kostet nur Code und Gates.
- **Alle `#available(iOS 26)`- und `#if swift(>=6.2)`-Gates entfernt.**
  `glassEffect(.regular, in:)` wird jetzt direkt aufgerufen
  (`Theme.GlassCardModifier`, `LiquidTabBar.LiquidGlassBackground`).
  Ebenso raus: die toten `iOS 17/18`-Gates (Control Widgets,
  `WidgetsBundle`, Video-Export-Legacy-Pfad, `DateNightAdvanceIntent`).
- Der Linux-Job (`swift test` + `swiftc -parse` auf Swift 6.0) bleibt wie er
  ist: Er parst nur bzw. testet Foundation-only-Logik und braucht kein
  iOS-SDK.

## Wenn Apple/GitHub weiterziehen

Der Default-Xcode des `macos-26`-Images rotiert automatisch nach vorn
(26.5 → 26.6 → …). Sollte ein Build wegen eines Xcode-Wechsels brechen,
zuerst im Image-Readme prüfen, was Default ist, und nur bei Bedarf im
Workflow mit `sudo xcode-select -s /Applications/Xcode_<ver>.app` pinnen.
