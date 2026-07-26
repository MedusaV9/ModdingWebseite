class_name ToastLayer
extends Control
## Sichtbarer Toast-Layer: genau EIN Toast gleichzeitig (Queue in
## `ToastQueue`, pure Logik). In eine Screen-Szene legen (Full-Rect,
## oberste UI-Ebene) und `show_toast("…")` rufen.
##
## UICOZY (Web .toast): Paper-Bubble mit Leaf-Akzent statt Frost-Pill —
## Radius 22, Outline-Ring + Shadow-Pop, Ink-Text 700; federt mit kleinem
## Hüpfer herein (@keyframes toast-in) und sinkt beim Ausblenden sanft ab
## (.toast-out). Größen skalieren über die ZENTRALE `UiScale`-Regel.

const HOLD_SEC := 2.2
const FADE_SEC := 0.25
## Web .toast: font-size 1rem (16), Leaf-Glyph 11 px, Gap 8 px, max-width
## min(86vw, 22rem = 352 px) — alles Design-px, skaliert mit UiScale.
const FONT_PX := 16.0
const LEAF_PX := 13.0
const GAP_PX := 8.0
const MAX_WIDTH_PX := 352.0
## Vertikale Ankerhöhe (Anteil der Canvas-Höhe, unter den Status-Pills).
const TOP_SHARE := 0.12

var queue := ToastQueue.new()

var _panel: PanelContainer
var _label: Label
var _leaf: TextureRect
var _hold_timer: Timer
var _in_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "ToastPanel"
	_panel.theme_type_variation = "ToastBubble"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.z_index = 100
	add_child(_panel)
	var box := HBoxContainer.new()
	box.name = "ToastBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_leaf = TextureRect.new()
	_leaf.name = "ToastLeaf"
	_leaf.texture = load("res://assets/ui/icons/leaf.svg")
	_leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_leaf.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leaf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_leaf)
	_label = Label.new()
	_label.name = "ToastText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrap bleibt AUS, bis _reposition Überbreite misst — ein Label MIT
	# Autowrap meldet ~1 Zeichen Minimalbreite, und Godots verzögerte
	# Min-Size-Durchsetzung würde die Bubble sonst zum Hochkant-Turm ziehen.
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_done)
	add_child(_hold_timer)


## Toast anfordern; wird ggf. eingereiht (nie gestapelt). `error = true`
## spielt den Fehler-Blip (W4P1-SFX-Wiring: Erfolgs-Toasts bleiben stumm).
func show_toast(text: String, error := false) -> void:
	var accepted := queue.push(text)
	if accepted and error:
		AudioDirector.try_play(self, "ui_error")
	if accepted and queue.current().is_empty():
		_show_next()


func is_showing() -> bool:
	return _panel != null and _panel.visible


func _show_next() -> void:
	var text := queue.advance()
	if text.is_empty():
		_panel.visible = false
		return
	_apply_scale()
	_label.text = text
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size = Vector2.ZERO
	_panel.visible = true
	_panel.reset_size()
	_reposition()
	_hold_timer.start(HOLD_SEC)


## Web-Maße auf den Canvas skalieren (zentrale UiScale-Regel, FIX1).
func _apply_scale() -> void:
	var f := UiScale.for_viewport(get_viewport())
	_label.add_theme_font_size_override("font_size", int(FONT_PX * f))
	if ThemeService.font(700) != null:
		_label.add_theme_font_override("font", ThemeService.font(700))
	_leaf.custom_minimum_size = Vector2.ONE * roundf(LEAF_PX * f)
	var box := _panel.get_node("ToastBox") as HBoxContainer
	box.add_theme_constant_override("separation", int(GAP_PX * f))


func _reposition() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_panel) or not _panel.visible:
		return
	var f := UiScale.for_viewport(get_viewport())
	# Layer kann im ersten Frame noch 0-groß sein (frisch gemountet).
	var area := size
	if area.x <= 1.0:
		area = Vector2(get_viewport().get_visible_rect().size)
	# Breiten-Deckel wie Web (min(86vw, 22rem)); langer Text wickelt um.
	# Godot-Falle: MIT Autowrap meldet das Label ~1 Zeichen Minimalbreite —
	# deshalb erst OHNE Wrap die natürliche Breite messen und nur bei
	# Überbreite auf den Deckel klemmen.
	var max_w := minf(area.x * 0.86, MAX_WIDTH_PX * f)
	var natural := _panel.get_combined_minimum_size()
	if natural.x > max_w:
		var chrome := natural.x - _label.get_combined_minimum_size().x
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size = Vector2(maxf(max_w - chrome, 40.0), 0.0)
		await get_tree().process_frame
		if not is_instance_valid(_panel) or not _panel.visible:
			return
		natural = Vector2(max_w, _panel.get_combined_minimum_size().y)
	_panel.size = natural
	# FB3: nie hinter die Notch — Ankerhöhe mindestens Safe-Top + Luft.
	var insets := UiScale.safe_insets_canvas(get_viewport())
	var top := maxf(area.y * TOP_SHARE, float(insets["top"]) + 8.0 * f)
	var rest := Vector2((area.x - natural.x) / 2.0, top)
	_panel.position = rest
	_animate_in(rest, f)


## Web @keyframes toast-in: von +12 px / Scale 0.9 federnd auf Position.
func _animate_in(rest: Vector2, f: float) -> void:
	if _in_tween != null and _in_tween.is_valid():
		_in_tween.kill()
	if ThemeService.is_reduced_motion(self):
		_panel.modulate.a = 1.0
		_panel.scale = Vector2.ONE
		return
	_panel.pivot_offset = _panel.size / 2.0
	_panel.position = rest + Vector2(0.0, 12.0 * f)
	_panel.scale = Vector2.ONE * 0.9
	_panel.modulate.a = 0.0
	_in_tween = create_tween().set_parallel()
	_in_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_in_tween.tween_property(_panel, "position:y", rest.y, AcTokens.DUR_POP)
	_in_tween.tween_property(_panel, "scale", Vector2.ONE, AcTokens.DUR_POP)
	_in_tween.tween_property(_panel, "modulate:a", 1.0, AcTokens.DUR_POP / 2.0).set_trans(
		Tween.TRANS_LINEAR
	)


func _on_hold_done() -> void:
	if ThemeService.is_reduced_motion(self):
		_show_next()
		return
	# Web .toast-out: absinken + ausblenden, dann nächster aus der Queue.
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "modulate:a", 0.0, FADE_SEC)
	tween.tween_property(_panel, "position:y", _panel.position.y + 8.0, FADE_SEC)
	tween.chain().tween_callback(_show_next)
	tween.chain().tween_callback(func() -> void: _panel.modulate.a = 1.0)
