# GOOBY-EVAL 2026-08 — Lens A: Gameplay & Vollständigkeit

Stand: 8. August 2026  
Geprüfter Branch: `cursor/gooby-godot-loop-2-d1d8`  
Lens: ausschließlich Gameplay, Vollständigkeit, Ziele, Belohnungsschleifen und
Spielerfrust. Visuals sowie technische Performance werden nur erwähnt, wenn sie
den spielbaren Loop unmittelbar verändern.

## Kurzurteil

**Gesamtwertung: 6,8 / 10**

GOOBY ist **kein Alpha und keine leere Dev-Demo mehr**. Es ist ein ungewöhnlich
breites, tatsächlich spielbares Paket: Care-Simulation, fünf Heimräume, Garten,
Stadt, Freizeitpark, Reisen, 38 Arcade-Spiele, drei DLC-Loops, Ranch-Open-World,
Quests, Erfolge, Sticker, Sammlungen, Social-Systeme und mehrere Formen von
Mehrspieler sind im aktuellen Code real vorhanden.

Die schonungslose Einschränkung lautet: **GOOBY hat inzwischen mehr Features als
es als zusammenhängendes Spiel tragen kann.** Seine Menge ist stärker als seine
Zielarchitektur. Viele Systeme zahlen Coins, XP, Sticker oder Zähler aus, aber
zu selten verändert eine Belohnung die nächsten spielerischen Entscheidungen.
Die großen Langzeitziele sind überwiegend Checklisten: Level 40, 44 Erfolge,
praktisch das gesamte Stickeralbum und jedes Arcade-Spiel einmal. Das erzeugt
Beschäftigung, aber noch keine starke persönliche Geschichte oder strategische
Entwicklung.

Am stärksten ist die Ranch: erkundbare Welt, Tiere, Beziehungen, 43 Quest-
Definitionen, Wettbewerbe, Entdeckerkarte und Ausbau greifen vergleichsweise
gut ineinander. Am schwächsten ist die Produktrealität des Mehrspielers:
Client, Server und Tests sind umfangreich, aber die ausgelieferte Konfiguration
zeigt auf `127.0.0.1:8765`. Für einen normalen Spieler ohne selbst betriebenen
oder manuell konfigurierten Server sind die Social-Loops deshalb standardmäßig
offline. Gleichzeitig hängen reguläre Sticker und damit der globale
100-%-Abschluss an Online-Ereignissen.

Das größte Vollständigkeitsproblem ist inzwischen die Dokumentation selbst.
`EVAL-VOLLSTAENDIGKEIT.md` friert überwiegend den Stand vom 27./31. Juli ein:
Sie nennt 70/79 vollständige Features und führt Ball, Sammlungssets,
Gyro-Parallax, Wetter-FX, Fotowerkzeuge, Nougatschleuse, zwölf Speisen und
City Drive noch als offen oder teilweise. Der aktuelle Code und
`UserFeedback.md` belegen, dass fast alle diese Punkte später umgesetzt wurden.
Die alte Matrix darf daher **nicht mehr als belastbare Ist-Aussage** verwendet
werden.

## Scores

| Bereich | Score | Begründung |
|---|---:|---|
| Einstieg / Onboarding | **7,0 / 10** | Ein echter neunstufiger Handlungs-Guide führt durch Streicheln, Füttern, Waschen, Coins, Minispiel, Einkauf und Sticker. Der First-Hour-Test deckt den Kernweg inklusive Save/Reload ab. Zwei Lernziele sind aber nur Zähler-Proxys: „Möbel“ prüft irgendeine Ausgabe, nicht Platzieren; „Sticker“ prüft nur, ob überhaupt ein Sticker existiert. |
| Care-Loop | **7,5 / 10** | Vier Bedürfnisse, Offline-Verfall, Schlaf, frühes Wecken, Gewicht, Junkfood, Krankheit, Medizin, Tierarzt, Wetter-/Kältefolgen und sichtbare Stimmung bilden einen echten Tamagotchi-Loop. Langfristig bleibt er weitgehend lineares Balken-Auffüllen; es fehlen persönliche Pflegepräferenzen, belastbare Beziehungen und Entscheidungen mit längerem Nachhall. |
| Minispiele-Spaß | **7,0 / 10** | 38 spielbare Registry-Einträge, 3D-Szenen, Schwierigkeitsgrade, Ziele, Rekorde, 0–3 Sterne, Endlosmodi, Tages-Spotlight und Geister-Rekorde sind echte Substanz. Qualität und Tiefe bleiben naturgemäß ungleich; viele Spiele enden im gleichen Score→Coins→XP-Rahmen und verändern das Metaspiel kaum. |
| Stadt | **6,5 / 10** | Freie Fahrt, Tageszeit, Verkehr, Bewohner, Wetter, zwölf Orte, Reisen, Wochenmarkt, GOOBERANDO und Funkelpark ergeben mehr als eine Kulisse. Der Großteil der Orte ist trotzdem Transaktions- oder Menüstation. Es fehlt eine starke stadtweite Aufgabenlinie, Navigation/GPS und ein Grund, dieselben Straßen jenseits einzelner Besorgungen neu zu lesen. |
| Ranch | **8,0 / 10** | Der tiefste zusammenhängende Inhalt: Open World, Pferdepflege/-level, Entdeckung, Ausbau, NPCs/Herzen, 43 Quests, fünf Wettbewerbe und Multiplayer-Einstieg. Harte Freischaltung, 24-/48-Stunden-Warteziele und frei in der Arcade sichtbare Ranch-Spiele schwächen Besitzgefühl und Tempo. |
| Progression / Ziele | **5,5 / 10** | Level 40, Erfolge, Sticker, Arcade-Sterne, Reisen, Garten, Ranch, Ladenlevel und DLC-Ränge liefern viele Leisten. Sie bilden aber keine klare Priorität. Level-Gates sind grindig, Belohnungen oft nur mehr Coins/Zähler, Abschlussbedingungen vermischen Basis-, DLC- und Online-Inhalte. |
| Multiplayer / Social | **4,5 / 10** | Freunde, Besuche, Post/Geschenke, Schach, Schiffe versenken, Ranch-Räume, GOB-NOM-Coop und GvZ-PvP haben echten Client-/Server-Code und Tests. Out of the box zeigt die Netzkonfiguration jedoch auf localhost. Mehrere sichtbare DLC-Versprechen – Mitarbeiter, echte Freundeskunden, McGooby-Koop – sind im jeweiligen DLC-Code nicht auffindbar. |
| Content-Menge | **8,5 / 10** | 38 Minispiele, 24 Tagesquests, 44 Erfolge, 144 Sticker, 44 Lebensmittel, 43 Ranch-Quests, neun Reiseziele, zwölf Stadtorte und drei DLCs sind außergewöhnlich viel. Menge ist hier nicht das Problem; Wiederholung, Verknüpfung und ehrliche Kommunikation sind es. |

Der einfache Mittelwert beträgt 6,8. Das ist eine Bewertung des **spielbaren
Produkts**, nicht der Code-Menge oder Testabdeckung.

## Prüfmethodik und Aussagegrenzen

Geprüft wurden:

- die 79er-Feature-Matrix gegen aktuellen Godot-Code und aktuelle Content-Daten;
- Registry und Manifeste aller Minispiele;
- Quest-, Achievement-, Sticker-, Lebensmittel-, Ranch- und DLC-Kataloge;
- Onboarding-, Care-, Health-, Sleep-, Level-, Award- und Abschlusslogik;
- Stadt-, Funkelpark-, Ranch-, DLC-, Social- und Netz-Einstiege;
- der Godot-Haupttestlauf nach drei stabilen Headless-Import-Pässen;
- vorhandene First-Hour-, Save/Load-, Quest-, Minigame-, DLC-, Ranch-,
  Multiplayer- und Server-Tests.

### Laufzeitergebnisse dieser Prüfung

- Drei Headless-Import-Pässe wurden nacheinander abgeschlossen.
- Der Godot-Hauptlauf führte **3.796 Tests** aus: **3.794 bestanden, 2
  fehlgeschlagen**. Beide Fehlschläge waren die echten Node-Netztests
  `test_net_integration` und `test_social_integration`. Sie starten den Server
  über den im Test fest kodierten Fremdpfad
  `/workspace/GOOBY-SERVER/server.js`, nicht über den beauftragten Worktree
  `/workspace/worktrees/gooby/GOOBY-SERVER`. Dort fehlten `express`/`ws`;
  die Serverprozesse wurden deshalb nicht erreichbar. Das ist ein
  Testumgebungs-/Portabilitätsfehler und wird **nicht** als grüner Vollauf
  verschwiegen.
- Die für Lens A entscheidenden Godot-Flows waren innerhalb desselben Laufs
  grün: `test_w13c_erste_stunde` (kompletter neuer Spieler inklusive
  Save/Reload), `test_state_save_manager` (Roundtrip, Migration, Backups und
  Korruptionsfälle), `test_rest2_quest_engine` (Roll, Fortschritt, Claim,
  Bonus, Reroll), `test_rest1_daily`, `test_rest4_park`,
  `test_abschluss_logic` und `test_w20_arcade_fortschritt`.
- Im **korrekten Worktree** bestand `npm test` anschließend **151/151
  Server-Tests**. Damit sind die Servermodule selbst ausführbar; nicht
  bewiesen ist weiterhin ein öffentlich erreichbarer Produktionsdienst.

Headless- und Bot-Tests beweisen Zustandsübergänge, Routing, Save-Persistenz und
das Starten/Beenden der Spiele. Sie beweisen **nicht**, dass 38 Spiele über
Stunden Spaß machen, dass eine Touch-Steuerung auf realer Hardware gut fühlt
oder dass ein öffentlicher Multiplayer-Dienst erreichbar ist. Genau diese
Grenze wird in der Wertung berücksichtigt.

## Behauptungscheck: Dokumentation gegen aktuellen Code

### 1. Die 79er-Matrix ist historisch, nicht aktuell

`docs/godot-rewrite/EVAL-VOLLSTAENDIGKEIT.md` nennt in der Kopfzeile den
27. Juli und in der W13-Revision den 31. Juli. Die dort unverändert
weitergeführte Summe „70 vollständig, 5 teilweise, 3 nicht umgesetzt, 1
gestrichen“ bildet den aktuellen Branch nicht mehr ab.

Konkrete Gegenbelege:

- Ballwerfen ist inzwischen über
  `GOOBY-GODOT/scripts/home/interactables/ball.gd` und
  `ball_logic.gd` vorhanden.
- Die vier alten Sammlungen besitzen mit
  `GOOBY-GODOT/scripts/ui/album/collections_view.gd` und
  `collections_logic.gd` eine sichtbare Auswertung.
- `gyro_parallax.gd` existiert und wird unter anderem vom Wallpaper und den
  Einstellungen verwendet.
- City Drive besitzt Szene, Logik und
  `scripts/minigames/games/city_drive/game.json`; es ist eine echte
  Arcade-Runde.
- Wetterpartikel, Fotomodus-Pose/Emotion/Rahmen und die Nougatschleuse sind
  im aktuellen Scriptbestand vorhanden.
- Von den damals als zwölf fehlend bezeichneten Web-Speisen sind elf im
  aktuellen `food_catalog.gd` eingetragen. Übrig bleibt als auffällige
  Web-Kataloglücke nur `corn-dog`.

Eine neue exakte 79er-Summe wäre ohne zeilenweisen Re-Audit und neue
Produktdefinition unseriös. Sicher ist aber: **Die publizierte 70/79-Zahl
unterschätzt den aktuellen Stand deutlich.**

### 2. Es sind 38, nicht 36 Minispiele

`MinigameRegistry.GAMES` enthält vier feste Spiele:

1. `teaParty`
2. `carrotCatch`
3. `gvz`
4. `gobnom`

Zusätzlich entdeckt die Registry 34 `game.json`-Manifeste. Da deren IDs nicht
mit den vier festen IDs kollidieren, ergibt das **38 spielbare Spiele**.
`ArcadeFortschritt.REIHEN_IDS` ordnet ebenfalls 38 IDs in sechs Reihen ein:

- Geschick & Timing: 8
- Tempo & Action: 12
- Fahren & Liefern: 4
- Puzzle & Denken: 6
- Ranch & Turnier: 5
- Ruhig & Gemütlich: 3

Die alte 36er-Aussage und die 37er-Zwischenstände sind überholt. Positiv:
Die aktuelle Arcade-Kopfzeile und `UserFeedback.md` sprechen bereits von 38.
Negativ: Mehrere andere Dokumente und Kommentare erzählen weiterhin
unterschiedliche Zahlen.

### 3. Tagesquests: vollständig, aber überwiegend Zählerarbeit

`content/quests/data/quests.json` enthält **24 Quest-Definitionen**. Der
Questdienst wählt täglich drei, unterstützt Fortschritt, Claim,
Abschlussbonus und einen täglichen Reroll. Die Kategorien Pflege, Spiele,
Garten und Wirtschaft binden existierende Loops ein.

Das System ist funktional und als täglicher Wegweiser nützlich. Seine Tiefe ist
begrenzt: Die Aufgaben messen größtenteils bekannte Aktionen und Zähler. Sie
erzeugen selten eine neue Situation, eine überraschende Regelkombination oder
eine kleine Geschichte. Nach wenigen Tagen erkennt der Spieler das Muster:
„Tue vorhandene Aktion N-mal“.

### 4. Erfolge und Sticker: viel Inhalt, unsaubere Semantik

- **44 Erfolge** sind definiert und mit Coin-Rewards verkabelt.
- **144 Sticker** liegen im aktuellen Stickerkatalog; davon sind 142 regulär
  und zwei geheim.
- Die Abschlusslogik zählt Level 40, alle 44 Erfolge, alle regulären Sticker
  und jedes registrierte Arcade-Spiel gleichgewichtet.

Die Benennung der Erfolge ist teilweise veraltet: `stickerBookFull` wird
bereits bei 28 Stickern ausgelöst, während ein späterer Erfolg 84 Sticker
fordert und das Album inzwischen 142 reguläre Sticker umfasst. „Full“ ist
damit sachlich falsch und verwirrt den Wert eines echten Vollalbums.

Gravierender: reguläre Sticker enthalten Online-Bedingungen wie
`chess_online`, `chess_win`, `chess_rematch` und weitere Multiplayer-Ziele.
Weil `AbschlussLogic` **alle regulären Sticker** verlangt, kann ein
Offline-Spieler 100 % nicht erreichen.

### 5. Tagesbonus: robust, aber keine Progressionsentscheidung

`daily_bonus.gd` implementiert eine siebentägige Coin-Leiter
20/30/40/50/60/80/100, einen Kulanz-Tag und ab Tag 7 einen Bonus-Snack.
Claim statt bloßes Öffnen, Save-Persistenz und injizierbarer Zufallswert sind
sauber gelöst.

Spielerisch ist es ein Login-Reiz, kein eigener Loop. Ab Tag 7 bleibt die
Leiter flach; es gibt weder Auswahl noch langfristige Verzweigung. Der Bonus
stützt Retention, aber nicht Identität oder Planung.

### 6. Onboarding: echter Flow mit zwei falschen Erfolgskriterien

Der Guide besteht aus neun Schritten:

`ankunft → streicheln → fuettern → waschen → muenzen → minispiel → moebel →
sticker → ausblick`

Für Streicheln, Füttern, Waschen, Coins und Minispiel werden Baseline-Zähler
gespeichert; die Aktion muss nach Eintritt in den Schritt wirklich stattfinden.
Das ist gut.

Zwei Prüfungen sind zu schwach:

- `moebel` gilt bei **beliebiger Erhöhung von `coinsSpent`** als erfüllt. Der
  Spieler muss weder ein Möbel kaufen noch es im Baumodus platzieren.
- `sticker` prüft nur `sticker_count(state) > 0`, nicht einen neu verdienten
  Sticker seit Schritteintritt. Ein bereits vergebener Startsticker kann den
  Lernschritt sofort erledigen.

Der Test `test_w13c_erste_stunde.gd` beweist einen umfangreichen Happy Path,
aber er macht diese semantischen Proxys nicht zu gutem Onboarding.

### 7. Care-Loop: vollständig und folgenreich

Die vier Stats Hunger, Energie, Hygiene und Spaß verfallen unterschiedlich.
Im offenen Spiel fällt Spaß am schnellsten, gefolgt von Hunger, Energie und
Hygiene. Offline läuft der Verfall mit Faktor 0,3 und maximal acht simulierten
Wachstunden; Urlaub friert die Stats ein.

Der Loop besitzt echte Folgen:

- Energie ≤ 15 blockiert Minispiele und deckelt die Stimmung.
- Mehrere niedrige Stats erzeugen Vernachlässigungsdruck.
- Junkfood kann über `junkScore` erst Übelkeit, dann Krankheit auslösen.
- Dauerhafte Müdigkeit und Kälte sind zusätzliche Krankheitsursachen.
- Schlaf, sanftes/frühes Wecken, Medizin, Check-up und Vollheilung sind
  funktionale Gegenmaßnahmen.
- Essen, Waschen, Garten, Einkauf, Wetter und Tierarzt greifen ineinander.

Das ist mechanisch stark. Langfristig wird die optimale Antwort jedoch
vorhersehbar: Balken sehen, passende Station antippen, Animation abwarten.
Die Seele-Texte und sichtbaren Reaktionen verbessern Bindung, ersetzen aber
keine Entwicklung der Beziehung.

### 8. Funkelpark: echter Ort, dünner Langzeitloop

Der Funkelpark ist begehbar und enthält Achterbahn, Riesenrad, Karussell,
Autoscooter sowie Naschgasse. Fahrten kosten Coins und 2 Energie, geben
12 Spaß, schreiben Besuchs-/Fahrtzähler und unterstützen Nachtbesuch,
Hände-hoch-Moment und Fahrtfotos.

Damit ist er kein Platzhalter. Nach dem ersten Sehen bleibt aber wenig
Meisterschaft: kaufen, kurze Fahrt ansehen/erleben, Spaß erhalten, Zähler
erhöhen. Es fehlen Park-Fortschritt, wechselnde Tagesziele, Sammelpass,
Highscore-/Timingelemente oder Ausbauentscheidungen.

### 9. Ranch: substanzielles DLC mit vermeidbaren Frustspitzen

Der Ranch-Code trägt den stärksten Langzeit-Loop:

- Kauf ab Level 15 für 2.500 Coins;
- offene Welt mit Zonen, Fundorten und Entdeckerkarte;
- Pferdepflege, Reiten, Pferdelevel und Ausrüstung;
- Ausbau/Bau, NPCs und Herzbeziehungen;
- fünf Wettbewerbs-/Arcade-Spiele;
- **43 Ranch-Quest-Definitionen**, darunter zehn Hauptkapitel;
- Solo-Liga, Bots, Geister und sichtbarer Multiplayer-Einstieg.

Die Probleme:

1. Level 15 benötigt kumuliert **5.950 XP**. Ein Minispiel zahlt maximal
   25 XP, also entspräche der reine Arcade-Weg bis Level 15 mindestens
   **238 maximal bezahlten Runden**. Andere XP-Quellen reduzieren das, aber
   das Gate bleibt für den spannendsten Inhalt sehr spät.
2. Haupt- und Nebenquests verwenden `warte_bis` mit 8 Stunden, 24 Stunden und
   48 Stunden. Solche Wartezeiten sind als Weltgefühl verständlich, erzeugen
   ohne aktive Abkürzung aber bewusstes Nichtspielen.
3. Die fünf Ranch-Spiele stehen ohne erkennbaren DLC-Kauf-Check in der
   allgemeinen Arcade. Das ist als Demo denkbar, wird aber nicht als Demo
   kommuniziert und entwertet die Freischaltung.

### 10. Goo und Bye: guter Kern, überverkauft

Der tatsächlich belegte Loop ist ordentlich:

Bestellen/Großmarkt → Transportkapazität → Ausladen → Regale bestücken →
Tagesangebot/Kühlung → Laden öffnen → Kunden → Kassensturz → Ladenlevel 1–5.

Level 5 verlangt mindestens 14 Markttage und 800 Gesamtumsatz. Das ist ein
lesbares mittelfristiges Ziel. Lieferwagen, Gartenware und Onkel Alwin geben
dem Loop Charakter.

Die sichtbare DLC-Beschreibung verspricht zusätzlich:

- vier Mitarbeiter mit Eigenleben;
- Freunde, die wirklich im eigenen Laden einkaufen.

Im Verzeichnis `scripts/dlc/goobye` findet sich keine entsprechende
Mitarbeiter-/Personal- oder Koop-Implementierung. Kunden-NPCs sind nicht
gleich vier steuernde Mitarbeiter; normale simulierte Käufer sind nicht
gleich echte Freunde. Der Store-Text verkauft somit derzeit Designplan als
fertige Funktion.

### 11. McGooby: gutes Geschicklichkeitsspiel, kein vollständiger Tycoon

Die Schicht besitzt vier echte Stationen – Grillen, Belegen, Frittieren und
Mixen –, zehn Rezepte, Bestellstress, Perfekt-Ketten, Score und einen
Fünf-Sterne-Rang. Vor dem Kauf gibt es eine tägliche Probeschicht; der Kauf
liegt bei Level 14 und 3.000 Coins.

Die Fortschrittslogik sagt selbst ehrlich, dass Deko, VIPs und Kritiker
„später“ kommen. Gleichzeitig wirbt `dlcs.json` mit:

- Menü und Preise festlegen;
- Gastraum frei einrichten;
- Drive-in und GOOBERANDO-Lieferung;
- Koop-Schichten;
- Stammkunden inklusive Bürgermeister und Monokel-Kritiker.

Diese Breite ist im aktuellen `scripts/dlc/mcgooby`-Code nicht als
vollständiger Loop nachweisbar. Spielbar ist ein guter Schicht-Arcade-Loop,
aber noch nicht das vollständig beworbene Restaurant-Management.

### 12. Multiplayer/Social: technisch breit, produktseitig nicht zugänglich

Nachweisbar vorhanden sind:

- Freundescodes, Presence und Freunde-App;
- Besuche, Remote-Gooby, Emotes und Snap-a-Gooby;
- Post mit Text, Fotos, Geschenken und Offline-Outbox;
- Schach, Schach-KI und Online-Sessions;
- Schiffe versenken;
- Ranch-Lobby, Räume, gemeinsame Ausritte und Wettbewerbe;
- GOB-NOM-Netz-Coop;
- GvZ-Netz-PvP;
- Servermodule und Servertests.

Das ist deutlich mehr als ein Stub. Der entscheidende Produktbefund bleibt:
`content/config/data/config.json` und `NetClient.DEFAULT_NET` zeigen auf
`127.0.0.1:8765` ohne TLS. Die Einstellungen erlauben einen Override, aber ein
normaler Spieler kennt weder Host, Port noch Join-Secret. Aus dessen Sicht ist
„Offline“ der Standardzustand.

Deshalb ist die richtige Bewertung nicht „Multiplayer fehlt“, sondern:
**Multiplayer ist implementiert, aber nicht als erreichbarer Dienst
ausgeliefert.**

## Die realen Gameplay-Schleifen

### Kernschleife

1. Goobys Bedürfnisse wahrnehmen.
2. Füttern, waschen, spielen, schlafen oder medizinisch versorgen.
3. Coins/XP/Zähler aus Care, Quests, Garten oder Arcade erhalten.
4. Nahrung, Möbel, Kosmetik, Reisen oder DLCs kaufen.
5. neue Aktivitäten und Sammlungsfortschritt freischalten.
6. zurück zu Bedürfnissen und Tagesaufgaben.

Diese Schleife funktioniert. Ihr Problem ist die schwache Rückkopplung:
Möbel und Kosmetik sind überwiegend Ausdruck, nicht neue Spielstrategie.
Erfolge und Sticker dokumentieren Verhalten, verändern es aber selten.

### Arcade-Schleife

Energie zahlen → Schwierigkeit wählen → Score spielen → Coins/XP/Spaß →
Bestwert/Ziel/Sterne → Wiederholen.

Spotlight, erster Tageslauf ×2, Modifier, Geister-Rekord, Schwierigkeit und
Endlosmodus machen den Rahmen besser als eine bloße Spieleliste. Trotzdem
läuft fast jede Aktivität in dieselben zwei Metawährungen. Ein Spieler
meistert ein Spiel nicht, um ein einzigartiges Werkzeug oder eine neue
Weltfähigkeit zu erhalten, sondern hauptsächlich für Stern, Score und
Fortschrittszähler.

### Tagesloop

Tagesbonus claimen → drei Tagesquests ansehen → Care → Garten/Markt →
Spotlight-Spiel → Laden/Ranch prüfen → Belohnungen claimen.

Der Loop bietet Struktur, droht aber zum Pflichtzettel zu werden. Es gibt zu
wenig tägliche Weltveränderung: besondere NPC-Konstellationen, Regelvarianten,
kleine Entscheidungen oder verzweigende Episoden.

### Langzeitloop

Level 40 + 44 Erfolge + 142 reguläre Sticker + 38 Arcade-Erfahrungen bilden
den globalen Abschluss. Parallel existieren Reisen, Ranch-Kapitel,
Pferdelevel, Ladenlevel und McGooby-Rang.

Das sind viele Ziele, aber kein klares Zielbild. Der Abschluss mittelt vier
Quoten gleich:

- Level;
- Erfolge;
- Sticker;
- jedes Spiel mindestens einmal.

Ein einmal gestartetes Spiel zählt dabei genauso als vollständige Arcade-
Komponente wie das Meistern aller Spiele; die neue 0–3-Sterne-Logik fließt
nicht in den globalen Abschluss ein. Umgekehrt blockiert ein einzelner
unerreichbarer Online-Sticker die komplette Stickerkomponente. Das ist
unausgewogen.

## Spielerperspektive nach Zeit

### Stunde 1

Was funktioniert:

- Gooby benennen/gestalten, streicheln, füttern und waschen;
- erste Coins, Minispiel, IKEA, Baumodus, Garten und Quest;
- klare Reaktionen und sichtbare Belohnungen;
- Save/Reload ist im vorhandenen First-Hour-Test abgedeckt.

Was frustriert:

- Der Guide kann „Möbel gelernt“ melden, obwohl nur irgendetwas gekauft wurde.
- Der Sticker-Schritt kann ohne neuen Sticker übersprungen wirken.
- Die Systembreite wird sehr früh sichtbar: HUD, Questblatt, Telefon, Stadt,
  Arcade, Shop, Profil, DLC, Daily Bonus. Der Spieler lernt Funktionen, aber
  noch nicht, **warum sein persönlicher Gooby diese Ziele verfolgen soll**.
- Mehrere Belohnungs-Overlays konkurrieren um Aufmerksamkeit. Der
  Overlay-Dirigent reduziert Kollisionen, aber nicht die konzeptionelle
  Dichte.

Urteil Stunde 1: **unterhaltsam und beeindruckend, aber onboarding-seitig mehr
Feature-Tour als emotionale Zielsetzung.**

### Tag 3

Was funktioniert:

- Tagesquests, Streak, Spotlight und Garten liefern Rückkehrgründe.
- Verschiedene Minispiele verhindern sofortige Monotonie.
- Stadtbesorgungen, Wetter und Reisen erweitern den Raum.

Was langweilt:

- Tagesquests offenbaren ihre Counter-Struktur.
- Care-Antworten werden routiniert: Balken → bekannte Aktion.
- Viele neue Aktivitäten zahlen dieselben Coins und XP; die Auswahl fühlt
  sich effizient statt persönlich an.
- Der Spieler sieht Ranch, Goo und Bye und McGooby, ist aber von ihren vollen
  Kauf-/Levelgates noch weit entfernt.
- Social-Funktionen melden ohne konfigurierte Gegenstelle offline.

Urteil Tag 3: **gute Vielfalt, aber die Systeme beginnen nebeneinander statt
miteinander zu laufen.**

### Woche 2

Was funktioniert:

- Ranch, Ladenlevel, McGooby-Ränge, Reisen, Album und Arcade-Sterne können
  Langzeitspieler tragen.
- Die Content-Menge reicht klar über eine Woche.

Was frustriert:

- Level- und Coin-Gates machen den Zugang zu den besten Loops zur
  Wiederholungsfrage.
- 24-/48-Stunden-Ranchziele ersetzen Spielen durch Warten.
- Der globale Abschluss verlangt Online-Sticker, obwohl der Standardserver
  localhost ist.
- Einige beworbene DLC-Fantasien – Team, Freundeskunden, Restaurant-Koop –
  materialisieren sich nicht.
- Nach „jedes Spiel einmal“ belohnt der globale Abschluss Arcade-Meisterschaft
  nicht weiter.
- Das Album und die vielen Zähler liefern Completion, aber wenig
  weltverändernde Belohnung.

Urteil Woche 2: **viel zu tun, aber zu wenig davon verändert die Bedeutung der
nächsten Woche.**

## Top-10-Findings

1. **Die alte 70/79-Matrix ist überholt.** Fast alle dort offenen W13-Punkte
   sind im aktuellen Code geschlossen.
2. **GOOBY hat 38 spielbare Minispiele, nicht 36.** Die Menge ist real und
   registry-seitig nachweisbar.
3. **Content-Menge ist nicht mehr der Engpass.** Kohärente Progression und
   unterschiedliche Folgen der Aktivitäten sind der Engpass.
4. **Der globale 100-%-Abschluss ist für Offline-Spieler blockiert**, weil alle
   regulären Sticker inklusive Online-Ereignissen verlangt werden.
5. **Mehrspieler ist implementiert, aber standardmäßig nicht erreichbar.**
   Client und Content-Konfiguration zeigen auf localhost.
6. **Ranch ist der stärkste Inhalt, kommt aber sehr spät.** Level 15 entspricht
   5.950 kumulativen XP; der reine Max-XP-Arcadeweg wären 238 Runden.
7. **DLC-Marketing verspricht mehr als der Code liefert.** Goo-und-Bye-Team/
   Freundeskunden und McGooby-Koop/Stammkunden sind in den DLC-Scripts nicht
   nachweisbar.
8. **Onboarding misst teilweise falsche Dinge.** Ausgeben ist nicht
   Möbelplatzieren; vorhandener Sticker ist nicht neu verdientes Albumlernen.
9. **Ranch-Quests enthalten 24-/48-Stunden-Sperren**, aber keine gleichwertige
   aktive Alternative.
10. **38 Spiele teilen zu stark denselben Metarahmen.** Score, Coins, XP,
    Sterne und Zähler erzeugen Breite, aber wenig einzigartige Progression.

## Priorisierte Verbesserungs-Queue

Sortierung: erwarteter Spieler-Impact, nicht technische Bequemlichkeit.

| Prio | Problem | Beleg | Konkreter Auftrag | Betroffene Dateien / Systeme | Aufwand |
|---:|---|---|---|---|:---:|
| 1 | Multiplayer ist für normale Spieler standardmäßig offline. | `content/config/data/config.json` und `NetClient.DEFAULT_NET` nutzen `127.0.0.1:8765`; UI verlangt manuelle Host-/Port-/Secret-Kenntnis. | Einen erreichbaren TLS-Endpunkt als Release-Konfiguration betreiben oder beim ersten Social-Einstieg einen geführten „Server verbinden“-Flow mit QR/Invite-Link liefern. Verfügbarkeit end-to-end aus einer Release-Build testen. | `content/config/data/config.json`, `scripts/net/net_client.gd`, `scripts/ui/settings/mehrspieler_sektion.gd`, `GOOBY-SERVER/**` | L |
| 2 | 100 % sind offline unmöglich. | `AbschlussLogic` verlangt alle regulären Sticker; reguläre Sticker enthalten `chess_online`, `chess_win`, `chess_rematch` und weitere Social-Ziele. | Abschluss in Basis, Online und DLC trennen. Basis-100-% darf keine externe Gegenstelle oder zweite Person benötigen; Online/DLC bekommen eigene Medaillen. Alt-Saves migrieren. | `scripts/ui/profil/abschluss_logic.gd`, `scripts/ui/profil/profil_screen.gd`, `content/stickers/data/stickers.json`, zugehörige Tests | M |
| 3 | GOOBY besitzt viele Leisten, aber keine klare Kampagne. | Level, Erfolge, Sticker, Arcade, Reisen, Ranch und DLC-Ränge laufen parallel; Abschluss ist nur Quotendurchschnitt. | Eine 12–20 Kapitel lange „Goobys Jahr“-Zielkette bauen, die Care, Stadt, Arcade, Garten, Reisen und Ranch erzählerisch nacheinander verknüpft. Jedes Kapitel muss eine sichtbare Weltänderung oder neue Fähigkeit freischalten. | neue Content-Daten plus `scripts/logic/quests/**`, `scripts/soul/**`, `scripts/city/**`, `scripts/home/**`, Profil/HUD | L |
| 4 | DLC-Beschreibungen verkaufen nicht vorhandene Features. | `dlcs.json` verspricht vier Goo-und-Bye-Mitarbeiter, echte Freundeskunden sowie McGooby-Koop und Stammkunden; entsprechende Systeme fehlen im jeweiligen DLC-Scriptbaum. | Entweder die Versprechen vollständig umsetzen oder den Store-Text sofort auf den tatsächlich spielbaren Umfang kürzen. Keine Zukunftsfunktion als aktuelle Bullet. | `content/dlc/data/dlcs.json`, `scripts/dlc/goobye/**`, `scripts/dlc/mcgooby/**`, Social-/Servermodule | S für ehrliche Texte, L für Umsetzung |
| 5 | Der beste große Loop wird zu spät freigeschaltet. | Ranch: Level 15, 2.500 Coins; kumuliert 5.950 XP. McGooby: Level 14, 3.000 Coins. | Ranch-Einführung als kurze kostenlose Story/Leihpferd spätestens Level 6; Kauf schaltet Ausbau/Herdenbesitz frei. McGooby-Probeschicht soll XP-/Coin-Rabattpfad zum Kauf öffnen. Gates anhand echter First-Week-Telemetrie balancieren. | `content/ranch/data/balance.json`, `content/dlc/data/mcgooby_menu.json`, DLC-Angebote, Level-/Economy-Tests | M |
| 6 | Onboarding bestätigt Lernen ohne gelernte Handlung. | `onboarding_guide_logic.gd`: Möbel prüft `coinsSpent`; Sticker prüft nur Gesamtzahl > 0. | Dedizierte Zähler/Ereignisse für `furniturePlacedAfterPurchase` und `stickerUnlockedAfterStep` verwenden. Guide erst nach Platzieren bzw. Öffnen des konkreten neuen Stickers fortsetzen. | `scripts/ui/onboarding/onboarding_guide_logic.gd`, Build-Mode/Reward-Hub, `test_w13c_erste_stunde.gd` | S |
| 7 | Ranch-Warten stoppt Spielen. | Questziele mit 480, 1.440 und 2.880 Minuten in `ranch_quests.json`. | Für jedes Warteziel eine aktive Abkürzung anbieten: Pflege-Minigame, Materialsuche, NPC-Hilfe oder Skill-Challenge. Warten bleibt die gemütliche Option, Spielen die beschleunigte. | `content/ranch_quests/data/ranch_quests.json`, `scripts/ranch/quests/**`, Ranch-NPCs | M |
| 8 | Arcade-Spiele entwerten das Ranch-Gate. | Fünf Ranch-Spiele sind global in Registry/Arcade einsortiert; `arcade_screen.gd` enthält keinen Ranch-Kauf-Check. | Entweder bis zum Ranch-Kauf sperren oder genau ein rotierendes Demo-Spiel klar als „Ranch-Probe“ markieren; Ergebnisse aus der Demo dürfen Ranch-Fortschritt nicht vorwegnehmen. | `scripts/minigames/arcade_screen.gd`, `arcade_fortschritt.gd`, `scripts/ui/dlc/**`, Ranch-State | S |
| 9 | Tagesquests werden nach wenigen Tagen vorhersehbar. | 24 Definitionen, überwiegend Einzel-Counter aus Pflege/Spiel/Garten/Wirtschaft. | Tägliche Mini-Episoden mit 2–3 Schritten, Kontextmodifier und Wahl einführen: z. B. Regen-Picknick vorbereiten oder kranken Markt-NPC versorgen. Mindestens ein Slot pro Tag soll Situation statt Zähler sein. | `content/quests/data/quests.json`, `scripts/logic/quests/**`, Soul/City/Garden-Hooks | M |
| 10 | Arcade-Meisterschaft zählt global kaum. | Abschluss zählt nur `plays[id] > 0`; 0–3 Sterne aus `ArcadeFortschritt` werden nicht verwendet. | Abschlusskomponente auf verdiente Sterne umstellen, aber fair staffeln: Bronze für alle gespielt, Silber für z. B. 60 Sterne, Gold für 90, Platin separat. Keine 114/114-Pflicht für Basis-100-%. | `scripts/ui/profil/abschluss_logic.gd`, `scripts/minigames/arcade_fortschritt.gd`, Profiltexte/tests | M |
| 11 | Minispiele zahlen überwiegend dieselben abstrakten Rewards. | Zentraler Award-Pfad gibt Coins, XP, Spaß, Bestwert und Sterne für fast alle Spiele. | Pro Arcade-Reihe eine einzigartige Fortschrittswährung mit echter Wirkung einführen: Deko-Baupläne, Stadtfahrzeugteile, Ranch-Ausrüstung, Gartenrezepte, Social-Emotes, Reise-Souvenirs. Keine zusätzliche Währung ohne Sink. | `scripts/minigames/minigame_award.gd`, `results.gd`, Content-Kataloge, Save-Schema | L |
| 12 | Care wird zum linearen Balkenservice. | Vier Stats haben feste Raten; die richtige Reaktion ist fast immer eindeutig. | Präferenzen und Gewohnheiten entwickeln lassen: Lieblingsritual, Essensabwechslung, Wasch-/Schlafpräferenz, Vertrauen. Wiederholung derselben Lösung bekommt abnehmende Wirkung; gute Variation schaltet Reaktionen und kleine Fähigkeiten frei. | `scripts/logic/stats.gd`, `health.gd`, `weight.gd`, `scripts/soul/**`, Interactables | L |
| 13 | Stadtorte sind eher Stationen als ein Stadtspiel. | Zwölf Orte und freie Fahrt existieren, aber kein stadtweiter Quest-/Navigationsbogen; Roadmap nennt Karte/GPS/Fahrersichtung selbst als offen. | Vollbildkarte mit gesetztem Ziel, sichtbarem GPS und drei rotierenden Stadtaufträgen bauen. Aufträge müssen mehrere Orte verbinden und Verkehrs-/Tageszeitregeln nutzen. | `scripts/city/city_map.gd`, `scripts/city/data/city_map.json`, HUD/Phone, City-Questdaten | L |
| 14 | Funkelpark ist nach Erstbesuch ausgeschöpft. | Vier Fahrgeschäfte geben vor allem Spaß/Zähler; keine Park-Mastery oder wechselnde Route. | Stempelpass mit Tageskombination, Timingmomente pro Fahrt, Nacht-Spezial, Fotoauftrag und Park-Souvenirreihe hinzufügen. Voller Pass schaltet sichtbare Parkdeko frei. | `scripts/park/**`, Sticker/Collections, City-Daten | M |
| 15 | Achievement-Namen widersprechen dem heutigen Umfang. | `stickerBookFull` fordert 28, `stickerBook84` fordert 84, Album hat 142 reguläre Sticker. | Erfolge semantisch neu staffeln und umbenennen: 28 „Erste Albumseite“, 84 „Sammler“, echter Katalogabschluss separat und dynamisch aus `regular_count`. Alt-Unlocks erhalten. | `content/achievements/data/achievements.json`, Achievement-Strings/Engine/tests | S |
| 16 | Der globale Abschluss verschleiert Voraussetzungen. | Eine Prozentzahl mittelt vier Komponenten; Online-/DLC-Abhängigkeiten sind nicht klar erkennbar. | Im Profil jede Abschlusskomponente aufklappbar machen, fehlende Anforderungen nennen und Basis/Online/DLC kennzeichnen. Beim Antippen direkt zum passenden Inhalt routen. | `scripts/ui/profil/abschluss_logic.gd`, `profil_screen.gd`, Album/Arcade-Routing | M |
| 17 | Goo und Bye endet primär in Umsatzschwellen. | Ladenlevel 1–5 nutzt nur Tage und Gesamtumsatz; Kommentare nennen weitere Systeme ausdrücklich als später. | Jede Stufe mit einer neuen operativen Entscheidung verbinden: Personalplan, Regalwege, Verderb, Sonderkunde, Liefervertrag. Level nicht nur anzeigen, sondern das Spielbrett verändern. | `scripts/dlc/goobye/goobye_level.gd`, `goobye_state.gd`, Laden-/Kunden-/Transportcode | L |
| 18 | McGooby-Rang misst Wiederholung stärker als Restaurantgestaltung. | Rang basiert nur auf gespielten Schichten, Bestwert und perfekten Schichten; Deko/VIP/Kritiker fehlen laut Scriptkommentar. | Rang um Service-Stil ergänzen: Menüwahl, Preise, Einrichtung, Stammkundenbeziehungen und Drive-in. Schichten bleiben Skillkern, sind aber nicht der ganze Tycoon. | `scripts/dlc/mcgooby/mcgooby_fortschritt.gd`, `content/dlc/data/mcgooby_menu.json`, Schicht-/Hub-Code | L |
| 19 | Social-Einstieg erklärt Offline-Zustand nicht produktgerecht. | Technik ist offline-first, aber Spieler bekommt ohne Server hauptsächlich „Offline“. | Social-Tour bauen: Was funktioniert solo, was braucht einen Freund, wie verbindet man sich, Testverbindung, Einladung teilen. Bei fehlendem Dienst Online-Sticker und Calls-to-action ausblenden statt locken. | Freunde-App, `mehrspieler_sektion.gd`, `net_error_text.gd`, Social-/Sticker-UI | M |
| 20 | Feature- und Minispielzahlen widersprechen sich in Dokus. | 36, 37 und 38 tauchen parallel auf; 70/79 ist vor späteren Wellen eingefroren. | Registry/Kataloge als Source of Truth auslesen und eine generierte Statusseite erstellen. Alte Matrix deutlich als historischen Audit markieren, nicht als „Wo das Spiel steht“ verlinken. | `docs/godot-rewrite/EVAL-VOLLSTAENDIGKEIT.md`, `STATUS.md`, `UserFeedback.md`, kleines Audit-Tool | S |
| 21 | Ein Web-Lebensmittel bleibt als sichtbare Paritätslücke. | Aktueller `FoodCatalog.FOODS` hat 44 Einträge und deckt elf der zwölf alten Restpunkte; `corn-dog` fehlt. | `corn-dog` mit Quelle, Asset, Shop-Zugang, Deltas, Kühlschrankkategorie und Sammlungs-Hook ergänzen; anschließend alte „12 fehlen“-Aussage entfernen. | `scripts/logic/food_catalog.gd`, REHWEI-Sortiment, Assets/Strings/tests | S |
| 22 | Testabdeckung beweist Funktion, nicht Langzeitspaß. | First-Hour- und Bot-Tests sind stark; kein semantischer Tag-3-/Woche-2-Durchlauf bewertet Grind, Wartezeiten und erreichbare Ziele. | Deterministische Simulations-Playtests für Stunde 1, Tag 3, Tag 7 und Tag 14 hinzufügen. Messen: neu erreichbare Aktivitäten, Wiederholungen, Idle-Wartezeit, Coins/XP, unerreichbare Quests und Abschlussblocker. | `GOOBY-GODOT/tests/**`, injizierte Clock/RNG, Testreport-Doku | M |

## Empfohlene Reihenfolge für die nächste Produktwelle

1. **Ehrlichkeit und Erreichbarkeit:** DLC-Texte korrigieren, Abschluss
   offline-fair machen, reale Multiplayer-Verbindung klären.
2. **Frühe Motivation:** Ranch-Probe vorziehen, Onboarding semantisch
   korrigieren, eine kapitelartige Hauptzielkette beginnen.
3. **Wiederkehrende Tiefe:** situative Tagesquests, aktive Alternativen zu
   Ranch-Wartezeiten, stadtweite Aufträge.
4. **Langzeitwert:** Arcade-Sterne sinnvoll in den Abschluss einbauen und
   einzigartige Rewards pro Aktivitätsfamilie schaffen.
5. **Erst danach mehr Content:** Das Spiel braucht derzeit keine Minispiele
   Nummer 39–45. Es braucht stärkere Gründe, die vorhandenen 38 erneut zu
   spielen.

## Schlussfazit

GOOBY hat den früheren Vorwurf „fast alles fehlt“ sichtbar überholt. Der
aktuelle Branch enthält genug Systeme und Content für ein echtes Spiel und
mehrere Wochen Beschäftigung. Besonders Care-Folgen, Ranch, Arcade-Breite,
Save-Persistenz und die vielen Metasysteme sind substanziell.

Der nächste Qualitätssprung entsteht nicht durch weitere Featurezahlen.
Er entsteht, wenn das Spiel drei Dinge löst:

1. **eine klare, emotionale Langzeitreise statt paralleler Checklisten;**
2. **Belohnungen, die die Welt und nächste Entscheidung verändern;**
3. **ehrliche, out-of-the-box erreichbare Social- und DLC-Versprechen.**

Bis dahin ist GOOBY ein erstaunlich großer, sympathischer Spielzeugkasten mit
mehreren guten Spielen darin – aber noch kein durchgehend fokussiertes
Langzeitspiel.
