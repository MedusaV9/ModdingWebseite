@tool
class_name GobnomEditorLogic
extends RefCounted
## W15/TECHKIT (Doc G §5) — PURE Logik des GOB-NOM-@tool-Level-Editors:
## Laden/Speichern der Level-Dokumente, Element-Griffe (Ziehen mit
## Snap-Raster, Eigenschaften, Hinzufügen/Entfernen) und die Lösbarkeits-
## Validierung über den BESTEHENDEN Auto-Solver (GobnomSolver, injizierbar
## für Tests). Komplett node-frei und headless-testbar — die @tool-Szene
## (gobnom_level_editor.gd) ist nur die Zeichen-/Maus-Schicht darüber.
##
## Die Level-Daten selbst bleiben TABU-konform unangetastet: der Editor
## LIEST res://…/gobnom_levels.json und schreibt nur dorthin, wohin der
## Nutzer (bzw. der Roundtrip-Test: /tmp) explizit speichert.

## Verschiebbare Element-Listen eines Levels (Schema der Level-JSONs).
const ELEMENT_KEYS: Array[String] = [
	"ropes", "bubbles", "cushions", "fans", "shooters", "spikes", "clouds", "jars"
]
## Verschiebbare Einzelpunkte.
const POINT_KEYS: Array[String] = ["candy", "mouth"]
## Standard-Snap-Raster (Design-px der 960×540-Welt).
const DEFAULT_GRID := 10.0

## Frisch-Vorlagen fürs Hinzufügen (minimal schema-valide Zeilen).
const ELEMENT_DEFAULTS := {
	"ropes": {"rest": 90.0},
	"bubbles": {"r": 26.0},
	"cushions": {"dx": 1.0, "dy": 0.0, "power": 420.0, "range": 120.0, "half_w": 40.0},
	"fans":
	{
		"dx": 1.0,
		"dy": 0.0,
		"force": 260.0,
		"range": 260.0,
		"half_w": 70.0,
		"on": true,
		"toggleable": true,
	},
	"shooters": {"r": 90.0},
	"spikes": {"w": 90.0, "h": 18.0},
	"clouds": {"w": 120.0, "h": 70.0},
	"jars": {},
}


## Level-Dokument laden (kaputt/fehlend → {} — Muster GobnomData).
static func load_doc(path: String) -> Dictionary:
	return GobnomData.read_json(path)


## Dokument im Stil der eingecheckten Level-Datei speichern (1-Space-Indent).
static func save_doc(path: String, doc: Dictionary) -> bool:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not dir.begins_with("res:"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[gobnom_editor] nicht schreibbar: %s" % path)
		return false
	file.store_string(JSON.stringify(doc, " ") + "\n")
	file.close()
	return true


## Level-REFERENZ (kein Duplikat) aus dem Dokument: Mutationen landen im doc.
static func level_ref(doc: Dictionary, track: String, id: int) -> Dictionary:
	var levels: Variant = doc.get(track, [])
	if levels is Array:
		for level: Variant in levels:
			if level is Dictionary and int((level as Dictionary).get("id", 0)) == id:
				return level
	return {}


## Level-Ids eines Tracks (für den Level-Picker).
static func level_ids(doc: Dictionary, track: String) -> Array[int]:
	var ids: Array[int] = []
	var levels: Variant = doc.get(track, [])
	if levels is Array:
		for level: Variant in levels:
			if level is Dictionary:
				ids.append(int((level as Dictionary).get("id", 0)))
	return ids


## Position aufs Raster runden (grid <= 0 = aus) und in die Welt klemmen.
static func snap_pos(pos: Vector2, grid: float, world := Vector2(960.0, 540.0)) -> Vector2:
	var snapped_pos := pos
	if grid > 0.0:
		snapped_pos = Vector2(snappedf(pos.x, grid), snappedf(pos.y, grid))
	return Vector2(clampf(snapped_pos.x, 0.0, world.x), clampf(snapped_pos.y, 0.0, world.y))


## Alle greifbaren Griffe eines Levels: [{kind, index, pos}] — Elemente aus
## den Listen plus candy/mouth (index −1).
static func handles(level: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in POINT_KEYS:
		var point: Variant = level.get(key)
		if point is Dictionary:
			out.append({"kind": key, "index": -1, "pos": _pos_of(point)})
	for key in ELEMENT_KEYS:
		var rows: Variant = level.get(key, [])
		if not (rows is Array):
			continue
		for i in (rows as Array).size():
			var row: Variant = (rows as Array)[i]
			if row is Dictionary:
				out.append({"kind": key, "index": i, "pos": _pos_of(row)})
	return out


## Nächster Griff an pos (Welt-px) innerhalb max_dist, sonst {}.
static func pick_handle(level: Dictionary, pos: Vector2, max_dist := 24.0) -> Dictionary:
	var best := {}
	var best_dist := max_dist
	for handle in handles(level):
		var d := pos.distance_to(handle["pos"])
		if d <= best_dist:
			best_dist = d
			best = handle
	return best


## Element/Punkt verschieben (gesnappt + geklemmt). index −1 = candy/mouth.
static func move_element(
	level: Dictionary, kind: String, index: int, pos: Vector2, grid := DEFAULT_GRID
) -> bool:
	var row := _row_of(level, kind, index)
	if row.is_empty():
		return false
	var snapped_pos := snap_pos(pos, grid)
	row["x"] = snapped_pos.x
	row["y"] = snapped_pos.y
	# Schiebe-Anker: die Schiene wandert mit ihrem Anker (t bleibt).
	if kind == "ropes" and row.get("rail") is Dictionary:
		var rail: Dictionary = row["rail"]
		var delta := snapped_pos - Vector2(_num(rail.get("x1")), _num(rail.get("y1")))
		rail["x1"] = _num(rail.get("x1")) + delta.x
		rail["y1"] = _num(rail.get("y1")) + delta.y
		rail["x2"] = _num(rail.get("x2")) + delta.x
		rail["y2"] = _num(rail.get("y2")) + delta.y
	return true


## Numerische/boolesche Eigenschaft einer Zeile setzen (x/y über
## move_element, damit Snap/Klemme greifen).
static func set_property(
	level: Dictionary, kind: String, index: int, key: String, value: Variant
) -> bool:
	if key == "x" or key == "y":
		return false
	var row := _row_of(level, kind, index)
	if row.is_empty():
		return false
	row[key] = value
	return true


## Editierbare Eigenschaften der Auswahl (Kopie, ohne rail/owner-Container).
static func properties_of(level: Dictionary, kind: String, index: int) -> Dictionary:
	var row := _row_of(level, kind, index)
	var out := {}
	for key: Variant in row:
		if row[key] is float or row[key] is int or row[key] is bool:
			out[key] = row[key]
	return out


## Neues Element aus der Vorlage an pos; liefert den neuen Index (−1 = Fehler).
static func add_element(level: Dictionary, kind: String, pos: Vector2, grid := DEFAULT_GRID) -> int:
	if not ELEMENT_KEYS.has(kind):
		return -1
	if not (level.get(kind) is Array):
		level[kind] = []
	var row: Dictionary = (ELEMENT_DEFAULTS.get(kind, {}) as Dictionary).duplicate(true)
	var snapped_pos := snap_pos(pos, grid)
	row["x"] = snapped_pos.x
	row["y"] = snapped_pos.y
	(level[kind] as Array).append(row)
	return (level[kind] as Array).size() - 1


static func remove_element(level: Dictionary, kind: String, index: int) -> bool:
	if not ELEMENT_KEYS.has(kind) or not (level.get(kind) is Array):
		return false
	var rows: Array = level[kind]
	if index < 0 or index >= rows.size():
		return false
	rows.remove_at(index)
	return true


## Struktur-Checks EINES Levels (Editor-Spiegel der GobnomData-Regeln:
## candy/mouth, exakt 3 Gläser, Lösungs-Plan vorhanden, alles in der Welt).
static func structural_errors(level: Dictionary, balance: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not (level.get("candy") is Dictionary):
		errors.append("candy fehlt")
	if not (level.get("mouth") is Dictionary):
		errors.append("mouth fehlt")
	var jars: Array = level.get("jars", [])
	if jars.size() != 3:
		errors.append("genau 3 Nutella-Glaeser erwartet (sind %d)" % jars.size())
	if (level.get("solution", {}).get("actions", []) as Array).is_empty():
		errors.append("Loesungs-Plan fehlt (Loesbarkeits-Beweis!)")
	var world: Dictionary = balance.get("world", {})
	var w := _num(world.get("w"), 960.0)
	var h := _num(world.get("h"), 540.0)
	for key in ELEMENT_KEYS:
		for row: Variant in level.get(key, []):
			if not (row is Dictionary):
				continue
			var p := _pos_of(row)
			if p.x < 0.0 or p.x > w or p.y < 0.0 or p.y > h:
				errors.append("%s ausserhalb der Welt (%d,%d)" % [key, p.x, p.y])
	return errors


## Validierungs-Knopf: Struktur + BESTEHENDER Auto-Solver (Doc G §5
## „Skip-sicher getestet"). solver ist injizierbar (Tests mocken den Lauf);
## Default = GobnomSolver.run_solution. Liefert
## {ok, errors, solver: Report, path: [Vector2] (Candy-Flugbahn)}.
static func validate(level: Dictionary, balance: Dictionary, solver := Callable()) -> Dictionary:
	var errors := structural_errors(level, balance)
	var report := {}
	var path: Array[Vector2] = []
	if errors.is_empty():
		if solver.is_valid():
			report = solver.call(level, balance)
		else:
			report = GobnomSolver.run_solution(level, balance)
			path = solver_path(level, balance)
	return {
		"ok": errors.is_empty() and bool(report.get("won", false)),
		"errors": errors,
		"solver": report,
		"path": path,
	}


## Candy-Flugbahn des Lösungs-Plans (für die grün/rot-Pfad-Anzeige):
## derselbe Lauf wie GobnomSolver.run_solution, nur mit Positions-Protokoll.
static func solver_path(
	level: Dictionary, balance: Dictionary, seed_value := 1, every_ticks := 4
) -> Array[Vector2]:
	var state := GobnomLogic.new_run(level, balance, seed_value)
	var actions: Array = (level.get("solution", {}).get("actions", []) as Array).duplicate(true)
	actions.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return _num(a.get("t")) < _num(b.get("t"))
	)
	var timeout := _num(balance.get("limits", {}).get("solver_timeout_sec"), 40.0)
	var max_ticks := int(timeout * GobnomLogic.TPS)
	var next_action := 0
	var path: Array[Vector2] = [GobnomLogic.candy_pos(state)]
	while int(state["tick"]) < max_ticks and not GobnomLogic.is_over(state):
		var now := float(state["tick"]) / float(GobnomLogic.TPS)
		while next_action < actions.size() and _num(actions[next_action].get("t")) <= now:
			_execute_action(state, actions[next_action])
			next_action += 1
		GobnomLogic.step(state)
		if int(state["tick"]) % every_ticks == 0:
			path.append(GobnomLogic.candy_pos(state))
	path.append(GobnomLogic.candy_pos(state))
	return path


## Eine Plan-Aktion über die öffentliche Sim-API (Spiegel des Solvers).
static func _execute_action(state: Dictionary, action: Dictionary) -> void:
	var player := str(action.get("player", GobnomLogic.PLAYER_SOLO))
	match str(action.get("do", "")):
		"cut":
			GobnomLogic.cut_rope(state, int(action.get("rope", 0)), player)
		"pop":
			GobnomLogic.pop_bubble(state, int(action.get("bubble", 0)), player)
		"puff":
			GobnomLogic.puff_cushion(state, int(action.get("cushion", 0)), player)
		"fan":
			GobnomLogic.toggle_fan(state, int(action.get("fan", 0)), player)
		"slide":
			GobnomLogic.move_anchor(
				state, int(action.get("rope", 0)), _num(action.get("to")), player
			)


static func _row_of(level: Dictionary, kind: String, index: int) -> Dictionary:
	if POINT_KEYS.has(kind):
		var point: Variant = level.get(kind)
		return point if point is Dictionary else {}
	if not ELEMENT_KEYS.has(kind) or not (level.get(kind) is Array):
		return {}
	var rows: Array = level[kind]
	if index < 0 or index >= rows.size():
		return {}
	return rows[index] if rows[index] is Dictionary else {}


static func _pos_of(row: Dictionary) -> Vector2:
	return Vector2(_num(row.get("x")), _num(row.get("y")))


static func _num(value: Variant, fallback := 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback
