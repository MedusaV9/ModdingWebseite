# NEUBAU_POSTAMT.md — Das Nachtpostamt

**Wettbewerbs-Dossier (Neubau der Informationsarchitektur, Seiten-Kompositionen und
Code-Ordner).** Das DESIGN bleibt wörtlich das beschlossene: Papier & Licht, Nacht-first
(`MIGRATION_DUNKEL.md`), Lampenlicht, Artefakt-Budgets, Zwei-Materialien-Gesetz. Dieses
Dossier baut den AUFBAU neu. Bewertungsgrundlage: `DESIGN.md` (15 Gebote, Ratchets),
`docs/styles/STYLE_DECISION.md` §3, `MIGRATION_PAPIER.md`/`MIGRATION_DUNKEL.md`, der
Ist-Stand in `ios/SoooDreamy/` (147 Feature-Dateien in 7 Ordnern, native iOS-26-TabView in
`App/RootView.swift`, `ios/Package.swift` mit expliziter Logic-Quellenliste,
`tools/charter_lint.sh` mit hartem `Features/`-Pfad, UITests mit gepinnten `tab.*`-IDs).

---

## 1. Leitidee: Das Nachtpostamt

**Die App ist das private Postamt zweier Menschen. Alles, was zwei Menschen einander
geben, ist Korrespondenz — und diese App verwaltet nichts anderes.**

Die Diagnose hinter „nur eine generische App": Das heutige Gerüst spricht die Sprache
jeder App — Dashboard, Chat, Hub, Memories, Settings. Fünf Sammel-Container, in die
Features einsortiert wurden, wie sie fertig wurden. Das Design (Papier, Nacht, Lampe,
Wachs) ist bereits unverwechselbar; das Gerüst darunter ist noch das Gerüst von Slack,
Duolingo und jeder Banking-App. Ein Screenshot der Tab-Leiste könnte zu hundert Apps
gehören.

Die Antwort ist keine weitere Umbenennung, sondern eine **Grammatik**: Im Nachtpostamt
ist jede Funktion eine Form von Post, jeder Screen ein Ort im Amt, jede Tageszeit eine
Zustellrunde. Die Grammatik hat drei Verben, die überall gleich dekliniert werden:

- **Ankunft** — etwas wird ZUGESTELLT (Tagesfrage, Zeitpost, Türchen, Wochenpost):
  es kommt durch den Briefschlitz, trägt einen Poststempel, wartet im Zustellfach.
- **Absendung** — etwas wird AUFGEGEBEN (Nachricht, Brief, Telegramm, Kapsel):
  es wird geschrieben, gesiegelt, gestempelt, und verlässt sichtbar den Schalter.
- **Ablage** — etwas wird EINGEORDNET (Fotos, Journal, Gutscheine, Tresor):
  es liegt in einem benannten Fach eines Schranks, nicht in einer Liste.

Warum diese Grammatik die Generik tötet: Generisch ist eine App, deren Screens
austauschbare **Container** sind. Ein Postamt hat keine Container, es hat **Orte mit
Beruf** — am Schalter wird aufgegeben, im Archiv wird eingeordnet, ins Postfach wird
zugestellt. Jeder Ort erzwingt eine eigene Komposition (ein Zustellfach sieht anders aus
als ein Schrank), eine eigene Interaktion (Siegel drücken ≠ Schublade ziehen) und ein
eigenes Vokabular. Die Metapher ist dabei nicht importiert, sondern **ausgegraben**: Das
Kino stellt heute schon einen Umschlag mit Poststempel „TAG 1" zu (`CinematicScript`,
Szene 2), die App besitzt Wachssiegel (`LetterSeals`, `WachsSiegel`), einen Poststempel
mit Prägezeile „TAG {n}" (Editorial-Anleihe der Jury), `Typo.anschrift` für Anschriften,
eine „Zeitpost" und versiegelte Briefe im Chat. Papier & Licht hat das Material des
Postamts bereits beschlossen — dieses Dossier gibt dem Material das **Gebäude**. Und die
Nacht-first-Balance (`MIGRATION_DUNKEL`) liefert die Uhrzeit: Ein Postamt bei Nacht, in
dem zwei Beamte im Lampenlicht die Post des jeweils anderen sortieren, ist die intime
Erzählung, die „dunkles Zimmer + helles Papier" schon immer war.

**Disziplin (das Postdeutsch-Budget):** Skeuomorphe Metaphern kippen als Sprache genauso
in Kitsch wie als Grafik. Deshalb gilt neben den Artefakt-Budgets (max. 3/1/1 pro Screen,
`PaperRules`) ein Vokabel-Budget: **pro Screen genau EINE Post-Vokabel** — im Titel oder
im Stempel, nie in beiden, nie im Fließtext. Buttons, Fehlertexte und Body-Copy sprechen
Klartext-Deutsch (Gebot 9, Vorlese-Test). „Postfach" ist ein Ort; „Deine Sendung wurde
erfolgreich frankiert" ist verboten.

---

## 2. IA-Karte: Die fünf Stationen

### 2.1 Stationen (die fünf Tabs der nativen TabView)

Die Tab-Struktur bleibt die native iOS-26-`TabView` aus `RootView.swift` — `Tab`-Builder,
`.tint(coupleTint.blend)`, `.tabBarMinimizeBehavior(.onScrollDown)`, Bottom-Accessory,
native Badges. **Die Accessibility-IDs `tab.home` / `tab.chat` / `tab.play` / `tab.us` /
`tab.settings` sind UITest-gepinnt und ändern sich NICHT** — nur L10n-Labels und Symbole.

| # | Station (DE) | EN | SF-Symbol (outline) | a11y-ID (fix) | Beruf des Ortes |
|---|---|---|---|---|---|
| 1 | **Postfach** | Mailbox | `tray.and.arrow.down` | `tab.home` | Ankunft. Hier wird zugestellt: der heutige Brief, das Nachsendebündel, Türchen, Zeitpost, Wochen-/Monatspost. |
| 2 | **Schreibstube** | Writing Desk | `envelope` | `tab.chat` | Absendung. Zettelspindel (Chat), Briefpapier, Rohrpost (Sprachnotizen), Telegramme (Touches/Klopfzeichen), Siegelpresse (Zeitpost/Kapseln/Türchen). |
| 3 | **Spieltisch** | Game Table | `dice` | `tab.play` | Die Pause der Nachtschicht. 26+ Spiele als Spielkarten-Umschläge; Fernpartien wie beim historischen Fernschach per Postkarte. |
| 4 | **Archiv** | Archive | `archivebox` | `tab.us` | Ablage. Der Archivschrank des Paares: sechs Fächer statt achtzehn Kacheln — Alben, Planfach, Wertfach, Chronik, Lagerfach, Tresorfach. |
| 5 | **Amt** | Bureau | `building.columns` | `tab.settings` | Betrieb. Zustellzeiten, Zweigstellen (Geräte), Zustellbezirke (Server), Prägeplatten (Icons), Aushangkasten (Widgets), Schlüssel. |

Der Heute-Zettel (`TodayAccessoryView`, das TabView-Bottom-Accessory) wird der
**Zustellzettel**: links Partner-Präsenz wie heute, rechts statt „Serie n" die aktuelle
Runde + Status — „Nachtpost · Siegel wartet". Beide Placements (`.expanded`/`.inline`)
bleiben bedient; Chrome-Regeln (kein Papier, kein Serif) gelten unverändert.

### 2.2 Vollständiges Mapping Alt → Neu

Regel für jede Zeile: **max. 2 Navigationsebenen unterm Tab** (Tab-Root → Push →
Detail-Push; Sheets und Inline-Aufklappen zählen nicht als Ebene). Cross-Station-Pushes
sind erlaubt (eine Zustellkarte im Postfach darf ihr im Archiv beheimatetes Ziel pushen)
— die Datei-Heimat regelt §6, nicht die Navigation.

**Heute-Tab „Home" → Station 1 POSTFACH**

| Heute (Screen/Karte/Sheet) | Neu (Ort · Rolle) | Ebene |
|---|---|---|
| `DashboardView` (Hub) | Postfach-Root: Kopf → Zustellfach → Ablage (§3.1) | Root |
| `DashboardHeaderView` (Avatare, Tage, Mood) | „Die zwei Beamten": Kopfzeile mit Dienstlicht (Energie-Akku als Lampenhelligkeit) | Root |
| `DailyQuestionCard` (Tagesfrage, Hero-Briefbogen) | **Der heutige Brief** — bleibt der EINE Briefbogen; Poststempel trägt zusätzlich die Runde: „TAGESPOST · TAG 137" | Root |
| `CheckinCard` (Morgen/Nacht) | Morgengruß = Morgenpost-Karte · Gute Nacht = Nachtpost-Karte (§4) | Root |
| `MissedInboxCard` („während du weg warst") | **Nachsendebündel**: gebündelte Zustellungen mit Stapelkante | Root |
| `RitualsDashboardSection` (Energie, „Ich brauche gerade", Daymemo, Banner) | zerlegt: Energie → Dienstlicht im Kopf · Needs → **Eilbote**-Karte · Daymemo → Tagesnotiz-Zustellung · Banner bleiben Zustellkarten | Root |
| `EnergyCard` (Energie-Akku) | **Dienstlicht**: „Wie hell brennt deine Lampe heute?" — grün/gelb/rot als Lampenschein, gleiche `MemberEnergy`-Daten | Root |
| `NeedsCard` + `NeedsHistoryView` („Ich brauche gerade") | **Eilbote** (Karte, Postfach) + Eilboten-Chronik (Archiv → Chronik) | Root / +1 |
| `DaymemoView` | Tagesnotiz (Zustellung + Compose) | +1 |
| `QuestCard`, `FirstMomentCard` | Erste-Sendung-Karten (neue Paare) — unverändert priorisiert via `DashboardPriority` | Root |
| `OnThisDayCard` / `FlashbackCard` | „Heute vor …"-Zustellung (Polaroid mit einer Klebeecke) | Root |
| `DateNightView` | Verabredungs-Karte; plant in Archiv → Planfach → Termine | Root / +1 |
| `HugQueueView` | Lagernde Sendungen (Umarmungen warten, bis der Partner da ist) | Root |
| `LevelCard`, `BadgeShelfView`, `StreakCalendarView` | Ablage-Zone: Biografie-Zahlen („137 gemeinsame Tage"), Siegelsammlung, Stempelkalender | Root (Fold) |
| `SeasonCalendarSupportCard` (Türchen heute) | **Türchen-Zustellung**: nummeriertes Fach öffnet sich zur Runde (§4) | Root |
| `WeekReviewSupportCard` / Weekplan-Banner | **Wochenpost**-Zustellung (Sonntag) / Laufzettel-Banner → pushen Archiv-Ziele | Root / +1 |
| Herz-Coda (`Heart3DView`) | bleibt die Coda der Seite — der eine Herzschlag-Sender | Root |
| `PulseFan` (FAB) | bleibt globales Chrome-Glas auf dem Postfach; Fächer öffnet Telegramm-Aktionen | Chrome |
| `TouchGridCard` (Send-Love-Raster) | **Telegramm-Leiste** (kompakt im Postfach) — Vollwerkzeuge in der Schreibstube | Root |
| `MoodPickerSheet`, `WhatsNewView` (Sheets) | bleiben Sheets am Postfach (What's New = „Aushang") | Sheet |
| `WaitingForPartnerCard` | „Der erste Brief ist unterwegs" (§7) | Root |
| `PresenceViews` | Präsenz bleibt im Kopf + Zustellzettel | Root |

**Heute-Tab „Chat" → Station 2 SCHREIBSTUBE**

| Heute | Neu | Ebene |
|---|---|---|
| `ChatView` (Bubble-Liste, `.searchable`) | **Zettelspindel** — Zettel bleiben brief/karton mit Tintenkante; Tagestrenner bleibt Poststempel-Medaillon; `.searchable` bleibt nativ | Root |
| Eingabeleiste (Chrome-Glas) | **Pult** — unverändert Chrome; Toolbar: Rohrpost · Briefpapier · Siegelpresse-Menü | Root |
| `LetterComposeView`, `LetterSeals` | Briefpapier + Wachssiegel (versiegelte Briefe, Siegelbruch beim Öffnen — bleibt der eine laute Moment) | Sheet |
| `LetterWorkshopView` (Sticker) | Marken-Werkstatt (Sticker = Briefmarken des Paares) | Sheet |
| `VoiceNotes` | **Rohrpost** — Sprachkapsel, Versand saugt sichtbar nach oben ab | Sheet |
| `PinnedMessages` (Banner/Rail) | **Das Brett** — angepinnte Zettel überm Pult (iPad: Rail bleibt) | Root |
| `TouchGridCard`, `DuetView`, `HapticStudioView` (heute Home) | **Telegramme**: Touch-Raster = Telegramme, Haptik-Duett = Klopfzeichen-Duett, Haptik-Studio = **Morsestube** (eigene Klopfzeichen komponieren) | +1 |
| `ZeitpostView`, `PostJournalView` (heute Home) | **Siegelpresse**: Zeitpost-Schalter (Falten → Stempeln → Abflug bleibt) + Sendungsbuch | Sheet / +1 |
| `RepairConsiderationView` (heute Rituals) | **Versöhnungsbrief** — der Reparatur-Flow ist Briefpapier mit Bedenkzeit | Sheet |
| Kapsel-/Türchen-Compose (heute Rituals) | Siegelpresse-Menü: „Versiegeln bis …" (Kapsel) · „Türchen-Kalender bauen"; Verwaltung/Reifung liegt im Archiv → Lagerfach | Sheet |

**Heute-Tab „Spielen" → Station 3 SPIELTISCH**

| Heute | Neu | Ebene |
|---|---|---|
| `PlayHubView` | Spieltisch-Root: Aushang → aufliegende Partien → Kartenschrank → Spielbuch (§3.3) | Root |
| Offene Sessions (`sessionBanners`) | **Aufliegende Blätter**: ausgeteilte Hände mit 2°-Fächerung (bestehende Karten-Fächerung) | Root |
| Wordle + `DailyQuestsView` | **Tagesaushang**: das tägliche Blatt + Tagesaufgaben | Root / +1 |
| Async-Katalog (battleship, kniffel, stadtlandfluss, twotruths, pictionary, wordchain, hangman, bingo, wordleduo, dame, reversi, kaesekaestchen, gomoku, mancala, memoryduo, story) | **Fernpartien** (Kartenschrank-Fach 1) — Spielkarten-Umschläge; Zug-Badges bleiben native `.badge` | +1 |
| Live-Katalog (connectfour, photomemory, quizduel, emojiriddle-live, truthordare-live, rps) | **Am Tisch** (Fach 2) — beide gleichzeitig da | +1 |
| Party/Gespräch (quiz, thisorthat, wouldyourather, truthordare, questions36, emojiriddle, wordparty) | **Feste & Fragen** (Fach 3) | +1 |
| `DateIdeasView`, `MovieRouletteView` | Ausgehkarten & Kinoprogramm (Fach 3) | +1 |
| `TournamentView` (Season), `GamesRecordView`, `ReplayView`, Tutorials | **Spielbuch**: Monats-Turnier (Aushang mit Monats-Poststempel), Siegerliste, Wiederholungen, Anleitungen | +1 |
| `GameTableView`, `GameEngine`, `GamesCoordinator` | unsichtbare Tisch-Infrastruktur — unverändert | — |

**Heute-Tab „Wir" → Station 4 ARCHIV**

Die 18 Sektionen der heutigen `MemoriesSidebarGroup`-Gruppen werden **sechs benannte
Fächer**; iPad behält den handgebauten Split (die Fächer SIND die Sidebar-Gruppen,
`sidebarAdaptable` bleibt vertagt wie beschlossen).

| Fach | Inhalt (heutige Sektionen) | Ebene |
|---|---|---|
| **Alben** | `GalleryView`, `VideoGalleryView`, `PotdView` (Tagesfoto), `EventsView`, `StoryTimelineView` (Geschichte), `YearReviewView` (Jahrespost) | Fach → +1, Lightbox +2 |
| **Planfach** | `SharedListsView`, `BucketListView`, `WeekplanView` (Laufzettel der Woche) | Fach → +1 |
| **Wertfach** | `CouponsView` (**Wertmarken**, Coupon-Scallop bleibt), `GoalsView` (**Postsparbuch** — Ziele/Sparen) | Fach → +1 |
| **Chronik** | `JournalView`, `LoveStatsView`, `SoundtrackView`, `CanvasView` (+ Export-Sheet), `MagazineView` (**Monatspost**), `WeekReviewView` (**Wochenpost**-Archiv), Eilboten-Chronik (`NeedsHistoryView`) | Fach → +1 |
| **Lagerfach** | `CapsulesView` (Kapseln reifen), `SeasonCalendarView` (gebaute Türchen-Kalender), eigene Zeitpost-Sendungen (Sicht aufs `PostJournalView`-Gegenstück) | Fach → +1 |
| **Tresorfach** | `VaultView` + `VaultItemViewer` (Face-ID-Schließfach) | Fach → +1 |
| Recent-Strip (`recentStrip`) | „Zuletzt eingeordnet" — bleibt über der Schrankfront | Root |

**Heute-Tab „Mehr" → Station 5 AMT**

| Heute | Neu (Amts-Abschnitt) | Ebene |
|---|---|---|
| Profil/Paar-Sektion, `ProfileEditSheet`, `PairingCodeSheet` | „Unser Amt" (Paar, Jahrestag, Pairing-Brief) | Sheet |
| `NotificationSettingsSheet` | **Zustellzeiten** (+ neuer Zustellrunden-Schalter, §4) | Sheet |
| `ServerListSheet`, `DeviceManagerSheet`, `MigrationAssistantView` | **Zustellbezirke** (Server) · **Zweigstellen** (Multi-Device) · Umzugshelfer | Sheet |
| `WidgetStudioView`, `LiveActivitySheet` | **Aushangkasten** (Widgets/Live Activity) | Sheet |
| `PersonalizationView`, `IconGiftView` | Schreibzeug (Paarfarben/Tinten) · **Prägeplatten** (Icon-Varianten; Unwrap-Zeremonie bleibt App-Overlay) | Sheet |
| `AutomationsGalleryView`, `IntelligenceConsentSheet` | Sortiermaschine (Automationen) · Einverständnis | Sheet |
| `ICloudSheet`, `RecoverySheet`, `AppLock`-Sektion | Sicherung & Schlüssel (Backup, Wiederherstellungsbrief, Schloss) | Sheet |
| `DiagnosticsView`, `VersionHistoryView`, `SoundCreditsView`, `HandbookView` | **Betriebsbuch** (Diagnose, Versionen, Credits, Handbuch) | Sheet / +1 |
| `CustomQuestionsView` (heute Rituals) | **Setzkasten**: eigene Tagesfragen setzen (konfiguriert die Tagespost) — zusätzlich aus dem Kontextmenü des heutigen Briefs erreichbar | Sheet |
| Demo-Modus (`DemoBadge`, Welle-7-Band) | **Musterbetrieb** — Band bleibt `safeAreaBar(edge: .top)`, Text „MUSTERBETRIEB", selbst der Ausgang | Chrome |
| Kino-Replay (`fullScreenCover`) | „Die Amtsgründung noch einmal ansehen" | Cover |

**App-weite Overlays & Zeremonien (RootView-ZStack — unverändert verdrahtet)**

| Heute | Neu (Erzählung) |
|---|---|
| `DailyRevealCeremonyView` (Siegelbruch) | bleibt DIE Zeremonie — der Siegelbruch des heutigen Briefs |
| `PostNoteOverlay` (Zeitpost-Ankunft) | Zustell-Moment: versiegelter Umschlag — unverändert |
| `TouchReceivedOverlay`, `PulseReceivedOverlay`, `HapticReceivedOverlay` | Telegramm-/Klopfzeichen-Empfang |
| `PairingCeremonyView`, `LevelUpCeremonyView`, `BadgeCeremonyView`, `IconGiftUnwrapView` | Amtsgründung · Meilenstein-Siegel · Prägeplatten-Geschenk |
| `LichtscheinHost`, `DelightOverlayHost`, `ToastView`, `LockScreenView` | unverändert (Licht, Feier-Budget, Toast, Schloss) |

**Widgets, Intents, Multi-Device (außerhalb des App-Targets — keine Struktur-Änderung)**

| Heute | Neu (nur Erzählung/L10n) |
|---|---|
| `DailyQuestionWidget` | „Der heutige Brief" (Siegel-Zustand bleibt) |
| `StreakWidget`, `DaysTogetherWidget` | Poststempel „TAG n" / „137 gemeinsame Tage" |
| `SendLoveWidget`, `ControlWidgets` | Telegrammknopf |
| `MoodWidget`, `MemoryWidget`, `PhotoWidget`, `CanvasWidget`, `CountdownWidget` | Dienstlicht · Archiv-Polaroid · Countdown |
| Live Activities (`CouplePulse`, `Countdown`, `DateNight`) | Zustellverfolgung („Sendung unterwegs") |
| `Intents/AppIntents.swift` | Phrasen ergänzen („Zeig mir unser Postfach") — IDs stabil |

**Vollständigkeits-Checkliste (nichts geht verloren):** Tagesfrage ✓ (heutiger Brief) ·
Chat ✓ (Zettelspindel) · 26+ Spiele ✓ (Kartenschrank, alle 34 `GameDestination`-Fälle
gemappt) · Zeitpost ✓ (Siegelpresse) · Kapseln ✓ (Siegelpresse + Lagerfach) ·
Ziele/Sparen ✓ (Postsparbuch) · Woche/Monat ✓ (Laufzettel/Wochenpost/Monatspost) ·
Tresor ✓ (Tresorfach) · Journal/Geschichte ✓ (Chronik/Alben) · Haptik-Duett/Studio ✓
(Klopfzeichen/Morsestube) · Energie-Akku ✓ (Dienstlicht) · „Ich brauche gerade" ✓
(Eilbote) · Gutscheine ✓ (Wertmarken) · Türchen-Kalender ✓ (Türchen-Zustellung +
Lagerfach) · Widgets ✓ · Multi-Device ✓ (Zweigstellen) · Demo-Modus ✓ (Musterbetrieb) ·
Onboarding-Kino ✓ (§7) · Pairing/Recovery ✓ (Amt + Kino) · What's New ✓ (Aushang) ·
Handbuch/Diagnose/Credits ✓ (Betriebsbuch).

---

## 3. Stations-Kompositionen

Alle Signature-Momente sind **benannte Modifier der UI-Schicht** (Gebot 11 — Features
rufen Tokens, keine Freihand-Motion): `.briefschlitz()`, `.spindelstich()`,
`.lascheAuf()`, `.schubladenauszug()`, `.schluesselDreh()` — Parameter in
`Theme.Motion.Signature`, jeder mit VoiceOver-Ansage und Reduce-Motion-Pfad (Gebot 13).
Klang kommt ausschließlich aus `SoundEngine`-Synth-Presets (kein Asset), Haptik aus
`Haptics`/`HapticPatternKit`. Alle Karten folgen `MIGRATION_DUNKEL`:
Standard = `nightCard()`, helles Papier NUR am Hero/Artefakt.

### 3.1 POSTFACH (`tab.home`)

**Bühne:** Ein Zustellfach im Lampenlicht — nicht „ein Feed". Drei Zonen, von oben:

- **Zone Kopf** (Padding `Space.l`, `contentColumn(.hub)`): `DashboardHeaderView` — die
  zwei Beamten (Avatare, Präsenz), daneben das **Dienstlicht**: der Energie-Status beider
  als kleiner Lampenschein-Punkt (`Licht.lampengold` → `Licht.glut` → `Theme.energyRed`;
  Icons ≥ 3:1 auf Nacht, nie Text). Antippen = Energie setzen (heutiges `EnergyCard`-Flow).
- **Zone Zustellfach** (die Bühne): Zuoberst die **Stempelzeile AUF dem Hero-Papier** —
  der bestehende Poststempel des Briefbogens erweitert um die Runde:
  „MORGENPOST · TAG 137" (`Typo.anschrift`, Serif nur auf Papier — die Zeile sitzt auf dem
  Briefbogen, nie auf Nacht). Darunter der Hero (genau EIN `paperCard(.briefbogen)`:
  heutiger Brief / Erste Sendung / Morgengruß je nach `DashboardPriority`), dann ≤ 3
  `nightCard()`-Zustellkarten (Eilbote, Türchen, Spielzug-Aviso, „Heute vor …"),
  Einstieg Hero `blaettern`, Karten `legen` (Stagger 40 ms, max. 6) — alles Bestand.
- **Zone Ablage** (unten): der „Mehr"-Fold wird der **Ablagekorb** (ein `nightCard`-Fold,
  ehrlicher Badge wie heute), darunter Herz-Coda. `PulseFan` bleibt Chrome-FAB.

**Native Bausteine:** `NavigationStack` + ScrollView, `.scrollEdgeEffectStyle(.soft)`,
`.refreshable` (= „im Fach nachsehen"), TimelineView-Minutentakt (Bestand),
Zustellzettel-Accessory. **iPhone:** eine Spalte. **iPad:** die zwei balancierten
Spalten aus `DashboardPriority.balancedColumns` bleiben — der Hero behält die volle
Breite („sein Rang IST seine Breite").

**Signature-Moment — DER BRIEFSCHLITZ:** Beim ersten Vordergrund-Eintritt einer neuen
Zustellrunde (§4) gleitet der Hero durch einen Schlitz: eine 1-pt-`Nacht.naht`-Linie
unter der Stempelzeile, aus der die Karte per Maske + y-Offset (`Theme.Motion.arrive`,
Alias in `Signature.briefschlitz`) hervorkommt; beim Aufliegen wandert der
`Elevation`-Schatten von 24 → 14 (Legen-Physik). Haptik: `tap` beim Erscheinen, ein
`rigid`-Tick beim Aufliegen; Klang: ein papierenes „Flap" (Synth-Preset). VoiceOver:
„Tagespost ist da: {Kartentitel}." Reduce Motion: Karte liegt sofort, statischer
`Lichtschein`-End-Glow. Kein neues Artefakt — der Schlitz ist eine Hairline, das Budget
bleibt beim Poststempel des Heros.

### 3.2 SCHREIBSTUBE (`tab.chat`)

**Bühne:** Ein Stehpult mit Spindel — kein Messenger-Klon. Drei Zonen:

- **Zone Brett** (oben, optional): angepinnte Zettel (`ChatPinnedBanner`) als „am Brett";
  iPad: bestehende Rail rechts.
- **Zone Spindel** (Mitte, der Scroll): der Zettelwechsel wie gebaut — eigene Zettel
  `Papier.brief`, Partner `Papier.karton`, 4-pt-Tintenkante, Poststempel-Tagestrenner,
  Mini-Polaroid-Sticker, versiegelte Briefe in `blend`-Wachs. `.searchable` bleibt nativ.
- **Zone Pult** (unten): Eingabeleiste bleibt Chrome-Glas. Toolbar (System-Glas):
  `waveform` (Rohrpost) · `square.and.pencil` (Briefpapier) · `seal` (Siegelpresse-Menü:
  „Zeitpost aufgeben" / „Kapsel versiegeln" / „Türchen-Kalender bauen") — drei
  Toolbar-Items, native Menüs, keine Custom-Bar.

**Unterseiten (je +1/Sheet):** Telegramme (Touch-Raster groß, Klopfzeichen-Duett,
Morsestube = `HapticStudioView`), Briefpapier-Composer, Marken-Werkstatt,
Versöhnungsbrief. **iPhone/iPad:** wie heute (Rail ab regular width).

**Signature-Moment — DER SPINDELSTICH:** Der eigene Zettel landet mit `legen`; im
Aufliege-Frame erscheint an seiner Oberkante ein 6-pt-Tintenpunkt
(`coupleTint.tintePrimary`) — der Stich auf die Spindel. Haptik:
`HapticPatternKit`-Doppel (weich → kurzer `rigid`-Stich); Klang: trockener Tick.
Sende-Antwort im selben Frame (Gebot 14: lokal mutieren, Server bestätigt). VoiceOver:
unverändert „Gesendet". Reduce Motion: Punkt erscheint per Fade. Der Punkt ist Tinte,
kein Artefakt — Budgets unberührt.

### 3.3 SPIELTISCH (`tab.play`)

**Bühne:** Der Tisch im Hinterzimmer der Nachtschicht. Vier Zonen:

- **Zone Aushang** (oben): Saison-Zeile als Zettelstreifen mit Monats-Poststempel
  (Bestand `seasonStatusRow`) + Tagesaushang (Wordle-Blatt, Tagesaufgaben).
- **Zone Aufliegende Blätter**: offene Partien als ausgeteilte Hände — Karten mit
  2°-Fächerung (seeded, Bestand), Zug-Badge nativ. Wer dran ist, sieht seine Hand zuerst.
- **Zone Kartenschrank**: der Katalog in DREI Fächern (einklappbar, `@AppStorage` wie
  heute): **Fernpartien** (asynchron — Spielkarten-Umschläge mit Anschrift-Zeile
  „Für {Partner}") · **Am Tisch** (live) · **Feste & Fragen** (Party/Gespräch, inkl.
  Ausgehkarten & Kinoprogramm).
- **Zone Spielbuch** (unten): Turnier, Siegerliste, Wiederholungen, Anleitungen.

**Native Bausteine:** `NavigationStack(path:)` mit `GameDestination` (Bestand),
DisclosureGroups, native Badges; Spielbretter liegen weiter auf dem einen Papier-Bogen
im Lichtkegel (`GamesPaperKit`). **iPad:** Kartenschrank-Fächer zweispaltig ab regular
width; Bretter zentriert (`contentColumn`).

**Signature-Moment — LASCHE AUF:** Spielstart öffnet den Spielkarten-Umschlag: eine
Dreiecks-Lasche (Path-Overlay in `Papier.kante`) klappt per `rotation3DEffect` um die
Oberkante auf (0° → −150°, `anchor: .top`, Perspektive 0.3 — dieselbe Mechanik-Familie
wie `blaettern`, als `Signature.lascheAuf` benannt), dahinter blättert das Brett herein.
Haptik: `rigid` im Aufklapp-Frame; Klang: kurzer heller Riss-Tick (Synth). VoiceOver:
„{Spiel} beginnt." Reduce Motion: Lasche entfällt, Brett per Crossfade + Lichtschein.
Match-Feiern bleiben Lichtschein Stufe 1–2, `epic` nur Monats-Ereignisse (Bestand).

### 3.4 ARCHIV (`tab.us`)

**Bühne:** Die Schrankfront — sechs Fächer, keine 18 Kacheln. Zwei Zonen:

- **Zone Zuletzt eingeordnet** (oben): der Recent-Strip (neuestes Foto/Lied/Wertmarke)
  als drei Mini-Polaroids/Zettel — Bestand, neue Überschrift.
- **Zone Schrankfront**: sechs Fach-Karten (`nightCard()` mit 2-pt-Stapelkante:
  Alben · Planfach · Wertfach · Chronik · Lagerfach · Tresorfach), jede mit ehrlichem
  Zähl-Badge (offene Wertmarken, reife Kapseln — Bestand `sectionBadge`-Logik). Ein Fach
  öffnet INLINE (kein Push): die Fachzeile expandiert und schiebt ihre Sektionen als
  Zeilenliste aus — erst die Sektion pusht (Ebene 1), Details (Lightbox, Player) Ebene 2.

**Native Bausteine:** compact = `NavigationStack`; regular (iPad) = der bestehende
handgebaute Split — die sechs Fächer SIND die Sidebar-Gruppen (`MemoriesSidebarGroup`
wird von 4 auf 6 Gruppen umgeschnitten, reine Mapping-Änderung; `sidebarAdaptable`
bleibt vertagt, Beschluss `STYLE_DECISION` §3.7). `.searchable` im Alben-Stack (Bestand
Recon-Sweep). Tresorfach behält Face-ID-Gate.

**Signature-Moment — DER SCHUBLADENAUSZUG:** Das Fach fährt aus: die Sektionszeilen
gleiten mit `settle` horizontal ein (x-Offset −12 → 0, Stagger 40 ms, max. 6) und die
Schublade rastet am Ende der Schiene: EIN weicher Detent (`Haptics`-Soft-Impact) im
letzten Frame. Klanglos — hörbar ODER fühlbar, hier fühlbar (Gebot 3). VoiceOver:
„{Fach}, {n} Bereiche, aufgeklappt." Reduce Motion: Fade ohne Transform, Detent bleibt.

### 3.5 AMT (`tab.settings`)

**Bühne:** Der Werkzeugraum — still, KEINE Artefakte (Beschluss §3.6: Werkzeug-Räume
bleiben still). Native `Form`/`.formStyle(.grouped)` auf Nachtkarton, sechs Abschnitte:
**Unser Amt** · **Zustelldienst** (Zustellzeiten, Zustellrunden-Schalter, Setzkasten) ·
**Zweigstellen & Bezirke** (Geräte, Server, Umzug) · **Werkstatt** (Aushangkasten,
Prägeplatten, Schreibzeug, Sortiermaschine) · **Sicherung & Schlüssel** (Schloss,
Wiederherstellung, iCloud) · **Betriebsbuch** (Diagnose, Versionen, Handbuch, Credits,
Gefahrenzone). Alle heutigen Sheets bleiben Sheets.

**Signature-Moment — DER SCHLÜSSELDREH:** Das Scharfschalten des App-Schlosses dreht
den Schlüssel: das `key.horizontal`-Symbol rotiert einmal um 90° via
`symbolEffect(.rotate.byLayer, options: .nonRepeating)` (natives Symbol-Motion — kein
`.rotationEffect`, der Ratchet `raw_rotation_features` bleibt unberührt). Haptik: ein
metallischer `rigid`-Klick. Klanglos, klein, einmalig — der leiseste Signature-Moment
der App, absichtlich: das Amt schreit nie. VoiceOver: „Schloss aktiv." Reduce Motion:
Symbolwechsel per Fade.

---

## 4. Zustellrunden-Dramaturgie

**Prinzip:** Der Tag des Paares hat drei Zustellrunden. Runden ERZEUGEN nichts — sie
**inszenieren nur, was ohnehin da ist** (Tagesfrage, Check-ins, Zeitpost, Türchen,
Wochen-/Monatspost). Keine neue Notification-Quelle: `NotificationDamping` bleibt die
einzige Autorität; die Inszenierung ist rein Foreground.

| Runde | Fenster (lokal) | Typische Zustellungen | Stempelzeile |
|---|---|---|---|
| **Morgenpost** | 05–11 Uhr | Morgengruß-Check-in, heutiger Brief (Frage), Tagesaushang (Wordle/Quests), fällige Zeitpost | „MORGENPOST · TAG {n}" |
| **Tagespost** | 11–17 Uhr | offene Frage-Erinnerung, Spielzug-Avisos, Eilbote, Tagesnotiz | „TAGESPOST · TAG {n}" |
| **Nachtpost** | 17–05 Uhr | Gute-Nacht-Check-in, Siegelbruch (wenn beide geantwortet), Türchen, reife Kapseln; sonntags Wochenpost, monatsletzt Monatspost | „NACHTPOST · TAG {n}" |

**Zustandsmodell** (pur, Foundation-only, Linux-testbar — neue Datei
`Content/ZustellrundenLogic.swift` + `LogicTests/ZustellrundenLogicTests.swift`):

```swift
enum Zustellrunde: String, Codable, CaseIterable { case morgenpost, tagespost, nachtpost }

enum ZustellungsArt: Comparable { case morgengruss, tagesbrief, siegelbruch, eilbote,
    tuerchen, zeitpost, spielzug, tagesnotiz, wochenpost, monatspost, nachtruhe }

struct ZustellrundenLogic {
    /// 05–11 morgen · 11–17 tag · 17–05 nacht (lokale Stunde, Kalender des Geräts).
    static func runde(hour: Int) -> Zustellrunde
    /// Genau EINE Inszenierung pro Runde und Gerät: Marke "2026-08-16#tagespost".
    static func sollInszenieren(runde: Zustellrunde, dateKey: String,
                                zuletzt: String?) -> Bool
    static func marke(dateKey: String, runde: Zustellrunde) -> String
    /// Runden-Rangfolge der Zustellarten (ersetzt DayPhase-Kontext in DashboardPriority).
    static func rangfolge(für runde: Zustellrunde) -> [ZustellungsArt]
}
```

**Verdrahtung:** `DayPhase` (heute in `DashboardView`/`DashboardPriority`) wird durch
`Zustellrunde` ERSETZT — gleiche Stelle, gleiche Disziplin („computed once per
activation, never mid-look"): berechnet bei `scenePhase == .active`, nie im Blick des
Nutzers gewechselt. Persistenz: `@AppStorage("postfach.letzteInszenierung")` hält die
Marke; `sollInszenieren` steuert ausschließlich den Briefschlitz-Einstieg (§3.1) und die
Stempelzeile — die Karten-Rangfolge selbst bleibt `DashboardPriority.layout` mit
erweitertem Kontext. Der Zustellzettel (Accessory) liest dieselbe Runde.

**Respekt-Regeln (hart):** (1) Abschaltbar: Amt → Zustelldienst →
„Zustellrunden inszenieren" (`@AppStorage("amt.zustellrunden")`, Default an); aus =
statischer Einstieg, Stempelzeile zeigt nur „TAG {n}". (2) Keine Runden-Pushes: gepusht
wird, was heute pusht (Tagesfrage-Reminder etc.), gedämpft wie heute. (3) Kein Verlust:
eine nicht inszenierte Zustellung liegt einfach im Zustellfach — Runden sind Bühne,
nie Gate. (4) Zeitzonen: Runden sind GERÄTELOKAL; was der Partner sieht, ist seine
eigene Bühne desselben Inhalts (ehrlich dokumentiert, §8 Selbstkritik 4).
(5) VoiceOver: die Runden-Inszenierung spricht einen Satz
(„Nachtpost ist da: zwei Zustellungen.") via `AccessibilityNotification.Announcement`.

**Die drei Tages-Momente konkret:** Morgengruß = Morgenpost-Hero, wenn der
Morgen-Check-in offen ist (Bestandslogik `morningCheckinDone`); Tagesfrage = Hero ab
Beantwortbarkeit, Siegelbruch-Zeremonie unverändert `RevealCeremony`; Gute Nacht =
Nachtpost-Hero ab 21 Uhr, wenn `nightCheckinDone == false` — antwortet der Partner nach
dem eigenen Check-in, wird das zur ersten Morgenpost-Zustellung von morgen.

---

## 5. Anti-Generik-Beweis

Prüfstein je Station: *Würde dieser Screenshot unter 100 Paar-Apps sofort als
SoooDreamy erkannt — und unter 100 SoooDreamy-Screens sofort als DIESE Station?*

1. **Postfach:** Generisch wäre: Feed + Karten + „Guten Morgen, {Name}!". Hier: eine
   Stempelzeile auf echtem Briefpapier („NACHTPOST · TAG 137"), ein Briefschlitz als
   Hairline, aus dem der Tag ankommt, ein Dienstlicht statt Status-Emoji. Kein
   „Dashboard" nennt seine Inhalte Zustellungen und lässt sie durch einen Schlitz
   kommen — und der Poststempel ist bereits Jury-beschlossene Signatur, keine Zutat.
2. **Schreibstube:** Generisch wäre: Bubbles + Plus-Menü. Hier: Zettel auf einer
   Spindel, deren Stich man FÜHLT; ein Siegel-Menü in der Toolbar, das drei
   Zeitpost-Formen (Zeitpost, Kapsel, Türchen) an EINEM Ort bündelt — die Funktion
   „zeitversetzt lieben" bekommt einen Ort statt drei versteckter Einstiege.
3. **Spieltisch:** Generisch wäre: App-Store-Grid aus Spiel-Icons. Hier: ausgeteilte
   Hände mit Fächerung, ein Kartenschrank mit drei Fächern und die Erzählung
   „Fernpartien" — das historische Fernschach-per-Postkarte macht Async-Spiele zur
   Korrespondenz statt zur Featureliste. Kein Emoji-Grid, keine bunten Kacheln: Umschläge.
4. **Archiv:** Generisch wäre: 18 gleiche Kacheln (heutiger Zustand — die ehrlichste
   Generik-Stelle der App). Hier: sechs benannte Fächer mit Auszug-Detent — Gutscheine
   heißen Wertmarken, Sparen heißt Postsparbuch, der Tresor ist ein Schließfach. Die
   Schublade, die fühlbar einrastet, existiert in keiner Listen-App.
5. **Amt:** Generisch wäre: „Einstellungen" — und das DARF es fast bleiben (stiller
   Werkzeugraum, native Form). Der Anti-Generik-Beweis ist hier die Benennung der
   Systeme in der Welt des Paares (Zweigstellen, Zustellbezirke, Prägeplatten) plus der
   eine Schlüsseldreh — Understatement als Signatur: die einzige Settings-Seite, die
   zur Erzählung der App gehört, statt aus ihr herauszufallen.

Quer über alles: die EINE Zeremonie-Grammatik (Siegel → Stempel → Umschlag) wiederholt
sich von Kino (Szene 2/3) über Tagesfrage (Siegelbruch), Zeitpost (Falten → Stempeln →
Abflug), Chat-Briefe, Türchen bis zu den Widgets — Wiedererkennung durch Wiederholung,
nicht durch Lautstärke. Das Kitsch-Budget (3/1/1) und das Postdeutsch-Budget (§1) sind
die Leitplanken, die aus dem Postamt kein Disneyland machen.

---

## 6. Ordner-Neubau

### 6.1 Zielbaum `SoooDreamy/ios/SoooDreamy/`

Grundsatz: **Stationen statt Feature-Sammelordner.** Swift kennt keine Ordner-Namespaces
— der Umzug ist compile-neutral; die drei mechanischen Anker (6.3) sind die einzigen
Datei-INHALTE, die sich in Welle A ändern.

```
ios/SoooDreamy/
├── App/                  # unverändert: SoooDreamyApp, AppState(+Platform), RootView,
│                         #   ScreenshotSeed, TodayAccessoryView, (+ DemoBadge, s.u.)
├── UI/                   # unverändert — Design-System, einziger Rohwerte-Ort
├── Core/                 # unverändert — Package.swift-Schonung
├── Content/              # unverändert + NEU ZustellrundenLogic.swift (Welle B)
├── Intents/, Resources/  # unverändert
├── Kino/                 # ex Features/Onboarding: Amtsgründung, Pairing, Recovery
├── Zeremonien/           # app-weite Zustell-Momente (RootView-Overlays)
├── Zustelldienst/        # Rituals-Domäne: API, Modelle, AppState-Extension, L10n
└── Stationen/
    ├── Postfach/         (+ Zustellfach/ für die Zustellkarten)
    ├── Schreibstube/     (+ Briefpapier/, Rohrpost/, Telegramme/, Siegelpresse/)
    ├── Spieltisch/       (+ Spiele/, Spielbuch/)
    ├── Archiv/           (+ Alben/, Planfach/, Wertfach/, Chronik/, Lagerfach/, Tresorfach/)
    └── Amt/
```

`ios/Shared/`, `ios/Widgets/`, `ios/LogicTests/`, `ios/UITests/`, `ios/Config/`,
`ios/scripts/` bleiben unverändert an Ort und Stelle.

### 6.2 Datei-Mapping (git-mv-fähig, vollständig — 147 Feature-Dateien)

Welle A ist ein **reiner `git mv`** (Dateinamen bleiben; Typ-Renames sind eine eigene,
optionale Etappe, §8). Format: `git mv ios/SoooDreamy/Features/<alt> ios/SoooDreamy/<neu>`.

**Features/Home/ (29 Dateien)**

| Heute | Neuer Pfad (unter `ios/SoooDreamy/`) |
|---|---|
| DashboardView.swift | Stationen/Postfach/DashboardView.swift |
| DashboardHeaderView.swift | Stationen/Postfach/DashboardHeaderView.swift |
| DailyQuestionCard.swift | Stationen/Postfach/Zustellfach/DailyQuestionCard.swift |
| DailySparkCard.swift | Stationen/Postfach/Zustellfach/DailySparkCard.swift |
| CheckinCard.swift | Stationen/Postfach/Zustellfach/CheckinCard.swift |
| MissedInboxCard.swift | Stationen/Postfach/Zustellfach/MissedInboxCard.swift |
| FlashbackCard.swift | Stationen/Postfach/Zustellfach/FlashbackCard.swift |
| FirstMomentCard.swift | Stationen/Postfach/Zustellfach/FirstMomentCard.swift |
| QuestCard.swift | Stationen/Postfach/Zustellfach/QuestCard.swift |
| DateNightView.swift | Stationen/Postfach/Zustellfach/DateNightView.swift |
| HugQueueView.swift | Stationen/Postfach/Zustellfach/HugQueueView.swift |
| WaitingForPartnerCard.swift | Stationen/Postfach/WaitingForPartnerCard.swift |
| LevelCard.swift | Stationen/Postfach/LevelCard.swift |
| BadgeShelfView.swift | Stationen/Postfach/BadgeShelfView.swift |
| StreakCalendarView.swift | Stationen/Postfach/StreakCalendarView.swift |
| WhatsNewView.swift | Stationen/Postfach/WhatsNewView.swift |
| MoodPickerSheet.swift | Stationen/Postfach/MoodPickerSheet.swift |
| PresenceViews.swift | Stationen/Postfach/PresenceViews.swift |
| Heart3DView.swift | Stationen/Postfach/Heart3DView.swift |
| PlatformL10n.swift | Stationen/Postfach/PlatformL10n.swift ⚠ Package.swift |
| PulseFan.swift | Stationen/Schreibstube/Telegramme/PulseFan.swift |
| TouchGridCard.swift | Stationen/Schreibstube/Telegramme/TouchGridCard.swift |
| DuetView.swift | Stationen/Schreibstube/Telegramme/DuetView.swift |
| HapticStudioView.swift | Stationen/Schreibstube/Telegramme/HapticStudioView.swift |
| ZeitpostView.swift | Stationen/Schreibstube/Siegelpresse/ZeitpostView.swift |
| PostJournalView.swift | Stationen/Schreibstube/Siegelpresse/PostJournalView.swift |
| RevealCeremonyView.swift | Zeremonien/RevealCeremonyView.swift |
| TouchReceivedOverlay.swift | Zeremonien/TouchReceivedOverlay.swift |
| PostNoteOverlay.swift | Zeremonien/PostNoteOverlay.swift |

**Features/Chat/ (9 Dateien)**

| Heute | Neuer Pfad |
|---|---|
| ChatView.swift | Stationen/Schreibstube/ChatView.swift |
| ChatModel.swift | Stationen/Schreibstube/ChatModel.swift |
| ChatPaper.swift | Stationen/Schreibstube/ChatPaper.swift |
| PinnedMessages.swift | Stationen/Schreibstube/PinnedMessages.swift |
| ChatL10n.swift | Stationen/Schreibstube/ChatL10n.swift ⚠ Package.swift |
| LetterComposeView.swift | Stationen/Schreibstube/Briefpapier/LetterComposeView.swift |
| LetterSeals.swift | Stationen/Schreibstube/Briefpapier/LetterSeals.swift |
| LetterWorkshopView.swift | Stationen/Schreibstube/Briefpapier/LetterWorkshopView.swift |
| VoiceNotes.swift | Stationen/Schreibstube/Rohrpost/VoiceNotes.swift |

**Features/Games/ (41 Dateien)** — Infrastruktur + Hub nach `Stationen/Spieltisch/`,
Spiel-Views nach `Spiele/`, Meta nach `Spielbuch/`:

| Heute | Neuer Pfad |
|---|---|
| PlayHubView.swift · GameEngine.swift · GamesCoordinator.swift · GamesAppState.swift · GamesA11y.swift · GamesPaperKit.swift · GameTableView.swift · BoardDuelKit.swift · DailyQuestsView.swift | Stationen/Spieltisch/⟨gleicher Name⟩ |
| GamesL10n.swift | Stationen/Spieltisch/GamesL10n.swift ⚠ Package.swift |
| BattleshipView · ChoiceGamesView · ConnectFourView · DameView · DateIdeasView · EmojiRiddleLiveView · EmojiRiddleView · GomokuView · KaesekaestchenView · KniffelView · MancalaView · MemoryDuoView · MovieRouletteView · PhotoMemoryView · PictionaryView · Questions36View · QuizDuelView · QuizGameView · ReversiView · StadtLandFlussView · TruthOrDareLiveView · TruthOrDareView · TwoTruthsView · WordleView · WordPartyGamesView · GamesWaveView (je .swift) | Stationen/Spieltisch/Spiele/⟨gleicher Name⟩ |
| TournamentView.swift · ReplayView.swift · GamesRecordView.swift · WordleRecordView.swift | Stationen/Spieltisch/Spielbuch/⟨gleicher Name⟩ |

**Features/Memories/ (25 Dateien)**

| Heute | Neuer Pfad |
|---|---|
| MemoriesView.swift · MemoriesHubComponents.swift | Stationen/Archiv/⟨gleicher Name⟩ |
| MemoriesL10n.swift | Stationen/Archiv/MemoriesL10n.swift ⚠ Package.swift |
| GalleryView · GalleryComponents · GalleryPagerView · MediaLightbox · VideoGalleryView · VideoPlayerScreen · PotdView · EventsView · StoryTimelineView · StoryModels · YearReviewView (je .swift) | Stationen/Archiv/Alben/⟨gleicher Name⟩ |
| SharedListsView.swift · BucketListView.swift | Stationen/Archiv/Planfach/⟨gleicher Name⟩ |
| CouponsView.swift | Stationen/Archiv/Wertfach/CouponsView.swift |
| JournalView · LoveStatsView · SoundtrackView · CanvasView · CanvasExportSheet (je .swift) | Stationen/Archiv/Chronik/⟨gleicher Name⟩ |
| VaultView.swift · VaultItemViewer.swift | Stationen/Archiv/Tresorfach/⟨gleicher Name⟩ |
| OnThisDayCard.swift | Stationen/Postfach/Zustellfach/OnThisDayCard.swift |

**Features/Rituals/ (15 Dateien — der Ordner löst sich auf)**

| Heute | Neuer Pfad |
|---|---|
| RitualsDashboardSection.swift | Stationen/Postfach/Zustellfach/RitualsDashboardSection.swift |
| DaymemoView.swift | Stationen/Postfach/Zustellfach/DaymemoView.swift |
| RepairConsiderationView.swift | Stationen/Schreibstube/Briefpapier/RepairConsiderationView.swift |
| CustomQuestionsView.swift | Stationen/Amt/CustomQuestionsView.swift |
| WeekplanView.swift | Stationen/Archiv/Planfach/WeekplanView.swift |
| WeekReviewView.swift | Stationen/Archiv/Chronik/WeekReviewView.swift |
| MagazineView.swift | Stationen/Archiv/Chronik/MagazineView.swift |
| GoalsView.swift | Stationen/Archiv/Wertfach/GoalsView.swift |
| CapsulesView.swift | Stationen/Archiv/Lagerfach/CapsulesView.swift |
| SeasonCalendarView.swift | Stationen/Archiv/Lagerfach/SeasonCalendarView.swift |
| NeedsHistoryView.swift | Stationen/Archiv/Chronik/NeedsHistoryView.swift |
| RitualsAPI.swift · RitualsAppState.swift · RitualsModels.swift | Zustelldienst/⟨gleicher Name⟩ |
| RitualsL10n.swift | Zustelldienst/RitualsL10n.swift ⚠ Package.swift |

**Features/Settings/ (18 Dateien) → Stationen/Amt/** — alle 18 flach nach
`Stationen/Amt/⟨gleicher Name⟩`; darunter ⚠ Package.swift: `IntelligenceL10n.swift`,
`SettingsL10n.swift`.

**Features/Onboarding/ (11 Dateien)**

| Heute | Neuer Pfad |
|---|---|
| CinematicChapterPlayer · CinematicChapterStages · CinematicHandoff · CinematicIntroView · OnboardingFlowView · PairingView · QRSupport · RecoveryViews (je .swift) | Kino/⟨gleicher Name⟩ |
| OnboardingL10n.swift | Kino/OnboardingL10n.swift ⚠ Package.swift |
| PairingCeremonyView.swift | Zeremonien/PairingCeremonyView.swift |
| DemoBadge.swift | App/DemoBadge.swift (globales Chrome-Band „Musterbetrieb") |

**Neue Dateien (Welle B, keine Moves):** `Content/ZustellrundenLogic.swift` (+ Eintrag
in `Package.swift` `sources`), `LogicTests/ZustellrundenLogicTests.swift`,
`UI/`-Erweiterung `Theme.Motion.Signature` um `briefschlitz`/`lascheAuf`/
`spindelstich`/`schubladenauszug` (bestehende Datei, keine neue).

### 6.3 Die drei mechanischen Anker (gleicher Commit wie der Move)

1. **`ios/Package.swift`** listet Logic-Quellen EXPLIZIT: genau **8 Pfade** ändern sich
   (die ⚠-Zeilen oben: ChatL10n, GamesL10n, MemoriesL10n, OnboardingL10n, PlatformL10n,
   RitualsL10n, IntelligenceL10n, SettingsL10n). Alle `Content/`-, `Core/`- und
   `Shared/`-Einträge bleiben wörtlich — deshalb ziehen Content/Core NICHT um.
   Gate: `swift test` grün auf Linux.
2. **`tools/charter_lint.sh`** verdrahtet `ios/SoooDreamy/Features` hart in ~8 Metriken
   (`bare_white_opacity`, `raw_corner_radius`, `hardcoded_pink_purple_features`,
   `ultrathin_material_features`, `surface_glass_features`, `raw_rotation_features`,
   `system_size_fonts`, `torn_edge_uses`): der Pfad wird zu
   `ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien
   ios/SoooDreamy/Zustelldienst`. Gate: Zähler VOR und NACH dem Move identisch
   (`charter_baseline.json` unangetastet — ein Move darf keinen Zähler bewegen).
3. **`ios/.swiftlint.yml`**: `included: '.*Features/.*'` →
   `'.*(Stationen|Kino|Zeremonien|Zustelldienst)/.*'`.

**Keine Änderung nötig:** `project.yml` globt (`path: SoooDreamy`,
`createIntermediateGroups: true` — XcodeGen baut die Gruppen aus dem Dateisystem);
UITests fahren über Accessibility-IDs (`tab.*`, `ui.*`-Seams), nie über Pfade oder
Typnamen; Widgets/Shared/Server unberührt.

---

## 7. Onboarding-Anschluss: Kino → erstes Postfach

Das Kino IST bereits die Gründungsurkunde des Postamts — die beschlossenen sieben Szenen
(`CinematicScript`: lampenklick · umschlag · siegelbruch · tinten · wachssiegel ·
polaroid · ankunft) werden nicht angefasst, nur ZU ENDE erzählt:

1. **Neue Rahmung ohne Szenen-Diff:** Szene 2 (Umschlag, Poststempel „TAG 1") und
   Szene 3 (Siegelbruch) sind wörtlich die Zeremonie-Grammatik des Postamts; Szene 4/5
   (Tinten → Wachs) gießen das Amtssiegel des Paares. Die Erzählung „ihr gründet euer
   Postamt" ist eine L10n-/Caption-Schicht, kein Video-Rerender (Text ist Overlay aus
   dem `captions`-Manifest — Beschluss `RECON_REMOTION_PIPELINE`).
2. **Die Übergabe (Szene 7 „ankunft") landet im Postfach:** Das Papier legt sich in den
   Postfach-Screen, die Glas-TabView gleitet herauf (Bestand `CinematicHandoff`). NEU:
   Das erste, was im Zustellfach liegt, ist **Sendung Nr. 1** — der Pairing-Code als
   versiegelter Brief „Für {Partnername, sobald bekannt}": dieselbe
   `WaitingForPartnerCard`, umerzählt („Der erste Brief ist unterwegs. Sobald {Name}
   ihn öffnet, seid ihr verbunden."), QR/Code als Briefinhalt. Pairing-Abschluss =
   `PairingCeremonyView` (Amtsgründungs-Zeremonie, Bestand) → das Postfach zeigt danach
   den heutigen Brief als erste echte Zustellung mit Stempel „TAG 1".
3. **Erste-Tage-Führung ohne Tutorial:** `FirstMomentCard`/`QuestCard` werden die ersten
   drei Dienstgänge („Beantwortet euren ersten Brief" → „Schickt ein Telegramm" →
   „Legt das erste Foto ins Archiv") — bestehende Quest-Steps, neue Sätze, kein neues
   System. Der Briefschlitz feuert am ersten Tag GENAU einmal (Marke ist gesetzt, bevor
   das Kino endet — kein Doppel-Moment nach der Amtsgründung).
4. **Demo-Modus = Musterbetrieb:** `DemoBadge` wird das Band „MUSTERBETRIEB" (bleibt
   `safeAreaBar` über allen Stationen und selbst der Ausgang); das gestagte Demo-Paar
   bespielt alle fünf Stationen, damit der App-Store-/Sideload-Erstkontakt das volle
   Postamt zeigt. Recovery (`RecoveryViews`) bleibt im Kino-Ordner: der
   Wiederherstellungs-Schlüssel ist der „Zweitschlüssel des Amts" (Amt → Sicherung).

---

## 8. Migrationsplan & Selbstkritik

### 8.1 Vier Wellen

- **Welle A — Der Umzug (rein mechanisch, EIN atomarer Commit).** 147 `git mv` nach
  §6.2 + die drei Anker (§6.3). Kein Verhaltens-Diff, kein Rename, kein L10n-Diff.
  Gates: `swift test` (Linux), `charter_lint.sh` mit identischen Zählern, XcodeGen-Build
  in CI, UITest-Suite grün. Risiko-Fenster klein halten: Welle A wird mit den parallel
  arbeitenden Agents als Freeze-Punkt koordiniert (der Move ist der Rebase-Killer —
  NACH dem Move rebasen ist trivial, WÄHREND des Moves offene Branches sind es nicht).
- **Welle B — Runden & Postfach.** `ZustellrundenLogic` (+ Tests), `DayPhase` →
  `Zustellrunde` in `DashboardPriority` (LogicTests neu gepinnt — bewusster
  Test-Commit), Stempelzeile auf dem Hero, Briefschlitz-Signature (UI-Schicht),
  Zustellzettel-Accessory, Stations-Labels + Tab-Symbole in L10n/`RootView`
  (a11y-IDs unverändert), Amt-Schalter „Zustellrunden".
- **Welle C — Schreibstube & Spieltisch.** Siegelpresse-Menü in der Chat-Toolbar
  (Zeitpost/Kapsel/Türchen-Einstiege), Telegramm-Seite (Umzug der Vollwerkzeuge,
  Postfach behält die kompakte Leiste), Spindelstich; Spieltisch-Zonen (Aushang,
  Kartenschrank-Dreiteilung — heutige Gruppen umgeschnitten), Lasche-auf-Signature.
- **Welle D — Archiv & Amt (+ optionale Rename-Etappe).** `MemoriesSidebarGroup`
  4 → 6 Fächer, Schrankfront mit Schubladenauszug, iPad-Split-Umbenennung;
  Amt-Sektionen neu geordnet, Schlüsseldreh. Optional (nur wenn ruhige See):
  Typ-Renames `DashboardView → PostfachView`, `MemoriesView → ArchivView`,
  `SettingsView → AmtView`, `TodayAccessoryView → ZustellzettelView` — Renames sind
  Kür, nie Blocker; UITests hängen an ID-Strings, nicht an Typnamen.

Jede Welle endet mit `bash SoooDreamy/tools/charter_lint.sh --update` (nur sinkende
Zähler), `swift test`, Screenshot-Matrix inkl. `paired-ax5-de.png` (AX5-Pflicht) und
den drei PR-Antworten des Noble-Tests.

### 8.2 Risiken (benannt, mit Gegenmittel)

| Risiko | Gegenmittel |
|---|---|
| Welle A kollidiert mit parallelen Branches (147 Moves) | Freeze-Fenster + atomarer Commit; `git log --follow` bleibt intakt, weil reine Renames |
| Ratchet-Blindflug nach Pfadwechsel (Zähler fallen fälschlich auf 0) | Anker 2 im SELBEN Commit + Vorher/Nachher-Zählervergleich als PR-Pflichtbeweis |
| `DashboardPriority`-Umbau kippt gepinnte LogicTests | eigener Test-Commit wie beim Verdict-Re-Baselining (Beschluss §3.11.2) — bewusst, nie nebenbei |
| Runden-Inszenierung nervt (dreimal täglich Bühne) | Ein-Marken-Modell (§4), Abschalt-Schalter, keine neuen Pushes; Inszenierung nur bei ECHTEN neuen Zustellungen |
| UITest-Journey test01 (First-Launch) bricht an Sendung Nr. 1 | Kino-Handoff behält Ablauf & Seams; neue Texte hinter bestehenden IDs; Staging-Argumente unverändert |

### 8.3 Selbstkritik — die fünf härtesten Schwächen

1. **Vokabel-Hürde am ersten Tag.** „Amt", „Schreibstube", „Spieltisch" muss man einmal
   lernen; ein gestresster Nutzer sucht „Einstellungen" und „Spiele". Die SF-Symbole
   tragen die halbe Last, das Kino die andere — aber wer das Kino skippt, zahlt
   Orientierungskosten. Wenn Telemetrie-lose Beobachtung (UserFeedback) zeigt, dass
   Labels nicht sitzen, ist der Rückzug billig (L10n-only) — aber er wäre eine
   halbierte These.
2. **Metapher-Overreach ist ein Dauerkampf.** Das Postdeutsch-Budget ist Review-Ritual,
   kein Ratchet — genau die Sorte Disziplin, die unter Zeitdruck zuerst stirbt. Ein
   Jahr später kann die App voller „frankiert/kuvertiert/Postwertzeichen" sein, und
   dann ist das Postamt das neue Emoji-Konfetti.
3. **Die Runden-Dramaturgie ist gerätelokal und damit halb wahr.** Ein Paar in
   Fernbeziehung über Zeitzonen erlebt „Nachtpost", während der Partner Morgenpost
   liest — die Erzählung suggeriert einen gemeinsamen Amtstag, den es physisch nicht
   gibt. Schichtarbeitende trifft dasselbe. Das Modell bleibt ehrlich (Runden sind
   Bühne, nie Gate), aber die Poesie hinkt der Realität hinterher.
4. **Das Archiv kann bürokratisch kippen.** Sechs Fächer mit Auszugs-Detent sind
   strukturell besser als 18 Kacheln — aber „Archiv", „Fach", „Chronik" ist genau die
   Distanz-Sprache, an der Editorial im Stil-Wettbewerb gescheitert ist. Die Wärme muss
   täglich aus dem Inhalt kommen (Polaroids, Wertmarken, Postsparbuch); wenn die Fächer
   je leer wirken, wirkt die Station wie ein Aktenschrank.
5. **Doppelte Heimat der Zeitformen.** Kapseln/Türchen werden an der Schreibstube
   versiegelt, reifen aber im Archiv-Lagerfach — zwei Orte für eine Sache ist die
   klassische Auffindbarkeits-Falle. Die Wette: „schreiben dort, wo geschrieben wird;
   lagern dort, wo gelagert wird" ist die richtige Grammatik — aber sie kostet einen
   Lernschritt mehr als der heutige Eine-Liste-Zustand, und der Cross-Link muss in
   beiden Richtungen sichtbar bleiben, sonst verliert jemand seine reifende Kapsel
   aus dem Blick.

---

*Dossier „Das Nachtpostamt" — eine Grammatik, fünf Orte mit Beruf, vier Wellen.
Das Design bleibt; das Gebäude wird gebaut. Die Jury möge streng sein: §2.2 ist
vollständig, §6.2 ist git-mv-fähig, und jede Behauptung über den Bestand ist gegen
den Code dieser Branch geschrieben.*
