class_name HudCoachmark
extends PanelContainer
## Erststart-Coachmark „Deine Knöpfe“ (FIX1, aus hud.gd ausgelagert —
## W20 P1 hielt die 1000-Zeilen-Lint-Schranke): erklärt die Cockpit-
## Spalte einmalig und merkt sich das über AppSettings
## `hints.hud_actions_seen`. Das HUD hängt die Karte ein, verbindet
## `minimum_size_changed` auf seinen Positions-Pass und hört `dismissed`.

signal dismissed

## AppSettings-Key: Coachmark „Deine Knöpfe“ schon gezeigt?
const SEEN_KEY := "hints.hud_actions_seen"
## Physisches Tippflächen-Minimum in pt (wie Hud.TOUCH_MIN_PT).
const TOUCH_MIN_PT := 46.0
const EDGE_PAD := 8.0


## Baut die Karte, wenn sie dran ist (Querformat, sichtbares HUD, Key noch
## nicht gesetzt) — sonst null. Der Aufrufer (HUD) macht add_child + Pop-in.
static func vielleicht_anzeigen(hud: Control, portrait: bool) -> HudCoachmark:
	if not hud.visible or not hud.is_inside_tree() or portrait:
		return null
	var settings := hud.get_node_or_null("/root/AppSettings")
	if settings == null or not settings.has_method("get_setting"):
		return null
	if bool(settings.get_setting(SEEN_KEY, false)):
		return null
	var karte := HudCoachmark.new()
	karte._baue(hud.get_viewport())
	return karte


func _baue(viewport: Viewport) -> void:
	var f := UiScale.for_viewport(viewport)
	name = "HudCoachmark"
	theme_type_variation = &"AcCard"
	# W20 P1 Nachfix (FB3 „Toast×Guide“): Coachmark-Karte ist Toast-
	# Hindernis — Toasts rutschen unter sie statt auf den OK-Knopf.
	add_to_group(ToastLayer.HINDERNIS_GROUP)
	custom_minimum_size = Vector2(280.0 * f, 0.0)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(12.0 * f))
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(8.0 * f))
	margin.add_child(vbox)
	var title := Label.new()
	title.theme_type_variation = "HeadlineLabel"
	title.text = I18nService.t("hud.coachmark_titel")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)
	var body := Label.new()
	body.name = "CoachmarkText"
	body.theme_type_variation = "CaptionLabel"
	body.text = I18nService.t("hud.coachmark_text")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	var ok := SquishButton.new()
	ok.name = "CoachmarkOk"
	ok.theme_type_variation = "BtnLeaf"
	ok.text = I18nService.t("hud.coachmark_ok")
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.focus_mode = Control.FOCUS_NONE
	# FB3-Regel: physische Tippflaeche >= 44 pt (nicht Design-Pixel!) —
	# `touch_px_per_pt` legt denselben physischen Massstab an wie die
	# UI-Pruefung (touch_floor_canvas unterschreitet auf dichten Displays).
	var touch_floor := UiScale.touch_px_per_pt(viewport) * TOUCH_MIN_PT
	ok.custom_minimum_size = Vector2(maxf(120.0 * f, touch_floor), touch_floor)
	ok.pressed.connect(_on_ok)
	vbox.add_child(ok)


## Links neben die Cockpit-Spalte setzen (vertikal mittig). `insets` liefert
## das HUD (inkl. Test-Override), `spalten_breite` = Cockpit-Spaltenbreite.
func positioniere(insets: Dictionary, spalten_breite: float) -> void:
	if not is_inside_tree():
		return
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var ok_btn := find_child("CoachmarkOk", true, false) as Control
	if ok_btn != null:
		var floor_px := UiScale.touch_px_per_pt(get_viewport()) * TOUCH_MIN_PT
		ok_btn.custom_minimum_size = Vector2(maxf(ok_btn.custom_minimum_size.x, floor_px), floor_px)
	reset_size()
	var groesse := get_combined_minimum_size()
	# Autowrap-Labels melden im ERSTEN Layout-Pass eine viel zu grosse Hoehe
	# (Godot kennt die Zeilenumbrueche noch nicht). Ungeklemmt schiebt das die
	# Karte weit ueber den Bildrand hinaus — deshalb hart in den sicheren
	# Bereich klemmen und nach dem Settle erneut setzen.
	var top := float(insets["top"]) + EDGE_PAD
	var bottom := canvas.y - float(insets["bottom"]) - EDGE_PAD
	var left := float(insets["left"]) + EDGE_PAD
	var right := canvas.x - float(insets["right"]) - EDGE_PAD
	groesse.x = minf(groesse.x, maxf(right - left, 1.0))
	groesse.y = minf(groesse.y, maxf(bottom - top, 1.0))
	size = groesse
	var x := canvas.x - float(insets["right"]) - EDGE_PAD - spalten_breite - 16.0 - groesse.x
	var y := (canvas.y - groesse.y) / 2.0
	position = Vector2(
		clampf(x, left, maxf(right - groesse.x, left)),
		clampf(y, top, maxf(bottom - groesse.y, top))
	)


func _on_ok() -> void:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("set_setting"):
		settings.set_setting(SEEN_KEY, true)
	dismissed.emit()
	queue_free()
