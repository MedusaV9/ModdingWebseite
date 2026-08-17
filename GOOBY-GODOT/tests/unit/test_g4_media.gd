extends TestCase
## G4/P17 UI-MEDIA: Radio-Sheet, Rückblick-Kino, Geschichten-Stunde,
## GOB.TY-Aus-Knopf, News-Lesebreite und DEV-Tabs — Touch-Floor, UiScale
## und Safe-Area (Leitidee FB3: Hintergrund vollflächig, Bedienung mittig).
## Geometrie-Tests pinnen das Fenster VOR dem Bau (Muster test_g3_wardrobe:
## headless übernimmt Window-Größen erst im Folge-Frame) und setzen es
## am Testende zurück.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const NewsSzene := preload("res://scripts/ui/news_50_panel.tscn")

var _saved_root_size := Vector2i.ZERO


## GameState-Double (Muster test_rest4_radio): dotted get/set + update().
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## Recap-taugliche GameState-Attrappe (Muster test_recap_scene).
class FakeRecapState:
	extends RefCounted
	var s: Dictionary

	func _init(state: Dictionary) -> void:
		s = state

	func state() -> Dictionary:
		return s

	func update(mutator: Callable) -> void:
		mutator.call(s)


## MusicDirector-Double: nur die vom Sheet benutzte Radio-API.
class FakeMusic:
	extends Node
	signal track_changed(track_id: String)
	var playing := false
	var track := ""

	func radio_play(id: String) -> void:
		playing = true
		var ids := MusicRegistry.station_track_ids(id)
		track = str(ids[0]) if not ids.is_empty() else ""
		track_changed.emit(track)

	func radio_stop() -> void:
		playing = false
		track = ""

	func is_radio_playing() -> bool:
		return playing

	func current_track_id() -> String:
		return track


# ------------------------------------------------------------ Fenster-Helfer


func _pin(size: Vector2i) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


# ------------------------------------------------------------- Radio-Sheet


func test_radio_sheet_knoepfe_squish_und_touch_floor() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	gs.set_value("radio.owned", true)
	gs.set_value("radio.station", "gooby-fm")
	gs.set_value("progression.level", 99)
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	tree.root.add_child(sheet)
	await wait_frames(2)
	var m := ScreenShell.metrics(sheet.get_viewport())
	var floor_px: float = m["floor_px"]
	var geprueft := 0
	for btn: Node in sheet.find_children("*", "Button", true, false):
		if btn is OptionButton:
			continue
		geprueft += 1
		assert_true(btn is SquishButton, "'%s' ist ein SquishButton" % btn.name)
		assert_true(
			(btn as Control).custom_minimum_size.y >= floor_px - 0.5,
			"'%s' erreicht den Touch-Floor (%.0f px)" % [btn.name, floor_px]
		)
	assert_true(geprueft >= 6, "Scan sieht Transport + Sender + Listen-Likes (%d)" % geprueft)
	var like_zeile: Button = sheet.find_child("Like_*", true, false)
	assert_true(like_zeile != null, "Titel-Listen-Like existiert")
	if like_zeile != null:
		assert_true(
			like_zeile.custom_minimum_size.x >= floor_px - 0.5,
			"Listen-Like ist auch in der BREITE tippbar"
		)
	var slider: HSlider = sheet.find_child("Lautstaerke", true, false)
	assert_true(slider != null, "Lautstärke-Slider existiert")
	if slider != null:
		assert_true(slider.custom_minimum_size.y >= floor_px - 0.5, "Slider-Trefferfläche ≥ Floor")
	sheet.queue_free()
	music.queue_free()
	await _unpin()


func test_radio_sheet_rebaut_bei_rotation() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	gs.set_value("radio.owned", true)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = FakeMusic.new()
	tree.root.add_child(sheet.music)
	tree.root.add_child(sheet)
	await wait_frames(2)
	var an_aus_vorher: Button = sheet.find_child("AnAus", true, false)
	assert_true(an_aus_vorher != null, "AnAus existiert vor der Rotation")
	tree.root.size = Vector2i(720, 1280)
	tree.root.size_changed.emit()
	await wait_frames(3)
	var an_aus_nachher: Button = sheet.find_child("AnAus", true, false)
	assert_true(an_aus_nachher != null, "AnAus existiert nach der Rotation")
	assert_true(an_aus_nachher != an_aus_vorher, "Rotation baut die UI mit frischen Metriken neu")
	sheet.music.queue_free()
	sheet.queue_free()
	await _unpin()


# ------------------------------------------------------- Now-Playing-Chip


func test_now_playing_chip_liegt_unter_der_safe_area() -> void:
	await _pin(Vector2i(1280, 720))
	UiScale.insets_override = Rect2(40.0, 30.0, 1200.0, 660.0)
	var chip := NowPlayingChip.new()
	chip.name = "NowPlayingChip"
	tree.root.add_child(chip)
	await wait_frames(1)
	var f := UiScale.for_viewport(chip.get_viewport())
	assert_almost(
		chip.offset_top, 30.0 + 14.0 * f, 0.5, "Floating-Chip sitzt UNTER der Notch-Kante"
	)
	assert_true(chip.sicht_breite >= 220.0, "Ticker-Sichtbreite kommt aus der Canvas")
	# Horizontal MITTIG (Daumenzone): Anker 0.5 + genullte Offsets — die
	# keep_offsets-Kompensation von set_anchors_preset klebte den Chip
	# sonst an die linke Kante (Screenshot-Befund G4).
	await wait_frames(1)
	var canvas := Vector2(chip.get_viewport().get_visible_rect().size)
	assert_almost(
		chip.get_global_rect().get_center().x,
		canvas.x / 2.0,
		1.0,
		"Floating-Chip ist horizontal zentriert"
	)
	# Insets ändern sich (Rotation/anderes Gerät) → Layout zieht nach.
	UiScale.insets_override = Rect2(0.0, 90.0, 1280.0, 630.0)
	tree.root.size_changed.emit()
	await wait_frames(1)
	assert_almost(chip.offset_top, 90.0 + 14.0 * f, 0.5, "Resize wendet die Insets neu an")
	chip.queue_free()
	await _unpin()


# ------------------------------------------------------------ Rückblick-Kino


func _recap_state() -> Dictionary:
	return {
		"progression": {"level": 11, "xp": 0},
		"economy": {"coins": 10, "coinsEarned": 80, "coinsSpent": 20},
		"profile": {"playtimeMin": 5, "distanceM": 120, "photos": 1},
		"minigames": {"plays": {"teaParty": 2}},
		"achievements":
		{"counters": {"feeds": 3, "tickles": 5, "trips": 1, "sleeps": 2, "harvests": 1}},
		"stickers": {"unlocked": {"a": true}},
		"park": {"visits": 0},
		"vacation": {"phase": "none"},
		"recap":
		{"history": [], "lastRecapLevel": 0, "baseline": {}, "baselineAt": 0.0, "pendingLevel": 5},
	}


func test_recap_skip_und_weiter_floor_safe_area_und_konfetti() -> void:
	await _pin(Vector2i(1280, 720))
	# Kino läuft im Querformat — Notch simuliert LINKS/RECHTS (44 px).
	UiScale.insets_override = Rect2(44.0, 0.0, 1192.0, 700.0)
	var gs := FakeRecapState.new(_recap_state())
	var scene: Control = RecapScene.build(gs)
	tree.root.add_child(scene)
	await wait_frames(2)
	var m := ScreenShell.metrics(scene.get_viewport())
	var f: float = m["f"]
	var floor_px: float = m["floor_px"]
	var insets: Dictionary = m["insets"]
	var skip: Button = scene.get("_skip_button")
	assert_true(skip is SquishButton, "Skip ist ein SquishButton")
	assert_true(skip.custom_minimum_size.y >= floor_px - 0.5, "Skip erreicht den Touch-Floor")
	assert_almost(
		skip.offset_top, float(insets["top"]) + 16.0 * f, 0.5, "Skip hängt unter der Safe-Kante"
	)
	assert_almost(
		skip.offset_right,
		-(float(insets["right"]) + 16.0 * f),
		0.5,
		"Skip respektiert den rechten Inset (Notch im Querformat)"
	)
	var weiter: Button = scene.get("_weiter_button")
	assert_true(weiter is SquishButton, "Weiter ist ein SquishButton")
	assert_true(weiter.custom_minimum_size.y >= floor_px - 0.5, "Weiter erreicht den Floor")
	assert_almost(
		weiter.offset_bottom,
		-(float(insets["bottom"]) + 24.0 * f),
		0.5,
		"Weiter bleibt über dem Home-Indicator"
	)
	var confetti: CPUParticles2D = scene.get("_confetti")
	var canvas: Vector2 = m["canvas"]
	assert_almost(confetti.position.x, canvas.x * 0.5, 0.5, "Konfetti mittig aus der Canvas")
	assert_almost(confetti.position.y, canvas.y * 0.17, 0.5, "Konfetti-Höhe aus der Canvas")
	var headline: Label = scene.get("_headline")
	assert_almost(headline.anchor_bottom, 0.34, 0.001, "Headline ankert im oberen Drittel")
	scene.queue_free()
	await wait_frames(2)
	await _unpin()


# ------------------------------------------------------- Geschichten-Stunde


## Buch-Layout über den WortGrid finden statt über den Namen: beim
## Rotation-Rebuild hängt der alte (queue_free-pending) "BuchLayout" noch
## als Geschwister im Sheet-Body — Godot benennt den NEUEN dann um
## (@BuchLayout@…), find_child("BuchLayout") liefe ins Leere.
func _buch_layout(sheet: PanelSheet) -> BoxContainer:
	var grid: GridContainer = sheet.find_child("WortGrid", true, false)
	var node: Node = grid
	while node != null and not (node.get_parent() is MarginContainer):
		node = node.get_parent()
	return node as BoxContainer


func _beispiel_story() -> Dictionary:
	return {
		"id": "test",
		"titel_de": "Test",
		"saetze_de": ["Gooby mag {0}.", "Er träumt von {1} und {2}."],
		"luecken": ["moehre", "nutella", "wolke"],
		"woerter_de":
		[
			{"id": "moehre", "text": "Möhre"},
			{"id": "nutella", "text": "Nutella"},
			{"id": "wolke", "text": "Wolke"},
			{"id": "socke", "text": "Socke"},
		],
	}


func test_story_buch_hochformat_stapelt_und_chips_floor() -> void:
	await _pin(Vector2i(720, 1280))
	var story_time := StoryTime.new()
	tree.root.add_child(story_time)
	await wait_frames(1)
	story_time.open_book(_beispiel_story())
	await wait_frames(2)
	var sheet: PanelSheet = story_time.get("_sheet")
	assert_true(sheet != null and sheet.is_open(), "Buch-Sheet ist offen")
	var layout := _buch_layout(sheet)
	assert_true(layout is VBoxContainer, "Hochformat: Sätze OBEN, Chips darunter (VBox)")
	var grid: GridContainer = sheet.find_child("WortGrid", true, false)
	assert_eq(grid.columns, 3, "Hochformat: 3 Chip-Spalten")
	var m := ScreenShell.metrics(story_time.get_viewport())
	var floor_px: float = m["floor_px"]
	for chip: Node in grid.get_children():
		assert_true(chip is SquishButton, "'%s' ist ein SquishButton" % chip.name)
		assert_true(
			(chip as Control).custom_minimum_size.y >= floor_px - 0.5,
			"'%s' erreicht den Touch-Floor" % chip.name
		)
	# Ein Wort setzen, dann rotieren: Umbruch wechselt, Wort bleibt verbraucht.
	var socke: Button = sheet.find_child("Wort_socke", true, false)
	socke.pressed.emit()
	await wait_frames(1)
	tree.root.size = Vector2i(1280, 720)
	tree.root.size_changed.emit()
	await wait_frames(3)
	layout = _buch_layout(sheet)
	assert_true(layout is HBoxContainer, "Querformat: Buch-Doppelseite (HBox)")
	grid = sheet.find_child("WortGrid", true, false)
	assert_eq(grid.columns, 2, "Querformat: 2 Chip-Spalten")
	var socke_neu: Button = sheet.find_child("Wort_socke", true, false)
	assert_true(socke_neu.disabled, "gesetztes Wort bleibt nach Rotation verbraucht")
	var moehre: Button = sheet.find_child("Wort_moehre", true, false)
	assert_false(moehre.disabled, "freie Wörter bleiben tippbar")
	sheet.close()
	story_time.queue_free()
	await _unpin()


func test_story_bibliothek_buecher_erreichen_floor() -> void:
	await _pin(Vector2i(1280, 720))
	var story_time := StoryTime.new()
	tree.root.add_child(story_time)
	await wait_frames(1)
	var m := ScreenShell.metrics(story_time.get_viewport())
	var row := story_time._library_row({"id": "b1", "titel_de": "Buch", "preis": 3}, true, {}, m)
	var btn: Button = row.find_child("Buch_b1", true, false)
	assert_true(btn is SquishButton, "Buch-Knopf ist ein SquishButton")
	assert_true(
		btn.custom_minimum_size.y >= float(m["floor_px"]) - 0.5, "Buch-Knopf erreicht den Floor"
	)
	row.free()
	story_time.queue_free()
	await _unpin()


# ---------------------------------------------------------- GOB.TY-Aus-Knopf


func test_gobty_aus_knopf_safe_area_und_floor() -> void:
	await _pin(Vector2i(1280, 720))
	UiScale.insets_override = Rect2(40.0, 0.0, 1200.0, 690.0)
	var host := InteractablesHost.new()
	tree.root.add_child(host)
	var tv := Fernseher.new()
	host.add_child(tv)
	tv._host = host
	await wait_frames(1)
	tv._zeige_aus_knopf()
	await wait_frames(1)
	var knopf: Button = tv.get("_aus_knopf")
	assert_true(knopf is SquishButton, "Aus-Knopf ist ein SquishButton")
	var m := ScreenShell.metrics(tv.get_viewport())
	var f: float = m["f"]
	var floor_px: float = m["floor_px"]
	var insets: Dictionary = m["insets"]
	assert_true(knopf.custom_minimum_size.y >= floor_px - 0.5, "Aus-Knopf erreicht den Floor")
	assert_true(knopf.custom_minimum_size.x >= floor_px * 2.0 - 0.5, "Aus-Knopf ist breit genug")
	assert_almost(
		knopf.offset_right,
		-(float(insets["right"]) + 16.0 * f),
		0.5,
		"Aus-Knopf respektiert den rechten Inset"
	)
	assert_almost(
		knopf.offset_bottom,
		-(float(insets["bottom"]) + 106.0 * f),
		0.5,
		"Aus-Knopf bleibt über der HUD-Daumen-Zeile + Safe-Area"
	)
	host.queue_free()
	await _unpin()


# ------------------------------------------------------------------- News


func test_news_items_lesebreite_gedeckelt_und_zentriert() -> void:
	await _pin(Vector2i(1280, 720))
	var panel: News50Panel = NewsSzene.instantiate()
	tree.root.add_child(panel)
	await wait_frames(1)
	panel.open()
	await wait_frames(2)
	var f := UiScale.for_viewport(panel.get_viewport())
	var item: PanelContainer = panel.find_child("Item0", true, false)
	assert_true(item != null, "erste News-Zeile existiert")
	if item != null:
		assert_eq(
			int(item.size_flags_horizontal),
			int(Control.SIZE_SHRINK_CENTER),
			"Item-Zeile ist zentriert (Inhaltsspalten-Gedanke)"
		)
		assert_true(
			item.custom_minimum_size.x <= 560.0 * f + 0.5, "Lesebreite ist auf ~560*f gedeckelt"
		)
		assert_true(item.custom_minimum_size.x >= 220.0, "Lesebreite hat einen Boden")
	panel.close()
	panel.queue_free()
	await _unpin()


func test_news_rotation_baut_lesebreite_neu_und_sheet_klemmt() -> void:
	# Hochformat: f≈1.78 brennt 560*f≈995 in die Zeilen — nach der Drehung
	# ins Querformat (Sheet nur ~720 breit) MUSS der Inhalt neu bauen, sonst
	# ragt das Blatt übers Bild hinaus (Screenshot-Befund G4).
	await _pin(Vector2i(720, 1280))
	var panel: News50Panel = NewsSzene.instantiate()
	tree.root.add_child(panel)
	await wait_frames(1)
	panel.open()
	await wait_frames(2)
	var f_hoch := UiScale.for_viewport(panel.get_viewport())
	assert_true(f_hoch > 1.5, "Hochformat skaliert deutlich (Canvas-Kurzkante 1280)")
	tree.root.size = Vector2i(1280, 720)
	tree.root.size_changed.emit()
	await wait_frames(3)
	var vp := panel.get_viewport()
	var f_quer := UiScale.for_viewport(vp)
	var item: PanelContainer = panel.find_child("Item0", true, false)
	assert_true(item != null, "News-Zeile existiert nach der Rotation")
	if item != null:
		assert_true(
			item.custom_minimum_size.x <= 560.0 * f_quer + 0.5,
			"Rotation baut die Lesebreite mit frischem f neu"
		)
	var sheet: PanelContainer = panel.get_node("%Sheet")
	var canvas := Vector2(vp.get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(vp)
	assert_true(
		sheet.size.x <= PanelSheetLayout.sheet_width(canvas, insets, f_quer) + 0.5,
		"Sheet bleibt nach der Rotation in seiner Layout-Breite (keine Blähung)"
	)
	panel.close()
	panel.queue_free()
	await _unpin()


# -------------------------------------------------------------- DEV-Tabs


func test_dev_tabs_skaliert_und_slider_floor() -> void:
	await _pin(Vector2i(1280, 720))
	var menu := DevMenu.new()
	tree.root.add_child(menu)
	await wait_frames(2)
	var tabs: TabContainer = menu.find_child("DevTabs", true, false)
	assert_true(tabs != null, "DevTabs existieren")
	if tabs != null:
		assert_true(tabs.clip_tabs, "Tab-Leiste läuft nicht mehr über die Karte hinaus")
		var erwartet := int(AcTokens.FONT_SIZE_BODY * UiScale.font_scale(menu.get_viewport()))
		assert_eq(tabs.get_theme_font_size("font_size"), erwartet, "Tab-Titel skalieren mit")
	var floor_px := float(ScreenShell.metrics(menu.get_viewport())["floor_px"])
	for slider_name: String in ["StatHunger", "ZeitSlider", "UhrOffsetSlider"]:
		var slider: HSlider = menu.find_child(slider_name, true, false)
		assert_true(slider != null, "%s existiert" % slider_name)
		if slider != null:
			assert_true(
				slider.custom_minimum_size.y >= floor_px - 0.5,
				"%s: Grabber-Trefferfläche ≥ Floor" % slider_name
			)
	menu.queue_free()
	await _unpin()
