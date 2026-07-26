class_name BuildCamera
extends Node
## Freie Baumodus-Kamera (FIX-3, User: „man kann sich nicht umherschwenken").
## Übernimmt im Baumodus die Kamera des HomeCameraRig und bietet:
## - Schwenken (Ein-Finger-Drag auf leerem Boden — BuildMode entscheidet per
##   Trefferprüfung, ob ein Möbel gegriffen oder geschwenkt wird),
## - Pinch-Zoom + Zwei-Finger-Drehen,
## - Draufsicht/Schrägsicht-Presets und 4×90°-Schnapp-Drehung,
## - sanftes Nachziehen und Klemmung des Pivots an die Raumgrenzen.
##
## Das Rig selbst wird währenddessen schlafen gelegt (set_process(false)) —
## nach dem Baumodus übernimmt es wieder und lerpt weich zurück zu Gooby.
## Die Mathe-Helfer sind static/pure (test_build_camera.gd).

## Schrägsicht = Blickwinkel des alten festen BUILD_OFFSET (0, 6.8, 3.2).
const PITCH_SCHRAEG := 1.1314  # atan2(6.8, 3.2) ≈ 64,8°
## Draufsicht: knapp unter 90°, damit look_at mit Vector3.UP stabil bleibt.
const PITCH_OBEN := 1.5184  # 87°
const GLAETTUNG := 9.0
const DIST_MIN := 3.5
## Maximal so weit raus wie die alte Fix-Kamera × Faktor (Stadt-Kulisse!).
const DIST_MAX_FAKTOR := 1.9
const ZOOM_SCHRITT := 1.12

var _rig: HomeCameraRig
var _room_size := Vector2(6, 5)
var _pivot := Vector3.ZERO
var _yaw := 0.0
var _pitch := PITCH_SCHRAEG
var _dist := 8.0
var _dist_max := 18.0
var _anzeige_pivot := Vector3.ZERO
var _aktiv := false


## Kamera-Offset (Pivot → Kamera) aus Gier/Neigung/Distanz — pure.
static func offset_fuer(yaw: float, pitch: float, dist: float) -> Vector3:
	var flach := cos(pitch) * dist
	return Vector3(sin(yaw) * flach, sin(pitch) * dist, cos(yaw) * flach)


## Pivot in die Raumgrenzen klemmen (XZ, y bleibt 0) — pure.
static func clamp_pivot(pivot: Vector3, room_size: Vector2) -> Vector3:
	return Vector3(clampf(pivot.x, 0.0, room_size.x), 0.0, clampf(pivot.z, 0.0, room_size.y))


## Nächster 90°-Schnapp-Winkel ab `yaw`, `richtung` = ±1 — pure.
static func schnapp_yaw(yaw: float, richtung: int) -> float:
	var viertel := roundf(yaw / (PI * 0.5))
	return (viertel + signf(richtung)) * PI * 0.5


func activate(rig: HomeCameraRig, room_size: Vector2) -> void:
	_rig = rig
	_room_size = room_size
	var aspekt := 16.0 / 9.0
	if is_inside_tree():
		var vp := get_viewport().get_visible_rect().size
		if vp.y > 0.0:
			aspekt = vp.x / vp.y
	_dist = HomeCameraRig.build_distanz(room_size, aspekt)
	_dist_max = maxf(_dist * DIST_MAX_FAKTOR, DIST_MIN + 1.0)
	_pivot = Vector3(room_size.x * 0.5, 0.0, room_size.y * 0.5)
	_anzeige_pivot = _pivot
	_yaw = 0.0
	_pitch = PITCH_SCHRAEG
	_aktiv = true
	_rig.set_process(false)
	set_process(true)


func deactivate() -> void:
	_aktiv = false
	set_process(false)
	if _rig != null:
		_rig.set_process(true)


func ist_aktiv() -> bool:
	return _aktiv


func pivot() -> Vector3:
	return _pivot


func yaw() -> float:
	return _yaw


func pitch() -> float:
	return _pitch


func distanz() -> float:
	return _dist


## Ein-Finger-Schwenk: „Boden festhalten" — beide Screen-Punkte auf die
## Bodenebene projizieren und den Pivot um die Differenz verschieben.
func pan_screen(von: Vector2, nach: Vector2) -> void:
	var a := _boden_punkt(von)
	var b := _boden_punkt(nach)
	if a == Vector3.INF or b == Vector3.INF:
		return
	_pivot = clamp_pivot(_pivot + (a - b), _room_size)


## Pinch: faktor > 1 = Finger auseinander = ranzoomen.
func zoom_um(faktor: float) -> void:
	if faktor <= 0.0001:
		return
	_dist = clampf(_dist / faktor, DIST_MIN, _dist_max)


func rotate_um(delta_yaw: float) -> void:
	_yaw = wrapf(_yaw + delta_yaw, -PI, PI)


func schnapp_90(richtung: int) -> void:
	_yaw = wrapf(schnapp_yaw(_yaw, richtung), -PI, PI)


func set_draufsicht(oben: bool) -> void:
	_pitch = PITCH_OBEN if oben else PITCH_SCHRAEG


func ist_draufsicht() -> bool:
	return _pitch > (PITCH_OBEN + PITCH_SCHRAEG) * 0.5


func _process(delta: float) -> void:
	if not _aktiv or _rig == null or _rig.camera == null:
		return
	var t := 1.0 - exp(-GLAETTUNG * delta)
	_anzeige_pivot = _anzeige_pivot.lerp(_pivot, t)
	var ziel := _anzeige_pivot + offset_fuer(_yaw, _pitch, _dist)
	var camera := _rig.camera
	camera.global_position = camera.global_position.lerp(ziel, t)
	camera.look_at(_anzeige_pivot + Vector3(0, 0.4, 0), Vector3.UP)


func _boden_punkt(screen_pos: Vector2) -> Vector3:
	if _rig == null or _rig.camera == null:
		return Vector3.INF
	var origin := _rig.camera.project_ray_origin(screen_pos)
	var richtung := _rig.camera.project_ray_normal(screen_pos)
	if absf(richtung.y) < 0.0001:
		return Vector3.INF
	var t := -origin.y / richtung.y
	if t < 0.0:
		return Vector3.INF
	return origin + richtung * t
