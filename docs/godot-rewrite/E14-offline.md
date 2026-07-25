# E14 — Offline-first-Degradation

**Branch:** `cursor/gooby-godot-rewrite-d1d8`  
**Godot:** `4.4.1.stable.official.49a5bc7b6`  
**Verdict:** **FAIL (P0)** — Netzwerk-Grundzustand degradiert ruhig, aber der echte Boot ist
nicht spielbar. Zusätzlich verlieren Analytics Daten; Redeems/Events/Presence sind clientseitig
nicht vollständig verdrahtet.

Alle Treiber und Laufzeitdaten liegen ausschließlich unter `/tmp/gooby-godot/eval/`.
`curl http://127.0.0.1:8765/health` schlug vor den Läufen sofort fehl; kein GOOBY-SERVER lief.
`git status --short --untracked-files=no` blieb leer.

## P0

### P0-1 — Echter Boot bleibt hinter dem W1-Platzhalter; Haus/Stadt/Netz-Screens/Minigames sind verdeckt

- `GOOBY-GODOT/scripts/boot/main.gd:9-13` instanziert `home_entry.tscn`, entfernt/versteckt
  aber den Platzhalter nicht.
- `GOOBY-GODOT/scripts/boot/main.tscn:10-29` enthält weiterhin einen `CanvasLayer` auf Layer 10
  mit vollflächigem, opakem `PlaceholderHome/Backdrop`.
- Der Offline-xvfb-Treiber erreichte nachweislich `home/living`, `social`, `city` und `mg_host`;
  trotzdem sind `01_boot_home_offline.png` bis `05_minigame_offline_playable.png` pixelinhaltlich
  derselbe sichtbare „GOOBY — Platzhalter-Home“-Screen. Selbst Stadt und Minigame bleiben dahinter.
- Damit sind Bewegung/Interaktion in Haus und Stadt und die gerouteten Control-Screens nicht
  zugänglich. Das ist kein kosmetischer Fehler, sondern verletzt „voll spielbar ohne Server“.

**Repro**

```bash
XDG_DATA_HOME=/tmp/gooby-godot/eval/E14-shots-user2 \
  xvfb-run -a godot --path /workspace/GOOBY-GODOT \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --script /tmp/gooby-godot/eval/E14-offline-shots.gd
```

**Evidenz:** `E14-shots/01_boot_home_offline.png`,
`E14-shots/03_social_features_offline.png`, `E14-shots/04_city_offline_playable.png`,
`E14-shots/05_minigame_offline_playable.png`, `E14-shots-run2.log`.

### P0-2 — Gerouteter MinigameHost ist 0×0 (Viewport 2×2)

- `GOOBY-GODOT/scripts/minigames/minigame_host.tscn:5-6` gibt dem Root-Control kein Layout.
- `GOOBY-GODOT/scripts/minigames/minigame_host.gd:59-75` nutzt nur
  `set_anchors_preset(PRESET_FULL_RECT)`, nicht `set_anchors_and_offsets_preset`.
- Der Router mountet unter dem `Node3D`-World aus `GOOBY-GODOT/scripts/home/home_entry.gd:30-34`.
  Dort existiert kein Control-Parent-Rect, von dem die Offsets abgeleitet würden.
- Echter Main/Router-Lauf:  
  `target=mg_host busy=false host=(0,0) stage=(0,0) container=(0,0) viewport=(2,2)`.

**Repro**

```bash
XDG_DATA_HOME=/tmp/gooby-godot/eval/E14-main-route-user \
  godot --headless --path /workspace/GOOBY-GODOT \
  --script /tmp/gooby-godot/eval/E14-main-route-probe.gd
```

**Evidenz:** `E14-main-route-probe.log`.

## P1

### P1-1 — Analytics-Session wird beim normalen Boot nicht sofort in die Outbox geschrieben

- `GOOBY-GODOT/scripts/net/net_client.gd:70-73` macht `add_child(analytics)` **vor**
  `analytics.setup(self, outbox)`.
- Dadurch läuft `AnalyticsSessions._ready()` (`scripts/net/analytics.gd:35-36`) zuerst:
  `start_session()` vergibt eine ID, aber `_write_session()` bricht wegen `outbox == null` in
  `scripts/net/analytics.gd:104-106` ab. Späteres `setup()` schreibt den Start nicht nach.
- Nach 7,2 s Offline-Lauf: `outbox size=0`, Datei existiert nicht. Erst ein sauberer Exit schreibt
  über `_exit_tree`; ein SIGKILL nach 3 s ließ nur Identity/Boot-Guard zurück, keine Outbox.
- Crash/OS-Kill vor dem ersten 60-s-Heartbeat verliert die komplette Session.

**Repro:** `E14-offline-probe.gd` mit frischem `XDG_DATA_HOME`; zusätzlich
`timeout --signal=KILL 3s godot --headless --path /workspace/GOOBY-GODOT`.

**Evidenz:** `E14-probe-run1.log`, `E14-crash.log`, Verzeichnis `E14-crash-user/`.

### P1-2 — Reconnect-Flush verliert die spätere Dauer einer laufenden Analytics-Session

- `scripts/net/analytics.gd:124-126` flusht beim ONLINE-Status auch die **laufende** Session.
- Bei HTTP-Erfolg entfernt `scripts/net/analytics.gd:97-101` deren Outbox-Eintrag.
- Der nächste Heartbeat legt dieselbe `sessionId` mit neuerem `endedAt` erneut an
  (`scripts/net/analytics.gd:65-71`, `104-121`).
- Der Server verwirft dieselbe `sessionId` als Duplikat
  (`GOOBY-SERVER/src/analytics.js:63-70`), antwortet aber 200; der Client entfernt daraufhin auch
  den neueren Eintrag. Resultat: Nach Reconnect wird nur die erste Teildauer gezählt.
- Probe mit exakt dieser Server-Dedupe-Semantik:
  `posts=2 accepted=1 duplicates=1 outbox=0`, obwohl `second_ended > first_ended`.

**Evidenz:** `E14-analytics-idempotency.log`.

### P1-3 — Redeem-Outbox ist nur ein Test-Dummy; kein Produktions-Client existiert

- `scripts/net/outbox.gd:3-7` verspricht Analytics/Redeems, ist aber nur eine generische Queue.
- `scripts/net/net_client.gd:42-45` und `58-73` bauen ausschließlich Outbox, Presence, Friends und
  Analytics.
- Repo-Suche nach `api/codes/redeem`, `enqueue("redeem")`, `CODE_REDEEM` findet im Godot-Client
  keinen Produktionspfad; einzig `tests/unit/test_net_outbox.gd:11,40` legt künstliche
  `"redeem"`-Einträge an.
- Folglich gibt es weder Offline-Pufferung noch Reconnect-Flush noch Redeem-UI-Zustand.

**Repro**

```bash
rg -n 'api/codes/redeem|enqueue\("redeem"|CODE_REDEEM' GOOBY-GODOT
```

### P1-4 — Events-Pull/Push wird vom Client nicht konsumiert

- `scripts/net/net_client.gd:232-242` speichert WELCOME nur generisch und emittiert das Signal.
- Es gibt im Godot-Produktionscode keinen Leser von `pendingEvents` und keinen Consumer von
  `SERVER_EVENT`; nur GoobyPal und Friends hängen an `welcome_received`.
- Der Server markiert Pull-Events bereits beim Erzeugen von WELCOME als zugestellt
  (`GOOBY-SERVER/src/events.js:54-69,89-91`). Der Client ignoriert sie danach dauerhaft.
- Es existiert deshalb auch kein ruhiger Offline-Zustand/„zuletzt synchronisiert“-Hinweis.

**Repro**

```bash
rg -n 'SERVER_EVENT|pendingEvents|welcome_received' GOOBY-GODOT/scripts
```

### P1-5 — Presence-Service ist offline ruhig, aber im Produkt nie gesetzt

- `scripts/net/presence.gd:31-37` puffert offline korrekt nichts; Reconnect sendet den letzten Kind.
- Außer `tests/unit/test_net_presence.gd` gibt es jedoch keinen Aufruf von
  `presence.set_kind(...)` im Produkt. `current_kind` bleibt leer; Home/Stadt/Minigames melden
  keine Aktivität.

**Repro**

```bash
rg -n 'presence\.set_kind|Net\.presence|set_kind\(' GOOBY-GODOT/scripts
```

### P1-6 — Besuchs-REST hat keinen Timeout; partieller Serverausfall kann UI-Flows endlos warten lassen

- `scripts/social/visit_service.gd:252-259` erstellt `HTTPRequest`, setzt aber kein
  `request.timeout`, bevor auf `request_completed` gewartet wird.
- Darauf warten u. a. `scripts/ui/social/social_screen.gd:254-280` und
  `scripts/social/visit_scene.gd:301-310`. Bei offenem TCP/HTTP-Stall bleibt Besuch annehmen,
  Haus laden oder Besuch beenden unbegrenzt hängen.
- WS-Requests sind dagegen in `scripts/net/net_client.gd:145-166` auf 10 s begrenzt;
  Analytics und Update-HTTP setzen ebenfalls 10 s. Der Visit-REST-Pfad ist der Ausreißer.

## P2

### P2-1 — „Letzter Freunde-Cache“ überlebt keinen Offline-Neustart

`scripts/net/friends_service.gd:19-21` hält Freunde/Anfragen nur im Speicher; es gibt keinen
persistierten Cache. Offline zeigt die UI zwar ruhig den Leerzustand, aber nicht den im
Offline-first-Design versprochenen letzten Stand.

### P2-2 — Kaputte Outbox wird ohne Recovery vollständig verworfen

`scripts/net/outbox.gd:97-105` startet bei Parsefehler leer. Es gibt weder Backup noch Recovery
aus `.tmp`; damit ist „kein Datenverlust“ bei Dateikorruption nicht erfüllt. Der bestehende Test
bestätigt bewusst genau dieses Verhalten.

## P3

### P3-1 — Backoff-Deckel weicht von der bindenden 60-s-Vorgabe ab

`scripts/net/net_client.gd:20-21,263-269` deckelt bei 30 s statt der in
`docs/godot-rewrite/C-backend.md:414-415` festgelegten 60 s. Funktional arbeitet der Backoff,
er erzeugt langfristig aber doppelt so viele Connect-Versuche wie vorgesehen.

## Feature-Matrix ohne Server

| Feature | Ergebnis |
|---|---|
| NetClient | PASS: localhost-Fehler → OFFLINE, Request 0 ms; 1/2/4-s-Backoff + Jitter; Blackhole schließt nach ~5 s; kein Toast-/Log-Spam |
| Freunde | PASS standalone: grauer Offline-Chip, Hinweis, Add disabled |
| Besuche | PASS standalone: globaler Offline-Hinweis, Button disabled; P1 bei partiellem REST-Stall |
| GoobyPal | PASS UI: Button/Senden disabled, kein Fehler-Toast ohne Aktion |
| Brettspiel | PASS standalone: Button disabled; Service liefert OFFLINE sofort |
| Analytics | FAIL P1: Start-Crashverlust und Reconnect/Dedupe-Dauerverlust |
| Codes-Redeem | FAIL P1: Clientpfad/Outbox/Offline-UI fehlt |
| Events-Pull | FAIL P1: WELCOME-Daten werden ignoriert und serverseitig als zugestellt markiert |
| Presence | TEILWEISE: Offline ruhig/nicht gepuffert, aber keine Produktionsaufrufe |
| Boot/Save | Save PASS (100→107→114 über Offline-Neustarts); Spielbarkeit FAIL P0 |

## Positive Laufzeitevidenz

- 59 gezielte Net-/Outbox-/Analytics-/Presence-/Friends-/Visit-/GoobyPal-/Board-Tests:
  **59 PASS, 0 FAIL** (`E14-targeted-tests.log`). Diese Tests maskieren P1-1, weil
  `test_net_analytics.gd:97-100` korrekt `setup()` **vor** `add_child()` macht.
- Offline-Probe: Friends/Visit/Board/Pal jeweils synchron `OFFLINE` in 0 ms;
  Presence verändert Outbox-Größe nicht (`E14-probe-run1.log`, `E14-probe-run2.log`).
- Sauberer Offline-Neustart erhält abgeschlossene Analytics-Einträge; nach Run 2 lagen zwei
  Sessions in `user://outbox.json`.
- Standalone-UI/Gameplay: `06_friends_standalone_offline.png`,
  `07_social_standalone_offline.png`, `08_goobypal_standalone_offline.png`,
  `09_city_standalone_offline.png`. `10_minigame_standalone_offline.png` ist leer und bestätigt
  den 0×0-Host zusätzlich.
