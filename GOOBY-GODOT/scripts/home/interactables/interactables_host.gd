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


## Gesten-Arbiter einer Tap-Zone (Wurzelfix PT1-B2 + PT4-B3, Welle H):
## - B2: `pointing/emulate_touch_from_mouse` liefert pro physischem Klick
##   Maus- UND Touch-Event (der Zwilling trägt DEVICE_ID_EMULATION) —
##   vorher feuerte `on_tap` doppelt und riss z. B. die Dusch-Routine in
##   eine Race (klo_dusche.gd: Fire 2 beendete, während Fire 1 im
##   `await walk_to` hing). Emulierte Events werden verworfen; zusätzlich
##   feuert pro Physik-Frame höchstens EIN Tap (Netz zweiter Ordnung,
##   Muster ranch_event_host._on_fang_input).
## - B3: Tap feuerte schon auf PRESS — Kamera-Pans, die auf einem
##   Interactable STARTEN, lösten es sofort aus. Jetzt feuert ein Tap erst
##   auf RELEASE und nur, wenn die Bewegung die Pan-Schwelle
##   (HomeCameraRig.PAN_DEADZONE_PX) nie erreicht hat — Tap und Boden-Pan
##   schließen sich damit exakt aus.
class TapGeste:
	extends RefCounted

	## Pseudo-Finger für Maus-Events (echte Touch-Indizes sind >= 0).
	const MAUS_FINGER := -1001

	var _armed := false
	var _finger := MAUS_FINGER
	var _press_pos := Vector2.ZERO
	var _letzter_feuer_frame := -1

	## true = Tap komplett (Press + Release unter der Schwelle) → feuern.
	## `frame` wird injiziert (Wrapper: Engine.get_physics_frames();
	## Tests zählen selbst — AGENTS-Regel „Zeit immer injizieren“).
	func verarbeite(event: InputEvent, frame: int) -> bool:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			# Synthetischer Zwilling (emulate_touch_from_mouse bzw.
			# emulate_mouse_from_touch) — die physische Familie genügt.
			return false
		if event is InputEventScreenTouch:
			return _touch_schritt(event as InputEventScreenTouch, frame)
		if event is InputEventMouseButton:
			return _maus_schritt(event as InputEventMouseButton, frame)
		if event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			_move(drag.index, drag.position)
		elif event is InputEventMouseMotion:
			_move(MAUS_FINGER, (event as InputEventMouseMotion).position)
		return false

	func _touch_schritt(touch: InputEventScreenTouch, frame: int) -> bool:
		if touch.pressed:
			_press(touch.index, touch.position)
			return false
		return _release(touch.index, touch.position, touch.canceled, frame)

	func _maus_schritt(maus: InputEventMouseButton, frame: int) -> bool:
		if maus.button_index != MOUSE_BUTTON_LEFT:
			return false
		if maus.pressed:
			_press(MAUS_FINGER, maus.position)
			return false
		return _release(MAUS_FINGER, maus.position, maus.canceled, frame)

	func _press(finger: int, pos: Vector2) -> void:
		if _armed and finger != _finger:
			# Zweiter Finger während einer laufenden Geste: der erste
			# behält Vorrang (Kinder-Doppelgriff bleibt EIN Tap; und
			# falls doch mal beide Ereignisfamilien echt ankommen,
			# frisst der Frame-Deckel unten das zweite Feuer).
			return
		_armed = true
		_finger = finger
		_press_pos = pos

	func _move(finger: int, pos: Vector2) -> void:
		if _armed and finger == _finger and HomeCameraRig.pan_gesture_ready(_press_pos, pos):
			# Bewegung auf/über der Pan-Schwelle: das ist ein Kamera-Pan.
			_armed = false

	func _release(finger: int, pos: Vector2, canceled: bool, frame: int) -> bool:
		if not _armed or finger != _finger:
			return false
		_armed = false
		if canceled:
			return false
		# Auch am Release messen: während eines aktiven Pans verschluckt
		# der Kamera-Rig die Drag-Events (set_input_as_handled) — die Zone
		# sieht dann nur Press+Release und muss den Weg selbst prüfen.
		if HomeCameraRig.pan_gesture_ready(_press_pos, pos):
			return false
		if frame == _letzter_feuer_frame:
			return false
		_letzter_feuer_frame = frame
		return true


## Tap-Zone über einem Möbel (Area3D + Box um die Möbel-AABB) — geteilter
## Baustein aller W3d-Interactables. `on_tap` feuert pro physischem Tap
## genau EINMAL, erst auf Release (s. TapGeste) und nie, während Gooby auf
## einem Skript-Lauf unterwegs ist (is_tap_blocked — Wiedereintritts-Sperre).
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
	connect_tap_gesture(area, on_tap)
	return area


## Gesten-Arbiter an eine BESTEHENDE Area3D hängen — für Tap-Flächen mit
## eigener Geometrie (z. B. die Tür in door_transition.gd, PT4-B3-Beleg).
static func connect_tap_gesture(area: Area3D, on_tap: Callable) -> void:
	var geste := TapGeste.new()
	area.input_event.connect(
		func(
			_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int
		) -> void:
			handle_tap_event(area, geste, event, int(Engine.get_physics_frames()), on_tap)
	)


## Testbarer Kern des Area-Handlers: Geste auswerten, Busy-Sperre prüfen,
## dann feuern. true = `on_tap` wurde gerufen.
static func handle_tap_event(
	area: Node, geste: TapGeste, event: InputEvent, frame: int, on_tap: Callable
) -> bool:
	if not geste.verarbeite(event, frame):
		return false
	if is_tap_blocked(area):
		return false
	on_tap.call()
	return true


## Wiedereintritts-Sperre (PT1-B2, zweite Verteidigungslinie — das
## „busy“-Flag des Hosts): Solange Gooby im KOMMANDIERTEN Anlauf einer
## Sequenz steckt, starten Taps keine neue Interactable-Sequenz und beenden
## keine anlaufende. Genau in diesem Fenster öffnete die Dusch-Race: ein
## echter Doppel-Tipp rief finish_shower(), während Fire 1 noch im
## `await walk_to` hing — die fortgesetzte Coroutine versteckte Gooby
## danach ohne Routine. Der Raum wird per Duck-Typing über den nächsten
## `gooby()`-Vorfahren gefunden (funktioniert für Host-Zonen UND Türen).
static func is_tap_blocked(area: Node) -> bool:
	var knoten := area
	while knoten != null:
		if knoten.has_method("gooby"):
			return _gooby_im_anlauf(knoten.call("gooby"))
		knoten = knoten.get_parent()
	return false


## Kommandierter Anlauf = Skript-Lauf MIT abgeschaltetem Wandern — so
## starten alle Interactable-Sequenzen (set_wander_enabled(false) +
## `await walk_to`, z. B. klo_dusche/kuehlschrank/bett/fernseher). Ambiente
## Skript-Läufe (Seelen-Gruß/-Absicht, Komm-her) lassen das Wandern an und
## sperren NICHT — sonst würden Tür-/Interactable-Taps grundlos
## verschluckt, während Gooby bloß zum Fenster schlendert.
static func _gooby_im_anlauf(gooby: Variant) -> bool:
	if not (gooby is Node):
		return false
	var node := gooby as Node
	if not node.has_method("is_scripted_walk") or not node.has_method("is_wander_enabled"):
		return false
	return bool(node.call("is_scripted_walk")) and not bool(node.call("is_wander_enabled"))


## Busy-Flag des Hosts von außen lesbar (Tests/Diagnose).
func is_tap_busy() -> bool:
	return is_tap_blocked(self)


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
