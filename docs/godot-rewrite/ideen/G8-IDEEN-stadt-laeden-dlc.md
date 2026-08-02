# G8-IDEEN — Stadt, Läden & Laden-DLCs (Ideen-Planner IP-2, Welle I)

**Bereich:** STADT (Orte, NPCs, Leben) + LÄDEN (REHWEI/IKEA/Wochenmarkt/GOOBERANDO/Flughafen)
+ DLCs („Goo und Bye" + „McGooby", beide Welle A spielbar; Ranch-DLC existiert).
**Quellen:** `UserFeedback.md` (komplett), `docs/godot-rewrite/DLC-GOO-UND-BYE.md` +
`DLC-MCGOOBY.md` (inkl. der 20-Perspektiven-Ideensammlungen), Code-Streifzug durch
`GOOBY-GODOT/scripts/city/**`, `scripts/dlc/goobye/**`, `scripts/dlc/mcgooby/**`,
`scripts/shop/ikea_*`, `content/dlc/data/*`, `git log -30`. Nur gelesen, nichts geändert.

**Die zwei User-Kritiken, an denen sich JEDE Idee messen muss (Feedback vom 1.8.):**

1. **„Läden sind zu leer — echte Orte mit animierten Chars!"** — G7/P55 hat das
   wiederverwendbare Ambient-System gebaut (`scripts/city/ambience/ort_leben.gd` +
   `kassen_npc.gd`), aber nur REHWEI und Baumarkt angeschlossen (IKEA bekam das
   Schaufenster `scripts/shop/ikea_schaufenster.gd`). ~10 weitere Orte sind noch stumm.
2. **„Alles fühlt sich wie einzelne Spiele statt EIN Gooby-Spiel an."** — G7/P56 hat die
   MINISPIELE gerahmt. Die Stadt-Dimension fehlt noch: Orte kennen einander nicht,
   Figuren existieren nur in „ihrem" Laden, die DLC-Läden hängen ohne Waren-/Personen-
   Kreislauf neben den Bestandssystemen.

Aufwand als **S/M/L** (Umfang/Risiko/betroffene Systeme, nie Kalenderzeit), Impact **1–5**
(Beitrag zu den beiden Kritiken + Zeig-Wert), Risiko ehrlich mit Gegenmittel.

---

## TOP-3 (Begründung)

**🥇 P1 „Jeder Ort lebt" — Ort-Leben-Rollout auf ALLE Stadt-Orte.** Die direkteste,
billigste und sichtbarste Antwort auf Kritik 1: das P55-System existiert, ist getestet
(`test_g7_ort_leben`) und braucht laut eigenem Docstring **~15–20 Zeilen Konfig pro Ort**.
Zehn Orte warten. Kein neues System, nur Anschluss + ortstypische Würze — maximaler
Effekt pro Zeile, minimales Risiko. Das gehört VOR alles andere.

**🥈 P2 „Der Stadt-Cast" — benannte Stamm-Goobys mit Tagesrouten.** Die strukturelle
Antwort auf BEIDE Kritiken zugleich: dieselben 6–8 benannten Figuren tauchen
deterministisch zu Tageszeiten an verschiedenen Orten auf (morgens REHWEI, samstags
Markt, abends McGooby) — die Stadt wird ein Organismus, und weil die DLC-Kunden
(Alwin, Listen-Gooby, Oma Hoppel …) DERSELBE Cast sind, näht das Stadt und DLCs zu
EINEM Spiel zusammen. Baut vollständig auf P55-Bausteinen auf (pure Pläne + Tages-Seed).

**🥉 P3 „Die Großmarkt-Fahrt" — Goobye Welle B als fühlbares Ritual.** DER
WOW-Ausbau-Moment beider DLC-Docs (GOO-UND-BYE §4.2, User-Wunsch wörtlich: „Ware
transportieren"): Bestellen → mit dem EIGENEN Auto zur Großmarkt-Rampe hinter REHWEI
fahren → Kofferraum ausladen. Ersetzt das abstrakte Nachschub-Sheet der Welle A, gibt
dem Fuhrpark erstmals einen Job und macht den Running-Gag („Gooby kauft beim
Konkurrenten") spielbar. Teuerste der Top-3, aber alle Bausteine existieren
(`fahrer_sim.gd`-Zeitmodell, `city_map.json`-Orte, Garage).

---

## Die priorisierte Liste (P1–P15)

### P1 — „Jeder Ort lebt": Ort-Leben-Rollout auf alle Stadt-Orte

Alle noch stummen Orte bekommen `_leben_konfig()` (Hook existiert in
`scripts/city/ort_scene.gd`, System in `scripts/city/ambience/ort_leben.gd`) plus je eine
eigene Spruch-Domain in `strings/de+en/city_leben.json` — mit ORTSTYPISCHER Würze statt
Copy-Paste: GOOBYTHEKE bekommt eine Wartebank mit Niesen-Gooby (Taschentuch-Requisit),
GOOBYMAN stöbernde Fans, die auf den Umhang-Moment hoffen (`orte/goobyman.gd` hat den
Umhang-Gag schon), die Post eine kleine Paket-Schlange mit Paket-Requisiten, das
Autohaus Kunden, die Autos umkreisen und in Motorräume gucken (Wegpunkte um die
Ausstellungswagen), POW stöbernde Sticker-Fans, der Tierarzt ein Wartezimmer mit
Kuscheltier-tragendem Goobylein, der Flughafen Rollkoffer-Zieher (s. P13). Kassen-Orte
verdrahten `kassen_npc.gd` ans Händler-Sheet (Muster `orte/rehwei.gd::_on_kunde_zahlt`).
**Aufwand:** S–M (pro Ort S; 9–10 Orte, dazu ~8 Spruch-Domains DE/EN + Requisiten-Props).
**Impact:** 5 — die Hauptkritik, flächendeckend beantwortet.
**Risiko:** niedrig. System ist deterministisch + getestet; einziger Wachpunkt ist das
iPhone-Budget bei Orten mit viel Deko (Gegenmittel steckt im System: geteilte
Material-Caches, RM = halbe Besucher statisch).

### P2 — „Der Stadt-Cast": benannte Stamm-Goobys mit Tagesrouten

Ein zentrales `stadt_cast.json` (neu, z. B. `scripts/city/data/`) definiert 6–8 benannte
Figuren mit fester Fellfarbe/Hut/Requisit und **Tagesplan** (Ort × Zeitfenster, Wochentag):
Oma Hoppel morgens REHWEI + samstags Wochenmarkt, Listen-Gooby werktags 17 Uhr, Pendler
18:55 im Laufschritt, Onkel Alwin 8:55 auf dem Weg zum Goobye (s. P16-Anker in P7/P3).
`ort_leben.gd::plaene()` bekommt einen zweiten, additiven Pfad: erst Cast-Mitglieder, deren
Zeitfenster (Zeit-Injektion `clock.gd`, wie `OrtKatalog.ist_offen`) passt, dann wie bisher
anonyme Füll-Besucher — die reine `zustand(plan, sekunden)`-Maschine bleibt unangetastet.
Die Figuren grüßen mit Namens-Sprüchen (eigene `city_leben.sprueche.cast_*`-Keys), und die
DLC-Archetypen (`goobye_markttag.gd`: alwin/listen_gooby/familie/hamster_gooby,
`KUNDEN_TINTE` in `laden_scene.gd`) referenzieren DIESELBEN Cast-Einträge — wer Oma Hoppel
mittags am Markt sah, bedient sie abends im eigenen Laden. **Aufwand:** M (JSON + Planer-
Erweiterung + Sprüche + DLC-Tint-Vereinheitlichung; Golden-Tests nach `tages_seed`-Muster).
**Impact:** 5 — Stadt als Organismus UND Ein-Spiel-Klammer in einem.
**Risiko:** mittel — Zeitfenster-Logik × Determinismus braucht saubere Zeit-Injektion
(Gegenmittel: pure Funktion `cast_vor_ort(cast, ort_id, wochentag, stunde, seed)` mit
Unit-Tests, Anzeige bleibt OrtLeben).

### P3 — „Die Großmarkt-Fahrt": Goobye Welle B als fühlbares Ritual

Das Nachschub-Sheet der Welle A (`scripts/dlc/goobye/laden_scene.gd`, Abschnitt
„Nachschub": 1 Stück je Tap zum EK-Preis) wird zum Erlebnis nach DLC-Doc §4.2: Bestell-Sheet
mit ±-Steppern → Fahrt zur **Großmarkt-Rampe hinter REHWEI** (neuer betretbarer Eintrag
oder Rückseiten-Spawn am REHWEI-Tile `[5,2]` in `scripts/city/data/city_map.json`) →
Kisten-Drag vom Kofferraum (Einräum-ASMR, „Alles ausladen"-Knopf). Selbst fahren = normale
Stadt-Fahrt (`city_scene.gd`); „Loretta schicken" = Abwesenheits-Variante über das
`fahrer_sim.gd`-Zeitmodell (Position/Ankunft = pure Funktion der Save-Timestamps, Feld
`transport.unterwegs` im `dlc.goobye`-Slice nach `goobye_state.gd`-Normalize-Muster).
Kofferraum-Volumen je Auto aus `scripts/home/garage/`-Stats (12/24/48 Kisten) gibt dem
Fuhrpark den ersten WIRTSCHAFTLICHEN Unterschied; Staffelrabatt ab 10 Stück (−5 %) rechnet
`goobye_preis.gd`. Großmarkt-Gooby-Spruch: „Das bleibt unter uns Händlern."
**Aufwand:** L (Sheet-Umbau, Rampen-Kulisse, Transport-Slice + Golden-Tests, Garage-Query).
**Impact:** 5 — der Ausbau-Moment, der aus „Laden-Screen" ein „mein Betrieb"-Gefühl macht.
**Risiko:** mittel — Zentrums-Tiles sind knapp (Doc §10.3-Warnung; Kulisse-Tests mitziehen)
und der Transport-Slice braucht Zeitsprung-Fälle (Gegenmittel: exakt das getestete
`fahrer_sim`/`ranch_offline`-Zeitmuster wiederverwenden).

### P4 — McGooby wird ein ORT: die Schicht bekommt eine Bühne

`scripts/dlc/mcgooby/schicht_scene.gd` ist heute ein reiner `Control`-Screen — genau das
„Dev-Demo"-Gefühl der User-Kritik. Neue 3D-Bühne im Diorama-Stil der Goobye-`laden_scene.gd`:
Theke, Grill mit sichtbarem Patty (Zustandsfarben `FARBE_ROH/GOLDBRAUN/KOHLE` existieren),
goldene Löffel-Bögen im Fenster, 2–3 wartende Gäste via `ort_leben.gd` (Wiederverwendung!),
der Patty-Knopf bleibt als UI-Layer darüber (die pure `schicht_logic.gd` bleibt zu 100 %
unangetastet — nur die Präsentation wächst). Bestell-Gäste treten sichtbar an die Theke,
nehmen ihr Tablett und setzen sich. Der Ort bekommt mittelfristig eine Fassade auf der
`city_map.json` (Eck-Grundstück mit Bögen-Schild, Muster `deko`-Eintrag „ikea").
**Hinweis:** „McGooby-Bühne" steht bereits als neu einsortiertes G6-Paket in
`UserFeedback.md` §2 — diese Idee konkretisiert den Zuschnitt.
**Aufwand:** M–L. **Impact:** 5 — verwandelt das abstrakteste Stück DLC in einen Ort.
**Risiko:** niedrig–mittel (Logik bleibt pure; Risiko nur im Szenen-Layout über 6 Formate —
Gegenmittel: FB3-UiScale-Konformitätstest deckt die Route schon ab).

### P5 — Laden-Umbau sichtbar: Goobye-Ausbaustufe „Minimarkt"

Erster Ausbau-Moment nach DLC-Doc §3.4/§7.1: Für 400 Münzen wächst der Laden von der
Welle-A-Einrichtung (5 Regal-Slots, `GoobyeRegal.neues_regal()`) auf 8 Slots + Obst-Schräge
+ Quengelware-Ständer an der Kasse (Familie-Archetyp nutzt ihn schon:
`goobye_markttag.gd::QUENGEL_CHANCE`). Der Umbau ist ein MOMENT: Vorhang zu,
Gooby-hämmert-Qualm (Ranch-D2-Animation wiederverwenden), Vorhang auf, Kamera-Schwenk über
den größeren Raum; draußen wächst die Fassade (Deko-Tint/Scale-Variante in `city_map.json`).
Kundenzahl skaliert mit: `KUNDEN_MIN/MAX` wandern aus den Szenen-/Logik-Konstanten
(`laden_scene.gd` 2–3, `goobye_markttag.gd` 3–5) in `content/balance/`-Daten je Ausbaustufe.
**Aufwand:** M. **Impact:** 4–5 — „mein Laden WÄCHST" ist der Kern-Sog des Genres.
**Risiko:** niedrig (additiver Slice-Unterschlüssel `laden.level` mit Normalize;
Regal-Persistenz übernimmt das bewährte `_bestand_sichern()`-Muster).

### P6 — Kundenwünsche & Schwarzes Brett (Goobye)

Die freundliche Interaktions-Schicht aus DLC-Doc §6.4: pro Markttag hat 1 Kunde ein
„?"-Wölkchen („Wo ist das Glitzersalz?" → Tap = hinführen) oder einen SORTIMENTS-Wunsch
(„Habt ihr auch Kartoffeln?") — der als Zettel am Schwarzen Brett landet (neues
`wuensche`-Feld im `dlc.goobye`-Slice). Listet man die Ware binnen 3 Markttagen, kommt der
Wunsch-Kunde wieder, kauft demonstrativ 3 Stück und lässt ein Sticker-Tütchen da.
Deterministisch bleibt alles: der Wunsch wird aus dem bestehenden Los-Block gezogen
(`goobye_markttag.gd::_lose_ziehen` bekommt +2 Lose pro Kunde — Achtung, Golden-Tests
bewusst mitziehen). Das Brett ist zugleich der organische Kompass, WELCHE Ware man als
Nächstes listet — Sortiments-Ausbau ohne Menü-Tutorial.
**Aufwand:** M. **Impact:** 4 — Kunden werden Personen mit Anliegen statt Bon-Abarbeiter.
**Risiko:** niedrig–mittel (Los-Block-Änderung invalidiert Golden-Values — einmalig
neu einfrieren, Monotonie-Beweis erneut laufen lassen).

### P7 — „Bio vom Gooby-Beet": der Waren-Kreislauf Garten ↔ Laden ↔ Kühlschrank

Der stärkste Ein-Spiel-Hebel unter den Cross-Ideen, und er ist BILLIG, weil die IDs schon
deckungsgleich sind (`content/dlc/data/goobye_sortiment.json` nutzt per Kommentar dieselben
Waren-IDs wie `scripts/city/data/rehwei_sortiment.json` und damit `food_catalog.gd`):
(a) Garten-Ernte lässt sich ins Goobye-Lager einliefern (Regal-Zeile „Bio vom Gooby-Beet",
+10 %-Aufschlag rechnet `goobye_preis.gd::empfohlener_preis` über das vorhandene
`bio`-Flag); (b) Privatentnahme aus dem eigenen Regal wandert als echtes Lebensmittel in
`inventory.food` — Kassen-Spruch „Das schreib ich an, Chef." (Kassen-NPC-Anker P55);
(c) der Kräuterkasten-Craft (liefert seit W15 wöchentlich Markt-Ware) darf wahlweise ins
Laden-Lager liefern. Ernte → Regal → Verkauf an Oma Hoppel → ihr Bon piept die
Gemüse-Tonhöhe (`GoobyeKatalog.ton_fuer`): ein Kreislauf, den man HÖRT.
**Aufwand:** S–M. **Impact:** 5 — Garten-Großanbau bekommt erstmals ökonomischen Sinn
(Stardew-Perspektive #13 der Ideensammlung), drei Bestandssysteme greifen ineinander.
**Risiko:** niedrig (reine Bestands-Verschiebung über die vorhandenen State-APIs;
Erhaltungssatz-Test nach dem Muster des bestehenden „Lager-Erhaltungssatzes").

### P8 — Zufallsereignisse für Stadt & Läden (Kontext „city"/„goobye")

Die Random-Event-Engine hat seit W13 ein Kontext-Tor (`scripts/events/random_events.gd`,
`context`-Feld, Ranch nutzt es) — Stadt und Läden docken an: **Krähen-Ladendiebe** an
Goobyes Obst-Schräge (15-s-Tap-Abwehr, verpasst = Foto-Gag statt Strafe, DLC-Doc §8.1 —
dieselbe Bande wie im Garten: stadtweiter Running-Gag), **Straßenmusiker-Gooby** am
Kreisel-Tile (Publikum sammelt sich, Münze werfen = kurzes Ständchen), **Bollerwagen
rollt weg** vor REHWEI (aufhalten!), **Möwen-Überfall** am Flughafen-Vorplatz,
**Klopapier-Turm-Umbau** bei GOOBYMAN. Events kündigen sich über Ort-Leben-Besucher an
(die Ambient-Goobys gucken alle in dieselbe Richtung, BEVOR das Event-Icon erscheint —
Weltwissen statt UI).
**Aufwand:** M (5–6 Event-Defs + je ein kleiner Szenen-Moment; Engine steht).
**Impact:** 4 — „bei jedem Besuch kann etwas passieren" ist Organismus-Gefühl pur.
**Risiko:** niedrig (Zeitfenster-Gags ohne Fail-State nach Ranch-H3-Regel).

### P9 — Jahreszeiten-Feeling: der Saison-Layer der Stadt

Die Stadt kennt Tag/Nacht + Wetter (`city_ambiente.gd::licht_profil`, W13-Wetter), aber
kein Jahr. Ein Monats-Filter für Deko-Einträge (`city_map.json` `deko[]` bekommt optional
`"monate": [10]`) + ein kleiner Saison-Katalog in `city_bau.baue_deko()`: Oktober =
Kürbis-Stapel vor REHWEI + Laub-Tint der Straßenbäume, Dezember = Lichterketten über der
Zentrums-Straße + beleuchtete Schaufenster, Frühling = Blüten-Bäume am Park, Sommer =
Wimpel + Eis-Stand am Wochenmarkt. Läden ziehen mit: REHWEI-Saatgut-Abschnitt rotiert
saisonal, das Goobye bekommt das „Kürbis-Oktober"-Regal als Content-Pack-Beispiel
(Live-Ops-Pfad aus DLC-Doc §4.1/§10.2), der Wochenmarkt einen Saison-Sonderstand.
Deterministisch über die Zeit-Injektion — Screenshots/Tests pinnen den Monat.
**Aufwand:** M. **Impact:** 4 — Wiederkommen fühlt sich anders an als gestern; AC-Kern.
**Risiko:** niedrig–mittel (Draw-Call-Budget der Stadt ≤ 400 im Blick behalten;
Saison-Deko als MultiMesh-Gruppen wie die bestehende Kulisse).

### P10 — Orte verweisen aufeinander: Dialog-Querverweise + Botengänge

Die Dialogbäume (`scripts/city/data/dialoge/*.json`) sind heute Ort-Inseln. Ein
Querverweis-Pass gibt jedem Händler 1–2 Zeilen über NACHBARN, teils zustandsbewusst über
die vorhandenen `city.flags`/Zeit-Checks: Frau Rehwald samstags: „Heute ist Markt — da
steh sogar ICH am Stand von nebenan."; Hilde (GOOBYTHEKE) verweist Schnupfen-Goobys zum
Tierarzt; der Baumarkt schwärmt vom IKEA-Katalog; Alwin erzählt im Goobye von seiner
Kreuzfahrt-Postkarte, die bei der POST liegt. Dazu 2–3 **Mini-Botengänge** als
Dialog-Effekt-Ketten (Muster `_on_dialog_effekt` „item"/„flag" in `ort_scene.gd`):
Paket von der Post zu Frau Rehwald bringen → 10 Münzen + Anekdote. Keine Quest-UI,
keine Marker — markerlos im Geiste der Ranch-B5-Regel.
**Aufwand:** S–M (reine Daten + 1 Effekt-Typ „botengang"). **Impact:** 4 — die Stadt
beginnt, über sich selbst zu reden; billigster Ein-Spiel-Kleber überhaupt.
**Risiko:** niedrig (DE/EN-Parität mitpflegen — `EXPECTED_DOMAINS`-Lernkurve beachten).

### P11 — Stammkunden-Gedächtnis: die Läden kennen Gooby

Umkehrung von P6 — nicht der Laden hat Stammkunden, sondern GOOBY IST einer: ein
Kauf-Zähler je Ort (additiv im `city`-Slice neben `besucht`, Muster
`OrtKatalog.besuch_merken`) schaltet Begrüßungs-Stufen frei: ab 5 Käufen grüßt Frau
Rehwald mit Goobys Namen, ab 10 legt sie „das Übliche" (meistgekaufte Ware,
1-Tap-Nachkauf-Knopf im `haendler_sheet.gd`) bereit, ab 20 gibt's einmalig eine
Treue-Möhre + Sticker-Fortschritt. GOOBYMAN wirft den Umhang dann schon bei 3 Artikeln.
Jeder Laden bekommt so Identität ohne neue Systeme — nur Erinnerungs-Zeilen + ein Knopf.
**Aufwand:** S. **Impact:** 3–4 — kleine Ursache, großes „der Ort kennt mich"-Gefühl.
**Risiko:** sehr niedrig (Zähler + Dialog-Varianten; Normalize-Self-Heal wie gehabt).

### P12 — GOOBERANDO ↔ eigene Läden: „Der Koch sieht Ihnen ähnlich."

McGooby wird 4. Eintrag in `scripts/city/data/gooberando_restaurants.json` (sichtbar nach
der ersten gespielten Probeschicht; Gerichte = FoodCatalog-taugliche Parodien wie `burger`
+ `fries` zu McGooby-Preisen, Fahrer-Startknoten = künftiges McGooby-Tile bzw. übergangsweise
die `gooberando_kueche`). Bestellt Gooby bei sich selbst, kommentiert die App
(„Der Koch sieht Ihnen ähnlich."), und der Liefer-Gooby holt SICHTBAR am eigenen Laden ab
(`fahrer_sim.gd` fährt ab dem Laden-Knoten — exakt DLC-MCGOOBY §9.1). Später derselbe
Pfad fürs Goobye („Goo&Go"-Einkaufskorb, GOO-UND-BYE §4.5.2). Zwei W13-Systeme, ein Loop —
und GOOBERANDO, heute reine Konsum-App, wird Teil des eigenen Wirtschafts-Organismus.
**Aufwand:** S–M. **Impact:** 4 — der überraschendste „alles hängt zusammen"-Moment.
**Risiko:** niedrig (Restaurants sind Daten; einzig der Fahrer-Startknoten braucht einen
gültigen Straßen-Anschluss — `naechste_strasse`-Fallback existiert).

### P13 — Abflughalle lebt: Flughafen-Momente + GOOBY-FREE-Theater

Der Flughafen (`scripts/city/orte/flughafen.gd`) hat Reise-Schalter, Flap-Board und den
GOOBY-FREE (öffnet nur mit Abflug-Buchung, `gooby_free_offen()`) — aber keine Menschen…
äh, Goobys. Drei Handgriffe: (a) `_leben_konfig()` mit Rollkoffer-Requisit (Koffer-Prop
am Besucher-Node, wie der P55-Hut) und Wegpunkten Schalter → Board → Gate; (b) das
Flap-Board (`travel/flap_board.gd`) mischt zwischen echte Ziele Gag-Zeilen („GOO-23 nach
Melonien: Boarding", „Vermisst: 1 linker Söckchen, Gate 2"); (c) einmal pro Besuch rennt
ein Zu-spät-Gooby in Zeitlupe durchs Bild Richtung Gate (der Eilige-Pendler-Gag der
DLC-Kunden-Castings, hier als Ambient-Moment). Der GOOBY-FREE-Verkäufer kommentiert
Duty-Free-Käufe kennerhaft („Der Mondstein. Ausgezeichnete Wahl. Völlig nutzlos.").
**Aufwand:** S. **Impact:** 3–4 — der Ort mit der größten Vorfreude-Funktion (Urlaub!)
bekommt endlich Reisefieber-Atmosphäre.
**Risiko:** sehr niedrig (alles P55-Bausteine + Textzeilen).

### P14 — Wochenmarkt-Samstag als Wochen-Höhepunkt

Der Markt ist der einzige Ort mit Öffnungsregel (Sa 8–14, `ort_katalog.gd`) und hat seit
W15 den Eigenstand (`markt/markt_sim.gd` mit Tagestrend „Heute lieben alle Kürbisse!") —
aber die Woche ARBEITET nicht auf ihn hin. Drei Verstärker: (a) Freitagabend-Vorfreude:
Gooby-Selbstgespräch + optionaler sanfter NotifyScheduler-Gruß („Morgen ist Markt!");
(b) der Tagestrend wird STADT-Wissen: Ambient-Besucher in REHWEI/Goobye zitieren ihn
freitags als Gerücht („Ich hör, morgen sind Kürbisse DER Renner") — wer hinhört, bestückt
den Stand richtig (Belohnung fürs Zuhören, kein Menü-Hinweis); (c) Stand-Nachbarn
reagieren auf den Verkaufserfolg (ab 10 Verkäufen applaudiert der Nachbar-Händler,
der Trend-Treffer gibt eine Extra-Anekdote am Abrechnungs-Ende). Ein Wochen-Rhythmus
entsteht: säen → gießen → Freitag lauschen → Samstag ernten.
**Aufwand:** S–M. **Impact:** 4 — Jahreszeiten im Kleinen: die WOCHE bekommt Gestalt.
**Risiko:** niedrig (Trend existiert deterministisch; nur Sichtbarkeit + 2 Momente).

### P15 — Die Kassen-Melodie wird Stadt-Grammatik

Das Goobye hat das Audio-Juwel: Warengruppen-Tonhöhen (`ton` in
`content/dlc/data/goobye_sortiment.json`, `GoobyeKatalog.ton_fuer`, Bon = Melodie).
REHWEI piept dagegen monoton (`kassen_npc.gd::PIEP_ID ui_coins` fix). Der Rollout: 
`KassenNpc.kunde_zahlt()` nimmt optional eine Tonhöhe, und jeder Laden piept fortan
SEINE Sortiments-Töne (REHWEI = Lebensmittel-Töne wie Goobye, GOOBYMAN eine Quinte
tiefer, POW poppig hoch, GOOBY-FREE flüstert). Wer durch die Stadt shoppt, hört überall
Verwandtes — und erkennt beim ersten Goobye-Kassensturz die Sprache sofort wieder
(Ein-Spiel-Gefühl auf der Audio-Ebene, AUDIO-GRAMMATIK-konform: Pitch-Reihe 0.9–1.6).
Dazu 1 Gag: scannt man bei REHWEI 3 Waren derselben Gruppe hintereinander, summt Frau
Rehwald den Dreiklang nach.
**Aufwand:** S. **Impact:** 3 — klein, aber genau die Sorte Liebe-zum-Detail, die der
User seit W13 einfordert.
**Risiko:** sehr niedrig (ein Parameter + Daten-Mapping; Bestands-Sound-Ids).

---

## Abhängigkeits-Hinweise für den Konsolidierer (Welle J+)

- **P1 vor P2:** der Cast (P2) spawnt über die P1-Konfigurationen; P1 allein ist schon
  ein kompletter sichtbarer Gewinn.
- **P3 + P5 + P6 bilden zusammen „Goobye Welle B"** (deckungsgleich mit dem
  Wellen-Schnitt W-B in DLC-GOO-UND-BYE §10.5); P7 ist unabhängig davon sofort machbar.
- **P4 vor P12** (der GOOBERANDO-Abholer braucht einen McGooby-Ort, von dem er abfährt —
  übergangsweise tut es die bestehende `gooberando_kueche`).
- **Golden-Test-Vorsicht:** P6 (Los-Block) und P5 (Kundenzahl aus Balance) verändern
  deterministische Pläne — Golden-Values bewusst NEU einfrieren, Monotonie-Beweis
  (`goobye_markttag`) erneut laufen lassen.
- **Performance-Wache:** P1/P2/P9 erhöhen die sichtbare Dichte — Draw-Call-Budget-Tests
  der Stadt (≤ 400) und der Ort-Szenen mitziehen; alle drei Ideen sind bewusst auf den
  P55-Sparprinzipien (geteilte Materialien, berechnete Positionen, RM-Degradierung) gebaut.
