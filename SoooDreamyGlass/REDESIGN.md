# REDESIGN.md — SoooDreamyGlass: Audit & Redesign-Plan

Auftrag: „Die App massiv verbessern — das UI wirkt leer und seelenlos. Cleaner,
verspielter, belebter: Designsystem, Micro-Animationen, Empty-States mit Charme,
Onboarding, konsistente Navigation, dunkler+heller Modus."

Dieses Dokument ist (1) das Audit des Ist-Zustands, (2) der Screen-für-Screen-Plan
(vorher → nachher) und (3) das Protokoll der Design-Entscheidungen — inklusive der
Stellen, an denen der Auftrag mit der verbindlichen Qualitätscharta
(`SoooDreamy/DESIGN.md`) kollidiert und wie der Konflikt aufgelöst wurde.

---

## 1. Audit

### 1.1 Was hier liegt

`SoooDreamyGlass/` ist ein vollständiger Squash-Import des SoooDreamy-Stands
v16.0.0 (Build 54): iOS-26-App (SwiftUI, XcodeGen) + Node-Server + Remotion-Kino.
Die App ist **kein leeres Gerüst** — 425 Swift-Dateien, ~130 000 Zeilen, fünf
„Stationen" (Tabs), Delight-Engine, Zeremonien-Schicht und ein gereiftes
Designsystem („Papier & Licht") mit eigenem Anti-Slop-Linter
(`SoooDreamy/tools/charter_lint.sh`, Ratchet: Slop-Zähler dürfen nur sinken).

### 1.2 Struktur & Datenfluss

```
SoooDreamy/ios/SoooDreamy/
├── App/          SoooDreamyApp → RootView (Phasen welcome/pairing/main,
│                 Overlay-/Zeremonien-Host, Delight-Host, Toast, AppLock)
├── UI/           Designsystem-Schicht (EINZIGER Ort für Roh-Designwerte):
│                 Theme (Tokens Papier/Tinte/Licht/Wachs/Nacht, Space, Radius,
│                 Typo, Theme.Motion), Glass (GlassLevel/PaperLevel/Elevation),
│                 Components (EmptyStateView, Skeletons, Siegel, Toast …)
│                 └── DesignSystem/   ← NEU (Welle 1, siehe §3)
├── Stationen/    die fünf Tabs: Postfach (Dashboard) · Schreibstube (Chat) ·
│                 Spieltisch (Spiele-Hub) · Archiv (Erinnerungen) · Amt (Settings)
├── Content/      Foundation-only Logik + Datenpakete (LogicTests auf Linux)
├── Zeremonien/   Reveal-, Pairing-, Touch-Overlays
├── Kino/         Erststart-Kino + statischer Guide (Onboarding)
└── Zustelldienst/ Rituale (Check-in, Kapseln, Ziele …)
```

Datenfluss: `AppState` (@Observable) + REST/WebSocket-Client → Stationen lesen
`@Environment(AppState.self)`; Feiern laufen zentral über `Delight`/`DelightArbiter`,
Farben über `CoupleTint` (aus den Paar-Farben abgeleitet, kontrastgesichert).

### 1.3 Befund zum „leer und seelenlos"

Der Eindruck entsteht nicht durch fehlende Features, sondern durch die bewusst
stille „Nacht-first"-Richtung der letzten Wellen:

1. **Der Raum ist statisch.** `DreamyBackground` = fixer Raumverlauf + statischer
   Lampenkegel + 18 winzige Staub-Motes (≤ 12 Hz). Auf großen Screens liest sich
   das als tote Fläche — nichts atmet.
2. **Kopfzeilen sind Verwaltung.** Das Postfach begrüßt mit „137 Tage zusammen"
   + Statuspille; es gibt keinen warmen Moment des Ankommens (keine Begrüßung,
   keine Tageszeit-Persönlichkeit).
3. **Leere Zonen verschwinden wortlos.** Der Spieltisch blendet die Zone
   „aufliegende Blätter" bei 0 offenen Partien einfach aus — der Screen erklärt
   den Zustand nicht und lädt nicht ein (Verstoß gegen den Geist von Gebot 8,
   auch wenn formal keine „leere Liste" gerendert wird).
4. **Micro-Feedback ist ungleich verteilt.** Manche Buttons (Siegellack, Glas)
   federn; viele `.plain`-Buttons (Avatare, Registerköpfe) antworten dem Finger
   nur per Haptik, nicht sichtbar.
5. **Komponenten-Vokabular fehlt für „verspielt".** Es gibt Karten/Buttons, aber
   keine benannten Chips, kein wiederverwendbares belebtes Empty-State, kein
   Panel-Baustein für schwebendes Chrome.

### 1.4 Konflikte Auftrag ↔ Charta (und Entscheidung)

| Auftrag | Charta | Entscheidung Welle 1 |
|---|---|---|
| Heller + dunkler Modus | „Lampenlicht-first: Dark Mode only" ist Markenentscheidung; beide Kontrast-Anker (`#201613`/`#F7F1E4`) sind in LogicTests gepinnt | Tokens im neuen `DesignSystem/` sind **semantisch** benannt (kein View-Code kennt Hexwerte). Ein Light-Theme ist damit eine reine UI-Schicht-Welle (Welle 3, §4): neue Anker in `PaperRules`/`CouplePaletteRules` + gepinnte Kontrastmatrix. In Welle 1 wird KEIN halber Light Mode ausgeliefert — 400+ Views gegen einen ungepinnten hellen Grund wären genau der Bruch, den die Charta verhindert. |
| Konfetti-/Partikel-Momente | Eine Feier pro Screen-Session, `epic` ist verdient (Gebot 4); Levels 1–2 feiern mit Licht | Partikel bleiben hinter `Delight`/`DelightArbiter`. Neu ist die **ambiente** Lebendigkeit (AnimatedBackground), nicht mehr Konfetti-Stellen. |
| „Alles komplett neu" | Ratchet: Zähler dürfen nie steigen | Neubau **additiv in `UI/DesignSystem/`** + gezielte Screen-Umbauten. Kein Zähler steigt; die Screens behalten Funktionalität, A11y-Pfade und Test-Hooks. |

---

## 2. Screen-für-Screen-Plan (vorher → nachher)

### 2.1 Postfach / Dashboard — Welle 1 ✅

| | Vorher | Nachher |
|---|---|---|
| Hintergrund | statischer Raum + 18 Staubpunkte | `AnimatedBackground`: Raum + Lampe + Staub + **Atemglühen** — zwei sehr langsam atmende Glühfelder in den Paar-Farben unter dem Lampenkegel (≤ 8 Hz, Reduce Motion/Low Power/Hintergrund: stilles Gemälde) |
| Kopf | „137 Tage zusammen" + Status | **Begrüßungszeile** darüber: „Guten Morgen · Schönen Tag euch · Guten Abend" aus der Zustellrunde (`Zustellrunde.greetingKey`, Foundation-getestet) — der Screen sagt zuerst Hallo, dann Zahlen |
| Avatare | `.plain`-Buttons, Antwort nur haptisch | federnde Druck-Antwort (`DSPressable`) — jede Berührung antwortet im Frame sichtbar (Gebot 14) |
| Mood-Ack-Chip | handgebaute Kapsel | `DSChip` (ein Chip-Vokabular für die ganze App) |

### 2.2 Spieltisch / PlayHub — Welle 1 ✅

| | Vorher | Nachher |
|---|---|---|
| Hintergrund | statisch | `AnimatedBackground` |
| 0 offene Partien | Zone „aufliegende Blätter" verschwindet wortlos | **„Der Tisch ist frei"** — belebtes `DSEmptyState` (Symbol-Choreografie + Lichtschein) mit Handlung: ein Tap öffnet das „Am Tisch"-Fach des Kartenschranks |
| Umschlag-Karten | Legen-Stagger vorhanden | bleibt — der Neubau ergänzt, er ersetzt keine funktionierende Choreografie |

### 2.3 Weitere Screens (Welle 2 — geplant, nicht Teil dieses Stands)

- **Schreibstube/Chat:** Erste-Nachricht-Empty-State auf `DSEmptyState` heben;
  Composer-Chrome auf `GlassPanel` v2 vereinheitlichen.
- **Archiv:** Alben-/Tresor-Leerzustände auf `DSEmptyState`; Schrankfront-Fächer
  mit `DSPressable`-Feder.
- **Amt/Settings:** Sektionseinstiege mit `DSChip`-Filterleiste (Suche nach
  Einstellungen), `GlassPanel` für den Verbindungs-Doktor.
- **Onboarding:** existiert als Erststart-Kino + statischer Guide (`Kino/`) und
  bleibt; Welle 2 hebt die Guide-Seiten auf `AnimatedBackground` + `DSEmptyState`-
  Anatomie (Einladung statt Erklärtext).

### 2.4 Welle 3 — Light Mode (geplant)

1. Zweiten Anker-Satz in `PaperRules` benennen (`tagOben/tagUnten`, Tinten-Matrix
   gegen hellen Grund), LogicTests erweitern (Kontrastmatrix beidseitig ≥ 4,5:1).
2. `DS.Surface`-Rollen (bereits semantisch) auf `Color(light:dark:)`-Dynamik heben.
3. Screens wellenweise freischalten; bis dahin bleibt `preferredColorScheme(.dark)`.

---

## 3. Das neue `DesignSystem/`-Modul (`ios/SoooDreamy/UI/DesignSystem/`)

Liegt bewusst IN der UI-Schicht: die Charta erlaubt Roh-Designwerte nur dort.
Alles baut auf den bestehenden Token-Familien auf (Space/Radius/Typo/Theme.Motion)
— das Modul erweitert das Vokabular, es konkurriert nicht damit.

| Datei | Inhalt |
|---|---|
| `DSTokens.swift` | `DS`-Namespace: Press-Feder-Parameter, Glüh-/Ambient-Tokens (Atem-Periode, Deckel-Opazitäten), Chip-Metriken — benannte Werte statt Freihand |
| `DSComponents.swift` | `DSChip` (federnde Kapsel-Chips mit Auswahl-Zustand), `DSPressable`/`DSPressableStyle` (sichtbare Druck-Antwort für bisher stumme `.plain`-Buttons) |
| `AnimatedBackground.swift` | Hintergrund v2: Raum + Lampe + Tintenstaub + Atemglühen in Paar-Farben; zentral gedrosselt (Reduce Motion, Low Power, Scene-Phase) |
| `GlassPanelV2.swift` | `GlassPanel` v2: ein benannter Baustein für schwebendes Chrome (echtes `glassEffect`, Elevation, optional interaktiv) — Adopter in Welle 2 (Chat-Composer, Verbindungs-Doktor) |
| `DSEmptyState.swift` | Empty-State mit Charme: Nachtkarte + Symbol-Bounce + Lichtschein + Einladungssatz + CTA; Reduce-Motion-Pfad = stiller End-Glow |

Ratchet-Versprechen: kein Zähler in `tools/charter_baseline.json` steigt durch
das Modul (verifiziert via `bash SoooDreamy/tools/charter_lint.sh`).

---

## 4. Nicht verhandelt / bewusst gestrichen

- **Kein zweiter Konfetti-Kanal** neben der Delight-Engine (Gebot 4).
- **Kein Emoji-Chrome, keine Gradient-Titel, keine Freihand-Federn** — die neuen
  Komponenten referenzieren ausschließlich benannte Tokens.
- **Kein halber Light Mode** in Welle 1 (siehe §1.4) — stattdessen der saubere
  Migrationspfad in §2.4.
