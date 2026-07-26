class_name GoobyPreview
extends Control
## ECHTE 3D-Vorschau für den Char-Editor (FIX2, User: „Mach den Char Editor
## wirklich sein 3D Model zeigen, auch mit rotieren etc."): SubViewport mit
## dem W1b-GoobyRig auf einem Pastell-Podest, warmes Dreipunkt-Licht,
## Drehen per Drag (Maus/Touch), Zoom per Mausrad/Pinch, sanfte Auto-
## Drehung im Leerlauf. Ersetzt die alte 2D-Vektor-Zeichnung.
##
## API-VERTRAG (unverändert seit Handoff W1c):
##     func set_morphs(morphs: Dictionary) -> void
##     # morphs = {eyes_apart:-1..1, eye_scale:0.7..1.4,
##     #           ear_len:0.7..1.4, chubby:0..1}
##
## eyes_apart/eye_scale/ear_len gehen live auf die Rig-Shapekeys
## (GoobyRig.SAVE_MORPH_MAP); chubby ist Weight-Tier ohne Shapekey und
## wird hier als sanfter Pausbacken-Puff (XZ-Skalierung) visualisiert.
## Farbwerte sind CHARAKTER-Kunstfarben (Stil-Anker GODOT-PLAN §7.1).

const PODEST_FARBE := Color("#BFE3CD")
const PODEST_RAND := Color("#A8D4BA")
const SCHATTEN := Color(0.24, 0.18, 0.14, 0.35)

const CAM_FOV := 32.0
const CAM_HOEHE := 0.9
const CAM_ZIEL := Vector3(0.0, 0.63, 0.0)
const DIST_DEFAULT := 2.55
const DIST_MIN := 1.6
const DIST_MAX := 4.0
const ZOOM_STEP := 0.22
const DRAG_RAD_PRO_PX := 0.011
## Leerlauf-Drehung: langsam und gemütlich; pausiert nach Drag kurz.
const AUTO_SPIN_RAD_S := 0.35
const AUTO_SPIN_PAUSE_S := 2.2
const CHUBBY_PUFF := 0.16

var rig: GoobyRig

var _morphs: Dictionary = OnboardingLogic.EDITOR_DEFAULTS.duplicate()
var _stage: Node3D
var _camera: Camera3D
var _dist := DIST_DEFAULT
var _dist_ziel := DIST_DEFAULT
var _spin_pause := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_viewport()
	_apply_morphs()


func set_morphs(morphs: Dictionary) -> void:
	for key: String in morphs:
		_morphs[key] = morphs[key]
	_apply_morphs()


func get_morphs() -> Dictionary:
	return _morphs.duplicate()


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.name = "PreviewContainer"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	# Bühne (dreht sich): Rig + Podest + Schattenfleck.
	_stage = Node3D.new()
	_stage.name = "Stage"
	viewport.add_child(_stage)
	rig = GoobyRig.new()
	rig.name = "PreviewRig"
	_stage.add_child(rig)
	rig.set_emotion("happy")
	_stage.add_child(_make_podest())
	_stage.add_child(_make_schatten())
	# Kamera + Licht bleiben fix; nur die Bühne rotiert.
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = CAM_FOV
	_camera.environment = _make_environment()
	viewport.add_child(_camera)
	_update_camera()
	for licht in _make_lights():
		viewport.add_child(licht)


## Warmes Dreipunkt-Licht (Key vorne-oben, kühles Fill, Rim von hinten) —
## ohne Schatten-Maps (Blob-Schatten übernimmt, wie im Raum).
func _make_lights() -> Array[DirectionalLight3D]:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(1.0, 0.96, 0.88)
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-38.0, 32.0, 0.0)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.82, 0.88, 1.0)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-16.0, -58.0, 0.0)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(1.0, 0.92, 0.98)
	rim.light_energy = 0.5
	rim.rotation_degrees = Vector3(-24.0, 168.0, 0.0)
	return [key, fill, rim]


func _make_environment() -> Environment:
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.92)
	env.ambient_light_energy = 0.55
	return env


## Pastell-Podest wie eine kleine AC-Präsentierbühne.
func _make_podest() -> MeshInstance3D:
	var podest := MeshInstance3D.new()
	podest.name = "Podest"
	var zylinder := CylinderMesh.new()
	zylinder.top_radius = 0.5
	zylinder.bottom_radius = 0.56
	zylinder.height = 0.09
	zylinder.radial_segments = 48
	podest.mesh = zylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PODEST_FARBE
	mat.roughness = 0.9
	podest.material_override = mat
	podest.position = Vector3(0.0, -0.045, 0.0)
	var rand := MeshInstance3D.new()
	rand.name = "PodestRand"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.58
	rand.mesh = torus
	var rand_mat := StandardMaterial3D.new()
	rand_mat.albedo_color = PODEST_RAND
	rand_mat.roughness = 0.9
	rand.material_override = rand_mat
	rand.position = Vector3(0.0, 0.0, 0.0)
	rand.scale = Vector3(1.0, 0.55, 1.0)
	podest.add_child(rand)
	return podest


## Weicher Schattenfleck unter Gooby (radialer Verlauf, kein Shadow-Mapping).
func _make_schatten() -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.78, 0.78)
	quad.orientation = PlaneMesh.FACE_Y
	blob.mesh = quad
	var gradient := Gradient.new()
	gradient.set_color(0, SCHATTEN)
	gradient.set_color(1, Color(SCHATTEN.r, SCHATTEN.g, SCHATTEN.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	blob.material_override = mat
	blob.position = Vector3(0.0, 0.012, 0.0)
	return blob


func _apply_morphs() -> void:
	if rig == null:
		return
	for save_key: String in GoobyRig.SAVE_MORPH_MAP:
		var neutral := 0.0 if save_key == "eyes_apart" else 1.0
		rig.set_morph(GoobyRig.SAVE_MORPH_MAP[save_key], float(_morphs.get(save_key, neutral)))
	# chubby hat (noch) keinen Shapekey (Weight-Tier M2) — sanfter Puff in
	# XZ, nur auf der Vorschau-Buehne, damit der Regler sichtbar wirkt.
	var chubby := clampf(float(_morphs.get("chubby", 0.0)), 0.0, 1.0)
	rig.scale = Vector3(1.0 + CHUBBY_PUFF * chubby, 1.0 - 0.03 * chubby, 1.0 + CHUBBY_PUFF * chubby)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_drehen((event as InputEventScreenDrag).relative.x)
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drehen(motion.relative.x)
			accept_event()
	elif event is InputEventMouseButton:
		var klick := event as InputEventMouseButton
		if not klick.pressed:
			return
		if klick.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoomen(-ZOOM_STEP)
			accept_event()
		elif klick.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoomen(ZOOM_STEP)
			accept_event()
	elif event is InputEventMagnifyGesture:
		_zoomen((1.0 - (event as InputEventMagnifyGesture).factor) * 1.4)
		accept_event()


func _drehen(pixel_dx: float) -> void:
	if _stage == null:
		return
	_stage.rotation.y += pixel_dx * DRAG_RAD_PRO_PX
	_spin_pause = AUTO_SPIN_PAUSE_S


func _zoomen(delta_dist: float) -> void:
	_dist_ziel = clampf(_dist_ziel + delta_dist, DIST_MIN, DIST_MAX)


func _process(delta: float) -> void:
	if _stage == null:
		return
	if _spin_pause > 0.0:
		_spin_pause -= delta
	else:
		_stage.rotation.y = wrapf(_stage.rotation.y + AUTO_SPIN_RAD_S * delta, -TAU, TAU)
	if not is_equal_approx(_dist, _dist_ziel):
		_dist = lerpf(_dist, _dist_ziel, minf(8.0 * delta, 1.0))
		_update_camera()


func _update_camera() -> void:
	_camera.position = CAM_ZIEL + Vector3(0.0, CAM_HOEHE - CAM_ZIEL.y, _dist)
	_camera.look_at_from_position(_camera.position, CAM_ZIEL, Vector3.UP)
