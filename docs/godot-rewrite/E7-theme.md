# E7 — Theme-Treue (AC-2.0-Design-System)

**Eval-Agent E7** · Repo `/workspace` · Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`) · Projekt `GOOBY-GODOT/`
**Keine Repo-Änderung.** Alle Messungen laufen gegen eine Arbeitskopie unter
`/tmp/gooby-godot/eval/proj` (Godot 4.4.1, `xvfb-run`, gl_compatibility).
Shots + Montage: `/tmp/gooby-godot/eval/E7-shots/`.

---

## Kohärenz-Urteil (Kurzfassung)

**Das Design-System selbst ist gut. Die Anbindung ist es nicht.**

`themes/tokens.gd` + `themes/build_theme.gd` sind vorbildlich: eine Quelle, 27 Farb-Tokens,
Radien/Schatten/Motion/Typo als Konstanten, 38 Theme-Typen programmatisch gebaut,
`test_ui_theme.gd` prüft die Werte. Wo das Theme ankommt (Settings, HUD, Album, Veil),
sieht es aus wie **ein** Spiel — warm, rund, Paper-auf-Creme, Baloo-2.

Das Problem ist die **Zustellung**. Drei unabhängige, still scheiternde Mechanismen sorgen
dafür, dass große Teile der App das Theme gar nicht oder falsch bekommen. Godot meldet
in allen drei Fällen **keinen Fehler** — es fällt lautlos auf den Default zurück. Ergebnis:
**46 Buttons in 19 Dateien haben keine Identitätsfarbe**, **das komplette Minigame-UI
rendert im Godot-Default-Theme**, und **die Arcade-/Album-Kacheln sind Kreise statt Karten**.

Kohärenz-Note pro Screen (1 = fremd, 5 = eine Familie):

| Screen | Note | Kern-Befund |
|---|---|---|
| Settings | 5 | Referenz-Look. Nur der Scrollbalken ist Godot-Default. |
| Veil | 5 | Korrekt — als einziger mit explizitem Theme-Fix. |
| HUD | 5 | Frost-Kapseln + Stat-Tokens exakt. Ein Chip unter 48 px. |
| Album | 4 | Richtiges Creme + Drift, aber Kachel-Kreise, 18 Chips à 40 px, Default-Scrollbalken. |
| Freunde | 3 | Falsches Creme, kein Drift, kein Primär-Button. |
| Pregame | 3 | Falsches Creme, kein Drift, „Spielen!“ = „Zurück“ (identisch). |
| Arcade | 2 | Falsches Creme, kein Drift, Kacheln als weiße Ellipsen. |
| **GvZ Level-Select** | **1** | **Kein AC-Theme. Fremde Schrift, graue Kästen, dunkelgrauer Default-Button.** |

![Montage](E7-shots/15_kohaerenz_montage.png)

Farbtemperatur, Rundungen und Abstände driften genau dort auseinander, wo die Zustellung
bricht — die Inkonsistenzen sind **Symptome von drei Bugs**, nicht 40 unabhängige
Schlampereien. Das ist die gute Nachricht: P0-1 bis P0-3 zu fixen hebt sieben von acht
Screens auf einmal.

---

## P0 — Muss vor Release weg

### P0-1 · 46 Buttons referenzieren Theme-Variationen, die es nicht gibt

Das Theme definiert `BtnPink` / `BtnTeal` / `BtnLeaf` / `BtnYellow` / `BtnGhost` / `BtnDanger`
(`themes/build_theme.gd:119-124`). Der Produktionscode setzt aber durchgängig
`PrimaryButton` / `AccentButton` / `GhostButton` — **diese drei Namen existieren im Theme
nicht** (`themes/ac_theme.tres`, 38 Typen, keiner davon dabei).

Godot wirft dafür keinen Fehler: unbekannte `theme_type_variation` fallen still auf die
Basisklasse zurück. **Jeder Primär-CTA im Spiel rendert als neutrale Paper-Ghost-Pille,
optisch identisch zum „Zurück“-Knopf daneben.**

![Variationen](E7-shots/00_button_variations.png)

Verteilung: `GhostButton` 28×, `PrimaryButton` 16×, `AccentButton` 9× — **46 Zuweisungen
in 19 Dateien**. Auszug der wichtigsten CTAs:

| Datei:Zeile | Variation | Was der Nutzer sieht |
|---|---|---|
| `scripts/minigames/pregame.gd:133` | PrimaryButton | „Spielen!“ = „Zurück“ |
| `scripts/minigames/results.gd:83` | PrimaryButton | „Nochmal“ ohne Akzent |
| `scripts/minigames/minigame_host.gd:190` | PrimaryButton | „Weiter“ im Pause-Menü |
| `scripts/ui/social/visit_hud.gd:117` | PrimaryButton | „Bauen“ im Besuch |
| `scripts/ui/social/visit_hud.gd:55` | AccentButton | „Besuch beenden“ |
| `scripts/city/travel/reise_app.gd:165` | PrimaryButton | „Buchen“ (Kauf-CTA!) |
| `scripts/city/travel/reise_app.gd:197` | PrimaryButton | „Einsteigen“ |
| `scripts/city/orte/flughafen.gd:26` | PrimaryButton | „Reise“ |
| `scripts/city/drive_hud.gd:158` | PrimaryButton | Interaktions-Prompt |
| `scripts/home/build_mode/build_mode.gd:373` | PrimaryButton | „Fertig“ im Baumodus |
| `scripts/home/room_base.gd:527` | PrimaryButton | „Neu bauen“ |
| `scripts/social/boardgame/battleship_scene.gd:202` | PrimaryButton | „Bereit“ |
| `scripts/social/boardgame/battleship_scene.gd:221` | AccentButton | Tomaten-Wurf |
| `scripts/ui/social/goobypal_sheet.gd:100` | PrimaryButton | „Senden“ |
| `scripts/city/haendler_sheet.gd:92` | AccentButton | Kauf-Buttons |

Vollständige Liste: `rg -n 'theme_type_variation.*(PrimaryButton|AccentButton|GhostButton)' scripts/`

**Ursache:** Namens-Drift zwischen Wellen. W1c baute `Btn*`, die Wellen W2d/W3a/W3c
nahmen die naheliegenden Namen `PrimaryButton`/`GhostButton` an. Nichts prüft das.

**Fix (klein):** entweder in `build_theme.gd` drei Aliase ergänzen
(`PrimaryButton`→PINK, `AccentButton`→TEAL/YELLOW, `GhostButton`→PAPER) oder die 46
Fundstellen umbenennen. Aliase sind der risikoärmere Weg. **Plus** der fehlende Test,
siehe P3-5.

---

### P0-2 · Das gesamte Minigame-UI liegt außerhalb der Theme-Vererbung

Godot propagiert Themes **nur über Control- und Window-Knoten**. Zwei Konstruktionen im
Minigame-Stack brechen die Kette:

- `scripts/minigames/minigame_base.gd:2` — `extends Node2D`. Alle Spiele erben davon.
- `scripts/minigames/minigame_host.gd:219` — `_viewport.add_child(_game)`, also ein
  `SubViewport`. Ein SubViewport ist kein Window; das Root-Theme kommt dort nicht an.

GvZ ist damit **doppelt abgeschnitten** (SubViewport → Node2D). Gemessen, nicht geraten:

```
A Control -> Window-Root   bg=fffaf2 (PAPER)  font_size=22   AC-Theme: JA
B unter Node2D             bg=1a1a1a          font_size=16   AC-Theme: NEIN
C in SubViewport           bg=1a1a1a          font_size=16   AC-Theme: NEIN
```

![Beweis](E7-shots/09_theme_inheritance_proof.png)

Selbst `BtnPink` und `AcCard` werden in B und C komplett ignoriert. Genau so sieht der
Level-Select im Spiel aus — fremde Schrift, graue Kästen, dunkelgrauer Default-Button:

![GvZ](E7-shots/06_gvz_select.png)

**Und der wichtigste Punkt:** das Team kennt den Bug bereits. `scripts/core/loading_veil.gd:58`
kommentiert *„CanvasLayer-Gotcha (W3d-Handoff): Window-Theme kommt hier nicht an“* und setzt
in Zeile 59 `_root.theme = ThemeService.theme()`. Neun Node2D/Node3D-Screens in Haus/Stadt/
Events haben denselben Fix. **Nur die Minigames, das Brettspiel und das Besuchs-HUD nicht:**

| Datei | Typ | Theme-Fix |
|---|---|---|
| `scripts/core/loading_veil.gd:59` | CanvasLayer | ✅ |
| `scripts/city/ort_scene.gd`, `scripts/home/room_base.gd`, +7 weitere | Node2D/3D | ✅ |
| `scripts/minigames/minigame_base.gd:2` | Node2D | ❌ |
| `scripts/minigames/minigame_host.gd:219` | SubViewport | ❌ |
| `scripts/social/boardgame/battleship_scene.gd` | Node2D | ❌ |
| `scripts/ui/social/visit_hud.gd` | CanvasLayer | ❌ |

**Fix:** in `MinigameBase._ready()` (und den beiden anderen) einen Control-Root mit
`theme = ThemeService.theme()` setzen — vier Zeilen, hebt GvZ/TeaParty/CarrotCatch/
Schiffe-versenken/Besuch auf einen Schlag.

**Folgeschaden:** `gvz_level_select.gd` ist die Datei mit den meisten hartkodierten
Styles der ganzen Codebase (siehe P1-4). Das ist kein Zufall — der Agent hat die fehlende
Theme-Vererbung von Hand nachgebaut. Nach dem Fix kann der Großteil davon weg.

---

### P0-3 · `AcCard` auf Buttons ⇒ Kreise statt Karten

`AcCard` ist eine **PanelContainer**-Variation (`build_theme.gd:167`) und definiert nur
die Stylebox `panel`. Ein `Button` fragt `normal`/`hover`/`pressed` ab, findet unter
`AcCard` nichts und landet beim Basis-Button — der Pill-Radius 999.

Gemessen:

```
PanelContainer[AcCard].panel   bg=fffaf2 radius=28  shadow=10
Button[AcCard].normal          bg=fffaf2 radius=999 shadow=0
Button[ohne Variation].normal  bg=fffaf2 radius=999 shadow=0   -> identisch
```

![AcCard auf Button](E7-shots/11_accard_auf_button.png)

Betroffen sind die zwei sichtbarsten Kachel-Raster des Spiels:

- `scripts/minigames/arcade_screen.gd:123` — `Button` 250×240 mit `AcCard`
- `scripts/ui/album/album_screen.gd:217` — `SquishButton` 190×200 mit `AcCard`
- `scripts/events/event_runner.gd:235` — Event-Auswahlkarte

In der Arcade sieht man das Ergebnis ungeschminkt: weiße Ellipsen, aus denen die
eckigen Cover herausragen.

![Arcade](E7-shots/12_arcade_voll.png)

**Fix:** Kachel = `PanelContainer[AcCard]` mit einem transparenten Button darüber, **oder**
eine echte Button-Variation `AcCardButton` im Theme (`_card()`-Stylebox für
normal/hover/pressed). Zweiteres ist sauberer und macht `SquishButton` weiter nutzbar.

---

## P1 — Sichtbare Inkonsistenz

### P1-1 · Drei verschiedene „Creme“-Töne

`AcTokens.BG_CREAM` ist `#FFF6EC`. Vier Screens hartkodieren stattdessen
`Color(0.98, 0.94, 0.87)` = **`#FAF0DE`** — im Blaukanal 14 Stufen tiefer, also spürbar
gelblicher/stumpfer. Aus den gerenderten PNGs gemessen (nicht geschätzt):

| Screen | Hintergrund | |
|---|---|---|
| Settings, Album, HUD, Veil, GvZ | `(255, 246, 236)` | = Token ✅ |
| **Arcade, Freunde, Pregame** | `(250, 240, 222)` | **≠ Token ❌** |

Fundstellen:
`scripts/minigames/arcade_screen.gd:76` · `scripts/minigames/pregame.gd:59` ·
`scripts/ui/friends/friends_screen.gd:66` · `scripts/ui/social/social_screen.gd:79`

Ein **dritter** Creme-Ton steckt in `scripts/minigames/games/gvz/gvz_art.gd:10`
(`CREAM = #F9EDD6`). Für eine Illustrationsfläche vertretbar, aber es sind damit drei
„Creme“-Definitionen im Umlauf.

**Fix:** `AcTokens.BG_CREAM` einsetzen. Besser noch: die vier `ColorRect`-Hintergründe
durch `AcWallpaper` ersetzen — löst P1-2 gleich mit.

---

### P1-2 · Drift-Wallpaper fehlt auf der Hälfte der Screens

`AcWallpaper` (`scripts/ui/wallpaper.gd`) ist laut eigenem Docstring „der AC-Look für
**ALLE** Screens“. Zur Laufzeit im Szenenbaum gefunden:

| Screen | Drift-Wallpaper |
|---|---|
| Settings, Album, Veil, Onboarding | ✅ |
| **Arcade, Freunde, Pregame, Social, GvZ** | ❌ (flacher `ColorRect`) |
| HUD | ❌ — **korrekt**, liegt über dem 3D-Raum |

Die fünf Screens ohne Wallpaper sind exakt die mit dem falschen Creme (P1-1): es ist
derselbe `ColorRect.new()`-Reflex. Nebeneffekt: `AcTokens.DRIFT_OPACITY`/
`DRIFT_TILES_PER_SEC` und der Reduced-Motion-Schalter greifen dort nicht.

> Achtung bei den bestehenden Artefakten: `tests/unit/screenshot_w1c.gd:46` und
> `screenshot_w4p2.gd:87` hängen das Wallpaper **im Testcode** manuell hinter das HUD.
> Die Review-Screenshots sehen dadurch besser aus als die Szene tatsächlich ist.

---

### P1-3 · Touch-Floor: 25 von 58 Buttons unter 48 px

`AcTokens.TOUCH_FLOOR = 48` („überall `custom_minimum_size ≥ 48×48`“). Zur Laufzeit
gemessene **tatsächliche** Höhen bei 1280×720:

| Screen | Buttons | < 48 px |
|---|---|---|
| Album | 25 | **18** (alle Seiten-Chips, 232×**40**) |
| Pregame | 8 | **6** (Schwierigkeit + Ausrichtung, ~80×**40**) |
| HUD | 9 | 1 (`WhereIsGoobyChip`, 175×**40**) |
| Settings, Arcade, Freunde | 16 | 0 |

**Ursache liegt im Theme, nicht an den Aufrufern:** `build_theme.gd:146-160` (`_chipify`)
setzt `content_margin_top 5` / `bottom 7` bei `font_size 17` → 40 px. Jeder `AcChip`
ist damit systematisch 8 px zu flach.

Ehrliche Einordnung: `build_theme.gd:125` kommentiert *„Chips: 40 px hoch (H §1.1)“* —
die Spec **will** hier 40 px und widerspricht damit ihrer eigenen 48-px-Regel. Das ist
zu entscheiden, nicht stillschweigend zu lassen. Kritisch ist es beim **Album**: die
18 Chips sind dort die *primäre* Seitennavigation, kein Zierfilter.

---

### P1-4 · GvZ-Level-Select baut das Design-System von Hand nach

`scripts/minigames/games/gvz/gvz_level_select.gd:111-118` (`_style_tile`) erzeugt
**15 Kacheln × 5 Zustände = 75 `StyleBoxFlat`-Instanzen** zur Laufzeit, mit fünf Farben,
die in keinem Token stehen:

| Zeile | Wert | Rolle |
|---|---|---|
| `:96` | `#E7DFD3` | gesperrt |
| `:104` | `#DFF2CF` | geschafft |
| `:104` | `#FFF6E3` | offen (vierter Creme-Ton) |
| `:117` | `#CDBFAE` | Rahmen gesperrt |
| `:80` | `#B3A99C` | Text gesperrt |

Dazu Radius 14 statt `RADIUS_CARD` 28, harte 2–3-px-Rahmen (nirgends sonst im Spiel),
kein Schatten. Der „Fertig“-Button (`:54`) hat gar keine Variation.

Das ist **Folge von P0-2** — ohne Theme blieb dem Agenten nichts anderes übrig. Nach dem
Vererbungs-Fix sollte `_style_tile` durch `AcCard`/`ChipLeaf` ersetzt werden.

Positiv erwähnenswert: das ist die **einzige** nennenswerte Ad-hoc-Stylebox-Stelle.
Repo-weit gibt es nur **3** `StyleBoxFlat.new()` in `scripts/` und **0** in allen `.tscn`.
Die Disziplin ist insgesamt gut.

---

### P1-5 · Scrollbalken sind ungestylt

Das Theme kennt weder `VScrollBar` noch `HScrollBar`. Auf jedem scrollenden Screen sitzt
damit Godots dunkelgrauer Default-Balken in der Pastell-Palette — im Album (linke Rail)
und in den Settings gut sichtbar. Ein `_build_scrollbars()` in `build_theme.gd`
(TRACK_SOFT-Track, INK_FAINT-Grabber, Pill-Radius) schließt die Lücke global.

---

## P2 — Token-Verstöße mit geringerer Sichtbarkeit

**P2-1 · Scrims umgehen die Veil-Tokens.** `AcTokens.VEIL` = `rgba(0.29,0.23,0.21,0.35)`
(warmes Braun). Stattdessen:
`scripts/ui/social/goobypal_sheet.gd:34` → `Color(0,0,0,0.35)` (reines Schwarz, kalt) ·
`scripts/minigames/results.gd:18` → `Color(0.24,0.16,0.12,0.55)` (dunkler + undurchsichtiger).
Drei verschiedene Abdunklungen für dieselbe Geste.

**P2-2 · Ergebnis-Screen erfindet eine Textpalette.**
`scripts/minigames/results.gd:54,58,63,65,67,74,77` — sieben freihändige Farben
(`Color(1.0,0.62,0.16)`, `Color(0.42,0.6,0.36)`, `Color(0.93,0.61,0.15)` …), obwohl
`YELLOW`/`LEAF`/`PINK`/`INK_SOFT` genau diese Rollen abdecken.

**P2-3 · Freundes-Status frei gefärbt.** `scripts/ui/friends/friend_list_ui.gd:27-30`
(`COLOR_ONLINE/CONNECTING/OFFLINE/HINT`) und `friends_screen.gd:330` — statt
`LEAF`/`YELLOW`/`INK_FAINT`/`DANGER`.

**P2-4 · Chip-Auswahl praktisch unsichtbar.** `pregame.gd:160` markiert die Auswahl über
`button_pressed`. Der `pressed`-Zustand unterscheidet sich in `_pill()` nur durch
Bodenlippe 4→2 px (`build_theme.gd:86-88`). Im Screenshot ist nicht erkennbar, welche
Schwierigkeit aktiv ist:

![Pregame](E7-shots/14_pregame_voll.png)

Dem System fehlt ein „Chip aktiv“-Zustand (die `TabBar` hat mit `tab_selected` einen —
Leaf-Pille, weißer Text). Vorschlag: `AcChip` bekommt eine `pressed`-Stylebox in LEAF.

**P2-5 · Font-Sizes an der Theme-Variation vorbei.** Nur 7 Stellen, davon 4 legitime
Display-Größen (`minigame_host.gd:149` = 96 Countdown, `drive_hud.gd:103` = 56 Chevron,
`juice_kit.gd:100` = 30, `perf_overlay.gd:142` = 15 Dev). Echte Verstöße:
`gvz_level_select.gd:36` (30 statt `TitleLabel` 28 / `HeadlineLabel` 34), `:51` (18 —
zwischen CAPTION 15 und BODY 20), `:75` (20 = exakt `FONT_SIZE_BODY`, also redundant).
Insgesamt ein sehr gutes Ergebnis.

---

## P3 — Aufräumen

**P3-1 · Gooby-Palette doppelt gepflegt.** `scripts/core/loading_veil_gooby.gd:13-18` und
`scripts/ui/onboarding/gooby_preview.gd:15-19` sind Copy-Paste (identisch bis auf die
Zeile `SHADOW`). Beide definieren `OUTLINE = #4A3B36`, was **exakt** `AcTokens.INK` ist,
und `SHADOW = rgba(0.2902,0.2314,0.2118,0.16)`, was exakt `AcTokens.SHADOW_PRESS_COLOR` ist —
als Literal statt als Token-Referenz.

**P3-2 · gvz_art: Palette passt, Referenzen fehlen.** Bewertung der 18 Konstanten in
`gvz_art.gd:9-27`: **4 sind zeichengenau Tokens** — `STAR_GOLD #FFD34D` = `GOLD`,
`BERRY_RED #E0655F` = `DANGER`, `MELON_GREEN #6DB54E` = `LEAF_DARK`, `OUTLINE #4A3B36` = `INK`.
Die anderen 14 (`WOOD`, `CARROT`, `ICE`, `METAL` …) sind Requisiten-Farben ohne
Token-Entsprechung — als Illustrationspalette **legitim und farblich harmonisch**
(warm, entsättigt, gleiche Temperatur wie die AC-Palette). **Urteil: geht in Ordnung.**
Nur die 4 Duplikate sollten `AcTokens.*` referenzieren, sonst driften sie beim nächsten
Token-Umbau auseinander.

**P3-3 · Boot-Szene hartkodiert.** `scripts/boot/main.tscn:45,52` setzen INK als
Literal `Color(0.290196, 0.231373, 0.211765, 1)`, `:46,:53` die Größen 72/24 (keine Tokens).
Onboarding: `onboarding_flow.tscn:72` = `Color(0.8784,0.3961,0.3725,1)` — exakt `DANGER`,
nur inline.

**P3-4 · Kleinkram.** `visit_hud.gd:44,50` Outline `Color(0.25,0.18,0.12)` ≠ `INK`. ·
`hud.gd:392` setzt `modulate` auf `Color(1.0,0.82,0.82)`, `:398` tweent auf
`Color(1.0,0.8,0.8)` — zwei minimal verschiedene Zielwerte, vermutlich Tippfehler. ·
`album_screen.gd:19-22` Rarity-Rahmen: `episch #FFD34D` = `GOLD`, aber
`selten #C7CBD6` / `geheim #C9A6E8` sind tokenlos.

**P3-5 · Der fehlende Test (wichtigste Präventivmaßnahme).** `tests/unit/test_ui_theme.gd:81`
prüft nur *„existiert Theme-Typ X?“*. Niemand prüft die Gegenrichtung: *„ist jede im Code
gesetzte `theme_type_variation` im Theme definiert?“* Genau deshalb konnten 46 tote
Referenzen (P0-1) durch 400+ grüne Tests, gdlint und CI rutschen.

Ein Test von ~15 Zeilen — alle `.gd`/`.tscn` nach `theme_type_variation` grep‘en, gegen
`ThemeService.theme().get_type_list()` prüfen — hätte P0-1 am Tag der Entstehung gefangen.
**Dringend nachrüsten**, sonst kommt die Drift bei der nächsten Welle zurück. Analog wäre
ein Test sinnvoll, der Card-Variationen auf Nicht-PanelContainern verbietet (P0-3).

---

## Zusammenfassung nach Aufwand

| Fix | Umfang | Hebt |
|---|---|---|
| 3 Button-Aliase in `build_theme.gd` | ~10 Zeilen | 46 Buttons, 19 Dateien (P0-1) |
| Theme-Root in `MinigameBase` + 2 Stellen | ~12 Zeilen | Alle Minigames, Brettspiel, Besuch (P0-2) |
| `AcCardButton`-Variation | ~15 Zeilen | Arcade + Album + Events (P0-3) |
| `AcWallpaper` statt `ColorRect` ×4 | ~8 Zeilen | P1-1 **und** P1-2 |
| `_build_scrollbars()` | ~15 Zeilen | Alle scrollenden Screens (P1-5) |
| Variations-Existenz-Test | ~15 Zeilen | Verhindert Rückfall (P3-5) |

Rund 75 Zeilen bringen sieben von acht Screens auf Referenz-Niveau. Der teuerste Posten
ist danach das Aufräumen von `gvz_level_select.gd` (P1-4), das erst nach P0-2 sinnvoll ist.

---

## Methodik / Reproduktion

Statische Analyse gegen `/workspace/GOOBY-GODOT` (nur lesend). Laufzeit-Messungen gegen
die Kopie `/tmp/gooby-godot/eval/proj` mit drei Eval-Skripten (`screenshot_e7*.gd`,
`audit_e7_touch.gd`), die **nur dort** liegen:

```bash
cd /tmp/gooby-godot/eval/proj
xvfb-run -a godot --path . --rendering-method gl_compatibility \
  --rendering-driver opengl3 --script res://tests/unit/screenshot_e7.gd
```

Hintergrundfarben wurden per Pixel-Sampling aus den PNGs gelesen, Button-Größen über
`Control.size` **nach** dem Layout, Stylebox-Auflösung über `get_theme_stylebox()` —
alles gemessen, nichts geschätzt.

Artefakte in `/tmp/gooby-godot/eval/E7-shots/`: `00_button_variations` ·
`01_hud` · `02_settings` · `03_arcade` · `04_album` · `05_freunde` · `06_gvz_select` ·
`07_pregame` · `08_veil` · `09_theme_inheritance_proof` · `10_veil_sichtbar` ·
`11_accard_auf_button` · `12_arcade_voll` · `13_album_voll` · `14_pregame_voll` ·
`15_kohaerenz_montage`.
