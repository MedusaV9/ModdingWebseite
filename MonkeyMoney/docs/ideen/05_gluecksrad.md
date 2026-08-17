# MONKEY MONEY — Ideen-Agent 5/20: Das Glücksrad & Runden-Modifier

> Reine Ideation, keine Code-Änderungen. Kontext: Jackbox/Buzz-artige Quiz-Show-
> Party-App (Handys = Controller, großer Bildschirm, GM optional mit
> Trigger-Knopf, Money-/Affen-Thema). Der GM triggert das Glücksrad, das Spiel
> pausiert kurz, alle sehen das Ergebnis auf dem großen Bildschirm, der
> Modifier passt zum aktuellen Modus/Minispiel.
>
> Referenz-Formate (für Kompatibilitätsangaben):
> **Buzzer-Blitz** (schnellste richtige Antwort), **Multiple-Choice-Standard**
> (alle antworten parallel, Speed-Bonus), **Schätzfrage** (näheste Zahl
> gewinnt), **Sortier-Runde** (Reihenfolge legen), **Bomben-Weitergabe**
> (Hot-Potato, wer die Bombe hält verliert), **Bild-Zoom** (Bild deckt sich
> langsam auf), **Sound-Runde** (Audio-Schnipsel raten), **Finale**
> (Punkte-Einsatz/Wette).
>
> Legende: Aufwand **S**(klein)/**M**(mittel)/**L**(groß), Prio
> **MUST/SHOULD/COULD**. Timing-Bezeichnungen: „nächste Frage" = genau 1
> Frage, „Rest der Runde" = bis zum nächsten Minispiel-Wechsel.

---

## Teil (a) — 18 Rad-Segmente / Modifier

### Positive Segmente

#### 1. „Doppelter Zaster" 🍌💰 — Aufwand S, Prio MUST
- **Wirkung exakt:** Alle Spieler erhalten für die **nächste Frage** doppelte
  Punkte (Gewinne x2, Verluste bleiben normal — kein Doppel-Malus).
- **Kompatibilität:** Sinnvoll bei Buzzer-Blitz, Multiple-Choice, Schätzfrage,
  Bild-Zoom, Sound-Runde. **Gesperrt** bei Bomben-Weitergabe (dort gibt es
  keine klassische Punktevergabe) und im Finale (dort regelt der Einsatz die
  Höhe bereits selbst).
- **Bildschirm/Sound:** Der Punkte-Ticker der nächsten Frage färbt sich
  golden, Münzregen-Overlay am Rand, Kassenklingel-Sound („Cha-Ching!") beim
  Einlochen der Punkte.
- **Spaß-Begründung:** Der Klassiker, den jeder sofort versteht — erzeugt
  ohne Erklärung Spannung („JETZT zählt's!") und ist der perfekte
  Einsteiger-Modifier für die erste Version des Rads.

#### 2. „Banana Bailout" (Banken-Rettung) 🏦 — Aufwand S, Prio MUST
- **Wirkung exakt:** **Nur der aktuell Letztplatzierte** erhält sofort einen
  Extra-Joker (50:50 oder Zeit-Stopp, je nach Modus) UND +15 % des
  Punkteabstands zum Vorletzten gutgeschrieben. Einmalige Sofort-Wirkung.
- **Kompatibilität:** Überall sinnvoll; in Teamspielen bekommt das letzte
  Team die Rettung. Keine Sperren.
- **Bildschirm/Sound:** Spotlight auf den Avatar des Letzten, ein
  Geldkoffer-Fallschirm segelt vom oberen Bildschirmrand zu ihm herab,
  Fanfare + Hubschrauber-Sound. Kurzer Text: „Die Affen-Zentralbank rettet
  [Name]!"
- **Spaß-Begründung:** Rubber-Banding gegen Frust — der Abgehängte bleibt im
  Spiel, und die Führenden stöhnen genüsslich auf. Klassisches
  Party-Balancing wie der blaue Panzer in Mario Kart.

#### 3. „Insider-Tipp" 🤫📈 — Aufwand M, Prio SHOULD
- **Wirkung exakt:** Ein per Rad-Unterdrehung zufällig bestimmter Spieler
  sieht für die **nächste Frage** auf SEINEM Handy 3 Sekunden vor allen
  anderen die Frage (nicht die Antwort!).
- **Kompatibilität:** Sinnvoll bei Buzzer-Blitz, Multiple-Choice,
  Schätzfrage. **Gesperrt** bei Sortier-Runde und Bild-Zoom (dort gibt es
  keinen sinnvollen Vorsprungsmoment) und Bomben-Weitergabe.
- **Bildschirm/Sound:** Auf dem großen Bildschirm nur: „Jemand hat einen
  Insider-Tipp bekommen…" mit Fragezeichen-Avataren — WER, sehen nur der
  Betroffene und der GM. Verschwörerisches Flüster-Sample.
- **Spaß-Begründung:** Erzeugt Misstrauen und Gelächter am Tisch („Warum
  grinst DU so?") — Information-Asymmetrie ist bei Couch-Partys Gold wert.

#### 4. „Dividende" 💹 — Aufwand S, Prio SHOULD
- **Wirkung exakt:** Für den **Rest der Runde** erhält jeder Spieler nach
  jeder richtigen Antwort zusätzlich +5 % seines aktuellen Kontostands als
  Zins (gerundet). Reiche werden reicher — bewusst!
- **Kompatibilität:** Multiple-Choice, Buzzer-Blitz, Sound-Runde.
  **Gesperrt** im Finale und bei Bomben-Weitergabe.
- **Bildschirm/Sound:** Kleines Aktienkurs-Chart neben jedem Avatar, das bei
  Zinsausschüttung nach oben zackt; Börsenglocken-Sound.
- **Spaß-Begründung:** Das thematische Gegenstück zum Bailout — die Führenden
  jubeln, die anderen buhen. Das Rad soll BEIDE Richtungen bedienen, sonst
  fühlt es sich wie ein reines Mitleids-Tool an.

### Negative Segmente

#### 5. „Halbe Miete" ⏱️✂️ — Aufwand S, Prio MUST
- **Wirkung exakt:** Die Antwortzeit **aller Spieler** wird für die
  **nächste Frage** halbiert (z. B. 20 s → 10 s). Der vom User explizit
  gewünschte „weniger Zeit"-Modifier.
- **Kompatibilität:** Sinnvoll bei Multiple-Choice, Schätzfrage,
  Sortier-Runde, Bild-Zoom (Bild deckt doppelt so schnell auf).
  **Gesperrt** bei Buzzer-Blitz (dort gibt es kein festes Zeitfenster) und
  Bomben-Weitergabe (hat eigenen Timer).
- **Bildschirm/Sound:** Der Timer-Balken wird sichtbar in der Mitte
  durchgesägt (Kreissägen-Animation + Sound), die Resthälfte pulsiert rot;
  Tick-Geschwindigkeit des Countdown-Sounds verdoppelt.
- **Spaß-Begründung:** Sofort spürbarer Druck, kollektives Aufstöhnen im
  Raum — der einfachste Weg, eine müde Fragerunde zu elektrisieren.

#### 6. „Affentheater" 🙈🔀 — Aufwand M, Prio SHOULD
- **Wirkung exakt:** Bei der **nächsten Frage** werden die
  Antwort-Positionen auf dem großen Bildschirm in ANDERER Reihenfolge
  angezeigt als auf den Handys — es zählt allein die Zuordnung per
  Antwort-TEXT auf dem eigenen Handy. Wer stur „Position B vom TV" drückt,
  fällt rein.
- **Kompatibilität:** NUR Multiple-Choice und Bild-Zoom (mit
  Auswahlantworten). **Gesperrt** bei allen anderen Formaten (automatisch
  aus dem Pool genommen).
- **Bildschirm/Sound:** Die Antwortkästen auf dem TV mischen sich sichtbar
  mit einem Kartentrick-Wusch; ein Affe mit Zylinder zwinkert in der Ecke.
  Jahrmarkts-Hütchenspieler-Musik.
- **Spaß-Begründung:** Bestraft Autopilot-Spielen, belohnt Lesen — und der
  Moment der Auflösung („WAS, ich hab auf die TV-Position getippt!") ist ein
  garantierter Lacher.

#### 7. „Inflation!" 📉🔥 — Aufwand S, Prio SHOULD
- **Wirkung exakt:** Für den **Rest der Runde** verlieren ALLE Spieler pro
  Frage 3 % ihres Kontostands (Abzug beim Frage-Ende, mindestens 5 Punkte).
  Richtige Antworten schützen nicht — nur schnelles Rundenende.
- **Kompatibilität:** Alle punktebasierten Formate. **Gesperrt** im Finale
  (Einsatz-Logik) und wenn ein Spieler unter einer Mindestpunktzahl liegt
  (dann wird stattdessen automatisch neu gedreht, kein Bankrott-Frust).
- **Bildschirm/Sound:** Alle Punktzahlen „schmelzen" sichtbar mit einem
  Tropf-Effekt, ein Geldschein-Lagerfeuer brennt in der Bildschirmecke;
  bedrohliches Cello + Nachrichtensprecher-Sample „Die Inflation steigt!"
- **Spaß-Begründung:** Kollektiver Gegner statt Spieler-gegen-Spieler-Ärger;
  trifft die Reichen absolut am härtesten und komprimiert nebenbei das Feld.

#### 8. „Affenpfoten-Modus" 🐒👆 — Aufwand M, Prio COULD
- **Wirkung exakt:** Für die **nächste Frage** werden die Antwort-Buttons
  auf den Handys aller Spieler winzig und wandern langsam über den Screen
  (Touch-Ziel-Erschwernis, Treffer zählt normal).
- **Kompatibilität:** Multiple-Choice, Sortier-Runde (Elemente zappeln).
  **Gesperrt** bei Schätzfrage (Zahleneingabe), Buzzer-Blitz (unfair beim
  Reaktionsduell), Bomben-Weitergabe.
- **Bildschirm/Sound:** Auf dem TV läuft eine Banane über die Antwortkästen;
  auf den Handys vibriert es kurz. Rutsch-/Boing-Sounds bei Fehltaps.
- **Spaß-Begründung:** Physische Komik — die Leute halten ihre Handys
  plötzlich mit zwei Händen und fluchen liebevoll. Reiner Slapstick, kein
  echter Wissens-Nachteil.

#### 9. „Steuerprüfung" 🧾 — Aufwand S, Prio COULD
- **Wirkung exakt:** Der **aktuell Führende** muss bei der **nächsten
  Frage** korrekt antworten, sonst zahlt er eine „Nachzahlung" von 10 %
  seines Kontostands in einen Pott, den der Gewinner der Frage kassiert.
- **Kompatibilität:** Multiple-Choice, Buzzer-Blitz, Schätzfrage, Bild-Zoom.
  **Gesperrt** bei Bomben-Weitergabe und im Finale.
- **Bildschirm/Sound:** Ein Aktenkoffer-Beamter-Affe stempelt den Avatar des
  Führenden mit „PRÜFUNG"; trockener Stempel-Sound, danach tickende Uhr.
- **Spaß-Begründung:** Zielt gezielt auf die Spitze, ohne sie zu enteignen —
  der Führende schwitzt EINE Frage lang, alle anderen feuern gegen ihn.

### Chaotische Segmente

#### 10. „Affen-Tausch-Börse" 🔄🐵 — Aufwand M, Prio SHOULD
- **Wirkung exakt:** **Sofort-Effekt:** Jeder Spieler tauscht seinen
  Punktestand mit seinem Sitznachbarn (Tausch-Richtung im Uhrzeigersinn
  entlang der Lobby-Reihenfolge; bei Teams tauschen die Teams). Kein
  Rücktausch.
- **Kompatibilität:** Überall, ABER automatisch **gesperrt** in den letzten
  zwei Runden des Matches und im Finale (sonst entwertet es den ganzen
  Abend). GM kann es zusätzlich per Setting deaktivieren.
- **Bildschirm/Sound:** Alle Avatare springen mit Affengeschrei im Kreis auf
  die Nachbarposition, die Punktzahlen fliegen als Geldbündel hinterher;
  Börsenparkett-Geschrei-Sample.
- **Spaß-Begründung:** Der größte „NEEEIN!"/„JAAAA!"-Moment im ganzen Pool —
  maximales Chaos, deshalb selten gewichtet und spät gesperrt. Genau diese
  Sorte Geschichte erzählt man sich am nächsten Tag noch.

#### 11. „Stumm-Runde: Blackout im Studio" 📺🕶️ — Aufwand M, Prio SHOULD
- **Wirkung exakt:** Bei der **nächsten Frage** zeigt der große Bildschirm
  NUR einen flackernden „Sendeausfall"-Testbildschirm — Frage UND Antworten
  erscheinen ausschließlich auf den Handys. Niemand kann mehr mitlesen oder
  vom Nachbarn abschauen; Vorlese-Stimme (falls aktiv) fällt ebenfalls aus.
- **Kompatibilität:** Multiple-Choice, Schätzfrage, Sortier-Runde.
  **Gesperrt** bei Bild-Zoom und Sound-Runde (Bild/Ton IST dort die Frage)
  und Buzzer-Blitz (der lebt vom gemeinsamen Bildschirm-Moment).
- **Bildschirm/Sound:** Statisches Rauschen, dann SMPTE-Testbild mit einem
  Affen, der an Kabeln kaut; Radio-Stör-Sound, danach unheimliche Stille —
  nur die Handys vibrieren.
- **Spaß-Begründung:** Dreht die Raum-Dynamik komplett: plötzlich starren
  alle in ihre Handys und es wird verdächtig still — die Stille selbst ist
  der Witz. (Direkt vom User gewünschtes Segment.)

#### 12. „Börsen-Roulette" 🎰 — Aufwand M, Prio COULD
- **Wirkung exakt:** Jeder Spieler wählt vor der **nächsten Frage** blind
  auf seinem Handy „Long" oder „Short". Bei richtiger Antwort: Long = +150 %
  Punkte, Short = +50 %. Bei falscher Antwort: Long = −50 Punkte,
  Short = ±0. Wahlzeit 5 Sekunden, keine Wahl = automatisch Short.
- **Kompatibilität:** Multiple-Choice, Schätzfrage, Bild-Zoom. **Gesperrt**
  bei Buzzer-Blitz, Bomben-Weitergabe, Sortier-Runde (zu viele
  Teilentscheidungen).
- **Bildschirm/Sound:** Kurzer Split-Screen „LONG 🐂 / SHORT 🐻" mit
  tickendem Kurs-Chart; nach der Auflösung zackt der Kurs pro Spieler hoch
  oder runter. Wall-Street-Glocke.
- **Spaß-Begründung:** Fügt eine Meta-Wette über das eigene Können hinzu —
  Selbstüberschätzung wird öffentlich sichtbar und ist herrlich zu
  kommentieren.

#### 13. „Der Affe würfelt" 🎲🙊 — Aufwand S, Prio COULD
- **Wirkung exakt:** Das Rad delegiert: Ein animierter Affe „beantwortet"
  die **nächste Frage** zusätzlich als Bot-Mitspieler mit Zufallsantwort
  und mittlerer Geschwindigkeit. Schlägt er einen echten Spieler, zahlt
  dieser 20 Punkte „Schmach-Gebühr" in den Pott der nächsten Frage.
- **Kompatibilität:** Multiple-Choice, Schätzfrage (Affe tippt Zufallszahl
  im plausiblen Bereich), Buzzer-Blitz. **Gesperrt** bei Sortier-Runde,
  Bomben-Weitergabe, Bild-Zoom.
- **Bildschirm/Sound:** Der Affe sitzt sichtbar mit eigenem Antwort-Kästchen
  zwischen den Spieler-Avataren, kratzt sich am Kopf, tippt dann theatralisch;
  Schreibmaschinen- + Affen-Sound.
- **Spaß-Begründung:** „Von einem Zufalls-Affen geschlagen zu werden" ist
  die perfekte Party-Demütigung — kostenloser Running Gag für den Rest des
  Abends.

#### 14. „Falschgeld im Umlauf" 💵🚨 — Aufwand M, Prio COULD
- **Wirkung exakt:** Für den **Rest der Runde** sind 30 % aller
  Punktegewinne „Falschgeld": Sie werden normal angezeigt, aber am
  Rundenende platzt ein Zufallsanteil (pro Spieler unterschiedlich, Seed
  fair pro Runde) sichtbar weg. Niemand weiß bis dahin, wie viel echt war.
- **Kompatibilität:** Multiple-Choice, Buzzer-Blitz, Sound-Runde.
  **Gesperrt** im Finale und in der letzten regulären Runde.
- **Bildschirm/Sound:** Punktegewinne erscheinen mit leichtem Grünstich-
  Flackern; am Rundenende UV-Lampen-Scan über alle Konten, Blüten verpuffen
  mit „Poof". Kriminalpolizei-Sirenen-Blip.
- **Spaß-Begründung:** Eine ganze Runde lang schwebt Unsicherheit über jedem
  Jubel — und die Auflösung am Rundenende ist ein eigener Show-Moment.

### Soziale Segmente

#### 15. „Umarmungs-Bonus" 🤗 — Aufwand S, Prio SHOULD
- **Wirkung exakt:** 15-Sekunden-Countdown: Alle Spieler, die sich in
  dieser Zeit real umarmen (Bestätigung: beide drücken danach gleichzeitig
  den „Umarmt!"-Button auf ihren Handys, Paar-Matching per gleichzeitigem
  Tap), erhalten je +25 Punkte. Einmalig, keine Frage-Auswirkung.
- **Kompatibilität:** Überall zwischen zwei Fragen einsetzbar; keine
  Sperren. In „Fremde/Streamer-Lobby"-Settings ersetzt durch „High-Five auf
  Distanz"-Emote.
- **Bildschirm/Sound:** Herz-Konfetti pro bestätigtem Paar, Kuschel-Jingle,
  Kamera-Blitz-Sound; der große Bildschirm zählt „3 Umarmungen = 150 Punkte
  verteilt!"
- **Spaß-Begründung:** Bringt Leute physisch in Bewegung und produziert die
  Fotos des Abends — Party-Apps leben von Momenten ABSEITS des Bildschirms.

#### 16. „Shot oder Schotter" 🥃 — Aufwand S, Prio COULD — **NUR Alkohol-Edition**
- **Wirkung exakt:** Der Spieler mit der langsamsten richtigen Antwort der
  LETZTEN Frage wählt auf seinem Handy binnen 10 s: Shot trinken (Ehre
  wiederhergestellt, +30 Punkte „Mut-Prämie") ODER 40 Punkte „Feigheits-
  Steuer" zahlen. Einmalige Sofort-Wirkung.
- **Kompatibilität:** Nur wenn das Match-Setting „Alkohol-Edition (18+)"
  aktiv ist — sonst existiert das Segment GAR NICHT auf dem Rad (nicht nur
  ausgegraut). Formatunabhängig einsetzbar; gesperrt, wenn die letzte Frage
  keine auswertbare Langsamster-Wertung hatte.
- **Bildschirm/Sound:** Saloon-Türen schwingen auf, das Rad-Segment zeigt
  ein klimperndes Schnapsglas; Country-Gitarren-Lick, dann Trommelwirbel
  bis zur Wahl. Bei „Shot": Gläser-Klirren + Jubel-Sample.
- **Spaß-Begründung:** Der Wahl-Mechanismus (trinken ODER zahlen) hält es
  konsensuell und nimmt Druck raus — trotzdem grölt der ganze Raum. Klare
  Trennung per Edition schützt Familien-/Streamer-Runden.

#### 17. „Kompliment-Konto" 💬💛 — Aufwand S, Prio COULD
- **Wirkung exakt:** Das Rad bestimmt zufällig zwei Spieler: A muss B binnen
  20 s laut ein ernst gemeintes Kompliment machen (GM oder Mehrheits-Vote
  auf den Handys bestätigt „ernst gemeint"). Gelingt es: BEIDE +20 Punkte;
  verweigert A: B bekommt 20 Punkte von A.
- **Kompatibilität:** Überall zwischen Fragen; keine Format-Sperren.
  Deaktivierbar im Setting „Nur-Spiel-Modus" für Gruppen, die keine
  Bühnen-Momente wollen.
- **Bildschirm/Sound:** Zwei Spotlights auf beide Avatare, kitschige
  Herz-Rahmen, Seifenoper-Streicher; bei Bestätigung „Aww!"-Publikums-Sample.
- **Spaß-Begründung:** Zwingt zu einem echten sozialen Mikro-Moment —
  zwischen Fremden eisbrechend, zwischen Freunden absurd komisch.

#### 18. „Affen-Anwalt" ⚖️🐒 — Aufwand M, Prio COULD
- **Wirkung exakt:** Der Letztplatzierte darf für den **Rest der Runde**
  EINMAL nach einer Auflösung „Einspruch!" drücken: Die Gruppe stimmt per
  Handy ab, ob seine falsche Antwort „vertretbar" war (z. B. Tippfehler,
  fiese Formulierung). Bei Mehrheit: halbe Punkte nachträglich.
- **Kompatibilität:** Multiple-Choice, Schätzfrage, Sortier-Runde.
  **Gesperrt** bei Buzzer-Blitz und Bomben-Weitergabe (keine
  interpretierbare Antwort).
- **Bildschirm/Sound:** Gerichts-Hammer-Sound, der Bildschirm wird zum
  Gerichtssaal mit Affen-Richter-Perücke über dem Avatar; Abstimmung als
  Daumen-hoch/runter-Balken.
- **Spaß-Begründung:** Legalisiert die Diskussionen, die am Tisch sowieso
  entstehen („Das war doch gemein formuliert!") und macht daraus einen
  eigenen Show-Beat mit Publikum als Jury.

---

## Teil (b) — Rad-Design

### B1. Gewichtungs-System („Seltenheits-Stufen") — Aufwand M, Prio MUST
- Drei sichtbare Seltenheitsklassen, farbcodiert auf dem Rad:
  **Häufig (grün, je ~12 %):** Doppelter Zaster, Halbe Miete, Banana
  Bailout — die verständlichen Brot-und-Butter-Segmente.
  **Gelegentlich (blau, je ~6 %):** Dividende, Affentheater, Inflation,
  Insider-Tipp, Börsen-Roulette, Umarmungs-Bonus.
  **Selten (gold, je ~2–3 %):** Affen-Tausch-Börse, Blackout, Falschgeld,
  Steuerprüfung, Shot oder Schotter.
- Zusatzregeln: (1) **Pech-Schutz:** dasselbe Segment kann nicht zweimal
  hintereinander fallen; (2) **Pity-Timer:** nach 4 Drehungen ohne
  Gold-Segment steigt dessen Chance pro Dreh um +2 %; (3) das Rad rendert
  physisch nur ~10 Segmente gleichzeitig — der Pool wird vor jedem Dreh aus
  den gerade KOMPATIBLEN Segmenten gemäß Gewichtung bestückt, so gibt es nie
  „gesperrte" Segmente sichtbar auf dem Rad (kein Anti-Klimax durch
  „gilt hier nicht"-Ergebnisse).

### B2. GM-Kontrolle & Segment-Pool-Verwaltung — Aufwand M, Prio MUST
- **Pro-Match-Setting (Lobby):** Checkbox-Liste aller Segmente mit
  Preset-Filtern „Familie" (ohne Shot, ohne Punkteklau), „Klassiker" (nur
  grün/blau), „Vollgas" (alles an), „Alkohol-Edition 18+" (schaltet
  Shot-Segmente frei). Presets speicherbar pro GM-Profil.
- **Live-GM-Panel während des Spiels:** GM sieht auf seinem Handy den
  aktuellen Pool und kann einzelne Segmente on-the-fly muten (z. B.
  Tausch-Börse aus, wenn die Stimmung kippt). Muting wirkt ab dem nächsten
  Dreh, nie rückwirkend.
- **„Nochmal drehen"-Kosten:** Der GM hat pro Match 2 kostenlose Re-Spins
  (für Anti-Klimax-Momente). Danach kostet jeder Re-Spin theatralisch
  „Studio-Budget": Der Bildschirm zeigt einen Buchhalter-Affen, der
  seufzend Scheine zählt, und ALLE Spieler bekommen +10 Punkte
  „Schweigegeld" aus der Studio-Kasse — der GM kauft sich den Re-Spin also
  auf Kosten der Dramaturgie, nicht einzelner Spieler. Optional strenger:
  Re-Spin 3+ deaktiviert das Gold-Segment für diesen Dreh.
- **GM-„Rigging"-Knopf (versteckt, COULD):** Langer Druck auf den
  Trigger-Knopf öffnet eine Auswahl von 3 zufälligen Segmenten, aus denen
  der GM heimlich eins vorwählen kann (max. 1x pro Match). Für kuratierte
  Show-Momente — die Spieler sehen weiterhin einen normalen Dreh.

### B3. Auto-GM-Trigger-Heuristik (Software dreht selbst) — Aufwand M, Prio SHOULD
Wenn kein GM aktiv ist ODER das Setting „Auto-Rad" an ist, triggert die
Software das Rad selbst. Heuristik-Vorschlag (Prioritätsreihenfolge):
1. **Langeweile-Detektor:** ≥4 Fragen in Folge ohne Rad UND ohne
   Führungswechsel → Dreh vor der nächsten Frage (Wahrscheinlichkeit 80 %).
2. **Blowout-Bremse:** Abstand Platz 1 zu Platz 2 > 35 % der
   durchschnittlichen Rundenausbeute → Dreh mit erhöhtem Gewicht auf
   Aufhol-Segmenten (Bailout, Steuerprüfung, Inflation).
3. **Fixe Show-Beats:** Genau 1 garantierter Dreh pro Minispiel-Wechsel
   (zwischen den Runden), damit das Rad zuverlässig Teil der Dramaturgie
   ist, nie mitten in einer laufenden Frage.
4. **Cooldown & Obergrenze:** Nie 2 Drehs innerhalb von 2 Fragen; hartes
   Maximum ~1 Dreh pro 3–4 Fragen, damit das Rad besonders bleibt.
5. **Endspiel-Regel:** In den letzten 2 Runden nur noch Drehs aus einem
   reduzierten „Fair-Finale-Pool" (keine Tausch-Börse, kein Falschgeld).
- Der GM-Trigger-Knopf überschreibt die Heuristik jederzeit; manuelle Drehs
  setzen den Cooldown der Automatik zurück.

### B4. Inszenierung des Drehs (Spannungs-Dramaturgie) — Aufwand M, Prio MUST
- **Phase 1 — Unterbrechung (1 s):** Aktuelles Spiel friert mit
  Schallplatten-Stopp-Sound („Vinyl-Scratch") ein, Licht dimmt, alle
  Handys vibrieren gleichzeitig kurz — der Raum weiß sofort: Rad-Zeit.
- **Phase 2 — Auffahrt (2 s):** Das Rad fährt riesig von unten ins Bild,
  goldener Rahmen, Affen-Publikum trommelt; auf den Handys erscheint ein
  „ALLE AUGEN AUF DEN BILDSCHIRM"-Screen (Handys zeigen bewusst NICHTS
  Nützliches — der Moment gehört dem großen Bildschirm).
- **Phase 3 — Dreh (3–5 s):** Klassischer Ratschen-Ticker-Sound, dessen
  Klick-Frequenz mit dem Rad physikalisch glaubwürdig abnimmt
  (Slow-down-Kurve mit leichtem Zurückfedern über die letzte Segmentkante —
  der „fast wär's das andere gewesen!"-Effekt, bewusst in ~30 % der Drehs
  als Beinahe-Ergebnis choreografiert).
- **Phase 4 — Einschlag (2 s):** Segment-abhängig: Gold-Segmente →
  Konfetti-Kanonen + Fanfare + Zeitlupen-Replay des letzten Ticks; negative
  Segmente → dumpfer Basston, kurzes Rotlicht, hämisches Affenlachen;
  soziale Segmente → warmes Licht + Publikums-„Ooooh".
- **Phase 5 — Erklärkarte (3–4 s, MUST):** Große Karte mit Name, Icon und
  EINEM Satz Wirkung („Nächste Frage: halbe Zeit für ALLE!") + dieselbe
  Karte kompakt auf allen Handys. Betroffene Spieler werden namentlich
  genannt und gehighlightet. Danach nahtlos zurück ins Spiel.
- Gesamtdauer max. ~12 s, via Setting „Kurze Show" auf ~6 s kürzbar
  (Vielspieler-Respekt).

### B5. Rad-Meta & Sammelspaß — Aufwand L, Prio COULD
- Segment-Historie am Match-Ende („Heute 6x gedreht: 2x Halbe Miete…") als
  Teil der Sieger-Zeremonie; seltene Segmente erscheinen im
  Abend-Highlight-Reel.
- Saisonale/freischaltbare Rad-Skins (Dschungel-Rad, Tresor-Rad,
  Casino-Rad) — rein kosmetisch, keine Gameplay-Kopplung.

---

## Teil (c) — Alternative Zufalls-Events neben dem Rad

### C1. „Der Money-Koffer" 💼 — Aufwand M, Prio SHOULD
- Zwischen zwei Fragen erscheint unangekündigt ein verschlossener Koffer auf
  dem großen Bildschirm. JEDER Spieler entscheidet binnen 8 s blind auf dem
  Handy: „Beanspruchen" oder „Ignorieren". Der Koffer enthält zu 60 %
  +80 Punkte, zu 30 % eine Handschellen-Falle (−40 Punkte), zu 10 % einen
  Joker. Twist: Beanspruchen ihn MEHRERE, wird der Inhalt (auch der
  negative!) durch alle Beanspruchenden GETEILT.
- **Inszenierung:** Koffer wackelt und klickt verdächtig; Auflösung mit
  Zahlenschloss-Drehung Ziffer für Ziffer.
- **Warum neben dem Rad:** Das Rad ist ein passives Schicksals-Event — der
  Koffer ist eine aktive Gier-Entscheidung jedes Einzelnen. Anderer
  psychologischer Muskel, gleiche Pausen-Länge.

### C2. „Affen-Alarm" 🚨🐒 — Aufwand M, Prio SHOULD
- Sirene + Rotlicht: „Ein Affe ist im Studio ausgebrochen!" Für 20 Sekunden
  rennt ein Affe über den großen Bildschirm und „klaut" sichtbar
  Geldbündel-Icons aus den Punktekonten (je 5 Punkte pro Sekunde vom
  aktuell Führenden). Alle Spieler können ihn stoppen, indem sie
  gleichzeitig auf ihren Handys ein 3er-Tap-Muster („Banane werfen")
  treffen — Erfolg ab X synchronen Treffern (X = Spielerzahl/2). Wird er
  gestoppt, regnet das Diebesgut als Gleichverteilung auf ALLE zurück.
- **Warum neben dem Rad:** Kooperatives Sofort-Minigame statt Modifier —
  bringt Hektik und gemeinsames Geschrei, ohne eine Frage zu verändern.

### C3. „Börsencrash / Bullenmarkt" 📉📈 — Aufwand S, Prio SHOULD
- Seltenes Doppel-Event (max. 1x pro Match, nie in den letzten 2 Runden):
  Ein Nachrichten-Banner unterbricht das Spiel. **Crash (50 %):** Alle
  Punktestände werden um 20 % Richtung Median komprimiert (Führende
  verlieren relativ, Hintere kaum). **Bullenmarkt (50 %):** Die Punkte der
  NÄCHSTEN kompletten Runde zählen für alle x1,5. Welcher der beiden Fälle
  eintritt, entscheidet live ein fallender/steigender Kurs-Chart mit
  Herzschlag-Sound.
- **Warum neben dem Rad:** Ein „Weltereignis", das ALLE gleichzeitig trifft
  und die Tabelle atmen lässt — thematisch das Money-Herzstück, dramaturgisch
  der große Mid-Game-Twist.

### C4. „Die Goldene Banane" 🍌✨ — Aufwand M, Prio COULD
- Irgendwann in der Runde blitzt für 2 Sekunden eine goldene Banane in einer
  zufälligen Ecke des GROSSEN Bildschirms auf. Der erste Spieler, der danach
  auf seinem Handy den „Banane!"-Buzzer drückt, kassiert sie (+50 Punkte) —
  ABER: Drücken bei falschem Alarm (kein Banane sichtbar) kostet 25 Punkte.
  Erscheint 1–2x pro Match zu unvorhersehbaren Zeitpunkten, auch MITTEN in
  einer Frage.
- **Warum neben dem Rad:** Belohnt Aufmerksamkeit auf den gemeinsamen
  Bildschirm über den ganzen Abend (Gegenmittel gegen Nur-aufs-Handy-
  Starren) und erzeugt herrliche Fehlbuzzer-Momente.

### C5. „Erbschaft aus Übersee" 📜🐒 — Aufwand S, Prio COULD
- Ein Brief-Umschlag segelt auf den Bildschirm: „Onkel Bananarius ist
  verstorben." Ein ZUFÄLLIGER Spieler (gewichtete Lotterie: je weniger
  Punkte, desto mehr Lose) erbt einen Betrag in Höhe von 50 % des
  DURCHSCHNITTS-Kontostands — muss aber vorher binnen 10 s eine absurde
  „Erbschafts-Bedingung" erfüllen, die der Umschlag nennt (z. B. „Mache
  3 Sekunden lang Affengeräusche", Bestätigung per GM-Knopf oder
  Gruppen-Vote).
- **Warum neben dem Rad:** Kombiniert Aufhol-Mechanik mit einem sozialen
  Performance-Moment — die Bedingung ist der eigentliche Inhalt, die Punkte
  sind der Vorwand.

---

## Priorisierungs-Übersicht

| # | Idee | Typ | Aufwand | Prio |
|---|------|-----|---------|------|
| 1 | Doppelter Zaster | Segment positiv | S | MUST |
| 2 | Banana Bailout | Segment positiv | S | MUST |
| 3 | Insider-Tipp | Segment positiv | M | SHOULD |
| 4 | Dividende | Segment positiv | S | SHOULD |
| 5 | Halbe Miete | Segment negativ | S | MUST |
| 6 | Affentheater | Segment negativ | M | SHOULD |
| 7 | Inflation! | Segment negativ | S | SHOULD |
| 8 | Affenpfoten-Modus | Segment negativ | M | COULD |
| 9 | Steuerprüfung | Segment negativ | S | COULD |
| 10 | Affen-Tausch-Börse | Segment chaotisch | M | SHOULD |
| 11 | Stumm-Runde: Blackout | Segment chaotisch | M | SHOULD |
| 12 | Börsen-Roulette | Segment chaotisch | M | COULD |
| 13 | Der Affe würfelt | Segment chaotisch | S | COULD |
| 14 | Falschgeld im Umlauf | Segment chaotisch | M | COULD |
| 15 | Umarmungs-Bonus | Segment sozial | S | SHOULD |
| 16 | Shot oder Schotter (18+) | Segment sozial | S | COULD |
| 17 | Kompliment-Konto | Segment sozial | S | COULD |
| 18 | Affen-Anwalt | Segment sozial | M | COULD |
| B1 | Gewichtungs-System | Rad-Design | M | MUST |
| B2 | GM-Kontrolle & Pool | Rad-Design | M | MUST |
| B3 | Auto-GM-Heuristik | Rad-Design | M | SHOULD |
| B4 | Dreh-Inszenierung | Rad-Design | M | MUST |
| B5 | Rad-Meta & Skins | Rad-Design | L | COULD |
| C1 | Money-Koffer | Alt-Event | M | SHOULD |
| C2 | Affen-Alarm | Alt-Event | M | SHOULD |
| C3 | Börsencrash/Bullenmarkt | Alt-Event | S | SHOULD |
| C4 | Goldene Banane | Alt-Event | M | COULD |
| C5 | Erbschaft aus Übersee | Alt-Event | S | COULD |

**MVP-Empfehlung:** B1+B2+B4 (Rad-Fundament) mit den drei MUST-Segmenten
(Doppelter Zaster, Halbe Miete, Banana Bailout) — damit steht ein
funktionierendes, verständliches Rad; danach die SHOULD-Segmente in der
Reihenfolge Blackout → Tausch-Börse → Affentheater als erste
„Wow-Erweiterung", parallel B3 für GM-lose Runden.
