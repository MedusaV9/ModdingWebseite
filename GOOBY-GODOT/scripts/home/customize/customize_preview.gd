class_name CustomizePreview
extends Control
## Live-3D-Vorschau des Gestalten-Screens (HAUS-CUSTOM) — eigenes
## SubViewport mit eigener World3D (Muster FurnitureShowcase, CONTENT-B).
## Zwei Modi:
##   show_interior(room_id, style) — Musterraum (Boden + zwei Wände) mit den
##     Wand-/Boden-Materialien des Raums; jede Auswahl wirkt SOFORT.
##   show_exterior(style)          — Haus + Grundstück (HouseExterior).
## Ziehen dreht die Kamera, Mausrad/Pinch zoomt; Screenshots setzen set_pose.

const TILT_MIN := 0.08
const TILT_MAX := 1.2
const ZOOM_MIN := 0.5
const ZOOM_MAX := 1.6
const DRAG_SPEED := 0.008
## Musterraum-Maße (Meter).
const RAUM := Vector2(5.0, 4.0)
const WAND_HOEHE := 2.5

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
## G7: laufende Weich-Blende (neuer Stil dippt kurz im Alpha statt hart).
var _blende: Tween
var _modus := ""
var _room_id := ""
var _style: Dictionary = {}
var _yaw := 0.5
var _tilt := 0.5
var _zoom := 1.0
var _fokus := Vector3.ZERO
var _abstand := 6.0
var _dragging := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_viewport()


## Musterraum mit den Flächen eines Raums zeigen.
func show_interior(room_id: String, style: Dictionary) -> void:
	_modus = "innen"
	_room_id = room_id
	_style = style
	_yaw = 0.5
	_tilt = 0.42
	_fokus = Vector3(RAUM.x * 0.5, 1.0, RAUM.y * 0.55)
	_abstand = 5.6
	_rebuild()


## Haus + Grundstück von außen zeigen.
func show_exterior(style: Dictionary) -> void:
	_modus = "aussen"
	_style = style
	_yaw = 0.35
	_tilt = 0.38
	_fokus = Vector3(HouseExterior.PLOT.x * 0.5, 1.4, HouseExterior.PLOT.y * 0.45)
	_abstand = 13.5
	_rebuild()


## Stil aktualisieren, Kamera bleibt stehen (Live-Anwendung beim Tippen).
## G7: ein WIRKLICH neuer Stil blendet weich ein (kurzer Alpha-Dip statt
## hartem Umspringen); unveränderte Refreshes (Resize) bleiben ruhig.
func update_style(style: Dictionary) -> void:
	var geaendert := style != _style
	_style = style
	_rebuild()
	if geaendert:
		_weich_blenden()


## G7: „Zufällig“-Spaß — kurzer Wackler der ganzen Vorschau. Reduced
## Motion: gar nichts (Gate sitzt zentral in UiMotion.wiggle).
func wackeln() -> void:
	UiMotion.wiggle(self, 2.5)


## Weicher Übergang beim Stil-Wechsel; RM springt sofort auf voll sichtbar.
func _weich_blenden() -> void:
	if not is_inside_tree() or UiMotion.reduced(self):
		modulate.a = 1.0
		return
	if _blende != null and _blende.is_valid():
		_blende.kill()
	modulate.a = 0.72
	_blende = create_tween()
	_blende.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_blende.tween_property(self, "modulate:a", 1.0, AcTokens.DUR_POP * 1.5)


func set_pose(yaw: float, tilt: float) -> void:
	_yaw = yaw
	_tilt = clampf(tilt, TILT_MIN, TILT_MAX)
	_update_camera()


func set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_update_camera()


func modus() -> String:
	return _modus


func raum_id() -> String:
	return _room_id


## Wurzel der aktuellen 3D-Szene (Tests schauen hinein).
func inhalt() -> Node3D:
	return _pivot


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			set_zoom(_zoom - 0.1)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			set_zoom(_zoom + 0.1)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		accept_event()
	elif event is InputEventScreenTouch:
		_dragging = (event as InputEventScreenTouch).pressed
		accept_event()
	elif event is InputEventMagnifyGesture:
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
	if _modus == "innen":
		# Im Musterraum nicht hinter die offene Seite drehen.
		_yaw = clampf(_yaw, -0.9, 0.9)
	_tilt = clampf(_tilt + relative.y * DRAG_SPEED, TILT_MIN, TILT_MAX)
	_update_camera()


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
	_pivot.name = "Inhalt"
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_viewport.add_child(_camera)
	var sonne := DirectionalLight3D.new()
	sonne.light_energy = 1.1
	sonne.light_color = Color(1.0, 0.97, 0.9)
	sonne.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	_viewport.add_child(sonne)
	var fuell := DirectionalLight3D.new()
	fuell.light_energy = 0.45
	fuell.light_color = Color(0.88, 0.93, 1.0)
	fuell.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	_viewport.add_child(fuell)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#CFE9F5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.93, 0.9, 0.86)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	_viewport.add_child(env)


func _rebuild() -> void:
	for kind in _pivot.get_children():
		_pivot.remove_child(kind)
		kind.queue_free()
	if _modus == "innen":
		_pivot.add_child(_musterraum())
	elif _modus == "aussen":
		_pivot.add_child(HouseExterior.build(_style))
	_update_camera()


## Musterraum: Boden, N- und W-Wand mit den Materialien des Raum-Styles,
## dazu Sockelleiste und ein Fensterrahmen für den Maßstab.
func _musterraum() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Musterraum"
	var raum: Dictionary = _style.get("raeume", {}).get(
		_room_id, CustomizeCatalog.raum_default(_room_id)
	)
	var boden := _mesh_box(
		Vector3(RAUM.x, 0.12, RAUM.y), HouseStyle.flaechen_material("boden", raum)
	)
	boden.name = "VorschauBoden"
	boden.position = Vector3(RAUM.x * 0.5, -0.06, RAUM.y * 0.5)
	wurzel.add_child(boden)
	var wand_material := HouseStyle.flaechen_material("wand", raum)
	var nord := _mesh_box(Vector3(RAUM.x, WAND_HOEHE, 0.1), wand_material)
	nord.name = "VorschauWandN"
	nord.position = Vector3(RAUM.x * 0.5, WAND_HOEHE * 0.5, -0.05)
	wurzel.add_child(nord)
	var west := _mesh_box(Vector3(0.1, WAND_HOEHE, RAUM.y), wand_material)
	west.name = "VorschauWandW"
	west.position = Vector3(-0.05, WAND_HOEHE * 0.5, RAUM.y * 0.5)
	wurzel.add_child(west)
	for leiste_def: Array in [
		[Vector3(RAUM.x, 0.09, 0.04), Vector3(RAUM.x * 0.5, 0.045, 0.02)],
		[Vector3(0.04, 0.09, RAUM.y), Vector3(0.02, 0.045, RAUM.y * 0.5)],
	]:
		var leiste := _mesh_box(leiste_def[0], CustomizeMaterials.flat("creme"))
		leiste.position = leiste_def[1]
		wurzel.add_child(leiste)
	var rahmen := _mesh_box(Vector3(1.3, 1.0, 0.06), CustomizeMaterials.flat("weiss"))
	rahmen.position = Vector3(RAUM.x * 0.62, 1.5, 0.03)
	wurzel.add_child(rahmen)
	var glas := _mesh_box(Vector3(1.1, 0.8, 0.04), CustomizeMaterials.flat("himmel", 0.3))
	glas.position = Vector3(RAUM.x * 0.62, 1.5, 0.06)
	wurzel.add_child(glas)
	return wurzel


func _mesh_box(groesse: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = groesse
	mesh.mesh = shape
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _update_camera() -> void:
	if _camera == null:
		return
	var abstand := _abstand * _zoom
	var offset := Vector3(
		sin(_yaw) * cos(_tilt) * abstand, sin(_tilt) * abstand, cos(_yaw) * cos(_tilt) * abstand
	)
	_camera.position = _fokus + offset
	_camera.look_at(_fokus, Vector3.UP)
