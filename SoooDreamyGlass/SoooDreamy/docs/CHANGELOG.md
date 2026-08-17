# Changelog

Alle nennenswerten Änderungen an SoooDreamy (App + Server). Datumsangaben in UTC.

## [16.0.0] — 2026-08-16 — Das Nachtpostamt (FULL RELEASE)

Der völlige Neubau auf das User-Feedback zu 15.0.0 („Intro auf dem
Gerät verbuggt, Leiste komisch, völlig neuer Aufbau, einzigartig statt
generisch"). Konzept-Wettbewerb (3 Dossiers + Jury → NEUBAU_ENTSCHEID),
Umbau in 4 Wellen (N1 Umzug 147 git mv, N2 Postfach, N3 Schreibstube/
Spieltisch, N4 Archiv/Amt/Anker), danach 5 Eval-Runden mit 8 Ressorts
bis ALLE PERFEKT. (MARKETING_VERSION 15.0.0 → 16.0.0, Build 53 → 54.)

### 📱 Geräte-Wahrheit (Ursprung der Runde)
- hev1→hvc1: Remotion-Videos trugen das falsche HEVC-Sample-Entry —
  iPhone-Hardware-Decoder lehnten still ab (Simulator spielte). Remux
  verlustfrei + doppeltes fail-closed-Gate (echter ISO-BMFF-Box-Walker
  mit In-Memory-Selbsttest, nach Render UND vor IPA-Packen).
- App-Panzerung: Item-Failure/Stall/Dry-Queue/Poster-Fehler → Kapitel
  fällt MID-RUN auf die prozedurale Kurzfassung; First-Frame-Watchdog
  mit Generationen-Stempel (Generation, Item) — nur die eigene
  false→true-Kante entwaffnet; Foreground-ehrliche Zeit.
- TabBar-Minimize entfernt; Partikel-Bounds; QuietPermissions-Naht;
  Prozess-Alive-Gate im Screenshot-Job (Jetsam-Homescreen fiel durch
  den Groessen-Floor).

### 🏤 Der Neubau: Nachtpostamt (5 Stationen, 147 Dateien umgezogen)
- POSTFACH: Zustellrunden (Morgen/Tages/Nachtpost, Runden-Menge pro
  Datum, Briefschlitz einmal pro Runde), Tagesbrief IMMER gestempelter
  Hero, Dienstlicht, TelegrammLeiste (SF-Chips statt Emoji-Raster,
  Voice-Control-Doppelnamen), Sendung Nr. 1 (versiegelter Brief statt
  Nest-Karte), Polaroid-Entwickeln (Press-and-hold, 1x/Tag).
- SCHREIBSTUBE: ChatView 2714→261 Zeilen (9 Zonen-Dateien), Siegelpresse
  buendelt Zeitpost/Kapsel/Tuerchen, Spindelstich beim Senden; sender-
  skopierte chatRowID (senderId, clientMessageId) mit Versoehnungs-
  Gesetz — ACK-Remounts/Doppel-Scroll/Duplikate strukturell tot.
- SPIELTISCH: Kartenschrank (3 Faecher, adressierte Umschlaege mit
  Lasche-auf), Punktlinien-Kapitelzeilen mit LEBENSLANG ehrlichen
  Zahlen (persistentes gamesAggregate uebersteht Kappung, isPlayedGame-
  Truth-Table beidseitig, lowerBound-'{n}+', Match-Verdikte zaehlen
  wie die Bilanz listet), Tagesaushang-Hero, AX5 vertikal.
- ARCHIV: Schrankfront mit 6 Faechern + Schubladenauszug (End-Detent),
  sprachUNabhaengige Suche mit Aliasen (DE×EN-Matrix-Pin) auf iPhone
  UND iPad, Vorschauzeilen, Fach-Gedaechtnis.
- AMT: natives Form(.grouped) in 6 Registern, Schluesseldreh
  (symbolEffect), Zustellrunden-Toggle, wirklich still (alle Sheets
  showBlobs:false).

### 🎬 Intro & Gesicht
- Sprach-Gate mit Wachs-Haekchen-Auswahl (beide Karten bleiben lesbar),
  Tintenwahl als 4×2 mit Tintenspur, Guide-Hero = versiegelter Brief
  (statt 3D-Emoji-Herz), Guide-Ende als durchgehende Zustellroute
  (scrollfaehig, Laengen-Pin), t57-Handoff mit EINEM morphenden Label.
- App-Icon neu: Nachtzimmer/Lampengold/Polaroid/tiefer Siegellack aus
  den PaperRules-Quellen (Drift-Test pinnt Wortlaut); Siegellack-
  Primaerknopf + goldene Tinte app-weit (Pink-Lila restlos entfernt,
  inkl. Avatar-Fallback).

### ✅ Abnahme & Gates
- 5 Eval-Runden × 8 Ressorts (6× GPT-Sol, 2× Fable): >90 Befunde
  strukturell geschlossen; Endstand ALLE ACHT PERFEKT (Gesamtbild:
  „einzigartig statt generisch — freigegeben").
- Swift 940/940, Server 509/509, 20 Charta-Ratchets gruen, CI komplett
  gruen inkl. 5 UI-Tests + 38-Shot-Beweis-Matrix (u. a. Kapsel-
  Zeremonie, AX5-Paare, Auswahlzustaende, ipad-main).

## [15.0.0] — 2026-08-15 — Lampenlicht

Die Nachtkorrektur auf das User-Feedback zu 14.0.0 („zu hell, Intro
verbuggt, wirklich benutzen und testen"). Drei Wellen (P1 Fundament+Tests,
P2 Screens, Fix-Iterationen), abgenommen von drei finalen Evaluatoren
(Dunkel-Artstil, Intro, Nutzungsqualität — letzterer mit eigenem
Arena-Lauf und forensischem Detektor-Beweis).
(MARKETING_VERSION 14.0.0 → 15.0.0, Build 52 → 53.)

### 🌙 Nacht-first (P1-A, P2-A–D)
- Zimmer vertieft (#1A100B/#2A1B12), `Papier.nachtkarton` (#33241C) als
  Standard-Karte via `nightCard()` — ~260 Stellen mit komplettem
  Tinten-Flip; helles Papier NUR noch als Artefakt (Briefbogen, Bubbles,
  Briefe, Polaroids, Spielbretter, Gutscheine, Umschläge). Dritter
  Kontrast-Anker testgepinnt; Wachs tief (#7E2429→wachsTief) mit heller
  Prägung; Lampenkegel nachjustiert; Widget-Zimmer-Spiegel nachgezogen.

### 🎬 Intro strukturell entbuggt (P1-B + Finale)
- KERN-BUG: Das Sprach-Gate erschien NIE — `AppState.bootstrap()`
  persistierte den Sprach-Key bei jedem Start (Spiegel-Trigger), das Gate
  keyte darauf. Jetzt dedizierter `languageGateDone`-Key mit exakt drei
  Schreibern (Kino-Gate, Guide-Chips, Settings), E2E-bewiesen.
- 7 Playback-Bugs: Doppel-Belichtung bei Kapitelwechseln
  (`CinematicChapterOnStage` mit Value-Capture statt Live-State in der
  scheidenden Crossfade-Instanz), dimmende Video-Naht (EIN persistenter
  `CinematicVideoSurface`), stale-Advance-Gate (`advanceTarget`),
  Skip-vs-Item-Ende auf Queue-Wahrheit, Run-Korruption plan-aligned,
  Lampen-Beat-Überleben, Freeze-Fidelity; dazu Poster-Underlay bis
  `isReadyForDisplay`, Advance-Debounce, Bloom-Ringe als
  Zero-Footprint-Overlay (Chrome-Clipping), Antwort-Prompt in
  `Tinte.tertiaer`. 60 Kino-Logic-Tests pinnen die Bugklassen.
- CI-Frame-Serie: 8 eingefrorene Playheads (t=2…57) als Screenshots in
  jedem Build.

### 🧪 Die App wird bei jedem Build BENUTZT (P1-C, P1-D)
- `SoooDreamyUITests` (5 Drehbuch-Tests) bedienen die echte App im
  CI-Simulator: Sprachgate→Intro→Skip→Guide, Demo-Tour über alle Tabs,
  Chat-Senden+Systemsuche, Zeitpost-Sheets, Königs-Test (UI-Pairing gegen
  echten Node-Server auf dem Runner, Erster-Gruß-Heartbeat mit In-Test-
  Journal-Poll + unabhängigem curl-Doppelbeweis). 7 Fix-Iterationen bis
  grün — dabei echte App-Befunde (Gate-Bug, Bar-Minimize versteckt
  Tab-Buttons, SDK-Suchbutton unadressierbar → Test-Seams).
- Multi-Paar-ARENA (`tools/arena/`): 6–12 Paare × 2 Geräte live über
  HTTP+WS gegen einen echten Server — seeded Szenarien inkl.
  Zeitpost-Echtzustellung, Daily-Pin-Races, Lease-Spielen,
  Reconnect-Stürmen und SIGKILL-Restart mitten im Lauf; zweistufiger
  Invarianten-Prüfer (Cross-Couple-Registry, exactly-once, Idempotenz,
  Persistenz-Diff). 18.726 Requests / 46.921 Frames / 0 Verletzungen —
  und 1 echter Server-Bug gefunden+gefixt (viaPost-Pulse-Zustellung
  startete den Sender-Cooldown; `presence.js` + Regressionstests).

### ✅ Gates
- Swift **844/844**, Server **497/497**, 19 Charter-Ratchets grün,
  CI komplett grün inkl. UI-Test-Gate (Läufe 31910588570 / 31911859046).

## [14.0.0] — 2026-08-15 — FULL RELEASE

„Papier & Licht": der Sprung aus der Alpha. Fünf Design-Richtungen traten im
Jury-Wettbewerb an (`docs/styles/DIRECTION_*.md`, Entscheid in
`STYLE_DECISION.md`); der Gewinner wurde als Art Direction v2 durch die
GESAMTE App getragen, dazu native iOS-26-Plattformarbeit, ein Remotion-Kino,
die Poststation und eine 10/10-Abnahme durch zehn Prüfperspektiven aus zwei
KI-Modellfamilien (drei Runden, Fix-Wellen R1–R3).
(MARKETING_VERSION 13.0.0 → 14.0.0, Build 51 → 52, Server-`package.json` im
Gleichschritt. Dieses Release erzeugt erstmals das ECHTE versionierte
GitHub-Release `v14.0.0` mit beiden IPAs.)

### 🕯️ Art Direction „Papier & Licht" (Wellen N1-B, N2-A–D, R1-A)
- `DreamyBackground` ist das Sepia-Zimmer: statischer Zimmer-Verlauf
  (#201613→#33241B), 10-Uhr-Lampenkegel mit Doppel-Falloff (Geometrie aus
  dem Remotion-`look.tsx`), 18 seeded Tintenstaub-Motes in den Paarfarben —
  Aurora-Blobs und Sternfeld sind gelöscht.
- Zwei-Materialien-Gesetz app-weit: Inhalt = opakes Papier (`paperCard`,
  Korn als einmal gerasterte Kachel, Lichtkante), Schwebendes = System-Glas.
  `surface_glass_features` 320 → 2 dokumentierte Ausnahmen.
- Chat als Korrespondenz: BEIDE Seiten Papier-Zettel mit 4-pt-Tintenkante
  (eigene `polaroid`-hell rechts, Partner `brief` links), Poststempel-
  Datumschips, Briefe auf Briefbogen mit materiellem `WachsSiegel`
  (seeded Blob-Kante, Herz-Relief) — derselbe Baustein siegelt Kino,
  Briefe und Zeitpost.
- Kontrast-Doppel-Anker (#201613 Nacht + 4 Papiertöne) mit `inkOnPaper`-
  Leiter, gepinnte 8×4-Matrizen; Kitsch-Budgets (3 Artefakte / 1 Riss /
  1 Solitär-Rotation bzw. 3 pro Sammlung) als testgepinnte Gesetze.

### ✨ Native Plattform (N1-A, R1-E, R3)
- Custom-Dock gelöscht → echte iOS-26-`TabView` (System-Liquid-Glass,
  `tabBarMinimizeBehavior(.onScrollDown)`, natives Badge, Re-Tap-Scroll,
  ⌘1–⌘5) + `tabViewBottomAccessory` „Heute-Zettel" (Partner-Präsenz +
  Tages-Hinweis, inline/expanded).
- Chat-Identität als Toolbar-Principal (Messages-Muster), System-`.searchable`
  in Chat + Journal, Fortschritt via `ProgressView`/`Gauge`-Styles,
  Einstell-Sheets als `Form(.grouped)`, Verbindungs-Chip als Chrome-Glas.
  `PrimaryButtonStyle`/`SecondaryButtonStyle` als benannte Marken-Ausnahmen
  in DESIGN.md verankert; iPad-Drag als dokumentierte Etappe.

### 🎬 First-Launch-Kino (N1-C, N3-Kino, R1-B, R2)
- Sprachwahl (Lampenklick) als wartendes Kapitel 1; danach 7 Kapitel,
  45–60 s wallclock-testgepinnt: drei in CI gerenderte Remotion-Filme
  (HEVC bt709, 1,18 MB, „TAG 1"-Poststempel aus SVG-Pfad-Glyphen,
  Lichtwanderung/Falztiefe/Schattenparallaxe) + interaktive Tintenwahl
  und Wachssiegel-Pressen, Haptik/Sound aus Timecode-Manifesten
  (`addBoundaryTimeObserver`).
- Das Finale ist ein echter Handoff: der Guide ist unter dem Kino montiert,
  PreferenceKey-Frames führen die letzten Zettel pixelgenau in die echten
  Buttons, und `ambientSettle` blendet das Kino-Licht in exakt die
  `DreamyBackground`-Komposition — kein Schnitt, keine Attrappe.
- Lite-Fallback (prozedurale Kurzfassungen), Reduce-Motion-Poster,
  VoiceOver-Kapitel mit separaten „Weiter"/„Überspringen"-Aktionen,
  Demo-Modus startet mit demselben Kino, Replay in den Einstellungen.

### 💌 Die Poststation (P6-B, R1-C, R1-D)
- Zeitpost (Touch/Puls/Notiz, 5 min–7 Tage, max. 5 offen, Empfänger sieht
  nie Ausstehendes), Echo-Antworten (10-min-Fenster, einmalig, beidseitig
  erzwungen), Sendungs-Journal (30 Tage, Tinten-Kanten).
- Zustellung als durable Outbox-Transition: Artefakt mit stabiler Id +
  Entfernung in EINEM synchronen Übergang, fsync-WAL vor Fanout/Push,
  Re-Sweep-Idempotenz — exactly-once fürs Artefakt, per SIGKILL-Tests an
  beiden Crash-Fenstern bewiesen; RFC-3339-Strenge, Push-Privacy-Pin.
- Aufgeben ist eine Zeremonie (Falten → Poststempel auf dem Kino-Beat →
  Abheben), Ankommen ein Moment (`PostNoteOverlay`: Siegelbruch durch die
  Hand des Empfängers). Zwei neue TouchKinds `stolz`/`haltedurch`.

### 🌱 Inhalte & Marke (P6-A, N3-Icon, P6-C, R1-F, R2)
- +312 zweisprachige Items (Tagesfragen 510, Ideen 282, Quests 203, …),
  Guinness-Fakten aktuell (Hiller ≈89 J., Littman/Fiterman 202 J.).
- Neues Logo „Versiegeltes Polaroid" (4 Ebenen, 10 Paletten, 60-px-lesbar);
  `IconPaletteTable` als Single-Source mit Quell-Scan-Test gegen den
  Generator; Widgets im Zimmer-bei-Nacht-Default + „Papier & Licht"-Theme,
  Live-Activity-Kontraste testgepinnt.
- Performance: Papierkorn als geteilte Kachel, `Heart3DView` mit 30-fps-Cap,
  Low-Power- und Sichtbarkeits-Gate, Saison-Partikel Low-Power-gegated,
  Formatter-Cache.

### ✅ Abnahme
- 10/10 in ALLEN zehn Prüfperspektiven (Artstil, Nativität, Kino,
  Robustheit, Server, Content, A11y, Performance, Widgets/Marke, Feel) —
  je zur Hälfte von Fable- und GPT-Sol-Evaluatoren, mit Screenshot- und
  Fault-Injection-Beweisen. Gates: Swift **820/820**, Server **493/493**,
  19 Charter-Ratchets grün.

## [13.0.0] — 2026-08-15

„Bis ins letzte Detail": die Perfektionsrunde. Nach einem zweiten Ideensturm
wurde die App in Rework-Wellen neu angestrichen und vertieft — und danach von
einer Batterie aus zwölf unabhängigen Prüfperspektiven (Feel, Polish,
Bugfreiheit, Klarheit, Dopamin, Modernität/HIG, Onboarding, Spiele-Tiefe,
Content-Seele, Accessibility, Multi-Device, iPad) über sieben Runden
abgenommen; zwischen den Runden schlossen die Fix-Wellen A–G jede gemeldete
Lücke, bis alle zwölf zufrieden waren.
(MARKETING_VERSION 12.0.0 → 13.0.0, Build 50 → 51, Server-`package.json` im
Gleichschritt.)

### 🎨 UI-Rework & First-Launch-Kino
- Deko-Emojis wichen einer ruhigen SF-Symbol-Sprache (`Iconography`-Fassade);
  Feature-Flächen färben sich konsequent über `CoupleTint` in die beiden
  Paarfarben statt in hartes Pink/Lila; Erfolge prägen prozedurale
  Glas-Medaillen (`GlassMedal`); die Widgets wanderten auf
  `WidgetPalette`/`WidgetTypo`-Tokens. Die Charter-Ratchets rasteten mehrfach
  tiefer ein (u. a. `emoji_as_text` in Features → 0).
- Der erste Start ist ein ~20-sekündiges prozedurales Kino
  (`CinematicScript` + `CinematicIntroView`): Licht, Parallax-Sterne,
  Haptik-Choreografie und Sound, deklarativ als getestetes Skript —
  überspringbar, mit ruhigem Reduce-Motion-Pfad, ganz ohne Video-Assets.

### 🎲 Neun neue Spiele
- Dame, Reversi, Käsekästchen, Gomoku, Mancala und Memory-Duo als
  Foundation-reine `BoardGameRules`-Reducer (45 Logic-Tests), server-validiert
  mit legalen-Zug-Hinweisen; Wordle-Duo, Schere-Stein-Papier (Commit-Reveal —
  versiegelte Wahl) und Geschichten-Staffel als Wort-/Party-Spiele.
- Jedes Spiel erklärt sich beim ersten Öffnen (`GameIntroCatalog`); der
  Spiele-Hub kuratiert nach Energie und Anlass (`PlayHubCuration`);
  Turn-Anzeigen sind server-autoritativ (`turnMemberId` end-to-end).

### 🌱 Content-Seele & Konsens
- +246 zweisprachige Inhalte (Tagesfragen, Date-Ideen, Quests, Rätsel,
  Quiz, This-or-That, Would-you-rather) mit Tiefen-/Energie-Tagging und
  paar-stabiler, wiederholungsfreier Rotation.
- Konsens-Pass über alle körperlichen Karten: Die Handlung wird beim Ja
  benannt, die eingeladene Person entscheidet frei; Passen bei Wahrheit oder
  Pflicht ist folgenlos (kein Serienverlust, kein Strafton, kein
  Punktabzug — `skip_quota` serverseitig entfernt). Vollständiges natives
  EN-Lektorat; „your love" global durch „your partner" ersetzt.

### 👀 Kontrastgarantie & Accessibility
- `CouplePaletteRules.gradientForegroundVerdict` garantiert ≥4,5:1 auf JEDEM
  Paarverlauf: berechnete Tinte, sonst Nacht-Scrim-Leiter auf der leichtesten
  wirksamen Stufe — von der vollen Paarmatrix in Logic-Tests bewiesen und in
  JEDEM Renderer adoptiert (eigene Chat-Bubbles zentral, Senden-Knöpfe,
  Streak-Kalender, Galerie-FAB, VoiceNote-Meta).
- Statisches Pendant fürs Marken-Gradient: `Theme.onHero` +
  `Theme.heroPlatter(in:)` (Verlauf+Scrim als EINE Einheit) — 17 zuvor
  hart-weiße Controls in 11 Dateien umgestellt; `CoupleTint.onLight` sichert
  Akzente auf weißen Kapseln, `onWax` das Wachssiegel.
- VoiceOver spricht die neuen Spiele vollständig (Buchstaben-Verdikte,
  Rundenergebnisse, Autoren-Wechsel); Read-Receipts tragen ihren Zustand in
  der Häkchen-Anzahl (farbunabhängig); AX5 ohne Clipping; `MotionGate`
  drosselt Dauer-Animationen unter Reduce Motion.

### 📌 Die unverwechselbare Tagesfrage
- Die erste Antwort pinnt die Frage; `GET /api/widget-snapshot?dateKey=`
  liefert Pin, gespeicherten Fragetext und Antwortstatus für den LOKALEN Tag
  des Geräts (`DailyPinRules` als Datums-Gate); `POST /api/daily/:dateKey`
  speichert beim Pin den zweisprachigen `questionText`, sodass jeder Stand
  die gepinnte Frage rendern kann.
- Divergente Zweitantworten → `409 daily_question_mismatch` mit maßgeblicher
  Id + Text; der direkte Pfad adoptiert sofort bei erhaltenem Entwurf, der
  Offline-Replay birgt den Text als Tages-Draft (`DailyAnswerDraftStore`)
  statt ihn still zu verwerfen; abgelehnte Operation-Ids werden nie als
  Duplikat erinnert. Bewusster, dokumentierter Trade-off für sehr alte
  Stände: klare Update-Aufforderung statt stiller Falsch-Zuordnung.

### 🔧 Härtung quer durch
- Delight-Budget app-weit atomar (`DelightArbiterStore`); `goal_updated`
  ohne Doppel-Feier beim Self-Echo; Idempotenz-Ledger verdrängt nur
  Abgelaufenes; Revoke-Tombstones ohne Recovery-Key-Hintertür; 409-Details
  (`conflict`/`stale_generation`/`game_lease_held`/Daily) typisiert dekodiert
  und adoptiert; Welcome-Catch-up lädt Events/Listen/Canvas nach.

### ✅ Abnahme
- 12/12 Prüfperspektiven ZUFRIEDEN (Schlussstand u. a. Spiele 10/10,
  iPad 10/10, Content 10/10, Modernität 10/10, A11y 10/10, Bugs 9/10).
- Gates beim Release: Swift-Logic **751/751**, Server **472/472**,
  Charter-Ratchet grün, CI (macos-26: IPA, Lite-IPA, Simulator-Screenshots
  iPhone DE/EN + iPad, Logic- und Server-Tests) durchgehend grün.

## [12.0.0] — 2026-08-14

„Mehr Platz für euch": sieben Wellen in einem Release — die App wächst aufs
iPad und auf Zweitgeräte, das Gerät hilft beim Formulieren und Übersetzen,
Spiele werden zu Tischen, und der erste Start wird eine Einladung.
(MARKETING_VERSION 11.1.0 → 12.0.0, Build 49 → 50, Server-`package.json` im
Gleichschritt.)

### 🖥️ iPad-Vollausbau (W1A/W5)

- **Device Family 1,2**: iPhone + iPad, alle vier iPad-Ausrichtungen, KEIN
  `UIRequiresFullScreen` — Split View, Slide Over und Stage Manager laufen;
  schmale Fenster fallen nahtlos aufs bewährte iPhone-Layout zurück.
- **Größenklassen-adaptive Layouts** statt vergrößertem iPhone: Dashboard-
  Raster, Erinnerungen als Split mit Sektionen-Sidebar, Brief-/Tagebuch-
  Lese-Spalten, zentrierte Content-Columns über Container-Metriken.
- **Apple Pencil** auf der Kritzel-Leinwand: Druckstärke moduliert den
  Strich, Hover zeigt die Einsatzstelle (Representable-eigener
  `gesture()`-Overload).
- **Hardware-Tastatur**: Cmd+1…5 wechseln die Tabs, Cmd+Return sendet;
  **Drag & Drop** legt Bilder direkt in Chat und Galerie ab.
- **Entwurfs-Kontinuität**: Brief- und Chat-Entwürfe überleben
  Größenklassen-/Layout-Wechsel (DraftContinuityRules).
- **XL-Widgets**: „Tage zusammen" zweispaltig als systemExtraLarge, das
  Foto-Widget mit echtem Landscape-Crop.

### 📲 Multi-Device (W1B/W3)

- **Mehrere Geräte pro Person** (bis 8 Sitzungen): Einmal-Geräte-Code auf dem
  verbundenen Gerät (`POST /api/sessions/link-code`, 10 min TTL, single-use,
  nur als SHA-256-Digest gespeichert), einlösen per QR, Code oder
  `sooodreamy://link`-Deep-Link (`POST /api/couples/link`) — ohne
  Recovery-Zeremonie, der Wiederherstellungs-Schlüssel rotiert dabei NICHT.
- **Geräte-Manager** in den Einstellungen: alle Plätze mit
  „Dieses Gerät"-Markierung, gezieltes Abmelden, ehrliche
  Leer-/Offline-/Fehler-Zustände; `device_linked`-Live-Toast auf den eigenen
  anderen Geräten.
- **`origin`-Marker + Self-Echo-Fanout**: member-verursachte Realtime-Frames
  tragen `{memberId, deviceId, sessionSuffix}` — das eigene Zweitgerät zeigt
  einen dezenten Tick statt Partner-Overlay, Echos deduplizieren sich sauber.
- **Session-Eviction gehärtet**: tote Einträge (widerrufen/abgelaufen)
  weichen vor der ältesten lebenden Sitzung.

### ✨ Liquid-Glass-Vertiefung (W2)

- Tab-Dock und Composer als echtes `safeAreaBar`-Glas-Chrome,
  Scroll-Edge-Effekte an den Listenkanten, `buttonStyle(.glass)`,
  `glassEffectID`-Morphing — und dokumentierte GlassGroup-Regeln:
  beschriftetes Chrome steht standalone (CI-bewiesen).
- Die Hintergrund-Aurora drosselt sich bei „Bewegung reduzieren", im
  App-Hintergrund und im Stromsparmodus selbst.

### 🧠 Apple Intelligence (W4 — on-device, opt-in)

- Drei Formulier-Hilfen über FoundationModels, alle hinter Consent-Gate:
  **Briefanfang-Werkstatt** (drei Töne: Zärtlich/Verspielt/Tief),
  **„Sag es sanft"** (Chat-Entwurf behutsamer, Original bleibt bis zur
  Übernahme) und **„Gemeinsamer Funke"** (Anschlussfrage aus beiden
  Antworten nach dem Tagesfrage-Reveal).
- Ehrliche Verfügbarkeits-Gründe in den Einstellungen (Gerät ungeeignet /
  ausgeschaltet / Modell lädt); nichts verlässt das Gerät, gesendet wird
  nie von allein.

### 🎲 Spiele & Game-Feel (W6)

- **Spieltische** ab 760-pt-Panes: 4 Gewinnt, Kniffel, Bingo, Montagsmaler —
  Schiffe versenken als Duelltisch mit beiden Flotten.
- **Eingabe-Lease + Zuschauer-Modus** über die eigenen Geräte: genau ein
  Gerät hält den Zug (`409 game_lease_held`), Übernahme per
  `POST /api/games/:id/takeover`; Commit-Reveal bleibt fair, kein Gerät
  sieht fremde Geheimnisse.
- **DelightRules-Zeremonien-Budget** mit eigenem Sieg-Motiv —
  `celebrate(.epic)`-Stellen von 9 auf 4 gesenkt (Ratchet eingerastet).
- **This-or-That-Couch-Modus** (W7): ein Handy, geheime Wahl, Weitergeben-
  Zeremonie.

### 🌍 Sprache (W7)

- **Chat-Übersetzung on-device** (Apple-Translation-Framework), unter dem
  Original mit „übersetzt"-Label; keine Cloud.
- **Voice-Transkripte on-device** (SpeechAnalyzer) mit lokalem Cache;
  fehlende Sprachpakete werden ehrlich gemeldet statt geraten.

### 🚪 Ankommen (W7)

- **Onboarding-Wegweiser** mit drei Schritten (Server → Koppeln → Loslegen).
- **Demo-Modus „Erst mal ansehen"**: Beispiel-Paar ohne Server, klarer
  Ausstieg als dauerhaft sichtbares Badge, verschwindet spurlos.
- **Kopplungs-Zeremonie**: die beiden Partnerfarben verschmelzen — auch beim
  Geräte-Link.

### ✅ Qualität & Lockstep

- Release-Lockstep: `project.yml` 12.0.0/Build 50, Server-`package.json`
  12.0.0 (Echo in `GET /api/health`), `release_v54`-Test nachgezogen,
  PATCHNOTES DE+EN, Handbuch/Manual 12.0.0 samt neuer Kapitel (iPad,
  Geräte, Apple Intelligence, Übersetzung/Transkripte, Demo-Modus),
  „Unsere Reise"-Kapitel 12.0 + What's-New-Karten, `docs/API.md` auf
  v12.0.0.
- Suites grün: Server-`node:test` inkl. Multi-Device-/Lease-/Release-Tests,
  Swift-Logic-Tests inkl. L10n-Vollständigkeit DE/EN, Charter-Ratchet ohne
  Anstieg (version_graffiti bleibt 0).

## [4.0.0] — 2026-08-10

4.0 ist bewusst eine Coherence-/Security-Welle, kein neues Feature-Versprechen.
Bestehende Funktionen werden gegen Fälschung, Netzabbrüche und unsichere
Transporte gehärtet.

### 🔐 Server-Autorität & Transport

- **Alle 16 Spieltypen server-authoritative**: Create-Payloads werden
  normalisiert; Moves auf Actor, Turn, Phase, Runde, Wertebereich und Duplikate
  geprüft; objektive Ergebnisse ausschließlich aus akzeptierten Server-Moves
  berechnet. Subjektive Urteile bleiben explizit autorisierte Aktionen.
- **Commit-Reveal gehärtet**: falsche Reveals werden verworfen statt als
  `verified:false` gespeichert. Battleship prüft Flotten, Salven-Reports und
  Sieger nach beiden Reveals; freie Client-`result`-Bodies werden ignoriert.
- **Legacy-Game-Migration**: offene Altpartien werden vollständig durch die
  aktuellen Regeln replayt. Unbekannte/unglaubwürdige Historien werden beendet
  und als `rules_migration` invalidiert; es werden keine unbekannten Moves
  übersprungen. Alte beendete Client-Ergebnisse bleiben als `legacy-client`
  gekennzeichnet.
- **Quoten**: begrenzte Couple-Erstellung/-Beitritte, Game-Creates/-Moves,
  maximal offene Spiele und Moves pro Partie; Rate-Limiter und Logs sind
  speicher-/größenbegrenzt, Bearer und Query-Secrets werden redigiert.
- **HTTPS/WSS standardmäßig**: Klartext nur bei explizitem
  `ALLOW_HTTP_PRIVATE_LAN=1` aus privatem LAN. Proxy-HTTPS wird nur mit
  `TRUST_PROXY=1` akzeptiert; ATS hat keine globalen Arbitrary-Load-Ausnahmen.
- **Geräte-Sessions**: Bearer liegen gehasht im Server-Store und im iOS
  Keychain/App-Group-Zugriff, besitzen Ablaufzeit, Rotation und Widerruf.
  Query-Tokens sind für REST, Medien, Widgets und WebSockets entfernt.

### 🛟 Persistenz, Widgets & Bedienbarkeit

- **Offline-Outbox**: Chattexte werden vor dem Sendeversuch atomar und
  paar-/servergebunden gespeichert; `clientMessageId` macht verlorene
  Antworten und Wiederholungen idempotent.
- **Cold Cache**: renderbarer Couple-/Event-/Daily-/Stats-/Level-Kernzustand
  überlebt Kaltstarts und bleibt pro Serverprofil begrenzt.
- **Widget-Snapshot** liefert zusätzlich Energie, aktives Ziel und
  Beziehungs-Level; Needs zählen im App-Open-Digest. Feiern laufen über eine
  FIFO-Queue, Kapseln aktualisieren am Unlock-Zeitpunkt.
- **Accessibility**: höhere Textkontraste, 44-pt-Minimalziele und ergänzte
  VoiceOver-Labels an kritischen Controls.
- **Portable Backups** sind `.sooodreamy`-Dateien mit AES-GCM und
  PBKDF2-HMAC-SHA256; Sitzungstokens werden nie exportiert und die UI benennt
  Passphrase-/Entschlüsselungsrisiken klar.

### 🔔 Push-Gate & Qualität

- **Killed-app Push vorbereitet**: pro authentifiziertem Gerät registrierte,
  widerrufbare APNs-Tokens, lokalisierte datensparsame Payloads und ein
  HTTP/2-APNs-Provider. Echte Zustellung bleibt ehrlich extern gegated durch
  Push-fähiges Apple-Provisioning und serverseitige `.p8`-Credentials;
  andernfalls meldet die API `deliveryAvailable:false`.
- **Tests**: 225/225 Node-E2E-/Security-/Adversarial-/Migrations-Tests grün.
  Swift-Pure-Logic-Tests für Outbox, Cold Cache und FIFO sind ergänzt; in der
  Linux-VM ohne Swift-Toolchain wurde weder deren Lauf noch eine iOS-UI-Abnahme
  behauptet.

## [3.0.0] — 2026-08-08

Das 3.0-Release „Rituale, Spiele & Delight": drei parallele Feature-Wellen —
Beziehungs-Rituale (A), eine Spiele-Offensive (B) und die neue
Gamification- & Plattform-Schicht (C).

### 💞 Rituale & Beziehung

- **„Wie war dein Tag?"-Audio-Check-in**: beide nehmen bis zu 60 s auf, die
  Enthüllung kommt erst, wenn BEIDE Memos da sind (Anti-Spoiler serverseitig
  erzwungen), 🔥-Streak, Verlauf vergangener Abende, Dashboard-Karte.
- **Zeitkapsel-Briefe**: Brief + optionales Foto versiegeln bis `unlockAt`;
  der Server gibt den Inhalt erst danach und nur an den Empfänger heraus;
  Öffnungs-Zeremonie + Kapsel-Archiv.
- **Bedürfnis-Knopf**: „Ich brauche gerade…" (Raum 🌿 / Zuspruch 🫂 /
  Ablenkung 🎈 / Nähe 💞 / Zuhören 👂) mit 1 Tap; Partner antwortet
  „Bin für dich da 🤍"; Verlauf + `needsForMe`-Bucket im App-Open-Digest.
- **Gemeinsame Ziele & Sparziele**: Zielwert/Einheit/Datum, beide buchen
  Fortschritt (auch Korrekturen), Meilenstein-Konfetti bei 25/50/75/100 %
  auf beiden Handys, Top-Ziel im Widget-Snapshot.
- **„Unsere Woche"**: 7-Tage-Board mit Verfügbarkeits-Chips (Frei/Voll/
  Telefonieren/Date!), Überschneidungs-Funkeln, ein­malige + wöchentlich
  wiederkehrende Slots mit Uhrzeit, Erinnerungs-Banner am Tag selbst.
- **Energie-Ampel**: 🟢/🟡/🔴 nach Feierabend (12-h-TTL wie Now-Playing),
  Partner-Ampel in Dashboard + Widget-Snapshot.
- **„Unser Monat"-Magazin**: deterministisch aggregierte, blätterbare
  Monats-Ausgabe (Cover, Top-5-Momente, Zitat des Monats, Song des Monats,
  12-Zahlen-Spread) + Archiv + beidseitige Lese-Quittung.
- **Meilenstein-Event-API** (`server/src/events.js`): zentrales App-Event-Log
  (WS `app_event` + `GET /api/app-events`) als Schnittstelle für das
  Level-/Badge-System.

### 🎮 Spiele & Aktivitäten

- **Spiele-Infrastruktur v3.0**: parallele Sessions (ein neues Spiel beendet
  nur laufende Partien DESSELBEN Typs), `GET /api/games/open` +
  `/api/games/:id`, „Du bist dran!"-Bucket im Inbox-Digest, Server-Seed im
  Payload (kein Client wählt seine eigene Mischung), Commit-Reveal-
  Verifikation im Relay (`verified`-Flag, SHA-256 bit-identisch Swift/Node).
- **Schiffe versenken** 🚢: 8×8, Flotte 4/3/3/2, 2-Schuss-Salven, versiegelte
  Flotten (Commit-Reveal) mit kryptografischem Fair-Play-Beweis am Ende,
  Ergebnis-Grid in den Chat teilbar.
- **Montagsmaler** 🎨: Live-Zeichnen über die Canvas-Pipeline, Rate-Timer mit
  Server-Zeitanker, Wortlisten DE/EN (je 120), Rollentausch pro Runde.
- **Kniffel-Liebesedition** 🎲: deterministische Seed-Würfel (voll
  async-tauglich), Halten + 3 Würfe, 13 Kategorien + Bonus, Liebes-Punkteblock
  mit Potenzial-Vorschau.
- **Film-Roulette** 🍿: beide swipen denselben Seed-Stapel (60 kuratierte
  Filme + bis zu 5 eigene Titel), Match-Overlay 💞, `movie_match`-App-Event
  als Filmabend-Hook für den Wochenplan.
- **Stadt-Land-Fluss Paar-Edition** 🗺️: Anti-Spoiler-Commit (Reveal erst wenn
  beide versiegelt haben), gegenseitiges Bewerten mit Auto-Buchstaben-Check,
  20/10/5-Punkte, eigene Kategorien, „Stop!"-Countdown mit Auto-Abgabe.
- **Zwei Wahrheiten, eine Lüge** 🤥: Lügen-Index wird MIT den Aussagen
  SHA-256-versiegelt (beweisbar nicht nachträglich tauschbar), Rollentausch,
  Auflösungs-Overlays.
- **Paar-Tagesquests** ⚔️: 3 Mini-Missionen täglich (deterministisch aus
  `coupleId + dateKey`, 48 Quests DE/EN), geteilte Häkchen (first tap wins),
  🔥-Streak mit Schonfrist, `quest_done`-App-Event pro Haken (XP-Hook).
- **Turnier-Modus & Saison-Trophäen** 🥇: Monats-Saison über ALLE Spiele
  (3 Punkte Sieg / 1 Remis, deterministisch aus `GET /api/games` abgeleitet),
  Saison-Ende-Zeremonie, Trophäen-Regal mit Gold-, Geteilt- und Koop-Trophäen
  (Marathon-Paar 15+ Partien, Entdecker-Duo 6+ Spielarten).
- **Replay & Zuschauer-Modus** 🎬: jede beendete Partie als Film (Züge in
  Originalreihenfolge, Async-Pausen im Zeitraffer, Play/Pause/Scrubber/1-2-4×,
  Wende-Moment ⭐️ markiert), Recap in den Chat teilbar; offene Partien live
  vom Zweitgerät beobachten (read-only).

### ✨ Level, Delight & Plattform

- **Delight-Engine**: zentrale Mikro-Feier-Schicht (Partikel + Haptik +
  prozeduraler Sound) in 3 Intensitäten — `Delight.celebrate(.small/.medium/
  .epic)`, ein Overlay in RootView, von allen 3.0-Features genutzt.
- **Beziehungs-Level**: XP deterministisch & rückwirkend fair aus
  Bestandsdaten aggregiert (Nachrichten, Berührungen, Spiele, beidseitige
  Tagesfragen-/Check-in-Tage, App-Events, …); Level-Kurve
  T(n) = 100·(n−1)·n/2, 10 Titel („Frisch verliebt" → „Legendäres Duo");
  Level-Up-Zeremonie auf beiden Handys, Dashboard-Ring, Level-Feld im
  Widget-Snapshot; Legacy-Paare adoptieren ihr verdientes Level still
  (kein Zeremonien-Spam beim Update).
- **Abzeichen-Sammlung**: 20 prozedural gezeichnete Glas-Medaillen (keine
  Binärdateien), davon 4 geheime („???" bis zur Freischaltung); Trophäen-Regal
  mit Fortschritt, Verleihungs-Zeremonie live; Unlocks sind persistiert und
  re-locken nie (gerissene Serie, gelöschte Fotos).
- **App-Icon-Geschenke**: 9 prozedural gerenderte Icon-Varianten (Classic,
  Sunset, Midnight, Mint, Rose, Ocean, Gold, Lavender, Blossom) über das
  parametrisierte GenerateIcon-Skript (CI rendert alle); Partner schenkt ein
  Icon → Auspack-Zeremonie beim nächsten App-Öffnen; Alternate Icons via
  `project.yml`.
- **iOS-18-Controls**: „Herzklopfen senden" + „Bedürfnis-Knopf öffnen" für
  Kontrollzentrum, Lock Screen und Action Button (`ControlWidget` mit
  `#available(iOS 18)`-Guard, auf iOS 17 sauber unsichtbar).
- **Haptik-Duett + Live-Herzschlag**: dasselbe Haptik-Muster startet auf
  beiden iPhones im selben Augenblick (NTP-light-Clock-Sync über
  WS-`pong`-Echo, 2 s Server-Vorlauf); Live-Modus streamt Taps in Echtzeit
  aufs 3D-Herz des Partners (`heartbeat_tap`-Relay).
- **Date-Night-Live-Activity**: Abend-Countdown im Lock Screen / in der
  Dynamic Island mit Phasen Vorfreude → Los! → Ausklang, Phasenwechsel per
  `LiveActivityIntent`-Button, beidseitig synchron.
- **Saison-Themes + Jahreszeiten-Partikel**: Blüten 🌸 / Glühwürmchen ✨ /
  Blätter 🍁 / Schnee ❄️ überm Dashboard — automatisch nach Datum (meteoro-
  logische Jahreszeiten) oder manuell, abschaltbar.
- **Polaroid-Foto-Widgets**: Rahmen-Stile Polaroid / Filmstreifen / Scrapbook
  im Widget-Studio + pro Widget via AppIntent, rein SwiftUI-gezeichnet.
- **Onboarding-Quest „Erste Woche"**: 7 geführte Mini-Aufgaben für frische
  Paare (Berührung, Nachricht, Tagesfrage zu zweit, Foto, Leinwand, Check-in
  zu zweit, erstes Spiel) — Finale = +150 XP, Abzeichen + große Zeremonie.

### ✅ Qualität & Infrastruktur

- Server-E2E-Suite 125 → **191 Tests** (Rituale, Spiele-Relay + Konventionen,
  Level/Badges/Quest, Icon-Gift/Duett/Date-Night), grün.
- Swift-Logic-Tests 77 → **161 Tests** auf Linux (Reducer aller 7 neuen
  Spiele, Commit-Reveal, Saison/Replay, LevelMath, SeasonLogic,
  L10n-Vollständigkeits-Scan DE/EN).
- `docs/API.md` vollständig auf v3.0: Rituale-, Spiele-Konventions- und
  Level-&-Plattform-Abschnitte, alle WS-Frames dokumentiert.
- CI rendert alle 9 App-Icon-Varianten prozedural; unsigniertes IPA weiterhin
  als Artefakt + rollendes Release nach jedem Push.

## [2.0.0] — 2026-08-08

Das große 2.0-Release: Widgets & Live Activities komplett überarbeitet, neues
Design-System, Videos, E2E-verschlüsselter Vault, eigener Haptik-Composer,
drei neue Live-Spiele und sechs neue Couple-Features.

### 🧩 Widgets 2.0

- Alle 8 Widgets unterstützen jetzt **alle Größen**: systemSmall/Medium/Large
  (Days Together zusätzlich ExtraLarge auf iPad) + accessoryCircular/
  Rectangular/Inline für Lock Screen & StandBy.
- **Animierte Inhalte**: tickende Countdowns über `Text(timerInterval:)`,
  automatisch weiterlaufende Tages-/Fortschrittsanzeigen über vordatierte
  Timeline-Einträge — auch ganz ohne App-Refresh.
- **Interaktive Widgets** (iOS 17 AppIntents): „Herzklopfen senden" 💓 direkt
  vom Home Screen (Send-Love-Widget + Buttons im Mood-Widget) mit
  Erfolgs-Feedback im Widget selbst.
- **Konfigurierbar pro Widget** via `AppIntentConfiguration`: Theme
  (Night/Sunset/Ocean/Blush/Mono/Foto), Layout-Varianten, Datenquelle
  (z. B. welcher Countdown, welches Album).
- Datenfluss repariert: App-Group-Snapshot wird bei jedem relevanten Event
  aktualisiert, `WidgetCenter`-Reloads gezielt statt pauschal; Foto-Widget
  cached ins App-Group-Verzeichnis und übersteht Netzfehler; Deep-Links auf
  allen Widgets (inkl. Lock Screen).

### 🎨 Widget-Studio (Einstellungen → Widget-Studio)

- Live-Vorschau aller Widgets in echten Proportionen, Theme-/Layout-/Foto-/
  Countdown-Auswahl mit sofortigem Preview-Update.
- Einstellungen landen im App-Group-Storage, Widgets lesen sie direkt;
  jede Änderung triggert einen `WidgetCenter`-Reload.

### ⚡ Live Activities 2.0

- Lifecycle sauber: Start/Update/Ende mit `staleDate`, sinnvolle Dismissal-
  Policy, kein Activity-Leak mehr bei App-Neustarts.
- Dynamic-Island-Varianten (compact/minimal/expanded) poliert; animierte
  Timer, Fortschrittsbalken und Herz-Puls.
- **Konfigurierbar** über Einstellungen → Live Activity: Stil, Farbschema und
  angezeigte Elemente wandern in den ContentState.
- Anwendungsfälle: Countdown zu Momenten, „Couple Pulse" (Mood/Online/letzter
  Touch/Streak), laufende Spiele-Sessions.

### 🔄 Background Refresh

- `BGAppRefreshTask` (`app.sooodreamy.refresh`) holt periodisch Partner-Status,
  Momente und Tagesfrage und aktualisiert Snapshot + Widgets.
- Ehrliche Doku der iOS-Limits (README) — das System entscheidet, wann Tasks
  laufen; die App verlässt sich nie darauf.

### 💎 Liquid Glass Design 2.0

- Neues Design-System: geschichtete Glas-Karten (ultraThinMaterial + eigene
  Refraktions-/Specular-Gradienten, weiche Innenschatten, Glanzkanten),
  animierte Hintergrund-Blobs, konsistente Radien, Dark/Light poliert.
- Alle Screens migriert; iOS-26-Glass-APIs werden per `#available` genutzt,
  wenn das Build-SDK sie kennt (Basis bleibt iOS 17).
- **App-Icon** neu: mehrschichtiges Glas-Herz (Hintergrund-Verlauf, Refraktions-
  Highlights, Glanz-Layer, Partikel) — weiterhin 100 % prozedural gerendert.

### 🎬 Videos

- Galerie kann Videos aufnehmen/hochladen: PhotosPicker (`.videos`),
  Client-Transcoding via `AVAssetExportSession` (720p/1080p je nach Länge),
  Thumbnail-Generierung, Vollbild-Player (AVPlayer) mit Sichern in die
  Fotobibliothek.
- Server: Upload/Streaming mit **Range-Requests**, Limits & Speicherverwaltung,
  eigene E2E-Tests.

### ☁️ iCloud

- CloudKit (private DB) sichert Server-Verbindungen + App-Einstellungen;
  JSON-Datei-Export (inkl. Momente/Bucket/Songs/Coupons) nach iCloud Drive
  oder übers Teilen-Menü.
- Laufzeit-Feature-Detection: ohne iCloud-Entitlements (typisches Sideload-
  Signing) blendet die App die CloudKit-Teile aus statt still zu scheitern.

### 🌶️ Spicy Vault

- Separater Bereich mit eigener PIN + Face ID (unabhängig von der App-Sperre),
  Fotos/Videos/Notizen.
- **Ende-zu-Ende verschlüsselt**: PBKDF2-SHA256 (210k Iterationen) →
  AES-GCM (CryptoKit); der Server speichert nur Ciphertext-Blobs, der
  Schlüssel verlässt nie eure Geräte.
- Blur-Vorschau bis zur Entsperrung, Panik-Verstecken per Schütteln, keine
  Vault-Inhalte in Widgets/Snapshots/Backups.

### 🎛️ Haptik-Composer

- Aufnahme-Pad: Tap-Rhythmus mit Druckdauer = Intensität, sofort fühlbar.
- Muster benennen, in gemeinsamer Bibliothek verwalten, an den Partner senden
  (Server-Relay + WebSocket); Empfang als Vollbild-Moment mit Puls-Ringen.
- Als kompakte Event-Timeline gespeichert, on-device ins **AHAP**-Format
  übersetzt; 6 Presets (Herzschlag, Schmetterlinge, Regen, SOS-Kuss,
  Meeresrauschen, Funkeln); Verlauf der letzten 100 Vibes.

### 🔊 Sound-Engine 2.0

- Deutlich hochwertigere Synthese: Stereo-Voices mit Detune, ADSR-Hüllkurven,
  inharmonische Glocken-Spektren, gefiltertes Rauschen, Echo mit Soft-Knee-
  Sättigung — weiterhin ohne gebündelte Audio-Dateien (Begründung in
  `docs/CREDITS.md`).
- 7 neue Sounds; Lautstärke **pro Kategorie** (Momente/Chat/Spiele/Interface)
  in den Einstellungen regelbar.

### 🎮 Drei neue Live-Spiele

- **4 Gewinnt** — klassisches 7×6-Brett, Gewinner-Reihe leuchtet.
- **Foto-Memory** — Paare finden mit euren eigenen Galerie-Fotos; Treffer =
  Punkt + nochmal dran.
- **Liebes-Quiz-Duell** — gleiche Frage auf beiden Handys, die schnellste
  richtige Antwort kassiert doppelt (Buzzer-Scoring über Server-Reihenfolge).
- Alle deterministisch über das Server-Move-Relay (beide Handys leiten den
  identischen Spielstand aus derselben Zugliste ab) + Logic-Tests.

### 💞 Sechs neue Couple-Features

- **Morgen-/Gutenacht-Check-in** ☀️🌙 — ein Tap pro Tageszeit, gemeinsame
  🔥-Serie für Tage, an denen beide eingecheckt haben.
- **Umarmungs-Warteschlange** 🫂 — Umarmung queuen, während der Schatz schläft;
  wird wie ein Geschenk geöffnet, der Absender bekommt Bescheid.
- **Gemeinsame Listen** 📝 — Einkauf, Filme & Co: anlegen, abhaken, umbenennen,
  live auf beiden Handys.
- **Foto des Tages** 📷 — jeder kürt täglich ein Galerie-Foto; zusammen wird
  daraus euer Bilder-Tagebuch.
- **„Gerade am Hören"** 🎧 — Musik-Status (Song + Artist) am Partner-Profil,
  verfällt automatisch nach 60 Minuten.
- **Unser Jahr** ✨ — Jahresrückblick mit allen Zahlen (Fotos, Nachrichten,
  Berührungen, Spiele, Serien …), teilbar in den Chat.

### 📚 Content-Ausbau

- 229 Tagesfragen (+20), 160 Wahrheit-oder-Pflicht-Karten (+20),
  142 Date-Ideen (+15), Wordle: 535 DE / 487 EN Wörter (+21/+26).

### 🖥 Server 2.0

- Neue Endpunkt-Familien: Videos, Vault-Blobs, Haptik-Muster, Check-ins,
  Listen, Umarmungen, Foto des Tages, Now Playing, Jahresrückblick; neue
  Spiel-Typen `connectfour`/`photomemory`/`quizduel`.
- Testsuite von 38 auf **125 E2E-Tests** gewachsen; iOS-Logic-Tests auf 77.

## [1.x] — 2026-08-03 … 2026-08-04

22 Iterationen von der leeren Repo bis v1.5.4 — Kern-App (Pairing, Chat mit
Briefen/Voice/Reaktionen, Berührungen mit Haptik, 3D-Herz, Tagesfrage mit
Streak, Liebes-Wordle + Duell, Quiz/Choice-Spiele, Galerie mit Alben &
Favoriten, Kritzel-Canvas, Bucket List, Momente mit Live Activity, Coupons,
Soundtrack, Love-Stats, Widgets, App-Sperre, Multi-Server) und Server v1.0 →
v1.8. Details: Build-Log in `UserFeedback.md`.
