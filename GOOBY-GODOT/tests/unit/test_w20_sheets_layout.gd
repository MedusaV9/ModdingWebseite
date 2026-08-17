extends TestCase
## W20 P3 „Sheets & Menü-Screens“ — Wächter für die UI-Rework-Befunde der
## Blätter/Menüs (befunde.md Welle 2, MIT Geräte-Metriken beide Leitformate):
## - PanelSheet-Grundvertrag (a): Backdrop dunkelt kräftig ab (VEIL_ALPHA),
##   das Blatt-Paper ist opak, Überlauf trägt die ScrollFade-Falz-Kante,
##   add_footer pinnt CTAs OHNE Scrollen ins Bild.
## - Fold-Regel für alle P3-Screens: JEDES sichtbare Bedienelement ist ohne
##   Scrollen im Canvas ODER lebt in einem Scroll-Fenster, das selbst im
##   Canvas liegt (Scrollen holt es dann jederzeit ins Bild).
## - Reisepass im Canvas (b, Befund-Top-6): die Pass-Karte passt im
##   Querformat KOMPLETT in den Canvas (Kompakt-Spalten + Foto-Deckel).
## - Tagesquests (c, Befund-Top-7): „Neu würfeln“ als gepinnter Blatt-Fuß.
## - IKEA-Zonen (d, Befund-Top-8): Kauf-Leiste × Detail-Zone (Swatches +
##   Zoom-Slider) sind DISJUNKTE Flächen, nichts verdeckt einander.
## - Radio (B5): „Schließen“ pinnt als Blatt-Fuß; Telefon/Taxi (B7): der
##   Haupt-CTA pinnt im Shell-Fuß; DLC (C4): Kopf scrollt nicht mehr mit;
##   Reise (B12): die Abflugtafel klemmt an ihre Rasterbreite und zentriert.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")

## Leitformate [Fenster-px, screen_scale, Insets in PUNKTEN [l, t, r, b]]
## — Werte wie fb3_ui_audit.SIZES (Dynamic-Island-Klasse).
const LEIT_QUER: Array = [Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]]
const LEIT_HOCH: Array = [Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]]
## Audit-Befund-Format des P3-Nachfixes (safe_area @ 05_dlc trat NUR hier
## auf — andere Karten-Fallhöhen als im Leitformat hoch).
const BEFUND_HOCH: Array = [Vector2i(1179, 2556), 3.0, [0.0, 59.0, 0.0, 34.0]]
## Flächen-Schnitte > 1×1 px zählen als Überlappung (Zonen-Disjunktheit).
const ZONEN_TOLERANZ := 1.0

var _seq := 0
var _fenster_vorher := Vector2i.ZERO
var _canvas := Vector2.ZERO
var _safe_rect := Rect2()


## GameState-Double (Muster test_g4_travel): dotted get/set + update auf
## dem Schema-Default — leicht genug für Radio/Telefon/Reise/DLC.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

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


## MusicDirector-Double (Muster test_rest4_radio): nur die vom RadioSheet
## abgefragte API — der Layout-Test spielt nichts ab.
class FakeMusic:
	extends Node
	signal track_changed(track_id: String)
	var playing := false

	func radio_play(_id: String) -> void:
		playing = true
		track_changed.emit("")

	func radio_stop() -> void:
		playing = false

	func is_radio_playing() -> bool:
		return playing

	func current_track_id() -> String:
		return ""


# ── Aufbau-/Abbau-Helfer (Muster test_w20_bau_layout) ───────────────────────


## Fenster + Geräte-Metriken deterministisch pinnen — VOR dem Szenen-Bau.
func _pin_format(format: Array) -> void:
	if _fenster_vorher == Vector2i.ZERO:
		_fenster_vorher = tree.root.size
	var win: Vector2i = format[0]
	var scale := float(format[1])
	UiScale.screen_scale_override = scale
	tree.root.size = win
	await wait_frames(2)
	_canvas = Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(win.x), float(win.y)) / scale
	var px_pt := minf(_canvas.x, _canvas.y) / pt_kurz
	var insets_pt: Array = format[2]
	var l := float(insets_pt[0]) * px_pt
	var t := float(insets_pt[1]) * px_pt
	var r := float(insets_pt[2]) * px_pt
	var b := float(insets_pt[3]) * px_pt
	_safe_rect = Rect2(l, t, _canvas.x - l - r, _canvas.y - t - b)
	UiScale.insets_override = Rect2(_safe_rect)
	await wait_frames(1)


func _unpin_format() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _fenster_vorher != Vector2i.ZERO:
		tree.root.size = _fenster_vorher
		_fenster_vorher = Vector2i.ZERO
	await wait_frames(2)


func _leit_label(format: Array) -> String:
	var win: Vector2i = format[0]
	return "quer" if win.x > win.y else "hoch"


func _frisches_gs() -> Node:
	_seq += 1
	var dir := "user://w20_tests/sheets_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


# ── Mess-Helfer ──────────────────────────────────────────────────────────────


## Fold-Regel (a): jedes sichtbare Bedienelement (Knopf/Slider/Eingabe) ist
## OHNE Scrollen komplett im Canvas ODER lebt in einem ScrollContainer,
## dessen Sichtfenster selbst im Canvas liegt — Scrollen (mit ScrollFade-
## Affordance) holt es dann jederzeit ins Bild.
func _fold_regel_pruefen(wurzel: Node, kontext: String) -> void:
	var canvas_rect := Rect2(Vector2.ZERO, _canvas)
	var geprueft := 0
	for typ: String in ["Button", "Slider", "LineEdit"]:
		for node in wurzel.find_children("*", typ, true, false):
			var ctl := node as Control
			if ctl == null or not ctl.is_visible_in_tree():
				continue
			geprueft += 1
			var scroll := _scroll_wirt(ctl)
			if scroll != null:
				assert_true(
					canvas_rect.grow(1.0).encloses(scroll.get_global_rect()),
					(
						"%s: Scroll-Fenster um %s liegt im Canvas: %s"
						% [kontext, ctl.name, scroll.get_global_rect()]
					)
				)
				continue
			assert_true(
				canvas_rect.grow(1.0).encloses(ctl.get_global_rect()),
				(
					"%s: %s ist ohne Scrollen unerreichbar: %s"
					% [kontext, ctl.name, ctl.get_global_rect()]
				)
			)
	assert_true(geprueft > 0, "%s: Bedienelemente gefunden (%d)" % [kontext, geprueft])


## ÄUSSERSTER Scroll-Vorfahre (null = gepinnt): bei geschachtelten Scrolls
## (z. B. Zeilen-Scroll im Blatt-Scroll) entscheidet das äußerste Fenster
## über die Erreichbarkeit — Scrollen dort holt jedes innere Fenster samt
## Inhalt jederzeit ins Bild.
func _scroll_wirt(ctl: Control) -> ScrollContainer:
	var gefunden: ScrollContainer = null
	var node: Node = ctl.get_parent()
	while node != null:
		if node is ScrollContainer:
			gefunden = node as ScrollContainer
		node = node.get_parent()
	return gefunden


func _im_canvas(ctl: Control, kontext: String) -> void:
	var rect := ctl.get_global_rect()
	assert_true(
		Rect2(Vector2.ZERO, _canvas).grow(1.0).encloses(rect),
		"%s: %s komplett im Canvas: %s (Canvas %s)" % [kontext, ctl.name, rect, _canvas]
	)


func _zonen_disjunkt(a: Rect2, b: Rect2, kontext: String) -> void:
	var schnitt := a.intersection(b)
	assert_false(
		schnitt.size.x > ZONEN_TOLERANZ and schnitt.size.y > ZONEN_TOLERANZ,
		"%s: Zonen überlappen: %s × %s = %s" % [kontext, a, b, schnitt]
	)


# ── (a) PanelSheet-Grundvertrag: Opazität + Fold + gepinnter Fuß ─────────────


func test_panel_sheet_opazitaet_und_fold_vertrag() -> void:
	await _pin_format(LEIT_QUER)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	sheet.theme = ThemeService.theme()
	host.add_child(sheet)
	await wait_frames(1)
	# E1 „Blätter wirken halbtransparent“: Backdrop dunkelt kräftiger ab
	# als der Token-VEIL, das Blatt-Paper selbst ist voll deckend.
	var backdrop := sheet.get_node("%Backdrop") as ColorRect
	assert_almost(backdrop.color.a, PanelSheet.VEIL_ALPHA, 0.001, "Backdrop nutzt VEIL_ALPHA")
	assert_true(backdrop.color.a > AcTokens.VEIL.a + 0.05, "kräftiger als der Token-VEIL")
	var karte := sheet.get_node("%Sheet") as PanelContainer
	var stil := karte.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(stil != null and stil.bg_color.a >= 0.999, "Blatt-Paper ist opak")
	# Fold-Affordance: der Scroll steckt in der ScrollFade-Hülle, die
	# Unique-Lookups überleben das Umhängen (Owner-Restauration).
	var scroll := sheet.get_node("%SheetScroll") as ScrollContainer
	assert_true(scroll != null, "Unique-Lookup SheetScroll löst weiter auf")
	assert_true(sheet.get_node("%SheetBody") != null, "Unique-Lookup SheetBody löst weiter auf")
	assert_true(scroll.get_parent() is ScrollFade, "Scroll steckt in der ScrollFade-Hülle")
	# Überlauf-Inhalt + gepinnter Fuß-CTA (add_footer-Muster W18/4).
	var inhalt := VBoxContainer.new()
	for i in 40:
		var zeile := Label.new()
		zeile.text = "Zeile %d" % i
		inhalt.add_child(zeile)
	sheet.add_content(inhalt)
	var cta := Button.new()
	cta.name = "FussCta"
	cta.text = "Weiter"
	sheet.add_footer(cta)
	sheet.open()
	await wait_frames(6)
	var vbar := scroll.get_v_scroll_bar()
	assert_true(vbar.max_value - vbar.page > 1.0, "Inhalt läuft über (sonst prüft das nichts)")
	var huelle := scroll.get_parent() as ScrollFade
	assert_true(huelle.unten_aktiv(), "Unten-Kante signalisiert die Falz (B3-Affordance)")
	assert_false(scroll.is_ancestor_of(cta), "Fuß-CTA lebt AUSSERHALB des Scrolls")
	_im_canvas(cta, "sheet/fuss")
	_fold_regel_pruefen(sheet, "sheet/quer")
	sheet.close()
	await wait_frames(2)
	PanelStack.clear()
	host.queue_free()
	await wait_frames(1)
	await _unpin_format()


# ── (c) Tagesquests: Reroll gepinnt, Karten erreichbar (Befund-Top-7) ────────


func test_tagesquests_reroll_gepinnt_und_erreichbar() -> void:
	for format: Array in [LEIT_QUER, LEIT_HOCH]:
		await _pin_format(format)
		var label := _leit_label(format)
		var host := Node.new()
		tree.root.add_child(host)
		var gs := _frisches_gs()
		tree.root.add_child(gs)
		var service := DailyQuestService.attach_to(host, gs)
		await wait_frames(2)
		service.open_panel()
		await wait_frames(6)
		var sheet: PanelSheet = service._sheet
		var scroll := sheet.get_node("%SheetScroll") as ScrollContainer
		var reroll := sheet.find_child("RerollButton", true, false) as Control
		assert_true(reroll != null and reroll.is_visible_in_tree(), "%s: Reroll sichtbar" % label)
		assert_false(
			scroll.is_ancestor_of(reroll),
			"%s: Reroll ist als Blatt-Fuß aus dem Scroll gepinnt (B3)" % label
		)
		_im_canvas(reroll, "quests/%s" % label)
		var karten := (service._panel._rows as Dictionary).size()
		assert_true(karten >= 3, "%s: 3 Quest-Karten gebaut (%d)" % [label, karten])
		_fold_regel_pruefen(sheet, "quests/%s" % label)
		sheet.close()
		await wait_frames(2)
		PanelStack.clear()
		host.queue_free()
		gs.queue_free()
		await wait_frames(2)
		await _unpin_format()


# ── (b) Reisepass im Canvas (Befund-Top-6, Probe pass_im_canvas) ─────────────


func test_reisepass_karte_im_canvas() -> void:
	await _pin_format(LEIT_QUER)
	var gs := _frisches_gs()
	tree.root.add_child(gs)
	var screen := ProfilScreen.new()
	screen.auto_navigate = false
	screen.gs_override = gs
	tree.root.add_child(screen)
	await wait_frames(6)
	var karte := screen.find_child("PassCard", true, false) as Control
	assert_true(karte != null, "PassCard existiert")
	# Querformat: die Karte passt KOMPLETT in den Canvas (Kompakt-Spalten
	# + Foto-Höhendeckel W20 B2) — vorher fehlte die halbe Karte.
	var rect := karte.get_global_rect()
	assert_true(
		rect.position.y >= -0.5 and rect.end.y <= _canvas.y + 0.5,
		(
			"quer: Pass-Karte vertikal im Canvas (y %.1f..%.1f von %.0f)"
			% [rect.position.y, rect.end.y, _canvas.y]
		)
	)
	assert_true(
		rect.position.x >= -0.5 and rect.end.x <= _canvas.x + 0.5,
		"quer: Pass-Karte horizontal im Canvas (x %.1f..%.1f)" % [rect.position.x, rect.end.x]
	)
	_fold_regel_pruefen(screen, "profil/quer")
	# Rotation ins Hochformat: die Karte bleibt in der Breite im Canvas,
	# längerer Inhalt scrollt (Fold-Regel deckt die Erreichbarkeit).
	await _pin_format(LEIT_HOCH)
	await wait_frames(4)
	var hoch_rect := karte.get_global_rect()
	assert_true(
		hoch_rect.position.x >= -0.5 and hoch_rect.end.x <= _canvas.x + 0.5,
		(
			"hoch: Pass-Karte horizontal im Canvas (x %.1f..%.1f)"
			% [hoch_rect.position.x, hoch_rect.end.x]
		)
	)
	_fold_regel_pruefen(screen, "profil/hoch")
	screen.queue_free()
	gs.queue_free()
	await wait_frames(2)
	await _unpin_format()


# ── (d) IKEA: Kauf-Leiste × Detail-Zone disjunkt (Befund-Top-8) ──────────────


func test_ikea_zonen_disjunkt() -> void:
	for format: Array in [LEIT_QUER, LEIT_HOCH]:
		await _pin_format(format)
		var label := _leit_label(format)
		HomeState.register_slice()
		var gs := _frisches_gs()
		gs.set_value("economy.coins", 1000)
		var screen := IkeaScreen.new()
		screen.game_state_override = gs
		screen.auto_navigate = false
		tree.root.add_child(screen)
		await wait_frames(3)
		screen.showcase().set_spin_enabled(false)
		# Härtester Fall: das Item mit den meisten Farbvarianten (höchste
		# Swatch-Zeile) — genau da verdeckte die Kauf-Leiste die Auswahl.
		screen.select_item(_variantenreichstes_item())
		await wait_frames(3)
		var kauf := screen.get("_kauf_leiste") as Control
		var detail := screen.get("_detail_panel") as Control
		var swatches := screen.get("_swatches") as Control
		var slider := screen.get("_zoom_slider") as Control
		assert_true(swatches.get_child_count() > 1, "%s: Farb-Swatches gebaut" % label)
		_zonen_disjunkt(
			kauf.get_global_rect(), detail.get_global_rect(), "%s: Kauf × Detail" % label
		)
		_zonen_disjunkt(
			kauf.get_global_rect(), swatches.get_global_rect(), "%s: Kauf × Swatches" % label
		)
		_zonen_disjunkt(kauf.get_global_rect(), slider.get_global_rect(), "%s: Kauf × Zoom" % label)
		# Beide Zonen sind gepinnt (kein Scroll-Vorfahre) und damit immer
		# sichtbar — die Vitrine scrollt bei Not, die Bedienung nie.
		assert_true(_scroll_wirt(kauf) == null, "%s: Kauf-Leiste gepinnt" % label)
		assert_true(_scroll_wirt(detail) == null, "%s: Detail-Zone gepinnt" % label)
		_im_canvas(kauf, "ikea/%s" % label)
		_im_canvas(detail, "ikea/%s" % label)
		_fold_regel_pruefen(screen, "ikea/%s" % label)
		screen.queue_free()
		await wait_frames(2)
		gs.free()
		SaveSchema.unregister_slice(HomeState.SLICE_ID)
		HomeState.reset_for_tests()
		await _unpin_format()


func _variantenreichstes_item() -> String:
	var beste_id := ""
	var beste := -1
	for item: Dictionary in ShopCatalog.filter(""):
		var n := FurnitureVariants.ids_for(item).size()
		if n > beste:
			beste = n
			beste_id = str(item["id"])
	return beste_id


# ── (e) Radio: „Schließen“ als gepinnter Blatt-Fuß (Befund B5) ───────────────


func test_radio_schliessen_als_blattfuss_gepinnt() -> void:
	await _pin_format(LEIT_QUER)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	sheet.theme = ThemeService.theme()
	host.add_child(sheet)
	var gs := FakeGameState.new()
	gs.set_value("radio.owned", true)
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var radio := RadioSheet.new()
	radio.gs = gs
	radio.music = music
	sheet.add_content(radio)
	sheet.open()
	await wait_frames(6)
	var schliessen := sheet.find_child("Schliessen", true, false) as Control
	assert_true(schliessen != null and schliessen.is_visible_in_tree(), "Schließen sichtbar")
	var scroll := sheet.get_node("%SheetScroll") as ScrollContainer
	assert_false(
		scroll.is_ancestor_of(schliessen), "Schließen pinnt als Blatt-Fuß statt im Scroll (B5)"
	)
	_im_canvas(schliessen, "radio/quer")
	_fold_regel_pruefen(sheet, "radio/quer")
	sheet.close()
	await wait_frames(2)
	PanelStack.clear()
	host.queue_free()
	music.queue_free()
	await wait_frames(1)
	await _unpin_format()


# ── (e) Telefon/Taxi: Haupt-CTA im gepinnten Shell-Fuß (Befund B7) ───────────


func test_taxi_cta_im_telefonfuss_gepinnt() -> void:
	for format: Array in [LEIT_QUER, LEIT_HOCH]:
		await _pin_format(format)
		var label := _leit_label(format)
		var gs := FakeGameState.new()
		gs.set_value("economy.coins", 300)
		var shell := PhoneShell.oeffne(tree.root, gs)
		await wait_frames(3)
		shell.oeffne_app("taxi")
		await wait_frames(3)
		var rufen := shell.find_child("RufenButton", true, false) as Control
		assert_true(rufen != null and rufen.is_visible_in_tree(), "%s: Rufen-CTA sichtbar" % label)
		var fuss := shell.find_child("AppFuss", true, false) as Control
		assert_true(
			fuss != null and fuss.is_ancestor_of(rufen),
			"%s: CTA pinnt im Shell-Fuß (B7, W18/4-B2-Muster)" % label
		)
		assert_true(_scroll_wirt(rufen) == null, "%s: CTA lebt außerhalb des Scrolls" % label)
		_im_canvas(rufen, "telefon/%s" % label)
		_fold_regel_pruefen(shell, "telefon/%s" % label)
		shell.schliesse()
		await wait_frames(2)
		await _unpin_format()


# ── (e) DLC: Kopfzeile scrollt nicht mehr aus dem Bild (Befund C4) ───────────


func test_dlc_kopf_bleibt_beim_scrollen_im_bild() -> void:
	await _pin_format(LEIT_QUER)
	DlcKatalog.reset_cache()
	var gs := FakeGameState.new()
	gs.set_value("progression.level", 20)
	var screen := DlcScreen.new()
	screen.gs_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(4)
	var zurueck := screen.find_child("Zurueck", true, false) as Control
	assert_true(zurueck != null and zurueck.is_visible_in_tree(), "Zurück sichtbar")
	var scroll := screen.get("_scroll") as ScrollContainer
	assert_false(
		scroll.is_ancestor_of(zurueck), "Kopf lebt ÜBER dem Scroll statt als Scroll-Kind (C4)"
	)
	_im_canvas(zurueck, "dlc/quer")
	# P3-Nachfix (Audit content_mitte @ 05_dlc): der gepinnte Kopf ist
	# SELBST eine Inhaltsspalte — Spalten-Meta gesetzt, safe-zentriert,
	# breiten-gedeckelt, und „Zurück“ liegt innerhalb der Spalte.
	var kopf := screen.get("_kopf") as Control
	assert_true(
		kopf != null and bool(kopf.get_meta(ScreenShell.META_CONTENT_COLUMN, false)),
		"Kopf trägt das W16-Spalten-Meta"
	)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m)
	var kopf_rect := kopf.get_global_rect()
	assert_true(
		kopf_rect.size.x <= spalte + 2.0,
		"Kopf hält den Spalten-Deckel (%.1f <= %.1f)" % [kopf_rect.size.x, spalte]
	)
	var insets: Dictionary = m["insets"]
	var safe_mitte := (float(insets["left"]) + (_canvas.x - float(insets["right"]))) / 2.0
	assert_almost(kopf_rect.get_center().x, safe_mitte, 2.0, "Kopf sitzt im Safe-Zentrum")
	assert_true(
		kopf_rect.grow(4.0).encloses(zurueck.get_global_rect()),
		"Zurück liegt in der Kopf-Spalte (Audit content_mitte)"
	)
	# Ganz nach unten scrollen: der Kopf bleibt an Ort und Stelle.
	var vorher := zurueck.get_global_rect().position.y
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await wait_frames(2)
	assert_almost(zurueck.get_global_rect().position.y, vorher, 0.5, "Kopf scrollt nicht mit (C4)")
	_fold_regel_pruefen(screen, "dlc/quer")
	screen.queue_free()
	await wait_frames(2)
	await _unpin_format()


## P3-Nachfix (Audit safe_area @ 05_dlc, hoch_1179x2556): die Ruhelage-
## Sicherung rechnet seit dem gepinnten Kopf scroll-LOKAL — in Ruhe darf
## kein SICHTBARER „Ansehen“-Knopf in der Home-Indicator-Zone liegen
## (die alte canvas-globale Zonen-Mathe übersah Kollisionen um die
## Kopf-Höhe). Der Audit-Befund war inhaltsabhängig (Karten-Fallhöhen),
## darum wird die Kollision hier zusätzlich PROVOZIERT: das Cover der
## ersten Karte wächst, bis ein Knopf mitten in der Home-Zone ruht — die
## Sicherung muss ihn wieder unter die Falte (aus dem Fenster) schieben.
func test_dlc_ruhelage_meidet_home_zone() -> void:
	for format: Array in [BEFUND_HOCH, LEIT_HOCH]:
		await _pin_format(format)
		var label := "%s" % (format[0] as Vector2i)
		DlcKatalog.reset_cache()
		var gs := FakeGameState.new()
		gs.set_value("progression.level", 20)
		var screen := DlcScreen.new()
		screen.gs_override = gs
		screen.auto_navigate = false
		tree.root.add_child(screen)
		# Ruhelage-Pass braucht sein Frame-Budget (deferred + bis zu 8 Frames).
		await wait_frames(12)
		var scroll := screen.get("_scroll") as ScrollContainer
		var insets: Dictionary = ScreenShell.metrics(screen.get_viewport())["insets"]
		var zone_ab := _canvas.y - float(insets["bottom"])
		var knoepfe: Array = screen.get("_ansehen_knoepfe")
		var paare: Array = screen.get("_parallax_cover")
		assert_true(
			knoepfe.size() >= 2 and paare.size() >= knoepfe.size(),
			"%s: Katalog baut Ansehen-Knöpfe + Cover-Rahmen" % label
		)
		_ruhe_zone_pruefen(knoepfe, scroll, zone_ab, "%s/aufbau" % label)
		# Unterster Knopf, der SICHTBAR über der Zone ruht — sein Karten-
		# Cover wächst, bis er mitten in der Home-Zone läge.
		var fenster := scroll.get_global_rect()
		var ziel_idx := -1
		for i in knoepfe.size():
			var r := (knoepfe[i] as Control).get_global_rect()
			if r.intersection(fenster).size.y > 0.0 and r.end.y < zone_ab - 4.0:
				ziel_idx = i
		assert_true(ziel_idx >= 0, "%s: ein Knopf ruht sichtbar über der Zone" % label)
		var delta := (zone_ab + 80.0) - (knoepfe[ziel_idx] as Control).get_global_rect().end.y
		(paare[ziel_idx]["rahmen"] as Control).custom_minimum_size.y += delta
		screen.call("_ruhelage_sichern")
		await wait_frames(12)
		_ruhe_zone_pruefen(knoepfe, scroll, zone_ab, "%s/provoziert" % label)
		screen.queue_free()
		await wait_frames(2)
		await _unpin_format()


## Helfer: kein SICHTBARER (am Scroll-Fenster geclippter) Knopf ragt in
## die Home-Indicator-Zone [zone_ab, Canvas-Boden) — Audit-safe_area-Regel.
func _ruhe_zone_pruefen(
	knoepfe: Array, scroll: ScrollContainer, zone_ab: float, wo: String
) -> void:
	var fenster := scroll.get_global_rect()
	for knopf: Button in knoepfe:
		var rect := knopf.get_global_rect().intersection(fenster)
		if rect.size.y <= 0.0:
			continue
		assert_true(
			rect.end.y <= zone_ab + 2.0,
			(
				"%s: sichtbarer Ansehen-Knopf endet über der Home-Zone (%.1f <= %.1f)"
				% [wo, rect.end.y, zone_ab]
			)
		)


# ── (e) Reise: Abflugtafel klemmt ans Raster + zentriert (Befund B12) ────────


func test_reise_tafel_klemmt_ans_raster() -> void:
	await _pin_format(LEIT_QUER)
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 500)
	var app := ReiseApp.oeffne(tree.root, gs)
	await wait_frames(6)
	var tafel := app.find_child("Abflugtafel", true, false) as FlapBoard
	assert_true(tafel != null, "Abflugtafel existiert")
	var breite := app.inhalt_breite()
	assert_true(
		tafel.size.x <= minf(tafel.raster_breite_px(), breite) + 1.0,
		(
			"Tafel klemmt an Raster-/Inhaltsbreite (B12): %.1f px (Raster %.1f, Inhalt %.1f)"
			% [tafel.size.x, tafel.raster_breite_px(), breite]
		)
	)
	assert_almost(
		tafel.get_global_rect().get_center().x,
		app.get_global_rect().get_center().x,
		2.0,
		"Tafel sitzt zentriert statt linksbündig mit leerem Rest-Drittel"
	)
	_fold_regel_pruefen(app.sheet, "reise/quer")
	app.sheet.close()
	await wait_frames(2)
	PanelStack.clear()
	await _unpin_format()
