extends TestCase
## G4 P15 UI-BAU — Baumodus-Domäne bedienbar: das Bau-UI liegt als EIN
## unten-mittiges Dock in der Daumenzone (Action-Bar / Status+Ebenen /
## Lager-Karte), läuft über den ScreenShell-Metrik-Pass (card_width,
## Safe-Area, Touch-Floor 44 pt, scale_fonts) statt Fix-Pixeln; GardenUi
## wandert von TOP_WIDE in eine unten-mittige Karte; das PresetSheet ist
## eine card_width-Karte mit Tastatur-Ausweich. Dazu die Audio-Grammatik-
## Verdrahtung als Quelltext-Wächter (Muster test_g3_wardrobe).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const BUILD_MODE_SRC := "res://scripts/home/build_mode/build_mode.gd"
const DOCK_SRC := "res://scripts/home/build_mode/build_ui_dock.gd"
const PRESET_SRC := "res://scripts/home/build_mode/preset_sheet.gd"
const GARDEN_SRC := "res://scripts/home/garden/garden_host.gd"

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://g4_build_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _open_room(gs: Node, scene_path: String) -> RoomBase:
	var scene: PackedScene = load(scene_path)
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	await wait_frames(6)
	return room


func _cleanup(room: Node, gs: Node) -> void:
	if room != null:
		room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Fenster VOR dem Szenen-Bau pinnen (W16-Befund, s. test_g3_wardrobe):
## headless übernimmt Window-Größen erst im Folge-Frame — ein Pin NACH dem
## Bau ließe Layout und Messung auseinanderlaufen (flaky im Voll-Runner).
func _pin_fenster(size: Vector2i) -> Vector2i:
	var vorher: Vector2i = tree.root.size
	tree.root.size = size
	await wait_frames(2)
	return vorher


func _unpin_fenster(vorher: Vector2i) -> void:
	tree.root.size = vorher
	await wait_frames(1)


# ── Bau-Dock: unten-mittig, gedeckelt, Touch-Floor, Status-Anzeige ───────────


func test_bau_dock_unten_mittig_gedeckelt_und_floor() -> void:
	var vorher := await _pin_fenster(Vector2i(1280, 720))
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/wohnzimmer.tscn")
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(4)
	var dock_ui: BuildUiDock = build._dock_ui
	var m := ScreenShell.metrics(build._ui.get_viewport())
	var canvas: Vector2 = m["canvas"]
	var dock: Control = dock_ui.dock
	# Mittig + auf card_width gedeckelt (statt BOTTOM_WIDE-Randleiste).
	assert_almost(
		dock.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Dock sitzt horizontal mittig"
	)
	var deckel := ScreenShell.card_width(m, BuildUiDock.DOCK_BASIS)
	assert_true(dock.size.x <= deckel + 0.6, "Dock gedeckelt: %.1f <= %.1f" % [dock.size.x, deckel])
	# Daumenzone: Unterkante respektiert den Bottom-Inset + Rand …
	var insets: Dictionary = m["insets"]
	var unten_max: float = canvas.y - float(insets["bottom"])
	assert_true(
		dock.get_global_rect().end.y <= unten_max + 0.6,
		"Dock endet über dem Safe-Bottom (%.1f <= %.1f)" % [dock.get_global_rect().end.y, unten_max]
	)
	# … und die EbenenLeiste liegt UNTEN (G1 ui-bau §1: vorher oben-mittig).
	var leiste: Control = dock_ui.ebenen_leiste
	assert_true(
		leiste.get_global_rect().position.y > canvas.y * 0.5,
		"EbenenLeiste in der unteren Hälfte (y=%.1f)" % leiste.get_global_rect().position.y
	)
	assert_true(leiste is HFlowContainer, "EbenenLeiste bricht als Flow um")
	# Touch-Floor 44 pt physisch auf ALLEN Bau-Knöpfen.
	var floor_px: float = m["floor_px"]
	for node in build._ui.find_children("*", "Button", true, false):
		var btn := node as Control
		assert_true(
			btn.custom_minimum_size.y >= floor_px - 0.5,
			"Knopf '%s' hält den Touch-Floor (%.0f px)" % [btn.name, floor_px]
		)
	# Kamera-Chips rechts mittig innerhalb des Canvas.
	var kamera: Control = dock_ui.kamera_leiste
	assert_true(
		kamera.get_global_rect().end.x <= canvas.x + 0.5, "Kamera-Leiste ragt nicht rechts raus"
	)
	assert_true(kamera.get_global_rect().position.x > canvas.x * 0.6, "Kamera-Leiste sitzt rechts")
	# Persistente Modus-Anzeige: beim Öffnen steht die Boden-Ebene drin.
	assert_eq(
		dock_ui.status_label.text,
		I18nService.t("build.status.ebene", {"ebene": I18nService.t("build.ebene.boden")}),
		"Status-Kapsel zeigt die aktive Ebene"
	)
	build.close()
	await _cleanup(room, gs)
	await _unpin_fenster(vorher)


func test_ebenen_wechsel_aktualisiert_chips_und_status() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/wohnzimmer.tscn")
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(2)
	var dock_ui: BuildUiDock = build._dock_ui
	build._on_ebene_gewaehlt(BuildMode.Ebene.WAND)
	assert_eq(
		dock_ui.ebenen_chips[BuildMode.Ebene.WAND].theme_type_variation,
		&"ChipLeaf",
		"aktiver Chip trägt ChipLeaf (nicht disabled — G1 §1d)"
	)
	assert_eq(
		dock_ui.ebenen_chips[BuildMode.Ebene.BODEN].theme_type_variation,
		&"AcChip",
		"inaktiver Chip fällt auf AcChip zurück"
	)
	assert_false(
		dock_ui.ebenen_chips[BuildMode.Ebene.WAND].disabled,
		"aktiver Chip bleibt tippbar (kein disabled-Grau)"
	)
	assert_eq(
		dock_ui.status_label.text,
		I18nService.t("build.status.ebene", {"ebene": I18nService.t("build.ebene.wand")}),
		"Status folgt dem Ebenen-Wechsel"
	)
	assert_false(build._action_bar.visible, "ohne Ghost bleibt die Action-Bar weg")
	build.close()
	await _cleanup(room, gs)


# ── GardenUi: unten-mittige Karte statt TOP_WIDE (G1 ui-bau §4) ──────────────


func test_garten_karte_unten_mittig_und_floor() -> void:
	var vorher := await _pin_fenster(Vector2i(1280, 720))
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/garten.tscn")
	var host: GardenHost = room.get_node("GardenHost")
	var ui: Control = host._ui
	await wait_frames(2)
	var m := ScreenShell.metrics(ui.get_viewport())
	var canvas: Vector2 = m["canvas"]
	# Unten verankert (vorher TOP_WIDE unter der Notch) …
	assert_almost(ui.anchor_top, 1.0, 0.001, "Karte ankert unten (anchor_top)")
	assert_almost(ui.anchor_bottom, 1.0, 0.001, "Karte ankert unten (anchor_bottom)")
	assert_true(
		ui.get_global_rect().position.y > canvas.y * 0.5,
		"Karte liegt in der unteren Hälfte (y=%.1f)" % ui.get_global_rect().position.y
	)
	# … mittig + gedeckelt statt volle Breite.
	assert_almost(
		ui.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Karte sitzt horizontal mittig"
	)
	var deckel := ScreenShell.card_width(m, GardenHost.KARTE_BASIS)
	assert_true(ui.size.x <= deckel + 0.6, "Karte gedeckelt: %.1f <= %.1f" % [ui.size.x, deckel])
	assert_true(host._aktionen is HFlowContainer, "Aktions-Chips brechen als Flow um")
	var floor_px: float = m["floor_px"]
	for node in ui.find_children("*", "Button", true, false):
		var btn := node as Control
		assert_true(
			btn.custom_minimum_size.y >= floor_px - 0.5,
			"Garten-Knopf '%s' hält den Touch-Floor" % btn.text
		)
	await _cleanup(room, gs)
	await _unpin_fenster(vorher)


# ── PresetSheet: card_width-Karte + Tastatur-Ausweich ────────────────────────


func test_preset_sheet_karte_floor_und_tastatur_ausweich() -> void:
	var vorher := await _pin_fenster(Vector2i(1280, 720))
	var gs := _fresh_gs()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	var sheet := PresetSheet.open_in(layer, gs, "living")
	await wait_frames(3)
	var m := ScreenShell.metrics(sheet.get_viewport())
	var karte: Control = sheet._card
	var deckel := ScreenShell.card_width(m, PresetSheet.CARD_BASIS)
	assert_almost(
		karte.custom_minimum_size.x, deckel, 0.6, "Karte bezieht ihre Breite aus card_width"
	)
	assert_almost(karte.anchor_top, 0.5, 0.001, "Normalfall: Karte mittig")
	var floor_px: float = m["floor_px"]
	for node in sheet.find_children("*", "Button", true, false):
		var btn := node as Control
		assert_true(
			btn.custom_minimum_size.y >= floor_px - 0.5,
			"Preset-Knopf '%s' hält den Touch-Floor" % btn.name
		)
	var feld: LineEdit = sheet._name_feld
	assert_true(feld.custom_minimum_size.y >= floor_px - 0.5, "Namensfeld hält den Touch-Floor")
	# Tastatur-Ausweich: fokussiertes Namensfeld ankert die Karte oben, damit
	# die Bildschirm-Tastatur (bis ~50 % Höhe quer) das Feld nicht verdeckt.
	feld.grab_focus()
	await wait_frames(1)
	assert_almost(karte.anchor_top, 0.0, 0.001, "Fokus: Karte ankert oben")
	feld.release_focus()
	await wait_frames(1)
	assert_almost(karte.anchor_top, 0.5, 0.001, "Fokus weg: Karte wieder mittig")
	sheet.close()
	await wait_frames(2)
	layer.queue_free()
	await wait_frames(1)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	await _unpin_fenster(vorher)


# ── Audio-Grammatik als Quelltext-Wächter (Muster test_g3_wardrobe) ──────────


func test_sound_grammatik_verdrahtung() -> void:
	var build := _source(BUILD_MODE_SRC)
	assert_false(build.is_empty(), "build_mode.gd lesbar")
	assert_true(build.contains('try_play(self, "ui_chip")'), "Ebene/Drawer-Chip = ui_chip")
	assert_true(build.contains('try_play(self, "ui_back")'), "Fertig/Abbrechen = ui_back")
	# W21 P2: Platzieren klingt als ACNH-„Klopf“ (build_hammer) statt als
	# generisches ui_confirm — das Möbel wird hörbar festgeklopft.
	assert_true(build.contains('try_play(self, "build_hammer")'), "Platzieren = build_hammer")
	assert_true(build.contains('try_play(self, "ui_tick")'), "Zellen-Wechsel-Tick = ui_tick")
	assert_true(build.contains('try_play(self, "ui_error")'), "Verweigerung = ui_error")
	assert_true(build.contains("Haptics.warn(self)"), "Verweigerung mit Warn-Haptik")
	assert_false(build.contains("= Button.new()"), "Baumodus: nur SquishButton")
	assert_false(build.contains("Haptics.tap("), "Tap-Haptik kommt zentral vom SquishButton")

	var dock := _source(DOCK_SRC)
	assert_false(dock.is_empty(), "build_ui_dock.gd lesbar")
	assert_true(dock.contains("SquishButton.new()"), "Dock baut SquishButtons")
	assert_false(dock.contains("= Button.new()"), "Dock: kein Button.new()-Rückfall")
	assert_true(dock.contains("ScreenShell.card_width"), "Dock-Breite über card_width")
	assert_true(dock.contains("ScreenShell.scale_fonts"), "Dock skaliert Schriften")

	var preset := _source(PRESET_SRC)
	assert_false(preset.is_empty(), "preset_sheet.gd lesbar")
	assert_true(preset.contains('try_play(self, "ui_open")'), "Sheet öffnet mit ui_open")
	assert_true(preset.contains('try_play(self, "ui_close")'), "Sheet schließt mit ui_close")
	assert_true(preset.contains('try_play(self, "ui_confirm")'), "Speichern/Anwenden = ui_confirm")
	assert_true(preset.contains('try_play(self, "ui_error")'), "Fehl-Outcome = ui_error")
	assert_false(preset.contains("= Button.new()"), "PresetSheet: nur SquishButton")
	assert_false(preset.contains("Haptics.tap("), "Tap-Haptik zentral")

	var garden := _source(GARDEN_SRC)
	assert_false(garden.is_empty(), "garden_host.gd lesbar")
	assert_true(garden.contains('try_play(self, "ui_toggle")'), "Rolltor = ui_toggle")
	assert_true(garden.contains('try_play(self, "ui_buy")'), "Bau-Käufe = ui_buy")
	assert_true(garden.contains("Haptics.success(self)"), "Kauf-Erfolg mit Erfolgs-Haptik")
	assert_true(garden.contains('try_play(self, "ui_error")'), "Fehl-Outcome = ui_error")
	assert_false(garden.contains("= Button.new()"), "Garten: nur SquishButton")
	assert_false(garden.contains("Haptics.tap("), "Tap-Haptik zentral")


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
