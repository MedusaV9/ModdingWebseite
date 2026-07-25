class_name PhoneKameraApp
extends VBoxContainer
## Kamera-App im IGohbie: startet den Fotomodus (Gate = Kamera aus dem POW!)
## und zeigt die letzte Aufnahme als Vorschau plus die Zahl der Bilder im
## Album. Das Knipsen selbst macht `FotoModus` über der laufenden Szene —
## diese App ist nur der Auslöser.

signal fotomodus_gewuenscht

var gs: Object


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("phone.kamera.titel"), "HeadlineLabel")
	if not FotoModus.ist_frei(gs):
		CitySheetBausteine.label(karte, I18nService.t("phone.app.kamera_gesperrt"), "CaptionLabel")
		return
	CitySheetBausteine.label(karte, I18nService.t("phone.kamera.text"), "CaptionLabel")
	var btn := Button.new()
	btn.theme_type_variation = "PrimaryButton"
	btn.text = I18nService.t("phone.kamera.starten")
	btn.pressed.connect(func() -> void: fotomodus_gewuenscht.emit())
	karte.add_child(btn)
	_baue_galerie()


func _baue_galerie() -> void:
	var bilder := FotoModus.fotos(gs)
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("phone.kamera.galerie"), "HeadlineLabel")
	if bilder.is_empty():
		CitySheetBausteine.label(karte, I18nService.t("phone.kamera.leer"), "CaptionLabel")
		return
	CitySheetBausteine.label(
		karte, I18nService.t("phone.kamera.anzahl").format({"n": bilder.size()}), "CaptionLabel"
	)
	var pfad := str((bilder[0] as Dictionary).get("pfad", ""))
	var bild := Image.new()
	if pfad.is_empty() or bild.load(pfad) != OK:
		return
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(bild)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(0.0, 150.0)
	karte.add_child(rect)
