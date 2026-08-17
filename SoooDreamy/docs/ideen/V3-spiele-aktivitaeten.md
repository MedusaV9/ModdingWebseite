# V3-Ideen — Lens „Spiele & gemeinsame Aktivitäten"

Ideensammlung für SoooDreamy 3.0 → 4.0 → 5.0 (Ideen-Agent 2/3).
Fokus: Realtime-Paar-Spiele + gemeinsame Aktivitäten.

**Architektur-Grundlage (2.0, siehe `docs/API.md`):** Alle Live-Spiele laufen
über das generische Move-Relay — `POST /api/games {type, payload}` →
`POST /api/games/:id/join` → `POST /api/games/:id/move {data}` →
`POST /api/games/:id/end {result}`, mit den WS-Events
`game_created / game_started / game_move / game_ended`. Beide Handys leiten
den **identischen Spielstand deterministisch** aus `payload` (inkl. Seed) +
geordneter Zugliste ab (Muster: `CoupleGamesLogic.swift` — pure Reducer,
ungültige/doppelte Züge werden defensiv **übersprungen**, nie zum Fehler).
Zufall kommt IMMER als Seed aus dem Payload (`seededShuffled`), nie aus der
OS-Uhr; wo Reihenfolge zählt (Buzzer), entscheidet die **Server-Reihenfolge**
der Move-Liste (Quiz-Duell-Muster).

**Sideload-Realität:** Kein Remote-Push. WS ist nur live, solange die App
offen ist. Konsequenz für V3: Jedes neue Spiel gehört in eine von zwei
Klassen — **„Live"** (beide gleichzeitig online, Lobby wartet auf `join`)
oder **„Async"** (Züge persistieren auf dem Server, der Partner sieht beim
nächsten App-Öffnen „Du bist dran!"). Async-Spiele sind auf Sideload sogar
die STÄRKERE Klasse, weil sie keine Verabredung brauchen.

---

## Infrastruktur-Voraussetzungen für V3 (einmal bauen, alle Ideen profitieren)

1. **Parallele Sessions:** `POST /api/games` beendet heute jede vorherige
   nicht-beendete Partie. Async-Spiele (Schiffe versenken, Kniffel, Dame …)
   brauchen mehrere offene Sessions gleichzeitig (z. B. 1 pro `type`).
2. **„Du bist dran"-Digest:** `GET /api/inbox` um einen `games`-Bucket
   erweitern (`{count, awaitingMe:[{gameId, type}]}`), damit App-Öffnen ohne
   Push sofort zeigt, wo man am Zug ist — plus Badge im Spiele-Tab.
3. **Server-Seed:** Der Server generiert beim `game_created` einen Seed im
   Payload (statt Client), damit kein Client den Shuffle „aussuchen" kann.
4. **Commit-Reveal-Konvention:** Für Spiele mit versteckter Information
   (Schiffe versenken, Zwei Wahrheiten, Schere-Stein-Papier) als Move-Muster:
   erst `{commit: sha256(geheimnis + salt)}`, am Ende `{reveal: geheimnis,
   salt}`; der Gegner-Client verifiziert den Hash. Reine Client-Konvention,
   Server bleibt dumm — passt perfekt zum bestehenden Relay.
5. **Foto-/Audio-Anhänge an Züge:** Beweis-Fotos & Karaoke-Clips laufen über
   die bestehende Galerie/Voice-Infrastruktur; Move-`data` referenziert nur
   `photoId`/Message-Id. Optional V3-Server: `album`-Konvention
   („🎮 Fotosafari") damit Spiel-Fotos die Galerie nicht fluten.

---

## A. Brett- & Denkspiel-Klassiker

### 1. Schiffe versenken 💥
- **Konzept:** Der Klassiker als Paar-Duell: Flotte auf 10×10 platzieren,
  abwechselnd schießen, Treffer-Animationen mit Haptik (Wasserplatscher vs.
  Explosion aus der Sound-Engine). Läuft wahlweise live oder async über Tage.
- **Multiplayer-Mechanik:** Commit-Reveal: Move 1 je Spieler =
  `{commit: hash(layout+salt)}`. Danach abwechselnd `{shot:{x,y}}`, der
  Beschossene antwortet `{result:"hit"|"miss"|"sunk", shipId?}` (sein Client
  wertet lokal gegen sein Layout aus). Endet die Partie, folgt
  `{reveal: layout, salt}` — der Gegner-Client verifiziert den Hash und
  deckt Lügen auf. Reducer skippt Schüsse außerhalb der Reihenfolge.
- **Aufwand:** M · **Score:** 9

### 2. Kniffel — Liebesedition 🎲
- **Konzept:** Würfelpoker zu zweit mit dem klassischen Kniffel-Block, aber
  Paar-Twists (Bonusfeld „Pärchenwurf": zwei identische Würfelpaare). Sehr
  hoher Wiederspielwert, perfekt async („dein Wurf wartet").
- **Multiplayer-Mechanik:** Zufall deterministisch: Wurf n des Spielers p =
  PRNG(seed aus Payload, p, n) — beide Clients berechnen identische Würfel,
  kein Würfel-Move nötig. Moves sind nur Entscheidungen:
  `{hold:[bool×5]}` (max 2× pro Runde) und `{score:"fullHouse"}`.
  Reducer validiert Kategorie-Doppelbelegung defensiv.
- **Aufwand:** M · **Score:** 9

### 3. Dame 🏁
- **Konzept:** 8×8-Damebrett im Liquid-Glass-Look, Steine in den
  Member-Farben. Ruhiges Denkspiel für den Feierabend, ideal async.
- **Multiplayer-Mechanik:** 1:1 das 4-Gewinnt-Muster: Moves =
  `{from:[c,r], to:[c,r]}`, Reducer erzwingt Zugpflicht/Schlagzwang/
  Mehrfachsprünge und skippt illegale Züge. Kein Zufall, kein Seed —
  der einfachste neue Reducer im ganzen Katalog.
- **Aufwand:** S/M · **Score:** 7

### 4. Backgammon 🎯
- **Konzept:** Der Beziehungs-Klassiker schlechthin (viele Paare haben ein
  physisches Brett). Würfeln, laufen, schlagen, auswürfeln — mit
  Verdopplungswürfel als „Einsatz": der Verlierer schuldet einen Coupon.
- **Multiplayer-Mechanik:** Würfel wie Kniffel deterministisch aus
  Seed + Zugindex. Moves: `{checker: point, die: 0|1}` einzeln, plus
  `{double}` / `{take}` / `{drop}` für den Verdopplungswürfel. Der Reducer
  ist die größte Einzelaufgabe (Bearing-off-Regeln), der Netzcode dagegen
  Standard-Relay.
- **Aufwand:** L · **Score:** 7

### 5. Wortkette-Blitz 🔗
- **Konzept:** Abwechselnd ein Wort schreiben, das mit dem letzten Buchstaben
  des vorherigen beginnt („Herz → Zelt → Traum…"), 20-Sekunden-Timer, keine
  Wiederholungen. Schnell, dumm, lustig — perfekter Lückenfüller.
- **Multiplayer-Mechanik:** Move = `{word}`. Reducer prüft Anfangsbuchstabe +
  Duplikat gegen die bisherige Liste. Timeout ist CLIENT-seitig deklariert:
  wer nicht rechtzeitig sendet, schickt `{timeout:true}` — bei Streit gilt
  der `createdAt`-Stempel des Servers auf dem Move (Quiz-Duell-Muster).
- **Aufwand:** S · **Score:** 6

### 6. Galgenraten: Unser Wort 🪢
- **Konzept:** Einer wählt ein geheimes Wort MIT Beziehungsbezug („unser
  erster Urlaubsort"), der andere rät Buchstaben. Statt Galgen welkt eine
  Herz-Blume — bei Sieg blüht sie auf.
- **Multiplayer-Mechanik:** Commit-Reveal light: Setter sendet
  `{commit: hash(wort+salt), len, hint}`; Rater sendet `{letter:"a"}`,
  Setter antwortet `{positions:[…]}` (Client-seitig ausgewertet), am Ende
  `{reveal}` mit Hash-Verifikation. Async-tauglich.
- **Aufwand:** S · **Score:** 7

### 7. Schere-Stein-Papier: Best-of-Turnier ✂️🪨📄
- **Konzept:** Best-of-7 mit Einsatz (Verlierer erfüllt einen Mini-Wunsch,
  z. B. „kocht heute"). Mit dramatischer 3-2-1-Aufdeck-Animation und Haptik-
  Countdown. Der schnellste Streitschlichter der App („wer bringt den Müll
  raus?").
- **Multiplayer-Mechanik:** Pro Runde Commit-Reveal in zwei Moves:
  `{commit: hash(wahl+salt)}` von beiden, dann `{reveal: wahl, salt}` —
  niemand kann auf die Wahl des anderen warten. Reducer wertet Runden erst,
  wenn beide Reveals da sind.
- **Aufwand:** S · **Score:** 6

### 8. Koop-Wordle „Duo" 🤝
- **Konzept:** Twist aufs bestehende Liebes-Wordle: EIN gemeinsames Grid,
  abwechselnd raten — Reihe 1 sie, Reihe 2 er … Man gewinnt oder verliert
  nur zusammen; Streak zählt für beide.
- **Multiplayer-Mechanik:** Neuer Game-Typ, aber maximale Wiederverwendung:
  Wortliste + Grid-Rendering existieren. Payload = `{dateKey, lang}` (Wort
  deterministisch wie beim Solo-Wordle), Move = `{guess}`; Reducer erzwingt
  Alternation. Ergebnis wandert als gemeinsames Grid in den Chat.
- **Aufwand:** S · **Score:** 8

### 9. Schach ♟️
- **Konzept:** Der Vollständigkeit halber: klassisches Schach, async über
  Tage („Fernschach für Verliebte"). Bewusst OHNE Engine/Tipps — es geht ums
  Miteinander, nicht um Elo.
- **Multiplayer-Mechanik:** Reines Relay wie Dame, Move = `{from, to,
  promotion?}`. Der Regel-Reducer (Rochade, en passant, Patt/Matt-Erkennung)
  ist aufwendig, aber komplett offline testbar (Logic-Tests auf Linux wie
  `CoupleGamesTests`).
- **Aufwand:** L · **Score:** 6

### 10. Paar-Kreuzworträtsel (Koop) 🧩
- **Konzept:** Ein gemeinsames Kreuzworträtsel, beide tippen gleichzeitig in
  dasselbe Gitter — wer gerade eine Zelle hält, „claimt" sie farbig (wie
  beim Kritzel-Canvas). Rätsel-Sets aus generischen + Beziehungs-Fragen
  („Kosename Nr. 1").
- **Multiplayer-Mechanik:** Move = `{cell:[x,y], char}` (leeres `char` =
  löschen), letzter Schreiber gewinnt die Zelle (Last-Write-Wins über
  Server-Reihenfolge — exakt das Canvas-Modell, nur auf Zellen statt
  Strokes). Payload = Rätsel-Id + Seed für die Fragenauswahl.
- **Aufwand:** L · **Score:** 8

---

## B. Kreativ- & Partyspiele

### 11. Montagsmaler mit Rate-Timer 🎨
- **Konzept:** Einer zeichnet einen geheimen Begriff auf dem bestehenden
  Kritzel-Canvas, der andere rät gegen einen 90-Sekunden-Timer per
  Texteingabe — je schneller, desto mehr Punkte. Rollen wechseln pro Runde,
  Best-of-5.
- **Multiplayer-Mechanik:** Die Strokes laufen über die EXISTIERENDE
  Canvas-Realtime-Pipeline (`canvas_stroke`), das Spiel-Layer darüber übers
  Move-Relay: Payload = Seed → deterministische Begriffs-Auswahl aus der
  Wortliste (nur der Maler-Client zeigt das Wort an), Moves =
  `{guess:"katze"}` und `{roundEnd, solved, elapsedMs}`. Punkte aus
  Server-`createdAt` der Guess-Moves — kein Timer-Streit möglich.
- **Aufwand:** M · **Score:** 9

### 12. Stadt-Land-Fluss: Paar-Edition 🗺️
- **Konzept:** Der Schulhof-Klassiker mit Paar-Kategorien: Stadt, Land,
  Fluss + „Kosename", „Date-Idee mit …", „Song", „Was ich an dir liebe
  mit …". Buchstabe wird ausgelost, beide schreiben gegen die Uhr, dann
  gegenseitiges Bewerten — die Antworten sind der eigentliche Spaß.
- **Multiplayer-Mechanik:** Payload = Seed → Buchstaben- und
  Kategorien-Reihenfolge deterministisch. Pro Runde 1 Move je Spieler:
  `{answers:{stadt:"…", …}}` (Anti-Spoiler: Client zeigt Partner-Antworten
  erst, wenn der eigene Move raus ist — Tagesfrage-Muster). Danach
  Bewertungs-Move `{scores:{stadt:0|5|10|20}}` über die Antworten des
  ANDEREN. Voll async-tauglich.
- **Aufwand:** M · **Score:** 8

### 13. Zwei Wahrheiten, eine Lüge 🤥
- **Konzept:** Jeder tippt drei Aussagen über sich/die Beziehung, der Partner
  muss die Lüge finden. Deckt nach Jahren noch Neues auf — die
  Auflösungs-Momente sind Gold und landen als teilbares Kärtchen im Chat.
- **Multiplayer-Mechanik:** Move 1 = `{statements:[a,b,c],
  commit: hash(lieIndex+salt)}`, Move 2 (Partner) = `{pick: 0|1|2}`,
  Move 3 = `{reveal: lieIndex, salt}` mit Client-Verifikation. Drei Moves,
  ein Abend-Ritual — kleinster sinnvoller Einsatz des Commit-Reveal-Musters.
- **Aufwand:** S · **Score:** 8

### 14. Fortsetzungsgeschichte 📖
- **Konzept:** Abwechselnd je einen Satz an eine gemeinsame Geschichte
  anhängen (Genre-Startkarten: Märchen über uns, Krimi, Sci-Fi-Liebesfilm).
  Nach 20 Sätzen wird das Werk „veröffentlicht": schön gesetzt, teilbar in
  den Chat, archiviert in einem Geschichten-Regal.
- **Multiplayer-Mechanik:** Move = `{sentence}` (≤ 200 Zeichen), Reducer
  erzwingt Alternation. Payload = Seed → Genre + optionale „Twist-Karten"
  an deterministischen Positionen („Satz 7 muss ein Tier enthalten").
  Async-Ideal: ein Satz pro Kaffeepause.
- **Aufwand:** S · **Score:** 8

### 15. Karaoke-Momente 🎤
- **Konzept:** Die App gibt einen Song-Prompt (aus eurem gemeinsamen
  Soundtrack oder Genre-Karten), einer singt 20–30 Sekunden ins Mikro, der
  Partner bewertet mit Herzen, Emojis und einem Kommentar. Verlauf =
  peinlich-schönes Audio-Album.
- **Multiplayer-Mechanik:** Aufnahme über die EXISTIERENDE
  Voice-Message-Pipeline (`POST /api/voice`), das Spiel referenziert die
  Message-Id im Move: `{performance: msgId, songTitle}`; Bewertung =
  `{rating: 1–5, emoji, comment}`. Kein neuer Medien-Code auf dem Server.
- **Aufwand:** M · **Score:** 7

### 16. Summ das Lied 🎵
- **Konzept:** Einer summt/pfeift 5–10 Sekunden ein Lied (gern aus eurem
  Soundtrack), der andere rät den Titel. Drei Rateversuche, dann Auflösung —
  Lacher garantiert.
- **Multiplayer-Mechanik:** Wie Karaoke über die Voice-Pipeline:
  `{clip: msgId, commit: hash(titel+salt)}` → `{guess}`-Moves →
  `{reveal}`. Der Rate-Abgleich passiert menschlich (Summer bestätigt per
  `{correct:true}`), der Hash verhindert nachträgliches „das meinte ich".
- **Aufwand:** S · **Score:** 7

### 17. 5-Sekunden-Blitz ⏱️
- **Konzept:** „Nenne 3 Dinge, die ich im Kühlschrank horte — 5 Sekunden!"
  Antwort kommt als Sprach-Schnipsel, der Fragesteller urteilt daumenhoch/
  runter. Karten-Set mit Paar-Fokus, Punktestand über 10 Runden.
- **Multiplayer-Mechanik:** Payload-Seed → Kartenreihenfolge. Moves:
  `{answer: voiceMsgId}` + `{verdict: bool}`. Die 5 Sekunden misst der
  Antwort-Client und deklariert `{elapsedMs}`; da der Partner das Audio
  hört und urteilt, braucht es keine Server-Schiedsrichterei.
- **Aufwand:** S · **Score:** 7

### 18. Paar-Bingo 🎰
- **Konzept:** 5×5-Karte mit Beziehungs-Alltag („hat ungefragt Essen
  mitgebracht", „Filmzitat im Alltag benutzt", „>10 km spazieren"). Beide
  streichen die Woche über ab — wer zuerst eine Reihe voll hat, ruft BINGO
  und kassiert einen Coupon.
- **Multiplayer-Mechanik:** Payload = Seed → beide Karten deterministisch
  aus dem Feld-Pool (unterschiedliche Karten je Spieler!). Move =
  `{check: cellIndex, note?}`; optionaler Beleg als `photoId`. Reducer
  erkennt Bingo-Reihen; Partner kann per `{challenge: cellIndex}` anzweifeln
  (dann muss ein Foto-Beleg her). Läuft tagelang async.
- **Aufwand:** S/M · **Score:** 7

---

## C. Koop & Rätsel

### 19. Escape-Room-Serie „Unsere Missionen" 🗝️
- **Konzept:** Kooperative Rätsel-Kapitel (30–45 min), bei denen JEDER
  Partner nur die HÄLFTE der Information sieht — einer hat den Code-Kreis,
  der andere die Symbol-Legende; lösen geht nur durch Reden (Call/FaceTime
  nebenher oder auf der Couch). Story-Bögen über mehrere Kapitel, neue
  Episoden pro Release als „Season-Content".
- **Multiplayer-Mechanik:** Payload = Kapitel-Id + Seed → asymmetrische
  Info-Verteilung deterministisch (Client A rendert Rolle 0, Client B
  Rolle 1 — Rollenzuteilung über Member-Id-Sortierung). Moves =
  `{puzzleId, attempt}`; der Reducer kennt die Lösungen (im Client-Content
  gehasht, nicht im Klartext) und schaltet Räume frei. Fortschritt
  persistiert → jederzeit unterbrechbar.
- **Aufwand:** L (Engine M + laufender Content) · **Score:** 10

### 20. Foto-Schiebepuzzle-Duell 🧩📷
- **Konzept:** Ein Foto aus EURER Galerie wird zum Puzzle (3×3 bis 5×5
  Schiebepuzzle oder Jigsaw-Raster): beide lösen dasselbe Puzzle
  gleichzeitig im Wettrennen, Splitscreen-Fortschrittsbalken zeigt, wie
  weit der andere ist.
- **Multiplayer-Mechanik:** Payload = `{photoId, size, seed}` →
  identische Start-Verwürfelung (Foto-Memory-Muster). Jeder löst LOKAL;
  Moves sind nur Fortschritts-Ticks `{placed: n}` + finales
  `{done, elapsedMs}` — gewonnen hat der frühere Server-`createdAt` des
  Done-Moves. Minimale Netzlast, maximales Renn-Gefühl.
- **Aufwand:** M · **Score:** 8

### 21. Galerie-Quiz: „Kennst du unsere Fotos?" 🖼️
- **Konzept:** Auto-generiertes Quiz aus eurer eigenen Galerie: „Wann war
  das?" (Monat raten), „Wer hat's hochgeladen?", „Welches Album?", „Welche
  Caption gehört dazu?". Nostalgie-Maschine ohne Content-Pflegeaufwand.
- **Multiplayer-Mechanik:** Payload = Seed + Foto-Id-Liste (Ersteller-Client
  sampelt aus `GET /api/photos`, legt die Auswahl in den Payload — beide
  laden die Bilder über die normalen Media-URLs). Fragen + Distraktoren
  deterministisch aus Seed + Metadaten. Moves = Quiz-Duell-Muster
  (`{questionIndex, answer, elapsedMs}`), Buzzer-Scoring über
  Server-Reihenfolge.
- **Aufwand:** M · **Score:** 8

### 22. Geo-Raten: „Wo war das?" 📍
- **Konzept:** Einer wählt ein Galerie-Foto, der andere muss auf einer Karte
  tippen, wo es aufgenommen wurde — Punkte nach Distanz (GeoGuessr-Gefühl
  mit euren Erinnerungen). Funktioniert auch ohne GPS-Metadaten: dann setzt
  der Wählende den Pin selbst als Referenz.
- **Multiplayer-Mechanik:** Move 1 = `{photoId, commit: hash(latlon+salt)}`,
  Move 2 = `{guess: latlon}`, Move 3 = `{reveal: latlon, salt}` →
  Distanz-Score im Reducer. MapKit ist framework-seitig da; keine neuen
  Server-Endpunkte.
- **Aufwand:** M · **Score:** 8

### 23. Sudoku zu zweit 🔢
- **Konzept:** Ein Board, zwei Modi: **Koop** (beide füllen dasselbe Gitter,
  Zellen leuchten in der Farbe des Ausfüllers) oder **Duell** (gleiches
  Puzzle, getrennte Boards, Wettrennen). Ruhiges Sonntags-Spiel.
- **Multiplayer-Mechanik:** Payload = Seed → deterministische
  Puzzle-Generierung (oder kuratierte Puzzle-Ids). Koop: Move =
  `{cell, digit}` mit Last-Write-Wins; Duell: nur Fortschritts-Ticks +
  `{done}` wie beim Schiebepuzzle. Generator/Solver ist die Hauptarbeit,
  komplett Logic-Test-bar.
- **Aufwand:** M · **Score:** 6

---

## D. Aktivitäten in der echten Welt

### 24. Fotosafari-Aufgaben 📸
- **Konzept:** Die App lost 5 Foto-Aufgaben („fotografiere etwas Rotes",
  „etwas, das dich an unser erstes Date erinnert", „dein Mittagessen aus
  Bodenperspektive"). Beide jagen parallel (zuhause, im Büro, auf Reisen),
  am Ende Side-by-Side-Galerie und gegenseitige Herz-Wertung pro Motiv.
- **Multiplayer-Mechanik:** Payload = Seed → identische Aufgabenliste.
  Fotos gehen über die normale Galerie-Pipeline (Album „📸 Safari <Datum>"),
  Move = `{taskIndex, photoId}`; Anti-Spoiler wie Tagesfrage (Partner-Fotos
  erst sichtbar, wenn die eigene Aufgabe erledigt ist). Bewertung =
  `{taskIndex, hearts:1–3}`. Tage-lang async — die perfekte
  Fernbeziehungs-Aktivität.
- **Aufwand:** M · **Score:** 8

### 25. Workout- & Spaziergang-Challenges 💪
- **Konzept:** Wochen-Challenges als Karten („3× 20 min spazieren", „jeden
  Morgen 10 Kniebeugen — zusammen per FaceTime zählt doppelt") mit
  Foto-/Video-Beweis. Der Partner verifiziert; abgeschlossene Wochen füttern
  eine gemeinsame Fitness-Flamme analog zum Check-in-Streak.
- **Multiplayer-Mechanik:** Game-Session pro Woche (async, lange Laufzeit):
  Payload = gewählte Challenge-Karten, Move = `{challengeId, proof: photoId
  | videoId, note}` + Partner-Bestätigung `{challengeId, verified: bool}`.
  Kein Fitness-Tracking-Anspruch — der Mensch ist der Sensor, das Paar der
  Schiedsrichter (ehrlich & sideload-sicher).
- **Aufwand:** M · **Score:** 8

### 26. Schrittzähler-Duell 👟
- **Konzept:** Wochen-Duell „wer geht mehr Schritte?" mit Tagesbalken und
  Sonntags-Siegerehrung. Ehrliche Einordnung: HealthKit-Zugriff übersteht
  nicht jedes Sideload-Signing — die App erkennt das zur Laufzeit (wie beim
  iCloud-Feature) und fällt auf manuelle Tageseingabe mit Partner-Vertrauen
  zurück.
- **Multiplayer-Mechanik:** Move = `{dateKey, steps}` (1× täglich je
  Spieler, Resubmit ersetzt den eigenen Wert — POTD-Muster). Reducer
  summiert pro Woche; keine Server-Änderung nötig. HealthKit liefert die
  Zahl nur lokal beim App-Öffnen — passt zum No-Push-Modell.
- **Aufwand:** M · **Score:** 7

### 27. Heim-Schnitzeljagd 🕵️
- **Konzept:** Einer versteckt ein „Schatz-Objekt" (Zettel, Snack, kleines
  Geschenk oder ein Coupon-Code aus der App) und legt 3–5 Hinweise in der
  App an; der andere sucht real und schaltet Hinweis für Hinweis frei.
  Fund-Beweis: Foto. Auch remote spielbar: Verstecken in der EIGENEN
  Wohnung, der Partner dirigiert per Hinweis-Raten.
- **Multiplayer-Mechanik:** Payload/Moves des Versteckers = Hinweisliste
  mit `{hint, unlockAnswer?: hash}`; Sucher-Moves = `{requestHint}` /
  `{attempt}` / `{found: photoId}`. Optional zeitgesteuerte Freischaltung
  über deklarierte Client-Zeit + Server-`createdAt` als Obergrenze.
- **Aufwand:** M · **Score:** 8

### 28. Paar-Tagesquests ⚔️
- **Konzept:** Jeden Tag 3 kleine gemeinsame Quests aus einem Pool („schickt
  euch heute ein Sprachmemo", „macht je ein Foto vom Himmel", „gewinnt eine
  Runde 4 Gewinnt"), Fortschritt füllt einen gemeinsamen Tages-Ring.
  Verzahnt bestehende Features zu einem Engagement-Loop — die „Daily" der
  ganzen App.
- **Multiplayer-Mechanik:** Quests deterministisch aus
  `hash(coupleId + dateKey)` (Tagesfrage-Muster — kein Server-State für
  die Auswahl nötig). Erfüllung erkennt der Client aus ohnehin
  vorhandenen Events (message/photo/game_ended über WS bzw. beim Öffnen
  via REST); ein `quest_progress`-Move pro Quest synchronisiert den Ring.
  Für V3 reicht das generische Relay, langfristig eigener Endpunkt.
- **Aufwand:** M · **Score:** 9

---

## E. Essen, Filme & Alltag

### 29. Film-Roulette mit Swipe-Matching 🍿
- **Konzept:** Beide swipen durch denselben Stapel Film-/Serien-Karten
  (Genre-Filter vorher wählbar) — Tinder-Mechanik: beide rechts = **MATCH**,
  Konfetti, „Filmabend steht!" mit 1-Tap-Übernahme in Momente (Termin) und
  die Snack-Einkaufsliste. Löst DAS Alltagsproblem Nr. 1 („was gucken
  wir?").
- **Multiplayer-Mechanik:** Payload = Seed + Filterauswahl →
  deterministische Karten-Reihenfolge aus gebündeltem Katalog (kuratierte
  Titelliste ohne externe API — Sideload braucht keine Keys; eigene
  Watchlist-Einträge als Karten importierbar). Moves = `{cardIndex,
  like: bool}`; der Reducer meldet einen Match, sobald beide Likes
  vorliegen — live per WS ODER Stunden versetzt async. Match → optional
  `POST /api/events` + Listen-Eintrag.
- **Aufwand:** M · **Score:** 9

### 30. Rezept-Roulette „Gemeinsam kochen" 👩‍🍳
- **Konzept:** Gleiches Swipe-Matching über Rezept-Karten (gebündelter
  Katalog: 80–120 Rezepte mit Aufwand/Ernährungs-Filtern). Match →
  Zutaten wandern per 1-Tap in eine gemeinsame Einkaufsliste
  (`/api/lists`), Kochabend als Moment, hinterher Foto vom Ergebnis in
  die Galerie („Unser Kochbuch"-Album).
- **Multiplayer-Mechanik:** Identischer Reducer wie Film-Roulette (eine
  Engine, zwei Content-Decks!). Die Einkaufsliste nutzt die existierende
  Listen-API inkl. Live-Abhaken im Supermarkt — null neue Serverarbeit.
- **Aufwand:** M (S, wenn Film-Roulette zuerst kommt) · **Score:** 8

### 31. Wettbüro der Herzen 🎫
- **Konzept:** Paar-Wetten mit Coupon-Einsatz: „Ich wette, dass ich das
  Wordle heute in 3 Reihen schaffe" / „…dass es Samstag regnet" / „…dass
  du vor mir einschläfst". Der Partner hält dagegen, Einsatz ist ein
  Love-Coupon; wer verliert, dessen Coupon wird für den Gewinner erstellt.
- **Multiplayer-Mechanik:** Moves: `{bet: text, stake: couponDraft,
  deadline}` → `{accept}` → beide `{settle: won|lost}` (bei Einigkeit
  zahlt der Client des Verlierers automatisch via `POST /api/coupons` aus;
  bei Uneinigkeit bleibt die Wette offen markiert — Humor statt
  Schiedsgericht). App-interne Wetten (Wordle, Spiele) kann der Client
  sogar selbst aus den APIs verifizieren.
- **Aufwand:** M · **Score:** 8

### 32. Date-Würfel Deluxe 🎲💘
- **Konzept:** Drei Würfel entscheiden den nächsten Abend: WAS (Aktivität),
  WO (drinnen/draußen/Stadt), WER ZAHLT/ORGANISIERT. Einmal würfeln,
  gemeinsam 1× Veto erlaubt, dann gilt's — Ergebnis wird als Moment mit
  Countdown angelegt. Der Date-Ideen-Generator existiert; das hier macht
  daraus ein verbindliches Mini-Ritual.
- **Multiplayer-Mechanik:** Payload-Seed → Würfelergebnisse deterministisch;
  Moves = `{roll}` / `{veto}` (max 1) / `{commit}`. Nach `{commit}` legt
  der Client das Event über die bestehende Momente-API an. Winziger
  Reducer, großer Alltagswert.
- **Aufwand:** S · **Score:** 7

---

## F. Saisonales & Meta

### 33. Advents-/Countdown-Kalender 🎄
- **Konzept:** 24 Türchen, die sich die Partner GEGENSEITIG füllen (je 12,
  abwechselnd): versiegelte Briefe, Fotos, Coupons, Sprachnachrichten,
  Haptik-Muster, Mini-Aufgaben. Ab 1. Dezember öffnet sich pro Tag ein
  Türchen mit der bestehenden Siegel-Enthüllungs-Animation. Generalisiert
  als „Countdown-Kalender" auch für Geburtstage/Jahrestage (X Türchen bis
  zum Tag).
- **Multiplayer-Mechanik:** Kein Spiel im engeren Sinn — Content-Container
  über bestehende Bausteine: Türchen referenzieren Message-/Photo-/
  Coupon-/Haptik-Ids; Zeitschloss client-seitig gegen Server-`serverTime`
  geprüft (kein Push nötig: wer die App öffnet, findet das offene
  Türchen). Anti-Spoiler: eigene Türchen-Inhalte sieht nur der Befüller.
  Braucht einen kleinen neuen Endpunkt (`/api/calendar`) oder eine
  Games-Session mit langer Laufzeit.
- **Aufwand:** M · **Score:** 9

### 34. Saisonale Event-Rahmen 💘🎃
- **Konzept:** Wiederkehrende zeitlich begrenzte Events mit eigenem Look:
  Valentinstags-Quest (7 Tage Mini-Aufgaben bis zum 14.2.), Halloween-
  Gruselgeschichten-Modus (Fortsetzungsgeschichte im Horror-Deck),
  Sommer-Fotosafari-Serie. Kein neues Spielsystem — Skins + kuratierte
  Aufgaben-Decks über die vorhandenen Engines, gesteuert per Datum.
- **Multiplayer-Mechanik:** Events sind Content + Theming, deterministisch
  aus `dateKey` aktiviert (beide Clients sehen dasselbe Event ohne
  Server-Flag). Aufgaben nutzen die jeweilige Spiel-Engine; ein
  Abschluss-Badge wandert in den Trophäenschrank (Idee 37).
- **Aufwand:** M/L (pro Event S, Rahmen M) · **Score:** 8

### 35. Turnier-Modus & Saison-Trophäen 🏆
- **Konzept:** Monats-Saisons über ALLE Spiele: Jede Partie (4 Gewinnt,
  Quiz-Duell, Wordle-Duell, Memory + alles Neue) zahlt Punkte auf ein
  Saison-Konto ein; am Monatsende gibt es Trophäen (Gold für den Sieger,
  aber auch Koop-Trophäen: „100 gemeinsame Partien"). Ein Trophäen-Regal
  archiviert die Saisons — sanfter Wettkampf mit Wir-Gefühl statt
  Dauer-Rangliste.
- **Multiplayer-Mechanik:** Kein neues Realtime-Protokoll: Der Client
  aggregiert `GET /api/games?limit=100` + Wordle-History deterministisch
  pro Monat (`dateKey`-Fenster) — beide Handys berechnen identische
  Tabellen aus denselben Server-Daten (Year-Review-Muster). Fürs Regal
  langfristig ein kleiner `/api/trophies`-Endpunkt, für V3 reicht die
  Ableitung on-the-fly.
- **Aufwand:** M/L · **Score:** 9

### 36. Replay & Zuschauer-Modus 🎬
- **Konzept:** Jede beendete Partie lässt sich als Film abspielen: Züge
  animieren in Originalreihenfolge (mit Zeitraffer), der „Wende-Moment"
  wird markiert; Highlights als Bild in den Chat teilbar. Live-Zuschauen
  gibt es gratis dazu: Ein zweites eigenes Gerät (iPad!) kann eine laufende
  Partie beobachten.
- **Multiplayer-Mechanik:** Das Killer-Argument: **Die Architektur schenkt
  uns das Feature.** Deterministische Reducer + persistierte Move-Listen
  (`GET /api/games` liefert `moves` inkl. `createdAt`) bedeuten: Replay =
  Reducer schrittweise über die Zugliste laufen lassen. Zuschauen = WS
  broadcastet `game_move` ohnehin an ALLE Sockets des Paars — der
  Beobachter-Client rendert nur read-only.
- **Aufwand:** S · **Score:** 7

### 37. Trophäenschrank & Abzeichen 🏅
- **Konzept:** Achievements über die ganze App: „Erster Sieg in jedem
  Spiel", „10-Tage-Quest-Serie", „Escape-Kapitel ohne Hinweis",
  „Karaoke-Mutprobe", saisonale Event-Badges. Gemeinsame UND persönliche
  Abzeichen; neue Trophäe = Vollbild-Moment mit Fanfare (Sound-Engine hat
  sie schon).
- **Multiplayer-Mechanik:** Abzeichen-Regeln sind pure Funktionen über
  Server-Daten (Games-History, Stats, Streaks) — beide Clients berechnen
  denselben Stand, kein neuer State. Nur „Moment des Freischaltens"
  braucht Sync: ein leichtgewichtiger Broadcast (Touch-artiger Endpunkt
  oder Game-Move) damit der Partner die Fanfare mitbekommt.
- **Aufwand:** M · **Score:** 8

---

## Top-10 für 3.0 (priorisiert)

| # | Idee | Aufwand | Score | Warum jetzt |
|---|------|---------|-------|-------------|
| 1 | **35 Turnier-Modus & Saison-Trophäen** | M/L | 9 | Multipliziert den Wert ALLER 13 bestehenden + aller neuen Spiele sofort; braucht null neue Realtime-Technik (reine Ableitung aus `GET /api/games`). Das Meta-Skelett, in das 4.0/5.0-Spiele einrasten. |
| 2 | **11 Montagsmaler** | M | 9 | Nutzt die Canvas-Realtime-Pipeline wieder — das charmanteste Live-Spiel fürs Geld; zeigt die WS-Stärke der App maximal. |
| 3 | **1 Schiffe versenken** | M | 9 | Meist­gewünschter Klassiker überhaupt; etabliert das Commit-Reveal-Muster, von dem 5 weitere Ideen (6, 7, 13, 16, 22) profitieren. Async-tauglich = sideload-perfekt. |
| 4 | **29 Film-Roulette** | M | 9 | Erste „Aktivität statt Spiel" — löst ein echtes Alltagsproblem und schafft die Swipe-Match-Engine, die Rezept-Roulette (30) fast gratis macht. |
| 5 | **2 Kniffel** | M | 9 | Höchster Wiederspielwert der Brettspiel-Klasse; etabliert deterministische Seed-Würfel (Grundlage für Backgammon & Date-Würfel). |
| 6 | **33 Advents-/Countdown-Kalender** | M | 9 | Saisonaler Wow-Moment: 3.0 erscheint vor Dezember → der Kalender IST das Weihnachts-Feature; komponiert nur bestehende Bausteine (Briefe, Coupons, Haptik). |
| 7 | **28 Paar-Tagesquests** | M | 9 | Der tägliche Engagement-Loop, der alle Features verzahnt; deterministisch aus `coupleId + dateKey` wie die Tagesfrage — kein Server-Umbau. |
| 8 | **12 Stadt-Land-Fluss** | M | 8 | Nostalgie + die Paar-Kategorien erzeugen Gesprächsstoff; Anti-Spoiler- und Bewertungs-Mechanik komplett nach Tagesfrage-Vorbild, voll async. |
| 9 | **13 Zwei Wahrheiten, eine Lüge** | S | 8 | Bestes Spaß-pro-Aufwand-Verhältnis der Liste: drei Moves, ein Abend-Ritual, teilbare Auflösungs-Kärtchen — idealer „Quick Win" fürs Release-Marketing. |
| 10 | **36 Replay & Zuschauer-Modus** | S | 7 | Die deterministische Architektur schenkt uns das Feature fast; macht jede Partie (alt UND neu) teilbar und archivierbar — sichtbarer 3.0-Polish für minimalen Preis. |

**Knapp dahinter (4.0-Kandidaten):** Escape-Room-Serie (19, Score 10 — aber
L-Aufwand plus laufende Content-Pipeline: als Leuchtturm-Feature für 4.0
aufsparen), Fotosafari (24), Rezept-Roulette (30, sobald die Swipe-Engine
aus #4 steht), Koop-Wordle Duo (8), Paar-Bingo (18), Wettbüro (31),
Trophäenschrank (37, sinnvoll eine Version NACH dem Turnier-Modus).

**Empfohlene Reihenfolge innerhalb 3.0:** Zuerst die
Infrastruktur-Voraussetzungen (parallele Sessions + Inbox-`games`-Bucket +
Server-Seed), dann #9/#10 als schnelle Erfolge, dann die M-Brocken. Der
Adventskalender (#6) hat eine harte Deadline (1. Dezember) und gehört früh
in die Planung.
