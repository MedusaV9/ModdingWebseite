extends "res://tools/capture/clip_driver.gd"
## Clip: Bergmassiv (WELT-1) — zwei Shots mit hartem Schnitt:
##   Teil A (0–7,4 s): Galopp über die HÄNGEBRÜCKE über die Schlucht
##     (reit_hoehe-Deckkurve trägt den Reiter, Blick nach -z).
##   Teil B (7,4–13 s): Ritt über das Gipfelplateau Richtung BERGSEE,
##     Gipfelkreuz + Panorama in der echten Reiter-Verfolgerkamera.

var region: Node3D


func _setup() -> void:
	duration = 13.0
	var packed: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	region = packed.instantiate()
	region.stunde_override = 9.2
	region.wetter_override = "sonne"
	region.receive_params({"spawn_zone": "bergmassiv"})
	add_child(region)
	schedule(0.2, func() -> void: _hud_aus())
	schedule(0.25, func() -> void: gooby_in_den_sattel(region.reiter.pferd))
	# Teil A: kurz vor der Brücke (a=[60,-778]) aufsetzen, Blick nach -z.
	schedule(
		0.3,
		func() -> void:
			region.reiter.springe_zu(Vector3(60.0, 0.0, -742.0), 0.0)
			region.reiter.galopp = true
			Input.action_press("ui_up")
	)
	# Teil B: hart aufs Plateau schneiden — Ritt ans Ufer des Bergsees
	# [128,-1036] (näher dran als im ersten Take, damit der See das Bild
	# füllt; Schilf-Ufer + Plateau-Schild ziehen vorbei).
	schedule(
		7.4,
		func() -> void:
			var start := Vector3(52.0, 0.0, -1002.0)
			var d := Vector2(128.0 - start.x, -1036.0 - start.z)
			region.reiter.springe_zu(start, atan2(-d.x, -d.y))
	)


func _hud_aus() -> void:
	for child in region.get_children():
		if child is CanvasLayer:
			child.visible = false
