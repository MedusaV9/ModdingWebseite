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
##   bed*                    → Bett (Schlafen/Nickerchen/Geschichte, REST-3)
##   kitchenFridge*          → Kuehlschrank (Füttern, EF-1/EVAL-1 D1)
##
## Einhängen (W2a-Hook-Request: W3d-home-requests.md):
##   InteractablesHost.attach_to(room)  # nach RoomBase._ready()

const KLO_IDS: Array[String] = ["toilet", "shower", "bathtub"]
## REST-4: Möbel-Ids, die die Radio-Oberfläche öffnen (Katalog W2a).
const RADIO_IDS: Array[String] = ["radio", "radioRetro", "speaker"]
## REST-4: Möbel-Ids, die das Postkarten-Archiv öffnen.
const POSTKARTEN_IDS: Array[String] = ["postkartenWand", "souvenirRegal"]
## W18/4 B6: Bewegungs-Toleranz eines Möbel-Taps (Design-px, ×f) — Release
## weiter weg vom Druckpunkt ist eine Zieh-Geste, kein Tap.
const TAP_TOLERANZ := 24.0

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
			_dock(Bett.new(), node)
		elif item_id.begins_with("kitchenFridge"):
			_dock(Kuehlschrank.new(), node)
		elif RADIO_IDS.has(item_id):
			# REST-4 (EVAL Rang 10): Radio-Möbel öffnen die Radio-Oberfläche.
			_dock(RadioGeraet.new(), node)
		elif POSTKARTEN_IDS.has(item_id):
			# REST-4 (EVAL Rang 15): Wand/Regal öffnen das Postkarten-Archiv.
			_dock(PostkartenWand.new(), node)
		elif item_id == "nougatschleuse":
			# W13/FOOD: Küchen-Nougatschleuse (Web-Easter-Egg §C6.4).
			_dock(Nougatschleuse.new(), node)
		elif Fernseher.TV_IDS.has(item_id):
			# W13C/GOBTY: TV-Möbel empfangen den GOB.TY-Sender (Doc H §6.2).
			_dock(Fernseher.new(), node)
		elif item_id == "windrad_deko":
			# W15/MARKT-Request: das Garten-Windrad dreht seinen Rotor.
			_dock(WindradRotor.new(), node)


## Tap-Zone über einem Möbel (Area3D + Box um die Möbel-AABB) — geteilter
## Baustein aller W3d-Interactables.
##
## W18/4 B6 („Radio-Sheet öffnet und schließt sofort“): feuert auf RELEASE
## statt Press — das ist die Godot-saubere Variante (BaseButton-Standard
## ACTION_MODE_BUTTON_RELEASE), weil sie das Doppel-Press-Problem an der
## WURZEL löst, ohne PanelSheet-Semantik anzufassen:
## `emulate_touch_from_mouse` liefert pro Klick ZWEI Press-Events (Maus +
## emulierter Touch). Der erste Press öffnete das Sheet, der zweite traf
## dessen frisch gespawnten Backdrop (schließt auf Press) — Sheet weg.
## Auf Release existiert beim Doppel-Event noch KEIN Sheet (es öffnet erst
## durch on_tap), und der `gedrueckt`-Merker dedupliziert das Maus/Touch-
## Paar: nur das ERSTE Release feuert. Die Bewegungs-Toleranz (24 ×f)
## filtert Zieh-Gesten über dem Möbel aus (kein Fehl-Tap beim Wischen).
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
	# Zustand als Dictionary: GDScript-Lambdas fangen Skalare per KOPIE —
	# nur Referenztypen tragen Zustand zwischen den Events.
	var zug := {"gedrueckt": false, "start": Vector2.ZERO}
	area.input_event.connect(
		func(
			_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int
		) -> void:
			if _tap_druck(event):
				zug["gedrueckt"] = true
				zug["start"] = _tap_position(event)
				return
			if not _tap_release(event) or not bool(zug["gedrueckt"]):
				return
			zug["gedrueckt"] = false
			var toleranz := TAP_TOLERANZ * UiScale.for_viewport(area.get_viewport())
			if _tap_position(event).distance_to(zug["start"]) <= toleranz:
				on_tap.call()
	)
	return area


## Press eines Tipp-Zeigers (nur Maus LINKS — Wheel-„Presses“ zählen nicht).
static func _tap_druck(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var maus := event as InputEventMouseButton
		return maus.pressed and maus.button_index == MOUSE_BUTTON_LEFT
	return false


static func _tap_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var maus := event as InputEventMouseButton
		return not maus.pressed and maus.button_index == MOUSE_BUTTON_LEFT
	return false


static func _tap_position(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return Vector2.ZERO


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
