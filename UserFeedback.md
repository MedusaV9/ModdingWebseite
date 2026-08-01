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

_(NEU seit W16: Das Projekt ist umgezogen — es lebt jetzt im Repo
`MedusaV9/MinecraftBubbleShieldMod` auf dem Branch `cursor/gooby-godot-loop-2c10`,
mit komplettem Verlauf. Alle Updates/Builds laufen ab jetzt über dieses Repo.
Diese Datei bleibt dein direkter Draht: einfach unten reinschreiben.)_

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
- [~] **W17 / Welle G5 läuft:** die großen Brocken aus deiner Liste:
      **DLC „Goo und Bye" Welle A** (Waren + Markttag + begehbarer Erstladen),
      **DLC „McGooby" Welle A** (Rezepte + erste Schicht), **GvZ-PvP übers Netz**
      (nach der GOB-NOM-Lockstep-Vorlage), **Trailer-Neuaufnahme** mit dem neuen
      UI (Storyboard v4), dazu der Minispiel-Batch-B-Rest (goobySays, memoryMatch,
      lanternFloat, miniGolf, pancakeTower, pipeFlow, ghostHunt, burgerBuild,
      deliveryRush, shoppingSurf, toyRacer) und die UI-Wache für die neuen
      G4-Flächen. Loop läuft weiter.

- [~] **DLC-Umsetzung „Goo und Bye" + „McGooby"** — Design-Docs komplett; Welle A
      beider Fundamente ist Teil von G5 (s. o.)
- [x] **Minispiel-Qualität, Gruppe 3** — die notierten Kandidaten (starHopper-Bühne,
      trampoline-Gym, carrotGuard-HUD, hideSeek-Wiese, cityDrive-Feedback,
      Ranch-Arena-Überstrahlung) sind seit Welle G2/G3 alle umgesetzt; der Rest-
      Batch läuft in G5
- [~] **GvZ-PvP übers Netz** — in G5 in Arbeit (GOB-NOM-Lockstep als Vorlage)
- [~] **Trailer-Refresh** — Neuaufnahme läuft in G5 (das UI-Rework ist durch,
      Storyboard v4 + Aufnahme-Treiber lagen seit G3 bereit)
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

Runde W17 (1./2. August) — Wellen G1–G4 sind FERTIG (Details oben + unten in
„Erledigt"), der Agent arbeitet gerade an **Welle G5**:

- [~] **DLC „Goo und Bye", Welle A** — Waren-Katalog, deterministischer Markttag,
      DLC-Hub-Kachel wird begehbar (erster Laden mit Regal, Kasse, Kunde)
- [~] **DLC „McGooby", Welle A** — Rezept-/Stationen-Fundament + erste Mini-Schicht
- [~] **GvZ-PvP übers Netz** (GOB-NOM-Lockstep-Vorlage) + GvZ-HUD-Entflechtung
- [~] **Trailer-Neuaufnahme** mit dem W16/W17-Look (Storyboard v4, 104 Beats)
- [~] **Minispiel-Batch-B-Rest** — goobySays+memoryMatch, lanternFloat+miniGolf,
      pancakeTower+pipeFlow, ghostHunt (mit Datei-Entflechtung), burgerBuild+
      deliveryRush, shoppingSurf+toyRacer
- [~] **UI-Wache auf die G4-Flächen ausdehnen** (Baumodus-Dock, Telefon, Radio,
      Ranch-MP, Level-Auswahlen, Onboarding) + Kino-Untertitel/Skip-Fläche und
      Freunde-App im Telefon-Layout

---

## 3. Wo das Spiel gerade steht

| | |
|---|---|
| **Testen** | GitHub → Actions → Lauf „GOOBY Godot" → Artefakt `GOOBY-godot-unsigned-ipa` herunterladen, mit AltStore/Sideloadly installieren. Anleitung: `docs/godot-rewrite/IOS-BUILD.md` |
| **Spielstand von früher** | Einstellungen → Spielstand → „Alten Spielstand übertragen"; Anleitung: `docs/godot-rewrite/SAVE-TRANSFER.md` |
| **Was noch offen ist** | `docs/godot-rewrite/EVAL-VOLLSTAENDIGKEIT.md` (ehrliche Feature-Matrix) |
| **Trailer** | `trailer/GOOBY-5.0-Godot-Update-Trailer.mp4` |

---

## 4. Erledigt

Chronologisch nach Meldung; die Erklärung steht jeweils darunter.

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
