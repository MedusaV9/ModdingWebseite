# Gooby Ranch DLC — Multiplayer, Technik, iOS und Komfort

**Ideen-Agent 4 (Sol) · Stand 26.07.2026 · Konzept, kein Spielcode**

Dieses Dokument bewertet den vorhandenen Stand und schlägt einen umsetzbaren Ausbau vor. Es geht
bewusst nicht von einem MMO, einer Anti-Cheat-Infrastruktur oder einem ständig verfügbaren
Dedicated-Game-Server aus. Ziel ist ein robustes Spiel für einen kleinen Freundeskreis auf der
vorhandenen Node.js-Instanz.

## Kurzentscheidung

| Thema | Empfehlung |
|---|---|
| Multiplayer-Modell | **Asynchron + 1:1-Besuche zuerst, instanzierte 2–4-Spieler-Minispiele danach.** Keine persistente geteilte Ranch-Welt. |
| Echtzeit-Synchronisation | Client simuliert sein Pferd; 10 Hz Pose-Snapshots, 100–150 ms Interpolationspuffer, keine Reiter-Kollision. Node ist autoritativ für Startzeit, Checkpoints, Ergebnis und Belohnung. |
| Typische Bandbreite | Bei vier Spielern konservativ etwa **24 kbit/s Upload und 80 kbit/s Download je Client**; rund **320 kbit/s Server-Egress je laufender Vierer-Partie** inklusive 20 % Reserve. |
| iOS | Lokale Notifications und Haptik sind realistische erste native Plugins. Eine lokale Live Activity ist möglich, braucht aber eine Swift/SwiftUI-Widget-Extension und einen Godot-iOS-Bridge. APNs-Updates und normale Verteilung brauchen das bezahlte Apple Developer Program. Eine wirklich unsignierte App läuft auf keinem iPhone. |
| Grafik | Mobile-Renderer beibehalten; Auto-Profil mit 30/60/120 FPS, 3D-Auflösung 0,67–1,0 und thermischem Herunterschalten. UI bleibt in nativer Auflösung. |
| Audio | Für die erste Fassung überwiegend CC0-Dateien verwenden; URL, Urheber, Lizenz, Downloaddatum und Hash mit jedem Asset archivieren. |

---

## 1. Bestand: Was schon da ist und was die Ranch neu braucht

### 1.1 Node.js-Server

Die Serverarchitektur ist bereits passend für ein kleines Freundesprojekt: ein Node-Prozess, ein
Port, Express und `ws`, keine nativen Module und JSON-Persistenz. Das ist wesentlich einfacher zu
betreiben als eine zusätzliche Echtzeit-Engine.

| Vorhandener Baustein | Beleg im Repository | Für die Ranch wiederverwenden | Fehlender Ranch-Ausbau |
|---|---|---|---|
| HTTP + WebSocket in einem Prozess | `GOOBY-SERVER/server.js`, `GOOBY-SERVER/README.md` | Unverändert; Ranch-REST und Ranch-WS laufen auf demselben Port | Neues Modul registrieren, keine zweite Serverinstanz |
| Envelope `{v,t,seq,ts,d}` und `re`-Korrelation | `src/protocol.js` | Alle neuen Nachrichten nutzen Version 1 und denselben Envelope | Ranch-Nachrichten dokumentieren und Schema-/Grenztests ergänzen |
| TOFU-Identität, `HELLO/WELCOME`, Heartbeat | `src/ws.js` | Geräteidentität, Online-Verbindung, `PING/PONG`, WELCOME-Provider | `WELCOME` nur um kleine Ranch-Zusammenfassung ergänzen, keine kompletten Ghosts |
| Freunde | `src/friends.js` | Einladungsziele und Zugriffsprüfung | Ranch-Einladungen müssen serverseitig `NOT_FRIENDS` prüfen |
| Presence | `src/presence.js` | Status „auf der Ranch“, „im Rennen“, „in der Show“ | Neue Presence-Kinds und serverseitige deutsche Texte |
| Generische Räume | `src/rooms.js` | Mitgliedschaft, Join/Leave, Relay, Peer-Events | Derzeit **hart auf 2 Mitglieder** begrenzt. Für `mg:` selektiv 4 erlauben; `visit:` und `board:` bei 2 lassen |
| Besuch mit POS-Relay | `src/visits.js` | Bewährtes 1:1-Einladungs- und Abbruchmuster | Besuch bleibt 5 Hz; Renn-Pose bekommt einen eigenen 10-Hz-Handler |
| Rate-Limits | `src/ratelimit.js` | Token-Buckets und stilles Verwerfen veralteter Posen | Separates `mgPose`-Limit, z. B. 12/s mit Burst 20; Events deutlich niedriger |
| Brettspiel-Sitzung | `src/boardgames.js` | Startzustand, Turn-/Phasenbesitz, History und 120-s-Rejoin als Muster | Eigenes Match-State-Modell; Pferdephysik nicht in JavaScript nachbauen |
| GoobyPal | `src/goobypal.js` | Pending-Delivery + `PAL_ACK` ist das Muster für genau-einmalige Ranch-Belohnungen | Ranch-Reward-Ledger mit idempotenter `rewardId` |
| Server-Events | `src/events.js` | Offline-Zustellung und ACK-Muster | Für Turnierankündigungen nutzbar; nicht für 10-Hz-Daten |
| JSON-Persistenz | `src/storage.js` | Atomisches tmp→fsync→rename, JSONL-Audit | Neue kleine Collections für Scores/Ghosts/Matches; Größenlimits und Retention |

Wichtige Grenzen des Ist-Stands:

1. `src/rooms.js` definiert `MAX_MEMBERS = 2`. Dies global auf 4 zu setzen wäre falsch, weil dadurch
   auch Besuche und Brettspiele unbeabsichtigt Mehrpersonenräume würden. Die Kapazität muss pro
   Präfix oder Raum-Metadatum gelten: `visit:/board:/drive:` = 2, `mg:` = 4.
2. Der bestehende `POS`-Relay ist mit 5 Hz limitiert. Das reicht für einen gemütlichen Hausbesuch,
   nicht für enges Rennen oder Fangen. Ranch-Minispiele brauchen einen separaten `MG_POSE`-Bucket.
3. Brettspiele sind absichtlich nur bei Turn-Ownership autoritativ; Trefferlogik bleibt Client-Sache.
   Für Ranch-Ergebnisse muss der Server etwas strenger sein, weil sonst ein Crash oder Doppel-Request
   doppelte Belohnungen erzeugt.
4. JSON-Dateien sind für Dutzende Freunde ausreichend. Sie sind keine Grundlage für tausende
   gleichzeitige Matches. Genau diese Skalierung ist hier nicht nötig.

### 1.2 Godot-Client

| Vorhandener Baustein | Beleg | Wiederverwenden | Neu nötig |
|---|---|---|---|
| Offline-first WebSocket-Client | `scripts/net/net_client.gd` | Verbindung, Envelope, Requests, PING und exponentieller Reconnect mit Jitter | Ranch-Dispatcher und Clock-Offset-Messung |
| Persistente Outbox | `scripts/net/outbox.gd` | Nur für idempotente, langsame Operationen wie Ergebnis-ACK oder Ghost-Upload | **Keine** Pose in die Outbox; alte Positionen sind wertlos |
| Freunde und Presence | `scripts/net/friends_service.gd`, `presence.gd` | Einladungs-UI, Status | Ranch-spezifische Presence-Kinds |
| Sozialer Orchestrator | `scripts/social/social_services.gd` | Ein gemeinsamer Einstiegspunkt | `RanchMultiplayerService` als weiterer Child-Service |
| Visit-Service | `scripts/social/visit_service.gd`, `visit_logic.gd` | Invite/Accept/Room-Flow und 5-Hz-Poseformat als Vorlage | Eigener Match-Flow, 10 Hz, bis 4 Peers |
| Remote-Figur | `scripts/social/remote_gooby.gd` | Interpolation und Animation einer entfernten Figur | `RemoteHorse` mit Puffer, Gait, Sprung und Teleport-Snap |
| Brettspiel-Session | `scripts/social/boardgame/board_session.gd` | Snapshot/Rejoin/History-Muster | Ranch-Snapshot enthält Zeit, Checkpoints, Tag-/Staffelzustand |
| Notification-Stubs | `scripts/events/notify_stub.gd`, `scripts/city/notification_service.gd` | API-Namen `schedule_local`, `cancel_local`, `pending` | Ein natives iOS-Backend statt zwei paralleler Stubs |
| App-Einstellungen | `scripts/core/app_settings.gd`, `scripts/ui/settings_screen.gd` | Atomische `settings.json`, bestehende Sprache/Audio/Bewegungsreduktion | Versionierte neue Grafik-, Bedien- und Accessibility-Keys |
| Reitgefühl | `scripts/ranch/gameplay/ride_controller.gd`, `ride_feel.gd` | Gänge, Beschleunigung, Sprung, Ausdauer, Hufschlag-Phase | Netzwerkadapter darf das lokale Fahrgefühl nicht ersetzen |

### 1.3 Klare neue Komponenten

Serverseitig:

- `ranch_multiplayer`-Modul für Invite, Match-Lifecycle, `MG_POSE`, Ereignisse, Rejoin und Resultat.
- Raumkapazität pro Raumtyp statt globalem `MAX_MEMBERS`.
- `ranch_scores.json`, begrenzte Ghost-Ablage und append-only `ranch-rewards.jsonl`.
- Serverseitige Plausibilitätsprüfung, aber **keine** doppelte Godot-Pferdephysik in JavaScript.
- REST-Endpunkte für Bestenliste/Ghost-Download; WebSocket bleibt für laufende Matches.

Clientseitig:

- `RanchMultiplayerService`, `RemoteHorse`, Match-Lobby und Ergebnis-ACK.
- Ein gemeinsames natives iOS-Plugin mit Modulen für Notifications, ActivityKit, Haptik und
  Thermal-State; die SwiftUI-Widget-Extension bleibt ein separates Xcode-Target.
- Ein zentraler `QualityManager`, damit Szenen nicht jeweils eigene widersprüchliche Qualitätslogik
  implementieren.

---

## 2. Multiplayer-Entwurf

### 2.1 Bewertung der Modelle

| Modell | Nutzen | Aufwand/Risiko | Urteil |
|---|---|---|---|
| Persistente geteilte Ranch-Welt | Freunde sind jederzeit sichtbar, starkes „gemeinsam wohnen“-Gefühl | Weltzustand, Ownership, Konflikte beim Bauen, Interest-Management, lange Sessions, mehr Persistenz- und Rejoin-Fälle | **Nicht bauen.** Für den Freundeskreis zu viel Infrastruktur und wenig zusätzlicher Spielwert. |
| Kurzlebige geteilte Weide, 2–4 Spieler | Gemeinsames Reiten ohne Matchdruck | 10-Hz-Pose, Join/Leave, keine harten Weltänderungen | Später als „Freie Weide“ möglich; nur instanziert und ohne gemeinsames Bauen |
| Besuchsmodus 1:1 | Bereits implementiert, persönlich, robust | Nur zwei Spieler, 5 Hz nicht wettbewerbstauglich | **Sofort wiederverwenden** für Stall zeigen, Pferd ansehen, pflegen und Geschenke |
| Instanzierte Minispiele 2–4 | Direkter Mehrspielerwert, klarer Start/Ende, kleiner Zustand | Neuer Match-State und höhere Pose-Rate | **Empfohlener Echtzeit-Ausbau** |
| Asynchron: Ghosts, Bestenlisten, Geschenke, Show-Bewertungen | Funktioniert trotz Zeitverschiebung, fast keine Live-Bandbreite, einfacher Reconnect | Moderation/Retention und Ergebnisvalidierung | **Zuerst liefern**; höchstes Nutzen-Aufwand-Verhältnis |

**Empfohlene Reihenfolge**

1. Ranch-Presence, Pferdegeschenke und 1:1-Stallbesuch auf vorhandener Technik.
2. Asynchroner Parcours mit Bestzeit, Freundes-Bestenliste und genau einem Best-Ghost pro
   Spieler/Strecke.
3. Live-Rennen für zunächst zwei, danach vier Spieler.
4. Staffel, Fangen und Schau-Jury auf demselben Match-Fundament.
5. Freie Vierer-Weide nur dann, wenn die Minispiele stabil sind. Keine persistente Shared World.

### 2.2 Autoritätsmodell: hybrid statt „alles Server“ oder „alles Client“

Godot und Node haben keine gemeinsame Physik. Eine serverautoritativ nachgebaute Pferdesimulation
würde zwei Implementierungen erzeugen, die sich bei Hang, Kollision und Framerate auseinanderentwickeln.
Vollständiges Client-Vertrauen wäre dagegen bei Gold und Rekorden unnötig fragil.

| Zustand | Autorität | Begründung/Prüfung |
|---|---|---|
| Lokale Pferdebewegung, Kamera, Animation | Client | Sofortiges Fahrgefühl ohne Roundtrip |
| Remote-Darstellung | Empfangender Client | Interpolation aus serverweitergeleiteten Snapshots |
| Raum-Mitgliedschaft, Teams, Ready | Server | Kein Spieler darf sich selbst in fremde Matches setzen |
| Kurs-ID, Seed, Startzeit | Server | Alle sehen dieselbe Variante und denselben Countdown |
| Checkpoint-/Rundenreihenfolge | Server | Event nur akzeptieren, wenn Reihenfolge stimmt und letzte Pose in Triggernähe liegt |
| Zielzeit | Serverzeit | `finishAt - startAt`, nicht vom Client gemeldete Stoppuhr |
| Tag-Übergabe/Staffelstab | Server | Distanzprüfung mit letzten Posen, Cooldown und Ereignisnummer |
| Show-Wertung | Server | Stimmen deduplizieren; niemand stimmt für sich selbst |
| Gold, Items, XP, Rekord | Server | Idempotente `rewardId`; Ledger zuerst schreiben, dann ACK |
| Kosmetik | Client, serverseitig erlaubt-listen | Unbekannte Asset-ID durch Standard-Pferd ersetzen |

Plausibilitätsprüfung ist **Crash- und Fehlerabwehr**, kein professionelles Anti-Cheat:

- `poseSeq` muss monoton steigen; alte/duplizierte Posen werden verworfen.
- Maximale Distanz pro Zeitfenster aus Maximaltempo + großzügiger 30-%-Toleranz.
- Teleport, unrealistische Beschleunigung und Checkpoint-Sprünge markieren den Lauf als
  `unranked`, trennen aber nicht sofort die Freundesrunde.
- Checkpoint muss in richtiger Reihenfolge und innerhalb eines serverbekannten Radius ausgelöst
  werden.
- Mindestzeit pro Streckenabschnitt verhindert Resultate von 0 Sekunden.
- Pro `matchId + friendCode` genau eine Ergebnis-/Reward-Zeile. Wiederholte Requests liefern
  dasselbe Resultat.
- Dev-Profil, modifizierter Save oder inkompatible Protokollversion: gemeinsames Spielen erlaubt,
  aber keine Bestenliste und keine Belohnung.

### 2.3 Protokoll

Alle Nachrichten behalten den vorhandenen Envelope. Ein Pose-Beispiel ist 172 UTF-8-Bytes groß:

```json
{"v":1,"t":"MG_POSE","seq":1234,"ts":1721980000123,"d":{"room":"mg:a8f4","p":[12.34,0.52,-8.91],"yaw":1.47,"speed":9.8,"gait":3,"anim":"gallop","jump":false,"poseSeq":481}}
```

Lange Schlüssel sind bei vier Spielern noch kein Problem. Binärprotokoll, UDP und WebRTC wären
vorzeitige Komplexität.

| Nachricht | Richtung | Frequenz | Inhalt/Zweck | Serververhalten |
|---|---|---:|---|---|
| `HELLO` / `WELCOME` | C↔S | Verbindung | Bestehende Identität; Protokollfeatures und `serverNowMs` | Wiederverwenden |
| `RANCH_INVITE` | C→S | Ereignis | Ziel-FriendCode, Modus, Kurs | Freundschaft, Onlinezustand und Cooldown prüfen |
| `RANCH_INVITED` | S→C | Ereignis | Einlader, Modus, Ablaufzeit | 30-s-Einladung, nur eine aktive pro Paar |
| `RANCH_ACCEPT/DECLINE` | C→S | Ereignis | Invite-ID | Server erzeugt `mg:<randomId>` |
| `MG_JOIN` | C→S | einmal | Match-ID, letzter bekannter State | Mitgliedschaft prüfen; nicht freies `ROOM_JOIN` vertrauen |
| `MG_SNAPSHOT` | S→C | Join/Rejoin | Spieler, Teams, Seed, Phase, Checkpoints, Score, `stateVersion` | Vollständiger kanonischer Zustand |
| `MG_READY` | C→S | Ereignis | Asset geladen, Kurs-Hash | Start erst bei kompatiblen Clients |
| `MG_START` | S→C | einmal | `startAtServerMs`, Seed | Mindestens 3 s in Zukunft; Countdown lokal |
| `MG_POSE` | C→S | 10 Hz bewegt, 2 Hz idle | Quantisierte Position, Yaw, Tempo, Gang, Anim, Sprung, Sequenz | Rate-/Plausibilitätscheck; an andere Mitglieder als `MG_PEER_POSE` |
| `MG_EVENT` | C→S | bei Bedarf | Checkpoint, Ziel, Stabübergabe, Hindernis, Tag-Versuch | Typ- und Phasenlogik serverseitig validieren |
| `MG_STATE` | S→C | 2 Hz + sofort bei Änderung | Runde, Platz, Tag-Spieler, Strafzeit, Teamfortschritt | `stateVersion` monoton |
| `MG_RESUME` | C→S | nach Reconnect | Match-ID, letzte Version/ACK | Snapshot statt vollständiger Tick-History |
| `MG_RESULT` | S→C | einmal + Retry | Platz, Zeit, Reward-ID, ranked/unranked | Bis `MG_RESULT_ACK` erneut in WELCOME anbieten |
| `MG_RESULT_ACK` | C→S | idempotent | Reward-ID | Pending-Zustellung entfernen |
| `GHOST_PUT` | C→S REST | Laufende | Ergebnis-ID + quantisierter Track | Nur nach akzeptiertem Resultat, Größenlimit |
| `GHOST_GET` / `LEADERBOARD_GET` | C→S REST | Menü | Kurs, Freunde, Version | ETag/Version und paginierte kleine Antwort |

`ROOM_MSG` bleibt für Besuch/Brettspiel erhalten. Der schnellere `MG_POSE` bekommt absichtlich einen
eigenen Handler, damit niemand durch einen anders benannten `kind` das 5-Hz-Limit umgeht.

### 2.4 Frequenz, Interpolation und Netzfehler

- **Senderate:** 10 Hz während Bewegung, 2 Hz nach 500 ms Stillstand, sofort bei Sprung/Landung.
  Fangen darf 15 Hz verwenden, wenn Gerät und Verbindung stabil sind.
- **Rendering:** RemoteHorse hält 100–150 ms Puffer und rendert zwischen den zwei umgebenden
  Snapshots. Position linear oder Hermite mit begrenzter Tangente; Yaw über den kürzesten Winkel;
  Gait/Animation als diskreter Zustand.
- **Paketlücke:** höchstens 250 ms aus letzter Geschwindigkeit extrapolieren, danach ausrollen und
  „Verbindung schwach“ anzeigen. Nach neuem Snapshot über 200 ms einblenden; bei >6 m Differenz
  hart snappen.
- **TCP-Effekt:** WebSocket ist geordnet und zuverlässig. Ein verlorenes TCP-Segment kann spätere
  Snapshots kurz blockieren. Deshalb keine Pose wiederholen, keinen Pose-ACK senden und beim Server
  nur die neueste wartende Pose pro Spieler weitergeben.
- **Kollision:** Reiter sind untereinander Ghosts. Harte Pferde-Kollision bei 100–150 ms Puffer würde
  sichtbar divergieren. Kursobjekte bleiben rein lokal deterministisch.
- **Clock-Sync:** PING/PONG misst Roundtrip; Offset aus mehreren Messungen per Median. Ergebnisse
  verwenden trotzdem nur Serverzeit. Der Client braucht den Offset für Countdown und Anzeige.

### 2.5 Bandbreitenrechnung

Annahmen:

- obiges `MG_POSE`: **172 B** JSON;
- Client-WebSocket-Header bei >125 B inklusive Maske: **8 B**;
- Server-WebSocket-Header ohne Maske: **4 B**;
- konservativ **70 B** pro Nachricht für TCP/IP, TLS-Record/Tag und Rundung;
- 10 Posen/s; `MG_STATE` konservativ 400 B Nutzlast, 2/s;
- vier Spieler, jeder empfängt die drei anderen; 20 % Reserve für Events und Schwankung.

**Client-Upload**

```text
(172 + 8 + 70) B × 10/s = 2 500 B/s
mit 20 % Reserve          = 3 000 B/s = 24 kbit/s
```

**Client-Download bei vier Spielern**

```text
Posen:  (172 + 4 + 70) B × 10/s × 3 Peers = 7 380 B/s
State:  (400 + 4 + 70) B ×  2/s           =   948 B/s
Summe mit 20 % Reserve                     ≈ 9 994 B/s ≈ 80 kbit/s
```

**Server-Egress je Vierer-Match**

```text
Posen: 246 B × 10/s × 4 Sender × 3 Empfänger = 29 520 B/s
State: 474 B ×  2/s × 4 Empfänger            =  3 792 B/s
mit 20 % Reserve                              ≈ 39 974 B/s ≈ 320 kbit/s
```

Bei zwei Spielern sinkt der Download grob auf 34 kbit/s. Bei 5 Hz halbiert sich der Pose-Anteil.
TLS/TCP kann mehrere kleine Frames bündeln, daher ist diese Ein-Paket-pro-Nachricht-Rechnung bewusst
konservativ. Audio/Voice-Chat ist **nicht** enthalten und wird nicht empfohlen.

Ein 3-minütiger Ghost mit 5 Hz enthält 900 Samples. Mit quantisierten 16 B pro Sample sind das
14,4 KB roh, als Base64 plus Metadaten etwa 20 KB. Pro Kurs und Freund nur den besten kompatiblen
Ghost behalten; dadurch bleibt JSON-/Dateispeicher kontrollierbar.

### 2.6 Persistenz und Wiederverbindung

Persistieren:

- Match-Metadaten bei Start: Match-ID, Mitglieder, Modus, Kursversion, Seed, Startzeit.
- Ergebnis und Reward atomisch/idempotent bei Abschluss.
- Freundes-Bestzeiten und genau einen Best-Ghost pro Kursversion.
- Append-only Reward-Audit mit `rewardId`, vor/nach Gold/XP und Match-ID.

Nicht persistieren:

- 10-Hz-Pose, Interpolationspuffer, Partikel, Kamera und komplette Tick-History.
- Abgebrochene freie Weiden nach Ende des Rejoin-Fensters.

Reconnect:

1. Socket verwendet den vorhandenen exponentiellen Backoff.
2. Match reserviert den Platz 120 Sekunden, analog zum Brettspiel. Das Pferd bleibt stehen und wird
   halbtransparent.
3. Client sendet nach `WELCOME` ein `MG_RESUME`; Server antwortet mit `MG_SNAPSHOT`.
4. Rennuhr läuft serverseitig weiter. Nach 120 s wird der Spieler DNF; im Freundschaftsmodus darf
   der Host optional neu starten.
5. Ein bereits geschriebenes Resultat wird nie neu berechnet, sondern mit derselben `rewardId`
   erneut zugestellt.

### 2.7 Konkrete Minispiele und Synchronisation

| Minispiel | Spieler | Synchronisationsstrategie | Autoritative Regeln | Bewusste Vereinfachung |
|---|---:|---|---|---|
| Rennen gegeneinander | 2–4 | 10-Hz-Pose, gemeinsames `startAt`, `MG_STATE` 2 Hz | Start, Checkpointfolge, Runden, Zielzeit, Platz | Keine Reiter-Kollision; grobe Rempler nur kosmetisch |
| Staffel | 2v2 | Rennen + serverseitiges `BATON_REQUEST`; Position beider Teammitglieder liegt im Übergabekorridor | Teamreihenfolge, Übergabe, Zeit, Fehlstartstrafe | Stab ist Zustand, kein netzwerksimuliertes Physics-Objekt |
| Geschicklichkeits-Parcours | 1–4 live oder Ghost | Jeder fährt unabhängig; 10-Hz-Pose nur zur Ansicht, Hindernis-Events sofort | Torfolge, Strafsekunden, Mindestsegmentzeiten, Ergebnis | Keine gemeinsamen beweglichen Hindernisse |
| Fangen auf der Weide | 3–4 | 15-Hz-Pose, Server hält letzte 500 ms; `TAG_REQUEST` mit Ziel und Zeitpunkt | Tag-Spieler, Distanz mit begrenztem Lag-Rewind, 2-s-Immunität, Rundenuhr | Kein Körperblocken; großzügiger 2–2,5-m-Tag-Radius |
| Pferdeschau/Jury | 2–4 live, beliebig asynchron | Performance ist geordnete Ereignisliste; Zuschauer-Pose genügt 5 Hz; Stimmen ereignisbasiert | Start/Ende, erlaubte Tricks, eine Stimme je Freund, keine Selbststimme | Bewertung durch Freunde statt objektiver Bewegungs-KI |

Für Version 1 ist **Parcours + Ghost** die beste erste Umsetzung: Sie testet Ergebnisvalidierung,
Bestenliste, Ghost-Storage und UI ohne Live-Match-Abhängigkeit. Danach nutzt Rennen dieselben
Checkpoints und dieselbe Resultatpipeline.

---

## 3. iOS-Möglichkeiten — realistische Machbarkeit

### 3.1 Aktueller Projektstand

- `GOOBY-GODOT/README.md` sagt ausdrücklich: noch kein laufender iOS-Build; Notification-Plugin und
  NSUserDefaults-Reader sind Stubs.
- `export_presets.cfg` setzt iOS 14.0 als Mindestversion. ActivityKit gibt es erst ab iOS 16.1;
  daher bleibt immer ein Notification-Fallback nötig.
- `project.godot` verwendet den Godot-Mobile-Renderer und ASTC/ETC2-Import. Ein explizites
  30/60/120-Profil existiert noch nicht.
- Der „unsigned IPA“-Workflow in `IOS-BUILD.md` meint ein **unsigniertes Artefakt vor der
  Installation**. AltStore/Sideloadly signiert es. Eine unverändert unsignierte App kann iOS nicht
  installieren oder starten.

### 3.2 Machbarkeitsmatrix

| Fähigkeit | Technisch nötig | Personal Team / kostenloses Sideloading | Bezahltes Developer Program | Aufwandsschätzung |
|---|---|---|---|---:|
| Lokale Notification | `UNUserNotificationCenter`, Berechtigung, Calendar/TimeInterval-Trigger, Deep Link | **Ja**, nach Signierung; 7-Tage-Profil bleibt Einschränkung | Ja | 2–4 Personentage |
| Haptik | Core Haptics, `CHHapticEngine`, Capability-Check, Fallback | **Ja**, nach Signierung | Ja | 2–4 Personentage inkl. Tuning |
| Lokale Live Activity | SwiftUI + WidgetKit-Extension, ActivityKit, `NSSupportsLiveActivities`, Godot-Bridge, iOS 16.1+ | **Prinzipiell testbar**, aber jede Installation muss signiert werden; Extension-Signing auf echten Geräten zuerst als Spike beweisen | Ja | 7–12 Personentage für belastbares MVP |
| Live Activity per Server aktualisieren/enden | APNs, Activity-Push-Token, Backend-Tokenablage, `.p8`-Key, Entitlements | **Nein**: Push Notifications gehören nicht zum kostenlosen Personal-Team-Profil | **Ja** | zusätzlich 5–10 Personentage |
| App Group für gemeinsame Dateien/Defaults | Capability auf App und Extension | Laut Apple-Capability-Tabelle **nicht für kostenlose Apple-Accounts** | Ja | 1–2 Tage, falls wirklich benötigt |
| App Store/TestFlight/Ad-hoc-Verteilung | Distribution-Zertifikate/Profile | **Nein** | Ja, Mitgliedschaft 99 USD/Jahr | Prozessaufwand |
| 120 Hz | ProMotion-Gerät, Godot High-Refresh erlaubt, `Engine.max_fps=120`, 8,33-ms-Budget | Ja | Ja | 2–5 Tage Profiling, kein bloßer Schalter |

Die Aufwandsschätzungen setzen einen Mac mit Xcode, ein echtes iPhone und Erfahrung mit
Objective-C++/Swift voraus. Sie enthalten Gerätetests, nicht nur „kompiliert einmal“.

### 3.3 Live Activities für Wartequests

Apple verlangt:

1. Ein Widget-Extension-Target. UI wird in **SwiftUI/WidgetKit** gebaut, nicht in einer Godot-Szene.
2. Gemeinsame `ActivityAttributes` und `ContentState` in App und Extension.
3. `NSSupportsLiveActivities = true` in der App-Konfiguration.
4. Eine native Godot-iOS-Bridge. Der offizielle Godot-Weg ist eine statische `.a`/`.xcframework`
   plus `.gdip`; Swift kann hinter einer kleinen Objective-C++-Fassade liegen.
5. API etwa `start_wait_quest(id,title,endDate)`, `update_wait_quest(...)`,
   `end_wait_quest(id)` und eine Fehler-/Authorization-Abfrage.
6. Einen reproduzierbaren Exportprozess, der die Widget-Extension bei jedem Godot-Export wieder
   einfügt. Manuelle Xcode-Klicks nach jedem Export sind kein wartbarer Build.

**Sinnvoller lokaler MVP:** Die App startet die Activity beim Beginn der Quest und übergibt ein
absolutes Enddatum. SwiftUI zeigt den Countdown mit einem systemgerenderten Timer; dafür muss Godot
nicht jede Sekunde im Hintergrund laufen. Parallel wird eine lokale Notification für das Enddatum
geplant.

Grenzen:

- Die Live Activity selbst hat keinen freien Netzwerkzugriff.
- `Activity.update()` funktioniert lokal nur, wenn die App Ausführungszeit bekommt. iOS garantiert
  keinen beliebigen Hintergrund-Tick. Ohne APNs kann der Server eine pausierte/verkürzte Quest nicht
  zuverlässig auf dem Lockscreen korrigieren, während die App geschlossen ist.
- Eine Live Activity ist höchstens **8 Stunden aktiv** und kann danach noch bis zu 4 Stunden auf dem
  Lockscreen verbleiben. Wartequests über 8 Stunden nutzen primär lokale Notifications.
- Eine einfache Activity braucht nicht zwingend eine App Group: ActivityKit transportiert den
  `ContentState`. App Groups werden erst nötig, wenn App und Extension zusätzliche gemeinsame
  Dateien/UserDefaults lesen sollen.
- `NSSupportsLiveActivitiesFrequentUpdates` ist für häufige Remote-Pushes. Ein Quest-Countdown
  braucht diese Option nicht.
- ActivityKit ist iOS 16.1+, Dynamic Island nur auf passenden Geräten. Andere Geräte zeigen die
  Lockscreen-Darstellung.

**Urteil:** Nach einem funktionierenden signierten iOS-Build ein guter M2-Baustein, aber kein
„einfacher Godot-Schalter“. Vorher lokale Notifications liefern.

### 3.4 Lokale Notifications

Die vorhandenen beiden Stubs sollten auf **ein** Interface zusammengeführt werden:

```text
request_permission()
schedule_local(id, title, body, at_ms, deep_link)
cancel_local(id)
pending()
```

Native Umsetzung: `UNMutableNotificationContent` +
`UNTimeIntervalNotificationTrigger`/`UNCalendarNotificationTrigger` +
`UNNotificationRequest`, geplant über `UNUserNotificationCenter`. IDs bleiben idempotent: Eine
erneut geplante Quest ersetzt ihre alte Notification; Abschluss/Abbruch storniert sie.

Produktregeln:

- Berechtigung erst in einem erklärenden In-Game-Dialog anfordern, nicht beim ersten Start.
- Kategorien getrennt schaltbar: Wartequests, Stall/Pflege, Freunde/Turnier.
- Ruhezeit, standardmäßig 21:00–08:00; Fertigmeldungen in die nächste erlaubte Zeit verschieben.
- Deep Link öffnet genau die Ranch-Quest, fällt aber sicher aufs Ranch-Menü zurück.
- Ablehnung ist kein Fehler: In-App-Badge und `NotifyStub`-Bubble bleiben verfügbar.

### 3.5 Core Haptics

Core Haptics eignet sich für kurze, sparsame Signale:

- leiser transienter Impuls auf betonte Hufschläge, nicht auf jeden Audiotick;
- kräftiger kurzer Impuls bei Landung;
- weicher Doppelimpuls bei perfektem Hindernis;
- Warnpuls bei leerer Ausdauer;
- keine Dauervibration bei Galopp.

Vor Initialisierung `CHHapticEngine.capabilitiesForHardware().supportsHaptics` prüfen. Apple nennt
unter anderem iPads als Geräte ohne Core-Haptics-Wiedergabe; dort bleibt Audio/visuelles Feedback.
Engine einmal früh erzeugen, auf Unterbrechung/Reset reagieren und im Hintergrund stoppen.

Settings: `Haptik aus / dezent / normal / stark`; bei Bewegungsreduktion standardmäßig „dezent“.
Audio-Hufschläge bleiben die Zeitquelle, damit Haptik nicht rhythmisch driftet.

### 3.6 ProMotion, Metal/MoltenVK und Renderer

- 120 Hz ist ein **Qualitätsmodus**, kein Mindestziel. Das Framebudget beträgt 8,33 ms statt
  16,67 ms bei 60 Hz. Auf nicht-ProMotion-Geräten fällt die Anzeige auf die verfügbare Rate zurück.
- Godot 4.4 kennt `display/window/ios/allow_high_refresh_rate` (Default laut Referenz `true`);
  zusätzlich setzt der Laufzeitmodus `Engine.max_fps` auf 30/60/120.
- Der Mobile-Renderer ist für diese stilisierte Ranch richtig. Forward+ auf iOS wäre schlechter
  optimiert und bringt hier keinen ausreichenden Nutzen.
- Godot 4.4 führt einen nativen Metal-Treiber, markiert ihn aber als **experimentell**. Vulkan über
  MoltenVK bleibt ein valider iOS-Pfad. Native-Metal/MetalFX darf erst nach echten A/B-Tests
  Standard werden.
- Mobile nutzt rasterbasierte Shader; Compute-Unterstützung ist eingeschränkt. Pro Mesh wirken
  höchstens 8 Omni- plus 8 Spot-Lights. Daraus folgt: eine Schatten-Sonne außen, gebackenes Licht/
  Blob-Shadows innen, keine „neue iPhone = unbegrenzt viele Lichter“-Annahme.
- MetalFX-Spatial/Temporal ist in Godot nur mit dem Metal-Treiber verfügbar. Bei experimentellem
  Treiber bleibt FSR 1/Bilinear der sichere Basispfad.

Das bestehende `E4-perf.md` liefert eine Warnung: Die Besuchsszene liegt mit 166 Draw Calls und
124.526 Dreiecken über dem Raumbudget, weil innen ein Directional Shadow aktiv ist; Battleship hat
232 einzigartige Materialien. Vor einer 120-Hz-Aussage müssen diese bekannten Muster in Ranch-Szenen
vermieden werden.

### 3.7 Speicher- und Thermalbudget

iOS veröffentlicht keine eine feste, für alle Geräte sichere „RAM-Grenze“. `jetsam` hängt von Gerät
und Systemdruck ab. Deshalb keine Aussage wie „neue iPhones haben 8 GB, also darf das Spiel 6 GB
nutzen“.

Interne Ziele für die Ranch:

| Messgröße | Ziel |
|---|---:|
| Physischer Footprint im stabilen Ranch-Spiel | ≤350 MB auf dem ältesten unterstützten Test-iPhone |
| Kurzer Peak beim Szenenwechsel | ≤500 MB, danach innerhalb 10 s zurück |
| Textur-/Renderbudget | bestehendes Projektbudget ≤350 MB; ASTC aktiv |
| 60-Hz-GPU/CPU-Frame | je <14 ms im 95. Perzentil, Reserve zum 16,67-ms-VSync |
| 120-Hz-GPU/CPU-Frame | je <7 ms im 95. Perzentil, sonst automatisch 60 Hz |
| Dauertest | 20 Minuten Reiten + Wetter + vier Remote-Pferde auf echtem Gerät |

Native Telemetrie darf `os_proc_available_memory()` als Headroom-Signal und den physischen Footprint
für QA erfassen. Auf `UIApplication`-Memory-Warning: unbenutzte Szenen/Audio entladen, Ghost-Cache
leeren, Partikel reduzieren.

`ProcessInfo.thermalState` und
`thermalStateDidChangeNotification` steuern Auto:

- `nominal`: gewähltes Profil;
- `fair`: Partikel 75 %, Schattenreichweite -25 %, 120→60;
- `serious`: 30/60 FPS, Skalierung max. 0,75, Post-FX aus;
- `critical`: 30 FPS, Skalierung 0,67, neue schwere Szene nicht vorladen und verständlichen Hinweis
  anzeigen.

Das Herunterschalten braucht Hysterese: frühestens nach 60 s in besserem Thermalzustand wieder
hochschalten, sonst pulsiert die Qualität.

### 3.8 Was ohne signierte App nicht geht

- **Gar keine App-Ausführung auf einem echten iPhone.** „Unsigned IPA“ ist nur das Artefakt vor
  AltStore/Sideloadly; die Installation wird signiert.
- Keine App-Store-, TestFlight- oder normale Ad-hoc-Verteilung über ein kostenloses Personal Team.
- Keine APNs-Push-Notifications und damit keine zuverlässigen serverseitigen Live-Activity-Updates.
- Keine App Groups mit dem kostenlosen Profil laut Apples Capability-Matrix.
- Nach sieben Tagen läuft ein kostenloses Provisioning-Profil ab; App erneut signieren/installieren.
  Apple nennt außerdem 10 App IDs, 3 Geräte pro Plattform und 3 Apps pro Gerät für den
  Personal-Team-Workflow.

Lokale Notifications, Haptik und ein lokaler ActivityKit-Spike sind erst **nach** erfolgreicher
Personal-Team-/AltStore-Signierung testbar. Das Repository hat diesen Gerätetest noch nicht belegt.

---

## 4. Grafik- und Komfort-Einstellungen

### 4.1 Menüstruktur

1. **Anzeige:** Qualitätsprofil, Bildrate, 3D-Auflösung, Schatten, Sichtweite, Partikel,
   Nachbearbeitung.
2. **Oberfläche & Barrierefreiheit:** UI-Skalierung, Textgröße, Bewegungsreduktion,
   Farbfehlsichtigkeit, Kontrast, Untertitel.
3. **Steuerung:** links/rechts, Schema, Empfindlichkeit, Auto-Galopp, Sprungknopf.
4. **Audio & Haptik:** Master, Musik, Effekte, Umgebung, UI, Haptik.
5. **Benachrichtigungen:** Kategorien, Ruhezeit, Systemstatus.

Jede Grafikänderung zeigt eine Vorschau und einen 15-s-„Behalten?“-Dialog. Bei App-Abbruch wird das
letzte bestätigte Profil geladen.

### 4.2 Qualitätsprofile

| Profil | 3D-Skala | FPS | Schatten | Sichtweite | Partikel | Post-FX | Ziel |
|---|---:|---:|---|---:|---:|---|---|
| Niedrig | 0,67 FSR1/Bilinear | 30 | Blob, dynamisch aus | 0,70× | 35 % / Systeme deckeln | aus | altes/thermisch belastetes Gerät |
| Mittel | 0,80 FSR1 | 60 | 1 Sonne außen, kurz | 0,85× | 65 % | nur Farbkorrektur | Standard ab iPhone 11 nach Messung |
| Hoch | 1,00 nativ | 60 | 1 Sonne außen, höher aufgelöst | 1,00× | 100 % | selektiv | stabile 60 Hz |
| 120 Hz | 0,85–1,00 dynamisch | 120 | wie Mittel | 0,85× | 75 % | sparsam | nur ProMotion + <7-ms-Messung |
| Auto | dynamisch 0,67–1,00 | 30/60/120 | dynamisch | dynamisch | dynamisch | dynamisch | Benchmark + Framezeit + Thermal-State |

„Auto“ darf nicht nur Modellnamen hardcoden. Ablauf:

1. konservativ Mittel/60 starten;
2. 10 s echte Ranch-Szene messen, CPU/GPU-Framezeit und 1-%-Lows;
3. nur nach 30 s stabiler Reserve erhöhen;
4. bei drei Sekunden über Budget sofort eine Stufe senken;
5. Thermal- und Memory-Signale haben Vorrang;
6. manuelle Wahl bleibt bis „Auto“ erneut aktiviert wird.

### 4.3 Mapping auf Godot

| UI-Regler | Werte | Godot-Wirkung | Implementierungshinweis |
|---|---|---|---|
| Qualität | Niedrig/Mittel/Hoch/Auto | Wendet ein versioniertes Bündel der folgenden Werte an | Einzelregler können Profil als „Benutzerdefiniert“ markieren |
| 3D-Auflösung | 67/75/80/90/100 % | `Viewport.scaling_3d_scale`; `scaling_3d_mode` = Bilinear/FSR | 3D-Puffer skaliert pro Achse: 0,67 bedeutet nur ca. 45 % Pixel; UI bleibt nativ |
| Bildrate | 30/60/120/Auto | `Engine.max_fps`; iOS-Export `display/window/ios/allow_high_refresh_rate=true` | 120 nur anbieten, wenn Display/Profil es erreicht |
| MSAA | aus/2×/4× | `Viewport.msaa_3d` bzw. `rendering/anti_aliasing/quality/msaa_3d` beim Start | 8× nicht anbieten; hohe Kosten, kaum mobiler Nutzen |
| Schatten | aus/niedrig/hoch | `Light3D.shadow_enabled`, `DirectionalLight3D.directional_shadow_max_distance`, `Viewport.positional_shadow_atlas_size` | Innen immer Blob/gebacken; max. eine Schatten-Sonne außen |
| Sichtweite | 70–100 % | `Camera3D.far`, `GeometryInstance3D.visibility_range_end`, LOD-/Deko-Distanzen | Terrain/Kursziele nie ausblenden; nur Deko staffeln |
| Partikel | 0/35/65/100 % | Systeme aus/ein; `GPUParticles3D.amount` oder vorbereitete Varianten, optional `amount_ratio` | Nur `amount_ratio` spart nicht die volle Allokation; Low nutzt kleinere Systeme |
| Nachbearbeitung | aus/dezent/hoch | unterstützte `Environment`-Effekte und Ranch-Fullscreen-Pass | Mobile-Feature prüfen; Glow/DOF/SSAO nicht blind aktivieren |
| UI-Skalierung | 85/100/115/130 % | Benutzerfaktor auf vorhandenes `UiScale.for_viewport()` und Theme-Font-/Spacing-Tokens | Nicht an `scaling_3d_scale` koppeln; Safe Area und Mindest-Touchziel beibehalten |
| Textgröße | 100/115/130/150 % | Theme-Fontgrößen, Mindesthöhen, Auto-Wrap | Bei 150 % alle Menüs mit längsten deutschen Strings testen |
| Bewegungsreduktion | aus/an | vorhandenes `reduced_motion`; Kamera-Bob, Shake, FOV-Kick, Parallax, lange Transitions aus | Gameplay-Timing und Trefferfeedback dürfen nicht verschwinden |
| Farbfehlsichtigkeit | aus/Protan/Deutan/Tritan | semantische Palette + Icons/Muster; optional Canvas-Farbmatrix | Nie nur Rot/Grün unterscheiden; Checkpoints zusätzlich Form/Nummer |
| Hoher Kontrast | aus/an | alternative Theme-Ressource, stärkere Outline/Focus | Nicht durch stärkere Sättigung ersetzen |
| Händigkeit | links/rechts | Touch-Container-Anker spiegeln | Text/Icons nicht spiegeln; Bestätigung vor Match möglich |
| Steuerungsschema | fester/freier Joystick, Buttons, optional Neigen | Touch-Zonen/InputMap; Neigen über Geräte-Sensor nach Kalibrierung | Neigen nie Default und immer mit Nullpunkt/Empfindlichkeit |
| Lenkempfindlichkeit | 50–150 % | Faktor vor `RideController`-Lenkeingang | Physikgrenzen unverändert, nur Eingabekurve |
| Lautstärken | Master/Musik/SFX/Umgebung/UI 0–100 % | `AudioServer.set_bus_volume_db(..., linear_to_db(value))` | Bestehende Master/Music/SFX migrieren; 0 % mutet Bus |
| Haptik | aus/dezent/normal/stark | Intensitätsmultiplikator im nativen Core-Haptics-Plugin | Capability-Check; keine Wirkung als Fehler behandeln |

Farbmodi brauchen eine Testkarte mit Fellfarben, Hindernisflaggen, Warnung und Erfolg. Ein
Fullscreen-Shader allein macht schlecht gewählte Gameplay-Farben nicht zugänglich; Formen, Icons und
Text sind die primäre Kodierung.

### 4.4 Persistenz und Migration

`AppSettings` bleibt getrennt vom Spielstand. Neue Keys liegen unter einer Settings-Schema-Version,
zum Beispiel:

```text
graphics.preset, graphics.scale_3d, graphics.fps, graphics.shadows
accessibility.ui_scale, accessibility.text_scale, accessibility.color_vision
controls.handedness, controls.scheme, controls.steering_sensitivity
audio.ambience, audio.ui, haptics.intensity
notifications.wait_quests, notifications.social, notifications.quiet_hours
```

Unbekannte/ungültige Werte fallen auf sichere Defaults zurück. Das bestehende atomische
tmp→rename-Schreiben wird beibehalten. Grafikänderungen werden erst nach Bestätigung als
`last_known_good` gespeichert.

---

## 5. Versteckte Entwickleroptionen

### 5.1 Aktivierung ohne Versehen

Der verlangte Weg bleibt erhalten:

1. Spracheinstellungen öffnen.
2. „Deutsch“ muss bereits ausgewählt sein.
3. Innerhalb von 1,5 Sekunden dreimal auf **den Text „Deutsch“** tippen; Wechsel über den Picker zählt
   nicht.
4. 1 Sekunde haptisches/visuelles Signal und Dialog „Entwicklermodus aktivieren?“.
5. Dialog verlangt zusätzlich 2 Sekunden Halten auf „Testprofil erstellen“.

Weitere Schutzmaßnahmen:

- Nach drei Fehlversuchen 10 s Cooldown.
- Permanentes gelb-schwarzes `DEV`-Badge, solange aktiv.
- Deaktivierung in derselben Seite und automatisch nach Release-Update, wenn das Dev-Schema
  inkompatibel ist.
- Optionaler Build-Schalter kann das Menü in öffentlichen Builds vollständig entfernen. Für den
  privaten Sideload-Build darf es enthalten sein.

### 5.2 Inhalt

| Bereich | Funktion | Schutz |
|---|---|---|
| Performance | FPS, CPU/GPU-Framezeit, Draw Calls, Primitives, Nodes, VRAM/Footprint, Thermal-State | Nur lesen; Ringbuffer für 60 s |
| Zeit/Wetter | Tageszeit, Wind, Regen, Gewitter setzen | Nur Testprofil; „Zur Simulation zurück“ |
| Gold/Level | Werte setzen/addieren | Clamp, Bestätigung, vorher Snapshot; online keine Rewards/Leaderboard |
| Quest | Starten, Timer auf 10 s, abschließen, überspringen | Nur registrierte Quest-ID; State-Machine-API statt JSON-Manipulation |
| Pferd | Pferd/Variante an sicherem Spawnpunkt erzeugen | Allowlist, max. Anzahl, Cleanup beim Szenenwechsel |
| Save | Export, Import-Vorschau, Snapshot, Rollback | Vor Import Schema/Hash prüfen; nie ungefragt überschreiben |
| Netzwerk | Zustand, RTT, Reconnect, letzte Nachrichtstypen, Paket-/Rate-Zähler | Secrets/Tokens/deviceSecret und Chattext redigieren; max. 500 Einträge |
| Szene | Sprung zu registrierter Szene/Route | Vorher laufendes Match sauber verlassen; keine freien Dateipfade |
| iOS | Notification in 10 s, Live-Activity-Test, Haptikmuster, Thermalstatus | Nur vorhandene Capability anbieten |

### 5.3 Spielstand- und Online-Sicherheit

- Beim ersten Aktivieren wird der echte Save **nur gelesen und geklont**. Änderungen gehen in
  `user://dev/` mit eigener Profil-ID.
- Jede mutierende Aktion erzeugt vorher einen atomischen Snapshot mit Schema-Version und SHA-256.
- „Auf echten Spielstand übernehmen“ existiert nicht. Export/Import läuft über den normalen,
  validierenden Transferweg.
- Dev-Sessions senden `devSession=true`; der Server sperrt Rekord, Ghost-Upload, Gold und XP.
- Direktes Editieren von JSON ist nicht Teil des Menüs. Alle Aktionen verwenden dieselben
  GameState-/Quest-APIs wie das Spiel.
- Szenenwechsel räumt Test-Pferde, Timer und Wetter-Overrides auf.
- Netzwerklog zeigt Typ, Größe, Zeit und redigiertes Payload; Auth-Geheimnisse werden schon beim
  Erfassen entfernt, nicht erst in der UI.

---

## 6. Legale Sounds und Musik aus dem Internet

### 6.1 Lizenz- und Importregel

Freesound bietet CC0, CC BY und CC BY-NC. Für dieses Projekt:

- **CC0 bevorzugen**: kommerziell und nichtkommerziell nutzbar, Attribution rechtlich nicht nötig.
- **CC BY erlaubt**: Titel, Urheber, Quell-URL, Lizenz-Link und Änderungen in Credits/Manifest.
- **CC BY-NC vermeiden**: blockiert eine spätere kommerzielle Nutzung.
- Pixabay ist nicht automatisch CC0, sondern hat eine eigene Content License. Nutzung im Spiel ist
  erlaubt, rohe Standalone-Weiterverteilung nicht. Lizenzbeleg beim Download sichern.
- OpenGameArt-Einträge können gemischte Lizenzen haben. Bei Packs gilt die Datei-zu-Datei-Liste,
  nicht nur die Überschrift der Pack-Seite.

Für jedes übernommene Asset eine Zeile in `THIRD_PARTY_AUDIO.md` und eine lokale Lizenzkopie:

```text
Dateiname · Originaltitel · Urheber · Quell-URL · exakte Lizenz+URL
Downloaddatum · SHA-256 des Originals · Bearbeitungen · Ziel-Datei im Spiel
```

Originaldatei und Lizenzbeleg archivieren. Danach Stille schneiden, DC entfernen, auf 48 kHz
vereinheitlichen, Peaks/Lautheit angleichen und als Ogg Vorbis importieren. Loop-Punkte von Hand
prüfen. CC0 entbindet nicht von Audio-QA oder Marken-/Persönlichkeitsrechten.

### 6.2 Konkrete Beschaffungsliste

Alle Lizenzangaben wurden auf der jeweiligen Asset-Seite geprüft; vor dem tatsächlichen Download
noch einmal prüfen und den Beleg archivieren.

| Bedarf | Konkreter Kandidat | Lizenz | Einsatz/Bearbeitung |
|---|---|---|---|
| Hufschlag Gras | [Horse steps on grass — Luisa_Sanchez](https://freesound.org/people/Luisa_Sanchez/sounds/813383/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Einzelschläge schneiden, 4–6 Varianten, leise Graslage |
| Hufschlag Erde | [Foley horse gallops… dirt — craigsmith](https://freesound.org/people/craigsmith/sounds/675421/) | CC0 1.0 | Zaumzeuganteil bei Bedarf EQ; Walk/Trot/Gallop-Slices |
| Hufschlag Holz | [R13-07 Horse on Wood — craigsmith](https://freesound.org/people/craigsmith/sounds/479679/) | CC0 1.0 | Sprache/Clicks herausschneiden, Rauschen restaurieren |
| Hufschlag Stein/Beton | [Horse steps on concrete — Luisa_Sanchez](https://freesound.org/people/Luisa_Sanchez/sounds/813382/) | CC0 1.0 | Kurze trockene Varianten für Hof/Turnierplatz |
| Wiehern, echter Klang | [Horse Whinny, Close, A — InspectorJ](https://freesound.org/people/InspectorJ/sounds/419231/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); Assetseite verlangt Attribution | Sauberer echter Pferdeklang; TASL-Credit und Bearbeitung angeben |
| Wiehern, CC0-Platzhalter | [horse.wav — stomachache](https://freesound.org/people/stomachache/sounds/53261/) | CC0 1.0 | Menschliche Imitation, nur Prototyp/komischer Gooby-Stil, nicht als Naturaufnahme ausgeben |
| Schnauben | [Horse_Snorting.wav — Mar.Sounds](https://freesound.org/people/Mar.Sounds/sounds/628978/) | CC0 1.0 | Einzelnes sauberes Schnauben; Nah-/Fernvarianten |
| Sattel/Leder | [Sitting Down on Horse Saddle — craigsmith](https://freesound.org/people/craigsmith/sounds/481831/) | CC0 1.0 | Vogel entfernen, Lederknarzer einzeln schneiden |
| Zaumzeug/Metall | [Muddy Footsteps with Bridle Rattles — craigsmith](https://freesound.org/people/craigsmith/sounds/480673/) | CC0 1.0 | Schritte wegschneiden; 5–8 kurze Metall-/Lederbewegungen |
| Bürsten | [horse being brushed — ldezem](https://freesound.org/people/ldezem/sounds/223358/) | CC0 1.0 | 5-Minuten-Quelle in kurze Loops/One-shots schneiden |
| Heu/Stroh | [Plants or Straw hay — Vrymaa](https://freesound.org/people/Vrymaa/sounds/734643/) | CC0 1.0 | Rascheln, Greifen und Füttern getrennt schneiden |
| Wind | [Wind in the Trees — willstepp](https://freesound.org/people/willstepp/sounds/188288/) | CC0 1.0 | Schritte/Insekten prüfen; brauchbare Segmente nahtlos loopen |
| Regen | [Indoor raining loop — Rvgerxini](https://freesound.org/people/Rvgerxini/sounds/527658/) | CC0 1.0 | Stall-Dach-Layer; für draußen zusätzlich eigene leichtere Tropfenlage |
| Gewitter | [Loud Thunder sounds — Rvgerxini](https://freesound.org/people/Rvgerxini/sounds/620529/) | CC0 1.0 | Donner einzeln schneiden; zufällige Abstände, nie als kurzer Loop |
| Vögel morgens | [Birds in the Morning — MamickaBeeGames](https://freesound.org/people/MamickaBeeGames/sounds/801600/) | CC0 1.0 | Leisen 60–90-s-Loop wählen; nicht gleichzeitig mit Nachtgrillen |
| Bach | [Stream Brook Water Flow — freedomfightervictor](https://freesound.org/people/freedomfightervictor/sounds/387923/) | CC0 1.0 | 3D-Loop am Bach, Distanzfilter |
| Grillen nachts | [Crickets and Owl — gfrog](https://freesound.org/people/gfrog/sounds/159727/) | CC0 1.0 | Mehrere versetzte Loops; Eule selten |
| Stallatmosphäre | [Barn ambience — Sadiquecat](https://freesound.org/people/Sadiquecat/sounds/801824/) | CC0 1.0 | Enthält Nachbar-Klimaanlage: nur nach Noise-/Loop-QA übernehmen |
| Turnier-Menge, kurzer Jubel | [Short Affirmative Cheer — ShangusBurger](https://freesound.org/people/ShangusBurger/sounds/763830/) | CC0 1.0 | Layer für Zieleinlauf; 96 kHz auf 48 kHz konvertieren |
| Turnier-Menge, Applaus | [applause.wav — cognito perceptu](https://freesound.org/people/cognito%20perceptu/sounds/57587/) | CC0 1.0 | Stadioncharakter leise unter kurze Jubel legen |
| Fanfare | [Success Fanfare Trumpets — FunWithSound](https://freesound.org/people/FunWithSound/sounds/456966/) | CC0 1.0 | 4,4-s-Siegsting; MP3-Quelle auf Artefakte prüfen |
| Alternative Fanfare | [Simple Battle Fanfare — OpenGameArt](https://opengameart.org/content/simple-battle-fanfare) | CC0 1.0 | WAV/MIDI vorhanden; für Ranch freundlicher neu instrumentieren |

Qualitätsvorbehalt: Einige CC0-Aufnahmen sind historisch, verrauscht oder enthalten Nebengeräusche.
„Kostenlos“ bedeutet nicht automatisch „direkt shipping-fertig“. Wenn Restauration den Charakter
zerstört, lieber eine eigene Aufnahme machen.

### 6.3 Musik

| Situation | Kandidat | Lizenz | Urteil |
|---|---|---|---|
| Ruhige Ranch/Weide | [Sunset Plains — OpenGameArt](https://opengameart.org/content/sunset-plains) | CC0 1.0 | Warm, Gitarre/Flächen; sehr große WAV-Datei vor Import zu Ogg |
| Ruhiger Stall/Abend | [Restful Meadow — OpenGameArt](https://opengameart.org/content/restful-meadow) | CC0 1.0 | Kurzes friedliches Ogg; Loop musikalisch prüfen |
| Ernte/Ranch-Aufbau | [Medieval: Harvest Season — OpenGameArt](https://opengameart.org/content/medieval-harvest-season) | CC0 laut Assetseite | Passt zu Arbeit/Ausbau, Credits freiwillig |
| Fröhliches Turnier | [Fiddles McGinty — Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400051) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Nutzbar mit dem auf der Trackseite vorgegebenen Credit |
| Weitere Suche | [Pixabay Music](https://pixabay.com/music/) | [Pixabay Content License](https://pixabay.com/service/license-summary/) | Nicht „CC0“ nennen; Download-Link/Lizenzzertifikat sichern, Content-ID-Risiko beachten |

Musiksystem:

- Ranch, Stall, Parcours und Turnier als Stem-/Playlist-Zustände, keine harte Neustartschleife.
- 1–2 Sekunden Crossfade; bei Multiplayer richtet sich nur Start/Resultat-Sting nach Serverevent,
  Hintergrundmusik bleibt lokal.
- Musik unter Wiehern/Questdialog per Bus-Ducking um 4–6 dB.
- Pro Szene höchstens zwei vorgepufferte Tracks; übrige Streams bei Bedarf laden.

---

## 7. Quellen und überprüfbare Grundlagen

### Repository

- Serverübersicht und Betriebsmodell: `GOOBY-SERVER/README.md`
- Räume/2er-Limit/Relay: `GOOBY-SERVER/src/rooms.js`
- Token-Buckets/5-Hz-POS: `GOOBY-SERVER/src/ratelimit.js`
- Persistenz: `GOOBY-SERVER/src/storage.js`
- Rejoin- und ACK-Muster: `GOOBY-SERVER/src/boardgames.js`,
  `GOOBY-SERVER/src/goobypal.js`
- Godot-Netzwerk/Reconnect: `GOOBY-GODOT/scripts/net/net_client.gd`
- Visit-Pose/Interpolation: `GOOBY-GODOT/scripts/social/visit_logic.gd`,
  `GOOBY-GODOT/scripts/social/remote_gooby.gd`
- iOS- und Plugin-Stand: `GOOBY-GODOT/README.md`, `docs/godot-rewrite/IOS-BUILD.md`
- Gemessene Rendering-Probleme/Budgets: `docs/godot-rewrite/E4-perf.md`

### Apple

- [ActivityKit / Widget-Extension und Lebenszyklus](https://developer.apple.com/documentation/activitykit)
- [Live Activities anzeigen; Sandbox und maximale Dauer](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [PushType: lokale Updates vs. ActivityKit-Push](https://developer.apple.com/documentation/activitykit/pushtype)
- [Lokale Notifications planen](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Core Haptics vorbereiten und Capability prüfen](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics)
- [Thermal-State](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- [Spielespeicher messen, `os_proc_available_memory`](https://developer.apple.com/videos/play/wwdc2022/10106/)
- [Kostenloses Personal Team: 7 Tage, IDs und Geräte](https://developer.apple.com/support/compare-memberships)
- [Apple-Account-Überblick: zusätzlich höchstens 3 Apps je Gerät im kostenlosen Workflow](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- [Capability-Matrix: App Groups und Push](https://developer.apple.com/help/account/reference/supported-capabilities-ios)

### Godot 4.4

- [iOS-Plugins erstellen](https://docs.godotengine.org/en/4.4/tutorials/platform/ios/ios_plugin.html)
- [Renderer und Mobile-Eignung](https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html)
- [Interne Rendererarchitektur; Metal experimentell, MoltenVK und Mobile-Lichtgrenzen](https://docs.godotengine.org/en/4.4/contributing/development/core_and_modules/internal_rendering_architecture.html)
- [3D-Auflösungsskalierung](https://docs.godotengine.org/en/4.4/tutorials/3d/resolution_scaling.html)
- [Viewport-Eigenschaften einschließlich FSR/MetalFX](https://docs.godotengine.org/en/4.4/classes/class_viewport.html)
- [ProjectSettings einschließlich iOS High Refresh](https://docs.godotengine.org/en/4.4/classes/class_projectsettings.html)

### Lizenzen

- [Freesound-Lizenz-FAQ](https://freesound.org/help/faq/)
- [OpenGameArt-Lizenz-FAQ](https://opengameart.org/content/faq)
- [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- [Pixabay Content License](https://pixabay.com/service/license-summary/)

## Schlussurteil

Die Ranch sollte nicht mit einer persistenten Shared World beginnen. Das vorhandene System ist für
Freunde, 1:1-Besuche, zuverlässige Meta-Events und kleine Räume bereits gut. Der technisch saubere
Ausbau ist: asynchroner Parcours/Ghost, danach kurzlebige 2–4-Spieler-Matches mit 10-Hz-Pose und
serverautoritativen Ergebnissen. So bleibt das lokale Reitgefühl unangetastet, während Abstürze,
Doppelgold und offensichtlich falsche Rekorde abgefangen werden.

Auf iOS sind Notifications und Haptik kurzfristig realistisch. Live Activities sind wertvoll, aber
erst nach einem echten signierten iOS-Build und als native SwiftUI-Extension; ohne bezahltes Programm
bleiben Remote-Pushes und normale Verteilung ausgeschlossen. 120 Hz ist nur nach Framezeit- und
Thermalmessung ein ehrliches Feature. Die vorgeschlagenen Einstellungen machen diese Skalierung
sichtbar und kontrollierbar, statt „neue iPhones“ pauschal als unbegrenzte Hardware zu behandeln.
