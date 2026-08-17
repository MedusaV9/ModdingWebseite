# MONKEY MONEY — Ideen-Agent 13/20: Frage-TYPEN & Medien-Fragen

Kontext-Annahmen (aus Briefing): Party-Quiz im Jackbox/Buzz-Stil. Handys hochkant
= Controller, gemeinsamer Bildschirm = Bühne. Währung „Money" (Punkte = Geld).
Jede Frage kann 2–3 gestufte Tipps haben. Medien nur mit sauberer Lizenz
(generiert, CC/Public Domain, Blender Open Movies). Keine Code-Änderungen —
reine Ideation.

Legende: **Aufwand** S (klein, <1 Baustein), M (mittel, eigener Screen/Widget),
L (groß, neue Pipeline/Asset-Produktion). **Prio** = Empfehlung für
Launch-Reihenfolge (P1 = Kern-Launch, P2 = bald danach, P3 = nice-to-have).

---

## Teil A — Frage-Typen-Katalog (Ideen 1–15)

Jeder Typ mit: Handy-Input · Bildschirm-Darstellung · Scoring ·
Tipp-Mechanik (wie die 2–3 gestuften Tipps konkret wirken).

### Idee 1 — Klassische 4er-Choice (das Brot-und-Butter-Format)
- **Handy-Input:** 4 große vertikal gestapelte Buttons (Daumen-Reichweite,
  hochkant-optimiert). Antwort wählbar bis Timer-Ende, letzte Wahl zählt
  (Umentscheiden erlaubt, kostet nichts — Party-freundlich).
- **Bildschirm:** Frage groß oben, 4 Antworten als Karten mit Symbol+Farbe
  (Kreis/Quadrat/Dreieck/Stern — nicht nur Farbe, siehe Fairness). Live-Anzeige
  „X von Y haben geantwortet", KEINE Verteilung vor Auflösung.
- **Scoring:** Basis 100 Money + Speed-Bonus (linear abfallend bis 0 über die
  Timer-Dauer). Falsch = 0 (kein Abzug im Standard-Modus, hält Stimmung hoch).
- **Tipp-Mechanik:** Stufe 1 = thematischer Hinweis-Satz (−15 % vom möglichen
  Gewinn), Stufe 2 = eine falsche Antwort verschwindet (−35 %), Stufe 3 =
  50/50, nur zwei Antworten bleiben (−60 %). Tipps wirken NUR auf dem Handy
  des Käufers (Bildschirm bleibt für alle gleich).
- **Aufwand:** S · **Prio:** P1 (Pflicht-Fundament, alle anderen Typen erben
  Timer/Scoring/Tipp-Gerüst hiervon).

### Idee 2 — Wahr/Falsch-Blitzrunde (Tempo-Wechsel)
- **Handy-Input:** Ganzer Screen zweigeteilt: oben GRÜN „WAHR" (Haken-Symbol),
  unten ROT „FALSCH" (Kreuz-Symbol). Ein Tap, sofort verbindlich — 5–8
  Aussagen in Serie à 6 Sekunden.
- **Bildschirm:** Eine Aussage groß, Countdown-Ring, dann sofort Auflösung
  (2 s) und nächste Aussage. Musik zieht Tempo an.
- **Scoring:** 40 Money pro Treffer, Streak-Bonus: ab 3 richtigen in Folge
  +10 pro weiterem Treffer. Falsch = Streak reißt (kein Abzug).
- **Tipp-Mechanik:** Keine Einzel-Tipps (zu schnell). Stattdessen EIN
  „Joker" vor der Runde kaufbar (50 Money): eine Aussage der Serie wird auf
  dem Handy mit „Bauchgefühl der Mehrheit" (Live-Tendenz der anderen)
  angezeigt. Bewusst nur 1 Stufe — Blitz bleibt Blitz.
- **Aufwand:** S · **Prio:** P1 (billig, bester Rhythmus-Brecher zwischen
  schweren Fragen).

### Idee 3 — Schätzfrage mit Slider (Scoring nach Nähe)
- **Handy-Input:** Vertikaler Slider (hochkant!) mit grober Skala + darunter
  Feinjustierung über +/−-Buttons oder Zahlen-Direkteingabe. Haptik-Tick
  pro Rasterschritt. „Einloggen"-Button macht verbindlich (Speed zählt hier
  NICHT — Nachdenken soll belohnt werden).
- **Bildschirm:** Frage + leere Skala. Bei Auflösung: alle Spieler-Marker
  fliegen auf die Skala, dann fährt der Wahrheits-Pfeil ein — Reveal-Drama
  wie bei „Der Preis ist heiß".
- **Scoring:** Nähe-basiert: 150 Money × (1 − relative Abweichung), gedeckelt
  bei 0. Zusätzlich +50 Bonus für den absolut Nächsten („Schätz-König" mit
  Kronen-Icon). Bei Jahreszahlen: ±0 Jahre = voll, linear bis Toleranzfenster
  (siehe Fairness, Idee 24).
- **Tipp-Mechanik:** Stufe 1 = Größenordnung („zwischen 1.000 und 100.000",
  −20 %), Stufe 2 = Intervall halbiert sich auf dem Handy-Slider (der
  wählbare Bereich wird eingeschränkt! −40 %), Stufe 3 = ±10 %-Korridor
  wird auf dem Handy farblich markiert (−65 %).
- **Aufwand:** M · **Prio:** P1 (kein Faktenwissen nötig → jeder kann
  mitspielen, ideal für gemischte Gruppen).

### Idee 4 — Sortier-Frage (4 Dinge ordnen)
- **Handy-Input:** 4 Karten untereinander, Drag-and-Drop hochkant (Daumen
  zieht Karten hoch/runter) — alternativ Tap-Reihenfolge (1., 2., 3., 4.
  antippen) als Barrierefrei-Modus. „Fertig"-Button loggt ein.
- **Bildschirm:** Aufgabe („Ordne nach Erscheinungsjahr, älteste zuerst") +
  die 4 Elemente ungeordnet. Auflösung: Karten sortieren sich animiert, pro
  Spieler wird gezeigt, wie viele Positionen exakt saßen.
- **Scoring:** 2 Varianten mischbar: (a) 30 Money pro exakt richtiger
  Position, +30 Bonus für perfekte Reihenfolge; (b) „Paar-Metrik": Money pro
  korrekt geordnetem Paar (6 Paare bei 4 Items) — verzeiht einen einzelnen
  Ausrutscher fairer. Empfehlung: (b) als Default.
- **Tipp-Mechanik:** Stufe 1 = ein Element wird an seine korrekte Position
  gepinnt und gesperrt (−25 %), Stufe 2 = zweites Element gepinnt (−45 %),
  Stufe 3 gibt es nicht (2 Pins bei 4 Items reichen fast zur Lösung).
- **Aufwand:** M · **Prio:** P2.

### Idee 5 — Lückentext („Vervollständige den Satz/das Zitat")
- **Handy-Input:** Zwei Modi: (a) Freitext-Feld mit Handy-Tastatur (fuzzy
  Matching: Tippfehler-Toleranz per Levenshtein, Groß/Klein egal), (b)
  „Silben-Baukasten": 8 Wort-/Silben-Kacheln, daraus die Lücke zusammensetzen
  — schneller, moderationsfrei, empfohlen als Default.
- **Bildschirm:** Satz mit auffällig pulsierender Lücke („Der ___ ist des
  Müllers Lust"). Bei Freitext: lustigste Falschantworten anonym einblenden
  (Jackbox-Moment!).
- **Scoring:** 120 Money bei korrekt; Freitext-Modus +20 Extra (höheres
  Risiko). Speed-Bonus klein halten (Tipp-Geschwindigkeit ≠ Wissen).
- **Tipp-Mechanik:** Stufe 1 = Anfangsbuchstabe (−20 %), Stufe 2 =
  Wortlänge als Unterstriche + Kategorie (−40 %), Stufe 3 = Anagramm der
  Lösung (−60 %, macht daraus ein Mini-Puzzle statt Geschenk).
- **Aufwand:** M (Fuzzy-Matching) · **Prio:** P2.

### Idee 6 — „Welches Bild passt?" (Bild-Antworten statt Text)
- **Handy-Input:** 4 Bild-Kacheln im 1×4-Stapel (hochkant) — Tap wählt,
  Lange-drücken zoomt das Bild bildschirmfüllend auf dem Handy (Details!).
- **Bildschirm:** Frage als Text („Welches dieser Tiere ist KEIN Säugetier?"),
  die 4 Bilder groß im Raster mit Symbol-Markern (A♠ B♥ C♦ D♣).
- **Scoring:** wie 4er-Choice (100 + Speed).
- **Tipp-Mechanik:** wie 4er-Choice; Stufe 2 graut ein falsches Bild aus.
- **Medien:** Generierte Bilder oder Wikimedia Commons (siehe Teil B).
- **Aufwand:** S (erbt Choice-Logik) · **Prio:** P1 (macht das Spiel sofort
  „reicher" fürs Auge, minimaler Mehraufwand).

### Idee 7 — Pixel-/Zoom-Enthüllung „Was ist das?" (das Risiko-Signature-Format)
- **Handy-Input:** Großer BUZZ-Button (ganze untere Handy-Hälfte). Wer
  buzzert, friert die Enthüllung für sich ein und bekommt 4 Antwort-Optionen
  (oder Silben-Baukasten in der Hard-Variante). Falsch geraten = für diese
  Frage gesperrt, Enthüllung läuft für den Rest weiter.
- **Bildschirm:** Bild startet extrem verpixelt (z. B. 8×8 Mosaik) und wird
  in 8–10 Stufen über ~20 s scharf. Alternativ-Modi mit derselben Mechanik:
  Extrem-Zoom-out (Makro → Totale), Wischkegel (Bild wird sektorweise
  freigelegt), Silhouette → Farbe. Money-Zähler tickt sichtbar runter
  (Countdown-Preisgeld: 250 → 20), das erzeugt den Risiko-Druck.
- **Scoring:** Wer früh buzzert und richtig liegt, kassiert den aktuellen
  Zählerstand. Falsch-Buzz = −30 Money Strafe (einziges Format mit Abzug —
  hier ist das Risiko das Spielgefühl!). Mehrere dürfen nacheinander buzzern.
- **Tipp-Mechanik:** Tipps sind hier ZEIT statt Text: Stufe 1 =
  Kategorie-Einblendung nur auf dem eigenen Handy („Es ist ein Küchengerät",
  −20 % vom Zählerstand bei Gewinn), Stufe 2 = das eigene Handy zeigt die
  NÄCHSTE Schärfestufe 2 s früher als der Bildschirm (−40 %) — sehr
  kitzelnd, weil Informationsvorsprung. Keine Stufe 3.
- **Aufwand:** M–L (Reveal-Renderer + Buzz-Arbitrierung mit
  Latenz-Fairness) · **Prio:** P1 (vom User explizit gewünscht;
  DAS Alleinstellungs-Format der Show).

### Idee 8 — Audio-Frage (Sound raten)
- **Handy-Input:** 4er-Choice-Buttons; Zusatz-Button „Nochmal hören"
  (max. 1×, kostet 5 s Speed-Bonus).
- **Bildschirm:** Visualizer-Waveform/pulsierendes Icon statt Bild (nichts
  verraten!). Sound läuft über den Bildschirm-Lautsprecher — Handys bleiben
  stumm (kein Chaos-Echo im Raum).
- **Sound-Kategorien (alle lizenzsicher machbar):** Tiergeräusche,
  Alltagsgeräusche rückwärts, Instrumente, Städte-Soundscapes, „Welches
  Gerät ist das?", verlangsamter/beschleunigter Klassiker (gemeinfreie
  Musik!).
- **Scoring:** wie 4er-Choice; „Nochmal hören" wie oben.
- **Tipp-Mechanik:** Stufe 1 = Kategorie (−15 %), Stufe 2 = Sound wird in
  Normal-Geschwindigkeit/vorwärts abgespielt, falls verfremdet (−35 %),
  Stufe 3 = 50/50 (−60 %).
- **Aufwand:** M (Audio-Pipeline + CC-Kuration) · **Prio:** P2.

### Idee 9 — Emoji-Rätsel („Film in 5 Emojis")
- **Handy-Input:** 4er-Choice (Filmtitel) oder Freitext in der Hard-Variante.
  Party-Twist als eigener Runden-Typ: Spieler BAUEN selbst Emoji-Rätsel für
  die anderen (Emoji-Picker auf dem Handy, 3–7 Emojis) — nutzergenerierter
  Content, null Lizenzkosten, maximaler Lacher.
- **Bildschirm:** Die Emojis erscheinen einzeln nacheinander (1/s) — wer
  nach 2 Emojis loggt, kriegt mehr Money als nach 5 (gestaffelter
  Zählerstand wie bei Idee 7, aber ohne Buzz-Sperre).
- **Scoring:** Zählerstand beim Einloggen (180 → 60), falsch = 0.
- **Tipp-Mechanik:** Stufe 1 = Genre + Jahrzehnt (−20 %), Stufe 2 = ein
  weiteres „Bonus-Emoji" nur auf dem eigenen Handy (−40 %), Stufe 3 =
  Anfangsbuchstaben der Titel-Wörter (−60 %).
- **Rechtlich:** Titel-Nennung + Emojis = unkritisch (keine Inhalte
  kopiert). Perfektes Film-Format OHNE Clip-Problem.
- **Aufwand:** S–M · **Prio:** P1 (Film-Content ohne Rechte-Risiko, hoher
  Party-Faktor).

### Idee 10 — Timeline („Ordne das Ereignis ein")
- **Handy-Input:** Horizontale Zeitleiste mit 3–5 bereits platzierten
  Anker-Ereignissen; das neue Ereignis per Drag in eine der Lücken ziehen
  (nur Lücken-Wahl, keine Jahres-Präzision → niedrige Frustration).
- **Bildschirm:** Zeitstrahl mit Ankern, das einzuordnende Ereignis schwebt
  darüber. Auflösung: Ereignis fliegt an die richtige Stelle, Marker der
  Spieler leuchten grün/rot (plus Form-Symbole).
- **Scoring:** Richtige Lücke = 100 Money; direkte Nachbar-Lücke = 40
  (Trostpreis hält Laune). Kampagnen-Variante: Timeline wächst über mehrere
  Fragen — jedes gelöste Ereignis wird neuer Anker (Schwierigkeit steigt
  organisch).
- **Tipp-Mechanik:** Stufe 1 = Jahrhundert/Jahrzehnt (−20 %), Stufe 2 =
  zwei Lücken werden ausgegraut (−45 %).
- **Aufwand:** M · **Prio:** P2.

### Idee 11 — Karten-Frage („Wo liegt X?" — Tap auf Karte)
- **Handy-Input:** Zoombare stumme Karte auf dem Handy (Pinch+Tap setzt
  Pin, Pin verschiebbar bis „Einloggen"). Hochkant: Karte oben 70 %,
  Bestätigen-Leiste unten.
- **Bildschirm:** Dieselbe stumme Karte groß; bei Auflösung fliegen alle
  Pins ein, dann Zielkreis-Animation um den wahren Ort mit
  Entfernungs-Beschriftung pro Spieler.
- **Scoring:** Distanz-basiert wie Schätzfrage: voll bei < 50 km, linear
  auf 0 bis Toleranz-Radius (kontinent-abhängig, siehe Fairness). Bonus für
  den Nächsten.
- **Kartenmaterial rechtlich:** Naturerde-/OpenStreetMap-Daten (ODbL,
  Attribution in Credits) oder eigene stilisierte Vektor-Karten aus
  Public-Domain-Grundlagen (Natural Earth ist public domain — sauberste
  Wahl, keine Attributions-Pflicht).
- **Tipp-Mechanik:** Stufe 1 = Kontinent/Land wird hervorgehoben (−25 %),
  Stufe 2 = 500-km-Kreis erscheint auf dem eigenen Handy (−50 %).
- **Aufwand:** L (Karten-Widget) · **Prio:** P2–P3 (stark, aber teuerstes
  Einzel-Format).

### Idee 12 — Mehrfach-Antwort („2 von 6 sind richtig")
- **Handy-Input:** 6 Toggle-Kacheln, Zähler zeigt „2 auswählen";
  Einloggen erst möglich, wenn exakt 2 markiert sind.
- **Bildschirm:** Frage + 6 Optionen im 2×3-Raster mit Form-Symbolen.
  Auflösung deckt beide richtigen nacheinander auf (doppelter
  Spannungs-Beat).
- **Scoring:** Beide richtig = 140 Money, genau eine richtig = 40, keine =
  0. (Teilpunkte sind hier wichtig, sonst fühlt sich 1 Treffer wie
  Niederlage an.)
- **Tipp-Mechanik:** Stufe 1 = eine falsche Option verschwindet (−20 %),
  Stufe 2 = noch eine (−40 %), Stufe 3 = eine RICHTIGE wird markiert, die
  zweite muss selbst gefunden werden (−65 %).
- **Aufwand:** S · **Prio:** P2.

### Idee 13 — Ketten-Frage („Die Antwort steckt in der nächsten Frage")
- **Handy-Input:** normale 4er-Choice, aber 3–5 Fragen bilden eine Kette:
  Die richtige Antwort von Frage 1 ist Bestandteil von Frage 2 („Der Fluss
  aus Frage 1 fließt durch welche Hauptstadt?").
- **Bildschirm:** Ketten-Visual: gelöste Glieder hängen sichtbar oben als
  „Kette", die wächst. Wer eine Frage falsch hatte, sieht die korrekte
  Antwort trotzdem (sonst ist er für den Rest der Kette verloren —
  wichtig!).
- **Scoring:** Pro Glied 80 Money, Ketten-Bonus ×1,5 auf die Gesamtsumme,
  wenn ALLE Glieder richtig — Streak-Nervenkitzel.
- **Tipp-Mechanik:** Standard-Choice-Tipps; Zusatz: Stufe 1 kann die
  Antwort des VORHERIGEN Glieds nochmal einblenden (für Unaufmerksame,
  −10 %).
- **Aufwand:** S (Content-Logik, kaum UI) · **Prio:** P2.

### Idee 14 — „Reihum-Duell": Pixel-Bild + Bieterrunde (Kombi-Format)
- **Idee:** Vor der Pixel-Enthüllung BIETEN die Spieler verdeckt auf dem
  Handy, bei welcher Schärfe-Stufe (1–10) sie die Antwort wissen werden.
  Der niedrigste Bieter bekommt exklusiv den Buzz bei seiner Stufe —
  schafft er es, kassiert er groß (Stufe × 40 Money invers), scheitert er,
  geht das Bild für alle anderen als normale Buzzer-Frage weiter.
- **Warum:** „Ich erkenne das Ding bei Stufe 3!" ist purer
  Casino-Angeber-Spaß — Buzz!-Nostalgie pur.
- **Aufwand:** M (auf Idee 7 aufbauend) · **Prio:** P3 (erst wenn Idee 7
  steht).

### Idee 15 — „Alle gegen den Kandidaten" (Rollen-Wechsel-Format)
- **Idee:** Eine Frage pro Runde ist eine „Heiße-Stuhl"-Frage: Der aktuell
  FÜHRENDE muss allein antworten (sein Handy vibriert, Spotlight auf dem
  Bildschirm), alle anderen wetten parallel auf „schafft er's?"
  (Ja/Nein-Wette mit kleinem Einsatz). Nivelliert Führungen, alle sind
  beteiligt, niemand wartet.
- **Scoring:** Kandidat: 150 oder −50; Wettende: Einsatz verdoppelt oder
  weg.
- **Aufwand:** M · **Prio:** P3.

---

## Teil B — Medien-Strategie (rechtlich sauber) (Ideen 16–21)

### Idee 16 — Generierte Bilder als Haupt-Quelle fürs Pixel-Raten
- **Was:** Objekte, Tiere, Orte, Gerichte, Fahrzeuge als KI-generierte
  Bilder — ideal fürs Pixel-Format, weil (a) keinerlei Fremd-Rechte,
  (b) Motiv exakt steuerbar (ein Objekt, zentriert, neutraler Hintergrund
  = fair verpixelbar), (c) beliebig nachproduzierbar.
- **Stil-Konsistenz:** EIN festgelegter Haus-Stil (z. B. „sauberes
  halb-realistisches Studio-Foto, weicher Verlaufs-Hintergrund,
  Objekt zentriert, kein Text im Bild") als wiederverwendbarer
  Prompt-Baustein; Stil-Referenzbild pro Kategorie. Wichtig: KEIN Stil-Mix
  innerhalb einer Runde (sonst raten Spieler den Stil statt das Motiv).
- **Qualitäts-Gate:** Jedes Bild vor Aufnahme in den Fragen-Pool von einem
  Menschen prüfen: Ist das Motiv eindeutig DAS, was die Antwort behauptet?
  (KI-Halluzinations-Schutz — falsche Anatomie bei Tieren etc.)
- **Grenze:** KEINE generierten Bilder realer Personen (Persönlichkeits-
  rechte!) und keine „im Stil von <lebender Künstler>"-Prompts.
- **Aufwand:** M (Pipeline + Review) · **Prio:** P1.

### Idee 17 — Wikimedia Commons für Personen, Orte, Kunst
- **Was:** Echte Fotos von Sehenswürdigkeiten, historischen Personen,
  Gemälden (gemeinfreie Kunst!) aus Wikimedia Commons.
- **Lizenz-Regeln praktikabel machen:** Nur Dateien mit CC0, Public Domain
  oder CC-BY / CC-BY-SA zulassen; KEINE „NC"- (non-commercial) und keine
  „ND"-Lizenzen (App ist kommerziell, Verpixeln ist Bearbeitung).
  Achtung bei CC-BY-SA: Share-Alike bezieht sich auf das Bild-Derivat —
  konservative Linie: bevorzugt CC0/PD/CC-BY, CC-BY-SA nur wenn das
  verpixelte Bild als solches wieder unter gleicher Lizenz nennbar wäre;
  im Zweifel weglassen.
- **Attribution doppelt:** (a) On-Screen dezent im Auflösungs-Moment
  („Foto: <Autor>, CC-BY 4.0, Wikimedia Commons" als kleine Bildunterschrift
  — erst NACH der Auflösung, sonst verrät der Dateiname-artige Credit die
  Antwort!), (b) vollständige Liste mit Links in einem Credits-Screen der
  App. Pro Frage werden Autor, Lizenz, Quell-URL als Pflichtfelder im
  Fragen-Datensatz gespeichert (maschinenlesbares Lizenz-Manifest).
- **Aufwand:** M (Kurations-Workflow + Manifest) · **Prio:** P1.

### Idee 18 — Film-Fragen mit ECHTEN Clips: Blender Open Movies
- **Was:** Big Buck Bunny, Sintel, Tears of Steel, Elephants Dream,
  Cosmos Laundromat u. a. sind CC-BY — echte, hochwertige Filmclips 100 %
  legal einsetzbar (Attribution an Blender Foundation/Autoren).
- **Frage-Formate damit:** „Was passiert als Nächstes?" (Clip stoppt vor
  der Pointe, 4 Optionen), „Welcher Sound fehlt?" (Clip ohne Ton, Sound
  raten), Standbild-Pixel-Raten („Welche Figur ist das?"), Chronologie
  („Ordne diese 4 Szenen"). Die Filme sind kurz und kultig genug, dass
  auch Nicht-Kenner über visuelle Logik raten können — Fragen so bauen,
  dass Filmkenntnis NICHT Voraussetzung ist.
- **Erweiterung:** NASA-Material (Public Domain) für „Weltraum-Clips",
  historische PD-Filme (Stummfilm-Klassiker vor 1929, z. B. für
  „Erkenne die Filmlegende") — Gemeinfreiheit je Titel einzeln prüfen.
- **Aufwand:** M (Clip-Schnitt + Einbindung) · **Prio:** P2.

### Idee 19 — Film-Fragen OHNE Medien: Text, Zitate, Plots
- **Was:** „Welcher Film endet so: …?" (Plot-Beschreibung in eigenen
  Worten), „Aus welchem Film stammt sinngemäß dieses Zitat?" (kurze Zitate
  mit Quellenangabe sind zitatrechtlich vertretbar; sicherheitshalber
  Plot-Paraphrasen bevorzugen), „Echter Film oder ausgedacht?"
  (Wahr/Falsch-Blitz mit absurden, aber echten Filmtiteln), „Tagline
  raten", „Film nach 3 Begriffen" („Hai. Strand. Bürgermeister.").
- **Warum:** Fakten (Titel, Jahr, Regisseur, Plot-Fakten) sind nicht
  schutzfähig — das ist die risikoärmste Film-Kategorie überhaupt und
  deckt gemeinsam mit Emoji-Rätseln (Idee 9) 80 % des
  „Film-Abends"-Gefühls ab.
- **Aufwand:** S (nur Content) · **Prio:** P1.

### Idee 20 — Generierte „Szenen-Nachstellungen" (mit Leitplanken)
- **Was:** KI-Bilder, die eine berühmte Film-SITUATION generisch
  nachstellen (z. B. „ein Mann rennt vor einer rollenden Riesenkugel in
  einem Tempel davon") — geraten wird der Film. Gezeichnet im neutralen
  Haus-Stil, bewusst OHNE Ähnlichkeit zu realen Schauspielern und ohne
  geschützte Marken/Logos/Kostüm-Designs 1:1 (keine konkreten
  Figuren-Designs übernehmen, nur die Situation).
- **Risiko-Hinweis ehrlich:** Das ist die rechtlich grauste der
  vorgeschlagenen Quellen (Figuren-/Szenenschutz bei sehr ikonischen
  Designs). Leitplanke: Nur SITUATIONEN nachstellen, nie Charaktere;
  Review-Checkliste pro Bild; im Zweifel raus. Alternative im selben
  Format: Nachstellungen mit Emoji-Figuren oder Strichmännchen —
  witziger UND sicherer.
- **Aufwand:** M · **Prio:** P2 (Strichmännchen-Variante), P3
  (fotorealistische Variante eher nicht).

### Idee 21 — Audio-Quellen-Stack (CC) + eigener Sound-Zoo
- **Quellen-Prioritäten:** (1) Selbst aufnehmen (Alltagsgeräusche — 1
  Nachmittag Aufnahme-Session deckt Dutzende Fragen, 100 % eigene Rechte);
  (2) CC0-Datenbanken (z. B. Freesound-CC0-Filter — nur CC0, dann keine
  Attributions-Buchführung nötig); (3) gemeinfreie Musik: Werke, deren
  Komponist > 70 Jahre tot ist, in EIGENER Einspielung oder als
  nachweislich gemeinfreie/CC0-Aufnahme (Achtung: Die AUFNAHME hat eigene
  Leistungsschutzrechte — nie „irgendeine" Aufnahme von Beethoven nehmen!);
  (4) generierte Musik/Jingles für Show-Sounds.
- **Gleiche Manifest-Pflicht wie Bilder:** Quelle, Lizenz, Autor pro
  Sound-Datei im Fragen-Datensatz.
- **Aufwand:** M · **Prio:** P2 (mit Idee 8 zusammen).

---

## Teil C — Tipp-System-Design (Ideen 22–23)

### Idee 22 — Die 3-Stufen-Leiter: „vage → eingrenzend → fast Antwort"
- **Design-Prinzip:** Stufe 1 aktiviert Vorwissen („Denk an Skandinavien"),
  Stufe 2 reduziert den Suchraum mechanisch (Option weg, Slider-Bereich
  enger, Element gepinnt — je Typ verschieden, siehe Teil A), Stufe 3 macht
  die Antwort fast sicher, lässt aber einen letzten Denk-Schritt
  (50/50, Anagramm, „eine der zwei Richtigen").
- **Preis-Kurve:** −15/20 %, −35/45 %, −60/65 % vom MÖGLICHEN Gewinn dieser
  Frage (nie vom Konto! Wer einen Tipp kauft und trotzdem falsch liegt,
  verliert kein Bestands-Money — Tipps dürfen sich nie wie Betrug am
  Spieler anfühlen). Stufen nur nacheinander kaufbar (kein Direktsprung zu
  Stufe 3), Restwert wird auf dem Handy live angezeigt („Mit Tipp 2 sind
  noch max. 65 Money drin").
- **Wer kauft:** Default = jeder Spieler individuell und GEHEIM auf dem
  eigenen Handy (die anderen sehen erst bei der Auflösung ein kleines
  Glühbirnen-Icon ×n am Namen — öffentliche Häme light, aber kein
  Live-Verrat). Optional „Ehrlichkeits-Modus": Tipp-Kauf wird sofort auf
  dem Bildschirm angekündigt („Lena zündet Tipp 2!") — mehr Show, für
  mutige Gruppen.
- **Aufwand:** M (Kern-System, wirkt in jedem Frage-Typ) · **Prio:** P1.

### Idee 23 — GM-Gnade & Tipp-Geschenke (der soziale Layer)
- **Was:** Der Game-Master (Host-Rolle am Bildschirm-Gerät oder ein
  Spieler-Handy mit GM-Flagge) hat pro Runde 2 „Gnaden-Tipps", die er
  KOSTENLOS an einzelne Spieler aufs Gerät schicken kann — z. B. an das
  abgeschlagene Kind in der Familien-Runde. Der Beschenkte sieht
  „🎁 Tipp vom GM!", die anderen sehen nur, DASS verschenkt wurde, nicht
  an wen (oder öffentlich, einstellbar).
- **Varianten:** (a) „Robin-Hood-Automatik": Der Letztplatzierte bekommt ab
  Runde 3 Stufe-1-Tipps automatisch gratis (Catch-up ohne GM); (b)
  Spieler können einander Tipps SCHENKEN (kostet dem Schenker echtes
  Money vom Konto — einziger Konto-Abzug im Tipp-System, weil es ein
  Geschenk ist): Allianzen, Flirts, Familien-Diplomatie.
- **Aufwand:** M · **Prio:** P2 (a: S/P2 — b: M/P3).

---

## Teil D — Fairness & Zugänglichkeit (Ideen 24–26)

### Idee 24 — Schätz- und Distanz-Toleranzen, die sich fair ANFÜHLEN
- **Relativ statt absolut:** Toleranzfenster als Prozent des wahren Werts
  (±30 % = Punktefenster), bei großen Spannen logarithmische Slider-Skala
  (Weltbevölkerung vs. „Beine einer Spinne" brauchen verschiedene Skalen).
- **Jahreszahlen:** Toleranz wächst mit Abstand zur Gegenwart (2005 ± 2
  Jahre, 1350 ± 25 Jahre — Faustformel: ± 5 % der Jahre seit dem Ereignis,
  min. ±1).
- **Karten:** Voll-Punkte-Radius abhängig von Zoom-Level der Aufgabe
  (Stadt-Frage: 5 km; Welt-Frage: 300 km).
- **Anti-Frust-Regel überall:** Es gibt IMMER einen „Nächster dran"-Bonus,
  selbst wenn alle außerhalb der Toleranz liegen — niemand-gewinnt-Runden
  töten Partystimmung.
- **Aufwand:** S (Regeln/Tuning) · **Prio:** P1.

### Idee 25 — Farbenblind-sichere Antwort-Codierung (Form + Farbe + Position)
- **Regel:** Antwort-Identität NIE nur über Farbe. Jede Option trägt
  dreifach redundant: (1) Form-Symbol (Kreis/Quadrat/Dreieck/Stern — wie
  Buzz!-Controller), (2) Farbe aus einer deuteranopie-/protanopie-sicheren
  Palette (z. B. Blau/Orange/Violett/Gelbgrün statt Rot/Grün), (3) feste
  Position (auf Handy und Bildschirm IDENTISCHE Reihenfolge — nie
  mischen!). Richtig/Falsch-Feedback zusätzlich mit Haken-/Kreuz-Symbol
  und Haptik-Muster (1× lang = richtig, 2× kurz = falsch) — nicht nur
  grün/rot.
- **Pixel-Bild-Fairness:** Farbenblind-Modus wählt Motive, deren Erkennung
  nicht an Rot-Grün-Kontrast hängt (Kurations-Tag im Fragen-Datensatz:
  `farbkritisch: ja/nein`).
- **Aufwand:** S (Design-Disziplin von Anfang an — nachrüsten wäre L) ·
  **Prio:** P1.

### Idee 26 — Lese-Zeit vor Timer-Start + Latenz-Ausgleich
- **Lese-Phase:** Frage erscheint zuerst OHNE Antwortoptionen für eine
  längenabhängige Lese-Zeit (Faustformel ~180 Wörter/min + 1,5 s Puffer;
  einstellbar „gemütlich/normal/flott" pro Lobby, plus Barrierefrei-Option
  ×1,5). Erst dann erscheinen die Optionen und der Score-Timer startet —
  Schnell-Leser bekommen sonst einen unfairen Dauer-Vorteil.
- **Buzz-Latenz-Fairness (wichtig für Idee 7):** Buzz-Zeitpunkt wird auf
  dem Handy lokal gestempelt und mit gemessenem Geräte-Ping normalisiert;
  bei Gleichstand innerhalb der Messtoleranz (~80 ms) entscheidet das Los
  sichtbar auf dem Bildschirm („Münzwurf!") statt stillschweigend der
  bessere WLAN-Platz.
- **Zusatz:** Ein „Eine-Hand-Modus" (alle Interaktionen in der unteren
  Handy-Hälfte) und Schriftgrößen-Option auf dem Handy.
- **Aufwand:** M (Latenz-Teil), S (Lese-Zeit) · **Prio:** P1 (Lese-Zeit,
  Buzz-Fairness), P2 (Rest).

---

## Priorisierungs-Überblick

| # | Idee | Aufwand | Prio |
|---|------|---------|------|
| 1 | 4er-Choice | S | P1 |
| 2 | Wahr/Falsch-Blitz | S | P1 |
| 3 | Schätz-Slider | M | P1 |
| 4 | Sortier-Frage | M | P2 |
| 5 | Lückentext | M | P2 |
| 6 | Welches Bild passt? | S | P1 |
| 7 | Pixel-/Zoom-Enthüllung | M–L | P1 |
| 8 | Audio-Frage | M | P2 |
| 9 | Emoji-Rätsel | S–M | P1 |
| 10 | Timeline | M | P2 |
| 11 | Karten-Frage | L | P2–P3 |
| 12 | Mehrfach-Antwort 2/6 | S | P2 |
| 13 | Ketten-Frage | S | P2 |
| 14 | Pixel-Bieterrunde | M | P3 |
| 15 | Heißer Stuhl + Wetten | M | P3 |
| 16 | Generierte Bilder (Haus-Stil) | M | P1 |
| 17 | Wikimedia-Commons-Workflow | M | P1 |
| 18 | Blender-Open-Movie-Clips | M | P2 |
| 19 | Text-Film-Fragen | S | P1 |
| 20 | Szenen-Nachstellungen | M | P2–P3 |
| 21 | Audio-CC-Stack | M | P2 |
| 22 | 3-Stufen-Tipp-Leiter | M | P1 |
| 23 | GM-Gnaden-Tipps | S–M | P2 |
| 24 | Faire Toleranzen | S | P1 |
| 25 | Farbenblind-Codierung | S | P1 |
| 26 | Lese-Zeit + Buzz-Latenz | S–M | P1 |

**Launch-Kern-Empfehlung (P1):** Ideen 1, 2, 3, 6, 7, 9 als Frage-Typen +
16, 17, 19 als Medien-Basis + 22 (Tipps) + 24/25/26 (Fairness von Tag 1).
