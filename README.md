# GOOBY 🐰

GOOBY ist ein virtuelles-Haustier-Spiel: ein fettes, liebenswertes Kaninchen zum
Füttern, Waschen, Anziehen und Bespaßen — mit eigenem Haus samt Baumodus, einer
Stadt mit freier Fahrt, Urlaub, Arcade-Minispielen, Stickeralbum und
Freunde-Besuchen. Dieses Repo (bzw. dieser Branch) enthält **GOOBY 5.0**: den
kompletten Neubau der alten Web-Version als natives **Godot-4.4.1**-Spiel,
Zielplattform **iPhone** (Installation per Sideload-`.ipa`), komplett auf
**Deutsch**.

> [!IMPORTANT]
> **Dieser Branch (`cursor/gooby-godot-loop-2c10`) ist eine eigenständige
> Arbeitslinie** im Repo `MedusaV9/MinecraftBubbleShieldMod`. Der `main`-Branch
> enthält ein **anderes Projekt** (eine Minecraft-Mod „Bubble Shield",
> Java/Gradle) — nicht mischen, nicht nach `main` mergen. Das GOOBY-Projekt ist
> in Runde W16 aus dem Repo `MedusaV9/CustomServerPrivate` hierher umgezogen;
> der volle Verlauf (Runden W1–W15) wurde übernommen.

## Was liegt wo

| Ordner | Inhalt |
|---|---|
| [`GOOBY-GODOT/`](GOOBY-GODOT/README.md) | Das Spiel: Godot-4.4.1-Projekt (Szenen, Skripte, Tests, Content-Packs, Export-Presets) |
| [`GOOBY/`](GOOBY/README.md) | Die alte Web-Version (GOOBY 4.0, three.js/Capacitor) — dient nur noch als **Referenz**, read-only |
| [`GOOBY-SERVER/`](GOOBY-SERVER/README.md) | Node-Mehrspieler-/Meta-Server (Freunde, Presence, GoobyPal, Codes, Besuche, Schiffe versenken) inkl. Admin-Webpanel |
| [`MONKEYBAR/`](MONKEYBAR/README.md) | **Eigenständiges, von GOOBY unabhängiges Projekt**, das aus dem alten Repo mitgezogen ist: „MONKEYBAR" 1.0, ein Online-Multiplayer-Bluff-Partyspiel mit Affen (three.js-Client + autoritativer Node-`ws`-Server, 6 Spielmodi, 10 Maps) |
| [`docs/`](docs/) | Design-Docs; das Godot-Rewrite lebt in [`docs/godot-rewrite/`](docs/godot-rewrite/) (Plan: `GODOT-PLAN.md`, Ist-Stand: `STATUS.md`) |
| [`tools/`](tools/ci/README.md) | Werkzeuge: Preflight/CI-Skripte (`tools/ci/`), Blender-Pipelines, Pack- und Audio-Tools |
| [`trailer/`](trailer/README.md) | Remotion-Projekt + fertiges Trailer-Video `GOOBY-5.0-Godot-Update-Trailer.mp4` |

Das frühere Root-README („# MonkeyBar") stammte noch vom MONKEYBAR-Projekt und
passte nicht mehr zum Inhalt dieses Branches.

## Spielen / Testen (iPhone)

1. Jeder Push, der `GOOBY-GODOT/**` berührt, baut in GitHub Actions
   (Workflow `.github/workflows/gooby-godot.yml`, Job `ios-ipa`) eine
   **unsignierte** `.ipa` und lädt sie als Artefakt **`GOOBY-godot-unsigned-ipa`**
   hoch — dort herunterladen.
2. Mit **AltStore** oder **Sideloadly** auf das iPhone sideloaden (die Tools
   signieren beim Installieren mit der eigenen Apple-ID).
3. Schritt-für-Schritt-Anleitung inkl. Troubleshooting:
   [`docs/godot-rewrite/IOS-BUILD.md`](docs/godot-rewrite/IOS-BUILD.md).
4. Spielstand aus der alten Web-/Capacitor-App übernehmen:
   [`docs/godot-rewrite/SAVE-TRANSFER.md`](docs/godot-rewrite/SAVE-TRANSFER.md)
   (drei Wege, automatisches Backup vor jedem Import).

## Entwickeln

Kurzfassung — die verbindlichen Arbeitsregeln stehen in
[`AGENTS.md`](AGENTS.md), Setup-Details in
[`GOOBY-GODOT/README.md`](GOOBY-GODOT/README.md):

- **Toolchain:** Godot 4.4.1 (stable), Python 3 + `gdtoolkit==4.*`
  (gdlint/gdformat), Node ≥ 18 (Server + Tools), optional Blender 4.x
  (Asset-Pipelines).
- **Preflight ist Pflicht:** Vor jedem Push, der `GOOBY-GODOT/**`,
  `tools/ci/**` oder den Workflow berührt, muss

  ```bash
  bash tools/ci/preflight.sh
  ```

  lokal grün laufen (spiegelt exakt die CI: Format, Lint, Import-Gate, beide
  Test-Runner, Boot-Smoke). Schnellvarianten: `--lint-only`, `--no-tests`.
- **Tests einzeln:** beide headless Runner stehen in
  [`GOOBY-GODOT/README.md`](GOOBY-GODOT/README.md) (Haupt-Runner
  `tests/run_tests.gd`, UI-Runner `tests/unit/run_w1c_tests.gd`).
- **Update-System (Content-Packs ohne neue App-Version):** Handbuch in
  [`docs/UPDATES.md`](docs/UPDATES.md).

## Mitreden

[`UserFeedback.md`](UserFeedback.md) ist der direkte Draht: Wünsche, Bugs und
Meckereien einfach unter „Neu von dir" eintragen — Stichworte reichen. Der
Agent liest die Datei vor und nach jeder Arbeitsrunde, hakt Erledigtes ab und
schreibt dazu, was er gemacht hat.
