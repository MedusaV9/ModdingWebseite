# NEUBAU_ZIMMERHAUS.md — Das Zimmerhaus: Neubau von Informationsarchitektur, Seiten und Ordnern

**Status: Wettbewerbs-Dossier (eine von drei Richtungen).** Das DESIGN steht nicht zur
Debatte: „Papier & Licht" (STYLE_DECISION.md §3) und die Nacht-first-Balance
(MIGRATION_DUNKEL.md) bleiben wörtlich in Kraft — Nachtkarton als Standardfläche, helles
Papier als Artefakt, die eine Lampe, die Kitsch-Budgets 3/1/1, alle Ratchets. Dieses Dossier
baut den AUFBAU neu: welche Räume die App hat, was in ihnen steht, und wie der Code-Baum
heißt. Navigation bleibt strikt nativ (iOS-26-`TabView` mit System-Liquid-Glass, Toolbars,
Sheets, `.searchable` — keine Custom-Bars, Recon-Verbote gelten).

Recherche-Grundlage: `DESIGN.md` (15 Gebote, Ratchet), `docs/styles/STYLE_DECISION.md`,
`docs/styles/MIGRATION_PAPIER.md` + `MIGRATION_DUNKEL.md`, `App/RootView.swift` (echte
TabView, Heute-Zettel-Accessory, Reselect-Scroll), alle 147 Feature-Dateien unter
`ios/SoooDreamy/Features/`, `Content/`-Kataloge, `ios/Package.swift` (explizite
Logic-Pfade), `ios/project.yml` (Glob), `UITests/SoooDreamyUITests.swift` (ID-Verträge),
`tools/charter_lint.sh` (hartkodierte Pfad-Scopes `ios/SoooDreamy/Features`, `**/UI/*`).

---

## 1. Leitidee: Das Zimmerhaus

Die heutige App ist gut möbliert, aber sie ist ein Katalog: fünf Tabs, und hinter jedem
dieselbe Anatomie — Header, dann ein Stapel gleich breiter Karten, dann ein Grid gleich
großer Kacheln. `DashboardView`, `PlayHubView`, `MemoriesView`, `SettingsView` sind
strukturell dieselbe Seite mit anderen Daten. Genau DAS liest das Auge als „generische
App": nicht die Farben (die sind seit Papier & Licht unverwechselbar), sondern die
Wiederholung derselben Seitengrammatik. Man kann die Screenshots der vier Hubs übereinander
legen und die Silhouetten decken sich.

**Die Antwort: Die App ist kein Katalog, sondern ein gemeinsames Zuhause bei Nacht.**
Jeder Tab ist ein ZIMMER mit eigener Innenarchitektur. Ein Zimmer hat keine „Sections",
es hat **Möbel** — und jedes Möbel IST eine Funktion: Der Tisch trägt die Tagesfrage, die
Kommode hat Schubladen für die Rituale, das Spielregal hält die 26 Schachteln, der
Kühlschrank trägt den Wochenplan unter Magneten, die Truhe auf dem Dachboden ist der
Tresor. Möbel sind keine Deko-Metapher, die man wegerklären muss: Sie geben jeder Seite
eine EIGENE Silhouette (Zonen mit festen Rollen statt endloser Stapel), sie geben jeder
Funktion einen ORT (man erinnert sich räumlich: „das Sparglas steht in der Küche"), und
sie geben der Lampe etwas zu beleuchten (die Licht-Dramaturgie bekommt Bühnenbild statt
Hintergrund).

Der rote Faden trägt vom ersten Frame bis in den Alltag: Das Kino erzählt schon heute die
erste Nacht in einem Zimmer — Lampenklick, Umschlag, Siegelbruch, Tintenfässer, Polaroid.
Das Zimmerhaus macht aus diesen Kino-Requisiten Dauer-Möbel: Der Umschlag wohnt fortan in
der Poststube, das Polaroid liegt auf dem Dachboden, das Wachs siegelt am Schreibtisch.
Das Kino ist dann keine Werbung für eine App, die danach anders aussieht — es ist der
Einzug in das Haus, in dem man wohnen bleibt. Und die Nacht-first-Entscheidung wird
stärker, nicht schwächer: EIN Haus, EINE Lampe, und jedes Zimmer stellt sie woanders hin.

Warum das die Generik tötet, in einem Satz: Eine Karte kann jede App zeigen — **einen
Raum, in dem die Möbel euch gehören, kann nur diese App zeigen.**

---

## 2. IA-Karte: Fünf Zimmer und die Kammer

### 2.1 Die Zimmer (Tab-Leiste, native `TabView`)

| # | Zimmer (DE) | EN | Tab-Label | SF-Symbol | Zweck (ein Satz) | a11y-ID |
|---|---|---|---|---|---|---|
| 1 | **Wohnzimmer** | Living Room | „Wohnzimmer" / "Living Room" | `lamp.desk` | Der Abend zu zweit: Präsenz, das heutige Papier auf dem Tisch, Berührungen, Rituale. | `tab.home` (stabil) |
| 2 | **Poststube** | Mail Room | „Poststube" / "Mail Room" | `envelope` | Alles Geschriebene: Zettelwechsel, Briefe, Zeitpost, Kapseln, die Leine mit den wichtigen Zetteln. | `tab.chat` (stabil) |
| 3 | **Spielzimmer** | Game Room | „Spielzimmer" / "Game Room" | `dice` | Der Spieltisch mit laufenden Partien, das Regal mit 26+ Schachteln, die Vitrine, der Abreißkalender. | `tab.play` (stabil) |
| 4 | **Küche** | Kitchen | „Küche" / "Kitchen" | `refrigerator` | Der gemeinsame Vorrat an Zukunft: Wochenplan am Kühlschrank, Listen, Sparglas, Gutscheinheft, Kalender, Türchen. | `tab.kueche` (**NEU**) |
| 5 | **Dachboden** | Attic | „Dachboden" / "Attic" | `archivebox` | Das Gedächtnis des Paares: Kisten voller Alben, die Chronik, die Messlatte, die Truhe. | `tab.us` (stabil) |
| — | **Kammer** | Utility Room | (kein Tab — Sheet hinter dem Hausschlüssel) | `key` | Werkzeugraum: Sicherungskasten, Schlüsselbrett, Vorratsregal, Anstreichtopf, Hausordnung. | `kammer.tuer` (**NEU**, ersetzt `tab.settings`) |

**Die eine strukturelle Entscheidung dieses Dossiers:** Der „Mehr"-Tab stirbt. Eine Kammer
ist kein Zimmer, in dem man wohnt — man geht hinein, legt einen Hebel um und geht wieder.
Die Kammer wird ein Sheet hinter dem **Hausschlüssel** (`key`-ToolbarItem, in JEDEM Zimmer
an derselben Stelle oben rechts; im Wohnzimmer ohne Nav-Bar als stiller Knopf am Ende der
Fensterbank). Der freigewordene fünfte Tab-Platz geht an die **Küche** — und holt damit
die heute am tiefsten vergrabene Feature-Familie (Wochenplan, Listen, Ziele/Sparen,
Events, Gutscheine, Bucket, Türchen-Kalender: sieben Screens hinter einem 14-Kachel-Grid
im Wir-Tab) an die Oberfläche. Native Präzedenz: Profil-/Einstellungs-Knopf in der Toolbar
ist etabliertes Apple-Muster (Fitness, Journal, News). iPad-Bonus: ⌘, öffnet die Kammer.

**Navigationsregel (Gesetz):** Unter jedem Tab maximal **2 Ebenen** — Zimmer-Root (0) →
Möbel-Seite (1) → Detail (2). Sheets zählen als Ebene ihrer Herkunft. Geprüfte Worst
Cases: Dachboden → Album → Lightbox ✓ · Spielzimmer → Spiel → (zurück) ✓ · Spielzimmer →
Vitrine/Replay → Replay-Player ✓ · Poststube → Kapselregal → Kapsel ✓ · Küche →
Wochenplan → Tag-Sheet ✓.

### 2.2 Vollständiges Mapping: jeder heutige Screen → sein Ort im Haus

Nichts geht verloren. Ebene = Navigationsebene unter dem Tab (S = Sheet).

**Alt: Zuhause (Dashboard)**

| Heute | Neu: Zimmer · Möbel/Zone | Ebene |
|---|---|---|
| `DashboardHeaderView` (Avatare, Tage, Mood, Präsenz) | Wohnzimmer · **Fensterbank** (Präsenz-Vignette) | 0 |
| Hero-Slot (`DailyQuestionCard`/`FirstMomentCard`/`CheckinCard`/Resting) | Wohnzimmer · **Der Tisch** (das heutige Papier; Rangfolge bleibt `DashboardPriority`) | 0 |
| `MissedInboxCard` („während du weg warst") | Wohnzimmer · Zettel AUF dem Tisch, über dem Hero (Papier-Artefakt) | 0 |
| `TouchGridCard` + Stationen (Zeitpost/Journal-Schnellzugriff) | Wohnzimmer · **Der Sessel** (Berührungen; Stationen behalten `home.station.*`) | 0 |
| `RitualsDashboardSection` (Energie-Akku, „Ich brauche gerade", Daymemo, Wochenrückblick, Reparatur, Türchen-Support) | Wohnzimmer · **Die Kommode** (drei Schubladen: Rituale · Spiel-Momente · Momente) | 0 (Inhalt 1/S) |
| `QuestCard`, `LevelCard`, `BadgeShelfView`, `StreakCalendarView`, `Heart3DView`-Koda | Wohnzimmer · **Der Kaminsims** (Biografie: Herz, Stufen, Abzeichen, Kalender) | 0 (Details S) |
| `HugQueueView`, `DuetView`, `HapticStudioView`, `MoodPickerSheet` | Wohnzimmer · Sessel-Aktionen (Sheets) | S |
| `PulseFan` (FAB), „Ich brauche gerade"-Fächer | Wohnzimmer · Chrome-Glas, unverändert | 0 |
| `ZeitpostView` (planen), `PostJournalView` (Zustell-Journal) | **Poststube** · Schreibtisch-Fach „Zeitpost" + Postfach „Journal" (Sessel-Station im Wohnzimmer öffnet dasselbe Sheet — `zeitpost.*`-IDs stabil, UITest test04 bleibt grün) | S / 1 |
| `DateNightView` | **Küche** · Zone „Der Abend" (Rezeptbox daneben) | 1 |
| `WhatsNewView` | **Kammer** · Hausordnung („Was ist neu") | S |
| `RevealCeremonyView`, `TouchReceivedOverlay`, `PostNoteOverlay` (RootView-Overlays) | **Werkstatt** (raumlos — Momente spielen über dem ganzen Haus) | — |

**Alt: Chat**

| Heute | Neu | Ebene |
|---|---|---|
| `ChatView` (Zettelwechsel, Tagestrenner-Poststempel) | Poststube · **Der Stapel** (Herzstück, Ebene 0) | 0 |
| `PinnedMessages` | Poststube · **Die Leine** (oben, quer gespannt; heute Sheet → wird sichtbare Zone) | 0 (alle: 1) |
| Composer + `VoiceNotes` | Poststube · **Der Schreibtisch** (Glas-Eingabeleiste bleibt Chrome) | 0 |
| `LetterComposeView`, `LetterWorkshopView`, `LetterSeals` | Poststube · Schreibtisch-Fach „Brief" (Siegel-Werkstatt) | S |
| `CapsulesView` (heute Wir) | Poststube · **Das Kapselregal** (Briefe an die Zukunft = Post) | 1 |

**Alt: Spielen**

| Heute | Neu | Ebene |
|---|---|---|
| `sessionBanners` + `GameTableView` (laufende Partien) | Spielzimmer · **Der Spieltisch** (Papier-Bogen im Lichtkegel, Partien liegen AUF dem Tisch) | 0 → 1 |
| Katalog (async/live/party, 26+ Spiele, `collapsibleSection`) | Spielzimmer · **Das Regal** (Schachtel-Rücken auf Brettern: Täglich · Zu zweit · Live · Party) | 0 → 1 |
| `WordleView`/`WordleRecordView`, `DailyQuestsView` | Spielzimmer · **Der Abreißkalender** (das heutige Blatt) | 0 → 1 |
| `TournamentView` (Saison), `GamesRecordView`, `ReplayView` | Spielzimmer · **Die Vitrine** (Pokale, Bestenliste, Wiedersehen) | 1 → 2 |
| Spiel-Tutorials (`GameIntroCatalog`) | Spielzimmer · Regal-Beileger („Anleitung" pro Schachtel) | 1 |
| `DateIdeasView` | **Küche** · Rezeptbox (Date-Ideen als Rezeptkarten) | 1 |

**Alt: Wir (Memories)**

| Heute | Neu | Ebene |
|---|---|---|
| `GalleryView`/`GalleryPagerView`/`MediaLightbox`, `VideoGalleryView`/`VideoPlayerScreen`, `PotdView` | Dachboden · **Kiste „Album"**, **Kiste „Filme"**, **Kiste „Foto des Tages"** | 1 → 2 |
| `OnThisDayCard`/`FlashbackCard` | Dachboden · das **Polaroid obenauf** (Zone 0; Wohnzimmer-Tisch darf es weiter als Tages-Hero ausspielen — Rangfolge unverändert) | 0 |
| `JournalView`, `StoryTimelineView`, `YearReviewView`, `MagazineView` (heute Rituale) | Dachboden · **Die Chronik** (Journal · Geschichte · Jahr · Monatsmagazin) | 1 |
| `LoveStatsView` | Dachboden · **Die Messlatte** (Striche am Türrahmen) | 1 |
| `SoundtrackView` | Dachboden · **Die Plattenkiste** | 1 |
| `CanvasView`/`CanvasExportSheet` | Dachboden · **Die Staffelei** | 1 / S |
| `VaultView`/`VaultItemViewer` | Dachboden · **Die Truhe** (mit Schloss, abseits der Kisten) | 1 → 2 |
| `SharedListsView`, `BucketListView`, `CouponsView`, `EventsView`, `GoalsView` (heute Rituale), `WeekplanView` (heute Rituale) | **Küche** (siehe unten) | 1 |
| Memories-Suche (Recon-Sweep #4/#5) | Dachboden · `.searchable` am Root, Scope-Tokens (Fotos · Journal · Ereignisse) | 0 |

**Alt: Rituale (heute über Zuhause/Wir verstreut)**

| Heute | Neu | Ebene |
|---|---|---|
| `EnergyCard`, `NeedsCard` + `NeedsHistoryView`, `DaymemoView`, `WeekReviewView` (Wochenrückblick-Ritual), `RepairConsiderationView` | Wohnzimmer · Kommoden-Schubladen (Historie = Ebene 1) | 0 → 1 |
| `CustomQuestionsView` (eigene Fragen) | Wohnzimmer · Tisch-Schublade „Eure Fragen" | 1 |
| `SeasonCalendarView` (Türchen-Kalender) | Küche · **Der Wandkalender** (Türchen des Monats) | 1 |
| `WeekplanView` | Küche · **Der Kühlschrank** (Hero) | 0 → 1 |
| `GoalsView` (Ziele/Sparen) | Küche · **Das Sparglas** | 1 |

**Alt: Mehr (Settings) → Kammer (Sheet, `kammer.tuer`)**

| Heute | Neu: Kammer-Zone | Ebene |
|---|---|---|
| Profil, Paar, Personalisierung (`PersonalizationView`), `IconGiftView`, `WidgetStudioView`, `LiveActivitySheet` | **Anstreichtopf** (alles, was das Haus färbt) | S → S2 |
| Töne, Haptik, Mitteilungen (`NotificationSettingsSheet`), App-Sperre | **Sicherungskasten** (die Hebel) | S |
| `ServerListSheet`, `DeviceManagerSheet` (Multi-Device), `MigrationAssistantView`, `ICloudSheet`, `RecoverySheet` | **Schlüsselbrett & Vorratsregal** (Verbindung, Geräte, Sicherung) | S → S2 |
| `DiagnosticsView`, `AutomationsGalleryView` (Shortcuts), `IntelligenceConsentSheet` | **Werkzeugkasten** | S → S2 |
| `HandbookView`, `AboutSheet`, `SoundCreditsView`, `VersionHistoryView`, `WhatsNewView`, Kino-Replay | **Hausordnung** | S → S2 |
| Demo-Modus (`DemoBadge`) | unverändert global (`safeAreaBar`, RootView) | — |

**Raumlose Systeme (unverändert):** Heute-Zettel-Accessory (`TodayAccessoryView`, System-
Accessory über der Bar), alle RootView-Overlays/Zeremonien, Widgets-Target, Live
Activities, App Intents, AppLock, Onboarding/Pairing/Recovery (→ `Kino/`, Abschnitt 6).

### 2.3 Accessibility-ID-Migrationsliste (UITest-Vertrag)

| ID | Status |
|---|---|
| `tab.home`, `tab.chat`, `tab.play`, `tab.us` | **stabil** (Zimmer dahinter umbenannt, IDs nicht) |
| `tab.kueche` | **neu** (Küchen-Tab) |
| `tab.settings` | **entfällt** → `kammer.tuer` (Hausschlüssel-ToolbarItem). UITest `test02_DemoModeTour` (Zeile ~134 `switchTab(id: "tab.settings")`) wechselt im selben Commit auf `app.buttons["kammer.tuer"].tap()` |
| `home.firstGreeting` | stabil (Fensterbank-Gruß; test05-Anker) |
| `home.station.zeitpost`, `home.station.journal` | stabil — die Sessel-Stationen bleiben im Wohnzimmer und öffnen die (umgezogenen) Poststube-Sheets; test04 unverändert grün |
| `chat.composer`, `chat.send`, `zeitpost.*`, `pairing.*`, `server.*`, `recovery.*`, `cinematic.*`, `onboarding.path.*`, `demo.badge` | stabil |
| `kueche.kuehlschrank`, `dachboden.suche`, `poststube.leine` | neu, nach Bedarf der jeweiligen Welle |

---

## 3. Zimmer-Kompositionen (Bühnenbeschreibungen)

Alle Maße sind benannte Tokens der neuen Familie **`Zimmer.*`** (Design-Schicht, Gebot 11;
alle Werte auf dem 4er-Raster): `fensterbank = 96` · `kommodenFront = 56` · `leine = 72` ·
`pult = 64` · `regalBrett = 148` · `kiste = 168` · `magnet = 28` · `lampenDim = 0.12`.
Jedes Zimmer erbt die Gesetze: genau EIN Briefbogen, max. 3 Artefakte / 1 Riss / 1
Rotation, Serif nur auf Papier, Nacht-Tinten auf Nachtkarton. **AX-Regel für alle Bühnen:**
ab `isAccessibilitySize` kollabiert jede Bühne in einen einfachen gestapelten Pfad
(Zonen werden Karten voller Breite, feste Zonenhöhen fallen) — dieselbe Mechanik wie
`AccessibilityBudget.sideChromeCollapses` heute.

### 3.1 Wohnzimmer — „der Abend beginnt hier"

**Bühne (iPhone, von oben nach unten):**
- **Fensterbank** (Höhe `Zimmer.fensterbank`): die Präsenz-Vignette. Links der Gruß
  (`home.firstGreeting`), rechts die zwei Avatare als Paar auf der Bank; ist der Partner
  online, sitzt seine Figur im Licht (voller `coupleTint`-Ring), offline rückt sie in den
  Schatten (Ring auf `Nacht.naht`, „zuletzt hier"-Zeile in `Nacht.tertiaer`). Mood-Emoji
  bleibt Paar-Inhalt neben dem Avatar. Ganz rechts, still: der Hausschlüssel (`key`,
  `kammer.tuer`).
- **Der Tisch** (Hero-Zone): das heutige Papier-Artefakt — `DashboardPriority` entscheidet
  wie heute (FirstMoment → Tagesfrage-Briefbogen → Check-in → Resting). Der Hero ist der
  EINE Briefbogen des Screens (Band + Wachssiegel + Poststempel „TAG {n}"), Einstieg per
  `blaettern`. Liegt Post im `MissedInbox`, liegt sie als schmaler Zettel OBEN AUF dem
  Tisch-Papier (überlappend um `Space.m`, Stapelkante) — „jemand hat dir etwas hingelegt".
- **Der Sessel** (Berührungs-Zone): TouchGrid + die Stationen (Zeitpost, Journal, Duett,
  Haptik-Studio, Umarmung) als eine Reihe niedriger Nachtkarton-Kacheln; der `PulseFan`
  bleibt als Chrome-FAB darüber.
- **Die Kommode** (Höhe geschlossen: 3 × `Zimmer.kommodenFront`): DREI beschriftete
  Schubladen — „Rituale" (Energie-Akku, Ich-brauche-gerade, Daymemo, Wochenrückblick,
  Reparatur), „Spiel-Momente" (Quest, wartende Züge), „Momente" (Heute-vor, nächstes
  Ereignis). Eine Schublade ist ein `DisclosureGroup` im Nachtkarton, dessen Front beim
  Öffnen um `Space.s` nach unten UND vorn fährt (Schatten `raised → floating`); der
  Griff ist eine `Papier.nachtLichtkante`-Linie, kein Chevron. Ersetzt den heutigen
  „Mehr"-Fold — gleiche Logik (`DashboardPriority.more`), neue Anatomie.
- **Der Kaminsims** (Koda): Herz-3D über einer schmalen Leiste mit Level, Abzeichen,
  Streak-Kalender — Biografie, kein Spielstand (Gebot 15).

**Native Bausteine:** `NavigationStack` (Toolbar versteckt wie heute), eine `ScrollView`
mit `.scrollEdgeEffectStyle(.soft)`, `TimelineView(.periodic 60 s)` für die Tisch-Rangfolge,
`DisclosureGroup` für Schubladen, `.refreshable` + `onScrollPhaseChange` für den
Signature-Moment, `contentMargins(.horizontal, Space.l)`.

**Licht-Dramaturgie:** Der Lampenkegel ankert visuell auf dem Tisch. Zonen außerhalb des
Kegels dimmen beim Scrollen minimal per `scrollTransition` (max. `Zimmer.lampenDim` = 12 %
Opacity-Delta, token-gedeckelt, unter Reduce Motion aus) — der Raum bleibt ruhig, aber das,
was man ansieht, steht im Licht.

**Signature-Moment: Der Lampenzug.** Pull-to-Refresh wird zum Zug an der Lampenschnur:
Überziehen spannt eine per `Canvas` gezeichnete Zugschnur aus der oberen Kante
(2-pt-`Nacht.naht`-Pfad mit Öse in `Licht.lampengold` — Nicht-Text-Akzent), am
Auslösepunkt ein Schnurzug-Klick (HapticPatternKit: zwei weiche Ticks + `rigid`-Klick),
der Lichtkegel blüht einmal per `lichtschein`-Signatur, dann läuft das normale
`.refreshable`. Kein neues Sound-Asset: der bestehende leise UI-Klick der SoundEngine
genügt, sonst haptisch-only (Gebot 3 verlangt eines von beiden). Reduce Motion: keine
Schnur, Standard-Refresh + statischer End-Glow. VoiceOver: „Aktualisiert — alles Neue
liegt auf dem Tisch."

**iPad (regular):** Fensterbank volle Breite; darunter `HStack`: Tisch-Spalte (Anteil
`Zimmer.tischN` = 0.62) links, rechts Sessel + Kommode + Kaminsims als schmale Wand.
Ersetzt die heutige `balancedColumns`-Mathematik durch feste Bühnen-Spalten (die
Rangfolge bleibt `DashboardPriority`, nur die Höhen-Balance-Heuristik entfällt).

### 3.2 Poststube — „alles, was ihr euch schreibt"

**Bühne:**
- **Die Leine** (oben, Höhe `Zimmer.leine`): gepinnte Zettel hängen an einer quer
  gespannten Schnur (ein `Canvas`-Bogen, `Nacht.naht`), horizontale `ScrollView` mit
  `scrollTargetBehavior(.viewAligned)`. Jeder Zettel: Mini-`paperCard` mit EINER
  Klebeecke; NUR der neueste trägt die eine Rotation des Screens (`paperTilt(seed:)`) —
  Budget-bewusst. Leer: die Schnur hängt sichtbar durch, eine Zeile lädt ein („Halte
  einen Zettel gedrückt, um ihn hier aufzuhängen.").
- **Der Stapel** (Mitte, Ebene 0): der Zettelwechsel wie heute — eigene Zettel
  `Papier.brief`, Partner `Papier.karton`, 4-pt-Tintenkante, Poststempel-Tagestrenner
  „TAG {n}", versiegelte Briefe mit Siegelbruch. `defaultScrollAnchor(.bottom)`.
- **Der Schreibtisch** (unten): die Glas-Eingabeleiste (Chrome, unverändert) bekommt
  darüber eine Fächerzeile (Höhe `Zimmer.pult`, erscheint auf den Büroklammer-Knopf):
  vier Fächer — **Brief** (LetterWorkshop mit Siegel), **Zeitpost** (`zeitpost.*`-Sheet,
  IDs stabil), **Kapsel** (an die Zukunft), **Foto/Ton**. Die Fächer sind
  `Papier.nachtInnenFill`-Mulden mit SF-Symbolen, keine Emoji.
- **Das Postfach** (Toolbar, `tray`): Ebene 1 — Zustell-Journal (Zeitpost-Historie) und
  **Kapselregal** (versiegelt/reif; reife Kapseln liegen obenauf, Siegel zuerst).

**Native Bausteine:** `NavigationStack` + Toolbar (Postfach, Hausschlüssel), Sheets für
die Fächer, `matchedGeometryEffect` für Zettel → aufgefalteter Brief (Lese-Ansicht in
`Typo.brief` auf Papier), `ScrollViewReader` für Sprung zum Tagestrenner.

**Signature-Moment: Der Poststempel-Schlag.** Senden stempelt: Der abgehende Zettel legt
sich per `legen` in den Stapel, und im Landetakt schlägt der Poststempel „TAG {n}" auf
seine Ecke — Stempel skaliert 1.6 → 1.0 auf `settle`, dazu ein einzelner satter
`rigid`-Thunk (das Stempel-Haptik-Muster existiert im Kino-Manifest bereits), danach
0.2 s Ruhe. Das materialisiert die Editorial-Anleihe („TAG 137") in der häufigsten Geste
der App, OHNE Feier-Inflation: kein Klang, kein Glow — ein Stempel ist Handwerk, kein
Feuerwerk. Reduce Motion: Stempel blendet ohne Scale ein. VoiceOver: „Zettel liegt bei
{Name}. Tag {n}."

**iPad:** Stapel + Schreibtisch links; ab Pult-Schwelle (neue reine Regel
`LayoutRules.poststubeUsesPult`, Mechanik wie `memoriesUsesPersistentSidebar`) rechts ein
ständiges **Pult**: Brief-Composer bzw. Postfach dauerhaft offen — schreiben und lesen
gleichzeitig, wie an einem echten Sekretär.

### 3.3 Spielzimmer — „der Tisch ist gedeckt"

**Bühne:**
- **Der Spieltisch** (Hero): ein großer Papier-Bogen im Lichtkegel (die eine helle
  Fläche; `paperCard`, Tisch-Einzug `Space.xl`). Laufende Partien liegen als Spielkarten
  AUF dem Bogen, gefächert um 2° (seeded; die Fächerung ist die EINE Rotation des
  Screens). Du-bist-dran-Karten liegen obenauf mit `coupleTint`-Tintenkante. Leerer
  Tisch: „Der Tisch ist frei. Zieh eine Schachtel aus dem Regal." + Knopf.
- **Der Abreißkalender** (schmal, unter dem Tisch): das heutige Blatt — Wordle-Tagesduell
  und Tagesaufgaben als EIN Kalenderblatt mit Datumszeile in `Typo.anschrift`. Erledigt =
  Blatt wirkt „abgerissen": obere Kante perforiert als gestanzte Linie (`Papier.kante`
  Strichlinie — der echte `TornEdgeShape`-Riss wird NUR gebucht, wenn der app-weite
  Deckel ≤ 6 es hergibt; sonst bleibt die Perforation, die Budget-frei ist).
- **Das Regal** (Katalog): vier Bretter (Zeilenhöhe `Zimmer.regalBrett`) — „Täglich",
  „Zu zweit" (async), „Live", „Party". Spiele stehen als **Schachtel-Rücken** im Brett:
  hochkant, Titel gedruckt (`Typo.label`), SF-Symbol als Prägung, Spielstand-Punkt in
  Paartinte. Horizontale `ScrollView` je Brett, `scrollTargetBehavior(.viewAligned)`;
  Brett-Kante = 2-pt-`Papier.nachtLichtkante`. Klapp-Zustand bleibt `@AppStorage`.
- **Die Vitrine** (unten): Saison-Pokal, Bestenliste, Wiedersehen (Replay) hinter Glas —
  eine Chrome-Glas-Leiste (die Vitrine SCHWEBT als einziges Möbel: Glas gehört dem
  Schwebenden) mit drei Zielen, Ebene 1.

**Native Bausteine:** `NavigationStack(path:)` mit `GameDestination` (bleibt wörtlich),
`.searchable` am Root („Spiel finden" — durchsucht die Schachteln), Toolbar (Vitrine,
Hausschlüssel), `matchedGeometryEffect` Tisch ↔ Karten.

**Signature-Moment: Vom Stapel ziehen.** Die oberste Karte des Weiterspielen-Stapels
lässt sich mit dem Finger AUF den Tisch ziehen (`DragGesture` + `matchedGeometryEffect`);
beim Einrasten in die Tischmitte ein Snap (`settle`-Feder + `rigid`-Tick), dann öffnet
die Partie. Tap tut dasselbe als Morph (kein Gesten-Zwang). Reduce Motion: Crossfade am
Ort. VoiceOver: „{Spiel} liegt auf dem Tisch. Du bist dran." — Siege feiern weiter per
Lichtschein Stufe 1–2, `epic` bleibt Monats-Ereignissen (Gebot 4).

**iPad:** Tisch links (0.55), Regal rechts als Schrankwand (Bretter untereinander),
Vitrine volle Breite unten.

### 3.4 Küche — „der Vorrat an Zukunft"

**Bühne:**
- **Der Kühlschrank** (Hero, Ebene 0): der Wochenplan als Magnettafel — sieben schmale
  Tagesspalten (native `Grid`), Einträge sind kleine Zettel unter **Magneten**
  (Ø `Zimmer.magnet`, Kreis in `coupleTint.primary`/`secondary` — wer plant, dessen
  Magnet). Heute-Spalte trägt die `Papier.nachtLichtkante`. Tap auf den Kühlschrank →
  Wochenplan-Vollbild (Ebene 1).
- **Der Wandkalender** (halbe Breite): nächstes Ereignis/Countdown groß, darunter der
  Monat mit den **Türchen** des Saison-Kalenders (verschlossene Türchen als
  `nachtInnenFill`-Quadrate mit Prägezahl; das nächste offene glimmt `lampengold`).
  Ebene 1: `EventsView` bzw. `SeasonCalendarView`.
- **Das Klemmbrett** (halbe Breite, neben dem Kalender): die gemeinsamen Listen — oberste
  3 offene Punkte als echte Checkboxen (sofortiges lokales Abhaken, Gebot 14), Klammer
  oben als `Papier.kante`-Bügel. Ebene 1: `SharedListsView`.
- **Die Vorratszeile**: drei Gläser nebeneinander — **Sparglas** (Ziele/Sparen: native
  `Gauge(.accessoryLinearCapacity)` als Füllstand IM Glasumriss, Zahlen in `Typo.number`),
  **Gutscheinheft** (oberster Coupon mit Scallop-Kante lugt heraus), **Korkwand** (Bucket-
  List: nächster Traum als Pin-Karte). Je Ebene 1.
- **Der Abend**: Date-Abend-Karte (DateNight + Live Activity) und die **Rezeptbox**
  (Date-Ideen als Rezeptkarten zum Durchblättern — `TabView(.page)` im Detail). Ebene 1.

**Native Bausteine:** `ScrollView` + `Grid`/`GridRow` (die Küche ist das EINE Zimmer mit
echtem Raster — eine Küche ist gekachelt, das ist hier Aussage, nicht Faulheit),
`Gauge`, `DisclosureGroup` nur im Klemmbrett, Toolbar (Hausschlüssel).

**Signature-Moment: Magnet setzen.** Einen Wochenplan-Eintrag bestätigen/verschieben
heißt: der Magnet springt an die Tafel — Chip folgt dem Finger (`DragGesture` über den
Tagesspalten), beim Loslassen schnappt er mit überschwingender `settle`-Feder auf den
Zieltag, ein einzelner `rigid`-Klick wie Metall auf Blech. Kein Klang (Planung ist
leise Alltagsarbeit). Reduce Motion: Eintrag erscheint ohne Flug. VoiceOver: „{Titel}
hängt am {Tag}."

**iPad:** Kühlschrank links als hohe Tür (volle Höhe), rechts die Wand: Kalender +
Klemmbrett oben, Vorratszeile + Abend darunter.

### 3.5 Dachboden — „das Gedächtnis unterm Dach"

**Bühne:**
- **Das Polaroid obenauf** (Zone 0): „Heute vor …" liegt als Polaroid auf der nächsten
  Kiste — UNENTWICKELT (milchig `Papier.polaroid`), bis man es entwickelt (Signature).
  Gibt es heute nichts: ein leerer Polaroid-Rahmen mit Einladung („Eure erste Erinnerung
  fehlt noch." + Kamera-Knopf) — dieselbe Dramaturgie wie Kino-Szene 6.
- **Die Kisten** (Herzstück): KEIN gleichförmiges Grid — zwei Spalten mit
  unterschiedlichen Kistenhöhen (Mindestkachel `Zimmer.kiste`): **Album** (größte Kiste,
  zeigt 3 Foto-Kanten als Stapel), **Filme**, **Foto des Tages**, **Plattenkiste**
  (Soundtrack), **Staffelei** (Canvas, lehnt „an der Wand" = volle Spaltenbreite, flach),
  **Chronik** (Journal · Geschichte · Jahresrückblick · Monatsmagazin als EIN Buchrücken-
  Stapel). Jede Kiste trägt ein Papier-ETIKETT: kleiner `Papier.karton`-Streifen mit
  Aufschrift in `Typo.anschrift` (Serif auf Papier ✓) — das einzige Artefakt pro Kiste.
- **Die Messlatte** (schmaler Streifen an der Führungskante): Love-Stats als
  Bleistift-Striche am Türrahmen — kleine Marken mit Zahl (`Typo.number`) und Label;
  Tap → Statistik-Seite (Ebene 1).
- **Die Truhe** (unten, abseits): der Tresor — dunkler als alles andere
  (`Papier.zimmerOben`-Fläche, `lock`-Beschlag), Face-ID öffnet den Deckel. Ebene 1 → 2.

**Native Bausteine:** `.searchable` am Root mit Scope-Tokens (Fotos · Journal ·
Ereignisse) — DIE Erinnerungs-Suche aus dem Recon-Sweep; `navigationTransition(.zoom
(sourceID:in:))` + `matchedTransitionSource` für Kiste → Album und Polaroid → Lightbox
(der native Zoom IST das Aufklappen der Kiste); auf regular width bleibt die bewährte
Split-Anatomie: die Kistenliste wird zur **Regalwand** (persistente Spalte, Mechanik von
`LayoutRules.memoriesUsesPersistentSidebar` wörtlich weiterverwendet).

**Signature-Moment: Polaroid entwickeln.** Press-and-hold auf das milchige Polaroid:
das Bild entwickelt sich radial unterm Daumen (maskierter Reveal via `TimelineView`),
begleitet von sechs weichen Haptik-Ticks im Crescendo; loslassen vor Ende lässt es
zurück-milchen. Am Ende: ein stiller Moment, kein Konfetti. Reduce Motion / AX: einfacher
Tap, Crossfade. VoiceOver: Announcement „Heute vor {n} Jahren: {Titel}". — Warum das
trägt: Erinnern bekommt eine GESTE des Wartens; kein anderes Feature der App und keine
andere Paar-App hat sie.

### 3.6 Kammer (Sheet) — „Hebel, Schlüssel, Vorräte"

Werkzeugraum: bewusst STILL (keine Artefakte, kein Korn, keine Signature-Feier — die
Physik der Hebel ist das einzige Vergnügen). Ein `NavigationStack` im Sheet
(`presentationDetents([.large])`), native grouped `Form` mit fünf Zonen als Sections:
**Sicherungskasten** (Master-Hebel: Töne, Haptik, Mitteilungen, App-Sperre — native
Toggles mit `sensoryFeedback` + schwerem `rigid`-Klick, Hebel-Ikonografie
`lightswitch.on`), **Schlüsselbrett** (Geräte/Multi-Device, Server, Pairing-Code),
**Vorratsregal** (iCloud, Backup, Migration, Wiederherstellung), **Anstreichtopf**
(Personalisierung, Icon-Geschenke, Widget-Studio, Live-Aktivität), **Werkzeugkasten &
Hausordnung** (Diagnose, Automationen, Handbuch, Über, Was-ist-neu, Kino-Replay).
Alle heutigen Sub-Sheets bleiben Sub-Sheets (max. Ebene S2).

---

## 4. Anti-Generik-Beweis: was konkret KEINE Standard-Liste mehr ist

| Zimmer | Standard-SwiftUI wäre … | Das Zimmerhaus baut stattdessen … |
|---|---|---|
| Wohnzimmer | Header + N gleich breite Karten + DisclosureGroup „Mehr" | Vier Zonen mit festen Rollen und eigener Silhouette: Vignette (96 pt) → EIN Tisch-Artefakt mit aufliegender Post (Überlappung statt Stapel) → Sesselreihe → Kommode mit fahrenden Schubladenfronten; Scroll-Licht dimmt, was die Lampe nicht ansieht; Pull-to-Refresh ist eine Schnur, kein Spinner. |
| Poststube | `List` mit Bubbles + Sheet für Pins | Die Pins HÄNGEN sichtbar an einer durchhängenden Schnur über dem Stapel; der Composer hat FÄCHER statt eines „+"-Menüs; jede Sendung wird körperlich gestempelt („TAG {n}" — Biografie in der häufigsten Geste); Briefe falten sich per matchedGeometry auf, statt zu pushen. |
| Spielzimmer | Sections mit Karten-Grid pro Kategorie | Partien LIEGEN auf einem Tisch (Ort = Status: auf dem Tisch → läuft; im Regal → wartet); der Katalog steht als Schachtel-RÜCKEN im Brett (vertikale Typo-Silhouette statt Kachel-Einerlei); das Tagesspiel ist ein Kalenderblatt mit Perforation; Trophäen stehen hinter echtem System-Glas — das einzige schwebende Möbel. |
| Küche | Noch ein Hub-Grid mit 7 Kacheln | Ein Raum, in dem die FUNKTIONEN ihre Alltagsform behalten: Plan unter Magneten am Kühlschrank, Listen am Klemmbrett, Sparen als Füllstand im Glas (native Gauge als Wasserlinie), Coupons als Heft mit herauslugendem Scallop-Rand — Typografie-Moment: die Türchen-Prägezahlen und Datumszeilen in `Typo.anschrift`. |
| Dachboden | `LazyVGrid` mit 14 identischen Tiles | Masonry aus ungleich hohen KISTEN mit Papier-Etiketten (Serif-Momente), die sich per nativem Zoom ÖFFNEN statt zu navigieren; Stats sind Striche am Türrahmen; der Tresor ist eine dunklere Truhe abseits, nicht Tile Nr. 14; die Tages-Erinnerung muss ENTWICKELT werden — Warten als Geste. |
| Kammer | Settings-Tab mit 9 Karten | Kein Tab: ein Schlüssel, ein Sheet, fünf benannte Wandzonen, native Form — der Kontrast „stiller Werkzeugraum vs. komponierte Zimmer" IST die Aussage; Hebel klicken schwer, sonst passiert nichts Schmückendes. |

Quer durch alle Zimmer: **Ort ersetzt Label** (Status wird räumlich erzählt),
**Überlappung ersetzt Stapelung** (Papier liegt AUF Dingen), **eine Handwerks-Geste pro
Zimmer** (Zug, Stempel, Ziehen, Magnet, Entwickeln) statt sechs gleicher Taps — und alles
davon in Token-Sprache, ratchet-fähig, ohne ein einziges Bitmap-Asset.

---

## 5. Ordner-Neubau: der Zielbaum

### 5.1 Zielbaum `SoooDreamy/ios/SoooDreamy/`

```
ios/SoooDreamy/
├── App/                    # Haus-Shell (unverändert benannt): SoooDreamyApp, AppState,
│                           # RootView, TodayAccessoryView, ScreenshotSeed, AppStatePlatform
├── Design/                 # ← UI/ (Design-System, EINZIGER Rohwerte-Ort)
├── Kern/                   # ← Core/ (API, Sockets, Haptik, Sound, Krypto … 1:1)
├── Fundament/              # ← Content/ (die Gesetzestafeln; Foundation-only)
│   └── Kataloge/           # ← Content/Data/
├── Zimmer/
│   ├── Wohnzimmer/         # 31 Dateien (Bühne, Tisch, Sessel, Kommode, Rituale)
│   ├── Poststube/          # 12 Dateien (Stapel, Leine, Schreibtisch, Briefe, Zeitpost, Kapseln)
│   ├── Spielzimmer/
│   │   └── Spiele/         # 39 Dateien (Tisch/Regal/Vitrine im Root, alle Spiel-Views in Spiele/)
│   ├── Kueche/             # 9 Dateien (Kühlschrank, Kalender, Klemmbrett, Gläser, Abend)
│   ├── Dachboden/          # 23 Dateien (Kisten, Chronik, Messlatte, Truhe)
│   └── Kammer/             # 19 Dateien (← Settings/ + WhatsNew)
├── Werkstatt/              # geteilte Feature-Bausteine (raumlose Momente & Zeremonien)
│   ├── Momente/            # TouchReceivedOverlay, PostNoteOverlay
│   └── Zeremonien/         # RevealCeremonyView, PairingCeremonyView
├── Kino/                   # ← Onboarding/ (Kino, Rundgang, Pairing, Recovery, QR)
├── Intents/                # bleibt
└── Resources/              # bleibt
```

Unverändert auf `ios/`-Ebene (Target-Grenzen): `Shared/`, `Widgets/`, `LogicTests/`,
`UITests/`, `Config/`, `scripts/`, `Package.swift`, `project.yml`. `project.yml` liest
per Glob (`path: SoooDreamy`) — der Umbau braucht dort KEINE Änderung.

### 5.2 Datei-Mapping (git-mv-fähig; Welle Z0 ist ein reiner Move ohne Code-Diff)

Swift hat flache Namensräume im Target — reine `git mv` brechen keinen Build. Dateinamen
bleiben in Z0 erhalten (Typ-Umbenennungen wie `DashboardView → WohnzimmerView` passieren
erst in der Welle, die den jeweiligen Screen umkomponiert).

**Regel-Zeilen (1:1-Umzüge ganzer Bäume):**

| Heute | Neu | Bemerkung |
|---|---|---|
| `UI/*` (11 Dateien: Theme, Glass, Components, PaperControls, GlassSkeleton, GlassMedal, HeartBurstView, Iconography, Lichtschein, PencilInput, SeasonEffectsView) | `Design/*` | Ratchet-Scope `!**/UI/*` → `!**/Design/*` (§5.3) |
| `Core/*` (alle ~50) | `Kern/*` | Package.swift: ~25 Pfade sed-en |
| `Content/*` (alle Gesetze) | `Fundament/*` | Package.swift: ~55 Pfade |
| `Content/Data/*` (14 Kataloge) | `Fundament/Kataloge/*` | Package.swift: 14 Pfade |
| `App/*` (6) | `App/*` | bleibt |
| `Intents/`, `Resources/` | unverändert | — |

**Features → Zimmer (jede Datei einzeln):**

*Zimmer/Wohnzimmer/ (31):* aus `Features/Home/`: `DashboardView.swift` (→ Welle Z2:
`WohnzimmerView.swift`), `DashboardHeaderView.swift` (→ `Fensterbank.swift`),
`DailyQuestionCard.swift`, `DailySparkCard.swift`, `FirstMomentCard.swift`,
`CheckinCard.swift`, `TouchGridCard.swift` (→ `Sessel.swift`), `PulseFan.swift`,
`MissedInboxCard.swift`, `MoodPickerSheet.swift`, `PresenceViews.swift`,
`WaitingForPartnerCard.swift`, `QuestCard.swift`, `LevelCard.swift`,
`BadgeShelfView.swift`, `StreakCalendarView.swift`, `Heart3DView.swift`,
`HugQueueView.swift`, `DuetView.swift`, `HapticStudioView.swift`, `PlatformL10n.swift`
(Package.swift-Pfad!); aus `Features/Rituals/`: `RitualsDashboardSection.swift`
(→ `Kommode.swift`), `DaymemoView.swift`, `NeedsHistoryView.swift`,
`RepairConsiderationView.swift`, `WeekReviewView.swift`, `CustomQuestionsView.swift`,
`RitualsAPI.swift`, `RitualsAppState.swift`, `RitualsModels.swift`, `RitualsL10n.swift`
(Package.swift-Pfad!).

*Zimmer/Poststube/ (12):* aus `Features/Chat/`: `ChatView.swift`, `ChatModel.swift`,
`ChatPaper.swift`, `ChatL10n.swift` (Package.swift-Pfad!), `LetterComposeView.swift`,
`LetterWorkshopView.swift`, `LetterSeals.swift`, `PinnedMessages.swift` (→ `Leine.swift`),
`VoiceNotes.swift`; aus `Features/Home/`: `ZeitpostView.swift`, `PostJournalView.swift`;
aus `Features/Rituals/`: `CapsulesView.swift`.

*Zimmer/Spielzimmer/ (Root) + Spiele/ (39):* Root: `PlayHubView.swift` (→ Z3:
`SpielzimmerView.swift`), `GameTableView.swift` (→ `Spieltisch.swift`),
`GamesCoordinator.swift`, `GamesAppState.swift`, `GameEngine.swift`, `GamesA11y.swift`,
`GamesPaperKit.swift`, `GamesL10n.swift` (Package.swift-Pfad!), `GamesRecordView.swift`,
`ReplayView.swift`, `TournamentView.swift`, `DailyQuestsView.swift`, `WordleView.swift`,
`WordleRecordView.swift`, `GamesWaveView.swift`; `Spiele/`: `BattleshipView.swift`,
`BoardDuelKit.swift`, `ChoiceGamesView.swift`, `ConnectFourView.swift`, `DameView.swift`,
`EmojiRiddleLiveView.swift`, `EmojiRiddleView.swift`, `GomokuView.swift`,
`KaesekaestchenView.swift`, `KniffelView.swift`, `MancalaView.swift`,
`MemoryDuoView.swift`, `MovieRouletteView.swift`, `PhotoMemoryView.swift`,
`PictionaryView.swift`, `Questions36View.swift`, `QuizDuelView.swift`,
`QuizGameView.swift`, `ReversiView.swift`, `StadtLandFlussView.swift`,
`TruthOrDareLiveView.swift`, `TruthOrDareView.swift`, `TwoTruthsView.swift`,
`WordPartyGamesView.swift`.

*Zimmer/Kueche/ (9):* `Features/Rituals/WeekplanView.swift` (→ `Kuehlschrank.swift` in
Z3), `Features/Rituals/SeasonCalendarView.swift` (→ `Wandkalender`-Detail),
`Features/Rituals/GoalsView.swift` (→ `Sparglas`), `Features/Memories/SharedListsView.swift`
(→ `Klemmbrett`), `Features/Memories/BucketListView.swift`,
`Features/Memories/CouponsView.swift`, `Features/Memories/EventsView.swift`,
`Features/Home/DateNightView.swift`, `Features/Games/DateIdeasView.swift`
(→ `Rezeptbox`). Neu in Z1: `KuecheView.swift` (Root).

*Zimmer/Dachboden/ (23):* aus `Features/Memories/`: `MemoriesView.swift` (→ Z3:
`DachbodenView.swift`), `MemoriesHubComponents.swift`, `MemoriesL10n.swift`
(Package.swift-Pfad!), `GalleryView.swift`, `GalleryComponents.swift`,
`GalleryPagerView.swift`, `MediaLightbox.swift`, `VideoGalleryView.swift`,
`VideoPlayerScreen.swift`, `PotdView.swift`, `OnThisDayCard.swift`, `JournalView.swift`,
`StoryModels.swift`, `StoryTimelineView.swift`, `YearReviewView.swift`,
`LoveStatsView.swift` (→ `Messlatte`), `SoundtrackView.swift` (→ `Plattenkiste`),
`CanvasView.swift` (→ `Staffelei`), `CanvasExportSheet.swift`, `VaultView.swift`
(→ `Truhe`), `VaultItemViewer.swift`; aus `Features/Rituals/`: `MagazineView.swift`
(Chronik); aus `Features/Home/`: `FlashbackCard.swift` (Polaroid-Zone).

*Zimmer/Kammer/ (19):* alle 18 aus `Features/Settings/` (`SettingsView.swift` → Z1:
`KammerView.swift`; `SettingsL10n.swift` + `IntelligenceL10n.swift` sind
Package.swift-Pfade!) + `Features/Home/WhatsNewView.swift`.

*Werkstatt/ (5):* `Momente/`: `Features/Home/TouchReceivedOverlay.swift`,
`Features/Home/PostNoteOverlay.swift`; `Zeremonien/`:
`Features/Home/RevealCeremonyView.swift`, `Features/Onboarding/PairingCeremonyView.swift`;
Root: `Features/Onboarding/DemoBadge.swift`.

*Kino/ (9):* aus `Features/Onboarding/`: `CinematicIntroView.swift`,
`CinematicChapterPlayer.swift`, `CinematicChapterStages.swift`, `CinematicHandoff.swift`,
`OnboardingFlowView.swift` (→ Z4: `Rundgang.swift`), `OnboardingL10n.swift`
(Package.swift-Pfad!), `PairingView.swift`, `QRSupport.swift`, `RecoveryViews.swift`.

Kontrollsumme: 31 + 12 + 39 + 9 + 23 + 19 + 5 + 9 = **147** = heutiger
`Features/`-Bestand. Kein Verlust, keine Doppelung.

### 5.3 Was der Umzug anfassen MUSS (im selben Commit wie die Moves)

1. **`ios/Package.swift`** — listet Logic-Quellen EXPLIZIT: alle `Content/` → `Fundament/`,
   `Content/Data/` → `Fundament/Kataloge/`, `Core/` → `Kern/` sowie die 8 umgezogenen
   L10n-Pfade (`Chat/ChatL10n` → `Zimmer/Poststube/ChatL10n` usw.). Mechanisch:
   `sed -i 's|SoooDreamy/Content/Data/|SoooDreamy/Fundament/Kataloge/|; s|SoooDreamy/Content/|SoooDreamy/Fundament/|; s|SoooDreamy/Core/|SoooDreamy/Kern/|' ios/Package.swift`
   plus die 8 L10n-Zeilen von Hand. Beweis: `swift test` auf Linux, unverändert grün.
2. **`tools/charter_lint.sh`** — Pfad-Scopes: alle `ios/SoooDreamy/Features`-Vorkommen →
   `ios/SoooDreamy/Zimmer ios/SoooDreamy/Werkstatt ios/SoooDreamy/Kino`; die Globs
   `!**/UI/*` und `**/UI/Theme.swift` → `Design/`. Die Baseline wird NICHT angefasst:
   ein reiner Move ändert keinen Zähler — genau das ist der Z0-Beweis
   (`bash tools/charter_lint.sh` vorher/nachher, identische Zahlen).
3. **`ios/.swiftlint.yml`** — dieselben zwei Scope-Regexe (`.*Features/.*` →
   `.*(Zimmer|Werkstatt|Kino)/.*`, `.*UI/Theme\.swift` → `.*Design/Theme\.swift`).
4. **Doku-Nachzug (eigene kleine Welle, wie MIGRATION_DUNKEL §9):** `DESIGN.md` nennt
   `ios/SoooDreamy/UI/` als Rohwerte-Ort — Pfadangaben auf `Design/` ziehen.

---

## 6. Onboarding-Anschluss: das Kino mündet ins Haus

Das bestehende Kino bleibt Szene für Szene (Sprach-Gate = Lampenklick wartet beliebig;
Kapitel 2–6 Umschlag/Siegelbruch/Tintenfässer/Wachsguss/Polaroid; Hybrid-Regel
Video/Bühne unangetastet). Der Anschluss wird stärker, weil die Requisiten jetzt Adressen
haben: Der Umschlag aus Kapitel 2 wohnt in der Poststube, das Polaroid aus Kapitel 6
liegt auf dem Dachboden — das Kino zeigt nichts, was es danach nicht mehr gibt.

**Zwei präzise Änderungen:**

1. **Der Rundgang ersetzt die vier Erklärseiten.** Nach dem Kino zeigt der Guide EINE
   Seite: den **Grundriss** — eine Tusche-Zeichnung des Hauses (reines `Canvas`,
   `Papier.aufNacht`-Linien auf Nacht, gezeichnet mit `drift`-Strichanimation; Reduce
   Motion: steht sofort). Die fünf Zimmer leuchten nacheinander kurz im Lampengold auf,
   je mit Namensschild — kleiner `Papier.karton`-Streifen, Beschriftung `Typo.anschrift`
   (Serif auf Papier ✓). Die Kammer ist eine Nische mit Schlüsselhaken. Drei **Türen**
   am Fuß des Grundrisses sind die drei heutigen Einstiege — Partner-QR scannen, eigener
   Server, „Erst mal ansehen" (Demo) — mit stabilen IDs `onboarding.path.scan/server/demo`
   und denselben `CinematicHandoff`-Ankern: Kapitel 7 legt seine Papiere wie heute
   punktgenau auf Wortmarke + Türen (der Morph-Vertrag `CinematicHandoffElement` bleibt,
   er bekommt nur das neue Ziel-Layout gemeldet).
2. **Erstbetreten statt Coachmarks.** Nach dem Pairing spielt jedes Zimmer beim ERSTEN
   Betreten einen 1,2-s-„Licht an"-Moment (einmalig, `@AppStorage
   zimmer.erleuchtet.<raum>`): Lichtschein-Signatur + das Namensschild des Zimmers, dann
   Ruhe für immer. Delight-Stufe 1, niemals `epic` (Gebot 4); VoiceOver sagt den
   Zimmernamen und den einen Satz Zweck an. Der Arrival-Morph aus Kapitel 7 endet damit
   nicht mehr in „irgendeinem Dashboard", sondern wörtlich im Wohnzimmer: das Tagesfrage-
   Papier aus dem Kino legt sich auf den Tisch-Rect (Handoff-Anker `.tisch`), die
   Glas-TabView gleitet herauf — erste Nacht im Zimmer, nahtlos in den Alltag.

---

## 7. Migrationsplan: vier Wellen

**Grundregel jeder Welle:** Funktion vor Bühne (kein Screen verliert je eine Fähigkeit,
auch nicht für einen Commit), Ratchets im selben Commit (`charter_lint.sh --update` nur
für SINKENDE Zähler), jede neue Fläche registriert ihre fünf Zustände in `PolishAudit`
vor dem Merge.

**Z0 — Umzugskartons (reiner Struktur-Commit).** Alle `git mv` aus §5.2, Package.swift-
Pfade, Lint-Scopes (§5.3). NULL Verhaltensänderung. *Beweis (Gate für alles Weitere):*
`swift test` grün · `charter_lint.sh` mit IDENTISCHEN Zählern · `xcodegen generate` +
Simulator-Build · kompletter UITest-Lauf unverändert grün. *Risiko:* klein; größte
Fehlerquelle sind vergessene Package.swift-L10n-Pfade — der Linux-Test fängt genau das.

**Z1 — Haus-Gerüst: Küche-Tab & Kammer-Tür.** `AppTab` bekommt `.kueche`, verliert
`.settings`; `MainTabView` mit fünf Zimmer-Tabs + `.tint(blend)` + Accessory unverändert;
Hausschlüssel-ToolbarItem in allen Zimmern; Kammer = `KammerView` als Sheet (Inhalt =
heutige SettingsView-Sections, nur umgruppiert in die fünf Wandzonen); Küche V1 =
funktionaler Root (die neun umgezogenen Ziele als schlichte nightCards — Bühne kommt in
Z3); Wir verliert die Plan-Kacheln. UITest-Migrationsliste (§2.3) und
`ScreenshotSeed`-Staging (Tab-Keys der Screenshot-Matrix) im selben Commit. ⌘1–5 auf die
neue Zimmer-Reihenfolge, ⌘, öffnet die Kammer. *Beweis:* UITests grün (test02 mit
`kammer.tuer`), Screenshot-Matrix inkl. `paired-ax5-de` neu abgenommen. *Risiko:* der
IA-Bruch schlechthin — deshalb früh, klein und isoliert, VOR jeder Bühne.

**Z2 — Wohnzimmer & Poststube (die täglichen 80 %).** Wohnzimmer-Bühne (Fensterbank,
Tisch mit aufliegender Post, Sessel, Kommode, Kaminsims; `Zimmer.*`-Tokens entstehen in
`Design/Theme.swift`), Lampenzug; Poststube-Bühne (Leine als Zone, Schreibtisch-Fächer,
Kapselregal, Postfach), Poststempel-Schlag. Vorher-Pflicht: `ChatView.swift` (2 707
Zeilen) wird in Zonen-Dateien zerlegt (`Leine`/`Stapel`/`Schreibtisch`), SONST wird der
Xcode-Typecheck zum Blocker. *Beweis:* test04/test05 grün (Stationen-IDs stabil),
AX5-Shots beider Zimmer, Artefakt-Inventur ≤ 3/1/1 pro Screen, Flugmodus-Probe (Gebot 8).
*Risiko:* Typecheck-Zeiten, Rotation-Budget der Leine (nur neuester Zettel), Feier-Budget
des Stempels (bewusst klanglos).

**Z3 — Spielzimmer, Küche-Bühne, Dachboden.** Spieltisch/Regal/Abreißkalender/Vitrine +
Vom-Stapel-ziehen; Küche V2 (Kühlschrank-Komposition, Magnet setzen, Gläser-Zeile);
Dachboden (Kisten-Masonry, Zoom-Transitions, Polaroid entwickeln, `.searchable`,
Regalwand-Split auf iPad). Riss-Budget wird VOR dem Bau gebucht: `torn_edge_uses`-Bestand
zählen; nur wenn < 6, bekommt der Abreißkalender den echten Riss, sonst dauerhaft die
gestanzte Perforation. *Beweis:* Draw-Call-/Scroll-Probe des Regals (40 Schachteln als
zwei-drei zusammengefasste Zeilen, nicht 40 Einzelkarten), UITest-Erweiterung Küche
(neue `kueche.*`-IDs), fünf Zustände je neuer Fläche in `PolishAudit`. *Risiko:* größter
Layout-Umfang; die Küche darf an leeren Tagen nicht tot wirken (leere Zustände mit Verb
+ Knopf sind Abnahme-Kriterium, Gebot des leeren Zustands).

**Z4 — Kino-Rundgang & Feinschliff.** Grundriss-Guide + Erstbetreten-Momente +
Handoff-Anker `.tisch`; iPad-Pässe aller Zimmer (Pult, Schrankwand, Kühlschranktür,
Regalwand); Ratchet-Ernte (`surface_glass_features` etc. einrasten); Doku-Welle
(DESIGN.md-Pfade, dieses Dossier auf „umgesetzt" stempeln). *Beweis:* kompletter
First-Run auf Gerät (Kino → Grundriss → Pairing → Wohnzimmer ohne Schnitt), Reduce-Motion-
und VoiceOver-Durchlauf aller fünf Signature-Momente (Gebot 13: drei Pfade je Moment).

**Was zuerst beweisbar sein muss (Reihenfolge der Beweise):** (1) Z0-Invarianz — der
Umzug ändert NICHTS Messbares; (2) Z1-IA — Küche-Tab + Kammer-Tür überleben die komplette
UITest-Journey; (3) erst DANN darf Bühne gebaut werden. Wer die Reihenfolge umdreht,
debuggt Bühnenbilder auf einem wackligen Fundament.

---

## 8. Selbstkritik: die fünf härtesten Schwächen dieser Richtung

1. **Die Kammer-Entscheidung ist der riskanteste Einzelzug.** Settings aus der Tab-Bar zu
   nehmen bricht Muskelgedächtnis und den `tab.settings`-Vertrag; wenn Nutzer den
   Schlüssel nicht finden, wirkt das Haus nicht charmant, sondern verschlossen. Der
   Erstbetreten-Hinweis und die IMMER-gleiche Position mildern das — aber wenn die Jury
   nur EINE Entscheidung kippt, ist es diese, und dann braucht die Küche einen anderen
   Platz (oder sie fällt, und mit ihr das stärkste Anti-Generik-Argument).
2. **Möbel-Metaphern altern Richtung Kitsch.** Zwischen Bühnenbild und Bastelladen liegen
   nur die PaperRules-Budgets: Schnur, Stempel, Magnete, Kisten, Hebel sind fünf neue
   Gelegenheiten, die 3/1/1-Regel zu reißen oder Game-Center-Filz zu reproduzieren. Die
   Charta schützt mechanisch — aber Geschmack bleibt Review-Handarbeit, und dieses Konzept
   erhöht die Zahl der Stellen, an denen Geschmack versagen kann.
3. **Bühnen kosten Dynamic-Type-Robustheit.** Feste Zonen (Fensterbank 96, Regalbrett 148,
   Magnettafel) kollidieren strukturell mit AX5; jede Bühne braucht den zweiten,
   gestapelten AX-Pfad. Das ist doppelte Layout-Arbeit pro Zimmer und die wahrscheinlichste
   Quelle von `paired-ax5-de`-Regressionen — die Generik der heutigen Kartenstapel ist
   in GENAU dieser Disziplin überlegen.
4. **Die Küche kann dünn wirken.** An Tagen ohne Pläne ist sie ein Raum voller leerer
   Möbel — und damit wäre ausgerechnet das Alleinstellungs-Zimmer das langweiligste. Leere
   Zustände müssen dort mehr leisten als überall sonst (Einladung mit Verb, Magnet zum
   Anfassen), und wenn ein Paar die Plan-Features schlicht nie nutzt, trägt ein ganzer
   Tab wenig — das heutige Wir-Grid versteckt diese Schwäche gnädiger.
5. **Der Gewinn ist ungleich verteilt, der Umbau flächendeckend.** Wohnzimmer + Poststube
   tragen den Alltag; wenn nach Z2 die Luft ausgeht, steht ein halbes Haus — komponierte
   Zimmer neben Kartenstapel-Zimmern wirken inkonsistenter als der heutige einheitliche
   Katalog. Die Funktion-vor-Bühne-Regel und die Wellen-Schnitte sind genau dagegen
   gebaut, aber das Restrisiko „ewiger Rohbau" ist real und wäre schlimmer als der
   Status quo.

---

*Zimmerhaus-Dossier für den Neubau-Wettbewerb. Ein Haus, eine Lampe, fünf Zimmer, eine
Kammer — und kein einziger Screen, der mit einer anderen App verwechselbar wäre.*
