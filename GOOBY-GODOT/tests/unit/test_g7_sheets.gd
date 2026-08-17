extends TestCase
## G7/P53 — Wachen fürs einheitliche Blatt-Verhalten der PanelSheet-Basis
## (User-Feedback „Modal-Menüs und Swipen/Wischen muss gefixt werden“):
## Öffnen setzt Dim + Endposition, Schließen räumt auf + gibt den Fokus
## zurück, Runterwisch-Synthese schließt (Kurz-Wisch schnappt zurück),
## Scroll-Inhalte ziehen das Blatt NICHT fälschlich, Dim-Tap schließt nur
## das oberste Blatt, Reduced Motion springt sofort — plus der
## Radio-Altbefund (FB3): „Gefällt mir“ bleibt im Canvas (hoch UND quer).
##
## Gesten laufen über echte Input-Synthese (InputEventScreenTouch/-Drag
## durch `root.push_input`), Fenster werden gepinnt und zurückgestellt.

const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## FB3-Formate: iPhone hoch (1179×2556 @3×) und das Leitformat
## iPhone 17 Pro Max quer (2868×1320 @3×) — Insets in Punkten [l, t, r, b].
const HOCH_FENSTER := Vector2i(1179, 2556)
const HOCH_INSETS_PT: Array = [0.0, 59.0, 0.0, 34.0]
const QUER_FENSTER := Vector2i(2868, 1320)
const QUER_INSETS_PT: Array = [62.0, 0.0, 62.0, 21.0]
const PIN_SCALE := 3.0


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
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


var _root_size := Vector2i.ZERO
var _user_factor := 1.0
var _text_factor := 1.0
var _extra_inset := 0.0

## ------------------------------------------------------------ Bausteine


## Sheet mit Label-Inhalt mounten und fertig geöffnet zurückgeben.
func _mount(zeilen := 8) -> Dictionary:
	PanelStack.clear()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var panel: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(panel)
	panel.set_title("G7-Probe")
	var box := VBoxContainer.new()
	for i in zeilen:
		var row := Label.new()
		row.text = "Zeile %d — Blatt-Inhalt für die Wisch-Wachen" % i
		box.add_child(row)
	panel.add_content(box)
	panel.open()
	await _settle(panel)
	return {
		"host": host,
		"panel": panel,
		"karte": panel.get_node("%Sheet") as Control,
		"scroll": panel.get_node("%SheetScroll") as ScrollContainer,
		"backdrop": panel.get_node("%Backdrop") as ColorRect,
		"griff": panel.get_node("%GrabHandle") as Control,
	}


## Warten, bis die Open-Animation in der Ruhelage angekommen ist.
## W20: zusätzlich auf das ENDE des Motion-Tweens warten — die TRANS_BACK-
## Kurve kreuzt die Ruhelage schon bei ~37 % der Laufzeit (vor dem
## Überschwinger); ein Frame genau im Kreuzungsfenster ließ die Probe
## sonst mitten in der Animation weiterlaufen (Dim erst bei ~0,74).
func _settle(panel: PanelSheet) -> void:
	var karte := panel.get_node("%Sheet") as Control
	var ok := await wait_until(
		func() -> bool:
			var tween := panel.get("_motion_tween") as Tween
			if tween != null and tween.is_valid() and tween.is_running():
				return false
			var rest := float(panel.get("_rest_y"))
			return karte.modulate.a >= 0.999 and absf(karte.position.y - rest) < 0.5
	)
	assert_true(ok, "Open-Animation erreicht die Ruhelage")


func _abbau(ctx: Dictionary) -> void:
	(ctx["host"] as Node).queue_free()
	await wait_frames(2)
	PanelStack.clear()


## Touch-/Drag-Synthese über den echten GUI-Weg (root.push_input).
func _touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	tree.root.push_input(ev, true)


func _drag(pos: Vector2, rel: Vector2, tempo := Vector2.ZERO) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = pos
	ev.relative = rel
	ev.velocity = tempo
	tree.root.push_input(ev, true)


## Runterwisch ab `start`: n Schritte à `schritt` px, dann loslassen.
func _wische(start: Vector2, schritt: float, schritte: int) -> void:
	_touch(start, true)
	await wait_frames(1)
	var pos := start
	for i in schritte:
		pos.y += schritt
		_drag(pos, Vector2(0.0, schritt))
		await wait_frames(1)
	_touch(pos, false)
	await wait_frames(1)


## Schrittweite, mit der 6 Wisch-Schritte SICHER über der Loslass-Schwelle
## (25 % der Blatthöhe, fensterabhängig) landen — deterministisch statt
## fester Pixel, damit der Test in jedem CI-Fensterformat schließt.
func _schliess_schritt(panel: PanelSheet) -> float:
	return float(panel.call("_schliess_distanz")) / 4.0 + 20.0


## Fenster + UiScale-Statics pinnen (Muster test_g4_nachfix._pin).
func _pin(fenster: Vector2i, insets_pt: Array) -> void:
	_root_size = tree.root.size
	_user_factor = UiScale.user_factor
	_text_factor = UiScale.text_factor
	_extra_inset = UiScale.extra_inset
	UiScale.user_factor = 1.0
	UiScale.text_factor = 1.0
	UiScale.extra_inset = 0.0
	UiScale.screen_scale_override = PIN_SCALE
	tree.root.size = fenster
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(fenster.x), float(fenster.y)) / PIN_SCALE
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


## -------------------------------------------------------- Öffnen/Schließen


func test_oeffnen_setzt_dim_und_endposition() -> void:
	var ctx: Dictionary = await _mount()
	var panel := ctx["panel"] as PanelSheet
	var karte := ctx["karte"] as Control
	var backdrop := ctx["backdrop"] as ColorRect
	assert_true(panel.visible, "Blatt sichtbar")
	assert_true(panel.is_open(), "logisch offen")
	assert_true(backdrop.visible, "Dim liegt hinterm Blatt")
	assert_almost(backdrop.modulate.a, 1.0, 1e-3, "Dim voll eingeblendet")
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_STOP, "Dim blockiert Klicks dahinter")
	assert_almost(karte.modulate.a, 1.0, 1e-3, "Karte voll deckend")
	assert_almost(karte.position.y, float(panel.get("_rest_y")), 0.5, "Endposition = Ruhelage")
	assert_eq(PanelStack.count(), 1, "auf dem Panel-Stack")
	await _abbau(ctx)


func test_schliessen_raeumt_dim_und_gibt_fokus_zurueck() -> void:
	PanelStack.clear()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var knopf := Button.new()
	knopf.text = "Außenwelt"
	host.add_child(knopf)
	knopf.grab_focus()
	var panel: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(panel)
	panel.add_content(Label.new())
	panel.open()
	await _settle(panel)
	var zu := [false]
	panel.closed.connect(func() -> void: zu[0] = true)
	panel.close()
	assert_true(zu[0], "closed feuert sofort (Vertrag der Call-Sites)")
	assert_false(panel.is_open(), "logisch zu")
	var weg := await wait_until(func() -> bool: return not panel.visible)
	assert_true(weg, "nach der Ausblend-Animation ist alles (inkl. Dim) unsichtbar")
	assert_eq(
		host.get_viewport().gui_get_focus_owner(), knopf, "Fokus kehrt zum Vorher-Eigner zurück"
	)
	host.queue_free()
	await wait_frames(2)
	PanelStack.clear()


## ------------------------------------------------------------ Runterwischen


func test_runterwisch_am_griff_schliesst() -> void:
	var ctx: Dictionary = await _mount()
	var panel := ctx["panel"] as PanelSheet
	var griff := ctx["griff"] as Control
	var zu := [false]
	panel.closed.connect(func() -> void: zu[0] = true)
	await _wische(griff.get_global_rect().get_center(), _schliess_schritt(panel), 6)
	assert_true(zu[0], "langer Runterwisch am Griff schließt das Blatt")
	var weg := await wait_until(func() -> bool: return not panel.visible)
	assert_true(weg, "Blatt fährt mit Restschwung aus und verschwindet")
	await _abbau(ctx)


func test_kurzwisch_schnappt_zurueck() -> void:
	var ctx: Dictionary = await _mount()
	var panel := ctx["panel"] as PanelSheet
	var karte := ctx["karte"] as Control
	var backdrop := ctx["backdrop"] as ColorRect
	var rest := float(panel.get("_rest_y"))
	var start := (ctx["griff"] as Control).get_global_rect().get_center()
	_touch(start, true)
	await wait_frames(1)
	_drag(start + Vector2(0.0, 18.0), Vector2(0.0, 18.0))
	await wait_frames(1)
	assert_almost(karte.position.y, rest + 18.0, 0.5, "Blatt folgt dem Finger")
	assert_true(backdrop.modulate.a < 1.0, "Dim hellt beim Zug leicht auf")
	_touch(start + Vector2(0.0, 18.0), false)
	var zurueck := await wait_until(
		func() -> bool: return absf(karte.position.y - rest) < 0.5 and backdrop.modulate.a >= 0.999
	)
	assert_true(zurueck, "unter der Schwelle schnappt das Blatt zurück, Dim wieder voll")
	assert_true(panel.is_open(), "Blatt bleibt offen")
	await _abbau(ctx)


func test_flick_mit_schwung_schliesst_trotz_kurzem_weg() -> void:
	var ctx: Dictionary = await _mount()
	var panel := ctx["panel"] as PanelSheet
	var zu := [false]
	panel.closed.connect(func() -> void: zu[0] = true)
	var start := (ctx["griff"] as Control).get_global_rect().get_center()
	var f := UiScale.for_viewport(tree.root)
	_touch(start, true)
	await wait_frames(1)
	# Weg klar UNTER der Distanz-Schwelle, aber mit kräftigem Schwung.
	_drag(start + Vector2(0.0, 30.0), Vector2(0.0, 30.0), Vector2(0.0, 2000.0 * f))
	await wait_frames(1)
	_touch(start + Vector2(0.0, 30.0), false)
	await wait_frames(1)
	assert_true(zu[0], "Flick nach unten schließt trotz kurzem Weg (Restschwung)")
	await _abbau(ctx)


func test_scroll_oben_zieht_blatt_und_schliesst() -> void:
	var ctx: Dictionary = await _mount(60)
	var panel := ctx["panel"] as PanelSheet
	var scroll := ctx["scroll"] as ScrollContainer
	assert_true(
		(scroll.get_node("SheetBody") as Control).get_combined_minimum_size().y > scroll.size.y,
		"Inhalt ist wirklich scrollbar (Testaufbau)"
	)
	scroll.scroll_vertical = 0
	var zu := [false]
	panel.closed.connect(func() -> void: zu[0] = true)
	await _wische(scroll.get_global_rect().get_center(), _schliess_schritt(panel), 6)
	assert_true(zu[0], "Scroller ganz oben: Runterwisch im Inhalt schließt")
	await _abbau(ctx)


func test_scroll_mittendrin_zieht_blatt_nicht() -> void:
	var ctx: Dictionary = await _mount(60)
	var panel := ctx["panel"] as PanelSheet
	var karte := ctx["karte"] as Control
	var scroll := ctx["scroll"] as ScrollContainer
	var rest := float(panel.get("_rest_y"))
	scroll.scroll_vertical = 300
	await wait_frames(1)
	assert_true(scroll.scroll_vertical > 0, "Scroller steht mittendrin (Testaufbau)")
	await _wische(scroll.get_global_rect().get_center(), 30.0, 3)
	assert_true(panel.is_open(), "Geste gehört dem Scroller — Blatt bleibt offen")
	assert_almost(karte.position.y, rest, 0.5, "Blatt hat sich keinen Pixel bewegt")
	await _abbau(ctx)


## ---------------------------------------------------------------- Dim-Tap


func test_dim_tap_schliesst_nur_oberstes_blatt() -> void:
	var ctx: Dictionary = await _mount()
	var unten := ctx["panel"] as PanelSheet
	var oben: PanelSheet = SHEET_SCENE.instantiate()
	(ctx["host"] as Node).add_child(oben)
	oben.add_content(Label.new())
	oben.open()
	await _settle(oben)
	var zu := [false]
	oben.closed.connect(func() -> void: zu[0] = true)
	# Tap oben links: dort liegt nur der Dim (Sheets sind unten zentriert).
	_touch(Vector2(8.0, 8.0), true)
	await wait_frames(1)
	_touch(Vector2(8.0, 8.0), false)
	await wait_frames(1)
	assert_true(zu[0], "Dim-Tap schließt das oberste Blatt")
	assert_true(unten.is_open(), "…und NUR das oberste — das untere bleibt offen")
	await _abbau(ctx)


## ---------------------------------------------------------- Reduced Motion


func test_reduced_motion_sofort_ohne_slide() -> void:
	var theme_svc := tree.root.get_node_or_null("/root/UiTheme")
	assert_true(theme_svc != null, "UiTheme-Autoload vorhanden")
	if theme_svc == null:
		return
	var vorher := bool(theme_svc.reduced_motion)
	theme_svc.reduced_motion = true
	PanelStack.clear()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var panel: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(panel)
	panel.add_content(Label.new())
	panel.open()
	var karte := panel.get_node("%Sheet") as Control
	var backdrop := panel.get_node("%Backdrop") as ColorRect
	# KEIN await: RM heißt SOFORT in Endlage — kein Slide, kein Fade.
	assert_almost(karte.modulate.a, 1.0, 1e-6, "RM: Karte sofort deckend")
	assert_almost(backdrop.modulate.a, 1.0, 1e-6, "RM: Dim sofort voll")
	assert_almost(karte.position.y, float(panel.get("_rest_y")), 0.5, "RM: sofort in der Ruhelage")
	panel.close()
	assert_false(panel.visible, "RM: Schließen versteckt sofort (kein Fade-Fenster)")
	theme_svc.reduced_motion = vorher
	host.queue_free()
	await wait_frames(2)
	PanelStack.clear()


## ------------------------------------------------------- Radio-Altbefund


func test_radio_like_bleibt_im_canvas_hoch_und_quer() -> void:
	for probe: Array in [[HOCH_FENSTER, HOCH_INSETS_PT], [QUER_FENSTER, QUER_INSETS_PT]]:
		await _pin(probe[0] as Vector2i, probe[1] as Array)
		PanelStack.clear()
		var host := Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		tree.root.add_child(host)
		var panel: PanelSheet = SHEET_SCENE.instantiate()
		panel.theme = ThemeService.theme()
		host.add_child(panel)
		panel.set_title("")
		var gs := FakeGameState.new()
		gs.set_value("radio.owned", true)
		var musik := Node.new()
		host.add_child(musik)
		var sheet := RadioSheet.new()
		sheet.gs = gs
		sheet.music = musik
		sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_content(sheet)
		panel.open()
		await wait_frames(4)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var like := panel.find_child("Like", true, false) as Control
		assert_true(like != null, "Like-Knopf existiert (%s)" % str(probe[0]))
		if like != null:
			var rect := like.get_global_rect()
			assert_true(rect.size.x > 0.0, "Like hat Breite (%s)" % str(probe[0]))
			assert_true(rect.position.x >= -0.5, "Like links im Canvas (%s)" % str(probe[0]))
			assert_true(
				rect.end.x <= canvas.x + 0.5,
				(
					"Like läuft rechts NICHT aus dem Canvas (%s): end.x=%f canvas.x=%f"
					% [str(probe[0]), rect.end.x, canvas.x]
				)
			)
			var karte := (panel.get_node("%Sheet") as Control).get_global_rect().grow(1.0)
			assert_true(
				rect.position.x >= karte.position.x and rect.end.x <= karte.end.x,
				"Like bleibt horizontal in der Blatt-Karte (%s)" % str(probe[0])
			)
		panel.close()
		host.queue_free()
		await wait_frames(2)
		PanelStack.clear()
		_unpin()
		await wait_frames(1)
