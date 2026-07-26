extends "res://tools/capture/clip_driver.gd"
## Clip: Multiplayer-Besuch — eigener Gooby + Gast-Gooby („Flauschi“ mit
## Namensschild) im selben Wohnzimmer; der Gast läuft per POS-Relay-Feed
## durchs Bild (Muster aus tests/unit/screenshot_w3c.gd — ohne echten Server).

var social: Node
var scene: Node3D
var _peer_von := Vector3.ZERO
var _peer_nach := Vector3.ZERO
var _peer_t0 := 0.0
var _peer_t1 := 0.0
var _peer_laeuft := false


func _setup() -> void:
	duration = 10.0
	social = SocialServices.new()
	add_child(social)
	social.visit.peer_gooby_name = "Flauschi"
	social.visit.peer_room_id = "living"
	scene = VisitScene.new()
	scene.services_override = social
	scene.relay_enabled = false
	scene.receive_params({"snapshot": _snapshot_haus(), "role": VisitService.ROLE_GUEST})
	add_child(scene)
	schedule(1.0, _peer_erscheint)
	schedule(2.0, func() -> void: _peer_geht(Vector3(1.6, 0.0, 1.2), 2.6))
	schedule(5.2, func() -> void: _peer_geht(Vector3(-1.2, 0.0, 2.0), 2.4))
	schedule(3.0, func() -> void:
		if scene.my_gooby != null:
			scene.my_gooby.set_wander_enabled(false)
			scene.my_gooby.walk_to(Vector3(0.4, 0.0, 2.2)))
	schedule(6.4, func() -> void:
		if scene.my_gooby != null and scene.my_gooby.rig != null:
			scene.my_gooby.rig.play_clip("wave")
			scene.my_gooby.rig.set_emotion("happy"))


func _snapshot_haus() -> Dictionary:
	return {
		"v": 1,
		"goobyName": "Flauschi",
		"rooms":
		{
			"living":
			{
				"items":
				[
					{"uid": "s1", "item": "loungeSofa", "at": [4, 2], "rot": 0},
					{"uid": "t1", "item": "tableCoffee", "at": [5, 5], "rot": 0},
					{"uid": "c1", "item": "loungeChair", "at": [9, 3], "rot": 3},
					{"uid": "b1", "item": "bookcaseOpen", "at": [1, 1], "rot": 0},
					{"uid": "r1", "item": "rugRectangle", "at": [4, 4], "rot": 0},
				]
			},
			"kitchen": {"items": []},
			"bedroom": {"items": [{"uid": "b2", "item": "bedSingle", "at": [3, 2], "rot": 0}]},
		},
	}


func _peer_erscheint() -> void:
	if scene.my_gooby == null:
		return
	_peer_von = scene.my_gooby.global_position + Vector3(1.4, 0.0, -0.8)
	social.visit.peer_pos.emit(_peer_von, "idle", "living")


func _peer_geht(ziel: Vector3, dauer: float) -> void:
	_peer_nach = ziel
	_peer_t0 = t
	_peer_t1 = t + dauer
	_peer_laeuft = true


func _tick(_delta: float) -> void:
	if not _peer_laeuft:
		return
	var k := clampf((t - _peer_t0) / (_peer_t1 - _peer_t0), 0.0, 1.0)
	var pos := _peer_von.lerp(_peer_nach, k)
	social.visit.peer_pos.emit(pos, "walk" if k < 1.0 else "idle", "living")
	if k >= 1.0:
		_peer_von = _peer_nach
		_peer_laeuft = false
