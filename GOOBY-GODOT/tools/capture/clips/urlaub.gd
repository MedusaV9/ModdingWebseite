extends "res://tools/capture/clip_driver.gd"
## Clip: Urlaubs-Besuch (W15/URLAUB) — Strand-Archetyp: Meer mit dem echten
## Wasser-Shader, Liegestuhl/Sonnenschirm/Sandburg, 2 Urlauber-Statisten mit
## Idle-Hop, Gooby bester Laune mittendrin. Wir streicheln (Tanz + Erzähl-
## Blase), sammeln die 5 Muschel-Tap-Spots ein (Abschluss: Toast + Freuden-
## tanz) und lösen den Souvenir-Spot ein — wie ein besuchender Spieler.
## Kamera: sanfter Push-in über die ORT-Kamera selbst (nicht cine_camera!)
## — die Tap-Spot-Knöpfe werden über `_kamera.unproject_position` platziert
## und müssen zur renderenden Kamera passen. Der Push-in endet deshalb VOR
## dem Aufbau der Tap-Ebene.

const TAP_SPOTS := 5

var ort: Node3D


func _setup() -> void:
	duration = 12.0
	var packed: PackedScene = load("res://scenes/city/urlaub/urlaub_strand.tscn")
	ort = packed.instantiate()
	ort.receive_params({"dest_id": "beach"})
	add_child(ort)
	# G5/P27: „Raus“-Knopf ist Navigation, kein Motiv (Aufnahme-Regie).
	schedule(0.2, func() -> void: ort._zurueck.visible = false)
	schedule(0.3, _kamerafahrt)
	schedule(1.6, func() -> void: ort._on_streicheln())
	schedule(4.6, func() -> void: ort._on_mini())
	for i in TAP_SPOTS:
		schedule(5.6 + 0.7 * i, func() -> void: ort._on_tap(i))
	# Souvenir zum Schluss (einmal täglich — frischer Save löst immer ein).
	schedule(10.0, func() -> void: ort._on_souvenir())


## Push-in auf der Ort-Kamera (Movie-Zeit-Tween), endet vor der Tap-Ebene.
func _kamerafahrt() -> void:
	var kamera: Camera3D = ort._kamera
	if kamera == null:
		return
	kamera.position = Vector3(0.0, 3.1, 6.6)
	kamera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	var tween := create_tween().set_parallel()
	(
		tween
		. tween_property(kamera, "position", Vector3(0.0, 2.2, 4.6), 3.6)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween
		. tween_property(kamera, "rotation_degrees", Vector3(-13.0, 0.0, 0.0), 3.6)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
