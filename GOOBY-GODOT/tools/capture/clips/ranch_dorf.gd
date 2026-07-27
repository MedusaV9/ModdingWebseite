extends "res://tools/capture/clip_driver.gd"
## Clip: Reit-Dorf Hufingen (RW-4) — Ankunft per Ritt: Galopp den Feldweg
## hinauf, vorbei am Ortsschild auf die Plaza mit den fünf Läden und den
## Gooby-NPCs. Echte Reiter-Verfolgerkamera, HUD aus.

var dorf: Node3D


func _setup() -> void:
	duration = 10.0
	var packed: PackedScene = load("res://scenes/ranch/dorf/hufingen.tscn")
	dorf = packed.instantiate()
	if dorf.has_method("receive_params"):
		dorf.receive_params({"via": "ritt"})
	add_child(dorf)
	schedule(0.2, func() -> void: _hud_aus())
	schedule(0.25, func() -> void: gooby_in_den_sattel(dorf.reiter.pferd))
	# Der Ritt-Spawn liegt ~174 m von der Plaza — in 10 s unerreichbar
	# (Erkenntnis aus der Einzelbild-Kontrolle: NPCs blieben unsichtbar).
	# Deshalb ~55 m vor die Plaza (600/540) teleportieren: Ankunft bei ~6 s,
	# dann im Schritt zwischen Brunnen, Läden und Gooby-NPCs.
	schedule(
		0.3,
		func() -> void:
			var start := Vector3(547.0, 0.0, 525.0)
			var d := Vector2(600.0 - start.x, 540.0 - start.z)
			dorf.reiter.springe_zu(start, atan2(-d.x, -d.y))
	)
	schedule(
		0.6,
		func() -> void:
			dorf.reiter.galopp = true
			Input.action_press("ui_up")
	)
	# Vor der Plaza vom Galopp in den Schritt fallen (Ankunfts-Gefühl).
	schedule(
		6.5,
		func() -> void:
			Input.action_release("ui_up")
			dorf.reiter.galopp = false
	)
	schedule(7.0, func() -> void: Input.action_press("ui_up"))


func _hud_aus() -> void:
	for child in dorf.get_children():
		if child is CanvasLayer:
			child.visible = false
