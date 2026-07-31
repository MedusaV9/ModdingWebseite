class_name BeifahrerUi
extends CanvasLayer
## Beifahrer-UI der Coop-Fahrt (W13B COUCH-COOP, Doc C §3.6): Einladungs-
## Karte („{name} will mit dir durch die Stadt düsen!“) und das Beifahrer-
## Radio — Sender-Knöpfe + Skip, aber NUR wenn der GASTGEBER das Radio
## besitzt (Gate reist mit der Einladung; RadioLogic bleibt read-only).
## Ohne Gastgeber-Radio gibt es statt Reglern den knuffigen Kaufhinweis.
## Verlassen/Disconnect: die UI verschwindet über fahrt_beendet — der
## Fahrer fährt einfach weiter.
##
## Selbstverdrahtend über setup(coop): Einladung → Karte, Beifahrer-Start →
## Radio-Panel, Ende → weg. Knoten-Namen sind stabil (Tests): Einladung,
## Mitfahren, Ablehnen, RadioPanel, Sender_<id>, Skip, Kaufhinweis,
## Aussteigen.

const PANEL_BREITE := 300.0

var coop: CoopDrive = null

var _einladung: PanelContainer = null
var _einladung_text: Label = null
var _panel: PanelContainer = null
var _titel: Label = null
var _radio_box: VBoxContainer = null


func setup(session: CoopDrive) -> void:
	coop = session
	coop.einladung_erhalten.connect(_on_einladung)
	coop.fahrt_gestartet.connect(_on_fahrt_gestartet)
	coop.fahrt_beendet.connect(func(_grund: String) -> void: verstecke())
	layer = 8
	_baue_einladung()
	_baue_panel()
	verstecke()


## Einladungs-Karte zeigen (Gast).
func zeige_einladung(von: String) -> void:
	_einladung_text.text = I18nService.t("coop.fahrt.einladung", {"name": von})
	_einladung.visible = true


## Beifahrer-Panel zeigen: Radio-Regler nur mit Gastgeber-Radio, sonst
## Kaufhinweis (Testfall „Kaufhinweis statt Regler“).
func zeige_beifahrer(radio_owned: bool, von: String) -> void:
	_einladung.visible = false
	_titel.text = I18nService.t("coop.fahrt.titel", {"name": von})
	for kind in _radio_box.get_children():
		kind.queue_free()
	if radio_owned:
		_baue_radio_regler()
	else:
		var hinweis := Label.new()
		hinweis.name = "Kaufhinweis"
		hinweis.text = I18nService.t("coop.radio.kaufhinweis")
		hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hinweis.custom_minimum_size = Vector2(PANEL_BREITE - 40.0, 0.0)
		_radio_box.add_child(hinweis)
	_panel.visible = true


func verstecke() -> void:
	if _einladung != null:
		_einladung.visible = false
	if _panel != null:
		_panel.visible = false


func ist_sichtbar() -> bool:
	return (_einladung != null and _einladung.visible) or (_panel != null and _panel.visible)


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _baue_einladung() -> void:
	_einladung = PanelContainer.new()
	_einladung.name = "Einladung"
	_einladung.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_einladung)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_einladung.add_child(box)
	_einladung_text = Label.new()
	_einladung_text.name = "EinladungText"
	_einladung_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_einladung_text.custom_minimum_size = Vector2(PANEL_BREITE, 0.0)
	box.add_child(_einladung_text)
	var reihe := HBoxContainer.new()
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 12)
	box.add_child(reihe)
	var ja := Button.new()
	ja.name = "Mitfahren"
	ja.text = I18nService.t("coop.fahrt.mitfahren")
	ja.pressed.connect(_on_mitfahren)
	reihe.add_child(ja)
	var nein := Button.new()
	nein.name = "Ablehnen"
	nein.text = I18nService.t("coop.fahrt.ablehnen")
	nein.pressed.connect(_on_ablehnen)
	reihe.add_child(nein)


func _baue_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "RadioPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.offset_left = -PANEL_BREITE - 16.0
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_titel = Label.new()
	_titel.name = "Titel"
	_titel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_titel.custom_minimum_size = Vector2(PANEL_BREITE - 40.0, 0.0)
	box.add_child(_titel)
	_radio_box = VBoxContainer.new()
	_radio_box.name = "RadioBox"
	_radio_box.add_theme_constant_override("separation", 6)
	box.add_child(_radio_box)
	var raus := Button.new()
	raus.name = "Aussteigen"
	raus.text = I18nService.t("coop.fahrt.aussteigen")
	raus.pressed.connect(_on_aussteigen)
	box.add_child(raus)


## Sender-Knöpfe aus der MusicRegistry (read-only; Namen über RadioLogic).
func _baue_radio_regler() -> void:
	var kopf := Label.new()
	kopf.name = "RadioTitel"
	kopf.text = I18nService.t("coop.radio.titel")
	_radio_box.add_child(kopf)
	for station: Dictionary in MusicRegistry.stations():
		var id := str(station.get("id", ""))
		if id.is_empty():
			continue
		var knopf := Button.new()
		knopf.name = "Sender_%s" % id
		knopf.text = RadioLogic.sender_name(station)
		knopf.pressed.connect(func() -> void: coop.radio_sender(id))
		_radio_box.add_child(knopf)
	var skip := Button.new()
	skip.name = "Skip"
	skip.text = I18nService.t("coop.radio.skip")
	skip.pressed.connect(func() -> void: coop.radio_skip())
	_radio_box.add_child(skip)


# ── Verdrahtung ──────────────────────────────────────────────────────────────


func _on_einladung(data: Dictionary) -> void:
	zeige_einladung(str(data.get("von", "?")))


func _on_fahrt_gestartet(rolle: String) -> void:
	if rolle == CoopDrive.ROLLE_BEIFAHRER:
		zeige_beifahrer(coop.host_radio_owned, coop.von_name)


func _on_mitfahren() -> void:
	_einladung.visible = false
	await coop.beitreten()


func _on_ablehnen() -> void:
	coop.ablehnen()
	verstecke()


func _on_aussteigen() -> void:
	coop.verlasse_fahrt()
