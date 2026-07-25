extends W1cTestCase
## Theme-Tokens exakt gegen styles.css-Werte + Struktur des gebauten Themes
## + Smoke der übrigen UI-Bausteine (Sheet-Stack-Policy, Toast-Layer, Bubble,
## Settings, News-Panel).

const BUILDER := preload("res://themes/build_theme.gd")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
const BUBBLE_SCENE := preload("res://scripts/ui/dialog_bubble.tscn")
const SETTINGS_SCENE := preload("res://scripts/ui/settings_screen.tscn")
const NEWS_SCENE := preload("res://scripts/ui/news_50_panel.tscn")

## Unabhängige Zweitquelle: Hex-Werte 1:1 aus GOOBY/src/ui/styles.css.
const CSS_TOKENS := {
	"BG_CREAM": "fff6ec",
	"PAPER": "fffaf2",
	"PAPER_SHADE": "f6ead8",
	"PINK": "ff7ba9",
	"PINK_DARK": "e05f8d",
	"TEAL": "59c9b9",
	"TEAL_DARK": "3fa89a",
	"YELLOW": "ffd166",
	"YELLOW_DARK": "e0b04a",
	"LEAF": "8fd06c",
	"LEAF_DARK": "6db54e",
	"SKY_SOFT": "cfe9f5",
	"GOLD": "ffd34d",
	"DANGER": "e0655f",
	"INK": "4a3b36",
	"STAT_HUNGER": "ff9f5a",
	"STAT_ENERGY": "ffd166",
	"STAT_HYGIENE": "6ec6ff",
	"STAT_FUN": "ff7ba9",
}


func test_farb_tokens_exakt_aus_styles_css() -> void:
	for token: String in CSS_TOKENS:
		var expected := Color(CSS_TOKENS[token])
		check_eq(
			ThemeService.color(token).to_html(false),
			expected.to_html(false),
			"Token %s == #%s" % [token, CSS_TOKENS[token]]
		)
	check_approx(AcTokens.INK_SOFT.a, 0.72, "INK_SOFT Alpha 72 %")
	check_approx(AcTokens.INK_FAINT.a, 0.55, "INK_FAINT Alpha 55 %")
	check_approx(AcTokens.TRACK_SOFT.a, 0.10, "TRACK_SOFT Alpha 10 %")
	check_approx(AcTokens.VEIL.a, 0.35, "VEIL Alpha 35 %")
	check_eq(AcTokens.RADIUS_CARD, 28, "Karten-Radius 28")
	check_eq(AcTokens.RADIUS_CARD_LG, 36, "Große Karte 36")
	check_eq(AcTokens.RADIUS_ROW, 14, "Row-Radius 14")
	check_approx(AcTokens.DUR_POP, 0.18, "Pop-Dauer 0.18 s")
	check_approx(AcTokens.DUR_SHEET, 0.24, "Sheet-Dauer 0.24 s")
	check_approx(AcTokens.DRIFT_OPACITY, 0.06, "Drift-Deckkraft 6 %")


func test_theme_struktur_und_styleboxen() -> void:
	var theme := BUILDER.build()
	for type in [
		"Button",
		"BtnPink",
		"BtnTeal",
		"BtnLeaf",
		"BtnYellow",
		"BtnGhost",
		"AcChip",
		"ChipLeaf",
		"ChipSky",
		"HudIconButton",
		"AcCard",
		"AcCardLg",
		"AcWell",
		"StatusCapsule",
		"DialogBubble",
		"TitleLabel",
		"CaptionLabel",
		"StatHunger",
		"StatEnergy",
		"StatHygiene",
		"StatFun",
	]:
		check(theme.get_type_list().has(type), "Theme-Typ %s existiert" % type)
	var pink := theme.get_stylebox("normal", "BtnPink") as StyleBoxFlat
	check_eq(pink.bg_color.to_html(false), "ff7ba9", "BtnPink-Fill = PINK")
	check_eq(pink.border_width_bottom, 4, "Pill hat 4-px-Boden-Lippe")
	var lip := AcTokens.lip_color(AcTokens.PINK)
	check_eq(pink.border_color.to_html(false), lip.to_html(false), "Lippe = Fill × 0.82")
	var pressed := theme.get_stylebox("pressed", "BtnPink") as StyleBoxFlat
	check_eq(pressed.border_width_bottom, 2, "Pressed: Lippe 2 px")
	check(pressed.content_margin_top > pink.content_margin_top, "Pressed: Content rückt nach unten")
	var card := theme.get_stylebox("panel", "AcCard") as StyleBoxFlat
	check_eq(card.bg_color.to_html(false), "fffaf2", "AcCard = PAPER")
	check_eq(card.corner_radius_top_left, 28, "AcCard-Radius 28")
	check_eq(card.shadow_size, 10, "AcCard-Schatten 10")
	var well := theme.get_stylebox("panel", "AcWell") as StyleBoxFlat
	check_eq(well.bg_color.to_html(false), "f6ead8", "AcWell = PAPER_SHADE")
	check_eq(well.shadow_size, 0, "AcWell ohne Schatten")
	var hunger_fill := theme.get_stylebox("fill", "StatHunger") as StyleBoxFlat
	check_eq(hunger_fill.bg_color.to_html(false), "ff9f5a", "StatHunger-Fill")
	check_eq(theme.default_font_size, 20, "Default-Fontgröße")
	check(theme.default_font != null, "Baloo-2-Font eingebunden")


func test_sheet_stack_backdrop_policy() -> void:
	PanelStack.clear()
	var lower: PanelSheet = SHEET_SCENE.instantiate()
	var upper: PanelSheet = SHEET_SCENE.instantiate()
	mount(lower)
	mount(upper)
	await tree.process_frame
	lower.open()
	upper.open()
	check_eq(PanelStack.count(), 2, "beide Sheets im Stack")
	check(PanelStack.is_top(upper), "oberes Sheet ist top")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	lower.get_node("%Backdrop").gui_input.emit(click)
	check(lower.is_open(), "Backdrop-Tap aufs UNTERE Sheet schließt es NICHT")
	upper.get_node("%Backdrop").gui_input.emit(click)
	check(not upper.is_open(), "Backdrop-Tap aufs OBERE Sheet schließt es")
	check(PanelStack.is_top(lower), "unteres Sheet rückt nach oben")
	lower.get_node("%Backdrop").gui_input.emit(click)
	check(not lower.is_open(), "jetzt schließt auch das untere")
	check_eq(PanelStack.count(), 0, "Stack leer")
	unmount(lower)
	unmount(upper)


func test_toast_layer_zeigt_nie_zwei() -> void:
	var layer := ToastLayer.new()
	mount(layer)
	await tree.process_frame
	layer.show_toast("Erster")
	layer.show_toast("Zweiter")
	await tree.process_frame
	await tree.process_frame
	check(layer.is_showing(), "ein Toast sichtbar")
	check_eq(layer.queue.current(), "Erster", "der erste zuerst")
	check_eq(layer.queue.pending_count(), 1, "zweiter wartet in der Queue")
	var panels := 0
	for child in layer.get_children():
		if child is PanelContainer and (child as PanelContainer).visible:
			panels += 1
	check_eq(panels, 1, "es existiert genau EIN sichtbares Toast-Panel")
	unmount(layer)


func test_dialog_bubble_weiter_tap() -> void:
	var bubble := BUBBLE_SCENE.instantiate()
	mount(bubble)
	await tree.process_frame
	var finished := [false]
	bubble.finished.connect(func() -> void: finished[0] = true)
	var lines: Array[String] = ["Zeile 1", "Zeile 2"]
	bubble.show_lines(lines)
	check(bubble.is_active(), "Bubble aktiv")
	check_eq(bubble.current_line(), "Zeile 1", "erste Zeile sichtbar")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	bubble.get_node("%Bubble").gui_input.emit(click)
	check_eq(bubble.current_line(), "Zeile 2", "Tap blättert weiter")
	bubble.get_node("%Bubble").gui_input.emit(click)
	check(finished[0], "finished nach letzter Zeile")
	check(not bubble.visible, "Bubble versteckt sich")
	unmount(bubble)


func test_audio_slider_schreibt_appsettings() -> void:
	# W4P1-SFX-Wiring-Hinweis: die Audio-Slider müssen die W1a-FROZEN-Keys
	# audio.* in AppSettings schreiben, sonst liest AudioDirector
	# (audio_level) ins Leere und die Regler bleiben wirkungslos.
	var app := tree.root.get_node_or_null("/root/AppSettings")
	if app == null:
		return  # isolierter Lauf ohne Autoloads
	var vorher: float = app.audio_level("sfx")
	var settings := SETTINGS_SCENE.instantiate()
	mount(settings)
	await tree.process_frame
	var slider := settings.find_child("RowVolumeSfx", true, false).get_node("Value") as HSlider
	check_approx(slider.value, vorher, "Slider startet auf dem AppSettings-Wert")
	slider.value_changed.emit(0.35)
	check_approx(app.audio_level("sfx"), 0.35, "Slider schreibt audio.sfx")
	check_approx(float(settings.get_value("volume_sfx")), 0.35, "lokaler Spiegel zieht mit")
	app.set_setting("audio.sfx", vorher)
	unmount(settings)


func test_settings_und_news_smoke() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	mount(settings)
	await tree.process_frame
	check(
		settings.find_child("SectionAllgemein", true, false) != null, "Sektion Allgemein existiert"
	)
	check(settings.find_child("SectionAudio", true, false) != null, "Sektion Audio")
	check(settings.find_child("SectionUpdates", true, false) != null, "Sektion Updates")
	check(settings.find_child("SectionUeber", true, false) != null, "Sektion Über")
	var update_requests := [0]
	settings.update_check_requested.connect(func() -> void: update_requests[0] += 1)
	var update_btn := settings.find_child("UpdateCheckButton", true, false) as Button
	update_btn.pressed.emit()
	check_eq(update_requests[0], 1, "Update-Signal feuert")
	await tree.process_frame
	await tree.process_frame
	# Seit W2b existiert der echte UpdateManager als Autoload: der Knopf
	# startet dann den echten Check (kein »bald«-Platzhalter-Toast mehr).
	# Ohne Autoload (isolierter Testlauf) bleibt der Platzhalter-Toast Pflicht.
	if settings.get_node_or_null("/root/UpdateManager") == null:
		var toast := settings.get_node("%Toast") as ToastLayer
		check(toast.is_showing(), "»bald«-Toast erscheint ohne UpdateManager")
	var news: News50Panel = NEWS_SCENE.instantiate()
	mount(news)
	await tree.process_frame
	var seen := [0]
	news.news_seen.connect(func() -> void: seen[0] += 1)
	news.open()
	check(news.is_open(), "News-Panel öffnet")
	for i in 6:
		check(news.find_child("Item%d" % i, true, false) != null, "News-Highlight %d vorhanden" % i)
	(news.find_child("NewsOkButton", true, false) as Button).pressed.emit()
	check_eq(seen[0], 1, "news_seen feuert")
	check(not news.is_open(), "News-Panel schließt")
	unmount(news)
	unmount(settings)
