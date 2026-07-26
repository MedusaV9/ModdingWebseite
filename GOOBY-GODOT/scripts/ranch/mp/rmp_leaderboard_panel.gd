class_name RmpLeaderboardPanel
extends PanelContainer
## Freundes-Bestenliste (RW-6): ein Panel für ALLE Wettbewerbe — die beiden
## Live-Kurse (Grasbahn, Hof-Parcours) und die asynchronen RW-5-Wertungen
## (rw5_*). Kurs-Wahl über OptionButton, Einträge sortiert der Server
## (richtungsbewusst), die eigene Zeile ist hervorgehoben, Geist-Einträge
## tragen ein Häkchen. Offline zeigt das Panel den höflichen Hinweis.

signal ghost_requested(kurs_id: String, friend_code: String)

var service: RanchMultiplayerService = null

var _wahl: OptionButton
var _liste: VBoxContainer
var _hinweis: Label
var _kurse: Array[String] = []


func _ready() -> void:
	custom_minimum_size = Vector2(460, 320)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("ranch_mp.besten.titel")
	box.add_child(titel)
	_wahl = OptionButton.new()
	_kurse = RmpKurse.bestenlisten_kurse()
	for kurs_id in _kurse:
		_wahl.add_item(I18nService.t("ranch_mp.besten.kurs_%s" % kurs_id))
	_wahl.item_selected.connect(func(_idx: int) -> void: refresh())
	box.add_child(_wahl)
	_hinweis = Label.new()
	_hinweis.theme_type_variation = &"CaptionLabel"
	_hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hinweis.visible = false
	box.add_child(_hinweis)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	box.add_child(scroll)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 4)
	scroll.add_child(_liste)


func setup(mp_service: RanchMultiplayerService) -> void:
	service = mp_service


func aktueller_kurs() -> String:
	var idx := _wahl.selected if _wahl != null else 0
	return _kurse[clampi(idx, 0, _kurse.size() - 1)] if not _kurse.is_empty() else ""


## Bestenliste des gewählten Kurses (neu) laden.
func refresh() -> void:
	if service == null or not service.is_online():
		_zeige_hinweis(I18nService.t("ranch_mp.menu.offline_hint"))
		return
	var res: Dictionary = await service.rest.fetch_leaderboard(aktueller_kurs())
	if not res["ok"]:
		_zeige_hinweis(RanchMultiplayerService.fehler_text(str(res["code"])))
		return
	zeige_eintraege(res.get("entries", []), str(res.get("me", "")))


## Einträge rendern (auch direkt befüllbar — Tests/Screenshots).
func zeige_eintraege(entries: Array, me: String) -> void:
	_hinweis.visible = false
	for kind in _liste.get_children():
		kind.queue_free()
	if entries.is_empty():
		_zeige_hinweis(I18nService.t("ranch_mp.besten.leer"))
		return
	var kurs_id := aktueller_kurs()
	var zeit_kurs := RmpKurse.kleiner_gewinnt(kurs_id)
	var platz := 0
	for eintrag: Variant in entries:
		if not (eintrag is Dictionary):
			continue
		platz += 1
		var e: Dictionary = eintrag
		var code := str(e.get("friendCode", ""))
		var zeile := HBoxContainer.new()
		zeile.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.theme_type_variation = &"TitleLabel" if code == me else &"SoftLabel"
		var wert := int(_num(e.get("wert"), 0.0))
		var text: String
		if zeit_kurs:
			text = I18nService.t(
				"ranch_mp.besten.zeile_zeit",
				{"platz": platz, "name": str(e.get("name", code)), "s": "%.1f" % (wert / 1000.0)}
			)
		else:
			text = I18nService.t(
				"ranch_mp.besten.zeile_punkte",
				{"platz": platz, "name": str(e.get("name", code)), "punkte": wert}
			)
		if code == me:
			text += " %s" % I18nService.t("ranch_mp.besten.du")
		label.text = text
		zeile.add_child(label)
		if bool(e.get("hatGhost", false)):
			var geist_btn := Button.new()
			geist_btn.theme_type_variation = &"GhostButton"
			geist_btn.text = I18nService.t("ranch_mp.besten.geist_laden")
			geist_btn.tooltip_text = I18nService.t("ranch_mp.besten.ghost")
			geist_btn.pressed.connect(func() -> void: ghost_requested.emit(kurs_id, code))
			zeile.add_child(geist_btn)
		_liste.add_child(zeile)


func _zeige_hinweis(text: String) -> void:
	for kind in _liste.get_children():
		kind.queue_free()
	_hinweis.text = text
	_hinweis.visible = true


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
