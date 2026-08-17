# MONKEY MONEY — Ideen-Paket 15/20: Profile, Stats, Bestenlisten & Admin-Analytics

Ideen-Agent 15/20 · reine Ideation, keine Code-Änderungen.
Kontext: Jackbox/Buzz-artige Quiz-Show-Party-App, Node.js-Server, JSON/SQLite-Storage,
alles läuft lokal auf dem Server des Gastgebers (kein Cloud-Zwang).

Legende: **Aufwand** S (klein, isoliert), M (mittel, mehrere Module), L (groß, Architektur berührt) ·
**Prio** P1 (Kern-Erlebnis, früh bauen), P2 (starker Mehrwert), P3 (Nice-to-have / später).

---

## (a) PROFIL-System

### Idee 1 — Frictionless-Profil: Name + Avatar, fertig
Profil-Anlage in unter 10 Sekunden, ohne Account, ohne E-Mail, ohne Passwort-Zwang:
Name eintippen, Avatar aus einem Affen-Raster wählen (oder Zufalls-Affe), los geht's.
Der Server legt intern eine stabile `profile_id` (UUID) an; der Name ist nur Anzeige-Label
und darf sich später ändern, ohne dass Stats verloren gehen. Optional beim Anlegen:
eine 4-stellige PIN als „Schloss", damit niemand auf einer Party fremde Profile kapert —
aber die PIN ist optional, Partyspiele dürfen nicht an Login-Hürden sterben.
**Aufwand:** S · **Prio:** P1

### Idee 2 — Geräte-Wiedererkennung via localStorage-Token
Beim ersten Join speichert der Client ein zufälliges `device_token` im localStorage.
Der Server merkt sich, welche Profile zuletzt von diesem Token aus gespielt haben, und
zeigt beim nächsten Besuch sofort „Willkommen zurück — als wer spielst du heute?" mit den
bekannten Profilen als Ein-Klick-Kacheln. Kein Login, keine Cookie-Banner-Problematik
(alles lokal). Fallback bei gelöschtem Storage: Profil-Suche per Name + optionale PIN.
**Aufwand:** S–M · **Prio:** P1

### Idee 3 — Mehrere Profile pro Gerät + Geräte-Wechsel per Claim-Code
Ein Handy, mehrere Menschen: Das Gerät hält eine Liste verknüpfter Profile (Familie,
Mitbewohner). Umgekehrt kann ein Profil auf mehreren Geräten „bekannt" sein — der
Übertrag geht über einen kurzen Claim-Code (z. B. 6 Zeichen), den man am alten Gerät
im Profil anzeigen lässt und am neuen eingibt. Kein Account nötig, trotzdem portabel.
**Aufwand:** M · **Prio:** P1

### Idee 4 — Gast-Modus mit nachträglichem „Adoptieren"
Wer nur einen Abend mitspielt, joint als Gast (Auto-Name „Gast-Gibbon #3"). Gäste
tauchen in Match-Ergebnissen auf, aber nicht in All-time-Bestenlisten. Clou: Am
Match-Ende gibt es die Option „Diesen Abend behalten?" — der Gast wird in ein echtes
Profil umgewandelt und die Stats des Abends wandern rückwirkend mit. Das nimmt die
Anlege-Hürde komplett aus dem Spielstart raus.
**Aufwand:** M · **Prio:** P2

### Idee 5 — Profil-Karte: Lieblings-Kategorie, Nemesis, Bestleistungen
Jedes Profil hat eine teilbare „Spielerkarte" (Lobby-Ansicht + eigene Seite):
Avatar, Spitzname, Titel (siehe Idee 16), Lieblings-Kategorie (höchste Richtig-Quote
bei ≥ N Antworten), **Nemesis-Kategorie** (schlechteste Quote, liebevoll gerahmt:
„Erzfeind: Geografie 🙈"), schnellster Buzz aller Zeiten, höchster Einzel-Match-Gewinn,
längste Sieges-Serie. Die Karte ist das emotionale Zentrum des Stats-Systems — sie
macht aus Zahlen eine Identität.
**Aufwand:** M · **Prio:** P1

---

## (b) STATS-Katalog

### Idee 6 — Genauigkeits-Matrix: Kategorie × Schwierigkeit
Pro Spieler eine Matrix (Zeilen = Kategorien, Spalten = leicht/mittel/schwer) mit
Richtig-Quote und Antwort-Anzahl je Zelle. Anzeige als Heatmap auf der Profilseite.
Wichtig: Zellen mit < N Antworten ausgrauen („zu wenig Daten"), sonst entstehen
90 %-Quoten aus einer einzigen Antwort. Diese Matrix ist gleichzeitig die Datenbasis
für Lieblings-/Nemesis-Kategorie (Idee 5) und für adaptive Fragenauswahl (anderes Themenpaket).
**Aufwand:** M · **Prio:** P1

### Idee 7 — Reaktionszeit-Profil & Buzzer-Aggressivität
Pro Spieler: Median-Buzz-Zeit, schnellster Buzz, Verteilung (Histogramm), und ein
„Aggressivitäts-Index": Anteil der Buzzes, die VOR dem Ende der Frage-Vorlesung kamen,
plus Quote „gebuzzert, aber falsch". Daraus entstehen Archetypen fürs Match-Ende:
„Der Scharfschütze" (langsam, aber fast immer richtig) vs. „Die Kanone" (buzzt alles,
trifft die Hälfte). Buzz-Zeit immer relativ zum Frage-Anzeige-Zeitpunkt messen
(Server-Zeitstempel, injizierte Clock — passend zur Testbarkeits-Regel des Repos).
**Aufwand:** M · **Prio:** P1

### Idee 8 — Joker-/Tipp-Ökonomie pro Spieler
Welche Joker nutzt jemand, wann (früh/spät im Match, bei welchem Rückstand), und
was bringen sie (Richtig-Quote mit vs. ohne Joker)? Ergebnis-Perlen: „Deine
50:50-Joker retten dich in 71 % der Fälle" oder „Du hortest Joker bis zum Ende und
verlierst sie ungenutzt (4× passiert)". Gleiche Auswertung aggregiert hilft dem
Game-Design: Ist ein Joker zu stark/zu schwach?
**Aufwand:** M · **Prio:** P2

### Idee 9 — Money-Historie & Verlaufs-Kurven pro Match
Jede Kontostand-Änderung ist ein Event; daraus entsteht pro Match eine Kurven-Grafik
(alle Spieler übereinander): Führungswechsel, der große Absturz bei Frage 12, das
Comeback. Am Match-Ende als „Story des Abends" anzeigen, mit Auto-Markern
(„größter Einzelgewinn", „Führungswechsel #4"). Pro Profil zusätzlich die
Langzeit-Kurve: All-time-Money kumuliert über alle Matches.
**Aufwand:** M · **Prio:** P1

### Idee 10 — Serien & Rekorde (Streaks)
Getrackt werden: aktuelle/längste Sieges-Serie (Matches), längste Richtig-Serie
(Antworten in Folge, auch match-übergreifend), „Perfect Category" (alle Fragen einer
Kategorie im Match richtig), Teilnahme-Serie (Spielabende in Folge). Serien sind
billige, starke Motivatoren — und ein laufender Streak wird in der Lobby angezeigt
(„⚠️ Lena verteidigt heute ihre 5-Siege-Serie"), was sofort Dramaturgie erzeugt.
**Aufwand:** S–M · **Prio:** P2

### Idee 11 — Fragen-Statistik: der Lebenslauf jeder Frage
Pro Frage: Ausspiel-Zähler (gesamt + letzte 30 Tage), Richtig-Quote (global und je
nach Buzzer-/Wahlmodus getrennt!), Ø- und Median-Antwortzeit, Tipp-Nutzungs-Quote,
Skip-Rate, Anzahl „fehlerhaft"-Markierungen, Datum der letzten Ausspielung.
Getrennte Quoten je Spielmodus sind wichtig: Multiple-Choice-Raten verzerrt sonst
die „wahre" Schwierigkeit. Obendrauf als Lobby-Gag und Anomalie-Fänger: das Widget
„Frage der Schande / Frage des Ruhms" (niedrigste Richtig-Quote aller Zeiten bzw.
schnellste Ø-Buzz-Zeit — eine 0 %-Quote ist fast immer eine kaputte Frage).
Diese Tabelle ist das Fundament des Admin-Dashboards (d).
**Aufwand:** M · **Prio:** P1

### Idee 12 — Head-to-Head & Rivalen-Erkennung
Für jedes Spieler-Paar mit ≥ N gemeinsamen Matches: Sieg-Bilanz, Ø-Punktabstand,
„Angstgegner"-Flag. Die Lobby kann daraus Zündstoff machen: „Rückspiel! Tom führt
gegen Ali 4:2." Rein aus dem Event-Log ableitbar, kein zusätzliches Tracking nötig.
**Aufwand:** M · **Prio:** P3

---

## (c) BESTENLISTEN

### Idee 13 — Bestenlisten-Set mit Fairness-Schwellen
Kern-Boards: All-time-Money · Win-Rate (nur ab ≥ 10 Matches, sonst dominieren
1-Match-Wunder) · Kategorie-Meister je Kategorie (beste Quote bei ≥ 20 Antworten) ·
„Schnellster Buzzer" (Median statt Bestwert, damit ein Glücks-Buzz nicht ewig thront) ·
Underdog-Award-Sammler (wer gewinnt am häufigsten von einem hinteren Platz aus / holt
Awards trotz Außenseiter-Rolle). Jedes Board zeigt die Schwelle transparent an
(„ab 10 Matches gelistet — dir fehlen noch 3").
**Aufwand:** M · **Prio:** P1

### Idee 14 — Drei Anzeige-Orte, drei Dosierungen
1. **Lobby (TV-Screen):** rotierendes Karussell mit je einem Board + „heute anwesende
Spieler werden hervorgehoben" — die wichtigste Bühne, denn hier schauen alle hin.
2. **Match-Ende:** nur Deltas — „Neuer Rekord!", „Platz 3 → Platz 2 bei All-time-Money",
nie die volle Liste (Sieger-Moment nicht mit Tabellen erschlagen).
3. **Eigene Bestenlisten-Seite:** vollständig, filterbar (Zeitraum: All-time / Saison /
dieser Abend; nur Anwesende / alle).
**Aufwand:** M · **Prio:** P1

### Idee 15 — Saison-System mit Hall of Fame
All-time-Listen frieren Langzeit-Gewinner fest — Neulinge haben nie eine Chance.
Lösung: Saisons (z. B. quartalsweise oder vom Admin manuell geschnitten). Saison-Ende
= kleine Zeremonie im Lobby-Screen, Saisonsieger wandern in eine „Hall of Fame"-Seite,
Saison-Boards starten bei null. All-time bleibt parallel bestehen. Technisch nur ein
Zeitfenster-Filter über dem Event-Log — kein separater Datenbestand.
**Aufwand:** M · **Prio:** P2

### Idee 16 — Titel & Freischaltungen statt nur Ränge
Board-Spitzenplätze verleihen tragbare Titel, die neben dem Namen erscheinen:
„💰 Money-Boss", „⚡ Blitz-Buzzer", „🧠 Geografie-Meister", „🐒 Underdog-König".
Titel wandern automatisch, wenn jemand überholt wird — das erzeugt mehr Gesprächsstoff
als jede statische Tabelle („Du hast mir meinen Titel geklaut!"). Ergänzend
Meilenstein-Freischaltungen für Avatare/Profil-Rahmen (100 richtige Antworten →
Goldbananen-Rahmen; 10 Siege → Kronen-Affe) — kein Kaufsystem, reine Sammel-Motivation,
vollständig aus dem Event-Log (Idee 21) ableitbar.
**Aufwand:** M · **Prio:** P2

### Idee 17 — Anti-Frust: „Persönliche Bests" als Parallel-Ebene
Wer nie Board-Spitze wird, braucht trotzdem Fortschritt: Jede Match-Zusammenfassung
prüft persönliche Rekorde (schnellster eigener Buzz, beste eigene Quote in einem
Match, höchster eigener Gewinn) und feiert sie gleichwertig zur globalen Liste.
Kostet fast nichts, wirkt enorm gegen „Ich bin eh immer Letzter"-Frust.
**Aufwand:** S · **Prio:** P2

---

## (d) ADMIN-ANALYTICS-Dashboard (Fragen-Gesundheit)

### Idee 18 — Abnutzungs-Schutz: Auto-Pause nach N Ausspielungen
Jede Frage hat einen Ausspiel-Zähler; ab konfigurierbarem N (z. B. 3× in 60 Tagen
oder 5× gesamt in derselben Spielgruppe) wird sie automatisch pausiert („Cooldown")
und im Dashboard als „abgenutzt" gelistet. Der Admin sieht den Report
„zu oft gespielt" mit Ein-Klick-Reaktivierung und globalem N-Regler. Wichtig fürs
Party-Erlebnis: Wiederholte Fragen killen die Show schneller als schlechte Fragen.
**Aufwand:** M · **Prio:** P1

### Idee 19 — Schwierigkeits-Drift-Detektor mit Umstufungs-Vorschlag
Nightly-Job (oder on-demand) vergleicht markierte Schwierigkeit mit gemessener
Richtig-Quote (nur Fragen mit ≥ N Ausspielungen; Quoten je Spielmodus getrennt,
siehe Idee 11). Als „Mittel" markiert, aber 20 % Richtig-Quote → Vorschlag
„Hochstufen auf Schwer". Das Dashboard zeigt eine sortierte Drift-Liste mit
Konfidenz-Angabe und Buttons: Annehmen / Ablehnen / Frage ansehen. Entscheidungen
werden geloggt, damit dieselbe Frage nicht jede Woche wieder vorgeschlagen wird.
**Aufwand:** M · **Prio:** P1

### Idee 20 — Fehlerhaft-Queue mit GM-Kommentaren und Konsequenz
Spieler/GM können Fragen im Spiel als „fehlerhaft" flaggen (falsche Antwort, Tippfehler,
veraltet, mehrdeutig — Kategorie wählbar). Die Queue im Dashboard zeigt: Frage,
Flag-Grund, Zahl der Flags, GM-Freitext-Kommentare aus der Situation („Antwort B ist
seit 2024 auch richtig"). Workflow-Status: Neu → In Prüfung → Korrigiert → Verworfen.
Ab X Flags wird die Frage automatisch aus der Rotation genommen, bis ein Admin
entscheidet — kaputte Fragen dürfen nicht weiter ausgespielt werden.
**Aufwand:** M · **Prio:** P1

### Idee 21 — Kategorie-Lücken-Report („wo brennt der Fragen-Vorrat?")
Matrix Kategorie × Schwierigkeit mit: verfügbare Fragen, davon pausiert/geflaggt,
Verbrauchsrate (Ausspielungen pro Abend), daraus Reichweiten-Prognose („Sport/Schwer:
noch ~2 Abende Vorrat"). Sortiert nach Dringlichkeit; direkt verlinkt auf
„Neue Frage anlegen" mit vorausgefüllter Kategorie+Schwierigkeit. Verwandelt das
Dashboard von einem Rückspiegel in eine Einkaufsliste.
**Aufwand:** M · **Prio:** P2

### Idee 22 — Feedback-Inbox mit Themen-Clustering (leichtgewichtig)
Freitext-Feedback der Spieler (nach Match-Ende, optional) landet in einer Inbox.
Clustering pragmatisch ohne ML-Abhängigkeit: Keyword-/Tag-Regeln (Wörter wie
„zu schwer", „Wiederholung", „Bug", Kategorienamen) gruppieren Einträge in Themen-Stapel
mit Zähler („7× ‚Fragen wiederholen sich'"). Jeder Eintrag trägt Kontext-Metadaten
(Match-Id, gespielte Fragen), sodass „die Frage über Hauptstädte war falsch" direkt
zur Frage verlinkbar ist. Erweiterbar später um Embedding-Clustering, aber der
Regel-Ansatz deckt 80 % ab.
**Aufwand:** M · **Prio:** P2

---

## (e) DATEN-Design

### Idee 23 — Event-Log als Single Source of Truth
Architektur-Kern: JEDES Match-Ereignis ist eine append-only Zeile in einer
SQLite-Tabelle `events` (`event_id, match_id, ts, type, actor_profile_id,
question_id, payload_json`). Typen z. B. `match_started`, `question_shown`,
`buzz`, `answer_submitted`, `answer_judged`, `joker_used`, `money_changed`,
`question_flagged`, `match_ended`. ALLE Stats (b), Bestenlisten (c) und
Analytics (d) sind Ableitungen daraus — materialisiert in kleinen
Aggregat-Tabellen (`player_stats`, `question_stats`), die nach jedem Match
inkrementell aktualisiert und jederzeit per Replay komplett neu aufgebaut werden
können. Vorteile: neue Stats rückwirkend einführbar, Bugs in Aggregaten heilbar
(Replay), Match-Wiedergabe „wie ein Sportreplay" gratis. Zeitstempel über
injizierte Clock (Repo-Regel), damit alles testbar bleibt.
**Aufwand:** L (früh festlegen!) · **Prio:** P1 — wichtigste Einzelentscheidung des Pakets

### Idee 24 — Privacy-by-Design: lokal, exportierbar, löschbar
Alles liegt auf dem Server des Gastgebers — das ist das Privacy-Versprechen, und es
gehört als Feature ausgebaut: (1) **Profil-Export** als JSON/ZIP (Profil + alle
eigenen Events + abgeleitete Stats) per Klick; (2) **Profil-Löschung** zweistufig —
„Anonymisieren" (Events bleiben für Fragen-Statistiken, `actor_profile_id` wird
durch Tombstone ersetzt, Name/Avatar weg) oder „Vollständig löschen" (auch Events);
(3) **Server-Voll-Backup/Restore** als eine Datei (SQLite-Kopie + JSON-Assets), damit
ein Umzug auf neue Hardware trivial ist; (4) keinerlei Telefonie nach außen,
und ein Admin-Schalter „Statistiken für Gäste gar nicht erst speichern".
**Aufwand:** M · **Prio:** P1 (Export/Löschen), P2 (Voll-Backup)

### Idee 25 — Retention- & Kompaktierungs-Strategie
Damit das Event-Log über Jahre nicht zum Problem wird: Events älter als X Monate
werden zu Monats-Aggregaten kompaktiert (konfigurierbar, Default: nie — lokale
SQLite verkraftet Hunderttausende Zeilen locker), plus `VACUUM`-Wartungsknopf im
Admin-Bereich und eine Größenanzeige („Datenbank: 48 MB, ältestes Event: 14.08.2026").
Bewusst als P3: erst bauen, wenn reale Daten zeigen, dass es nötig ist.
**Aufwand:** M · **Prio:** P3

---

## Priorisierungs-Überblick

| Prio | Ideen |
|---|---|
| P1 | 1, 2, 3, 5, 6, 7, 9, 11, 13, 14, 18, 19, 20, 23, 24 |
| P2 | 4, 8, 10, 15, 16, 17, 21, 22 |
| P3 | 12, 25 |

**Empfohlene Baureihenfolge:** Zuerst Idee 23 (Event-Log) — sie ist die Grundlage,
auf der alles andere zu reinen „Views" wird. Danach Profil-Minimalpfad (1, 2, 3),
dann Fragen-Statistik + Fehlerhaft-Queue (11, 20) — die schützen sofort die
Fragen-Qualität — und parallel die sichtbaren Belohnungen (5, 9, 13, 14).
