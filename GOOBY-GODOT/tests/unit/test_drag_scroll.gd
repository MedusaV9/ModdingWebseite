extends TestCase
## FIX-7-Tests (G8-PT3, Befund B1 HOCH): der zentrale DragScroll-Helfer
## (scripts/ui/widgets/drag_scroll.gd) macht Button-volle ScrollContainer
## per Drag scrollbar, ohne Taps zu verändern. Die Events laufen ECHT durch
## Input.parse_input_event (inkl. Emulations-Zwillinge der Projekt-Settings),
## Koordinaten wie in der Probe in Fenster-px (Canvas → final_transform):
## - Drag AUF einem Knopf pannt den Scroller und feuert KEIN pressed
##   (SCROLL_BEGIN-Abbruch des Press — der Engine-Kontrakt).
## - Tap ohne Schwellen-Bewegung drückt exakt 1× und scrollt nicht —
##   auch direkt NACH einem Pann-Zug (Zustand endet sauber).
## - anbinden() ist idempotent (EIN Helfer pro Scroller, null → null).
## Dazu die Nachbar-Fixes des Pakets:
## - B2: font_hover_pressed_color liegt theme-weit auf allen Button-Typen
##   (gedrückt+gehovert fiel sonst aufs Default-WEISS zurück → weiß auf weiß).
## - B3: JuiceKit.float_text_position zentriert am Ereignispunkt und klemmt
##   in die Feld-Fläche („Eine Möhre geklaut!“ ragte rechts raus).

const BUILDER := preload("res://themes/build_theme.gd")

## Zug-Strecke in Canvas-px (deutlich über der 24er-Deadzone).
const DRAG_STRECKE := 220.0
const DRAG_SCHRITTE := 10

var _scroll: ScrollContainer
var _gedrueckt := {"n": 0}

# ── B1: DragScroll-Helfer ────────────────────────────────────────────────────


func test_drag_auf_knopf_pannt_und_feuert_nicht() -> void:
	await _aufbauen()
	await _maus_drag(_knopf_mitte())
	assert_true(
		_scroll.scroll_vertical > 100,
		"Drag auf Knopf muss pannen (scroll_vertical=%d)" % _scroll.scroll_vertical
	)
	assert_eq(int(_gedrueckt["n"]), 0, "während des Pannens darf kein pressed feuern")
	await _abbauen()


func test_tap_ohne_bewegung_drueckt_genau_einmal() -> void:
	await _aufbauen()
	await _maus_tipp(_knopf_mitte())
	assert_eq(int(_gedrueckt["n"]), 1, "Tap ohne Bewegung drückt exakt 1×")
	assert_eq(_scroll.scroll_vertical, 0, "Tap darf nicht scrollen")
	# Nach einem Pann-Zug endet der Helfer-Zustand sauber: der nächste
	# Tap (auf einen JETZT sichtbaren Knopf) drückt wieder exakt 1×.
	await _maus_drag(_knopf_mitte())
	_gedrueckt["n"] = 0
	var stand := _scroll.scroll_vertical
	await _maus_tipp(_knopf_mitte())
	assert_eq(int(_gedrueckt["n"]), 1, "auch nach einem Pann-Zug drückt der Tap exakt 1×")
	assert_eq(_scroll.scroll_vertical, stand, "der Tap nach dem Zug scrollt nicht weiter")
	await _abbauen()


func test_anbinden_ist_idempotent() -> void:
	var scroller := ScrollContainer.new()
	tree.root.add_child(scroller)
	var erster := DragScroll.anbinden(scroller)
	var zweiter := DragScroll.anbinden(scroller)
	assert_true(erster != null, "anbinden liefert den Helfer")
	assert_true(erster == zweiter, "zweites anbinden liefert DENSELBEN Helfer")
	var helfer := scroller.get_children().filter(
		func(kind: Node) -> bool: return kind is DragScroll
	)
	assert_eq(helfer.size(), 1, "genau EIN Helfer-Kind am Scroller")
	assert_true(DragScroll.anbinden(null) == null, "null-Scroller → null, kein Crash")
	scroller.queue_free()
	await wait_frames(1)


func test_anbinden_alle_erreicht_verschachtelte_scroller() -> void:
	# Customize-Bauart: äußere Spalte scrollt vertikal, innen liegt die
	# horizontale Optionen-Zeile — EIN anbinden_alle versorgt beide.
	var wurzel := VBoxContainer.new()
	var aussen := ScrollContainer.new()
	wurzel.add_child(aussen)
	var spalte := VBoxContainer.new()
	aussen.add_child(spalte)
	var innen := ScrollContainer.new()
	spalte.add_child(innen)
	tree.root.add_child(wurzel)
	DragScroll.anbinden_alle(wurzel)
	for scroller: ScrollContainer in [aussen, innen]:
		var helfer := scroller.get_children().filter(
			func(kind: Node) -> bool: return kind is DragScroll
		)
		assert_eq(helfer.size(), 1, "jeder Scroller im Ast trägt genau EINEN Helfer")
	wurzel.queue_free()
	await wait_frames(1)


# ── B2: Theme-Farbe für gedrückt+gehovert ────────────────────────────────────


func test_b2_font_hover_pressed_color_theme_weit() -> void:
	var theme: Theme = BUILDER.build()
	var typen: Array[String] = [
		"Button",
		"BtnPink",
		"BtnTeal",
		"BtnLeaf",
		"BtnYellow",
		"BtnGhost",
		"BtnDanger",
		"PrimaryButton",
		"AccentButton",
		"AcChip",
		"ChipLeaf",
		"ChipSky",
		"HudIconButton",
		"GhostButton",
		"AcCardButton",
		"CheckButton",
	]
	for typ: String in typen:
		assert_true(
			theme.has_color("font_hover_pressed_color", typ),
			"%s braucht font_hover_pressed_color (B2: sonst weiß auf Papierweiß)" % typ
		)
		assert_eq(
			theme.get_color("font_hover_pressed_color", typ),
			theme.get_color("font_pressed_color", typ),
			"%s: hover+pressed trägt die pressed-Textfarbe" % typ
		)


# ── B3: float_text zentriert + geklemmt ──────────────────────────────────────


func test_b3_float_text_position_zentriert_und_klemmt() -> void:
	# Ohne bekannte Grenzen (<= 0): nur zentrieren.
	assert_eq(
		JuiceKit.float_text_position(Vector2(100, 50), Vector2(40, 20), Vector2.ZERO),
		Vector2(80, 40),
		"Ereignispunkt wird Label-MITTE (keine Grenzen bekannt)"
	)
	# Rechter Feldrand: Label bleibt in der Fläche (pt3_c1/041).
	assert_eq(
		JuiceKit.float_text_position(Vector2(195, 50), Vector2(50, 20), Vector2(200, 100)),
		Vector2(150, 40),
		"am rechten Rand klemmt das Label an grenzen.x - text.x"
	)
	# Linke/obere Kante klemmt auf 0 statt negativ.
	assert_eq(
		JuiceKit.float_text_position(Vector2(2, 3), Vector2(50, 20), Vector2(200, 100)),
		Vector2.ZERO,
		"links/oben klemmt auf 0"
	)
	# Text breiter als das Feld: an 0 geklemmt (nie negatives Maximum).
	assert_eq(
		JuiceKit.float_text_position(Vector2(20, 50), Vector2(60, 20), Vector2(40, 100)),
		Vector2(0, 40),
		"Übertext klemmt an 0 statt an negativer Grenze"
	)


# ── Bausteine (Muster der Minimal-Probe pt3_scroll_probe.gd) ─────────────────


## Nackter Scroller voller Knöpfe mit Arcade-Deadzone + DragScroll-Helfer.
func _aufbauen() -> void:
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(40, 40)
	_scroll.size = Vector2(360, 420)
	_scroll.scroll_deadzone = 24
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	for i in 30:
		var knopf := Button.new()
		knopf.text = "Knopf %d" % i
		knopf.custom_minimum_size = Vector2(280, 56)
		knopf.pressed.connect(func() -> void: _gedrueckt["n"] += 1)
		box.add_child(knopf)
	tree.root.add_child(_scroll)
	DragScroll.anbinden(_scroll)
	_gedrueckt["n"] = 0
	await wait_frames(2)


func _abbauen() -> void:
	_scroll.queue_free()
	_scroll = null
	await wait_frames(1)


## Fenster-px der Mitte eines Knopfs, dessen Mitte GERADE SICHTBAR im
## Scroller liegt (nach dem Pannen rutschen die ersten aus dem Fenster).
func _knopf_mitte() -> Vector2:
	var fenster := _scroll.get_global_rect()
	for kind in _scroll.get_child(0).get_children():
		if not (kind is Button):
			continue
		var mitte := (kind as Control).get_global_rect().get_center()
		if fenster.has_point(mitte):
			return _px(mitte)
	return _px(fenster.get_center())


## Canvas-Punkt → Fenster-px (Input.parse_input_event spricht Fenster-px;
## der Stretch rechnet sie beim Zustellen wieder in Canvas um).
func _px(canvas: Vector2) -> Vector2:
	return tree.root.get_final_transform() * canvas


func _maus_drag(von: Vector2) -> void:
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = von
	runter.global_position = von
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(runter)
	var schritt := Vector2(0.0, -_px(Vector2(0.0, DRAG_STRECKE)).y / float(DRAG_SCHRITTE))
	var pos := von
	for i in DRAG_SCHRITTE:
		await wait_frames(1)
		pos += schritt
		var zug := InputEventMouseMotion.new()
		zug.position = pos
		zug.global_position = pos
		zug.relative = schritt
		zug.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(zug)
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = pos
	hoch.global_position = pos
	Input.parse_input_event(hoch)
	await wait_frames(2)


func _maus_tipp(pos: Vector2) -> void:
	# Hover zuerst: BaseButton drückt nur mit mouse_over (wie ein echter Zeiger).
	var beweg := InputEventMouseMotion.new()
	beweg.position = pos
	beweg.global_position = pos
	Input.parse_input_event(beweg)
	await wait_frames(1)
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = pos
	runter.global_position = pos
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(runter)
	await wait_frames(2)
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = pos
	hoch.global_position = pos
	Input.parse_input_event(hoch)
	await wait_frames(2)
