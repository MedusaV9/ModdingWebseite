extends "res://tools/capture/clip_driver.gd"
## Clip: Freies Reiten in der offenen Ranch-Region (RW-1) — Galopp vom
## Hof hinaus in die Landschaft mit der echten Reiter-Verfolgerkamera.
## Sonniger Vormittag, HUD aus, sanfte Lenk-Impulse für eine geschwungene
## Linie an Weiden, Bach und Windrad vorbei.

var region: Node3D


func _setup() -> void:
	duration = 12.0
	var packed: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	region = packed.instantiate()
	region.stunde_override = 10.0
	region.wetter_override = "sonne"
	region.receive_params({"spawn_zone": "hof"})
	add_child(region)
	schedule(0.2, func() -> void: _hud_aus())
	schedule(
		0.6,
		func() -> void:
			region.reiter.galopp = true
			Input.action_press("ui_up")
	)
	schedule(3.6, func() -> void: Input.action_press("ui_left"))
	schedule(4.8, func() -> void: Input.action_release("ui_left"))
	schedule(7.8, func() -> void: Input.action_press("ui_right"))
	schedule(9.2, func() -> void: Input.action_release("ui_right"))


func _hud_aus() -> void:
	for child in region.get_children():
		if child is CanvasLayer:
			child.visible = false
