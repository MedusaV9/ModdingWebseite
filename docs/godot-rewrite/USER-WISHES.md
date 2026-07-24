# GOOBY → Godot Rewrite — vollständige User-Wunschliste (verbatim erfasst, DE)

Quelle: User-Auftrag Juli 2026. Das Spiel ist hauptsächlich DEUTSCH und OFFLINE-first.
Ziel-Engine: Godot 4.4.x. Neuer Branch enthält den bisherigen Web-Fortschritt (GOOBY/ bleibt als Referenz liegen).

## A) Engine & Architektur
- Komplettes Spiel in der Godot Engine neu bauen (echte Game Engine, Postprocessing-Effekte NUTZEN).
- Räume werden ECHTE eigene Szenen mit Ladebildschirm-Übergängen (der alte Ladebildschirm überschnitt sich mit Transitions und laggte — in Godot sauber neu).
- Dynamische Anpassung an Handy-Größen; Raum nutzt den Platz ordentlich.
- Hochkant UND Querformat überall unterstützt; QUERFORMAT wird ab sofort bevorzugt; auf Geräterotation achten.
- Kamera-Fahrten: von Zimmer-Ansicht rein ins Zimmer, durch Türen, smooth; Kamera-Clipping vermeiden (aufpassen, falls Möbel im Weg).
- Der Rückblick war falsch rotiert → in Godot richtig; Rückblick generell nochmal verbessern.
- Gooby-Welt-Minispiel (Gaussian Splats) ENTFERNEN.
- Arcade-Klick lud kurz alte Icons statt Custom-Bilder → im Rewrite fixen (sauberes Preloading).

## B) Update-System & Modularität (WICHTIG, eigene Doku ins Repo!)
- Autoupdater: In Settings ein „Suche nach Updates“-Knopf; lädt Updates von GitHub Releases OHNE neue .ipa.
- Fast alles soll ohne .ipa-Update aktualisierbar sein (Content-Packs). Wenn ein Update die native App braucht: Updater erkennt das (checkt IPA/native Version) und SAGT es dem User.
- Multiplayer-Server-IP und Port ohne IPA-Wechsel änderbar (über Update/Remote-Config).
- Modulare Teams: z. B. ein Team nur für Cosmetics kann unabhängig Updates shippen; alles modular, eigenständig updatebar. GitHub Actions baut trotzdem immer die neueste IPA mit allem Content.
- Codes zum Einlösen per Auto-Updater änderbar/hinzufügbar. Sticker per Auto-Updater hinzufügbar. Item-/Drop-Chancen (z. B. Goobyman-Zahnbürsten) per Updater änderbar.
- Doku in Repo: wie das Update-System exakt aufgebaut ist (docs/UPDATES.md).

## C) Backend & Multiplayer
- Node.js-Backend, das auf AMP (CubeCoders) im „Node.js App Runner“ läuft — Multiplayer/Backend darüber. (Godot: WebSocket/ENet — was mit Node.js sauber geht.)
- Spiel bleibt OFFLINE-first: keine Serververbindung nötig zum Spielen.
- Webpanel im Backend: Codes ausstellen; Analytics (Spielzeit: wann, wie lange, wie oft — WICHTIGSTES Analytic); Events beim Client triggern; sehen wer mit wem befreundet ist.
- Freunde-System: Hinzufügen per Name oder FriendID; Freunde-Tab zeigt was Freunde machen („Sonic0810 ist gerade mit <Gooby-Spitzname> im Park“); Münzen der Freunde updaten sich ab und zu.
- Zu Freunden REISEN: Haus des anderen ansehen; dann sind bei beiden 2 Goobys sichtbar; Wohnungen synchron; in unterschiedlichen Räumen gleichzeitig; Bauen während Besuch möglich (beide kriegen Warnung, dass Probleme auftreten können).
- Gemeinsame Spiele (gegeneinander): Brettspiel-Tisch bei IKEA kaufen (Schiffe versenken, Schach); First-Person am Tisch, Goobys stehen links/rechts, machen Animationen/Grimassen; „Emote“-Taste (tanzen, wütend etc.); TOMATE 1×/Runde als Emote — Wurf-Animation ins Gesicht des anderen Goobys, verschwindet nach 3–5 s langsam.
- Gemeinsam wohin fahren: einer fährt Auto, der andere steuert das Radio (Radio synchron).
- Abends ohne Energie: der Besucher-Gooby schläft auf der Couch im Wohnzimmer (Couch ist Pflicht-Möbel).
- Post: neuer Ort für Multiplayer — Freunden Items schicken oder Briefe mit Fotos (Ingame-Gooby-Kamera).
- GoobyPal (Handy-App): Coins an Freunde schicken, max 250/Tag.
- Gooby-Spitzname vergeben können. Spieler-Name wird beim Onboarding gefragt.
- Level-System komplett überarbeiten (Multiplayer-tauglich).
- Live Activities (iOS) fürs Taxi-Warten: 5–10 min Wartezeit aufs Taxi; App kann zu sein; Nachricht wenn Taxi in 10–15 s da ist; Taxi wartet 1 Minute; eigenes Design.

## D) Haus, Bau & Garten
- Haus-Baumodus wie Animal Crossing: Grid, alle Möbel frei platzieren, JEDEN Bereich gestalten; Räume eigene Szenen.
- Erstes Mal: Grundmöbel (z. B. Bett) platzieren; Bauen kostet keine Energie; kurze witzige Aufbau-Animation (Gooby hämmert, Qualm) beim ersten Bett.
- Möbel-Bestellung: Gooby steht draußen vor der Einfahrt, weist dem LKW mit Clipboard den Weg.
- Haus mit Geld upgraden: Keller, 2. Etage, Balkon; Fenster an Wände (draußen Straße mit ab und zu vorbeifahrenden Autos).
- Fast alles anpassbar. Spieler kann das GANZE Haus einstellen.
- Möbel-Lagerwert: Standard 100 Lagerplatz; Shed/Schuppen im Garten baubar (2x2 Felder) für mehr Lager; Shed upgradebar (visuell besser).
- Werkstatt (erst kaufen): Möbel craften aus Materialien (Stöcke im Garten finden, Baum pflanzen für Holz; Eisen/Nägel im Baumarkt).
- Baumarkt: neuer Ort, einkaufen wie IKEA, zeigt was man womit craften kann; Baupläne kaufen; Zäune (auch in Werkstatt baubar).
- Garage + Autos: Garage (erst kaufen, Bau-Animation + Sounds), Autohaus für neue Autos (farblich anpassbar; die Autos fährt man auch in den Spielen; schnellere Autos = Upgrades). Auto hat man von Anfang an, Garten auch.
- Goobay: nicht benötigte Möbel verkaufen mit Verhandlungs-Dialog (Text-Bubbles, höher/niedriger); Abholung oder zur Post bringen. Bett/Couch etc. nicht verkaufbar (Pflichtmöbel).
- Garten: von Anfang an; ECHTES Grid, kann groß werden; Wind/Schatten-Faktoren; Bewässerung per Hand/Regen oder Bewässerungsanlage (kaufen); Gewächshaus-Upgrade (deckt 6 Grid-Teile ab, Tür platzieren); Zäune.
- Wochenmarkt 1×/Woche: Garten-Ernte mit Profit verkaufen; ECHTER Ort mit Animationen (kein reines UI); Erste-Male-Info beim Gartenöffnen + „Info“-Schild.
- IKEA: Möbel-AUSSTELLUNG in 3D (drehbare Modelle), Kategorien-Suche, Farbe/Muster/Stoff anpassen, Grid-Felder-Bedarf sichtbar; viele Deko-Artikel (Toaster etc.); Brettspieltisch; Radio kaufen; SEHR viele Möbel am Ende.

## E) Stadt & Orte
- Stadt größer & besser; FREIE FAHRT zu jedem Ort (Energie wird erst bei Ankunft abgezogen); per Knopf jederzeit nach Hause.
- Reise-Cutscene NEU: Gooby geht hinten aus der Tür, auf der Straße kommt das Taxi, dann Flughafen — echte Cutscene. Bestätigen-Dialog + Warnung davor. Urlaub muss einen NUTZEN haben (erklären/geben!).
- Taxi-Wartezeit 5–10 min (mit Live Activity, s. o.).
- „Laden“-Knopf heißt jetzt „Reise“ (o. ä.), weil man zu Orten kommt.
- Orte: REHWEI (Rewe: alle Lebensmittel), GOOBYTHEKE (Apotheke: Medizin), Dr.Dr.Professor.Dr.Dr.GOOUHBUS (Arzt: erst Rezept holen; alter, witzig angezogener Doktor; Dialog-Räume), POW! (Action: Kamera kaufen + täglich 3 zufällige Items/Deko mit Angeboten), Baumarkt, Autohaus, Post, Wochenmarkt, Flughafen. Alle Rückblick-Orte erreichbar (Weltraum reicht als Minispiel).
- IGohbie (Handy, Button unten): Apps: Taxi rufen (bei 0 Energie), Guber (schneller, teurer), GOOBERANDO („Erstmal Goobyn“, Essen bestellen, 2–5 min Wartezeit, Fahrer live auf Stadtkarte, Türklingel, ORANGER Liefer-Gooby mit Essenstüte (Markenlogo generieren!), Übergabe-Animation, 5-Münzen-Trinkgeld-Option; Trinkgeld → ab und zu 2 h mehr Energie; Hinweis wenn nie Trinkgeld), Snap A Gooby (First-Person-Selfies, auch im Multiplayer Handy vor sich halten), InstantGooby (Bilder + Nachrichten an Freunde), GoobyPal, Kamera (Fotomodus), Freunde-Status.
- Fotos brauchen jetzt eine Kamera (von POW!).

## F) Gooby: Charakter, Animationen, witzige Interaktionen
- Char-Editor beim ersten Start: Augenweite etc. anpassen (Aussehen bleibt Gooby); Fellfarbe weiterhin NUR im Shop. Onboarding fragt „Wie heißt du?“ und „Willst du Gooby einen Spitznamen geben?“ — super knuffig wie Animal Crossing.
- Tür-System: Man SIEHT wie Gooby durch die Tür geht (Tür öffnet, Laufanimation); ab und zu bleibt er witzig stecken (Partikel/Effekte, Model quetscht sich durch, Body-Deform); Text-Bubble „Gooby ist stecken geblieben!“ + Klick-Minigame um ihn durchzudrücken; Tür-Animation skippbar + in Settings abschaltbar.
- Lampen per Klick an/aus: UI mit Schalter zum Hoch-/Runterschalten, Goobys Arm klickt ihn.
- Gooby-Sounds wie Animal-Crossing-Gebrabbel.
- Mehr passive Animationen overall.
- Schüttel-Secret: Handy schütteln → Haus wackelt, Deckenpartikel; mehr → Gooby hält sich am Boden fest; noch mehr → fliegt kurz witzig als Ragdoll + schreit; beschwert sich, ist dann wieder happy.
- Klo-Fix: Gooby muss jetzt WIRKLICH mal aufs Klo. Bei Baden/Klo nur SCHATTEN sichtbar; wenn man ihn beim Duschen sitzen lässt statt abzuspülen: Kopf+Ohren gucken über den Duschvorhang + witzige Textblase.
- Spiegel anklickbar: weitere Anpassungsmöglichkeiten.
- Zähneputzen nach dem Aufwachen Pflicht: Gooby wartet vor Spiegel/Waschbecken.
- Interaktions-Anzeige-Button: zeigt alles Interagierbare im Raum an.
- Geschichten-Stunde beim Einschlafen: Buch-UI öffnet sich, links Lückentext, rechts Wörter zum Einsetzen; nach ein paar Wörtern schläft er ein; danach kann man sich nur noch umsehen bis er fertig ist (oder wecken). Bücher haben Entertainment-Wert; ab und zu neue kaufen (er schläft sonst später ein, mehr Wörter/Seiten nötig).
- Laufband-Objekt: Gooby versucht drauf zu rennen — ultra-schweres Minispiel ohne echte Wirkung (Gag).
- PC für Gooby (erst kaufen, braucht GOBBULL): 1–2 h zocken lassen → sammelt Spaß.
- Gooby sucht sich immer freien Platz im Raum zum Stehen.
- Weg versperrt → Gooby beschwert sich („ich kann nicht so gut klettern manno“), Optionen: „Ich baue um“ oder „BODEN IST LAVA“ → Gooby springt an die Decke: „ICH BIN SPIDERGOOBY!“, Lava löst sich auf, er kommt runter, Bau-Menü öffnet sich.
- Random Events (Push + 5–10 min Zeitfenster, sonst „Gooby hat es schon alleine hingekommen -_-“): „Gooby ist hingefallen, hilf ihm auf!“ (liegt wie Marienkäfer auf dem Rücken), „Der Kühlschrank ist umgekippt“ (alles aufsammeln), Glas/Teller runtergefallen … witzige Texte + Belohnung (z. B. +10 Spaß für 5 h). MEHR solche Mini-Action-Events erfinden.
- Nutella-Nacht-Event: Nachricht „Du hörst etwas…“; Gooby nachts am Esstisch mit Nutella „uhhh UPPPS“; Optionen: wieder schlafen schicken (−5 Freude +10 Energie) oder weitermachen lassen (+10 Freude −5 Energie); nach 10–20 min räumt er auf und geht zurück ins Bett (Spieler muss ihn in der Zeit erwischen).
- Idle-Wandern: Gooby läuft bei Inaktivität alleine durch Räume; Button „Wo ist mein Gooby?“ teleportiert die Kamera zu ihm; er sagt was er gerade tat (z. B. Blume im Garten angeschaut); ab dann folgt er wieder.

## G) Minigames
- Alle Spiele spannender machen mit Godot-Postprocessing (Bloom etc.).
- Jedes Minispiel: Overhaul + Hochkant & Seitwärts; bei der Schwierigkeitswahl auch Orientierung wählbar, wird pro Minispiel gemerkt; globales Setting in Settings.
- Goobys vs Zombies (PvZ mit Goobys): komplette Kampagne 15 Level (jedes Level schwerer, neue Gooby-Typen mit unterschiedlichen Fähigkeiten); Multiplayer-Edition (einer platziert Goobys, der andere Zombies — gegeneinander); Coop-Modus 15 Level (einer obere drei, einer untere drei Reihen); statt Sonnen: NUTELLA.
- GOB NOM (= OH NOM-Prinzip): Süßigkeit zu Gooby bringen; Kampagne 15 Level (schwerer werdend); 10 Coop-Level (jeder kontrolliert nur einen Teil des Bildschirms → Zusammenarbeit); es wird ein NUTELLA-GLAS gesammelt.
- Autos aus dem Autohaus sind die Autos in den Fahr-Spielen (schnellere = besser).
- Weltraum als Ort/Minispiel (Rückblick-Ort).

## H) UI & Content
- UI-Anordnung (Stats oben, Buttons unten) NEU und besser.
- Für neue UI-Elemente Bilder GENERIEREN; animierte Hintergründe wie Animal Crossing (Icons wandern langsam schräg) für ALLE Tabs (Profil-Tab-Hintergrund war gut → für alle anderen auch).
- Flughafen-UI passte nicht zum Design-System → neu im GOOBY-Design.
- Profil-Tab neu aufbauen; Erfolge in den Profil-Knopf; Reisepass witziger/schöner/niedlicher + Gooby-FOTO einsetzbar.
- Ton-Knopf weg (nur Settings); Garderobe-Knopf weg (Möbel/Haus ersetzt das).
- Version-5.0-Neuigkeiten-Panel (wie früher).
- VIEL mehr Sticker, ALLE DEUTSCH beschriftet (Hauptsprache!); bisherige Sticker ERWEITERN; für Sticker-Tabs Garten/Fische/Stadt etc. je passende Bilder mit Gooby; Stickerbuch-Visual-Bug (Sticker verschwinden kurz) im Rewrite weg.
- Sehr viele neue Cosmetics; Cosmetics-System aufs Auto-Update-System umstellen (leichter + schneller Cosmetics adden).
- Save-Migration: alter Spielstand (gleiche AppId) wird automatisch erkannt und ins neue Format konvertiert (oder Option zum Übertragen).
- Radio: erst im IKEA kaufen; vorher nur „Bordmusik“ im Loop (kein Skip, nur Pause); Radio-Feature verbessert.
- GOB.TY im Wohnzimmer: witzige Videos (Animationen zwischen Goobys) anschauen.
- Deko wie Girlanden etc.
- Goobyman: Laden für Zahnbürste u. ä. (geht ab und zu kaputt; Chancen per Updater änderbar).

## Prozess-Anforderungen des Users
- Subagent-Flow: NUR Fable 5 Max Thinking (+ zusätzlich erlaubt: Opus 5 Max Thinking fast) für Arbeit; Ideen-Sammler/Improver 5–10 Stück (Fable Max).
- Bilder generieren erlaubt & erwünscht (UI, Logos, Sticker …).
- Blender + Blockbench auf der VM nutzen/installieren, Assets im Kenney-Stil selbst bauen wenn nötig; Internet-Downloads erlaubt.
- Regelmäßige Commits; GitHub Actions baut die IPA.
- Am Ende: 10–20 Polish-Subagents, dann Eval mit 5 Fable Max + 5 Opus Max fast + 5 Sol 5.6 Max fast; Findings mit weiteren Fable-Agents fixen.
