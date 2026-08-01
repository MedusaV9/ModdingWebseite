class_name GvzOverlay
extends RefCounted
## End-Overlays der GvZ-Spielszene (G5/P26-Split + End-Overlay Stufe 2,
## P20-Restpunkt): Dim + AcCardLg-Plate mittig (MG-Audit B §2, seit G4),
## jetzt mit FeelStarRow-Sterne-Pop (Reduced Motion: sofort still) und
## Icon-Knöpfen (SVG in Ink, Daumenzone, Touch-Floor). `view` ist
## gvz_game.gd (Duck-Typing wie gvz_hud.gd): liefert _overlay-Verwaltung,
## Navigation (open_level/back_to_select) und netz_session.

const ICON_DIR := "res://assets/ui/icons/"

var view


func _init(game_view: CanvasItem) -> void:
	view = game_view


## Kampagnen-Ende: Sieg feiert mit Sterne-Pop, Niederlage gibt einen Tipp;
## Weiter/Nochmal/Level-Wahl als Icon-Knöpfe.
func build_end(won: bool, stars: int, total: int, first_clear: bool) -> void:
	var box := _plate()
	box.add_child(_title(I18nService.t("gvz.end.win" if won else "gvz.end.lose")))
	if won:
		_add_star_row(box, stars)
	var info := Label.new()
	info.theme_type_variation = &"CaptionLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if won:
		info.text = I18nService.t("gvz.end.score", {"n": total})
		if first_clear:
			info.text += "\n" + I18nService.t("gvz.end.first_clear")
	else:
		info.text = I18nService.t("gvz.end.lose_hint")
	box.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var level_id := int(view.level_id)
	if won and level_id < GvzProgress.LEVEL_COUNT:
		row.add_child(
			_button("gvz.end.next", "arrow_right", func() -> void: view.open_level(level_id + 1))
		)
	if not won:
		row.add_child(
			_button("gvz.end.retry", "sparkle", func() -> void: view.open_level(level_id))
		)
	row.add_child(_button("gvz.end.select", "home", func() -> void: view.back_to_select()))
	_center()


## Netz-PvP-Ende: Sieger-Ansage mit Partnernamen; Revanche läuft über das
## wieder freie Panel im Level-Select (Muster gobnom — kein lokales Retry,
## das liefe am Partner vorbei).
func build_netz_end(won: bool) -> void:
	var box := _plate()
	var partner := str(view.netz_session.partner_gooby_name) if view.netz_session != null else "?"
	box.add_child(
		_title(I18nService.t("gvz.end.netz_win" if won else "gvz.end.netz_lose", {"name": partner}))
	)
	if won:
		_add_star_row(box, 3)
	var info := Label.new()
	info.theme_type_variation = &"CaptionLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = I18nService.t("gvz.end.netz_hint", {"name": partner})
	box.add_child(info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_button("gvz.end.select", "home", func() -> void: view.back_to_select()))
	_center()


## ── Interne Bau-Helfer ───────────────────────────────────────────────────


func _title(text: String) -> Label:
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


## Sterne-Pop (P20 Stufe 2): FeelStarRow ploppt earned Sterne gestaffelt
## ein — unter Reduced Motion stehen sie sofort still da (RM-gegated).
func _add_star_row(box: VBoxContainer, earned: int) -> void:
	var star_row := FeelStarRow.new()
	star_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(star_row)
	star_row.reveal(earned, ThemeService.is_reduced_motion(view))


## Overlay-Grundgerüst (Dim + AcCardLg-Plate): liefert die Inhalts-Spalte.
## Das Overlay-Control selbst verwaltet die Szene (view._overlay).
func _plate() -> VBoxContainer:
	view._clear_overlay()
	var root := Control.new()
	view.add_child(root)
	view._overlay = root
	var dim := ColorRect.new()
	dim.color = Color(0.24, 0.16, 0.12, 0.55)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Plate"
	panel.theme_type_variation = &"AcCardLg"
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var vp: Vector2 = view._view_size()
	root.size = vp
	dim.size = vp
	return box


## Nach dem Befüllen: Fonts skalieren und die Plate mittig setzen.
func _center() -> void:
	var panel: PanelContainer = (view._overlay as Control).get_node("Plate")
	ScreenShell.scale_fonts(panel, ScreenShell.metrics(view.get_viewport())["f"])
	panel.size = panel.get_combined_minimum_size()
	panel.position = (((view._view_size() as Vector2) - panel.size) * 0.5).floor()


## Icon-Knopf fürs End-Overlay (Stufe 2): SVG-Icon in Ink vor dem Text.
func _button(key: String, icon_name: String, action: Callable) -> Button:
	var button := SquishButton.new()
	button.text = I18nService.t(key)
	if icon_name != "":
		button.icon = load("%s%s.svg" % [ICON_DIR, icon_name])
		button.expand_icon = false
		for state_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
			button.add_theme_color_override(state_name, AcTokens.INK)
	button.custom_minimum_size = Vector2(104, 48)
	ScreenShell.touch_target(button, ScreenShell.metrics(view.get_viewport()))
	button.pressed.connect(func() -> void: AudioDirector.try_play(button, "ui_click"))
	button.pressed.connect(action)
	return button
