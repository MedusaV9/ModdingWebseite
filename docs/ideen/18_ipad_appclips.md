# Ideen-Agent 18/20 — iPad-App, .ipa-Machbarkeit & App Clips

Recherche/Design für MONKEY MONEY (Jackbox/Buzz-artige Quiz-Party-App, Web-App
als Kern). Keine Code-Änderungen — dieses Dokument ist die Deliverable.

Kurzfassung vorab:

- **.ipa-Empfehlung:** Minimaler nativer **WKWebView-Wrapper** (Swift/UIKit,
  ~6 Dateien, via XcodeGen generiert), unsigniert gebaut mit exakt denselben
  `xcodebuild`-Flags wie die vorhandene Godot-Pipeline — Capacitor lohnt sich
  NICHT.
- **App-Clips-Wahrheit:** App Clips sind mit unsignierten Builds/Sideload
  **unmöglich** (Signatur + App Store Connect + Apple-verifizierte
  AASA-Domain zwingend) — die beste Alternative ist QR → Safari mit
  gehärteter Join-Seite.

---

## (a) .ipa-Wege für eine Web-App

### Option 1: WKWebView-Wrapper (EMPFOHLEN)

Ein minimales natives Xcode-Projekt, dessen einziger Job es ist, die
Server-URL in einem Vollbild-`WKWebView` zu laden.

**Wie klein kann es sein?** Sehr klein. Kein Storyboard, kein Asset-Overkill,
kein SwiftUI nötig:

```
ipad-wrapper/
├── project.yml                 # XcodeGen-Spec (~40 Zeilen) — ODER .xcodeproj committen
├── Sources/
│   ├── AppDelegate.swift       # ~30 Zeilen: Window, isIdleTimerDisabled, AVAudioSession
│   ├── ConnectViewController.swift  # ~120 Zeilen: URL-Eingabe + QR-Scan + UserDefaults
│   └── GameViewController.swift     # ~80 Zeilen: WKWebView fullscreen, Reload-Geste
├── Info.plist                  # siehe Skizze unten
└── Assets.xcassets/            # AppIcon (1 Bild reicht, Single-Size seit Xcode 14)
```

Die fertige unsignierte .ipa liegt bei **unter 1 MB** (das App-Binary eines
reinen WKWebView-Wrappers sind wenige hundert KB — WebKit ist System-
Framework und wird nicht mitgeliefert). Zum Vergleich: die Godot-.ipa im
Repo hat zweistellige MB.

**xcodebuild ohne Signing — funktioniert exakt wie im Godot-Muster.** Die
etablierten Flags (mehrfach verifiziert, u. a. Stack Overflow und mehrere
produktive GitHub-Workflows für WebView-Wrapper):

```
xcodebuild archive \
  -project MonkeyMoneyPad.xcodeproj \
  -scheme MonkeyMoneyPad \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/MonkeyMoneyPad.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
# dann: .app aus dem Archiv in Payload/ kopieren und zippen → .ipa
```

Ehrliche Fußnote (gilt genauso für die Godot-.ipa, der User kennt den Weg
also schon): eine unsignierte .ipa wird beim Sideload (AltStore/Sideloadly/
Xcode + freie Apple-ID) neu signiert; freie Apple-ID = 7-Tage-Laufzeit,
max. 3 Apps. Für die Party-Nutzung reicht das völlig.

**XcodeGen statt .xcodeproj committen:** `project.yml` (YAML) ist
diff-freundlich und der macos-Runner installiert XcodeGen in Sekunden via
`brew install xcodegen`. Alternativ das .xcodeproj einmalig committen —
funktioniert auch, ist aber merge-feindlich. Empfehlung: XcodeGen.

### Option 2: Capacitor — lohnt der Overhead? NEIN.

Capacitor bringt: node_modules im nativen Build, CocoaPods/SPM-Abhängigkeit,
eigenes CLI (`npx cap sync`), Plugin-Ökosystem, Bridge-JS. Was wir davon
bräuchten: genau nichts. Die zwei „nativen" Features, die MONKEY MONEY
braucht (Idle-Timer aus, Landscape-Lock), sind je 1 Zeile Swift bzw. 4
Zeilen Info.plist. Capacitor lohnt erst, wenn die Web-App IN die App
gebündelt werden soll (Offline-Betrieb) oder viele native Plugins
(Push, Haptics, In-App-Purchase) dazukommen. Beides ist nicht der Fall —
die App lädt vom Party-Host-Server. Overhead ohne Nutzen → verwerfen.

### Option 3: „Zum Home-Bildschirm" (PWA) — Teilwahrheit

- Der Share-Sheet-Eintrag „Zum Home-Bildschirm" existiert in Safari **auch
  für HTTP-Seiten**, und der Legacy-Meta-Tag
  `<meta name="apple-mobile-web-app-capable" content="yes">` öffnet die
  gemerkte Seite ohne Adressleiste. Das ist aber nur die Hülle.
- **Echte PWA-Features gehen über HTTP NICHT:** Service Worker, Web-App-
  Manifest-Install, und vor allem die **Screen Wake Lock API verlangen einen
  Secure Context (HTTPS)** — über HTTP wirft `navigator.wakeLock.request()`
  einen `NotAllowedError` (MDN/caniuse bestätigt; iOS-Safari unterstützt
  Wake Lock ab 16.4, alle iOS-Browser via WebKit gleich).
- **Cloudflare-HTTPS als Brücke:** Ja, das funktioniert. `cloudflared tunnel
  --url http://localhost:3000` (Quick Tunnel, kein Account nötig) gibt eine
  zufällige `https://….trycloudflare.com`-URL → Wake Lock, PWA-Install und
  Clipboard-API funktionieren auf allen Handys. Preis: der Traffic läuft
  übers Internet (Latenz +20–80 ms, Internetpflicht auf der Party, URL
  wechselt pro Start). Als **optionaler „Online-Modus"** sinnvoll, nicht als
  Default. Lokales HTTPS via mkcert scheitert praktisch daran, dass jedes
  Gast-Handy das CA-Zertifikat installieren müsste — nicht party-tauglich.

### Empfehlung + Xcode-Projekt-Skizze

**Der schlauste Weg: WKWebView-Wrapper fürs iPad (Bildschirm/GM), nacktes
Safari für die Spieler-Handys.** Das iPad ist das Gerät des Gastgebers — dort
ist einmaliges Sideloaden zumutbar und der Wrapper löst genau die Probleme,
die Safari nicht lösen kann (Sleep, Adressleiste, Autoplay). Gäste-Handys
bekommen NIE eine App — die joinen per QR in Safari (siehe b).

Info.plist-Skizze (die entscheidenden Keys):

```xml
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
  <string>UIInterfaceOrientationLandscapeLeft</string>
  <string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UIRequiresFullScreen</key><true/>          <!-- kein Split View/Slide Over -->
<key>UIStatusBarHidden</key><true/>
<key>UIViewControllerBasedStatusBarAppearance</key><false/>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key><true/>     <!-- http://192.168.x.x erlauben -->
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>Verbindet sich mit dem MONKEY-MONEY-Server im lokalen Netz.</string>
<key>NSCameraUsageDescription</key>
<string>Scannt den QR-Code des Spielservers.</string>
```

Verhalten beim Start (ConnectViewController):

1. Zuletzt benutzte Server-URL aus `UserDefaults` vorschlagen, großer
   „Verbinden"-Button.
2. Alternativ: **QR-Code scannen** (AVFoundation, ~30 Zeilen) — derselbe
   QR, den die Handys scannen; das iPad liest daraus die URL und hängt
   `?role=screen` bzw. `?role=gm` an. Rollen-Toggle auf dem Screen.
3. Nach Verbinden: `GameViewController` mit WKWebView, dabei:
   - `UIApplication.shared.isIdleTimerDisabled = true` (Sleep aus — DER
     Grund für den Wrapper),
   - `webView.configuration.mediaTypesRequiringUserActionForPlayback = []`
     und `allowsInlineMediaPlayback = true` → Sounds/Jingles spielen ohne
     Touch-Geste (in Safari bräuchte es erst einen Tap),
   - `AVAudioSession`-Kategorie `.playback` setzen,
   - versteckte Geste (3-Finger-Longpress) → zurück zum Connect-Screen.

## (b) App Clips — Technik & ehrliche Wahrheit

**Was sie sind:** Ein App Clip ist ein signiertes Mini-Binary (≤ 10 MB bis
iOS 15, ≤ 15 MB ab iOS 16, ≤ 100 MB ab iOS 17 — Letzteres NUR für digitale
Invocations, ausdrücklich NICHT für QR-Codes/NFC), das iOS on-demand lädt,
wenn eine Invocation-URL getriggert wird (QR, App-Clip-Code, NFC, Safari
Smart Banner, Messages).

**Gehen sie unsigniert/per Sideload? NEIN — definitiv nicht:**

1. Der App Clip muss das **Associated-Domains-Entitlement**
   (`appclips:example.com`) in seiner **Code-Signatur** tragen — eine
   unsignierte .ipa hat keine verwertbare Signatur.
2. Die Domain muss eine von Apple abrufbare
   **AASA-Datei** (`/.well-known/apple-app-site-association`) auf einem
   öffentlichen HTTPS-Server hosten, die den Clip zurück-referenziert; das
   System validiert beide Seiten gegeneinander.
3. Ausgeliefert wird ausschließlich über **App Store Connect** (App Store
   oder TestFlight); selbst „Local Experiences" zum Testen verlangen
   Development-/Ad-hoc-/TestFlight-**signierte** Builds (Apple-Doku:
   „local experiences only launch an App Clip that's signed for
   Development, Ad Hoc, or TestFlight distribution").
4. Es gibt keinen Sideload-Kanal für App Clips — AltStore & Co. können
   das On-Demand-Invocation-System von iOS nicht bedienen.

Fazit: App Clips sind ein „Später vielleicht, falls App-Store-Release"-
Feature (dann allerdings ein sehr gutes: QR scannen → Clip-Card → nativ
drin, ohne Install). Für die unsignierte Hobby-Pipeline: **streichen.**

**Beste Alternative für „Handy scannt QR und ist SOFORT drin":**
QR → Safari auf die lokale HTTP-Join-URL (`http://192.168.x.x:3000/j/ABCD`,
Raumcode direkt in der URL → null Tipparbeit). Nachteile ehrlich benannt +
Gegenmittel:

| Nachteil | Gegenmittel |
| --- | --- |
| Adressleiste/Safari-Chrome frisst Platz | `<meta name="apple-mobile-web-app-capable" content="yes">` + „Zum Home-Bildschirm"-Hinweis für Vielspieler; UI so bauen, dass die Leiste beim Scrollen kollabiert; wichtige Buttons nie hinter die untere Leiste legen (`env(safe-area-inset-bottom)`, `viewport-fit=cover`) |
| Standby/Auto-Lock: Wake Lock geht über HTTP nicht | (1) UI-Hinweis beim Join: „Auto-Sperre aus: Einstellungen → Anzeige → Automatische Sperre → Nie"; (2) Interaktion hält iOS wach — Spieler tippen ohnehin alle paar Sekunden; (3) Reconnect-Logik im Client, sodass ein gesperrtes Handy nach Entsperren sofort wieder im Spiel ist (Session-Token in localStorage) — das ist die WICHTIGSTE Maßnahme; (4) optionaler Cloudflare-Tunnel-Modus = echtes Wake Lock |
| Versehentliches Wegwischen/Tab schließen | Reconnect wie oben; `beforeunload` ist auf iOS unzuverlässig — nicht drauf bauen |
| iPad (Bildschirm) schläft ein | Im Wrapper gelöst (`isIdleTimerDisabled`); OHNE Wrapper: **Geführter Zugriff** (Guided Access, Dreifachklick Seitentaste) sperrt das iPad in Safari UND unterdrückt den Auto-Lock — als dokumentierter Fallback in die README |

## (c) iPad als BILDSCHIRM und als GM-COCKPIT

### iPad = Bildschirm (an der Wand / auf dem Tisch)

- **Landscape-Lock:** über die Info.plist (nur LandscapeLeft/Right, s. o.)
  — zuverlässiger als jede CSS/JS-Lösung; `UIRequiresFullScreen` verhindert
  zusätzlich Split View, das das Layout zerschießen würde.
- **Sleep verhindern:** `isIdleTimerDisabled = true` im Wrapper — damit ist
  das Thema komplett erledigt, kein Wake-Lock-Gefrickel. (Fallback ohne
  Wrapper: Guided Access oder Auto-Lock „Nie".)
- **Lautstärke:** iPad-Lautsprecher sind für Wohnzimmer okay, aber:
  `AVAudioSession .playback` setzen (spielt auch bei Stummschalter-Stellung
  „aus" — relevant für ältere iPads mit Schalter) und
  `mediaTypesRequiringUserActionForPlayback = []`, sonst bleibt der erste
  Jingle stumm bis jemand das iPad anfasst. Empfehlung im UI: Bluetooth-Box
  koppeln; Lautstärke-Check-Button im GM-Cockpit („Test-Jingle").
- **4:3 vs 16:9:** iPads sind ~4:3 (iPad 10.2": 1,31; iPad Pro 11": 1,43),
  TVs/Beamer 16:9 (1,78). Der Screen-View muss den Bereich 1,3–1,8
  abdecken: zentrale „Bühne" mit `aspect-ratio`-Container + CSS `clamp()`
  für Typo; bei 4:3 gewinnt man Höhe → Scoreboard-Leiste unten andocken,
  bei 16:9 Scoreboard seitlich. Kein fixes 16:9-Letterboxing aufs iPad —
  verschenkt 25 % Fläche. Ein `?aspect=`-Override für Sonderfälle reicht.

### iPad = GM-Cockpit

- **Split-Layout (Landscape):** links schmale Spalte = Ablaufplan/Rundown
  (Fragen-Queue, abgehakte Items), Mitte = aktuelle Frage GROSS mit
  korrekter Antwort (nur für GM-Augen!), rechts = Live-Panel (wer hat
  geantwortet/gebuzzert, Timer, Punktestände). Untere Leiste: 3–4 fette
  Aktions-Buttons („Aufdecken", „Nächste", „Punkte vergeben",
  „Panik/Skip") — daumen-erreichbar, min. 60 pt Höhe.
- **Zweites Layout Portrait** ist verzichtbar (Landscape-Lock auch im
  Cockpit) — spart ein komplettes Responsive-Layout.
- **Apple Pencil als Gimmick:** technisch trivial nutzbar (Pencil = normale
  Touch/Pointer-Events im WebView). Nette Ideen: (1) Malrunden-Minispiel
  „GM zeichnet, alle raten" (Canvas → Broadcast an Screen/Handys), (2)
  Freihand-Anmerkungen über dem Scoreboard („Korrektur +5"), (3)
  Unterschrift des Siegers auf der „Wall of Fame". Alles P3-Gimmick — der
  Pencil braucht KEINE eigene API, es ist einfach präziser Touch. Nicht
  verplanen, aber das Mal-Minispiel ist der beste Kandidat.

## (d) Screen-loser Modus konkret

Setup: kein TV — das **GM-iPad zeigt die Regie**, die Handys zeigen alles,
was Spieler sehen MÜSSEN. Grundregel: jede Information wandert entweder in
den Mund des GM („vorlesbar") oder auf die Handys.

GM-iPad im Screen-los-Modus zusätzlich zur normalen Regie:

- Frage in **Vorlese-Typografie** (groß, Zeilenumbrüche als Sprechpausen,
  Antwortoptionen mit „A… B… C…"-Präfix zum Mitlesen),
- „Was die Spieler gerade sehen"-Mini-Vorschau,
- Auflösung + 1-Satz-Fun-Fact zum Vorlesen nach jeder Frage,
- Soundboard-Buttons (Jingles kommen dann aus dem iPad-Lautsprecher).

Was sich PRO MINISPIEL-FORMAT ändert:

| Format | Mit Screen | Screen-los: was ändert sich |
| --- | --- | --- |
| Multiple Choice | Frage+Optionen auf Screen, Handy nur A–D-Buttons | Optionstexte MÜSSEN aufs Handy (statt nackter A–D-Buttons); GM liest Frage vor |
| Buzzer/Schnellste Antwort | Screen zeigt Frage + Buzz-Reihenfolge | Funktioniert fast unverändert (bestes Format!); Buzz-Reihenfolge erscheint auf GM-iPad, GM moderiert; Handys: dicker Buzzer + „Du warst 2." |
| Schätzfrage/Slider | Screen zeigt Auflösungs-Animation | Handy: Zahleneingabe wie gehabt; Auflösung als Text auf allen Handys + GM verkündet dramatisch; die Nähe-Animation entfällt oder wird zur Handy-Mini-Animation |
| Sortieren/Reihenfolge | Items auf Screen | Item-Liste komplett aufs Handy (Drag&Drop dort ohnehin); praktisch kein Verlust |
| Bild-/Medienfragen | Bild auf Screen | Bild an ALLE Handys pushen (im LAN unkritisch, Bilder < 300 KB) — oder Format im Screen-los-Setup automatisch aus dem Fragenpool filtern; Audio-Fragen: GM-iPad spielt den Clip ab |
| Wetten/Einsätze | Quoten auf Screen | Quoten + Kontostand aufs Handy; GM liest die Wett-Optionen vor |
| Scoreboard/Zwischenstand | Screen-Moment | Scoreboard als Zwischenscreen auf ALLE Handys + GM verliest Top 3 — wird zum eigenen „Moment" |

Architektur-Konsequenz (billig, wenn früh eingeplant): ein globales Flag
`screenless: true` im Spielzustand; jede Minispiel-View entscheidet pro
Rolle (screen/gm/player), was sie rendert. Medienfragen deklarieren
`needs_screen: true` und werden ohne Screen gefiltert oder auf Handys
gespiegelt.

## (e) GitHub-Actions-Pipeline-Skizze für den Wrapper

Neuer Job neben dem bestehenden Godot-`ios-ipa`-Job (gleiche Philosophie:
unsigniert bauen, verifizieren, Artefakt hochladen). Läuft nur bei
Änderungen am Wrapper — und ist mit ~2–4 min viel schneller als der
Godot-Job, weil nichts exportiert werden muss:

```yaml
ipad-wrapper-ipa:
  runs-on: macos-15
  if: <pfad-filter auf ipad-wrapper/**>
  steps:
    - uses: actions/checkout@v4
    - name: XcodeGen
      run: brew install xcodegen && xcodegen generate --spec ipad-wrapper/project.yml
    - name: Archive (unsigned)
      run: |
        xcodebuild archive \
          -project ipad-wrapper/MonkeyMoneyPad.xcodeproj \
          -scheme MonkeyMoneyPad -configuration Release \
          -destination 'generic/platform=iOS' \
          -archivePath build/MonkeyMoneyPad.xcarchive \
          CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
          CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
    - name: Package .ipa
      run: |
        mkdir -p build/Payload
        cp -R build/MonkeyMoneyPad.xcarchive/Products/Applications/*.app build/Payload/
        (cd build && zip -qry monkey-money-ipad-unsigned.ipa Payload)
    - name: Verify .ipa            # Muster von tools/ci/verify_ipa.py übernehmen:
      run: python3 tools/ci/verify_wrapper_ipa.py   # Info.plist auspacken, prüfen:
      # nur Landscape-Orientierungen, UIRequiresFullScreen, Bundle-Id,
      # NSLocalNetworkUsageDescription vorhanden; Erfolgszeile
      # „.ipa gebaut: X MB, Y Dateien" wie beim Godot-Vorbild
    - uses: actions/upload-artifact@v4
      with:
        name: monkey-money-ipad-unsigned-ipa
        path: build/monkey-money-ipad-unsigned.ipa
```

Bewährte Details aus dem Godot-Muster übernehmen: Verifikation leitet ihre
Erwartungen aus der Projekt-Config ab (hier: `project.yml` statt
`export_presets.cfg`), Erfolgs-Beleg-Zeile am Ende, Release-Job optional
per Tag (`ipad-v<semver>`).

## Aufwand / Priorität je Baustein

| Baustein | Aufwand (technisch) | Prio |
| --- | --- | --- |
| QR→Safari-Join härten (Meta-Tags, safe-area, Reconnect/Session-Token, Auto-Lock-Hinweis) | klein: nur Web-Frontend, keine neuen Komponenten | **P1** — nützt JEDEM Spieler sofort |
| WKWebView-Wrapper (Connect-Screen mit URL-Merken, WebView, idleTimer, Landscape-plist) | klein: ~250 Zeilen Swift + project.yml, isoliertes neues Verzeichnis | **P1** — löst Sleep/Adressleiste/Autoplay am iPad komplett |
| CI-Job `ipad-wrapper-ipa` inkl. Verify-Skript | klein: 1 Workflow-Job + kleines Python-Skript nach vorhandenem Muster | **P1** — zusammen mit dem Wrapper |
| QR-Scan im Wrapper-Connect-Screen (AVFoundation) | klein–mittel: Kamera-Permission + Scanner-View | P2 — Komfort, Texteingabe reicht anfangs |
| Screen-los-Modus (`screenless`-Flag, Rollen-Rendering pro Minispiel, `needs_screen`-Filter) | mittel: zieht sich durch jede Minispiel-View, früh einplanen = billig | P2 — hoher Party-Nutzen |
| GM-Cockpit-Split-Layout + Vorlese-Modus | mittel: eigenes Layout, aber reines Frontend | P2 |
| Cloudflare-Quick-Tunnel-„Online-Modus" (Wake Lock/PWA für Handys) | klein: Doku + Start-Skript-Option, kein App-Code | P3 — nice-to-have |
| Apple-Pencil-Malrunde | mittel: Canvas-Sync als eigenes Minispiel | P3 — Gimmick |
| App Clips | n/a ohne Apple-Developer-Account + App Store Connect | **P– (streichen)**; wiedervorlegen nur bei App-Store-Plänen |

## Quellen (Kernaussagen)

- Apple: „Associating your App Clip with your website" + „Testing the launch
  experience" — Signatur-/AASA-/App-Store-Connect-Pflicht, Local Experiences
  nur mit Dev/AdHoc/TestFlight-Signatur.
- Apple App Store Connect Help „Maximum build file sizes" — App-Clip-Limits
  10/15/100 MB; 100 MB nur digitale Invocations (kein QR!), iOS 17+.
- MDN/caniuse „Screen Wake Lock API" — Secure Context (HTTPS) zwingend,
  iOS-Safari ab 16.4.
- Stack Overflow „Building iOS applications using xcodebuild without
  codesign" + mehrere produktive GitHub-Workflows (WebView-Wrapper,
  XcodeGen, macos-Runner) — `CODE_SIGNING_ALLOWED=NO`-Flagset +
  Payload-Zip-Packaging.
