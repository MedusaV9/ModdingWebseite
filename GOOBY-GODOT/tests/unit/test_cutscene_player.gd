extends TestCase
## FIX-4: CutscenePlayer — jede Pflicht-Cutscene läuft headless komplett
## durch (finished feuert, Player räumt sich auf) und ist überspringbar
## (finished(skipped=true), Endzustand identisch aufgeräumt).

const PlayerScript := preload("res://scripts/cutscenes/cutscene_player.gd")


## Minimaler Raum-Host: Cutscene-Ops degradieren ohne Gooby/Kamera zu No-ops.
class FakeRoom:
	extends Node3D


func test_alle_pflicht_cutscenes_laufen_headless_durch() -> void:
	for id: String in CutsceneLib.REQUIRED_IDS:
		var room := FakeRoom.new()
		tree.root.add_child(room)
		var player: CutscenePlayer = PlayerScript.play_in_room(room, null, id)
		assert_ne(player, null, "play_in_room lieferte null für %s" % id)
		if player == null:
			room.queue_free()
			continue
		player.time_scale = 60.0
		var result: Array = []
		player.finished.connect(func(skipped: bool) -> void: result.append(skipped))
		await player.spielen()
		assert_eq(result.size(), 1, "%s: finished muss genau einmal feuern." % id)
		if result.size() == 1:
			assert_false(bool(result[0]), "%s: Volllauf ist kein Skip." % id)
		room.queue_free()
		await wait_frames(2)


func test_cutscene_ist_ueberspringbar() -> void:
	var room := FakeRoom.new()
	tree.root.add_child(room)
	var player: CutscenePlayer = PlayerScript.play_in_room(room, null, "wake_morning")
	player.time_scale = 60.0
	var result: Array = []
	player.finished.connect(func(skipped: bool) -> void: result.append(skipped))
	player.ueberspringen()
	assert_true(player.is_skipped())
	await player.spielen()
	assert_eq(result.size(), 1)
	if result.size() == 1:
		assert_true(bool(result[0]), "Skip muss als skipped=true enden.")
	await wait_frames(2)
	assert_eq(
		room.get_children().filter(func(c: Node) -> bool: return c is CutscenePlayer).size(),
		0,
		"Player muss sich nach dem Skip selbst entfernen."
	)
	room.queue_free()
	await wait_frames(2)


func test_unbekannte_cutscene_gibt_null() -> void:
	var room := FakeRoom.new()
	tree.root.add_child(room)
	assert_eq(PlayerScript.play_in_room(room, null, "gibt_es_nicht"), null)
	room.queue_free()
	await wait_frames(1)
