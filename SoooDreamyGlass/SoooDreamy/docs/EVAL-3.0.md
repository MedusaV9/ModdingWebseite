# SoooDreamy 3.0 — unabhängige Evaluation

**Stand:** 8. August 2026  
**Bewerteter Branch:** `cursor/sodreamy-2-0-d1d8`  
**Ausgangs-HEAD:** `de76aab06`  
**Scope:** 2.0 + 3.0, Schwerpunkt 3.0; Code und Historie seit `1e67e8780`  
**Änderungsdisziplin:** Für diese Evaluation wurde kein Produktcode geändert.

## Kurzurteil

**Nicht „glücklich“ — vor 4.0 ist eine 3.0.1-Integrationswelle nötig.**

3.0 enthält viel echte, gut getestete Substanz: Die Ritual-Kette funktioniert
serverseitig, sieben neue Spiele haben überwiegend saubere pure Reducer, die
rückwirkende Level-Baseline ist fair, und die Delight-Engine ist breit in A und
B eingesetzt. Die gemeldeten 191 Server- und 161 Swift-Logic-Tests sind lokal
reproduzierbar.

Als gemeinsames Paar-Release ist 3.0 aber noch nicht rund. Die drei Wellen
berühren sich oft nur an einem Event oder an Dokumentation:

1. Film-Roulette erzeugt ein `movie_match`, aber weder Wochenplan noch Momente
   konsumieren es; trotzdem behauptet die UI, der Filmabend sei gespeichert.
2. `goal`, `partner.energy` und `level` erreichen die Widgets nicht
   end-to-end; selbst die vorhandenen Level-Felder werden von keinem Widget
   gerendert.
3. Die Fairness-Aussage „kein Client kann seinen Seed wählen“ ist falsch.
   Client-Seeds werden ausdrücklich beibehalten.
4. Game-App-Events sind nicht aus gültigem Spielzustand abgeleitet. Ein Client
   kann ein Film-Match erfinden und denselben Quest-Haken mehrfach als XP-Event
   verbuchen.
5. Bestandspaare bekommen für die mehr als 20 neuen Funktionen keine
   Entdeckungsreise; gleichzeitig ist das Dashboard deutlich überladen.

## Bewertung

| Bereich | Note | Begründung |
|---|---:|---|
| Rituale & Beziehung | **7,4 / 10** | Starke Server-Kerne und gute Paar-Ideen; zwei Top-10-Ideen fehlen, Kapsel-/Widget-/Cross-Feature-Flows sind unvollständig. |
| Spiele | **7,2 / 10** | Große spielbare Breite und gute Reducer; Seed-Vertrag, Event-Fairness, Saison-Vollständigkeit und Replay-Versprechen haben Lücken. |
| Gamification / Plattform | **7,6 / 10** | Retro-Baseline, Level, Badges, Delight, Duett und Date Night sind substanziell; Widget-Ausgabe, Zeremonie-Queue und Controls-Scope bleiben offen. |
| Integration A×B×C | **5,5 / 10** | Events existieren, aber mehrere zentrale End-to-End-Ketten enden vor dem sichtbaren Paar-Nutzen. |
| Server-Qualität | **7,7 / 10** | 191 grüne E2E-Tests, gute Abwärtskompatibilität und Redaction; das regelagnostische Relay vertraut sicherheitsrelevanten Client-Behauptungen. |
| UX-Kohärenz | **6,2 / 10** | Einzelne Screens sind liebevoll; Feature-Discovery, Dashboard-Hierarchie und Zeremonie-Orchestrierung sind nicht releaseweit gelöst. |
| Testtiefe | **7,8 / 10** | Sehr gute API-/Reducer-Breite; keine SwiftUI-/Widget-End-to-End-Tests und wichtige Negativfälle fehlen oder sind als falscher Vertrag festgeschrieben. |

Da mindestens eine Note unter 8 liegt, gilt die vereinbarte
„glücklich“-Schwelle nicht als erreicht.

## Nachprüfung der gemeldeten Qualität

### Lokal reproduziert

| Prüfung | Ergebnis |
|---|---|
| `cd SoooDreamy/server && npm install && npm test` | **191/191 bestanden**, 0 Fehler |
| `cd SoooDreamy/ios && swift test` | **161/161 bestanden**, 0 Fehler |
| Eigener L10n-Audit über alle sechs Tabellen | **1.648 Keys**, 0 leere DE-Werte, 0 leere EN-Werte, 0 tabellenübergreifende Duplikate |
| Eigene Live-Smokes | Ritual-, Parallelspiel-, Commit-Reveal-, Gamification-, Retro-Baseline- und Saison-Ketten ausgeführt; Details unten |

Die normale `L10nUsageTests`-Suite prüft verwendete Keys bereits gegen alle
Tabellen. Der einfachere Tabellen-Paritätstest in `ios/LogicTests/L10nTests.swift`
nimmt `RitualsL10n` und `PlatformL10n` dagegen nicht auf. Der zusätzliche Audit
hat diese Lücke für die Evaluation geschlossen; der dauerhafte Test sollte die
beiden Tabellen ebenfalls enthalten.

### CI und iOS-Build

Das GitHub-Billing-Limit ist **kein Codefehler** und senkt keine Note.

- Run [31281428017](https://github.com/MedusaV9/CustomServerPrivate/actions/runs/31281428017)
  war erfolgreich: Server-Tests, Swift-Logic, unsignierter iOS-Build,
  IPA-Paket und Artifact-Upload grün.
- Run [31282147674](https://github.com/MedusaV9/CustomServerPrivate/actions/runs/31282147674)
  hatte erneut grüne Server-, Swift-Logic- und Unsigned-IPA-Jobs. Nur der
  best-effort Rolling-Prerelease-Job scheiterte; der Workflow blieb insgesamt
  erfolgreich.
- Die danach blockierten Läufe starteten wegen des Account-Billing-Limits
  nicht. Auf Linux ist kein eigener Xcode/iOS-Build möglich. Die aktuelle
  Swift-Bewertung beruht deshalb wie beauftragt auf den zwei letzten grünen
  macOS-Builds, Linux-Logic-Tests und Code-Review.

## Eigene Live-Smokes

Die Smokes liefen gegen einen echten lokalen HTTP-Server mit zwei frisch
gekoppelten Mitgliedern. Temporäre Testskripte lagen ausschließlich unter
`/tmp` und wurden nicht committet.

### A. Ritual-Kette

| Probe | Ergebnis |
|---|---|
| Erstes Audio-Memo | Partner sieht `partnerRecorded: true`, aber keinen Blob: Anti-Spoiler **grün** |
| Zweites Audio-Memo | Beide Seiten sehen danach das Partner-Memo: Reveal **grün** |
| Zeitkapsel vor `unlockAt` | `409 still_locked`, Inhalt weiter redigiert: **grün** |
| Zeitkapsel nach `unlockAt` | Öffnen erfolgreich, Text exakt zurückgegeben: **grün** |

API-Dokumentation und Implementierung widersprechen sich beim Fehlercode:
`docs/API.md` nennt `still_sealed`, der Server und sein Test verwenden
`still_locked`.

### B. Spiele-Integration und Fairness

| Probe | Ergebnis |
|---|---|
| Battleship + Kniffel parallel | Beide IDs gleichzeitig in `GET /api/games/open`: **grün** |
| Server injiziert fehlenden Kniffel-Seed | Integer-Seed vorhanden und beim Partnerabruf identisch: **grün** |
| Kniffel-Determinismus | Linux-Test `testPipsAreDeterministicAndInRange` grün; Seed auf beiden API-Sichten identisch |
| Manipulierter Battleship-Reveal | Server speichert `verified: false`: **grün** |
| Client sendet `payload.seed = 7` | Server übernimmt **7**: **rot gegen Release-Vertrag** |
| Erfundenes Film-Match | Ein beliebiges `match`-Objekt erzeugt `movie_match`: **rot** |
| Derselbe Quest-Haken zweimal | Zwei `quest_done`-Events werden gespeichert: **rot** |

Der positive Commit-Reveal-Helfer macht genau, was er verspricht: Er
zertifiziert nachträglich, ob Reveal und Commit zusammenpassen. Er beweist
jedoch nicht, dass ein Move nach den Spielregeln zulässig ist. Das ist für ein
regelagnostisches Relay akzeptabel, darf aber nicht mit serverseitiger
Spiel-Fairness gleichgesetzt werden.

### C. Gamification und rückwirkende Fairness

Im frischen Paar stieg der Stand durch reale A-Aktionen:

- vor Bedürfnis: **55 XP**, Level 1, davon 55 Event-XP;
- nach `need_sent`: **58 XP**, Level 1;
- nach Zielanlage und 100-%-Beitrag: **139 XP**, Level 2;
- `first_touch` wurde nach einer Berührung freigeschaltet.

Für eine simulierte einjährige Bestandsbeziehung mit 500 historischen
Nachrichten:

- erste Adoption: **1.001 XP, Level 5**, **keine** Level-/Badge-Zeremonie;
- spätere neue Aktivität: **1.602 XP, Level 6**, live ein `level_up` auf 6.

Damit ist die behauptete rückwirkende Baseline **grün**: Geschichte zählt,
ohne beim Update Zeremonien-Spam auszulösen.

### D. Turnier-/Saison-Ableitung

Drei beendete Sessions wurden über die gespeicherten `result.scores`
ausgewertet:

- Battleship: Mitglied A gewinnt → 3 Punkte A;
- Kniffel: Mitglied B gewinnt → 3 Punkte B;
- Zwei Wahrheiten: Remis → je 1 Punkt.

Ergebnis **4:4**, identisch zur 3/1-Regel: die einfache Ableitung ist **grün**.
Die Produktbehauptung „über ALLE Spiele“ ist trotzdem zu weit: Der Client lädt
nur die letzten 100 Relay-Sessions, zählt nur Sessions mit
`result.scores` und bindet die separate Wordle-History nicht ein.

## Integrations-Audit A×B×C

### App-Events → XP / Badges

Alle **tatsächlich emittierten** A-Events besitzen explizite XP-Werte:
`daymemo_first`, `daymemo_both`, `capsule_sealed`, `capsule_opened`,
`need_sent`, `goal_created`, `goal_milestone`, `goal_reached`,
`weekplan_slot_created`, `magazine_seen_both`.

Die B-/C-Typen `movie_match`, `quest_done`, `icon_gift_sent` und
`datenight_planned` sind nicht verwaist, werden aber nur über den generischen
Default von 5 XP konsumiert. Das funktioniert technisch, ist aber kein
expliziter, reviewbarer Produktvertrag.

Die Dokumentation nennt zusätzlich Ereignisse, die so nicht existieren:

- `daymemo_streak` ist dokumentiert, wird aber nicht emittiert;
- `goal_completed` heißt im Code `goal_reached`;
- `weekplan_slot` heißt im Code `weekplan_slot_created`.

### Film-Roulette → Wochenplan

**Nicht verdrahtet.** `MovieRouletteView.swift` annotiert den abschließenden
Swipe, `server/src/router.js` erzeugt daraus `movie_match`, und
`server/src/events.js` speichert das Event. Danach endet die Kette:

- `WeekplanView.swift` reagiert nur auf Wochenplan-CRUD-Events;
- es gibt keinen Listener/Fetcher für `movie_match`;
- es gibt keinen 1-Tap-CTA, der `POST /api/events` oder einen Film-Slot
  aufruft.

Die UI-Zeile „als Filmabend-Moment gespeichert“ und `docs/API.md` behaupten
damit mehr als die Implementierung.

### Delight in A/B

**Grün.** Es gibt 20 Aufrufe von `Delight.celebrate` in Feature-Code, unter
anderem in Daymemo, Kapseln, Ziele, Battleship, Montagsmaler, Kniffel,
Film-Roulette, Stadt-Land-Fluss, Zwei Wahrheiten, Tagesquests und Turnier.
Das ist echte Wiederverwendung und keine isolierte C-Demo.

### Widget-Snapshot

**End-to-end rot für alle drei ausdrücklich geforderten Felder.**

- Der Server liefert `goal`, `partner.energy` und `level`.
- `WidgetSnapshotResponse` in `Core/Models.swift` bildet keines dieser
  v3-Felder ab; der vorhandene API-Call wird im Refresh-Pfad nicht verwendet.
- Die App-Group-Struktur `WidgetSnapshot` besitzt nur Level-Felder, keine
  Ziel- oder Energie-Felder.
- `AppState.updateWidgetSnapshot()` befüllt die Level-Felder aus
  `GET /api/level`.
- Kein Swift-Widget liest oder rendert `levelNumber` oder `levelProgress`.

Das Serverfeld ist also korrekt getestet, aber der sichtbare Nutzerweg endet
vor dem Widget.

### Inbox-Buckets

- `games`: **sichtbar** als Play-Tab-Badge und als Chip in „Während du weg
  warst“; im Play-Hub werden wartende Sessions markiert.
- `needsForMe`: **dekodiert, aber vom Digest ignoriert**. Es fehlt in
  `InboxResponse.total/isEmpty`, in den Digest-Chips und in der
  Tap-Navigation. Ein reines Need-Digest kann deshalb als „leer“ verworfen
  werden. Die Dashboard-`NeedsCard` kompensiert das mit einem separaten
  `GET /api/needs`, sodass ein offenes Bedürfnis meist trotzdem erscheint —
  aber nicht durch die versprochene Inbox-Integration.

## iOS-Code-Review der acht Stichproben

| System | Befund |
|---|---|
| `DaymemoView` | Gute Anti-Spoiler-Darstellung und Wiederverwendung des Recorders. Aufnahme wird bei `onDisappear` gecancelt, der Audio-Session-State zurückgesetzt; Uploadfehler bleibt retryfähig. AVAudio/SwiftUI konnte auf Linux nicht runtime-getestet werden. |
| `CapsulesView` | Redaction und Zeremonie sind sauber. Die Karte zeigt nur ein Datum, keinen tickenden Countdown. `canOpen` hängt an einem beim letzten Fetch berechneten `unlocked`; wenn `unlockAt` bei offenem Screen verstreicht, erscheint der Öffnen-Button erst nach Pull-to-refresh/Neuladen. |
| `LevelCard` + Zeremonien | Ring, Shelf und Retro-Adoption sind gut. `levelUpCeremony` und `badgeCeremony` sind einzelne optionale States, keine Queue. Mehrere Badges überschreiben einander; während Level-Up hat nur der zuletzt geschriebene Badge eine Chance. |
| iOS-18-Controls | `@available(iOS 18.0, *)` und Bundle-Guards sind korrekt. Gebaut sind Herzklopfen und „Bedürfnis öffnen“. Die Top-10-Spezifikation verlangte Herzklopfen, „Denk an dich“-Toggle und Date-Night-Start; zwei davon fehlen, eines wurde ersetzt. |
| Date-Night-Live-Activity-Intent | Sauber in Shared-Code gekapselt und ohne APNs nutzbar. Der Intent aktualisiert die lokale Phase optimistisch und ignoriert Fehler/Status der Serverantwort; bei Netzfehler kann das Paar vorübergehend verschiedene Phasen sehen. |
| Saison-Partikel | Deterministische 16 Partikel in einem Canvas-Pass bei 20 Hz, Reduce-Motion-Fallback und kein Per-frame-Array-Aufbau: vernünftig. Die in der Idee versprochenen Low-Power-/Geräte-Dichte-Gates sind nicht implementiert. |
| Polaroid-Widget | Speicherschonendes Downsampling auf 800 px, Offline-Cache und drei rein gezeichnete Rahmen sind gut. „Filmstrip“ rahmt nur dasselbe einzelne Foto; Mehrfoto-Filmstreifen, Datumsstempel und Passbildautomat aus der Idee fehlen. |
| Replay-Scrubber | Reihenfolge, Task-Cancel, Zeitraffer, Scrubber und Live-Feed sind vorhanden. Es läuft jedoch ein lokalisiertes Move-Protokoll ab; die Spiel-Reducer werden nicht schrittweise in echte Boards/Würfel/Zeichnungen gerendert. „Partie als Film“ ist daher überzeichnet. |

## Paar-Sicht

### Was als Paar bereits überzeugt

- Audio-Check-in und Zeitkapsel haben eine klare emotionale Dramaturgie.
- Need-Button und Energie-Ampel lösen echte Alltagsprobleme mit wenig Reibung.
- Parallel laufende Async-Spiele passen gut zur Sideload-/No-Push-Realität.
- Retro-Level anerkennt eine bestehende Beziehung statt bei null zu starten.
- Delight ist konsistent genug, dass A, B und C nach derselben App wirken.

### Wo sich 3.0 noch wie drei Wellen anfühlt

1. **Bestandspaare entdecken nichts geführt.** Die Erste-Woche-Quest ist
   absichtlich nur für neue Paare sichtbar. Ein Paar mit zwei Jahren Historie
   bekommt Level und Badges, aber keinen „Neu in 3.0“-Pfad zu Kapseln, Woche,
   Spielen, Duett und Date Night.
2. **Das Dashboard hat keine Hierarchie.** In fester Reihenfolge konkurrieren
   Inbox, Monatstag, Partner, Quest, Herz, Touch-Grid, Tagesfrage, Level,
   Date Night, Check-in, Hugs sowie vier Ritual-Karten um Aufmerksamkeit.
   Es gibt weder Einklappen noch Priorisieren noch den in der Ideenliste
   vorgesehenen Layout-Editor.
3. **Zeremonien konkurrieren.** Level-Up, Badge, Icon-Geschenk,
   Delight-Overlay, eingehende Touches und Toasts besitzen verschiedene
   `zIndex`-Ebenen, aber keine gemeinsame Queue. Ein produktiver Paarmoment
   kann damit mehrere Feiern gleichzeitig auslösen oder verschlucken.
4. **Cross-Feature-Versprechen enden unsichtbar.** Das Film-Match wird nicht
   zum Filmabend, Ziele/Energie/Level nicht zum Widget, und der Needs-Inbox-
   Bucket nicht zum Digest.

Das Release braucht nicht weniger Features, sondern eine klare
„Was ist jetzt für uns wichtig?“-Schicht.

## Vollständigkeit gegen die drei Top-10-Listen

Legende: ✅ substanziell umgesetzt · △ vorhanden, aber relevantes Scope- oder
Integrationsdefizit · ❌ nicht gefunden

### A — Beziehung & Alltag

| # | Top-10-Idee | Status | Befund |
|---:|---|:---:|---|
| 1 | Audio-Check-in | ✅ | Anti-Spoiler, Streak, Verlauf, Re-Recording, Dashboard |
| 2 | Zeitkapsel-Briefe | △ | Text/Foto, Server-Lock und Zeremonie; kein Voice-Payload, Countdown oder zeitgesteuertes UI-Refresh |
| 3 | Bedürfnis-Knopf | ✅ | Signal, Antwort, Verlauf, Dashboard; Inbox-Anbindung unvollständig |
| 4 | Gemeinsame Ziele | △ | Beiträge/Meilensteine gut; keine Bucket-List-Übernahme und kein sichtbares Widget |
| 5 | Wochenplan | ✅ | Verfügbarkeiten, Überschneidungen, einmalige/wöchentliche Slots; Film-Hook fehlt |
| 6 | Aussprache-Modus | ❌ | Kein geführter Konflikt-/Spiegel-/Friedensprotokoll-Flow gefunden |
| 7 | Meilenstein-Feiern & Badge-Album | △ | 20 Badges und Zeremonien vorhanden; keine kommenden Meilenstein-Teaser, Queue fehleranfällig |
| 8 | Energie-Ampel | △ | 12-h-TTL und Dashboard vorhanden; Widget fehlt |
| 9 | Rücksicht-Radar | ❌ | Kein granularer Opt-in-Zyklus-/Schmerz-/Vault-Flow gefunden |
| 10 | Monats-Magazin | △ | Aggregation, Archiv und Lesebestätigung vorhanden; Share/Export aus der Idee fehlt |

### B — Spiele & Aktivitäten

| # | Top-10-Idee | Status | Befund |
|---:|---|:---:|---|
| 1 | Turnier & Saison | △ | 3/1-Ableitung korrekt; nur letzte 100 scorebasierte Relay-Games, ohne Wordle |
| 2 | Montagsmaler | ✅ | Live-Zeichnen, Timer, Rollen, Punkte, DE/EN |
| 3 | Schiffe versenken | ✅ | Reducer, Commit-Reveal und `verified:false` bei Fälschung funktionieren |
| 4 | Film-Roulette | △ | Swipe/Match funktioniert; Filmabend-Übernahme fehlt und Event ist client-fälschbar |
| 5 | Kniffel | △ | Deterministische Würfel/Block gut; Server akzeptiert frei gewählten Client-Seed |
| 6 | Advents-/Countdown-Kalender | ❌ | Kein Kalender-/Türchen-System gefunden |
| 7 | Paar-Tagesquests | △ | Deterministisches Deck/UI vorhanden; doppelte Haken erzeugen doppelte XP-Events, Erfüllung wird nicht aus realen Feature-Events erkannt |
| 8 | Stadt-Land-Fluss | ✅ | Commit/Reveal, Bewertung, Letter-Check und Punkte vorhanden |
| 9 | Zwei Wahrheiten, eine Lüge | ✅ | Drei-Move-Runden, Rollenwechsel und verifiziertes Reveal vorhanden |
| 10 | Replay & Zuschauer | △ | Scrubber und Read-only-Live-Feed vorhanden; keine animierte Spielzustands-Wiedergabe |

### C — Plattform & Delight

| # | Top-10-Idee | Status | Befund |
|---:|---|:---:|---|
| 1 | Delight-Engine | ✅ | Zentraler Host, drei Intensitäten, breite A/B-Nutzung |
| 2 | Beziehungs-Level | △ | XP/Retro/Level-Zeremonie gut; Level-Widget fehlt sichtbar |
| 3 | Abzeichen | ✅ | 20 Stück, vier geheim, persistente Freischaltung, Shelf |
| 4 | App-Icon-Geschenke | ✅ | Neun Varianten, Relay und Auspack-Flow |
| 5 | iOS-18-Controls-Familie | △ | Guards korrekt; nur 1/3 der spezifizierten Controls, plus Ersatz „Need öffnen“ |
| 6 | Haptik-Duett + Live-Herzschlag | ✅ | Clock-Sync, gemeinsamer Start und Tap-Relay vorhanden |
| 7 | Date-Night-Live-Activity | ✅ | Planung, drei Phasen, Intent-Button und lokaler LA-Flow |
| 8 | Saison-Themes + Partikel | △ | Dashboard/Themes vorhanden; Low-Power-/Dichte-Regeln und saisonale Widget-Skins fehlen |
| 9 | Polaroid-Foto-Widgets | △ | Drei Rahmen vorhanden; Mehrfoto-/Datum-/Passbild-Varianten fehlen |
| 10 | Erste-Woche-Quest | ✅ | Sieben Schritte, +150 XP, Badge, nur für neue Paare wie spezifiziert |

## Priorisierte 3.0.1-Fix-Queue

### P0 — Release-Verträge und echte Cross-Wave-Ketten

| Problem | Beleg | Vorschlag | Primäre Dateien |
|---|---|---|---|
| Seed-Fairness ist falsch beschrieben und implementiert | Live-Probe `payload.seed=7` bleibt 7; bestehender Test fordert sogar „keeps a client-provided one“ | Für zufallsabhängige Typen Client-Seed ignorieren/überschreiben; optional nur in explizitem Test-/Replay-Modus zulassen. Negativtest auf nicht wählbaren Seed. | `server/src/router.js`, `server/test/games_v3.test.js`, `docs/API.md` |
| `movie_match` und `quest_done` vertrauen beliebigen/duplizierten Moves | Erfundenes Match → 1 Event; identischer Quest-Haken zweimal → 2 Events und damit Default-XP | Events aus validierter kanonischer Transition ableiten; Idempotenzschlüssel pro `gameId+cardIndex` bzw. `gameId+questIndex`; Tests für Fälschung/Duplikat. | `server/src/router.js`, `server/test/games_v3_games.test.js`, `server/src/gamification.js` |
| Film-Roulette endet vor Wochenplan/Moment | Kein Konsument in `WeekplanView`; dokumentierter 1-Tap-Flow fehlt | Im Match-Overlay echten CTA „Filmabend planen“ anbieten und per API Event oder Weekplan-Slot anlegen; erst nach Erfolg „gespeichert“ anzeigen. | `ios/SoooDreamy/Features/Games/MovieRouletteView.swift`, `ios/SoooDreamy/Features/Rituals/WeekplanView.swift`, `ios/SoooDreamy/Core/API.swift` |
| Widget-Felder sind nur serverseitig | Kein Widget liest Ziel, Energie oder Level; Clientmodell verwirft Server-v3-Felder | Response-Modell, App-Group-Snapshot und mindestens ein sichtbares Widget/Widget-Layout um alle drei Felder erweitern; Decoder-/Snapshot-/Rendering-Tests hinzufügen. | `ios/SoooDreamy/Core/Models.swift`, `ios/Shared/SharedBridge.swift`, `ios/SoooDreamy/App/AppState.swift`, `ios/Widgets/` |

### P1 — Paar-UX, Datenvollständigkeit und Zustandsfehler

| Problem | Beleg | Vorschlag | Primäre Dateien |
|---|---|---|---|
| Zeremonien sind keine Queue | Einzelne optionale States; mehrere Badge-Events überschreiben sich | Ein gemeinsames FIFO aus Level, Badge, Icon und wichtigen Ritual-Feiern; genau ein Modal, Abschluss zeigt das nächste. | `ios/SoooDreamy/App/AppState.swift`, `ios/SoooDreamy/App/AppStatePlatform.swift`, `ios/SoooDreamy/App/RootView.swift` |
| Zeitkapsel wird auf offenem Screen nicht automatisch öffnbar | `canOpen` nutzt stale `capsule.unlocked`; kein Timeline-Countdown | Countdown aus `unlockAt` lokal rendern; beim Grenzübertritt gezielt reloaden und Button freigeben; Foreground-Refresh. | `ios/SoooDreamy/Features/Rituals/CapsulesView.swift` |
| Saison ist nicht „über alle Spiele“ | `limit:100`, nur `result.scores`, keine Wordle-History | Paginierten/aggregierten Server-Endpunkt oder vollständige Quellen inklusive Wordle verwenden; Vertrag und UI klar auf kompetitive Spiele begrenzen, falls gewollt. | `ios/SoooDreamy/Features/Games/TournamentView.swift`, `server/src/router.js`, `docs/API.md` |
| Replay ist ein Eventlog, kein Zustandsfilm | Player rendert `Step`-Zeilen statt Reducer-States | Pro Game-Typ Replay-Adapter, der den pure Reducer bis Index N ausführt und das echte Board rendert; bis dahin UI/Changelog in „Zugprotokoll“ umbenennen. | `ios/SoooDreamy/Features/Games/ReplayView.swift`, `ios/SoooDreamy/Content/ReplayLogic.swift` |
| Bestandspaare haben keine 3.0-Entdeckung; Dashboard ist fest überladen | Quest nur bei `isNewCouple`; 15+ feste Karten/Blöcke | Separate „Neu in 3.0“-Quest für Bestandsbeziehungen; Dashboard-Sektionen priorisieren/einklappen und lokale Reihenfolge/Verbergen erlauben. | `ios/SoooDreamy/Features/Home/QuestCard.swift`, `ios/SoooDreamy/Features/Home/DashboardView.swift`, `ios/SoooDreamy/Features/Rituals/RitualsDashboardSection.swift` |
| `needsForMe` ist im Digest praktisch unbenutzt | Nicht in `total/isEmpty`, keine Chip-/Tap-Behandlung | `needsCount/openNeed` in Digest-Semantik aufnehmen; Need-Chip direkt zur Need-Karte/History führen; separaten Fetch nur als Fallback behalten. | `ios/SoooDreamy/Core/Models.swift`, `ios/SoooDreamy/App/AppState.swift`, `ios/SoooDreamy/Features/Home/DashboardView.swift` |
| API-Dokumentation widerspricht dem Server | `still_sealed`, `daymemo_streak`, `goal_completed`, `weekplan_slot` und Movie-CTA stimmen nicht | Dokumentation aus tatsächlichen Event-Konstanten/Tests synchronisieren; Contract-Test, der dokumentierte Eventtypen mit Export/Registry vergleicht. | `docs/API.md`, `server/src/events.js`, `server/test/rituals.test.js` |

### P2 — Scope-Schluss und Robustheit

| Problem | Beleg | Vorschlag | Primäre Dateien |
|---|---|---|---|
| Controls-Top-10 nur teilweise erfüllt | Herzklopfen + Need statt Herzklopfen + Thinking + Date Night | Thinking-Control und Date-Night-Control ergänzen oder die Top-10-/Release-Aussage explizit auf zwei Controls reduzieren. | `ios/Widgets/ControlWidgets.swift`, `ios/Widgets/WidgetsBundle.swift` |
| Date-Night-Intent kann lokal/serverseitig auseinanderlaufen | Lokale Phase wird vor unvalidiertem best-effort POST gesetzt | HTTP-Status prüfen; bei Fehler lokale Phase zurücksetzen/als ausstehend markieren; beim nächsten App-Open Server als Quelle abgleichen. | `ios/Shared/DateNightActivity.swift`, `ios/SoooDreamy/Core/DateNightActivityController.swift` |
| Saison-Partikel ignorieren versprochene Energie-Gates | 20-Hz-Timeline unabhängig von Low Power Mode/Geräteklasse | Low-Power-/ScenePhase-Pause und einfache Dichteklasse ergänzen; Instruments auf einem echten Gerät nach 3.0.1 prüfen. | `ios/SoooDreamy/UI/SeasonEffectsView.swift` |
| Dauerhafte L10n-Parität deckt neue Tabellen nicht direkt ab | `L10nTests.swift` listet nur vier Tabellen; eigener Audit aller sechs ist grün | `RitualsL10n` und `PlatformL10n` in den regulären Tabellen-Test aufnehmen. | `ios/LogicTests/L10nTests.swift` |

## Freigabeempfehlung

Die Kernsysteme müssen nicht zurückgebaut werden. 3.0.1 sollte zuerst die vier
P0-Verträge schließen und danach Zeremonie-Queue, Kapsel-Zeitwechsel,
Bestandspaar-Discovery und Saison-/Replay-Ehrlichkeit liefern. Erst dann ist
die Release-Erzählung „alles greift ineinander“ durch sichtbare Paar-Flows
gedeckt und eine 4.0-Welle sinnvoll.
