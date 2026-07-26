extends "res://tools/capture/clips/_mg_base.gd"
## Clip: GOB NOM (Cut-the-Rope-artig) — spielt die Kampagnen-Level 1→3 mit
## den offiziellen Level-Lösungen (getimte Seil-Schnitte als sichtbare
## Wischgesten) und springt nach jedem Sieg ins nächste Level.

const LEVELS_PATH := "res://scripts/minigames/games/gobnom/data/gobnom_levels.json"

var _level_id := 0
var _next_level_at := -1.0
var _cuts: Array[Dictionary] = []


func _setup() -> void:
	game_id = "gobnom"
	duration = 12.0
	seed_value = 7
	super._setup()


func _drive(_delta: float) -> void:
	var g := game()
	if g == null:
		return
	var phase := str(g.phase)
	if phase == "select":
		_starte_level(1)
		return
	if phase == "won" and _next_level_at < 0.0 and _level_id < 3:
		_next_level_at = t + 1.0
	if _next_level_at > 0.0 and t >= _next_level_at:
		_next_level_at = -1.0
		_starte_level(_level_id + 1)
		return
	if phase != "play" or g.state.is_empty():
		return
	# Geplante Schnitte ausführen (Positionen live berechnen).
	for cut: Dictionary in _cuts:
		if bool(cut["done"]) or t < float(cut["at"]):
			continue
		cut["done"] = true
		_schneide_seil(int(cut["rope"]))


func _starte_level(id: int) -> void:
	var g := game()
	_level_id = id
	g.open_level("campaign", id)
	_cuts.clear()
	var lösung := _loesung_von(id)
	var versatz := 0.0
	for aktion: Dictionary in lösung:
		if str(aktion.get("do", "")) != "cut":
			continue
		# Gleichzeitige Schnitte leicht staffeln (ein Zeiger-Index).
		var at := t + 0.35 + float(aktion["t"]) + versatz
		versatz += 0.22
		_cuts.append({"at": at, "rope": int(aktion["rope"]), "done": false})


func _loesung_von(id: int) -> Array:
	var text := FileAccess.get_file_as_string(LEVELS_PATH)
	var daten: Dictionary = JSON.parse_string(text)
	for lv: Dictionary in daten.get("campaign", []):
		if int(lv.get("id", -1)) == id:
			return lv.get("solution", {}).get("actions", [])
	return []


## Wisch quer über Seil `rope_id` (Mitte zwischen Anker und Bonbon).
func _schneide_seil(rope_id: int) -> void:
	var g := game()
	var candy: Vector2 = GobnomLogic.candy_pos(g.state)
	for rope: Dictionary in g.state["ropes"]:
		if int(rope["id"]) != rope_id or bool(rope["cut"]):
			continue
		var anker := Vector2(rope["anchor"])
		var mitte := (anker + candy) * 0.5
		var seil := (candy - anker).normalized()
		var quer := Vector2(-seil.y, seil.x)
		var a: Vector2 = to_window(g._to_screen(mitte - quer * 55.0))
		var b: Vector2 = to_window(g._to_screen(mitte + quer * 55.0))
		drag(a, b, 0.14)
		return
