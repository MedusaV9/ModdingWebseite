class_name InteractablesHost
extends Node3D
## Interactable-Host (W3d CONTENT): dockt Interactables an bestehende
## W2a-Möbel-Nodes an, OHNE W2a-Dateien zu ändern. Der Host lebt als eigenes
## Kind im Raum und re-scannt nach Bau-Commits (RoomBase.rebuild_furniture
## ersetzt alle FurnitureNodes — Signal `build_mode_toggled(false)`).
##
## Zuordnung Möbel → Interactable (Doc F §3.2 Bad-Suite + Geschichten-Stunde):
##   can_toggle_light        → LampenSchalter
##   toilet/shower/bathtub   → KloDusche
##   bathroomMirror          → Spiegel
##   bathroomSink            → Zahnputz
##   bed*                    → StoryTime (Geschichten-Stunde am Bett)
##
## Einhängen (W2a-Hook-Request: W3d-home-requests.md):
##   InteractablesHost.attach_to(room)  # nach RoomBase._ready()

const KLO_IDS: Array[String] = ["toilet", "shower", "bathtub"]

var _room: Node = null


## Host erzeugen und an einen RoomBase hängen (idempotent pro Raum).
static func attach_to(room: Node) -> InteractablesHost:
	var existing := room.get_node_or_null("InteractablesHost")
	if existing is InteractablesHost:
		return existing
	var host := InteractablesHost.new()
	host.name = "InteractablesHost"
	room.add_child(host)
	host.setup(room)
	return host


func setup(room: Node) -> void:
	_room = room
	if room.has_signal("build_mode_toggled"):
		room.build_mode_toggled.connect(_on_build_mode_toggled)
	rescan()


## Möbel-Nodes scannen und Interactables (neu) andocken.
func rescan() -> void:
	for child in get_children():
		child.queue_free()
	if _room == null:
		return
	for node in _furniture_nodes():
		var def: Dictionary = node.item_def
		var item_id := str(def.get("id", ""))
		if bool(def.get("can_toggle_light", false)):
			_dock(LampenSchalter.new(), node)
		elif KLO_IDS.has(item_id):
			_dock(KloDusche.new(), node)
		elif item_id == "bathroomMirror":
			_dock(Spiegel.new(), node)
		elif item_id == "bathroomSink":
			_dock(Zahnputz.new(), node)
		elif item_id.begins_with("bed"):
			_dock(StoryTime.new(), node)


## Tap-Zone über einem Möbel (Area3D + Box um die Möbel-AABB) — geteilter
## Baustein aller W3d-Interactables.
static func make_tap_area(furniture: Node3D, on_tap: Callable) -> Area3D:
	var area := Area3D.new()
	area.name = "TapArea"
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var top := 1.0
	if furniture.has_method("top_y"):
		top = maxf(0.6, float(furniture.top_y()))
	box.size = Vector3(0.9, top + 0.3, 0.9)
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
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
				on_tap.call()
	)
	return area


func room() -> Node:
	return _room


## GameState des Raums (RoomBase.game_state() — Test-Override inklusive).
func game_state() -> Object:
	if _room != null and _room.has_method("game_state"):
		return _room.game_state()
	return get_node_or_null("/root/GameState")


func _furniture_nodes() -> Array:
	var result: Array = []
	for mount_name in ["GridMount", "Blockers"]:
		var mount := _room.find_child(mount_name, true, false)
		if mount == null:
			continue
		for child in mount.get_children():
			if child is FurnitureNode:
				result.append(child)
	return result


func _dock(interactable: Node3D, furniture: Node3D) -> void:
	add_child(interactable)
	interactable.global_position = furniture.global_position
	if interactable.has_method("setup"):
		interactable.setup(self, furniture)


func _on_build_mode_toggled(active: bool) -> void:
	if not active:
		# Nach Bau-Commit sind alle FurnitureNodes neu — frisch andocken.
		rescan.call_deferred()
