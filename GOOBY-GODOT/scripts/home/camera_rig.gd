class_name HomeCameraRig
extends Node3D
## Kamera-Rig der Raum-Szenen (W2a HOUSE + W4-P3 POLISH-6): sanftes
## Follow/Pan hinter Gooby (geclampt auf den Raum) + Schräg-Draufsicht im
## Baumodus (Doc D §2.1). Die Kamera-DISTANZ ist dynamisch: sie wird aus
## Raumgröße + Viewport-Aspekt berechnet, damit der Raum das Bild in
## Hochkant UND Quer ordentlich füllt (User-Wunsch „Handy-Platz nutzen“).
## Framing-Mathe ist pure/static (test_home_camera_framing.gd).

const FOLLOW_OFFSET := Vector3(0.0, 4.6, 4.1)
const BUILD_OFFSET := Vector3(0.0, 6.8, 3.2)
const SMOOTHING := 3.5
const FOV_Y := 45.0
## Hochkant: Mindest-Sichtbreite in m, damit Gooby Kontext behält.
const MIN_SICHTBREITE_HOCHKANT := 3.6
const DIST_MIN := 3.5
const DIST_MAX := 18.0

var camera: Camera3D
var follow_target: Node3D

var _bounds := Rect2(Vector2.ZERO, Vector2(6, 5))
var _room_size := Vector2(6, 5)
var _pivot := Vector3.ZERO
var _offset := FOLLOW_OFFSET
var _build_active := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV_Y
	camera.current = true
	add_child(camera)
	if is_inside_tree():
		get_viewport().size_changed.connect(_update_framing)
	_update_framing()
	_apply(1.0)


## Raumgrenzen in Weltmetern (XZ) — der Pivot bleibt im Raum.
func setup(room_world_size: Vector2) -> void:
	var margin := 0.8
	_bounds = Rect2(
		Vector2(margin, margin), (room_world_size - Vector2(margin, margin) * 2.0).max(Vector2.ZERO)
	)
	_room_size = room_world_size
	_pivot = Vector3(room_world_size.x * 0.5, 0.0, room_world_size.y * 0.5)
	_update_framing()
	_apply(1.0)


func set_build_mode(active: bool) -> void:
	_build_active = active
	_update_framing()


func is_build_mode() -> bool:
	return _build_active


## ── Framing-Mathe (pure, testbar) ───────────────────────────────────────────


## Sichtbreite in m auf der Pivot-Ebene bei Distanz d (horizontales FOV).
static func sichtbreite(distanz: float, aspekt: float, fov_y_grad := FOV_Y) -> float:
	return 2.0 * distanz * tan(deg_to_rad(fov_y_grad * 0.5)) * aspekt


## Follow-Distanz: Quer sieht den ganzen Raum + etwas Wand; Hochkant füllt
## die Bildhöhe mit der Raumtiefe und hält eine Mindest-Sichtbreite
## (Kamera-Pan deckt den Rest ab).
static func follow_distanz(room_size: Vector2, aspekt: float) -> float:
	var a := clampf(aspekt, 0.4, 2.6)
	var tan_y := tan(deg_to_rad(FOV_Y * 0.5))
	var pitch := atan2(FOLLOW_OFFSET.y, FOLLOW_OFFSET.z)
	if a >= 1.0:
		var ziel_breite := room_size.x * 1.3 + 1.0
		return clampf(ziel_breite * 0.5 / (tan_y * a), DIST_MIN, DIST_MAX)
	var ziel_hoehe := room_size.y * sin(pitch) + 2.2 * cos(pitch) + 1.0
	var d_hoehe := ziel_hoehe * 0.5 / tan_y
	var d_breite := MIN_SICHTBREITE_HOCHKANT * 0.5 / (tan_y * a)
	return clampf(maxf(d_hoehe, d_breite), DIST_MIN, DIST_MAX)


## Sichtbare Bodentiefe VOR dem Pivot (Richtung Kamera): bis hierhin reicht
## der untere Frustum-Rand auf der Bodenebene. Damit clampen wir den
## Follow-Pivot nach vorn — sonst kippt in Hochkant unter dem Raum ein
## leerer Hintergrund-Streifen ins Bild.
static func front_sichtweite(distanz: float, fov_y_grad := FOV_Y) -> float:
	var pitch := atan2(FOLLOW_OFFSET.y, FOLLOW_OFFSET.z)
	var bodenwinkel := pitch + deg_to_rad(fov_y_grad * 0.5)
	var cam_hoehe := distanz * sin(pitch)
	var cam_z := distanz * cos(pitch)
	return cam_z - cam_hoehe / tan(bodenwinkel)


## Baumodus-Distanz: das GANZE Grid muss in beiden Achsen sichtbar sein
## (Bauen braucht Überblick — auch in Hochkant).
static func build_distanz(room_size: Vector2, aspekt: float) -> float:
	var a := clampf(aspekt, 0.4, 2.6)
	var tan_y := tan(deg_to_rad(FOV_Y * 0.5))
	var pitch := atan2(BUILD_OFFSET.y, BUILD_OFFSET.z)
	var d_breite := (room_size.x + 1.2) * 0.5 / (tan_y * a)
	var d_tiefe := (room_size.y * sin(pitch) + 1.2) * 0.5 / tan_y
	return clampf(maxf(d_breite, d_tiefe), DIST_MIN, DIST_MAX)


## ── Anwendung ────────────────────────────────────────────────────────────────


func _update_framing() -> void:
	var aspekt := _viewport_aspekt()
	var basis := BUILD_OFFSET if _build_active else FOLLOW_OFFSET
	var distanz := (
		build_distanz(_room_size, aspekt) if _build_active else follow_distanz(_room_size, aspekt)
	)
	_offset = basis.normalized() * distanz


func _viewport_aspekt() -> float:
	if not is_inside_tree():
		return 16.0 / 9.0
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return 16.0 / 9.0
	return size.x / size.y


func _process(delta: float) -> void:
	var goal := _pivot
	if not _build_active and follow_target != null:
		goal = follow_target.global_position
	elif _build_active:
		goal = Vector3(
			_bounds.position.x + _bounds.size.x * 0.5,
			0.0,
			_bounds.position.y + _bounds.size.y * 0.5
		)
	goal.x = clampf(goal.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
	goal.z = clampf(goal.z, _bounds.position.y, _bounds.position.y + _bounds.size.y)
	if not _build_active:
		# Front-Clamp: nie so weit nach vorn folgen, dass unter der Raumkante
		# Leere sichtbar wird — mindestens bis zur Raummitte folgen wir aber.
		var z_limit := _room_size.y - front_sichtweite(_offset.length())
		goal.z = minf(goal.z, maxf(z_limit, _room_size.y * 0.5))
	goal.y = 0.0
	_pivot = _pivot.lerp(goal, 1.0 - exp(-SMOOTHING * delta))
	_apply(delta)


func _apply(delta: float) -> void:
	if camera == null:
		return
	var target_pos := _pivot + _offset
	camera.global_position = camera.global_position.lerp(target_pos, 1.0 - exp(-SMOOTHING * delta))
	camera.look_at(_pivot + Vector3(0, 0.5, 0))
