extends TestCase
## W21 Home/Pflege — STREICHEL-TAP-WACHE (Playtest-Befund flow_streicheln
## W21: ALLE 10 tipp_3d-Streichler buchten nicht, petsToday blieb stehen,
## obwohl jeder Tap exakt auf die projizierte Gooby-Position ging).
## Die Wache stellt die komplette Kette headless nach: Wohnzimmer +
## GoobyReactions, dann ein synthetischer Maus-Tap GENAU wie in der
## Playtest-Harness (Fenster-px über Input.parse_input_event) auf
## gooby.global_position + 0,35 m — das Physics-Picking muss die
## GoobyTapArea treffen und petsToday steigen. Zur Diagnose castet der
## Test den Picking-Strahl zusätzlich selbst und nennt den ERSTEN
## Treffer (wer den Tap schluckt, wenn es nicht die TapArea ist).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const WOHNZIMMER_SCENE := preload("res://scenes/home/wohnzimmer.tscn")

const NOW_MS := 1785448800000  # 2026-07-30 UTC
const LEITFORMAT_QUER := Vector2i(2868, 1320)
## Tap-Ziel wie flow_streicheln/GoobyReactions: Gooby-Ursprung + 0,35 m.
const TAP_OFFSET := Vector3(0.0, 0.35, 0.0)

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w21_streichel_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	return gs


## Tap-Synthese wie playtest_harness._tippe_canvas/_maus_knopf: Canvas-
## Koordinate in Fenster-px umrechnen und rohe Maus-Events parsen.
func _tippe_canvas(canvas_pos: Vector2) -> void:
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var px := canvas_pos * (Vector2(tree.root.size) / canvas)
	for gedrueckt: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = gedrueckt
		ev.position = px
		ev.global_position = px
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if gedrueckt else 0
		Input.parse_input_event(ev)
		await wait_frames(2)


func test_streichel_tap_bucht_petstoday() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	tree.root.size = LEITFORMAT_QUER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var gs := _fresh_gs()
	var room: RoomBase = WOHNZIMMER_SCENE.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(6)
	var reactions := GoobyReactions.attach_to(room)
	assert_ne(reactions, null, "GoobyReactions hängt am Raum")
	# _process muss die TapArea auf Gooby platziert haben.
	await wait_frames(4)
	var gooby := room.gooby() as Node3D
	assert_ne(gooby, null, "Gooby steht im Raum")
	if gooby != null and gooby.has_method("set_wander_enabled"):
		gooby.call("set_wander_enabled", false)
	await wait_frames(2)
	var kamera := tree.root.get_camera_3d()
	assert_ne(kamera, null, "aktive 3D-Kamera")
	if gooby == null or kamera == null or reactions == null:
		room.free()
		_gs_weg(gs)
		await _fenster_zurueck(fenster_vorher)
		return
	var welt := gooby.global_position + TAP_OFFSET
	var canvas_pos := kamera.unproject_position(welt)
	# Diagnose: wer fängt den Picking-Strahl zuerst? (Bei Fehlschlag steht
	# der Schlucker im Log — Basis für den eigentlichen Fix.)
	var abfrage := PhysicsRayQueryParameters3D.create(
		kamera.project_ray_origin(canvas_pos),
		kamera.project_ray_origin(canvas_pos) + kamera.project_ray_normal(canvas_pos) * 100.0
	)
	abfrage.collide_with_areas = true
	abfrage.collide_with_bodies = true
	var treffer := room.get_world_3d().direct_space_state.intersect_ray(abfrage)
	print(
		(
			"[W21-STREICHEL] canvas=%s gooby=%s erster_treffer=%s"
			% [canvas_pos, welt, treffer.get("collider", "NICHTS")]
		)
	)
	var vorher := int(gs.get_value("achievements.counters.petsToday", 0))
	await _tippe_canvas(canvas_pos)
	await wait_frames(6)
	var nach_tap := int(gs.get_value("achievements.counters.petsToday", 0))
	assert_true(
		nach_tap >= vorher + 1, "synthetischer Tap bucht petsToday (%d -> %d)" % [vorher, nach_tap]
	)
	# Referenz: die Buchung SELBST funktioniert (direkter handle_tap) —
	# trennt Input-Kette von Zähl-Logik.
	reactions.handle_tap()
	await wait_frames(2)
	var nach_direkt := int(gs.get_value("achievements.counters.petsToday", 0))
	assert_true(
		nach_direkt >= nach_tap + 1, "handle_tap bucht direkt (%d -> %d)" % [nach_tap, nach_direkt]
	)
	room.free()
	_gs_weg(gs)
	await _fenster_zurueck(fenster_vorher)


func _gs_weg(gs: Node) -> void:
	gs.get_parent().remove_child(gs)
	gs.free()


func _fenster_zurueck(fenster_vorher: Vector2i) -> void:
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)
