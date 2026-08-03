class_name WochenVorhabenSection
extends PanelContainer
## „Diese Woche“-Abschnitt im Tagesquests-Blatt (G8 IDEA-WOCHE): EINE
## AC-Karte oben im DailyQuestPanel mit dem laufenden Wochen-Vorhaben —
## Titel, Schrittliste mit Häkchen, Goobys Zwischentext zum aktuellen
## Schritt, Belohnungs-Chip und der Feiern-Knopf fürs Finale. Nach dem
## Feiern (und für den Rest der Woche) zeigt die Karte den Geschafft-
## Zustand samt „Nächste Woche“-Zeile — kein Verfall, kein Druck.
##
## Wird bei jedem DailyQuestPanel.rebuild() frisch gebaut (kein eigener
## Cache); der Feiern-Tap läuft als Signal zurück zum DailyQuestService.

signal feiern_pressed

const ICON_DIR := "res://assets/ui/icons/"
const ICON_PX := 22.0
const CHECK_PX := 20.0

var _f := 1.0


func rebuild(info: Dictionary, f: float) -> void:
	_f = maxf(f, 0.5)
	name = "VorhabenSektion"
	theme_type_variation = "AcCard"
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(10.0 * _f))
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(6.0 * _f))
	margin.add_child(box)
	box.add_child(_build_kopf(info))
	if bool(info.get("fertig", false)):
		_build_fertig(box, info)
		return
	var def: Dictionary = info.get("def", {})
	var schritt := int(info.get("schritt", 0))
	var schritte := WochenVorhaben.schritte_von(def)
	for i in schritte.size():
		box.add_child(_build_schritt_zeile(def, i, schritt, info))
	box.add_child(_build_gooby_zeile(def, schritt, schritte.size()))
	box.add_child(_build_fuss(info))


func _build_kopf(info: Dictionary) -> Control:
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", int(8.0 * _f))
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "sparkle.svg")
	icon.custom_minimum_size = Vector2.ONE * roundf(ICON_PX * _f)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = AcTokens.GOLD
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kopf.add_child(icon)
	var wo := Label.new()
	wo.name = "VorhabenWoche"
	wo.theme_type_variation = "CaptionLabel"
	wo.text = I18nService.t("vorhaben.titel")
	wo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kopf.add_child(wo)
	var titel := Label.new()
	titel.name = "VorhabenTitel"
	titel.theme_type_variation = "SoftLabel"
	titel.add_theme_font_override("font", ThemeService.font(800))
	var def: Dictionary = info.get("def", {})
	titel.text = I18nService.t(WochenVorhabenKatalog.title_key(def))
	titel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	return kopf


## Schrittzeile: Häkchen (fertig) / Punkt (offen), Aufgabentext, beim
## aktiven Schritt der n/ziel-Fortschritt.
func _build_schritt_zeile(def: Dictionary, index: int, schritt: int, info: Dictionary) -> Control:
	var zeile := HBoxContainer.new()
	zeile.name = "VorhabenSchritt%d" % index
	zeile.add_theme_constant_override("separation", int(8.0 * _f))
	var erledigt := index < schritt
	var aktiv := index == schritt
	var check := TextureRect.new()
	check.texture = load(ICON_DIR + ("check.svg" if erledigt else "arrow_right.svg"))
	check.custom_minimum_size = Vector2.ONE * roundf(CHECK_PX * _f)
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.self_modulate = AcTokens.LEAF_DARK if erledigt else AcTokens.INK_FAINT
	if aktiv:
		check.self_modulate = AcTokens.TEAL_DARK
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(check)
	var text := Label.new()
	text.theme_type_variation = "CaptionLabel"
	text.text = I18nService.t(WochenVorhabenKatalog.schritt_text_key(def, index))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not erledigt and not aktiv:
		text.self_modulate = Color(1.0, 1.0, 1.0, 0.55)
	zeile.add_child(text)
	if aktiv:
		var stand := Label.new()
		stand.name = "VorhabenStand"
		stand.theme_type_variation = "CaptionLabel"
		stand.text = I18nService.t(
			"vorhaben.fortschritt",
			{"n": int(info.get("progress", 0)), "ziel": int(info.get("target", 1))}
		)
		zeile.add_child(stand)
	return zeile


## Goobys warme Zeile: Zwischentext des aktiven Schritts, nach dem letzten
## Schritt die Finale-Zeile des Bogens.
func _build_gooby_zeile(def: Dictionary, schritt: int, anzahl: int) -> Control:
	var zeile := Label.new()
	zeile.name = "VorhabenZwischen"
	zeile.theme_type_variation = "SoftLabel"
	if schritt >= anzahl:
		zeile.text = I18nService.t(WochenVorhabenKatalog.finale_key(def))
	else:
		zeile.text = I18nService.t(WochenVorhabenKatalog.schritt_zwischen_key(def, schritt))
	zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return zeile


## Fußzeile: Belohnungs-Chip + Feiern-Knopf (erfüllbar) bzw. die
## Wohlfühl-Zeile „läuft einfach weiter“.
func _build_fuss(info: Dictionary) -> Control:
	var fuss := HBoxContainer.new()
	fuss.add_theme_constant_override("separation", int(8.0 * _f))
	var chip := PanelContainer.new()
	chip.theme_type_variation = "AcChip"
	var belohnung := HBoxContainer.new()
	belohnung.add_theme_constant_override("separation", int(4.0 * _f))
	var coin := TextureRect.new()
	coin.texture = load("res://assets/ui/coin.png")
	coin.custom_minimum_size = Vector2.ONE * roundf(16.0 * _f)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	belohnung.add_child(coin)
	var betrag := Label.new()
	betrag.theme_type_variation = "CaptionLabel"
	betrag.text = I18nService.t(
		"vorhaben.belohnung", {"muenzen": int(info.get("muenzen", 0)), "xp": int(info.get("xp", 0))}
	)
	belohnung.add_child(betrag)
	chip.add_child(belohnung)
	fuss.add_child(chip)
	if bool(info.get("erfuellbar", false)):
		var feiern := SquishButton.new()
		feiern.name = "VorhabenFeiern"
		feiern.theme_type_variation = "BtnLeaf"
		feiern.text = I18nService.t("vorhaben.feiern")
		feiern.focus_mode = Control.FOCUS_NONE
		var floor_px := _touch_floor_px()
		feiern.custom_minimum_size = feiern.custom_minimum_size.max(Vector2(floor_px, floor_px))
		feiern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feiern.pressed.connect(func() -> void: feiern_pressed.emit())
		fuss.add_child(feiern)
	else:
		var hinweis := Label.new()
		hinweis.theme_type_variation = "CaptionLabel"
		hinweis.text = I18nService.t("vorhaben.laeuft_weiter")
		hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hinweis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hinweis.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fuss.add_child(hinweis)
	return fuss


## Geschafft-Zustand (Rest der Woche): Häkchen + Finale-Zeile des
## gefeierten Bogens + „Nächste Woche“-Vorfreude.
func _build_fertig(box: VBoxContainer, info: Dictionary) -> void:
	var zeile := HBoxContainer.new()
	zeile.name = "VorhabenGeschafft"
	zeile.add_theme_constant_override("separation", int(8.0 * _f))
	var check := TextureRect.new()
	check.texture = load(ICON_DIR + "check.svg")
	check.custom_minimum_size = Vector2.ONE * roundf(ICON_PX * _f)
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.self_modulate = AcTokens.LEAF_DARK
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(check)
	var text := Label.new()
	text.theme_type_variation = "SoftLabel"
	text.add_theme_font_override("font", ThemeService.font(800))
	text.text = I18nService.t("vorhaben.geschafft")
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(text)
	box.add_child(zeile)
	var def: Dictionary = info.get("def", {})
	if not def.is_empty():
		var finale := Label.new()
		finale.name = "VorhabenZwischen"
		finale.theme_type_variation = "SoftLabel"
		finale.text = I18nService.t(WochenVorhabenKatalog.finale_key(def))
		finale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(finale)
	var naechste := Label.new()
	naechste.theme_type_variation = "CaptionLabel"
	naechste.text = I18nService.t("vorhaben.naechste_woche")
	naechste.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(naechste)


## Physischer 44-pt-Touch-Floor (Muster DailyQuestPanel._touch_floor_px);
## außerhalb des Baums fällt er auf die f-Heuristik zurück.
func _touch_floor_px() -> float:
	if is_inside_tree():
		return float(ScreenShell.metrics(get_viewport())["floor_px"])
	return float(AcTokens.TOUCH_FLOOR) * maxf(_f, 1.0)
