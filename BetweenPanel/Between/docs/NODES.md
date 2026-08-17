# Multi-Node (Remote-Maschinen)

Between kann Gameserver auf **mehreren Maschinen** verwalten: Ein Panel (die Web-Oberfläche) steuert beliebig viele **Nodes** (Agenten auf anderen Servern/VPS). Ohne Nodes verhält sich Between exakt wie ein Einzel-Setup — das Feature ist vollständig optional.

## Konzept

- **Panel** = die Maschine mit Web-UI, Benutzern, Rechten, Audit-Log. Alle Berechtigungen werden panel-seitig geprüft.
- **Node** = derselbe Between-Code im Agent-Modus (`BETWEEN_MODE=node`): kein Web-UI, keine Benutzer — nur die Server-/Datei-/Backup-API, geschützt durch ein einzelnes Bearer-Token.
- Das Panel verbindet sich zum Node (Pull-Modell): HTTP + eine gemultiplexte WebSocket für Live-Konsole/Stats. Konsole, Dateien, Backups und Power-Aktionen laufen transparent durch.

## Node aufsetzen

Auf der Zweitmaschine (gleiche Codebasis, z. B. per Git-Checkout + `npm install`):

```bash
BETWEEN_MODE=node \
BETWEEN_NODE_TOKEN=<mindestens-16-zeichen-geheim> \
BETWEEN_NODE_NAME="Mein-Node-1" \
BETWEEN_PORT=8485 \
BETWEEN_DATA=/opt/between-node-data \
npm start
```

Dann im Panel: **Nodes → Add node** — Name, Basis-URL (`http://<ip>:8485`) und dasselbe Token eintragen. Das Panel testet die Verbindung automatisch und zeigt Identität + Latenz. Der „Add node"-Dialog generiert dir auf Wunsch ein sicheres Token und den fertigen Startbefehl zum Kopieren.

## Sicherheitsmodell

- Das Token ist **admin-äquivalent auf dem Node** — behandle es wie ein Passwort. Es wird nie in API-Antworten oder Logs ausgegeben und ausschließlich als `Authorization: Bearer`-Header übertragen (nie in URLs).
- Vergleich in konstanter Zeit (sha256 + `timingSafeEqual`), Mindestlänge 16 Zeichen (Agent verweigert sonst den Start).
- Benutzer-/Subuser-Rechte prüft **immer das Panel** (inklusive Re-Check pro WebSocket-Nachricht); der Node vertraut nur dem Panel-Token.
- Die Basis-URL wird nur auf Form geprüft (http/https, keine Credentials/Pfade). Private/LAN-Adressen sind **bewusst erlaubt** — dafür ist Self-Hosting da. Für WAN-Verbindungen: VPN/WireGuard oder Reverse-Proxy mit TLS davorschalten.

## Was funktioniert (v1)

| Bereich | Remote-Server |
|---|---|
| Erstellen (Blueprint wird mitgeschickt, auch Custom) | ✔ |
| Start/Stop/Restart/Kill, Konsole live, Befehle | ✔ |
| Stats + Verlauf (Sparklines), Spielerzahlen | ✔ |
| Dateien: Liste/Lesen/Schreiben/Upload/Download/Löschen | ✔ (gestreamt, 4-GiB-Cap) |
| Backups: Liste/Erstellen/Restore/Löschen | ✔ |
| Subuser-Rechte, Audit, Dashboard/Übersicht | ✔ |
| Node offline | Panel degradiert sauber (`node-offline`-Status, klare Fehlermeldungen) |

**Noch nicht remote (kommt in einer Folgerunde):** Settings-Änderungen, Clone, Config-Editor, Reinstall, Steam-Update, Docker-Pull, Schedules, Mods, Backup-Lock/-Download, Datei-Rename/-Archiv. Die UI blendet diese Aktionen für Remote-Server aus bzw. zeigt einen Hinweis.

**Steam-Login ist pro Maschine:** Der Steam-Account-Login in den Panel-Einstellungen (für Spiele, die nicht anonym per SteamCMD ladbar sind) gilt nur für die Panel-Maschine — SteamCMD cacht die Sitzung in seinem lokalen Datenverzeichnis. Installationen auf Remote-Nodes, die einen Login bräuchten, schlagen mit einer klaren Fehlermeldung fehl (v1-Limitierung).

## Betrieb & Fehlersuche

- Health-Poll alle 10 s (`BETWEEN_NODE_POLL_MS` überschreibbar); Ausfälle erscheinen binnen ~15 s als „Offline" auf der Nodes-Seite.
- Node down? Gemirrorte Server zeigen den Status **Node offline**; Aktionen liefern eine klare 502-Meldung. Nach Agent-Neustart übernimmt das Panel automatisch wieder (Reconcile).
- Node dauerhaft weg? **Remove node** im Panel entfernt die Spiegel-Einträge (der Agent selbst bleibt unberührt).
- Ein Node verwaltet seine Server lokal in seinem eigenen `BETWEEN_DATA`-Verzeichnis — Panel-Neustarts beeinflussen laufende Remote-Server nicht.
