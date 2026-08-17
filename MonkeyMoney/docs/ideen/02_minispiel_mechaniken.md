# MONKEY MONEY — Ideen-Agent 2/20: Minispiel-MECHANIKEN im Detail

> Reine Ideation. 22 Mechanik-Designs für Handy-hochkant-Controller + großen
> Bildschirm (iPad/PC). Node.js HTTP-only (Polling) — alle Designs sind auf
> Latenz-Toleranz ausgelegt (keine Frame-genauen Echtzeit-Inputs nötig).

---

## 0. Globale Konventionen (gelten für alle Mechaniken, sofern nicht überschrieben)

**Währung & Basispunkte (MM = MONKEY MONEY):**

| Schwierigkeit | Basis-MM |
|---|---|
| Leicht | 100 |
| Mittel | 200 |
| Schwer | 400 |
| ULTRAHARD | 800 |

**Standard-Speed-Bonus:** `MM = Basis × (1 + 0,5 × Restzeit/Gesamtzeit)`
(gerundet auf 10er). Wer in der letzten Sekunde antwortet, bekommt also die
Basis; wer sofort antwortet, das 1,5-fache.

**Standard-Streak:** Ab 3 richtigen Antworten in Folge `×1,25`, ab 5 `×1,5`,
Kappe bei `×2,0`. Streak-Anzeige als Bananen-Kette am Spieler-Panel; reißt
sichtbar (Animation) bei Fehler.

**Spätantwort (HTTP-only):** Server-Empfangszeit zählt, mit **+400 ms
Gnadenfenster** nach Timer-Ende (Polling-Latenz). Danach: Antwort verworfen,
Spieler gilt als „keine Antwort" (0 MM, Streak reißt NICHT — nur bei aktiv
falscher Antwort).

**Disconnect mitten in der Frage:** Spieler bleibt 2 Fragen lang „AFK-Affe"
(Avatar schläft am Bildschirm, sammelt 0 MM, keine Strafe). Reconnect via
Raumcode + Name → gleicher Spielstand. Nach 2 Fragen entscheidet der
Show-Master (oder Auto-GM: weiter ohne ihn, Slot bleibt reserviert).

**Gleichstand (global):** Bei punktgleicher Wertung innerhalb einer Runde
gewinnt die frühere Server-Empfangszeit; bei Spielstand-Gleichstand am
Rundenende → Tiebreak-Minigame **„Kokosnuss-Shake"** (Nr. 16).

**Timer-Design (Standard):** Große Banane am oberen Bildschirmrand, die von
rechts „aufgegessen" wird (Bissspuren = verbleibende Zeit); letzte 5 s:
Pulsieren + Tick-Sound + Affenkreischen bei 0. Auf dem Handy nur ein dünner
Fortschrittsbalken oben (Redundanz, nie die einzige Zeitquelle).

**Punkte-Anzeige (Standard):** Spieler-Leiste am unteren Bildschirmrand:
Avatar-Affe, Name, MM-Kontostand als Geldbündel-Stapel, Streak-Bananenkette.
MM-Gewinne fliegen als Geldschein-Partikel vom Fragenfeld zum Avatar.

---

## 1. Vier Lianen (Multiple-Choice-Standard)

- **Frage-Typ:** Multiple Choice 4er (Text, Bild-als-Frage möglich).
- **Input am Handy:** 4 große Buttons vertikal gestapelt (je ~20 % Bildhöhe,
  volle Breite, Daumen-Zone), Farben+Symbole wie Buzz: 🍌 Gelb, 🥥 Braun,
  🐒 Rot, 🌴 Grün. Nach Tap: Button rastet ein, Rest ausgegraut, „Antwort
  gesendet"-Häkchen. **Kein Umentscheiden** (Standard; Joker „Zweite Chance"
  kann das aufheben).
- **Bildschirm:** Frage oben, 4 Antwort-Lianen hängen ins Bild und pendeln
  leicht; pro abgegebener Antwort springt ein anonymer Mini-Affe auf „hat
  geantwortet"-Ast (wer, bleibt geheim). Auflösung: falsche Lianen reißen,
  die richtige zieht die Affen der Richtigen hoch.
- **Timing:** 15 s Antwortzeit (Leicht/Mittel), 20 s (Schwer), 25 s
  (ULTRAHARD). Auflösung + Punktevergabe 6 s.
- **Scoring:** Standard (Basis × Speed × Streak).
- **Edge-Cases:** Gleichstand → Standard. Disconnect → Standard. Spätantwort
  → Standard. Doppel-Tap durch Netz-Retry → Server nimmt nur die erste
  Antwort pro Frage-ID (idempotent).
- **Aufwand:** S · **Priorität:** MUST

## 2. Bananen-Buzzer (klassische Buzzer-Runde)

- **Frage-Typ:** Offene Wissensfrage, die der Show-Master vorliest (oder TTS
  beim Auto-GM); Antwort mündlich bzw. per Master-Bestätigung.
- **Input am Handy:** EIN riesiger runder Buzzer (60 % Bildhöhe, Banane als
  Knopf), vibriert (Vibration API) beim Freischalten. Vor Freigabe: Buzzer
  grau + „Warten…". Frühbuzzern (vor Freigabe) → 1,5 s Sperre („Heißer
  Buzzer"-Anzeige), verhindert Dauerdrücken.
- **Bildschirm:** Frage baut sich Wort für Wort auf; sobald der erste buzzt:
  Freeze der Frage, Spotlight + Zoom auf dessen Avatar, Buzz-Reihenfolge als
  Nummern über den Avataren. Show-Master-Handy zeigt „Richtig/Falsch"-Buttons.
- **Timing:** Buzz-Fenster bis 5 s nach fertig gelesener Frage; nach Buzz
  8 s Antwortzeit (laut sagen); bei „Falsch" → Buzzer wieder frei für den
  Rest (die Falschen bleiben gesperrt).
- **Scoring:** Erster & richtig: Basis ×1,5. Zweiter Versuch: Basis ×1,0,
  dritter: ×0,75. Falsch gebuzzert: **−25 % der Basis** (Risiko!).
- **Edge-Cases:** *Buzz-Gleichstand:* Server-Empfangszeit entscheidet; bei
  <50 ms Differenz zeigt der Bildschirm „FOTOFINISH" und beide dürfen
  antworten (der Richtige mit früherem Timestamp gewinnt volle Punkte, der
  andere die Hälfte). *Disconnect nach Buzz:* 8-s-Timer läuft ab → gilt als
  falsch, aber ohne Malus. *HTTP-Fairness:* Buzz-Zeit = Client-Timestamp,
  aber gedeckelt auf Server-Zeit −800 ms (Anti-Cheat gegen manipulierte
  Uhren). *Kein Master (Auto-GM):* Runde wechselt auf 4er-Choice-Fallback.
- **Aufwand:** M · **Priorität:** MUST

## 3. Bananen-Waage (Schätz-Slider)

- **Frage-Typ:** Schätzfrage mit numerischer Antwort („Wie viele Bananen isst
  ein Gorilla pro Tag?").
- **Input am Handy:** Großer vertikaler Slider (hochkant ideal!) über 70 %
  Bildhöhe mit Log- oder Linear-Skala je nach Frage; darüber das aktuell
  gewählte Zahlenfeld GROSS; Feintuning per −/+ Buttons (±1) unter dem
  Slider; optional Zahlen-Direkteingabe per Tap aufs Zahlenfeld. Bestätigen
  mit „EINLOGGEN"-Button (verhindert versehentliches Absenden).
- **Bildschirm:** Zahlenstrahl als Liane quer über den Screen. Nach
  Timer-Ende erscheinen alle Tipps als Affen-Köpfe auf der Liane
  (gleichzeitig, mit Namen), dann fährt ein goldener Pfeil zum wahren Wert
  — Kamera-Zoom, Abstands-Beschriftung pro Spieler.
- **Timing:** 20 s Schätzzeit, 8 s Auflösung.
- **Scoring:** Ranking nach Distanz: Platz 1 = Basis ×1,5, Platz 2 = ×1,0,
  Platz 3 = ×0,6, Rest ×0,25 (jeder kriegt was — Schätzen soll sich immer
  lohnen). **Volltreffer (exakt): ×3 + „NAGEL AUF DEN KOPF"-Cutscene.**
- **Edge-Cases:** *Gleiche Distanz:* beide bekommen den besseren Platz
  (Platz dahinter entfällt). *Keine Abgabe:* letzter Slider-Stand zählt,
  wenn der Slider bewegt wurde, sonst keine Wertung. *Disconnect:* wie keine
  Abgabe. *Über-/Unterlauf:* Slider-Grenzen großzügig, Anzeige „>10.000"
  als Kappe.
- **Aufwand:** M · **Priorität:** MUST

## 4. Affenleiter (Reihenfolge-Sortieren)

- **Frage-Typ:** Sortieren, 4–5 Elemente (chronologisch, nach Größe, Preis,
  …). Auch mit Bildern.
- **Input am Handy:** Vertikale Liste mit 4–5 Karten, Drag-Handle rechts
  (☰), lange Karten (volle Breite). Drag & Drop ODER Tap-Tap-Tausch
  (erst Karte A, dann Karte B antippen → tauschen; wichtig für
  zittrige Finger + Touch-Zuverlässigkeit). „EINLOGGEN"-Button unten.
- **Bildschirm:** Leiter/Palme mit Sprossen; während der Antwortphase nur
  „X von Y haben sortiert". Auflösung Sprosse für Sprosse von unten: pro
  Sprosse klettern die Avatare hoch, die dieses Element richtig platziert
  haben — Spannung baut sich pro Sprosse auf.
- **Timing:** 30 s Sortierzeit, Auflösung 3 s pro Sprosse.
- **Scoring:** Pro korrekt platziertem Element `Basis/4`; komplett richtig:
  zusätzlicher Perfekt-Bonus +50 % + Speed-Bonus nur bei Komplett-Richtig.
  Alternativ-Modus „streng": Nur längste korrekte Teilsequenz zählt.
- **Edge-Cases:** *Keine Abgabe:* aktueller Stand zählt (Startreihenfolge
  wird serverseitig pro Spieler zufällig gemischt, sonst wären
  Nicht-Antworter identisch). *Gleichstand:* Standard. *Disconnect:*
  gemischte Startreihenfolge zählt = faktisch Zufallspunkte, fair genug.
- **Aufwand:** M · **Priorität:** MUST

## 5. Pixel-Dschungel (Bild-Zoom / Pixel-Enthüllung — „Was ist das?")

- **Frage-Typ:** Bildfrage; Antwort per 4er-Choice (robust) oder Buzzer
  (Show-Master-Modus).
- **Input am Handy:** 4 große Buttons (wie Nr. 1) — ABER jederzeit während
  der Enthüllung drückbar. Zusätzlich „NOCH WARTEN"-Fläche unten als
  bewusste Nicht-Aktion (zeigt dem Spieler: du verlierst gerade Bonus).
- **Bildschirm:** Bild startet extrem verpixelt (oder als 8× Zoom auf ein
  Detail) und wird in 8 Stufen über 24 s scharf/herausgezoomt. Über dem Bild
  eine **Geld-Uhr: der aktuelle Fragen-Jackpot schrumpft sichtbar mit jeder
  Enthüllungsstufe** (800 → 700 → … → 100 MM). Wer geantwortet hat, dessen
  Avatar hält sich die Augen zu (er sieht die weiteren Stufen nicht mehr —
  Anzeige am Handy wird verdeckt).
- **Timing:** 24 s Enthüllung (8 Stufen à 3 s) + 4 s Restzeit voll scharf.
- **Scoring:** MM = Jackpot-Stand zum Zeitpunkt der (richtigen) Antwort.
  Falsch = 0 und Sperre für den Rest der Enthüllung. Kein separater
  Speed-Bonus (steckt im Jackpot-Verfall). Streak zählt normal.
- **Edge-Cases:** *Spätantwort:* Jackpot-Stufe der Server-Empfangszeit
  zählt (nicht Client-Anzeige) — durch 3-s-Stufen ist Polling-Latenz
  praktisch egal (genau deshalb Stufen statt stufenlos!). *Gleichstand:*
  gleiche Stufe = gleiche Punkte, kein Konflikt. *Disconnect:* 0 MM,
  Standard.
- **Aufwand:** M · **Priorität:** MUST

## 6. Dschungel-Ohren (Audio-Raten)

- **Frage-Typ:** Audio (Song-Intro, Tierlaut, berühmtes Zitat rückwärts,
  Geräusch); Antwort 4er-Choice.
- **Input am Handy:** 4 große Buttons + ein „🔇 ICH HÖR NIX"-Mini-Button
  (meldet Audio-Problem an den Bildschirm, pausiert NICHT). Audio kommt NUR
  vom großen Bildschirm (Party-Situation, ein Lautsprecher, kein Sync-Chaos
  über HTTP).
- **Bildschirm:** Schallwellen-Visualizer als tanzende Affenband; Audio
  läuft in 3 Häppchen: 2 s → 4 s → volle 8 s, dazwischen je 5 s
  Antwortfenster mit sinkender Wertung (Anzeige: „Runde 1: ×2 / Runde 2:
  ×1,5 / Runde 3: ×1").
- **Timing:** Gesamt ~35 s. Antworten jederzeit möglich, gewertet nach
  Häppchen-Phase.
- **Scoring:** Basis × Phasen-Multiplikator (2 / 1,5 / 1) — richtig nach
  dem ersten 2-s-Häppchen wird fett belohnt. Falsch: gesperrt für die
  Frage, −10 % Basis.
- **Edge-Cases:** *Audio-Datei lädt nicht:* Auto-Skip mit Ersatzfrage
  (Puffer von 2 vorge­ladenen Ersatzfragen pro Runde). *Gleichstand/
  Disconnect/Spät:* Standard, Phasengrenzen wie bei Nr. 5 latenztolerant.
- **Aufwand:** M · **Priorität:** SHOULD

## 7. Bananen-Bluff (Lügen erfinden & erkennen, Fibbage-Stil)

- **Frage-Typ:** Obskure Fakten-Frage mit Lücke („Der teuerste je verkaufte
  Affe hieß ___").
- **Input am Handy:** Phase 1: Texteingabe-Feld (Autokorrektur aus,
  20-Zeichen-Limit, Profanity-Filter, Server lehnt Duplikate der Wahrheit
  ab mit „Zu nah dran — schreib was Fieseres!"). Phase 2: Liste aller
  Antworten (Wahrheit + Lügen, gemischt) als große Buttons — die eigene
  Lüge ist ausgegraut.
- **Bildschirm:** Phase 1: Schreibmaschinen-Affen tippen. Phase 2: Antworten
  auf Bananenkisten. Auflösung: pro Lüge fliegt die Kiste auf, der Lügner
  wird enttarnt (Avatar mit Diebesmaske) + wer draufgefallen ist.
- **Timing:** 45 s Lügen schreiben, 25 s wählen, 20 s Auflösung.
- **Scoring:** Wahrheit gefunden: Basis. Pro Mitspieler, der auf DEINE Lüge
  fällt: +50 % Basis in DEINE Tasche — **direkt vom Konto des
  Reingelegten abgebucht** (MONKEY-MONEY-Twist: Lügen ist Diebstahl).
  Kein Speed-Bonus.
- **Edge-Cases:** *Keine Lüge abgegeben:* Server setzt Auto-Lüge aus
  kuratiertem Pool (Spieler kann trotzdem Phase 2 spielen, verdient aber
  nichts an der Auto-Lüge). *Zwei identische Lügen:* werden zusammengelegt,
  Ertrag geteilt. *Disconnect in Phase 1:* Auto-Lüge. *2 Spieler:* Modus
  gesperrt (min. 3).
- **Aufwand:** L · **Priorität:** SHOULD

## 8. Angeber-Affe (Bluff-Buzzer: Glauben oder Zweifeln)

- **Frage-Typ:** Schwere offene Frage; einer behauptet, sie zu können.
- **Input am Handy:** Phase 1: großer „ICH WEISS ES!"-Buzzer (jeder darf,
  der Schnellste wird Angeber). Phase 2 (alle anderen): 2 Riesen-Buttons
  „GLAUB ICH 🍌" / „NIEMALS 🙈" + Einsatz-Slider (0–200 MM). Phase 3
  (Angeber): 4er-Choice, aber er sieht die Optionen ERST JETZT — vorher
  musste er blind behaupten.
- **Bildschirm:** Angeber-Avatar auf einem Podest im Scheinwerfer, die
  anderen als Jury mit Daumen-Anzeigen (verdeckt bis Auflösung), Einsätze
  als Geldsäcke vor der Jury.
- **Timing:** 6 s Buzz-Fenster, 15 s Wetten, 12 s Antwort, 8 s Auflösung.
- **Scoring:** Angeber richtig: Basis ×2 + 25 % aller „NIEMALS"-Einsätze.
  Angeber falsch: −Basis (kann ins Minus!), „NIEMALS"-Wetter verdoppeln
  ihren Einsatz, „GLAUB ICH"-Wetter verlieren ihn.
- **Edge-Cases:** *Keiner buzzt:* Frage wird normale 4er-Choice für alle
  (halbe Basis). *Angeber disconnectet:* gilt als falsch, aber ohne Malus
  für ihn; Wetten werden zurückerstattet. *Gleichstand beim Buzz:*
  Server-Zeit (wie Nr. 2).
- **Aufwand:** M · **Priorität:** SHOULD

## 9. Monkey Market / Geld-Regen (Money-Drop-Verteilung) 🐒💡

- **Frage-Typ:** Multiple Choice 4er mit Unsicherheit — ideal für Schwer/
  ULTRAHARD.
- **Input am Handy:** 4 Ablagefelder (2×2-Grid) + darunter der eigene
  Einsatz als 10 Geldbündel-Chips. Chips per Drag auf Felder ziehen ODER
  Tap-aufs-Feld = +1 Chip, Langdruck = −1 Chip (Fallback ohne Drag).
  „Alles auf eins"-Schnellbutton. Muss alle 10 Chips verteilen (Rest wird
  beim Timeout gleichmäßig auf belegte Felder gelegt).
- **Bildschirm:** 4 Falltüren mit Bananenkisten-Stapeln pro Spielerfarbe.
  Auflösung: falsche Falltüren öffnen sich nacheinander (dramatisch, die
  richtige zuletzt), Geld regnet in den Abgrund, Affen kreischen.
- **Timing:** 25 s Verteilen, 12 s Falltür-Dramaturgie.
- **Scoring:** Einsatz = 10 Chips à `Basis/10`. Chips auf der richtigen
  Antwort kommen ×2 zurück, Rest ist weg. Wer alles auf die richtige
  setzt: zusätzlich +25 % Mut-Bonus. Kein Speed-Bonus.
- **Edge-Cases:** *Keine Aktion:* automatische Gleichverteilung (2/2/3/3)
  → garantierter kleiner Rückfluss, kein Totalausfall für AFKs.
  *Disconnect:* wie keine Aktion. *Gleichstand:* Standard.
- **Aufwand:** M · **Priorität:** MUST *(einer der Signature-Modi:
  MONKEY MONEY = Geld anfassen, nicht nur Punkte sehen)*

## 10. Bananen-Börse (Live-Investieren während der Timer läuft) 🐒💡

- **Frage-Typ:** Multiple Choice 4er, gerne kontrovers/knifflig.
- **Input am Handy:** 4 „Aktien"-Zeilen (je Antwortoption) mit KAUF-Button;
  man investiert in **Tranchen à 25 MM**, darf mehrfach und auf mehrere
  Optionen kaufen, **Umschichten verboten** (gekauft ist gekauft — das
  erzeugt den Nervenkitzel). Kontostand-Anzeige oben.
- **Bildschirm:** Börsenticker! Pro Option ein Live-Kurs = Auszahlungsquote,
  die **sinkt, je mehr Gesamt-MM aller Spieler bereits auf dieser Option
  liegen** (Quote = 3,0 − 1,5 × Anteil, min. 1,2). Herdentrieb wird also
  bestraft, Contrarian-Wissen belohnt. Anonyme Kaufblips laufen als Ticker.
- **Timing:** 30 s Handelsfenster in 6 Kurs-Updates à 5 s (latenztolerant,
  Käufe werden zur Quote des laufenden 5-s-Blocks abgerechnet — HTTP-fair).
- **Scoring:** Auszahlung = Σ(Tranche × Quote zum Kaufzeitpunkt) auf der
  richtigen Option; falsche Investments verfallen. Früh + richtig + gegen
  die Herde = Maximum.
- **Edge-Cases:** *Konto zu klein:* Mindestbudget 100 MM wird jedem für
  diese Runde gestellt (Kredit der Affenbank, wird nicht zurückgefordert).
  *Keine Käufe:* 0 MM, Streak unberührt. *Disconnect:* getätigte Käufe
  bleiben gültig und werden ausgezahlt. *Gleichstand:* Standard.
- **Aufwand:** L · **Priorität:** SHOULD *(UNIQUE — gibt's so in keiner
  Quiz-App: Quiz + Quoten-Markt)*

## 11. Affen-Auktion (Fragen ersteigern) 🐒💡

- **Frage-Typ:** Beliebig — versteigert wird das RECHT, exklusiv zu
  antworten. Kategorie + Schwierigkeit sind vor der Auktion sichtbar,
  die Frage nicht.
- **Input am Handy:** Großer „BIETEN +25"-Button (jeder Tap erhöht das
  eigene Gebot um 25 MM), daneben „AUSSTEIGEN". Aktuelles Höchstgebot
  + Führender live am Handy.
- **Bildschirm:** Auktionshaus-Set, Auktionator-Affe mit Hammer, Gebote
  als steigende Geldsäule pro Spieler. „Zum Ersten… zum Zweiten…"-Countdown
  (3 s) startet, sobald 3 s kein neues Gebot kommt.
- **Timing:** Auktion max. 20 s, dann 15 s Antwortzeit (4er-Choice) für den
  Gewinner.
- **Scoring:** Gewinner zahlt sein Gebot SOFORT. Richtig: Basis ×2 zurück
  (Gebot ist Einsatz). Falsch: Gebot wird **gleichmäßig an alle anderen
  verteilt** (Schadenfreude-Ausschüttung!). Nicht-Bieter: risikofrei, aber
  chancenlos.
- **Edge-Cases:** *Niemand bietet:* Frage geht für alle als normale
  4er-Choice mit halber Basis. *Gebots-Gleichstand durch Latenz:*
  Server-Reihenfolge zählt, Anzeige „überboten!" am Handy. *Gewinner
  disconnectet:* Gebot zurück, Frage verfällt. *Bieten über Kontostand:*
  Button deaktiviert ab Konto-Limit.
- **Aufwand:** M · **Priorität:** SHOULD *(UNIQUE-Twist: Quiz-Rechte als
  Ware)*

## 12. Banane oder Bombe (Push-your-luck nach richtiger Antwort) 🐒💡

- **Frage-Typ:** Aufsatz auf JEDE richtige 4er-Choice-Antwort in
  Spezialrunden („Risiko-Runde").
- **Input am Handy:** Nach richtiger Antwort erscheint EIN großer
  „HALTEN = SAMMELN"-Button. Solange gedrückt, füllt sich ein
  Bananen-Zähler (+10 % Basis pro halbe Sekunde). Irgendwann (zufällig,
  serverseitig zwischen 2 und 8 s ausgelost) platzt die Bombe — wer dann
  noch hält, verliert den GESAMTEN Rundengewinn dieser Frage. Loslassen =
  sichern.
- **Bildschirm:** Pro haltendem Spieler eine Zündschnur, die unterschiedlich
  schnell abbrennt (jeder hat seine eigene Auslosung); gesicherte Spieler
  springen mit Bananensack ab. Herzschlag-Sound schwillt an.
- **Timing:** Max. 8 s Zusatzphase. HTTP-fair: „Loslassen"-Event zählt mit
  Client-Timestamp, gedeckelt auf Server-Zeit −800 ms; die Bombe wird erst
  NACH Eingang aller Events aufgelöst (Server vergleicht Timestamps —
  deshalb funktioniert das trotz Polling).
- **Scoring:** Gesichert = Fragen-MM × (1 + 0,1 × Halte-Halbsekunden).
  Bombe erwischt = 0 MM für diese Frage (Konto bleibt unangetastet).
- **Edge-Cases:** *Disconnect beim Halten:* zählt als Loslassen zum
  Zeitpunkt des letzten Polls (Spieler wird geschützt, nicht bestraft).
  *Alle sichern sofort:* okay, Phase endet früh. *Gleichstand:* keiner
  nötig, individuelle Auslosung.
- **Aufwand:** M · **Priorität:** SHOULD *(UNIQUE als Quiz-Aufsatz;
  Bindeglied zu Bestrafungen: Bomben-Opfer kriegt Mini-Strafe/Cutscene)*

## 13. Tipp-Basar (Tipps kaufen per Gedrückthalten) 🐒💡

- **Frage-Typ:** Aufsatz auf 4er-Choice und Schätzfragen (nutzt das
  „Fragen mit Tipps"-Feature).
- **Input am Handy:** Neben den Antwort-Buttons ein „🐵 TIPP-AFFE"-Button
  zum GEDRÜCKTHALTEN: Solange man hält, tickt der Preis (5 MM/Sekunde) und
  der Tipp wird Wort für Wort am eigenen Handy enthüllt (nur für diesen
  Spieler!). Loslassen stoppt Kosten UND Enthüllung. Bis zu 3 Tipps mit
  steigender Deutlichkeit.
- **Bildschirm:** Zeigt NUR, wer gerade Tipps kauft (Avatar bekommt
  Flüster-Affen auf die Schulter) — nicht den Inhalt. Sozialer Druck:
  „Der kauft sich die Antwort!"
- **Timing:** Innerhalb der normalen Antwortzeit der Trägerfrage
  (verlängert diese um +5 s, wenn mind. einer kauft).
- **Scoring:** Trägerfrage normal, aber Tipp-Kosten werden abgezogen; wer
  MIT Tipp richtig liegt, bekommt keinen Speed-Bonus (Ausgleich).
- **Edge-Cases:** *Konto leer:* erster Tipp-Ansatz (2 s) gratis pro Spiel
  („Probier-Bananen"). *Halten + Disconnect:* Kosten stoppen beim letzten
  Poll. *Wort-Enthüllung vs. Latenz:* Enthüllung in 1-s-Schritten,
  abgerechnet wird serverseitig — kleine Anzeige-Nachläufe sind egal.
- **Aufwand:** S · **Priorität:** SHOULD *(UNIQUE: Tipps als
  Pay-per-Second-Ökonomie)*

## 14. Diebischer Affe (Steal-Phase nach der Antwort) 🐒💡

- **Frage-Typ:** 4er-Choice in „Diebstahl-Runden".
- **Input am Handy:** Nach der eigenen Antwort (und VOR der Auflösung)
  öffnet sich 8 s ein zweites Panel: Avatare aller Mitspieler als Buttons
  — „Bei wem klaust du?" Man setzt einen Klau-Marker auf GENAU einen
  Spieler (oder „Nicht klauen" = sicher).
- **Bildschirm:** Nebelphase „Die Diebe gehen um…" mit schleichenden
  Affen-Silhouetten (niemand sieht, wer wen markiert). Auflösung: erst
  Frage, dann Diebstähle als Comic-Einblendungen.
- **Timing:** 15 s Frage + 8 s Klau-Phase + 10 s Auflösung.
- **Scoring:** Klau erfolgreich, wenn ICH richtig lag UND mein Opfer falsch:
  Ich ziehe 50 % von dessen Fragengewinn-Basis von SEINEM Konto ab. Lag ich
  falsch und mein Opfer richtig: Es dreht sich — das Opfer erwischt mich
  („In die Falle getappt"), −25 % Basis an ihn. Beide richtig/beide falsch:
  nichts passiert.
- **Edge-Cases:** *Zwei klauen beim selben Opfer:* beide erfolgreich, Opfer
  zahlt aber gedeckelt max. 75 % (Anti-Mobbing-Kappe). *Klau auf
  Disconnected:* automatisch „Nicht klauen". *2-Spieler-Spiel:* Phase
  entfällt.
- **Aufwand:** M · **Priorität:** COULD *(UNIQUE: soziales Metagame über
  dem Quiz — wer ist schlau, wer ist dumm UND reich?)*

## 15. Duell am Lianensteg (1v1)

- **Frage-Typ:** Schnelle 4er-Choice-Serie (Best-of-5), Themen-Kategorie
  vom Herausforderer gewählt.
- **Input am Handy:** Duellanten: 4 Buttons (wie Nr. 1), aber mit
  3-2-1-Countdown vor jeder Frage. Zuschauer: 2 Wett-Buttons („Wer
  gewinnt?", Einsatz fest 50 MM) vor Duellbeginn.
- **Bildschirm:** Split-Screen! Zwei Affen auf einem Hängesteg über der
  Schlucht; pro gewonnener Teilfrage schubst der Gewinner den Verlierer
  einen Schritt Richtung Abgrund (Tauziehen-Logik: Stand −2 bis +2).
  Zuschauer-Wetten als Fähnchen an den Seilen.
- **Timing:** 5 Fragen à 10 s; Sudden-Death-Frage bei 2:2-Gleichstand nach
  Tempo (schnellste richtige Antwort).
- **Scoring:** Sieger: 300 MM + 100 MM direkt vom Konto des Verlierers.
  Richtige Zuschauer-Wetten: Einsatz ×2. Duell-Auswahl: Rad/GM bestimmt
  Herausforderer, dieser wählt den Gegner (Letzter darf nicht gezwungen
  werden: „Feiglings-Schutz" — der Führende ist immer wählbar).
- **Edge-Cases:** *Duellant disconnectet:* verbleibende Fragen gehen
  kampflos an den Anwesenden, aber ohne Konto-Abzug beim Verlierer.
  *Beide falsch:* Schritt-Stand unverändert, nächste Frage. *Doppelter
  Sudden-Death-Gleichstand (<50 ms):* geteilter Sieg, beide +150 MM,
  Wetten zurück.
- **Aufwand:** M · **Priorität:** SHOULD

## 16. Kokosnuss-Shake (Tap-Frenzy — Tiebreaker & Auflockerung)

- **Frage-Typ:** KEIN Wissen — reines Reaktions-/Ausdauerspiel als
  Gleichstand-Brecher und Zwischenrunden-Gag.
- **Input am Handy:** Eine große Kokosnuss, so schnell wie möglich tippen
  (10 s). Jeder Tap wackelt die Nuss; clientseitig gezählt, in 1-s-Batches
  an den Server gemeldet (HTTP-tauglich), Plausibilitätskappe 12 Taps/s
  (Anti-Autoclicker).
- **Bildschirm:** Pro Spieler eine Palme, die durchgeschüttelt wird;
  Kokosnüsse fallen pro 10 Taps; Live-Balkenrennen.
- **Timing:** 3-s-Countdown + 10 s Tippen + 4 s Ergebnis.
- **Scoring:** Als Tiebreaker: Sieger gewinnt den Gleichstand. Als
  Zwischenspiel: Platz 1 = 100 MM, Platz 2 = 50 MM.
- **Edge-Cases:** *Erneuter Gleichstand:* Sudden-Death 3 s. *Disconnect:*
  letzter gemeldeter Batch-Stand zählt. *Batch kommt zu spät:* Batches mit
  Server-Empfang > Ende + 1,5 s verworfen.
- **Aufwand:** S · **Priorität:** MUST *(klein, aber als globaler
  Tiebreaker systemrelevant)*

## 17. Affenkette (Team-Kooperativ)

- **Frage-Typ:** Listen-Frage mit vielen richtigen Antworten („Nennt 8
  Länder mit Dschungel") als Team-Staffel, 4er-Choice-Häppchen.
- **Input am Handy:** Es antwortet IMMER NUR der Spieler, der gerade den
  „Staffel-Affen" hat: Er sieht 4 Optionen (1 richtig, 3 schon-genannt/
  falsch), 6 s Zeit, danach wandert der Affe automatisch zum Nächsten.
  Alle anderen sehen ein „ANFEUERN"-Trommel-Button (rein kosmetisch,
  triggert Trommel-Sounds + Konfetti am Bildschirm — Beschäftigung für
  Wartende!).
- **Bildschirm:** Team-Kette aus Avataren, der aktive Spieler vorn an der
  Liane; Ketten-Combo-Zähler; Trommel-Intensität = wie viele anfeuern.
- **Timing:** 6 s pro Glied, Runde = 2× durch die volle Kette.
- **Scoring:** Gemeinschaftstopf: pro richtigem Glied +100 MM × aktuelle
  Ketten-Combo (1, 2, 3 …, Fehler = Combo-Reset auf 1). Topf wird am Ende
  GLEICH verteilt (Koop!). Perfekte Kette: alle bekommen zusätzlich einen
  Joker.
- **Edge-Cases:** *Aktiver Spieler disconnectet/AFK:* nach 6 s automatisch
  weiter, zählt nicht als Fehler (Combo bleibt), Spieler wird bei Runde 2
  übersprungen. *Ungerade Topf-Teilung:* Rest an den Letztplatzierten
  (Aufhol-Mechanik). *2 Spieler:* funktioniert, Kette = Ping-Pong.
- **Aufwand:** M · **Priorität:** SHOULD

## 18. Preis-Prügelei (Schätzen ohne Überbieten, Price-is-Right-Stil)

- **Frage-Typ:** Preis-/Mengen-Schätzung mit „nicht drüber!"-Regel („Was
  kostet dieses Affen-Plüschtier auf Amazon?").
- **Input am Handy:** Nummern-Pad (0–9, Löschen, Einloggen) — bewusst
  KEIN Slider, damit krumme Werte möglich sind; eingeloggte Zahl groß oben.
- **Bildschirm:** Preisschild-Wand; alle Tipps erscheinen gleichzeitig als
  Preisschilder, dann Stempel „ÜBERBOTEN!" auf alle Tipps über dem wahren
  Wert (die sind RAUS), dann Krönung des besten verbleibenden Tipps.
- **Timing:** 20 s Eingabe, 10 s Auflösung.
- **Scoring:** Bester nicht-überbietender Tipp: Basis ×1,5. Zweitbester:
  ×0,75. Überbieter: 0. ALLE überboten: niemand punktet, dafür Cutscene
  „Die Bank lacht euch aus" + alle zahlen 25 MM Strafgebühr.
- **Edge-Cases:** *Exakter Treffer:* ×3. *Gleiche Tipps:* teilen sich die
  Wertung des Platzes. *Keine Eingabe:* gilt als überboten (raus).
- **Aufwand:** S · **Priorität:** COULD

## 19. Aufpasser-Affe (Meta-Fragen über die Show selbst) 🐒💡

- **Frage-Typ:** 4er-Choice über Dinge, die IM LAUFENDEN SPIEL passiert
  sind: „Was hat Lisa in Runde 2 geschätzt?", „Wer hatte die längste
  Streak?", „Welche Farbe hatte der Hut in der letzten Cutscene?" —
  generiert aus den Analytics-/Verlaufsdaten + Cutscene-Metadaten.
- **Input am Handy:** 4 große Buttons (Standard).
- **Bildschirm:** „RÜCKBLENDE!"-Stinger, Sepia-Filter, Detektiv-Affe mit
  Lupe; nach Auflösung wird der Original-Moment als Replay-Einblendung
  gezeigt (Screenshot des damaligen Spielstands).
- **Timing:** 12 s (kurz — man weiß es oder nicht).
- **Scoring:** Basis 200 MM fix + Speed-Bonus; die Person, um die es in
  der Frage ging, bekommt bei richtiger Antwort ×1,5 („Selbstkenntnis").
- **Edge-Cases:** *Zu wenig Verlauf (früh im Spiel):* Modus erst ab Runde 3
  freigeschaltet. *Betroffener Spieler disconnected:* Frage über ihn
  trotzdem gültig. *Gleichstand/Spät:* Standard.
- **Aufwand:** M · **Priorität:** COULD *(UNIQUE: belohnt Zuschauen statt
  Handy-Starren zwischen den eigenen Zügen; füttert sich aus Analytics)*

## 20. Glücksrad-Heist (Rad-Wette + Wisch-Dreh) 🐒💡

- **Frage-Typ:** Kein Wissen — Glücksrad-Integration als Risiko-Minigame
  zwischen Runden.
- **Input am Handy:** Phase 1: Alle setzen per 8-Felder-Grid (Rad-Sektoren
  als Buttons) + Einsatz-Slider, AUF WELCHEM Sektor das Rad landet.
  Phase 2: Der aktuell LETZTPLATZIERTE darf drehen — vertikale
  Wischgeste, Wischlänge+Geschwindigkeit = Impuls (einmalig gemessen,
  dann läuft die Rad-Physik deterministisch serverseitig — HTTP-fair,
  Seed = Wisch-Impuls).
- **Bildschirm:** Riesiges Rad mit Sektoren: MM-Beträge, „×2 für alle",
  „BESTRAFUNG", „Bananen-Regen (+50 alle)", „AFFENALARM (Plätze 1↔️
  letzter tauschen 10 % Konto)". Einsätze der Spieler als Fähnchen an den
  Sektoren.
- **Timing:** 15 s wetten, 8 s Dreh-Dramaturgie.
- **Scoring:** Richtiger Sektor getippt: Einsatz ×6 (8 Sektoren, leichter
  House-Edge für die Affenbank). Sektor-Effekt gilt zusätzlich für alle.
  Der Dreher erhält 50 MM Gage („Rad-Trinkgeld") — Trostpflaster für den
  Letzten.
- **Edge-Cases:** *Dreher disconnectet:* Auto-GM dreht (Zufalls-Impuls).
  *Kein Einsatz:* zuschauen erlaubt. *Wisch zu schwach (<1 Umdrehung):*
  „Lahme Liane!"-Sound, einmal Wiederholung erlaubt.
- **Aufwand:** M · **Priorität:** COULD *(verzahnt Glücksrad + Wetten +
  Aufhol-Mechanik)*

## 21. Ultrahart-Survival (ULTRAHARD-Eliminierung mit 8 Optionen)

- **Frage-Typ:** ULTRAHARD Multiple Choice mit **8 Optionen** (statt 4),
  Serie von bis zu 5 Fragen, Eliminierungs-Modus.
- **Input am Handy:** 8 Buttons als 2×4-Grid (kleiner, aber hochkant noch
  gut tippbar); vor der Serie einmalig „SCHUTZ-BANANE"-Toggle: EINEN
  Freischuss für die Serie aktivierbar (kostet 100 MM).
- **Bildschirm:** Spieler stehen auf Eisschollen… äh, Baumstümpfen im
  Piranha-Fluss; pro falscher Antwort bricht der Stumpf, Spieler hängt am
  letzten Ast (2. Fehler = raus, Zuschauermodus mit Wett-Buttons auf den
  Sieger). Dramatische Nebel + Trommel-Eskalation pro Frage.
- **Timing:** 25 s pro Frage, Serie endet, wenn 1 Spieler übrig ist oder
  5 Fragen gespielt sind (dann gewinnen alle Überlebenden).
- **Scoring:** Überleben pro Frage: +200 MM. Letzter Überlebender: +800 MM
  Jackpot. Eliminierte behalten ihre bis dahin verdienten Serien-MM.
- **Edge-Cases:** *Alle in einer Frage falsch:* niemand fliegt („Der Fluss
  hat heute keinen Hunger"), nächste Frage. *Disconnect:* zählt als keine
  Antwort = 1 Fehler-Fortschritt, aber nie Direkt-Eliminierung durch
  Disconnect. *Nur noch 2, beide falsch im Finale:* Kokosnuss-Shake
  entscheidet.
- **Aufwand:** M · **Priorität:** COULD

## 22. Der Goldene Affe (Finale)

- **Frage-Typ:** 3-stufiges Finale, kombiniert die gelernten Inputs:
  Stufe 1 „Alles-oder-Anteil" (Money-Drop, Nr. 9, mit dem ECHTEN
  Kontostand — jeder muss mind. 50 % seines Vermögens verteilen),
  Stufe 2 Schätz-Showdown (Nr. 3, Verlierer der Stufe scheidet aus),
  Stufe 3 nur die Top 2: Buzzer-Best-of-3 (Nr. 2, Auto-GM-tauglich als
  Speed-4er-Choice: schnellste richtige Antwort gewinnt den Punkt).
- **Input am Handy:** Wechselt pro Stufe (Chips-Drag → Slider → Buzzer/
  4 Buttons); Ausgeschiedene bekommen Zuschauer-Wetten (50-MM-Häppchen auf
  den Finalsieger — sie bleiben bis zur letzten Sekunde beteiligt!).
- **Bildschirm:** Goldener Affentempel, der sich pro Stufe weiter öffnet;
  Vermögen der Finalisten als physische Goldstapel NEBEN den Spielern
  (nicht mehr abstrakt in der Leiste); Konfetti-Kanonen + Sieger-Cutscene:
  Krönung mit Bananen-Krone, Verlierer-Bestrafung aus dem Strafen-Pool.
- **Timing:** Gesamt 4–6 min: Stufe 1: 30 s, Stufe 2: 20 s, Stufe 3:
  3 Fragen à 10 s.
- **Scoring:** Der SIEGER ist, wer nach Stufe 3 gewinnt — aber sein
  Endvermögen = eigenes Konto + 20 % der Konten aller anderen
  („Der Gewinner nimmt die Bananen mit"). Zuschauer-Wetten zahlen ×3.
  Das Endvermögen ist der Highscore fürs Analytics-Leaderboard.
- **Edge-Cases:** *Finalist disconnectet:* Nachrücker ist der nächstbeste
  Nicht-Finalist (Anzeige „Wildcard!"). *Gleichstand nach Stufe 3 (1:1 +
  Zeitgleichheit):* eine finale Schätzfrage, näher dran gewinnt — die
  ultimative Antwort auf alles. *2-Spieler-Spiel:* Stufe 2 entfällt.
- **Aufwand:** L · **Priorität:** MUST

---

## Übersicht

| # | Name | Kern | Aufwand | Priorität | Unique? |
|---|---|---|---|---|---|
| 1 | Vier Lianen | MC-4-Standard | S | MUST | – |
| 2 | Bananen-Buzzer | Buzzer-Runde | M | MUST | – |
| 3 | Bananen-Waage | Schätz-Slider | M | MUST | – |
| 4 | Affenleiter | Sortieren | M | MUST | – |
| 5 | Pixel-Dschungel | Bild-Enthüllung + Geld-Verfall | M | MUST | Twist |
| 6 | Dschungel-Ohren | Audio-Häppchen | M | SHOULD | – |
| 7 | Bananen-Bluff | Lügen schreiben | L | SHOULD | Twist (Klau) |
| 8 | Angeber-Affe | Bluff-Buzzer + Wetten | M | SHOULD | Twist |
| 9 | Monkey Market / Geld-Regen | Chips verteilen | M | MUST | Twist |
| 10 | Bananen-Börse | Live-Quoten-Investieren | L | SHOULD | ✅ UNIQUE |
| 11 | Affen-Auktion | Fragen ersteigern | M | SHOULD | ✅ UNIQUE |
| 12 | Banane oder Bombe | Push-your-luck-Halten | M | SHOULD | ✅ UNIQUE |
| 13 | Tipp-Basar | Tipps pay-per-second | S | SHOULD | ✅ UNIQUE |
| 14 | Diebischer Affe | Steal-Phase | M | COULD | ✅ UNIQUE |
| 15 | Duell am Lianensteg | 1v1 Best-of-5 | M | SHOULD | – |
| 16 | Kokosnuss-Shake | Tap-Frenzy-Tiebreak | S | MUST | – |
| 17 | Affenkette | Team-Koop-Staffel | M | SHOULD | – |
| 18 | Preis-Prügelei | Nicht überbieten | S | COULD | – |
| 19 | Aufpasser-Affe | Meta-Fragen zur Show | M | COULD | ✅ UNIQUE |
| 20 | Glücksrad-Heist | Rad-Wette + Wisch-Dreh | M | COULD | ✅ UNIQUE |
| 21 | Ultrahart-Survival | 8-Optionen-Elimination | M | COULD | Twist |
| 22 | Der Goldene Affe | 3-Stufen-Finale | L | MUST | Twist |

**MVP-Empfehlung (MUST-Set):** 1, 2, 3, 4, 5, 9, 16, 22 — deckt Standard,
Buzzer, Schätzen, Sortieren, Bild, Geld-Mechanik, Tiebreak und Finale ab;
alle weiteren Modi docken an dieselben 5 Input-Primitive an (Buttons,
Slider, Drag-Liste, Halten, Tap-Frenzy), d. h. Controller-seitig wächst
der Aufwand danach nur noch langsam.

**HTTP-only-Leitplanke (überall angewandt):** Wertungen hängen nie an
Frame-genauen Zeitpunkten, sondern an Stufen/Blöcken (3-s-Pixel-Stufen,
5-s-Kurs-Blöcke, 1-s-Tap-Batches) oder an gedeckelten Client-Timestamps
(Buzzer, Bombe) — damit bleibt jede Mechanik trotz Polling fair.
