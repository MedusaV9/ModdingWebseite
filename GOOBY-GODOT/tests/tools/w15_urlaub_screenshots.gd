extends SceneTree
## W15/URLAUB-Screenshot-Tool (KEIN Test): rendert die drei Besuchs-
## Archetypen (Strand/Berge/Stadt) mit Gooby vor Ort als Review-Artefakte.
## Aufruf (echter Renderer):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/w15_urlaub_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W15_URLAUB"
const SETTLE := 45

const Vacation := preload("res://scripts/logic/vacation.gd")


## GameState-Double (Muster rest4_screenshots — läuft ohne Spiel-Autoloads).
class FakeGameState:
	extends RefCounted
	var daten: Dictionary = {}

	func _init(dest_id: String) -> void:
		var now := int(Time.get_unix_time_from_system() * 1000.0)
		var v := Vacation.default_slice()
		v["phase"] = Vacation.PHASE_AWAY
		v["destId"] = dest_id
		v["bookedAt"] = now - Vacation.MS_PER_DAY
		v["returnAt"] = now + 2 * Vacation.MS_PER_DAY
		v["pickupBy"] = now + 3 * Vacation.MS_PER_DAY
		daten = {
			"vacation": v,
			"economy": {"coins": 200},
			"inventory": {"items": {}, "food": {}},
			"gooby": {"stats": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "fun": 60.0}},
			"buffs": {"aktiv": []},
			"city": {},
		}

	func state() -> Dictionary:
		return daten

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = daten
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = daten
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	# Notbremse aus (Muster rw5/rw8): llvmpipe-FPS würde sonst mitten im
	# Lauf den "Qualität angepasst"-Banner über die Szene legen.
	var quality := root.get_node_or_null("/root/Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	await process_frame
	await _besuch("strand", "beach", "w15_urlaub_strand.png", true)
	await _besuch("berge", "meadowTrip", "w15_urlaub_berge.png", false)
	await _besuch("stadt", "bigCity", "w15_urlaub_stadt.png", false)
	print("W15-URLAUB-Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


func _besuch(archetyp: String, dest_id: String, datei: String, mit_tap: bool) -> void:
	var szene: PackedScene = load(str(UrlaubsBesuch.SZENEN[archetyp]))
	var ort: UrlaubsOrt = szene.instantiate()
	ort.game_state_override = FakeGameState.new(dest_id)
	ort.receive_params({"dest_id": dest_id})
	root.add_child(ort)
	await _settle(SETTLE)
	if mit_tap:
		# Muschel-Mini sichtbar machen (Tap-Spots über den 3D-Markern).
		ort._on_mini()
		await _settle(10)
	await _shot(datei)
	ort.queue_free()
	await process_frame


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s" % datei)
