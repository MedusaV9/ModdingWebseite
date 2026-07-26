class_name RQuestLogUi
extends Control
## Quest-Log des Ranch-DLC (RW-3) im AC-Look: links die Kapitel-Titelkarte
## (echte Artworks aus assets/ranch/artwork/), rechts Tabs (Hauptreihe /
## Nebenquests / Tagesaufgaben) mit Quest-Karten. Karten zeigen Status-Chip,
## Ziele mit Fortschritt, bei Warte-Quests Restzeit + Alternativ-Tipp, und
## Annehmen-/Abgeben-Knöpfe (RQuestState übernimmt Save + Notifications).
##
## Einbau: mounten + `back_pressed` verdrahten; Tests/Probes injizieren
## `game_state_override` und rufen refresh() nach Zustandsänderungen.

signal back_pressed

const INK := Color("#3B3630")

var game_state_override: Object

var _tab := "haupt"
var _titelkarte: TextureRect
var _kapitel_label: Label
var _liste: VBoxContainer
var _tab_buttons: Dictionary = {}


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	refresh()


## Kompletten Inhalt neu aufbauen (nach Annehmen/Abgeben/Tick).
func refresh() -> void:
	var gs := game_state()
	RQuestState.tick(gs)
	_kapitel_aktualisieren(gs)
	for kind in _liste.get_children():
		kind.queue_free()
	var defs := _tab_quests(gs)
	if defs.is_empty():
		var leer := Label.new()
		leer.theme_type_variation = "SoftLabel"
		leer.text = I18nService.t("rquest.log.leer")
		leer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_liste.add_child(leer)
		return
	for def: Dictionary in defs:
		_liste.add_child(_quest_karte(gs, def))


## ------------------------------------------------------------ Aufbau


func _build_layout() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 14)
	add_child(hbox)

	var links := PanelContainer.new()
	links.theme_type_variation = "AcCard"
	links.custom_minimum_size = Vector2(320.0, 0.0)
	hbox.add_child(links)
	var links_box := VBoxContainer.new()
	links_box.add_theme_constant_override("separation", 10)
	links.add_child(links_box)
	var titel := Label.new()
	titel.theme_type_variation = "TitleLabel"
	titel.text = I18nService.t("rquest.log.titel")
	links_box.add_child(titel)
	_kapitel_label = Label.new()
	_kapitel_label.theme_type_variation = "CaptionLabel"
	links_box.add_child(_kapitel_label)
	_titelkarte = TextureRect.new()
	_titelkarte.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_titelkarte.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_titelkarte.custom_minimum_size = Vector2(300.0, 380.0)
	_titelkarte.size_flags_vertical = Control.SIZE_EXPAND_FILL
	links_box.add_child(_titelkarte)
	var zurueck := Button.new()
	zurueck.theme_type_variation = "GhostButton"
	zurueck.text = I18nService.t("rquest.log.schliessen")
	zurueck.pressed.connect(func() -> void: back_pressed.emit())
	links_box.add_child(zurueck)

	var rechts := VBoxContainer.new()
	rechts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rechts.add_theme_constant_override("separation", 10)
	hbox.add_child(rechts)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	rechts.add_child(tabs)
	for eintrag: Array in [
		["haupt", "rquest.log.tab_haupt"],
		["neben", "rquest.log.tab_neben"],
		["tages", "rquest.log.tab_tages"],
	]:
		var btn := Button.new()
		btn.text = I18nService.t(str(eintrag[1]))
		btn.toggle_mode = true
		btn.pressed.connect(_on_tab.bind(str(eintrag[0])))
		_tab_buttons[str(eintrag[0])] = btn
		tabs.add_child(btn)
	_tabs_stylen()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rechts.add_child(scroll)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 10)
	scroll.add_child(_liste)


func _on_tab(tab: String) -> void:
	_tab = tab
	_tabs_stylen()
	refresh()


func _tabs_stylen() -> void:
	for id: String in _tab_buttons:
		var btn: Button = _tab_buttons[id]
		btn.button_pressed = id == _tab
		btn.theme_type_variation = "PrimaryButton" if id == _tab else "GhostButton"


func _kapitel_aktualisieren(gs: Object) -> void:
	var kapitel := RQuestState.kapitel(gs)
	var aktuelle := mini(kapitel, RQuestKatalog.hauptreihe().size())
	_kapitel_label.text = I18nService.t("rquest.log.kapitel", {"n": aktuelle})
	var karte := ""
	for def: Dictionary in RQuestKatalog.hauptreihe():
		if int(def.get("kapitel", 0)) == aktuelle:
			karte = str(def.get("titelkarte", ""))
	if not karte.is_empty() and ResourceLoader.exists(karte):
		_titelkarte.texture = load(karte)


## ------------------------------------------------------------ Karten


func _tab_quests(gs: Object) -> Array:
	var out: Array = []
	var quelle: Array
	match _tab:
		"haupt":
			quelle = RQuestKatalog.hauptreihe()
		"neben":
			quelle = RQuestKatalog.nebenquests()
		_:
			quelle = RQuestKatalog.tagesaufgaben(RQuestState.datum(gs))
	for def: Dictionary in quelle:
		var status := RQuestState.status(gs, str(def.get("id", "")))
		if status == RQuestEngine.STATUS_GESPERRT and _tab != "haupt":
			continue
		out.append(def)
	return out


func _quest_karte(gs: Object, def: Dictionary) -> Control:
	var quest_id := str(def.get("id", ""))
	var status := RQuestState.status(gs, quest_id)
	var karte := PanelContainer.new()
	karte.theme_type_variation = "AcCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	karte.add_child(box)

	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	box.add_child(kopf)
	var titel := Label.new()
	titel.theme_type_variation = "HeadlineLabel"
	titel.text = I18nService.t("rquest.q.%s.titel" % quest_id)
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	var chip := Label.new()
	chip.theme_type_variation = "AcChip"
	chip.text = I18nService.t("rquest.log.status_%s" % status)
	kopf.add_child(chip)

	var geber := Label.new()
	geber.theme_type_variation = "CaptionLabel"
	geber.text = I18nService.t(
		"rquest.log.geber", {"name": I18nService.t("rnpc.%s.name" % str(def.get("geber", "")))}
	)
	box.add_child(geber)

	if status == RQuestEngine.STATUS_GESPERRT or status == RQuestEngine.STATUS_ERLEDIGT:
		return karte

	var text := Label.new()
	text.theme_type_variation = "SoftLabel"
	text.text = I18nService.t("rquest.q.%s.text" % quest_id)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)

	var lauf: Variant = (RQuestState.quests(gs).get("aktiv", {}) as Dictionary).get(quest_id)
	if lauf is Dictionary:
		_ziele_anfuegen(box, def, lauf)
	if status == RQuestEngine.STATUS_WARTEND and lauf is Dictionary:
		_warte_anfuegen(box, quest_id, lauf)
	_knopf_anfuegen(box, gs, quest_id, status)
	return karte


func _ziele_anfuegen(box: VBoxContainer, def: Dictionary, lauf: Dictionary) -> void:
	var ziele: Array = def.get("ziele") if def.get("ziele") is Array else []
	var index := int(lauf.get("zielIndex", 0))
	for i: int in ziele.size():
		var zeile := Label.new()
		zeile.theme_type_variation = "CaptionLabel"
		var praefix := "[x] " if i < index else ("> " if i == index else "[ ] ")
		zeile.text = praefix + ziel_text(ziele[i], int(lauf.get("zaehler", 0)) if i == index else 0)
		box.add_child(zeile)


func _warte_anfuegen(box: VBoxContainer, quest_id: String, lauf: Dictionary) -> void:
	var rest := RQuestWarte.restzeit_ms(lauf, RQuestState.now_ms(game_state()))
	var zeile := Label.new()
	zeile.theme_type_variation = "AcChip"
	zeile.text = I18nService.t("rquest.log.wartend_bis", {"rest": RQuestWarte.restzeit_text(rest)})
	box.add_child(zeile)
	var tipp := Label.new()
	tipp.theme_type_variation = "SoftLabel"
	tipp.text = (
		I18nService.t("rquest.warte.alternative_titel")
		+ " "
		+ RQuestWarte.alternative_text(quest_id)
	)
	tipp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tipp)


func _knopf_anfuegen(box: VBoxContainer, gs: Object, quest_id: String, status: String) -> void:
	if status == RQuestEngine.STATUS_VERFUEGBAR:
		var annehmen := Button.new()
		annehmen.theme_type_variation = "PrimaryButton"
		annehmen.text = I18nService.t("rquest.log.annehmen")
		annehmen.pressed.connect(
			func() -> void:
				RQuestState.annehmen(gs, quest_id)
				refresh()
		)
		box.add_child(annehmen)
	elif status == RQuestEngine.STATUS_ERFUELLBAR:
		var abgeben := Button.new()
		abgeben.theme_type_variation = "AccentButton"
		abgeben.text = I18nService.t("rquest.log.abgeben")
		abgeben.pressed.connect(
			func() -> void:
				RQuestState.abgeben(gs, quest_id)
				refresh()
		)
		box.add_child(abgeben)


## Lokalisierte Ziel-Zeile ({ist}-Fortschritt nur fürs aktuelle Ziel) —
## static, damit Tests sie ohne Szene prüfen können.
static func ziel_text(ziel: Dictionary, ist: int) -> String:
	var typ := str(ziel.get("typ", ""))
	match typ:
		"gehe_zu":
			return I18nService.t(
				"rquest.ziel.gehe_zu",
				{"ort": I18nService.t("rquest.ort.%s" % str(ziel.get("ort", "")))}
			)
		"sprich_mit":
			return I18nService.t(
				"rquest.ziel.sprich_mit",
				{"npc": I18nService.t("rnpc.%s.name" % str(ziel.get("npc", "")))}
			)
		"sammle":
			return I18nService.t(
				"rquest.ziel.sammle",
				{
					"item": I18nService.t("rquest.item.%s" % str(ziel.get("item", ""))),
					"ist": ist,
					"soll": RQuestEngine.ziel_n(ziel)
				}
			)
		"pflege":
			return I18nService.t(
				"rquest.ziel.pflege",
				{
					"aktion": I18nService.t("rquest.aktion.%s" % str(ziel.get("aktion", ""))),
					"ist": ist,
					"soll": RQuestEngine.ziel_n(ziel)
				}
			)
		"reite_strecke":
			return I18nService.t(
				"rquest.ziel.reite_strecke",
				{"strecke": I18nService.t("rquest.strecke.%s" % str(ziel.get("strecke", "")))}
			)
		"gewinne_wettbewerb":
			return I18nService.t(
				"rquest.ziel.gewinne_wettbewerb",
				{
					"platz": int(ziel.get("platz", 1)),
					"disziplin":
					I18nService.t("rquest.disziplin.%s" % str(ziel.get("disziplin", "")))
				}
			)
		_:
			return I18nService.t("rquest.ziel.warte_bis")
