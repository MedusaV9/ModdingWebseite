extends "res://tools/capture/clip_driver.gd"
## Basis der Stadt-Clips: mountet die echte CityScene (prozedurale Stadt,
## Verkehr, Fußgänger, ChaseCam) und fährt das Spielerauto per Pure-Pursuit
## am Straßengraphen entlang — Eingriff NUR über die öffentliche
## CarController-API (set_steer/set_brake), wie ein Spieler-Daumen.

var stunde := 14.0
## Leer = zuhause (mit Rückwärts-Ausparken); sonst Ort-Id.
var spawn := ""
## Ort-Id des Fahrziels.
var ziel_ort := "wochenmarkt"

var city: Node3D
var _wps: PackedVector3Array = PackedVector3Array()
var _wp_i := 0


func _setup() -> void:
	var packed: PackedScene = load("res://scenes/city/city_scene.tscn")
	city = packed.instantiate()
	city.stunde_override = stunde
	add_child(city)
	if not spawn.is_empty():
		city.receive_params({"spawn": spawn})


func _tick(_delta: float) -> void:
	if city == null or city.auto == null:
		return
	if city._ausparken != null:
		return
	if _wps.is_empty():
		_plan_route()
	_steer_along()


func _plan_route() -> void:
	var karte: Object = city.karte
	var graph: Object = city.graph
	var von: Vector2i = graph.naechste_strasse(karte.welt_zu_tile(city.auto.position))
	var eintrag: Dictionary = karte.ort(ziel_ort)
	var nach: Vector2i = graph.naechste_strasse(CityMap._tile_von(eintrag.get("strasse", [0, 0])))
	var pfad: Array = graph.pfad(von, nach)
	_wps = PackedVector3Array()
	for tile: Vector2i in pfad:
		_wps.append(karte.tile_zu_welt(tile))
	_wp_i = 0
	print("[city] Route: %d Wegpunkte %s → %s" % [_wps.size(), von, nach])


func _steer_along() -> void:
	if _wp_i >= _wps.size():
		city.auto.set_steer(0.0)
		city.auto.set_brake(true)
		return
	var auto: Node3D = city.auto
	var pos: Vector3 = auto.position
	# Wegpunkte abhaken, sobald sie erreicht/überfahren sind.
	while (
		_wp_i < _wps.size() and Vector2(_wps[_wp_i].x - pos.x, _wps[_wp_i].z - pos.z).length() < 9.0
	):
		_wp_i += 1
	if _wp_i >= _wps.size():
		return
	var ziel: Vector3 = _wps[_wp_i]
	var wunsch := atan2(ziel.x - pos.x, ziel.z - pos.z)
	var fehler := wrapf(wunsch - auto.heading, -PI, PI)
	# Positiver Steer senkt das Heading (§G3.1-a) → Vorzeichen drehen.
	auto.set_steer(clampf(-fehler * 1.8, -1.0, 1.0))
