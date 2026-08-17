# MONKEY MONEY — Ideen-Agent 7/20: Spiel-Modi, Match-Formate & Session-Design

Kontext: Jackbox/Buzz-artige Quiz-Show-Party-App. Handys = Controller, großer
Bildschirm optional, GM optional, 2–8 Spieler, Money-Thema. Explizite
User-Wünsche abgedeckt: Quick-Modus, Custom Games mit einstellbarer Länge,
Alkohol-Shot-Edition, Übungsmodus, Deutschland vs. global, Screen-los-Modus.

Legende: Aufwand **S** (klein, v. a. Config/UI), **M** (eigene Logik/Screens),
**L** (neues Subsystem). Prio **MUST / SHOULD / COULD**.

---

## (a) MODUS-PALETTE

### Idee 1 — Quick Cash (Quick-Modus, 10–15 min) — Aufwand: S · Prio: MUST
Ein-Tap-Start vom Homescreen: 3 Runden × 5 Fragen, 15 s pro Frage, gemischter
Kategorien-Pool, Joker aus, Rad nur einmal als Finale. Kein Setup-Screen —
Defaults sind fest, nur Spielerzahl wird erkannt. Ziel: "Wir warten auf die
Pizza"-Situation. Der Quick-Modus ist gleichzeitig das Onboarding: Wer ihn
einmal gespielt hat, kennt 80 % der Mechaniken. Ergebnis-Screen bietet direkt
"Nochmal" und "Jetzt Custom Game bauen" an (Upsell in die Tiefe).

### Idee 2 — Klassik-Show (30 min, Default-Modus) — Aufwand: M · Prio: MUST
Die "richtige" Show mit Dramaturgie: Intro-Jingle, 3 Akte (Aufwärmrunde →
Themenrunden mit Kategoriewahl → Finale mit Einsatz-Mechanik, bei der Spieler
ihr erspieltes Geld auf die letzte Frage wetten). Punkteanzeige als
Kontostand, Moderations-Texte (TTS oder Textbanner) zwischen den Runden.
Match-Länge über Rundenzahl skalierbar (siehe Settings-Matrix), aber die
3-Akt-Struktur bleibt erhalten, damit sich jedes Match wie eine Episode anfühlt.

### Idee 3 — Marathon / Börsentag (60–90 min) — Aufwand: M · Prio: SHOULD
Lange Session mit "Handelstag"-Rahmung: Vormittagshandel, Mittagspause
(automatischer Pausen-Screen, siehe Idee 18), Nachmittagshandel,
Börsenschluss-Finale. Zwischenstände werden als "Kurscharts" visualisiert
(Kontostand über Zeit). Enthält 1–2 eingestreute Bonus-Minispiele als
Tempo-Wechsel. Auto-Save nach jeder Runde ist hier Pflicht (siehe Idee 21),
weil lange Sessions eher unterbrochen werden.

### Idee 4 — Turnier-Bracket über mehrere Matches — Aufwand: L · Prio: SHOULD
Bracket-Modus für 4–8 Spieler: App generiert KO-Baum oder Gruppenphase + Finale
aus Quick-Matches (je 10 min). Wer ausscheidet, wird automatisch
Zuschauer/Saboteur (darf pro Match einmal eine Störkarte gegen einen
Finalisten spielen — hält Ausgeschiedene bei Laune). Turnier-Stand wird
persistent gespeichert (Save/Load, Idee 21), sodass ein Turnier über mehrere
Abende laufen kann ("Liga-Abend"). Bracket-Anzeige auf dem großen Bildschirm
zwischen den Matches, auf Handys als Tab.

### Idee 5 — Alkohol-Edition "Zinsen & Shots" (18+, fair & optional) — Aufwand: M · Prio: SHOULD
Separater Schalter im Custom Game, mit Alters-Hinweis und ausdrücklichem
Opt-in PRO SPIELER (wer nüchtern bleibt, bekommt Ersatzstrafen wie
"Grimasse in die Kamera" oder Punktabzug — niemand wird gezwungen).
Fairness-Regeln: Shots werden nie an den Letztplatzierten allein verteilt
(kein Loser-Bashing-Spiral), sondern über Ereignisse: "Alle, die Frage 3
falsch hatten", "Der Führende gibt einen aus", Rad-Feld "Lokalrunde".
Hartes Limit: max. X Trink-Events pro Match (einstellbar, Default konservativ).
Hydrations-Reminder: Nach jedem 2. Trink-Event blendet die App einen
Wasser-Break-Screen ein ("Wasserstand auffüllen — Kurs stabilisieren"), der
nicht wegklickbar ist (10 s). Zusätzlich "Beifahrer-Modus" pro Person
(nimmt an Trink-Events nie teil, App merkt es sich für die Session).

### Idee 6 — Familien-Modus (Kids- + Eltern-Fragen gemischt) — Aufwand: M · Prio: SHOULD
Beim Setup wird pro Spieler ein Profil "Kind" oder "Erwachsen" gesetzt. Die
App serviert in derselben Runde jedem Spieler eine Frage aus seinem Pool zur
gleichen Kategorie (z. B. Kategorie "Tiere": Kind bekommt "Welches Tier sagt
Muh?", Erwachsener "Wie viele Mägen hat eine Kuh?"). Punkte sind dadurch
vergleichbar, alle spielen "dieselbe" Runde. Optional Handicap-Multiplikator
statt getrennter Pools. Bestrafungen und Alkohol-Inhalte sind in diesem Modus
hart deaktiviert, Timer defaults länger.

### Idee 7 — Late-Night-Edition — Aufwand: M · Prio: COULD
Freigeschaltet ab einstellbarer Uhrzeit oder manuell: dunkles Neon-Casino-Theme,
gedämpfte Sounds (Nachbarn!), frecherer Fragen-Pool (peinliche Schätzfragen,
"Wer im Raum würde am ehesten…"-Voting-Runden), höhere Einsätze, ein
exklusives Rad-Feld "Alles auf Rot" (Kontostand verdoppeln oder halbieren).
Kombinierbar mit Alkohol-Edition, aber unabhängig davon.

### Idee 8 — Solo-Übungsmodus "Trainingslager" mit Statistik — Aufwand: M · Prio: SHOULD
Einzelspieler-Modus komplett auf dem Handy (kein Bildschirm, kein Raum):
endlose Fragen-Streaks, Kategorie frei wählbar, drei Trainingsarten:
(1) Freies Training, (2) Schwächen-Training (App serviert bevorzugt Kategorien
mit niedriger persönlicher Trefferquote), (3) Tages-Challenge (10 Fragen,
gleich für alle Spieler weltweit/DE, mit lokaler Bestenliste unter Freunden).
Statistik-Dashboard: Trefferquote pro Kategorie, Reaktionszeit-Trend,
Streak-Rekord. Fortschritt zahlt in dasselbe Profil ein wie Partys (aber
KEIN Geld/Shop-Währung farmen — Training gibt nur XP/Kosmetik, sonst wird's
grindig und verzerrt die Party-Ökonomie).

### Idee 9 — Screen-los-Modus "GM-Show" (GM-iPad steuert alles) — Aufwand: L · Prio: MUST
Detail-Konzept für den Modus ohne großen Bildschirm:
- **Rollenverteilung:** Das GM-Gerät (iPad/Handy) ist Regiepult UND Bühne. Es
  zeigt dem GM Frage + richtige Antwort + Regieanweisungen ("Baue Spannung
  auf, dann tippe 'Auflösen'"). Der GM liest die Frage laut vor — er ist der
  Show-Host, die App souffliert.
- **Spieler-Handys übernehmen die Bildschirm-Rolle verteilt:** Antwortoptionen
  erscheinen NACH dem Vorlesen auf allen Handys (damit niemand vorliest-schneller-
  liest). Punktestände, Rad-Animation und Zwischenstände laufen auf ALLEN
  Handys synchron als Vollbild-Moment ("Alle Handys hoch!").
- **Buzz-Formate ohne Bildschirm:** Buzzern funktioniert sogar besser — GM
  liest vor, Handys werden zum großen roten Buzzer (ganzer Screen), das
  schnellste Handy vibriert + leuchtet auf und der Spieler antwortet MÜNDLICH
  dem GM, der per Richtig/Falsch-Tap wertet. Das ist die klassische
  Pub-Quiz-Dynamik und braucht null Bildschirm.
- **Audio-Ersatz:** Jingles/Timer-Sounds kommen vom GM-Gerät (lauteste Box im
  Raum, ggf. Bluetooth-Speaker).
- **GM-los + Screen-los Fallback:** Ohne GM übernimmt ein rotierender Spieler
  pro Runde die Vorlese-Rolle (sein Handy zeigt die Frage, er spielt die Runde
  nicht mit, bekommt Durchschnittspunkte — "Praktikant an der Börse").

### Idee 10 — "Feierabend-Häppchen" (Micro-Modus, 3–5 min) — Aufwand: S · Prio: COULD
Noch unter Quick: exakt 1 Runde, 5 Buzzer-Fragen, Sieger bekommt einen
kosmetischen Tages-Badge. Gedacht für "einer will nur kurz zeigen wie's geht"
oder als Entscheider ("Wer räumt die Spülmaschine aus?"— App bietet dafür
sogar einen eigenen Framing-Text an: "Worum spielt ihr?" als Freitextfeld,
das im Siegerscreen wieder auftaucht).

### Idee 11 — Koop-Modus "Gemeinschaftskonto" — Aufwand: M · Prio: COULD
Alle Spieler zahlen auf ein gemeinsames Konto ein und spielen gegen die
"Bank" (Punkteziel je nach Spielerzahl/Schwierigkeit). Uneinigkeit ist die
Mechanik: Bei Mehrheitsfragen zählt die Mehrheits-Antwort, bei Buzzer-Fragen
haftet das Team für Fehlbuzzer. Guter Modus für gemischte Gruppen, in denen
kompetitives Spielen Stress erzeugt (Familienfeiern!). Endscreen zeigt
"Team-Rendite" statt Einzelplatzierung.

---

## (b) MATCH-SETTINGS-MATRIX (Custom Games)

### Idee 12 — Settings-Matrix als "Vertragsverhandlung" — Aufwand: M · Prio: MUST
Der Custom-Game-Screen ist thematisch ein Kreditvertrag/Term Sheet, den der
Host "unterschreibt". Die konkreten Regler:

| Setting | Optionen | Default (Klassik) |
|---|---|---|
| Rundenzahl | 2–10 (mit Zeitschätzung live: "≈ 34 min") | 5 |
| Zeit pro Frage | 10 / 15 / 20 / 30 s / Gemütlich (60 s) | 20 s |
| Kategorien-Pool | Multi-Select + "Überraschung" (App wählt) | Alle |
| Schwierigkeits-Kurve | Flach / Ansteigend / ULTRAHARD-Finale / Chaos (zufällig) | Ansteigend |
| Joker | An / Aus / Nur 1 pro Match | An |
| Glücksrad | Jede Runde / Nur Finale / Aus | Jede Runde |
| Bestrafungen | Aus / Mild / Party / Eigene Liste | Mild |
| All-time-Shop-Items | Erlaubt / Nur Kosmetik / Gesperrt ("Fair Play") | Nur Kosmetik |
| Regionsfokus | DE / DACH / Global / Mix (Regler in %) | Mix 50/50 |
| 18+-Inhalte | Aus / Alkohol-Events / Late-Night-Fragen | Aus |

Jede Änderung aktualisiert die Match-Dauer-Schätzung live — das erfüllt
"anpassbare Länge" ohne separaten Längen-Regler.

### Idee 13 — Schwierigkeits-Kurven als wählbare "Risikoprofile" — Aufwand: M · Prio: SHOULD
Vier Kurven, thematisch als Anlage-Profile: **Sparbuch** (konstant leicht),
**Aktienfonds** (leicht → mittel → schwer, Default), **Krypto** (zufällige
Ausschläge, jede Frage kann alles sein), **ULTRAHARD-Endgame** (Runden 1–n
normal, letzte Runde nur Expertenfragen mit 3-fach-Punkten — "der Markt
crasht, wer überlebt?"). Wichtig fürs Balancing: Punkt-Multiplikatoren an
Schwierigkeit koppeln, damit ein schweres Finale Aufholjagden ermöglicht
(Comeback-Design), aber Führung nicht wertlos macht (Cap: Finale max. ~40 %
der Gesamtpunkte).

### Idee 14 — DE/Global-Regler mit Pool-Transparenz — Aufwand: M · Prio: SHOULD
Kein binärer Schalter, sondern Prozent-Regler ("Wie deutsch soll's werden?"):
0 % = nur globale Fragen (für gemischte Runden mit Nicht-Deutschen, dann auch
Sprach-Option EN), 100 % = GEZ, Pfand, Autobahn, Schlager. Die App zeigt vor
Match-Start ehrlich an, wie groß der resultierende Fragen-Pool ist und warnt,
wenn Kategorie-Auswahl + Regionsfilter den Pool zu klein machen
("Wiederholungsgefahr: Pool < 3× Fragenbedarf").

### Idee 15 — Presets & Community-Setups mit Share-Code — Aufwand: M · Prio: SHOULD
Jede Settings-Kombination lässt sich als benanntes Preset speichern
("WG-Dienstag", "Omas Geburtstag") und als 6-stelliger Code / QR teilen.
Mitgelieferte offizielle Presets = die Modus-Palette aus Teil (a) — technisch
sind Quick, Klassik, Familien etc. intern nur Presets über derselben Engine,
was den Implementierungsaufwand der gesamten Palette drastisch senkt.
Zuletzt gespielte Setups erscheinen auf dem Homescreen ("Wieder so wie
letzten Freitag?").

### Idee 16 — Haus-Regeln-Slot: eigene Bestrafungs-/Aufgabenliste — Aufwand: S · Prio: COULD
Im Settings-Bereich "Bestrafungen: Eigene Liste" kann der Host bis zu 10
Freitext-Aufgaben hinterlegen ("Handstand", "Nächste Runde nur auf Englisch
antworten erklären"), die das Rad/die Events statt der eingebauten nutzen.
Wird pro Gruppe gespeichert. Minimaler Aufwand, riesiger
Personalisierungs-Effekt — Gruppen entwickeln eigene Rituale und kommen dafür
zurück.

---

## (c) SESSION-KOMFORT

### Idee 17 — Spät-Joiner: Zuschauer → Einstieg zur nächsten Runde — Aufwand: M · Prio: MUST
Wer während eines Matches den Raum-Code eingibt, landet sofort im
Zuschauer-Modus: sieht Fragen live mit, darf mit-tippen (Schattenpunkte,
zählen nicht), kann Emoji-Reaktionen senden. Zu Beginn der nächsten Runde
fragt die App den Host: "Kevin einsteigen lassen?" Einstieg mit dem
MEDIAN-Kontostand aller Spieler (nicht 0 — sonst chancenlos; nicht
Durchschnitt — sonst verzerrt durch Führende). Im Endscreen bekommt der
Spät-Joiner ein Sternchen "eingestiegen Runde 3". Max. Spielerzahl 8 bleibt
hartes Limit, danach nur Zuschauer.

### Idee 18 — Rage-Quit- & Verbindungs-Handling ("Der Markt vergisst nicht") — Aufwand: M · Prio: MUST
Drei Eskalationsstufen: (1) Verbindungsabbruch < 60 s: Bot antwortet nicht,
Spieler verliert nichts, Platz bleibt reserviert, Rejoin per Code nahtlos mit
vollem Kontostand. (2) Länger weg: Spieler wird "eingefroren" (nimmt nicht
teil, sammelt nichts), Match läuft für die anderen ungebremst weiter — nie
alle blockieren wegen einem. (3) Aktives Verlassen: Kontostand wandert als
"Insolvenzmasse" in den Pot der nächsten Rad-Runde (macht den Quit für die
anderen zum Ereignis statt zum Ärgernis). Host kann Ex-Spieler
zurückholen (Stufe 3 → Rejoin mit halber Insolvenzmasse zurück).

### Idee 19 — Pausen-Screen mit Mini-Beschäftigung — Aufwand: M · Prio: SHOULD
Host (oder GM) kann jederzeit pausieren: großer Bildschirm zeigt
"Handelspause" mit Zwischenstand-Chart. Auf den Handys läuft währenddessen
optional ein Ein-Personen-Minigame ohne Punkte-Relevanz: "Geldscheine
stapeln" (Timing-Tapper) mit Session-Highscore, der beim Fortsetzen kurz
eingeblendet wird ("Lisa hat in der Pause 34 Scheine gestapelt"). Zusätzlich
zeigt der Pausen-Screen praktische Infos: wer am Zug wäre, Restdauer-Schätzung,
und in der Alkohol-Edition den Hydrations-Zähler.

### Idee 20 — Ein-Tap-Rematch mit Rache-Twist — Aufwand: S · Prio: MUST
Endscreen hat genau einen großen Button: "REVANCHE" (gleiche Spieler, gleiche
Settings, kein neuer Raum-Code, keine Lobby — 3-2-1 und es läuft). Zwei kleine
Nebenoptionen: "Settings anpassen" (öffnet Custom-Screen mit aktuellem Setup
vorbefüllt) und "Rache-Modus": der Letztplatzierte darf für das Rematch EINE
Einstellung ändern (z. B. Kategorie raus, die er hasst) — sichtbar für alle
angekündigt. Hält Verlierer im Spiel und erzeugt Gesprächsstoff.

### Idee 21 — Save/Load: klarer Scope, Auto-Save, ein Slot pro Kontext — Aufwand: L · Prio: SHOULD
Was genau gespeichert wird (und was nicht):
- **Laufendes Match:** Auto-Save nach jeder abgeschlossenen Runde (nicht
  mitten in einer Frage — Frage in Bearbeitung wird beim Laden neu gestellt,
  mit frischer Frage gegen Schummeln). Gespeichert: Spielerliste + Kontostände +
  Rundenindex + Settings + bereits verwendete Fragen-IDs (keine Wiederholungen)
  + Joker-/Item-Stände. Ein Slot pro Raum, 7 Tage Haltbarkeit, danach Verfall
  mit augenzwinkernder Notification ("Dein Festgeld ist verfallen").
- **Turnier-Stand:** Eigener persistenter Speicher (Bracket, erledigte
  Matches, Saboteur-Karten), unbegrenzt haltbar, mehrere benannte Turniere
  parallel möglich ("Bürо-Liga", "WG-Cup").
- **NICHT gespeichert:** Zuschauer, laufende Frage, Pausen-Minigame-Stände.
- Beim App-Start mit vorhandenem Save: "Weiterspielen?"-Karte ganz oben, mit
  Anzeige, welche Spieler damals dabei waren (Wiedererkennungs-Avatare).

### Idee 22 — Session-Abspann & "Kontoauszug" — Aufwand: S · Prio: SHOULD
Nach dem letzten Match des Abends (App erkennt: kein Rematch nach 2 min /
Host tippt "Feierabend") erzeugt die App einen Abend-Kontoauszug: Awards
("Schnellster Buzzer", "Mutigster Wetteinsatz", "Pechvogel des Abends"),
Gesamtbilanz über alle Matches der Session, als Bild teilbar (WhatsApp-Format
9:16). Kostet wenig, ist aber der Moment, der die Gruppe zum nächsten
Spieleabend zurückbringt — der Kontoauszug endet mit "Nächste Sitzung der
Zentralbank: ?" und einem Kalender-Share-Link.

### Idee 23 — Barrierefreiheit als Session-Option, nicht als Modus — Aufwand: M · Prio: COULD
Pro Spieler (nicht pro Match) zuschaltbar: längere Antwortzeit (+50 %, für
diesen Spieler unsichtbar für andere gepuffert über eine "Bedenkzeit-Bank"),
Vorlese-Funktion der Fragen aufs eigene Handy (Kopfhörer), hoher Kontrast,
Farbenblind-sichere Antwort-Farben. Wichtig: als individuelle
Spieler-Einstellung statt globalem "Senioren-Modus" — niemand wird vor der
Gruppe markiert, die App gleicht still aus.

---

## Querverbindungen
- Ideen 1, 2, 3, 6, 7, 10 sind intern Presets der Engine aus Idee 15 →
  zuerst Settings-Matrix (12) + Preset-System (15) bauen, dann ist die halbe
  Modus-Palette fast gratis.
- Screen-los-Modus (9) und GM-Rolle bedingen einander: das GM-Regiepult sollte
  von Anfang an als eigene Client-Rolle (neben Spieler/Zuschauer/Bildschirm)
  in der Netzwerk-Architektur angelegt sein.
- Alkohol-Edition (5) hängt an Bestrafungs-Setting (12) und Pausen-Screen (19,
  Hydrations-Zähler).
