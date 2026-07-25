# GOOBY-GODOT

Der **Godot-Rewrite von GOOBY** (5.0): Das Web-/Capacitor-Spiel aus `GOOBY/` wird als
natives Godot-4-Spiel neu gebaut — Haus mit Baumodus, Stadt mit freier Fahrt, Urlaub,
Arcade-Minispiele (inkl. Goobys vs. Zombies), Random-Events, Stickeralbum, Freunde/Besuche
über den eigenen [GOOBY-SERVER](../GOOBY-SERVER/README.md) und ein Pack-Update-System.
Verbindlicher Plan: `docs/godot-rewrite/GODOT-PLAN.md` · Ist-Stand:
`docs/godot-rewrite/STATUS.md` · Web-Referenz `GOOBY/` bleibt read-only.

## Setup

Voraussetzungen: **Godot 4.4.1** (stable, Standard-Build), Python 3 mit pip,
optional Blender 4.x (Asset-Pipelines) und Node ≥ 18 (Goldwert-/Manifest-Tools).

```bash
# 1. Einmalig nach jedem frischen Checkout: Import-Cache aufbauen (PFLICHT vor allem anderen)
godot --headless --path GOOBY-GODOT --import

# 2. Spiel starten (Desktop-Fenster)
godot --path GOOBY-GODOT

# 3. Lint/Format (gdtoolkit — es gibt kein natives Godot-Lint)
pip install "gdtoolkit==4.*"
cd GOOBY-GODOT && gdlint scripts/ tests/ themes/ && gdformat --check scripts/ tests/ themes/
```

Wichtig: `gdlint`/`gdformat` immer **aus `GOOBY-GODOT/` heraus** aufrufen, damit die
`.gdlintrc` gefunden wird.

## Tests

Zwei Runner, beide headless (CI: `.github/workflows/gooby-godot.yml`):

```bash
# Haupt-Runner (W1a): entdeckt rekursiv tests/**/test_*.gd, Exit 0/1
godot --headless --path GOOBY-GODOT --script res://tests/run_tests.gd

# UI-Runner (W1c): tests/unit/test_ui_*.gd (Theme, HUD, Onboarding, Strings-Parität)
godot --headless --path GOOBY-GODOT --script res://tests/unit/run_w1c_tests.gd
```

Screenshot-Werkzeuge (`tests/unit/screenshot_*.gd`) brauchen einen echten Renderer:

```bash
xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
  --rendering-driver opengl3 --script res://tests/unit/screenshot_w1c.gd
```

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `scripts/boot/` | Main-Szene (`main.tscn`, Einstieg laut `project.godot`) |
| `scripts/core/` | SceneRouter, OrientationService, AppSettings, LoadingVeil |
| `scripts/state/` | GameState (Slice-Registry), SaveManager (Save v5, Backups, Recovery), Migration v0–v4→v5 |
| `scripts/home/`, `scenes/home/` | Räume, Türen (Steckenbleib-Gag), Grid-Baumodus, Lager |
| `scripts/city/`, `scenes/city/` | Stadt 15×12, freie Fahrt, Taxi, Reise/Urlaub, GOOBERANDO |
| `scripts/minigames/` | Framework (Host/Pregame/Results/JuiceKit) + Spiele inkl. `games/gvz/` |
| `scripts/net/` | NetClient (offline-first, Outbox, HELLO/WELCOME) für GOOBY-SERVER |
| `scripts/social/` | Besuche (Snapshot + POS-Relay), Schiffe versenken, GoobyPal |
| `scripts/ui/` | HUD, Onboarding, Settings, Toasts, `friends/` + `social/`-Screens, `i18n.gd` |
| `scripts/updates/` | PackLoader, Boot-Guard, ContentRegistry, UpdateService |
| `scripts/events/`, `scripts/character/` | Random-Events/Buffs, Gooby-Rig-Runtime |
| `strings/` | DE führend + EN-Parität, Domain-Dateien, Ownership: `strings/OWNERSHIP.md` |
| `content/` | Pack-Quellordner (core/balance/events/cosmetics/stickers/codes/config) |
| `themes/` | AC-Theme 2.0: `tokens.gd` → `build_theme.gd` → `ac_theme.tres` (nur Tokens verwenden!) |
| `tests/` | Beide Runner + `tests/unit/test_*.gd` + Fixtures/Goldwerte |
| `../tools/` | Blender-Pipelines (Gooby, Stadt), `cross_check.mjs` (Web-Goldwerte), CI-Helfer, Pack-Tools |

## Strings / Deutsch

Alle UI-Texte kommen aus `strings/de/*.json` + `strings/de.json` (DE ist führend,
EN muss paritätisch sein — `tests/unit/test_ui_strings.gd` erzwingt Parität,
Kollisionfreiheit und {platzhalter}-Gleichheit über ALLE Domains). Keine hartkodierten
deutschen Texte in `.gd`-Dateien. Wer eine Domain ändert: `strings/OWNERSHIP.md`.

## Content-Packs & Updates

Inhalte (Balance, Events, Kosmetik, Sticker, Codes, Server-Config) werden als
`.pck`-Packs über GitHub-Releases nachgeliefert — **ohne neue App-Version**.
Vollständiges Handbuch (Pack bauen, Manifest, Boot-Guard, Rollback):
**`docs/UPDATES.md`**. Pack-CI: `.github/workflows/gooby-packs.yml`,
Export-Presets `pack-<id>` in `export_presets.cfg`.

## iOS-Build — ehrlicher Stand

- Ein `ios`-Export-Preset existiert in `export_presets.cfg` (W2b), und
  `.github/workflows/gooby-godot.yml` enthält ein **dokumentiertes, per `if: false`
  deaktiviertes** `ios-ipa-skeleton`-Gerüst (macOS-Runner, Export-Templates, unsigned IPA).
- Es gibt **noch keinen laufenden iOS-Build**: kein Signing, keine Templates im CI-Cache
  verifiziert, kein Gerätetest. Scharfschalten ist Backlog M2
  (`GODOT-PLAN.md` §6 → B §5.2); Ziel bleibt eine unsignierte IPA zum Sideloaden
  (AltStore/Sideloadly), wie beim Web-Spiel (`gooby-ios.yml` — Achtung: dieser
  Workflow gehört zum ALTEN Web-Spiel unter `GOOBY/**`).
- Das native iOS-Notification-Plugin und der NSUserDefaults-Legacy-Reader sind Stubs
  mit dokumentiertem Goldweg (Backlog, siehe STATUS.md).

## Server

Multiplayer/Meta (Freunde, Presence, GoobyPal, Codes, Besuche, Schiffe versenken):
eigener Node-Server in [`GOOBY-SERVER/`](../GOOBY-SERVER/README.md) — ein Prozess,
ein Port, JSON-Storage, AMP-tauglich. Der Client läuft ohne Server vollständig
offline weiter (Offline-Chips statt Fehlern).
