# SoooDreamy Handbuch

<p align="center">
  <strong>Die App für euch zwei</strong><br />
  made by Sonic0810
</p>

Version des Handbuchs: 16.0.0 · Sprache: Deutsch · Ton: warm, direkt und ehrlich

Dieses Handbuch erklärt Installation, Server, Kopplung, alle fünf Tabs und die Grenzen eines unsignierten Builds. Seit 4.9 verlinkt die App direkt in diese Kapitel.

<a id="handbook-setup"></a>
## 1. Schnellstart

Ihr braucht:

1. einen Computer, NAS, Raspberry Pi oder Cloud-Server mit Node.js 20 oder neuer;
2. zwei iPhones oder iPads mit iOS/iPadOS 26 oder neuer (iPad seit 12.0; frühere Versionen liefen ab iOS 17);
3. das aktuelle unsignierte IPA aus dem rollenden GitHub-Release
   `sooodreamy-latest` (`versions/` archiviert nur Releases 4.1 bis 6.0);
4. AltStore, SideStore oder Sideloadly zum Signieren und Installieren.

### Server starten

```bash
git clone https://github.com/MedusaV9/BiggerRepo.git
cd BiggerRepo/SoooDreamy/server
npm ci
npm test
HOST=0.0.0.0 PORT=4321 npm start
```

`npm test` braucht weder Datenbank noch externe Dienste. Vor jeder
Erfolgsantwort schreibt und synchronisiert der Server die Änderung dauerhaft
ins Write-ahead-Journal; die JSON-Segmente sind die nachgelagerte
Kompaktierung. Ein exklusiver Datenordner-Lock verhindert Doppelstarts.
`GET /api/health` zeigt Segment-/Mediengröße, Backup-Schutz und Quarantäne.

### Sichere Adresse wählen

- Standard: HTTP/WS funktioniert für das bewusst kleine private Setup, ist
  aber unverschlüsselt — nur in einem vertrauten Netz betreiben.
- `ALLOW_HTTP_PRIVATE_LAN=1` beschränkt HTTP auf Loopback/private/Tailscale-
  Quelladressen.
- Öffentlich: HTTPS/WSS über Caddy/nginx mit `TRUST_PROXY=1 REQUIRE_HTTPS=1`.
- Die Adresse muss den Port enthalten, wenn euer Proxy nicht den Standardport 443 nutzt.

## 2. IPA installieren

Das Archiv enthält ein unsigniertes Geräte-IPA. iOS akzeptiert es erst, nachdem ein Sideload-Tool App und Erweiterungen mit eurem Profil signiert hat.

### AltStore

1. AltStore auf dem iPhone einrichten.
2. In AltStore „My Apps“ öffnen und `+` wählen.
3. `SoooDreamy-<version>-unsigned.ipa` auswählen.
4. Prüfen, dass App und Widget-Erweiterung gemeinsam signiert wurden.

### SideStore

1. SideStore samt Pairing-Datei und VPN-Tunnel einrichten.
2. Das IPA in SideStore importieren.
3. Vor Ablauf der Signatur bei aktiver SideStore-Verbindung aktualisieren.

### Sideloadly

1. iPhone per Kabel oder WLAN mit dem Computer verbinden.
2. IPA in Sideloadly ziehen, Apple-ID wählen und installieren.
3. Das Entwicklerprofil auf dem iPhone erlauben, falls iOS danach fragt.

### ESign / KSign (ohne Rechner)

1. Zertifikatspaar (`.p12` + `.mobileprovision`) in ESign bzw. KSign importieren.
2. Das IPA laden und in die App-Bibliothek importieren.
3. Beim Signieren die Widget-Erweiterung **nicht** entfernen lassen — beide Bundle-IDs (`app.sooodreamy.ios` + `app.sooodreamy.ios.widgets`) müssen vom Profil abgedeckt sein (Wildcard-Profil).
4. Installieren und das Zertifikat unter Einstellungen → Allgemein → VPN & Geräteverwaltung vertrauen.

Ehrlicher 2026-Stand: Das Original-ESign wird nicht mehr gepflegt (bekanntester Nachfolger: KSign auf Feather-Basis), und kostenlose geteilte Zertifikate werden häufig widerrufen — dann öffnen alle damit signierten Apps nicht mehr, bis neu signiert wird. Kann euer Zertifikat keine App Groups, zeigen Widgets nur Platzhalter — dann die Lite-IPA nehmen ([`SOOODREAMY-LITE.md`](SOOODREAMY-LITE.md)). Ausführlich mit Vergleichstabelle und Troubleshooting: [`SIDELOAD-ESIGN.md`](SIDELOAD-ESIGN.md).

### Ehrliche Sideload-Grenzen

| Bereich | Kostenlose Apple-ID |
|---|---|
| Signatur | üblicherweise 7 Tage gültig |
| Aktive Apps | höchstens 3 sideloaded Apps |
| Widgets | funktionieren, wenn das Tool die App Group mitsigniert |
| Remote-Push | meist nicht verfügbar; bezahltes Profil + APNs-Serverdaten nötig |
| iCloud/CloudKit | Entitlements werden oft entfernt |
| Lokale Erinnerungen | verfügbar, wenn iOS die Erlaubnis erteilt |
| Datei-Export | verfügbar und AES-GCM-verschlüsselt |

Ein Ablauf der Signatur löscht nicht automatisch eure Serverdaten. Installiert die neu signierte App mit demselben Bundle-Identifier darüber. Haltet euren Paar-Code beziehungsweise ein aktuelles verschlüsseltes Backup bereit.

## 3. Server verbinden und Paar koppeln

Die erste Onboarding-Seite bietet **drei Wege** an — der schnellste steht bewusst zuerst:

1. **„Einladung scannen“:** Hat euer Schatz schon ein Paar erstellt, öffnet dieser Weg direkt die Kamera. Der Einladungs-QR bringt Serveradresse UND Paar-Code in einem Schritt mit — nichts abtippen, nichts nachschlagen.
2. **„Server verbinden“:** Der klassische Weg für die erste Person — Servername und vollständige Adresse eingeben, „Verbindung testen“ tippen (die App zeigt die gemeldete Server-Version), dann das Paar erstellen und den sechsstelligen Code oder QR-Code teilen.
3. **„Was euch erwartet“:** Erst schauen, dann entscheiden — die kleine Tour durch die App-Idee.

Danach prüfen beide Namen, Avatar und Farbe. Der QR-Code enthält Serveradresse und Paar-Code. Teilt ihn nur über einen vertrauten Kanal. Sitzungstokens gehören in den Keychain und werden nicht in Exportdateien geschrieben.

Seit 10.0 führt ein vierseitiges Onboarding durch App-Idee, Server-Prinzip und das Sicherheitsnetz, bevor der erste Server eingetragen wird. Die Sprache ist oben links jederzeit umschaltbar, „Überspringen“ springt zur letzten Seite.

Seit 12.0 endet das Onboarding mit einem Wegweiser aus drei Schritten (Server verbinden → Paar koppeln → Loslegen). Wer erst schauen möchte, tippt **„Erst mal ansehen“**: Der Demo-Modus öffnet die App mit einem Beispiel-Paar, ganz ohne Server — alles darin ist Beispiel-Inhalt und verschwindet spurlos, der Ausstieg („Eigenen Server verbinden“) ist als Badge immer sichtbar. Und der Moment des Koppelns ist eine kleine Zeremonie: eure beiden Farben verschmelzen — auch beim Verbinden eines Zweitgeräts.

### Das Sicherheitsnetz (10.0)

Beim Koppeln erhält jede Person einen **Wiederherstellungs-Schlüssel** (`rec_…`). Er wandert automatisch in den iCloud-Schlüsselbund und wird direkt nach dem Koppeln einmalig angezeigt — schreibt ihn zusätzlich auf, Papier stirbt nie. Der Server speichert nur den SHA-256-Fingerabdruck, nie den Schlüssel selbst. Wer vor 10.0 gekoppelt hat, bekommt beim ersten Start still einen Schlüssel nachgereicht.

Damit gilt:

- **Abgelaufene Sitzung:** Die App repariert sich selbst im Hintergrund (alter Token oder Schlüssel als Beweis). Ihr merkt höchstens einen kurzen Hinweis „Verbindung still erneuert“.
- **Neues Handy / Neuinstallation:** Auf dem Koppel-Bildschirm den dritten Tab **„Wieder verbinden“** wählen. Paar-Code + Schlüssel — liegt der Schlüssel im iCloud-Schlüsselbund, reicht ein einziger Tipp. Verlauf, Statistiken und Abzeichen bleiben vollständig erhalten.
- **Alles verloren:** Der Schatz erzeugt unter **Mehr → Sicherheit & Wiederherstellung** einen einmaligen **Ersatz-Code** (8 Zeichen, 15 Minuten gültig). Damit verbindet ihr euch ohne Schlüssel neu auf euren eigenen Platz. Sicherheit: Alle alten Geräte und der alte Schlüssel des ersetzten Platzes werden dabei ungültig.

In **Mehr → Sicherheit & Wiederherstellung** könnt ihr den Schlüssel ansehen (maskiert, auf Wunsch vollständig), kopieren und rotieren — der alte Schlüssel wird beim Rotieren sofort ungültig. Ehrliche Grenze: Der iCloud-Schlüsselbund braucht eine Signatur mit Schlüsselbund-Berechtigung; nackte Sideloads speichern den Schlüssel nur lokal — dann zählt der Zettel.

### Mehrere Geräte pro Person (12.0)

Jede Person kann iPhone UND iPad (und mehr) gleichzeitig verbinden — dieselbe Anmeldung, derselbe gemeinsame Platz:

1. Auf dem schon verbundenen Gerät **Mehr → Sicherheit & Wiederherstellung → Geräte → „Gerät hinzufügen“** öffnen und einen **Einmal-Code** erzeugen (zeitlich begrenzt, genau einmal einlösbar).
2. Auf dem neuen Gerät SoooDreamy öffnen und im Onboarding **„Ich habe schon ein Gerät“** wählen: QR scannen, Code eintippen oder den `sooodreamy://link`-Deep-Link öffnen — Server-Adresse und Code stecken schon drin.
3. Fertig — die Farbverschmelzungs-Zeremonie begrüßt das Gerät, und auf euren anderen Geräten erscheint ein leiser Hinweis („Neues Gerät verbunden“).

Der **Geräte-Manager** liegt im Sicherheitsbereich unter **Mehr → Sicherheit & Wiederherstellung → Geräte**: Er zeigt alle Plätze („Dieses Gerät“ ist markiert, höchstens 8 pro Person) und meldet einzelne Geräte gezielt ab — abgemeldete Geräte verlieren sofort den Zugang. Eigene Geräte verwirren euch dabei nie gegenseitig: Was du am iPad schreibst, zeigt dein iPhone als dezenten Haken, nicht als Partner-Ereignis. Sicherheit: Ein Einmal-Code allein öffnet kein fremdes Paar — er entsteht immer auf einem bereits verbundenen Gerät und läuft von selbst ab.

<a id="handbook-rejoin"></a>
## 4. Wieder verbinden

Für fast jede Situation gibt es einen Weg zurück auf euren eigenen Platz samt Verlauf, Statistiken und Abzeichen — wir helfen euch Schritt für Schritt. Ehrlich dabei: Jeder Weg braucht mindestens einen Beweis (Schlüssel, Schatz oder Server-Betreiberin). Sind wirklich alle drei verloren, bleibt nur eine neue Kopplung. Der Reihe nach prüfen:

1. **Nichts tun:** Abgelaufene Sitzungen heilen sich selbst — höchstens erscheint kurz „🗝️ Verbindung still erneuert — weiter geht's“.
2. **Ein-Tap:** Zeigt der Koppel-Bildschirm im Tab **„Wieder verbinden“** die Karte „Schlüssel im Schlüsselbund gefunden — einfach auf „Wieder verbinden“ tippen.“, reicht genau dieser eine Tipp (gleiches Gerät, oder neues Handy aus iCloud-/Gerätebackup).
3. **Login-QR vom Admin-Panel:** Die Server-Betreiberin erzeugt im Panel unter „Login-QR“ → „QR für {Name} erzeugen“ einen 30 Minuten gültigen Einmal-QR. In der App **„Wieder verbinden“ → „QR-Code scannen“** — ein Scan, wieder drin; Replay und Ablauf werden abgelehnt (siehe Kapitel 5).
4. **Partner hilft:** Der Schatz öffnet **Mehr → Sicherheit & Wiederherstellung → Sicherheitsnetz → „Schatz ausgesperrt?“ → „Ersatz-Code erzeugen“** und zeigt den QR (einmalig, 15 Minuten gültig). Scannen — fertig.
5. **Alles manuell:** **„Wieder verbinden“ → „Code eintippen“** → Paar-Code plus Wiederherstellungs-Schlüssel vom Zettel; oder den Schalter „Ich habe einen Ersatz-Code von meinem Schatz“ aktivieren und den Ersatz-Code eintippen.

Sicherheit: Der Ersatz-Code ersetzt bewusst die alten Geräte des ausgesperrten Platzes — alte Sitzungen und der alte Schlüssel werden ungültig, danach gibt es einen frischen Schlüssel. Das vollständige Runbook mit Entscheidungsbaum, exakten Bildschirm-Wortlauten und Fehlermeldungen: [`RECOVERY.md`](RECOVERY.md).

<a id="handbook-admin"></a>
## 5. Server & Admin-Panel

Das Admin-Panel läuft im Serverprozess mit — nichts extra zu starten, kein zweiter Port. Beim Serverstart druckt die Konsole einen gerahmten Banner mit der URL (`http://…/admin`) und einem frischen Passwort; es gilt bis zum nächsten Neustart und wird nirgends gespeichert.

Aus Nutzersicht zählt vor allem der **Login-QR** — der bequemste Weg zurück, wenn kein Schlüssel zur Hand ist:

1. Die Betreiberin meldet sich im Panel an und klappt euer Paar auf.
2. Im Tab **„Login-QR“** prüft sie „Server-URL im QR“ (eine Adresse, die euer Handy erreicht) und tippt **„QR für {Name} erzeugen“** für den richtigen Platz.
3. Ihr scannt den QR in der App (**„Wieder verbinden“ → „QR-Code scannen“**) oder direkt mit der iOS-Kamera — der `sooodreamy://rejoin`-Link öffnet SoooDreamy und meldet das Handy ohne weitere Eingabe wieder an. Alternativ verschickt **„Deep-Link kopieren“** denselben Link als Text.
4. Der Token ist 30 Minuten einlösbar; unbenutzte Tokens verfallen einfach.

Daneben kann das Panel je Paar Einladungs-, Wiederherstellungs- und Ersatz-Codes neu setzen, Geräte gezielt ausloggen, Backups anstoßen und Logs einsehen — jede Aktion landet im Audit-Log. Geheimnisse erscheinen genau einmal und tauchen in keinem Log auf. Details für Betreiberinnen: [`ADMIN-PANEL.md`](ADMIN-PANEL.md).

## 6. Die fünf Tabs

**Der Look „Papier & Licht" (14.0):** Die App spielt in einem warmen Zimmer bei Nacht — Lampenlicht von zehn Uhr, feiner Tintenstaub in euren beiden Farben. Alles, was Inhalt trägt, ist Papier mit dunkler Tinte; die Leiste unten ist die echte iOS-Glas-Leiste des Systems und schrumpft beim Lesen mit. Über ihr sitzt der **Heute-Zettel**: Präsenz deines Schatzes und der Tages-Hinweis, ein Tipp führt nach Zuhause.

**Das Kino zum ersten Start (14.0):** Beim allerersten Öffnen fragt ein Lampenklick nach der Sprache (Deutsch/English), dann erzählt rund eine Minute Kino die App — echte kleine Filme, eure Tintenwahl, das Wachssiegel. Jedes Kapitel ist überspringbar; unter **Mehr → „Intro erneut ansehen"** läuft es jederzeit wieder. Bei „Bewegung reduzieren" erzählen ruhige Standbilder dieselbe Geschichte.

**Die Poststation (14.0):** Im Berührungs-Raster findest du zwei neue Schalter: **Zeitpost** gibt eine Berührung, einen Puls oder eine Notiz (bis 120 Zeichen) mit Zustellzeit auf — fünf Minuten bis sieben Tage voraus, höchstens fünf offene pro Person. Dein Schatz sieht nichts davon, bis die Sendung zugestellt wird; eine Notiz kommt als versiegelter Umschlag an, dessen Wachs erst der eigene Tipp bricht. **Verlauf** zeigt die letzten 30 Tage eurer kleinen Post. Auf eine empfangene Berührung kannst du zehn Minuten lang mit **„Zurückschicken"** genau einmal dieselbe zurücksenden — ohne Wartezeit. Neu dabei: **„Stolz auf dich"** und **„Halt durch"**.

<a id="handbook-home"></a>
### Zuhause

Partnerstatus, Berührungen, Frage des Tages, Rituale, Level und dringende Hinweise.

Die Frage des Tages und das Herz bleiben direkt erreichbar. Darunter ordnet eine lokale Prioritätslogik drei Gruppen:

1. **Rituale & Nähe** bei offenem Bedürfnis, freier Kapsel oder noch offener Tagesfrage;
2. **Spiele** bei „Du bist dran“-Partien;
3. **Momente** bei bevorstehenden Terminen und Flashbacks.

Tippt auf den Regler oben, um eine Gruppe anzuheften oder auszublenden. Diese Wahl gilt nur auf diesem Gerät; dringende Hinweise werden nie durch eine Partner-Einstellung auf dem Server verändert. Der Pfeil einer Gruppe klappt sie in höchstens einer kurzen Systemanimation auf.

Nach einem Update erscheint „Neu in dieser Version“ einmal. Ein Eintrag führt direkt zum genannten Tab. Die Versionsmarke liegt lokal und wird bei einem weiteren App-Start nicht erneut gezeigt.

**Eure Woche in Zahlen (7.0):** Unter Rituale & Nähe fasst ein Rückblick jede ISO-Woche zusammen — Nachrichten, Berührungen, Spiele, perfekte Tage, das Zitat der Woche aus eurem Fragenspiel und das Foto der Woche. Dazu gehört das Highlight-Ritual: Jede Person teilt ihren Moment der Woche, und die Wahl des Schatzes zeigt sich erst, wenn beide geteilt haben. Highlights gehen nur für die laufende und die vergangene Woche; abgeschlossene Wochen zeigen zusätzlich, ob beide den Rückblick gelesen haben. Tage folgen der Gerätezeit; ISO-Wochen und das tolerante Server-Prüffenster rechnen in UTC.

**Eigene Tagesfragen (7.0):** Über das kleine Plus an der Tagesfrage füllt ihr heimlich einen gemeinsamen Fragen-Topf. Ungefähr jeden dritten Tag stellt SoooDreamy statt einer Paket-Frage eine Frage aus dem Topf — erkennbar am Abzeichen „Eine eurer eigenen Fragen“. Wer sie geschrieben hat, wird erst nach beidseitiger Antwort verraten. Jede Person sieht nur die eigenen Topf-Fragen; frisch angelegte Fragen kommen frühestens am Folgetag dran, und einmal gestellte Fragen bleiben festgeschrieben.

**An diesem Tag (8.0):** In der Momente-Gruppe erscheint die Erinnerung von heute vor genau X Monaten oder Jahren — Fotos und Tagesfragen, die ihr BEIDE beantwortet habt. Die Auswahl ist deterministisch: Beide Handys zeigen dieselbe Erinnerung. Ein Langdruck teilt sie in den Chat. Nur der exakte Kalendertag zählt; der 31. Januar hat im Februar schlicht keine Monats-Erinnerung. Halb beantwortete Fragen bleiben privat — auch als Erinnerung. Das passende Homescreen-Widget „An diesem Tag“ richtet ihr im Widget-Studio ein.

**Unsere Geschichte (8.0):** Im Wir-Tab öffnet „Unsere Geschichte“ eure Meilenstein-Zeitreise — Kopplungstag, Jahrestag, erste Nachricht, erstes Foto, erste Tagesfrage zu zweit, Zähl-Meilensteine und Abzeichen, Monat für Monat. Ehrlich dabei: „Erste Male“ sind die ältesten noch gespeicherten Einträge. Sehr alte Nachrichten, Berührungen und Spiele rollen aus dem Server-Speicher; die Geschichte beginnt dann später, statt Daten zu erfinden.

**Denk-an-dich-Puls (9.0):** Das schwebende 💭 schickt jetzt einen Puls — ein Vibrationsmuster, das euer Schatz körperlich fühlt: drei sanfte Klopfer („Denk an dich“), eine lange Welle („Gute Nacht“), ein ruhiger Herzschlag oder eine anschwellende Umarmung (Langdruck wählt das Muster). Ihr fühlt beim Senden dasselbe Muster, das ankommt. War die App des Schatzes zu, wartet der Puls auf dem Server und vibriert beim nächsten Öffnen — ehrlich gesagt: Eine seitgeladene App kann ein geschlossenes Handy nicht vibrieren lassen, die Push-Banner-Nachricht kommt aber sofort. Wurde der Puls gefühlt, bekommt ihr eine leise Bestätigung („hat deinen Puls gefühlt“). Höchstens ein Puls alle 30 Sekunden — damit er kostbar bleibt.

**Fokus & Schlafen (9.0):** Über den kleinen Modus-Chip neben eurer Stimmung sagt ihr sanft Bescheid, wenn ihr gerade nicht antworten könnt — 🎯 Fokus oder 😴 Schlafen, mit optionaler Notiz und Auto-Ende (30 Minuten bis 8 Stunden oder „bis ich es ausschalte“). Euer Schatz sieht den Modus als ruhige Pille an eurem Avatar samt Glow — auch im Sperrbildschirm-Puls leuchtet der Status mit. Nachrichten und Pulse kommen weiterhin an; der Modus nimmt nur die Erwartung einer schnellen Antwort heraus. Der Modus endet pünktlich von selbst, ganz ohne dass jemand daran denken muss.

**Gemeinsamer Funke (12.0):** Habt ihr beide die Tagesfrage beantwortet, kann euer iPhone nach der Enthüllung eine kleine Anschlussfrage aus euren beiden Antworten bauen — gedacht als Gesprächsöffner für den Abend. Das läuft über Apple Intelligence direkt auf dem Gerät (siehe „Apple Intelligence“ weiter unten), ist freiwillig und erscheint nur, wenn ihr es in den Einstellungen erlaubt habt.

<a id="handbook-chat"></a>
### Chat

Text, Fotos, Sprachnachrichten, Briefe, Reaktionen, Sticker und Pins. Versiegelte „Öffnen wenn…“-Briefe werden erst nach eurer bewussten Aktion geöffnet.

Über den Zauberstab wählt ihr einen von sechs sparsamen Sendeeffekten oder öffnet die Sticker-Werkstatt. Kritzelstriche bestimmen dort deterministisch eine gezeichnete Form und einen optionalen Kurztext; es findet keine Foto-Freistellung und keine KI-Erkennung statt. Ein Effekt kann höchstens alle zwölf Sekunden gesendet werden. Unsichtbare Tinte wird durch bewusstes Antippen enthüllt.

**Übersetzung & Transkripte (12.0):** Führt ihr eure Beziehung in zwei Sprachen, haltet eine Nachricht **gedrückt** und wählt im Menü **„Übersetzen“** — die Übersetzung erscheint direkt unter dem Original, on-device über das Apple-Translation-Framework, nichts geht in eine Cloud. Dasselbe Menü blendet sie wieder aus oder übersetzt erneut. Sprachnachrichten bekommen über **„Transkript anzeigen“** eine Mitschrift (SpeechAnalyzer, ebenfalls on-device), die lokal zwischengespeichert wird. Beides hängt von den Sprachpaketen ab, die iOS je Sprache auf dem Gerät bereithält; fehlt eines, sagt die App das ehrlich, statt zu raten.

**Formulier-Hilfen mit Apple Intelligence (12.0):** Im Brief-Composer öffnet **„Schreibblockade?“** die Briefanfang-Werkstatt — drei vorgeschlagene Anfänge im Ton eurer Wahl (Zärtlich, Verspielt, Tief). Und **„Sag es sanft“** formuliert einen Chat-Entwurf behutsamer: Dein Original bleibt stehen, bis du die neue Fassung bewusst übernimmst. Beides läuft im Apple-Sprachmodell auf dem Gerät, ist opt-in und schickt nie etwas von allein ab.

<a id="handbook-play"></a>
### Spielen

Tägliche und asynchrone Spiele, Live-Spiele, Tagesquests, Turniere und Replays. „Du bist dran“ steht immer zuerst; darunter folgen Täglich, Asynchron, Live zusammen und Party. Serverregeln entscheiden über gültige Züge und Ergebnisse.

**Spiele-Offensive II:** Wortkette-Blitz wechselt nach dem letzten Buchstaben und akzeptiert nur Wörter aus dem gewählten deutsch/englischen Paket. Galgenraten „Unser Wort“ speichert vor der Runde nur SHA-256-Prüfsumme, Länge und Hinweis; der Reveal prüft am Ende Wort und gemeldete Positionen. Paar-Bingo erzeugt wöchentlich ein 4×4-Feld. Felder lassen sich nicht antippen: Nur echte, vom Server bereits validierte Ereignisse wie eine abgeschlossene Tagesquest oder ein geöffnetes Türchen haken die passende Mikro-Aktion ab. Eine Reihe, Spalte oder Diagonale beendet die Karte und feiert auf beiden Geräten.

Über **So spielt ihr** öffnet jedes der 26 Spiele ein fortsetzbares Intro mit drei Schritten. „Lokal üben“ zeigt einen kleinen Solo-Impuls. Diese Übung bleibt auf dem Gerät, sendet keinen Spielzug und vergibt weder XP noch Turnierpunkte. Und direkt am Spieltisch sitzt die Hilfe gleich mit: Der **?**-Knopf oben rechts öffnet dasselbe Drei-Schritte-Intro als Blatt — kein Umweg zurück in den Hub.

**Replay:** Öffnet im Spielen-Hub „Replay & Zuschauer“. Laufende Partien erscheinen mit Live-Badge; beendete Partien werden in Serverreihenfolge abgespielt. Geschwindigkeit 1×/2×/4× verändert nur die Wartezeit, nie die Zugfolge. Ein Stern markiert den berechneten Wendemoment. Alle 21 Server-Spieltypen besitzen einen expliziten Darstellungsadapter; bei einem unbekannten zukünftigen Typ wird keine erfundene Interpretation gezeigt.

**Turnier:** Die Saison verwendet den Server-Aggregatvertrag über die gesamte aufbewahrte Historie (bis zu 1.000 Sitzungen) und Wordle DE/EN. Sieg = 3 Punkte, Gleichstand = je 1; Ko-op-Abschlüsse zählen als gemeinsamer Gleichstand. Vergangene Monate stehen im Trophäenregal. Bereits vor 4.3 entfernte Partien können nicht zurückgeholt werden.

**Spieltische, Zuschauer & Couch-Modus (12.0):** Auf dem iPad (und in breiten Fenstern) werden 4 Gewinnt, Kniffel, Bingo, Montagsmaler und Schiffe versenken zu echten Spieltischen — Schiffe versenken als Duelltisch mit beiden Flotten nebeneinander. Spielt ihr auf mehreren eigenen Geräten, hält genau eines die Eingabe: Die anderen schauen zu („Nur zuschauen — dein iPhone spielt gerade“) und übernehmen mit **„Hier weiterspielen“**; versiegelte Züge bleiben dabei Commit-Reveal-fair, kein Gerät sieht Geheimnisse des anderen. Siege feiert die App mit einem eigenen Sieg-Motiv unter einem Zeremonien-Budget — groß gefeiert wird, was selten ist. This-or-That kennt zusätzlich den Couch-Modus **„An einem Handy spielen“**: geheime Wahl, Handy weiterreichen, gemeinsame Auflösung.

**Brett- & Duell-Spiele:** Sechs Klassiker fürs Duell zu zweit, alle unter „Live zusammen“: **Dame** (Schlagzwang und Sprungketten — eine begonnene Kette wird zu Ende gesprungen; wer die Grundlinie erreicht, bekommt die Krone), **Reversi** (einschließen und umdrehen; ohne legalen Zug wird gepasst), **Käsekästchen** (Kanten zeichnen; ein geschlossenes Kästchen gehört dir und schenkt einen Extra-Zug), **Gomoku** (genau fünf in einer Reihe gewinnen — sechs zählen nicht), **Mancala** (aussäen gegen den Uhrzeigersinn; endet der letzte Stein im eigenen Speicher, bist du nochmal dran, in einer leeren eigenen Mulde fängt er die Gegenmulde) und **Memory-Duo** (36 verdeckte Karten; einmal Aufgedecktes bleibt für beide sichtbar — euer gemeinsames Gedächtnis spielt mit, und die Karten kennt vor dem Aufdecken nicht einmal die App). Die Steine tragen eure Avatarfarben, wer einlädt, zieht zuerst, der Server prüft jeden Zug, und der entscheidende Zug beendet die Partie auf beiden Geräten. Alle sechs werden auf dem iPad zum Spieltisch und erscheinen in Replay, Bilanz und Saison.

<a id="handbook-us"></a>
### Wir

Galerie, Videos, Canvas, Momente, Listen, Gutscheine, Soundtrack, Vault und eure gemeinsamen Rituale.

Der vollständige Bereich umfasst Galerie/Alben/Favoriten, Video-Galerie, Kritzel-Canvas samt Export, Momente und wiederkehrende Termine, Bucket List, gemeinsame Listen, Gutscheine, Soundtrack, Tagesfragen-Tagebuch, Vault, Foto des Tages, Liebes-Statistiken, Zeitkapseln, Türchen-Kalender, Ziele, Wochenplan, Tages-Memos, Monatsmagazin, „3 gute Dinge“ und Jahresrückblick. Jede Kachel führt zu ihrem eigenen Archiv oder Editor; Löschen und Bearbeiten folgt den in der Ansicht erklärten Eigentumsregeln.

<a id="handbook-settings"></a>
### Mehr / Einstellungen

Profil, Paar, Server, Geräte, Sprache, Sound, Haptik, Saison-Theme samt Nord-/Südhalbkugel, Widgets, Live Activities, Backups und App-Sperre. Unter „Über SoooDreamy“ findet ihr Version, Build, Server-Version und „made by Sonic0810“.

**Geräte (12.0):** Im Sicherheitsbereich unter **Mehr → Sicherheit & Wiederherstellung → Geräte** verwaltet ihr eure eigenen Geräte-Plätze: „Gerät hinzufügen“ erzeugt den Einmal-Code fürs iPad oder Zweithandy, die Liste markiert „Dieses Gerät“ und meldet andere gezielt ab (Kapitel 3 erklärt den Ablauf). **Apple Intelligence (12.0):** Auf der Sicherheits-Karte schaltet ihr die Formulier-Hilfen frei — mit klarem Einwilligungs-Blatt und ehrlichem Verfügbarkeits-Status. Alles läuft nur auf dem Gerät; aus ist aus.

Unter **Euer Paar → Eure Farben** kombiniert ihr eure Profilfarben oder wählt ein Preset. Die abgeleitete Akzentfarbe muss mindestens 4,5:1 Kontrast halten; die App hellt sie nötigenfalls automatisch auf. Das Farbschema färbt Hintergründe und eigene Chatblasen und wird als „Eure Farben“ an das Widget-Studio übergeben. Euer Monogramm erscheint auf Briefen, Monatsmagazinen und Türchen-Kalendern.

Im Profil kann jede Person einen optionalen Kosenamen eintragen. Der Schatz sieht ihn in persönlichen Sätzen. Deutsch und Englisch verwenden vollständige Vorlagen mit Platzhaltern; Satzteile werden nicht grammatikgefährdend aneinandergereiht.

### SoooDreamy auf dem iPad (12.0)

Auf dem iPad bekommt jede Fläche ein eigenes Layout statt einer vergrößerten iPhone-Ansicht: Das Dashboard ordnet sich als Raster, Erinnerungen öffnen sich als Split mit Sektionen-Leiste, Briefe und Tagebuch lesen sich in ruhigen Spalten, und breite Fenster machen aus Spielen echte Spieltische. Split View, Slide Over und Stage Manager funktionieren in allen vier Ausrichtungen — wird das Fenster schmal, wechselt die App nahtlos ins vertraute iPhone-Layout, angefangene Briefe und Chat-Entwürfe bleiben dabei erhalten.

Der Apple Pencil zeichnet auf der Kritzel-Leinwand mit Druckstärke und zeigt beim Schweben eine Vorschau des Strichs. Eine angeschlossene Tastatur wechselt mit **Cmd+1 bis Cmd+5** die Tabs und sendet mit **Cmd+Return**; Bilder lassen sich per Drag & Drop direkt in Chat und Galerie ziehen. Fürs Widget-Brett gibt es XL-Größen („Tage zusammen“ zweispaltig, Foto-Widget mit Querformat-Ausschnitt). Ehrliche Grenze: Den meisten iPads fehlt die Taptic Engine — Berührungen und Pulse sind dort zu sehen, aber nicht zu fühlen.

### Bedienungshilfen

SoooDreamy verwendet semantische Systemschriften für Fließtext und wechselt enge Dashboard-Zeilen bei Accessibility-Schriftgrößen in ein vertikales Layout. VoiceOver liest Gruppenname und Anzahl offener Einträge zusammen. Mit **Ohne Farben differenzieren** ergänzen ✓/× den Online-Status. Mit **Bewegung reduzieren** werden Feiern zu einem statischen, nicht blinkenden Schimmer; Partikel-Timelines laufen dann nicht. Interaktive Hauptziele sind mindestens 44 × 44 Punkte.

Das schwebende **?** über der Tableiste öffnet die gebündelte Markdown-Hilfe direkt für Zuhause, Chat, Spielen, Wir oder Einstellungen. Datum, Uhrzeit, Monat, Zahlen, Zielwerte und Dauer richten sich nach der in SoooDreamy gewählten Sprache — auch wenn die Gerätesprache abweicht. Einzahl und Mehrzahl besitzen getrennte geprüfte Formen. Reiner Benutzertext in `Text("…")` wird durch einen Quellcode-Test blockiert; nur Markenname und feste Akronyme stehen auf der geprüften Ausnahmeliste.

### Widgets, StandBy und iOS-18-Controls

Im Widget-Studio wählt ihr pro Widget einen von drei Schnellstilen oder stellt Theme, Layout und Datenquelle selbst ein. Filmstreifen zeigen bis zu drei verschiedene Favoriten; der Passbildautomat zeichnet vier Frames. Ein kleines Uhr-Warnsymbol bedeutet, dass der letzte App-Group-Schnappschuss älter als der natürliche Takt dieses Widgets ist. Öffnet die App, um sicher neu zu synchronisieren.

Herzklopfen, Bedürfnis-Knopf, **Denk an dich** und **Date-Night starten** stehen für Kontrollzentrum, Sperrbildschirm und Action Button bereit. Fügt sie in der jeweiligen iOS-Galerie hinzu. Widgets und Controls funktionieren beim Sideload nur, wenn App und Widget-Erweiterung samt `group.app.sooodreamy.shared` gemeinsam signiert wurden.

### Aussprache, Rücksicht und 3 gute Dinge

Unter **Zuhause → Rituale & Nähe → Aussprache & Rücksicht** findet ihr drei bewusst ruhige Werkzeuge:

1. **Aussprache-Modus:** Eine Person beschreibt ihr Gefühl, die andere spiegelt zuerst das Gehörte. Danach wechseln die Rollen; am Ende formuliert jede Person einen Teil der kleinen Vereinbarung. Der Server lässt nur die aktuelle Person und Schrittart zu. Eine zehnminütige gemeinsame Pause stoppt beide Seiten bis zur Serverzeit. Das ist ein Gesprächsrahmen, keine Therapie und kein Ersatz für professionelle Hilfe oder Sicherheit.
2. **Rücksicht-Radar:** Ihr teilt nur freiwillig. Der Hinweis wird auf dem iPhone mit dem gemeinsamen Vault-Schlüssel verschlüsselt; der Server speichert Ciphertext, Ablaufzeit und die grobe Sichtbarkeitsstufe. Nur die sendende Person kann den Hinweis sofort pausieren. Es gibt absichtlich keine XP, Serie oder Bewertung. Beide Geräte müssen den Vault mit demselben gemeinsamen Schlüssel entsperrt haben, um den Text zu lesen.
3. **3 gute Dinge:** Jede Person schreibt abends genau drei kurze Lichtblicke. Die Einträge des Schatzes bleiben verborgen, bis beide geteilt haben; danach erscheinen beide Listen zusammen. Dieser Moment darf in die Monatsausgabe einfließen.

### Türchen-Kalender und Fest-Rahmen

Unter **Zuhause → Rituale & Nähe → Türchen-Kalender** bereitet eine Person bis zu 31 Türchen für den Schatz vor. Wählt Advent, Geburtstagswoche, Jahrestagswoche oder einen eigenen Countdown. Die App setzt passende zweisprachige Vorlagen für Impulse, Mini-Quests, Briefe oder Spiele ein; vor dem Versiegeln seht ihr eine Vorschau.

Der Server hält jeden Inhalt bis zum jeweiligen Datum zurück. Nur die empfangende Person kann ein fälliges Türchen öffnen. Geöffnete Kalender bleiben als gemeinsames Archiv bestehen; nur ungeöffnete Kalender kann die erstellende Person löschen. Die Serverzeit ist verbindlich, auch wenn eine Geräteuhr verstellt wird.

Unter **Mehr → Saison-Theme** wählt ihr Nord- oder Südhalbkugel. Valentinstag, Halloween, Silvester und der eingetragene Jahrestag können einen Fest-Rahmen beziehungsweise Widget-Look vorschlagen. Diese Vorschläge werden nie ungefragt angewendet. Lokale Erinnerungen funktionieren ohne Remote-Push; ein sicherer Hinweis bei geschlossener App braucht weiterhin ein Push-fähiges signiertes Profil.

Das Monatsmagazin besitzt oben rechts einen Export. Er rendert ein zweisprachig beschriftetes, persönliches Bildset mit Höhepunkten und Zahlen, das über das iOS-Teilen-Menü in Chat oder Fotos gelangt. Fotos selbst werden dabei nicht neu vom Server in die Exportkarten kopiert.

## 7. Datenschutz und Backups

- Gemeinsame Inhalte liegen auf eurem selbst gehosteten Server.
- Vault-Inhalte sind Ende-zu-Ende verschlüsselt; der Server sieht nur Ciphertext.
- Die exportierte `.sooodreamy`-Datei ist mit einer mindestens zwölf Zeichen langen Passphrase verschlüsselt.
- Die Passphrase wird nicht gespeichert. Ohne sie ist das Backup nicht wiederherstellbar.
- Ein neues Gerät koppelt sich über „Wieder verbinden“ mit dem Wiederherstellungs-Schlüssel neu — siehe Kapitel „Wieder verbinden“ und [`RECOVERY.md`](RECOVERY.md).

Unter **Mehr → iCloud & Backup** wählt ihr vier getrennte Export-Domänen: Serverprofile ohne Sitzungstokens, Sprache/Sound/Haptik auf dem Gerät, Widget-/Live-Activity-App-Group-Daten und einen leichten Paar-Schnappschuss. Die `.sooodreamy`-Datei ist immer AES-GCM-verschlüsselt; die mindestens zwölf Zeichen lange Passphrase wird nie gespeichert.

Vor der Wiederherstellung wählt ihr Serverprofile, Geräte- und App-Group-Einstellungen separat. Der Paar-Schnappschuss ist nur ein lesbarer Nachweis und wird niemals in euren Paar-Server zurückgeschrieben. Alte Schema-1-Dateien werden als diese drei lokalen Domänen plus optionalem Schnappschuss verstanden; unbekannte zukünftige Schemata werden abgelehnt. Neue Serverprofile brauchen auf einem neuen Gerät absichtlich eine neue Kopplung.

### Paar auf einen neuen Server umziehen (6.0)

1. Auf dem alten Server unter **Mehr → Server-Umzug** eine Passphrase mit mindestens zwölf Zeichen eingeben und die verschlüsselte `.sooodreamy-migration`-Datei teilen.
2. Den neuen Server in SoooDreamy hinzufügen, dort mit dem eigenen Profil ein **frisches Paar ohne Aktivitäten** erstellen und diesen Server aktiv lassen.
3. Den Assistenten erneut öffnen, Datei und Passphrase wählen, Quellversion sowie kurze SHA-256-Prüfsumme prüfen und den Import bestätigen.
4. Den angezeigten **neuen** Kopplungscode mit dem Schatz teilen. Alte Server-Tokens werden nie übernommen.

Der API-Vertrag überträgt logische JSON-Inhalte und weist manipulierte Dateien, unbekannte Schemata und nicht leere Ziele ab. Große Foto-, Video-, Sprach- und Vault-Binärdateien sind absichtlich nicht Teil der mobilen JSON-Datei: Der Server-Admin kopiert dafür den Medienordner mit einem konsistenten Dateisystem-Snapshot. Bewahrt den alten Server bis zur Inhalts- und Medienprüfung unverändert auf.

Die eingebauten stündlichen Backups enthalten standardmäßig auch Medien.
Für ein externes `npm run backup`, Migration oder Restore den Server stoppen;
die Werkzeuge verweigern per Datenordner-Lock einen Lauf neben dem Server.

## 8. Fehlerbehebung

### „Keine Verbindung“

1. Im Browser desselben Netzes `<server>/api/health` öffnen.
2. Host, Schema und Port prüfen.
3. Bei öffentlicher Erreichbarkeit HTTPS und `REQUIRE_HTTPS=1` einrichten.
4. Firewall beziehungsweise Tailscale-Regeln prüfen.
5. Serverlog auf einen Bindefehler oder falschen `DATA_DIR` prüfen.

### Widget bleibt leer

Öffnet die App einmal, prüft im Widget-Studio den App-Group-Status und signiert App plus Widget-Erweiterung erneut gemeinsam.

### Push kommt bei geschlossener App nicht

Das ist bei kostenlos signierten Builds erwartbar. Nutzt lokale Erinnerungen; vollständiger Remote-Push braucht ein Push-fähiges Apple-Profil und gültige APNs-Zugangsdaten auf dem Server.

### App startet nach sieben Tagen nicht

Die kostenlose Signatur ist wahrscheinlich abgelaufen. IPA erneut mit demselben Apple-Account signieren und installieren.

### Lade-, Offline- und Fehlerzustände

Serveransichten unterscheiden fünf Zustände: Laden, Inhalt, leer, offline und Fehler. Bereits geladene Inhalte bleiben sichtbar, auch wenn die Verbindung kurz ausfällt. „Leer“ bedeutet eine erfolgreiche Antwort ohne Einträge; „offline“ bedeutet keine Verbindung; „Fehler“ bedeutet eine fehlgeschlagene Anfrage. Bei den letzten beiden führt **Nochmal versuchen** denselben sicheren Lesevorgang erneut aus.

Die Offline-Outbox speichert Chat-Text, Reaktionen, Tagesantworten, Quest-Haken und Spielbewertungen atomar pro Serverprofil, Paar und Mitglied. Beim Wiederverbinden sendet sie FIFO mit derselben Idempotenz-ID und entfernt nur den serverbestätigten Eintrag ihres eigenen Profils. Ein App-Abbruch nach dem Einreihen verliert den Vorgang nicht; Medien werden weiterhin nicht offline eingereiht.

WebSocket-Neuverbindungen verwenden exponentielle Wartezeiten mit Zufallsstreuung. Dadurch überfluten zwei Geräte den Server nach einem Router-Neustart nicht gleichzeitig. Große Galerie-, Vault-, Widget- und Magazinbilder werden direkt auf ihr Anzeigebudget dekodiert, damit Kameraauflösung nicht unnötig im Arbeitsspeicher landet.

### App-Sperre wiederherstellen

Ein Abbruch von Face ID/Touch ID lässt die App ruhig gesperrt. Nach einer fehlgeschlagenen Erkennung könnt ihr erneut tippen und den Gerätecode verwenden. Ist Geräte-Authentifizierung nicht verfügbar, zeigt SoooDreamy einen Link in die Systemeinstellungen. Die App umgeht die Sperre nicht und kann keinen Gerätecode zurücksetzen.

## 9. FAQ

**Brauchen wir zwei Server?**  
Nein. Ein Server verwaltet das gemeinsame Paar; beide Apps verbinden sich damit.

**Kann der Server unsere Vault-Inhalte lesen?**  
Nein. Er speichert Ciphertext und öffentliche Schlüsselableitungsparameter, nicht den Geräteschlüssel.

**Funktioniert SoooDreamy ohne Internet?**  
Gecachte Inhalte und vorbereitete Chat-Nachrichten bleiben verfügbar. Synchronisation mit dem Partner braucht eine Verbindung zum Paar-Server.

**Ist das IPA im App Store?**  
Nein. Das veröffentlichte Artefakt ist unsigniert und für bewusstes Sideloading gedacht.

## 10. Release-Nachweis

Das rollende GitHub-Release `sooodreamy-latest` ist die Quelle für aktuelle
16.0.0-IPAs. `versions/` ist ein historisches, reproduzierbares Archiv der
Releases 4.1 bis 6.0; für 7.0 bis 16.0 wird dort kein vollständiger
versionsbezogener IPA-Nachweis behauptet.

Seit 5.4 gehört ein vollständiges Zustandsinventar zum Release-Nachweis: Laden, leer, Inhalt, offline und Fehler werden für alle zentralen Oberflächen geprüft. Ein leerer Bildschirm darf keinen Netzwerkfehler verschweigen; vorhandene Daten bleiben bei Offline- und Fehlerhinweisen lesbar, und Wiederholen bleibt mit einem Tipp erreichbar.

### Dev Cockpit (Entwicklung)

Startet den Server nur für lokale QA mit `SOOODREAMY_DEV_COCKPIT=1 npm start` und öffnet `/dev/cockpit`. Die zwei Spalten erstellen ein Paar, senden Berührungen, beantworten die Tagesfrage und führen einen Spielzug aus. Ohne das Flag liefert die Route absichtlich 404. Das Cockpit speichert keine Zugangsdaten außerhalb der geöffneten Seite und ersetzt keine Geräteprüfung.

---

SoooDreamy — made by Sonic0810
