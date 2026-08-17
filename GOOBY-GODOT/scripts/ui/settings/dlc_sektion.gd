class_name DlcSektion
extends RefCounted
## Settings-Sektion „DLC“ (W14/DLCHUB) — EIGENE Datei, damit
## settings_screen.gd nur EINE Andock-Zeile braucht (Koordination mit
## W14/UISCREENS-A). Baut die AcCard-Sektion im Settings-Muster
## (_add_section-Optik nachgebaut, ohne private Screen-Helfer zu rufen)
## und führt in die DLC-Bibliothek (DlcScreen, Route `dlc`).


## Vom SettingsScreen mit dessen aktuellen Skalierungs-Faktoren gerufen:
## f = UiScale-Faktor, tf = Font-Faktor.
static func baue(screen: Control, sections: VBoxContainer, f: float, tf: float) -> void:
	var card := PanelContainer.new()
	card.name = "SectionDlc"
	card.theme_type_variation = "AcCard"
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	sections.add_child(card)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_theme_constant_override("separation", int(10.0 * f))
	card.add_child(rows)

	var titel := Label.new()
	titel.name = "SectionTitle"
	titel.theme_type_variation = "TitleLabel"
	titel.text = I18nService.t("dlc.settings_titel")
	titel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titel.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * tf))
	rows.add_child(titel)

	var info := Label.new()
	info.name = "DlcInfo"
	info.theme_type_variation = "SoftLabel"
	info.text = I18nService.t("dlc.settings_info", _zaehler())
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * tf))
	rows.add_child(info)

	var knopf := SquishButton.new()
	knopf.name = "DlcButton"
	knopf.theme_type_variation = "BtnTeal"
	knopf.text = I18nService.t("dlc.settings_knopf")
	knopf.custom_minimum_size = Vector2(0.0, 52.0 * f)
	knopf.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * tf))
	knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	knopf.focus_mode = Control.FOCUS_ALL
	knopf.pressed.connect(func() -> void: _oeffne_bibliothek(screen))
	rows.add_child(knopf)


## Info-Zeile: wie viele DLCs spielbar bzw. in Arbeit sind (Pack-Daten).
static func _zaehler() -> Dictionary:
	var spielbar := 0
	var bald := 0
	for dlc: Dictionary in DlcKatalog.eintraege():
		if str(dlc.get("status", "")) == DlcKatalog.STATUS_VERFUEGBAR:
			spielbar += 1
		else:
			bald += 1
	return {"spielbar": spielbar, "bald": bald}


## W18/4 Befund B2 („Settings-Overlay blockiert die DLC-Bibliothek“):
## home_entry überlebt Router-Reisen (der Router tauscht nur die Szene in
## dessen World-Mount), und der Settings-Screen hängt in home_entrys
## UiLayer-CanvasLayer DARÜBER — ohne explizites Schließen blieb er als
## tap-fressendes Overlay über der Bibliothek stehen (der einzige
## Hub-Zugang war damit tot). Sauberes Routen statt Z-Hacks: erst den
## Settings-Screen über seinen back_pressed-Vertrag abräumen (home_entry
## → _close_settings, exakt der Spieler-Zurück-Pfad), dann reisen — beides
## im selben Frame, es flackert also kein HUD auf.
static func _oeffne_bibliothek(screen: Control) -> void:
	DlcScreen.register_routes()
	var router := screen.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	if screen.has_signal("back_pressed"):
		screen.emit_signal("back_pressed")
	router.goto(DlcScreen.ROUTE)
