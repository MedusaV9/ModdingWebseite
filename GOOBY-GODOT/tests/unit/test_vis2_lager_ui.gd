extends TestCase
## VIS-2, Trailer-Review 0:08–0:10: „Unten links in der UI (Lager-Inventar)
## ist der Text am linken Bildschirmrand abgeschnitten — ‚Fe…' statt
## ‚Fernsehsessel'.“ Fix (build_mode.gd): die Lager-Schublade bekommt einen
## Innenabstand (DRAWER_RAND_X/Y) zum Bildschirmrand, die Chips behalten
## ihre text-basierte Mindestbreite (kein Kollabieren), und die Kopfzeile
## traegt eine Ellipse statt eines harten Schnitts.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://vis2_tests/lager_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_lager_chips_starten_mit_rand_und_vollem_namen() -> void:
	var gs := _fresh_gs()
	# Der Fall aus dem Trailer: der Fernsehsessel ist der ERSTE Chip links.
	HomeState.store_item(gs, "loungeChair")
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(4)
	var chips: Array[Button] = []
	for kind in build._drawer_items.get_children():
		if kind is Button:
			chips.append(kind)
	assert_true(chips.size() >= 1, "Lager zeigt Chips")
	var erster := chips[0]
	# Der Fall aus dem Trailer: der Fernsehsessel-Chip traegt den VOLLEN
	# Namen (nicht "Fe…"). Startbestand (z. B. Kuschelbett) kann davor liegen.
	var sessel: Button = null
	for chip in chips:
		if chip.text.begins_with("Fernsehsessel"):
			sessel = chip
	assert_ne(
		sessel,
		null,
		(
			"Fernsehsessel-Chip mit vollem Namen vorhanden (Chips: %s)"
			% ", ".join(chips.map(func(c: Button) -> String: return c.text))
		)
	)
	for chip in chips:
		# Kein Kollabieren: der Knopf ist mindestens so breit wie sein Text.
		assert_true(
			chip.size.x + 0.5 >= chip.get_combined_minimum_size().x,
			"Chip '%s' behaelt seine Textbreite" % chip.text
		)
	# Sicherheitsabstand: kein Chip klebt an der linken Bildschirmkante.
	assert_true(
		erster.get_global_rect().position.x >= BuildMode.DRAWER_RAND_X - 0.5,
		(
			"erster Chip startet mit Rand (x=%.1f, Soll >= %.0f)"
			% [erster.get_global_rect().position.x, BuildMode.DRAWER_RAND_X]
		)
	)
	# Kopfzeile: ebenfalls eingerueckt + Ellipse statt hartem Schnitt.
	var kopf: Label = build._capacity_label
	assert_true(
		kopf.get_global_rect().position.x >= BuildMode.DRAWER_RAND_X - 0.5,
		"Lager-Kopfzeile startet mit Rand"
	)
	assert_eq(
		kopf.text_overrun_behavior,
		TextServer.OVERRUN_TRIM_ELLIPSIS,
		"Kopfzeile schneidet mit Ellipse statt hart"
	)
	build.close()
	await _cleanup(room, gs)
