extends TestCase
## VIS-2, Trailer-Review 0:08–0:10: „Unten links in der UI (Lager-Inventar)
## ist der Text am linken Bildschirmrand abgeschnitten — ‚Fe…' statt
## ‚Fernsehsessel'.“ Schutzintention: der VOLLE Item-Name bleibt erreichbar
## und kein Chip klebt an der Bildkante.
##
## W21 P2: die Lager-Chips sind jetzt BILD-Chips (Thumb + Kurzname-Zeile +
## Zähler-Badge) in einem einklappbaren KontextDock — der volle Name lebt
## im Label-Text (Playtest-Harness findet ihn dort) UND im Tooltip; die
## Kurzname-ZEILE darf mit Ellipse trimmen (Design), aber nie Information
## verlieren. Die Kapazitäts-Kopfzeile ist in den Dock-Griff gewandert:
## der Fit-Pass fällt bei Enge auf die Kurzform („6/100“) zurück, statt
## die Zahl wegzuellipsen (W21-Hochkant-Befund).

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
	# Der Fall aus dem Trailer: der Fernsehsessel liegt im Lager.
	HomeState.store_item(gs, "loungeChair")
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(2)
	# W21: das Dock startet eingeklappt — fürs Chip-Messen Blatt aufklappen.
	build._dock_ui.klappe_lager(false)
	await wait_frames(3)
	var chips: Array[Button] = []
	for kind in build._drawer_items.get_children():
		if kind is Button:
			chips.append(kind)
	assert_true(chips.size() >= 1, "Lager zeigt Chips")
	# Der volle Name lebt im Namens-Label (harte Schnitte wie „Fe…" im
	# TEXT selbst wären wieder der Trailer-Bug) und im Tooltip.
	var sessel := build._dock_ui.lager_chip("loungeChair")
	assert_ne(sessel, null, "Fernsehsessel-Chip vorhanden")
	var name_label := sessel.find_child("Name", true, false) as Label
	assert_ne(name_label, null, "Bild-Chip trägt die Kurzname-Zeile")
	assert_eq(name_label.text, "Fernsehsessel", "Label-Text trägt den VOLLEN Namen")
	assert_eq(sessel.tooltip_text, "Fernsehsessel", "Tooltip trägt den vollen Namen")
	assert_eq(
		name_label.text_overrun_behavior,
		TextServer.OVERRUN_TRIM_ELLIPSIS,
		"Kurzname-Zeile trimmt mit Ellipse statt hart"
	)
	var f := float(build._dock_ui.m.get("f", 1.0))
	for chip in chips:
		# Kein Kollabieren: der Chip hält sein Bild-Chip-Mindestmaß.
		assert_true(
			chip.size.x + 0.5 >= BuildUiDock.CHIP_BREITE * f,
			"Chip '%s' hält die Bild-Chip-Breite" % chip.name
		)
		assert_true(
			chip.find_child("Badge", true, false) != null,
			"Chip '%s' trägt den Zähler-Badge" % chip.name
		)
	# Sicherheitsabstand: kein Chip klebt an der linken Bildschirmkante.
	var erster := chips[0]
	assert_true(
		erster.get_global_rect().position.x >= BuildMode.DRAWER_RAND_X - 0.5,
		(
			"erster Chip startet mit Rand (x=%.1f, Soll >= %.0f)"
			% [erster.get_global_rect().position.x, BuildMode.DRAWER_RAND_X]
		)
	)
	# Kapazitäts-Kopfzeile (jetzt Griff-Titel): komplett im Canvas, kein
	# harter Schnitt an der Kante.
	var griff: Button = build._dock_ui.kontext.griff
	var canvas := Vector2(build._ui.get_viewport().get_visible_rect().size)
	assert_true(
		Rect2(Vector2.ZERO, canvas).grow(0.5).encloses(griff.get_global_rect()),
		"Griff-Titel liegt komplett im Canvas (%s)" % griff.get_global_rect()
	)
	build.close()
	await _cleanup(room, gs)


## W21 (Hochkant-Playtest): die Kopfzeile wurde so eng, dass die Ellipse
## GENAU die Kapazitaets-Zahl frass („Lager 6/1…“) — der Titel-Fit fällt
## dann auf die Kurzform („6/100“) zurueck statt Information zu kappen.
func test_kapazitaets_titel_faellt_bei_enge_auf_kurzform_zurueck() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	var dock := BuildUiDock.new()
	dock.build(layer, BuildMode.EBENEN_KEYS)
	dock.ui.visible = true
	await wait_frames(2)
	dock.set_capacity_text(6, 100)
	await wait_frames(2)
	var voll := I18nService.t("build.lager", {"used": 6, "cap": 100})
	var kurz := I18nService.t("build.lager_kurz", {"used": 6, "cap": 100})
	# Enge Dock-Klemme → Kurzform; mit Platz kehrt der Volltext zurueck.
	assert_eq(dock._kapazitaets_titel(1.0), kurz, "enge Klemme → Kurzform statt Zahlen-Ellipse")
	assert_eq(dock._kapazitaets_titel(100000.0), voll, "breite Klemme → Volltext")
	# Der Griff trägt den gewählten Titel (Pfeil-Präfix + Titel).
	dock._capacity_fit_gegen(100000.0)
	assert_true(
		dock.kontext.griff.text.contains(voll),
		"Griff-Titel trägt die Vollform (ist: '%s')" % dock.kontext.griff.text
	)
	layer.free()
