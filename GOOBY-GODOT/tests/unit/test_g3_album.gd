extends TestCase
## G3/P04 SPALTE-ALBUM — Album-Sonderfall (Inhaltsspalte mit eigener Basis
## 880 im Querformat, Rail als Top-Chip-Leiste im Hochformat), responsives
## Sammlungs-Raster (statt 5-Spalten-Fixraster), Galerie-Vollansicht in der
## Safe-Area und Touch-Floors für den Pass-Foto-Picker. Formate werden wie
## im FB3-Audit simuliert (root.size + UiScale screen_scale/insets-Override).

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1_750_000_000_000
## FB3-Formate: iPhone quer 1792×828 @2× / iPhone hoch 1179×2556 @3×.
const QUER := Vector2i(1792, 828)
const HOCH := Vector2i(1179, 2556)

var _seq := 0

## ------------------------------------------------------------ Album quer


func test_quer_inhaltsspalte_und_rail_links() -> void:
	await _format(QUER, 2.0, 59.0, 0.0, 59.0, 21.0)
	var ctx := await _open_album()
	var album: AlbumScreen = ctx["album"]
	assert_true(
		album._rows_box.has_meta(ScreenShell.META_CONTENT_COLUMN),
		"Album trägt das Inhaltsspalten-Meta-Flag (FB3-Audit-Vertrag)"
	)
	var m := ScreenShell.metrics(album.get_viewport())
	var breite := album._rows_box.size.x
	var deckel := ScreenShell.content_width(m, AlbumScreen.SPALTE_BASIS)
	assert_true(
		breite <= deckel + 2.0, "Spalte hält den 880er-Deckel (%.1f <= %.1f)" % [breite, deckel]
	)
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	var safe_mitte := (float(insets["left"]) + canvas.x - float(insets["right"])) / 2.0
	var spalten_mitte := album._rows_box.global_position.x + breite / 2.0
	assert_almost(spalten_mitte, safe_mitte, 2.0, "Spalte im SAFE-Rechteck zentriert")
	assert_false(album._split.vertical, "quer: Rail steht NEBEN dem Seiten-Panel")
	assert_true(album._rail_box.vertical, "quer: Chips stapeln vertikal")
	assert_true(album._rail_scroll.custom_minimum_size.x > 0.0, "quer: Rail hat Spaltenbreite")
	await _close_album(ctx)
	await _reset_format()


## ------------------------------------------------------------ Album hoch


func test_hoch_rail_als_top_chip_leiste() -> void:
	await _format(HOCH, 3.0, 0.0, 59.0, 0.0, 34.0)
	var ctx := await _open_album()
	var album: AlbumScreen = ctx["album"]
	assert_true(album._split.vertical, "hoch: Chip-Leiste liegt ÜBER dem Seiten-Panel")
	assert_false(album._rail_box.vertical, "hoch: Chips reihen sich horizontal")
	var chip := album._rail_box.get_node_or_null("PageChip_testset") as Button
	assert_true(chip != null, "Namensvertrag PageChip_%s bleibt erhalten")
	var m := ScreenShell.metrics(album.get_viewport())
	var floor_px: float = m["floor_px"]
	if chip != null:
		assert_true(
			chip.size.y >= floor_px - 0.5,
			"Chip hält den Touch-Floor (%.1f >= %.1f)" % [chip.size.y, floor_px]
		)
	assert_true(
		album._grid.get_node_or_null("Sticker_st_a") != null,
		"Namensvertrag Sticker_%s bleibt erhalten"
	)
	# Ohne linke Rail bekommt das Grid die volle Spaltenbreite.
	var spalte := ScreenShell.content_width(m, AlbumScreen.SPALTE_BASIS)
	assert_true(
		album._grid_scroll.size.x >= spalte - 2.0,
		"Grid nutzt die volle Spalte (%.1f >= %.1f)" % [album._grid_scroll.size.x, spalte]
	)
	await _close_album(ctx)
	await _reset_format()


func test_hoch_sammlungs_raster_passt_in_die_spalte() -> void:
	await _format(HOCH, 3.0, 0.0, 59.0, 0.0, 34.0)
	var ctx := await _open_album()
	var album: AlbumScreen = ctx["album"]
	album.show_page(AlbumScreen.COLLECTIONS_PAGE)
	await wait_frames(2)
	var view: CollectionsView = album._collections_view
	var m := ScreenShell.metrics(album.get_viewport())
	var floor_px: float = m["floor_px"]
	for def: Dictionary in CollectionsLogic.sets():
		var set_id := str(def["id"])
		var card := view.find_child("SetCard_%s" % set_id, true, false) as Control
		assert_true(card != null, "%s: Set-Karte existiert" % set_id)
		if card == null:
			continue
		var grid := card.find_child("EntryGrid", true, false) as GridContainer
		assert_true(grid.columns >= 3, "%s: mindestens 3 Slot-Spalten" % set_id)
		var min_breite := grid.get_combined_minimum_size().x
		assert_true(
			min_breite <= view.size.x + 2.0,
			"%s: Raster passt in die Panelbreite (%.1f <= %.1f)" % [set_id, min_breite, view.size.x]
		)
		var claim := card.find_child("ClaimButton", true, false) as Button
		assert_true(claim.size.y >= floor_px - 0.5, "%s: Claim-Knopf hält den Touch-Floor" % set_id)
	await _close_album(ctx)
	await _reset_format()


## ------------------------------------------------------------ Galerie


func test_galerie_vollansicht_in_der_safe_area() -> void:
	await _format(HOCH, 3.0, 0.0, 59.0, 0.0, 34.0)
	var gs := _fresh_gs()
	var pfade := _lege_fotos_an(gs, 2)
	var screen: Control = load("res://scripts/ui/galerie/galerie_screen.gd").new()
	screen.gs_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen.oeffne_vollansicht(pfade[0])
	await wait_frames(2)
	var m := ScreenShell.metrics(screen.get_viewport())
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	var safe := Rect2(
		float(insets["left"]),
		float(insets["top"]),
		canvas.x - float(insets["left"]) - float(insets["right"]),
		canvas.y - float(insets["top"]) - float(insets["bottom"])
	)
	var leiste: Control = screen._voll_leiste
	assert_true(leiste != null, "Vollansichts-Knopfleiste existiert")
	assert_true(
		safe.grow(2.0).encloses(leiste.get_global_rect()),
		"Knopfleiste liegt IN der Safe-Area (%s vs %s)" % [leiste.get_global_rect(), safe]
	)
	var floor_px: float = m["floor_px"]
	for knopf in leiste.get_children():
		if knopf is Button:
			assert_true(
				(knopf as Button).size.y >= floor_px - 0.5,
				"%s hält den Touch-Floor" % (knopf as Button).name
			)
	assert_true(
		screen._back_btn.custom_minimum_size.y >= floor_px - 0.5, "Zurück hält den Touch-Floor"
	)
	assert_true(
		screen._filter_btn.custom_minimum_size.y >= floor_px - 0.5, "Filter hält den Touch-Floor"
	)
	screen.queue_free()
	gs.queue_free()
	await wait_frames(2)
	await _reset_format()


## ------------------------------------------------------------ Pass-Picker


func test_passfoto_picker_floors_und_raster() -> void:
	await _format(HOCH, 3.0, 0.0, 59.0, 0.0, 34.0)
	var gs := _fresh_gs()
	_lege_fotos_an(gs, 5)
	var karte: PanelContainer = load("res://scripts/ui/profil/passport_card.gd").new()
	karte.gs = gs
	tree.root.add_child(karte)
	await wait_frames(2)
	var m := ScreenShell.metrics(karte.get_viewport())
	var floor_px: float = m["floor_px"]
	var foto_btn := karte.find_child("FotoAendernBtn", true, false) as Button
	assert_true(
		foto_btn.custom_minimum_size.y >= floor_px - 0.5,
		"FotoAendernBtn hält den Touch-Floor (%.1f)" % foto_btn.custom_minimum_size.y
	)
	karte._on_foto_aendern()
	await wait_frames(2)
	var picker := tree.root.get_node_or_null("PassFotoPicker")
	assert_true(picker != null, "Galerie-Picker öffnet")
	var raster := picker.find_child("PickerRaster", true, false) as GridContainer
	assert_true(raster != null, "Picker-Raster existiert")
	var f: float = m["f"]
	if raster != null:
		assert_true(
			raster.columns >= 2 and raster.columns <= 4,
			"Spaltenzahl aus der Breite (2–4), ist %d" % raster.columns
		)
		var kachel := raster.get_child(0) as Control
		assert_almost(kachel.custom_minimum_size.x, 128.0 * f, 0.5, "Picker-Kachel skaliert ×f")
	var abbrechen := picker.find_child("PickerAbbrechen", true, false) as Button
	assert_true(abbrechen.custom_minimum_size.y >= floor_px - 0.5, "PickerAbbrechen hält den Floor")
	karte._schliesse_picker()
	await wait_frames(2)
	karte.queue_free()
	gs.queue_free()
	await wait_frames(2)
	await _reset_format()


## ------------------------------------------------------------ Helfer


## Geräteformat wie im FB3-Audit simulieren (Insets in PUNKTEN).
func _format(win: Vector2i, scale: float, l: float, t: float, r: float, b: float) -> void:
	tree.root.size = win
	UiScale.screen_scale_override = scale
	await wait_frames(1)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(win.x), float(win.y)) / scale
	var px_pro_pt := minf(canvas.x, canvas.y) / pt_kurz
	var il := l * px_pro_pt
	var it := t * px_pro_pt
	var ir := r * px_pro_pt
	var ib := b * px_pro_pt
	UiScale.insets_override = Rect2(il, it, canvas.x - il - ir, canvas.y - it - ib)
	tree.root.size_changed.emit()
	await wait_frames(1)


func _reset_format() -> void:
	UiScale.insets_override = Rect2()
	UiScale.screen_scale_override = 0.0
	tree.root.size = Vector2i(1280, 720)
	await wait_frames(1)


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://g3_album_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	return gs


## Winzige echte PNGs anlegen und als city.fotos in den Save hängen
## (Galerie/Picker laden die Dateien wirklich als Texturen).
func _lege_fotos_an(gs: Node, anzahl: int) -> Array[String]:
	_seq += 1
	var dir := "user://g3_album_tests/fotos_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var pfade: Array[String] = []
	var fotos: Array = []
	for i in anzahl:
		var pfad := "%s/foto_%d.png" % [dir, i]
		var bild := Image.create(8, 8, false, Image.FORMAT_RGB8)
		bild.fill(Color(0.2 * i, 0.5, 0.8))
		bild.save_png(pfad)
		pfade.append(pfad)
		fotos.append({"pfad": pfad, "at": NOW_MS - i * 1000, "ort": "city"})
	gs.set_value("city.fotos", fotos)
	return pfade


func _mini_catalog() -> Array:
	return [
		{
			"id": "st_a",
			"name_de": "Alpha-Sticker",
			"flavor_de": "A.",
			"hint_de": "Zähler A.",
			"set": "testset",
			"page": "testset",
			"rarity": "haeufig",
			"image": "res://content/stickers/assets/ranch_neuer_hof.png",
			"cond": {"type": "counter", "key": "alpha_zaehler", "count": 1},
		},
	]


func _open_album() -> Dictionary:
	var gs := _fresh_gs()
	var album := AlbumScreen.new()
	album.auto_navigate = false
	album.gs_override = gs
	album.catalog_override = _mini_catalog()
	album.pages_override = [
		{"id": "testset", "title_de": "Testset", "icon": "star", "tint": "#CDE6BE", "order": 0}
	]
	tree.root.add_child(album)
	await wait_frames(2)
	return {"album": album, "gs": gs}


func _close_album(ctx: Dictionary) -> void:
	(ctx["album"] as Node).queue_free()
	(ctx["gs"] as Node).queue_free()
	await wait_frames(2)
