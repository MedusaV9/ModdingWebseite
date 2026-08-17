# NEUBAU_ENTSCHEID.md — Das Jury-Urteil des Neubau-Wettbewerbs

**Status: BINDEND.** Dieses Dokument entscheidet den Neubau-Wettbewerb der drei Dossiers
(`NEUBAU_ZIMMERHAUS.md`, `NEUBAU_POSTAMT.md`, `NEUBAU_ALMANACH.md`) und ist das Bauprogramm,
nach dem Informationsarchitektur, Seiten und Code-Ordner neu gebaut werden. Das DESIGN steht
nicht zur Debatte: „Papier & Licht" (`STYLE_DECISION.md` §3), Nacht-first
(`MIGRATION_DUNKEL.md`), die 15 Gebote, Ratchets und Budgets (`DESIGN.md`) bleiben wörtlich
in Kraft. Die Wellen N1–N4 (§5) setzen dieses Dokument 1:1 um.

Bewertungsgrundlage: die drei Dossiers vollständig, `DESIGN.md`, `STYLE_DECISION.md`,
`App/RootView.swift` (Ist-Shell), und eine **Stichproben-Verifikation gegen den echten
Baum** (Prüfprotokoll in §3.4): 147 Feature-Dateien (Chat 9 · Games 40 · Home 29 ·
Memories 25 · Onboarding 11 · Rituals 15 · Settings 18), `ios/Package.swift` (exakt 8
explizite Feature-L10n-Pfade), `tools/charter_lint.sh` (9 hart auf
`ios/SoooDreamy/Features` verdrahtete Grep-Stellen), `ios/.swiftlint.yml` (1 Regel-Scope),
`ios/project.yml` (Glob, `createIntermediateGroups: true` — keine Änderung nötig),
`UITests/` (`switchTab` ist ID-first, Label nur Fallback; Inhalts-Anker benannt in §5).

---

## §1 Urteil

**Gewinner ist „Das Nachtpostamt" (`NEUBAU_POSTAMT.md`).**

Die Klage des Users lautet „alles noch viel viel krasser und einzigartiger statt nur
generische App" — und die ehrliche Diagnose aller drei Dossiers ist dieselbe: generisch ist
nicht das Material (das ist seit Papier & Licht unverwechselbar), sondern das Gerüst aus
austauschbaren Containern. Das Postamt ersetzt das Gerüst durch eine **Grammatik** (Ankunft ·
Absendung · Ablage), die drei Dinge gleichzeitig leistet, die kein Konkurrent in dieser
Kombination schafft: (1) Sie ist die **Vollendung des beschlossenen Kinos**, nicht eine
zweite Metapher daneben — Umschlag, Poststempel „TAG 1", Siegelbruch und Wachsguss der
Szenen 2–5 SIND die Zeremonie-Grammatik des Postamts, das Kino wird rückwirkend zur
Amtsgründung; (2) sie ist die **billigste und sicherste Migration** — Core/Content/UI
bleiben byte-identisch liegen, alle fünf `tab.*`-IDs bleiben wörtlich, genau 8
Package.swift-Pfade ändern sich, und die tägliche Bedienung (Tagesfrage = Tab-1-Hero,
Chat = Tab 2, Spiel = Tab 3) verliert keinen einzigen Handgriff; (3) ihre Grammatik
**absorbiert Wachstum** — jedes neue Spiel ist ein weiterer Spielkarten-Umschlag im Fach,
jede neue Frage ist Tagespost, jedes neue Ritual ist eine `ZustellungsArt` im Enum, ohne
dass je ein neues Möbelstück oder Buchteil erfunden werden muss.

Das Zimmerhaus hat die stärkste Silhouetten-These (Möbel statt Sections), scheitert aber an
der Summe seiner Risiken: Der Kammer-Zug bricht den `tab.settings`-Vertrag und das
Muskelgedächtnis für einen Küche-Tab, dessen Alleinstellungs-Zimmer an leeren Tagen am
dünnsten ist (Selbstkritik 1 + 4 des eigenen Dossiers); die Ordner-Umbenennung
Core/Content/UI → Kern/Fundament/Design kostet ~90 zusätzliche Package.swift-Pfade plus
Lint-Glob-Umbau für null Nutzer-Nutzen; und fünf neue Requisiten-Familien (Schnur, Stempel,
Magnete, Kisten, Hebel) sind fünf neue Fronten im Dauerkampf gegen den Bastelladen. Der
Almanach hat die beste Einzel-Idee des Wettbewerbs (das Blatt, das sich aus dem Tun
schreibt) und die beste iPad-Idee (die Doppelseite) — aber sein Kern hängt an einem neuen
Merge-System (`ChronikLogic`) mit selbst eingestandenem Doppel-Wahrheits-Risiko
(Selbstkritik-Risiko 5), und eine Seite, die sich „füllen muss", ist in stillen Wochen
strukturell eine Streak mit anderem Namen (Selbstkritik 5) — genau der Druck, den Gebot 15
verbietet. Das Postamt gewinnt nicht, weil es am lautesten ist, sondern weil es am längsten
trägt.

### 1.1 Score-Tabelle (Skala 1–10; je 1 Satz Begründung)

| Kriterium | Zimmerhaus | Postamt | Almanach |
|---|---|---|---|
| (a) Einzigartigkeit im Alltag | **8** — Möbel-Silhouetten töten die Karten-Wiederholung, aber der Effekt ist Bühnenbild und nutzt sich als Layout schneller ab als als Grammatik. | **8** — Orte mit Beruf + Zustellrunden geben jedem Tag drei verschiedene Bühnen desselben Inhalts, ohne je Deko zu sein. | **9** — das Blatt ist ab dem zweiten Eintrag ein datengetriebenes Unikat pro Paar und Tag — die stärkste Anti-Generik-These des Felds. |
| (b) Stimmigkeit Papier & Licht + Kino | **7** — Lampe und Zimmer passen, aber Kühlschrank, Magnete und Wäscheleine sind NEUE Requisiten, die das Kino nie gezeigt hat. | **10** — Umschlag/Stempel/Siegel/Tinte/Polaroid sind wörtlich die Kino-Szenen 2–6; das Postamt erfindet nichts, es erbt. | **8** — Buch, Tinte und „TAG n als Seitenzahl" schließen gut an, aber Mondstand und Buchbinden importieren almanach-eigene Motive. |
| (c) Tägliche Gebrauchstauglichkeit | **6** — die Kammer hinter dem Schlüssel und der Tab-Umbau kosten gelerntes Verhalten; die Küche belohnt nur Plan-Paare. | **9** — kein Weg wird länger, alle fünf Tabs und Wurzeln bleiben, die Runden sind reine Foreground-Bühne mit Abschalt-Schalter, nie Gate. | **8** — die Wege bleiben, aber der Haupteintrag lebt IN der Blatt-Komposition, und die Chronik konkurriert im Alltag mit Faden und Postbuch um dieselben Ereignisse. |
| (d) Machbarkeit / Migrationsrisiko | **5** — größter Blast-Radius: ~90 zusätzliche Package.swift-Pfade (Content/Core/UI-Rename), `tab.settings`-Bruch, neuer Tab, ScreenshotSeed- und UITest-Umbau schon in der Gerüst-Welle. | **9** — 147 reine `git mv`, exakt 8 Manifest-Pfade, 9 Lint-Grep-Stellen, 1 SwiftLint-Scope, IDs stabil; einzige neue Logik ist EIN pures Modul (`ZustellrundenLogic`). | **7** — Moves ähnlich billig, aber drei neue Logic-Module + TextRenderer + Feed-Merge, und RootView/Rituals-Dateien wandern in Schichten (`Buch/`, `Core/`), wo sie nicht hingehören. |
| (e) Kitsch-/Overreach-Risiko über Monate (höher = sicherer) | **5** — fünf Requisiten-Familien und je eine Handwerks-Geste pro Zimmer sind die meisten Gelegenheiten, die 3/1/1-Budgets zu reißen. | **7** — das Risiko ist Sprache statt Grafik („Postdeutsch") und hat als einziges Dossier ein hartes Vokabel-Budget (eine Post-Vokabel pro Screen) als Leitplanke. | **7** — die Tintenschrift ist nach einer Woche ein Ladebalken mit Serifen, wenn die Nur-neueste-Zeile-Regel je aufweicht; das Regal mit 90°-Text flirtet offen mit AX- und Deko-Grenzen. |
| (f) iPad-Stärke | **8** — Pult, Schrankwand, Kühlschranktür und Regalwand sind durchdachte, aber je eigene Layout-Sonderwege pro Zimmer. | **7** — solide (balancierte Spalten bleiben, Archiv-Fächer = Sidebar-Gruppen), aber die am wenigsten ambitionierte iPad-Erzählung des Felds. | **9** — die Verso/Recto-Doppelseite mit Marginalien-Randspalte ist die natürlichste iPad-Idee des Wettbewerbs. |
| (g) Content-Erweiterungen wachsen natürlich hinein | **6** — neue Spiele passen ins Regal, aber jede neue Feature-FAMILIE braucht ein neues Möbel, und Zimmer können nicht beliebig vollgestellt werden. | **9** — „alles ist eine Form von Post": neues Spiel = Umschlag im Fach, neue Frage = Tagespost, neues Ritual = neue `ZustellungsArt` — die Grammatik hat für alles schon ein Wort. | **8** — „alles ist ein Eintrag" trägt ebenso weit, aber jeder neue Eintragstyp muss durch die Dedupe-Regeln der Chronik verhandelt werden. |
| **Σ** | **45** | **59** | **56** |

### 1.2 Die zwei Adoptionen (bindend)

**A1 — aus `NEUBAU_ALMANACH.md`: das Kapitelverzeichnis mit Punktlinien-Seitenzahlen**
(Spielbuch-Wurzel, dort §3.3 Punkt 3). Die Registerzeile „Kapiteltitel ····· Zahl", bei der
die „Seitenzahl" die Zahl der gespielten Partien des Fachs ist, macht den Katalog SELBST zur
Biografie (Gebot 15) — mit reiner Typografie (`Typo.anschrift` + `Typo.number`), null
Artefakt-Budget und null neuer Mechanik. Sie stärkt die Postamt-Grammatik statt sie zu
verwässern, weil Druckwerk (Register, Amtsblatt) im Postamt heimisch ist. **Einbau-Stelle:**
Spieltisch (`tab.play`), Zone Kartenschrank — die drei Fach-Kopfzeilen (Fernpartien · Am
Tisch · Feste & Fragen) tragen die Punktlinien-Zeile mit der Partien-Zahl des Fachs; dieselbe
Zeilen-Anatomie für die vier Spielbuch-Einträge (Turnier · Siegerliste · Wiederholungen ·
Anleitungen). Umsetzung in Welle N3.

**A2 — aus `NEUBAU_ZIMMERHAUS.md`: „Polaroid entwickeln"** (Dachboden-Signature, dort §3.5).
Press-and-hold entwickelt das milchige „Heute vor …"-Polaroid radial unterm Daumen (sechs
weiche Haptik-Ticks im Crescendo, Loslassen milcht zurück, am Ende Stille statt Konfetti) —
Erinnern bekommt eine Geste des Wartens, die keine andere Paar-App hat. Sie ist nicht
haus-spezifisch, sondern Foto-Papier-Physik und vollendet Kino-Szene 6 (das leere Polaroid)
im Alltag — postamt-kompatibel, denn Fotos kommen mit der Post. **Einbau-Stelle:** Postfach
(`tab.home`), Zone Zustellfach — die „Heute vor …"-Zustellkarte (`OnThisDayCard`/
`FlashbackCard`); derselbe benannte UI-Modifier wird in Archiv › Alben › Foto des Tages
(`PotdView`) wiederverwendet. Kollisions-Regel: der Briefschlitz (§4.1) feuert nur beim
Rundenbeginn, das Entwickeln ist nutzer-initiiert — zwei leise Momente, nie gleichzeitig.
Reduce Motion/AX: einfacher Tap + Crossfade; VoiceOver: Announcement „Heute vor {n} Jahren:
{Titel}" (wörtlich aus dem Zimmerhaus-Dossier übernommen). Umsetzung in Welle N2.

Alles andere aus den Verlierer-Dossiers wird NICHT übernommen (§6).

---

## §2 Finale Informationsarchitektur

### 2.1 Die fünf Stationen (native iOS-26-`TabView`, `RootView.swift`)

Struktur, Accessory, Badges, `.tint(coupleTint.blend)`, Reselect-Scroll und die defensive
Lazy-Pane-Mechanik bleiben wörtlich wie in `App/RootView.swift`. **Die a11y-IDs
`tab.home` / `tab.chat` / `tab.play` / `tab.us` / `tab.settings` bleiben WÖRTLICH bestehen**
— nur L10n-WERTE und SF-Symbole ändern sich (die L10n-KEYS `tab.home`…`tab.more` bleiben).

| # | Station (DE) | EN | SF-Symbol (outline) | a11y-ID (fix) | Beruf des Ortes |
|---|---|---|---|---|---|
| 1 | **Postfach** | Mailbox | `tray.and.arrow.down` | `tab.home` | Ankunft: der heutige Brief, Zustellkarten, Nachsendebündel, Ablage, Herz-Coda. |
| 2 | **Schreibstube** | Writing Desk | `envelope` | `tab.chat` | Absendung: Zettelspindel, Briefpapier, Rohrpost, Telegramme, Siegelpresse. |
| 3 | **Spieltisch** | Game Table | `dice` | `tab.play` | Die Pause der Nachtschicht: aufliegende Partien, Kartenschrank, Spielbuch. |
| 4 | **Archiv** | Archive | `archivebox` | `tab.us` | Ablage: sechs benannte Fächer statt 18 Kacheln. |
| 5 | **Amt** | Bureau | `building.columns` | `tab.settings` | Betrieb: still, native Form, sechs Abschnitte. |

Chrome-Umbenennungen (gleiche APIs): `TodayAccessoryView` wird der **Zustellzettel**
(links Präsenz wie heute, rechts Runde + Status „Nachtpost · Siegel wartet"; beide
Placements `.expanded`/`.inline` bedient). `PulseFan` bleibt Chrome-FAB auf dem Postfach.
`DemoBadge` wird das Band „MUSTERBETRIEB" (bleibt `safeAreaInset(edge: .top)` wie im
Bestand). ⌘1–5 bleiben in Bar-Reihenfolge.

### 2.2 Vollständige Screen-Tabelle alt → neu (inkl. Sheets)

Regel: max. 2 Navigationsebenen unterm Tab (Root → Push → Detail); Sheets zählen als Ebene
ihrer Herkunft. Cross-Station-Pushes sind erlaubt; die Datei-HEIMAT regelt §3.

**Zuhause (Home) → Station 1 POSTFACH**

| Heute | Neu (Ort · Rolle) | Ebene |
|---|---|---|
| `DashboardView` | Postfach-Root: Kopf → Zustellfach → Ablage (§4.1) | Root |
| `DashboardHeaderView` | „Die zwei Beamten": Kopfzeile + **Dienstlicht** (Energie-Status als Lampenschein-Punkt) | Root |
| `DailyQuestionCard` | **Der heutige Brief** — der EINE `briefbogen` des Screens; Stempelzeile trägt die Runde: „MORGENPOST · TAG 137" | Root |
| `CheckinCard` | Morgenpost-/Nachtpost-Karte (Runden-Hero, §4.6) | Root |
| `MissedInboxCard` | **Nachsendebündel** (gebündelte Zustellungen mit Stapelkante) | Root |
| `RitualsDashboardSection` | zerlegt: Energie → Dienstlicht · Needs → **Eilbote**-Karte · Daymemo → Tagesnotiz-Zustellung · Support-Banner bleiben Zustellkarten | Root |
| `NeedsHistoryView` | Eilboten-Chronik (Archiv › Chronik) | +1 |
| `DaymemoView` | Tagesnotiz (Zustellung + Compose) | +1 |
| `QuestCard`, `FirstMomentCard` | Erste Dienstgänge (Neu-Paar-Dramaturgie, `DashboardPriority` unverändert) | Root |
| `OnThisDayCard` / `FlashbackCard` | „Heute vor …"-Zustellung — **mit Adoption A2 „Polaroid entwickeln"** | Root |
| `DateNightView` | Verabredungs-Karte; plant in Archiv › Planfach | Root / +1 |
| `HugQueueView` | Lagernde Sendungen (Umarmungen warten auf den Partner) | Root |
| `LevelCard`, `BadgeShelfView`, `StreakCalendarView` | Ablage-Zone: Biografie-Zahlen, Siegelsammlung, Stempelkalender | Root (Fold) |
| `Heart3DView` | Herz-Coda — bleibt die Coda der Seite | Root |
| `TouchGridCard` | **Telegramm-Leiste** (kompakt; Vollwerkzeuge in der Schreibstube). Die Stationen-Kacheln (Zeitpost, Journal) BLEIBEN hier und öffnen dieselben Sheets — `zeitpost.*`-IDs stabil, UITest test04 bleibt grün | Root |
| `PulseFan` | Chrome-FAB, unverändert | Chrome |
| `MoodPickerSheet` | Stimmungs-Sheet am Postfach | Sheet |
| `WhatsNewView` | „Aushang" (Auto-Sheet beim Start bleibt; Heimat: Postfach) | Sheet |
| `WaitingForPartnerCard` | **Sendung Nr. 1**: Pairing-Code als versiegelter Brief „Für {Name}" (§5 N2) | Root |
| `PresenceViews` | Präsenz im Kopf + Zustellzettel | Root |
| `ZeitpostView` | **Siegelpresse: Zeitpost-Schalter** (Heimat Schreibstube; vom Postfach-Stationen-Tile aus als Sheet erreichbar) | Sheet |
| `PostJournalView` | **Sendungsbuch** (Zustell-Journal; ebenso doppelt erreichbar) | +1 / Sheet |

**Chat → Station 2 SCHREIBSTUBE**

| Heute | Neu | Ebene |
|---|---|---|
| `ChatView` | **Zettelspindel** — Zettel brief/karton mit Tintenkante, Poststempel-Tagestrenner, `.searchable` nativ | Root |
| Eingabeleiste | **Pult** — Chrome-Glas unverändert; Toolbar: `waveform` (Rohrpost) · `square.and.pencil` (Briefpapier) · `seal` (Siegelpresse-Menü) | Root |
| `LetterComposeView`, `LetterSeals` | Briefpapier + Wachssiegel (Siegelbruch bleibt DER laute Moment) | Sheet |
| `LetterWorkshopView` | Marken-Werkstatt (Sticker = Briefmarken des Paares) | Sheet |
| `VoiceNotes` | **Rohrpost** (Sprachkapsel) | Sheet |
| `PinnedMessages` | **Das Brett** (angepinnte Zettel überm Pult; iPad-Rail bleibt) | Root |
| `TouchGridCard` (groß), `DuetView`, `HapticStudioView` | **Telegramme**: Touch-Raster, Klopfzeichen-Duett, **Morsestube** | +1 |
| `ZeitpostView`, `PostJournalView` | **Siegelpresse** (Zeitpost aufgeben · Kapsel versiegeln · Türchen-Kalender bauen) + Sendungsbuch | Sheet / +1 |
| `RepairConsiderationView` | **Versöhnungsbrief** (Briefpapier mit Bedenkzeit) | Sheet |

**Spielen → Station 3 SPIELTISCH**

| Heute | Neu | Ebene |
|---|---|---|
| `PlayHubView` | Spieltisch-Root: Aushang → aufliegende Blätter → Kartenschrank → Spielbuch (§4.3) | Root |
| Offene Sessions | **Aufliegende Blätter** (2°-Fächerung, Bestand) | Root |
| `WordleView` + `DailyQuestsView` | **Tagesaushang** (das tägliche Blatt + Tagesaufgaben) | Root / +1 |
| Async-Katalog (battleship, kniffel, stadtlandfluss, twotruths, pictionary, wordchain, hangman, bingo, wordleduo, dame, reversi, kaesekaestchen, gomoku, mancala, memoryduo, story) | **Fernpartien** (Fach 1) — Spielkarten-Umschläge, native `.badge` | +1 |
| Live-Katalog (connectfour, photomemory, quizduel, emojiriddle-live, truthordare-live, rps) | **Am Tisch** (Fach 2) | +1 |
| Party/Gespräch (quiz, thisorthat, wouldyourather, truthordare, questions36, emojiriddle, wordparty) | **Feste & Fragen** (Fach 3) | +1 |
| `DateIdeasView`, `MovieRouletteView` | Ausgehkarten & Kinoprogramm (Fach 3) | +1 |
| `TournamentView`, `GamesRecordView`, `ReplayView`, Tutorials (`GameIntroCatalog`) | **Spielbuch** — Zeilen mit **Adoption A1 (Punktlinien-Seitenzahlen)** | +1 |
| `GameTableView`, `GameEngine`, `GamesCoordinator` | unsichtbare Tisch-Infrastruktur, unverändert | — |

Alle 34 `GameDestination`-Fälle sind gemappt (gegen `PlayHubView.swift` verifiziert:
30 Spiele + tutorials/season/replay/record).

**Wir (Memories) → Station 4 ARCHIV** — sechs Fächer statt 18 Kacheln; iPad behält den
handgebauten Split (`MemoriesSidebarGroup` wird von 4 auf 6 Gruppen umgeschnitten,
`sidebarAdaptable` bleibt vertagt).

| Fach | Inhalt (heutige Screens) | Ebene |
|---|---|---|
| **Alben** | `GalleryView`/`GalleryPagerView`/`MediaLightbox`, `VideoGalleryView`/`VideoPlayerScreen`, `PotdView` (mit A2-Modifier), `EventsView`, `StoryTimelineView`, `YearReviewView` | +1, Lightbox +2 |
| **Planfach** | `SharedListsView`, `BucketListView`, `WeekplanView` (Laufzettel der Woche) | +1 |
| **Wertfach** | `CouponsView` (**Wertmarken**, Scallop bleibt), `GoalsView` (**Postsparbuch**) | +1 |
| **Chronik** | `JournalView`, `LoveStatsView`, `SoundtrackView`, `CanvasView` (+ `CanvasExportSheet`), `MagazineView` (**Monatspost**), `WeekReviewView` (**Wochenpost**-Archiv), `NeedsHistoryView` (Eilboten-Chronik) | +1 |
| **Lagerfach** | `CapsulesView` (Kapseln reifen), `SeasonCalendarView` (Türchen-Kalender) | +1 |
| **Tresorfach** | `VaultView` + `VaultItemViewer` (Face-ID-Gate bleibt) | +1 / +2 |
| Recent-Strip | „Zuletzt eingeordnet" über der Schrankfront | Root |

`.searchable` im Alben-Stack (Recon-Sweep, Bestand).

**Mehr (Settings) → Station 5 AMT**

| Heute | Neu (Amts-Abschnitt) | Ebene |
|---|---|---|
| Profil/Paar, `ProfileEditSheet`, `PairingCodeSheet` | **Unser Amt** | Sheet |
| `NotificationSettingsSheet` | **Zustelldienst** (Zustellzeiten + Zustellrunden-Schalter §4.6 + Setzkasten) | Sheet |
| `CustomQuestionsView` | **Setzkasten** (eigene Tagesfragen; zusätzlich aus dem Kontextmenü des heutigen Briefs) | Sheet |
| `ServerListSheet`, `DeviceManagerSheet`, `MigrationAssistantView` | **Zustellbezirke** (Server) · **Zweigstellen** (Geräte) · Umzugshelfer | Sheet |
| `WidgetStudioView`, `LiveActivitySheet` | **Aushangkasten** | Sheet |
| `PersonalizationView`, `IconGiftView` | Schreibzeug (Tinten) · **Prägeplatten** (Icons; Unwrap bleibt Overlay) | Sheet |
| `AutomationsGalleryView`, `IntelligenceConsentSheet` | Sortiermaschine · Einverständnis | Sheet |
| `ICloudSheet`, `RecoverySheet` (`RecoveryViews`), App-Sperre | **Sicherung & Schlüssel** | Sheet |
| `DiagnosticsView`, `VersionHistoryView`, `SoundCreditsView`, `HandbookView` | **Betriebsbuch** (+ Gefahrenzone am Ende, wie heute) | Sheet / +1 |
| Kino-Replay | „Die Amtsgründung noch einmal ansehen" | Cover |

**App-weite Overlays & Zeremonien (RootView-ZStack, unverändert verdrahtet):**
`DailyRevealCeremonyView` (Siegelbruch — bleibt DIE Zeremonie), `PostNoteOverlay`
(Zustell-Moment), `TouchReceivedOverlay`/`PulseReceivedOverlay`/`HapticReceivedOverlay`
(Telegramm-Empfang), `PairingCeremonyView` (Amtsgründung), `LevelUpCeremonyView`/
`BadgeCeremonyView`/`IconGiftUnwrapView`, `LichtscheinHost`, `DelightOverlayHost`,
`ToastView`, `LockScreenView`. **Widgets/Intents/Live Activities:** außerhalb des
App-Targets, nur Erzählung/L10n („Der heutige Brief", „Sendung unterwegs") — keine
Struktur-Änderung. Deep Links (`sooodreamy://reveal` → Postfach) und die Chat→Album-Brücke
bleiben Verträge.

### 2.3 a11y-ID-Vertrag

**Stabil (nie anfassen):** `tab.home`, `tab.chat`, `tab.play`, `tab.us`, `tab.settings`,
`cinematic.skipAll`, `home.firstGreeting`, `chat.composer`/`chat.send`, `zeitpost.*`,
`pairing.*`, `server.*`, `recovery.*`, `onboarding.path.*`, `demo.badge`.
**Neu (nach Bedarf der Welle):** `postfach.ablage`, `spieltisch.spielbuch`,
`archiv.fach.*`, `amt.zustellrunden`. Es entfällt KEINE bestehende ID.

---

## §3 Ordner-Neubau

### 3.1 Zielbaum `SoooDreamy/ios/SoooDreamy/`

Grundsatz: **Stationen statt Feature-Sammelordner.** Nur die View-Schicht zieht um;
`App/`, `UI/`, `Core/`, `Content/` (+ `Data/`), `Intents/`, `Resources/` bleiben
byte-identisch liegen (Package.swift-Schonung). Auf `ios/`-Ebene bleiben `Shared/`,
`Widgets/`, `LogicTests/`, `UITests/`, `Config/`, `scripts/`, `Package.swift`,
`project.yml` unverändert (project.yml globt `path: SoooDreamy`,
`createIntermediateGroups: true` — verifiziert, keine Änderung nötig).

```
ios/SoooDreamy/
├── App/                  # unverändert + NEU: DemoBadge.swift (globales Chrome-Band)
├── UI/                   # unverändert — Design-System, einziger Rohwerte-Ort
├── Core/                 # unverändert
├── Content/              # unverändert + NEU (Welle N2): ZustellrundenLogic.swift
│   └── Data/             # unverändert
├── Intents/, Resources/  # unverändert
├── Kino/                 # ex Features/Onboarding: Amtsgründung, Pairing, Recovery
├── Zeremonien/           # app-weite Momente (RootView-Overlays)
├── Zustelldienst/        # Rituals-Domäne: API, Modelle, AppState-Extension, L10n
└── Stationen/
    ├── Postfach/         (+ Zustellfach/)
    ├── Schreibstube/     (+ Briefpapier/, Rohrpost/, Telegramme/, Siegelpresse/)
    ├── Spieltisch/       (+ Spiele/, Spielbuch/)
    ├── Archiv/           (+ Alben/, Planfach/, Wertfach/, Chronik/, Lagerfach/, Tresorfach/)
    └── Amt/
```

### 3.2 Autoritative Datei-Mapping-Tabelle (alle 147 Feature-Dateien; wird 1:1 ausgeführt)

Übernommen aus `NEUBAU_POSTAMT.md` §6.2 und **gegen den echten Baum verifiziert**
(§3.4); eine Korrektur: die Games-Kopfzeile des Dossiers behauptete „41 Dateien" —
es sind **40** (die Aufzählung selbst war vollständig). Welle N1 ist ein reiner
`git mv` (Dateinamen bleiben; Typ-Renames sind Kür in N4). ⚠ = Pfad steht explizit
in `ios/Package.swift`.

**Features/Home/ → (29 Dateien)**

| Datei | Neuer Pfad unter `ios/SoooDreamy/` |
|---|---|
| DashboardView.swift · DashboardHeaderView.swift · WaitingForPartnerCard.swift · LevelCard.swift · BadgeShelfView.swift · StreakCalendarView.swift · WhatsNewView.swift · MoodPickerSheet.swift · PresenceViews.swift · Heart3DView.swift | Stationen/Postfach/⟨Name⟩ |
| PlatformL10n.swift ⚠ | Stationen/Postfach/PlatformL10n.swift |
| DailyQuestionCard.swift · DailySparkCard.swift · CheckinCard.swift · MissedInboxCard.swift · FlashbackCard.swift · FirstMomentCard.swift · QuestCard.swift · DateNightView.swift · HugQueueView.swift | Stationen/Postfach/Zustellfach/⟨Name⟩ |
| PulseFan.swift · TouchGridCard.swift · DuetView.swift · HapticStudioView.swift | Stationen/Schreibstube/Telegramme/⟨Name⟩ |
| ZeitpostView.swift · PostJournalView.swift | Stationen/Schreibstube/Siegelpresse/⟨Name⟩ |
| RevealCeremonyView.swift · TouchReceivedOverlay.swift · PostNoteOverlay.swift | Zeremonien/⟨Name⟩ |

**Features/Chat/ → (9 Dateien)**

| Datei | Neuer Pfad |
|---|---|
| ChatView.swift · ChatModel.swift · ChatPaper.swift · PinnedMessages.swift | Stationen/Schreibstube/⟨Name⟩ |
| ChatL10n.swift ⚠ | Stationen/Schreibstube/ChatL10n.swift |
| LetterComposeView.swift · LetterSeals.swift · LetterWorkshopView.swift | Stationen/Schreibstube/Briefpapier/⟨Name⟩ |
| VoiceNotes.swift | Stationen/Schreibstube/Rohrpost/VoiceNotes.swift |

**Features/Games/ → (40 Dateien)**

| Datei | Neuer Pfad |
|---|---|
| PlayHubView.swift · GameEngine.swift · GamesCoordinator.swift · GamesAppState.swift · GamesA11y.swift · GamesPaperKit.swift · GameTableView.swift · BoardDuelKit.swift · DailyQuestsView.swift | Stationen/Spieltisch/⟨Name⟩ |
| GamesL10n.swift ⚠ | Stationen/Spieltisch/GamesL10n.swift |
| BattleshipView · ChoiceGamesView · ConnectFourView · DameView · DateIdeasView · EmojiRiddleLiveView · EmojiRiddleView · GomokuView · KaesekaestchenView · KniffelView · MancalaView · MemoryDuoView · MovieRouletteView · PhotoMemoryView · PictionaryView · Questions36View · QuizDuelView · QuizGameView · ReversiView · StadtLandFlussView · TruthOrDareLiveView · TruthOrDareView · TwoTruthsView · WordleView · WordPartyGamesView · GamesWaveView (je .swift, 26 Stück) | Stationen/Spieltisch/Spiele/⟨Name⟩ |
| TournamentView.swift · ReplayView.swift · GamesRecordView.swift · WordleRecordView.swift | Stationen/Spieltisch/Spielbuch/⟨Name⟩ |

**Features/Memories/ → (25 Dateien)**

| Datei | Neuer Pfad |
|---|---|
| MemoriesView.swift · MemoriesHubComponents.swift | Stationen/Archiv/⟨Name⟩ |
| MemoriesL10n.swift ⚠ | Stationen/Archiv/MemoriesL10n.swift |
| GalleryView · GalleryComponents · GalleryPagerView · MediaLightbox · VideoGalleryView · VideoPlayerScreen · PotdView · EventsView · StoryTimelineView · StoryModels · YearReviewView (je .swift, 11 Stück) | Stationen/Archiv/Alben/⟨Name⟩ |
| SharedListsView.swift · BucketListView.swift | Stationen/Archiv/Planfach/⟨Name⟩ |
| CouponsView.swift | Stationen/Archiv/Wertfach/CouponsView.swift |
| JournalView · LoveStatsView · SoundtrackView · CanvasView · CanvasExportSheet (je .swift) | Stationen/Archiv/Chronik/⟨Name⟩ |
| VaultView.swift · VaultItemViewer.swift | Stationen/Archiv/Tresorfach/⟨Name⟩ |
| OnThisDayCard.swift | Stationen/Postfach/Zustellfach/OnThisDayCard.swift |

**Features/Rituals/ → (15 Dateien — der Ordner löst sich auf)**

| Datei | Neuer Pfad |
|---|---|
| RitualsDashboardSection.swift · DaymemoView.swift | Stationen/Postfach/Zustellfach/⟨Name⟩ |
| RepairConsiderationView.swift | Stationen/Schreibstube/Briefpapier/RepairConsiderationView.swift |
| CustomQuestionsView.swift | Stationen/Amt/CustomQuestionsView.swift |
| WeekplanView.swift | Stationen/Archiv/Planfach/WeekplanView.swift |
| WeekReviewView.swift · MagazineView.swift · NeedsHistoryView.swift | Stationen/Archiv/Chronik/⟨Name⟩ |
| GoalsView.swift | Stationen/Archiv/Wertfach/GoalsView.swift |
| CapsulesView.swift · SeasonCalendarView.swift | Stationen/Archiv/Lagerfach/⟨Name⟩ |
| RitualsAPI.swift · RitualsAppState.swift · RitualsModels.swift | Zustelldienst/⟨Name⟩ |
| RitualsL10n.swift ⚠ | Zustelldienst/RitualsL10n.swift |

**Features/Settings/ → (18 Dateien)** — alle 18 flach nach `Stationen/Amt/⟨Name⟩`
(SettingsView, PersonalizationView, IconGiftView, WidgetStudioView, LiveActivitySheet,
NotificationSettingsSheet, AutomationsGalleryView, IntelligenceConsentSheet,
DeviceManagerSheet, MigrationAssistantView, ServerListSheet, ICloudSheet, DiagnosticsView,
VersionHistoryView, SoundCreditsView, HandbookView, dazu ⚠ IntelligenceL10n.swift und
⚠ SettingsL10n.swift).

**Features/Onboarding/ → (11 Dateien)**

| Datei | Neuer Pfad |
|---|---|
| CinematicChapterPlayer · CinematicChapterStages · CinematicHandoff · CinematicIntroView · OnboardingFlowView · PairingView · QRSupport · RecoveryViews (je .swift) | Kino/⟨Name⟩ |
| OnboardingL10n.swift ⚠ | Kino/OnboardingL10n.swift |
| PairingCeremonyView.swift | Zeremonien/PairingCeremonyView.swift |
| DemoBadge.swift | App/DemoBadge.swift (verifiziert counter-neutral, §3.4) |

**Kontrollsumme:** 29 + 9 + 40 + 25 + 15 + 18 + 11 = **147** = `rg --files
SoooDreamy/ios/SoooDreamy/Features | wc -l`. Kein Verlust, keine Doppelung.
**Neue Dateien (Welle N2, keine Moves):** `Content/ZustellrundenLogic.swift`
(+ Package.swift-`sources`-Eintrag), `LogicTests/ZustellrundenLogicTests.swift`;
`UI/Theme.swift` erweitert `Theme.Motion.Signature` um
`briefschlitz`/`spindelstich`/`lascheAuf`/`schubladenauszug`/`entwickeln` (A2) —
bestehende Datei, keine neue.

### 3.3 Die exakten Pflicht-Edits (im SELBEN Commit wie die Moves, Welle N1)

1. **`ios/Package.swift`** — genau **8 Pfade** ändern sich (verifiziert: nur diese 8
   Feature-Dateien stehen im Manifest):
   `SoooDreamy/Features/Chat/ChatL10n.swift` → `SoooDreamy/Stationen/Schreibstube/ChatL10n.swift` ·
   `Features/Games/GamesL10n.swift` → `Stationen/Spieltisch/GamesL10n.swift` ·
   `Features/Memories/MemoriesL10n.swift` → `Stationen/Archiv/MemoriesL10n.swift` ·
   `Features/Onboarding/OnboardingL10n.swift` → `Kino/OnboardingL10n.swift` ·
   `Features/Home/PlatformL10n.swift` → `Stationen/Postfach/PlatformL10n.swift` ·
   `Features/Rituals/RitualsL10n.swift` → `Zustelldienst/RitualsL10n.swift` ·
   `Features/Settings/IntelligenceL10n.swift` → `Stationen/Amt/IntelligenceL10n.swift` ·
   `Features/Settings/SettingsL10n.swift` → `Stationen/Amt/SettingsL10n.swift`.
   Alle `Content/`-, `Core/`- und `Shared/`-Einträge bleiben wörtlich. Gate: `swift test`
   grün auf Linux.
2. **`tools/charter_lint.sh`** — **9 Grep-Stellen** tragen den Literal-Pfad
   `ios/SoooDreamy/Features` (verifiziert; das Postamt-Dossier zählte 8 und übersah
   `bright_paper_features`): `bare_white_opacity` (+ ios/Widgets), `raw_corner_radius`,
   `hardcoded_pink_purple_features`, `ultrathin_material_features`,
   `surface_glass_features`, `bright_paper_features` (ZWEI count-Zeilen: `all_paper` und
   `night_paper`), `raw_rotation_features`, `system_size_fonts` (+ ios/Widgets) und der
   Deckel `torn_edge_uses` (+ ios/Shared ios/Widgets). Ersetzung überall:
   `ios/SoooDreamy/Features` → `ios/SoooDreamy/Stationen ios/SoooDreamy/Kino
   ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst`. Der Glob `!**/UI/*`
   (`smallcaps_features`) bleibt unangetastet — `UI/` zieht nicht um.
   `tools/charter_baseline.json` wird NICHT angefasst. Gate: Zähler VOR und NACH dem
   Move identisch.
3. **`ios/.swiftlint.yml`** — genau eine Regel: `no_bare_opacity_in_features`,
   `included: '.*Features/.*'` → `'.*(Stationen|Kino|Zeremonien|Zustelldienst)/.*'`.
   (Die übrigen drei Regeln sind pfad-neutral; `excluded: '.*UI/Theme\.swift'` bleibt.)
4. **Keine Änderung nötig:** `ios/project.yml` (Glob + `createIntermediateGroups`),
   UITests (fahren über a11y-IDs, nie über Pfade/Typnamen), Widgets/Shared/Server.

### 3.4 Prüfprotokoll der Jury (Stichproben gegen den echten Baum, alle bestanden)

- `rg --files ios/SoooDreamy/Features | wc -l` = **147**; per Ordner: Chat 9, Games 40,
  Home 29, Memories 25, Onboarding 11, Rituals 15, Settings 18 — die Postamt-Tabelle
  §6.2 enumeriert exakt diese Dateien (einzige Korrektur: Games-Kopfzeile „41" → 40).
- `ios/Package.swift`: exakt die 8 ⚠-Pfade als einzige Feature-Einträge — bestätigt.
- `charter_lint.sh`: 9 Features-Pfad-Stellen (inkl. `bright_paper_features` mit zwei
  counts, Zeilen 108–211) — Liste in §3.3(2) ist vollständig.
- `DemoBadge.swift` (55 Zeilen): enthält KEINES der pfad-gescopten Muster
  (`white.opacity(0.` / `cornerRadius:` / `Theme.pink|purple|rose` / `ultraThinMaterial` /
  `glassCard(` / `.paperCard(` / `.rotationEffect(` / `.system(size:` / `TornEdgeShape`) —
  der Umzug nach `App/` (aus dem Lint-Scope heraus) ist zähler-neutral; das
  Identitäts-Gate von N1 hält.
- `GameDestination` = 34 Fälle (30 Spiele + tutorials/season/replay/record) — die
  Spieltisch-Fächer decken alle.
- `MemoriesSidebarGroup` = 4 Gruppen (remember/plan/rituals/private) — der 4→6-Umschnitt
  ist eine reine Mapping-Änderung.
- UITests: `switchTab(id:labelPrefix:)` ist ID-first (Label nur Fallback) — Label-Wechsel
  brechen den Tab-Wechsel nicht; harte Inhalts-Anker sind `navigationBars["Mehr"]`
  (`settings.title`, separater L10n-Key von `tab.more` — verifiziert), „Wir zwei"
  (`MemoriesL10n`), „Kleine Spiele" (`GamesL10n`), „Zeitpost planen"-Kachel,
  „Schreib etwas Liebes"-Placeholder, `home.firstGreeting` — Wellen-Zuordnung in §5.
- Typecheck-Brocken (echte Zeilen): `ChatView.swift` 2 714 · `PlayHubView.swift` 1 786 ·
  `SettingsView.swift` 1 227 · `MemoriesView.swift` 1 084.

---

## §4 Bindende Seiten-Kompositionen

Gesetze für alle Stationen: Standardfläche `nightCard()` auf Nachtkarton, helles Papier NUR
am Hero-Artefakt; genau EIN `briefbogen` pro Screen; Artefakt-Budget 3/1/1; Serif nur auf
Papier; `legen`-Stagger 40 ms max. 6; jede neue Fläche registriert ihre fünf Zustände in
`PolishAudit` vor dem Merge. Alle Signature-Momente sind **benannte Modifier der
UI-Schicht** (`Theme.Motion.Signature`), jeder mit VoiceOver-Ansage und
Reduce-Motion-Pfad (Gebot 13); Klang nur aus `SoundEngine`-Synth-Presets, Haptik aus
`Haptics`/`HapticPatternKit`. **Postdeutsch-Budget (hart): pro Screen genau EINE
Post-Vokabel — im Titel oder im Stempel, nie in beiden, nie im Fließtext.**

### 4.1 POSTFACH (`tab.home`)

**Zonen (iPhone, von oben):** (1) **Kopf** — `DashboardHeaderView` als „die zwei Beamten"
+ **Dienstlicht** (Energie beider als Lampenschein-Punkt `Licht.lampengold` → `Licht.glut`
→ `Theme.energyRed`; Icon-Kontrast ≥ 3:1 auf Nacht; Tap = Energie setzen).
(2) **Zustellfach** — Stempelzeile AUF dem Hero-Papier („MORGENPOST · TAG 137",
`Typo.anschrift`, nie auf Nacht), darunter der EINE `paperCard(.briefbogen)`-Hero per
`DashboardPriority`, dann ≤ 3 `nightCard()`-Zustellkarten (Eilbote, Türchen,
Spielzug-Aviso, „Heute vor …" mit **A2 Polaroid entwickeln**). (3) **Ablage** — der
„Mehr"-Fold als Ablagekorb + Herz-Coda; `PulseFan` bleibt Chrome-FAB.
**Signature — Der Briefschlitz:** beim ersten Vordergrund-Eintritt einer neuen
Zustellrunde gleitet der Hero durch eine 1-pt-`Nacht.naht`-Hairline unterm Stempel
(`Signature.briefschlitz` auf `arrive`); Haptik `tap` + `rigid`-Tick, Klang papierenes
„Flap". VoiceOver: „Tagespost ist da: {Titel}." Reduce Motion: Karte liegt sofort +
statischer Lichtschein. **iPhone:** eine Spalte. **iPad:** die balancierten Spalten aus
`DashboardPriority.balancedColumns` bleiben; der Hero behält die volle Breite.

### 4.2 SCHREIBSTUBE (`tab.chat`)

**Zonen:** (1) **Brett** — gepinnte Zettel oben (iPad: Rail rechts, Bestand).
(2) **Spindel** — der Zettelwechsel wie gebaut (brief/karton, 4-pt-Tintenkante,
Poststempel-Tagestrenner, versiegelte Briefe, `.searchable` nativ,
`defaultScrollAnchor(.bottom)`). (3) **Pult** — Eingabeleiste bleibt Chrome-Glas;
Toolbar: Rohrpost (`waveform`) · Briefpapier (`square.and.pencil`) · **Siegelpresse-Menü**
(`seal`: „Zeitpost aufgeben" / „Kapsel versiegeln" / „Türchen-Kalender bauen") — drei
native Toolbar-Items, keine Custom-Bar. Unterseiten: Telegramme (Touch-Raster groß,
Klopfzeichen-Duett, Morsestube), Briefpapier-Composer, Marken-Werkstatt, Versöhnungsbrief.
**Vorher-Pflicht (N3):** `ChatView.swift` (2 714 Zeilen) wird in Zonen-Dateien zerlegt
(Brett/Spindel/Pult), sonst wird der Xcode-Typecheck zum Blocker.
**Signature — Der Spindelstich:** der eigene Zettel landet per `legen`; im Aufliege-Frame
ein 6-pt-Tintenpunkt (`coupleTint.tintePrimary`) an der Oberkante; Haptik weich →
`rigid`-Stich, trockener Tick; Antwort im selben Frame (Gebot 14). Reduce Motion: Punkt
per Fade. **iPad:** wie heute (Rail ab regular width).

### 4.3 SPIELTISCH (`tab.play`)

**Zonen:** (1) **Aushang** — Saison-Zeile mit Monats-Poststempel + Tagesaushang
(Wordle-Blatt, Tagesaufgaben). (2) **Aufliegende Blätter** — offene Partien als
ausgeteilte Hände (2°-Fächerung seeded = die EINE Rotation des Screens; Zug-Badge nativ).
(3) **Kartenschrank** — drei Fächer (einklappbar, `@AppStorage` wie heute): Fernpartien ·
Am Tisch · Feste & Fragen; Spiele als Spielkarten-Umschläge mit Anschrift-Zeile.
**Adoption A1:** jede Fach-Kopfzeile trägt die Punktlinien-Zeile
„{Fachname} ····· {n}" (`Typo.anschrift` + Punktlinie + `Typo.number` = gespielte Partien
des Fachs). (4) **Spielbuch** — Turnier · Siegerliste · Wiederholungen · Anleitungen als
dieselbe Punktlinien-Zeilen-Anatomie. `NavigationStack(path:)` mit `GameDestination`
bleibt wörtlich; Bretter bleiben auf dem Papier-Bogen im Lichtkegel (`GamesPaperKit`).
**Signature — Lasche auf:** Spielstart klappt die Dreiecks-Lasche des Umschlags per
`rotation3DEffect` (0° → −150°, `anchor: .top`, als `Signature.lascheAuf` benannt) auf,
dahinter blättert das Brett herein; Haptik `rigid`, kurzer heller Riss-Tick. Reduce
Motion: Crossfade + Lichtschein. Match-Feiern bleiben Lichtschein Stufe 1–2, `epic` nur
Monats-Ereignisse. **iPad:** Fächer zweispaltig ab regular width, Bretter zentriert
(`contentColumn`).

### 4.4 ARCHIV (`tab.us`)

**Zonen:** (1) **Zuletzt eingeordnet** — Recent-Strip als drei Mini-Polaroids/Zettel
(Bestand). (2) **Schrankfront** — sechs Fach-Karten (`nightCard()` mit 2-pt-Stapelkante),
ehrliche Zähl-Badges (Bestands-Logik); ein Fach öffnet INLINE (expandiert, schiebt seine
Sektionszeilen aus), erst die Sektion pusht (Ebene 1), Details Ebene 2.
**Signature — Der Schubladenauszug:** Sektionszeilen gleiten mit `settle` horizontal ein
(x −12 → 0, Stagger 40 ms, max. 6), am Ende EIN weicher Haptik-Detent — klanglos
(Gebot 3: fühlbar statt hörbar). VoiceOver: „{Fach}, {n} Bereiche, aufgeklappt." Reduce
Motion: Fade, Detent bleibt. **iPad:** der handgebaute Split bleibt; die sechs Fächer
SIND die Sidebar-Gruppen (`MemoriesSidebarGroup` 4 → 6, reine Mapping-Änderung;
`sidebarAdaptable` bleibt vertagt). `.searchable` im Alben-Stack; Tresorfach behält das
Face-ID-Gate.

### 4.5 AMT (`tab.settings`)

Still, KEINE Artefakte, kein Korn (Werkzeug-Räume bleiben still). Native
`Form`/`.formStyle(.grouped)` auf Nachtkarton, sechs Abschnitte: Unser Amt ·
Zustelldienst · Zweigstellen & Bezirke · Werkstatt · Sicherung & Schlüssel ·
Betriebsbuch (Gefahrenzone am Ende, wie heute). Alle heutigen Sheets bleiben Sheets.
**Signature — Der Schlüsseldreh:** Scharfschalten der App-Sperre rotiert das
`key.horizontal`-Symbol einmal um 90° via `symbolEffect(.rotate.byLayer, options:
.nonRepeating)` (natives Symbol-Motion — `raw_rotation_features` bleibt unberührt);
ein metallischer `rigid`-Klick, klanglos. Reduce Motion: Symbolwechsel per Fade.
**iPhone/iPad:** identisch; iPad zentriert die Form (`contentColumn`).

### 4.6 Zustellrunden (bindende Dramaturgie-Regeln)

Drei Runden inszenieren nur, was ohnehin da ist (Morgenpost 05–11 · Tagespost 11–17 ·
Nachtpost 17–05, Stempelzeile „{RUNDE} · TAG {n}"). Zustandsmodell: neue pure Datei
`Content/ZustellrundenLogic.swift` (+ `LogicTests/ZustellrundenLogicTests.swift`,
Package.swift-Eintrag) ersetzt `DayPhase` in `DashboardPriority` — berechnet bei
`scenePhase == .active`, nie im Blick des Nutzers; Ein-Marken-Modell
(`@AppStorage("postfach.letzteInszenierung")` = „{dateKey}#{runde}") steuert
ausschließlich Briefschlitz + Stempelzeile. **Respekt-Regeln (hart):** abschaltbar (Amt →
Zustelldienst → „Zustellrunden inszenieren", Default an; aus = statischer Einstieg,
Stempel nur „TAG {n}"); KEINE neuen Pushes (`NotificationDamping` bleibt einzige
Autorität); Runden sind Bühne, nie Gate (nicht Inszeniertes liegt einfach im Fach);
Runden sind gerätelokal (ehrlich dokumentiert); VoiceOver-Announcement mit ganzem Satz.

---

## §5 Umbau-Wellen N1–N4 (mit Beweis-Gates)

Grundregel jeder Welle: Funktion vor Bühne (kein Screen verliert je eine Fähigkeit, auch
nicht für einen Commit); `charter_lint.sh --update` nur für SINKENDE Zähler; jede Welle
endet mit `swift test`, Screenshot-Matrix inkl. `paired-ax5-de.png` und den drei
PR-Antworten des Noble-Tests.

**N1 — Der Umzug (EIN atomarer Commit, reiner Struktur-Move).** Alle 147 `git mv` aus
§3.2 + die drei Anker aus §3.3. Kein Verhaltens-Diff, kein Rename, kein L10n-Diff.
Freeze-Fenster mit parallel arbeitenden Agents (der Move ist der Rebase-Killer; danach
rebased jeder offene Branch billig, `git log --follow` bleibt intakt).
*Gates:* `swift test` grün auf Linux · `bash tools/charter_lint.sh` mit **identischen
Zählern** vor/nach (Vorher/Nachher-Ausgabe als PR-Pflichtbeweis; Baseline unangetastet) ·
`xcodegen generate` + Simulator-Build · UITest-Suite test01–test05 unverändert grün.

**N2 — Runden & Postfach.** `ZustellrundenLogic` + Tests + Manifest-Eintrag;
`DayPhase` → `Zustellrunde` in `DashboardPriority` (LogicTests neu gepinnt — **bewusster
Test-Commit**, nie nebenbei); Postfach-Zonen (Kopf/Dienstlicht, Stempelzeile,
Zustellfach, Ablagekorb); Briefschlitz; **Adoption A2** auf der „Heute vor …"-Karte;
Zustellzettel-Accessory; Tab-Labels + Symbole (nur L10n-WERTE und `systemImage`,
IDs unangetastet — `switchTab` ist ID-first, verifiziert); Amt-Schalter „Zustellrunden";
Sendung Nr. 1 (`WaitingForPartnerCard` umerzählt) + erste Dienstgänge (Quest-Texte).
**Bindend:** die Telegramm-Leiste des Postfachs behält die Zeitpost-/Journal-Stationen
samt `zeitpost.*`-Sheet — die test04-Anker („Zeitpost planen") bleiben unangefasst.
`settings.title` („Mehr") bleibt in N2 unverändert (separater Key von `tab.more`,
verifiziert) — test02 bleibt ohne Anpassung grün.
*Gates:* UITests grün OHNE Test-Diff · neue LogicTests pinnen Runde/Marke/Rangfolge ·
AX5-Shot des Postfachs · Artefakt-Inventur ≤ 3/1/1 · Flugmodus-Probe (Gebot 8).

**N3 — Schreibstube & Spieltisch.** Vorher-Pflicht: `ChatView.swift`-Zerlegung in
Zonen-Dateien (< 300-Zeilen-Subviews, explizite Typen — Typecheck-Schutz). Dann:
Siegelpresse-Menü (ADDITIV — die Postfach-Einstiege bleiben), Telegramme-Seite (Umzug der
Vollwerkzeuge, Postfach behält die kompakte Leiste), Spindelstich; Spieltisch-Zonen
(Aushang, Kartenschrank-Dreiteilung — heutige Gruppen umgeschnitten), **Adoption A1**
(Punktlinien-Zeilen), Lasche auf.
*UITest-Anpassungen benannt:* test03 (Chat senden/suchen — Placeholder „Schreib etwas
Liebes" nur ändern, wenn im selben PR der Test nachzieht); „Kleine Spiele"-Anker
(`GamesL10n`) zieht im selben PR nach, wenn der Hub-Untertitel neu formuliert wird.
*Gates:* test03 + test04 grün · Fünf-Zustände-Einträge in `PolishAudit` für jede neue
Fläche · Zähler sinken oder halten (Spindel/Umschläge laufen über `paperCard`/`nightCard`
und `Theme.Motion.*`).

**N4 — Archiv, Amt & Kino-Anschluss (+ Kür-Renames).** `MemoriesSidebarGroup` 4 → 6
Fächer (Vollständigkeits-Garantie testbar halten), Schrankfront + Schubladenauszug;
Amt-Sektionen neu geordnet + Schlüsseldreh; `settings.title` „Mehr" → „Amt" **im selben
PR** wie die test02-Anpassung (`navigationBars["Mehr"]` → `["Amt"]`, `labelPrefix:
"Mehr"` → `"Amt"`, „Sprache"-Zeilen-Anker prüfen); „Wir zwei"-Anker analog, falls der
Archiv-Titel wechselt. Kino-Anschluss: Caption-Schicht „Amtsgründung" (L10n-Overlay,
kein Video-Rerender), Musterbetrieb-Band, Kino-Replay-Text im Amt. Optional (nur bei
ruhiger See): Typ-Renames `DashboardView → PostfachView`, `MemoriesView → ArchivView`,
`SettingsView → AmtView`, `TodayAccessoryView → ZustellzettelView` — Kür, nie Blocker.
*Gates:* kompletter UITest-Durchlauf (test01–test05) · Screenshot-Matrix inkl.
`paired-ax5-de` neu abgenommen · Reduce-Motion- und VoiceOver-Durchlauf aller fünf
Signature-Momente + A2 (drei Pfade je Moment, Gebot 13) · finale Ratchet-Ernte nur nach
unten.

**Reihenfolge der Beweise:** (1) N1-Invarianz — der Umzug ändert NICHTS Messbares;
(2) N2-Runden überleben die UITest-Journey ohne Test-Diff; (3) erst DANN wird Bühne
gebaut. Wer die Reihenfolge umdreht, debuggt Bühnenbilder auf wackligem Fundament.

---

## §6 Abgelehnte Ideen (damit sie nicht wieder aufpoppen)

1. **Kammer-Sheet statt Settings-Tab (Zimmerhaus):** bricht den `tab.settings`-Vertrag
   und jahrelanges Muskelgedächtnis für einen Gewinn, den ein stiller Amt-Tab genauso
   liefert.
2. **Küche als fünfter Tab (Zimmerhaus):** die Plan-Familie ist im Archiv (Planfach/
   Wertfach/Lagerfach) vollständig zuhause; ein Tab, der nur Plan-Paare belohnt, trägt
   an leeren Tagen nicht.
3. **Magnet-Kühlschrank & Möbel-Vokabular (Zimmerhaus):** Kühlschränke, Wäscheleinen und
   Kommoden existieren im Kino-Requisiten-Kanon nicht — zweite Metapher-Familie =
   Verwässerung.
4. **Lampenzug-Refresh (Zimmerhaus):** ein zweiter Signature-Moment auf dem Postfach
   neben dem Briefschlitz wäre Momente-Inflation auf dem meistgesehenen Screen.
5. **Ordner-Renames `Core/Content/UI` → `Kern/Fundament/Design` (Zimmerhaus):** ~90
   zusätzliche Package.swift-Pfade plus Lint-Glob-Umbau ohne einen einzigen sichtbaren
   Nutzen — der Stabilitätskern bleibt liegen.
6. **Tageschronik + `TintenschriftRenderer` (Almanach):** ein drittes Anzeigesystem über
   denselben Feeds mit eingestandenem Doppel-Wahrheits-Risiko; das Sendungsbuch bleibt
   die eine Chronologie.
7. **Morgen-Umschlag-Blättern (Almanach):** der Briefschlitz IST der eine
   Tagesankunfts-Moment — zwei Ankunfts-Choreografien pro Tag kann das Feier-Budget
   nicht tragen.
8. **Buchrücken-Regal mit 90°-Text (Almanach):** die riskanteste neue Fläche des Felds
   (AX5, Artefakt-Budget) mit einem Fallback, der sie zur Deko degradiert.
9. **Das Binden + Mondstand-Glyphe (Almanach):** Buch-Motive ohne Post-Bedeutung; das
   Monats-Ritual trägt bereits die Monatspost (`MagazineView`).
10. **`RootView`/`TodayAccessoryView` → `Buch/` und `RitualsAPI` → `Core/` (Almanach):**
    Shell bleibt `App/`, Domänen-Leitungen bekommen ihre eigene Heimat
    (`Zustelldienst/`) statt Schichten zu verwischen.
11. **Erstbetreten-„Licht an" pro Zimmer (Zimmerhaus):** fünf einmalige
    Begrüßungs-Choreografien multiplizieren Delight-Flächen; die Amtsgründung
    (PairingCeremony) bleibt der eine Ankunftsmoment.
12. **`sidebarAdaptable`-Wiedervorlage:** bleibt vertagt, wörtlich nach
    `STYLE_DECISION.md` §3.7 / Recon §2.7 — dieser Entscheid ändert daran nichts.

---

*Jury-Vorsitz, Neubau-Wettbewerb SoooDreamy. Ein Gewinner, zwei Adoptionen, vier Wellen —
kein Grammatik-Brei. Das Kino war schon immer die Gründung eines Postamts; jetzt wird das
Amt gebaut, in dem es endet.*
