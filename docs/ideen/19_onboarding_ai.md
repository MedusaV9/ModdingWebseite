# MONKEY MONEY — Ideen-Agent 19/20: Onboarding, Übungsmodus, AI-Spieler & Zugänglichkeit

Rahmen: Jackbox/Buzz-artige Quiz-Show-Party-App, 2–8 Spieler, iPhones (Safari,
hochkant) als Controller, iPad/PC als Bildschirm, Rollen Spieler/Bildschirm/
Show-Master (GM). Läuft über HTTP (AMP) ODER HTTPS (Cloudflare-Tunnel) —
alles Secure-Context-Abhängige nur über Capability-Schicht mit Fallback
(vgl. Datei 17, Leitprinzip 2). Party-Kontext: SOFORT losspielen.

Aufwand: S (Tage) / M (klein-modulig, mehrere Komponenten) / L (invasiv,
mehrere Subsysteme). Prio: MUST / SHOULD / COULD.

---

## (a) ONBOARDING

### Idee 1 — Host-Erststart „Drei-Fragen-Concierge" — Aufwand: M · Prio: MUST

Erster App-Start des Hosts stellt GENAU drei Fragen, je 1 Tap:

1. **Welche Geräte habt ihr?** (nur Handys / Handys + iPad / Handys + PC+TV)
2. **Gibt es einen großen Bildschirm?** (TV/Beamer / iPad auf dem Tisch / keiner)
3. **Will jemand Show-Master sein?** (ja / nein / „was ist das?" → 1-Satz-Erklärung)

Daraus wird eine konkrete Setup-Empfehlung mit fertigem Preset gebaut
(„iPad in die Mitte, alle scannen den QR-Code, du bist Show-Master auf deinem
Handy") — inkl. Skizze des Raum-Setups. Danach direkt in die Lobby, kein
Settings-Dschungel. Der Concierge merkt sich die Antworten und wird bei
späteren Starts zu einem 1-Tap-„Wie letztes Mal?". Integriert ist ein
60-Sekunden-Selbsttest vor Gästen: Ton-Check, WLAN-Name anzeigen, „öffne auf
einem zweiten Gerät diese URL als Test-Spieler". Skippable für Profis.

### Idee 2 — Spieler-Join in <20 s: „QR → Name → Affe → drin" — Aufwand: M · Prio: MUST

- Screen zeigt großen QR + Kurz-URL `/j/CODE` als Tipp-Fallback (HTTP-Modus:
  QR enthält `http://IP:PORT/j/CODE` — funktioniert im Party-WLAN ohne DNS).
- Join-Seite = EINE Ansicht: Namensfeld mit Vorschlags-Chips (letzte Namen
  aus localStorage, sonst lustige Defaults), Avatar = 1 Tap aus 8 Affen
  (weitere Avatare erst später freigeschaltet/erreichbar — Wahl darf den Join
  nicht bremsen), Button „Rein da!".
- Kein Account, keine E-Mail, keine Berechtigungsabfragen. Session-Token in
  localStorage → Reconnect nach Safari-Tab-Wechsel ist unsichtbar.
- Screen zeigt Join-Fortschritt als Show-Element („6/8 Affen an Bord", jeder
  Neuzugang bekommt einen Einlauf-Jingle) — sozialer Druck beschleunigt die
  Trödler. Messlatte als Test: Kaltstart QR-Scan → spielbereit < 20 s auf
  iPhone 11.

### Idee 3 — JIT-Regelerklärung: „Erst spielen, dann erklären" — Aufwand: M · Prio: MUST

Keine Regel-Wand vor dem Spiel. Jede Mechanik wird beim ERSTEN Auftreten
erklärt: Screen zeigt ≤2 Sätze + 3-Sekunden-Animation (z. B. Wett-Mechanik:
Chips wandern animiert in den Topf), Handys zeigen parallel NUR die eigene
Aktion mit Micro-Hinweis („Tippe deinen Einsatz"). Pro Gerät ein
„schon gesehen"-Flag → Stammspieler sehen Erklärungen nie wieder; GM kann
Erklärungen jederzeit erneut auslösen oder global abschalten („alle kennen's").
Wichtig für Modul-Schnitt: jedes Minispiel liefert seine Erklär-Karte
(Text + Animation) selbst mit — neue Spiele sind damit automatisch onboardbar.

### Idee 4 — Demo-Runde „Nullrunde" mit verstecktem Technik-Check — Aufwand: S · Prio: MUST

Sobald die Lobby voll genug ist: EINE Probefrage, die nicht zählt
(„Aufwärmen! Um nix."). Nutzen dreifach: (1) jeder hat einmal gebuzzert und
geantwortet, bevor es um Punkte geht; (2) die App misst dabei still die
Round-Trip-Latenz pro Handy (Basis für faire Buzzer-Wertung, vgl. Datei 17);
(3) Ton-/Sichtbarkeits-Check („Habt ihr den Gong gehört? Screen lesbar?" —
1-Tap-Bestätigung pro Spieler). Ergebnis der Nullrunde wird als Gag
präsentiert („Ihr seid bereit. Theoretisch.").

### Idee 5 — Spät-Joiner-Crashkurs „Zuschauen mit Untertiteln" — Aufwand: S · Prio: SHOULD

Wer mitten im Spiel joint (vgl. Datei 07, Idee 17: Zuschauer → Einstieg zur
nächsten Runde), bekommt aufs Handy einen 3-Karten-Crashkurs, WÄHREND er
zuschaut: Karte 1 „Worum geht's" (Money sammeln), Karte 2 „Was du gleich
tust" (antworten/wetten), Karte 3 „Aktueller Stand" (wer führt, was läuft
gerade). Die Karten aktualisieren sich live mit dem Spielgeschehen — der
Crashkurs IST die Zuschauer-Ansicht. Beim Einstieg zur nächsten Runde
entfällt jede weitere Erklärung.

---

## (b) ÜBUNGSMODUS

### Idee 6 — Trainingslager: solo auf DEM Gerät, das gerade da ist — Aufwand: M · Prio: MUST

Vertiefung von Datei 07, Idee 8. Gleiche Engine, Session mit 1 Menschen —
aber zwei Darstellungs-Modi: (1) **Handy-Solo**: Controller- und
Screen-Ansicht kombiniert in einer Hochkant-Seite (Frage oben, Antworten in
der Daumen-Zone) — für Bahn/Sofa/Klo; (2) **Bildschirm-Solo**: iPad/PC zeigt
die Show, Handy bleibt Controller — zum „Bühnen-Gefühl üben". Auswahl von
Kategorie(n) + Schwierigkeit + Frage-Formaten, endlos mit sanften
Etappen-Pausen alle 10 Fragen (Weiterspielen = 1 Tap). Kein Game Over —
Training endet, wenn der Spieler aufhört.

### Idee 7 — Lern-Statistik „Bananen-Boxen" (Spaced-Repetition-light) — Aufwand: M · Prio: SHOULD

Kein SM-2-Algorithmus-Overkill, sondern drei Boxen pro gesehener Frage:
**neu → wacklig → sitzt**. Falsch beantwortet = zurück auf „wacklig";
zweimal in Folge richtig = „sitzt". Der Endlos-Mix zieht gewichtet
(~60 % neue, ~30 % wacklige, ~10 % sitzende zur Auffrischung), mit Verfall:
„sitzt" rutscht nach ~14 Tagen ohne Kontakt zurück auf „wacklig".
Statistik-Screen zeigt pro Kategorie einen Reife-Balken („Sport: 12 sitzen,
7 wackeln") statt Prozent-Zahlen — motivierender und ehrlicher. Persistenz
lokal im Spieler-Profil (Anschluss an Datei 15); Zeit via injizierter Clock,
damit der Verfall testbar ist (Repo-Disziplin).

### Idee 8 — Tipps kostenlos + „Warum"-Karte nach jeder Antwort — Aufwand: S · Prio: MUST

Im Training sind alle Show-Joker (50:50, Kategorie-Hinweis, Anfangsbuchstabe)
gratis und unbegrenzt — Üben soll sich nie bestraft anfühlen. Nach JEDER
falschen (und auf Wunsch richtigen) Antwort erscheint eine „Warum"-Karte:
1–2 Erklärungssätze + Eselsbrücke, wenn vorhanden. Konsequenz für die
Fragen-DB: Feld `erklaerung` wird Pflicht-Feld im Content-Format — das ist
der eigentliche Aufwand und muss FRÜH entschieden werden, nachrüsten über
tausende Fragen ist teuer.

### Idee 9 — Trainings-Duell gegen AI: „Sparringspartner" — Aufwand: M · Prio: SHOULD

Kompaktes 1v1 (5–7 Fragen) gegen ein wählbares AI-Profil aus (c) — gleiche
Mechanik wie die Show, gleiche Buzzer-Spannung, aber privat. Doppelnutzen:
Skill-Selbsttest („schaffst du Professor Pavian?") UND Schaufenster für die
AI-Persönlichkeiten, die man dann samstags in die Party-Lobby einlädt. Nach
dem Duell schlägt die App das nächstpassende Profil vor („Zu leicht? Versuch
Turbo-Timmy."). Als Streak-Haken optional eine „Tägliche Banane": 5 Fragen
aus den wackligen Boxen als 3-Minuten-Daily.

---

## (c) AI-SPIELER

### Idee 10 — AI-Profile als reine Daten: „Affen-Kartei" — Aufwand: M · Prio: MUST

Jede AI ist ein JSON-Profil, kein Code: `{name, avatar, basis_staerke,
kategorie_vektor, tempo_verteilung, fehler_muster, risiko_profil,
sprueche_pool}`. Start-Roster mit 5 Persönlichkeiten, die sich SPÜRBAR
unterschiedlich anfühlen:

- **Professor Pavian** — stark in Wissen/Geschichte, langsam, wettet konservativ.
- **Turbo-Timmy** — buzzert blitzschnell, oft schludrig falsch.
- **Gier-Gibbon** — mittelmäßiges Wissen, wettet immer aggressiv (Drama-Garant).
- **Oma Orang** — Alltagswissen & Klassiker top, Popkultur nach 2000 = Blackout.
- **Zufalls-Zeno** — Chaos-Affe für Lachen, Skill niedrig, Sprüche frech.

Neue AIs = neue JSON-Datei + Avatar. Balancing ohne Code-Release änderbar.

### Idee 11 — Realistische Antwortzeiten: die AI „überlegt" sichtbar — Aufwand: M · Prio: MUST

Antwortzeit aus Log-Normal-Verteilung, parametrisiert je Profil × Frage-
Schwierigkeit × Kategorie-Stärke (starke Kategorie = schneller UND sicherer).
Harte Regeln gegen Roboter-Gefühl: nie unter ~800 ms buzzern, gelegentliche
„Zöger-Ausreißer" auch bei leichten Fragen, Status auf dem Screen
(„Professor Pavian überlegt…", Avatar kratzt sich am Kopf). Zeit und Zufall
ausschließlich über injizierte Clock/RNG — AI-Verhalten ist damit im Test
deterministisch reproduzierbar (Seed = Testfall), exakt das Clock-Muster aus
dem Repo.

### Idee 12 — Fehler-Muster statt Münzwurf — Aufwand: M · Prio: SHOULD

Wenn die AI falsch liegt, liegt sie PLAUSIBEL falsch: Distraktor-Wahl
gewichtet nach „Nähe" zur richtigen Antwort (gleiche Dekade, ähnlicher Name,
gleiche Liga) — dafür bekommen Antwortoptionen in der Fragen-DB optional ein
`naehe`-Gewicht. Dazu Muster-Typen je Profil: Flüchtigkeitsfehler (schnell
gebuzzert → höhere Fehlerquote, Turbo-Timmy), Wissenslücken (Kategorie-
Vektor, Oma Orang), seltene „Blackouts" auch in Stärke-Kategorien (macht
AIs schlagbar und menschlich). Risiko-Profil steuert Wett-/Joker-Verhalten.
Effekt am Tisch: Spieler diskutieren über AI-Fehler wie über menschliche
(„KLAR verwechselt der die Brüder!") — das ist das Ziel.

### Idee 13 — Auffüll-Logik: „Mit Affen auffüllen" — Aufwand: M · Prio: MUST

Lobby unter Wunsch-Spielerzahl → 1-Tap-Angebot „mit AI-Affen auf N
auffüllen". Zwei Kalibrierungs-Stufen, transparent wählbar: **Faire Gegner**
(AI-Stärke ≈ Feld-Mittel der letzten Sessions, sanftes Rubber-Banding: nie
uneinholbar vorn, nie peinlich hinten) oder **Profis** (feste Stärke, kein
Mitleid). Kommt ein echter Spät-Joiner, verabschiedet sich eine AI
inszeniert („Gier-Gibbon geht Bananen holen") und der Mensch übernimmt den
Slot samt Kontostand — niemand wartet auf die nächste Session. Mindestregel:
im 2-Spieler-Abend machen 1–2 AIs aus einem Duell eine Show.

### Idee 14 — Persönlichkeits-Sprüche mit Budget & Ton-Regler — Aufwand: M · Prio: SHOULD

Sprüche aus dem Profil-Pool, getriggert von Spielereignissen (Führung
übernommen, knapp verzockt, Mensch überholt AI, Blackout in der
Stärke-Kategorie). Hartes Budget: max. 1 Spruch pro AI pro Runde, nie
während Lese-/Antwortphasen — Sprüche würzen, nicht nerven. Darstellung als
Sprechblase am Screen-Avatar, optional per TTS mit je Profil leicht anderer
Stimm-Einstellung (Rate/Pitch der speechSynthesis-Stimme, siehe Idee 20).
Ton-Regler SFW / frech in den Session-Settings; Spott zielt IMMER auf die
Situation oder die AI selbst, nie unter die Gürtellinie gegen Spieler.

### Idee 15 — AI im Team: Partner, nie Kapitän — Aufwand: M · Prio: COULD

Bei ungerader Spielerzahl in Team-Modi (vgl. Datei 06) darf eine AI als
Duo-Partner einspringen. Regeln gegen Frust: AI übernimmt nur Rollen ohne
verdecktes Meta-Wissen (mit-antworten, Einsatz VORSCHLAGEN — Mensch hat
Veto per Tap), nie Kapitäns-Entscheidungen, nie Verräter-Rollen. Der
AI-Vorschlag ist sichtbares Team-Theater („Professor Pavian empfiehlt: 500
setzen") — Annehmen/Ablehnen wird ein eigener kleiner Spaßmoment.

### Idee 16 — „AI-Ghost": der abwesende Stammspieler spielt mit — Aufwand: L · Prio: COULD

Opt-in: Aus den lokalen Stats eines Stammspielers (Kategorie-Genauigkeit,
Tempo-Verteilung, Risiko-Verhalten — Anschluss an Datei 15) wird ein
Ghost-Profil erzeugt. „Kevin ist krank — sein Geist spielt trotzdem mit."
Avatar = Kevins Affe mit Geist-Schimmer. Sozial goldwert in Stammgruppen,
aber bewusst COULD: braucht saubere Stats-Basis und Einverständnis-Flow
(Ghost nur, wenn Kevin es in seinem Profil erlaubt hat).

---

## (d) ZUGÄNGLICHKEIT

### Idee 17 — Textgrößen-System mit Content-Gate — Aufwand: M · Prio: MUST

Drei Stufen (Standard / Groß / Riesig), GETRENNT einstellbar für Screen
(Betrachtungsdistanz Sofa→TV!) und Spieler-Handy (pro Gerät, in den
Join-Settings). Technisch ein einziges rem-Token pro Client. Der eigentliche
Hebel ist das Content-Gate: ein Linter in der Fragen-Pipeline prüft
Maximal-Längen für Frage/Antworten, sodass die längste Frage der DB in
„Riesig" auf iPhone 11 UND auf dem Screen aus 4 m Entfernung ohne Scrollen
lesbar bleibt. Ohne dieses Gate wird jede Textgrößen-Option irgendwann von
einer 300-Zeichen-Frage zerschossen.

### Idee 18 — Farbe + Form + Buchstabe: farbenblind-sicher by design — Aufwand: S · Prio: MUST

Antwortoptionen A–D tragen IMMER drei redundante Kanäle: Farbe, Form
(Dreieck/Kreis/Quadrat/Stern — Buzz!/Kahoot-bewährt) und Buchstabe. Gleiche
Formen auf Handy-Buttons, Screen und Gamepad-Legende (Idee 22) → „drück das
Dreieck" funktioniert für alle. Zwei alternative Paletten
(Deuteranopie/Protanopie-freundlich, Tritanopie-freundlich) als
Session-Setting; Team-Farben zusätzlich mit Mustern (Streifen/Punkte).
Style-Guide-Regel von Tag 1: KEINE Information nur über Farbe. Als reine
Design-Disziplin fast gratis — nachträglich ein Repaint aller Screens.

### Idee 19 — Daumen-Zone, spiegelbares Layout, Riesen-Buzzer — Aufwand: S · Prio: SHOULD

Alle kritischen Aktionen auf dem Handy liegen im unteren Drittel
(Daumen-Zone, einhändig bedienbar — Party heißt: ein Bier in der anderen
Hand). Layout pro Spieler-Gerät spiegelbar (Links-/Rechtshänder: Primär-
Buttons und Bestätigen-Seite wechseln), Einstellung direkt auf der
Join-Seite hinter einem Hand-Symbol. Der Buzzer ist die gesamte untere
Bildschirmhälfte — nicht verfehlbar, auch mit geschlossenen Augen. Touch-
Targets überall ≥ 44 pt.

### Idee 20 — Lese-Zeit-Regler + „Ruhe-Modus" — Aufwand: M · Prio: SHOULD

Globale Lese-Zeit-Skala (0.75×–2×) multipliziert alle Frage-Timer — eine
Zahl, die der GM/Host für die Gruppe stellt („Oma liest mit? 1.5×.").
Getrennt davon der **Ruhe-Modus** als Session-Schalter: keine tickende
Countdown-Musik, Timer als ruhiger Fortschrittsbalken statt Beep-Countdown,
keine Blitz-/Shake-Animationen, sanftere Sounds. Respektiert zusätzlich
`prefers-reduced-motion` des Geräts automatisch. Zielgruppen: Kinder,
reizempfindliche Mitspieler, späte Stunde — Zugänglichkeit als
Session-Option, nicht als separater Modus (konsistent mit Datei 07,
Idee 23).

### Idee 21 — Sprachausgabe: speechSynthesis geht auch über HTTP — Aufwand: M · Prio: SHOULD

Antwort auf die offene Frage: **Ja, Web Speech API (Ausgabe-Teil) ist
HTTP-tauglich.** `speechSynthesis` (TTS) ist in Chrome, Safari und Firefox
NICHT an Secure Context gebunden → funktioniert im AMP/HTTP-Modus.
Fallstricke, die die Capability-Schicht kapseln muss: iOS-Safari braucht
eine erste Nutzergeste zum Entsperren (beim Join-/Start-Tap miterledigen,
gleiches Muster wie Audio-Unlock), `getVoices()` lädt asynchron
(voiceschanged-Event abwarten), Stimmqualität variiert je Gerät. Empfehlung:
Vorlese-Funktion primär auf dem SCREEN-Client (bekannter Browser, eine
„Show-Master-Stimme" liest Frage + Antworten vor — hilft Sehschwachen und
Lese-Schwächeren gleichzeitig), am Handy optional pro Spieler zuschaltbar.
**Gegenstück Spracherkennung (STT) NICHT einplanen:** SpeechRecognition
verlangt in Chrome Secure Context + Cloud-Anbindung → höchstens als Bonus im
Cloudflare-HTTPS-Modus, nie als Kern-Feature.

### Idee 22 — Screenreader-Grundgerüst von Tag 1 — Aufwand: S · Prio: MUST

Der Player-Client ist bewusst winzig (eine Ansicht pro Phase, vgl. Datei 17)
— genau deshalb ist Screenreader-Tauglichkeit JETZT billig und später teuer:
semantisches HTML (echte `<button>`), `aria-live="polite"` für
Phasenwechsel-Ansagen („Runde 3, deine Antwort ist gefragt"), sichtbare
Fokus-Ringe, logische Fokus-Reihenfolge. Kein WCAG-Vollaudit als Ziel,
sondern: ein VoiceOver-Nutzer kann joinen, antworten und wetten. Definierter
Smoke-Test: eine Runde komplett mit VoiceOver auf iPhone durchspielen.

---

## (e) CONTROLLER

### Idee 23 — Gamepad am Screen-Client: 4 Face-Buttons = 4 Antworten — Aufwand: M · Prio: SHOULD

Gamepad API im Screen-Client (PC-Browser; iPadOS unterstützt Xbox-/
PS-Controller in Safari nativ). Mapping: 4 Face-Buttons = Antworten A–D,
und zwar über die FORMEN aus Idee 18 verdrahtet — auf PS-Controllern sind
Dreieck/Kreis/Quadrat/Kreuz sogar physisch aufgedruckt, der Screen zeigt die
Legende passend zum erkannten Pad. D-Pad/Stick = Menü-Navigation, beliebige
Taste = Buzzer, Start = bereit/weiter. Caveat für den HTTP-Modus: die
Gamepad-Spec ist SecureContext-markiert, Chrome toleriert HTTP bislang mit
Deprecation-Warnung → früh im AMP-Setup testen und hinter die
Capability-Schicht legen (Fallback: Tastatur-Mapping, Idee 24 — Tastatur ist
garantiert HTTP-sicher).

### Idee 24 — „Sofa-Modus": Hotseat/Local-Play ganz ohne Handys — Aufwand: L · Prio: SHOULD

Antwort des Drei-Fragen-Concierge auf „keine Handys / Akku leer / Kinder
ohne Gerät": 2–4 Spieler an EINEM Bildschirm mit je einem Gamepad ODER
geteilter Tastatur (Zonen: WASD / Pfeiltasten / Numpad / IJKL). Design-
Konsequenz ernst nehmen: verdeckte Eingaben sind am geteilten Screen
unmöglich → der Sofa-Modus nutzt nur Mechaniken ohne Geheim-Infos
(Buzzer-Rennen, gleichzeitig-offen antworten mit Blind-Commit: Eingaben
werden erst nach Timer-Ende gemeinsam aufgedeckt, Schätzfragen). Das ist das
Buzz!-Erbe der App — und der Modus, der auf LAN-Partys und im Wohnzimmer
mit Besuch „einfach immer geht". Mischbetrieb erlaubt: 2 am Pad + 4 am
Handy in derselben Lobby.

### Idee 25 — Ein-Knopf-Modus: Controller als Zugänglichkeits-Brücke — Aufwand: M · Prio: COULD

Switch-Access-Muster für motorisch eingeschränkte Mitspieler: ein
Auto-Scan-Highlight wandert in einstellbarem Tempo über die
Antwort-Optionen, EINE beliebige Taste (Gamepad-Button, Leertaste, oder
Riesen-Buzzer-Fläche am Handy) wählt aus. Kombiniert mit Lese-Zeit-Regler
(Idee 20) spielbar ohne Zeitdruck-Frust. Pro Spieler aktivierbar, nicht
global — der Rest des Tisches spielt normal weiter. Wenig Code (ein
Eingabe-Adapter vor der bestehenden Antwort-Logik), großer Kreis neuer
Mitspieler.

---

## Top-5 (Empfehlung des Agents)

1. **Idee 2 — Spieler-Join in <20 s** (MUST): Der Party-Kontext steht und
   fällt mit dem Join. Alles andere ist zweitrangig, wenn Gäste hier hängen.
2. **Idee 3 — JIT-Regelerklärung** (MUST): Löst „SOFORT losspielen"
   strukturell — und zwingt nebenbei zu sauberem Minispiel-Modul-Schnitt.
3. **Idee 13 — AI-Auffüll-Logik** (MUST): Macht 2-Spieler-Abende zur Show
   und ist der Haupt-Kaufgrund für AI-Spieler überhaupt.
4. **Idee 10+11 — AI-Profile als Daten + sichtbares Überlegen** (MUST):
   Fundament aller AI-Ideen; deterministisch testbar dank Clock/RNG-Injektion.
5. **Idee 18 — Farbe+Form+Buchstabe** (MUST): Fast gratis, wenn von Anfang
   an — verankert Zugänglichkeit im Design-System statt in Sonderlocken
   (und Idee 23 erbt das Formen-Mapping für Controller kostenlos).

## Querverbindungen

- Datei 07 (Modi): Idee 8 „Trainingslager" hier vertieft (Ideen 6–9);
  Spät-Joiner (deren Idee 17) ↔ Crashkurs (Idee 5) und AI-Slot-Übergabe
  (Idee 13); Barrierefreiheit als Session-Option (deren Idee 23) ↔ Ideen 17–22.
- Datei 15 (Profile/Stats): Lern-Boxen (Idee 7) und AI-Ghost (Idee 16)
  bauen auf lokalen Spieler-Stats auf.
- Datei 17 (Architektur): Capability-Schicht für speechSynthesis (Idee 21)
  und Gamepad-über-HTTP (Idee 23); Latenz-Messung der Nullrunde (Idee 4)
  füttert die faire Buzzer-Wertung; Clock/RNG-Injektion trägt Ideen 7 und 11.
- Datei 06 (Teams): AI als Duo-Partner (Idee 15) nutzt deren Team-Strukturen.
