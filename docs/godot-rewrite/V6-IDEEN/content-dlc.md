# V6-IDEEN — Lens „CONTENT & DLC" (Ideen-Agent 1/2 für Version 6.0)

Stand: 8. August 2026 · Branch `cursor/gooby-godot-loop-2-d1d8`
Quellen: `USER-WISHES.md`, `EVAL-2026-08/A-gameplay.md`, `STATUS.md`,
`UserFeedback.md`, `ROADMAP-W20.md`, `DLC-GOO-UND-BYE.md`, `DLC-MCGOOBY.md`.

**Leitfrage der Lens:** Was gibt dem Spiel **nach Stunde 10 noch Monate an
Zielen** — als Content und DLC-große Inhalte, nicht als weitere Zähler?

## 0) Ist-Anker (verifiziert, damit die Ideen andocken statt schweben)

- Vorhanden: 38 Minispiele (6 Arcade-Reihen), 144 Sticker, 44 Erfolge,
  24 Tagesquests, 43 Ranch-Quests, 4 Sammlungssets (Fische/Gemüse/
  Sehenswürdigkeiten/Leckereien), 12 Stadtorte, 9 Reiseziele, Funkelpark,
  3 DLCs (Ranch/Goo und Bye/McGooby), 207 Möbel, 92 Cosmetics, Garten 2.0,
  Wochenmarkt, Werkstatt-Crafting, Post/Mail, Fotomodus, Soul-System.
- Eval-Scores (A-gameplay): **Content-Menge 8,5** · **Progression 5,5** ·
  **Multiplayer 4,5**. Kernsatz der Eval: „Das Spiel braucht derzeit keine
  Minispiele Nummer 39–45. Es braucht stärkere Gründe, die vorhandenen 38
  erneut zu spielen."
- Multiplayer-Realität: Client/Server sind breit implementiert, aber der
  Default zeigt auf `127.0.0.1:8765`. Ausgeliefert erlebbar sind daher vor
  allem **asynchrone** Formen (Post/Mail, Outbox, Geister) — neue
  MP-Content-Ideen setzen bewusst dort an.
- Technik-Wiederverwendung, die XL-Ideen billiger macht: Ranch-Open-World
  (Zonen, `welt_aufbau_takt`-Time-Slicing, Entdecker-Karte), SceneRouter,
  Save-v5-Slices, ContentRegistry/Packs, Minigame-Framework, Herzen-/
  NPC-Muster der Ranch, Overlay-Dirigent.

**Was diese Lens bewusst NICHT vorschlägt:** isolierte neue Minispiele
(Eval-Empfehlung) und einen vierten Tycoon-DLC, bevor die beworbenen
Goo-und-Bye-Mitarbeiter und der McGooby-Koop ehrlich geliefert sind
(Eval-Finding 7). Jede Idee unten stopft ein benanntes Langzeit-Loch.

---

## 1) Die 34 Ideen

Aufwands-Skala (in Systemen, nicht Kalenderzeit):
**S** = Daten/Strings + 1 kleiner Screen · **M** = 1–2 Szenen/Screens,
1 Save-Slice-Erweiterung, überschaubare Assets · **L** = mehrere Szenen,
neuer Save-Slice, eigener Asset-Batch, neue Kataloge ·
**XL** = eigene Welt/DLC: neue Szenen-Familie, mehrere Slices, großer
Asset-Batch, eigener Quest-/NPC-/Shop-Katalog, DLC-Hub-Eintrag.

### Kategorie A — Welt-DLCs (die XL-Flaggschiffe)

#### A1. Tiefsee-DLC „GOOBY BLUBB" (Unterwasserwelt)

- **Konzept:** Vor der Muschelbucht der Ranch öffnet ein U-Boot-Steg den Weg
  in eine begehbare Unterwasserwelt: Korallengarten, Seegraswiese,
  Wrack-Schlucht, Leucht-Grotte — gebaut auf der Ranch-Open-World-Tech
  (Zonen + Time-Slicing + Entdecker-Karten-Muster). Gooby taucht im
  Blubberhelm (Sauerstoff = sanfter Timer statt Fail-State), sammelt
  Meeres-Funde und trifft fünf Meeres-Gooby-Freunde (Quallen-Oma, schüchterner
  Oktopus-Junge, Seepferd-Postbotin …) mit eigenen Herz-Leveln und
  Mini-Geschichten. Zuhause entsteht das **Aquarium-Haus**: ein neuer Raumtyp,
  in dem gefangene Fische und Tiefsee-Funde in bebaubaren Becken sichtbar
  schwimmen — das Aquarium ist zugleich Besuchsziel für Freunde.
- **Spielziel-Beitrag:** DAS neue „Wohin nach Stunde 10?"-Ziel: eine zweite
  erkundbare Welt mit eigener Karte, eigenen Beziehungen und einer Sammlung,
  die man ZUHAUSE ausstellt (Belohnung verändert die Welt — Eval-Kernkritik an
  Progression 5,5). Füttert Angeln 2.0 (B4), Museum (B3) und
  Sticker/Sammlungen; Aquarium-Besuche geben dem bestehenden Besuchs-System
  (Multiplayer 4,5) endlich einen Vorzeige-Grund.
- **Aufwand:** **XL** — 4–6 Unterwasser-Zonen-Szenen + Aquarium-Raumszene,
  Tauch-Controller (Schwimm-Variante des Bewegungs-Codes),
  Unterwasser-Postprocessing (Caustics/Fog/Blau-Grading auf dem vorhandenen
  Effekt-Stack), neuer Save-Slice `tiefsee` + Erweiterung `home.aquarium`,
  ~40 Assets (Korallen, Fische, Wrack, Helm), 1 NPC-Katalog, 1 Quest-Katalog
  (~15 Quests), 12–15 Sticker, DLC-Hub-Karte. Keine neuen Minispiele nötig
  (bewusst); optional 1 „Strömungs-Parcours" als Arcade-Reihe „Ruhig".
- **Score:** **9,5**

#### A2. Berg-/Ski-Resort-DLC „Funkelalm"

- **Konzept:** Das Bergmassiv der Ranch bekommt eine Winterseite: Seilbahn ab
  Hufingen, Alm-Dorf mit Hütte (zweites, kleines Zuhause zum Einrichten),
  Pisten in drei Schwierigkeiten und einen Rodel-Hang. Wintersport nutzt das
  vorhandene Fahr-/Steuer-Framework (Ski/Rodel als „Fahrzeuge"), dazu
  Après-Ski-Kakao-Stube mit eigenen Stammgästen und einem
  Schneemann-Bau-Ritual pro Besuch. Das Resort hat einen Saisonpass mit
  Pisten-Stempeln und einem Lawinen-Warndienst-Nebenjob.
- **Spielziel-Beitrag:** Zweites XL-Ziel für Spätspieler; die Hütte als
  einrichtbares Zweitheim gibt dem 207-Möbel-Katalog neuen Sinn (Progression:
  Belohnung = neuer Gestaltungsraum statt Zähler). Ski-Geister-Rennen
  gegen Freunde nutzen das vorhandene Geister-System asynchron (Multiplayer
  4,5 ohne Server-Pflicht).
- **Aufwand:** **XL** — 3–4 Berg-Zonen-Szenen + Hütten-Innenraum, Seilbahn-
  Cutscene, Ski-/Rodel-Controller auf Fahr-Framework, Slice `funkelalm`,
  ~35 Assets (Schnee-Varianten existieren teils aus Winter-Deko-Pack),
  Stammgast-NPCs, 10–12 Quests, 10 Sticker.
- **Score:** **8,5**

#### A3. Café-DLC „Café Herzknuffel"

- **Konzept:** Ein ruhiges Nachbarschafts-Café als Gegenpol zu McGooby: kein
  Zeitdruck, sondern Beziehungs-Spiel. Man wählt Tageskarte (Rezepte aus dem
  Kochbuch E6), richtet den Gastraum ein und bedient **Stammgäste mit echten
  Fortsetzungs-Geschichten** — jeder Gast hat 10+ Kapitel Dialog, die sich
  über Wochen entfalten (die Rentnerin, die auf Briefe wartet; der schüchterne
  Straßenmusiker …). Wer die Lieblingsbestellung eines Gastes merkt und
  vorbereitet, schaltet Geschichten schneller frei.
- **Spielziel-Beitrag:** Stopft das Eval-Loch „Belohnungen erzeugen keine
  persönliche Geschichte": Hier IST die Geschichte die Belohnung. Monatelange
  Ziele durch Gäste-Kapitel + Rezept-Rotation; klare Abgrenzung zum
  McGooby-Skill-Loop (Dopplungs-Verbot aus dem Goo-und-Bye-Doc respektiert).
- **Aufwand:** **XL** — Café-Innenszene (Grid-Baumodus-Wiederverwendung wie
  Goo und Bye §3.1), Slice `cafe`, Gäste-Katalog (8 Gäste × 10 Kapitel
  Dialogbäume, DE+EN — der größte Posten sind STRINGS, nicht Code),
  ~20 Assets, Tageskarten-UI, 8 Sticker.
- **Score:** **8,5**

#### A4. Insel-Resort „Kokoswelle" — Urlaub wird begehbar

- **Konzept:** Das meistgebuchte Reiseziel (Strand) wird von der Cutscene zur
  kleinen begehbaren Welt: Strandpromenade, Bungalow, Schnorchel-Bucht
  (Vorgeschmack auf A1), Strandbar, Hängematten-Idle für Gooby. Urlaubstage
  laufen als echte Tage mit 3 wählbaren Aktivitäten (Muscheln, Sandburg-Ritual,
  Markt), die Erholungs-Boni und Souvenirs füttern. Die W15-„Gooby im Urlaub
  besuchen"-Szenen werden zur Basis ausgebaut statt ersetzt.
- **Spielziel-Beitrag:** Löst den USER-WISH „Urlaub muss einen Nutzen haben"
  endgültig ein und macht aus 9 Reisezielen eine Ausbau-Schiene: pro Version
  kann ein weiteres Ziel begehbar werden (klare 6.0→15.0-Wachstumsachse).
  Gemeinsamer Urlaub mit Besuchs-Freund = neuer MP-Moment.
- **Aufwand:** **L→XL** — 2–3 Insel-Szenen (W15-Urlaubsszenen als Startpunkt),
  Erweiterung Slice `travel`, ~25 Assets (Palmen aus CC0-Backlog eingeplant),
  Aktivitäten-Katalog, 6 Sticker.
- **Score:** **8**

#### A5. Kindergarten-DLC „Die Mini-Goobys"

- **Konzept:** Gooby übernimmt ehrenamtlich den Stadt-Kindergarten: 3–5
  Mini-Goobys mit eigenen Temperamenten (Wildfang, Träumerin, Nimmersatt …)
  wollen an Werktagen beschäftigt werden — Bastelstunde, Vorlesen (nutzt die
  Geschichten-Stunde-Bücher!), Ausflug in den Funkelpark. Die Minis wachsen
  über Wochen sichtbar und „graduieren" irgendwann mit Abschlussfest; danach
  kommt ein neuer Jahrgang mit neuen Persönlichkeiten.
- **Spielziel-Beitrag:** Monats-Rhythmus mit emotionalem Bogen (Jahrgänge!)
  statt flacher Leisten; verzahnt bestehende Systeme (Bücher, Park, Basteln)
  neu. Risiko: dupliziert den Care-Loop — Design muss auf „Momente statt
  zweite Bedürfnisbalken" bestehen.
- **Aufwand:** **XL** — Kindergarten-Innen/Außen-Szene, Mini-Gooby-Modell
  (Skalierung + eigene Clips), Slice `kindergarten`, Temperament-/
  Jahrgangs-Katalog, ~15 Assets, 10 Sticker.
- **Score:** **7,5**

#### A6. Landwirtschafts-Erweiterung „Der Goobyhof"

- **Konzept:** Zwischen Garten 2.0 und Ranch entsteht die fehlende Mitte:
  pachtbare **Felder** (großes Grid jenseits des Gartens), Saatgut-Wirtschaft
  mit Saisonkalender (C3), Scheune mit Silo-Lager und ein Markt-Ökosystem —
  Wochenmarkt-Preise reagieren auf das eigene Angebot (Preiselastizität
  existiert bereits im Marktcode!). Erntehelfer-NPCs kann man tageweise
  anheuern; die Ranch liefert Dünger, der Hof liefert Ranch-Futter (Synergie
  statt Insel).
- **Spielziel-Beitrag:** Verwandelt drei existierende Einzelsysteme
  (Garten/Markt/Ranch) in EIN Wirtschaftsspiel mit Saison-Planung — genau die
  von der Eval geforderte Verknüpfung statt neuer Breite (Progression 5,5).
- **Aufwand:** **L** — Feld-Szene (Garten-Grid-Wiederverwendung), Erweiterung
  Slices `garden`/`market`, Saat-/Preis-Kataloge, ~15 Assets (Gemüse mit
  Wachstumsstufen liegt als CC0-Pack schon im Repo), 8 Quests.
- **Score:** **8**

### Kategorie B — Sammeln, Museum & Naturkunde (das ACNH-Rückgrat)

#### B1. Insekten-Album + Käscher

- **Konzept:** Der POW!-Laden verkauft den Käscher; ab dann summen in Garten,
  Stadt, Ranch und Funkelpark **30–40 Insekten**, deren Vorkommen von Ort,
  Tageszeit, Wetter und (mit C3) Saison abhängt — der Seltenheits-Nervenkitzel
  von ACNH. Fangen ist ein kurzer Schleich-Skill-Moment (Annähern + Timing),
  kein Menü. Jeder Erstfang bekommt die Gooby-typische Witz-Zeile („Ein
  Zitterling! Er zittert… genau wie ich!").
- **Spielziel-Beitrag:** Das klassische „Ich schau nur kurz, was heute
  fliegt"-Langzeitziel: bindet Tageszeiten/Wetter/Orte, die es alle schon
  gibt, in ein monatelanges Sammelziel ein (Progression + tägliche
  Weltveränderung, Eval-Finding „zu wenig tägliche Weltveränderung").
- **Aufwand:** **L** — Spawn-System (Wetter-/Uhr-Hooks existieren),
  Fang-Interaktion, Insekten-Katalog + Album-Tab (Collections-View erweitern),
  Slice-Erweiterung `collections.insects`, ~35 kleine Assets, 6 Sticker.
- **Score:** **9**

#### B2. Fossilien & Ausgrabungsstellen

- **Konzept:** Täglich erscheinen 4–6 Riss-Stellen in Garten, Stadt-Grünflächen
  und Ranch-Zonen; mit der Baumarkt-Schaufel gräbt Gooby Fossilteile aus
  (Grab-Mini-Moment mit Vorsicht-Mechanik: zu grob = Teil beschädigt,
  Goobyseum-Kurator seufzt). Fossilien kommen in **Sets** (Brachio-Gooby:
  Schädel/Hals/Rumpf/Schwanz), erst komplette Sets ergeben das
  Museums-Exponat.
- **Spielziel-Beitrag:** Der stärkste Tages-Login-Grund nach ACNH-Vorbild —
  endlich ein Tagesloop-Baustein, der NICHT „Aktion N-mal" ist
  (Eval-Kritik an den 24 Tagesquests). Set-Logik erzeugt Wochenziele und
  füttert die Tausch-Post (F2).
- **Aufwand:** **M** — Spawn-Logik (deterministisch aus Tages-Seed),
  Grab-Interaktion, Fossil-Katalog (8 Skelette × 3–4 Teile),
  Slice `collections.fossils`, ~12 Assets.
- **Score:** **8,5**

#### B3. Das GOOBYSEUM — ein Museum, das man kuratiert

- **Konzept:** Ein neues Stadtgebäude mit vier Flügeln (Fische/Insekten/
  Fossilien/Kunst), geführt von Kurator **Prof. Eule von Vitrine**. Jede
  Spende wird als echtes 3D-Exponat sichtbar — leere Hallen füllen sich über
  Monate zu einem Ort, durch den man Freunde führen kann. Der Kurator
  kommentiert jede Spende mit einem Zwei-Satz-Wissens-Gag; Meilensteine
  (10/25/50 Exponate pro Flügel) schalten Sonderausstellungen und
  Museums-Nachtbesuch frei.
- **Spielziel-Beitrag:** DER Anker der Naturkunde-Säule: Angeln 2.0, Insekten,
  Fossilien und Tiefsee-Funde zahlen alle auf EIN sichtbares, begehbares
  Langzeitziel ein — Belohnung verändert die Welt (Progression 5,5), und als
  Besuchsziel wertet es das Besuchs-System auf (Multiplayer 4,5).
- **Aufwand:** **L** — Museums-Szene (4 Hallen, Exponat-Sockel prozedural aus
  Katalogen befüllt), Kurator-NPC + Dialogbaum, Slice `museum`
  (Spenden-Status), ~20 Architektur-Assets (Exponate kommen aus den
  Sammel-Katalogen selbst!), 8 Sticker, 4 Erfolge.
- **Score:** **9,5**

#### B4. Angeln 2.0 — Gewässer, Schatten, Saisonfische

- **Konzept:** Der bestehende Angel-Loop wird zum Sammelspiel: **Gewässer-Typen**
  (Gartenteich, Ranch-Bergsee, Muschelbucht, Stadt-Brunnen als Gag) mit je
  eigenem Fischbestand, Schatten-Größen vor dem Biss, Tageszeit-/Wetter-/
  Saisonfenster und 8–10 seltenen „Legenden-Fischen" mit eigener Fang-Zeile.
  Der Fisch-Sammlungsset-Tab wächst von heute auf ~45 Arten; Duplikate werden
  Museums-Spende, Aquarium-Besatz (A1) oder Tausch-Ware (F2).
- **Spielziel-Beitrag:** Verwandelt ein vorhandenes Feature in ein
  Monats-Ziel, ohne neue Spielart zu erfinden — exakt die Eval-Direktive
  „Gründe, Vorhandenes erneut zu spielen". Direkter Zulieferer für Museum und
  Tiefsee-DLC.
- **Aufwand:** **M** — Fisch-Katalog-Ausbau + Spawn-Regeln (Wetter/Uhr-Hooks
  vorhanden), Schatten-Rendering am Angel-Spot, Album-Erweiterung,
  ~20 Fisch-Assets (Low-Poly, klein).
- **Score:** **8,5**

#### B5. Sternwarte + Sternbild-Album

- **Konzept:** Auf dem Ranch-Plateau öffnet nachts eine kleine Sternwarte:
  Durchs Teleskop sucht man in einem ruhigen Himmel-Panorama Sternbilder
  (Wimmelbild-Prinzip), katalogisiert sie im Sternbild-Album und erwischt in
  echten Meteor-Nächten (Kalender!) Sternschnuppen für Wunsch-Rezepte.
  Verzahnt mit Raumstation GOOB-1: Wer 12 Sternbilder hat, bekommt dort den
  „Navigator"-Titel.
- **Spielziel-Beitrag:** Gibt der Nacht (Tag/Nacht-System existiert!) einen
  eigenen Content-Grund und schafft ein weiteres ruhiges Sammelziel für die
  „Ruhig & Gemütlich"-Spielerschaft.
- **Aufwand:** **M** — Sternwarte-Szene + Teleskop-View, Sternbild-Katalog
  (20 Stück), Slice `collections.stars`, wenig Assets (Shader-Himmel
  existiert).
- **Score:** **7,5**

#### B6. Blumen-Zucht mit Kreuzungen

- **Konzept:** Garten 2.0 lernt Genetik light: Blumen in Grundfarben lassen
  sich benachbart pflanzen und kreuzen mit deterministischen (injizierter RNG!)
  Regeln zu Hybrid-Farben — bis zur legendären Gold-Möhrenblume. Hybride sind
  Deko, Geschenk-Ware für Nachbarn (D1) und Museums-Kunstflügel-Spenden.
- **Spielziel-Beitrag:** Der ACNH-Hybridblumen-Loop ist ein bewährtes
  Monatsziel mit täglicher 2-Minuten-Routine; nutzt Gieß-/Wetter-Systeme, die
  komplett existieren (Progression durch Wissen statt Grind).
- **Aufwand:** **M** — Kreuzungs-Logik (pur, testbar), 6 Blumenfamilien × 6
  Farben als Assets/Tints, Katalog + Album-Seite, Slice-Erweiterung `garden`.
- **Score:** **8**

### Kategorie C — Jahreskalender & Feste

#### C1. Jahresfest-Kalender (8 Feste, Welle 1 = 4)

- **Konzept:** Ein fester Jahreskalender realer Daten:
  **Laternenfest** (November: Laternen basteln, Umzug durch die Abendstadt),
  **Erntedank** (Oktober: Riesen-Gemüse-Wettbewerb — Goobyhof/Garten zahlt
  ein), **Winterlichter** (Dezember), **Silvester** (C2),
  **Frühlingsblüte**, **Sommer-Seifenkistenrennen**, **Gruselnacht**
  (Kostüme = Cosmetics!), **Gooby-Tag** (Spielstand-Geburtstag). Jedes Fest
  verwandelt die Stadt sichtbar (Deko-Layer), hat 1 Ritual, 1 exklusive
  Belohnungs-Reihe und 1 Fest-Sticker — Wiederkehr im nächsten Jahr mit
  Variation.
- **Spielziel-Beitrag:** Der stärkste Kalender-Anker gegen das Eval-Loch
  „zu wenig tägliche/saisonale Weltveränderung": Feste geben MONATE im Voraus
  Vorfreude-Ziele und machen die Stadt zur Bühne statt Transaktionsstation
  (Stadt-Score 6,5). Feste sind natürliche Verabredungs-Momente für Besuche
  (Multiplayer 4,5).
- **Aufwand:** **L** (Welle 1 mit 4 Festen) — Fest-Engine (Kalender-Gate,
  injizierte Clock!, Deko-Layer pro Ort), pro Fest 1 Ritual-Interaktion +
  Deko-Assets + Strings; Slice `festivals` (besuchte Jahre, Belohnungen).
  Packs-fähig: weitere Feste als Content-Pack ohne IPA.
- **Score:** **9**

#### C2. Silvester-Feuerwerk mit Echtzeit-Countdown

- **Konzept:** Am 31.12. zählt die Stadtuhr zur ECHTEN Mitternacht (lokale
  Gerätezeit, injizierte Clock für Tests): Countdown auf dem Marktplatz,
  Goobys tragen Partyhüte, um 0:00 startet ein 3-Minuten-Feuerwerk über der
  Stadt, Gooby staunt mit dem 12-Emotionen-System. Wer dabei ist, bekommt den
  Jahres-Sticker „Guten Rutsch {Jahr}!" — jedes Jahr ein neuer.
- **Spielziel-Beitrag:** Ein einziger unvergesslicher Echtzeit-Moment pro Jahr
  — maximale Erinnerungs-Dichte pro Aufwand, Vorbild ACNH-Silvester. Perfekter
  gemeinsamer Besuchs-Moment.
- **Aufwand:** **S** — Countdown-Overlay + Feuerwerk-Partikel (FX-Stack
  existiert), Marktplatz-Deko, 1 Sticker/Jahr (datengetrieben), Clock-Gate.
- **Score:** **8,5**

#### C3. Echte Jahreszeiten im Basisspiel

- **Konzept:** Vier Saisons nach realem Kalender färben Welt und Content:
  Laub/Schnee/Blüten-Varianten für Stadt, Garten und Ranch (Material-Tints +
  Partikel statt neuer Szenen), Saison-Fenster für Crops, Fische, Insekten und
  Markt-Preise. Der Winter bringt Schneemann-Bau + zufrierenden Teich; der
  Herbst Kastanien-Sammeln.
- **Spielziel-Beitrag:** Fundament für B1/B4/C1/A6 — die eine Änderung, die
  ALLE Sammel- und Fest-Inhalte in einen Jahresrhythmus spannt und dem Spiel
  „Monate an Zielen" strukturell einbaut (Eval: Wiederholung → Rhythmus).
- **Aufwand:** **L** — Saison-Service (Clock-injiziert), Material-/
  Partikel-Varianten über 3 Welten, Saison-Felder in Spawn-/Preis-Katalogen,
  wenig neue Meshes (Winter-Deko-Pack liegt im Repo).
- **Score:** **8,5**

#### C4. Wanderjahrmarkt „Zirkus Goobyloni"

- **Konzept:** Einmal im Monat gastiert ein kleiner Wanderzirkus für 3 Tage
  neben dem Funkelpark: 3 Schausteller-Stände (Losbude mit
  deterministischer Preis-Rotation, Spiegelkabinett-Gag mit verzerrtem Gooby,
  Wahrsagerin, die Save-Daten witzig „liest": „Ich sehe… 4 ungegossene
  Beete!"). Exklusive Zirkus-Deko-Serie über Monate sammelbar.
- **Spielziel-Beitrag:** Monats-Beat zwischen den Festen; billige, wiederkehrende
  Weltveränderung mit Sammel-Serie als Langzeitklammer.
- **Aufwand:** **M** — 1 Zelt-Szene am Funkelpark-Rand, 3 Stand-Interaktionen,
  Monats-Gate, ~10 Assets, Deko-Serie im Katalog.
- **Score:** **7,5**

### Kategorie D — Nachbarn, NPCs & Story

#### D1. Nachbarschafts-Herzen + Geschenke-System

- **Konzept:** Die 5 benannten Stammkunden (Frau Rosine, Opa Hatschi, Frau
  Fernweh, Herr Dübel, Rollo) + 7 neue Figuren werden echte **Nachbarn** mit
  Herz-Leveln nach Ranch-NPC-Muster: Jeder hat Tagesroutine, Vorlieben,
  Abneigungen und pro Herz-Stufe eine freigeschaltete Mini-Geschichte.
  **Geschenke** sind der Motor: verpackbar an der Post, Reaktion hängt von
  Vorliebe ab (Herr Dübel liebt Werkstatt-Selbstgebautes!), zurückgeschenkt
  wird auch — Nachbarn schicken Briefe und seltene Items.
- **Spielziel-Beitrag:** Übersetzt den beliebtesten ACNH-Loop (Dorfbewohner-
  Freundschaften) auf die bereits belebte Stadt: monatelange Beziehungsziele,
  die Crafting, Läden, Garten und Post als Geschenk-Quellen NEU verwerten
  (Progression 5,5: Belohnung = Geschichte + Beziehung statt Coins).
- **Aufwand:** **L** — Herz-/Vorlieben-Kataloge (Ranch-Herzen-Code
  wiederverwenden), Geschenk-Interaktion + Post-Anbindung, 12 × 5
  Mini-Geschichten (Hauptposten: Strings DE+EN), Slice `neighbors`,
  wenige Assets (Figuren existieren teils).
- **Score:** **9**

#### D2. Story-Kampagne „Goobys Jahr" — Staffel 1 (Kapitel 1–8)

- **Konzept:** Die von der Eval geforderte Zielkette (Prio 3) als Content:
  8 Kapitel mit Zwischensequenzen (Cutscene-Pipeline existiert!), die die
  V6-Inhalte erzählerisch auffädeln — vom „Der alte Professor braucht Hilfe:
  das Museum ist LEER!" über das erste Laternenfest bis zum
  Tiefsee-Steg-Finale. Jedes Kapitel endet mit sichtbarer Weltänderung
  (Museum-Flügel öffnet, Fest-Deko bleibt, Steg wird gebaut) und einer
  Fähigkeit (Käscher, Schaufel, Tauchhelm) statt Coins.
- **Spielziel-Beitrag:** Der direkte Fix für das größte Eval-Loch (Progression
  5,5: „viele Leisten, keine Kampagne"). Als Staffel-Format über Versionen
  skalierbar: 6.0 = Staffel 1, jede Folgeversion +1 Staffel um ihre neuen
  Inhalte.
- **Aufwand:** **L** — Kapitel-Engine auf Quest-Engine aufsetzen
  (Meilenstein-Kette + Kapitel-Karte im Profil), 8 kurze Cutscenes
  (bestehende Pipeline), Kapitel-Katalog, Slice `campaign`, Strings.
- **Score:** **9,5**

#### D3. Brieffreundin „Oma Weitweg auf Weltreise"

- **Konzept:** Eine NPC-Brieffreundin bereist die 9 Reiseziele und schreibt
  alle 2–3 Tage echte Briefe mit Foto-Postkarte und **Briefmarke** — 30
  Briefmarken als eigenes Mini-Album. Antwortet man (Antwort-Chips), beeinflusst
  das ihre Route; ab und zu schickt sie Souvenirs oder bittet Gooby, ihr etwas
  Bestimmtes zu schicken (Post-Feature wird Pflicht-Loop).
- **Spielziel-Beitrag:** Gibt dem fertigen Post-System einen dauerhaften
  Single-Player-Herzschlag — genau der „Multiplayer-Gefühl ohne
  Server"-Baustein, den die 4,5 verlangt; Briefmarken = ruhiges Sammelziel.
- **Aufwand:** **M** — Brief-Kette als Datenkatalog (Route deterministisch,
  Clock-injiziert), 30 Briefmarken-Icons, Album-Seite, Slice-Erweiterung
  `mail.penpal`, Strings.
- **Score:** **8**

#### D4. NPC-Geburtstags-Kalender

- **Konzept:** Alle Nachbarn (D1), Ranch-NPCs und DLC-Figuren bekommen feste
  Geburtstage im Jahreskalender; am Tag hängt Deko an ihrem Ort, sie freuen
  sich über Geschenke doppelt, und es gibt eine Mini-Feier-Szene mit Kuchen.
  Der IGohbie-Kalender erinnert 2 Tage vorher.
- **Spielziel-Beitrag:** Micro-Content, der den Kalender (C1/C3) verdichtet
  und D1-Beziehungen Termine gibt — 25+ kleine Vorfreude-Anker pro Jahr.
- **Aufwand:** **S** — Geburtstags-Felder in NPC-Katalogen, Kalender-Check,
  1 Feier-Overlay, Strings.
- **Score:** **7,5**

### Kategorie E — Haus, Ausbau & Hobbys

#### E1. Villa-Ausbau: Keller, 2. Etage, Balkon

- **Konzept:** Der explizite USER-WISH (§D43, M3-Backlog) als Content-Schiene:
  4 Haus-Ausbaustufen beim Baumarkt beauftragen (Bau-Animation mit Gerüst +
  Qualm über 1 Realtag), jede Stufe = neue begehbare Raum-Szenen (Keller,
  Obergeschoss mit 2 Räumen, Balkon mit Straßenblick). Stufenpreise sind die
  großen Coin-Senken, die die Wirtschaft braucht.
- **Spielziel-Beitrag:** Das klassische ACNH-Langzeitziel Nummer 1
  (Haus-Kredit-Treppe) fehlt GOOBY komplett — dies ist die größte einzelne
  Progression-Lücke mit fertigem Wunsch-Beleg. Gibt 207 Möbeln + Baumodus
  Monate neuen Auslauf.
- **Aufwand:** **L** — 4 Raum-Szenen (Raum-Szenen-Muster existiert),
  Treppen-/Tür-Verdrahtung im SceneRouter, Slice-Erweiterung `home.stufen`,
  Bau-Cutscene, ~10 Architektur-Assets.
- **Score:** **9**

#### E2. Keller-Hobbyräume: Töpferei + Fotostudio

- **Konzept:** Der neue Keller (E1) kann als Hobbyraum ausgebaut werden:
  Die **Töpferei** macht aus Ton (Ranch-Fundort!) eigene Vasen/Teller — Form
  per Dreh-Interaktion, Glasur per Farbwahl, Ergebnis ist ein ECHTES
  Unikat-Möbel und Top-Geschenk (D1). Das **Fotostudio** bietet Kulissen,
  Requisiten und Licht-Presets für den Fotomodus — Grundlage für den
  Foto-Wettbewerb (F1).
- **Spielziel-Beitrag:** Kreativ-Content mit Besitz-Ergebnis: selbst gemachte
  Dinge stehen sichtbar in der Welt (Eval-Forderung „Belohnungen, die die Welt
  verändern"). Zwei Hobbys = zwei ruhige Langzeit-Skills.
- **Aufwand:** **L** — 2 Kellerraum-Varianten, Töpfer-Interaktion
  (Mesh-Morphs + Tints), Unikat-Item-Serialisierung im Möbel-Slice,
  Studio-Presets im Fotomodus, ~15 Assets.
- **Score:** **8**

#### E3. Berufe & Nebenjobs für Gooby

- **Konzept:** Das Schwarze Brett an der Post bietet rotierende **Nebenjobs**
  mit Job-Leveln: Post austragen (3 Pakete an Nachbar-Adressen — nutzt
  Stadt-Navigation), Gärtnern für Nachbarn (fremde Mini-Beete pflegen),
  Taxi-Aushilfe (Fahrgäste im City-Drive-Modus), Museums-Nachtwächter
  (Wimmelbild: was ist anders?). Jobs zahlen neben Coins **Referenzen** —
  10 Referenzen = Job-Beförderung mit Uniform-Cosmetic und neuen Auftragsarten.
- **Spielziel-Beitrag:** Erfüllt den USER-WISH „Berufe/Nebenjobs" und gibt der
  Stadt die fehlende Aufgabenlinie (Stadt 6,5: „Orte sind Stationen") — Jobs
  verbinden mehrere Orte pro Auftrag, exakt Eval-Prio 13.
- **Aufwand:** **L** — Job-Engine (Auftrags-Generator, deterministisch),
  4 Job-Ablauf-Szenenkits auf bestehenden Welten, Slice `jobs`,
  Uniform-Cosmetics, Strings.
- **Score:** **8,5**

#### E4. Trophäen-Regal & Meilenstein-Möbel

- **Konzept:** Große Meilensteine (Legenden-Fisch, Staffel-Finale, 100
  Museums-Exponate, Arcade-Reihen-Pokal …) materialisieren sich als
  **Trophäen-Möbel**: Pokale, gerahmte Fotos, präparierter Rekordfisch — nur
  erspielbar, nie kaufbar. Ein IKEA-Trophäenregal präsentiert sie mit
  Erinnerungs-Tooltip („Gefangen am 12.03. bei Gewitter").
- **Spielziel-Beitrag:** Billigster Fix für „Erfolge dokumentieren Verhalten,
  verändern es aber selten": Leistung wird Wohnungs-Inhalt, den Besucher sehen.
- **Aufwand:** **S** — Trophäen-Katalog (Möbel-Pipeline), Meilenstein-Hooks,
  ~12 kleine Assets, Tooltip-Daten im Möbel-Slice.
- **Score:** **8**

### Kategorie F — Multiplayer-Content (async-first, wegen localhost-Realität)

#### F1. Wöchentlicher Foto-Wettbewerb „Blende & Blubber"

- **Konzept:** Jede Woche ein Foto-Thema („Dein Gooby + Regen", „Marktstand-
  Stillleben") im IGohbie; eingereicht wird per bestehendem Post-/
  Server-Kanal, bei Offline-Betrieb bewertet eine Jury aus NPC-Nachbarn
  (deterministisches Scoring auf Bild-Metadaten: Ort/Emotion/Requisiten —
  ehrlich als NPC-Jury kommuniziert). Gewinnerfotos hängen eine Woche im
  Museums-Kunstflügel; Teilnahme-Serie = eigene Sticker-Reihe.
- **Spielziel-Beitrag:** Wochen-Rhythmus + kreatives Ziel, das Fotomodus,
  Studio (E2) und Orte neu verwertet. Online mit Freunden echt, offline
  vollwertig per NPC-Jury — der ehrliche Umgang mit der
  localhost-Schwäche (Multiplayer 4,5, Eval-Prio 19).
- **Aufwand:** **M** — Themen-Katalog (Pack-updatebar!), Einreichungs-Flow auf
  Mail-Kanal, NPC-Jury-Scoring (pur, testbar), Museums-Aushang, Sticker.
- **Score:** **8,5**

#### F2. Tausch-Post: Sammlungs-Duplikate tauschen

- **Konzept:** Doppelte Fossilteile, Fische, Briefmarken oder Möbel-Baupläne
  lassen sich per Brief als **Tauschangebot** an Freunde schicken („Ich gebe:
  Brachio-Schwanz. Ich suche: Brachio-Schädel."); der Empfänger akzeptiert
  asynchron — komplett über die existierende Offline-Outbox, kein
  Live-Server-Zwang. Ein Schwarzes-Brett-Tab zeigt offene Angebote.
- **Spielziel-Beitrag:** Macht ALLE V6-Sammlungen sozial (der ACNH-Kern
  „meine Kirschen gegen deine Pfirsiche") und gibt dem Post-System einen
  wiederkehrenden Zweck — bester Multiplayer-Wert pro Aufwand (4,5), weil
  asynchron und damit out-of-the-box erlebbar, sobald IRGENDEIN Server
  konfiguriert ist.
- **Aufwand:** **M** — Tausch-Protokoll auf Mail-Modul (Server: 1 neues
  Nachrichtenfeld + Escrow-Logik gegen Item-Verlust — transaktional!),
  Angebots-UI, Wächter-Tests.
- **Score:** **8,5**

#### F3. Gemeinschafts-Beet & Gieß-Besuche

- **Konzept:** Ein markierbares Garten-Beet wird „Gemeinschafts-Beet": Besucher
  dürfen dort gießen, ernten (Anteil) und eine Überraschungs-Saat stecken.
  Wer bei Freunden gießt, hinterlässt ein Schleifchen + Notiz; seltene
  Freundschafts-Blume wächst NUR in Beeten, die von 2 verschiedenen Spielern
  gepflegt wurden.
- **Spielziel-Beitrag:** Gibt Besuchen (funktioniert bereits!) eine Handlung
  statt nur Anschauen — behebt den Eval-Befund „Besuch = Ansehen" mit
  minimalem Neu-System; Freundschafts-Blume ist ein echtes MP-exklusives
  Sammelziel (fair: nicht abschluss-relevant, Lehre aus Eval-Finding 4).
- **Aufwand:** **M** — Beet-Flag im Garten-Slice, Besucher-Rechte im
  Visit-Protokoll, Blumen-Spezies, Notiz-UI.
- **Score:** **7,5**

#### F4. Koop-Wochenaufgabe „Beste-Freunde-Zettel"

- **Konzept:** Jede Woche ein gemeinsamer 2-Personen-Zettel per Post: beide
  Spieler tragen asynchron zu EINEM Ziel bei („Fangt zusammen 20 Fische",
  „Sammelt je 1 Fossil-Set-Teil"). Fortschritt synct über Mail-Pings;
  Abschluss belohnt BEIDE mit einem Duo-Sticker und einem geteilten
  Erinnerungsfoto im Album.
- **Spielziel-Beitrag:** Wiederkehrender sozialer Termin ohne
  Gleichzeitigkeits-Zwang — passend zur Realität, dass Freunde selten
  gleichzeitig online sind (Multiplayer 4,5).
- **Aufwand:** **M** — Wochenzettel-Katalog, Fortschritts-Merge über Mail
  (idempotent!), Duo-Sticker, Slice `social.wochenzettel`.
- **Score:** **8**

#### F5. Museums-Leihgaben von Freunden

- **Konzept:** Freunde können dem eigenen GOOBYSEUM Exponate **leihen**: das
  Stück steht 7 Tage mit Messing-Schild („Leihgabe von Sonic0810") im
  passenden Flügel und zählt für Sonderausstellungen. Beim Besuch beim Freund
  sieht man umgekehrt die eigenen Leihgaben glänzen.
- **Spielziel-Beitrag:** Verbindet die Museums-Säule direkt mit dem
  Freunde-System und erzeugt Gegenseitigkeits-Momente — Sichtbarkeit des
  Freundes in MEINER Welt ist der stärkste Social-Klebstoff (4,5).
- **Aufwand:** **S→M** — Leih-Protokoll auf Mail/Visit, Schild-Rendering,
  Ablauf-Timer (Clock-injiziert).
- **Score:** **7,5**

### Kategorie G — Progression-Content (die 5,5 direkt anheben)

#### G1. Arcade-Reihen-Meisterschaften mit einzigartigen Belohnungen

- **Konzept:** Jede der 6 Arcade-Reihen bekommt eine Meisterschafts-Leiter
  (Bronze/Silber/Gold über Sterne der Reihe) mit REIHEN-EIGENER Belohnung
  statt Coins: „Fahren & Liefern" → Autoteile/Lack, „Ranch & Turnier" →
  Ausrüstung, „Puzzle & Denken" → Museums-Kunstwerke, „Ruhig & Gemütlich" →
  exklusive Musik fürs Radio, „Geschick & Timing" → Werkstatt-Baupläne,
  „Tempo & Action" → Funkelpark-Deko. Gold pro Reihe = Reihen-Pokal fürs
  Trophäenregal (E4).
- **Spielziel-Beitrag:** Eval-Prio 11 wörtlich („einzigartige
  Fortschrittswährung mit echter Wirkung pro Reihe") — der wichtigste Hebel,
  damit 38 vorhandene Spiele monatelang Ziele bleiben (Progression 5,5).
- **Aufwand:** **L** — Meisterschafts-Logik auf `ArcadeFortschritt`-Sternen,
  6 Belohnungs-Kataloge (Items in bestehende Systeme einhängen),
  Meisterschafts-UI in der Arcade, keine neuen Spiele.
- **Score:** **9**

#### G2. GOOBY-Wochenpass (kostenlos, saisonal)

- **Konzept:** Ein kostenloser 8-Wochen-Pass pro Saison (C3) mit einer Spur
  aus ~30 Stufen: Punkte kommen aus ALLEN Aktivitäten (Care, Jobs, Sammeln,
  Arcade, DLCs), Belohnungen sind Saison-Deko, Cosmetics und Fest-Vorbereitung
  (Laternen-Bauplan 2 Wochen vor dem Laternenfest!). Bewusst ohne Kaufspur —
  der Pass ist Kompass, nicht Kasse.
- **Spielziel-Beitrag:** Die von der Eval vermisste „klare Priorität" über
  allen Leisten: EIN Ort, der jede Woche sagt, was sich lohnt — und die
  Saisons/Feste vorbereitet (Progression 5,5, ROADMAP-W20 nennt ihn bereits
  als L-Brocken).
- **Aufwand:** **M** — Pass-Katalog pro Saison (Pack-updatebar), Punkte-Hooks
  auf bestehende Events, Pass-Screen, Slice `pass`.
- **Score:** **8,5**

#### G3. Funkelpark-Parkpass + Saison-Umbauten

- **Konzept:** Der Funkelpark bekommt den fehlenden Langzeitloop
  (Eval-Finding 14): Stempelpass mit Tages-Kombinationen („Riesenrad bei
  Nacht + Zuckerwatte"), pro Saison ein Umbau (Winter: Eisbahn statt
  Autoscooter-Vorplatz), Timing-Momente pro Fahrt (Hände-hoch im richtigen
  Moment = Foto-Perfekt) und eine Park-Souvenir-Reihe. Voller Saisonpass
  schaltet sichtbare Park-Deko dauerhaft frei.
- **Spielziel-Beitrag:** Verwandelt einen fertigen Ort von „einmal gesehen"
  in einen Saison-Loop — reine Content-Verdichtung ohne neues System.
- **Aufwand:** **M** — Pass-Logik + Kombinations-Katalog, Saison-Deko-Layer,
  Souvenir-Items, Slice-Erweiterung `park`.
- **Score:** **8**

#### G4. Reise-Souvenirregal + Weltengooby 2.0

- **Konzept:** Jedes der 9 Reiseziele bekommt 3 Mini-Aufgaben (Foto-Motiv
  finden, lokale Speise essen, verstecktes Souvenir) und ein
  Vitrinen-Souvenir; das Wohnzimmer-Souvenirregal zeigt die Weltreise
  physisch. 27/27 = Weltengooby-Parade-Cutscene am Flughafen.
- **Spielziel-Beitrag:** Reisen (heute Cutscene + Boni) werden zu 27
  konkreten Zielen mit sichtbarem Wohnungs-Ergebnis — Brücke, bis Ziele nach
  A4-Muster begehbar werden.
- **Aufwand:** **M** — Aufgaben-Katalog pro Ziel, 9 Souvenir-Assets,
  Regal-Möbel, Slice-Erweiterung `travel`.
- **Score:** **7,5**

#### G5. Kochen & Rezeptbuch

- **Konzept:** Die Küche wird Craft-Station: 30 Rezepte aus Garten-/Hof-/
  Markt-Zutaten (Möhrensuppe bis Nutella-Crêpe-Turm), Koch-Interaktion mit
  3-Schritt-Mini-Choreo, Ergebnisse sind Speisen mit Sonder-Effekten
  (Picknick-Buff, Lieblingsessen-Chance) und Geschenk-Ware (D1) bzw.
  Café-Tageskarte (A3). Rezepte findet man in Büchern, bei Nachbarn und auf
  Festen — das Rezeptbuch ist ein eigenes Sammelziel.
- **Spielziel-Beitrag:** Verbindet Garten→Küche→Care→Geschenke zu einer
  Wertschöpfungskette (Eval: „Systeme laufen nebeneinander statt
  miteinander") und gibt dem 44-Speisen-Katalog eine zweite Ebene.
- **Aufwand:** **L** — Koch-Interaktion + Rezept-Katalog, Zutaten-Mapping auf
  FoodCatalog/Garten, Rezeptbuch-UI, Slice `cooking`, ~15 Speise-Assets.
- **Score:** **8,5**

### Kategorie H — Weitere Content-Bausteine

#### H1. Gooby-Haustier: „Der Wurm Herbert zieht ein"

- **Konzept:** Der Event-Wurm Herbert wird adoptierbar: Terrarium-Möbel,
  tägliches Mini-Füttern, Herbert kommentiert (Schild-Bubbles) und begleitet
  Gooby als Mini-Sidekick durch den Garten. Später weitere Adoptions-Tiere aus
  Events (Klopapier-Mumie-Katze?).
- **Spielziel-Beitrag:** Ein Tamagotchi IM Tamagotchi — kleiner täglicher
  Herz-Moment; macht ein bestehendes Event persistent (ROADMAP-Befund
  „Herbert nicht persistent").
- **Aufwand:** **M** — Terrarium-Interactable, Begleiter-Logik light,
  Slice-Erweiterung `pets`, wenige Assets.
- **Score:** **7,5**

#### H2. Straßenmusik & Bandproben

- **Konzept:** Gooby lernt 5 Instrumente (Kazoo zuerst!): Übungs-Sessions als
  ruhige Rhythmus-Interaktion zuhause, dann Straßenmusik-Auftritte an
  Stadt-Spots mit Publikums-Goobys und Hut-Münzen. Meisterschaft schaltet
  Auftritte auf Festen (C1) frei — inklusive Silvester-Bühne.
- **Spielziel-Beitrag:** Skill-Progression mit öffentlicher Bühne; verzahnt
  Home-Hobby mit Stadt und Festen. (Bewusst KEIN neues Arcade-Spiel: Auftritte
  sind Welt-Interaktionen.)
- **Aufwand:** **M** — Instrument-Items + Übungs-Interaktion, Auftritt-Spots,
  Slice `music`, Audio-Assets (Kazoo-Covers der Radio-Tracks!).
- **Score:** **7**

#### H3. Untermieter fürs Gästezimmer

- **Konzept:** Nach dem Villa-Ausbau (E1) kann ein Nachbar (D1, ab Herz-Level
  4) als Untermieter einziehen: eigenes Zimmer einrichten (seine Wünsche!),
  Morgen-Begegnungen in der Küche, Miet-Beitrag, kleine Alltags-Storys.
  Wechselbar — jeder Untermieter erzählt andere Geschichten.
- **Spielziel-Beitrag:** Krönung der Beziehungs-Säule: eine Beziehung wird
  WOHNRAUM (maximale Welt-Veränderung durch Progression); Wiederspielwert
  durch Untermieter-Wechsel.
- **Aufwand:** **L** — Zimmer-Zuweisung + NPC-Heim-Routinen,
  Wunsch-Einrichtungs-Checks, Story-Strings, Slice-Erweiterung `neighbors`.
- **Score:** **7,5**

#### H4. Goobypedia — das Entdecker-Handbuch

- **Konzept:** Ein In-Game-Lexikon, das sich selbst schreibt: Jede erlebte
  Sache (Fisch, Fest, NPC, Ort, Rezept, Event) bekommt eine illustrierte
  Seite mit Witz-Text und Fundumständen; Seiten-Vervollständigung pro Kapitel
  gibt Rahmen-Belohnungen. Der „???"-Nebel zeigt ehrlich, wie viel Welt noch
  wartet — OHNE Online-/DLC-Einträge in die Basis-Zählung zu mischen
  (Lehre aus Eval-Finding 4).
- **Spielziel-Beitrag:** Macht die gesamte Content-Menge (8,5!) als
  Entdeckungs-Landkarte sichtbar und ist das Schaufenster für alle
  V6-Sammlungen — Completion mit klaren, fairen Grenzen.
- **Aufwand:** **M** — Lexikon-UI auf Album-Muster, Auto-Einträge aus
  bestehenden Katalogen (generativ, kein Hand-Pflege-Zwang), Slice
  `goobypedia` (Gesehen-Status).
- **Score:** **8**

#### H5. Wetterfrosch-Station & Wetter-Tagebuch

- **Konzept:** Ein Dachboden-/Balkon-Instrument (E1-Synergie) zeichnet das
  deterministische Wetter auf: Wetter-Tagebuch mit Rekorden („längster
  Regen"), 1×/Woche eine Vorhersage-Wette (morgen Regen? Einsatz: Saatgut)
  und Regenbogen-Sichtungen als seltene Foto-Momente mit eigenem Sticker.
- **Spielziel-Beitrag:** Verwandelt das existierende Wetter-System in
  Sammel-/Beobachtungs-Content; billiger Zulieferer für B1/B4-Spawns
  („Morgen Regen → Regenwurm-Insekten!").
- **Aufwand:** **S** — Instrument-Interactable, Tagebuch-UI light,
  Wett-Logik (pur), 2 Sticker.
- **Score:** **7**

#### H6. Raumstation-Ausbau: Mondspaziergang „GOOB-LUNA"

- **Konzept:** Die Raumstation GOOB-1 bekommt ein Shuttle zum Mini-Mond:
  begehbarer Low-Gravity-Krater-Rundweg mit Mondstein-Sammlung (Museums-
  Sonderflügel!), Erde-Aufgang-Foto-Spot und dem einsamen Mond-Gooby „Luno",
  der sich über jede Stippvisite kindisch freut (Herz-Level → er zieht
  irgendwann in die Stadt!).
- **Spielziel-Beitrag:** Baut den schwächsten „Ort ohne Loop" zur kleinen
  Erkundungs-Destination aus; Lunos Umzug ist eine sichtbare Weltänderung als
  Belohnung (Progression).
- **Aufwand:** **M** — 1 Mond-Szene (Low-Gravity-Hopser existiert),
  Mondstein-Katalog, Luno-NPC, ~8 Assets.
- **Score:** **7,5**

#### H7. Geheimgänge & Stadt-Mysterien

- **Konzept:** 5 versteckte Mini-Mysterien in der bestehenden Stadt: der
  Gully, der nachts dampft (Kanal-Kurzbesuch), das immer verschlossene blaue
  Haus (Schlüssel-Questkette über Nachbarn), die Statue, die sich bei Regen
  dreht … Jedes Mysterium ist eine 3–5-Schritt-Entdeckung mit Foto-Beweis und
  Mysterien-Sticker-Seite.
- **Spielziel-Beitrag:** Belohnt das Neu-Lesen derselben Straßen (Stadt 6,5:
  „kein Grund, dieselben Straßen neu zu lesen") — Erkundungs-Content ohne
  neuen Ort.
- **Aufwand:** **M** — 5 Interaktions-Ketten in bestehenden Szenen,
  Hinweis-Strings, 5 Sticker, Slice-Erweiterung `city.mysteries`.
- **Score:** **8**

#### H8. Sammelkarten „GOOBY-Quartett"

- **Konzept:** Physische Sammelkarten (Booster bei POW!/Goobyman, Karten auch
  als Fest-/Job-/Meisterschafts-Belohnung): 60 Karten mit Stadt-NPCs,
  Ranch-Pferden und Legenden-Fischen in 3 Raritäten. Mit Nachbarn (D1) und
  Freunden (F2) tauschbar; volle Serien geben Quartett-Partien am
  Brettspieltisch (existiert!) gegen NPCs/Freunde.
- **Spielziel-Beitrag:** Klassisches Monats-Sammelziel, das Läden, Feste und
  den Brettspieltisch verbindet; Tauschbarkeit füttert F2 (Multiplayer 4,5).
- **Aufwand:** **M** — Karten-Katalog + Icons (generierbar), Booster-Logik
  (injizierter RNG), Album-Seite, Quartett-Regelwerk auf Brettspiel-Muster.
- **Score:** **7,5**

---

## 2) TOP-10 für Version 6.0 (priorisiert)

Mix wie beauftragt: **1 DLC-XL als Flaggschiff + L/M-Paket**, zusammengehalten
von einer Story-Staffel. Roter Faden von 6.0: **„Das Naturkunde-Jahr"** —
Sammeln, Museum, Feste und Nachbarn machen aus der vorhandenen Content-Breite
ein Jahres-Spiel; die Tiefsee liefert den DLC-Wow.

| # | Idee | Größe | Score | Stopft primär |
|---|---|---|---:|---|
| 1 | **A1 Tiefsee-DLC „GOOBY BLUBB"** (Tauchen, Aquarium-Haus, Meeres-Freunde) | XL | 9,5 | Nach-Stunde-10-Ziel, Welt-Belohnungen, Besuchs-Grund |
| 2 | **D2 Story-Kampagne „Goobys Jahr" Staffel 1** (8 Kapitel + Cutscenes, fädelt alle V6-Inhalte auf) | L | 9,5 | Progression 5,5 (Eval-Prio 3) |
| 3 | **B3 GOOBYSEUM** (kuratierbares Museum, 4 Flügel) | L | 9,5 | Progression: Belohnung = sichtbare Welt |
| 4 | **B1 Insekten-Album + Käscher** (30–40 Arten, Ort/Zeit/Wetter) | L | 9 | Tägliche Weltveränderung, Monats-Sammelziel |
| 5 | **C1 Jahresfest-Kalender Welle 1** (Laternenfest, Erntedank, Winterlichter + **C2 Silvester-Echtzeit-Countdown**) | L (+S) | 9 | Kalender-Anker, Stadt als Bühne, Besuchs-Termine |
| 6 | **D1 Nachbarschafts-Herzen + Geschenke** (12 Nachbarn, Herz-Geschichten) | L | 9 | Beziehungs-Progression statt Zähler |
| 7 | **G1 Arcade-Reihen-Meisterschaften** (6 reiheneigene Belohnungs-Schienen) | L | 9 | Progression 5,5 (Eval-Prio 11), 38 Spiele neu motiviert |
| 8 | **B4 Angeln 2.0** (Gewässer/Schatten/Legenden, ~45 Arten) | M | 8,5 | Vorhandenes → Monatsziel; Zulieferer Museum/Tiefsee |
| 9 | **F1 Foto-Wettbewerb „Blende & Blubber"** (wöchentlich, async, NPC-Jury offline) | M | 8,5 | Multiplayer 4,5 — ehrlich & out-of-the-box |
| 10 | **F2 Tausch-Post** (Duplikate asynchron tauschen, Escrow) | M | 8,5 | Multiplayer 4,5 × alle neuen Sammlungen |

**Warum dieser Schnitt:**

- **Genau 1 XL** (A1) — die Ranch-Open-World-Tech und das Besuchs-System sind
  wiederverwendbar, das Risiko ist also das kleinste unter den sechs
  XL-Kandidaten; zugleich füttert die Tiefsee 4 weitere Top-10-Punkte
  (Museum, Angeln, Foto, Tausch).
- **Progression zuerst** (#2, #3, #7 direkt aus Eval-Prios 3/11): 6.0 soll die
  5,5 messbar heben, nicht nur Fläche addieren.
- **Multiplayer async** (#9, #10 + Aquarium-/Museums-Besuche aus #1/#3): hebt
  die 4,5 OHNE von der offenen Server-Frage (Eval-Prio 1, Technik-Lens)
  abhängig zu sein.
- **Reserve-Bank für 6.0**, falls Kapazität übrig: E4 Trophäen-Regal (S),
  C2 wäre notfalls solo lieferbar (S), H5 Wetter-Tagebuch (S),
  G2 Wochenpass (M — bewusst NACH C3-Saisons besser).

## 3) Versions-Ausblick (die übrigen XL-Flaggschiffe, Vorschlag)

| Version | Flaggschiff-Kandidat | Begleit-Säule aus dieser Liste |
|---|---|---|
| 7.0 | E1 Villa-Ausbau + E2 Hobbyräume | C3 Jahreszeiten, G5 Kochen, E3 Berufe |
| 8.0 | A3 Café „Herzknuffel" | D3 Brieffreundin, H3 Untermieter, C1 Welle 2 |
| 9.0 | A2 Ski-Resort „Funkelalm" | G3 Parkpass-Winter, H8 Sammelkarten |
| 10.0 | A4 Insel-Resort „Kokoswelle" | G4 Souvenirregal 2.0, F4 Koop-Zettel |
| 11.0+ | A5 Kindergarten / A6 Goobyhof-Vollausbau / H6 GOOB-LUNA-Ausbau | Staffeln 3+, Goobypedia-Vollausbau |

*(Nur Orientierung — Welt-/Technik-Agents und User-Feedback entscheiden.)*
