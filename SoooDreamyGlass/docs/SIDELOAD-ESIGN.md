# SoooDreamy mit ESign sideloaden / Sideloading SoooDreamy with ESign

Stand / as of: v10.1, Sommer/summer 2026. IPA-Quelle / IPA source:
[Rolling-Release `sooodreamy-latest`](https://github.com/MedusaV9/BiggerRepo/releases/tag/sooodreamy-latest)
(`SoooDreamy-unsigned-<version>.ipa` und/and `SoooDreamy-Lite-unsigned-<version>.ipa`).
Verwandt / related: [`SOOODREAMY-LITE.md`](SOOODREAMY-LITE.md) (Bundle-IDs & Widgets),
[`HANDBUCH.de.md`](HANDBUCH.de.md) · [`MANUAL.en.md`](MANUAL.en.md) (AltStore/SideStore/Sideloadly).

---

## 🇩🇪 Deutsch

### Der ESign-Stand 2026 (bitte zuerst lesen)

ESign ist ein On-Device-Signierer: Er signiert IPAs **direkt auf dem iPhone**
mit einem Apple-Zertifikatspaar (`.p12` + `.mobileprovision`) — kein Computer,
kein 7-Tage-Rhythmus. Der Preis dafür ist das Zertifikat selbst. Ehrlicher
Stand Sommer 2026:

- **Das Original-ESign wird nicht mehr weiterentwickelt** (Entwicklung ca.
  2025 eingestellt). Die App kursiert weiter und funktioniert auch auf
  aktuellen iOS-Versionen, bekommt aber keine Updates mehr.
- **Die Community ist auf Nachfolger umgestiegen.** Der bekannteste ist
  **KSign** (Open Source, auf Feather-Basis, bewusst als „ESign-Nachbau“
  gestaltet); daneben existieren weitere Feather-Ableger (z. B. unter Namen
  wie KravaSign) und kommerzielle Signer wie Scarlet oder GBox. Namen und
  Bezugsquellen ändern sich schnell — alles in diesem Guide gilt genauso für
  diese Forks, die Menüs heißen fast identisch.
- **Zertifikate sind der Engpass:** Kostenlose „geteilte“ Zertifikate von
  Cert-Seiten/Telegram-Kanälen werden 2026 quasi wöchentlich von Apple
  widerrufen (Revoke) — dann öffnen alle damit signierten Apps schlagartig
  nicht mehr, bis neu signiert wird. Bezahlte „private“ Zertifikate
  (an eure Geräte-UDID gebunden) halten deutlich länger (Wochen bis Monate).
  Anti-Revoke-DNS-Profile helfen immer seltener.
- **Einordnung für SoooDreamy:** Wer Widgets will und einen Rechner hat, ist
  mit AltStore/SideStore (kostenlose Apple-ID, App Groups werden sauber
  mitsigniert) weiterhin am verlässlichsten unterwegs. ESign/KSign lohnt sich
  vor allem **ohne Rechner** oder **mit bezahltem privatem Zertifikat**.

### Was ihr braucht

1. Das unsignierte IPA aus dem
   [Rolling-Release `sooodreamy-latest`](https://github.com/MedusaV9/BiggerRepo/releases/tag/sooodreamy-latest):
   `SoooDreamy-unsigned-<version>.ipa` (Standard, mit Widgets) oder
   `SoooDreamy-Lite-unsigned-<version>.ipa` (ohne Widgets, nur eine Bundle-ID).
2. ESign bzw. einen ESign-Fork (KSign o. ä.), installiert und in
   **Einstellungen → Allgemein → VPN & Geräteverwaltung** vertraut.
3. Ein Zertifikatspaar: `.p12`-Datei + zugehöriges Passwort +
   `.mobileprovision`-Profil (kostenlos von Cert-Seiten oder bezahlt/privat).

### Schritt für Schritt

1. **IPA laden:** Auf dem iPhone die Release-Seite öffnen und
   `SoooDreamy-unsigned-<version>.ipa` in die Dateien-App laden.
2. **Zertifikat importieren:** In ESign unter dem Profil-/Ich-Tab die
   Zertifikatsverwaltung öffnen („Certificate Management“), `.p12` +
   `.mobileprovision` importieren und das `.p12`-Passwort eingeben. Das
   Zertifikat als aktiv auswählen.
3. **IPA importieren:** Im Dateien-Bereich von ESign das IPA auswählen
   („Import“ → aus der Dateien-App) und dann **„In App-Bibliothek
   importieren“** / „Import to app library“ antippen.
4. **Signieren — hier entscheidet sich alles mit den Widgets:**
   - Das Standard-IPA enthält **zwei** Bundles: die App
     (`app.sooodreamy.ios`) und die Widget-Extension
     (`app.sooodreamy.ios.widgets`) im `PlugIns/`-Ordner.
     **Beide müssen mitsigniert werden** — Details unten.
   - In den Signatur-Optionen **keine** Option wie „App-Erweiterungen
     entfernen“ / „Remove plug-ins“ / „Delete app extensions“ aktivieren.
     Manche ESign-Versionen bieten das an, weil es Signierprobleme
     „wegräumt“ — danach gibt es schlicht keine Widgets mehr.
   - Wenn ihr die Bundle-ID ändert (bei geteilten Zertifikaten teils nötig):
     Die Extension-ID **muss ein Kind der App-ID bleiben** — aus
     `com.euer.name` wird also zwingend `com.euer.name.widgets`. ESign-Forks
     mit „ID ändern“-Automatik machen das meist richtig; kontrolliert es.
5. **Installieren & vertrauen:** „Signieren“ antippen, danach „Installieren“.
   Fragt iOS nach Vertrauen: **Einstellungen → Allgemein → VPN &
   Geräteverwaltung** → euer Zertifikat → „Vertrauen“. Dann SoooDreamy öffnen.

### Widgets: Extensions, Profile und App Groups (die Stolperfallen)

**Stolperfalle 1 — Extensions brauchen ein passendes Profil.** Bei Apple ist
eine Widget-Extension eine eigene App mit eigener Bundle-ID. Ein
`.mobileprovision`-Profil deckt entweder genau **eine** App-ID ab (explizit)
oder **alle** (Wildcard `*`). ESign & Co. signieren mit **einem** Paar aus
Zertifikat + Profil:

- **Wildcard-Profil** (bei den meisten geteilten und bezahlten
  Distribution-Zertifikaten üblich): deckt App **und** Extension ab —
  Widgets sind signierbar. ✅
- **Explizites Profil** (nur eine feste App-ID): deckt die Extension NICHT
  ab. Typisches Symptom: App läuft, Widgets tauchen nirgends auf. In dem
  Fall braucht ihr ein Wildcard-Profil, einen anderen Weg (AltStore/
  SideStore) — oder die Lite-IPA. ❌

**Stolperfalle 2 — App Groups.** Damit die Widgets echte Daten zeigen,
teilen sich App und Extension die App Group
`group.app.sooodreamy.shared`. Dieses Entitlement muss das Signier-Tool in
**beide** Bundles schreiben und das Zertifikat/Profil muss App Groups
erlauben. Geteilte Gratis-Zertifikate tun das oft nicht. Symptom: Widgets
lassen sich hinzufügen, zeigen aber dauerhaft nur Platzhalter.

**Wenn euer (Gratis-)Weg keine App Groups oder keine zweite App-ID
hergibt:** Nehmt die **Lite-IPA** (`SoooDreamy-Lite-unsigned-<version>.ipa`).
Sie ist dieselbe App mit nur **einer** Bundle-ID und ohne Widget-Extension —
signiert garantiert überall. Kopplung und lokale Daten bleiben beim späteren
Wechsel auf die Standard-IPA erhalten (gleiche App-Bundle-ID). Details:
[`SOOODREAMY-LITE.md`](SOOODREAMY-LITE.md). Zur Einordnung: Eine kostenlose
Apple-ID erlaubt außerdem nur 10 App-ID-Registrierungen pro 7 Tage — die
Standard-IPA verbraucht davon zwei (App + Extension), die Lite-IPA eine.

### Welcher Weg für wen? (Vergleich)

| | ESign / KSign & Forks | Feather | AltStore / SideStore |
| --- | --- | --- | --- |
| Widgets (App Group) | ✅ mit Wildcard-Profil + App-Groups-fähigem Zertifikat; ❌ mit vielen Gratis-Zertifikaten → Lite-IPA | ⚠️ bekannte Schwäche: Profile je Extension werden nicht unterstützt, Widgets registrieren sich oft nicht | ✅ signiert App + Extension + App Group mit eurem persönlichen Team |
| 7-Tage-Refresh nötig? | Nein — gilt, solange das Zertifikat lebt (Revoke-Risiko!) | Nein mit bezahltem Developer-Zertifikat (1 Jahr); ja mit Gratis-Apple-ID | Ja (kostenlose Apple-ID); AltStore refresht per AltServer, SideStore on-device |
| Rechner nötig? | Nein | Nein | AltStore: ja, wöchentlich im selben WLAN · SideStore: nur einmalig fürs Setup |
| Kosten | Gratis-Zertifikate (revoke-anfällig) oder privates Zertifikat (kostenpflichtig) | am sinnvollsten mit Apple Developer Program (~99 €/Jahr) | kostenlos |
| Größtes Risiko | Zertifikat-Revoke: alle Apps tot bis zur Neusignatur | Widgets/Extensions | 3-App-Limit, 7-Tage-Ablauf |

**Empfehlung 2026:** Widgets wichtig + Rechner vorhanden → AltStore/SideStore.
Kein Rechner → KSign/ESign mit privatem (bezahltem) Zertifikat; mit
Gratis-Zertifikat die Lite-IPA nehmen und die Widgets abhaken. Feather ist
super für Leute mit bezahltem Developer-Account — aber wegen der
Extension-Schwäche für SoooDreamy-Widgets nur zweite Wahl.

### Troubleshooting

- **Widgets erscheinen nicht in der Widget-Galerie:** iPhone neu starten,
  App einmal öffnen, dann in der Galerie erneut suchen; hilft das nicht,
  Widget entfernen und neu hinzufügen. Bleiben sie verschwunden, wurde die
  Extension beim Signieren entfernt oder vom Profil nicht abgedeckt →
  neu signieren (Wildcard-Profil, Extension NICHT entfernen lassen).
- **Widgets zeigen nur Platzhalter:** App Group wurde nicht mitsigniert
  (siehe Stolperfalle 2). App einmal öffnen und im Widget-Studio den
  App-Group-Status prüfen; sonst Weg wechseln oder Lite-IPA.
- **„Nicht vertrauenswürdiger Entwickler“ beim ersten Start:**
  Einstellungen → Allgemein → VPN & Geräteverwaltung → Zertifikat →
  „Vertrauen“. Neuere iOS-Versionen verlangen danach teils einen Neustart.
- **„App-Integrität konnte nicht überprüft werden“ / alle Apps öffnen
  plötzlich nicht mehr:** Das Zertifikat wurde von Apple widerrufen.
  Frisches Zertifikat importieren und alle Apps neu signieren — eure
  Serverdaten und die Kopplung sind davon nicht betroffen
  („Wieder verbinden“, siehe [`RECOVERY.md`](RECOVERY.md)).
- **App startet nach 7 Tagen nicht mehr** (Gratis-Apple-ID-Weg über
  Feather/AltStore/SideStore): Signatur abgelaufen — einfach neu
  signieren/refreshen, Daten bleiben.
- **ESign selbst ist verschwunden/deaktiviert:** Auch ESign hängt an einem
  Zertifikat. Neu beziehen (bzw. auf KSign umsteigen), dann Apps neu
  signieren.

---

## 🇬🇧 English

### The state of ESign in 2026 (read this first)

ESign is an on-device signer: it signs IPAs **directly on the iPhone** using
an Apple certificate pair (`.p12` + `.mobileprovision`) — no computer, no
7-day cycle. The price you pay is the certificate itself. The honest picture
as of summer 2026:

- **The original ESign is no longer developed** (development ended around
  2025). The app still circulates and works on current iOS versions, but it
  receives no updates.
- **The community has moved to successors.** The best-known one is
  **KSign** (open source, built on Feather, deliberately designed as an
  “ESign recreation”); other Feather offshoots exist (e.g. under names like
  KravaSign), plus commercial signers such as Scarlet or GBox. Names and
  download sources change quickly — everything in this guide applies to
  those forks too; the menus are nearly identical.
- **Certificates are the bottleneck:** free “shared” certificates from cert
  sites/Telegram channels get revoked by Apple almost weekly in 2026 — all
  apps signed with them stop opening at once until re-signed. Paid
  “private” certificates (bound to your device UDID) last considerably
  longer (weeks to months). Anti-revoke DNS profiles help less and less.
- **What this means for SoooDreamy:** if you want widgets and own a
  computer, AltStore/SideStore (free Apple ID, App Groups co-signed
  properly) remains the most reliable route. ESign/KSign shines when you
  have **no computer** or a **paid private certificate**.

### What you need

1. The unsigned IPA from the
   [rolling release `sooodreamy-latest`](https://github.com/MedusaV9/BiggerRepo/releases/tag/sooodreamy-latest):
   `SoooDreamy-unsigned-<version>.ipa` (default, with widgets) or
   `SoooDreamy-Lite-unsigned-<version>.ipa` (no widgets, single bundle id).
2. ESign or an ESign fork (KSign etc.), installed and trusted under
   **Settings → General → VPN & Device Management**.
3. A certificate pair: `.p12` file + its password + a `.mobileprovision`
   profile (free from cert sites, or paid/private).

### Step by step

1. **Download the IPA:** open the release page on the iPhone and save
   `SoooDreamy-unsigned-<version>.ipa` to the Files app.
2. **Import the certificate:** in ESign, open certificate management on the
   profile/me tab, import `.p12` + `.mobileprovision`, and enter the `.p12`
   password. Select the certificate as active.
3. **Import the IPA:** in ESign's files section, pick the IPA (“Import” →
   from the Files app), then tap **“Import to app library”**.
4. **Sign — this is where the widgets are won or lost:**
   - The default IPA contains **two** bundles: the app
     (`app.sooodreamy.ios`) and the widget extension
     (`app.sooodreamy.ios.widgets`) inside `PlugIns/`.
     **Both must be signed** — details below.
   - In the signing options, do **not** enable anything like “remove
     plug-ins” / “delete app extensions”. Some ESign builds offer this
     because it makes signing problems “go away” — and your widgets with
     them.
   - If you change the bundle id (sometimes necessary with shared
     certificates): the extension id **must remain a child of the app id**
     — `com.your.name` requires `com.your.name.widgets`. Forks with an
     automatic id rewrite usually get this right; verify it.
5. **Install & trust:** tap “Sign”, then “Install”. If iOS asks for trust:
   **Settings → General → VPN & Device Management** → your certificate →
   “Trust”. Then open SoooDreamy.

### Widgets: extensions, profiles, and App Groups (the pitfalls)

**Pitfall 1 — extensions need a matching profile.** To Apple, a widget
extension is its own app with its own bundle id. A `.mobileprovision`
profile covers either exactly **one** app id (explicit) or **all** of them
(wildcard `*`). ESign & friends sign with **one** certificate + profile
pair:

- **Wildcard profile** (typical for most shared and paid distribution
  certificates): covers app **and** extension — widgets can be signed. ✅
- **Explicit profile** (a single fixed app id): does NOT cover the
  extension. Typical symptom: the app runs, but widgets never appear
  anywhere. You then need a wildcard profile, a different route
  (AltStore/SideStore) — or the Lite IPA. ❌

**Pitfall 2 — App Groups.** For widgets to show real data, app and
extension share the App Group `group.app.sooodreamy.shared`. The signing
tool must write this entitlement into **both** bundles, and the
certificate/profile must permit App Groups. Shared free certificates often
don't. Symptom: widgets can be added but forever show placeholders.

**If your (free) route offers no App Groups or no second app id:** use the
**Lite IPA** (`SoooDreamy-Lite-unsigned-<version>.ipa`). It is the same app
with a single bundle id and no widget extension — it signs everywhere.
Pairing and local data survive a later switch to the default IPA (same app
bundle id). Details: [`SOOODREAMY-LITE.md`](SOOODREAMY-LITE.md). For
context: a free Apple ID also allows only 10 app-id registrations per
7 days — the default IPA consumes two of them (app + extension), Lite one.

### Which route for whom? (comparison)

| | ESign / KSign & forks | Feather | AltStore / SideStore |
| --- | --- | --- | --- |
| Widgets (App Group) | ✅ with a wildcard profile + App-Groups-capable certificate; ❌ with many free certificates → Lite IPA | ⚠️ known weakness: per-extension profiles unsupported, widgets often fail to register | ✅ signs app + extension + App Group with your personal team |
| 7-day refresh needed? | No — valid as long as the certificate lives (revoke risk!) | No with a paid developer certificate (1 year); yes with a free Apple ID | Yes (free Apple ID); AltStore refreshes via AltServer, SideStore on-device |
| Computer needed? | No | No | AltStore: yes, weekly on the same Wi-Fi · SideStore: only once for setup |
| Cost | free certificates (revoke-prone) or a private certificate (paid) | most sensible with the Apple Developer Program (~$99/year) | free |
| Biggest risk | certificate revoke: all apps dead until re-signed | widgets/extensions | 3-app limit, 7-day expiry |

**2026 recommendation:** widgets matter + computer available →
AltStore/SideStore. No computer → KSign/ESign with a private (paid)
certificate; with a free certificate take the Lite IPA and let the widgets
go. Feather is great for people with a paid developer account — but its
extension weakness makes it second choice for SoooDreamy widgets.

### Troubleshooting

- **Widgets don't appear in the widget gallery:** restart the iPhone, open
  the app once, then search the gallery again; if that fails, remove and
  re-add the widget. If they stay gone, the extension was stripped during
  signing or not covered by the profile → re-sign (wildcard profile, do NOT
  let the tool remove the extension).
- **Widgets only show placeholders:** the App Group wasn't co-signed (see
  pitfall 2). Open the app once and check the App Group status in the
  Widget Studio; otherwise switch routes or use the Lite IPA.
- **“Untrusted Developer” on first launch:** Settings → General → VPN &
  Device Management → certificate → “Trust”. Recent iOS versions sometimes
  require a restart afterwards.
- **“App integrity could not be verified” / all apps suddenly stop
  opening:** Apple revoked the certificate. Import a fresh certificate and
  re-sign all apps — your server data and pairing are unaffected
  (“Reconnect”, see [`RECOVERY.md`](RECOVERY.md)).
- **The app stops launching after 7 days** (free-Apple-ID route via
  Feather/AltStore/SideStore): the signature expired — simply
  re-sign/refresh; data stays.
- **ESign itself disappeared/got disabled:** ESign hangs off a certificate
  too. Re-obtain it (or switch to KSign), then re-sign your apps.
