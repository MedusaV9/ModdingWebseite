# IDEEN-V6 — konsolidierte Ideensammlung für Version 6.0

Stand: 10. August 2026 · Branch `cursor/gooby-godot-loop-2-2c10`

Konsolidiert aus den beiden Sammler-Dokumenten der Vorgänger-Flotte
(`V6-IDEEN/content-dlc.md` — Lens „Content & DLC", 34 Ideen;
`V6-IDEEN/tiefe-bindung.md` — Lens „Tiefe, Bindung & Systeme", 36 Ideen)
plus eigener neuer Ideen aus der frischen Codebasis-Sichtung (10.8.).

**Eval-Anker (EVAL-2026-08/A-gameplay):** Content-Menge 8,5 ·
Progression 5,5 · Multiplayer 4,5. Kernsatz: „Das Spiel braucht keine
Minispiele 39–45. Es braucht stärkere Gründe, die vorhandenen 38 erneut
zu spielen." → V6 addiert deshalb KEINE Minispiele, sondern Sammel-,
Museums- und Beziehungs-Content, der die Welt täglich verändert.

Aufwand: **S** = Daten/Strings + 1 kleiner Screen · **M** = 1–2 Szenen,
1 Slice-Erweiterung · **L** = mehrere Szenen, neuer Slice, Asset-Batch ·
**XL** = eigene Welt/DLC. Score = Impact aufs Eval-Loch pro Aufwand.

---

## 1) Die priorisierte Gesamtliste (36 Ideen)

### Säule A — Naturkunde & Sammeln (das ACNH-Rückgrat)

| # | Idee | Quelle | Aufwand | Score |
|---|---|---|:--:|:--:|
| A1 | **Insekten-Album + Käscher**: 12–40 Arten in Garten/Stadt/Ranch, Vorkommen nach Ort/Tageszeit/Wetter, Erstfang-Witzzeile | content-dlc B1 | L | 9 |
| A2 | **Fossilien & Grabungsstellen**: täglich deterministische Riss-Stellen, Fossilteile in Sets (Skelette), erst komplette Sets = Exponat | content-dlc B2 | M | 8,5 |
| A3 | **GOOBYSEUM**: kuratierbares Museum mit Flügeln (Fische/Insekten/Fossilien), jede Spende als sichtbares Exponat, Kurator Prof. Eule von Vitrine, Meilenstein-Sonderausstellungen | content-dlc B3 | L | 9,5 |
| A4 | **Angeln 2.0**: Gewässer-Typen, Schatten-Größen, Saisonfische, 8–10 Legenden-Fische | content-dlc B4 | M | 8,5 |
| A5 | **Sternwarte + Sternbild-Album** auf dem Ranch-Plateau (Nacht-Content) | content-dlc B5 | M | 7,5 |
| A6 | **Blumen-Zucht mit Kreuzungen** (Genetik light, deterministischer RNG) | content-dlc B6 | M | 8 |
| A7 | **Goobypedia** — In-Game-Lexikon, das sich selbst schreibt (Auto-Einträge aus Katalogen) | content-dlc H4 | M | 8 |
| A8 | **NEU (Codebasis-Sichtung): Naturkunde-Tagesfenster im Quest-Blatt** — „Heute fliegt: …" als kleiner Info-Chip, gespeist aus den deterministischen Spawn-Fenstern (Wetter-/Uhr-Hooks existieren in `SoulWetter`/`Clock`) | neu | S | 8 |

### Säule B — Progression & roter Faden (die 5,5 direkt anheben)

| # | Idee | Quelle | Aufwand | Score |
|---|---|---|:--:|:--:|
| B1 | **Story-Kampagne „Goobys Jahr" Staffel 1** (8–16 Kapitel, Cutscene-Pipeline existiert, jede Kapitel-Belohnung verändert die Welt) | beide Lenses (D2 / Idee 1) | XL | 10 |
| B2 | **Nordstern-HUD**: `WhatsNextAdvisor` wird sichtbarer Meta-Kompass — genau EIN nächster Schritt, in Goobys Stimme | tiefe-bindung 3 | M | 8 |
| B3 | **Freischalt-Matrix „Früh zeigen, spät besitzen"** — Ranch-Schnupperkapitel ab Level 5–6 | tiefe-bindung 2 | M | 9 |
| B4 | **Abschluss 2.0**: Basis/Zusammen/DLC/Meister als getrennte Medaillen (Offline-100 % wird möglich) | tiefe-bindung 6 | M | 9 |
| B5 | **Arcade-Reihen-Meisterschaften** mit reiheneigenen Belohnungen (Blaupausen, Fahrzeugteile, Rezepte …) | beide (G1 / 18) | L | 9 |
| B6 | **Warteziel-Redesign „Warten ODER Anpacken"** — jede 24/48-h-Sperre bekommt einen aktiven Pfad | tiefe-bindung 28 | M | 9 |
| B7 | **Level-Aufstieg als Zeremonie** mit konkretem benannten Unlock pro Level | tiefe-bindung 4 | M | 8 |
| B8 | **Trophäen-Regal & Meilenstein-Möbel** — Leistung wird Wohnungs-Inhalt, nie kaufbar | content-dlc E4 | S | 8 |
| B9 | **NEU: Museums-Meilensteine zahlen Trophäen-Möbel** — verbindet A3+B8 zu einer Schiene (Spenden-Zähler → Pokal ins Hauslager, `StorageLogic`-Muster existiert) | neu | S | 8,5 |

### Säule C — Bindung & Beziehung (Gooby wächst)

| # | Idee | Quelle | Aufwand | Score |
|---|---|---|:--:|:--:|
| C1 | **Vertrauens-Band Bond-Level 1–10** (Huckepack, gemeinsames Kochen, Geheimnisse, „bester Freund"-Zeremonie) | tiefe-bindung 11 | L | 10 |
| C2 | **Gooby-Lebensphasen** Nestling→Wirbelwind→Teenie→Gefährte über reale Wochen | tiefe-bindung 7 | XL | 10 |
| C3 | **Erinnerungsalbum „Unser Buch"** — automatisch wachsendes Tagebuch aus `SoulMemories` | tiefe-bindung 8 | L | 9 |
| C4 | **„Weißt du noch?"-Rückkehrmomente** nach Pausen: warmer Wiedereinstieg statt Schuldgefühl, Verfall gedeckelt + erklärt | tiefe-bindung 36 | S | 8 |
| C5 | **Geheimnisse & kleine Versprechen** (ab Bond 6, Nachhall statt Strafe) | tiefe-bindung 14 | M | 9 |
| C6 | **Pflege-Gewohnheiten & abnehmende Wirkung** — jeder Gooby „spielt sich anders" | tiefe-bindung 16 | M | 8 |
| C7 | **Gooby-Träume & Traumtagebuch** (Schlafphase wird Bindungszeit) | tiefe-bindung 10 | M | 7 |
| C8 | **NEU: Erstfang-/Erstspenden-Momente in Goobys Stimme** — jede neue Art bekommt EINE Witz-Zeile (DE+EN), Gooby feiert mit (`SoulService`-Momente existieren) | neu | S | 8 |

### Säule D — Nachbarn, NPCs & Feste

| # | Idee | Quelle | Aufwand | Score |
|---|---|---|:--:|:--:|
| D1 | **Nachbarschafts-Herzen + Geschenke** (12 Nachbarn nach Ranch-NPC-Muster) | content-dlc D1 | L | 9 |
| D2 | **Jahresfest-Kalender** (Laternenfest, Erntedank, Winterlichter, Silvester …) | content-dlc C1 | L | 9 |
| D3 | **Silvester-Feuerwerk mit Echtzeit-Countdown** (Clock-injiziert, Jahres-Sticker) | content-dlc C2 | S | 8,5 |
| D4 | **Echte Jahreszeiten im Basisspiel** (Saison-Service, Material-Tints, Saison-Fenster) | content-dlc C3 | L | 8,5 |
| D5 | **Brieffreundin „Oma Weitweg"** — Briefe + 30 Briefmarken als Mini-Album | content-dlc D3 | M | 8 |
| D6 | **Besucher-System: NPCs klingeln** (Random-Event-Muster existiert) | tiefe-bindung 27 | L | 8 |
| D7 | **NEU: Kurator als ERSTER echter Stadt-NPC mit Beziehung** — Prof. Eule von Vitrine kommentiert jede Spende, merkt sich Meilensteine; Blaupause für D1 | neu | M | 8 |

### Säule E — Welt-DLCs (XL-Flaggschiffe, je Version eins)

| # | Idee | Quelle | Aufwand | Score |
|---|---|---|:--:|:--:|
| E1 | **Tiefsee-DLC „GOOBY BLUBB"** (Unterwasserwelt + Aquarium-Haus) | content-dlc A1 | XL | 9,5 |
| E2 | **Villa-Ausbau: Keller/2. Etage/Balkon** + Hobbyräume (Töpferei/Fotostudio) | content-dlc E1/E2 | L/XL | 9 |
| E3 | **Café „Herzknuffel"** — Beziehungs-Spiel mit Gäste-Kapiteln | content-dlc A3 | XL | 8,5 |
| E4 | **Ski-Resort „Funkelalm"** (Winterseite des Bergmassivs) | content-dlc A2 | XL | 8,5 |
| E5 | **Insel-Resort „Kokoswelle"** — Urlaub wird begehbar | content-dlc A4 | L/XL | 8 |

### Säule F — Multiplayer async-first

| # | Idee | Quelle | Aufwand | Score |
|---|---|---|:--:|:--:|
| F1 | **Tausch-Post** (Duplikate asynchron tauschen, Escrow) | content-dlc F2 | M | 8,5 |
| F2 | **Foto-Wettbewerb „Blende & Blubber"** (NPC-Jury offline) | content-dlc F1 | M | 8,5 |
| F3 | **Asynchrone Besuche mit Gästebuch** | tiefe-bindung 24 | L | 9 |
| F4 | **Server-Wahl-UX „Verbinden in 60 Sekunden"** | tiefe-bindung 22 | L | 9 |

---

## 2) Der V6.0-Schnitt: „DAS NATURKUNDE-UPDATE"

Roter Faden (aus content-dlc §2 übernommen und verdichtet): **Sammeln →
Ausstellen → Gefeiert werden.** Die Welt bekommt täglich wechselnde
Naturkunde-Funde (Insekten nach Uhr+Wetter, Fossilien nach Tages-Seed),
das GOOBYSEUM macht die Sammlung als begehbaren Ort sichtbar, und
Nordstern/Rückkehr-Momente hängen die neue Schiene in den Alltag.

Gewählt (Content + Progression + Polish, jede Idee vollständig):

1. **A1 light** — Insekten-Sammlung: 12 Arten, Fenster nach Ort/
   Tageszeit/Wetter (deterministisch, `SoulWetter`-Adapter), Käscher-
   Gefühl im Garten (Insekten sichtbar, Antippen = Fang-Moment).
2. **A2** — Fossilien: 3 Skelette × 4 Teile, täglich 3 deterministische
   Grabungsstellen im Garten (Spot-Muster von `GardenWorld` existiert).
3. **A3** — GOOBYSEUM als 13. Stadt-Ort: 3 Flügel (Fische/Insekten/
   Fossilien), Spenden aus echten Sammlungs-Slices, Exponate SICHTBAR
   auf Podesten, Kurator-Dialog.
4. **B9** — Museums-Meilensteine (5/12/24 Exponate) → Münzen + einzig-
   artige Trophäen-Möbel ins Hauslager (nie kaufbar).
5. **D7** — Prof. Eule von Vitrine: Spenden-Kommentare mit Wissens-Gag,
   DE+EN.
6. **C8** — Erstfang-Witzzeilen für alle 24 neuen Arten/Teile (DE+EN)
   + Fang-/Grabungs-Feier (Reduced-Motion-fair).
7. **B2 light** — Nordstern: `WhatsNextAdvisor` lernt Naturkunde
   (spendbare Funde → Museums-Hinweis; heute fliegende neue Art →
   Fang-Hinweis).
8. **A8** — „Heute fliegt"-Tagesfenster als Advisor-Hinweis.
9. **C4** — Rückkehr-Momente nach ≥3 Tagen: warme Begrüßung, was Gooby
   allein erlebt hat, Verfall-Deckel sichtbar erklärt.
10. **B8/B9-Verzahnung** — neue Sticker + Erfolge für die Naturkunde-
    Schiene (Erstfang, 6/12 Arten, erstes Skelett, Museums-Meilensteine).

**Bewusst NICHT in 6.0** (Top-Kandidaten für 7.0+): B1 Kampagne (XL —
braucht eigene Welle mit Cutscene-Batch), C1 Bond-Level (L — verdient
eine eigene Beziehungs-Version), E1 Tiefsee (XL-Flaggschiff, docken die
Museums-Funde später an), D2 Feste + D4 Jahreszeiten (Kalender-Version),
B5 Arcade-Meisterschaften, F1–F4 (Multiplayer-Version nach Server-Frage).

## 3) Versions-Ausblick 7.0–15.0 (fortgeschrieben)

| Version | Flaggschiff | Begleit-Säule |
|---|---|---|
| 7.0 | B1 Kampagne „Goobys Jahr" Staffel 1 | B2 Nordstern voll, B7 Level-Zeremonie, B3 Freischalt-Rework |
| 8.0 | C1 Bond-Level + C3 Erinnerungsalbum | C5 Versprechen, C6 Gewohnheiten, C4-Ausbau |
| 9.0 | E2 Villa-Ausbau + Hobbyräume | B8 Trophäen voll, A6 Blumen-Zucht |
| 10.0 | D2 Feste + D4 Jahreszeiten | D3 Silvester, A5 Sternwarte, A8-Ausbau |
| 11.0 | E1 Tiefsee „GOOBY BLUBB" | A4 Angeln 2.0, Museums-Sonderflügel |
| 12.0 | D1 Nachbarn + D6 Besucher | D5 Brieffreundin, F2 Foto-Jury |
| 13.0 | F3/F4 Multiplayer-Rework | F1 Tausch-Post, B4 Abschluss 2.0 |
| 14.0 | E3 Café „Herzknuffel" | C7 Träume, B5 Meisterschaften |
| 15.0 | C2 Lebensphasen + Generationen (tiefe-bindung 32) | E4/E5 Resort-Welt |
