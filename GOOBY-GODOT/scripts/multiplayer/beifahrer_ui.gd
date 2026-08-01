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
## G4/P16 (ui-reisen HOCH 3 + g2 F14a): das RadioPanel klebt nicht mehr an
## der rechten Kante, sondern sitzt als BODENZENTRIERTE Karte in der
## Safe-Area (Daumenzone); beide Karten tragen das AC-Theme (CanvasLayer
## propagiert das Window-Theme nicht), alle Knöpfe sind SquishButtons mit
## Theme-Variation + Touch-Floor und klingen nach Grammatik (Mitfahren
## ui_confirm · Ablehnen/Aussteigen ui_back · Sender ui_chip · Skip
## ui_click). Rotation zieht das Layout über size_changed nach.
##
## Selbstverdrahtend über setup(coop): Einladung → Karte, Beifahrer-Start →
## Radio-Panel, Ende → weg. Knoten-Namen sind stabil (Tests): Einladung,
## Mitfahren, Ablehnen, RadioPanel, Sender_<id>, Skip, Kaufhinweis,
## Aussteigen.

## Wunschbreiten in Design-px (klemmen an die Safe-Area).
const PANEL_BREITE := 360.0
const EINLADUNG_BREITE := 320.0
## Mindesthöhe der Knöpfe in Design-px (zusätzlich zum Touch-Floor).
const KNOPF_HOEHE := 48.0

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
	# setup() läuft je nach Aufrufer VOR oder NACH add_child — wenn wir
	# schon im Tree hängen, sofort layouten (sonst übernimmt _ready).
	if is_inside_tree():
		_relayout()


func _ready() -> void:
	get_viewport().size_changed.connect(_relayout)
	_relayout()


## Einladungs-Karte zeigen (Gast).
func zeige_einladung(von: String) -> void:
	_einladung_text.text = I18nService.t("coop.fahrt.einladung", {"name": von})
	_einladung.visible = true
	_relayout()


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
		hinweis.custom_minimum_size = Vector2(_inhalt_breite(), 0.0)
		_radio_box.add_child(hinweis)
	_panel.visible = true
	_relayout()


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
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	_einladung.theme = ThemeService.theme()
	_einladung.theme_type_variation = &"AcCard"
	_einladung.set_anchors_preset(Control.PRESET_CENTER)
	_einladung.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_einladung.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_einladung)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_einladung.add_child(box)
	_einladung_text = Label.new()
	_einladung_text.name = "EinladungText"
	_einladung_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_einladung_text.custom_minimum_size = Vector2(EINLADUNG_BREITE, 0.0)
	box.add_child(_einladung_text)
	var reihe := HBoxContainer.new()
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 12)
	box.add_child(reihe)
	var ja := _knopf("Mitfahren", I18nService.t("coop.fahrt.mitfahren"), "PrimaryButton")
	ja.pressed.connect(_on_mitfahren)
	reihe.add_child(ja)
	var nein := _knopf("Ablehnen", I18nService.t("coop.fahrt.ablehnen"), "GhostButton")
	nein.pressed.connect(_on_ablehnen)
	reihe.add_child(nein)


func _baue_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "RadioPanel"
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	_panel.theme = ThemeService.theme()
	_panel.theme_type_variation = &"AcCard"
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_titel = Label.new()
	_titel.name = "Titel"
	_titel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_titel.custom_minimum_size = Vector2(PANEL_BREITE - 48.0, 0.0)
	box.add_child(_titel)
	_radio_box = VBoxContainer.new()
	_radio_box.name = "RadioBox"
	_radio_box.add_theme_constant_override("separation", 6)
	box.add_child(_radio_box)
	var raus := _knopf("Aussteigen", I18nService.t("coop.fahrt.aussteigen"), "GhostButton")
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
		var knopf := _knopf("Sender_%s" % id, RadioLogic.sender_name(station), "AccentButton")
		knopf.pressed.connect(_on_sender.bind(id))
		_radio_box.add_child(knopf)
	var skip := _knopf("Skip", I18nService.t("coop.radio.skip"), "AccentButton")
	skip.pressed.connect(_on_skip)
	_radio_box.add_child(skip)


## SquishButton im AC-Look (F14a): Theme-Variation + 48·f-Mindesthöhe;
## den physischen Touch-Floor klemmt _relayout (Metrics erst im Tree).
func _knopf(knoten_name: String, text: String, variation: String) -> SquishButton:
	var btn := SquishButton.new()
	btn.name = knoten_name
	btn.theme_type_variation = variation
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0.0, KNOPF_HOEHE)
	return btn


## Innenbreite der Radio-Karte (für autowrap-Labels).
func _inhalt_breite() -> float:
	if not is_inside_tree():
		return PANEL_BREITE - 48.0
	var m := ScreenShell.metrics(get_viewport())
	return ScreenShell.card_width(m, PANEL_BREITE) - 48.0


# ── Layout ───────────────────────────────────────────────────────────────────


## G4/P16: Einladung mittig, RadioPanel bodenzentriert ÜBER dem
## Home-Indicator (Safe-Area), Breiten gedeckelt, Knöpfe ≥ Touch-Floor.
func _relayout() -> void:
	if not is_inside_tree() or _panel == null:
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var panel_breite := ScreenShell.card_width(m, PANEL_BREITE)
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -panel_breite / 2.0
	_panel.offset_right = panel_breite / 2.0
	_panel.offset_bottom = -(float(insets["bottom"]) + 16.0 * f)
	_panel.offset_top = _panel.offset_bottom
	if _titel != null:
		_titel.custom_minimum_size = Vector2(panel_breite - 48.0, 0.0)
	if _einladung_text != null:
		var einladung_breite := ScreenShell.card_width(m, EINLADUNG_BREITE)
		_einladung_text.custom_minimum_size = Vector2(einladung_breite, 0.0)
	for wurzel: Control in [_einladung, _panel]:
		if wurzel == null:
			continue
		for knopf in wurzel.find_children("*", "Button", true, false):
			var ctl := knopf as Control
			ctl.custom_minimum_size = ctl.custom_minimum_size.max(
				Vector2(0.0, roundf(KNOPF_HOEHE * f))
			)
			ScreenShell.touch_target(ctl, m)
		ScreenShell.scale_fonts(wurzel, f)


# ── Verdrahtung ──────────────────────────────────────────────────────────────


func _on_einladung(data: Dictionary) -> void:
	zeige_einladung(str(data.get("von", "?")))


func _on_fahrt_gestartet(rolle: String) -> void:
	if rolle == CoopDrive.ROLLE_BEIFAHRER:
		zeige_beifahrer(coop.host_radio_owned, coop.von_name)


func _on_mitfahren() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	_einladung.visible = false
	await coop.beitreten()


func _on_ablehnen() -> void:
	AudioDirector.try_play(self, "ui_back")
	coop.ablehnen()
	verstecke()


func _on_sender(id: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	coop.radio_sender(id)


func _on_skip() -> void:
	AudioDirector.try_play(self, "ui_click")
	coop.radio_skip()


func _on_aussteigen() -> void:
	AudioDirector.try_play(self, "ui_back")
	coop.verlasse_fahrt()
