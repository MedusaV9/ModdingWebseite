# GOB-NOM-Level-Editor (@tool, W15/TECHKIT — Doc G §5)

Visuelles Bauen der GOB-NOM-Level-JSONs ohne Hand-Editieren. Der Editor ist
ein reines **Dev-Werkzeug**: nur im Godot-Editor nutzbar, in exportierten
Builds entsorgt er sich sofort selbst (`_ready`-Guard).

## Starten

1. `scripts/minigames/games/gobnom/editor/gobnom_level_editor.tscn` im
   Godot-Editor öffnen.
2. **F6** (Aktuelle Szene abspielen) drücken — der Editor braucht die
   GOB-NOM-Sim-Klassen (kein `@tool`), deshalb läuft er als abgespielte
   Szene, nicht im Editor-Viewport. Dort erscheint nur ein Hinweis-Label.

## Bedienung

- **Datei**: Pfad-Feld (Standard = eingecheckte
  `data/gobnom_levels.json`) + `Laden`/`Speichern`. Zum Experimentieren den
  Pfad z. B. auf `/tmp/mein_level.json` stellen — die eingecheckte Datei
  nie ungefragt überschreiben (Level-Daten gehören dem Sim-Owner). Hinweis:
  Godots JSON-Parser liest alle Zahlen als float, gespeichert wird darum
  `480.0` statt `480` (für Sim + Schema egal, alles läuft über float).
- **Level**: Track (`campaign`/`coop`) + Level-Auswahl. `Neues Level` legt
  ein minimales, schema-valides Level an (Bonbon, Mund, 1 Seil, 3 Gläser,
  leerer Lösungs-Plan — der Plan muss noch ins JSON, s. u.).
- **Ziehen**: Element im Feld anklicken (Auswahl-Ring) und ziehen — mit
  Snap-Raster (SpinBox, `0` = aus). Seile ziehen ihre Schiebe-Schiene
  (`rail`) mit. `candy`/`mouth` sind ebenfalls greifbar.
- **Elemente**: Kind wählen → `Platzieren` → Klick ins Feld legt ein neues
  Element mit Vorlage-Werten an. `Auswahl löschen` entfernt Listen-Elemente
  (nie `candy`/`mouth`). `Seil ans Bonbon koppeln` = „Verbinden“: setzt die
  Seil-Ruhelänge `rest` auf den aktuellen Abstand Anker → Bonbon.
- **Eigenschaften**: alle Zahl-/Bool-Felder der Auswahl (SpinBox/CheckBox);
  getippte `x`/`y` gelten exakt (Snap nur beim Ziehen).
- **Validierung**: `Level prüfen` läuft erst die Struktur-Checks
  (candy/mouth, exakt 3 Gläser, Lösungs-Plan vorhanden, alles in der Welt)
  und dann den **bestehenden Auto-Solver** (`GobnomSolver.run_solution`).
  Ergebnis: `LÖSBAR ✔` (grün) / `NICHT LÖSBAR ✘` (rot) + Solver-Report
  (Outcome, Gläser, Sterne, Ticks) und die Candy-Flugbahn des Lösungs-Plans
  als grüne/rote Linie im Feld.

## Lösungs-Plan

Der Lösbarkeits-Beweis ist der datengetriebene Plan
`level.solution.actions` (`{"t": Sekunden, "do": "cut|pop|puff|fan|slide", …}`,
Coop zusätzlich `"player": "a"|"b"`). Der Editor prüft und visualisiert den
Plan; die Aktions-Zeiten selbst werden (noch) im JSON gepflegt — nach jeder
Geometrie-Änderung neu validieren.

## Kein Export-Ballast

`_ready` räumt den Editor in Nicht-Editor-Builds sofort ab
(`OS.has_feature("editor")`). Zusätzlich ist bei W2b (Owner
`export_presets.cfg`) der Ausschluss
`res://scripts/minigames/games/gobnom/editor/*` als `exclude_filter` des
iOS-Presets angefragt (siehe Handoff W15-techkit), damit auch die
kompilierten `.gdc` nicht in die IPA wandern.

## Dateien

- `gobnom_editor_logic.gd` — pure, headless-testbare Logik (Laden/Speichern,
  Griffe, Snap, Eigenschaften, Struktur-Checks, Solver-Aufruf + Flugbahn).
  Tests: `tests/unit/test_w15_techkit.gd`.
- `gobnom_editor_canvas.gd` — Zeichen-/Maus-Schicht (Welt, Raster, Auswahl).
- `gobnom_level_editor.gd` + `.tscn` — UI-Schale (Panels, Knöpfe, Status).
