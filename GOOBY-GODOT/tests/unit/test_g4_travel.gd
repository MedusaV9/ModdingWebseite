extends TestCase
## G4/P16 UI-TRAVELAPP — Reise-Strecke bedienbar + hübsch (g1/ui-reisen
## HOCH 3/5, MITTEL 6/7/10/11, NIEDRIG 12 + g2 F14a):
## - FlapBoard: Spaltenraster/Font aus der REALEN Breite (Schmal-Raster
##   wirft die Abflug-Spalte ab), Default bleibt der 47-Zeichen-Vertrag.
## - ReiseApp/Gooberando: Inhalt baut auf sheet_width − chrome_width statt
##   Festbreiten 420/380; Aktions-Knöpfe = SquishButtons ≥ Touch-Floor.
## - GOOBERANDO: Restaurant-KARTEN (AcCardButton) + dynamische Live-Karte.
## - BoardingPass: Breitenklemme + Barcode-Einpassung (kein Überlauf).
## - Weltengooby: zentrierte Feier-KARTE statt Toast (PanelStack + Weiter).
## - BeifahrerUi: RadioPanel bodenzentriert in der Safe-Area, F14a-Squish.
## - Reise-Cutscene: Skip bodenzentriert in der Safe-Area + Touch-Floor.
## Geometrie-Tests pinnen das Fenster VOR dem Screen-Bau (Muster
## test_g3_orte.gd) und setzen es am Ende zurück.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW := 1768478400000
const QUER := Vector2i(1280, 720)
const HOCH := Vector2i(720, 1280)


## GameState-Double (Muster test_w13b_reisepass): dotted get/set + update.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var clock := FakeClock.new()

	func _init() -> void:
		s = SaveSchema.default_state(1768478400000)

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


class FakeClock:
	extends RefCounted
	var ms := 1768478400000

	func now_ms() -> int:
		return ms


## Fenster + simulierte Notch setzen (Muster test_g3_orte/fb3_ui_audit).
func _setze_format(win_size: Vector2i, hochformat: bool) -> void:
	tree.root.size = win_size
	await wait_frames(1)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	if hochformat:
		UiScale.insets_override = Rect2(0.0, 90.0, canvas.x, canvas.y - 90.0 - 34.0)
	else:
		UiScale.insets_override = Rect2(88.0, 0.0, canvas.x - 176.0, canvas.y - 30.0)
	if tree.root.has_signal("size_changed"):
		tree.root.size_changed.emit()
	await wait_frames(1)


func _reset_format() -> void:
	UiScale.insets_override = Rect2()
	tree.root.size = QUER
	await wait_frames(1)


func _knoepfe_von(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		if current is Button:
			out.append(current)
	return out


## ------------------------------------------------------------- FlapBoard


func test_flap_spaltenraster_pur() -> void:
	var voll := FlapBoard.SPALTE_ZIEL + FlapBoard.SPALTE_ABFLUG + FlapBoard.SPALTE_STATUS
	assert_eq(
		FlapBoard.spalten_fuer_budget(voll),
		[FlapBoard.SPALTE_ZIEL, FlapBoard.SPALTE_ABFLUG, FlapBoard.SPALTE_STATUS],
		"volles Budget = klassisches Raster"
	)
	var eng: Array = FlapBoard.spalten_fuer_budget(30)
	assert_eq(int(eng[1]), 0, "schmal: Abflug-Spalte fliegt raus")
	assert_eq(int(eng[0]) + int(eng[2]), 30, "Budget wird voll verteilt")
	assert_true(int(eng[2]) >= 8, "Status bleibt lesbar")
	var minimal: Array = FlapBoard.spalten_fuer_budget(4)
	assert_eq(
		int(minimal[0]) + int(minimal[2]), FlapBoard.BUDGET_MIN, "nie unter BUDGET_MIN gequetscht"
	)


func test_flap_board_schmale_breite_rastert_um() -> void:
	var board := FlapBoard.new()
	board.reduziert_override = true
	tree.root.add_child(board)
	await wait_frames(1)
	var eintrag := {"ziel": "Glitzermeer", "abflug": "3 TAGE", "status": "BOARDING"}
	# Ohne Breiten-Angabe: klassischer 47-Zeichen-Vertrag (zeile_text_von).
	board.set_zeilen([eintrag])
	assert_eq(board.zeile_text(0), FlapBoard.zeile_text_von(eintrag), "Default-Raster steht")
	# Schmale Breite: Raster schrumpft, Zeile = Ziel|Status ohne Abflug.
	board.setze_verfuegbare_breite(180.0, 1.0)
	var schmal := board.gerasterte_zeile(eintrag)
	assert_true(schmal.length() < 47, "Schmal-Raster ist kürzer als 47 Zeichen")
	assert_true(schmal.begins_with("GLITZERMEER".left(schmal.find(" "))), "Ziel bleibt vorn")
	assert_false(schmal.contains("3 TAGE"), "Abflug-Spalte ist im Schmal-Raster raus")
	assert_eq(board.zeile_text(0), schmal, "sichtbare Zeile sofort neu gerastert")
	tree.root.remove_child(board)
	board.free()


## -------------------------------------------------------------- ReiseApp


func test_reise_app_breite_aus_sheet_und_touch_floor() -> void:
	await _setze_format(QUER, false)
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 500)
	var app := ReiseApp.oeffne(tree.root, gs)
	await wait_frames(3)
	var vp := tree.root
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp)
	var canvas := Vector2(vp.get_visible_rect().size)
	var erwartet := PanelSheetLayout.sheet_width(canvas, insets, f) - app.sheet.chrome_width()
	assert_almost(app.inhalt_breite(), erwartet, 0.5, "Breite = sheet_width − chrome_width")
	assert_almost(app.custom_minimum_size.x, erwartet, 0.5, "Festbreite 420 ist Geschichte")
	# 9 Ziel-Knöpfe (Vertrag) — alle SquishButtons ≥ 52·f UND Touch-Floor.
	var m := ScreenShell.metrics(vp)
	var floor_px: float = m["floor_px"]
	var knoepfe := 0
	for kind in app.get_children():
		if kind is Button:
			knoepfe += 1
			assert_true(kind is SquishButton, "%s ist ein SquishButton" % kind.name)
			assert_true(
				(kind as Control).custom_minimum_size.y >= maxf(roundf(52.0 * f), floor_px) - 0.5,
				"%s hält 52·f + Touch-Floor" % kind.name
			)
	assert_eq(knoepfe, ReiseLogic.ZIELE.size(), "alle 9 Ziele buchbar (Knopf-Vertrag)")
	# 9/9-Kapsel: Fortschritt der Weltengooby-Jagd am Buchungsort.
	var kapsel: Control = app.find_child("FortschrittKapsel", true, false)
	assert_ne(kapsel, null, "Fortschritts-Kapsel steht über der Tafel")
	assert_false(kapsel is Button, "Kapsel ist KEIN Knopf (9-Knöpfe-Vertrag)")
	var text: Label = app.find_child("FortschrittText", true, false)
	assert_true(str(text.text).contains("0/9"), "0/9 bereist im Frisch-Spielstand")
	app.sheet.close()
	await wait_frames(2)
	await _reset_format()


func test_reise_app_confirm_ueberlebt_rotation() -> void:
	await _setze_format(QUER, false)
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 500)
	var app := ReiseApp.new()
	app.gs = gs
	tree.root.add_child(app)
	await wait_frames(1)
	var erster: Button = null
	for kind in app.get_children():
		if kind is Button:
			erster = kind
			break
	erster.pressed.emit()
	await wait_frames(1)
	assert_false(String(app._confirm_ziel).is_empty(), "Bestätigung ist offen")
	# Rotation: Hochformat — Bestätigung bleibt offen statt zur Liste zu
	# springen (Resize-Rerender behält die aktive Ansicht).
	await _setze_format(HOCH, true)
	await wait_frames(2)
	assert_false(String(app._confirm_ziel).is_empty(), "Rotation wirft die Bestätigung nicht weg")
	var buchen_da := false
	for kind in app.get_children():
		if kind is Button and not (kind as Button).disabled:
			buchen_da = true
	assert_true(buchen_da, "Buchen/Doch-nicht stehen nach der Rotation")
	tree.root.remove_child(app)
	app.free()
	await _reset_format()


## ---------------------------------------------------------- BoardingPass


func test_boarding_pass_klemme_und_barcode_fit() -> void:
	await _setze_format(HOCH, true)
	var gerufen: Array = []
	var layer := BoardingPass.oeffne(tree.root, "beach", NOW, func() -> void: gerufen.append(1))
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var karte: BoardingPass = layer.find_child("BoardingPassKarte", true, false)
	assert_ne(karte, null, "Karte steht")
	var box: Control = karte.get_child(0)
	assert_almost(
		box.custom_minimum_size.x,
		ScreenShell.card_width(m, BoardingPass.BASIS_BREITE),
		0.5,
		"Breite klemmt an card_width statt Festwert 380"
	)
	var barcode: Label = layer.find_child("Barcode", true, false)
	assert_true(barcode.clip_text, "Barcode clippt als Notnagel")
	assert_true(barcode.has_meta(ScreenShell.META_FONT_SKIP), "Barcode skaliert nur über den Fit")
	var barcode_px := barcode.get_theme_font_size("font_size")
	assert_true(barcode_px <= int(BoardingPass.BARCODE_PX * f), "Barcode-Font ist eingepasst")
	var mess := (
		barcode
		. get_theme_font("font")
		. get_string_size(barcode.text, HORIZONTAL_ALIGNMENT_LEFT, -1, barcode_px)
		. x
	)
	assert_true(mess <= box.custom_minimum_size.x + 0.5, "Barcode läuft nicht aus der Karte")
	var knopf: Button = layer.find_child("GuteReiseBtn", true, false)
	assert_true(knopf is SquishButton, "Gute-Reise bleibt SquishButton")
	assert_true(knopf.custom_minimum_size.y >= float(m["floor_px"]) - 0.5, "Knopf hält den Floor")
	knopf.pressed.emit()
	assert_eq(gerufen.size(), 1, "Callback läuft weiter")
	assert_true(layer.is_queued_for_deletion(), "Karte räumt sich weg")
	await wait_frames(2)
	await _reset_format()


## ------------------------------------------------------------ GOOBERANDO


func test_gooberando_restaurant_karten_und_livekarte() -> void:
	await _setze_format(QUER, false)
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 500)
	var app := GooberandoApp.new()
	app.gs = gs
	tree.root.add_child(app)
	await wait_frames(1)
	# Restaurant-Wahl: EINE tappbare Karte je Küche (statt Button+Captions).
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var karten := 0
	for restaurant: Dictionary in GooberandoRestaurants.alle():
		var id := str(restaurant.get("id", ""))
		var karte: Button = app.find_child("Restaurant_%s" % id, true, false)
		assert_ne(karte, null, "Karte für %s steht" % id)
		karten += 1
		assert_true(karte is SquishButton, "Karte %s squisht" % id)
		assert_true(
			karte.custom_minimum_size.y >= maxf(roundf(64.0 * f), float(m["floor_px"])) - 0.5,
			"Karte %s ist ≥ 64·f hoch" % id
		)
		assert_ne(karte.find_child("KartenName", true, false), null, "Name in der Karte")
	assert_eq(karten, 3, "3 Lieferküchen als Karten")
	# Live-Karte: Kante = clamp(Breite·0,7, 220, 420) statt Briefmarke 148.
	(
		gs
		. set_value(
			"city.gooberando",
			{
				"state": GooberandoLogic.STATE_BESTELLT,
				"bestelltAt": NOW,
				"fertigAt": NOW + 300000,
				"restaurantId": "",
			}
		)
	)
	gs.clock.ms = NOW + 10000
	app._render()
	await wait_frames(2)
	var mini: CityMinimap = null
	for kind in app.find_children("*", "CityMinimap", true, false):
		mini = kind
	assert_ne(mini, null, "Live-Karte steht im Countdown")
	var kante := app.karten_kante()
	assert_true(kante >= 220.0 - 0.5, "Karte ist keine 148er-Briefmarke mehr")
	assert_almost(mini.kachel, kante, 0.5, "Minimap-Kachel = dynamische Kante")
	assert_almost(mini.kante(), kante, 1.0, "reale Kante folgt der Kachel")
	tree.root.remove_child(app)
	app.free()
	await _reset_format()


func test_minimap_kachel_skaliert_projektion() -> void:
	var karte := CityMap.laden()
	var klein := CityMinimap.new()
	klein.karte = karte
	var gross := CityMinimap.new()
	gross.karte = karte
	gross.kachel = CityMinimap.GROESSE * 2.0
	var welt := karte.parkplatz_welt("zuhause")
	var p_klein := klein.welt_zu_pixel(welt)
	var p_gross := gross.welt_zu_pixel(welt)
	assert_almost(p_gross.x, p_klein.x * 2.0, 0.01, "Projektion skaliert linear (x)")
	assert_almost(p_gross.y, p_klein.y * 2.0, 0.01, "Projektion skaliert linear (y)")
	assert_true(p_gross.x >= 0.0 and p_gross.x <= gross.kachel, "Pixel bleiben in der Kachel")
	klein.free()
	gross.free()


## ---------------------------------------------------- Weltengooby-Feier


func test_weltengooby_feier_als_karte() -> void:
	await _setze_format(QUER, false)
	var gs := FakeGameState.new()
	var v: Dictionary = gs.s["vacation"]
	for ziel_id in ReiseLogic.ZIELE:
		v["visited"][ziel_id] = true
	v["weltengoobyAt"] = NOW
	v["weltengoobyGefeiert"] = false
	var host := Node.new()
	tree.root.add_child(host)
	var stack_vorher := PanelStack.count()
	var res := UrlaubsBonus.sync(gs, NOW + 1000, host)
	assert_true(bool(res["weltengooby_gefeiert"]), "Titel neu → Feier")
	await wait_frames(2)
	var karte: Control = tree.root.find_child("WeltengoobyKarte", true, false)
	assert_ne(karte, null, "Feier ist eine KARTE (kein Toast)")
	assert_ne(karte.find_child("FeierTitel", true, false), null, "Titel-Zeile da")
	assert_eq(PanelStack.count(), stack_vorher + 1, "Karte hängt im PanelStack (Back-Geste)")
	var m := ScreenShell.metrics(tree.root)
	var weiter: Button = karte.find_child("FeierWeiter", true, false)
	assert_true(weiter is SquishButton, "Weiter-Knopf squisht")
	assert_true(weiter.custom_minimum_size.y >= float(m["floor_px"]) - 0.5, "Weiter hält den Floor")
	weiter.pressed.emit()
	await wait_frames(2)
	assert_eq(PanelStack.count(), stack_vorher, "Weiter räumt den Stack auf")
	assert_eq(tree.root.find_child("WeltengoobyLayer", true, false), null, "Feier-Layer ist weg")
	# Latch: zweiter sync feiert nicht erneut.
	var res2 := UrlaubsBonus.sync(gs, NOW + 2000, host)
	assert_false(bool(res2["weltengooby_gefeiert"]), "Feier nur einmal")
	host.queue_free()
	await wait_frames(1)
	await _reset_format()


## ------------------------------------------------------------ BeifahrerUi


func test_beifahrer_radiopanel_bodenzentriert_f14a() -> void:
	await _setze_format(QUER, false)
	var coop := CoopDrive.new()
	var ui := BeifahrerUi.new()
	tree.root.add_child(ui)
	ui.setup(coop)
	ui.zeige_beifahrer(true, "Flauschi")
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	var panel: Control = ui.get_node("RadioPanel")
	# HOCH 3: bodenzentrierte Karte statt Kleber an der rechten Kante.
	assert_almost(
		panel.offset_bottom, -(float(insets["bottom"]) + 16.0 * f), 0.5, "über dem Home-Indicator"
	)
	var rect := panel.get_global_rect()
	var safe_l := float(insets["left"])
	var safe_r := canvas.x - float(insets["right"])
	assert_almost(
		rect.get_center().x, (safe_l + safe_r) / 2.0, 1.0, "horizontal im Safe-Rechteck zentriert"
	)
	assert_true(
		rect.end.y <= canvas.y - float(insets["bottom"]) + 0.5, "Karte liegt in der Safe-Area"
	)
	# F14a: alle Knöpfe SquishButtons + Theme-Variation + Touch-Floor.
	for knopf in _knoepfe_von(panel):
		assert_true(knopf is SquishButton, "%s squisht (F14a)" % knopf.name)
		assert_false(
			String(knopf.theme_type_variation).is_empty(), "%s trägt AC-Variation" % knopf.name
		)
		assert_true(
			knopf.custom_minimum_size.y >= float(m["floor_px"]) - 0.5,
			"%s hält den Touch-Floor" % knopf.name
		)
	assert_ne(panel.find_child("Sender_gooby-fm", true, false), null, "Sender-Namen stabil")
	# Namens-Verträge Einladung: Mitfahren/Ablehnen bleiben SquishButtons.
	ui.zeige_einladung("Flauschi")
	await wait_frames(1)
	var einladung: Control = ui.get_node("Einladung")
	assert_true(einladung.find_child("Mitfahren", true, false) is SquishButton, "Mitfahren squisht")
	assert_true(einladung.find_child("Ablehnen", true, false) is SquishButton, "Ablehnen squisht")
	ui.queue_free()
	coop.free()
	await wait_frames(1)
	await _reset_format()


## --------------------------------------------------------- Reise-Cutscene


func test_cutscene_skip_in_der_safe_area() -> void:
	await _setze_format(HOCH, true)
	var cutscene: ReiseCutscene = load("res://scenes/city/reise_cutscene.tscn").instantiate()
	cutscene.ziel_id = "beach"
	var fertig_zaehler: Array = []
	cutscene.fertig.connect(func() -> void: fertig_zaehler.append(1))
	tree.root.add_child(cutscene)
	await wait_frames(2)
	var skip: Button = cutscene.find_child("Skip", true, false)
	assert_ne(skip, null, "Skip-Knopf heißt Skip")
	assert_true(skip is SquishButton, "Skip squisht")
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	assert_true(skip.custom_minimum_size.y >= float(m["floor_px"]) - 0.5, "Skip hält den Floor")
	assert_almost(
		skip.offset_bottom, -(float(insets["bottom"]) + 16.0 * f), 0.5, "Skip über dem Indicator"
	)
	assert_almost(skip.anchor_left, 0.5, 0.01, "Skip ist bodenZENTRIERT (Daumenzone)")
	var rect := skip.get_global_rect()
	assert_true(
		rect.end.y <= canvas.y - float(insets["bottom"]) + 0.5, "Skip liegt in der Safe-Area"
	)
	# Knopf wird ab Sekunde 2 sichtbar; skip() bricht die Shots ab.
	var sichtbar := await wait_until(func() -> bool: return skip.visible, 4000)
	assert_true(sichtbar, "Skip erscheint nach 2 s")
	cutscene.skip()
	var beendet := await wait_until(func() -> bool: return not fertig_zaehler.is_empty(), 8000)
	assert_true(beendet, "Skip beendet die Cutscene")
	cutscene.queue_free()
	await wait_frames(2)
	await _reset_format()
