# iPad-Setup: Wrapper-App (.ipa) oder Safari

Das Gastgeber-iPad ist die **Bühne** (Bildschirm-Rolle) — oder das Regiepult
(GM). Drei Wege führen dahin: die native Wrapper-App (unsignierte .ipa aus
der CI, per Sideload installiert), pures Safari — oder der **Standalone-Modus**,
in dem das iPad den Spiel-Server gleich **selbst hostet** (Weg 3, kein AMP/PC
nötig). Gäste-iPhones bekommen **nie** eine App — die joinen per QR in Safari
(TECH-SPEC §6).

## Weg 1: Wrapper-App per Sideload (empfohlen für Show-Abende)

Die App ist ein minimaler WKWebView-Wrapper (`ios-wrapper/`) und löst genau
die drei Dinge, die Safari nicht kann: **Display-Sleep aus**, **Landscape-
Lock**, **Jingle-Autoplay ohne Touch**. Erwartete Größe: unter 1 MB.

### .ipa besorgen

Die CI baut bei Änderungen an `ios-wrapper/**` (oder per Run-workflow-Knopf,
Workflow „MONKEY MONEY" → `ipa`-Job) das Artefakt **`monkey-money-unsigned-ipa`**
mit der Datei `MonkeyMoney-unsigned.ipa`. Von der Actions-Seite des Laufs
herunterladen.

### Sideload-Realität (ehrlich)

Die .ipa ist **unsigniert**. Beim Sideload wird sie mit deiner (kostenlosen)
Apple-ID neu signiert. Kostenlose Apple-ID heißt: **7 Tage Laufzeit** (danach
neu sideloaden), **max. 3 Apps** gleichzeitig. Für Party-Nutzung reicht das
locker; mit bezahltem Developer-Account sind es 1 Jahr.

### Variante Sideloadly (PC/Mac)

1. [Sideloadly](https://sideloadly.io) auf PC/Mac installieren.
2. iPad per USB anschließen (beim ersten Mal „Diesem Computer vertrauen").
3. `MonkeyMoney-unsigned.ipa` in Sideloadly ziehen, Apple-ID eintragen,
   „Start".
4. Auf dem iPad: Einstellungen → Allgemein → „VPN & Geräteverwaltung" → dem
   Entwicklerprofil der Apple-ID **vertrauen**.
5. „MONKEY MONEY" vom Home-Bildschirm starten.

### Variante AltStore

1. [AltStore](https://altstore.io) installieren (AltServer auf PC/Mac, dann
   AltStore aufs iPad).
2. `MonkeyMoney-unsigned.ipa` aufs iPad bringen (Dateien-App/AirDrop) und in
   AltStore über „+" installieren — AltStore refresht die 7-Tage-Signatur
   automatisch, solange AltServer im selben WLAN läuft.

### App benutzen

Der Start-Screen hat seit W4 eine klare Hierarchie:

1. **GROSSER Hero-Button „🎪 Party hosten — iPad ist der Server"** — der
   Normalfall für den Spieleabend. Ein Tipp startet den eingebetteten
   Server und lädt die Host-Seite (Details: Weg 3 unten). Kein AMP, kein
   PC, keine Adresse eintippen.
2. Darunter sekundär **„Mit Server verbinden"**: Server-Adresse eingeben
   (z. B. `http://192.168.1.20:8080` — wird gemerkt) und Rolle
   **Bildschirm** wählen → „Verbinden". Die Bühne lädt, Raum-Code + QR +
   GM-PIN erscheinen — Handys scannen den QR. Rolle **Show-Master (GM)**
   lädt stattdessen das Regiepult (`/gm`) — braucht die GM-PIN vom
   Bildschirm.
3. Not-Ausgang zurück zum Start-Screen: mit **3 Fingern lange drücken**.
   Neuladen: Seite mit einem Finger **herunterziehen** (Pull-to-Reload).

Hinweis für Entwickler: Swift kompiliert erst im CI (macos-Job) — die
Start-Screen-Änderungen nutzen bewusst nur UIKit-APIs, die die Datei
schon vorher verwendete (`UIButton.Configuration`, `UIStackView`).

### Guided Access (Geführter Zugriff) — Empfehlung

Sperrt das iPad für den Abend in der App fest (kein versehentliches
Home-Wischen mitten im Finale):

1. Einstellungen → Bedienungshilfen → **Geführter Zugriff** aktivieren (+
   Code festlegen).
2. MONKEY MONEY öffnen → **Dreifachklick** auf die Seitentaste → „Starten".
3. Beenden: Dreifachklick + Code.

## Weg 2: Safari ohne .ipa (der No-Sideload-Fallback)

Funktioniert sofort, mit zwei Handgriffen gegen die Safari-Schwächen:

1. In Safari `http://<lan-ip>:8080/` öffnen → Rolle „Bildschirm" wählen.
2. Optional: Teilen-Menü → **„Zum Home-Bildschirm"** — öffnet ohne
   Adressleiste (funktioniert auch über HTTP; nur die Hülle, kein Offline).
3. **Auto-Sperre aus:** Einstellungen → Anzeige & Helligkeit → Automatische
   Sperre → **Nie** (Safari darf das Display sonst schlafen legen — das
   NoSleep-Video der App hilft, aber „Nie" ist die sichere Bank).
4. **Guided Access** wie oben — sperrt zusätzlich in Safari fest und
   unterdrückt die Auto-Sperre.
5. Audio startet nach dem ersten Tipp aufs „Tippe zum Starten"-Overlay
   (Autoplay-Policy — im Wrapper entfällt das).

## Weg 3: Standalone — das iPad IST der Server (kein AMP, kein PC)

Der Hero-Button des Start-Screens:
**„🎪 Party hosten — iPad ist der Server"**. Damit läuft der KOMPLETTE
Spiel-Server auf dem iPad — Engine, Räume, alle Minigames, GM-Cockpit,
6000+ Fragen, Profile/AT, Save-Slots, Bots. Kein AMP-Server, kein PC,
kein Internet. Beide Betriebsarten stecken in DERSELBEN .ipa: wer einen
Server hat, verbindet sich wie bisher (sekundäre Option darunter).

### So funktioniert es (ein Absatz Technik)

Die App startet einen kleinen HTTP+WebSocket-Server (Port 8080, Swifter) und
lädt eine Host-Seite in die WebView. **Diese Web-Seite ist der Server**: die
Spiellogik ist pures TypeScript und läuft im Browser; Fragen stecken als
JSON-Bundle im Build (`host-content.json`), gespeichert wird in IndexedDB
statt Dateien. Der Swift-Teil versteht NULL Spiellogik — er liefert nur die
Client-Dateien aus und relayt WebSocket-Frames 1:1 zwischen den Handys und
der Host-Seite. Die Handys der Gäste joinen exakt wie immer: QR scannen,
Safari, Name, los (sie erkennen den Standalone-Modus am `?standalone=1` in
der URL und nutzen dann einen simplen WebSocket statt socket.io).

### Benutzen

1. iPad und iPhones ins **selbe WLAN** (oder Hotspot, s. u.).
2. App starten → **„🎪 Party hosten — iPad ist der Server"** tippen.
3. Beim ersten Mal fragt iOS nach der Berechtigung „Lokales Netzwerk" —
   **erlauben** (sonst kommen die Handys nicht durch).
4. Die Host-Seite zeigt oben ein Banner mit der **Server-Adresse GROSS**
   (`http://<ipad-ip>:8080`), einem QR-Code und dem Hinweis „iPhones ins
   gleiche WLAN/Hotspot" — darunter läuft die Bühne mit Raum-Code + QR
   (`http://<ipad-ip>:8080/j/CODE`). Handys scannen, fertig. Das Banner
   lässt sich antippen und schrumpft auf eine schmale Leiste, sobald alle
   drin sind. GM-Cockpit: zweites Gerät (oder Handy) öffnet
   `http://<ipad-ip>:8080/gm` und gibt die PIN von der Bühne ein.
5. Guided Access aktivieren (s. o.) — die App muss den ganzen Abend im
   Vordergrund bleiben.

### Was wird lokal gespeichert (IndexedDB auf dem iPad)

Fortschritt wird **lokal auf dem iPad gespeichert** — der META-Service
läuft im Standalone gegen dieselbe Storage-Abstraktion wie im Node-Pfad,
nur dass statt Dateien IndexedDB im WKWebView dahintersteckt. Konkret:

- **Save-Slots (GM):** „💾 Speichern"/„📂 Laden" im GM-Cockpit sichern den
  kompletten Spielstand (Engine-Zustand, Spieler-Sessions, Raum-Code +
  GM-PIN, Rng-Zustand, Profil-Bindungen) in 3 Slots. Nach einem
  App-Neustart lädt der GM den Slot aus der Lobby — der Raum läuft unter
  dem ALTEN Code weiter, die Handys finden Join-URL und Session wieder.
- **Profile / Affen-Taler / Level:** Spieler-Profile inkl. AT, Level,
  Käufen und Ausrüstung überleben App-Neustarts. Profil anlegen/login
  läuft auf den Handys wie am Node-Server (die `/api/meta`-Aufrufe reisen
  im Standalone als `meta.http`-Event über den WebSocket-Relay).
- **~30-s-Autosave + Boot-Wiederbelebung:** laufende Matches werden alle
  ~30 s automatisch gesichert. Wird die App mitten im Match gekillt,
  belebt der nächste Start das Match aus dem frischen Autosave (< 10 min)
  wieder — für die Gäste ist es nur eine kurze Pause.
- **Match-Event-Log** (Statistik-Futter für Profil-Karten/Boards) läuft
  als Ring-Puffer in IndexedDB.

NICHT gespeichert wird außerhalb des iPads: es gibt keinen Sync, kein
Cloud-Backup — löscht man die App (oder iOS räumt Website-Daten der
WebView ab), sind Spielstände und Profile weg.

### Ehrliche Grenzen (Standalone)

- **App im Vordergrund lassen.** Der Server lebt in der WebView; Home-Wischen
  oder App-Wechsel friert ihn ein (iOS drosselt Hintergrund-Apps). Die App
  hält das Display wach — einfach anlassen, Guided Access hilft.
- **Kein Zurück auf den Start-Screen mitten in der Show** (3-Finger-Longpress
  ist der Not-Ausgang): der Serverzustand lebt in der Seite — dank
  Autosave + Boot-Wiederbelebung ist ein Versehen aber kein Totalverlust
  mehr (s. o.).
- **Kein Admin-Dashboard** im Standalone (`/admin` hängt am Node-Pfad).
  Gast-Joins, alle Minigames, Joker, Teams, GM-Werkzeuge, Profile/AT,
  Save-Slots, Bots: alles da.
- Die App braucht das Web-Bundle (`WebDist/` = `client/dist` + Medien),
  das der ipa-Job beim Bauen einpackt — die .ipa ist dadurch ~70–90 MB
  groß (Fragen + Bilder + Videos).

### Testen ohne iPad (Entwickler)

Derselbe Browser-Server läuft auch in Desktop-Chrome — mit einem
Node-Relay als Swift-Stellvertreter (identischer Frame-Vertrag):

```bash
npm run build:client
node tools/ipad-host/relay-sim.mjs     # http://localhost:8093/host = „das iPad"
node tools/ipad-host/proof-standalone.mjs   # automatisierter End-zu-End-Beweis
```

## Unterwegs ohne Router: der Hotspot-Flow (DIE Lösung)

Kein WLAN am Ferienhaus/Garten/Zug? Es braucht **keinen Router** — nur ein
Gerät, das ein WLAN aufspannt. Internet ist fürs Spiel egal, das LAN reicht.

**Fall A — iPad mit Cellular (SIM/eSIM):**

1. iPad: Einstellungen → **Persönlicher Hotspot** → „Zugriff für andere
   erlauben" AN (WLAN-Passwort steht dort).
2. Alle iPhones: WLAN → das iPad-Netz wählen, Passwort eingeben.
3. App → **Standalone** starten → QR scannen → spielen. Das iPad ist
   gleichzeitig Access-Point UND Server.

**Fall B — iPad ohne Cellular (WLAN-only):** ein WLAN-only-iPad kann
**keinen** Hotspot aufspannen (Personal Hotspot ist eine Cellular-Funktion —
der Menüpunkt existiert dort schlicht nicht). Der Trick: **irgendein iPhone
spannt den Hotspot auf**, z. B. das des Gastgebers:

1. iPhone des Gastgebers: Einstellungen → Persönlicher Hotspot → AN.
2. **iPad** in dieses Hotspot-WLAN hängen (Einstellungen → WLAN).
3. Gäste-iPhones ins selbe Hotspot-WLAN.
4. iPad-App → Standalone → QR scannen → spielen. Das iPad bleibt der
   Server; das Hotspot-iPhone kann trotzdem normal mitspielen.

Geräte im selben persönlichen Hotspot können sich gegenseitig erreichen
(kein AP-Isolation-Problem wie in manchen Hotel-WLANs). Mobilfunk-Daten
werden fürs Spiel **nicht** verbraucht — der Verkehr bleibt lokal.

## Bluetooth-Sync iPad↔iPhones? Die ehrliche Antwort: Nein.

Die Idee „Handys verbinden sich per Bluetooth, ganz ohne WLAN" scheitert an
zwei harten Fakten (Stand 2026, geprüft):

1. **Safari/iOS hat KEIN Web-Bluetooth.** WebKit lehnt die API offiziell ab
   (Position „oppose", Datenschutz/Fingerprinting), und weil Apple ALLE
   iOS-Browser auf WebKit zwingt, gilt das auch für Chrome/Edge auf dem
   iPhone. Es gibt nur Nischen-Apps (Bluefy, WebBLE), die eine eigene
   Bluetooth-Brücke mitbringen — dann müssten die Gäste aber eine App
   installieren, und genau das verbietet unser „QR → Safari → drin"-Prinzip.
2. **MultipeerConnectivity** (Apples Bluetooth/Peer-WLAN-Framework) wäre
   technisch schön — läuft aber nur in **nativen Apps auf JEDEM Gerät**.
   Gäste-iPhones ohne App-Store-App (unsere .ipa ist Sideload-only!) können
   daran nicht teilnehmen. Gleiches Argument tötet AWDL/AirDrop-artige Pfade.

Selbst wenn es ginge, wäre BLE fürs Quiz eng (Durchsatz, 8 gleichzeitige
Verbindungen, Latenz-Jitter beim Buzzern). **Die praktikable „ohne
Infrastruktur"-Lösung ist der Hotspot-Flow oben** — der funktioniert heute,
ohne App-Installation auf den Gäste-Handys, und trägt problemlos 8 Spieler.

## Warum keine App Clips? (QR scannen → App öffnet sich)

Die Idee lag nahe: Gäste scannen den QR und bekommen einen App Clip statt
Safari. **Das geht mit unsignierten Builds/Sideload definitiv nicht**
(TECH-SPEC §6.3):

1. App Clips brauchen das Associated-Domains-Entitlement (`appclips:…`) —
   das steckt in der **Code-Signatur**, und eine unsignierte .ipa hat keine
   verwertbare.
2. Apple validiert eine AASA-Datei auf einer **öffentlichen HTTPS-Domain**
   gegen den signierten Clip — unser Primärpfad ist HTTP im LAN.
3. App Clips werden ausschließlich über **App Store Connect** ausgeliefert;
   selbst „Local Experiences" verlangen Dev-/AdHoc-/TestFlight-Signatur.
4. Es gibt **keinen Sideload-Kanal** für das On-Demand-System der Clips.

**Stattdessen:** QR → Safari. Der Join dauert unter 20 Sekunden (Scan → Name +
Farbe → drin), braucht keinerlei Installation und funktioniert auf jedem
iPhone. Wiedervorlage nur, falls MONKEY MONEY je in den App Store geht.
