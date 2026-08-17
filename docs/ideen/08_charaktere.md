# MONKEY MONEY — Ideenpapier 08: Charaktere, Avatare & Customization

Ideen-Agent 8/20 · Thema: Affen-Ensemble, Customization, Charakter-Präsenz im Match, AI-Spieler.
Format pro Idee: **Aufwand** S/M/L · **Prio** MUST/SHOULD/COULD.

Rahmenannahmen (aus Projektkontext): Bildschirm-App in Godot 4.4.1, Handys sind
Browser-Controller (Node/Express-Server), Assets werden selbst gebaut
(Blender/prozedural, keine gekauften Packs), Dev-Umgebung ist eine 4-Kern-VM.
Zeit-/Zufallslogik immer injizieren (Clock-Muster, RNG als Parameter), damit
Reaktions- und Bot-Verhalten testbar bleibt.

---

## Teil A — Das Affen-Ensemble (Ideen 1–12)

Design-Grundregel für ALLE Charaktere: Jeder Affe muss **als schwarze
Silhouette in 0,5 s erkennbar** sein (Jackbox-Prinzip). Deshalb bekommt jeder
genau EIN übertriebenes Silhouetten-Merkmal (Kopfform, Körperbau oder
Dauer-Prop). Farben sind austauschbar (Customization), die Silhouette nie.

### Idee 1 — „Don Bananas" (der Pate) — Aufwand M · Prio MUST
- **Persönlichkeit:** Schmieriger Affen-Pate, der jede Quiz-Antwort klingen
  lässt wie ein Angebot, das man nicht ablehnen kann.
- **Silhouette:** Breite Schultern im Nadelstreifen-Sakko + tief sitzender
  Fedora-Hut, dazu eine Banane, die er wie eine Zigarre hält.
- **Signature-Reaktionen:** Jubel: zieht ruckartig am Revers, schnippt mit den
  Fingern, ein einzelner Geldschein segelt herab. Frust: drückt die
  Bananen-Zigarre langsam im Aschenbecher aus, Kopfschütteln in Zeitlupe.
  Sieg-Pose: lehnt lässig an einem aufgeklappten Geldkoffer und tippt sich an
  die Hutkrempe.
- **Sound-Charakter:** Tiefes, kehliges Brummen, „Capisce?"-Grunzer,
  musikalisch mit Kontrabass-Pizzicato unterlegt.

### Idee 2 — „Gitti Giro" (die Buchhalterin) — Aufwand M · Prio MUST
- **Persönlichkeit:** Pedantische Buchhalter-Äffin, die jeden Punkt sofort
  nachrechnet und bei Fehlern der ANDEREN sichtbar aufblüht.
- **Silhouette:** Turmhohe Bienenkorb-Frisur mit quer steckendem Bleistift +
  Brillenkette; hält immer einen Abakus.
- **Signature-Reaktionen:** Jubel: schiebt drei Abakus-Kugeln mit Karateschlag
  auf einmal rüber, kurzes zackiges Nicken. Frust: Brille beschlägt (weißer
  Dampf), sie putzt sie hektisch. Sieg-Pose: stempelt mit einem riesigen
  „GEBUCHT"-Stempel in die Luft, Konfetti aus Quittungen.
- **Sound-Charakter:** Rechenmaschinen-Rattern, Kassen-„Kaching", spitzes
  „Tse-tse-tse" bei Fehlern anderer.

### Idee 3 — „Kiki Krawall" (das Chaos-Äffchen) — Aufwand M · Prio MUST
- **Persönlichkeit:** Hyperaktives Mini-Äffchen, das jede Runde behandelt wie
  ein ausverkauftes Stadionfinale.
- **Silhouette:** Kleinster Charakter im Cast, dafür riesige
  Antennen-Wuschelfrisur, die ständig nachwippt (Sekundär-Animation).
- **Signature-Reaktionen:** Jubel: dreifacher Salto auf der Stelle, Frisur
  kreist mit Verzögerung nach. Frust: wirft sich bäuchlings aufs Podium und
  trommelt mit Fäusten und Füßen. Sieg-Pose: Sprung in die Kamera-Ebene, hängt
  kurz „am Bildschirmrand" wie an einer Reckstange.
- **Sound-Charakter:** Hohe Quietscher, Kazoo-Fanfaren, bei Frust ein
  Luftballon, dem die Luft ausgeht.

### Idee 4 — „Baron Bodo von Bananenstein" (der Adelige) — Aufwand M · Prio MUST
- **Persönlichkeit:** Verarmter Affen-Adeliger, der so tut, als spiele er nur
  zum Zeitvertreib mit, aber verzweifelt das Preisgeld braucht.
- **Silhouette:** Zylinder + Umhang mit Stehkragen + Monokel; hält eine Banane
  am ausgestreckten Arm wie ein Weinglas.
- **Signature-Reaktionen:** Jubel: dezentes Ein-Finger-Klatschen, dann platzt
  es aus ihm heraus und er wirft den Zylinder hoch (darunter: zweiter, kleinerer
  Zylinder). Frust: Monokel ploppt heraus und baumelt am Kettchen. Sieg-Pose:
  Umhang-Schwung, verbeugt sich vor sich selbst.
- **Sound-Charakter:** Näselndes „Hohoho", Cembalo-Stinger, Monokel-„Plopp".

### Idee 5 — „Rico Rendite" (der Krypto-Bro) — Aufwand M · Prio SHOULD
- **Persönlichkeit:** Dauer-optimistischer Zocker-Affe, der jede richtige
  Antwort als Beweis seiner „Strategie" verkauft und jede falsche als „Dip".
- **Silhouette:** Basecap verkehrt herum + überdimensioniertes Smartphone, das
  er nie weglegt; Energy-Drink-Dose in der Schwanzspitze.
- **Signature-Reaktionen:** Jubel: „To the moon"-Rakete aus Pappe steigt hinter
  ihm auf. Frust: starrt aufs Handy, ein roter Chart-Pfeil durchbohrt das
  Podium nach unten. Sieg-Pose: Sonnenbrille fällt aus dem Off auf seine Nase,
  Doppel-Daumen hoch.
- **Sound-Charakter:** Airhorn, Benachrichtigungs-Pings im Dauerfeuer,
  „Diamond Hands, Baby!"-Kieksen.

### Idee 6 — „Oma Zinseszins" (die Unterschätzte) — Aufwand M · Prio SHOULD
- **Persönlichkeit:** Gemütliche Großmutter-Äffin, die alle einlullt und dann
  eiskalt die Finalrunde gewinnt — sie hat schließlich Zeit mitgebracht.
- **Silhouette:** Gebückte Haltung, Kopftuch mit Knoten, riesige Handtasche am
  Unterarm, Strickzeug in den Händen.
- **Signature-Reaktionen:** Jubel: strickt in Sekundenschnelle einen Schal mit
  „1. PLATZ"-Muster fertig und hält ihn hoch. Frust: strickt demonstrativ
  weiter, eine einzelne Masche fällt (Kamera-Zoom darauf). Sieg-Pose: öffnet
  die Handtasche, ein Goldbarren-Stapel schaut heraus, sie zwinkert.
- **Sound-Charakter:** Klappernde Stricknadeln, Teetassen-Klirren, leises
  zufriedenes „Jaja, der Zinseszins…".
- **Bonus-Gag:** Ihre Handtasche ist ihr Buzzer — beim Drücken schnappt der
  Verschluss hörbar zu.

### Idee 7 — „Pumper-Paule" (der Gym-Gorilla) — Aufwand M · Prio SHOULD
- **Persönlichkeit:** Gutmütiger Kraftprotz, der Wissen wörtlich für Muskelsache
  hält („Ich hab die Antwort GEDRÜCKT, also stimmt sie").
- **Silhouette:** Massives V-Profil, winziger Kopf, Tanktop, Shaker-Becher in
  der Faust — mit Abstand breiteste Silhouette im Cast.
- **Signature-Reaktionen:** Jubel: Doppel-Bizeps-Pose, das Podium unter ihm
  bekommt einen Riss. Frust: zerdrückt den Shaker, Protein-Fontäne. Sieg-Pose:
  stemmt sein eigenes Podium samt Namensschild über den Kopf.
- **Sound-Charakter:** Tiefe Grunzer, Hantel-Scheppern, Shaker-Rasseln als
  Buzzer-Vorschlag.

### Idee 8 — „Schnarch-Schorsch" (der Tiefenentspannte) — Aufwand M · Prio SHOULD
- **Persönlichkeit:** Faultier-artiger Affe, der zwischen den Fragen wegnickt
  und trotzdem in letzter Sekunde buzzert — niemand weiß, wie.
- **Silhouette:** Hängende Schultern, halb geschlossene Lider, Zipfelmütze mit
  Bommel, die bei jeder Bewegung eine Sekunde nachschwingt.
- **Signature-Reaktionen:** Jubel: erwacht schlagartig, kurzer euphorischer
  Armwurf, schläft im Stehen wieder ein. Frust: zuckt mit den Schultern, gähnt,
  dreht sich demonstrativ zur Seite. Sieg-Pose: liegt quer auf dem Podium wie
  auf einem Sofa, Siegerkranz rutscht ihm über die Augen wie eine Schlafmaske.
- **Sound-Charakter:** Sägendes Schnarchen mit Melodie, Gähn-Glissando, sein
  Buzzer klingt wie ein Wecker.
- **Synergie:** Perfekter Default für den AFK-/Einschlaf-Gag (Idee 21).

### Idee 9 — „Glitzer-Gina" (die Diva) — Aufwand M · Prio SHOULD
- **Persönlichkeit:** Showgirl-Äffin, die überzeugt ist, dass die Sendung nach
  ihr benannt werden sollte, und jede Kamera-Einstellung für sich reklamiert.
- **Silhouette:** Hochgesteckte Federkrone + Federboa, eine Hand permanent in
  Pose über dem Kopf.
- **Signature-Reaktionen:** Jubel: Spotlight schwenkt (auch unaufgefordert) auf
  sie, Glitzer-Explosion, Kusshand. Frust: reißt der Boa eine Feder aus und
  pustet sie weg. Sieg-Pose: Scheinwerfer-Kegel von oben, sie „badet" im Licht
  und winkt wie bei einer Krönung.
- **Sound-Charakter:** Glöckchen-Schimmer, gehauchtes „Darling!", kurzer
  Vegas-Bläsersatz.

### Idee 10 — „Professor Pavian" (der Besserwisser) — Aufwand M · Prio SHOULD
- **Persönlichkeit:** Emeritierter Quiz-Theoretiker, der auch falsche Antworten
  noch als „im weiteren Sinne korrekt" verteidigt.
- **Silhouette:** Riesiger glänzender Denker-Schädel, winzige Lesebrille auf
  Nasenspitze, Ellenbogen-Flicken-Sakko, Zeigestock.
- **Signature-Reaktionen:** Jubel: tippt sich mit dem Zeigestock an die Schläfe
  und nickt in die Kamera („wusste ich"). Frust: schreibt wild auf eine
  unsichtbare Tafel, streicht alles durch. Sieg-Pose: lässt sich einen
  Doktorhut aufsetzen, wirft ihn NICHT (zu würdelos), hält ihn nur fest.
- **Sound-Charakter:** „Ähem-ähem", Kreidequietschen, Seitenblättern; sein
  Buzzer ist eine Schulglocke.

### Idee 11 — „Klaus Kleingeld" (der Underdog) — Aufwand M · Prio COULD
- **Persönlichkeit:** Chronisch pleite, aber unerschütterlich zuversichtlich —
  der Sympathieträger, dem der ganze Raum den Sieg gönnt.
- **Silhouette:** Trägt ein Fass mit Hosenträgern statt Kleidung, ein einzelner
  Knopf fliegt regelmäßig ab; um ihn kreist EINE Fliege.
- **Signature-Reaktionen:** Jubel: schüttelt das Fass, eine einzige Münze
  klimpert darin — er feiert sie wie einen Jackpot. Frust: die Fliege setzt
  sich auf seine Nase, er schielt sie an. Sieg-Pose: das Fass läuft plötzlich
  mit Goldmünzen über, er weint vor Glück.
- **Sound-Charakter:** Einzelne Münze, die scheppernd ausrollt, trauriger
  Posaunen-Wah-Wah, bei Siegen ein komplett übertriebener Jackpot-Sound.

### Idee 12 — „Fiona Fifty-Fifty" (die Zockerin) — Aufwand M · Prio COULD
- **Persönlichkeit:** Eiskalte Glücksspielerin, die grundsätzlich alles auf
  eine Karte setzt — inklusive der Antworten, die sie eigentlich weiß.
- **Silhouette:** Flacher Riverboat-Gambler-Hut + eine Münze, die PERMANENT
  über ihrer offenen Hand rotiert (Loop-Animation = Erkennungszeichen).
- **Signature-Reaktionen:** Jubel: fängt die Dauer-Münze zum ersten Mal, küsst
  sie, wirft sie wieder an. Frust: Münze fällt zu Boden und rollt aus dem Bild,
  sie schaut ihr lange nach. Sieg-Pose: Kartenfächer aus Geldscheinen vor dem
  Gesicht, nur die Augen schauen darüber.
- **Sound-Charakter:** Münz-„Pling" im Loop, Roulette-Rattern,
  Kartenmisch-Schnarren als Buzzer.

**Roster-Empfehlung:** v1 startet mit den vier MUST-Charakteren (Don Bananas,
Gitti Giro, Kiki Krawall, Baron von Bananenstein) — maximal kontrastierende
Silhouetten (breit / hochfrisiert / winzig / Zylinder). Die übrigen acht sind
Shop-Unlocks bzw. Update-Content, was gleichzeitig die All-time-Money-Ökonomie
füttert (siehe Idee 16).

---

## Teil B — Machart & Technik (Ideen 13–14)

### Idee 13 — Machart v1: 2D-Pappfiguren mit Gelenken („Kasperletheater deluxe") — Aufwand L (einmalig Pipeline), dann S pro Charakter · Prio MUST
- **Stil:** Jackbox-artige Cutout-Optik: Charaktere wie aus Pappe
  ausgeschnitten, sichtbare „Niet-Gelenke" an Schultern/Hüften, leichte
  Wackel-Physik. Der Stil verzeiht einfache Formen, sieht absichtlich
  handgemacht aus und ist mit Eigenmitteln (Inkscape/Blender-Grease-Pencil →
  PNG-Atlas) realistisch produzierbar.
- **Technik Bildschirm (Godot):** Pro Charakter eine `Skeleton2D`/`Polygon2D`-
  bzw. simple `Sprite2D`-Hierarchie mit ~10–14 Teilen (Kopf, Kiefer, Torso,
  2×Ober-/Unterarm, 2×Bein, Schwanz, Hut-Slot, Hand-Prop-Slot). Alle 12 Affen
  teilen sich EIN Grundskelett; Silhouetten-Merkmale sind ausgetauschte
  Teile-Sprites + 1–2 Extra-Bones (Frisur, Dauer-Münze). Animationen (Idle,
  Jubel, Frust, Sieg, Schlafen, Buzz) werden EINMAL aufs Standardskelett
  gebaut und von allen geerbt; Signature-Reaktionen sind zusätzliche Clips pro
  Charakter.
- **Farben ohne Asset-Duplikate:** Fell-/Kleidungsfarben über einen
  Palette-Swap-Shader (Graustufen-Masken + Gradient-Map) — ein Texturatlas
  bedient sämtliche Farb-Customization (Idee 15) ohne neue Downloads.
- **Performance:** 8 Skelett-Avatare + Partikel sind auf jeder Ziel-Hardware
  trivial; auf der 4-Kern-Dev-VM laufen Headless-Tests rein datengetrieben
  (Reaktions-Trigger als Resources, Zeit injiziert), Rendering wird nur im
  Boot-Smoke angefasst.
- **Handy-Browser:** KEIN Godot/WebGL auf dem Controller. Der Mini-Avatar
  (Idee 23) ist eine geschichtete SVG/PNG-Figur mit CSS-Keyframe-Animationen
  (nicken, zittern, jubeln) — wenige KB, läuft auf jedem Alt-Handy.

### Idee 14 — Machart-Upgrade später: Low-Poly-3D mit Vertex-Colors — Aufwand L · Prio COULD
- **Stil:** Flat-shaded Low-Poly (300–800 Tris pro Affe), NUR Vertex-Colors,
  keine Texturen — das ist in Blender skript-/prozedural-freundlich (bestehende
  `tools/blender/`-Pipeline nutzbar) und behält den „selbstgebaut"-Charme.
- **Regel:** Gleiche Proportions-Sprache wie die 2D-Cutouts (ein Merkmal pro
  Silhouette), ein gemeinsames Rig (~20 Bones), Animations-Sharing über
  identische Skelette. So bleibt die Charakter-Identität beim Umstieg erhalten
  und Hüte/Props (Idee 15) passen per Bone-Attachment weiter.
- **Grenze:** 3D nur auf dem Bildschirm; Handy-Controller bekommen weiterhin
  2D (notfalls vorgerenderte Sprite-Turnarounds aus Blender). Erst angehen,
  wenn v1-Loop steht — 2D-Cutout ist kein Platzhalter, sondern ein valider
  Endstil (siehe Jackbox).

---

## Teil C — Customization-System (Ideen 15–18)

### Idee 15 — v1-Basis: Farben, Muster, Hut-Slot — Aufwand M · Prio MUST
- **v1 kostenlos für alle:** 8 Fellfarben (u. a. Schoko, Gold-Blond, Aschgrau,
  Flamingo-Rosa) + 4 Muster (uni, Bauchfleck, Ringelschwanz, „Anzug-Fell" mit
  aufgemaltem Krawatten-Muster) + 6 Starter-Kopfbedeckungen: Banane (quer wie
  ein Barett), Pappkrone, Propellermütze, Melone, Stirnband, „nix" (Stolz-Glatze).
- **Slots-Architektur von Anfang an:** Kopf (Hut), Gesicht (Brille/Monokel),
  Hand (Prop), Körper (Outfit), Buzzer-Sound, Sieg-Pose, Namensschild, Taunt-Set.
  Auch wenn v1 nur Farbe+Hut freischaltet — die Slots im Datenmodell (ein
  Resource-Profil pro Spieler) verhindern späteren Umbau.
- **UX:** Anpassung passiert auf dem HANDY in der Lobby (privat, kein
  Bloßstellen), der Bildschirm zeigt jede Änderung live am Lobby-Podium mit
  einem kleinen „Umzieh-Wirbel" — das ist kostenlose Lobby-Unterhaltung.

### Idee 16 — Shop-Ökonomie: Money-Thema-Unlocks mit Raritäten — Aufwand M · Prio SHOULD
- **Währung:** All-time-Money (Lebenszeit-Gesamtverdienst, wird durchs Spielen
  verdient, nie abgezogen — Shop „kauft" gegen einen separaten ausgebbaren
  Kontostand, All-time bleibt als Prestige-Zahl stehen; alternativ simpler:
  Unlock-Schwellen statt Bezahlen, dann ist Grinden = Sammeln).
- **Raritätsstufen:** Blech (billig): Sparschwein-Mütze, Kleingeld-Kette,
  Quittungs-Schal. Silber: Monokel, Bananen-Anzug, Dagobert-Zylinder,
  Krawatte aus einem echten Geldschein. Gold (teuer): Goldbarren-Rucksack,
  Krone mit Preisschild dran, Dollarzeichen-Sonnenbrille, kompletter
  Nadelstreifen-Dreiteiler. Diamant (Prestige-Grind): **Gold-Fell** (Charakter
  komplett vergoldet, eigener Glanz-Shader) — das sichtbare „Ich spiele das
  seit Ewigkeiten"-Statussymbol.
- **Charaktere als Unlocks:** Die 8 Nicht-Starter-Affen (Ideen 5–12) kosten
  gestaffelt; jeder bringt seine Signature-Reaktionen mit — Charaktere sind
  damit die wertvollsten Shop-Items überhaupt.
- **Wichtig:** Alles rein kosmetisch, niemals Gameplay-Vorteile — die Party-App
  darf kein Pay/Grind-to-win-Gefühl erzeugen.

### Idee 17 — Sieg-Posen & Buzzer-Sounds wählbar — Aufwand M · Prio SHOULD
- **Sieg-Posen (Slot):** Jeder Charakter hat seine Signature-Pose gratis;
  zusätzlich kaufbare Universal-Posen: „Geldscheine zählen und der Kamera
  zufächern", „Rückwärts in einen Münzhaufen fallen (Dagobert-Dive)",
  „Mikrofon-Drop mit Banane", „Steuererklärung zerreißen". Wird bei Rundensieg
  UND Endsieg abgespielt — der meistgesehene Customization-Moment.
- **Buzzer-Sounds (Slot):** v1: 4 Basis-Sounds (klassischer Quiz-Buzzer,
  Affenschrei, Kassen-Kaching, Fahrradklingel). Shop: Wecker, Airhorn,
  Schulglocke, Jackpot-Slot-Machine, „Öööh"-Falschantwort-Sound (ironisch),
  Opern-„Aaah". Der Buzzer-Sound ertönt AUF DEM BILDSCHIRM, wenn dieser
  Spieler buzzert/lockt — dadurch erkennen alle im Raum akustisch, WER gedrückt
  hat, bevor der Name eingeblendet wird. Charakter-Buzzer (Omas
  Handtaschen-Schnapper, Schorschs Wecker) kommen mit dem Charakter.
- **Regel:** Max. ~1,2 s pro Sound, Lautheits-normalisiert, damit kein
  Troll-Sound die Show sprengt.

### Idee 18 — Namensschilder & Taunts (mit Anti-Spam) — Aufwand S–M · Prio SHOULD (Taunts) / COULD (Schilder-Stile)
- **Namensschilder:** Am Podium hängt unter jedem Affen ein Schild mit
  Spielername. Stile als Unlocks: Pappe mit Filzstift (v1), Holz-Brandmalerei,
  Neon-Leuchtreklame, Gold-Gravur mit Serifenschrift, „von der Bank gepfändet"
  (Schild mit Siegel-Aufkleber). Zweizeilig: Spielername + gewählter Titel
  („Praktikant", „Filialleiter", „Monopolist" — Titel sind Meta-Progression).
- **Taunts:** Vom Handy auslösbare Kurz-Animationen+Sounds, die der eigene
  Avatar am Bildschirm abspielt (z. B. Geldschein-Fächer wedeln, demonstratives
  Gähnen, Münze Richtung Führenden schnippen). **Anti-Spam hart einbauen:**
  3 Taunts pro Spieler pro Match, 30 s Abklingzeit, gesperrt während Frage
  läuft (nur in Auflösungs-/Zwischenphasen), Host kann Taunts lobbyweit
  stummschalten. Taunt-SETS (thematisch je 3 Stück) als Shop-Items.

---

## Teil D — Charakter-Präsenz im Match (Ideen 19–23)

### Idee 19 — Podium-Bühne: Idle-Leben & Live-Reaktionen auf richtig/falsch — Aufwand M · Prio MUST
- **Aufbau:** Alle Spieler-Affen stehen an Quiz-Show-Pulten am unteren/seitl.
  Bildschirmrand — IMMER sichtbar, nie in ein Menü weggeklappt. Die Affen SIND
  die Spieler-Repräsentation, nicht nur eine Punkteliste.
- **Idle-Schicht (damit nie Standbild herrscht):** Basis-Loop atmen/blinzeln +
  zufällig eingestreute Mikro-Gags mit injiziertem RNG: Schwanz wippt, Ohr
  kratzen, Geldschein aus der Tasche ziehen, kurz zählen, zurückstecken; Kiki
  balanciert auf einem Bein, Fiona flippt ihre Münze. Frequenz niedrig halten
  (alle 6–12 s ein Mikro-Gag), damit es lebendig, nicht zappelig wirkt.
- **Auflösungs-Moment (der Kern-Payoff):** Bei „richtig" feuert die
  Jubel-Reaktion + Münz-Fontäne aus dem Pult + Kontostand-Zähler rattert hoch.
  Bei „falsch" die Frust-Reaktion + ein kleiner Geldschein flattert aus dem
  Pult davon (Geld „entwischt"). Reaktionen sind pro Charakter die
  Signature-Clips (Ideen 1–12), also fühlt sich dieselbe Spielmechanik pro
  Affe anders an.
- **Staffelung:** Auflösungen der Spieler 150 ms versetzt abspielen
  (Links→Rechts oder Letzter→Führender), damit das Auge jede Reaktion einzeln
  mitbekommt — der „Reaktions-Schwenk" wird zum wiederkehrenden Show-Beat.

### Idee 20 — Sozialer Blick: Affen schauen zum Führenden (und reagieren aufeinander) — Aufwand S · Prio SHOULD
- Nach jeder Punktevergabe drehen alle Affen kurz den Kopf zum aktuellen
  Führenden (Kopf-Bone-Rotation, ein Tween — im Cutout-Rig fast gratis).
  Der Führende reagiert je nach Charakter: Gina sonnt sich, Klaus ist es
  sichtbar unangenehm, Don nickt gönnerhaft.
- **Mini-Rivalitäten:** Wechselt Platz 1, schnippt der Entthronte eine Münze
  Richtung neuen Führenden (kleine Bogen-Animation) oder zieht eine Grimasse.
  Bei Gleichstand starren sich die beiden im Duell-Splitscreen an
  (Western-Zoom auf die Augen).
- Alles rein kosmetisch und aus dem Spielzustand ableitbar — keine neue
  Netzwerk-Logik, nur Präsentations-Trigger.

### Idee 21 — Einschlaf-Gag & AFK-Comedy statt AFK-Scham — Aufwand S · Prio SHOULD
- Antwortet ein Spieler 2 Fragen in Folge nicht (oder Verbindung weg), nickt
  sein Affe ein: Zzz-Sprechblase aus Geldscheinen, Schnarch-Sound leise im Mix,
  Zipfelmütze fadet ein. Die NACHBAR-Affen reagieren: schauen rüber, einer
  wirft eine Erdnuss, Kiki hält ihm einen Filzstift an die Stirn.
- **Aufwachen ist der Payoff:** Kommt wieder Input vom Handy, schreckt der
  Affe hoch, Mütze fliegt weg, er tut betont beschäftigt (Papiere sortieren).
  Auf dem HANDY des AFK-Spielers erscheint groß „DEIN AFFE IST EINGESCHLAFEN —
  tippen zum Wecken" — reaktiviert Abgelenkte charmant statt strafend.
- Timeout-Logik über injizierte Clock, damit der Gag deterministisch testbar
  ist (AGENTS.md-Regel).

### Idee 22 — Money-Regen, Streak-Effekte & Verlierer-Cam — Aufwand M · Prio MUST (Money-Regen) / SHOULD (Rest)
- **Money-Regen (MUST):** Der Rundensieger bekommt einen lokal begrenzten
  Geldschein-und-Münzen-Schauer NUR über seinem Podium (ein `GPUParticles2D`-
  Emitter, ~150–250 gepoolte Münzen, Münzen bleiben 2 s liegen und versickern
  dann im Pult). Beim Endsieg: ganzer Bildschirm, Sieger-Affe watet knietief
  in Münzen zur Sieg-Pose (Idee 17).
- **Streak-Effekte (SHOULD):** Ab 3 richtigen in Folge beginnt das Fell des
  Affen güldern zu schimmern (Shader-Parameter, kein neues Asset), ab 5 trägt
  er kurzzeitig eine brennende Geldschein-Aura; ein Fehler löscht alles mit
  einem „Pfffft"-Dampfwölkchen — Verlust sichtbar machen, ohne zu bestrafen.
- **Verlierer-Cam (SHOULD):** Vor der Finalrunde ein 2-Sekunden-Dramazoom auf
  den Letztplatzierten mit Seifenoper-Streicher — sein Affe spielt eine
  „Jetzt-erst-recht"-Pose (Ärmel hochkrempeln). Macht den letzten Platz zur
  Comeback-Story statt zur Demütigung.

### Idee 23 — Handy-Seite: Mini-Avatar mit Vor-Auflösungs-Nervosität — Aufwand M · Prio MUST
- **Kernidee:** Oben auf dem Controller-Screen sitzt eine kleine 2D-Version
  des eigenen Affen (geschichtete SVG + CSS-Animationen, s. Idee 13), die auf
  DEINE Eingaben reagiert, BEVOR die Auflösung am Bildschirm läuft: beim
  Eintippen schaut er neugierig auf „deine" Antwort; beim Absenden stempelt er
  sie ab (Lock-in-Stempel + kurzes Handy-Vibrieren); in der Wartezeit bis zur
  Auflösung kaut er nervös an einer Banane / trommelt mit den Fingern —
  je knapper der Timer, desto hektischer (Timer-Restzeit steuert die
  Animationsstufe).
- **Kein Spoiler:** Der Mini-Avatar kennt die Korrektheit NICHT vorab — seine
  Reaktion spiegelt nur „abgeschickt/nicht abgeschickt" und Zeitdruck. Die
  echte richtig/falsch-Emotion gehört exklusiv dem gemeinsamen Bildschirm
  (gemeinsames Aufschauen = Party-Moment). Nach der Auflösung synct der
  Mini-Avatar auf Mini-Jubel/Mini-Seufzer.
- **Nebenwirkung:** Der Blick pendelt natürlich zwischen Handy und Bildschirm —
  genau die Jackbox-Dynamik, die die App will.

---

## Teil E — AI-Spieler-Persönlichkeiten (Idee 24)

### Idee 24 — Bot-Roster: 5 Persönlichkeiten mit Skill-Profil, Antwortverhalten & Sprüchen — Aufwand L · Prio SHOULD
Bots füllen kleine Lobbys (2 Menschen + 2 Bots fühlt sich nach Show an) und
sind Trainingsgegner. Technisch: Antwortzeit als Verteilung (injizierter RNG),
Fehlermodell wählt PLAUSIBLE falsche Antworten (Distraktoren aus der Frage),
nie uniform zufällig — das wirkt sonst sofort künstlich. Alle Bots nutzen das
normale Avatar-System (eigene exklusive Skins, damit man Bots sofort erkennt
und die Skins gleichzeitig Sammler-Reiz haben, falls später freischaltbar).

1. **„Al Gorithmus"** — Blechroboter-Affe mit Antennen-Schädel (Silhouette:
   eckiger Kopf). *Skill:* 85 % Trefferquote bei Fakten, nur 40 % bei
   Popkultur/Schätzfragen; Antwortzeit konstant-mechanisch (immer ~2,5 s —
   verdächtig gleichmäßig, das IST der Witz). *Verhalten:* lockt nie zu früh,
   ändert Antworten nie. *Sprüche:* „Berechne… Banane.", „Fehler gefunden:
   bei dir.", „Meine Trefferquote ist dokumentiert."
2. **„Praktikant Pit"** — junger Affe mit viel zu großem Hemd und
   Kaffeebecher-Stapel. *Skill:* 35 % Trefferquote, buzzert aber IMMER als
   Erster (0,5–1 s). *Verhalten:* wechselt seine Antwort in letzter Sekunde
   mit 30 % Wahrscheinlichkeit (meist von richtig auf falsch). *Sprüche:*
   „Ich hab das mal gegoogelt!", „Das kam in meinem Praktikum dran!",
   „Zählt der Versuch trotzdem?"
3. **„Tante Trude"** — Bot-Version im Oma-Zinseszins-Stil (eigene Häkelweste).
   *Skill:* 70 % bei Alltag/Essen/Geschichte, 20 % bei Technik; langsame
   Antworten (6–9 s), verpasst gelegentlich den Timer komplett (5 %).
   *Verhalten:* in Schätzfragen unheimlich präzise (der Running Gag).
   *Sprüche:* „Zu meiner Zeit war das noch eine D-Mark.", „Ich schreib's mir
   auf einen Zettel.", „Junge, schrei nicht so."
4. **„Zocker-Zeno"** — Affe mit Würfel-Kette und nervösem Blick. *Skill:*
   solide 60 %, aber in Einsatz-/Wettrunden setzt er IMMER alles. *Verhalten:*
   nutzt Taunts maximal aus (im Rahmen der Anti-Spam-Regeln), schnippt nach
   jeder Runde eine Münze Richtung Führendem. *Sprüche:* „Alles auf Rot.
   Also auf Banane.", „Risiko ist nur ein Wort für Spaß mit Folgen.",
   „Doppelt oder Matsche."
5. **„Fräulein Fastrichtig"** — adrette Äffin mit Klemmbrett, ewige Zweite.
   *Skill:* 55 %, wählt bei Fehlern IMMER den plausibelsten Distraktor
   (knapp daneben — Menschen fühlen sich ertappt, weil sie dieselbe Falle
   kennen). *Verhalten:* Rubber-Banding-Bot: spielt etwas stärker, wenn sie
   hinten liegt, etwas schwächer, wenn sie führt — hält Partien spannend,
   Stärke-Delta klein halten (±10 %), damit es nie unfair wirkt. *Sprüche:*
   „Ich war SO nah dran.", „Das hätte ich fast gewusst — zählt fast?",
   „Nächste Runde gehört mir. Diesmal wirklich."

**Schwierigkeitsgrade:** Host wählt pro Bot leicht/mittel/schwer → skaliert
nur Trefferquote und Antwortzeit, NIE das Persönlichkeitsverhalten (Pit bleibt
auch auf „schwer" der Erste am Buzzer). Alle Wahrscheinlichkeiten und Timings
aus injiziertem RNG/Clock, damit Bot-Verhalten in Tests deterministisch
reproduzierbar ist.

---

## Priorisierungs-Überblick

| # | Idee | Aufwand | Prio |
|---|------|---------|------|
| 1 | Don Bananas (Pate) | M | MUST |
| 2 | Gitti Giro (Buchhalterin) | M | MUST |
| 3 | Kiki Krawall (Chaos-Äffchen) | M | MUST |
| 4 | Baron von Bananenstein (Adeliger) | M | MUST |
| 5 | Rico Rendite (Krypto-Bro) | M | SHOULD |
| 6 | Oma Zinseszins (Unterschätzte) | M | SHOULD |
| 7 | Pumper-Paule (Gym-Gorilla) | M | SHOULD |
| 8 | Schnarch-Schorsch (Tiefenentspannter) | M | SHOULD |
| 9 | Glitzer-Gina (Diva) | M | SHOULD |
| 10 | Professor Pavian (Besserwisser) | M | SHOULD |
| 11 | Klaus Kleingeld (Underdog) | M | COULD |
| 12 | Fiona Fifty-Fifty (Zockerin) | M | COULD |
| 13 | Machart v1: 2D-Pappfiguren-Pipeline | L | MUST |
| 14 | Machart-Upgrade: Low-Poly-3D | L | COULD |
| 15 | Customization-Basis (Farben/Muster/Hut) | M | MUST |
| 16 | Shop-Ökonomie mit Raritäten | M | SHOULD |
| 17 | Sieg-Posen & Buzzer-Sounds wählbar | M | SHOULD |
| 18 | Namensschilder & Taunts | S–M | SHOULD/COULD |
| 19 | Podium: Idle & Live-Reaktionen | M | MUST |
| 20 | Blick zum Führenden / Rivalitäten | S | SHOULD |
| 21 | Einschlaf-Gag & AFK-Comedy | S | SHOULD |
| 22 | Money-Regen, Streaks, Verlierer-Cam | M | MUST/SHOULD |
| 23 | Handy-Mini-Avatar (Vor-Auflösung) | M | MUST |
| 24 | Bot-Roster (5 Persönlichkeiten) | L | SHOULD |

**Empfohlene v1-Schnittmenge:** Ideen 1–4, 13, 15, 19, 22 (Money-Regen), 23 —
damit steht das komplette Charakter-Gefühl der Show; alles Weitere ist
Shop-/Update-Futter, das die All-time-Money-Ökonomie langfristig trägt.
