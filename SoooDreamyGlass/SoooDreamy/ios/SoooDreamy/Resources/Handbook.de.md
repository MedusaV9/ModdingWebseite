<!-- anchor:setup -->
# Einrichtung

Startet den Node-20-Server, öffnet `/api/health` und verbindet beide iPhones per Paar-Code oder QR. Beim Koppeln bekommt jede Person einen Wiederherstellungs-Schlüssel (iCloud-Schlüsselbund + einmalige Anzeige). Öffentliche Adressen brauchen HTTPS/WSS; privates HTTP ist nur mit `ALLOW_HTTP_PRIVATE_LAN=1` vorgesehen.

**Wieder verbinden:** Nach Handywechsel oder Neuinstallation holt der dritte Tab „Wieder verbinden“ euren Platz zurück — Verlauf, Statistiken und Abzeichen bleiben. Liegt der Schlüssel noch im iCloud-Schlüsselbund, reicht EIN Tipp. Sonst „QR-Code scannen“: den Login-QR erzeugt die Server-Betreiberin im Admin-Panel, oder dein Schatz zeigt im Amt unter Sicherung & Schlüssel → „Schatz ausgesperrt?“ den Ersatz-Code-QR. Zur Not „Code eintippen“: Paar-Code plus Schlüssel oder Ersatz-Code (einmalig, 15 Minuten gültig). Abgelaufene Sitzungen heilen sich still von selbst.

**Server & Admin-Panel:** Das Admin-Panel läuft im Serverprozess mit (`/admin`); das Passwort erscheint bei jedem Serverstart frisch im Konsolen-Banner. Für euch als Paar zählt der Tab „Login-QR“: ein Scan mit der App oder der iOS-Kamera, und das Handy hängt wieder an seinem Platz — 30 Minuten einlösbar, ohne weitere Eingabe.

Das unsignierte IPA wird mit AltStore, SideStore oder Sideloadly signiert; ESign/KSign signieren ohne Rechner direkt auf dem iPhone — dann beide Bundle-IDs (App + Widget-Erweiterung) mitsignieren, und ohne App-Groups-fähiges Zertifikat die Lite-IPA nehmen (ausführlich: `docs/SIDELOAD-ESIGN.md`). Kostenlose Apple-IDs laufen üblicherweise nach sieben Tagen ab.

<!-- anchor:home -->
# Postfach

Der Partnerstatus, Herzklopfen, Berührungen, Tagesfrage und Streak stehen oben; das Dienstlicht im Kopf spiegelt die Energie-Ampel von euch beiden. Darunter sortiert das Postfach Rituale, offene Spielzüge und Momente in Zustellrunden — neue Runden treffen leise gestaffelt ein (abschaltbar im Amt unter „Zustellrunden inszenieren“). Gruppen lassen sich lokal anheften, einklappen oder ausblenden; dringende Partnerzustände bleiben sichtbar.

**Rituale:** Check-in, Umarmung, Energie-Ampel, Bedürfnis-Knopf, Tages-Memo, Aussprache, Rücksicht-Radar, 3 gute Dinge und Türchen-Kalender. Kalenderinhalte bleiben bis zur Serverzeit gesperrt und sind nur für den Empfänger; geöffnete Kalender bleiben im Archiv. Rücksicht-Hinweise sind Vault-verschlüsselt und ohne XP. Aussprache ist ein Gesprächswerkzeug, keine Therapie.

**Wenn etwas fehlt:** Verbindung prüfen, Gruppe aufklappen und „Nochmal versuchen“ wählen. Offline bleiben geladene Inhalte sichtbar.

<!-- anchor:chat -->
# Schreibstube

Text, Fotos, Sprachnachrichten, Reaktionen, Pins, Liebesbriefe und „Öffnen wenn…“-Siegel. Die Siegelpresse am Pult bündelt die drei Absende-Zeremonien: Zeitpost, Zeitkapsel und Türchen-Kalender. Die Schreibstube lädt ältere Seiten nach und hält neue Nachrichten am stabilen Anker. Vorbereitete Textnachrichten warten offline pro Serverprofil in der Outbox.

**Privatsphäre:** Vault-Inhalte gehören nicht in normale Chat-Nachrichten. Versiegelte Briefe sind ein Freigabe-Ritual, keine Ende-zu-Ende-Verschlüsselung.

**Wenn Senden hängt:** Serveradresse prüfen und warten, bis die Outbox bestätigt ist. Medien werden nicht offline eingereiht.

<!-- anchor:play -->
# Spieltisch

Der Kartenschrank ordnet den Katalog in drei Fächer (tägliche, asynchrone und Live-/Partyspiele); das Spielbuch führt Turnier, Siegerliste und Wiederholungen als Kapitelzeilen. „Du bist dran“ bleibt oben. Turniere nutzen die vollständige aufbewahrte Serverhistorie plus Wordle. Replay-Adapter zeigen den echten Zustand; unbekannte zukünftige Typen werden nicht erfunden.

Enthalten sind unter anderem Wordle/Duell, Quiz, Entweder-oder, Würdest du eher, Wahrheit oder Pflicht, 36 Fragen, Emoji-Rätsel, Battleship, Kniffel, Pictionary, Vier gewinnt, Foto-Memory, Stadt-Land-Fluss und Zwei Wahrheiten.

**Wenn ein Zug abgelehnt wird:** Der Server entscheidet über Person, Phase und Reihenfolge. Ansicht neu laden; nie denselben Zug blind mehrfach senden.

<!-- anchor:us -->
# Archiv

Die Schrankfront ordnet alles in sechs Fächer: **Alben** (Galerie, Videos, Foto des Tages, Momente, Geschichte, Jahresrückblick), **Planfach** (gemeinsame Listen, Bucket List, Wochenplan), **Wertfach** (Gutscheine, Ziele), **Chronik** (Tagebuch, Jahr in Zahlen, Soundtrack, Canvas, Monatsmagazin, Wochenrückblick, Bedürfnis-Verlauf), **Lagerfach** (Zeitkapseln, Türchen-Kalender) und **Tresorfach** (Vault). Ein Fach öffnet an Ort und Stelle — die Zeilen gleiten heraus. Die Suche über der Schrankfront filtert alle Bereiche nach Titel; das zuletzt offene Fach merkt sich der Schrank.

Das Monatsmagazin kann Höhepunkte und Zahlen als Bildset teilen. Backups exportieren lokale Profile/Einstellungen verschlüsselt; Paarinhalte bleiben auf dem selbst gehosteten Server. Zeitkapseln öffnen serverseitig erst zum Freigabezeitpunkt.

**Wenn Medien fehlen:** Server-Medienordner, Berechtigung und Speicher prüfen. Vault-Daten benötigen denselben PIN/Schlüssel auf beiden Geräten.

<!-- anchor:settings -->
# Amt & Einstellungen

Das Amt arbeitet in sechs stillen Sektionen: **Unser Amt** (Profil, Paar, Pairing-Code), **Zustelldienst** (Benachrichtigungen, „Zustellrunden inszenieren“, eigene Tagesfragen), **Zweigstellen & Bezirke** (Serverwechsel, Geräte, Umzug), **Werkstatt** (Sprache, Sounds, Haptik, Saison-Theme mit Nord-/Südhalbkugel, Widget-Studio, Live Activities, Icons, Gestaltung), **Sicherung & Schlüssel** (App-Sperre, Wiederherstellungs-Schlüssel — ansehen, kopieren, rotieren —, Ersatz-Code für den ausgesperrten Schatz, iCloud/Backup) und **Betriebsbuch** (Verbindungs-Doktor, Handbuch, Über/Credits, Amtsgründung noch einmal ansehen).

Widgets brauchen beim Sideload eine gemeinsam signierte App Group. Remote-Push und iCloud benötigen passende Apple-Entitlements; lokale Erinnerungen sind davon unabhängig. Kostenlose Apple-IDs laufen üblicherweise nach sieben Tagen ab.

**Hilfe:** Bei Verbindungsfehlern `/api/health`, HTTPS/Tailscale, Port und Firewall prüfen. Ein neues Gerät verbindet sich per „Wieder verbinden“ und Schlüssel neu — die Geschichte bleibt. made by Sonic0810.
