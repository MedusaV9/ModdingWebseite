# IDEEN-IMPROVER C — Backend & Multiplayer, Live Activities, IGohbie-Social-Apps

Scope: USER-WISHES §C komplett + Live Activities (§C/§E Taxi) + Social-Apps aus §E
(GoobyPal, InstantGooby, Freunde-Status, Snap-A-Gooby-Multiplayer-Aspekt).
Nur DESIGN — keine Implementierung. Referenz-Spielstand: `/workspace/GOOBY`
(`src/systems/economy.js` = einziger Münz-Pfad, `src/systems/profileStats.js` =
Spielzeit/Coins-Lifetime-Slice, `src/systems/codesEngine.js` = Offline-Code-Muster).

---

## 1. Protokoll-Wahl: WebSocket, nicht ENet

**Entscheidung: `WebSocketPeer` (LOW-level) im Godot-Client, `ws`-Modul im Node-Server.**

| Kriterium | WebSocket | ENet |
|---|---|---|
| Node.js-Serverseite | `ws` ist battle-tested, pure JS | kein brauchbares Node-ENet; müsste native binding sein |
| AMP „Node.js App Runner“ | 1 Prozess, 1 TCP-Port — genau das Modell | UDP-Port extra, AMP-Portmapping-Frickelei |
| iOS/Firewalls/Reverse-Proxy | läuft überall, TLS via `wss://` trivial | UDP oft geblockt |
| Latenzbedarf | unsere Features sind Turn-/Relay-basiert (s. §3) — TCP reicht | nur nötig für twitch-Netcode, den wir NICHT bauen |

**Warum `WebSocketPeer` und nicht `WebSocketMultiplayerPeer`:** Das High-Level-API
(`WebSocketMultiplayerPeer` + RPCs) spricht Godots internes SceneMultiplayer-Binärprotokoll —
das müsste Node nachimplementieren. Wir wollen ein **eigenes, versioniertes JSON-Protokoll**,
das Node nativ versteht und das Webpanel mitlesen kann. Also: `WebSocketPeer`, Text-Frames,
JSON. (Binär/MessagePack ist bei unserer Nachrichtengröße Overkill — Foto-Uploads laufen
über REST, nicht über den Socket.)

### 1.1 Envelope (alle Messages, beide Richtungen)

```json
{ "v": 1, "t": "MESSAGE_TYPE", "seq": 42, "ts": 1753380000000, "d": { } }
```

- `v` — Protokollversion (int). Server antwortet auf unbekanntes `v` mit
  `ERROR {code:"PROTO_VERSION", min:1, max:1}` und schließt. Client zeigt
  „Server-Update nötig“ / „App-Update nötig“ (passt zum §B-Updater: Server-IP/Port
  kommen per Remote-Config, Protokollversion wird dort gleich mitgeliefert).
- `t` — UPPER_SNAKE Message-Typ.
- `seq` — pro Verbindung monoton; Antworten tragen `re: seq` (Request/Response-Korrelation).
- `d` — Payload. Unbekannte Felder werden ignoriert (additive Evolution ohne v-Bump).

### 1.2 Handshake & Heartbeat

```json
// Client → Server, erste Message nach Connect (sonst Disconnect nach 5 s)
{ "v":1, "t":"HELLO", "seq":1, "d":{
  "deviceId":   "gd-7f3a…",            // UUID, client-generiert beim ersten Start
  "deviceSecret":"…32-byte-hex…",      // Token, s. §7
  "friendCode": "GOOBY-4K7Q",          // null beim allerersten HELLO → Server vergibt
  "playerName": "Sonic0810",           // Onboarding-Name (Spitzname, kein PII-Zwang)
  "goobyNick":  "Herr Flauschig",      // Gooby-Spitzname (für Presence-Texte)
  "appVersion": "5.0.0", "contentVersion": "cp-2026-07-1"
}}

// Server → Client
{ "v":1, "t":"WELCOME", "re":1, "d":{
  "friendCode":"GOOBY-4K7Q", "serverTime":1753380000000,
  "heartbeatSec":20, "features":["visits","boardgames","mail","events"],
  "pendingEvents":[…], "mailCount":3, "friendRequests":[…]
}}

// Heartbeat: Client sendet PING alle heartbeatSec, Server antwortet PONG.
{ "t":"PING", "d":{} }   →   { "t":"PONG", "d":{"serverTime":…} }
// Server droppt nach 3 verpassten Intervallen (60 s); Presence → offline.
```

### 1.3 Rooms

Ein Room ist ein server-seitiger Relay-Kanal: `join`/`leave`/`msg`-Semantik, Server
broadcastet an alle Mitglieder außer Absender (oder inkl., je nach Typ). Room-IDs:

- `visit:<hostFriendCode>` — Besuch (max 2 Mitglieder: Host + Gast)
- `board:<uuid>` — Brettspiel-Session (2 Spieler + theoretisch Zuschauer später)
- `drive:<uuid>` — Coop-Fahrt (2)
- `mg:<uuid>` — Koop-/PvP-Minigame (2)

```json
{ "t":"ROOM_JOIN",  "d":{"room":"visit:GOOBY-4K7Q"} }
{ "t":"ROOM_LEAVE", "d":{"room":"…"} }
{ "t":"ROOM_MSG",   "d":{"room":"…", "kind":"POS", "body":{…}} }   // Relay-Nutzlast
{ "t":"ROOM_PEER_JOINED" / "ROOM_PEER_LEFT", "d":{"room":"…","friendCode":"…","goobyNick":"…"} }
```

`ROOM_MSG.kind` ist der Feature-Multiplexer (POS, EMOTE, MOVE, RADIO, …, s. §3).
Server validiert nur: Mitgliedschaft, Payload-Größe (≤ 8 KB), Rate (≤ 30 msg/s/Verbindung).
Feature-Logik, die Geld/Items bewegt, läuft NIE über ROOM_MSG, sondern über eigene
validierte Typen (GoobyPal, Mail).

---

## 2. Node.js-Server: EIN Prozess, EIN Port (AMP „Node.js App Runner“)

### 2.1 Architektur

```
node server.js
 └─ http.createServer(expressApp)      ← EIN Listener auf process.env.PORT (default 8244)
     ├─ express: /panel/* (Webpanel, Session-Cookie)
     ├─ express: /api/*   (REST: Auth, Mail-Upload, Codes-Redeem-online, Analytics-Flush)
     ├─ express: /health  ({ok:true, uptime, clients})
     └─ ws.WebSocketServer({ noServer:true }) + server.on('upgrade') für Pfad /ws
```

Kein Cluster, kein Worker, kein Docker, kein zweiter Port. AMP-Template startet
`node server.js`, fertig. Graceful Shutdown auf SIGTERM (AMP-Stop): Snapshot flushen,
Sockets mit `GOING_DOWN` schließen (Client zeigt „Server macht Pause“).

### 2.2 Storage: JSON-Files (empfohlen) vs better-sqlite3 — Abwägung

| | better-sqlite3 | Node-builtin `node:sqlite` | JSON-File-Storage |
|---|---|---|---|
| Native Dependency | **JA** (prebuilds meist ok, aber: AMP-Container ohne Build-Tools + exotische Node-Version ⇒ `npm install` kann hart scheitern) | nein (builtin) | nein |
| Node-Versions-Kopplung | ABI-gebunden — AMP-Node-Update kann Neubau erzwingen | braucht Node ≥ 23.4 (unflagged) — AMP-Template-Node nicht garantiert | jede Node ≥ 18 |
| Query-Power | SQL | SQL | in-Memory-Maps, selbst joinen |
| Unsere Datenmenge | Freundeskreis-Server: Dutzende Spieler, wenige MB | dito | dito — **passt locker in RAM** |
| Backup/Debug durch den User | Binärfile | Binärfile | `data/` per Hand lesbar, AMP-File-Manager-freundlich |

**Empfehlung: reines JSON-File-Storage.** Begründung: Das robusteste auf AMP ist das,
was bei `npm install` **nicht scheitern kann** und bei jedem Node läuft. Unsere Skala
(privater Server für einen Freundeskreis) braucht keine SQL-Engine. Muster:

- **State-Collections** (devices, friends, codes, events, houses-index): komplette
  In-Memory-Maps, Write-behind-Snapshot alle 10 s wenn dirty — atomar via
  `write tmp → fsync → rename` (dasselbe Atomik-Muster wie der Godot-Client für `user://`).
- **Append-Logs** (Analytics-Sessions, GoobyPal-Transfers, Audit): JSONL, eine Zeile
  pro Event, monatlich rotiert (`sessions-2026-07.jsonl`). Nie in RAM gehalten außer
  Aggregaten.
- **Blobs** (Briefe-Fotos, Haus-Snapshots): einzelne Dateien unter `data/blobs/`,
  Index in der Collection.
- Storage hinter einem Mini-Interface (`store.js`: `get/put/all/append`), damit ein
  späterer `node:sqlite`-Swap eine 1-Datei-Änderung ist.

### 2.3 Konfiguration

Priorität: ENV > `config.json` > Defaults. AMP setzt ENV am bequemsten.

```
PORT=8244                      GOOBY_ADMIN_PASSWORD=…   (Pflicht! ohne → Panel deaktiviert, lautes Log-Warning)
GOOBY_DATA_DIR=./data          GOOBY_MAX_PHOTO_KB=512
GOOBY_PAL_DAILY_LIMIT=250      GOOBY_TZ=Europe/Berlin   (Tagesgrenze für Limits)
GOOBY_PUBLIC_URL=…             (optional, fürs Panel-Log)
```

### 2.4 Server-Dateistruktur (`GOOBY-SERVER/`)

```
GOOBY-SERVER/
├─ server.js                 # Entry: config laden, http+express+ws verdrahten, SIGTERM
├─ package.json              # deps: express, ws, cookie-session — SONST NICHTS natives
├─ config.example.json
├─ README.md                 # AMP-Setup-Anleitung (Node.js App Runner, ENV, Port)
├─ src/
│  ├─ config.js              # ENV/config.json-Merge + Validierung
│  ├─ store.js               # JSON-Storage-Engine (Snapshots, JSONL, Blobs, atomare Writes)
│  ├─ auth.js                # deviceSecret-Hash-Check, FriendCode-Vergabe, Panel-Session
│  ├─ protocol.js            # Envelope-Parse/Build, v-Check, Typ-Registry, Schemas
│  ├─ hub.js                 # Verbindungs-Registry, HELLO/WELCOME, Heartbeat, Presence
│  ├─ rooms.js               # Room-Join/Leave/Relay + Größen-/Rate-Limits
│  ├─ friends.js             # Requests, Accept/Decline, Liste, Coins-Cache
│  ├─ pal.js                 # GoobyPal-Transfers inkl. 250/Tag-Ledger (server-autoritativ)
│  ├─ visits.js              # Haus-Snapshot-Verwaltung, Besuchs-Lifecycle, Bau-Warnung
│  ├─ boardgames.js          # Schach + Schiffe versenken: Turn-Relay + Turn-Ownership
│  ├─ mail.js                # Briefe/Item-Geschenke, Foto-Upload (REST), Quota, Pruning
│  ├─ analytics.js           # Session-Ping-Ingest (REST-Batch), Aggregation fürs Panel
│  ├─ codes.js               # Online-Codes CRUD + Redeem-Validierung
│  ├─ events.js              # Admin-Events: WS-Push + Pull-Queue (Boot-Abholung)
│  └─ ratelimit.js           # Token-Bucket per Device + per IP
├─ panel/                    # Webpanel (server-gerendert + vanilla JS, kein Build-Step!)
│  ├─ views/ *.html          # Templates (simples Mustache-artiges Inline-Templating)
│  └─ static/ panel.css, panel.js, chart.js (vendored, ein File)
├─ test/                     # node:test, headless (Muster wie GOOBY/test/*)
│  ├─ pal.test.js, codes.test.js, boardgames.test.js, store.test.js, protocol.test.js
└─ data/                     # Laufzeit (gitignored; AMP persistiert das Verzeichnis)
   ├─ devices.json  friends.json  codes.json  events.json  houses.json
   ├─ log/sessions-YYYY-MM.jsonl  log/transfers-YYYY-MM.jsonl  log/audit.jsonl
   └─ blobs/ (Fotos, Haus-Snapshots)
```

### 2.5 „DB“-Schema (JSON-Collections)

```jsonc
// devices.json — Account = anonymes Gerät
{ "gd-7f3a…": {
    "secretHash":"sha256:…", "friendCode":"GOOBY-4K7Q",
    "playerName":"Sonic0810", "goobyNick":"Herr Flauschig",
    "createdAt":…, "lastSeenAt":…, "coins":1234, "coinsUpdatedAt":…,   // Anzeige-Cache!
    "banned":false } }

// friends.json
{ "edges":   [ {"a":"GOOBY-4K7Q","b":"GOOBY-9ZML","since":…} ],
  "requests":[ {"from":"…","to":"…","at":…} ] }

// log/transfers-YYYY-MM.jsonl — GoobyPal (append-only = auditierbar)
{"at":…,"from":"GOOBY-4K7Q","to":"GOOBY-9ZML","amount":50,"dayKey":"2026-07-24"}

// codes.json — Online-Codes (Panel-CRUD)
{ "SOMMER26": { "reward":{"coins":500,"sticker":"sonne"}, "maxUses":100, "uses":17,
                "perDevice":1, "validFrom":…, "validUntil":…, "createdBy":"admin" } }

// events.json — Admin-Events (Push + Pull)
{ "evt-…": { "type":"WEATHER_RAIN", "params":{"durationMin":60}, "at":…,
             "target":"all"|"GOOBY-XXXX", "expiresAt":…, "deliveredTo":["gd-…"] } }

// houses.json — Index; Layout selbst als Blob
{ "GOOBY-4K7Q": { "blob":"blobs/house-gd7f3a-17.json.gz", "rev":17,
                  "sizeBytes":48213, "uploadedAt":… } }

// log/sessions-YYYY-MM.jsonl — Analytics (WICHTIGSTES Analytic: Spielzeit)
{"at":…,"deviceId":"gd-…","kind":"session","startedAt":…,"endedAt":…,"minutes":34.5,
 "appVersion":"5.0.0","offlineBuffered":true}

// mail (Index in mail.json, Bodies/Fotos als Blob)
{ "mail-…": { "from":"GOOBY-4K7Q","to":"GOOBY-9ZML","kind":"letter"|"gift",
   "text":"…","photoBlob":"blobs/…jpg"|null,"item":{"id":"toaster","qty":1}|null,
   "sentAt":…,"readAt":null } }
```

---

## 3. Features — Message-Schemas & Regeln

### 3.1 Accounts & FriendCode

- Kein Login, kein PII: `deviceId` (Client-UUID) + `deviceSecret` (Client-Random, s. §7).
- Server vergibt beim ersten HELLO den **FriendCode `GOOBY-XXXX`** (Base32 ohne
  I/O/0/1, 4 Zeichen ⇒ ~1 M Codes — für Freundeskreis-Skala reichlich; Kollision → neu würfeln).
  FriendCode ist die öffentliche Identität, `deviceId` bleibt privat.
- `playerName`/`goobyNick` sind frei änderbar (`PROFILE_UPDATE`), Server längen-limitiert
  (≤ 24 Zeichen) und filtert Steuerzeichen.

### 3.2 Freunde & Presence & Coins-Anzeige

```json
{ "t":"FRIEND_REQUEST",  "d":{"target":"GOOBY-9ZML"} }          // oder {"targetName":"Sonic0810"} — Server löst eindeutigen Namen auf, sonst ERROR AMBIGUOUS
{ "t":"FRIEND_ACCEPT" / "FRIEND_DECLINE" / "FRIEND_REMOVE", "d":{"target":"…"} }
{ "t":"FRIENDS_LIST",    "d":{} }   // → FRIENDS_STATE
{ "t":"FRIENDS_STATE",   "d":{"friends":[
   {"friendCode":"GOOBY-9ZML","playerName":"Lena","goobyNick":"Knöpfchen",
    "online":true,"activity":{"kind":"park","label":"ist mit Knöpfchen im Park"},
    "coins":842,"coinsUpdatedAt":…} ], "requests":[…]} }

// Presence: Client meldet Aktivitätswechsel (Raum/Ort betreten), gedrosselt ≥ 30 s Abstand
{ "t":"PRESENCE_SET", "d":{"kind":"park"|"home"|"ikea"|"minigame:gvz"|…} }
// Server pusht Änderungen an Online-Freunde:
{ "t":"FRIEND_PRESENCE", "d":{"friendCode":"…","online":true,"activity":{…}} }

// Coins-Anzeige („updaten sich ab und zu“): Client pusht Balance im SYNC —
// alle 5 min UND bei Änderung > 100 Coins (debounced 60 s). Server cached nur (Anzeige!),
// die ECHTE Balance bleibt client-autoritativ offline (economy.js-Nachfolger in Godot).
{ "t":"SYNC", "d":{"coins":1234} }
```

Presence-Label wird SERVER-seitig aus `goobyNick` + `kind` gebaut (deutsche Templates
im Server ⇒ per Server-Update änderbar, passt zu §B-Modularität).

### 3.3 GoobyPal (server-validiert, 250/Tag)

```json
{ "t":"PAL_SEND", "seq":9, "d":{"to":"GOOBY-9ZML","amount":50} }
{ "t":"PAL_RESULT", "re":9, "d":{"ok":true,"sentToday":120,"dailyLimit":250} }
// oder {"ok":false,"code":"DAILY_LIMIT"|"NOT_FRIENDS"|"OFFLINE_TARGET_OK"} — Empfänger
// offline ist OK: Gutschrift landet als Mail-artiges "PAL_RECEIVED" in der Pull-Queue.
{ "t":"PAL_RECEIVED", "d":{"from":"GOOBY-4K7Q","amount":50,"at":…} }
```

Regeln: nur zwischen Freunden; `amount` int 1..250; Tages-Ledger server-seitig pro
**Absender** und `dayKey` in `GOOBY_TZ`; Client zieht Coins erst bei `ok:true` ab
(Server ist hier autoritativ — einziges Feature, das die Offline-Ökonomie berührt,
darum bewusst NUR online möglich; UI graut den Senden-Knopf offline aus).

### 3.4 Besuche (Haus-Snapshot + Live-Relay)

Ablauf („Reisen zu Freund“):

1. Gast: `VISIT_REQUEST {target}` → Host (online) bekommt `VISIT_INCOMING`, bestätigt
   mit `VISIT_ACCEPT` (oder Auto-Accept-Einstellung).
2. Host lädt Haus-Snapshot hoch, falls `rev` veraltet: `PUT /api/house` (REST, gzip-JSON
   des Haus-Layouts, ≤ 256 KB). Server bumpt `rev`.
3. Beide joinen `visit:<hostCode>`. Gast: `GET /api/house/<hostCode>` → rendert Layout lokal.
4. Live: beide senden `ROOM_MSG kind:POS` mit 5 Hz `{room, pos:[x,y], anim:"walk", roomId:"kitchen"}`
   — Godot interpoliert. Unterschiedliche Räume gleichzeitig = einfach andere `roomId`,
   der jeweils andere wird als Tür-Icon/„ist in der Küche“ angezeigt statt gerendert.
5. **Bauen während Besuch:** Host sendet `ROOM_MSG kind:BUILD_START` → beide Clients
   zeigen die Warnung („kann zu Problemen führen“); Möbeländerungen kommen als
   `kind:BUILD_DELTA {op:"place"|"remove", item, cell}` — Gast wendet Best-Effort an,
   bei Konflikt (Gast steht auf der Zelle) teleportiert er sich zur Tür. Beim
   `VISIT_END` lädt der Host den finalen Snapshot als neue `rev` hoch.
6. Abends/Energie-0-Regel („Besucher schläft auf der Couch“) ist CLIENT-Logik beim Gast;
   Server relayt nur `kind:EMOTE {id:"sleep_couch"}`.

### 3.5 Brettspiele (Schach, Schiffe versenken)

Server = **Turn-Relay + Turn-Ownership**, KEINE Spielregeln im Server (M2 simpel):

```json
{ "t":"BOARD_INVITE", "d":{"target":"…","game":"chess"|"battleship"} }
{ "t":"BOARD_START",  "d":{"room":"board:…","game":"chess","white":"GOOBY-4K7Q","seed":123} }
{ "t":"ROOM_MSG","d":{"room":"board:…","kind":"MOVE","body":{"n":14,"move":"e2e4"}}}          // Schach: UCI-Strings
{ "t":"ROOM_MSG","d":{"room":"board:…","kind":"SHOT","body":{"n":7,"cell":"B4","hit":true}}}  // Schiffe: Zelle + Ergebnis vom Beschossenen
{ "t":"ROOM_MSG","d":{"room":"board:…","kind":"EMOTE","body":{"id":"dance"|"angry"|…}}}
{ "t":"ROOM_MSG","d":{"room":"board:…","kind":"TOMATO","body":{}}}                             // Server erzwingt: max 1×/Runde (zählt MOVE/SHOT-Paare)
```

- Beide Clients validieren Züge (Schach-Legalität client-seitig, deterministisch);
  `n` = Zugnummer schützt gegen Doppel-/Out-of-order-Züge, Server checkt nur „bist du dran“.
- **Tomate** ist die EINE Ausnahme mit Server-Regel (1×/Runde), weil’s sonst gespammt wird.
- Disconnect mitten im Spiel: Room bleibt 120 s reserviert (Rejoin mit gleichem `deviceId`
  → `BOARD_RESUME {history}`), danach Forfeit-Info an den Verbliebenen.

### 3.6 Coop-Fahrt (Fahrer + Radio)

`drive:<uuid>`-Room: Fahrer sendet `kind:CAR {pos, speed}` 5 Hz; Beifahrer sendet
`kind:RADIO {station, trackId, positionSec, playing}` nur bei Änderung. Radio-Sync =
Zustands-Replikation, kein Audio-Streaming (beide haben die Tracks lokal — Content-Pack).

### 3.7 Post (Briefe + Fotos + Item-Geschenke)

- Foto-Upload über **REST**, nicht WS: `POST /api/mail` (multipart: JSON-Teil + JPEG).
  **Limits:** Foto ≤ `GOOBY_MAX_PHOTO_KB` (512 KB, Client resized auf ≤ 1280 px vor
  Upload), Text ≤ 1000 Zeichen, Magic-Bytes-Check (JPEG/PNG only), Mailbox-Quota
  50 Briefe / 20 MB pro Empfänger (ältester gelesener fliegt), Auto-Prune nach 90 Tagen.
- Item-Geschenke: `{"item":{"id":"toaster","qty":1}}` — Server prüft nur Katalog-ID-Format
  (Whitelist kommt per Content-Pack-Manifest, s. §B-Updater); Abzug beim Sender ist
  Client-Sache VOR dem Senden (offline-first-Ökonomie), Gutschrift beim Empfänger beim Abholen.
- Abholen: `MAIL_LIST` → `MAIL_STATE {mails:[…]}`, Foto lazy via `GET /api/blob/<id>`.
- Neue Post wird online gepusht (`MAIL_NEW`) und beim Boot gepullt (`WELCOME.mailCount`).

### 3.8 Koop-Minigames-Relay (GvZ PvP/Coop, GOB-NOM-Coop) — SIMPEL

**Empfehlung: Host-autoritativ + Input-/Event-Relay. KEIN Lockstep.** Begründung:
Lockstep verlangt deterministische Simulation in Godot (Float-Determinismus über iOS-Geräte
= Riesen-Risiko) und Frame-genaue Input-Verzögerung. Unsere Spiele sind gutmütig:

- **GvZ PvP** („einer platziert Goobys, einer Zombies“): quasi rundenbasiert.
  Platzierungen = Events `kind:PLACE {lane, slot, unitId, n}`. Der **Einladende ist Host**
  und simuliert; er sendet 2 Hz Snapshots `kind:STATE {n, units:[…], nutella, hp}` (≤ 8 KB
  komprimierbar — Grid ist klein); der Gast rendert Snapshots + eigene Platzierungs-Preview.
  Bei 2 Hz + Interpolation sieht Tower-Defense flüssig aus.
- **GvZ Coop** (Reihen geteilt): identisch, beide senden PLACE, Host simuliert.
- **GOB-NOM Coop** (geteilter Bildschirm, Puzzle-artig): Züge/Aktionen sind diskret →
  reines Event-Relay `kind:ACT {n, action}` mit Sequenznummer, beide simulieren lokal
  den (kleinen, diskreten) Zustand; alle 5 s Host-`kind:CHECK {n, hash}` — bei Mismatch
  einmalige Voll-Resync vom Host. Diskrete Puzzle-Logik IST determinierbar (Int-Grid).
- Disconnect → Minigame pausiert 30 s („Warte auf Lena…“), dann Abbruch ohne Strafe.

### 3.9 IGohbie-Social-Apps (aus §E)

- **Freunde-Status-App** = UI über `FRIENDS_STATE`/`FRIEND_PRESENCE` (§3.2). Offline:
  letzter gecachter Stand + „Offline“-Banner.
- **GoobyPal-App** = §3.3 + Verlaufs-Liste (`PAL_HISTORY` → letzte 30 Transfers des Geräts).
- **InstantGooby** (Bilder + Nachrichten an Freunde) = **dasselbe Mail-Backend** (§3.7),
  nur andere UI (Feed statt Briefkasten): `kind:"insta"`-Mails, gleiche Limits/Quota.
  Bewusst KEIN Echtzeit-Chat (Moderations-/Scope-Falle) — Nachrichten sind Brief-artig.
- **Snap A Gooby im Multiplayer** („Handy vor sich halten“): rein visuell —
  `ROOM_MSG kind:EMOTE {id:"phone_up"}` im Visit-Room; das Foto selbst ist lokal
  (Kamera-Feature), teilen läuft über InstantGooby/Post.

---

## 4. Webpanel (gleicher Express-Prozess)

Server-gerendertes HTML + vanilla JS, **kein Frontend-Build-Step** (AMP-freundlich).
Login: `GOOBY_ADMIN_PASSWORD` (ENV, Pflicht) → scrypt-Vergleich → `cookie-session`
(httpOnly, sameSite=lax, 12 h). 5 Fehlversuche/15 min pro IP → Lockout. Ohne gesetztes
Passwort ist `/panel` hart deaktiviert (503 + Log-Warning) — **niemals offen**.

| Seite | Inhalt |
|---|---|
| `/panel/login` | Passwort-Form |
| `/panel/` **Dashboard** | Online-Clients (FriendCode, Name, Aktivität, Verbindungsdauer), aktive Rooms, Server-Uptime, Datenverzeichnis-Größe, letzte Fehler |
| `/panel/analytics` | **SPIELZEIT (wichtigstes Analytic):** Sessions-Tabelle + 3 simple Diagramme (vendored Ein-File-Chartlib): Minuten/Tag (30 Tage), Sessions/Wochentag-Heatmap „wann“, Session-Längen-Histogramm „wie lange“; Filter pro Spieler; Zahlen „wie oft“ = Sessions/Woche |
| `/panel/codes` | CRUD-Tabelle (Code, Reward-JSON, maxUses, Gültigkeit, Uses-Zähler), „Neu“-Form, Deaktivieren-Knopf |
| `/panel/events` | Event auslösen: Typ-Dropdown (Regen-Event, Doppel-Coins-Stunde, Ansage-Text …), Ziel (alle / FriendCode), Ablaufzeit → Push an Online-Clients + Pull-Queue; Verlaufs-Liste mit Zustell-Status |
| `/panel/friends` | Freundschafts-Graph: simples SVG-Force-Layout (Knoten = FriendCode+Name, Kanten = Freundschaften, grün = online) + Request-Liste |

**Events-Zustellung (Push + Pull):** Online-Clients kriegen sofort
`{ "t":"SERVER_EVENT","d":{"id":"evt-…","type":"WEATHER_RAIN","params":{…},"expiresAt":…}}`;
Offline-Clients holen beim nächsten Boot `WELCOME.pendingEvents` ab (Server merkt
`deliveredTo` pro Gerät, `expiresAt` verhindert Uralt-Regen).

**Analytics-Ingest offline-gepuffert:** Client schreibt Session-Records (Start/Ende/Minuten —
gespeist vom Godot-Pendant des `profileStats.tickPlaytime`-Ticks) in eine `user://`-Queue
und flusht bei Verbindung batchweise: `POST /api/analytics {sessions:[…]}` (idempotent
via Client-`sessionId`-UUID — doppelte Flushes dedupliziert der Server).

**Codes-DOPPELSTRATEGIE (Online + Offline):**

- **Offline-Codes** bleiben wie im Web-GOOBY (`codesEngine.js`-Muster): Katalog wird als
  Content-Pack-Datei mitgeliefert (per §B-Auto-Updater erweiterbar!), Redeem rein lokal,
  Rate-Limit lokal. Für „Update Liebe“-artige, für alle gleiche Geschenk-Codes.
- **Online-Codes** (Panel-CRUD): begrenzte Nutzungen, Gültigkeitsfenster, pro Gerät 1×,
  server-gezählt — für Aktionen/Verlosungen, sofort ausstellbar ohne jedes Update.
- **Auflösungsreihenfolge im Client:** Eingabe → erst lokaler Katalog; unbekannt UND
  online → `POST /api/codes/redeem {code}` → Server antwortet Reward-JSON, Client wendet
  ihn über denselben lokalen Reward-Pfad an. Unbekannt UND offline → „Unbekannt — bist du
  offline? Online-Codes brauchen Verbindung“. Namensräume kollidieren nicht: Server lehnt
  Code-Anlage ab, wenn der Name im mitgelieferten Offline-Manifest existiert.

---

## 5. Offline-first-Regeln (bindend für den Godot-Client)

1. **ALLES Kern-Gameplay läuft ohne Server.** Kein Feature aus §D–§H wartet je auf HTTP.
2. `NetClient` (s. §6) hat drei Zustände: `OFFLINE → CONNECTING → ONLINE`. UI-Elemente
   der Social-Features binden an ein Signal `net_state_changed` und zeigen bei
   OFFLINE einen einheitlichen „Offline“-Chip statt Spinner/Fehler.
3. Degradation pro Feature: Freunde-Tab = letzter Cache + Offline-Chip; GoobyPal-Senden,
   Besuche, Brettspiele, Coop = Knöpfe disabled mit Tooltip; Post = Entwürfe landen in
   der Outbox und gehen beim Reconnect raus; Codes = Doppelstrategie (§4).
4. **Outbox-Muster:** `user://net/outbox/*.json` für alles nicht-flüchtige (Analytics-
   Sessions, Briefe, Profil-Updates). Flüchtiges (Presence, POS, Coins-SYNC) wird NIE
   gepuffert — veraltete Presence ist schlimmer als keine.
5. Reconnect: Exponential Backoff 1→2→4→…→60 s, Jitter; kein Modal, kein Blockieren.
   Nach WELCOME: Outbox flushen → `pendingEvents`/Mail abholen → Presence neu setzen.
6. Server-IP/Port kommen aus der Remote-Config des §B-Updaters (ohne IPA änderbar);
   Fallback auf den zuletzt funktionierenden Endpoint in `user://`.

---

## 6. Godot-Client: `NetClient`-Autoload-Design

```
autoload/net_client.gd          # DAS Autoload (Singleton). Öffentliche API + Signals.
autoload/net/ws_link.gd         # WebSocketPeer-Wrapper: poll() im _process, Frame-Assembly
autoload/net/protocol.gd        # Envelope build/parse, v-Konstante, seq-Vergabe, re-Matching
autoload/net/outbox.gd          # user://net/outbox — persistente Sende-Queue (atomar)
autoload/net/identity.gd        # deviceId/deviceSecret erzeugen & in user:// halten
autoload/net/rooms.gd           # Room-Membership + kind-Dispatcher an Feature-Nodes
```

- **API-Stil:** `NetClient.request(t, d) -> Awaitable` (Coroutine, resolved bei `re`-Match,
  Timeout 10 s → `{ok:false, code:"TIMEOUT"}`); Push-Messages als Signals:
  `friend_presence(d)`, `server_event(d)`, `mail_new(d)`, `room_msg(room, kind, body)`,
  `net_state_changed(state)`, `pal_received(d)`.
- `_process`: `ws.poll()`; Heartbeat-Timer; Backoff-Timer. Kein Thread — `WebSocketPeer`
  ist poll-basiert, JSON-Parsing unserer Nachrichtengrößen ist frame-billig.
- Feature-Module (FriendsApp, VisitManager, BoardGameTable …) reden NUR mit `NetClient`,
  nie mit dem Socket — testbar mit einem `FakeLink` (gleiche Schnittstelle wie `ws_link`,
  skriptbare Antworten; Muster analog zu den headless node:test der Web-Version).
- REST (Uploads/Analytics): `HTTPRequest`-Pool in `net_client.gd`, gleiche
  `Authorization: Bearer <deviceId>:<deviceSecret>`-Header.

---

## 7. Sicherheit

- **Kein PII:** nur Spitznamen, deviceId (zufällige UUID), Fotos (User-Content — Hinweis
  im Panel: „Fotos können Persönliches zeigen, Server privat halten“). Keine E-Mail,
  kein echtes Login, keine IP-Speicherung über Session-Dauer hinaus (Rate-Limit-Buckets
  sind in-memory).
- **Token:** `deviceSecret` = 32 Byte crypto-random, entsteht CLIENT-seitig beim ersten
  Start, geht im ersten HELLO mit (TOFU — Trust On First Use); Server speichert nur
  `sha256(secret)`. Jede spätere Verbindung/REST muss es vorweisen. Verlust = neuer
  Account (bewusst simpel; „Account-Umzug“ = Backlog: Transfer-Code im Panel generierbar).
- **Transport:** AMP-Instanz idealerweise hinter TLS-Proxy → `wss://`; README dokumentiert
  beides, Client akzeptiert `ws://` nur wenn Remote-Config es explizit erlaubt (Heimnetz).
- **Rate-Limits (Token-Bucket, `ratelimit.js`):** WS-Messages 30/s pro Verbindung;
  HELLO 5/min pro IP; FRIEND_REQUEST 10/h pro Gerät; PAL_SEND 20/h; Mail 20/Tag pro
  Gerät; Codes-Redeem 5/15 min (Muster identisch zum lokalen `codesEngine`-Lockout);
  Analytics-Batch ≤ 200 Sessions/Request. Panel-Login 5/15 min pro IP.
- **Panel niemals öffentlich ohne Passwort:** ohne `GOOBY_ADMIN_PASSWORD` ist `/panel`
  503 (Fail-closed, s. §4). Keine Default-Passwörter, kein „admin/admin“.
- **Input-Härtung:** jede Message gegen Typ-Schema geprüft (protocol.js), Payload-Limits
  (WS-Frame ≤ 16 KB außer nix — Uploads sind REST), Blob-Magic-Bytes, Pfad-Traversal-sichere
  Blob-IDs (nur server-generierte IDs, nie Client-Dateinamen).

---

## 8. iOS Live Activities fürs Taxi-Warten — ehrliche Optionen

**Fakt:** Godot hat kein natives ActivityKit; Live Activities brauchen zwingend eine
**Widget-Extension** (eigenes Swift/SwiftUI-Target in der Xcode-Projektdatei) + App-seitiges
ActivityKit-Start/Stop. Das ist ein echtes iOS-Plugin-Projekt, kein Nachmittag.

### M1: Lokale Notifications (Fallback, sofort machbar)

Die Taxi-Wartezeit (5–10 min) wird **client-seitig beim Rufen festgelegt** → alle
Zeitpunkte sind vorab bekannt → **lokale, vorab geplante Notifications reichen komplett**,
null Server-Beteiligung:

- Kleines iOS-Plugin (`gooby_notify`, Objective-C/Swift, UNUserNotificationCenter):
  `request_permission()`, `schedule(id, title, body, delay_sec, sound)`, `cancel(id)`,
  `cancel_all_prefix(prefix)`. (~200 Zeilen nativer Code — auch fürs §F-Random-Event-
  Zeitfenster wiederverwendbar!)
- Beim Taxi-Rufen plant der Client: T−15 s „🚕 Dein Taxi ist gleich da!“ und
  T+60 s „Das Taxi ist wieder weggefahren 😾“ (wird gecancelt, wenn der Spieler
  rechtzeitig einsteigt/die App öffnet). App zu = Notification weckt den Spieler; App
  offen = In-Game-Banner stattdessen (Foreground-Handler unterdrückt die System-Notification).

### Backlog M3+: ActivityKit-Plugin (Skizze)

- Xcode-Seite: Widget-Extension-Target `GoobyTaxiActivity` (SwiftUI); `TaxiAttributes:
  ActivityAttributes { let calledAt: Date; let arrivesAt: Date }`; UI nutzt
  `Text(timerInterval: now...arrivesAt)` — **iOS rendert den Countdown selbst**, d. h.
  die Activity braucht während des Wartens KEINE Updates (kein Push-Token, kein Server!).
  Dynamic-Island-Compact: Taxi-Emoji + Countdown. `staleDate = arrivesAt + 60 s`,
  danach `end(dismissalPolicy: .after(arrivesAt + 90 s))`.
- Godot-Seite: GDExtension/Plugin-API `start_taxi_activity(arrives_in_sec)`,
  `end_taxi_activity()`. GitHub-Actions-IPA-Build muss das Extension-Target mitbauen
  (Godot-iOS-Export + nachgelagerter xcodebuild-Schritt — der eigentliche Aufwandstreiber).
- Eigenes Design (User-Wunsch): SwiftUI-Layout mit generiertem Taxi-/Gooby-Artwork.

---

## 9. Prioritäten

| Meilenstein | Inhalt |
|---|---|
| **M1 — Fundament** | Server-Skeleton (server.js, store, protocol, hub, ratelimit), HELLO/WELCOME/PING, Identity + FriendCode, `NetClient`-Autoload + Outbox, **Analytics-Sessions** (Ingest + Panel-Diagramme), **Codes** (Online-CRUD + Redeem + Doppelstrategie), **Freunde + Presence + Coins-Cache**, Panel (Login, Dashboard, Analytics, Codes, Friends-Graph), Events (Push+Pull), lokale Taxi-Notifications (`gooby_notify`-Plugin) |
| **M2 — Zusammen spielen** | Rooms-Relay, **Besuche** (Haus-Snapshot REST + POS-Relay + Bau-Warnung), **Brettspiele** (Schach, Schiffe versenken, Emotes, Tomate), Post/Mail + InstantGooby (Uploads, Quota), GoobyPal-Transfers |
| **M3 — Rest** | Coop-Fahrt (Auto+Radio), Koop-Minigames-Relay (GvZ PvP/Coop, GOB-NOM), Snap-A-Gooby-Emote, Account-Umzugs-Code, ActivityKit-Live-Activity |

## 10. Risiken

1. **AMP-Umgebung unbekannt exakt** (Node-Version, npm-Verhalten) → darum null native
   Deps + Node ≥ 18-Kompatibilität + `/health` für AMP-Monitoring. Restrisiko klein.
2. **Bauen-während-Besuch-Konflikte** — bewusst Best-Effort + Warnung (User hat’s genau
   so bestellt); Snapshot-`rev` verhindert dauerhafte Divergenz.
3. **GvZ-Snapshot-Größe** bei 2 Hz auf großem Board → Messen; notfalls Delta-Snapshots.
4. **Foto-Uploads = User-Content** auf Privatserver → Quota + Prune + README-Hinweis;
   keine öffentliche Galerie, nur Freund→Freund.
5. **TOFU-deviceSecret**: wer den Server-Datenordner leakt, leakt nur Hashes; aber
   Erst-HELLO über `ws://` im offenen Netz wäre abhörbar → README drängt auf TLS.
6. **iOS-Notification-Permission** kann verweigert werden → Taxi funktioniert trotzdem
   (In-Game-Timer), Notification ist reiner Komfort.
7. **Schach-Legalität nur client-seitig** — Cheaten unter Freunden möglich; akzeptiert
   für M2 (Freundeskreis-Server), Server-Validierung wäre M3+-Option.

## 11. Scope-Schätzung (Dateien / LOC)

| Teil | Dateien | LOC (≈) |
|---|---|---|
| GOOBY-SERVER src/ (14 Module) | 16 | 3.800 |
| Panel (Views + static, kein Build) | 9 | 1.400 |
| Server-Tests (node:test) | 6 | 1.200 |
| Godot `NetClient` + net/* | 6 | 1.600 |
| Godot Feature-Glue (FriendsApp, VisitManager, BoardTable, MailUI, PalApp) | 8 | 2.400 |
| `gooby_notify` iOS-Plugin (M1) | 3 | 250 |
| Docs (README-Server/AMP, docs/PROTOCOL.md) | 2 | 500 |
| **Summe** | **50** | **≈ 11.150** |

(ActivityKit-Backlog separat: ~5 Dateien / 600 LOC + CI-Arbeit.)

---

## Top-Entscheidungen (Kurzfassung)

**Protokoll:** Godot `WebSocketPeer` (low-level) + Node `ws` — ENet hat kein brauchbares
Node-Binding und bringt UDP-Port-Ärger in AMP. Eigenes versioniertes JSON-Envelope
(`{v,t,seq,ts,d}`), HELLO mit deviceId+deviceSecret+FriendCode, PING/PONG 20 s,
Rooms als generischer Relay-Kanal (`visit:`, `board:`, `drive:`, `mg:`).

**Server:** EIN Node-Prozess, EIN Port — express (Panel+REST) und ws teilen denselben
HTTP-Listener. **Storage = reine JSON-Files** (Snapshots + JSONL-Logs + Blobs):
better-sqlite3 ist nativ und kann auf AMP beim `npm install` scheitern; unsere
Freundeskreis-Skala braucht kein SQL. Storage-Interface erlaubt späteren
`node:sqlite`-Swap. Konfig via ENV > config.json.

**Autorität:** Offline-first heißt client-autoritative Ökonomie; NUR GoobyPal-Transfers
(250/Tag-Ledger) sind server-autoritativ und online-only. Alles andere degradiert
sauber (Offline-Chip, Outbox in `user://`, gepufferte Analytics-Sessions).

**Multiplayer simpel:** Brettspiele = Turn-Relay (Server prüft nur Turn-Ownership +
Tomate 1×/Runde), Besuche = Haus-Snapshot per REST + 5-Hz-Positions-Relay,
Minigames = Host-autoritativ mit 2-Hz-Snapshots bzw. Event-Relay — **kein Lockstep**
(Float-Determinismus-Risiko).

**Codes-Doppelstrategie:** Offline-Katalog per Content-Pack (bewährtes
codesEngine-Muster) + Online-Codes mit Panel-CRUD; Client löst lokal zuerst auf.

**Live Activities:** M1 = winziges UNUserNotificationCenter-Plugin (Taxi-Zeiten sind
vorab bekannt → geplante lokale Notifications genügen); ActivityKit-Widget-Extension
mit selbstlaufendem `Text(timerInterval:)`-Countdown als M3-Backlog.

**Panel fail-closed:** ohne `GOOBY_ADMIN_PASSWORD` ist `/panel` deaktiviert.
