extends SceneTree
## SEELE-2 Diagnose (KEIN Test — kein test_-Präfix): spielt einen simulierten
## Tag im echten Wohnzimmer (GoobyReactions + PflegeRunner wie im Spiel) und
## protokolliert, was man von Gooby SIEHT: Ruhe-Emotion, Bewegung, Bubbles.
## Vergleichswert daneben: welche Emotion die Web-Referenz (emotions.js:
## context ?? statOverride ?? moodEmotion) zu denselben Stats zeigen würde.
## Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/seele2_diagnose.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/SEELE2/diagnose"

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Stats := preload("res://scripts/logic/stats.gd")

const MS_H := 3_600_000
const MS_D := 86_400_000
## 2026-07-27 06:00 UTC — Montag, Tagesbeginn.
const START_MS := 1_785_132_000_000
## Beobachtungsfenster pro Station (Frames à ~1/60 s Headless-Takt).
const WATCH_FRAMES := 600

var _gs: Node = null
var _room: Node = null
var _now := START_MS


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	SoulState.register_slice()
	var dir := "user://seele2_diag/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_gs = GameStateScript.new()
	_gs.initialize(dir + "/save_v5.json")
	_gs.update(
		func(s: Dictionary) -> void:
			s["meta"]["playerName"] = "Mira"
			s["meta"]["createdAt"] = START_MS - 30 * MS_D
	)
	_build_room()
	await _settle(70)
	_attach_runners()

	# Ein Tag in fünf Stationen: Stats verfallen ehrlich nach §C1
	# (Stats.apply_tick über die wachen Minuten seit Tagesbeginn).
	var morgen := {"hunger": 92.0, "energy": 95.0, "hygiene": 88.0, "fun": 90.0}
	await _station("A_0800_frisch", 8, morgen, 120)
	await _station("B_1230_angegraut", 12, _decayed(morgen, 4.5 * 60.0), 270)
	await _station("C_1700_durchhaengend", 17, _decayed(morgen, 9.0 * 60.0), 270)
	await _station("D_2100_elend", 21, _decayed(morgen, 13.0 * 60.0), 240)
	await _station("E_2300_nacht", 23, _decayed(morgen, 15.0 * 60.0), 120)

	print("Diagnose fertig -> %s" % OUT_DIR)
	_room.queue_free()
	await _settle(2)
	_gs.free()
	SaveSchema.unregister_slice(SoulState.SLICE_ID)
	SoulState.reset_for_tests()
	quit(0)


func _build_room() -> void:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	_room = scene.instantiate()
	_room.set("game_state_override", _gs)
	root.add_child(_room)


func _attach_runners() -> void:
	var reactions := GoobyReactions.attach_to(_room)
	reactions.now_ms_override = _now
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/soul/data/soul.json")
	)
	reactions._defs = parsed.get("items", [])
	PflegeRunner.attach_to(_room)
	SoulState.mutate(
		_gs,
		func(s: Dictionary) -> void:
			s["firstMetAt"] = START_MS - 30 * MS_D
			s["lastVisitAt"] = START_MS - 10 * MS_H
	)


## Stats nach wachen Minuten seit Tagesbeginn (§C1-Verfall, ehrlich).
func _decayed(from: Dictionary, minutes: float) -> Dictionary:
	return Stats.apply_tick(from, minutes)


## Eine Tages-Station: Uhrzeit + Stats setzen, dann nur zuschauen.
func _station(label: String, hour: int, stats: Dictionary, frames: int) -> void:
	_now = START_MS + (hour - 6) * MS_H
	var reactions: GoobyReactions = _room.get_node("GoobyReactions")
	reactions.now_ms_override = _now
	_gs.update(func(s: Dictionary) -> void: s["gooby"]["stats"] = stats.duplicate())
	_gs.notify_slice_changed("gooby")

	var mood := Stats.mood(stats)
	var band := Stats.mood_band(mood)
	print("\n== %s  stats=%s" % [label, _fmt_stats(stats)])
	print("   web-referenz: mood=%.1f band=%s (Ruhe-Gesicht der Web-Version)" % [mood, band])

	var gooby: Node3D = _room.gooby()
	var rig: GoobyRig = gooby.get("rig")
	var bubble: DialogBubble = _find_bubble()
	var emotions := {}
	var lines := {}
	var moved := 0.0
	var last_pos: Vector3 = gooby.global_position
	for i in frames:
		await process_frame
		if i % 10 == 0:
			var e := rig.get_emotion()
			emotions[e] = int(emotions.get(e, 0)) + 1
			moved += (gooby.global_position - last_pos).length()
			last_pos = gooby.global_position
			if bubble != null and bubble.is_active():
				lines[bubble.current_line()] = true
	print("   beobachtet: emotionen=%s bewegung=%.1fm" % [emotions, moved])
	for line: String in lines:
		print('   bubble: "%s"' % line)
	await _shot("diag_%s.png" % label)


func _fmt_stats(stats: Dictionary) -> String:
	return (
		"hunger=%.0f energy=%.0f hygiene=%.0f fun=%.0f"
		% [stats["hunger"], stats["energy"], stats["hygiene"], stats["fun"]]
	)


func _find_bubble() -> DialogBubble:
	for node in _room.find_children("*", "DialogBubble", true, false):
		return node
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
