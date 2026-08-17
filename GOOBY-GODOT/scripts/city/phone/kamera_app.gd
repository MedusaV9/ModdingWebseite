class_name PhoneKameraApp
extends VBoxContainer
## Kamera-App im IGohbie: startet den Fotomodus (Gate = Kamera aus dem POW!)
## und zeigt die letzte Aufnahme als Vorschau plus die Zahl der Bilder im
## Album. Das Knipsen selbst macht `FotoModus` über der laufenden Szene —
## diese App ist nur der Auslöser.
##
## W16/G4 P18: Breiten an die reale Gerätebreite gekoppelt (PhoneShell-
## Bausteine statt 420er-City-Bausteine), Vorschau ×f, SquishButtons mit
## `ui_click` (W16 F12).

signal fotomodus_gewuenscht

var gs: Object


func _ready() -> void:
	PhoneShell.richte_app_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	var m := ScreenShell.metrics(get_viewport())
	var karte := PhoneShell.app_karte(self)
	PhoneShell.app_label(karte, I18nService.t("phone.kamera.titel"), "HeadlineLabel")
	if not FotoModus.ist_frei(gs):
		PhoneShell.app_label(karte, I18nService.t("phone.app.kamera_gesperrt"), "CaptionLabel")
		PhoneShell.app_fonts_skalieren(self)
		return
	PhoneShell.app_label(karte, I18nService.t("phone.kamera.text"), "CaptionLabel")
	var btn := SquishButton.new()
	btn.name = "FotomodusStarten"
	btn.theme_type_variation = "PrimaryButton"
	btn.text = I18nService.t("phone.kamera.starten")
	# W16 F12: Start-Klick — der Fotomodus selbst bleibt beim Öffnen stumm.
	btn.pressed.connect(
		func() -> void:
			AudioDirector.try_play(btn, "ui_click")
			fotomodus_gewuenscht.emit()
	)
	ScreenShell.touch_target(btn, m)
	karte.add_child(btn)
	_baue_galerie(m)
	PhoneShell.app_fonts_skalieren(self)


func _baue_galerie(m: Dictionary) -> void:
	var bilder := FotoModus.fotos(gs)
	var karte := PhoneShell.app_karte(self)
	PhoneShell.app_label(karte, I18nService.t("phone.kamera.galerie"), "HeadlineLabel")
	if bilder.is_empty():
		PhoneShell.app_label(karte, I18nService.t("phone.kamera.leer"), "CaptionLabel")
		return
	PhoneShell.app_label(
		karte, I18nService.t("phone.kamera.anzahl").format({"n": bilder.size()}), "CaptionLabel"
	)
	var pfad := str((bilder[0] as Dictionary).get("pfad", ""))
	var bild := Image.new()
	if not pfad.is_empty() and bild.load(pfad) == OK:
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(bild)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(0.0, 150.0 * float(m["f"]))
		karte.add_child(rect)
	# REST-4 (EVAL Rang 14): volle Galerie (Raster/Zoom/Favoriten/Löschen).
	var galerie_btn := SquishButton.new()
	galerie_btn.name = "GalerieOeffnen"
	galerie_btn.theme_type_variation = "AccentButton"
	galerie_btn.text = I18nService.t("galerie.oeffnen")
	# W16 F12: Routen-Klick zur Galerie.
	galerie_btn.pressed.connect(
		func() -> void:
			AudioDirector.try_play(galerie_btn, "ui_click")
			_on_galerie_oeffnen()
	)
	ScreenShell.touch_target(galerie_btn, m)
	karte.add_child(galerie_btn)


func _on_galerie_oeffnen() -> void:
	GalerieScreen.register_routes()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(GalerieScreen.ROUTE, {})
