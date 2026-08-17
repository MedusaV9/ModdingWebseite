class_name FurnitureShowcase
extends Control
## Die Vitrine der Möbel-Ausstellung (CONTENT-B, User-Wunsch D: „Möbel-
## AUSSTELLUNG in 3D (drehbare Modelle) … Grid-Felder-Bedarf sichtbar“).
##
## Enthält einen eigenen SubViewport mit eigener World3D — der Rest des
## Screens bleibt 2D-UI, und der Laden funktioniert überall, egal welche
## Szene sonst gemountet ist.
##
## Bedienung (Touch = Maus, `pointing/emulate_touch_from_mouse` ist an):
##   Ziehen  → drehen (Gieren frei, Nicken auf ±TILT_MAX begrenzt)
##   Pinch / Mausrad / Slider → zoomen (set_zoom)
##   Loslassen → Drehteller läuft sanft weiter (aus bei Reduced Motion)
##
## Unter dem Möbel liegt eine Feld-Platte in Footprint-Größe: ein Kästchen
## pro belegtem Grid-Feld. Damit ist „belegt X×Y Felder“ nicht nur ein Text,
## sondern direkt sichtbar.

signal rotated

## Blickwinkel-Grenzen: nie unter die Bodenplatte, nie steil von oben.
const TILT_MIN := -0.15
const TILT_MAX := 1.15
## Zoom als Vielfaches des automatisch berechneten Kamera-Abstands.
const ZOOM_MIN := 0.6
const ZOOM_MAX := 2.2
const ZOOM_DEFAULT := 1.0
const DRAG_SPEED := 0.008
const SPIN_PER_SEC := 0.35
const CELL := 0.5

## Startpose: leicht von schräg oben — zeigt Front UND Oberseite.
const START_YAW := 0.6
const START_TILT := 0.45

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _plate: Node3D
var _model: Node3D
var _halo: TextureRect
var _item: Dictionary = {}
var _variant := FurnitureVariants.DEFAULT_ID
var _yaw := START_YAW
var _tilt := START_TILT
var _zoom := ZOOM_DEFAULT
var _frame_distance := 2.0
var _dragging := false
var _spin := true


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_halo()
	_build_viewport()


## Zeigt ein Möbel (ShopCatalog-Def) in der gewünschten Farbvariante.
func show_item(item_def: Dictionary, variant_id := FurnitureVariants.DEFAULT_ID) -> void:
	_item = item_def
	_variant = variant_id
	_yaw = START_YAW
	_tilt = START_TILT
	_rebuild()


## Nur die Farbe wechseln — das Modell bleibt stehen (kein Reload-Flackern).
func set_variant(variant_id: String) -> void:
	_variant = variant_id
	if _model != null:
		FurnitureVariants.apply(_model, variant_id)


func set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_update_camera()


func get_zoom() -> float:
	return _zoom


## Drehteller an/aus (Reduced Motion + Screenshot-Determinismus).
func set_spin_enabled(enabled: bool) -> void:
	_spin = enabled


## Feste Pose setzen (Screenshots, Tests).
func set_pose(yaw: float, tilt: float) -> void:
	_yaw = yaw
	_tilt = clampf(tilt, TILT_MIN, TILT_MAX)
	_update_camera()


func get_yaw() -> float:
	return _yaw


## Das aktuell ausgestellte Modell (null, wenn nichts/kaputtes GLB).
func model() -> Node3D:
	return _model


func _process(delta: float) -> void:
	if not _spin or _dragging or _model == null:
		return
	_yaw += SPIN_PER_SEC * delta
	_update_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			set_zoom(_zoom - 0.12)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			set_zoom(_zoom + 0.12)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		accept_event()
	elif event is InputEventScreenTouch:
		_dragging = (event as InputEventScreenTouch).pressed
		accept_event()
	elif event is InputEventMagnifyGesture:
		# Pinch: >1 = aufziehen = näher ran (kleinerer Abstandsfaktor).
		set_zoom(_zoom / maxf(0.2, (event as InputEventMagnifyGesture).factor))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag((event as InputEventMouseMotion).relative)
		accept_event()
	elif event is InputEventScreenDrag:
		_drag((event as InputEventScreenDrag).relative)
		accept_event()


func _drag(relative: Vector2) -> void:
	_yaw -= relative.x * DRAG_SPEED
	_tilt = clampf(_tilt + relative.y * DRAG_SPEED, TILT_MIN, TILT_MAX)
	_update_camera()
	rotated.emit()


func _build_halo() -> void:
	# „Dezenter Glow“ ohne Renderer-Abhängigkeit: weicher Radialverlauf HINTER
	# dem Viewport. Postprocessing-Glow gibt es im Compatibility-Renderer
	# nicht zuverlässig, dieser Halo überall.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.94, 0.78, 0.75))
	gradient.set_color(1, Color(1.0, 0.94, 0.78, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_halo = TextureRect.new()
	_halo.texture = texture
	_halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_halo.stretch_mode = TextureRect.STRETCH_SCALE
	_halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_halo)


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_viewport.add_child(_camera)
	_add_lights()


func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.97, 0.92)
	key.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.light_color = Color(0.86, 0.92, 1.0)
	fill.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	_viewport.add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.88, 0.82)
	environment.ambient_light_energy = 0.85
	env.environment = environment
	_viewport.add_child(env)


func _rebuild() -> void:
	for child in _pivot.get_children():
		child.queue_free()
	_model = null
	_plate = null
	if _item.is_empty():
		return
	_plate = _build_plate(_item.get("footprint", Vector2i.ONE))
	_pivot.add_child(_plate)
	var node := FurnitureNode.create(_item, Vector2i.ZERO, 0, "showcase")
	if node != null:
		# create() setzt die Grid-Weltposition — in der Vitrine steht das
		# Stück mittig über der Platte.
		node.position = Vector3.ZERO
		_pivot.add_child(node)
		_model = node
		FurnitureVariants.apply(node, _variant)
	_frame_distance = _compute_distance()
	_update_camera()


## Bodenplatte: ein Kästchen pro Grid-Feld, damit „X×Y Felder“ sichtbar ist.
func _build_plate(footprint: Vector2i) -> Node3D:
	var plate := Node3D.new()
	var origin := Vector3(-footprint.x * CELL * 0.5, 0.0, -footprint.y * CELL * 0.5)
	for x in footprint.x:
		for y in footprint.y:
			var tile := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(CELL * 0.94, 0.012, CELL * 0.94)
			tile.mesh = mesh
			var material := StandardMaterial3D.new()
			var warm := (x + y) % 2 == 0
			# Deutlicher Kontrast: die Platte muss auch unter einem großen Möbel
			# als „so viele Felder“ ablesbar bleiben.
			material.albedo_color = (Color(0.99, 0.93, 0.84) if warm else Color(0.82, 0.68, 0.54))
			material.roughness = 0.95
			tile.material_override = material
			tile.position = origin + Vector3((x + 0.5) * CELL, -0.006, (y + 0.5) * CELL)
			plate.add_child(tile)
	return plate


## Kamera-Abstand so, dass Platte UND Möbelhöhe komplett ins Bild passen.
func _compute_distance() -> float:
	var fp: Vector2i = _item.get("footprint", Vector2i.ONE)
	var span := maxf(fp.x, fp.y) * CELL
	var height := 0.6
	if _model != null and _model.has_method("top_y"):
		height = maxf(height, _model.top_y())
	var radius := maxf(span * 0.75, height * 0.65)
	return maxf(1.1, radius / tan(deg_to_rad(_camera.fov * 0.5)) + radius * 0.5)


func _update_camera() -> void:
	if _camera == null:
		return
	var height := 0.6
	if _model != null and _model.has_method("top_y"):
		height = maxf(height, _model.top_y())
	var focus := Vector3(0.0, height * 0.5, 0.0)
	var distance := _frame_distance * _zoom
	var offset := Vector3(
		sin(_yaw) * cos(_tilt) * distance, sin(_tilt) * distance, cos(_yaw) * cos(_tilt) * distance
	)
	_camera.position = focus + offset
	_camera.look_at(focus, Vector3.UP)
