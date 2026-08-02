# G8-PT3 — Playtest „Minispiele & Arcade-Rahmen" (Welle H)

- **Agent:** PT-3 · **Branch:** `cursor/bubble-shield-loop` · **Datum:** 2.8.
- **Bereich:** Arcade-Einstieg (Grid, 38 Kacheln, Zähler-Kapsel, Scrollen),
  Pregame (Chips, Energie-Zeile, Bestwert, Sticker), MinigameHost (Countdown,
  HUD, Pause-Modal in der Tiefe, Results), Router-Blocker-Regression
  (ec242ee3), plus VIER Spiele WIRKLICH gespielt: Sternenhüpfer (starHopper),
  Möhrenwache (carrotGuard), Einkaufsfahrt (cityDrive), Memory (memoryMatch)
  — Teestube (teaParty) läuft als Rahmen-Vehikel mit.
- **Methode:** 5 Flows unter `tests/tools/playtest_flows/flow_pt3_*.gd` spielen
  das ECHTE Spiel (main.tscn) mit synthetischen Eingaben, jeder Lauf frisches
  `user://` durchs komplette Onboarding, Leitformat quer 2868x1320, strikt
  unter `flock /tmp/gooby_godot_global.lock tools/ci/run_playtest.sh
  flow_pt3_<x>`. Die Spiel-Flows lesen den Spielzustand wie ein aufmerksamer
  Spieler (Meteor-Bahnen, Maulwurf-Restzeit, Münz-Peilung, Kartengesichter)
  und tippen als ECHTE Touch-Events ins letterboxte Spielfeld
  (SubViewport-Mapping in `flow_pt3_basis.gd`). Awards/Energie werden EXAKT
  nachgerechnet (merke/prüfe-Zettel), nie nur „irgendwas gutgeschrieben".

## Lauf-Übersicht (finale Läufe)

| Flow | Finaler Lauf (unter `/tmp/gooby-godot/artifacts/PLAYTEST/`) | Ergebnis |
| --- | --- | --- |
| `flow_pt3_rahmen` | `pt3_a4` | 50 ok / 1 geplanter Diagnose-Soft-Fail = Befund **B1** (Kachel-Wisch scrollt nie). Grid 38/38 + Kapsel, Pregame-Rahmen, Pause-Modal (5 Knöpfe), History-Wache, „Zurück" → Wohnzimmer, keine Gratis-Runde |
| `flow_pt3_star_hopper` | `pt3_b1` | **0 fail (129 Schritte)** — reaktive Bahnwechsel, Treffer beendet Runde sauber, Results exakt (+8 ᴳ = Row-Min 4 ×2 Tagesbonus), „Nochmal" −8 Energie + frische Runde, Pause-„Neustart" Score 0 |
| `flow_pt3_carrot_guard` | `pt3_c1` | **0 fail (102 Schritte)** — round_finished-Breakdown gefangen, Award exakt (Score 2 → 4er-Row ×2 = +8 ᴳ, Konto-Delta +8), Klau-Ende (alle Möhren weg) durchlaufen, „Nach Hause" direkt ins Wohnzimmer |
| `flow_pt3_city_drive` | `pt3_d2` | **0 fail (117 Schritte)** — 90-s-Runde komplett (Score 200, 15 Münzen, 0 Crashes), Pause-Tiefe: Freeze-Beweis 9,69→9,69 s EXAKT, Hilfe-Typewriter, Ton-Schalter audio.master 0↔1, 3-2-1-Resume, Backdrop-Tap, Award +40 ᴳ = Row 20 ×2 |
| `flow_pt3_memory_match` | `pt3_e1` | **0 fail (138 Schritte)** — Brett 1 PERFEKT gelöst (0 Fehlgriffe), Spick-Knopf nach 7 sauberen Treffern (peek 1 s), Award +48 ᴳ = Row-CAP 24 ×2, „Nochmal" −8 Energie, Brett 2 drei Paare, Pause-„Beenden" |

Diagnose-Zwischenläufe (Belege): `pt3_a1`–`pt3_a3` (LoadingVeil-Lektion,
Scroll-Isolierung), `pt3_d1` (Freeze-Messfehler des Flows, gefixt),
`pt3_b1`-Zettel-Kollision (gefixt: getrennte `start_coins`/`start_energie`).
Minimal-Repro ohne Spielcode: `tests/tools/playtest_flows/pt3_scroll_probe.gd`.

## Befunde nach Schweregrad

### B1 — HOCH: Arcade-Grid ist per Touch-Drag AUF Kacheln nicht scrollbar (nur ~2 von 13 Reihen erreichbar)

- **Repro:** Arcade öffnen (38 Kacheln, 3 Spalten ≈ 13 Reihen, Scroller
  `max=3312, page=512`), Wisch mitten auf dem Grid (= auf einer Kachel) nach
  oben — `scroll_vertical` bleibt **0**. Der Container selbst ist gesund:
  Wisch in der 16-px-LÜCKE zwischen den Kachel-Spalten pannt sofort (+249),
  Mausrad pannt (+384), und `ensure_control_visible` (Code-Scroll) rollt
  einwandfrei. Auch ein synthetischer ECHTER Touch-Drag
  (`InputEventScreenTouch`+`ScreenDrag`, wie vom OS) auf einer Kachel pannt
  NICHT (633→633).
- **Beleg:** `pt3_a4/lauf.log` Zeilen „Scroll (…)": 0 → 0 → 0 (2 Kachel-Wischer)
  → +249 (Lücke) → +633 (Rad) → 633 (Touch-Drag auf `Tile_ghostHunt`);
  Screenshots `pt3_a4/018|021` (Grid unbewegt nach Wischern) vs.
  `pt3_a4/028_rad_hat_gescrollt.png` (Reihen 5–7 sichtbar, Grabber unten).
- **Minimal-Repro OHNE Spielcode** (`pt3_scroll_probe.gd`, nackter
  `ScrollContainer` + 40 `Button`s, echte Projekt-Settings): Knopf-Drag pannt
  NIE — weder als reiner Touch noch als Maus-Drag, weder mit `deadzone 0/24`
  noch mit `mouse_filter PASS` (Knopf drückt dabei weiterhin, `pressed` 1×).
  Es ist also KEIN Arcade-/SquishButton-Sonderfall, sondern Engine-Verhalten
  dieser Godot-4.4.1-Konstellation: der Knopf konsumiert den Press, der
  ScrollContainer armt sein Touch-Panning nie.
- **Einordnung (ehrlich):** Unter xvfb/X11 gibt es keinen echten Touchscreen —
  ob ein REALES Gerät (Android/iOS-Treiber, `is_touchscreen_available()=true`)
  anders routet, konnte diese Umgebung nicht final beweisen. Der Verdacht ist
  aber dringend, und die Wirkung wäre hart: Im Grid liegt Kachel an Kachel —
  Spieler kämen per Finger nur an die ersten ~6 der 38 Spiele. Dieselbe
  Bauart (Buttons füllen einen ScrollContainer) haben Kleiderschrank
  (`wardrobe_screen.gd`), Baumodus-Dock (`build_ui_dock.gd`), Füttern-Grid
  (`fuetter_grid.gd`), Customize (`customize_screen.gd`) u. a.
- **Fix-Verdacht:** Auf einem Gerät verifizieren (Mini-Log in
  `ScrollContainer`-Panning bzw. 2-Minuten-Handtest „im Grid auf einer Kachel
  wischen"). Falls es dort genauso ist: Drag-Shim im Arcade-Screen (bei
  `ScreenDrag` über der Kachel-Fläche `scroll_vertical -= relative.y` +
  Kachel-Press abbrechen), oder generisch ein kleines
  `TouchScrollShim`-Control über den betroffenen Scrollern. Die 16-px-Lücken
  taugen NICHT als Ausweg (niemand trifft sie absichtlich).

### B2 — KLEIN (theme-weit): Gedrückte/getoggelte Knöpfe schreiben WEISS auf Papierweiß (`font_hover_pressed_color` fehlt)

- **Repro:** Pause-Modal → „Hilfe" tippen. Der Chip ist `toggle_mode` und
  bleibt gedrückt+gehovert (Finger/Maus liegt drauf) — sein Label rendert
  jetzt WEISS auf Papierweiß und wirkt LEER („kaputter Knopf").
- **Beleg:** `pt3_d1/040_hilfe_lesen.png` (Chip rechts neben „Ton: An" scheinbar
  leer; Zoom zeigt weißes „Hilfe" auf Weiß).
- **Ursache:** `themes/build_theme.gd:_button_set` setzt `font_color`,
  `font_hover_color`, `font_focus_color`, `font_pressed_color` — aber NICHT
  `font_hover_pressed_color`. Godot fällt für hover+pressed aufs
  Default-Theme-WEISS zurück. Betrifft ALLE `_button_set`-Varianten: auch
  normale Knöpfe „blitzen" bei jedem Druck weiß (auf Paper-Fills unsichtbar).
- **Fix-Verdacht:** in `_button_set` zusätzlich
  `theme.set_color("font_hover_pressed_color", type, text)` (und
  `icon_hover_pressed_color`) setzen — eine Zeile, wirkt überall.

### B3 — KLEIN: JuiceKit-`float_text` ankert oben-links und clippt nicht — Meldungen ragen aus dem Spielfeld / würden auf Gerät abgeschnitten

- **Repro:** Möhrenwache, Maulwurf klaut eine Möhre aus der RECHTEN Loch-Spalte
  → „Eine Möhre geklaut!" beginnt am Loch-Zentrum und läuft ÜBER den rechten
  Spielfeld-Rand hinaus in die Letterbox-Fläche.
- **Beleg:** `pt3_c1/041_maulwurf_hauen_08.png`.
- **Ursache:** `juice_kit.gd:float_text` setzt `label.position = pos`
  (= Text-ANFANG am Ereignispunkt), die JuiceLayer clippt nicht. Am rechten
  Feldrand ragt der Text raus; auf einem echten Gerät (Feld = ganzer Schirm)
  wäre er am Schirmrand ABGESCHNITTEN. Gleiche Mechanik nutzen z. B. auch die
  „König besiegt!"-Zeile und die Teestuben-Serien-Texte.
- **Fix-Verdacht:** Label um `size/2` zentrieren und in die Layer-Rect klemmen
  (`pos.x = clamp(pos.x - w/2, 0, layer.w - w)`), alternativ
  `clip_contents = true` auf der JuiceLayer (dann wenigstens sauber gekappt).

### B4 — KLEIN: Host-Countdown (3-2-1/„Los!") zentriert auf dem CANVAS statt auf dem SPIELFELD

- **Repro:** Runde in einem Hochkant-Spiel starten (Leitformat quer →
  Letterbox-Streifen). Die Countdown-Ziffer sitzt in der FENSTER-Mitte; das
  Feld liegt (wegen Safe-Area-Zentrierung) daneben — beim Resume-„3" ragt die
  Ziffer halb ÜBER den Feldrand.
- **Beleg:** `pt3_d2/046_weiter_tippen.png` bzw. `pt3_d1/045_weiter_tippen.png`
  („3" ragt halb über den rechten Streifen-Rand), `pt3_b1/023…` („Los!" versetzt).
- **Ursache:** `minigame_host.gd` hängt `_countdown_label` mit
  `PRESET_CENTER` in das FULL-RECT-`_overlay` — Fenster-Mitte. Das Spielfeld
  (`_viewport_container`) zentriert sich dagegen in der SAFE-Fläche
  (`_layout_stage`), die bei asymmetrischen Insets (Notch quer; hier die
  xvfb-Phantom-Insets aus B6) verschoben ist.
- **Fix-Verdacht:** Countdown (und Schluss-Banner) wie die `_float_layer` am
  `_viewport_container`-Rect ausrichten — ein Anker-Sync in `_layout_stage`.

### B5 — HINWEIS (Balance): Einkaufsfahrt-Checkpoint-Ring in 2×90 s nie erreicht

- **Befund:** Zwei komplette Fahrten (llvmpipe-Bot lenkt mit der invertierten
  `_steer_from`-Formel des eingebauten Autopilots, Runde 2 mit 15 Münzen und
  0 Crashes) — `checkpoints` blieb BEIDE Male 0, der rosa Ring stand konstant
  bei „72 m". Wer wie der Autopilot (und wohl jedes Kind) immer zur nächsten
  Münze zieht, sieht den Ring nie von innen; seine +Sekunden/Punkte bleiben
  totes Feature.
- **Beleg:** `pt3_d1/lauf.log` + `pt3_d2/lauf.log` („Checkpoints 0" in beiden
  End-Ausbeuten), `pt3_d2/045…` (Ring-Pfeil „72 m" dauerhaft).
- **Vorschlag:** Ring an die Münz-Kette anlehnen (nächster Ring liegt AUF dem
  Weg zur dichtesten Münz-Gruppe) oder Ring-Radius/Spawn-Distanz senken.

### B6 — HINWEIS (Test-Umgebung, betrifft ALLE Wellen-Screenshots): xvfb-Screen 1280×1024 erzeugt PHANTOM-Safe-Insets rechts/unten

- **Befund:** `run_godot_isolated.sh` startet xvfb mit
  `XVFBARGS="-screen 0 1280x1024x24"`, das Spiel-Fenster ist aber 2868×1320.
  `DisplayServer.get_display_safe_area()` meldet dann den kleineren SCREEN,
  und `UiScale.safe_insets_canvas` klemmt das auf die 15-%-Kappe:
  **insets = rechts 234,6 / unten 108** (Beleg `pt3_a4/lauf.log`
  „[PT3] Metriken: canvas (1564, 720), f 1.00, insets {left 0, top 0,
  right 234.6, bottom 108}"). Folge: JEDES safe-area-zentrierte Element
  (Arcade-Inhaltsspalte, Pregame-/Results-Karten, Spielfeld) sitzt in ALLEN
  Playtest-Screenshots ~117 px links der Fenstermitte, unten fehlen 108 px.
- **Einordnung:** KEIN Spiel-Bug — die Safe-Area-Logik reagiert korrekt auf
  die (falschen) Treiberdaten; unfreiwillig ist es sogar ein dauerhafter
  Asymmetrie-Härtetest, den das Layout besteht. Fürs Screenshot-Urteil der
  Playtest-Wellen aber wichtig: „linkslastige" Karten sind Umgebungs-Artefakt.
- **Vorschlag (tools/ci, nicht von PT-3 geändert):** XVFBARGS auf
  `-screen 0 2868x1320x24` (oder ans `[BxH]`-Argument gekoppelt) heben.

### B7 — HINWEIS: Hochkant-Spiele laufen im Quer-Leitformat als schmaler Streifen (Desktop-/CI-Fallback)

- **Befund:** teaParty/carrotGuard/starHopper/cityDrive/memoryMatch sind
  `orientation: portrait`; der Host ruft die Bildschirm-Rotation
  (`Orientation not supported by this display server` in JEDEM Lauf-Log unter
  X11) und fällt auf Letterbox zurück — das Spielfeld belegt quer nur ~16 %
  der Breite. Auf Geräten rotiert der Schirm (richtig so), am Desktop bleibt
  der Streifen. Das Pregame bietet „Ausrichtung: Auto/Hochkant/Quer" an —
  gut; nur wirkt der Streifen im Quer-Modus arg verloren (Host-Backdrop füllt
  passend eingefärbt, aber leer).
- **Vorschlag:** Für den Desktop-/Streifen-Fall dezente Seitenfüllung
  (Vignette/Muster des Spiel-Themes) statt nackter Fläche — reine Kosmetik.

## Verifizierte Kern-Systeme (alles GRÜN, exakt nachgerechnet)

- **Blocker-Regression ec242ee3 (DER Welle-H-Check):** in ALLEN 5 Läufen liegt
  nach Pregame-Zurück, Pause-„Beenden", Results-„Zur Arcade" und „Nach Hause"
  NIE `mg_pregame`/`mg_host` in der Router-History (`get_history()`-Wache);
  Arcade-„Zurück" führt ins Wohnzimmer, danach lebt KEIN
  MinigameHost/-Results mehr im Baum (keine Gratis-Runden-Farm).
- **Energie §C6:** Rundenstart bucht exakt `energy_cost` ab — 8,0 (starHopper,
  carrotGuard, memoryMatch, teaParty) bzw. **6,0** (cityDrive,
  `difficulty_opt_in`); auch Results-„Nochmal" bucht erneut exakt −8,0.
- **Award-Mathe §G5.2 (Konto-Delta == Breakdown, Row ×2-Tagesbonus):**
  starHopper Score 30 → Row min 4 ×2 = **+8 ᴳ** ✓; carrotGuard Score 2 →
  Row min 4 ×2 = **+8 ᴳ** ✓ (round_finished-Breakdown 1:1: coins 8,
  firstToday true, xp 14, coinsFromLevels 0); cityDrive Score 200 → 200/10 =
  Row 20 ×2 = **+40 ᴳ** ✓; memoryMatch (perfekt + schnell) → Row-KAPPE 24 ×2 =
  **+48 ᴳ** ✓.
- **Pause-Rahmen G7-P56 (in 3 Spielen geprüft):** immer dieselben 5 Knöpfe
  (Weiter/Neustart/Ton/Hilfe/Beenden); **Freeze-Beweis** cityDrive: Sim-Uhr
  9,69 → 9,69 s über 2,5 s Modal-Zeit (SubViewport wirklich DISABLED);
  Hilfe-Typewriter tickt den Spiel-Hint („…rosa Ringe…"); Ton-Schalter kippt
  `audio.master` 0↔1 UND das Label „Ton: An/Aus"; „Weiter" zeigt ERST die
  3-2-1-Ziffer, dann läuft die Runde (`running && !game_paused`), dann wird
  der Pause-Knopf wieder aktiv; Uhr läuft nachweislich weiter (9,69→11,68);
  **Backdrop-Tap** neben der Karte = Fortsetzen (PanelStack-Kontrakt) ✓;
  Pause-„Neustart" startet frisch (Host-Score 0) ✓.
- **Results-Rahmen:** Gooby-Sticker, „Runde vorbei!", Punkte-Count-up (18→30
  beobachtbar), FeelStarRow (2 Sterne bei 30 P), „Neuer Rekord!" beim
  Erstlauf, Münz-Zeile MIT „Tagesbonus ×2!"-Kapsel, +XP-Zeile, die EINE
  Knopf-Reihe Nochmal/Zur Arcade/Nach Hause — alle drei Wege benutzt und
  korrekt (Quick-GO ohne 3-2-1 bei „Nochmal", Arcade-Route, Wohnzimmer-Route).
- **Arcade-Grid:** 38/38 Kacheln aus der Registry, Kapsel „38 Spiele",
  Kachel-Tap → Pregame (Route-basiert, wartet das LoadingVeil ab); Pregame
  zeigt Chips Leicht/Normal/Schwer (Endlos beim frischen Save korrekt
  gesperrt), „Kostet 8 Energie pro Runde", „Bestwert: 0", GoobySticker.
- **Spiel-Logik von innen:** starHopper-Treffer beendet die Runde hart
  (mg_lose-Cue im Pfad), Schauer-Bahnen in der Gefahr-Map; carrotGuard-Ende
  „alle Möhren geklaut" nach 2 Bonks; memoryMatch NIMMT nur echte Paare an
  (0 Fehlgriffe End-Beweis), Spick-Knopf erscheint nach 3+ sauberen Treffern
  und deckt 1 s auf (peek_left 0,83 gemessen), ×7-Combo-Popup.

## Qualitäts-Rangliste der getesteten Spiele (ehrlich, llvmpipe-Vorbehalt: kein Urteil über Glow/Performance)

1. **Einkaufsfahrt (cityDrive)** — rundestes Erlebnis: klare Lenk-Geste,
   lesbares 3D-Städtchen im Streifen, Crash-Pips, Ring-Pfeil mit Metern,
   sauberes 90-s-Pacing; Abzug: toter Checkpoint-Ring (B5).
2. **Memory (memoryMatch)** — beste „ruhige" Runde: Merk-Fenster, faires
   Auflöse-Tempo, Spick-Belohnung als cleverer Twist, Picknick-Optik mit
   Combo-Popups; Score-Kappe (Row 24) beim perfekten Lauf zeigt gesundes
   Balancing nach oben.
3. **Sternenhüpfer (starHopper)** — gutes Gefühl für Gefahr (Meteore +
   angekündigter Schauer), große konturierte Eigen-Popups (bewusst statt
   float_text — genau richtig, vgl. B3), harter aber fairer Rundenschluss;
   Abzug: Bahnwechsel-Hint nennt nur „wischen", Taps gehen auch (besser
   beides nennen).
4. **Möhrenwache (carrotGuard)** — solide Whack-a-Mole-Mechanik, König-HP
   und Klau-Drama funktionieren; Abzug: float_text-Ausreißer (B3) und im
   Streifen sehr kleine Möhren-Leiste; Hit-Fenster fühlten sich mit
   niedriger FPS hart an (Umgebung, kein Balance-Urteil).
5. **Teestube (teaParty, nur als Rahmen-Vehikel gespielt)** — Gieß-Geste und
   „Gieß bis ins grüne Band!"-Beat sind charmant; für ein Urteil übers
   Serien-Scoring bräuchte es einen eigenen Lauf.

**Arcade-RAHMEN gesamt:** Pregame→Countdown→Pause→Results ist konsistent,
hübsch und regelfest (EIN Look, exakte Buchungen) — die EINE echte Sorge ist
B1 (Grid-Scrollen per Finger), die den Katalog hinter Reihe 2 versteckt.

## Dateiliste (PT-3, nur eigene Dateihoheit)

- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt3_basis.gd` (+ `.uid`) —
  Host/Spielfeld-Mapping (Canvas↔Spiel-px), Rundenzustand
  (`spiel_aktiv`/Countdown/Results), Münz-/Energie-Zettel (getrennte
  Schlüssel), Router-History-Wache, `arcade_pregame_schritte`-Baustein
  (Route-basiert, LoadingVeil-fest, `energie_kosten`-Parameter).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt3_rahmen.gd` (+ `.uid`) —
  Arcade/Pregame/Pause/History + Scroll-Forensik (Wisch/Lücke/Rad/Touch-Drag,
  Metriken-Log für B6).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt3_star_hopper.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt3_carrot_guard.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt3_city_drive.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt3_memory_match.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/pt3_scroll_probe.gd` (+ `.uid`) —
  Standalone-Minimal-Repro für B1 (nackter ScrollContainer + Buttons,
  Touch-/Maus-Drags, STOP/PASS, deadzone-Varianten).
- `docs/playtest/G8-PT3-minispiele.md` (dieser Report)

Alle Dateien `gdformat`-/`gdlint`-sauber; KEINE Spiel-/Engine-Dateien
angefasst (Report only). Import (`--import` für `.uid`) lief unter flock.

## Screenshot-/Lauf-Pfade (Belege)

Basis: `/tmp/gooby-godot/artifacts/PLAYTEST/`

- Finale grüne Läufe: `pt3_a4/` (Rahmen + Scroll-Forensik), `pt3_b1/`
  (Sternenhüpfer komplett), `pt3_c1/` (Möhrenwache komplett), `pt3_d2/`
  (Einkaufsfahrt + Pause-Tiefe), `pt3_e1/` (Memory perfekt) — je `report.md`,
  `lauf.log`, `NNN_schritt.png`.
- Befund-Belege: B1 → `pt3_a4/018|021|022|025|028|031` + `lauf.log`
  (Scroll-Zeilen) + `pt3_scroll_probe.gd`-Ausgabe; B2 → `pt3_d1/040`;
  B3 → `pt3_c1/041`; B4 → `pt3_d1/045`, `pt3_d2/046`, `pt3_b1/023`;
  B5 → `pt3_d1|pt3_d2/lauf.log` („Checkpoints 0"); B6 → `pt3_a4/lauf.log`
  („[PT3] Metriken … insets"); B7 → alle Läufe (`Orientation not supported`,
  Streifen in jedem Spiel-Screenshot).
- Frühere Iterationen (Lern-Belege): `pt3_a1` (Veil-Blocker beim
  „Spielen!"-Tap), `pt3_a2` (Rahmen grün ohne Scroll-Forensik), `pt3_a3`
  (Scroll-Isolierung Wisch/Lücke/Rad), `pt3_d1` (Freeze-Messfehler → Flow-Fix).
