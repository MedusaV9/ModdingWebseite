# NEUBAU_ALMANACH.md — Dossier „Der lebendige Almanach"

**Status: Wettbewerbs-Einreichung (Neubau-Konzept, eines von drei Dossiers).** Dieses Dokument
ändert keinen Code. Es beschreibt den NEUBAU der Informationsarchitektur, der
Seiten-Kompositionen und der Code-Ordner — auf dem unveränderten Fundament der Art Direction
„Papier & Licht" (`STYLE_DECISION.md` §3, `MIGRATION_PAPIER.md`, Nacht-first-Korrektur
`MIGRATION_DUNKEL.md`) und der Charta (`SoooDreamy/DESIGN.md`, 15 Gebote, Ratchets, Budgets).
Gelesen und eingerechnet: `RootView.swift` (Ist-Shell, native TabView, Heute-Zettel-Accessory),
alle Feature-Wurzeln unter `Features/`, `Content/`-Kataloge, `ios/Package.swift`
(explizite Logic-Quellenliste), `project.yml` (Glob-Sources), `UITests/SoooDreamyUITests.swift`
(gescriptete test01–test05-Reise), `tools/charter_baseline.json` (Ist-Zähler).

**Die eine Zeile:** Die App hört auf, eine App mit Features zu sein, und wird das BUCH, das
ein Paar über sich selbst schreibt — jeder Tag ein Blatt, jede Handlung ein Eintrag, jeder
Monat ein gebundener Band. Nichts am Design ändert sich; alles am Aufbau.

---

## 1. Leitidee: Der Almanach, der sich selbst schreibt

Warum sieht die heutige App trotz preiswürdigem Material „generisch" aus? Weil ihr AUFBAU der
Aufbau jeder Produktivitäts-App ist: ein Dashboard mit Karten-Stapel, ein Chat, ein
Spiele-Grid, ein Hub mit 18 Kacheln, eine Settings-Liste. Das Papier ist einzigartig — aber
die Karten darauf sind austauschbare Container: „hier Karte, dort Karte", in einer
Reihenfolge, die eine Priority-Engine bestimmt und kein Mensch erzählt. Ein Screenshot des
Dashboards ist unverwechselbar SoooDreamy; ein Diagramm des Dashboards ist jede App.

Der Almanach dreht das Verhältnis um. Ein Almanach ist die älteste Form des „lebendigen
Dokuments": Kalendarium, Mondstände, Bauernregeln, Platz für eigene Einträge — ein Buch, das
beim Kauf halb leer ist und dessen Wert der Besitzer hineinschreibt. Genau das IST diese App
faktisch schon: ein Archiv aus Briefen (Chat, Liebesbriefe), Antworten (Tagesfrage), Fotos
(Galerie, Polaroids), Partien (Spielstände), Versprechen (Ziele, Kapseln, Bucket List). Der
Neubau macht aus diesem Faktum die STRUKTUR:

- **Jeder Tag ist ein Blatt.** Es liegt morgens fast leer im Lampenlicht — Datum, Mondstand,
  die gedruckte Tagesfrage — und füllt sich über den Tag aus dem Tun des Paares: Antworten
  erscheinen als Tinte, Grüße als Marginalien, Partien als Randnotizen, die Abendstimme als
  Schlusszeile. Der Nutzer SIEHT den Schreiber arbeiten: Was ihr tut, steht danach im Buch.
- **Die Tabs sind Buchteile,** keine Feature-Silos: das heutige Blatt, der Faden (das
  fortlaufende Gesprächsband), das Spielbuch, das Archiv der gebundenen Jahrgänge, der
  Anhang mit den Werkzeugen. Jeder Ort in der App beantwortet die Frage „wo im Buch bin ich?"
  — nicht „welches Feature nutze ich?".
- **Nichts ist statisch-generisch,** weil jede Fläche entweder beschriebenes Papier ist
  (vom Paar gefüllt) oder ein Werkzeug, das ehrlich Werkzeug sein darf (Anhang, still, ohne
  Artefakte — exakt Charta §3.6 „Settings bleiben still").

**Anschluss ans Kino:** Das First-Launch-Kino (`STYLE_DECISION.md` §3.9) erzählt in sieben
Szenen bereits Buch-Motive — Umschlag mit Poststempel „TAG 1", Siegelbruch und entfalteter
Brief, zwei Tintenfässer, die sich zum Blend mischen, ein leeres Polaroid, das auf seine
erste Erinnerung wartet. Das heutige Kino endet aber in einem Dashboard, das diese Motive nur
zitiert. Der Almanach löst das Versprechen ein: Szene 7 legt das Papier nicht „in den
Home-Screen", sondern schlägt DIE ERSTE SEITE DES BUCHES auf — und die App danach ist
dasselbe Buch, Tag für Tag weitergeschrieben. Brief → Tinte → Polaroid sind dann keine
Intro-Metaphern mehr, sondern die drei Eintragsarten des Alltags.

**Warum das die Generik tötet:** Generisch ist, was für beliebige zwei Menschen identisch
aussieht (Noble-Test Frage 10). Ein Karten-Dashboard sieht für jedes Paar gleich aus, solange
beide „noch nichts gemacht haben". Ein Blatt, das sich aus dem Tun schreibt, ist ab dem
zweiten Eintrag ein Unikat — und sein LEERER Zustand ist kein Loch, sondern eine gedruckte
Einladung („Die erste Zeile gehört dir", Gebot 8: der leere Zustand lädt mit Verb und
Button). Die App wird vom Anbieter von Funktionen zum Zeugen einer Biografie — und Gebot 15
(„Zahlen sind Biografie, kein Spielstand") bekommt seine natürliche Bühne: „TAG 137" ist
keine Streak-Zahl, sondern eine Seitennummer.

---

## 2. IA-Karte: Die fünf Buchteile

### 2.1 Übersicht

| # | Buchteil (DE) | EN | SF Symbol | AppTab-Case (bleibt) | a11y-ID (bleibt) | Zweck |
|---|---|---|---|---|---|---|
| I | **Blatt** | Leaf | `book.pages` | `.home` | `tab.home` | Die Doppelseite des heutigen Tages: Ritual-Haupteintrag, Tageschronik, Marginalien-Werkzeuge |
| II | **Faden** | Thread | `scroll` | `.chat` | `tab.chat` | Das fortlaufende Gesprächsband: Zettel, Briefe, Stimmen, Sticker — mit sichtbarem Faden vernäht |
| III | **Spielbuch** | Playbook | `dice` | `.play` | `tab.play` | Spielbrett-Kapitel: offene Partien als aufgeschlagene Seiten, Katalog als Kapitelverzeichnis, Saison als Stempelbogen |
| IV | **Archiv** | Archive | `books.vertical` | `.memories` | `tab.us` | Die gebundenen Jahrgänge (Vergangenes), die versprochenen Seiten (Zukünftiges), das Versiegelte (Tresor) |
| V | **Anhang** | Appendix | `paperclip` | `.settings` | `tab.settings` | Register der Werkzeuge: Paar & Geräte, Erscheinung, Rituale, Sicherung, Werkstatt |

Verbindliche Nativitäts-Entscheide (unverändert aus `RECON_NATIVE_IOS26.md` / Decision §3.7):
echte iOS-26-`TabView` mit `Tab`-Buildern, `.tint(coupleTint.blend)`,
`.tabBarMinimizeBehavior(.onScrollDown)`, `.scrollEdgeEffectStyle(.soft)`; **kein**
`sidebarAdaptable` (Recon §2.7 bleibt bindend), **kein** `Tab(role: .search)`; Suche via
`.searchable` im Faden und im Archiv. Blätter-Gesten sind ZUSATZ: nur dort, wo ohnehin native
Paging-Container arbeiten (`TabView(.page)` im Magazin, `ScrollView.scrollTargetBehavior(.paging)`
im Archiv-Regal) — nie als Ersatz für Push/Pop oder Tab-Wechsel.

**Chrome-Umbenennungen (Konzept, gleiche APIs):**

- Der Heute-Zettel (`tabViewBottomAccessory`) wird das **Lesezeichen-Band**: die Stelle, an
  der das Buch heute aufgeschlagen ist — Partner-Präsenz links, „nächste unbeschriebene
  Zeile" rechts (offene Frage schlägt Streak, wie heute). `.expanded` = Band mit Subline,
  `.inline` = Präsenzpunkt + Kurzstatus. Tap → Blatt.
- Der PulseFan-FAB wird der **Stift**: das Schreibwerkzeug, das über dem Blatt schwebt
  (Chrome-Glas, unverändert rund) — Puls, Notiz, Berührung sind seine drei Striche.
- L10n: die KEYS `tab.home`…`tab.settings` bleiben; nur die WERTE wechseln
  (DE „Blatt · Faden · Spielbuch · Archiv · Anhang", EN „Leaf · Thread · Playbook ·
  Archive · Appendix"). `accessibilityIdentifier` der Tabs bleiben wörtlich bestehen —
  die UITest-Verträge brechen nicht.

### 2.2 Vollständiges Screen-Mapping alt → neu (max. 2 Ebenen unterm Tab)

Ebene 0 = Tab-Wurzel · Ebene 1 = Push/Sheet von der Wurzel · Ebene 2 = Push/Sheet darunter.
Overlays/Zeremonien (RootView-ZStack) zählen nicht als Ebenen. Querverweise (z. B. Blatt-Karte
→ Türchen-Kalender) sind erlaubt; die Tabelle nennt die HEIMAT jedes Screens.

**I. BLATT (heute: Home-Tab)**

| Heute | Neu im Almanach | Ebene | Form |
|---|---|---|---|
| `DashboardView` (Karten-Stapel) | **Blatt-Wurzel**: Kopfzeile · Haupteintrag · Tageschronik · Marginalien · Fußnote (§3.1) | 0 | Scroll-Seite |
| `DashboardHeaderView` (Avatare, Tage, Mood) | **Kopfzeile des Blattes** (Datum, „TAG n"-Stempel, Mondstand, Präsenz-Tinte) | 0 | Zone |
| `DailyQuestionCard` + `RevealCeremonyView` | **Haupteintrag** (gedruckte Frage → meine Tinte → Siegel → Reveal-Zeremonie) | 0 (+Overlay) | Zone + Overlay |
| `CheckinCard` (Morgen/Abend) | **Erste/letzte Zeile des Blattes** (Morgengruß-, Abendzeilen-Eintrag) | 0 | Zone |
| `FirstMomentCard`, `QuestCard` | **Vorgedruckte erste Zeilen** (Neu-Paar-Dramaturgie im Haupteintrag-Slot) | 0 | Zone |
| `MissedInboxCard` („Während du weg warst") | **„Inzwischen geschrieben"-Absatz** oben auf der Chronik | 0 | Zone |
| `TouchGridCard` (Grüße-Grid) | **Federkasten** (Sheet vom Stift & von der Marginalie) | 1 | Sheet |
| `PulseFan` | **Der Stift** (FAB, Chrome) | — | Chrome |
| `ZeitpostSheet` (Zeitpost) | **Zeitpost** — „eine Zeile für später aufgeben" | 1 | Sheet |
| `PostJournalSheet` (Posteingang der Zärtlichkeiten) | **Postbuch** (30-Tage-Chronologie; speist die Chronik) | 1 | Sheet |
| `HapticStudioView` | **Haptik-Studio** (Marginalien-Werkzeug) | 1 | Sheet |
| `DuetSheet` (Haptik-Duett) | **Duett** | 1 | Sheet |
| `HugQueueCard`/`HugQueueView` | **Umarmungs-Warteschlange** (Marginalie + Sheet) | 1 | Sheet |
| `DateNightCard`/`DateNightView` | **Verabredung** (Marginalie + Plan-Sheet, Live Activity bleibt) | 1 | Sheet |
| `MoodPickerSheet` | **Stimmungs-Tinte** | 1 | Sheet |
| `StreakCalendarView` | **Kalendarium** (Monatsraster der beschriebenen Tage) | 1 | Sheet |
| `EnergyCard` (Energie-Akku) | **Marginalie „Energie"** (Batterie-Form bleibt, wertfrei) | 0 | Zone |
| `NeedsCard` („Ich brauche gerade") + `NeedsHistoryView` | **Marginalie „Ich brauche gerade"** + Verlauf | 0 / 1 | Zone / Push |
| `DaymemoCard`/`DaymemoView` (Abend-Audio) | **Abendstimme** (Schlusszeile des Blattes + Ritualseite) | 0 / 1 | Zone / Push |
| `WeekplanTodayBanner` | **Heute-im-Wochenplan-Zeile** (Chronik-Vordruck) | 0 | Zone |
| `WeekReviewView` (Wochenrückblick) | **Sonntags-Doppelseite** (Blatt bietet sie sonntags an; Ablage im Archiv) | 1 | Push |
| `RepairSupportCard`/`RepairConsiderationView` | **Marginalie „Wieder gut"** + Seite | 0 / 1 | Zone / Push |
| `SeasonCalendarSupportCard` | **Türchen-Marginalie** (Countdown; Heimat des Kalenders: Archiv › Versprochen) | 0 | Zone (Querverweis) |
| `LevelCard` | **Marginalie „Kapitelstand"** (Level als Seitenzahl-Metapher) | 0 | Zone |
| `OnThisDayCard`/`FlashbackCard` | **Fußnote „Vor einem Jahr"** (Mini-Polaroid, EINE Klebeecke) | 0 | Zone |
| `DailySparkCard` (Intelligence-Funke) | **Randbemerkung des Tages** (unter dem Reveal, wie heute) | 0 | Zone |
| `Heart3DView`-Coda | **Schlussvignette** (bleibt die Coda) | 0 | Zone |
| `WhatsNewView` | Anhang › Werkstatt › **„Neu in dieser Auflage"** (Auto-Sheet bleibt beim Start) | (V) | Sheet |
| `TouchReceivedOverlay`, `PostNoteOverlay`, `PulseReceivedOverlay` | **Momente** (RootView-Overlays, unverändert) | — | Overlay |

**II. FADEN (heute: Chat-Tab)**

| Heute | Neu | Ebene | Form |
|---|---|---|---|
| `ChatView` (Zettelwechsel, `.searchable`, Effekte, Tagestrenner) | **Faden-Wurzel**: Band mit Naht, Poststempel-Knoten als Tagestrenner | 0 | Scroll-Band |
| `LetterComposeView` + `LetterSeals` (Liebesbriefe) | **Briefpresse** (versiegelte Briefe, Siegelbruch bleibt DER laute Moment) | 1 | Sheet |
| `LetterWorkshopView` (Sticker-Werkstatt) | **Sticker-Werkstatt** (Mini-Polaroids) | 1 | Sheet |
| `VoiceNotes` (Aufnahme + Wiedergabe) | **Stimmzettel** | 1 | Sheet |
| `PinnedMessages` | **Eingenähte Zeilen** (Toolbar-Knopf, Banner + Sprung) | 1 | Toolbar/Banner |
| Nachricht bearbeiten / Brief weiterleiten | unverändert als Sheets | 1 | Sheet |
| `MessageEffectOverlay`, `ChatTranslation` | unverändert (Overlay / Inline-Funktion) | — | Overlay/Inline |

**III. SPIELBUCH (heute: Spielen-Tab)**

| Heute | Neu | Ebene | Form |
|---|---|---|---|
| `PlayHubView` (kuratierter Hub) | **Spielbuch-Wurzel**: „Aufgeschlagene Partien" (Fächer-Stapel) · Tagesempfehlung (eine Spielkarte) · Kapitelverzeichnis | 0 | Scroll-Seite |
| 26+ Spiele (`GameDestination`: wordle, quiz, thisorthat, wouldyourather, truthordare, questions36, emojiriddle, dateideas, connectfour, photomemory, quizduel, battleship, pictionary, kniffel, movieroulette, stadtlandfluss, twotruths, wordchain, hangman, bingo, wordleduo, rps, story, dame, reversi, kaesekaestchen, gomoku, mancala, memoryduo) | **Kapitel-Seiten** — Kapitel spiegeln `PlayHubCuration`: „Brett & Duell" · „Wort & Zahl" · „Fragen & Wahrheit" · „Live & Party" · „Abende" (Filmroulette, Date-Ideen) | 1 | Push (NavigationStack, wie heute) |
| `DailyQuestsView` (Tagesaufgaben) | **Tagesaufgaben-Vordruck** (Spielbuch-Wurzel-Zeile + Seite) | 1 | Push |
| Tutorials (`GameIntroCatalog`) | **Spielregel-Beiblatt** je Kapitel | 2 | Push/Sheet |
| `TournamentView` (Saison/Turnier) | **Saison-Stempelbogen** (Monats-Turnier) | 1 | Push |
| `GamesRecordView` (Spielstände) | **Spielstands-Register** (Druckwerk, `Typo.number`) | 1 | Push |
| `ReplayView` (Replays/Zuschauen) | **Nachlese** | 1 | Push |
| `GameTableView`, `BoardDuelKit`, `GamesPaperKit`, `GameEngine`, `GamesCoordinator` | unverändert die Werkbank unter den Kapiteln | — | Infrastruktur |

**IV. ARCHIV (heute: Wir-Tab + verstreute Rituale)**

Die Wurzel trägt drei **Register** (native segmented `Picker` in der Toolbar):
**Gebunden** (Vergangenes) · **Versprochen** (Zukünftiges) · **Versiegelt** (Privates).
`.searchable` durchsucht das Archiv (Journal-Sweep #5 der Recon wird hier eingelöst).

| Heute | Neu (Register › Seite) | Ebene | Form |
|---|---|---|---|
| `MemoriesView` (18-Kachel-Hub / iPad-Split) | **Archiv-Wurzel**: Jahrgangs-Regal + Register-Inhalt | 0 | Scroll/Split |
| `YearReviewView` (Jahresrückblick) | Gebunden › **Jahrgang** (Regal-Band öffnet ihn) | 1 | Push |
| `MagazineView` („Unser Monat") | Gebunden › **Monats-Ausgaben** (blätterbar, `TabView(.page)`) | 1 (Ausgabe: 2) | Push |
| `StoryTimelineView` (Geschichte) | Gebunden › **Unsere Geschichte** | 1 | Push |
| `JournalView` | Gebunden › **Journal** | 1 | Push |
| `GalleryView`/`GalleryPagerView`/`MediaLightbox` | Gebunden › **Album** (+ Lightbox) | 1 / 2 | Push / Cover |
| `VideoGalleryView`/`VideoPlayerScreen` | Gebunden › **Filmspulen** | 1 / 2 | Push / Cover |
| `PotdView` (Foto des Tages) | Gebunden › **Foto des Tages** | 1 | Push |
| `SoundtrackView` | Gebunden › **Soundtrack** | 1 | Push |
| `CanvasView`/`CanvasExportSheet` | Gebunden › **Leinwand** | 1 / 2 | Push / Sheet |
| `LoveStatsView` | Gebunden › **Zahlen unserer Tage** (Biografie-Sprache, Gebot 15) | 1 | Push |
| `BadgeShelfView` (Abzeichen) | Gebunden › **Meilensteine** | 1 | Push |
| PostJournal-HISTORIE (>heute) | Gebunden › **Postbuch** (dieselbe Quelle wie Blatt-Sheet) | 1 | Push |
| `EventsView` (Termine/Countdowns) | Versprochen › **Kommende Tage** | 1 | Push |
| `WeekplanView` (Wochenplan) | Versprochen › **Wochenplan** | 1 | Push |
| `BucketListView` | Versprochen › **Bucket List** | 1 | Push |
| `SharedListsView` (Listen) | Versprochen › **Listen** | 1 | Push |
| `GoalsView` (Ziele & Sparen) | Versprochen › **Ziele & Sparen** | 1 | Push |
| `CouponsView` (Gutscheine) | Versprochen › **Gutscheine** (Coupon-Scallop bleibt) | 1 | Push |
| `CapsulesView` (Kapseln) | Versprochen › **Zeitkapseln** (versiegelt bis Datum) | 1 | Push |
| `SeasonCalendarView` (Türchen-Kalender) | Versprochen › **Türchen-Kalender** | 1 | Push |
| `VaultView`/`VaultItemViewer` (Spicy Vault) | Versiegelt › **Tresor** (eigene PIN, wie heute; erscheint nie in Widgets/Backups) | 1 / 2 | Push / Cover |

**V. ANHANG (heute: Mehr-Tab, eine 1200-Zeilen-Seite + 15 Sheets)**

Die Wurzel wird ein Inhaltsverzeichnis aus fünf **Registern** (je eine Ebene-1-Seite,
`Form`/`.formStyle(.grouped)`, `ScopeBadge` Paar/Gerät bleibt):

| Heute (Sheet/Link in `SettingsView`) | Neu (Register › Eintrag) | Ebene |
|---|---|---|
| ProfileEditSheet, PairingCodeSheet, `DeviceManagerSheet`, `MigrationAssistantView`, RecoverySheet (`RecoveryViews`) | **A · Paar & Geräte** (Profil, Pairing, Multi-Device, Umzug, Wiederherstellung) | 1 (Sheets: 2) |
| `ServerListSheet`, Verbindungstest, `ICloudSheet`, Backup/Export | **B · Verbindung & Sicherung** | 1 (2) |
| `PersonalizationView`, `IconGiftView`, `WidgetStudioView`, `LiveActivitySheet` | **C · Erscheinung** (Paarfarben, Icon-Geschenke, Widgets, Live Activity) | 1 (2) |
| `NotificationSettingsSheet`, `AutomationsGalleryView`, `IntelligenceConsentSheet`, `CustomQuestionsView` (eigene Tagesfragen), App-Sperre (`AppLock`) | **D · Rituale & Schutz** | 1 (2) |
| `DiagnosticsView`, `VersionHistoryView`, `SoundCreditsView`, `HandbookView`, `WhatsNewView`, Kino-Replay (`CinematicIntroView`), AboutSheet, Demo-Modus-Ausgang | **E · Werkstatt** | 1 (2) |

**Außerhalb der Tabs (unverändert verortet):**

| Heute | Neu | Anmerkung |
|---|---|---|
| `OnboardingFlowView`, `CinematicIntroView` + Chapter*, `PairingView`, `PairingCeremonyView`, `QRSupport`, `RecoveryViews` | **Kino** (Phase vor dem Buch; §6) | RootView-Phasen `welcome/pairing` bleiben |
| `DemoBadge` / „Erst mal ansehen" | **Leseprobe** (Demo-Modus = ein bereits beschriebenes Probe-Buch; Badge als Top-Bar bleibt) | `safeAreaBar(edge: .top)` bleibt |
| `TodayAccessoryView` | **Lesezeichen-Band** | gleiche API, §2.1 |
| Widgets (`ios/Widgets/`: DailyQuestion, DaysTogether, Streak, Mood, Photo, Memory, Countdown, SendLove, Canvas, Controls; Live Activities Countdown/CouplePulse/DateNight) | unverändert EIN Zettel pro Widget; inhaltlich künftig „die nächste unbeschriebene Zeile" | Code-Heimat bleibt `ios/Widgets` + `ios/Shared` |
| Deep Links `sooodreamy://reveal`, Chat→Album-Brücke (`pendingGalleryPhotoId`) | `reveal` → Blatt; Brücke → Archiv › Gebunden › Album | Verträge bleiben |
| `LockScreenView`, Toasts, Delight-/Lichtschein-Hosts, Zeremonien | RootView-ZStack unverändert | — |

Damit ist JEDES heutige Feature verortet; nichts entfällt. Die einzige bewusste
Doppel-Heimat: das Postbuch (Blatt-Sheet für „heute/zuletzt", Archiv-Seite für die Historie —
eine Datenquelle, zwei Einstiege).

---

## 3. Blatt-Kompositionen (Bühnenbeschreibungen)

Alle Kompositionen stehen auf den bestehenden Gesetzen: Nacht-first
(Standard = `Papier.nachtkarton`, helles Papier NUR als Hero-Artefakt, `MIGRATION_DUNKEL.md`),
Zwei-Materialien-Gesetz, Artefakt-Budget 3/1/1, `legen`-Stagger 40 ms max. 6, Serif nur auf
Papier, eine `briefbogen`-Karte pro Screen.

### 3.1 BLATT — die Doppelseite, die sich selbst schreibt

**Bühne (iPhone, von oben nach unten):**

1. **Nacht-Zimmer**: `DreamyBackground` (Lampenkegel + Tintenstaub), unverändert.
2. **Kopfzeile** (auf Nacht, kein Papier): links Datumszeile in `Typo.anschrift`
   („SONNTAG · 16. AUGUST"), daneben die **Mondstand-Glyphe** (SF `moonphase.*`, berechnet in
   neuem purem `Content/AlmanachKopfLogic.swift`, LogicTest-gepinnt — ein Almanach führt
   Mondstände); rechts Partner-Präsenz als Tintenpunkt + Name (heutige
   `DashboardHeaderView`-Substanz). Höhe ≈ 64 pt, Abstand `Space.l`.
3. **Das Blatt** — DIE eine helle Papierfläche des Screens (`PaperLevel.briefbogen`,
   `Radius.papier`, Paar-Band 6 pt, Lichtkante oben-links). Es trägt drei Zonen:
   - **Blattkopf**: Poststempel-Artefakt Ø 56 pt mit Prägezeile „TAG 137" (Artefakt 1/3,
     seeded −8°), darunter `Papier.kante`-Hairline.
   - **Haupteintrag** (Zustandsmaschine, s. u.): die gedruckte Tagesfrage (`Typo.title`,
     Rounded = „die App spricht") und darunter die Antwortzeilen in `Typo.brief`/`voice`
     (New York = „von euch geschrieben"), jede mit 4-pt-Tintenkante des Autors
     (`coupleTint.tintePrimary`/`tinteSecondary`).
   - **Tageschronik**: die Einträge des Tages (Datenmodell §3.1.1), jede Zeile = Uhrzeit in
     `Typo.anschrift` + Satz in Rounded (`Typo.label`) + Glyphe (SF Symbol, tintiert in der
     Autor-Tinte). KEINE Artefakte in der Chronik — nur Tinte; das hält das Budget frei.
4. **Marginalien** (nach dem Blatt, auf `nachtkarton`-Zetteln — Werkzeuge des Tages, kein
   Papier): Energie-Akku, „Ich brauche gerade", Heute-im-Wochenplan, Abendstimme,
   Türchen-Countdown, Verabredung, Umarmungs-Warteschlange, Kapitelstand — kuratiert von der
   bestehenden `DashboardPriority` (Budget: höchstens drei sichtbar + ein „Mehr"-Fold, wie
   heute; die Engine bleibt, nur ihre Bühne heißt jetzt Marginalien-Spalte).
5. **Fußnote**: „Vor einem Jahr"-Mini-Polaroid (`Radius.polaroid`, EINE Klebeecke —
   Artefakt 2/3) + Herz-Coda (Schlussvignette, bleibt).

Der **Stift** (PulseFan) schwebt unten rechts (Chrome). Das **Lesezeichen-Band** liegt auf
der Bar. Artefakt-Inventur des Screens: Stempel (1) + Klebeecke (2) + Wachssiegel im
Haupteintrag nur im Zustand „versiegelt" (3) — exakt am Budget, gerissene Kante: 0.

**3.1.1 Zustandsmodell des Schreibers (neu, pur, testbar: `Content/ChronikLogic.swift`)**

Die Chronik ist ein deterministischer Merge existierender Feeds — KEINE neue Server-Route:
Postbuch-Chronologie (`PostJournalEntry`: Berührungen, Pulse, Zeitpost), `dailyEntry`
(Tagesfrage), Check-ins, beendete Partien (`GET /api/games`), Daymemo-Status, Meilensteine
(Monatstag, Level). `ChronikLogic.eintraege(feeds:) -> [ChronikEintrag]` sortiert, dedupliziert
(eine Berührung erscheint NIE doppelt in Haupteintrag UND Chronik), kappt auf 12 Zeilen/Tag
mit „+ n weitere"-Fold. LogicTests pinnen Ordnung, Dedupe und Kappung.

| Aktion des Paares | Chronik-Eintrag (Beispiel-Duktus, Gebot 9) | Erscheinung |
|---|---|---|
| Morgen-Check-in | „7:41 · Du hast den Tag aufgeschlagen." | Tintenschrift-Reveal (s. u.), Haptik `tap` |
| Meine Tagesfrage-Antwort | Antwortzeile im Haupteintrag; Chronik: „9:12 · Deine Antwort liegt im Buch." | Tintenschrift + Siegel legt sich auf Partnerzeile |
| Beide geantwortet → Reveal | Haupteintrag: beide Tinten nebeneinander; „TAG n" prägt sich | Bestehende Reveal-Zeremonie — bleibt DER laute Moment des Tages |
| Gruß/Puls gesendet/empfangen | „14:02 · Ein Kuss ging an Mara." / „…kam von Mara." | `legen` + Glyphe in Autor-Tinte, Haptik `tap` |
| Zeitpost aufgegeben | „15:30 · Eine Sendung liegt beim Postamt." (Inhalt bleibt geheim) | Stempel-Beat aus dem Kino-Manifest (existiert: `PostMomentScore.stamp`) |
| Partie beendet | „18:47 · Kniffel — Mara 287, du 231." | Randnotiz-Stil, `Typo.number` für Zahlen; Sieg: Lichtschein Stufe 1 |
| Abendstimme (beide) | Schlusszeile: „22:10 · Zwei Stimmen zum Tag." | Wellenlinien-Glyphe (`waveform`), Haptik weich |

**Tinte erscheint animiert:** Neuer UI-Baustein `TintenschriftRenderer` (SwiftUI
`TextRenderer`, iOS 26 vorhanden, keine Assets): Glyphen-Opacity 0→1 + y-Versatz 2 pt→0,
Stagger 12 ms/Glyphe, Kurve `Theme.Motion.settle`; davor zeichnet sich die 4-pt-Tintenkante
in 0,2 s von oben. Anti-Kitsch-Regeln (hart): Es schreibt IMMER NUR die neueste Zeile; beim
Wiederbetreten des Screens rendert die Chronik statisch (zuletzt gesehene Eintrag-ID in
`@AppStorage`, pure Entscheidungsfunktion in `ChronikLogic`, getestet). Reduce Motion:
Crossfade. VoiceOver: `AccessibilityNotification.Announcement` mit dem vollen Satz (Gebot 13).
Gebot 14 bleibt unverletzlich: der Zustand mutiert im Frame des Taps, die Tinte ist
nachlaufende Bestätigung, nie Gate.

**Signature-Moment „Der Morgen-Umschlag":** Beim ersten Öffnen eines neuen Tages blättert
das gestrige Blatt einmal um (`blaettern` rückwärts: Rotation um die Führungskante, −0° →
−12° → weg) und legt das heutige, fast leere Blatt frei — Datum und Frage stehen schon
gedruckt da, die erste Zeile wartet. Haptik: zwei weiche Ticks (`HapticPatternKit`,
Papier-Duktus); Klang: das vorhandene leise Papier-Cue der SoundEngine (keine neuen
Binärdateien). Reduce Motion: hartes Standbild-Cross-fade. Exakt 1×/Tag — Budget-fest.

**iPad (regular width): die echte Doppelseite.** Das Blatt wird ein breiter Bogen mit
Mittelfalz (1-pt-`Papier.kante`-Linie + hauchdünner Innenschatten): **Verso (links) = die
Chronik des bisherigen Tages**, **Recto (rechts) = Haupteintrag + Randbemerkung**; die
Marginalien rücken als echte Randspalte (Breite 320 pt, `nachtkarton`) rechts NEBEN das
Papier — Marginalien stehen am Rand, nicht unter dem Text. Compact bleibt die gestapelte
Fassung. Umsetzung im selben `horizontalSizeClass`-Muster wie heute
(`DashboardView`-Zweispalter), kein neues Layout-System.

### 3.2 FADEN — das Gesprächsband

**Bühne:** Das Band ist der bestehende Zettelwechsel (Nachtkarton-Zettel, eigene rechts /
Partner links, 4-pt-Tintenkante) mit ZWEI Neubau-Zügen:

1. **Die Naht:** eine 2-pt-Linie in `coupleTint.tinte` @ 0.35, die in der Gasse zwischen den
   Zetteln vertikal durchläuft und an jedem Zettel kurz unter dessen Tintenkante taucht —
   das Band ist sichtbar EIN fortlaufendes Dokument, kein Stapel Bubbles. Rein dekorativ,
   kein Layout-Beitrag (AX5-sicher), unter Increased Contrast aus. Token
   `FadenNaht` in `UI/` (Breite, Opacity, Tauchtiefe benannt).
2. **Knoten:** die Tagestrenner sind die bestehenden Poststempel-Medaillons — konzeptionell
   die Knoten im Faden; am Knoten beginnt links die Tagesnummer („TAG 136").

Native Bausteine unverändert: `.searchable` (Systemfeld), Eingabeleiste als Chrome-Glas,
`ScrollViewReader`-Sprünge, `.badge` am Tab. Briefe bleiben versiegelte `karton`-Umschläge
(Ebene 1), Sticker Mini-Polaroids, Stimmen Stimmzettel. Eingenähte Zeilen (Pins) als
Toolbar-Knopf mit Banner.

**Signature-Moment „Einfädeln":** Beim Senden legt sich der Zettel (`legen`, existiert) und
die Naht STICHT nach: das Nahtsegment vom vorigen Zettel zum neuen zeichnet sich in 0,25 s
(`settle`). Haptik: `tap` (Senden bleibt leise — laut ist nur der Siegelbruch der Briefe).
Reduce Motion: Naht erscheint ohne Zeichnung. iPad: Band in der Lese-Mittelspalte
(bestehende `contentColumn`-Token), Naht läuft mittig durch.

### 3.3 SPIELBUCH — die Spielbrett-Kapitel

**Bühne (Wurzel):**

1. **Aufgeschlagene Partien** (oben): laufende Partien als Spielkarten-Fächer (2°-Fächerung
   seeded, existierendes Muster) — der Fächer ist die EINE Rotation des Screens. Leerzustand:
   „Schlagt ein Kapitel auf" + Primärknopf zur Tagesempfehlung (Gebot 8).
2. **Tagesempfehlung**: EINE Spielkarte (Kuration `PlayHubCuration`, bleibt) — der Hero-Slot.
3. **Kapitelverzeichnis**: fünf Kapitel als Registerzeilen mit `Typo.anschrift`-Kapitelzeile
   + Punktlinien-Füllung zur Seitenzahl (die Seitenzahl IST die Zahl gespielter Partien des
   Kapitels — Biografie, `Typo.number`): „Brett & Duell", „Wort & Zahl", „Fragen & Wahrheit",
   „Live & Party", „Abende". Ein Kapitel öffnet die Spielliste inline (DisclosureGroup, wie
   heutige collapsed groups) — Spiele bleiben Ebene-1-Pushes im bestehenden
   `NavigationStack(path:)`.
4. **Saisonzeile**: Zettelstreifen mit Monats-Poststempel → Saison-Stempelbogen (Turnier),
   Spielstands-Register, Nachlese, Tagesaufgaben.

Die Spielbretter selbst bleiben, was sie sind: Bretter auf dem Papier-Bogen im Lichtkegel
(GamesPaperKit) — das Buch rahmt, es bremst nie eine Partie (Live-Spiele behalten ihre
eigene Bühne bildschirmfüllend).

**Signature-Moment „Eintrag ins Spielbuch":** Beim Partie-Ende schreibt sich die
Ergebniszeile via `TintenschriftRenderer` unten auf die Kapitelseite („Mara 287 — du 231"),
gleichzeitig entsteht der Chronik-Eintrag auf dem Blatt. Sieg: Lichtschein Stufe 1 hinter der
Zeile; Saison-Meilensteine (Monatssieger) sind die einzigen Stufe-2/`epic`-Kandidaten
(Feier-Budget, Gebot 4: `epic_celebrations` steht auf 1 — so bleibt es). Haptik: ein
`rigid`-Tick pro geschriebener Zeile-Landung.

**iPad:** Verzeichnis links (320 pt), aufgeschlagene Seite rechts — dasselbe handgebaute
Split-Muster, das `MemoriesView` heute fährt (kein `sidebarAdaptable`, Recon §2.7 gilt).

### 3.4 ARCHIV — die gebundenen Jahrgänge

**Bühne (Wurzel):**

1. **Das Regal** (oben): Jahrgänge und Monats-Ausgaben als Buchrücken-Karten in einer
   horizontalen `ScrollView` mit `.scrollTargetBehavior(.paging)` (Blättern als Zusatz auf
   nativer Basis). Rücken = `Papier.karton`-Hochkant-Karte 56 pt breit, Prägezeile
   (Monat/Jahr) über neues UI-Token `BuchrueckenText` (fest −90°, UI-Schicht, KEIN
   Freihand-`rotationEffect` — der Ratchet `raw_rotation_features` bleibt sauber); ab
   `isAccessibilitySize` wird das Regal eine horizontale Liste mit liegenden Titeln
   (AX-Fallback, Gebot 12). Der aktuelle, noch ungebundene Monat liegt als loser
   Blätterstapel rechts neben den Rücken.
2. **Registerwahl**: nativer segmented `Picker` (Toolbar): Gebunden · Versprochen ·
   Versiegelt.
3. **Registerinhalt**: Zeilenliste statt Kachel-Grid — jede Zeile wie ein
   Inhaltsverzeichnis-Eintrag (Titel, Punktlinie, Zählwert als Seitenzahl: „Album ······ 214",
   `Typo.number`), Teaser-Zeile darunter (jüngstes Foto/Song/Coupon — heutige recent strip).
   Versiegelt-Register: Tresorzeile mit Schloss, danach die bestehende PIN-Bühne.
4. `.searchable` über Journal, Geschichte, Alben, Listen (Feld gehört dem System).

**Signature-Moment „Das Binden":** Am Monatsersten (erster App-Start im neuen Monat) bindet
sich der Vormonat: der lose Blätterstapel staffelt sich zusammen (`legen` rückwärts, 6
Blätter, 40-ms-Stagger), ein Rücken schiebt sich ins Regal, die Prägezeile erscheint.
Haptik: drei absteigende Ticks + ein tiefer `rigid`-Schlusston; Lichtschein Stufe 2. Exakt
1×/Monat — von `Content/BindungLogic.swift` entschieden (pur: „ist Monat X bindbar?",
getestet), nie in der View. Reduce Motion: der Rücken steht sofort, Glow statt Choreografie.

**iPad:** Das bestehende Memories-Split bleibt die Grundlage — die Sidebar-Gruppen
(remember/plan/rituals/private) werden auf die drei Register + Regal gemappt (reines
Umgruppieren von `MemoriesSidebarGroup`, die „kann nie eine Section verlieren"-Garantie
bleibt testbar).

### 3.5 ANHANG — das Register der Werkzeuge

**Bühne:** Eine kurze Wurzelseite als Inhaltsverzeichnis (fünf Registerzeilen A–E mit
`ScopeBadge`), jede öffnet eine `Form`-Seite (`.formStyle(.grouped)`) — die heutige
1200-Zeilen-Monsterseite wird fünf flache, native Seiten. KEINE Artefakte, kein Papier-Korn,
keine Serifen — Werkzeug-Räume bleiben still (Charta §3.6). Gefahrenzone bleibt am Ende von
Register B mit rotem Abschnitts-Header wie heute.

**Signature-Moment „Siegelprobe"** (der eine erlaubte warme Punkt): In Register C
(Erscheinung) drückt sich beim Ändern der Paarfarbe eine Probe des Wachssiegels auf eine
Schmierzettel-Ecke (bestehender `WachsSiegel`-Gradient `Wachs.dunkel → wachsTief`), mit der
leichten Pairing-Haptik. Sonst: keine Klänge, `tap`-Haptik, Punkt statt Ausrufezeichen.

**iPhone/iPad:** identische Struktur; iPad zentriert die Form in der Lese-Spalte
(`contentColumn`), kein Split nötig.

---

## 4. Anti-Generik-Beweis pro Buchteil

- **Blatt:** Eine generische Paar-App zeigt ein Karten-Dashboard, dessen Layout eine Engine
  würfelt; nach 30 Sekunden ist es bei jedem Paar gleich. Das Blatt ist nach dem zweiten
  Eintrag ein Unikat — Screenshot um 9 Uhr ≠ Screenshot um 22 Uhr, Paar A ≠ Paar B, und der
  Beweis hängt am Datenmodell (Chronik aus echten Feeds), nicht an Deko. Kein Wettbewerber
  kann das kopieren, ohne unser Ritual-Inventar zu kopieren.
- **Faden:** Generisch = Bubbles vor Verlaufs-Hintergrund (jede Messaging-App). Der Faden ist
  ein einziges fortlaufendes Dokument mit sichtbarer Naht und Tagesknoten — die Metapher
  sitzt im Material (Naht in der gemeinsamen Tinte), nicht im Farbschema. Die Bubble-Grammatik
  (abgerundete Blasen, Schwänzchen) existiert hier schlicht nicht.
- **Spielbuch:** Generisch = App-Store-Grid aus Spiel-Icons. Das Kapitelverzeichnis mit
  Punktlinien und gespielten-Partien-Seitenzahlen macht den KATALOG selbst zur Biografie:
  schon die Übersicht erzählt, was dieses Paar spielt. Ergebnisse verschwinden nicht in
  einer Stats-Tabelle, sie stehen im Buch — mit Handschrift-Moment, aber ohne Fake-Font.
- **Archiv:** Generisch = Foto-Grid + „Ordner". Das Regal aus gebundenen Jahrgängen mit dem
  losen aktuellen Monat daneben ist eine Informationsvisualisierung der Beziehung selbst:
  Man SIEHT, wie dick das eigene Buch schon ist. Der Binden-Moment gibt dem Monatswechsel
  eine Zeremonie, die keine Galerie-App besitzt.
- **Anhang:** Der Beweis ist hier bewusst NEGATIV: Der Anhang sieht absichtlich nach
  System aus (Form, grouped, ScopeBadges) — Einzigartigkeit durch Kontrast. Dass die
  Werkzeuge still sind, macht die beschriebenen Seiten laut; eine App, die ÜBERALL besonders
  sein will, ist es nirgends (Noble-Test Frage 1).

---

## 5. Ordner-Neubau für `SoooDreamy/ios/SoooDreamy/`

### 5.1 Prinzipien (die den Bestand nicht brechen)

1. **Welle 1 ist ein reiner `git mv`:** Swift kennt keine Pfad-Imports — Datei-Moves brauchen
   NULL Code-Änderungen. Nur zwei Dateien außerhalb müssen mitziehen:
   `ios/Package.swift` (listet 8 Feature-L10n-Dateien EXPLIZIT — Pfade im selben Commit
   aktualisieren) und `ios/project.yml` (globt `path: SoooDreamy` — funktioniert unverändert;
   `createIntermediateGroups: true` baut die Xcode-Gruppen beim nächsten XcodeGen-Lauf neu).
2. **Typ-Umbenennungen sind NICHT Teil des Umzugs** (eigene Welle, §7): In Welle 1 behalten
   alle Dateien ihre Namen; nur Ordner ändern sich. Dateiname ≠ Typname ist in Swift legal.
3. **UITests bleiben grün:** `accessibilityIdentifier`s (`tab.home`, `tab.chat`, `tab.play`,
   `tab.us`, `tab.settings`, `cinematic.skipAll`, `home.firstGreeting`, …) sind ein
   VERTRAG und werden nie umbenannt — auch nicht, wenn Labels und Typnamen wechseln.
4. **`Core/`, `Content/`, `UI/`, `Intents/`, `Resources/`, `ios/Shared/`, `ios/Widgets/`,
   `ios/LogicTests/`, `ios/UITests/` bleiben byte-identisch liegen** — die Logic-Schicht ist
   der Stabilitätskern (Package.swift-Liste!), nur die View-Schicht zieht um.

### 5.2 Zielbaum

```
ios/SoooDreamy/
├── App/            # SoooDreamyApp, AppState(+Platform), ScreenshotSeed
├── Buch/           # die Buchbinderei: RootView (Shell+Overlays), AlmanachTabView,
│                   # LesezeichenBand, DoppelseitenLayout (geteiltes iPad-Split-Muster)
├── Blatt/          # Buchteil I  (+ Blatt/Rituale/, Blatt/Post/, Blatt/Momente/)
├── Faden/          # Buchteil II
├── Spielbuch/      # Buchteil III (+ Spielbuch/Werk/, Spielbuch/Kapitel/, Spielbuch/Saison/)
├── Archiv/         # Buchteil IV (+ Archiv/Gebunden/, Archiv/Versprochen/, Archiv/Versiegelt/)
├── Anhang/         # Buchteil V
├── Kino/           # Onboarding: Kino, Pairing, Recovery, Leseprobe (Demo)
├── Core/           # unverändert
├── Content/        # unverändert + NEU: ChronikLogic, AlmanachKopfLogic, BindungLogic
│   └── Data/       # unverändert
├── UI/             # unverändert + NEU: TintenschriftRenderer, FadenNaht, BuchrueckenText
├── Intents/        # unverändert
└── Resources/      # unverändert
```

### 5.3 Vollständige Datei-Mapping-Tabelle (git-mv-fähig, Welle 1)

**`App/` (6 Dateien — 2 ziehen um):**

| Heute | Ziel |
|---|---|
| `App/RootView.swift` | `Buch/RootView.swift` |
| `App/TodayAccessoryView.swift` | `Buch/TodayAccessoryView.swift` |
| `App/SoooDreamyApp.swift`, `App/AppState.swift`, `App/AppStatePlatform.swift`, `App/ScreenshotSeed.swift` | bleiben in `App/` |

**`Features/Home/` (29 Dateien) → `Blatt/`:**

| Heute | Ziel |
|---|---|
| `DashboardView.swift`, `DashboardHeaderView.swift`, `DailyQuestionCard.swift`, `DailySparkCard.swift`, `CheckinCard.swift`, `FirstMomentCard.swift`, `QuestCard.swift`, `MissedInboxCard.swift`, `FlashbackCard.swift`, `LevelCard.swift`, `WaitingForPartnerCard.swift`, `PresenceViews.swift`, `StreakCalendarView.swift`, `MoodPickerSheet.swift`, `Heart3DView.swift`, `PlatformL10n.swift` † | `Blatt/…` (gleicher Dateiname) |
| `TouchGridCard.swift`, `PulseFan.swift`, `HapticStudioView.swift`, `DuetView.swift`, `HugQueueView.swift`, `DateNightView.swift` | `Blatt/Gruesse/…` |
| `ZeitpostView.swift`, `PostJournalView.swift` | `Blatt/Post/…` |
| `RevealCeremonyView.swift`, `TouchReceivedOverlay.swift`, `PostNoteOverlay.swift` | `Blatt/Momente/…` |
| `BadgeShelfView.swift` | `Archiv/Gebunden/BadgeShelfView.swift` |
| `WhatsNewView.swift` | `Anhang/WhatsNewView.swift` |

**`Features/Rituals/` (15 Dateien):**

| Heute | Ziel |
|---|---|
| `RitualsDashboardSection.swift`, `DaymemoView.swift`, `WeekReviewView.swift`, `NeedsHistoryView.swift`, `RepairConsiderationView.swift`, `CustomQuestionsView.swift`, `RitualsL10n.swift` † | `Blatt/Rituale/…` |
| `SeasonCalendarView.swift`, `CapsulesView.swift`, `GoalsView.swift`, `WeekplanView.swift` | `Archiv/Versprochen/…` |
| `MagazineView.swift` | `Archiv/Gebunden/MagazineView.swift` |
| `RitualsAPI.swift`, `RitualsAppState.swift`, `RitualsModels.swift` | `Core/…` (Feature-übergreifende Leitungen; nicht in Package.swift → kein Manifest-Edit) |

**`Features/Chat/` (9 Dateien) → `Faden/` (alle, gleicher Name):**
`ChatView.swift`, `ChatModel.swift`, `ChatPaper.swift`, `ChatL10n.swift` †,
`LetterComposeView.swift`, `LetterSeals.swift`, `LetterWorkshopView.swift`,
`PinnedMessages.swift`, `VoiceNotes.swift`.

**`Features/Games/` (40 Dateien) → `Spielbuch/`:**

| Heute | Ziel |
|---|---|
| `PlayHubView.swift` | `Spielbuch/PlayHubView.swift` |
| `GameEngine.swift`, `GamesCoordinator.swift`, `GamesAppState.swift`, `GamesA11y.swift`, `GamesL10n.swift` †, `GamesPaperKit.swift`, `BoardDuelKit.swift`, `GameTableView.swift` | `Spielbuch/Werk/…` |
| `BattleshipView.swift`, `ConnectFourView.swift`, `DameView.swift`, `ReversiView.swift`, `GomokuView.swift`, `MancalaView.swift`, `KaesekaestchenView.swift`, `MemoryDuoView.swift`, `WordleView.swift`, `WordPartyGamesView.swift`, `GamesWaveView.swift`, `StadtLandFlussView.swift`, `QuizGameView.swift`, `QuizDuelView.swift`, `ChoiceGamesView.swift`, `TruthOrDareView.swift`, `TruthOrDareLiveView.swift`, `Questions36View.swift`, `TwoTruthsView.swift`, `PictionaryView.swift`, `EmojiRiddleView.swift`, `EmojiRiddleLiveView.swift`, `PhotoMemoryView.swift`, `KniffelView.swift`, `MovieRouletteView.swift`, `DateIdeasView.swift` | `Spielbuch/Kapitel/…` |
| `TournamentView.swift`, `GamesRecordView.swift`, `WordleRecordView.swift`, `ReplayView.swift`, `DailyQuestsView.swift` | `Spielbuch/Saison/…` |

**`Features/Memories/` (25 Dateien) → `Archiv/`:**

| Heute | Ziel |
|---|---|
| `MemoriesView.swift`, `MemoriesHubComponents.swift`, `MemoriesL10n.swift` † | `Archiv/…` |
| `GalleryView.swift`, `GalleryComponents.swift`, `GalleryPagerView.swift`, `MediaLightbox.swift`, `VideoGalleryView.swift`, `VideoPlayerScreen.swift`, `PotdView.swift`, `SoundtrackView.swift`, `CanvasView.swift`, `CanvasExportSheet.swift`, `JournalView.swift`, `LoveStatsView.swift`, `StoryTimelineView.swift`, `StoryModels.swift`, `YearReviewView.swift` | `Archiv/Gebunden/…` |
| `OnThisDayCard.swift` | `Blatt/OnThisDayCard.swift` (Fußnote des Blattes) |
| `EventsView.swift`, `BucketListView.swift`, `SharedListsView.swift`, `CouponsView.swift` | `Archiv/Versprochen/…` |
| `VaultView.swift`, `VaultItemViewer.swift` | `Archiv/Versiegelt/…` |

**`Features/Settings/` (18 Dateien) → `Anhang/` (alle, gleicher Name):**
`SettingsView.swift`, `SettingsL10n.swift` †, `IntelligenceL10n.swift` †,
`PersonalizationView.swift`, `IconGiftView.swift`, `WidgetStudioView.swift`,
`LiveActivitySheet.swift`, `NotificationSettingsSheet.swift`, `AutomationsGalleryView.swift`,
`IntelligenceConsentSheet.swift`, `DeviceManagerSheet.swift`, `MigrationAssistantView.swift`,
`ServerListSheet.swift`, `ICloudSheet.swift`, `DiagnosticsView.swift`,
`VersionHistoryView.swift`, `SoundCreditsView.swift`, `HandbookView.swift`.

**`Features/Onboarding/` (11 Dateien) → `Kino/` (alle, gleicher Name):**
`OnboardingFlowView.swift`, `OnboardingL10n.swift` †, `CinematicIntroView.swift`,
`CinematicChapterPlayer.swift`, `CinematicChapterStages.swift`, `CinematicHandoff.swift`,
`PairingView.swift`, `PairingCeremonyView.swift`, `QRSupport.swift`, `RecoveryViews.swift`,
`DemoBadge.swift`.

**† = in `ios/Package.swift` explizit gelistet** — genau diese 8 Pfade werden im
Umzugs-Commit im Manifest aktualisiert: `ChatL10n`, `GamesL10n`, `MemoriesL10n`,
`OnboardingL10n`, `PlatformL10n`, `RitualsL10n`, `IntelligenceL10n`, `SettingsL10n`.
`swift test` auf Linux ist danach der Beweis, dass der Umzug vollständig war.

**Neue Dateien (spätere Wellen, mit Package.swift-Eintrag + LogicTests):**
`Content/ChronikLogic.swift` (+ `LogicTests/ChronikLogicTests.swift`),
`Content/AlmanachKopfLogic.swift` (Mondphase; + Tests),
`Content/BindungLogic.swift` (+ Tests), `UI/TintenschriftRenderer.swift`,
`UI/FadenNaht.swift`, `UI/BuchrueckenText.swift`, `Buch/AlmanachTabView.swift`,
`Buch/DoppelseitenLayout.swift`.

**Typ-Umbenennungen (Welle 2/3, NICHT Welle 1):** `MainTabView → AlmanachTabView` (lebt in
`RootView.swift`), `TodayAccessoryView → LesezeichenBand`, `DashboardView → BlattView`,
`ChatView → FadenView`, `PlayHubView → SpielbuchView`, `MemoriesView → ArchivView`,
`SettingsView → AnhangView` — jeweils Datei + Typ in EINEM Commit, a11y-IDs unangetastet.

---

## 6. Onboarding-Anschluss: Kino → erste beschriebene Seite

Die Sieben-Szenen-Dramaturgie (§3.9 der Decision) bleibt szenengleich — nur Szene 6/7 und die
Übergabe werden auf den Almanach scharfgestellt:

- **Szene 6 (leeres Polaroid)** erhält den Nachsatz „Eure erste Erinnerung fehlt noch —
  euer Buch fängt sie." (Remotion-Video bleibt textfrei; der Satz ist SwiftUI-Overlay aus dem
  `captions`-Manifest).
- **Szene 7 (Übergabe)** legt das Papier nicht „in den Home-Screen", sondern schlägt DAS
  ERSTE BLATT auf: dasselbe `briefbogen`-Blatt der App, Poststempel prägt „TAG 1", die
  Glas-TabView gleitet herauf, das Lesezeichen-Band erscheint — Kino endet pixelgenau in der
  Blatt-Wurzel, kein Schnitt (prozedural, `CinematicHandoff` bleibt der Mechanismus).
- **Die erste Zeile schreibt die Pairing-Zeremonie:** `PairingCeremonyView` (beide Farben
  fließen zusammen) hinterlässt beim Ausblenden den ersten Chronik-Eintrag in beiden Tinten —
  „{name} & {name}. Hier beginnt euer Buch." — als erste je gerenderte
  `TintenschriftRenderer`-Zeile. Der Moment, in dem der Nutzer versteht: was wir tun, steht
  danach hier.
- **Leseprobe (Demo-Modus):** „Erst mal ansehen" öffnet ein bereits BESCHRIEBENES Buch
  (die bestehenden Demo-Daten als gefüllte Chronik + ein gebundener Probe-Monat im Regal) —
  der Demo-Modus wird vom Feature-Rundgang zur Leseprobe; das permanente Demo-Band oben
  bleibt der Ausgang.
- Solo-Warten (Partner noch nicht da): das Blatt zeigt den `WaitingForPartnerCard`-Zustand
  als „Das Buch wartet auf die zweite Handschrift" — Pairing-Code als erster Zettel im Faden
  (bestehender Flow, neue Bühne).

---

## 7. Migrationsplan (4 Wellen) und Risiken

**Welle 1 — „Umzug" (rein mechanisch, ein PR):** komplette `git mv`-Tabelle aus §5.3 +
8 Pfad-Updates in `Package.swift` + XcodeGen-Regeneration + `swift test` + Charter-Lint.
ACHTUNG, verifiziert: `charter_lint.sh` grept mindestens sieben Metriken hart gegen
`ios/SoooDreamy/Features` (`bare_white_opacity`, `raw_corner_radius`,
`hardcoded_pink_purple_features`, `ultrathin_material_features`, `surface_glass_features`,
`bright_paper_features`, `raw_rotation_features`, `system_size_fonts`) — nach dem Umzug
zählten sie ins Leere und würden fälschlich „0" melden. Der Umzugs-Commit MUSS die
Skript-Scopes auf die Buchteil-Ordner (`Blatt Faden Spielbuch Archiv Anhang Kino Buch`)
umstellen und beweisen, dass alle Zähler exakt gleich bleiben. Kein Pixel ändert sich.
Wegen paralleler Agents: enges Merge-Fenster, Welle 1 zuerst mergen — jeder offene Branch
danach rebased billig (Moves ohne Inhaltsänderung).

**Welle 2 — „Blatt & Lesezeichen":** `ChronikLogic`/`AlmanachKopfLogic` + LogicTests +
Package.swift-Einträge; `TintenschriftRenderer`; `DashboardView` wird zur
Blatt-Komposition (§3.1) umgebaut — `DashboardPriority` bleibt die Kurations-Engine der
Marginalien; Tab-Symbole/-Labels (L10n-WERTE) + Lesezeichen-Band; Morgen-Umschlag;
Deep-Link-Verträge (`sooodreamy://reveal` → Blatt) verifizieren; Typ-Renames Home-Paket;
UITests + Screenshot-Staging (`ScreenshotSeed`) im selben PR nachziehen.

**Welle 3 — „Archiv & Spielbuch":** Register-IA + Regal + `BindungLogic` + Binden-Moment;
`MemoriesSidebarGroup` → Register-Mapping (Vollständigkeits-Garantie testen); Spielbuch-Wurzel
mit Kapitelverzeichnis (PlayHubCuration bleibt Datenquelle); Saison-Stempelbogen; Typ-Renames
Archiv/Spielbuch; `surface_glass_features`-Restbestand (2) fällt hier auf 0.

**Welle 4 — „Faden, Anhang, Kino-Anschluss":** FadenNaht + Einfädeln; Anhang-Register-Split
der `SettingsView`; Szene-6/7-Anschluss + Leseprobe; Siegelprobe; Handbuch
(`Resources/Handbook.de/en.md`) + `docs/`-Handbücher auf die Buchteil-Sprache umschreiben;
finale Ratchet-`--update`-Runde.

**Die fünf härtesten technischen Risiken:**

1. **Xcode-Typecheck-Grenzen:** `ChatView` (~2600 Z.), `PlayHubView` (1784), `SettingsView`
   (1222), `MemoriesView` (1078) werden umkomponiert — genau die Dateien, in denen SwiftUI-
   Typechecker-Explosionen wohnen. Regel: jede neue Komposition extrahiert Subviews < 300
   Zeilen mit expliziten Typen, keine Ternary-Türme; der Anhang-Split ENTSCHÄRFT das Risiko
   langfristig, aber Welle 2–4 brauchen CI-Builds pro Zwischenschritt (Linux-`swiftc -parse`
   + macOS-Build im Release-Farm-Rhythmus).
2. **UITest-Stabilität:** test01–test05 sind EINE gescriptete Reise mit deutschem
   Label-Matching („Erst mal ansehen", „Nachricht senden") und erased-first-launch-Zustand.
   Jede Label-Änderung bricht sie stumm auf dem CI-Simulator. Gegenmittel: IDs statt Labels,
   wo wir anfassen; Labels nur in Wellen ändern, die den UITest im selben PR aktualisieren;
   `cinematic.skipAll`- und `home.firstGreeting`-Verträge nie brechen.
3. **Charter-Ratchets:** Neue Chronik-/Regal-Views schreiben viel Text und Motion — die
   Zähler `emoji_as_text` (22), `try_await_api` (88), `bare_progressview` (36),
   `raw_corner_radius` (32) dürfen NICHT steigen; alle neuen Kurven laufen über
   `Theme.Motion.*`, alle Flächen über `paperCard`/`nightCard`, Skeletons statt Spinner in
   Chronik/Regal. Besonders `bright_paper_features` (Nacht-first-Deckel auf helle
   `paperCard`-Karten): das Blatt ist genau EINE helle `briefbogen`-Fläche und ersetzt den
   heutigen hellen Tagesfrage-Briefbogen — netto darf der Zähler nicht steigen; Marginalien
   und Chronik-Werkzeuge bleiben `nachtkarton`. Jede Welle endet mit
   `charter_lint.sh --update` nur nach UNTEN.
4. **Package.swift-Explizitliste:** Jeder Move einer gelisteten Datei und jede neue
   Content-Logik erfordert einen Manifest-Edit — vergessen = grüner Xcode-Build, roter
   Linux-CI. Der Umzugs-PR enthält deshalb einen Ein-Zeilen-Check
   (`swift test` listet die 3 neuen Logic-Dateien in den Testzielen).
5. **Konzept-Risiko Doppel-Wahrheit:** Chronik (Blatt), Postbuch und Faden zeigen
   verwandte Ereignisse. Ohne harte Dedupe-Regeln (in `ChronikLogic` gepinnt: Chat-Nachrichten
   erscheinen NIE in der Chronik; Berührungen NIE im Faden; das Postbuch ist Rohdaten-Quelle,
   kein dritter Anzeigeort auf dem Blatt) wird das Buch geschwätzig und die App fühlt sich
   redundant an.

---

## 8. Selbstkritik — die fünf härtesten Schwächen dieses Entwurfs

1. **Der Schreiber kann zum Gimmick verkommen.** Wenn die Tintenschrift öfter läuft als der
   Nutzer Geduld hat, ist sie nach einer Woche ein Ladebalken mit Serifen. Die
   Nur-die-neueste-Zeile- und Kein-Replay-Regeln sind Pflicht, aber ihr Erfolg ist erst im
   Gebrauch beweisbar — das Dossier kann ihn nur behaupten.
2. **Die Buch-Metapher verträgt sich schlecht mit Echtzeit.** Tipp-Indikator, Live-Spiele,
   Presence sind KEINE Buch-Phänomene; wo das Buch „lebt", darf es nie träge wirken
   (Gebot 14). Der Entwurf zieht die Grenze (Bretter bleiben Bretter, Faden bleibt sofort),
   aber jede künftige Live-Funktion wird diese Grenze neu verhandeln müssen.
3. **Welle 2 ist teurer, als sie aussieht.** Fünf Tab-Namen, sieben Typ-Renames,
   Handbuch-Texte, Screenshot-Matrix, Widget-Copy, App-Store-Metadaten — der
   Umbenennungs-Blast-Radius reicht weit über `ios/` hinaus (Server-Handbuch, `docs/`,
   Remotion-Captions). Wer nur den Swift-Diff budgetiert, unterschätzt die Welle um die
   Hälfte.
4. **Das Regal flirtet mit dem Kitsch und mit AX.** Buchrücken mit 90°-Text sind die
   riskanteste neue Fläche: Dynamic-Type-AX5, VoiceOver-Lesbarkeit und das Artefakt-Budget
   stehen dagegen; der definierte Fallback (liegende Liste) ist ehrlich, aber wenn er zu oft
   greift, war das Regal Deko. Plan B steht im Entwurf: Register ohne Regal funktionieren
   vollständig.
5. **Die Chronik hängt an Feed-Vollständigkeit.** Sie ist nur so lebendig wie die Ereignisse,
   die der Server liefert; ein Paar in einer stillen Woche sieht ein leeres Blatt — der
   „Ruhetag ist der schönste Zustand"-Text (heutige resting card) muss diese Stille als
   Würde erzählen, sonst erzeugt der Almanach genau den Druck, den Gebot 15 verbietet
   (eine Seite, die sich „füllen MUSS", ist eine Streak mit anderem Namen).

---

*Einreichung „Der lebendige Almanach". Ein Buch, zwei Handschriften, fünf Buchteile —
und eine App, die morgens fast leer ist und abends beweist, dass dieser Tag stattgefunden
hat.*
