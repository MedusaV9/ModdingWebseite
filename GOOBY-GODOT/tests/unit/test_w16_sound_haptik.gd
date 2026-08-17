extends TestCase
## W16 SOUND/HAPTIK — Wächter (F5, g2-Fixliste): reparierte Builder/Screens
## bauen ausschließlich SquishButtons (Haptik + Squish laufen zentral dort).
## Die Datei wächst wellenweise mit; Editor in G3: P09 SOUND-KERN.
## Konvention: docs/godot-rewrite/AUDIO-GRAMMATIK.md.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const TAG := "2026-07-25"

var _seq := 0


## Scan-Helfer: jeder interaktive Button unter `root` muss SquishButton sein.
## Ausgenommen: OptionButton-Dropdowns (kein SquishButton-Erbe möglich) und
## reine Anzeige-Chips mit MOUSE_FILTER_IGNORE.
func _assert_alle_buttons_squish(root: Node, kontext: String) -> void:
	var gefunden := 0
	for btn: Node in root.find_children("*", "Button", true, false):
		if btn is OptionButton or (btn as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		gefunden += 1
		assert_true(btn is SquishButton, "%s: '%s' ist kein SquishButton" % [kontext, btn.name])
	assert_true(gefunden > 0, "%s: Scan fand keinen einzigen Button" % kontext)


func test_city_bausteine_bauen_squish() -> void:
	var box := VBoxContainer.new()
	var zeile := CitySheetBausteine.kauf_zeile(box, "T", "", "Kauf", true, func() -> void: pass)
	_assert_alle_buttons_squish(zeile, "kauf_zeile")
	var knopf := CitySheetBausteine.farb_knopf(Color.RED, false, func() -> void: pass)
	assert_true(knopf is SquishButton, "farb_knopf baut keinen SquishButton")
	knopf.free()
	box.free()


func test_kauf_zeile_sound_overrides_bleiben_kompatibel() -> void:
	# Die zwei dokumentierten Overrides (F1): Bestücken = stumm (""),
	# GoobyPal-Senden = "ui_click". Beide Signaturen müssen bauen und der
	# Druck muss den bei_kauf-Handler weiterhin erreichen.
	var box := VBoxContainer.new()
	var gedrueckt := [0]
	var stumm := CitySheetBausteine.kauf_zeile(
		box, "T", "", "K", true, func() -> void: gedrueckt[0] += 1, ""
	)
	var klick := CitySheetBausteine.kauf_zeile(
		box, "T", "", "K", false, func() -> void: pass, "ui_click"
	)
	var stumm_btn := stumm.get_child(stumm.get_child_count() - 1) as Button
	stumm_btn.pressed.emit()
	assert_eq(gedrueckt[0], 1, 'bei_kauf läuft auch mit sound_id=""')
	var klick_btn := klick.get_child(klick.get_child_count() - 1) as Button
	assert_true(klick_btn.disabled, "aktiv=false disabled den Knopf weiterhin")
	box.free()


func test_goobay_panel_baut_nur_squish_buttons() -> void:
	# F4: GooBay-Listenzeile, „zu“, Versand und die _add_button-Knöpfe.
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	HomeState.store_item(gs, "chair")
	var layer := Control.new()
	tree.root.add_child(layer)
	var panel := GoobayPanel.open_in(layer, gs, null, TAG, 7)
	await wait_frames(2)
	panel.starte_verhandlung("chair")
	await wait_frames(1)
	_assert_alle_buttons_squish(panel, "GoobayPanel")
	layer.queue_free()
	await wait_frames(2)
	_teardown(gs)


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w16_sound_haptik/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
