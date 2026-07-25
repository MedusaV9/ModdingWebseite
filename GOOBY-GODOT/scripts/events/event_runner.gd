class_name EventRunner
extends Node3D
## Event-Runner (W3d CONTENT, Doc F §4.2): setzt das AKTIVE Random-Event als
## Szene im Raum um — Gooby-Pose, Props, Tap-Auflösung, Nutella-Choice.
## `szene_setup`-Hooks: marienkaefer, kuehlschrank, glas_scherben,
## teller_scherben, nutella_nacht, sockensuche (alle 6 KOMPLETT SPIELBAR).
##
## Einhängen: EventRunner.attach_to(room) nach dem Raum-Aufbau (Hook-Request
## an W2a in W3d-home-requests.md). Der Runner liest das aktive Event aus dem
## `events`-Slice (RandomEventEngine) und baut die passende Szene.

signal event_resolved(event_id: String)

const FOOD_COLORS: Array[Color] = [
	Color("#FF9F5A"),
	Color("#8FD06C"),
	Color("#FFD166"),
	Color("#F4BFCD"),
	Color("#AFD8E8"),
]
const SHARD_COLOR := Color("#DDE3EA")
const SOCK_COLOR := Color("#FF7BA9")
const NUTELLA_COLOR := Color("#5A3A25")
## Rücklings-Pose: Kippwinkel + Anhebung, damit der Rücken auf dem Boden
## aufliegt (Rig-Origin liegt an den Füßen, sonst rotiert er unter den Boden).
const MARIENKAEFER_TILT_DEG := 105.0
const MARIENKAEFER_RIG_LIFT := 0.5

var _room: Node = null
var _gs: Object = null
var _defs: Array = []
var _def: Dictionary = {}
var _props: Array = []
var _remaining := 0
var _running := false
var _wiggle: Tween = null
var _rng := RandomNumberGenerator.new()


## Runner an einen Raum hängen; zeigt Fail-Bubble und startet das aktive
## Event (falls dessen Szene in diesen Raum passt).
static func attach_to(room: Node, defs: Array = []) -> EventRunner:
	var existing := room.get_node_or_null("EventRunner")
	if existing is EventRunner:
		return existing
	var runner := EventRunner.new()
	runner.name = "EventRunner"
	room.add_child(runner)
	runner.setup(room, defs)
	return runner


func setup(room: Node, defs: Array = []) -> void:
	_room = room
	_rng.randomize()
	_gs = room.game_state() if room.has_method("game_state") else null
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	_defs = defs if not defs.is_empty() else RandomEventEngine.defs_from_registry()
	if _gs == null:
		return
	var fail_text := RandomEventEngine.take_fail_notice(_gs)
	if not fail_text.is_empty():
		_say_raw(fail_text)
	var active := RandomEventEngine.active_of(_gs)
	if not active.is_empty():
		var def := RandomEventEngine.def_by_id(_defs, str(active.get("id", "")))
		if not def.is_empty():
			start(def)


## Event-Szene direkt starten (Screenshots/Tests; normal via setup()).
func start(def: Dictionary) -> void:
	if _running:
		return
	_running = true
	_def = def
	match str(def.get("szene_setup", "")):
		"marienkaefer":
			_setup_marienkaefer()
		"kuehlschrank":
			_setup_aufsammeln(int(def.get("props", 5)), FOOD_COLORS, "events.kuehlschrank.bubble")
		"glas_scherben":
			_setup_scherben(int(def.get("props", 3)), "events.glas.bubble")
		"teller_scherben":
			_setup_scherben(int(def.get("props", 3)), "events.teller.bubble")
		"nutella_nacht":
			_setup_nutella()
		"sockensuche":
			_setup_sockensuche(int(def.get("props", 3)))
		_:
			_running = false


func is_running() -> bool:
	return _running


# ── (1) Hingefallen-Marienkäfer ──────────────────────────────────────────────


## Gooby auf dem Rücken, zappelt (ragdoll-nah: Rig-Rotation + Wipp-Tween).
## Wichtig: der GoobyHome-Origin liegt an den FÜSSEN — deshalb das Rig kippen
## und anheben (sonst rotiert der Körper unter den Boden), Muster wie der
## Decken-Gag in gooby_home.gd. Tap-Hilfe → er rollt auf die Füße (+10 Spaß 5 h).
func _setup_marienkaefer() -> void:
	var gooby := _gooby()
	if gooby == null or not ("rig" in gooby) or gooby.rig == null:
		_running = false
		return
	gooby.set_wander_enabled(false)
	var rig: Node3D = gooby.rig
	rig.rotation.x = deg_to_rad(MARIENKAEFER_TILT_DEG)
	rig.position.y = MARIENKAEFER_RIG_LIFT
	if rig.has_method("set_emotion"):
		rig.set_emotion("dizzy")
	_wiggle = create_tween().set_loops()
	_wiggle.tween_property(rig, "rotation:z", 0.22, 0.28)
	_wiggle.tween_property(rig, "rotation:z", -0.22, 0.28)
	_say("events.marienkaefer.bubble")
	var helper := _make_prop(Color(1, 1, 1, 0.02), Vector3(1.0, 1.0, 1.0), _on_marienkaefer_help)
	helper.position = gooby.position
	add_child(helper)
	_props = [helper]


func _on_marienkaefer_help() -> void:
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		if _wiggle != null:
			_wiggle.kill()
			_wiggle = null
		var rig: Node3D = gooby.rig
		var up := create_tween()
		up.tween_property(rig, "rotation", Vector3.ZERO, 0.35)
		up.parallel().tween_property(rig, "position:y", 0.0, 0.35)
		gooby.play_clip("hop")
	_say("events.marienkaefer.danke")
	_resolve()


# ── (2) Kühlschrank / (3+4) Scherben / (6) Socken: Tap-Aufsammeln ────────────


func _setup_aufsammeln(count: int, colors: Array, bubble_key: String) -> void:
	_say(bubble_key)
	_set_gooby_emotion("sad")
	_scatter_props(
		count,
		func(i: int) -> Node3D:
			return _make_prop(
				colors[i % colors.size()], Vector3(0.28, 0.28, 0.28), _on_prop_collected
			)
	)


func _setup_scherben(count: int, bubble_key: String) -> void:
	_say(bubble_key)
	_set_gooby_emotion("scared")
	_scatter_props(
		count,
		func(_i: int) -> Node3D:
			return _make_prop(SHARD_COLOR, Vector3(0.3, 0.06, 0.3), _on_prop_collected)
	)


func _setup_sockensuche(count: int) -> void:
	_say("events.sockensuche.bubble")
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(true)
	_scatter_props(
		count,
		func(_i: int) -> Node3D:
			return _make_prop(SOCK_COLOR, Vector3(0.22, 0.1, 0.34), _on_prop_collected)
	)


func _scatter_props(count: int, factory: Callable) -> void:
	_props = []
	_remaining = count
	var cells := _free_cells()
	for i in count:
		var prop: Node3D = factory.call(i)
		if cells.is_empty():
			prop.position = Vector3(1.0 + i * 0.7, 0.15, 1.0)
		else:
			var cell: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
			cells.erase(cell)
			prop.position = GridData.world_center(cell, Vector2i.ONE, 0) + Vector3(0.0, 0.15, 0.0)
		add_child(prop)
		_props.append(prop)


func _on_prop_collected() -> void:
	_remaining -= 1
	if _remaining <= 0:
		match str(_def.get("szene_setup", "")):
			"sockensuche":
				_say("events.sockensuche.danke")
			"kuehlschrank":
				_say("events.kuehlschrank.danke")
			_:
				_say("events.scherben.danke")
		_set_gooby_emotion("happy")
		_resolve()


# ── (5) Nutella-Nacht ────────────────────────────────────────────────────────


## Küche nachts: Gooby am Tisch mit Nutella-Glas, „uhhh UPPPS“, Choice:
## schlafen schicken (−5 Freude +10 Energie) / weitermachen (+10 Freude
## −5 Energie) — danach räumt er auf + tapst zurück ins Bett.
func _setup_nutella() -> void:
	var gooby := _gooby()
	var jar := _make_prop(NUTELLA_COLOR, Vector3(0.22, 0.3, 0.22), func() -> void: pass)
	if gooby != null:
		gooby.set_wander_enabled(false)
		gooby.play_clip("sit")
		if "rig" in gooby and gooby.rig != null:
			gooby.rig.set_emotion("scared")
		jar.position = gooby.position + Vector3(0.45, 0.15, 0.0)
	add_child(jar)
	_props = [jar]
	_say("events.nutella.upps")
	_show_nutella_choice()


func _show_nutella_choice() -> void:
	var choice := PanelContainer.new()
	choice.name = "NutellaChoice"
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	choice.theme = ThemeService.theme()
	choice.theme_type_variation = &"AcCard"
	choice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	choice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	choice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choice.position.y -= 40.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	choice.add_child(box)
	var bed := SquishButton.new()
	bed.theme_type_variation = &"BtnTeal"
	bed.text = I18nService.t("events.nutella.ab_ins_bett")
	bed.pressed.connect(_on_nutella_choice.bind(true, choice))
	box.add_child(bed)
	var keep := SquishButton.new()
	keep.theme_type_variation = &"BtnPink"
	keep.text = I18nService.t("events.nutella.weitermachen")
	keep.pressed.connect(_on_nutella_choice.bind(false, choice))
	box.add_child(keep)
	_ui_layer().add_child(choice)


func _on_nutella_choice(to_bed: bool, choice: Control) -> void:
	choice.queue_free()
	_apply_stat_delta("fun", -5.0 if to_bed else 10.0)
	_apply_stat_delta("energy", 10.0 if to_bed else -5.0)
	var gooby := _gooby()
	if to_bed:
		_say("events.nutella.murmel")
		_set_gooby_emotion("sad")
	else:
		_say("events.nutella.strahlen")
		_set_gooby_emotion("ecstatic")
	await _sleep_s(2.0)
	# Aufräumen + zurück ins Bett tapsen (M1: kurzer Walk + sleep-Clip).
	_say("events.nutella.aufraeumen")
	_clear_props()
	if gooby != null and is_instance_valid(gooby):
		await gooby.walk_to(gooby.position + Vector3(1.5, 0.0, 1.0), 4.0)
		gooby.play_clip("sleep")
	_resolve()


# ── gemeinsame Helfer ────────────────────────────────────────────────────────


func _resolve() -> void:
	var event_id := str(_def.get("id", ""))
	if _gs != null:
		RandomEventEngine.resolve_active(_gs, _defs, _now_ms())
	_clear_props()
	var gooby := _gooby()
	if gooby != null and str(_def.get("szene_setup", "")) != "nutella_nacht":
		gooby.set_wander_enabled(true)
	_running = false
	_def = {}
	event_resolved.emit(event_id)


func _make_prop(color: Color, box_size: Vector3, on_tap: Callable) -> Node3D:
	var prop := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		# Sonst rendert der „unsichtbare“ Tap-Helfer als opaker Klotz.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	prop.add_child(mesh)
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = box_size * 2.0
	shape.shape = col_box
	area.add_child(shape)
	area.input_event.connect(
		func(
			_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int
		) -> void:
			var pressed: bool = (
				(event is InputEventMouseButton and event.pressed)
				or (event is InputEventScreenTouch and event.pressed)
			)
			if pressed:
				prop.queue_free()
				_props.erase(prop)
				on_tap.call()
	)
	prop.add_child(area)
	return prop


func _clear_props() -> void:
	for prop: Node3D in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props = []


func _apply_stat_delta(stat: String, delta: float) -> void:
	if _gs == null:
		return
	_gs.update(
		func(state: Dictionary) -> void:
			var stats: Variant = state.get("gooby", {}).get("stats")
			if stats is Dictionary:
				stats[stat] = clampf(float(stats.get(stat, 50.0)) + delta, 0.0, 100.0)
	)


func _free_cells() -> Array:
	if _room == null or not ("grid" in _room) or _room.grid == null:
		return []
	return _room.grid.free_cells()


func _gooby() -> Node:
	if _room != null and _room.has_method("gooby"):
		return _room.gooby()
	return null


func _set_gooby_emotion(emotion: String) -> void:
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		gooby.rig.set_emotion(emotion)


func _say(key: String) -> void:
	_say_raw(I18nService.t(key))


func _say_raw(text: String) -> void:
	if _room != null and _room.has_method("say"):
		_room.say(text)


func _ui_layer() -> CanvasLayer:
	var existing := get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	add_child(layer)
	return layer


func _sleep_s(seconds: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
