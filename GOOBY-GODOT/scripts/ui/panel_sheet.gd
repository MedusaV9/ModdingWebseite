class_name PanelSheet
extends Control
## Bottom-Sheet im AC-2.0-Look: Veil-Backdrop + Paper-Karte (Radius 36),
## die von unten hereinfedert. Backdrop-Dismiss-Policy wie im Web:
## ein Tap auf den Backdrop schließt NUR das oberste Sheet (`PanelStack`).
##
## FIX1-Umbau (P0 „Panels überdecken alles / Patchnotes broken“):
## - Das Blatt ist ein ZENTRIERTES, breiten-gedeckeltes Sheet über der
##   Abdunkelung — HUD bleibt sichtbar, aber der Backdrop frisst Input.
## - Geometrie kommt aus der puren `PanelSheetLayout` (Safe-Area-Klemmung,
##   Höhen-Deckel); längerer Inhalt scrollt in `%SheetScroll` statt aus dem
##   Bildschirm zu wachsen (das war der Patchnotes-Totalausfall).
## - Schrift/Ränder skalieren mit `UiScale.for_viewport()` (kurze Kante).
## - Escape/Back-Geste schließt das oberste Sheet (SceneRouter → PanelStack).
##
## Nutzung: Szene `panel_sheet.tscn` instanzieren, `add_content(node)`,
## dann `open()`. `closed`-Signal abonnieren.

signal opened
signal closed

## Innenabstand des Sheet-Bodys (Design-px, skaliert mit UiScale).
const BODY_MARGIN := 8.0

## Notch-Simulation für Tests (Rect2() = aus → DisplayServer fragen).
var safe_area_override := Rect2()

var _open := false

@onready var _backdrop: ColorRect = %Backdrop
@onready var _sheet: PanelContainer = %Sheet
@onready var _title_label: Label = %SheetTitle
@onready var _scroll: ScrollContainer = %SheetScroll
@onready var _body: MarginContainer = %SheetBody
@onready var _grab_handle: Panel = %GrabHandle


func _ready() -> void:
	visible = false
	_backdrop.color = AcTokens.VEIL
	_backdrop.gui_input.connect(_on_backdrop_input)
	_style_grab_handle()
	get_viewport().size_changed.connect(_on_viewport_resized)


## UICOZY: Grabber-Pill wie Web .panel::before (44×5 px, Radius 999,
## rgba(74,59,54,.16)) — vorher ein eckiges ColorRect.
func _style_grab_handle() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(AcTokens.INK, 0.16)
	sb.set_corner_radius_all(AcTokens.RADIUS_PILL)
	_grab_handle.add_theme_stylebox_override("panel", sb)


## Titel setzen ("" blendet die Titelzeile aus).
func set_title(text: String) -> void:
	_title_label.text = text
	_title_label.visible = not text.is_empty()


## Inhalt einhängen (ersetzt vorherigen Inhalt).
func add_content(node: Control) -> void:
	for child in _body.get_children():
		child.queue_free()
	_body.add_child(node)
	if _open:
		_relayout()


func open() -> void:
	if _open:
		return
	AudioDirector.try_play(self, "ui_open")
	_open = true
	visible = true
	PanelStack.push(self)
	_relayout()
	opened.emit()
	if ThemeService.is_reduced_motion(self):
		_backdrop.modulate.a = 1.0
		_sheet.modulate.a = 1.0
		return
	# UICOZY: Backdrop blendet weich ein (Web polishd-backdrop-in), das
	# Blatt federt von unten herein (Web panel-up, --ease-spring).
	_backdrop.modulate.a = 0.0
	_sheet.position.y += 60.0
	_sheet.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sheet, "position:y", _sheet.position.y - 60.0, AcTokens.DUR_SHEET)
	tween.tween_property(_sheet, "modulate:a", 1.0, AcTokens.DUR_SHEET / 2.0)
	tween.tween_property(_backdrop, "modulate:a", 1.0, AcTokens.DUR_SHEET / 2.0).set_trans(
		Tween.TRANS_LINEAR
	)


func close() -> void:
	if not _open:
		return
	AudioDirector.try_play(self, "ui_close")
	_open = false
	PanelStack.remove(self)
	visible = false
	closed.emit()


func is_open() -> bool:
	return _open


## Breite des Sheet-Chromes (Karten-StyleBox + Body-Ränder) in Canvas-px:
## Inhalt darf höchstens `PanelSheetLayout.sheet_width() - chrome_width()`
## breit bauen, sonst wird er rechts abgeschnitten (SheetScroll scrollt
## bewusst NUR vertikal). FIX1: Content-Builder (z. B. Status-Sheet) fragen
## das ab, statt feste Breiten zu erzwingen.
func chrome_width() -> float:
	var f := UiScale.for_viewport(get_viewport())
	var chrome := 2.0 * BODY_MARGIN * f
	var style := _sheet.get_theme_stylebox("panel")
	if style != null:
		chrome += style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	return chrome


## Geometrie neu anwenden (open/resize; Tests rufen es direkt).
## Zwei-Pass: erst Wunschhöhe aus dem Inhalt messen, dann per
## `PanelSheetLayout.sheet_rect` klemmen — Überschuss scrollt.
func _relayout() -> void:
	var vp := get_viewport()
	if vp == null or _sheet == null:
		return
	var canvas := Vector2(vp.get_visible_rect().size)
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp, safe_area_override)
	_apply_scale(f)
	# Pass 1: Chrome (Karte + Handle + Titel) ohne Scroll-Inhalt messen.
	_scroll.custom_minimum_size = Vector2.ZERO
	var chrome_h := _sheet.get_combined_minimum_size().y
	var content_min := _body.get_combined_minimum_size()
	var desired_h := chrome_h + content_min.y
	var rect := PanelSheetLayout.sheet_rect(canvas, insets, f, desired_h)
	# Pass 2: Scroll-Fenster auf den verfügbaren Innenraum setzen.
	var inner_h := maxf(rect.size.y - chrome_h, 0.0)
	_scroll.custom_minimum_size = Vector2(0.0, minf(content_min.y, inner_h))
	_sheet.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sheet.offset_left = rect.position.x
	_sheet.offset_top = rect.position.y
	_sheet.offset_right = rect.position.x + rect.size.x
	_sheet.offset_bottom = rect.position.y + rect.size.y


func _apply_scale(f: float) -> void:
	_title_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * f))
	# Grabber-Pill skaliert mit (Web: 2.75rem × 0.3125rem = 44×5 Design-px).
	_grab_handle.custom_minimum_size = Vector2(roundf(44.0 * f), maxf(roundf(5.0 * f), 4.0))
	var pad := int(BODY_MARGIN * f)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		_body.add_theme_constant_override(side, pad)


func _on_viewport_resized() -> void:
	if _open:
		_relayout()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if PanelStack.is_top(self):
			close()
