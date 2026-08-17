# UI-DESIGN-ACNH — Die verbindliche Designsprache (W21)

Runde W21 „ACNH-UI": komplettes UI-Neu-Design Richtung **Animal Crossing New
Horizons** — modern, warm, handgemacht, mit Mikroanimationen und Satisfaction,
nichts clippt, themen- und kontextabhängig. Dieses Dokument ist die
**verbindliche** Designsprache: Die 5 Area-Agents setzen ihre Flächen AUF
diesem Fundament um (Pakete in §8) — kein Screen erfindet eigene Maße, Zeiten
oder Farben.

Fundament im Code (W21, fertig):

| Baustein | Datei | Inhalt |
| --- | --- | --- |
| Skalen-Tokens | `GOOBY-GODOT/themes/tokens.gd` | `TYPO_SKALA`, `SPACE_*`, `RADIUS_SKALA`, `BTN_H_*`, `BAR_H`, `ICON_*`, `MOODS`, `px()`/`font_px()` |
| Theme-Rollen | `GOOBY-GODOT/themes/build_theme.gd` → `ac_theme.tres` | u. a. `StatKapselKopf/Mitte/Fuss`, `KontextDock` |
| Motion-Grammatik | `GOOBY-GODOT/scripts/ui/motion_kit.gd` (`MotionKit`) | §6 — Zeiten/Kurven als Statics, Reduced-Motion-gated |
| Kern-Bausteine | `GOOBY-GODOT/scripts/ui/components/acnh_kit.gd` (`AcnhKit`) | §5 — StatKapsel, IconButton, PapierKarte, BlattKopf, KontextDock |
| Referenz-Umsetzung | `GOOBY-GODOT/scripts/ui/hud/hud_stat_kapseln.gd` | §7 — linke HUD-Stats-Spalte als StatKapsel-Gruppe |
| Wächter | `tests/unit/test_w21_acnh_skalen.gd`, `test_w21_motion_kit.gd`, `test_w21_stat_kapsel_budget.gd` | §9 |

## 1. Befund-Lage (warum dieses Redesign)

Fünf Playtest-Agents haben den Ist-Zustand vermessen (`/tmp/gooby-ui-eval/
*_befunde.md`, W21-Runde). Die Top-Befunde, die diese Spec auflöst:

- **HUD-Flächenfraß:** Ruhe-HUD malt 16,5 % des Canvas zu (ACNH: 2–3 %); die
  linke Stats-Spalte allein 7,95 % bei 70,6 % Spaltenhöhe (6 Pillen à
  190×78,5 Canvas-px).
- **Baumodus zeigt nur 59 % Welt** (ACNH > 75 %): Lager-Karte permanent offen
  (22,7 % Fläche), Aktionsleiste verdeckt die Baufläche.
- **Font-Lotterie:** 2–3 Größen pro Screen für DIESELBE Theme-Rolle; sechs
  Knopf-Höhen (79–95 px), drei Balken-Standards (10 fix / 12 fix / 10×f).
- **Sheet-Sprachen-Spaltung:** zwei Kopfzeilen-Grammatiken, unterschiedliche
  Radien/Ränder je Screen.
- **Fehlende Mikroanimationen:** Werte springen, Listen erscheinen hart,
  keine Belohnungs-Momente (Stempel/Puff/Konfetti-Regeln fehlten).

## 2. Ästhetik — ACNH-Prinzipien, übersetzt auf GOOBY

1. **Cremefarbenes Papier mit dezenter Textur.** Grundton `BG_CREAM`,
   Flächen `PAPER`/`PAPER_SHADE`, Chips überm 3D-Raum `FROST`. Die Wand
   (`AcWallpaper`) driftet langsam mit ≤ 6 % effektivem Glyph-Kontrast —
   Textur ist Stimmung, nie Rauschen.
2. **Warme, dicke Soft-Outlines statt harter Kanten.** Outline = `OUTLINE_SOFT`
   (Ink 8 %); Knöpfe tragen eine „Boden-Lippe" (`AcTokens.lip_color`, Ink-Blend
   18 %) — das ist der handgemachte ACNH-Sticker-Look.
3. **Blatt- und Kapsel-Formen.** Interaktives ist rund: Pills (Sentinel
   `RADIUS_PILL`), Karten `RADIUS_CARD`/`RADIUS_CARD_LG`, Zeilen `RADIUS_ROW`.
   ES GIBT NUR DIESE EINE Radien-Skala (§3).
4. **Warme Mehrschicht-Schatten.** `SHADOW_*`-Tokens (Pop/Soft/Btn) sind
   braun getönt (Ink-Alpha), nie schwarz; Schatten fällt immer leicht nach
   unten (Papier liegt auf dem Tisch).
5. **Handgemachte Akzente, sparsam.** Stempel, Papier-Puff, Sparkle nur an
   ECHTEN Momenten (§6.3) — ACNH wirkt liebevoll, weil es NICHT dauernd
   feuert.
6. **Weniger, aber liebevoller.** Ruhe-Zustände sind minimal (§4) — die Welt
   und das Gooby sind die Bühne, UI ist Requisite.

### 2.1 Themen-Ebene: leise Farbstimmung pro Bereich

`AcTokens.MOODS` (deckungsgleich mit `AcWallpaper.CONTEXTS`, Wächter §9):

| Bereich | Mood-Key | Wash | Akzent | Stimmung |
| --- | --- | --- | --- | --- |
| Home | `home` | `#FFF6EC` | Leaf-Grün | warm-creme, Blätter |
| Ranch | `ranch` | `#F1F8E9` | Weide-Grün | grün, Koppel |
| Stadt | `stadt` | `#EFF4FB` | Himmelblau | luftig, Reise |
| Arcade | `arcade` | `#F3EFFA` | Dämmer-Violett | Abend, Neon-leise |
| DLC Goo&Bye | `dlc_gooundbye` | `#EFF9F3` | Markt-Mint | Kasse/Markt |
| DLC McGooby | `dlc_mcgooby` | `#FDF2E7` | Ketchup-Orange | Imbiss |

Regeln: Der Wash bleibt LEISE (UI-Flächen bleiben `PAPER`/`FROST`); das
Akzent-Trio (`accent`/`accent_dark`/`soft`) färbt NUR Tabs, Ribbons und den
einen Bereichs-CTA. Screens holen es über `AcWallpaper.context_accent(ctx)`.
Die DLC-Moods bekommen ihre Wallpaper-Kontexte im jeweiligen DLC-Paket.

## 3. Skalen (VERBINDLICH — Wächter: `test_w21_acnh_skalen`)

Alle Maße sind **Design-px** und werden mit dem UiScale-Faktor `f`
skaliert. Rundungs-Konvention: IMMER `AcTokens.px(design, f)` (= `round()`,
nie `int()`-Trunkierung) bzw. `AcTokens.font_px()` (zusätzlich Boden 10 px).

### 3.1 EINE Typo-Skala (5 Stufen × f)

| Stufe | Token | Design-px | Gewicht | Einsatz |
| --- | --- | --- | --- | --- |
| Caption | `SIZE_CAPTION` | 15 | 700 | Meta, Chips, Hinweise (Ink-Faint) |
| Body | `SIZE_BODY` | 20 | 600 | Fließtext, Listen |
| Button | `SIZE_BUTTON` | 22 | 700 | Knopf-Text |
| Title | `SIZE_TITLE` | 28 | 800 | Blatt-/Screen-Titel |
| Headline | `SIZE_HEADLINE` | 34 | 800 | EINE Hero-Zahl/-Zeile pro Ansicht |

Einzige Ausnahme UNTER der Skala: HUD-Mikro-Labels unter Icons (9/12,
autoshrink) — nie für Fließtext. `FONT_SIZE_*` sind reine Aliasse.

### 3.2 EIN Spacing-Grid (4/8er)

`SPACE_GRID = 4`; Stufen `SPACE_XS/S/M/L/XL = 4/8/16/24/32`. Jeder Abstand
und Innenrand ist ein Grid-Vielfaches (`separation`, `content_margin`).

### 3.3 EINE Radien-Skala (3 Stufen + Pill)

`RADIUS_ROW = 14` (Zeilen, Wells, Popups) · `RADIUS_CARD = 28` (Karten,
Dialoge, Sheets) · `RADIUS_CARD_LG = 36` (Hero-Karten) · `RADIUS_PILL = 999`
(Sentinel, clampt auf Halbhöhe). Bestands-Ausnahme: `ToastBubble` 22
(Web-Paritäts-Pin) — Migration gehört Paket 1.

### 3.4 EIN Knopf-System (2 Höhen × f)

`BTN_H_PRIMAER = 56` (Hero-CTA, max. 1 pro Ansicht) · `BTN_H_KOMPAKT = 48`
(= `TOUCH_FLOOR`, alles andere). Löst die sechs gemessenen Höhen ab. Echte
Knöpfe sind `SquishButton` (Druck-Antwort gratis); runde Icon-Knöpfe über
`AcnhKit.icon_button`.

### 3.5 EIN Balken-Standard

`BAR_H = 10` (× f), Pill-Radius, Spur `TRACK_SOFT`, Füllung Stat-/Akzentfarbe.
Mini-Balken in Kapseln: Breite `AcnhKit.BAR_W_MINI = 44` (× f).

### 3.6 Icon-Größen-Set

`ICON_S = 16` (Inline-Glyphen) · `ICON_M = 20` (Stat-/Listen-Icons, Münze) ·
`ICON_L = 24` (Kachel-/Dock-Icons) · `ICON_XL = 44` (Hero, z. B. Auge).

## 4. Kontext-Choreographie — was ist wann sichtbar

Baut auf dem W20-Verdeckungs-Vertrag (`hud_sichtbarkeit.gd`: Kanäle
BuildMode/PanelSheet/PanelStack/`hud_verdecker`-Gruppe) auf — NEUE Overlays
melden sich dort an, statt das HUD zu überdecken.

| Kontext | Sichtbar | Weicht | Mechanik |
| --- | --- | --- | --- |
| Ruhe (Welt) | StatKapsel-Gruppe (links, EIN Element), Kachel-Cockpit/Dock, Auge, Zahnrad, Gooby-Chip | — | Grundzustand; Stats-Detail erst im Status-Sheet (Tap auf Gruppe) |
| Baumodus | Welt zuerst; KontextDock (einklappbar) + Verlassen-Knopf | HUD komplett (Stil RUTSCH) | `BuildMode.opened` → Verdeckungs-Vertrag |
| Blatt/Sheet offen | das Blatt | HUD (Stil BLENDE) | `PanelSheet.opened` → Zähler (verschachtelt robust) |
| Modal/Popup (Tagesbonus, Telefon …) | das Modal | HUD | PanelStack-Watcher bzw. Gruppe `hud_verdecker` |
| Minispiel | NUR Spiel-Chrome (Host: Timer/Score/Pause — §8 P4) | HUD (Szenenwechsel) | MinigameHost |
| Toast | eine Sprechblase oben, nie gestapelt | — | `ToastQueue` (Cap + Dedupe) |

Regeln: (1) Ruhe-HUD minimal — Stats sind EINE kompakte Kapsel-Gruppe,
Aktionen schwebende Icon-Buttons. (2) Es gibt keinen Zustand, in dem zwei
„Bühnen" konkurrieren: Sheet offen ⇒ HUD weg. (3) Coachmarks/Guide-Karten
verdecken bewusst NICHT (sie brauchen die HUD-Knöpfe).

## 5. Kern-Bausteine (`AcnhKit`, alle statisch)

```gdscript
AcnhKit.stat_kapsel(icon, farbe, bar_variation, f) -> PanelContainer
AcnhKit.stat_kapsel_gruppe(zeilen) -> VBoxContainer   # Separation 0 + Rollen
AcnhKit.segment_rollen(zeilen)                        # Kopf/Mitte/Fuss je Position
AcnhKit.gruppen_breite_angleichen(zeilen)             # EINE Gruppenbreite
AcnhKit.icon_button(icon, f, kompakt := false) -> Button   # rund, Soft-Outline
AcnhKit.papier_karte(gross := false) -> PanelContainer     # AcCard/AcCardLg
AcnhKit.blatt_kopf(titel, on_back) -> AcScreenHeader       # W20-Kopf-Grammatik
AcnhKit.kontext_dock(inhalt, griff_text, f) -> AcnhKit.KontextDock
```

- **StatKapsel-Gruppe:** Segmente teilen sich EINE Frost-Fläche — Kopf oben
  gerundet (`StatKapselKopf`), Mitten eckig mit 1-px-Hairline oben
  (`StatKapselMitte`), Fuss unten gerundet (`StatKapselFuss`); eine einzelne
  Zeile bleibt ganze Pill (`StatusCapsule`).
- **IconButton:** `SquishButton` + `HudIconButton`-Rolle, GENAU zwei Größen
  (`BTN_H_PRIMAER`/`BTN_H_KOMPAKT`), Icon `ICON_XL`/`ICON_L`.
- **KontextDock:** Griff-Zeile bleibt, Inhalt klappt (MotionKit-Blatt-Slide,
  Signal `zustand_geaendert`) — für Baumodus-Lager und Werkzeug-Leisten.
- **BlattKopf:** Wrapper um `AcScreenHeader` (W20) — Zurück-Pill links, Titel
  mittig, Chips rechts; `apply_metrics(m)` beim Metrics-Pass rufen.

## 6. Motion-Grammatik (`MotionKit` — Zeiten/Kurven VERBINDLICH)

Alle Helfer sind Reduced-Motion-gated: bei `UiTheme.reduced_motion` springen
sie sofort in den Endzustand und geben `null` zurück (Wächter §9).

### 6.1 Grammatik

| Bewegung | Aufruf | Zeit/Kurve | Einsatz |
| --- | --- | --- | --- |
| Pop-In | `MotionKit.pop_in(ctl)` | 240 ms, Back-Out-Feder, 1.04-Overshoot | Auftritt einzelner Elemente |
| Squish | `MotionKit.squish(ctl)` | 0.94-Druck, 120 ms + Feder | Druck-Antwort für Nicht-Buttons (Karten, Kapseln) |
| Blatt-Slide | `MotionKit.blatt_slide_in/out(ctl)` | 280 ms Quint-Out, 24 px Offset (× f) | Sheets/Karten rein/raus |
| Stagger | `MotionKit.stagger_ein(ctls)` | 40 ms Versatz, je Kind Pop-In | Listen/Gruppen |
| Count-Up | `MotionKit.count_up(label, von, bis)` | 600 ms Quad-Out, endet EXAKT | Münzen, Ergebnis-Zeilen |
| Stempel | `MotionKit.stempel(ctl)` | 320 ms, 1.6→1.0 + −8°→0° | „gefunden!"/„eingelöst" |
| Papier-Puff | `MotionKit.papier_puff(host)` | 450 ms, 6 Flöckchen (RNG injizierbar) | Platzieren, leise Belohnung |
| Wert-Puls | `MotionKit.puls(ctl)` | 1.03, 180 ms Sine | Stat/Chip ändert sich spürbar |

Echte Buttons behalten `SquishButton` (identische 0.94/1.04-Werte über
`AcTokens.PRESS_SCALE`/`SQUISH_OVERSHOOT`). `UiMotion` bleibt für
Bestands-Call-Sites — neue/umgebaute Flächen nutzen NUR `MotionKit`.

### 6.2 Reduced-Motion-Pfade

Endzustand sofort, keine Teilchen, kein Tween — jede neue Animation MUSS
durch `MotionKit` (oder explizit `ThemeService.is_reduced_motion`) gehen.

### 6.3 Effekt-Vokabular + Konfetti-Sparsamkeitsregel

- **Papier-Puff** = leises „ist passiert" (Platzieren, Abschluss einer Zeile).
- **Stempel** = persönlicher Fund/Abschluss (Album, Code, Quest-Häkchen).
- **Sparkle** (`UiMotion.sparkle`) = kleiner Glanz auf NEU-Badges.
- **Konfetti** NUR bei: Level-Up, Minispiel-Rekord, Quest-Serie komplett,
  DLC-/Feature-Freischaltung. NIE für Routine (Füttern, Kauf, Toast). Pro
  Bildschirm-Moment maximal EIN Effekt — der wichtigste.

## 7. Referenz-Umsetzung: linke HUD-Stats-Spalte (BEWEIS)

Quer-HUD: sechs fette Einzel-Pillen → EINE StatKapsel-Gruppe (Level-Ring als
Kopf, vier Stat-Zeilen mit Icon + Mini-Balken, Münzen als Fuss). Hochkant
bleibt die Web-Paritäts-Statuszeile. Umsetzung: `hud_stat_kapseln.gd`
(Rollen/Maße), Stagger-Pop-In beim Layout-Wechsel, sanfter `puls` bei
spürbarer Wert-Änderung (≥ 2 Punkte, nie während Alarm-Puls).

Messung Leitformat 2868×1320 @3× (Canvas 1564×720, `w21_stats_mess.gd`):

| | vorher | nachher | Gewinn |
| --- | --- | --- | --- |
| gemalte Fläche | 89 542 px² = **7,95 %** | 39 690 px² = **3,52 %** | **−56 %** |
| Bounding-Box | 8,58 % | 3,52 % | −59 % |
| Spaltenhöhe | 70,6 % | 40,8 % | −42 % |
| Chip-Maß | 6× 190×78,5 | Gruppe 135 breit, 294 hoch | — |

Budget eingefroren in `test_w21_stat_kapsel_budget.gd` (≤ 4,5 % Fläche,
≤ 45 % Höhe, Segment-Rollen, EINE Breite, Separation 0).

## 8. Umsetzungs-Pakete (Migrations-Plan für die Area-Agents)

Datei-Grenzen sind konfliktfrei geschnitten; Fundament-Dateien (`tokens.gd`,
`build_theme.gd`, `motion_kit.gd`, `acnh_kit.gd`) werden von Area-Agents NUR
konsumiert — Erweiterungen laufen über den Design-Lead. Für JEDES Paket gilt:
bestehende Wachen grün (`fb3_uiscale_conformance`, `fb3_ui_audit` 0 Befunde,
`w20_overlay_choreo`, W21-Wächter), gdformat/gdlint sauber, Godot unter
flock, `--import` nach neuen `class_name`.

### P1 — HUD rechts + Toasts

- **Dateien:** `scripts/ui/hud.gd` (rechte Spalte/Dock/TopBar-Anteile),
  `scripts/ui/hud/hud_button_order.gd`, `hud_mehr_cluster.gd`,
  `scripts/ui/toast.gd`, `toast_queue.gd`.
- **Schritte:** Kacheln → `AcnhKit.icon_button`-Sprache (Frost, Soft-Outline,
  `ICON_L`, Label `SIZE_CAPTION`); „Mehr"-Aufklapp mit `stagger_ein`; Toast
  → `RADIUS_CARD` + `blatt_slide_in/out` + `ICON_S`-Glyphe; Zahnrad/Auge auf
  `BTN_H_*`-Höhen.
- **Abnahme (messbar):** Ruhe-HUD gesamt ≤ 8 % gemalte Canvas-Fläche im
  Leitformat; Radius-Ausnahme `ToastBubble` aus `test_w21_acnh_skalen`
  STREICHEN (der Pin in `test_uicozy_theme` wandert mit); Toast nie > 1
  sichtbar (Bestands-Wache).

### P2 — Baumodus

- **Dateien:** `scripts/home/build_mode/**` (+ eigene Wachen/Flows).
- **Schritte:** Lager-Karte → `AcnhKit.kontext_dock` (startet EINGEKLAPPT,
  Griff mit Stück-Zahl); Aktionsleiste → kompakte Icon-Buttons am Rand;
  Item-Thumbnails in den Dock-Zeilen (`ICON_L`); `papier_puff` beim
  Platzieren, `squish` beim Aufnehmen; Grid-/Geister-Vorschau bleibt.
- **Abnahme (messbar):** sichtbare Welt im Baumodus ≥ 75 % (Mess-Sonde wie
  `w21_stats_mess.gd`); Dock eingeklappt ≤ 8 % Fläche; Platzieren feuert
  GENAU einen Puff (RNG injiziert im Test).

### P3 — Sheets / Menüs (Profil, Album, Settings, Quests …)

- **Dateien:** `scripts/ui/panel_sheet.gd`, `screen_shell.gd`, die
  Screen-Dateien unter `scripts/ui/**` (Album/Profil/Settings/…).
- **Schritte:** JEDER Screen-Kopf → `AcnhKit.blatt_kopf` (EINE Grammatik);
  Blatt-Auf/Zu → `blatt_slide_in/out`; Karten → `papier_karte`; Listen →
  `stagger_ein`; Typo NUR über Theme-Rollen (Font-Overrides raus, außer
  HUD-Mikro-Ausnahme); Balken → `BAR_H`-Standard; Knöpfe → 2-Höhen-System.
- **Abnahme (messbar):** 0 `add_theme_font_size_override`-Call-Sites mit
  Werten außerhalb der Typo-Skala (rg-Wache); pro Screen genau 1 Titel
  (`SIZE_TITLE`) und ≤ 1 Headline; `fb3_ui_audit` 0 Befunde über alle
  Formate.

### P4 — Minispiel-Rahmen (Host, Arcade, Pregame, Ergebnis)

- **Dateien:** `scripts/minigames/minigame_host.gd`, `arcade_screen.gd`,
  `arcade_spotlight.gd`, Pregame-/Ergebnis-UI des Hosts.
- **Schritte:** Timer/Score/Pause als EIN Host-Chrome (Frost-Kapseln oben,
  `ICON_M` + `SIZE_CAPTION`); Orientierungs-Mismatch: Pregame-Karte trägt
  die Dreh-Aufforderung (Blatt-Grammatik statt 80 % Leere); Ergebnis-Blatt:
  `count_up` für Punkte/Münzen, `stempel` für Rekord, Konfetti NUR bei
  Rekord (§6.3); Cover-Bild bleibt im Pregame sichtbar.
- **Abnahme (messbar):** Ergebnis-Screen clippt in KEINEM Leitformat
  (fb3_ui_audit); Timer lebt im Host statt im Spiel (Node-Pfad-Wache);
  Count-Up endet exakt (Bestands-/W21-Wache).

### P5 — Minispiele (In-Game-UI der ~20 Spiele)

- **Dateien:** `scripts/minigames/games/**` (pro Spiel eigene Dateien —
  parallelisierbar, KEINE Host-Dateien anfassen).
- **Schritte:** In-Game-HUD-Chips → `stat_kapsel`-/Chip-Sprache (Frost,
  `SIZE_CAPTION`, `BAR_H`); Banner („Los!", „Vorbei!") → EIN Standard
  (`papier_karte` + `pop_in`/`blatt_slide`); Celebration-Momente nach §6.3;
  alle Größen über `AcTokens.px` × f (keine Fix-px).
- **Abnahme (messbar):** `fb3_uiscale_conformance` deckt die Spiel-Dateien
  (keine nackten Pixel-Literale); Banner-Rolle identisch über alle Spiele
  (rg-Wache auf die Standard-Builder); Spiel-HUD ≤ 6 % Fläche im
  Spiel-Leitformat.

## 9. Wächter (W21, laufen in der Unit-Suite)

- `test_w21_acnh_skalen.gd` — Skalen-Konsistenz: Typo-Skala (5 Stufen,
  Aliasse), Spacing-Grid-Vielfache, Radien-Skala (3 + Pill), 2-Höhen-System
  (Kompakt = Touch-Floor), Icon-Set monoton; JEDE Font-Größe und JEDER Radius
  des GEBAUTEN Themes liegt auf der Skala (Ausnahme dokumentiert:
  `ToastBubble` 22 → P1); W21-Rollen präsent + korrekt gerundet; `MOODS` ≡
  `AcWallpaper.CONTEXTS`; `px()`-Rundungs-Konvention.
- `test_w21_motion_kit.gd` — Motion-Verträge: Grammatik-Konstanten verbindlich;
  ALLE Helfer Reduced-Motion-gated (Endzustand sofort, `null`, keine
  Flöckchen); Pop-In endet in Ruhelage; Count-Up endet EXAKT (auch mit
  Formatter); Papier-Puff deterministisch über injizierten RNG + räumt auf;
  Stagger blendet alle ein.
- `test_w21_stat_kapsel_budget.gd` — Referenz-Budget: ≤ 4,5 % Fläche, ≤ 45 %
  Höhe, Segment-Rollen in Reihenfolge, EINE Gruppenbreite, Separation 0.
- Bestands-Wachen bleiben Pflicht: `test_fb3_uiscale_conformance`,
  `fb3_ui_audit` (0 Befunde), `test_w20_overlay_choreo`, HUD-Label-Wachen,
  `test_ui_layout`, `test_uicozy_theme`.
