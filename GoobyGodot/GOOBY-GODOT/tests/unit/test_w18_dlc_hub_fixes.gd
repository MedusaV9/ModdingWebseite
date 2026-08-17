extends TestCase
## W18/4 — Wächter für vier Playtest-Befunde des DLC-Hubs (report_dlc_ranch):
## - B2 „Settings-Overlay blockiert die Bibliothek“: der Bibliothek-Knopf
##   der Settings-Sektion räumt den Settings-Screen über seinen
##   back_pressed-Vertrag ab, BEVOR er die Route `dlc` anfährt.
## - B3 „Scrollen öffnet DLC-Sheets“: ein synthetischer Drag über einer
##   Cover-Karte scrollt die Bibliothek, ohne ein Detail-Sheet zu reißen;
##   ein Tap unter der scroll_deadzone öffnet weiterhin (Arcade-B5-Muster).
## - B4 „Aktionsknopf unter der Falz“: die CTA aller Detail-/Angebots-Sheets
##   (Aktions-Knopf/Bald-Hinweis, Ranch-„Jetzt losfahren“, Goobye-„Schlüssel
##   übernehmen“) sitzt im gepinnten SheetFooter AUSSERHALB des Scrolls und
##   liegt in BEIDEN Leitformaten (quer 2868×1320, hoch 1320×2868)
##   vollständig im Canvas — ganz ohne Scrollen (IKEA-Muster W18/F6).
## - B12 „Kauf-Knopf aktiv-grün trotz Münzmangel“: bei zu wenig Münzen ist
##   „Schlüssel übernehmen“ disabled, die Hinweiszeile sagt sofort Klartext,
##   und ein Tipp-Versuch schüttelt den Kopf (Garderoben-Muster).

## Leitformate (W18): iPhone 17 Pro Max quer/hoch, @3×, Insets [l, t, r, b] pt.
const QUER_FENSTER := Vector2i(2868, 1320)
const QUER_INSETS_PT: Array = [62.0, 0.0, 62.0, 21.0]
const HOCH_FENSTER := Vector2i(1320, 2868)
const HOCH_INSETS_PT: Array = [0.0, 59.0, 0.0, 34.0]
const IPHONE_SCALE := 3.0
const KLEIN_FENSTER := Vector2i(1280, 800)

var _root_size := Vector2i.ZERO
var _user_factor := 1.0
var _text_factor := 1.0
var _extra_inset := 0.0


## GameState-Double: dotted get_value/set_value wie /root/GameState
## (Muster test_w14_dlchub) — reicht für Status-/Kauf-Gates (kein update()).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

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


## SceneRouter-Double als Node unter /root (Muster test_shop_screen):
## protokolliert Reisen in ein GETEILTES Log, damit die Reihenfolge
## „Settings zu → Reise“ über Objektgrenzen hinweg beweisbar ist.
class FakeRouter:
	extends Node
	var routen: Dictionary = {}
	var protokoll: Array = []

	func register_routes(neu: Dictionary) -> void:
		routen.merge(neu, true)

	func register_route(route: StringName, szene: String) -> void:
		routen[route] = szene

	func goto(route: StringName, _params: Dictionary = {}) -> void:
		protokoll.append("reise:%s" % route)


## Settings-Screen-Double: nur der back_pressed-Vertrag zählt — home_entry
## hängt daran sein _close_settings (der echte Spieler-Zurück-Pfad).
class FakeSettings:
	extends Control
	signal back_pressed


func _gs(level: int, coins := 100000) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	gs.set_value("ranch.gekauft", false)
	gs.set_value("dlc.goobye.gekauft", false)
	return gs


## Fenster + UiScale-Statics pinnen (Muster test_w18_f6_ui_fixes).
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


## Wartet, bis die Einfahr-Animation des Blatts fertig ist (Ruhelage) —
## die CTA-Rects sind erst dann aussagekräftig. RM-sicher (kein Tween).
func _blatt_ruhe(sheet: PanelSheet) -> void:
	var fertig := await wait_until(
		func() -> bool:
			var tw := sheet.get("_motion_tween") as Tween
			return tw == null or not tw.is_valid() or not tw.is_running(),
		4000
	)
	assert_true(fertig, "Sheet-Einfahr-Animation endet")
	await wait_frames(2)


## B4-Kern: CTA lebt AUSSERHALB des SheetScrolls im gepinnten SheetFooter.
func _cta_gepinnt(sheet: PanelSheet, cta: Control, kontext: String) -> void:
	var scroll := sheet.find_child("SheetScroll", true, false) as Control
	assert_true(
		scroll != null and not scroll.is_ancestor_of(cta),
		"%s: CTA lebt außerhalb des Sheet-Scrolls (gepinnt, Befund B4)" % kontext
	)
	var fuss := sheet.find_child("SheetFooter", true, false) as Control
	assert_true(fuss != null and fuss.is_ancestor_of(cta), "%s: CTA sitzt im SheetFooter" % kontext)


## B4-Sichtbarkeit: CTA-Rect vollständig im Canvas, ohne zu scrollen.
func _cta_im_canvas(cta: Control, kontext: String) -> void:
	assert_true(cta != null and cta.is_visible_in_tree(), "%s: CTA sichtbar" % kontext)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var rect := cta.get_global_rect()
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


## ------------------------------------------ (a) B2: Settings → Bibliothek


func test_b2_bibliothek_knopf_raeumt_settings_vor_der_reise_ab() -> void:
	# Echten Router parken, Attrappe unter /root/SceneRouter einhängen
	# (Muster test_shop_screen) — sonst startete eine echte Szenen-Reise.
	var echt := tree.root.get_node_or_null(NodePath("SceneRouter"))
	if echt != null:
		echt.name = "SceneRouterGeparkt"
	var router := FakeRouter.new()
	router.name = "SceneRouter"
	tree.root.add_child(router)

	var settings := FakeSettings.new()
	tree.root.add_child(settings)
	settings.back_pressed.connect(func() -> void: router.protokoll.append("settings_zu"))
	var sections := VBoxContainer.new()
	settings.add_child(sections)
	DlcSektion.baue(settings, sections, 1.0, 1.0)
	await wait_frames(1)

	var knopf := sections.find_child("DlcButton", true, false) as Button
	assert_true(knopf != null, "Bibliothek-Knopf existiert in der Settings-Sektion")
	knopf.emit_signal("pressed")
	await wait_frames(1)
	assert_eq(
		router.protokoll,
		["settings_zu", "reise:dlc"],
		"B2: erst Settings über back_pressed abräumen, DANN zur Bibliothek reisen"
	)
	assert_true(router.routen.has(DlcScreen.ROUTE), "Route `dlc` ist vor der Reise registriert")

	settings.queue_free()
	tree.root.remove_child(router)
	router.free()
	if echt != null:
		echt.name = "SceneRouter"
	await wait_frames(1)


## ------------------------------------------ (b) B3: Wisch scrollt, Tap öffnet


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


func _sheets_von(screen: Control) -> Array[PanelSheet]:
	var out: Array[PanelSheet] = []
	for kind in screen.get_children():
		if kind is PanelSheet and not kind.is_queued_for_deletion():
			out.append(kind)
	return out


func test_b3_drag_ueber_karte_scrollt_ohne_sheet_und_tap_oeffnet() -> void:
	_root_size = tree.root.size
	tree.root.size = KLEIN_FENSTER
	DlcKatalog.reset_cache()
	var screen := DlcScreen.new()
	screen.gs_override = _gs(20)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(5)
	var scroll := screen.get("_scroll") as ScrollContainer
	var vbar := scroll.get_v_scroll_bar()
	assert_true(
		vbar.max_value - vbar.page > 1.0, "Bibliothek läuft über (sonst prüft der Test nichts)"
	)
	var karte := screen.karten()[0]
	assert_eq(
		karte.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"Karte reicht Events an den Scroll weiter (B3-Wurzel)"
	)
	var ansehen := karte.find_child("Ansehen", true, false) as Button
	assert_eq(
		ansehen.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"Ansehen-Knopf schluckt Drags nicht (Arcade-B5-Muster)"
	)
	# Drag: Press auf dem Cover, dann 6×40 px nach oben — ab der Deadzone
	# gehört die Geste dem Scroll, es darf KEIN Sheet aufgehen.
	var start := karte.find_child("CoverRahmen", true, false) as Control
	var pos := start.get_global_rect().get_center()
	_druck(pos, true)
	await wait_frames(1)
	for _i in 6:
		pos += Vector2(0.0, -40.0)
		_ziehe(pos, Vector2(0.0, -40.0))
		await wait_frames(1)
	_druck(pos, false)
	await wait_frames(2)
	assert_true(
		scroll.scroll_vertical > 0,
		"Drag über der Karte scrollt die Bibliothek (scroll_vertical=%d)" % scroll.scroll_vertical
	)
	assert_eq(_sheets_von(screen).size(), 0, "Drag reißt kein Detail-Sheet auf (Befund B3)")
	# Tap: zurück an den Anfang, Press+Release ohne Bewegung öffnet weiter.
	scroll.scroll_vertical = 0
	await wait_frames(2)
	var tap := karte.find_child("CoverRahmen", true, false) as Control
	var tap_pos := tap.get_global_rect().get_center()
	_druck(tap_pos, true)
	await wait_frames(1)
	_druck(tap_pos, false)
	await wait_frames(2)
	var sheets := _sheets_von(screen)
	assert_eq(sheets.size(), 1, "Tap unter der Deadzone öffnet GENAU EIN Detail-Sheet")
	if sheets.size() == 1:
		assert_true(sheets[0].is_open(), "Detail-Sheet ist offen")
		sheets[0].close()
		sheets[0].queue_free()
	screen.queue_free()
	await wait_frames(2)
	tree.root.size = _root_size


## ------------------------------------------ (c) B4: CTA in quer + hoch


## Detail-Sheets aller Katalog-Einträge bei gegebenem Level: die CTA
## (Aktions-Knopf ODER Bald-/Gesperrt-Hinweis) ist gepinnt + im Canvas.
func _pruefe_detail_ctas(kontext: String, level: int) -> void:
	DlcKatalog.reset_cache()
	var screen := DlcScreen.new()
	screen.gs_override = _gs(level)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	for dlc: Dictionary in DlcKatalog.eintraege():
		var id := str(dlc.get("id", ""))
		var sheet := screen.oeffne_detail(id)
		assert_true(sheet != null, "%s/%s: Detail-Sheet öffnet" % [kontext, id])
		if sheet == null:
			continue
		await _blatt_ruhe(sheet)
		var cta: Control = sheet.get_meta(DlcScreen.META_AKTION, null)
		if cta == null:
			cta = sheet.get_meta(DlcScreen.META_BALD, null)
		assert_true(cta != null, "%s/%s: Aktions-Knopf oder Hinweis existiert" % [kontext, id])
		if cta != null:
			_cta_gepinnt(sheet, cta, "%s/%s" % [kontext, id])
			_cta_im_canvas(cta, "%s/%s" % [kontext, id])
		sheet.close()
		sheet.queue_free()
		await wait_frames(2)
	screen.queue_free()
	await wait_frames(2)


## Angebots-Sheets (Ranch + Goobye): Kauf-Knöpfe gepinnt + im Canvas.
func _pruefe_angebot_ctas(kontext: String) -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var ranch_sheet := RanchOffer.zeige(host, _gs(20)) as PanelSheet
	assert_true(ranch_sheet != null, "%s: Ranch-Angebot öffnet" % kontext)
	if ranch_sheet != null:
		await _blatt_ruhe(ranch_sheet)
		var jetzt: Control = ranch_sheet.get_meta(RanchOffer.META_JETZT, null)
		assert_true(jetzt != null, "%s: „Jetzt losfahren“ existiert" % kontext)
		if jetzt != null:
			_cta_gepinnt(ranch_sheet, jetzt, "%s/ranch_jetzt" % kontext)
			_cta_im_canvas(jetzt, "%s/ranch_jetzt" % kontext)
		ranch_sheet.close()
		ranch_sheet.queue_free()
		await wait_frames(2)
	var goobye_sheet := GoobyeOffer.zeige(host, _gs(20)) as PanelSheet
	assert_true(goobye_sheet != null, "%s: Goobye-Angebot öffnet" % kontext)
	if goobye_sheet != null:
		await _blatt_ruhe(goobye_sheet)
		var kaufen: Control = goobye_sheet.get_meta(GoobyeOffer.META_KAUFEN, null)
		assert_true(kaufen != null, "%s: „Schlüssel übernehmen“ existiert" % kontext)
		if kaufen != null:
			_cta_gepinnt(goobye_sheet, kaufen, "%s/goobye_kaufen" % kontext)
			_cta_im_canvas(kaufen, "%s/goobye_kaufen" % kontext)
		goobye_sheet.close()
		goobye_sheet.queue_free()
		await wait_frames(2)
	host.queue_free()
	await wait_frames(1)


func test_b4_cta_im_canvas_leitformat_quer() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	# Level 20 = Angebot/Hof-Knöpfe; Level 1 = Gesperrt-Knopf + Hinweis.
	await _pruefe_detail_ctas("quer/L20", 20)
	await _pruefe_detail_ctas("quer/L1", 1)
	await _pruefe_angebot_ctas("quer")
	_unpin()


func test_b4_cta_im_canvas_leitformat_hoch() -> void:
	await _pin(HOCH_FENSTER, IPHONE_SCALE, HOCH_INSETS_PT)
	await _pruefe_detail_ctas("hoch/L20", 20)
	await _pruefe_detail_ctas("hoch/L1", 1)
	await _pruefe_angebot_ctas("hoch")
	_unpin()


## ------------------------------------------ (d) B12: Kauf-Knopf bei Ebbe


func test_b12_kauf_knopf_disabled_bei_muenzmangel() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var preis := GoobyeKatalog.preis()
	var sheet := GoobyeOffer.zeige(host, _gs(20, preis - 1)) as PanelSheet
	assert_true(sheet != null, "Angebot öffnet trotz Münzmangel (nur der Kauf ist gesperrt)")
	if sheet == null:
		host.queue_free()
		return
	await _blatt_ruhe(sheet)
	var kaufen: Button = sheet.get_meta(GoobyeOffer.META_KAUFEN, null)
	assert_true(kaufen != null and kaufen.disabled, "Kauf-Knopf DISABLED bei Münzmangel (B12)")
	var hinweis: Label = sheet.get_meta(GoobyeOffer.META_HINWEIS, null)
	assert_eq(
		hinweis.text,
		I18nService.t("dlc_goobye.angebot.zu_wenig", {"preis": preis}),
		"Hinweiszeile sagt SOFORT „zu wenig Münzen“ — nicht erst nach dem Tap"
	)
	# Tipp-Versuch auf den grauen Knopf: Kopfschütteln (Garderoben-Muster).
	# push_input mit in_local_coords=true: die Position ist in CANVAS-
	# Koordinaten (get_global_rect) — ohne das Flag rechnet der Root-Window-
	# Push die Stretch-Transformation drauf und der Touch landet daneben.
	var mitte := kaufen.get_global_rect().get_center()
	var drauf := InputEventScreenTouch.new()
	drauf.index = 7
	drauf.pressed = true
	drauf.position = mitte
	tree.root.push_input(drauf, true)
	await wait_frames(1)
	var weg := InputEventScreenTouch.new()
	weg.index = 7
	weg.pressed = false
	weg.position = mitte
	tree.root.push_input(weg, true)
	await wait_frames(1)
	if not ThemeService.is_reduced_motion(kaufen):
		assert_true(
			kaufen.get_meta(&"g7_schuettel", null) is Tween,
			"Tipp auf den gesperrten Knopf löst das Kopfschütteln aus"
		)
	sheet.close()
	sheet.queue_free()
	await wait_frames(2)
	# Gegenprobe: genug Münzen → Knopf aktiv, Hinweis = normale Kauffrage.
	var sheet2 := GoobyeOffer.zeige(host, _gs(20, preis)) as PanelSheet
	await _blatt_ruhe(sheet2)
	var kaufen2: Button = sheet2.get_meta(GoobyeOffer.META_KAUFEN, null)
	assert_true(kaufen2 != null and not kaufen2.disabled, "genau Preis reicht → Knopf aktiv")
	var hinweis2: Label = sheet2.get_meta(GoobyeOffer.META_HINWEIS, null)
	assert_eq(hinweis2.text, I18nService.t("dlc_goobye.angebot.frage"), "normale Kauffrage")
	sheet2.close()
	sheet2.queue_free()
	host.queue_free()
	await wait_frames(2)
