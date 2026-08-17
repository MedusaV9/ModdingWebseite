class_name MomentRegie
extends Node
## FEEL-AC — Momente inszenieren: bei STARKEN Emotionen (Schreck, Stolz,
## Begeisterung, Verliebtheit) kurz auf Gooby zoomen (FOV), eine Prise
## Zeitlupe und ein Farbakzent über den Post-FX-Puls. SPARSAM per Cooldown,
## damit es besonders bleibt. Reduced Motion: nur der (milde) Farbpuls —
## kein Zoom, keine Zeitlupe. Kamera und time_scale werden IMMER exakt
## restauriert (auch wenn der Node mittendrin stirbt).

## Mindestabstand zwischen zwei Inszenierungen.
const COOLDOWN_S := 45.0
const ZOOM_FAKTOR := 0.82
const ZOOM_IN_S := 0.22
const ZOOM_HALTEN_S := 0.55
const ZOOM_OUT_S := 0.45
const ZEITLUPE := 0.55
const ZEITLUPE_S := 0.4

## Tests: −1 = AppSettings fragen, 0 = aus, 1 = an.
var reduced_motion_override := -1

var _letzte_ms := -1_000_000_000
var _cam: Camera3D = null
var _fov_vorher := 0.0
var _zeitlupe_aktiv := false


## Regie fahren (true = lief). ziel = Gooby (nur für künftige Erweiterung
## der Blickführung — der Zoom bleibt beim FOV, das restauriert verlustfrei).
func inszeniere(_ziel: Node3D, farbe: Color) -> bool:
	var now := Time.get_ticks_msec()
	if now - _letzte_ms < int(COOLDOWN_S * 1000.0):
		return false
	_letzte_ms = now
	if is_inside_tree():
		PostFx.get_or_create(self).emotions_puls(farbe, 1.0)
	if _reduziert() or not is_inside_tree():
		return true
	_zoome()
	_zeitlupe()
	return true


func cooldown_uebrig_ms(now_ms: int) -> int:
	return maxi(0, int(COOLDOWN_S * 1000.0) - (now_ms - _letzte_ms))


## Tests: Cooldown zurücksetzen.
func reset_cooldown() -> void:
	_letzte_ms = -1_000_000_000


func _zoome() -> void:
	if _cam != null:
		return  # Zoom läuft noch — nicht stapeln.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam = cam
	_fov_vorher = cam.fov
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(cam, "fov", _fov_vorher * ZOOM_FAKTOR, ZOOM_IN_S)
	tween.tween_interval(ZOOM_HALTEN_S)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cam, "fov", _fov_vorher, ZOOM_OUT_S)
	tween.finished.connect(_zoom_fertig)


func _zoom_fertig() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.fov = _fov_vorher
	_cam = null


func _zeitlupe() -> void:
	if _zeitlupe_aktiv:
		return
	_zeitlupe_aktiv = true
	Engine.time_scale = ZEITLUPE
	# ignore_time_scale — sonst dauert die Zeitlupe sich selbst länger.
	var timer := get_tree().create_timer(ZEITLUPE_S, true, false, true)
	timer.timeout.connect(_zeitlupe_ende)


func _zeitlupe_ende() -> void:
	if _zeitlupe_aktiv:
		_zeitlupe_aktiv = false
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	_zeitlupe_ende()
	_zoom_fertig()


func _reduziert() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()
