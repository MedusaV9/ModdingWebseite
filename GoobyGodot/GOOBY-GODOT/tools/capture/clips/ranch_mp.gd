extends "res://tools/capture/clip_driver.gd"
## Clip: Multiplayer-Ausritt (RW-6) — zwei Goobys galoppieren GEMEINSAM
## durchs Weidetal: der eigene Reiter plus ein echter RmpRemoteRider
## („Flauschi" mit Namensschild), gefüttert über die echte Pose-Pipeline
## (apply_pose → RmpInterp) — ohne Server, Muster aus visit.gd.

var region: Node3D
var peer: Node3D


func _setup() -> void:
	duration = 11.0
	var packed: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	region = packed.instantiate()
	region.stunde_override = 16.6
	region.wetter_override = "sonne"
	region.receive_params({"spawn_zone": "weidetal"})
	add_child(region)
	schedule(0.2, func() -> void: _hud_aus())
	schedule(0.25, func() -> void: gooby_in_den_sattel(region.reiter.pferd))
	schedule(
		0.5,
		func() -> void:
			peer = RmpRemoteRider.new()
			region.add_child(peer)
			peer.set_display_name("Flauschi")
			region.reiter.galopp = true
			Input.action_press("ui_up")
	)


## Peer-Pose je Frame: seitlich versetzt neben dem eigenen Reiter, Boden-
## Höhe aus dem Gelände (sonst schwebt er am Hang), Gangart 4 = Galopp.
func _tick(_delta: float) -> void:
	if peer == null or region == null or region.reiter == null:
		return
	var r: Node3D = region.reiter
	var rechts := r.global_transform.basis.x
	var pos := r.global_position + rechts * 3.4 + r.global_transform.basis.z * 1.4
	pos.y = RanchGelaende.reit_hoehe(pos.x, pos.z)
	peer.apply_pose({"p": [pos.x, pos.y, pos.z], "yaw": r.rotation.y, "gait": 4})


func _hud_aus() -> void:
	for child in region.get_children():
		if child is CanvasLayer:
			child.visible = false
