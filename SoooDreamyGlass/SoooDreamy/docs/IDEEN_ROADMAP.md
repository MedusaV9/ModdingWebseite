# SooDreamy — Ideen-Roadmap

Synthese aus 50 Ideen-Sammler-Berichten (~500 Einzelideen) und einem Deep-Recon der Codebase.
Stand: August 2026, App/Server-Version 11.1.0. Alle „existiert schon"-Aussagen wurden per Grep
gegen den echten Code geprüft (nicht nur gegen das App-Profil, das die Sammler hatten).
Sammler-Quellen werden als `#NN` zitiert; die Legende steht im Anhang.

---

## 1. Leitplanken

Diese Rahmenbedingungen gelten für **jedes** Feature dieser Roadmap. Ideen, die eine davon
verletzen, stehen in Abschnitt 5 (Bewusst verworfen).

### 1.1 Sideload-Realität (unsignierte IPA)

Die App wird als **unsignierte IPA** verteilt und von den Nutzern selbst signiert
(typisch: freies Apple-Konto, 7-Tage-Resign). Konsequenzen:

- **Entfällt: gemanagte/bezahlte Entitlements.** Core NFC (Tag-Reading), JournalingSuggestions
  (nur auf Antrag), CarPlay, App Attest. Features darauf sind nicht machbar.
- **Entfällt: Apple-Konto-gebundene Dienste.** CloudKit-Zwang, Game Center, WeatherKit-Token,
  MusicKit-Developer-Token — alles setzt bezahltes Konto und/oder App-Store-Distribution voraus.
- **Degradiert: Push (APNs).** `aps-environment` greift nur mit echtem Provisioning-Profil +
  Server-`.p8`. Der Server meldet heute schon ehrlich `deliveryAvailable:false` — neue Features
  dürfen Push nur als Bonus nutzen, nie als Voraussetzung (lokale Benachrichtigungs-Brücke #12
  ist das Muster).
- **Fragil: Extensions.** Widget-Extension überlebt Ein-App-ID-Resigns nicht immer — genau dafür
  existiert das `SoooDreamyLite`-Target ohne PlugIns. Neue Extension-Typen (Share, Watch) sind
  deshalb keine tragfähige Basis.
- **Funktioniert ohne Entitlement:** FoundationModels, ImagePlayground, Translation, Speech,
  WidgetKit/App Intents/Live Activities (lokal), EventKit, PencilKit, MultipeerConnectivity,
  App Group (`group.app.sooodreamy.shared`, pro Signatur ggf. Suffix-Anpassung).

### 1.2 Privacy-Grundsatz

- Alle Daten liegen **auf dem Gerät oder auf dem selbst gehosteten Paar-Server** — keine
  Dritt-Cloud, keine Telemetrie, keine Analytics.
- Apple Intelligence ausschließlich **on-device** (FoundationModels); kein Cloud-LLM-Fallback.
  AI-Ausgaben sind immer Entwurf, nie Autosend (#07).
- Sicherheits-Invarianten (v4.0, nicht regressieren): Bearer nur im Header, Tokens nur als
  SHA-256-Digest gespeichert, keine Tokens in Backups/Exports, Log-Redaktion.

### 1.3 Design-Charter (Kurzfassung aus DESIGN.md)

- **Ratchets:** `tools/charter_lint.sh` führt 15 Zähler, die **nur sinken** dürfen
  (u. a. `bare_white_opacity` 238, `raw_corner_radius` 201, `fixed_font_sizes` 377);
  `ultrathin_material_features` und `version_graffiti` sind auf **0 gepinnt** — ein Treffer
  bricht CI. Große Refactors senken Baselines im selben Commit (`--update`).
- **3 Glas-Stufen:** `GlassLevel.chrome` (schwebende Controls) / `.surface` (Content-Karten,
  Default) / `.tinted` (genau **eine** Hero-Fläche pro Screen). Einziger sanktionierter
  Einstieg: `View.glass(_:in:)`. Glas-auf-Glas ist verboten; Innenflächen sind matt.
- **4 Motion-Kurven:** `Theme.Motion.settle/arrive/playful/drift` — keine freien Springs/Easings.
- **Kein Gradient auf Text**, maximal 2-Stop-Gradienten auf Flächen, 10-Uhr-Licht,
  konzentrische Radien.
- **Dark-only ist Markenentscheidung** — keine Light-Mode-Arbeit.
- **Prozess-Gates:** jede neue Surface muss in `PolishAudit` alle 5 Zustände beantworten
  (loading/empty/content/offline/failure); jede neue Feature-View braucht einen Handbuch-Anker;
  Releases bumpen Version im Lockstep (project.yml, server/package.json, PATCHNOTES, Handbuch,
  VersionHistory, WhatsNew) und tragen „made by Sonic0810".

---

## 2. Die 5 Säulen

### Säule 1 — UI-Rework mit echtem Liquid Glass → Vertiefung

**Status quo (Recon):** Die Migration ist **fertig**, nicht offen: Deployment-Target iOS 26,
`Glass.swift` kapselt das echte `glassEffect()` (chrome/surface/tinted), null `#available`-Gates,
null `ultraThinMaterial`-Fakes (Ratchet gepinnt), `SecondaryButtonStyle` nutzt bereits
`.regular.interactive()`. **Aber:** im gesamten Code gibt es **kein einziges**
`GlassEffectContainer`, `glassEffectID`, `scrollEdgeEffectStyle` oder
`backgroundExtensionEffect` (Grep verifiziert); Widgets sind komplett flach; der PrimaryButton
ist noch ein handgemalter Gradient mit Sheen; Aurora invalidiert mit 12 Hz unter jedem Glas.

**Vertiefung (Auswahl):**
- Ein `GlassEffectContainer` pro Region statt ~10 Einzel-Effekte im Dashboard; `glassEffectUnion`
  fürs Bottom-Chrome (#05, #04)
- Morphing als Signature-Moment: Canvas-FAB → Werkzeugpalette, Pulse-Fächer am 💭-FAB,
  Siegelbruch-Zoom beim versiegelten Brief (`glassEffectID`) (#01, #02, #03)
- PrimaryButton auf `.glassProminent` mit CoupleTint-Kontrastvertrag (#04, #01)
- Zentraler Reduce-Transparency-/Kontrast-Fallback in `GlassLevel` — heute nirgends behandelt (#03)
- Aurora-Invalidierung drosseln, Listen-Regel „Glas ist Chrome, Zellen sind matt" (#05)
- Chat-Composer als `safeAreaBar` mit interaktivem Glas (#01, #02)
- Nachrücker: Toolbar-Glasgruppen (#01), Layered App Icon aus dem Icon Composer (#01),
  `.clear`-Stufe über Medien (#04), Thermal-/LowPower-GlassBudget + Signpost-Messung (#05),
  Grundsatzfrage native `TabView` vs. `LiquidTabBar` (#01, #46 — Entscheid, kein Blindumbau)

### Säule 2 — Apple Intelligence / FoundationModels

**Status quo (Recon):** **Null Code** — kein `FoundationModels`-, `LanguageModelSession`-,
`ImagePlayground`-, `Translation`- oder `Speech`-Import im gesamten Projekt (Grep verifiziert).
Gute Nachricht für den Sideload: FoundationModels braucht **kein Entitlement**. Harte Grenze:
läuft nur auf Apple-Intelligence-fähigen Geräten (A17 Pro/M-Serie) mit aktiviertem Apple
Intelligence — jedes Feature braucht ein `SystemLanguageModel.default.availability`-Gate mit
ehrlichem Fallback (#06). On-device passt exakt zum Privacy-Versprechen (§1.2).

**Vertiefung (Auswahl):**
- Fundament zuerst: netzwerkfreies SwiftPM-Target `SoooDreamyAI` (Compile-Zeit-Airgap),
  Consent-Matrix pro Feature (Default: aus), On-Device-Badge, ephemere Sessions (#07)
- Briefanfang-Werkstatt: drei Anfänge im eigenen Ton, nie Autosend (#08, #06)
- „Sag es sanft": Versöhnungs-Umformulierer / Ich-Botschaften-Hilfe (#06, #08, #30)
- Tagesfrage-Nachklapp + Antwort-Impulse als Streak-Retter (#08, #06)
- Inline-Übersetzung für bilinguale Paare (Translation-Framework, on-device-Packs) (#10, #49)
- Voice-Transkripte via `SpeechAnalyzer` + durchsuchbarer Sprachnachrichten-Verlauf (#10, #08)
- Nachrücker: Monats-Essenz fürs Magazin (#06), „Quiz über uns"-Decks mit Server-Verteilung
  für Fairness (#06, #24), Genmoji-Anzeige im Chat (#10), Kitsch-Wächter vorm Versiegeln (#08),
  Geschenk-Radar strikt device-only (#06), PII-Redaktion vor Modell-Kontext (#07)

### Säule 3 — Mehrere Geräte gleichzeitig pro Partner

**Status quo (Recon):** Server kann ~80 %: Sessions sind **per Gerät** (`MAX_SESSIONS_PER_MEMBER
= 8`, Token-Digests, `lastUsedAt`, Revoke-API), WS-Fanout geht an **alle** Sockets beider Member,
Push-Registrierungen per Gerät, Presence = „irgendein Gerät online" ist korrekt. Lücken:
(a) Client hält genau **einen** Token pro Server-Profil, es fehlt der Geräte-Link-Flow im UI;
(b) drei Events (`touch`, `haptic`, `typing`) gehen nur an den Partner — das eigene Zweitgerät
verpasst sie; (c) `AppState` nimmt stellenweise an, jedes Event komme vom Partner (Self-Echo).
**Welle 1 (läuft):** Origin-Marker im Event-Stream + Geräte-Link-Codes serverseitig.

**Vertiefung (Auswahl):**
- Geräte-Manager in Settings: „Dieses Gerät"-Badge, Revoke mit Undo, Sicherheitsevent
  „Neues Gerät angemeldet" (#11, #13)
- QR-Geräte-Link vom bestehenden Gerät — Proximity-Beweis, nie der Paar-Code (#11, #13, #35)
- Self-Echo-Härtung + Read-State-/Badge-Sync über eigene Geräte (#11, #12)
- Fanout-Audit für `touch`/`haptic`/`typing` (Recon-Lücke, #14)
- `clientOpId`-Idempotenz für alle mutierenden POSTs (#15, #34)
- Entwurfs-Kontinuität: Brief auf dem iPhone anfangen, auf dem iPad zu Ende schreiben (#11, #14)
- Spiel-Eingabe-Lease + Zuschauer-Modus über eigene Geräte (#22, #11, #24)
- Nachrücker: Presence-Hysterese (#11), Push-Dedupe „das aktive Gerät klingelt" (#11),
  generalisierter Delta-Feed + `/api/bootstrap` (#34, #12), Panik-Aktion „alle anderen Geräte
  abmelden" (#13), Auto-Revoke inaktiver Sessions (#13), Multi-Device-Spoiler-Matrix (#24)

### Säule 4 — iPad-Version

**Status quo (Recon):** Komplett fehlend: `TARGETED_DEVICE_FAMILY: "1"` (auch Widgets),
portrait-only, **keine** Size-Class-Nutzung in irgendeiner View, `LayoutMetrics` liest
`UIScreen.main` mit Pro-Max-Baseline (Scale-Clamp ≤ 1.0 → iPad bekäme ein Telefon-Layout).
**Welle 1 (läuft):** Device Family „1,2" + adaptive Layout-Grundlagen.

**Vertiefung (Auswahl):**
- Chrome-Grundsatzentscheid: LiquidTabBar (compact) + Liquid-Rail (regular), `SizeTier`-Raster
  als Fundament; NavigationSplitView nur innerhalb der Tabs (#16, #18)
- Zwei-Spalten-Chat (Verlauf + Brief-Reader) und Dashboard als Regular-Width-Grid (#16)
- Canvas wird Pencil-Instrument: Druck/Neigung in der eigenen Stroke-Engine, Hover-Vorschau,
  Squeeze-Werkzeugwechsel (#16, #17)
- Pointer-Hover, Keyboard-Shortcuts (⌘1–5, Chat-Senden, Wordle voll tippbar), Drag & Drop (#17, #16)
- Multitasking-Härtung: kleinste Stage-Manager-Größe = iPhone-Layout, Socket-Politik pro
  ScenePhase, resize-feste Aurora (#18)
- Landscape-Spieltische (Battleship-Doppelbrett, Kniffel-Tisch) + Couch-Modus „ein iPad,
  zwei Spieler" (#20)
- XL-Widgets („Unser Monat"-Collage) + interaktive Tagesfrage im Widget, Reveal-sicher (#19, #09)
- Nachrücker: Galerie-Sidebar-Filter mit Pinch-Grid (#16), Popover-vs-Sheet-Matrix (#18),
  Szenen-Restauration pro Tab (#18), Turnier-Wandtafel (#20), Tisch-/Ambient-Modus (#14, #19 —
  Fernziel nach Welle 7)

### Säule 5 — HIG + Apple-Games-Doku

**Status quo (Recon + #46-Audit):** Solide Basis (flächendeckend `refreshable`,
`confirmationDialog` vor Destruktivem, saubere Badge-Disziplin), aber konkrete HIG-Abweichungen:
Custom-TabBar liefert System-Semantik nur teilweise, Tab-Badges in Pink statt System-Rot,
Purpose-Strings nur Englisch, Sprachwahl nur in-App statt per-App-Language, Custom-Suchfelder
statt `searchable`, Brief-Entwurf geht beim Wegwischen verloren, Kamera-Verweigerung endet
schwarz. Spiele: server-authoritativ mit Commit-Reveal und Season/Replay — **kein GameKit,
bewusst** (privates 2-Personen-Kontomodell; Game Center bleibt draußen, §5).

**Features (Auswahl):**
- HIG-Fix-Paket: deutsche Purpose-Strings, System-Badge-Rot, Kamera-Fallback-View,
  Entwurfs-Schutz beim Wisch (#46)
- Per-App-Sprache: In-App-Switch zusätzlich HIG-konform in die iOS-Settings spiegeln (#49, #46)
- `searchable` + Such-Konvention „unten, minimierbar" statt Eigenbau (#01, #46)
- Undo-Ethik in Spielen: 3-Sekunden-Misclick-Gnade (#24); Spiel-Unterbrechungs-Kontrakt (#47)
- AHAP-Haptik-Partituren pro Spiel + Sieg-Motive in Paar-Tonart, Sieg-Zeremonie-Stufen über
  DelightRules (#23, #47, #40, #39)
- Reducer-Fuzz-/Property-Tests als Fairness-Fundament (#22)
- Apple-Games-Haltung: GameController fürs iPad ist ein optionales Gimmick (#47);
  Game-Center-Mechaniken werden nicht verfolgt

---

## 3. Top-30 priorisiert

Priorisierung: Säulen-Nähe > Impact×Wow > geringer Aufwand. Die Reihenfolge entspricht grob der
Wellen-Zuordnung (§4). Dedupliziert über alle 50 Sammler; bereits existierende Features sind
nicht enthalten (siehe §5 letzter Punkt), echte Ausbauten sind als solche benannt.
Wow-Werte stammen vom Sammler, wo vorhanden (nur #50 vergab sie durchgängig), sonst aus der
Synthese. Sideload: OK = ohne Einschränkung; Fußnoten unter der Tabelle.

| # | Feature | Sammler | Aufwand | Impact | Wow | Sideload | Abhängigkeiten |
|---|---------|---------|---------|--------|-----|----------|----------------|
| 1 | Glas-Regionen-Konsolidierung: ein `GlassEffectContainer` pro Region, `glassEffectUnion` fürs Bottom-Chrome | #05, #04 | M | 5 | 3 | OK | keine — Fundament für 2, 7, 30 |
| 2 | Glas-Morphing-Trio: Canvas-FAB→Palette, Pulse-Fächer, Siegelbruch-Zoom (`glassEffectID`) | #01, #02, #03 | M | 5 | 5 | OK | 1; Reduce-Motion-Pfad (#03) |
| 3 | PrimaryButton → `.glassProminent` + CoupleTint-Kontrastvertrag (4.5:1-Gate) | #04, #01 | S | 4 | 3 | OK | Charter-Baseline-Update |
| 4 | Zentraler Reduce-Transparency-/Kontrast-Fallback in `GlassLevel` + AX-Screenshot-Gate | #03, #04 | S | 5 | 2 | OK | keine |
| 5 | Aurora-Drosselung unter Glas + Listen-Regel „Glas ist Chrome, Zellen matt" | #05 | S | 5 | 2 | OK | keine |
| 6 | System-Scroll-Edge-Effekte als Token + `backgroundExtensionEffect` für Foto-Heroes | #01, #02, #04 | S | 3 | 2 | OK | keine; zahlt auf iPad ein |
| 7 | Chat-Composer als `safeAreaBar` mit interaktivem Glas | #01, #02 | M | 5 | 4 | OK | 1 |
| 8 | Geräte-Manager in Settings: „Dieses Gerät", Revoke mit Undo, Sicherheitsevents (Ausbau der Session-Liste) | #11, #13 | M | 5 | 2 | OK | Welle 1 (Link-Codes) |
| 9 | QR-Geräte-Link vom bestehenden Gerät (Proximity-Beweis, nie der Paar-Code) | #11, #13, #35 | M | 5 | 3 | OK | 8 |
| 10 | Self-Echo-Härtung + Read-State-/Badge-Sync über eigene Geräte | #11, #12 | M | 5 | 2 | OK | Welle 1 (Origin-Marker) |
| 11 | Fanout-Audit: `touch`/`haptic`/`typing` auch an eigene Geräte | Recon, #14 | S | 4 | 2 | OK | 10 |
| 12 | `clientOpId`-Idempotenz für alle mutierenden POSTs (+ 409-Konfliktpfad) | #15, #34 | M | 5 | 1 | OK | API.md-Vertrag |
| 13 | AI-Fundament: netzwerkfreies `SoooDreamyAI`-Target, Availability-Gate, Consent-Matrix (Default: aus) | #07, #06 | M | 5 | 2 | OK¹ | keine |
| 14 | Briefanfang-Werkstatt: drei Anfänge im eigenen Ton, nie Autosend | #08, #06 | M | 5 | 4 | OK¹ | 13 |
| 15 | „Sag es sanft": Versöhnungs-Umformulierer + Ich-Botschaften-Hilfe (Ausbau von RepairConsideration) | #06, #08, #30 | M | 5 | 4 | OK¹ | 13 |
| 16 | Tagesfrage-Nachklapp + Antwort-Impulse (Streak-Retter) | #08, #06 | S | 4 | 3 | OK¹ | 13 |
| 17 | Zwei-Spalten-Layouts: Chat-Split (Verlauf + Brief-Reader), Dashboard-Grid in Regular Width | #16 | M | 5 | 3 | OK | Welle 1 |
| 18 | Canvas-Pencil-Ausbau: Druck/Neigung in der Stroke-Engine, Hover-Vorschau, Squeeze-Palette | #16, #17 | L | 5 | 5 | OK | Welle 1; 2 (Palette) |
| 19 | Pointer-Hover, Keyboard-Shortcuts (⌘1–5, Chat, Wordle), Drag & Drop | #17, #16 | M | 4 | 2 | OK | Welle 1 |
| 20 | Multitasking-Härtung: Stage-Manager-Minimalgröße, Socket-Politik pro ScenePhase, resize-feste Aurora | #18 | M | 4 | 1 | OK | Welle 1 |
| 21 | Entwurfs-Kontinuität: Briefe/Antworten nahtlos auf dem anderen Gerät weiterschreiben | #11, #14 | M | 4 | 4 | OK | 10, 12 |
| 22 | Landscape-Spieltische: Battleship-Doppelbrett, Kniffel-Tisch, Rotations-Übergänge ohne Zustandsverlust | #20 | L | 5 | 4 | OK | Welle 1, 17 |
| 23 | Couch-Modus: ein iPad, zwei Spieler (Pass-and-Play mit Sichtschutz-Übergabe) | #20 | L | 5 | 5 | OK | 22 |
| 24 | AHAP-Haptik-Partituren pro Spiel + Sieg-Motive in Paar-Tonart (Ausbau von HapticPatternKit/SoundEngine) | #23, #47, #40 | M | 4 | 4 | OK | DelightRules-Budget |
| 25 | Spiel-Eingabe-Lease + Zuschauer-Modus über eigene Geräte (iPad Brett, iPhone Controller) | #22, #11, #24 | M | 4 | 3 | OK | 10; Welle 1 |
| 26 | Widget-Ausbau: ehrliche Glas-Strategie, XL-Collage, interaktive Tagesfrage (Reveal-sicher) | #19, #09, #31 | M | 5 | 3 | OK² | Welle 1 (iPad-XL) |
| 27 | Inline-Übersetzung für bilinguale Paare (Translation-Framework, on-device-Packs) | #10, #49 | M | 5 | 3 | OK | 13 (Consent-Muster) |
| 28 | Voice-Transkripte (`SpeechAnalyzer`) + durchsuchbarer Sprachnachrichten-Verlauf | #10, #08 | L | 5 | 3 | OK¹ | 13 |
| 29 | Onboarding-Wegweiser „Ich habe noch keinen Server" + Mia-&-Ben-Demo-Modus | #38 | M | 5 | 3 | OK | keine |
| 30 | Kopplungs-Zeremonie: beidseitiges Glas-Morphing als Epic-Moment | #38, #02 | L | 5 | 5 | OK | 1, 2 |

¹ Kein Entitlement nötig, aber Apple-Intelligence-fähiges Gerät (A17 Pro/M-Serie) bzw.
iOS-26-Speech-APIs erforderlich — Availability-Gate mit ehrlichem Fallback ist Teil des Features.
² Widget-Extension fehlt in der Lite-Variante (Ein-App-ID-Sideload); Timeline ohne Push heißt
Snapshot-Ehrlichkeit statt Live-Anspruch (#31).

---

## 4. Wellenplan

### Welle 1 — läuft bereits (nicht neu planen)

- **(a) iPad-Fundament:** `TARGETED_DEVICE_FAMILY` „1,2" + adaptive Layout-Grundlagen
  (Size-Class-Einstieg, `LayoutMetrics`-Entkopplung von `UIScreen.main`).
- **(b) Server-Multi-Device:** Origin-Marker im Event-Stream (welche Session hat ausgelöst),
  Geräte-Link-Codes serverseitig.
- Bereiche: `ios/project.yml`, `UI/Theme.swift` (LayoutMetrics), `server/src/security.js`,
  `server/src/realtime.js`, `docs/API.md`.

### Welle 2 — Liquid-Glass-Vertiefung (Top-30: 1–7)

- **Ziel:** Die fertige Glas-Basis von „korrekt" auf „lebendig" heben: Regionen statt
  Einzel-Panes, Morphing als Signature-Moment, Systemeffekte statt Eigenbau.
- **Features:** Regionen-Konsolidierung + Aurora-Drossel [1, 5] · Morphing-Trio [2] ·
  `.glassProminent`-PrimaryButton + zentraler A11y-Fallback [3, 4] · Composer-`safeAreaBar` +
  Scroll-Edge/`backgroundExtensionEffect` [6, 7].
- **Bereiche:** ios (`UI/Glass.swift`, `UI/Theme.swift`, `LiquidTabBar`, `ChatView`,
  `CanvasView`, `DashboardView`), `tools/charter_baseline.json`, docs (DESIGN.md-Ergänzung
  Morph-Regeln).
- **Risiken:** Ratchets steigen bei Refactors (im selben Commit `--update` senken);
  Glas-auf-Glas-Verbot beim Container-Umbau; System-Morph-Timing vs. die 4 Motion-Kurven
  (Gebot 11 präzisieren); Performance auf Basisgeräten → Signposts messen (#05).

### Welle 3 — Multi-Device im Client (Top-30: 8–12)

- **Ziel:** Aus „der Server kann es" wird „das Paar merkt es": Geräte sichtbar und koppelbar,
  kein Doppel-Klingeln, keine Geister-Badges, keine verlorenen Events.
- **Features:** Geräte-Manager [8] · QR-Geräte-Link [9] · Self-Echo + Read-State +
  Fanout-Audit [10, 11] · `clientOpId`-Idempotenz [12].
- **Bereiche:** ios (`SettingsView`, `AppState`, `SharedKeychain`, `PairingView`),
  server (`security.js`, `realtime.js`, `router.js`), `docs/API.md`.
- **Risiken:** `AppState` (1 691 Zeilen) nimmt stellenweise „Event = Partner" an — breite
  Regressionsfläche; `router.js` ist Merge-Hotspot; Determinismus-Migration für rev-lose
  Bestandsdaten (#15); Sicherheits-Invarianten (nie Tokens im QR, nur Digests).

### Welle 4 — Apple-Intelligence-Fundament (Top-30: 13–16)

- **Ziel:** On-device-Intelligenz mit hartem Privacy-Rahmen: erst Architektur + Consent,
  dann die zwei wertvollsten Text-Features und ein Streak-Retter.
- **Features:** AI-Airgap-Target + Gate + Consent-Matrix [13] · Briefanfang-Werkstatt [14] ·
  „Sag es sanft" [15] · Tagesfrage-Nachklapp [16].
- **Bereiche:** ios (neues SwiftPM-Target `SoooDreamyAI`, `LetterComposeView`,
  Tagesfrage/`RevealCeremonyView`, `RepairConsiderationView`, `SettingsView`),
  docs (Privacy-Transparenz-Karte, Handbuch-Anker).
- **Risiken:** Geräte-Eligibility spaltet die Nutzerbasis (Gate + ehrliche Kommunikation
  Pflicht); deutscher Ton/Kitsch-Gefahr (Kitsch-Wächter #08, L10n-Gebot 9);
  Prompt-Injection über Partnertexte — Partnerinhalte als untrusted Input (#07);
  Produktregel „immer Entwurf, nie Autosend".

### Welle 5 — iPad-Vollausbau (Top-30: 17–21)

- **Ziel:** Aus dem Welle-1-Fundament eine echte iPad-App machen: Fläche nutzen, Pencil/
  Tastatur/Pointer erster Klasse, Zustand übersteht Multitasking und Gerätewechsel.
- **Features:** Zwei-Spalten-Layouts [17] · Canvas + Pencil [18] · Pointer/Keyboard/
  Drag & Drop [19] · Multitasking-Härtung + Entwurfs-Kontinuität [20, 21].
- **Bereiche:** ios (`LayoutMetrics`/SizeTier, `ChatView`, `DashboardView`, `CanvasView`,
  RootView-Overlays, `project.yml`-Orientierungen), CI (Screenshot-Matrix um iPad erweitern),
  docs/Handbuch.
- **Risiken:** `LayoutMetrics`-Umbau berührt fast jede View (inkrementell, Ratchets beachten);
  Portrait-Annahmen in Vollbild-Zeremonien; CI-Screenshot-Job wählt bisher nur iPhones;
  jede neue Surface muss in `PolishAudit` eingeschrieben werden.

### Welle 6 — Spiele & Game-Feel (Top-30: 22–25)

- **Ziel:** Die 21 Spiele fühlen sich auf dem iPad wie ein Spieleabend an — Tische statt
  hochkant gestreckter Telefon-Layouts, Feedback mit Substanz, faires Spielen über mehrere
  eigene Geräte.
- **Features:** Landscape-Spieltische [22] · Couch-Modus [23] · AHAP-Partituren +
  Sieg-Motive + Zeremonie-Stufen über DelightRules [24] · Eingabe-Lease + Zuschauer-Modus [25].
- **Bereiche:** ios (`Features/Games/*`, `GameEngine`, `GamesCoordinator`, `Haptics`,
  `SoundEngine`), server (`game-rules.js`: Lease-/Spectate-Policy, Spoiler-Matrix #24),
  `docs/API.md`.
- **Risiken:** 21 Spiele × Layout-Matrix — pro Spiel entscheiden, nicht pauschal;
  Commit-Reveal-Fairness darf durch Zweitgeräte nicht kippen (#24); Feier-Inflation
  vermeiden (DelightRules-Budget, #39); Reducer-Fuzz-Tests (#22) als Absicherung einplanen.

### Welle 7 — Rundung: Widgets, Sprache, Ankommen (Top-30: 26–30)

- **Ziel:** Die Vertiefungen dort sichtbar machen, wo täglich hingeschaut wird (Homescreen),
  Sprachgrenzen abbauen, und den ersten Kontakt zum Signature-Moment machen.
- **Features:** Widget-Ausbau [26] · Sprach-Paket: Übersetzung + Voice-Transkripte [27, 28] ·
  Onboarding-Wegweiser + Demo-Modus [29] · Kopplungs-Zeremonie [30].
- **Bereiche:** ios (`Widgets/*`, `ChatView`/`VoiceNotes`, `OnboardingFlowView`,
  `PairingView`), server (optionale Demo-Seeds), docs/Handbuch.
- **Risiken:** Widget-Reload-Budget (Timeline-Disziplin #31); `SpeechAnalyzer` ist iOS-26-API —
  Geräteabdeckung prüfen; Demo-Modus braucht klaren Ausstieg Richtung echtem Server;
  Zeremonie kombiniert Glas + Sound + Haptik → Ein-Kanal-Regel der Charta wahren.

---

## 5. Bewusst verworfen

- **Game Center / GameKit** (Achievements, Leaderboards, Matchmaking): braucht Apple-ID-Bindung
  und signierte Distribution — kollidiert mit dem privaten Selbsthost-Kontomodell.
- **CloudKit-Sync jeder Art:** Entitlement wird beim Sideload-Signieren gestrippt, und
  Apple-Cloud widerspricht dem Eigener-Server-Versprechen.
- **NFC-Kusspunkte (#50):** Core-NFC-Entitlement ist in der unsignierten IPA nicht verfügbar.
- **Journal-Anbindung / JournalingSuggestions (#43, #50):** Entitlement nur auf Antrag bei
  Apple — für Sideload nicht erreichbar.
- **Push-abhängige Feature-Kerne** (z. B. Live-Activity-Fernupdates): ohne bezahltes Profil +
  `.p8` bleibt `deliveryAvailable:false`; die lokale Benachrichtigungs-Brücke (#12) ist der
  ehrliche Ersatz, Push bleibt Bonus.
- **Watch-App (#33 komplett):** watchOS-Companion-Targets lassen sich beim unsignierten
  Sideload praktisch nicht installieren; die Ideen sind als Fernziel archiviert.
- **Share-Extension (#43):** Extensions sind beim Ein-App-ID-Resign fragil (genau dafür
  existiert SoooDreamyLite); der Extension-freie Zwischenablage-Wächter (#43) ist der
  Backlog-Ersatz.
- **Cloud-LLM-Fallback** (ChatGPT-Anbindung o. Ä.): verletzt das On-Device-Versprechen —
  FoundationModels-only ist gesetzt.
- **Unser-Lied-Radar via ShazamKit (#50):** Katalog-Matching sendet Audio-Signaturen an
  Apple-Server — Dritt-Cloud in intimen Momenten.
- **MusicKit-Integrationen:** brauchen Developer-Token eines bezahlten Kontos plus
  Apple-Music-Abo beider Partner.
- **Herzfrequenz-Gruß (#45) / Workout-Grüße (#33):** hängen an der verworfenen Watch;
  Partner-Gesundheitsdaten bleiben per Ethik-Grundsatz (#45) ohnehin tabu.
- **Zyklus-Rücksicht als Paar-Feature (#45):** Gesundheitsdaten des Partners sind eine rote
  Linie — bewusst nicht geplant.
- **Multi-Paar-Mandanten (#35):** als Feature verworfen (ein Server = ein Paar ist
  Produktidentität), als Betriebs-Doku („zwei Instanzen auf einem Host") sinnvoll.
- **SceneKit→RealityKit-Migration (#47):** kein Nutzergewinn, hohes Regressionsrisiko —
  dokumentiert nicht migrieren.
- **Multi-Window auf dem iPad (#16):** bewusst EIN Fenster — die App hat genau einen
  gemeinsamen Zustand, zwei Fenster erzeugen nur Konflikt-UX.
- **Fake-Cover/Tarn-Modus (#48):** eine Vertrauens-App verkleidet sich nicht; der
  Schulterblick-Schutz (#48, Backlog) adressiert die reale Sorge.
- **UWB-Schatzsuche (#50) / AR-Erinnerungs-Anker (#50):** Hardware-Nische (U1/Lidar) bzw.
  L-Aufwand für seltene Momente — Wow hoch, Alltagsnutzen zu schmal.
- **Bereits vorhanden** (von Sammlern ohne Code-Zugriff neu vorgeschlagen, per Grep bestätigt —
  kein Neubau, höchstens gezielter Ausbau): „An diesem Tag"-Karte (= `OnThisDayCard`),
  Widget-Galerie in-App (= `WidgetStudioView`), Verbindungs-Doktor/Diagnose (= `DiagnosticsView`),
  Recovery-Zeremonie (= `RecoveryViews` + Partner-Replace-Codes), Streak-Widget (= `StreakWidget`),
  Berührungs-Control (= `ControlWidgets`), Multi-Server-Profile (= `ServerListSheet`),
  Automations-Galerie (= `AutomationsGalleryView`), Haptik-Komponist (= `HapticStudioView`),
  Jahresrückblick (= `YearReviewView`), Zeitkapseln (= `CapsulesView`), Monats-Magazin
  (= `MagazineView`), Replay/Season (= `ReplayView`/`TournamentView`).

---

## Anhang: Sammler-Legende

| Nr. | Fokus | Nr. | Fokus |
|-----|-------|-----|-------|
| #01–05 | Liquid Glass: HIG-Purist, Motion, Accessibility, Dark-Kontrast, Performance | #26–30 | Beziehung: Therapeut, Fernbeziehung, Rituale, Archivar, Reparatur |
| #06–10 | Apple Intelligence: Produkt, Privacy, Texte, Intents, Media | #31–33 | WidgetKit, Live Activities, Watch |
| #11–15 | Multi-Device: Protokoll, Offline, Security, Presence, Konflikte | #34–37 | Server: API, Deploy, Migration, Observability |
| #16–20 | iPad: SplitView, Eingabe, Stage Manager, Widgets, Landscape-Games | #38–41 | Delight: First-Run, Habit, Sound, Personalisierung |
| #21–25 | Spiele: Designer, Architektur, Game-Feel, Fairness, Party | #42–45 | Plattform: Shortcuts, Share, Kalender, Health |
| | | #46–50 | HIG-Audit, Spiele-Tech, App-Sicherheit, Lokalisierung, Wildcard |

Nicht jede gute Idee hat es in die Top-30 geschafft — die „Nachrücker"-Listen in §2 sind die
kuratierte zweite Reihe und der natürliche Nachschub, wenn eine Welle Kapazität übrig hat.
