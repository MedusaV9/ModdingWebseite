# MONKEY MONEY — GAME-DESIGN.md (verbindlich, v1.0)

> Dieses Dokument ist ENTSCHIEDENES Design, kein Options-Katalog. Es
> konsolidiert die 20 Ideen-Kataloge aus `/tmp/monkey-money-ideen/` (01–20,
> ~7.800 Zeilen). Wo Kataloge sich widersprachen, steht hier die Entscheidung
> samt Zahl. Bau-Agents setzen dieses Dokument direkt um. Abweichungen nur
> mit dokumentierter Design-Änderung.
>
> Produkt: Jackbox/Buzz-artige Quiz-Show-Party-App, 2–8 Spieler, Handys
> hochkant = Controller, iPad/PC = Bildschirm, optionaler menschlicher GM
> oder Auto-GM, Money-/Affen-Thema. Node.js-Server, HTTP-Polling,
> lokales Hosting, kein Cloud-Zwang.

---

## 0. Design-Kompass (nicht verhandelbar)

1. **Money ist Punktestand UND Spielressource.** Match-Money (MM) kann
   ausgegeben werden (Tipps, Joker, Wetten) — jeder Kontostand ist eine
   Entscheidung, keine Anzeige.
2. **1 Schein = 50 MM.** ALLE Beträge sind Vielfache von 50 (Ausnahme:
   das 25-MM-„Applaus-Almosen“, bewusst ein halber Schein als Gag).
   Gewinne regnen als einzelne 50er-Scheine aufs Podium (ab 20 Scheinen
   Bündel-Animation); Stapel-Höhe am Podium = Kontostand.
3. **Zwei Währungs-Sphären, eine Richtung.** Match-Money → All-Time-Money
   (AT) fließt nur in eine Richtung. AT ist NIE im Match einsetzbar
   (einzige eng umzäunte Ausnahme: Gutscheine, siehe 7.4). Kein Echtgeld,
   nirgends, niemals.
4. **Drama vor Fairness, Fairness im Finale.** Zwischenrunden dürfen gemein
   sein; das Finale garantiert mathematisch, dass der Letzte noch gewinnen
   KANN (Finale-Formel, 3.5).
5. **Verlustfreie Zone:** In den ersten ~25 % der Spielzeit kann niemand
   MM verlieren.
6. **Jede Handy-Aktion hat einen Bildschirm-Moment.** Joker, Klau, Strafe,
   Kauf — alles wird auf dem großen Bildschirm inszeniert.
7. **Transparenz schlägt Verbot.** GM darf fast alles, aber alles wird
   geloggt und vieles am Runden-/Match-Ende inszeniert aufgedeckt.
8. **Underdog-Hilfe ist transparent, nie heimlich.** Aufholmechaniken
   werden angekündigt („Rückenwind für Lisa!“).
9. **HTTP-Leitplanke:** Wertungen hängen nie an Frame-genauen Zeitpunkten,
   sondern an Stufen/Blöcken (50-MM-Ticks, 3-s-Pixel-Stufen,
   1-s-Tap-Batches) oder gedeckelten Client-Timestamps (Server-Zeit
   −800 ms Anti-Cheat-Kappe). Spätantwort-Gnadenfenster: +400 ms nach
   Timer-Ende.
10. **Zeit und Zufall werden IMMER injiziert** (Clock-Muster, RNG als
    Parameter) — Kernlogik ist deterministisch testbar. **Event-Log ist
    Single Source of Truth**: jede Zustandsänderung ist ein append-only
    Event; Stats/Boards/Analytics sind Ableitungen (Replay-fähig).

**Fragen-Grundlagen:** 14 Hauptkategorien (aus Katalog 12), 4 Schwierigkeiten
(EASY/MEDIUM/HARD/ULTRAHARD), DE/Global-Anteil als Prozent-Regler (Default
Mix 50/50). Jeder Spieler wählt beim Join 3 „Meine Themen“-Tags
(Futter für Maßanzug-Runden und Auto-GM-Kuration).

---

## 1. SPIELABLAUF-BIBEL

### 1.1 Standard-Match-Flow (Phasen)

| # | Phase | Dauer | Inhalt |
|---|---|---|---|
| 1 | **Lobby** | offen | Raumcode/QR-Join, Name + Affen-Avatar (10-s-Profil, optional PIN), 3 „Meine Themen“-Tags, Preset-/Settings-Wahl durch Host/GM, Ready-Check. Bestenlisten-Karussell auf dem Bildschirm. |
| 2 | **Opening** | 30–45 s | Intro-Jingle, Spieler-Einlauf (Avatare + Buzzer-Sound-Vorstellung), Ansage der „heutigen Show-Stimmung“ (Regie-Preset) und der aktiven Special Rules als Icon-Leiste. Skippable per Host-Tap. |
| 3 | **Runden** | s. 1.3 | Pro Runde: Erklärkarte (10–15 s, mit Streik-Fenster S-03) → Minispiel → Runden-Zwischenstand. Glücksrad dreht ZWISCHEN Runden (Szenenwechsel-Vorhang, ~12 s, kürzbar auf 6 s). |
| 4 | **Jackpot-Beat** | ~90 s | 1× pro Match (nicht in Quick), direkt vor der RISIKO-Runde: „DIE JACKPOT-FRAGE!“ — MC-4 für alle, Wert 2.000 MM + kompletter Inhalt des Jackpot-Glases (siehe 3.2). |
| 5 | **Finale** | 4–6 min | „Das große Lianen-Finale“ (Format 10, Formel 3.5). Vorher: Schuldenerlass auf 0 (Affen-Anwalt-Cutscene) + Mitleids-Banane (300 MM an den Letzten). |
| 6 | **Siegerehrung** | 90–120 s | Sieger-Inszenierung (Konfetti, Geldregen, Krönung), 3 Podeste: Money-Sieger, MVP (Spieler-Voting, ab 4 Spielern), Stiller Star (beste Quote bei wenigsten Angriffen, auto). 3–4 Fun-Stats-Awards. Kontoauszug: Match→AT-Umrechnung sichtbar pro Spieler. |
| 7 | **Abspann** | 30 s | End-Feedback (3 Fragen aufs Handy, Ergebnis als „Presse-Stimmen“), persönliche Rekorde („Neuer Bestwert!“), großer **REVANCHE**-Button (gleiche Spieler/Settings, 3-2-1-Restart) + „Rache-Modus“: der Letzte darf für das Rematch EINE Einstellung ändern (öffentlich angekündigt). |

### 1.2 Slot-Dramaturgie (Regeln für jede Playlist)

Jede Show besteht aus Slots `OPENER → AUFBAU → GELD → KONFLIKT → RISIKO →
FINALE`. Jedes Format trägt Slot-Tags; der Auto-GM (oder GM) besetzt Slots —
so bleibt jede Show anders, der Spannungsbogen stimmt immer.

- **Verlustfreie Zone:** OPENER- und erste AUFBAU-Runde können MM nur
  BRINGEN (Bananen-Basics, Kokosnuss-Uhr, Bananen-Tresor, Affenleiter).
- **Aggro-Puffer:** Nach Klau-/Krawall-Runden (Taschendieb, Stinkbanane)
  nie direkt das Finale — immer die Wettrunde dazwischen.
- **Comeback-Garantie:** Pro Show mindestens zwei von: (a) Letzter wählt
  die Kategorie der KONFLIKT-Runde, (b) Glücksrad-Segment „Banana Bailout“ /
  „Steuerprüfung“ im Pool, (c) Jackpot-Frage, (d) Finale mit
  Aufhol-Formel (immer aktiv).
- **Schwierigkeits-Progression:** OPENER zieht aus EASY+MEDIUM, AUFBAU aus
  MEDIUM+HARD, KONFLIKT/RISIKO aus HARD (+ULTRAHARD). ULTRAHARD max. 2× pro
  Match (Quick: 1×), IMMER mit Fanfare angekündigt („DIE 1000er!!“).
- **Rad-Beats:** genau 1 garantierter Dreh pro Runden-Wechsel ab Runde 2,
  hartes Maximum ~1 Dreh pro 3–4 Fragen; in den letzten 2 Runden + Finale
  nur „Fair-Finale-Pool“ (siehe 5.3).

### 1.3 Match-Längen (verbindlich)

| Modus | Runden | Fragen/Runde | Finalfragen Q | Dauer | Rad-Drehs |
|---|---|---|---|---|---|
| **Quick Cash** | 4 | 3 | 3 | ~15–20 min | 1 (nach R3) |
| **Klassik-Show** | 6 | 4 | 5 | ~35–45 min | 3 (nach R2/R4/R5) |
| **Marathon („Börsentag“)** | 9 | 4 | 7 | ~60–75 min (mit Halbzeit-Pause) | 4–5 |

**Default-Playlists (Auto-GM-Varianten in Klammern):**

- **Quick:** Bananen-Basics → Kokosnuss-Uhr → Affenbank → Alles oder
  Banane → Lianen-Finale (Q=3). Keine Jackpot-Frage, Joker aus,
  Defaults fest — Ein-Tap-Start, gleichzeitig das Onboarding.
- **Klassik:** R1 Bananen-Basics (fix) → R2 Bananen-Tresor (alt:
  Kokosnuss-Uhr, Affenleiter) → R3 Pixel-Dschungel (alt: Affenleiter,
  Kokosnuss-Uhr) → R4 Affenbank (fix) → R5 Stinkbanane (alt: Taschendieb;
  Letzter wählt Kategorie) → Jackpot-Frage → R6 Alles oder Banane (fix) →
  Lianen-Finale (Q=5).
- **Marathon:** Basics → Kokosnuss-Uhr → Bananen-Tresor → Affenleiter →
  Affenbank → **[Halbzeit-Pause, Zwischenstand als Kurschart]** →
  Pixel-Dschungel → Stinkbanane → Taschendieb → Jackpot-Frage →
  Alles oder Banane → Lianen-Finale (Q=7).

### 1.4 Team-Modi v1 (genau diese)

**v1 enthält EINEN Team-Modus: „Affenbanden“ (feste 2er-Teams).**

- Verfügbar ab 4 Spielern (2v2, 2v2v2, 2v2v2v2). Bei 5/7 Spielern:
  „Doppel-Affe“ (ein Spieler zählt doppelt, erhält Einzelanteil). Bei
  2–3 Spielern ausgeblendet.
- Team-Bildung: frei wählen / Zufalls-Auslosung (Slot-Machine-Animation) /
  GM-Drag&Drop. Auto-Team-Namen aus Money-Affen-Wortschatz
  („Die Bananen-Barone“, „Krypto-Kapuziner“) + Team-Farbe.
- Money: Team-Topf für Rundengewinne, transparent auf dem Bildschirm,
  am Match-Ende 50/50 auf die Einzelkonten. Individuelle Boni
  (z. B. Volltreffer) bleiben privat.
- Zwei Team-Twists laufen über die bestehenden Formate:
  1. **Flüster-Timer** (in Basics/Tresor/Leiter): 10 s Beratung erlaubt,
     danach Einzeleingabe gesperrt-getrennt; einstimmig UND richtig =
     Bonus ×1,5 („Synchron-Affen“).
  2. **Doppel-Buzzer** (Basics-Variante): beide antworten getrennt;
     Punkte nur bei identisch UND richtig; identisch-falsch = 50 MM
     Trostpreis („wenigstens einig“).
- Finale im Team-Modus: eine Team-Liane, Antworten alternierend.
- „Ansage-Momente“ (Bildschirm dirigiert den Tisch: High-Five, Affentanz,
  „zeig auf den nächsten Dieb“) sind in allen Modi aktiv (Prompt-Pool
  filtert nach Spielerzahl/Modus).

Alles Weitere (Affenkönig, Dschungel-Clash 4v4, Schlange/Verräter,
1v1-Duelle, Turnier-Bracket) ist **v2** (siehe 8.3).

---

## 2. DIE MINISPIEL-LISTE v1 (10 Formate) + Systembausteine

### 2.0 Globale Konventionen (gelten überall, sofern nicht überschrieben)

- **Werte/Boni/Streak:** siehe Ökonomie-Tabellen in Abschnitt 3.
- **Timer:** EASY/MEDIUM 15 s, HARD 20 s, ULTRAHARD 25 s. Anzeige: Banane
  am oberen Bildschirmrand wird „aufgegessen“; letzte 5 s Pulsieren +
  Tick + Affenkreischen. Handy zeigt redundanten dünnen Balken.
- **Spätantwort:** Server-Empfangszeit zählt, +400 ms Gnadenfenster nach
  Timer-Ende; danach verworfen = „keine Antwort“ (0 MM).
- **Disconnect:** Spieler wird „AFK-Affe“ (Avatar schläft, 0 MM, keine
  Strafe, Streak eingefroren) für 2 Fragen; Reconnect via Raumcode+Name
  mit vollem Stand. Danach entscheidet GM/Auto-GM (weiter ohne ihn,
  Slot reserviert). Bot antwortet NIE für Menschen.
- **Gleichstand:** innerhalb einer Wertung entscheidet frühere
  Server-Empfangszeit; bei Konto-Gleichstand am Runden-/Matchende →
  Tiebreaker **Kokosnuss-Shake** (2.11).
- **Doppel-Eingaben (Netz-Retry):** Server nimmt pro Frage-ID nur die
  erste Antwort (idempotent).
- **Input-Primitive (Controller braucht genau 5):** große Buttons,
  vertikaler Slider, Drag-Sortier-Liste, Gedrückthalten, Tap-Frenzy.

---

### 2.1 Bananen-Basics *(Buzz: Point Builder — OPENER, fix in jeder Show)*

- **Regeln:** MC-4-Standardrunde. Alle beantworten dieselbe Frage
  gleichzeitig. Runde 1 ist verlustfrei: falsch = 0, keine Strafe.
- **Handy:** 4 große Farb-Buttons vertikal (je ~20 % Bildhöhe): 🍌 Gelb,
  🥥 Braun, 🐒 Rot, 🌴 Grün. Nach Tap eingerastet, kein Umentscheiden
  (Joker „Rückgaberecht“ hebt das auf).
- **Bildschirm:** Frage oben, 4 Antwort-Lianen pendeln; pro Abgabe hüpft
  ein anonymer Mini-Affe auf den „hat geantwortet“-Ast. Auflösung: falsche
  Lianen reißen, die richtige zieht die Richtigen hoch; MM regnet als
  Scheine auf die Avatare.
- **Timing:** Timer nach Schwierigkeit (15/15/20/25 s), Auflösung 6 s.
- **Scoring:** `MM = Grundwert × Speed-Faktor × Streak-Faktor` (Tabellen
  3.1). Beispiel: MEDIUM 250, Antwort bei 20 % der Zeit, Streak 3 →
  250 × 1,5 × 1,5 = ~550 (auf 10er gerundet, Anzeige in Scheinen).
- **Edge-Cases:** Gleichstand/Disconnect/Spät = Standard.

### 2.2 Stopp die Kokosnuss-Uhr *(Buzz: Stop the Clock — AUFBAU)*

- **Regeln:** Über der Frage schrumpft ein MM-Sack in sichtbaren
  **50-MM-Ticks** auf 0. Antworten friert DEN EIGENEN Sack ein: richtig =
  eingefrorener Betrag, falsch = 0. Ersetzt den Speed-Bonus komplett.
- **Sack-Startwerte:** MEDIUM 400 MM (8 Ticks / 15 s ≈ alle 1,9 s),
  HARD 750 MM (15 Ticks / 20 s). Streak zählt normal.
- **Handy:** 4 Antwort-Buttons + live mitschrumpfender Betrag darüber.
- **Bildschirm:** prall gefüllter Geldsack leert sich Tick für Tick;
  eingefrorene Spieler bekommen ein Eis-Overlay auf ihrem Sack.
- **Timing:** 15/20 s je Schwierigkeit, Auflösung 6 s.
- **Edge-Cases:** Spätantwort → Tick der Server-Empfangszeit zählt
  (Tick-Stufen machen Polling-Latenz egal). Rest Standard.

### 2.3 Der Bananen-Tresor *(eigenes Format: Schätzrunde — AUFBAU, der große Gleichmacher)*

- **Regeln:** Schätzfrage mit Zahlenantwort. Jeder tippt einen Wert;
  nächster dran gewinnt, gestaffelt nach Nähe.
- **Handy:** großer vertikaler Slider (70 % Bildhöhe, Log-/Linear-Skala je
  Frage), Zahlenfeld groß darüber, ±1-Feintuning, optional Direkteingabe,
  „EINLOGGEN“-Button.
- **Bildschirm:** Zahlenstrahl als Liane; nach Timer-Ende erscheinen alle
  Tipps gleichzeitig als Affen-Köpfe mit Namen, dann fährt der goldene
  Pfeil zum wahren Wert (Zoom, Abstands-Beschriftung). Absurde Ausreißer
  liest der (Auto-)GM genüsslich vor.
- **Timing:** 20 s schätzen, 8 s Auflösung.
- **Scoring (Festwerte, immer):** Platz 1 = 400 MM, Platz 2 = 250,
  Platz 3 = 150, alle übrigen 50 („Schätzen lohnt immer“).
  **Volltreffer exakt = 1.000 MM + „NAGEL AUF DEN KOPF“-Cutscene.**
  Marathon-Spätrunden-Variante (HARD-Schätzung): 800/500/300/100,
  Volltreffer 2.000. Kein Speed-Bonus, keine Streak.
- **Edge-Cases:** gleiche Distanz = beide bekommen den besseren Platz
  (nächster Platz entfällt). Keine Abgabe: letzter bewegter Slider-Stand
  zählt, unbewegt = keine Wertung. Disconnect = keine Abgabe.
  Slider-Kappe „>10.000“ gegen Überlauf.

### 2.4 Affenleiter *(Buzz: Top Rank — AUFBAU)*

- **Regeln:** 4 Elemente in die richtige Reihenfolge bringen
  (größer/älter/teurer/früher; auch mit Bildern).
- **Handy:** vertikale Karten-Liste, Drag&Drop ODER Tap-Tap-Tausch
  (zittrige-Finger-Fallback), „EINLOGGEN“.
- **Bildschirm:** Palmen-Leiter; Auflösung Sprosse für Sprosse von unten,
  pro Sprosse klettern die Avatare hoch, die richtig lagen.
- **Timing:** 30 s sortieren, 3 s pro Sprosse Auflösung.
- **Scoring:** pro korrekt platziertem Element `Grundwert/4`; komplett
  richtig: +50 % Perfekt-Bonus, und NUR dann zusätzlich Speed-Bonus.
  Streak zählt nur bei Komplett-Richtig.
- **Edge-Cases:** Startreihenfolge wird serverseitig pro Spieler zufällig
  gemischt; keine Abgabe = aktueller Stand zählt. Rest Standard.

### 2.5 Pixel-Dschungel *(Bild-Enthüllung mit Geld-Verfall — AUFBAU/TEMPO)*

- **Regeln:** Bild startet extrem verpixelt/gezoomt und wird in **8 Stufen
  à 3 s** scharf. Über dem Bild schrumpft der Fragen-Jackpot pro Stufe.
  Antwort jederzeit per MC-4; falsch = 0 + Sperre für den Rest der Frage.
- **Jackpot-Treppen:** MEDIUM 400→50 (−50/Stufe), HARD 800→100
  (−100/Stufe), ULTRAHARD 1.600→200 (−200/Stufe).
- **Handy:** 4 Buttons, jederzeit drückbar; „NOCH WARTEN“-Fläche als
  bewusste Nicht-Aktion. Wer geantwortet hat, sieht die weiteren Stufen
  nicht mehr (Handy verdeckt, Avatar hält sich die Augen zu).
- **Bildschirm:** Bild + sichtbare Geld-Uhr mit aktuellem Jackpot-Stand.
- **Timing:** 24 s Enthüllung + 4 s voll scharf, 6 s Auflösung.
- **Scoring:** MM = Jackpot-Stufe zum Server-Empfangszeitpunkt der
  richtigen Antwort. Kein Speed-Bonus (steckt im Verfall), Streak normal.
- **Edge-Cases:** Stufen-Wertung ist latenztolerant per Design; gleiche
  Stufe = gleiche Punkte. Rest Standard.

### 2.6 Die Stinkbanane *(Buzz: Pass the Bomb — KONFLIKT)*

- **Regeln:** Eine tickende Stinkbanane startet bei einem Zufallsspieler.
  Nur der Halter sieht die aktuelle Frage (MC-4); richtig = Banane wandert
  im Kreis weiter, falsch/zu langsam = festhalten, neue Frage. Platzt sie
  (serverseitig ausgeloster Timer 45–75 s), zahlt der Halter **500 MM ins
  Jackpot-Glas** und sein Avatar trägt Matsch-Spritzer bis Match-Ende.
  2 Durchgänge pro Runde.
- **Handy:** Halter: 4 Buttons + 8-s-Frage-Timer. Alle anderen:
  „ANFEUERN“-Trommel-Button (kosmetisch, triggert Sounds/Konfetti).
- **Bildschirm:** wer hält die Banane (Zoom), lauter werdendes Ticken;
  Explosion mit Matsch-Splatter.
- **Timing:** 8 s pro Weitergabe-Frage; Durchgang endet mit Explosion.
- **Scoring:** jede erfolgreiche Weitergabe (richtige Antwort): +150 MM.
  Explosion: −500 MM (ins Glas). Keine Streak, kein Speed-Bonus.
- **Edge-Cases:** Disconnect des Halters → Banane wandert automatisch
  weiter, keine Strafe. Explosion während Antwort-Übertragung: Antwort mit
  Server-Empfang vor Explosions-Tick zählt noch. 2 Spieler: Ping-Pong,
  funktioniert.

### 2.7 Der Taschendieb-Affe *(Buzz: Point Stealer — KONFLIKT)*

- **Regeln:** MC-4 an alle; die SCHNELLSTE richtige Antwort gewinnt das
  Klau-Recht: geheime Opferwahl auf dem Handy, dann Klau-Cutscene.
- **Klau-Beträge:** MEDIUM-Frage: 300 MM, HARD: 500 MM — gedeckelt auf
  **max. 25 % des Opfer-Kontostands**. Anti-Mobbing: dieselbe Person kann
  nicht 3× in Folge Opfer sein (Server-hart).
- **Handy:** 4 Buttons; Gewinner bekommt 8 s ein Avatar-Grid „Bei wem
  klaust du?“ (Default bei Timeout: reichster Spieler).
- **Bildschirm:** Dieb-Affe mit Maske flitzt zum Opfer-Avatar, haarige
  Affenhand trägt die Scheine rüber (Klauen muss sich wie Klauen anfühlen).
- **Timing:** 15/20 s Frage + 8 s Opferwahl + 6 s Cutscene.
- **Scoring:** Dieb erhält den Klau-Betrag vom Opfer-Konto. Alle anderen
  Richtigen: halber Grundwert aus der Bank (Mitmachen lohnt).
  Keine Streak/Speed auf den Klau.
- **Edge-Cases:** Antwort-Gleichstand <50 ms → „FOTOFINISH“: früherer
  Server-Timestamp klaut, der andere bekommt vollen Grundwert.
  Klau auf Disconnected → automatisch reichster verbundener Spieler.
  2-Spieler-Spiel: Opfer ist automatisch der Gegner.

### 2.8 Die Affenbank *(eigenes Format: Kette + Verrat — GELD-Slot, DIE Signatur-Runde, fix)*

- **Regeln:** Schnellfeuer-MC-4 an alle im 10-s-Takt. Antwortet die
  MEHRHEIT richtig, verdoppelt sich der wachsende Runden-Pott:
  **50 → 100 → 200 → 400 → 800 → 1.600 MM** (Kappe 1.600). Jeder hat
  jederzeit einen fetten roten **„BANK!“**-Button: Wer bankt, schreibt
  sich den aktuellen Pott PERSÖNLICH gut — die Kette startet für alle
  wieder bei 50. Falsche Mehrheit = ungesicherter Pott verbrennt.
- **Handy:** 4 Antwort-Buttons + darüber der rote BANK!-Button mit
  Live-Pottstand.
- **Bildschirm:** Tresor in der Mitte füllt sich; jeder „BANK!“ wird mit
  Namens-Einblendung genüsslich geoutet („TOM SICHERT SICH 400!“).
- **Timing:** 90 s Kette pro Durchgang, 2 Durchgänge pro Runde.
- **Scoring:** nur über BANK! gesicherte Beträge; alle BANK!-Drücker im
  selben 1-s-Fenster sichern denselben Betrag (ein Ketten-Reset).
  Keine Streak/Speed.
- **Edge-Cases:** Disconnect: kein Auto-Bank, gesicherte Beträge bleiben.
  Gleichzeitige Mehrheits-Auswertung: Serverfenster-Ende zählt.
  2 Spieler: „Mehrheit“ = beide richtig.

### 2.9 Alles oder Banane *(Buzz: High Stakes — RISIKO-Slot, fix vorletzte/letzte Runde)*

- **Regeln:** Pro Frage wird NUR Kategorie + Schwierigkeit angeteasert
  („Gleich: Hauptstädte, SCHWER“). Jeder setzt geheim; Reveal ALLER
  Einsätze VOR der Frage („Paul geht ALL-IN bei Mathe?!“), dann MC-4.
  Richtig = Einsatz zurück + gleicher Betrag obendrauf, falsch = Einsatz
  weg (an die Bank, nicht ins Glas).
- **Einsatz:** 100–1.000 MM in 50er-Schritten, gedeckelt auf 50 % des
  Kontostands. „All-in erlaubt“-Toggle in den Match-Settings (Default aus).
  Konto < 100: die Bank stellt 100 MM Gratis-Einsatz („Kredit der
  Affenbank“, wird nicht zurückgefordert).
- **Handy:** Einsatz-Slider in 50er-Rasterung + „EINLOGGEN“; danach
  normale 4 Buttons.
- **Bildschirm:** Einsätze als Geldsäcke vor den Avataren, einzeln
  aufgedeckt mit Trommelwirbel.
- **Timing:** 12 s setzen, 6 s Einsatz-Reveal, 20 s Frage, 8 s Auflösung.
  3 Fragen pro Runde (Quick: 2).
- **Scoring:** ±Einsatz. Keine Streak/Speed.
- **Edge-Cases:** kein Einsatz eingeloggt = Minimum 100 automatisch.
  Disconnect nach Einsatz: Einsatz wird zurückerstattet, Frage zählt als
  keine Antwort. Rest Standard.

### 2.10 Das große Lianen-Finale *(Buzz: Final Countdown — FINALE, fix)*

- **Regeln:** Jeder Affe hängt an einer Liane über dem Krokodil-Fluss;
  Lianenlänge = live normierter Kontostand (Führender 100 %, alle
  proportional, Anzeige-Minimum 25 %). Q Finalfragen (MC-4, alle
  gleichzeitig): richtig = +`W_final` (Ruck nach oben), falsch =
  −`W_final/2` (Riss nach unten, Konto fällt im Finale nie unter 0),
  keine Antwort = 0. **Kein Speed-Bonus, keine Streak, keine Joker** —
  die Formel (3.5) hält exakt. Niemand scheidet aus; das Krokodil schnappt
  nur (Drama). Sieger = höchster Kontostand nach Frage Q.
- **Handy:** nur 4 Antwort-Buttons + eigene Restlänge.
- **Bildschirm:** eigenes Set (Fluss, Lianen, Krokodil), eigene Musik,
  Fallhöhe sichtbar. Vor Frage 1: Ansage des W_final-Werts („Jede Frage
  ist heute 1.050 MM wert!“).
- **Timing:** 12 s pro Frage, 6 s Auflösung; gesamt 4–6 min.
- **Scoring:** siehe Formel 3.5.
- **Edge-Cases:** Gleichstand nach Frage Q → Kokosnuss-Shake um den Sieg.
  Finalist-Disconnect: spielt 0-Antworten, kein Nachrücker (alle sind im
  Finale). Spätantwort Standard. Special Rule „Vabanque-Finale“ (5.4)
  ERSETZT dieses Format inkl. Formel, wenn aktiviert.

### 2.11 Systembausteine (v1, keine eigenen Runden)

- **Kokosnuss-Shake (globaler Tiebreaker):** 3-s-Countdown + 10 s
  Tap-Frenzy auf eine Kokosnuss; clientseitig gezählt, in 1-s-Batches
  gemeldet, Plausibilitätskappe 12 Taps/s. Sieger gewinnt den Gleichstand.
  Batches mit Server-Empfang > Ende +1,5 s werden verworfen; erneuter
  Gleichstand → 3-s-Sudden-Death.
- **Bananen-Buzzer (Buzzer-Modul, nur GM-Show-/Screen-los-Modus):** GM
  liest vor, jedes Handy ist EIN riesiger Bananen-Buzzer (60 % Bildhöhe,
  vibriert bei Freigabe; Frühbuzz = 1,5 s Sperre). Schnellster antwortet
  MÜNDLICH, GM wertet per Richtig/Falsch-Tap. Scoring: Erster & richtig
  Basis ×1,5; falsch gebuzzert −25 % der Basis (fließt ins Jackpot-Glas),
  Buzzer wieder frei für den Rest. Buzz-Zeit = Client-Timestamp, gedeckelt
  auf Server-Zeit −800 ms; <50 ms Differenz = „FOTOFINISH“, beide dürfen
  antworten (früherer Timestamp volle Punkte, der andere die Hälfte).

### 2.12 Die v2-Liste (8 Formate, Kurzbeschreibung)

1. **Flinke Affenfinger** *(Fastest Finger)*: gestaffelte Prämien nach
   Antwort-Reihenfolge (400/300/200/100, skaliert bis 8 Spieler),
   Zieleinlauf-Animation.
2. **Monkey Market / Geld-Regen**: 10 Einsatz-Chips per Drag auf 4
   Antwort-Falltüren verteilen; richtige Tür ×2 zurück, „Alles auf
   eins“ +25 % Mut-Bonus.
3. **Bananen-Bluff** *(Fibbage-Stil)*: Lügen zu obskuren Fakten erfinden;
   wer auf deine Lüge fällt, zahlt DIR (Lügen ist Diebstahl). Min. 3 Spieler.
4. **Bananen-Börse**: Live-Investieren in Antwort-Optionen während der
   Timer läuft; Quote sinkt mit Herdenverhalten (Quote = 3,0 − 1,5 ×
   Anteil, min. 1,2), Abrechnung in 5-s-Kurs-Blöcken.
5. **Affen-Auktion**: 20-s-Auktion um das exklusive Antwortrecht
   (BIETEN +25); richtig = Gebot ×2 zurück, falsch = Gebot wird an alle
   anderen verteilt.
6. **Duell am Lianensteg**: 1v1 Best-of-5 auf dem Hängesteg, Zuschauer
   wetten 50 MM; Sieger 300 MM + 100 vom Verlierer.
7. **Dschungel-Ohren**: Audio-Häppchen (2 s → 4 s → 8 s) mit
   Phasen-Multiplikator ×2/×1,5/×1; Audio nur vom großen Bildschirm.
8. **Königsaffe unter Beschuss**: der Führende verteidigt auf dem Thron
   reihum Fragen der anderen — Rollenumkehr als vorletzte Runde.

Zusätzlich v2: **Der Goldene Affe** (3-Stufen-Wechselfinale) und
**Angeber-Affe** (Bluff-Buzzer mit Wetten) im Backlog.

---

## 3. MONEY-ÖKONOMIE FINAL (verbindliche Zahlen)

Referenzmatch für alle Balancing-Aussagen: 4 Spieler, Klassik (6 Runden +
Finale, ~24 Fragen + 5 Finalfragen), Ziel-Endstand des Siegers
≈ 8.000–12.000 MM. Startkonto: 0 MM.

### 3.1 Frage-Grundwerte, Speed, Streak

| Parameter | Wert |
|---|---|
| Frage EASY | **100 MM** |
| Frage MEDIUM | **250 MM** |
| Frage HARD | **500 MM** |
| Frage ULTRAHARD | **1.000 MM** (max. 2×/Match, immer angekündigt) |
| JACKPOT-Frage | **2.000 MM + Jackpot-Glas** (1×/Match, vor der RISIKO-Runde) |
| Antwortzeit T | EASY/MEDIUM 15 s · HARD 20 s · ULTRAHARD 25 s |

**Speed-Bonus (abgeknickte Gerade, kein Blind-Tipp-Exploit):**
`bonus = wert × 0,5 × clamp((T − t) / (0,8 × T), 0, 1)`
→ volle +50 % nur bei Antwort in den ersten 20 % der Zeit (Lese-Zeit ist
frei), danach linear fallend auf 0. Gilt NUR in Bananen-Basics und als
Perfekt-Zusatz in der Affenleiter; Kokosnuss-Uhr/Pixel-Dschungel haben den
Zeitdruck im Format eingebaut.

**Streak-Multiplikator:** ab 3 richtigen in Folge **×1,5**, ab 5 **×2,0**,
harte Kappe ×2. Gilt auf (Grundwert + Speed-Bonus). Die Streak-Kette
(Bananen-Lunte am Podium) zählt nur in Frage-Formaten (Basics,
Kokosnuss-Uhr, Pixel-Dschungel, Affenleiter-Komplett). Sie **reißt** bei
falscher Antwort, aktivem Pass/Skip UND Timeout ohne Antwort; sie ist
**eingefroren** (reißt nicht) bei Disconnect/AFK. Im Finale keine Streak.

### 3.2 Strafen, Jackpot-Glas, Pleite-Schutz

| Regel | Wert |
|---|---|
| Falsche MC-Antwort (Standard-Formate) | 0 MM, KEINE Strafe (Anti-Frust) |
| Fehlbuzz (nur Buzzer-Modul) | −25 % der Basis → ins Jackpot-Glas |
| Stinkbananen-Explosion | −500 MM → ins Jackpot-Glas |
| Jackpot-Glas Grundfüllung | 500 MM bei Match-Start |
| Weitere Glas-Quellen | abgewiesene Reklamationen (100 MM), Pranger-Geldstrafen |
| Dispo-Limit | **−500 MM hart**, tiefer nie |
| Pfandflaschen-Modus (am Dispo-Limit) | keine Strafen mehr möglich, Gewinne nur zu 75 % |
| Schuldenerlass | vor dem Finale automatisch auf 0 („Privatinsolvenz“, Affen-Anwalt stempelt) |

### 3.3 Wett- & Steal-Regeln

| Mechanik | Regel |
|---|---|
| Wettrunde „Alles oder Banane“ | Einsatz 100–1.000 MM (50er-Schritte), Cap 50 % Konto; richtig +Einsatz, falsch −Einsatz (an die Bank). All-in nur per Toggle. Konto <100: 100 MM Gratis-Einsatz von der Bank. |
| Einsatz-Reveal | IMMER vor der Frage (der Reveal ist der Show-Moment) |
| Steal „Taschendieb“ | 300 MM (MEDIUM) / 500 MM (HARD) vom gewählten Opfer, Cap 25 % des Opfer-Kontos, dieselbe Person nie 3× in Folge Opfer |
| Klau-Schutz | Joker „Bananentresor“ blockt alle Klau-Effekte 1 Runde (Preis 10 % Konto) |
| Money-Sinks (öffentl. sichtbar) | Schmiergeld-Tipp 25 % des Fragenwerts · 50:50 40 % · max. 1 Info-Joker pro Frage |

### 3.4 Underdog-Mechaniken (auto + GM)

| Mechanik | Auslöser | Wirkung |
|---|---|---|
| **Rückenwind** (auto) | >40 % hinter dem Führenden | ×1,25 auf alle Fragen-Gewinne |
| | >60 % hinter dem Führenden | ×1,5 |
| Rückenwind-Kappe | — | Zusatzgewinn kann pro Buchung nie über den Vordermann katapultieren (Aufholen ja, Überholen aus dem Stand nein). Einmalige Ansage, danach dezente Windböen — kein Dauer-Mitleid. |
| **Sozialrabatt** (auto) | untere Tabellenhälfte / Letzter | Joker-Preise −30 % / −50 % („SOZIALRABATT“-Sticker) |
| **Mitleids-Banane** (auto) | vor dem Finale | Letzter erhält einmalig 300 MM (inszeniert als Lacher) |
| **Applaus-Almosen** (auto) | als Einziger falsch | +25 MM „Applaus fürs Mitmachen“ |
| **Banana Bailout** (Rad) | Segment fällt | Letzter: +1 Joker + 15 % des Abstands zum Vorletzten |
| **Letzte-Chance-Anzeige** (auto) | ab 60 % der Show | privater „Pfad zum Sieg“; wenn Sieg unmöglich: Neben-Ziel mit AT-Bonus („Schlag wenigstens Tom: +150 AT“) |
| **Kategorie-Wahl** (auto) | KONFLIKT-Runde | der Letzte wählt die Kategorie |
| **Gönnung vom Boss** (GM) | jederzeit | +300 MM ODER 1 Gratis-Joker ODER ×2 nächste Frage — PFLICHT-Begründungs-Chip („Bester Fehlversuch“, „Mut-Buzzer“ …) erscheint groß am Bildschirm; max. 1 Boost pro Spieler/Runde, nie für Platz 1–2 |

### 3.5 Finale-Aufholbarkeits-Formel (Kernstück)

Vor dem Finale: `G = Konto_Erster − Konto_Letzter`. Bei Q Finalfragen:

```
W_final = max(500, aufrunden(1,25 × G / Q, auf 50er))
richtig  = +W_final
falsch   = −W_final / 2   (Konto fällt im Finale nie unter 0)
keine Antwort = 0
```

- Q = 3 (Quick) / 5 (Klassik) / 7 (Marathon).
- Gewinnt der Letzte alle Q Fragen und der Führende keine, holt er 125 %
  des Rückstands auf → Sieg möglich, aber nur bei perfektem Lauf. Dem
  Führenden reicht EINE richtige Antwort, um die Rechnung zu sprengen.
- Im Finale keine Streaks, kein Speed-Bonus, keine Joker (Formel hält exakt).
- Settings-Knopf: Faktor 1,25 → 1,0 („streng“) oder 1,5 („Chaos“).
- Beispiel (durchgerechnet): Stände 6.800/4.900/3.600/2.700 → G = 4.100,
  Q = 5 → W_final = 1.050. Letzter braucht 5/5 gegen 1/5 des Führenden
  für den Sieg um 100 MM — möglich, episch, selten. Genau richtig.

### 3.6 Match → All-Time-Umrechnung (AT)

| Regel | Wert |
|---|---|
| Jeder Spieler | `AT = Match-Endstand / 10`, mindestens 50 AT |
| Sieger | ×1,5 auf seinen Betrag |
| Erste-Male-Boni (einmalig, keine Farm-Quelle) | erste ULTRAHARD richtig +100 AT · erster Match-Sieg +500 AT · erste gewonnene All-in-Wette +250 AT |
| Richtwert Einkommen | 1 Abend (2–3 Matches) ≈ **2.000–4.000 AT** |
| Übungsmodus | zahlt KEIN AT und kein Level (nur Stats/Meilensteine) |
| Rückrichtung | AT → Match: existiert nicht (einzige Ausnahme: Gutscheine 7.4, per Setting abschaltbar) |

Beispiel Referenzmatch: Sieger 10.000 MM → 1.500 AT; Letzter 2.000 MM →
200 AT.

---

## 4. GM-COCKPIT v1

### 4.1 Fundament

- **Regiepult (3-Zonen-Layout, iPad quer):** Links Live-Status
  (Spielerliste, Score, Antwort-Status, Verbindungs-Ampel) · Mitte
  Bühnen-Spiegel + kontextabhängige Haupt-Aktion („Nächste Frage“,
  „Auflösen“, „Runde beenden“) · Rechts Geheim-Panel + Schnell-Dock
  (6–8 konfigurierbare Buttons). Destruktive Aktionen per
  800-ms-Long-Press mit Füll-Ring statt Dialog.
- **Spickzettel (Geheim-Panel):** korrekte Antwort fett, Fun-Fact zum
  Vorlesen, live einlaufende Spieler-Antworten mit Zeiten, Zahlenstrahl
  bei Schätzfragen, Blur-Toggle gegen Über-die-Schulter-Gucker.
- **Zeitleiste der Wahrheit (Log + Undo):** jede GM-Aktion als Chip,
  Swipe = Undo (wo semantisch möglich), Undo erzeugt öffentliche
  „Korrektur!“-Kachel. Session-Ende: „Regie-Protokoll“ für alle.
- **Ein Kommando-Kanal:** Mensch-GM und Auto-GM feuern identische
  „GM-Commands“ über den Server — eine Logik, ein Log, zwei Betriebsarten
  (Copilot-Modus = v2, Architektur dafür liegt damit bereits).

### 4.2 Die Werkzeug-Liste v1 (17 Werkzeuge) + Auto-GM-Verhalten

| # | Werkzeug | Funktion (Mensch-GM) | Auto-GM-Verhalten |
|---|---|---|---|
| 1 | **Bananen-Bank** (Punkte ±) | Stepper ±50/±100/±500 + Freibetrag; Begründungs-Chip PFLICHT, öffentlich inszeniert; Soft-Cap ±20 % des Runden-Maximums (Override rot geloggt) | vergibt NUR regelbasierte Boni (Underdog, Almosen), nie freihändig |
| 2 | **Zeitmaschine** (Zeit ±/Stopp) | Pause/Weiter, +15 s/+30 s, „Freeze!“ mit Eis-Effekt; max. 2 Verlängerungen/Frage, immer für ALLE | +15 s wenn <50 % geantwortet und Restzeit <5 s (max. 1×); Auto-Pause bei Spieler-Disconnect |
| 3 | **Fragen-Regal** (Frage/Kategorie/Schwierigkeit-Pick) | Regal der nächsten 5 Fragen als Karten: wegwischen, umsortieren, Suche („was mit Fußball für Tom“); Filter Kategorie/Schwierigkeit/nie-gespielt | bestückt nach Kategorien-Rotation + Schwierigkeitskurve; meidet 0-%-Kategorien einzelner Spieler |
| 4 | **Maßanzug-Modus** (per-Spieler-Fragen) | Zuordnungs-Matrix: pro Spieler 3 Vorschläge gleicher Schwierigkeit, per Tap tauschen; Punktwert hängt an der Stufe, nicht an der Einzelfrage | matcht über „Meine Themen“-Tags + Alters-/Trefferquoten-Historie (Familienrunden!) |
| 5 | **Tipp-Kanone & Flüster-Tipp** (global/privat) | global: Hint-Stufe 1/2/3 mit sichtbarem Punktabzug −25 % · privat: Flüster-Blase an EIN Handy, max. 2/Spieler/Runde, Existenz wird am Runden-Ende aufgedeckt | global nach 60 % Zeit, wenn niemand richtig liegt; privat nur an Spieler mit „Unterstützungs-Modus“ |
| 6 | **Gnaden-Automat** (Joker/Skip-Vergabe) | Joker-Palette per Drag auf Spieler oder „Alle“; Session-Budget 6 Chips | Meilenstein-Belohnungen (3 richtige in Folge = 50:50) + stilles Fairness-Werkzeug an Schlusslichter |
| 7 | **Aufholjagd** (Underdog-Boost) | pulsierendes 🐒-Badge am Abgehängten → Boost-Menü (×2 nächste Frage / +300 / Geheim-Joker); öffentlich oder still (stille IMMER am Runden-Ende aufgedeckt); nie Platz 1–2 | aktiviert bei >35 % hinter Median + 2 Runden ohne Gewinn; inszeniert öffentlich |
| 8 | **Publikums-Entscheid** (Votings) | Vorlagen: Kategorie-Wahl, Straf-Ziel, „Frage doof?“, „Pause?“ + Freitext-Voting; beratend oder „bindend“ markierbar | Standard-Mechanik für alle Geschmacksfragen — der Auto-GM ist demokratisch, nie willkürlich |
| 9 | **Roter Buzzer** (Fehlerhaft-Markierung) | Long-Press → Grund → „Punkte annullieren“ oder „Allen geben“ → Ersatzfrage rückt nach; Rollback atomar (Antworten, Punkte, Joker); Frage in Kurations-Queue | markiert automatisch bei >50 % „Frage doof“-Voting, wählt die großzügige Variante |
| 10 | **Rad des Schicksals** (Glücksrad-Trigger) | Dreh-Button; Segment-Pool live muten; 2 Gratis-Re-Spins (danach „Studio-Budget“: alle +50 MM Schweigegeld); „Gezinktes Rad“ (Zielfeld vorwählen) — rot geloggt, im Regie-Protokoll aufgedeckt | Trigger-Heuristik siehe 5.3; zinkt nur im Underdog-Fenster und loggt es genauso |
| 11 | **Bananen-Pause** (Timeout-Screen) | 5/10/15 min oder offen, Pause-Text („Pizza ist da!“); Zwischenstand als Kontoauszug, Gong 60 s vor Ende; Pause = Save-Point | schlägt nach ~45 min von sich aus Pause per Voting vor |
| 12 | **Notausgang** (Skip-Game & Buggy-Flag) | „…“-Menü in jedem Minispiel: überspringen / als fehlerhaft melden (Grund per 1 Tap) / neu starten; erspielte Punkte behalten oder annullieren | erkennt harte Fehlerbilder (keine Zustandsänderung >30 s) und skippt mit Auto-Flag; nach 3 Flags fliegt das Spiel aus der Rotation |
| 13 | **Pranger** (Bestrafungen) | Strafen-Palette: Handy-Erdbeben (5 s Vibration), Clowns-Avatar bis Rundenende, −3 s nächste Frage, Straf-Aufgabe vorlesen, Bananen-Steuer −100 MM (→ Glas); Ziel-Handy zeigt „Ertragen“-Button | bestraft nur regelbasiert und ANGEKÜNDIGT („Wer als Letzter antwortet, zahlt Bananen-Steuer!“); Anti-Mobbing: 2× in Folge Bestrafte sind gesperrt (Server-hart); Familienmodus filtert |
| 14 | **Stimmungs-Barometer** (Feedback einsammeln) | „Blitz-Stimmung“: 3 s lang 5 Emojis auf allen Handys, Verlaufs-Kurve nur im Cockpit (max. 3×/Session); End-Feedback nach der Zeremonie (3 Fragen, „Presse-Stimmen“ im Abspann) | fragt nach jedem 2. Minispiel ab; 2× 🥱 in Folge → Tempo anziehen / Spiel-Wechsel vorschlagen |
| 15 | **Encore!** | +1 Zusatzfrage am Runden-Ende (Vorschau aus dem Regal), max. 2/Runde, normaler Punktwert | triggert, wenn Platz 1 und 2 weniger als eine Fragen-Wertung auseinanderliegen |
| 16 | **Applaus-Knopf** (Soundboard) | 2×4-Grid: Applaus, Trommelwirbel, Fail-Buzzer, „Ohhh!“, Kassen-Kling, Grillen, Konfetti, Blackout (1 s); Rate-Limit 1 Sound/2 s | spielt dieselben Sounds regelgetrieben — das Soundboard IST das akustische Vokabular beider GM-Arten |
| 17 | **Drama-Meter lite** | Spannungs-Score 0–100 (Score-Abstand, Streuung, Tempo-Trend, Restrunden) + genau EIN Empfehlungs-Chip, antippen = Aktion vorbefüllt | dieselben Heuristiken SIND der Auto-GM-Entscheidungskern (führt im Auto-Modus direkt aus) |

Dazu v1: **Regie-Führerschein** (3-min-Pflicht-Tour beim ersten
Cockpit-Start mit Bot-Spielern „Kokos“, „Splitter“, „Banana Joe“ — einmal
Zeit verlängern, Tipp flüstern, Punkte vergeben, roten Buzzer drücken).

**v2 (bewusst nicht in v1):** Regel-Karten-Deck, Copilot-Regie,
Hosentaschen-Fernbedienung, Drama-Meter-Vollausbau, Souffleuse-Modus.

### 4.3 Regie-Presets (Session-Start, live wechselbar ab nächster Frage)

| Preset | Timer | Strafen | Hints | Rad/Karten | Cockpit-Farbe |
|---|---|---|---|---|---|
| **Locker** | lang (+25 %) | aus | großzügig (Auto-Hint bei 50 % Zeit) | Rad selten, nur grüne/blaue Segmente | grün |
| **Gemein** | kurz (−25 %) | aktiv (Bananen-Steuer im Pool) | selten (nur manuell) | Strafen-nahe Segmente rein | rot |
| **Chaotisch** | normal | mild | normal | Rad oft (Cooldown halbiert), Gold-Segmente +50 % Gewicht | lila |

Presets parametrieren die Auto-GM-Heuristiken direkt (eine
Konfigurationsdatei für Mensch und Software). Familienmodus überschreibt
Straf-/18+-Inhalte hart, egal welches Preset.

---

## 5. JOKER / SKIPS / GLÜCKSRAD FINAL

### 5.1 Die v1-Joker (genau 7)

Verfügbarkeits-Modell: **Standard** = kaufbar mit MM (max. 2 gleiche pro
Spieler/Match) · **GM-Chip** = GM kann 1–3 vergeben (sichtbar) ·
**Shop** = NUR Skins/Sounds für Joker, NIE zusätzliche Ladungen.
Sozialrabatt: untere Hälfte −30 %, Letzter −50 %. Max. 1 Info-Joker
(J1 ODER J4) pro Frage. Im Finale sind alle Joker gesperrt.

| # | Joker | Wirkung | Kosten/Verfügbarkeit | Einsatzfenster |
|---|---|---|---|---|
| J1 | **Bananen-Split** (50:50) | Affenhand reißt 2 falsche Optionen ab | 40 % des Fragenwerts; 1 Gratis-Ladung zum Start | während MC-Frage, vor eigener Abgabe; nicht bei 2-Optionen-Fragen |
| J2 | **Überziehungskredit** (Zeit+) | +10 s auf den laufenden Timer (in Minispielen +5 s); in den Dispo-Sekunden KEIN Speed-Bonus | 150 MM flat | jede Timer-Frage, max. 1×/Frage |
| J3 | **Goldene Banane** (Doppel) | nächste Frage: Gewinn ×2 UND Strafen ×2; App zieht die Frage heimlich eine Schwierigkeitsstufe höher („Gold kostet Mut“) | 1× pro Match GRATIS für jeden, keine Nachkäufe | vor Anzeige der Frage (nach Kategorie-Reveal) |
| J4 | **Schmiergeld** (Tipp-Kauf) | Stufe 1: eine falsche Option weg (25 %) · Stufe 2: Anfangsbuchstabe/Themen-Hinweis (35 %) — Inhalt nur aufs Handy, der Kauf ist öffentlich (Geldschein unterm Tisch) | 25 % / 35 % des Fragenwerts, unbegrenzt oft | während der Frage, vor Abgabe |
| J5 | **Rückgaberecht** (Zweitantwort) | nach falscher Antwort sofort 2. Versuch (falsche Option gesperrt), Gewinn nur 50 % — gilt auch auf der Jackpot-Frage: Zweitversuch zahlt den HALBEN Jackpot (1.000 statt 2.000; knackt er das Glas, gibt es nur die Hälfte des Inhalts, der Rest bleibt drin) | 50 % des Fragenwerts, max. 1×/Frage | 3-s-Kauffenster im Moment der Falsch-Aufdeckung; nicht bei 2 Optionen |
| J6 | **Bananentresor** (Klau-Schutz) | Passiv-Schild 1 Runde: alle Klau-Effekte (Taschendieb, Rad-Raub, Affensteuer 1×) prallen ab — Dieb-Affe mit Sternchen | 10 % des eigenen Kontostands (progressiv); Cooldown: nicht 2 Runden in Folge | zwischen Fragen, wirkt bis Rundenende |
| J7 | **Portfolio-Umschichtung** (Kategorie-Tausch) | eigene Solo-/Maßanzug-Kategorie abwerfen, Wahl aus 2 ZUFÄLLIGEN Ersatz-Kategorien gleicher Stufe | 1× pro Match gratis, 2. Ladung 300 MM | nach Kategorie-Reveal, vor der Frage |

v2-Joker: Affenrat (Mitspieler-Voting mit „Verlogener Affenrat“-Option),
Versicherungspolice (Falsch-kostet-nix).

### 5.2 Skip-Varianten (v1: drei bewusst verschiedene Werkzeuge)

| Skip | Wer | Wann | Kosten | Effekt |
|---|---|---|---|---|
| **„Nächster Kunde bitte!“** (Frage-Skip) | einzelner Spieler | während der eigenen Frage | 25 % des Fragenwerts, max. 2×/Match; zählt NICHT als Streak-Bruch-Fehler, reißt die Streak aber (aktiver Pass) | Ersatzfrage gleicher Stufe+Kategorie MUSS beantwortet werden (kein Skip auf den Skip) |
| **„Streik!“** (Minispiel-Skip) | Gruppe (Mehrheit) | in der Erklärkarten-Phase vor Minispiel-Start | gratis, ABER der Minispiel-Pot verfällt ersatzlos | Minispiel entfällt, ersatzweise 1 Blitzfrage für alle; Streik-Rate ist Kurations-Signal im Dashboard |
| **„Reklamation“** (Frage buggy) | einzelner Spieler | während/direkt nach einer Frage | GRATIS (Fairness kostet nie Geld); abgewiesene Reklamation: 100 MM „Bearbeitungsgebühr“ → Glas | GM entscheidet sofort (annullieren+Ersatz / abweisen), ohne GM Gruppen-Voting; Rollback atomar; Frage in Kurations-Queue, nach 2 Flags matchübergreifend deaktiviert |

v2-Skips: Marktflucht (Kategorie-Neudreh per Gruppentopf), Vertagen
(Wiedervorlage-Korb).

### 5.3 Das Glücksrad v1 (14 Segmente mit Gewichten)

Das Rad dreht ZWISCHEN Runden (nie mitten in einer Frage). Es rendert pro
Dreh ~10 Segmente, bestückt aus den gerade KOMPATIBLEN Segmenten gemäß
Gewicht — „gilt hier nicht“-Ergebnisse existieren nicht.

| # | Segment | Klasse | Gewicht | Wirkung exakt |
|---|---|---|---|---|
| 1 | **Doppelter Zaster** | grün | 13 % | nächste Frage: Gewinne ×2, Verluste normal |
| 2 | **Halbe Miete** | grün | 13 % | nächste Frage: Antwortzeit halbiert (Timer wird sichtbar durchgesägt) |
| 3 | **Banana Bailout** | grün | 13 % | Letzter: +1 Joker (50:50) + 15 % des Abstands zum Vorletzten; Geldkoffer-Fallschirm |
| 4 | **Dividende** | blau | 7 % | Rest der Runde: +5 % Zins auf den Kontostand pro richtiger Antwort (reich wird reicher — bewusst) |
| 5 | **Insider-Tipp** | blau | 7 % | ein Zufallsspieler sieht die nächste Frage 3 s früher; Bildschirm zeigt nur „Jemand hat einen Insider-Tipp …“ |
| 6 | **Inflation!** | blau | 7 % | Rest der Runde: −3 % Kontostand pro Frage-Ende (min. 50 MM); dreht automatisch neu, wenn jemand unter 200 MM liegt |
| 7 | **Affentheater** | blau | 7 % | nächste MC-Frage: Bildschirm-Reihenfolge ≠ Handy-Reihenfolge; es zählt der TEXT auf dem eigenen Handy |
| 8 | **Börsen-Roulette** | blau | 7 % | jeder wählt blind Long/Short (5 s): richtig+Long +150 %, richtig+Short +50 %; falsch+Long −100 MM, falsch+Short ±0 |
| 9 | **Umarmungs-Bonus** | blau | 7 % | 15 s: real umarmen + beide drücken „Umarmt!“ → je +50 MM (Fremden-Lobby: High-Five-Emote) |
| 10 | **Steuerprüfung** | blau | 7 % | Führender muss die nächste Frage richtig haben, sonst zahlt er 10 % Kontostand in einen Pott, den der Fragen-Gewinner kassiert |
| 11 | **Blackout im Studio** | gold | 3 % | nächste Frage NUR auf den Handys, Bildschirm zeigt Sendeausfall-Testbild (verdächtige Stille als Feature) |
| 12 | **Affen-Tausch-Börse** | gold | 3 % | SOFORT: alle tauschen Kontostand mit dem Sitznachbarn (Lobby-Reihenfolge); GESPERRT in den letzten 2 Runden + Finale |
| 13 | **Der Affe würfelt** | gold | 3 % | Bot-Affe rät die nächste Frage mit; wen er schlägt, der zahlt 50 MM „Schmach-Gebühr“ in den Pott der nächsten Frage |
| 14 | **Kompliment-Konto** | gold | 3 % | Rad bestimmt A und B: A macht B binnen 20 s ein ernstes Kompliment (Gruppen-Vote bestätigt) → beide +50 MM; Verweigerung: B bekommt 50 von A |

Summe 100 %. **Alkohol-Edition (18+):** Segment 14 wird ersetzt durch
**„Shot oder Schotter“** (langsamste richtige Antwort der letzten Frage
wählt: Shot trinken +50 MM Mut-Prämie ODER 100 MM Feigheits-Steuer);
das Segment existiert außerhalb der Edition GAR NICHT auf dem Rad.

**Rad-Regeln:**
- **Pech-Schutz:** dasselbe Segment nie 2× hintereinander.
  **Pity-Timer:** nach 4 Drehs ohne Gold +2 % Gold-Chance pro Dreh.
- **Fair-Finale-Pool** (letzte 2 Runden + vor Finale): nur Segmente
  1, 2, 3, 5, 9, 11 — keine Umverteilung mehr kurz vor Schluss.
- **Dreh-Inszenierung (max. ~12 s, „Kurze Show“-Setting: 6 s):**
  Vinyl-Stopp + Handy-Vibration → Rad fährt auf (Handys zeigen „ALLE
  AUGEN AUF DEN BILDSCHIRM“) → 3–5 s Dreh mit glaubwürdiger
  Slow-down-Kurve (in ~30 % der Drehs choreografiertes Beinahe-Ergebnis)
  → Einschlag (Gold: Konfetti-Kanonen; negativ: Basston + hämisches
  Affenlachen) → Erklärkarte: EIN Satz Wirkung, betroffene Spieler
  namentlich, kompakt auch auf allen Handys.
- **Auto-GM-Trigger-Heuristik:** (1) fixer Beat: 1 Dreh pro
  Runden-Wechsel ab R2; (2) Langeweile-Detektor: ≥4 Fragen ohne Rad UND
  ohne Führungswechsel → 80 % Dreh; (3) Blowout-Bremse: Abstand P1–P2
  >35 % der Ø-Rundenausbeute → Dreh mit erhöhtem Gewicht auf
  Bailout/Steuerprüfung/Inflation; (4) Cooldown: nie 2 Drehs binnen 2
  Fragen, Max ~1 Dreh pro 3–4 Fragen; (5) GM-Trigger überschreibt alles
  und resettet den Cooldown.

### 5.4 Special Rules (8 zuschaltbare Match-Regeln)

Toggles bei der Match-Erstellung; aktive Regeln als Icon-Leiste dauerhaft
am Bildschirmrand. Presets: **Klassisch** (keine) · **Casino** (SR1+SR5) ·
**Chaos-Affen** (SR4+SR8) · **Hardcore** (SR2+SR3).

| # | Regel | Wirkung |
|---|---|---|
| SR1 | **Vabanque-Finale** | ERSETZT das Lianen-Finale: vor der letzten Frage setzt jeder VERDECKT 0–100 % seines Kontos auf die eigene Antwort; richtig = Einsatz ×2, falsch = weg; Einsätze werden NACH der Antwort einzeln aufgedeckt (Jeopardy-Spannung). Pflicht-Finale im Screen-los-Modus. |
| SR2 | **Pleitegeier** | 3 falsche Antworten IN FOLGE → Geier frisst 20 % des Kontos (nie alles); Zähler als 3 Geier-Silhouetten sichtbar; Reset durch jede richtige Antwort; Skips zählen nicht als Fehler |
| SR3 | **Notariats-Runde** | 1 angekündigte Runde: keine Joker, keine Tipps, keine Zurufe („PSST!“-Overlay, Bibliotheks-Ästhetik); Fragenwerte +25 % als Kompensation |
| SR4 | **Affensteuer** | Runden-Ende: Führender zahlt 10 % in eine sichtbare Bananenkiste; Ausschüttung am Match-Ende an den Gewinner der letzten Frage. Bananentresor (J6) blockt genau eine Zahlung |
| SR5 | **Kopfgeld auf den Boss** | wer länger als 1 Runde führt, bekommt einen WANTED-Steckbrief: wer ihn in einer Direktsituation schlägt, kassiert 200 MM Prämie AUS DER BANK (kein Klau) |
| SR6 | **Kapitalismus-Gong** | 1× pro Match: Führender +10 % Zins, Letzter gleichzeitig +20 % des Median-Kontos „Grundeinkommen“ — fühlt sich skandalös an, verschiebt netto wenig |
| SR7 | **Die Bananenschale** | vor der letzten Frage jeder Runde (nicht Finale): optional den GESAMTEN Rundengewinn setzen — richtig ×2, falsch weg (Schaden max. eine Runde Arbeit; attraktiver für Zurückliegende) |
| SR8 | **Flohmarkt der Flüche** *(v2-Nachzügler)* | jeder zieht pro Runde ein mildes Zufalls-Handicap (Spiegelschrift, Timer −15 %, zufällige Antwort-Reihenfolge …), alle gleichzeitig, max. ~10 % Effektstärke — Umsetzung nach v1-Launch |

---

## 6. MODI-MATRIX

Alle Modi sind intern **Presets über derselben Engine** (Settings-Matrix +
Preset-System zuerst bauen, dann ist die Palette fast gratis). Presets
speicherbar + teilbar als 6-stelliger Code/QR (v1: lokal speichern,
Share-Codes v2).

### 6.1 Settings-Matrix (Custom Game = „Kreditvertrag“, den der Host unterschreibt)

| Setting | Optionen | Default (Klassik) |
|---|---|---|
| Rundenzahl | 2–10 (Live-Zeitschätzung „≈ 34 min“) | 6 |
| Zeit pro Frage | 10 / 15 / 20 / 30 s / Gemütlich (60 s) | nach Schwierigkeit (15/20/25) |
| Kategorien-Pool | Multi-Select + „Überraschung“ | Alle |
| Schwierigkeits-Kurve | Sparbuch (flach leicht) / Aktienfonds (ansteigend) / Krypto (chaotisch) / ULTRAHARD-Endgame | Aktienfonds |
| Joker | An / Aus / Nur 1 pro Match | An |
| Glücksrad | Jede Runde / Nur vor Finale / Aus | Jede Runde (ab R2) |
| Bestrafungen | Aus / Mild / Party / Eigene Liste (bis 10 Freitext-Aufgaben, pro Gruppe gespeichert) | Mild |
| Special Rules | 8 Toggles (5.4) + Presets | Klassisch (keine) |
| All-Time-Items im Match | An / Aus | An; AUTO-AUS sobald ein Gast ohne Historie in der Lobby ist |
| Regionsfokus | DE-Anteil 0–100 % (Pool-Größen-Warnung bei < 3× Fragenbedarf) | Mix 50/50 |
| 18+ | Aus / Alkohol-Events | Aus |
| Finale-Faktor | 1,0 streng / 1,25 / 1,5 Chaos | 1,25 |

### 6.2 Die Modi (was ist anders)

| Modus | Runden/Länge | Abweichungen von Klassik |
|---|---|---|
| **Quick Cash** | 4 + Finale (Q=3), ~15–20 min | Ein-Tap-Start, Defaults fest, kein Setup-Screen; Joker AUS, 1 Rad-Dreh, keine Jackpot-Frage, ULTRAHARD max. 1; Endscreen bietet „Nochmal“ + „Custom Game bauen“ |
| **Klassik-Show** | 6 + Finale (Q=5), ~40 min | Der Default. 3-Akt-Dramaturgie, alle Systeme an |
| **Marathon** | 9 + Finale (Q=7), ~60–75 min | „Handelstag“-Rahmung, Halbzeit-Pause mit Kurscharts, Auto-Save nach jeder Runde Pflicht, 2. Schätzrunde mit HARD-Festwerten |
| **Custom** | 2–10 Runden | volle Settings-Matrix (6.1), speicherbar als Preset |
| **Übungsmodus „Trainingslager“** | endlos, solo | komplett auf dem Handy (kein Bildschirm/Raum); Freies Training / Schwächen-Training (bevorzugt schwache Kategorien) / Tages-Challenge (10 Fragen, lokale Freundes-Bestenliste); zahlt NUR in Stats & Meilensteine ein — kein MM, kein AT, kein Level |
| **Alkohol-Edition „Zinsen & Shots“ (18+)** | wie Basis-Modus | Opt-in PRO SPIELER (Beifahrer-Modus: nimmt nie an Trink-Events teil, Ersatz: Grimasse/−100 MM); Shots NIE an den Letzten allein, nur über Ereignisse („alle, die Frage 3 falsch hatten“, „der Führende gibt einen aus“, Rad „Shot oder Schotter“); hartes Limit Default 6 Trink-Events/Match; nach jedem 2. Event 10-s-Wasser-Break (nicht wegklickbar) |
| **Familien-Modus** | wie Basis-Modus | pro Spieler Profil „Kind“/„Erwachsen“: gleiche Kategorie, altersgerechter Pool (Maßanzug-Modus) → Punkte vergleichbar; Bestrafungen + 18+ hart deaktiviert; Timer +50 %; Rad ohne Tausch-Börse/Steuerprüfung |
| **Screen-los „GM-Show“** | wie Basis-Modus | GM-Gerät = Regiepult UND Bühne (souffliert: Frage + Antwort + Regieanweisung), GM liest laut vor; Buzzer-Modul als Kern-Format (Handys = Riesen-Buzzer, mündliche Antwort, GM wertet); Antwortoptionen erscheinen erst NACH dem Vorlesen auf den Handys; Zwischenstände/Rad als „Alle Handys hoch!“-Vollbild-Moment; Format-Pool: Basics, Buzzer, Kokosnuss-Uhr, Tresor, Leiter, Affenbank, Alles oder Banane; Finale = Vabanque (SR1 auto-aktiv); ohne GM: rotierender Vorleser („Praktikant an der Börse“, erhält Durchschnittspunkte) |

### 6.3 Session-Komfort (alle Modi)

- **Spät-Joiner:** sofort Zuschauer (tippt mit, Schattenpunkte,
  Emoji-Reaktionen); Einstieg zur nächsten Runde nach Host-Okay mit
  MEDIAN-Kontostand; Endscreen-Sternchen „eingestiegen Runde 3“; Hard-Cap
  8 Spieler.
- **Disconnect-Eskalation:** <60 s: Platz reserviert, nahtloser Rejoin ·
  länger: eingefroren, Match läuft ungebremst weiter · aktives Verlassen:
  Kontostand wird „Insolvenzmasse“ im Pott des nächsten Rad-Drehs
  (Rückkehr: halbe Masse zurück).
- **Auto-Save:** nach jeder abgeschlossenen Runde (nie mitten in einer
  Frage; angerissene Frage wird beim Laden NEU gestellt). Ein Slot pro
  Raum, 7 Tage Haltbarkeit. Beim App-Start: „Weiterspielen?“-Karte mit
  Wiedererkennungs-Avataren.
- **Rematch:** REVANCHE-Button (3-2-1, kein neuer Raumcode) + Rache-Modus
  (Letzter ändert 1 Setting, öffentlich).
- **Barrierefreiheit pro Spieler (nicht pro Match):** +50 % Bedenkzeit
  (still gepuffert, für andere unsichtbar), hoher Kontrast,
  farbenblind-sichere Antwortfarben (Farbe+Symbol immer gemeinsam).

---

## 7. META v1

### 7.1 Profile

- **Frictionless:** Name + Affen-Avatar, unter 10 s, kein Account/E-Mail.
  Stabile `profile_id` (UUID), Name jederzeit änderbar. Optionale
  4-stellige PIN als Schloss.
- **Geräte-Wiedererkennung:** `device_token` im localStorage →
  „Willkommen zurück — als wer spielst du heute?“ mit Ein-Klick-Kacheln.
  Mehrere Profile pro Gerät; Geräte-Wechsel per 6-Zeichen-Claim-Code.
- **Gast-Modus:** Auto-Name („Gast-Gibbon #3“), taucht in
  Match-Ergebnissen auf, nicht in All-Time-Boards; am Match-Ende
  „Diesen Abend behalten?“ → Adoption in echtes Profil inkl. Stats.
- **Spielerkarte:** Avatar, Titel, Lieblings-Kategorie,
  Nemesis-Kategorie („Erzfeind: Geografie 🙈“), schnellster Buzz,
  höchster Match-Gewinn, längste Serie.
- **Privacy:** alles lokal auf dem Host-Server; Profil-Export (JSON/ZIP),
  zweistufige Löschung (Anonymisieren mit Tombstone / vollständig),
  keinerlei Telefonie nach außen.

### 7.2 Stats-Katalog (die wichtigsten 15, alle aus dem Event-Log abgeleitet)

1. Richtig-Quote gesamt (+ pro Match)
2. Genauigkeits-Matrix Kategorie × Schwierigkeit (Heatmap; Zellen mit
   <10 Antworten ausgegraut)
3. Median-Antwort-/Buzz-Zeit (+ Trend)
4. Schnellster Buzz aller Zeiten
5. Aggressivitäts-Index (Anteil Früh-Buzzes + „gebuzzert, aber falsch“-Quote
   → Archetypen „Scharfschütze“ vs. „Kanone“)
6. Matches gespielt / gewonnen (Win-Rate)
7. Lifetime-AT-Einnahmen (= Level-Basis)
8. Höchster Einzel-Match-Endstand
9. Längste Richtig-Serie (auch matchübergreifend)
10. Längste Sieges-Serie (Matches)
11. Joker-Effizienz (Richtig-Quote mit vs. ohne Joker; „Deine 50:50 retten
    dich in 71 %“)
12. Wett-Bilanz (gewonnene/verlorene Einsätze, größter Einzel-Wettgewinn)
13. Klau-Bilanz (gestohlen vs. bestohlen, in MM)
14. Comeback-Zähler (Siege, wenn vor dem Finale nicht Platz 1)
15. Lieblings- & Nemesis-Kategorie (höchste/niedrigste Quote ab 20 Antworten)

### 7.3 Bestenlisten (genau 4, mit Fairness-Schwellen)

| Board | Metrik | Schwelle |
|---|---|---|
| **Money-Boss** | Lifetime-AT-Einnahmen | — |
| **Kategorie-Meister** | beste Quote je Kategorie | ≥ 20 Antworten in der Kategorie |
| **Blitz-Buzzer** | MEDIAN-Buzz-Zeit (kein Glücks-Bestwert) | ≥ 30 gewertete Buzzes/Antworten |
| **Comeback-König** | Win-Rate nur aus Matches ohne Führung vor dem Finale | ≥ 5 solcher Matches |

Anzeige-Orte: (1) Lobby-Karussell (Anwesende hervorgehoben), (2)
Match-Ende NUR Deltas („Platz 3 → 2!“), (3) eigene Board-Seite mit
Filtern. Schwellen werden transparent angezeigt („dir fehlen noch 3
Matches“). Board-Spitzen tragen automatische Titel („💰 Money-Boss“,
„⚡ Blitz-Buzzer“ …), die beim Überholen wandern. Parallel-Ebene:
persönliche Rekorde werden am Match-Ende gleichwertig gefeiert.
Nur lokal/Freundesgruppe — keine globalen Boards.

### 7.4 Shop-Sortiment v1 (20 Items) + Regeln

Seltenheits-Stufen (rein kosmetisch): Grüne Banane 500–1.000 AT · Reife
Banane 2.000–4.000 · Goldbanane 5.000–15.000 · Diamant-Banane 25.000.

| # | Item | Typ | Preis (AT) |
|---|---|---|---|
| 1 | Buzzer-Sound „Entenquak“ | Sound | 500 |
| 2 | Buzzer-Sound „Dial-up-Modem“ | Sound | 750 |
| 3 | Buzzer-Sound „Opern-Aaah“ | Sound | 750 |
| 4 | Buzzer-Sound „Furz Deluxe“ | Sound | 1.000 |
| 5 | Kopf „Zylinder“ | Accessoire | 500 |
| 6 | Kopf „Bananen-Helm“ | Accessoire | 1.000 |
| 7 | Gesicht „Monokel“ | Accessoire | 500 |
| 8 | Gesicht „3D-Brille“ | Accessoire | 750 |
| 9 | Hand „Kaffeetasse“ | Accessoire | 500 |
| 10 | Hand „Mini-Buzzer“ | Accessoire | 1.000 |
| 11 | Titel „Bananen-Baron“ | Titel (Spaß, kaufbar) | 500 |
| 12 | Titel „Buzzer-Berserker“ | Titel (Spaß, kaufbar) | 1.000 |
| 13 | Sticker-Pack „Börsen-Panik“ (8 Taunts) | Sticker | 1.500 |
| 14 | Konfetti-Stil „Bananen-Regen“ | Money-Regen | 2.000 |
| 15 | Konfetti-Stil „8-Bit-Scheine“ | Money-Regen | 3.000 |
| 16 | Fell-Muster „Leopard“ | Avatar | 3.000 |
| 17 | Fell-Muster „Neon“ | Avatar | 4.000 |
| 18 | Spezies „Orang-Utan“ | Avatar | 6.000 |
| 19 | Spezies „Pavian“ | Avatar | 6.000 |
| 20 | „Hologramm-Affe“ (animiert) | Avatar legendär | 25.000 |

**Gratis ab Minute 0 (auch Gäste):** 8 Affen-Avatare × 6 Farben, 4
Buzzer-Sounds, Standard-Konfetti, Theme „Dschungel“, 1
Sticker-Basispack. Gäste/Neue dürfen zusätzlich die komplette
Grüne-Banane-Garderobe für die Session LEIHEN („geliehen“-Schildchen).

**Shop-Regeln (Verfassungsrang):** Kein Echtgeld. Kein gekauftes Item
verändert Punkte/Zeiten/Fragen — einzige Ausnahme:
**Modifier-Gutscheine** (50:50-Gutschein 300 AT, Rad-Neudreh 200 AT),
max. 1 pro Spieler pro Match, öffentlich angekündigt, im Finale verboten,
global abschaltbar über „All-Time-Items: AUS“ (Auto-AUS bei Gast in der
Lobby). Anti-Dark-Pattern: Preise zusätzlich in Spielabenden angezeigt
(„8.000 AT ≈ 2–3 Abende“), keine Countdown-Timer, kein „nur heute“,
Kauf-Button zeigt Kontostand vorher/nachher, 24-h-Rückgaberecht
(ungetragen). Taunt-Sticker: max. 3 pro Spieler/Match, nur in
Auflösungs-/Pausenfenstern, empfängerseitig stummschaltbar.
Kauf-Inszenierung: jede gekaufte Banane wird geschält (Schäl-Dauer nach
Seltenheit; Diamant = Bühnen-Blackout + Spotlight für die ganze Lobby).

### 7.5 Unlock-Regeln

- **Level = Lifetime-AT-Einnahmen** (kein zweites XP-System): Level n bei
  `1.000 × n × (n+1) / 2` Lifetime-AT (L5 ≈ 15.000, L20 ≈ 210.000).
  Ausgeben/Spenden kostet nie Level. Jeder Level-Up = EIN Gratis-Item
  nach Wahl aus einem 3er-Angebot (2× Grün, 1× Reif).
- **Erste-Male-Kette (Session 1–3):** sichtbarer 6-Schritte-Pfad („Erste
  richtige Antwort“, „Erster Buzz“, „Erstes Match“, „Erster Sticker“ …),
  jeder Schritt = 1 Gratis-Grün-Item SOFORT. Ziel: Neuling verlässt
  Session 1 mit eigenem Buzzer-Sound, Hut und ~500 AT.
- **Meilenstein-Unlocks (unkaufbar):** 100 richtige Antworten → Badge
  „Grundgelehrter“; erster Jackpot → Buzzer-Sound „Kaching-Kaskade“;
  einziger Richtiger bei ULTRAHARD → Titel „Die 1000er-Legende“;
  5 Matches mit derselben Gruppe → Gruppen-Rahmen; Comeback-Sieg →
  Badge „Comeback-König“. App zeigt immer, ob ein Titel gekauft oder
  verdient ist.
- **v2:** Season-Soft-Reset auf `100 × √(AT/100)` + Prestige-Rahmen,
  Kategorie-Mastery-Tracks, Vault/Antiquitäten-Stand, Streuner-Affe,
  Geschenke.

### 7.6 Analytics-Reports (die 5 wichtigsten, Admin-Dashboard)

1. **Fehlerhaft-Queue:** geflaggte Fragen mit Grund, Flag-Zahl,
   GM-Kommentaren; Workflow Neu → In Prüfung → Korrigiert/Verworfen; ab
   2 Flags automatisch aus der Rotation.
2. **Schwierigkeits-Drift:** markierte Stufe vs. gemessene Quote (je
   Spielmodus getrennt, ab ≥ 20 Ausspielungen) → sortierte
   Umstufungs-Vorschläge mit Annehmen/Ablehnen (Entscheidungen geloggt).
3. **Abnutzungs-Report:** Ausspiel-Zähler pro Frage; Auto-Cooldown ab 3×
   in 60 Tagen in derselben Gruppe; Ein-Klick-Reaktivierung. Dazu
   „Frage der Schande“ (0-%-Quote = fast immer kaputt).
4. **Kategorie-Lücken-Report:** Matrix Kategorie × Schwierigkeit mit
   Vorrat, Verbrauchsrate und Reichweiten-Prognose („Sport/Schwer: noch
   ~2 Abende“) → verlinkt auf „Neue Frage anlegen“.
5. **Show-Gesundheits-Report:** Streik-Raten pro Minispiel,
   Skip-/Reklamations-Raten, Blitz-Stimmungs-Kurven (wann kippte die
   Stimmung, nach welchem Spiel/Tool), End-Feedback-Cluster per
   Keyword-Regeln („7× ‚Fragen wiederholen sich‘“).

---

## 8. V1-SCOPE-VERTRAG

### 8.1 MUST — das hat v1 zwingend

**Kern-Loop:**
- Lobby (Raumcode/QR, Profile, Gäste, „Meine Themen“), Opening,
  Runden-Engine mit Slot-Dramaturgie, Glücksrad-Beats, Jackpot-Frage,
  Lianen-Finale mit Aufhol-Formel, Siegerehrung (3 Podeste + Awards +
  Kontoauszug), End-Feedback, Revanche.
- Die **10 v1-Minispiele** (2.1–2.10) + Kokosnuss-Shake +
  Bananen-Buzzer-Modul.
- Modi: **Quick, Klassik, Marathon, Custom (Settings-Matrix + lokale
  Presets), Übungsmodus, Alkohol-Edition, Familien-Modus,
  Screen-los-Modus** — alle als Presets über einer Engine.
- **Team-Modus „Affenbanden“** (2er-Teams) mit Flüster-Timer +
  Doppel-Buzzer; Ansage-Momente.

**Ökonomie:** Fragewerte 100/250/500/1.000, Jackpot 2.000+Glas,
Speed-Knick-Formel, Streak ×1,5/×2 (Cap ×2), Dispo −500 +
Pfandflaschen-Modus + Schuldenerlass, Wett-/Steal-Regeln, alle
Underdog-Mechaniken aus 3.4, Finale-Formel, AT-Umrechnung.

**Systeme:**
- 7 Joker, 3 Skips, 14-Segment-Glücksrad mit Gewichtung/Pech-Schutz/
  Pity-Timer/Fair-Finale-Pool/Inszenierung, 7 Special-Rule-Toggles
  (SR1–SR7).
- GM-Cockpit mit den 17 Werkzeugen aus 4.2 + Regie-Presets +
  Regie-Führerschein; Auto-GM mit denselben Commands und den
  dokumentierten Heuristiken; Auto-GM-Moderation als Text-Banner +
  Soundboard (kein TTS).
- Ein gemeinsames „Consumable“-Datenmodell für Joker/Skips/GM-Chips
  (id, Besitzer, Ladungen, Einsatzfenster, Preisformel, Bildschirm-Event).
- **Event-Log als Single Source of Truth** (append-only, injizierte
  Clock/RNG), Stats/Boards/Analytics als Ableitungen; Replay-fähig.
- Meta: Profile + Geräte-Wiedererkennung + Gast-Adoption, 15 Stats,
  4 Bestenlisten, Shop mit 20 Items + Startausstattung + Leih-Garderobe +
  Level/Erste-Male/Meilensteine + Anti-Dark-Pattern-Charta,
  5 Analytics-Reports, Profil-Export/-Löschung.
- Session-Komfort: Spät-Joiner, Disconnect-Eskalation, Auto-Save
  (1 Slot/Raum, 7 Tage), Pause-Screen, Rematch, Barrierefreiheit-Basics
  (Bedenkzeit-Bank, Kontrast, Farbe+Symbol).

### 8.2 NICHT in v1 (ehrlich)

- KEIN Echtgeld, keine Käufe, keine Lootboxen (auch nie in v2+).
- Keine Cloud-Accounts, keine globalen Bestenlisten, kein Online-Matchmaking
  — alles lokal beim Gastgeber.
- Keine App Clips (WKWebView-Wrapper-App für den iPad-Bildschirm statt
  dessen); Spieler-Handys laufen im Browser.
- Keine weiteren Team-Modi (Affenkönig, 4v4-Clash, Schlange/Verräter,
  Stellvertreter-Krieg), keine 1v1-Duell-Einlagen, kein Turnier-Bracket.
- Keine Audio-/Video-Fragen (Dschungel-Ohren = v2), keine
  Freitext-Eingabe-Spiele (Bananen-Bluff = v2), kein Monkey Market,
  keine Bananen-Börse, keine Affen-Auktion.
- Kein Season-System, kein Prestige, kein Vault, keine Geschenke, kein
  Streuner-Affe, keine Mastery-Tracks.
- Kein Regel-Karten-Deck, kein Copilot-Regie-Modus, keine
  GM-Fernbedienung, kein Drama-Meter-Vollausbau, kein Souffleuse-Modus,
  kein „Rigging“-Knopf über das gezinkte Rad hinaus.
- Kein TTS (Auto-GM moderiert per Banner+Sound), keine EN-Lokalisierung,
  keine Vorlese-Barrierefreiheit.
- Keine Video-Cutscenes/Remotion-Trailer, kein Highlight-Reel, keine
  Bildschirm-Themes außer „Dschungel“, keine Einlauf-Animationen/Sieg-Posen.
- Keine adaptive Fragenauswahl (Rubberband über Fragen, I-23), keine
  Head-to-Head-Rivalen-Historie, keine alternativen Zufalls-Events
  (Money-Koffer, Affen-Alarm, Börsencrash-Event, Goldene-Banane-Blitz).
- Kein Save/Load über den Auto-Save hinaus (kein Turnier-Speicher,
  keine parallelen Slots).

### 8.3 v2-Vision (10 Punkte)

1. **Der komplette Team-Abend:** Affenkönig (alle gegen den Führenden),
   Dschungel-Clash 4v4, „Die Schlange“ (Social Deduction),
   Bananen-Duell-Fenster + Thron-Anfechtung, Affen-Galerie mit
   Zuschauer-Wetten.
2. **8 neue Formate** (2.12) + „Der Goldene Affe“ als
   3-Stufen-Wechselfinale und Flinke Affenfinger als Opener-Variante.
3. **Turnier & Liga:** Bracket über mehrere Quick-Matches,
   Saboteur-Karten für Ausgeschiedene, persistenter Turnier-Speicher
   über mehrere Abende, Session-Abspann mit teilbarem 9:16-Kontoauszug.
4. **Regie-Ausbau:** Copilot-Modus (Auto-GM schlägt vor, Mensch drückt
   ab), Regel-Karten-Deck, Drama-Meter voll, Souffleuse,
   Hosentaschen-Fernbedienung, Stimmungs-gesteuerte Auto-Dramaturgie.
5. **Seasons & Prestige:** 3-Monats-Seasons mit Wurzel-Soft-Reset,
   Hall of Fame, Season-Vault + Antiquitäten-Stand, Mastery-Tracks,
   Streuner-Affe, Geschenke unter Freunden, Bananen-Stiftung als
   AT-Endgame-Senke.
6. **Show-Polish:** Bildschirm-Themes (Casino/Weltraum),
   Einlauf-Animationen + Sieg-Posen, Shop als Marktstand mit
   Marktschreier-Makake, Rad-Skins, Halbzeit-/Sieger-Cutscenes,
   Highlight-Reel des Abends.
7. **Content-Intelligenz:** adaptive Fragenauswahl (Rubberband über
   Fragen statt Geld), Schwierigkeits-Drift-Automatik,
   Embedding-Clustering fürs Feedback, Fragen-Import-Pipelines.
8. **AI-Mitspieler:** Bot-Personas mit Spielstil (Zocker, Angsthase,
   Streber) zum Auffüllen kleiner Runden + Solo-Show gegen Bots;
   Tages-Challenge mit Freundes-Vergleich.
9. **Erreichbarkeit & Reichweite:** Vorlese-Funktion, EN-Lokalisierung,
   Community-Preset-Share-Codes, Late-Night-Edition,
   Koop-„Gemeinschaftskonto“-Modus (alle gegen die Bank).
10. **Zufalls-Ereignisse neben dem Rad:** Money-Koffer
    (Gier-Entscheidung), Affen-Alarm (Koop-Sofort-Minigame),
    Börsencrash/Bullenmarkt (Mid-Game-Weltereignis), Goldene-Banane-Blitz
    (Aufmerksamkeits-Belohnung).

---

## Anhang A — Aufgelöste Widersprüche (Entscheidungs-Log)

| Konflikt | Quellen | Entscheidung |
|---|---|---|
| Fragewerte 100/200/400/800 vs. 100/250/500/1.000 | 02 vs. 14 | **14 gewinnt** (100/250/500/1.000) — Ökonomie-Katalog ist die gerechnete Referenz, 50er-Stückelung passt |
| Speed-Bonus linear vs. Knick-Formel | 02 vs. 14 | **Knick-Formel** (kein Blind-Tipp-Exploit) |
| Streak ×1,25/×1,5 vs. ×1,5/×2,0 | 02 vs. 14 | **×1,5 ab 3, ×2,0 ab 5, Cap ×2** (14, durchgerechnet); Bruch bei falsch/Pass/Timeout, eingefroren bei AFK |
| Timer ULTRAHARD 20 s vs. 25 s | 14 vs. 02 | **25 s** (8 Optionen/lange Fragen brauchen Lesezeit) |
| Finale: Lianen (01) vs. Goldener Affe (02) vs. Formel (14) vs. Vabanque (04) | 01/02/04/14 | **Lianen-Inszenierung + I-21-Formel** als v1-Standard; Vabanque als Special Rule SR1 (ersetzt Formel); Goldener Affe v2 |
| Schätzrunde „Bananen-Waage“ vs. „Bananen-Tresor“ | 02 vs. 01 | Ein Format: **„Der Bananen-Tresor“** mit Waage-Mechanik und Festwert-Auszahlung (50er-kompatibel statt ×0,25-Brüche) |
| Falsch-Antwort-Strafe (I-04) vs. straffreies MC | 14 vs. 02 | Standard-MC straffrei (Anti-Frust); das Jackpot-Glas füllt sich stattdessen aus Stinkbananen-Explosionen, Fehlbuzz (Buzzer-Modul), abgewiesenen Reklamationen und Pranger-Strafen + 500 MM Grundfüllung |
| Wett-Mechanik: eigene Antwort (A7) vs. auf andere wetten (I-06) | 01 vs. 14 | **A7 in v1** (einfach, riesiger Effekt); Wetten-auf-andere in v2 (Wett-Affen/Affenmarkt) |
| Underdog: Geld-Multiplikator (U-01) vs. Fragen-Rubberband (I-23) | 04 vs. 14 | **Rückenwind (U-01) in v1** — transparent und billig; Fragen-Rubberband v2 |
| Übungsmodus-Belohnung: „XP/Kosmetik“ vs. „Level = AT“ | 07 vs. 16 | Training zahlt **nur in Stats + Meilensteine** ein (kein AT, kein Level) — kein Grind-Kanal an der Party-Ökonomie vorbei |
| Rad-Segment-Werte in „Punkten“ | 05 | Alle auf MM-Skala in 50er-Stückelung normiert (z. B. Umarmung +50 MM, Schmach-Gebühr 50 MM) |
