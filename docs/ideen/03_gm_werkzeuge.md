# MONKEY MONEY — Ideen-Agent 3/20: Game-Master-Werkzeuge & Live-Regie

Ziel: Ein GM-Cockpit, das sich anfühlt wie ein Regiepult einer TV-Show — der menschliche
Show-Master (eigenes Gerät, sieht Geheim-Infos) bekommt Superkräfte, der Auto-GM macht
dasselbe softwaregesteuert. Alle Ideen sind HTTP-only-tauglich (Polling/Long-Poll), Money-Thema
(Bananen/Dollar/Tresor-Metaphern), 2–8 Spieler.

Legende: Aufwand S/M/L · Prio MUST/SHOULD/COULD

---

## A. Fundament: Cockpit, Log, Geheimsicht

### 1. „Regiepult" — Das 3-Zonen-Cockpit-Grundlayout
- **GM-UI:** iPad quer, drei feste Zonen. Links: Live-Status (Spielerliste mit Score, Antwort-Status,
  Verbindungs-Ampel). Mitte: Bühnen-Spiegel (Mini-Vorschau dessen, was der Bildschirm gerade zeigt)
  plus kontextabhängige Haupt-Aktion („Nächste Frage", „Auflösen", „Runde beenden"). Rechts:
  aufklappbares Geheim-Panel + Schnell-Aktions-Dock (6–8 große Buttons, konfigurierbar).
  Alles mit Daumen erreichbar, keine verschachtelten Menüs für Standard-Flow.
- **Wirkung Bildschirm/Handys:** Keine direkte — das ist der Rahmen, in dem alle anderen Werkzeuge leben.
- **Missbrauchs-/Balance-Schutz:** Destruktive Buttons (Runde abbrechen, Punkte löschen) brauchen
  Long-Press (800 ms) mit Füll-Ring statt Bestätigungs-Dialog — schnell, aber nicht versehentlich.
- **Auto-GM:** Nutzt dieselbe Aktions-API; das Cockpit ist nur eine Bedienoberfläche über einem
  einheitlichen „GM-Command"-Kanal (wichtig fürs spätere Copilot-Hybrid, Idee 24).
- **Aufwand:** L · **Prio:** MUST

### 2. „Spickzettel" — Geheim-Ansicht mit Antworten & Live-Tipps
- **GM-UI:** Rechtes Panel zeigt pro Frage: korrekte Antwort (fett), Erklärung/Fun-Fact zum Vorlesen,
  und LIVE einlaufende Spieler-Antworten (wer hat schon getippt, was, wie lange gebraucht).
  Bei Schätzfragen ein Zahlenstrahl mit allen Tipps als Punkte. Blur-Toggle („Über-die-Schulter-Schutz"),
  falls Spieler in der Nähe sitzen.
- **Wirkung Bildschirm/Handys:** Keine — rein geheim. Ermöglicht aber Moderations-Gold: „Ui, Lisa
  ist SEHR sicher, sie hat nach 2 Sekunden getippt…"
- **Schutz:** Geheim-Panel nie im Bühnen-Spiegel; Screenshot-freundliche Elemente vermeiden
  (Antwort erst nach Auflösung im Log sichtbar).
- **Auto-GM:** Nutzt dieselben Daten für Kommentar-Generierung („3 von 5 haben schon geantwortet!")
  als Bildschirm-Ticker.
- **Aufwand:** M · **Prio:** MUST

### 3. „Zeitleiste der Wahrheit" — Aktions-Log mit Undo-Stack
- **GM-UI:** Ausklappbarer Streifen am unteren Rand: jede GM-Aktion als Chip (⏱ +30 s, 💰 −200 an Ben,
  🎡 Glücksrad). Tap auf Chip = Details, Swipe nach links = Undo (wo semantisch möglich; Punkte,
  Joker, Regel-Karten ja — abgespielte Sounds nein). Undo erzeugt selbst einen Log-Eintrag.
- **Wirkung Bildschirm/Handys:** Undo von Punkten zeigt auf dem Bildschirm eine transparente
  „Korrektur!"-Kachel — nichts passiert heimlich, das hält den GM ehrlich und die Runde fair.
- **Schutz:** Das Log IST der Schutz — Session-Ende-Export („Regie-Protokoll") zeigt allen, was der GM
  getan hat. Optional „Transparenz-Modus": jede manuelle Punktänderung wird sofort öffentlich betitelt.
- **Auto-GM:** Schreibt ins selbe Log; nach der Show kann man Auto-Entscheidungen nachvollziehen
  (gut fürs Balancing der Auto-GM-Heuristiken).
- **Aufwand:** M · **Prio:** MUST

---

## B. Zeit & Runden-Kontrolle

### 4. „Zeitmaschine" — Timer anhalten, verlängern, dramatisieren
- **GM-UI:** Timer-Widget immer sichtbar in der Cockpit-Mitte. Buttons: ⏸ Pause, ▶ Weiter,
  +15 s, +30 s, „Freeze!" (Timer friert MIT Eis-Effekt und Sound auf dem Bildschirm ein — Pause als
  Show-Moment statt Verlegenheits-Stopp).
- **Wirkung Bildschirm/Handys:** Bildschirm-Timer reagiert sofort (Eis-Overlay, Ticken stoppt);
  Handys zeigen „Zeit angehalten — der Show-Master spricht!" und sperren Eingaben optional.
- **Schutz:** Max. 2 Verlängerungen pro Frage (danach Button ausgegraut mit Tooltip „Genug gedehnt!");
  alles im Log. Verlängerung gilt immer für ALLE, nie für einzelne Spieler (sonst Timing-Unfairness).
- **Auto-GM:** Verlängert automatisch +15 s, wenn <50 % der Spieler geantwortet haben und die
  Restzeit <5 s ist (max. 1×); pausiert bei Verbindungsverlust eines Spielers automatisch.
- **Aufwand:** S · **Prio:** MUST

### 5. „Encore!" — Runden-Verlängerung um Extra-Fragen
- **GM-UI:** Am Runden-Ende erscheint neben „Runde beenden" ein „Encore +1 Frage"-Button
  (mit Vorschau der Zusatzfrage aus dem Fragen-Regal, Idee 7). Bei knappem Spielstand pulsiert er.
- **Wirkung Bildschirm/Handys:** Bildschirm: „ENCORE! Der Show-Master will mehr!"-Banner mit
  Trommelwirbel; Handys vibrieren kurz. Fühlt sich an wie eine Zugabe, nicht wie Verzögerung.
- **Schutz:** Max. 2 Encores pro Runde; Encore-Fragen zählen mit normalem Punktwert (kein heimlicher
  Punkte-Multiplikator ohne Regel-Karte).
- **Auto-GM:** Triggert Encore, wenn Platz 1 und 2 weniger als eine Fragen-Wertung auseinanderliegen
  („es bleibt spannend!").
- **Aufwand:** S · **Prio:** SHOULD

### 6. „Bananen-Pause" — Der 10-Minuten-Timeout-Screen
- **GM-UI:** Pause-Button im Dock → Sheet mit Dauer-Wahl (5/10/15 min oder offen), optional
  Pause-Text („Pizza ist da!"). „Pause beenden"-Button danach prominent.
- **Wirkung Bildschirm/Handys:** Bildschirm: entspannter Pause-Screen mit Countdown, Zwischenstand
  als „Kontoauszug", Loop-Musik und rotierenden Fun-Facts zu bisherigen Antworten. Handys:
  Countdown + „Lehn dich zurück"-Screen; 60 s vor Ende weckt ein sanfter Gong alle Geräte.
- **Schutz:** Spielzustand wird beim Pausieren serverseitig gesichert (Pause = natürlicher
  Save-Point); Reconnect-Fenster für abgesprungene Handys.
- **Auto-GM:** Schlägt nach ~45 min Spielzeit von sich aus eine Pause vor (Voting aufs Handy:
  „Pause?" Ja/Nein — Mehrheit entscheidet).
- **Aufwand:** M · **Prio:** MUST

### 7. „Fragen-Regal" — Live-Picker für Fragen, Kategorien, Schwierigkeit
- **GM-UI:** Horizontales Regal mit den nächsten 5 geplanten Fragen als Karten (Kategorie-Farbe,
  Schwierigkeits-Sterne, Fragentext-Preview). Karte wegwischen = verwerfen, Nachschub rückt nach.
  Filter-Chips oben: Kategorie, Schwierigkeit, „noch nie gespielt". Drag einer Karte auf Position 1 =
  kommt als Nächstes. Suchen-Feld für gezieltes Reinziehen („irgendwas mit Fußball für Tom").
- **Wirkung Bildschirm/Handys:** Unsichtbar bis zur Ausspielung — der GM kuratiert im Verborgenen,
  die Show wirkt maßgeschneidert.
- **Schutz:** Verworfene Fragen landen in „Verworfen"-Ablage (wiederherstellbar); Log vermerkt Swaps,
  damit man Muster erkennt (z. B. GM meidet immer eine Kategorie → Feedback an Content-Team).
- **Auto-GM:** Bestückt das Regal nach Kategorien-Rotation + Schwierigkeits-Kurve (leicht → schwer
  pro Runde) und meidet Kategorien, in denen ein Spieler laut Profil-Historie 0 % trifft.
- **Aufwand:** L · **Prio:** MUST

### 8. „Notausgang" — Skip-Game & Buggy-Flag
- **GM-UI:** In jedem Minispiel oben rechts ein dezentes „…"-Menü: „Spiel überspringen",
  „Als fehlerhaft melden" (mit 1-Tap-Grund: hängt / unfair / unverständlich / Crash), „Neu starten".
- **Wirkung Bildschirm/Handys:** Bei Skip: charmanter Übergang („Der Affe hat den Stecker gezogen —
  weiter geht's!"), bereits erspielte Punkte des Spiels werden je nach Wahl behalten oder annulliert
  (GM wählt im Skip-Sheet). Kein peinlicher Freeze-Moment.
- **Schutz:** Buggy-Flags gehen in eine serverseitige Telemetrie-Liste (Spiel-ID, Zustand,
  Fehlergrund) — nach 3 Flags wird das Minispiel automatisch aus der Auto-Rotation genommen,
  bis es entflaggt wird. Skip annulliert nie rückwirkend frühere Runden.
- **Auto-GM:** Erkennt harte Fehlerbilder selbst (keine Zustandsänderung >30 s, Exception) und
  skippt mit demselben Übergang + Auto-Flag.
- **Aufwand:** M · **Prio:** MUST

---

## C. Punkte, Fairness & Fürsorge

### 9. „Bananen-Bank" — Punkte geben/abziehen mit Begründungs-Chips
- **GM-UI:** Tap auf einen Spieler in der Live-Liste → Punkte-Sheet: Stepper (±50/±100/±500),
  Freibetrag, und Begründungs-Chips („Bonus: bester Spruch", „Strafe: reingerufen", „Korrektur:
  Frage war doof", „Style-Punkte"). Begründung ist Pflicht (1 Tap), Betrag + Chip erscheinen im Log.
- **Wirkung Bildschirm/Handys:** Bildschirm: animierte Geldbörsen-Transaktion mit Chip-Text
  („+100 an Mia — bester Spruch!"), Kassen-Kling. Handy des Betroffenen: Kontoauszug-Zeile.
  Öffentlichkeit macht Willkür sozial teuer.
- **Schutz:** Soft-Cap: manuelle Punkte pro Spieler und Runde auf ±20 % des Runden-Maximums begrenzt
  (Override via Long-Press möglich, wird aber ROT geloggt und am Runden-Ende eingeblendet). Undo via
  Zeitleiste.
- **Auto-GM:** Vergibt nur regelbasierte Boni (z. B. Comeback-Bonus, Idee 11) — nie freihändig.
- **Aufwand:** M · **Prio:** MUST

### 10. „Maßanzug-Modus" — Unterschiedliche Fragen für unterschiedliche Spieler
- **GM-UI:** Vor einer „Maßanzug-Runde" zeigt das Cockpit eine Zuordnungs-Matrix: Spieler-Zeilen,
  je 3 Fragen-Vorschläge pro Spieler (aus Profil/Alter/Selbstauskunft „Meine Themen" beim Join).
  GM tauscht per Tap; Schwierigkeits-Sterne zeigen, dass alle Fragen gleichwertig sind.
- **Wirkung Bildschirm/Handys:** Bildschirm erklärt das Format offen: „Jeder bekommt SEINE Frage —
  gleiche Schwierigkeit, anderes Thema!" Jedes Handy zeigt die individuelle Frage; der Bildschirm
  zeigt reihum die Frage des gerade auflösenden Spielers (alle können mitraten → bleibt gemeinsam).
- **Schutz:** Punktwert ist an die Schwierigkeits-Stufe gekoppelt, nicht an die Einzelfrage — GM kann
  keinem Spieler heimlich eine „500-Punkte-Gratisfrage" geben. Zuordnung steht im Log.
- **Auto-GM:** Matcht Fragen automatisch über Themen-Tags aus dem Join-Screen („Wähle 3 Themen, in
  denen du stark bist") und gleicht Schwierigkeit über die Trefferquoten-Historie an (Kinder bekommen
  altersgerechte Fragen — Fairness bei Wissens-Gefälle, z. B. Familienrunden).
- **Aufwand:** L · **Prio:** MUST

### 11. „Aufholjagd" — Underdog-Boost mit Empfehlungs-Badge
- **GM-UI:** In der Live-Liste bekommt der abgeschlagene Spieler automatisch ein pulsierendes
  🐒-Badge („Underdog-Kandidat: 800 Punkte hinter Platz 3"). Tap → Boost-Menü: „Doppelte Punkte
  nächste Frage", „+300 Startkapital", „Geheim-Joker schicken". Der GM entscheidet, das Cockpit
  empfiehlt nur.
- **Wirkung Bildschirm/Handys:** Wahlweise öffentlich inszeniert („AUFHOLJAGD! Ben spielt die
  nächste Frage doppelt!") oder still (nur Bens Handy weiß es — Auflösung am Runden-Ende:
  „Ben hatte heimlich den Doppel-Boost!" → zweiter Show-Moment).
- **Schutz:** Max. 1 Boost pro Spieler und Runde; Boost nie für Platz 1–2 auswählbar; stille Boosts
  werden IMMER am Runden-Ende aufgedeckt (kein dauerhaft heimliches Schummeln).
- **Auto-GM:** Aktiviert Underdog-Boost automatisch, wenn ein Spieler >35 % hinter dem Median liegt
  und 2 Runden nichts gewonnen hat; inszeniert öffentlich.
- **Aufwand:** M · **Prio:** MUST

### 12. „Gnaden-Automat" — Joker & Skips aufs Handy vergeben
- **GM-UI:** Joker-Palette im Dock: 50:50, „Frage tauschen", „Zeit ×2", „Publikums-Blick"
  (sieht 3 Sekunden die Antwort-Verteilung), „Skip ohne Punktverlust". Drag eines Jokers auf einen
  Spieler(-Avatar) oder auf „Alle".
- **Wirkung Bildschirm/Handys:** Handy des Empfängers: Joker fliegt mit Konfetti-Animation ins
  Inventar (nutzbar per Tap, wenn passend). Bildschirm optional: „Der Show-Master war großzügig…"
  ohne zu verraten, wer was bekam (Mystery).
- **Schutz:** Joker-Budget pro Session (z. B. 6 Stück), im Cockpit als Restanzeige — verhindert
  Joker-Inflation; Vergaben im Log.
- **Auto-GM:** Verteilt Joker als Meilenstein-Belohnungen (3 richtige in Folge = 50:50) und als
  stilles Fairness-Werkzeug an Schlusslichter.
- **Aufwand:** M · **Prio:** SHOULD

### 13. „Flüster-Tipp & Tipp-Kanone" — Hinweise global und individuell
- **GM-UI:** Bei jeder Frage zwei Buttons im Geheim-Panel: 📢 „Tipp an alle" (zeigt vorbereitete
  Hint-Stufen 1/2/3 aus den Fragendaten, mit Punktabzug-Vorschau) und 🤫 „Flüster-Tipp" (Spieler
  wählen → vorgefertigten Hint schicken oder Freitext tippen/diktieren).
- **Wirkung Bildschirm/Handys:** Global: Hint erscheint auf dem Bildschirm mit „Tipp-Kosten:
  −25 % Punkte für diese Frage" für alle sichtbar. Individuell: Nur das Ziel-Handy zeigt eine
  Flüster-Blase (mit dezentem Vibrieren); niemand sonst sieht etwas.
- **Schutz:** Flüster-Tipps werden am Runden-Ende als Zähler aufgedeckt („Ben bekam 2 Flüster-Tipps")
  — Inhalt bleibt geheim, aber die Existenz ist transparent; max. 2 pro Spieler/Runde.
- **Auto-GM:** Global-Hints nach 60 % Zeitablauf, wenn niemand richtig liegt; Flüster-Tipps
  automatisch nur an Spieler mit aktiviertem „Unterstützungs-Modus" (z. B. jüngere Kinder,
  beim Join wählbar).
- **Aufwand:** M · **Prio:** MUST

### 14. „Roter Buzzer" — Frage als fehlerhaft markieren & sauber zurückrollen
- **GM-UI:** Großer roter „Frage kaputt!"-Button im Geheim-Panel (Long-Press). Sheet: Grund wählen
  (Antwort falsch / mehrdeutig / veraltet / Tippfehler) → Auswahl: „Punkte annullieren" oder
  „Allen die Punkte geben" (großzügig) → Ersatzfrage aus dem Regal rückt automatisch nach.
- **Wirkung Bildschirm/Handys:** Bildschirm: Die Frage wird theatralisch „geschreddert"
  (Aktenvernichter-Animation, Alarm-Sound) — aus dem Fehler wird ein Lacher. Punkte-Rollback
  sichtbar als Korrektur-Ticker.
- **Schutz:** Rollback ist atomar (Antworten, Punkte, Joker-Verbrauch dieser Frage) — kein
  halbgarer Zustand; Flag + Grund gehen an die Content-Datenbank (Frage wird zur Redaktion
  markiert und aus der Rotation genommen).
- **Auto-GM:** Markiert Fragen automatisch, wenn im Voting „Frage doof?" (Idee 15) >50 % zustimmen,
  und wählt standardmäßig die großzügige Variante.
- **Aufwand:** M · **Prio:** MUST

---

## D. Show-Momente & Chaos-Werkzeuge

### 15. „Publikums-Entscheid" — Ad-hoc-Votings triggern
- **GM-UI:** Voting-Button im Dock → Vorlagen-Galerie: „Nächste Kategorie wählen", „Wer muss die
  Straf-Aufgabe machen?", „Frage doof? 👍/👎", „Pause?", „Sudden-Death-Finale?" + Freitext-Voting
  (Frage + 2–4 Antwort-Buttons selbst tippen). Live-Balken der Stimmen im Cockpit.
- **Wirkung Bildschirm/Handys:** Handys werden sofort zu Abstimm-Geräten (große Buttons);
  Bildschirm zeigt Live-Balkendiagramm mit Countdown und Ergebnis-Fanfare.
- **Schutz:** Votings sind anonym auf dem Bildschirm, aber der GM sieht (optional) die Einzelstimmen
  im Geheim-Panel; Ergebnis-Umsetzung bleibt GM-Entscheidung (Voting ist beratend, außer der GM
  markiert es als „bindend" — dann führt der Server das Ergebnis automatisch aus).
- **Auto-GM:** Nutzt Votings als Standard-Mechanik für alle Geschmacksfragen (Kategorie-Wahl,
  Pausen, Strafen-Ziel) — so bleibt der Auto-GM „demokratisch" statt willkürlich.
- **Aufwand:** M · **Prio:** MUST

### 16. „Regel-Karten" — Special Rules als sammelbares Deck
- **GM-UI:** Karten-Fächer im Dock: „Doppelte Punkte", „Stille Runde (nur Emoji-Jubel)",
  „Antworten-Tausch (du tippst für deinen Nachbarn)", „Alles-oder-nichts", „Zeitlupe (30 s statt 10)",
  „Umgekehrte Punkte (Letzter gewinnt die Frage)". Karte auf die Bühne ziehen = gilt ab nächster Frage;
  aktive Regel klebt sichtbar am Bühnen-Spiegel.
- **Wirkung Bildschirm/Handys:** Bildschirm: Karte dreht sich groß ein mit eigenem Jingle; Handys
  passen ihre UI an (z. B. Nachbar-Name beim Antworten-Tausch). Regeln enden automatisch
  (1 Frage / 1 Runde, auf der Karte definiert) — der GM muss nichts zurückbauen.
- **Schutz:** Max. 1 aktive Regel-Karte gleichzeitig; „Alles-oder-nichts" nie in der letzten Runde
  ohne Warnhinweis (kann Sieg entscheiden); alles im Log.
- **Auto-GM:** Zieht pro Session 2–3 Karten an dramaturgisch passenden Stellen (Preset-abhängig,
  Idee 21: „chaotisch" zieht öfter und wilder).
- **Aufwand:** L · **Prio:** SHOULD

### 17. „Pranger mit Augenzwinkern" — Bestrafungs-Panel
- **GM-UI:** Strafen-Palette: „Handy-Erdbeben" (Dauer-Vibration 5 s), „Clowns-Avatar bis Rundenende",
  „Zeit-Malus −3 s nächste Frage", „Straf-Aufgabe" (Karte vom Bildschirm vorlesen: „Antworte eine
  Runde lang singend"), „Bananen-Steuer −100". Ziehen auf Spieler; Vorschau, was passiert.
- **Wirkung Bildschirm/Handys:** Bildschirm inszeniert die Strafe als Show-Element (Gerichts-Gong,
  Steckbrief-Einblendung); das Ziel-Handy zeigt die Strafe groß und (wichtig!) einen
  „Ertragen"-Button zum Bestätigen — der Bestrafte bleibt handelnder Teil des Spiels.
- **Schutz:** Strafen sind mechanisch gedeckelt (nie mehr als −100 Punkte oder −3 s); ein Spieler,
  der 2× in Folge bestraft wurde, ist für die nächste Strafe gesperrt (Anti-Mobbing-Regel, hart im
  Server); Familienmodus blendet bestimmte Strafen aus.
- **Auto-GM:** Bestraft nur regelbasiert und angekündigt (z. B. „Wer als Letzter antwortet, zahlt
  Bananen-Steuer!") — nie überraschend-persönlich.
- **Aufwand:** M · **Prio:** SHOULD

### 18. „Rad des Schicksals" — Glücksrad triggern (ehrlich oder gezinkt)
- **GM-UI:** Glücksrad-Button im Dock → Sheet: Rad-Typ wählen (Punkte-Rad, Ereignis-Rad mit
  Regel-Karten-Feldern, Strafen-Rad, Kategorie-Rad). Geheim-Option „Gezinktes Rad": GM tippt
  vorher das Zielfeld an — das Rad landet dort mit glaubwürdiger Physik-Animation.
- **Wirkung Bildschirm/Handys:** Bildschirm: großes Rad mit Trommelwirbel, Handys können per
  „ALLE SCHÜTTELN!"-Aufforderung gemeinsam den Schwung geben (Accelerometer/Tap-Frequenz) —
  kollektiver Hype-Moment.
- **Schutz:** Gezinkte Dreh-Vorgänge werden ROT geloggt und (Standard-Einstellung) am Session-Ende
  im Regie-Protokoll aufgedeckt — Zinken ist ein Dramaturgie-Werkzeug („der Underdog gewinnt das
  Rad"), kein Dauerbetrug; abschaltbar nur in den erweiterten Einstellungen.
- **Auto-GM:** Dreht ehrlich, außer die Fairness-Heuristik greift (Underdog-Fenster) — dann zinkt
  auch der Auto-GM, loggt es aber genauso.
- **Aufwand:** M · **Prio:** SHOULD

### 19. „Applaus-Knopf" — Soundboard & Szenen-Blenden
- **GM-UI:** 2×4-Soundboard-Grid im Dock: Applaus, Trommelwirbel, Buzzer-Fail, „Ohhh!",
  Kassen-Kling, Grillen-Zirpen (für peinliche Stille), Konfetti (visuell), Blackout (Bildschirm
  1 s schwarz — für „Technik-Gag" oder Neustart eines Moments).
- **Wirkung Bildschirm/Handys:** Sound + passender Kurz-Effekt auf dem Bildschirm; Konfetti
  optional auch auf allen Handys gleichzeitig (billiger, großer Wow-Effekt).
- **Schutz:** Rate-Limit (max. 1 Sound/2 s), sonst wird aus Regie Krawall; Sounds sind nicht undo-bar
  und stehen deshalb nur als Ereignis im Log.
- **Auto-GM:** Spielt dieselben Sounds regelgetrieben (richtige Antwort → Kling; alle falsch →
  Grillen) — das Soundboard definiert das akustische Vokabular für beide GM-Arten.
- **Aufwand:** S · **Prio:** SHOULD

---

## E. Dramaturgie-Intelligenz & Feedback

### 20. „Drama-Meter" — Spannungs-Anzeige mit Regie-Empfehlungen
- **GM-UI:** Schmale Leiste über der Live-Liste: Spannungs-Score 0–100, berechnet aus Score-Abstand
  Platz 1↔2, Streuung des Felds, Antwort-Tempo-Trend und Runden-Restzahl. Darunter kontextuelle
  Empfehlungs-Chips: „Abstand riesig → Regel-Karte ‚Doppelte Punkte'?", „Ben 3 Runden ohne Treffer →
  Underdog-Boost?", „Alle antworten in <3 s → Schwierigkeit rauf?". Chip antippen = Aktion vorbefüllt.
- **Wirkung Bildschirm/Handys:** Indirekt — die Show wird spürbar besser getaktet, ohne dass Spieler
  das Werkzeug je sehen.
- **Schutz:** Reine Empfehlungen, nie Auto-Ausführung im Mensch-Modus; die Heuristik erklärt sich
  immer in einem Satz (kein Blackbox-Gefühl für den GM).
- **Auto-GM:** Das Drama-Meter IST der Kern des Auto-GM — dieselben Heuristiken führen im
  Auto-Modus direkt aus. Ein Werkzeug, zwei Betriebsarten.
- **Aufwand:** L · **Prio:** SHOULD

### 21. „Regie-Presets" — locker / gemein / chaotisch
- **GM-UI:** Preset-Wahl beim Session-Start (und live wechselbar im Einstellungs-Sheet):
  **Locker** (lange Timer, milde Strafen aus, großzügige Hints, Auto-Encore aus), **Gemein**
  (kurze Timer, Bananen-Steuer aktiv, Strafen-Rad im Pool, seltene Hints), **Chaotisch**
  (Regel-Karten-Frequenz hoch, Ereignis-Rad oft, Antworten-Tausch möglich). Preset färbt das
  Cockpit dezent ein (grün/rot/lila) und filtert, welche Werkzeuge im Dock prominent sind.
- **Wirkung Bildschirm/Handys:** Bildschirm kündigt das Preset als „heutige Show-Stimmung" mit
  eigenem Intro-Jingle an — Erwartungs-Management für die Spieler.
- **Schutz:** Preset-Wechsel mitten in der Runde erst ab der nächsten Frage wirksam; Familienmodus
  überschreibt Preset-Inhalte (Strafen-Filter) hart.
- **Auto-GM:** Presets parametrieren direkt die Auto-GM-Heuristiken (Hint-Schwellen,
  Karten-Frequenz, Timer) — dieselbe Konfigurationsdatei für Mensch und Software.
- **Aufwand:** M · **Prio:** SHOULD

### 22. „Stimmungs-Barometer" — Spieler-Feedback einsammeln
- **GM-UI:** Zwei Werkzeuge: (a) „Blitz-Stimmung"-Button → alle Handys zeigen 3 s lang 5 Emojis
  (🤩🙂😐🥱😡), Ergebnis nur im Cockpit als Verlaufs-Kurve über die Session; (b) automatisches
  End-Feedback nach der Finale-Zeremonie: 3 Fragen aufs Handy („Lieblings-Minispiel?",
  „Tempo okay?", „1 Wort für heute?"), Ergebnis als „Presse-Stimmen" auf dem Abspann-Bildschirm.
- **Wirkung Bildschirm/Handys:** Blitz-Stimmung ist für Spieler ein Mini-Moment (3 s), fürs
  Cockpit Gold: die Kurve zeigt, WANN die Stimmung kippte (nach welchem Spiel/welcher Aktion).
  End-Feedback als „Presse-Stimmen" macht aus Datensammlung einen Show-Abschluss.
- **Schutz:** Blitz-Stimmung anonym (auch für den GM nur aggregiert); max. 3 Blitz-Abfragen pro
  Session (sonst nervt's); Feedback wird mit Spiel-Telemetrie (Idee 8) verknüpft gespeichert.
- **Auto-GM:** Fragt Blitz-Stimmung automatisch nach jedem 2. Minispiel ab und reagiert:
  2× 🥱 hintereinander → Tempo-Preset anziehen, Regel-Karte ziehen oder Spiel-Wechsel vorschlagen.
- **Aufwand:** M · **Prio:** SHOULD

### 23. „Regie-Führerschein" — GM-Onboarding für Erstnutzer
- **GM-UI:** Beim ersten Cockpit-Start: 3-minütige interaktive Tour mit einer Fake-Session
  (Bot-Spieler „Kokos", „Splitter", „Banana Joe") — der neue GM MUSS einmal Zeit verlängern, einen
  Tipp flüstern, Punkte vergeben und den roten Buzzer drücken, jeweils mit Erklär-Blase. Danach:
  Kontext-Coachmarks („Du hast noch nie ein Voting gestartet — hier wäre ein guter Moment") und ein
  „Souffleuse"-Modus: dezente Einblendungen, was ein TV-Moderator jetzt sagen würde („Frag Lisa,
  wie sicher sie sich ist!").
- **Wirkung Bildschirm/Handys:** Tour läuft komplett im Cockpit (Bildschirm zeigt derweil
  „Show-Master bereitet die Show vor…" mit Warte-Gag) — kein toter Bildschirm für die Gruppe.
- **Schutz:** Tour überspringbar, Coachmarks abschaltbar; Souffleuse-Texte kommen aus den
  Fragendaten (Fun-Facts) — kein Improvisations-Druck.
- **Auto-GM:** Entfällt — aber die Souffleuse-Texte sind exakt die Sprüche, die der Auto-GM als
  Bildschirm-Moderation ausspielt (ein Content-Topf für beide).
- **Aufwand:** M · **Prio:** SHOULD

### 24. „Copilot-Regie" — Auto-GM schlägt vor, Mensch drückt ab
- **GM-UI:** Dritter Betriebsmodus zwischen Mensch und Auto-GM: Der Auto-GM läuft mit, führt aber
  nichts aus, sondern legt Vorschlags-Karten in eine Ecke des Cockpits („Jetzt Encore?", „Hint an
  alle?", „Rad drehen?") — 1 Tap = ausführen, Wegwischen = verwerfen. Ideal für nervöse Erst-GMs
  und für Show-Master, die lieber moderieren als bedienen.
- **Wirkung Bildschirm/Handys:** Wie bei manuellen Aktionen — Spieler merken den Unterschied nicht.
- **Schutz:** Vorschläge verfallen nach 20 s automatisch (kein Stau); Log unterscheidet
  „Copilot-bestätigt" von „manuell" (fürs Heuristik-Tuning).
- **Auto-GM:** Ist die Brücken-Architektur: Auto-GM = Copilot mit Auto-Bestätigung. Ein
  Entscheidungs-Kern, drei Modi (Mensch / Copilot / Auto) — hält die Codebasis schlank.
- **Aufwand:** M (wenn Idee 1 + 20 stehen) · **Prio:** SHOULD

### 25. „Zweiter Bildschirm für die Hosentasche" — GM-Notfall-Fernbedienung
- **GM-UI:** Reduzierte Cockpit-Ansicht fürs GM-HANDY (falls das iPad der Bildschirm ist oder der
  GM aufsteht, um Snacks zu holen): nur Timer-Kontrolle, Nächste-Frage, Pause, Soundboard-Top-4
  und Not-Aus. Läuft als gleiche HTTP-Session, Cockpit und Fernbedienung synchron.
- **Wirkung Bildschirm/Handys:** Keine sichtbare — aber die Show stockt nie, weil der GM den Raum
  nie „verlassen" muss.
- **Schutz:** Fernbedienung kann keine Punkte ändern und nichts Destruktives (bewusst kastriert);
  gleichzeitige Eingaben löst der Server per Last-Write-Wins + Log.
- **Auto-GM:** Entfällt; nützlich aber im Auto-GM-Modus als „Not-Bremse" für den Gastgeber
  (Pause/Skip, ohne voller GM zu sein).
- **Aufwand:** M · **Prio:** COULD

---

## Querschnitts-Prinzipien (für alle Werkzeuge)

1. **Ein Kommando-Kanal:** Jede GM-Aktion (Mensch, Copilot, Auto) läuft als dasselbe
   „GM-Command" über den Server — eine Logik, drei Bedienarten, ein Log.
2. **Transparenz schlägt Verbot:** Fast nichts ist verboten, aber alles wird geloggt und vieles am
   Runden-/Session-Ende inszeniert aufgedeckt (Flüster-Tipps, gezinkte Räder, rote Overrides) —
   Missbrauchsschutz durch soziale Sichtbarkeit statt durch Bevormundung des GMs.
3. **Fehler werden Show:** Roter Buzzer, Notausgang, Blackout — jedes Problem-Werkzeug hat eine
   Bühnen-Inszenierung, damit Pannen Lacher statt Peinlichkeit erzeugen.
4. **Fairness ist mechanisch:** Caps, Anti-Mobbing-Sperre, Schwierigkeits-Kopplung beim
   Maßanzug-Modus — die harten Grenzen sitzen im Server, nicht in der UI.
5. **Zeit/Zufall injiziert:** Timer-Manipulation und (gezinkte) Räder brauchen injizierte Clock/RNG —
   deckt sich mit der bestehenden Repo-Regel (Clock-Muster, RNG als Parameter) und macht alle
   GM-Werkzeuge testbar.

## Priorisierungs-Übersicht

| # | Idee | Aufwand | Prio |
|---|------|---------|------|
| 1 | Regiepult (3-Zonen-Cockpit) | L | MUST |
| 2 | Spickzettel (Geheim-Ansicht) | M | MUST |
| 3 | Zeitleiste der Wahrheit (Log + Undo) | M | MUST |
| 4 | Zeitmaschine (Timer-Kontrolle) | S | MUST |
| 5 | Encore! (Runden-Verlängerung) | S | SHOULD |
| 6 | Bananen-Pause (Timeout-Screen) | M | MUST |
| 7 | Fragen-Regal (Live-Picker) | L | MUST |
| 8 | Notausgang (Skip + Buggy-Flag) | M | MUST |
| 9 | Bananen-Bank (Punkte ±) | M | MUST |
| 10 | Maßanzug-Modus (individuelle Fragen) | L | MUST |
| 11 | Aufholjagd (Underdog-Boost) | M | MUST |
| 12 | Gnaden-Automat (Joker-Vergabe) | M | SHOULD |
| 13 | Flüster-Tipp & Tipp-Kanone | M | MUST |
| 14 | Roter Buzzer (fehlerhafte Frage) | M | MUST |
| 15 | Publikums-Entscheid (Votings) | M | MUST |
| 16 | Regel-Karten (Special Rules) | L | SHOULD |
| 17 | Pranger mit Augenzwinkern (Strafen) | M | SHOULD |
| 18 | Rad des Schicksals (Glücksrad) | M | SHOULD |
| 19 | Applaus-Knopf (Soundboard) | S | SHOULD |
| 20 | Drama-Meter (Spannungs-Anzeige) | L | SHOULD |
| 21 | Regie-Presets (locker/gemein/chaotisch) | M | SHOULD |
| 22 | Stimmungs-Barometer (Feedback) | M | SHOULD |
| 23 | Regie-Führerschein (Onboarding) | M | SHOULD |
| 24 | Copilot-Regie (Hybrid-Modus) | M | SHOULD |
| 25 | Hosentaschen-Fernbedienung | M | COULD |
