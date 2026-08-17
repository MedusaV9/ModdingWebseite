class_name RNpcFreundeUi
extends Control
## Freundschafts-Ansicht des Ranch-DLC (RW-3): eine AC-Karte pro NPC mit
## Name, Rolle, Herz-Leiste (0–5, gefüllt/leer), Punkte-Fortschritt bis zum
## nächsten Herz und den Freischaltungen je Stufe (erreichte normal,
## kommende ausgegraut mit Stufen-Hinweis). Liest NUR über RNpcState —
## Verfall ist damit automatisch eingerechnet.
##
## Einbau: mounten + `back_pressed`; Tests injizieren `game_state_override`.

signal back_pressed

const HERZ_VOLL := "\u2665"
const HERZ_LEER := "\u2661"
const HERZ_FARBE := Color("#D96A6A")

var game_state_override: Object

var _liste: VBoxContainer


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	refresh()


func refresh() -> void:
	for kind in _liste.get_children():
		kind.queue_free()
	var gs := game_state()
	var jetzt := RQuestState.now_ms(gs)
	for def: Dictionary in RNpcKatalog.alle():
		_liste.add_child(_npc_karte(gs, def, jetzt))


## Herz-Leiste als Text ("♥♥♥♡♡") — static für Tests.
static func herz_text(stufe: int) -> String:
	var voll := clampi(stufe, 0, RNpcFreundschaft.HERZ_MAX)
	return HERZ_VOLL.repeat(voll) + HERZ_LEER.repeat(RNpcFreundschaft.HERZ_MAX - voll)


func _build_layout() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	box.add_child(kopf)
	var titel := Label.new()
	titel.theme_type_variation = "TitleLabel"
	titel.text = I18nService.t("rnpc.ui.titel")
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	var zurueck := Button.new()
	zurueck.theme_type_variation = "GhostButton"
	zurueck.text = I18nService.t("rquest.log.schliessen")
	zurueck.pressed.connect(func() -> void: back_pressed.emit())
	kopf.add_child(zurueck)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 10)
	scroll.add_child(_liste)


func _npc_karte(gs: Object, def: Dictionary, jetzt: int) -> Control:
	var npc_id := str(def.get("id", ""))
	var freund := RNpcState.freund(gs, npc_id, jetzt)
	var punkte := float(freund.get("punkte", 0.0))
	var stufe := RNpcFreundschaft.herzen(punkte)

	var karte := PanelContainer.new()
	karte.theme_type_variation = "AcCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	karte.add_child(box)

	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	box.add_child(kopf)
	var name_label := Label.new()
	name_label.theme_type_variation = "HeadlineLabel"
	name_label.text = I18nService.t("rnpc.%s.name" % npc_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(name_label)
	var rolle := Label.new()
	rolle.theme_type_variation = "AcChip"
	rolle.text = I18nService.t("rnpc.%s.rolle" % npc_id)
	kopf.add_child(rolle)

	var herzen := Label.new()
	herzen.theme_type_variation = "TitleLabel"
	herzen.add_theme_color_override("font_color", HERZ_FARBE)
	herzen.text = herz_text(stufe)
	box.add_child(herzen)

	var fortschritt := Label.new()
	fortschritt.theme_type_variation = "CaptionLabel"
	if stufe >= RNpcFreundschaft.HERZ_MAX:
		fortschritt.text = I18nService.t("rnpc.ui.max")
	else:
		fortschritt.text = I18nService.t(
			"rnpc.ui.naechste", {"p": int(ceilf(RNpcFreundschaft.punkte_bis_naechste(punkte)))}
		)
	box.add_child(fortschritt)

	_freischaltungen_anfuegen(box, def, stufe)
	return karte


func _freischaltungen_anfuegen(box: VBoxContainer, def: Dictionary, stufe: int) -> void:
	var kopf := Label.new()
	kopf.theme_type_variation = "CaptionLabel"
	kopf.text = I18nService.t("rnpc.ui.freischaltungen")
	box.add_child(kopf)
	for herz in range(1, RNpcFreundschaft.HERZ_MAX + 1):
		for frei: Variant in RNpcFreundschaft.freischaltungen_der_stufe(def, herz):
			if not (frei is Dictionary):
				continue
			var zeile := Label.new()
			zeile.theme_type_variation = "SoftLabel"
			zeile.text = "%s %d: %s" % [HERZ_VOLL, herz, frei_text(frei)]
			if herz > stufe:
				zeile.modulate = Color(1.0, 1.0, 1.0, 0.45)
			box.add_child(zeile)


## Lokalisierte Freischaltungs-Zeile — static für Tests.
static func frei_text(frei: Dictionary) -> String:
	var typ := str(frei.get("typ", ""))
	if typ == "rabatt":
		return I18nService.t("rnpc.frei.rabatt", {"shop": str(frei.get("shop", ""))})
	if ["smalltalk", "geschichte", "quest", "rezept", "cosmetic", "ort"].has(typ):
		return I18nService.t("rnpc.frei.%s" % typ)
	return typ
