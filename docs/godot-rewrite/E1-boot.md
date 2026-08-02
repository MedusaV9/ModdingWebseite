# E1 — Frisch-Boot & Onboarding (GOOBY-GODOT Mega-Eval)

Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`), Godot 4.4.1 headless + xvfb (gl_compatibility).
Profil-Wipe zwischen Läufen: `rm -rf ~/.local/share/godot/app_userdata/GOOBY`.
Treiber (NUR /tmp): `/tmp/e1_drive.gd` (Phasen fresh/second/abort/after_abort),
`/tmp/e1_verify_placeholder.gd`, `/tmp/e1_theme_probe2.gd`. Screenshots: `/tmp/gooby-godot/eval/shots/`.

## Verdict

Die Boot-/Onboarding-**Logik** ist solide: kein SCRIPT ERROR, Statemaschine, Save-Pipeline
(Name/Spitzname/Morphs → `user://save_v5.json`), Zweit-Boot-Skip und Abbruch-Semantik sind korrekt.
Die **Präsentation** ist doppelt kaputt (2×P1): Nach dem Onboarding sieht man NIE das Wohnzimmer
(Platzhalter-Overlay), und Onboarding/HUD rendern im Godot-Default-Grau statt im AC-Theme.

## Prüfmatrix

| # | Check | Ergebnis |
|---|---|---|
| 1 | Frisch-Boot ohne Save: SCRIPT ERROR? | ✅ keiner (`boot1.log`, `phase_fresh.log`) |
| 1 | Onboarding erscheint? | ✅ `OnboardingFlow` geladen, Welcome-Karte sichtbar (`01_welcome.png`) |
| 2 | Durchlauf: Name/Spitzname/Morphs im Save? | ✅ exakt: `playerName="ZwanzigZeichenName20"`, `goobyNickname="Flausch"`, `charMorphs {0.5,1.25,0.8,0.65}`, `onboarding.done=true` |
| 3 | Zweit-Boot: Onboarding übersprungen? | ✅ kein Flow; Route `home/living` mounted |
| 3 | Wohnzimmer lädt + HUD Startwerte? | ⚠️ Szene lädt (Wohnzimmer-Node3D aktiv), HUD zeigt coins=100, level=1, stats 80/90/85/70 — aber 3D-Sicht verdeckt (P1-1), HUD grau (P1-2). `09/10_*.png` |
| 4 | Kante leerer Name (auch nur Spaces) | ✅ bleibt WELCOME, roter Pflicht-Hinweis (`02_leerer_name_hinweis.png`) |
| 4 | Kante 20-Zeichen-Name | ✅ unverstümmelt übernommen (Limit 24: `onboarding_logic.gd:9` + `max_length=24` `onboarding_flow.tscn:64`) |
| 4 | Abbruch mitten drin + Neustart | ✅ Quit im Nickname-Step → kein/`done=false`-Save → Onboarding erscheint erneut, keine Daten-Reste (`08_nach_abbruch_wieder_onboarding.png`) |

## Findings

### P1-1 — Platzhalter-Overlay verdeckt dauerhaft die gesamte 3D-Welt
- `scripts/boot/main.gd:9-13` instanziert `home_entry.tscn`, blendet aber `UILayer/PlaceholderHome`
  nie aus; `scripts/boot/main.tscn:13-29` = Vollbild-Control mit **opakem** Cream-`Backdrop`
  (ColorRect) auf CanvasLayer `layer=10` (`main.tscn:10-11`).
- `home_entry.tscn` nutzt ebenfalls `layer=10` → dessen UI (HUD/Onboarding) zeichnet über den
  Platzhalter, die 3D-Viewport-Ausgabe (Wohnzimmer, Stadt, …) liegt aber IMMER darunter.
  Spieler sieht nach dem Onboarding nur „GOOBY / Platzhalter-Home — W1c baut hier das echte HUD.“
- Beweis: `shots/09_zweitboot_ist_zustand.png` (Ist) vs. `shots/10_zweitboot_platzhalter_ausgeblendet.png`
  (nach `placeholder.visible=false` per Laufzeit-Skript: voll möbliertes Wohnzimmer inkl. Gooby).
- Zusatzrisiko: `Backdrop` hat Default-`MOUSE_FILTER_STOP` → schluckt sehr wahrscheinlich alle Klicks
  in die 3D-Szene (Interactables/Türen), nur das eigene UI von HomeEntry liegt davor.
- Repro: Save mit `onboarding.done=true` vorhanden, dann
  `xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --script /tmp/e1_verify_placeholder.gd`

### P1-2 — AC-Theme erreicht Onboarding/HUD/Toasts nicht (Godot-Default-Grau)
- `themes/theme_service.gd:26-33` setzt das Theme nur als `window.theme` am Root-Window.
  Window-Themes propagieren aber **nicht durch CanvasLayer** — die Home-UI hängt unter
  `HomeEntry/UiLayer` (CanvasLayer, `scenes/home/home_entry.tscn`).
- Laufzeit-Beweis (`/tmp/e1_theme_probe2.gd`): `%StepWelcome.get_theme_stylebox("panel").bg_color`
  = `(0.1,0.1,0.1,0.6)` (Godot-Default) obwohl `root.theme=ac_theme.tres` inkl. korrekt
  registrierter Variation (`AcCardLg/base_type` `ac_theme.tres:990`); `flow.theme = ThemeService.theme()`
  → sofort Cream `(1,0.98,0.949)`.
- Die City-/Raum-Screens kennen den Workaround und setzen das Theme explizit
  (`scripts/city/city_scene.gd:412`, `scripts/city/ort_scene.gd:163`, `scripts/core/loading_veil.gd:59`,
  `scripts/home/room_base.gd`, Interactables) — **`home_entry.gd` nicht**: weder in `_build_hud()`
  (`scripts/home/home_entry.gd:75`) noch in `_show_onboarding()` (`:137`). Betroffen: kompletter
  Erstkontakt (Onboarding-Karten, Buttons, Slider) + dauerhaft HUD & Toasts.
- Soll-Zustand siehe Repo-eigenes Tool (`tests/unit/screenshot_w4p2.gd`, setzt `root.theme` direkt):
  `/tmp/gooby-godot/artifacts/W4P2/onboarding_konfetti.png` (cream/rosa) vs. Ist `shots/01_welcome.png` (grau).
- Fix-Kandidaten: `gui/theme/custom=res://themes/ac_theme.tres` in `project.godot` ODER
  `ThemeService.theme()` auf die UiLayer-Kind-Controls in `home_entry.gd` anwenden.
- Repro: `rm -rf ~/.local/share/godot/app_userdata/GOOBY && xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --script /tmp/e1_drive.gd ++ --phase=fresh`

### P3-1 — Autosave schreibt vor Onboarding-Abschluss einen Default-Save
- `home_entry.gd:42` (`_roll_random_event` → `RandomEventEngine.roll_on_start`) dirtied den State
  direkt beim Frisch-Boot; `save_manager.gd` flusht nach 800 ms → `save_v5.json` mit leerem
  `meta.playerName` und `onboarding.done=false` existiert, bevor der Spieler irgendetwas bestätigt hat.
  Harmlos (Onboarding erscheint wieder, Durchlauf überschreibt), aber ein Save „vor dem ersten Klick“
  ist unsauber und kostete den Eval-Treiber einen Race (Stale-Read).

### P3-2 — Namens-Overflow ohne Feedback
- >24 Zeichen werden still gekappt (`onboarding_logic.gd:32` `.left(24)`; LineEdit `max_length=24`).
  Kein Hinweistext à la „max. 24 Zeichen“. Nice-to-have.

### P3-3 — NavMesh-Bake beim Raum-Laden zur Laufzeit
- Beim Mount des Wohnzimmers: `WARNING: Source geometry parsing … had to parse RenderingServer meshes
  at runtime` + agent_radius/max_climb-Präzisionswarnungen (Log `phase_second.log`). Kostet Ladezeit
  auf Mobile; vorbakte NavMeshes/Collision-Shapes wären sauberer.

## Nicht beanstandet
- `--import` sauber (0 Errors/Warnings), Boot-Exit 0, keine SCRIPT ERRORs in allen 8 Läufen.
- Save-Atomik (tmp+rename, .bak-Rotation) und `onboarding.done`-Gate verhalten sich wie dokumentiert.
- Voice-Ticker korrekt headless-gegated (`onboarding_flow.gd:161`).
- „Socket error: 111“ (GOOBY-SERVER offline) nur im `--verbose`-Log, kein Spam, Boot unbeeinträchtigt.
