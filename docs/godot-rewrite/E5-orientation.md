# E5 — Orientierung / Resize-Matrix (GOOBY-Godot-Mega-Eval)

Branch `cursor/gooby-godot-rewrite-d1d8`, Godot 4 headless (xvfb, opengl3).
Shots: `/tmp/gooby-godot/eval/E5-shots/` — Treiber: `e5_driver.gd` (Einzelflächen, Theme auf Root),
`e5_real.gd` (ECHTE `home_entry`-Komposition inkl. `UiLayer`-CanvasLayer + Router),
`e5_theme_probe.gd` (Theme-Propagations-Beweis).

Projekt-Stretch: Basis 1280×720, `canvas_items` + `expand` → in Hochkant ist der Canvas
immer ≥1280 breit, d. h. die gesamte UI wird physisch auf ~56 % (720er-Phone) bzw. ~84 %
(1080er-Phone) verkleinert. Das prägt fast alle Portrait-Findings.

## Matrix (Fläche × Auflösung)

| Fläche | 1280×720 | 720×1280 | 2340×1080 | 1080×2340 | 1024×768 | 768×1024 |
|---|---|---|---|---|---|---|
| HUD-Home (Wohnzimmer) | F1 (unthemed) | **F1+F2** (Stapel, geclippt) | F1; Cockpit ok, kein Rand-Margin | **F1+F2** | F1 | F1+F2 |
| Onboarding Schritt 1 | OK | F5 (Karte winzig) | OK | F5 | OK | F5 |
| Onboarding Schritt 3 | OK | F5 (Slider-Griffe ~9 px) | OK | F5 | OK | F5 |
| Settings | OK | F4 (klein, unten leer) | OK | F4 | OK | F4 |
| Arcade-Grid | OK | **F6** (1 Reihe, 80 % leer) | OK (luftig) | F6 | OK | F6 |
| Pregame | OK | **F4** (Chips ~25×14 px) | OK | F4 | OK | F4 |
| teaParty quer | OK (F9 Timer-Kontrast) | Letterbox ok | OK | Letterbox ok | OK | OK |
| teaParty hoch | Pillarbox ok | OK | Pillarbox ok | OK | Pillarbox ok | OK |
| GvZ quer | **F3** (Bank links geclippt) | — | F3 | — | F3 | — |
| GvZ hoch | **F3** (Spalte, Einheiten geclippt) | F3 | F3 | F3 | F3 | F3 |
| Album | OK | F4 (Sidebar-Buttons ~22 px) | F7 (nur linke Hälfte) | F4 | OK | F4 |
| Freunde | OK | F4 (klein, sonst sauber) | OK | F4 | OK | OK |
| Stadt-Fahrt | OK (F8 Schild/Chevrons) | OK — Framing gut | OK | OK | OK | OK |

Zusatz-Runs:
- Safe-Area (`HudLayoutLogic.safe_area_override`, 2340×1080 + 1080×2340): HUD rückt korrekt ein
  (`hud_home_safearea_*.png`) — aber der Portrait-Stapel (F2) bleibt.
- Echte Komposition (`real_home_*`, `real_onboarding_*`, `real_album_*`): **F0** überall sichtbar;
  Live-Rotation (`real_home_rotated_von_*.png`) schaltet Daumen-Bogen↔Cockpit korrekt live um.

## Findings

### P0
- **F0 — Theme erreicht Controls unter CanvasLayer nicht.** `UiTheme` setzt `root.theme`, aber
  HUD/Onboarding/Toasts leben im `UiLayer`-**CanvasLayer** (`home_entry.tscn`) und rendern als
  dunkelgraue Godot-Defaults statt AC-Pastell. Empirisch bewiesen: `e5_theme_probe.gd` →
  direktes Root-Kind bekommt FROST `(1,1,1,0.92)`, CanvasLayer-Kind `(0.1,0.1,0.1,0.6)`.
  Betrifft die GESAMTE In-Game-UI der echten App.
  Shots: `real_home_1280x720.png`, `real_onboarding_1080x2340.png`, `real_album_1280x720.png`.
- **F2 — Portrait-„Daumen-Bogen" kaputt:** HUD-Buttons stapeln sich als diagonaler Haufen unten
  rechts, überlappen einander und werden am rechten/unteren Rand geclippt. Die
  Layout-*Umschaltung* (quer↔hoch) funktioniert live, nur die Portrait-Platzierung ist falsch.
  Shots: `hud_home_720x1280.png`, `real_home_720x1280.png`, `real_home_1080x2340.png`,
  `hud_home_safearea_1080x2340.png`.

### P1
- **F1 — HUD bleibt über Router-Screens sichtbar:** `home_entry.gd` blendet `_hud` nie aus
  (nur Onboarding-Toggle, Z. 77/152). Beim Router-`goto(album)` liegen HUD-Cockpit-Buttons und
  Status-Kapseln ÜBER dem Album (Zurück-Button + Sidebar verdeckt).
  Shots: `real_album_1280x720.png`, `real_album_1080x2340.png`.
- **F3 — GvZ clippt Spawn-Bank/Einheiten am linken Rand** (beide Lagen); in Hochkant wird das
  Landscape-Grid in eine schmale Spalte gequetscht, unterste Reihe am Screen-Rand abgeschnitten.
  Shots: `gvz_quer_1280x720.png`, `gvz_hoch_1080x2340.png`, `gvz_hoch_768x1024.png`.
- **F4 — Systemisch zu kleine Touch-Ziele in Hochkant** (Stretch `expand` + Landscape-Basis):
  Pregame-Chips ~25×14 px, Album-Kategorien ~22 px, Settings-Toggles ~20 px physisch — alles <48 px.
  Shots: `pregame_720x1280.png`, `album_720x1280.png`, `settings_720x1280.png`.

### P2
- **F5 — Onboarding-Karte skaliert nicht** (fix ~540 Canvas-px): in Hochkant winzig zentriert,
  Slider-Griffe ~9 px physisch. Shots: `onboarding3_720x1280.png`, `onboarding1_1080x2340.png`.
- **F6 — Arcade-Grid reflowt nicht:** in Hochkant eine einzelne Mini-Reihe oben, ~80 % Leerfläche.
  Shot: `arcade_720x1280.png`.
- **F7 — Ultrawide/Hochkant-Leerflächen:** Album nutzt bei 2340×1080 nur die linke Hälfte; Album/
  Freunde/Settings lassen in Hochkant 60–70 % unten leer. Shots: `album_2340x1080.png`,
  `album_1080x2340.png`.

### P3
- **F8 — Stadt:** 3D-Schild als „KE" angeschnitten (oben links, quer); Lenk-Chevrons an den
  Bildrändern extrem kontrastarm/klein. Shots: `city_fahrt_1280x720.png`, `city_fahrt_1024x768.png`.
- **F9 — teaParty:** Timer („58 s") weiß auf hellgrün kaum lesbar; Tasse rechts angeschnitten (quer).
  Shot: `teaparty_quer_1280x720.png`.

## Positiv
- **Kamera-Framing Hochkant (User-Kernwunsch): GUT.** Raum füllt das Bild, Gooby + Kernmöbel
  zentriert (`hud_home_720x1280.png`, `real_home_1080x2340.png`, `city_fahrt_720x1280.png`).
- Minigame-Orientierungs-Umschaltung via Pregame **wirkt** (teaParty/GvZ in beiden Lagen,
  saubere Pillar-/Letterbox durch `MinigameHost`).
- Live-Rotation schaltet HUD-Layout korrekt um; Safe-Area-Override rückt HUD ein.
- Freunde-Screen und Stadt-Fahrt sind die robustesten Flächen der Matrix.
