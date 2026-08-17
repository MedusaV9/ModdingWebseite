class_name News50Panel
extends PanelSheet
## 5.0-Neuigkeiten-Panel: Liste der Godot-Rewrite-Highlights (DEUTSCH,
## Inhalte aus strings `news.items`). Baut auf dem Bottom-Sheet auf;
## `news_seen` feuert beim Bestätigen (W1d persistiert `whats_new_5_seen`).
##
## FIX1 („Patchnotes komplett broken“): Das Sheet selbst ist jetzt
## zentriert, breiten-gedeckelt und SCROLLT (PanelSheet-Umbau) — vorher
## wuchs die Liste ungebremst aus dem Bildschirm und das Panel war leer.
## Neu außerdem: Versions-Zeile (aus project.godot `config/version`).

signal news_seen

const ICON_DIR := "res://assets/ui/icons/"

## Zuletzt eingehängter Inhalt — wird beim Neubau SOFORT freigegeben.
var _inhalt: Control


func _ready() -> void:
	super()
	set_title(I18nService.t("news.titel"))
	_setze_inhalt(_build_content())


## FIX1: bei jedem Öffnen frisch bauen — so stimmt die Schrift-Skalierung
## auch nach Rotation/Resize (Faktor wird in _build_content gelesen).
func open() -> void:
	var frisch := not is_open()
	if frisch:
		_setze_inhalt(_build_content())
	super()
	# W21 (c): gestaffelter Zeilen-Auftritt (MotionKit, RM-gated im Kit).
	if frisch and _inhalt != null:
		var zeilen: Array = []
		for kind in _inhalt.get_children():
			if String(kind.name).begins_with("Item"):
				zeilen.append(kind)
		MotionKit.stagger_ein(zeilen)


## G4/P17: Rotation bei OFFENEM Panel baut den Inhalt neu — Lesebreite/f
## sind in die Zeilen eingebrannt, nach der Drehung ragten sie sonst übers
## Blatt hinaus. Überschreibt den PanelSheet-Resize-Hook (super() = relayout).
func _on_viewport_resized() -> void:
	if is_open():
		_setze_inhalt(_build_content())
	super()


## Alten Inhalt SOFORT freigeben statt queue_free-pendent zu lassen:
## _relayout misst pendente Kinder mit, und ein PanelContainer schrumpft
## nach so einer Min-Size-Blähung nicht von selbst auf seine Offsets
## zurück (Screenshot-Befund G4 — Sheet ragte rechts aus dem Bild).
func _setze_inhalt(neu: Control) -> void:
	if _inhalt != null and is_instance_valid(_inhalt):
		var eltern := _inhalt.get_parent()
		if eltern != null:
			eltern.remove_child(_inhalt)
		_inhalt.free()
	_inhalt = neu
	add_content(neu)


func _build_content() -> Control:
	var f := UiScale.for_viewport(get_viewport())
	var lese_breite := _lese_breite(f)
	var vbox := VBoxContainer.new()
	vbox.name = "NewsList"
	vbox.add_theme_constant_override("separation", AcTokens.px(12.0, f))
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = "SoftLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", AcTokens.font_px(AcTokens.SIZE_BODY, f))
	subtitle.text = I18nService.t("news.untertitel")
	vbox.add_child(subtitle)
	var version := Label.new()
	version.name = "VersionLabel"
	version.theme_type_variation = "CaptionLabel"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", AcTokens.font_px(AcTokens.SIZE_CAPTION, f))
	version.text = I18nService.t(
		"news.version",
		{"version": str(ProjectSettings.get_setting("application/config/version", "5.0.0"))}
	)
	vbox.add_child(version)
	var entries := I18nService.items("news.items")
	for i in entries.size():
		vbox.add_child(_build_item_row(i, entries[i], f, lese_breite))
	var ok := SquishButton.new()
	ok.name = "NewsOkButton"
	ok.theme_type_variation = "BtnLeaf"
	ok.text = I18nService.t("news.button")
	# 2-Höhen-System: der EINE Hero-CTA des Blatts → BTN_H_PRIMAER.
	ok.custom_minimum_size = Vector2(
		float(AcTokens.px(220.0, f)), float(AcTokens.px(AcTokens.BTN_H_PRIMAER, f))
	)
	ok.add_theme_font_size_override("font_size", AcTokens.font_px(AcTokens.SIZE_BUTTON, f))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_on_ok_pressed)
	vbox.add_child(ok)
	return vbox


## G4/P17 (Inhaltsspalten-Gedanke W16): Lesebreite der Item-Zeilen deckeln —
## im Querformat läuft das Sheet bis 720*f, Fließtext bleibt bei ~560*f und
## mittig statt randlos breit (Icon „hing“ sonst weit weg vom Text).
func _lese_breite(f: float) -> float:
	var vp := get_viewport()
	var canvas := Vector2(vp.get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(vp, safe_area_override)
	var innen := PanelSheetLayout.sheet_width(canvas, insets, f) - chrome_width()
	return minf(float(AcTokens.px(560.0, f)), maxf(innen, 220.0))


func _build_item_row(index: int, entry: Dictionary, f: float, lese_breite: float) -> Control:
	var row := PanelContainer.new()
	row.name = "Item%d" % index
	row.theme_type_variation = "AcWell"
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.custom_minimum_size = Vector2(lese_breite, 0.0)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", AcTokens.px(12.0, f))
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "sparkle.svg")
	icon.custom_minimum_size = Vector2.ONE * AcTokens.px(AcTokens.ICON_L, f)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = AcTokens.YELLOW_DARK
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.name = "ItemTitle"
	title.add_theme_font_size_override("font_size", AcTokens.font_px(AcTokens.SIZE_BODY, f))
	title.text = str(entry.get("titel", ""))
	text_box.add_child(title)
	var body := Label.new()
	body.name = "ItemText"
	body.theme_type_variation = "CaptionLabel"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", AcTokens.font_px(AcTokens.SIZE_CAPTION, f))
	# Wrap-Breite stabilisieren (W3a-GOTCHA: Autowrap ohne Min-Breite misst
	# im ersten Pass bei Breite 0): Lesebreite minus Icon/Abstände/Well-Rand.
	body.custom_minimum_size = Vector2(maxf(lese_breite - float(AcTokens.px(80.0, f)), 160.0), 0.0)
	body.text = str(entry.get("text", ""))
	text_box.add_child(body)
	box.add_child(text_box)
	row.add_child(box)
	return row


func _on_ok_pressed() -> void:
	news_seen.emit()
	close()
