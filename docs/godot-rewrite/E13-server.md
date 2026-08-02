# E13 — Server-Korrektheit & Limits (rein funktional)

## Verdict

**BEDINGT BESTANDEN.** Normale Kernflüsse und dokumentierte Limits funktionieren; keine P0.
Eine P1-Durability-Lücke verletzt jedoch bestätigte Einmaligkeit/Idempotenz nach einem
Prozessabsturz. Zusätzlich ist die robuste Fehlersemantik nicht für alle defekten Nachrichten
vertragstreu.

Scope: `/workspace/GOOBY-SERVER/**`, Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`), Node `v22.14.0`.
Keine Repo-Änderungen; Clients/Harnesses liegen nur unter `/tmp/gooby-godot/eval/`.

## Findings

### P0

Keine.

### P1-1 — Bestätigte Mutationen sind im 10-s-Write-behind-Fenster nicht crash-durable

`Storage.markDirty()` persistiert Collections erst beim periodischen `flush()` (Default 10 s).
Codes und Analytics antworten vorher erfolgreich. Ein Prozessabsturz nach der Antwort rollt den
Collection-Zustand zurück, obwohl JSONL bereits geschrieben sein kann.

Legitime Repro (`e13-crash-durability.mjs`):

1. Account und `CRASH26` (`maxUses=1`) normal anlegen; sauber stoppen.
2. Server starten; Code via `POST /api/codes/redeem` einlösen → `ok:true`.
3. Unmittelbar nach erhaltener Antwort Prozessabsturz simulieren; Server neu starten.
4. Derselbe Account löst denselben Code erneut ein → nochmals `ok:true`.
5. Analog: derselbe Analytics-`batchId`/`sessionId` wird vor und nach Restart jeweils mit
   `accepted:1, duplicates:0` bestätigt.

Damit sind „Redeem einmalig“ und Analytics-Idempotenz über einen normalen Crash hinweg falsch.
Das gemeinsame Muster betrifft potenziell auch `players` (Pal-Limit/Pending), Events und Houses.
Fix-Richtung: bestätigungsrelevante Zustände vor der Erfolgsantwort synchron atomar flushen oder
ein dauerhaftes Journal schreiben und beim Start replayen.

### P1-2 — GoobyPal/Events haben eine normale Disconnect-Zustelllücke

Code-Lektüre: `Hub.sendToDevice()` liefert `true`, sobald eine Connection im Map existiert, selbst
wenn `send()` wegen `readyState !== OPEN` nichts sendet. `PAL_SEND` legt nur bei `false` ein Pending
an; Events markieren dann ebenfalls `deliveredTo`. Außerdem werden `palPending` und Events bereits
beim Erzeugen von `WELCOME` als verbraucht markiert, ohne Client-Ack.

Legitime Repro-Bedingung: Empfänger beginnt einen normalen Disconnect, während der Freund
`PAL_SEND` sendet. Der Absender kann `PAL_RESULT ok:true` erhalten, während weder `PAL_RECEIVED`
ankommt noch `WELCOME.palPending` entsteht. Bei einem Coin-Transfer ist das eine P1-Datenverlustlücke.
Fix-Richtung: stabile Delivery-/Transfer-ID, persistentes Pending, Client-Ack + Dedupe; niemals
Socket-Queueing als Zustellbestätigung werten.

### P2-1 — Defekte Messages ergeben nicht immer den dokumentierten Fehler

Reproduziert über denselben normalen WS:

- `d:[]` mit gültigem `seq` → `ERROR BAD_MESSAGE`, aber ohne korrelierbares `re` (Vertrag:
  „mit `re` wenn korrelierbar“; `request()` kann dadurch timeouten).
- `SYNC {"coins":"not-a-number"}` → still verworfen, kein Fehler.
- `FRIEND_DECLINE {}`, `PROFILE_UPDATE {"name":42}`, `ROOM_LEAVE {}` → jeweils `OK` statt Fehler.
- Positiv: kaputtes JSON → `BAD_MESSAGE`; falscher Presence-Typ → `BAD_MESSAGE`; unbekannter Typ
  → `UNKNOWN_TYPE`; danach bleibt `PING/PONG` funktionsfähig. Kein Server-Crash.

Fix-Richtung: Typ-spezifische Schemas vor Dispatch und ein Parse-Ergebnis, das einen sicher
geparsten `seq` auch bei Payload-Fehlern für `re` erhält.

### P3-1 — Kleine Diagnose-/Recovery-Ungenauigkeiten

- `node --test` meldet 73 Tests, davon sind 72 echte `test(...)`-Fälle; `test/helpers.js` wird als
  eigener leerer Pass mitgezählt. Keine Skips/TODOs/immer-grünen Assertions gefunden.
- Bei kaputtem `players.json` bootet der Server und quarantänisiert die Datei als
  `.corrupt-*`; eine neue `players.json` entsteht erst nach der nächsten Mutation/Shutdown.
- Ohne Admin-Passwort antwortet das Panel korrekt 503, loggt aber zusätzlich irreführend
  „Webpanel aktiv“, bevor der Entry-Point „DEAKTIVIERT“ meldet.

## Ausgeführte Prüfung

### Test-Suite und Abdeckung

`node --test` dreimal:

| Lauf | Tests | Pass | Fail | Dauer |
|---|---:|---:|---:|---:|
| 1 | 73 | 73 | 0 | 3357 ms |
| 2 | 73 | 73 | 0 | 3494 ms |
| 3 | 73 | 73 | 0 | 3443 ms |

`node --test --experimental-test-coverage`: 95,56 % Lines, 85,10 % Branches,
90,93 % Functions. Die Tests enthalten substanzielle Assertions und echte Port-0-Server/WS/REST-
Interaktionen; keine `skip`, `todo`, `assert.ok(true)` oder leeren `*.test.js`.

### Kernflüsse gegen `W2c-protocol.md`

| Flow | Ergebnis |
|---|---|
| HELLO/WELCOME/TOFU | PASS |
| Friend request → accept → list | PASS |
| Presence-Label + Push | PASS |
| GoobyPal 100+100+50; weitere 1 | PASS: 250, dann `DAILY_LIMIT` |
| Analytics gleicher Batch + Session | PASS ohne Crash |
| Code-Redeem zweimal | PASS ohne Crash: `ALREADY_REDEEMED` |
| Event offline → WELCOME-Pull | PASS |
| House PUT/GET + Visit READY/Room/End | PASS |
| Battleship Turn/`n`/SHOT_RESULT | PASS |
| Tomate zweimal in Runde | PASS: zweite `TOMATO_LIMIT` |

Harness: `/tmp/gooby-godot/eval/e13-functional.mjs`.

### Panel und Persistenz

Der echte Entry-Point lief als
`PORT=0 DATA_DIR=<temp> env -u GOOBY_ADMIN_PASSWORD node GOOBY-SERVER/server.js`:
`GET /health` → 200; `GET /panel/` → 503. Sechs Collection-Snapshots waren nach sauberem
Stop parsebar; keine `.tmp-*`-Leichen. Ein absichtlich halb geschriebenes `players.json` führte
zu erfolgreichem Boot/Health, `.corrupt-*`-Quarantäne und anschließend wieder parsebarem Zustand.

## Offline-first

Der bindende „Server-Ausfall blockiert Client nie“-Vertrag ist client-seitig und wird an E14
verwiesen. E13 bewertet nur die Serverreaktion/Persistenz.
