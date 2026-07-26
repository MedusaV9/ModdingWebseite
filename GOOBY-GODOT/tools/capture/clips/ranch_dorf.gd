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
