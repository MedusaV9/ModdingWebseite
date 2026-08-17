# GOOBY Riesen-Bewertung 2026-08 — Lens B: Visuals & Welt

Stand: 8. August 2026, Branch `cursor/gooby-godot-loop-2-d1d8`, nach W21.

## Schonungslos kurzes Urteil

**Lens-B-Gesamtscore: 4,0/10. Welt allein: 3,2/10.**

GOOBY hat inzwischen viel Inhalt, aber die Welt sieht noch nicht wie ein
fertiges Cozy-Spiel aus. Sie sieht überwiegend wie ein technisch
funktionsfähiger Low-Poly-Prototyp mit unterschiedlich weit polierten Inseln
aus. Die stärksten Bilder sind einzelne Hausräume und `toyRacer`; die
schwächsten sind Hufingen, die Ranch-Fernansichten und Funkelpark.

Der Kernfehler ist nicht die reine Polygonzahl. Es fehlen:

- visuelle Hierarchie zwischen Großform, Landmarke und Kleindeko;
- glaubwürdige Materialreaktion und kontrollierte Belichtung;
- sichtbares Leben in Form von Figuren, Tieren, Tätigkeiten und Bewegung;
- dichte, handgesetzte Übergangszonen statt großer prozedural wirkender Felder;
- ein einheitliches Qualitätsniveau zwischen Welt, Orten und Minispielen.

Gegen den Anspruch **„Animal Crossing: New Horizons Cozy-Vibe“** liegt GOOBY
visuell derzeit etwa **vier Qualitätsstufen** zurück: ACNH baut kleine,
handkuratierte Räume voller Material-, Bewegungs- und Bewohnergeschichten;
GOOBY zeigt häufig große Flächen, wiederholte Assets und Beschriftungen anstelle
von lesbaren Orten.

## Methode und Grenzen

- Alle Belege wurden in dieser Runde neu aus dem aktuellen Branch gerendert.
- Haus, Stadt, Ranch, Hufingen, Funkelpark und sieben Minispiele liefen über
  die vorhandenen echten Szenen- und Capture-Werkzeuge.
- HUD und Profil wurden zusätzlich in den exakt angeforderten physischen
  Formaten **2340×1080** und **2048×1536** mit passender Punkt-Skalierung und
  Safe-Area-Simulation gerendert.
- Renderer: `gl_compatibility` unter `xvfb` gemäß den vorhandenen
  Capture-Werkzeugen. Deshalb bewerte ich kein mögliches Vulkan-exklusives
  Bloom-/DoF-Plus. Komposition, Dichte, Farben, Geometrie, Maßstab und UI sind
  trotzdem belastbar sichtbar.
- Die 20 kuratierten PNGs liegen unter `shots/`; jedes ist kleiner als 400 KB.
  `01_house_rooms_montage.png` montiert vier unveränderte Raum-Captures.

## Scorecard

`Geo sauber` bedeutet: kein offensichtliches Clipping, Schweben, falscher
Maßstab oder störende Übergangskante. Ein hoher Wert ist gut.

| Szene | Komposition / Dichte | Licht / Stimmung | Material / Farbe | Geo sauber | UI darüber | Gesamt |
|---|---:|---:|---:|---:|---:|---:|
| Haus — vier Innenräume | 6,2 | 4,2 | 4,6 | 5,5 | 5,7 | **5,1** |
| Haus — Baumodus | 4,8 | 4,0 | 4,2 | 3,5 | 5,3 | **4,4** |
| Garten + Haus außen | 2,5 | 3,5 | 3,5 | 4,0 | 5,0 | **3,4** |
| Stadt — Tag | 3,8 | 4,0 | 3,4 | 4,4 | 4,0 | **3,9** |
| Stadt — Nacht | 4,2 | 5,2 | 3,8 | 4,5 | 4,5 | **4,4** |
| Stadt — begehbare Orte | 4,0 | 3,8 | 4,0 | 4,7 | 5,0 | **4,3** |
| Ranch — Fernsicht | 2,0 | 2,8 | 2,4 | 4,0 | 5,0 | **2,8** |
| Ranch — Bergmassiv | 3,5 | 3,2 | 2,6 | 3,8 | 5,3 | **3,5** |
| Ranch — Zonen | 3,8 | 3,0 | 3,2 | 4,0 | 5,2 | **3,7** |
| Ranch — Hufingen | 2,0 | 2,3 | 2,8 | 3,5 | 5,0 | **2,6** |
| Funkelpark | 3,0 | 3,2 | 3,2 | 3,3 | 4,0 | **3,1** |
| Minispiel — GvZ | 4,0 | 4,0 | 4,2 | 4,4 | 5,0 | **4,3** |
| Minispiel — Tea Party | 6,4 | 5,8 | 5,7 | 5,6 | 5,8 | **5,9** |
| Minispiel — Ranch Herde | 4,8 | 4,5 | 4,3 | 5,0 | 5,5 | **4,8** |
| Minispiel — Memory | 5,2 | 4,8 | 5,3 | 5,3 | 5,8 | **5,3** |
| Minispiel — Runner | 5,2 | 3,6 | 3,2 | 3,8 | 5,2 | **4,2** |
| Minispiel — Toy Racer | 6,8 | 6,0 | 6,3 | 5,2 | 5,9 | **6,1** |
| iPhone 2340×1080 — Home-HUD | 5,2 | 5,0 | 5,8 | 4,5 | 4,1 | **4,8** |
| iPhone 2340×1080 — Profil | 5,8 | 5,5 | 6,0 | 5,5 | 5,9 | **5,8** |
| iPad 2048×1536 — Home-HUD | 6,3 | 5,8 | 6,2 | 6,0 | 5,8 | **6,0** |
| iPad 2048×1536 — Profil | 6,6 | 6,0 | 6,4 | 6,3 | 6,5 | **6,4** |

## Szenenbewertung

### 1. Haus: stärkster Weltbereich, aber zu hell und zu beige

Beleg: `shots/01_house_rooms_montage.png`,
`shots/02_house_build_mode.png`, `shots/03_garden_house_exterior.png`.

**Komposition/Dichte:** Das Wohnzimmer hat eine brauchbare Cozy-Grundform:
Sitzgruppe, Teppich, Bücher, Pflanze und Gooby bilden ein Zentrum. Küche und
Bad haben erkennbare Funktionen. Das Schlafzimmer bleibt trotz Möbeln leer,
weil Kartons, Teppich und Türen nicht zu einer Geschichte gruppiert sind.

**Licht/Stimmung:** Alle Räume laufen nahe an Weiß. Im Bad verschwinden
Waschbecken, Toilette und Wanne fast im Hintergrund. Küche und Wohnzimmer
haben kaum Kontakt- oder Eckenabdunklung; Möbel wirken dadurch leicht und
unverankert. Das Licht ist „hell“, aber nicht „warm“.

**Material/Farbe:** Holzfußboden und Türen sind die stärksten Materialien.
Fast alle übrigen Oberflächen teilen sich Creme, blasses Rosa und Weiß. Stoff,
Keramik, Metall, Holz und Kunststoff reagieren zu ähnlich. Das ist Pastell,
aber nicht die taktile ACNH-Materialvielfalt.

**Geometrie/Skala:** Die sehr hohen, dunklen Türen dominieren mehrere Räume.
Im Baumodus liegen außerhalb des Zimmers weiße Zaun-/Pfostensegmente und
braune Rechtecke ohne lesbaren Zusammenhang. Die Kulisse wirkt zerlegt statt
wie ein Grundstück. Die Dachbalken aus den Zusatzcaptures schneiden den Blick
stark.

**UI-Lesbarkeit:** Das neue Baumodus-Dock ist grundsätzlich lesbar und
ruhiger als ein Vollbildmenü. Es konkurriert aber mit vier Randknöpfen und den
Layer-Chips. Die Außenansicht verwendet ein sehr breites, inhaltsarmes Panel,
das fast das gesamte untere Bild abschneidet.

**Garten außen:** Das Hausmodell ist als Symbol lesbar, aber die Szene endet
direkt hinter Zaun und Wiese in einer hellblauen Leere. Kein Nachbargrundstück,
Baum, Hügel, Himmelshorizont oder Straßenbezug bindet das Haus an eine Welt.
Das ist ein Showroom, kein Zuhause.

### 2. Stadt: mehr Assets, aber Ortsidentität kommt aus Text

Beleg: `shots/04_city_day_street.png`, `shots/05_city_night_street.png`,
`shots/06_city_weekly_market.png`.

**Komposition/Dichte:** Der Straßenraum hat Fahrbahn, Bäume, Laternen,
Pflanzinseln und Gebäude. Trotzdem ist die Mitte leer und die Seiten sind
ungeordnet. Es fehlen Schaufensterfronten, Eingänge, Vorplätze und
Fußgängergruppen als Blickanker.

**Licht/Stimmung:** Nacht ist klar stärker als Tag. Dunkler Himmel, Regen,
Laternen und Scheinwerfer geben endlich eine Stimmung. Tagsüber überstrahlen
Gehwege und Pflanzenflächen; Fassaden verlieren Kanten und Tiefe.

**Material/Farbe:** Die Pastellpalette ist grundsätzlich passend. Viele Häuser
sind jedoch nur unterschiedlich gefärbte Quader mit identischen Fenster- und
Sockelmustern. Die Stadt wirkt dadurch wie ein Baukasten, nicht wie zwölf
eigene Orte.

**Geometrie/Skala:** Riesige schwebende 3D-Namen überlagern sich bereits in
Straßenhöhe und werden in der Übersicht unlesbar. `REHWEI`, `GOOBYTHEKE`,
`Baumarkt Bodo Balken` und weitere Labels ersetzen echte Fassadenkommunikation.
Die Schrift ist teilweise größer als Geschosse. Einzelne Grün-Cluster wirken
auf weißen Gehwegflächen ausgesät.

**Leben:** In der Verkehrsaufnahme sind Autos sichtbar, aber fast keine
Fußgänger. Kein Laden hat vor der Tür Wartende, Lieferungen, Fahrräder,
Einkaufswagen oder sichtbare Tätigkeiten. Selbst wenn Systeme für NPCs
existieren, tragen sie das Bild nicht.

**Orte:** Der Wochenmarkt hat Kisten und Gemüse, aber das große Sheet verdeckt
den Ort. POW, Baumarkt und Post zeigen in weiteren Captures viel freie Fläche,
Kisten und wenige Props hinter einer generischen Cremefläche. Ein Ort sollte
vor dem Öffnen des Menüs interessant aussehen.

### 3. Ranch: größte Fläche, größtes visuelles Defizit

Beleg: `shots/07_ranch_mountain_bridge.png`,
`shots/08_ranch_lavender_zone.png`, `shots/09_ranch_village_plaza.png`.

**Komposition/Dichte:** Die Ranch-Fernsicht ist fast vollständig gleich helles
Grün. Wege, Bäume, Gebäude und Gewässer werden zu dünnen Linien bzw. Punkten.
Zwischen „nichts“ und „ein Asset“ fehlt die mittlere Dichteebene: Hecken,
Felsgruppen, Geländekanten, Zaunzüge, Baumhaine, kleine Höfe und
Vegetationssäume.

**Licht/Stimmung:** Der Boden ist häufig neonhell, während Himmel und
Hintergrundberge grau-blau bleiben. Das Bild hat keinen gemeinsamen
Farb-/Belichtungsraum. Schatten helfen lokal, lösen den großflächigen
Überstrahlungscharakter aber nicht.

**Material/Farbe:** Gras zeigt ein stark wiederholtes, kontrastreiches Muster.
Der Bergsee zeigt eine punktartige Rasterstruktur. Wege sind fast weiß und
dadurch heller als alle Landmarken. Bäume wiederholen dieselbe türkise
Low-Poly-Krone in großer Zahl.

**Bergmassiv:** Das Gelände ist real vorhanden, doch der Berg liest sich eher
als glatter Hügel. Die Hängebrücke ist ein guter Landmarkenansatz; ihre
überhellen, groben Bretter, dünnen Seile und die leere Schlucht verkaufen die
Höhe nicht. Felsen, Geröll, Vegetationswechsel und atmosphärische Tiefe fehlen.

**Zonen:** Lavendelwiese, Kornfeld, Moor und Obstgarten unterscheiden sich
hauptsächlich durch ein wiederholtes Streu-Asset. Das ergibt Farbe, aber keine
Ortsgeschichte. Die Lavendelreihen sind zu regelmäßig und reichen bis zum
Horizont ohne Hof, Bienenhaus, Arbeiter, Zaun oder Baumgruppe als Ziel.

**Hufingen:** Das Dorf ist der klarste Alpha-Look des Spiels: drei bis fünf
weit auseinander stehende Scheunen, eine ausgebleichte Kreisfläche, ein
Brunnen und fast keine Figuren. Die weiße Plaza überstrahlt. Zwischen den
Gebäuden fehlt alles, was Dorfleben erzählt: Markt, Pferde, Karren,
Werkstücke, Sitzgruppen, Zäune, Schilder, Wäsche, Gärten, Rauch, Licht und
Bewohnerpfade.

**Skala/Lesbarkeit:** Pferd/Reiter wirken in der riesigen Landschaft klein wie
ein Spielzeug. Wegweisertexte und Dorf-Namensschilder schweben bzw. stapeln
sich im Sichtzentrum. Der Button „Zum Hof“ ist gut lesbar, aber die Welt unter
ihm nicht stark genug.

### 4. Funkelpark: vollständig erkennbar, aber visuell ein Whitebox-Diorama

Beleg: `shots/10_funkelpark_plaza.png`.

**Komposition:** Riesenrad, Achterbahn, Karussell, Kasse und Autoscooter sind
in einer Totale vorhanden. Das ist funktional lesbar. Gleichzeitig liegen sie
auf einer kleinen, rechteckigen Insel im hellblauen Nichts.

**Material/Geometrie:** Die Achterbahn ist ein rotes Band auf weißen Stützen,
ohne überzeugende Schienen, Schwellen, Plattformen oder Warteschlange. Das
Riesenrad besteht aus sehr dünnen Speichen und simplen Farbwürfel-Gondeln.
Kasse und Schild wirken wie Editor-Primitives. Der Park hat keine
Randbebauung, Bäume, Zäune oder Skyline.

**Leben/Stimmung:** Keine Besuchergruppe, keine Warteschlange, kein
Mitarbeiter, keine wehenden Fahnen, kein Dampf, Popcorn, Konfetti oder
Fahrgeschäft-Lichtmuster belebt die Totale. Der Nachtcapture ist dunkler, aber
nicht festlicher. Ein Freizeitpark ohne Menge und Bewegung wirkt geschlossen.

**UI:** Oben steht eine lange Textzeile direkt über der Welt; in weiteren
Ride-Captures läuft Text bis an den Rand. Die Parkinformation braucht eine
kompakte, sichere Lane statt einer losen Überschrift.

### 5. Minispiele: sechs verschiedene Qualitätsstufen

Belege: `shots/11_mg_gvz.png` bis `shots/16_mg_toy_racer.png`.

- **GvZ (4,3):** Das Spielfeld ist beim Intro groß und leer. Gezeichnete
  2D-Goobys/Zombies passen stilistisch nicht zu den 3D-Häuschen und Bäumen.
  Karten unten links sind winzig und wirken wie Fremd-UI.
- **Tea Party (5,9):** Beste Innenrauminszenierung. Tisch, Figur, Küche,
  Wimpel und Props bilden Tiefe. Trotzdem sind Beige-/Cremeflächen
  überbelichtet und der Hinweis unten liegt knapp am Rand.
- **Ranch Herde (4,8):** Mechanik ist sofort lesbar, aber Weide, Büsche,
  Schafe und Zaun sind sehr gleichmäßig und flach. Es fehlt ein echter
  Ranch-Hintergrund.
- **Memory (5,3):** Saubere Spielfläche und klare Karten, aber viel leeres
  Grün. Der Tisch wirkt wie eine flache Texturfläche statt ein Objekt in
  einer Szene.
- **Runner (4,2):** Gute Fluchtlinie, doch Bäume sind nahezu schwarz und
  verdecken große Bildbereiche. Gebäude wiederholen sich, Vegetation wirkt
  zufällig angeklebt.
- **Toy Racer (6,1):** Stärkstes Minispiel. Kurve, Konkurrenten, Zimmerprops
  und farbige Fahrbahn erzeugen Vorder-/Mittel-/Hintergrund. Die Autos
  berühren/überlappen sich sehr eng, und das linke Rundepanel ist groß, aber
  das Bild hat tatsächlich Energie.

Der gemeinsame Host-Rahmen hilft der UI-Kohärenz. Er kann aber nicht
kaschieren, dass Bühnenmaterial, Licht und Assetqualität von Spiel zu Spiel
stark springen.

### 6. HUD und Menüs in den zwei Zielgeräten

Belege: `shots/17_ui_iphone_hud_2340x1080.png`,
`shots/18_ui_iphone_profile_2340x1080.png`,
`shots/19_ui_ipad_hud_2048x1536.png`,
`shots/20_ui_ipad_profile_2048x1536.png`.

**iPhone quer:** Die Welt füllt das Bild, aber linke Statleiste, sechs rechte
Aktionsknöpfe, Auge unten, Lupe unten und Sprechblase belegen gleichzeitig
sehr viel Randfläche. Die sichtbare Sprechblase endet bei „Kannst du kurz be“:
optisch genau der alte mitten-im-Satz-Abbruch. Selbst wenn der Text
weitergetippt wird, ist dieser Zwischenzustand nicht präsentationsreif.

**iPad quer:** Das Layout atmet deutlich besser. Die Questkarte oben rechts
und die Randaktionen bleiben getrennt; Gooby und das Zimmer sind klarer
lesbar. Die Statleiste links ist dennoch visuell schwerer als nötig.

**Profil:** Das iPad-Raster funktioniert besser als das extrem flache
iPhone-Fenster. Typografie und cremefarbene Karten sind kohärent, aber das
Profil besteht überwiegend aus Text auf großen hellen Flächen. Ein ACNH-Pass
würde Stempel, Materialtextur, handschriftliche Details, Sticker und stärkere
visuelle Gruppierung nutzen. Auf dem iPhone ist fast nur die erste Karte
sichtbar; die Szene wirkt wie ein Formular.

## Welt-Fokus: Wo konkret Leben fehlt

| Bereich | Fehlendes sichtbares Leben | Fehlende Landmarken | Wiederholung / Übergangsbruch |
|---|---|---|---|
| Haus/Garten | Vögel, Insekten, Wind, Nachbarn, Straßenbewegung, Rauch, Gartenarbeit | markanter Baum, Veranda, Gartenbogen, Nachbarblick | Garten endet in blauer Leere; Zaun-/Kulissenteile wirken zerlegt |
| Stadt | dichte Fußgängergruppen, Ladenkunden, Lieferungen, Radfahrer, Bushaltestellen-Aktion | echte Fassadenikonen, Uhrturm, Plaza, Fluss/Brücke, Parkpavillon | gleiche Quaderhäuser; riesige Textlabels kollidieren; Stadtrand fällt ins leere Grün |
| Ranch | Herden, Wildtiere, Reiter, arbeitende NPCs, Wind in Feldern, Staub, Wasserbewegung | echte Felsgipfel, Wasserfall, Hofsilhouette, Ruinenkomplex, markante Baumgruppen | identische Bäume/Streuassets; Zonen wechseln über Farbe statt Übergang; Fernsicht ist neonleer |
| Hufingen | Bewohnerwege, Pferde, Schmiedearbeit, Markt, Karren, Schornsteinrauch | Rathaus/Scheune, zentraler großer Baum, Stallgasse, Dorfportal | Gebäude stehen isoliert; weiße Plaza schneidet hart ins Gras |
| Funkelpark | Besucher, Warteschlangen, Personal, fahrende Attraktionen in der Totale, Partikel | beleuchtetes Eingangstor, Achterbahnstation, zentrales Schloss/Zelt | rechteckige Insel endet im Himmel; Attraktionen bestehen aus dünnen Primitives |
| Minispiele | Publikum, Reaktionen, Hintergrundbewegung, stärkere Treffer-/Kontaktspuren | je Spiel ein ikonischer Bühnenanker | stark schwankende Asset-/Lichtqualität trotz gemeinsamem Rahmen |

**Sound-Sichtbarkeit:** Audio selbst ist aus Screenshots nicht zu benoten.
Visuell fehlen aber fast überall die Quellen, die Sound glaubhaft machen:
wehende Blätter, Motorabgas, Hufstaub, Ladenklingel/Schiebetür, Menschenmenge,
Wasserbewegung, Schmiedefunken, Achterbahn-Warteschlange. Ein Klangbett kann
eine unbewegte, leere Szene nicht lebendig aussehen lassen.

## Konkretes Delta zu Animal Crossing: New Horizons

| ACNH-Qualität | GOOBY jetzt | Sichtbares Delta |
|---|---|---|
| Kleine, handkuratierte Sichtkegel | sehr große, offene Flächen | Kamerawege enger führen; Dichte in Schichten bauen |
| Materialien unterscheiden sich taktil | viele Oberflächen teilen Creme/Grün und ähnliche Roughness | Materialbibliothek nach Stoff/Holz/Metall/Keramik/Laub/Wasser |
| Jede Zone hat ein ikonisches Motiv | Zonenname und Streufarbe tragen die Identität | 1 Hero-Landmarke + 3 Nebenmotive pro Zone |
| Bewohner erzählen ständig Mikrogeschichten | NPCs sind im Bild selten oder sehr klein | Tagesroutinen sichtbar an Hauptwegen und Orten bündeln |
| Vegetation ist gruppiert und artdirektiert | Assets wiederholen sich raster-/zufallsartig | Cluster, Alters-/Farbvarianten, Säume und Leerflächen bewusst setzen |
| Beleuchtung hat warme/kühle Farbdramaturgie | Tag oft überstrahlt, Ranch neonhell | Exposure, Tonemapping und Palette pro Biom kalibrieren |
| Weltgrenzen werden durch Wasser, Klippen, Wald kaschiert | Garten, Park und Stadt enden sichtbar | spielbare bzw. dekorative Randkulissen mit Parallaxe |
| UI wirkt wie ein Objekt aus der Welt | funktionale Creme-Panels liegen über der Welt | Papier, Stempel, Illustration und kontextuelle Form stärker nutzen |
| Ein konsistenter Modellstil | 2D-Sprites, Primitives und detailliertere Assets gemischt | Style-Bible für Silhouette, Kanten, Textur und Material anwenden |

## Top-10-Findings

1. **Hufingen ist visuell der schwächste Hauptort**: leere, überstrahlte Plaza,
   isolierte Scheunen, kaum Bewohner oder Deko.
2. **Die Ranch ist zu groß für ihre Assetdichte**: weite Neonflächen machen
   vorhandene Inhalte kleiner statt beeindruckender.
3. **Funkelpark sieht wie eine Whitebox aus**: rechteckige Insel, Primitive,
   keine Besucher und keine glaubwürdige Achterbahn-Infrastruktur.
4. **Stadt-Orte werden durch riesige Textlabels erklärt statt durch Architektur
   erkannt**; Labels überlagern sich und brechen Maßstab.
5. **Garten/Haus außen hat keinen Horizont** und wirkt von der Welt
   abgeschnitten.
6. **Belichtung wäscht Materialien aus**, besonders Bad, Ranch-Wege,
   Hufingen-Plaza und viele Tagesansichten.
7. **Sichtbares Leben fehlt**: Systeme und Inhalte mögen existieren, aber in den
   Hauptbildern fehlen Figuren, Tätigkeiten und Bewegungssignale.
8. **Assetwiederholung ist offen sichtbar**, vor allem Ranch-Bäume,
   Blumen-/Kornreihen und Stadt-Quaderhäuser.
9. **Minispielqualität schwankt stark**: `toyRacer` wirkt wie ein fertiges
   Spielbild, GvZ/Runner/Ranch Herde mehrere Stufen darunter.
10. **Das iPhone-HUD bleibt zu beschäftigt**; die sichtbare Sprechblase ist
    mitten im Satz abgeschnitten, während viele Randaktionen gleichzeitig
    präsent sind.

## Priorisierte visuelle Verbesserungs-Queue

Sortierung nach sichtbarem Impact, nicht nach technischer Bequemlichkeit.

| Prio | Problem + Beleg | Konkreter Auftrag | Betroffene Szenen / Skripte | Aufwand |
|---:|---|---|---|:---:|
| 1 | Ranch ist neonhell und flach (`07`, `08`) | Ranch-Art-Direction-Pass: Exposure/Tonemapping senken, Gras auf ruhigere Makrofarbe umstellen, Roughness normalisieren, Wege 25–35 % dunkler, atmosphärische Tiefenstaffelung einführen | `scenes/ranch/welt/ranch_region.tscn`, `scripts/ranch/welt/ranch_atmosphaere.gd`, `ranch_terrain.gd`, `ranch_gelaende.gd` | L |
| 2 | Hufingen ist fast leer (`09`) | Plaza komplett set-dressen: 8–12 NPC-/Tier-Slots, Karren, Tränke, Schmiedeecke, Markt, Sitzgruppe, Gärten, Zäune, Rauch und warme Fensterspots; Wege enger an Gebäude führen | `scenes/ranch/dorf/hufingen.tscn`, `scripts/ranch/dorf/hufingen_szene.gd`, `dorf_katalog.gd`, `dorf_haendler.gd` | L |
| 3 | Ranch hat keine mittlere Dichte (`07`, `08`) | Pro Zone 12–20 handgesetzte Cluster aus Felsen, Hecken, Bäumen, Zäunen und Kleinhöfen; pro 30 m Sichtkegel mindestens ein mittleres Motiv | `scripts/ranch/welt/ranch_streu.gd`, `ranch_zonen_deko.gd`, `ranch_neue_zonen.gd`, `ranch_fundorte_bau.gd` | L |
| 4 | Zonen unterscheiden sich nur durch Streu (`08`) | Je Zone eine Hero-Landmarke bauen: Lavendelhof+Bienenhaus, Kornmühle, Moorhütte+Stegnetz, Obstpresse, Ruinenhof, Strandpier; Übergangssäume von 40–60 m | `scripts/ranch/welt/ranch_neue_zonen.gd`, `ranch_welt_routen.gd`, `ranch_wegenetz.gd` | L |
| 5 | Stadtlabels kollidieren und sprengen Maßstab (`04`, `05`) | Schwebende Ortsnamen entfernen bzw. auf Nahbereich begrenzen; echte Fassadenschilder, Logos, Markisen und Farbcodes einsetzen; Minimap trägt Fernerkennung | `scripts/city/city_bau.gd`, `city_map.gd`, `ui/ort_schild.gd`, `ui/minimap.gd` | M |
| 6 | Stadtblöcke sehen gleich aus (`04`) | 12 Orte mit eigener Silhouette versehen: Dachform, Eingang, Schaufenster, Vorplatzprop und Signaturfarbe; Wohnblöcke in 4–5 Nachbarschaftstypen gruppieren | `scripts/city/city_kulisse.gd`, `city_bau.gd`, `city_gruen.gd`, `scenes/city/city_scene.tscn` | L |
| 7 | Funkelpark ist Whitebox (`10`) | Park neu komponieren: Gelände statt Rechteckinsel, Randbäume/Zaun/Skyline, echte Stationsgebäude, Schienenquerschnitt mit Schwellen, dichter zentraler Boulevard | `scenes/park/funkelpark.tscn`, `scripts/park/funkelpark.gd`, `coaster_ride.gd`, `ferris_wheel.gd` | L |
| 8 | Funkelpark hat keine Menge (`10`) | Besucher- und Queue-System sichtbar machen: 20–30 günstige Crowd-Instanzen, 4 Mitarbeiter, Warteschlangen, Ballons, Partikel, animierte Lichter und Fahrgeschäfte schon in der Totale | `scripts/park/funkelpark.gd`, `park_stall.gd`, `karussell.gd`, `autoscooter.gd` | M |
| 9 | Garten endet in blauer Leere (`03`) | Vollständige Randkulisse: Nachbarhäuser, Straße, Baumkronen, Hügel/Skyline, Parallaxeschichten, Grundstücksschatten; Außenkamera nie über die Kulisse schauen lassen | `scenes/home/garten.tscn`, `scripts/home/exterior/garten_haus.gd`, `garten_diorama.gd`, `scripts/home/garden/garden_world.gd` | M |
| 10 | Hausmaterialien sind fast alle cremefarben (`01`) | Verbindliche Materialpalette mit 5 Stoffen, 4 Hölzern, Keramik, Metall und Glas; Kontakt-/Eckenabdunklung und wärmere Lichtkontraste; Bad auf Weiß-Clipping prüfen | `scripts/home/room_base.gd`, `home_licht.gd`, `rooms/room_deko.gd`, `furniture_node.gd` | M |
| 11 | Baumodus-Außenkulisse wirkt zerlegt (`02`) | Alle schwebend/unzusammenhängend lesbaren Pfosten, Rechtecke und Straßenprops auditieren; geschlossene Zaunzüge, Straßenkanten und Grundstücksnachbarn statt Einzelteile | `scripts/home/build_mode/build_mode.gd`, `build_camera.gd`, `scripts/home/exterior/haus_kontext.gd`, `street_diorama.gd` | M |
| 12 | Stadt wirkt trotz Assets unbelebt (`04`, `05`) | NPC-Dichte entlang Kamera- und Ladenpfaden erhöhen; sichtbare Mikrohandlungen: Einkaufen, Reden, Warten, Liefern, Zeitung, Hund; Tag/Nacht-Gruppen statt Einzelspawns | `scripts/city/city_fussgaenger.gd`, `city_rhythmus.gd`, `ambience/ort_leben.gd`, `ambience/stammkunden.gd` | M |
| 13 | Läden verschwinden hinter generischen Sheets (`06`) | Jeden Ort zuerst als starkes 3D-Diorama inszenieren; Sheet auf 45–55 % Bildhöhe deckeln oder als seitliche Karte öffnen; Händler und Waren sichtbar lassen | `scripts/city/ort_scene.gd`, `orte/ort_requisiten.gd`, `haendler_sheet.gd`, `ui/markt_sheet.gd` | M |
| 14 | Minispiele haben keine gemeinsame Licht-/Materialqualität (`11`–`16`) | Sechs Referenzbühnen definieren, Luma-/Sättigungsziele messen und alle Spiele kalibrieren; Host-Rahmenfarbe aus Bühne ableiten statt nur neutrales Wallpaper | `scripts/minigames/minigame_host.gd`, `host_stage_chrome.gd`, jeweilige `*_stage3d.gd`/`*_world.gd` | M |
| 15 | Runner-Bäume sind schwarz (`15`) | Baum-Materialien entmetallisieren, Albedo an Stadtpalette angleichen, Schattenwerte anheben; Clipping der großen Randbäume gegen Kamera prüfen | `scripts/minigames/games/runner/runner_world.gd`, `runner.gd`, `runner_feel.gd` | S |
| 16 | GvZ mischt flache Sprites und 3D-Kulisse (`11`) | Figuren/Türme auf ein gemeinsames Diorama-Styling bringen: entweder 3D-Standees mit Dicke/Schatten oder echte Low-Poly-Modelle; Intro schon mit sichtbarer Welle komponieren | `scripts/minigames/games/gvz/gvz_stage3d.gd`, `gvz_stage3d_props.gd`, `gvz_zombies.gd`, `gvz_art.gd` | M |
| 17 | Ranch Herde ist flach und generisch (`13`) | Spielfeld mit Stall, Tribüne, Zaunvariation, Bodenabrieb und Publikum rahmen; Schafe farblich/skalenseitig variieren; Tor als klaren Zielanker stärken | `scripts/minigames/games/ranch_herde/herde_game.gd`, `herde_logic.gd` | M |
| 18 | iPhone-HUD belegt zu viele Ränder (`17`) | Ruhemodus auf Stats + 3 Primäraktionen reduzieren; Lupe/Auge in „Mehr“; Bubble erst zeigen, wenn erste vollständige Zeile gesetzt ist, und Breite gegen rechten Dockbereich klemmen | `scripts/ui/hud.gd`, `scripts/ui/hud_layout_logic.gd`, `scripts/ui/hud/hud_mehr_cluster.gd`, `scripts/ui/components/ac_bubble.gd` | M |
| 19 | Profil wirkt wie Formular (`18`, `20`) | Pass materialisieren: Papiertextur, Stempel, Sticker, handschriftliche Akzente, klare 2-Spalten-Gruppen; iPhone-Landscape mit horizontalem Pass-Layout statt abgeschnittener Langseite | `scripts/ui/profil/profil_screen.gd`, `scripts/ui/profil/profil_screen.tscn`, `scripts/ui/components/acnh_kit.gd` | M |
| 20 | Visuelle Regressionen werden funktional, nicht qualitativ gewacht | Golden-Shot-Suite für 20 Lens-B-Motive: Luma-Histogramm, dominierende Farbflächen, Horizont-Leere, Label-Überlappung, NPC-Anzahl und sichtbare Landmarke als Review-Gates | vorhandene Capture-Skripte unter `tests/tools/`, neue Doku-/CI-Auswertung außerhalb Produktlaufzeit | M |

## Shot-Katalog

| Datei | Inhalt |
|---|---|
| `shots/01_house_rooms_montage.png` | Wohnzimmer, Küche, Bad, Schlafzimmer |
| `shots/02_house_build_mode.png` | Baumodus mit Außenkulisse und Dock |
| `shots/03_garden_house_exterior.png` | Garten und eigenes Haus von außen |
| `shots/04_city_day_street.png` | Stadt auf Straßenniveau bei Tag |
| `shots/05_city_night_street.png` | Stadtfahrt bei Nacht/Regen |
| `shots/06_city_weekly_market.png` | Wochenmarkt als begehbarer Ort mit Sheet |
| `shots/07_ranch_mountain_bridge.png` | Bergmassiv/Hängebrücke |
| `shots/08_ranch_lavender_zone.png` | repräsentative Ranch-Zone |
| `shots/09_ranch_village_plaza.png` | Hufingen-Plaza |
| `shots/10_funkelpark_plaza.png` | Funkelpark-Totale |
| `shots/11_mg_gvz.png` | GvZ |
| `shots/12_mg_tea_party.png` | Tea Party |
| `shots/13_mg_ranch_herd.png` | Ranch Herde |
| `shots/14_mg_memory.png` | Memory Match |
| `shots/15_mg_runner.png` | Runner |
| `shots/16_mg_toy_racer.png` | Toy Racer |
| `shots/17_ui_iphone_hud_2340x1080.png` | Home-HUD, iPhone quer |
| `shots/18_ui_iphone_profile_2340x1080.png` | Profil, iPhone quer |
| `shots/19_ui_ipad_hud_2048x1536.png` | Home-HUD, iPad quer |
| `shots/20_ui_ipad_profile_2048x1536.png` | Profil, iPad quer |

## Schlussfazit

GOOBY braucht keine weitere Runde, die primär „noch mehr einzelne Assets“
einträgt. Es braucht eine **Art-Direction-Runde mit festen Bildzielen**:

1. Ranch/Hufingen neu belichten und dicht komponieren.
2. Funkelpark als glaubwürdigen Ort statt Attraktionsliste bauen.
3. Stadt-Orte architektonisch statt typografisch unterscheidbar machen.
4. Weltleben in den Hauptsichtkegeln bündeln.
5. Material- und Luma-Standards über alle Welten und Minispiele erzwingen.

Wenn nur die Top 1–10 umgesetzt werden, steigt der sichtbare Welt-Eindruck
wahrscheinlich stärker als durch weitere 100 Möbel oder neue Menüs. Der
aktuelle Inhalt ist groß genug; die Welt muss ihn endlich wie ein fertiges,
bewohntes Spiel präsentieren.
