class_name GoobayPanel
extends Control
## Goobay-Handy (Doc D §5.4): links die Verkaufsliste aus dem Lager, rechts
## der Chat mit dem Käufer — Text-Bubbles, Stimmungs-Icon und die drei
## Knöpfe „Höher!“ / „Deal!“ / „Lass gut sein“.
##
## Die Verhandlung selbst rechnet GoobayLogic (PURE); dieses Panel zeigt
## ausschließlich `GoobayLogic.public_view()` an — Budget und Geduld des
## Käufers bleiben verdeckt. Pflichtmöbel filtert GoobayState vorher heraus.

signal verkauft(item_id: String, erloes: int)
signal closed

const ICON_PX := 26
const CARD_MIN := Vector2(700, 440)
## Käufernamen (Chat-Absender) — bewusst albern, aber neutral.
const KAEUFER: Array[String] = ["Gerd", "Bibi", "Olaf", "Tante Roswita", "Mo", "Klaus-Dieter"]

var _gs: Object
var _room: Node
var _rng := RandomNumberGenerator.new()
var _tag := ""
var _session: Dictionary = {}
var _kaeufer_name := ""
var _kategorie := ""

var _liste: VBoxContainer
var _chat: VBoxContainer
var _chat_scroll: ScrollContainer
var _buttons: HBoxContainer
var _stimmung: TextureRect


## Panel öffnen. `tag` = Datumsschlüssel für Tagesnachfrage/Sperren,
## `saat` > 0 macht die Verhandlung deterministisch (Tests/Screenshots).
static func open_in(
	ui_layer: Node, gs: Object, room: Node = null, tag := "", saat := 0
) -> GoobayPanel:
	var panel := GoobayPanel.new()
	panel.name = "GoobayPanel"
	panel._gs = gs
	panel._room = room
	panel._tag = tag if tag != "" else Time.get_date_string_from_system()
	if saat > 0:
		panel._rng.seed = saat
	else:
		panel._rng.randomize()
	# Anker VOR add_child: unter einem CanvasLayer bleibt ein Control sonst
	# 0×0 groß (Godot rechnet die Preset-Offsets nur beim Eintritt aus).
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(panel)
	return panel


func _ready() -> void:
	theme = ThemeService.theme()
	_build_ui()
	refresh_liste()
	AudioDirector.try_play(self, "ui_open")


func close() -> void:
	AudioDirector.try_play(self, "ui_close")
	closed.emit()
	queue_free()


## Angebotsliste (Lager minus Pflichtmöbel minus heute gesperrte) neu bauen.
func refresh_liste() -> void:
	for child in _liste.get_children():
		child.queue_free()
	var angebote := GoobayState.angebote(_gs, _tag)
	if angebote.is_empty():
		var leer := Label.new()
		leer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		leer.text = I18nService.t("goobay.kein_angebot")
		_liste.add_child(leer)
		return
	for eintrag: Dictionary in angebote:
		var btn := SquishButton.new()
		btn.theme_type_variation = "AcChip"
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s ×%d — %d ᴳ" % [eintrag["name"], eintrag["count"], eintrag["wert"]]
		btn.pressed.connect(starte_verhandlung.bind(str(eintrag["item"])))
		_liste.add_child(btn)


## Verhandlung für ein Lager-Item starten (auch von Tests gerufen).
func starte_verhandlung(item_id: String) -> void:
	var def := FurnitureCatalog.def(item_id)
	if def.is_empty():
		return
	_kategorie = str(def.get("kategorie", "deko"))
	var nachfrage := GoobayState.nachfrage(_gs, _kategorie, _tag, _rng)
	_kaeufer_name = KAEUFER[_rng.randi_range(0, KAEUFER.size() - 1)]
	_session = GoobayLogic.start(item_id, GoobayState.verkaufswert(def), nachfrage, _rng)
	_chat_leeren()
	_bubble(
		I18nService.t("goobay.kaeufer", {"name": _kaeufer_name}),
		FurnitureCatalog.display_name(def, I18nService.get_locale()),
		false
	)
	_angebots_bubble()
	_update_buttons()


func hoeher() -> void:
	if _session.is_empty() or GoobayLogic.ist_beendet(_session):
		return
	_bubble("", I18nService.t("goobay.antwort_hoeher"), true)
	GoobayLogic.hoeher(_session, _rng)
	var status := str(_session["status"])
	if status == GoobayLogic.STATUS_ABBRUCH:
		_abbruch_anzeigen()
	elif status == GoobayLogic.STATUS_FINAL:
		_bubble("", I18nService.t("goobay.letztes", {"preis": int(_session["angebot"])}), false)
	else:
		_bubble("", I18nService.t("goobay.nachbessern", {"preis": int(_session["angebot"])}), false)
	_update_buttons()


func annehmen(versand := false) -> void:
	if _session.is_empty() or GoobayLogic.ist_beendet(_session):
		return
	GoobayLogic.annehmen(_session)
	var erloes := GoobayState.deal_abschliessen(
		_gs, str(_session["item"]), int(_session["erloes"]), versand
	)
	_bubble("", I18nService.t("goobay.verkauft", {"preis": erloes}), false)
	_bubble(
		"",
		(
			I18nService.t("goobay.versand_laeuft")
			if versand
			else I18nService.t("goobay.abholung_laeuft", {"name": _kaeufer_name})
		),
		false
	)
	# Verkaufs-Erfolg = abgeschlossene Geld-Transaktion + Belohnungsmoment
	# (W16 F4, Muster ikea_screen: ui_buy + Haptics.success).
	AudioDirector.try_play(self, "ui_buy")
	Haptics.success(self)
	if _room != null and _room.has_method("say"):
		_room.say(I18nService.t("goobay.verkauft", {"preis": erloes}))
	verkauft.emit(str(_session["item"]), erloes)
	_session = {}
	_update_buttons()
	refresh_liste()


func abbrechen() -> void:
	if _session.is_empty() or GoobayLogic.ist_beendet(_session):
		return
	GoobayLogic.abbrechen(_session)
	_abbruch_anzeigen()
	_update_buttons()


## Sichtbarer Zustand (Tests/Screenshots).
func public_view() -> Dictionary:
	return GoobayLogic.public_view(_session) if not _session.is_empty() else {}


# ── Aufbau & Anzeige ─────────────────────────────────────────────────────────


func _build_ui() -> void:
	var veil := ColorRect.new()
	veil.color = AcTokens.VEIL
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var card := PanelContainer.new()
	card.theme_type_variation = "AcCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = CARD_MIN
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_build_header())
	box.add_child(_build_body())
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	box.add_child(_buttons)
	_update_buttons()


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_stimmung = HomeIcons.node("stimmung0", ICON_PX + 6)
	header.add_child(_stimmung)
	var titel := Label.new()
	titel.text = I18nService.t("goobay.titel")
	titel.theme_type_variation = "TitleLabel"
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titel)
	var zu := SquishButton.new()
	zu.text = I18nService.t("craft.schliessen")
	zu.theme_type_variation = "GhostButton"
	zu.pressed.connect(close)
	header.add_child(zu)
	return header


func _build_body() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	var links := ScrollContainer.new()
	links.custom_minimum_size = Vector2(280, 250)
	body.add_child(links)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 6)
	links.add_child(_liste)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_chat_scroll)
	_chat = VBoxContainer.new()
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat.add_theme_constant_override("separation", 8)
	_chat_scroll.add_child(_chat)
	return body


func _chat_leeren() -> void:
	for child in _chat.get_children():
		child.queue_free()


## Eine Chat-Bubble: `titel` optional (Absenderzeile), `eigen` = Gooby.
func _bubble(titel: String, text: String, eigen: bool) -> void:
	var reihe := HBoxContainer.new()
	reihe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if eigen:
		var luft := Control.new()
		luft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reihe.add_child(luft)
	var karte := PanelContainer.new()
	karte.theme_type_variation = "DialogBubble" if not eigen else "AcWell"
	karte.custom_minimum_size = Vector2(220, 0)
	var inhalt := VBoxContainer.new()
	karte.add_child(inhalt)
	if titel != "":
		var kopf := Label.new()
		kopf.text = titel
		kopf.theme_type_variation = "CaptionLabel"
		inhalt.add_child(kopf)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200, 0)
	inhalt.add_child(label)
	reihe.add_child(karte)
	_chat.add_child(reihe)
	_ans_chat_ende.call_deferred()


## Der Chat läuft nach unten weiter — die neueste Bubble muss sichtbar sein.
func _ans_chat_ende() -> void:
	if _chat_scroll == null:
		return
	await get_tree().process_frame
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat.size.y)


func _angebots_bubble() -> void:
	_bubble("", I18nService.t("goobay.angebot", {"preis": int(_session["angebot"])}), false)
	_stimmung.texture = HomeIcons.stimmung(int(_session["stimmung"]))


func _abbruch_anzeigen() -> void:
	_bubble("", I18nService.t("goobay.geplatzt"), false)
	_bubble("", I18nService.t("goobay.geplatzt_info", {"name": _kaeufer_name}), false)
	GoobayState.abbruch_merken(_gs, str(_session["item"]), _kategorie, _tag)
	AudioDirector.try_play(self, "ui_error")
	_session = {}
	refresh_liste()


func _update_buttons() -> void:
	for child in _buttons.get_children():
		child.queue_free()
	if _session.is_empty():
		_stimmung.texture = HomeIcons.stimmung(0)
		return
	_stimmung.texture = HomeIcons.stimmung(int(_session["stimmung"]))
	var runde := Label.new()
	runde.text = I18nService.t("goobay.runde", {"runde": int(_session["runde"]) + 1})
	runde.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.add_child(runde)
	if str(_session["status"]) == GoobayLogic.STATUS_OFFEN:
		_add_button("goobay.hoeher", "AccentButton", hoeher)
	_add_button("goobay.deal", "PrimaryButton", annehmen.bind(false))
	var bonus := GoobayLogic.post_bonus(int(_session["angebot"]))
	var versand := SquishButton.new()
	versand.text = I18nService.t("goobay.versand", {"bonus": bonus})
	versand.theme_type_variation = "ChipLeaf"
	versand.pressed.connect(annehmen.bind(true))
	_buttons.add_child(versand)
	_add_button("goobay.abbrechen", "GhostButton", abbrechen)


func _add_button(key: String, variation: String, handler: Callable) -> void:
	var btn := SquishButton.new()
	btn.text = I18nService.t(key)
	btn.theme_type_variation = variation
	btn.pressed.connect(handler)
	_buttons.add_child(btn)
