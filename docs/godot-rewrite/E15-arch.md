# E15 — Architekturtreue zu den Design-Dokumenten

**Branch:** `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`)  
**Engine:** Godot `4.4.1.stable.official`  
**Verdict:** **FAIL / nicht architekturtreu.** Kein P0, aber vier eingefrorene
Verträge sind gebrochen. 438/438 Tests bestehen; sie prüfen die Integrations-
und Boot-Reihenfolge der Save-Slices sowie mehrere Contract-Shapes jedoch nicht.

## P0

Keine.

## P1

### P1-1 — Frozen SceneRouter-Verhalten ist nicht implementiert

Der Vertrag verlangt `DOOR_TRAVEL` additiv und ohne Veil sowie einen
8-s-Hard-Timeout (`docs/godot-rewrite/A-engine.md:91-108`). Die Implementierung
deklariert das vertragsgemäße Door-Verhalten dagegen ausdrücklich als M2-Backlog
(`GOOBY-GODOT/scripts/core/scene_router.gd:19-24`), setzt den Timeout auf 10 s
(`GOOBY-GODOT/scripts/core/scene_router.gd:38-43`) und führt für jeden
`travel_type` denselben COVER→SWAP→REVEAL-Pfad aus
(`GOOBY-GODOT/scripts/core/scene_router.gd:129-165`). Es gibt keinen
`DOOR_TRAVEL`-Branch. Die API-Namen `goto`, `VEIL_TRAVEL`, `DOOR_TRAVEL` sind
vorhanden, die eingefrorene Semantik aber nicht.

### P1-2 — Frozen GameState-Slice-API fehlt; Registrierungen kommen zu spät

Der Plan friert `GameState.register_slice(name, default, validator)` als
einzigen additiven Erweiterungsweg ein
(`docs/godot-rewrite/GODOT-PLAN.md:152-161,475-490`). `GameState` bietet diese
Methode nicht (`GOOBY-GODOT/scripts/state/game_state.gd:56-129`); Domains greifen
direkt auf die intern gewordene `SaveSchema.register_slice`-Registry zu
(`GOOBY-GODOT/scripts/state/save_schema.gd:38-53`,
`GOOBY-GODOT/scripts/home/home_state.gd:22-30`,
`GOOBY-GODOT/scripts/city/city_state.gd:21-26`).

Zusätzlich initialisiert der Autoload `GameState` bereits in `_ready`
(`GOOBY-GODOT/project.godot:23-37`,
`GOOBY-GODOT/scripts/state/game_state.gd:39-63`). `home`, `events`, `buffs` und
`bad` werden erst beim späteren `HomeEntry._ready` registriert
(`GOOBY-GODOT/scripts/home/home_entry.gd:22-29`), obwohl ihre eigenen Kommentare
„VOR GameState.initialize“ fordern
(`GOOBY-GODOT/scripts/home/home_state.gd:22-25`,
`GOOBY-GODOT/scripts/events/random_events.gd:28-33`,
`GOOBY-GODOT/scripts/events/buffs.gd:20-25`,
`GOOBY-GODOT/scripts/home/interactables/bad_state.gd:26-31`).

`city` wird im Produktions-Bootpfad nirgends registriert; die einzigen Aufrufe
sind Test/Perf-Helfer. `gvz` registriert sich erst in `setup`
(`GOOBY-GODOT/scripts/minigames/games/gvz/gvz_game.gd:45-48`). Damit fehlen
Defaults/Validatoren beim Load; insbesondere indiziert `CityState.set_flag`
anschließend hart einen möglicherweise nicht existierenden `city`-Slice
(`GOOBY-GODOT/scripts/city/city_state.gd:52-66`).

### P1-3 — Frozen Minigame-Contract wurde durch eine inkompatible API ersetzt

Doc G verlangt `MinigameBase extends Node`, `ctx` **vor** `add_child`, sowie
`setup/start/set_paused/apply_view/teardown`
(`docs/godot-rewrite/G-minigames.md:53-76,120-127`). Tatsächlich erbt die Basis
von `Node2D` und bietet `pause/resume/end`, aber weder `set_paused`,
`apply_view` noch `teardown`
(`GOOBY-GODOT/scripts/minigames/minigame_base.gd:1-48`). Der Host hängt die
Spielszene zuerst ein und ruft danach `setup`, wodurch `ctx` in `_ready` noch
null ist (`GOOBY-GODOT/scripts/minigames/minigame_host.gd:202-220`).
`MinigameCtx` ersetzt die Vertragsfelder `params`, gespeichertes `rng` und
`view_size` durch `run_seed` plus `rng()`-Factory
(`GOOBY-GODOT/scripts/minigames/minigame_ctx.gd:1-37`). Neue Spiele nach Doc G
sind damit nicht plug-kompatibel; Resize/Rotation kann den Pflicht-Hook nicht
aufrufen.

### P1-4 — Frozen Theme-Ownership wird breit umgangen

Tokens/Builder sollen die einzige Theme-Quelle sein
(`docs/godot-rewrite/H-ui-content.md:18-22`,
`docs/godot-rewrite/GODOT-PLAN.md:475-477`). Trotzdem definieren Screens
Hardcode-Farben, etwa Arcade/Friends/Minigame-Host
(`GOOBY-GODOT/scripts/minigames/arcade_screen.gd:74-76,171-192`,
`GOOBY-GODOT/scripts/ui/friends/friends_screen.gd:64-75`,
`GOOBY-GODOT/scripts/minigames/minigame_host.gd:98-101,166-182`), und bauen
eigene `StyleBoxFlat`s außerhalb des Builders
(`GOOBY-GODOT/scripts/ui/album/album_screen.gd:258-268`,
`GOOBY-GODOT/scripts/minigames/games/gvz/gvz_level_select.gd:110-118`).
`themes/tokens.gd`/`build_theme.gd` existieren und der Root erhält das Theme
korrekt (`GOOBY-GODOT/themes/theme_service.gd:26-45`), verhindern den Drift aber
nicht.

## P2

### P2-1 — Autoload-Reihenfolge enthält eine harte, wirkungslose Boot-Kopplung

`PackLoader` ist Autoload Nr. 1, `SceneRouter` erst Nr. 9
(`GOOBY-GODOT/project.godot:23-37`). `PackLoader._ready` prüft
`/root/SceneRouter` genau einmal
(`GOOBY-GODOT/scripts/updates/pack_loader.gd:40-44,224-232`); der Router kann zu
diesem Zeitpunkt nicht existieren. Der dokumentierte
`travel_finished`-Erfolgspfad für den Boot-Guard wird daher nie verdrahtet, nur
der 15-s-Fallback bleibt. Weitere Autoloads koppeln direkt an Root-Namen
(`GOOBY-GODOT/scripts/audio/audio_director.gd:62-73`,
`GOOBY-GODOT/scripts/social/social_services.gd:44-58`,
`GOOBY-GODOT/scripts/net/net_client.gd:287-294,335-349`). Diese Zugriffe sind
null-geprüft; im statischen Abhängigkeitsgraphen wurde kein Zyklus gefunden.
Der Headless-Boot lief ohne fatalen Fehler.

### P2-2 — Strings-Ownership weicht vom „eine Datei pro Domain“-Vertrag ab

Der Frozen-Plan verbietet gemeinsame `de.json` und fordert
`strings/de/<domain>.json` (`docs/godot-rewrite/GODOT-PLAN.md:475-479`).
Die Implementierung lädt weiterhin gemeinsame Root-Dateien
(`GOOBY-GODOT/scripts/ui/i18n.gd:6-11,92-102`), und `strings/de.json` enthält
mindestens `ui`, `hud`, `dialog`, `onboarding`, `settings`, `news`
(`GOOBY-GODOT/strings/de.json:1-80`). Auch einzelne Domain-Dateien bündeln
mehrere Domains (`GOOBY-GODOT/strings/de/city.json:1-32`,
`GOOBY-GODOT/strings/de/social.json:1-52`). Positiv: DE ist Default/Fallback
(`GOOBY-GODOT/scripts/ui/i18n.gd:15-17,81-89`), und der bestandene Test prüft
DE/EN-Parität, Placeholder und Kollisionen
(`GOOBY-GODOT/tests/unit/test_ui_strings.gd:43-95`).

### P2-3 — Zwei ungemergte Notification-Backends besitzen getrennten Zustand

`NotifyStub` hat eine statische Queue und `schedule_local/cancel_local`
(`GOOBY-GODOT/scripts/events/notify_stub.gd:1-50`); die Stadt besitzt parallel
eine Instanz-Queue mit `plane/storniere`
(`GOOBY-GODOT/scripts/city/notification_service.gd:1-66`). Beide Kommentare
bezeichnen den Merge noch als Backlog. Events schreiben nur in `NotifyStub`
(`GOOBY-GODOT/scripts/events/random_events.gd:172-189`), Reisen nur in
`CityNotificationService`
(`GOOBY-GODOT/scripts/city/travel/reise_app.gd:14-20`). Es gibt damit weder ein
gemeinsames Interface noch eine zentrale OS-/Foreground-Queue.

### P2-4 — Gemischte CRLF/LF-Zeilenenden trotz `.editorconfig`

`.editorconfig` erzwingt LF (`GOOBY-GODOT/.editorconfig:3-11`), ein
Repo-weites `\r$`-Scanning findet jedoch CRLF breit in produktivem Code,
Szenen, Tests und Strings, u. a.
`GOOBY-GODOT/scripts/minigames/minigame_base.gd:1`,
`GOOBY-GODOT/scripts/city/city_state.gd:1`,
`GOOBY-GODOT/scripts/ui/hud.gd:1`,
`GOOBY-GODOT/strings/de/city.json:1` und
`GOOBY-GODOT/scenes/city/city_scene.tscn:1`. Gleichzeitig sind Kern-Dateien wie
`project.godot`, `scene_router.gd` und `game_state.gd` LF. Das ist kein einzelner
Ausreißer, sondern ein gemischter Baum und kann `gdformat`/Diffs churnen.

### P2-5 — Orphaned/duplizierte Screens und eine fehlende Quellressource

- `FriendsScreen` registriert seine Route nur aus seinem eigenen `_ready`
  (`GOOBY-GODOT/scripts/ui/friends/friends_screen.gd:34-48`); kein
  Produktionsaufrufer registriert sie vor Navigation. `HomeEntry` registriert
  stattdessen den funktional überlappenden `SocialScreen`
  (`GOOBY-GODOT/scripts/home/home_entry.gd:34-38`). `friends_screen.tscn` ist
  dadurch außerhalb von Tests/Screenshots verwaist.
- Der HUD-Settings-Knopf emittiert nur `settings_pressed`
  (`GOOBY-GODOT/scripts/ui/hud.gd:322-325,435-437`); `HomeEntry` verbindet das
  Signal nicht (`GOOBY-GODOT/scripts/home/home_entry.gd:75-91`).
  `settings_screen.tscn` ist im Produktionsgraphen ebenfalls nicht erreichbar.
- Der HUD lädt `res://assets/ui/coin.png`
  (`GOOBY-GODOT/scripts/ui/hud.gd:286-296`), aber die Quell-PNG fehlt; vorhanden
  ist nur eine stale Import-Metadatei, die genau diese fehlende Quelle nennt
  (`GOOBY-GODOT/assets/ui/coin.png.import:1-14`). Ein frischer Import/Export kann
  das Münz-Icon daher nicht reproduzieren.

## P3

### P3-1 — Headless-Exit ist nicht vollständig sauber

`godot --headless --path . --quit-after 5` bootet, meldet beim Exit aber
`ObjectDB instances leaked` und zwei noch verwendete Ressourcen. Die komplette
Suite besteht (438/438); Navigation-Mesh-Baking meldet zusätzlich Laufzeit-
Geometrie-Parsing sowie gerundete `agent_max_climb`/`agent_radius`-Werte. Das ist
kein aktueller Contract-Blocker, sollte aber als Cleanup/Performance-Schuld
verfolgt werden.

## Bestanden / keine Finding

- `SaveSchema.SCHEMA_VERSION` bleibt 5
  (`GOOBY-GODOT/scripts/state/save_schema.gd:23-27`).
- `scripts/logic/**` sowie alle `*logic*.gd`-Module enthalten im Grep keine
  `extends Node*`, `get_node*`, `get_tree` oder `Engine.get_main_loop`-Nutzung.
- Keine statische Autoload-Zyklus-Kante gefunden; alle Root-Lookups sind
  `get_node_or_null`, nicht hartes `get_node`.
- DE/EN-Parität und Key-Kollisionsprüfung bestehen.
- Vollsuite: **438/438 bestanden**.
- Audit blieb read-only; `git diff --check` und `git status --short` waren sauber.

## Priorisierte Korrekturreihenfolge

1. Slice-API in `GameState` wiederherstellen und **alle** Domain-Slices vor
   `GameState.initialize()` zentral registrieren.
2. Minigame-Contract exakt auf Doc G zurückführen.
3. `DOOR_TRAVEL`-Semantik/Timeout gemäß Frozen Contract umsetzen.
4. UI-Hardcodes in Tokens/Builder überführen.
5. Notifications vereinheitlichen, tote Screens/Routen bereinigen und
   Zeilenenden repo-weit normalisieren.
