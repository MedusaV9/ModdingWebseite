# MONKEY MONEY — Ideen-Agent 11/20: Cutscenes, Intros, Übergänge & Video-Produktion

Kontext: Jackbox/Buzz-artige Quiz-Show-Party-App. Der Bildschirm ist ein
Browser (TV/Beamer), Spieler steuern per Handy. Thema: Money + Affen. Harte
Vorgaben: **alle Cutscenes SKIPPABLE**, der User will **Remotion** für Videos
(Trailer/Erklärungen) und **echte Cutscenes im Spiel**; Blender-Modelle werden
selbst gebaut.

Legende: Aufwand S/M/L · Prio MUST/SHOULD/COULD.

**Skip-Modelle (werden unten je Cutscene referenziert):**
- **GM-Skip:** Nur der Game-Master (Host-Handy) hat den Skip-Button.
- **Mehrheits-Skip:** Auf jedem Handy erscheint „Skip?" — bei >50 % Ja wird
  übersprungen; Screen zeigt live „3/5 wollen skippen".
- **Jeder-sofort-Skip:** Ein einziger Spieler genügt (nur für rein dekorative
  Einspieler ohne Info-Gehalt).
- **Kein-Skip-Fenster:** Die ersten ~1,5 s laufen immer (Stinger-Sound +
  Branding), danach greift das jeweilige Skip-Modell — verhindert, dass die
  Show „zerhackt" wirkt, kostet aber praktisch keine Zeit.

---

## A. CUTSCENE-MOMENTE im Match (Ideen 1–10)

### Idee 1 — Show-Opening: Logo-Stinger + Studio-Kamerafahrt `[L · MUST]`
**Ablauf in 5 Beats:**
1. Schwarz → goldener Lichtpunkt, Münz-Klimpern (0–1,5 s).
2. 3D-Logo „MONKEY MONEY" dreht sich ein, Münzen prallen von den Lettern ab,
   Blitz-Flash (1,5–4 s) — das ist der wiederverwendbare **Logo-Stinger**.
3. Kamerafahrt durchs Studio: über die Zuschauerränge (Affen-Publikum winkt),
   an den Neon-Bananen vorbei, auf die Bühne zu (4–9 s).
4. Spotlights schwenken auf die leeren Kandidatenpulte, Konfetti-Kanone
   feuert einmal (9–12 s).
5. Titel-Karte „HEUTE SPIELEN:" als Übergabe an die Kandidaten-Vorstellung
   (Idee 2) (12–14 s).
**Dauer:** 12–14 s. **Skip:** Kein-Skip-Fenster (1,5 s), danach GM-Skip —
das Opening ist Teil des Rituals, einzelne Ungeduldige sollen es nicht für
alle killen.
**Technik:** Beats 1–2 vorgerendert (Blender-Logo → WebM), Beats 3–5 in
Echtzeit (damit später Saison-Deko/Spielerzahl variieren kann) — siehe Idee 14.

### Idee 2 — Kandidaten-Vorstellung mit Avataren + Namen `[M · MUST]`
Der wichtigste Echtzeit-Pflichtfall: Namen und Avatare sind erst zur Laufzeit
bekannt → **niemals vorrendern**.
**Ablauf in 4 Beats (pro Spieler ~2,5 s, sequenziell):**
1. Spotlight knallt auf ein leeres Pult, Drumroll.
2. Avatar (gewählter Affe mit Accessoire) rutscht/fällt/stolpert herein —
   Einlauf-Animation zufällig aus 5–6 Varianten (Liane, Bananenschale,
   Geldkoffer-Fallschirm, Moonwalk, Kanone, Aufzug).
3. Namens-Banner in Show-Typo klappt auf, dazu ein automatisch generierter
   Show-Titel („Der Herausforderer aus dem Dschungel", „Titelverteidigerin");
   bei Rückkehrern: Bilanz-Zeile („2 Siege, 34.000 🍌").
4. Kurzer Jubel-Sound des Affen-Publikums, Kamera schwenkt zum nächsten Pult.
**Dauer:** 2,5 s × Spielerzahl + 2 s Gruppen-Totale am Ende (bei 8 Spielern
~22 s → ab 6 Spielern Beats parallelisieren: je 2 Spieler gleichzeitig).
**Skip:** Mehrheits-Skip; zusätzlich darf **jeder Spieler seine EIGENE
Vorstellung** per Buzzer „abkürzen" (Gag: der Vorhang fällt ihm auf den Kopf).

### Idee 3 — Runden-Ankündigungs-Karte je Minispiel-Format `[M · MUST]`
Ein **einheitliches Echtzeit-Template**, pro Minispiel nur Daten (Name, Icon,
Farbe, 3 Regel-Zeilen, Maskottchen-Pose) — so kostet jedes neue Minispiel nur
Content, keinen Code.
**Ablauf in 4 Beats:**
1. Übergang (Abschnitt E) wischt das alte Bild weg; Format-Logo + Name
   stempeln sich ein, Format-Jingle (1,5 s).
2. Regel-Erklärung charmant in max. 3 Zeilen, die nacheinander einfliegen,
   dazu eine Mini-Demo-Animation in Dauerschleife (z. B. Handy-Mockup zeigt,
   was gedrückt wird) (6–8 s).
3. Einsatz-Anzeige: „Pro richtiger Antwort: 500 🍌" + Besonderheit der Runde
   („Letzter Platz zahlt doppelt!") (2–3 s).
4. „BEREIT?"-Prompt: alle Handys zeigen einen Bereit-Button; Countdown 3-2-1
   sobald alle (oder Timeout 10 s) (variabel).
**Dauer:** 10–15 s + Bereit-Phase. **Skip:** Beim ERSTEN Auftreten eines
Formats Mehrheits-Skip; ab dem zweiten Mal Jeder-sofort-Skip UND automatische
Kurzfassung (nur Beat 1+4, ~4 s) — Wiederholungen nerven sonst am meisten.

### Idee 4 — Halbzeit-Zwischenstand: „Die Börsen-News" `[M · SHOULD]`
Inszeniert als Nachrichten-Einspieler: ein Affen-Anchor am News-Desk
(„MMN — Monkey Money News").
**Ablauf in 5 Beats:**
1. News-Intro-Stinger, Globus mit Bananen-Kontinenten (2 s).
2. Anchor-Affe verliest den Spitzenreiter, Kurs-Chart mit dessen
   Punkteverlauf zoomt ins Bild (4 s).
3. „Aufsteiger des Tages": Spieler mit größtem Rundengewinn, grüner Pfeil,
   Börsenglocke (3 s).
4. „Krisen-Ticker" unten im Bild läuft mit Spott-Schlagzeilen über den
   Letzten (auto-generiert aus Templates, liebevoll statt fies) (parallel).
5. Anchor kündigt die zweite Hälfte an: „Nach der Werbung: Es geht um ALLES!"
   → Fake-Werbeübergang (Idee 24) (3 s).
**Dauer:** 12–15 s. **Skip:** Mehrheits-Skip nach Beat 2 (der Zwischenstand
selbst — Beat 2 — ist die Information, die alle sehen wollen).

### Idee 5 — Finale-Einlauf: „Nur noch N können gewinnen" `[M · SHOULD]`
**Ablauf in 5 Beats:**
1. Licht im Studio fällt aus, nur Notbeleuchtung, Herzschlag-Sound (2 s).
2. Ein Tresor fährt aus dem Bühnenboden, darauf der Jackpot-Betrag in
   glühenden Ziffern (3 s).
3. Die Finalisten-Avatare werden einzeln von Spotlights „gefunden" —
   absteigend nach Punkten, mit Punkte-Einblendung (1,5 s pro Finalist).
4. Ausgeschiedene Avatare winken aus dem „Zuschauerraum" (sie bleiben als
   Publikum/Wett-Teilnehmer im Spiel — Anschluss an Zuschauer-Wetten) (2 s).
5. Titel-Karte „DAS FINALE" mit Flammen/Gold-Partikeln, Finale-Jingle (2 s).
**Dauer:** 10–14 s. **Skip:** GM-Skip only — der dramatischste Moment der
Show, hier soll die Spannung stehen bleiben.

### Idee 6 — Siegerehrung: Podest + Money-Regen + Konfetti `[M · MUST]`
**Ablauf in 5 Beats:**
1. Trommelwirbel, drei Podeste fahren hoch, noch leer; Platz 3 wird
   eingeblendet und der Avatar hüpft aufs Podest (3 s).
2. Platz 2 ebenso, mit kurzem „so knapp!"-Kommentar wenn Abstand < 10 % (3 s).
3. Spannungspause — zwei Spotlights kreisen, Herzschlag … dann knallt der
   Sieger-Avatar per Konfetti-Kanone aufs oberste Podest (4 s).
4. **Money-Regen:** Scheine + Münzen + Bananen regnen als Partikelsystem,
   der Sieger macht Jubel-Loop, Krone landet (physikbasiert, darf schief
   sitzen — Gag) auf seinem Kopf (4 s).
5. End-Tafel: finale Punkte aller Spieler, Foto-Blitzlichter, „Nochmal
   spielen?"-Prompt; Screen bleibt als „Sieger-Poster" stehen (Foto-Moment
   für die Runde!) (bis Interaktion).
**Dauer:** 14–18 s + stehendes End-Bild. **Skip:** Mehrheits-Skip, aber erst
nach Beat 3 (der Sieger hat sich den Moment verdient); der SIEGER bekommt
exklusiv einen „Zugabe!"-Button, der den Money-Regen einmal wiederholt.

### Idee 7 — Bestrafungs-Inszenierung: „Der Bananen-Pranger" `[M · SHOULD]`
Für Verlierer-Strafen (letzter Platz, verlorene Wette, Minispiel-Pleite).
**Ablauf in 4 Beats:**
1. Düster-komischer Posaunen-Sound („wah-wah"), Licht wird rötlich, der
   Avatar des Bestraften wird von einer Riesen-Affenhand (Idee 23) auf ein
   Podest in der Bühnenmitte gestellt (3 s).
2. Ein Glücksrad-ähnliches „Straf-Rad" (oder GM wählt) zeigt die Strafe:
   virtuelle (Punktabzug, alberner Hut auf dem Avatar für die nächste Runde,
   Buzzer-Sound wird auf Quietsche-Ente getauscht) oder Real-Life-Karte
   („Erzähl einen Flachwitz") (4 s).
3. Vollstreckung als Mini-Animation: Bananenschauer, Torten-Wurf, Publikum
   johlt; bei Real-Life-Strafe: Countdown-Timer + „Erledigt"-Bestätigung
   durch den GM (3 s bzw. variabel).
4. Versöhnungs-Beat: Publikum applaudiert dem Bestraften, kleiner
   Trost-Betrag (+50 🍌) — die Show bleibt gutmütig (2 s).
**Dauer:** 10–12 s + ggf. Real-Life-Phase. **Skip:** Der BESTRAFTE darf nicht
skippen (Teil des Spaßes), alle anderen per Mehrheits-Skip — bewusst
invertierte Machtverhältnisse als Meta-Gag.

### Idee 8 — Glücksrad-Einspieler: „Das Rad des Reichtums" `[M · SHOULD]`
**Ablauf in 5 Beats:**
1. Fanfare, das Riesen-Rad fährt von oben herab (Segmente: Geldbeträge,
   „Bankrott"-Affe, Doppelt-oder-Nichts, Mystery-Banane) (2,5 s).
2. Kamera-Zoom auf den drehberechtigten Spieler-Avatar, sein Handy wird zum
   Dreh-Controller (Wisch-Geste = Schwung!) (2 s).
3. Dreh in Echtzeit — Tick-Tick-Tick der Rad-Zunge, physikbasiertes
   Auslaufen, bei langsamer werdendem Rad zoomt die Kamera ran (3–6 s,
   spielergesteuert).
4. Ergebnis-Knall: Segment leuchtet, Betrag fliegt als Münzstrahl zum
   Kontostand des Spielers (oder Bankrott-Affe klaut den Koffer) (2 s).
5. Kurze Reaktions-Einblendung: die anderen Avatare jubeln/lachen (1,5 s).
**Dauer:** 10–14 s. **Skip:** Nur Beats 1+5 skippbar (Jeder-sofort-Skip);
Beat 3 ist Gameplay, kein Video — Interaktion schlägt Cutscene.

### Idee 9 — Comeback-/Momentum-Einspieler: „Die Aufholjagd" `[S · COULD]`
Trigger-basierte Kürzest-Cutscene (max. 4 s), wenn ein Spieler ≥2 Plätze in
einer Runde gutmacht oder der Letzte eine Runde gewinnt.
**Ablauf in 3 Beats:** 1. Rekord-Kratzer-Sound, Zeit friert ein (0,5 s).
2. Avatar des Aufholers rast auf einer Rakete/Liane an den überholten
   Avataren vorbei, deren Gesichter im Comic-Schock (2 s).
3. „+3 PLÄTZE!"-Stempel, weiter im Flow (1 s).
**Dauer:** 3,5–4 s. **Skip:** Kein Skip nötig — unter der
Wahrnehmungsschwelle für Ungeduld; global im GM-Menü abschaltbar
(„Einspieler: viele/wenige/aus").

### Idee 10 — Ereignis-Karten: „Breaking News im Studio" `[S · COULD]`
Zufalls-Events zwischen Fragen (Doppelte Punkte, Bananen-Bonus für alle,
Kurssturz: alle verlieren 10 %, Diebischer Affe klaut dem Führenden 500).
**Ablauf in 3 Beats:** 1. Alarm-Rotlicht + „BREAKING"-Banner quer über den
Screen (1 s). 2. Event-Karte klappt auf: Icon + 1 Zeile Text + betroffene
Avatare reagieren (2,5 s). 3. Effekt wird sichtbar verbucht
(Kontostands-Animation), Banner fliegt raus (1,5 s).
**Dauer:** 5 s. **Skip:** Jeder-sofort-Skip (Info steht danach trotzdem als
Icon in der Ecke).

---

## B. PRODUKTIONS-TECHNIK: Echtzeit vs. Remotion vs. Blender (Ideen 11–15)

### Idee 11 — Drei-Schichten-Regel als Architektur-Prinzip `[S · MUST]`
Eine einzige Entscheidungsregel für JEDES visuelle Element:
- **Schicht 1 — Echtzeit (DOM/Canvas/CSS im Browser):** alles mit
  **Laufzeit-Daten** (Namen, Avatare, Punktestände, Spielerzahl, Beträge)
  und alles **Interaktive** (Glücksrad-Dreh, Bereit-Buttons). Begründung:
  vorgerenderte Videos können keine dynamischen Namen zeigen; genau daran
  scheitern Video-only-Ansätze bei Party-Spielen.
- **Schicht 2 — Remotion (vorgerendert, aber CODE-generiert):** alles, was
  **außerhalb des Spiels** lebt oder **viele Varianten aus einem Template**
  braucht: Trailer, Tutorial-Videos, Social-Clips, evtl. App-Store-Material.
  Begründung: Remotion = React-Komponenten → dieselben UI-Bausteine
  (Logos, Karten, Typo) können zwischen Spiel (live) und Video (gerendert)
  geteilt werden; Batch-Rendern vieler Varianten per Props ist der
  Kern-Vorteil gegenüber Schnittsoftware.
- **Schicht 3 — Blender (vorgerendert, 3D):** alles, was im Browser-Echtzeit
  zu teuer/zu hässlich wäre: Logo-3D-Stinger, cineastische Kamerafahrt,
  Charakter-Drehungen mit echtem Licht. Export als WebM (VP9 mit Alpha)
  oder Sprite-Sequenz → wird von Schicht 1 als Baustein abgespielt und
  kann von Schicht 2 (Remotion `<Video>`/`<OffthreadVideo>`) im Trailer
  wiederverwendet werden.
Faustregel als Satz fürs Team: **„Steht ein Spielername drauf → Echtzeit;
ist es Marketing/Erklärung → Remotion; braucht es echtes 3D-Licht →
Blender-Clip als Zutat für beide."**

### Idee 12 — Blender→Web-Pipeline: Charakter-Drehungen & Posen-Bibliothek `[L · SHOULD]`
Die selbstgebauten Blender-Affen werden EINMAL als wiederverwendbare
Web-Assets exportiert statt pro Cutscene neu gerendert:
- **Turntable-Renders** (360°-Drehung, 36 Frames) pro Affe/Accessoire →
  Sprite-Sheets für die Avatar-Auswahl auf dem Handy und die
  Kandidaten-Vorstellung (Idee 2) — sieht 3D aus, kostet im Browser nichts.
- **Posen-/Emote-Clips** (Jubel, Heulen, Schulterzucken, Tanzen, Schock —
  je 1–2 s, geloopt) als WebM-mit-Alpha → die Echtzeit-Schicht legt sie
  über beliebige Hintergründe; dieselben Clips füttern Remotion-Videos.
- Namenskonvention + Render-Skript (`blender --background --python …`) im
  Repo, damit neue Affen automatisch durch die Pipeline laufen (passt zur
  bestehenden `tools/blender/`-Denke des Projekts).
Alternative Alpha-Route falls WebM-Alpha auf Safari zickt: gestapelte
PNG-Sequenz bzw. HEVC-mit-Alpha als Fallback prüfen.

### Idee 13 — Logo-3D-Stinger als Universal-Asset `[M · MUST]`
EIN hochwertiger Blender-Render (3–4 s: Logo dreht ein, Münzen kollidieren
physikalisch, Gold-Shader, Lichtblitz) wird zum meistgenutzten Asset der
Marke: Show-Opening Beat 1–2 (Idee 1), Trailer-Shot 1 und 10 (Idee 16),
Tutorial-Outro (Idee 17), Lade-/Reconnect-Screen, Social-Clips. In drei
Varianten rendern: mit Alpha (zum Überlagern), auf Studio-Hintergrund, und
als 1-s-Kurzfassung („Logo-Bumper") für Übergänge. Genau hier lohnt sich
Blender-Qualität, weil das Asset hundertfach wiederverwendet wird.

### Idee 14 — Hybrid-Cutscenes: Video-Layer + Echtzeit-Overlay `[M · SHOULD]`
Muster für „cineastisch UND personalisiert": Ein vorgerenderter Clip
(Blender-Kamerafahrt) läuft als `<video>`-Hintergrund, die Echtzeit-Schicht
zeichnet synchronisiert Namen, Avatare und Beträge darüber (Zeitmarken im
JSON: „bei t=4,2 s Pult 1 einblenden"). So bekommt das Show-Opening (Idee 1)
Kino-Look, bleibt aber pro Lobby personalisiert. Wichtigste Regel:
Overlay-Positionen im Video „reserviert" gestalten (leere Pulte, leere
Banner), damit Overlays nie mit gerendertem Inhalt kollidieren. Skip bricht
Video UND Overlay-Timeline gemeinsam ab (eine gemeinsame Clock, kein
Auseinanderlaufen).

### Idee 15 — Remotion als Build-Zeit-Werkzeug, nie zur Laufzeit `[S · MUST]`
Klare Abgrenzung: Remotion rendert Videos **im Build/CI**, nicht im
laufenden Spiel (der `@remotion/player` könnte zwar live im Browser abspielen,
aber dann wäre es faktisch Echtzeit-React — dafür haben wir Schicht 1 schon).
Konsequenzen: (a) Ein `videos/`-Workspace mit Remotion-Projekt, das
Trailer + alle Tutorials per `npx remotion render` in CI baut und als
Artefakte ablegt; (b) geteiltes Paket `show-ui` mit Logo-, Karten- und
Typo-Komponenten, das SOWOHL die Spiel-Frontend-App ALS AUCH die
Remotion-Kompositionen importieren — Corporate Design an einer Stelle;
(c) Tutorial-Neurendering bei Regeländerung = Props-Änderung + CI-Lauf,
kein Schnittprogramm.

---

## C. DER TRAILER (60–90 s, Remotion) (Idee 16)

### Idee 16 — Trailer-Storyboard in 10 Shots `[L · SHOULD]`
Ziel: 75 s, 16:9 (+ 9:16-Schnittfassung aus denselben Kompositionen — in
Remotion nur eine zweite Composition mit anderem Layout). Musik: treibender
Game-Show-Funk, Schnitte auf den Beat.

| # | Zeit | Shot | Inhalt |
|---|------|------|--------|
| 1 | 0–4 s | **Logo-Stinger** | Blender-Logo-Render (Idee 13), Münz-Knall — Marke zuerst. |
| 2 | 4–10 s | **Problem-Hook** | Realfilm-artig gestellt (oder illustriert): gelangweilte Runde auf dem Sofa, Zapping … Text-Card: „Spieleabend eingeschlafen?" |
| 3 | 10–18 s | **Die Verwandlung** | Fernseher schaltet auf MONKEY-MONEY-Studio, Wohnzimmer wird von Show-Licht geflutet, alle richten sich auf. Kamera-Swoosh (Idee 22) ins Spiel. |
| 4 | 18–26 s | **So funktioniert's** | Split-Screen: TV-Browser oben, 3 Handys unten; Join per Raum-Code in 3 s gezeigt (Screen-Capture in Remotion-Mockup-Rahmen). Text: „Handy = Buzzer. Kein Download." |
| 5 | 26–38 s | **Minispiel-Montage** | 4 schnelle Gameplay-Ausschnitte à 3 s (Buzzer-Duell, Schätzfrage, Glücksrad, Bluff-Runde), jeweils mit Format-Logo-Stempel. Screen-Recordings, in Remotion beschnitten + gestempelt. |
| 6 | 38–46 s | **Emotion-Peak** | Reaktions-Momente: Money-Regen, Comeback-Rakete (Idee 9), Bestrafungs-Torte (Idee 7) — die Show lacht MIT den Verlierern. |
| 7 | 46–56 s | **Das Finale** | Tresor-Shot (Idee 5), Herzschlag, Jackpot-Ziffern glühen; ein Avatar gewinnt, Podest + Konfetti (Idee 6). |
| 8 | 56–64 s | **Feature-Karten** | 3 Karten im Show-Design: „2–8 Spieler" · „Partys, Familien, Büro" · „Jede Woche neue Fragen" (Props-getrieben, leicht aktualisierbar). |
| 9 | 64–70 s | **Social Proof / Ton** | Zitat-Karten mit Publikums-Lachern unterlegt („Der Affe hat meine Punkte GEKLAUT?!" — Lena, Platz 4). |
| 10 | 70–75 s | **Call-to-Action** | Logo-Bumper (Kurzfassung Idee 13) + URL/QR-Code + Claim: „MONKEY MONEY — Wer nicht spielt, zahlt." |
**Remotion-Umsetzung:** Jeder Shot eine eigene `<Composition>`/Sequence;
Gameplay-Shots als `<OffthreadVideo>` aus Screen-Captures; Texte/Claims als
Props (Lokalisierung DE/EN = zweiter Render-Lauf). Aufwand L, aber Shots
5+6 recyceln pures Gameplay-Material — erst bauen, wenn 3–4 Minispiele
vorzeigbar sind.

---

## D. TUTORIAL-VIDEOS (Ideen 17–18)

### Idee 17 — Remotion-Tutorial-Template „HowToCard" mit Props `[M · MUST]`
EIN Remotion-Template, aus dem ALLE Minispiel-Tutorials (15–20 s) gerendert
werden. Props pro Minispiel: `title`, `icon`, `accentColor`, `steps[]`
(max. 3 × {Text, Demo-Clip/Screenshot}), `rewardLine`, `mascotPose`.
**Fester Ablauf im Template:** (1) Format-Logo-Stempel + Jingle (2 s) →
(2) drei Schritte, je 4 s: links Handy-Mockup mit Demo-Clip, rechts
Text-Zeile, Maskottchen-Affe zeigt drauf → (3) Belohnungs-Zeile + Logo-Bumper
(3 s). **Nutzung:** (a) im Spiel als optionales „Regeln nochmal?"-Video aus
der Runden-Karte (Idee 3) heraus, (b) als Social-Snippets, (c) im
Hilfe-Bereich. Neue Minispiele bekommen ihr Tutorial durch eine
Props-Datei + CI-Render — Minuten statt Stunden. Wichtig: Texte kurz halten
und als Props führen (DE/EN-Batch-Render).

### Idee 18 — Attract-Mode: Tutorial-Loop in der Lobby `[S · COULD]`
Während Spieler joinen, läuft auf dem Screen (gedimmt, hinter dem Raum-Code)
eine Endlosschleife aus den Tutorial-Videos (Idee 17) + Trailer-Shots —
wie ein Arcade-Automat im Attract-Mode. Effekt: Neue Mitspieler kennen die
Formate schon, bevor die Show beginnt; die Lobby fühlt sich nie „tot" an.
Ton aus bzw. leise; Raum-Code IMMER unverdeckt. Rein Abspiel-Logik →
Aufwand S, setzt nur Idee 17 voraus.

---

## E. ÜBERGÄNGE zwischen Szenen (Ideen 19–24)

Alle Übergänge in Echtzeit (CSS/Canvas/WebGL), 0,5–1,2 s, NIE skippbar
(kürzer als jede Skip-Interaktion) — aber global im GM-Menü auf „reduziert"
schaltbar (Barrierefreiheit: Motion-Empfindlichkeit, `prefers-reduced-motion`
respektieren).

### Idee 19 — Bananen-Wipe `[S · MUST]`
Eine Staffel Bananen fliegt im Bogen von links unten quer über den Screen
und „schält" dabei das neue Bild auf (Masken-Wipe entlang der Flugbahn).
Dauer 0,8 s, Woosh + Flatsch-Sound. Standard-Übergang zwischen Fragen.
Umsetzung: 2D-Sprites + animierte SVG/Canvas-Maske — bewusst billig.

### Idee 20 — Money-Regen-Wipe `[S · MUST]`
Geldscheine wirbeln von oben herab, verdichten sich für 0,3 s zum
Vollbild-Scheinwirbel, wehen wieder raus — dahinter ist die neue Szene.
Dauer 1,0 s. Reserviert für Geld-Momente (Rundenauszahlung → Zwischenstand,
Glücksrad-Ergebnis), damit der Übergang selbst Bedeutung trägt
(„Übergangs-Vokabular": Bananen = neutral, Geld = Auszahlung, Licht = Akt).

### Idee 21 — Studio-Licht-Blende (Blackout + Spotlights) `[S · SHOULD]`
Alle Studio-Lichter gehen „klack-klack-klack" (3 Relais-Sounds) aus →
0,3 s Schwarz → zwei Spotlights fahren kreisend hoch und „finden" die neue
Szene. Dauer 1,2 s. Für Akt-Wechsel (Halbzeit, Finale) — der theatralischste
Übergang, deshalb sparsam einsetzen. Umsetzung: CSS-Radial-Gradients als
Spot-Masken, kein WebGL nötig.

### Idee 22 — Kamera-Swoosh mit Motion-Blur `[M · SHOULD]`
Die aktuelle Szene wird horizontal „weggerissen" (starker directional Blur +
Skew), 0,15 s Unschärfe-Peak mit Speedlines, neue Szene bremst mit
Overshoot-Bounce ein. Dauer 0,6 s, sattes Swoosh-Sounddesign. Für Wechsel
Pult ↔ Bühne ↔ Rad, gibt der „Studio-Kamera" Physikalität. Umsetzung:
CSS-Filter/Canvas; auf schwachen Geräten automatisch durch harten Schnitt +
Sound ersetzen (Sound trägt 70 % des Effekts).

### Idee 23 — Affen-Hand-Grab `[M · COULD]`
Eine Riesen-Affenhand greift von oben ins Bild, „packt" die alte Szene
(die zerknüllt wie Papier — Canvas-Verzerrung oder vorgerenderte
Knüll-Sequenz) und zieht sie raus; die neue Szene liegt darunter. Dauer
1,0 s. Signature-Übergang mit Wiedererkennung; auch als Bestrafungs-Intro
(Idee 7) wiederverwendet. Die Hand als Blender-Render mit Alpha (Idee 12)
in 2–3 Griff-Varianten.

### Idee 24 — Fake-Werbepause `[S · COULD]`
Vor Halbzeit/Finale: 4-s-Fake-Werbespot im Retro-TV-Look für absurde
In-Universe-Produkte („Bananen-Fonds 24 — jetzt mit 200 % Zins-Affen!",
„Fell-Gel für den gepflegten Silberrücken"). Als Remotion-Template
(Props: Produktname, Claim, Packshot) → Bibliothek wächst mit der Zeit,
zufällige Auswahl pro Show. Übergang UND Weltenbau in einem;
Jeder-sofort-Skip, da rein dekorativ.

---

## Priorisierungs-Übersicht

| Prio | Ideen |
|------|-------|
| MUST | 1 (Opening), 2 (Kandidaten-Vorstellung), 3 (Runden-Karten), 6 (Siegerehrung), 11 (Drei-Schichten-Regel), 13 (Logo-Stinger), 15 (Remotion=Build-Zeit), 17 (Tutorial-Template), 19 (Bananen-Wipe), 20 (Money-Wipe) |
| SHOULD | 4 (Halbzeit-News), 5 (Finale-Einlauf), 7 (Bestrafung), 8 (Glücksrad), 12 (Blender-Pipeline), 14 (Hybrid-Cutscenes), 16 (Trailer), 21 (Licht-Blende), 22 (Kamera-Swoosh) |
| COULD | 9 (Comeback-Einspieler), 10 (Breaking News), 18 (Attract-Mode), 23 (Affen-Hand), 24 (Fake-Werbung) |

**Empfohlene Bau-Reihenfolge:** 11+15 (Architektur-Entscheid, kostet fast
nichts) → 19+3+2 (minimal spielbare Show-Hülle) → 13 (Logo-Asset) → 1+6
(emotionale Klammer Opening/Ehrung) → 17 (Tutorials) → Rest nach Bedarf;
16 (Trailer) erst, wenn Gameplay-Material für Shots 5–6 existiert.
