# SoooDreamy vs. SoooDreamy-Lite — Bundle-IDs & Widgets

## 🇩🇪 Deutsch

**Kurzfassung:** Widgets erfordern bei Apple technisch zwingend eine eigene
App-Extension mit **eigener Bundle-ID**. Weniger als **2 IDs** geht mit
Widgets also nicht — das ist eine Plattform-Regel, keine Entscheidung dieser App.

| Variante | Bundle-IDs | Widgets |
| --- | --- | --- |
| `SoooDreamy-unsigned-<version>.ipa` (Standard) | **2** — `app.sooodreamy.ios` (App) + `app.sooodreamy.ios.widgets` (Widget-Extension) | ✅ alle 8 Widgets, 3 Live Activities, iOS-18-Controls |
| `SoooDreamy-Lite-unsigned-<version>.ipa` | **1** — nur `app.sooodreamy.ios` | ❌ keine (sonst identische App) |

- **Alle** Widgets stecken in genau **einer** Widget-Extension
  (`WidgetBundle` in `SoooDreamy/ios/Widgets/WidgetsBundle.swift`) — mehr
  als diese eine zusätzliche ID braucht SoooDreamy nie.
- **Wofür Lite?** Manche Signier-/Sideload-Wege (z. B. stark limitierte
  Gratis-Zertifikate: max. 10 App-ID-Registrierungen pro 7 Tage) kommen mit
  nur einer ID besser aus. Lite ist dieselbe App aus demselben Code — es
  fehlt ausschließlich der `PlugIns/`-Ordner mit der Widget-Extension.
- **Datenverlust?** Nein. Beide Varianten benutzen dieselbe App-Bundle-ID
  `app.sooodreamy.ios` — wer von Lite auf die Standard-IPA wechselt (oder
  umgekehrt), behält Kopplung und lokale Daten.
- Beide IPAs baut der CI-Workflow `SoooDreamy` bei jedem Push; sie hängen
  am Rolling-Release `sooodreamy-latest` und als Workflow-Artifacts.

## 🇬🇧 English

**TL;DR:** Apple only allows widgets as an app extension with its **own
bundle id**. Fewer than **2 ids** with widgets is therefore impossible —
a platform rule, not a choice made by this app.

| Variant | Bundle ids | Widgets |
| --- | --- | --- |
| `SoooDreamy-unsigned-<version>.ipa` (default) | **2** — `app.sooodreamy.ios` (app) + `app.sooodreamy.ios.widgets` (widget extension) | ✅ all 8 widgets, 3 Live Activities, iOS 18 controls |
| `SoooDreamy-Lite-unsigned-<version>.ipa` | **1** — only `app.sooodreamy.ios` | ❌ none (otherwise identical app) |

- **All** widgets live in exactly **one** widget extension
  (`WidgetBundle` in `SoooDreamy/ios/Widgets/WidgetsBundle.swift`) —
  SoooDreamy never needs more than that single extra id.
- **Why Lite?** Some signing/sideload flows (e.g. tightly limited free
  certificates: max 10 App ID registrations per 7 days) are happier with a
  single id. Lite is the same app built from the same sources — the only
  difference is the missing `PlugIns/` folder with the widget extension.
- **Data loss?** No. Both variants share the app bundle id
  `app.sooodreamy.ios` — switching from Lite to the full IPA (or back)
  keeps your pairing and local data.
- CI builds both IPAs on every push; both are attached to the rolling
  release `sooodreamy-latest` and as workflow artifacts.
