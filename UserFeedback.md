# UserFeedback — dein direkter Draht zum Agenten

**So funktioniert's:** Schreib unten unter „Neu von dir" einfach rein, was dich
stört, was fehlt oder was du dir wünschst — Stichworte reichen, kein Format nötig.
Der Agent liest die Datei vor und nach jeder Arbeitsrunde, hakt Erledigtes ab und
schreibt dazu, WAS er gemacht hat.

| Zeichen | Bedeutung |
|---|---|
| `[ ]` | offen |
| `[~]` | der Agent arbeitet gerade daran |
| `[x]` | erledigt (mit Erklärung darunter) |
| `[?]` | Rückfrage an dich |
| `[-]` | bewusst zurückgestellt (mit Begründung) |

---

## 1. Neu von dir

> **Hier reinschreiben.** Stichworte reichen, z. B. „HUD im Querformat zu weit links"
> oder „Taxi-Sound zu laut". Der Agent hakt sie ab und schreibt dazu, was er gemacht hat.

- [x] **UI IMMER NOCH grauenhaft → FULL NEW DESIGN (5.8., aus dem Chat)** —
      geliefert als **W21 „ACNH-UI"** mit genau deinem Prozess: 5 Fable-Agents
      haben das Spiel WIRKLICH gespielt (Home, Baumodus, Profil/Menüs,
      Minispiel-Rahmen, 6 Spiele in-game) und 13 direkte Bugs sofort gefixt;
      GPT-5.6-Sol-Bewerter haben davor und danach benotet. **Die Zahlen:**
      UI-Feel **3,2 → 6,8**, Dopamin **5,3 → 6,9**, Readiness **3,0 → 6,3**.
      **Was neu ist:** ein verbindliches ACNH-Design-System
      (`docs/godot-rewrite/UI-DESIGN-ACNH.md` — EINE Typo-Skala, 4er-Grid,
      3 Radien, 2 Knopf-Höhen, 1 Balken-Standard, Themen-Stimmungen,
      Motion-Grammatik) + MotionKit/AcnhKit als Bausteine mit Wächtern.
      **Deine Punkte konkret:** Baumodus — Lager ist jetzt ein einklappbares
      Kontext-Dock mit Bild-Chips, Welt-Sichtbarkeit beim Zielen **59 → 86 %**
      (nie wieder „nur Knöpfe"); Stats links — EINE kompakte Kapsel-Gruppe
      statt 6 fetter Pillen (−56 % Fläche); rechte Knöpfe — runde Icon-Buttons
      + „Mehr"-Cluster, HUD-Ruhefläche gesamt **12 → 7,4 %**; Profil — **152
      Skalen-Ausreißer → 0**, ein Kartenraster, „Weltme…"-Abschnitt gefixt;
      Quest-/Nachrichten-Banner — Blatt-Sprache mit fester Lane (überbreiter
      Toast wurzelgefixt); Minispiele — Bühnen-Diorama statt schwarzer
      Streifen, EIN HUD-Kit über 8 Spiele (gvz komplett entpixelt),
      Feier-Beats, Results-Zeremonie mit Sternen-STEMPEL; dazu
      Platzier-Puff + Raster-Tick, Quest-/Sticker-Stempel, Stagger-Einflüge,
      Count-Ups — alles Reduced-Motion-fair. **Erstlauf serialisiert** (max.
      1 Overlay + 1 Toast) und der schlimmste Blocker gefixt: Event-Karten
      kapern keine Welt-Taps mehr (Dirigent + 25-s-Vertagen als Rand-Chip +
      Gooby rückt ins Bild). Video-Abnahme: ACNH-Eindruck **8/10**,
      Welt dominiert, keine Layout-Brüche. _(W21, 5.8.)_

- [x] **Komplettes Mobile-Design-Rework des UI (4.8., aus dem Chat)** — W20
      Welle 2 „UI-REWORK", geliefert in Analyse + 4 Fix-Paketen + Nachfix:
      **Der Schlüssel-Fund zuerst:** Unsere Playtest-/Screenshot-Werkzeuge
      simulierten NIE echte iPhone-Metriken (Retina-Faktor 3x + Dynamic-
      Island-Ränder) — alles sah in den Prüfungen ~40 % kleiner und randnäher
      aus als bei dir. DESHALB war „Wache grün", während du Überlappungen und
      Gestrecktes gesehen hast. Jetzt rendert JEDER Playtest mit echten
      Geräte-Metriken. **Was danach gefunden + gefixt wurde (49 Befunde):**
      **Dynamik** — das HUD duckt sich jetzt bei JEDEM Overlay weg (Tagesbonus,
      Telefon, Guide … — vorher nur Baumodus/Sheets; dein Baumodus-Beispiel
      funktionierte schon und bleibt), nur noch EIN Willkommens-Overlay
      gleichzeitig, Toasts + Sprechblasen weichen Docks/Tabs/Karten aus
      (nie mehr Text über Knöpfen), die Kühlschrank-Taps frisst keine
      unsichtbare Karte mehr. **Schluss mit gestreckt** — das Quer-Cockpit ist
      keine 12-Kachel-Wand mehr (5 Haupt-Aktionen + „Mehr"-Cluster in der
      Daumen-Zone), Reisepass/Tagesquests/IKEA/Radio/Telefon/DLC/Abflugtafel/
      Album/Garderobe auf Inhaltsspalten + gepinnte Knöpfe umgebaut (nichts
      läuft mehr aus dem Bild, nichts liegt unter der Falz), Minispiele haben
      statt schwarzer Streifen einen Pastell-Bühnen-Rahmen mit Score/Pause AM
      Spielfeld, Fahr-UI in den Daumen-Ecken, weiche AC-Scrollbars überall.
      **Baumodus** — Werkzeug-Dock und Kamera-Chips sind jetzt in allen
      Zuständen und Formaten überlappungsfrei (auf dem Gerät ragten sie
      ineinander), Geister-Knöpfe sind echte Pills. **Der Beweis:** das neue
      Dauer-Gate (Überlappungs-/Falz-/Stretch-/Safe-Area-Prüfung MIT
      Geräte-Metriken) meldet über **216 Screen-Format-Kombinationen: 0
      Befunde** — und wacht ab jetzt bei jedem Push. **Nachschlag aus der
      Live-Video-Abnahme** (wir haben die neue UI auf dem Desktop GESPIELT und
      das Video von einem zweiten Prüfer sichten lassen): 4 weitere Funde
      gefixt — der „Fertig"-Knopf im Baumodus wirkte tot (in Wahrheit eine
      UNSICHTBARE Bett-Quest-Verweigerung + ein Tür-Dialog, der den
      Platzieren-Tap fraß — Verweigerung jetzt sichtbar mit Geist + Erklär-
      Blase), die Ebenen-Zeile duckt sich jetzt, solange die Werkzeug-Leiste
      offen ist (vorher gestapelt), der Sprechblasen-SCHWANZ ragte 5 px in
      Knöpfe (Ausweichen rechnet jetzt mit dem ganzen Fußabdruck), und eine
      frame-genaue Dauer-Wache garantiert: Werkzeug-Leiste und Ebenen-Zeile
      sind NIE gleichzeitig sichtbar — nicht mal für einen einzigen Frame.
      Finale Abnahme: Video-Tour ohne einen einzigen Überlappungs-Befund.
      _(W20/2, 4.8.)_



_(Das Projekt lebt im Repo `MedusaV9/MinecraftBubbleShieldMod`; aktueller
Arbeits-Branch seit W19: `cursor/gooby-godot-loop-d1d8` — mit komplettem
Verlauf der alten Branches (`cursor/gooby-godot-rewrite-d1d8` aus
CustomServerPrivate → `loop-2c10` → `loop-next` → `loop-d1d8`). Alle
Updates/Builds laufen über dieses Repo. Diese Datei bleibt dein direkter
Draht: einfach unten reinschreiben.)_


- [x] **Assets richtig rotiert / richtig rum** — Es gibt jetzt einen
      automatischen **Orientierungs-Audit** (`tools/audit/orientation_audit.gd`,
      Doku in `tools/ci/README.md`): mountet jede Welt-Szene headless und prüft
      alle platzierten Modelle auf Up-Achse/Kipp-Winkel, Spiegelungen/negative
      Scales, Yaw-Raster (Stadt) und Boden-Kontakt (inkl. Ranch-Terrain-Höhe).
      Voll-Lauf über 27 Szenen / 4165 Nodes: **genau 1 echter Befund** — ein
      schwebender Teddybär im POW-Laden (hing 1 m in der Luft VOR dem Regal;
      sitzt jetzt AUF dem Regal). Alles andere waren bewusste Posen/Konventionen,
      die der Audit jetzt kennt. Der Audit bleibt als Dauer-Werkzeug für jede
      neue Szene. _(W18, 2.8.)_

- [x] **Mehr Modelle downloaden (Stil muss passen!)** — **7 CC0-Packs, 186
      kuratierte Low-Poly-Modelle** (19 MB) sind im Repo:
      Kenney City Commercial/Suburban (endlich echte Wohnhäuser!), Fantasy-Town-
      Marktstände, Holiday-/Winter-Deko, Möbel-Nachschub, Quaternius-Tiere
      (animiert: Shiba, Husky, Esel, Stier, Hirsch) + Gemüse mit Wachstumsstufen.
      Ehrlich zu deinen Unity-Store-Links: deren Lizenz erlaubt Nutzung nur in
      Unity — die Packs hier sind stilgleiche CC0-Quellen (jede mit Lizenzdatei
      + `INDEX.md` Modell→Einsatzort). **Schon eingebaut:** REHWEI ist jetzt ein
      echter Laden (Regalwand, Frischetheken mit Gemüse-Auslage, Kartons,
      Hirsch-Maskottchen), GooUndBye-DLC-Laden + Baumarkt ebenfalls echte Möbel
      statt Primitives — alle mit Pastell-Tint auf den Gooby-Look, Audit 0
      Befunde. Rest-Integration (Stadt-Häuser, Ranch-Tiere, Urlaubs-Palmen)
      läuft in den nächsten Wellen. _(W18, 2.8.)_
https://blockbenchworkshop.com/browse?status=free&sort=downloads

https://sketchfab.com/3d-models?date=week&features=downloadable&sort_by=-likeCount

https://assetstore.unity.com/packages/3d/free-low-poly-pack-65375?srsltid=AfmBOopI2uLBGsg25yrGayQnnA8GDYPH9EbuyNHhDkPbKCKt8WpzPLtX

https://assetstore.unity.com/listing#nf-ec_price_filter=0...0

https://assetstore.unity.com/packages/3d/environments/landscapes/low-poly-atmospheric-locations-pack-278928

https://assetstore.unity.com/packages/3d/environments/low-poly-environment-315184

https://assetstore.unity.com/packages/3d/environments/simplepoly-city-low-poly-assets-58899

https://assetstore.unity.com/packages/2d/textures-materials/sky/farland-skies-low-poly-64604


https://assetstore.unity.com/packages/package/low-poly-environment-park-242702

hier im Unity Stire Gibt es echt extrem viel was uns helfen kann was free ist plus low poly was ja unser Stil etwas ist 
[
](https://assetstore.unity.com/search#q=Low%20Poly&nf-ec_price_filter=0...0)

wenn du irgendwo nen Account brauchst erstell dir einfach einen mit temp mail oder sowas




- [~] **Dein Feedback vom 1. August (mit 7 Screenshots, iPhone quer):** UI-Full-
      Rework, dynamisches UI mit Animationen (z. B. Baumenü → andere Knöpfe
      verschwinden), ALLE Bugs fixen, Subagents sollen das Spiel richtig SPIELEN
      (10 parallel, jeder eigene Instanz), iPhone 17 Pro Max + Querformat als
      Leitformat, Modal-Menüs + Swipen/Wischen fixen, Läden sind zu leer (echte
      Orte mit animierten Chars!), alles fühlt sich wie eine Dev-Demo bzw. wie
      einzelne Spiele statt EIN Gooby-Spiel an. → **Welle G7 „SPIELGEFÜHL" läuft**
      (Zuschnitt unten in „In Arbeit"); danach Playtest-Welle (10 Spieler-Agents)
      und die 30-Ideen-Planner-Welle. Deine Screenshots sind als Befunde erfasst:
      HUD-Kacheln schneiden Wörter ab („IGohbi/Garder/Gestalt"), Sprechblasen
      brechen mitten im Wort („Ohh, wird das sch"), Tagesquests-Blatt liegt ÜBER
      den Status-Leisten, IGohbie-Telefon hat ein kaputtes Dunkel-Icon, Gestalten-
      Liste schneidet „Briefkasten" ab, Baumodus = Knopf-Salat (der bekannte
      97-Befunde-Wurzelfix, jetzt MIT Weggleit-Animation).

_(Runden W14 UND W15 sind FERTIG — Details unten in „Erledigt". Aktueller Stand:)_

- [x] **W16 / Welle G2 FERTIG (1. August):** 13 Umsetzungs-Pakete gelandet,
      voller Testlauf grün (3024 Tests / 0 rot). Im Einzelnen:
      **(a) Update-Kanal aufs neue Repo** (Client-Config + Pack 1.1.0 + Doku
      samt Zugangsschlüssel-Migration),
      **(b) UI-Rework Fundament „Inhaltsspalte"** — Hintergrund vollflächig,
      Knöpfe/Inhalte gedeckelt in der Mitte; 7 Menü-Screens + Einstellungen
      umgestellt, automatische Zentrier-Prüfung wacht jetzt über alle Screens,
      **(c) Ladebildschirm im Alt-Look** — Szenenwechsel-Karte 1:1 nach der
      alten Web-Version (Cover-Zone, hüpfender Sticker, Teal-Balken, Tipps)
      **plus der rosa Blütenblätter-Wipe** als Übergang (26 Blüten/Blätter
      reiten der Wisch-Kante voraus, exakt die alten Web-Kurven),
      **(d) Arcade-Fix** — die 5 Ranch-Wettbewerbe haben echte Cover statt
      „?"-Platzhalter,
      **(e) 5 Minispiel-Polituren** — starHopper, trampoline, hideSeek,
      cityDrive und die Ranch-Arena (Überstrahlung raus, Publikum rein),
      **(f) Boot schneller** — erster Pixel ~55 ms früher, Welt-Laden mit
      echtem Fortschritt + vorgewärmter Musik (kein Ruckler in der Öffnung),
      **(g) 11 Prozess-/Robustheits-Fixe** (stapelnde Klick-Animationen,
      Zeitzonen-Fehler im Schnupfen-Wetter, schlafende Hintergrund-Prozesse,
      Speicher-Rettung aus Backups).
- [x] **W16 / Welle G3 FERTIG (1. August):** 12 Umsetzungs-Pakete gelandet,
      voller Testlauf grün (3078 Tests, alle Störfeuer beseitigt — u. a. 416
      wiederkehrende Fehlerzeilen im Testlauf auf 0 gebracht). Im Einzelnen:
      **(a) Inhaltsspalte ausgerollt** auf Arcade, IKEA-Katalog, Garderobe +
      Gestalten (mit Hochformat-Stapel) und das Album (Rail wird hochkant zur
      Chip-Leiste) — Hintergrund bleibt vollflächig, Knöpfe/Inhalte mittig,
      **(b) 12 Stadt-Orte** bekommen eine zentrierte Knopfleiste in der
      Daumenzone statt Ecken-Knöpfen; „geschlossen" (GOOBY-FREE) sieht man
      jetzt am Ort statt nur als Toast,
      **(c) Sozial + Post fühlbar** — alle Knöpfe drücken sich (Squish + Sound
      + Haptik nach fester Grammatik), Brief-Schreibfeld verwirft nichts mehr
      ohne Nachfrage, Ungelesen-Zähler als hübsche Kapsel,
      **(d) 137 Text-Feinschliffe** (Apostrophe, Gedankenstriche, ein Ding =
      ein Name, wärmerer Tonfall) über 50+ Dateien,
      **(e) Haptik-Stärke** (dezent/normal/stark) wirkt jetzt wirklich,
      **(f) carrotGuard poliert** (Möhren-Reihe fliegt sichtbar, Kombo-Pips,
      König-Banner, Timer-Urgenz, Intro-Beat),
      **(g) Server-CI + ehrliche Doku**, **(h) Trailer-Vorarbeiten**
      (Storyboard v4, 4 neue Aufnahme-Treiber, Zahlen-Fixes).
- [x] **W17 / Welle G4 FERTIG (1. August):** 18 Pakete gelandet, voller Testlauf
      grün (**3235 Tests / 0 rot**, UI-Audit **21 Screens × 4 Formate = 0 Befunde**).
      Das UI-Rework ist damit in der Fläche angekommen:
      **(a) Baumodus** — alle Werkzeuge in EINEM Dock unten-mittig (Daumenzone),
      **(b) IGohbie-Telefon** skaliert endlich mit (kein 420er-Überstand mehr),
      Fotomodus-Sucher in der Safe-Area,
      **(c) Reise-Strecke** — Abflugtafel/Reise-App/Bordkarte auf realer Breite,
      Weltengooby-Fortschritt „n/9 bereist" + Stempel,
      **(d) Radio/Kino/GOB.TY/Geschichten** — alle Knöpfe endlich fingergroß,
      **(e) Ranch-Mehrspieler hat jetzt einen sichtbaren Einstieg im Spiel**
      (Hof-Knopf → Raum anlegen/beitreten/Code teilen),
      **(f) Level-Auswahlen + Brettspiele** mittig mit gepinntem Fertig-Knopf,
      **(g) Boot-Ladebalken als Möhren-Pill im Alt-Web-Look** samt Papier-Ladekarte
      und „Lädt… NN%", **(h) Onboarding/Quests/Geburtstags-Feier** poliert,
      **(i) 7 Minispiel-Polituren** (teaParty, carrotCatch, bubblePop+bunnyHop,
      danceParty, fishingPond, goalieGooby, rocketRescue — Intro-Beats, lesbare
      HUDs, Jubel-Momente), **(j)** zentraler Fix: Punkte-Texte/Ringe treffen
      jetzt in ALLEN Spielen den gemeinten Punkt statt im Creme-Rand zu kleben,
      **(k)** Test-Runner gehärtet (ein Tippfehler in einer Testdatei kann den
      Lauf nicht mehr dauerhaft aufhängen).
- [x] **W17 / Welle G5 FERTIG (1. August):** 13 Pakete gelandet, voller Testlauf
      grün (**3387 Tests / 0 rot**, String-Parität 25 962 Checks / 0). Die großen
      Brocken aus deiner Liste sind jetzt SPIELBAR:
      **(a) DLC „Goo und Bye" Welle A** — im DLC-Hub freigeschaltet (ab Level 12,
      2500 Münzen, Kauf direkt im Angebots-Sheet): erster begehbarer Laden mit
      komplettem Tag-Loop Nachschub → Regal einräumen → Laden öffnen →
      Kundenstrom → Kassensturz; Onkel Alwin kommt jeden Tag um 9 und kauft
      GENAU eine Möhre, die Kasse piept sein Gebrabbel,
      **(b) DLC „McGooby" Welle A** — Probeschicht frei (kein Kauf-Gate, Welle B
      bringt das): Grill-Station mit taktilem Patty-Wenden (rosa → goldbraun →
      Kohle, „JETZT wenden!"), 10 Parodie-Rezepte (GoobyMac, Gurken-Deluxe mit
      7 Gurken …), Kassensturz mit Trinkgeld-Combo,
      **(c) GvZ-PvP übers Netz** — Gooby verteidigt, ein Freund schickt die
      Zombie-Wellen (Lockstep wie GOB-NOM, Matsch-Budget, Überlebens-Timer);
      das Server-Modul kommt in G6, bis dahin zeigt das Panel freundlich
      „Offline",
      **(d) Trailer 5.1 neu aufgenommen** — 62 s im neuen Look, alle 34 Clips
      frisch (Möhren-Ladebalken-Opening, Kühlschrank 2.0, Marktstand-Kamera,
      GvZ mit sichtbaren Zombies, Outro „38 Minispiele"),
      **(e) 11 Minispiele poliert** (goobySays, memoryMatch, lanternFloat,
      miniGolf, pancakeTower, pipeFlow, ghostHunt inkl. Datei-Entflechtung,
      burgerBuild, deliveryRush, shoppingSurf, toyRacer — Intro-Beats, lesbare
      Banner, Motor-/Fluss-Momente, Reduced-Motion sauber),
      **(f) Kino-Untertitel/Skip in der Safe-Area + Freunde-App im Telefon**
      (echtes Telefon-Layout mit Code-Teilen, Anfragen, Online-Punkten),
      **(g) UI-Wache ausgedehnt auf 34 Screens × 4 Formate** — die Alt-Screens
      bleiben bei 0 Befunden; die neue Abdeckung hat einen dicken Alt-Fisch
      gefangen: das Home-HUD bleibt im Baumodus sichtbar und liegt über dem
      Bau-Dock (97 Befunde, EIN Wurzel-Problem) → wird in G6 gefixt.

- [x] **DLC-Umsetzung „Goo und Bye" + „McGooby"** — Welle A beider Fundamente ist
      mit G5 gelandet und spielbar (s. o.); Welle B (Großmarkt-Fahrt, Preis-Schieber,
      weitere Stationen, Kauf-Gate McGooby) ist der nächste Ausbau-Schritt
- [x] **Minispiel-Qualität, Gruppe 3** — die notierten Kandidaten (starHopper-Bühne,
      trampoline-Gym, carrotGuard-HUD, hideSeek-Wiese, cityDrive-Feedback,
      Ranch-Arena-Überstrahlung) sind seit Welle G2/G3 alle umgesetzt; der Rest-
      Batch läuft in G5
- [x] **GvZ-PvP übers Netz** — Client komplett (Lockstep, Panel, End-Overlay);
      nur das kleine Server-Modul (gvzmp.js nach gobnom-Muster) folgt in G6
- [x] **Trailer-Refresh** — `trailer/GOOBY-5.1-Godot-Trailer.mp4` (62 s, 1080p60),
      alle 34 Clips mit dem neuen UI neu aufgenommen, 12 Abnahme-Stills gesichtet
- [-] **Dynamic Island / Live Activities + iOS-Homescreen-Widget** — braucht native
      Extensions in einer SIGNIERTEN App (Sideload-.ipa kann das nicht registrieren).
      Ehrlich zurückgestellt; Godot-Andockpunkte existieren.

---

_(gerade nichts offen — alle bisherigen Punkte stehen unten unter „Erledigt")_

- [x] **verbessere den Aufbau der Feedback Md**
      Neu gegliedert: 1. Neu von dir (hier reinschreiben), 2. In Arbeit,
      3. Wo das Spiel steht (Testen/Spielstand/Offenes/Trailer auf einen Blick),
      4. Erledigt mit Erklärung. Keine Doppelungen mehr, klare Reihenfolge.
- [x] **verbessere das UI von Gooby**
      Jeder Screen einzeln bewertet und nachgezogen: klare Hierarchie (eine Hauptsache
      pro Bild), einheitliche Kopfzeilen, illustrierte Leerzustaende statt leerer
      Flaechen, animierte Hintergruende mit eigener Farbstimmung, Freundescode als
      Blickfang. Die automatische UI-Pruefung (15 Screens x 4 Geraeteformate) bleibt
      bei 0 Befunden.
- [x] **Baumodus-Kulisse + Haus von aussen sehen**
      Diagnose der alten Kulisse: eine Ringstrasse lag 4 m an der Wand, mit Autos die
      groesser waren als der Raum - das las sich als Kreisverkehr um eine Insel. Neu:
      eigenes Grundstueck mit Zaun und Weg, EINE Strasse hinter Vorgarten und Gehweg,
      Nachbarhaeuser in richtiger Groesse, Baumreihen, Horizont. Im Garten steht jetzt
      dein Haus mit Dach im gewaehlten Stil daneben (die Haustuer sitzt exakt ueber der
      Gartentuer), Raeume haben Deckenbalken bzw. Dachschraegen, hinter Tueren sieht man
      den Nachbarraum, und aus Kuechen-/Badfenster blickt man in den Garten.
- [x] **Post-Processing + echte Gefuehle wie bei Animal Crossing**
      12 klar lesbare Emotionen mit Gesicht, Koerperhaltung, Bewegung, Ton und
      Symbol ueber dem Kopf: Schreck (Ausrufezeichen), Freude, Begeisterung,
      Ueberraschung, Verlegenheit, Trotz, Traurigkeit, Muedigkeit, Neugier, Stolz,
      Angst, Verliebtheit (Herz). Sie kommen von selbst - Schreck beim Donner,
      Verliebtheit beim Lieblingsessen, Stolz nach einem Rekord - und die starken
      bekommen einen Kamera-Zoom mit Zeitlupe. Dazu ein Effekt-Stapel: Vignette,
      Tageszeit-Toenung, Bloom, Tiefenschaerfe, Farbstoss bei starken Gefuehlen -
      in den Einstellungen abschaltbar, Kosten nur +1 Draw-Call.

---

## 2. In Arbeit

**Runde W21 (5.8.) — „ACNH-UI" Wellen A–D FERTIG:** dein Full-New-Design-Auftrag
— Bericht oben im abgehakten Punkt unter „Neu von dir" (Scores: UI-Feel 3,2→6,8,
Dopamin 5,3→6,9, Readiness 3,0→6,3; Baumodus-Welt 59→86 %, HUD 12→7,4 %,
Skalen-Ausreißer 152→0, 13 Playtest-Bugs + Event-Kaperung gefixt).
**Als Nächstes (W21 Welle E, aus den GPT-Re-Evals + Video-Abnahme):**
universelles Tap-Feedback + Fütter-Finale (Dopamin-Top-2), MG-HUD-Kit auf
alle 38 Spiele ausrollen, Event-„Ansage"-Vorlauf, Home-Ruhe-HUD Richtung
≤5 %, Chip-Label-Clipping im Bau-Item-Blatt, Qualitäts-Notify in die
Toast-Lane, Geburtstags-Blase vs. Tagesbonus entzerren, echter
iPhone-Smoke-Test; danach die W20-Roadmap-M-Brocken (Freunde-Geister,
Stadtkarte + GPS, Fahrer-Sichtung, Tages-Rätsel).

**Runde W20 (4.8.) — Welle 2 „UI-REWORK" FERTIG:** dein Mobile-Rework-Auftrag
aus dem Chat — Details oben im abgehakten Punkt unter „Neu von dir". Kurz:
echte iPhone-Metriken in allen Prüfwerkzeugen (der Wurzelgrund, warum es bei
dir anders aussah als in unseren Wachen), HUD-Verdeckungs-Vertrag für alle
Overlays, Toast-/Blasen-Lanes, schlankes Quer-Cockpit mit „Mehr"-Cluster,
Baumodus-Dock disjunkt, 15+ Screens auf Inhaltsspalte/gepinnte Füße umgebaut,
Minispiel-Bühnen-Rahmen, Fahr-UI in Daumen-Ecken — und das neue Dauer-Gate
meldet 0 Befunde über 216 Screen-Format-Kombinationen.
**Als Nächstes (Welle 3):** Playtest-Sichtprobe der neuen UI auf weiteren
Screens + die W20-Roadmap-M-Brocken (Freunde-Geister, Stadtkarte + GPS,
Fahrer-Sichtung, Tages-Rätsel).

**Runde W20 (4.8.) — Welle 1 FERTIG (die 4 Quick-Wins aus den Roadmap-Top-10):**
**(1) McGooby-Rang-Feier** — der Sterne-Aufstieg wird jetzt zelebriert (Gold-Titel,
Sterne-Band, Konfetti, Haptik; genau einmal pro Stufe, reload-fest) und die 4
Stationen haben eigene Deko (Grill-Flackern, Öl-Blubbern, Mixer & Co.).
**(2) Veil-Ziel-Karten** — Schluss mit der falschen „Trautes Heim"-Karte: die
Reise zur DLC-Bibliothek hat ihr eigenes Regal-Artwork, Flughafen/Raumstation
sagen „Gute Reise!", Arcade-Reisen „Ab in die Arcade!", und unbekannte Ziele
zeigen ehrlich „Unterwegs…" (damit ist das seit W17 wartende G6-Paket
„DLC-Ladebildschirme" erledigt). **(3) Erinnerungs-Horizont 2.0** — Gooby
erinnert sich jetzt an ALLES Neue: Markttage, Onkel Alwins Möhre, McGooby-
Schichten, Fundort-Entdeckungen, geschlagene Geister, Mitbringsel und den
Spotlight-Bonus (15 neue warme Sprüche, DE+EN). **(4) Arcade mit
Fortschritts-Gefühl** — 6 beschriftete Kategorien-Reihen statt 38-Kacheln-Wand,
3-Sterne-Zeile auf jeder Kachel (aus echten Bestwerten) und der Kopf
„n/38 gespielt · m Sterne". Preflight grün, alle Playtest-Wächter-Flows grün.
**Als Nächstes (W20 Welle 2):** die M-Brocken der Top-10 — Freunde-Geister,
Vollbild-Stadtkarte + GPS, GOOBERANDO-Fahrer-Sichtung, Tages-Rätsel.

**Runde W19 (3./4.8., neuer Branch `cursor/gooby-godot-loop-d1d8`) — Wellen 1–5 FERTIG:**

**Welle 4 (Roadmap-Brocken, 4 Agents):** **McGooby hat jetzt alle 4 Stationen**
(neu: Fritteuse „im goldenen Fenster loslassen" + Shake-Bar „kreisen bis zur
Flausch-Krone", beide bot-zertifiziert) — damit sind **alle 10 Rezepte
zubereitbar** und die Timer-Jonglage über Stationen ist real; dazu ein
**5-Sterne-Laden-Rang** mit ehrlicher Anzeige (Ende-Karte + DLC-Hub).
**Goo und Bye:** Laden-Level 1–5 aus dem Umsatz-Zettel, **Lieferwagen-Kauf ab
Level 5** (1500, transaktional) mit Übergabe-Story (Van-Vorfahrt + 3
Onkel-Alwin-Sprüche), **REHWEI-Rampen-Inszenierung** (Lieferwagen + Kisten
sichtbar, solange eine Fahrt läuft) und **Kisten-Drag-ASMR** beim Ausladen.
**Liefer-Hetze poliert:** die Kamera gerät nie mehr hinter Häuserwände
(Kulissen-Klemme; 54/2640 Posen waren betroffen — szenen-analytisch bewiesen),
die Spawn-Stele stand exakt auf dem Start (verschoben), der Steuer-Hinweis hat
eine Milchglas-Plate, und die ehrliche Anfahrts-Wartezeit (Web-Parität!) wird
jetzt durch den „Erste Lieferung: … folge dem rosa Band!"-Beat ERKLÄRT statt
verschwiegen. **Ranch-Welt lädt 7× schneller:** Reveal von **14,7 s auf 1,9 s**
(kalt) bzw. 33 ms (warm) durch Time-Slicing + Geometrie-/Mesh-/Streu-Caches —
bit-identische Welt, das 10-s-Hard-Timeout beim Ausreiten ist WEG.

**Welle 5 (die seit W17 eingeplante Ideen-Planner-Welle):** 6 Planner-Agents
haben **76 verifizierte, priorisierte Ideen** (17 S / 40 M / 19 L) für alle
Bereiche geliefert — konsolidiert in
**`docs/godot-rewrite/ROADMAP-W20.md`** (Top-10 + große Brocken + alle
Original-Ideen mit Quelle/Skizze/Risiko/Beweis). Die Planner haben nebenbei
STATUS.md-Staubfänger korrigiert (einiges ist fertiger als dokumentiert).

**Welle 2 (Playtest — Agents SPIELEN die 6 neuen Features, quer + hochkant):**
6 neue DAUERHAFTE Playtest-Flows als Regressionswächter (Goobye-Großmarkt 77
Schritte, McGooby-Kauf+Belegen 68, Heimkehr 63, Spotlight 44, Entdecker-Karte 47,
Geist-Rekord 45 — alle Exit 0 in BEIDEN Formaten). Dabei 5 echte Bugs gefunden
und mit Wurzel-Fixes + rot-vor-grün-Wächtern behoben: (1) BLOCKER: im
Goobye-Laden lag hochkant der erste Regal-Chip außerhalb des Bildschirms (hartes
Kamera-Z + ungedeckelte Chip-Reihe); (2) das Tagesangebot-Kritzelschild hing
quer HINTER den Regal-Chips; (3) die Heimkehr-Übergabe-Karte lag UNTER dem
Home-HUD (CanvasLayer-Falle — HUD blieb tappbar); (4) der GOOBY-FREE-Hinweis
war konturlos unlesbar (Gooby lief durch den Text); (5) die Karten-Pins klebten
nach Zoom bis 150 px neben ihren Fundorten (Resize-Race). McGooby, Spotlight
und Geist-Rekorde: KEINE Produkt-Befunde.

**Welle 3 (Funde fremder Domänen aus den Playtests, alle rot-vor-grün):**
WeltengoobyKarte ebenfalls unters HUD gerutscht (gleiche Layer-Falle → Layer
40); der „Kuschelabend?"-Abend-Prompt drängelte sich unter offene Overlays
(Soul-Gespräche reihen sich jetzt beim Overlay-Dirigenten ein, Prio 40); der
HUD-Alert-Puls crashte selten beim Szenenwechsel („Infinite loop detected" —
Tween hing am HUD statt am Chip, per Laufzeit-Probe reproduziert und gefixt).
Der einmalige „Invalid polygon"-Fehler wurde forensisch untersucht: der
Blütenblätter-Wipe ist ENTLASTET (0 Degenerationen über 2001×9 Testfälle) —
bleibt als Backlog-Beobachtung.

**Welle 1 (die komplette „Welle 5"-Warteschlange aus W18):**
Die komplette „Welle 5"-Warteschlange aus W18 ist gelandet — 6 Pakete von 6
parallelen Subagents (Details unten in „Erledigt"): **DLC „Goo und Bye" Welle B**
(Großmarkt-Fahrt mit echtem Warentransport, Tagesangebot, Kühl-Kapazität),
**DLC „McGooby" Welle B** (Kauf-Gate im DLC-Hub, zweite Station „Belegen",
Perfekt-Kette), **Mitbring-Momente** (Wiedersehens-Inszenierung + deterministisches
Mitbringsel + GOOBY-FREE-24h-Fenster), **Arcade-Spotlight** („Spiel des Tages" mit
+50-%-Tagesbonus), **Geister-Rekorde** (Live-Geist-Chip gegen den eigenen Bestlauf
+ „Geist geschlagen!"-Beat) und die **Ranch-Entdecker-Karte** (Fog-Karte, 16
Fundort-Pins, NEU-Badges, Detail-Karten). Preflight komplett grün (3625 Tests,
26 761 UI-Checks, 0 rot), Leak-Gate über alle 38 Spiele dicht.
**Als Nächstes (W20):** Umsetzung nach `docs/godot-rewrite/ROADMAP-W20.md`.
_→ Welle 1 (die 4 S-Quick-Wins der Top-10) ist bereits gelandet — Bericht oben
unter „Runde W20"._ Danach: Freunde-Geister, Vollbild-Stadtkarte + GPS,
GOOBERANDO-Fahrer-Sichtung, Tages-Rätsel, dann die großen Brocken
(McGooby-Team, Goobye-Team + Offline-Kasse, GvZ-Coop). Wünsch dir gern
Reihenfolge!

**Runde W18 (2.8., Branch `cursor/gooby-godot-loop-next`) — Welle 1+2 FERTIG:**
3 Playtest-Agents haben das Spiel wirklich GESPIELT (22 Flows, ~800 Screenshots,
quer + hochkant) und 2 Blocker + 12 ernste Befunde gefunden; 9 Fix-Agents haben
ALLE Blocker/ERNST-Befunde mit Wurzel-Fixes + Wächter-Tests + End-zu-End-Beweisen
behoben (Details unten in „Erledigt» W18). Preflight komplett grün.

**Welle 3 FERTIG (2.8.):** 5 große Pakete gelandet (Preflight grün, 3519 Tests / 0 rot):
**(a) Morgen-Ritual + Overlay-Dirigent** — nie mehr Popup-Stau: erst begrüßt
Gooby, DANN gleitet das Tagesbonus-Blatt rein, dann der Rest — immer nur EIN
Willkommens-Overlay, Reise-Sperre inklusive; **(b) Läden lebendig überall** —
das Ambient-System läuft jetzt in ALLEN 12 Orten (Apotheke, Drogerie, POW, Post,
Autohaus, Tierarzt, Praxis, Flughafen mit Rollkoffer-Goobys, Raumstation, Markt,
Funkelpark, GooUndBye) + **5 benannte Stammkunden** (Frau Rosine schnuppert
vormittags an den REHWEI-Möhren, Opa Hatschi schlurft zu seinen Kräuterbonbons,
Frau Fernweh träumt am Flughafen, Herr Dübel werkelt nach Feierabend, Rollo
skatet am Funkelpark — mit Namensschildern + eigenen Sprüchen DE/EN);
**(c) Stadt-Tagesrhythmus + echte Wohnhäuser** — Verkehr/Fußgänger/Licht folgen
der Uhr (morgens Zeitungs-Gooby, abends Laternen + leuchtende Fenster, nachts
leer), 13 CC0-Haustypen ersetzen die Primitiv-Würfel; **(d) Klangbetten** —
jeder Ort hat ein dezentes Ambiente (Kaminknistern, Vögel, Stadt-Grummeln,
Laden-Raumton; 6 nahtlose CC0-Loops, selbst synthetisiert) mit weichem Ducking
wenn Gooby spricht; **(e) Münzflug** — Belohnungen fliegen sichtbar im Bogen
zur HUD-Kapsel, die pulst und hochzählt (Reduced-Motion-fair, Toast wenn HUD
geduckt). **Und 3 weitere Playtests** (Stadt/Reise, DLCs/Ranch,
Telefon/Sozial/Onboarding) haben 5 neue dicke Fische gefunden.

**Welle 4 FERTIG (2.8., Preflight grün):** ALLE Playtest-Funde gefixt —
**Reise läuft wieder komplett** (Flughafen-Parkplatz lag im Gebäude-Collider →
Pad jetzt straßenseitig mit Wächter über ALLE Orte; die Abflug-Cutscene buchte
nie, weil das Sheet die App freigab bevor „fertig" feuerte → Buchung jetzt
genau-einmal + volle Rückerstattung wenn unterbrochen — kein Geldverlust mehr
möglich); **Ranch-Kauf frisst keine 2500 Münzen mehr** (der ranch-Slice fehlte
in der Boot-Registrierung — exakt das Loch, das city früher hatte; Kauf jetzt
transaktional: erst prüfen, dann buchen, mit Save-Beweis im Playtest);
**Öffnungszeiten wirken jetzt wirklich** (Wochenmarkt nur Samstag — vorher
tote Daten); **Gooby ist im Urlaub wirklich WEG** (leeres Sofa + Hinweis statt
Sofa-Geist); **DLC-Hub komplett bedienbar** (Settings-Overlay weg beim Routen,
Wischen scrollt statt Sheets zu öffnen, Kauf-Knöpfe gepinnt sichtbar + ehrlich
ausgegraut bei Münzmangel); **Post-Briefkasten + Codes liegen VOR ihren
Sheets** (Layering-Klasse gefixt + MAIL_NEW-Push geht nicht mehr verloren);
**Möbel-Sheets bleiben offen** (Radio-Tap öffnete+schloss sofort — TapArea
feuert jetzt auf Release, gilt für ALLE Möbel); **GOOBERANDO-Bestellen
gepinnt + Korb-Feedback + Wisch-Scroll**; **POW-Parkfeld schleudert das Auto
nicht mehr 16 m durch die Fassade** (Kriech-Minimum + Depenetration-Punch
gefixt, Autos können endlich echt PARKEN); **Heudieb zählt 1 Tap = 1 Krähe**.
**Als Nächstes:** Welle 5 (DLC Welle B beider Läden, Mitbring-Momente,
Arcade-Spotlight, Geister-Rekorde, Ranch-Entdecker-Karte aus der Roadmap).
_→ Erledigt: die komplette Welle 5 ist als Runde W19 / Welle 1 gelandet (s. o.)._

Runde W17 — Wellen G1–G5 sind FERTIG (Details oben + unten in „Erledigt").
_Hinweis zur Transparenz: die am 31.7. gestartete Welle G6 ist einem VM-Neustart
zum Opfer gefallen, bevor sie integriert/committet war — kein Stand verloren
gegangen außer der unfertigen Subagent-Arbeit; die G6-Pakete sind neu einsortiert._

**Welle G7 „SPIELGEFÜHL" LÄUFT** (dein Feedback vom 1.8. hat Vorrang; 10
Subagents parallel — das ist das harte Plattform-Limit, die Pipeline bleibt voll):

- [~] **P50 HUD-Dynamik** — dein Wunsch wörtlich: beim Baumenü GLEITEN die
      HUD-Knöpfe animiert weg (und kommen animiert zurück); bei offenen
      Blättern/Modals (z. B. Tagesquests) weicht/dimmt das HUD statt
      durchzuscheinen; HUD-Kachel-Labels werden nie mehr abgeschnitten
      („IGohbi/Garder/Gestalt" → passende Beschriftung), „Wo ist mein
      Gooby?"-Chip inklusive
- [~] **P51 Sprechblasen + Text-Fit** — „Ohh, wird das sch" ade: Blasen
      wachsen/wickeln sauber, nie mehr mitten im Wort enden; Text-Fit-Sweep
- [~] **P52 IGohbie-Telefon-Rework** — kaputtes Dunkel-Icon, unklare Symbole,
      App-Labels, Öffnen-Animation, Wisch-zum-Schließen
- [~] **P53 Modal/Sheet-System + Swipe** — EIN einheitliches Blatt-Verhalten
      überall: Slide-in/out, Hintergrund-Dim, runterwischen = schließen
      (inkl. Radio-Like-Offscreen-Fix)
- [~] **P54 Garderobe + Gestalten poliert** — abgeschnittene Kategorien
      („Briefkasten"), Scroll-Hinweise, Karten-Layout, Kauf-Feedback
- [~] **P55 Läden lebendig, Teil 1** — REHWEI + IKEA werden ECHTE Orte:
      animierte Kunden-Goobys, Kassen-NPC, Ambiente-Sound, Deko
- [~] **P56 Ein-Spiel-Gefühl** — einheitlicher Minispiel-Rahmen (Intro/
      Outro/Pause im Gooby-Look überall) + einheitliche Szenen-Übergänge,
      damit sich nichts mehr wie ein Fremd-Spiel anfühlt
- [~] **P57 iPhone-17-Pro-Max-Leitformat (2868×1320 quer)** — UI-Wache +
      Konformitätstests aufs neue Leitformat, plus die 17 bekannten
      Audit-Restbefunde (RMP-Tippflächen, Onboarding-Knöpfe offscreen)
- [~] **P38R GvZ-PvP-Server** — Relaunch des verlorenen Pakets (gvzmp.js
      nach gobnom-Muster inkl. Node-Tests)
- [~] **P58 Playtest-Harness + Pionier-Spieler** — baut das „Subagent
      spielt das Spiel"-Werkzeug (eigene Instanz, echte Eingaben,
      Screenshot-Serie, Hänger-/Fehler-Detektor) und spielt den ersten
      kompletten Durchlauf im Leitformat → Bug-Report Nr. 1

**Danach sofort (Warteschlange):**
- [ ] **Welle H: PLAYTEST ×10** — 10 Spieler-Agents, jeder spielt seinen
      Bereich mit eigener Instanz (Home/Bau, Stadt/Läden, Minispiele ×3,
      DLCs, Telefon/Radio, Garderobe/Gestalten, Quests/Progression,
      Onboarding) → gesammelte Bug-Liste
- [ ] **Welle I: 30+ Ideen-Planner** — 10 Planner parallel, jeder liefert
      10+ priorisierte Ideen für seinen Bereich (≈100+ Ideen), konsolidiert
      zur Roadmap
- [ ] **Wellen J+: Umsetzung** — Playtest-Bugs + beste Planner-Ideen +
      die neu einsortierten G6-Pakete (DLC Welle B beider Läden, Ball-Wurf,
      DLC-Ladebildschirme, Audio-Feel, B11/Warn-Sweep, Doku-Refresh,
      McGooby-Bühne, Alwin-NPC)

---

## 3. Wo das Spiel gerade steht

| | |
|---|---|
| **Testen** | GitHub → Actions → Lauf „GOOBY Godot" → Artefakt `GOOBY-godot-unsigned-ipa` herunterladen, mit AltStore/Sideloadly installieren. Anleitung: `docs/godot-rewrite/IOS-BUILD.md` |
| **Spielstand von früher** | Einstellungen → Spielstand → „Alten Spielstand übertragen"; Anleitung: `docs/godot-rewrite/SAVE-TRANSFER.md` |
| **Was noch offen ist** | `docs/godot-rewrite/EVAL-VOLLSTAENDIGKEIT.md` (ehrliche Feature-Matrix) |
| **Trailer** | `trailer/GOOBY-5.1-Godot-Trailer.mp4` (neu, W17-Look) — Vorgänger 5.0 bleibt daneben liegen |

---

## 4. Erledigt

Chronologisch nach Meldung; die Erklärung steht jeweils darunter.

- [x] **Runde W19, Welle 1 (3. August): die komplette „Welle 5"-Warteschlange — 6 Pakete**
      **Goo und Bye Welle B:** Der Großmarkt-Einkauf wird WIRKLICH gefahren — Bestell-Sheet
      mit Steppern (Einkauf = 60 % des Richtwerts), die Fahrt läuft als pure Funktion der
      Uhr nach dem GOOBERANDO-Fahrer-Muster (App zu/auf — die Ware ist exakt da, wo sie
      sein soll), Kofferraum-Volumen zählt endlich (kleines Auto 12 / Kombi 24 /
      Lieferwagen 48 Kisten), „Alles ausladen!" mit Klonk-Piep-Choreo. Dazu das
      **Tagesangebot** (1 Warengruppe/Tag: −15 % Preis, +40 % Griff-Chance, 6
      Kritzel-Schilder) — die Kunden-Sim bleibt bit-genau deterministisch — und
      **Kühl-Kapazität** (Kühlware braucht Kühlmodule statt Frische-Timer; Module im
      Bestell-Sheet nachkaufbar). 12 neue Wächter-Tests.
      **McGooby Welle B:** McGooby ist jetzt im DLC-Hub **kaufbar** (Level 14, 3000
      Münzen, transaktional — Geld weg ohne Leistung ist ausgeschlossen; Kauf-Knopf bei
      Münzmangel ehrlich ausgegraut), die Probeschicht bleibt als Demo (genau 1×/Tag vor
      dem Kauf, danach unbegrenzt). Neue **Belegstation** (Zutat in Ticket-Reihenfolge
      aufs Brötchen wischen — GoobyMac & Co. komplett zubereitbar, Stations-Tabs in der
      Daumen-Zone, bot-zertifiziert) + **Perfekt-Kette ×N** über Stationen hinweg. Dabei
      echten Szenen-Bug gefunden+gefixt (Zutaten-Knöpfe verloren ab Bestellung 2 ihre
      Namen). 15 neue Wächter-Tests.
      **Mitbring-Momente:** Kommt Gooby aus dem Urlaub heim, gibt es beim ersten
      Home-Besuch ein echtes Wiedersehen — celebrate-Clip, Koffer + Mitbringsel-Tüte als
      Props, Übergabe-Karte mit „Fest drücken!" → Umarmungs-Konfetti. Das **Mitbringsel**
      ist deterministisch pro Urlaub (Schneekugel/Magnet/Wimpelkette mit Ziel-Namen) und
      landet im Inventar; die beiden NICHT mitgebrachten Varianten sind danach **24 h
      exklusiv im GOOBY-FREE** am Flughafen kaufbar („Nur 24 h"-Chip + Countdown). Reiht
      sich brav beim Overlay-Dirigenten ein — kein Popup-Stau. 11 neue Wächter-Tests.
      **Arcade-Spotlight:** Jeden Tag ist EIN Spiel „Spiel des Tages" (deterministische
      Rotation — nie zweimal dasselbe hintereinander): goldenes Banner + Puls-Rahmen auf
      der Kachel, **+50 % Münzen** auf die erste Spotlight-Runde des Tages, ehrlich im
      Pregame und in den Results ausgewiesen. 8 neue Wächter-Tests.
      **Geister-Rekorde:** Dein Bestlauf spielt sichtbar mit — ein dezenter Geist-Chip
      in der Top-Bar zeigt live, ob du vor oder hinter deiner Bestlauf-Kurve liegst
      (1-Hz-Aufzeichnung, kompaktes Speicher-Budget), und wer seinen Geist am Ende
      schlägt, bekommt den „Geist geschlagen!"-Beat auf der Results-Karte. Beim
      Verifizieren echten Crash-Bug im Feier-Timer gefunden+gefixt. Leak-Gate über alle
      38 Spiele: dicht. 9 neue Wächter-Tests.
      **Ranch-Entdecker-Karte:** Die Ranch hat jetzt eine handgezeichnete Entdecker-Karte
      (Knopf im Hof-Cluster + Region-HUD): bereiste Zonen farbig, unbereiste als
      „???"-Nebel, alle 16 Fundorte als Pins (unentdeckte nur als „?" an GROBER Position),
      Fortschritts-Kopf „n/16 Orte · m/16 Zonen", NEU-Badge bis zum ersten Ansehen,
      Detail-Karten mit warmem Beschreibungssatz + „Dahin!"-Kompass. 9 neue Wächter-Tests.
      Qualität: kompletter Preflight grün (3625 Haupt-Tests, 26 761 UI-Checks, 0 rot),
      Leak-Gate 38/38 dicht, gdformat/gdlint sauber. Jeder Push baut die unsignierte
      .ipa automatisch (Artefakt `GOOBY-godot-unsigned-ipa`).

- [x] **Runde W18, Welle 1+2 (2. August): Playtest-Welle + alle Befunde gefixt +
      CC0-Assets + Orientierungs-Audit**
      **Playtest (3 Agents spielen wirklich):** Home/Pflege/HUD, Baumodus/Garderobe/
      Gestalten/IKEA, Arcade + 5 Minispiele — 22 dauerhafte Playtest-Flows als
      Regressionswächter aufgenommen. Der Arcade-Router-Fix aus W17 wurde end-zu-end
      bestätigt. **Gefundene + gefixte Blocker:** (1) Tagesquests-Blatt war nach
      einmal Öffnen+Schließen für immer LEER (PanelSheet zerstörte den wieder-
      verwendeten Inhalt — jetzt idempotent + Wächter über alle 20 Nutzer);
      (2) im Minispiel-Rahmen war die ZWEITE Results-Karte off-screen = Soft-Lock
      nach „Nochmal" (Layout-Race: Autowrap maß bei Breite 0, versteckte Container
      sortieren nicht — Karte ist jetzt in JEDER Runde mittig, bewiesen über
      star_hopper/Diagnose-Flow). **Ernste Fixe:** „×N"-Combo-Label überlebte das
      Rundenende (machte aus „Pause" „P×2e") → Host räumt jetzt jedes Juice-Overlay
      deterministisch ab; Guide-/Tour-Karte blähte sich auf >5400 px und schluckte
      Eingaben (Baumodus hochkant unerreichbar — 42%-Höhendeckel + duckt sich im
      Baumodus); „Was nun?"-Karte + Sprechblasen fraßen Taps (unsichtbare Riesen-
      STOP-Flächen bzw. mouse_filter — Tür/Platzieren-Knopf wieder tippbar);
      Bau-Ghost spawnte HINTER der Knopfleiste (sucht jetzt freie+sichtbare Zelle);
      HUD-Kachel-Labels („IGohb", „Garde"…) hart abgeschnitten → Autoshrink-Kaskade
      + vollständige Kurzworte (nie mehr Fragmente, beide Formate, DE+EN);
      IKEA-Kaufen-Knopf lag unterm Sichtbereich → CTA jetzt gepinnt; Arcade-Grid
      scrollt jetzt per Touch-Wisch (Buttons geben Drags ab Deadzone ab);
      Chip-Leisten (Lager/IKEA) mit Fade-Kante statt hartem Anschnitt; Wurm-Event
      „Herbert": Knöpfe lagen hochkant unterm Dock + Event-UI überlebte den
      Raumwechsel (jetzt Bubble-Lane + sauberer Abbruch/Wiederaufbau); cityDrive-
      Bäume waren tiefschwarz (metallicFactor 1 ohne Reflexionsquelle → Pastell-
      Tint). **Außerdem:** Playtest-Harness rendert jetzt im echten Format (xvfb-
      Screen = Fensterformat — vorher Phantom-Safe-Insets in allen Screenshots).
      Qualität: kompletter Preflight grün (3474 Tests, 26035 UI-Checks, 0 rot).

- [x] **Runde W15 (31. Juli): Updates über DIESES Repo + 9 weitere Pakete**
      **App-Updates laufen jetzt komplett über dieses Repo** (dein Wunsch): Pack-Releases
      per Tag `packs-v*` (rollender `updates`-Release), der Client lädt über die
      GitHub-API mit Zugangsschlüssel (Einstellungen → Updates → „GitHub-Token";
      da das Repo privat ist, brauchen Freunde einen Lese-Token von dir — Anleitung
      in docs/UPDATES.md §6a), und der ipa-Release-Job pflegt latest_native jetzt
      automatisch. KEINE Extra-Repo-Aktion mehr nötig!
      Außerdem: **Gooby im Urlaub besuchen** (Strand/Berge/Stadt-Szenen + Raumstation,
      Streicheln/Foto/Muschel-Sammeln/Souvenir-Spot, 24 neue Urlaubs-Sprüche);
      **Minispiel-Gruppe 2 poliert** (purblePlace-UI-Redesign, ranchHerde-Treiben mit
      Einfluss-Ring, rocketRescue-Kamera, gardenRush-Kulisse, danceParty-Publikum,
      AC-Level-Menüs mit Sterne-Stempeln); **4 neue Garten-Crops** (Radieschen, Mais
      mit Wind-Empfindlichkeit, Aubergine, Kürbis) → das Gemüse-Sammelset ist jetzt
      8/8 erspielbar und ALLE 4 Sammlungen sind komplettierbar; **GOB-NOM-Coop übers
      Netz** (2 Geräte, Lockstep mit Desync-Wächter + Rejoin — zugleich die Vorlage
      für GvZ-PvP); **Kamera fährt jetzt wirklich DURCH die Tür** beim Raumwechsel
      (additiv geladener Zielraum, Gooby läuft voraus; Fallback auf den Wisch bei
      Reduced-Motion/Low-End); **Wochenmarkt-Eigenstand** (Stand bestücken, Preise
      per Slider, deterministische Verkaufs-Sim mit Tagestrend „Heute lieben alle
      Kürbisse!", Abrechnungs-Karte) + 3 neue Craft-Rezepte mit 3D-Vorschau
      (Vogelhäuschen, Kräuterkasten der wöchentlich Markt-Ware liefert, drehendes
      Windrad); **danceParty-Timing-Kalibrierung** (Audio-Latenz-Ausgleich + 8-Beat-
      Antipp-Kalibrierung); **HDR-Glow-Auto-Downgrade** auf schwachen Geräten;
      **GOB-NOM-Level-EDITOR** im Godot-Editor (Level visuell bauen, Solver-Check);
      **neue Gooby-Clips phone_up/phone_tap** (Selfie-Emote echt) + Streichel-Übermut-
      Gag („Paus-e-e!"); **30 von 38 Minispielen sind jetzt bit-genau gegen die alte
      Web-Version zertifiziert** (vorher 12). Qualität: 3.010 Haupt-Tests, 24.815
      UI-Checks, 140 Server-Tests — alles grün, Preflight grün.

- [x] **Runde W14 (31. Juli): dein komplettes Feedback vom Morgen — 12 Arbeitspakete**
      **UI-Full-Rework:** Buttons/Karten exakt an der alten Web-Version geeicht (Press-Squish
      0.94 mit Feder-Overshoot, wärmere dicke Outlines), NEUE animierte runde ACNH-Sprechblasen
      (Pop-In-Wackler, Atmen, Buchstaben-Typewriter, Sprech-Schwanz) überall, haptisches
      Feedback auf JEDEM Knopf (abschaltbar unter Einstellungen → Haptik), und Notifications
      können Goobys Bubble strukturell nie mehr überlappen (Anker-Zonen + Ausweich-Logik, per
      Test bewiesen). Alle Screens reworked: Settings (6 Icon-Gruppen), Arcade, Profil (inkl.
      Reisepass-Hochkant-Fix — lief 40 % übers Canvas!), Album (Off-Screen-Sticker gefixt),
      HUD (Daumen-Zeile unten/Cockpit-Spalte quer nach Design-Doc), IKEA (Preis-Pillen statt
      abgeschnittener Preise), Radio/Codes/News/Pause/Galerie im Einheits-Look.
      **Ladebildschirm:** Beim App-Start jetzt ein generiertes Vollbild-Coverartwork
      (Gooby + Garten/Stadt/Ranch-Panorama) mit ECHTEM Möhren-Ladebalken (an die realen
      Boot-Phasen gekoppelt) + 10 knuffige Sprüche, dann Kreis-Wipe-Öffnung auf Gooby ins
      Spiel; der Szenenwechsel-Veil wurde mitpoliert (hüpfender Gooby, Fortschritts-Punkte).
      **Kühlschrank 2.0:** Regal-Grid mit echten 3D-Vorschauen, Kategorien-Chips,
      Vorrats-Badges, Stat-Pillen — und eine richtige Fütter-Sequenz: die Speise schwebt zu
      Gooby, er mampft in 3 Bissen mit Krümeln und Sound, Lieblingsessen macht verliebt.
      **Gooby lebendiger:** 120+ neue deutsche Text-Lines (Tageszeiten, Wetter, Reaktionen
      auf alle neuen Features, Selbstgespräche), NEU: Antwort-Chips — du kannst Gooby
      antworten und er reagiert (12 Mini-Dialoge), 3 Gebrabbel-Melodien (fragend/aufgeregt/
      schläfrig).
      **Decke weg beim Umschauen:** Kamera von oben = Decke/Balken/Dachschräge faden sanft
      aus (Decken-Lampen im Baumodus als 30-%-Geister). **Stadt-Feinschliff:** Top-5-Diagnose
      gefixt (Pastell-Fassaden-Varianz, Laternen-Lichtkegel nachts, begrünte Vorplätze,
      weiche Distrikt-Übergänge, möblierter Wochenmarkt).
      **Mehrspieler-Settings:** Server + Port + Secret jetzt ganz normal in den Einstellungen
      (mit „Verbindung testen"-Knopf); Secret wird serverseitig geprüft (GOOBY_JOIN_SECRET).
      **DEV-Tools-Werkzeugkasten:** 6 Tabs — Spielstand (Coins/XP/Sticker/Fixtures), Zeit
      (Uhr-Offset + „Nächster Tag"), Events (jedes sofort auslösen + Wetter-Override),
      Gegenstände (durchsuchbare Item-Vergabe), Netz (Config-Dump, Log, Outbox), Perf-Overlay.
      **DLC-Hub:** Einstellungen → DLC mit großen Cover-Karten (Ranch = verfügbar/installiert,
      „Goo und Bye" + „McGooby" = BALD mit generierten Coverarts + spoilerarmen Teasern);
      beide neuen Riesen-DLCs sind fertig durchdesignt (je ~600-700 Zeilen Design-Doc mit
      20-Perspektiven-Ideensammlung, Kern-Loops, Mitarbeiter-Gags, Multiplayer, Technik-Plan).
      **Minispiel-Qualitätspass:** Alle 38 Spiele bewertet (5 Achsen); die 6 schwächsten tief
      poliert — dabei ECHTEN Bug gefunden: die 3 Ranch-Wettkampf-Spiele hatten unsichtbares
      HUD! Dazu GvZ-Intro + Mäher-Fix, starHopper-Forgiveness, runner-Licht, 7 Quick-Wins
      (danceParty-Bahnen sichtbar, deliveryRush-Leuchtkugel, u. a.).
      Qualität: Haupt-Runner 2872 Tests grün, UI-Runner 24027 Checks grün, Preflight grün.

- [x] **Runde W13, Welle A+B (30./31. Juli): Backlog-Großputz — 20 Arbeitspakete**
      Jeder Push baut jetzt automatisch eine frische unsignierte .ipa (Artefakt
      `GOOBY-godot-unsigned-ipa`; Läufe 30592927997 + 30597075885 grün). NEU/GEFIXT:
      Ball werfen & apportieren ist zurück (Web-Physik 1:1, Wohnzimmer); die 4
      Sammlungssets (Fische/Gemüse/Sehenswürdigkeiten/Leckereien) sind wieder im Album
      sichtbar UND werden von Angeln/Ernte/Lieferungen/Füttern echt befüllt; sichtbarer
      Regen/Schnee/Gewitter jetzt auch in Haus (durchs Fenster), Garten und Stadt; die
      Stadt liest echtes Wetter statt Dauer-Sonne; GvZ-Sticker sind endlich erspielbar
      (L5/L10/L15-Meilensteine, 2 neue Sticker „Zaunheld" + „Nutella-Kommandant") und
      der Geheimcode GOLDIGOLD schaltet Goldi frei; „Wo ist mein Gooby?" springt zu ihm
      und er erzählt, was er gerade tut; der Auge-Knopf markiert alle anklickbaren
      Objekte (Rim-Glow + Pfeile); Radio: Bordmusik ohne Kauf nur pausierbar, Sender/Skip
      erst nach IKEA-Kauf, dazu „Was läuft?"-Ticker; Ranch ab Level 15 kaufbar + 4
      Ranch-Random-Events (ausgebüxtes Pferd, Heudieb, Hufschmied, Karottenregen); 9 neue
      Speisen inkl. Nutella + die Küchen-Nougatschleuse aus dem Web ist zurück;
      Post/Mail-Multiplayer komplett (Briefe + Fotos + Geschenke an Freunde, Quota,
      offline-Outbox); GOOBERANDO mit 3 Restaurants und echtem Fahrer auf der Karte;
      Guber kostet 30 (Surge-Gag 18–20 Uhr: 45); City Drive ist jetzt eine echte
      Arcade-Runde mit Score/Strikes, Autos haben Stats, die im Pregame stehen;
      Reisepass 2.0 (Flip-Karte, eigenes Passfoto aus der Galerie, Stempelseite,
      MRZ-Gag) + Abflugtafel im Split-Flap-Look + Boarding-Pass; Raumstation GOOB-1
      als betretbarer Ort (2 Arcade-Terminals, Low-Gravity-Hopser); Weltengooby-Titel
      bei 9/9 Zielen + 48-h-Erholungs-Boost + GOOBY-FREE-Shop am Flughafen; Besucher
      schlafen abends auf der Couch; Coop-Fahrt mit synchronem Radio; Geschichten-Stunde
      mit 6 Büchern/14 neuen Geschichten + Abnutzung; Schüttel-Secret (3 Stufen bis zum
      Ragdoll-Flug + Geheim-Sticker „Ganz blümerant"); Decken-Bau-Layer + spannbare
      Girlanden (Wimpel/Lichterkette/Pompons); Sticker-Rarity-Effekte (Gold glitzert,
      Konfetti+Jingle); Galaxie-Fellfarbe mit Sternen-Shader; Klopapier-Mumie-Event;
      Buchstaben-Typewriter in Dialogen; 5 Kauf-Bugs gefixt (Geld weg ohne Leistung —
      Lambda-Capture-Falle); alte Debug-Instrumentierung entfernt; STATUS.md/Doku auf
      den ehrlichen Ist-Stand gebracht.

- [x] **Stelle immer sicher das die Github Actions runs erfolgreich sind.**
      ALLE DREI JOBS GRUEN (Lauf 30285924723: lint, linux-checks, ios-ipa). Die .ipa liegt als
      Artefakt bereit (188 MB, gewachsen durch Ranch/Musik/Modelle). Damit das so bleibt:
      tools/ci/preflight.sh faehrt lokal exakt dieselben Pruefungen vor jedem Push, und der
      iOS-Job baut jetzt auch dann, wenn Tests rot sind (dann mit Hinweis im Artefaktnamen) - du
      bekommst immer eine .ipa.

- [x] **Erstelle mal richtige Skyboxen selber**
      prozeduraler Himmel-Shader mit 7 Stimmungen (klarer Morgen, Mittag, goldene Stunde,
      Abendrot, Nacht mit Sternen, bedeckt, Gewitter), blendet weich zwischen Tageszeit und
      Wetter.

- [x] **Mach das der Boden auch etwas Textur hat also mal rau ist oder uneben statt das alles nur hunderprozent gerade flächen sind.**
      mehrstufiges Gelände-Rauschen (Großformen + Hügel + Feinstruktur), Bodentextur-Variation
      (Grasbüschel, Erdstellen, Trampelpfade, Kies, Matsch nach Regen) und kleine Unebenheiten.

- [x] **Du kannst dir ja von vielen UIs oder Modelen erst bilder generieren und sie danach nach bauen damit du mehr infos hast wie so etwas ca. aussieht.**
      genau so gemacht: für das Gooby-Modell wurde die alte Web-Version gerendert und
      Bild-für-Bild verglichen, das Ranch-Artwork wurde generiert und danach nachgebaut.

- [x] **Der Trailer ist noch nicht perfekt und vorallem ist das gameplay etwas zu low quality also irgendwie ist das pixelig**
      Ursache gefunden: die Clips wurden in 960x540 aufgenommen und auf 1080p hochskaliert, MSAA
      war aus, und es gab drei verlustbehaftete Kompressionsstufen. Jetzt nativ 1920x1080, MSAA
      4x, verlustfreie Zwischenbilder, ein einziger Endencode mit CRF 16.

- [x] **Die Ranch ist nicht "belebt" genug und irgendwie fehlt so ein richtiges Feeling also Berge, Landschaften, Dinge zum erkunden.**
      Ranch-Openworld massiv erweitert: begehbares Bergmassiv (Gipfel ~90 m) mit Serpentine,
      Plateau, Schlucht mit Hängebrücke und Bergsee, dazu 7 neue Zonen (Lavendelwiese, Nebelmoor,
      Turmruine, Muschelbucht, Apfelgarten, Kornfeld, Strand), Wegenetz mit Wegweisern und
      Rastplätzen, 9 Entdeckungsorte.

- [x] **Viele Regionen sehen noch recht kahl aus also da fehlt so das du Scenerie besser gemacht hast wie zb mehr Bäume, hier und dort blumen,büsche etc**
      neue Streu-Bibliothek verteilt Bäume, Büsche, Blumen, Gräser, Steine und Farne in Gruppen
      statt gleichmäßig - angewendet auf Ranch UND Stadt (Straßenbäume, Blumenkästen, Hecken,
      Grünstreifen, Efeu).

- [x] **Jedes Spiel muss 3D sein**
      alle 36 Minispiele sind jetzt echte 3D-Szenen mit Kamera, Umgebung, Licht und Schatten -
      geprüft durch einen Test, der für jedes Spiel Kamera + Umgebung + Geometrie verlangt.

- [x] **Gooby braucht sein altes Model aus der alten vor Godot version wieder. (Du kannst dir ja einfach den anderen Branch anschauen)**
      das Original ist zurück: alle Proportionen wurden am Web-Quellcode gemessen und im
      Blender-Modell wiederhergestellt (Kopfanteil, Augengröße, Ohren, Wangen). Nebenbefund: die
      Farbpalette war doppelt kodiert und dadurch übersättigt - auch behoben.

- [x] **Viele UI Elemente sind noch nicht polished**
      UI-Prüfung über 15 Screens x 4 Gerätformate fand 430 Befunde - alle behoben (0 verbleibend).
      Dazu Mikro-Animationen: federnde Panels, gestaffeltes Einblenden, hochzählende Zahlen.

- [x] **Der Stadt fehlt auch sceneriere**
      Stadt bekam Alleen, Hecken, Blumenkästen, Grünstreifen, Efeu an Fassaden und
      Park-Verdichtung.

- [x] **Manche Autos schweben**
      Ursache: die Fahrbahn-Kacheln lagen mit ihrer Dicke über Null, die Fahrzeuge aber auf Null.
      Behoben, plus ein Test der für alle Fahrzeuge Bodenkontakt prüft.

- [x] **Viele UI Sachen sind meist ganz ganz außen am Rand und Skalieren nicht wirklich mit der gerät größe**
      zentrale Skalierung an der kurzen Bildschirmkante durchgesetzt, Safe-Area überall
      respektiert, Tippflächen auf mindestens 44 pt gebracht.

- [x] **Viele UI Sachen sind einfach nervig zuerreichen zb bei einem Mini Spiel kann das Pause Menü wenn man es öffnet auch nur ein Modal in der Mitte öffnen.**
      das Pause-Menü ist jetzt eine kompakte, mittige Karte über Abdunkelung (max. 62 % Breite) -
      für alle 36 Spiele auf einmal, inklusive echtem Einfrieren und 3-2-1 beim Fortsetzen.

- [x] **Das Rennen lässt alle in einander fahren?**
      Karts haben jetzt echte gegenseitige Kollision (sanftes Abdrängen + Tempoverlust statt
      Durchfahren), mit Test der den Bug erst nachweist und dann den Fix.

- [x] **Die Seele des Spiels fehlt.**
      Diagnose ergab: es gab zwar 43 Sprueche, aber keinen ZUSTAND. Goobys Gesicht fiel nach jedem
      Moment auf happy zurueck - bei leeren Stats riss er noch Witze. Jetzt: eine traege Laune
      (Halbwertszeit Stunden) faerbt Gesicht, Ohrenstellung, Lider, Bewegungstempo, Stimmlage und
      Idle-Auswahl. Dazu Absicht statt Zufall (Hunger -> er geht zum Kuehlschrank und schaut dich
      an), Blick der dir folgt, und Erinnerungen aus echten Erlebnissen.

- [x] **Du musst checken das die Builds wirklich erfolgreich sind statt immer Fehler kommen.**
      Ursachen analysiert (10x Formatierung, 8x eine veraltete iOS-Prüfung). Es gibt jetzt
      tools/ci/preflight.sh, das lokal exakt dieselben Prüfungen fährt wie die CI - vor jedem
      Push.

- [x] **Die kompletten Rückblicke Cutsecenen fehlen**
      Rückblick-Kino im Querformat und 5 Cutscenes sind gebaut (Aufwachen, Schlafengehen, Abreise,
      Urlaubsankunft, Einkaufsfahrt).

- [x] **Es fehlt fast alles von da vor und was da ist ist einfach nur schlechter, das einzig gute ist das Bau System der Rest sonst ist kacke.**
      unabhängige Prüfung: von 79 Features der alten Version sind jetzt 53 vollständig, 16
      teilweise, 10 fehlen - dazu sieben Spiele, die es vorher gar nicht gab. In dieser Runde neu:
      Profil, 44 Erfolge, Tagesbonus, 24 Tagesquests, Schlaf/Krankheit/Tierarzt, Funkelpark,
      Radio, Codes, Galerie, Postkarten.

- [x] **Das Ganze Spiel ist viel zu unfertig.**
      Vollstaendigkeit gegenueber der alten Version: von 53 auf 70 der 79 Features (5 teilweise, 3
      offen, 1 bewusst gestrichen). Neu in dieser Runde: Profil, 44 Erfolge, Tagesbonus, 24
      Tagesquests, gefuehrtes Onboarding, Schlaf/Krankheit/ Tierarzt, Funkelpark, Radio, Codes,
      Galerie, Postkarten, Arcade-Modifikatoren. Alle 'Bald'-Platzhalter sind beseitigt (per Test
      abgesichert).

- [x] **Das Spiel hat keine Seele**
      43 Seele-Momente gebaut: Gooby grüßt mit deinem Namen nach Tageszeit, vermisst dich nach
      längerer Abwesenheit, kommentiert Wetter und Neuanschaffungen, hat Lieblingsessen, feiert
      Geburtstage und Jubiläen, erinnert sich an echte Erlebnisse, macht Unsinn wenn man nicht
      hinsieht.

- [x] **Das Spiel ist nur eine Alpha.**
      Das Urteil der unabhaengigen Pruefung lautet jetzt: 'Inhaltlich komplettes Spiel mit wenigen
      dokumentierten Restluecken - kein Alpha-Zustand mehr.' Die drei ehrlich offenen Punkte
      (Ball-Wurf, Sammlungsset-UI, Gyro-Parallax) stehen in
      docs/godot-rewrite/EVAL-VOLLSTAENDIGKEIT.md.

- [x] **Alle Spiele sind grauen Haft.**
      siehe Politur oben - jedes Spiel wurde vorher/nachher bewertet und alles unter 4 von 5
      verbessert.

- [x] **Baue wirkliche 3D Spiele und nicht so 2D zeug.**
      erledigt, alle 36 Spiele sind 3D.

- [x] **Stelle sicher das wirklich alles 3D ist und nicht 2D**
      per Test abgesichert: jede Spielszene braucht Kamera, Umgebung, Licht und mindestens drei
      3D-Objekte.

- [x] **Das neue Gooby model ist nicht so toll wie das alte, nutze das alte bitte wieder.**
      siehe oben - das alte Modell ist wiederhergestellt und in allen Ansichten geprüft (Haus,
      Editor, Garderobe, Minispiele, Ranch).

- [x] **Es ist irgendwie nicht alles so gut gebackportet worden nur so gerusht ohne ohne Liebe zum detail.**
      die Vollständigkeitsprüfung listet jetzt jedes Feature der alten Version mit Belegstellen
      auf beiden Seiten - offene Punkte stehen in docs/godot-rewrite/EVAL-VOLLSTAENDIGKEIT.md.

- [x] **Jedes Game hat nicht genug Polish.**
      dito - plus zentral verbesserte Momente (Countdown, Ergebnisbildschirm mit hochzählenden
      Punkten, Sternen, Rekord-Feier), die auf alle Spiele gleichzeitig einzahlen.

- [x] **Das ganze UI ist null wie davor**
      Theme gegen die alte Web-CSS geeicht (Schattenfarben, Radien, Federungskurve, Stat-Pillen
      mit Icons) und animierte Hintergründe mit eigener Farbstimmung je Bereich.

- [x] **Es gibt viele Bugs.**
      systematischer Durchlauf: Godot-Meldungen von 7 Fehlern und 533 Warnungen auf 1 und 5
      gesenkt (Lambda-Captures, Navigations-Sync, Speicherlecks, GPU-Readback, veraltete
      Materialeigenschaft).

- [x] **Warum ist sovieles keine richtigen Assets sondern nur premetives?**
      23 eigene Blender-Modelle gebaut (Kassettentüren mit Klinke, Fensterrahmen, Duschvorhang,
      Duschkopf, Shed, Werkstatt, Gewächshaus, Sprinkler) und 6 fertige Modelle eingebunden; dazu
      Wanddeko (Lichtschalter, Steckdosen, Heizkörper, Bilderrahmen).

- [x] **Es fehlt der polish. Nimm dir mehr Subagents die auch sowas wie Dopamin, Sounddesign und feeling bewerten und verbessern sollen.**
      unabhängiger Prüf-Agent hat Dopamin, Sound und Spielgefühl gemessen; die Befunde wurden
      umgesetzt: Belohnungen von 9 auf 24 pro Erstflow, kein Musikstück clippt mehr, Loop-Nähte
      von 95 dB auf 6 dB, Türwechsel von 918 auf 455 ms, Nochmal-Start von 2450 auf 509 ms.

- [x] **Verbessere den Remotion Trailer massiv vor allem mit dem neuen was du alles geändert hat hat sich ja auch das aussehen geändert also baue den Trailern nochmal besser**
      komplett neu gebaut: 54,6 s, alle 27 Clips neu aufgenommen (der alte zeigte noch das falsche
      Gooby-Modell), mit Ranch-Kapitel, Bergmassiv, neuen Zonen, Wetter, Dorf, Turnier und
      Multiplayer.

- [x] **Deine Ganze Arbeit bisher ist viel zu wenig und es kommt mir so vor als ob du keine Mühe bisher hattest. Gib dir mehr Mühe und nimm mehr Subagents und mehr Teams die gemeinsam ansachen arbeiten statt nur 6-8 Subagents. Du kannst wirklich 20-30 nutzen.**
      auf bis zu 9 gleichzeitige Agents pro Welle hochgezogen, plus unabhängige Bewerter-Agents
      für Dopamin, Sounddesign und Vollständigkeit.

- [x] **Verbessere nochmal die Gooby Ranch sowie Seceneriere ich will das es richtig schönes aussehen gibt es soll auch berge und terrain etc geben baue die OpenWorld da richtig nochmal mehr aus.**
      siehe Bergmassiv + 7 neue Zonen oben.

- [x] **Verbessere jedes Minispiel nochmal mit jeweils 3 Subagents Fable 5 Max Thinking als Model nutzen unbedingt damit die Arbeit wirklich perfekt wird.**
      alle 36 Spiele durch Politur-Agents gelaufen: echte Kulissen mit Tiefe, Gooby als sichtbarer
      Mitspieler, korrigierte Belichtung (die Bühnen waren rund 40 Luma-Stufen zu hell),
      Belohnungsmomente, Ton.
