# Ideen-Agent 14/20 — Die MONEY-ÖKONOMIE von MONKEY MONEY

> Thema: Das namensgebende Herz der App. Match-Ökonomie, Inszenierung,
> All-Time-Ökonomie, Anti-Frust. 24 Ideen mit konkreten Startwerten fürs
> Balancing. Aufwand: S/M/L (Implementierungsumfang), Prio: P1 (Kern,
> ohne das fühlt sich MONKEY MONEY nicht nach Money an) / P2 (starker
> Mehrwert) / P3 (Ausbau später).

## Leitprinzipien (Design-Kompass)

1. **Money ist Punktestand UND Spielressource.** Man kann es AUSGEBEN
   (Tipps, Joker, Wetten) — dadurch wird jeder Kontostand eine Entscheidung,
   nicht nur eine Anzeige.
2. **Drama vor Fairness, aber Fairness im Finale.** Zwischenrunden dürfen
   gemein sein (Zins, Klau, Schulden) — das Finale garantiert mathematisch,
   dass Platz 4 noch gewinnen KANN (Idee I-21).
3. **Zwei Währungs-Sphären, eine Richtung.** Match-Money → All-Time-Money
   fließt nur in eine Richtung (nie All-Time ins Match einsetzbar!), sonst
   kauft sich der Grinder den Match-Sieg → Pay-to-win-Gefühl unter Freunden.
4. **Runde Zahlen, Schein-Stückelung.** Alle Beträge sind Vielfache von 50,
   damit die Inszenierung (Idee I-13: Scheine fliegen einzeln) aufgeht:
   1 Schein = 50 MM. 1000 MM = 20 Scheine = fühlbarer Stapel.

---

## KERN-ZAHLENTABELLE (Balancing-Startwerte v0.1)

Referenzmatch: 4 Spieler, 3 Runden + Finale, ~24 Fragen, Ziel-Endstand des
Siegers ≈ 8.000–12.000 MM (fünfstellig nur bei Jackpot-Glück → besonderer Moment).

| Parameter | Startwert | Anmerkung |
|---|---|---|
| Frage EASY | 100 MM | Aufwärmen, Runde 1 |
| Frage MEDIUM | 250 MM | Brot-und-Butter |
| Frage HARD | 500 MM | ab Runde 2 |
| Frage ULTRAHARD | 1.000 MM | max. 2× pro Match, angekündigt |
| JACKPOT-Frage | 2.000 MM + Topf | 1× pro Match, Topf aus Fehlbuzz-Strafen (I-04) |
| Speed-Bonus max. | +50 % des Fragenwerts | linear fallend über Antwortzeit (I-02) |
| Streak-Multiplikator | ×1,5 ab 3 / ×2 ab 5 / Cap ×2 | Streak bricht bei falsch ODER Pass (I-03) |
| Fehlbuzz-Strafe | −50 % des Fragenwerts | fließt in den Jackpot-Topf (I-04) |
| Dispo-Limit (Pleite-Schutz) | −500 MM hart | darunter nur noch „Pfandflaschen-Modus“ (I-05) |
| Tipp kaufen (1 Antwort weg) | 25 % des Fragenwerts | (I-10) |
| 50/50-Joker | 40 % des Fragenwerts | (I-10) |
| Rad neu drehen | 200 MM flat | (I-11) |
| Wett-Runde Einsatz | 10–50 % des Kontostands | Quoten 1,5–5,0 (I-06) |
| Zins-Runde | Führender +10 %, Letzter +20 % „Grundeinkommen“ auf Median | (I-08) |
| Finale-Fragenwert | `max(500, aufrunden(1,25 × Rückstand₄ / Q, 50))` | Q = Anzahl Finalfragen (I-21) |
| Trost-Money letzter Platz | 300 MM Match-seitig vor Finale | „Mitleids-Banane“ (I-22) |
| Umrechnung Match→All-Time | Alle: Endstand/10; Sieger: ×1,5; mind. 50 AT | (I-17) |
| Shop-Spanne | 500 – 25.000 AT | Sticker bis Legendär-Skin (I-18) |
| Season-Länge | 3 Monate, Soft-Reset auf Wurzel (I-19) | Prestige-Rahmen bleibt |

---

## (a) MATCH-ÖKONOMIE

### I-01 · Vier-Stufen-Grundwerte mit Runden-Progression — Aufwand S · **P1**
EASY 100 / MEDIUM 250 / HARD 500 / ULTRAHARD 1.000. Runde 1 zieht nur aus
EASY+MEDIUM, Runde 2 aus MEDIUM+HARD, Runde 3 aus HARD+ULTRAHARD. Effekt:
Frühe Führung ist wenig wert (max. ~1.750 MM Vorsprung nach R1), späte Runden
entscheiden — eingebauter Spannungsbogen ohne Extra-Regeln. ULTRAHARD wird
IMMER mit Fanfare angekündigt („DIE 1000er!!“), max. 2× pro Match, damit sie
Event bleibt.

### I-02 · Speed-Bonus als abgeknickte Gerade (kein Hektik-Exploit) — Aufwand S · **P1**
Bonus = 50 % des Fragenwerts, wenn Antwort in den ersten 20 % der Zeit kommt;
danach linear fallend auf 0 % bei Zeitablauf. Formel bei Antwortzeit t,
Limit T: `bonus = wert × 0,5 × clamp((T − t) / (0,8 × T), 0, 1)`.
Warum Knick statt purer Linearität: Die ersten Sekunden sind Lese-Zeit —
wer blind sofort tippt, soll KEINEN Vorteil gegenüber schnellem Lesen+Denken
haben. Startwerte: T = 15 s (EASY/MEDIUM), 20 s (HARD/ULTRAHARD).

### I-03 · Streak-Multiplikator mit sichtbarer Lunte — Aufwand M · **P1**
Ab 3 richtigen in Folge ×1,5, ab 5 ×2,0, hart gecappt bei ×2 (kein ×3 —
sonst zieht ein Serien-Wisser uneinholbar davon, siehe Leitprinzip 2).
Multiplikator gilt auf Grundwert + Speed-Bonus. Streak bricht bei falscher
Antwort UND bei Pass (sonst passt man taktisch schwere Fragen weg).
UI: Am Podium brennt eine Zündschnur zur „Streak-Banane“ — alle SEHEN, wer
heiß läuft, und Buzzer-Runden werden automatisch zur Jagd auf den Streaker.

### I-04 · Fehlbuzz-Schulden, die den Jackpot füttern — Aufwand M · **P1**
Falsch gebuzzert = −50 % des Fragenwerts. ABER: Jede Strafe wandert sichtbar
in ein Jackpot-Glas in der Bühnenmitte. 1× pro Match (Runde 3) kommt die
JACKPOT-Frage: 2.000 MM Grundwert + kompletter Glas-Inhalt. So wird jede
Strafe zu einem Versprechen („das Glas ist schon bei 1.400!“) statt purem
Frust — und wilde Buzzer-Spieler finanzieren das Comeback (oft ihr eigenes).

### I-05 · Pleite-Schutz: Dispo bei −500, dann Pfandflaschen-Modus — Aufwand M · **P2**
Konto kann bis −500 MM fallen (Schulden erzeugen Galgenhumor, siehe I-16),
tiefer NIE. Wer am Dispo-Limit klebt, bekommt bei den nächsten Fragen den
„Pfandflaschen-Modus“: keine Strafen mehr möglich, aber Gewinne nur zu 75 %
— Comeback bleibt möglich, Risiko-Kamikaze („mir doch egal, ich bin eh im
Minus“) wird gebremst. Schulden werden vor dem Finale automatisch auf 0
erlassen (Privatinsolvenz mit Affen-Anwalt-Einblendung), damit das Finale
für alle zählt.

### I-06 · Wett-Runde „Der Affenmarkt“ (auf DICH oder ANDERE wetten) — Aufwand L · **P1**
Einmal pro Match (Ende Runde 2): Jeder setzt verdeckt 10–50 % seines
Kontostands darauf, WER die nächste Themen-Frage richtig beantwortet —
sich selbst eingeschlossen. Quoten aus der bisherigen Kategorie-Trefferquote:
Favorit 1,5×, Mittelfeld 2,5×, Underdog 5,0×. Kern-Drama: Die App zeigt vor
der Auflösung, WER AUF WEN gesetzt hat („Lisa wettet GEGEN sich selbst?!“).
Underdog-Hebel eingebaut: Auf den Letzten zu setzen (oder als Letzter auf
sich selbst) hat die fetteste Quote.

### I-07 · Steal-Frage „Affengriff“ — Aufwand M · **P2**
2× pro Match: Bei einer Steal-Frage gewinnt der Richtige nicht Money von der
Bank, sondern KLAUT den Fragenwert vom aktuell Führenden (Cap: max. 25 % von
dessen Kontostand, damit ein einziger Steal keine Runde entwertet). Der
Führende darf zur Verteidigung mitantworten: Ist ER richtig, verdoppelt er
stattdessen den Fragenwert aus der Bank. Macht Führung zur Zielscheibe —
bewusstes Gegengewicht zur Zins-Runde (I-08).

### I-08 · Zins-Runde „Der Kapitalismus-Gong“ (Drama + Gegengewicht) — Aufwand S · **P2**
Einmal pro Match ertönt der Gong: Der Führende bekommt 10 % Zins auf seinen
Kontostand (reich wird reicher — BEWUSST unfair, die App kommentiert es
hämisch: „So funktioniert die Welt, Leute“). GLEICHZEITIG bekommt der Letzte
„Grundeinkommen“: 20 % des Median-Kontostands. Bei den Startwerten gleicht
das Grundeinkommen den Zins fast aus, solange der Abstand < ~2× Median ist —
der Gong fühlt sich skandalös an, verschiebt aber netto wenig. Genau richtig.

### I-09 · Alles-oder-nichts: „Die Bananenschale“ — Aufwand M · **P2**
Vor der letzten Frage jeder Runde (nicht Finale) darf jeder optional seinen
GESAMTEN Rundengewinn (nicht Kontostand!) auf die Frage setzen: richtig =
verdoppelt, falsch = Rundengewinn weg. Nur Rundengewinn als Einsatz hält den
Schaden begrenzt (max. eine Runde Arbeit) und macht den Move für Zurückliegende
attraktiver als für Führende — Underdog-Mechanik ohne Extra-Regel.

### I-10 · Money-Sinks: Tipps & Joker mit Prozent-Preisen — Aufwand M · **P1**
Kaufbar VOR dem Antworten, Preis skaliert mit Fragenwert (Flat-Preise würden
bei 1000er-Fragen lächerlich billig): Tipp „eine falsche Antwort fliegt raus“
= 25 % des Fragenwerts; 50/50 = 40 %; „Affenflüstern“ (Sekundenblick auf die
laufende Antwort-Tendenz der Mitspieler) = 30 %. Max. 1 Kauf pro Frage.
Warum das wichtig ist: Sinks entziehen dem Match Money → Endstände bleiben
in der Ziel-Spanne, UND jeder Kauf ist öffentlich sichtbar („Tom kauft sich
schon wieder frei!“) = Social-Content.

### I-11 · Rad-Neudreh & Kategorie-Veto — Aufwand S · **P3**
Wenn ein Glücksrad/Themenrad die Kategorie bestimmt: Neudreh kostet 200 MM
flat (flat, weil unabhängig vom Fragenwert — es ist eine Komfort-Ausgabe).
Zusätzlich 1× pro Match ein kostenloses „Veto“ für den letztplatzierten
Spieler — der Underdog darf einmal die Kategorie des Führenden umwerfen.

### I-12 · Team-Topf-Runde „Die Affenbande“ — Aufwand L · **P3**
Eine Runde in 2er-Teams (Zufallslos, bevorzugt Erster+Letzter zusammen):
Gewinne laufen in einen Team-Topf, der am Rundenende 50/50 geteilt wird.
Twist: Vor der Teilung darf jeder verdeckt „GIER“ drücken — drückt nur einer,
kriegt er 70/30; drücken beide, verbrennt der Topf zu 50 % (Gefangenendilemma
als Rundenfinale). Zahlen so gewählt, dass Kooperation erwartungswert-optimal
ist, Gier aber verführerisch bleibt.

---

## (b) INSZENIERUNG von Money (das physische Gefühl)

### I-13 · Scheine fliegen EINZELN, Stückelung 50 MM — Aufwand M · **P1**
Jeder Gewinn regnet als einzelne 50er-Scheine aufs Podium-Konto (250-MM-Gewinn
= 5 Scheine, ~0,8 s Gesamtanimation; ab 20 Scheinen Bündel-Animation, damit
Jackpots nicht 40 s dauern). Mit Kassen-Kaching pro Schein, Tonhöhe steigt
pro Schein leicht an (Slot-Machine-Psychologie). Money muss man HÖREN.

### I-14 · Stapel-Höhe = Kontostand am Podium — Aufwand M · **P1**
Jeder Spieler hat am Podium einen physischen Geldstapel; Höhe linear zum
Kontostand (Skala auto-normiert auf den Führenden). Schulden (I-05) = Loch
im Podium mit herausschauender Ratte. Der Blick über die Stapel ersetzt
jede Tabelle — Zuschauer checken den Spielstand in 0,5 Sekunden.

### I-15 · Klau = Affenhand quer über den Screen — Aufwand M · **P2**
Bei Steal (I-07) und Wett-Gewinnen gegen andere greift eine haarige Affenhand
sichtbar in den Stapel des Opfers und trägt die Scheine rüber — mit kurzem
Tauziehen, wenn der Bestohlene die Verteidigungsfrage knapp verlor. Klauen
muss sich wie Klauen ANFÜHLEN, nicht wie eine Zahlbuchung.

### I-16 · Pleite-Inszenierung: leerer Beutel, Motte, Anwalt — Aufwand S · **P2**
Kontostand ≤ 0: Der Stapel wird zum umgekippten Beutel, eine Motte fliegt
raus (Loop). Beim Schuldenerlass vor dem Finale (I-05) tritt der
Affen-Anwalt auf und stempelt „PRIVATINSOLVENZ — VIEL GLÜCK“. Scheitern
wird zur Comedy-Bühne statt zur stillen Demütigung — zentral für Anti-Frust.

---

## (c) ALL-TIME-ÖKONOMIE

### I-17 · Umrechnung Match→All-Time: alle anteilig + Sieger-Prämie — Aufwand S · **P1**
NICHT nur der Sieger (sonst spielen Schwächere nach 3 Matches nicht mehr mit):
Jeder erhält `Match-Endstand / 10` als All-Time-Money (AT), mindestens 50 AT.
Sieger: ×1,5 auf seinen Betrag. Beispiel Referenzmatch: Sieger 10.000 MM →
1.500 AT; Letzter 2.000 MM → 200 AT. Erste-Male-Boni on top: erste
ULTRAHARD richtig +100 AT, erster Match-Sieg überhaupt +500 AT, erste
gewonnene Underdog-Wette (Quote ≥ 5) +250 AT — einmalige Meilensteine,
keine Farm-Quelle.

### I-18 · Shop-Preisgefüge in 5 Stufen — Aufwand M · **P1**
Faustregel: 1 Abend (2–3 Matches) ≈ 2.000–4.000 AT Einkommen.
Stufe 1 „Kleinkram“ (Buzzer-Sounds, Sticker): 500–1.000 AT — jede Session
kann man sich WAS leisten. Stufe 2 (Podium-Deko, Konfetti-Farben):
2.000–4.000 AT. Stufe 3 (Avatar-Outfits): 5.000–8.000 AT. Stufe 4
(animierte Sieges-Taunts, Klau-Handschuh-Skins für I-15): 10.000–15.000 AT.
Stufe 5 „Legendär“ (goldener Geldstapel-Skin, eigener Einzugs-Jingle):
25.000 AT — das Saisonziel für Vielspieler. Alles rein kosmetisch
(Leitprinzip 3).

### I-19 · Inflation-Schutz: Season-Soft-Reset auf die Wurzel + Prestige — Aufwand L · **P2**
Alle 3 Monate Season-Ende: All-Time-Konto wird NICHT genullt, sondern auf
`100 × √(AT / 100)` gesetzt (10.000 → 1.000; 40.000 → 2.000) — Vielspieler
behalten Vorsprung, aber komprimiert; Neueinsteiger sind nie hoffnungslos
hinten. Gekaufte Items bleiben IMMER. Wer die Season in den Top 10 % des
Freundeskreises beendet, bekommt einen Prestige-Rahmen (☆→☆☆→☆☆☆) um den
Avatar — Status wird in Prestige gespeichert, nicht in gehorteter Währung.

### I-20 · Bestenlisten-Triple: Reichste / Skill / Clutch — Aufwand M · **P2**
Drei Boards, damit nicht nur der Vielspieler glänzt: (1) All-Time-Money
(Fleiß), (2) Kategorie-Skill: Trefferquote je Kategorie, gewertet ab 30
beantworteten Fragen (der „Sport-Gott“ der Gruppe ist ausweisbar), (3)
Clutch-Rating: Win-Rate NUR aus Matches, in denen man vor dem Finale nicht
Erster war (der offizielle Comeback-König). Standard-Ansicht: Freundesgruppe;
global nur optional (globale Boards sind bei Party-Apps Bot-/Grind-Futter).

---

## (d) ANTI-FRUST-REGELN

### I-21 · Finale-Formel: Platz 4 kann IMMER noch gewinnen — Aufwand M · **P1**
Kernstück. Vor dem Finale berechnet die App den Rückstand des Letzten:
`G = Konto₁ − Konto₄`. Bei Q Finalfragen (Standard Q = 5) gilt pro Frage:

`W_final = max(500, aufrunden(1,25 × G / Q, auf 50er))`

Damit gilt: Gewinnt der Letzte alle Q Fragen und der Führende keine, holt er
125 % des Rückstands auf → Sieg möglich, aber nur bei perfektem Lauf gegen
einen kalten Führenden — die Führung ist weiter klar wertvoll (sie zwingt
den Letzten zur Perfektion, umgekehrt reicht dem Führenden EINE richtige
Antwort, um die Rechnung des Letzten zu sprengen). Beispiel: G = 4.000,
Q = 5 → W_final = 1.000 MM/Frage. Zusatzregel: Im Finale keine Streaks und
kein Speed-Bonus (reiner Grundwert), damit die Formel exakt hält und das
Finale als „neues Spiel“ lesbar ist. Optional-Knopf in den Match-Settings:
Faktor 1,25 auf 1,0 („streng“) oder 1,5 („Chaos“) stellbar.

### I-22 · Trost-Money „Mitleids-Banane“ + Fast-richtig-Almosen — Aufwand S · **P1**
Vor dem Finale bekommt der Letzte einmalig 300 MM, überreicht von einem
mitleidig schauenden Affen (Inszenierung macht aus dem Almosen einen
Lacher, nicht eine Bloßstellung). Zusätzlich während des Matches: Wer eine
Frage als EINZIGER falsch hat, bekommt 25 MM „Applaus fürs Mitmachen“ —
mikroökonomisch irrelevant (halber Schein), psychologisch: der Ton der App
ist nie „du kriegst nichts“, sondern immer „hier, wenigstens etwas“.

### I-23 · Rubberband über Fragenauswahl, nicht über Geld — Aufwand L · **P3**
Unsichtbare Anti-Frust-Schraube: Liegt ein Spieler > 60 % hinter dem Median,
erhöht die Fragenauswahl die Wahrscheinlichkeit SEINER stärksten Kategorie
(aus All-Time-Skill-Daten, I-20) um +15 Prozentpunkte für die nächsten 3
Fragen. Kein Geld-Geschenk, keine sichtbare Bevorzugung — der Underdog
bekommt nur öfter die Bühne, liefern muss er selbst. (Transparenz-Hinweis
in den Settings, abschaltbar für „Hardcore“-Lobbys.)

### I-24 · „Letzte Chance“-Anzeige statt stiller Hoffnungslosigkeit — Aufwand S · **P2**
Ab Runde 3 zeigt die App jedem Spieler privat seinen Pfad zum Sieg („Du
brauchst: 3 von 5 Finalfragen + 1× HARD vorher“). Sobald ein Sieg rechnerisch
unmöglich WÄRE, greift stattdessen ein Neben-Ziel mit AT-Bonus („Schlag
wenigstens Tom: +150 AT“). Niemand sitzt die letzten 10 Minuten ohne
erreichbares Ziel ab — der größte Frustkiller in Punkte-Partyspielen.

---

## Balancing-Anhang: Beispiel-Matchverlauf (Probe aufs Exempel)

4 Spieler, Trefferquoten 70/55/45/35 %, 24 Fragen + Finale (Q = 5):
Erwartete Stände vor Finale ≈ 6.800 / 4.900 / 3.600 / 2.700 MM (inkl.
Streaks, einer Wett-Runde, Zins-Gong, ~800 MM Sinks-Ausgaben gesamt).
G = 4.100 → W_final = aufrunden(1,25 × 4.100 / 5, 50) = 1.050 MM/Frage.
Platz 4 mit 4/5 im Finale + Führender 1/5: 2.700 + 4.200 = 6.900 vs.
6.800 + 1.050 = 7.850 → reicht NICHT; mit 5/5 vs. 1/5: 7.950 vs. 7.850 →
Sieg um 100 MM. Genau die gewünschte Schärfe: möglich, episch, selten.

## Offene Fragen an andere Agenten

- An Runden-Format-Agent: Welche Runde trägt die Wett-Runde (I-06) am besten
  — eigene Runde oder Einschub?
- An UI/Podium-Agent: Stapel-Normierung (I-14) bei > 6 Spielern prüfen.
- An Shop/Meta-Agent: Stufe-5-Preis (25.000 AT) gegen geplante
  Season-Einkommenskurve gegenrechnen.
