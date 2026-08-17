extends TestCase
## W18/F6 — Wächter für drei Playtest-Befunde (report_bau 3+5/6/8, report_arcade B5):
## - IKEA Befund 3: die Kauf-Zeile (Preis-Pille + BuyButton) ist als
##   gepinnter CTA aus dem DetailScroll gewandert — der Knopf liegt in
##   BEIDEN Leitformaten (quer 2868×1320, hoch 1320×2868) bei allen
##   Item-Typen VOLLSTÄNDIG im Canvas, ganz ohne Scrollen.
## - Arcade B5: ein synthetischer Drag ÜBER einer Kachel scrollt das Grid
##   (Kacheln = MOUSE_FILTER_PASS + eigener Pan im gui_input-Signal des
##   Scrolls), ein Tap unter der Deadzone öffnet weiterhin das Spiel.
## - Chips (Befunde 6+8): IKEA-Kategorie-Chips und die Lager-Chip-Leiste
##   des Bau-Docks tragen ScrollFade-Kanten + Endpolster, die nur bei
##   echtem Überlauf einladen (G7-P54-Muster wie Garderobe/Gestalten).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Leitformate (W18): iPhone 17 Pro Max quer/hoch, @3×, Insets [l, t, r, b] pt.
const QUER_FENSTER := Vector2i(2868, 1320)
const QUER_INSETS_PT: Array = [62.0, 0.0, 62.0, 21.0]
const HOCH_FENSTER := Vector2i(1320, 2868)
const HOCH_INSETS_PT: Array = [0.0, 59.0, 0.0, 34.0]
const IPHONE_SCALE := 3.0
const ARCADE_FENSTER := Vector2i(1280, 800)

var _root_size := Vector2i.ZERO
var _user_factor := 1.0
var _text_factor := 1.0
var _extra_inset := 0.0
var _seq := 0


## Fenster + UiScale-Statics pinnen (Muster test_g7_garderobe_gestalten).
func _pin(fenster: Vector2i, scale: float, insets_pt: Array) -> void:
	_root_size = tree.root.size
	_user_factor = UiScale.user_factor
	_text_factor = UiScale.text_factor
	_extra_inset = UiScale.extra_inset
	UiScale.user_factor = 1.0
	UiScale.text_factor = 1.0
	UiScale.extra_inset = 0.0
	UiScale.screen_scale_override = scale
	tree.root.size = fenster
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(fenster.x), float(fenster.y)) / scale
	var px_pt := minf(canvas.x, canvas.y) / pt_kurz
	var l := float(insets_pt[0]) * px_pt
	var t := float(insets_pt[1]) * px_pt
	var r := float(insets_pt[2]) * px_pt
	var b := float(insets_pt[3]) * px_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	UiScale.user_factor = _user_factor
	UiScale.text_factor = _text_factor
	UiScale.extra_inset = _extra_inset
	tree.root.size = _root_size


func _frisches_gs(coins := 1000) -> Node:
	_seq += 1
	HomeState.register_slice()
	var dir := "user://w18_f6_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _ikea(gs: Node) -> IkeaScreen:
	var screen := IkeaScreen.new()
	screen.game_state_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	screen.showcase().set_spin_enabled(false)
	return screen


func _drop(screen: Node, gs: Node) -> void:
	screen.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Repräsentative Item-Typen: ein Item je Kategorie + die Extremfälle
## „längster Name“ (Autowrap → höchstes Detail-Panel) und „meiste
## Farbvarianten“ (höchste Swatch-Zeile).
func _pruef_items() -> Array[String]:
	var ids: Array[String] = []
	for kategorie: String in ShopCatalog.categories():
		var items := ShopCatalog.by_category(kategorie)
		if not items.is_empty():
			ids.append(str(items[0]["id"]))
	var laengster_name := ""
	var laengster_id := ""
	var meiste_varianten := -1
	var varianten_id := ""
	for item: Dictionary in ShopCatalog.filter(""):
		var name_text := FurnitureCatalog.display_name(item, "de")
		if name_text.length() > laengster_name.length():
			laengster_name = name_text
			laengster_id = str(item["id"])
		var varianten := FurnitureVariants.ids_for(item).size()
		if varianten > meiste_varianten:
			meiste_varianten = varianten
			varianten_id = str(item["id"])
	for id: String in [laengster_id, varianten_id]:
		if id != "" and not ids.has(id):
			ids.append(id)
	return ids


func _kauf_im_canvas(screen: IkeaScreen, kontext: String) -> void:
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var kauf := screen.find_child("BuyButton", true, false) as Control
	assert_true(kauf != null and kauf.is_visible_in_tree(), "%s: BuyButton sichtbar" % kontext)
	var rect := kauf.get_global_rect()
	assert_true(
		rect.position.y >= -0.5 and rect.end.y <= canvas.y + 0.5,
		(
			"%s: CTA vertikal komplett im Canvas (y %.1f..%.1f von %.0f)"
			% [kontext, rect.position.y, rect.end.y, canvas.y]
		)
	)
	assert_true(
		rect.position.x >= -0.5 and rect.end.x <= canvas.x + 0.5,
		(
			"%s: CTA horizontal komplett im Canvas (x %.1f..%.1f von %.0f)"
			% [kontext, rect.position.x, rect.end.x, canvas.x]
		)
	)


# ── IKEA: CTA immer sichtbar ───────────────────────────────────────────


func test_ikea_kaufzeile_ist_aus_dem_scroll_gepinnt() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := await _ikea(gs)
	var kauf := screen.find_child("BuyButton", true, false) as Control
	var scroll := screen.find_child("DetailScroll", true, false) as Control
	assert_true(kauf != null and scroll != null, "BuyButton und DetailScroll existieren")
	assert_false(
		scroll.is_ancestor_of(kauf),
		"Kauf-Zeile lebt AUSSERHALB des DetailScrolls (gepinnter CTA, Befund 3)"
	)
	var leiste := screen.find_child("KaufLeiste", true, false) as Control
	assert_true(leiste != null and leiste.is_ancestor_of(kauf), "CTA sitzt in der KaufLeiste")
	await _drop(screen, gs)
	_unpin()


func test_ikea_cta_im_canvas_leitformat_quer() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := await _ikea(gs)
	for id: String in _pruef_items():
		screen.select_item(id)
		await wait_frames(2)
		_kauf_im_canvas(screen, "quer/%s" % id)
	await _drop(screen, gs)
	_unpin()


func test_ikea_cta_im_canvas_leitformat_hoch() -> void:
	await _pin(HOCH_FENSTER, IPHONE_SCALE, HOCH_INSETS_PT)
	var gs := _frisches_gs()
	var screen := await _ikea(gs)
	for id: String in _pruef_items():
		screen.select_item(id)
		await wait_frames(2)
		_kauf_im_canvas(screen, "hoch/%s" % id)
	await _drop(screen, gs)
	_unpin()


# ── Arcade: Wisch scrollt, Tap öffnet ──────────────────────────────────


func _druck(pos: Vector2, gedrueckt: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = gedrueckt
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if gedrueckt else 0
	tree.root.push_input(ev)


func _ziehe(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.root.push_input(ev)


func test_arcade_drag_ueber_kachel_scrollt_und_tap_oeffnet() -> void:
	_root_size = tree.root.size
	tree.root.size = ARCADE_FENSTER
	var screen: ArcadeScreen = (
		(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
	)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var scroll := screen.get("_scroll") as ScrollContainer
	var grid := screen.get("_grid") as GridContainer
	var vbar := scroll.get_v_scroll_bar()
	assert_true(vbar.max_value - vbar.page > 1.0, "Grid läuft über (sonst prüft der Test nichts)")
	var tile := grid.get_child(0) as Control
	assert_eq(
		tile.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"Kachel reicht Events an den Scroll weiter (B5-Wurzel: STOP schluckte den Drag)"
	)
	var gewaehlt: Array = []
	screen.game_selected.connect(func(id: String) -> void: gewaehlt.append(id))
	# Drag: Press auf der Kachel, dann 6×40 px nach oben — ab der Deadzone
	# gehört die Geste dem Scroll, die Kachel darf NICHT feuern.
	var start := tile.get_global_rect().get_center()
	_druck(start, true)
	await wait_frames(1)
	var pos := start
	for _i in 6:
		pos += Vector2(0.0, -40.0)
		_ziehe(pos, Vector2(0.0, -40.0))
		await wait_frames(1)
	_druck(pos, false)
	await wait_frames(2)
	assert_true(
		scroll.scroll_vertical > 0,
		"Drag über der Kachel scrollt das Grid (scroll_vertical=%d)" % scroll.scroll_vertical
	)
	assert_true(gewaehlt.is_empty(), "Drag feuert keinen Kachel-Tap (war %s)" % str(gewaehlt))
	# Tap: zurück an den Anfang, Press+Release ohne Bewegung öffnet weiter.
	scroll.scroll_vertical = 0
	await wait_frames(2)
	var tap := tile.get_global_rect().get_center()
	_druck(tap, true)
	await wait_frames(1)
	_druck(tap, false)
	await wait_frames(2)
	assert_eq(gewaehlt.size(), 1, "Tap unter der Deadzone öffnet weiterhin die Kachel")
	screen.queue_free()
	await wait_frames(2)
	tree.root.size = _root_size


# ── Chips: Fade-Affordance + Endpolster ────────────────────────────────


func test_ikea_kategorie_chips_mit_fade_und_endpolster() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := await _ikea(gs)
	var chip_scroll := screen.get("_chip_scroll") as ScrollContainer
	var hbar := chip_scroll.get_h_scroll_bar()
	assert_true(
		hbar.max_value - hbar.page > 1.0,
		(
			"Chip-Leiste läuft im Leitformat über (Befund 8: nur 5 von %d Chips sichtbar)"
			% (screen.get("_chips") as Control).get_child_count()
		)
	)
	var fade := screen.get("_chip_fade") as ScrollFade
	assert_true(fade != null, "Chip-Leiste hat den ScrollFade-Affordance-Knoten")
	var rechts := fade.find_child("FadeRechts", true, false) as Control
	var links := fade.find_child("FadeLinks", true, false) as Control
	chip_scroll.scroll_horizontal = 0
	await wait_frames(2)
	assert_true(rechts.visible, "am Leisten-Anfang lädt die Rechts-Kante zum Scrollen ein")
	assert_false(links.visible, "links ist am Anfang nichts verborgen")
	chip_scroll.scroll_horizontal = int(hbar.max_value)
	await wait_frames(2)
	assert_false(rechts.visible, "am Leisten-Ende verschwindet die Rechts-Kante")
	assert_true(links.visible, "am Ende lädt die Links-Kante zurück")
	var polster := screen.get("_chip_polster") as MarginContainer
	assert_true(
		polster.get_theme_constant("margin_right") > 0,
		"Endpolster: letzter Chip steht frei vor der Fade-Kante"
	)
	await _drop(screen, gs)
	_unpin()


func test_lager_chip_leiste_mit_fade_und_endpolster() -> void:
	_root_size = tree.root.size
	tree.root.size = ARCADE_FENSTER
	var ui_layer := Control.new()
	ui_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(ui_layer)
	var keys: Array[String] = ["build.ebene.boden", "build.ebene.wand", "build.ebene.decke"]
	var dock := BuildUiDock.new()
	dock.build(ui_layer, keys)
	dock.ui.visible = true
	# W21: das Dock startet eingeklappt — die Scroll-/Fade-Probe braucht
	# das aufgeklappte Item-Blatt.
	dock.klappe_lager(false)
	await wait_frames(2)
	assert_true(dock.drawer_fade != null, "Lager-Leiste hat den ScrollFade-Affordance-Knoten")
	var scroll := dock.drawer_polster.get_parent() as ScrollContainer
	assert_true(scroll != null, "Endpolster sitzt im Chip-Scroll")
	assert_eq(scroll.scroll_deadzone, 24, "Wisch-Deadzone der Lager-Leiste gesetzt")
	# Überlauf herstellen (die Chip-SPAWN-Logik gehört build_mode.gd —
	# hier zählt nur das Scroll-/Affordance-Verhalten der Leiste selbst).
	for i in 16:
		var chip := Button.new()
		chip.text = "Kaktus-Freund %d" % i
		dock.drawer_items.add_child(chip)
	await wait_frames(3)
	var hbar := scroll.get_h_scroll_bar()
	assert_true(hbar.max_value - hbar.page > 1.0, "Chips laufen über (sonst prüft der Test nichts)")
	var rechts := dock.drawer_fade.find_child("FadeRechts", true, false) as Control
	scroll.scroll_horizontal = 0
	await wait_frames(2)
	assert_true(rechts.visible, "Überlauf zeigt die Rechts-Kante (kein harter Schnitt mehr)")
	scroll.scroll_horizontal = int(hbar.max_value)
	await wait_frames(2)
	assert_false(rechts.visible, "am Ende verschwindet die Rechts-Kante")
	assert_true(
		dock.drawer_polster.get_theme_constant("margin_right") > 0,
		"Endpolster: letzter Lager-Chip steht frei vor der Fade-Kante"
	)
	ui_layer.queue_free()
	await wait_frames(2)
	tree.root.size = _root_size
